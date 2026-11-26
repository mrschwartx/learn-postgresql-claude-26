# verifikasi.py : verifikasi LOGIKA Modul 11 dengan SQLite dan Python. PostgreSQL TIDAK dipakai.
#
# Diuji: hitungan partisi pada Praktik; pagination (OFFSET vs keyset); normalisasi 3NF tanpa kehilangan
# data; EAV vs JSON; logika pembuat partisi harian; mesin status antrean (retry, backoff, timeout);
# arah biaya cara muat data; pola batch UPDATE.
# TIDAK bisa diuji: PARTITION BY, partition pruning, SKIP LOCKED/konkurensi, COPY, NOT VALID/VALIDATE,
# lock, Flyway, PgQ, hasil EXPLAIN PostgreSQL. Semua itu berlabel (diharapkan) di jawaban.
import datetime as dt
import os
import re
import sqlite3
import tempfile
import time
from pathlib import Path

DIR = Path(__file__).parent
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


LATIHAN = (DIR / "latihan.sql").read_text()

# ------------------------------------------------------------------ A
judul("A. Praktik Partitioning: jumlah baris per partisi [hitungan Python]")
awal = dt.datetime(2026, 10, 1)
batas_nov, batas_des = dt.datetime(2026, 11, 1), dt.datetime(2026, 12, 1)
cacah = {"log_2026_10": 0, "log_2026_11": 0, "log_default": 0}
for g in range(1, 80001):
    t = awal + dt.timedelta(minutes=g)
    if t < batas_nov:
        cacah["log_2026_10"] += 1
    elif t < batas_des:
        cacah["log_2026_11"] += 1
    else:
        cacah["log_default"] += 1
cek("baris per partisi (zona waktu sesi konsisten untuk data dan batas)", cacah,
    {"log_2026_10": 44639, "log_2026_11": 35361, "log_default": 0}, " [hitungan]")
cek_benar("baris pada 1 November 00:00 (g = 44.640) masuk partisi November (batas bawah inklusif)",
          awal + dt.timedelta(minutes=44640) == batas_nov, "tepat 2026-11-01 00:00 -> log_2026_11", " [hitungan]")

# ------------------------------------------------------------------ B
judul("B. Pagination: OFFSET vs keyset [SQLite]")
db = sqlite3.connect(":memory:", isolation_level=None)
db.execute("CREATE TABLE t (id INTEGER, x INT)")
db.executemany("INSERT INTO t VALUES (?, 0)", ((i * 2,) for i in range(1, 150001)))      # id genap 2..300000
rencana = lambda q: " | ".join(r[3] for r in db.execute("EXPLAIN QUERY PLAN " + q))
QO = "SELECT id FROM t ORDER BY id LIMIT 20 OFFSET 135000"
QK = "SELECT id FROM t WHERE id > 270000 ORDER BY id LIMIT 20"
r1, r2 = rencana(QO), rencana(QK)
cek_benar("TANPA index: keduanya harus mengurutkan (USE TEMP B-TREE), tidak ada yang 'cepat'",
          "TEMP B-TREE" in r1 and "TEMP B-TREE" in r2 and r1.startswith("SCAN") and r2.startswith("SCAN"), f"offset: {r1} || keyset: {r2}", " [SQLite]")
db.execute("CREATE INDEX i_id ON t (id)")
r1, r2 = rencana(QO), rencana(QK)
cek_benar("DENGAN index: keyset melompat (SEARCH), OFFSET tetap memindai (SCAN)",
          r2.startswith("SEARCH") and r1.startswith("SCAN") and "TEMP B-TREE" not in r1 + r2, f"offset: {r1} || keyset: {r2}", " [SQLite]")
cek("hasil halaman keyset sama dengan halaman OFFSET pada data statis",
    db.execute(QK).fetchall(), db.execute(QO).fetchall(), " [SQLite]")


def waktu(q, n=5):
    t0 = time.perf_counter()
    for _ in range(n):
        db.execute(q).fetchall()
    return (time.perf_counter() - t0) * 1000 / n


w_o, w_k = waktu(QO), waktu(QK)
print(f"waktu SQLite (ms/query): OFFSET {w_o:.3f}, keyset {w_k:.4f}, {w_o / w_k:.0f}x")
cek_benar("OFFSET besar jauh lebih lambat daripada keyset ber-index (arah)", w_o > 10 * w_k, f"{w_o / w_k:.0f}x", " [SQLite]")

d2 = sqlite3.connect(":memory:", isolation_level=None)
d2.execute("CREATE TABLE t (id INTEGER PRIMARY KEY)")
d2.executemany("INSERT INTO t VALUES (?)", ((i * 2,) for i in range(1, 1001)))
hal1 = [r[0] for r in d2.execute("SELECT id FROM t ORDER BY id LIMIT 20 OFFSET 0")]
d2.execute("INSERT INTO t VALUES (1)")                                           # baris baru muncul di awal antar permintaan
hal2_offset = [r[0] for r in d2.execute("SELECT id FROM t ORDER BY id LIMIT 20 OFFSET 20")]
hal2_keyset = [r[0] for r in d2.execute("SELECT id FROM t WHERE id > ? ORDER BY id LIMIT 20", (hal1[-1],))]
cek_benar("OFFSET: baris terakhir halaman 1 muncul LAGI di halaman 2 (hasil bergeser)", hal1[-1] == hal2_offset[0],
          f"hal1[-1]={hal1[-1]}, hal2_offset[0]={hal2_offset[0]}", " [SQLite]")
cek_benar("keyset: tidak ada duplikat, halaman 2 mulai tepat sesudah baris terakhir halaman 1",
          hal2_keyset[0] == hal1[-1] + 2 and not set(hal1) & set(hal2_keyset), f"hal2_keyset[0]={hal2_keyset[0]}", " [SQLite]")
# Keyset dengan dua kolom: (dibuat_pada, id) < (:t, :id)
d3 = sqlite3.connect(":memory:", isolation_level=None)
d3.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, dibuat TEXT)")
d3.executemany("INSERT INTO t VALUES (?, ?)", [(i, f"2026-01-{(i % 5) + 1:02d}") for i in range(1, 41)])   # banyak waktu yang sama
semua = [r for r in d3.execute("SELECT dibuat, id FROM t ORDER BY dibuat DESC, id DESC")]
terkumpul, kursor = [], None
while True:
    if kursor is None:
        baris = d3.execute("SELECT dibuat, id FROM t ORDER BY dibuat DESC, id DESC LIMIT 7").fetchall()
    else:
        baris = d3.execute("SELECT dibuat, id FROM t WHERE (dibuat, id) < (?, ?) ORDER BY dibuat DESC, id DESC LIMIT 7", kursor).fetchall()
    if not baris:
        break
    terkumpul += baris
    kursor = baris[-1]
cek("keyset (dibuat, id) menelusuri SEMUA baris tepat sekali walau banyak waktu yang sama", terkumpul, semua, " [SQLite]")

# ------------------------------------------------------------------ C
judul("C. Latihan 1: normalisasi 3NF tanpa kehilangan data [SQLite]")
d = sqlite3.connect(":memory:", isolation_level=None)
d.executescript("""
CREATE TABLE pesanan_lama (id INT PRIMARY KEY, pelanggan_nama TEXT, pelanggan_alamat TEXT, produk_nama TEXT, produk_harga NUMERIC, jumlah INT);
CREATE TABLE pelanggan (id INTEGER PRIMARY KEY, nama TEXT UNIQUE NOT NULL, alamat TEXT NOT NULL);
CREATE TABLE produk (id INTEGER PRIMARY KEY, nama TEXT UNIQUE NOT NULL, harga NUMERIC NOT NULL);
CREATE TABLE pesanan (id INT PRIMARY KEY, pelanggan_id INT NOT NULL REFERENCES pelanggan(id));
CREATE TABLE item_pesanan (pesanan_id INT, produk_id INT, jumlah INT, harga_satuan NUMERIC, PRIMARY KEY (pesanan_id, produk_id));
""")
m = re.search(r"INSERT INTO pesanan_lama VALUES(.*?);", LATIHAN, re.S)
d.execute("INSERT INTO pesanan_lama VALUES" + m.group(1))
fd1 = d.execute("SELECT count(*) FROM (SELECT pelanggan_nama FROM pesanan_lama GROUP BY 1 HAVING count(DISTINCT pelanggan_alamat) > 1)").fetchone()[0]
fd2 = d.execute("SELECT count(*) FROM (SELECT produk_nama FROM pesanan_lama GROUP BY 1 HAVING count(DISTINCT produk_harga) > 1)").fetchone()[0]
cek("dependensi pelanggan_nama -> pelanggan_alamat berlaku pada data contoh", fd1, 0)
cek("dependensi produk_nama -> produk_harga berlaku pada data contoh (harga sama di semua baris)", fd2, 0)
for stmt in re.findall(r"(INSERT INTO (?:pelanggan|produk|pesanan|item_pesanan) .*?;)\n", LATIHAN, re.S):
    d.execute(stmt)       # empat INSERT ... SELECT asli dari latihan.sql
n_tabel = {t: d.execute(f"SELECT count(*) FROM {t}").fetchone()[0] for t in ("pelanggan", "produk", "pesanan", "item_pesanan")}
cek("baris tiap tabel hasil normalisasi", n_tabel, {"pelanggan": 3, "produk": 3, "pesanan": 6, "item_pesanan": 6})
REK = """SELECT ps.id, c.nama, c.alamat, pr.nama, i.harga_satuan, i.jumlah FROM pesanan ps
         JOIN pelanggan c ON c.id = ps.pelanggan_id JOIN item_pesanan i ON i.pesanan_id = ps.id JOIN produk pr ON pr.id = i.produk_id"""
cek("rekonstruksi (join 4 tabel) EXCEPT tabel lama = kosong", d.execute(REK + " EXCEPT SELECT * FROM pesanan_lama").fetchall(), [])
cek("tabel lama EXCEPT rekonstruksi = kosong", d.execute("SELECT * FROM pesanan_lama EXCEPT " + REK).fetchall(), [])
d.execute("BEGIN")
lama = d.execute("UPDATE pesanan_lama SET produk_harga = 170000 WHERE produk_nama = 'Mouse'").rowcount
baru = d.execute("UPDATE produk SET harga = 170000 WHERE nama = 'Mouse'").rowcount
d.execute("ROLLBACK")
cek("anomali update: baris yang harus diubah (tabel lama vs tabel normal)", (lama, baru), (2, 1))

# ------------------------------------------------------------------ D
judul("D. Latihan 2: JSON hibrida vs EAV [SQLite JSON1]")
e = sqlite3.connect(":memory:", isolation_level=None)
e.executescript("""
CREATE TABLE tiket (id INTEGER PRIMARY KEY, jenis TEXT NOT NULL, judul TEXT NOT NULL, atribut TEXT NOT NULL DEFAULT '{}',
  CHECK (json_valid(atribut) AND json_type(atribut) = 'object'),
  CHECK (jenis <> 'bug' OR (json_extract(atribut,'$.versi') IS NOT NULL AND json_extract(atribut,'$.tingkat') IS NOT NULL)),
  CHECK (jenis <> 'tagihan' OR json_type(atribut,'$.jumlah') IN ('integer','real')));
CREATE TABLE tiket_eav (tiket_id INT, nama TEXT, nilai TEXT, PRIMARY KEY (tiket_id, nama));
""")
data = [("bug", "Login gagal", '{"versi": "2.3", "tingkat": "tinggi"}'), ("bug", "Teks terpotong", '{"versi": "2.4", "tingkat": "rendah"}'),
        ("bug", "Laporan lambat", '{"versi": "2.3", "tingkat": "rendah"}'), ("tagihan", "Tagihan ganda", '{"jumlah": 150000, "metode": "transfer"}'),
        ("tagihan", "Refund", '{"jumlah": 50000, "metode": "kartu"}'), ("permintaan_fitur", "Ekspor PDF", '{"modul": "laporan"}')]
e.executemany("INSERT INTO tiket (jenis, judul, atribut) VALUES (?,?,?)", data)
e.execute("INSERT INTO tiket_eav SELECT t.id, j.key, j.value FROM tiket t, json_each(t.atribut) j")
JSON_Q = "SELECT id FROM tiket WHERE jenis='bug' AND json_extract(atribut,'$.versi')='2.3' AND json_extract(atribut,'$.tingkat')='tinggi'"
EAV_Q = """SELECT t.id FROM tiket t JOIN tiket_eav a1 ON a1.tiket_id=t.id AND a1.nama='versi' AND a1.nilai='2.3'
           JOIN tiket_eav a2 ON a2.tiket_id=t.id AND a2.nama='tingkat' AND a2.nilai='tinggi' WHERE t.jenis='bug'"""
cek("EAV dan JSON memberi hasil yang sama untuk bug versi 2.3 tingkat tinggi", e.execute(EAV_Q).fetchall(), e.execute(JSON_Q).fetchall())
cek("banyak baris EAV vs 1 baris per tiket (6 tiket, 11 pasangan atribut: 3x2 + 2x2 + 1)",
    (e.execute("SELECT count(*) FROM tiket").fetchone()[0], e.execute("SELECT count(*) FROM tiket_eav").fetchone()[0]), (6, 11))
for sql, label in [("INSERT INTO tiket (jenis, judul, atribut) VALUES ('bug','Tanpa versi','{\"tingkat\":\"tinggi\"}')", "bug tanpa versi"),
                   ("INSERT INTO tiket (jenis, judul, atribut) VALUES ('tagihan','Salah tipe','{\"jumlah\":\"abc\"}')", "jumlah bukan angka")]:
    try:
        e.execute(sql); hasil = "lolos"
    except sqlite3.IntegrityError:
        hasil = "ditolak"
    cek(f"JSON + CHECK menolak: {label}", hasil, "ditolak")
e.execute("INSERT INTO tiket_eav VALUES (3, 'jumlah', 'abc')")
cek_benar("EAV menerima nilai salah tipe tanpa protes (semua nilai teks, tanpa tipe dan constraint)", True, "INSERT nilai 'abc' pada atribut jumlah berhasil")
print("[CATATAN] SQLite diam-diam mengubah CAST('abc' AS NUMERIC) menjadi 0, jadi error cast PostgreSQL pada EAV tidak bisa dibuktikan di sini:",
      e.execute("SELECT CAST('abc' AS NUMERIC)").fetchone()[0])

# ------------------------------------------------------------------ E
judul("E. Latihan 3: logika partisi harian [hitungan Python]")
cnt = {}
for g in range(1, 100001):
    detik = (g - 1) * 2.592
    hari = int(detik // 86400)
    cnt[hari] = cnt.get(hari, 0) + 1
cek("100.000 baris selama 3 hari penuh: baris per hari", [cnt[0], cnt[1], cnt[2]], [33334, 33333, 33333], " [hitungan]")
cek_benar("tidak ada baris yang jatuh di luar 3 partisi (tidak butuh partisi DEFAULT)", set(cnt) == {0, 1, 2} and (100000 - 1) * 2.592 < 3 * 86400,
          f"detik terakhir = {(100000 - 1) * 2.592:.3f} < 259200", " [hitungan]")


def partisi(hari):    # port logika buat_partisi_sensor
    return f"sensor_{hari:%Y%m%d}", hari.isoformat(), (hari + dt.timedelta(days=1)).isoformat()


hari_list = [dt.date(2026, 12, 1) + dt.timedelta(days=i) for i in range(10)]
batas = [partisi(h) for h in hari_list]
cek_benar("partisi harian bersambung tanpa celah dan tanpa tumpang tindih (batas atas = batas bawah berikutnya)",
          all(batas[i][2] == batas[i + 1][1] for i in range(len(batas) - 1)), f"{batas[0]} ... {batas[-1]}", " [hitungan]")
cek("nama partisi untuk 2026-12-04", partisi(dt.date(2026, 12, 4))[0], "sensor_20261204", " [hitungan]")
cek("pemanggilan ulang idempoten (CREATE TABLE IF NOT EXISTS): himpunan nama tidak bertambah",
    len({partisi(h)[0] for h in hari_list + hari_list}), len(hari_list), " [hitungan]")

# ------------------------------------------------------------------ F
judul("F. Latihan 4: mesin status antrean (retry, backoff, timeout) [SQLite]")
q = sqlite3.connect(":memory:", isolation_level=None)
q.executescript("""CREATE TABLE antrean2 (id INTEGER PRIMARY KEY, payload TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'menunggu'
  CHECK (status IN ('menunggu','diproses','selesai','gagal')), percobaan INT NOT NULL DEFAULT 0, maks_percobaan INT NOT NULL DEFAULT 3,
  mulai INT, jalankan_setelah INT NOT NULL DEFAULT 0, pesan_error TEXT);""")
JAM = [0]
ambil = lambda: q.execute("""UPDATE antrean2 SET status='diproses', mulai=?, percobaan=percobaan+1 WHERE id = (
    SELECT id FROM antrean2 WHERE status='menunggu' AND jalankan_setelah <= ? ORDER BY jalankan_setelah, id LIMIT 1) RETURNING id, payload, percobaan""", (JAM[0], JAM[0])).fetchone()
selesai = lambda i: q.execute("UPDATE antrean2 SET status='selesai', pesan_error=NULL WHERE id=? AND status='diproses'", (i,))
gagal = lambda i, tunda=0: q.execute("""UPDATE antrean2 SET status = CASE WHEN percobaan >= maks_percobaan THEN 'gagal' ELSE 'menunggu' END,
    pesan_error='error simulasi', jalankan_setelah=? + ? * percobaan WHERE id=? AND status='diproses'""", (JAM[0], tunda, i))
q.executemany("INSERT INTO antrean2 (payload) VALUES (?)", [("sukses",), ("gagal-sekali",), ("selalu-gagal",)])
while (t := ambil()):
    i, p, perc = t
    if p == "selalu-gagal" or (p == "gagal-sekali" and perc == 1):
        gagal(i)
    else:
        selesai(i)
cek("status akhir dan jumlah percobaan",
    q.execute("SELECT payload, status, percobaan FROM antrean2 ORDER BY id").fetchall(),
    [("sukses", "selesai", 1), ("gagal-sekali", "selesai", 2), ("selalu-gagal", "gagal", 3)], " [PADANAN]")
q.execute("DELETE FROM antrean2")
q.execute("INSERT INTO antrean2 (payload) VALUES ('backoff')")
JAM[0] = 100
i, _, _ = ambil()
gagal(i, tunda=30)                      # tunda linear: 30 x percobaan(1)
cek_benar("dengan backoff, tugas tidak bisa diambil sebelum waktunya", ambil() is None, "pada jam 100 tidak ada tugas", " [PADANAN]")
JAM[0] = 129
cek_benar("... masih belum pada jam 129", ambil() is None, "jalankan_setelah = 130", " [PADANAN]")
JAM[0] = 130
cek("... bisa diambil pada jam 130 sebagai percobaan ke-2", (lambda r: (r[1], r[2]))(ambil()), ("backoff", 2), " [PADANAN]")
q.execute("DELETE FROM antrean2")
q.execute("INSERT INTO antrean2 (payload, status, percobaan, mulai) VALUES ('macet','diproses',1,0), ('macet-terakhir','diproses',3,0), ('baru-mulai','diproses',1,590)")
JAM[0] = 600
q.execute("""UPDATE antrean2 SET status = CASE WHEN percobaan >= maks_percobaan THEN 'gagal' ELSE 'menunggu' END, pesan_error='melebihi batas waktu'
             WHERE status='diproses' AND mulai < ? - 300""", (JAM[0],))
cek("visibility timeout (batas 300): macet kembali ke antrean, yang sudah 3x gagal, yang baru mulai tidak disentuh",
    q.execute("SELECT payload, status FROM antrean2 ORDER BY id").fetchall(),
    [("macet", "menunggu"), ("macet-terakhir", "gagal"), ("baru-mulai", "diproses")], " [PADANAN]")
print("[CATATAN] FOR UPDATE SKIP LOCKED (konkurensi antar worker) TIDAK bisa diuji di SQLite. Lihat dua_sesi.sh antrean di Modul 7.")

# ------------------------------------------------------------------ G
judul("G. Latihan 5: biaya cara muat data (arah, SQLite file) [SQLite]")
N = 20000
tmp = tempfile.mkdtemp()


def baru_db(nama):
    c = sqlite3.connect(os.path.join(tmp, nama), isolation_level=None)
    c.execute("PRAGMA synchronous = FULL")
    c.execute("CREATE TABLE t (id INT, isi TEXT)")
    return c


c1 = baru_db("a.db")
t0 = time.perf_counter()
for i in range(N):
    c1.execute("INSERT INTO t VALUES (?, ?)", (i, f"baris {i}"))              # autocommit: satu transaksi per baris
w_a = time.perf_counter() - t0
c2 = baru_db("b.db")
t0 = time.perf_counter()
c2.execute("BEGIN")
for i in range(N):
    c2.execute("INSERT INTO t VALUES (?, ?)", (i, f"baris {i}"))
c2.execute("COMMIT")
w_a2 = time.perf_counter() - t0
c3 = baru_db("c.db")
t0 = time.perf_counter()
c3.execute("BEGIN")
c3.executemany("INSERT INTO t VALUES (?, ?)", ((i, f"baris {i}") for i in range(N)))
c3.execute("COMMIT")
w_c = time.perf_counter() - t0
print(f"{N:,} baris di SQLite (detik): satu transaksi per baris {w_a:.2f}; semua dalam satu transaksi {w_a2:.3f}; executemany {w_c:.3f}")
cek_benar("commit per baris jauh lebih lambat daripada satu transaksi (arah)", w_a > 3 * w_a2, f"{w_a / w_a2:.0f}x", " [SQLite]")
cek("ketiga cara menghasilkan jumlah baris yang sama",
    [c.execute("SELECT count(*) FROM t").fetchone()[0] for c in (c1, c2, c3)], [N, N, N], " [SQLite]")

# ------------------------------------------------------------------ H
judul("H. Latihan 9: UPDATE bertahap (batch) vs satu UPDATE besar [SQLite]")
h = sqlite3.connect(":memory:", isolation_level=None)
h.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, merek TEXT)")
h.executemany("INSERT INTO t (id) VALUES (?)", ((i,) for i in range(1, 25001)))
ukuran, batch, diubah = 10000, 0, []
while True:
    h.execute("BEGIN")
    n = h.execute("UPDATE t SET merek='Generik' WHERE id IN (SELECT id FROM t WHERE merek IS NULL LIMIT ?)", (ukuran,)).rowcount
    h.execute("COMMIT")                                                         # commit per batch memendekkan lock dan transaksi
    if n == 0:
        break
    batch += 1
    diubah.append(n)
cek("25.000 baris dengan batch 10.000: ukuran tiap batch", diubah, [10000, 10000, 5000])
cek("tidak ada baris yang tersisa NULL", h.execute("SELECT count(*) FROM t WHERE merek IS NULL").fetchone()[0], 0)

print(f"\nSemua {TOTAL} pemeriksaan sesuai harapan.")
