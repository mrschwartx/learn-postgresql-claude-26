# Modul 8: Advanced SQL & PL/pgSQL

[← Modul 7: Transaksi, ACID, MVCC & WAL](07-transaksi-mvcc-wal.md) · [Daftar Isi](README.md#daftar-isi) · [Modul 9: Index & Use Case-nya →](09-index.md)

**Isi modul ini**

- [Teori](#teori)
  - [8.1 Window Function](#81-window-function)
  - [8.2 Agregat Lanjutan](#82-agregat-lanjutan)
  - [8.3 Recursive CTE](#83-recursive-cte)
  - [8.4 Function dan Procedure](#84-function-dan-procedure)
  - [8.5 PL/pgSQL](#85-plpgsql)
  - [8.6 Trigger](#86-trigger)
  - [8.7 Fitur SQL Modern Lain](#87-fitur-sql-modern-lain)
- [Praktik](#praktik)
  - [Persiapan Data Uji](#persiapan-data-uji)
  - [Window Function](#window-function)
  - [Recursive CTE](#recursive-cte)
  - [Function dan Trigger](#function-dan-trigger)
  - [Audit Trigger](#audit-trigger)
- [Latihan](#latihan)

---


## Teori

### 8.1 Window Function

**Window function** menghitung nilai atas sekumpulan baris yang berkaitan dengan baris saat ini **tanpa menggabungkan baris** (berbeda dengan `GROUP BY`). Sintaks: `fungsi() OVER (PARTITION BY ... ORDER BY ... [frame])`.

| Fungsi | Kegunaan |
|---|---|
| `row_number()` | Nomor urut unik dalam partisi |
| `rank()` / `dense_rank()` | Peringkat (dengan/ tanpa lompatan saat seri) |
| `ntile(n)` | Bagi menjadi `n` kelompok sama besar |
| `lag(kolom, n)` / `lead(kolom, n)` | Nilai `n` baris sebelumnya / berikutnya |
| `first_value()` / `last_value()` | Nilai pertama / terakhir dalam frame |
| `sum() OVER`, `avg() OVER` | Agregat berjalan (*running total*, rata-rata bergerak) |

```sql
SELECT id, pelanggan_id, dibuat_pada,
       row_number() OVER (PARTITION BY pelanggan_id ORDER BY dibuat_pada DESC) AS urutan,
       sum(total) OVER (PARTITION BY pelanggan_id ORDER BY dibuat_pada) AS total_berjalan,
       total - lag(total) OVER (PARTITION BY pelanggan_id ORDER BY dibuat_pada) AS selisih
FROM pesanan_ringkas;
```

Pola **Top-N per grup**: bungkus `row_number()` dalam subquery/CTE lalu filter `urutan <= N` (alternatif lain: `LATERAL`, [Modul 6](06-join-subquery-cte.md)).

### 8.2 Agregat Lanjutan

| Fitur | Contoh |
|---|---|
| `FILTER` | `count(*) FILTER (WHERE status='selesai')` |
| `DISTINCT` dalam agregat | `count(DISTINCT pelanggan_id)` |
| `ORDER BY` dalam agregat | `string_agg(nama, ', ' ORDER BY nama)` |
| Ordered-set | `percentile_cont(0.5) WITHIN GROUP (ORDER BY harga)` (median) |
| Statistik | `stddev()`, `corr()`, `regr_slope()` |
| Agregat kustom | `CREATE AGGREGATE` |

### 8.3 Recursive CTE

`WITH RECURSIVE` untuk data **hierarkis/graf** (organisasi, kategori bersarang, rute):

```sql
WITH RECURSIVE bawahan AS (
    SELECT id, nama, atasan_id, 1 AS level
    FROM karyawan WHERE id = 1                     -- anchor (akar)
  UNION ALL
    SELECT k.id, k.nama, k.atasan_id, b.level + 1  -- bagian rekursif
    FROM karyawan k JOIN bawahan b ON k.atasan_id = b.id
)
SELECT * FROM bawahan ORDER BY level;
```

Hati-hati terhadap siklus (loop tak berujung): batasi `level`, atau gunakan klausa `CYCLE` (PostgreSQL 14+).

### 8.4 Function dan Procedure

| Aspek | `FUNCTION` | `PROCEDURE` |
|---|---|---|
| Dipanggil dengan | `SELECT fungsi()` | `CALL prosedur()` |
| Mengembalikan nilai | Ya (skalar, baris, tabel) | Tidak (hanya parameter `OUT`) |
| Kontrol transaksi (`COMMIT`/`ROLLBACK` di dalam) | **Tidak** | **Ya** |
| Dipakai di dalam query | Ya | Tidak |

Bahasa yang tersedia: **SQL**, **PL/pgSQL** (paling umum), PL/Python, PL/Perl, PL/Tcl (butuh ekstensi), dan lainnya.

### 8.5 PL/pgSQL

**PL/pgSQL** adalah bahasa prosedural PostgreSQL: variabel, percabangan, perulangan, penanganan error.

```sql
CREATE OR REPLACE FUNCTION kurangi_stok(p_produk bigint, p_jumlah int)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
    v_stok integer;
BEGIN
    SELECT stok INTO v_stok FROM produk WHERE id = p_produk FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Produk % tidak ditemukan', p_produk;
    ELSIF v_stok < p_jumlah THEN
        RAISE EXCEPTION 'Stok tidak cukup: tersedia %, diminta %', v_stok, p_jumlah
              USING ERRCODE = 'P0001';
    END IF;

    UPDATE produk SET stok = stok - p_jumlah WHERE id = p_produk;
    RETURN v_stok - p_jumlah;
END;
$$;
```

| Elemen | Catatan |
|---|---|
| `$$ ... $$` | *Dollar quoting* — menghindari escape tanda kutip tunggal |
| `DECLARE` | Deklarasi variabel |
| `IF / ELSIF / ELSE`, `CASE` | Percabangan |
| `LOOP`, `WHILE`, `FOR i IN 1..n`, `FOR r IN SELECT ...` | Perulangan |
| `RAISE NOTICE/EXCEPTION` | Pesan / lempar error |
| `EXCEPTION WHEN ... THEN` | Tangkap error (membuat subtransaksi implisit — ada biaya) |
| `RETURNS TABLE(...)` + `RETURN QUERY` | Fungsi yang mengembalikan banyak baris |
| `SECURITY DEFINER` | Berjalan dengan hak pemilik fungsi (hati-hati; set `search_path`) |

Procedure dengan kontrol transaksi:

```sql
CREATE PROCEDURE arsipkan_pesanan_lama()
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO arsip_pesanan SELECT * FROM pesanan WHERE dibuat_pada < now() - interval '1 year';
    COMMIT;                                      -- hanya boleh di PROCEDURE
    DELETE FROM pesanan WHERE dibuat_pada < now() - interval '1 year';
    COMMIT;
END; $$;
CALL arsipkan_pesanan_lama();
```

### 8.6 Trigger

**Trigger** menjalankan fungsi otomatis saat `INSERT`/`UPDATE`/`DELETE`/`TRUNCATE`.

| Dimensi | Pilihan |
|---|---|
| Waktu | `BEFORE`, `AFTER`, `INSTEAD OF` (untuk view) |
| Cakupan | `FOR EACH ROW`, `FOR EACH STATEMENT` |
| Variabel khusus | `NEW`, `OLD`, `TG_OP`, `TG_TABLE_NAME` |

```sql
CREATE FUNCTION set_diubah_pada() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.diubah_pada := now();
    RETURN NEW;               -- BEFORE trigger: kembalikan baris (atau NULL untuk membatalkan)
END; $$;

CREATE TRIGGER trg_produk_diubah
BEFORE UPDATE ON produk
FOR EACH ROW EXECUTE FUNCTION set_diubah_pada();
```

Use case: audit log, kolom `updated_at` otomatis, validasi kompleks, sinkronisasi tabel ringkasan. **Peringatan**: logika bisnis tersembunyi di trigger sulit di-debug dan di-test; pakai secukupnya.

### 8.7 Fitur SQL Modern Lain

| Fitur | Contoh |
|---|---|
| `RETURNING` | `INSERT ... RETURNING id` |
| `MERGE` (PG 15+) | Sinkronisasi data sumber ke target |
| `generate_series()` | Data uji, deret tanggal |
| JSONB operator | `->`, `->>`, `@>`, `jsonb_path_query()` |
| `LISTEN` / `NOTIFY` | Pub/sub ringan antar sesi database |
| `FOR UPDATE SKIP LOCKED` | Job queue |

## Praktik

```bash
docker exec -it pg-latihan psql -U postgres -d toko
```

### Persiapan Data Uji

```sql
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
```

### Window Function

```sql
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
```

### Recursive CTE

```sql
WITH RECURSIVE struktur AS (
  SELECT id, nama, atasan_id, 0 AS level, nama::text AS jalur FROM karyawan WHERE atasan_id IS NULL
  UNION ALL
  SELECT k.id, k.nama, k.atasan_id, s.level + 1, s.jalur || ' > ' || k.nama
  FROM karyawan k JOIN struktur s ON k.atasan_id = s.id
)
SELECT repeat('  ', level) || nama AS pohon, jalur FROM struktur ORDER BY jalur;
```

### Function dan Trigger

```sql
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
```

### Audit Trigger

```sql
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
```

## Latihan

1. Tampilkan **pertumbuhan bulanan** total penjualan menggunakan `lag()`: kolom bulan, total, total bulan sebelumnya, dan persentase pertumbuhan.
2. Tulis query *Top-3 produk terlaris per kategori* dengan dua cara: `row_number()` dan `LATERAL`. Bandingkan keterbacaannya.
3. Buat fungsi PL/pgSQL `buat_pesanan(p_pelanggan bigint, p_produk bigint, p_jumlah int)` yang membuat baris `pesanan` + `item_pesanan` dan memanggil `kurangi_stok`, semuanya atomik. Uji dengan stok tidak cukup dan pastikan tidak ada data setengah jadi.
4. Buat trigger yang mencegah `DELETE` pada tabel `pelanggan` bila pelanggan masih punya pesanan aktif, dengan pesan error yang jelas. Mengapa FK saja tidak cukup untuk aturan bisnis ini?
5. Gunakan `WITH RECURSIVE` untuk menghasilkan seluruh tanggal bulan ini dari satu tanggal awal, lalu bandingkan dengan `generate_series()`. Mana yang lebih sederhana?
6. Diskusikan: kapan logika bisnis sebaiknya diletakkan di **function/trigger database**, dan kapan di **kode aplikasi**? Sebutkan minimal dua kelebihan dan dua risiko masing-masing.

---

[← Modul 7: Transaksi, ACID, MVCC & WAL](07-transaksi-mvcc-wal.md) · [Daftar Isi](README.md#daftar-isi) · [Modul 9: Index & Use Case-nya →](09-index.md)
