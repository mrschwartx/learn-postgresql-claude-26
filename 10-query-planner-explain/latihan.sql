-- latihan.sql : Latihan 1-4 Modul 10 (Latihan 5 dan 6 konseptual, lihat jawaban).
-- Prasyarat: praktik.sql Modul 9 dan Modul 10 sudah dijalankan (tabel app.transaksi dan idx_trx_pelanggan).
-- Jalankan: docker exec -i pg-latihan psql -U postgres -d toko -f - < latihan.sql
-- Setiap pengaturan planner memakai SET LOCAL di dalam BEGIN ... ROLLBACK, sehingga otomatis
-- kembali normal. Tidak ada angka yang saya tuliskan sebagai "hasil": semuanya harus Anda baca
-- dari keluaran EXPLAIN. Waktu bergantung cache: jalankan query dua kali, ambil yang kedua.
-- Setelah selesai: ./jalankan.sh salinan

SET search_path TO app, public;
\timing off

-- CATATAN PENTING: tabel pelanggan hasil seed Modul 5 hanya berisi 4 baris, sedangkan
-- transaksi.pelanggan_id berkisar 1..10001. Join dengan pelanggan asli hanya cocok untuk
-- pelanggan_id 1..4 (±100 baris per pelanggan) dan terlalu kecil untuk membandingkan algoritma
-- join. Karena itu dibuat pelanggan_uji (10.001 baris) agar setiap baris transaksi punya pasangan.
DROP TABLE IF EXISTS pelanggan_uji;
CREATE TABLE pelanggan_uji AS SELECT g AS id, 'Pelanggan ' || g AS nama FROM generate_series(1, 10001) g;
ALTER TABLE pelanggan_uji ADD PRIMARY KEY (id);
ANALYZE pelanggan_uji;

-- =====================================================================
\echo '=== LATIHAN 1a: join besar, rencana bawaan (catat node join yang dipilih) ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.nama, count(*), sum(t.total)
FROM transaksi t JOIN pelanggan_uji p ON p.id = t.pelanggan_id
WHERE t.status = 'selesai'
GROUP BY p.nama;

\echo '=== LATIHAN 1b: enable_hashjoin = off ==='
BEGIN;
SET LOCAL enable_hashjoin = off;
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.nama, count(*), sum(t.total)
FROM transaksi t JOIN pelanggan_uji p ON p.id = t.pelanggan_id
WHERE t.status = 'selesai'
GROUP BY p.nama;
ROLLBACK;

\echo '=== LATIHAN 1c: enable_hashjoin = off DAN enable_nestloop = off ==='
BEGIN;
SET LOCAL enable_hashjoin = off;
SET LOCAL enable_nestloop = off;
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.nama, count(*), sum(t.total)
FROM transaksi t JOIN pelanggan_uji p ON p.id = t.pelanggan_id
WHERE t.status = 'selesai'
GROUP BY p.nama;
ROLLBACK;

\echo '--- pembanding: join dengan pelanggan ASLI (4 baris) seperti di Praktik'
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.nama, count(*), sum(t.total)
FROM transaksi t JOIN pelanggan p ON p.id = t.pelanggan_id
WHERE t.status = 'selesai'
GROUP BY p.nama;

-- =====================================================================
\echo '=== LATIHAN 2: sort ke disk dan work_mem (hanya untuk transaksi ini) ==='
\echo '--- 2a: ORDER BY ... LIMIT 100000, work_mem 64kB (cari "external merge Disk")'
BEGIN;
SET LOCAL work_mem = '64kB';
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM transaksi ORDER BY total DESC LIMIT 100000;
ROLLBACK;

\echo '--- 2b: sama, work_mem 256MB (cari Sort Method: top-N heapsort atau quicksort)'
BEGIN;
SET LOCAL work_mem = '256MB';
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM transaksi ORDER BY total DESC LIMIT 100000;
ROLLBACK;

\echo '--- 2c: TANPA LIMIT, kolom sempit, work_mem 64kB'
BEGIN;
SET LOCAL work_mem = '64kB';
EXPLAIN (ANALYZE, BUFFERS) SELECT id, total FROM transaksi ORDER BY total DESC;
ROLLBACK;

\echo '--- 2d: TANPA LIMIT, kolom sempit, work_mem 256MB'
BEGIN;
SET LOCAL work_mem = '256MB';
EXPLAIN (ANALYZE, BUFFERS) SELECT id, total FROM transaksi ORDER BY total DESC;
ROLLBACK;

-- =====================================================================
\echo '=== LATIHAN 3: estimasi rows meleset, lalu diperbaiki ==='
DROP TABLE IF EXISTS trx_stat;
-- autovacuum dimatikan HANYA pada tabel uji ini agar ANALYZE otomatis tidak "menolong" saat demo
CREATE TABLE trx_stat (LIKE transaksi) WITH (autovacuum_enabled = off);
INSERT INTO trx_stat SELECT * FROM transaksi WHERE id <= 1000000;
CREATE INDEX idx_stat_pel ON trx_stat (pelanggan_id);
ANALYZE trx_stat;

\echo '--- 3a: statistik segar. Catat rows estimasi vs aktual untuk pelanggan_id = 1'
EXPLAIN (ANALYZE) SELECT * FROM trx_stat WHERE pelanggan_id = 1;

INSERT INTO trx_stat SELECT g + 2000000, 1, 'baru', 1, now(), 'x' || g FROM generate_series(1, 200000) g;

\echo '--- 3b: setelah 200.000 baris baru TANPA ANALYZE. Estimasi rows vs aktual'
EXPLAIN (ANALYZE) SELECT * FROM trx_stat WHERE pelanggan_id = 1;
SELECT relname, n_live_tup, n_mod_since_analyze, last_analyze, last_autoanalyze
FROM pg_stat_user_tables WHERE relname = 'trx_stat';

\echo '--- 3c: setelah ANALYZE'
ANALYZE trx_stat;
EXPLAIN (ANALYZE) SELECT * FROM trx_stat WHERE pelanggan_id = 1;
SELECT n_distinct, most_common_vals::text AS mcv_awal, most_common_freqs::text AS mcv_freqs_awal
FROM pg_stats WHERE tablename = 'trx_stat' AND attname = 'pelanggan_id';

\echo '--- ambang autovacuum ANALYZE untuk tabel 1 juta baris (default): threshold + scale_factor * baris'
SELECT current_setting('autovacuum_analyze_threshold')::int
     + current_setting('autovacuum_analyze_scale_factor')::numeric * 1000000 AS ambang_baris_berubah,
       current_setting('autovacuum_naptime') AS naptime;

-- =====================================================================
\echo '=== LATIHAN 4: mengoptimalkan satu query lambat dengan alur 10.6 ==='
DROP TABLE IF EXISTS trx_opt;
CREATE TABLE trx_opt AS SELECT * FROM transaksi WHERE id <= 1000000;
ANALYZE trx_opt;

\echo '--- Langkah 2-3: UKUR query awal (fungsi/cast pada kolom di WHERE). Catat Execution Time dan node terlambat'
EXPLAIN (ANALYZE, BUFFERS)
SELECT date_trunc('day', dibuat_pada) AS hari, sum(total) AS omzet
FROM trx_opt
WHERE pelanggan_id = 4242 AND status = 'selesai' AND dibuat_pada::date >= current_date - 90
GROUP BY 1 ORDER BY 1;

\echo '--- Langkah 4a: tulis ulang yang SETARA tanpa cast pada kolom (timestamptz >= date: date dibaca tengah malam zona sesi). Tanpa index pendukung waktu tetap'
EXPLAIN (ANALYZE, BUFFERS)
SELECT date_trunc('day', dibuat_pada) AS hari, sum(total) AS omzet
FROM trx_opt
WHERE pelanggan_id = 4242 AND status = 'selesai' AND dibuat_pada >= current_date - 90
GROUP BY 1 ORDER BY 1;

\echo '--- Langkah 4b: index yang sesuai: kesamaan dulu (pelanggan_id, status), rentang terakhir, total sebagai INCLUDE'
CREATE INDEX idx_opt ON trx_opt (pelanggan_id, status, dibuat_pada) INCLUDE (total);
VACUUM (ANALYZE) trx_opt;

\echo '--- Langkah 5: VERIFIKASI. Bandingkan dengan langkah 2-3 (idealnya Index Only Scan, Heap Fetches kecil)'
EXPLAIN (ANALYZE, BUFFERS)
SELECT date_trunc('day', dibuat_pada) AS hari, sum(total) AS omzet
FROM trx_opt
WHERE pelanggan_id = 4242 AND status = 'selesai' AND dibuat_pada >= current_date - 90
GROUP BY 1 ORDER BY 1;

\echo '--- Query awal (dibuat_pada::date) pada index yang sama: dibuat_pada hanya menjadi Filter, bukan Index Cond. Bandingkan barisnya'
EXPLAIN (ANALYZE, BUFFERS)
SELECT date_trunc('day', dibuat_pada) AS hari, sum(total) AS omzet
FROM trx_opt
WHERE pelanggan_id = 4242 AND status = 'selesai' AND dibuat_pada::date >= current_date - 90
GROUP BY 1 ORDER BY 1;
