# Jawaban Modul 8: Advanced SQL & PL/pgSQL

## Status eksekusi (baca dulu)

PostgreSQL dan Docker tidak tersedia di lingkungan saya, jadi **tidak ada perintah di modul ini yang sudah dijalankan di PostgreSQL**. Logikanya saya uji di SQLite dan dengan hitungan independen di Python: **32 pemeriksaan, semuanya sesuai harapan** (`output_verifikasi_sqlite.txt`).

| Bagian | Status |
|---|---|
| Window function, recursive CTE, pertumbuhan bulanan, top-N per grup, rekursi tanggal | **Diuji nyata di SQLite**, hasilnya dibandingkan dengan hitungan Python |
| PL/pgSQL (`kurangi_stok`, `buat_pesanan`), trigger PostgreSQL, `LATERAL` | Hanya lewat **padanan** (`[PADANAN]`): fungsi Python + `SAVEPOINT`, trigger SQLite, dan loop per grup. Membuktikan **logikanya**, bukan sintaks PL/pgSQL. |
| `percentile_cont`, `date_trunc`, `CYCLE`, `CREATE TRIGGER ... EXECUTE FUNCTION`, pesan error PostgreSQL | **Tidak bisa diuji di sini.** Berlabel **(diharapkan)**. |

| Berkas | Fungsi |
|---|---|
| `praktik.sql` | Praktik, disalin langsung dari modul (isi tidak diubah) |
| `latihan.sql` | Latihan 1-5 |
| `bersih.sql`, `pulihkan.sql` | Menghapus objek modul ini dan mengembalikan data seed |
| `jalankan.sh` | `praktik`, `latihan`, `bersih` (= `bersih.sql` lalu `pulihkan.sql`) |
| `skema_dasar.sql`, `seed.sql`, `verifikasi_sqlite.py`, `output_verifikasi_sqlite.txt` | Bukti logika |

**Urutan:** `./jalankan.sh praktik` → `./jalankan.sh latihan`. Untuk mengulang: `./jalankan.sh bersih`.

> **Efek samping pada seed (penting untuk modul berikutnya).** Praktik mengubah data secara permanen: `kurangi_stok(1, 2)` menurunkan stok Laptop dari 10 menjadi 8, dan `harga + 5000` menaikkan harga Mouse dari 165.000 menjadi 170.000. Selain itu, tabel `produk` mendapat kolom `diubah_pada` dan dua trigger. `./jalankan.sh bersih` menghapus semuanya dan mengembalikan stok Laptop 10 dan harga Mouse 165.000 (keadaan akhir Modul 5).

---

## Praktik

### Persiapan Data Uji

**(diharapkan)** `SELECT 12` untuk `CREATE TABLE penjualan AS ...`, `INSERT 0 6` untuk `karyawan`.

**Data `penjualan` bersifat acak** (`random()`), sehingga angka di bawah ini berbeda tiap kali dijalankan. Untuk jawaban yang bisa diverifikasi, saya memakai tabel tetap `penjualan_uji` (12 baris, tanggal dan total yang sama dengan pola modul) di `latihan.sql`. Dua catatan tentang data acak itu:

- `(random()*3)::int + 1` menghasilkan 1 sampai 4, tetapi nilai 1 dan 4 lebih jarang muncul daripada 2 dan 3 (pembulatan). Bisa saja ada pelanggan yang tidak muncul sama sekali.
- Tanggalnya `2026-01-01 + 3*g`, jadi 12 baris itu mencakup **hanya dua bulan** (Januari: 10 baris, Februari: 2 baris). Itu penting untuk Latihan 1.

### Window Function

Terverifikasi pada `penjualan_uji` (dibandingkan dengan hitungan Python untuk seluruh 12 baris): `sum(...) OVER (PARTITION BY pelanggan_id ORDER BY tanggal)` memberi total berjalan per pelanggan, `lag()` memberi total transaksi sebelumnya (NULL pada transaksi pertama pelanggan), dan `rank() OVER (ORDER BY total DESC)` memberi peringkat global.

Perilaku yang perlu dipahami:

- **Total berjalan** memakai frame bawaan `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`. Jika dua baris punya `tanggal` sama (peer), keduanya mendapat total berjalan yang sama. Pada data ini tanggalnya unik.
- **`rank()` vs `dense_rank()`**: bila ada total yang sama, `rank()` melompati nomor berikutnya (1, 1, 3), sedangkan `dense_rank()` tidak (1, 1, 2). Pada `penjualan_uji` semua total berbeda sehingga hasilnya sama.

**Top-2 per pelanggan** (`row_number()`), terverifikasi:

| pelanggan | baris terpilih (id, total) |
|---|---|
| 1 | (10, 800.000), (3, 750.000) |
| 2 | (5, 450.000), (2, 300.000) |
| 3 | (12, 650.000), (8, 350.000) |
| 4 | (7, 900.000), (11, 400.000) |

**Median:** untuk 12 total di `penjualan_uji`, nilai tengahnya adalah rata-rata dua nilai tengah (450.000 dan 500.000), yaitu **475.000** (hitungan Python). **(diharapkan)** `percentile_cont(0.5) WITHIN GROUP (ORDER BY total)` menghasilkan `475000` bertipe `double precision`. Fungsi ini tidak ada di SQLite, jadi tidak bisa saya jalankan.

### Recursive CTE

Terverifikasi (enam baris, urut menurut `jalur`):

```
Direktur
  Manajer A
    Staf A1
    Staf A2
  Manajer B
    Staf B1
```

Cara kerja: bagian *anchor* memilih akar (`atasan_id IS NULL`), bagian rekursif terus menggabungkan karyawan yang atasannya ada di hasil sebelumnya (`level + 1`), berhenti saat tidak ada baris baru.

**Catatan urutan.** Mengurutkan dengan `ORDER BY jalur` (teks) di PostgreSQL mengikuti *collation* database, bukan urutan biner seperti di SQLite. Untuk nama sederhana ini hasilnya kemungkinan sama, tetapi untuk urutan pohon yang pasti, bawa array jalur (`ARRAY[id]` lalu `|| k.id`) dan urutkan dengan array itu.

### Function dan Trigger

**(diharapkan)**

| Langkah | Hasil |
|---|---|
| `SELECT kurangi_stok(1, 2);` | `8` (stok Laptop 10 → 8) |
| `SELECT kurangi_stok(1, 9999);` | `ERROR: Stok tidak cukup (8 < 9999)`, diikuti baris `CONTEXT: PL/pgSQL function kurangi_stok(bigint,integer) line N at RAISE` |
| `UPDATE produk SET harga = harga WHERE id = 1;` lalu `SELECT ... diubah_pada` | `diubah_pada` terisi waktu sekarang |

Logika kedua fungsi diverifikasi lewat padanan Python: `kurangi_stok(1, 2)` mengembalikan 8, dan `kurangi_stok(1, 9999)` gagal dengan pesan yang sama.

Hal yang patut diketahui:

1. **`UPDATE ... SET harga = harga` tetap menjalankan trigger dan tetap membuat versi baris baru** (MVCC, Modul 7), walau nilainya tidak berubah. Trigger `BEFORE UPDATE` mengisi `diubah_pada` untuk update yang sebenarnya tidak mengubah apa pun. PostgreSQL menyediakan fungsi bawaan `suppress_redundant_updates_trigger` bila ingin mengabaikan update semacam itu.
2. **`FOR UPDATE` di `kurangi_stok`** mengunci baris produk sampai transaksi selesai, sehingga dua pesanan serentak untuk produk yang sama berjalan bergantian dan tidak menjual stok yang sama dua kali.

### Audit Trigger

**(diharapkan)** `SELECT * FROM audit_harga` menampilkan satu baris: `produk_id = 2`, `harga_lama = 165000.00`, `harga_baru = 170000.00`, dan `waktu` sekarang. Kedua trigger aktif pada `UPDATE` itu: `BEFORE` mengisi `diubah_pada`, `AFTER` mencatat audit.

Logika `IS DISTINCT FROM` diverifikasi dengan trigger SQLite yang setara: `UPDATE ... SET harga = harga` **tidak** mencatat audit, sedangkan `harga + 5000` mencatat tepat satu baris (165000 → 170000). `IS DISTINCT FROM` dipakai (bukan `<>`) agar perubahan dari atau ke NULL tetap terdeteksi.

### Catatan atas contoh di teori

Contoh procedure `arsipkan_pesanan_lama()` di bagian teori punya beberapa jebakan:

- `COMMIT` di dalam procedure hanya bekerja bila `CALL` dijalankan **di luar blok transaksi eksplisit**. Jika dipanggil setelah `BEGIN`, hasilnya `ERROR: invalid transaction termination`.
- Antara `COMMIT` pertama dan kedua, data bisa berubah. Dan bila prosedur gagal setelah `INSERT` ke arsip tetapi sebelum `DELETE` selesai, menjalankannya lagi menyalin baris yang sama dua kali (tidak idempoten).
- Item pesanan ikut terhapus lewat `ON DELETE CASCADE` tanpa diarsipkan (temuan yang sama dengan Latihan 4 Modul 6).

---

## Latihan 1: Pertumbuhan bulanan dengan `lag()`

```sql
WITH bulanan AS (
    SELECT date_trunc('month', tanggal)::date AS bulan, sum(total) AS total
    FROM penjualan_uji GROUP BY 1
), dengan_lag AS (
    SELECT bulan, total, lag(total) OVER (ORDER BY bulan) AS total_sebelumnya
    FROM bulanan
)
SELECT bulan, total, total_sebelumnya,
       round(100.0 * (total - total_sebelumnya) / NULLIF(total_sebelumnya, 0), 2) AS pertumbuhan_persen
FROM dengan_lag ORDER BY bulan;
```

Hasil (angka terverifikasi di SQLite; `date_trunc` khas PostgreSQL):

| bulan | total | total_sebelumnya | pertumbuhan_persen |
|---|---|---|---|
| 2026-01-01 | 5.100.000 | NULL | NULL |
| 2026-02-01 | 1.050.000 | 5.100.000 | **-79,41** |

**Penjelasan:**

- Agregasi per bulan dulu di CTE pertama, baru `lag()` di CTE kedua. Dengan begitu `lag()` dihitung sekali, tidak diulang tiga kali di rumus.
- Bulan pertama tidak punya pendahulu, sehingga `lag()` menghasilkan NULL dan persentasenya NULL (bukan 0).
- `NULLIF(total_sebelumnya, 0)` mencegah error pembagian nol bila bulan sebelumnya bertotal 0.
- Februari hanya memuat 2 baris, jadi turun tajam. Itu akibat data yang berhenti di 6 Februari, bukan penurunan bisnis.

**Jebakan celah bulan:** `lag()` membandingkan dengan baris **sebelumnya yang ada**, bukan bulan kalender sebelumnya. Jika Maret tidak punya penjualan, April akan dibandingkan dengan Februari. Untuk pertumbuhan bulan-ke-bulan yang benar, buat deret bulan dengan `generate_series` lalu `LEFT JOIN` ke agregat (bulan kosong menjadi 0).

---

## Latihan 2: Top-3 produk terlaris per kategori

"Terlaris" saya definisikan sebagai jumlah unit terjual pada pesanan yang **tidak batal**. Dasarnya view sementara `terjual` (`FILTER (WHERE p.status <> 'batal')`). Hasil `qty` (terverifikasi): Laptop 1, Mouse 3, Keyboard 1, Monitor 2, **Headset 0** (satu-satunya penjualannya ada di pesanan yang batal).

**Cara 1: `row_number()`**

```sql
SELECT kategori, nama, qty, n FROM (
    SELECT t.*, row_number() OVER (PARTITION BY kategori ORDER BY qty DESC, id) AS n FROM terjual t
) x WHERE n <= 3 ORDER BY kategori, n;
```

**Cara 2: `LATERAL`**

```sql
SELECT k.kategori, x.nama, x.qty
FROM (SELECT DISTINCT kategori FROM produk) k
CROSS JOIN LATERAL (
    SELECT t.nama, t.qty FROM terjual t WHERE t.kategori = k.kategori
    ORDER BY t.qty DESC, t.id LIMIT 3
) x ORDER BY k.kategori, x.qty DESC;
```

Hasil, terverifikasi (cara 1 langsung; cara 2 lewat padanan loop per kategori dengan hasil yang sama persis):

| Skenario | Hasil |
|---|---|
| Semua kategori `umum` (kondisi seed) | umum: Mouse (3), Monitor (2), Laptop (1) |
| Tiga kategori sementara | aksesori: Mouse (3), Keyboard (1); komputer: Monitor (2), Laptop (1); umum: Headset (0) |

Dengan satu kategori, tiga produk teratas dipilih dari 5. Dengan tiga kategori, tiap kategori hanya punya 1-2 produk sehingga semuanya muncul. Pada seri (Keyboard dan Laptop sama-sama 1), `id` sebagai pemutus seri membuat hasilnya pasti.

**Perbandingan keterbacaan:**

| | `row_number()` | `LATERAL` |
|---|---|---|
| Struktur | Subquery bersarang plus filter `n <= 3` | Terbaca seperti "untuk setiap kategori, ambil 3 teratas" |
| Fleksibilitas | Mudah ganti `rank()`/`dense_rank()` untuk menangani seri | `LIMIT` memotong tegas, seri tidak ikut |
| Performa | Memberi nomor pada **semua** baris, lalu membuang | Bisa hanya membaca N baris per grup bila ada index yang cocok |
| Yang lebih mudah dipahami pemula | Window function sudah umum di SQL standar | Perlu mengerti `LATERAL` |

Rekomendasi saya: `row_number()` untuk kasus umum dan data kecil sampai menengah; `LATERAL` bila jumlah grup sedikit, setiap grup besar, dan ada index pendukung. Klaim performa itu bergantung pada data dan index, dan belum saya ukur.

---

## Latihan 3: `buat_pesanan` yang atomik

DDL lengkap ada di `latihan.sql`. Intinya:

```sql
CREATE OR REPLACE FUNCTION buat_pesanan(p_pelanggan bigint, p_produk bigint, p_jumlah int)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE v_pesanan bigint; v_harga numeric;
BEGIN
    IF p_jumlah IS NULL OR p_jumlah <= 0 THEN
        RAISE EXCEPTION 'Jumlah harus lebih dari 0 (diminta %)', p_jumlah;
    END IF;
    PERFORM kurangi_stok(p_produk, p_jumlah);
    SELECT harga INTO v_harga FROM produk WHERE id = p_produk;
    INSERT INTO pesanan (pelanggan_id) VALUES (p_pelanggan) RETURNING id INTO v_pesanan;
    INSERT INTO item_pesanan (pesanan_id, produk_id, jumlah, harga_satuan)
    VALUES (v_pesanan, p_produk, p_jumlah, v_harga);
    RETURN v_pesanan;
END; $$;
```

**Mengapa atomik tanpa kode transaksi apa pun:** fungsi berjalan **di dalam transaksi pemanggilnya**. Bila terjadi error di mana pun (stok kurang, FK gagal, constraint), exception merambat keluar dan seluruh efek pernyataan pemanggil dibatalkan: stok kembali, pesanan dan item tidak tersimpan. Jangan menambahkan blok `EXCEPTION` yang menelan error, karena fungsi akan kembali seolah sukses. Tangkap error hanya bila Anda memang punya penanganan khusus.

**Urutan langkah disengaja:** `kurangi_stok` dipanggil **pertama** supaya kegagalan paling umum (stok tidak cukup) terjadi sebelum ada `INSERT`. Itu menghemat kerja dan mengurangi "lubang" nomor identity. Atomisitasnya sendiri tidak bergantung pada urutan.

**Hasil yang diuji lewat padanan Python + `SAVEPOINT`** (semuanya kembali ke keadaan awal 5 pesanan, 6 item, stok Monitor 5):

| Kasus | Hasil |
|---|---|
| Stok tidak cukup (9999) | Gagal, tidak ada data setengah jadi |
| **Pelanggan 999 tidak ada** (stok **sudah dikurangi**, lalu `INSERT pesanan` gagal oleh FK) | Gagal, **stok kembali ke 5** |
| Jumlah 0 | Gagal |
| Sukses `buat_pesanan(2, 4, 2)` | +1 pesanan, +1 item, stok 5 → 3 |
| Satu transaksi: sukses lalu gagal, lalu `ROLLBACK` | Kembali ke keadaan awal |

Kasus kedua adalah pembuktian atomisitas yang sesungguhnya: ada perubahan (stok berkurang) yang harus dibatalkan karena kegagalan **sesudahnya**.

**(diharapkan)** pesan error di PostgreSQL:

- `ERROR: Stok tidak cukup (5 < 9999)`
- `ERROR: insert or update on table "pesanan" violates foreign key constraint "pesanan_pelanggan_id_fkey"` dengan `DETAIL: Key (pelanggan_id)=(999) is not present in table "pelanggan".`

Di dalam transaksi eksplisit, error pada pemanggilan kedua membuat **seluruh transaksi** berstatus *aborted*, termasuk pesanan pertama yang sukses. Hanya `ROLLBACK` yang diterima (Modul 7).

---

## Latihan 4: Trigger pencegah `DELETE` pelanggan ber-pesanan aktif

```sql
CREATE FUNCTION cegah_hapus_pelanggan() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_aktif int;
BEGIN
    SELECT count(*) INTO v_aktif FROM pesanan
    WHERE pelanggan_id = OLD.id AND status IN ('baru', 'dibayar', 'dikirim');
    IF v_aktif > 0 THEN
        RAISE EXCEPTION 'Pelanggan % (%) tidak boleh dihapus: masih punya % pesanan aktif',
              OLD.id, OLD.nama, v_aktif
              USING ERRCODE = 'restrict_violation',
                    HINT = 'Selesaikan atau batalkan pesanan tersebut terlebih dahulu.';
    END IF;
    RETURN OLD;
END; $$;

CREATE TRIGGER trg_cegah_hapus_pelanggan BEFORE DELETE ON pelanggan
FOR EACH ROW EXECUTE FUNCTION cegah_hapus_pelanggan();
```

"Pesanan aktif" saya definisikan sebagai status `baru`, `dibayar`, atau `dikirim` (bukan `selesai`/`batal`).

**Hasil logika** (padanan dengan trigger SQLite, terverifikasi):

| Skenario | Hasil |
|---|---|
| FK biasa + trigger: hapus Budi (pesanan `baru`) | Ditolak oleh **trigger** |
| FK biasa + trigger: hapus Andi (`selesai` + `dibayar`) | Ditolak oleh **trigger** |
| FK biasa + trigger: hapus Dedi (hanya `batal`) | Lolos trigger, tetapi **ditolak FK** |
| FK biasa tanpa trigger: hapus Budi | Ditolak FK dengan pesan generik |
| FK `ON DELETE CASCADE` + trigger: hapus Budi | Ditolak trigger |
| FK `ON DELETE CASCADE` + trigger: hapus Dedi | **Berhasil**, pesanan batalnya ikut terhapus |
| FK `ON DELETE CASCADE` **tanpa** trigger: hapus Budi | **Berhasil, pesanan aktifnya ikut terhapus** (bahaya) |

**Mengapa FK saja tidak cukup untuk aturan ini:**

1. **FK hanya tahu "ada atau tidak ada" baris yang mereferensi, bukan keadaannya.** Aturan "yang menghalangi hanya pesanan aktif" tidak bisa dinyatakan dengan FK. FK bawaan menolak penghapusan pelanggan yang punya pesanan apa pun, termasuk pesanan yang sudah selesai atau batal (lihat kasus Dedi).
2. **Memperlonggar FK dengan `CASCADE` membuka lubang.** Penghapusan pelanggan lalu ikut menghapus pesanan aktifnya tanpa peringatan (kasus terakhir pada tabel). Trigger menutup lubang itu sambil mengizinkan kasus yang memang sah.
3. **`CHECK` tidak bisa melihat tabel atau baris lain**, jadi aturan lintas tabel yang bergantung pada keadaan data tidak bisa ditaruh di sana.
4. **Pesan error yang jelas** dan kode error khusus (`restrict_violation`), alih-alih pesan FK yang generik.

**Peringatan:**

- Pemeriksaan di trigger membaca keadaan data saat itu. Jika transaksi lain **sedang** membuat pesanan aktif untuk pelanggan yang sama dan belum commit, trigger tidak melihatnya. Apakah celah itu tertutup oleh FK dan penguncian baris bergantung pada detail penguncian. Saya belum menguji skenario konkurensi ini, jadi **ujilah dengan dua sesi** sebelum mengandalkannya.
- Menghapus pelanggan beserta riwayat pesanannya jarang diinginkan. Untuk data transaksi, pola yang lebih umum adalah *soft delete* (kolom `dihapus_pada` atau status `nonaktif`) atau anonimisasi data pribadi.
- Pengujian trigger di `latihan.sql` memakai `ALTER TABLE ... ON DELETE CASCADE` di dalam transaksi yang di-`ROLLBACK`. DDL di PostgreSQL bersifat transaksional (Modul 4), jadi FK semula kembali utuh. Perintah itu mengambil kunci ketat sehingga hanya cocok di database latihan.

---

## Latihan 5: Tanggal satu bulan dengan `WITH RECURSIVE`

```sql
WITH RECURSIVE tgl AS (
    SELECT date '2028-02-01' AS d
  UNION ALL
    SELECT d + 1 FROM tgl
    WHERE d + 1 < (date_trunc('month', date '2028-02-01') + interval '1 month')::date
)
SELECT d FROM tgl;
```

Versi `generate_series`:

```sql
SELECT d::date FROM generate_series(date '2028-02-01', date '2028-02-29', interval '1 day') AS d;
```

**Hasil logika** (rekursi diuji di SQLite dengan `date(d, '+1 day')`): untuk tiga bulan, jumlah dan isi tanggalnya **sama dengan kalender** Python:

| Bulan | Jumlah tanggal |
|---|---|
| November 2026 | 30 |
| Februari 2028 (kabisat) | 29 |
| Februari 2026 | 28 |

**(diharapkan)** `latihan.sql` membandingkan kedua cara dengan `EXCEPT` dua arah, dan hasilnya kosong (identik).

**Mana yang lebih sederhana: `generate_series()`.** Satu panggilan fungsi, tanpa kondisi berhenti yang harus ditulis sendiri, dan tidak bisa menggantung. Pada versi rekursif, akhir bulan harus dihitung lewat `date_trunc` + `interval`, dan **salah menulis kondisi berhenti membuat rekursi tak berujung**. Catatan: `generate_series` dengan argumen `date` + `interval` di PostgreSQL menghasilkan `timestamp with time zone`, karena itu hasilnya di-cast `::date`.

**Kapan rekursif tepat:** bila nilai berikutnya bergantung pada baris sebelumnya dengan cara yang bukan deret aritmetika, yaitu data hierarkis atau graf (Praktik: struktur organisasi). Untuk graf yang bisa memuat siklus, gunakan klausa `CYCLE` (PostgreSQL 14+) atau batasi `level`, agar rekursi tidak berputar tanpa henti. `CYCLE` tidak bisa saya uji di sini.

---

## Latihan 6: Function/trigger database atau kode aplikasi?

**Logika di function/trigger database**

| Kelebihan | Risiko |
|---|---|
| **Ditegakkan untuk semua klien.** Aplikasi web, skrip, dan siapa pun yang terkoneksi tunduk pada aturan yang sama (Latihan 4). | **Tersembunyi dan sulit dilacak.** Perilaku "ajaib" saat `UPDATE` sulit di-debug dan mudah terlewat dalam *code review*. |
| **Atomik dan dekat dengan data.** Satu panggilan menggantikan banyak round-trip, dan semua langkah ada dalam satu transaksi (Latihan 3). | **Sulit diuji dan di-versi.** Perlu migrasi terkelola; tooling debugging dan observabilitasnya lebih terbatas daripada kode aplikasi. |
| Konsisten lintas bahasa dan layanan. | Menambah beban di database (CPU), yang lebih sulit diskalakan daripada server aplikasi. |
| | *Vendor lock-in*: PL/pgSQL tidak portabel ke DBMS lain. |

**Logika di kode aplikasi**

| Kelebihan | Risiko |
|---|---|
| Mudah diuji (unit test), di-debug, dan di-versi bersama kode lain. | **Tidak ditegakkan untuk klien lain.** Skrip manual atau layanan lain bisa melanggarnya. |
| Mudah diskalakan (tambah server aplikasi) dan memakai pustaka serta bahasa yang dikuasai tim. | **Pola baca-lalu-tulis rawan *race condition*** bila tidak dibungkus transaksi dan penguncian yang benar. |
| Aturan yang sering berubah mudah di-deploy tanpa migrasi database. | Banyak round-trip jaringan untuk operasi yang terdiri dari banyak langkah. |
| | Aturan bisa terduplikasi dan tidak seragam di beberapa layanan. |

**Pedoman praktis:**

- **Taruh di database** aturan *integritas data* yang harus berlaku apa pun kliennya: constraint, FK, `CHECK`, `EXCLUDE`, dan trigger audit yang sederhana dan deterministik. Contohnya aturan yang tidak boleh dilanggar siapa pun.
- **Taruh di aplikasi** logika bisnis yang kompleks, sering berubah, butuh integrasi eksternal (email, API pembayaran), atau butuh pengujian ketat.
- Mulailah dengan constraint deklaratif. Trigger dan function dipakai bila constraint tidak cukup, seperti pada Latihan 4. Prinsip modul ini sendiri: pakai trigger **secukupnya**.

---

## Lembar hasil Anda

| Langkah | Hasil Anda | Sesuai harapan? |
|---|---|---|
| Praktik: `kurangi_stok(1, 2)` mengembalikan 8; `(1, 9999)` error | | |
| Praktik: `diubah_pada` terisi setelah `UPDATE` | | |
| Praktik: `audit_harga` berisi 1 baris (165000.00 → 170000.00) | | |
| Praktik: pohon organisasi 6 baris, urutan benar | | |
| Latihan 1: bulan Februari `-79.41` | | |
| Latihan 2: top-3 (satu kategori dan tiga kategori) | | |
| Latihan 3: stok kurang → error; pelanggan 999 → error FK dan stok Monitor tetap 5 | | |
| Latihan 3: berhasil → +1 pesanan, +1 item, stok 5 → 3 (lalu rollback) | | |
| Latihan 4: Budi ditolak trigger; Dedi ditolak FK; setelah FK CASCADE, Dedi berhasil dihapus | | |
| Latihan 5: 29 baris, selisih dengan `generate_series` kosong | | |

## Sebelum lanjut ke Modul 9

Jalankan `./jalankan.sh bersih` bila Anda ingin data produk kembali seperti akhir Modul 5 dan semua objek Modul 8 dihapus. Modul 9 (index) tidak memerlukan fungsi atau trigger dari modul ini, dan trigger `trg_produk_diubah` serta `trg_audit_harga` akan menambah overhead tiap `UPDATE` produk bila dibiarkan.
