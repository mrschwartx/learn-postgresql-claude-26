-- praktik.sql : Praktik Modul 9, disalin langsung dari modul (isi tidak diubah).
-- Prasyarat: database toko + schema app. Untuk MENGULANG: ./jalankan.sh bersih
-- Jalankan: docker exec -i pg-latihan psql -U postgres -d toko -f - < praktik.sql
-- PERINGATAN: membuat tabel 1 juta baris dan beberapa index; butuh beberapa menit dan
-- ratusan MB disk. Data memakai random(): angka, ukuran, dan waktu berbeda tiap dijalankan.

\echo '=== Membuat Data Besar ==='
SET search_path TO app, public;
\timing on

CREATE TABLE transaksi AS
SELECT g AS id,
       (random()*10000)::int + 1 AS pelanggan_id,
       (ARRAY['baru','dibayar','dikirim','selesai','batal'])[(random()*4)::int + 1] AS status,
       (random()*1000000)::numeric(12,0) AS total,
       now() - (random() * interval '365 days') AS dibuat_pada,
       lower('user' || g || '@contoh.com') AS email
FROM generate_series(1, 1000000) g;

ANALYZE transaksi;
SELECT pg_size_pretty(pg_total_relation_size('transaksi'));

\echo '=== Sebelum dan Sesudah Index ==='
EXPLAIN ANALYZE SELECT * FROM transaksi WHERE pelanggan_id = 4242;     -- Seq Scan
CREATE INDEX idx_trx_pelanggan ON transaksi (pelanggan_id);
EXPLAIN ANALYZE SELECT * FROM transaksi WHERE pelanggan_id = 4242;     -- Index/Bitmap Scan
SELECT pg_size_pretty(pg_relation_size('idx_trx_pelanggan'));

\echo '=== Index Komposit, Partial, Expression, Covering ==='
CREATE INDEX idx_trx_pel_waktu ON transaksi (pelanggan_id, dibuat_pada DESC);
EXPLAIN SELECT * FROM transaksi WHERE pelanggan_id = 77 ORDER BY dibuat_pada DESC LIMIT 5;

CREATE INDEX idx_trx_baru ON transaksi (dibuat_pada) WHERE status = 'baru';
EXPLAIN SELECT * FROM transaksi WHERE status = 'baru' AND dibuat_pada > now() - interval '7 days';

EXPLAIN SELECT * FROM transaksi WHERE email = 'user500@contoh.com';       -- Seq Scan
CREATE UNIQUE INDEX idx_trx_email ON transaksi (lower(email));
EXPLAIN SELECT * FROM transaksi WHERE lower(email) = 'user500@contoh.com';

CREATE INDEX idx_trx_cover ON transaksi (pelanggan_id) INCLUDE (total);
VACUUM transaksi;                                                           -- agar visibility map terisi
EXPLAIN ANALYZE SELECT pelanggan_id, total FROM transaksi WHERE pelanggan_id = 100;   -- Index Only Scan

\echo '=== GIN untuk JSONB dan Trigram ==='
CREATE TABLE dokumen (id serial PRIMARY KEY, data jsonb);
INSERT INTO dokumen (data)
SELECT jsonb_build_object('tag', ARRAY['a','b', 'tag' || (g % 50)], 'nilai', g)
FROM generate_series(1, 100000) g;
CREATE INDEX idx_dok_gin ON dokumen USING gin (data jsonb_path_ops);
EXPLAIN ANALYZE SELECT count(*) FROM dokumen WHERE data @> '{"tag": ["tag7"]}';

CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX idx_trx_email_trgm ON transaksi USING gin (email gin_trgm_ops);
EXPLAIN ANALYZE SELECT * FROM transaksi WHERE email LIKE '%er5000%';

\echo '=== BRIN dan Audit Index ==='
CREATE INDEX idx_trx_brin ON transaksi USING brin (id);
SELECT pg_size_pretty(pg_relation_size('idx_trx_brin')) AS brin,
       pg_size_pretty(pg_relation_size('idx_trx_pelanggan')) AS btree;

SELECT relname, indexrelname, idx_scan, pg_size_pretty(pg_relation_size(indexrelid)) AS ukuran
FROM pg_stat_user_indexes ORDER BY idx_scan;

\echo '=== Hash Index ==='
CREATE INDEX idx_trx_email_hash ON transaksi USING hash (email);
CREATE INDEX idx_trx_email_btree ON transaksi (email);

-- Bandingkan ukuran kedua index
SELECT indexrelname, pg_size_pretty(pg_relation_size(indexrelid)) AS ukuran
FROM pg_stat_user_indexes
WHERE indexrelname IN ('idx_trx_email_hash', 'idx_trx_email_btree');

-- Pencarian kesamaan: kedua index bisa dipakai, planner memilih yang lebih murah
EXPLAIN ANALYZE SELECT * FROM transaksi WHERE email = 'user500@contoh.com';

-- Hash index tidak bisa dipakai untuk prefix maupun rentang
EXPLAIN ANALYZE SELECT * FROM transaksi WHERE email LIKE 'user500%';
EXPLAIN ANALYZE SELECT * FROM transaksi WHERE email > 'user9';

-- Paksa planner memakai hash index dengan menghapus B-Tree, lalu ulangi query pertama
DROP INDEX idx_trx_email_btree;
EXPLAIN ANALYZE SELECT * FROM transaksi WHERE email = 'user500@contoh.com';
