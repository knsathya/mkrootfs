#!/bin/sh

# Change this for hardware non x86 devices.

SERIAL_NUMBER=`/bin/hostname`0001
MANUFACTURER=Intel
PRODUCT="KDEV"

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
}

makedir /config
mount -t configfs none /config
makedir /config/usb_gadget/g1
chmod 0770 /config/usb_gadget/g1
chown shell:shell /config/usb_gadget/g1

write /config/usb_gadget/g1/idVendor 0x8087
write /config/usb_gadget/g1/idProduct 0x0a5f
write /config/usb_gadget/g1/bcdDevice 0x0
write /config/usb_gadget/g1/bcdUSB 0x0210
makedir /config/usb_gadget/g1/strings/0x409
write /config/usb_gadget/g1/strings/0x409/serialnumber $SERIAL_NUMBER
write /config/usb_gadget/g1/strings/0x409/manufacturer $MANUFACTURER
write /config/usb_gadget/g1/strings/0x409/product $PRODUCT

makedir /config/usb_gadget/g1/functions/ffs.adb
makedir /config/usb_gadget/g1/configs/b.1
chmod 0770 /config/usb_gadget/g1/configs/b.1
chown shell:shell /config/usb_gadget/g1/configs/b.1
makedir /config/usb_gadget/g1/configs/b.1/strings/0x409
chmod 0770 /config/usb_gadget/g1/configs/b.1/strings/0x409
write /config/usb_gadget/g1/os_desc/b_vendor_code 0x1
write /config/usb_gadget/g1/os_desc/qw_sign "MSFT100"
write /config/usb_gadget/g1/configs/b.1/MaxPower 500


makedir /dev/usb-ffs
makedir /dev/usb-ffs/adb
chmod 0770 /dev/usb-ffs
chmod 0770 /dev/usb-ffs/adb
chown shell:shell /dev/usb-ffs
chown shell:shell /dev/usb-ffs/adb
mount -t functionfs adb /dev/usb-ffs/adb

write /config/usb_gadget/g1/configs/b.1/strings/0x409/configuration "adb"

ln -s /config/usb_gadget/g1/configs/b.1 /config/usb_gadget/g1/os_desc/b.1
ln -s /config/usb_gadget/g1/functions/ffs.adb /config/usb_gadget/g1/configs/b.1/f1

write /config/usb_gadget/g1/UDC dwc3.0.auto

