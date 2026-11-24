# Jawaban Modul 5: DML: Query, Filter & Modifikasi Data

## Status eksekusi (baca dulu)

PostgreSQL dan Docker tidak tersedia di lingkungan saya, jadi **tidak ada perintah di modul ini yang sudah dijalankan di PostgreSQL**. Berbeda dari modul sebelumnya, sebagian besar isi modul ini adalah SQL standar, sehingga logikanya bisa saya uji nyata dengan SQLite.

| Yang | Status |
|---|---|
| Logika query, upsert, cascade, ROLLBACK, perbandingan CSV | **Diuji di SQLite**: 22 pemeriksaan, semuanya sesuai harapan (`output_verifikasi_sqlite.txt`). `seed.sql` dan `CREATE TABLE` yang dipakai adalah teks asli modul. |
| Sintaks PostgreSQL (`ILIKE`, `::`, `date_trunc`, `\copy`, `LIKE ... INCLUDING`, format `numeric`) | **Belum dijalankan**. Hasilnya berlabel **(diharapkan)**. |
| Error `column "h" does not exist` (Latihan 3) | **Tidak bisa dibuktikan di SQLite**: SQLite justru menerima alias di `WHERE`. Ini murni pengetahuan tentang PostgreSQL. |

| Berkas | Fungsi |
|---|---|
| `seed.sql` | Seed Data (disalin dari modul). **`TRUNCATE` menghapus semua data `app.*`.** |
| `praktik.sql` | Query, Modifikasi, COPY (disalin dari modul; satu perubahan: path CSV `/tmp/produk.csv`) |
| `latihan.sql` | Latihan 1-5 |
| `jalankan.sh` | `seed`, `praktik`, `latihan`, `semua` |
| `skema_dasar.sql`, `verifikasi_sqlite.py`, `output_verifikasi_sqlite.txt` | Bukti logika di SQLite |

**Urutan:** `./jalankan.sh seed` → `praktik` → `latihan`. Prasyarat: Modul 4 selesai (schema `app` dan empat tabel ada).

---

## Praktik

### Seed Data

**(diharapkan)** `TRUNCATE ... RESTART IDENTITY` lalu empat `INSERT` dengan hasil `INSERT 0 4`, `INSERT 0 5`, `INSERT 0 5`, `INSERT 0 6`. Jumlah baris 4/5/5/6 terverifikasi di SQLite. `RESTART IDENTITY` membuat ID kembali ke 1, sehingga `pesanan_id`/`produk_id` yang ditulis manual di seed sesuai.

### Query dan Filter

Hasil terverifikasi di SQLite (data seed sama):

| Query | Hasil |
|---|---|
| `harga BETWEEN 100000 AND 1000000 ORDER BY harga DESC` | Keyboard Mekanik 850000, Headset 450000, Mouse Nirkabel 150000 |
| `CASE ... status_stok` | LP-001 aman, MS-001 aman, KB-001 aman, MN-001 **menipis**, HP-001 **habis** |
| `ORDER BY harga DESC LIMIT 3 OFFSET 1` | Monitor 24 inci, Keyboard Mekanik, Headset |

Perhatikan `LP-001` berstok 10: `stok < 10` salah, jadi labelnya `aman`, bukan `menipis`.

**(diharapkan)** untuk yang khas PostgreSQL:

- `nama ILIKE '%mouse%'` → `Mouse Nirkabel`. (Di SQLite saya memakai `LIKE`, yang tidak peka huruf besar/kecil untuk ASCII, hanya sebagai pendekatan.)
- `harga * 1.11 AS harga_ppn`: `harga` bertipe `numeric(12,2)`, dikali `1.11` (skala 2), sehingga hasilnya **berskala 4**. Nilai yang saya hitung dengan `Decimal`:

  | sku | harga_ppn |
  |---|---|
  | LP-001 | 13875000.0000 |
  | MS-001 | 166500.0000 |
  | KB-001 | 943500.0000 |
  | MN-001 | 2442000.0000 |
  | HP-001 | 499500.0000 |

  Angka 1.11 di sini hanya contoh latihan. Tarif pajak berubah dan bergantung pada jenis barang, jadi jangan di-*hardcode* di aplikasi nyata.
- `date_trunc('month', dibuat_pada) ... GROUP BY 1`: satu baris dengan `count = 5`, yaitu awal bulan saat Anda menjalankannya. Seluruh pesanan dibuat dengan `now()`. Tanggal dan zona waktu bergantung pada sesi Anda (default image Docker: UTC).

### Modifikasi Data

Terverifikasi di SQLite:

| Langkah | Hasil |
|---|---|
| `UPDATE ... SET stok = stok - 1 WHERE sku = 'MS-001' RETURNING sku, stok` | `MS-001 | 99` |
| `INSERT ... ON CONFLICT (sku) DO UPDATE ... RETURNING *` | Satu baris: `id = 2`, harga `165000`, stok `80`. **Jumlah produk tetap 5**: baris lama diperbarui, tidak ada baris baru. |
| `BEGIN; DELETE ... 'batal'; ROLLBACK;` | Satu pesanan (id 5) terhapus di dalam transaksi, lalu kembali setelah `ROLLBACK` |

**(diharapkan)** psql menampilkan `DELETE 1` untuk perintah di dalam transaksi.

Catatan: setelah Praktik, `MS-001` tersimpan dengan harga 165000 dan stok 80, bukan nilai seed. Ini tidak mengganggu Modul 6.

### Import/Export dengan COPY

**(diharapkan)** `\copy ... TO` mencetak `COPY 5`, `\copy ... FROM` mencetak `COPY 5`, dan `SELECT count(*) FROM produk_import` menghasilkan `5`.

Dua hal yang perlu diperhatikan:

1. **Path di dalam container.** `\copy` memakai file di mesin tempat `psql` berjalan. Pada `docker exec`, itu berarti **di dalam container**. Karena itu skrip memakai path absolut `/tmp/produk.csv`, dan bukan `produk.csv` seperti di teks modul (lokasi relatifnya bergantung pada direktori kerja container). Untuk mengambilnya ke host: `docker cp pg-latihan:/tmp/produk.csv .`.
2. **`INCLUDING DEFAULTS INCLUDING IDENTITY`** menyalin default dan identity (dengan sequence baru milik tabel sementara). Kolom `kategori` (hasil Modul 4) yang `NOT NULL DEFAULT 'umum'` tetap terisi karena `\copy` tidak menyertakannya. `LIKE` otomatis menyalin `NOT NULL`, tetapi **tidak** menyalin `CHECK` bila tanpa `INCLUDING CONSTRAINTS`.

---

## Latihan 1: Stok di bawah 20 dengan label `kritis`

```sql
SELECT sku, nama, stok,
       CASE WHEN stok = 0 THEN 'kritis' ELSE 'rendah' END AS label
FROM produk
WHERE stok < 20
ORDER BY stok ASC;
```

Hasil (terverifikasi di SQLite):

| sku | nama | stok | label |
|---|---|---|---|
| HP-001 | Headset | 0 | kritis |
| MN-001 | Monitor 24 inci | 5 | rendah |
| LP-001 | Laptop 14 inci | 10 | rendah |

Soal hanya meminta label `'kritis'` untuk stok 0, jadi saya memberi `'rendah'` pada sisanya agar kolomnya tidak NULL. Tanpa `ELSE`, `CASE` menghasilkan NULL untuk baris yang tidak cocok. Setelah Latihan 2, `KB-001` berstok 35 dan tetap tidak masuk daftar.

---

## Latihan 2: Tambah stok `KB-001` sebanyak 10 tanpa membaca stok lama

```sql
INSERT INTO produk (sku, nama, harga, stok)
VALUES ('KB-001', 'Keyboard Mekanik', 850000, 10)
ON CONFLICT (sku) DO UPDATE
   SET stok = produk.stok + EXCLUDED.stok
RETURNING sku, stok;
```

Hasil: `KB-001 | 35` (dari 25). Terverifikasi di SQLite.

**Cara kerja:**

- `produk.stok` adalah nilai baris yang **sudah ada** di tabel. `EXCLUDED.stok` adalah nilai baris yang **diusulkan** (10).
- Karena `sku` sudah ada, terjadi konflik pada unique index `sku`, lalu `DO UPDATE` berjalan.
- Aplikasi tidak perlu `SELECT stok` terlebih dulu. Pola "baca → hitung di aplikasi → tulis" rawan *lost update* bila dua proses berjalan bersamaan. Di sini penambahan dilakukan di dalam database pada baris yang terkunci, sehingga dua permintaan serentak menghasilkan +20 yang benar.

**Hal yang sering terlewat:**

| Hal | Penjelasan |
|---|---|
| Kolom wajib tetap harus diisi | `nama` dan `harga` bersifat `NOT NULL` tanpa default, jadi harus ada di `VALUES`, walau akhirnya tidak dipakai saat konflik |
| **Tidak idempoten** | Menjalankannya dua kali menambah 20. Terverifikasi: stok 25 → 35 → 45 |
| `CHECK` dievaluasi pada baris usulan | Mengurangi stok dengan nilai negatif lewat pola ini (mis. `-30`) ditolak oleh `CHECK (stok >= 0)` pada baris usulan, meski hasil penjumlahannya mungkin tidak negatif. Terverifikasi di SQLite. Untuk pengurangan stok, pakai `UPDATE ... SET stok = stok - n WHERE sku = ... AND stok >= n`. Perilaku urutan pemeriksaan ini di PostgreSQL berdasarkan pengetahuan saya, belum diuji. |
| Alias tabel | Jika tabelnya diberi alias (`INSERT INTO produk AS p`), sisi kanan harus memakai `p.stok`, bukan `produk.stok` |

Untuk mengembalikan data ke nilai seed (opsional): `UPDATE produk SET stok = 25 WHERE sku = 'KB-001';`.

---

## Latihan 3: Alias di `WHERE`

```sql
SELECT harga*1.11 AS h FROM produk WHERE h > 1000000;
```

**(diharapkan)** `ERROR: column "h" does not exist`.

**Penyebab:** urutan eksekusi logis (tabel 5.3): `FROM` → `WHERE` → `GROUP BY` → `HAVING` → **`SELECT`** → `DISTINCT` → `ORDER BY` → `LIMIT`. `WHERE` berjalan **sebelum** `SELECT`, jadi alias `h` yang baru dibuat di tahap `SELECT` belum ada. Sebaliknya, `ORDER BY` berjalan sesudah `SELECT`, jadi boleh memakai alias.

Catatan: ini perilaku **standar SQL dan PostgreSQL**, tidak berlaku universal. SQLite dan MySQL menerima alias di `WHERE`. Karena itu perbaikan di bawah ini terverifikasi di SQLite, tetapi **error aslinya tidak** (SQLite tidak menghasilkannya).

**Perbaikan 1: ulangi ekspresi**

```sql
SELECT harga*1.11 AS h FROM produk WHERE harga*1.11 > 1000000 ORDER BY h;
```

**Perbaikan 2: subquery**

```sql
SELECT h FROM (SELECT harga*1.11 AS h FROM produk) AS t WHERE h > 1000000 ORDER BY h;
```

Hasil kedua cara (terverifikasi): dua baris, yaitu **Monitor (2.442.000)** dan **Laptop (13.875.000)**. Di PostgreSQL ditampilkan dengan skala 4: `2442000.0000` dan `13875000.0000`. Keyboard (943.500) dan lainnya di bawah 1.000.000.

Perbandingan: cara 1 singkat, tetapi ekspresi yang panjang harus ditulis dua kali (risiko tidak sinkron). Cara 2 menulis ekspresi sekali. Planner PostgreSQL umumnya menggabungkan subquery sederhana seperti ini ke query induknya, jadi biasanya tidak ada penalti performa. Alternatif lain: CTE (`WITH t AS (...)`) atau `CROSS JOIN LATERAL (SELECT harga*1.11 AS h) x`.

---

## Latihan 4: `DELETE ... RETURNING` di dalam transaksi

```sql
BEGIN;
DELETE FROM pesanan WHERE status = 'batal' RETURNING id;
SELECT count(*) FROM item_pesanan WHERE pesanan_id = 5;   -- cek item terkait
ROLLBACK;
```

Hasil (terverifikasi di SQLite):

| Tahap | `pesanan` | `item_pesanan` |
|---|---|---|
| Sebelum | 5 | 6 |
| Di dalam transaksi, setelah `DELETE` (RETURNING id → **5**) | 4 | **5** |
| Setelah `ROLLBACK` | 5 | 6 |

Pesanan 5 (status `batal`) terhapus, dan **satu item miliknya (Headset) ikut terhapus** lewat `ON DELETE CASCADE` pada `item_pesanan.pesanan_id`. Setelah `ROLLBACK` keduanya kembali. Ini sekaligus membuktikan DML bersifat transaksional.

Catatan: `latihan.sql` menghitung total baris. Bila ingin memverifikasi langsung, jalankan `SELECT count(*) FROM item_pesanan WHERE pesanan_id = 5;` di dalam transaksi. **(diharapkan)** hasilnya `0` di dalam transaksi dan `1` setelah rollback.

---

## Latihan 5: Ekspor CSV, ubah harga, impor, bandingkan

`latihan.sql` mengerjakan seluruh alur dalam **satu sesi psql** (tabel `TEMP` hanya hidup selama sesi):

1. `\copy (SELECT ... ORDER BY sku) TO '/tmp/produk.csv' WITH (FORMAT csv, HEADER true)`
2. `\! sed -i '/^KB-001,/s/,850000.00,/,900000.00,/' /tmp/produk.csv`: `\!` menjalankan perintah shell di tempat `psql` berjalan (di dalam container)
3. `CREATE TEMP TABLE produk_import (LIKE produk INCLUDING DEFAULTS INCLUDING IDENTITY)`, lalu `\copy produk_import (...) FROM ...`
4. Bandingkan:

```sql
SELECT p.sku, p.harga AS harga_asli, i.harga AS harga_csv
FROM produk p JOIN produk_import i USING (sku)
WHERE p.harga IS DISTINCT FROM i.harga;
```

**Isi CSV yang diharapkan** (harga tampil 2 desimal karena `numeric(12,2)`; saya menyusun isinya dari data seed setelah Praktik):

```
sku,nama,harga,stok
HP-001,Headset,450000.00,0
KB-001,Keyboard Mekanik,850000.00,25
LP-001,Laptop 14 inci,12500000.00,10
MN-001,Monitor 24 inci,2200000.00,5
MS-001,Mouse Nirkabel,165000.00,80
```

(Jika Latihan 2 sudah dijalankan, stok `KB-001` tertulis `35`.)

Logika perbandingan terverifikasi (dengan modul `csv` Python dan SQLite): perubahan tepat **satu baris**; jumlah baris 5 vs 5; selisih harga hanya **KB-001: 850000 → 900000**; `EXCEPT` dua arah menemukan 2 baris (versi lama dan versi baru).

**Mengapa `IS DISTINCT FROM`, bukan `<>`:** `<>` menghasilkan NULL bila salah satu sisi NULL, sehingga perbedaan yang melibatkan NULL tidak terdeteksi. `IS DISTINCT FROM` memperlakukan NULL sebagai nilai biasa.

Alternatif membandingkan semua kolom sekaligus: `EXCEPT` di kedua arah (ada di `latihan.sql`).

**Jika file CSV Anda ingin diedit di host:** `docker cp pg-latihan:/tmp/produk.csv .`, edit, lalu `docker cp produk.csv pg-latihan:/tmp/` sebelum `\copy ... FROM`.

---

## Latihan 6: `DELETE` vs `TRUNCATE` vs `DROP TABLE`

| | `DELETE` | `TRUNCATE` | `DROP TABLE` |
|---|---|---|---|
| Yang dihapus | Baris yang cocok `WHERE` (atau semua) | **Semua** baris | Seluruh tabel (struktur + data + index) |
| Bisa pakai `WHERE` | Ya | Tidak | Tidak |
| Kecepatan untuk semua baris | **Lambat**, memproses baris satu per satu | **Sangat cepat**, membuang berkas data sekaligus | Sangat cepat |
| Trigger per baris | Ya | Tidak (hanya trigger `TRUNCATE`) | Tidak |
| Jejak WAL | Besar | Kecil | Kecil |
| Ruang disk | **Tidak langsung kembali** (baris mati menunggu `VACUUM`) | Langsung dilepas | Langsung dilepas |
| Struktur tabel | Tetap | Tetap | **Hilang** |
| Transaksional | Ya | Ya (bisa `ROLLBACK` di PostgreSQL) | Ya |
| Kunci | Kunci baris | `ACCESS EXCLUSIVE` pada tabel | `ACCESS EXCLUSIVE` |

**Untuk mengosongkan tabel log 100 juta baris: `TRUNCATE`.**

Alasan:

- `DELETE` seluruh 100 juta baris menghasilkan 100 juta *baris mati* (MVCC), WAL yang sangat besar, transaksi panjang, dan tabel yang membengkak sampai `VACUUM`. Ruang disk tidak langsung kembali.
- `TRUNCATE` hanya mengganti berkas data tabel, hampir seketika, dengan sedikit WAL, dan ruang langsung kembali. Index ikut dikosongkan.
- `DROP TABLE` terlalu jauh bila tabelnya masih dipakai, karena struktur, index, dan hak aksesnya ikut hilang.

**Peringatan `TRUNCATE`:**

- Butuh kunci `ACCESS EXCLUSIVE`: semua query lain ke tabel itu menunggu.
- Ditolak bila tabel direferensikan foreign key dari tabel lain, kecuali ikut di-`TRUNCATE` bersama atau memakai `CASCADE` (yang juga mengosongkan tabel anak). Itu sebabnya seed di Praktik menulis `TRUNCATE item_pesanan, pesanan, produk, pelanggan`.
- Tambahkan `RESTART IDENTITY` bila ID harus mulai dari 1 lagi.
- Transaksi lain dengan snapshot lama akan melihat tabel kosong setelah `TRUNCATE` commit (tidak sepenuhnya aman terhadap MVCC, sesuai dokumentasi).
- Tidak ada `WHERE`. Jika yang ingin dibuang hanya data lama (mis. log > 90 hari), pakai **partisi per waktu** lalu `DROP` partisi lama (Modul 11), atau `DELETE` bertahap dalam batch dengan `VACUUM`.

---

## Lembar hasil Anda

| Langkah | Hasil Anda | Sesuai harapan? |
|---|---|---|
| Seed: `INSERT 0 4/5/5/6` | | |
| `harga * 1.11` tampil dengan 4 desimal | | |
| `ILIKE '%mouse%'` | | |
| `date_trunc` menghasilkan 1 baris, `count = 5` | | |
| Upsert `MS-001`: harga 165000, stok 80 | | |
| `COPY 5` untuk ekspor dan impor | | |
| Latihan 1: HP-001, MN-001, LP-001 | | |
| Latihan 2: stok `KB-001` = 35 | | |
| Latihan 3: error `column "h" does not exist` | | |
| Latihan 4: item 6 → 5 → 6 | | |
| Latihan 5: hanya `KB-001` yang berbeda (850000 vs 900000) | | |

## Sebelum lanjut ke Modul 6

Modul 6 memakai seed dari modul ini. Jangan jalankan `seed.sql` lagi sebelum selesai, kecuali Anda memang ingin data kembali ke keadaan awal. Praktik dan Latihan mengubah dua data: `MS-001` (harga 165000, stok 80) dan stok `KB-001` (35 bila Latihan 2 dijalankan). Perubahan itu tidak memengaruhi query di Modul 6 yang saya periksa (mis. `harga > avg(harga)` tetap hanya memilih Laptop). Untuk kembali tepat ke seed: `./jalankan.sh seed`.
