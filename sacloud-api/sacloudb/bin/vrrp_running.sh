#!/bin/bash

cd $(dirname $0)/.. && . .env

$SACLOUDB_MODULE_BASE/$SACLOUDB_DATABASE_NAME/vrrp_running.sh
