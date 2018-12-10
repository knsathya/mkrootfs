#!/bin/bash

out=$1

MANUFACTURER="Linux"
PRODUCT="Zero"
VENDORID=0x1a0a
PRODUCTID=0xbadd

echo "############### Zero Gadget details ####################"

echo "PRODUCTID = "$PRODUCTID
echo "PRODUCT = "$PRODUCT
echo "MANUFACTURER = "$MANUFACTURER
echo "VENDORID = "$VENDORID

echo "############### End Gadget details ####################"

#############################################################
#Update etc folder
#############################################################
etc=$out/etc

cat > "$etc"/init.d/S05zero << 'EOF' &&
#!/bin/sh

# Change this for hardware non x86 devices.
SERIAL_NUMBER=`/bin/hostname`0001

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

makedir /config/usb_gadget/g1
makedir /config/usb_gadget/g1/configs/c.1
makedir /config/usb_gadget/g1/configs/c.2

makedir /config/usb_gadget/g1/functions/Loopback.0
makedir /config/usb_gadget/g1/functions/SourceSink.0

makedir /config/usb_gadget/g1/strings/0x409
makedir /config/usb_gadget/g1/configs/c.1/strings/0x409
makedir /config/usb_gadget/g1/configs/c.2/strings/0x409

write /config/usb_gadget/g1/idVendor VENDORID
write /config/usb_gadget/g1/idProduct PRODUCTID

write /config/usb_gadget/g1/strings/0x409/serialnumber $SERIAL_NUMBER
write /config/usb_gadget/g1/strings/0x409/manufacturer MANUFACTURER
write /config/usb_gadget/g1/strings/0x409/product PRODUCT

write /config/usb_gadget/g1/configs/c.1/strings/0x409/configuration "Conf 1"
write /config/usb_gadget/g1/configs/c.2/strings/0x409/configuration "Conf 2"
write /config/usb_gadget/g1/configs/c.1/MaxPower 120

ln -s /config/usb_gadget/g1/functions/Loopback.0 /config/usb_gadget/g1/configs/c.1
ln -s /config/usb_gadget/g1/functions/SourceSink.0 /config/usb_gadget/g1/configs/c.2

exit $?
EOF

sed -i "s/VENDORID/$VENDORID/g" "$etc"/init.d/S05zero
sed -i "s/PRODUCTID/$PRODUCTID/g" "$etc"/init.d/S05zero
sed -i "s/MANUFACTURER/$MANUFACTURER/g" "$etc"/init.d/S05zero
sed -i "s/PRODUCT/$PRODUCT/g" "$etc"/init.d/S05zero

chmod +x "$etc"/init.d/S05zero