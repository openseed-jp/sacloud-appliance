#!/bin/bash
# This script is run after failover_command to synchronize the Standby with the new Primary.
# First try pg_rewind. If pg_rewind failed, use pg_basebackup.

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

PGHOME=/usr/pgsql-13
ARCHIVEDIR=/var/lib/pgsql/archivedir
REPLUSER=repl
PCP_USER=pgpool
PGPOOL_PATH=/usr/bin
PCP_PORT=9898

logger -i -p local1.info follow_master.sh: start: Standby node ${FAILED_NODE_ID}

## Test passwrodless SSH
ssh -T -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null postgres@${NEW_MASTER_NODE_HOST} -i ~/.ssh/id_rsa_pgpool ls /tmp > /dev/null

if [ $? -ne 0 ]; then
    logger -i -p local1.info follow_master.sh: passwrodless SSH to postgres@${NEW_MASTER_NODE_HOST} failed. Please setup passwrodless SSH.
    exit 1
fi

## Get PostgreSQL major version
#PGVERSION=`${PGHOME}/bin/initdb -V | awk '{print $3}' | sed 's/\..*//' | sed 's/\([0-9]*\)[a-zA-Z].*/\1/'`

RECOVERYCONF=${FAILED_NODE_PGDATA}/postgresql.auto.conf

## Check the status of Standby
ssh -T -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
postgres@${FAILED_NODE_HOST} -i ~/.ssh/id_rsa_pgpool ${PGHOME}/bin/pg_ctl -w -D ${FAILED_NODE_PGDATA} status


## If Standby is running, synchronize it with the new Primary.
if [ $? -eq 0 ]; then

    logger -i -p local1.info follow_master.sh: pg_rewind for node $FAILED_NODE_ID

    # Create replication slot "${FAILED_NODE_SLOT}"
    ssh -T -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null postgres@${NEW_MASTER_NODE_HOST} -i ~/.ssh/id_rsa_pgpool "
        ${PGHOME}/bin/psql -p ${NEW_MASTER_NODE_PORT} -c \"SELECT pg_create_physical_replication_slot('${FAILED_NODE_SLOT}');\"
    "

    ssh -T -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null postgres@${FAILED_NODE_HOST} -i ~/.ssh/id_rsa_pgpool "

        set -o errexit

        ${PGHOME}/bin/pg_ctl -w -m f -D ${FAILED_NODE_PGDATA} stop

        ${PGHOME}/bin/pg_rewind -D ${FAILED_NODE_PGDATA} --source-server=\"user=${REPLUSER} host=${NEW_MASTER_NODE_HOST} port=${NEW_MASTER_NODE_PORT} dbname=postgres\" --write-recovery-conf

        cat > ${RECOVERYCONF} << EOT
primary_conninfo = 'host=${NEW_MASTER_NODE_HOST} port=${NEW_MASTER_NODE_PORT} user=${REPLUSER} application_name=${FAILED_NODE_SLOT} passfile=''/var/lib/pgsql/.pgpass'''
recovery_target_timeline = 'latest'
restore_command = 'scp ${NEW_MASTER_NODE_HOST}:${ARCHIVEDIR}/%f %p'
primary_slot_name = '${FAILED_NODE_SLOT}'
EOT

        touch ${FAILED_NODE_PGDATA}/standby.signal

        ${PGHOME}/bin/pg_ctl -l /dev/null -w -D ${FAILED_NODE_PGDATA} start

    "

    if [ $? -ne 0 ]; then
        logger -i -p local1.error follow_master.sh: end: pg_rewind failed. Try pg_basebackup.


        cat <<_EOL | ssh -T -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null postgres@${FAILED_NODE_HOST} -i ~/.ssh/id_rsa_pgpool
            set -o errexit

            # Execute pg_basebackup
            rm -rf ${FAILED_NODE_PGDATA}
            rm -rf ${ARCHIVEDIR}/*
            ${PGHOME}/bin/pg_basebackup -h ${NEW_MASTER_NODE_HOST} -U $REPLUSER -p ${NEW_MASTER_NODE_PORT} -D ${FAILED_NODE_PGDATA} -X stream \
                --write-recovery-conf --slot=${FAILED_NODE_SLOT}

            cat  << _EOF > ${FAILED_NODE_PGDATA}/conf.d/01_standby_names.conf
synchronous_standby_names = ''
synchronous_commit = on
_EOF
            sed -i ${FAILED_NODE_PGDATA}/postgresql.auto.conf -e "s/^primary_conninfo = 'user/primary_conninfo = 'application_name=''${FAILED_NODE_PGDATA}'' user/g"
_EOL

        if [ $? -ne 0 ]; then
            # drop replication slot
            ssh -T -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null postgres@${NEW_MASTER_NODE_HOST} -i ~/.ssh/id_rsa_pgpool \
                ${PGHOME}/bin/psql -p ${NEW_MASTER_NODE_PORT} -c "SELECT pg_drop_replication_slot('${FAILED_NODE_SLOT}')"

            logger -i -p local1.error follow_master.sh: end: pg_basebackup failed
            exit 1
        fi

        # start Standby node on ${FAILED_NODE_HOST}
        ssh -T -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                postgres@${FAILED_NODE_HOST} -i ~/.ssh/id_rsa_pgpool $PGHOME/bin/pg_ctl -l /dev/null -w -D ${FAILED_NODE_PGDATA} start

    fi

    # If start Standby successfully, attach this node
    if [ $? -eq 0 ]; then

        # Run pcp_attact_node to attach Standby node to Pgpool-II.
        ${PGPOOL_PATH}/pcp_attach_node -w -h localhost -U $PCP_USER -p ${PCP_PORT} -n ${FAILED_NODE_ID}

        if [ $? -ne 0 ]; then
                logger -i -p local1.error follow_master.sh: end: pcp_attach_node failed
                exit 1
        fi

    # If start Standby failed, drop replication slot "${FAILED_NODE_SLOT}"
    else

        ssh -T -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null postgres@${NEW_MASTER_NODE_HOST} -i ~/.ssh/id_rsa_pgpool \
            ${PGHOME}/bin/psql -p ${NEW_MASTER_NODE_PORT} -c "SELECT pg_drop_replication_slot('${FAILED_NODE_SLOT}')"

        logger -i -p local1.error follow_master.sh: end: follow master command failed
        exit 1
    fi

else
    logger -i -p local1.info follow_master.sh: failed_nod_id=${FAILED_NODE_ID} is not running. skipping follow master command
    exit 0
fi

logger -i -p local1.info follow_master.sh: end: follow master command complete
exit 0