#!/bin/bash

SACLOUDB_MODULE_BASE=$(cd $(dirname $0)/..; pwd)
cd $SACLOUDB_MODULE_BASE
. .env
. $SACLOUDB_MODULE_BASE/$SACLOUDB_DATABASE_NAME/.env

set -x -e -o pipefail -o errexit

# keepalived の最終ステイタスを更新
echo "STOP" > $SACLOUD_TMP/.vrrp_status.txt
chmod 666 $SACLOUD_TMP/.vrrp_status.txt

# 各DBの初期化処理
$SACLOUDB_MODULE_BASE/$SACLOUDB_DATABASE_NAME/boot.sh

# cron 登録
cat <<_EOL > /var/spool/cron/root
* * * * *   $SACLOUDB_MODULE_BASE/bin/cron1min.sh >/dev/null 2>&1
*/5 * * * * $SACLOUDB_MODULE_BASE/bin/cron5min.sh >/dev/null 2>&1
_EOL
chmod 600 /var/spool/cron/root
chown root:root /var/spool/cron/root
systemctl reload crond

# Config の更新
$SACLOUDB_MODULE_BASE/bin/update-config.sh

echo "boot.sh done!"
