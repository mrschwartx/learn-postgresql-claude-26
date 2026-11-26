-- latihan.sql : Latihan 1-4 dan perbaikan demo pagination Modul 11.
-- (Latihan 5 = bulk_ukur.sh, Latihan 7 = flyway/, Latihan 6, 8, 9 = diskusi di jawaban.)
-- Semua objek ada di schema latihan11. Hapus: ./jalankan.sh bersih
-- Jalankan: docker exec -i pg-latihan psql -U postgres -d toko -f - < latihan.sql
-- Baris berlabel "DISENGAJA ERROR" memang diharapkan gagal.

DROP SCHEMA IF EXISTS latihan11 CASCADE;
CREATE SCHEMA latihan11;
SET search_path TO latihan11, public;

-- =====================================================================
\echo '=== PERBAIKAN PRAKTIK PAGINATION: salinan transaksi dengan dan tanpa index B-Tree pada id ==='
-- transaksi (Modul 9) tidak punya PK maupun index B-Tree pada id (hanya BRIN), sehingga keyset
-- pada tabel asli tidak bisa memanfaatkan index. Salinan ini memperlihatkan perbedaannya.
CREATE TABLE trx_page AS SELECT id FROM app.transaksi WHERE id <= 1000000;
ANALYZE trx_page;
\echo '--- TANPA index: kedua bentuk harus memindai dan mengurutkan (bandingkan Execution Time)'
EXPLAIN (ANALYZE, COSTS OFF) SELECT id FROM trx_page ORDER BY id LIMIT 20 OFFSET 900000;
EXPLAIN (ANALYZE, COSTS OFF) SELECT id FROM trx_page WHERE id > 900000 ORDER BY id LIMIT 20;
CREATE INDEX idx_page_id ON trx_page (id);
ANALYZE trx_page;
\echo '--- DENGAN index: OFFSET tetap melewati 900.000 entri, keyset langsung melompat ke id > 900000'
EXPLAIN (ANALYZE, COSTS OFF) SELECT id FROM trx_page ORDER BY id LIMIT 20 OFFSET 900000;
EXPLAIN (ANALYZE, COSTS OFF) SELECT id FROM trx_page WHERE id > 900000 ORDER BY id LIMIT 20;

-- =====================================================================
\echo '=== LATIHAN 1: normalisasi pesanan_lama sampai 3NF ==='
CREATE TABLE pesanan_lama (
    id int PRIMARY KEY, pelanggan_nama text, pelanggan_alamat text,
    produk_nama text, produk_harga numeric(12,2), jumlah int);
INSERT INTO pesanan_lama VALUES
 (1, 'Andi',  'Jl. Mawar 1',   'Keyboard', 850000,  1),
 (2, 'Andi',  'Jl. Mawar 1',   'Mouse',    165000,  2),
 (3, 'Budi',  'Jl. Melati 2',  'Mouse',    165000,  1),
 (4, 'Citra', 'Jl. Kenanga 3', 'Monitor',  2200000, 2),
 (5, 'Budi',  'Jl. Melati 2',  'Keyboard', 850000,  1),
 (6, 'Andi',  'Jl. Mawar 1',   'Monitor',  2200000, 1);

-- Asumsi dependensi fungsional (HARUS dinyatakan eksplisit):
--   pelanggan_nama -> pelanggan_alamat         (nama menentukan alamat; di dunia nyata pakai id pelanggan)
--   produk_nama    -> harga produk SAAT INI    (tetapi harga yang tersimpan di item = harga SAAT TRANSAKSI)
CREATE TABLE pelanggan (
    id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nama   text NOT NULL UNIQUE,
    alamat text NOT NULL);
CREATE TABLE produk (
    id    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nama  text NOT NULL UNIQUE,
    harga numeric(12,2) NOT NULL CHECK (harga >= 0));
CREATE TABLE pesanan (
    id           int PRIMARY KEY,
    pelanggan_id bigint NOT NULL REFERENCES pelanggan(id));
CREATE TABLE item_pesanan (
    pesanan_id   int    NOT NULL REFERENCES pesanan(id) ON DELETE CASCADE,
    produk_id    bigint NOT NULL REFERENCES produk(id),
    jumlah       int    NOT NULL CHECK (jumlah > 0),
    harga_satuan numeric(12,2) NOT NULL CHECK (harga_satuan >= 0),   -- harga saat transaksi (snapshot)
    PRIMARY KEY (pesanan_id, produk_id));
CREATE INDEX idx_pesanan_pelanggan ON pesanan (pelanggan_id);       -- PostgreSQL tidak membuat index FK otomatis
CREATE INDEX idx_item_produk ON item_pesanan (produk_id);

INSERT INTO pelanggan (nama, alamat) SELECT DISTINCT pelanggan_nama, pelanggan_alamat FROM pesanan_lama;
INSERT INTO produk (nama, harga)     SELECT DISTINCT produk_nama, produk_harga FROM pesanan_lama;
INSERT INTO pesanan (id, pelanggan_id)
SELECT l.id, c.id FROM pesanan_lama l JOIN pelanggan c ON c.nama = l.pelanggan_nama;
INSERT INTO item_pesanan (pesanan_id, produk_id, jumlah, harga_satuan)
SELECT l.id, p.id, l.jumlah, l.produk_harga FROM pesanan_lama l JOIN produk p ON p.nama = l.produk_nama;

\echo '--- tanpa kehilangan data: rekonstruksi dari 4 tabel harus identik dengan tabel lama (hasil KOSONG)'
CREATE VIEW pesanan_rekonstruksi AS
SELECT ps.id, c.nama AS pelanggan_nama, c.alamat AS pelanggan_alamat, pr.nama AS produk_nama,
       i.harga_satuan AS produk_harga, i.jumlah
FROM pesanan ps JOIN pelanggan c ON c.id = ps.pelanggan_id
JOIN item_pesanan i ON i.pesanan_id = ps.id JOIN produk pr ON pr.id = i.produk_id;
(SELECT * FROM pesanan_lama EXCEPT SELECT * FROM pesanan_rekonstruksi)
UNION ALL
(SELECT * FROM pesanan_rekonstruksi EXCEPT SELECT * FROM pesanan_lama);

\echo '--- anomali update: ubah harga Mouse. Tabel lama menyentuh banyak baris, tabel normal hanya satu'
BEGIN;
UPDATE pesanan_lama SET produk_harga = 170000 WHERE produk_nama = 'Mouse';
UPDATE produk SET harga = 170000 WHERE nama = 'Mouse';
ROLLBACK;

-- =====================================================================
\echo '=== LATIHAN 2: tiket_dukungan, JSONB hibrida vs EAV ==='
CREATE TABLE tiket (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    jenis       text NOT NULL CHECK (jenis IN ('bug', 'tagihan', 'permintaan_fitur')),
    judul       text NOT NULL,
    status      text NOT NULL DEFAULT 'baru' CHECK (status IN ('baru', 'diproses', 'selesai')),
    dibuat_pada timestamptz NOT NULL DEFAULT now(),
    atribut     jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT atribut_objek   CHECK (jsonb_typeof(atribut) = 'object'),
    CONSTRAINT atribut_bug     CHECK (jenis <> 'bug' OR (atribut ? 'versi' AND atribut ? 'tingkat')),
    CONSTRAINT atribut_tagihan CHECK (jenis <> 'tagihan' OR jsonb_typeof(atribut -> 'jumlah') = 'number')
);
CREATE INDEX idx_tiket_atribut ON tiket USING gin (atribut jsonb_path_ops);

INSERT INTO tiket (jenis, judul, atribut) VALUES
 ('bug',     'Login gagal',      '{"versi": "2.3", "tingkat": "tinggi"}'),
 ('bug',     'Teks terpotong',   '{"versi": "2.4", "tingkat": "rendah"}'),
 ('bug',     'Laporan lambat',   '{"versi": "2.3", "tingkat": "rendah"}'),
 ('tagihan', 'Tagihan ganda',    '{"jumlah": 150000, "metode": "transfer"}'),
 ('tagihan', 'Refund',           '{"jumlah": 50000,  "metode": "kartu"}'),
 ('permintaan_fitur', 'Ekspor PDF', '{"modul": "laporan"}');

\echo '--- DISENGAJA ERROR: bug tanpa atribut wajib'
INSERT INTO tiket (jenis, judul, atribut) VALUES ('bug', 'Tanpa versi', '{"tingkat": "tinggi"}');
\echo '--- DISENGAJA ERROR: jumlah tagihan bukan angka'
INSERT INTO tiket (jenis, judul, atribut) VALUES ('tagihan', 'Salah tipe', '{"jumlah": "abc"}');

\echo '--- versi JSONB: bug versi 2.3 dengan tingkat tinggi'
SELECT id, judul FROM tiket WHERE jenis = 'bug' AND atribut @> '{"versi": "2.3", "tingkat": "tinggi"}';
\echo '--- versi JSONB: tagihan di atas 100000 (angka asli, tanpa cast)'
SELECT id, judul FROM tiket WHERE jenis = 'tagihan' AND (atribut ->> 'jumlah')::numeric > 100000;

-- Pembanding EAV --------------------------------------------------------
CREATE TABLE tiket_eav (
    tiket_id bigint NOT NULL REFERENCES tiket(id) ON DELETE CASCADE,
    nama     text   NOT NULL,
    nilai    text,                       -- SEMUA nilai menjadi teks: tipe hilang
    PRIMARY KEY (tiket_id, nama));
INSERT INTO tiket_eav SELECT t.id, e.key, e.value FROM tiket t, jsonb_each_text(t.atribut) AS e;

\echo '--- EAV: pertanyaan yang sama butuh satu self-join PER atribut'
SELECT t.id, t.judul
FROM tiket t
JOIN tiket_eav a1 ON a1.tiket_id = t.id AND a1.nama = 'versi'   AND a1.nilai = '2.3'
JOIN tiket_eav a2 ON a2.tiket_id = t.id AND a2.nama = 'tingkat' AND a2.nilai = 'tinggi'
WHERE t.jenis = 'bug';

\echo '--- EAV tidak menolak nilai yang salah tipe:'
INSERT INTO tiket_eav SELECT id, 'jumlah', 'abc' FROM tiket WHERE judul = 'Laporan lambat';
\echo '--- DISENGAJA ERROR: cast numerik gagal untuk SELURUH query karena satu nilai buruk'
SELECT tiket_id FROM tiket_eav WHERE nama = 'jumlah' AND nilai::numeric > 100000;

-- =====================================================================
\echo '=== LATIHAN 3: sensor_data dipartisi per hari ==='
CREATE TABLE sensor_data (
    id        bigint GENERATED ALWAYS AS IDENTITY,
    waktu     timestamptz NOT NULL,
    sensor_id int NOT NULL,
    nilai     double precision,
    PRIMARY KEY (id, waktu)                 -- PK harus memuat kunci partisi
) PARTITION BY RANGE (waktu);
CREATE TABLE sensor_20261201 PARTITION OF sensor_data FOR VALUES FROM ('2026-12-01') TO ('2026-12-02');
CREATE TABLE sensor_20261202 PARTITION OF sensor_data FOR VALUES FROM ('2026-12-02') TO ('2026-12-03');
CREATE TABLE sensor_20261203 PARTITION OF sensor_data FOR VALUES FROM ('2026-12-03') TO ('2026-12-04');

-- 100.000 baris tersebar merata selama tepat 3 hari (selang 2,592 detik): 33.334 / 33.333 / 33.333
INSERT INTO sensor_data (waktu, sensor_id, nilai)
SELECT '2026-12-01'::timestamptz + interval '1 second' * ((g - 1) * 2.592), (g % 50) + 1, random() * 100
FROM generate_series(1, 100000) g;
ANALYZE sensor_data;

SELECT tableoid::regclass AS partisi, count(*) FROM sensor_data GROUP BY 1 ORDER BY 1;

\echo '--- BUKTI pruning: filter pada kunci partisi, hanya satu partisi muncul di rencana'
EXPLAIN SELECT * FROM sensor_data WHERE waktu >= '2026-12-02' AND waktu < '2026-12-03';
\echo '--- tanpa filter kunci partisi: SEMUA partisi dipindai'
EXPLAIN SELECT * FROM sensor_data WHERE sensor_id = 7;
\echo '--- kunci partisi dibungkus cast: pruning kemungkinan GAGAL (bandingkan dengan yang pertama)'
EXPLAIN SELECT * FROM sensor_data WHERE waktu::date = '2026-12-02';

-- Otomatisasi: fungsi idempoten pembuat partisi untuk satu hari
CREATE OR REPLACE FUNCTION buat_partisi_sensor(p_hari date) RETURNS text
LANGUAGE plpgsql AS $$
DECLARE
    v_nama text := format('sensor_%s', to_char(p_hari, 'YYYYMMDD'));
BEGIN
    EXECUTE format(
        'CREATE TABLE IF NOT EXISTS latihan11.%I PARTITION OF latihan11.sensor_data FOR VALUES FROM (%L) TO (%L)',
        v_nama, p_hari, p_hari + 1);
    RETURN v_nama;
END $$;

SELECT buat_partisi_sensor(date '2026-12-04');
SELECT buat_partisi_sensor(date '2026-12-04') AS idempoten_aman_dipanggil_ulang;
\echo '--- siapkan 6 hari ke depan sekaligus (penyangga bila penjadwal gagal satu hari)'
SELECT buat_partisi_sensor(d::date) FROM generate_series(date '2026-12-05', date '2026-12-10', interval '1 day') AS d;
SELECT inhrelid::regclass AS partisi FROM pg_inherits WHERE inhparent = 'latihan11.sensor_data'::regclass ORDER BY 1;

-- =====================================================================
\echo '=== LATIHAN 4: job queue SKIP LOCKED dengan percobaan dan retry maksimum 3 kali ==='
CREATE TABLE antrean2 (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    payload         text NOT NULL,
    status          text NOT NULL DEFAULT 'menunggu' CHECK (status IN ('menunggu', 'diproses', 'selesai', 'gagal')),
    percobaan       int  NOT NULL DEFAULT 0,
    maks_percobaan  int  NOT NULL DEFAULT 3,
    mulai           timestamptz,
    selesai_pada    timestamptz,
    jalankan_setelah timestamptz NOT NULL DEFAULT now(),
    pesan_error     text);
CREATE INDEX idx_antrean2_menunggu ON antrean2 (jalankan_setelah, id) WHERE status = 'menunggu';

CREATE FUNCTION ambil_tugas() RETURNS SETOF antrean2 LANGUAGE sql AS $$
    WITH tugas AS (
        SELECT id FROM antrean2
        WHERE status = 'menunggu' AND jalankan_setelah <= now()
        ORDER BY jalankan_setelah, id
        FOR UPDATE SKIP LOCKED LIMIT 1)
    UPDATE antrean2 a
       SET status = 'diproses', mulai = now(), percobaan = a.percobaan + 1
      FROM tugas WHERE a.id = tugas.id
    RETURNING a.*;
$$;

CREATE FUNCTION tugas_selesai(p_id bigint) RETURNS void LANGUAGE sql AS $$
    UPDATE antrean2 SET status = 'selesai', selesai_pada = now(), pesan_error = NULL
    WHERE id = p_id AND status = 'diproses';
$$;

-- Gagal: kembali ke antrean (menunggu) selama percobaan < maksimum, selain itu status akhir 'gagal'.
CREATE FUNCTION tugas_gagal(p_id bigint, p_pesan text, p_tunda interval DEFAULT interval '0') RETURNS text
LANGUAGE sql AS $$
    UPDATE antrean2
       SET status = CASE WHEN percobaan >= maks_percobaan THEN 'gagal' ELSE 'menunggu' END,
           pesan_error = p_pesan,
           jalankan_setelah = now() + p_tunda * percobaan          -- backoff linear: tunda x nomor percobaan
     WHERE id = p_id AND status = 'diproses'
    RETURNING status;
$$;

-- Visibility timeout: tugas 'diproses' terlalu lama (worker mati) dikembalikan ke antrean atau digagalkan
CREATE FUNCTION pulihkan_macet(p_batas interval) RETURNS int LANGUAGE sql AS $$
    WITH u AS (
        UPDATE antrean2
           SET status = CASE WHEN percobaan >= maks_percobaan THEN 'gagal' ELSE 'menunggu' END,
               pesan_error = 'melebihi batas waktu', jalankan_setelah = now()
         WHERE status = 'diproses' AND mulai < now() - p_batas
        RETURNING 1)
    SELECT count(*)::int FROM u;
$$;

INSERT INTO antrean2 (payload) VALUES ('sukses'), ('gagal-sekali'), ('selalu-gagal');

-- Worker simulasi dalam SATU transaksi (hanya untuk demo; worker nyata commit setelah klaim)
DO $$
DECLARE t antrean2;
BEGIN
    LOOP
        SELECT * INTO t FROM ambil_tugas();
        EXIT WHEN t.id IS NULL;
        IF t.payload = 'selalu-gagal' OR (t.payload = 'gagal-sekali' AND t.percobaan = 1) THEN
            PERFORM tugas_gagal(t.id, 'error simulasi');
        ELSE
            PERFORM tugas_selesai(t.id);
        END IF;
    END LOOP;
END $$;
SELECT payload, status, percobaan, pesan_error FROM antrean2 ORDER BY id;

\echo '--- visibility timeout: tugas macet 10 menit dengan batas 5 menit'
INSERT INTO antrean2 (payload) VALUES ('macet');
UPDATE antrean2 SET status = 'diproses', mulai = now() - interval '10 minutes', percobaan = 1 WHERE payload = 'macet';
SELECT pulihkan_macet(interval '5 minutes') AS dipulihkan;
SELECT payload, status, percobaan, pesan_error FROM antrean2 WHERE payload = 'macet';
