#!/usr/bin/env bash
# latihan.sh : bantu menjalankan Latihan 1-5 Modul 3. Jalankan berurutan (2-4 butuh database toko dari Latihan 1).
# Pemakaian:  ./latihan.sh 1 | 2 | 3 | 4 | 5 | bersih
set -euo pipefail

NAMA=pg-latihan
VOL=pgdata
PASS=rahasia

siap() {  # siap <nama-container>
  for _ in $(seq 1 60); do
    docker exec "$1" pg_isready -h 127.0.0.1 -U postgres -q && return 0
    sleep 1
  done
  echo "Container $1 tidak siap. docker logs $1" >&2; return 1
}
psqlc() { docker exec "$NAMA" psql -U postgres "$@"; }
jalankan18() {
  docker run --name "$NAMA" -e POSTGRES_PASSWORD="$PASS" -p 5432:5432 \
    -v "$VOL":/var/lib/postgresql -d postgres:18 >/dev/null
  siap "$NAMA"
}

latihan1() {   # volume bertahan walau container dihapus
  docker rm -f "$NAMA" 2>/dev/null || true
  jalankan18
  echo "SELECT 'CREATE DATABASE toko' WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname='toko') \\gexec" \
    | docker exec -i "$NAMA" psql -U postgres >/dev/null
  echo "--- sebelum hapus container:"; psqlc -At -c "SELECT datname FROM pg_database WHERE datname='toko'"
  docker rm -f "$NAMA"
  jalankan18
  echo "--- sesudah container dibuat ulang dengan volume yang sama:"
  psqlc -At -c "SELECT datname FROM pg_database WHERE datname='toko'"
}

latihan2() {   # \d vs \d+ dan \dt+
  psqlc -d toko -c "CREATE TABLE IF NOT EXISTS contoh (id int PRIMARY KEY, nama text NOT NULL)"
  echo "--- \\d contoh";  psqlc -d toko -c '\d contoh'
  echo "--- \\d+ contoh"; psqlc -d toko -c '\d+ contoh'
  echo "--- \\dt+";       psqlc -d toko -c '\dt+'
}

latihan3() {   # context parameter, reload vs restart
  psqlc -d toko -c "SELECT name, context FROM pg_settings
                    WHERE name IN ('work_mem','log_min_duration_statement','autovacuum_naptime',
                                   'shared_buffers','max_connections') ORDER BY context, name;"
  echo ">> ubah parameter yang cukup reload"
  psqlc -c "ALTER SYSTEM SET log_min_duration_statement = '100ms'"
  psqlc -c "SELECT pg_reload_conf()"
  sleep 1
  psqlc -c "SHOW log_min_duration_statement"
  echo ">> ubah parameter yang WAJIB restart"
  psqlc -c "ALTER SYSTEM SET shared_buffers = '256MB'"
  psqlc -c "SELECT pg_reload_conf()"
  sleep 1
  psqlc -c "SELECT name, setting, pending_restart FROM pg_settings WHERE name='shared_buffers'"
  echo "   (pending_restart = t: nilai baru belum aktif sebelum restart)"
  docker restart "$NAMA" >/dev/null; siap "$NAMA"
  psqlc -c "SHOW shared_buffers"
  echo ">> kembalikan ke default"
  psqlc -c "ALTER SYSTEM RESET log_min_duration_statement"
  psqlc -c "ALTER SYSTEM RESET shared_buffers"
  docker restart "$NAMA" >/dev/null; siap "$NAMA"
}

latihan4() {   # koneksi dari host dengan URI
  command -v psql >/dev/null || { echo "psql lokal tidak ada. Pasang postgresql-client, atau pakai tool GUI."; exit 1; }
  # PGPASSWORD hanya untuk latihan; produksi: ~/.pgpass
  PGPASSWORD="$PASS" psql "postgresql://postgres@localhost:5432/toko" -c '\conninfo'
}

latihan5() {   # dua versi mayor berdampingan
  docker rm -f pg17 pg18 2>/dev/null || true
  # PG 17: volume di /var/lib/postgresql/data. PG 18: volume di /var/lib/postgresql.
  docker run --name pg17 -e POSTGRES_PASSWORD="$PASS" -p 5433:5432 -v pg17data:/var/lib/postgresql/data -d postgres:17 >/dev/null
  docker run --name pg18 -e POSTGRES_PASSWORD="$PASS" -p 5434:5432 -v pg18data:/var/lib/postgresql      -d postgres:18 >/dev/null
  siap pg17; siap pg18
  for c in pg17 pg18; do
    echo "=== $c"
    docker exec "$c" psql -U postgres -At -c "SELECT version()"
    docker exec "$c" psql -U postgres -At -c "SHOW data_directory"
    docker exec "$c" sh -c 'cat "$(psql -U postgres -At -c "SHOW data_directory")/PG_VERSION"'
  done
  echo
  echo "=== Opsional: paksa PG 18 memakai data directory PG 17 (seharusnya GAGAL start)"
  docker stop pg17 >/dev/null
  docker run --rm -e POSTGRES_PASSWORD="$PASS" -e PGDATA=/var/lib/postgresql/data \
    -v pg17data:/var/lib/postgresql/data postgres:18 2>&1 | tail -6 || true
}

bersih() {
  docker rm -f "$NAMA" pg17 pg18 2>/dev/null || true
  docker volume rm "$VOL" pg17data pg18data 2>/dev/null || true
}

case "${1:-}" in
  1) latihan1 ;; 2) latihan2 ;; 3) latihan3 ;; 4) latihan4 ;; 5) latihan5 ;;
  bersih) bersih ;;
  *) echo "Pemakaian: $0 1|2|3|4|5|bersih"; exit 1 ;;
esac
