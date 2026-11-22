# Modul 13: Security

[← Modul 12: Arsitektur Internal & Konfigurasi](12-internal-konfigurasi.md) · [Daftar Isi](README.md#daftar-isi) · [Modul 14: Backup, Recovery & Upgrade →](14-backup-recovery-upgrade.md)

**Isi modul ini**

- [Teori](#teori)
  - [13.1 Lapisan Keamanan PostgreSQL](#131-lapisan-keamanan-postgresql)
  - [13.2 Role — Pengguna dan Grup](#132-role--pengguna-dan-grup)
  - [13.3 Hak Akses Objek — GRANT / REVOKE](#133-hak-akses-objek--grant--revoke)
  - [13.4 Default Privileges](#134-default-privileges)
  - [13.5 Row-Level Security (RLS)](#135-row-level-security-rls)
  - [13.6 Autentikasi dan `pg_hba.conf`](#136-autentikasi-dan-pg_hbaconf)
  - [13.7 SSL/TLS](#137-ssltls)
  - [13.8 SELinux dan Hardening Sistem](#138-selinux-dan-hardening-sistem)
- [Praktik](#praktik)
  - [Role dan Hak Akses](#role-dan-hak-akses)
  - [Menguji sebagai Pengguna Lain](#menguji-sebagai-pengguna-lain)
  - [Default Privileges dan Hak per Kolom](#default-privileges-dan-hak-per-kolom)
  - [Row-Level Security (Multi-Tenant)](#row-level-security-multi-tenant)
  - [Autentikasi](#autentikasi)
- [Latihan](#latihan)

---


## Teori

### 13.1 Lapisan Keamanan PostgreSQL

Keamanan PostgreSQL berlapis — jangan bergantung pada satu lapisan saja:

```
 Jaringan        firewall, security group, listen_addresses
    ▼
 Koneksi         SSL/TLS (enkripsi saat transit)
    ▼
 Autentikasi     pg_hba.conf + metode (scram-sha-256, cert, LDAP, ...)
    ▼
 Otorisasi       role, GRANT/REVOKE, default privileges
    ▼
 Data            Row-Level Security, enkripsi kolom (pgcrypto), masking
    ▼
 Audit           logging, pgaudit
```

### 13.2 Role — Pengguna dan Grup

Di PostgreSQL, **user dan group adalah satu konsep: ROLE**. Role dengan atribut `LOGIN` bisa dipakai untuk masuk; tanpa `LOGIN` berfungsi sebagai grup.

| Atribut | Fungsi |
|---|---|
| `LOGIN` | Boleh login |
| `SUPERUSER` | Melewati **semua** pemeriksaan hak — batasi seketat mungkin |
| `CREATEDB`, `CREATEROLE` | Boleh membuat database / role |
| `REPLICATION` | Boleh melakukan replikasi |
| `PASSWORD '...'` | Password (disimpan sebagai hash SCRAM) |
| `CONNECTION LIMIT n` | Batas koneksi |

```sql
CREATE ROLE app_baca NOLOGIN;                       -- "grup" hak baca
CREATE ROLE app_tulis NOLOGIN;
CREATE ROLE budi LOGIN PASSWORD 'rahasia-kuat' IN ROLE app_baca;
GRANT app_tulis TO budi;                            -- keanggotaan role
```

Role bawaan berguna (*predefined roles*): `pg_read_all_data`, `pg_write_all_data`, `pg_monitor`, `pg_read_server_files`, `pg_signal_backend`, dan lainnya — memberi hak spesifik tanpa menjadikan seseorang superuser.

### 13.3 Hak Akses Objek — GRANT / REVOKE

| Objek | Hak yang tersedia |
|---|---|
| Database | `CONNECT`, `CREATE`, `TEMPORARY` |
| Schema | `USAGE` (melihat isi), `CREATE` |
| Tabel | `SELECT`, `INSERT`, `UPDATE`, `DELETE`, `TRUNCATE`, `REFERENCES`, `TRIGGER` |
| Kolom | `SELECT(kolom)`, `UPDATE(kolom)`, dst. |
| Sequence | `USAGE`, `SELECT`, `UPDATE` |
| Fungsi | `EXECUTE` |

```sql
REVOKE ALL ON DATABASE toko FROM PUBLIC;
GRANT CONNECT ON DATABASE toko TO app_baca, app_tulis;
GRANT USAGE ON SCHEMA app TO app_baca, app_tulis;

GRANT SELECT ON ALL TABLES IN SCHEMA app TO app_baca;
GRANT INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app TO app_tulis;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA app TO app_tulis;

GRANT SELECT (id, nama) ON app.pelanggan TO analis;      -- hak per kolom (email disembunyikan)
```

**Prinsip hak minimum (*least privilege*)**: aplikasi memakai role khusus dengan hak seperlunya — **bukan** `postgres`. Pemisahan umum: role *owner* (pemilik schema/migrasi), role *aplikasi* (DML), role *read-only* (laporan).

`PUBLIC` adalah pseudo-role yang mewakili semua role. Secara default `PUBLIC` mendapat `CONNECT` dan `TEMPORARY` pada database, serta `EXECUTE` pada fungsi baru — cabut jika tidak diinginkan. Sejak PostgreSQL 15, `PUBLIC` **tidak lagi** punya `CREATE` pada schema `public`.

### 13.4 Default Privileges

`GRANT ... ON ALL TABLES` hanya berlaku untuk tabel yang **sudah ada**. Agar tabel **baru** otomatis mendapat hak yang sama:

```sql
ALTER DEFAULT PRIVILEGES FOR ROLE migrator IN SCHEMA app
    GRANT SELECT ON TABLES TO app_baca;
ALTER DEFAULT PRIVILEGES FOR ROLE migrator IN SCHEMA app
    GRANT INSERT, UPDATE, DELETE ON TABLES TO app_tulis;
```

`FOR ROLE` menentukan siapa **pembuat** objek yang dipengaruhi. Lihat hasilnya dengan `\ddp` di psql.

### 13.5 Row-Level Security (RLS)

**RLS** membatasi **baris** yang boleh dilihat/diubah per pengguna lewat *policy* — ideal untuk aplikasi multi-tenant.

```sql
ALTER TABLE pesanan ENABLE ROW LEVEL SECURITY;
ALTER TABLE pesanan FORCE ROW LEVEL SECURITY;       -- berlaku juga untuk pemilik tabel

CREATE POLICY tenant_isolasi ON pesanan
    USING (tenant_id = current_setting('app.tenant_id')::int)       -- baris yang terlihat
    WITH CHECK (tenant_id = current_setting('app.tenant_id')::int); -- baris yang boleh ditulis
```

Aplikasi menetapkan `SET app.tenant_id = '7'` per sesi/transaksi (`SET LOCAL` bila memakai pooler mode transaksi). **Superuser** dan role dengan `BYPASSRLS` melewati RLS — jangan pakai untuk aplikasi.

### 13.6 Autentikasi dan `pg_hba.conf`

**`pg_hba.conf`** (*host-based authentication*) menentukan **siapa boleh terhubung dari mana dengan metode apa**. Aturan dibaca dari atas ke bawah; **yang pertama cocok dipakai**.

```
# TYPE   DATABASE   USER        ADDRESS          METHOD
local    all        postgres                     peer
host     toko       app_tulis   10.0.1.0/24      scram-sha-256
hostssl  all        all         0.0.0.0/0        scram-sha-256
host     replication replicator 10.0.2.5/32      scram-sha-256
host     all        all         0.0.0.0/0        reject
```

| Metode | Penjelasan |
|---|---|
| `scram-sha-256` | **Direkomendasikan** — password aman |
| `md5` | Lama, usang |
| `peer` | Memakai nama user OS (socket lokal) |
| `cert` | Sertifikat klien TLS |
| `ldap`, `gss`, `sspi`, `radius` | Integrasi direktori/SSO |
| `oauth` | Autentikasi token OAuth (PostgreSQL 18+) — cocok dengan IdP seperti Keycloak |
| `trust` | **Tanpa password — jangan dipakai di produksi** |
| `reject` | Tolak |

Terapkan perubahan `pg_hba.conf` dengan `SELECT pg_reload_conf();` (tanpa restart). Periksa aturan aktif: `SELECT * FROM pg_hba_file_rules;`. Pastikan `password_encryption = scram-sha-256` (default sejak PG 14).

### 13.7 SSL/TLS

Enkripsi koneksi dengan TLS agar password dan data tidak terbaca di jaringan:

```
# postgresql.conf
ssl = on
ssl_cert_file = 'server.crt'
ssl_key_file  = 'server.key'
ssl_min_protocol_version = 'TLSv1.2'
```

| `sslmode` klien | Perilaku |
|---|---|
| `disable` | Tanpa SSL |
| `prefer` (default) | Coba SSL, boleh turun ke tanpa SSL — **tidak aman** |
| `require` | Wajib SSL (tanpa verifikasi sertifikat) |
| `verify-ca` | + verifikasi CA |
| **`verify-full`** | + verifikasi nama host — **disarankan** |

Gunakan `hostssl` di `pg_hba.conf` untuk **mewajibkan** SSL pada koneksi jaringan.

### 13.8 SELinux dan Hardening Sistem

Pada distro berbasis RHEL, **SELinux** membatasi proses `postgres` hanya ke direktori/port berlabel yang diizinkan (mis. data directory di lokasi custom perlu `semanage fcontext` + `restorecon`; port non-standar perlu `semanage port`). Jangan menonaktifkan SELinux — perbaiki labelnya.

Checklist hardening:

| Area | Praktik |
|---|---|
| Jaringan | `listen_addresses` seperlunya; firewall hanya untuk host aplikasi |
| Akun | Tanpa `trust`; password kuat; rotasi kredensial; batasi `SUPERUSER` |
| Hak | Least privilege; cabut `PUBLIC`; role terpisah per fungsi |
| SQL Injection | **Selalu parameterized query**; jangan menyusun SQL dengan string concatenation |
| Fungsi `SECURITY DEFINER` | Set `search_path` aman; cabut `EXECUTE` dari `PUBLIC` |
| Audit | `log_connections`, `log_disconnections`, ekstensi **pgaudit** |
| Patch | Terapkan rilis minor secara rutin (memuat perbaikan keamanan) |
| Backup | Enkripsi backup, uji pemulihan ([Modul 14](14-backup-recovery-upgrade.md)) |

## Praktik

```bash
docker exec -it pg-latihan psql -U postgres -d toko
```

### Role dan Hak Akses

```sql
CREATE ROLE app_baca NOLOGIN;
CREATE ROLE app_tulis NOLOGIN;
CREATE ROLE budi LOGIN PASSWORD 'rahasia-kuat' IN ROLE app_baca;
CREATE ROLE sari LOGIN PASSWORD 'rahasia-kuat2' IN ROLE app_tulis;

REVOKE ALL ON DATABASE toko FROM PUBLIC;
GRANT CONNECT ON DATABASE toko TO app_baca, app_tulis;
GRANT USAGE ON SCHEMA app TO app_baca, app_tulis;
GRANT SELECT ON ALL TABLES IN SCHEMA app TO app_baca;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app TO app_tulis;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA app TO app_tulis;

\du
\dp app.produk
```

### Menguji sebagai Pengguna Lain

```bash
docker exec -it pg-latihan psql -U budi -d toko -h localhost
```

```sql
SELECT count(*) FROM app.produk;                              -- berhasil
UPDATE app.produk SET stok = 0;                               -- ERROR: permission denied
```

### Default Privileges dan Hak per Kolom

```sql
ALTER DEFAULT PRIVILEGES IN SCHEMA app GRANT SELECT ON TABLES TO app_baca;
CREATE TABLE app.tabel_baru (id int);
\dp app.tabel_baru                                            -- app_baca otomatis punya SELECT

CREATE ROLE analis LOGIN PASSWORD 'rahasia-kuat3';
GRANT CONNECT ON DATABASE toko TO analis;
GRANT USAGE ON SCHEMA app TO analis;
GRANT SELECT (id, nama) ON app.pelanggan TO analis;           -- tanpa kolom email
```

### Row-Level Security (Multi-Tenant)

```sql
CREATE TABLE app.dokumen_tenant (id serial PRIMARY KEY, tenant_id int NOT NULL, isi text);
INSERT INTO app.dokumen_tenant (tenant_id, isi) VALUES (1,'rahasia A'), (1,'rahasia A2'), (2,'rahasia B');

ALTER TABLE app.dokumen_tenant ENABLE ROW LEVEL SECURITY;
CREATE POLICY isolasi ON app.dokumen_tenant
  USING (tenant_id = current_setting('app.tenant_id', true)::int)
  WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::int);

GRANT SELECT, INSERT ON app.dokumen_tenant TO app_tulis;
GRANT USAGE ON SEQUENCE app.dokumen_tenant_id_seq TO app_tulis;

SET ROLE sari;
SET app.tenant_id = '1';
SELECT * FROM app.dokumen_tenant;                             -- hanya tenant 1
SET app.tenant_id = '2';
SELECT * FROM app.dokumen_tenant;                             -- hanya tenant 2
INSERT INTO app.dokumen_tenant (tenant_id, isi) VALUES (1, 'curang');   -- ERROR: melanggar policy
RESET ROLE;
```

### Autentikasi

```sql
SHOW password_encryption;
SELECT rolname, left(rolpassword, 14) AS awal_hash FROM pg_authid WHERE rolname = 'budi';  -- 'SCRAM-SHA-256$'
SELECT line_number, type, database, user_name, address, auth_method FROM pg_hba_file_rules;
```

## Latihan

1. Rancang tiga role (`owner`, `aplikasi`, `readonly`) untuk skema `app` dan tulis seluruh perintah `GRANT`/`REVOKE`-nya, termasuk `ALTER DEFAULT PRIVILEGES` agar tabel baru ikut tercakup. Uji dengan login sebagai masing-masing role.
2. Jelaskan perbedaan hak `USAGE` pada schema dan `SELECT` pada tabel. Apa yang terjadi bila hanya salah satunya diberikan?
3. Terapkan RLS untuk skenario "pegawai hanya melihat pesanan yang ditanganinya (`petugas = current_user`), manajer melihat semuanya". Tuliskan dua policy yang diperlukan.
4. Tulis aturan `pg_hba.conf` untuk: aplikasi dari subnet `10.0.1.0/24` memakai SCRAM + SSL, replikasi dari satu IP khusus, dan menolak semua lainnya. Mengapa urutan baris penting?
5. Tunjukkan contoh SQL injection pada query yang dibangun dengan string concatenation, lalu perbaiki memakai parameterized query (bahasa pilihan Anda). Hak apa dari role aplikasi yang membatasi kerusakan?
6. Diskusikan: mengapa aplikasi tidak boleh terhubung sebagai `postgres` (superuser), dan risiko apa yang muncul bila fungsi `SECURITY DEFINER` tidak mengunci `search_path`?

---

[← Modul 12: Arsitektur Internal & Konfigurasi](12-internal-konfigurasi.md) · [Daftar Isi](README.md#daftar-isi) · [Modul 14: Backup, Recovery & Upgrade →](14-backup-recovery-upgrade.md)
