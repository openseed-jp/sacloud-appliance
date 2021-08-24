#!/bin/bash

## コンパネの反映ボタンからコールされる


cd $(dirname $0)/.. && . .env
. $SACLOUDB_MODULE_BASE/$SACLOUDB_DATABASE_NAME/.env

set -x -e -o pipefail -o errexit

$SACLOUDAPI_HOME/bin/update-config.sh
$SACLOUDAPI_HOME/sacloudb/bin/update-monitoring.sh --graceful
$SACLOUDAPI_HOME/sacloudb/$SACLOUDB_DATABASE_NAME/update-parameter.sh

# autofs
if [ "$DB_BACKUP_CONNECT" = "" ]; then
    cat /dev/null > /etc/auto.sacloud
    systemctl restart autofs
else
    cat <<_EOF > /etc/auto.sacloud
export -fstype=$DB_BACKUP_CONNECT_PROTOCOL,rw,hard,intr,rsize=32768,wsize=32768 $DB_BACKUP_CONNECT_HOST:$DB_BACKUP_CONNECT_SRCPATH
_EOF
    systemctl reload autofs
    if [ "$?" = 0 ]; then
        mkdir -p $SACLOUD_MOUNT_PATH/export/sacloud-appliance/db-$APPLIANCE_ID/backup
    fi
fi

# キャッシュの削除
$SACLOUDAPI_HOME/sacloudb/bin/execute-list-backup.sh --force
