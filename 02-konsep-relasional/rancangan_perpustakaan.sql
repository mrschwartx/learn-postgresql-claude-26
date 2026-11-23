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
