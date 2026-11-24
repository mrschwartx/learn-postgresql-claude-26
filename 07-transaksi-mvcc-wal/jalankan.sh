#!/usr/bin/env bash
# jalankan.sh : Modul 7 ke container pg-latihan (database toko).
# Pemakaian:  ./jalankan.sh praktik | latihan | sesi <isolasi|rr_konflik|locking|deadlock|antrean> | bersih
set -euo pipefail
NAMA=pg-latihan
DIR="$(cd "$(dirname "$0")" && pwd)"
psql_file() { docker exec -i "$NAMA" psql -U postgres -d toko -f - < "$DIR/$1"; }
case "${1:-}" in
  praktik) psql_file praktik.sql ;;
  latihan) psql_file latihan.sql ;;
  sesi)    "$DIR/dua_sesi.sh" "${2:?isi: isolasi|rr_konflik|locking|deadlock|antrean}" ;;
  bersih)  psql_file bersih.sql ;;
  *) echo "Pemakaian: $0 praktik|latihan|sesi <skenario>|bersih"; exit 1 ;;
esac
