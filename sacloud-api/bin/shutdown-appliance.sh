#!/bin/bash

cd $(dirname $0)

. ../.env

set -e -o pipefail -o errexit

curl -s --user "$SACLOUD_APIKEY_ACCESS_TOKEN:$SACLOUD_APIKEY_ACCESS_TOKEN_SECRET" \
     -X DELETE $APIROOT/cloud/1.1/appliance/$APPLIANCE_ID/power