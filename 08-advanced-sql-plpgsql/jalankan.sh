#!/usr/bin/env bash
# jalankan.sh : Modul 8 ke container pg-latihan (database toko).
# Pemakaian:  ./jalankan.sh praktik | latihan | bersih
#   bersih = bersih.sql lalu pulihkan.sql (hapus objek modul 8, kembalikan stok/harga)
set -euo pipefail
NAMA=pg-latihan
DIR="$(cd "$(dirname "$0")" && pwd)"
psql_file() { docker exec -i "$NAMA" psql -U postgres -d toko -f - < "$DIR/$1"; }
case "${1:-}" in
  praktik) psql_file praktik.sql ;;
  latihan) psql_file latihan.sql ;;
  bersih)  psql_file bersih.sql; psql_file pulihkan.sql ;;
  *) echo "Pemakaian: $0 praktik|latihan|bersih"; exit 1 ;;
esac
