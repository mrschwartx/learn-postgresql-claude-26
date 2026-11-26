#!/usr/bin/env bash
# log_lambat.sh : Latihan 4. Aktifkan log_min_duration_statement = 100ms, jalankan query lambat,
# temukan barisnya di log container, lalu kembalikan pengaturan.
# Belum diuji di PostgreSQL. Log image resmi menuju stderr sehingga terbaca lewat 'docker logs'.
set -uo pipefail
NAMA=pg-latihan
psql_q() { docker exec -i "$NAMA" psql -U postgres -d toko -X -q "$@"; }

psql_q -c "ALTER SYSTEM SET log_min_duration_statement = '100ms';"
psql_q -c "SELECT pg_reload_conf();"
sleep 1
psql_q -At -c "SHOW log_min_duration_statement;"

echo "--- query cepat (tidak boleh tercatat) dan dua query lambat (harus tercatat)"
psql_q -c "SELECT 1;"
psql_q -c "SELECT pg_sleep(0.3);"
psql_q -c "SELECT count(*) FROM app.transaksi WHERE email LIKE '%er5000%';" || true

sleep 1
echo "--- baris di log (cari 'duration:')"
docker logs "$NAMA" 2>&1 | grep "duration:" | tail -5

psql_q -c "ALTER SYSTEM RESET log_min_duration_statement;"
psql_q -c "SELECT pg_reload_conf();"
