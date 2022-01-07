#!/bin/bash

. $(dirname $0)/.env

cd $SACLOUDB_MODULE_BASE/$SACLOUDB_DATABASE_NAME

set -x -e -o pipefail -o errexit

if [ "$SERVER_ID" = "$SERVER1_ID" ]; then
	SERVER_PRIMARY_LOCALIP=$SERVER1_LOCALIP
	SERVER_PEER_LOCALIP=$SERVER2_LOCALIP
	SERVER_PEER_HOSTNAME=db-$APPLIANCE_ID-02
else
	SERVER_PRIMARY_LOCALIP=$SERVER2_LOCALIP
	SERVER_PEER_LOCALIP=$SERVER1_LOCALIP
	SERVER_PEER_HOSTNAME=db-$APPLIANCE_ID-01
fi


: postgresql の起動
su - postgres <<_EOL
if $PGHOME/bin/pg_ctl status; then
    $PGHOME/bin/pg_ctl reload -D $PGDATA
else
    $PGHOME/bin/pg_ctl start -D $PGDATA
fi
_EOL

wait_for_db_connect


exit 0

# 起動した後、次回用に
SLOT_NAME=$(hostname | tr - _)
PEER_APPLICATION_NAME=$(echo $SERVER_PEER_HOSTNAME | tr - _)




cat <<_EOF > $PGDATA/postgresql.auto.conf
# follow-primary.sh
# Do not edit this file manually!
# It will be overwritten by the ALTER SYSTEM command.
primary_conninfo = 'application_name=$SLOT_NAME user=$SACLOUD_ADMIN_USER passfile=/var/lib/pgsql/.pgpass channel_binding=prefer host=$SERVER_PEER_LOCALIP port=$PGPORT sslmode=prefer sslcompression=0 ssl_min_protocol_version=TLSv1.2 gssencmode=prefer krbsrvname=postgres target_session_attrs=any'
primary_slot_name = '$SLOT_NAME'
_EOF

cat  << _EOF >> $PGDATA/conf.d/01_standby_names.conf
synchronous_standby_names = ''
synchronous_commit = on
_EOF

# touch $PGDATA/standby.signal