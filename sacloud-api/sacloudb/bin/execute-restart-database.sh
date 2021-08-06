#!/bin/bash

## API からコールされる

SACLOUDB_MODULE_BASE=$(cd $(dirname $0)/..; pwd)
cd $SACLOUDB_MODULE_BASE
. .env
. $SACLOUDB_MODULE_BASE/$SACLOUDB_DATABASE_NAME/.env

set -x -e -o pipefail -o errexit

if [ "$SACLOUDB_DATABASE_NAME" = "MariaDB" ]; then
    systemctl restart mariadb
fi

if [ "$SACLOUDB_DATABASE_NAME" = "postgres" ]; then
    # TODO PostgreSQL のインスタンス再起動
    echo "TODO PostgreSQL のインスタンス再起動"
fi
