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


VRRP_STATUS=$(cat $SACLOUD_TMP/.vrrp_status.txt 2>/dev/null)
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
TO_LOCK_STATUS=$1
LOCK_TIMESTAMP=$2
FILE=$(TZ=Asia/Tokyo date '+dump-%Y%m%d-%H%M%S.sql.gz' -s "$LOCK_TIMESTAMP")

case "$TO_LOCK_STATUS" in
  "unlock")
    FROM_LOCK_STATUS="locked"
    ;;
  "locked")
    FROM_LOCK_STATUS="unlock"
    ;;
  "delete")
    rm -f $DISTDIR/unlock/$FILE $DISTDIR/locked/$FILE
    exit 0
    ;;
  *)
    exit 1
    ;;
esac

mkdir -p $DISTDIR/$TO_LOCK_STATUS
if [ -f $DISTDIR/$FROM_LOCK_STATUS/$FILE ]; then
    mv $DISTDIR/$FROM_LOCK_STATUS/$FILE $DISTDIR/$TO_LOCK_STATUS/$FILE
    exit 0
fi

exit 1
