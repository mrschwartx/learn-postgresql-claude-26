# Jawaban Modul 6: Join, Subquery, Grouping, CTE & Set Operations

## Status eksekusi (baca dulu)

PostgreSQL dan Docker tidak tersedia di lingkungan saya, jadi **tidak ada perintah di modul ini yang sudah dijalankan di PostgreSQL**. Sebagian besar isi modul ini SQL standar, sehingga logikanya saya uji di SQLite memakai skema dan `seed.sql` asli. Hasilnya: **29 pemeriksaan, semuanya sesuai harapan** (`output_verifikasi_sqlite.txt`).

| Bagian | Status |
|---|---|
| JOIN, `GROUP BY`/`HAVING`/`FILTER`, subquery, CTE biasa, `UNION`/`EXCEPT`, `NOT IN` vs `NOT EXISTS`, `COALESCE` | **Diuji nyata di SQLite** |
| `ROLLUP`, `LATERAL`, CTE data-modifying (`WITH ... DELETE ... RETURNING`) | SQLite **tidak mendukungnya**. Saya menguji **padanannya** (ditandai `[PADANAN]`) terhadap hasil yang dihitung tangan. Sintaks aslinya baru terbukti saat Anda menjalankannya di psql. |
| Error `GROUP BY` (Latihan 6), `EXPLAIN` (Latihan 5), format `numeric` | **Tidak bisa dibuktikan di SQLite** (SQLite justru menerima query Latihan 6). Berlabel **(diharapkan)**. |

| Berkas | Fungsi |
|---|---|
| `praktik.sql` | Praktik, disalin langsung dari modul (isi query tidak diubah) |
| `latihan.sql` | Latihan 1-6 |
| `jalankan.sh` | `praktik`, `latihan`, `semua` |
| `skema_dasar.sql`, `seed.sql`, `verifikasi_sqlite.py`, `output_verifikasi_sqlite.txt` | Bukti logika di SQLite |

**Urutan:** Modul 5 harus sudah selesai (seed ada), lalu `./jalankan.sh praktik` dan `./jalankan.sh latihan`. Semua data uji di `latihan.sql` (pelanggan Eka, kategori produk, tabel arsip) dibuat di dalam `BEGIN ... ROLLBACK`, jadi data seed tidak berubah. Konsekuensinya, nomor identity yang terpakai tidak kembali (ada "lubang" di ID).

---

## Praktik

Hasil di bawah terverifikasi di SQLite dengan data seed (kondisi akhir Modul 5).

| Query | Hasil |
|---|---|
| INNER JOIN `pelanggan`-`pesanan` | 5 baris: Andi (selesai, dibayar), Budi (baru), Citra (selesai), Dedi (batal) |
| LEFT JOIN + `count(p.id)` | Andi 2, Budi 1, Citra 1, Dedi 1 |
| JOIN 4 tabel | 6 baris detail, subtotal: 12.500.000, 300.000, 850.000, 150.000, 4.400.000, 450.000 |
| `GROUP BY status` | selesai 2, dibayar 1, baru 1, batal 1 |
| `count(*) FILTER (WHERE status='selesai')` | total 5, selesai 2 |
| `ROLLUP (nama, status)` | 10 baris: 5 detail + 4 subtotal per pelanggan + 1 grand total (5) |
| Produk di atas harga rata-rata | Hanya **Laptop 14 inci** (rata-rata 3.233.000) |
| Produk yang belum pernah dipesan (`NOT EXISTS`) | **Kosong** |
| `SELECT id FROM produk EXCEPT SELECT produk_id FROM item_pesanan` | **Kosong** |
| CTE total belanja | Andi 13.650.000; Citra 4.400.000; Dedi 450.000; Budi 150.000 |
| `UNION ALL` pelanggan `@contoh.com` + produk > 1 juta | 5 baris: Andi, Budi, Citra, Laptop 14 inci, Monitor 24 inci |

### Temuan yang perlu diketahui

1. **Dua query "anti-join" di Praktik mengembalikan hasil kosong pada data seed.** Seluruh 5 produk pernah dipesan, dan seluruh 4 pelanggan punya pesanan. Itu bukan error, melainkan datanya belum memuat kasus yang dicari. Untuk melihat hasil tidak kosong, tambahkan data uji (contoh: Latihan 2 memakai pelanggan Eka).
2. **LEFT JOIN dan INNER JOIN menampilkan pelanggan yang sama** pada seed, karena tidak ada pelanggan tanpa pesanan. Perbedaannya baru terlihat bila ada pelanggan tanpa pesanan.
3. **Query LATERAL "pesanan terbaru per pelanggan" bersifat tidak deterministik untuk Andi.** Kedua pesanan Andi (id 1 dan 2) dimasukkan dalam satu `INSERT`, sehingga `now()` (waktu awal transaksi) **sama persis**. Terbukti di SQLite: hanya 1 nilai `dibuat_pada` berbeda untuk Andi. `ORDER BY dibuat_pada DESC LIMIT 1` lalu memilih salah satunya secara sembarang. Perbaikan: tambah pemutus seri, `ORDER BY dibuat_pada DESC, id DESC`. Dengan perbaikan itu hasilnya: Andi → pesanan 2, Budi → 3, Citra → 4, Dedi → 5 (terverifikasi lewat padanan).
4. **`ROLLUP` memberi `NULL` pada baris subtotal**, yang sulit dibedakan dari `NULL` asli di data. Pakai `GROUPING(c.nama)` untuk membedakannya. Urutan baris hasil juga tidak dijamin tanpa `ORDER BY`.
5. **Format angka (diharapkan):** `sum(jumlah * harga_satuan)` bertipe `numeric` dengan 2 desimal, jadi tampil sebagai `13650000.00`, bukan `13650000`.

---

## Latihan 1: Total belanja per pelanggan, termasuk yang belum belanja

```sql
SELECT c.id, c.nama,
       COALESCE(sum(i.jumlah * i.harga_satuan), 0) AS total_belanja
FROM pelanggan c
LEFT JOIN pesanan p      ON p.pelanggan_id = c.id
LEFT JOIN item_pesanan i ON i.pesanan_id = p.id
GROUP BY c.id, c.nama
ORDER BY total_belanja DESC, c.id;
```

Karena seed tidak punya pelanggan tanpa belanja, `latihan.sql` menambahkan pelanggan **Eka** sementara (di dalam transaksi yang di-`ROLLBACK`). Hasil (terverifikasi di SQLite):

| nama | total_belanja |
|---|---|
| Andi | 13.650.000 |
| Citra | 4.400.000 |
| Dedi | 450.000 |
| Budi | 150.000 |
| Eka | 0 |

**Penjelasan:**

- Harus **dua** `LEFT JOIN` berantai. Jika `item_pesanan` memakai `INNER JOIN`, baris Eka (yang `i`-nya NULL) tersaring dan Eka hilang.
- Pelanggan tanpa pesanan menghasilkan `sum(NULL) = NULL`. `COALESCE(..., 0)` mengubahnya menjadi 0. **(diharapkan)** Kolom tampil campuran: `13650000.00` untuk yang punya nilai dan `0` untuk Eka.
- Total Dedi (450.000) berasal dari pesanan berstatus `batal`. Query ini tidak memfilter status. Jika "total belanja" harus mengecualikan pesanan batal, tambahkan `AND p.status <> 'batal'` **di `ON`**, bukan di `WHERE`. Menaruhnya di `WHERE` mengubah LEFT JOIN menjadi INNER JOIN dan menghilangkan pelanggan tanpa pesanan.

**Jebakan `count(*)` pada LEFT JOIN** (terverifikasi): untuk Eka, `count(*)` menghasilkan **1** (baris hasil join dengan sisi kanan NULL tetap dihitung), sedangkan `count(p.id)` menghasilkan **0**. Hitung kolom dari sisi kanan, bukan `*`.

---

## Latihan 2: Pelanggan yang belum pernah memesan, tiga cara

Pakai pelanggan Eka sementara. Hasil ketiganya (terverifikasi): **Eka**.

```sql
-- 1. LEFT JOIN ... IS NULL
SELECT c.id, c.nama FROM pelanggan c
LEFT JOIN pesanan p ON p.pelanggan_id = c.id
WHERE p.id IS NULL;

-- 2. NOT EXISTS
SELECT c.id, c.nama FROM pelanggan c
WHERE NOT EXISTS (SELECT 1 FROM pesanan p WHERE p.pelanggan_id = c.id);

-- 3. NOT IN
SELECT c.id, c.nama FROM pelanggan c
WHERE c.id NOT IN (SELECT pelanggan_id FROM pesanan);
```

### Mengapa `NOT IN` berbahaya bila ada `NULL`

`x NOT IN (a, b, NULL)` sama dengan `x <> a AND x <> b AND x <> NULL`. Ekspresi terakhir bernilai **NULL** (tidak diketahui), dan `TRUE AND NULL = NULL`. `WHERE` hanya meloloskan baris `TRUE`, sehingga **seluruh hasil menjadi kosong**, padahal secara logika Eka belum pernah memesan. Ini penerapan logika tiga nilai dari Modul 2.

Peragaan (terverifikasi di SQLite):

| Query | Hasil |
|---|---|
| `NOT IN (SELECT pelanggan_id FROM pesanan)` | Eka |
| `NOT IN (SELECT pelanggan_id FROM pesanan UNION ALL SELECT NULL)` | **Kosong** |
| `NOT EXISTS` dengan subquery yang berisi NULL yang sama | Eka (tidak terpengaruh) |

Pada kasus ini, `NOT IN` pertama masih aman **hanya karena** `pesanan.pelanggan_id` berstatus `NOT NULL`. Jika kolom di subquery boleh NULL, atau skema berubah kelak, query yang sama diam-diam berubah hasilnya tanpa error. Itu yang membuatnya berbahaya.

**Rekomendasi:** pakai `NOT EXISTS` (benar terhadap NULL, dan planner PostgreSQL mengubahnya menjadi anti-join). `LEFT JOIN ... IS NULL` juga aman dan setara.

---

## Latihan 3: `LATERAL`, 2 produk termahal per kategori

Kolom `kategori` sudah ada dari Modul 4, tetapi seluruh produk berisi `'umum'`. Karena itu `latihan.sql` mengisi kategori sementara (di dalam transaksi): komputer (Laptop, Monitor), aksesori (Keyboard, Mouse), audio (Headset).

```sql
SELECT k.kategori, x.nama, x.harga
FROM (SELECT DISTINCT kategori FROM produk) k
CROSS JOIN LATERAL (
    SELECT nama, harga FROM produk p
    WHERE p.kategori = k.kategori
    ORDER BY harga DESC, id
    LIMIT 2
) x
ORDER BY k.kategori, x.harga DESC;
```

Hasil yang dihitung dari data seed (`[PADANAN]`: SQLite tidak punya `LATERAL`, jadi diuji lewat `row_number()` dengan hasil akhir yang sama):

| kategori | nama | harga |
|---|---|---|
| aksesori | Keyboard Mekanik | 850.000 |
| aksesori | Mouse Nirkabel | 165.000 |
| audio | Headset | 450.000 |
| komputer | Laptop 14 inci | 12.500.000 |
| komputer | Monitor 24 inci | 2.200.000 |

**Cara kerja:** subquery `LATERAL` dijalankan **sekali untuk setiap baris `k`** dan boleh merujuk `k.kategori`. `ORDER BY ... LIMIT 2` di dalamnya berlaku per kategori. Itulah yang tidak bisa dilakukan `JOIN` biasa, karena `LIMIT` di subquery biasa berlaku untuk seluruh hasil, bukan per grup. Kategori `audio` hanya punya satu produk sehingga hanya satu baris.

Catatan:

- `id` pada `ORDER BY` berfungsi sebagai pemutus seri agar hasil deterministik bila ada dua harga sama.
- `CROSS JOIN LATERAL` membuang kategori yang subquery-nya kosong. Gunakan `LEFT JOIN LATERAL (...) ON true` bila kategori tanpa produk harus tetap muncul.
- Alternatif tanpa `LATERAL`: window function `row_number() OVER (PARTITION BY kategori ORDER BY harga DESC)` lalu filter `rn <= 2` (Modul 8). Untuk tabel besar dengan index `(kategori, harga DESC)`, `LATERAL` sering lebih efisien karena hanya membaca N baris teratas per grup.

---

## Latihan 4: CTE data-modifying untuk mengarsipkan pesanan batal

Tabel `arsip_pesanan` belum ada, jadi dibuat dulu:

```sql
CREATE TABLE arsip_pesanan (
    LIKE pesanan INCLUDING DEFAULTS,
    diarsipkan_pada timestamptz NOT NULL DEFAULT now()
);

WITH dihapus AS (
    DELETE FROM pesanan WHERE status = 'batal' RETURNING *
)
INSERT INTO arsip_pesanan (id, pelanggan_id, status, dibuat_pada)
SELECT id, pelanggan_id, status, dibuat_pada FROM dihapus;
```

**Mengapa atomik dalam satu pernyataan:** `DELETE ... RETURNING *` menghasilkan baris yang benar-benar terhapus, lalu `INSERT` memakai baris itu. Tidak ada celah di antara "pilih" dan "hapus" tempat pesanan lain bisa berubah menjadi `batal`. Baris yang diarsipkan **persis** baris yang terhapus. Bila salah satu bagian gagal, seluruh pernyataan dibatalkan. Tidak perlu `BEGIN` eksplisit untuk menjaga konsistensi.

Hasil yang diharapkan: `arsip_pesanan` berisi 1 baris (pesanan id 5, `batal`), `pesanan` tinggal 4.

> **Peringatan penting: item pesanan ikut hilang.** `item_pesanan.pesanan_id` memakai `ON DELETE CASCADE`. Saat pesanan 5 dihapus, **item miliknya (Headset) ikut terhapus** dan tidak ikut diarsipkan. `item_pesanan` turun dari 6 menjadi 5 baris dan datanya tidak tersimpan di mana pun. Jika pesanan arsip harus bisa direkonstruksi, item harus diarsipkan juga.

**Versi yang mengarsipkan item (4b di `latihan.sql`)**: salin item **sebelum** pesanan dihapus, dalam satu transaksi:

```sql
BEGIN;
CREATE TABLE arsip_item_pesanan (LIKE item_pesanan INCLUDING DEFAULTS);
INSERT INTO arsip_item_pesanan
SELECT * FROM item_pesanan
WHERE pesanan_id IN (SELECT id FROM pesanan WHERE status = 'batal');

WITH dihapus AS (DELETE FROM pesanan WHERE status = 'batal' RETURNING *)
INSERT INTO arsip_pesanan (id, pelanggan_id, status, dibuat_pada)
SELECT id, pelanggan_id, status, dibuat_pada FROM dihapus;
COMMIT;
```

Hasil yang dihitung: arsip pesanan 1, arsip item 1, pesanan aktif 4, item aktif 5 (terverifikasi lewat padanan). Satu `WITH` yang menghapus `item_pesanan` dan `pesanan` sekaligus mungkin saja bisa dibuat, tetapi urutan eksekusi sub-pernyataan di dalam satu `WITH` tidak dijamin dan saya tidak menguji kombinasinya, jadi saya tidak merekomendasikannya.

Keterbatasan verifikasi: SQLite tidak mendukung `WITH ... DELETE`. Yang terbukti hanyalah **hasil akhir** yang sama lewat `INSERT ... SELECT` lalu `DELETE` dalam satu transaksi (dan `ROLLBACK` mengembalikan seed ke 5 pesanan dan 6 item). Sintaks CTE-nya sendiri baru terbukti di psql.

Di `latihan.sql`, tabel arsip dibuat dalam transaksi yang di-`ROLLBACK`, sehingga hilang lagi. Ganti dengan `COMMIT` bila ingin mengarsipkan sungguhan.

---

## Latihan 5: `UNION` vs `UNION ALL`

| | `UNION` | `UNION ALL` |
|---|---|---|
| Hasil | Gabungan **tanpa duplikat** (juga membuang duplikat di dalam satu sisi) | Gabungan **apa adanya** |
| Peragaan (terverifikasi) | `a,b` ∪ `b,c` → **3** baris | → **4** baris (`b` dua kali) |
| Performa | Harus mengurutkan atau meng-hash seluruh hasil untuk menemukan duplikat, butuh memori dan bisa tumpah ke disk | Hanya menyambung (*append*), bisa mengalir tanpa menahan data |

**(diharapkan)** `EXPLAIN` memperlihatkan perbedaannya: `UNION` menambahkan node penghapus duplikat (`HashAggregate`, atau `Sort` + `Unique`) di atas node `Append`, sedangkan `UNION ALL` hanya `Append`.

**Kasus nyata di mana `UNION ALL` aman:**

- **Menggabungkan tabel yang dipecah per periode** (`log_2026_10` dan `log_2026_11`). Barisnya tidak mungkin sama, jadi tidak ada duplikat untuk dibuang. Memakai `UNION` hanya membuang waktu.
- **Menambahkan kolom penanda sumber**, mis. `SELECT 'pelanggan' AS sumber, nama ... UNION ALL SELECT 'produk', nama ...`. Kolom `sumber` menjamin baris tidak identik.
- **Hasilnya akan diagregasi lagi** (`sum`, `count`), dan duplikat memang harus ikut terhitung (mis. dua transaksi nominal sama pada hari yang sama).

Pakai `UNION` hanya bila duplikat **mungkin** muncul dan memang harus dibuang. Catatan tambahan: `UNION` mensyaratkan tipe kolom yang bisa dibandingkan atau di-hash. Tipe `json` (berbeda dari `jsonb`) tidak punya operator kesamaan sehingga tidak bisa di-`UNION`.

---

## Latihan 6: `GROUP BY` dan kolom bukan agregat

```sql
SELECT c.id, c.nama, p.status, count(*)
FROM pelanggan c JOIN pesanan p ON p.pelanggan_id = c.id
GROUP BY c.id;
```

**(diharapkan)** `ERROR: column "p.status" must appear in the GROUP BY clause or be used in an aggregate function`.

**Mengapa PostgreSQL menolak:** setelah pengelompokan, setiap grup menjadi **satu baris hasil**. Andi punya dua pesanan dengan status berbeda (`selesai` dan `dibayar`). Tidak ada satu nilai `status` yang benar untuk baris "Andi". Database tidak boleh memilih sembarang, sehingga query diminta dibuat tidak ambigu: masukkan kolom itu ke `GROUP BY` (menghasilkan satu baris per kombinasi) atau agregasikan (`max(p.status)`, `string_agg(p.status, ', ')`).

Catatan perbandingan: **SQLite menerima query ini** (terbukti: query menghasilkan 4 baris dengan `status` yang dipilih sembarang per grup). MySQL tanpa mode `ONLY_FULL_GROUP_BY` juga demikian. Karena itu penolakan ini tidak bisa diverifikasi di SQLite. Perilaku yang aman dan portabel adalah perilaku PostgreSQL.

**Pengecualian: ketergantungan fungsional pada primary key.**

```sql
SELECT c.id, c.nama, count(p.id) AS jumlah_pesanan
FROM pelanggan c LEFT JOIN pesanan p ON p.pelanggan_id = c.id
GROUP BY c.id;                -- c.nama TIDAK perlu ada di GROUP BY
```

**(diharapkan)** Query ini **berhasil**. `c.id` adalah primary key `pelanggan`, jadi untuk setiap `c.id` hanya ada tepat satu `c.nama`. Nilainya tidak mungkin ambigu, sehingga PostgreSQL mengizinkannya. (Versi `GROUP BY c.id, c.nama` yang dipakai di Praktik juga benar dan valid di semua DBMS, terverifikasi: Andi 2, Budi 1, Citra 1, Dedi 1.)

Batas pengecualian ini:

| Hal | Penjelasan |
|---|---|
| Hanya untuk **primary key** (atau subset kolom yang merupakan PK tabel tersebut) | Kolom `UNIQUE` biasa tidak dikenali oleh aturan ini |
| Hanya untuk kolom **dari tabel yang sama** dengan PK itu | `GROUP BY p.id` tidak membuat `c.nama` (tabel lain) legal. `latihan.sql` mengujinya dan **(diharapkan)** gagal dengan pesan `column "c.nama" must appear in the GROUP BY clause ...` |
| Tidak berlaku untuk hasil subquery atau view | PostgreSQL tidak bisa menelusuri PK di sana |

---

## Lembar hasil Anda

| Langkah | Hasil Anda | Sesuai harapan? |
|---|---|---|
| Praktik: JOIN 4 tabel menghasilkan 6 baris | | |
| `ROLLUP` menghasilkan 10 baris, dengan satu `NULL, NULL, 5` | | |
| Praktik: dua query anti-join kosong | | |
| LATERAL pesanan terbaru: Andi berganti antar eksekusi? (jika tidak ada pemutus seri) | | |
| Latihan 1: Eka = 0, pelanggan lain sesuai tabel | | |
| Latihan 2: tiga cara menghasilkan Eka; `NOT IN` dengan NULL kosong | | |
| Latihan 3: 5 baris, kategori audio hanya 1 | | |
| Latihan 4a: arsip 1 baris; `item_pesanan` turun 6 → 5 | | |
| Latihan 4b: arsip item 1 baris | | |
| Latihan 5: `UNION` 3 baris, `UNION ALL` 4 baris; node `EXPLAIN` | | |
| Latihan 6: dua error disengaja, satu query berhasil | | |

## Sebelum lanjut ke Modul 7

Modul 7 membahas transaksi, dan data seed Modul 5 masih utuh karena semua eksperimen modul ini dilakukan dalam `ROLLBACK`. Satu-satunya efek samping adalah lubang di nomor identity `pelanggan` (dari Eka, yang ditambahkan di Latihan 1 dan 2). Itu tidak berpengaruh pada query.
