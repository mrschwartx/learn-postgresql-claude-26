-- bersih.sql : kembalikan semua efek samping Praktik/Latihan Modul 12.
SET search_path TO app, public;
DROP SCHEMA IF EXISTS latihan12 CASCADE;
DROP TABLE IF EXISTS app.uji_bloat, public.uji_bloat, app.uji_horizon;
-- Menghapus setting role-di-database yang tidak di-reset oleh modul. TANPA ini, statement_timeout 60s
-- menempel pada semua sesi baru dan akan menimpa ALTER DATABASE ... SET statement_timeout di Modul 16.
ALTER ROLE postgres IN DATABASE toko RESET statement_timeout;
ALTER TABLE app.transaksi RESET (autovacuum_vacuum_scale_factor, autovacuum_analyze_scale_factor);
ALTER SYSTEM RESET work_mem;
ALTER SYSTEM RESET log_min_duration_statement;
SELECT pg_reload_conf();
\echo '--- sisa pengaturan role/database (harus kosong untuk role postgres di toko):'
SELECT * FROM pg_db_role_setting;
SELECT relname, reloptions FROM pg_class WHERE relname = 'transaksi';
