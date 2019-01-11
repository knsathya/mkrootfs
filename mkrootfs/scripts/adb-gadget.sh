#!/bin/bash

out=$1
adbd=$2

#############################################################
# Update ADBD binary
#############################################################

echo "############### Copy ADBD binary ####################"

cp $adbd $out/bin/adbd
chmod 775 $out/bin/adbd

#############################################################

if [ $# -ge 2 ]; then
    MANUFACTURER=$3
else
    MANUFACTURER="Intel"
fi

if [ $# -ge 3 ]; then
    PRODUCT=$4
else
    PRODUCT="KDEV"
fi

if [ $# -ge 4 ]; then
    VENDORID=$5
else
    VENDORID=0x8087
fi

if [ $# -ge 5 ]; then
    PRODUCTID=$6
else
    PRODUCTID=0x09ef
fi

echo "############### ADB Gadget details ####################"

echo "PRODUCTID = "$PRODUCTID
echo "PRODUCT = "$PRODUCT
echo "MANUFACTURER = "$MANUFACTURER
echo "VENDORID = "$VENDORID

echo "############### End Gadget details ####################"

#############################################################
#Update etc folder
#############################################################
etc=$out/etc

cat > "$etc"/init.d/S05adb << 'EOF' &&
#!/bin/sh
#
# Change this for hardware non x86 devices.

SERIAL_NUMBER=`/bin/hostname`0001

/sbin/adduser shell

write()
{
	file_name=$1
	value=$2

	echo $value > $file_name
}

makedir()
{
	dir_name=$1

	if [ ! -d "$dir_name" ]; then
		mkdir $dir_name
	else
    	echo $dir_name" exists"
	fi

	if [ $# -ge 1 ]; then
	   chmod $2 $dir_name
	fi

	if [ $# -ge 2 ]; then
	   chown $3 $dir_name
	fi


}

makedir /config

mount -t configfs none /config

makedir /config/usb_gadget/g1 0770 shell:shell
makedir /config/usb_gadget/g1/strings/0x409
makedir /config/usb_gadget/g1/functions/ffs.adb
makedir /config/usb_gadget/g1/configs/b.1 0770 shell:shell
makedir /config/usb_gadget/g1/configs/b.1/strings/0x409 0770
makedir /dev/usb-ffs 0770 shell:shell
makedir /dev/usb-ffs/adb 0770 shell:shell

write /config/usb_gadget/g1/idVendor VENDORID
write /config/usb_gadget/g1/idProduct PRODUCTID
write /config/usb_gadget/g1/bcdDevice 0x0
write /config/usb_gadget/g1/bcdUSB 0x0210

write /config/usb_gadget/g1/strings/0x409/serialnumber $SERIAL_NUMBER
write /config/usb_gadget/g1/strings/0x409/manufacturer MANUFACTURER
write /config/usb_gadget/g1/strings/0x409/product PRODUCT

write /config/usb_gadget/g1/os_desc/b_vendor_code 0x1
write /config/usb_gadget/g1/os_desc/qw_sign "MSFT100"
write /config/usb_gadget/g1/configs/b.1/MaxPower 500

write /config/usb_gadget/g1/configs/b.1/strings/0x409/configuration "adb"

ln -s /config/usb_gadget/g1/configs/b.1 /config/usb_gadget/g1/os_desc/b.1
ln -s /config/usb_gadget/g1/functions/ffs.adb /config/usb_gadget/g1/configs/b.1/f1

exit $?
EOF

sed -i "s/VENDORID/$VENDORID/g" "$etc"/init.d/S05adb
sed -i "s/PRODUCTID/$PRODUCTID/g" "$etc"/init.d/S05adb
sed -i "s/MANUFACTURER/$MANUFACTURER/g" "$etc"/init.d/S05adb
sed -i "s/PRODUCT/$PRODUCT/g" "$etc"/init.d/S05adb

chmod +x "$etc"/init.d/S05adb


