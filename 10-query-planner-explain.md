# Modul 10: Query Planner & EXPLAIN

[← Modul 9: Index & Use Case-nya](09-index.md) · [Daftar Isi](README.md#daftar-isi) · [Modul 11: Desain Schema & Pola Aplikasi →](11-desain-schema-pola.md)

**Isi modul ini**

- [Teori](#teori)
  - [10.1 Query Planner — Dari "Apa" ke "Bagaimana"](#101-query-planner--dari-apa-ke-bagaimana)
  - [10.2 `EXPLAIN` dan `EXPLAIN ANALYZE`](#102-explain-dan-explain-analyze)
  - [10.3 Node Penting dalam Rencana](#103-node-penting-dalam-rencana)
  - [10.4 Alat Bantu Analisis Rencana](#104-alat-bantu-analisis-rencana)
  - [10.5 Parameter yang Memengaruhi Planner](#105-parameter-yang-memengaruhi-planner)
  - [10.6 Alur Optimasi Query](#106-alur-optimasi-query)
- [Praktik](#praktik)
  - [Rencana Sederhana](#rencana-sederhana)
  - [Seq Scan vs Index Scan](#seq-scan-vs-index-scan)
  - [Join dan Algoritmanya](#join-dan-algoritmanya)
  - [work_mem dan Sort ke Disk](#work_mem-dan-sort-ke-disk)
  - [Statistik Planner](#statistik-planner)
  - [EXPLAIN ANALYZE yang Aman untuk DML](#explain-analyze-yang-aman-untuk-dml)
  - [Visualisasi Rencana](#visualisasi-rencana)
- [Latihan](#latihan)

---


## Teori

### 10.1 Query Planner — Dari "Apa" ke "Bagaimana"

SQL bersifat **deklaratif**: Anda hanya menyatakan hasil yang diinginkan. **Query planner (optimizer)** menentukan cara terbaiknya: urutan join, metode scan, algoritma join, dan seterusnya. Ia memilih rencana dengan **estimasi biaya (cost)** terendah berdasarkan **statistik** tabel.

```
Statistik (pg_statistic / pg_stats)  ┐
Parameter biaya (seq_page_cost, ...)  ├─► Planner ─► Beberapa kandidat rencana ─► Rencana termurah ─► Executor
Index yang tersedia                  ┘
```

**Statistik** dikumpulkan oleh `ANALYZE` (otomatis oleh autovacuum): jumlah baris, distribusi nilai, nilai paling sering (*most common values*), histogram, korelasi fisik. **Statistik usang = rencana buruk** — penyebab paling umum query tiba-tiba lambat.

### 10.2 `EXPLAIN` dan `EXPLAIN ANALYZE`

| Perintah | Perilaku |
|---|---|
| `EXPLAIN query` | Menampilkan **rencana** dan estimasi biaya; query **tidak dijalankan** |
| `EXPLAIN ANALYZE query` | **Menjalankan** query dan menampilkan waktu & jumlah baris **aktual** |
| `EXPLAIN (ANALYZE, BUFFERS)` | Plus penggunaan buffer (cache hit vs baca disk) — sangat dianjurkan |
| `EXPLAIN (ANALYZE, VERBOSE, SETTINGS, WAL)` | Detail tambahan |

> `EXPLAIN ANALYZE` pada `INSERT`/`UPDATE`/`DELETE` **benar-benar mengubah data**. Bungkus dengan `BEGIN; ... ROLLBACK;`.

Contoh keluaran:

```
Index Scan using idx_trx_pelanggan on transaksi  (cost=0.42..8.44 rows=1 width=60) (actual time=0.03..0.04 rows=100 loops=1)
  Index Cond: (pelanggan_id = 4242)
  Buffers: shared hit=105
Planning Time: 0.15 ms
Execution Time: 0.07 ms
```

| Bagian | Arti |
|---|---|
| `cost=0.42..8.44` | Biaya **startup** .. biaya **total** (satuan abstrak, bukan milidetik) |
| `rows=1` | Estimasi planner untuk jumlah baris keluaran |
| `actual time=..` | Waktu nyata (ms) — startup..total **per loop** |
| `rows=100 loops=1` | Baris nyata dan berapa kali node dijalankan |
| `Buffers: shared hit/read` | `hit` = dari cache PostgreSQL; `read` = dari disk/OS cache |

**Tanda bahaya**: selisih besar antara `rows` estimasi dan aktual (mis. estimasi 1, aktual 100.000) berarti statistik buruk dan planner kemungkinan salah memilih rencana.

### 10.3 Node Penting dalam Rencana

| Kategori | Node | Catatan |
|---|---|---|
| **Scan** | Seq Scan, Index Scan, Index Only Scan, Bitmap Heap Scan | Lihat [Modul 9](09-index.md) |
| **Join** | **Nested Loop** | Baik untuk sedikit baris luar + index pada sisi dalam |
| | **Hash Join** | Membangun hash table dari sisi kecil; baik untuk join besar tanpa urutan |
| | **Merge Join** | Kedua sisi sudah terurut; baik untuk dataset besar terurut |
| **Agregasi** | HashAggregate, GroupAggregate | |
| **Urut** | Sort (in-memory / `external merge` ke disk), Incremental Sort | `external merge Disk:` berarti `work_mem` kurang |
| **Paralel** | Gather, Parallel Seq Scan | Pekerja paralel ikut query |
| **Lain** | Limit, Materialize, CTE Scan, Memoize | |

Cara membaca: rencana berupa **pohon** — baca dari node **paling menjorok (paling dalam)** ke luar. Node anak memberi baris kepada induknya.

### 10.4 Alat Bantu Analisis Rencana

| Alat | Fungsi |
|---|---|
| **explain.depesz.com** | Tempel hasil `EXPLAIN ANALYZE`; sorot node paling lambat |
| **explain.dalibo.com (PEV2)** | Visualisasi grafis pohon rencana |
| **pgMustard**, **Tensor** | Analisis rencana dengan saran |
| **`auto_explain`** (extension) | Log otomatis rencana query yang lambat |
| **`pg_stat_statements`** | Statistik agregat per query (waktu total, rata-rata, jumlah panggilan) — temukan query yang paling perlu dioptimalkan ([Modul 16](16-monitoring-troubleshooting.md)) |

### 10.5 Parameter yang Memengaruhi Planner

| Parameter | Fungsi |
|---|---|
| `work_mem` | Memori per operasi sort/hash; kecil → spill ke disk |
| `effective_cache_size` | Perkiraan cache total (OS + PG); memengaruhi pilihan index scan |
| `random_page_cost` | Biaya baca acak; default 4.0, untuk SSD sering diturunkan (mis. 1.1–2.0) |
| `default_statistics_target` | Detail statistik (default 100); naikkan untuk kolom dengan distribusi rumit |
| `enable_seqscan`, `enable_nestloop`, ... | Untuk **diagnosis saja** (jangan dimatikan permanen) |
| `max_parallel_workers_per_gather` | Jumlah worker paralel per query |

Statistik diperluas dengan **`CREATE STATISTICS`** untuk korelasi antar kolom (mis. `kota` dan `kode_pos`) yang tidak ditangkap statistik per kolom.

### 10.6 Alur Optimasi Query

1. **Temukan** query lambat (`pg_stat_statements`, log lambat).
2. **Ukur** dengan `EXPLAIN (ANALYZE, BUFFERS)`.
3. **Cari** node dengan waktu terbesar dan selisih estimasi vs aktual.
4. **Perbaiki**: tambah/ubah index, `ANALYZE`, tulis ulang query, naikkan `work_mem` untuk sesi, ubah skema.
5. **Verifikasi** dengan mengukur ulang. Jangan menebak.

Anti-pola umum: `SELECT *`, `OFFSET` besar, fungsi pada kolom ber-index di `WHERE`, N+1 query dari aplikasi, join tanpa kondisi (cartesian), `DISTINCT` untuk menutupi join yang salah, dan `OR` antar kolom berbeda tanpa index yang sesuai.

## Praktik

Gunakan tabel `transaksi` (1 juta baris) dari Modul 9.

```bash
docker exec -it pg-latihan psql -U postgres -d toko
```

### Rencana Sederhana

```sql
SET search_path TO app, public;

-- 1) Rencana sederhana
EXPLAIN SELECT * FROM transaksi WHERE pelanggan_id = 4242;
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM transaksi WHERE pelanggan_id = 4242;
```

### Seq Scan vs Index Scan

```sql
-- 2) Seq Scan vs Index Scan: ubah selektivitas
EXPLAIN SELECT * FROM transaksi WHERE pelanggan_id < 10;       -- sedikit baris: index
EXPLAIN SELECT * FROM transaksi WHERE pelanggan_id < 9000;     -- banyak baris: Seq Scan

-- 3) Diagnosis: matikan seqscan sementara untuk membandingkan biaya
SET enable_seqscan = off;
EXPLAIN SELECT * FROM transaksi WHERE pelanggan_id < 9000;
RESET enable_seqscan;
```

### Join dan Algoritmanya

```sql
-- 4) Join dan algoritmanya
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.nama, count(*), sum(t.total)
FROM transaksi t JOIN pelanggan p ON p.id = t.pelanggan_id
WHERE t.status = 'selesai'
GROUP BY p.nama;
```

### work_mem dan Sort ke Disk

```sql
-- 5) work_mem dan sort ke disk
SET work_mem = '64kB';
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM transaksi ORDER BY total DESC LIMIT 100000;   -- 'external merge Disk'
SET work_mem = '256MB';
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM transaksi ORDER BY total DESC LIMIT 100000;   -- 'quicksort Memory'
RESET work_mem;
```

### Statistik Planner

```sql
-- 6) Statistik
SELECT attname, n_distinct, most_common_vals, correlation
FROM pg_stats WHERE tablename = 'transaksi' AND attname IN ('status','pelanggan_id');

-- 7) Statistik usang: tambah banyak data tanpa ANALYZE
INSERT INTO transaksi SELECT g+2000000, 1, 'baru', 1, now(), 'x'||g FROM generate_series(1,200000) g;
EXPLAIN SELECT * FROM transaksi WHERE pelanggan_id = 1;    -- estimasi 'rows' jauh dari kenyataan
ANALYZE transaksi;
EXPLAIN SELECT * FROM transaksi WHERE pelanggan_id = 1;    -- estimasi membaik
```

### EXPLAIN ANALYZE yang Aman untuk DML

```sql
-- 8) EXPLAIN ANALYZE aman untuk DML
BEGIN;
EXPLAIN ANALYZE UPDATE transaksi SET total = total + 1 WHERE pelanggan_id = 5;
ROLLBACK;
```

### Visualisasi Rencana

Tempel hasil `EXPLAIN (ANALYZE, BUFFERS)` ke **explain.depesz.com** atau **explain.dalibo.com** dan temukan node paling lambat.

## Latihan

1. Jalankan query join `transaksi` dengan `pelanggan` dan catat node join yang dipilih. Ubah `enable_hashjoin = off` lalu `enable_nestloop = off` dan bandingkan waktu eksekusinya. Mengapa setting ini hanya untuk diagnosis?
2. Cari query dengan `Sort Method: external merge`. Naikkan `work_mem` **hanya untuk sesi** dan ukur perbedaannya. Mengapa menaikkan `work_mem` global berbahaya (petunjuk: dipakai **per operasi per koneksi**)?
3. Buat situasi di mana estimasi `rows` meleset jauh dari aktual (tambah banyak data tanpa `ANALYZE`), lalu perbaiki. Jelaskan peran autovacuum dalam mencegah masalah ini.
4. Ambil satu query lambat buatan Anda, optimalkan dengan langkah 1–5 pada 10.6, dan dokumentasikan waktu sebelum/sesudah beserta perubahan yang dilakukan.
5. Jelaskan perbedaan **Nested Loop**, **Hash Join**, dan **Merge Join**, dan kapan planner cenderung memilih masing-masing.
6. Diskusikan: mengapa `EXPLAIN ANALYZE` pada sistem yang sedang sibuk bisa menyesatkan (cache panas vs dingin, lock, beban lain), dan bagaimana `BUFFERS` membantu menginterpretasi hasilnya?

---

[← Modul 9: Index & Use Case-nya](09-index.md) · [Daftar Isi](README.md#daftar-isi) · [Modul 11: Desain Schema & Pola Aplikasi →](11-desain-schema-pola.md)
