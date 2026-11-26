#!/usr/bin/env bash
# dua_sesi.sh : Latihan 3. Transaksi yang menggantung vs VACUUM, dalam TIGA variasi:
#   rc    : BEGIN (READ COMMITTED); SELECT ...;       tanpa commit   <- persis seperti teks latihan
#   rr    : BEGIN ISOLATION LEVEL REPEATABLE READ; SELECT ...;       <- menahan snapshot
#   tulis : BEGIN; UPDATE satu baris;                                <- memegang ID transaksi (xid)
# Dua proses psql berjalan bersamaan lewat named pipe; sinkronisasi dengan sleep (sederhana, bukan harness kokoh).
# BELUM diuji di PostgreSQL. Pemakaian:  ./dua_sesi.sh rc | rr | tulis
set -uo pipefail
NAMA=pg-latihan
T=""; PID_A=""; PID_B=""
psql_utama() { docker exec -i "$NAMA" psql -U postgres -d toko -X -q "$@"; }

buka() {
  T="$(mktemp -d)"
  mkfifo "$T/a.in" "$T/b.in"
  docker exec -i "$NAMA" psql -U postgres -d toko -X -a < "$T/a.in" > "$T/a.out" 2>&1 & PID_A=$!
  docker exec -i "$NAMA" psql -U postgres -d toko -X -a < "$T/b.in" > "$T/b.out" 2>&1 & PID_B=$!
  exec 3> "$T/a.in" 4> "$T/b.in"
}
a() { echo "[A] $1"; printf '%s\n' "$1" >&3; sleep "${2:-1}"; }
b() { echo "[B] $1"; printf '%s\n' "$1" >&4; sleep "${2:-1}"; }
tutup() {
  exec 3>&- 4>&-
  wait "$PID_A" "$PID_B" 2>/dev/null
  echo; echo "=================== Keluaran sesi A ==================="; cat "$T/a.out"
  echo;  echo "=================== Keluaran sesi B ==================="; cat "$T/b.out"
  rm -rf "$T"
}

siapkan() {
  psql_utama <<'SQL'
CREATE SCHEMA IF NOT EXISTS app;
DROP TABLE IF EXISTS app.uji_horizon;
CREATE TABLE app.uji_horizon (id int PRIMARY KEY, v text) WITH (autovacuum_enabled = off);
INSERT INTO app.uji_horizon SELECT g, 'awal' FROM generate_series(1, 100000) g;
VACUUM app.uji_horizon;
SQL
}

periksa_xmin() {
  echo "--- sesi ketiga: apakah sesi A yang menggantung menahan horizon? (backend_xmin / backend_xid)"
  psql_utama -c "SELECT pid, state, backend_xid, backend_xmin FROM pg_stat_activity
                 WHERE datname = 'toko' AND state = 'idle in transaction';"
}

skenario="${1:-}"
case "$skenario" in rc|rr|tulis) ;; *) echo "Pemakaian: $0 rc|rr|tulis"; exit 1 ;; esac
siapkan
buka
case "$skenario" in
  rc)    a "BEGIN;";                                        a "SELECT count(*) FROM app.uji_horizon;" ;;
  rr)    a "BEGIN ISOLATION LEVEL REPEATABLE READ;";        a "SELECT count(*) FROM app.uji_horizon;" ;;
  tulis) a "BEGIN;";                                        a "UPDATE app.uji_horizon SET v = 'a' WHERE id = 1;" ;;
esac
b "UPDATE app.uji_horizon SET v = 'baru';" 2          # menciptakan ±100.000 dead tuple SETELAH sesi A menggantung
periksa_xmin
b "VACUUM (VERBOSE) app.uji_horizon;" 3                # lihat 'removed' dan 'dead but not yet removable'
a "ROLLBACK;"
b "VACUUM (VERBOSE) app.uji_horizon;" 3                # sesudah sesi A selesai
tutup
