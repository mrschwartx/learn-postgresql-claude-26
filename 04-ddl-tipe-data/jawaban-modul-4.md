# Jawaban Modul 4: DDL: Schema, Tabel & Tipe Data

## Status eksekusi (baca dulu)

Seperti Modul 3, **tidak ada perintah SQL di modul ini yang sudah saya jalankan di PostgreSQL**. Lingkungan saya tidak punya Docker maupun PostgreSQL dan tidak ada akses jaringan untuk memasangnya.

| Yang | Status |
|---|---|
| `praktik.sql` | Diambil **langsung dari teks modul** lewat skrip (bukan diketik ulang), tetapi belum dijalankan |
| `perpustakaan.sql` | DDL-nya **identik** dengan `rancangan_perpustakaan.sql` Modul 2, yang logikanya sudah diuji (29 pengujian, di SQLite). Belum dijalankan di PostgreSQL. |
| `latihan.sql` | Ditulis dan diperiksa secara manual, **belum dijalankan** |
| `demo_tipe.py` | **Sudah dijalankan** (Python). Ini analogi untuk Latihan 3, bukan PostgreSQL. |
| Hasil berlabel **(diharapkan)** | Berdasarkan perilaku PostgreSQL yang terdokumentasi, bukan output nyata |

Pengecualian atas label "diharapkan": saya tidak menulis nomor versi tepat atau waktu eksekusi. Isi kolom "Hasil Anda" di akhir setelah menjalankan.

| Berkas | Fungsi |
|---|---|
| `jalankan.sh` | `reset`, `praktik`, `perpustakaan`, `latihan`, `semua` (ke container `pg-latihan`, database `toko`) |
| `praktik.sql` | Praktik modul |
| `perpustakaan.sql` | Latihan 1 |
| `latihan.sql` | Latihan 2, 3, 4, 5 |
| `reset.sql` | Mengulang dari nol. **Menghapus schema `app`.** Jangan dijalankan di tengah Modul 5-16. |
| `demo_tipe.py`, `output_demo_tipe.txt` | Analogi Python untuk Latihan 3 |

**Urutan:** `./jalankan.sh praktik` dulu, baru `perpustakaan` dan `latihan` (Latihan 2 membutuhkan tabel `app.produk`). Saran: jangan pakai `semua` pada percobaan pertama, supaya Anda bisa memeriksa hasil per tahap.

---

## Praktik

### Membuat Schema dan Tabel

`./jalankan.sh praktik` membuat schema `app` dan empat tabel: `pelanggan`, `produk`, `pesanan`, `item_pesanan`.

**(diharapkan)**

- `\dt app.*` menampilkan empat tabel, tipe `table`, pemilik `postgres`.
- `\d app.pesanan` menampilkan:
  - kolom `id` bertanda `generated always as identity`, `status` dengan default `'baru'::text`, `dibuat_pada` dengan default `now()`;
  - index `pesanan_pkey` (PK);
  - check constraint `pesanan_status_check`;
  - foreign key `pesanan_pelanggan_id_fkey`;
  - bagian *Referenced by* yang menyebut `item_pesanan` dengan `ON DELETE CASCADE`.

  Nama constraint dibentuk otomatis dengan pola `<tabel>_<kolom>_<jenis>`: `_pkey`, `_key` (unique), `_check`, `_fkey`.

Catatan penting: `SET search_path TO app, public;` hanya berlaku untuk **sesi psql itu**. Di sesi baru, `produk` tanpa awalan `app.` tidak ditemukan, kecuali Anda mengatur ulang `search_path` atau memakai `app.produk`. Untuk membuatnya permanen: `ALTER DATABASE toko SET search_path TO app, public;` (berlaku di sesi berikutnya).

### Menguji Constraint dan Transactional DDL

| Langkah | (diharapkan) |
|---|---|
| `INSERT ... VALUES ('X-1','Uji',-5,0)` | `ERROR: new row for relation "produk" violates check constraint "produk_harga_check"` dan baris `DETAIL: Failing row contains (...)`. **Satu-satunya error yang disengaja di berkas ini.** |
| `BEGIN; ALTER TABLE produk ADD COLUMN kategori text; \d produk` | Kolom `kategori` terlihat |
| `ROLLBACK; \d produk` | Kolom `kategori` **hilang lagi**: bukti DDL transaksional |
| `ALTER TABLE ... ADD COLUMN kategori ... DEFAULT 'umum'`, `ADD COLUMN telepon`, `COMMENT ON TABLE` | `ALTER TABLE`, `ALTER TABLE`, `COMMENT` |
| Perangkap float | `float_sama = f`, `numeric_sama = t` |
| `'sedang'::prioritas < 'tinggi'::prioritas` | `t` (enum berurutan sesuai urutan deklarasi) |
| `ARRAY[1,2,3] @> ARRAY[2]` | `t` |
| `'{"warna":"merah","ukuran":"L"}'::jsonb ->> 'warna'` | `merah` |
| `daterange(...) && daterange(...)` | `t` (rentang beririsan 5-10 Januari) |
| `CREATE VIEW`, `CREATE MATERIALIZED VIEW`, `REFRESH` | `CREATE VIEW`, `SELECT 1`, `REFRESH MATERIALIZED VIEW` |

Hal yang patut dicatat:

1. **INSERT yang gagal tetap memakai nomor sequence.** Nilai identity diambil sebelum constraint diperiksa, sehingga `INSERT` yang ditolak membuat `id` berikutnya melompat. Modul 5 sudah mengantisipasi ini dengan `TRUNCATE ... RESTART IDENTITY` sebelum seed.
2. **`prioritas` dibuat di schema `app`**, karena schema pertama di `search_path` yang dipakai `CREATE`. View dan materialized view juga masuk ke `app`.
3. **`mv_ringkasan_produk` menampilkan `jumlah_produk = 0` dan `total_stok` kosong (NULL)** karena tabel `produk` belum berisi data. `sum()` atas himpunan kosong menghasilkan NULL. Materialized view tidak otomatis mengikuti data: setelah seed di Modul 5, ia masih menampilkan angka lama sampai `REFRESH`.
4. Pada `item_pesanan.harga_satuan` tidak ada `CHECK (harga_satuan >= 0)` seperti pada `produk.harga`. Itu pilihan modul; di produksi saya akan menambahkannya.

---

## Latihan 1: Schema `perpustakaan`

`./jalankan.sh perpustakaan` membuat schema `perpustakaan` dengan skema dari Latihan 4 Modul 2.

Latihan meminta tiga tabel (`buku`, `anggota`, `peminjaman`). Saya memakai rancangan Modul 2 yang lebih lengkap: **enam tabel** (`penulis`, `buku`, `buku_penulis`, `eksemplar`, `anggota`, `peminjaman`). Alasannya, `peminjaman` mereferensi `eksemplar` (salinan fisik), bukan langsung `buku`, dan penulis-buku adalah many-to-many. Ketiga tabel yang diminta tetap ada, lengkap dengan PK, FK, `UNIQUE`, dan banyak `CHECK` (permintaan minimal dua).

Ringkasan constraint kunci:

| Jenis | Contoh |
|---|---|
| PK | `id bigint GENERATED ALWAYS AS IDENTITY` pada tiap tabel; PK komposit `(buku_id, penulis_id)` pada `buku_penulis` |
| FK | `peminjaman.anggota_id → anggota`, `peminjaman.eksemplar_id → eksemplar`, `eksemplar.buku_id → buku` (semuanya `RESTRICT`), `buku_penulis.buku_id → buku` (`CASCADE`) |
| `UNIQUE` | `buku.isbn`, `eksemplar.barcode`, `anggota.email`, `anggota.nomor_anggota`, `(buku_id, urutan)` |
| `CHECK` | panjang ISBN, rentang tahun, `kondisi`, `status`, `jatuh_tempo >= tanggal_pinjam`, `tanggal_kembali`, `denda >= 0` |
| Partial unique index | `uq_peminjaman_aktif`: satu eksemplar hanya boleh dipinjam satu orang pada satu waktu |

**(diharapkan)** pada bagian uji di `perpustakaan.sql`: semua baris berlabel "DISENGAJA ERROR" gagal (ISBN pendek → `check constraint`, tahun 1200 → `check constraint`, jatuh tempo mendahului pinjam → `check constraint`, peminjaman ganda → `duplicate key value violates unique constraint "uq_peminjaman_aktif"`, hapus anggota → `violates foreign key constraint`), sedangkan peminjaman ulang setelah pengembalian **berhasil**. Logika yang sama sudah lolos 29 pengujian di SQLite pada Modul 2.

---

## Latihan 2: Kolom `rating` dan `NOT NULL` tanpa `DEFAULT`

### 2a. Menambahkan `rating`

```sql
ALTER TABLE produk ADD COLUMN rating numeric(2,1) CHECK (rating BETWEEN 0 AND 5);
```

**(diharapkan)**

- `numeric(2,1)` = total 2 digit, 1 di belakang koma, jadi rentang `-9.9` sampai `9.9`. `CHECK` membatasi lebih jauh ke 0-5.
- `rating = 5.5` lolos tipe, **gagal `CHECK`** (`produk_rating_check`). `rating = 10.0` akan gagal lebih awal dengan `numeric field overflow`.
- `rating` NULL dan `4.5` berhasil. `CHECK` yang bernilai NULL **dianggap lolos**, sehingga baris tanpa rating tidak ditolak. Itulah sebabnya perlu `NOT NULL` terpisah bila rating wajib.

### 2b. `NOT NULL` tanpa `DEFAULT` pada tabel berisi data

```sql
ALTER TABLE tabel ADD COLUMN wajib text NOT NULL;
```

| Kondisi tabel | (diharapkan) |
|---|---|
| **Sudah berisi baris** | **Gagal:** `ERROR: column "wajib" of relation "..." contains null values`. Baris lama tidak punya nilai, sehingga akan bernilai NULL dan melanggar `NOT NULL`. |
| **Kosong** | Berhasil |
| Berisi baris, **dengan `DEFAULT`** | Berhasil, baris lama terisi nilai default |

Untuk percobaan ini saya memakai tabel contoh di schema `latihan` (bukan `produk`), karena `produk` masih kosong dan tidak akan memperlihatkan kegagalan.

**Cara aman untuk tabel besar yang aktif:**

1. `ADD COLUMN kolom tipe` (nullable) → cepat, hanya mengubah metadata.
2. Isi nilai lama secara **bertahap** (batch) dengan `UPDATE`.
3. `ALTER COLUMN kolom SET NOT NULL` → memindai seluruh tabel sambil menahan *lock* ketat. Mulai PostgreSQL 12, pemindaian dilewati bila sudah ada `CHECK (kolom IS NOT NULL)` yang valid (dibuat lewat `NOT VALID` lalu `VALIDATE CONSTRAINT`).

**Kapan `ALTER` menulis ulang tabel?** `ADD COLUMN` dengan `DEFAULT` **konstan** tidak menulis ulang tabel (PostgreSQL 11+). Default yang volatil (mis. `random()`) dan `ALTER COLUMN ... TYPE` yang butuh konversi (mis. `int` → `bigint`) menulis ulang tabel. `latihan.sql` mengukurnya lewat `pg_relation_filenode`. **(diharapkan)** `tanpa_rewrite_add_default_konstan = t`, `tanpa_rewrite_alter_type = f`.

---

## Latihan 3: `numeric`, `timestamptz`, dan contoh bug

### `numeric` untuk uang

`double precision` menyimpan bilangan dalam biner, sehingga banyak desimal (0.1, 0.2) tidak bisa disimpan tepat. `numeric` menyimpan digit desimal secara eksak.

**Hasil nyata** (Python, analogi `double precision` vs `numeric`; ini bukan PostgreSQL, lihat `output_demo_tipe.txt`):

```
0.1 + 0.2 == 0.3          float  : False | 0.30000000000000004
0.1 + 0.2 == 0.3          Decimal: True
jumlah 0.1 sebanyak 10x   float  : 0.9999999999999999 | == 1.0 ? False
jumlah 0.1 sebanyak 10x   Decimal: 1.0 | == 1.0 ? True
1000 transaksi Rp0,10     float  : 99.9999999999986
1000 transaksi Rp0,10     Decimal: 100.0
```

**(diharapkan)** untuk PostgreSQL (`latihan.sql`): `float_sama = f`, `numeric_sama = t`; `sum(0.1::double precision)` atas 10 baris menampilkan `0.9999999999999999`, sedangkan `sum(0.1::numeric)` menampilkan `1.0`.

**Contoh bug bila memakai float untuk uang:**

- Rekonsiliasi keuangan tidak pernah tepat nol, dengan selisih sangat kecil yang membingungkan.
- Perbandingan `total = pembayaran` gagal meski angka tampak sama, sehingga pesanan lunas tetap berstatus "belum lunas".
- Galat menumpuk pada jutaan transaksi.

### `timestamptz` untuk waktu transaksi

| | `timestamptz` | `timestamp` |
|---|---|---|
| Yang disimpan | Satu titik waktu absolut (disimpan sebagai UTC) | Jam dinding tanpa zona |
| Saat dibaca | Ditampilkan dalam zona waktu sesi (`SET timezone`) | Ditampilkan apa adanya |
| Offset pada input (`+07`) | Dipakai untuk menghitung titik waktunya | **Dibuang diam-diam** |

Catatan: `timestamptz` **tidak menyimpan nama zona**. Ia menyimpan titik waktu, lalu mengonversinya saat ditampilkan.

**Contoh bug bila memakai `timestamp`:**

1. Transaksi pukul `10:00 +07` dan `10:00 +00` tersimpan sebagai nilai **identik**, padahal berbeda 7 jam. `latihan.sql` menguji hal ini: `'2026-11-23 10:00:00+07'::timestamp = '2026-11-23 10:00:00+00'::timestamp` **(diharapkan)** bernilai `t`.
2. Dua server aplikasi di zona berbeda mengisi kolom dari `now()` dengan jam lokal masing-masing, sehingga urutan kejadian menjadi salah. Analoginya di `output_demo_tipe.txt`: jam "10:00" naif dibaca sebagai 03:00 UTC oleh server di WIB, tetapi 10:00 UTC oleh server berzona UTC.
3. Laporan harian "per tanggal" bergeser ketika dilihat dari zona waktu lain, atau ketika pengguna di WIB, WITA, dan WIT dilayani sistem yang sama.
4. Di negara dengan DST, jam yang sama bisa terjadi dua kali saat jam mundur sehingga ambiguitas tidak bisa diselesaikan. Indonesia tidak memakai DST, tetapi punya tiga zona waktu.

`timestamp` tetap sah untuk **jam dinding lokal yang memang tidak terkait titik waktu**, mis. "toko buka pukul 09:00".

### `latihan.sql` bagian 3, nilai yang diharapkan

| Zona sesi | `timestamptz` dari `'2026-11-23 10:00:00+07'` | `timestamp` dari `'2026-11-23 10:00:00'` |
|---|---|---|
| `Asia/Jakarta` | `2026-11-23 10:00:00+07` | `2026-11-23 10:00:00` |
| `UTC` | `2026-11-23 03:00:00+00` | `2026-11-23 10:00:00` (tidak berubah) |

---

## Latihan 4: Sequence tidak transaksional

```sql
INSERT ... ('pertama')    RETURNING id;      -- id = 1
BEGIN;
INSERT ... ('dibatalkan') RETURNING id;      -- id = 2
ROLLBACK;
INSERT ... ('ketiga')     RETURNING id;      -- id = 3
SELECT * FROM latihan.uji_seq ORDER BY id;   -- hanya id 1 dan 3
```

**(diharapkan)** Baris `dibatalkan` tidak tersimpan, tetapi nomor 2 **sudah terpakai**, sehingga baris berikutnya mendapat `3`. Tabel akhir berisi `1` dan `3`, dengan satu "lubang".

**Mengapa:** sequence dirancang untuk konkurensi tinggi. Bila `nextval()` ikut di-rollback, transaksi lain yang berjalan bersamaan harus menunggu atau akan menerima nomor yang sama. Karena itu nilai yang sudah dibagikan tidak ditarik kembali. `INSERT` yang gagal karena constraint (seperti pada Praktik) juga memakai nomor.

Implikasi:

- Jangan mengandalkan identity sebagai **nomor urut tanpa celah** (nomor faktur resmi, nomor surat). Pakai tabel penghitung dengan lock, atau sistem penomoran terpisah.
- Lubang pada ID itu normal dan tidak berarti data hilang.

---

## Latihan 5: `EXCLUDE` untuk reservasi ruangan

```sql
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE TABLE reservasi_ruangan (
    id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ruangan text      NOT NULL,
    waktu   tstzrange NOT NULL,
    CONSTRAINT tidak_tumpang_tindih
        EXCLUDE USING gist (ruangan WITH =, waktu WITH &&)
);
```

Artinya: **tidak boleh ada dua baris yang `ruangan`-nya sama (`=`) dan `waktu`-nya beririsan (`&&`)**.

**(diharapkan)**

| Percobaan | Hasil |
|---|---|
| Ruangan A, 09:00-11:00 | Berhasil |
| Ruangan A, 10:00-12:00 (tumpang tindih) | **Gagal:** `ERROR: conflicting key value violates exclusion constraint "tidak_tumpang_tindih"` |
| Ruangan B, 10:00-12:00 | Berhasil (ruangan berbeda) |
| Ruangan A, 11:00-12:00 | Berhasil: `tstzrange` default `[)`, batas atas **eksklusif**, jadi rentang yang hanya bersentuhan tidak beririsan |

**Mengapa `btree_gist`:** index GiST secara bawaan tidak punya operator `=` untuk tipe skalar biasa seperti `text`. Extension `btree_gist` menyediakannya, sehingga `ruangan WITH =` dan `waktu WITH &&` bisa digabung dalam satu index GiST. Ekstensi ini termasuk paket contrib yang disertakan image Docker resmi.

**Mengapa lebih baik daripada cek di aplikasi:** pola "`SELECT` cek bentrok, lalu `INSERT`" rawan *race condition*, karena dua permintaan bersamaan bisa sama-sama lolos cek. `EXCLUDE` ditegakkan database secara atomik, jadi hanya satu yang berhasil. Ini adalah constraint khas PostgreSQL yang tidak ada padanannya di banyak database lain.

---

## Latihan 6: `view` vs `materialized view`

| | View | Materialized view |
|---|---|---|
| Penyimpanan | Hanya definisi query, tanpa data | Hasil query disimpan fisik |
| Kesegaran data | **Selalu terkini**, dihitung saat dibaca | **Basi** sampai `REFRESH MATERIALIZED VIEW` |
| Kecepatan baca | Sama dengan menjalankan query-nya | Cepat, membaca hasil yang sudah jadi |
| Bisa di-index | Tidak (index ada di tabel dasar) | **Ya** |
| Biaya | Nol penyimpanan | Penyimpanan + biaya refresh |

**View cocok:** query murah yang harus selalu akurat, atau untuk menyederhanakan query dan membatasi kolom yang boleh dilihat. Contoh: **`v_stok_menipis`** (produk dengan stok < 10) untuk halaman gudang. Datanya harus real-time, dan query-nya ringan.

**Materialized view cocok:** query agregasi berat yang dibaca sering tetapi boleh sedikit tertinggal. Contoh: **ringkasan penjualan bulanan per kategori** untuk dasbor manajemen, yang dihitung dari jutaan baris `item_pesanan` dan di-refresh tiap malam atau tiap beberapa menit. `REFRESH ... CONCURRENTLY` (butuh unique index) memungkinkan pembacaan tetap berjalan selama refresh.

Aturan praktis: mulai dengan view biasa. Ubah ke materialized view hanya bila query-nya terukur lambat **dan** pembaca bisa menerima data yang agak basi.

---

## Lembar hasil Anda

| Langkah | Hasil Anda | Sesuai harapan? |
|---|---|---|
| `\dt app.*` menampilkan 4 tabel | | |
| Error `produk_harga_check` muncul | | |
| `\d produk` di dalam transaksi menunjukkan `kategori`; setelah `ROLLBACK` tidak | | |
| `float_sama` / `numeric_sama` = f / t | | |
| `perpustakaan.sql`: semua error disengaja muncul, peminjaman ulang berhasil | | |
| Latihan 2b: error `contains null values` pada tabel berisi | | |
| Latihan 2b: filenode (konstan = t, alter type = f) | | |
| Latihan 3: `jumlah_float` dan `jumlah_numeric` | | |
| Latihan 4: id akhir = 1 dan 3 | | |
| Latihan 5: error `tidak_tumpang_tindih` | | |

## Sebelum lanjut ke Modul 5

Modul 5 memakai schema `app` dan tabel dari Praktik. Latihan tidak mengubah tabel `pelanggan`, `pesanan`, atau `item_pesanan`. Latihan 2a menambahkan kolom `rating` ke `produk`, sehingga `SELECT * FROM produk` di Modul 5 akan menampilkan satu kolom tambahan (nilainya NULL). Itu tidak merusak query lain. Schema `latihan` dan `perpustakaan` berdiri sendiri; hapus jika tidak diperlukan: `DROP SCHEMA latihan CASCADE;`.

**Jangan jalankan `reset.sql`** sebelum Modul 5, karena itu menghapus schema `app`.
