# Jawaban Modul 12: Arsitektur Internal & Konfigurasi

## Status eksekusi (baca dulu)

PostgreSQL, Docker, dan jaringan tidak tersedia di lingkungan saya, jadi **tidak ada perintah di modul ini yang sudah dijalankan di PostgreSQL**. Modul ini hampir seluruhnya tentang perilaku server: proses, memori, file, vacuum, konfigurasi, catalog. Itu tidak bisa ditiru SQLite. Karena itu:

- **Saya tidak menuliskan keluaran server sebagai fakta**: tidak ada angka ukuran file, jumlah proses, atau isi log yang saya klaim dari mesin.
- Yang saya berikan adalah **hitungan dan model** (berlabel jelas), skrip siap jalan, dan penjelasan.

| Bagian | Status |
|---|---|
| Ukuran `uji_bloat` dari tata letak halaman PostgreSQL; ambang autovacuum; usulan `shared_buffers` dan batas `work_mem` | **Hitungan** (`[hitungan]`), dengan asumsi yang saya tuliskan |
| Kapan dead tuple boleh dibuang (Latihan 3) | **Simulasi** model sederhana (`[SIMULASI]`). **Premis modelnya belum saya uji di PostgreSQL** (lihat Temuan 2). |
| Arah biaya `fsync` (Latihan 6) | SQLite (`[SQLite]`), hanya arah |
| Alur skrip dua sesi, `sesi_banyak.sh`, `log_lambat.sh` | Diuji dengan `docker` tiruan yang hanya menggemakan input: membuktikan perintah mengalir ke sesi yang benar, **bukan** perilaku database |
| `pg_stat_activity`, proses OS, ukuran file nyata, `VACUUM`, isi log, parameter | **Tidak bisa diuji.** Berlabel **(diharapkan)**. |

Total **24 pemeriksaan hitungan/model, semuanya sesuai harapan** (`output_verifikasi.txt`).

| Berkas | Fungsi |
|---|---|
| `praktik.sql`, `praktik_shell.sh` | Praktik, disalin langsung dari modul (isi tidak diubah) |
| `latihan.sql` | Latihan 2 (1 juta baris; semua di schema `latihan12`) |
| `sesi_banyak.sh` | Latihan 1 |
| `dua_sesi.sh` | Latihan 3 (tiga variasi: `rc`, `rr`, `tulis`) |
| `log_lambat.sh` | Latihan 4 |
| `bersih.sql`, `jalankan.sh` | `praktik`, `shell`, `latihan`, `sesi [N]`, `vacuum <rc\|rr\|tulis>`, `log`, `bersih` |
| `verifikasi.py`, `output_verifikasi.txt` | Hitungan dan model |

> **Jalankan `./jalankan.sh bersih` setelah selesai, sebelum Modul 13-16.** Praktik meninggalkan efek samping yang **tidak** dibersihkan modul sendiri (lihat Temuan 1).

---

## Temuan dari membaca modul ini

1. **`ALTER ROLE postgres IN DATABASE toko SET statement_timeout = '60s'` tidak pernah di-reset.** Praktik hanya me-reset `work_mem`. Pengaturan itu menempel pada **setiap sesi baru** role `postgres` di database `toko`: juga `pg_dump`, `CREATE INDEX`, dan pemuatan data yang panjang di modul berikutnya, yang bisa dibatalkan pada detik ke-60. Lebih halus lagi, Modul 16 nanti menjalankan `ALTER DATABASE toko SET statement_timeout = '30s'`, tetapi pengaturan *role di database* **berprioritas lebih tinggi** daripada pengaturan database saja, sehingga nilai 60 detik dari modul ini akan menimpanya. `bersih.sql` me-reset keduanya, juga opsi autovacuum pada `transaksi`.
2. **Resep Latihan 3 kemungkinan tidak memperlihatkan efeknya.** Teks latihan menyuruh `BEGIN; SELECT ...;` tanpa commit pada tingkat isolasi bawaan (`READ COMMITTED`). Berdasarkan cara PostgreSQL mengelola snapshot, transaksi `READ COMMITTED` yang **hanya membaca** dan sedang idle **tidak memegang snapshot maupun ID transaksi**, sehingga tidak menahan *xmin horizon* dan `VACUUM` tetap bisa membuang dead tuple. Ini pemahaman saya, **belum diuji**, dan memang itulah yang diperiksa `dua_sesi.sh rc`. Efek yang dimaksud modul baru muncul bila sesi itu **menahan snapshot** (`REPEATABLE READ`) atau **memegang xid** (sudah menulis). Itulah dua variasi lain pada skrip.
3. **Praktik Bloat bisa "dibantu" autovacuum sebelum Anda melihatnya.** `UPDATE` 200.000 baris (jauh di atas ambang 50 + 0,2 × 200.000 = 40.050) memicu autovacuum dalam ±1 menit (`autovacuum_naptime`). Selain itu, `n_dead_tup` berasal dari statistik yang bisa tertinggal beberapa detik. `latihan.sql` mematikan autovacuum **hanya pada tabel ujinya**.
4. **`ps aux` mungkin tidak ada di image.** Bila perintahnya gagal, gunakan `docker top pg-latihan` (skrip `sesi_banyak.sh` memakainya).
5. **`uji_bloat` tidak dihapus oleh modul** dan jatuh di schema `app` atau `public` bergantung sesi mana yang membuatnya. `bersih.sql` menghapus keduanya.
6. **`VACUUM FULL` butuh ruang disk kosong sebesar salinan baru tabel**, karena menulis ulang seluruh tabel. Pada Latihan 2 itu berarti ratusan MB di dalam container.

---

## Praktik

### Proses dan Memori

**(diharapkan)**

| Perintah | Yang dicari |
|---|---|
| `SELECT pid, backend_type, state FROM pg_stat_activity ...` | Satu `client backend` (sesi Anda) ditambah proses latar belakang: `checkpointer`, `background writer`, `walwriter`, `autovacuum launcher`, `logical replication launcher`, dan (PostgreSQL 18, sesuai diagram modul) beberapa `io worker`. Daftar persisnya bergantung versi dan konfigurasi. |
| `SHOW shared_buffers; work_mem; max_connections; wal_level` | Nilai bawaan: `128MB`, `4MB`, `100`, `replica` |
| `ps aux \| grep postgres` | Satu proses `postmaster` induk, proses latar belakang bernama (`postgres: checkpointer`, dst.), dan satu proses `postgres: postgres toko [local] ...` per koneksi klien. Itulah model **proses per koneksi**. |

### Layout File dan Ukuran

**(diharapkan)**

| Perintah | Yang dicari |
|---|---|
| `pg_relation_filepath('transaksi')` | Jalur berbentuk `base/<oid database>/<filenode>` |
| Ukuran tabel, index, total | `pg_indexes_size('transaksi')` kemungkinan **lebih besar** daripada tabelnya, karena `transaksi` kini memiliki banyak index dari Modul 9 (termasuk GIN trigram). `total = tabel + index + TOAST`. Angka pastinya tidak saya tuliskan. |
| `SELECT oid, datname FROM pg_database` | `template1` = 1, `template0` = 4, `postgres` = 5, dan `toko` bernomor di atas 16383 (OID objek pengguna dimulai dari 16384) |
| `ls $PGDATA` | `PG_VERSION`, `base`, `global`, `pg_wal`, `pg_xact`, `postgresql.conf`, `postgresql.auto.conf`, `pg_hba.conf`, dll. `PGDATA` pada image 18+ biasanya `/var/lib/postgresql/18/docker`. |
| `ls $PGDATA/pg_wal \| head` | Berkas segmen WAL berukuran 16 MB (nama 24 karakter heksadesimal) dan folder `archive_status` |

### Bloat dan Vacuum

**Hitungan ukuran dari tata letak halaman** (`[hitungan]`, bukan pengukuran). Asumsi: halaman 8 KB, mesin 64-bit (`MAXALIGN` = 8), tidak ada nilai `NULL`, `fillfactor` 100:

| Langkah perhitungan | Hasil |
|---|---|
| Header tuple (23 byte, dibulatkan) | 24 byte |
| `id` integer | 4 byte |
| `isi` (`repeat('x', 100)` bertipe text, header pendek 1 byte) | 101 byte |
| Panjang tuple 24 + 4 + 101 = 129, dibulatkan ke kelipatan 8 | **136 byte** |
| Ditambah *item pointer* 4 byte | **140 byte per baris** |
| Ruang pakai per halaman: 8192 − 24 (header halaman) = 8168; 8168 ÷ 140 | **58 baris per halaman** |
| 200.000 baris ÷ 58 | **3.449 halaman = 28.254.208 byte ≈ `27 MB`** |

Sisa ruang pada halaman penuh hanya 48 byte, lebih kecil daripada satu tuple (140 byte), sehingga `UPDATE` tidak bisa menaruh versi baru di halaman yang sama dan **semua versi baru masuk ke halaman baru**. Maka ukuran tabel kira-kira **2×** setelah `UPDATE` seluruh baris, sesuai komentar modul ("hampir 2x lipat").

**(diharapkan) pada Praktik, per langkah:**

| Langkah | Ukuran |
|---|---|
| Awal | ≈ 27 MB |
| Setelah `UPDATE` seluruh baris | ≈ 2× (≈ 54 MB) |
| `n_dead_tup` | Besar (≈ 200.000), kecuali autovacuum sudah berjalan (Temuan 3) |
| Setelah `VACUUM (VERBOSE)` | **Ukuran file tetap.** Output verbose melaporkan dead tuple yang dibuang dan halaman yang dipindai. `n_dead_tup` turun mendekati 0. |
| Setelah `VACUUM FULL` | Kembali ke ≈ 27 MB |

Perkiraan ini bergantung pada asumsi tata letak di atas. Bila hasil nyata Anda sedikit berbeda, rasio **±2× lalu kembali** tetap yang menjadi inti pelajarannya.

### Konfigurasi

**(diharapkan)**

| Langkah | Hasil |
|---|---|
| `pg_settings` untuk tiga parameter | `shared_buffers` dan `max_connections`: `context = postmaster` (perlu restart). `work_mem`: `context = user`. |
| `ALTER SYSTEM SET work_mem = '32MB'`, `pg_reload_conf()`, `SHOW work_mem` | `32MB` (tanpa restart, karena konteks `user`). Tersimpan di `postgresql.auto.conf`. |
| `ALTER ROLE postgres IN DATABASE toko SET statement_timeout = '60s'` lalu `pg_db_role_setting` | Satu baris dengan `setconfig = {statement_timeout=60s}`. **Jangan lupa mengembalikannya (Temuan 1).** |
| `ALTER TABLE transaksi SET (autovacuum_vacuum_scale_factor = 0.02)` lalu `reloptions` | `{autovacuum_vacuum_scale_factor=0.02}` |

Dengan 0,02, ambang autovacuum untuk `transaksi` (1,2 juta baris) turun dari 50 + 0,2 × 1.200.000 = **240.050** menjadi 50 + 0,02 × 1.200.000 = **24.050** baris dead tuple (hitungan).

### System Catalog

**(diharapkan)** Query `pg_class` menampilkan tabel biasa (`relkind = 'r'`) di schema `app`, dengan `estimasi_baris` dari `reltuples` (nilai estimasi dari `ANALYZE`/vacuum terakhir, bukan hitungan eksak; `-1` bila belum pernah dianalisis). Tabel berpartisi (`relkind = 'p'`, mis. `log_aktivitas` dari Modul 11 bila belum dibersihkan) tidak muncul karena filter `'r'`, tetapi partisinya muncul. `information_schema.columns` untuk `produk` menampilkan kolom hasil modul-modul sebelumnya (mis. `kategori`, `diubah_pada`, `merek`) selain kolom aslinya, bergantung apa yang sudah/ belum dibersihkan.

---

## Latihan 1: Tiga sesi `psql` dan 2.000 koneksi

`./jalankan.sh sesi` membuka 3 sesi bersamaan (masing-masing `pg_sleep(25)`), lalu menampilkan `pg_stat_activity` dan proses OS.

**(diharapkan)** `client backend` bertambah **tiga baris**, ditambah **satu** untuk sesi pemeriksa itu sendiri, jadi total empat selama sesi tidur masih hidup. Proses latar belakang tidak bertambah. Pada daftar proses OS, tiap koneksi tampil sebagai **proses `postgres` terpisah**. Itulah model proses-per-koneksi.

**Konsekuensi bila ada 2.000 koneksi aktif:**

| Aspek | Akibat |
|---|---|
| **`max_connections`** | Bawaan 100. Koneksi di atas batas ditolak: `FATAL: sorry, too many clients already`. Menaikkannya ke 2.000 butuh **restart** dan menambah ukuran shared memory. |
| **Memori** | Tiap koneksi adalah proses OS dengan memori privat sendiri, **ditambah** `work_mem` per node sort/hash yang dijalankan. Lonjakan beban dapat menghabiskan RAM (Latihan 5). |
| **Penjadwalan CPU** | Ribuan proses saling berebut inti CPU, sehingga banyak waktu habis untuk *context switch*. Jumlah query yang benar-benar aktif bersamaan jauh lebih kecil daripada jumlah koneksi. |
| **Kontensi internal** | Struktur bersama seperti daftar proses (untuk mengambil snapshot) dan tabel kunci menjadi titik rebutan yang makin terasa dengan banyaknya koneksi. |

**Solusi:** *connection pooling* (PgBouncer, Modul 15): ribuan klien berbagi puluhan koneksi sebenarnya. Aplikasi menyimpan koneksi ke pooler, dan pooler yang menjaga jumlah koneksi ke PostgreSQL tetap kecil dan terkendali.

Peringatan untuk `./sesi_banyak.sh N`: N besar (di atas 100) akan menabrak batas koneksi dan memakan memori container. Lakukan hanya bila Anda ingin melihatnya.

---

## Latihan 2: `UPDATE` 1 juta baris, `VACUUM`, `VACUUM FULL`

`./jalankan.sh latihan` memakai tabel 1 juta baris dengan struktur yang sama seperti Praktik (autovacuum dimatikan pada tabel ini).

**Hitungan** (`[hitungan]`, asumsi tata letak di atas; hasil nyata Anda yang menentukan):

| Langkah | Halaman | Ukuran | Catatan |
|---|---|---|---|
| 1. Awal | 17.242 | **≈ 135 MB** | 1.000.000 ÷ 58 baris per halaman |
| 2. Setelah `UPDATE` seluruh baris | ≈ 34.484 | **≈ 269 MB** (≈ 2×) | Semua versi baru ke halaman baru; `n_dead_tup` ≈ 1.000.000 |
| 3. Setelah `VACUUM` | tetap ≈ 34.484 | **tetap ≈ 269 MB** | Dead tuple dibuang; ruangnya ditandai bisa dipakai ulang |
| 4. Setelah `UPDATE` seluruh baris lagi | **hampir tetap** | ≈ 269 MB | 1 juta tuple baru muat persis di halaman yang dibebaskan (17.242 × 58 = 1.000.036) |
| 5. Setelah `VACUUM FULL` | 17.242 | **≈ 135 MB** | Tabel ditulis ulang; nama file (`relfilenode`) berganti |

`latihan.sql` mencetak `ukuran` dan `halaman` di setiap langkah, plus `pg_relation_filepath` sebelum dan sesudah `VACUUM FULL` (**diharapkan** berbeda, karena tabel ditulis ke berkas baru).

**Mengapa `VACUUM` biasa tidak mengecilkan file tetapi tetap berguna:**

- Ia hanya **menandai** ruang dead tuple sebagai bisa dipakai ulang, tanpa memindahkan data. File hanya bisa dipotong bila halaman **di ujung** file kosong semua, dan pada kasus ini ujung file berisi baris hidup.
- **Manfaatnya:** (1) pertumbuhan tabel **berhenti**, karena `INSERT`/`UPDATE` berikutnya memakai ruang bekas (langkah 4); (2) memperbarui *visibility map*, sehingga `Index Only Scan` efektif; (3) memperbarui *free space map*; (4) **membekukan** (*freeze*) ID transaksi tua untuk mencegah *transaction ID wraparound*; (5) tidak mengunci baca/tulis.
- `VACUUM FULL` mengecilkan file tetapi menahan kunci `ACCESS EXCLUSIVE` selama menulis ulang seluruh tabel (semua baca dan tulis menunggu) dan butuh ruang disk tambahan sebesar salinan baru. Karena itu hindari di produksi; alternatifnya `pg_repack`.

---

## Latihan 3: Transaksi menggantung dan `VACUUM`

`./jalankan.sh vacuum rc|rr|tulis` menjalankan tiga variasi. Dalam tiap variasi sesi A menggantung **sebelum** sesi B meng-`UPDATE` seluruh 100.000 baris, lalu sesi B menjalankan `VACUUM (VERBOSE)` sebelum dan sesudah sesi A selesai.

**Yang dicari dalam keluaran:** pada `VACUUM VERBOSE`, jumlah tuple yang **dibuang** (*removed*) dan yang **mati tetapi belum bisa dibuang** (*dead but not yet removable*); serta kolom `backend_xid`/`backend_xmin` sesi A pada `pg_stat_activity`.

**(diharapkan)**, dengan premis Temuan 2:

| Variasi sesi A | Menahan horizon? | Hasil `VACUUM` pertama |
|---|---|---|
| `rc`: `BEGIN; SELECT ...;` (READ COMMITTED, idle) | **Tidak** (diperkirakan `backend_xmin` dan `backend_xid` kosong) | Dead tuple **dibuang** |
| `rr`: `REPEATABLE READ; SELECT ...;` | **Ya**: snapshot diambil sebelum update | Dead tuple **tidak bisa dibuang** (mendekati 100.000 "belum bisa dibuang") |
| `tulis`: `BEGIN; UPDATE satu baris;` | **Ya**: memegang ID transaksi | Hampir seluruh dead tuple **tidak bisa dibuang** |
| (sesudah sesi A `ROLLBACK`) | | `VACUUM` kedua membuang dead tuple |

**Simulasi model** (`[SIMULASI]`, 1.000 dead tuple dihapus oleh transaksi ber-xid 105): jumlah yang bisa dibuang adalah **1.000** bila tidak ada sesi lain, **1.000** untuk READ COMMITTED yang hanya membaca (**berdasarkan premis tadi**), **0** untuk snapshot REPEATABLE READ yang diambil sebelum update, **0** untuk sesi yang memegang xid, dan **1.000** bila snapshot REPEATABLE READ baru diambil **sesudah** update (dead tuple itu sudah mati sebelum snapshot dibuat). Model ini hanya menerjemahkan aturannya, bukan mengukur PostgreSQL.

**Mengapa dead tuple tertahan:** `VACUUM` hanya boleh membuang versi baris yang **tidak lagi dibutuhkan siapa pun**. Sebuah sesi dengan snapshot lama (atau ID transaksi lama) masih bisa membutuhkan versi lama untuk membaca keadaan data pada saat snapshot itu. PostgreSQL menghitung "batas bawah" dari semua sesi (*xmin horizon*), dan hanya versi yang sudah mati **sebelum** batas itu yang boleh dibuang. Selama batas itu tertahan, tabel membengkak (Latihan 2).

**Penyebab lain yang menahan horizon** (dari teori 12.4): *slot replikasi* yang tertinggal, *prepared transaction* yang terlupakan, dan `hot_standby_feedback` dari replika. **Pencegahan:** `idle_in_transaction_session_timeout`, `statement_timeout`, pantau `pg_stat_activity` (usia `xact_start`, `backend_xmin`), dan pantau slot replikasi.

---

## Latihan 4: Mencatat query lambat dengan `log_min_duration_statement`

`./jalankan.sh log` mengaktifkan `log_min_duration_statement = '100ms'` lewat `ALTER SYSTEM`, memuat ulang konfigurasi, menjalankan query cepat dan dua query lambat, mencari baris di `docker logs`, lalu mengembalikan pengaturan.

**(diharapkan)** `SHOW` menampilkan `100ms` tanpa restart (parameter berkonteks `superuser`, cukup reload). `SELECT 1` tidak tercatat. `SELECT pg_sleep(0.3)` tercatat dengan bentuk seperti:

```
2026-11-26 10:15:42.123 UTC [1234] LOG:  duration: 300.456 ms  statement: SELECT pg_sleep(0.3);
```

(awalan waktu dan nomor proses mengikuti `log_line_prefix` bawaan `%m [%p] `). Image resmi menulis log ke *stderr* sehingga terbaca lewat `docker logs`.

Catatan: log mencatat **teks query lengkap termasuk nilai literalnya**, yang bisa memuat data sensitif. Untuk produksi, pertimbangkan `log_min_duration_sample`, `auto_explain` untuk menangkap rencana, dan pengaturan akses log. Skrip mengembalikan nilai ke bawaan dengan `ALTER SYSTEM RESET`. `bersih.sql` juga melakukannya.

---

## Latihan 5: `shared_buffers` dan batas `work_mem` untuk server 16 GB

**Usulan awal `shared_buffers`** = 25% × 16 GB = **4 GB** (titik awal umum dari teori; bukan nilai optimal mutlak).

**Rumus batas `work_mem`:**

> `work_mem_maks = (RAM − shared_buffers − cadangan) / (koneksi_aktif × node_per_query × pengali)`

- **cadangan** = memori untuk OS, *page cache*, `maintenance_work_mem`/autovacuum, dan overhead per koneksi. **Asumsi saya: 25% RAM = 4 GB.** Ubah sesuai kondisi Anda.
- **koneksi_aktif** = 100, **node_per_query** = 2 (soal).
- **pengali** menampung dua hal yang membuat pemakaian riil bisa lebih besar: `hash_mem_multiplier` (hash boleh memakai kelipatan `work_mem`, bawaan 2,0 sejak PostgreSQL 15 sepengetahuan saya) dan query paralel (tiap worker memakai jatahnya sendiri).

Hasil hitungan (`[hitungan]`; memori tersedia = 16384 − 4096 − 4096 = **8192 MiB**, pembagi dasar 100 × 2 = 200):

| Kasus terburuk yang dibayangkan | Pengali | `work_mem` maksimum |
|---|---|---|
| Dasar | 1 | **40,96 MiB** |
| Semua node hash (`hash_mem_multiplier` = 2) | 2 | 20,48 MiB |
| Paralel (1 leader + 2 worker) | 3 | 13,65 MiB |
| Hash dan paralel sekaligus | 6 | 6,83 MiB |

**Jawaban:** batas teoretis atas ≈ **40 MiB** untuk skenario paling sederhana. Pada praktiknya, bila Anda mempertimbangkan hash dan paralel, nilai **global sekitar 8-16 MiB** adalah titik awal yang lebih aman, lalu naikkan **per sesi/transaksi** (`SET LOCAL`) atau per role pelaporan untuk query berat. Ini hitungan terburuk (seluruh koneksi aktif memakai seluruh node sekaligus). Rata-rata pemakaian nyata biasanya jauh di bawahnya, tetapi lonjakan beban justru pada saat yang paling tidak tepat. `effective_cache_size` hanya petunjuk untuk planner dan tidak mengalokasikan memori.

---

## Latihan 6: Mengapa `fsync = off` berbahaya

**Mengapa mempercepat:** `fsync` membuat PostgreSQL memaksa data (terutama WAL saat `COMMIT`) benar-benar sampai ke media penyimpanan dan menunggu konfirmasinya. Itu langkah paling lambat di jalur commit. Dengan `fsync = off`, PostgreSQL menyerahkan data ke cache OS dan segera melanjutkan.

**Arah pembuktiannya di SQLite** (3.000 commit satu per baris, file di disk): `synchronous = FULL` **1,728 detik**, `synchronous = OFF` **0,0434 detik**, sekitar **40× lebih cepat**. Itu milik SQLite pada mesin ini dan **bukan** angka untuk PostgreSQL, tetapi memperlihatkan bahwa hampir seluruh biaya commit adalah menunggu `fsync`.

**Mengapa tidak boleh di produksi:** bila listrik atau OS mati, data yang sudah "di-commit" bisa belum sampai ke media. Lebih buruk lagi, **urutan penulisan** WAL dan halaman data tidak lagi terjaga, sehingga setelah crash klaster bisa **rusak dan tidak konsisten secara diam-diam**, tidak sekadar kehilangan beberapa transaksi terakhir. Jaminan *write-ahead* (Modul 7) bergantung pada `fsync`. Tanpanya, pemulihan dari WAL tidak bisa dipercaya.

**Bedakan dari alternatif yang lebih aman:**

| Pengaturan | Risiko |
|---|---|
| `fsync = off` | **Kerusakan data yang tidak bisa dipulihkan** saat crash OS/listrik |
| `synchronous_commit = off` | Kehilangan beberapa commit terakhir (jendela pendek), tetapi database **tetap konsisten** |
| Tabel `UNLOGGED` | Hanya tabel itu yang dikosongkan saat crash; tabel lain tetap aman |

**Kapan (jika ada) wajar dimatikan:** hanya bila **seluruh isi database bisa dibuat ulang** dan kehilangannya tidak masalah: database uji di CI, container pengembangan sekali pakai, atau pemuatan awal sekali jalan ke klaster **baru** yang bisa di-*init* ulang bila crash. Pada kasus terakhir, nyalakan `fsync` lagi dan pastikan data sudah ter-flush ke media sebelum mengandalkannya. Jangan pernah untuk data yang tidak bisa Anda buat ulang.

---

## Lembar hasil Anda

| Langkah | Hasil Anda | Sesuai harapan? |
|---|---|---|
| Praktik: daftar `backend_type` di `pg_stat_activity` | | |
| Praktik: `shared_buffers`, `work_mem`, `max_connections`, `wal_level` | | |
| Praktik: `pg_relation_filepath` dan OID database | | |
| Praktik Bloat: ukuran awal (≈ 27 MB?) dan sesudah `UPDATE` (≈ 2×?) | | |
| Praktik Bloat: ukuran sesudah `VACUUM` dan sesudah `VACUUM FULL` | | |
| Praktik: `pg_db_role_setting` berisi `statement_timeout=60s` (lalu di-reset) | | |
| Latihan 1: jumlah `client backend` sebelum/sesudah | | |
| Latihan 2: halaman/ukuran tiap langkah (bandingkan dengan hitungan) | | |
| Latihan 3: `rc`, `rr`, `tulis`: berapa tuple "dead but not yet removable"? | | |
| Latihan 3: `backend_xmin`/`backend_xid` sesi A pada tiap variasi | | |
| Latihan 4: baris `duration:` di `docker logs` | | |

## Sebelum lanjut ke Modul 13

**Jalankan `./jalankan.sh bersih`.** Perintah itu me-reset `statement_timeout` role di database (Temuan 1), opsi autovacuum pada `transaksi`, parameter `ALTER SYSTEM`, dan menghapus `uji_bloat`, `uji_horizon`, serta schema `latihan12`. Di akhir ia menampilkan `pg_db_role_setting` dan `reloptions` agar Anda bisa memastikan semuanya bersih. Modul 13 (security) bekerja pada role, hak akses, dan `pg_hba.conf`, jadi sisa `statement_timeout` dari modul ini akan membingungkan bila ada yang gagal pada detik ke-60.
