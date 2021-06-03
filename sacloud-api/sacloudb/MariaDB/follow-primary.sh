#!/bin/bash

. $(dirname $0)/.env

cd $SACLOUDB_MODULE_BASE/$SACLOUDB_DATABASE_NAME

set -x -e -o pipefail -o errexit

SERVER_NAME_PREFIX=db-${APPLIANCE_ID}

if [ "$SERVER_ID" = "$SERVER1_ID" ]; then
	SERVER_PRIMARY_IP=$SERVER2_LOCALIP
	SERVER_SECONDARY_IP=$SERVER1_LOCALIP
else
	SERVER_PRIMARY_IP=$SERVER1_LOCALIP
	SERVER_SECONDARY_IP=$SERVER2_LOCALIP
fi

if [ "$1" = "--force" ]; then
        : 対抗のサーバが Master　でログイン可能
	until echo "\q;" | mysql \
                        -h ${SERVER_PRIMARY_IP} \
                        -u${SACLOUDB_REPLICA_USER} \
                        -p${SACLOUDB_REPLICA_PASS} 2>/dev/null ; do 
                echo "Try connect to ${SERVER_PRIMARY_IP} by ${SACLOUDB_REPLICA_USER}"
                sleep 1
        done
else
        mysqladmin stop-slave
        mysqladmin start-slave
        sleep 5



        LIST_SERVERS=$(maxctrl list servers)
        if echo "$LIST_SERVERS" | grep ${SERVER_PRIMARY_IP} | grep "Master" 2>&1 >/dev/null ; then
                : 対抗のサーバが Master　でログイン可能
                until echo "\q;" | mysql -h ${SERVER_PRIMARY_IP} -u ${SACLOUDB_REPLICA_USER} -p${SACLOUDB_REPLICA_PASS} 2>/dev/null ; do 
                        echo "Try connect to ${SERVER_PRIMARY_IP} by ${SACLOUDB_REPLICA_USER}"
                        sleep 1
                done
                if echo  "$LIST_SERVERS" | grep ${SERVER_SECONDARY_IP} | grep "Slave, Running" 2>&1 >/dev/null ; then
                        : すでに、Slave
                        CHECK_GTID=$(echo "$LIST_SERVERS" | grep ${SERVER_NAME_PREFIX}-0 | cut -d'│' -f7 | uniq | wc -l)
                        if [ "$CHECK_GTID" = "1" ]; then
                                : GTID が同じ
                                exit 1;
                        fi
                fi

                MSG_OK="Slave_SQL_Running_State: Slave has read all relay log"
                STATUS=$(echo "show slave status\G" | mysql | grep "$MSG_OK" | wc -l || true)
                if [ ! "$STATUS" = "0" ]; then
                        echo $MSG_OK
                        echo "$LIST_SERVERS"
                        exit 1
                fi 
                # slave status\G が、これだったら、強制なのかなぁ・・・
                # Last_Error: An attempt was made to binlog GTID
        else
                : Master がいなければ、追従しない。
                echo "Can not follow Master is gone."
                echo "$LIST_SERVERS"
                exit 1
        fi
fi

# 
# echo 'DELETE FROM `mysql`.`gtid_slave_pos`; RESET MASTER;' | mysql -h ${SERVER_PRIMARY_IP} -u ${SACLOUDB_REPLICA_USER} -p${SACLOUDB_REPLICA_PASS}'

mysqladmin shutdown
rm -rf /var/lib/mysql/*
su - mysql -s /bin/sh sh -c 'mysql_install_db --datadir=/var/lib/mysql'
rm -f /var/lib/mysql/*-bin.*


mysqld_safe --skip-grant-tables --skip-networking &
until echo "\q;" | mysql -u root 2>/dev/null ; do sleep 1; done

echo "$(cat <<_EOL
STOP SLAVE;
RESET SLAVE ALL;
SET GLOBAL read_only=1;
_EOL
)" | mysql -u root 

mysqldump -h ${SERVER_PRIMARY_IP} \
        -u${SACLOUDB_REPLICA_USER} \
        -p${SACLOUDB_REPLICA_PASS} \
        --quote-names \
        --skip-lock-tables \
        --single-transaction \
        --flush-logs \
        --master-data=1 \
        --all-databases \
        --gtid \
        | mysql --user=root

GTID_SLAVE_POS=$(mysql -NB -u root -e 'SELECT @@gtid_slave_pos')

wait_for_db_shutdown
systemctl start mariadb
until echo "\q;" | mysql -u root 2>/dev/null ; do sleep 1; done

#rm -f /var/lib/mysql/*-bin.*

echo "$(cat <<_EOL
RESET MASTER;
SET GLOBAL gtid_slave_pos='${GTID_SLAVE_POS}';
CHANGE MASTER TO 
        MASTER_HOST='${SERVER_PRIMARY_IP}',
        MASTER_PORT=3306,
        MASTER_USER='${SACLOUDB_REPLICA_USER}',
        MASTER_PASSWORD='${SACLOUDB_REPLICA_PASS}',
        MASTER_CONNECT_RETRY = 20,
        MASTER_HEARTBEAT_PERIOD = 30,
        MASTER_USE_GTID=slave_pos;
SET GLOBAL read_only=1;
START SLAVE;
_EOL
)" | mysql -u root
