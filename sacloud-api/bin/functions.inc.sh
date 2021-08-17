#!/bin/bash

function sacloud_func_file_cleanup () {
  FILE=$1
  if [ ! -f $FILE ]; then
    mkdir -p $(dirname $FILE)
    return 0
  fi
  if [ ! -f $FILE.org ]; then
    mv -f $FILE $FILE.org
  fi
  cp -f $FILE.org $FILE

}
function check_vrrp_primary () {
    ip addr | grep $SERVER_VIP > /dev/null 2>&1
    return $?
}