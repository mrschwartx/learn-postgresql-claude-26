# Modul 11: Desain Schema & Pola Aplikasi

[← Modul 10: Query Planner & EXPLAIN](10-query-planner-explain.md) · [Daftar Isi](README.md#daftar-isi) · [Modul 12: Arsitektur Internal & Konfigurasi →](12-internal-konfigurasi.md)

**Isi modul ini**

- [Teori](#teori)
  - [11.1 Normalisasi — Mengurangi Redundansi](#111-normalisasi--mengurangi-redundansi)
  - [11.2 Pola dan Anti-Pola Desain Skema](#112-pola-dan-anti-pola-desain-skema)
  - [11.3 Partitioning](#113-partitioning)
  - [11.4 Sharding](#114-sharding)
  - [11.5 Queue di PostgreSQL](#115-queue-di-postgresql)
  - [11.6 Pola Pagination](#116-pola-pagination)
  - [11.7 Bulk Loading dan Pemrosesan Data Massal](#117-bulk-loading-dan-pemrosesan-data-massal)
  - [11.8 Migrasi Skema yang Aman](#118-migrasi-skema-yang-aman)
  - [11.9 Tuning Berdasarkan Beban Kerja](#119-tuning-berdasarkan-beban-kerja)
- [Praktik](#praktik)
  - [Partitioning](#partitioning)
  - [Queue dengan SKIP LOCKED](#queue-dengan-skip-locked)
  - [Keyset Pagination vs OFFSET](#keyset-pagination-vs-offset)
  - [Migrasi Aman dan Bulk Load](#migrasi-aman-dan-bulk-load)
  - [Tool Migrasi dengan Flyway (Opsional)](#tool-migrasi-dengan-flyway-opsional)
  - [Queue dengan PgQ (Opsional)](#queue-dengan-pgq-opsional)
- [Latihan](#latihan)

---


## Teori

### 11.1 Normalisasi — Mengurangi Redundansi

**Normalisasi** adalah proses menata tabel agar data tidak berulang dan anomali (insert/update/delete) dihindari.

| Bentuk Normal | Aturan | Pelanggaran Khas |
|---|---|---|
| **1NF** | Setiap sel satu nilai atomik; tidak ada grup berulang | Kolom `telepon` berisi `"0812,0813"` |
| **2NF** | 1NF + setiap kolom non-kunci bergantung pada **seluruh** primary key | Tabel `item_pesanan(pesanan_id, produk_id, nama_produk)` — `nama_produk` hanya bergantung pada `produk_id` |
| **3NF** | 2NF + tidak ada **dependensi transitif** antar kolom non-kunci | `pelanggan(id, kode_pos, kota)` — `kota` ditentukan oleh `kode_pos` |
| **BCNF** | Setiap determinan adalah *candidate key* | Kasus lanjutan dari 3NF |

Praktik: **desain sampai 3NF**, lalu **denormalisasi secara sadar** hanya bila ada bukti performa (mis. kolom total yang disimpan, tabel ringkasan, materialized view).

| Normalisasi | Denormalisasi |
|---|---|
| Integritas kuat, tulis ringan | Baca cepat (lebih sedikit join) |
| Banyak join | Redundansi; risiko data tidak sinkron |

### 11.2 Pola dan Anti-Pola Desain Skema

| Anti-Pola | Masalah | Alternatif |
|---|---|---|
| Tanpa primary key | Duplikat, replikasi logical sulit | Selalu punya PK |
| **EAV** (Entity-Attribute-Value) | Query rumit, tanpa tipe & constraint | Kolom nyata atau `jsonb` |
| Menyimpan uang di `float` | Galat pembulatan | `numeric(p,s)` atau bilangan bulat (sen) |
| `timestamp` tanpa zona | Ambigu lintas zona waktu | `timestamptz` |
| Daftar dipisah koma di satu kolom | Melanggar 1NF; tak bisa di-index/join | Tabel penghubung / array |
| FK tanpa index | JOIN & `DELETE` induk lambat | Index pada kolom FK |
| Satu tabel "serba ada" | Kolom `NULL` melimpah | Pecah per entitas |
| Soft delete di mana-mana tanpa strategi | Query harus selalu `WHERE deleted_at IS NULL` | Partial index, view, atau arsip |
| `varchar(255)` refleks | Batas arbitrer | `text` + `CHECK` bila perlu |
| Mengandalkan urutan tanpa `ORDER BY` | Hasil tidak deterministik | Selalu `ORDER BY` |

**JSONB vs kolom relasional**: pakai `jsonb` untuk atribut yang **bervariasi/tidak terstruktur**; pakai kolom biasa untuk data inti yang di-filter, di-join, dan butuh constraint.

### 11.3 Partitioning

**Partitioning** memecah satu tabel logis menjadi banyak tabel fisik (partisi). Manfaat: query dengan filter kunci partisi hanya menyentuh partisi relevan (**partition pruning**), pemeliharaan lebih mudah (hapus data lama dengan `DROP`/`DETACH` partisi), vacuum/index per partisi lebih kecil.

| Metode | Cocok untuk |
|---|---|
| `RANGE` | Data deret waktu (per bulan/hari) |
| `LIST` | Kategori diskret (negara, tenant) |
| `HASH` | Sebaran merata tanpa kunci alami |

```sql
CREATE TABLE log_aktivitas (
    id          bigint GENERATED ALWAYS AS IDENTITY,
    dibuat_pada timestamptz NOT NULL,
    pesan       text
) PARTITION BY RANGE (dibuat_pada);

CREATE TABLE log_2026_11 PARTITION OF log_aktivitas
    FOR VALUES FROM ('2026-11-01') TO ('2026-12-01');
CREATE TABLE log_2026_12 PARTITION OF log_aktivitas
    FOR VALUES FROM ('2026-12-01') TO ('2027-01-01');
```

Catatan: primary key/unique pada tabel partisi **harus menyertakan kolom kunci partisi**. Otomatisasi pembuatan partisi dapat memakai `pg_partman` atau cron job.

### 11.4 Sharding

**Sharding** memecah data **lintas server** (horizontal scaling untuk tulis). PostgreSQL inti tidak memiliki sharding otomatis; pola yang umum:

| Pendekatan | Penjelasan |
|---|---|
| **Sharding di aplikasi** | Aplikasi memilih server berdasarkan *shard key* (mis. `tenant_id % N`) |
| **Foreign Data Wrapper** (`postgres_fdw`) | Tabel remote terlihat sebagai tabel lokal; terbatas untuk query lintas shard |
| **Ekstensi/Platform terdistribusi** | Citus, atau PostgreSQL-compatible terdistribusi lainnya |
| **Read replica** | Bukan sharding, tapi sering cukup untuk skala **baca** |

Sebelum sharding, tempuh dulu: optimasi query/index → partitioning → read replica → hardware lebih besar. Sharding menambah kompleksitas besar (join lintas shard, transaksi terdistribusi, resharding).

### 11.5 Queue di PostgreSQL

Untuk beban sedang, PostgreSQL bisa menjadi **job queue** tanpa broker terpisah:

```sql
-- Worker mengambil satu tugas aman dari konkurensi
WITH tugas AS (
    SELECT id FROM antrean
    WHERE status = 'menunggu'
    ORDER BY id
    FOR UPDATE SKIP LOCKED
    LIMIT 1
)
UPDATE antrean a SET status = 'diproses', mulai = now()
FROM tugas WHERE a.id = tugas.id
RETURNING a.*;
```

| Pilihan | Catatan |
|---|---|
| `FOR UPDATE SKIP LOCKED` | Pola paling umum; sederhana |
| `LISTEN`/`NOTIFY` | Membangunkan worker saat ada tugas baru (tanpa polling) |
| **PgQ**, library queue (mis. pgmq, River, Graphile Worker) | Fitur lebih lengkap (retry, scheduling) |
| Kafka / RabbitMQ | Throughput sangat tinggi, banyak konsumen, replay (course Kafka) |

**Mengenal PgQ.** PgQ adalah sistem antrean berbasis PostgreSQL yang awalnya dikembangkan di Skype dan menjadi bagian dari SkyTools. Londiste (replikasi berbasis trigger) dibangun di atasnya. Ia terdiri dari tiga lapisan:

| Lapisan | Peran |
|---|---|
| **Producer** | Aplikasi memasukkan event dengan `pgq.insert_event(queue, tipe, data)` di dalam transaksi yang sama dengan perubahan datanya |
| **Ticker** | Daemon (`pgqd`) yang secara berkala membuat *tick*; antara dua tick, event dikelompokkan menjadi satu **batch** |
| **Consumer** | Mendaftar dengan `pgq.register_consumer`, mengambil batch lewat `pgq.next_batch`, memproses event, lalu menutup batch dengan `pgq.finish_batch` |

Ciri khas PgQ dibanding pola `SKIP LOCKED`:

- Event ditulis ke tabel yang **dirotasi**, bukan di-`UPDATE`/`DELETE` satu per satu, sehingga hampir tanpa *bloat*.
- Beberapa consumer bisa membaca antrean yang sama, masing-masing dengan posisinya sendiri.
- Jaminannya **at-least-once**: batch yang belum di-`finish_batch` akan dikirim ulang, jadi consumer harus **idempoten**.
- **Ticker harus selalu berjalan.** Tanpa ticker, tidak ada batch baru dan tabel antrean tidak dirotasi.

Anti-pola antrean di PostgreSQL:

| Anti-pola | Akibat | Alternatif |
|---|---|---|
| `SELECT ... LIMIT 1` tanpa `FOR UPDATE SKIP LOCKED` | Dua worker mengambil tugas yang sama, atau saling menunggu lock | `FOR UPDATE SKIP LOCKED` |
| Menyimpan tugas selesai selamanya dalam tabel yang sama | Tabel membengkak, scan antrean melambat | Hapus atau arsipkan berkala; partisi per waktu |
| Polling dengan `sleep` sangat singkat | Beban query sia-sia | `LISTEN`/`NOTIFY` atau interval polling yang wajar |
| Worker menahan transaksi saat memproses lama | Menahan `VACUUM` dan lock | Tandai tugas `diproses` lalu commit; beri batas waktu (*visibility timeout*) |
| Consumer tidak idempoten | Efek ganda saat terjadi retry | Kunci idempotensi, mis. `ON CONFLICT DO NOTHING` |

### 11.6 Pola Pagination

| Pola | Kelebihan | Kekurangan |
|---|---|---|
| `LIMIT/OFFSET` | Sederhana, bisa loncat halaman | Lambat untuk offset besar; hasil bisa bergeser |
| **Keyset** (`WHERE (dibuat_pada, id) < (:t, :id) ORDER BY dibuat_pada DESC, id DESC LIMIT n`) | Konsisten dan cepat (dengan index) | Tidak bisa loncat ke halaman acak |

### 11.7 Bulk Loading dan Pemrosesan Data Massal

| Teknik | Manfaat |
|---|---|
| `COPY` / `\copy` | Jauh lebih cepat daripada ribuan `INSERT` |
| `INSERT` multi-baris (`VALUES (..),(..)`) | Kurangi round-trip jaringan |
| Dalam satu transaksi | Hindari commit per baris |
| Buat index **setelah** muat data | Hindari update index per baris |
| `UNLOGGED` table / tabel staging | Tulis lebih cepat untuk data sementara (hilang saat crash) |
| Naikkan sementara `maintenance_work_mem`, `max_wal_size` | Percepat build index dan checkpoint |
| Jalankan `ANALYZE` setelahnya | Perbarui statistik planner |

### 11.8 Migrasi Skema yang Aman

| Prinsip | Penjelasan |
|---|---|
| **Gunakan tool migrasi** | Flyway, Liquibase, Alembic, golang-migrate, Prisma Migrate, Rails/Django migrations — versi skema tercatat dan berulang |
| **DDL transaksional** | Bungkus dalam `BEGIN/COMMIT` agar atomik |
| **Hindari lock panjang** | `ALTER TABLE` mengambil lock berat; set `lock_timeout` agar gagal cepat daripada memblokir antrean |
| `CREATE INDEX CONCURRENTLY` | Tidak memblokir tulis |
| Tambah kolom `NOT NULL` | Tambah nullable → isi bertahap (batch) → `SET NOT NULL` (gunakan `CHECK ... NOT VALID` lalu `VALIDATE CONSTRAINT`) |
| **Expand → Migrate → Contract** | Tambah struktur baru, pindahkan data & kode, baru hapus struktur lama — aman untuk deploy tanpa downtime |

**Anti-pola migrasi**

| Anti-pola | Mengapa berbahaya | Praktik yang benar |
|---|---|---|
| Mengubah file migrasi yang sudah dijalankan | Checksum tidak cocok; lingkungan berbeda menyimpang | Buat migrasi baru yang memperbaiki |
| Menjalankan DDL manual di produksi | Tidak tercatat, tidak bisa diulang di staging | Semua perubahan lewat tool migrasi dan Git |
| `RENAME COLUMN` langsung | Versi aplikasi lama langsung rusak | Expand → Migrate → Contract |
| `DROP COLUMN` sebelum kode berhenti memakainya | Error pada aplikasi yang masih berjalan | Rilis kode dulu, hapus kolom di rilis berikutnya |
| `UPDATE` jutaan baris dalam satu transaksi | Lock lama, WAL besar, bloat | Batch bertahap (mis. 10.000 baris per iterasi) |
| `CREATE INDEX` tanpa `CONCURRENTLY` pada tabel ramai | Memblokir penulisan | `CREATE INDEX CONCURRENTLY` (tidak bisa di dalam transaksi) |
| `ADD COLUMN ... DEFAULT` dengan fungsi *volatile* | Menulis ulang seluruh tabel | Default konstan (sejak PG 11 instan), isi nilai lain secara bertahap |
| Tanpa rencana mundur | Tidak bisa kembali saat gagal | Siapkan migrasi *forward-fix* atau skrip rollback yang diuji |

**Tool migrasi**

| Tool | Cara mendefinisikan migrasi | Contoh |
|---|---|---|
| **Flyway** | File SQL berversi pada folder | `V1__buat_tabel.sql`, `V2__tambah_index.sql` |
| **Liquibase** | *Changelog* YAML/XML/SQL berisi *changeset* | `databaseChangeLog: - changeSet: {id: 1, author: budi, ...}` |
| **Alembic** (Python/SQLAlchemy) | Skrip Python dengan `upgrade()` dan `downgrade()` | `alembic revision -m "tambah merek"` lalu `alembic upgrade head` |
| **golang-migrate** | Pasangan file `up`/`down` | `000001_init.up.sql`, `000001_init.down.sql`; `migrate -path db/migrations -database "$URL" up` |
| **Sqitch** | Skrip `deploy`/`revert`/`verify` tanpa nomor versi (berbasis dependensi) | `sqitch add tambah_merek -n "Tambah kolom merek"` |
| **Atlas** | Deklaratif: bandingkan skema yang diinginkan dengan database lalu hasilkan migrasi | `atlas migrate diff`, `atlas migrate apply` |
| Migrasi bawaan framework | Rails, Django, Prisma, Laravel | `python manage.py migrate` |

Pilih satu tool per proyek, jalankan di pipeline CI/CD, dan pastikan migrasi diuji terhadap salinan data berukuran realistis.

### 11.9 Tuning Berdasarkan Beban Kerja

| Beban | Ciri | Fokus tuning |
|---|---|---|
| **OLTP** | Banyak transaksi kecil, latensi rendah | Index tepat, connection pooling, `shared_buffers`, vacuum agresif, sedikit `work_mem` |
| **OLAP** | Query berat, scan besar, agregasi | `work_mem` besar, paralelisme, partitioning, columnar/ekstensi analitik, replica khusus |
| **HTAP** | Campuran | Pisahkan beban ke replica; materialized view; pertimbangkan sistem terpisah bila bentrok |

Detail parameter ada di [Modul 12](12-internal-konfigurasi.md).

## Praktik

```bash
docker exec -it pg-latihan psql -U postgres -d toko
```

### Partitioning

```sql
SET search_path TO app, public;

CREATE TABLE log_aktivitas (
    id bigint GENERATED ALWAYS AS IDENTITY,
    dibuat_pada timestamptz NOT NULL,
    pesan text,
    PRIMARY KEY (id, dibuat_pada)
) PARTITION BY RANGE (dibuat_pada);

CREATE TABLE log_2026_10 PARTITION OF log_aktivitas FOR VALUES FROM ('2026-10-01') TO ('2026-11-01');
CREATE TABLE log_2026_11 PARTITION OF log_aktivitas FOR VALUES FROM ('2026-11-01') TO ('2026-12-01');
CREATE TABLE log_default PARTITION OF log_aktivitas DEFAULT;

INSERT INTO log_aktivitas (dibuat_pada, pesan)
SELECT '2026-10-01'::timestamptz + (g || ' minutes')::interval, 'log ' || g
FROM generate_series(1, 80000) g;

\d+ log_aktivitas
SELECT tableoid::regclass AS partisi, count(*) FROM log_aktivitas GROUP BY 1;

-- Partition pruning: perhatikan hanya satu partisi yang dipindai
EXPLAIN SELECT * FROM log_aktivitas WHERE dibuat_pada >= '2026-11-10' AND dibuat_pada < '2026-11-11';

-- Hapus data lama secara instan
ALTER TABLE log_aktivitas DETACH PARTITION log_2026_10;
DROP TABLE log_2026_10;
```

### Queue dengan SKIP LOCKED

```sql
CREATE TABLE antrean (id bigserial PRIMARY KEY, payload text, status text DEFAULT 'menunggu', mulai timestamptz);
INSERT INTO antrean (payload) SELECT 'tugas-' || g FROM generate_series(1, 10) g;

WITH tugas AS (
  SELECT id FROM antrean WHERE status = 'menunggu' ORDER BY id FOR UPDATE SKIP LOCKED LIMIT 1
)
UPDATE antrean a SET status = 'diproses', mulai = now() FROM tugas WHERE a.id = tugas.id RETURNING a.*;
```

Jalankan perintah di atas dari **dua terminal** secara bergantian: setiap worker mendapat tugas berbeda.

### Keyset Pagination vs OFFSET

```sql
\timing on
SELECT id FROM transaksi ORDER BY id LIMIT 20 OFFSET 900000;
SELECT id FROM transaksi WHERE id > 900000 ORDER BY id LIMIT 20;
```

### Migrasi Aman dan Bulk Load

```sql
-- NOT NULL bertahap
ALTER TABLE produk ADD COLUMN merek text;
UPDATE produk SET merek = 'Generik' WHERE merek IS NULL;
ALTER TABLE produk ADD CONSTRAINT merek_wajib CHECK (merek IS NOT NULL) NOT VALID;
ALTER TABLE produk VALIDATE CONSTRAINT merek_wajib;

-- Agar DDL tidak memblokir antrean lock
SET lock_timeout = '3s';
CREATE INDEX CONCURRENTLY idx_produk_merek ON produk (merek);

-- Bulk load: COPY vs INSERT per baris
CREATE UNLOGGED TABLE staging_produk (LIKE produk INCLUDING ALL);
\copy produk TO 'produk_full.csv' WITH (FORMAT csv, HEADER true)
\copy staging_produk FROM 'produk_full.csv' WITH (FORMAT csv, HEADER true)
```

### Tool Migrasi dengan Flyway (Opsional)

Flyway dijalankan lewat Docker dan terhubung ke container `pg-latihan` melalui jaringan Docker khusus:

```bash
docker network create migrasi-net
docker network connect migrasi-net pg-latihan

mkdir -p sql
cat > sql/V1__tambah_kolom_catatan.sql <<'EOF'
ALTER TABLE app.produk ADD COLUMN IF NOT EXISTS catatan text;
EOF
cat > sql/V2__index_nama_produk.sql <<'EOF'
CREATE INDEX IF NOT EXISTS idx_produk_nama ON app.produk (nama);
EOF

docker run --rm --network migrasi-net -v "$PWD/sql:/flyway/sql" flyway/flyway \
  -url=jdbc:postgresql://pg-latihan:5432/toko -user=postgres -password=rahasia \
  -baselineOnMigrate=true -baselineVersion=0 migrate

docker run --rm --network migrasi-net -v "$PWD/sql:/flyway/sql" flyway/flyway \
  -url=jdbc:postgresql://pg-latihan:5432/toko -user=postgres -password=rahasia info

docker exec pg-latihan psql -U postgres -d toko -c "SELECT version, description, success FROM flyway_schema_history;"
```

`-baselineOnMigrate` diperlukan karena database `toko` sudah berisi tabel sebelum Flyway dipakai. Ubah isi `V1__...sql` setelah dijalankan dan jalankan `migrate` lagi: Flyway menolak karena checksum berubah. Itulah alasan aturan "jangan mengubah migrasi yang sudah berjalan".

Pembersihan: `docker network disconnect migrasi-net pg-latihan && docker network rm migrasi-net`.

### Queue dengan PgQ (Opsional)

PgQ adalah ekstensi yang tidak ada di image `postgres` resmi. Pasang paket PGDG ke container latihan (nama paket berbentuk `postgresql-<versi>-pgq3`; cek dengan `apt-cache search pgq` bila tidak ditemukan untuk versi Anda):

```bash
docker exec -u root pg-latihan bash -c 'apt-get update -qq && apt-get install -y -qq postgresql-18-pgq3'
docker exec pg-latihan psql -U postgres -d toko -c "CREATE EXTENSION pgq;"
```

```sql
SELECT pgq.create_queue('pesanan_baru');
SELECT pgq.register_consumer('pesanan_baru', 'worker_email');

-- Producer
SELECT pgq.insert_event('pesanan_baru', 'dibuat', '{"pesanan_id": 1}');
SELECT pgq.insert_event('pesanan_baru', 'dibuat', '{"pesanan_id": 2}');

-- Ticker: pada sistem nyata dikerjakan daemon pgqd; di latihan kita picu manual
SELECT pgq.ticker();

-- Consumer
SELECT pgq.next_batch('pesanan_baru', 'worker_email');       -- mengembalikan batch_id, misalnya 1
SELECT ev_id, ev_type, ev_data FROM pgq.get_batch_events(1); -- ganti 1 dengan batch_id Anda
SELECT pgq.finish_batch(1);

-- Status consumer
SELECT * FROM pgq.get_consumer_info();
```

Jika `next_batch` mengembalikan `NULL`, belum ada tick baru: jalankan `pgq.ticker()` lagi. Jalankan `next_batch` sekali lagi **tanpa** `finish_batch` pada batch baru dan perhatikan bahwa batch yang sama dikirim ulang (*at-least-once*).

## Latihan

1. Diberikan tabel `pesanan_lama(id, pelanggan_nama, pelanggan_alamat, produk_nama, produk_harga, jumlah)`, normalisasikan hingga 3NF dan gambarkan tabel hasilnya beserta relasinya.
2. Rancang tabel `tiket_dukungan` dengan atribut yang bervariasi per jenis tiket. Kapan Anda memakai `jsonb` dan kapan kolom biasa? Buat versi EAV sebagai pembanding dan jelaskan mengapa lebih buruk.
3. Buat tabel `sensor_data` dipartisi per **hari** untuk 3 hari, isi 100.000 baris, dan buktikan dengan `EXPLAIN` bahwa query satu hari hanya memindai satu partisi. Bagaimana Anda mengotomatiskan pembuatan partisi hari berikutnya?
4. Implementasikan *job queue* dengan `SKIP LOCKED`, tambahkan kolom `percobaan` dan logika retry hingga 3 kali sebelum status `gagal`.
5. Bandingkan waktu memuat 100.000 baris dengan (a) 100.000 `INSERT` terpisah, (b) satu `INSERT` multi-baris, (c) `COPY`. Catat hasilnya.
6. Diskusikan: sebuah toko online tumbuh dari 1 juta ke 1 miliar baris pesanan. Urutkan langkah-langkah skala (index, partisi, replica, sharding, arsip) dan jelaskan kapan masing-masing mulai diperlukan.
7. Buat tiga migrasi Flyway: (a) tambah kolom `merek` nullable, (b) isi bertahap, (c) tambah constraint `NOT NULL` lewat `CHECK ... NOT VALID` dan `VALIDATE`. Jelaskan mengapa ketiganya dipisah menjadi migrasi terpisah.
8. Bandingkan antrean `SKIP LOCKED` dan PgQ: sebutkan dua situasi di mana PgQ lebih unggul dan satu situasi di mana `SKIP LOCKED` cukup.
9. Daftar tiga anti-pola migrasi yang pernah atau mungkin Anda temui di proyek Anda, dan tuliskan versi aman untuk masing-masing.

---

[← Modul 10: Query Planner & EXPLAIN](10-query-planner-explain.md) · [Daftar Isi](README.md#daftar-isi) · [Modul 12: Arsitektur Internal & Konfigurasi →](12-internal-konfigurasi.md)
