-- eksplorasi.sql : Praktik "Eksplorasi di psql" (Modul 3)
-- Jalankan: docker exec -i pg-latihan psql -U postgres -f - < eksplorasi.sql
\set ON_ERROR_STOP on

\echo '== 1. Versi dan lokasi =='
SELECT version();
SHOW server_version;
SHOW data_directory;
SHOW port;

\echo '== 2. Daftar database =='
\l

\echo '== 3. Waktu eksekusi =='
\timing on
SELECT 1 + 1 AS hasil;
\timing off

\echo '== 4. Bukti perilaku NULL (Modul 2) =='
SELECT NULL = NULL                  AS sama,
       NULL IS NULL                 AS is_null,
       NULL OR TRUE                 AS or_true,
       NULL AND FALSE               AS and_false,
       COALESCE(NULL, NULL, 3)      AS coalesce_3,
       NULL IS DISTINCT FROM NULL   AS distinct_null;

\echo '== 5. Buat database toko (idempoten: dilewati jika sudah ada) =='
SELECT 'CREATE DATABASE toko'
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'toko')
\gexec

\c toko
\conninfo
