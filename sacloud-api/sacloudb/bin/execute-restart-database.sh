#!/bin/bash

## API からコールされる

SACLOUDB_MODULE_BASE=$(cd $(dirname $0)/..; pwd)
cd $SACLOUDB_MODULE_BASE
. .env
. $SACLOUDB_MODULE_BASE/$SACLOUDB_DATABASE_NAME/.env

set -x -e -o pipefail -o errexit

VRRP_STATUS=$(cat /tmp/.vrrp_status.txt 2>/dev/null)
if [ ! "$VRRP_STATUS" = "MASTER" ]; then
    echo "is not master" >&2
    exit 1
fi

if [ "$SACLOUDB_DATABASE_NAME" = "MariaDB" ]; then
    if [ "$SERVER2_LOCALIP" = "$SERVER_LOCALIP" ]; then
        PEER_IDX=01
    else
        PEER_IDX=02
    fi
    # まず、冗長化 が維持されているか確認
    if ! ssh root@db-$APPLIANCE_ID-$PEER_IDX systemctl restart mariadb ; then
        exit 1
    fi

    sleep 10
    # 冗長化 が維持されているか確認

    if ! systemctl restart mariadb; then
        exit 1
    fi
    # 冗長化 が維持されているか確認
fi

if [ "$SACLOUDB_DATABASE_NAME" = "postgres" ]; then
    # TODO PostgreSQL のインスタンス再起動
    echo "TODO PostgreSQL のインスタンス再起動"
fi
