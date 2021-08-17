#!/bin/bash

rm -rf /tmp/sacloud-appliance
git clone -b feature/sacloudb https://github.com/openseed-jp/sacloud-appliance.git /tmp/sacloud-appliance
/usr/bin/cp -rf /tmp/sacloud-appliance/sacloud-api/{bin,sacloudb} /root/.sacloud-api/.
