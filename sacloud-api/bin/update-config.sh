#!/bin/bash

cd $(dirname $0)

. ../.env

set -e -o pipefail -o errexit

# ネットワークインターフェースのチェック
STATUS=$(curl -s -w "%{http_code}" -o /dev/null https://www.sakura.ad.jp/) || true
if [ "$STATUS" != "200" ]; then
        ifdown eth0; ifup eth0
fi

# API から、最新の状態を取得
# {"Exclude":["SettingsResponse"]}
EXCLUDE_SETTING_RESPONSE="%7B%22Exclude%22%3A%5B%22SettingsResponse%22%5D%2C%22_nonce%22%3A1619249437215%7D"
curl -s --user "$SACLOUD_APIKEY_ACCESS_TOKEN:$SACLOUD_APIKEY_ACCESS_TOKEN_SECRET" \
        -o /root/.sacloud-api/status.json.tmp \
        $APIROOT/cloud/1.1/appliance/$APPLIANCE_ID/status?$EXCLUDE_SETTING_RESPONSE

if jq .ID /root/.sacloud-api/status.json.tmp 2>&1 >/dev/null ; then
	 mv -f /root/.sacloud-api/status.json.tmp /root/.sacloud-api/status.json
fi

# 設定ファイルのディレクトリ
mkdir -p $SACLOUDAPI_HOME/conf

# テンポラリのディレクトリ
if [ "$SACLOUD_TMP" = "" ]; then
        SACLOUD_TMP=/tmp
else
        mkdir -p $SACLOUD_TMP
        chmod 777 $SACLOUD_TMP
fi

# update-interfaces.sh 用の設定ファイル
SERVER_VIP=$(jq -r .Appliance.Settings.Network.VirtualIPAddress /root/.sacloud-api/status.json)

INTERFACES_JQ_FILTER=".Appliance.Servers[] | select(.ID == \"$SERVER_ID\")"
INTERFACES_JQ_FILTER="$INTERFACES_JQ_FILTER | {\"Interfaces\": .Interfaces, \"Zone\": .Zone}"
jq "$INTERFACES_JQ_FILTER" $SACLOUDAPI_HOME/status.json | jq '.Interfaces[(.Interfaces|length)-1] |= .+ {"VirtualIPAddress": "'$SERVER_VIP'"}' > $SACLOUDAPI_HOME/conf/interfaces.json


# uddate-firewalld.sh 用の設定ファイル
jq '.Appliance.Servers[0].Interfaces[].PacketFilter'  /root/.sacloud-api/status.json | jq -s '{"Firewalld":{"Zones":.}}' > $SACLOUDAPI_HOME/conf/firewalld.json

. /root/.sacloud-api/.env
set | grep -e ^SACLOUD -e ^SERVER -e ^AP > /root/.sacloud-api/conf/env.cache


# 設定ファイルのディレクトリ
mkdir -p $SACLOUD_TMP/.status
cp -f /root/.sacloud-api/status.json  $SACLOUD_TMP/.status/appliance.json

# 