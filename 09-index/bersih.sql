-- bersih.sql : hapus semua objek buatan Modul 9 (tabel besar, tabel uji, fungsi ukur).
-- Ekstensi pg_trgm sengaja dibiarkan (tidak mengganggu).
SET search_path TO app, public;
DROP TABLE IF EXISTS transaksi, dokumen, teks_panjang,
                     trx_a, trx_b, trx_c, trx_d, trx_email, trx_ins_a, trx_ins_b CASCADE;
DROP FUNCTION IF EXISTS uji_baca(regclass, int);
DROP FUNCTION IF EXISTS uji_insert(regclass, int);
