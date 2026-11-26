-- Latihan 7(c), bagian 2: validasi memindai tabel dengan kunci SHARE UPDATE EXCLUSIVE
-- (tidak memblokir INSERT/UPDATE/DELETE), sehingga aman untuk tabel besar.
ALTER TABLE app.produk VALIDATE CONSTRAINT produk_merek_wajib;
