# Modul 16: Monitoring, Troubleshooting & Operasi

[← Modul 15: Replication, High Availability & Connection Pooling](15-replication-ha-pooling.md) · [Daftar Isi](README.md#daftar-isi)

**Isi modul ini**

- [Teori](#teori)
  - [16.1 Apa yang Dipantau?](#161-apa-yang-dipantau)
  - [16.2 System View Penting](#162-system-view-penting)
  - [16.3 Alat Monitoring](#163-alat-monitoring)
  - [16.4 Troubleshooting Sistematis](#164-troubleshooting-sistematis)
  - [16.5 Alat Level Sistem Operasi](#165-alat-level-sistem-operasi)
  - [16.6 Analisis Log](#166-analisis-log)
  - [16.7 Otomasi dan Infrastructure as Code](#167-otomasi-dan-infrastructure-as-code)
  - [16.8 Capacity Planning dan Provisioning](#168-capacity-planning-dan-provisioning)
  - [16.9 Berkontribusi ke PostgreSQL](#169-berkontribusi-ke-postgresql)
- [Praktik](#praktik)
  - [pg_stat_statements dan pgbench](#pg_stat_statements-dan-pgbench)
  - [Simulasi Blocking](#simulasi-blocking)
  - [Proteksi dari Sesi Nakal](#proteksi-dari-sesi-nakal)
  - [Monitoring OS dan Prometheus (Opsional)](#monitoring-os-dan-prometheus-opsional)
  - [Analisis Log](#analisis-log)
  - [Monitoring Backup: check_pgbackrest (Opsional)](#monitoring-backup-check_pgbackrest-opsional)
  - [Otomasi: Shell, Python, dan Ansible](#otomasi-shell-python-dan-ansible)
- [Latihan](#latihan)

---


## Teori

### 16.1 Apa yang Dipantau?

Metodologi pemantauan yang populer sebagai kerangka berpikir:

| Metode | Fokus | Penerapan di PostgreSQL |
|---|---|---|
| **USE** (Utilization, Saturation, Errors) | **Resource** (CPU, memori, disk, jaringan) | CPU %, iowait, swap, antrean disk, kapasitas disk |
| **RED** (Rate, Errors, Duration) | **Layanan/request** | TPS, error rate, latensi query (p95/p99) |
| **Four Golden Signals** | Latency, Traffic, Errors, Saturation | Latensi query, TPS, error/rollback, koneksi mendekati `max_connections` |

Metrik PostgreSQL yang wajib dipantau:

| Kategori | Metrik | Sumber |
|---|---|---|
| Koneksi | Jumlah koneksi vs `max_connections`, `idle in transaction` | `pg_stat_activity` |
| Throughput | Transaksi commit/rollback per detik | `pg_stat_database` |
| Latensi | Query paling lambat/paling sering | `pg_stat_statements`, log |
| Cache | Cache hit ratio (`blks_hit / (blks_hit + blks_read)`) | `pg_stat_database` |
| Lock | Sesi menunggu / memblokir | `pg_locks`, `pg_stat_activity` |
| Vacuum | Dead tuple, umur vacuum, XID age | `pg_stat_user_tables`, `age(datfrozenxid)` |
| Replikasi | Lag, status slot | `pg_stat_replication`, `pg_replication_slots` |
| WAL & checkpoint | Checkpoint paksa, volume WAL | `pg_stat_checkpointer`, `pg_stat_wal` |
| Disk | Pertumbuhan tabel/index, ruang bebas | `pg_total_relation_size`, OS |
| Resource OS | CPU, memori, I/O | `top`, `iostat`, node exporter |

### 16.2 System View Penting

| View | Kegunaan |
|---|---|
| **`pg_stat_activity`** | Sesi aktif: query berjalan, state, `wait_event`, lama transaksi |
| **`pg_stat_statements`** | Statistik per-query ternormalisasi (waktu total, rata-rata, jumlah panggilan, baris) |
| `pg_stat_database` | Statistik per database (commit, rollback, cache hit, deadlock) |
| `pg_stat_user_tables` / `pg_stat_user_indexes` | Seq scan vs index scan, dead tuple, penggunaan index |
| `pg_locks` + `pg_blocking_pids()` | Lock dan siapa memblokir siapa |
| `pg_stat_replication`, `pg_replication_slots` | Replikasi |
| `pg_stat_progress_*` | Progres `VACUUM`, `CREATE INDEX`, `COPY`, `ANALYZE` |
| `pg_stat_checkpointer` (PG 17+; sebelumnya `pg_stat_bgwriter`), `pg_stat_io` (PG 16+) | Checkpoint dan I/O |

Mengaktifkan `pg_stat_statements`: tambahkan ke `shared_preload_libraries` (**restart**), lalu `CREATE EXTENSION pg_stat_statements;`.

### 16.3 Alat Monitoring

| Alat | Fungsi |
|---|---|
| **Prometheus + `postgres_exporter` + Grafana** | Stack metrik + dashboard + alert yang paling umum |
| **Zabbix** | Monitoring umum dengan template PostgreSQL |
| **pgBadger** | Analisis **log** → laporan HTML (query lambat, error, lock, koneksi) |
| **pgCluu** | Audit & laporan performa berbasis snapshot |
| **pgcenter** | "top" interaktif untuk PostgreSQL |
| **pg_activity** | Antarmuka "top" untuk `pg_stat_activity` |
| **temBoard** | Dashboard & manajemen berbasis web |
| **check_pgactivity**, **check_postgres** | Plugin Nagios/Icinga/Zabbix untuk kondisi server (koneksi, lag replikasi, WAL, dll.) |
| **check_pgbackrest** | Plugin Nagios/Icinga untuk **backup pgBackRest**: kebijakan retensi dan kelengkapan arsip WAL |
| **Cloud-native** | CloudWatch/Performance Insights (RDS), Cloud SQL Insights |

**Contoh penggunaan alat yang jarang dibahas**

| Alat | Contoh |
|---|---|
| **Zabbix** | Pasang Zabbix agent 2 (memiliki plugin PostgreSQL bawaan), lalu kaitkan template *PostgreSQL by Zabbix agent 2* ke host dan isi macro koneksi (`{$PG.URI}`, `{$PG.USER}`, `{$PG.PASSWORD}`) |
| **pgcenter** | `pgcenter top -h localhost -U postgres -d toko`; tombol angka berpindah antar tampilan (database, tabel, statement, replikasi) |
| **pgCluu** | `pgcluu_collectd -i 60 /var/lib/pgcluu/data/` mengumpulkan statistik tiap 60 detik; `pgcluu -o /var/www/pgcluu /var/lib/pgcluu/data/` membuat laporan HTML |
| **temBoard** | Terdiri dari server UI dan *agent* di tiap host PostgreSQL; agent didaftarkan ke UI lalu Anda mendapat dashboard, statistik, dan manajemen aktivitas lewat web |
| **check_pgactivity** | `check_pgactivity -h localhost -U nagios -s connection -w 70% -c 90%`; `-s backends` untuk jumlah koneksi; `--list` menampilkan semua *service* |
| **check_pgbackrest** | `check_pgbackrest --service=retention --stanza=toko --retention-full=2` memberi *critical* bila full backup kurang dari 2; `--service=archives --stanza=toko` memeriksa WAL yang hilang |

Pilihan pada plugin Nagios (`-w` untuk *warning*, `-c` untuk *critical*) mengikuti konvensi Nagios: kode keluar 0 = OK, 1 = WARNING, 2 = CRITICAL, 3 = UNKNOWN.

### 16.4 Troubleshooting Sistematis

```
 Gejala  ──► Hipotesis ──► Ukur ──► Perbaiki ──► Verifikasi ──► Dokumentasikan
```

| Gejala | Periksa | Penyebab umum |
|---|---|---|
| Aplikasi "lambat" | `pg_stat_statements`, `EXPLAIN (ANALYZE, BUFFERS)` | Index hilang, statistik usang, query buruk |
| Banyak query menunggu | `pg_stat_activity.wait_event`, `pg_blocking_pids()` | Lock panjang, transaksi `idle in transaction` |
| `too many connections` | Jumlah sesi per aplikasi/state | Tanpa pooler, kebocoran koneksi |
| Disk penuh | Ukuran `pg_wal`, slot replikasi, log, tabel/index bloat | Slot menggantung, arsip WAL macet, bloat |
| Tabel/index membengkak | `n_dead_tup`, `last_autovacuum` | Autovacuum tertahan transaksi panjang |
| CPU 100% | `top`, query teratas | Seq scan masif, query paralel, banyak koneksi |
| I/O tinggi | `iostat`, `pg_stat_io`, checkpoint | Checkpoint terlalu sering, sort ke disk, cache kecil |
| Replica tertinggal | `pg_stat_replication` | Beban tulis, jaringan, query panjang di replica |
| Server tak mau start | Log server, `pg_controldata`, ruang disk | Konfigurasi salah, disk penuh, WAL korup |
| Peringatan XID wraparound | `age(datfrozenxid)` | Vacuum tidak bisa menyelesaikan freeze — **darurat** |

### 16.5 Alat Level Sistem Operasi

| Alat | Kegunaan |
|---|---|
| `top` / `htop` | CPU & memori per proses (proses `postgres` memperlihatkan query di judul) |
| **`sysstat`**: `iostat -x`, `vmstat`, `sar`, `mpstat` | Statistik I/O, memori, CPU historis |
| `iotop` | Proses pemakai I/O |
| `free -m`, `df -h`, `du` | Memori & disk |
| `ss -tanp` | Koneksi jaringan |
| `dmesg`, `journalctl` | Pesan kernel (mis. **OOM killer** membunuh proses PostgreSQL) |

Profiling dan debugging tingkat lanjut:

| Alat | Kegunaan |
|---|---|
| `strace -p PID` | Melihat system call proses backend |
| `gdb` | Backtrace dari proses/core dump |
| `perf` & **perf-tools** | Profiling CPU (flame graph) |
| **eBPF** (`bcc`, `bpftrace`) | Tracing kernel/user tingkat rendah dengan overhead kecil |
| **Core dump** | Diagnosis crash backend (`ulimit -c unlimited`, atur `core_pattern`) |

### 16.6 Analisis Log

```bash
# jumlah dan rata-rata durasi query lambat yang tercatat
grep -oE 'duration: [0-9.]+ ms' postgresql.log | awk '{n++; s+=$2} END {printf "%d query, rata-rata %.1f ms\n", n, s/n}'
# 10 pesan error/fatal paling sering
grep -E 'ERROR|FATAL' postgresql.log | sed -E 's/^.*(ERROR|FATAL): *//' | sort | uniq -c | sort -rn | head
# laporan HTML lengkap
pgbadger -j 4 -o laporan.html /var/log/postgresql/postgresql-*.log
```

`pgBadger` butuh `log_line_prefix` yang sesuai (mis. `%t [%p]: user=%u,db=%d,app=%a,client=%h `) dan logging seperti `log_min_duration_statement`, `log_checkpoints`, `log_lock_waits`, `log_temp_files`.

### 16.7 Otomasi dan Infrastructure as Code

| Pendekatan | Contoh penggunaan |
|---|---|
| **Shell script** | Backup terjadwal, rotasi, health check, `psql -c` untuk pengecekan |
| **Bahasa pemrograman** (Python/Go) | Tool internal, migrasi, laporan (psycopg, pgx) |
| **Configuration management** — **Ansible, Salt, Puppet, Chef** | Instalasi, `postgresql.conf`, `pg_hba.conf`, role, replikasi yang konsisten & berulang |
| **Terraform** | Provisioning RDS/Cloud SQL, jaringan, parameter group (course Terraform) |
| **Kubernetes Operator + GitOps** | Cluster sebagai YAML deklaratif |

Prinsip: setiap perubahan konfigurasi dan skema **dilacak di Git**, dapat diulang, dan dites di staging.

**Shell script: health check sederhana**

```bash
#!/usr/bin/env bash
# health_check.sh — keluar dengan kode 0=OK, 1=WARNING, 2=CRITICAL
set -euo pipefail
export PGCONNECT_TIMEOUT=5
PSQL="psql -X -At -h ${PGHOST:-localhost} -U ${PGUSER:-postgres} -d ${PGDATABASE:-postgres}"

pg_isready -q -h "${PGHOST:-localhost}" || { echo "CRITICAL: server tidak merespons"; exit 2; }

aktif=$($PSQL -c "SELECT count(*) FROM pg_stat_activity WHERE backend_type = 'client backend'")
maks=$($PSQL -c "SHOW max_connections")
persen=$(( aktif * 100 / maks ))

if   [ "$persen" -ge 90 ]; then echo "CRITICAL: koneksi $aktif/$maks ($persen%)"; exit 2
elif [ "$persen" -ge 70 ]; then echo "WARNING: koneksi $aktif/$maks ($persen%)"; exit 1
else echo "OK: koneksi $aktif/$maks ($persen%)"; fi
```

**Bahasa pemrograman (Python dengan psycopg 3)**

```python
import psycopg

with psycopg.connect("postgresql://postgres:rahasia@localhost:5432/toko") as conn:
    baris = conn.execute(
        "SELECT relname, n_dead_tup FROM pg_stat_user_tables ORDER BY n_dead_tup DESC LIMIT 5"
    ).fetchall()
    for nama, mati in baris:
        print(f"{nama:30} {mati}")
```

**Configuration management: satu tugas, empat alat**

Tujuan sama: PostgreSQL terpasang, database `toko` dan role `app` ada, serta `app` boleh login dari jaringan internal. Nama paket dan path bergantung distro; contoh memakai Debian/Ubuntu dengan repositori PGDG.

*Ansible* (koleksi `community.postgresql`, `ansible-galaxy collection install community.postgresql`):

```yaml
- name: Siapkan PostgreSQL
  hosts: db
  become: true
  vars:
    pg_version: 18
  tasks:
    - name: Pasang paket
      ansible.builtin.apt:
        name: ["postgresql-{{ pg_version }}", python3-psycopg2]
        state: present
        update_cache: true

    - name: Atur shared_buffers
      community.postgresql.postgresql_set:
        name: shared_buffers
        value: 1GB
      become_user: postgres
      notify: Restart PostgreSQL

    - name: Buat database toko
      community.postgresql.postgresql_db:
        name: toko
      become_user: postgres

    - name: Buat role app
      community.postgresql.postgresql_user:
        name: app
        password: "{{ vault_app_password }}"
        db: toko
      become_user: postgres

    - name: Izinkan app dari jaringan internal
      community.postgresql.postgresql_pg_hba:
        dest: "/etc/postgresql/{{ pg_version }}/main/pg_hba.conf"
        contype: host
        databases: toko
        users: app
        source: 10.0.1.0/24
        method: scram-sha-256
      notify: Reload PostgreSQL

  handlers:
    - name: Restart PostgreSQL
      ansible.builtin.service: { name: postgresql, state: restarted }
    - name: Reload PostgreSQL
      ansible.builtin.service: { name: postgresql, state: reloaded }
```

*Salt* (state `/srv/salt/postgres.sls`):

```yaml
postgresql:
  pkg.installed:
    - name: postgresql-18
  service.running:
    - name: postgresql
    - enable: True
    - require:
      - pkg: postgresql

database_toko:
  postgres_database.present:
    - name: toko
    - user: postgres
    - require:
      - service: postgresql

role_app:
  postgres_user.present:
    - name: app
    - password: {{ pillar['pg_app_password'] }}
    - user: postgres
    - require:
      - service: postgresql
```

*Puppet* (modul `puppetlabs-postgresql`):

```puppet
class { 'postgresql::globals':
  version             => '18',
  manage_package_repo => true,
}
class { 'postgresql::server':
  listen_addresses => '*',
}
postgresql::server::db { 'toko':
  user     => 'app',
  password => postgresql::postgresql_password('app', $app_password),
}
postgresql::server::pg_hba_rule { 'app dari jaringan internal':
  type        => 'host',
  database    => 'toko',
  user        => 'app',
  address     => '10.0.1.0/24',
  auth_method => 'scram-sha-256',
}
```

*Chef* (cookbook `sous-chefs/postgresql`; nama properti mengikuti versi cookbook, jadi cocokkan dengan README-nya):

```ruby
postgresql_server_install 'PostgreSQL' do
  version '18'
  password data_bag_item('postgres', 'secrets')['postgres_password']
  action [:install, :create]
end
```

Perbandingan singkat: Ansible *agentless* (SSH) dan berurutan; Salt dan Puppet memakai agen dan model deklaratif; Chef memakai Ruby DSL. Semuanya idempoten: menjalankannya berulang menghasilkan keadaan yang sama.

### 16.8 Capacity Planning dan Provisioning

| Sumber daya | Pertimbangan |
|---|---|
| **CPU** | Jumlah core ≈ koneksi aktif paralel; query analitik butuh lebih banyak |
| **RAM** | Working set (data+index panas) ideal muat di `shared_buffers` + page cache |
| **Disk** | **IOPS & latensi** lebih penting daripada kapasitas; SSD/NVMe; pisahkan `pg_wal` bila perlu; sisakan ruang (backup, bloat, WAL, vacuum full) |
| **Jaringan** | Replikasi & backup |
| **Pertumbuhan** | Ukur laju pertumbuhan data per bulan dan proyeksikan 6–12 bulan |

Lakukan **load test** dengan `pgbench` atau skenario nyata sebelum produksi.

### 16.9 Berkontribusi ke PostgreSQL

| Cara | Penjelasan |
|---|---|
| **Mailing list** | `pgsql-general` (pengguna), `pgsql-hackers` (pengembangan inti), `pgsql-bugs` |
| **Review patch** | Ikut **CommitFest** — meninjau patch orang lain sangat dihargai |
| **Menulis patch** | Ikuti panduan kontribusi di wiki PostgreSQL; kirim patch ke `pgsql-hackers` |
| **Dokumentasi & terjemahan** | Perbaikan dokumen dan terjemahan |
| **Komunitas** | Konferensi (PGConf), user group lokal, blog Planet PostgreSQL |

**Langkah praktis memulai kontribusi**

| Tahap | Perintah/tindakan |
|---|---|
| Berlangganan | Daftar ke `pgsql-hackers` dan `pgsql-general` lewat postgresql.org/list; baca arsipnya beberapa minggu sebelum menulis |
| Ambil kode | `git clone https://git.postgresql.org/git/postgresql.git` |
| Bangun untuk pengembangan | `./configure --enable-debug --enable-cassert --enable-tap-tests --prefix=$HOME/pg-dev && make -j4 && make check` |
| Tulis patch | Buat cabang, ubah kode dan dokumentasi, tambahkan tes regresi di `src/test/regress` |
| Buat berkas patch | `git format-patch -v1 origin/master` (versi berikutnya: `-v2`, dst.) |
| Kirim | Lampirkan patch ke thread di `pgsql-hackers` dengan penjelasan masalah dan alasan solusi |
| Daftarkan di CommitFest | Tambahkan entri di commitfest.postgresql.org agar patch ditinjau pada putaran berikutnya |
| Review patch orang lain | Terapkan patch, jalankan `make check`, uji skenario, lalu balas di thread dengan temuan Anda |

Meninjau patch orang lain adalah jalan masuk paling mudah: Anda belajar basis kode dan kebiasaan komunitas tanpa harus menulis fitur besar.

Roadmap terkait yang layak dipelajari berikutnya: **Backend**, **DevOps**, **MongoDB** (perbandingan model dokumen), dan **System Design**.

## Praktik

Gunakan container `pg-latihan` dari modul-modul sebelumnya.

### pg_stat_statements dan pgbench

Aktifkan `pg_stat_statements` dan buat beban dengan `pgbench`:

```bash
docker exec pg-latihan psql -U postgres -c "ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_statements';"
docker restart pg-latihan
docker exec pg-latihan psql -U postgres -d toko -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;"

docker exec pg-latihan pgbench -U postgres -i -s 10 toko                 # inisialisasi data uji
docker exec pg-latihan pgbench -U postgres -c 10 -j 2 -T 30 toko         # 10 klien, 30 detik
```

```sql
-- 10 query paling menghabiskan waktu
SELECT calls, round(total_exec_time::numeric, 1) AS total_ms,
       round(mean_exec_time::numeric, 3) AS rata_ms, rows, left(query, 80) AS query
FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 10;

-- Cache hit ratio
SELECT datname, round(100.0 * blks_hit / nullif(blks_hit + blks_read, 0), 2) AS cache_hit_pct,
       xact_commit, xact_rollback, deadlocks
FROM pg_stat_database WHERE datname = 'toko';

-- Tabel dengan banyak seq scan atau dead tuple
SELECT relname, seq_scan, idx_scan, n_live_tup, n_dead_tup, last_autovacuum
FROM pg_stat_user_tables ORDER BY seq_scan DESC LIMIT 10;

-- Usia XID (pantau wraparound)
SELECT datname, age(datfrozenxid) FROM pg_database ORDER BY 2 DESC;
```

### Simulasi Blocking

Simulasi blocking dan penanganannya (dua terminal):

```
-- Terminal A
BEGIN;
UPDATE pgbench_accounts SET abalance = abalance + 1 WHERE aid = 1;     -- biarkan terbuka

-- Terminal B
UPDATE pgbench_accounts SET abalance = abalance + 1 WHERE aid = 1;     -- menggantung

-- Terminal C (monitor)
SELECT pid, state, wait_event_type, wait_event, pg_blocking_pids(pid) AS diblokir_oleh,
       now() - xact_start AS lama_transaksi, left(query, 60) AS query
FROM pg_stat_activity WHERE datname = 'toko' AND state <> 'idle';

SELECT pg_cancel_backend(<pid_B>);       -- batalkan query (halus)
SELECT pg_terminate_backend(<pid_A>);    -- putuskan sesi penyebab (lebih keras)
```

### Proteksi dari Sesi Nakal

```sql
ALTER DATABASE toko SET idle_in_transaction_session_timeout = '5min';
ALTER DATABASE toko SET statement_timeout = '30s';
ALTER DATABASE toko SET lock_timeout = '5s';
```

### Monitoring OS dan Prometheus (Opsional)

```bash
docker stats pg-latihan --no-stream
docker exec pg-latihan bash -c 'cat /proc/loadavg; free -m; df -h /var/lib/postgresql'

docker run -d --name pg-exporter --network host \
  -e DATA_SOURCE_NAME="postgresql://postgres:rahasia@localhost:5432/toko?sslmode=disable" \
  quay.io/prometheuscommunity/postgres-exporter
curl -s localhost:9187/metrics | grep -E '^pg_up|^pg_stat_database_xact_commit' | head
```

> `--network host` tidak berfungsi sama di Docker Desktop (macOS/Windows); gunakan jaringan Docker bersama (`--network pgnet`) dan nama container sebagai host.

### Analisis Log

```bash
docker exec pg-latihan psql -U postgres -c "ALTER SYSTEM SET log_min_duration_statement = '100ms';"
docker exec pg-latihan psql -U postgres -c "SELECT pg_reload_conf();"
docker exec pg-latihan psql -U postgres -d toko -c "SELECT count(*) FROM app.transaksi t1 CROSS JOIN generate_series(1,3);"
docker logs pg-latihan 2>&1 | grep 'duration:' | tail -5
```

### Monitoring Backup: check_pgbackrest (Opsional)

Lanjutan dari praktik pgBackRest di [Modul 14](14-backup-recovery-upgrade.md). Paket Debian bernama `check-pgbackrest` (membutuhkan pgBackRest versi baru):

```bash
docker exec -u root pg-latihan bash -c 'apt-get install -y -qq check-pgbackrest'

docker exec -u postgres pg-latihan check_pgbackrest --service=retention --stanza=toko --retention-full=1 --output=human
docker exec -u postgres pg-latihan check_pgbackrest --service=retention --stanza=toko --retention-full=5 --output=human
echo "kode keluar: $?"       # perhatikan: kode keluar 2 (CRITICAL) karena baru ada 1 full backup

docker exec -u postgres pg-latihan check_pgbackrest --service=archives --stanza=toko --output=human
docker exec -u postgres pg-latihan check_pgbackrest --list
```

Jika paket tidak tersedia di repositori Anda, ambil skripnya dari repositori proyek `check_pgbackrest` (Dalibo/pgstef).

### Otomasi: Shell, Python, dan Ansible

```bash
# Shell: simpan skrip 16.7 sebagai health_check.sh
chmod +x health_check.sh
PGPASSWORD=rahasia PGHOST=localhost ./health_check.sh; echo "kode keluar: $?"

# Jadwalkan tiap 5 menit dengan cron
( crontab -l 2>/dev/null; echo "*/5 * * * * PGPASSWORD=rahasia /home/user/health_check.sh >> /tmp/health.log 2>&1" ) | crontab -

# Python
pip install "psycopg[binary]"
python3 cek_dead_tuple.py     # simpan cuplikan Python 16.7 sebagai cek_dead_tuple.py

# Ansible (butuh host target; untuk uji lokal pakai localhost)
ansible-galaxy collection install community.postgresql
ansible-playbook -i "localhost," -c local --ask-become-pass postgres.yml --check    # --check = dry run
```

Jalankan playbook dua kali tanpa `--check` dan perhatikan bahwa putaran kedua melaporkan `changed=0`. Itulah idempotensi.

## Latihan

1. Jalankan `pgbench` selama 60 detik, lalu gunakan `pg_stat_statements` untuk menemukan tiga query dengan `total_exec_time` terbesar. Mana yang lebih layak dioptimalkan: query dengan `mean_exec_time` terbesar atau `total_exec_time` terbesar? Jelaskan.
2. Buat skenario *blocking* dua sesi, temukan penyebabnya dengan `pg_blocking_pids()`, lalu selesaikan tanpa me-restart server. Apa perbedaan `pg_cancel_backend` dan `pg_terminate_backend`?
3. Buat satu dashboard mini (query SQL saja) berisi: koneksi aktif/idle/idle-in-transaction, cache hit ratio, 5 tabel dengan dead tuple terbanyak, dan lag replikasi. Jadikan satu skrip `health_check.sh` yang dijalankan cron.
4. Susun *runbook* troubleshooting: "disk server database hampir penuh". Urutkan langkah pemeriksaan (WAL, slot replikasi, log, bloat, tabel temporer) dan tindakan aman untuk masing-masing.
5. Terapkan metode **USE** dan **RED** pada layanan Anda: tentukan minimal tiga metrik + ambang alert untuk masing-masing metode.
6. Rancang rencana belajar lanjutan Anda berdasarkan roadmap: topik mana yang ingin diperdalam berikutnya (mis. tuning lanjutan, Patroni, internals, kontribusi)? Tentukan proyek kecil untuk masing-masing.
7. Tulis playbook Ansible (atau state Salt/modul Puppet) yang memasang PostgreSQL, membuat database dan role, serta mengatur `pg_hba.conf`. Jalankan dua kali dan buktikan hasilnya idempoten.
8. Pasang `check_pgbackrest` dan `check_pgactivity`, lalu pasang ambang *warning/critical* yang masuk akal untuk retensi backup dan jumlah koneksi. Bagaimana Anda menghubungkannya ke Zabbix atau Nagios?
9. Tinjau satu patch yang sedang berjalan di CommitFest (cukup baca thread dan diskusinya) dan ringkas masalah yang ingin diselesaikan patch tersebut serta keberatan reviewer.

Selamat — Anda telah menuntaskan seluruh modul. Kembali ke [Daftar Isi](README.md) untuk meninjau ulang modul mana pun yang perlu diperdalam.

---

[← Modul 15: Replication, High Availability & Connection Pooling](15-replication-ha-pooling.md) · [Daftar Isi](README.md#daftar-isi)
