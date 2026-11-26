-- latihan.sql : Latihan 2 Modul 12 (1 juta baris: UPDATE, VACUUM, VACUUM FULL).
-- (Latihan 1 = sesi_banyak.sh, Latihan 3 = dua_sesi.sh, Latihan 4 = log_lambat.sh,
--  Latihan 5 dan 6 = hitungan/diskusi di jawaban.)
-- Jalankan: docker exec -i pg-latihan psql -U postgres -d toko -f - < latihan.sql
-- Tabel uji ada di schema latihan12. Autovacuum dimatikan HANYA pada tabel ini agar hasilnya tidak
-- berubah di tengah demo. Hapus: ./jalankan.sh bersih

DROP SCHEMA IF EXISTS latihan12 CASCADE;
CREATE SCHEMA latihan12;
SET search_path TO latihan12, public;

\echo '=== LATIHAN 2: pertumbuhan file saat UPDATE, lalu VACUUM dan VACUUM FULL (1 juta baris) ==='
CREATE TABLE uji_bloat WITH (autovacuum_enabled = off) AS
SELECT g AS id, repeat('x', 100) AS isi FROM generate_series(1, 1000000) g;

-- Pembacaan ukuran dibuat satu fungsi agar mudah diulang
CREATE VIEW ukuran AS
SELECT pg_relation_size('uji_bloat') AS byte,
       pg_size_pretty(pg_relation_size('uji_bloat')) AS ukuran,
       pg_relation_size('uji_bloat') / 8192 AS halaman,
       (SELECT n_live_tup FROM pg_stat_user_tables WHERE relname = 'uji_bloat') AS n_live_tup,
       (SELECT n_dead_tup FROM pg_stat_user_tables WHERE relname = 'uji_bloat') AS n_dead_tup;

\echo '--- 1) awal'
SELECT ukuran, halaman FROM ukuran;
SELECT pg_relation_filepath('uji_bloat') AS lokasi_file;

\echo '--- 2) UPDATE seluruh baris'
UPDATE uji_bloat SET isi = repeat('y', 100);
SELECT ukuran, halaman FROM ukuran;
SELECT pg_sleep(2);                      -- beri waktu statistik diperbarui
SELECT n_live_tup, n_dead_tup FROM pg_stat_user_tables WHERE relname = 'uji_bloat';

\echo '--- 3) VACUUM biasa: dead tuple dibersihkan, file TIDAK mengecil'
VACUUM (VERBOSE) uji_bloat;
SELECT ukuran, halaman FROM ukuran;
SELECT pg_sleep(2);
SELECT n_live_tup, n_dead_tup FROM pg_stat_user_tables WHERE relname = 'uji_bloat';

\echo '--- 4) UPDATE seluruh baris LAGI: ruang bekas dipakai ulang, file hampir tidak bertambah'
UPDATE uji_bloat SET isi = repeat('z', 100);
SELECT ukuran, halaman FROM ukuran;

\echo '--- 5) VACUUM FULL: tabel ditulis ulang, file mengecil (kunci ACCESS EXCLUSIVE)'
VACUUM FULL uji_bloat;
SELECT ukuran, halaman FROM ukuran;
SELECT pg_relation_filepath('uji_bloat') AS lokasi_file_baru;   -- relfilenode berganti karena tabel ditulis ulang
