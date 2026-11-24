-- praktik.sql : Praktik Modul 6, disalin langsung dari modul (tanpa perubahan isi query).
-- Prasyarat: seed.sql Modul 5 sudah dijalankan. Jalankan:
--   docker exec -i pg-latihan psql -U postgres -d toko -f - < praktik.sql

\echo '=== INNER dan LEFT JOIN ==='
SET search_path TO app, public;

-- INNER vs LEFT JOIN
SELECT c.nama, p.id, p.status
FROM pelanggan c JOIN pesanan p ON p.pelanggan_id = c.id;

SELECT c.nama, count(p.id) AS jumlah_pesanan
FROM pelanggan c LEFT JOIN pesanan p ON p.pelanggan_id = c.id
GROUP BY c.id, c.nama ORDER BY jumlah_pesanan DESC;

\echo '=== JOIN Beberapa Tabel ==='
-- JOIN 4 tabel: detail pesanan
SELECT p.id AS pesanan, c.nama AS pelanggan, pr.nama AS produk,
       i.jumlah, i.jumlah * i.harga_satuan AS subtotal
FROM pesanan p
JOIN pelanggan c    ON c.id = p.pelanggan_id
JOIN item_pesanan i ON i.pesanan_id = p.id
JOIN produk pr      ON pr.id = i.produk_id
ORDER BY p.id;

\echo '=== Grouping dan Agregasi ==='
-- Grouping + HAVING + FILTER
SELECT status, count(*) FROM pesanan GROUP BY status HAVING count(*) >= 1;
SELECT count(*) AS total, count(*) FILTER (WHERE status='selesai') AS selesai FROM pesanan;

-- ROLLUP: subtotal dan grand total
SELECT c.nama, p.status, count(*)
FROM pesanan p JOIN pelanggan c ON c.id = p.pelanggan_id
GROUP BY ROLLUP (c.nama, p.status);

\echo '=== Subquery ==='
-- Subquery
SELECT nama, harga FROM produk WHERE harga > (SELECT avg(harga) FROM produk);
SELECT nama FROM produk pr
WHERE NOT EXISTS (SELECT 1 FROM item_pesanan i WHERE i.produk_id = pr.id);   -- belum pernah dipesan

\echo '=== CTE ==='
-- CTE
WITH total_pesanan AS (
  SELECT pesanan_id, sum(jumlah * harga_satuan) AS total FROM item_pesanan GROUP BY pesanan_id
)
SELECT c.nama, sum(t.total) AS total_belanja
FROM total_pesanan t
JOIN pesanan p ON p.id = t.pesanan_id
JOIN pelanggan c ON c.id = p.pelanggan_id
GROUP BY c.nama ORDER BY total_belanja DESC;

\echo '=== LATERAL Join ==='
-- LATERAL: pesanan terbaru per pelanggan
SELECT c.nama, x.id, x.dibuat_pada
FROM pelanggan c
LEFT JOIN LATERAL (
  SELECT id, dibuat_pada FROM pesanan p WHERE p.pelanggan_id = c.id
  ORDER BY dibuat_pada DESC LIMIT 1
) x ON true;

\echo '=== Set Operations ==='
-- Set operations
SELECT nama FROM pelanggan WHERE email LIKE '%@contoh.com'
UNION ALL
SELECT nama FROM produk WHERE harga > 1000000;

SELECT id FROM produk
EXCEPT
SELECT produk_id FROM item_pesanan;
