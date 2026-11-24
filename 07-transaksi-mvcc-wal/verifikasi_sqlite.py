# verifikasi_sqlite.py
# Memverifikasi LOGIKA Latihan 1 (SAVEPOINT) dan Atomicity dengan SQLite.
# Yang TIDAK bisa diwakili SQLite: MVCC (xmin/xmax/ctid), isolation level, row locking,
# SKIP LOCKED, deadlock, WAL/LSN, bloat. Semua itu khas PostgreSQL dan berlabel
# (diharapkan) di jawaban; skenario dua sesinya ada di dua_sesi.sh.
#
# Pengganti kegagalan "numeric field overflow" PostgreSQL pada numeric(12,2):
# di SQLite dipakai CHECK (saldo <= 9999999999.99) agar penambahan ke Citra gagal.
import sqlite3

TOTAL = 0


def cek(label, aktual, harapan):
    global TOTAL
    TOTAL += 1
    ok = aktual == harapan
    print(f"[{'OK' if ok else 'GAGAL'}] {label}\n       aktual   : {aktual}\n       harapan  : {harapan}")
    assert ok, label


def baru():
    db = sqlite3.connect(":memory:", isolation_level=None)
    db.executescript("""
    CREATE TABLE rekening (id INTEGER PRIMARY KEY, pemilik TEXT,
        saldo NUMERIC CHECK (saldo >= 0 AND saldo <= 9999999999.99));
    CREATE TABLE log_transfer (id INTEGER PRIMARY KEY AUTOINCREMENT, dari INT NOT NULL, ke INT NOT NULL,
        jumlah NUMERIC NOT NULL, status TEXT NOT NULL CHECK (status IN ('berhasil','gagal')), pesan TEXT);
    INSERT INTO rekening VALUES (1,'Andi',500000),(2,'Budi',100000),(3,'Citra',9999999999.99);
    """)
    return db


def saldo(db):
    return [(i, round(s, 2)) for i, s in db.execute("SELECT id, saldo FROM rekening ORDER BY id")]


def gagal(db, sql):
    try:
        db.execute(sql)
        return False
    except sqlite3.IntegrityError:
        return True


print("=" * 78 + "\nA. Praktik: Atomicity\n" + "=" * 78)
db = baru()
db.execute("DELETE FROM rekening WHERE id = 3")
db.execute("BEGIN")
cek("UPDATE pertama melanggar CHECK saldo >= 0", gagal(db, "UPDATE rekening SET saldo = saldo - 600000 WHERE id = 1"), True)
kedua = not gagal(db, "UPDATE rekening SET saldo = saldo + 600000 WHERE id = 2")
print("[CATATAN] PERBEDAAN dengan PostgreSQL: di SQLite UPDATE kedua DITERIMA setelah error "
      f"(diterima = {kedua}).\n          Di PostgreSQL transaksi masuk status 'aborted' dan UPDATE kedua ditolak "
      "('current transaction is aborted').\n          Itu tidak bisa dibuktikan di sini.")
assert kedua
db.execute("ROLLBACK")
cek("setelah ROLLBACK tidak ada yang berubah", saldo(db), [(1, 500000.0), (2, 100000.0)])

print("\n" + "=" * 78 + "\nB. Latihan 1: transfer dengan SAVEPOINT\n" + "=" * 78)
db = baru()
db.execute("BEGIN")
db.execute("SAVEPOINT sebelum_transfer")
db.execute("UPDATE rekening SET saldo = saldo - 100000 WHERE id = 1")
db.execute("UPDATE rekening SET saldo = saldo + 100000 WHERE id = 2")
db.execute("INSERT INTO log_transfer (dari, ke, jumlah, status) VALUES (1,2,100000,'berhasil')")
db.execute("RELEASE SAVEPOINT sebelum_transfer")
db.execute("COMMIT")
cek("transfer 1 berhasil", saldo(db), [(1, 400000.0), (2, 200000.0), (3, 9999999999.99)])

db.execute("BEGIN")
db.execute("SAVEPOINT sebelum_transfer")
db.execute("UPDATE rekening SET saldo = saldo - 100000 WHERE id = 1")
cek("penambahan ke Citra gagal (di luar batas)", gagal(db, "UPDATE rekening SET saldo = saldo + 100000 WHERE id = 3"), True)
db.execute("ROLLBACK TO SAVEPOINT sebelum_transfer")
db.execute("INSERT INTO log_transfer (dari, ke, jumlah, status, pesan) "
           "VALUES (1,3,100000,'gagal','kredit ditolak')")
db.execute("COMMIT")
cek("pengurangan Andi ikut dibatalkan; saldo tidak berubah", saldo(db),
    [(1, 400000.0), (2, 200000.0), (3, 9999999999.99)])
cek("log mencatat kedua percobaan, yang gagal tetap tersimpan",
    [(d, k, s) for d, k, s in db.execute("SELECT dari, ke, status FROM log_transfer ORDER BY id")],
    [(1, 2, "berhasil"), (1, 3, "gagal")])

print("\n" + "=" * 78 + "\nC. Jebakan: SAVEPOINT diletakkan SESUDAH pengurangan\n" + "=" * 78)
db = baru()
total_awal = round(sum(s for _, s in saldo(db)), 2)
db.execute("BEGIN")
db.execute("UPDATE rekening SET saldo = saldo - 100000 WHERE id = 1")
db.execute("SAVEPOINT setelah_debit")                       # salah tempat
gagal(db, "UPDATE rekening SET saldo = saldo + 100000 WHERE id = 3")
db.execute("ROLLBACK TO SAVEPOINT setelah_debit")           # hanya membatalkan penambahan
db.execute("COMMIT")
total_akhir = round(sum(s for _, s in saldo(db)), 2)
cek("uang hilang 100000 karena pengurangan tidak dibatalkan", round(total_awal - total_akhir, 2), 100000.0)

print(f"\nSemua {TOTAL} pemeriksaan sesuai harapan.")
