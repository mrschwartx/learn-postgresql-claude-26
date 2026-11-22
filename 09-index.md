# Modul 9: Index & Use Case-nya

[← Modul 8: Advanced SQL & PL/pgSQL](08-advanced-sql-plpgsql.md) · [Daftar Isi](README.md#daftar-isi) · [Modul 10: Query Planner & EXPLAIN →](10-query-planner-explain.md)

**Isi modul ini**

- [Teori](#teori)
  - [9.1 Apa itu Index dan Mengapa Penting?](#91-apa-itu-index-dan-mengapa-penting)
  - [9.2 Jenis Index di PostgreSQL](#92-jenis-index-di-postgresql)
  - [9.3 Varian dan Teknik Index](#93-varian-dan-teknik-index)
  - [9.4 Metode Scan](#94-metode-scan)
  - [9.5 Kapan Index Tidak Dipakai?](#95-kapan-index-tidak-dipakai)
  - [9.6 Pemeliharaan Index](#96-pemeliharaan-index)
- [Praktik](#praktik)
  - [Membuat Data Besar](#membuat-data-besar)
  - [Sebelum dan Sesudah Index](#sebelum-dan-sesudah-index)
  - [Index Komposit, Partial, Expression, Covering](#index-komposit-partial-expression-covering)
  - [GIN untuk JSONB dan Trigram](#gin-untuk-jsonb-dan-trigram)
  - [BRIN dan Audit Index](#brin-dan-audit-index)
- [Latihan](#latihan)

---


## Teori

### 9.1 Apa itu Index dan Mengapa Penting?

**Index** adalah struktur data terpisah yang mempercepat pencarian baris tanpa membaca seluruh tabel (*sequential scan*). Analogi: indeks di belakang buku — Anda langsung ke halaman yang dituju, bukan membaca dari awal.

| Aspek | Tanpa index | Dengan index |
|---|---|---|
| Pencarian | Baca seluruh tabel — O(n) | Navigasi struktur — mis. O(log n) untuk B-Tree |
| `INSERT`/`UPDATE`/`DELETE` | Lebih cepat | **Lebih lambat** (index ikut diperbarui) |
| Ruang disk | Hanya tabel | Tabel + setiap index |

**Index adalah trade-off**: mempercepat baca, memperlambat tulis, dan memakan ruang. Jangan membuat index "untuk berjaga-jaga".

### 9.2 Jenis Index di PostgreSQL

| Tipe | Operator utama | Use case |
|---|---|---|
| **B-Tree** (default) | `=`, `<`, `<=`, `>`, `>=`, `BETWEEN`, `LIKE 'abc%'`, `ORDER BY` | Hampir semua kasus umum |
| **Hash** | `=` saja | Pencarian kesamaan murni (jarang lebih unggul dari B-Tree) |
| **GiST** | Overlap, kedekatan, containment | Geometri (PostGIS), range, exclusion constraint, full-text, nearest-neighbor |
| **SP-GiST** | Pencarian partisi ruang | Data tidak seimbang: titik, trie, IP, teks prefix |
| **GIN** | `@>`, `?`, `@@` (banyak nilai per baris) | `jsonb`, array, **full-text search**, `pg_trgm` |
| **BRIN** | Rentang blok | Tabel **sangat besar** dengan data berkorelasi fisik (mis. timestamp insert-only); ukuran index sangat kecil |

```sql
CREATE INDEX idx_pesanan_pelanggan ON pesanan (pelanggan_id);                  -- B-Tree
CREATE INDEX idx_dokumen_gin ON dokumen USING gin (data jsonb_path_ops);       -- GIN
CREATE INDEX idx_log_brin ON log_aktivitas USING brin (dibuat_pada);           -- BRIN
```

### 9.3 Varian dan Teknik Index

| Teknik | Contoh | Manfaat |
|---|---|---|
| **Multicolumn (komposit)** | `(pelanggan_id, dibuat_pada)` | Urutan kolom penting — aturan *leftmost prefix* |
| **Unique** | `CREATE UNIQUE INDEX ...` | Menegakkan keunikan |
| **Partial** | `... WHERE status = 'baru'` | Index kecil hanya untuk subset baris |
| **Expression** | `... (lower(email))` | Mempercepat query pada ekspresi/fungsi |
| **Covering (`INCLUDE`)** | `... (pelanggan_id) INCLUDE (total)` | Memungkinkan **index-only scan** |
| **Konkuren** | `CREATE INDEX CONCURRENTLY` | Tidak memblokir tulis (lebih lama, tidak bisa dalam transaksi) |

Aturan *leftmost prefix* pada index `(a, b, c)`: efektif untuk `WHERE a = ?`, `WHERE a = ? AND b = ?`, dst., tetapi **tidak** efektif untuk `WHERE b = ?` saja (pada versi lama; PostgreSQL 18 menambah *skip scan* yang membantu pada kasus tertentu, tetapi jangan mengandalkannya untuk desain).

### 9.4 Metode Scan

| Scan | Kapan dipilih planner |
|---|---|
| **Seq Scan** | Tabel kecil, atau query mengambil sebagian besar baris |
| **Index Scan** | Sedikit baris, ambil data dari tabel lewat index |
| **Index Only Scan** | Semua kolom yang diminta ada di index dan halaman "all-visible" (butuh vacuum yang sehat) |
| **Bitmap Index/Heap Scan** | Baris sedang (bukan sedikit, bukan banyak) atau menggabungkan beberapa index |

Seq Scan bukan selalu buruk — untuk query yang membaca 30% tabel, membaca berurutan seringkali lebih cepat daripada ribuan loncatan acak lewat index.

### 9.5 Kapan Index Tidak Dipakai?

| Penyebab | Contoh | Solusi |
|---|---|---|
| Fungsi pada kolom | `WHERE lower(email) = 'a'` | Expression index atau ubah query |
| Tipe tidak cocok / implicit cast | `WHERE id = '5'::text` | Samakan tipe |
| `LIKE '%abc'` (wildcard di depan) | | `pg_trgm` + GIN/GiST |
| Selektivitas rendah | `WHERE aktif = true` (90% baris) | Partial index atau terima Seq Scan |
| Statistik usang | Tabel baru di-load besar-besaran | `ANALYZE tabel` |
| Index tidak sesuai urutan kolom | | Desain ulang index komposit |

### 9.6 Pemeliharaan Index

| Masalah | Penjelasan | Tindakan |
|---|---|---|
| **Bloat** | Index membengkak karena baris mati | `REINDEX [CONCURRENTLY]`, vacuum yang baik |
| **Index tidak terpakai** | Memperlambat tulis tanpa manfaat | Cek `pg_stat_user_indexes.idx_scan = 0`, lalu `DROP INDEX` |
| **Index duplikat** | Dua index identik/redundan | Hapus salah satu |
| **Index invalid** | `CREATE INDEX CONCURRENTLY` gagal | `DROP INDEX` lalu buat ulang |

Ukuran index: `SELECT pg_size_pretty(pg_relation_size('idx_nama'));`

## Praktik

```bash
docker exec -it pg-latihan psql -U postgres -d toko
```

### Membuat Data Besar

Buat data besar (±1 juta baris):

```sql
SET search_path TO app, public;
\timing on

CREATE TABLE transaksi AS
SELECT g AS id,
       (random()*10000)::int + 1 AS pelanggan_id,
       (ARRAY['baru','dibayar','dikirim','selesai','batal'])[(random()*4)::int + 1] AS status,
       (random()*1000000)::numeric(12,0) AS total,
       now() - (random() * interval '365 days') AS dibuat_pada,
       lower('user' || g || '@contoh.com') AS email
FROM generate_series(1, 1000000) g;

ANALYZE transaksi;
SELECT pg_size_pretty(pg_total_relation_size('transaksi'));
```

### Sebelum dan Sesudah Index

```sql
EXPLAIN ANALYZE SELECT * FROM transaksi WHERE pelanggan_id = 4242;     -- Seq Scan
CREATE INDEX idx_trx_pelanggan ON transaksi (pelanggan_id);
EXPLAIN ANALYZE SELECT * FROM transaksi WHERE pelanggan_id = 4242;     -- Index/Bitmap Scan
SELECT pg_size_pretty(pg_relation_size('idx_trx_pelanggan'));
```

### Index Komposit, Partial, Expression, Covering

```sql
CREATE INDEX idx_trx_pel_waktu ON transaksi (pelanggan_id, dibuat_pada DESC);
EXPLAIN SELECT * FROM transaksi WHERE pelanggan_id = 77 ORDER BY dibuat_pada DESC LIMIT 5;

CREATE INDEX idx_trx_baru ON transaksi (dibuat_pada) WHERE status = 'baru';
EXPLAIN SELECT * FROM transaksi WHERE status = 'baru' AND dibuat_pada > now() - interval '7 days';

EXPLAIN SELECT * FROM transaksi WHERE email = 'user500@contoh.com';       -- Seq Scan
CREATE UNIQUE INDEX idx_trx_email ON transaksi (lower(email));
EXPLAIN SELECT * FROM transaksi WHERE lower(email) = 'user500@contoh.com';

CREATE INDEX idx_trx_cover ON transaksi (pelanggan_id) INCLUDE (total);
VACUUM transaksi;                                                           -- agar visibility map terisi
EXPLAIN ANALYZE SELECT pelanggan_id, total FROM transaksi WHERE pelanggan_id = 100;   -- Index Only Scan
```

### GIN untuk JSONB dan Trigram

```sql
CREATE TABLE dokumen (id serial PRIMARY KEY, data jsonb);
INSERT INTO dokumen (data)
SELECT jsonb_build_object('tag', ARRAY['a','b', 'tag' || (g % 50)], 'nilai', g)
FROM generate_series(1, 100000) g;
CREATE INDEX idx_dok_gin ON dokumen USING gin (data jsonb_path_ops);
EXPLAIN ANALYZE SELECT count(*) FROM dokumen WHERE data @> '{"tag": ["tag7"]}';

CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX idx_trx_email_trgm ON transaksi USING gin (email gin_trgm_ops);
EXPLAIN ANALYZE SELECT * FROM transaksi WHERE email LIKE '%er5000%';
```

### BRIN dan Audit Index

```sql
CREATE INDEX idx_trx_brin ON transaksi USING brin (id);
SELECT pg_size_pretty(pg_relation_size('idx_trx_brin')) AS brin,
       pg_size_pretty(pg_relation_size('idx_trx_pelanggan')) AS btree;

SELECT relname, indexrelname, idx_scan, pg_size_pretty(pg_relation_size(indexrelid)) AS ukuran
FROM pg_stat_user_indexes ORDER BY idx_scan;
```

## Latihan

1. Ukur waktu query `WHERE pelanggan_id = X` sebelum dan sesudah index. Hitung berapa kali lebih cepat, dan ukur waktu `INSERT` 100.000 baris tambahan dengan dan tanpa index tersebut untuk melihat harga yang dibayar.
2. Jelaskan mengapa index `(pelanggan_id, dibuat_pada)` bisa melayani query `WHERE pelanggan_id = 5 ORDER BY dibuat_pada DESC LIMIT 10` tanpa langkah *sort* tambahan, sedangkan index `(dibuat_pada, pelanggan_id)` tidak optimal.
3. Buat partial index untuk mempercepat daftar "pesanan yang belum dibayar" dan bandingkan ukurannya dengan index penuh pada kolom yang sama.
4. Query `WHERE lower(email) = ...` tidak memakai index biasa pada `email`. Buktikan dengan `EXPLAIN`, lalu perbaiki dengan expression index.
5. Cari semua index yang **tidak pernah dipakai** (`idx_scan = 0`) di database latihan Anda. Apa risiko menghapusnya di produksi, dan data apa lagi yang perlu Anda periksa dulu (petunjuk: replica, periode statistik)?
6. Diskusikan: kapan BRIN lebih tepat daripada B-Tree untuk tabel log 5 miliar baris, dan syarat apa yang harus dipenuhi data agar BRIN efektif?

---

[← Modul 8: Advanced SQL & PL/pgSQL](08-advanced-sql-plpgsql.md) · [Daftar Isi](README.md#daftar-isi) · [Modul 10: Query Planner & EXPLAIN →](10-query-planner-explain.md)
