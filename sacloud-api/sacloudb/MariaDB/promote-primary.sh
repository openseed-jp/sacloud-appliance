#!/bin/bash

. $(dirname $0)/.env

cd $SACLOUDB_MODULE_BASE/$SACLOUDB_DATABASE_NAME

set -x -e -o pipefail -o errexit

if [ "$SERVER_ID" = "$SERVER1_ID" ]; then
	SERVER_PRIMARY_LOCALIP=$SERVER2_LOCALIP
else
	SERVER_PRIMARY_LOCALIP=$SERVER1_LOCALIP
fi

if maxctrl list servers | grep "Master" 2>&1 >/dev/null ; then
	# Master が存在したら、Promoteしない。
	echo "Can not promote. Master is alive."
	maxctrl list servers
	exit 1
fi

	mysql -u root <<_EOL
STOP SLAVE;
RESET SLAVE ALL;
-- DELETE FROM mysql.gtid_slave_pos;
CHANGE MASTER TO
	MASTER_HOST='${SERVER_PRIMARY_LOCALIP}',
	MASTER_PORT=3306,
	MASTER_USER='${SACLOUD_ADMIN_USER}',
	MASTER_PASSWORD='${SACLOUD_ADMIN_PASS}',
	MASTER_CONNECT_RETRY = 20,
	MASTER_HEARTBEAT_PERIOD = 30,
	MASTER_USE_GTID=current_pos;
-- RESET MASTER;
SET GLOBAL read_only=0;

CREATE DATABASE DUMMY_GTID_INIT;
DROP DATABASE DUMMY_GTID_INIT;

_EOL
