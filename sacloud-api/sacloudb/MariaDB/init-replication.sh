#!/bin/bash

. $(dirname $0)/.env

cd $SACLOUDB_MODULE_BASE/$SACLOUDB_DATABASE_NAME

set -x -e -o pipefail -o errexit

if [ "$SERVER_ID" = "$SERVER1_ID" ]; then
	# プライマリ
	$SACLOUDB_MODULE_BASE/$SACLOUDB_DATABASE_NAME/promote-primary.sh
else
	# セカンダリ
	$SACLOUDB_MODULE_BASE/$SACLOUDB_DATABASE_NAME/follow-primary.sh --force
fi
