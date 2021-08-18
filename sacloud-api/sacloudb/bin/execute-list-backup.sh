#!/bin/bash

## コンパネのバックアップタブからコールされる
# キャッシュファイルがある場合

SACLOUDB_MODULE_BASE=$(cd $(dirname $0)/..; pwd)
cd $SACLOUDB_MODULE_BASE
. .env
. $SACLOUDB_MODULE_BASE/$SACLOUDB_DATABASE_NAME/.env


if [ ! "$VRRP_STATUS" = "MASTER" -o "$1" = "--force" ]; then
    rm -f $DB_BACKUP_CACHE_FILE
fi

if [ -f $DB_BACKUP_CACHE_FILE ]; then
        cat $DB_BACKUP_CACHE_FILE
        exit
fi

if [ "$DB_BACKUP_CONNECT" = "" ]; then
    exit
fi

# クローンへの登録

sed -e /execute-dump-backup.sh/d /var/spool/cron/root > /var/spool/cron/root.tmp

if [ ! "$DB_BACKUP_TIME" = "" ]; then
    DUMP_COMMAND=$SACLOUDB_MODULE_BASE/bin/execute-dump-backup.sh
    CRON_LINE="$(echo $DB_BACKUP_TIME | cut -d: -f2) $(echo $DB_BACKUP_TIME | cut -d: -f1)  * * $(echo ${DB_BACKUP_DAY:-[0,1,2,3,4,5,6]}  | jq -M -r '.|@csv' | tr -d '"') $DUMP_COMMAND"
    echo "$CRON_LINE" >> /var/spool/cron/root.tmp
fi
if diff /var/spool/cron/root /var/spool/cron/root.tmp >/dev/null 2>&1 ; then
    rm -f /var/spool/cron/root.tmp
else
    cp -f /var/spool/cron/root.tmp /var/spool/cron/root
    chmod 600 /var/spool/cron/root
    systemctl reload crond
fi

set -e -o pipefail -o errexit

if [ $DB_BACKUP_CONNECT_PROTOCOL != "nfs" ]; then
    echo unsupport $DB_BACKUP_CONNECT_PROTOCOL > $DISTDIR/backup.log
fi

if [ -f $DB_BACKUP_CACHE_FILE ]; then
	cat $DB_BACKUP_CACHE_FILE
	exit;
fi

mkdir -p /mnt/backup

if ! df -h | grep /mnt/backup >/dev/null ; then
    mount $DB_BACKUP_CONNECT_HOST:$DB_BACKUP_CONNECT_SRCPATH /mnt/backup
fi

DISTDIR=/mnt/backup/sacloud-appliance/db-$APPLIANCE_ID
mkdir -p $DISTDIR
OUT=$(
for file in $(cd $DISTDIR; find $DISTDIR  -name dump-*.sql.gz  | xargs ls -t | grep .sql.gz) ; do

name=$(basename $file)
#timestamp=$(TZ=Asia/Tokyo date '+%FT%T%:z' -s "`stat -c  %x $file`")
timestamp=$(basename $file | sed 's/dump-\([0-9]\{4\}\)\([0-9][0-9]\)\([0-9][0-9]\)-\([0-9][0-9]\)\([0-9][0-9]\)\([0-9][0-9]\).sql.gz/\1-\2-\3T\4:\5:\6+09:00/g')
parent_dir=$(dirname $file)
type=$(basename $parent_dir)
backuptype=SQL
recoveredat="0000-00-00T00:00:00+09:00"


case $type in
"unlock")
    type=discontinued;;
"locked")
    type=avaiable;;
*)
    type=zombie;;
esac

cat <<_EOL
{
    "createdat": "$timestamp",
    "availability": "$type",
    "backuptype": "$backuptype",
    "recoveredat": "$recoveredat",
    "size": "$(stat -c  %s $file)"
}
_EOL
done
)

echo "$OUT" | jq -s -M '{"files": .}' > $DB_BACKUP_CACHE_FILE
cat $DB_BACKUP_CACHE_FILE

umount /mnt/backup
