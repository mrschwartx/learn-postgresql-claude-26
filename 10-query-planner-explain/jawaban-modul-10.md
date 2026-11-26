# Jawaban Modul 10: Query Planner & EXPLAIN

## Status eksekusi (baca dulu)

PostgreSQL dan Docker tidak tersedia di lingkungan saya, jadi **tidak ada perintah di modul ini yang sudah dijalankan di PostgreSQL**. Modul ini hampir seluruhnya tentang **membaca keluaran planner PostgreSQL**, hal yang tidak bisa ditiru SQLite maupun Python. Karena itu:

- **Saya tidak menuliskan satu pun keluaran `EXPLAIN` sebagai fakta**: tidak ada nilai `cost`, `actual time`, `Buffers`, atau angka baris yang saya klaim dari mesin. Yang saya tulis adalah **apa yang perlu dicari**, **mengapa**, dan **dugaan terarah** yang berlabel **(diharapkan)**.
- Anda perlu menjalankan skripnya dan mengisi hasil di lembar akhir.

Yang **bisa** saya buktikan hanyalah konsep di bawahnya, dan itu pun dengan batasan:

| Bagian | Metode | Catatan |
|---|---|---|
| Nested loop vs hash vs merge join: hasil sama, jumlah kerja berbeda menurut ukuran data | **Simulasi Python** (`[SIMULASI]`) | Model **sederhana**, bukan model biaya PostgreSQL |
| Top-N heap = sort + `LIMIT` tetapi hanya menyimpan N baris | Simulasi Python | |
| Aritmetika estimasi `rows` saat statistik usang | Simulasi Python (pendekatan) | Memakai model selektivitas yang disederhanakan |
| Fungsi pada kolom membuat index tak terpakai; kesamaan dulu, rentang terakhir; covering index | **SQLite** `EXPLAIN QUERY PLAN` (`[SQLite]`) | Planner SQLite, hanya konsepnya |
| Format `EXPLAIN`, `Sort Method`, nama node, `Buffers`, waktu | **Tidak diuji** | Berlabel (diharapkan) |

Total **15 pemeriksaan, semuanya sesuai harapan** (`output_verifikasi.txt`).

| Berkas | Fungsi |
|---|---|
| `praktik.sql` | Praktik, disalin langsung dari modul (isi tidak diubah) |
| `latihan.sql` | Latihan 1-4. Pengaturan planner memakai `SET LOCAL` di dalam `BEGIN ... ROLLBACK`, sehingga otomatis kembali normal. |
| `bersih_salinan.sql`, `jalankan.sh` | `praktik`, `latihan`, `salinan` |
| `verifikasi.py`, `output_verifikasi.txt` | Bukti konsep |

**Urutan:** Modul 9 harus selesai (tabel `app.transaksi` dan `idx_trx_pelanggan`). Lalu `./jalankan.sh praktik` → `./jalankan.sh latihan` → `./jalankan.sh salinan`.

> **Praktik ini menambah data permanen.** Bagian "Statistik Planner" (nomor 7) menyisipkan **200.000 baris** ke `app.transaksi` (`id` 2.000.001 dan seterusnya, `pelanggan_id = 1`, status `baru`). Baris itu tidak ikut hilang oleh `ROLLBACK` dan tetap ada untuk **Modul 11-16**, yang memakai `transaksi`. Menjalankan Praktik dua kali berarti menambahkan 200.000 baris lagi. `latihan.sql` memakai salinan tabel sendiri dan tidak menyentuh `transaksi`.

---

## Temuan dari membaca modul ini

1. **Tabel `pelanggan` hanya berisi 4 baris** (seed Modul 5), sedangkan `transaksi.pelanggan_id` berkisar 1 sampai 10001. Join di Praktik (nomor 4) hanya cocok untuk `pelanggan_id` 1-4 (±100 baris per pelanggan), jadi **sisi luar join hanya 4 baris**. Rencana yang dipilih kemungkinan besar Nested Loop dengan pemindaian `idx_trx_pelanggan` (`loops=4`), bukan Hash Join. Itu tidak salah, tetapi **terlalu kecil untuk membandingkan algoritma join** seperti yang diminta Latihan 1. Karena itu `latihan.sql` membuat `pelanggan_uji` (10.001 baris) agar setiap baris transaksi punya pasangan.
2. **Contoh keluaran di teori tidak konsisten dengan nasihatnya sendiri.** Contoh itu menampilkan `rows=1` (estimasi) lawan `rows=100` (aktual), padahal modul menyebut selisih sebesar itu sebagai tanda statistik buruk. Dengan statistik segar, estimasi untuk `pelanggan_id = 4242` mestinya mendekati 100 dan rencananya kemungkinan `Bitmap Heap Scan`. Anggap contoh itu ilustrasi format, bukan keluaran nyata.
3. **Komentar `-- 'quicksort Memory'` pada langkah `work_mem` kemungkinan keliru.** Karena ada `LIMIT 100000`, PostgreSQL biasanya memakai pengurutan terbatas (*bounded sort*) yang disebut `top-N heapsort` begitu tuple di memori melebihi dua kali batasnya. Berdasarkan pemahaman saya atas cara kerjanya (belum diuji di sini), `Sort Method: quicksort` baru akan muncul pada pengurutan **tanpa** `LIMIT` yang muat di memori. Karena itu `latihan.sql` (Latihan 2) menjalankan keempat kombinasi: dengan dan tanpa `LIMIT`, `work_mem` kecil dan besar.
4. **Autovacuum bisa "menolong" demo statistik usang sebelum Anda sempat melihatnya.** Ambang `ANALYZE` otomatis untuk tabel 1 juta baris ≈ 50 + 0,1 × 1.000.000 = **100.050 baris berubah** (default). Penyisipan 200.000 baris melampauinya, dan `autovacuum_naptime` default hanya 1 menit. Jadi bila Anda menunggu terlalu lama sebelum `EXPLAIN`, statistik mungkin sudah diperbarui. `latihan.sql` (Latihan 3) mematikan autovacuum **hanya pada tabel uji**.
5. **Beberapa tampilan di PostgreSQL 18 mungkin berbeda dari teks modul.** Seingat saya (verifikasi di catatan rilis 18, saya tidak mengujinya): `EXPLAIN ANALYZE` kini menyertakan `BUFFERS` secara bawaan; node yang dinonaktifkan lewat `enable_*` ditandai `Disabled: true` alih-alih biaya yang digelembungkan; dan ada baris `Index Searches`. Tujuannya sekadar agar Anda tidak bingung bila keluaran Anda tampak berbeda dari contoh.
6. **Pengaturan `SET` pada Praktik berlaku untuk sesi**, dan modul menutupnya dengan `RESET`. Di `latihan.sql` saya memakai `SET LOCAL` di dalam transaksi, yang otomatis hilang saat `ROLLBACK`.
7. **Tiga layanan visualisasi tidak bisa saya akses** (tidak ada jaringan), jadi saya tidak bisa memverifikasi klaim tentang Tensor (antarmuka berbahasa Rusia, rekomendasi otomatis) atau membandingkan ketiganya. Itu tugas Anda; saya sediakan templat di bawah.

---

## Praktik

Karena saya tidak menulis keluaran sebagai fakta, berikut **apa yang perlu dicari** pada setiap bagian dan dugaan terarahnya **(diharapkan)**:

| Bagian | Yang dicari dan dugaan |
|---|---|
| **1. Rencana sederhana** | `EXPLAIN` tanpa `ANALYZE` tidak menjalankan query. Dugaan: `Bitmap Heap Scan` + `Bitmap Index Scan on idx_trx_pelanggan`, estimasi `rows` ≈ 100. Pada `EXPLAIN (ANALYZE, BUFFERS)` bandingkan `rows` estimasi vs aktual, dan `Buffers: shared hit` vs `read` (jalankan dua kali: pembacaan kedua biasanya didominasi `hit`). |
| **2. Seq Scan vs Index Scan** | `pelanggan_id < 10` memilih ±0,1% baris: dugaan memakai index. `pelanggan_id < 9000` memilih ±90% baris: dugaan `Seq Scan` (kemungkinan `Parallel Seq Scan` di bawah `Gather`), karena membaca nyaris seluruh tabel lewat index lebih mahal. |
| **3. `enable_seqscan = off`** | Dugaan: planner terpaksa memakai Bitmap/Index Scan dengan **biaya estimasi lebih tinggi** daripada Seq Scan tadi. Itu membuktikan pilihan bawaannya benar. Ingat: ini alat diagnosis. |
| **4. Join** | Lihat Temuan 1: dugaan Nested Loop dengan `loops=4` pada sisi dalam, karena sisi luar hanya 4 baris. Perhatikan juga node agregasi (`HashAggregate` atau `GroupAggregate`). |
| **5. `work_mem` kecil dan besar** | Lihat Temuan 3. Yang pasti dicari: baris `Sort Method:` dan ada tidaknya `Disk: ... kB`. `Buffers: temp read/written` hanya muncul bila sort tumpah ke disk. |
| **6. `pg_stats`** | `status`: `n_distinct` ≈ 5; `most_common_vals` berisi kelima status dengan frekuensi ±0,25 untuk tiga di antaranya dan ±0,125 untuk `baru` dan `batal` (akibat pembulatan `::int`; saya memverifikasi proporsi ini dengan rumus yang sama di Modul 9). `pelanggan_id`: `n_distinct` kira-kira 10.000 (diperkirakan dari sampel, jadi bisa sedikit meleset) dan `correlation` ≈ 0 karena data acak. |
| **7. Statistik usang** | Lihat Latihan 3: estimasi sekitar seratus baris, aktual sekitar 200.000. |
| **8. `EXPLAIN ANALYZE` pada `UPDATE`** | Muncul node `Update on transaksi` dan **perubahan benar-benar dilakukan** sampai `ROLLBACK`. `ROLLBACK` tidak mengembalikan ruang: versi baris yang dibatalkan menjadi *dead tuple* yang akan dibersihkan vacuum (Modul 7). |

### Visualisasi Rencana: templat untuk Anda isi

Saya tidak bisa menjalankan atau membuka ketiga layanan itu. Gunakan `EXPLAIN (ANALYZE, BUFFERS)` (teks, untuk depesz dan Tensor) dan `FORMAT JSON` (untuk PEV2) dari Praktik, lalu isi:

| Pertanyaan | depesz | PEV2 (dalibo) | Tensor |
|---|---|---|---|
| Node mana yang disorot paling lambat? | | | |
| Bagaimana selisih estimasi vs aktual ditandai? | | | |
| Apakah ada saran/rekomendasi? | | | |
| Apakah memberi saran yang tidak ada di dua lainnya? | | | |
| Bahasa/antarmuka dan keterbatasan | | | |

**Peringatan data sensitif (dari modul, dan saya sependapat):** rencana query memuat nama tabel, kolom, dan sering nilai literal. Jangan menempelkan rencana dari produksi ke layanan publik tanpa disamarkan. Pilih opsi "jangan publikasikan ke arsip" bila ada, atau jalankan PEV2 sendiri secara lokal.

---

## Latihan 1: Join, `enable_hashjoin`, `enable_nestloop`

`latihan.sql` menjalankan join `transaksi` dengan `pelanggan_uji` (10.001 pelanggan, setiap baris transaksi punya pasangan) dalam tiga kondisi: bawaan, `enable_hashjoin = off`, lalu `enable_hashjoin = off` **dan** `enable_nestloop = off`. Sebagai pembanding, join dengan `pelanggan` asli (4 baris) juga dijalankan.

**Yang dicatat:** nama node join di tiap kondisi, `Execution Time`, dan apakah ada node tambahan (`Sort`, `Memoize`, `Materialize`).

**(diharapkan, arah saja)**:

| Kondisi | Dugaan |
|---|---|
| Bawaan, `pelanggan_uji` | **Hash Join**: hash table dari sisi kecil (10.001 pelanggan), probe dengan ±250 ribu baris `transaksi` berstatus `selesai` |
| `enable_hashjoin = off` | Planner beralih ke **Merge Join** atau Nested Loop (dengan `Memoize`). Dugaan: lebih lambat atau setara, **bukan dijamin**. Ukur. |
| Keduanya mati | **Merge Join** (perlu pengurutan kedua sisi atau pemindaian index berurutan). Dugaan: lebih lambat. |
| `pelanggan` asli (4 baris) | Nested Loop dengan sisi dalam di-index (Temuan 1) |

Arah dugaan ini konsisten dengan simulasi di bawah (Latihan 5), tetapi **hasil nyata menentukan**. Jika hasil Anda berbeda dari dugaan saya, itu informasi yang berguna, bukan kesalahan jawaban Anda.

**Mengapa `enable_*` hanya untuk diagnosis:**

- Parameter itu **bukan petunjuk (hint)**, melainkan penalti biaya yang mendorong planner menjauhi satu jenis node untuk **semua query** dalam sesi itu. Query lain bisa mendapat rencana jauh lebih buruk.
- Rencana "terbaik" hari ini bergantung pada ukuran data dan statistik. Ketika data tumbuh, pilihan yang dipaksa bisa menjadi sangat lambat sementara planner sebenarnya tahu alternatif yang lebih baik.
- Yang berguna adalah **membandingkan biaya dan waktu** untuk mengonfirmasi bahwa pilihan planner benar. Bila planner salah, perbaiki akar masalahnya: statistik (`ANALYZE`), index, penulisan ulang query, atau parameter biaya (`random_page_cost`, `effective_cache_size`), bukan mematikan algoritma.

---

## Latihan 2: `external merge` dan `work_mem`

Empat kombinasi di `latihan.sql`:

| | `work_mem` kecil (64kB) | `work_mem` besar (256MB) |
|---|---|---|
| `SELECT * ... ORDER BY total DESC LIMIT 100000` | dugaan `external merge Disk: ... kB` | dugaan `top-N heapsort Memory` (lihat Temuan 3) |
| `SELECT id, total ... ORDER BY total DESC` (tanpa `LIMIT`, kolom sempit) | dugaan `external merge Disk` | dugaan `quicksort Memory` bila muat; bila tidak, tetap `external merge` |

**Yang dicatat:** baris `Sort Method`, ukuran `Disk`/`Memory`, `Buffers: temp read/written`, dan waktu. Ukuran `Disk` memberi tahu **berapa banyak data yang harus ditulis ke disk** karena memori tidak cukup.

**Simulasi (konsep)**: top-N heap menghasilkan hasil yang **identik** dengan sort penuh lalu `LIMIT`, tetapi hanya menyimpan N baris di memori (puncak 1.000 baris dibanding 200.000 untuk sort penuh pada simulasi). Itulah sebabnya `ORDER BY ... LIMIT` kecil sering murah walau tabelnya besar.

### Mengapa menaikkan `work_mem` global berbahaya

`work_mem` adalah batas memori **per operasi** (satu node `Sort` atau `Hash`), **bukan per query atau per koneksi**. Satu query kompleks bisa memiliki beberapa node sekaligus, dan setiap worker paralel memakai jatahnya sendiri, dan semuanya dikalikan jumlah koneksi aktif.

Contoh hitungan terburuk (ilustrasi, bukan ukuran): `work_mem = 256MB` × 3 node × 100 koneksi = **75 GB**. Pada server berkapasitas jauh di bawah itu, lonjakan beban bisa menghabiskan RAM dan memicu pembunuhan proses oleh OS (OOM). Operasi hash juga bisa memakai kelipatan `work_mem` lewat `hash_mem_multiplier`.

**Praktik yang lebih aman:** biarkan nilai global moderat, naikkan per transaksi (`SET LOCAL`), per sesi, atau per role pelaporan (`ALTER ROLE laporan SET work_mem = '...'`) hanya untuk beban yang memang butuh, dan pantau penggunaan file sementara (`log_temp_files`).

---

## Latihan 3: Estimasi `rows` meleset, lalu diperbaiki

`latihan.sql` memakai salinan `trx_stat` dengan autovacuum **dimatikan hanya pada tabel itu**, supaya ANALYZE otomatis tidak memperbaiki statistik sebelum Anda melihatnya (Temuan 4).

Urutan: (a) `ANALYZE`, catat `rows` estimasi vs aktual untuk `pelanggan_id = 1`; (b) sisipkan 200.000 baris dengan `pelanggan_id = 1`, **tanpa** `ANALYZE`, catat lagi; (c) `ANALYZE`, catat lagi.

**Perhitungan saya** (simulasi Python dengan rumus data Modul 9, pendekatan, bukan keluaran PostgreSQL):

| Tahap | Estimasi `rows` | Aktual `rows` |
|---|---|---|
| (a) statistik segar | ≈ puluhan sampai seratusan | ≈ 40-60 (nilai 1 jarang karena pembulatan `::int` memberi bobot setengah) |
| (b) 200.000 baris baru, statistik usang | **≈ 120** | **≈ 200.040** (selisih > 1.000×) |
| (c) setelah `ANALYZE` | ≈ 200.000 (nilai 1 kini ±16,7% baris, masuk *most common values*) | ≈ 200.040 |

**Mengapa (b) meleset:** statistik per kolom (`most_common_vals`, histogram, `n_distinct`) masih menggambarkan keadaan sebelum penyisipan. Planner tahu tabel kini lebih besar (ia menghitung dari ukuran fisik tabel), tetapi **proporsi** nilai 1 diambil dari statistik lama, yaitu nilai langka ≈ satu per 10.000. Ia memperkirakan ±120 baris dan **mungkin memilih Index/Bitmap Scan** untuk apa yang sebenarnya 17% tabel. Hasilnya query jauh lebih lambat daripada seharusnya. Itu contoh dari kalimat modul: "statistik usang = rencana buruk".

**Peran autovacuum:** autovacuum menjalankan `ANALYZE` otomatis ketika jumlah baris yang berubah melampaui

> `autovacuum_analyze_threshold` (50) + `autovacuum_analyze_scale_factor` (0,1) × jumlah baris

yaitu ≈ **100.050** baris untuk tabel 1 juta baris, dicek tiap `autovacuum_naptime` (default 1 menit). Jadi pada sistem normal jendela "statistik usang" dibatasi: begitu 200.000 baris masuk, autovacuum akan memperbaikinya dalam satu siklus. Masalah muncul bila: (1) **autovacuum dimatikan atau tertinggal**, (2) perubahan **di bawah ambang** tetapi sangat memengaruhi distribusi (tabel besar: 10% dari 100 juta baris = 10 juta), (3) **bulk load** lalu query langsung dijalankan sebelum autovacuum sempat, dan (4) tabel sementara, yang tidak di-ANALYZE otomatis.

**Pencegahan:**

- Jalankan `ANALYZE` manual setelah bulk load atau perubahan data besar.
- Turunkan `autovacuum_analyze_scale_factor` per tabel besar yang volatil (contoh sudah ada di Modul 12).
- Naikkan `default_statistics_target` untuk kolom dengan distribusi rumit.
- Gunakan `CREATE STATISTICS` untuk korelasi antar kolom (mis. kota dan kode pos).

---

## Latihan 4: Mengoptimalkan satu query lambat (alur 10.6)

Query buatan saya (omzet harian satu pelanggan, 90 hari terakhir, hanya status `selesai`), pada salinan `trx_opt` berisi 1 juta baris:

```sql
SELECT date_trunc('day', dibuat_pada) AS hari, sum(total) AS omzet
FROM trx_opt
WHERE pelanggan_id = 4242 AND status = 'selesai' AND dibuat_pada::date >= current_date - 90
GROUP BY 1 ORDER BY 1;
```

**Langkah menurut 10.6:**

| Langkah | Yang dilakukan |
|---|---|
| 1. Temukan | Anggap query ini muncul di daftar teratas `pg_stat_statements` (Modul 16) |
| 2. Ukur | `EXPLAIN (ANALYZE, BUFFERS)`: catat `Execution Time` dan `Buffers` |
| 3. Cari | **(diharapkan)** pemindaian tabel penuh (`Parallel Seq Scan`) dengan `Rows Removed by Filter` mendekati 1 juta, karena tidak ada index pendukung |
| 4a. Tulis ulang | `dibuat_pada::date >= current_date - 90` menjadi `dibuat_pada >= current_date - 90` (**setara**: `timestamptz >= date` memakai tengah malam zona sesi). Tanpa index pendukung, waktunya tetap. |
| 4b. Index | `CREATE INDEX ON trx_opt (pelanggan_id, status, dibuat_pada) INCLUDE (total)`, lalu `VACUUM (ANALYZE)` |
| 5. Verifikasi | `EXPLAIN (ANALYZE, BUFFERS)` ulang. **(diharapkan)** `Index Only Scan`, `Heap Fetches` kecil, `Buffers` jauh lebih sedikit |

**Alasan desain index** (terbukti sebagai konsep di SQLite, yang menghasilkan `SEARCH ... USING COVERING INDEX (pelanggan_id=? AND status=? AND dibuat_pada>?)`):

- Kolom **kesamaan** (`pelanggan_id`, `status`) di depan, kolom **rentang** (`dibuat_pada`) terakhir (Latihan 2 Modul 9).
- `INCLUDE (total)` membuat query dilayani seluruhnya dari index (*covering*), tanpa membaca tabel.

**Catatan jujur tentang langkah 4a:** pada index yang sama, bentuk `dibuat_pada::date` kemungkinan tetap memakai index lewat dua kolom pertamanya (hanya ±25 baris yang tersisa), dengan `dibuat_pada` sebagai *Filter*, bukan *Index Cond*. Jadi **perbedaan waktu antara dua bentuk query setelah ada index kemungkinan kecil** pada data ini. Yang sama sekali berbeda adalah ada atau tidaknya index. Bentuk yang tidak membungkus kolom tetap lebih baik sebagai kebiasaan, karena pada tabel dengan filter yang kurang selektif perbedaannya bisa besar. Verifikasi di SQLite: `date(kolom) >= ...` membuat index pada kolom itu tidak terpakai (`SCAN`), sedangkan versi tanpa fungsi memakainya (`SEARCH`).

**Dokumentasi sebelum/sesudah (isi dari hasil Anda):**

| | Sebelum | Sesudah |
|---|---|---|
| Node utama | | |
| Execution Time | | |
| `Buffers` (hit + read) | | |
| Perubahan | | `CREATE INDEX ... INCLUDE (total)` + tulis ulang kondisi |
| **Harga yang dibayar** | | Index tambahan memperlambat `INSERT`/`UPDATE` dan memakan disk (Modul 9, Latihan 1) |

---

## Latihan 5: Nested Loop, Hash Join, Merge Join

| | Nested Loop | Hash Join | Merge Join |
|---|---|---|---|
| Cara kerja | Untuk setiap baris sisi luar, cari pasangannya di sisi dalam | Bangun hash table dari sisi kecil, lalu probe dengan sisi besar | Kedua sisi diurutkan menurut kunci, lalu digabung dalam satu kali lewat |
| Kondisi join | **Apa saja** (juga non-kesamaan, `LATERAL`) | **Hanya kesamaan** | Kesamaan pada kunci yang bisa diurutkan |
| Butuh | Biasanya index pada sisi dalam | Memori (`work_mem` × `hash_mem_multiplier`); tumpah ke disk bila kurang | Kedua sisi terurut (dari index atau `Sort`) |
| Cenderung dipilih bila | **Sisi luar sedikit baris** dan sisi dalam punya index | Join **besar**, tidak terurut, kesamaan | **Keduanya besar dan sudah terurut**, atau hasil harus terurut |
| Memori | Kecil | Besar | Kecil bila sudah terurut |

**Simulasi** (jumlah operasi di model Python sederhana, **bukan biaya PostgreSQL**; hasil join ketiganya terbukti identik):

| Skenario | Nested loop tanpa index | Nested loop + index | Hash join | Merge join |
|---|---|---|---|---|
| 1. Luar 4 baris, dalam 120.000 baris (160 hasil) | 480.000 | **228** | 120.004 | 2.040.136 (termasuk pengurutan) |
| 2. Luar 20.000, dalam 1.000 unik tak terurut | 20.000.000 | 220.000 | **21.000** | 330.999 (termasuk pengurutan) |
| 3. Keduanya terurut (20.000 × 5.000 unik) | 100.000.000 | 280.000 | 25.000 | **24.999** |
| 3. (data yang sama, belum terurut) | | | 25.000 | 389.999 (harus mengurutkan) |

Cara membacanya: skenario 1 mirip join `pelanggan` (4 baris) di Praktik, sehingga Nested Loop + index menang jauh. Skenario 2 mirip join `pelanggan_uji`, sehingga Hash Join menang. Skenario 3 menunjukkan Merge Join hanya kompetitif bila datanya sudah terurut, dan ia tidak memerlukan hash table di memori. Planner PostgreSQL tentu memakai model biaya yang jauh lebih rinci (I/O, CPU, paralelisme, estimasi baris), jadi tabel ini hanya menunjukkan **arah** dan alasannya.

**Catatan:** `FULL JOIN` hanya bisa dilakukan Hash Join atau Merge Join, bukan Nested Loop.

---

## Latihan 6: Mengapa `EXPLAIN ANALYZE` pada sistem sibuk bisa menyesatkan

| Faktor | Efek |
|---|---|
| **Cache panas vs dingin** | Eksekusi pertama banyak membaca dari disk, yang kedua dari cache. Waktu bisa beda berkali-kali lipat untuk rencana yang sama. |
| **Lock dan antrean** | Query yang menunggu kunci tampak lambat, tetapi waktu tunggu itu tidak tampak di node mana pun. `EXPLAIN` tidak menjelaskannya. |
| **Beban lain** | Rebutan CPU, I/O, dan memori dengan query lain membuat waktu tidak bisa dibandingkan antar-eksekusi. |
| **Overhead pengukuran** | `ANALYZE` mengukur waktu per node, dan itu menambah beban (terutama untuk node yang diulang jutaan kali di dalam Nested Loop). Opsi `TIMING OFF` mengurangi overhead. |
| **Yang tidak ikut terukur** | Waktu mengirim hasil ke klien tidak termasuk. Angka `actual time` juga **per loop**, sehingga harus dikalikan `loops`. |
| **Efek samping** | Pada `INSERT`/`UPDATE`/`DELETE`, `EXPLAIN ANALYZE` benar-benar mengubah data (bungkus dengan `BEGIN; ... ROLLBACK;`). |

**Bagaimana `BUFFERS` membantu:**

- `shared hit` vs `shared read` menunjukkan seberapa besar eksekusi ini ditanggung cache. Itu langsung menjelaskan mengapa pengukuran pertama dan kedua berbeda.
- **Jumlah buffer jauh lebih stabil antar-eksekusi daripada waktu**, sehingga cocok sebagai ukuran pembanding sebelum/sesudah optimasi. Jumlah halaman yang disentuh turun ketika rencananya benar-benar lebih efisien.
- `temp read/written` memperlihatkan sort atau hash yang tumpah ke disk; `shared dirtied/written` menunjukkan efek tulis.
- Bila `track_io_timing` aktif, waktu I/O terpisah dari waktu CPU, sehingga terlihat apakah query terikat I/O.

**Praktik yang disarankan:** jalankan beberapa kali dan ambil yang stabil, bandingkan `Buffers` selain waktu, ukur di salinan data yang representatif (*staging*) bila produksi terlalu sibuk, dan cek lock lewat `pg_stat_activity`/`pg_locks`, bukan `EXPLAIN`.

---

## Lembar hasil Anda

| Langkah | Hasil Anda | Sesuai dugaan? |
|---|---|---|
| Praktik 1: node scan dan `rows` estimasi vs aktual untuk `pelanggan_id = 4242` | | |
| Praktik 2: `< 10` memakai index, `< 9000` Seq Scan | | |
| Praktik 4: node join pada `pelanggan` 4 baris | | |
| Praktik 5: `Sort Method` untuk `64kB` dan `256MB` | | |
| Praktik 6: `n_distinct` dan `correlation` | | |
| Praktik 7: `rows` estimasi sebelum/sesudah `ANALYZE` | | |
| Latihan 1: node join (bawaan / `hashjoin off` / keduanya off) dan waktunya | | |
| Latihan 2: empat kombinasi `Sort Method` | | |
| Latihan 3a/3b/3c: estimasi vs aktual | | |
| Latihan 4: waktu sebelum/sesudah dan node utama | | |

## Sebelum lanjut ke Modul 11

Jalankan `./jalankan.sh salinan` untuk menghapus `pelanggan_uji`, `trx_stat`, dan `trx_opt`. **Jangan** menghapus `transaksi`. Modul 11 (pola desain, termasuk perbandingan `OFFSET` vs *keyset*) dan Modul 12 (autovacuum per tabel) memakainya. Perhatikan bahwa `transaksi` kini berisi **1.200.000 baris** (200.000 baris tambahan dari Praktik nomor 7), dan statistiknya sudah diperbarui lewat `ANALYZE` di akhir langkah itu.
