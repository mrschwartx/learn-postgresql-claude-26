-- praktik.sql : Praktik Modul 4, disalin langsung dari modul.
-- Jalankan (setelah reset.sql bila mengulang):
--   docker exec -i pg-latihan psql -U postgres -d toko -f - < praktik.sql
-- Satu ERROR di bawah ini DISENGAJA (INSERT harga -5). Error lain berarti ada masalah.

\echo '=== Membuat Schema dan Tabel ==='
CREATE SCHEMA IF NOT EXISTS app;
SET search_path TO app, public;

CREATE TABLE pelanggan (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nama        text        NOT NULL,
    email       text        NOT NULL UNIQUE,
    dibuat_pada timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE produk (
    id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sku    text          NOT NULL UNIQUE,
    nama   text          NOT NULL,
    harga  numeric(12,2) NOT NULL CHECK (harga >= 0),
    stok   integer       NOT NULL DEFAULT 0 CHECK (stok >= 0)
);

CREATE TABLE pesanan (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    pelanggan_id bigint NOT NULL REFERENCES pelanggan(id),
    status       text   NOT NULL DEFAULT 'baru'
                 CHECK (status IN ('baru','dibayar','dikirim','selesai','batal')),
    dibuat_pada  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE item_pesanan (
    pesanan_id bigint  NOT NULL REFERENCES pesanan(id) ON DELETE CASCADE,
    produk_id  bigint  NOT NULL REFERENCES produk(id),
    jumlah     integer NOT NULL CHECK (jumlah > 0),
    harga_satuan numeric(12,2) NOT NULL,
    PRIMARY KEY (pesanan_id, produk_id)
);

\dt app.*
\d app.pesanan

\echo '=== Menguji Constraint dan Transactional DDL ==='
-- constraint menolak data tidak valid
INSERT INTO produk (sku, nama, harga, stok) VALUES ('X-1', 'Uji', -5, 0);
-- ERROR: violates check constraint

-- DDL transaksional
BEGIN;
ALTER TABLE produk ADD COLUMN kategori text;
\d produk
ROLLBACK;
\d produk          -- kolom 'kategori' hilang lagi

-- ubah struktur permanen
ALTER TABLE produk ADD COLUMN kategori text NOT NULL DEFAULT 'umum';
ALTER TABLE pelanggan ADD COLUMN telepon text;
COMMENT ON TABLE produk IS 'Katalog produk toko';

-- perangkap floating point
SELECT 0.1::double precision + 0.2::double precision = 0.3 AS float_sama,
       0.1::numeric + 0.2::numeric = 0.3 AS numeric_sama;

-- enum, array, jsonb, range
CREATE TYPE prioritas AS ENUM ('rendah', 'sedang', 'tinggi');
SELECT 'sedang'::prioritas < 'tinggi'::prioritas;
SELECT ARRAY[1,2,3] @> ARRAY[2];
SELECT '{"warna":"merah","ukuran":"L"}'::jsonb ->> 'warna';
SELECT daterange('2026-01-01','2026-01-10') && daterange('2026-01-05','2026-01-20');

-- view & materialized view
CREATE VIEW v_stok_menipis AS
  SELECT id, nama, stok FROM produk WHERE stok < 10;
CREATE MATERIALIZED VIEW mv_ringkasan_produk AS
  SELECT count(*) AS jumlah_produk, sum(stok) AS total_stok FROM produk;
REFRESH MATERIALIZED VIEW mv_ringkasan_produk;
