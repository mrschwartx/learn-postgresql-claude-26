-- latihan.sql : Latihan 1-6 Modul 6.
-- Prasyarat: seed.sql Modul 5 sudah dijalankan. Jalankan SATU sesi:
--   docker exec -i pg-latihan psql -U postgres -d toko -f - < latihan.sql
-- Data uji (pelanggan Eka, kategori produk, tabel arsip) dibuat di dalam BEGIN ... ROLLBACK
-- sehingga data seed tidak berubah. Konsekuensi: nomor identity yang terpakai tidak kembali.
-- Baris berlabel "DISENGAJA ERROR" memang diharapkan gagal.

SET search_path TO app, public;

-- =====================================================================
\echo '=== LATIHAN 1: total belanja per pelanggan, termasuk yang belum pernah belanja ==='
BEGIN;
INSERT INTO pelanggan (nama, email) VALUES ('Eka', 'eka@contoh.com');   -- belum punya pesanan

SELECT c.id, c.nama,
       COALESCE(sum(i.jumlah * i.harga_satuan), 0) AS total_belanja
FROM pelanggan c
LEFT JOIN pesanan p      ON p.pelanggan_id = c.id
LEFT JOIN item_pesanan i ON i.pesanan_id = p.id
GROUP BY c.id, c.nama
ORDER BY total_belanja DESC, c.id;

\echo '--- jebakan: count(*) vs count(p.id) pada LEFT JOIN'
SELECT c.nama, count(*) AS salah, count(p.id) AS benar
FROM pelanggan c LEFT JOIN pesanan p ON p.pelanggan_id = c.id
GROUP BY c.id, c.nama ORDER BY c.id;
ROLLBACK;

-- =====================================================================
\echo '=== LATIHAN 2: pelanggan yang belum pernah memesan, tiga cara ==='
BEGIN;
INSERT INTO pelanggan (nama, email) VALUES ('Eka', 'eka@contoh.com');

\echo '--- cara 1: LEFT JOIN ... IS NULL'
SELECT c.id, c.nama FROM pelanggan c
LEFT JOIN pesanan p ON p.pelanggan_id = c.id
WHERE p.id IS NULL;

\echo '--- cara 2: NOT EXISTS'
SELECT c.id, c.nama FROM pelanggan c
WHERE NOT EXISTS (SELECT 1 FROM pesanan p WHERE p.pelanggan_id = c.id);

\echo '--- cara 3: NOT IN (aman di sini karena pesanan.pelanggan_id NOT NULL)'
SELECT c.id, c.nama FROM pelanggan c
WHERE c.id NOT IN (SELECT pelanggan_id FROM pesanan);

\echo '--- NOT IN bila subquery menghasilkan satu NULL: hasil KOSONG'
SELECT c.id, c.nama FROM pelanggan c
WHERE c.id NOT IN (SELECT pelanggan_id FROM pesanan UNION ALL SELECT NULL);

\echo '--- NOT EXISTS tidak terpengaruh oleh NULL'
SELECT c.id, c.nama FROM pelanggan c
WHERE NOT EXISTS (SELECT 1 FROM (SELECT pelanggan_id FROM pesanan UNION ALL SELECT NULL) s
                  WHERE s.pelanggan_id = c.id);
ROLLBACK;

-- =====================================================================
\echo '=== LATIHAN 3: LATERAL, 2 produk termahal per kategori ==='
BEGIN;
UPDATE produk SET kategori = CASE sku
    WHEN 'LP-001' THEN 'komputer' WHEN 'MN-001' THEN 'komputer'
    WHEN 'KB-001' THEN 'aksesori' WHEN 'MS-001' THEN 'aksesori'
    ELSE 'audio' END;

SELECT k.kategori, x.nama, x.harga
FROM (SELECT DISTINCT kategori FROM produk) k
CROSS JOIN LATERAL (
    SELECT nama, harga FROM produk p
    WHERE p.kategori = k.kategori
    ORDER BY harga DESC, id        -- id sebagai pemutus seri
    LIMIT 2
) x
ORDER BY k.kategori, x.harga DESC;
ROLLBACK;

-- =====================================================================
\echo '=== LATIHAN 4a: CTE data-modifying, persis seperti diminta ==='
BEGIN;
CREATE TABLE arsip_pesanan (
    LIKE pesanan INCLUDING DEFAULTS,
    diarsipkan_pada timestamptz NOT NULL DEFAULT now()
);

WITH dihapus AS (
    DELETE FROM pesanan WHERE status = 'batal' RETURNING *
)
INSERT INTO arsip_pesanan (id, pelanggan_id, status, dibuat_pada)
SELECT id, pelanggan_id, status, dibuat_pada FROM dihapus;

SELECT id, pelanggan_id, status FROM arsip_pesanan;
SELECT (SELECT count(*) FROM pesanan)      AS pesanan_aktif,
       (SELECT count(*) FROM item_pesanan) AS item_pesanan_tersisa;   -- item pesanan batal ikut terhapus (CASCADE)
ROLLBACK;

\echo '=== LATIHAN 4b: versi yang ikut mengarsipkan item_pesanan ==='
BEGIN;
CREATE TABLE arsip_pesanan (
    LIKE pesanan INCLUDING DEFAULTS,
    diarsipkan_pada timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE arsip_item_pesanan (LIKE item_pesanan INCLUDING DEFAULTS);

-- 1) salin item SEBELUM pesanan dihapus (karena ON DELETE CASCADE akan menghapusnya)
INSERT INTO arsip_item_pesanan
SELECT * FROM item_pesanan
WHERE pesanan_id IN (SELECT id FROM pesanan WHERE status = 'batal');

-- 2) pindahkan pesanan
WITH dihapus AS (
    DELETE FROM pesanan WHERE status = 'batal' RETURNING *
)
INSERT INTO arsip_pesanan (id, pelanggan_id, status, dibuat_pada)
SELECT id, pelanggan_id, status, dibuat_pada FROM dihapus;

SELECT (SELECT count(*) FROM arsip_pesanan)      AS arsip_pesanan,
       (SELECT count(*) FROM arsip_item_pesanan) AS arsip_item,
       (SELECT count(*) FROM pesanan)            AS pesanan_aktif,
       (SELECT count(*) FROM item_pesanan)       AS item_aktif;
ROLLBACK;     -- ganti dengan COMMIT bila ingin benar-benar mengarsipkan

-- =====================================================================
\echo '=== LATIHAN 5: UNION vs UNION ALL ==='
SELECT x FROM (VALUES ('a'), ('b')) t(x)
UNION ALL
SELECT x FROM (VALUES ('b'), ('c')) t(x);        -- 4 baris (b dua kali)

SELECT x FROM (VALUES ('a'), ('b')) t(x)
UNION
SELECT x FROM (VALUES ('b'), ('c')) t(x);        -- 3 baris (b sekali)

\echo '--- rencana eksekusi (perhatikan node penghapus duplikat)'
EXPLAIN SELECT status FROM pesanan UNION     SELECT status FROM pesanan;
EXPLAIN SELECT status FROM pesanan UNION ALL SELECT status FROM pesanan;

-- =====================================================================
\echo '=== LATIHAN 6: GROUP BY dan ketergantungan fungsional ==='
\echo '--- DISENGAJA ERROR: p.status tidak di GROUP BY dan bukan agregat'
SELECT c.id, c.nama, p.status, count(*)
FROM pelanggan c JOIN pesanan p ON p.pelanggan_id = c.id
GROUP BY c.id;

\echo '--- BERHASIL: c.nama bergantung fungsional pada PK c.id (tabel yang sama)'
SELECT c.id, c.nama, count(p.id) AS jumlah_pesanan
FROM pelanggan c LEFT JOIN pesanan p ON p.pelanggan_id = c.id
GROUP BY c.id
ORDER BY c.id;

\echo '--- DISENGAJA ERROR: c.nama berasal dari tabel LAIN daripada PK yang di-GROUP BY (p.id)'
SELECT p.id, c.nama
FROM pesanan p JOIN pelanggan c ON c.id = p.pelanggan_id
GROUP BY p.id;
