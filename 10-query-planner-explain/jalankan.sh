#!/usr/bin/env bash
# jalankan.sh : Modul 10 ke container pg-latihan (database toko).
# Pemakaian:  ./jalankan.sh praktik | latihan | salinan
set -euo pipefail
NAMA=pg-latihan
DIR="$(cd "$(dirname "$0")" && pwd)"
psql_file() { docker exec -i "$NAMA" psql -U postgres -d toko -f - < "$DIR/$1"; }
case "${1:-}" in
  praktik) psql_file praktik.sql ;;
  latihan) psql_file latihan.sql ;;
  salinan) psql_file bersih_salinan.sql ;;
  *) echo "Pemakaian: $0 praktik|latihan|salinan"; exit 1 ;;
esac
