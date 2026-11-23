# demo_relasional.py
import sqlite3

db = sqlite3.connect(":memory:")
db.execute("PRAGMA foreign_keys = ON")   # SQLite mematikan FK secara default

db.executescript("""
CREATE TABLE pelanggan (
    id    INTEGER PRIMARY KEY,
    nama  TEXT NOT NULL,
    email TEXT UNIQUE NOT NULL
);
CREATE TABLE pesanan (
    id           INTEGER PRIMARY KEY,
    pelanggan_id INTEGER NOT NULL REFERENCES pelanggan(id),
    total        INTEGER CHECK (total >= 0)
);
INSERT INTO pelanggan (nama, email) VALUES ('Andi', 'andi@contoh.com');
""")

# 1) Pesanan untuk pelanggan yang tidak ada -> ditolak oleh FOREIGN KEY
try:
    db.execute("INSERT INTO pesanan (pelanggan_id, total) VALUES (999, 100)")
except sqlite3.IntegrityError as e:
    print("FK menolak:", e)

# 2) Email duplikat -> ditolak oleh UNIQUE
try:
    db.execute("INSERT INTO pelanggan (nama, email) VALUES ('Budi', 'andi@contoh.com')")
except sqlite3.IntegrityError as e:
    print("UNIQUE menolak:", e)

# 3) Total negatif -> ditolak oleh CHECK
try:
    db.execute("INSERT INTO pesanan (pelanggan_id, total) VALUES (1, -5)")
except sqlite3.IntegrityError as e:
    print("CHECK menolak:", e)
