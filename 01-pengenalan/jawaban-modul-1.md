# Jawaban Modul 1: Pengenalan PostgreSQL

Isi berkas ini: hasil **Praktik** dan jawaban **Latihan 1-6**.

| Berkas | Isi |
|---|---|
| `demo_relasional.py` | Skrip Praktik dari modul (tanpa perubahan) |
| `output_demo_relasional.txt` | Output asli saat skrip dijalankan |
| `demo_relasional_lanjutan.py` | Jawaban Latihan 5 + demo atomicity untuk Latihan 3 |
| `output_demo_relasional_lanjutan.txt` | Output asli skrip lanjutan |

---

## Praktik: `demo_relasional.py`

Dijalankan dengan `python3 demo_relasional.py` (SQLite 3.45.1). Output:

```
FK menolak: FOREIGN KEY constraint failed
UNIQUE menolak: UNIQUE constraint failed: pelanggan.email
CHECK menolak: CHECK constraint failed: total >= 0
```

| # | Percobaan | Constraint yang menolak | Artinya |
|---|---|---|---|
| 1 | Pesanan untuk `pelanggan_id = 999` | `FOREIGN KEY` | Tidak ada "pesanan yatim" (referential integrity) |
| 2 | Email `andi@contoh.com` didaftarkan dua kali | `UNIQUE` | Identitas tidak boleh ganda |
| 3 | `total = -5` | `CHECK` | Aturan bisnis ditegakkan di level data |

Catatan: `PRAGMA foreign_keys = ON` wajib. SQLite mematikan FK secara default, jadi tanpa baris itu percobaan 1 akan lolos tanpa error. PostgreSQL selalu menegakkan FK.

---

## Latihan 1: ORDBMS vs RDBMS klasik

RDBMS klasik hanya menyimpan data dalam tabel dengan sekumpulan tipe bawaan yang tetap. **ORDBMS** menambahkan konsep *objek* ke model relasional. Pengguna boleh **mendefinisikan sendiri tipe, operator, fungsi, dan index**, dan tabel bisa memakai tipe yang kompleks. Sistem tetap relasional dan SQL tetap bahasanya.

Dua fitur PostgreSQL yang menunjukkan sifat "object":

1. **Tipe data kaya dan buatan pengguna.** Ada `JSONB`, array, range, `inet`, `uuid`, dan tipe geometri. Anda juga bisa membuat tipe komposit, enum, dan domain sendiri:
   ```sql
   CREATE TYPE alamat AS (jalan text, kota text, kodepos text);
   CREATE TABLE gudang (id int, lokasi alamat, tag text[]);
   ```
2. **Extension.** Tipe, operator, dan jenis index baru bisa ditambahkan tanpa mengubah inti PostgreSQL. Contohnya PostGIS (tipe `geometry` + index GiST) dan pgvector (tipe `vector` + index ANN).

Fitur lain yang sejalan: *table inheritance*, fungsi dan operator buatan sendiri, serta bahasa prosedural yang bisa dipasang (PL/Python, dll.).

---

## Latihan 2: PostgreSQL vs MySQL untuk e-commerce

Skenario: toko online dengan katalog produk, keranjang, pesanan, pembayaran, dan stok.

| # | Aspek | PostgreSQL | MySQL/MariaDB | Dampak untuk e-commerce |
|---|---|---|---|---|
| 1 | Integritas dan constraint | FK, `CHECK`, `EXCLUDE`, partial unique index | FK dan `CHECK` ada, tetapi tipe-tipe constraint lanjutan lebih terbatas | Stok tidak negatif, satu kode promo aktif per pelanggan |
| 2 | Tipe data semi-terstruktur | `JSONB` + index GIN, sangat kuat | Tipe `JSON` ada, indexing lebih terbatas | Atribut produk yang beragam (warna, ukuran, spesifikasi) |
| 3 | Transactional DDL | Ya, migrasi bisa di-`ROLLBACK` | Umumnya tidak (DDL commit implisit) | Deploy migrasi skema lebih aman |
| 4 | Query kompleks | Window function, CTE rekursif, `LATERAL`, planner matang | Sudah mendukung, tetapi fitur dan optimasi planner tidak selengkap PostgreSQL | Laporan penjualan, rekomendasi, kategori bertingkat |
| 5 | Ekstensibilitas | PostGIS, pg_trgm, pgvector, dll. | Terbatas | Cari toko terdekat, pencarian produk mirip nama (typo-tolerant) |
| 6 | Full-text search | Bawaan (`tsvector`, GIN) | Ada, lebih sederhana | Pencarian produk dasar tanpa Elasticsearch |
| 7 | Lisensi | PostgreSQL License (permisif) | GPL (MySQL punya edisi komersial Oracle) | Bebas biaya dan mudah dikomersialkan |
| 8 | Ekosistem hosting dan keahlian | Luas, tetapi MySQL lebih umum di hosting murah dan CMS lama | Sangat luas | Ketersediaan tenaga dan hosting |

**Aspek yang paling memengaruhi pilihan: integritas transaksional (aspek 1, 3, dan 4).** E-commerce adalah domain uang dan stok. Kesalahan kecil menjadi pesanan ganda atau stok minus yang langsung merugikan. Constraint yang kaya, ACID penuh, dan transactional DDL membuat PostgreSQL lebih aman sebagai sumber kebenaran. Aspek 2 menjadi pertimbangan kedua karena katalog dengan atribut beragam bisa disimpan di `JSONB` tanpa database tambahan.

Catatan jujur: untuk aplikasi baca-berat yang sederhana, MySQL juga bekerja baik. Perbedaannya lebih terasa ketika skema dan query makin kompleks.

---

## Latihan 3: Data tidak konsisten antara `pesanan` dan `stok` di MongoDB

**Akar masalah:** pesanan dan stok berada di dua koleksi berbeda. Tanpa transaksi, "buat pesanan" dan "kurangi stok" bisa berhasil sebagian: pesanan tercatat tetapi stok tidak berkurang, atau sebaliknya. MongoDB memang punya transaksi multi-dokumen sejak 4.0, tetapi tidak ada FK dan constraint antar koleksi, dan model dokumen mendorong denormalisasi sehingga data ganda mudah menyimpang.

**Fitur PostgreSQL yang mencegahnya:**

| Fitur | Cara kerjanya | Mengapa mencegah masalah |
|---|---|---|
| **Transaksi ACID** (`BEGIN ... COMMIT`) | Insert pesanan, insert item, dan update stok dijalankan sebagai satu unit | Atomicity: semuanya berhasil atau semuanya dibatalkan |
| **`CHECK (stok >= 0)`** | Database menolak stok negatif | Overselling ditolak di level data, bukan hanya oleh kode aplikasi |
| **`FOREIGN KEY`** | `item_pesanan.produk_id` harus ada di `produk` | Tidak ada item yang menunjuk produk fiktif |
| **Row locking** (`SELECT ... FOR UPDATE`, MVCC) | Dua pembeli yang berebut stok terakhir diserialkan | Mencegah race condition |

Peragaan dengan SQLite (lihat `demo_relasional_lanjutan.py` bagian C). Pembelian 9 Mouse padahal stok 3 memicu `CHECK` gagal, lalu `ROLLBACK`:

```
beli 2 Mouse (stok 5)     : COMMIT -> pesanan=2, item_pesanan=3, stok Mouse=3
beli 9 Mouse (stok cuma 3): ROLLBACK (CHECK constraint failed: stok >= 0) -> pesanan=2, item_pesanan=3, stok Mouse=3
```

Setelah pembelian yang gagal, jumlah pesanan dan item tidak berubah, jadi tidak ada pesanan "setengah jadi".

Pola yang aman di PostgreSQL:

```sql
BEGIN;
INSERT INTO pesanan (...) RETURNING id;
INSERT INTO item_pesanan (...);
UPDATE produk SET stok = stok - 2 WHERE id = 2;   -- CHECK menolak jika stok kurang
COMMIT;
```

---

## Latihan 4: Arsitektur PostgreSQL + Redis + Elasticsearch

```
 Browser / Mobile App
          │
          ▼
 ┌────────────────────┐
 │  Aplikasi Backend  │
 └──┬──────┬───────┬──┘
    │      │       │
 (1)│   (2)│    (3)│ pencarian produk
    │      │       ▼
    │      │   ┌───────────────┐
    │      │   │ Elasticsearch │  indeks turunan (bisa dibangun ulang)
    │      │   └───────▲───────┘
    │      │           │ (B) asynchronous: CDC → Kafka → indexer
    │      ▼           │
    │  ┌───────┐   ┌───┴──────────────────┐   WAL / streaming   ┌──────────┐
    │  │ Redis │   │ PostgreSQL (primary) │ ──────────────────► │ replica  │
    │  │ cache │   │  SUMBER KEBENARAN    │                     │ (baca)   │
    │  └───────┘   └──────────────────────┘                     └──────────┘
    └───(A) write-through───────▲
```

| Alur | Jenis | Penjelasan |
|---|---|---|
| **A. Tulis data produk atau pesanan** | **Write-through** | Aplikasi menulis ke PostgreSQL (commit = data aman), lalu memperbarui atau meng-invalidate kunci cache di Redis pada alur yang sama. Redis tidak pernah menjadi satu-satunya salinan. |
| **B. PostgreSQL → Elasticsearch** | **Asynchronous** | Perubahan data dialirkan lewat logical replication/CDC (mis. Debezium → Kafka) ke indexer. Pencarian boleh terlambat beberapa detik (*eventual consistency*). Jika indeks rusak, bangun ulang dari PostgreSQL. |
| **C. Baca produk** | *Cache-aside* | Cek Redis dulu. Jika *miss*, baca PostgreSQL (replica bila perlu), lalu isi cache dengan TTL. |
| **D. Pencarian produk** | Baca saja | Langsung ke Elasticsearch. Detail akhir (harga dan stok yang akurat) diambil dari PostgreSQL. |

Prinsip desain: **PostgreSQL adalah sumber kebenaran**, sedangkan Redis dan Elasticsearch adalah salinan turunan yang boleh hilang. Menulis ke dua tempat sekaligus dari aplikasi (*dual write*) berisiko tidak konsisten, jadi sinkronisasi ke Elasticsearch sebaiknya lewat CDC.

---

## Latihan 5: Perluasan `demo_relasional.py`

Kode lengkap: `demo_relasional_lanjutan.py`. Skema bertambah dengan `produk` dan `item_pesanan` (FK ke `pesanan` dan `produk`).

```
pelanggan 1 ◄── pesanan 1 ◄── item_pesanan ──► produk
```

**Apa yang terjadi saat pelanggan yang masih punya pesanan dihapus?**

```
DELETE ditolak: FOREIGN KEY constraint failed
pelanggan tersisa: 1 | pesanan tersisa: 1
```

Dengan FK default (`NO ACTION`), `DELETE` **ditolak**. Database menolak karena akan meninggalkan `pesanan` yang menunjuk pelanggan yang tidak ada. Menghapus produk yang sudah dipakai `item_pesanan` juga ditolak.

**Opsi `ON DELETE` yang tersedia** (hasil nyata dari skrip):

| Opsi | Perilaku saat pelanggan dihapus | Hasil di demo |
|---|---|---|
| `NO ACTION` (default) | Ditolak. Di PostgreSQL, pengecekan bisa ditunda ke akhir transaksi bila FK `DEFERRABLE`. | Ditolak, data utuh |
| `RESTRICT` | Ditolak **langsung**, tidak bisa ditunda | Ditolak, data utuh |
| `CASCADE` | Pesanan ikut terhapus (dan item-nya, karena `item_pesanan` memakai `ON DELETE CASCADE`) | `pelanggan=0, pesanan=0, item_pesanan=0` |
| `SET NULL` | Kolom FK di pesanan menjadi `NULL` (kolom harus boleh NULL) | Pesanan tetap, `pelanggan_id = NULL` |
| `SET DEFAULT` | Kolom FK diisi nilai `DEFAULT`-nya | Di demo `DEFAULT`-nya NULL, hasilnya sama dengan `SET NULL`. Nilai default yang dipakai harus tetap valid sebagai FK. |

Panduan memilih untuk e-commerce:

- **`pesanan` → `pelanggan`: jangan `CASCADE`.** Riwayat transaksi adalah data keuangan dan sering wajib disimpan. Lebih baik `RESTRICT` atau *soft delete* (kolom `dihapus_pada`), atau anonimkan data pelanggan.
- **`item_pesanan` → `pesanan`: `CASCADE`.** Item tidak punya arti tanpa induknya.
- **`item_pesanan` → `produk`: `RESTRICT`.** Produk yang pernah terjual tidak boleh hilang. Tandai saja sebagai tidak aktif.

Catatan perbedaan SQLite dan PostgreSQL: di SQLite, `NO ACTION` dan `RESTRICT` sama-sama menolak dengan pesan yang sama. Perbedaan waktu pengecekan terlihat di PostgreSQL pada FK `DEFERRABLE`.

---

## Latihan 6: Kapan **tidak** memilih PostgreSQL?

**Skenario 1: aplikasi mobile/desktop lokal atau perangkat IoT yang offline.**
PostgreSQL adalah server (proses, port, konfigurasi, administrasi), jadi terlalu berat untuk aplikasi yang hanya butuh penyimpanan lokal di satu perangkat. **Alternatif: SQLite** (embedded, satu berkas, tanpa server), yang dipakai di Android, iOS, dan browser.

**Skenario 2: throughput tulis sangat besar dengan pola akses sederhana (key-value) dan perlu skala horizontal multi-region.**
Contohnya keranjang sesi jutaan pengguna atau event stream sensor dengan puluhan ribu tulis per detik. PostgreSQL scale-out untuk *write* lebih sulit (butuh partitioning/sharding manual atau Citus) dan sering tidak sebanding kerumitannya. **Alternatif:**
- **Redis** untuk sesi, cache, dan state sementara.
- **Cassandra/ScyllaDB/DynamoDB** untuk write masif dan multi-region.
- **Kafka** bila datanya berupa aliran event.

Skenario tambahan (opsional):
- **Pencarian teks relevansi tinggi dan analitik log skala besar** → Elasticsearch/OpenSearch.
- **Analitik kolumnar atas ratusan TB** → ClickHouse, BigQuery, atau Snowflake. Postgres cocok untuk OLTP, bukan untuk scan seluruh data berukuran besar.
- **Pengguna hanya butuh spreadsheet atau laporan sederhana** → mungkin database server tidak diperlukan sama sekali.

Prinsip: pilih PostgreSQL sebagai **default** untuk data yang harus benar. Tinggalkan hanya bila ada kebutuhan spesifik yang jelas lebih cocok ditangani alat lain.
