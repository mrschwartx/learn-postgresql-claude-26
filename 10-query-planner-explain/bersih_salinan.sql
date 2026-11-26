-- bersih_salinan.sql : hapus salinan/objek bantu latihan Modul 10.
-- Tabel transaksi dan index Praktik TIDAK disentuh (dipakai Modul 11-16).
SET search_path TO app, public;
DROP TABLE IF EXISTS pelanggan_uji, trx_stat, trx_opt;
