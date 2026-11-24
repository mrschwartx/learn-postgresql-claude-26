# verifikasi_sqlite.py
# Memverifikasi LOGIKA jawaban Modul 6 dengan SQLite, memakai skema dan seed.sql asli
# (disalin ke dialek SQLite). PostgreSQL tidak dipakai di sini.
#
# SQLite TIDAK mendukung: ROLLUP, LATERAL, CTE data-modifying, dan menolak-bare-column pada
# GROUP BY (SQLite justru permisif). Untuk itu dipakai PADANAN yang hasilnya dibandingkan
# dengan hasil yang dihitung tangan; ditandai [PADANAN]. Sintaks aslinya baru terbukti di psql.
import re
import sqlite3
from pathlib import Path

DIR = Path(__file__).parent
TOTAL = 0


def cek(label, aktual, harapan, padanan=False):
    global TOTAL
    TOTAL += 1
    ok = aktual == harapan
    tag = "[OK][PADANAN]" if padanan and ok else ("[OK]" if ok else "[GAGAL]")
    print(f"{tag} {label}\n       aktual   : {aktual}\n       harapan  : {harapan}")
    assert ok, label


def ke_sqlite(sql):
    sql = sql.replace("now()", "CURRENT_TIMESTAMP")
    sql = sql.replace("bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY", "INTEGER PRIMARY KEY")
    sql = re.sub(r"numeric\(\d+,\s*\d+\)", "NUMERIC", sql)
    return sql.replace("bigint", "INTEGER").replace("timestamptz", "TEXT")


def buat_db():
    db = sqlite3.connect(":memory:")
    db.execute("PRAGMA foreign_keys = ON")
    db.executescript(ke_sqlite((DIR / "skema_dasar.sql").read_text()))
    db.execute("ALTER TABLE produk ADD COLUMN kategori TEXT NOT NULL DEFAULT 'umum'")  # dari Modul 4
    seed = "\n".join(l for l in (DIR / "seed.sql").read_text().splitlines()
                     if not l.startswith(("SET search_path", "TRUNCATE", "--")))
    db.executescript(seed)
    # keadaan akhir Praktik Modul 5 (upsert MS-001)
    db.execute("UPDATE produk SET harga = 165000, stok = 80 WHERE sku = 'MS-001'")
    db.commit()
    db.isolation_level = None
    return db


db = buat_db()
q = lambda s, p=(): db.execute(s, p).fetchall()


def judul(t):
    print("\n" + "=" * 78 + f"\n{t}\n" + "=" * 78)


judul("A. Praktik")
cek("INNER JOIN pelanggan-pesanan (5 baris)",
    q("SELECT c.nama, p.id, p.status FROM pelanggan c JOIN pesanan p ON p.pelanggan_id = c.id ORDER BY p.id"),
    [("Andi", 1, "selesai"), ("Andi", 2, "dibayar"), ("Budi", 3, "baru"), ("Citra", 4, "selesai"), ("Dedi", 5, "batal")])
cek("LEFT JOIN + count(p.id)",
    dict(q("SELECT c.nama, count(p.id) FROM pelanggan c LEFT JOIN pesanan p ON p.pelanggan_id = c.id GROUP BY c.id, c.nama")),
    {"Andi": 2, "Budi": 1, "Citra": 1, "Dedi": 1})
cek("JOIN 4 tabel: 6 baris detail",
    q("""SELECT p.id, c.nama, pr.nama, i.jumlah, i.jumlah * i.harga_satuan
         FROM pesanan p JOIN pelanggan c ON c.id = p.pelanggan_id
         JOIN item_pesanan i ON i.pesanan_id = p.id JOIN produk pr ON pr.id = i.produk_id
         ORDER BY p.id, pr.id"""),
    [(1, "Andi", "Laptop 14 inci", 1, 12500000), (1, "Andi", "Mouse Nirkabel", 2, 300000),
     (2, "Andi", "Keyboard Mekanik", 1, 850000), (3, "Budi", "Mouse Nirkabel", 1, 150000),
     (4, "Citra", "Monitor 24 inci", 2, 4400000), (5, "Dedi", "Headset", 1, 450000)])
cek("GROUP BY status",
    dict(q("SELECT status, count(*) FROM pesanan GROUP BY status")),
    {"selesai": 2, "dibayar": 1, "baru": 1, "batal": 1})
cek("count(*) FILTER (WHERE status='selesai')",
    q("SELECT count(*), count(*) FILTER (WHERE status='selesai') FROM pesanan"), [(5, 2)])

rollup_padanan = q("""
    SELECT c.nama, p.status, count(*) FROM pesanan p JOIN pelanggan c ON c.id = p.pelanggan_id GROUP BY c.nama, p.status
    UNION ALL
    SELECT c.nama, NULL, count(*) FROM pesanan p JOIN pelanggan c ON c.id = p.pelanggan_id GROUP BY c.nama
    UNION ALL
    SELECT NULL, NULL, count(*) FROM pesanan""")
cek("ROLLUP (nama, status): 5 detail + 4 subtotal + 1 grand total = 10 baris",
    sorted(rollup_padanan, key=lambda r: (r[0] is None, r[0] or "", r[1] is None, r[1] or "")),
    [("Andi", "dibayar", 1), ("Andi", "selesai", 1), ("Andi", None, 2),
     ("Budi", "baru", 1), ("Budi", None, 1),
     ("Citra", "selesai", 1), ("Citra", None, 1),
     ("Dedi", "batal", 1), ("Dedi", None, 1),
     (None, None, 5)], padanan=True)

cek("produk di atas harga rata-rata (3.233.000)",
    q("SELECT nama FROM produk WHERE harga > (SELECT avg(harga) FROM produk)"), [("Laptop 14 inci",)])
cek("produk yang belum pernah dipesan (NOT EXISTS): kosong pada seed",
    q("SELECT nama FROM produk pr WHERE NOT EXISTS (SELECT 1 FROM item_pesanan i WHERE i.produk_id = pr.id)"), [])
cek("EXCEPT id produk - produk_id item: kosong pada seed",
    q("SELECT id FROM produk EXCEPT SELECT produk_id FROM item_pesanan"), [])
cek("CTE total belanja per pelanggan",
    q("""WITH total_pesanan AS (SELECT pesanan_id, sum(jumlah * harga_satuan) AS total FROM item_pesanan GROUP BY pesanan_id)
         SELECT c.nama, sum(t.total) AS total_belanja FROM total_pesanan t
         JOIN pesanan p ON p.id = t.pesanan_id JOIN pelanggan c ON c.id = p.pelanggan_id
         GROUP BY c.nama ORDER BY total_belanja DESC"""),
    [("Andi", 13650000), ("Citra", 4400000), ("Dedi", 450000), ("Budi", 150000)])
cek("TEMUAN: dua pesanan Andi punya dibuat_pada IDENTIK (now() = awal transaksi)",
    q("SELECT count(DISTINCT dibuat_pada) FROM pesanan WHERE pelanggan_id = 1")[0][0], 1)
cek("pesanan terbaru per pelanggan dengan pemutus seri (id DESC)",
    q("""SELECT c.nama, (SELECT p.id FROM pesanan p WHERE p.pelanggan_id = c.id
                        ORDER BY p.dibuat_pada DESC, p.id DESC LIMIT 1) FROM pelanggan c ORDER BY c.id"""),
    [("Andi", 2), ("Budi", 3), ("Citra", 4), ("Dedi", 5)], padanan=True)
cek("UNION ALL: pelanggan @contoh.com + produk > 1 juta (5 baris)",
    q("""SELECT nama FROM pelanggan WHERE email LIKE '%@contoh.com'
         UNION ALL SELECT nama FROM produk WHERE harga > 1000000"""),
    [("Andi",), ("Budi",), ("Citra",), ("Laptop 14 inci",), ("Monitor 24 inci",)])

judul("B. Latihan 1: total belanja termasuk pelanggan tanpa belanja")
db.execute("BEGIN")
db.execute("INSERT INTO pelanggan (nama, email) VALUES ('Eka', 'eka@contoh.com')")
cek("total per pelanggan, Eka = 0",
    q("""SELECT c.nama, COALESCE(sum(i.jumlah * i.harga_satuan), 0)
         FROM pelanggan c LEFT JOIN pesanan p ON p.pelanggan_id = c.id
         LEFT JOIN item_pesanan i ON i.pesanan_id = p.id
         GROUP BY c.id, c.nama ORDER BY 2 DESC, c.id"""),
    [("Andi", 13650000), ("Citra", 4400000), ("Dedi", 450000), ("Budi", 150000), ("Eka", 0)])
cek("jebakan: count(*) menghitung 1 untuk Eka, count(p.id) menghitung 0",
    q("""SELECT count(*), count(p.id) FROM pelanggan c LEFT JOIN pesanan p ON p.pelanggan_id = c.id
         WHERE c.nama = 'Eka'"""), [(1, 0)])

judul("C. Latihan 2: tiga cara + bahaya NOT IN")
cek("cara 1 LEFT JOIN ... IS NULL",
    q("SELECT c.nama FROM pelanggan c LEFT JOIN pesanan p ON p.pelanggan_id = c.id WHERE p.id IS NULL"), [("Eka",)])
cek("cara 2 NOT EXISTS",
    q("SELECT c.nama FROM pelanggan c WHERE NOT EXISTS (SELECT 1 FROM pesanan p WHERE p.pelanggan_id = c.id)"), [("Eka",)])
cek("cara 3 NOT IN (tanpa NULL di subquery)",
    q("SELECT c.nama FROM pelanggan c WHERE c.id NOT IN (SELECT pelanggan_id FROM pesanan)"), [("Eka",)])
cek("NOT IN dengan satu NULL di subquery: KOSONG",
    q("SELECT c.nama FROM pelanggan c WHERE c.id NOT IN (SELECT pelanggan_id FROM pesanan UNION ALL SELECT NULL)"), [])
cek("NOT EXISTS dengan NULL yang sama: tetap benar",
    q("""SELECT c.nama FROM pelanggan c WHERE NOT EXISTS
         (SELECT 1 FROM (SELECT pelanggan_id FROM pesanan UNION ALL SELECT NULL) s WHERE s.pelanggan_id = c.id)"""),
    [("Eka",)])
db.execute("ROLLBACK")
cek("setelah ROLLBACK Eka tidak ada", q("SELECT count(*) FROM pelanggan WHERE nama = 'Eka'")[0][0], 0)

judul("D. Latihan 3: 2 produk termahal per kategori")
db.execute("BEGIN")
db.execute("""UPDATE produk SET kategori = CASE sku
    WHEN 'LP-001' THEN 'komputer' WHEN 'MN-001' THEN 'komputer'
    WHEN 'KB-001' THEN 'aksesori' WHEN 'MS-001' THEN 'aksesori' ELSE 'audio' END""")
cek("top-2 per kategori (PADANAN LATERAL dengan row_number())",
    q("""SELECT kategori, nama, harga FROM
           (SELECT kategori, nama, harga,
                   row_number() OVER (PARTITION BY kategori ORDER BY harga DESC, id) AS rn FROM produk)
         WHERE rn <= 2 ORDER BY kategori, harga DESC"""),
    [("aksesori", "Keyboard Mekanik", 850000), ("aksesori", "Mouse Nirkabel", 165000),
     ("audio", "Headset", 450000),
     ("komputer", "Laptop 14 inci", 12500000), ("komputer", "Monitor 24 inci", 2200000)], padanan=True)
db.execute("ROLLBACK")

judul("E. Latihan 4: memindahkan pesanan batal ke arsip")
print("[CATATAN] CTE data-modifying (WITH ... DELETE ... RETURNING) tidak didukung SQLite.")
print("          Yang diuji: HASIL AKHIR yang sama lewat INSERT..SELECT lalu DELETE dalam satu transaksi.")
db.execute("BEGIN")
db.execute("CREATE TABLE arsip_pesanan (id INTEGER NOT NULL, pelanggan_id INTEGER NOT NULL, status TEXT NOT NULL, dibuat_pada TEXT NOT NULL)")
db.execute("CREATE TABLE arsip_item_pesanan (pesanan_id INTEGER, produk_id INTEGER, jumlah INTEGER, harga_satuan NUMERIC)")
db.execute("""INSERT INTO arsip_item_pesanan SELECT * FROM item_pesanan
              WHERE pesanan_id IN (SELECT id FROM pesanan WHERE status = 'batal')""")
db.execute("INSERT INTO arsip_pesanan SELECT id, pelanggan_id, status, dibuat_pada FROM pesanan WHERE status = 'batal'")
db.execute("DELETE FROM pesanan WHERE status = 'batal'")
cek("arsip_pesanan / arsip_item / pesanan aktif / item aktif",
    (q("SELECT count(*) FROM arsip_pesanan")[0][0], q("SELECT count(*) FROM arsip_item_pesanan")[0][0],
     q("SELECT count(*) FROM pesanan")[0][0], q("SELECT count(*) FROM item_pesanan")[0][0]),
    (1, 1, 4, 5), padanan=True)
cek("pesanan yang diarsipkan = id 5", q("SELECT id, status FROM arsip_pesanan"), [(5, "batal")], padanan=True)
db.execute("ROLLBACK")
cek("setelah ROLLBACK seed utuh (pesanan, item)",
    (q("SELECT count(*) FROM pesanan")[0][0], q("SELECT count(*) FROM item_pesanan")[0][0]), (5, 6))

judul("F. Latihan 5: UNION vs UNION ALL")
cek("UNION ALL -> 4 baris", len(q("SELECT 'a' UNION ALL SELECT 'b' UNION ALL SELECT 'b' UNION ALL SELECT 'c'")), 4)
cek("UNION -> 3 baris", len(q("SELECT 'a' UNION SELECT 'b' UNION SELECT 'b' UNION SELECT 'c'")), 3)
cek("UNION juga membuang duplikat DI DALAM satu sisi", len(q("SELECT 1 UNION SELECT 1")), 1)

judul("G. Latihan 6: GROUP BY dengan kolom bukan agregat")
hasil = q("SELECT c.id, c.nama, p.status, count(*) FROM pelanggan c JOIN pesanan p ON p.pelanggan_id = c.id GROUP BY c.id")
print("[CATATAN] SQLite MENERIMA query ini (kolom p.status dipilih sembarang per grup), "
      f"dan menghasilkan {len(hasil)} baris.")
print("          PostgreSQL MENOLAK: column \"p.status\" must appear in the GROUP BY clause or be used in an aggregate function.")
print("          Jadi penolakan ini tidak bisa dibuktikan di SQLite. Hanya perbaikannya yang diuji:")
cek("GROUP BY c.id, c.nama (valid di semua DBMS)",
    q("SELECT c.id, c.nama, count(p.id) FROM pelanggan c LEFT JOIN pesanan p ON p.pelanggan_id = c.id GROUP BY c.id, c.nama ORDER BY c.id"),
    [(1, "Andi", 2), (2, "Budi", 1), (3, "Citra", 1), (4, "Dedi", 1)])

print(f"\nSemua {TOTAL} pemeriksaan sesuai harapan.")
