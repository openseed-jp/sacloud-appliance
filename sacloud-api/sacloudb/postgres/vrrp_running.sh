#!/bin/bash

cd $(dirname $0)
. .env

set -o pipefail

export PGPASSFILE=/home/sacloud-admin/.pgpass
psql -h localhost -U sacloud-admin -p 5432 postgres -c "SELECT pg_is_in_recovery();"  -P expanded=on --csv > $SACLOUD_TMP/.status/postgres

systemctl status pgpool > $SACLOUD_TMP/.status/pgpool
STATUS_PGPOOL=$?
if [ ! $STATUS_PGPOOL = 0 ]; then
#    shutdown -t0 now
    exit 1
fi

ip addr | grep "scope global secondary" >/dev/null
BACKUP_VIP=$?

# バックアップとして動作していた場合、 常にリカバリ中のため、 t となる。 プライマリは、 f
grep 'pg_is_in_recovery,f' $SACLOUD_TMP/.status/postgres > /dev/null 2>&1
BACKUP_DB=$?

echo $BACKUP_VIP $BACKUP_DB
if [ $BACKUP_VIP = 0 -a $BACKUP_DB = 1 ]; then
    # VIP がプライマリの時, DB がバックアップだったら、NG
    exit 1;
fi

exit 0
