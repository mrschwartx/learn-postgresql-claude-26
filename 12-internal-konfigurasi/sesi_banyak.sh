#!/usr/bin/env bash
# sesi_banyak.sh : Latihan 1. Membuka N sesi psql bersamaan dan melihat pg_stat_activity + proses OS.
# Pemakaian:  ./sesi_banyak.sh [N]     (default 3). N besar (mis. di atas 100) akan menabrak max_connections
# dan memakan memori container: lakukan hanya bila Anda memang ingin melihat "too many clients already".
set -uo pipefail
N="${1:-3}"
NAMA=pg-latihan
psql_q() { docker exec -i "$NAMA" psql -U postgres -d toko -X -q "$@"; }

echo "Sebelum: jumlah client backend"
psql_q -At -c "SELECT count(*) FROM pg_stat_activity WHERE backend_type = 'client backend';"

for i in $(seq 1 "$N"); do
  docker exec -d "$NAMA" psql -U postgres -d toko -X -q -c "SELECT pg_sleep(25);" >/dev/null 2>&1 || true
done
sleep 3

echo "Sesudah membuka $N sesi (satu lagi adalah sesi pemeriksa ini sendiri):"
psql_q -c "SELECT backend_type, count(*) FROM pg_stat_activity GROUP BY 1 ORDER BY 1;"
psql_q -c "SELECT pid, state, left(query, 30) AS query FROM pg_stat_activity WHERE backend_type = 'client backend' ORDER BY pid;"
echo "Proses OS di container (tiap client backend = satu proses terpisah):"
docker top "$NAMA" 2>/dev/null | grep -E "postgres" | head -30 || true
echo "Menunggu sesi selesai (±25 detik)..."
sleep 25
