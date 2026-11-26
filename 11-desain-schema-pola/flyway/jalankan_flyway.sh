#!/usr/bin/env bash
# jalankan_flyway.sh : perintah Flyway dari modul, dibungkus. BELUM diuji di lingkungan saya
# (butuh Docker, jaringan, dan image flyway/flyway).
# Pemakaian:  ./jalankan_flyway.sh jaringan | migrate | info | riwayat | bersih
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
URL="jdbc:postgresql://pg-latihan:5432/toko"
fw() { docker run --rm --network migrasi-net -v "$DIR/sql:/flyway/sql" flyway/flyway \
         -url="$URL" -user=postgres -password=rahasia "$@"; }
case "${1:-}" in
  jaringan) docker network create migrasi-net; docker network connect migrasi-net pg-latihan ;;
  migrate)  fw -baselineOnMigrate=true -baselineVersion=0 migrate ;;
  info)     fw info ;;
  riwayat)  docker exec pg-latihan psql -U postgres -d toko -c "SELECT version, description, success FROM flyway_schema_history;" ;;
  bersih)   docker network disconnect migrasi-net pg-latihan; docker network rm migrasi-net ;;
  *) echo "Pemakaian: $0 jaringan|migrate|info|riwayat|bersih"; exit 1 ;;
esac
