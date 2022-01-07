#!/bin/bash

# /root/.sacloud-api/server.json を元に、ネットワーク情報を更新します。
cd $(dirname $0)

# route の設定
GATEWAY0=$(jq -r .Interfaces[0].Switch.Subnet.DefaultRoute /root/.sacloud-api/conf/interfaces.json)
GATEWAY1=$(jq -r .Interfaces[1].Switch.UserSubnet.DefaultRoute /root/.sacloud-api/conf/interfaces.json)

cat <<_EOF > /etc/sysconfig/network-scripts/route-eth0
61.211.224.144/28 via $GATEWAY0 dev eth0
_EOF

cat <<_EOF > /etc/sysconfig/network-scripts/route-eth1
10.0.0.0/8 via $GATEWAY1 dev eth1
172.16.0.0/12 via $GATEWAY1 dev eth1
192.168.0.0/16 via $GATEWAY1 dev eth1
_EOF

# eth1 の 追加 route設定
BASE_ROUTE=$(cat /etc/sysconfig/network-scripts/route-eth1)
ASIS_ROUTE=$(ip r | grep "$GATEWAY1 dev eth1 $" | sed -e 's/ $//g')
TOBE_ROUTE=$(cat /root/.sacloud-api/status.json | jq -r .Appliance.Settings.DBConf.Common.SourceNetwork[] | sed -e 's/\/32//g' | xargs -I{} echo {} via $GATEWAY1 dev eth1)

echo "$TOBE_ROUTE" | xargs -I{} sh -c "ip route add {}" 2>/dev/null || true
cat <<_EOL | sort | uniq --unique | xargs -I{} sh -c "ip route del {}" 2>/dev/null || true
$ASIS_ROUTE
$TOBE_ROUTE
$TOBE_ROUTE
$BASE_ROUTE
$BASE_ROUTE
_EOL





