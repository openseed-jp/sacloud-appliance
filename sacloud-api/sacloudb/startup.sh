#!/bin/bash



SACLOUDB_MODULE_BASE=$(cd $(dirname $0); pwd)
cd $SACLOUDB_MODULE_BASE
. .env

if [ ! $(basename $0) = "startup.sh" ]; then
  /usr/bin/cp -f $SACLOUDB_MODULE_BASE/startup.sh $SACLOUDB_MODULE_BASE/startup.run.sh
  $SACLOUDB_MODULE_BASE/startup.run.sh
  exit $?
fi

set -x -e -o pipefail

# モジュールの更新
$SACLOUDAPI_HOME/bin/update-modules.sh

if [ $? = 0 ]; then
  $SACLOUDB_MODULE_BASE/bin/init.sh
fi

if [ $? = 0 ]; then
  $SACLOUDB_MODULE_BASE/bin/boot.sh
fi

(
sleep 10
TITLE="SETUP STATUS INFOMATION"

. /root/.sacloud-api/.env
DATA=$(
for file in $(ls /root/.sacloud-api/notes/*.log); do
  EXIT_STATUS=$(tail $file | sed  '/^$/d' | tail -n1)
  echo $(TZ=Asia/Tokyo date '+%FT%T%:z' -s "`stat -c  %x $file`") $(basename $file) $EXIT_STATUS
  if [ ! "$EXIT_STATUS" = "(exit code: 0)" ]; then
    TITLE="SETUP STATUS FATAL"
  fi
done
)

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
        "",
        "$(echo "$DATA" | tr "\n" "\t" | sed 's/\t/","/g')",
    ]
  }
}
_EOL
) > /dev/null 2>&1 &
