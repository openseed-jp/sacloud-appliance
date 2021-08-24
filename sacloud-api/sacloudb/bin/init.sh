#!/bin/bash

cd $(dirname $0)/..
. .env
set -x -e -o pipefail -o errexit


# TODO 暫定 開始
yum install -y nfs-utils quota autofs 
### s3fs
yum -y install fuse-devel openssl-devel libcurl-devel libxml2-devel
curl -SsL https://github.com/s3fs-fuse/s3fs-fuse/archive/refs/tags/v1.90.tar.gz | tar zxvf - -C /usr/local/src
cd /usr/local/src/s3fs-fuse-1.90
./autogen.sh && ./configure
make && make install && make clean

### autofs
systemctl enable autofs
cat <<_EOF > /etc/auto.master
#
# Sample auto.master file
#

#/misc   /etc/auto.misc
#/net    -hosts
#+dir:/etc/auto.master.d
#+auto.master
/mnt/sacloud /etc/auto.sacloud
_EOF
mkdir -p /mnt/sacloud
touch /etc/auto.sacloud
systemctl start autofs
# TODO 暫定 終了

cd $SACLOUDAPI_HOME
cat <<'_EOF' > $SACLOUDAPI_HOME/bin/update-firewalld-ext.sh
#!/bin/bash

# データベースのポートをローカル以外から接続できないようにする設定。現在は、制限なし。

exit 0
####################### 
. ../.env

for zone in internal ; do
    echo firewall-cmd --zone=$zone --list-rich-rules --permanent
    while read -a arr; do
    if [ "${arr[*]}" != "" ]; then
        for PORT in 3306 5432 ; do
            if echo "${arr[*]}" | grep -e ' port="'$PORT'"' >/dev/null 2>&1 ; then
                echo "firewall-cmd --zone=$zone --remove-rich-rule="${arr[*]}" --permanent"
                firewall-cmd --zone=$zone --remove-rich-rule="${arr[*]}" --permanent
            fi
        done
    fi
    done < <(echo "$(firewall-cmd --zone=$zone --list-rich-rules --permanent)")
done

for IPADDR in $SERVER1_LOCALIP $SERVER2_LOCALIP ; do
    for PORT in 3306 5432 ; do
        rule="rule family="ipv4" source address="$IPADDR/32" port port="$PORT" protocol="tcp" accept"
        firewall-cmd --zone=$zone --add-rich-rule="$rule" --permanent
        echo firewall-cmd --zone=$zone --add-rich-rule="$rule" --permanent
    done
done
_EOF

cat <<'__EOF' > $SACLOUDAPI_HOME/bin/update-interfaces-ext.sh
#!/bin/bash

cd $(dirname $0)

. ../.env

cat <<_EOF > /etc/hosts
# edit by $SACLOUDAPI_HOME/bin/update-interfaces-ext.sh

127.0.0.1   localhost

# phpmyadmin で、リモートIPの名前解決で利用
$SERVER_VIP db-$APPLIANCE_ID
$SERVER1_LOCALIP db-$APPLIANCE_ID-01
$SERVER2_LOCALIP db-$APPLIANCE_ID-02

_EOF

__EOF
chmod +x $SACLOUDAPI_HOME/bin/*-ext.sh
$SACLOUDAPI_HOME/bin/update-interfaces-ext.sh

# クオータ設定
if [ ! -f /aquota.user ]; then
    if ! grep usrjquota=aquota.user /etc/fstab >/dev/null ; then
        sed -i /etc/fstab -e 's|/ *ext4 *defaults *1 1|/                       ext4    defaults,usrjquota=aquota.user,jqfmt=vfsv0       1 1|g'
        reboot
    fi

    QUOTA_SIZE=$(jq ".Disks[0].SizeMB - 10240" $SACLOUDAPI_HOME/server.json)
    QUOTA_SIZE=$(jq ".Disks[1].SizeMB //$QUOTA_SIZE" $SACLOUDAPI_HOME/server.json)
    QUOTA_SIZE=$(expr $QUOTA_SIZE '*' 1000 / 1024)

    QUOTA_GRACE=$(expr 86400 '*' 3)

    quotacheck -amugv
    if [ "$SACLOUDB_DATABASE_NAME" = "MariaDB" ]; then
        setquota -u mysql $(expr $QUOTA_SIZE - 500)M $(expr $QUOTA_SIZE + 500)M 0 0 /
    fi
    if [ "$SACLOUDB_DATABASE_NAME" = "postgres" ]; then
        setquota -u postgres $(expr $QUOTA_SIZE - 500)M $(expr $QUOTA_SIZE + 500)M 0 0 /
    fi
    setquota -aut $QUOTA_GRACE $QUOTA_GRACE
    repquota -au | grep -e User -e mysql -e postgres
fi

if [ ! -f $SACLOUDB_MODULE_BASE/bin/init.done ]; then
    # Apache の実行ユーザを sacloud-admin に変更
    sed -i /etc/httpd/conf/httpd.conf \
        -e 's/^User apache/User sacloud-admin/g' \
        -e 's/^Group apache/Group sacloud-admin/g'

    # 自己署名ファイルの更新
    openssl req -x509 -sha256 -nodes -days 36500 -newkey rsa:2048 -subj /CN=localhost -keyout /etc/pki/tls/private/localhost.key -out /etc/pki/tls/certs/localhost.crt
    chmod 600 /etc/pki/tls/private/localhost.key /etc/pki/tls/certs/localhost.crt

    openssl req -x509 -sha256 -nodes -days 36500 -newkey rsa:2048 -subj /CN=localhost -keyout /etc/pki/tls/private/postgres.key -out /etc/pki/tls/certs/postgres.crt
    chmod 400 /etc/pki/tls/private/postgres.key /etc/pki/tls/certs/postgres.crt
    chown postgres:postgres /etc/pki/tls/private/postgres.key /etc/pki/tls/certs/postgres.crt

    openssl req -x509 -sha256 -nodes -days 36500 -newkey rsa:2048 -subj /CN=localhost -keyout /etc/pki/tls/private/mysql.key -out /etc/pki/tls/certs/mysql.crt
    chmod 440 /etc/pki/tls/private/mysql.key /etc/pki/tls/certs/mysql.crt
    chown maxscale:mysql /etc/pki/tls/private/mysql.key /etc/pki/tls/certs/mysql.crt

    if [ "$SACLOUDB_DATABASE_NAME" = "MariaDB" ]; then
        $SACLOUDB_MODULE_BASE/MariaDB/update-MariaDB.sh
        $SACLOUDB_MODULE_BASE/MariaDB/init-replication.sh
        $SACLOUDB_MODULE_BASE/MariaDB/update-maxscale.sh
    fi
    if [ "$SACLOUDB_DATABASE_NAME" = "postgres" ]; then
        $SACLOUDB_MODULE_BASE/postgres/update-postgres.sh
        $SACLOUDB_MODULE_BASE/postgres/init-replication.sh
        $SACLOUDB_MODULE_BASE/postgres/update-pgpool.sh
    fi

    # sshd の設定
    sed -e 's/^UsePAM no/UsePAM yes/g' -i /etc/ssh/sshd_config
    systemctl restart sshd

    touch $SACLOUDB_MODULE_BASE/bin/init.done
fi
