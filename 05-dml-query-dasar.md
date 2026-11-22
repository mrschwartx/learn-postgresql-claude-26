# Modul 5: DML: Query, Filter & Modifikasi Data

[← Modul 4: DDL: Schema, Tabel & Tipe Data](04-ddl-tipe-data.md) · [Daftar Isi](README.md#daftar-isi) · [Modul 6: Join, Subquery, Grouping, CTE & Set Operations →](06-join-subquery-cte.md)

**Isi modul ini**

- [Teori](#teori)
  - [5.1 DML — Data Manipulation Language](#51-dml--data-manipulation-language)
  - [5.2 INSERT — Menambah Data](#52-insert--menambah-data)
  - [5.3 SELECT — Membaca Data](#53-select--membaca-data)
  - [5.4 Filtering Data — `WHERE`](#54-filtering-data--where)
  - [5.5 Mengurutkan dan Membatasi Hasil](#55-mengurutkan-dan-membatasi-hasil)
  - [5.6 Ekspresi dan Fungsi Berguna](#56-ekspresi-dan-fungsi-berguna)
  - [5.7 UPDATE dan DELETE](#57-update-dan-delete)
  - [5.8 Import dan Export dengan `COPY`](#58-import-dan-export-dengan-copy)
- [Praktik](#praktik)
  - [Seed Data](#seed-data)
  - [Query dan Filter](#query-dan-filter)
  - [Modifikasi Data](#modifikasi-data)
  - [Import/Export dengan COPY](#importexport-dengan-copy)
- [Latihan](#latihan)

---


## Teori

### 5.1 DML — Data Manipulation Language

**DML** adalah perintah untuk **membaca dan mengubah data**: `SELECT`, `INSERT`, `UPDATE`, `DELETE`, dan `MERGE` (sejak PostgreSQL 15). Berbeda dari DDL (Modul 4) yang mengubah *struktur*, DML mengubah *isi* tabel.

### 5.2 INSERT — Menambah Data

```sql
INSERT INTO produk (sku, nama, harga, stok)
VALUES ('LP-001', 'Laptop 14"', 12500000, 10),
       ('MS-001', 'Mouse Nirkabel', 150000, 100);

-- dari hasil query
INSERT INTO arsip_produk SELECT * FROM produk WHERE stok = 0;

-- RETURNING: dapatkan nilai hasil insert tanpa query kedua
INSERT INTO pelanggan (nama, email) VALUES ('Andi', 'andi@contoh.com')
RETURNING id, dibuat_pada;
```

**UPSERT** — insert, atau update jika bentrok:

```sql
INSERT INTO produk (sku, nama, harga, stok)
VALUES ('MS-001', 'Mouse Nirkabel', 165000, 80)
ON CONFLICT (sku) DO UPDATE
   SET harga = EXCLUDED.harga, stok = EXCLUDED.stok;
-- atau: ON CONFLICT (sku) DO NOTHING
```

`EXCLUDED` merujuk pada baris yang **gagal dimasukkan**. Pola ini atomik dan aman dari race condition (berbeda dengan "cek dulu lalu insert").

### 5.3 SELECT — Membaca Data

Urutan **penulisan** klausa vs urutan **eksekusi logis**:

| Urutan Eksekusi | Klausa | Fungsi |
|---|---|---|
| 1 | `FROM` / `JOIN` | Sumber data |
| 2 | `WHERE` | Filter baris |
| 3 | `GROUP BY` | Kelompokkan |
| 4 | `HAVING` | Filter kelompok |
| 5 | `SELECT` | Pilih kolom/ekspresi |
| 6 | `DISTINCT` | Hilangkan duplikat |
| 7 | `ORDER BY` | Urutkan |
| 8 | `LIMIT` / `OFFSET` / `FETCH` | Batasi hasil |

Akibatnya, **alias kolom di `SELECT` tidak bisa dipakai di `WHERE`** (karena `WHERE` dijalankan lebih dulu), tetapi bisa dipakai di `ORDER BY`.

### 5.4 Filtering Data — `WHERE`

| Operator | Contoh |
|---|---|
| Perbandingan | `=`, `<>` / `!=`, `<`, `<=`, `>`, `>=` |
| Logika | `AND`, `OR`, `NOT` |
| Rentang | `harga BETWEEN 100000 AND 500000` |
| Daftar | `status IN ('baru','dibayar')` |
| Pola teks | `nama LIKE 'Lap%'`, **`ILIKE`** (tidak peka huruf besar/kecil) |
| Regex | `nama ~ '^Lap'`, `~*` (case-insensitive) |
| NULL | `IS NULL`, `IS NOT NULL`, `IS DISTINCT FROM` |
| Array/JSONB | `tags @> ARRAY['a']`, `data ->> 'k' = 'v'` |

### 5.5 Mengurutkan dan Membatasi Hasil

```sql
SELECT nama, harga FROM produk
ORDER BY harga DESC, nama ASC NULLS LAST
LIMIT 10 OFFSET 20;
```

**`OFFSET` besar lambat** karena database tetap harus melewati semua baris sebelumnya. Untuk pagination skala besar gunakan **keyset pagination**: `WHERE id > :id_terakhir ORDER BY id LIMIT 20` ([Modul 11](11-desain-schema-pola.md)).

### 5.6 Ekspresi dan Fungsi Berguna

| Kategori | Contoh |
|---|---|
| Teks | `lower()`, `upper()`, `length()`, `substring()`, `concat()` / `\|\|`, `trim()`, `replace()`, `split_part()` |
| Angka | `round()`, `ceil()`, `floor()`, `abs()`, `mod()` |
| Tanggal | `now()`, `current_date`, `date_trunc('month', t)`, `extract(year FROM t)`, `age()`, `t + interval '7 days'` |
| Konversi | `CAST(x AS integer)`, `x::integer`, `to_char()`, `to_date()` |
| Kondisional | `CASE WHEN ... THEN ... ELSE ... END`, `COALESCE()`, `NULLIF()` |

### 5.7 UPDATE dan DELETE

```sql
UPDATE produk SET stok = stok - 1 WHERE sku = 'MS-001' RETURNING stok;

-- UPDATE dengan data dari tabel lain
UPDATE pesanan p SET status = 'batal'
FROM pelanggan c
WHERE p.pelanggan_id = c.id AND c.email LIKE '%@spam.com';

DELETE FROM pesanan WHERE status = 'batal' AND dibuat_pada < now() - interval '1 year'
RETURNING id;
```

> **Selalu tulis `WHERE`** pada `UPDATE`/`DELETE`. Biasakan menjalankan `SELECT` dengan `WHERE` yang sama terlebih dulu, atau bungkus dalam `BEGIN` dan periksa jumlah baris sebelum `COMMIT`.

**`MERGE`** (PostgreSQL 15+) menggabungkan insert/update/delete dalam satu pernyataan berdasarkan kondisi pencocokan — berguna untuk sinkronisasi data dari tabel staging.

### 5.8 Import dan Export dengan `COPY`

`COPY` adalah cara **tercepat** memuat atau mengekspor data massal:

| Perintah | Sisi | Keterangan |
|---|---|---|
| `COPY tabel FROM '/path/file.csv' ...` | **Server** | File harus ada di server; butuh hak `pg_read_server_files` atau superuser |
| `COPY tabel TO '/path/file.csv' ...` | **Server** | Butuh `pg_write_server_files` |
| **`\copy`** (psql) | **Klien** | File dibaca/ditulis dari mesin klien — **paling praktis** |
| `COPY (SELECT ...) TO STDOUT` | Klien | Ekspor hasil query |

```sql
\copy produk (sku, nama, harga, stok) FROM 'produk.csv' WITH (FORMAT csv, HEADER true)
\copy (SELECT * FROM produk WHERE stok > 0) TO 'produk_ready.csv' WITH (FORMAT csv, HEADER true)
```

## Praktik

```bash
docker exec -it pg-latihan psql -U postgres -d toko
```

### Seed Data

```sql
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
```

### Query dan Filter

```sql
SELECT * FROM produk;
SELECT nama, harga FROM produk WHERE harga BETWEEN 100000 AND 1000000 ORDER BY harga DESC;
SELECT nama FROM produk WHERE nama ILIKE '%mouse%';
SELECT sku, nama, CASE WHEN stok = 0 THEN 'habis'
                       WHEN stok < 10 THEN 'menipis' ELSE 'aman' END AS status_stok
FROM produk;
SELECT nama, harga * 1.11 AS harga_ppn FROM produk;
SELECT date_trunc('month', dibuat_pada) AS bulan, count(*) FROM pesanan GROUP BY 1;
SELECT * FROM produk ORDER BY harga DESC LIMIT 3 OFFSET 1;
```

### Modifikasi Data

```sql
UPDATE produk SET stok = stok - 1 WHERE sku = 'MS-001' RETURNING sku, stok;

INSERT INTO produk (sku, nama, harga, stok) VALUES ('MS-001','Mouse Nirkabel',165000,80)
ON CONFLICT (sku) DO UPDATE SET harga = EXCLUDED.harga, stok = EXCLUDED.stok
RETURNING *;

BEGIN;
DELETE FROM pesanan WHERE status = 'batal';   -- perhatikan jumlah baris
ROLLBACK;                                      -- batalkan jika ragu
```

### Import/Export dengan COPY

```sql
\copy (SELECT sku, nama, harga, stok FROM produk) TO 'produk.csv' WITH (FORMAT csv, HEADER true)
CREATE TEMP TABLE produk_import (LIKE produk INCLUDING DEFAULTS INCLUDING IDENTITY);
\copy produk_import (sku, nama, harga, stok) FROM 'produk.csv' WITH (FORMAT csv, HEADER true)
SELECT count(*) FROM produk_import;
```

> `\copy` memakai file di **mesin tempat `psql` berjalan**. Jika Anda memakai `docker exec`, file tersebut berada di dalam container.

## Latihan

1. Tampilkan semua produk dengan stok di bawah 20, diurutkan dari stok terkecil, dan beri label `'kritis'` jika stok = 0 memakai `CASE`.
2. Gunakan `INSERT ... ON CONFLICT DO UPDATE` untuk menambah stok produk `KB-001` sebanyak 10 unit **tanpa** membaca nilai stok sebelumnya dari aplikasi. (Petunjuk: `stok = produk.stok + EXCLUDED.stok`.)
3. Jelaskan mengapa query `SELECT harga*1.11 AS h FROM produk WHERE h > 1000000` gagal, dan perbaiki dengan dua cara berbeda (ulangi ekspresi; subquery).
4. Hapus semua pesanan berstatus `batal` dengan `DELETE ... RETURNING id` di dalam transaksi. Verifikasi bahwa `item_pesanan` terkait ikut terhapus (karena `ON DELETE CASCADE`), lalu `ROLLBACK`.
5. Ekspor tabel `produk` ke CSV dengan `\copy`, ubah satu harga di file tersebut, lalu impor ke tabel sementara dan bandingkan dengan tabel asli.
6. Jelaskan perbedaan `DELETE`, `TRUNCATE`, dan `DROP TABLE`. Pilih yang paling tepat untuk mengosongkan tabel log berukuran 100 juta baris, dan jelaskan alasannya.

---

[← Modul 4: DDL: Schema, Tabel & Tipe Data](04-ddl-tipe-data.md) · [Daftar Isi](README.md#daftar-isi) · [Modul 6: Join, Subquery, Grouping, CTE & Set Operations →](06-join-subquery-cte.md)
