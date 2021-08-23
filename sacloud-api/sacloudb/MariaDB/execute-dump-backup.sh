#!/bin/bash

. $(dirname $0)/.env

set -x -e -o pipefail -o errexit

VRRP_STATUS=$(cat $SACLOUD_TMP/.vrrp_status.txt 2>/dev/null)
if [ ! "$VRRP_STATUS" = "MASTER" ]; then
   exit
fi

DISTDIR=$SACLOUD_MOUNT_PATH/export/sacloud-appliance/db-$APPLIANCE_ID/backup
if [ ! -d $DISTDIR ] ; then
   exit
fi

LOCK_STATUS=${1:-locked}
mkdir -p $DISTDIR/$LOCK_STATUS

DATETIME=$(TZ=Asia/Tokyo date '+%Y%m%d-%H%M%S')

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

# バックグランド実行
cat <<_EOL | bash - >/dev/null 2>&1 &
mysqldump --quote-names \
        --skip-lock-tables \
        --single-transaction \
        --flush-logs \
        --add-drop-database \
        --all-databases \
        --log-error=$DISTDIR/mysqldump.err \
    | gzip -c > $DISTDIR/.dump-$DATETIME.sql.gz 2>> $DISTDIR/backup.log
mv $DISTDIR/.dump-$DATETIME.sql.gz $DISTDIR/$LOCK_STATUS/dump-$DATETIME.sql.gz
$SACLOUDB_MODULE_BASE/bin/execute-list-backup.sh --force
_EOL

exit 0
