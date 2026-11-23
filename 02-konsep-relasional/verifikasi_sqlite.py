# verifikasi_sqlite.py
# Menguji LOGIKA constraint dari rancangan_toko.sql dan rancangan_perpustakaan.sql.
# PostgreSQL tidak dipakai di sini: berkas .sql (dialek PostgreSQL) disalin otomatis
# ke dialek SQLite (identity -> INTEGER PRIMARY KEY, timestamptz -> TEXT, dst.).
# Jadi ini bukti perilaku constraint, BUKAN bukti DDL-nya valid di PostgreSQL
# (itu diuji di Modul 4).
import re
import sqlite3
from pathlib import Path

DIR = Path(__file__).parent


def ke_sqlite(sql: str) -> str:
    sql = sql.replace("current_date", "CURRENT_DATE").replace("now()", "CURRENT_TIMESTAMP")
    sql = sql.replace("bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY", "INTEGER PRIMARY KEY")
    sql = re.sub(r"numeric\(\d+,\s*\d+\)", "NUMERIC", sql)
    sql = sql.replace("bigint", "INTEGER").replace("timestamptz", "TEXT")
    sql = re.sub(r"\bdate\b", "TEXT", sql)
    return sql


def db_dari(berkas: str) -> sqlite3.Connection:
    db = sqlite3.connect(":memory:")
    db.execute("PRAGMA foreign_keys = ON")
    db.executescript(ke_sqlite((DIR / berkas).read_text()))
    return db


def coba(db, label, sql, params=(), harapan="ditolak"):
    try:
        db.execute(sql, params)
        hasil = "lolos"
    except sqlite3.IntegrityError as e:
        hasil = f"ditolak ({e})"
    ok = hasil.startswith(harapan)
    print(f"[{'OK' if ok else 'GAGAL'}] {label:<58} -> {hasil}")
    assert ok, f"harapan {harapan}, hasil {hasil}"


# ------------------------------------------------------------------ Bagian A
print("=" * 78)
print("A. Latihan 2 & 3: logika NULL (tiga nilai)")
print("=" * 78)
db = sqlite3.connect(":memory:")
db.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, email TEXT)")
db.executemany("INSERT INTO t (email) VALUES (?)", [("a@x.com",), (None,), ("b@x.com",), (None,)])
q = lambda s: db.execute(s).fetchall()
print("WHERE email = NULL     ->", len(q("SELECT * FROM t WHERE email = NULL")), "baris")
print("WHERE email IS NULL    ->", len(q("SELECT * FROM t WHERE email IS NULL")), "baris")
print("WHERE email <> 'a@x.com' ->", len(q("SELECT * FROM t WHERE email <> 'a@x.com'")),
      "baris (baris NULL ikut tersaring)")
print("WHERE email IS DISTINCT FROM 'a@x.com' (SQLite: IS NOT) ->",
      len(q("SELECT * FROM t WHERE email IS NOT 'a@x.com'")), "baris")
assert len(q("SELECT * FROM t WHERE email = NULL")) == 0
assert len(q("SELECT * FROM t WHERE email IS NULL")) == 2
assert len(q("SELECT * FROM t WHERE email <> 'a@x.com'")) == 1
assert len(q("SELECT * FROM t WHERE email IS NOT 'a@x.com'")) == 3
print()
for label, sql in [
    ("NULL OR TRUE", "SELECT NULL OR 1"),
    ("NULL AND FALSE", "SELECT NULL AND 0"),
    ("COALESCE(NULL, NULL, 3)", "SELECT COALESCE(NULL, NULL, 3)"),
    ("NULL IS DISTINCT FROM NULL (SQLite: NULL IS NOT NULL)", "SELECT NULL IS NOT NULL"),
    ("NULL = NULL", "SELECT NULL = NULL"),
    ("TRUE AND NULL", "SELECT 1 AND NULL"),
    ("FALSE AND NULL", "SELECT 0 AND NULL"),
    ("5 + NULL", "SELECT 5 + NULL"),
]:
    print(f"{label:<55} -> {q(sql)[0][0]!r}   (None = NULL, 1 = true, 0 = false)")

# ------------------------------------------------------------------ Bagian B
print()
print("=" * 78)
print("B. Praktik: Analisis rancangan toko")
print("=" * 78)
db = db_dari("rancangan_toko.sql")
db.executescript("""
INSERT INTO pelanggan (nama, email) VALUES ('Andi','andi@contoh.com');
INSERT INTO produk (nama, harga, stok) VALUES ('Keyboard', 250000, 10), ('Mouse', 100000, 5);
INSERT INTO pesanan (pelanggan_id) VALUES (1);
INSERT INTO item_pesanan VALUES (1, 1, 1), (1, 2, 2);
""")
print("Pertanyaan 1: PK komposit")
coba(db, "produk yang sama dimasukkan dua kali ke pesanan sama", "INSERT INTO item_pesanan VALUES (1, 1, 3)")
db.execute("INSERT INTO pesanan (pelanggan_id) VALUES (1)")
coba(db, "produk yang sama di pesanan 2 (valid)", "INSERT INTO item_pesanan VALUES (2, 1, 3)", harapan="lolos")
print("\nPertanyaan 2: ON DELETE CASCADE")
n0 = db.execute("SELECT COUNT(*) FROM item_pesanan WHERE pesanan_id = 1").fetchone()[0]
db.execute("DELETE FROM pesanan WHERE id = 1")
n1 = db.execute("SELECT COUNT(*) FROM item_pesanan WHERE pesanan_id = 1").fetchone()[0]
print(f"item_pesanan milik pesanan 1: sebelum hapus={n0}, sesudah hapus={n1}")
assert (n0, n1) == (2, 0)
coba(db, "hapus produk yang masih ada di item_pesanan (tanpa CASCADE)", "DELETE FROM produk WHERE id = 1")
coba(db, "hapus pelanggan yang masih punya pesanan (tanpa CASCADE)", "DELETE FROM pelanggan WHERE id = 1")
print("\nPertanyaan 3: constraint pencegah data tidak valid")
coba(db, "stok negatif", "UPDATE produk SET stok = -1 WHERE id = 2")
coba(db, "jumlah = 0", "INSERT INTO item_pesanan VALUES (2, 2, 0)")
coba(db, "jumlah negatif", "INSERT INTO item_pesanan VALUES (2, 2, -3)")
coba(db, "harga negatif", "INSERT INTO produk (nama, harga) VALUES ('X', -1)")
coba(db, "email duplikat", "INSERT INTO pelanggan (nama, email) VALUES ('Budi','andi@contoh.com')")
coba(db, "nama pelanggan NULL", "INSERT INTO pelanggan (nama, email) VALUES (NULL,'z@x.com')")
coba(db, "pesanan untuk pelanggan tidak ada", "INSERT INTO pesanan (pelanggan_id) VALUES (999)")
print("\nCelah rancangan (SENGAJA lolos, lihat jawaban):")
coba(db, "status pesanan bebas ('asal-asalan')", "INSERT INTO pesanan (pelanggan_id, status) VALUES (1, 'asal-asalan')", harapan="lolos")

# ------------------------------------------------------------------ Bagian C
print()
print("=" * 78)
print("C. Latihan 4: rancangan perpustakaan")
print("=" * 78)
db = db_dari("rancangan_perpustakaan.sql")
db.executescript("""
INSERT INTO penulis (nama, negara) VALUES ('Pramoedya Ananta Toer','Indonesia'), ('Penulis Kedua','Indonesia');
INSERT INTO buku (isbn, judul, tahun_terbit) VALUES ('9789799731234','Bumi Manusia',1980);
INSERT INTO buku_penulis VALUES (1, 1, 1), (1, 2, 2);
INSERT INTO eksemplar (buku_id, barcode) VALUES (1,'BC-001'), (1,'BC-002');
INSERT INTO anggota (nomor_anggota, nama, email) VALUES ('A-0001','Sari','sari@contoh.com'), ('A-0002','Dewi','dewi@contoh.com');
INSERT INTO peminjaman (anggota_id, eksemplar_id, tanggal_pinjam, jatuh_tempo) VALUES (1, 1, '2026-11-01', '2026-11-15');
""")
print("Data valid masuk. Sekarang uji penolakan:")
coba(db, "ISBN bukan 13 karakter", "INSERT INTO buku (isbn, judul, tahun_terbit) VALUES ('123','X',2000)")
coba(db, "ISBN duplikat", "INSERT INTO buku (isbn, judul, tahun_terbit) VALUES ('9789799731234','Y',2001)")
coba(db, "tahun terbit tidak masuk akal (1200)", "INSERT INTO buku (isbn, judul, tahun_terbit) VALUES ('9789799731999','Z',1200)")
coba(db, "pasangan buku-penulis ganda (PK komposit)", "INSERT INTO buku_penulis VALUES (1, 1, 3)")
coba(db, "dua penulis dengan urutan sama", "INSERT INTO buku_penulis VALUES (1, 2, 1)")
coba(db, "eksemplar dengan kondisi tidak dikenal", "INSERT INTO eksemplar (buku_id, barcode, kondisi) VALUES (1,'BC-003','bagus')")
coba(db, "barcode duplikat", "INSERT INTO eksemplar (buku_id, barcode) VALUES (1,'BC-001')")
coba(db, "status anggota tidak valid", "INSERT INTO anggota (nomor_anggota, nama, email, status) VALUES ('A-3','Q','q@x.com','vip')")
coba(db, "email anggota duplikat", "INSERT INTO anggota (nomor_anggota, nama, email) VALUES ('A-4','R','sari@contoh.com')")
coba(db, "jatuh tempo sebelum tanggal pinjam",
     "INSERT INTO peminjaman (anggota_id, eksemplar_id, tanggal_pinjam, jatuh_tempo) VALUES (2,2,'2026-11-10','2026-11-01')")
coba(db, "tanggal kembali sebelum tanggal pinjam",
     "INSERT INTO peminjaman (anggota_id, eksemplar_id, tanggal_pinjam, jatuh_tempo, tanggal_kembali) VALUES (2,2,'2026-11-10','2026-11-20','2026-11-05')")
coba(db, "denda negatif",
     "INSERT INTO peminjaman (anggota_id, eksemplar_id, tanggal_pinjam, jatuh_tempo, denda) VALUES (2,2,'2026-11-10','2026-11-20',-1)")
coba(db, "eksemplar 1 dipinjam lagi padahal belum kembali (partial unique)",
     "INSERT INTO peminjaman (anggota_id, eksemplar_id, tanggal_pinjam, jatuh_tempo) VALUES (2,1,'2026-11-05','2026-11-19')")
db.execute("UPDATE peminjaman SET tanggal_kembali = '2026-11-12' WHERE id = 1")
coba(db, "setelah dikembalikan, eksemplar 1 boleh dipinjam lagi",
     "INSERT INTO peminjaman (anggota_id, eksemplar_id, tanggal_pinjam, jatuh_tempo) VALUES (2,1,'2026-11-13','2026-11-27')", harapan="lolos")
coba(db, "hapus anggota yang punya riwayat pinjam (RESTRICT)", "DELETE FROM anggota WHERE id = 2")
coba(db, "hapus penulis yang masih dipakai buku (RESTRICT)", "DELETE FROM penulis WHERE id = 1")
coba(db, "hapus buku yang masih punya eksemplar (RESTRICT)", "DELETE FROM buku WHERE id = 1")
print("\nSemua pengujian sesuai harapan.")
