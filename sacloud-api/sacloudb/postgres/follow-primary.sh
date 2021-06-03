#!/bin/bash

. $(dirname $0)/.env

cd $SACLOUDB_MODULE_BASE/$SACLOUDB_DATABASE_NAME

set -x -e -o pipefail -o errexit


FORCE=$1


if [ "$SERVER_ID" = "$SERVER1_ID" ]; then
    SERVER_PRIMARY_IP=$SERVER2_LOCALIP
    SERVER_SECONDARY_IP=$SERVER1_LOCALIP
else
    SERVER_PRIMARY_IP=$SERVER1_LOCALIP
    SERVER_SECONDARY_IP=$SERVER2_LOCALIP
fi

SLOT_NAME=$(hostname | tr - _)

: セカンダリのVM 初回同期
if [ "$FORCE" = "--force" ]; then
    if wait_for_db_connect $SERVER_PRIMARY_IP 20 ; then
        wait_for_db_shutdown
        rm -rf ${PGDATA}/*
        su - postgres <<_EOL
            psql -h $SERVER_PRIMARY_IP -U $SACLOUDB_ADMIN_USER postgres -c "select pg_drop_replication_slot('$SLOT_NAME');" >/dev/null 2>&1 || true
            ${PGHOME}/bin/pg_basebackup \
                -h $SERVER_PRIMARY_IP \
                -U $SACLOUDB_ADMIN_USER \
                -p $PGPORT \
                -D $PGDATA \
                -X stream \
                -R \
                --write-recovery-conf \
                --create-slot --slot=${SLOT_NAME}
            
            echo "restore_command = 'echo $(hostname) restore_command %f %p'" >> $PGDATA/postgresql.auto.conf

            cat  << _EOF > $PGDATA/conf.d/01_standby_names.conf
synchronous_standby_names = ''
synchronous_commit = on
_EOF
            sed -i $PGDATA/postgresql.auto.conf -e "s/^primary_conninfo = 'user/primary_conninfo = 'application_name=''${SLOT_NAME}'' user/g"
            $PGHOME/bin/pg_ctl -l /dev/null -w -D $PGDATA start
_EOL
    else
        echo "マスターに接続できない"
        exit 1
    fi
fi
