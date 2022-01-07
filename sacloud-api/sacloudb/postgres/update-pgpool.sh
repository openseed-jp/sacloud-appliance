#!/bin/bash

. $(dirname $0)/.env

cd $SACLOUDB_MODULE_BASE/$SACLOUDB_DATABASE_NAME

set -x -e -o pipefail -o errexit

SERVER_PRIMARY_IP=$SERVER1_LOCALIP
SERVER_BACKUP_IP=$SERVER2_LOCALIP
SERVER_LOCAL_IP=$SERVER_LOCALIP
SERVER_PEER_IP=$SERVER_PEER_LOCALIP
SERVER_VIRTUAL_IP=$SERVER_VIP

if [ "$SERVER1_LOCALIP" == "$SERVER_LOCALIP" ]; then
    WD_PRIORITY=100
else
    WD_PRIORITY=50
fi

: =====================================================
:  modify /var/lib/pgsql/.ssh : $0:$LINENO
: =====================================================
if [ ! -d /var/lib/pgsql/.ssh ]; then
    mkdir -p /var/lib/pgsql/.ssh
    cp -f /root/.ssh/id_rsa_admin /var/lib/pgsql/.ssh/id_rsa_pgpool
    cp -f /root/.ssh/id_rsa_admin.pub /var/lib/pgsql/.ssh/id_rsa_pgpool.pub
    cp -f /root/.ssh/id_rsa_admin.pub /var/lib/pgsql/.ssh/authorized_keys
    chown -R postgres:postgres /var/lib/pgsql/.ssh
    chmod 600 /var/lib/pgsql/.ssh/*
    chmod 700 /var/lib/pgsql/.ssh
    ls -alt /var/lib/pgsql/.ssh/* | md5sum | cut -d' ' -f1 | passwd --stdin postgres
fi

: =====================================================
:  modify /etc/pgpool-II/pgpool.conf : $0:$LINENO
: =====================================================
sacloud_func_file_cleanup /etc/pgpool-II/pgpool.conf
cp /etc/pgpool-II/pgpool.conf.sample-stream /etc/pgpool-II/pgpool.conf


SERVER_NETWORK_LEN=$(jq -r .Interfaces[1].Switch.UserSubnet.NetworkMaskLen $SACLOUDAPI_HOME/conf/interfaces.json)

cat <<_EOL >> /etc/pgpool-II/pgpool.conf
# sacloud
listen_addresses '*'
logdir = '/var/log/pgpool-II-13'
socket_dir = '/var/run/pgpool'
pcp_socket_dir = '/var/run/pgpool'
allow_clear_text_frontend_auth = on

enable_pool_hba = 'off'
pool_passwd = 'pool_passwd'

if_up_cmd = '/usr/bin/sudo /sbin/ip addr add $SERVER_VIRTUAL_IP/$SERVER_NETWORK_LEN dev eth1'
if_down_cmd = '/usr/bin/sudo /sbin/ip addr del $SERVER_VIRTUAL_IP/$SERVER_NETWORK_LEN dev eth1'
arping_cmd = '/usr/bin/sudo /usr/sbin/arping -U $_IP_$ -w 1 -I eth1'

### watch dog
#use_watchdog = off
#trusted_servers = 'db-${APPLIANCE_ID}-01,db-${APPLIANCE_ID}-02'
#delegate_IP = '$SERVER_VIRTUAL_IP'

wd_lifecheck_method = 'query'
wd_lifecheck_user = '$SACLOUDB_ADMIN_USER'
wd_lifecheck_password = '$SACLOUDB_ADMIN_PASS'
wd_hostname = '$SERVER_LOCAL_IP'
wd_priority = $WD_PRIORITY
wd_port = 9000
wd_interval = 3
wd_ipc_socket_dir = '/var/run/pgpool'
other_pgpool_hostname0 = '$SERVER_PEER_IP'
other_pgpool_port0 = 9999
other_wd_port0 = 9000

enable_consensus_with_half_votes = on

# pgpool
health_check_user = '$SACLOUDB_ADMIN_USER'
health_check_password = '$SACLOUDB_ADMIN_PASS'
health_check_database = 'postgres'
health_check_period = 5
health_check_timeout = 0
recovery_user = '$SACLOUDB_ADMIN_USER'
sr_check_user = '$SACLOUDB_ADMIN_USER'

follow_master_command = '/etc/pgpool-II/follow_master.sh %d %h %p %D %m %H %M %P %r %R'
failover_command = '/etc/pgpool-II/failover.sh %d %h %p %D %m %H %M %P %r %R %N %S'
failback_command = '/etc/pgpool-II/failback.sh %d %h %p %D %m %H %M %P %r %R %N %S'
auto_failback = on
auto_failback_interval = 120

socket_dir = '/var/run/postgresql'
pcp_socket_dir = '/var/run/postgresql'
wd_ipc_socket_dir = '/var/run/postgresql'

backend_hostname0 = 'db-${APPLIANCE_ID}-01'
backend_application_name0 = 'db_${APPLIANCE_ID}_01'
backend_port0 = $PGPORT
backend_weight0 = 1
backend_data_directory0 = '$PGDATA'
backend_flag0 = 'ALLOW_TO_FAILOVER'

backend_hostname1 = 'db-${APPLIANCE_ID}-02'
backend_application_name1 = 'db_${APPLIANCE_ID}_02'
backend_port1 = $PGPORT
backend_weight1 = 1
backend_data_directory1 = '$PGDATA'
backend_flag1 = 'ALLOW_TO_FAILOVER'

ssl = on
ssl_key = '/etc/pki/tls/private/postgres.key'
ssl_cert = '/etc/pki/tls/certs/postgres.crt'


# num_init_children = 5


# /sacloud
_EOL

cp -f $SACLOUDB_MODULE_BASE/$SACLOUDB_DATABASE_NAME/pgpool-II/*.sh /etc/pgpool-II/.
sed -i /etc/pgpool-II/failover.sh \
    -e "s|^PGHOME=.*$|PGHOME=$PGHOME|" 
sed -i /etc/pgpool-II/follow_master.sh \
	-e "s|^PGHOME=.*$|PGHOME=$PGHOME|" \
	-e "s/^REPLUSER=.*/REPLUSER=$SACLOUDB_ADMIN_USER/" \
	-e "s/^PCP_USER=.*/PCP_USER=$SACLOUDB_ADMIN_USER/"
sed -i /etc/pgpool-II/failback.sh \
    -e "s|^PGHOME=.*$|PGHOME=$PGHOME|" 

touch /etc/pgpool-II/{failover.log,follow_master.log}
chmod 666 /etc/pgpool-II/{failover.log,follow_master.log}
chmod +x /etc/pgpool-II/*.sh

:
: =====================================================
:  modify .pgpass in HOME : $0:$LINENO
: =====================================================
cat <<_EOL > /root/.pcppass
#hostname:port:username:password
localhost:9898:$SACLOUDB_ADMIN_USER:$SACLOUDB_ADMIN_PASS
localhost:9898:$SACLOUDB_DEFAULT_USER:$SACLOUDB_DEFAULT_PASS
$SERVER_PRIMARY_IP:9898:$SACLOUDB_ADMIN_USER:$SACLOUDB_ADMIN_PASS
$SERVER_BACKUP_IP:9898:$SACLOUDB_ADMIN_USER:$SACLOUDB_ADMIN_PASS
db-$APPLIANCE_ID-01:9898:$SACLOUDB_ADMIN_USER:$SACLOUDB_ADMIN_PASS
db-$APPLIANCE_ID-02:9898:$SACLOUDB_ADMIN_USER:$SACLOUDB_ADMIN_PASS
_EOL
chmod 600 /root/.pcppass

#pg_md5 --md5auth --username=$SACLOUDB_ADMIN_USER "$SACLOUDB_ADMIN_PASS"
echo "$SACLOUDB_ADMIN_USER:$SACLOUDB_ADMIN_PASS" > /etc/pgpool-II/pool_passwd
chmod 600 /etc/pgpool-II/pool_passwd

usermod -aG postgres $SACLOUD_ADMIN_USER

# 暫定：アーカイブ作成時に変更予定
chown -R root:root /usr/pgpoolAdmin-4*
chown -R $SACLOUD_ADMIN_USER:$SACLOUD_ADMIN_USER /usr/pgpoolAdmin-4*/{templates_c,conf/pgmgt.conf.php} 

: =====================================================
:  modify pool_hba.conf : $0:$LINENO
: =====================================================
if [ -f /etc/pgpool-II/pool_hba.conf ]; then
    sacloud_func_file_cleanup /etc/pgpool-II/pool_hba.conf
    sed -e '/^# sacloud$/,/^# \/sacloud$/d' -i /etc/pgpool-II/pool_hba.conf
    cat <<_EOL >> /etc/pgpool-II/pool_hba.conf
# sacloud
hostssl  all         all         0.0.0.0/0          md5
#host    all         all         0.0.0.0/0          trust
#host    all         all         0.0.0.0/0          scram-sha-256
# /sacloud
_EOL
fi


#su - postgres <<_EOF 
#psql postgres -t -A \
#    -o /etc/pgpool-II/pool_passwd \
#    -c "select concat(usename, ':', passwd) from pg_shadow where passwd is not null;"
#_EOF
#chmod 644 /etc/pgpool-II/pool_passwd

chown -R postgres:postgres /etc/pgpool-II
chmod 644 /etc/pgpool-II/{pgpool.conf,pcp.conf}

cat <<_EOF > /etc/httpd/conf.d/pgpoolAdmin.conf

Alias /pgpoolAdmin /usr/pgpoolAdmin-4.1.0
Alias /pgpooladmin /usr/pgpoolAdmin-4.1.0

<Directory /usr/pgpoolAdmin-4.1.0/>
	# Apache 2.4
	Require all granted
</Directory>

_EOF

apachectl restart

sacloud_func_file_cleanup /etc/pgpool-II/pcp.conf
php -r "echo '"$SACLOUD_ADMIN_USER":'.md5('"$SACLOUD_ADMIN_PASS"'),PHP_EOL;" >> /etc/pgpool-II/pcp.conf
php -r "echo '"$SACLOUDB_DEFAULT_USER":'.md5('"$SACLOUDB_DEFAULT_PASS"'),PHP_EOL;" >> /etc/pgpool-II/pcp.conf


# pgpool からの参照が必要
cp -f  /root/.pcppass /var/lib/pgsql/.
chown -R postgres:postgres /var/lib/pgsql

# apache からの参照権限が必要
# /usr/pgpoolAdmin-4.1.0/conf にコピーしてもいいのかな
cp -f  /root/.pcppass /home/$SACLOUD_ADMIN_USER/.
chown $SACLOUD_ADMIN_USER:$SACLOUD_ADMIN_USER /home/$SACLOUD_ADMIN_USER/.pcppass 

echo '## keepalived'

sacloud_func_file_cleanup /etc/keepalived/keepalived.conf

VRRP_STATE=backup
VRRP_PRIORITY=100
VRRP_INTERFACE=eth1
VRRP_IPADDRESS=$(jq -r .Interfaces[1].VirtualIPAddress $SACLOUDAPI_HOME/conf/interfaces.json)
VRRP_IPADDRESS_LEN=$(jq -r .Interfaces[1].Switch.UserSubnet.NetworkMaskLen $SACLOUDAPI_HOME/conf/interfaces.json)
VRRP_ID=$(echo $VRRP_IPADDRESS | cut -d. -f4)

cat > /etc/keepalived/keepalived.conf <<_EOL
! Configuration File for keepalived

global_defs {
}

vrrp_script chk_myscript {
  script "$SACLOUDAPI_HOME/bin/vrrp_running.sh"
  interval 5 # check every 5 seconds
  fall 2 # require 2 failures for KO
  rise 2 # require 2 successes for OK
}

vrrp_instance VI_1 {
    state $VRRP_STATE
    interface $VRRP_INTERFACE
    virtual_router_id $VRRP_ID
    priority $VRRP_PRIORITY
    nopreempt
    advert_int 1
    virtual_ipaddress {
        $VRRP_IPADDRESS/$VRRP_IPADDRESS_LEN
    }
    track_script {
        chk_myscript
    }
    notify /root/.sacloud-api/bin/vrrp_notify.sh
}
_EOL

chmod +x $SACLOUDAPI_HOME/bin/*.sh


# /var/www/html/index.html
cat <<_EOF > /var/www/html/index.html
<html>
<body>
<ul>
<li>HostName: $(hostname)</li>
<li><a href="/pgadmin4/">pgAdmin 4 (v5.3)</a>(ID: ${SACLOUDB_DEFAULT_USER}@localhost, PW: [default password]</li>
<li><a href="/pgpooladmin/">pgpool Administration Tool Version 4.1.0</a></li>
</ul>
</body>
</html>
_EOF
