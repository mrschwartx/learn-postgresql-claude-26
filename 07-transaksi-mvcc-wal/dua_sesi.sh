#!/usr/bin/env bash
# dua_sesi.sh : mengotomatiskan skenario DUA SESI psql (Latihan 2, 3, 4 dan bagian Locking).
# Dua proses psql dijalankan bersamaan di container pg-latihan; perintah dikirim bergantian
# lewat named pipe. Sinkronisasi memakai jeda waktu (sleep), jadi cukup sederhana, bukan
# harness uji yang kokoh. Bila hasilnya aneh, jalankan ulang atau lakukan manual di dua terminal.
#
# Pemakaian:  ./dua_sesi.sh isolasi | rr_konflik | locking | deadlock | antrean
set -uo pipefail

NAMA=pg-latihan
T=""
PID_A=""; PID_B=""

psql_utama() { docker exec -i "$NAMA" psql -U postgres -d toko -X -q "$@"; }

buka() {
  T="$(mktemp -d)"            # folder baru untuk setiap pasangan sesi
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

reset_rekening() {
  psql_utama <<'SQL'
CREATE TABLE IF NOT EXISTS rekening (id int PRIMARY KEY, pemilik text, saldo numeric(12,2) CHECK (saldo >= 0));
TRUNCATE rekening;
INSERT INTO rekening VALUES (1,'Andi',500001), (2,'Budi',100000);
SQL
}

isolasi() {
  for tingkat in "READ COMMITTED" "REPEATABLE READ"; do
    echo; echo "############ Sesi A memakai: $tingkat ############"
    reset_rekening
    buka
    a "BEGIN ISOLATION LEVEL $tingkat;"
    a "SELECT saldo FROM rekening WHERE id = 1;"
    b "UPDATE rekening SET saldo = 999 WHERE id = 1;"
    a "SELECT saldo FROM rekening WHERE id = 1;"
    a "COMMIT;"
    a "SELECT saldo FROM rekening WHERE id = 1;"
    tutup
  done
}

rr_konflik() {
  reset_rekening
  buka
  a "BEGIN ISOLATION LEVEL REPEATABLE READ;"
  a "SELECT saldo FROM rekening WHERE id = 1;"
  b "UPDATE rekening SET saldo = 999 WHERE id = 1;"
  a "UPDATE rekening SET saldo = saldo + 1 WHERE id = 1;"     # baris sudah diubah transaksi lain
  a "ROLLBACK;"
  tutup
}

locking() {
  reset_rekening
  buka
  a "BEGIN;"
  a "SELECT * FROM rekening WHERE id = 1 FOR UPDATE;"
  b "SET lock_timeout = '3s';"
  b "UPDATE rekening SET saldo = 1 WHERE id = 1;" 0.7       # akan menunggu (blocked)
  echo "--- dari sesi ketiga: siapa yang menunggu siapa? (sementara B masih menunggu)"
  psql_utama -c "SELECT pid, pg_blocking_pids(pid) AS diblokir_oleh, wait_event_type, wait_event,
                        left(query, 45) AS query
                 FROM pg_stat_activity
                 WHERE datname = 'toko' AND wait_event_type = 'Lock';"
  sleep 3                                                    # tunggu lock_timeout B habis
  b "SELECT * FROM rekening ORDER BY id FOR UPDATE SKIP LOCKED LIMIT 1;"
  a "ROLLBACK;"
  tutup
}

deadlock() {
  reset_rekening
  buka
  a "BEGIN;"
  b "BEGIN;"
  a "UPDATE rekening SET saldo = saldo + 1 WHERE id = 1;"
  b "UPDATE rekening SET saldo = saldo + 1 WHERE id = 2;"
  a "UPDATE rekening SET saldo = saldo + 1 WHERE id = 2;" 0.5   # A menunggu B
  b "UPDATE rekening SET saldo = saldo + 1 WHERE id = 1;" 3.5   # B menunggu A -> deadlock
  a "COMMIT;"
  b "COMMIT;"                                                  # pada sesi korban: berubah menjadi ROLLBACK
  tutup
  psql_utama -c "SELECT * FROM rekening ORDER BY id;"
}

antrean() {
  psql_utama <<'SQL'
DROP TABLE IF EXISTS tugas;
CREATE TABLE tugas (
    id     int GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    status text NOT NULL DEFAULT 'baru' CHECK (status IN ('baru','diproses','selesai'))
);
INSERT INTO tugas (status) SELECT 'baru' FROM generate_series(1, 5);
SQL
  AMBIL="UPDATE tugas SET status = 'diproses' WHERE id = (SELECT id FROM tugas WHERE status = 'baru' ORDER BY id FOR UPDATE SKIP LOCKED LIMIT 1) RETURNING id;"
  echo; echo "############ Dengan SKIP LOCKED ############"
  buka
  a "BEGIN;"
  b "BEGIN;"
  a "$AMBIL"
  b "$AMBIL"
  a "COMMIT;"
  b "COMMIT;"
  tutup
  psql_utama -c "SELECT id, status FROM tugas ORDER BY id;"

  echo; echo "############ Tanpa SKIP LOCKED (B menunggu A, lalu kena lock_timeout) ############"
  psql_utama -c "UPDATE tugas SET status = 'baru';"
  NAIF="UPDATE tugas SET status = 'diproses' WHERE id = (SELECT id FROM tugas WHERE status = 'baru' ORDER BY id FOR UPDATE LIMIT 1) RETURNING id;"
  buka
  a "BEGIN;"
  a "$NAIF"
  b "SET lock_timeout = '2s';"
  b "$NAIF" 3
  a "ROLLBACK;"
  tutup
}

case "${1:-}" in
  isolasi|rr_konflik|locking|deadlock|antrean) "$1" ;;
  *) echo "Pemakaian: $0 isolasi|rr_konflik|locking|deadlock|antrean"; exit 1 ;;
esac
