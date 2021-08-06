#!/bin/bash

## コンパネの反映ボタンからコールされる

SACLOUDB_MODULE_BASE=$(cd $(dirname $0)/..; pwd)
cd $SACLOUDB_MODULE_BASE
. .env
. $SACLOUDB_MODULE_BASE/$SACLOUDB_DATABASE_NAME/.env

set -x -e -o pipefail -o errexit

# DB_BACKUP_CONNECT nfs://user:pass@host:port/path
DB_BACKUP_CONNECT_PROTOCOL=$(echo $DB_BACKUP_CONNECT | cut -d':' -f 1)
DB_BACKUP_CONNECT_SRCPATH=/$(echo $DB_BACKUP_CONNECT | cut -d'/' -f 4-)

DB_BACKUP_CONNECT_USERPASSHOSTPORT=$(echo $DB_BACKUP_CONNECT | cut -d'/' -f 3)
if echo $DB_BACKUP_CONNECT_USERPASSHOSTPORT | grep "@" > /dev/null ; then
    DB_BACKUP_CONNECT_USERPASSHOSTPORT=${DB_BACKUP_CONNECT_USERPASSHOSTPORT}:
else
    DB_BACKUP_CONNECT_USERPASSHOSTPORT=:@${DB_BACKUP_CONNECT_USERPASSHOSTPORT}:
fi
DB_BACKUP_CONNECT_USER=$(echo ${DB_BACKUP_CONNECT_USERPASSHOSTPORT//@/:} | cut -d: -f1)
DB_BACKUP_CONNECT_PASS=$(echo ${DB_BACKUP_CONNECT_USERPASSHOSTPORT//@/:} | cut -d: -f2)
DB_BACKUP_CONNECT_HOST=$(echo ${DB_BACKUP_CONNECT_USERPASSHOSTPORT//@/:} | cut -d: -f3)
DB_BACKUP_CONNECT_PORT=$(echo ${DB_BACKUP_CONNECT_USERPASSHOSTPORT//@/:} | cut -d: -f4)

if [ $DB_BACKUP_CONNECT_PROTOCOL != "nfs" ]; then
    echo unsupport $DB_BACKUP_CONNECT_PROTOCOL > $DISTDIR/backup.log
fi

mkdir -p /mnt/backup
mount $DB_BACKUP_CONNECT_HOST:$DB_BACKUP_CONNECT_SRCPATH /mnt/backup

DISTDIR=/mnt/backup/sacloud-appliance/db-$APPLIANCE_ID
mkdir -p $DISTDIR/unlock
mkdir -p $DISTDIR/locked

DATETIME=$(TZ=Asia/Tokyo date '+%Y%m%d-%H%M%S')

(
if [ "$SACLOUDB_DATABASE_NAME" = "MariaDB" ]; then
    # TODO MariaDB 反映ボタン
    cat <<_EOL > $DISTDIR/backup.log
$DISTDIR/unlock/.dump-$DATETIME.sql.gz
_EOL
    echo "TODO MariaDB 反映ボタン"
    mysqldump --quote-names \
        --skip-lock-tables \
        --single-transaction \
        --flush-logs \
        --master-data=1 \
        --all-databases \
        --gtid \
        --log-error=$DISTDIR/mysqldump.err \
    | gzip -c > $DISTDIR/unlock/.dump-$DATETIME.sql.gz 2>> $DISTDIR/backup.log

    mv $DISTDIR/unlock/.dump-$DATETIME.sql.gz $DISTDIR/unlock/dump-$DATETIME.sql.gz 
fi

if [ "$SACLOUDB_DATABASE_NAME" = "postgres" ]; then
    # TODO PostgreSQL 反映ボタン
    echo "TODO PostgreSQL 反映ボタン"
fi

cd /mnt
umount /mnt/backup
) &

exit 0
