#!/usr/bin/env bash
# jalankan.sh : Modul 12 ke container pg-latihan (database toko).
# Pemakaian:  ./jalankan.sh praktik | shell | latihan | sesi | vacuum <rc|rr|tulis> | log | bersih
set -euo pipefail
NAMA=pg-latihan
DIR="$(cd "$(dirname "$0")" && pwd)"
psql_file() { docker exec -i "$NAMA" psql -U postgres -d toko -f - < "$DIR/$1"; }
case "${1:-}" in
  praktik) psql_file praktik.sql ;;
  shell)   "$DIR/praktik_shell.sh" ;;
  latihan) psql_file latihan.sql ;;
  sesi)    "$DIR/sesi_banyak.sh" "${2:-3}" ;;
  vacuum)  "$DIR/dua_sesi.sh" "${2:?isi: rc|rr|tulis}" ;;
  log)     "$DIR/log_lambat.sh" ;;
  bersih)  psql_file bersih.sql ;;
  *) echo "Pemakaian: $0 praktik|shell|latihan|sesi [N]|vacuum <rc|rr|tulis>|log|bersih"; exit 1 ;;
esac
