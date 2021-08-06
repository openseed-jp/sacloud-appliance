#!/bin/bash

## コンパネの反映ボタンからコールされる

SACLOUDB_MODULE_BASE=$(cd $(dirname $0)/..; pwd)
cd $SACLOUDB_MODULE_BASE
. .env
. $SACLOUDB_MODULE_BASE/$SACLOUDB_DATABASE_NAME/.env

set -x -e -o pipefail -o errexit

if [ "$SACLOUDB_DATABASE_NAME" = "MariaDB" ]; then
    # TODO MariaDB 反映ボタン
    echo "TODO MariaDB 反映ボタン"
fi

if [ "$SACLOUDB_DATABASE_NAME" = "postgres" ]; then
    # TODO PostgreSQL 反映ボタン
    echo "TODO PostgreSQL 反映ボタン"
fi
