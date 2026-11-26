-- praktik.sql : Praktik Modul 11 (bagian SQL), disalin dari modul.
-- Perubahan dari teks modul: path CSV memakai /tmp/produk_full.csv (path di dalam container).
-- Jalankan: docker exec -i pg-latihan psql -U postgres -d toko -f - < praktik.sql
-- Untuk MENGULANG: ./jalankan.sh bersih
-- CATATAN: bagian Keyset Pagination di bawah memakai tabel transaksi yang TIDAK punya index
--          B-Tree pada kolom id (hanya BRIN dari Modul 9). Lihat jawaban: keyset tidak akan
--          tampak lebih cepat tanpa index itu. latihan.sql memakai salinan ber-index.
-- Bagian Partitioning memakai ts dengan zona waktu sesi; hasil hitungan per partisi lihat jawaban.

\echo '=== Partitioning ==='
SET search_path TO app, public;

CREATE TABLE log_aktivitas (
    id bigint GENERATED ALWAYS AS IDENTITY,
    dibuat_pada timestamptz NOT NULL,
    pesan text,
    PRIMARY KEY (id, dibuat_pada)
) PARTITION BY RANGE (dibuat_pada);

CREATE TABLE log_2026_10 PARTITION OF log_aktivitas FOR VALUES FROM ('2026-10-01') TO ('2026-11-01');
CREATE TABLE log_2026_11 PARTITION OF log_aktivitas FOR VALUES FROM ('2026-11-01') TO ('2026-12-01');
CREATE TABLE log_default PARTITION OF log_aktivitas DEFAULT;

INSERT INTO log_aktivitas (dibuat_pada, pesan)
SELECT '2026-10-01'::timestamptz + (g || ' minutes')::interval, 'log ' || g
FROM generate_series(1, 80000) g;

\d+ log_aktivitas
SELECT tableoid::regclass AS partisi, count(*) FROM log_aktivitas GROUP BY 1;

-- Partition pruning: perhatikan hanya satu partisi yang dipindai
EXPLAIN SELECT * FROM log_aktivitas WHERE dibuat_pada >= '2026-11-10' AND dibuat_pada < '2026-11-11';

-- Hapus data lama secara instan
ALTER TABLE log_aktivitas DETACH PARTITION log_2026_10;
DROP TABLE log_2026_10;

\echo '=== Queue dengan SKIP LOCKED ==='
CREATE TABLE antrean (id bigserial PRIMARY KEY, payload text, status text DEFAULT 'menunggu', mulai timestamptz);
INSERT INTO antrean (payload) SELECT 'tugas-' || g FROM generate_series(1, 10) g;

WITH tugas AS (
  SELECT id FROM antrean WHERE status = 'menunggu' ORDER BY id FOR UPDATE SKIP LOCKED LIMIT 1
)
UPDATE antrean a SET status = 'diproses', mulai = now() FROM tugas WHERE a.id = tugas.id RETURNING a.*;

\echo '=== Keyset Pagination vs OFFSET ==='
\timing on
SELECT id FROM transaksi ORDER BY id LIMIT 20 OFFSET 900000;
SELECT id FROM transaksi WHERE id > 900000 ORDER BY id LIMIT 20;

\echo '=== Migrasi Aman dan Bulk Load ==='
-- NOT NULL bertahap
ALTER TABLE produk ADD COLUMN merek text;
UPDATE produk SET merek = 'Generik' WHERE merek IS NULL;
ALTER TABLE produk ADD CONSTRAINT merek_wajib CHECK (merek IS NOT NULL) NOT VALID;
ALTER TABLE produk VALIDATE CONSTRAINT merek_wajib;

-- Agar DDL tidak memblokir antrean lock
SET lock_timeout = '3s';
CREATE INDEX CONCURRENTLY idx_produk_merek ON produk (merek);

-- Bulk load: COPY vs INSERT per baris
CREATE UNLOGGED TABLE staging_produk (LIKE produk INCLUDING ALL);
\copy produk TO '/tmp/produk_full.csv' WITH (FORMAT csv, HEADER true)
\copy staging_produk FROM '/tmp/produk_full.csv' WITH (FORMAT csv, HEADER true)
