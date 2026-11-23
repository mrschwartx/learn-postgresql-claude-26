# Jawaban Modul 2: Konsep Relasional & Object Model

| Berkas | Isi |
|---|---|
| `rancangan_toko.sql` | Rancangan dari modul (disalin apa adanya) |
| `rancangan_perpustakaan.sql` | Jawaban Latihan 4 (dialek PostgreSQL) |
| `verifikasi_sqlite.py` | Skrip uji logika constraint dan NULL |
| `output_verifikasi_sqlite.txt` | Output skrip: 29 pengujian sesuai harapan, 0 gagal |

> **Batasan verifikasi.** PostgreSQL tidak tersedia di lingkungan saya, dan modul ini memang tidak meminta menjalankannya (baru di Modul 4). Perilaku constraint dan logika NULL saya uji dengan **SQLite**: berkas `.sql` yang sama disalin otomatis ke dialek SQLite (`identity` → `INTEGER PRIMARY KEY`, `timestamptz` → `TEXT`, dst.). Hasilnya membuktikan **logika** rancangan, bukan bahwa DDL-nya valid di PostgreSQL. Jalankan kedua berkas `.sql` di PostgreSQL pada Modul 3-4 untuk memastikannya.

---

## Praktik: Analisis Rancangan Toko

### 1. Tabel many-to-many dan primary key komposit

**`item_pesanan`** mewakili relasi many-to-many antara `pesanan` dan `produk`. Satu pesanan berisi banyak produk, dan satu produk muncul di banyak pesanan. Relasi N:M tidak bisa dipasang langsung di salah satu sisi, sehingga dibuat tabel penghubung dengan dua FK.

PK komposit `(pesanan_id, produk_id)` berarti **kombinasi pesanan + produk hanya boleh muncul sekali**. Jika pelanggan membeli 3 unit produk yang sama, hasilnya satu baris dengan `jumlah = 3`, bukan tiga baris. PK komposit juga otomatis `NOT NULL` dan `UNIQUE`, jadi tidak perlu kolom `id` tambahan.

Bukti: memasukkan produk 1 ke pesanan 1 untuk kedua kalinya ditolak (`UNIQUE constraint failed: item_pesanan.pesanan_id, item_pesanan.produk_id`), sedangkan produk yang sama di pesanan lain lolos.

Catatan: index PK ini melayani pencarian berdasarkan `pesanan_id` ("isi pesanan X"). Pencarian "pesanan mana yang memuat produk Y" tidak terbantu, dan PostgreSQL **tidak** otomatis membuat index untuk kolom FK. Index tambahan pada `produk_id` dibahas di Modul 9.

### 2. Penghapusan `pesanan` dan `ON DELETE CASCADE`

Baris `item_pesanan` milik pesanan itu **ikut terhapus otomatis**. Hasil uji: sebelum hapus 2 item, sesudah hapus 0.

Alasannya: item tidak punya arti tanpa pesanan induknya. Tanpa `CASCADE`, penghapusan pesanan ditolak selama masih ada item, atau perlu dua `DELETE` manual yang berisiko terlewat. Perhatikan bahwa kolom lain **sengaja tidak** memakai `CASCADE`: `pesanan.pelanggan_id` dan `item_pesanan.produk_id` bersifat default (`NO ACTION`), sehingga menghapus pelanggan atau produk yang masih dipakai ditolak (diuji, hasilnya ditolak). Itu pilihan yang aman untuk data transaksi.

### 3. Constraint yang mencegah data tidak valid tanpa kode aplikasi

| Kolom | Constraint | Mencegah | Diuji |
|---|---|---|---|
| `produk.stok` | `CHECK (stok >= 0)` | Stok negatif | ditolak |
| `produk.harga` | `CHECK (harga >= 0)` | Harga negatif | ditolak |
| `item_pesanan.jumlah` | `CHECK (jumlah > 0)` | Jumlah 0 atau negatif | ditolak |
| `pelanggan.email` | `NOT NULL UNIQUE` | Email kosong atau ganda | ditolak |
| `pelanggan.nama`, `produk.nama` | `NOT NULL` | Nama kosong | ditolak |
| `pesanan.pelanggan_id` | `NOT NULL REFERENCES` | Pesanan tanpa pelanggan atau untuk pelanggan fiktif | ditolak |
| `item_pesanan` (PK komposit) | `PRIMARY KEY` | Baris item ganda | ditolak |

### Celah pada rancangan ini

Dua kelemahan yang saya temukan saat menguji (keduanya diperbaiki di rancangan final Modul 4):

1. **`pesanan.status` bebas diisi.** Nilai `'asal-asalan'` lolos (diuji). Perbaikannya `CHECK (status IN ('baru','dibayar','dikirim','selesai','batal'))` atau tipe enum.
2. **Harga tidak tersimpan di `item_pesanan`.** Jika `produk.harga` berubah, total pesanan lama ikut berubah kalau dihitung dari harga produk saat ini. Perlu kolom `harga_satuan` di `item_pesanan` yang menyalin harga saat transaksi.

Modul 4 memang menambahkan kedua hal itu (CHECK status dan `harga_satuan`), jadi rancangan di Modul 2 adalah versi awal yang disederhanakan. Hal lain yang tidak dicegah di level skema: pembelian melebihi stok pada tingkat item. Itu ditangani lewat transaksi dan `CHECK (stok >= 0)` saat stok dikurangi (Modul 7).

---

## Latihan 1: Pemetaan istilah ke tabel `produk`

```sql
CREATE TABLE produk (
    id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nama   text           NOT NULL,
    harga  numeric(12,2)  NOT NULL CHECK (harga >= 0),
    stok   integer        NOT NULL DEFAULT 0 CHECK (stok >= 0)
);
```

| Istilah formal | Pada tabel `produk` |
|---|---|
| **Relation** | Tabel `produk` itu sendiri: himpunan baris dengan struktur sama |
| **Tuple** | Satu baris, mis. `(1, 'Keyboard', 250000.00, 10)` |
| **Attribute** | Kolom `id`, `nama`, `harga`, `stok` |
| **Domain** | Nilai yang valid untuk sebuah atribut. Untuk `harga`: `numeric(12,2)` + `CHECK (harga >= 0)` (angka non-negatif, maksimum 10 digit sebelum koma). Untuk `stok`: `integer` + `CHECK (stok >= 0)` (bilangan bulat non-negatif). |
| **Degree** | 4 (jumlah kolom) |
| **Cardinality** | Jumlah baris saat ini (berubah-ubah) |

Domain bisa dibuat eksplisit agar aturan dipakai ulang di banyak tabel. Contoh yang belum saya jalankan di PostgreSQL (nanti diuji di Modul 4):

```sql
CREATE DOMAIN rupiah AS numeric(12,2) CHECK (VALUE >= 0);
-- harga rupiah NOT NULL
```

---

## Latihan 2: `WHERE email = NULL`

`NULL` berarti "tidak diketahui", jadi `email = NULL` bernilai `NULL` (UNKNOWN), bukan `true`, **untuk setiap baris**, termasuk baris yang emailnya memang NULL. `WHERE` hanya meloloskan baris yang bernilai `TRUE`, sehingga hasilnya selalu 0 baris.

Uji pada tabel dengan 2 email NULL dari 4 baris:

```
WHERE email = NULL       -> 0 baris
WHERE email IS NULL      -> 2 baris
```

Query yang benar:

```sql
SELECT * FROM pelanggan WHERE email IS NULL;
```

Catatan:
- Pada rancangan toko, `email` adalah `NOT NULL`, jadi query ini selalu kosong. Ia bermakna jika kolomnya boleh NULL.
- Hati-hati juga dengan `email <> 'a@x.com'`: baris NULL ikut tersaring (diuji: 1 baris dari 4). Untuk menyertakan NULL, pakai `email IS DISTINCT FROM 'a@x.com'` (diuji: 3 baris).
- PostgreSQL punya parameter `transform_null_equals` yang mengubah `= NULL` menjadi `IS NULL`, tetapi **nonaktif secara default** dan tidak dianjurkan.

---

## Latihan 3: Ekspresi NULL

Perhitungan manual (hasil di PostgreSQL):

| Ekspresi | Hasil | Alasan |
|---|---|---|
| `NULL OR TRUE` | **`true`** | `OR` dengan salah satu sisi `TRUE` selalu `TRUE`, apa pun sisi lainnya |
| `NULL AND FALSE` | **`false`** | `AND` dengan salah satu sisi `FALSE` selalu `FALSE` |
| `COALESCE(NULL, NULL, 3)` | **`3`** | `COALESCE` mengembalikan argumen pertama yang bukan NULL |
| `NULL IS DISTINCT FROM NULL` | **`false`** | Operator ini memperlakukan NULL sebagai nilai biasa, dan dua NULL dianggap tidak berbeda |

Verifikasi dengan SQLite (logika tiga nilai-nya sama; `IS DISTINCT FROM` di SQLite ditulis `IS NOT`):

```
NULL OR TRUE   -> 1 (true)
NULL AND FALSE -> 0 (false)
COALESCE(NULL, NULL, 3) -> 3
NULL IS NOT NULL -> 0 (false)
```

Pembanding yang diuji juga: `NULL = NULL` → NULL, `TRUE AND NULL` → NULL, `FALSE AND NULL` → false, `5 + NULL` → NULL. Verifikasi final di PostgreSQL (`SELECT NULL OR TRUE, ...`) menunggu Modul 3.

---

## Latihan 4: Skema perpustakaan

DDL lengkap ada di `rancangan_perpustakaan.sql`. Ringkasannya:

```
penulis ──< buku_penulis >── buku ──< eksemplar ──< peminjaman >── anggota
   (N:M lewat tabel penghubung)  (1:N)        (1:N)        (N:1)
```

### Relasi

| Relasi | Jenis | Implementasi |
|---|---|---|
| `penulis` ↔ `buku` | **Many-to-many** | Tabel `buku_penulis` dengan dua FK, PK komposit `(buku_id, penulis_id)` |
| `buku` → `eksemplar` | One-to-many | `eksemplar.buku_id` → `buku.id` |
| `anggota` → `peminjaman` | One-to-many | `peminjaman.anggota_id` → `anggota.id` |
| `eksemplar` → `peminjaman` | One-to-many | `peminjaman.eksemplar_id` → `eksemplar.id` |

(Secara logis `anggota` ↔ `eksemplar` adalah many-to-many, dengan `peminjaman` sebagai tabel penghubung yang membawa atribut sendiri: tanggal dan denda. Karena anggota boleh meminjam eksemplar yang sama berkali-kali dari waktu ke waktu, `peminjaman` memakai PK surrogate `id`, bukan PK komposit.)

**Mengapa ada tabel `eksemplar` terpisah dari `buku`?** Judul buku adalah satu hal, salinan fisiknya hal lain. Perpustakaan bisa punya 3 salinan judul yang sama, dan yang dipinjam adalah salinan tertentu. Tanpa tabel ini, tidak bisa dibedakan salinan mana yang sedang keluar.

### Primary key dan foreign key

| Tabel | Primary key | Foreign key (aksi hapus) |
|---|---|---|
| `penulis`, `buku`, `eksemplar`, `anggota`, `peminjaman` | `id bigint` identity (surrogate) | |
| `buku_penulis` | `(buku_id, penulis_id)` komposit | `buku_id` → `buku` (**CASCADE**), `penulis_id` → `penulis` (**RESTRICT**) |
| `eksemplar` | | `buku_id` → `buku` (RESTRICT) |
| `peminjaman` | | `anggota_id` → `anggota` (RESTRICT), `eksemplar_id` → `eksemplar` (RESTRICT) |

Riwayat peminjaman dilindungi dengan `RESTRICT`. Anggota atau eksemplar yang pernah dipakai tidak boleh dihapus begitu saja. Gunakan kolom `status`/`kondisi` untuk menonaktifkan.

### Constraint (lebih dari tiga, semuanya diuji)

| Constraint | Aturan bisnis |
|---|---|
| `buku.isbn` `UNIQUE` + `CHECK (length(isbn) = 13)` | ISBN unik dan 13 karakter |
| `buku.tahun_terbit` `CHECK BETWEEN 1450 AND 2100` | Tahun masuk akal |
| `buku_penulis` `UNIQUE (buku_id, urutan)` | Tidak ada dua "penulis pertama" |
| `eksemplar.barcode` `UNIQUE` | Barcode tidak boleh ganda |
| `eksemplar.kondisi` `CHECK IN ('baik','rusak','hilang')` | Nilai terbatas |
| `anggota.email`, `anggota.nomor_anggota` `UNIQUE` | Identitas anggota |
| `anggota.status` `CHECK IN ('aktif','ditangguhkan','nonaktif')` | Nilai terbatas |
| `peminjaman` `CHECK (jatuh_tempo >= tanggal_pinjam)` | Jatuh tempo tidak mendahului tanggal pinjam |
| `peminjaman` `CHECK (tanggal_kembali IS NULL OR tanggal_kembali >= tanggal_pinjam)` | Tanggal kembali logis |
| `peminjaman.denda` `CHECK (denda >= 0)` | Denda tidak negatif |
| **`UNIQUE INDEX ... ON peminjaman (eksemplar_id) WHERE tanggal_kembali IS NULL`** | **Satu eksemplar hanya boleh sedang dipinjam satu orang** |

Constraint terakhir adalah *partial unique index*. Uji: meminjam eksemplar yang belum kembali ditolak, dan setelah `tanggal_kembali` diisi eksemplar itu boleh dipinjam lagi. Ini mencegah peminjaman ganda **tanpa kode aplikasi**, termasuk saat dua petugas menekan tombol bersamaan. Perhatikan `tanggal_kembali` sengaja boleh NULL: NULL berarti "belum dikembalikan" dan itu informasi bisnis, bukan data hilang.

Hasil pengujian: 29 pengujian lolos sesuai harapan (lihat `output_verifikasi_sqlite.txt`).

---

## Latihan 5: Database vs Schema

| | Database | Schema |
|---|---|---|
| Posisi | Wadah terisolasi di dalam satu cluster | *Namespace* di dalam satu database |
| Koneksi | Satu koneksi terikat ke **satu** database | Satu koneksi bisa mengakses banyak schema |
| Query lintas | **Tidak bisa** dalam satu query (perlu `postgres_fdw` atau `dblink`) | Bisa: `JOIN laporan.x ON ... public.y` |
| Transaksi | Satu transaksi hanya mencakup satu database | Satu transaksi bisa mencakup banyak schema |
| Hak akses | Hak `CONNECT`; role bersifat cluster-wide | `USAGE`/`CREATE` per schema |
| Backup | `pg_dump` per database | Bisa `pg_dump -n schema`, tetapi satu database tetap satu kesatuan |

**Pakai beberapa schema dalam satu database bila:**
- Modul-modul satu aplikasi perlu dikelompokkan (`public`, `laporan`, `audit`) dan masih saling join serta berbagi transaksi.
- Perlu memisahkan hak akses (tim analitik hanya boleh baca schema `laporan`).
- Ingin menaruh extension atau objek bantu di schema tersendiri agar tidak mengotori `public`.
- Multi-tenant skala kecil sampai menengah dengan schema per tenant. Hati-hati: ribuan schema membuat migrasi dan system catalog berat.

**Pakai database terpisah bila:**
- Aplikasi atau tim berbeda dan data tidak perlu di-join.
- Perlu pengaturan berbeda: encoding, locale, atau versi extension.
- Perlu backup, restore, atau penghapusan independen.
- Perlu isolasi lebih kuat, misalnya menghindari satu aplikasi tidak sengaja membaca data aplikasi lain.

Batas yang perlu diingat: database dalam satu cluster **berbagi sumber daya** (proses, memori `shared_buffers`, WAL, `max_connections`). Untuk isolasi beban yang sungguh-sungguh, gunakan **cluster/instance terpisah**, bukan hanya database terpisah.

---

## Latihan 6: `email` sebagai `UNIQUE`, bukan primary key

**Mengapa tetap `UNIQUE`:** `id` hanya memberi identitas teknis. Aturan bisnis "satu akun per email" tetap harus ditegakkan. Tanpa `UNIQUE (email)`, dua baris dengan email sama bisa tersimpan. `UNIQUE` juga membuat index yang mempercepat login berdasarkan email.

**Kelemahan memakai `email` sebagai primary key:**

| Masalah | Penjelasan |
|---|---|
| **Email bisa berubah** | Pengguna ganti email, lalu semua tabel yang mereferensikan (`pesanan.pelanggan_email`, dst.) harus ikut diubah (`ON UPDATE CASCADE` mahal dan rawan). Surrogate key stabil. |
| **Ukuran** | `text` lebih lebar daripada `bigint` (8 byte). Ukuran itu ikut diulang di setiap FK dan index di tabel anak. |
| **Privasi** | Data pribadi tersebar ke tabel lain, URL, log, dan cache. |
| **Normalisasi** | `Andi@x.com` dan `andi@x.com` dianggap berbeda oleh `UNIQUE` biasa. Perlu `UNIQUE INDEX ON (lower(email))` atau tipe `citext`. |
| **Tidak selalu ada** | Ada pelanggan tanpa email, atau email dipakai bersama. PK tidak boleh NULL. |

Praktik umum (sesuai teori 2.6): **surrogate key sebagai primary key**, **natural key sebagai `UNIQUE`**. Catatan: `UNIQUE` di PostgreSQL menganggap setiap NULL berbeda, jadi beberapa baris dengan email NULL tetap boleh (kecuali kolomnya `NOT NULL`, seperti pada rancangan ini). Mulai PostgreSQL 15 ada opsi `UNIQUE NULLS NOT DISTINCT` bila perilaku itu tidak diinginkan.
