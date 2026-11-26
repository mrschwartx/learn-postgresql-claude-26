-- praktik.sql : Praktik Modul 10, disalin langsung dari modul (isi tidak diubah).
-- Prasyarat: tabel app.transaksi (1 juta baris) dan index Praktik Modul 9 (terutama idx_trx_pelanggan).
-- Jalankan: docker exec -i pg-latihan psql -U postgres -d toko -f - < praktik.sql
--
-- EFEK SAMPING (disengaja oleh modul): bagian "Statistik Planner" menyisipkan 200.000 baris ke
-- app.transaksi (id 2.000.001 dst., pelanggan_id = 1, status 'baru'). Baris itu PERMANEN dan
-- tetap ada untuk Modul 11-16. Praktik tidak dapat diulang tanpa menambah 200.000 baris lagi.
-- Hasil EXPLAIN bergantung mesin, versi PostgreSQL, dan keadaan cache: ulangi bila perlu.

\echo '=== Rencana Sederhana ==='
SET search_path TO app, public;

-- 1) Rencana sederhana
EXPLAIN SELECT * FROM transaksi WHERE pelanggan_id = 4242;
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM transaksi WHERE pelanggan_id = 4242;

\echo '=== Seq Scan vs Index Scan ==='
-- 2) Seq Scan vs Index Scan: ubah selektivitas
EXPLAIN SELECT * FROM transaksi WHERE pelanggan_id < 10;       -- sedikit baris: index
EXPLAIN SELECT * FROM transaksi WHERE pelanggan_id < 9000;     -- banyak baris: Seq Scan

-- 3) Diagnosis: matikan seqscan sementara untuk membandingkan biaya
SET enable_seqscan = off;
EXPLAIN SELECT * FROM transaksi WHERE pelanggan_id < 9000;
RESET enable_seqscan;

\echo '=== Join dan Algoritmanya ==='
-- 4) Join dan algoritmanya
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.nama, count(*), sum(t.total)
FROM transaksi t JOIN pelanggan p ON p.id = t.pelanggan_id
WHERE t.status = 'selesai'
GROUP BY p.nama;

\echo '=== work_mem dan Sort ke Disk ==='
-- 5) work_mem dan sort ke disk
SET work_mem = '64kB';
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM transaksi ORDER BY total DESC LIMIT 100000;   -- 'external merge Disk'
SET work_mem = '256MB';
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM transaksi ORDER BY total DESC LIMIT 100000;   -- 'quicksort Memory'
RESET work_mem;

\echo '=== Statistik Planner ==='
-- 6) Statistik
SELECT attname, n_distinct, most_common_vals, correlation
FROM pg_stats WHERE tablename = 'transaksi' AND attname IN ('status','pelanggan_id');

-- 7) Statistik usang: tambah banyak data tanpa ANALYZE
INSERT INTO transaksi SELECT g+2000000, 1, 'baru', 1, now(), 'x'||g FROM generate_series(1,200000) g;
EXPLAIN SELECT * FROM transaksi WHERE pelanggan_id = 1;    -- estimasi 'rows' jauh dari kenyataan
ANALYZE transaksi;
EXPLAIN SELECT * FROM transaksi WHERE pelanggan_id = 1;    -- estimasi membaik

\echo '=== EXPLAIN ANALYZE yang Aman untuk DML ==='
-- 8) EXPLAIN ANALYZE aman untuk DML
BEGIN;
EXPLAIN ANALYZE UPDATE transaksi SET total = total + 1 WHERE pelanggan_id = 5;
ROLLBACK;

\echo '=== Visualisasi Rencana ==='
-- Format teks: cocok untuk depesz dan Tensor
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM transaksi WHERE pelanggan_id = 4242;

-- Format JSON: cocok untuk PEV2 (explain.dalibo.com)
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) SELECT * FROM transaksi WHERE pelanggan_id = 4242;
