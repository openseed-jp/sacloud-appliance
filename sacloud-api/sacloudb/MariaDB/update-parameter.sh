#!/bin/bash

cd $(dirname $0) && . .env

VRRP_STATUS=$(cat /tmp/.vrrp_status.txt 2>/dev/null)
if [ ! "$VRRP_STATUS" = "MASTER" ]; then
    echo "is not master" >&2
    exit 1
fi

if [ ! -f /etc/my.cnf.d/zz_sacloudb.sql -o $(cat /etc/my.cnf.d/zz_sacloudb.sql| wc -l) = 0]; then
    exit 0
fi
cat /etc/my.cnf.d/zz_sacloudb.sql | mysql -h $SERVER_VIP -u $SACLOUDB_ADMIN_USER -p$SACLOUDB_ADMIN_PASS
