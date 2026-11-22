# Modul 7: Transaksi, ACID, MVCC & WAL

[← Modul 6: Join, Subquery, Grouping, CTE & Set Operations](06-join-subquery-cte.md) · [Daftar Isi](README.md#daftar-isi) · [Modul 8: Advanced SQL & PL/pgSQL →](08-advanced-sql-plpgsql.md)

**Isi modul ini**

- [Teori](#teori)
  - [7.1 Transaksi — Unit Kerja yang Tak Terpisahkan](#71-transaksi--unit-kerja-yang-tak-terpisahkan)
  - [7.2 ACID](#72-acid)
  - [7.3 MVCC — Multi-Version Concurrency Control](#73-mvcc--multi-version-concurrency-control)
  - [7.4 Isolation Level](#74-isolation-level)
  - [7.5 Locking](#75-locking)
  - [7.6 WAL — Write-Ahead Log](#76-wal--write-ahead-log)
  - [7.7 Query Processing — Alur Sebuah Query](#77-query-processing--alur-sebuah-query)
- [Praktik](#praktik)
  - [Persiapan Tabel Rekening](#persiapan-tabel-rekening)
  - [Atomicity](#atomicity)
  - [MVCC — Melihat Versi Baris](#mvcc--melihat-versi-baris)
  - [Isolation Level](#isolation-level)
  - [Locking dan SKIP LOCKED](#locking-dan-skip-locked)
  - [Melihat WAL](#melihat-wal)
- [Latihan](#latihan)

---


## Teori

### 7.1 Transaksi — Unit Kerja yang Tak Terpisahkan

**Transaksi** adalah sekumpulan perintah SQL yang diperlakukan sebagai **satu kesatuan**: semuanya berhasil, atau tidak ada yang berlaku. Contoh klasik — transfer saldo: mengurangi rekening A dan menambah rekening B harus terjadi bersama.

```sql
BEGIN;
UPDATE rekening SET saldo = saldo - 100000 WHERE id = 1;
UPDATE rekening SET saldo = saldo + 100000 WHERE id = 2;
COMMIT;      -- atau ROLLBACK; untuk membatalkan semuanya
```

| Perintah | Fungsi |
|---|---|
| `BEGIN` / `START TRANSACTION` | Mulai transaksi |
| `COMMIT` | Simpan permanen |
| `ROLLBACK` | Batalkan semua perubahan |
| `SAVEPOINT nama` / `ROLLBACK TO nama` | Titik kembali parsial dalam transaksi |

Tanpa `BEGIN`, setiap statement berjalan dalam **transaksi implisit** (autocommit). Jika terjadi error di tengah transaksi, transaksi masuk status *aborted* dan hanya menerima `ROLLBACK` (atau `ROLLBACK TO SAVEPOINT`).

### 7.2 ACID

| Properti | Arti | Mekanisme di PostgreSQL |
|---|---|---|
| **A**tomicity | Semua-atau-tidak-sama-sekali | Rollback via MVCC (versi lama baris tetap ada) |
| **C**onsistency | Data selalu memenuhi constraint | Constraint, trigger, FK |
| **I**solation | Transaksi bersamaan tidak saling mengganggu | MVCC + isolation level + lock |
| **D**urability | Data yang di-commit tidak hilang walau crash | **WAL** + `fsync` |

### 7.3 MVCC — Multi-Version Concurrency Control

PostgreSQL **tidak menimpa** baris saat `UPDATE`. Ia membuat **versi baru** dari baris dan menandai versi lama sebagai kedaluwarsa. Setiap transaksi melihat **snapshot** data sesuai waktu ia mulai (atau tiap statement, tergantung isolation level).

```
UPDATE produk SET stok = 9 WHERE id = 1;

  halaman tabel (heap):
  ┌────────────────────────────────────────────────┐
  │ (id=1, stok=10)  xmin=100  xmax=205  ← versi lama│
  │ (id=1, stok=9 )  xmin=205  xmax=0    ← versi baru│
  └────────────────────────────────────────────────┘
  xmin = ID transaksi yang membuat baris
  xmax = ID transaksi yang menghapus/menggantikan baris
```

Konsekuensinya:

- **Pembaca tidak memblokir penulis dan sebaliknya.**
- Versi lama yang tidak lagi terlihat oleh transaksi mana pun menjadi **dead tuple** yang dibersihkan oleh **VACUUM** ([Modul 12](12-internal-konfigurasi.md)).
- Tabel dengan banyak `UPDATE`/`DELETE` mengalami **bloat** bila vacuum tidak berjalan baik.

Kolom sistem `xmin`/`xmax`/`ctid` bisa dilihat: `SELECT xmin, xmax, ctid, * FROM produk;`.

### 7.4 Isolation Level

| Level | Dirty Read | Non-repeatable Read | Phantom Read | Catatan |
|---|---|---|---|---|
| `READ UNCOMMITTED` | Tidak | Mungkin | Mungkin | Di PostgreSQL berperilaku **sama** dengan `READ COMMITTED` |
| **`READ COMMITTED`** (default) | Tidak | Mungkin | Mungkin | Tiap **statement** melihat snapshot baru |
| `REPEATABLE READ` | Tidak | Tidak | Tidak* | Snapshot satu kali untuk seluruh transaksi |
| `SERIALIZABLE` | Tidak | Tidak | Tidak | Terdeteksi anomali → error `40001` (aplikasi harus **retry**) |

\* Implementasi snapshot isolation PostgreSQL pada `REPEATABLE READ` juga mencegah phantom read standar, tetapi masih mengizinkan anomali seperti *write skew*, yang baru dicegah oleh `SERIALIZABLE` (SSI).

```sql
BEGIN ISOLATION LEVEL REPEATABLE READ;
-- ...
COMMIT;
```

### 7.5 Locking

| Lock | Cara | Kegunaan |
|---|---|---|
| **Row-level** | Otomatis saat `UPDATE`/`DELETE`; eksplisit `SELECT ... FOR UPDATE` | Mencegah dua transaksi mengubah baris sama |
| `FOR UPDATE SKIP LOCKED` | Lewati baris yang terkunci | **Job queue** — banyak worker mengambil tugas berbeda |
| `FOR UPDATE NOWAIT` | Gagal segera jika terkunci | Hindari menunggu |
| `FOR SHARE` / `FOR KEY SHARE` | Kunci baca bersama | Pastikan baris tidak berubah/hilang |
| **Table-level** | `LOCK TABLE`, otomatis oleh DDL | `ALTER TABLE` mengambil `ACCESS EXCLUSIVE` — memblokir semua akses |
| **Advisory lock** | `pg_advisory_lock(key)` | Kunci aplikasi (mis. cron job tunggal) |

**Deadlock**: dua transaksi saling menunggu kunci satu sama lain. PostgreSQL mendeteksinya otomatis (setelah `deadlock_timeout`, default 1 detik) dan **membatalkan salah satu** transaksi. Pencegahan: kunci baris dalam **urutan konsisten**.

### 7.6 WAL — Write-Ahead Log

Prinsip **write-ahead**: setiap perubahan data **dicatat dulu di log (WAL)** dan di-`fsync` ke disk **sebelum** transaksi dianggap `COMMIT`. Halaman data di memori (*shared buffers*) boleh ditulis ke disk belakangan.

```
 UPDATE ... COMMIT
     │
     ├─► 1. Ubah halaman di shared_buffers (memori, "dirty page")
     ├─► 2. Tulis record WAL ke WAL buffer ─► flush ke pg_wal/ (fsync)  ◄── commit selesai di sini
     └─► 3. (nanti) background writer / checkpointer menulis dirty page ke file data
```

Mengapa dirancang begini?

| Alasan | Penjelasan |
|---|---|
| **Durability cepat** | Menulis log berurutan (sequential) jauh lebih cepat daripada menulis halaman tabel acak |
| **Crash recovery** | Setelah crash, PostgreSQL memutar ulang (*replay*) WAL sejak checkpoint terakhir |
| **Replikasi** | Replica mengonsumsi aliran WAL ([Modul 15](15-replication-ha-pooling.md)) |
| **PITR** | Arsip WAL + base backup memungkinkan pemulihan ke titik waktu mana pun ([Modul 14](14-backup-recovery-upgrade.md)) |

**Checkpoint** adalah titik ketika semua dirty page ditulis ke disk, sehingga WAL sebelum titik itu tidak lagi diperlukan untuk crash recovery.

### 7.7 Query Processing — Alur Sebuah Query

```
SQL text
  │
  ▼  1. Parser        → memeriksa sintaks, membuat parse tree
  ▼  2. Analyzer      → resolusi nama tabel/kolom, tipe data
  ▼  3. Rewriter      → menerapkan aturan (mis. mengganti view dengan definisinya)
  ▼  4. Planner       → memilih rencana eksekusi termurah (berdasarkan statistik)
  ▼  5. Executor      → menjalankan rencana, mengembalikan baris
```

Tahap **Planner/Optimizer** yang paling menentukan performa — dibahas mendalam di [Modul 10](10-query-planner-explain.md).

## Praktik

```bash
docker exec -it pg-latihan psql -U postgres -d toko
```

### Persiapan Tabel Rekening

```sql
CREATE TABLE rekening (id int PRIMARY KEY, pemilik text, saldo numeric(12,2) CHECK (saldo >= 0));
INSERT INTO rekening VALUES (1,'Andi',500000), (2,'Budi',100000);
```

### Atomicity

```sql
BEGIN;
UPDATE rekening SET saldo = saldo - 600000 WHERE id = 1;   -- melanggar CHECK -> error
UPDATE rekening SET saldo = saldo + 600000 WHERE id = 2;   -- ditolak: transaction is aborted
ROLLBACK;
SELECT * FROM rekening;    -- tidak ada yang berubah
```

### MVCC — Melihat Versi Baris

```sql
SELECT xmin, xmax, ctid, * FROM rekening;
UPDATE rekening SET saldo = saldo + 1 WHERE id = 1;
SELECT xmin, xmax, ctid, * FROM rekening;   -- ctid dan xmin berubah: ini baris versi baru
```

### Isolation Level

Isolation — buka **dua terminal** `psql` (A dan B):

```
-- A:
BEGIN;
SELECT saldo FROM rekening WHERE id = 1;          -- misal 500001
-- B:
UPDATE rekening SET saldo = 999 WHERE id = 1;     -- autocommit
-- A:
SELECT saldo FROM rekening WHERE id = 1;          -- READ COMMITTED: melihat 999
COMMIT;

-- Ulangi dengan A memakai: BEGIN ISOLATION LEVEL REPEATABLE READ;
-- Kini A tetap melihat nilai lama sampai COMMIT.
```

### Locking dan SKIP LOCKED

Locking dan `SKIP LOCKED` (dua terminal):

```
-- A:
BEGIN;
SELECT * FROM rekening WHERE id = 1 FOR UPDATE;
-- B:
UPDATE rekening SET saldo = 1 WHERE id = 1;       -- menunggu (blocked)
-- B (batalkan dengan Ctrl+C), lalu:
SELECT * FROM rekening ORDER BY id FOR UPDATE SKIP LOCKED LIMIT 1;   -- melewati id=1, mengambil id=2
-- A:
ROLLBACK;
```

### Melihat WAL

```sql
SHOW wal_level;
SELECT pg_current_wal_lsn();
UPDATE rekening SET saldo = saldo + 1;
SELECT pg_current_wal_lsn();     -- LSN maju: perubahan tercatat di WAL
SELECT pg_wal_lsn_diff(pg_current_wal_lsn(), '0/0') AS total_byte_wal;
```

## Latihan

1. Implementasikan transfer saldo dalam satu transaksi dengan `SAVEPOINT`: jika pengurangan berhasil tetapi penambahan gagal, kembali ke savepoint dan catat percobaan gagal di tabel `log_transfer`.
2. Buktikan perbedaan `READ COMMITTED` dan `REPEATABLE READ` dengan dua sesi `psql`. Jelaskan hasil yang Anda amati terkait *non-repeatable read*.
3. Ciptakan **deadlock** dengan dua sesi (A mengunci baris 1 lalu 2; B mengunci baris 2 lalu 1). Catat pesan error yang muncul, dan jelaskan cara mencegahnya.
4. Bangun "job queue" sederhana: tabel `tugas(id, status)`, lalu jalankan dua sesi worker yang masing-masing mengambil satu tugas dengan `FOR UPDATE SKIP LOCKED` dan memastikan tidak ada tugas yang diproses dua kali.
5. Jelaskan dengan kata-kata Anda mengapa PostgreSQL cukup menulis WAL (bukan seluruh halaman data) ke disk saat `COMMIT`, dan apa yang terjadi saat server mati mendadak sebelum halaman data sempat ditulis.
6. Diskusikan: mengapa tabel dengan `UPDATE` yang sangat sering bisa membengkak (bloat) pada PostgreSQL meskipun jumlah baris "hidup" tidak bertambah? Hubungkan dengan MVCC.

---

[← Modul 6: Join, Subquery, Grouping, CTE & Set Operations](06-join-subquery-cte.md) · [Daftar Isi](README.md#daftar-isi) · [Modul 8: Advanced SQL & PL/pgSQL →](08-advanced-sql-plpgsql.md)
