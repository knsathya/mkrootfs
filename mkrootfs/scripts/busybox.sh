#!/bin/bash

# setup env
out=$1
rm -fr $out

###########################################################
# create minimum rootfs
############################################################

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
	DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
	SOURCE="$(readlink "$SOURCE")"
	[[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

$DIR/minrootfs.sh $out

#############################################################
#setup etc folder
#############################################################
etc=$out/etc

#setup inittab
cat > "$etc"/inittab << 'EOF' &&
##sample inittab
# Each entry in the /etc/inittab file has the following fields:
# id:rstate:action:process

# Start rcS config script
::sysinit:/etc/init.d/rcS

# Start an "askfirst" shell on the console
::askfirst:-/bin/sh

# Start an "askfirst" shell on /dev/tty2-4
#tty2::askfirst:-/bin/sh
#tty3::askfirst:-/bin/sh
#tty4::askfirst:-/bin/sh

# /sbin/getty invocations for selected ttys
#tty4::respawn:/sbin/getty 38400 tty5
#tty5::respawn:/sbin/getty 38400 tty6

# Example of how to put a getty on a serial line (for a terminal)
#::respawn:/sbin/getty -L ttyS0 9600 vt100
#::respawn:/sbin/getty -L ttyS1 9600 vt100
#console::respawn:/sbin/getty -L console 0 vt100

# Stuff to do when restarting the init process
::restart:/sbin/init

# Stuff to do before rebooting
::ctrlaltdel:/sbin/reboot
::shutdown:/bin/umount -a -r
::shutdown:/sbin/swapoff -a
EOF

#setup hosts
cat > "$etc"/hosts << 'EOF' &&
127.0.0.1	localhost
127.0.1.1	busybox-x86_64
EOF

#setup interface
cat > "$etc"/network/interfaces << "EOF"
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
        address 192.168.1.150
        netmask 255.255.255.0
        gateway 192.168.1.1
EOF

#setup resolv.conf
cat > "$etc"/resolv.conf << "EOF"
nameserver 127.0.1.1
EOF

#setup module
cat > "$etc"/modules << 'EOF' &&
#load the static modules
EOF

#setup fstab
cat > "$etc"/fstab << 'EOF' &&
# /etc/fstab: static file system information.
#
# Use 'blkid' to print the universally unique identifier for a
# device; this may be used with UUID= as a more robust way to name devices
# that works even if disks are added and removed. See fstab(5).
#
# <file system> <mount point>   <type>  <options>       <dump>  <pass>

none            /proc           proc     defaults          0      2
none            /sys            sysfs    defaults          0      1
none            /dev            devtmpfs defaults          0      1
EOF

#setup init.d
cat > "$etc"/init.d/rcS << 'EOF' &&
#!/bin/sh
# Start all init scripts in /etc/init.d
# executing them in numerical order.
#
for i in /etc/init.d/S??* ;do

     # Ignore dangling symlinks (if any).
     [ ! -f "$i" ] && continue
     case "$i" in
	*.sh)
	    # Source shell script for speed.
	    (
		trap - INT QUIT TSTP
		set start
		. $i
	    )
	    ;;
	*)
	    # No sh extension, so fork subprocess.
	    sh $i start
	    ;;
    esac
done
EOF
chmod +x "$etc"/init.d/rcS

cat > "$etc"/init.d/S01default << 'EOF' &&
#!/bin/sh
#
# Default boot initalization
#

case "$1" in
  start)
 	echo "Mounting Filesystems..."
	/bin/mount -a
	echo "Setting hostname"
	/bin/hostname -F /etc/hostname
	;;
  stop)
	echo -n "Unmounting Filesystem..."
	/bin/umount -a
	;;
  *)
	echo "Usage: $0 {start|stop}"
	exit 1
esac

exit $?
EOF
chmod +x "$etc"/init.d/S01default

cat > "$etc"/init.d/S02kmod << 'EOF' &&
#!/bin/sh
#
# Load the kernel modules
# This script is based on Ubuntu rootfs
#

# Silently exit if the kernel does not support modules.
[ -f /proc/modules ] || exit 0
[ -x /sbin/modprobe  ] || exit 0

PATH='/sbin:/bin'

modules_files() {
  local add_etc_modules=true

  if [ "$add_etc_modules" ]; then
    echo /etc/modules
  fi
}

case "$1" in
  start)
 	echo "Loading local modules..."
	files=$(modules_files)
	if [ "$files" ] ; then
		grep -h '^[^#]' $files |
		while read module args; do 
			echo $module
			[ "$module" ] || continue
			if [ -n "$args" ] ;  then
				/sbin/modprobe "$module" "$args"
			else
				/sbin/modprobe "$module"
			fi
		done
	fi
	;;
  stop)
 	echo "Unloading local modules..."
	if [ "$files" ] ; then
		grep -h '^[^#]' $files |
		while read module args; do 
			[ "$module" ] || continue
			/sbin/rmmod "$module"
		done
	fi
	;;
  restart|reload)
	"$0" stop
	"$0" start
	;;
  *)
	echo "Usage: $0 {start|stop|restart}"
	exit 1
esac

exit $?
EOF
chmod +x "$etc"/init.d/S02kmod

cat > "$etc"/init.d/S03mdev << 'EOF' &&
#!/bin/sh

case "$1" in
  start)
	echo "Enabling mdev daemon"

	#enable mdev
	/bin/echo /sbin/mdev > /proc/sys/kernel/hotplug
	/sbin/mdev -s

	# mdev -s does not poke network interfaces or usb devices so we need to do it here.
	echo "Loading pci devices kernel modules"
	for i in /sys/class/pci_bus/0*/device/0*/uevent;do
		printf 'add' > "$i";
	done; unset i;

	echo "Loading network devices kernel modules"
	for i in /sys/class/net/*/uevent; do
		printf 'add' > "$i";
	done; unset i;

	echo "Loading usb devices kernel modules"
	for i in /sys/bus/usb/devices/*; do
		case "${i##*/}" in
			[0-9]*-[0-9]*)
				printf 'add' > "$i/uevent"
			;;
		esac
	done; unset i;

	# Load kernel modules, run twice.
	echo "Loading other kernel modules"
	find /sys -name 'modalias' -type f -exec cat '{}' + | sort -u | xargs /sbin/modprobe -b -a 2>/dev/null
	find /sys -name 'modalias' -type f -exec cat '{}' + | sort -u | xargs /sbin/modprobe -b -a 2>/dev/null
	;;
  *)
	echo "Usage: $0 {start}"
	exit 1
esac

exit $?
EOF
chmod +x "$etc"/init.d/S03mdev

cat > "$etc"/init.d/S04network << 'EOF' &&
#!/bin/sh
#
# Start the network....
#

case "$1" in
  start)
 	echo "Starting network..."
	/sbin/ifdown -a
	/sbin/ifup -a
	;;
  stop)
	echo -n "Stopping network..."
	/sbin/ifdown -a
	;;
  restart|reload)
	"$0" stop
	"$0" start
	;;
  *)
	echo "Usage: $0 {start|stop|restart}"
	exit 1
esac

exit $?
EOF
chmod +x "$etc"/init.d/S04network

#setup inputrc
cat > "$etc"/inputrc << 'EOF' &&
# /etc/inputrc - global inputrc for libreadline
# See readline(3readline) and `info readline' for more information.

# Be 8 bit clean.
set input-meta on
set output-meta on
set bell-style visible

# To allow the use of 8bit-characters like the german umlauts, comment out
# the line below. However this makes the meta key not work as a meta key,
# which is annoying to those which don't need to type in 8-bit characters.

# set convert-meta off

"\e0d": backward-word
"\e0c": forward-word
"\e[h": beginning-of-line
"\e[f": end-of-line
"\e[1~": beginning-of-line
"\e[4~": end-of-line
#"\e[5~": beginning-of-history
#"\e[6~": end-of-history
"\e[3~": delete-char
"\e[2~": quoted-insert

# Common standard keypad and cursor
# (codes courtsey Werner Fink, <werner@suse.de>)
#"\e[1~": history-search-backward
"\e[2~": yank
"\e[3~": delete-char
#"\e[4~": set-mark
"\e[5~": history-search-backward
"\e[6~": history-search-forward
# Normal keypad and cursor of xterm
"\e[F": end-of-line
"\e[H": beginning-of-line
# Application keypad and cursor of xterm
"\eOA": previous-history
"\eOC": forward-char
"\eOB": next-history
"\eOD": backward-char
"\eOF": end-of-line
"\eOH": beginning-of-line
EOF

#setup protocols
cat > "$etc"/protocols << 'EOF' &&
# /etc/protocols:
#
# Internet (IP) protocols
#
#	from: @(#)protocols	5.1 (Berkeley) 4/17/89
#
# Updated for NetBSD based on RFC 1340, Assigned Numbers (July 1992).

ip	0	IP		# internet protocol, pseudo protocol number
icmp	1	ICMP		# internet control message protocol
igmp	2	IGMP		# Internet Group Management
ggp	3	GGP		# gateway-gateway protocol
ipencap	4	IP-ENCAP	# IP encapsulated in IP (officially ``IP'')
st	5	ST		# ST datagram mode
tcp	6	TCP		# transmission control protocol
egp	8	EGP		# exterior gateway protocol
pup	12	PUP		# PARC universal packet protocol
udp	17	UDP		# user datagram protocol
hmp	20	HMP		# host monitoring protocol
xns-idp	22	XNS-IDP		# Xerox NS IDP
rdp	27	RDP		# "reliable datagram" protocol
iso-tp4	29	ISO-TP4		# ISO Transport Protocol class 4
xtp	36	XTP		# Xpress Tranfer Protocol
ddp	37	DDP		# Datagram Delivery Protocol
idpr-cmtp	39	IDPR-CMTP	# IDPR Control Message Transport
rspf	73	RSPF		#Radio Shortest Path First.
vmtp	81	VMTP		# Versatile Message Transport
ospf	89	OSPFIGP		# Open Shortest Path First IGP
ipip	94	IPIP		# Yet Another IP encapsulation
encap	98	ENCAP		# Yet Another IP encapsulation
EOF

#setup securetty
cat > "$etc"/securetty << 'EOF' &&
tty1
tty2
tty3
tty4
tty5
tty6
tty7
tty8
ttyS0
ttyS1
ttyS2
ttyS3
ttyAMA0
ttyAMA1
ttyAMA2
ttyAMA3
ttySAC0
ttySAC1
ttySAC2
ttySAC3
ttyUL0
ttyUL1
ttyUL2
ttyUL3
ttyPSC0
ttyPSC1
ttyPSC2
ttyPSC3
ttyCPM0
ttyCPM1
ttyCPM2
ttyCPM3
ttymxc0
ttymxc1
ttymxc2
ttyO0
ttyO1
ttyO2
ttyO3
ttyAM0
ttyAM1
ttyAM2
ttySC0
ttySC1
ttySC2
ttySC3
ttySC4
ttySC5
ttySC6
ttySC7
ttyGS0
EOF

#setup services
cat > "$etc"/services << 'EOF' &&
# /etc/services:
#
# Network services, Internet style
#
# Note that it is presently the policy of IANA to assign a single well-known
# port number for both TCP and UDP; hence, most entries here have two entries
# even if the protocol doesn't support UDP operations.
# Updated from RFC 1700, ``Assigned Numbers'' (October 1994).  Not all ports
# are included, only the more common ones.

tcpmux		1/tcp				# TCP port service multiplexer
echo		7/tcp
echo		7/udp
discard		9/tcp		sink null
discard		9/udp		sink null
systat		11/tcp		users
daytime		13/tcp
daytime		13/udp
netstat		15/tcp
qotd		17/tcp		quote
msp		18/tcp				# message send protocol
msp		18/udp				# message send protocol
chargen		19/tcp		ttytst source
chargen		19/udp		ttytst source
ftp-data	20/tcp
ftp		21/tcp
fsp		21/udp		fspd
ssh		22/tcp				# SSH Remote Login Protocol
ssh		22/udp				# SSH Remote Login Protocol
telnet		23/tcp
# 24 - private
smtp		25/tcp		mail
# 26 - unassigned
time		37/tcp		timserver
time		37/udp		timserver
rlp		39/udp		resource	# resource location
nameserver	42/tcp		name		# IEN 116
whois		43/tcp		nicname
re-mail-ck	50/tcp				# Remote Mail Checking Protocol
re-mail-ck	50/udp				# Remote Mail Checking Protocol
domain		53/tcp		nameserver	# name-domain server
domain		53/udp		nameserver
mtp		57/tcp				# deprecated
bootps		67/tcp				# BOOTP server
bootps		67/udp
bootpc		68/tcp				# BOOTP client
bootpc		68/udp
tftp		69/udp
gopher		70/tcp				# Internet Gopher
gopher		70/udp
rje		77/tcp		netrjs
finger		79/tcp
www		80/tcp		http		# WorldWideWeb HTTP
www		80/udp				# HyperText Transfer Protocol
link		87/tcp		ttylink
kerberos	88/tcp		kerberos5 krb5	# Kerberos v5
kerberos	88/udp		kerberos5 krb5	# Kerberos v5
supdup		95/tcp
# 100 - reserved
hostnames	101/tcp		hostname	# usually from sri-nic
iso-tsap	102/tcp		tsap		# part of ISODE.
csnet-ns	105/tcp		cso-ns		# also used by CSO name server
csnet-ns	105/udp		cso-ns
# unfortunately the poppassd (Eudora) uses a port which has already
# been assigned to a different service. We list the poppassd as an
# alias here. This should work for programs asking for this service.
# (due to a bug in inetd the 3com-tsmux line is disabled)
#3com-tsmux	106/tcp		poppassd
#3com-tsmux	106/udp		poppassd
rtelnet		107/tcp				# Remote Telnet
rtelnet		107/udp
pop-2		109/tcp		postoffice	# POP version 2
pop-2		109/udp
pop-3		110/tcp				# POP version 3
pop-3		110/udp
sunrpc		111/tcp		portmapper	# RPC 4.0 portmapper TCP
sunrpc		111/udp		portmapper	# RPC 4.0 portmapper UDP
auth		113/tcp		authentication tap ident
sftp		115/tcp
uucp-path	117/tcp
nntp		119/tcp		readnews untp	# USENET News Transfer Protocol
ntp		123/tcp
ntp		123/udp				# Network Time Protocol
netbios-ns	137/tcp				# NETBIOS Name Service
netbios-ns	137/udp
netbios-dgm	138/tcp				# NETBIOS Datagram Service
netbios-dgm	138/udp
netbios-ssn	139/tcp				# NETBIOS session service
netbios-ssn	139/udp
imap2		143/tcp				# Interim Mail Access Proto v2
imap2		143/udp
snmp		161/udp				# Simple Net Mgmt Proto
snmp-trap	162/udp		snmptrap	# Traps for SNMP
cmip-man	163/tcp				# ISO mgmt over IP (CMOT)
cmip-man	163/udp
cmip-agent	164/tcp
cmip-agent	164/udp
xdmcp		177/tcp				# X Display Mgr. Control Proto
xdmcp		177/udp
nextstep	178/tcp		NeXTStep NextStep	# NeXTStep window
nextstep	178/udp		NeXTStep NextStep	# server
bgp		179/tcp				# Border Gateway Proto.
bgp		179/udp
prospero	191/tcp				# Cliff Neuman's Prospero
prospero	191/udp
irc		194/tcp				# Internet Relay Chat
irc		194/udp
smux		199/tcp				# SNMP Unix Multiplexer
smux		199/udp
at-rtmp		201/tcp				# AppleTalk routing
at-rtmp		201/udp
at-nbp		202/tcp				# AppleTalk name binding
at-nbp		202/udp
at-echo		204/tcp				# AppleTalk echo
at-echo		204/udp
at-zis		206/tcp				# AppleTalk zone information
at-zis		206/udp
qmtp		209/tcp				# The Quick Mail Transfer Protocol
qmtp		209/udp				# The Quick Mail Transfer Protocol
z3950		210/tcp		wais		# NISO Z39.50 database
z3950		210/udp		wais
ipx		213/tcp				# IPX
ipx		213/udp
imap3		220/tcp				# Interactive Mail Access
imap3		220/udp				# Protocol v3
ulistserv	372/tcp				# UNIX Listserv
ulistserv	372/udp
https		443/tcp				# MCom
https		443/udp				# MCom
snpp		444/tcp				# Simple Network Paging Protocol
snpp		444/udp				# Simple Network Paging Protocol
saft		487/tcp				# Simple Asynchronous File Transfer
saft		487/udp				# Simple Asynchronous File Transfer
npmp-local	610/tcp		dqs313_qmaster	# npmp-local / DQS
npmp-local	610/udp		dqs313_qmaster	# npmp-local / DQS
npmp-gui	611/tcp		dqs313_execd	# npmp-gui / DQS
npmp-gui	611/udp		dqs313_execd	# npmp-gui / DQS
hmmp-ind	612/tcp		dqs313_intercell# HMMP Indication / DQS
hmmp-ind	612/udp		dqs313_intercell# HMMP Indication / DQS
#
# UNIX specific services
#
exec		512/tcp
biff		512/udp		comsat
login		513/tcp
who		513/udp		whod
shell		514/tcp		cmd		# no passwords used
syslog		514/udp
printer		515/tcp		spooler		# line printer spooler
talk		517/udp
ntalk		518/udp
route		520/udp		router routed	# RIP
timed		525/udp		timeserver
tempo		526/tcp		newdate
courier		530/tcp		rpc
conference	531/tcp		chat
netnews		532/tcp		readnews
netwall		533/udp				# -for emergency broadcasts
uucp		540/tcp		uucpd		# uucp daemon
afpovertcp	548/tcp				# AFP over TCP
afpovertcp	548/udp				# AFP over TCP
remotefs	556/tcp		rfs_server rfs	# Brunhoff remote filesystem
klogin		543/tcp				# Kerberized `rlogin' (v5)
kshell		544/tcp		krcmd		# Kerberized `rsh' (v5)
kerberos-adm	749/tcp				# Kerberos `kadmin' (v5)
#
webster		765/tcp				# Network dictionary
webster		765/udp
#
# From ``Assigned Numbers'':
#
#> The Registered Ports are not controlled by the IANA and on most systems
#> can be used by ordinary user processes or programs executed by ordinary
#> users.
#
#> Ports are used in the TCP [45,106] to name the ends of logical
#> connections which carry long term conversations.  For the purpose of
#> providing services to unknown callers, a service contact port is
#> defined.  This list specifies the port used by the server process as its
#> contact port.  While the IANA can not control uses of these ports it
#> does register or list uses of these ports as a convienence to the
#> community.
#
nfsdstatus	1110/tcp
nfsd-keepalive	1110/udp

ingreslock	1524/tcp
ingreslock	1524/udp
prospero-np	1525/tcp			# Prospero non-privileged
prospero-np	1525/udp
datametrics	1645/tcp	old-radius	# datametrics / old radius entry
datametrics	1645/udp	old-radius	# datametrics / old radius entry
sa-msg-port	1646/tcp	old-radacct	# sa-msg-port / old radacct entry
sa-msg-port	1646/udp	old-radacct	# sa-msg-port / old radacct entry
radius		1812/tcp			# Radius
radius		1812/udp			# Radius
radacct		1813/tcp			# Radius Accounting
radacct		1813/udp			# Radius Accounting
nfsd		2049/tcp	nfs
nfsd		2049/udp	nfs
cvspserver	2401/tcp			# CVS client/server operations
cvspserver	2401/udp			# CVS client/server operations
mysql		3306/tcp			# MySQL
mysql		3306/udp			# MySQL
rfe		5002/tcp			# Radio Free Ethernet
rfe		5002/udp			# Actually uses UDP only
cfengine	5308/tcp			# CFengine
cfengine	5308/udp			# CFengine
bbs		7000/tcp			# BBS service
#
#
# Kerberos (Project Athena/MIT) services
# Note that these are for Kerberos v4, and are unofficial.  Sites running
# v4 should uncomment these and comment out the v5 entries above.
#
kerberos4	750/udp		kerberos-iv kdc	# Kerberos (server) udp
kerberos4	750/tcp		kerberos-iv kdc	# Kerberos (server) tcp
kerberos_master	751/udp				# Kerberos authentication
kerberos_master	751/tcp				# Kerberos authentication
passwd_server	752/udp				# Kerberos passwd server
krb_prop	754/tcp				# Kerberos slave propagation
krbupdate	760/tcp		kreg		# Kerberos registration
kpasswd		761/tcp		kpwd		# Kerberos "passwd"
kpop		1109/tcp			# Pop with Kerberos
knetd		2053/tcp			# Kerberos de-multiplexor
zephyr-srv	2102/udp			# Zephyr server
zephyr-clt	2103/udp			# Zephyr serv-hm connection
zephyr-hm	2104/udp			# Zephyr hostmanager
eklogin		2105/tcp			# Kerberos encrypted rlogin
#
# Unofficial but necessary (for NetBSD) services
#
supfilesrv	871/tcp				# SUP server
supfiledbg	1127/tcp			# SUP debugging
#
# Datagram Delivery Protocol services
#
rtmp		1/ddp				# Routing Table Maintenance Protocol
nbp		2/ddp				# Name Binding Protocol
echo		4/ddp				# AppleTalk Echo Protocol
zip		6/ddp				# Zone Information Protocol
#
# Services added for the Debian GNU/Linux distribution
poppassd	106/tcp				# Eudora
poppassd	106/udp				# Eudora
mailq		174/tcp				# Mailer transport queue for Zmailer
mailq		174/tcp				# Mailer transport queue for Zmailer
omirr		808/tcp		omirrd		# online mirror
omirr		808/udp		omirrd		# online mirror
rmtcfg		1236/tcp			# Gracilis Packeten remote config server
xtel		1313/tcp			# french minitel
coda_opcons	1355/udp			# Coda opcons            (Coda fs)
coda_venus	1363/udp			# Coda venus             (Coda fs)
coda_auth	1357/udp			# Coda auth              (Coda fs)
coda_udpsrv	1359/udp			# Coda udpsrv            (Coda fs)
coda_filesrv	1361/udp			# Coda filesrv           (Coda fs)
codacon		1423/tcp	venus.cmu	# Coda Console           (Coda fs)
coda_aux1	1431/tcp			# coda auxiliary service (Coda fs)
coda_aux1	1431/udp			# coda auxiliary service (Coda fs)
coda_aux2	1433/tcp			# coda auxiliary service (Coda fs)
coda_aux2	1433/udp			# coda auxiliary service (Coda fs)
coda_aux3	1435/tcp			# coda auxiliary service (Coda fs)
coda_aux3	1435/udp			# coda auxiliary service (Coda fs)
cfinger		2003/tcp			# GNU Finger
afbackup	2988/tcp			# Afbackup system
afbackup	2988/udp			# Afbackup system
icp		3130/tcp			# Internet Cache Protocol (Squid)
icp		3130/udp			# Internet Cache Protocol (Squid)
postgres	5432/tcp			# POSTGRES
postgres	5432/udp			# POSTGRES
fax		4557/tcp			# FAX transmission service        (old)
hylafax		4559/tcp			# HylaFAX client-server protocol  (new)
noclog		5354/tcp			# noclogd with TCP (nocol)
noclog		5354/udp			# noclogd with UDP (nocol)
hostmon		5355/tcp			# hostmon uses TCP (nocol)
hostmon		5355/udp			# hostmon uses TCP (nocol)
ircd		6667/tcp			# Internet Relay Chat
ircd		6667/udp			# Internet Relay Chat
webcache	8080/tcp			# WWW caching service
webcache	8080/udp			# WWW caching service
tproxy		8081/tcp			# Transparent Proxy
tproxy		8081/udp			# Transparent Proxy
mandelspawn	9359/udp	mandelbrot	# network mandelbrot
amanda		10080/udp			# amanda backup services
amandaidx	10082/tcp			# amanda backup services
amidxtape	10083/tcp			# amanda backup services
isdnlog		20011/tcp			# isdn logging system
isdnlog		20011/udp			# isdn logging system
vboxd		20012/tcp			# voice box system
vboxd		20012/udp			# voice box system
binkp           24554/tcp			# Binkley
binkp           24554/udp			# Binkley
asp		27374/tcp			# Address Search Protocol
asp		27374/udp			# Address Search Protocol
tfido           60177/tcp			# Ifmail
tfido           60177/udp			# Ifmail
fido            60179/tcp			# Ifmail
fido            60179/udp			# Ifmail

# Local services
EOF

#setup mdev.conf
cat > "$etc"/mdev.conf << 'EOF' &&
# /etc/mdev/conf

# Devices:
# Syntax: %s %d:%d %s
# devices user:group mode

# support module loading on hotplug
$MODALIAS=.*            root:root       660 @/sbin/modprobe -b "$MODALIAS"

# null does already exist; therefore ownership has to be changed with command
null    root:root 0666  @chmod 666 $MDEV
zero    root:root 0666
grsec   root:root 0660
full    root:root 0666

random  root:root 0666
urandom root:root 0444
hwrandom root:root 0660

# console does already exist; therefore ownership has to be changed with command
#console        root:tty 0600   @chmod 600 $MDEV && mkdir -p vc && ln -sf ../$MDEV vc/0
console root:tty 0600 @mkdir -pm 755 fd && cd fd && for x in 0 1 2 3 ; do ln -sf /proc/self/fd/$x $x; done

fd0     root:floppy 0660
kmem    root:root 0640
mem     root:root 0640
port    root:root 0640
ptmx    root:tty 0666

# ram.*
ram([0-9]*)     root:disk 0660 >rd/%1
loop([0-9]+)    root:disk 0660 >loop/%1
sd[a-z].*       root:disk 0660 */lib/mdev/usbdisk_link
hd[a-z][0-9]*   root:disk 0660 */lib/mdev/ide_links
md[0-9]         root:disk 0660

tty             root:tty 0666
tty[0-9]        root:root 0600
tty[0-9][0-9]   root:tty 0660
ttyS[0-9]*      root:tty 0660
pty.*           root:tty 0660
vcs[0-9]*       root:tty 0660
vcsa[0-9]*      root:tty 0660

ttyLTM[0-9]     root:dialout 0660 @ln -sf $MDEV modem
ttySHSF[0-9]    root:dialout 0660 @ln -sf $MDEV modem
slamr           root:dialout 0660 @ln -sf $MDEV slamr0
slusb           root:dialout 0660 @ln -sf $MDEV slusb0
fuse            root:root  0666

# dri device
card[0-9]       root:video 0660 =dri/

# alsa sound devices and audio stuff
pcm.*           root:audio 0660 =snd/
control.*       root:audio 0660 =snd/
midi.*          root:audio 0660 =snd/
seq             root:audio 0660 =snd/
timer           root:audio 0660 =snd/

adsp            root:audio 0660 >sound/
audio           root:audio 0660 >sound/
dsp             root:audio 0660 >sound/
mixer           root:audio 0660 >sound/
sequencer.*     root:audio 0660 >sound/

# misc stuff
agpgart         root:root 0660  >misc/
psaux           root:root 0660  >misc/
rtc             root:root 0664  >misc/

# input stuff
event[0-9]+     root:root 0640 =input/
mice            root:root 0640 =input/
mouse[0-9]      root:root 0640 =input/
ts[0-9]         root:root 0600 =input/

# v4l stuff
vbi[0-9]        root:video 0660 >v4l/
video[0-9]      root:video 0660 >v4l/

# dvb stuff
dvb.*           root:video 0660 */lib/mdev/dvbdev

# load drivers for usb devices
usbdev[0-9].[0-9]       root:root 0660 */lib/mdev/usbdev
usbdev[0-9].[0-9]_.*    root:root 0660

# net devices
tun[0-9]*       root:root 0600 =net/
tap[0-9]*       root:root 0600 =net/

# zaptel devices
zap(.*)         root:dialout 0660 =zap/%1
dahdi!(.*)      root:dialout 0660 =dahdi/%1

# raid controllers
cciss!(.*)      root:disk 0660 =cciss/%1
ida!(.*)        root:disk 0660 =ida/%1
rd!(.*)         root:disk 0660 =rd/%1

sr[0-9]         root:cdrom 0660 @ln -sf $MDEV cdrom 

# hpilo
hpilo!(.*)      root:root 0660 =hpilo/%1

# xen stuff
xvd[a-z]        root:root 0660 */lib/mdev/xvd_links
EOF

#############################################################
#setup usr folder
#############################################################
usr=$out/usr

#setup udhcpc script
cat > "$usr"/share/udhcpc/default.script << 'EOF' &&
#!/bin/sh

# udhcpc script edited by Tim Riker <Tim@Rikers.org>

[ -z "$1" ] && echo "Error: should be called from udhcpc" && exit 1

RESOLV_CONF="/etc/resolv.conf"
[ -n "$broadcast" ] && BROADCAST="broadcast $broadcast"
[ -n "$subnet" ] && NETMASK="netmask $subnet"

case "$1" in
	deconfig)
		/sbin/ifconfig $interface 0.0.0.0
		;;

	renew|bound)
		/sbin/ifconfig $interface $ip $BROADCAST $NETMASK

		if [ -n "$router" ] ; then
			echo "deleting routers"
			while route del default gw 0.0.0.0 dev $interface ; do
				:
			done

			for i in $router ; do
				route add default gw $i dev $interface
			done
		fi

		echo -n > $RESOLV_CONF
		[ -n "$domain" ] && echo search $domain >> $RESOLV_CONF
		for i in $dns ; do
			echo adding dns $i
			echo nameserver $i >> $RESOLV_CONF
		done
		;;
esac

exit 0
EOF

#############################################################
#setup var
#############################################################
var=$out/var

#setup ifstate
cat > "$var"/run/ifstate << 'EOF' &&
EOF

#############################################################
#setup lib
#############################################################
lib_dir=$out/lib
mdev_lib_dir=$lib_dir/mdev

mkdir -p $mdev_lib_dir

#setup dvbdev
cat > "$mdev_lib_dir"/dvbdev << 'EOF' &&
#!/bin/sh

# MDEV=dvb0.demux1 -> ADAPTER=dvb0 -> N=0
ADAPTER=${MDEV%.*}
N=${ADAPTER#dvb}
# MDEV=dvb0.demux1 -> DEVB_DEV=demux1
DVB_DEV=${MDEV#*.}

case "$ACTION" in
	add|"")
		mkdir -p dvb/adapter${N}
		mv ${MDEV} dvb/adapter${N}/${DVB_DEV}
		;;
	remove)
		rm -f dvb/adapter${N}/${DVB_DEV}
		rmdir dvb/adapter${N} 2>/dev/null
		rmdir dvb/ 2>/dev/null
esac
EOF
chmod +x "$mdev_lib_dir"/dvbdev

#setup ide_links
cat > "$mdev_lib_dir"/ide_links << 'EOF' &&
#!/bin/sh

[ -f /proc/ide/$MDEV/media ] || exit

media=`cat /proc/ide/$MDEV/media`
for i in $media $media[0-9]* ; do
	if [ "`readlink $i 2>/dev/null`" = $MDEV ] ; then
		LINK=$i
		break
	fi
done

# link exist, remove if necessary and exit
if [ "$LINK" ] ; then
	[ "$ACTION" = remove ] && rm $LINK
	exit
fi

# create a link
num=`ls $media[0-9]* 2>/dev/null | wc -l`
ln -sf $MDEV "$media`echo $num`"
[ -e "$media" ] || ln -sf $MDEV "$media"
EOF
chmod +x "$mdev_lib_dir"/ide_links

#setup usbdev
cat > "$mdev_lib_dir"/usbdev << 'EOF' &&
#!/bin/sh

# script is buggy; until patched just do exit 0
#exit 0

# add zeros to device or bus
add_zeros () {
	case "$(echo $1 | wc -L)" in
		1)	echo "00$1" ;;
		2)	echo "0$1" ;;
		*)	echo "$1"
	esac
	exit 0
}


# bus and device dirs in /sys
USB_PATH=$(echo $MDEV | sed -e 's/usbdev\([0-9]\).[0-9]/usb\1/')
USB_PATH=$(find /sys/devices -type d -name "$USB_PATH")
USB_DEV_DIR=$(echo $MDEV | sed -e 's/usbdev\([0-9]\).\([0-9]\)/\1-\2/')

# dir names in /dev
BUS=$(add_zeros $(echo $MDEV | sed -e 's/^usbdev\([0-9]\).[0-9]/\1/'))
USB_DEV=$(add_zeros $(echo $MDEV | sed -e 's/^usbdev[0-9].\([0-9]\)/\1/'))


# try to load the proper driver for usb devices
case "$ACTION" in
	add|"")
		# load usb bus driver
		for i in $USB_PATH/*/modalias ; do
			modprobe `cat $i` 2>/dev/null
		done
		# load usb device driver if existent
		if [ -d $USB_PATH/$USB_DEV_DIR ]; then
			for i in $USB_PATH/$USB_DEV_DIR/*/modalias ; do
				modprobe `cat $i` 2>/dev/null
			done
		fi
		# move usb device file
		mkdir -p bus/usb/$BUS
		mv $MDEV bus/usb/$BUS/$USB_DEV
		;;
	remove)
		# unload device driver, if device dir is existent
		if [ -d $USB_PATH/$USB_DEV_DIR ]; then
			for i in $USB_PATH/$USB_DEV_DIR/*/modalias ; do
				modprobe -r `cat $i` 2>/dev/null
		done
		fi
		# unload usb bus driver. Does this make sense?
		# what happens, if two usb devices are plugged in
		# and one is removed?
		for i in $USB_PATH/*/modalias ; do
			modprobe -r `cat $i` 2>/dev/null
		done
		# remove device file and possible empty dirs
		rm -f bus/usb/$BUS/$USB_DEV
		rmdir bus/usb/$BUS/ 2>/dev/null
		rmdir bus/usb/ 2>/dev/null
		rmdir bus/ 2>/dev/null
esac
EOF
chmod +x "$mdev_lib_dir"/usbdev

#setup usbdisk_link
cat > "$mdev_lib_dir"/usbdisk_link << 'EOF' &&
#!/bin/sh

# NOTE: since mdev -s only provide $MDEV, don't depend on any hotplug vars.

current=$(readlink usbdisk)

if [ "$current" = "$MDEV" ] && [ "$ACTION" = "remove" ]; then
	rm -f usbdisk usba1
fi
[ -n "$current" ] && exit

if [ -e /sys/block/$MDEV ]; then
	SYSDEV=$(readlink -f /sys/block/$MDEV/device)
	# if /sys device path contains '/usb[0-9]' then we assume its usb
	# also, if it's a usb without partitions we require FAT
	if [ "${SYSDEV##*/usb[0-9]}" != "$SYSDEV" ]; then
		# do not create link if there is not FAT
		dd if=/dev/$MDEV bs=512 count=1 2>/dev/null | strings | grep FAT >/dev/null || exit 0

		ln -sf $MDEV usbdisk
		# keep this for compat. people have it in fstab
		ln -sf $MDEV usba1
	fi

elif [ -e /sys/block/*/$MDEV ] ; then
	PARENT=$(dirname /sys/block/*/$MDEV)
	SYSDEV=$(readlink -f $PARENT/device)
	if [ "${SYSDEV##*/usb[0-9]}" != "$SYSDEV" ]; then
		ln -sf $MDEV usbdisk
		# keep this for compat. people have it in fstab
		ln -sf $MDEV usba1
	fi
fi
EOF
chmod +x "$mdev_lib_dir"/usbdisk_link

#done
echo "done"
