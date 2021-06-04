#!/bin/bash


SACLOUDB_MODULE_BASE=$(cd $(dirname $0); pwd)

set -x -e -o pipefail -o errexit


$SACLOUDB_MODULE_BASE/bin/init.sh
$SACLOUDB_MODULE_BASE/bin/boot.sh

