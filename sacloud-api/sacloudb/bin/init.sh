#!/bin/bash

cd $(dirname $0)/..
. .env
set -x -e -o pipefail -o errexit

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
# edit by /root/.sacloud-api/bin/update-interfaces-ext.sh

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
    if ! type quotacheck ; then
        yum -y install quota
    fi
    if ! grep usrjquota=aquota.user /etc/fstab >/dev/null ; then
        sed -i /etc/fstab -e 's|/ *ext4 *defaults *1 1|/                       ext4    defaults,usrjquota=aquota.user,jqfmt=vfsv0       1 1|g'
        reboot
    fi

    QUOTA_SIZE=$(jq ".Disks[0].SizeMB - 10240" /root/.sacloud-api/server.json)
    QUOTA_SIZE=$(jq ".Disks[1].SizeMB //$QUOTA_SIZE" /root/.sacloud-api/server.json)
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

    # TODO: 自己署名ファイルの更新
    openssl req -x509 -sha256 -nodes -days 36500 -newkey rsa:2048 -subj /CN=localhost -keyout /etc/pki/tls/private/localhost.key -out /etc/pki/tls/certs/localhost.crt
    chmod 600 /etc/pki/tls/private/localhost.key /etc/pki/tls/certs/localhost.crt

    openssl req -x509 -sha256 -nodes -days 36500 -newkey rsa:2048 -subj /CN=localhost -keyout /etc/pki/tls/private/postgres.key -out /etc/pki/tls/certs/postgres.crt
    chmod 400 /etc/pki/tls/private/postgres.key /etc/pki/tls/certs/postgres.crt
    chown postgres:postgres /etc/pki/tls/private/postgres.key /etc/pki/tls/certs/postgres.crt

    openssl req -x509 -sha256 -nodes -days 36500 -newkey rsa:2048 -subj /CN=localhost -keyout /etc/pki/tls/private/mysql.key -out /etc/pki/tls/certs/mysql.crt
    chmod 440 /etc/pki/tls/private/mysql.key /etc/pki/tls/certs/mysql.crt
    chown macscale:mysql /etc/pki/tls/private/mysql.key /etc/pki/tls/certs/mysql.crt



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

    # TODO: （アーカイブ作成時に書くべき？）
    sed -e 's/^UsePAM no/UsePAM yes/g' -i /etc/ssh/sshd_config
    systemctl restart sshd

    # TODO: その他の設定（アーカイブ作成時に書くべき？）
    if ! which gotty >/dev/null ; then
        curl -SsL https://github.com/yudai/gotty/releases/download/v1.0.1/gotty_linux_amd64.tar.gz | tar zxvf - -C /usr/bin/
    fi

    touch $SACLOUDB_MODULE_BASE/bin/init.done
fi
