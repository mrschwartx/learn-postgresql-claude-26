#!/usr/bin/env bash
# jalankan.sh : menjalankan berkas SQL Modul 4 ke container pg-latihan (database toko).
# Pemakaian:  ./jalankan.sh reset | praktik | perpustakaan | latihan | semua
set -euo pipefail
NAMA=pg-latihan
DIR="$(cd "$(dirname "$0")" && pwd)"

psql_file() {   # psql_file <berkas.sql> [database]
  docker exec -i "$NAMA" psql -U postgres -d "${2:-toko}" -f - < "$DIR/$1"
}

case "${1:-}" in
  reset)        psql_file reset.sql ;;
  praktik)      psql_file praktik.sql ;;
  perpustakaan) psql_file perpustakaan.sql ;;
  latihan)      psql_file latihan.sql ;;
  semua)        psql_file reset.sql; psql_file praktik.sql; psql_file perpustakaan.sql; psql_file latihan.sql ;;
  *) echo "Pemakaian: $0 reset|praktik|perpustakaan|latihan|semua"; exit 1 ;;
esac
