#!/bin/bash


mkdir -p /tmp/.status
cat <<_EOF > /tmp/.status/systemctl.txt
[pg_ctl status]
$(su - postgres -c sh -c "/usr/pgsql-13/bin/pg_ctl status")

[pgpool.service]
$(systemctl status pgpool.service)

_EOF
