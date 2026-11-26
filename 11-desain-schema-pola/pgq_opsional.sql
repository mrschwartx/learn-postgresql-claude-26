-- pgq_opsional.sql : Praktik PgQ (opsional). Butuh ekstensi pgq yang TIDAK ada di image postgres resmi:
--   docker exec -u root pg-latihan bash -c 'apt-get update -qq && apt-get install -y -qq postgresql-18-pgq3'
--   docker exec pg-latihan psql -U postgres -d toko -c "CREATE EXTENSION pgq;"
-- (nama paket bisa berbeda; cek dengan apt-cache search pgq.) Belum diuji di lingkungan saya.
-- Ganti angka 1 pada get_batch_events/finish_batch dengan batch_id dari next_batch.
SELECT pgq.create_queue('pesanan_baru');
SELECT pgq.register_consumer('pesanan_baru', 'worker_email');

-- Producer
SELECT pgq.insert_event('pesanan_baru', 'dibuat', '{"pesanan_id": 1}');
SELECT pgq.insert_event('pesanan_baru', 'dibuat', '{"pesanan_id": 2}');

-- Ticker: pada sistem nyata dikerjakan daemon pgqd; di latihan kita picu manual
SELECT pgq.ticker();

-- Consumer
SELECT pgq.next_batch('pesanan_baru', 'worker_email');       -- mengembalikan batch_id, misalnya 1
SELECT ev_id, ev_type, ev_data FROM pgq.get_batch_events(1); -- ganti 1 dengan batch_id Anda
SELECT pgq.finish_batch(1);

-- Status consumer
SELECT * FROM pgq.get_consumer_info();
