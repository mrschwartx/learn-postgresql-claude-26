# verifikasi_sqlite.py
# Memverifikasi LOGIKA jawaban Modul 5 dengan SQLite, memakai seed.sql dan CREATE TABLE asli
# (praktik Modul 4) yang disalin otomatis ke dialek SQLite. PostgreSQL tidak dipakai di sini.
#
# Yang TIDAK bisa dibuktikan oleh SQLite (ditandai di output): ILIKE, ::cast, date_trunc,
# format keluaran numeric, `\copy`, dan error "column does not exist" pada Latihan 3
# (SQLite justru MENGIZINKAN alias di WHERE).
import csv
import io
import re
import sqlite3
from decimal import Decimal
from pathlib import Path

DIR = Path(__file__).parent
M4 = (DIR / "skema_dasar.sql").read_text()
TOTAL = 0


def cek(label, aktual, harapan):
    global TOTAL
    ok = aktual == harapan
    TOTAL += 1
    print(f"[{'OK' if ok else 'GAGAL'}] {label}\n       aktual   : {aktual}\n       harapan  : {harapan}")
    assert ok, label


def ke_sqlite(sql):
    sql = sql.replace("now()", "CURRENT_TIMESTAMP").replace("current_date", "CURRENT_DATE")
    sql = sql.replace("bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY", "INTEGER PRIMARY KEY")
    sql = re.sub(r"numeric\(\d+,\s*\d+\)", "NUMERIC", sql)
    return sql.replace("bigint", "INTEGER").replace("timestamptz", "TEXT")


def buat_db():
    db = sqlite3.connect(":memory:")
    db.execute("PRAGMA foreign_keys = ON")
    for ddl in re.findall(r"CREATE TABLE \w+ \(.*?\);", M4, re.S):
        db.execute(ke_sqlite(ddl))
    seed = (DIR / "seed.sql").read_text()
    seed = "\n".join(l for l in seed.splitlines()
                     if not l.startswith(("SET search_path", "TRUNCATE", "--")))
    db.executescript(seed)
    return db


db = buat_db()
q = lambda s, p=(): db.execute(s, p).fetchall()

print("=" * 78)
print("A. Seed data (seed.sql asli)")
print("=" * 78)
cek("jumlah pelanggan/produk/pesanan/item_pesanan",
    (q("SELECT count(*) FROM pelanggan")[0][0], q("SELECT count(*) FROM produk")[0][0],
     q("SELECT count(*) FROM pesanan")[0][0], q("SELECT count(*) FROM item_pesanan")[0][0]),
    (4, 5, 5, 6))

print()
print("=" * 78)
print("B. Query dan Filter")
print("=" * 78)
cek("harga BETWEEN 100000 AND 1000000 ORDER BY harga DESC",
    q("SELECT nama, harga FROM produk WHERE harga BETWEEN 100000 AND 1000000 ORDER BY harga DESC"),
    [("Keyboard Mekanik", 850000), ("Headset", 450000), ("Mouse Nirkabel", 150000)])
cek("CASE status_stok",
    q("SELECT sku, CASE WHEN stok = 0 THEN 'habis' WHEN stok < 10 THEN 'menipis' ELSE 'aman' END FROM produk ORDER BY id"),
    [("LP-001", "aman"), ("MS-001", "aman"), ("KB-001", "aman"), ("MN-001", "menipis"), ("HP-001", "habis")])
cek("ORDER BY harga DESC LIMIT 3 OFFSET 1",
    q("SELECT nama FROM produk ORDER BY harga DESC LIMIT 3 OFFSET 1"),
    [("Monitor 24 inci",), ("Keyboard Mekanik",), ("Headset",)])
print("[CATATAN] ILIKE '%mouse%' khas PostgreSQL. LIKE SQLite tidak peka huruf besar/kecil (ASCII), "
      "dipakai sebagai pendekatan:")
cek("LIKE '%mouse%' (pendekatan ILIKE)", q("SELECT nama FROM produk WHERE nama LIKE '%mouse%'"), [("Mouse Nirkabel",)])

print()
print("Nilai harga * 1.11 di PostgreSQL (numeric(12,2) * numeric(skala 2) = skala 4), dihitung dengan Decimal:")
for sku, nama, harga in q("SELECT sku, nama, harga FROM produk ORDER BY id"):
    print(f"   {sku}  {Decimal(harga).quantize(Decimal('0.01')) * Decimal('1.11')}")

print()
print("=" * 78)
print("C. Modifikasi Data")
print("=" * 78)
cek("UPDATE ... RETURNING", q("UPDATE produk SET stok = stok - 1 WHERE sku = 'MS-001' RETURNING sku, stok"), [("MS-001", 99)])
cek("UPSERT ON CONFLICT DO UPDATE ... RETURNING *",
    q("INSERT INTO produk (sku, nama, harga, stok) VALUES ('MS-001','Mouse Nirkabel',165000,80) "
      "ON CONFLICT (sku) DO UPDATE SET harga = EXCLUDED.harga, stok = EXCLUDED.stok RETURNING *"),
    [(2, "MS-001", "Mouse Nirkabel", 165000, 80)])
cek("jumlah produk tetap 5 (tidak ada baris baru)", q("SELECT count(*) FROM produk")[0][0], 5)
db.commit()

print()
print("=" * 78)
print("D. Latihan 1: stok < 20 dengan label")
print("=" * 78)
cek("Latihan 1",
    q("SELECT sku, nama, stok, CASE WHEN stok = 0 THEN 'kritis' ELSE 'rendah' END FROM produk "
      "WHERE stok < 20 ORDER BY stok ASC"),
    [("HP-001", "Headset", 0, "kritis"), ("MN-001", "Monitor 24 inci", 5, "rendah"),
     ("LP-001", "Laptop 14 inci", 10, "rendah")])

print()
print("=" * 78)
print("E. Latihan 2: upsert menambah stok tanpa membaca stok lama")
print("=" * 78)
sql2 = ("INSERT INTO produk (sku, nama, harga, stok) VALUES ('KB-001','Keyboard Mekanik',850000,10) "
        "ON CONFLICT (sku) DO UPDATE SET stok = produk.stok + EXCLUDED.stok RETURNING sku, stok")
cek("stok KB-001: 25 -> 35", q(sql2), [("KB-001", 35)])
cek("dijalankan lagi (tidak idempoten): 35 -> 45", q(sql2), [("KB-001", 45)])
db.execute("UPDATE produk SET stok = 25 WHERE sku = 'KB-001'")
try:
    db.execute("INSERT INTO produk (sku, nama, harga, stok) VALUES ('KB-001','Keyboard Mekanik',850000,-30) "
               "ON CONFLICT (sku) DO UPDATE SET stok = produk.stok + EXCLUDED.stok")
    hasil = "lolos"
except sqlite3.IntegrityError:
    hasil = "ditolak"
cek("baris usulan stok -30 melanggar CHECK (stok >= 0) walau akan di-UPDATE", hasil, "ditolak")
db.commit()

print()
print("=" * 78)
print("F. Latihan 3: alias di WHERE")
print("=" * 78)
print("[CATATAN] SQLite menerima 'WHERE h > ...' (alias di WHERE), PostgreSQL TIDAK:")
print("          PostgreSQL -> ERROR: column \"h\" does not exist. Jadi tahap ini tidak bisa dibuktikan di sini.")
cek("perbaikan 1: ulangi ekspresi",
    [round(r[0]) for r in q("SELECT harga*1.11 AS h FROM produk WHERE harga*1.11 > 1000000 ORDER BY h")],
    [2442000, 13875000])
cek("perbaikan 2: subquery",
    [round(r[0]) for r in q("SELECT h FROM (SELECT harga*1.11 AS h FROM produk) AS t WHERE h > 1000000 ORDER BY h")],
    [2442000, 13875000])

print()
print("=" * 78)
print("G. Latihan 4: DELETE ... RETURNING + cascade + ROLLBACK")
print("=" * 78)
db.isolation_level = None
cek("sebelum", (q("SELECT count(*) FROM pesanan")[0][0], q("SELECT count(*) FROM item_pesanan")[0][0]), (5, 6))
db.execute("BEGIN")
cek("DELETE RETURNING id", q("DELETE FROM pesanan WHERE status = 'batal' RETURNING id"), [(5,)])
cek("di dalam transaksi (pesanan 5 dan 1 item-nya hilang)",
    (q("SELECT count(*) FROM pesanan")[0][0], q("SELECT count(*) FROM item_pesanan")[0][0]), (4, 5))
db.execute("ROLLBACK")
cek("setelah ROLLBACK", (q("SELECT count(*) FROM pesanan")[0][0], q("SELECT count(*) FROM item_pesanan")[0][0]), (5, 6))

print()
print("=" * 78)
print("H. Latihan 5: ekspor CSV, ubah harga di file, impor ke tabel sementara, bandingkan")
print("=" * 78)
print("[CATATAN] Logikanya diuji dengan modul csv Python; sintaks \\copy hanya bisa dibuktikan di psql.")
buf = io.StringIO()
w = csv.writer(buf, lineterminator="\n")
w.writerow(["sku", "nama", "harga", "stok"])
for r in q("SELECT sku, nama, harga, stok FROM produk ORDER BY sku"):
    w.writerow([r[0], r[1], f"{Decimal(r[2]).quantize(Decimal('0.01'))}", r[3]])
teks = buf.getvalue()
print("isi CSV (harga tampil dengan 2 desimal seperti numeric(12,2) di PostgreSQL):")
print("   " + teks.replace("\n", "\n   ").rstrip())
teks_baru = re.sub(r"^(KB-001,[^,]*,)850000\.00,", r"\g<1>900000.00,", teks, flags=re.M)
cek("sed pada baris KB-001 mengubah tepat 1 baris", sum(a != b for a, b in zip(teks.splitlines(), teks_baru.splitlines())), 1)
db.execute("CREATE TEMP TABLE produk_import (id INTEGER PRIMARY KEY, sku TEXT, nama TEXT, harga NUMERIC, stok INTEGER)")
for row in csv.DictReader(io.StringIO(teks_baru)):
    db.execute("INSERT INTO produk_import (sku, nama, harga, stok) VALUES (?,?,?,?)",
               (row["sku"], row["nama"], row["harga"], int(row["stok"])))
cek("jumlah baris asli vs impor", (q("SELECT count(*) FROM produk")[0][0], q("SELECT count(*) FROM produk_import")[0][0]), (5, 5))
cek("baris yang harganya berbeda (IS NOT = IS DISTINCT FROM)",
    q("SELECT p.sku, p.harga, i.harga FROM produk p JOIN produk_import i USING (sku) WHERE p.harga IS NOT i.harga + 0"),
    [("KB-001", 850000, 900000)])
cek("EXCEPT dua arah menemukan 2 baris (versi lama dan baru KB-001)",
    len(q("SELECT sku,nama,harga+0,stok FROM produk EXCEPT SELECT sku,nama,harga+0,stok FROM produk_import")) +
    len(q("SELECT sku,nama,harga+0,stok FROM produk_import EXCEPT SELECT sku,nama,harga+0,stok FROM produk")), 2)

print(f"\nSemua {TOTAL} pemeriksaan sesuai harapan.")
