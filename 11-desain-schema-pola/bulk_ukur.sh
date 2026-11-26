#!/usr/bin/env bash
# bulk_ukur.sh : Latihan 5, membandingkan cara memuat N baris ke PostgreSQL (container pg-latihan).
#   (a)  N pernyataan INSERT terpisah, masing-masing transaksi sendiri (autocommit)
#   (a2) N pernyataan INSERT di dalam SATU transaksi (BEGIN ... COMMIT)       [pembanding tambahan]
#   (b)  SATU INSERT multi-baris
#   (c)  COPY dari STDIN
# Pemakaian:  ./bulk_ukur.sh [N]      (default N = 100000; (a) bisa memakan puluhan detik sampai menit)
# Belum dijalankan di lingkungan saya. Waktu = jam dinding sisi klien, termasuk overhead docker exec.
set -euo pipefail
N="${1:-100000}"
NAMA=pg-latihan
psql_q() { docker exec -i "$NAMA" psql -U postgres -d toko -q -v ON_ERROR_STOP=1 "$@"; }

psql_q <<'SQL'
CREATE SCHEMA IF NOT EXISTS latihan11;
DROP TABLE IF EXISTS latihan11.muat_a, latihan11.muat_a2, latihan11.muat_b, latihan11.muat_c;
CREATE TABLE latihan11.muat_a  (id int, isi text);
CREATE TABLE latihan11.muat_a2 (id int, isi text);
CREATE TABLE latihan11.muat_b  (id int, isi text);
CREATE TABLE latihan11.muat_c  (id int, isi text);
SQL

ukur() {   # ukur <label> <perintah...>
  local label="$1"; shift
  local t0 t1
  t0=$(date +%s.%N)
  "$@"
  t1=$(date +%s.%N)
  awk -v l="$label" -v a="$t0" -v b="$t1" -v n="$N" 'BEGIN { d = b - a; printf "%-34s %8.2f detik  (%d baris/detik)\n", l, d, n / d }'
}

a()  { seq 1 "$N" | awk '{ printf "INSERT INTO latihan11.muat_a VALUES (%d, '\''baris %d'\'');\n", $1, $1 }' | psql_q; }
a2() { { echo "BEGIN;"; seq 1 "$N" | awk '{ printf "INSERT INTO latihan11.muat_a2 VALUES (%d, '\''baris %d'\'');\n", $1, $1 }'; echo "COMMIT;"; } | psql_q; }
b()  { { echo "INSERT INTO latihan11.muat_b VALUES"; seq 1 "$N" | awk -v n="$N" '{ printf "(%d, '\''baris %d'\'')%s\n", $1, $1, ($1 < n ? "," : ";") }'; } | psql_q; }
c()  { seq 1 "$N" | awk '{ printf "%d,baris %d\n", $1, $1 }' | psql_q -c "\\copy latihan11.muat_c FROM STDIN WITH (FORMAT csv)"; }

echo "Memuat $N baris dengan empat cara:"
ukur "(a)  INSERT terpisah (autocommit)" a
ukur "(a2) INSERT dalam satu transaksi" a2
ukur "(b)  satu INSERT multi-baris"     b
ukur "(c)  COPY"                        c

psql_q -c "SELECT 'muat_a' t, count(*) FROM latihan11.muat_a UNION ALL SELECT 'muat_a2', count(*) FROM latihan11.muat_a2 UNION ALL SELECT 'muat_b', count(*) FROM latihan11.muat_b UNION ALL SELECT 'muat_c', count(*) FROM latihan11.muat_c;"
