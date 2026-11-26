-- bersih_salinan.sql : hapus HANYA salinan uji dan objek bantu latihan, BIARKAN tabel transaksi
-- dan dokumen beserta index Praktik. Modul 10 memakai app.transaksi dan idx_trx_pelanggan.
SET search_path TO app, public;
DROP TABLE IF EXISTS trx_a, trx_b, trx_c, trx_d, trx_email, trx_ins_a, trx_ins_b, teks_panjang;
DROP INDEX IF EXISTS idx_trx_brin_waktu;      -- index tambahan dari Latihan 6 (acak, tidak berguna)
DROP INDEX IF EXISTS idx_trx_waktu_penuh;     -- pembanding Latihan 3 (sudah dihapus latihan; jaga-jaga)
DROP FUNCTION IF EXISTS uji_baca(regclass, int);
DROP FUNCTION IF EXISTS uji_insert(regclass, int);
