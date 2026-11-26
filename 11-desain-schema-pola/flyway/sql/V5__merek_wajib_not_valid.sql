-- Latihan 7(c), bagian 1: pasang constraint TANPA memindai tabel. Kunci ACCESS EXCLUSIVE hanya sekejap.
-- Sengaja DIPISAH dari V6: dalam satu transaksi, kunci ketat dari ADD CONSTRAINT ikut tertahan
-- selama VALIDATE (yang memindai seluruh tabel), sehingga tujuan NOT VALID hilang.
SET LOCAL lock_timeout = '3s';
ALTER TABLE app.produk ADD CONSTRAINT produk_merek_wajib CHECK (merek IS NOT NULL) NOT VALID;
