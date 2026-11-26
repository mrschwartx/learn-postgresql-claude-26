-- Latihan 7(a): tambah kolom nullable. Hanya mengubah metadata: instan, kunci sangat singkat.
-- IF NOT EXISTS agar aman bila Praktik "Migrasi Aman" sudah menambah kolom ini.
SET LOCAL lock_timeout = '3s';
ALTER TABLE app.produk ADD COLUMN IF NOT EXISTS merek text;
