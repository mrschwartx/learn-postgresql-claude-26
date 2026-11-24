-- praktik.sql : Query dan Filter, Modifikasi Data, COPY (Modul 5), disalin dari modul.
-- Perubahan dari teks modul: path CSV memakai /tmp/produk.csv (path absolut di dalam container).
-- Prasyarat: seed.sql sudah dijalankan. Jalankan:
--   docker exec -i pg-latihan psql -U postgres -d toko -f - < praktik.sql

SET search_path TO app, public;

\echo '=== Query dan Filter ==='
SELECT * FROM produk;
SELECT nama, harga FROM produk WHERE harga BETWEEN 100000 AND 1000000 ORDER BY harga DESC;
SELECT nama FROM produk WHERE nama ILIKE '%mouse%';
SELECT sku, nama, CASE WHEN stok = 0 THEN 'habis'
                       WHEN stok < 10 THEN 'menipis' ELSE 'aman' END AS status_stok
FROM produk;
SELECT nama, harga * 1.11 AS harga_ppn FROM produk;
SELECT date_trunc('month', dibuat_pada) AS bulan, count(*) FROM pesanan GROUP BY 1;
SELECT * FROM produk ORDER BY harga DESC LIMIT 3 OFFSET 1;

\echo '=== Modifikasi Data ==='
UPDATE produk SET stok = stok - 1 WHERE sku = 'MS-001' RETURNING sku, stok;

INSERT INTO produk (sku, nama, harga, stok) VALUES ('MS-001','Mouse Nirkabel',165000,80)
ON CONFLICT (sku) DO UPDATE SET harga = EXCLUDED.harga, stok = EXCLUDED.stok
RETURNING *;

BEGIN;
DELETE FROM pesanan WHERE status = 'batal';   -- perhatikan jumlah baris
ROLLBACK;                                      -- batalkan jika ragu

\echo '=== Import/Export dengan COPY ==='
\copy (SELECT sku, nama, harga, stok FROM produk) TO '/tmp/produk.csv' WITH (FORMAT csv, HEADER true)
CREATE TEMP TABLE produk_import (LIKE produk INCLUDING DEFAULTS INCLUDING IDENTITY);
\copy produk_import (sku, nama, harga, stok) FROM '/tmp/produk.csv' WITH (FORMAT csv, HEADER true)
SELECT count(*) FROM produk_import;
