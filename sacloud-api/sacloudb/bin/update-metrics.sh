#!/bin/bash

cd $(dirname $0)/..
. .env

set -e -o pipefail -o errexit
mkdir -p $SACLOUD_TMP/.metrics

TIME=$(TZ=Asia/Tokyo date '+%FT%R:00%:z')
TOTAL_DISK_SIZE_KIB=$(/usr/sbin/repquota -au | grep  -e $SACLOUDB_DATABASE_OWNER | awk '{print ($4+$5)/2}')
USED_DISK_SIZE_KIB=$(/usr/sbin/repquota -au | grep  -e $SACLOUDB_DATABASE_OWNER | awk '{print ($3)}')
TOTAL_MEMORY_SIZE_KIB=$(free | grep Mem: | awk '{print $2}')
USED_MEMORY_SIZE_KIB=$(free | grep Mem: | awk '{print $2-$4}')

cat <<_EOL | jq -c >> $SACLOUD_TMP/.metrics/cur.txt
{
    "$TIME": {
        "disk1TotalSizeKiB": $TOTAL_DISK_SIZE_KIB,
        "disk1UsedSizeKiB":  $USED_DISK_SIZE_KIB,
        "memoryTotalSizeKiB": $TOTAL_MEMORY_SIZE_KIB,
        "memoryUsedSizeKiB": $USED_MEMORY_SIZE_KIB
    }
}
_EOL

LEN=$(cat $SACLOUD_TMP/.metrics/cur.txt | wc -l)
if [ $LEN -ge 5 ];then
    FILE=$SACLOUD_TMP/.metrics/cur.txt.$(date +%s)
    mv $SACLOUD_TMP/.metrics/cur.txt $FILE
fi

FILES=$(ls -tr $SACLOUD_TMP/.metrics/cur.txt.* 2>/dev/null | head)
if [ $? = 0 ]; then
    sleep $(($(od -vAn --width=4 -tu4 -N4 </dev/urandom) % 60))
fi

FILES=$(ls -tr $SACLOUD_TMP/.metrics/cur.txt.* 2>/dev/null | head)
if [ $? = 0 ]; then
    for FILE in $(ls -tr $SACLOUD_TMP/.metrics/cur.txt.* | head); do
        METRICS=$(jq -s add $FILE | jq -c '{"Data":.}')
        if check_vrrp_primary ; then
            curl -sSLf --user "$SACLOUD_APIKEY_ACCESS_TOKEN:$SACLOUD_APIKEY_ACCESS_TOKEN_SECRET" \
                -X PUT $APIROOT/cloud/1.1/appliance/$APPLIANCE_ID/database/0/monitor \
                -d "$METRICS"
        fi

        curl -sSLf --user "$SACLOUD_APIKEY_ACCESS_TOKEN:$SACLOUD_APIKEY_ACCESS_TOKEN_SECRET" \
            -X PUT $APIROOT/cloud/1.1/appliance/$APPLIANCE_ID/database/$SERVER_NO/monitor \
            -d "$METRICS"

        if [ $? = 0 ]; then
            rm -f ${FILE}
        fi
    done
fi
