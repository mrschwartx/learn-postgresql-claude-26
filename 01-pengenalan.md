# Modul 1: Pengenalan PostgreSQL

[Daftar Isi](README.md#daftar-isi) · [Modul 2: Konsep Relasional & Object Model →](02-konsep-relasional.md)

**Isi modul ini**

- [Teori](#teori)
  - [1.1 Apa itu PostgreSQL?](#11-apa-itu-postgresql)
  - [1.2 Apa itu Relational Database?](#12-apa-itu-relational-database)
  - [1.3 Kelebihan dan Keterbatasan RDBMS](#13-kelebihan-dan-keterbatasan-rdbms)
  - [1.4 PostgreSQL vs RDBMS Lain](#14-postgresql-vs-rdbms-lain)
  - [1.5 PostgreSQL vs Database NoSQL](#15-postgresql-vs-database-nosql)
  - [1.6 Fitur Khas PostgreSQL](#16-fitur-khas-postgresql)
  - [1.7 PostgreSQL dalam Arsitektur Modern](#17-postgresql-dalam-arsitektur-modern)
  - [1.8 Versi dan Siklus Rilis](#18-versi-dan-siklus-rilis)
- [Praktik](#praktik)
- [Latihan](#latihan)

---


## Teori

### 1.1 Apa itu PostgreSQL?

**PostgreSQL** (sering disingkat **Postgres**) adalah **object-relational database management system (ORDBMS)** open source dengan pengembangan aktif lebih dari 35 tahun. Ia dikenal karena **keandalan**, **kelengkapan fitur**, dan **kepatuhan tinggi terhadap standar SQL**. Akarnya ada di proyek **POSTGRES** di University of California, Berkeley (dipimpin Michael Stonebraker, pertengahan 1980-an); dukungan SQL ditambahkan pada 1990-an dan proyeknya berganti nama menjadi **PostgreSQL** pada 1996.

PostgreSQL dirilis di bawah **PostgreSQL License** — lisensi permisif mirip BSD/MIT. Tidak ada perusahaan tunggal pemiliknya: pengembangan dikelola komunitas (**PostgreSQL Global Development Group**), sehingga Anda bebas memakai, memodifikasi, dan mendistribusikannya untuk keperluan komersial tanpa biaya lisensi.

### 1.2 Apa itu Relational Database?

**Relational database** menyimpan data dalam **tabel** (baris dan kolom) yang saling berhubungan lewat **key**. Model ini berakar pada **relational model** dari E. F. Codd (1970) dan diakses dengan bahasa deklaratif **SQL** — Anda menyatakan *apa* yang diinginkan, sedangkan *bagaimana* mengambilnya diputuskan oleh **query planner** (Modul 10).

```
┌──────────────┐        ┌──────────────┐        ┌───────────────┐
│  pelanggan   │ 1    n │   pesanan    │ 1    n │ item_pesanan  │
│──────────────│◄───────│──────────────│◄───────│───────────────│
│ id (PK)      │        │ id (PK)      │        │ id (PK)       │
│ nama         │        │ pelanggan_id │        │ pesanan_id    │
│ email        │        │ tanggal      │        │ produk_id     │
└──────────────┘        └──────────────┘        │ jumlah        │
                                                └───────────────┘
```

### 1.3 Kelebihan dan Keterbatasan RDBMS

| Kelebihan | Keterbatasan |
|---|---|
| **Integritas data** kuat lewat constraint (PK, FK, UNIQUE, CHECK) | **Skema kaku** — mengubah struktur tabel besar butuh perencanaan |
| **Transaksi ACID** — data tetap konsisten meski terjadi error/crash | **Scale-out (horizontal)** write lebih sulit dibanding banyak NoSQL |
| **SQL** — bahasa standar, kuat untuk query kompleks (JOIN, agregasi) | Perlu desain skema di depan (normalisasi, relasi) |
| Ekosistem matang: tooling, backup, replikasi, ORM | Data tidak terstruktur/skala sangat besar bisa kurang efisien |
| Konkurensi terkontrol (MVCC, locking) | Join banyak tabel besar butuh index & tuning yang tepat |

### 1.4 PostgreSQL vs RDBMS Lain

| Aspek | PostgreSQL | MySQL/MariaDB | SQL Server | Oracle | SQLite |
|---|---|---|---|---|---|
| Lisensi | PostgreSQL License (permisif) | GPL (MySQL) / GPL (MariaDB) | Komersial | Komersial | Public domain |
| Arsitektur | Client-server | Client-server | Client-server | Client-server | **Embedded** (file) |
| Kepatuhan standar SQL | **Sangat tinggi** | Cukup | Tinggi | Tinggi | Sebagian |
| Tipe data kaya (JSONB, array, range, geometri) | **Ya, native** | Terbatas | Sebagian | Sebagian | Minimal |
| Ekstensibilitas (tipe, operator, index, extension) | **Sangat tinggi** | Terbatas | Terbatas | Terbatas | Rendah |
| Transactional DDL | **Ya** | Tidak (umumnya) | Ya | Terbatas | Ya |
| Cocok untuk | Workload umum hingga analitik, GIS | Web app sederhana, baca-berat | Ekosistem Microsoft | Enterprise legacy | Aplikasi lokal/mobile |

**Transactional DDL** (perubahan skema bisa di-`ROLLBACK`) adalah salah satu fitur favorit PostgreSQL untuk migrasi yang aman (Modul 11).

### 1.5 PostgreSQL vs Database NoSQL

| Aspek | PostgreSQL | MongoDB | Redis | Elasticsearch |
|---|---|---|---|---|
| Model data | Relasional (+ JSONB) | Dokumen | Key-value / struktur data | Dokumen + inverted index |
| Sumber kebenaran (source of truth) | **Ya** | Ya | Biasanya cache | Biasanya indeks turunan |
| Transaksi multi-baris/tabel | **ACID penuh** | Ya (sejak 4.0) | Terbatas | Tidak |
| Query kompleks (JOIN) | **Sangat baik** | Terbatas | Tidak ada | Terbatas |
| Kekuatan utama | Konsistensi + fleksibilitas | Skema fleksibel | Kecepatan | Full-text search & analitik |

**Prinsip penting**: PostgreSQL dengan tipe `JSONB` + index GIN (Modul 9) sering cukup untuk kebutuhan "semi-terstruktur" tanpa harus menambah database baru. Dalam banyak arsitektur, PostgreSQL menjadi **sumber kebenaran**, sementara **Redis** (course Redis) berperan sebagai cache dan **Elasticsearch** (course Elasticsearch) sebagai mesin pencari turunan.

### 1.6 Fitur Khas PostgreSQL

| Fitur | Penjelasan |
|---|---|
| **MVCC** | Pembaca tidak memblokir penulis dan sebaliknya ([Modul 7](07-transaksi-mvcc-wal.md)) |
| **Tipe data kaya** | `JSONB`, array, `UUID`, range, `inet`, `tsvector`, tipe komposit, enum |
| **Index beragam** | B-Tree, Hash, GiST, SP-GiST, GIN, BRIN ([Modul 9](09-index.md)) |
| **Extension** | `pg_stat_statements`, `PostGIS`, `pgvector`, `pg_trgm`, `TimescaleDB`, dll. |
| **Replikasi** | Streaming (fisik) dan logical ([Modul 15](15-replication-ha-pooling.md)) |
| **Bahasa prosedural** | PL/pgSQL, PL/Python, PL/Perl, dll. ([Modul 8](08-advanced-sql-plpgsql.md)) |
| **Partitioning** | Deklaratif (range/list/hash) ([Modul 11](11-desain-schema-pola.md)) |
| **Row-Level Security** | Kontrol akses per baris ([Modul 13](13-security.md)) |

### 1.7 PostgreSQL dalam Arsitektur Modern

```
Browser/Mobile App
       │
       ▼
┌──────────────┐   cache hit    ┌─────────┐
│  Aplikasi    │ ─────────────► │  Redis  │
│  Backend     │ ◄───────────── │ (cache) │
└──────┬───────┘                └─────────┘
       │ SQL (via connection pool)
       ▼
┌──────────────┐  streaming replication  ┌──────────────┐
│ PostgreSQL   │ ──────────────────────► │ PostgreSQL   │
│ (primary)    │                         │ (replica)    │
└──────┬───────┘                         └──────────────┘
       │ CDC / logical replication
       ▼
 Kafka → Elasticsearch / Data Warehouse
```

Dalam diagram ini PostgreSQL adalah pusatnya: data ditulis ke primary, dibaca dari replica, di-cache oleh Redis, dan dialirkan ke sistem lain lewat Kafka (course Kafka) menggunakan *logical replication* / CDC.

### 1.8 Versi dan Siklus Rilis

PostgreSQL merilis **satu versi mayor per tahun** (biasanya September–Oktober) dan setiap versi mayor didukung **5 tahun**. Versi minor (mis. 18.6) berisi perbaikan bug dan security **tanpa** perubahan format data — upgrade minor cukup mengganti binary dan restart.

| Jenis | Contoh | Cara upgrade |
|---|---|---|
| **Minor** | 18.5 → 18.6 | Ganti binary, restart |
| **Mayor** | 17 → 18 | `pg_upgrade`, dump/restore, atau logical replication ([Modul 14](14-backup-recovery-upgrade.md)) |

> Materi ini ditulis dan diuji terhadap **PostgreSQL 16–18**. PostgreSQL 19 baru dirilis pada November 2026; sebagian besar materi tetap berlaku, tetapi selalu baca *release notes* versi yang Anda pakai. Untuk produksi, pastikan versi mayor Anda masih menerima patch (PostgreSQL 14 berhenti didukung pada 12 November 2026).

## Praktik

Kita belum menjalankan PostgreSQL ([Modul 3](03-instalasi-setup.md)). Mari merasakan **manfaat constraint relasional** dengan `sqlite3` bawaan Python (SQLite juga RDBMS, sehingga konsepnya sama).

```python
# demo_relasional.py
import sqlite3

db = sqlite3.connect(":memory:")
db.execute("PRAGMA foreign_keys = ON")   # SQLite mematikan FK secara default

db.executescript("""
CREATE TABLE pelanggan (
    id    INTEGER PRIMARY KEY,
    nama  TEXT NOT NULL,
    email TEXT UNIQUE NOT NULL
);
CREATE TABLE pesanan (
    id           INTEGER PRIMARY KEY,
    pelanggan_id INTEGER NOT NULL REFERENCES pelanggan(id),
    total        INTEGER CHECK (total >= 0)
);
INSERT INTO pelanggan (nama, email) VALUES ('Andi', 'andi@contoh.com');
""")

# 1) Pesanan untuk pelanggan yang tidak ada -> ditolak oleh FOREIGN KEY
try:
    db.execute("INSERT INTO pesanan (pelanggan_id, total) VALUES (999, 100)")
except sqlite3.IntegrityError as e:
    print("FK menolak:", e)

# 2) Email duplikat -> ditolak oleh UNIQUE
try:
    db.execute("INSERT INTO pelanggan (nama, email) VALUES ('Budi', 'andi@contoh.com')")
except sqlite3.IntegrityError as e:
    print("UNIQUE menolak:", e)

# 3) Total negatif -> ditolak oleh CHECK
try:
    db.execute("INSERT INTO pesanan (pelanggan_id, total) VALUES (1, -5)")
except sqlite3.IntegrityError as e:
    print("CHECK menolak:", e)
```

```bash
python3 demo_relasional.py
```

Perhatikan bahwa **database sendiri** yang menolak data tidak valid — Anda tidak perlu mengandalkan kode aplikasi untuk menjaga integritas. Pada Modul 4 kita akan membuat constraint yang sama di PostgreSQL.

## Latihan

1. Jelaskan perbedaan **ORDBMS** (PostgreSQL) dengan RDBMS "klasik". Sebutkan dua fitur PostgreSQL yang menunjukkan sifat "object" tersebut (petunjuk: tipe data dan extension).
2. Buat tabel perbandingan (min. 5 aspek) antara PostgreSQL dan MySQL untuk kebutuhan aplikasi e-commerce yang Anda bayangkan. Aspek mana yang paling memengaruhi pilihan Anda?
3. Sebuah tim menyimpan data pesanan di MongoDB, tetapi sering mengalami data tidak konsisten antara koleksi `pesanan` dan `stok`. Jelaskan fitur PostgreSQL apa yang bisa mencegah masalah ini dan mengapa.
4. Gambarkan arsitektur sistem sederhana yang memakai PostgreSQL sebagai sumber kebenaran, Redis sebagai cache, dan Elasticsearch untuk pencarian produk. Alur mana yang memakai *write-through* dan mana yang *asynchronous*?
5. Perluas `demo_relasional.py`: tambahkan tabel `produk` dan `item_pesanan` (dengan FK ke `pesanan` dan `produk`), lalu coba hapus sebuah pelanggan yang masih punya pesanan. Apa yang terjadi, dan opsi `ON DELETE` apa yang tersedia?
6. Diskusikan: kapan Anda akan **tidak** memilih PostgreSQL? Berikan dua skenario dan alternatif yang lebih cocok.

---

[Daftar Isi](README.md#daftar-isi) · [Modul 2: Konsep Relasional & Object Model →](02-konsep-relasional.md)
