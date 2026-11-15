# Moodle Docker Deployment

Moodle berjalan sebagai stack Docker Compose dengan PHP-FPM, nginx, MariaDB,
dan worker cron. Development membangun image dari source lokal, sedangkan
production menarik image release dari GitHub Container Registry (GHCR).

## Arsitektur

| Service | Development | Production |
| --- | --- | --- |
| `app` | Image dibangun lokal | `ghcr.io/diconic-dev/moodle:<version>` |
| `web` | nginx dengan source tree read-only | `ghcr.io/diconic-dev/moodle:<version>-web` |
| `db` | MariaDB 11 | MariaDB 11 |
| `cron` | Memakai image `app` | Memakai image release `app` |

Database dan `moodledata` disimpan dalam named volume Docker.

## Development

Salin template environment lalu isi password database:

```bash
cp .env.example .env
docker compose up -d --build
```

Buka <http://localhost:8080>. Jangan membuka `http://localhost:9000`:
service `app` menjalankan PHP-FPM pada port FastCGI internal, bukan HTTP.
Port `9000` tidak dipublish ke host; request browser harus masuk melalui
service nginx `web` pada port `8080`.

Perintah yang berguna:

```bash
docker compose ps
docker compose logs -f app
docker compose exec app php admin/cli/cron.php
docker compose down
```

Development menggunakan [compose.yaml](./compose.yaml), membangun image
aplikasi dari `Dockerfile`, dan me-mount folder `public/` ke container
`app` dan `cron`, serta source tree ke nginx.

### Development plugin

Setelah repository di-clone ke laptop developer:

```bash
git clone https://github.com/diconic-dev/moodle.git
cd moodle
cp .env.example .env
docker compose up -d --build
```

Plugin dapat dikembangkan langsung di lokasi yang sesuai, misalnya:

```text
public/local/myplugin/
public/mod/myplugin/
public/blocks/myplugin/
public/theme/mytheme/
```

Perubahan kode di `public/` langsung terbaca oleh `app`, `cron`, dan nginx.
Untuk perubahan kode plugin biasa, developer tidak perlu menjalankan build
lagi. Setelah perubahan struktur plugin atau database, jalankan helper script:

```bash
./moodle-upgrade.sh
```

Script tersebut menjalankan upgrade Moodle lalu purge cache. Pastikan stack
development sudah berjalan sebelum menjalankannya.

Build ulang hanya diperlukan jika mengubah Dockerfile, PHP extensions,
dependency Composer, konfigurasi PHP/nginx, atau script entrypoint.

## Production

Production tidak membutuhkan source code atau Dockerfile pada server.

### 1. Siapkan environment

```bash
cp .env.example .env
```

Setidaknya ubah nilai berikut di `.env`:

```env
MOODLE_DB_PASSWORD=<strong-database-password>
MOODLE_DB_ROOT_PASSWORD=<strong-root-password>
MOODLE_WWWROOT=https://moodle.example.com
MOODLE_IMAGE_TAG=5.3.1
MOODLE_REVERSEPROXY=1
MOODLE_SSLPROXY=1
```

Gunakan tag release immutable, bukan `latest`.

### 2. Deploy

```bash
docker compose -f compose.production.yaml pull
docker compose -f compose.production.yaml up -d
```

Periksa status dan log:

```bash
docker compose -f compose.production.yaml ps
docker compose -f compose.production.yaml logs -f app
```

Untuk update versi, ubah `MOODLE_IMAGE_TAG`, lalu jalankan kembali:

```bash
docker compose -f compose.production.yaml pull
docker compose -f compose.production.yaml up -d
```

Jangan menjalankan `docker compose down -v` di production kecuali volume
database dan `moodledata` sudah dibackup dan memang ingin dihapus.

## Image CI/CD

GitHub Actions di [.github/workflows/build.yml](./.github/workflows/build.yml)
akan:

1. Memvalidasi konfigurasi Docker dan script shell.
2. Membuat serta menguji image PHP-FPM.
3. Membuat dan mem-publish image nginx.
4. Mendorong image `linux/amd64` ke GHCR pada push ke `main` atau tag `v*`.

Image public yang dipublikasikan:

```text
ghcr.io/diconic-dev/moodle:<version>
ghcr.io/diconic-dev/moodle:<version>-web
```

Pull request hanya melakukan build dan smoke test; image tidak dipublish.
Production ditargetkan untuk server x86_64. Docker Desktop pada Apple Silicon
tetap dapat menjalankan image `linux/amd64` melalui emulasi.

## Konfigurasi

Gunakan [.env.example](./.env.example) sebagai template. Jangan commit file
`.env` atau secret ke repository.

Entrypoint membuat `config.php` secara otomatis dari environment variables saat
container aplikasi pertama kali berjalan. Tidak perlu membuat `config.php`
secara manual untuk deployment Docker.
