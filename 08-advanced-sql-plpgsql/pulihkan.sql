-- pulihkan.sql : mengembalikan dua perubahan data akibat Praktik Modul 8
-- (jalankan SETELAH bersih.sql, karena trigger harus sudah tidak ada).
--   kurangi_stok(1, 2)            : stok LP-001 10 -> 8
--   harga MS-001 + 5000           : 165000 -> 170000
SET search_path TO app, public;
UPDATE produk SET stok  = 10     WHERE sku = 'LP-001';
UPDATE produk SET harga = 165000 WHERE sku = 'MS-001';
SELECT sku, harga, stok FROM produk ORDER BY id;
