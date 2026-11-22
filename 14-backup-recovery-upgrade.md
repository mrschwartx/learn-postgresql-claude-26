# Modul 14: Backup, Recovery & Upgrade

[← Modul 13: Security](13-security.md) · [Daftar Isi](README.md#daftar-isi) · [Modul 15: Replication, High Availability & Connection Pooling →](15-replication-ha-pooling.md)

**Isi modul ini**

- [Teori](#teori)
  - [14.1 Dua Keluarga Backup](#141-dua-keluarga-backup)
  - [14.2 Logical Backup: `pg_dump`, `pg_dumpall`, `pg_restore`](#142-logical-backup-pg_dump-pg_dumpall-pg_restore)
  - [14.3 Physical Backup: `pg_basebackup`](#143-physical-backup-pg_basebackup)
  - [14.4 Continuous Archiving dan PITR](#144-continuous-archiving-dan-pitr)
  - [14.5 Alat Backup Profesional](#145-alat-backup-profesional)
  - [14.6 Strategi: RPO, RTO, dan Validasi](#146-strategi-rpo-rto-dan-validasi)
  - [14.7 Upgrade Versi](#147-upgrade-versi)
  - [14.8 Anonymization](#148-anonymization)
- [Praktik](#praktik)
  - [Logical Backup dan Restore](#logical-backup-dan-restore)
  - [Simulasi Bencana dan Pemulihan Satu Tabel](#simulasi-bencana-dan-pemulihan-satu-tabel)
  - [Physical Backup dengan pg_basebackup](#physical-backup-dengan-pg_basebackup)
  - [Arsip WAL (Dasar PITR)](#arsip-wal-dasar-pitr)
- [Latihan](#latihan)

---


## Teori

### 14.1 Dua Keluarga Backup

| Aspek | **Logical backup** | **Physical backup** |
|---|---|---|
| Isi | Perintah SQL / data per objek | Salinan **file** data directory |
| Alat | `pg_dump`, `pg_dumpall` | `pg_basebackup`, pgBackRest, Barman, WAL-G, pg_probackup |
| Pemulihan | `psql` / `pg_restore` | Salin file + replay WAL |
| Granularitas | Per database/tabel/schema | Seluruh cluster |
| Lintas versi mayor | **Bisa** | **Tidak** (versi harus sama) |
| Kecepatan untuk DB besar | Lambat | **Cepat** |
| **Point-in-Time Recovery** | Tidak | **Ya** (dengan arsip WAL) |

Jangan hanya menyalin folder data saat server hidup — hasilnya tidak konsisten. Gunakan alat yang tepat.

### 14.2 Logical Backup: `pg_dump`, `pg_dumpall`, `pg_restore`

| Alat | Fungsi |
|---|---|
| `pg_dump` | Backup **satu database** (konsisten via snapshot MVCC, tidak memblokir tulis) |
| `pg_dumpall` | Seluruh cluster — terutama untuk **role & tablespace** (`--globals-only`) |
| `pg_restore` | Memulihkan arsip format custom/directory/tar |

| Format `-F` | Ekstensi | Karakteristik |
|---|---|---|
| `p` (plain) | `.sql` | Teks SQL; pulihkan dengan `psql` |
| **`c`** (custom) | `.dump` | Terkompresi, dapat dipulihkan selektif & paralel |
| **`d`** (directory) | folder | Mendukung dump **paralel** (`-j`) |
| `t` (tar) | `.tar` | Jarang dipakai |

```bash
pg_dump -h localhost -U postgres -Fc -f toko.dump toko                  # custom format
pg_dump -Fd -j 4 -f toko_dir toko                                       # directory, paralel
pg_dump -U postgres -t app.produk --data-only toko > produk_data.sql    # satu tabel
pg_dumpall -U postgres --globals-only > globals.sql                      # role & tablespace

createdb -U postgres toko_pulih
pg_restore -U postgres -d toko_pulih -j 4 --no-owner toko.dump
pg_restore -l toko.dump                                                  # daftar isi arsip
```

### 14.3 Physical Backup: `pg_basebackup`

`pg_basebackup` menyalin seluruh cluster secara konsisten via protokol replikasi (butuh role dengan atribut `REPLICATION` dan entri di `pg_hba.conf`):

```bash
pg_basebackup -h primary -U replicator -D /backup/base -Ft -z -P -X stream
```

| Opsi | Fungsi |
|---|---|
| `-D` | Direktori tujuan |
| `-Ft -z` | Format tar terkompresi |
| `-X stream` | Sertakan WAL yang dibuat selama backup |
| `-P` | Progres |
| `-R` | Siapkan konfigurasi standby (untuk membangun replica) |

### 14.4 Continuous Archiving dan PITR

**Point-in-Time Recovery (PITR)** memulihkan database ke **waktu tertentu** (mis. 1 menit sebelum `DROP TABLE` yang tidak sengaja). Komponennya:

```
 Base backup (Minggu)  +  Arsip WAL kontinu (Senin ... Kamis)  ─►  pulihkan ke Kamis 14:05:00
```

Konfigurasi arsip WAL pada server:

```
wal_level = replica
archive_mode = on
archive_command = 'test ! -f /arsip/%f && cp %p /arsip/%f'
```

Pemulihan: siapkan base backup di data directory baru, lalu atur:

```
restore_command = 'cp /arsip/%f %p'
recovery_target_time = '2026-11-20 14:05:00+07'
recovery_target_action = 'promote'
```

Buat file `recovery.signal` di data directory dan start server; PostgreSQL me-*replay* WAL hingga target.

### 14.5 Alat Backup Profesional

| Alat | Karakteristik |
|---|---|
| **pgBackRest** | Full/diferensial/inkremental, paralel, kompresi, enkripsi, repositori S3/GCS/Azure, verifikasi — sangat populer |
| **Barman** | Manajemen backup & pemulihan terpusat dari server terpisah |
| **WAL-G** | Backup & arsip WAL cloud-native (S3, dll.), cepat |
| **pg_probackup** | Backup inkremental & validasi |

Pada **managed cloud** (RDS, Cloud SQL, dll.), backup otomatis & PITR disediakan, tetapi Anda tetap perlu memahami retensi, uji pemulihan, dan *snapshot* lintas region.

### 14.6 Strategi: RPO, RTO, dan Validasi

| Istilah | Arti |
|---|---|
| **RPO** (Recovery Point Objective) | Berapa banyak data boleh hilang (mis. 5 menit) → menentukan frekuensi arsip WAL/replikasi |
| **RTO** (Recovery Time Objective) | Berapa lama pemulihan boleh memakan waktu → menentukan metode & ukuran backup |

**Aturan 3-2-1**: 3 salinan data, di 2 jenis media berbeda, 1 di luar lokasi (offsite).

> **Backup yang belum pernah diuji pemulihannya = belum punya backup.** Jadwalkan *backup validation*: pulihkan berkala ke lingkungan uji, jalankan `pg_checksums`/`amcheck`, lalu verifikasi jumlah baris dan query kunci.

### 14.7 Upgrade Versi

| Jenis | Metode | Downtime |
|---|---|---|
| **Minor** (18.5→18.6) | Ganti binary, restart | Detik–menit |
| **Mayor** — `pg_dump`/`pg_restore` | Dump dari versi lama, restore ke baru | Sebanding ukuran data (lama) |
| **Mayor** — **`pg_upgrade`** | Mengonversi cluster lama ke versi baru; mode `--link` memakai hard link (sangat cepat) | Menit |
| **Mayor** — **Logical replication** | Replikasi ke cluster versi baru, lalu *cutover* | **Hampir nol** |

Langkah `pg_upgrade` secara umum: instal binary versi baru → `initdb` cluster baru → `pg_upgrade --check` → hentikan server lama → `pg_upgrade` (`--link` opsional) → start cluster baru → `ANALYZE` (pada versi lama statistik tidak ikut dibawa; mulai PG 18 `pg_upgrade` mempertahankan statistik planner) → uji aplikasi. Selalu **backup** sebelum upgrade dan baca *release notes* untuk perubahan yang tidak kompatibel.

```bash
pg_upgrade --check \
  -b /usr/lib/postgresql/17/bin -B /usr/lib/postgresql/18/bin \
  -d /var/lib/postgresql/17/main -D /var/lib/postgresql/18/main
```

### 14.8 Anonymization

Untuk menyalin data produksi ke staging/dev tanpa membocorkan data pribadi, gunakan **PostgreSQL Anonymizer** (ekstensi `anon`): *masking* dinamis, anonimisasi statis, dan dump teranonimkan.

```sql
SECURITY LABEL FOR anon ON COLUMN app.pelanggan.email
    IS 'MASKED WITH FUNCTION anon.partial_email(email)';
SECURITY LABEL FOR anon ON COLUMN app.pelanggan.nama
    IS 'MASKED WITH FUNCTION anon.fake_last_name()';
```

Alternatif: skrip SQL anonimisasi pada salinan staging sebelum diberikan ke developer.

## Praktik

```bash
docker exec -it pg-latihan psql -U postgres -d toko
```

### Logical Backup dan Restore

Logical backup & restore (jalankan di host; `docker exec` menjalankan `pg_dump` di dalam container):

```bash
docker exec pg-latihan pg_dump -U postgres -Fc toko > toko.dump
docker exec pg-latihan pg_dumpall -U postgres --globals-only > globals.sql
ls -lh toko.dump globals.sql

docker exec pg-latihan createdb -U postgres toko_pulih
docker exec -i pg-latihan pg_restore -U postgres -d toko_pulih --no-owner < toko.dump
docker exec pg-latihan psql -U postgres -d toko_pulih -c "SELECT count(*) FROM app.produk;"
```

### Simulasi Bencana dan Pemulihan Satu Tabel

```bash
docker exec pg-latihan psql -U postgres -d toko -c "DROP TABLE app.item_pesanan CASCADE;"
docker exec -i pg-latihan pg_restore -U postgres -d toko -t item_pesanan -n app --no-owner < toko.dump
docker exec pg-latihan psql -U postgres -d toko -c "SELECT count(*) FROM app.item_pesanan;"
```

### Physical Backup dengan pg_basebackup

```bash
docker exec pg-latihan bash -c 'echo "host replication all 127.0.0.1/32 trust" >> $PGDATA/pg_hba.conf'
docker exec pg-latihan psql -U postgres -c "SELECT pg_reload_conf();"
docker exec pg-latihan pg_basebackup -h 127.0.0.1 -U postgres -D /tmp/base -Ft -z -X stream -P
docker exec pg-latihan ls -lh /tmp/base
```

> Aturan `trust` di atas **hanya** untuk latihan lokal dalam container sekali pakai — jangan ditiru di lingkungan nyata.

### Arsip WAL (Dasar PITR)

```sql
ALTER SYSTEM SET archive_mode = on;                                     -- butuh restart
ALTER SYSTEM SET archive_command = 'test ! -f /tmp/arsip/%f && cp %p /tmp/arsip/%f';
```

```bash
docker exec pg-latihan mkdir -p /tmp/arsip
docker exec -u root pg-latihan chown postgres /tmp/arsip
docker restart pg-latihan
docker exec pg-latihan psql -U postgres -c "SELECT pg_switch_wal();"
docker exec pg-latihan ls /tmp/arsip | head
docker exec pg-latihan psql -U postgres -c "SELECT * FROM pg_stat_archiver;"
```

## Latihan

1. Buat backup `pg_dump -Fc` database `toko`, hapus satu tabel, dan pulihkan **hanya tabel itu** dengan `pg_restore -t`. Catat langkah dan waktunya.
2. Bandingkan ukuran dan waktu backup format `p` (plain), `c` (custom), dan `d` dengan `-j 4` pada tabel `transaksi` (1 juta baris).
3. Jelaskan perbedaan `pg_dump` dan `pg_dumpall`. Mengapa `pg_dump` saja tidak cukup untuk memulihkan seluruh server (petunjuk: role dan tablespace)?
4. Rancang strategi backup untuk sistem dengan **RPO 5 menit** dan **RTO 30 menit**: alat, frekuensi full/inkremental, arsip WAL, lokasi penyimpanan, dan jadwal uji pemulihan.
5. Jelaskan langkah-langkah PITR untuk kasus "seseorang menjalankan `DELETE` tanpa `WHERE` pukul 14:05". Parameter apa yang harus diatur di sisi pemulihan?
6. Bandingkan tiga strategi upgrade mayor (`pg_dump/restore`, `pg_upgrade --link`, logical replication) dari sisi downtime, risiko, dan kompleksitas. Pilih satu untuk database 2 TB yang harus online 24/7 dan jelaskan alasannya.

---

[← Modul 13: Security](13-security.md) · [Daftar Isi](README.md#daftar-isi) · [Modul 15: Replication, High Availability & Connection Pooling →](15-replication-ha-pooling.md)
