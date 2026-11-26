-- latihan.sql : Latihan 1-7 Modul 9 (Latihan 5 sebagian query, Latihan 6 diskusi + korelasi).
-- Prasyarat: praktik.sql sudah dijalankan (tabel app.transaksi 1 juta baris).
-- Jalankan: docker exec -i pg-latihan psql -U postgres -d toko -f - < latihan.sql
-- Untuk pengukuran yang adil, setiap latihan memakai SALINAN tabel sendiri (trx_a, trx_b, ...),
-- sehingga tidak terpengaruh index yang sudah dibuat di Praktik.
-- Waktu yang tercetak bergantung mesin dan cache; ulangi 2-3 kali dan ambil yang stabil.
-- Baris berlabel "DISENGAJA ERROR" memang diharapkan gagal.
-- Setelah selesai: ./jalankan.sh salinan (hapus salinan uji, TETAPKAN tabel transaksi untuk Modul 10).

SET search_path TO app, public;
\timing off

-- Fungsi bantu pengukuran ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION uji_baca(p_tabel regclass, p_n int) RETURNS numeric
LANGUAGE plpgsql AS $$
DECLARE
    t0    timestamptz := clock_timestamp();
    i     int;
    dummy numeric;
BEGIN
    FOR i IN 1..p_n LOOP
        EXECUTE format('SELECT sum(total) FROM %s WHERE pelanggan_id = $1', p_tabel)
            INTO dummy USING (i * 37) % 10000 + 1;
    END LOOP;
    RETURN extract(epoch FROM clock_timestamp() - t0) * 1000 / p_n;    -- ms per query
END; $$;

CREATE OR REPLACE FUNCTION uji_insert(p_tabel regclass, p_baris int) RETURNS numeric
LANGUAGE plpgsql AS $$
DECLARE
    t0 timestamptz := clock_timestamp();
BEGIN
    EXECUTE format($f$INSERT INTO %s
        SELECT g, (random()*10000)::int + 1, 'baru', (random()*1000000)::numeric(12,0),
               now(), 'x' || g || '@contoh.com'
        FROM generate_series(1, %s) g$f$, p_tabel, p_baris);
    RETURN extract(epoch FROM clock_timestamp() - t0) * 1000;          -- ms total
END; $$;

-- =====================================================================
\echo '=== LATIHAN 1a: waktu baca sebelum vs sesudah index ==='
DROP TABLE IF EXISTS trx_a, trx_b;
CREATE TABLE trx_a AS TABLE transaksi;                 -- tanpa index
CREATE TABLE trx_b AS TABLE transaksi;                 -- akan diberi index
CREATE INDEX idx_trx_b_pelanggan ON trx_b (pelanggan_id);
ANALYZE trx_a;
ANALYZE trx_b;

SELECT uji_baca('trx_a', 20) AS tanpa \gset
SELECT uji_baca('trx_b', 20) AS dengan \gset
SELECT round(:tanpa, 3) AS ms_per_query_tanpa_index,
       round(:dengan, 3) AS ms_per_query_dengan_index,
       round(:tanpa / NULLIF(:dengan, 0), 1) AS kali_lebih_cepat;

\echo '--- rencana eksekusi dengan waktu sebenarnya'
EXPLAIN (ANALYZE, COSTS OFF) SELECT * FROM trx_a WHERE pelanggan_id = 4242;
EXPLAIN (ANALYZE, COSTS OFF) SELECT * FROM trx_b WHERE pelanggan_id = 4242;

\echo '=== LATIHAN 1b: harga yang dibayar saat INSERT 100.000 baris ==='
DROP TABLE IF EXISTS trx_ins_a, trx_ins_b;
CREATE TABLE trx_ins_a (LIKE transaksi);                       -- tanpa index
CREATE TABLE trx_ins_b (LIKE transaksi);                       -- dengan index
CREATE INDEX idx_trx_ins_b ON trx_ins_b (pelanggan_id);

SELECT uji_insert('trx_ins_a', 100000) AS tanpa \gset
SELECT uji_insert('trx_ins_b', 100000) AS dengan \gset
SELECT round(:tanpa) AS ms_insert_tanpa_index,
       round(:dengan) AS ms_insert_dengan_index,
       round(:dengan / NULLIF(:tanpa, 0), 2) AS kali_lebih_lambat;

-- =====================================================================
\echo '=== LATIHAN 2: urutan kolom pada index komposit ==='
DROP TABLE IF EXISTS trx_c, trx_d;
CREATE TABLE trx_c AS SELECT * FROM transaksi WHERE id <= 200000;
CREATE TABLE trx_d AS SELECT * FROM transaksi WHERE id <= 200000;
CREATE INDEX idx_c ON trx_c (pelanggan_id, dibuat_pada DESC);     -- urutan yang benar
CREATE INDEX idx_d ON trx_d (dibuat_pada, pelanggan_id);          -- urutan terbalik
ANALYZE trx_c;
ANALYZE trx_d;

\echo '--- (pelanggan_id, dibuat_pada DESC): tidak ada node Sort'
EXPLAIN (ANALYZE, COSTS OFF)
SELECT * FROM trx_c WHERE pelanggan_id = 5 ORDER BY dibuat_pada DESC LIMIT 10;
\echo '--- (dibuat_pada, pelanggan_id): lihat apakah ada Sort, atau scan index yang menyaring banyak baris'
EXPLAIN (ANALYZE, COSTS OFF)
SELECT * FROM trx_d WHERE pelanggan_id = 5 ORDER BY dibuat_pada DESC LIMIT 10;

-- =====================================================================
\echo '=== LATIHAN 3: partial index vs index penuh ("belum dibayar" = status baru) ==='
CREATE INDEX IF NOT EXISTS idx_trx_baru ON transaksi (dibuat_pada) WHERE status = 'baru';
CREATE INDEX idx_trx_waktu_penuh ON transaksi (dibuat_pada);

SELECT count(*) FILTER (WHERE status = 'baru') AS baris_baru,
       count(*) AS total_baris,
       round(100.0 * count(*) FILTER (WHERE status = 'baru') / count(*), 1) AS persen_baru
FROM transaksi;

SELECT indexrelname, pg_size_pretty(pg_relation_size(indexrelid)) AS ukuran
FROM pg_stat_user_indexes
WHERE indexrelname IN ('idx_trx_baru', 'idx_trx_waktu_penuh')
ORDER BY pg_relation_size(indexrelid);

\echo '--- partial index dipakai bila WHERE query mengimplikasikan predikat index'
EXPLAIN SELECT * FROM transaksi WHERE status = 'baru' AND dibuat_pada > now() - interval '7 days';
\echo '--- status lain TIDAK bisa memakai partial index'
EXPLAIN SELECT * FROM transaksi WHERE status = 'selesai' AND dibuat_pada > now() - interval '7 days';
DROP INDEX idx_trx_waktu_penuh;

-- =====================================================================
\echo '=== LATIHAN 4: lower(email) dan expression index ==='
DROP TABLE IF EXISTS trx_email;
CREATE TABLE trx_email AS SELECT id, email FROM trx_c;
CREATE INDEX idx_email_biasa ON trx_email (email);
ANALYZE trx_email;

\echo '--- index biasa pada email TIDAK dipakai oleh lower(email): Seq Scan'
EXPLAIN SELECT * FROM trx_email WHERE lower(email) = 'user500@contoh.com';
CREATE INDEX idx_email_lower ON trx_email (lower(email));
ANALYZE trx_email;
\echo '--- setelah expression index: Index/Bitmap Scan using idx_email_lower'
EXPLAIN SELECT * FROM trx_email WHERE lower(email) = 'user500@contoh.com';

\echo '--- tambahan: LIKE awalan butuh text_pattern_ops bila database tidak ber-collation C'
SELECT datcollate AS collation_database FROM pg_database WHERE datname = current_database();
EXPLAIN SELECT * FROM trx_email WHERE email LIKE 'user500%';
CREATE INDEX idx_email_pattern ON trx_email (email text_pattern_ops);
ANALYZE trx_email;
EXPLAIN SELECT * FROM trx_email WHERE email LIKE 'user500%';

-- =====================================================================
\echo '=== LATIHAN 5: index yang tidak pernah dipakai ==='
SELECT stats_reset FROM pg_stat_database WHERE datname = current_database();

SELECT ui.schemaname, ui.relname, ui.indexrelname, ui.idx_scan,
       pg_size_pretty(pg_relation_size(ui.indexrelid)) AS ukuran,
       i.indisunique AS unik, i.indisprimary AS pk
FROM pg_stat_user_indexes ui
JOIN pg_index i ON i.indexrelid = ui.indexrelid
WHERE ui.idx_scan = 0
ORDER BY pg_relation_size(ui.indexrelid) DESC;

-- Kandidat yang aman dipertimbangkan: bukan PK/UNIQUE (tidak menegakkan constraint)
SELECT ui.relname, ui.indexrelname, pg_get_indexdef(ui.indexrelid) AS definisi
FROM pg_stat_user_indexes ui
JOIN pg_index i ON i.indexrelid = ui.indexrelid
WHERE ui.idx_scan = 0 AND NOT i.indisunique AND NOT i.indisprimary;

-- =====================================================================
\echo '=== LATIHAN 6: syarat BRIN = korelasi fisik ==='
CREATE INDEX IF NOT EXISTS idx_trx_brin ON transaksi USING brin (id);
CREATE INDEX idx_trx_brin_waktu ON transaksi USING brin (dibuat_pada);
ANALYZE transaksi;

SELECT attname, round(correlation::numeric, 3) AS korelasi
FROM pg_stats
WHERE schemaname = 'app' AND tablename = 'transaksi' AND attname IN ('id', 'dibuat_pada', 'pelanggan_id')
ORDER BY attname;

SELECT indexrelname, pg_size_pretty(pg_relation_size(indexrelid)) AS ukuran
FROM pg_stat_user_indexes
WHERE indexrelname IN ('idx_trx_brin', 'idx_trx_brin_waktu', 'idx_trx_pelanggan');

\echo '--- kolom berkorelasi (id): rentang sempit, BRIN efektif'
EXPLAIN (ANALYZE, COSTS OFF) SELECT * FROM transaksi WHERE id BETWEEN 500000 AND 500100;
\echo '--- kolom acak (dibuat_pada): BRIN nyaris tak membantu (banyak blok harus dibaca)'
EXPLAIN (ANALYZE, COSTS OFF)
SELECT * FROM transaksi WHERE dibuat_pada BETWEEN now() - interval '2 days' AND now() - interval '1 day';

-- =====================================================================
\echo '=== LATIHAN 7: hash vs B-Tree pada teks panjang (200 karakter) ==='
DROP TABLE IF EXISTS teks_panjang;
CREATE TABLE teks_panjang AS
SELECT g AS id,
       substr(md5(random()::text) || md5(random()::text) || md5(random()::text) || md5(random()::text)
              || md5(random()::text) || md5(random()::text) || md5(random()::text), 1, 200) AS isi
FROM generate_series(1, 300000) g;
CREATE INDEX idx_tp_hash  ON teks_panjang USING hash (isi);
CREATE INDEX idx_tp_btree ON teks_panjang (isi);
ANALYZE teks_panjang;

SELECT min(length(isi)) AS panjang_min, max(length(isi)) AS panjang_maks FROM teks_panjang;
SELECT indexrelname, pg_size_pretty(pg_relation_size(indexrelid)) AS ukuran
FROM pg_stat_user_indexes WHERE indexrelname IN ('idx_tp_hash', 'idx_tp_btree') ORDER BY indexrelname;
SELECT pg_size_pretty(pg_relation_size('teks_panjang')) AS ukuran_tabel;

\echo '--- yang tidak bisa dilakukan hash index'
\echo '--- DISENGAJA ERROR: UNIQUE'
CREATE UNIQUE INDEX idx_tp_hash_unik ON teks_panjang USING hash (isi);
\echo '--- DISENGAJA ERROR: multikolom'
CREATE INDEX idx_tp_hash_multi ON teks_panjang USING hash (id, isi);

\echo '--- kesamaan: hash dan B-Tree sama-sama bisa (contoh nilai diambil dari id 1234)'
SELECT isi AS contoh FROM teks_panjang WHERE id = 1234 \gset
EXPLAIN (ANALYZE, COSTS OFF) SELECT id FROM teks_panjang WHERE isi = :'contoh';
DROP INDEX idx_tp_btree;
\echo '--- tanpa B-Tree, hanya hash yang melayani kesamaan'
EXPLAIN (ANALYZE, COSTS OFF) SELECT id FROM teks_panjang WHERE isi = :'contoh';
\echo '--- ORDER BY tidak bisa dilayani hash (Sort atau Seq Scan)'
EXPLAIN (COSTS OFF) SELECT id FROM teks_panjang ORDER BY isi LIMIT 5;
