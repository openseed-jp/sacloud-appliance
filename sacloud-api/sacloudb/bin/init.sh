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

if [ ! -f $SACLOUDB_MODULE_BASE/bin/init.done ]; then

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

    touch $SACLOUDB_MODULE_BASE/bin/init.done
fi
