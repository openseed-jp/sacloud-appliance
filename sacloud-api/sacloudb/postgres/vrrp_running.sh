#!/bin/bash

cd $(dirname $0)
. .env

set -o pipefail

# VIP を持っているか判断
ip addr | grep "scope global secondary" >/dev/null
BACKUP_VIP=$?


export PGPASSFILE=/home/sacloud-admin/.pgpass
psql -h localhost -U sacloud-admin -p 5432 postgres -c "SELECT pg_is_in_recovery();"  -P expanded=on --csv > $SACLOUD_TMP/.status/postgres
if [ "$?" = "2" -a "$BACKUP_VIP" = "1" ];then
    ## VIP を持っておらず、PostgreSQL につなげない場合、再起動
    #（さくらのクラウドでは、shutdown すると、別ホストで起動する）
    shutdown -t0 now
fi


psql -h localhost -U sacloud-admin -p 5432 postgres -c "select * from pg_replication_slots" -P expanded=on --csv > $SACLOUD_TMP/.status/replication_slots
psql -h localhost -U sacloud-admin -p 5432 postgres -c "select * from pg_replication_slots"  > $SACLOUD_TMP/.status/replication_slots.txt




systemctl status pgpool > $SACLOUD_TMP/.status/pgpool
STATUS_PGPOOL=$?
if [ ! $STATUS_PGPOOL = 0 ]; then
    shutdown -t0 now
    exit 1
fi


# バックアップとして動作していた場合、 常にリカバリ中のため、 t となる。 プライマリは、 f

if grep 'pg_is_in_recovery,f' $SACLOUD_TMP/.status/postgres > /dev/null 2>&1 ; then
    # Primary
    BACKUP_DB=0
    if grep "priority 100" /etc/keepalived/keepalived.conf; then
        sed -i /etc/keepalived/keepalived.conf -e 's/priority 100/priority 200/'
        (sleep 1 && systemctl reload keepalived) &
    fi
else
    # Backup
    BACKUP_DB=1
    if grep "priority 200" /etc/keepalived/keepalived.conf; then
        sed -i /etc/keepalived/keepalived.conf -e 's/priority 200/priority 100/'
        (sleep 1 && systemctl reload keepalived) &
    fi
fi



echo $BACKUP_VIP $BACKUP_DB
if [ $BACKUP_VIP = 0 -a $BACKUP_DB = 1 ]; then
    # VIP がプライマリの時, DB がバックアップだったら、NG
    exit 1;
fi


exit 0

export PCPPASSFILE=/home/sacloud-admin/.pcppass
psql -h localhost -U sacloud-admin -p 9999 postgres -c "show pool_nodes" > $SACLOUD_TMP/.status/pool_nodes

NODE_ID=$(grep $(hostname) /var/log/sacloud/tmp/.status/pool_nodes | cut -d' ' -f2)
pcp_promote_node -h localhost -U $SACLOUDB_ADMIN_USER  --node-id=$NODE_ID --gracefully


su - $SACLOUDB_ADMIN_USER -c "pcp_promote_node -h localhost -U $SACLOUDB_ADMIN_USER  --node-id=$NODE_ID --gracefully"

exit 0
