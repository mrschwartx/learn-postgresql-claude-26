#!/usr/bin/env bash
# jalankan.sh : Modul 9 ke container pg-latihan (database toko).
# Pemakaian:  ./jalankan.sh praktik | latihan | salinan | bersih
#   salinan = hapus hanya salinan uji (transaksi tetap ada, dibutuhkan Modul 10)
#   bersih  = hapus SEMUA termasuk transaksi
set -euo pipefail
NAMA=pg-latihan
DIR="$(cd "$(dirname "$0")" && pwd)"
psql_file() { docker exec -i "$NAMA" psql -U postgres -d toko -f - < "$DIR/$1"; }
case "${1:-}" in
  praktik) psql_file praktik.sql ;;
  latihan) psql_file latihan.sql ;;
  salinan) psql_file bersih_salinan.sql ;;
  bersih)  psql_file bersih.sql ;;
  *) echo "Pemakaian: $0 praktik|latihan|salinan|bersih"; exit 1 ;;
esac
