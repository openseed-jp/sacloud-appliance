#!/bin/bash

. $(dirname $0)/.env

mkdir -p $SACLOUD_TMP/.status
cat <<_EOF > $SACLOUD_TMP/.status/systemctl.txt
[pg_ctl status]
$(su - postgres -c sh -c "/usr/pgsql-13/bin/pg_ctl status")

[pgpool.service]
$(systemctl status pgpool.service)

_EOF
