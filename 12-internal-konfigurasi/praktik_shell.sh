#!/usr/bin/env bash
# praktik_shell.sh : perintah shell pada Praktik Modul 12, disalin dari modul.
# 'ps' mungkin tidak ada di image; gunakan 'docker top pg-latihan' sebagai gantinya.
set -uo pipefail

echo '=== Proses dan Memori ==='
docker exec pg-latihan ps aux | grep postgres | head -20     # lihat proses postmaster dan background

echo '=== Layout File dan Ukuran ==='
docker exec pg-latihan bash -c 'ls $PGDATA && ls $PGDATA/pg_wal | head'
