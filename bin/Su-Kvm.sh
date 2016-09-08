#! /bin/bash

SCRIPT=$0

function usage {
    echo "Usage: ${SCRIPT} [start|stop] conf"
    echo "Usage: ${SCRIPT} configure conf [#RootPartition]"
    echo "Usage: ${SCRIPT} genconf OS.img hostname VM-IP Bridge TAP-No"
    exit 1
}

function usage_configure {
    echo "Usage: ${SCRIPT} configure conf [#RootPartition]"
    exit 2
}

function usage_genconf {
    echo "Usage: ${SCRIPT} genconf OS.img hostname VM-IP Bridge TAP-No"
    exit 3
}

function filenotfound {
    echo "$2 not found!"
    exit 13
}

function alreadyrun {
    echo "Server is still running?"
    echo "Stop it, first. Abort."
    exit 14
}

function CheckMountPoint {
    if [ ! -d /mnt/tmp ]; then
        echo "Mount point /mnt/tmp does not exist, create it first."
        exit 15
    fi
}

function CheckBridge {
    if [ ! -d /proc/sys/net/ipv4/conf/$1 ]; then
        echo "Network bridge $1 does not exist, start it first."
        exit 16
    fi
}

function CheckConfigExit {
    if [ -f ${1} ]; then
        echo "‘${1}’ already exist! Please use another hostname or ‘rm ${1}’."
        exit 17
    fi
}

function start-lan {
    echo "start lan..."
    if [ $EUID -ne 0 ]; then
        sudo echo "Super User passwd, please:"
        if [ $? -ne 0 ]; then
            echo "Sorry, need root privilege!"
            exit 1
        fi
    fi

#    COUNTER=0
#    while [ $COUNTER -lt 10 ]; do
#        BR=BR$COUNTER
#        echo $BR
#        if [ ! -z $BR ]; then
#            break
#        fi
#        TAP=TAP$COUNTER
#        echo "start $TAP"
        FakeMac=FakeMac$COUNTER
        
        if [ ! -d /proc/sys/net/ipv4/conf/${BR0} ]; then
            echo "Network bridge ${BR} does not exist, start it first."
            exit 2
        fi

        case ${NETTYPE} in
            macvlan)
                sudo ip link add link ${BR0} name v${TAP0} address ${FakeMac0} type macvtap mode bridge
                sleep 2
                sudo ip link set dev v${TAP0} up
                sudo chmod 666 /dev/net/tun
                sudo chmod 666 /dev/tap$(< /sys/class/net/v${TAP0}/ifindex)
            ;;
            ovs)
                sudo chmod 666 /dev/net/tun
                sudo tunctl -u ${WHO} -t ${TAP0}
                sudo /sbin/ifconfig ${TAP0} up
                sudo ovs-vsctl add-port ${BR0} ${TAP0}
                ;;
            *)
                sudo chmod 666 /dev/net/tun
                sudo tunctl -u ${WHO} -t ${TAP0}
                sudo /sbin/ifconfig ${TAP0} up
                sudo ovs-vsctl add-port ${BR0} ${TAP0}
                ;;
        esac

#    done #end while
    # vhostOn.sh
    sudo modprobe vhost-net
    sudo chmod 666 /dev/vhost-net
} #end start-lan

function restore-lan {
    echo "Restore lan..."
    if [ $EUID -ne 0 ]; then
        sudo echo "Super User passwd, please:"
        if [ $? -ne 0 ]; then
            echo "Sorry, need root privilege!"
            exit 1
        fi
    fi
    
#    COUNTER=0
#    while [ $COUNTER -lt 10 ]; do
#        BR=BR$COUNTER
#        if [ ! -z $BR ]; then
#            break
#        fi
#        TAP=TAP$COUNTER

        case ${NETTYPE} in
            macvlan)
                if [ -d /proc/sys/net/ipv4/conf/v${TAP0} ]; then
                    sudo ip link set dev v${TAP0} down
                    sudo ip link delete v${TAP0}
                fi
            ;;
            ovs)
                if [ -d /proc/sys/net/ipv4/conf/${TAP0} ]; then
                    sudo ovs-vsctl del-port ${BR0} ${TAP0}
                    sudo /sbin/ifconfig ${TAP0} down
                    sudo tunctl -d ${TAP0}
                fi
                ;;
            *)
                if [ -d /proc/sys/net/ipv4/conf/${TAP0} ]; then
                    sudo ovs-vsctl del-port ${BR0} ${TAP0}
                    sudo /sbin/ifconfig ${TAP0} down
                    sudo tunctl -d ${TAP0}
                fi
                ;;
        esac
#    done #end while
} #end restore-lan

function start {
    # Prepare networking
    start-lan
    
    echo "Starting VM: ${Hostname}..., mem=${MEM}"

    CMD=""
    case $Console in
        screen)
	    CMD+="screen -S ${Hostname} -d -m "
	    CMD+="kvm -name ${Hostname} -localtime -enable-kvm "
	    CMD+="-curses "
	    ;;
        serial-screen)
	    CMD+="screen -S ${Hostname} -d -m "
	    CMD+="kvm -name ${Hostname} -localtime -enable-kvm "
	    CMD+="-nographic -serial stdio "
	    ;;
        serial-stdio)
	    CMD+="kvm -name ${Hostname} -localtime -enable-kvm "
	    CMD+="-nographic -serial stdio "
	    ;;
        *)
	    CMD+="kvm -name ${Hostname} -localtime -enable-kvm "
	    ;;
    esac

    if [ ! "x${SMP}" == "x" ]; then
        CMD+="-smp ${SMP} "
    fi
    
    CMD+="-k en-us "
    CMD+="-m ${MEM} "
    CMD+="-monitor unix:${Sock},server,nowait "
    # Nerwork interfaces
#    COUNTER=0
#    while [ $COUNTER -lt 10 ]; do
#        BR=BR$COUNTER
#        if [ ! -z $BR ]; then
#            break
#        fi
#        TAP=TAP$COUNTER
#        FakeMac=FakeMac$COUNTER

#        case ${NETTYPE} in
#            macvlan)
#                CMD+="-net nic,vlan=${COUNTER},netdev=${TAP},macaddr=${FakeMac},model=virtio "
#                CMD+="-netdev tap,fd=`expr $COUNTER + 1`,id=${TAP},vhost=on $COUNTER<>/dev/tap$(< /sys/class/net/v${TAP}/ifindex)"
#            ;;
#            ovs)
#                CMD+="-net nic,vlan=${COUNTER},netdev=${TAP},macaddr=${FakeMac},model=virtio "
#                CMD+="-netdev tap,id=${TAP},ifname=${TAP},script=no,vhost=on "
#                ;;
#            *)
#                CMD+="-net nic,vlan=${COUNTER},netdev=${TAP},macaddr=${FakeMac},model=virtio "
#                CMD+="-netdev tap,id=${TAP},ifname=${TAP},script=no,vhost=on "
#                ;;
#        esac
#        CMD+="-net nic,vlan=${COUNTER},netdev=${TAP},macaddr=${FakeMac},model=virtio "
#        CMD+="-netdev tap,id=${TAP},ifname=${TAP},script=no,vhost=on "
#    done #end while

    case ${NETTYPE} in
        macvlan)
            CMD+="-net nic,vlan=0,netdev=${TAP0},macaddr=${FakeMac0},model=virtio "
            CMD+="-netdev tap,fd=3,id=${TAP0},vhost=on 3<>/dev/tap$(< /sys/class/net/v${TAP0}/ifindex)"
            ;;
        ovs)
            CMD+="-net nic,vlan=0,netdev=${TAP0},macaddr=${FakeMac0},model=virtio "
            CMD+="-netdev tap,id=${TAP0},ifname=${TAP0},script=no,vhost=on "
            ;;
        *)
            CMD+="-net nic,vlan=0,netdev=${TAP0},macaddr=${FakeMac0},model=virtio "
            CMD+="-netdev tap,id=${TAP0},ifname=${TAP0},script=no,vhost=on "
            ;;
    esac
    
    # Hard Disks
    CMD+="-drive index=0,media=disk,if=virtio,file=${IMG} "
    if [ ! -z "${IMG1}" ]; then
        CMD+="-drive index=1,media=disk,if=virtio,file=${IMG1} "
    fi
    # Append Option Argument
    if [ ! -z "${OPTARG}" ]; then
        CMD+="${OPTARG} "
    fi
    
    CMD+="&"

    # Execute
    echo "$CMD"
    eval $CMD
} #end start

function stop {

    if [ $EUID -ne 0 ]; then
        sudo echo "Super User passwd, please:"
        if [ $? -ne 0 ]; then
            echo "Sorry, need root privilege!"
            exit 1
        fi
    fi

    if [ -S ${Sock} ]; then
        echo "system_powerdown" | sudo socat - unix-connect:${Sock}
        echo "Please wait 10 seconds."
        sleep 10
    else
        echo "Socket has been removed! resotre Lan only."
    fi

    ping -c 3 ${IP0}
    if [ $? -eq 0 ]; then
        echo "${Hostname} still alive, force shutdown!"
        echo "quit" | sudo socat - unix-connect:${Sock}
        echo ""
        rm ${Sock}
    else
        rm ${Sock}
    fi

    restore-lan
} #end stop

function configure {

    if [ $# == 3 ]; then
        PT=$3
    else
        PT=1
    fi

    CheckMountPoint

    echo "Configure VM..."

    # We need to check the OS-img format for mounting and customize the OS
    Format=`qemu-img info ${IMG} | grep "file format" | sed 's/file format: //'`
    echo "I got ${IMG} format is: ${Format}"
    if [ ${Format} == "raw" ]; then
        Offset=`/sbin/fdisk -l ${IMG} | grep ${IMG}${PT} | tr -s ' ' | cut -d' ' -f 3`
        Offset=`expr ${Offset} '*' 512`
        sudo modprobe loop
        sudo mount -o loop,offset=${Offset} ${IMG} /mnt/tmp
    elif [ ${Format} == "qcow2" ] || [ ${Format} == "qed" ]; then
        sudo modprobe nbd max_part=16
        echo -n "Please wait nbd modile to be loaded."
        while [ ! -b /dev/nbd0 ]; do
	    echo -n "."
	    sleep 1
        done
        echo ""
        sudo qemu-nbd -c /dev/nbd0 ${IMG}
        echo -n "Please wait image to be connected."
        while [ ! -b /dev/nbd0p${PT} ]; do
	    echo -n "."
            sleep 1
        done
        echo ""
        sudo mount /dev/nbd0p${PT} /mnt/tmp
    else
        echo "Not support this file format!"
        exit 21
    fi

    mount | grep /mnt/tmp
    if [ ! $? -eq 0 ]; then
        echo "Mount failed!"
        exit 22
    fi

echo "${Hostname}" >hostname
cat <<EOF >hosts
127.0.0.1        localhost
# Without the next line, "\$ hostname --fqdn" can't produce the correct hostname.
${IP0}       ${Hostname}

# The following lines are desirable for IPv6 capable hosts
::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

cat <<EOF >interfaces
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
      address ${IP0}
      netmask ${Netmask0}
      gateway ${Gateway}
EOF

sudo mv hostname /mnt/tmp/etc/hostname
sudo mv hosts /mnt/tmp/etc/hosts
sudo mv interfaces /mnt/tmp/etc/network
sudo cp /etc/resolv.conf /mnt/tmp/etc

#if [ ! -f /mnt/tmp/etc/ssh/ssh_config.orig ]; then
#    sudo mv /mnt/tmp/etc/ssh/ssh_config /mnt/tmp/etc/ssh/ssh_config.orig
#fi
#if [ ! -f /mnt/tmp/etc/ssh/sshd_config.orig ]; then
#    sudo mv /mnt/tmp/etc/ssh/sshd_config /mnt/tmp/etc/ssh/sshd_config.orig
#fi
#if [ ! -f /mnt/tmp/etc/apt/sources.list.orig ]; then
#    sudo mv /mnt/tmp/etc/apt/sources.list /mnt/tmp/etc/apt/sources.list.orig
#fi
#
#sudo cp ../DebianNetFiles/hosts.allow  /mnt/tmp/etc
#sudo cp ../DebianNetFiles/hosts.deny   /mnt/tmp/etc
#sudo cp ../DebianNetFiles/ssh_config   /mnt/tmp/etc/ssh
#sudo cp ../DebianNetFiles/sshd_config  /mnt/tmp/etc/ssh
#sudo cp ../DebianNetFiles/sources.list /mnt/tmp/etc/apt
sync; sync
sudo umount /mnt/tmp

if [ ${Format} == "qcow2" ]; then
    sudo qemu-nbd -d /dev/nbd0
    echo -n "Please wait image fully disconnected."
    while [ -b /dev/nbd0p${PT} ]; do
        echo -n "."
        sleep 1
    done
    echo ""
    sudo rmmod nbd
    echo -n "Please wait nbd modile to be removed."
    while [ -b /dev/nbd0 ]; do
        echo -n "."
        sleep 1
    done
    echo ""
fi

} #end configure

function genconf {

    CheckBridge ${4}

    # Argument name substitutiion
    IMG="${1}"
    Hostname="${2}"
    VMIP="${3}"
    BR="${4}"

    # We also need to test hostname, VM-IP, Ether-card are legal ones.
    TAP="tap${5}"
    SrcDir=`dirname $(pwd)`
    SockDir=`readlink -f  "../Sockets"`
    Config=`readlink -f "../conf.d/${Hostname}.conf"`

    CheckConfigExit ${Config}

    DeclAutoGen="# Don't Edit, File automatically generated by `basename ${SCRIPT}` script"

    # We need to get the Ip of the assigned ether card and its MAC address and get a
    # fake MAC address for our VM.
    HostIP=`/sbin/ifconfig ${BR} | grep "Bcast" | sed 's/^[ \t]*inet addr://' | sed 's/[ \t]*Bcast:.*$//'`
    ip4="${HostIP##*.}" ; x="${HostIP%.*}"
    ip3="${x##*.}" ; x="${x%.*}"
    ip2="${x##*.}" ; x="${x%.*}"
    ip1="${x##*.}"
    Netmask=`/sbin/ifconfig ${BR} | grep "Bcast" | sed 's/^[ \t]*.*Mask://'`
    Bcast=`/sbin/ifconfig ${BR} | grep "Bcast" | tr -s ' ' | cut -d ' ' -f 4 | sed 's/^[ \t]*.*Bcast://'`
    let gw4="(${Bcast##*.}-1)" ; x="${Bcast%.*}"
    gw3="${x##*.}" ; x="${x%.*}"
    gw2="${x##*.}" ; x="${x%.*}"
    gw1="${x##*.}"
    Gateway=$gw1.$gw2.$gw3.$gw4
    PREFIX=`/sbin/ifconfig ${BR} | grep "HWaddr" | sed 's/^br[0-9]*.*Link.*HWaddr //' | cut -d':' -f 1-3`
    F4=`od -An -N1 -x /dev/random | sed 's/^\ 00//'`
    F5=`od -An -N1 -x /dev/random | sed 's/^\ 00//'`
    F6=`od -An -N1 -x /dev/random | sed 's/^\ 00//'`
    FakeMac=$PREFIX:${F4}:${F5}:${F6}
    echo " I got current IP: ${HostIP}, FakeMac: ${FakeMac}"

    if [ ! -d ../conf.d ]; then
        echo "\"conf.d\" dir does not exist, create it first."
        mkdir ../conf.d
        echo "done."
    fi

    if [ ! -d ../Sockets ]; then
        echo "\"Sockets\" dir does not exist, create it first."
        mkdir ../Sockets
        echo "done."
    fi

    cat <<EOF >${Config}
# ${Hostname} Configure file

Hostname=${Hostname}
WHO=`whoami`
MEM=512M
IMG=${IMG}
ROOT=1
BOOTABLEFLAG=1
Sock=${SockDir}/${Hostname}.sock
SMP=
# Add with -, ex: -usb -usbdevice tablet
OPTARG=""

# Avalable Console variable:
# screen, serial-screen, serial-stdio, and *=monitor
Console=screen

# External Storage
IMG1=

# Network0 setting
# [ovs | macvlan] future uml-sw vde-sw
NETTYPE=ovs
BR0=${BR}
TAP0=${TAP}
IP0=${VMIP}
Netmask0=${Netmask}
Bcast0=${Bcast}
FakeMac0=${FakeMac}
Gateway=${Gateway}

# Network1 setting
BR1=
TAP1=
IP1=
Netmask1=
Bcast1=
FakeMac1=

EOF

    echo "Now you can configure VM or start VM via following commands"
#    echo "./Kvm-installOS ${Config} bootable.iso"
    echo "${SCRIPT} configure ${Config}"
    echo "${SCRIPT} start ${Config}"
    echo "Note: Please make sure you have been configure images before start VM."
    
} #end genconf


if [ $# -lt 1 ]; then
    usage
fi

case $1 in
    start)
        if [ $# != 2 ]; then
            usage
        fi
        if [ ! -f $2 ]; then
            filenotfound
        fi
        source "$2"

        if [ -S ${Sock} ]; then
            alreadyrun
        fi

        start
        ;;
    stop)
        if [ $# != 2 ]; then
            usage
        fi
        if [ ! -f $2 ]; then
            filenotfound
        fi
        source "$2"

        stop
        ;;
    configure)
        if [ ! $# == 2 -o $# == 3 ]; then
            usage_configure
        fi
        if [ ! -f $2 ]; then
            filenotfound
        fi
        source "$2"
        configure
        ;;
    genconf)
        if [ $# != 6 ]; then
            usage_genconf
        fi
        genconf ${2} ${3} ${4} ${5} ${6}
        ;;
    *)
        usage
        ;;
esac
