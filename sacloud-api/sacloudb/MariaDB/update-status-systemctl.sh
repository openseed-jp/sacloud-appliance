#!/bin/bash

. $(dirname $0)/.env

mkdir -p /tmp/.status
cat <<_EOF > /tmp/.status/systemctl.txt
[mariadb.service]
$(systemctl status mariadb.service)

[maxscale.service]
$(systemctl status maxscale.service)

_EOF
