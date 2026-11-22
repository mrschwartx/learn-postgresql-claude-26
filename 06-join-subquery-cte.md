# Modul 6: Join, Subquery, Grouping, CTE & Set Operations

[← Modul 5: DML: Query, Filter & Modifikasi Data](05-dml-query-dasar.md) · [Daftar Isi](README.md#daftar-isi) · [Modul 7: Transaksi, ACID, MVCC & WAL →](07-transaksi-mvcc-wal.md)

**Isi modul ini**

- [Teori](#teori)
  - [6.1 Joining Tables](#61-joining-tables)
  - [6.2 Grouping dan Agregasi](#62-grouping-dan-agregasi)
  - [6.3 Subquery](#63-subquery)
  - [6.4 CTE — Common Table Expression](#64-cte--common-table-expression)
  - [6.5 Lateral Join](#65-lateral-join)
  - [6.6 Set Operations](#66-set-operations)
- [Praktik](#praktik)
  - [INNER dan LEFT JOIN](#inner-dan-left-join)
  - [JOIN Beberapa Tabel](#join-beberapa-tabel)
  - [Grouping dan Agregasi](#grouping-dan-agregasi)
  - [Subquery](#subquery)
  - [CTE](#cte)
  - [LATERAL Join](#lateral-join)
  - [Set Operations](#set-operations)
- [Latihan](#latihan)

---


## Teori

### 6.1 Joining Tables

`JOIN` menggabungkan baris dari dua tabel berdasarkan kondisi (biasanya kesamaan FK dan PK).

| Jenis JOIN | Hasil |
|---|---|
| `INNER JOIN` | Hanya baris yang **cocok** di kedua tabel |
| `LEFT JOIN` | Semua baris kiri + yang cocok dari kanan (sisanya `NULL`) |
| `RIGHT JOIN` | Kebalikan `LEFT JOIN` |
| `FULL OUTER JOIN` | Semua baris dari kedua sisi |
| `CROSS JOIN` | Kombinasi **setiap** baris kiri dengan setiap baris kanan (hasil kartesian) |
| `SELF JOIN` | Tabel di-join dengan dirinya sendiri (mis. hierarki karyawan–atasan) |

```sql
SELECT c.nama, p.id AS pesanan_id, p.status
FROM pelanggan c
LEFT JOIN pesanan p ON p.pelanggan_id = c.id;
```

**Anti-join** (cari yang *tidak punya* pasangan) — pola umum:

```sql
SELECT c.* FROM pelanggan c
LEFT JOIN pesanan p ON p.pelanggan_id = c.id
WHERE p.id IS NULL;                   -- pelanggan tanpa pesanan
-- setara: WHERE NOT EXISTS (SELECT 1 FROM pesanan p WHERE p.pelanggan_id = c.id)
```

> Hindari `NOT IN (subquery)` jika subquery bisa menghasilkan `NULL` — hasilnya menjadi kosong karena logika tiga nilai (Modul 2). Gunakan `NOT EXISTS`.

### 6.2 Grouping dan Agregasi

| Fungsi Agregat | Fungsi |
|---|---|
| `count(*)` / `count(kolom)` | Jumlah baris / jumlah nilai non-NULL |
| `sum()`, `avg()`, `min()`, `max()` | Agregasi numerik |
| `string_agg(kolom, ', ')` | Gabung teks |
| `array_agg(kolom)` | Kumpulkan ke array |
| `jsonb_agg()`, `jsonb_object_agg()` | Kumpulkan ke JSON |

```sql
SELECT status, count(*) AS jumlah
FROM pesanan
GROUP BY status
HAVING count(*) > 1
ORDER BY jumlah DESC;
```

| Klausa | Memfilter | Dijalankan |
|---|---|---|
| `WHERE` | **Baris** individual | Sebelum pengelompokan |
| `HAVING` | **Kelompok** (hasil agregat) | Sesudah pengelompokan |

Fitur grouping lanjutan: `GROUPING SETS`, `ROLLUP`, `CUBE` (subtotal dan grand total dalam satu query), serta klausa `FILTER`:

```sql
SELECT count(*) AS total,
       count(*) FILTER (WHERE status = 'selesai') AS selesai
FROM pesanan;
```

### 6.3 Subquery

Subquery adalah `SELECT` di dalam query lain.

| Jenis | Contoh |
|---|---|
| **Scalar** (satu nilai) | `WHERE harga > (SELECT avg(harga) FROM produk)` |
| **List** | `WHERE id IN (SELECT produk_id FROM item_pesanan)` |
| **EXISTS** | `WHERE EXISTS (SELECT 1 FROM pesanan WHERE pelanggan_id = c.id)` |
| **Derived table** (di `FROM`) | `FROM (SELECT ... ) AS t` |
| **Correlated** | Subquery merujuk kolom query luar; dievaluasi per baris luar (planner sering mengoptimalkannya jadi join) |

`EXISTS` berhenti begitu menemukan satu baris cocok, sehingga sering lebih efisien daripada `IN` untuk subquery besar.

### 6.4 CTE — Common Table Expression

**CTE** (`WITH`) memberi nama pada subquery agar query kompleks lebih mudah dibaca:

```sql
WITH total_per_pesanan AS (
    SELECT pesanan_id, sum(jumlah * harga_satuan) AS total
    FROM item_pesanan GROUP BY pesanan_id
)
SELECT p.id, c.nama, t.total
FROM pesanan p
JOIN pelanggan c ON c.id = p.pelanggan_id
JOIN total_per_pesanan t ON t.pesanan_id = p.id;
```

Sejak PostgreSQL 12, CTE non-rekursif yang dirujuk **sekali** dan tanpa efek samping di-*inline* oleh planner (bukan lagi "optimization fence"). Anda bisa mengontrolnya: `WITH x AS MATERIALIZED (...)` atau `AS NOT MATERIALIZED (...)`.

**CTE data-modifying** — menggabungkan beberapa DML atomik:

```sql
WITH dihapus AS (
    DELETE FROM pesanan WHERE status = 'batal' RETURNING *
)
INSERT INTO arsip_pesanan SELECT * FROM dihapus;
```

CTE **rekursif** (`WITH RECURSIVE`) untuk data hierarkis dibahas di [Modul 8](08-advanced-sql-plpgsql.md).

### 6.5 Lateral Join

`LATERAL` memungkinkan subquery di `FROM` **merujuk kolom dari tabel di sebelah kirinya** — seperti `foreach` di SQL. Kasus klasik: **Top-N per grup**.

```sql
SELECT c.nama, x.id AS pesanan_id, x.dibuat_pada
FROM pelanggan c
CROSS JOIN LATERAL (
    SELECT id, dibuat_pada FROM pesanan p
    WHERE p.pelanggan_id = c.id
    ORDER BY dibuat_pada DESC LIMIT 2        -- 2 pesanan terbaru per pelanggan
) x;
```

Gunakan `LEFT JOIN LATERAL (...) ON true` agar pelanggan tanpa pesanan tetap muncul. Fungsi yang mengembalikan set (mis. `unnest()`, `generate_series()`) juga implisit bersifat lateral.

### 6.6 Set Operations

| Operator | Hasil | Catatan |
|---|---|---|
| `UNION` | Gabungan, **duplikat dihapus** | Butuh sort/hash — lebih lambat |
| `UNION ALL` | Gabungan **tanpa** hapus duplikat | **Lebih cepat** — pakai bila duplikat tidak masalah |
| `INTERSECT` | Irisan | |
| `EXCEPT` | Selisih (ada di kiri, tidak di kanan) | |

Syarat: jumlah dan tipe kolom kedua query harus kompatibel.

## Praktik

```bash
docker exec -it pg-latihan psql -U postgres -d toko
```

### INNER dan LEFT JOIN

```sql
SET search_path TO app, public;

-- INNER vs LEFT JOIN
SELECT c.nama, p.id, p.status
FROM pelanggan c JOIN pesanan p ON p.pelanggan_id = c.id;

SELECT c.nama, count(p.id) AS jumlah_pesanan
FROM pelanggan c LEFT JOIN pesanan p ON p.pelanggan_id = c.id
GROUP BY c.id, c.nama ORDER BY jumlah_pesanan DESC;
```

### JOIN Beberapa Tabel

```sql
-- JOIN 4 tabel: detail pesanan
SELECT p.id AS pesanan, c.nama AS pelanggan, pr.nama AS produk,
       i.jumlah, i.jumlah * i.harga_satuan AS subtotal
FROM pesanan p
JOIN pelanggan c    ON c.id = p.pelanggan_id
JOIN item_pesanan i ON i.pesanan_id = p.id
JOIN produk pr      ON pr.id = i.produk_id
ORDER BY p.id;
```

### Grouping dan Agregasi

```sql
-- Grouping + HAVING + FILTER
SELECT status, count(*) FROM pesanan GROUP BY status HAVING count(*) >= 1;
SELECT count(*) AS total, count(*) FILTER (WHERE status='selesai') AS selesai FROM pesanan;

-- ROLLUP: subtotal dan grand total
SELECT c.nama, p.status, count(*)
FROM pesanan p JOIN pelanggan c ON c.id = p.pelanggan_id
GROUP BY ROLLUP (c.nama, p.status);
```

### Subquery

```sql
-- Subquery
SELECT nama, harga FROM produk WHERE harga > (SELECT avg(harga) FROM produk);
SELECT nama FROM produk pr
WHERE NOT EXISTS (SELECT 1 FROM item_pesanan i WHERE i.produk_id = pr.id);   -- belum pernah dipesan
```

### CTE

```sql
-- CTE
WITH total_pesanan AS (
  SELECT pesanan_id, sum(jumlah * harga_satuan) AS total FROM item_pesanan GROUP BY pesanan_id
)
SELECT c.nama, sum(t.total) AS total_belanja
FROM total_pesanan t
JOIN pesanan p ON p.id = t.pesanan_id
JOIN pelanggan c ON c.id = p.pelanggan_id
GROUP BY c.nama ORDER BY total_belanja DESC;
```

### LATERAL Join

```sql
-- LATERAL: pesanan terbaru per pelanggan
SELECT c.nama, x.id, x.dibuat_pada
FROM pelanggan c
LEFT JOIN LATERAL (
  SELECT id, dibuat_pada FROM pesanan p WHERE p.pelanggan_id = c.id
  ORDER BY dibuat_pada DESC LIMIT 1
) x ON true;
```

### Set Operations

```sql
-- Set operations
SELECT nama FROM pelanggan WHERE email LIKE '%@contoh.com'
UNION ALL
SELECT nama FROM produk WHERE harga > 1000000;

SELECT id FROM produk
EXCEPT
SELECT produk_id FROM item_pesanan;
```

## Latihan

1. Tampilkan total belanja (`sum(jumlah * harga_satuan)`) per pelanggan, **termasuk pelanggan yang belum pernah belanja** (total 0 — gunakan `COALESCE`).
2. Tulis query "pelanggan yang belum pernah memesan" dengan tiga cara berbeda: `LEFT JOIN ... IS NULL`, `NOT EXISTS`, dan `NOT IN`. Jelaskan mengapa `NOT IN` berbahaya bila ada `NULL`.
3. Gunakan `LATERAL` untuk menampilkan **2 produk termahal** dari setiap kategori (tambahkan kolom `kategori` bila perlu).
4. Buat CTE data-modifying yang memindahkan pesanan berstatus `batal` ke tabel `arsip_pesanan` secara atomik dalam **satu** pernyataan.
5. Jelaskan perbedaan `UNION` dan `UNION ALL` dari sisi hasil dan performa, lalu berikan satu kasus nyata di mana `UNION ALL` aman dipakai.
6. Diskusikan: query dengan `GROUP BY` yang menampilkan kolom bukan agregat dan bukan di `GROUP BY` akan error. Mengapa PostgreSQL menolak, dan bagaimana pengecualian untuk kolom yang bergantung fungsional pada primary key?

---

[← Modul 5: DML: Query, Filter & Modifikasi Data](05-dml-query-dasar.md) · [Daftar Isi](README.md#daftar-isi) · [Modul 7: Transaksi, ACID, MVCC & WAL →](07-transaksi-mvcc-wal.md)
