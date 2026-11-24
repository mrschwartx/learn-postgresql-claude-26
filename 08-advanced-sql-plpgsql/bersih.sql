-- bersih.sql : menghapus semua objek buatan Modul 8 agar praktik/latihan bisa diulang.
-- Tidak menyentuh data pelanggan/produk/pesanan/item_pesanan (lihat pulihkan.sql untuk data).
SET search_path TO app, public;

DROP TRIGGER IF EXISTS trg_produk_diubah          ON produk;
DROP TRIGGER IF EXISTS trg_audit_harga            ON produk;
DROP TRIGGER IF EXISTS trg_cegah_hapus_pelanggan  ON pelanggan;

DROP FUNCTION IF EXISTS kurangi_stok(bigint, int);
DROP FUNCTION IF EXISTS set_diubah_pada();
DROP FUNCTION IF EXISTS catat_harga();
DROP FUNCTION IF EXISTS buat_pesanan(bigint, bigint, int);
DROP FUNCTION IF EXISTS cegah_hapus_pelanggan();

DROP TABLE IF EXISTS penjualan, penjualan_uji, karyawan, audit_harga;
ALTER TABLE produk DROP COLUMN IF EXISTS diubah_pada;
