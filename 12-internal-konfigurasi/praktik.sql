-- praktik.sql : Praktik Modul 12 (bagian SQL), disalin langsung dari modul (isi tidak diubah).
-- Perintah shell (ps, ls $PGDATA) ada di praktik_shell.sh.
-- Jalankan: docker exec -i pg-latihan psql -U postgres -d toko -f - < praktik.sql
--
-- PERINGATAN, EFEK SAMPING YANG TIDAK DI-RESET OLEH MODUL:
--  * ALTER ROLE postgres IN DATABASE toko SET statement_timeout = '60s'  -> berlaku untuk SEMUA sesi baru
--    role postgres di database toko (juga pg_dump, CREATE INDEX, bulk load di modul berikutnya!).
--  * ALTER TABLE transaksi SET (autovacuum_vacuum_scale_factor = 0.02)    -> opsi tabel yang menetap.
--  * tabel uji_bloat tidak dihapus.
-- Semuanya dibersihkan oleh: ./jalankan.sh bersih
-- Catatan: autovacuum dapat memperbaiki n_dead_tup di bagian "Bloat dan Vacuum" sebelum Anda melihatnya
-- (lihat jawaban); latihan.sql mematikan autovacuum pada tabel ujinya.

\echo '=== Proses dan Memori ==='
SELECT pid, backend_type, state FROM pg_stat_activity ORDER BY backend_type;
SHOW shared_buffers; SHOW work_mem; SHOW max_connections; SHOW wal_level;

\echo '=== Layout File dan Ukuran ==='
SET search_path TO app, public;
SELECT pg_relation_filepath('transaksi');
SELECT pg_size_pretty(pg_relation_size('transaksi')) AS tabel,
       pg_size_pretty(pg_indexes_size('transaksi')) AS index,
       pg_size_pretty(pg_total_relation_size('transaksi')) AS total;
SELECT oid, datname FROM pg_database;

\echo '=== Bloat dan Vacuum ==='
CREATE TABLE uji_bloat AS SELECT g AS id, repeat('x', 100) AS isi FROM generate_series(1, 200000) g;
SELECT pg_size_pretty(pg_relation_size('uji_bloat'));
UPDATE uji_bloat SET isi = repeat('y', 100);                    -- menciptakan dead tuple
SELECT pg_size_pretty(pg_relation_size('uji_bloat'));           -- hampir 2x lipat
SELECT n_live_tup, n_dead_tup FROM pg_stat_user_tables WHERE relname = 'uji_bloat';
VACUUM (VERBOSE) uji_bloat;
SELECT pg_size_pretty(pg_relation_size('uji_bloat'));           -- ukuran file tetap
VACUUM FULL uji_bloat;
SELECT pg_size_pretty(pg_relation_size('uji_bloat'));           -- mengecil

\echo '=== Konfigurasi ==='
SELECT name, setting, context FROM pg_settings WHERE name IN ('shared_buffers','work_mem','max_connections');
ALTER SYSTEM SET work_mem = '32MB';
SELECT pg_reload_conf();
SHOW work_mem;

ALTER ROLE postgres IN DATABASE toko SET statement_timeout = '60s';
SELECT * FROM pg_db_role_setting;
ALTER SYSTEM RESET work_mem; SELECT pg_reload_conf();

ALTER TABLE transaksi SET (autovacuum_vacuum_scale_factor = 0.02);
SELECT reloptions FROM pg_class WHERE relname = 'transaksi';

\echo '=== System Catalog ==='
SELECT c.relname, c.relkind, c.reltuples::bigint AS estimasi_baris
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'app' AND c.relkind = 'r';

SELECT table_name, column_name, data_type
FROM information_schema.columns WHERE table_schema = 'app' AND table_name = 'produk';
