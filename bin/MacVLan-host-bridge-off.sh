#! /bin/bash

IF=brLAN
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
    sudo ifconfig ${IF} 192.168.180.3
    sudo ip link del vlan0
fi
