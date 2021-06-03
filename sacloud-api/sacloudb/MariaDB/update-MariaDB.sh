#!/bin/bash

. $(dirname $0)/.env

cd $SACLOUDB_MODULE_BASE/$SACLOUDB_DATABASE_NAME

set -x -e -o pipefail -o errexit

DB_SERVER_BASE=db-$SERVER_ID

DB_DOMAIN_ID=$(echo $SERVER_LOCALIP | awk -F. '{print($1*65536+$2*256+$3)}')
DB_SERVER_ID=$(echo $SERVER_LOCALIP | awk -F. '{print($4)}')

cat > /etc/my.cnf.d/sacloudb.cnf <<_EOL
[mariadb]
log-bin = mysql-bin
log-error = error.log
gtid_domain_id=${DB_DOMAIN_ID}
server_id=${DB_SERVER_ID}
log-basename=${DB_SERVER_BASE}
log-slave-updates
gtid_strict_mode
binlog-format = ROW
read_only=1

default-time-zone = 'SYSTEM'
character-set-server = utf8mb4
default_storage_engine = InnoDB

# 準同期用設定
# plugin-load=rpl_semi_sync_master=semisync_master.so;rpl_semi_sync_slave=semisync_slave.so
rpl_semi_sync_master_enabled=1
rpl_semi_sync_master_timeout=1000
rpl_semi_sync_slave_enabled=1
rpl_semi_sync_master_wait_point=AFTER_SYNC


tmpdir=/var/lib/mysql

# カスタマイズ
innodb_flush_method = O_DIRECT
innodb_buffer_pool_size = ${SACLOUDB_INNODB_BUFFER_POOL_SIZE}
sync_binlog = 1
slave_net_timeout = 60
skip_name_resolve = on

[server]
port=3306

_EOL

sacloud_func_file_cleanup /etc/systemd/system/mariadb.service.d/limits.conf
cat <<_EOF > /etc/systemd/system/mariadb.service.d/limits.conf
#

[Service]
LimitNOFILE=32535

_EOF
systemctl daemon-reload


sacloud_func_file_cleanup /root/.my.cnf
cat <<_EOL > /root/.my.cnf

[client]

[mysqldump]
#user=${SACLOUD_ADMIN_USER}
#password=${SACLOUD_ADMIN_PASS}

_EOL

if [ -d /home/${SACLOUD_ADMIN_USER} ]; then
	sacloud_func_file_cleanup /home/${SACLOUD_ADMIN_USER}/.my.cnf
	cat <<_EOL > /home/${SACLOUD_ADMIN_USER}/.my.cnf

[client]
user=${SACLOUDB_ADMIN_USER}
password=${SACLOUDB_ADMIN_PASS}

[mysqldump]
user=${SACLOUDB_ADMIN_USER}
password=${SACLOUDB_ADMIN_PASS}

_EOL
fi


### PHP MYADMIN
sacloud_func_file_cleanup /etc/httpd/conf.d/phpMyAdmin.conf
sed -i /etc/httpd/conf.d/phpMyAdmin.conf -e '/^<Directory \/usr\/share\/phpMyAdmin\/>/,/<\/Directory>/d'
cat <<_EOL >> /etc/httpd/conf.d/phpMyAdmin.conf

<Directory /usr/share/phpMyAdmin/>
	AddDefaultCharset UTF-8
   
	# ベーシック認証(API Key)
	AuthUserFile /etc/httpd/.htpasswd
	AuthGroupFile /dev/null
	AuthName "Basic Auth"
	AuthType Basic
	Require valid-user

	<IfModule mod_authz_core.c>
		# Apache 2.4
		<RequireAny>
			Require ip 127.0.0.1
			Require ip ::1
		</RequireAny>
   </IfModule>
</Directory>

_EOL

E1="s/\(cfg\['blowfish_secret'\]\) = ''/\1 = '$(echo $SERVER_VIP$SACLOUDB_ADMIN_PASS | md5sum | cut -d' ' -f1)'/" 
E2='s/^$cfg..Servers/\/\/\0/g'
E3='/Authentication type/i $cfg["Servers"][$i++] = ["auth_type" => "cookie", "host" => "db-'$APPLIANCE_ID'", "port" => "4006", "compress" => false, "AllowNoPassword" => false];'
E4='/Authentication type/i $cfg["Servers"][$i++] = ["auth_type" => "cookie", "host" => "db-'$APPLIANCE_ID'", "port" => "4008", "compress" => false, "AllowNoPassword" => false];'
E5='/Authentication type/i $cfg["Servers"][$i++] = ["auth_type" => "cookie", "host" => "db-'$APPLIANCE_ID'", "port" => "3306", "compress" => false, "AllowNoPassword" => false];'
E6='/Authentication type/i $cfg["Servers"][$i++] = ["auth_type" => "cookie", "host" => "db-'$APPLIANCE_ID-01'", "port" => "3306", "compress" => false, "AllowNoPassword" => false];'
E7='/Authentication type/i $cfg["Servers"][$i++] = ["auth_type" => "cookie", "host" => "db-'$APPLIANCE_ID-02'", "port" => "3306", "compress" => false, "AllowNoPassword" => false];'
sed -e "$E1" -e "$E2" -e "$E3" -e "$E4" -e "$E5" -e "$E6" -e "$E7" /usr/share/phpMyAdmin/config.sample.inc.php > /usr/share/phpMyAdmin/config.inc.php

# Basic認証のパスワードを利用する場合
# $cfg["Servers"][$i++] = ["auth_type" => "config", "host" => "db-113300012605", "port" => "4008", "compress" => false, "AllowNoPassword" => false, 'user' => $_SERVER['PHP_AUTH_USER'], 'password' => $_SERVER['PHP_AUTH_PW']];


apachectl graceful || apachectl restart

if systemctl status mariadb ; then
	# 起動している場合は何もしない。
	systemctl restart mariadb
	exit
fi


if [ "$SERVER_ID" = "$SERVER1_ID" ]; then
	mysqld_safe --skip-grant-tables --skip-networking &
	until mysql -u root -e"set global read_only=0" 2>/dev/null ; do sleep 1; done

	# ユーザがいなければ、初期化
	if [ $(echo "select user from mysql.user where user='${SACLOUDB_ADMIN_USER}';" | mysql | wc -l) = 0 ]; then
		/usr/bin/mysql_tzinfo_to_sql /usr/share/zoneinfo | mysql -u root mysql
		mysql -u root <<_EOL
FLUSH PRIVILEGES;
set global strict_password_validation = 'OFF';
-- ADMIN
CREATE USER IF NOT EXISTS '${SACLOUDB_ADMIN_USER}'@'localhost' IDENTIFIED VIA unix_socket;
-- ALTER USER '${SACLOUDB_ADMIN_USER}'@'localhost' IDENTIFIED BY '${SACLOUDB_ADMIN_PASS}';
GRANT ALL PRIVILEGES ON *.* TO '${SACLOUDB_ADMIN_USER}'@'localhost' WITH GRANT OPTION;
GRANT SUPER ON *.* TO '${SACLOUDB_ADMIN_USER}'@'localhost';

CREATE USER IF NOT EXISTS '${SACLOUDB_ADMIN_USER}'@'127.0.0.1' IDENTIFIED BY '${SACLOUDB_ADMIN_PASS}';
GRANT ALL PRIVILEGES ON mysql.* TO '${SACLOUDB_ADMIN_USER}'@'127.0.0.1';
GRANT SHOW DATABASES, SELECT ON *.* TO '${SACLOUDB_ADMIN_USER}'@'127.0.0.1';


-- MAXSCALE
CREATE USER IF NOT EXISTS '${SACLOUDB_MAXSCALE_USER}'@'${DB_REPLICATION_NETROWK}' IDENTIFIED BY '${SACLOUDB_MAXSCALE_PASS}';
GRANT SELECT ON mysql.user TO '${SACLOUDB_MAXSCALE_USER}'@'${DB_REPLICATION_NETROWK}';
GRANT SELECT ON mysql.db TO '${SACLOUDB_MAXSCALE_USER}'@'${DB_REPLICATION_NETROWK}';
GRANT SELECT ON mysql.tables_priv TO '${SACLOUDB_MAXSCALE_USER}'@'${DB_REPLICATION_NETROWK}';
GRANT SELECT ON mysql.columns_priv TO '${SACLOUDB_MAXSCALE_USER}'@'${DB_REPLICATION_NETROWK}';
GRANT SELECT ON mysql.proxies_priv TO '${SACLOUDB_MAXSCALE_USER}'@'${DB_REPLICATION_NETROWK}';
GRANT SELECT ON mysql.roles_mapping TO '${SACLOUDB_MAXSCALE_USER}'@'${DB_REPLICATION_NETROWK}';
GRANT SHOW DATABASES, REPLICATION CLIENT, REPLICATION SLAVE, RELOAD, SUPER ON *.* TO '${SACLOUDB_MAXSCALE_USER}'@'${DB_REPLICATION_NETROWK}';

-- REPLICA
CREATE USER IF NOT EXISTS '${SACLOUDB_REPLICA_USER}'@'${DB_REPLICATION_NETROWK}' IDENTIFIED BY '${SACLOUDB_REPLICA_PASS}';
GRANT SELECT, LOCK TABLES, SHOW VIEW, RELOAD, REPLICATION CLIENT, REPLICATION SLAVE ON *.* TO '${SACLOUDB_REPLICA_USER}'@'${DB_REPLICATION_NETROWK}';
GRANT DELETE ON mysql.gtid_slave_pos TO '${SACLOUDB_REPLICA_USER}'@'${DB_REPLICATION_NETROWK}';

FLUSH PRIVILEGES;
set global strict_password_validation = 'ON';

-- OTHER
drop database test;

_EOL
	fi
fi

sacloudb_update_user "$SACLOUDB_DEFAULT_USER" "%" "$SACLOUDB_DEFAULT_PASS" "$SACLOUDB_DEFAULT_USER"

wait_for_db_shutdown
systemctl start mariadb
wait_for_db_connect