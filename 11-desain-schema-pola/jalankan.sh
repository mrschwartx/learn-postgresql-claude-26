#!/usr/bin/env bash
# jalankan.sh : Modul 11 ke container pg-latihan (database toko).
# Pemakaian:  ./jalankan.sh praktik | latihan | pgq | bulk [N] | bersih
set -euo pipefail
NAMA=pg-latihan
DIR="$(cd "$(dirname "$0")" && pwd)"
psql_file() { docker exec -i "$NAMA" psql -U postgres -d toko -f - < "$DIR/$1"; }
case "${1:-}" in
  praktik) psql_file praktik.sql ;;
  latihan) psql_file latihan.sql ;;
  pgq)     psql_file pgq_opsional.sql ;;
  bulk)    "$DIR/bulk_ukur.sh" "${2:-100000}" ;;
  bersih)  psql_file bersih.sql ;;
  *) echo "Pemakaian: $0 praktik|latihan|pgq|bulk [N]|bersih"; exit 1 ;;
esac
