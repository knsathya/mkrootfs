#!/bin/bash

# setup env
out=$1
rm -fr $out
###########################################################
# create rootfs basic dirs
############################################################
echo "Create files and directories"
mkdir -pv $out/{dev,etc,lib,proc,tmp,sys,media,mnt,opt,var,home,root,usr,var/run} &&
chmod a+rwxt "$out"/tmp &&
mkdir -pv $out/etc/{init.d,network/if-{post-{up,down},pre-{up,down},up,down}.d} &&
mkdir -pv $out/usr/{bin,sbin,lib,share/udhcpc} &&
ln -s usr/bin "$out/bin" &&
ln -s usr/sbin "$out/sbin" &&
ln -s usr/lib "$out/lib" &&

#############################################################
#setup dev folder
#############################################################
dev_dir=$out/dev

#setup min device nodes
sudo mknod -m 600 $dev_dir/mem c 1 1;
sudo mknod -m 666 $dev_dir/null c 1 3;
sudo mknod -m 666 $dev_dir/zero c 1 5;
sudo mknod -m 644 $dev_dir/random c 1 8;
sudo mknod -m 600 $dev_dir/tty0 c 4 0;
sudo mknod -m 600 $dev_dir/tty1 c 4 1;
sudo mknod -m 600 $dev_dir/ttyS0 c 4 64;
sudo mknod -m 666 $dev_dir/tty c 5 0;
sudo mknod -m 666 $dev_dir/console c 5 1;

#############################################################
#setup etc folder
#############################################################
etc=$out/etc

#setup hostname
cat > "$etc"/hostname << 'EOF' &&
busybox-x86_64
EOF

#setup os-release
cat > "$etc"/os-release << 'EOF' &&
NAME="Kdev"
PRETTY_NAME="Kdev 0.1"
VERSION_ID="0.1"
HOME_URL="https://github.com/knsathya/kdev.git"
EOF

#setup profile
cat > "$etc"/profile << 'EOF' &&
# /etc/profile

# Set the initial path
export PS1='\[\033[0;32m\]\u@\h:\[\033[36m\]\W\[\033[0m\] \$ '

export PATH=/bin:/usr/bin

if [ `id -u` -eq 0 ] ; then
	PATH=/bin:/sbin:/usr/bin:/usr/sbin
	unset HISTFILE
fi

# Setup some environment variables.
export USER=`id -un`
export LOGNAME=$USER
export HOSTNAME=`/bin/hostname`
export HISTSIZE=1000
export HISTFILESIZE=1000
export PAGER='/bin/more '
export EDITOR='/bin/vi'

# End /etc/profile
EOF

#setup passwd
cat > "$etc"/passwd << 'EOF' &&
root:x:0:0:root:/:/bin/sh
EOF

#setup group
cat > "$etc"/group << 'EOF' &&
root:x:0:
tty:x:5:
disk:x:6:
dialout:x:20:
cdrom:x:24:sathya
floppy:x:25:
audio:x:29:pulse
video:x:44:
pulse:x:124:
EOF

#############################################################
#setup init
#############################################################

#setup basic init
cat > "$out"/init << 'EOF' &&
#!/bin/sh

export HOME=/home
export PATH=/bin:/sbin

source /etc/profile

parse_cmdline()
{
	param=$1
	value="$(cat /proc/cmdline | awk -F"$param=" '{print $2}' | awk -F" " '{print $1}')"
	echo $value
}

# mount temporary filesystems

/bin/mount -n -t devtmpfs devtmpfs /dev
/bin/mount -n -t proc     proc     /proc
/bin/mount -n -t sysfs    sysfs    /sys
/bin/mount -n -t tmpfs    tmpfs    /tmp

# setup networking
ifconfig eth0 192.168.1.150
route add default gw 192.168.1.1

# set hostname
echo "Setting hostname"
/bin/hostname -F /etc/hostname

root_dev=$(parse_cmdline root)
console_dev=$(parse_cmdline console)
new_init=$(parse_cmdline init)

if [ -z "$root_dev" ]; then
    echo "root_dev is empty"
else
	echo "Root device is "$root_dev
	count=0
	while [ ! -b "$root_dev" ] && [ $count -le 10 ]; do
		echo "Waiting for root device "$root_dev
		count=$((count+1))
		sleep 1
	done
	if [ -b "$root_dev" ]; then
		/bin/mount $root_dev /root
		/bin/mount --move /sys /root/sys
		/bin/mount --move /proc /root/proc
		/bin/mount --move /dev /root/dev
		/bin/mount --move /tmp /root/tmp
		exec /sbin/switch_root /root $new_init
	fi
fi

/bin/sh

EOF
chmod +x "$out"/init &&

#############################################################
#copy min busybox shell
#############################################################
bin_dir=$out/bin
sbin_dir=$out/sbin

ln -s ./busybox $bin_dir/sh
ln -s ./busybox $bin_dir/sed
ln -s ./busybox $bin_dir/grep
ln -s ./busybox $bin_dir/cat
ln -s ./busybox $bin_dir/mount
ln -s ./busybox $bin_dir/ls
ln -s ./busybox $bin_dir/hostname
ln -s ./busybox $bin_dir/id
ln -s ./busybox $bin_dir/more
ln -s ./busybox $bin_dir/vi
ln -s ./busybox $bin_dir/xargs
ln -s ./busybox $bin_dir/awk
ln -s ../bin/busybox $sbin_dir/ifconfig
ln -s ../bin/busybox $sbin_dir/route
ln -s ../bin/busybox $sbin_dir/switch_root

#done
echo "done"
