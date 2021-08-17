#!/bin/bash

cd $(dirname $0)

. ../.env

set -x -e -o pipefail -o errexit

##### 管理ユーザの作成
if [ ! -d /home/$SACLOUD_ADMIN_USER ]; then
	sed -i /etc/sudoers -e 's/^%wheel/# %wheel/g' -e 's/# \(%wheel.*NOPASSWD: ALL\)/\1/g'

	groupadd -g 501 $SACLOUD_ADMIN_USER
	useradd -g 501 -u 501 $SACLOUD_ADMIN_USER
	usermod -aG wheel $SACLOUD_ADMIN_USER
    mkdir -p /home/$SACLOUD_ADMIN_USER/.ssh
    chmod 710 /home/$SACLOUD_ADMIN_USER/.ssh

	cp -f /root/.ssh/authorized_keys /home/$SACLOUD_ADMIN_USER/.ssh/authorized_keys

    cat <<_EOF > /home/sacloud-admin/.ssh/config
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile=/dev/null
_EOF

    chmod 640 /home/sacloud-admin/.ssh/config
    chown -R $SACLOUD_ADMIN_USER:$SACLOUD_ADMIN_USER /home/$SACLOUD_ADMIN_USER

fi
echo "$SACLOUD_ADMIN_PASS" | passwd --stdin sacloud-admin
