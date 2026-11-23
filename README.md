# Course PostgreSQL: Basic to Advance

> **Catatan sumber:** Kurikulum ini disusun mengikuti **roadmap PostgreSQL DBA dari roadmap.sh** ([roadmap.sh/postgresql-dba](https://roadmap.sh/postgresql-dba)) sebagaimana tercantum pada berkas `postgresql-dba.pdf` yang Anda kirim — mulai dari *Introduction*, *Installation and Setup*, *Learn SQL*, *Advanced Topics*, *Infrastructure Skills*, *Application Skills*, hingga *Get Involved in Development* — dan dilengkapi **dokumentasi resmi PostgreSQL** ([postgresql.org/docs](https://www.postgresql.org/docs/current/)). Modul ditulis untuk **PostgreSQL 16–18**; SQL pada modul 4–13 telah dijalankan ulang pada PostgreSQL 16. PostgreSQL 19 baru dirilis pada November 2026 — sebagian besar materi tetap berlaku, tetapi selalu periksa *release notes* versi yang Anda pakai.

PostgreSQL adalah **jangkar** seri course Anda: Docker/Kubernetes/EKS menjawab "bagaimana menjalankan aplikasi", Terraform "bagaimana menyediakan infrastrukturnya", Kafka "bagaimana data mengalir", Elasticsearch "bagaimana data dicari", Redis "bagaimana membuat semuanya cepat", Keycloak "siapa yang boleh akses" — PostgreSQL menjawab **"di mana data disimpan dengan benar dan dapat dipercaya"**. Dalam hampir setiap arsitektur, PostgreSQL adalah **sumber kebenaran (source of truth)** yang menopang semua komponen lain.

## Daftar Isi

| # | Modul |
|---|-------|
| 1 | [Pengenalan PostgreSQL](01-pengenalan.md) |
| 2 | [Konsep Relasional & Object Model](02-konsep-relasional.md) |
| 3 | [Instalasi, Setup & psql](03-instalasi-setup.md) |
| 4 | [DDL: Schema, Tabel & Tipe Data](04-ddl-tipe-data.md) |
| 5 | [DML: Query, Filter & Modifikasi Data](05-dml-query-dasar.md) |
| 6 | [Join, Subquery, Grouping, CTE & Set Operations](06-join-subquery-cte.md) |
| 7 | [Transaksi, ACID, MVCC & WAL](07-transaksi-mvcc-wal.md) |
| 8 | [Advanced SQL & PL/pgSQL](08-advanced-sql-plpgsql.md) |
| 9 | [Index & Use Case-nya](09-index.md) |
| 10 | [Query Planner & EXPLAIN](10-query-planner-explain.md) |
| 11 | [Desain Schema & Pola Aplikasi](11-desain-schema-pola.md) |
| 12 | [Arsitektur Internal & Konfigurasi](12-internal-konfigurasi.md) |
| 13 | [Security](13-security.md) |
| 14 | [Backup, Recovery & Upgrade](14-backup-recovery-upgrade.md) |
| 15 | [Replication, High Availability & Connection Pooling](15-replication-ha-pooling.md) |
| 16 | [Monitoring, Troubleshooting & Operasi](16-monitoring-troubleshooting.md) |

## Pemetaan ke Roadmap roadmap.sh

| Cabang Roadmap | Topik | Modul |
|---|---|---|
| **Introduction** | RDBMS, benefit & limitation, PostgreSQL vs RDBMS/NoSQL | [1](01-pengenalan.md) |
| **Basic RDBMS Concepts / Object Model** | Domains, attributes, tuples, relations, constraints, NULL, tables, schemas, databases | [2](02-konsep-relasional.md) |
| **High Level Database Concepts** | ACID, MVCC, transactions, WAL, query processing | [7](07-transaksi-mvcc-wal.md) |
| **Installation and Setup** | Docker, package managers, `psql`, cloud, `systemd`, `pg_ctl`, `pg_ctlcluster` | [3](03-instalasi-setup.md) |
| **Learn SQL — DDL** | Schemas, tables, data types | [4](04-ddl-tipe-data.md) |
| **Learn SQL — DML** | Querying, filtering, modifying, `COPY` | [5](05-dml-query-dasar.md) |
| **Learn SQL — lanjutan** | Joins, subqueries, grouping, CTE, lateral join, set operations | [6](06-join-subquery-cte.md) |
| **Advanced SQL** | Window & aggregate functions, recursive CTE, PL/pgSQL, procedures, triggers | [8](08-advanced-sql-plpgsql.md) |
| **Indexes and their Usecases** | B-Tree, Hash, GiST, SP-GiST, GIN, BRIN | [9](09-index.md) |
| **Query Analysis & SQL Optimization** | `EXPLAIN`, depesz, PEV2/dalibo, Tensor, query planner | [10](10-query-planner-explain.md) |
| **Application Skills** | Normalization, partitioning, sharding, queues (`SKIP LOCKED`, PgQ), migrations (pola/anti-pola, Flyway, Liquibase, Alembic, dll.), bulk loading, OLTP/OLAP/HTAP | [11](11-desain-schema-pola.md) |
| **Configuring / Low Level Internals** | Resource usage, vacuum, checkpoints, bgwriter, buffers, locks, physical storage, system catalog, per-user/db settings, storage parameters, extensions | [12](12-internal-konfigurasi.md) |
| **Security** | Object privileges, grant/revoke, default privileges, RLS, SELinux, roles, `pg_hba.conf`, SSL | [13](13-security.md) |
| **Infrastructure — Backup & Upgrade** | `pg_dump`, `pg_dumpall`, `pg_restore`, `pg_basebackup`, pgBackRest, Barman, WAL-G, `pg_probackup`, `pg_upgrade`, upgrade via logical replication, validasi backup (`pg_verifybackup`), anonymization (PostgreSQL Anonymizer) | [14](14-backup-recovery-upgrade.md) |
| **Infrastructure — Replication & HA** | Streaming/logical replication, Patroni (+ repmgr, pg_auto_failover), HAProxy, Keepalived, Consul/etcd, PgBouncer, Kubernetes (StatefulSet, Helm, CloudNativePG) | [15](15-replication-ha-pooling.md) |
| **Troubleshooting & Monitoring** | OS tools, profiling (gdb, strace, eBPF, perf), pgBadger, pgCluu, `pg_stat_*`, USE/RED/Golden Signals, Prometheus, Zabbix, temBoard, pgcenter, check_pgactivity, check_pgbackrest | [16](16-monitoring-troubleshooting.md) |
| **Learn to Automate** | Shell scripts, Python, Ansible, Salt, Puppet, Chef (dengan contoh untuk masing-masing) | [16](16-monitoring-troubleshooting.md) |
| **Get Involved in Development** | Mailing lists, reviewing & writing patches | [16](16-monitoring-troubleshooting.md) |

> **Catatan penambahan:** bagian berlabel **(Opsional)** (pgBackRest, PostgreSQL Anonymizer, PgQ, Flyway, HAProxy, etcd/Consul, Kubernetes, SELinux, check_pgbackrest) membutuhkan paket, image, atau lingkungan tambahan. Nama paket dan versi image bisa berubah; cocokkan dengan dokumentasi resmi masing-masing alat bila ada perintah yang gagal.

## Cara Menggunakan Materi Ini

1. Ikuti urutan modul 1-16. Modul 4-6 (DDL dan DML) menjadi fondasi semua modul berikutnya, dan **Modul 7 (transaksi, MVCC, WAL)** adalah kunci untuk memahami modul 9-15.
2. Setiap modul berisi **Teori**, **Praktik** (perintah `psql` dan shell siap coba), dan **Latihan**.
3. Praktik memakai **Docker** (course Docker Anda) — cukup satu perintah untuk menjalankan PostgreSQL secara lokal, gratis sepenuhnya.
4. Modul 4-16 memakai database `toko` yang dibuat bertahap (pelanggan, produk, pesanan, item_pesanan) dengan data yang di-*seed* di Modul 5 dan tabel besar di Modul 9. **Kerjakan berurutan** agar contoh di modul berikutnya bisa dijalankan.
5. Course ini mengasumsikan Anda familiar dengan Docker dan command line, dan untuk Modul 15 akan menyinggung Kubernetes (course Kubernetes/EKS), Kafka (course Kafka), dan Redis/Elasticsearch sebagai pelengkap arsitektur.

## Prasyarat

- Familiar dengan Docker dan command line.
- Memahami konsep dasar tabel/spreadsheet akan sangat membantu.
- Tidak perlu pengalaman database sebelumnya.

## Sumber Referensi

- Dokumentasi resmi: https://www.postgresql.org/docs/current/
- Roadmap: https://roadmap.sh/postgresql-dba
- Release notes & versi didukung: https://www.postgresql.org/support/versioning/
- Wiki komunitas: https://wiki.postgresql.org/
- Visualisasi `EXPLAIN`: https://explain.dalibo.com/ · https://explain.depesz.com/

## Navigasi

Setiap modul punya tautan *Sebelumnya · Daftar Isi · Berikutnya* di atas dan di bawah, plus daftar isi modul itu sendiri.
