#!/bin/bash


SACLOUDB_MODULE_BASE=$(cd $(dirname $0); pwd)

if [ ! -d $SACLOUDB_MODULE_BASE/html/sacloud-api/vendor ]; then
    cd $SACLOUDB_MODULE_BASE/html/sacloud-api/
    COMPOSER_ALLOW_SUPERUSER=1 composer update
fi
cd $SACLOUDB_MODULE_BASE

set -x -e -o pipefail -o errexit


$SACLOUDB_MODULE_BASE/bin/init.sh
$SACLOUDB_MODULE_BASE/bin/boot.sh

