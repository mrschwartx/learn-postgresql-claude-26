-- Latihan 7(b): isi data lama. Untuk tabel produk (hanya beberapa baris) satu UPDATE cukup.
-- Pada tabel besar JANGAN satu UPDATE: kerjakan dalam batch (mis. 10.000 baris) dengan COMMIT per batch.
-- Itu tidak bisa dilakukan di migrasi bertransaksi bawaan Flyway; jalankan sebagai pekerjaan terpisah
-- atau sebagai migrasi non-transaksional (cek dokumentasi Flyway untuk executeInTransaction).
UPDATE app.produk SET merek = 'Generik' WHERE merek IS NULL;
