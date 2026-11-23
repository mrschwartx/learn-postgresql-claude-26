# Jawaban Modul 3: Instalasi, Setup & psql

## Status eksekusi (baca dulu)

**Modul ini berpraktik penuh dengan Docker dan `psql`. Keduanya tidak tersedia di lingkungan tempat saya menyiapkan jawaban ini (tidak ada Docker, tidak ada PostgreSQL, tidak ada akses jaringan untuk memasangnya). Jadi tidak ada perintah di modul ini yang sudah saya jalankan sungguhan.**

Yang saya lakukan:

- Menulis skrip dan berkas SQL siap pakai. Sintaks shell sudah diperiksa dengan `bash -n`.
- Menuliskan **hasil yang diharapkan** berdasarkan perilaku PostgreSQL yang terdokumentasi. Setiap hasil seperti itu diberi label **(diharapkan)**.
- Menjawab latihan konseptual secara tertulis.

Hasil yang **tidak** saya tulis karena tidak bisa saya pastikan: nomor versi tepat (`18.x`), path persis, waktu eksekusi, dan format keluaran `\conninfo` (berubah antarversi). Isi kolom "Hasil Anda" di akhir berkas ini setelah menjalankannya.

| Berkas | Fungsi |
|---|---|
| `praktik.sh` | Menjalankan Praktik: `mulai`, `eksplorasi`, `service`, `bersih`, `semua` |
| `eksplorasi.sql` | Perintah `psql` bagian "Eksplorasi di psql" (idempoten) |
| `latihan.sh` | Membantu Latihan 1-5: `1`, `2`, `3`, `4`, `5`, `bersih` |

Prasyarat: Docker berjalan, port 5432/5433/5434 kosong. Jalankan dengan `chmod +x *.sh` bila perlu.

---

## Praktik

### Menjalankan PostgreSQL

```bash
./praktik.sh mulai        # setara docker run ... postgres:18 + menunggu siap + docker logs | tail -5
```

**(diharapkan)** Log berakhir dengan kalimat *database system is ready to accept connections*. Saat inisialisasi pertama, kalimat itu muncul dua kali karena image menjalankan server sementara lebih dulu.

Dua perbaikan kecil dari perintah di modul:

1. **Menunggu siap.** `docker logs` yang dijalankan sesaat setelah `docker run` bisa tampil sebelum server siap. Skrip memakai `pg_isready -h 127.0.0.1` (lewat TCP). Cek tanpa `-h` bisa lolos terlalu cepat karena server sementara saat inisialisasi hanya mendengarkan di socket Unix.
2. **Password.** `POSTGRES_PASSWORD=rahasia` hanya untuk latihan.

### Eksplorasi di psql

```bash
./praktik.sh eksplorasi
```

Hasil yang diharapkan per langkah:

| Perintah | (diharapkan) |
|---|---|
| `SELECT version();` | Teks yang menyebut `PostgreSQL 18.x` dan arsitektur Linux image |
| `SHOW server_version;` | `18.x` |
| `SHOW data_directory;` | Di image 18+: `/var/lib/postgresql/18/docker` |
| `SHOW port;` | `5432` (port **di dalam** container; `-p` hanya memetakan ke host) |
| `\l` | Database `postgres`, `template0`, `template1`, lalu `toko` bila sudah dibuat |
| `SELECT 1 + 1 AS hasil;` | `2` |

Pembuktian NULL (verifikasi Latihan 3 Modul 2). Hasil ini deterministik:

```
 sama | is_null | or_true | and_false | coalesce_3 | distinct_null
------+---------+---------+-----------+------------+---------------
      | t       | t       | f         |          3 | f
```

`sama` tampil kosong karena nilainya NULL. Hasil ini sama dengan perhitungan manual di Modul 2. Dengan `CREATE DATABASE toko; \c toko`, `\conninfo` menunjukkan koneksi ke database `toko` sebagai user `postgres` lewat socket Unix, karena Anda berada di dalam container.

### Mengelola Service

```bash
./praktik.sh service
```

**(diharapkan)**

| Aksi | `pg_postmaster_start_time()` |
|---|---|
| Sebelum apa pun | T0 |
| Sesudah `pg_reload_conf()` (setara `reload`) | **Tetap T0**: proses postmaster tidak dimulai ulang, koneksi tidak putus |
| Sesudah `docker restart` (setara `restart`) | **Berubah** ke waktu baru |

### Membersihkan Lingkungan

```bash
./praktik.sh bersih       # docker rm -f pg-latihan && docker volume rm pgdata
```

---

## Latihan 1: Volume dan persistensi

```bash
./latihan.sh 1
```

**Jawaban: ya, database `toko` masih ada** setelah container dihapus dan dibuat ulang dengan volume yang sama.

**Mengapa:** data directory berada di *named volume* `pgdata` (dipasang di `/var/lib/postgresql`), bukan di lapisan tulis container. `docker rm -f` hanya menghapus container, sedangkan named volume tetap ada sampai dihapus eksplisit (`docker volume rm`). Container baru yang memasang volume yang sama menemukan data directory yang sudah terisi, lalu PostgreSQL memakainya apa adanya.

Hal yang perlu diwaspadai:

| Perilaku | Penjelasan |
|---|---|
| **`POSTGRES_PASSWORD` diabaikan** pada volume yang sudah terisi | Variabel ini hanya dipakai saat inisialisasi data directory yang masih kosong. Password lama tetap berlaku. |
| **Skrip di `/docker-entrypoint-initdb.d/` tidak dijalankan ulang** | Alasannya sama: hanya jalan saat inisialisasi pertama. |
| **Versi mayor harus sama** | Volume dari 18 tidak bisa dipakai image 17 (lihat Latihan 5). |
| **Tanpa `-v`, data hilang bersama container** | Pada image 18 `/var/lib/postgresql` dideklarasikan sebagai volume, sehingga Docker membuat *volume anonim* yang sulit dilacak. Selalu beri nama volume. |

---

## Latihan 2: `\d`, `\d+`, dan `\dt+`

```bash
./latihan.sh 2
```

Skrip membuat tabel `contoh (id int PRIMARY KEY, nama text NOT NULL)` lalu menjalankan ketiga perintah.

| Perintah | Isi |
|---|---|
| `\d contoh` | Kolom (nama, tipe, collation, nullable, default), index (termasuk index PK), dan constraint |
| `\d+ contoh` | Semua yang ada di `\d`, **ditambah** kolom *Storage* (plain/extended/main/external), *Stats target*, dan *Description* (komentar), serta informasi tambahan seperti *Access method* |
| `\dt+` | Daftar tabel di schema yang terlihat, dengan kolom **Size** (ukuran di disk) dan *Description* |

Singkatnya, `+` berarti "tampilkan lebih detail". Untuk tabel yang baru dibuat dan kosong, ukuran biasanya 0 bytes atau hanya beberapa KB. Detail kolom Storage dibahas di Modul 12.

---

## Latihan 3: `reload` vs `restart`

```bash
./latihan.sh 3
```

| | `reload` | `restart` |
|---|---|---|
| Mekanisme | Mengirim sinyal `SIGHUP` ke postmaster (`pg_reload_conf()`, `pg_ctl reload`, `systemctl reload`) | Menghentikan lalu menjalankan ulang server |
| Koneksi | **Tidak diputus** | **Semua diputus** |
| Efek | Membaca ulang file konfigurasi | Memuat semua parameter dari awal |
| Parameter | Hanya yang konteksnya bukan `postmaster` | Semua, wajib untuk konteks `postmaster` |

Kolom `context` pada `pg_settings` menentukan kapan parameter berlaku:

| `context` | Artinya |
|---|---|
| `postmaster` | **Wajib restart** |
| `sighup` | Cukup **reload** |
| `superuser`, `user` | Bisa diubah per sesi (`SET`), atau global lewat reload |
| `backend`, `superuser-backend` | Berlaku untuk koneksi *baru* |
| `internal` | Tidak bisa diubah |

Contoh:

- **Cukup reload:** `autovacuum_naptime` (`sighup`), `log_min_duration_statement` (`superuser`, bisa diubah lewat reload atau `SET` per sesi).
- **Wajib restart:** `shared_buffers` dan `max_connections` (`postmaster`).

**(diharapkan)** pada skrip `latihan.sh 3`:

1. Setelah `ALTER SYSTEM SET log_min_duration_statement` dan `pg_reload_conf()`, `SHOW` langsung menampilkan `100ms`.
2. Setelah `ALTER SYSTEM SET shared_buffers = '256MB'` dan `pg_reload_conf()`, `pg_settings` menampilkan `pending_restart = t` dan nilai lama tetap aktif.
3. Setelah restart, `SHOW shared_buffers` menunjukkan `256MB`.
4. Skrip lalu mengembalikan kedua parameter ke default (`ALTER SYSTEM RESET`). `ALTER SYSTEM` menulis ke `postgresql.auto.conf` di data directory, sehingga perubahannya **bertahan** di volume bila tidak dikembalikan.

---

## Latihan 4: Koneksi dari host dengan URI

```bash
./latihan.sh 4
# setara:
PGPASSWORD=rahasia psql "postgresql://postgres@localhost:5432/toko" -c '\conninfo'
```

Format URI: `postgresql://USER:PASSWORD@HOST:PORT/DATABASE`.

**(diharapkan)** `\conninfo` menunjukkan koneksi ke database `toko`, user `postgres`, host `localhost`, port `5432`, lewat TCP. Berbeda dari `docker exec`, yang memakai socket Unix tanpa host. Format tampilannya berbeda antarversi `psql`.

Jika bermasalah:

| Gejala | Penyebab dan solusi |
|---|---|
| `psql: command not found` | Pasang klien saja (`postgresql-client`, atau `brew install libpq`). Alternatif: tool GUI (DBeaver, pgAdmin) dengan host `localhost`, port `5432`. |
| *connection refused* | Container belum jalan atau port salah. Cek `docker ps`. |
| *password authentication failed* | Password lama masih berlaku pada volume yang sudah ada (lihat Latihan 1). |
| Port 5432 sudah terpakai | Ada PostgreSQL lokal. Ubah mapping, mis. `-p 5435:5432`, dan sesuaikan URI. |

Catatan keamanan: password di dalam URI tersimpan di *shell history* dan terlihat di daftar proses. Untuk selain latihan, pakai `~/.pgpass` (izin `0600`).

---

## Latihan 5: Dua versi mayor berdampingan

```bash
./latihan.sh 5
```

Skrip menjalankan `pg17` (port 5433) dan `pg18` (port 5434), masing-masing dengan volume sendiri. Port host berbeda, tetapi **di dalam container keduanya tetap 5432**, itulah sebabnya pemetaannya `5433:5432` dan `5434:5432`. Perhatikan juga lokasi mount yang berbeda: image 17 di `/var/lib/postgresql/data`, image 18 di `/var/lib/postgresql`.

**(diharapkan)** `SELECT version();` menyebut `PostgreSQL 17.x` pada pg17 dan `PostgreSQL 18.x` pada pg18. `PG_VERSION` di masing-masing data directory berisi `17` dan `18`. Data directory 18 berada di bawah `/var/lib/postgresql/18/docker`.

**Mengapa data directory tidak kompatibel antarversi mayor:**

- Setiap data directory ditandai dengan versi mayor (`PG_VERSION`) dan *catalog version number*. Server menolak start bila tidak cocok.
- Antarversi mayor, **format penyimpanan internal boleh berubah**: struktur system catalog (`pg_catalog`), format WAL, dan detail penyimpanan lainnya. Server baru tidak dijamin bisa membaca berkas versi lama begitu saja.
- Antarversi **minor** (18.5 → 18.6) format data dijaga tetap sama, sehingga cukup ganti binary dan restart.

Langkah opsional di skrip memaksa image 18 memakai data directory 17. **(diharapkan)** server gagal start dengan pesan seperti *database files are incompatible with server*. Saya tidak bisa memastikan teks persisnya, dan perilaku entrypoint image bisa berbeda antar rilis, jadi anggap langkah ini opsional.

Cara resmi pindah versi mayor (Modul 14): `pg_upgrade`, dump/restore (`pg_dump`/`pg_restore`), atau logical replication.

---

## Latihan 6: Managed PostgreSQL vs menjalankan sendiri di VM

Untuk **startup kecil**, kebanyakan kasus cenderung ke managed. Pertimbangannya:

| Pertimbangan | Managed (RDS, Cloud SQL, dll.) | Sendiri di VM |
|---|---|---|
| **Backup dan PITR** | Otomatis, restore ke titik waktu tertentu dengan beberapa klik | Harus dirancang, diuji, dan dipantau sendiri (Modul 14). Backup yang tidak pernah diuji restore-nya hanyalah harapan. |
| **High availability** | Opsi standby dan failover otomatis tersedia sebagai fitur layanan (mis. Multi-AZ) | Harus membangun replikasi, failover, dan pooling sendiri (Modul 15) |
| **Patching dan upgrade** | Patch minor dan keamanan dikelola penyedia, upgrade mayor dibantu | Tanggung jawab tim sendiri |
| **Waktu dan keahlian tim** | Hemat: tim fokus ke produk | Butuh orang yang paham operasi database |
| **Biaya** | Harga per jam lebih tinggi daripada VM biasa, tetapi tidak ada biaya orang untuk operasi | Biaya infrastruktur lebih rendah, **biaya waktu engineer lebih tinggi** |
| **Kontrol** | Akses superuser dibatasi, tanpa akses OS, parameter tertentu dikunci | Kontrol penuh, termasuk tuning dan filesystem |
| **Ekstensi** | Hanya yang diizinkan penyedia | Bebas, termasuk ekstensi buatan sendiri |
| **Lock-in dan portabilitas** | Fitur khusus penyedia bisa menyulitkan pindah | PostgreSQL standar, mudah dipindahkan |
| **Kepatuhan dan lokasi data** | Bergantung wilayah dan sertifikasi penyedia | Bisa diatur sepenuhnya |

**Kesimpulan:**

- Pilih **managed** bila tidak ada DBA, data penting, dan butuh backup serta HA tanpa membangunnya. Ini keputusan terbaik untuk kebanyakan startup awal.
- Pertimbangkan **self-managed** bila butuh ekstensi atau tuning yang tidak diizinkan, biaya managed sudah jauh melebihi biaya tim operasi pada skala besar, atau ada syarat regulasi tertentu.
- Rancang aplikasi dengan PostgreSQL standar sejak awal agar migrasi antar-opsi tetap mungkin.

---

## Lembar hasil Anda

Setelah menjalankan skrip, isi hasilnya di sini untuk dibandingkan dengan yang diharapkan.

| Langkah | Hasil Anda | Sesuai harapan? |
|---|---|---|
| `version()` / `server_version` | | |
| `data_directory` | | |
| Log "ready to accept connections" | | |
| Output NULL (6 kolom) | | |
| Start time: reload tetap, restart berubah | | |
| Latihan 1: `toko` ada setelah container dibuat ulang | | |
| Latihan 3: `pending_restart` | | |
| Latihan 4: `\conninfo` dari host | | |
| Latihan 5: `PG_VERSION` 17 vs 18 | | |
