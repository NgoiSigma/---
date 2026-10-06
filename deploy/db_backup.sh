#!/bin/bash

BACKUP_DIR="/var/backups/novea"
DATE=$(date +'%Y-%m-%d_%H-%M')
DB_NAME="novea_db"
ARCHIVE_NAME="novea_backup_$DATE.sql.gz"
SFTP_USER="backup_user"
SFTP_HOST="10.0.0.50" # IP резервного сервера
SFTP_PATH="/backups/novea_atom"

mkdir -p $BACKUP_DIR

echo "[*] Создание дампа TimescaleDB..."
# Используем pg_dump с пайпом в gzip для экономии места на лету
sudo -u postgres pg_dump $DB_NAME | gzip > "$BACKUP_DIR/$ARCHIVE_NAME"

echo "[*] Отправка на удаленный сервер по SFTP..."
# Используем пакетный режим sftp с ключом RSA
sftp -b - -i /root/.ssh/id_rsa_backup $SFTP_USER@$SFTP_HOST <<EOF
cd $SFTP_PATH
put $BACKUP_DIR/$ARCHIVE_NAME
bye
EOF

echo "[*] Очистка старых локальных бэкапов (старше 7 дней)..."
find $BACKUP_DIR -type f -name "*.sql.gz" -mtime +7 -exec rm {} \;

echo "[+] Резервное копирование завершено: $ARCHIVE_NAME"
