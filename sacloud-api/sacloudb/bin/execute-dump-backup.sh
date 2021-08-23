#!/bin/bash

cd $(dirname $0)/..
. .env

set -x -e -o pipefail -o errexit

$SACLOUDB_MODULE_BASE/$SACLOUDB_DATABASE_NAME/execute-dump-backup.sh $@

exit $?
