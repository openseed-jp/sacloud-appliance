#!/bin/bash

## コンパネの反映ボタンからコールされる

SACLOUDB_MODULE_BASE=$(cd $(dirname $0)/..; pwd)
cd $SACLOUDB_MODULE_BASE
. .env
. $SACLOUDB_MODULE_BASE/$SACLOUDB_DATABASE_NAME/.env

set -x -e -o pipefail -o errexit
if [ $DB_BACKUP_CONNECT_PROTOCOL != "nfs" ]; then
    echo unsupport $DB_BACKUP_CONNECT_PROTOCOL > $DISTDIR/backup.log
fi


VRRP_STATUS=$(cat /tmp/.vrrp_status.txt 2>/dev/null)
if [ ! "$VRRP_STATUS" = "MASTER" ]; then
   if df -h | grep /mnt/backup >/dev/null ; then
      umount /mnt/backup
   fi
   exit
fi

if ! df -h | grep /mnt/backup >/dev/null ; then
    mount $DB_BACKUP_CONNECT_HOST:$DB_BACKUP_CONNECT_SRCPATH /mnt/backup
fi

DISTDIR=/mnt/backup/sacloud-appliance/db-$APPLIANCE_ID
LOCK_STATUS=${1:-locked}
mkdir -p $DISTDIR/$LOCK_STATUS

DATETIME=$(TZ=Asia/Tokyo date '+%Y%m%d-%H%M%S')

if [ "$SACLOUDB_DATABASE_NAME" = "MariaDB" ]; then
    # MariaDB バックアップ作成
    if pgrep mysqldump >/dev/null ; then
        cat <<_EOL
{
    "status_code": 423,
    "message": "process is running..."
}
_EOL
        exit 1
    fi



    cat <<_EOL >> $DISTDIR/backup.log
$DISTDIR/$LOCK_STATUS/.dump-$DATETIME.sql.gz
_EOL
    cat <<_EOL | bash - >/dev/null 2>&1 &
mysqldump --quote-names \
        --skip-lock-tables \
        --single-transaction \
        --flush-logs \
        --master-data=1 \
        --all-databases \
        --gtid \
        --log-error=$DISTDIR/mysqldump.err \
    | gzip -c > $DISTDIR/.dump-$DATETIME.sql.gz 2>> $DISTDIR/backup.log
mv $DISTDIR/.dump-$DATETIME.sql.gz $DISTDIR/$LOCK_STATUS/dump-$DATETIME.sql.gz
$(dirname $0)/execute-list-backup.sh　--force
_EOL

fi

if [ "$SACLOUDB_DATABASE_NAME" = "postgres" ]; then
    echo "TODO PostgreSQL バックアップ作成"
fi

exit 0
