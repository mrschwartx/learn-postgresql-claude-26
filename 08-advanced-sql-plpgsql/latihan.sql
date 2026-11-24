-- latihan.sql : Latihan 1-5 Modul 8 (Latihan 6 diskusi, lihat jawaban).
-- Prasyarat: praktik.sql sudah dijalankan (fungsi kurangi_stok dan kolom produk.diubah_pada).
-- Jalankan: docker exec -i pg-latihan psql -U postgres -d toko -f - < latihan.sql
-- Perubahan data uji dibungkus BEGIN ... ROLLBACK agar seed tidak berubah.
-- Baris berlabel "DISENGAJA ERROR" memang diharapkan gagal.

SET search_path TO app, public;

-- Data uji DETERMINISTIK (penjualan di praktik memakai random(), sehingga hasilnya berubah-ubah).
DROP TABLE IF EXISTS penjualan_uji;
CREATE TABLE penjualan_uji (
    id int PRIMARY KEY, pelanggan_id int NOT NULL, tanggal date NOT NULL, total numeric(12,0) NOT NULL);
INSERT INTO penjualan_uji VALUES
 (1, 1,'2026-01-04',500000), (2, 2,'2026-01-07',300000), (3, 1,'2026-01-10',750000),
 (4, 3,'2026-01-13',200000), (5, 2,'2026-01-16',450000), (6, 1,'2026-01-19',600000),
 (7, 4,'2026-01-22',900000), (8, 3,'2026-01-25',350000), (9, 2,'2026-01-28',250000),
 (10,1,'2026-01-31',800000), (11,4,'2026-02-03',400000), (12,3,'2026-02-06',650000);

-- =====================================================================
\echo '=== LATIHAN 1: pertumbuhan bulanan dengan lag() ==='
WITH bulanan AS (
    SELECT date_trunc('month', tanggal)::date AS bulan, sum(total) AS total
    FROM penjualan_uji GROUP BY 1
), dengan_lag AS (
    SELECT bulan, total, lag(total) OVER (ORDER BY bulan) AS total_sebelumnya
    FROM bulanan
)
SELECT bulan, total, total_sebelumnya,
       round(100.0 * (total - total_sebelumnya) / NULLIF(total_sebelumnya, 0), 2) AS pertumbuhan_persen
FROM dengan_lag
ORDER BY bulan;

-- =====================================================================
\echo '=== LATIHAN 2: Top-3 produk terlaris per kategori (pesanan batal tidak dihitung) ==='
CREATE TEMP VIEW terjual AS
SELECT pr.id, pr.nama, pr.kategori,
       COALESCE(sum(i.jumlah) FILTER (WHERE p.status <> 'batal'), 0) AS qty
FROM produk pr
LEFT JOIN item_pesanan i ON i.produk_id = pr.id
LEFT JOIN pesanan p      ON p.id = i.pesanan_id
GROUP BY pr.id;

\echo '--- semua kategori masih "umum" (hasil seed): cara 1 row_number()'
SELECT kategori, nama, qty, n FROM (
    SELECT t.*, row_number() OVER (PARTITION BY kategori ORDER BY qty DESC, id) AS n FROM terjual t
) x WHERE n <= 3 ORDER BY kategori, n;
\echo '--- cara 2 LATERAL'
SELECT k.kategori, x.nama, x.qty
FROM (SELECT DISTINCT kategori FROM produk) k
CROSS JOIN LATERAL (
    SELECT t.nama, t.qty FROM terjual t WHERE t.kategori = k.kategori
    ORDER BY t.qty DESC, t.id LIMIT 3
) x ORDER BY k.kategori, x.qty DESC;

\echo '--- dengan 2 kategori sementara (komputer/aksesori; HP-001 tetap "umum")'
BEGIN;
UPDATE produk SET kategori = CASE sku
    WHEN 'LP-001' THEN 'komputer' WHEN 'MN-001' THEN 'komputer'
    WHEN 'KB-001' THEN 'aksesori' WHEN 'MS-001' THEN 'aksesori' ELSE kategori END;
SELECT kategori, nama, qty, n FROM (
    SELECT t.*, row_number() OVER (PARTITION BY kategori ORDER BY qty DESC, id) AS n FROM terjual t
) x WHERE n <= 3 ORDER BY kategori, n;
ROLLBACK;

-- =====================================================================
\echo '=== LATIHAN 3: buat_pesanan atomik ==='
CREATE OR REPLACE FUNCTION buat_pesanan(p_pelanggan bigint, p_produk bigint, p_jumlah int)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE
    v_pesanan bigint;
    v_harga   numeric;
BEGIN
    IF p_jumlah IS NULL OR p_jumlah <= 0 THEN
        RAISE EXCEPTION 'Jumlah harus lebih dari 0 (diminta %)', p_jumlah;
    END IF;

    PERFORM kurangi_stok(p_produk, p_jumlah);    -- gagal lebih dulu bila stok tidak cukup; mengunci baris produk

    SELECT harga INTO v_harga FROM produk WHERE id = p_produk;

    INSERT INTO pesanan (pelanggan_id) VALUES (p_pelanggan) RETURNING id INTO v_pesanan;
    INSERT INTO item_pesanan (pesanan_id, produk_id, jumlah, harga_satuan)
    VALUES (v_pesanan, p_produk, p_jumlah, v_harga);

    RETURN v_pesanan;
END; $$;

\echo '--- keadaan awal'
SELECT (SELECT count(*) FROM pesanan) AS pesanan, (SELECT count(*) FROM item_pesanan) AS item,
       (SELECT stok FROM produk WHERE id = 4) AS stok_monitor;

\echo '--- DISENGAJA ERROR: stok tidak cukup'
SELECT buat_pesanan(1, 4, 9999);
\echo '--- DISENGAJA ERROR: pelanggan 999 tidak ada (stok SUDAH dikurangi sebelum INSERT pesanan gagal karena FK)'
SELECT buat_pesanan(999, 4, 2);
\echo '--- tidak ada data setengah jadi (angka harus sama dengan keadaan awal)'
SELECT (SELECT count(*) FROM pesanan) AS pesanan, (SELECT count(*) FROM item_pesanan) AS item,
       (SELECT stok FROM produk WHERE id = 4) AS stok_monitor;

\echo '--- berhasil (di-ROLLBACK agar seed tidak berubah)'
BEGIN;
SELECT buat_pesanan(2, 4, 2) AS pesanan_baru;
SELECT p.id, p.pelanggan_id, i.produk_id, i.jumlah, i.harga_satuan
FROM pesanan p JOIN item_pesanan i ON i.pesanan_id = p.id
WHERE p.id = (SELECT max(id) FROM pesanan);
SELECT stok AS stok_monitor_sesudah FROM produk WHERE id = 4;
ROLLBACK;

\echo '--- satu transaksi: pesanan pertama sukses, kedua gagal -> seluruh transaksi batal'
BEGIN;
SELECT buat_pesanan(2, 4, 1);
\echo '--- DISENGAJA ERROR'
SELECT buat_pesanan(2, 4, 9999);
ROLLBACK;
SELECT (SELECT count(*) FROM pesanan) AS pesanan, (SELECT count(*) FROM item_pesanan) AS item,
       (SELECT stok FROM produk WHERE id = 4) AS stok_monitor;

-- =====================================================================
\echo '=== LATIHAN 4: trigger pencegah DELETE pelanggan ber-pesanan aktif ==='
CREATE OR REPLACE FUNCTION cegah_hapus_pelanggan() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_aktif int;
BEGIN
    SELECT count(*) INTO v_aktif
    FROM pesanan
    WHERE pelanggan_id = OLD.id AND status IN ('baru', 'dibayar', 'dikirim');

    IF v_aktif > 0 THEN
        RAISE EXCEPTION 'Pelanggan % (%) tidak boleh dihapus: masih punya % pesanan aktif', OLD.id, OLD.nama, v_aktif
            USING ERRCODE = 'restrict_violation',
                  HINT = 'Selesaikan atau batalkan pesanan tersebut terlebih dahulu.';
    END IF;
    RETURN OLD;
END; $$;

DROP TRIGGER IF EXISTS trg_cegah_hapus_pelanggan ON pelanggan;
CREATE TRIGGER trg_cegah_hapus_pelanggan
BEFORE DELETE ON pelanggan
FOR EACH ROW EXECUTE FUNCTION cegah_hapus_pelanggan();

\echo '--- DISENGAJA ERROR: Budi (id 2) punya pesanan "baru" -> ditolak trigger'
DELETE FROM pelanggan WHERE id = 2;
\echo '--- DISENGAJA ERROR: Dedi (id 4) hanya punya pesanan "batal" -> trigger mengizinkan, tetapi FK menolak'
DELETE FROM pelanggan WHERE id = 4;

\echo '--- andaikan FK diubah menjadi ON DELETE CASCADE (DDL transaksional, di-ROLLBACK): kini trigger yang menjadi penjaga'
BEGIN;
ALTER TABLE pesanan DROP CONSTRAINT pesanan_pelanggan_id_fkey;
ALTER TABLE pesanan ADD CONSTRAINT pesanan_pelanggan_id_fkey
    FOREIGN KEY (pelanggan_id) REFERENCES pelanggan(id) ON DELETE CASCADE;
\echo '--- DISENGAJA ERROR: Budi tetap ditolak trigger'
DELETE FROM pelanggan WHERE id = 2;
ROLLBACK;                          -- setelah error transaksi aborted; ROLLBACK mengembalikan FK semula

BEGIN;
ALTER TABLE pesanan DROP CONSTRAINT pesanan_pelanggan_id_fkey;
ALTER TABLE pesanan ADD CONSTRAINT pesanan_pelanggan_id_fkey
    FOREIGN KEY (pelanggan_id) REFERENCES pelanggan(id) ON DELETE CASCADE;
\echo '--- Dedi (hanya pesanan batal) kini BERHASIL dihapus, pesanannya ikut terhapus (CASCADE)'
DELETE FROM pelanggan WHERE id = 4;
SELECT (SELECT count(*) FROM pelanggan) AS pelanggan, (SELECT count(*) FROM pesanan) AS pesanan;
ROLLBACK;

-- =====================================================================
\echo '=== LATIHAN 5: tanggal satu bulan, WITH RECURSIVE vs generate_series ==='
\echo '--- WITH RECURSIVE (bulan Februari 2028, tahun kabisat)'
WITH RECURSIVE tgl AS (
    SELECT date '2028-02-01' AS d
  UNION ALL
    SELECT d + 1 FROM tgl
    WHERE d + 1 < (date_trunc('month', date '2028-02-01') + interval '1 month')::date
)
SELECT count(*) AS jumlah_hari, min(d) AS awal, max(d) AS akhir FROM tgl;

\echo '--- generate_series'
SELECT count(*) AS jumlah_hari, min(d)::date AS awal, max(d)::date AS akhir
FROM generate_series(date '2028-02-01', date '2028-02-29', interval '1 day') AS d;

\echo '--- keduanya identik? (hasil harus KOSONG)'
WITH RECURSIVE tgl AS (
    SELECT date '2028-02-01' AS d
  UNION ALL
    SELECT d + 1 FROM tgl
    WHERE d + 1 < (date_trunc('month', date '2028-02-01') + interval '1 month')::date
), gs AS (
    SELECT d::date AS d FROM generate_series(date '2028-02-01', date '2028-02-29', interval '1 day') AS d
)
SELECT 'hanya_rekursif' AS sumber, d FROM (SELECT d FROM tgl EXCEPT SELECT d FROM gs) a
UNION ALL
SELECT 'hanya_generate_series', d FROM (SELECT d FROM gs EXCEPT SELECT d FROM tgl) b;
