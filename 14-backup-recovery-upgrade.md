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
  - [Validasi Backup dengan pg_verifybackup](#validasi-backup-dengan-pg_verifybackup)
  - [pgBackRest (Opsional)](#pgbackrest-opsional)
  - [Anonymization dengan PostgreSQL Anonymizer (Opsional)](#anonymization-dengan-postgresql-anonymizer-opsional)
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

**Contoh singkat tiap alat**

*pgBackRest* (`/etc/pgbackrest/pgbackrest.conf`):

```ini
[global]
repo1-path=/var/lib/pgbackrest
repo1-retention-full=2
start-fast=y

[toko]
pg1-path=/var/lib/postgresql/18/main
```

```bash
pgbackrest --stanza=toko stanza-create
pgbackrest --stanza=toko --type=full backup          # juga: --type=diff, --type=incr
pgbackrest --stanza=toko restore --type=time --target="2026-11-23 14:04:00+07"
```

Di `postgresql.conf`: `archive_mode = on` dan `archive_command = 'pgbackrest --stanza=toko archive-push %p'`.

*Barman* (dijalankan di server backup terpisah, `/etc/barman.d/pg-toko.conf`):

```ini
[pg-toko]
description = "Server toko"
conninfo = host=db1 user=barman dbname=postgres
streaming_conninfo = host=db1 user=streaming_barman
backup_method = postgres
streaming_archiver = on
slot_name = barman
create_slot = auto
retention_policy = RECOVERY WINDOW OF 7 DAYS
```

```bash
barman check pg-toko
barman backup pg-toko
barman list-backups pg-toko
barman recover pg-toko latest /var/lib/postgresql/pulih
```

*WAL-G* (konfigurasi lewat variabel lingkungan; contoh repositori lokal):

```bash
export WALG_FILE_PREFIX=/var/lib/walg          # untuk S3: WALG_S3_PREFIX=s3://bucket/jalur
# postgresql.conf:
#   archive_command = 'wal-g wal-push %p'
#   restore_command = 'wal-g wal-fetch %f %p'
wal-g backup-push "$PGDATA"
wal-g backup-list
wal-g backup-fetch /var/lib/postgresql/pulih LATEST
wal-g delete retain FULL 3 --confirm
```

*pg_probackup*:

```bash
pg_probackup init -B /backup
pg_probackup add-instance -B /backup -D "$PGDATA" --instance main
pg_probackup backup -B /backup --instance main -b FULL --stream -U backup
pg_probackup backup -B /backup --instance main -b DELTA --stream -U backup
pg_probackup validate -B /backup --instance main
pg_probackup restore -B /backup --instance main -D /var/lib/postgresql/pulih
```

Pada **managed cloud** (RDS, Cloud SQL, dll.), backup otomatis & PITR disediakan, tetapi Anda tetap perlu memahami retensi, uji pemulihan, dan *snapshot* lintas region.

### 14.6 Strategi: RPO, RTO, dan Validasi

| Istilah | Arti |
|---|---|
| **RPO** (Recovery Point Objective) | Berapa banyak data boleh hilang (mis. 5 menit) → menentukan frekuensi arsip WAL/replikasi |
| **RTO** (Recovery Time Objective) | Berapa lama pemulihan boleh memakan waktu → menentukan metode & ukuran backup |

**Aturan 3-2-1**: 3 salinan data, di 2 jenis media berbeda, 1 di luar lokasi (offsite).

**Alat validasi backup**

| Alat | Yang diperiksa |
|---|---|
| `pg_verifybackup` | Backup `pg_basebackup` terhadap *backup manifest*: file hilang, ukuran, checksum, dan WAL yang dibutuhkan |
| `pgbackrest verify` / `pgbackrest check` | Integritas file di repositori dan konfigurasi arsip WAL |
| `barman check` / `barman verify-backup` | Kondisi server, arsip, dan backup (alat Barman terbaru memakai `pg_verifybackup`) |
| `pg_probackup validate` | Checksum file backup dan ketersediaan WAL |
| `pg_checksums` / `amcheck` | Halaman rusak dan konsistensi struktur index pada cluster hasil pemulihan |
| **Restore test berkala** | Satu-satunya bukti nyata bahwa backup bisa dipakai |

> **Backup yang belum pernah diuji pemulihannya = belum punya backup.** Jadwalkan *backup validation*: pulihkan berkala ke lingkungan uji, jalankan `pg_checksums`/`amcheck`, lalu verifikasi jumlah baris dan query kunci.

### 14.7 Upgrade Versi

| Jenis | Metode | Downtime |
|---|---|---|
| **Minor** (18.5→18.6) | Ganti binary, restart | Detik–menit |
| **Mayor** — `pg_dump`/`pg_restore` | Dump dari versi lama, restore ke baru | Sebanding ukuran data (lama) |
| **Mayor** — **`pg_upgrade`** | Mengonversi cluster lama ke versi baru; mode `--link` memakai hard link (sangat cepat) | Menit |
| **Mayor** — **Logical replication** | Replikasi ke cluster versi baru, lalu *cutover* | **Hampir nol** |

**Upgrade mayor dengan logical replication** (downtime hampir nol):

1. Bangun cluster baru versi tujuan (`initdb`), pasang ekstensi yang sama.
2. Salin skema saja: `pg_dump --schema-only` dari lama, restore ke baru (DDL tidak ikut replikasi).
3. Di cluster lama: `wal_level = logical`, lalu `CREATE PUBLICATION pub_upgrade FOR ALL TABLES;`.
4. Di cluster baru: `CREATE SUBSCRIPTION sub_upgrade CONNECTION '...' PUBLICATION pub_upgrade;` dan tunggu sinkronisasi awal selesai.
5. Pantau *lag* sampai nyaris nol. Sinkronkan nilai *sequence* secara manual (sequence tidak direplikasi) dan jalankan `ANALYZE`.
6. **Cutover**: hentikan tulis ke cluster lama, tunggu lag nol, sinkronkan sequence, arahkan aplikasi ke cluster baru, lalu `DROP SUBSCRIPTION`.
7. Simpan cluster lama sebagai jalur mundur sebelum dihapus.

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

Tiga mode kerja PostgreSQL Anonymizer:

| Mode | Cara kerja | Cocok untuk |
|---|---|---|
| **Dynamic masking** | Role tertentu (`SECURITY LABEL FOR anon ON ROLE analis IS 'MASKED'`) melihat data tersamarkan, sedangkan data asli tidak berubah | Analis atau BI yang membaca langsung dari produksi |
| **Static masking** | `SELECT anon.anonymize_database();` menimpa data secara permanen | Salinan staging/dev |
| **Anonymous dump** | Dump yang sudah teranonimkan | Menyerahkan data ke pihak luar |

Fungsi penyamaran yang umum: `anon.fake_*()` (data palsu), `anon.partial()` / `anon.partial_email()` (menyisakan sebagian), `anon.random_*()`, dan `MASKED WITH VALUE '...'` (nilai tetap). Syarat penting: tentukan **semua** kolom sensitif (nama, email, telepon, alamat, nomor identitas), karena kolom yang tidak diberi label tidak disamarkan.

Alternatif tanpa ekstensi: skrip SQL anonimisasi pada salinan staging sebelum diberikan ke developer.

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

### Validasi Backup dengan pg_verifybackup

Gunakan aturan replikasi `trust` dari latihan `pg_basebackup` di atas. Format `plain` diperlukan agar `pg_verifybackup` bisa memeriksa file satu per satu:

```bash
docker exec pg-latihan pg_basebackup -h 127.0.0.1 -U postgres -D /tmp/base_plain -Fp -X stream
docker exec pg-latihan pg_verifybackup /tmp/base_plain          # berhasil

# Simulasikan kerusakan
docker exec pg-latihan bash -c 'echo x >> /tmp/base_plain/PG_VERSION'
docker exec pg-latihan pg_verifybackup /tmp/base_plain          # gagal: ukuran file berbeda dari manifest
```

### pgBackRest (Opsional)

pgBackRest harus dijalankan sebagai user `postgres`, bukan `root`. Paket dipasang ke container latihan:

```bash
docker exec -u root pg-latihan bash -c 'apt-get update -qq && apt-get install -y -qq pgbackrest'
docker exec -u root pg-latihan bash -c 'mkdir -p /etc/pgbackrest /var/lib/pgbackrest /var/log/pgbackrest && chown postgres:postgres /var/lib/pgbackrest /var/log/pgbackrest'

docker exec -u root pg-latihan bash -c 'cat > /etc/pgbackrest/pgbackrest.conf <<EOF
[global]
repo1-path=/var/lib/pgbackrest
repo1-retention-full=2
start-fast=y
log-level-console=info

[toko]
pg1-path=$PGDATA
EOF'

# Arahkan arsip WAL ke pgBackRest (menggantikan archive_command latihan sebelumnya)
docker exec pg-latihan psql -U postgres -c "ALTER SYSTEM SET archive_mode = on;"
docker exec pg-latihan psql -U postgres -c "ALTER SYSTEM SET archive_command = 'pgbackrest --stanza=toko archive-push %p';"
docker restart pg-latihan

docker exec -u postgres pg-latihan pgbackrest --stanza=toko stanza-create
docker exec -u postgres pg-latihan pgbackrest --stanza=toko check
docker exec -u postgres pg-latihan pgbackrest --stanza=toko --type=full backup

# Ubah data, lalu backup inkremental
docker exec pg-latihan psql -U postgres -d toko -c "CREATE TABLE IF NOT EXISTS uji_backup AS SELECT generate_series(1,100000) AS n;"
docker exec -u postgres pg-latihan pgbackrest --stanza=toko --type=incr backup
docker exec -u postgres pg-latihan pgbackrest info
```

Pulihkan ke direktori lain (tidak menyentuh cluster yang sedang berjalan), lalu jalankan sebagai instance kedua:

```bash
docker exec -u postgres pg-latihan bash -c 'mkdir -p /tmp/pulih && chmod 700 /tmp/pulih'
docker exec -u postgres pg-latihan pgbackrest --stanza=toko --pg1-path=/tmp/pulih restore
docker exec -u postgres pg-latihan pg_ctl -D /tmp/pulih -o "-p 5433 -c archive_mode=off" -w start
docker exec pg-latihan psql -U postgres -p 5433 -d toko -c "SELECT count(*) FROM uji_backup;"
docker exec -u postgres pg-latihan pg_ctl -D /tmp/pulih stop
docker exec -u postgres pg-latihan pgbackrest --stanza=toko verify
```

`archive_mode=off` pada instance hasil restore mencegahnya mengarsipkan WAL ke repositori yang sama dengan server asli.

### Anonymization dengan PostgreSQL Anonymizer (Opsional)

Image `postgres` resmi tidak menyertakan ekstensi `anon`; gunakan image dari proyeknya:

```bash
docker run -d --name pg-anon -e POSTGRES_PASSWORD=rahasia -p 5440:5432 \
  registry.gitlab.com/dalibo/postgresql_anonymizer:stable
docker exec -it pg-anon psql -U postgres
```

```sql
CREATE EXTENSION anon;      -- versi 1.x: CREATE EXTENSION anon CASCADE; SELECT anon.init();

CREATE TABLE pelanggan (id serial PRIMARY KEY, nama text, email text, telepon text);
INSERT INTO pelanggan (nama, email, telepon) VALUES
  ('Budi Santoso', 'budi@contoh.com', '081234567890'),
  ('Sari Wulandari', 'sari@contoh.com', '085711112222');

SECURITY LABEL FOR anon ON COLUMN pelanggan.nama    IS 'MASKED WITH FUNCTION anon.fake_last_name()';
SECURITY LABEL FOR anon ON COLUMN pelanggan.email   IS 'MASKED WITH FUNCTION anon.partial_email(email)';
SECURITY LABEL FOR anon ON COLUMN pelanggan.telepon IS 'MASKED WITH VALUE ''08xxxxxxxxxx''';

-- Static masking: data ditimpa permanen (jalankan HANYA pada salinan)
SELECT anon.anonymize_database();
SELECT * FROM pelanggan;
```

Dynamic masking (`SECURITY LABEL FOR anon ON ROLE analis IS 'MASKED'`) memerlukan pengaturan tambahan yang bergantung versi, termasuk `shared_preload_libraries`; ikuti dokumentasi versi Anda.

## Latihan

1. Buat backup `pg_dump -Fc` database `toko`, hapus satu tabel, dan pulihkan **hanya tabel itu** dengan `pg_restore -t`. Catat langkah dan waktunya.
2. Bandingkan ukuran dan waktu backup format `p` (plain), `c` (custom), dan `d` dengan `-j 4` pada tabel `transaksi` (1 juta baris).
3. Jelaskan perbedaan `pg_dump` dan `pg_dumpall`. Mengapa `pg_dump` saja tidak cukup untuk memulihkan seluruh server (petunjuk: role dan tablespace)?
4. Rancang strategi backup untuk sistem dengan **RPO 5 menit** dan **RTO 30 menit**: alat, frekuensi full/inkremental, arsip WAL, lokasi penyimpanan, dan jadwal uji pemulihan.
5. Jelaskan langkah-langkah PITR untuk kasus "seseorang menjalankan `DELETE` tanpa `WHERE` pukul 14:05". Parameter apa yang harus diatur di sisi pemulihan?
6. Bandingkan tiga strategi upgrade mayor (`pg_dump/restore`, `pg_upgrade --link`, logical replication) dari sisi downtime, risiko, dan kompleksitas. Pilih satu untuk database 2 TB yang harus online 24/7 dan jelaskan alasannya.
7. Pasang pgBackRest, buat backup full dan inkremental, lalu lakukan PITR ke satu menit sebelum Anda menjalankan `DELETE` tanpa `WHERE`. Catat opsi `--type=time --target=...` yang dipakai.
8. Jalankan `pg_verifybackup` pada backup yang sengaja Anda rusak. Susun prosedur *backup validation* mingguan: alat apa saja, di mana dijalankan, dan bagaimana hasilnya dilaporkan.
9. Bandingkan pgBackRest, Barman, WAL-G, dan pg_probackup dari sisi arsitektur (agen atau server terpisah), dukungan cloud storage, dan kemudahan restore. Alat mana yang Anda pilih untuk tim kecil di cloud?
10. Gunakan PostgreSQL Anonymizer untuk membuat salinan staging dari tabel pelanggan. Bagaimana Anda memastikan tidak ada kolom sensitif yang terlewat?

---

[← Modul 13: Security](13-security.md) · [Daftar Isi](README.md#daftar-isi) · [Modul 15: Replication, High Availability & Connection Pooling →](15-replication-ha-pooling.md)
