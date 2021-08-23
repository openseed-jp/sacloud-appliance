#!/bin/bash

. $(dirname $0)/.env

mkdir -p $SACLOUD_TMP/.status
cat <<_EOF > $SACLOUD_TMP/.status/systemctl.txt
[mariadb.service]
$(systemctl status mariadb.service)

[maxscale.service]
$(systemctl status maxscale.service)

_EOF
