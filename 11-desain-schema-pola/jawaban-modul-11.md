# Jawaban Modul 11: Desain Schema & Pola Aplikasi

## Status eksekusi (baca dulu)

PostgreSQL, Docker, dan jaringan tidak tersedia di lingkungan saya, jadi **tidak ada perintah SQL di modul ini yang sudah dijalankan di PostgreSQL**. Modul ini campuran antara desain (yang bisa saya periksa logikanya) dan fitur khas PostgreSQL (yang tidak bisa).

| Bagian | Status |
|---|---|
| Normalisasi 3NF tanpa kehilangan data; JSON hibrida vs EAV; logika pagination OFFSET vs keyset; mesin status antrean (retry, backoff, timeout); logika pembuat partisi; pola UPDATE bertahap | **Diuji nyata di SQLite/Python** (34 pemeriksaan, semuanya sesuai: `output_verifikasi.txt`) |
| Jumlah baris per partisi pada Praktik, sebaran 100.000 baris sensor per hari | **Hitungan Python** (`[hitungan]`) |
| Teks SQL dan data yang dihasilkan `bulk_ukur.sh` | Diuji dengan `psql` tiruan berbasis SQLite: keempat cara menghasilkan jumlah baris yang sama. **Waktu dari uji itu tidak bermakna dan tidak saya kutip.** |
| `PARTITION BY` dan *pruning*, `FOR UPDATE SKIP LOCKED` dan konkurensi, `COPY`, `NOT VALID`/`VALIDATE`, kunci (*lock*), Flyway, PgQ, keluaran `EXPLAIN` | **Tidak bisa diuji.** Berlabel **(diharapkan)**. |

| Berkas | Fungsi |
|---|---|
| `praktik.sql` | Praktik, disalin langsung dari modul (satu perubahan: path CSV `/tmp/...`) |
| `latihan.sql` | Perbaikan demo pagination + Latihan 1-4 (semua di schema `latihan11`) |
| `bulk_ukur.sh` | Latihan 5 (membandingkan cara memuat data) |
| `flyway/` | Migrasi V1-V6 dan `jalankan_flyway.sh` (Latihan 7 dan Praktik Flyway) |
| `pgq_opsional.sql` | Praktik PgQ (opsional, belum diuji) |
| `bersih.sql`, `jalankan.sh` | `praktik`, `latihan`, `pgq`, `bulk [N]`, `bersih` |
| `verifikasi.py`, `output_verifikasi.txt` | Bukti logika |

**Urutan:** Modul 9-10 selesai (tabel `app.transaksi`). `./jalankan.sh praktik` → `./jalankan.sh latihan` → `./jalankan.sh bulk` → bila perlu `./flyway/jalankan_flyway.sh ...`. **`./jalankan.sh bersih` aman:** menghapus semua objek modul ini dan **tidak menyentuh `transaksi`**. Saya sudah memeriksa bahwa Modul 12-16 tidak memakai satu pun objek dari modul ini.

---

## Temuan dari membaca modul ini

1. **Demo keyset pagination di Praktik tidak akan memperlihatkan keunggulannya.** Tabel `transaksi` (dibuat lewat `CREATE TABLE AS` di Modul 9) **tidak punya primary key maupun index B-Tree pada `id`**, hanya index BRIN yang tidak bisa melayani `ORDER BY`. Akibatnya kedua query di Praktik sama-sama memindai dan mengurutkan tabel. Di SQLite saya mereproduksi konsepnya: **tanpa index**, keduanya memakai `USE TEMP B-TREE FOR ORDER BY`; **dengan index**, keyset menjadi `SEARCH` sedangkan OFFSET tetap `SCAN`. `latihan.sql` mengulangi demo pada salinan tabel, dengan dan tanpa index.
2. **Praktik antrean ("dua terminal bergantian") tidak menguji `SKIP LOCKED`.** Masing-masing perintah berjalan *autocommit*, jadi klaim pertama sudah commit sebelum klaim kedua dimulai. Keduanya tentu mendapat tugas berbeda, tanpa ada kunci yang dilewati. Agar benar-benar melihat baris yang dilewati, klaim pertama harus berada di dalam transaksi yang belum commit (skenario `antrean` pada `dua_sesi.sh` di Modul 7).
3. **`NOT VALID` lalu `VALIDATE` dalam satu transaksi menggagalkan tujuannya.** Lihat Latihan 7: karena itu saya memecah migrasi (c) menjadi dua berkas, V5 dan V6.
4. **Praktik "Migrasi Aman" meninggalkan objek** (`produk.merek`, constraint `merek_wajib`, `idx_produk_merek`, tabel `staging_produk`), sehingga migrasi Flyway di Latihan 7 harus idempoten atau memakai nama berbeda. Saya memakai `IF NOT EXISTS` dan nama constraint `produk_merek_wajib`.
5. **`\copy ... 'produk_full.csv'` memakai path relatif di dalam container**, sehingga lokasinya tidak jelas. Saya ganti dengan `/tmp/produk_full.csv`.
6. **Migrasi Flyway biasa berjalan dalam satu transaksi**, jadi `COMMIT` per batch tidak bisa dilakukan di dalamnya (lihat Latihan 7(b)).
7. **PgQ.** Nama paket (`postgresql-18-pgq3`) belum bisa saya verifikasi (tidak ada jaringan). Dugaan saya, `pgq.ticker()` hanya membuat *tick* bila ambang jumlah event atau selisih waktu terpenuhi, jadi `next_batch` bisa `NULL` beberapa detik setelah `insert_event`. Ini belum diuji. Modul sendiri sudah mengantisipasi dengan "jalankan `pgq.ticker()` lagi".

---

## Praktik

### Partitioning

**Hitungan saya untuk 80.000 menit data** (`2026-10-01` + 1 s.d. 80.000 menit, hitungan Python):

| Partisi | Baris |
|---|---|
| `log_2026_10` | **44.639** |
| `log_2026_11` | **35.361** |
| `log_default` | 0 |

Baris pada tepat `2026-11-01 00:00` (g = 44.640) masuk ke partisi **November**: batas bawah `FROM` bersifat inklusif, batas atas `TO` eksklusif. Hitungan ini mengasumsikan data dan batas partisi memakai zona waktu sesi yang sama (keduanya memang demikian pada Praktik).

**(diharapkan)**

| Perintah | Hasil |
|---|---|
| `\d+ log_aktivitas` | Daftar tiga partisi: `log_2026_10`, `log_2026_11`, dan `DEFAULT` |
| `SELECT tableoid::regclass, count(*) ... GROUP BY 1` | Dua baris saja (partisi `log_default` kosong sehingga tidak muncul) dengan hitungan di atas |
| `EXPLAIN` untuk `2026-11-10` sampai `11-11` | Hanya `log_2026_11` yang muncul (`Seq Scan`, karena satu-satunya index pada partisi adalah PK `(id, dibuat_pada)`). Partisi lain termasuk `DEFAULT` terpangkas (*pruned*). |
| `DETACH` lalu `DROP` | Hampir seketika, walau membuang 44.639 baris, karena yang dihapus adalah satu tabel utuh, bukan baris demi baris |

### Queue dengan SKIP LOCKED

**(diharapkan)** Perintah pertama mengembalikan baris `id = 1` (`tugas-1`, `status = diproses`, `mulai` terisi). Perintah yang sama dari terminal lain mengembalikan `id = 2`. Lihat Temuan 2: hasil ini terjadi karena commit berurutan, bukan karena baris dilewati.

### Keyset Pagination vs OFFSET

Lihat Temuan 1. **(diharapkan)** pada tabel asli: kedua query memindai `transaksi` (kemungkinan `Parallel Seq Scan`) lalu mengurutkan, dengan waktu yang tidak berbeda jauh. Jangan menyimpulkan bahwa keyset "tidak lebih cepat". Kesimpulannya: **keyset hanya cepat bila ada index yang cocok.** Hasil di SQLite (300.000 baris, hanya arah): OFFSET ±135.000 baris ≈ 1,1 ms vs keyset ≈ 0,007 ms (±157×).

### Migrasi Aman dan Bulk Load

**(diharapkan)**

| Langkah | Hasil |
|---|---|
| `ADD COLUMN merek`, `UPDATE` | `ALTER TABLE`, `UPDATE 5` (jumlah baris `produk`) |
| `ADD CONSTRAINT ... NOT VALID` lalu `VALIDATE CONSTRAINT` | Keduanya `ALTER TABLE`. Yang kedua memindai tabel tanpa memblokir tulis. |
| `CREATE INDEX CONCURRENTLY` | `CREATE INDEX`. **Bila gagal di tengah jalan, index tertinggal dengan status `INVALID`** (terlihat di `\d produk`). Hapus dan ulangi. |
| `\copy` ekspor lalu impor ke `staging_produk` (`UNLOGGED`) | `COPY 5` dua kali |

### Flyway (opsional)

**(diharapkan, belum diuji):** `migrate` melaporkan dua migrasi berhasil diterapkan (V1, V2); `info` menampilkan keduanya `Success`; `flyway_schema_history` berisi baris baseline dan dua migrasi. Setelah mengubah isi `V1...sql` dan `migrate` lagi, Flyway menolak dengan pesan ketidakcocokan *checksum*. Itulah alasan aturan "jangan ubah migrasi yang sudah berjalan".

### PgQ (opsional)

Tidak diuji. Lihat Temuan 7. Bagian `at-least-once` bisa diamati dengan memanggil `next_batch` dua kali tanpa `finish_batch`: **(diharapkan)** `batch_id` yang sama dikembalikan.

---

## Latihan 1: Normalisasi `pesanan_lama` sampai 3NF

**Analisis dependensi** (asumsi saya nyatakan eksplisit, karena menentukan hasil):

- `id` adalah kunci utama (satu kolom), sehingga **2NF otomatis terpenuhi**. Masalahnya ada pada **dependensi transitif (3NF)**: `id → pelanggan_nama → pelanggan_alamat` dan `id → produk_nama → produk_harga`.
- Asumsi 1: nama pelanggan menentukan alamat. Di dunia nyata nama tidak unik, jadi pelanggan diberi `id` sendiri.
- Asumsi 2: **`produk_harga` saya anggap harga produk saat ini**, sedangkan harga yang tertera pada baris pesanan adalah **harga saat transaksi**. Dua hal yang berbeda: harga produk bisa berubah, harga di pesanan lama tidak boleh ikut berubah. Karena itu hasilnya menyimpan `produk.harga` **dan** `item_pesanan.harga_satuan`. Bila `produk_harga` sebenarnya hanya harga saat transaksi, tabel `produk` tidak perlu kolom harga.
- Tabel lama menyatukan "pesanan" dan "baris pesanan" (satu produk per baris). Hasilnya dipisah agar satu pesanan bisa berisi banyak produk.

**Hasil (3NF):**

```
pelanggan (id PK, nama UNIQUE, alamat)
produk    (id PK, nama UNIQUE, harga)
pesanan   (id PK, pelanggan_id FK → pelanggan)
item_pesanan (pesanan_id FK → pesanan, produk_id FK → produk,
              jumlah, harga_satuan,  PK (pesanan_id, produk_id))

pelanggan 1 ──< N pesanan 1 ──< N item_pesanan N >── 1 produk
```

Index pada kolom FK (`pesanan.pelanggan_id`, `item_pesanan.produk_id`) ditambahkan karena PostgreSQL **tidak** membuat index FK otomatis (anti-pola "FK tanpa index" di teori).

**Terverifikasi di SQLite**, dengan `INSERT ... SELECT` asli dari `latihan.sql` pada enam baris contoh:

| Pemeriksaan | Hasil |
|---|---|
| Dependensi nama → alamat dan nama produk → harga berlaku pada data contoh | Ya (tidak ada pelanggaran) |
| Baris hasil: `pelanggan` / `produk` / `pesanan` / `item_pesanan` | 3 / 3 / 6 / 6 |
| Rekonstruksi (join 4 tabel) `EXCEPT` tabel lama, dan sebaliknya | **Kosong kedua arah** (tidak ada data hilang atau bertambah) |
| Anomali update: mengubah harga Mouse | Tabel lama menyentuh **2 baris**, tabel normal **1 baris** |

Anomali lain yang dihilangkan: **insert** (tidak bisa mencatat produk baru sebelum ada pesanan), **delete** (menghapus satu-satunya pesanan sebuah produk menghilangkan informasi produknya), dan **update** (alamat atau harga yang ditulis berulang bisa tidak konsisten).

---

## Latihan 2: `tiket_dukungan`, JSONB vs EAV

**Rancangan hibrida** (di `latihan.sql`): kolom nyata untuk data inti (`jenis`, `judul`, `status`, `dibuat_pada`), dan satu kolom `atribut jsonb` untuk atribut yang bervariasi menurut jenis tiket, dengan `CHECK` per jenis:

```sql
CONSTRAINT atribut_bug     CHECK (jenis <> 'bug' OR (atribut ? 'versi' AND atribut ? 'tingkat')),
CONSTRAINT atribut_tagihan CHECK (jenis <> 'tagihan' OR jsonb_typeof(atribut -> 'jumlah') = 'number')
```

plus index GIN (`jsonb_path_ops`) untuk pencarian `@>`.

**Kapan jsonb, kapan kolom biasa:**

| Kolom biasa | `jsonb` |
|---|---|
| Data **inti** yang di-filter, di-join, diurutkan, atau butuh `FK`/`NOT NULL`/tipe ketat (`status`, `pelanggan_id`, `dibuat_pada`) | Atribut yang **bervariasi atau jarang** menurut jenis (versi aplikasi untuk bug, metode bayar untuk tagihan) |
| Dipakai di laporan agregasi berat | Tidak pernah di-join, dibaca bersama tiketnya |
| Atribut yang sudah stabil dan dipakai semua tiket | Atribut eksperimental atau cepat berubah |

Aturan praktis: mulai dari `jsonb` untuk yang tidak pasti, lalu **angkat menjadi kolom** begitu atribut itu sering difilter, perlu constraint, atau perlu `FK`. Jalan tengah bila tiap jenis punya atribut ketat: satu tabel induk plus tabel per jenis (`tiket_bug`, `tiket_tagihan`).

**Pembanding EAV** (`tiket_eav(tiket_id, nama, nilai text)`) dan mengapa lebih buruk. Terverifikasi di SQLite kecuali yang berlabel diharapkan:

| Masalah EAV | Bukti |
|---|---|
| **Baris membengkak:** 6 tiket menjadi 11 baris atribut | Terverifikasi |
| **Query butuh satu self-join per atribut:** "bug versi 2.3 tingkat tinggi" = 2 join; makin banyak atribut, makin banyak join | Terverifikasi (hasilnya sama dengan versi JSON) |
| **Tipe hilang:** semua nilai berupa teks | Nilai `'abc'` untuk atribut `jumlah` **diterima** tanpa protes |
| **Tanpa constraint per atribut:** tidak ada `NOT NULL`, `CHECK`, atau `FK` per jenis | Di versi JSON, `CHECK` menolak bug tanpa `versi` dan tagihan dengan `jumlah` bukan angka (**keduanya ditolak**, terverifikasi) |
| **Satu nilai buruk merusak query:** `nilai::numeric` gagal untuk seluruh query | **(diharapkan)** `ERROR: invalid input syntax for type numeric: "abc"`. **Tidak bisa dibuktikan di SQLite**, yang justru diam-diam mengubah `CAST('abc' AS NUMERIC)` menjadi 0 |
| **Statistik dan index buruk:** planner tidak bisa memperkirakan selektivitas tiap atribut | Berdasarkan cara kerja planner, belum diuji |

---

## Latihan 3: `sensor_data` dipartisi per hari

DDL lengkap di `latihan.sql`. **Sebaran data:** 100.000 baris dengan selang 2,592 detik mencakup tepat 3 hari, sehingga hasilnya (hitungan Python) **33.334 / 33.333 / 33.333** baris, dan **tidak ada baris di luar tiga partisi** (baris terakhir ada di detik 259.197,408 dari 259.200). Karena itu tidak diperlukan partisi `DEFAULT`.

**(diharapkan) bukti pruning dengan `EXPLAIN`:**

| Query | Rencana |
|---|---|
| `WHERE waktu >= '2026-12-02' AND waktu < '2026-12-03'` | **Hanya `sensor_20261202`** yang muncul. Itulah bukti pruning. |
| `WHERE sensor_id = 7` | **Ketiga partisi** dipindai (tidak ada filter pada kunci partisi) |
| `WHERE waktu::date = '2026-12-02'` | Kemungkinan **semua partisi** dipindai, karena kunci partisi dibungkus cast. Bandingkan dengan query pertama. |

Pelajarannya: pruning hanya bekerja bila filter dinyatakan langsung pada kolom kunci partisi.

**Otomatisasi pembuatan partisi hari berikutnya:**

```sql
CREATE FUNCTION buat_partisi_sensor(p_hari date) RETURNS text ... AS $$
  EXECUTE format('CREATE TABLE IF NOT EXISTS latihan11.%I PARTITION OF latihan11.sensor_data
                  FOR VALUES FROM (%L) TO (%L)', nama, p_hari, p_hari + 1);
$$;
```

Logikanya diverifikasi lewat portnya di Python: batas partisi harian **bersambung tanpa celah dan tanpa tumpang tindih**, nama konsisten (`sensor_20261204`), dan pemanggilan ulang **idempoten** (`IF NOT EXISTS`). Sintaks PL/pgSQL-nya sendiri belum dijalankan.

| Cara menjadwalkan | Catatan |
|---|---|
| `pg_cron` | Menjadwalkan `SELECT buat_partisi_sensor(current_date + 1)` di dalam database. Ekstensinya tidak ada di image resmi. |
| `cron`/penjadwal OS atau job di aplikasi | `psql -c "SELECT ..."` tiap hari. Sederhana dan tersedia di mana saja. |
| `pg_partman` | Mengelola pembuatan dan retensi partisi otomatis (`create_parent`, `run_maintenance`) |

**Praktik pendukung:**

- **Buat beberapa hari ke depan sekaligus** (contoh: 7 hari), sebagai penyangga bila penjadwal gagal satu hari. `latihan.sql` melakukannya untuk 6 hari.
- Tambahkan partisi `DEFAULT` sebagai jaring pengaman, dan **pantau isinya** (bila tidak kosong, ada partisi yang terlewat). Peringatan: membuat partisi baru yang rentangnya sudah berisi baris di partisi `DEFAULT` akan **gagal**, sehingga baris itu harus dipindahkan dulu.
- Retensi: `DETACH PARTITION ... CONCURRENTLY` (PostgreSQL 14+) lalu `DROP`.
- `ANALYZE` pada tabel induk perlu dijalankan manual, karena autovacuum tidak menganalisis tabel induk berpartisi (sepengetahuan saya).

---

## Latihan 4: Job queue `SKIP LOCKED` dengan retry maksimum 3 kali

**Rancangan** (`latihan.sql`): tabel `antrean2` dengan `status` (`menunggu`, `diproses`, `selesai`, `gagal`), `percobaan`, `maks_percobaan` (3), `jalankan_setelah`, `pesan_error`, dan index parsial pada tugas yang menunggu. Empat fungsi: `ambil_tugas()` (klaim dengan `FOR UPDATE SKIP LOCKED` dan `percobaan + 1`), `tugas_selesai`, `tugas_gagal` (kembali ke `menunggu` selama `percobaan < maks`, selain itu `gagal`, dengan *backoff* opsional), dan `pulihkan_macet` (*visibility timeout*).

**Terverifikasi lewat padanan mesin status di SQLite** (klaim, selesai, gagal, dan waktu disimulasikan; `SKIP LOCKED` tidak bisa):

| Tugas | Status akhir | `percobaan` |
|---|---|---|
| `sukses` | `selesai` | 1 |
| `gagal-sekali` | `selesai` | 2 |
| `selalu-gagal` | **`gagal`** | **3** |

- **Backoff:** dengan `tunda = 30` dan `jalankan_setelah = sekarang + 30 × percobaan`, tugas tidak bisa diambil pada jam 100 maupun 129, dan baru bisa diambil pada jam 130 sebagai percobaan ke-2.
- **Visibility timeout** (batas 300 detik, jam 600): tugas macet dengan 1 percobaan kembali ke `menunggu`; yang sudah 3 percobaan menjadi `gagal`; yang baru mulai (jam 590) tidak disentuh.

**Catatan penting:**

- **Worker harus commit setelah klaim**, lalu memproses di luar transaksi. Menahan transaksi selama pekerjaan berjalan menahan `VACUUM` dan kunci (anti-pola di teori). Karena `percobaan` sudah dinaikkan saat klaim, tugas yang worker-nya mati di tengah jalan tetap terhitung dan akhirnya masuk `gagal` lewat `pulihkan_macet`.
- Pada demo SQL, loop worker berjalan dalam **satu transaksi** hanya untuk memudahkan (`now()` bernilai tetap di dalam transaksi). Karena itu *backoff* > 0 tidak bisa didemonstrasikan di sana: tugas yang di-backoff tidak akan "cukup umur" sampai transaksi berakhir.
- Konsumen harus **idempoten**, karena retry berarti pekerjaan yang sama bisa dijalankan lebih dari sekali.
- Pantau tugas berstatus `gagal` (*dead-letter*) dan bersihkan atau arsipkan tugas `selesai` secara berkala.
- **Konkurensi `SKIP LOCKED`** tidak bisa saya uji. Ujilah dengan dua sesi, dengan klaim pertama di dalam `BEGIN` yang belum commit.

---

## Latihan 5: Membandingkan cara memuat 100.000 baris

`./jalankan.sh bulk` (atau `./bulk_ukur.sh 100000`) mengukur: (a) 100.000 `INSERT` terpisah, masing-masing transaksi sendiri; (a2, tambahan) 100.000 `INSERT` dalam satu transaksi; (b) satu `INSERT` multi-baris; (c) `COPY`. Waktu yang tercetak adalah waktu jam dinding di sisi klien, **termasuk overhead `docker exec`** dan pembuatan data oleh `awk`, sehingga cocok untuk membandingkan, bukan sebagai angka absolut. Cara (a) bisa memakan puluhan detik sampai menit.

**Isi hasil Anda** (saya tidak mengisinya karena belum dijalankan):

| Cara | Waktu (detik) | Baris/detik |
|---|---|---|
| (a) `INSERT` terpisah (autocommit) | | |
| (a2) `INSERT` dalam satu transaksi | | |
| (b) satu `INSERT` multi-baris | | |
| (c) `COPY` | | |

**Arah yang diharapkan:** (a) paling lambat, (c) paling cepat atau mendekati. **Pembuktian arah di SQLite** (20.000 baris, file di disk dengan `synchronous = FULL`): satu transaksi per baris **11,09 detik**, semua dalam satu transaksi **0,027 detik**, `executemany` 0,017 detik. Angka itu milik SQLite pada mesin ini dan **bukan** perkiraan untuk PostgreSQL, tetapi menunjukkan bahwa biaya terbesar bukan di `INSERT`-nya, melainkan di **commit per baris** (satu flush WAL/`fsync` tiap transaksi).

**Alasannya, per cara:**

| Cara | Mengapa lambat atau cepat |
|---|---|
| (a) | Per pernyataan: *parse*, *plan*, *round-trip* jaringan, **dan `COMMIT` (flush WAL) sendiri-sendiri** |
| (a2) | Satu commit saja, tetapi tetap parse/plan dan round-trip per pernyataan |
| (b) | Mengurangi parse/plan dan round-trip. Pernyataan raksasa memakan memori dan waktu parse |
| (c) | Jalur khusus pemuatan massal: tanpa parse/plan per baris, data dialirkan dalam satu perintah |

**Teknik pelengkap** dari teori 11.7: bungkus dalam satu transaksi, buat index **setelah** data dimuat, pakai tabel staging `UNLOGGED` (hilang saat crash), naikkan sementara `maintenance_work_mem`, dan `ANALYZE` setelahnya.

---

## Latihan 6: Dari 1 juta ke 1 miliar baris pesanan

Urutan yang saya sarankan, dari yang paling murah dan paling dulu. **Tidak ada angka ajaib**; ambang bergantung pada lebar baris, pola akses, dan perangkat keras. Yang menentukan adalah **gejala yang terukur**.

| Langkah | Mulai diperlukan ketika... | Cara memastikan | Harga yang dibayar |
|---|---|---|---|
| **1. Index dan perbaikan query** | Sejak hari pertama; query lambat muncul bahkan pada 1 juta baris | `pg_stat_statements`, `EXPLAIN (ANALYZE, BUFFERS)` (Modul 9-10, 16) | Tulis sedikit lebih lambat, disk bertambah |
| **2. Konfigurasi, vacuum, connection pooling, perangkat keras lebih besar** | CPU, memori, atau I/O jenuh; koneksi terlalu banyak; autovacuum tertinggal | Metrik sistem, `pg_stat_activity`, `n_dead_tup` | Murah dibanding kompleksitas arsitektur |
| **3. Arsip data lama** | Mayoritas pesanan adalah data dingin yang jarang dibaca (mis. pesanan yang sudah lama selesai) | Distribusi umur data yang benar-benar diakses | Perlu jalur baca terpisah untuk arsip |
| **4. Partisi menurut waktu** | Perawatan tabel mulai menyakitkan: vacuum, pembuatan index, atau penghapusan data lama terlalu lama; query hampir selalu dibatasi rentang waktu | Lama `VACUUM`/`CREATE INDEX`, ukuran tabel, rencana query | Kunci partisi harus masuk PK; pruning hanya bila filter pada kunci partisi; butuh otomatisasi pembuatan partisi |
| **5. Read replica** | Beban baca (laporan, pencarian) mengganggu beban transaksi atau melebihi kapasitas satu server | Pemakaian CPU/I/O pada primary oleh query baca | Ada *replication lag*; bukan solusi untuk skala **tulis** |
| **6. Sharding** | Terakhir: throughput **tulis** atau ukuran data melampaui satu primary yang sudah dioptimalkan dan dipartisi | Setelah langkah 1-5 terbukti tidak cukup | Kompleksitas besar: join lintas shard, transaksi terdistribusi, *resharding* |

**Gambaran ukuran (asumsi, bukan pengukuran):** 1 miliar baris pesanan dengan lebar ±200 byte kira-kira beberapa ratus GB data, plus index yang sebanding. Itu besar tetapi bukan hal yang mustahil bagi satu server PostgreSQL yang dipartisi dengan baik. Karena itu **sharding sering bisa ditunda jauh lebih lama** daripada yang diperkirakan, dan teori modul sendiri memang menaruhnya paling akhir.

---

## Latihan 7: Tiga migrasi Flyway (menjadi empat berkas)

Berkas di `flyway/sql/`:

| Berkas | Isi | Profil kunci |
|---|---|---|
| `V3__tambah_kolom_merek.sql` | `ADD COLUMN IF NOT EXISTS merek text` | Hanya metadata, **instan**; kunci ketat sangat singkat |
| `V4__isi_merek_bertahap.sql` | `UPDATE ... SET merek = 'Generik' WHERE merek IS NULL` | Kunci baris dan WAL sebanding jumlah baris; **bisa panjang** |
| `V5__merek_wajib_not_valid.sql` | `ADD CONSTRAINT produk_merek_wajib CHECK (merek IS NOT NULL) NOT VALID` | Kunci ketat (`ACCESS EXCLUSIVE`) **hanya sekejap**, tanpa memindai tabel |
| `V6__merek_wajib_validate.sql` | `VALIDATE CONSTRAINT produk_merek_wajib` | Memindai seluruh tabel dengan kunci yang **tidak memblokir tulis** |

**Mengapa saya memecah (c) menjadi V5 dan V6** (latihan meminta tiga migrasi): bila `NOT VALID` dan `VALIDATE` berada di migrasi yang sama, keduanya berjalan dalam **satu transaksi**, dan kunci ketat dari `ADD CONSTRAINT` **tertahan sampai commit**, termasuk selama `VALIDATE` memindai tabel. Tujuan `NOT VALID` (menghindari kunci panjang) hilang. Dengan dua migrasi, kunci ketat dilepas sebelum pemindaian dimulai.

**Mengapa semuanya dipisah** menjadi migrasi sendiri-sendiri:

1. **Profil kunci berbeda.** DDL cepat (V3, V5) tidak boleh digabung dengan pekerjaan panjang (V4, V6) yang menahan kunci.
2. **Mudah dihentikan dan diulang.** Bila V4 gagal atau lambat, V3 sudah selesai dan tercatat. Tidak ada rollback yang mengulang semuanya.
3. **Kompatibel dengan deploy tanpa downtime** (*expand → migrate → contract*): kode aplikasi bisa dirilis di antara langkah-langkahnya (mis. mulai menulis `merek` sebelum constraint dipasang).
4. **Checksum per migrasi** membuat riwayat dapat dipercaya dan setiap langkah dapat ditinjau sendiri.
5. Pada tabel besar, V4 bahkan **tidak seharusnya** satu `UPDATE`: lakukan per batch (lihat Latihan 9) sebagai pekerjaan terpisah, atau sebagai migrasi non-transaksional (cek dokumentasi Flyway tentang `executeInTransaction`). Itu tidak bisa dilakukan dalam transaksi bawaan Flyway karena `COMMIT` per batch dilarang di dalamnya.

**Langkah tambahan opsional (PostgreSQL 12+):** setelah `VALIDATE`, `ALTER TABLE ... ALTER COLUMN merek SET NOT NULL` dapat melewati pemindaian karena sudah ada constraint `CHECK (merek IS NOT NULL)` yang valid. Constraint itu kemudian bisa dihapus.

**Cara menjalankan** (belum diuji): `./flyway/jalankan_flyway.sh jaringan`, lalu `migrate`, `info`, `riwayat`. **(diharapkan)** `info` menampilkan V1 sampai V6 berstatus `Success`.

---

## Latihan 8: `SKIP LOCKED` vs PgQ

**Dua situasi PgQ lebih unggul:**

1. **Banyak consumer independen pada aliran event yang sama.** PgQ memberi tiap consumer posisinya sendiri, sedangkan pada `SKIP LOCKED` satu baris hanya diproses satu worker lalu selesai. Memberi dua sistem (email dan analitik) event yang sama berarti dua antrean.
2. **Volume event tinggi dengan perhatian pada *bloat*.** `SKIP LOCKED` melakukan `UPDATE`/`DELETE` per tugas yang menghasilkan *dead tuple*. PgQ menulis event ke tabel yang **dirotasi** sehingga hampir tanpa bloat, dan memprosesnya per *batch*. (Pola semacam ini juga mendasari replikasi berbasis trigger seperti Londiste.)

**Satu situasi `SKIP LOCKED` sudah cukup:** pekerjaan latar belakang berbeban sedang (mengirim email, membuat thumbnail) dengan satu kelompok worker, kebutuhan retry, prioritas, dan penjadwalan yang cukup dinyatakan lewat kolom biasa, dan tidak ingin menambah komponen. Keuntungannya: **tanpa ekstensi dan tanpa daemon tambahan**. PgQ membutuhkan ekstensi `pgq` dan daemon `pgqd` yang harus selalu berjalan (tanpa ticker tidak ada batch baru dan tabel tidak dirotasi). Ketersediaannya di layanan PostgreSQL terkelola perlu dicek (belum saya verifikasi).

Kesamaan: keduanya memungkinkan event dimasukkan **dalam transaksi yang sama** dengan perubahan datanya, dan keduanya menjamin pengiriman **minimal sekali** sehingga konsumen harus idempoten.

---

## Latihan 9: Tiga anti-pola migrasi dan versi amannya

Saya tidak punya proyek Anda untuk dilihat, jadi tiga anti-pola yang paling lazim ini saya jadikan contoh. Silakan ganti dengan yang pernah Anda temui.

**1. `RENAME COLUMN` langsung** → *expand → migrate → contract*:

```sql
-- Rilis 1 (expand): kolom baru, nullable. Aplikasi mulai menulis ke KEDUA kolom (atau pakai trigger).
ALTER TABLE produk ADD COLUMN nama_lengkap text;
-- Isi data lama secara bertahap (lihat anti-pola 2), lalu pasang constraint dengan NOT VALID + VALIDATE.
-- Rilis 2 (migrate): aplikasi membaca dari kolom baru.
-- Rilis 3 (contract): setelah tidak ada kode yang memakai kolom lama
ALTER TABLE produk DROP COLUMN nama;
```

Mengapa: `RENAME` instan mematahkan semua versi aplikasi lama yang masih berjalan selama deploy.

**2. `UPDATE` jutaan baris dalam satu transaksi** → batch bertahap:

```sql
DO $$
DECLARE n int;
BEGIN
  LOOP
    UPDATE t SET merek = 'Generik'
    WHERE id IN (SELECT id FROM t WHERE merek IS NULL LIMIT 10000);
    GET DIAGNOSTICS n = ROW_COUNT;
    EXIT WHEN n = 0;
    COMMIT;                -- commit per batch (PostgreSQL 11+, hanya di DO/procedure tingkat atas)
  END LOOP;
END $$;
```

Logika loop batch **terverifikasi di SQLite**: 25.000 baris dengan batch 10.000 menjadi batch 10.000, 10.000, dan 5.000, dan tidak ada baris tersisa. Blok `DO` di atas sendiri belum dijalankan di PostgreSQL. Mengapa: satu `UPDATE` besar menahan kunci lama, menulis WAL raksasa, membuat bloat, dan menahan vacuum. Beri jeda antar-batch bila replika sulit mengejar.

**3. `CREATE INDEX` biasa pada tabel ramai** → `CONCURRENTLY`:

```sql
SET lock_timeout = '3s';
CREATE INDEX CONCURRENTLY idx_produk_merek ON produk (merek);   -- tidak boleh di dalam BEGIN ... COMMIT
-- Bila gagal: index tertinggal INVALID. Cek lalu ulangi:
SELECT indexrelid::regclass FROM pg_index WHERE NOT indisvalid;
DROP INDEX CONCURRENTLY idx_produk_merek;
```

Mengapa: `CREATE INDEX` biasa memblokir penulisan selama pembuatan index. Versi `CONCURRENTLY` lebih lama tetapi tidak memblokir tulis.

---

## Lembar hasil Anda

| Langkah | Hasil Anda | Sesuai harapan? |
|---|---|---|
| Praktik: hitungan partisi 44.639 / 35.361 | | |
| Praktik: `EXPLAIN` hanya menampilkan `log_2026_11` | | |
| Praktik: keyset vs OFFSET pada `transaksi` asli (waktu mirip?) | | |
| Pagination pada salinan: tanpa vs dengan index | | |
| Latihan 1: rekonstruksi vs tabel lama kosong | | |
| Latihan 2: dua `CHECK` menolak; EAV: error `invalid input syntax` | | |
| Latihan 3: 33.334 / 33.333 / 33.333; pruning hanya satu partisi | | |
| Latihan 3: pruning pada `waktu::date`? | | |
| Latihan 4: status akhir `selesai/selesai/gagal`, percobaan 1/2/3 | | |
| Latihan 5: tabel waktu (a), (a2), (b), (c) | | |
| Latihan 7: `flyway info` V1-V6 `Success` | | |

---

## Catatan tambahan: ringkasan Modul 10 (pesan sebelumnya terpotong)

Ringkasan jawaban saya untuk Modul 10 terpotong sebelum Anda sempat membacanya, jadi inti pentingnya saya ulang di sini:

- **Tidak ada keluaran `EXPLAIN` yang saya klaim sebagai fakta.** Modul itu tentang membaca keluaran planner PostgreSQL, yang tidak bisa saya jalankan. Isinya berupa apa yang perlu dicari dan dugaan terarah.
- **Praktik nomor 7 Modul 10 menambah 200.000 baris permanen ke `transaksi`** (kini 1,2 juta baris).
- **Tabel `pelanggan` hanya 4 baris**, sehingga join di Praktik terlalu kecil untuk membandingkan algoritma join. `latihan.sql` Modul 10 membuat `pelanggan_uji` (10.001 baris).
- **Komentar `quicksort Memory` di teori kemungkinan keliru** karena ada `LIMIT` (kemungkinan `top-N heapsort`); itu pemahaman saya dan belum diuji.
- Hanya **konsep** yang terbukti (simulasi algoritma join, aritmetika estimasi usang, aturan *sargable*), dengan 15 pemeriksaan lolos.

## Sebelum lanjut ke Modul 12

Modul 12 memakai `transaksi` dan tidak memakai objek Modul 11, jadi jalankan `./jalankan.sh bersih` bila ingin membersihkan. Jika Anda menjalankan Flyway, bersihkan jaringannya dengan `./flyway/jalankan_flyway.sh bersih`, dan ingat bahwa `flyway_schema_history` serta `produk.merek` yang dibuat migrasi **tidak** ikut terhapus oleh `bersih.sql` (kolom `merek` dan `catatan` dihapus, tabel riwayat Flyway tidak). Hapus dengan `DROP TABLE flyway_schema_history;` bila perlu.
