#!/bin/bash

. $(dirname $0)/.env

set -x -e -o pipefail -o errexit
VRRP_STATUS=$(cat $SACLOUD_TMP/.vrrp_status.txt 2>/dev/null)
if [ ! "$VRRP_STATUS" = "MASTER" ]; then
   exit 1
fi

DISTDIR=$SACLOUD_MOUNT_PATH/export/sacloud-appliance/db-$APPLIANCE_ID/backup
if [ ! -d $DISTDIR ] ; then
   exit 1
fi

TO_LOCK_STATUS=$1
LOCK_TIMESTAMP=$2
FILE=$(TZ=Asia/Tokyo date '+dump-%Y%m%d-%H%M%S.sql.gz' -s "$LOCK_TIMESTAMP")
BACKUP_FILE=$(ls $DISTDIR/*lock*/$FILE)

if [ "$BACKUP_FILE" = "" ]; then
    exit 1
else
    mysql -h $SERVER_PEER_LOCALIP -u $SACLOUDB_ADMIN_USER -p$SACLOUDB_ADMIN_PASS -e "stop slave"
    zcat $BACKUP_FILE | mysql
    ssh root@db-$APPLIANCE_ID-$SERVER_PEER_IDX $SACLOUDB_MODULE_BASE/$SACLOUDB_DATABASE_NAME/follow-primary.sh
fi
