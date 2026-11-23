#!/usr/bin/env bash
# praktik.sh : seluruh Praktik Modul 3 dengan Docker.
# Pemakaian:  ./praktik.sh mulai | eksplorasi | service | bersih | semua
set -euo pipefail

NAMA=pg-latihan
VOL=pgdata
IMAGE=postgres:18
export PGPASSWORD_LATIHAN=rahasia          # hanya untuk latihan, jangan dipakai di produksi
DIR="$(cd "$(dirname "$0")" && pwd)"

tunggu_siap() {
  # Penting: cek lewat TCP (-h 127.0.0.1). Saat inisialisasi pertama, image menjalankan
  # server sementara yang HANYA di socket Unix; cek tanpa -h bisa lolos terlalu cepat.
  for _ in $(seq 1 60); do
    if docker exec "$NAMA" pg_isready -h 127.0.0.1 -U postgres -q; then return 0; fi
    sleep 1
  done
  echo "PostgreSQL tidak siap dalam 60 detik. Lihat: docker logs $NAMA" >&2
  return 1
}

mulai() {
  docker run --name "$NAMA" -e POSTGRES_PASSWORD="$PGPASSWORD_LATIHAN" \
    -p 5432:5432 -v "$VOL":/var/lib/postgresql -d "$IMAGE"
  tunggu_siap
  docker logs "$NAMA" 2>&1 | tail -5          # cari "ready to accept connections"
}

eksplorasi() {
  docker exec -i "$NAMA" psql -U postgres -f - < "$DIR/eksplorasi.sql"
}

service() {
  psqlc() { docker exec "$NAMA" psql -U postgres -At -c "$1"; }
  echo "Waktu start awal      : $(psqlc 'SELECT pg_postmaster_start_time();')"
  echo ">> reload (setara systemctl reload)"
  psqlc 'SELECT pg_reload_conf();'
  echo "Waktu start sesudah reload  : $(psqlc 'SELECT pg_postmaster_start_time();')   <- TIDAK berubah"
  echo ">> restart (setara systemctl restart)"
  docker restart "$NAMA" >/dev/null
  tunggu_siap
  echo "Waktu start sesudah restart : $(psqlc 'SELECT pg_postmaster_start_time();')   <- BERUBAH"
}

bersih() {
  docker rm -f "$NAMA" 2>/dev/null || true
  docker volume rm "$VOL" 2>/dev/null || true
}

case "${1:-}" in
  mulai) mulai ;;
  eksplorasi) eksplorasi ;;
  service) service ;;
  bersih) bersih ;;
  semua) mulai; eksplorasi; service ;;
  *) echo "Pemakaian: $0 mulai|eksplorasi|service|bersih|semua"; exit 1 ;;
esac
