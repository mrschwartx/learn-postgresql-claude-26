# Modul 2: Konsep Relasional & Object Model

[← Modul 1: Pengenalan PostgreSQL](01-pengenalan.md) · [Daftar Isi](README.md#daftar-isi) · [Modul 3: Instalasi, Setup & psql →](03-instalasi-setup.md)

**Isi modul ini**

- [Teori](#teori)
  - [2.1 Relational Model: Istilah Formal vs Praktis](#21-relational-model-istilah-formal-vs-praktis)
  - [2.2 Hierarki Objek: Cluster → Database → Schema → Tabel](#22-hierarki-objek-cluster--database--schema--tabel)
  - [2.3 Tabel: Rows dan Columns](#23-tabel-rows-dan-columns)
  - [2.4 Constraint — Menjaga Integritas Data](#24-constraint--menjaga-integritas-data)
  - [2.5 NULL — Nilai "Tidak Diketahui"](#25-null--nilai-tidak-diketahui)
  - [2.6 Keys: Natural vs Surrogate](#26-keys-natural-vs-surrogate)
  - [2.7 Relasi Antar Tabel](#27-relasi-antar-tabel)
  - [2.8 Object Model PostgreSQL — Apa Saja yang Bisa Dibuat?](#28-object-model-postgresql--apa-saja-yang-bisa-dibuat)
- [Praktik](#praktik)
  - [Rancangan Skema Toko](#rancangan-skema-toko)
  - [Analisis Rancangan](#analisis-rancangan)
- [Latihan](#latihan)

---


## Teori

### 2.1 Relational Model: Istilah Formal vs Praktis

Relational model punya terminologi akademik yang sering muncul di dokumentasi dan roadmap. Berikut pemetaannya ke istilah sehari-hari:

| Istilah Formal | Istilah Praktis (SQL) | Penjelasan |
|---|---|---|
| **Relation** | Tabel | Himpunan *tuple* dengan struktur sama |
| **Tuple** | Baris (row/record) | Satu entri data |
| **Attribute** | Kolom (column) | Satu properti dengan nama dan tipe |
| **Domain** | Tipe data + constraint | Himpunan nilai valid sebuah atribut |
| **Degree** | Jumlah kolom | |
| **Cardinality** | Jumlah baris | |

**Domain** bisa dibuat eksplisit di PostgreSQL dengan `CREATE DOMAIN` — tipe turunan yang membawa constraint, sehingga aturan validasi dipakai ulang di banyak tabel:

```sql
CREATE DOMAIN email_valid AS text
  CHECK (VALUE ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$');
```

### 2.2 Hierarki Objek: Cluster → Database → Schema → Tabel

PostgreSQL mengorganisasi objek dalam hierarki bertingkat:

```
Server (instance / cluster)       <- satu proses postgres, satu port (5432)
 └── Database: toko               <- terisolasi; koneksi terikat ke satu database
      ├── Schema: public          <- namespace
      │    ├── Table: pelanggan
      │    ├── View, Index, Sequence, Function, Type ...
      └── Schema: laporan
           └── Table: penjualan_bulanan
```

| Level | Penjelasan |
|---|---|
| **Cluster** | Kumpulan database yang dikelola satu instance server dengan satu *data directory* |
| **Database** | Wadah terisolasi. **Tidak bisa** query lintas database dalam satu query (gunakan schema atau `postgres_fdw`) |
| **Schema** | *Namespace* di dalam database untuk mengelompokkan objek dan mengatur hak akses |
| **Objek** | Tabel, view, index, sequence, fungsi, tipe, dll. |

Nama lengkap objek: `database.schema.objek` — namun di SQL Anda hanya menulis `schema.objek` (database ditentukan saat koneksi). Jika schema tidak ditulis, PostgreSQL mencarinya berdasarkan **`search_path`** (default: `"$user", public`).

> **Catatan keamanan**: sejak PostgreSQL 15, pengguna biasa **tidak lagi** punya hak `CREATE` di schema `public` secara default. Lihat [Modul 13](13-security.md).

### 2.3 Tabel: Rows dan Columns

Tabel adalah struktur utama penyimpan data. Sifat penting:

- Baris pada dasarnya **tidak berurutan** — tanpa `ORDER BY`, urutan hasil tidak dijamin.
- Setiap kolom punya **tipe data** tetap.
- Setiap sel berisi satu nilai (atau `NULL`).
- Setiap tabel sebaiknya punya **primary key**.

### 2.4 Constraint — Menjaga Integritas Data

| Constraint | Fungsi | Contoh |
|---|---|---|
| `NOT NULL` | Kolom wajib diisi | `nama text NOT NULL` |
| `UNIQUE` | Nilai tidak boleh duplikat | `UNIQUE (email)` |
| `PRIMARY KEY` | Identitas unik baris (= `UNIQUE` + `NOT NULL`) | `id bigint PRIMARY KEY` |
| `FOREIGN KEY` | Referensi ke tabel lain | `REFERENCES pelanggan(id)` |
| `CHECK` | Syarat logika bebas | `CHECK (harga >= 0)` |
| `EXCLUDE` | Mencegah baris yang "bertumpuk" (khas PostgreSQL) | Pemesanan ruangan tanpa jadwal tumpang tindih |

Constraint dievaluasi oleh database pada setiap `INSERT`/`UPDATE`, sehingga berlaku untuk **semua** aplikasi yang mengakses data — bukan hanya satu service.

### 2.5 NULL — Nilai "Tidak Diketahui"

`NULL` bukan nol, bukan string kosong, dan bukan `false` — ia berarti **tidak diketahui / tidak ada nilai**. SQL memakai **logika tiga nilai** (*three-valued logic*): `TRUE`, `FALSE`, `UNKNOWN`.

| Ekspresi | Hasil |
|---|---|
| `NULL = NULL` | `NULL` (bukan true!) |
| `NULL <> 5` | `NULL` |
| `NULL IS NULL` | `true` |
| `5 + NULL` | `NULL` |
| `TRUE AND NULL` | `NULL` |
| `FALSE AND NULL` | `false` |
| `COALESCE(NULL, 'default')` | `'default'` |

Klausa `WHERE` hanya meloloskan baris yang bernilai `TRUE` — baris `UNKNOWN` ikut tersaring. Gunakan `IS NULL`, `IS NOT NULL`, atau `IS DISTINCT FROM` (perbandingan yang memperlakukan `NULL` sebagai nilai biasa).

### 2.6 Keys: Natural vs Surrogate

| Jenis | Penjelasan | Kelebihan | Kekurangan |
|---|---|---|---|
| **Natural key** | Data bisnis yang unik (NIK, email, ISBN) | Bermakna | Bisa berubah, bisa sensitif |
| **Surrogate key** | ID buatan (`bigint` identity, `uuid`) | Stabil, ringkas | Tidak punya makna bisnis |

Praktik umum: **surrogate key sebagai primary key** + **natural key sebagai `UNIQUE`**.

### 2.7 Relasi Antar Tabel

| Relasi | Implementasi |
|---|---|
| **One-to-Many** | FK di sisi "many" (`pesanan.pelanggan_id → pelanggan.id`) |
| **Many-to-Many** | **Tabel penghubung** dengan dua FK (`item_pesanan` antara `pesanan` dan `produk`) |
| **One-to-One** | FK yang juga `UNIQUE` |

### 2.8 Object Model PostgreSQL — Apa Saja yang Bisa Dibuat?

Selain tabel, PostgreSQL memiliki banyak jenis objek: **view** & **materialized view**, **index**, **sequence**, **function/procedure**, **trigger**, **type** (enum, composite, range, domain), **extension**, **role**, dan **tablespace**. Semuanya tercatat di **system catalog** (skema `pg_catalog`) yang bisa di-query seperti tabel biasa ([Modul 12](12-internal-konfigurasi.md)).

## Praktik

### Rancangan Skema Toko

Di modul ini kita belum menjalankan PostgreSQL, jadi cukup simpan DDL berikut ke berkas teks sebagai **rancangan** (akan dijalankan di PostgreSQL pada [Modul 4](04-ddl-tipe-data.md)):

```sql
-- rancangan_toko.sql
CREATE TABLE pelanggan (
    id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nama       text        NOT NULL,
    email      text        NOT NULL UNIQUE,
    dibuat_pada timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE produk (
    id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nama   text           NOT NULL,
    harga  numeric(12,2)  NOT NULL CHECK (harga >= 0),
    stok   integer        NOT NULL DEFAULT 0 CHECK (stok >= 0)
);

CREATE TABLE pesanan (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    pelanggan_id bigint NOT NULL REFERENCES pelanggan(id),
    tanggal      date   NOT NULL DEFAULT current_date,
    status       text   NOT NULL DEFAULT 'baru'
);

CREATE TABLE item_pesanan (
    pesanan_id bigint  NOT NULL REFERENCES pesanan(id) ON DELETE CASCADE,
    produk_id  bigint  NOT NULL REFERENCES produk(id),
    jumlah     integer NOT NULL CHECK (jumlah > 0),
    PRIMARY KEY (pesanan_id, produk_id)
);
```

### Analisis Rancangan

Analisis rancangan di atas dengan pertanyaan berikut:

1. Tabel mana yang mewakili relasi many-to-many? Mengapa primary key-nya **komposit**?
2. Apa yang terjadi pada `item_pesanan` jika sebuah `pesanan` dihapus? Mengapa dipilih `ON DELETE CASCADE`?
3. Kolom mana saja yang mencegah data tidak valid (stok negatif, jumlah nol) **tanpa** kode aplikasi?

## Latihan

1. Petakan istilah **relation, tuple, attribute, domain** ke tabel `produk` pada rancangan di atas.
2. Jelaskan mengapa `SELECT * FROM pelanggan WHERE email = NULL` selalu mengembalikan 0 baris, dan tulis query yang benar untuk mencari pelanggan tanpa email.
3. Hitung hasil ekspresi berikut tanpa menjalankannya, lalu verifikasi nanti di Modul 3: `NULL OR TRUE`, `NULL AND FALSE`, `COALESCE(NULL, NULL, 3)`, `NULL IS DISTINCT FROM NULL`.
4. Rancang skema untuk **perpustakaan** (buku, anggota, peminjaman, penulis). Tentukan relasi one-to-many dan many-to-many, primary key, foreign key, dan minimal tiga constraint `CHECK`/`UNIQUE`.
5. Jelaskan perbedaan **database** dan **schema** di PostgreSQL. Kapan Anda memakai beberapa schema dalam satu database dibanding beberapa database terpisah?
6. Diskusikan: mengapa `email` sebaiknya `UNIQUE` meski sudah ada `id` sebagai primary key? Apa kelemahan memakai `email` sebagai primary key?

---

[← Modul 1: Pengenalan PostgreSQL](01-pengenalan.md) · [Daftar Isi](README.md#daftar-isi) · [Modul 3: Instalasi, Setup & psql →](03-instalasi-setup.md)
