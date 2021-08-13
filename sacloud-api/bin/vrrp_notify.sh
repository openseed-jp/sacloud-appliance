#!/bin/bash

cd $(dirname $0)
. ../.env

$SACLOUDAPI_HOME/$SACLOUD_MODULE_NAME/bin/vrrp_notify.sh $@
