# Jawaban Modul 9: Index

## Status eksekusi (baca dulu)

PostgreSQL dan Docker tidak tersedia di lingkungan saya, jadi **tidak ada perintah di modul ini yang sudah dijalankan di PostgreSQL**. Modul ini paling bergantung pada planner, ukuran, dan waktu eksekusi PostgreSQL, hal-hal yang tidak bisa ditiru SQLite. Karena itu saya membatasi klaim dengan ketat.

| Bagian | Status |
|---|---|
| **Konsep**: urutan kolom komposit dan *leftmost prefix*, partial index, expression index, covering index | **Diuji di SQLite** lewat `EXPLAIN QUERY PLAN` (ditandai `[SQLite]`). Itu planner SQLite, bukan PostgreSQL. Yang terbukti adalah konsepnya. |
| Distribusi data hasil rumus modul (mis. `status = 'baru'` ±12,5%) | **Diuji nyata** dengan rumus yang sama di Python |
| Arah waktu: index mempercepat baca, memperlambat tulis | Diuji di SQLite (hanya **arah**, angkanya milik SQLite) |
| Syarat BRIN (korelasi fisik) | **Simulasi Python** (`[SIMULASI]`), bukan BRIN PostgreSQL |
| Bitmap Scan, Index Only Scan, GIN, trigram, BRIN, hash, `EXPLAIN ANALYZE`, ukuran index, waktu | **Tidak bisa diuji.** Berlabel **(diharapkan)**. Angka ukuran dan waktu sengaja tidak saya tuliskan. |

Total **21 pemeriksaan, semuanya sesuai harapan** (`output_verifikasi_sqlite.txt`).

| Berkas | Fungsi |
|---|---|
| `praktik.sql` | Praktik, disalin langsung dari modul (isi tidak diubah) |
| `latihan.sql` | Latihan 1-7. Tiap latihan memakai **salinan tabelnya sendiri** agar tidak terpengaruh index Praktik. |
| `bersih_salinan.sql` | Menghapus **hanya** salinan uji dan objek bantu (`transaksi` tetap ada) |
| `bersih.sql` | Menghapus **semuanya**, termasuk `transaksi` |
| `jalankan.sh` | `praktik`, `latihan`, `salinan`, `bersih` |
| `verifikasi_sqlite.py`, `output_verifikasi_sqlite.txt` | Bukti konsep |

**Urutan:** `./jalankan.sh praktik` → `./jalankan.sh latihan`. **Peringatan sumber daya:** modul ini membuat tabel 1 juta baris plus beberapa salinan dan banyak index, jadi butuh beberapa menit dan ratusan MB disk. Waktu yang tercetak bergantung mesin dan cache, jadi ulangi 2-3 kali. Setelah selesai, jalankan `./jalankan.sh salinan` (bukan `bersih`) agar tabel `transaksi` tetap ada untuk Modul 10.

---

## Temuan dari membaca modul ini

Beberapa hal yang perlu diperhatikan sebelum menjalankan:

1. **`LIKE 'abc%'` pada B-Tree biasa hanya bekerja bila database ber-collation `C`.** Pada collation lain (umumnya `en_US.utf8`, yang lazim dipakai image Docker), prefix pencarian butuh operator class `text_pattern_ops`. Ini berdasarkan dokumentasi PostgreSQL, dan saya belum menguji di sini. `latihan.sql` (Latihan 4) memeriksa `datcollate` dan membuktikannya.
2. **Seq Scan 1 juta baris biasanya tampil sebagai `Gather` + `Parallel Seq Scan`**, bukan "Seq Scan" polos seperti di komentar modul. Itu masih pemindaian tabel penuh, hanya dibagi ke beberapa worker.
3. **Demo "hash tidak bisa dipakai untuk prefix" bisa tampak aneh.** Pada saat query `LIKE 'user500%'` dijalankan, index trigram GIN (`idx_trx_email_trgm`) dari bagian sebelumnya sudah ada. Index trigram juga melayani pola awalan, sehingga planner kemungkinan memakai Bitmap Scan pada index trigram. Itu bukan hash atau B-Tree, jadi jangan salah menyimpulkan.
4. **`EXPLAIN` tanpa `ANALYZE` tidak menjalankan query**, sehingga tidak menambah `idx_scan`. Index yang hanya "diuji" dengan `EXPLAIN` biasa (`idx_trx_pel_waktu`, `idx_trx_baru`, `idx_trx_email`) bisa tampak `idx_scan = 0` di audit akhir Praktik. Lihat Latihan 5.
5. **Distribusi data tidak seragam.** `(random()*4)::int + 1` membulatkan, sehingga `'baru'` dan `'batal'` masing-masing ±12,5% baris, sedangkan tiga status lain ±25% (terverifikasi: 12,5 / 12,6 / 25,0 / 25,0 / 24,8%). Itu menentukan ukuran partial index di Latihan 3. Demikian pula `pelanggan_id` berkisar 1 sampai 10001 (angka 10001 sangat jarang), ±100 baris per pelanggan.
6. **Tiga index ada pada `pelanggan_id`** setelah Praktik (`idx_trx_pelanggan`, `idx_trx_pel_waktu`, `idx_trx_cover`). `idx_trx_pelanggan` praktis redundan karena `idx_trx_pel_waktu` sudah mempunyai `pelanggan_id` sebagai kolom pertama.

---

## Praktik

**(diharapkan)**, ringkas per bagian:

| Bagian | Yang diharapkan |
|---|---|
| Data besar | `CREATE TABLE AS` 1 juta baris; ukuran total tabel puluhan sampai sekitar seratus MB (belum diukur) |
| Sebelum dan sesudah index | Sebelum: `Gather` + `Parallel Seq Scan`. Sesudah `idx_trx_pelanggan`: `Bitmap Index Scan` + `Bitmap Heap Scan` (atau `Index Scan`); query memilih ±100 baris, jadi waktu turun drastis. |
| Index komposit | `EXPLAIN` memakai `Index Scan using idx_trx_pel_waktu` dengan `Limit`, **tanpa node `Sort`** |
| Partial | `idx_trx_baru` dipakai karena `WHERE status = 'baru'` mengimplikasikan predikat index |
| Expression | `email = ...`: Seq Scan; `lower(email) = ...`: Index Scan atau Bitmap Scan via `idx_trx_email` |
| Covering | Setelah `VACUUM`: `Index Only Scan using idx_trx_cover` dengan `Heap Fetches: 0` atau sangat kecil |
| GIN JSONB | `Bitmap Index Scan on idx_dok_gin` untuk `@>` |
| Trigram | `LIKE '%er5000%'` memakai `idx_trx_email_trgm` (B-Tree biasa tidak bisa melayani pola tengah) |
| BRIN | Ukuran BRIN **jauh lebih kecil** daripada B-Tree (beda orde besar) |
| Hash | Ukuran hash dan B-Tree pada `email` (±20 karakter) tidak berbeda jauh; hash tidak dipakai untuk prefix dan rentang (lihat temuan nomor 3) |

---

## Latihan 1: Waktu baca dan harga saat tulis

`latihan.sql` memakai dua salinan `transaksi`: `trx_a` (tanpa index) dan `trx_b` (dengan index `pelanggan_id`), lalu mengukur 20 query berbeda pada tiap tabel dengan fungsi `uji_baca`. Untuk INSERT, dua tabel kosong (`trx_ins_a` tanpa index, `trx_ins_b` dengan index) masing-masing diisi 100.000 baris lewat `uji_insert`.

**Hasil di SQLite** (300.000 baris; hanya untuk menunjukkan **arah**, bukan angka PostgreSQL):

| Pengukuran | Tanpa index | Dengan index | Rasio |
|---|---|---|---|
| Baca (ms per query) | 8,227 | 0,013 | **631× lebih cepat** |
| INSERT 100.000 baris (ms) | 84 | 155 | **1,86× lebih lambat** |

Rencana eksekusi SQLite berubah dari `SCAN t` menjadi `SEARCH t USING INDEX ... (pelanggan_id=?)`.

**(diharapkan di PostgreSQL)**: baca turun dengan selisih sangat besar, karena query hanya memilih ±100 dari 1 juta baris (±0,01%), dan INSERT dengan index lebih lambat. Angka persisnya bergantung mesin dan tidak saya tuliskan; isi di lembar hasil.

**Mengapa INSERT lebih lambat dengan index:**

- Setiap baris baru harus **juga** disisipkan ke struktur B-Tree pada posisi yang tepat (mencari halaman daun, kadang membelah halaman), dan perubahan itu ikut ditulis ke WAL.
- Pekerjaan ini bertambah **per index**: lima index berarti lima penyisipan tambahan untuk setiap baris.
- Index juga memakan disk dan memori (*shared buffers*), sehingga menekan cache untuk data lain.

**Pertimbangan trade-off:** index menguntungkan beban kerja yang **baca-berat dengan query selektif**. Untuk beban tulis-berat atau tabel yang hampir selalu di-*scan* penuh, index tambahan lebih banyak merugikan. Untuk *bulk load* besar, praktik umum adalah memuat data dulu, lalu membuat index sesudahnya (satu pengurutan, jauh lebih murah daripada ribuan penyisipan satu per satu).

---

## Latihan 2: Urutan kolom index komposit

Dua index pada data yang sama (200.000 baris pertama):

- `idx_c` pada `(pelanggan_id, dibuat_pada DESC)`
- `idx_d` pada `(dibuat_pada, pelanggan_id)`

Query: `WHERE pelanggan_id = 5 ORDER BY dibuat_pada DESC LIMIT 10`.

**Terbukti di SQLite (konsep)**:

| Index | Rencana |
|---|---|
| `(pelanggan_id, dibuat_pada DESC)` | `SEARCH ... USING INDEX (pelanggan_id=?)`, tanpa langkah pengurutan tambahan |
| `(dibuat_pada, pelanggan_id)` | `SCAN ... USING INDEX`: seluruh index dipindai berurutan lalu disaring (tidak ada `SEARCH`) |
| `(dibuat_pada, pelanggan_id)`, query hanya `WHERE pelanggan_id = 5` | `SCAN` tabel penuh: index **tidak bisa dipakai** |

**(diharapkan di PostgreSQL):**

- `idx_c`: `Limit` → `Index Scan using idx_c` dengan `Index Cond: (pelanggan_id = 5)`, **tanpa `Sort`**. Index sudah menyimpan baris per pelanggan dalam urutan `dibuat_pada` menurun, sehingga 10 baris pertama langsung diambil.
- `idx_d`: salah satu dari dua kemungkinan. (a) memindai index mundur menurut `dibuat_pada` sambil menyaring `pelanggan_id = 5`, yang bisa membaca ribuan entri sebelum menemukan 10 baris (pelanggan ini hanya ±20 dari 200.000 baris, sehingga rata-rata separuh index terbaca); atau (b) Bitmap Scan lalu node `Sort`. Keduanya jauh lebih mahal daripada `idx_c`. PostgreSQL 18 memiliki *skip scan* untuk B-Tree, tetapi itu membantu bila kolom **pertama** berkardinalitas rendah. Di sini kolom pertama adalah `dibuat_pada` (hampir unik), sehingga tidak menolong.

**Aturan yang bisa diambil:**

1. Kolom yang dipakai dengan **kesamaan (`=`)** ditaruh **di depan**.
2. Kolom untuk **rentang atau pengurutan** ditaruh **sesudahnya**. Ia hanya bisa memanfaatkan urutan index bila semua kolom di depannya dibatasi dengan kesamaan.
3. Index hanya efektif bila query memakai kolom paling kiri (*leftmost prefix*). Menghilangkan kolom pertama membuat index tidak bisa dipakai untuk pencarian.
4. Bukan soal "kolom paling selektif dulu". Yang menentukan adalah bagaimana kolom itu dipakai di query.

---

## Latihan 3: Partial index untuk "pesanan belum dibayar"

Saya memakai status `'baru'` sebagai "belum dibayar":

```sql
CREATE INDEX idx_trx_baru ON transaksi (dibuat_pada) WHERE status = 'baru';
CREATE INDEX idx_trx_waktu_penuh ON transaksi (dibuat_pada);   -- pembanding (dihapus lagi di akhir)
```

**Ukuran.** Partial index hanya memuat baris berstatus `'baru'`, yaitu **±12,5%** baris (terverifikasi dengan rumus yang sama), sehingga ukurannya ±1/8 index penuh. Di SQLite (300.000 baris): partial 638.976 byte vs penuh 5.099.520 byte, **rasio 0,13**. **(diharapkan)** rasio serupa di PostgreSQL. Angka persisnya belum diukur. Hasil di PostgreSQL bisa sedikit bergeser karena struktur halaman dan *deduplication* B-Tree.

**Kapan dipakai** (terverifikasi di SQLite):

| Query | Hasil |
|---|---|
| `status = 'baru' AND dibuat_pada > ...` | Memakai partial index |
| `status = 'selesai' AND dibuat_pada > ...` | **Tidak bisa** memakainya (pemindaian tabel penuh) |

Aturannya: planner hanya memakai partial index bila `WHERE` query **mengimplikasikan** predikat index. Catatan tambahan: bila statusnya berupa parameter (`status = $1`) pada *generic plan* prepared statement, planner tidak bisa membuktikannya, sehingga partial index tidak dipakai. Pada *custom plan* nilainya diketahui dan index bisa dipakai.

**Manfaat:** index lebih kecil (hemat disk dan cache), penulisan lebih ringan (baris berstatus lain tidak menyentuh index), dan pencarian pada subset yang "panas" lebih cepat. **Cocok** bila query hampir selalu hanya mengincar subset kecil. Contohnya antrean pekerjaan, pesanan yang belum selesai, dan baris yang belum dihapus (*soft delete*). Partial index juga bisa dibuat `UNIQUE`, untuk aturan "unik hanya di antara baris aktif".

---

## Latihan 4: `lower(email)` dan expression index

```sql
CREATE INDEX idx_email_biasa ON trx_email (email);
EXPLAIN SELECT * FROM trx_email WHERE lower(email) = 'user500@contoh.com';   -- tidak memakai index
CREATE INDEX idx_email_lower ON trx_email (lower(email));
EXPLAIN SELECT * FROM trx_email WHERE lower(email) = 'user500@contoh.com';   -- memakai idx_email_lower
```

**Terbukti di SQLite**: dengan index biasa pada `email`, query `lower(email) = ...` menghasilkan `SCAN` penuh. Setelah expression index, menjadi `SEARCH ... USING INDEX il (<expr>=?)`. **(diharapkan di PostgreSQL)** `Seq Scan` sebelum, `Index Scan` atau `Bitmap Index Scan using idx_email_lower` sesudah.

**Mengapa index biasa tidak terpakai:** B-Tree pada `email` menyimpan nilai `email` apa adanya, terurut menurut nilai itu. `lower(email)` adalah nilai **hasil perhitungan** yang urutannya bisa berbeda. Index tidak bisa menjawab "mana baris yang `lower(email)`-nya sama dengan X" tanpa menghitung fungsi untuk semua baris. Expression index menyimpan hasil `lower(email)` itu sendiri.

**Syaratnya:** ekspresi di query harus **sama persis** dengan ekspresi di index. Fungsi di index juga harus `IMMUTABLE`.

**Tambahan: `LIKE` awalan.** `latihan.sql` juga menjalankan:

```sql
SELECT datcollate FROM pg_database WHERE datname = current_database();
EXPLAIN SELECT * FROM trx_email WHERE email LIKE 'user500%';              -- B-Tree biasa
CREATE INDEX idx_email_pattern ON trx_email (email text_pattern_ops);
EXPLAIN SELECT * FROM trx_email WHERE email LIKE 'user500%';              -- setelah text_pattern_ops
```

**(diharapkan)** Bila `datcollate` bukan `C`, query pertama tidak memakai `idx_email_biasa` (Seq Scan), dan baru memakai index setelah `text_pattern_ops`. Bila `C`, index biasa sudah cukup. Hasil query `datcollate` menentukan mana yang berlaku di mesin Anda.

---

## Latihan 5: Index yang tidak pernah dipakai

```sql
SELECT ui.schemaname, ui.relname, ui.indexrelname, ui.idx_scan,
       pg_size_pretty(pg_relation_size(ui.indexrelid)) AS ukuran,
       i.indisunique AS unik, i.indisprimary AS pk
FROM pg_stat_user_indexes ui
JOIN pg_index i ON i.indexrelid = ui.indexrelid
WHERE ui.idx_scan = 0
ORDER BY pg_relation_size(ui.indexrelid) DESC;
```

**Mengapa jangan langsung `DROP`:**

| Risiko | Penjelasan |
|---|---|
| **Statistik baru direset atau belum cukup lama** | `idx_scan = 0` hanya berarti "belum dipakai sejak statistik dimulai". Cek `pg_stat_database.stats_reset`. Statistik bisa hilang setelah crash recovery atau reset manual. |
| **Index dipakai di replika, bukan di primary** | Statistik dicatat per server. Query baca yang diarahkan ke standby tidak menaikkan `idx_scan` di primary. |
| **Query langka tetapi penting** | Laporan bulanan, tahunan, atau akhir kuartal bisa saja memakai index yang tampak "mati" selama minggu-minggu biasa. |
| **Menegakkan constraint** | Index `UNIQUE` dan primary key tidak dipakai "untuk dibaca" tetapi mencegah duplikat. Jangan dihapus hanya karena `idx_scan = 0`. Karena itu kolom `unik` dan `pk` ikut ditampilkan, dan kueri "kandidat" di `latihan.sql` mengecualikan keduanya. |
| **Mendukung foreign key** | Index pada kolom FK di tabel anak mempercepat penghapusan atau pembaruan di tabel induk. Pemakaiannya bisa jarang tetapi kritis. |
| **Tidak bisa di-undo cepat** | Membuat ulang index besar memakan waktu dan beban. Simpan definisinya dulu (`pg_get_indexdef`). |

**Prosedur yang lebih aman:** amati satu siklus bisnis penuh, periksa `stats_reset` dan semua replika, simpan definisi index, uji di lingkungan *staging*, lalu `DROP INDEX CONCURRENTLY` (tidak mengunci tulis).

**(diharapkan) di akhir Praktik**, dua pengamatan:

- `idx_trx_pel_waktu`, `idx_trx_baru`, dan `idx_trx_email` hanya diuji dengan `EXPLAIN` biasa, yang **tidak menjalankan query**, sehingga `idx_scan` kemungkinan masih 0. Padahal index itu benar dipakai oleh planner. Jadi `idx_scan = 0` sering **terlalu pesimis** pada lingkungan uji.
- `idx_trx_brin` baru dibuat dan belum dipakai, sehingga juga 0.
- Selain `idx_scan`, cari **index redundan**: `idx_trx_pelanggan (pelanggan_id)` sudah tercakup oleh `idx_trx_pel_waktu (pelanggan_id, dibuat_pada DESC)` dan `idx_trx_cover`. Itu kandidat yang lebih kuat daripada sekadar `idx_scan = 0`.

---

## Latihan 6: BRIN untuk tabel log 5 miliar baris

**Syarat agar BRIN efektif:**

1. **Korelasi fisik tinggi** antara nilai kolom dan urutan penyimpanan di disk. Cirinya: `pg_stats.correlation` mendekati +1 atau -1. Contohnya tabel log yang hanya di-*append* menurut waktu.
2. Query berupa **rentang** (`BETWEEN`, `>`, `<`) pada kolom itu, bukan pencarian satu nilai acak.
3. Tabel **sangat besar**, sehingga pemindaian penuh mahal dan ukuran index B-Tree merepotkan.
4. Hampir tanpa `UPDATE`/`DELETE` yang menyebarkan baris, dan tanpa penyisipan yang jauh tidak berurutan.

**Mengapa korelasi penting (simulasi Python, bukan PostgreSQL):** BRIN hanya menyimpan nilai **minimum dan maksimum per kelompok halaman** (default 128 halaman, ±9.000 baris pada asumsi saya). Pada 1 juta baris dan 112 kelompok:

| Data | Korelasi | Kelompok yang harus dibaca untuk rentang sempit |
|---|---|---|
| Berurutan (seperti `id`) | 1,000 | **1 dari 112** |
| Acak (seperti `dibuat_pada` pada data modul) | -0,000 | **112 dari 112** (semuanya) |

Pada data acak, setiap kelompok mencakup hampir seluruh rentang nilai, sehingga BRIN tidak bisa mengecualikan apa pun. Karena itu, di tabel `transaksi` dari modul ini, BRIN pada **`id`** efektif (berkorelasi), sedangkan BRIN pada **`dibuat_pada`** (acak) praktis tidak menolong. `latihan.sql` memperlihatkan keduanya.

**(diharapkan)**

- `pg_stats.correlation`: `id` ≈ 1, `dibuat_pada` dan `pelanggan_id` ≈ 0.
- `id BETWEEN 500000 AND 500100`: `Bitmap Heap Scan` + `Bitmap Index Scan on idx_trx_brin`, hanya membaca satu atau dua kelompok blok (dengan baris yang dibuang oleh *recheck*).
- Rentang `dibuat_pada` sehari: planner kemungkinan memilih pemindaian penuh, atau Bitmap Scan yang tetap membaca hampir semua halaman.

**Perkiraan ukuran untuk 5 miliar baris** (berdasarkan **asumsi** yang saya tulis, **tidak diukur**): baris ±100 byte → tabel ±500 GB ≈ 61 juta halaman 8 KB → pada 128 halaman per kelompok ≈ 480 ribu kelompok → BRIN berukuran puluhan MB (tiap kelompok hanya menyimpan sedikit byte). B-Tree pada `timestamptz` untuk 5 miliar baris, dengan ±16-24 byte per entri, berukuran ratusan GB (orde 100 GB). Selisihnya beberapa orde besar. Itulah alasan BRIN menarik untuk log besar.

**Kekurangannya:** BRIN bersifat *lossy*, jadi query tetap membaca seluruh kelompok yang mungkin cocok dan membuang yang tidak cocok. Ia buruk untuk pencarian satu nilai, dan efektivitasnya turun bila korelasi rusak (data masuk tidak berurutan, banyak `UPDATE`). Pertimbangkan `pages_per_range` yang lebih kecil bila perlu ketelitian lebih, atau kombinasi dengan partisi menurut waktu (Modul 11).

---

## Latihan 7: Hash vs B-Tree pada teks 200 karakter

`latihan.sql` membuat `teks_panjang` (300.000 baris, panjang tepat 200 karakter dari `md5` bersambung) dengan kedua jenis index, lalu membandingkan ukuran dan rencana.

**(diharapkan)**

| | Hash | B-Tree |
|---|---|---|
| Isi entri | Hanya **kode hash 4 byte + penunjuk baris** | **Seluruh kunci 200 karakter** + penunjuk baris |
| Ukuran | **Jauh lebih kecil** (kelipatan; angka tidak saya tuliskan) | Besar, kira-kira sebanding dengan panjang kunci |
| `WHERE isi = '...'` | Bisa dipakai; baris di tabel dicek ulang karena hash bisa bertabrakan | Bisa dipakai |

Dugaan arah (hash lebih kecil) wajar karena B-Tree tidak mengompresi kunci acak. Besarnya selisih belum diukur.

**Hal yang tidak bisa dilakukan hash index** (dua di antaranya diuji sebagai "DISENGAJA ERROR" di `latihan.sql`):

| Keterbatasan | Hasil |
|---|---|
| `UNIQUE` | `ERROR: access method "hash" does not support unique indexes` |
| Multikolom | `ERROR: access method "hash" does not support multicolumn indexes` |
| Rentang, `ORDER BY`, prefix `LIKE` | Tidak bisa (hash tidak menjaga urutan) |
| Index-Only Scan | Tidak bisa (hanya menyimpan kode hash, bukan nilainya) |

**Kapan hash masuk akal:** hanya untuk pencarian **kesamaan** pada kunci **panjang** (URL, token) dan tanpa kebutuhan unik atau urutan, ketika ukuran index penting. Index hash aman dari kerusakan setelah crash sejak PostgreSQL 10. Untuk kebanyakan kasus **B-Tree tetap pilihan default** karena fleksibel. Ada juga batas yang menguntungkan hash: entri B-Tree dibatasi sekitar sepertiga halaman (±2,7 KB), sehingga nilai yang jauh lebih panjang tidak bisa diindeks dengan B-Tree, sedangkan hash tidak terkena batas itu karena hanya menyimpan hash.

---

## Lembar hasil Anda

| Langkah | Hasil Anda | Sesuai harapan? |
|---|---|---|
| Praktik: sebelum index = `Parallel Seq Scan`; sesudah = Bitmap/Index Scan | | |
| Praktik: index komposit tanpa node `Sort` | | |
| Praktik: `Index Only Scan` dengan `Heap Fetches` kecil | | |
| Praktik: `LIKE 'user500%'` memakai index apa? (cek temuan 3) | | |
| Latihan 1a: ms per query tanpa vs dengan index | | |
| Latihan 1b: ms INSERT tanpa vs dengan index | | |
| Latihan 2: `idx_c` tanpa `Sort`; `idx_d` ada `Sort` atau scan besar | | |
| Latihan 3: `persen_baru` ≈ 12,5; ukuran partial ≈ 1/8 index penuh | | |
| Latihan 4: Seq Scan → Index Scan; `datcollate` dan efek `text_pattern_ops` | | |
| Latihan 5: index dengan `idx_scan = 0` di daftar Anda | | |
| Latihan 6: korelasi `id` ≈ 1, `dibuat_pada` ≈ 0; BRIN pada `id` efektif | | |
| Latihan 7: ukuran hash vs B-Tree; dua error disengaja muncul | | |

## Sebelum lanjut ke Modul 10

**Modul 10 memakai tabel `app.transaksi` dan index `idx_trx_pelanggan` dari modul ini** (teks Modul 10 menyatakan "Gunakan tabel `transaksi` (1 juta baris) dari Modul 9"). Karena itu:

- **Jangan** jalankan `./jalankan.sh bersih`, yang menghapus `transaksi`.
- Jalankan `./jalankan.sh salinan`: menghapus salinan uji (`trx_a`, `trx_b`, ...), `teks_panjang`, fungsi ukur, dan index tambahan `idx_trx_brin_waktu` dari Latihan 6 (index acak yang tidak berguna dan akan mengacaukan rencana eksekusi di Modul 10). Tabel `transaksi` dan index Praktik tetap utuh.
- Jika Anda memperkirakan akan menjalankan modul-modul berikutnya, tinggalkan juga tabel `dokumen` dan `idx_trx_*` hasil Praktik apa adanya.
