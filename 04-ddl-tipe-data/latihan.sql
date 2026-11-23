-- latihan.sql : Latihan 2-5 Modul 4 (Latihan 1 ada di perpustakaan.sql).
-- Prasyarat: praktik.sql sudah dijalankan (schema app + tabel produk).
-- Jalankan: docker exec -i pg-latihan psql -U postgres -d toko -f - < latihan.sql
-- Baris berlabel "DISENGAJA ERROR" memang diharapkan gagal.

CREATE SCHEMA IF NOT EXISTS latihan;
SET search_path TO app, public;

-- =====================================================================
\echo '=== LATIHAN 2a: kolom rating dengan CHECK pada produk ==='
ALTER TABLE produk ADD COLUMN rating numeric(2,1) CHECK (rating BETWEEN 0 AND 5);

\echo '--- DISENGAJA ERROR: rating 5.5 (lolos numeric(2,1), gagal CHECK)'
INSERT INTO produk (sku, nama, harga, rating) VALUES ('R-1', 'Uji rating', 1000, 5.5);
\echo '--- rating NULL dan 4.5 harus BERHASIL (NULL tidak melanggar CHECK)'
BEGIN;
INSERT INTO produk (sku, nama, harga)         VALUES ('R-2', 'Tanpa rating', 1000);
INSERT INTO produk (sku, nama, harga, rating) VALUES ('R-3', 'Rating 4.5',  1000, 4.5);
SELECT sku, rating FROM produk WHERE sku LIKE 'R-%' ORDER BY sku;
ROLLBACK;                     -- data uji tidak disimpan

-- =====================================================================
\echo '=== LATIHAN 2b: NOT NULL tanpa DEFAULT pada tabel berisi data ==='
CREATE TABLE latihan.uji_kolom (id int PRIMARY KEY, nama text);
INSERT INTO latihan.uji_kolom VALUES (1, 'a'), (2, 'b');
CREATE TABLE latihan.uji_kosong (id int PRIMARY KEY);

\echo '--- DISENGAJA ERROR: tabel berisi 2 baris, kolom NOT NULL tanpa DEFAULT'
ALTER TABLE latihan.uji_kolom ADD COLUMN wajib text NOT NULL;
\echo '--- tabel KOSONG: perintah yang sama harus BERHASIL'
ALTER TABLE latihan.uji_kosong ADD COLUMN wajib text NOT NULL;
\echo '--- dengan DEFAULT: BERHASIL, baris lama terisi nilai default'
ALTER TABLE latihan.uji_kolom ADD COLUMN wajib text NOT NULL DEFAULT 'n/a';
SELECT * FROM latihan.uji_kolom ORDER BY id;
\echo '--- cara bertahap: tambah nullable -> isi -> SET NOT NULL'
ALTER TABLE latihan.uji_kolom ADD COLUMN wajib2 text;
UPDATE latihan.uji_kolom SET wajib2 = 'isi' WHERE wajib2 IS NULL;
ALTER TABLE latihan.uji_kolom ALTER COLUMN wajib2 SET NOT NULL;

\echo '--- rewrite tabel? bandingkan relfilenode (berubah = tabel ditulis ulang)'
SELECT pg_relation_filenode('latihan.uji_kolom') AS filenode_awal \gset
ALTER TABLE latihan.uji_kolom ADD COLUMN konstan int NOT NULL DEFAULT 0;
SELECT pg_relation_filenode('latihan.uji_kolom') = :filenode_awal AS tanpa_rewrite_add_default_konstan;
ALTER TABLE latihan.uji_kolom ALTER COLUMN id TYPE bigint;
SELECT pg_relation_filenode('latihan.uji_kolom') = :filenode_awal AS tanpa_rewrite_alter_type;

-- =====================================================================
\echo '=== LATIHAN 3: numeric vs double precision, timestamptz vs timestamp ==='
SELECT 0.1::double precision + 0.2::double precision = 0.3 AS float_sama,
       0.1::numeric + 0.2::numeric = 0.3                  AS numeric_sama;
SELECT sum(0.1::double precision) AS jumlah_float,
       sum(0.1::numeric)          AS jumlah_numeric
FROM generate_series(1, 10);

-- timestamp (tanpa zona) MEMBUANG offset pada input tanpa peringatan:
SELECT '2026-11-23 10:00:00+07'::timestamp = '2026-11-23 10:00:00+00'::timestamp AS dua_waktu_beda_dianggap_sama;

SET timezone = 'Asia/Jakarta';
SELECT '2026-11-23 10:00:00+07'::timestamptz AS timestamptz_di_jakarta,
       '2026-11-23 10:00:00'::timestamp      AS timestamp_di_jakarta;
SET timezone = 'UTC';
SELECT '2026-11-23 10:00:00+07'::timestamptz AS timestamptz_di_utc,
       '2026-11-23 10:00:00'::timestamp      AS timestamp_di_utc;
RESET timezone;

-- =====================================================================
\echo '=== LATIHAN 4: sequence tidak transaksional ==='
CREATE TABLE latihan.uji_seq (
    id   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    isi  text
);
INSERT INTO latihan.uji_seq (isi) VALUES ('pertama')    RETURNING id;
BEGIN;
INSERT INTO latihan.uji_seq (isi) VALUES ('dibatalkan') RETURNING id;
ROLLBACK;
INSERT INTO latihan.uji_seq (isi) VALUES ('ketiga')     RETURNING id;
SELECT * FROM latihan.uji_seq ORDER BY id;

-- =====================================================================
\echo '=== LATIHAN 5: EXCLUDE constraint untuk reservasi ruangan ==='
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE TABLE latihan.reservasi_ruangan (
    id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ruangan text      NOT NULL,
    waktu   tstzrange NOT NULL,
    CONSTRAINT tidak_tumpang_tindih
        EXCLUDE USING gist (ruangan WITH =, waktu WITH &&)
);
\echo '--- ruangan A 09:00-11:00 (BERHASIL)'
INSERT INTO latihan.reservasi_ruangan (ruangan, waktu)
VALUES ('A', tstzrange('2026-11-23 09:00+07', '2026-11-23 11:00+07'));
\echo '--- DISENGAJA ERROR: ruangan A 10:00-12:00 tumpang tindih'
INSERT INTO latihan.reservasi_ruangan (ruangan, waktu)
VALUES ('A', tstzrange('2026-11-23 10:00+07', '2026-11-23 12:00+07'));
\echo '--- ruangan B waktu sama (BERHASIL: ruangan berbeda)'
INSERT INTO latihan.reservasi_ruangan (ruangan, waktu)
VALUES ('B', tstzrange('2026-11-23 10:00+07', '2026-11-23 12:00+07'));
\echo '--- ruangan A 11:00-12:00 (BERHASIL: batas atas default eksklusif, jadi hanya bersentuhan)'
INSERT INTO latihan.reservasi_ruangan (ruangan, waktu)
VALUES ('A', tstzrange('2026-11-23 11:00+07', '2026-11-23 12:00+07'));
SELECT ruangan, waktu FROM latihan.reservasi_ruangan ORDER BY ruangan, waktu;
