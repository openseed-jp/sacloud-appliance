#!/bin/bash

HOME=/root
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/root/bin

cd /root/.sacloud-api/sacloudb && . .env

$SACLOUDB_MODULE_BASE/$SACLOUDB_DATABASE_NAME/update-status-systemctl.sh