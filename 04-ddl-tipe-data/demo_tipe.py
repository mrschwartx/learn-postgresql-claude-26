# demo_tipe.py : analogi Python untuk Latihan 3 (numeric vs float, timestamptz vs timestamp).
# Ini BUKAN PostgreSQL. Ia menunjukkan akar masalah yang sama:
#  - float biner tidak bisa menyimpan 0.1 secara tepat; Decimal (seperti numeric) bisa.
#  - waktu tanpa zona ("naif") bermakna ganda; waktu dengan zona merujuk satu titik waktu.
from decimal import Decimal
from datetime import datetime
from zoneinfo import ZoneInfo

print("== Float vs Decimal (analog double precision vs numeric) ==")
print("0.1 + 0.2 == 0.3          float  :", 0.1 + 0.2 == 0.3, "|", repr(0.1 + 0.2))
print("0.1 + 0.2 == 0.3          Decimal:", Decimal("0.1") + Decimal("0.2") == Decimal("0.3"))
def jumlah_berurutan(nilai):
    """Penjumlahan satu per satu (+=). Catatan: sum() bawaan Python 3.12+ memakai
    penjumlahan terkompensasi yang menyembunyikan galat; di sini sengaja tidak dipakai."""
    total = nilai[0] * 0
    for n in nilai:
        total += n
    return total


f10 = jumlah_berurutan([0.1] * 10)
d10 = jumlah_berurutan([Decimal("0.1")] * 10)
print("jumlah 0.1 sebanyak 10x   float  :", repr(f10), "| == 1.0 ?", f10 == 1.0)
print("jumlah 0.1 sebanyak 10x   Decimal:", d10, "| == 1.0 ?", d10 == Decimal("1.0"))
f1000 = jumlah_berurutan([0.1] * 1000)
print("1000 transaksi Rp0,10     float  :", repr(f1000), "(selisih", repr(f1000 - 100), "dari 100)")
print("1000 transaksi Rp0,10     Decimal:", jumlah_berurutan([Decimal("0.1")] * 1000))

print()
print("== Waktu dengan zona vs tanpa zona (analog timestamptz vs timestamp) ==")
jkt, utc = ZoneInfo("Asia/Jakarta"), ZoneInfo("UTC")
aware = datetime(2026, 11, 23, 10, 0, tzinfo=jkt)          # titik waktu pasti
print("timestamptz (aware) di Jakarta:", aware.isoformat())
print("timestamptz (aware) di UTC     :", aware.astimezone(utc).isoformat(), "<- instan yang sama")
naif = datetime(2026, 11, 23, 10, 0)                        # jam dinding tanpa zona
print("timestamp (naif)               :", naif.isoformat(), "<- zona tidak diketahui")
print("Jika server A (WIB) dan server B (UTC) membaca '10:00' naif sebagai jam lokal masing-masing:")
print("  server A:", naif.replace(tzinfo=jkt).astimezone(utc).isoformat())
print("  server B:", naif.replace(tzinfo=utc).isoformat(), "<- selisih 7 jam untuk 'kejadian' yang sama")
