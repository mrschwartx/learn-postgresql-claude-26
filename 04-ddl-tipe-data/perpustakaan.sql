-- perpustakaan.sql : Jawaban Latihan 1 Modul 4.
-- Skema perpustakaan dari Latihan 4 Modul 2 (isi DDL identik; lihat verifikasi di jawaban),
-- ditempatkan di schema `perpustakaan`. Lebih lengkap dari permintaan (buku, anggota,
-- peminjaman): ditambah penulis, buku_penulis, eksemplar.
-- Jalankan: docker exec -i pg-latihan psql -U postgres -d toko -f - < perpustakaan.sql
-- Baris berlabel "-- DISENGAJA ERROR" memang diharapkan gagal.

CREATE SCHEMA IF NOT EXISTS perpustakaan;
SET search_path TO perpustakaan, public;

-- rancangan_perpustakaan.sql  (Jawaban Latihan 4, dialek PostgreSQL)
--
-- Relasi:
--   penulis  M --- N buku      (tabel penghubung: buku_penulis)
--   buku     1 --- N eksemplar (satu judul punya banyak salinan fisik)
--   anggota  1 --- N peminjaman
--   eksemplar 1 --- N peminjaman (riwayat; hanya SATU yang aktif sekaligus)

CREATE TABLE penulis (
    id    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nama  text NOT NULL CHECK (length(trim(nama)) > 0),
    negara text
);

CREATE TABLE buku (
    id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    isbn          text    NOT NULL UNIQUE CHECK (length(isbn) = 13),
    judul         text    NOT NULL,
    tahun_terbit  integer NOT NULL CHECK (tahun_terbit BETWEEN 1450 AND 2100)
);

-- Many-to-many buku <-> penulis, PK komposit mencegah pasangan ganda
CREATE TABLE buku_penulis (
    buku_id    bigint  NOT NULL REFERENCES buku(id)    ON DELETE CASCADE,
    penulis_id bigint  NOT NULL REFERENCES penulis(id) ON DELETE RESTRICT,
    urutan     integer NOT NULL DEFAULT 1 CHECK (urutan >= 1),
    PRIMARY KEY (buku_id, penulis_id),
    UNIQUE (buku_id, urutan)            -- tidak ada dua "penulis pertama"
);

CREATE TABLE eksemplar (
    id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    buku_id bigint NOT NULL REFERENCES buku(id) ON DELETE RESTRICT,
    barcode text   NOT NULL UNIQUE,
    kondisi text   NOT NULL DEFAULT 'baik'
            CHECK (kondisi IN ('baik', 'rusak', 'hilang'))
);

CREATE TABLE anggota (
    id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nomor_anggota  text NOT NULL UNIQUE,
    nama           text NOT NULL,
    email          text NOT NULL UNIQUE,
    status         text NOT NULL DEFAULT 'aktif'
                   CHECK (status IN ('aktif', 'ditangguhkan', 'nonaktif')),
    bergabung_pada date NOT NULL DEFAULT current_date
);

CREATE TABLE peminjaman (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    anggota_id      bigint NOT NULL REFERENCES anggota(id)   ON DELETE RESTRICT,
    eksemplar_id    bigint NOT NULL REFERENCES eksemplar(id) ON DELETE RESTRICT,
    tanggal_pinjam  date   NOT NULL DEFAULT current_date,
    jatuh_tempo     date   NOT NULL,
    tanggal_kembali date,                          -- NULL = belum dikembalikan
    denda           numeric(10,2) NOT NULL DEFAULT 0 CHECK (denda >= 0),
    CHECK (jatuh_tempo >= tanggal_pinjam),
    CHECK (tanggal_kembali IS NULL OR tanggal_kembali >= tanggal_pinjam)
);

-- Satu eksemplar hanya boleh sedang dipinjam oleh satu orang pada satu waktu.
CREATE UNIQUE INDEX uq_peminjaman_aktif
    ON peminjaman (eksemplar_id)
    WHERE tanggal_kembali IS NULL;


-- ---------------------------------------------------------------- Data valid
INSERT INTO penulis (nama, negara) VALUES ('Pramoedya Ananta Toer','Indonesia'), ('Penulis Kedua','Indonesia');
INSERT INTO buku (isbn, judul, tahun_terbit) VALUES ('9789799731234','Bumi Manusia',1980);
INSERT INTO buku_penulis VALUES (1, 1, 1), (1, 2, 2);
INSERT INTO eksemplar (buku_id, barcode) VALUES (1,'BC-001'), (1,'BC-002');
INSERT INTO anggota (nomor_anggota, nama, email) VALUES ('A-0001','Sari','sari@contoh.com'), ('A-0002','Dewi','dewi@contoh.com');
INSERT INTO peminjaman (anggota_id, eksemplar_id, tanggal_pinjam, jatuh_tempo) VALUES (1, 1, '2026-11-01', '2026-11-15');

\echo '--- DISENGAJA ERROR: ISBN bukan 13 karakter'
INSERT INTO buku (isbn, judul, tahun_terbit) VALUES ('123','X',2000);
\echo '--- DISENGAJA ERROR: tahun terbit 1200'
INSERT INTO buku (isbn, judul, tahun_terbit) VALUES ('9789799731999','Z',1200);
\echo '--- DISENGAJA ERROR: jatuh tempo sebelum tanggal pinjam'
INSERT INTO peminjaman (anggota_id, eksemplar_id, tanggal_pinjam, jatuh_tempo) VALUES (2,2,'2026-11-10','2026-11-01');
\echo '--- DISENGAJA ERROR: eksemplar 1 dipinjam lagi padahal belum kembali (partial unique index)'
INSERT INTO peminjaman (anggota_id, eksemplar_id, tanggal_pinjam, jatuh_tempo) VALUES (2,1,'2026-11-05','2026-11-19');
\echo '--- Setelah dikembalikan, eksemplar 1 boleh dipinjam lagi (harus BERHASIL)'
UPDATE peminjaman SET tanggal_kembali = '2026-11-12' WHERE id = 1;
INSERT INTO peminjaman (anggota_id, eksemplar_id, tanggal_pinjam, jatuh_tempo) VALUES (2,1,'2026-11-13','2026-11-27');
\echo '--- DISENGAJA ERROR: hapus anggota yang punya riwayat pinjam (RESTRICT)'
DELETE FROM anggota WHERE id = 2;

\dt perpustakaan.*
\d perpustakaan.peminjaman
