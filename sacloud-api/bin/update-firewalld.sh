#!/bin/bash

cd $(dirname $0)

. ../.env

set -x -e -o pipefail -o errexit

python << _EOF
import json, os
with open("/root/.sacloud-api/conf/firewalld.json", "r") as read_file:
  j = json.load(read_file)
  for zone in j.get("Firewalld").get("Zones"):
    lines = []
    zone_name = zone.get("Name")

    lines.append('<?xml version="1.0" encoding="utf-8"?>')
    lines.append('<zone>')
    lines.append('  <short>' + str(zone_name).capitalize() + '</short>')
    lines.append('  <description>' + str(zone_name).capitalize() + '</description>')
    for intfs in zone.get("Interfaces"):
      lines.append('  <interface name="' + intfs + '"/>')
    lines.append('  <service name="ssh"/>')


    for exp in zone.get("Expression"):
      source_address = ["0.0.0.0/0"] if exp.get("SourceNetwork") is None else exp.get("SourceNetwork")
      ports = exp.get("DestinationPort")
      action = "accept" if exp.get("Action") else "deny"
      proto = exp.get("Protocol")
      for addr in source_address:
          if(proto == "vrrp" or proto == "ip"):
            lines.append('  <rule family="ipv4"><source address="' + addr + '"/><protocol value="vrrp"/><' + action + '/></rule>');
          else:
            for port in ports:
              lines.append('  <rule family="ipv4"><source address="' + addr + '"/><port protocol="' + proto + '" port="' + port + '"/><' + action + '/></rule>');

    lines.append('</zone>')
    f = open('/etc/firewalld/zones/' + zone_name + '.xml', 'w')
    f.write('\n'.join(lines))
    f.close()
    print('/etc/firewalld/zones/' + zone_name + '.xml')
    print('\n'.join(lines))
_EOF

echo firewall-cmd --reload
firewall-cmd --reload

if [ -f $(dirname $0)/update-firewalld-ext.sh ]; then
  $(dirname $0)/update-firewalld-ext.sh
  firewall-cmd --reload
fi

systemctl restart firewalld
