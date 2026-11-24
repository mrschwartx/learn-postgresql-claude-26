-- praktik.sql : Praktik Modul 8, disalin langsung dari modul (isi tidak diubah).
-- Prasyarat: seed Modul 5 sudah ada. Untuk MENGULANG, jalankan dulu: ./jalankan.sh bersih
-- Jalankan: docker exec -i pg-latihan psql -U postgres -d toko -f - < praktik.sql
-- Satu ERROR di bagian Function dan Trigger DISENGAJA (kurangi_stok(1, 9999)).
-- Data di tabel penjualan memakai random(), jadi angkanya berbeda tiap dijalankan.
-- EFEK SAMPING PADA SEED: stok Laptop 10 -> 8 dan harga Mouse +5000. Lihat pulihkan.sql.

\echo '=== Persiapan Data Uji ==='
SET search_path TO app, public;

CREATE TABLE penjualan AS
SELECT g AS id,
       (random()*3)::int + 1 AS pelanggan_id,
       date '2026-01-01' + (g * 3) AS tanggal,
       (random()*900000 + 100000)::numeric(12,0) AS total
FROM generate_series(1, 12) g;

CREATE TABLE karyawan (id int PRIMARY KEY, nama text, atasan_id int);
INSERT INTO karyawan VALUES (1,'Direktur',NULL),(2,'Manajer A',1),(3,'Manajer B',1),
                            (4,'Staf A1',2),(5,'Staf A2',2),(6,'Staf B1',3);

\echo '=== Window Function ==='
SELECT id, pelanggan_id, tanggal, total,
       sum(total)  OVER (PARTITION BY pelanggan_id ORDER BY tanggal) AS total_berjalan,
       lag(total)  OVER (PARTITION BY pelanggan_id ORDER BY tanggal) AS total_sebelumnya,
       rank()      OVER (ORDER BY total DESC) AS peringkat
FROM penjualan ORDER BY pelanggan_id, tanggal;

-- Top-2 per pelanggan
SELECT * FROM (
  SELECT *, row_number() OVER (PARTITION BY pelanggan_id ORDER BY total DESC) AS n FROM penjualan
) t WHERE n <= 2;

-- Median
SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY total) AS median FROM penjualan;

\echo '=== Recursive CTE ==='
WITH RECURSIVE struktur AS (
  SELECT id, nama, atasan_id, 0 AS level, nama::text AS jalur FROM karyawan WHERE atasan_id IS NULL
  UNION ALL
  SELECT k.id, k.nama, k.atasan_id, s.level + 1, s.jalur || ' > ' || k.nama
  FROM karyawan k JOIN struktur s ON k.atasan_id = s.id
)
SELECT repeat('  ', level) || nama AS pohon, jalur FROM struktur ORDER BY jalur;

\echo '=== Function dan Trigger ==='
ALTER TABLE produk ADD COLUMN IF NOT EXISTS diubah_pada timestamptz;

CREATE OR REPLACE FUNCTION kurangi_stok(p_produk bigint, p_jumlah int)
RETURNS integer LANGUAGE plpgsql AS $$
DECLARE v_stok integer;
BEGIN
  SELECT stok INTO v_stok FROM produk WHERE id = p_produk FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Produk % tidak ditemukan', p_produk; END IF;
  IF v_stok < p_jumlah THEN RAISE EXCEPTION 'Stok tidak cukup (% < %)', v_stok, p_jumlah; END IF;
  UPDATE produk SET stok = stok - p_jumlah WHERE id = p_produk;
  RETURN v_stok - p_jumlah;
END; $$;

SELECT kurangi_stok(1, 2);
SELECT kurangi_stok(1, 9999);     -- error: stok tidak cukup

CREATE OR REPLACE FUNCTION set_diubah_pada() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.diubah_pada := now(); RETURN NEW; END; $$;

CREATE TRIGGER trg_produk_diubah BEFORE UPDATE ON produk
FOR EACH ROW EXECUTE FUNCTION set_diubah_pada();

UPDATE produk SET harga = harga WHERE id = 1;
SELECT id, nama, diubah_pada FROM produk WHERE id = 1;

\echo '=== Audit Trigger ==='
CREATE TABLE audit_harga (id bigserial PRIMARY KEY, produk_id bigint, harga_lama numeric, harga_baru numeric, waktu timestamptz DEFAULT now());

CREATE FUNCTION catat_harga() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.harga IS DISTINCT FROM OLD.harga THEN
    INSERT INTO audit_harga (produk_id, harga_lama, harga_baru) VALUES (OLD.id, OLD.harga, NEW.harga);
  END IF;
  RETURN NEW;
END; $$;

CREATE TRIGGER trg_audit_harga AFTER UPDATE ON produk FOR EACH ROW EXECUTE FUNCTION catat_harga();
UPDATE produk SET harga = harga + 5000 WHERE id = 2;
SELECT * FROM audit_harga;
