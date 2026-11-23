-- rancangan_toko.sql
CREATE TABLE pelanggan (
    id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nama       text        NOT NULL,
    email      text        NOT NULL UNIQUE,
    dibuat_pada timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE produk (
    id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nama   text           NOT NULL,
    harga  numeric(12,2)  NOT NULL CHECK (harga >= 0),
    stok   integer        NOT NULL DEFAULT 0 CHECK (stok >= 0)
);

CREATE TABLE pesanan (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    pelanggan_id bigint NOT NULL REFERENCES pelanggan(id),
    tanggal      date   NOT NULL DEFAULT current_date,
    status       text   NOT NULL DEFAULT 'baru'
);

CREATE TABLE item_pesanan (
    pesanan_id bigint  NOT NULL REFERENCES pesanan(id) ON DELETE CASCADE,
    produk_id  bigint  NOT NULL REFERENCES produk(id),
    jumlah     integer NOT NULL CHECK (jumlah > 0),
    PRIMARY KEY (pesanan_id, produk_id)
);
