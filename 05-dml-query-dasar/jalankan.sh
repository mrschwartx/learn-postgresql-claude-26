#!/usr/bin/env bash
# jalankan.sh : menjalankan berkas SQL Modul 5 ke container pg-latihan (database toko).
# Pemakaian:  ./jalankan.sh seed | praktik | latihan | semua
set -euo pipefail
NAMA=pg-latihan
DIR="$(cd "$(dirname "$0")" && pwd)"
psql_file() { docker exec -i "$NAMA" psql -U postgres -d toko -f - < "$DIR/$1"; }
case "${1:-}" in
  seed)    psql_file seed.sql ;;
  praktik) psql_file praktik.sql ;;
  latihan) psql_file latihan.sql ;;
  semua)   psql_file seed.sql; psql_file praktik.sql; psql_file latihan.sql ;;
  *) echo "Pemakaian: $0 seed|praktik|latihan|semua"; exit 1 ;;
esac
