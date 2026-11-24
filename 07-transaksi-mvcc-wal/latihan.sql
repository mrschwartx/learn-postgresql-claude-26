-- latihan.sql : Latihan 1 dan 6 Modul 7 (yang berjalan di satu sesi).
-- Latihan 2, 3, 4 (dua sesi): lihat dua_sesi.sh. Latihan 5 konseptual.
-- Prasyarat: tabel rekening dari praktik.sql (bagian Persiapan) -- data di-reset di sini.
-- Jalankan: docker exec -i pg-latihan psql -U postgres -d toko -f - < latihan.sql
-- Baris berlabel "DISENGAJA ERROR" memang diharapkan gagal.

-- =====================================================================
\echo '=== LATIHAN 1: transfer dengan SAVEPOINT dan log_transfer ==='
CREATE TABLE IF NOT EXISTS log_transfer (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    dari         int           NOT NULL,
    ke           int           NOT NULL,
    jumlah       numeric(12,2) NOT NULL,
    status       text          NOT NULL CHECK (status IN ('berhasil', 'gagal')),
    pesan        text,
    dicatat_pada timestamptz   NOT NULL DEFAULT now()
);
TRUNCATE log_transfer RESTART IDENTITY;

TRUNCATE rekening;
INSERT INTO rekening VALUES (1, 'Andi', 500000), (2, 'Budi', 100000),
                            (3, 'Citra', 9999999999.99);   -- saldo Citra tepat di batas numeric(12,2)

\echo '--- transfer 1: Andi -> Budi 100000 (berhasil)'
BEGIN;
SAVEPOINT sebelum_transfer;
UPDATE rekening SET saldo = saldo - 100000 WHERE id = 1;
UPDATE rekening SET saldo = saldo + 100000 WHERE id = 2;
INSERT INTO log_transfer (dari, ke, jumlah, status) VALUES (1, 2, 100000, 'berhasil');
RELEASE SAVEPOINT sebelum_transfer;
COMMIT;

\echo '--- transfer 2: Andi -> Citra 100000 (pengurangan berhasil, penambahan GAGAL)'
BEGIN;
SAVEPOINT sebelum_transfer;                 -- SEBELUM pengurangan, bukan sesudahnya
UPDATE rekening SET saldo = saldo - 100000 WHERE id = 1;   -- berhasil
\echo '--- DISENGAJA ERROR: numeric field overflow'
UPDATE rekening SET saldo = saldo + 100000 WHERE id = 3;   -- gagal
ROLLBACK TO SAVEPOINT sebelum_transfer;     -- pengurangan ikut dibatalkan
INSERT INTO log_transfer (dari, ke, jumlah, status, pesan)
VALUES (1, 3, 100000, 'gagal', 'kredit ditolak: saldo penerima melebihi batas kolom');
COMMIT;                                     -- log tersimpan, saldo tidak berubah

SELECT * FROM rekening ORDER BY id;
SELECT id, dari, ke, jumlah, status, pesan FROM log_transfer ORDER BY id;

-- =====================================================================
\echo '=== LATIHAN 6: bloat akibat UPDATE (MVCC) ==='
DROP TABLE IF EXISTS uji_bloat;
CREATE TABLE uji_bloat (id int PRIMARY KEY, nilai int NOT NULL)
WITH (autovacuum_enabled = off);            -- agar hasil tidak terganggu autovacuum
INSERT INTO uji_bloat SELECT g, 0 FROM generate_series(1, 10000) g;
VACUUM (ANALYZE) uji_bloat;

\echo '--- 1) ukuran awal'
SELECT pg_size_pretty(pg_relation_size('uji_bloat')) AS ukuran_awal;

\echo '--- 2) UPDATE seluruh baris 5 kali (jumlah baris hidup tetap 10000)'
UPDATE uji_bloat SET nilai = nilai + 1;
UPDATE uji_bloat SET nilai = nilai + 1;
UPDATE uji_bloat SET nilai = nilai + 1;
UPDATE uji_bloat SET nilai = nilai + 1;
UPDATE uji_bloat SET nilai = nilai + 1;
SELECT count(*) AS baris_hidup, pg_size_pretty(pg_relation_size('uji_bloat')) AS ukuran_sesudah_update FROM uji_bloat;
SELECT pg_sleep(2);        -- beri waktu statistik diperbarui
SELECT n_live_tup, n_dead_tup FROM pg_stat_user_tables WHERE relname = 'uji_bloat';

\echo '--- 3) VACUUM: dead tuple dibersihkan, ruang bisa dipakai ulang'
VACUUM uji_bloat;
SELECT pg_size_pretty(pg_relation_size('uji_bloat')) AS ukuran_sesudah_vacuum;
SELECT pg_sleep(2);
SELECT n_live_tup, n_dead_tup FROM pg_stat_user_tables WHERE relname = 'uji_bloat';

\echo '--- 4) UPDATE 5 kali lagi: ruang bekas dipakai ulang'
UPDATE uji_bloat SET nilai = nilai + 1;
UPDATE uji_bloat SET nilai = nilai + 1;
UPDATE uji_bloat SET nilai = nilai + 1;
UPDATE uji_bloat SET nilai = nilai + 1;
UPDATE uji_bloat SET nilai = nilai + 1;
SELECT pg_size_pretty(pg_relation_size('uji_bloat')) AS ukuran_sesudah_update_kedua;

\echo '--- 5) VACUUM FULL menulis ulang tabel dan mengembalikan ruang ke OS (butuh kunci ACCESS EXCLUSIVE)'
VACUUM FULL uji_bloat;
SELECT pg_size_pretty(pg_relation_size('uji_bloat')) AS ukuran_sesudah_vacuum_full;
DROP TABLE uji_bloat;
