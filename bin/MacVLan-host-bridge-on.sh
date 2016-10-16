#! /bin/bash

IF=eth0
GW=192.168.180.254
IP=192.168.180.12

if [ $EUID -ne 0 ]
   then sudo echo "Super User passwd, please:"
        if [ $? -ne 0 ]
          then  echo "Sorry, need su privilege!"
                exit 1
        fi
fi

MACaddr='50:e5:49:00:00:00'
sudo ip link add link ${IF} name vlan0 address ${MACaddr} type macvlan mode bridge
sleep 2
sudo ifconfig ${IF} 0.0.0.0
sudo ifconfig vlan0 ${IP} up
sudo route add default gw ${GW}
