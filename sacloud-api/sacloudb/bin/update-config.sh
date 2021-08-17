#!/bin/bash

## コンパネの反映ボタンからコールされる


cd $(dirname $0)/.. && . .env
. $SACLOUDB_MODULE_BASE/$SACLOUDB_DATABASE_NAME/.env

set -x -e -o pipefail -o errexit

$SACLOUDAPI_HOME/bin/update-config.sh
$SACLOUDAPI_HOME/sacloudb/bin/update-monitoring.sh --graceful
$SACLOUDAPI_HOME/sacloudb/$SACLOUDB_DATABASE_NAME/update-parameter.sh

