# verifikasi_sqlite.py
# Memverifikasi LOGIKA jawaban Modul 8 dengan SQLite + hitungan independen di Python.
#
# Diuji nyata (SQL standar, hasil dibandingkan dengan hitungan Python): window function,
# recursive CTE, pertumbuhan bulanan, top-N per grup, rekursi tanggal.
# Diuji lewat PADANAN [PADANAN]: PL/pgSQL (ditiru dengan fungsi Python + SAVEPOINT),
# trigger PostgreSQL (ditiru dengan trigger SQLite), LATERAL (ditiru dengan loop per grup).
# TIDAK bisa diuji di sini: percentile_cont, CYCLE, date_trunc, sintaks PL/pgSQL,
# CREATE TRIGGER ... EXECUTE FUNCTION, dan pesan error PostgreSQL.
import calendar
import datetime
import re
import sqlite3
import statistics
from pathlib import Path

DIR = Path(__file__).parent
TOTAL = 0


def cek(label, aktual, harapan, padanan=False):
    global TOTAL
    TOTAL += 1
    ok = aktual == harapan
    tag = ("[OK][PADANAN]" if padanan else "[OK]") if ok else "[GAGAL]"
    print(f"{tag} {label}\n       aktual   : {aktual}\n       harapan  : {harapan}")
    assert ok, label


def ke_sqlite(sql):
    sql = sql.replace("now()", "CURRENT_TIMESTAMP")
    sql = sql.replace("bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY", "INTEGER PRIMARY KEY")
    sql = re.sub(r"numeric\(\d+,\s*\d+\)", "NUMERIC", sql)
    return sql.replace("bigint", "INTEGER").replace("timestamptz", "TEXT")


def buat_db(cascade=False):
    db = sqlite3.connect(":memory:", isolation_level=None)
    db.execute("PRAGMA foreign_keys = ON")
    ddl = (DIR / "skema_dasar.sql").read_text()
    if cascade:   # hipotesis Latihan 4: FK pesanan -> pelanggan memakai ON DELETE CASCADE
        i = ddl.index("CREATE TABLE pesanan")
        j = ddl.index(");", i)
        bagian = ddl[i:j].replace("REFERENCES pelanggan(id)", "REFERENCES pelanggan(id) ON DELETE CASCADE")
        ddl = ddl[:i] + bagian + ddl[j:]
    db.executescript(ke_sqlite(ddl))
    db.execute("ALTER TABLE produk ADD COLUMN kategori TEXT NOT NULL DEFAULT 'umum'")
    seed = "\n".join(l for l in (DIR / "seed.sql").read_text().splitlines()
                     if not l.startswith(("SET search_path", "TRUNCATE", "--")))
    db.executescript(seed)
    db.execute("UPDATE produk SET harga = 165000, stok = 80 WHERE sku = 'MS-001'")   # akhir Modul 5
    return db


PENJUALAN = [(1,1,'2026-01-04',500000),(2,2,'2026-01-07',300000),(3,1,'2026-01-10',750000),
             (4,3,'2026-01-13',200000),(5,2,'2026-01-16',450000),(6,1,'2026-01-19',600000),
             (7,4,'2026-01-22',900000),(8,3,'2026-01-25',350000),(9,2,'2026-01-28',250000),
             (10,1,'2026-01-31',800000),(11,4,'2026-02-03',400000),(12,3,'2026-02-06',650000)]


def judul(t):
    print("\n" + "=" * 78 + f"\n{t}\n" + "=" * 78)


db = buat_db()
db.execute("CREATE TABLE penjualan_uji (id INT PRIMARY KEY, pelanggan_id INT, tanggal TEXT, total NUMERIC)")
db.executemany("INSERT INTO penjualan_uji VALUES (?,?,?,?)", PENJUALAN)
q = lambda s, p=(): db.execute(s, p).fetchall()

judul("A. Praktik: window function (dibandingkan dengan hitungan Python)")
hasil = q("""SELECT id, pelanggan_id, tanggal, total,
                    sum(total) OVER (PARTITION BY pelanggan_id ORDER BY tanggal) AS total_berjalan,
                    lag(total) OVER (PARTITION BY pelanggan_id ORDER BY tanggal) AS total_sebelumnya,
                    rank() OVER (ORDER BY total DESC) AS peringkat
             FROM penjualan_uji ORDER BY pelanggan_id, tanggal""")
harapan, berjalan, sebelumnya = [], {}, {}
urut_total = sorted((r[3] for r in PENJUALAN), reverse=True)
for id_, pel, tgl, tot in sorted(PENJUALAN, key=lambda r: (r[1], r[2])):
    berjalan[pel] = berjalan.get(pel, 0) + tot
    harapan.append((id_, pel, tgl, tot, berjalan[pel], sebelumnya.get(pel), urut_total.index(tot) + 1))
    sebelumnya[pel] = tot
cek("total_berjalan, total_sebelumnya, peringkat per baris (12 baris)", hasil, harapan)

cek("Top-2 per pelanggan (row_number)",
    q("""SELECT pelanggan_id, id, total FROM (
           SELECT *, row_number() OVER (PARTITION BY pelanggan_id ORDER BY total DESC) AS n FROM penjualan_uji)
         WHERE n <= 2 ORDER BY pelanggan_id, n"""),
    [(1, 10, 800000), (1, 3, 750000), (2, 5, 450000), (2, 2, 300000),
     (3, 12, 650000), (3, 8, 350000), (4, 7, 900000), (4, 11, 400000)])
print(f"[CATATAN] median (percentile_cont) tidak ada di SQLite. Hitungan Python: {statistics.median(r[3] for r in PENJUALAN):.0f}"
      "  -> nilai yang diharapkan dari PostgreSQL untuk data ini (tipe double precision).")

judul("B. Praktik: recursive CTE (struktur organisasi)")
db.executescript("""CREATE TABLE karyawan (id INT PRIMARY KEY, nama TEXT, atasan_id INT);
INSERT INTO karyawan VALUES (1,'Direktur',NULL),(2,'Manajer A',1),(3,'Manajer B',1),
                            (4,'Staf A1',2),(5,'Staf A2',2),(6,'Staf B1',3);""")
cek("pohon organisasi diurut menurut jalur",
    q("""WITH RECURSIVE struktur AS (
           SELECT id, nama, atasan_id, 0 AS level, nama AS jalur FROM karyawan WHERE atasan_id IS NULL
         UNION ALL
           SELECT k.id, k.nama, k.atasan_id, s.level + 1, s.jalur || ' > ' || k.nama
           FROM karyawan k JOIN struktur s ON k.atasan_id = s.id)
         SELECT level, jalur FROM struktur ORDER BY jalur"""),
    [(0, "Direktur"), (1, "Direktur > Manajer A"), (2, "Direktur > Manajer A > Staf A1"),
     (2, "Direktur > Manajer A > Staf A2"), (1, "Direktur > Manajer B"), (2, "Direktur > Manajer B > Staf B1")])
print("[CATATAN] Urutan memakai perbandingan biner di SQLite. Di PostgreSQL urutan teks mengikuti collation database;\n"
      "          untuk urutan pohon yang pasti, urutkan dengan array jalur (ARRAY[id]) alih-alih teks.")

judul("C. Latihan 1: pertumbuhan bulanan")
cek("bulan, total, total_sebelumnya, persen",
    q("""WITH bulanan AS (SELECT substr(tanggal,1,7) || '-01' AS bulan, sum(total) AS total
                         FROM penjualan_uji GROUP BY 1),
              dengan_lag AS (SELECT bulan, total, lag(total) OVER (ORDER BY bulan) AS sebelumnya FROM bulanan)
         SELECT bulan, total, sebelumnya,
                round(100.0 * (total - sebelumnya) / NULLIF(sebelumnya, 0), 2) FROM dengan_lag ORDER BY bulan"""),
    [("2026-01-01", 5100000, None, None), ("2026-02-01", 1050000, 5100000, -79.41)])

judul("D. Latihan 2: Top-3 produk terlaris per kategori")
VIEW = """CREATE TEMP VIEW terjual AS
SELECT pr.id, pr.nama, pr.kategori,
       COALESCE(sum(i.jumlah) FILTER (WHERE p.status <> 'batal'), 0) AS qty
FROM produk pr LEFT JOIN item_pesanan i ON i.produk_id = pr.id LEFT JOIN pesanan p ON p.id = i.pesanan_id
GROUP BY pr.id"""
db.execute(VIEW)
TOP3 = """SELECT kategori, nama, qty FROM (
            SELECT t.*, row_number() OVER (PARTITION BY kategori ORDER BY qty DESC, id) AS n FROM terjual t)
          WHERE n <= 3 ORDER BY kategori, n"""
cek("qty terjual per produk (pesanan batal dikecualikan; HP hanya ada di pesanan batal)",
    q("SELECT nama, qty FROM terjual ORDER BY id"),
    [("Laptop 14 inci", 1), ("Mouse Nirkabel", 3), ("Keyboard Mekanik", 1), ("Monitor 24 inci", 2), ("Headset", 0)])
cek("satu kategori 'umum': 3 teratas", q(TOP3),
    [("umum", "Mouse Nirkabel", 3), ("umum", "Monitor 24 inci", 2), ("umum", "Laptop 14 inci", 1)])
db.execute("""UPDATE produk SET kategori = CASE sku WHEN 'LP-001' THEN 'komputer' WHEN 'MN-001' THEN 'komputer'
              WHEN 'KB-001' THEN 'aksesori' WHEN 'MS-001' THEN 'aksesori' ELSE kategori END""")
rn = q(TOP3)
cek("tiga kategori (row_number)", rn,
    [("aksesori", "Mouse Nirkabel", 3), ("aksesori", "Keyboard Mekanik", 1),
     ("komputer", "Monitor 24 inci", 2), ("komputer", "Laptop 14 inci", 1), ("umum", "Headset", 0)])
lateral = []
for (kat,) in q("SELECT DISTINCT kategori FROM produk ORDER BY kategori"):      # semantik LATERAL: per grup, LIMIT 3
    lateral += [(kat, n, qty) for n, qty in
                q("SELECT nama, qty FROM terjual WHERE kategori = ? ORDER BY qty DESC, id LIMIT 3", (kat,))]
cek("padanan LATERAL (loop per kategori + LIMIT 3) = hasil row_number", lateral, rn, padanan=True)

judul("E. Praktik + Latihan 3: fungsi PL/pgSQL (ditiru Python + SAVEPOINT)")


class ErrorFungsi(Exception):
    pass


def kurangi_stok(db, produk, jumlah):
    r = db.execute("SELECT stok FROM produk WHERE id = ?", (produk,)).fetchone()
    if r is None:
        raise ErrorFungsi(f"Produk {produk} tidak ditemukan")
    if r[0] < jumlah:
        raise ErrorFungsi(f"Stok tidak cukup ({r[0]} < {jumlah})")
    db.execute("UPDATE produk SET stok = stok - ? WHERE id = ?", (jumlah, produk))
    return r[0] - jumlah


def buat_pesanan(db, pel, produk, jumlah):
    if jumlah is None or jumlah <= 0:
        raise ErrorFungsi(f"Jumlah harus lebih dari 0 (diminta {jumlah})")
    kurangi_stok(db, produk, jumlah)
    harga = db.execute("SELECT harga FROM produk WHERE id = ?", (produk,)).fetchone()[0]
    pid = db.execute("INSERT INTO pesanan (pelanggan_id) VALUES (?)", (pel,)).lastrowid
    db.execute("INSERT INTO item_pesanan (pesanan_id, produk_id, jumlah, harga_satuan) VALUES (?,?,?,?)",
               (pid, produk, jumlah, harga))
    return pid


def panggil(fn, *args):
    """Atomisitas tingkat statement: error di mana pun membatalkan seluruh efek fungsi."""
    db.execute("SAVEPOINT stmt")
    try:
        hasil = fn(db, *args)
        db.execute("RELEASE stmt")
        return hasil
    except Exception:
        db.execute("ROLLBACK TO stmt")
        db.execute("RELEASE stmt")
        raise


def keadaan():
    return (q("SELECT count(*) FROM pesanan")[0][0], q("SELECT count(*) FROM item_pesanan")[0][0],
            q("SELECT stok FROM produk WHERE id = 4")[0][0])


db.execute("BEGIN")
cek("kurangi_stok(1, 2) mengembalikan sisa stok Laptop (10 - 2)", panggil(kurangi_stok, 1, 2), 8, padanan=True)
try:
    panggil(kurangi_stok, 1, 9999)
    pesan = "tidak error"
except ErrorFungsi as e:
    pesan = str(e)
cek("kurangi_stok(1, 9999) gagal dengan pesan stok tidak cukup", pesan, "Stok tidak cukup (8 < 9999)", padanan=True)
db.execute("ROLLBACK")

awal = keadaan()
cek("keadaan awal (pesanan, item, stok Monitor)", awal, (5, 6, 5))
for label, args, jenis in [("stok tidak cukup", (1, 4, 9999), ErrorFungsi),
                           ("pelanggan 999 tidak ada: stok SUDAH dikurangi, INSERT pesanan gagal (FK)", (999, 4, 2), sqlite3.IntegrityError),
                           ("jumlah 0", (1, 4, 0), ErrorFungsi)]:
    try:
        panggil(buat_pesanan, *args)
        gagal = False
    except jenis:
        gagal = True
    cek(f"buat_pesanan gagal: {label}", gagal, True, padanan=True)
    cek("   tidak ada data setengah jadi", keadaan(), awal, padanan=True)
db.execute("BEGIN")
panggil(buat_pesanan, 2, 4, 2)
cek("buat_pesanan(2, 4, 2) berhasil: +1 pesanan, +1 item, stok Monitor 5 -> 3", keadaan(), (6, 7, 3), padanan=True)
db.execute("ROLLBACK")
db.execute("BEGIN")
panggil(buat_pesanan, 2, 4, 1)
try:
    panggil(buat_pesanan, 2, 4, 9999)
except ErrorFungsi:
    pass
db.execute("ROLLBACK")          # di PostgreSQL error membuat transaksi aborted; aplikasi memanggil ROLLBACK
cek("satu transaksi sukses+gagal lalu ROLLBACK: kembali ke keadaan awal", keadaan(), awal, padanan=True)

judul("F. Latihan 4: trigger pencegah DELETE pelanggan (ditiru trigger SQLite)")
TRIGGER = """CREATE TRIGGER trg_cegah BEFORE DELETE ON pelanggan
WHEN EXISTS (SELECT 1 FROM pesanan WHERE pelanggan_id = OLD.id AND status IN ('baru','dibayar','dikirim'))
BEGIN SELECT RAISE(ABORT, 'masih punya pesanan aktif'); END"""


def hapus(db, id_):
    try:
        db.execute("DELETE FROM pelanggan WHERE id = ?", (id_,))
        return "dihapus"
    except sqlite3.IntegrityError as e:
        return str(e)


d1 = buat_db()
d1.execute(TRIGGER)
cek("FK biasa + trigger: Budi (pesanan 'baru') ditolak oleh TRIGGER", hapus(d1, 2), "masih punya pesanan aktif", padanan=True)
cek("FK biasa + trigger: Andi (selesai + dibayar) ditolak oleh TRIGGER", hapus(d1, 1), "masih punya pesanan aktif", padanan=True)
cek("FK biasa + trigger: Dedi (hanya 'batal') lolos trigger tetapi DITOLAK FK", hapus(d1, 4), "FOREIGN KEY constraint failed", padanan=True)
cek("FK biasa tanpa trigger: Budi ditolak oleh FK saja (pesan generik)",
    hapus(buat_db(), 2), "FOREIGN KEY constraint failed", padanan=True)
d2 = buat_db(cascade=True)
d2.execute(TRIGGER)
cek("FK CASCADE + trigger: Budi tetap ditolak trigger", hapus(d2, 2), "masih punya pesanan aktif", padanan=True)
cek("FK CASCADE + trigger: Dedi (hanya batal) dihapus", hapus(d2, 4), "dihapus", padanan=True)
cek("   pesanan Dedi ikut terhapus (CASCADE): pelanggan, pesanan, item",
    (d2.execute("SELECT count(*) FROM pelanggan").fetchone()[0], d2.execute("SELECT count(*) FROM pesanan").fetchone()[0],
     d2.execute("SELECT count(*) FROM item_pesanan").fetchone()[0]), (3, 4, 5), padanan=True)
d3 = buat_db(cascade=True)
cek("FK CASCADE TANPA trigger: Budi dihapus bersama pesanan aktifnya (bahaya)", hapus(d3, 2), "dihapus", padanan=True)

judul("G. Praktik: audit trigger (logika IS DISTINCT FROM)")
db = buat_db()
db.executescript("""CREATE TABLE audit_harga (id INTEGER PRIMARY KEY, produk_id INT, harga_lama NUMERIC, harga_baru NUMERIC);
CREATE TRIGGER trg_audit_harga AFTER UPDATE ON produk FOR EACH ROW WHEN NEW.harga IS NOT OLD.harga
BEGIN INSERT INTO audit_harga (produk_id, harga_lama, harga_baru) VALUES (OLD.id, OLD.harga, NEW.harga); END;""")
db.execute("UPDATE produk SET harga = harga WHERE id = 1")
cek("UPDATE tanpa perubahan harga tidak mencatat audit", db.execute("SELECT count(*) FROM audit_harga").fetchone()[0], 0, padanan=True)
db.execute("UPDATE produk SET harga = harga + 5000 WHERE id = 2")
cek("harga Mouse +5000 mencatat satu baris audit",
    db.execute("SELECT produk_id, harga_lama, harga_baru FROM audit_harga").fetchall(), [(2, 165000, 170000)], padanan=True)

judul("H. Latihan 5: tanggal satu bulan dengan WITH RECURSIVE")
for tahun, bulan in [(2026, 11), (2028, 2), (2026, 2)]:
    awal = f"{tahun}-{bulan:02d}-01"
    rek = [r[0] for r in db.execute("""WITH RECURSIVE tgl(d) AS (
              SELECT ? UNION ALL SELECT date(d, '+1 day') FROM tgl
              WHERE date(d, '+1 day') < date(?, 'start of month', '+1 month'))
            SELECT d FROM tgl""", (awal, awal))]
    hari = calendar.monthrange(tahun, bulan)[1]
    cek(f"{awal[:7]}: {hari} tanggal, sama dengan kalender",
        rek, [datetime.date(tahun, bulan, h).isoformat() for h in range(1, hari + 1)])

print(f"\nSemua {TOTAL} pemeriksaan sesuai harapan.")
