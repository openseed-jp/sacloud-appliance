#!/bin/bash

cd $(dirname $0)
. .env

set -x -e -o pipefail -o errexit

wait_for_db_shutdown
su - postgres -c "$PGHOME/bin/pg_ctl start -D $PGDATA"

wait_for_db_connect $SERVER1_LOCALIP 3
wait_for_db_connect $SERVER2_LOCALIP 12


systemctl start pgpool
systemctl start keepalived


# Apache からログをみたいため
chmod 710 /var/lib/pgsql /var/lib/pgsql/13 /var/lib/pgsql/13/data
chmod 770 /var/lib/pgsql/13/data/log

