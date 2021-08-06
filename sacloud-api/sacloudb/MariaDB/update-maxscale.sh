#!/bin/bash

. $(dirname $0)/.env

cd $SACLOUDB_MODULE_BASE/$SACLOUDB_DATABASE_NAME

systemctl stop keepalived

set -x -e -o pipefail -o errexit

MAXSCALE_SERVER_BASENAME=${APPLIANCE_ID}
MAXSCALE_SERVER_PRIMARY_NAME=db-${APPLIANCE_ID}-01
MAXSCALE_SERVER_PRIMARY_IP=$SERVER1_LOCALIP
MAXSCALE_SERVER_BACKUP_NAME=db-${APPLIANCE_ID}-02
MAXSCALE_SERVER_BACKUP_IP=$SERVER2_LOCALIP

MAXSCALE_SERVER_PORT=3306
MAXSCALE_SERVER_PORT_RW=4006
MAXSCALE_SERVER_PORT_RO=4008

if [ ! -f /var/lib/maxscale/.secrets ]; then
	maxkeys /var/lib/maxscale
fi
SACLOUDB_MAXSCALE_PASS_ENCRYPTED=$(maxpasswd /var/lib/maxscale $SACLOUDB_MAXSCALE_PASS)
#SACLOUDB_MAXSCALE_PASS_ENCRYPTED=$SACLOUDB_MAXSCALE_PASS ## 暗号化しない場合

cat <<_EOL > /etc/maxscale.cnf

# MaxScale documentation:
# https://mariadb.com/kb/en/mariadb-maxscale-24/

# Global parameters
#
# Complete list of configuration options:
# https://mariadb.com/kb/en/mariadb-maxscale-24-mariadb-maxscale-configuration-guide/

[maxscale]
threads=auto
admin_secure_gui=false

# Server definitions
#
# Set the address of the server to the network
# address of a MariaDB server.
#

[${MAXSCALE_SERVER_PRIMARY_NAME}]
type=server
address=${MAXSCALE_SERVER_PRIMARY_IP}
port=${MAXSCALE_SERVER_PORT}
protocol=MariaDBBackend

[${MAXSCALE_SERVER_BACKUP_NAME}]
type=server
address=${MAXSCALE_SERVER_BACKUP_IP}
port=${MAXSCALE_SERVER_PORT}
protocol=MariaDBBackend

# Monitor for the servers
#
# This will keep MaxScale aware of the state of the servers.
# MariaDB Monitor documentation:
# https://mariadb.com/kb/en/mariadb-maxscale-24-mariadb-monitor/

[MariaDB-Monitor]
type=monitor
module=mariadbmon
servers=${MAXSCALE_SERVER_PRIMARY_NAME},${MAXSCALE_SERVER_BACKUP_NAME}
user=${SACLOUDB_MAXSCALE_USER}
password=${SACLOUDB_MAXSCALE_PASS_ENCRYPTED}
monitor_interval=2000
auto_failover=true
auto_rejoin=true

# Service definitions

# Service definitions
#
# Service Definition for a read-only service and
# a read/write splitting service.
#

# ReadConnRoute documentation:
# https://mariadb.com/kb/en/mariadb-maxscale-24-readconnroute/

[Read-Only-Service]
type=service
router=readconnroute
servers=${MAXSCALE_SERVER_PRIMARY_NAME},${MAXSCALE_SERVER_BACKUP_NAME}
user=${SACLOUDB_MAXSCALE_USER}
password=${SACLOUDB_MAXSCALE_PASS_ENCRYPTED}
router_options=slave
#router_options=master,slave

# ReadWriteSplit documentation:
# https://mariadb.com/kb/en/mariadb-maxscale-24-readwritesplit/

[Read-Write-Service]
type=service
router=readwritesplit
servers=${MAXSCALE_SERVER_PRIMARY_NAME},${MAXSCALE_SERVER_BACKUP_NAME}
user=${SACLOUDB_MAXSCALE_USER}
password=${SACLOUDB_MAXSCALE_PASS_ENCRYPTED}
router_options=master
version_string=MaxScale_${MAXSCALE_SERVER_BASENAME}

# Listener definitions for the services
#
# These listeners represent the ports the
# services will listen on.
#

[Read-Only-Listener]
type=listener
service=Read-Only-Service
protocol=MariaDBClient
port=${MAXSCALE_SERVER_PORT_RO}
ssl=true
ssl_cert=/etc/pki/tls/certs/mysql.crt
ssl_key=/etc/pki/tls/private/mysql.key

[Read-Write-Listener]
type=listener
service=Read-Write-Service
protocol=MariaDBClient
port=${MAXSCALE_SERVER_PORT_RW}
ssl=true
ssl_cert=/etc/pki/tls/certs/mysql.crt
ssl_key=/etc/pki/tls/private/mysql.key

_EOL

cat <<'_EOF' > $SACLOUDAPI_HOME/bin/is_running.sh
#!/bin/bash

cd $(dirname $0)
. ../sacloudb/MariaDB/.env

set -o pipefail
fileName="/tmp/.maxctrl_output.txt"

maxctrl list servers --tsv > $fileName.work
to_result=$?

mv -f $fileName.work $fileName
if [ $to_result -ge 1 ]; then
	echo Timed out or error, timeout returned $to_result
	#reboot
	exit 3
else
	echo maxctrl success, rval is $to_result
	echo Checking maxctrl output sanity
	grep1=$(grep $SERVER1_LOCALIP $fileName)
	grep2=$(grep $SERVER2_LOCALIP $fileName)

	if [ "$grep1" ] && [ "$grep2" ]; then
		echo All is fine
		MasterIP=$(grep 'Master, Running' $fileName | cut -f2)
		if [ "$?" = "0" ]; then
			if [ "$MasterIP" = "$SERVER_LOCALIP" ]; then
				maxctrl alter maxscale passive true
				exit 0
			else
				maxctrl alter maxscale passive false
				if ip addr | grep "scope global secondary" > /dev/null ; then
					# VIPを破棄したい。
					exit 9
				else
					exit 0
				fi
			fi
		else
			exit 4
		fi
	else
		echo Something is wrong
		exit 3
	fi
fi

_EOF
chmod +x $SACLOUDAPI_HOME/bin/is_running.sh

MAXSCALE_GUI_PREFIX=/maxscale-gui

if [ -f /usr/share/maxscale/gui/js/app~5a11b65b.0e8a9101 ]; then
sacloud_func_file_cleanup /usr/share/maxscale/gui/js/app~5a11b65b.0e8a9101.js
sed -i /usr/share/maxscale/gui/js/app~5a11b65b.0e8a9101.js \
	-e 's/,o.p="\/",/,o.p="\'$MAXSCALE_GUI_PREFIX'\/",/g' \
	-e "s/xios.get(['\"]/\0\\$MAXSCALE_GUI_PREFIX/g" \
	-e "s/xios.patch(['\"]/\0\\$MAXSCALE_GUI_PREFIX/g" \
	-e "s/xios.put(['\"]/\0\\$MAXSCALE_GUI_PREFIX/g" \
	-e "s/xios.post(['\"]/\0\\$MAXSCALE_GUI_PREFIX/g" \
	-e 's/"\/servers\//"\'$MAXSCALE_GUI_PREFIX'\/servers\//g' \
	-e "s/\\$MAXSCALE_GUI_PREFIX\\$MAXSCALE_GUI_PREFIX/\\$MAXSCALE_GUI_PREFIX/g"


	sacloud_func_file_cleanup /usr/share/maxscale/gui/js/app~06837ae4.1b590c19.js
	sed -i /usr/share/maxscale/gui/js/app~06837ae4.1b590c19.js -e 's/r.p+"/"\'$MAXSCALE_GUI_PREFIX'\//g'
else
    for jsfile in $(grep 'r.p+"' /usr/share/maxscale/gui/js/app~*.js | cut -d: -f1) ; do
		sacloud_func_file_cleanup $jsfile
		sed -i $jsfile \
			-e 's/r.p+"/"\'$MAXSCALE_GUI_PREFIX'\//g' \
			-e 's/,o.p="\/",/,o.p="\'$MAXSCALE_GUI_PREFIX'\/",/g' \
			-e "s/xios.get(['\"]/\0\\$MAXSCALE_GUI_PREFIX/g" \
			-e "s/xios.patch(['\"]/\0\\$MAXSCALE_GUI_PREFIX/g" \
			-e "s/xios.put(['\"]/\0\\$MAXSCALE_GUI_PREFIX/g" \
			-e "s/xios.post(['\"]/\0\\$MAXSCALE_GUI_PREFIX/g" \
			-e 's/"\/servers\//"\'$MAXSCALE_GUI_PREFIX'\/servers\//g' \
			-e "s/\\$MAXSCALE_GUI_PREFIX\\$MAXSCALE_GUI_PREFIX/\\$MAXSCALE_GUI_PREFIX/g"

    done

fi

sacloud_func_file_cleanup /usr/share/maxscale/gui/index.html
sed -i /usr/share/maxscale/gui/index.html \
	 -e 's/href=\/apple/href=\'$MAXSCALE_GUI_PREFIX'\/apple/g' \
	 -e 's/href=\/favicon/href=\'$MAXSCALE_GUI_PREFIX'\/favicon/g' \
	 -e 's/href=\/css/href=\'$MAXSCALE_GUI_PREFIX'\/css/g' \
	 -e 's/href=\/js/href=\'$MAXSCALE_GUI_PREFIX'\/js/g' \
	 -e 's/src=\/js/src=\'$MAXSCALE_GUI_PREFIX'\/js/g'


cat <<_EOF > /etc/httpd/conf.d/maxscale.conf

<Location $MAXSCALE_GUI_PREFIX/>
        AddDefaultCharset UTF-8
        # ベーシック認証(API Key)

        AuthUserFile /etc/httpd/.htpasswd
        AuthGroupFile /dev/null
        AuthName "Basic Auth"
        AuthType Basic
        Require valid-user
</Location>

ProxyRequests Off

ProxyPass        $MAXSCALE_GUI_PREFIX/ http://localhost:8989/
ProxyPassReverse $MAXSCALE_GUI_PREFIX/ https://

_EOF

systemctl start maxscale
until [ -f /var/lib/maxscale/passwd ]; do sleep 1; echo waiting /var/lib/maxscale/passwd; done

if jq -c '.[] | select (.name == "admin")' /var/lib/maxscale/passwd | grep '"admin"' ; then
	/usr/bin/maxctrl create user $SACLOUDB_DEFAULT_USER $SACLOUDB_DEFAULT_PASS --type=basic
	/usr/bin/maxctrl create user $SACLOUD_ADMIN_USER $SACLOUD_ADMIN_PASS --type=admin
	/usr/bin/maxctrl create user $SACLOUD_APIKEY_ACCESS_TOKEN $SACLOUD_APIKEY_ACCESS_TOKEN_SECRET --type=admin
	/usr/bin/maxctrl destroy user admin

	htpasswd -b /etc/httpd/.htpasswd $SACLOUD_ADMIN_USER $SACLOUD_ADMIN_PASS
	htpasswd -b /etc/httpd/.htpasswd-secure $SACLOUD_ADMIN_USER $SACLOUD_ADMIN_PASS
	htpasswd -b /etc/httpd/.htpasswd-user $SACLOUD_ADMIN_USER $SACLOUD_ADMIN_PASS
fi

apachectl restart

echo '## keepalived'

sacloud_func_file_cleanup /etc/keepalived/keepalived.conf

VRRP_STATE=backup
VRRP_PRIORITY=100
VRRP_INTERFACE=eth1
VRRP_IPADDRESS=$(jq -r .Interfaces[1].VirtualIPAddress $SACLOUDAPI_HOME/conf/interfaces.json)
VRRP_IPADDRESS_LEN=24
VRRP_ID=$(echo $VRRP_IPADDRESS | cut -d. -f4)

cat > /etc/keepalived/keepalived.conf <<_EOL
! Configuration File for keepalived

global_defs {
}

vrrp_script chk_myscript {
  script "$SACLOUDAPI_HOME/bin/is_running.sh"
  interval 5 # check every 5 seconds
  fall 2 # require 2 failures for KO
  rise 2 # require 2 successes for OK
}

vrrp_instance VI_1 {
    state $VRRP_STATE
    interface $VRRP_INTERFACE
    virtual_router_id $VRRP_ID
    priority $VRRP_PRIORITY
    advert_int 1
    virtual_ipaddress {
        $VRRP_IPADDRESS/$VRRP_IPADDRESS_LEN
    }
    track_script {
        chk_myscript
    }
}
_EOL

systemctl restart keepalived
systemctl is-active keepalived.service


chmod +x $SACLOUDAPI_HOME/bin/*.sh

# /var/www/html/index.html
cat <<_EOF > /var/www/html/index.html
<html>
<body>
<ul>
<li><a href="/phpmyadmin/">phpMyAdmin 5.1.0</a></li>
<li><a href="/maxscale-gui/">MariaDB MaxScale 2.5.13</a></li>
</ul>
</body>
</html>
_EOF