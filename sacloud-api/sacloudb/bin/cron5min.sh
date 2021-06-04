#!/bin/bash

HOME=/root
SCRIPT=/root/.sacloud-api/sacloudb/bin/cron5min.sh
CRONFILE=/var/spool/cron/root
if ! grep $SCRIPT /var/spool/cron/root >/dev/null ; then
    cat <<_EOL >> /var/spool/cron/root
*/5 * * * * $SCRIPT
_EOL
    chmod 600 $CRONFILE
    chown root:root $CRONFILE
    systemctl reload crond
fi

/root/.sacloud-api/sacloudb/bin/update-status-systemctl.sh