#!/bin/bash

. $(dirname $0)/.env

cd $SACLOUDB_MODULE_BASE/$SACLOUDB_DATABASE_NAME

set -x -e -o pipefail -o errexit


FORCE=$1


if [ "$SERVER_ID" = "$SERVER1_ID" ]; then
    SERVER_PRIMARY_IP=$SERVER2_LOCALIP
    SERVER_SECONDARY_IP=$SERVER1_LOCALIP

    FAILED_NODE_ID=0
    FAILED_NODE_HOST=db-$APPLIANCE_ID-01
    NEW_MASTER_NODE_ID=1
    NEW_MASTER_NODE_HOST=db-$APPLIANCE_ID-02
else
    SERVER_PRIMARY_IP=$SERVER1_LOCALIP
    SERVER_SECONDARY_IP=$SERVER2_LOCALIP

    FAILED_NODE_ID=1
    FAILED_NODE_HOST=db-$APPLIANCE_ID-02
    NEW_MASTER_NODE_ID=0
    NEW_MASTER_NODE_HOST=db-$APPLIANCE_ID-01
fi
FAILED_NODE_PORT=5432
FAILED_NODE_PGDATA=/var/lib/pgsql/13/data
NEW_MASTER_NODE_PORT=5432
NEW_MASTER_NODE_PGDATA=/var/lib/pgsql/13/data




SLOT_NAME=$(hostname | tr - _)

if wait_for_db_connect $SERVER_PRIMARY_IP 20 ; then
    wait_for_db_shutdown

    if [ "$FORCE" = "--force" -o ! -d "$PGDATA" ]; then
        : セカンダリのVM 初回同期
        su - postgres <<_EOL
            psql -h $SERVER_PRIMARY_IP -U $SACLOUDB_ADMIN_USER postgres -c "select pg_drop_replication_slot('$SLOT_NAME');" >/dev/null 2>&1 || true
            rm -rf ${PGDATA}/*
            ${PGHOME}/bin/pg_basebackup \
                -h $SERVER_PRIMARY_IP \
                -U $SACLOUDB_ADMIN_USER \
                -p $PGPORT \
                -D $PGDATA \
                -X stream \
                --write-recovery-conf \
                --create-slot --slot=${SLOT_NAME}

            cat  << _EOF > $PGDATA/conf.d/01_standby_names.conf
synchronous_standby_names = ''
synchronous_commit = on
_EOF
            sed -i $PGDATA/postgresql.auto.conf -e "s/^primary_conninfo = 'user/primary_conninfo = 'application_name=''${SLOT_NAME}'' user/g"
            $PGHOME/bin/pg_ctl -l /dev/null -w -D $PGDATA start

_EOL

    else
        if ! systemctl status pgpool ; then
            systemctl start pgpool
        fi
        cat <<_LOG
            /etc/pgpool-II/follow_master.sh \
                $FAILED_NODE_ID $FAILED_NODE_HOST $FAILED_NODE_PORT $FAILED_NODE_PGDATA \
                $NEW_MASTER_NODE_ID $NEW_MASTER_NODE_HOST \
                -1 -1 \
                $NEW_MASTER_NODE_PORT $NEW_MASTER_NODE_PGDATA 
_LOG


        su - postgres <<_EOL 
            $PGHOME/bin/pg_ctl -l /dev/null -w -D $PGDATA start
            sleep 5
            /etc/pgpool-II/follow_master.sh \
                $FAILED_NODE_ID $FAILED_NODE_HOST $FAILED_NODE_PORT $FAILED_NODE_PGDATA \
                $NEW_MASTER_NODE_ID $NEW_MASTER_NODE_HOST \
                -1 -1 \
                $NEW_MASTER_NODE_PORT $NEW_MASTER_NODE_PGDATA 
_EOL
    fi
else
    echo "マスターに接続できない"
    exit 1
fi

