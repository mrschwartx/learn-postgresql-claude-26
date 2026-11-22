# Modul 3: Instalasi, Setup & psql

[← Modul 2: Konsep Relasional & Object Model](02-konsep-relasional.md) · [Daftar Isi](README.md#daftar-isi) · [Modul 4: DDL: Schema, Tabel & Tipe Data →](04-ddl-tipe-data.md)

**Isi modul ini**

- [Teori](#teori)
  - [3.1 Cara Menjalankan PostgreSQL](#31-cara-menjalankan-postgresql)
  - [3.2 Instalasi dengan Docker](#32-instalasi-dengan-docker)
  - [3.3 Instalasi dengan Package Manager (Debian/Ubuntu)](#33-instalasi-dengan-package-manager-debianubuntu)
  - [3.4 Mengelola Layanan PostgreSQL](#34-mengelola-layanan-postgresql)
  - [3.5 psql — Klien Command-Line](#35-psql--klien-command-line)
  - [3.6 Struktur Data Directory](#36-struktur-data-directory)
- [Praktik](#praktik)
  - [Menjalankan PostgreSQL](#menjalankan-postgresql)
  - [Eksplorasi di psql](#eksplorasi-di-psql)
  - [Mengelola Service](#mengelola-service)
  - [Membersihkan Lingkungan](#membersihkan-lingkungan)
- [Latihan](#latihan)

---


## Teori

### 3.1 Cara Menjalankan PostgreSQL

| Cara | Cocok untuk | Catatan |
|---|---|---|
| **Docker** | Belajar, development, CI | Satu perintah, mudah dibuang — **dipakai di course ini** |
| **Package manager** (`apt`, `dnf`, Homebrew) | Server VM/bare-metal, laptop | Mengikuti repo distro atau repo resmi PGDG |
| **Installer** (EDB, Postgres.app) | Windows/macOS desktop | GUI, cocok pemula |
| **Managed cloud** (Amazon RDS/Aurora, Google Cloud SQL, Azure, Supabase, Neon) | Produksi tanpa mengurus server | Backup, HA, patch dikelola penyedia; akses superuser dibatasi |
| **Kubernetes operator** (CloudNativePG, Zalando, Crunchy) | Platform Kubernetes | Lihat [Modul 15](15-replication-ha-pooling.md) |

### 3.2 Instalasi dengan Docker

```bash
docker run --name pg-latihan \
  -e POSTGRES_PASSWORD=rahasia \
  -p 5432:5432 \
  -v pgdata:/var/lib/postgresql \
  -d postgres:18
```

| Opsi | Fungsi |
|---|---|
| `POSTGRES_PASSWORD` | **Wajib** — password untuk superuser `postgres` |
| `-p 5432:5432` | Membuka port default PostgreSQL |
| `-v pgdata:/var/lib/postgresql` | Volume agar data tidak hilang saat container dihapus |
| `postgres:18` | Image resmi versi 18 (selalu pin versi mayor!) |

> Pada image `postgres` versi **18 ke atas**, direktori data berada di dalam `/var/lib/postgresql/<versi>/docker`, sehingga volume di-mount ke `/var/lib/postgresql`. Pada versi 17 ke bawah, volume di-mount ke `/var/lib/postgresql/data`.

### 3.3 Instalasi dengan Package Manager (Debian/Ubuntu)

```bash
sudo apt update
sudo apt install -y postgresql postgresql-contrib
# atau gunakan repo resmi PGDG untuk versi terbaru:
#   https://www.postgresql.org/download/linux/ubuntu/
```

Paket Debian/Ubuntu membuat **cluster** bernama `main` secara otomatis dan menyertakan tool `pg_ctlcluster`, `pg_lsclusters`. Distro berbasis RHEL memakai `postgresql-server` dan perlu inisialisasi manual (`postgresql-setup --initdb`).

### 3.4 Mengelola Layanan PostgreSQL

| Tool | Kegunaan | Contoh |
|---|---|---|
| **`systemd`** (`systemctl`) | Cara standar di Linux modern | `sudo systemctl restart postgresql` |
| **`pg_ctl`** | Tool bawaan PostgreSQL, bekerja langsung pada data directory | `pg_ctl -D /var/lib/postgresql/18/main reload` |
| **`pg_ctlcluster`** | Wrapper Debian/Ubuntu per versi & cluster | `sudo pg_ctlcluster 18 main restart` |
| **`pg_lsclusters`** | Daftar cluster di Debian/Ubuntu | `pg_lsclusters` |

Perbedaan **`reload`** dan **`restart`**:

| Aksi | Efek | Kapan |
|---|---|---|
| `reload` | Membaca ulang konfigurasi **tanpa memutus koneksi** | Parameter yang bersifat `sighup` |
| `restart` | Menghentikan lalu menjalankan ulang server | Parameter yang butuh restart (mis. `shared_buffers`, `max_connections`) |

Modus shutdown `pg_ctl stop -m`: **smart** (tunggu semua klien keluar), **fast** (default; putuskan klien, rollback transaksi, checkpoint bersih), **immediate** (seperti crash — butuh *crash recovery* saat start berikutnya).

### 3.5 psql — Klien Command-Line

**`psql`** adalah klien interaktif resmi. Format koneksi:

```bash
psql -h localhost -p 5432 -U postgres -d postgres
# atau connection string (URI):
psql "postgresql://postgres:rahasia@localhost:5432/postgres"
```

Variabel lingkungan yang membantu: `PGHOST`, `PGPORT`, `PGUSER`, `PGDATABASE`, `PGPASSWORD` (hindari untuk produksi; gunakan berkas `~/.pgpass`).

Meta-command `psql` (diawali backslash, **bukan** SQL):

| Perintah | Fungsi |
|---|---|
| `\l` | Daftar database |
| `\c nama_db` | Pindah database |
| `\dt` / `\dt+` | Daftar tabel (+ ukuran) |
| `\d nama_tabel` | Struktur tabel (kolom, index, constraint) |
| `\dn` | Daftar schema |
| `\du` | Daftar role |
| `\df` | Daftar fungsi |
| `\x` | Toggle tampilan **expanded** (vertikal) |
| `\timing` | Tampilkan waktu eksekusi query |
| `\i berkas.sql` | Jalankan berkas SQL |
| `\copy` | Import/export CSV di sisi klien |
| `\?` / `\h CREATE TABLE` | Bantuan meta-command / bantuan sintaks SQL |
| `\q` | Keluar |

### 3.6 Struktur Data Directory

Setiap cluster punya satu **data directory** (`PGDATA`) berisi data dan konfigurasi:

| Berkas/Folder | Isi |
|---|---|
| `postgresql.conf` | Konfigurasi utama server |
| `pg_hba.conf` | Aturan autentikasi klien ([Modul 13](13-security.md)) |
| `PG_VERSION` | Versi mayor cluster |
| `base/` | Data database (satu subfolder per database) |
| `pg_wal/` | Write-Ahead Log ([Modul 7](07-transaksi-mvcc-wal.md)) |
| `global/` | Tabel katalog yang dipakai seluruh cluster |

Detail lengkap ada di [Modul 12](12-internal-konfigurasi.md).

## Praktik

### Menjalankan PostgreSQL

```bash
docker run --name pg-latihan -e POSTGRES_PASSWORD=rahasia \
  -p 5432:5432 -v pgdata:/var/lib/postgresql -d postgres:18

docker logs pg-latihan | tail -5     # pastikan "ready to accept connections"
docker exec -it pg-latihan psql -U postgres
```

### Eksplorasi di psql

```
SELECT version();
SHOW server_version;
SHOW data_directory;
SHOW port;

\l
\timing
SELECT 1 + 1 AS hasil;

-- Buktikan perilaku NULL dari Modul 2
SELECT NULL = NULL AS sama, NULL IS NULL AS is_null,
       NULL OR TRUE AS or_true, NULL AND FALSE AS and_false,
       COALESCE(NULL, NULL, 3) AS coalesce_3,
       NULL IS DISTINCT FROM NULL AS distinct_null;

CREATE DATABASE toko;
\c toko
\conninfo
```

### Mengelola Service

Latihan pengelolaan service (memakai Docker sebagai pengganti `systemctl`):

```bash
docker restart pg-latihan                         # setara 'restart'
docker exec pg-latihan psql -U postgres -c "SELECT pg_reload_conf();"   # setara 'reload'
docker exec pg-latihan psql -U postgres -c "SELECT pg_postmaster_start_time();"
```

### Membersihkan Lingkungan

Bersihkan (opsional): `docker rm -f pg-latihan && docker volume rm pgdata`.

## Latihan

1. Jalankan PostgreSQL 18 via Docker dengan volume, buat database `toko`, lalu hapus container (`docker rm -f`) dan jalankan ulang dengan volume yang sama. Apakah database `toko` masih ada? Jelaskan mengapa.
2. Gunakan `\d` dan `\dt+` untuk melihat struktur tabel setelah Anda membuat satu tabel sederhana. Apa perbedaan keluaran `\d` dan `\d+`?
3. Jelaskan perbedaan `reload` dan `restart`. Sebutkan satu parameter yang cukup di-reload dan satu yang wajib restart (petunjuk: `SELECT name, context FROM pg_settings;`).
4. Hubungkan ke database `toko` dengan **connection string URI** dari host (bukan dari dalam container) menggunakan `psql` lokal atau tool GUI, lalu gunakan `\conninfo` untuk memverifikasi.
5. Jalankan dua container PostgreSQL berbeda versi (mis. `postgres:17` di port 5433 dan `postgres:18` di port 5434). Bandingkan keluaran `SELECT version();` dan jelaskan mengapa data directory keduanya **tidak kompatibel** satu sama lain.
6. Diskusikan: untuk startup kecil, kapan Anda memilih **managed PostgreSQL** (RDS/Cloud SQL) dibanding menjalankan sendiri di VM? Sebutkan minimal tiga pertimbangan (backup, HA, biaya, kontrol, ekstensi).

---

[← Modul 2: Konsep Relasional & Object Model](02-konsep-relasional.md) · [Daftar Isi](README.md#daftar-isi) · [Modul 4: DDL: Schema, Tabel & Tipe Data →](04-ddl-tipe-data.md)
