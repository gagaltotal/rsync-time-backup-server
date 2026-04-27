# Rsync-time-backup-server

`rsync_backup.sh` adalah skrip backup berbasis `rsync` yang membuat backup inkremental dengan struktur folder timestamp. Skrip ini mendukung backup lokal dan melalui SSH, serta otomatis mengelola backup lama menggunakan strategi retensi yang dapat dikonfigurasi.

## Isi folder

- `rsync_backup.sh` - skrip utama backup.
- `README.md` - dokumentasi penggunaan dan fitur.

## Fitur

- Backup incremental dengan hard link ke backup sebelumnya.
- Backup sumber lokal atau remote melalui SSH.
- Mendukung kunci SSH khusus (`--id_rsa`) dan port SSH kustom (`-p`).
- Folder backup dibuat berdasarkan timestamp `YYYY-MM-DD-HHMMSS`.
- `latest` symlink menunjuk ke backup terakhir yang berhasil.
- Deteksi otomatis jika sumber atau tujuan berada di filesystem FAT, kemudian menambahkan opsi `--modify-window=2`.
- Pengecekan safety via `backup.marker` di direktori tujuan.
- Resume backup yang terputus dengan file `.inprogress`.
- Opsi `--log-dir` atau `--log-to-destination` untuk mengatur lokasi file log.
- Retensi backup otomatis berdasarkan strategi `--strategy`.
- Opsi `--no-auto-expire` untuk menonaktifkan pembersihan otomatis saat disk penuh.

## Instalasi

![Screen Capture](https://raw.githubusercontent.com/gagaltotal/rsync-time-backup-server/refs/heads/main/Screenshot%20from%202026-04-27%2010-38-32.png)

Simpan `rsync_backup.sh` di folder pilihan Anda dan beri izin eksekusi:

```bash
chmod +x rsync_backup.sh
```

## Contoh penggunaan

```bash
./rsync_backup.sh /home/user /mnt/backup_drive
```

Backup dengan daftar pengecualian:

```bash
./rsync_backup.sh /home/user /mnt/backup_drive exclude-patterns.txt
```

Backup ke tujuan remote melalui SSH di port 2222:

```bash
./rsync_backup.sh -p 2222 /home/user user@example.com:/mnt/backup_drive
```

Backup dari sumber remote:

```bash
./rsync_backup.sh user@example.com:/home/user /mnt/backup_drive
```

## Opsi

```text
Usage: rsync_backup.sh [OPTION]... <[USER@HOST:]SOURCE> <[USER@HOST:]DESTINATION> [exclude-pattern-file]

Options
 -p, --port             SSH port.
 -h, --help             Display this help message.
 -i, --id_rsa           Specify the private ssh key to use.
 --rsync-get-flags      Display the default rsync flags that are used for backup.
 --rsync-set-flags      Set the rsync flags that are going to be used for backup.
 --rsync-append-flags   Append the rsync flags that are going to be used for backup.
 --log-dir              Set the log file directory. Generated log files will not be automatically deleted.
 --log-to-destination   Use the destination directory for logs. Generated log files will not be automatically deleted.
 --strategy             Set the expiration strategy. Default: "1:1 30:7 365:30".
 --no-auto-expire       Disable automatic deletion of old backups when out of space.
```

Default folder log:

```bash
~/.rsync_backup
```

## Penjelasan strategi retensi

Strategi retensi default `1:1 30:7 365:30` berarti:

- Setelah 1 hari, simpan satu backup setiap 1 hari.
- Setelah 30 hari, simpan satu backup setiap 7 hari.
- Setelah 365 hari, simpan satu backup setiap 30 hari.

## Cara restore

Backup disimpan sebagai folder biasa, jadi Anda dapat mengembalikannya dengan `rsync` atau penyalinan file biasa:

```bash
rsync -aP /path/to/backup/ /path/to/restore/
```

Gunakan `--dry-run` terlebih dahulu jika ingin memeriksa perubahan tanpa benar-benar menyalin.

## Lisensi

Skrip ini menggunakan lisensi MIT.
