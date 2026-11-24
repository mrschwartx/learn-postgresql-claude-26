-- latihan.sql : Latihan 1-5 Modul 5 (Latihan 6 konseptual, lihat jawaban).
-- Prasyarat: seed.sql dan praktik.sql sudah dijalankan. Jalankan SATU sesi:
--   docker exec -i pg-latihan psql -U postgres -d toko -f - < latihan.sql
-- Baris berlabel "DISENGAJA ERROR" memang diharapkan gagal.

SET search_path TO app, public;

-- =====================================================================
\echo '=== LATIHAN 1: stok < 20, urut stok terkecil, label kritis ==='
SELECT sku, nama, stok,
       CASE WHEN stok = 0 THEN 'kritis' ELSE 'rendah' END AS label
FROM produk
WHERE stok < 20
ORDER BY stok ASC;

-- =====================================================================
\echo '=== LATIHAN 2: tambah stok KB-001 sebanyak 10 tanpa membaca stok lama ==='
SELECT sku, stok AS stok_sebelum FROM produk WHERE sku = 'KB-001';
INSERT INTO produk (sku, nama, harga, stok)
VALUES ('KB-001', 'Keyboard Mekanik', 850000, 10)
ON CONFLICT (sku) DO UPDATE
   SET stok = produk.stok + EXCLUDED.stok
RETURNING sku, stok AS stok_sesudah;
-- Catatan: perintah ini TIDAK idempoten. Menjalankannya dua kali menambah 20.
-- Mengembalikan ke nilai semula (opsional, agar data modul berikutnya sama dengan seed):
--   UPDATE produk SET stok = 25 WHERE sku = 'KB-001';

-- =====================================================================
\echo '=== LATIHAN 3: alias tidak bisa dipakai di WHERE ==='
\echo '--- DISENGAJA ERROR: column "h" does not exist'
SELECT harga*1.11 AS h FROM produk WHERE h > 1000000;
\echo '--- Perbaikan 1: ulangi ekspresi'
SELECT harga*1.11 AS h FROM produk WHERE harga*1.11 > 1000000 ORDER BY h;
\echo '--- Perbaikan 2: subquery'
SELECT h FROM (SELECT harga*1.11 AS h FROM produk) AS t WHERE h > 1000000 ORDER BY h;

-- =====================================================================
\echo '=== LATIHAN 4: DELETE ... RETURNING dalam transaksi, cascade, lalu ROLLBACK ==='
SELECT (SELECT count(*) FROM pesanan)      AS pesanan_awal,
       (SELECT count(*) FROM item_pesanan) AS item_awal;
BEGIN;
DELETE FROM pesanan WHERE status = 'batal' RETURNING id;
SELECT (SELECT count(*) FROM pesanan)      AS pesanan_dalam_tx,
       (SELECT count(*) FROM item_pesanan) AS item_dalam_tx;
ROLLBACK;
SELECT (SELECT count(*) FROM pesanan)      AS pesanan_sesudah_rollback,
       (SELECT count(*) FROM item_pesanan) AS item_sesudah_rollback;

-- =====================================================================
\echo '=== LATIHAN 5: ekspor CSV, ubah satu harga di file, impor ke tabel sementara, bandingkan ==='
\copy (SELECT sku, nama, harga, stok FROM produk ORDER BY sku) TO '/tmp/produk.csv' WITH (FORMAT csv, HEADER true)
-- \! menjalankan perintah shell di tempat psql berjalan (di dalam container saat memakai docker exec)
\! sed -i '/^KB-001,/s/,850000.00,/,900000.00,/' /tmp/produk.csv
\! cat /tmp/produk.csv

CREATE TEMP TABLE produk_import (LIKE produk INCLUDING DEFAULTS INCLUDING IDENTITY);
\copy produk_import (sku, nama, harga, stok) FROM '/tmp/produk.csv' WITH (FORMAT csv, HEADER true)

\echo '--- jumlah baris asli vs impor'
SELECT (SELECT count(*) FROM produk) AS asli, (SELECT count(*) FROM produk_import) AS impor;
\echo '--- baris yang berbeda harga (IS DISTINCT FROM aman terhadap NULL)'
SELECT p.sku, p.harga AS harga_asli, i.harga AS harga_csv
FROM produk p JOIN produk_import i USING (sku)
WHERE p.harga IS DISTINCT FROM i.harga;
\echo '--- selisih lengkap semua kolom, dua arah (EXCEPT)'
(SELECT sku, nama, harga, stok FROM produk EXCEPT SELECT sku, nama, harga, stok FROM produk_import)
UNION ALL
(SELECT sku, nama, harga, stok FROM produk_import EXCEPT SELECT sku, nama, harga, stok FROM produk);
