-- praktik.sql : bagian Praktik Modul 7 yang berjalan di SATU sesi (disalin dari modul).
-- Bagian Isolation Level dan Locking butuh DUA sesi: lihat dua_sesi.sh.
-- Perubahan dari teks modul: baris DROP TABLE di awal agar bisa diulang.
-- Jalankan: docker exec -i pg-latihan psql -U postgres -d toko -f - < praktik.sql
-- Satu ERROR di bagian Atomicity DISENGAJA (diikuti 'transaction is aborted').

DROP TABLE IF EXISTS rekening;

\echo '=== Persiapan Tabel Rekening ==='
CREATE TABLE rekening (id int PRIMARY KEY, pemilik text, saldo numeric(12,2) CHECK (saldo >= 0));
INSERT INTO rekening VALUES (1,'Andi',500000), (2,'Budi',100000);

\echo '=== Atomicity ==='
BEGIN;
UPDATE rekening SET saldo = saldo - 600000 WHERE id = 1;   -- melanggar CHECK -> error
UPDATE rekening SET saldo = saldo + 600000 WHERE id = 2;   -- ditolak: transaction is aborted
ROLLBACK;
SELECT * FROM rekening;    -- tidak ada yang berubah

\echo '=== MVCC — Melihat Versi Baris ==='
SELECT xmin, xmax, ctid, * FROM rekening;
UPDATE rekening SET saldo = saldo + 1 WHERE id = 1;
SELECT xmin, xmax, ctid, * FROM rekening;   -- ctid dan xmin berubah: ini baris versi baru

\echo '=== Melihat WAL ==='
SHOW wal_level;
SELECT pg_current_wal_lsn();
UPDATE rekening SET saldo = saldo + 1;
SELECT pg_current_wal_lsn();     -- LSN maju: perubahan tercatat di WAL
SELECT pg_wal_lsn_diff(pg_current_wal_lsn(), '0/0') AS total_byte_wal;
