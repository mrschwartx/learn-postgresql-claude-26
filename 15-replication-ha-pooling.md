# Modul 15: Replication, High Availability & Connection Pooling

[← Modul 14: Backup, Recovery & Upgrade](14-backup-recovery-upgrade.md) · [Daftar Isi](README.md#daftar-isi) · [Modul 16: Monitoring, Troubleshooting & Operasi →](16-monitoring-troubleshooting.md)

**Isi modul ini**

- [Teori](#teori)
  - [15.1 Mengapa Replikasi?](#151-mengapa-replikasi)
  - [15.2 Streaming Replication (Fisik)](#152-streaming-replication-fisik)
  - [15.3 Logical Replication](#153-logical-replication)
  - [15.4 High Availability dan Manajemen Cluster](#154-high-availability-dan-manajemen-cluster)
  - [15.5 Load Balancing dan Service Discovery](#155-load-balancing-dan-service-discovery)
  - [15.6 Connection Pooling](#156-connection-pooling)
  - [15.7 PostgreSQL di Kubernetes](#157-postgresql-di-kubernetes)
- [Praktik](#praktik)
  - [Menyiapkan Primary](#menyiapkan-primary)
  - [Membangun Replica](#membangun-replica)
  - [Verifikasi Replikasi](#verifikasi-replikasi)
  - [Simulasi Failover Manual](#simulasi-failover-manual)
  - [Logical Replication](#logical-replication)
  - [PgBouncer](#pgbouncer)
  - [Membersihkan Lingkungan](#membersihkan-lingkungan)
- [Latihan](#latihan)

---


## Teori

### 15.1 Mengapa Replikasi?

| Tujuan | Penjelasan |
|---|---|
| **High Availability (HA)** | Jika primary mati, replica diangkat menjadi primary baru (*failover*) |
| **Skala baca** | Query baca/laporan dialihkan ke replica |
| **Backup & DR** | Salinan di region/zona lain |
| **Migrasi & upgrade** | Pindah versi/server dengan downtime minimal |
| **Integrasi data** | Mengalirkan perubahan ke sistem lain (CDC → Kafka, data warehouse) |

> Replikasi **bukan pengganti backup**: `DROP TABLE` yang tidak sengaja ikut tereplikasi ke semua replica dalam hitungan detik.

### 15.2 Streaming Replication (Fisik)

**Streaming replication** mengirim aliran **WAL** ([Modul 7](07-transaksi-mvcc-wal.md)) dari primary ke standby, yang me-*replay*-nya sehingga menjadi salinan **byte-per-byte** seluruh cluster.

```
 ┌───────────────┐  WAL stream (walsender → walreceiver)  ┌───────────────┐
 │   PRIMARY     │ ─────────────────────────────────────► │   STANDBY     │
 │ (baca + tulis)│                                        │ (hot standby: │
 └───────────────┘                                        │  hanya baca)  │
                                                          └───────────────┘
```

| Aspek | Penjelasan |
|---|---|
| **Hot standby** | Replica dapat melayani query **baca** |
| **Asinkron** (default) | Primary tidak menunggu replica → cepat, tetapi **mungkin kehilangan** transaksi terakhir saat failover |
| **Sinkron** | `synchronous_standby_names` + `synchronous_commit = on`/`remote_apply` → tidak ada kehilangan data, tetapi commit lebih lambat dan bergantung pada replica |
| **Replication slot** | Menjamin primary menyimpan WAL sampai dikonsumsi replica (**awas**: replica mati lama → disk primary penuh; pantau dan set `max_slot_wal_keep_size`) |
| **Cascading replication** | Replica dapat menjadi sumber bagi replica lain |
| **Replication lag** | Selisih antara primary dan replica; pantau lewat `pg_stat_replication` |
| **Konflik query di replica** | Query panjang di replica bisa dibatalkan karena WAL replay butuh membersihkan baris (`hot_standby_feedback`, `max_standby_streaming_delay`) |

Parameter kunci di primary: `wal_level = replica` (atau `logical`), `max_wal_senders`, `max_replication_slots`; di replica: `hot_standby = on`, `primary_conninfo`, berkas `standby.signal`.

**Promote** (menjadikan standby sebagai primary): `SELECT pg_promote();` atau `pg_ctl promote`.

### 15.3 Logical Replication

**Logical replication** mereplikasi **perubahan baris** (INSERT/UPDATE/DELETE) per **tabel** memakai model **publish/subscribe** — bukan salinan fisik.

| Aspek | Streaming (fisik) | Logical |
|---|---|---|
| Unit | Seluruh cluster | Tabel terpilih |
| Versi mayor berbeda | Tidak | **Ya** (mendukung upgrade zero-downtime) |
| Replica bisa ditulis | Tidak | **Ya** (tabel lain / tabel yang sama dengan hati-hati) |
| DDL | Ikut (karena fisik) | **Tidak** ikut — skema harus disiapkan manual |
| Sequence | Ikut | Tidak ikut |
| Syarat tabel | — | Perlu **replica identity** (PK atau `REPLICA IDENTITY FULL`) |
| Use case | HA, skala baca | Upgrade, migrasi, konsolidasi, CDC (Debezium → Kafka), replikasi sebagian |

```sql
-- Di publisher (wal_level = logical)
CREATE PUBLICATION pub_toko FOR TABLE produk, pelanggan;

-- Di subscriber (struktur tabel sudah dibuat)
CREATE SUBSCRIPTION sub_toko
  CONNECTION 'host=pg-primary dbname=toko user=replicator password=...'
  PUBLICATION pub_toko;
```

### 15.4 High Availability dan Manajemen Cluster

Replikasi saja tidak otomatis memberi HA — Anda butuh sistem yang **mendeteksi kegagalan, memilih primary baru, dan mengarahkan klien**. Tantangan utamanya: mencegah **split-brain** (dua node sama-sama merasa primary).

| Alat | Karakteristik |
|---|---|
| **Patroni** | Standar de facto; memakai **DCS** (etcd, Consul, ZooKeeper, atau Kubernetes API) untuk leader election; REST API; terintegrasi HAProxy |
| **repmgr** | Manajemen replikasi & failover berbasis tool/daemon |
| **pg_auto_failover** | State machine sederhana dengan *monitor* node |
| **Stolon** | Cloud-native (kini jarang dipakai dibanding operator) |
| **Kubernetes Operator** | **CloudNativePG**, Zalando Postgres Operator, Crunchy PGO — mengotomatiskan HA, backup, upgrade di Kubernetes (course Kubernetes) |
| **Managed service** | RDS Multi-AZ, Aurora, Cloud SQL HA — failover dikelola penyedia |

```
                      ┌────────────┐
   Aplikasi ─────────►│  HAProxy   │◄── health check ke REST API Patroni
                      └─────┬──────┘     (:8008 /primary , /replica)
             ┌──────────────┼──────────────┐
             ▼              ▼              ▼
       ┌──────────┐   ┌──────────┐   ┌──────────┐
       │ Patroni  │   │ Patroni  │   │ Patroni  │
       │ PG (L)   │   │ PG (R)   │   │ PG (R)   │    L = leader, R = replica
       └────┬─────┘   └────┬─────┘   └────┬─────┘
            └──────────────┴──────────────┘
                     etcd / Consul (DCS) — kunci leader & konfigurasi
```

### 15.5 Load Balancing dan Service Discovery

| Komponen | Peran |
|---|---|
| **HAProxy** | TCP load balancer; memisahkan port tulis (ke primary) dan baca (ke replica) berdasarkan health check Patroni |
| **Keepalived** | Virtual IP (VRRP) yang berpindah ke node HAProxy sehat |
| **Consul / etcd** | Service discovery & konfigurasi terdistribusi |
| **`libpq` multi-host** | `postgresql://h1,h2/db?target_session_attrs=read-write` — klien memilih primary sendiri |
| **Pooler dengan routing** | PgCat, Pgpool-II (bisa memisahkan baca/tulis) |

```
# haproxy.cfg (cuplikan)
listen postgres_tulis
    bind *:5000
    option httpchk GET /primary
    http-check expect status 200
    default-server inter 3s fall 3 rise 2 on-marked-down shutdown-sessions
    server pg1 10.0.1.11:5432 maxconn 100 check port 8008
    server pg2 10.0.1.12:5432 maxconn 100 check port 8008
```

### 15.6 Connection Pooling

Setiap koneksi PostgreSQL adalah **proses OS** ([Modul 12](12-internal-konfigurasi.md)); ribuan koneksi dari aplikasi (apalagi microservice/serverless) membebani server. **Connection pooler** menampung banyak koneksi klien dan memakai ulang sedikit koneksi ke server.

| Mode **PgBouncer** | Koneksi server dilepas setelah... | Batasan |
|---|---|---|
| **`session`** | Klien disconnect | Paling kompatibel; hemat sedikit |
| **`transaction`** | Transaksi selesai | **Paling umum** untuk web; fitur sesi (`SET`, advisory lock, `LISTEN`, prepared statement lama) tidak aman — gunakan `SET LOCAL`; dukungan prepared statement tergantung versi PgBouncer |
| `statement` | Setiap statement | Tidak mendukung transaksi multi-statement |

```ini
; pgbouncer.ini (cuplikan)
[databases]
toko = host=127.0.0.1 port=5432 dbname=toko

[pgbouncer]
listen_port = 6432
auth_type = scram-sha-256
auth_file = /etc/pgbouncer/userlist.txt
pool_mode = transaction
default_pool_size = 20
max_client_conn = 2000
```

| Alternatif PgBouncer | Catatan |
|---|---|
| **PgCat** | Rust; pooling + load balancing + sharding dasar |
| **Pgpool-II** | Pooling + load balancing + failover (lebih berat/kompleks) |
| **Odyssey** | Multi-thread, performa tinggi |
| **Amazon RDS Proxy** | Managed pooler untuk RDS/Aurora |
| **Pooler di aplikasi** | HikariCP, pgx pool — tetap dianjurkan, tetapi **tidak menggantikan** pooler eksternal pada skala besar |

Pedoman ukuran: jumlah koneksi aktif ke database sebaiknya sekitar **2–4× jumlah core CPU**; sisanya antre di pooler.

### 15.7 PostgreSQL di Kubernetes

| Pendekatan | Catatan |
|---|---|
| **Operator** (CloudNativePG, Zalando, Crunchy) | Direkomendasikan — mengelola HA, backup ke object storage, upgrade, pooling |
| **Helm chart** (Bitnami `postgresql`, `postgresql-ha`) | Cepat untuk dev/test; evaluasi dukungan jangka panjang untuk produksi |
| **StatefulSet manual** | Rumit — hindari kecuali sangat paham |

Prinsip: gunakan `PersistentVolume` dengan storage cepat, atur `PodDisruptionBudget` dan *anti-affinity*, simpan backup & arsip WAL di object storage, dan uji *failover* secara rutin.

## Praktik

### Menyiapkan Primary

```bash
docker network create pgnet

docker run -d --name pg-primary --network pgnet \
  -e POSTGRES_PASSWORD=rahasia -v primary-data:/var/lib/postgresql \
  postgres:18 \
  -c wal_level=logical -c max_wal_senders=10 -c max_replication_slots=10 -c hot_standby=on

# role replikasi + izin koneksi replikasi dari jaringan docker
docker exec pg-primary psql -U postgres -c \
  "CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'repl-rahasia';"
docker exec pg-primary bash -c \
  'echo "host replication replicator all scram-sha-256" >> $PGDATA/pg_hba.conf'
docker exec pg-primary psql -U postgres -c "SELECT pg_reload_conf();"
```

### Membangun Replica

Bangun replica dari base backup (`-R` otomatis menulis `standby.signal` dan `primary_conninfo`):

```bash
docker run -d --name pg-replica --network pgnet --user postgres \
  -e PGPASSWORD=repl-rahasia -v replica-data:/var/lib/postgresql \
  postgres:18 \
  bash -c 'pg_basebackup -h pg-primary -U replicator -D "$PGDATA" -R -X stream -P && exec postgres'

docker logs pg-replica | tail -5          # cari "ready to accept read-only connections"
```

### Verifikasi Replikasi

```bash
docker exec pg-primary psql -U postgres -c "SELECT client_addr, state, sync_state, replay_lag FROM pg_stat_replication;"
docker exec pg-primary psql -U postgres -c "CREATE TABLE uji (id serial, waktu timestamptz DEFAULT now()); INSERT INTO uji DEFAULT VALUES;"
docker exec pg-replica psql -U postgres -c "SELECT * FROM uji;"                      # data muncul di replica
docker exec pg-replica psql -U postgres -c "SELECT pg_is_in_recovery();"             # true
docker exec pg-replica psql -U postgres -c "INSERT INTO uji DEFAULT VALUES;"         # ERROR: read-only transaction
```

### Simulasi Failover Manual

```bash
docker stop pg-primary
docker exec pg-replica psql -U postgres -c "SELECT pg_promote();"
docker exec pg-replica psql -U postgres -c "SELECT pg_is_in_recovery();"             # false: kini primary
docker exec pg-replica psql -U postgres -c "INSERT INTO uji DEFAULT VALUES;"         # berhasil
```

### Logical Replication

Logical replication (gunakan primary baru atau jalankan ulang `pg-primary`). Contoh dengan subscriber terpisah:

```bash
docker start pg-primary        # bila masih mati; catatan: ia kini 'tertinggal' dari replica yang dipromosikan
docker run -d --name pg-sub --network pgnet -e POSTGRES_PASSWORD=rahasia postgres:18

docker exec pg-primary psql -U postgres -c "CREATE TABLE produk_rep (id int PRIMARY KEY, nama text);"
docker exec pg-primary psql -U postgres -c "GRANT SELECT ON produk_rep TO replicator;"
docker exec pg-primary psql -U postgres -c "CREATE PUBLICATION pub_toko FOR TABLE produk_rep;"
docker exec pg-sub psql -U postgres -c "CREATE TABLE produk_rep (id int PRIMARY KEY, nama text);"
docker exec pg-sub psql -U postgres -c \
 "CREATE SUBSCRIPTION sub_toko CONNECTION 'host=pg-primary dbname=postgres user=replicator password=repl-rahasia' PUBLICATION pub_toko;"

docker exec pg-primary psql -U postgres -c "INSERT INTO produk_rep VALUES (1,'Laptop'),(2,'Mouse');"
docker exec pg-sub psql -U postgres -c "SELECT * FROM produk_rep;"
```

### PgBouncer

PgBouncer (image komunitas; periksa README image untuk daftar variabel terbaru):

```bash
docker run -d --name pgbouncer --network pgnet -p 6432:5432 \
  -e DB_HOST=pg-primary -e DB_USER=postgres -e DB_PASSWORD=rahasia \
  -e POOL_MODE=transaction -e AUTH_TYPE=scram-sha-256 \
  edoburu/pgbouncer

psql "postgresql://postgres:rahasia@localhost:6432/postgres" -c "SELECT 1;"
```

### Membersihkan Lingkungan

Bersihkan: `docker rm -f pg-primary pg-replica pg-sub pgbouncer && docker volume rm primary-data replica-data && docker network rm pgnet`.

## Latihan

1. Bangun primary + replica seperti di atas, lalu matikan replica selama beberapa menit sambil menulis data di primary (dengan replication slot aktif). Pantau ukuran `pg_wal` dan jelaskan risiko slot yang tidak dikonsumsi.
2. Ukur *replication lag* (`replay_lag`, `pg_wal_lsn_diff`) saat primary menerima beban tulis berat (misalnya `INSERT ... generate_series(1, 5000000)`). Apa yang memengaruhi lag?
3. Ubah ke replikasi **sinkron** (`synchronous_standby_names`) lalu hentikan replica. Apa yang terjadi pada `COMMIT` di primary? Mengapa ini trade-off antara konsistensi dan ketersediaan?
4. Siapkan logical replication dua arah **berbeda tabel** dan buktikan bahwa DDL (mis. `ALTER TABLE ADD COLUMN`) tidak otomatis tereplikasi. Bagaimana prosedur yang aman untuk perubahan skema?
5. Gambarkan arsitektur HA 3 node dengan Patroni + etcd + HAProxy. Jelaskan apa yang terjadi saat primary mati: siapa yang mendeteksi, memilih leader baru, dan bagaimana klien diarahkan?
6. Diskusikan: aplikasi serverless membuka 3.000 koneksi singkat ke PostgreSQL. Jelaskan masalahnya dan solusi dengan PgBouncer mode `transaction` beserta batasan fitur sesi yang harus diperhatikan.

---

[← Modul 14: Backup, Recovery & Upgrade](14-backup-recovery-upgrade.md) · [Daftar Isi](README.md#daftar-isi) · [Modul 16: Monitoring, Troubleshooting & Operasi →](16-monitoring-troubleshooting.md)
