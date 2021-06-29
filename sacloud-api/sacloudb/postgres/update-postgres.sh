#!/bin/bash

. $(dirname $0)/.env

cd $SACLOUDB_MODULE_BASE/$SACLOUDB_DATABASE_NAME

set -x -e -o pipefail -o errexit

if [ "$SERVER_ID" = "$SERVER1_ID" ]; then
	if [ ! -f $PGDATA/postgresql.conf ]; then
		$PGHOME/bin/postgresql-$PGVERSION-setup initdb
		su - postgres <<_EOL
$PGHOME/bin/pg_ctl start -D $PGDATA
until psql -c '\l' > /dev/null 2>&1 ; do echo "connecting...3"; sleep 1; done

# 起動確認
cat <<_SQL | psql
CREATE USER "$SACLOUDB_ADMIN_USER" WITH SUPERUSER CREATEDB CREATEROLE INHERIT LOGIN REPLICATION PASSWORD '$SACLOUDB_ADMIN_PASS';
GRANT "postgres" TO "sacloud-admin";

CREATE USER "$SACLOUDB_DEFAULT_USER" PASSWORD '$SACLOUDB_DEFAULT_PASS';
CREATE SCHEMA IF NOT EXISTS "$SACLOUDB_DEFAULT_USER" AUTHORIZATION "$SACLOUDB_DEFAULT_USER";
CREATE DATABASE "$SACLOUDB_DEFAULT_USER";
GRANT ALL PRIVILEGES ON DATABASE "$SACLOUDB_DEFAULT_USER" TO "$SACLOUDB_DEFAULT_USER";

_SQL
    $PGHOME/bin/pg_ctl stop -D $PGDATA
_EOL
        wait_for_db_shutdown
	fi

	: =====================================================
	:  modify $PGDATA/postgresql.conf : $0:$LINENO
	: =====================================================
	sacloud_func_file_cleanup $PGDATA/postgresql.conf
	sed -e "s/^#\{0,1\}include_dir = '[^ ]*'/include_dir = 'conf.d'/g" \
		-e 's/^#search_path = /search_path = /g' \
		-i $PGDATA/postgresql.conf
	mkdir -p $PGDATA/conf.d

	cat <<_EOL > $PGDATA/conf.d/sacloudb.conf
listen_addresses = '*' # what IP address(es) to listen on;

wal_level = hot_standby
max_wal_senders = 3
archive_mode = off
#wal_keep_segments = 30
max_replication_slots = 3
hot_standby = on
##synchronous_commit = on #remote_write
##synchronous_standby_names = '1 (walreceiver)'

wal_log_hints = on 
recovery_target_timeline = 'latest'

log_file_mode = 117
_EOL

	: =====================================================
	:  modify $PGDATA/pg_hba.conf : $0:$LINENO
	: =====================================================
	sacloud_func_file_cleanup $PGDATA/pg_hba.conf

	cat <<_EOL >> $PGDATA/pg_hba.conf
# sacloud
local   all             $SACLOUD_ADMIN_USER                      peer
host    replication     $SACLOUD_ADMIN_USER  $DB_REPLICATION_NETROWK_ADDRESS/$DB_REPLICATION_NETROWK_MASKLEN    md5

host    all             all             127.0.0.1/32    md5
host    all             all             $DB_REPLICATION_NETROWK_ADDRESS/$DB_REPLICATION_NETROWK_MASKLEN    md5

# /sacloud
_EOL


fi

:
: =====================================================
:  modify .pgpass in HOME : $0:$LINENO
: =====================================================
sacloud_func_file_cleanup /var/lib/pgsql/.pgpass
cat <<_EOL > /var/lib/pgsql/.pgpass
//[IP]:[port][dbname]:[user]:[password]
$SERVER1_LOCALIP:$PGPORT:*:$SACLOUDB_ADMIN_USER:$SACLOUDB_ADMIN_PASS
$SERVER2_LOCALIP:$PGPORT:*:$SACLOUDB_ADMIN_USER:$SACLOUDB_ADMIN_PASS
localhost:$PGPORT:*:$SACLOUDB_ADMIN_USER:$SACLOUDB_ADMIN_PASS
db-$APPLIANCE_ID-01:$PGPORT:*:$SACLOUDB_ADMIN_USER:$SACLOUDB_ADMIN_PASS
db-$APPLIANCE_ID-02:$PGPORT:*:$SACLOUDB_ADMIN_USER:$SACLOUDB_ADMIN_PASS

$SERVER1_LOCALIP:9999:*:$SACLOUDB_ADMIN_USER:$SACLOUDB_ADMIN_PASS
$SERVER2_LOCALIP:9999:*:$SACLOUDB_ADMIN_USER:$SACLOUDB_ADMIN_PASS
localhost:9999:*:$SACLOUDB_ADMIN_USER:$SACLOUDB_ADMIN_PASS
db-$APPLIANCE_ID-01:9999:*:$SACLOUDB_ADMIN_USER:$SACLOUDB_ADMIN_PASS
db-$APPLIANCE_ID-02:9999:*:$SACLOUDB_ADMIN_USER:$SACLOUDB_ADMIN_PASS

_EOL

chmod 600 /var/lib/pgsql/.pgpass
chown -R postgres:postgres /var/lib/pgsql

cp -f /var/lib/pgsql/.pgpass /home/$SACLOUD_ADMIN_USER/.
chown -R $SACLOUD_ADMIN_USER:$SACLOUD_ADMIN_USER /home/$SACLOUD_ADMIN_USER

cp -f /var/lib/pgsql/.pgpass /usr/share/httpd/.pgpass 
chown -R apache:apache /usr/share/httpd/.pgpass

: 再起動 $0:$LINENO at $(date "+%Y/%m/%d-%H:%M:%S")
apachectl restart



: #初期設定# $0:$LINENO at $(date "+%Y/%m/%d-%H:%M:%S")

export PGADMIN_SETUP_EMAIL=$SACLOUDB_ADMIN_USER
export PGADMIN_SETUP_PASSWORD=$SACLOUDB_ADMIN_PASS
export PYTHONPATH=/usr/pgadmin4/venv/lib/python3.6/site-packages
mkdir -p /var/lib/pgadmin /var/log/pgadmin

cat <<_EOF > /var/lib/pgadmin/servers.json
{
    "Servers": {
		"1": {
            "Name": "db-$APPLIANCE_ID(pgpool:9999)",
            "Group": "db-$APPLIANCE_ID",
            "Host": "$SERVER_VIP",
            "Port": 9999,
            "MaintenanceDB": "$SACLOUDB_DEFAULT_USER",
            "Username": "$SACLOUDB_DEFAULT_USER",
            "SSLMode": "prefer",
            "SSLCert": "<STORAGE_DIR>/.postgresql/postgresql.crt",
            "SSLKey": "<STORAGE_DIR>/.postgresql/postgresql.key",
            "SSLCompression": 0,
            "Timeout": 10,
            "UseSSHTunnel": 0,
            "TunnelPort": "22",
            "TunnelAuthentication": 0
        },
		"2": {
            "Name": "db-$APPLIANCE_ID(VIP:$PGPORT)",
            "Group": "db-$APPLIANCE_ID",
            "Host": "$SERVER_VIP",
            "Port": $PGPORT,
            "MaintenanceDB": "$SACLOUDB_DEFAULT_USER",
            "Username": "$SACLOUDB_DEFAULT_USER",
            "SSLMode": "prefer",
            "SSLCert": "<STORAGE_DIR>/.postgresql/postgresql.crt",
            "SSLKey": "<STORAGE_DIR>/.postgresql/postgresql.key",
            "SSLCompression": 0,
            "Timeout": 10,
            "UseSSHTunnel": 0,
            "TunnelPort": "22",
            "TunnelAuthentication": 0
        },
		"3": {
            "Name": "db-$APPLIANCE_ID-01",
            "Group": "db-$APPLIANCE_ID",
            "Host": "$SERVER1_LOCALIP",
            "Port": $PGPORT,
            "MaintenanceDB": "$SACLOUDB_DEFAULT_USER",
            "Username": "$SACLOUDB_DEFAULT_USER",
            "SSLMode": "prefer",
            "SSLCert": "<STORAGE_DIR>/.postgresql/postgresql.crt",
            "SSLKey": "<STORAGE_DIR>/.postgresql/postgresql.key",
            "SSLCompression": 0,
            "Timeout": 10,
            "UseSSHTunnel": 0,
            "TunnelPort": "22",
            "TunnelAuthentication": 0
        },
		"4": {
            "Name": "db-$APPLIANCE_ID-02",
            "Group": "db-$APPLIANCE_ID",
            "Host": "$SERVER2_LOCALIP",
            "Port": $PGPORT,
            "MaintenanceDB": "$SACLOUDB_DEFAULT_USER",
            "Username": "$SACLOUDB_DEFAULT_USER",
            "SSLMode": "prefer",
            "SSLCert": "<STORAGE_DIR>/.postgresql/postgresql.crt",
            "SSLKey": "<STORAGE_DIR>/.postgresql/postgresql.key",
            "SSLCompression": 0,
            "Timeout": 10,
            "UseSSHTunnel": 0,
            "TunnelPort": "22",
            "TunnelAuthentication": 0
        }
    }
}
_EOF

# pgadmin4 version 5.4 は動かない・・・。 
yum erase -y pgadmin4 pgadmin4-*
rpm -ivh https://ftp.postgresql.org/pub/pgadmin/pgadmin4/yum/redhat/rhel-7-x86_64/pgadmin4-server-5.3-1.el7.x86_64.rpm
rpm -ivh https://ftp.postgresql.org/pub/pgadmin/pgadmin4/yum/redhat/rhel-7-x86_64/pgadmin4-python3-mod_wsgi-4.7.1-2.el7.x86_64.rpm
rpm -ivh https://ftp.postgresql.org/pub/pgadmin/pgadmin4/yum/redhat/rhel-7-x86_64/pgadmin4-web-5.3-1.el7.noarch.rpm

cat <<_EOF > /usr/pgadmin4/web/config_local.py
UPGRADE_CHECK_ENABLED=False
_EOF

: #初期化
python3 /usr/pgadmin4/web/setup.py

: #設定情報読み込み# $0:$LINENO at $(date "+%Y/%m/%d-%H:%M:%S")
python3 /usr/pgadmin4/web/setup.py \
	--user $PGADMIN_SETUP_EMAIL \
	--load-servers /var/lib/pgadmin/servers.json

: #権限変更
chown -R apache:apache /var/lib/pgadmin /var/log/pgadmin

: 再起動 $0:$LINENO at $(date "+%Y/%m/%d-%H:%M:%S")
apachectl restart

: 初回アクセス $0:$LINENO at $(date "+%Y/%m/%d-%H:%M:%S")
curl -sSL http://localhost/pgadmin4/ >/dev/null 

: Default User を pgadmin4 に追加
sacloudb_update_pgadmin_user $SACLOUDB_DEFAULT_USER $SACLOUDB_DEFAULT_PASS


: #END# $0:$LINENO at $(date "+%Y/%m/%d-%H:%M:%S")
