#!/bin/bash

SACLOUDB_MODULE_BASE=$(cd $(dirname $0)/..; pwd)
cd $SACLOUDB_MODULE_BASE
. .env
. $SACLOUDB_MODULE_BASE/$SACLOUDB_DATABASE_NAME/.env

set -x -e -o pipefail -o errexit


$SACLOUDB_MODULE_BASE/bin/update-monitoring.sh

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
    wait_for_db_connect $SERVER2_LOCALIP 3


    systemctl start pgpool

    systemctl start keepalived
fi

apachectl restart



# cron 登録
$SACLOUDB_MODULE_BASE/bin/cron5min.sh

echo "boot.sh done!"
