#!/bin/bash

cd $(dirname $0)
. .env

set -x -e -o pipefail -o errexit

wait_for_db_shutdown
if [ -f $PGDATA/postgresql.conf ]; then
    su - postgres -c "$PGHOME/bin/pg_ctl start -D $PGDATA"

    wait_for_db_connect $SERVER1_LOCALIP 3
    wait_for_db_connect $SERVER2_LOCALIP 12

    SERVER_SELF_RECOVERY_MODE=$(PGPASSFILE=/home/$SACLOUDB_ADMIN_USER/.pgpass psql -h $SERVER_LOCALIP -U $SACLOUDB_ADMIN_USER -p 5432 postgres -c "SELECT pg_is_in_recovery();"  -P expanded=on --csv)
    SERVER_PEAR_RECOVERY_MODE=$(PGPASSFILE=/home/$SACLOUDB_ADMIN_USER/.pgpass psql -h $SERVER_PEER_LOCALIP -U $SACLOUDB_ADMIN_USER -p 5432 postgres -c "SELECT pg_is_in_recovery();"  -P expanded=on --csv)
    SERVER_IS_SECONDARY=pg_is_in_recovery,t

    : #対向確認
    if [ "$SERVER_PEAR_RECOVERY_MODE" = "$SERVER_IS_SECONDARY" ] ; then
        : #対向がSlaveが開始している場合。
        if [ "$SERVER_SELF_RECOVERY_MODE" = "$SERVER_IS_SECONDARY" ] ; then
            : #自分も Slave だった。

            : TODO: 人の判断が必要かも。
        else
            : Promote する？
        fi
    else
        # セカンダリで、マスターを追従する。
        $SACLOUDB_MODULE_BASE/$SACLOUDB_DATABASE_NAME/follow-primary.sh
    fi
else
    # postgresql.conf ファイルがない場合は、強制
    $SACLOUDB_MODULE_BASE/$SACLOUDB_DATABASE_NAME/follow-primary.sh --force
fi


#if  su - postgres -c "$PGHOME/bin/pg_ctl status"; then
    systemctl start pgpool
#fi

if systemctl status pgpool; then
    systemctl start keepalived
fi


# Apache からログをみたいため
chmod 710 /var/lib/pgsql /var/lib/pgsql/13 /var/lib/pgsql/13/data
chmod 770 /var/lib/pgsql/13/data/log

