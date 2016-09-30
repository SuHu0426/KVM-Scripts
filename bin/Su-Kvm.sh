#! /bin/bash

SCRIPT=$0

function usage {
    echo "Usage: ${SCRIPT} start|stop conf"
    echo "Usage: ${SCRIPT} configure conf [#RootPartition]"
    echo "Usage: ${SCRIPT} genconf OS.img hostname VM-IP Bridge TAP"
    exit 1
}

function usage_configure {
    echo "Usage: ${SCRIPT} configure conf [#RootPartition]"
    exit 2
}

function usage_genconf {
    echo "Usage: ${SCRIPT} genconf OS.img hostname VM-IP Bridge TAP"
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

    for br in ${Bridge[*]}; do
        if [ ! -d /proc/sys/net/ipv4/conf/${br} ]; then
            echo "Network bridge ${br} does not exist, start it first."
            exit 2
        fi
    done
    
        case ${NETTYPE} in
            macvlan)
                for (( c=0; c<${#Bridge[*]}; c++ )); do
                    sudo ip link add link ${Bridge[$c]} name v${TAP[$c]} address ${MACAddress[$c]} type macvtap mode bridge
                    sleep 2
                    sudo ip link set dev v${TAP[$c]} up
                    sudo chmod 666 /dev/net/tun
                    sudo chmod 666 /dev/tap$(< /sys/class/net/v${TAP[$c]}/ifindex)
                done
            ;;
            ovs)
                sudo chmod 666 /dev/net/tun
                for (( c=0; c<${#Bridge[*]}; c++ )); do
                    sudo tunctl -u ${WHO} -t ${TAP[$c]}
                    sudo /sbin/ifconfig ${TAP[$c]} up
                    sudo ovs-vsctl add-port ${Bridge[$c]} ${TAP[$c]}
                done
                ;;
            *)
                sudo chmod 666 /dev/net/tun
                for (( c=0; c<${#Bridge[*]}; c++ )); do
                    sudo tunctl -u ${WHO} -t ${TAP[$c]}
                    sudo /sbin/ifconfig ${TAP[$c]} up
                    sudo ovs-vsctl add-port ${Bridge[$c]} ${TAP[$c]}
                done
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
    
    case ${NETTYPE} in
        macvlan)
            for tap in ${TAP[*]}; do
                if [ -d /proc/sys/net/ipv4/conf/v${tap} ]; then
                    sudo ip link set dev v${tap} down
                    sudo ip link delete v${tap}
                fi
            done
            ;;
        ovs)
            for (( c=0; c<${#TAP[*]}; c++ )); do
                if [ -d /proc/sys/net/ipv4/conf/${TAP[$c]} ]; then
                    sudo ovs-vsctl del-port ${Bridge[$c]} ${TAP[$c]}
                    sudo /sbin/ifconfig ${TAP[$c]} down
                    sudo tunctl -d ${TAP[$c]}
                fi
            done
            ;;
        *)
            for (( c=0; c<${#TAP[*]}; c++ )); do
                if [ -d /proc/sys/net/ipv4/conf/${TAP[$c]} ]; then
                    sudo ovs-vsctl del-port ${Bridge[$c]} ${TAP[$c]}
                    sudo /sbin/ifconfig ${TAP[$c]} down
                    sudo tunctl -d ${TAP[$c]}
                fi
            done
            ;;
    esac
} #end restore-lan

function start {

    # Pre start script
    if [ -n "${PRESTART}" ]; then
        echo "Executing pre-start script"
        if [ ! -f ${PRESTART} ]; then
            echo "${PRESTART} not exist!"
            echo "SKIP"
        else
            bash ${PRESTART}
        fi
    fi
    
    # Prepare networking
    start-lan
    
    echo "Starting VM: ${Hostname}..., mem=${MEM}"
    
    CMD=""
    case $Console in
        screen)
	    CMD="screen -S ${Hostname} -d -m "
            eval $CMD
            CMD="screen -r ${Hostname} -X stuff \$\""
	    CMD+="kvm -name ${Hostname} -localtime -enable-kvm "
	    CMD+="-curses "
	    ;;
        serial-screen)
            CMD="screen -S ${Hostname} -d -m "
            echo "$CMD"
            eval $CMD
            CMD="screen -r ${Hostname} -X stuff \$\""
	    CMD+="kvm -name ${Hostname} -localtime -enable-kvm "
	    CMD+="-serial stdio -nographic "
	    ;;
        serial-stdio)
	    CMD+="kvm -name ${Hostname} -localtime -enable-kvm "
	    CMD+="-serial stdio -nographic "
	    ;;
        *)
	    CMD+="kvm -name ${Hostname} -localtime -enable-kvm "
	    ;;
    esac

    if [ -n "${SMP}" ]; then
        CMD+="-smp ${SMP} "
    fi
    
    CMD+="-k en-us "
    CMD+="-m ${MEM} "
    CMD+="-monitor unix:${Sock},server,nowait "

    case ${NETTYPE} in
        macvlan)
            for (( c=0; c<${#TAP[*]}; c++ )); do
                fd=$(< /sys/class/net/v${TAP[$c]}/ifindex)
                CMD+="-net nic,vlan=0,netdev=${TAP[$c]},macaddr=${MACAddress[$c]},model=virtio "
                CMD+="-netdev tap,fd=${fd},id=${TAP[$c]},vhost=on ${fd}<>/dev/tap${fd} "
            done
            ;;
        ovs)
            for (( c=0; c<${#TAP[*]}; c++ )); do
                CMD+="-net nic,vlan=0,netdev=${TAP[$c]},macaddr=${MACAddress[$c]},model=virtio "
                CMD+="-netdev tap,id=${TAP[$c]},ifname=${TAP[$c]},script=no,vhost=on "
            done
            ;;
        *)
            for (( c=0; c<${#TAP[*]}; c++ )); do
                CMD+="-net nic,vlan=0,netdev=${TAP[$c]},macaddr=${MACAddress[$c]},model=virtio "
                CMD+="-netdev tap,id=${TAP[$c]},ifname=${TAP[$c]},script=no,vhost=on "
            done
            ;;
    esac
    
    # Hard Disks
    for img in ${IMG[*]}; do
        CMD+="-drive index=0,media=disk,if=virtio,file=${img} "
    done

    # Append Option Argument
    if [ -n "${OPTARG}" ]; then
        CMD+="${OPTARG} "
    fi

    case $Console in
        screen)
	    CMD+="\\n\""
	    ;;
        serial-screen)
            CMD+="\\n\""
	    ;;
        serial-stdio)
            CMD+="&"
	    ;;
        *)
            CMD+="&"
	    ;;
    esac

    # Execute
    echo "$CMD"
    eval $CMD

    # POST start script
    if [ -n "${POSTSTART}" ]; then
        echo "Executing post-start script"
        if [ ! -f ${POSTSTART} ]; then
            echo "${POSTSTART} not exist!"
            echo "SKIP"
        else
            bash ${POSTSTART}
        fi
    fi
    
} #end start

function stop {

    # PRE stop script
    if [ -n "${PRESTOP}" ]; then
        echo "Executing pre-stop script"
        if [ ! -f ${PRESTOP} ]; then
            echo "${PRESTOP} not exist!"
            echo "SKIP"
        else
            bash ${PRESTOP}
        fi
    fi

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

    ping -c 3 ${IPAddress[0]}
    if [ $? -eq 0 ]; then
        if [ -S ${Sock} ]; then
           echo "${Hostname} still alive, force quit!"
           echo "quit" | sudo socat - unix-connect:${Sock}
           echo ""
           rm ${Sock}
        fi
    else
        if [ -S ${Sock} ]; then
            rm ${Sock}
        fi
    fi

    restore-lan

    # POST stop script
    if [ -n "${POSTSTOP}" ]; then
        echo "Executing post-stop script"
        if [ ! -f ${POSTSTOP} ]; then
            echo "${POSTSTOP} not exist!"
            echo "SKIP"
        else
            bash ${POSTSTOP}
        fi
    fi
} #end stop

function configure {

    if [ $# == 3 ]; then
        PT=$3
    else
        PT=1
    fi

    CheckMountPoint

    echo "Configure VM..."

    img=$IMG[0]
    # We need to check the OS-img format for mounting and customize the OS
    Format=`qemu-img info ${img} | grep "file format" | sed 's/file format: //'`
    echo "I got ${img} format is: ${Format}"
    if [ ${Format} == "raw" ]; then
        Offset=`/sbin/fdisk -l ${img} | grep -F ${img}${PT} | tr -s ' ' | cut -d' ' -f 3`
        Offset=`expr ${Offset} '*' 512`
        sudo modprobe loop
        sudo mount -o loop,offset=${Offset} ${img} /mnt/tmp
    elif [ ${Format} == "qcow2" ] || [ ${Format} == "qed" ]; then
        sudo modprobe nbd max_part=16
        echo -n "Please wait nbd modile to be loaded."
        while [ ! -b /dev/nbd0 ]; do
	    echo -n "."
	    sleep 1
        done
        echo ""
        sudo qemu-nbd -c /dev/nbd0 ${img}
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
${IPAddress[0]}       ${Hostname}

# The following lines are desirable for IPv6 capable hosts
::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

cat <<EOF >interfaces
auto lo
iface lo inet loopback
EOF

for (( c=0; c<${#Bridge[*]}; c++ )); do
    cat <<EOF >>interfaces
auto eth${c}
iface eth${c} inet static
      address ${IPAddress[$c]}
      netmask ${Netmask[$c]}
      gateway ${Gateway}
EOF
done

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
    BR0="${4}"

    # We also need to test hostname, VM-IP, Ether-card are legal ones.
    TAP="tap${5}"
    SrcDir=`dirname $(pwd)`
    SockDir=`readlink -f  "../Sockets"`
    Config=`readlink -f "../conf.d/${Hostname}.conf"`

    CheckConfigExit ${Config}

    DeclAutoGen="# Don't Edit, File automatically generated by `basename ${SCRIPT}` script"

    # We need to get the Ip of the assigned ether card and its MAC address and get a
    # fake MAC address for our VM.
    HostIP=`/sbin/ifconfig ${BR0} | grep "Bcast" | sed 's/^[ \t]*inet addr://' | sed 's/[ \t]*Bcast:.*$//'`
    ip4="${HostIP##*.}" ; x="${HostIP%.*}"
    ip3="${x##*.}" ; x="${x%.*}"
    ip2="${x##*.}" ; x="${x%.*}"
    ip1="${x##*.}"
    Netmask=`/sbin/ifconfig ${BR0} | grep "Bcast" | sed 's/^[ \t]*.*Mask://'`
    Bcast=`/sbin/ifconfig ${BR0} | grep "Bcast" | tr -s ' ' | cut -d ' ' -f 4 | sed 's/^[ \t]*.*Bcast://'`
    let gw4="(${Bcast##*.}-1)" ; x="${Bcast%.*}"
    gw3="${x##*.}" ; x="${x%.*}"
    gw2="${x##*.}" ; x="${x%.*}"
    gw1="${x##*.}"
    Gateway=$gw1.$gw2.$gw3.$gw4
    PREFIX=`/sbin/ifconfig ${BR0} | grep -F HWaddr | sed 's/^[0-9]*.*Link.*HWaddr //' | cut -d':' -f 1-3`
    if [ -n $PREFIX ]; then
        PREFIX=`/sbin/ifconfig ${BR0} | grep -F ether | cut -d':' -f 1-3 | tr -s ' ' | sed s'/ ether //'`
    fi
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

# Declare Arrays
declare -a IMG
declare -a Bridge TAP IPAddress Netmask MACAddress 

Hostname=${Hostname}
WHO=`whoami`
MEM=512M
ROOT=1
BOOTABLEFLAG=1
Sock=${SockDir}/${Hostname}.sock
SMP=
# Add with -, ex: -usb -usbdevice tablet, -cdrom /video/ISOs/vyos-1.1.7-amd64.iso
OPTARG=""

# Avalable Console variable:
# screen, serial-screen, serial-stdio, and *=monitor
Console=screen

# Virtual Image
IMG=(${IMG} )

# Network setting
# [ovs | macvlan] future uml-sw vde-sw
NETTYPE=ovs
Bridge=(${BR0} )
TAP=(${TAP} )
IPAddress=(${VMIP} )
Netmask=(${Netmask} )
MACAddress=(${FakeMac} )
Gateway=${Gateway}

# Pre/Post Scripts
PRESTART=
POSTSTART=
PRESTOP=
POSTSTOP=
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
