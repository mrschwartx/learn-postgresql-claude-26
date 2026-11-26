# verifikasi.py : Modul 12 hampir seluruhnya tentang perilaku server PostgreSQL yang TIDAK bisa dijalankan
# di sini. Yang dikerjakan skrip ini hanya hitungan dan model, dengan label yang jelas:
#   A. [hitungan]  ukuran tabel dari tata letak halaman PostgreSQL (asumsi dinyatakan di bawah)
#   B. [hitungan]  ambang autovacuum
#   C. [hitungan]  usulan shared_buffers dan batas work_mem (Latihan 5)
#   D. [SIMULASI]  model sederhana "xmin horizon": kapan dead tuple boleh dibuang (Latihan 3).
#                  PREMIS MODEL (belum diuji di PostgreSQL): transaksi READ COMMITTED yang hanya membaca
#                  dan sedang idle tidak memegang snapshot maupun xid.
#   E. [SQLite]    arah biaya fsync (Latihan 6), bukan angka PostgreSQL
# TIDAK diuji: pg_stat_activity, proses OS, ukuran file nyata, VACUUM, log, konfigurasi.
import math
import os
import sqlite3
import tempfile
import time

TOTAL = 0


def cek(label, aktual, harapan, tag=""):
    global TOTAL
    TOTAL += 1
    ok = aktual == harapan
    print(f"[{'OK' if ok else 'GAGAL'}]{tag} {label}\n       aktual   : {aktual}\n       harapan  : {harapan}")
    assert ok, label


def cek_benar(label, kondisi, rincian, tag=""):
    global TOTAL
    TOTAL += 1
    print(f"[{'OK' if kondisi else 'GAGAL'}]{tag} {label}\n       {rincian}")
    assert kondisi, label


def judul(t):
    print("\n" + "=" * 78 + f"\n{t}\n" + "=" * 78)


# ------------------------------------------------------------------ A
judul("A. Ukuran tabel uji_bloat dari tata letak halaman [hitungan]")
BLOK, HDR_HALAMAN, ITEM_ID, HDR_TUPLE = 8192, 24, 4, 23


def maxalign(n):                      # MAXALIGN = 8 byte pada mesin 64-bit umum
    return (n + 7) // 8 * 8


def tuple_per_halaman(panjang_data_setelah_header):
    t_hoff = maxalign(HDR_TUPLE)      # tanpa NULL: tidak ada null bitmap, header tetap 24 byte
    t_len = t_hoff + panjang_data_setelah_header
    per_tuple = maxalign(t_len) + ITEM_ID
    return (BLOK - HDR_HALAMAN) // per_tuple, t_len, maxalign(t_len), per_tuple


# kolom: id integer (4 byte, rata 4) + isi text 100 karakter (header pendek 1 byte + 100 = 101 byte, tanpa penyelarasan)
data = 4 + (1 + 100)
n_per_hal, t_len, t_align, per_tuple = tuple_per_halaman(data)
print(f"t_len={t_len}, setelah MAXALIGN={t_align}, plus item pointer={per_tuple}, tuple per halaman={n_per_hal}")
cek("tuple per halaman", n_per_hal, 58, " [hitungan]")


def pretty(byte):                      # meniru aturan pg_size_pretty (satuan 1024; naik satuan bila >= 10240 satuan bawah)
    nilai, satuan = byte, "bytes"
    for s in ("kB", "MB", "GB", "TB"):
        if abs(nilai) >= 10240:
            nilai = round(nilai / 1024)
            satuan = s
        else:
            break
    return f"{nilai} {satuan}"


for baris, label in [(200_000, "Praktik (200.000 baris)"), (1_000_000, "Latihan 2 (1 juta baris)")]:
    hal = math.ceil(baris / n_per_hal)
    print(f"{label}: {hal:,} halaman = {hal * BLOK:,} byte = {pretty(hal * BLOK)}")
hal_praktik, hal_latihan = math.ceil(200_000 / n_per_hal), math.ceil(1_000_000 / n_per_hal)
cek("halaman dan ukuran Praktik", (hal_praktik, pretty(hal_praktik * BLOK)), (3449, "27 MB"), " [hitungan]")
cek("halaman dan ukuran Latihan 2 (awal)", (hal_latihan, pretty(hal_latihan * BLOK)), (17242, "135 MB"), " [hitungan]")
bebas_per_halaman = (BLOK - HDR_HALAMAN) - n_per_hal * per_tuple
cek_benar("halaman penuh hanya menyisakan ruang lebih kecil dari satu tuple, sehingga UPDATE tidak bisa memakai halaman yang sama (bukan HOT) dan versi baru menambah halaman",
          bebas_per_halaman < per_tuple, f"sisa {bebas_per_halaman} byte < {per_tuple} byte per tuple", " [hitungan]")
hal_sesudah_update = hal_latihan * 2
print(f"sesudah UPDATE seluruh baris: ≈ {hal_sesudah_update:,} halaman ≈ {pretty(hal_sesudah_update * BLOK)} (≈ 2x)")
cek("ukuran setelah UPDATE seluruh baris ≈ 2x", pretty(hal_sesudah_update * BLOK), "269 MB", " [hitungan]")
cek_benar("setelah VACUUM, 1 juta tuple baru muat persis di halaman yang dibebaskan, sehingga UPDATE kedua hampir tidak menambah file",
          hal_latihan * n_per_hal >= 1_000_000, f"{hal_latihan:,} halaman x {n_per_hal} = {hal_latihan * n_per_hal:,} >= 1.000.000", " [hitungan]")

# ------------------------------------------------------------------ B
judul("B. Ambang autovacuum [hitungan]")
cek("VACUUM untuk uji_bloat 200.000 baris (default 50 + 0,2 x baris)", 50 + 0.2 * 200_000, 40050.0, " [hitungan]")
cek("VACUUM untuk tabel 1 juta baris", 50 + 0.2 * 1_000_000, 200050.0, " [hitungan]")
cek("VACUUM transaksi 1,2 juta baris, default", 50 + 0.2 * 1_200_000, 240050.0, " [hitungan]")
cek("VACUUM transaksi 1,2 juta baris, scale_factor = 0,02 (Praktik)", 50 + 0.02 * 1_200_000, 24050.0, " [hitungan]")
cek("ANALYZE transaksi 1,2 juta baris, scale_factor = 0,01", 50 + 0.01 * 1_200_000, 12050.0, " [hitungan]")
cek_benar("UPDATE 200.000 baris pada Praktik (>40.050) memicu autovacuum dalam ±1 menit bila tidak dimatikan; itu bisa mengubah n_dead_tup sebelum Anda melihatnya",
          200_000 > 40_050, "200.000 > 40.050", " [hitungan]")

# ------------------------------------------------------------------ C
judul("C. Latihan 5: shared_buffers dan batas work_mem untuk 16 GB RAM [hitungan]")
RAM_MIB = 16 * 1024
sb = 0.25 * RAM_MIB
cek("usulan awal shared_buffers = 25% RAM (MiB)", sb, 4096.0, " [hitungan]")
cadangan = 0.25 * RAM_MIB       # ASUMSI: OS, page cache, maintenance_work_mem, autovacuum, overhead per backend
tersedia = RAM_MIB - sb - cadangan
KONEKSI, NODE = 100, 2


def work_mem_maks(pengali):
    return tersedia / (KONEKSI * NODE * pengali)


hasil = {"dasar": work_mem_maks(1), "hash x2 (hash_mem_multiplier)": work_mem_maks(2),
         "paralel 3 proses": work_mem_maks(3), "hash x2 dan paralel 3": work_mem_maks(6)}
for k, v in hasil.items():
    print(f"  {k:<32}: {v:6.2f} MiB")
cek("memori tersedia untuk work_mem (MiB)", tersedia, 8192.0, " [hitungan]")
cek("batas teoretis terburuk, kasus dasar (MiB)", round(hasil["dasar"], 2), 40.96, " [hitungan]")
cek("dengan hash_mem_multiplier = 2", round(hasil["hash x2 (hash_mem_multiplier)"], 2), 20.48, " [hitungan]")
cek("dengan paralel (1 leader + 2 worker)", round(hasil["paralel 3 proses"], 2), 13.65, " [hitungan]")
cek("keduanya", round(hasil["hash x2 dan paralel 3"], 2), 6.83, " [hitungan]")

# ------------------------------------------------------------------ D
judul("D. Model xmin horizon: kapan dead tuple boleh dibuang [SIMULASI]")


def removable(dead_deleter_xids, sesi_menggantung, xid_berikutnya):
    """Dead tuple (dihapus oleh xid d yang sudah commit) boleh dibuang bila d < horizon.
    horizon = min(xmin snapshot, xid) dari semua sesi yang masih menahan sesuatu; bila tidak ada: xid_berikutnya."""
    tahan = [s["snapshot_xmin"] for s in sesi_menggantung if s.get("snapshot_xmin") is not None]
    tahan += [s["xid"] for s in sesi_menggantung if s.get("xid") is not None]
    horizon = min(tahan) if tahan else xid_berikutnya
    return sum(1 for d in dead_deleter_xids if d < horizon), horizon


# Sesi A menggantung pada xid 100. Sesi B men-UPDATE 1000 baris dengan xid 105 (commit), sehingga 1000 dead tuple
dead = [105] * 1000
skenario = [
    ("tidak ada sesi lain menggantung", [], 106, 1000),
    ("A: READ COMMITTED, hanya SELECT, idle (tanpa snapshot, tanpa xid) [premis]", [{"snapshot_xmin": None, "xid": None}], 106, 1000),
    ("A: REPEATABLE READ, snapshot diambil SEBELUM update (xmin=100)", [{"snapshot_xmin": 100, "xid": None}], 106, 0),
    ("A: transaksi menulis, memegang xid=100", [{"snapshot_xmin": None, "xid": 100}], 106, 0),
    ("A: REPEATABLE READ, snapshot diambil SESUDAH update (xmin=106)", [{"snapshot_xmin": 106, "xid": None}], 106, 1000),
]
for label, sesi, nxt, harapan in skenario:
    n, hz = removable(dead, sesi, nxt)
    cek(f"dead tuple yang bisa dibuang: {label}", n, harapan, " [SIMULASI]")
print("[CATATAN] Skenario kedua bergantung pada premis perilaku snapshot READ COMMITTED yang BELUM saya uji di PostgreSQL.\n"
      "          dua_sesi.sh membuktikannya langsung: lihat backend_xmin/backend_xid dan baris 'dead but not yet removable'.")

# ------------------------------------------------------------------ E
judul("E. Latihan 6: arah biaya fsync [SQLite]")
N = 3000
d = tempfile.mkdtemp()


def jalan(mode):
    c = sqlite3.connect(os.path.join(d, f"{mode}.db"), isolation_level=None)
    c.execute(f"PRAGMA synchronous = {mode}")
    c.execute("CREATE TABLE t (id INT, isi TEXT)")
    t0 = time.perf_counter()
    for i in range(N):
        c.execute("INSERT INTO t VALUES (?, 'x')", (i,))               # satu commit per baris
    return time.perf_counter() - t0


w_full, w_off = jalan("FULL"), jalan("OFF")
print(f"{N:,} commit di SQLite (detik): synchronous=FULL {w_full:.3f}, synchronous=OFF {w_off:.4f}, {w_full / w_off:.0f}x")
cek_benar("tanpa fsync, penulisan jauh lebih cepat (arah). Harganya: tidak ada jaminan data sampai ke media saat listrik/OS mati",
          w_full > 5 * w_off, f"{w_full / w_off:.0f}x lebih cepat", " [SQLite]")

print(f"\nSemua {TOTAL} pemeriksaan sesuai harapan.")
