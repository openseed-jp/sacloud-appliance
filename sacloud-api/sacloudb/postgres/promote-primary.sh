#!/bin/bash

. $(dirname $0)/.env

cd $SACLOUDB_MODULE_BASE/$SACLOUDB_DATABASE_NAME

set -x -e -o pipefail -o errexit

if [ "$SERVER_ID" = "$SERVER1_ID" ]; then
	SERVER_PRIMARY_LOCALIP=$SERVER1_LOCALIP
else
	SERVER_PRIMARY_LOCALIP=$SERVER2_LOCALIP
fi

su - postgres -c "$PGHOME/bin/pg_ctl start -D $PGDATA"
wait_for_db_connect $SERVER_PRIMARY_LOCALIP
