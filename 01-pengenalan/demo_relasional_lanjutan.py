# demo_relasional_lanjutan.py  -- Jawaban Latihan 5 (dan demo pendukung Latihan 3)
import sqlite3


def koneksi():
    db = sqlite3.connect(":memory:")
    db.execute("PRAGMA foreign_keys = ON")   # SQLite mematikan FK secara default
    return db


def skema(db, on_delete_pesanan="", pelanggan_nullable=False):
    """Buat skema pelanggan -> pesanan -> item_pesanan <- produk.
    on_delete_pesanan = klausa ON DELETE untuk FK pesanan.pelanggan_id."""
    not_null = "" if pelanggan_nullable else "NOT NULL"
    db.executescript(f"""
    CREATE TABLE pelanggan (
        id    INTEGER PRIMARY KEY,
        nama  TEXT NOT NULL,
        email TEXT UNIQUE NOT NULL
    );
    CREATE TABLE produk (
        id    INTEGER PRIMARY KEY,
        nama  TEXT NOT NULL,
        harga INTEGER NOT NULL CHECK (harga >= 0),
        stok  INTEGER NOT NULL DEFAULT 0 CHECK (stok >= 0)
    );
    CREATE TABLE pesanan (
        id           INTEGER PRIMARY KEY,
        pelanggan_id INTEGER {not_null} REFERENCES pelanggan(id) {on_delete_pesanan},
        total        INTEGER NOT NULL DEFAULT 0 CHECK (total >= 0)
    );
    CREATE TABLE item_pesanan (
        id         INTEGER PRIMARY KEY,
        pesanan_id INTEGER NOT NULL REFERENCES pesanan(id) ON DELETE CASCADE,
        produk_id  INTEGER NOT NULL REFERENCES produk(id),
        jumlah     INTEGER NOT NULL CHECK (jumlah > 0)
    );
    INSERT INTO pelanggan (nama, email) VALUES ('Andi', 'andi@contoh.com');
    INSERT INTO produk (nama, harga, stok) VALUES ('Keyboard', 250000, 10), ('Mouse', 100000, 5);
    INSERT INTO pesanan (pelanggan_id, total) VALUES (1, 450000);
    INSERT INTO item_pesanan (pesanan_id, produk_id, jumlah) VALUES (1, 1, 1), (1, 2, 2);
    """)


def hitung(db, tabel):
    return db.execute(f"SELECT COUNT(*) FROM {tabel}").fetchone()[0]


print("=" * 60)
print("A. Hapus pelanggan yang masih punya pesanan (default = NO ACTION)")
print("=" * 60)
db = koneksi(); skema(db)
try:
    db.execute("DELETE FROM pelanggan WHERE id = 1")
except sqlite3.IntegrityError as e:
    print("DELETE ditolak:", e)
print("pelanggan tersisa:", hitung(db, "pelanggan"), "| pesanan tersisa:", hitung(db, "pesanan"))

# Juga: hapus produk yang sudah dipakai item_pesanan -> ditolak
try:
    db.execute("DELETE FROM produk WHERE id = 1")
except sqlite3.IntegrityError as e:
    print("DELETE produk ditolak:", e)

print()
print("=" * 60)
print("B. Perbandingan opsi ON DELETE pada pesanan.pelanggan_id")
print("=" * 60)
opsi = [
    ("NO ACTION (default)", "ON DELETE NO ACTION", False),
    ("RESTRICT",            "ON DELETE RESTRICT",  False),
    ("CASCADE",             "ON DELETE CASCADE",   False),
    ("SET NULL",            "ON DELETE SET NULL",  True),
    ("SET DEFAULT",         "ON DELETE SET DEFAULT", True),
]
for label, klausa, nullable in opsi:
    db = koneksi(); skema(db, klausa, nullable)
    try:
        db.execute("DELETE FROM pelanggan WHERE id = 1")
        hasil = "DELETE berhasil"
    except sqlite3.IntegrityError as e:
        hasil = f"DITOLAK ({e})"
    pel = db.execute("SELECT pelanggan_id FROM pesanan").fetchall()
    print(f"{label:<20} -> {hasil}")
    print(f"{'':<20}    pelanggan={hitung(db,'pelanggan')}, pesanan={hitung(db,'pesanan')}, "
          f"item_pesanan={hitung(db,'item_pesanan')}, pesanan.pelanggan_id={pel}")

print()
print("=" * 60)
print("C. Atomicity (Latihan 3): pesanan + kurangi stok dalam satu transaksi")
print("=" * 60)
db = koneksi(); skema(db)
db.isolation_level = None   # kendali transaksi manual (BEGIN/COMMIT/ROLLBACK eksplisit)


def checkout(db, produk_id, jumlah):
    try:
        db.execute("BEGIN")
        db.execute("INSERT INTO pesanan (pelanggan_id, total) VALUES (1, 0)")
        pid = db.execute("SELECT last_insert_rowid()").fetchone()[0]
        db.execute("INSERT INTO item_pesanan (pesanan_id, produk_id, jumlah) VALUES (?,?,?)",
                   (pid, produk_id, jumlah))
        db.execute("UPDATE produk SET stok = stok - ? WHERE id = ?", (jumlah, produk_id))  # CHECK stok >= 0
        db.execute("COMMIT")
        return "COMMIT"
    except sqlite3.IntegrityError as e:
        db.execute("ROLLBACK")
        return f"ROLLBACK ({e})"


def snapshot():
    stok = db.execute("SELECT stok FROM produk WHERE id=2").fetchone()[0]
    return f"pesanan={hitung(db,'pesanan')}, item_pesanan={hitung(db,'item_pesanan')}, stok Mouse={stok}"


print("awal                      :", snapshot())
print("beli 2 Mouse (stok 5)     :", checkout(db, 2, 2), "->", snapshot())
print("beli 9 Mouse (stok cuma 3):", checkout(db, 2, 9), "->", snapshot())
print("Perhatikan: setelah gagal, pesanan & item_pesanan TIDAK ikut tersimpan (all-or-nothing).")
