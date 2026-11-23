-- reset.sql : kembalikan ke keadaan sebelum Modul 4 (hanya objek buatan modul ini).
-- Menghapus schema app (tabel, view, materialized view, tipe 'prioritas' ikut terhapus),
-- latihan, dan perpustakaan. AWAS: ini menghapus datanya. Hanya untuk database latihan.
DROP SCHEMA IF EXISTS app CASCADE;
DROP SCHEMA IF EXISTS latihan CASCADE;
DROP SCHEMA IF EXISTS perpustakaan CASCADE;
