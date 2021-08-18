#!/bin/bash

SACLOUDB_MODULE_BASE=$(cd $(dirname $0)/..; pwd)
cd $SACLOUDB_MODULE_BASE
. .env
. $SACLOUDB_MODULE_BASE/$SACLOUDB_DATABASE_NAME/.env

set -x -e -o pipefail -o errexit

$SACLOUDB_MODULE_BASE/bin/update-monitoring.sh

echo "STOP" > /tmp/.vrrp_status.txt

if [ "$SACLOUDB_DATABASE_NAME" = "MariaDB" ]; then
    systemctl start mariadb

    wait_for_db_connect $SERVER1_LOCALIP 3
    wait_for_db_connect $SERVER2_LOCALIP 3

    : #対向確認
    if mysql -h $SERVER_PEER_LOCALIP -u $SACLOUDB_ADMIN_USER -p$SACLOUDB_ADMIN_PASS -e"show slave status\G" | grep "SQL_Delay: 0" ; then
        : #対向がSlaveが開始している場合。
        if mysql -h $SERVER_LOCALIP -u $SACLOUDB_ADMIN_USER -p$SACLOUDB_ADMIN_PASS -e"show slave status\G" | grep "Master_Host: $SERVER_PEER_LOCALIP" ; then
            : #自分も Slave だった。

            : TODO: 人の判断が必要かも。
        else
            : #読み込み専用だったら
            if mysql -h $SERVER_LOCALIP -u $SACLOUDB_ADMIN_USER -p$SACLOUDB_ADMIN_PASS -e"select @@read_only\G" | grep "@@read_only: 1" ; then
                : #書き込み可能にする
                mysql -h $SERVER_LOCALIP -u $SACLOUDB_ADMIN_USER -p$SACLOUDB_ADMIN_PASS -e"set global read_only=0"
            fi
        fi
    fi

    if systemctl status mariadb; then
        systemctl start maxscale
    fi

    if systemctl status maxscale; then
        systemctl start keepalived
    else
        echo "FATAL";
    fi
fi

if [ "$SACLOUDB_DATABASE_NAME" = "postgres" ]; then
    wait_for_db_shutdown
    su - postgres -c "$PGHOME/bin/pg_ctl start -D $PGDATA"

    wait_for_db_connect $SERVER1_LOCALIP 3
    wait_for_db_connect $SERVER2_LOCALIP 12


    systemctl start pgpool
    systemctl start keepalived


    # Apache からログをみたいため
    chmod 710 /var/lib/pgsql /var/lib/pgsql/13 /var/lib/pgsql/13/data
    chmod 770 /var/lib/pgsql/13/data/log
fi

apachectl restart

# cron 登録
cat <<_EOL > /var/spool/cron/root
* * * * *   $SACLOUDB_MODULE_BASE/bin/cron1min.sh >/dev/null 2>&1
*/5 * * * * $SACLOUDB_MODULE_BASE/bin/cron5min.sh >/dev/null 2>&1
_EOL
chmod 600 /var/spool/cron/root
chown root:root /var/spool/cron/root
systemctl reload crond


# Config の更新
$SACLOUDAPI_HOME/bin/update-config.sh
$SACLOUDB_MODULE_BASE/bin/execute-list-backup.sh --force

echo "boot.sh done!"
