#! /bin/bash

IF=eth0
IP=192.168.180.12

if [ $EUID -ne 0 ]
   then sudo echo "Super User passwd, please:"
        if [ $? -ne 0 ]
          then  echo "Sorry, need su privilege!"
                exit 1
        fi
fi

echo "Restore lan..."
if [ -d /proc/sys/net/ipv4/conf/vlan0 ]; then
    sudo ifconfig vlan0 down
    sudo ifconfig ${IF} ${IP}
    sudo ip link del vlan0
fi
