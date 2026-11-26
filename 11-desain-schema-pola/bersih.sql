-- bersih.sql : hapus objek buatan Modul 11 (Praktik + latihan). Tidak menyentuh transaksi.
SET search_path TO app, public;
DROP SCHEMA IF EXISTS latihan11 CASCADE;
DROP TABLE IF EXISTS log_aktivitas CASCADE, antrean, staging_produk;
ALTER TABLE produk DROP CONSTRAINT IF EXISTS merek_wajib;
ALTER TABLE produk DROP CONSTRAINT IF EXISTS produk_merek_wajib;
DROP INDEX IF EXISTS idx_produk_merek;
DROP INDEX IF EXISTS idx_produk_nama;
ALTER TABLE produk DROP COLUMN IF EXISTS merek;
ALTER TABLE produk DROP COLUMN IF EXISTS catatan;
