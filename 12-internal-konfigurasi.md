# Modul 12: Arsitektur Internal & Konfigurasi

[← Modul 11: Desain Schema & Pola Aplikasi](11-desain-schema-pola.md) · [Daftar Isi](README.md#daftar-isi) · [Modul 13: Security →](13-security.md)

**Isi modul ini**

- [Teori](#teori)
  - [12.1 Arsitektur Proses PostgreSQL](#121-arsitektur-proses-postgresql)
  - [12.2 Arsitektur Memori](#122-arsitektur-memori)
  - [12.3 Penyimpanan Fisik dan Layout File](#123-penyimpanan-fisik-dan-layout-file)
  - [12.4 VACUUM dan Autovacuum](#124-vacuum-dan-autovacuum)
  - [12.5 Konfigurasi: `postgresql.conf` dan Cara Mengubahnya](#125-konfigurasi-postgresqlconf-dan-cara-mengubahnya)
  - [12.6 Parameter Penting](#126-parameter-penting)
  - [12.7 Reporting, Logging dan Statistik](#127-reporting-logging-dan-statistik)
  - [12.8 Ekstensi](#128-ekstensi)
  - [12.9 System Catalog](#129-system-catalog)
- [Praktik](#praktik)
  - [Proses dan Memori](#proses-dan-memori)
  - [Layout File dan Ukuran](#layout-file-dan-ukuran)
  - [Bloat dan Vacuum](#bloat-dan-vacuum)
  - [Konfigurasi](#konfigurasi)
  - [System Catalog](#system-catalog)
- [Latihan](#latihan)

---


## Teori

### 12.1 Arsitektur Proses PostgreSQL

PostgreSQL memakai model **proses per koneksi** (bukan thread):

```
                         ┌───────────────────────────┐
 klien ──koneksi──►      │  postmaster (proses induk) │
                         └─────────────┬─────────────┘
              fork per koneksi         │  proses latar belakang
        ┌───────────┬──────────┐       ├─► checkpointer
        ▼           ▼          ▼       ├─► background writer
    backend      backend    backend    ├─► WAL writer
    (sesi 1)     (sesi 2)   (sesi N)   ├─► autovacuum launcher ─► autovacuum workers
        │           │          │       ├─► io workers (PG 18+)
        └───────────┴────┬─────┘       └─► WAL sender / receiver (replikasi)
                         ▼
             ┌─────────────────────────┐
             │  Shared Memory          │
             │  shared_buffers · WAL buffers · lock tables · proc array
             └─────────────────────────┘
```

| Proses | Fungsi |
|---|---|
| **postmaster** | Menerima koneksi, mem-*fork* backend, mengawasi proses lain |
| **backend** | Melayani satu sesi klien |
| **checkpointer** | Menulis semua dirty page ke disk pada checkpoint |
| **background writer** | Menulis dirty page secara bertahap agar backend tidak harus menulis |
| **WAL writer** | Mem-flush WAL buffer ke disk |
| **autovacuum launcher/worker** | Menjalankan VACUUM dan ANALYZE otomatis |
| **WAL sender/receiver** | Mengirim/menerima WAL untuk replikasi |

Karena setiap koneksi adalah **proses OS**, ratusan koneksi aktif terasa berat — inilah alasan **connection pooling** (PgBouncer, [Modul 15](15-replication-ha-pooling.md)) penting.

### 12.2 Arsitektur Memori

| Memori | Parameter | Penjelasan |
|---|---|---|
| **Shared** — buffer pool | `shared_buffers` | Cache halaman tabel/index bersama (titik awal umum: ~25% RAM) |
| **Shared** — WAL buffer | `wal_buffers` | Buffer sementara sebelum WAL ditulis |
| **Per-operasi** | `work_mem` | Sort/hash per node per koneksi — **bisa berlipat ganda** |
| **Per-sesi** | `temp_buffers` | Tabel sementara |
| **Perawatan** | `maintenance_work_mem` | `VACUUM`, `CREATE INDEX` |
| **OS page cache** | (tidak diatur PG) | PostgreSQL mengandalkan cache OS di samping `shared_buffers`; `effective_cache_size` hanya memberi tahu planner |

**Buffer management**: halaman 8 KB dimuat ke `shared_buffers` dengan algoritma *clock-sweep*; halaman yang dimodifikasi disebut *dirty* dan ditulis oleh background writer/checkpointer. Ekstensi `pg_buffercache` memperlihatkan isi buffer.

### 12.3 Penyimpanan Fisik dan Layout File

| Konsep | Penjelasan |
|---|---|
| **Data directory** (`PGDATA`) | Direktori utama cluster |
| `base/<oid_db>/<filenode>` | File per tabel/index; dipecah segmen 1 GB |
| **Page (halaman)** | Unit penyimpanan 8 KB; berisi header, *line pointer*, dan tuple |
| **Tuple** | Satu versi baris (header `xmin`, `xmax`, `ctid`) |
| **TOAST** | Nilai besar (> ~2 KB) dikompresi/dipisah ke tabel TOAST |
| **Free Space Map** (`_fsm`) & **Visibility Map** (`_vm`) | Melacak ruang kosong dan halaman "all-visible" (untuk index-only scan dan vacuum) |
| **Tablespace** | Lokasi penyimpanan alternatif di disk lain |

```sql
SELECT pg_relation_filepath('produk');                   -- lokasi file tabel
SELECT pg_size_pretty(pg_relation_size('produk')) AS tabel,
       pg_size_pretty(pg_total_relation_size('produk')) AS total_dengan_index_toast;
```

### 12.4 VACUUM dan Autovacuum

Karena MVCC ([Modul 7](07-transaksi-mvcc-wal.md)), `UPDATE`/`DELETE` meninggalkan **dead tuple**. **VACUUM**:

- menandai ruang dead tuple agar dipakai ulang,
- memperbarui *visibility map* dan *free space map*,
- membekukan (*freeze*) ID transaksi tua untuk mencegah **transaction ID wraparound**.

| Perintah | Efek |
|---|---|
| `VACUUM tabel` | Membersihkan dead tuple; **tidak mengecilkan file**; tidak memblokir baca/tulis |
| `VACUUM (ANALYZE)` | Plus perbarui statistik |
| `VACUUM FULL tabel` | Menulis ulang tabel (mengecilkan file) — **`ACCESS EXCLUSIVE` lock**, hindari di produksi; alternatif `pg_repack` |
| `ANALYZE tabel` | Perbarui statistik planner |

**Autovacuum** berjalan otomatis ketika dead tuple melebihi: `autovacuum_vacuum_threshold + autovacuum_vacuum_scale_factor × jumlah_baris` (default 50 + 20%). Untuk tabel besar, 20% terlalu longgar — turunkan per tabel:

```sql
ALTER TABLE transaksi SET (autovacuum_vacuum_scale_factor = 0.02, autovacuum_analyze_scale_factor = 0.01);
```

Penyebab vacuum tidak efektif: **transaksi panjang** / `idle in transaction`, slot replikasi tertinggal, prepared transaction yang terlupakan — semuanya menahan *xmin horizon*.

### 12.5 Konfigurasi: `postgresql.conf` dan Cara Mengubahnya

| Cara | Cakupan | Contoh |
|---|---|---|
| Edit `postgresql.conf` | Seluruh server | `shared_buffers = 4GB` |
| `ALTER SYSTEM SET ...` | Seluruh server (tersimpan di `postgresql.auto.conf`) | `ALTER SYSTEM SET work_mem = '32MB';` |
| `ALTER DATABASE db SET ...` | Per database | |
| `ALTER ROLE r SET ...` | Per pengguna (**per-user, per-database setting**) | `ALTER ROLE laporan SET statement_timeout = '5min';` |
| `SET ...` / `SET LOCAL ...` | Sesi / transaksi | `SET work_mem = '256MB';` |
| `include_dir` | Pecah konfigurasi ke banyak file | `conf.d/*.conf` |

Cek asal dan konteks parameter: `SELECT name, setting, unit, context, source FROM pg_settings WHERE name = 'work_mem';`. Kolom `context`: `postmaster` (butuh restart), `sighup` (cukup reload), `user`/`superuser` (bisa per sesi).

### 12.6 Parameter Penting

| Kelompok | Parameter | Catatan |
|---|---|---|
| **Koneksi** | `max_connections`, `listen_addresses`, `port` | Jaga `max_connections` tetap wajar; pakai pooler |
| **Memori** | `shared_buffers`, `work_mem`, `maintenance_work_mem`, `effective_cache_size` | Lihat 12.2 |
| **WAL** | `wal_level`, `max_wal_size`, `min_wal_size`, `wal_compression`, `synchronous_commit`, `fsync` | **Jangan** matikan `fsync` di produksi |
| **Checkpoint** | `checkpoint_timeout`, `checkpoint_completion_target`, `max_wal_size` | Checkpoint terlalu sering → I/O lonjakan; terlalu jarang → recovery lebih lama |
| **Vacuum** | `autovacuum_*`, `vacuum_cost_*` | Tuning per tabel |
| **Planner** | `random_page_cost`, `default_statistics_target`, `jit` | Lihat [Modul 10](10-query-planner-explain.md) |
| **Replikasi** | `max_wal_senders`, `max_replication_slots`, `hot_standby` | [Modul 15](15-replication-ha-pooling.md) |
| **Logging** | `log_min_duration_statement`, `log_line_prefix`, `log_checkpoints`, `log_lock_waits`, `log_temp_files`, `log_autovacuum_min_duration` | Fondasi observability |
| **Timeout** | `statement_timeout`, `lock_timeout`, `idle_in_transaction_session_timeout` | Lindungi server dari sesi nakal |
| **I/O (PG 18+)** | `io_method` (`worker`/`io_uring`/`sync`) | I/O asinkron untuk beberapa jenis scan |

### 12.7 Reporting, Logging dan Statistik

| Sumber | Isi |
|---|---|
| **Log server** | Query lambat, error, checkpoint, lock wait, autovacuum |
| **Cumulative statistics** (`pg_stat_*`) | Aktivitas sesi, tabel, index, bgwriter, WAL, replikasi |
| **`pg_stat_statements`** | Statistik per-query ternormalisasi |

Contoh logging yang direkomendasikan:

```
log_min_duration_statement = 500ms
log_checkpoints = on
log_lock_waits = on
log_temp_files = 0
log_autovacuum_min_duration = 0
log_line_prefix = '%m [%p] %q%u@%d '
```

### 12.8 Ekstensi

| Ekstensi | Fungsi |
|---|---|
| `pg_stat_statements` | Statistik query (**wajib** di hampir semua produksi) |
| `pg_trgm` | Pencarian teks mirip/`LIKE '%x%'` dengan index |
| `btree_gist`, `btree_gin` | Index GiST/GIN untuk tipe B-Tree |
| `pgcrypto` | Fungsi kriptografi |
| `postgres_fdw` | Akses database PostgreSQL lain |
| `PostGIS` | Data geospasial |
| `pgvector` | Pencarian vektor/embedding untuk AI |
| `pg_partman`, `pg_repack`, `auto_explain`, `pg_buffercache` | Partisi otomatis, repack tanpa lock, rencana otomatis, inspeksi buffer |

```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;   -- butuh shared_preload_libraries + restart
SELECT * FROM pg_available_extensions ORDER BY name;
```

### 12.9 System Catalog

**System catalog** adalah tabel/view internal yang menyimpan metadata (schema `pg_catalog`, `information_schema`).

| Catalog | Isi |
|---|---|
| `pg_class` | Tabel, index, view, sequence |
| `pg_attribute` | Kolom |
| `pg_index` | Index |
| `pg_namespace` | Schema |
| `pg_roles` / `pg_authid` | Role |
| `pg_database` | Database |
| `pg_settings` | Parameter konfigurasi |
| `information_schema.*` | Metadata berstandar SQL (portabel) |

## Praktik

```bash
docker exec -it pg-latihan psql -U postgres -d toko
```

### Proses dan Memori

```sql
SELECT pid, backend_type, state FROM pg_stat_activity ORDER BY backend_type;
SHOW shared_buffers; SHOW work_mem; SHOW max_connections; SHOW wal_level;
```

```bash
docker exec pg-latihan ps aux | grep postgres | head -20     # lihat proses postmaster dan background
```

### Layout File dan Ukuran

```sql
SET search_path TO app, public;
SELECT pg_relation_filepath('transaksi');
SELECT pg_size_pretty(pg_relation_size('transaksi')) AS tabel,
       pg_size_pretty(pg_indexes_size('transaksi')) AS index,
       pg_size_pretty(pg_total_relation_size('transaksi')) AS total;
SELECT oid, datname FROM pg_database;
```

```bash
docker exec pg-latihan bash -c 'ls $PGDATA && ls $PGDATA/pg_wal | head'
```

### Bloat dan Vacuum

```sql
CREATE TABLE uji_bloat AS SELECT g AS id, repeat('x', 100) AS isi FROM generate_series(1, 200000) g;
SELECT pg_size_pretty(pg_relation_size('uji_bloat'));
UPDATE uji_bloat SET isi = repeat('y', 100);                    -- menciptakan dead tuple
SELECT pg_size_pretty(pg_relation_size('uji_bloat'));           -- hampir 2x lipat
SELECT n_live_tup, n_dead_tup FROM pg_stat_user_tables WHERE relname = 'uji_bloat';
VACUUM (VERBOSE) uji_bloat;
SELECT pg_size_pretty(pg_relation_size('uji_bloat'));           -- ukuran file tetap
VACUUM FULL uji_bloat;
SELECT pg_size_pretty(pg_relation_size('uji_bloat'));           -- mengecil
```

### Konfigurasi

```sql
SELECT name, setting, context FROM pg_settings WHERE name IN ('shared_buffers','work_mem','max_connections');
ALTER SYSTEM SET work_mem = '32MB';
SELECT pg_reload_conf();
SHOW work_mem;

ALTER ROLE postgres IN DATABASE toko SET statement_timeout = '60s';
SELECT * FROM pg_db_role_setting;
ALTER SYSTEM RESET work_mem; SELECT pg_reload_conf();

ALTER TABLE transaksi SET (autovacuum_vacuum_scale_factor = 0.02);
SELECT reloptions FROM pg_class WHERE relname = 'transaksi';
```

### System Catalog

```sql
SELECT c.relname, c.relkind, c.reltuples::bigint AS estimasi_baris
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'app' AND c.relkind = 'r';

SELECT table_name, column_name, data_type
FROM information_schema.columns WHERE table_schema = 'app' AND table_name = 'produk';
```

## Latihan

1. Jalankan 3 sesi `psql` bersamaan dan perhatikan `pg_stat_activity`. Berapa proses backend baru muncul, dan apa konsekuensinya jika ada 2.000 koneksi aktif?
2. Buat tabel dengan 1 juta baris, `UPDATE` seluruh baris, dan ukur pertumbuhan file sebelum/sesudah `VACUUM` dan `VACUUM FULL`. Jelaskan mengapa `VACUUM` biasa tidak mengecilkan file tetapi tetap berguna.
3. Buka transaksi dan biarkan menggantung (`BEGIN; SELECT ...;` tanpa commit), lalu `UPDATE` banyak baris di sesi lain dan jalankan `VACUUM VERBOSE`. Apa yang terjadi pada dead tuple, dan mengapa?
4. Aktifkan `log_min_duration_statement = 100ms` melalui `ALTER SYSTEM`, jalankan query lambat, dan temukan barisnya di log container (`docker logs`).
5. Hitung usulan awal `shared_buffers` (25% RAM) dan batas aman `work_mem` untuk server 16 GB RAM, 100 koneksi aktif, dengan asumsi tiap query memakai rata-rata 2 node sort/hash. Tunjukkan rumusnya.
6. Diskusikan: mengapa `fsync = off` mempercepat tulis tetapi tidak boleh dipakai di produksi, dan dalam kasus apa (jika ada) wajar dimatikan?

---

[← Modul 11: Desain Schema & Pola Aplikasi](11-desain-schema-pola.md) · [Daftar Isi](README.md#daftar-isi) · [Modul 13: Security →](13-security.md)
