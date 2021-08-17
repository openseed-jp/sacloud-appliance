#!/bin/bash

cd $(dirname $0)
. .env

set -o pipefail
fileName="/tmp/.maxctrl_output.txt"

maxctrl list servers --tsv > $fileName.work
to_result=$?

mv -f $fileName.work $fileName
if [ $to_result -ge 1 ]; then
	echo Timed out or error, timeout returned $to_result
	#reboot
	exit 3
else
	echo maxctrl success, rval is $to_result
	echo Checking maxctrl output sanity
	grep1=$(grep $SERVER1_LOCALIP $fileName)
	grep2=$(grep $SERVER2_LOCALIP $fileName)

	if [ "$grep1" ] && [ "$grep2" ]; then
		echo All is fine
		MasterIP=$(grep -e 'Master, Running' -e 'Relay Master' $fileName | cut -f2)
		if [ "$?" = "0" ]; then
			if [ "$MasterIP" = "$SERVER_LOCALIP" ]; then
				maxctrl alter maxscale passive true
				exit 0
			else
				maxctrl alter maxscale passive false
				if ip addr | grep "scope global secondary" > /dev/null ; then
					# VIPを破棄したい。
					exit 9
				else
					exit 0
				fi
			fi
		else
			exit 4
		fi
	else
		echo Something is wrong
		exit 3
	fi
fi

