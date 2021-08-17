#!/bin/bash

# /root/.sacloud-api/server.json を元に、ネットワーク情報を更新します。
cd $(dirname $0)

. ../.env

set -x -e -o pipefail -o errexit

# centos 系
if ! type "python" > /dev/null 2>&1 ; then
	yum -y install python3
	alternatives --set python /usr/bin/python3
fi
	python << _EOF
import json, os
with open("/root/.sacloud-api/conf/interfaces.json", "r") as read_file:
	j = json.load(read_file)
	i = 0
	for intfs in j.get('Interfaces'):
		file="/etc/sysconfig/network-scripts/ifcfg-eth" + str(i)
		route="/etc/sysconfig/network-scripts/route-eth" + str(i)
		if(intfs.get("IPAddress")):
			ipaddr = intfs.get("IPAddress")
			subnet = intfs.get("Switch").get("Subnet");
		else:
			ipaddr = intfs.get("UserIPAddress")
			subnet = intfs.get("Switch").get("UserSubnet");
		if(ipaddr):
			prefix = subnet.get("NetworkMaskLen")
			gateway = subnet.get("DefaultRoute")
			dns = j.get("Zone").get("Region").get("NameServers")
			data = ["DEVICE=eth" + str(i)]
			data += ["BOOTPROTO=static", "ONBOOT=yes"]
			data += ["IPADDR=" + ipaddr]
			data += ["PREFIX=" + str(prefix)]
			if (i == 0):
				data += ["GATEWAY=" + gateway]
				data += ["DNS1=" + dns[0], "DNS2=" + dns[1]]
			else:
			  with open(route, mode='w') as fh:
			    fh.write((" via " + gateway + "\n").join(["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", ""]))

			# override network-scripts config
			with open(file, mode='w') as fh:
				fh.write('\n'.join(data))
				fh.write('\n')
			# debug
			print (file)
			for line in data:
				print(line)
			# interface down and up
			os.system("ifdown eth" + str(i))
			os.system("ifup eth" + str(i))
		i = i + 1
_EOF

if [ -f $(dirname $0)/update-interfaces-ext.sh ]; then
  $(dirname $0)/update-interfaces-ext.sh
fi
