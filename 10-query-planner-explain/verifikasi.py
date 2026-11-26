# verifikasi.py
# Modul 10 hampir seluruhnya tentang membaca keluaran planner PostgreSQL, yang TIDAK bisa
# dijalankan di sini. Yang bisa dibuktikan hanyalah konsep di bawahnya:
#   A. [SIMULASI] algoritma join (nested loop, hash, merge) menghasilkan hasil yang sama tetapi
#      jumlah kerja berbeda menurut ukuran data. Ini MODEL SEDERHANA, bukan model biaya PostgreSQL.
#   B. [SIMULASI] top-N heap sama dengan sort + LIMIT tetapi hanya menyimpan N baris.
#   C. [SIMULASI] aritmetika estimasi 'rows' saat statistik usang (pendekatan model selektivitas).
#   D. [SQLite]   fungsi/cast pada kolom membuat index tak terpakai; index komposit + kolom
#                 tambahan menghasilkan covering index. (Planner SQLite, bukan PostgreSQL.)
# TIDAK diuji: format EXPLAIN, cost, waktu, Buffers, Sort Method, nama node PostgreSQL.
import bisect
import heapq
import random
import sqlite3
from collections import defaultdict

random.seed(10)
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


# ---------------------------------------------------------------- A
judul("A. Tiga algoritma join: hasil sama, jumlah kerja berbeda [SIMULASI]")


def nested_loop(R, S):                       # tanpa index pada S
    kerja, hasil = 0, []
    for r in R:
        for s in S:
            kerja += 1
            if r[0] == s[0]:
                hasil.append((r, s))
    return hasil, kerja


def nested_loop_index(R, S_urut, kunci_S):   # index (array terurut) pada S
    kerja, hasil = 0, []
    for r in R:
        i = bisect.bisect_left(kunci_S, r[0])
        kerja += max(1, len(kunci_S).bit_length())      # turun pohon ≈ log2(n)
        while i < len(kunci_S) and kunci_S[i] == r[0]:
            hasil.append((r, S_urut[i]))
            kerja += 1
            i += 1
    return hasil, kerja


def hash_join(R, S):                         # bangun hash dari S (sisi kecil), probe dengan R
    kerja, tabel, hasil = 0, defaultdict(list), []
    for s in S:
        tabel[s[0]].append(s)
        kerja += 1
    for r in R:
        kerja += 1
        for s in tabel.get(r[0], ()):
            hasil.append((r, s))
    return hasil, kerja


def merge_join(R, S, sudah_urut=False):
    kerja = 0
    if not sudah_urut:
        R, S = sorted(R), sorted(S)
        kerja += len(R) * max(1, len(R).bit_length()) + len(S) * max(1, len(S).bit_length())
    i = j = 0
    hasil = []
    while i < len(R) and j < len(S):
        kerja += 1
        if R[i][0] < S[j][0]:
            i += 1
        elif R[i][0] > S[j][0]:
            j += 1
        else:
            k = j
            while k < len(S) and S[k][0] == R[i][0]:
                hasil.append((R[i], S[k]))
                k += 1
            i += 1
    return hasil, kerja


def semua(R, S, urut=False):
    Su = sorted(S)
    kunci = [s[0] for s in Su]
    out = {"nested loop (tanpa index)": nested_loop(R, S),
           "nested loop + index": nested_loop_index(R, Su, kunci),
           "hash join": hash_join(R, S),
           "merge join": merge_join(sorted(R) if urut else R, Su if urut else S, sudah_urut=urut)}
    himpunan = {k: sorted(h) for k, (h, _) in out.items()}
    ref = next(iter(himpunan.values()))
    assert all(v == ref for v in himpunan.values()), "hasil join berbeda antar algoritma"
    return {k: w for k, (_, w) in out.items()}, len(ref)


# Skenario 1: sisi luar sangat kecil (4 baris), sisi dalam besar ber-index (±100 baris cocok per kunci)
S1_S = [(k, f"t{k}-{n}") for k in range(1, 3001) for n in range(40)]
S1_R = [(k, f"p{k}") for k in range(1, 5)]
w1, n1 = semua(S1_R, S1_S)
print(f"skenario 1 (luar 4 baris, dalam {len(S1_S):,} baris, {n1} hasil):", w1)
cek("skenario 1: nested loop + index paling sedikit kerja", min(w1, key=w1.get), "nested loop + index", " [SIMULASI]")

# Skenario 2: sisi luar besar, sisi dalam kecil unik, tidak terurut (join 'besar' tanpa urutan)
S2_R = [(random.randint(1, 1000), f"r{i}") for i in range(20000)]
S2_S = [(k, f"s{k}") for k in range(1, 1001)]
random.shuffle(S2_S)
w2, n2 = semua(S2_R, S2_S)
print(f"skenario 2 (luar {len(S2_R):,}, dalam {len(S2_S):,} unik, {n2:,} hasil):", w2)
cek("skenario 2: hash join paling sedikit kerja", min(w2, key=w2.get), "hash join", " [SIMULASI]")
cek_benar("skenario 2: nested loop tanpa index jauh terburuk", max(w2, key=w2.get) == "nested loop (tanpa index)" and w2["nested loop (tanpa index)"] > 100 * w2["hash join"],
          f"{w2['nested loop (tanpa index)']:,} vs hash {w2['hash join']:,}", " [SIMULASI]")

# Skenario 3: kedua sisi SUDAH terurut (mis. dari index) dan keduanya besar
S3_R = sorted((random.randint(1, 5000), f"r{i}") for i in range(20000))
S3_S = [(k, f"s{k}") for k in range(1, 5001)]
w3, n3 = semua(S3_R, S3_S, urut=True)
print(f"skenario 3 (keduanya terurut, {n3:,} hasil):", w3)
cek_benar("skenario 3: merge join sama murahnya dengan hash join (satu kali lewat), tanpa tabel hash di memori",
          w3["merge join"] <= w3["hash join"] and w3["merge join"] < w3["nested loop + index"],
          f"merge {w3['merge join']:,}, hash {w3['hash join']:,}, nested loop+index {w3['nested loop + index']:,}", " [SIMULASI]")
w3b, _ = semua(S3_R, S3_S, urut=False)
cek_benar("jika data belum terurut, merge join harus mengurutkan dulu (lebih mahal daripada hash join)",
          w3b["merge join"] > w3b["hash join"], f"merge {w3b['merge join']:,} vs hash {w3b['hash join']:,}", " [SIMULASI]")

# ---------------------------------------------------------------- B
judul("B. Top-N heap vs sort penuh [SIMULASI]")
data = [random.random() for _ in range(200_000)]
N = 1000
via_sort = sorted(data, reverse=True)[:N]
heap = []
puncak = 0
for x in data:
    if len(heap) < N:
        heapq.heappush(heap, x)
    elif x > heap[0]:
        heapq.heapreplace(heap, x)
    puncak = max(puncak, len(heap))
cek("hasil top-N heap = sort lalu LIMIT", sorted(heap, reverse=True), via_sort, " [SIMULASI]")
cek_benar("heap hanya menyimpan N baris di memori, sort penuh menyimpan semuanya",
          puncak == N and len(data) == 200_000, f"heap puncak {puncak:,} baris vs sort penuh {len(data):,} baris", " [SIMULASI]")

# ---------------------------------------------------------------- C
judul("C. Aritmetika estimasi 'rows' dengan statistik usang [SIMULASI, pendekatan]")
# Rumus data Praktik Modul 9: (random()*10000)::int + 1
awal = [round(random.random() * 10000) + 1 for _ in range(1_000_000)]
cacah = defaultdict(int)
for v in awal:
    cacah[v] += 1
n_distinct = len(cacah)
n_mcv = 100                                                    # default_statistics_target = 100
mcv = sorted(cacah.items(), key=lambda kv: -kv[1])[:n_mcv]
mcv_nilai = {k for k, _ in mcv}
frek_mcv = sum(v for _, v in mcv) / len(awal)
nilai1_awal = cacah[1]
print(f"n_distinct ≈ {n_distinct:,}; baris dengan pelanggan_id=1 semula: {nilai1_awal}; apakah masuk MCV: {1 in mcv_nilai}")
est_non_mcv = (1 - frek_mcv) / (n_distinct - n_mcv)             # selektivitas nilai non-MCV
baris_sekarang = 1_200_000                                      # planner memakai ukuran tabel SEKARANG
est_usang = baris_sekarang * est_non_mcv
aktual = nilai1_awal + 200_000
print(f"estimasi dengan statistik USANG ≈ {est_usang:,.0f} baris; aktual = {aktual:,}")
cek_benar("nilai 1 jarang (setengah bobot karena pembulatan) sehingga bukan MCV", 1 not in mcv_nilai and nilai1_awal < 80, f"{nilai1_awal} baris", " [SIMULASI]")
cek_benar("estimasi usang kira-kira 100-150 baris, jauh di bawah aktual (rasio > 1000x)",
          90 < est_usang < 160 and aktual / est_usang > 1000, f"estimasi ≈ {est_usang:,.0f}, aktual {aktual:,}, rasio {aktual/est_usang:,.0f}x", " [SIMULASI]")
frek_baru = aktual / 1_200_000
cek_benar("setelah ANALYZE nilai 1 ±16,7% baris, masuk MCV, estimasi ≈ aktual", 0.16 < frek_baru < 0.17, f"{frek_baru:.3%} dari 1,2 juta ≈ {frek_baru*baris_sekarang:,.0f} baris", " [SIMULASI]")
ambang = 50 + 0.1 * 1_000_000
cek("ambang autovacuum ANALYZE untuk 1 juta baris (default 50 + 0,1 x baris)", ambang, 100050.0, " [hitungan]")
cek_benar("200.000 baris baru melewati ambang, jadi autovacuum akan meng-ANALYZE pada siklus berikutnya (itu sebabnya demo mematikan autovacuum pada tabel uji)",
          200_000 > ambang, "200.000 > 100.050", " [hitungan]")

# ---------------------------------------------------------------- D
judul("D. Sargable dan covering (planner SQLite, hanya konsep)")
db = sqlite3.connect(":memory:")
db.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, pelanggan_id INT, status TEXT, total INT, dibuat_pada TEXT)")
db.executemany("INSERT INTO t VALUES (?,?,?,?,?)",
               [(i, random.randint(1, 10000), random.choice(["baru", "dibayar", "selesai"]), random.randint(1, 10**6),
                 f"2026-{random.randint(1, 11):02d}-{random.randint(1, 28):02d}") for i in range(1, 100_001)])
rencana = lambda q: " | ".join(r[3] for r in db.execute("EXPLAIN QUERY PLAN " + q))
db.execute("CREATE INDEX i_waktu ON t (dibuat_pada)")
cek("fungsi pada kolom ber-index: tidak bisa memakai index", rencana("SELECT * FROM t WHERE date(dibuat_pada) >= '2026-10-01'"), "SCAN t", " [SQLite]")
cek("ditulis ulang tanpa fungsi pada kolom: memakai index", rencana("SELECT * FROM t WHERE dibuat_pada >= '2026-10-01'"),
    "SEARCH t USING INDEX i_waktu (dibuat_pada>?)", " [SQLite]")
db.execute("CREATE INDEX i_opt ON t (pelanggan_id, status, dibuat_pada, total)")   # SQLite tak punya INCLUDE
Q = "SELECT dibuat_pada, sum(total) FROM t WHERE pelanggan_id = 4242 AND status = 'selesai' AND dibuat_pada >= '2026-08-01' GROUP BY 1 ORDER BY 1"
r = rencana(Q)
cek_benar("query Latihan 4: kesamaan dulu, rentang terakhir, covering index", r.startswith("SEARCH t USING COVERING INDEX i_opt (pelanggan_id=? AND status=? AND dibuat_pada>?)"), r, " [SQLite]")

print(f"\nSemua {TOTAL} pemeriksaan sesuai harapan.")
