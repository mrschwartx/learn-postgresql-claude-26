-- seed.sql : Seed Data Modul 5, disalin langsung dari modul.
-- PERINGATAN: TRUNCATE menghapus SEMUA data di 4 tabel app.* (aman di database latihan).
-- Jalankan: docker exec -i pg-latihan psql -U postgres -d toko -f - < seed.sql

SET search_path TO app, public;

-- Reset ID agar mulai dari 1 (INSERT gagal di Modul 4 sudah memakai nomor sequence)
TRUNCATE item_pesanan, pesanan, produk, pelanggan RESTART IDENTITY;

-- Seed data
INSERT INTO pelanggan (nama, email) VALUES
  ('Andi', 'andi@contoh.com'), ('Budi', 'budi@contoh.com'),
  ('Citra', 'citra@contoh.com'), ('Dedi', 'dedi@spam.com');

INSERT INTO produk (sku, nama, harga, stok) VALUES
  ('LP-001', 'Laptop 14 inci',   12500000, 10),
  ('MS-001', 'Mouse Nirkabel',     150000, 100),
  ('KB-001', 'Keyboard Mekanik',   850000,  25),
  ('MN-001', 'Monitor 24 inci',   2200000,   5),
  ('HP-001', 'Headset',            450000,   0);

INSERT INTO pesanan (pelanggan_id, status) VALUES
  (1,'selesai'), (1,'dibayar'), (2,'baru'), (3,'selesai'), (4,'batal');

INSERT INTO item_pesanan (pesanan_id, produk_id, jumlah, harga_satuan) VALUES
  (1,1,1,12500000), (1,2,2,150000), (2,3,1,850000),
  (3,2,1,150000),   (4,4,2,2200000), (5,5,1,450000);
