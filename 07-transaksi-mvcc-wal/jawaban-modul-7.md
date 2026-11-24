# Jawaban Modul 7: Transaksi, ACID, MVCC & WAL

## Status eksekusi (baca dulu)

PostgreSQL dan Docker tidak tersedia di lingkungan saya, jadi **tidak ada perintah di modul ini yang sudah dijalankan di PostgreSQL**. Modul ini juga yang paling bergantung pada perilaku khas PostgreSQL, sehingga SQLite hanya bisa mewakili sebagian kecilnya.

| Bagian | Status |
|---|---|
| Logika `SAVEPOINT` / `ROLLBACK TO` pada transfer (Latihan 1), hasil akhir Atomicity | **Diuji di SQLite**: 7 pemeriksaan, semuanya sesuai (`output_verifikasi_sqlite.txt`) |
| Alur skrip dua sesi (`dua_sesi.sh`): perintah masuk ke sesi yang benar, skrip selesai tanpa menggantung | **Diuji dengan `docker` tiruan** yang hanya menggemakan input. Ini hanya membuktikan plumbing skrip, bukan perilaku database. |
| MVCC (`xmin`/`xmax`/`ctid`), isolation level, row locking, `SKIP LOCKED`, deadlock, WAL/LSN, bloat | **Tidak bisa diuji di sini.** Semua berlabel **(diharapkan)**, berdasarkan perilaku PostgreSQL yang terdokumentasi. |
| Pesan error PostgreSQL, ID transaksi, nilai LSN, ukuran tabel | Saya tidak menuliskan angka persisnya; hanya bentuk dan arahnya |

| Berkas | Fungsi |
|---|---|
| `praktik.sql` | Bagian Praktik yang berjalan di satu sesi (disalin dari modul; satu tambahan: `DROP TABLE IF EXISTS rekening`) |
| `latihan.sql` | Latihan 1 (savepoint) dan Latihan 6 (demo bloat) |
| `dua_sesi.sh` | Skenario dua sesi: `isolasi`, `rr_konflik`, `locking`, `deadlock`, `antrean` |
| `jalankan.sh` | `praktik`, `latihan`, `sesi <skenario>`, `bersih` |
| `bersih.sql` | Menghapus tabel buatan modul ini |
| `verifikasi_sqlite.py`, `output_verifikasi_sqlite.txt` | Bukti logika Latihan 1 di SQLite |

**Tentang `dua_sesi.sh`:** dua proses `psql` dijalankan bersamaan di container, perintah dikirim bergantian lewat named pipe, dan sinkronisasinya memakai jeda `sleep`. Ini cara cepat untuk mereproduksi skenario modul, bukan harness uji yang kokoh. Bila hasilnya tidak sesuai atau tampak aneh, jalankan ulang atau lakukan manual di dua terminal seperti di modul. Keluaran kedua sesi ditampilkan terpisah di akhir, dan baris `[A]`/`[B]` di layar menunjukkan urutan perintahnya.

**Urutan:** `./jalankan.sh praktik` → `./jalankan.sh latihan` → `./jalankan.sh sesi isolasi` (dan skenario lain). Satu-satunya tabel yang dibuat modul ini (`rekening`, `log_transfer`, `tugas`) tidak dipakai modul lain.

---

## Praktik

### Atomicity

```sql
BEGIN;
UPDATE rekening SET saldo = saldo - 600000 WHERE id = 1;   -- melanggar CHECK
UPDATE rekening SET saldo = saldo + 600000 WHERE id = 2;   -- ditolak
ROLLBACK;
SELECT * FROM rekening;
```

**(diharapkan)**

| Langkah | Hasil |
|---|---|
| `UPDATE` pertama | `ERROR: new row for relation "rekening" violates check constraint "rekening_saldo_check"` (dengan `DETAIL: Failing row contains ...`) |
| `UPDATE` kedua | `ERROR: current transaction is aborted, commands ignored until end of transaction block` |
| `ROLLBACK`, lalu `SELECT` | `500000.00` dan `100000.00`, tidak ada yang berubah |

**Perbedaan penting yang saya temukan saat menguji di SQLite:** di SQLite, `UPDATE` kedua **diterima** setelah error pertama, karena transaksi tidak masuk status *aborted*. Itu menunjukkan mengapa perilaku PostgreSQL penting: setelah error, PostgreSQL menolak semua perintah sampai `ROLLBACK`, sehingga transfer setengah jadi (pengurangan gagal tetapi penambahan berhasil) **tidak mungkin tercommit tanpa disengaja**. Di SQLite, jika aplikasi lupa `ROLLBACK`, penambahan itu bisa tercommit.

### MVCC: Melihat Versi Baris

**(diharapkan)**

| Tahap | `xmin` | `xmax` | `ctid` |
|---|---|---|---|
| Awal, kedua baris | sama (ID transaksi yang meng-insert) | `0` | `(0,1)` dan `(0,2)` |
| Sesudah `UPDATE ... WHERE id = 1` | baris 1: **ID transaksi baru** | `0` | baris 1: **pindah** ke posisi baru, kemungkinan `(0,3)` |
| | baris 2: tidak berubah | `0` | `(0,2)` |

Nomor ID transaksi bergantung pada riwayat database Anda, jadi nilainya berbeda.

Inti pelajarannya: `UPDATE` **tidak menimpa** baris. Versi lama tetap ada secara fisik di `(0,1)` dengan `xmax` berisi ID transaksi pengubahnya, hanya tidak lagi terlihat oleh query biasa. Opsional (butuh superuser; belum saya uji) untuk melihat ketiga versi di halaman heap:

```sql
CREATE EXTENSION IF NOT EXISTS pageinspect;
SELECT lp, t_xmin, t_xmax, t_ctid FROM heap_page_items(get_raw_page('rekening', 0));
```

**(diharapkan)** 3 baris: dua milik `Andi`/`Budi` awal, satu versi baru `Andi`. Versi lama Andi memiliki `t_xmax` terisi dan `t_ctid` menunjuk ke versi barunya.

### Isolation Level

`./jalankan.sh sesi isolasi` menjalankan skenario dua kali (A memakai `READ COMMITTED`, lalu `REPEATABLE READ`), dengan data diatur ulang agar saldo awal Andi 500001.

**(diharapkan)** keluaran sesi A:

| Perintah A | `READ COMMITTED` | `REPEATABLE READ` |
|---|---|---|
| `SELECT` pertama (di dalam transaksi) | 500001.00 | 500001.00 |
| (B: `UPDATE ... saldo = 999`, autocommit) | | |
| `SELECT` kedua (masih di transaksi yang sama) | **999.00** | **500001.00** |
| `COMMIT`, lalu `SELECT` | 999.00 | **999.00** |

Setelah `COMMIT`, transaksi A berakhir dan SELECT berikutnya memakai snapshot baru, sehingga keduanya melihat 999.

Catatan akurasi: pada `REPEATABLE READ`, snapshot diambil pada **perintah pertama** setelah `BEGIN` (bukan pada `BEGIN` itu sendiri). Karena itu `SELECT` pertama pada skenario ini yang menentukan "foto" data.

### Locking dan SKIP LOCKED

`./jalankan.sh sesi locking` memakai `lock_timeout` agar tidak perlu `Ctrl+C` manual. **(diharapkan)**:

| Langkah | Hasil |
|---|---|
| A: `BEGIN; SELECT ... WHERE id = 1 FOR UPDATE;` | Baris 1 terkunci oleh A |
| B: `UPDATE rekening SET saldo = 1 WHERE id = 1;` | **Menunggu (blocked)** |
| Sesi ketiga: query `pg_stat_activity` | Satu baris: pid B, `diblokir_oleh` berisi pid A, `wait_event_type = Lock`, `wait_event` kemungkinan `transactionid` |
| Setelah 3 detik | Di B: `ERROR: canceling statement due to lock timeout` |
| B: `SELECT ... ORDER BY id FOR UPDATE SKIP LOCKED LIMIT 1;` | Mengembalikan baris **id = 2** (baris 1 dilewati) |
| A: `ROLLBACK;` | Kunci dilepas |

### Melihat WAL

**(diharapkan)**

| Perintah | Hasil |
|---|---|
| `SHOW wal_level;` | `replica` (default) |
| `pg_current_wal_lsn()` sebelum `UPDATE` | Nilai berbentuk `0/xxxxxxx` |
| `pg_current_wal_lsn()` sesudah `UPDATE` | **Nilai lebih besar** (LSN maju) |
| `pg_wal_lsn_diff(pg_current_wal_lsn(), '0/0')` | Angka (byte) total WAL sejak awal, jauh lebih besar dari selisih satu `UPDATE` |

LSN adalah posisi (*byte offset*) dalam aliran WAL. Fungsi `pg_current_wal_lsn()` hanya bisa dipanggil di server primary (bukan saat recovery/standby).

---

## Latihan 1: Transfer dengan `SAVEPOINT` dan `log_transfer`

```sql
BEGIN;
SAVEPOINT sebelum_transfer;                              -- SEBELUM pengurangan
UPDATE rekening SET saldo = saldo - 100000 WHERE id = 1; -- berhasil
UPDATE rekening SET saldo = saldo + 100000 WHERE id = 3; -- gagal
ROLLBACK TO SAVEPOINT sebelum_transfer;                  -- pengurangan ikut dibatalkan
INSERT INTO log_transfer (dari, ke, jumlah, status, pesan)
VALUES (1, 3, 100000, 'gagal', 'kredit ditolak: ...');
COMMIT;                                                  -- log tersimpan, saldo tidak berubah
```

**Agar penambahan bisa gagal secara realistis,** `latihan.sql` menyiapkan rekening Citra dengan saldo `9999999999.99`, yaitu batas maksimum `numeric(12,2)`. Menambah 100.000 menghasilkan **(diharapkan)** `ERROR: numeric field overflow`. Di aplikasi nyata, kegagalan seperti ini bisa berupa pelanggaran constraint, trigger yang menolak, deadlock, atau error serialisasi.

Hasil yang diharapkan di PostgreSQL, dan **terverifikasi logikanya di SQLite** (dengan `CHECK` sebagai pengganti overflow):

| | Andi | Budi | Citra | `log_transfer` |
|---|---|---|---|---|
| Setelah transfer 1 (Andi → Budi, berhasil) | 400.000 | 200.000 | 9.999.999.999,99 | 1 baris `berhasil` |
| Setelah transfer 2 (Andi → Citra, gagal) | **400.000 (tidak berubah)** | 200.000 | 9.999.999.999,99 | + 1 baris `gagal` |

**Mengapa letak `SAVEPOINT` penting:** soal berbunyi "jika pengurangan berhasil tetapi penambahan gagal, kembali ke savepoint". Jika savepoint dipasang **sesudah** pengurangan, `ROLLBACK TO` hanya membatalkan penambahan, sedangkan **pengurangan tetap tercommit**, sehingga uang Andi hilang tanpa berpindah ke mana pun. Terbukti di SQLite: total uang berkurang tepat 100.000. Jadi savepoint harus dipasang **sebelum** langkah pertama transfer.

**Mengapa `log_transfer` bisa tersimpan:** `ROLLBACK TO SAVEPOINT` hanya membatalkan perubahan setelah savepoint, dan juga mengeluarkan transaksi dari status *aborted*. `INSERT` ke log dilakukan sesudah itu, di transaksi yang sama, lalu ikut `COMMIT`. Jika kita memakai `ROLLBACK` penuh, log gagal itu ikut hilang, dan karena itulah savepoint dipakai.

Keluaran akhir pada skrip: `SELECT * FROM rekening` menampilkan 3 baris sesuai tabel di atas, dan `log_transfer` berisi 2 baris.

---

## Latihan 2: `READ COMMITTED` vs `REPEATABLE READ`

Jalankan `./jalankan.sh sesi isolasi`. Hasil yang diharapkan sudah ada pada tabel bagian Praktik di atas.

**Pengamatan terkait non-repeatable read:**

- **`READ COMMITTED`:** dua `SELECT` identik di **dalam satu transaksi** memberi hasil berbeda (500001.00 lalu 999.00). Itulah *non-repeatable read*. Penyebabnya, **setiap statement** mendapat snapshot baru, sehingga perubahan B yang sudah commit di antara dua statement terlihat.
- **`REPEATABLE READ`:** kedua `SELECT` memberi hasil sama (500001.00). Snapshot diambil sekali untuk seluruh transaksi, jadi perubahan B tidak terlihat sampai transaksi A selesai.

**Harga yang dibayar `REPEATABLE READ`:** jika A mencoba mengubah baris yang sudah diubah dan di-commit B sesudah snapshot A, PostgreSQL menolak. Skenario `./jalankan.sh sesi rr_konflik` menunjukkannya. **(diharapkan)**: `ERROR: could not serialize access due to concurrent update` (SQLSTATE `40001`). Aplikasi harus mengulang (*retry*) seluruh transaksi. `SERIALIZABLE` juga menghasilkan error `40001` saat mendeteksi anomali, sehingga logika retry wajib ada untuk kedua level itu.

---

## Latihan 3: Deadlock

`./jalankan.sh sesi deadlock` menjalankan urutan: A mengunci baris 1; B mengunci baris 2; A meminta baris 2 (menunggu B); B meminta baris 1 (menunggu A, sehingga **saling menunggu**).

**(diharapkan)** setelah sekitar `deadlock_timeout` (default 1 detik), salah satu sesi (biasanya yang mendeteksinya lebih dulu; tidak ditentukan sebelumnya) menerima:

```
ERROR:  deadlock detected
DETAIL:  Process X waits for ShareLock on transaction Y; blocked by process Z.
         Process Z waits for ShareLock on transaction W; blocked by process X.
HINT:  See server log for query details.
CONTEXT:  while updating tuple (0,N) in relation "rekening"
```

Kode SQLSTATE-nya `40P01`. Sesi korban dibatalkan dan transaksinya *aborted*, sedangkan sesi lain melanjutkan dan bisa `COMMIT`. Dengan begitu, `COMMIT` pada sesi korban sebenarnya berperilaku sebagai `ROLLBACK`. Rekening yang tersisa menunjukkan hanya perubahan dari sesi yang selamat.

**Cara mencegah:**

| Cara | Penjelasan |
|---|---|
| **Urutan kunci konsisten** | Semua transaksi mengunci baris dalam urutan yang sama, mis. selalu id kecil dulu. Pada transfer: `SELECT ... FROM rekening WHERE id IN (a, b) ORDER BY id FOR UPDATE;` lalu lakukan `UPDATE`. Dengan begitu tidak ada siklus tunggu. |
| Transaksi singkat | Semakin cepat commit, semakin kecil peluang bertabrakan |
| Hindari menunggu di dalam transaksi | Jangan menahan transaksi sambil menunggu input pengguna atau panggilan jaringan |
| `lock_timeout` | Batasi lama menunggu agar tidak menggantung |
| **Retry otomatis** | Tangkap error `40P01` (dan `40001`) di aplikasi lalu ulangi transaksi. Deadlock tidak bisa dihilangkan seluruhnya pada sistem yang sibuk. |

---

## Latihan 4: Job queue dengan `FOR UPDATE SKIP LOCKED`

`./jalankan.sh sesi antrean` membuat tabel `tugas(id, status)` berisi 5 tugas `baru`, lalu dua sesi worker mengambil tugas dengan pola satu pernyataan:

```sql
UPDATE tugas SET status = 'diproses'
WHERE id = (SELECT id FROM tugas WHERE status = 'baru'
            ORDER BY id FOR UPDATE SKIP LOCKED LIMIT 1)
RETURNING id;
```

**(diharapkan)**

| Langkah | Hasil |
|---|---|
| A: `BEGIN;` lalu perintah di atas | `id = 1` |
| B: `BEGIN;` lalu perintah yang sama (A belum commit) | **`id = 2`** (baris 1 yang dikunci A dilewati) |
| A dan B `COMMIT` | |
| `SELECT id, status FROM tugas` | id 1 dan 2 `diproses`; id 3, 4, 5 masih `baru` |

Kedua worker mendapat tugas berbeda, sehingga **tidak ada tugas yang diproses dua kali** (tidak ada id yang sama pada hasil A dan B, dan tiap tugas berubah status tepat satu kali).

**Bagian kedua skrip: tanpa `SKIP LOCKED`.** Dengan A menahan kunci baris 1 dan B memakai query yang sama tanpa `SKIP LOCKED`, B **menunggu** A. Dengan `lock_timeout = '2s'` **(diharapkan)** B menerima `ERROR: canceling statement due to lock timeout`. Tanpa timeout, B akan menunggu sampai A selesai. Artinya worker saling menunggu satu per satu dan antrean tidak lagi paralel. Perilaku persis B setelah A akhirnya commit tidak saya uji dan tidak saya klaim di sini.

**Mengapa pola ini aman:** pemilihan tugas dan penguncian terjadi **atomik** dalam satu statement, jadi tidak ada celah "baca lalu klaim" tempat dua worker melihat tugas yang sama. `SKIP LOCKED` membuat setiap worker langsung mengambil baris berikutnya yang tidak terkunci.

Catatan: antrean di PostgreSQL cocok untuk beban sedang. Pola lengkapnya (visibility timeout, retry, arsip) ada di Modul 11. Worker sebaiknya `COMMIT` segera setelah menandai `diproses`, bukan menahan transaksi selama pekerjaan berjalan (itu menahan `VACUUM`).

---

## Latihan 5: Mengapa cukup menulis WAL saat `COMMIT`

**Mengapa tidak menulis halaman data saat commit:**

- Satu `UPDATE` hanya mengubah beberapa byte, tetapi halaman data berukuran **8 KB** dan tersebar di berbagai lokasi file. Menulis halaman saat commit berarti banyak penulisan acak yang mahal, ditambah `fsync` ke banyak berkas.
- **WAL ditulis berurutan (append-only)** dan ringkas, sehingga satu `fsync` pada ujung log sudah cukup untuk menjamin durabilitas seluruh transaksi. Beberapa transaksi yang commit bersamaan bisa berbagi satu flush.
- Halaman data yang kotor tetap di memori (*shared buffers*) dan ditulis belakangan oleh *background writer* dan *checkpointer*. Beberapa perubahan pada halaman yang sama digabung dalam satu penulisan.

Prinsipnya **write-ahead**: catatan perubahan harus aman di disk **sebelum** transaksi dinyatakan commit, dan sebelum halaman data yang bersangkutan boleh ditulis.

**Server mati mendadak sebelum halaman data sempat ditulis:**

1. Halaman di memori hilang, sehingga file data belum memuat perubahan terbaru.
2. Saat dijalankan lagi, proses *startup* membaca WAL mulai dari titik *redo* checkpoint terakhir, lalu **memutar ulang** (*replay*) perubahan ke halaman data.
3. Transaksi yang sudah `COMMIT` (catatannya sudah ada di WAL yang di-`fsync`) pulih seluruhnya. Transaksi yang belum commit tidak punya catatan commit, sehingga perubahannya dianggap tidak pernah terjadi (tak terlihat oleh MVCC).

Nuansa yang perlu diketahui:

- Setelah checkpoint, perubahan **pertama** pada sebuah halaman menulis **salinan halaman penuh** ke WAL (`full_page_writes`), untuk melindungi dari *torn page* (halaman tertulis setengah saat crash). Jadi "WAL, bukan seluruh halaman" benar untuk sebagian besar catatan, tetapi tidak mutlak.
- Jaminan durabilitas bergantung pada `fsync` dan perangkat penyimpanan yang jujur. Dengan `synchronous_commit = off`, commit bisa dikembalikan sebelum WAL ter-flush: crash dapat menghilangkan beberapa commit terakhir (tetapi tidak merusak konsistensi). `fsync = off` dapat merusak database, jadi jangan dipakai selain untuk eksperimen.

---

## Latihan 6: Bloat akibat `UPDATE` yang sering

**Hubungan dengan MVCC:** `UPDATE` tidak menimpa baris. Ia membuat **versi baru** dan menandai versi lama sebagai kedaluwarsa (`xmax`). Setiap `UPDATE` dengan demikian menambah satu *dead tuple*. Jumlah baris hidup tetap, tetapi total versi fisik bertambah. Versi lama baru bisa dibuang bila **tidak ada transaksi yang masih membutuhkannya**.

Ruang itu direklamasi oleh `VACUUM`, tetapi:

| Faktor | Efek |
|---|---|
| `UPDATE` lebih cepat daripada vacuum | Dead tuple menumpuk, tabel dan index membengkak |
| **Transaksi panjang** (atau slot replikasi / `hot_standby_feedback`) | Menahan "horizon" pembersihan sehingga vacuum tidak boleh membuang versi lama, walau vacuum berjalan |
| `VACUUM` biasa tidak mengecilkan file | Ruang ditandai bisa dipakai ulang, tetapi file jarang mengecil (hanya halaman kosong di ujung file yang bisa dikembalikan ke OS) |
| Index | Setiap versi baru (non-HOT) menambah entri index, sehingga index ikut membengkak |

**Demo di `latihan.sql`** (10.000 baris, 5 kali `UPDATE` seluruh baris, `autovacuum_enabled = off` agar tidak terganggu). **(diharapkan, kualitatif)**:

| Tahap | Ukuran tabel |
|---|---|
| Awal | ukuran dasar |
| Setelah 5× `UPDATE` (baris hidup tetap 10.000) | **Jauh lebih besar**, dengan `n_dead_tup` besar |
| Setelah `VACUUM` | **Tidak mengecil** secara berarti; `n_dead_tup` turun mendekati 0 |
| Setelah 5× `UPDATE` lagi | **Hampir tidak bertambah**: ruang bekas dipakai ulang |
| Setelah `VACUUM FULL` | **Mengecil** (tabel ditulis ulang; butuh kunci `ACCESS EXCLUSIVE`) |

Angka pastinya tidak saya tuliskan karena belum dijalankan. `n_dead_tup` berasal dari statistik yang bisa tertinggal beberapa detik, karena itu skrip menyertakan `pg_sleep`.

**Cara menangani:**

- Atur autovacuum lebih agresif untuk tabel yang sering di-`UPDATE` (mis. `autovacuum_vacuum_scale_factor` lebih kecil per tabel). Dibahas di Modul 12.
- Hindari `UPDATE` yang tidak perlu (`WHERE kolom IS DISTINCT FROM nilai_baru`).
- Turunkan `fillfactor` pada tabel panas agar `UPDATE` bisa menempatkan versi baru di halaman yang sama (*HOT update*), yang tidak menambah entri index. HOT hanya terjadi bila kolom yang diubah tidak ter-index.
- Jaga transaksi tetap singkat.
- Untuk tabel yang sudah sangat membengkak: `VACUUM FULL` (menahan akses penuh) atau alat seperti `pg_repack` (kunci minimal).

---

## Lembar hasil Anda

| Langkah | Hasil Anda | Sesuai harapan? |
|---|---|---|
| Atomicity: error `rekening_saldo_check`, lalu `transaction is aborted` | | |
| MVCC: `ctid` dan `xmin` baris 1 berubah, baris 2 tidak | | |
| `sesi isolasi`: `READ COMMITTED` 500001 → 999; `REPEATABLE READ` 500001 → 500001 | | |
| `sesi rr_konflik`: `could not serialize access ...` | | |
| `sesi locking`: B menunggu, lalu `lock timeout`, `SKIP LOCKED` mengambil id 2 | | |
| `wal_level` dan LSN yang maju | | |
| Latihan 1: Andi tetap 400000 setelah transfer gagal, log berisi 2 baris | | |
| `sesi deadlock`: `deadlock detected` | | |
| `sesi antrean`: A dapat id 1, B dapat id 2 | | |
| Latihan 6: ukuran naik, tidak turun setelah `VACUUM`, turun setelah `VACUUM FULL` | | |

## Sebelum lanjut ke Modul 8

Modul 8 tidak memakai tabel dari modul ini. Anda boleh menjalankan `./jalankan.sh bersih` untuk menghapus `rekening`, `log_transfer`, `tugas`, dan `uji_bloat`.
