# Modul 4: DDL: Schema, Tabel & Tipe Data

[← Modul 3: Instalasi, Setup & psql](03-instalasi-setup.md) · [Daftar Isi](README.md#daftar-isi) · [Modul 5: DML: Query, Filter & Modifikasi Data →](05-dml-query-dasar.md)

**Isi modul ini**

- [Teori](#teori)
  - [4.1 DDL — Data Definition Language](#41-ddl--data-definition-language)
  - [4.2 DDL untuk Schema](#42-ddl-untuk-schema)
  - [4.3 DDL untuk Tabel](#43-ddl-untuk-tabel)
  - [4.4 Kolom Identitas, Sequence, dan Generated Column](#44-kolom-identitas-sequence-dan-generated-column)
  - [4.5 Tipe Data Utama](#45-tipe-data-utama)
  - [4.6 Constraint pada DDL](#46-constraint-pada-ddl)
  - [4.7 View dan Materialized View](#47-view-dan-materialized-view)
- [Praktik](#praktik)
  - [Membuat Schema dan Tabel](#membuat-schema-dan-tabel)
  - [Menguji Constraint dan Transactional DDL](#menguji-constraint-dan-transactional-ddl)
- [Latihan](#latihan)

---


## Teori

### 4.1 DDL — Data Definition Language

**DDL** adalah kelompok perintah SQL untuk **mendefinisikan struktur** database: `CREATE`, `ALTER`, `DROP`, `TRUNCATE`, `COMMENT`. Berbeda dengan banyak database lain, **DDL di PostgreSQL bersifat transaksional** — Anda bisa membungkus `CREATE`/`ALTER`/`DROP` dalam `BEGIN ... ROLLBACK`.

### 4.2 DDL untuk Schema

| Perintah | Fungsi |
|---|---|
| `CREATE SCHEMA nama [AUTHORIZATION role]` | Buat schema |
| `CREATE SCHEMA IF NOT EXISTS nama` | Buat jika belum ada |
| `ALTER SCHEMA nama RENAME TO baru` | Ganti nama |
| `DROP SCHEMA nama [CASCADE]` | Hapus (`CASCADE` ikut menghapus isinya) |
| `SET search_path TO laporan, public` | Atur urutan pencarian schema untuk sesi |

### 4.3 DDL untuk Tabel

```sql
CREATE TABLE IF NOT EXISTS produk (
    id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sku     text           NOT NULL UNIQUE,
    nama    text           NOT NULL,
    harga   numeric(12,2)  NOT NULL CHECK (harga >= 0),
    stok    integer        NOT NULL DEFAULT 0
);
```

| Perintah `ALTER TABLE` | Fungsi |
|---|---|
| `ADD COLUMN kolom tipe` | Tambah kolom |
| `DROP COLUMN kolom` | Hapus kolom |
| `ALTER COLUMN kolom TYPE tipe USING ekspresi` | Ubah tipe (mungkin menulis ulang tabel!) |
| `ALTER COLUMN kolom SET NOT NULL` / `DROP NOT NULL` | Ubah nullability |
| `ALTER COLUMN kolom SET DEFAULT x` | Ubah default |
| `ADD CONSTRAINT nama ...` / `DROP CONSTRAINT nama` | Kelola constraint |
| `RENAME COLUMN a TO b` / `RENAME TO baru` | Ganti nama |

Perintah penghapusan data:

| Perintah | Efek |
|---|---|
| `DROP TABLE t` | Hapus tabel **beserta strukturnya** |
| `TRUNCATE TABLE t` | Kosongkan semua baris sangat cepat (struktur tetap); `RESTART IDENTITY` mengatur ulang sequence; `CASCADE` ikut mengosongkan tabel yang mereferensinya |
| `DELETE FROM t` | Hapus baris per baris (bisa pakai `WHERE`, memicu trigger, lambat untuk tabel besar) |

### 4.4 Kolom Identitas, Sequence, dan Generated Column

| Cara | Contoh | Catatan |
|---|---|---|
| **Identity** (disarankan, standar SQL) | `id bigint GENERATED ALWAYS AS IDENTITY` | `ALWAYS` menolak nilai manual; `BY DEFAULT` mengizinkannya |
| **`serial` / `bigserial`** | `id bigserial` | Cara lama (sequence + default); masih umum di kode lama |
| **UUID** | `id uuid DEFAULT gen_random_uuid()` | Tersebar acak; sejak PG 18 tersedia `uuidv7()` yang terurut waktu sehingga lebih ramah index |
| **Generated column** | `total numeric GENERATED ALWAYS AS (harga * jumlah) STORED` | Nilai dihitung otomatis dari kolom lain |

> **Sequence tidak transaksional**: nilai yang sudah diambil tidak dikembalikan saat `ROLLBACK`, sehingga ID bisa memiliki "lubang". Ini normal dan bukan bug.

### 4.5 Tipe Data Utama

| Kategori | Tipe | Catatan |
|---|---|---|
| **Bilangan bulat** | `smallint` (2 B), `integer` (4 B), `bigint` (8 B) | Gunakan `bigint` untuk ID yang akan tumbuh besar |
| **Desimal presisi** | `numeric(p,s)` | **Wajib untuk uang** — tepat, tidak ada galat pembulatan |
| **Floating point** | `real`, `double precision` | Cepat tapi **tidak tepat**; jangan untuk uang |
| **Teks** | `text`, `varchar(n)`, `char(n)` | `text` dan `varchar` sama cepatnya; **hindari `char(n)`** |
| **Boolean** | `boolean` | `true` / `false` / `NULL` |
| **Tanggal & waktu** | `date`, `time`, `timestamp`, `timestamptz`, `interval` | **Pakai `timestamptz`** untuk titik waktu |
| **UUID** | `uuid` | 128-bit identifier |
| **JSON** | `json`, **`jsonb`** | `jsonb` biner, bisa di-index (GIN); pilih `jsonb` |
| **Array** | `integer[]`, `text[]` | Kolom bisa berisi array |
| **Enum** | `CREATE TYPE status AS ENUM (...)` | Daftar nilai tetap |
| **Range** | `int4range`, `daterange`, `tstzrange` | Rentang nilai; cocok untuk jadwal |
| **Jaringan** | `inet`, `cidr`, `macaddr` | Alamat IP |
| **Biner** | `bytea` | Data biner kecil |
| **Pencarian teks** | `tsvector`, `tsquery` | Full-text search |

**Contoh perangkap tipe data**:

```sql
SELECT 0.1::double precision + 0.2::double precision = 0.3;   -- false!
SELECT 0.1::numeric + 0.2::numeric = 0.3;                      -- true
```

### 4.6 Constraint pada DDL

```sql
CREATE TABLE pesanan (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    pelanggan_id bigint NOT NULL REFERENCES pelanggan(id) ON DELETE RESTRICT,
    status       text   NOT NULL DEFAULT 'baru'
                 CHECK (status IN ('baru','dibayar','dikirim','selesai','batal')),
    dibuat_pada  timestamptz NOT NULL DEFAULT now()
);
```

Opsi aksi foreign key:

| Opsi | Perilaku saat baris induk dihapus/diubah |
|---|---|
| `NO ACTION` (default) | Tolak (dicek di akhir statement) |
| `RESTRICT` | Tolak segera |
| `CASCADE` | Ikut hapus/ubah baris anak |
| `SET NULL` | Kolom FK anak menjadi `NULL` |
| `SET DEFAULT` | Kolom FK anak menjadi nilai default |

**Index tidak dibuat otomatis untuk FK** (hanya untuk PK dan UNIQUE). Kolom FK sering perlu di-index manual agar JOIN dan `DELETE` pada tabel induk cepat ([Modul 9](09-index.md)).

### 4.7 View dan Materialized View

| Objek | Penjelasan |
|---|---|
| **View** | Query tersimpan; dijalankan setiap kali dibaca; tidak menyimpan data |
| **Materialized View** | Hasil query **disimpan fisik**; perlu `REFRESH MATERIALIZED VIEW` (bisa `CONCURRENTLY` bila punya unique index) |

## Praktik

```bash
docker exec -it pg-latihan psql -U postgres -d toko
```

### Membuat Schema dan Tabel

```sql
CREATE SCHEMA IF NOT EXISTS app;
SET search_path TO app, public;

CREATE TABLE pelanggan (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nama        text        NOT NULL,
    email       text        NOT NULL UNIQUE,
    dibuat_pada timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE produk (
    id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sku    text          NOT NULL UNIQUE,
    nama   text          NOT NULL,
    harga  numeric(12,2) NOT NULL CHECK (harga >= 0),
    stok   integer       NOT NULL DEFAULT 0 CHECK (stok >= 0)
);

CREATE TABLE pesanan (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    pelanggan_id bigint NOT NULL REFERENCES pelanggan(id),
    status       text   NOT NULL DEFAULT 'baru'
                 CHECK (status IN ('baru','dibayar','dikirim','selesai','batal')),
    dibuat_pada  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE item_pesanan (
    pesanan_id bigint  NOT NULL REFERENCES pesanan(id) ON DELETE CASCADE,
    produk_id  bigint  NOT NULL REFERENCES produk(id),
    jumlah     integer NOT NULL CHECK (jumlah > 0),
    harga_satuan numeric(12,2) NOT NULL,
    PRIMARY KEY (pesanan_id, produk_id)
);

\dt app.*
\d app.pesanan
```

### Menguji Constraint dan Transactional DDL

```sql
-- constraint menolak data tidak valid
INSERT INTO produk (sku, nama, harga, stok) VALUES ('X-1', 'Uji', -5, 0);
-- ERROR: violates check constraint

-- DDL transaksional
BEGIN;
ALTER TABLE produk ADD COLUMN kategori text;
\d produk
ROLLBACK;
\d produk          -- kolom 'kategori' hilang lagi

-- ubah struktur permanen
ALTER TABLE produk ADD COLUMN kategori text NOT NULL DEFAULT 'umum';
ALTER TABLE pelanggan ADD COLUMN telepon text;
COMMENT ON TABLE produk IS 'Katalog produk toko';

-- perangkap floating point
SELECT 0.1::double precision + 0.2::double precision = 0.3 AS float_sama,
       0.1::numeric + 0.2::numeric = 0.3 AS numeric_sama;

-- enum, array, jsonb, range
CREATE TYPE prioritas AS ENUM ('rendah', 'sedang', 'tinggi');
SELECT 'sedang'::prioritas < 'tinggi'::prioritas;
SELECT ARRAY[1,2,3] @> ARRAY[2];
SELECT '{"warna":"merah","ukuran":"L"}'::jsonb ->> 'warna';
SELECT daterange('2026-01-01','2026-01-10') && daterange('2026-01-05','2026-01-20');

-- view & materialized view
CREATE VIEW v_stok_menipis AS
  SELECT id, nama, stok FROM produk WHERE stok < 10;
CREATE MATERIALIZED VIEW mv_ringkasan_produk AS
  SELECT count(*) AS jumlah_produk, sum(stok) AS total_stok FROM produk;
REFRESH MATERIALIZED VIEW mv_ringkasan_produk;
```

## Latihan

1. Buat schema `perpustakaan` dengan tabel `buku`, `anggota`, `peminjaman` sesuai rancangan latihan Modul 2, lengkap dengan PK, FK, `UNIQUE`, dan minimal dua `CHECK`.
2. Tambahkan kolom `rating numeric(2,1)` ke `produk` dengan `CHECK (rating BETWEEN 0 AND 5)` memakai `ALTER TABLE`. Apa yang terjadi jika tabel sudah berisi data dan Anda menambahkan kolom `NOT NULL` **tanpa** `DEFAULT`?
3. Jelaskan mengapa `numeric` dipakai untuk harga dan `timestamptz` (bukan `timestamp`) untuk waktu transaksi. Berikan contoh bug yang bisa terjadi jika sebaliknya.
4. Buktikan bahwa sequence tidak transaksional: insert satu baris dalam transaksi lalu `ROLLBACK`, kemudian insert lagi dan amati nilai `id`.
5. Buat tabel `reservasi_ruangan` dengan kolom `ruangan text` dan `waktu tstzrange`, lalu tambahkan constraint `EXCLUDE USING gist (ruangan WITH =, waktu WITH &&)` (butuh `CREATE EXTENSION btree_gist`). Coba insert dua reservasi yang tumpang tindih.
6. Diskusikan: kapan memakai `view` vs `materialized view`? Berikan satu contoh laporan yang cocok untuk masing-masing.

---

[← Modul 3: Instalasi, Setup & psql](03-instalasi-setup.md) · [Daftar Isi](README.md#daftar-isi) · [Modul 5: DML: Query, Filter & Modifikasi Data →](05-dml-query-dasar.md)
