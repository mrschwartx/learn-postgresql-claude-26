# verifikasi_sqlite.py
# Memverifikasi KONSEP index Modul 9 dengan SQLite (EXPLAIN QUERY PLAN) dan simulasi Python.
#
# PENTING: ini planner SQLite, BUKAN PostgreSQL. Yang terbukti hanyalah konsepnya (leftmost
# prefix, partial/expression/covering index, urutan sort dari index). Semua yang khas
# PostgreSQL (Bitmap Scan, GIN, BRIN, hash index, trigram, ukuran index, EXPLAIN ANALYZE,
# waktu eksekusi) TIDAK bisa diuji di sini dan berlabel (diharapkan) di jawaban.
# Angka waktu SQLite di bawah hanya menunjukkan ARAH (index mempercepat baca, memperlambat tulis).
import random
import sqlite3
import time

TOTAL = 0
random.seed(20261124)


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


N = 300_000
STATUS = ["baru", "dibayar", "dikirim", "selesai", "batal"]
# Rumus data meniru Praktik Modul 9: (random()*10000)::int + 1, (ARRAY[...])[(random()*4)::int + 1]
rows = [(g, round(random.random() * 10000) + 1, STATUS[round(random.random() * 4)],
         round(random.random() * 1_000_000), 1.7e9 + random.random() * 31_536_000, f"user{g}@contoh.com")
        for g in range(1, N + 1)]


def baru():
    db = sqlite3.connect(":memory:")
    db.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, pelanggan_id INT, status TEXT, total INT, "
               "dibuat_pada REAL, email TEXT)")
    db.executemany("INSERT INTO t VALUES (?,?,?,?,?,?)", rows)
    return db


def rencana(db, sql):
    return " | ".join(r[3] for r in db.execute("EXPLAIN QUERY PLAN " + sql))


judul("A. Distribusi data hasil rumus modul (mengapa ukuran partial index = ±12,5%)")
db = baru()
dist = dict(db.execute("SELECT status, count(*) FROM t GROUP BY status").fetchall())
persen = {k: round(100 * v / N, 1) for k, v in sorted(dist.items())}
print("persentase per status:", persen)
cek_benar("'baru' dan 'batal' ±12,5%; tiga status lain ±25% (akibat pembulatan ::int)",
          abs(persen["baru"] - 12.5) < 0.6 and abs(persen["batal"] - 12.5) < 0.6
          and all(abs(persen[s] - 25) < 0.8 for s in ("dibayar", "dikirim", "selesai")), str(persen))
mn, mx, rata = db.execute("SELECT min(pelanggan_id), max(pelanggan_id), count(*)*1.0/count(DISTINCT pelanggan_id) FROM t").fetchone()
cek_benar("pelanggan_id berkisar 1..10001 (10001 muncul sangat jarang), rata-rata baris per pelanggan = N/10000",
          mn == 1 and mx in (10000, 10001) and 25 < rata < 35, f"min={mn} maks={mx} rata-rata baris/pelanggan={rata:.1f} (untuk 1 juta baris: ±100)")

judul("B. Sebelum dan sesudah index (rencana + arah waktu)")
Q = "SELECT * FROM t WHERE pelanggan_id = 4242"
cek("tanpa index: pemindaian seluruh tabel", rencana(db, Q), "SCAN t", " [SQLite]")
db.execute("CREATE INDEX i_pel ON t (pelanggan_id)")
cek("dengan index: pencarian lewat index", rencana(db, Q), "SEARCH t USING INDEX i_pel (pelanggan_id=?)", " [SQLite]")

db2 = baru()
def waktu_baca(d, n=20):
    t0 = time.perf_counter()
    for i in range(n):
        d.execute("SELECT sum(total) FROM t WHERE pelanggan_id = ?", ((i * 37) % 10000 + 1,)).fetchone()
    return (time.perf_counter() - t0) * 1000 / n
tanpa = min(waktu_baca(db2) for _ in range(3))
dengan = min(waktu_baca(db) for _ in range(3))
print(f"waktu baca SQLite (ms/query): tanpa index {tanpa:.3f}, dengan index {dengan:.3f}, {tanpa/dengan:.0f}x lebih cepat")
cek_benar("index mempercepat pencarian selektif (arah, bukan angka PostgreSQL)", tanpa / dengan > 5, f"rasio {tanpa/dengan:.0f}x", " [SQLite]")


def waktu_insert(dengan_index):
    d = sqlite3.connect(":memory:")
    d.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, pelanggan_id INT, status TEXT, total INT, dibuat_pada REAL, email TEXT)")
    if dengan_index:
        d.execute("CREATE INDEX i ON t (pelanggan_id)")
    t0 = time.perf_counter()
    d.executemany("INSERT INTO t VALUES (?,?,?,?,?,?)", rows[:100_000])
    return (time.perf_counter() - t0) * 1000
ins_tanpa = min(waktu_insert(False) for _ in range(3))
ins_dengan = min(waktu_insert(True) for _ in range(3))
print(f"waktu INSERT 100.000 baris SQLite (ms): tanpa index {ins_tanpa:.0f}, dengan index {ins_dengan:.0f}, {ins_dengan/ins_tanpa:.2f}x lebih lambat")
cek_benar("index memperlambat INSERT (arah)", ins_dengan > ins_tanpa, f"rasio {ins_dengan/ins_tanpa:.2f}x", " [SQLite]")

judul("C. Latihan 2: urutan kolom index komposit dan ORDER BY")
QO = "SELECT * FROM t WHERE pelanggan_id = 5 ORDER BY dibuat_pada DESC LIMIT 10"
d = baru()
d.execute("CREATE INDEX ic ON t (pelanggan_id, dibuat_pada DESC)")
r1 = rencana(d, QO)
cek("(pelanggan_id, dibuat_pada): SEARCH, tanpa langkah sort tambahan", r1, "SEARCH t USING INDEX ic (pelanggan_id=?)", " [SQLite]")
assert "TEMP B-TREE" not in r1
d = baru()
d.execute("CREATE INDEX id_ ON t (dibuat_pada, pelanggan_id)")
r2 = rencana(d, QO)
cek("(dibuat_pada, pelanggan_id): tidak ada SEARCH; seluruh index dipindai berurutan lalu disaring", r2,
    "SCAN t USING INDEX id_", " [SQLite]")
cek("leftmost prefix: WHERE pelanggan_id = 5 saja pada index (dibuat_pada, pelanggan_id)",
    rencana(d, "SELECT * FROM t WHERE pelanggan_id = 5"), "SCAN t", " [SQLite]")

judul("D. Latihan 3: partial index")
d = baru()
d.execute("CREATE INDEX ip ON t (dibuat_pada) WHERE status = 'baru'")
d.execute("CREATE INDEX ipenuh ON t (dibuat_pada)")
cek("status='baru' memakai index (partial atau penuh, planner memilih yang murah)",
    "USING INDEX" in rencana(d, "SELECT * FROM t WHERE status='baru' AND dibuat_pada > 1.71e9"), True, " [SQLite]")
d.execute("DROP INDEX ipenuh")
cek("hanya partial: status='baru' memakai partial index",
    rencana(d, "SELECT * FROM t WHERE status='baru' AND dibuat_pada > 1.71e9"),
    "SEARCH t USING INDEX ip (dibuat_pada>?)", " [SQLite]")
cek("hanya partial: status='selesai' TIDAK bisa memakainya",
    rencana(d, "SELECT * FROM t WHERE status='selesai' AND dibuat_pada > 1.71e9"), "SCAN t", " [SQLite]")
try:
    d.execute("CREATE INDEX ipenuh ON t (dibuat_pada)")
    u = dict(d.execute("SELECT name, sum(pgsize) FROM dbstat WHERE name IN ('ip','ipenuh') GROUP BY name").fetchall())
    rasio = u["ip"] / u["ipenuh"]
    print(f"ukuran index SQLite: partial {u['ip']:,} B, penuh {u['ipenuh']:,} B, rasio {rasio:.2f}")
    cek_benar("partial index ±1/8 ukuran index penuh (karena 'baru' ±12,5% baris)", 0.08 < rasio < 0.20, f"rasio {rasio:.3f}", " [SQLite]")
except sqlite3.OperationalError as e:
    print("[CATATAN] dbstat tidak tersedia, perbandingan ukuran dilewati:", e)

judul("E. Latihan 4: expression index")
d = baru()
d.execute("CREATE INDEX ie ON t (email)")
QL = "SELECT * FROM t WHERE lower(email) = 'user500@contoh.com'"
cek("index biasa pada email TIDAK dipakai oleh lower(email)", rencana(d, QL), "SCAN t", " [SQLite]")
d.execute("CREATE INDEX il ON t (lower(email))")
cek("setelah expression index: dipakai", rencana(d, QL), "SEARCH t USING INDEX il (<expr>=?)", " [SQLite]")

judul("F. Index covering (padanan INCLUDE)")
d = baru()
d.execute("CREATE INDEX icv ON t (pelanggan_id, total)")   # SQLite tidak punya INCLUDE: kolom tambahan dimasukkan ke kunci
cek("semua kolom yang diminta ada di index: COVERING INDEX",
    rencana(d, "SELECT pelanggan_id, total FROM t WHERE pelanggan_id = 100"),
    "SEARCH t USING COVERING INDEX icv (pelanggan_id=?)", " [SQLite]")
cek("meminta kolom di luar index: harus ke tabel",
    rencana(d, "SELECT pelanggan_id, total, status FROM t WHERE pelanggan_id = 100"),
    "SEARCH t USING INDEX icv (pelanggan_id=?)", " [SQLite]")

judul("G. Latihan 6: syarat BRIN = korelasi fisik (SIMULASI Python, bukan PostgreSQL)")
import statistics
BARIS = 1_000_000
PER_RANGE = 9_000      # asumsi: 128 halaman x ±70 baris/halaman (baris ±100 byte)
urut = list(range(BARIS))
acak = [random.random() for _ in range(BARIS)]


def range_terbaca(nilai, lo, hi):
    n = ok = 0
    for i in range(0, len(nilai), PER_RANGE):
        blok = nilai[i:i + PER_RANGE]
        n += 1
        ok += (min(blok) <= hi and max(blok) >= lo)
    return ok, n


kor_urut = statistics.correlation(range(BARIS), urut)
kor_acak = statistics.correlation(range(BARIS), acak)
a, n = range_terbaca(urut, 500_000, 500_100)
b, _ = range_terbaca(acak, 0.40, 0.4027)       # jendela sempit ±0,3% dari domain (setara 1 hari dari 365)
print(f"korelasi posisi-nilai: berurutan {kor_urut:.3f}, acak {kor_acak:.3f}")
print(f"range blok yang harus dibaca dari {n}: berurutan {a}, acak {b}")
cek_benar("data berurutan: korelasi ≈ 1", kor_urut > 0.999, f"{kor_urut:.4f}", " [SIMULASI]")
cek_benar("data acak: korelasi ≈ 0", abs(kor_acak) < 0.01, f"{kor_acak:.4f}", " [SIMULASI]")
cek_benar("rentang sempit pada data berurutan hanya menyentuh ±1 range blok", a <= 2, f"{a} dari {n}", " [SIMULASI]")
cek_benar("rentang sempit pada data acak menyentuh (hampir) SEMUA range blok", b >= 0.9 * n, f"{b} dari {n}", " [SIMULASI]")

print(f"\nSemua {TOTAL} pemeriksaan sesuai harapan.")
