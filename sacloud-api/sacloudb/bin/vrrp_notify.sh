#!/bin/bash

ENDSTATE=$3
NAME=$2
TYPE=$1


cd $(dirname $0)/.. && . .env
set -e -o pipefail -o errexit

RUNAT=$(TZ=Asia/Tokyo date '+%FT%T%:z')
echo $RUNAT "Perform action for transition to ${ENDSTATE} state for VRRP ${TYPE} ${NAME}"  >> $SACLOUD_TMP/vrrp_notify
echo "${ENDSTATE}" > $SACLOUD_TMP/.vrrp_status.txt

case $ENDSTATE in
    "BACKUP")
        TITLE="Keepalived Status Change Information"
        ;;
    "FAULT")
        TITLE="Keepalived Status Change FATAL"
        ;;
    "MASTER")
        TITLE="Keepalived Status Change Information"
        ;;
    *)
        TITLE="[FATAL] Keepalived Status Change UNKNOWN"
        ;;
esac

cat <<_EOL | curl -s --user "$SACLOUD_APIKEY_ACCESS_TOKEN:$SACLOUD_APIKEY_ACCESS_TOKEN_SECRET" \
                        -X PUT $APIROOT/cloud/1.1/appliance/$APPLIANCE_ID/database/notify \
                        -d @-
{
  "Notify": {
    "Class": "Slack",
    "RunAt": "$RUNAT",
    "Title": "$TITLE",
    "Messages": [
        "HostName: $(hostname)",
        "RunAt: $RUNAT",
	    "",
        "*Perform action for transition to ${ENDSTATE}*"
    ]
  }
}
_EOL
