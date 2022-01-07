#!/bin/bash

set -o xtrace
exec > >(logger -i -p local1.info) 2>&1

# Special values:
# 1)  %d = failed node id
# 2)  %h = failed node hostname
# 3)  %p = failed node port number
# 4)  %D = failed node database cluster path
# 5)  %m = new primary node id
# 6)  %H = new primary node hostname
# 7)  %M = old master node id
# 8)  %P = old primary node id
# 9)  %r = new primary port number
# 10) %R = new primary database cluster path
# 11) %N = old primary node hostname
# 12) %S = old primary node port number
# 13) %% = '%' character

FAILED_NODE_ID="$1"
FAILED_NODE_HOST="$2"
FAILED_NODE_SLOT="$(echo $FAILED_NODE_HOST | tr - _)"
FAILED_NODE_PORT="$3"
FAILED_NODE_PGDATA="$4"
NEW_MASTER_NODE_ID="$5"
NEW_MASTER_NODE_HOST="$6"
OLD_MASTER_NODE_ID="$7"
OLD_PRIMARY_NODE_ID="$8"
NEW_MASTER_NODE_PORT="$9"
NEW_MASTER_NODE_PGDATA="${10}"
OLD_PRIMARY_NODE_HOST="${11}"
OLD_PRIMARY_NODE_PORT="${12}"


PGHOME=/usr/pgsql-13

cat <<_EOL > /tmp/failback.log
-----------------------------------
$(date)
-- failback.sh
FAILED_NODE_ID="$1"
FAILED_NODE_HOST="$2"
FAILED_NODE_PORT="$3"
FAILED_NODE_PGDATA="$4"
NEW_MASTER_NODE_ID="$5"
NEW_MASTER_NODE_HOST="$6"
OLD_MASTER_NODE_ID="$7"
OLD_PRIMARY_NODE_ID="$8"
NEW_MASTER_NODE_PORT="$9"
NEW_MASTER_NODE_PGDATA="${10}"
OLD_PRIMARY_NODE_HOST="${11}"
OLD_PRIMARY_NODE_PORT="${12}"

_EOL


logger -i -p local1.info failback.sh: start: Standby node ${FAILED_NODE_ID}

$(dirname $0)/follow_master.sh $FAILED_NODE_ID $FAILED_NODE_HOST $FAILED_NODE_PORT $FAILED_NODE_PGDATA \
                                    $OLD_PRIMARY_NODE_ID $OLD_PRIMARY_NODE_HOST \
                                    -1 -1 \
                                    $NEW_MASTER_NODE_PORT $NEW_MASTER_NODE_PGDATA



if [ $? -ne 0 ]; then
    logger -i -p local1.info failback.sh: run follow_master.sh with error $?
    exit 1
fi

logger -i -p local1.info failback.sh: run follow_master.sh with success

exit 0