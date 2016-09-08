#! /bin/bash

# Note: My host use eth1 for network communication, the next line cause virtual host
# to enable eth1. Dont know why.
# PREFIX=`ifconfig eth0 | grep eth0 | sed 's/^eth0      Link encap:Ethernet  HWaddr //' | cut -d':' -f 1-3`
PREFIX=`ifconfig eth0 | grep eth0 | sed 's/^eth0      Link encap:Ethernet  HWaddr //' | cut -d':' -f 1-3`
F4=`od -An -N1 -x /dev/random | sed 's/^\ 00//'`
F5=`od -An -N1 -x /dev/random | sed 's/^\ 00//'`
F6=`od -An -N1 -x /dev/random | sed 's/^\ 00//'`
echo -n $PREFIX:${F4}:${F5}:${F6}
