# mkrootfs

Build your own rootfs image. Currently this app supports busybox or minrootfs types.

Usage:

```
makerootfs [OPTIONS] TYPE

Options:
  -c, --config-file PATH          Rootfs config file
  --debug / --no-debug
  -s, --src-dir PATH
  -i, --install-dir PATH
  --adb-gadget TEXT...            Manufacturer, Product, VendorId, ProductId
  --zero-gadget / --no-zero-gadget
                                  Add zero gadget support
  --out-type [ext2|ext3|ext4|cpio]
                                  Output image type
  --out-image PATH                Output image file
  --kmod-dir TEXT                 Kernel modules directory
  --help                          Show this message and exit.

```
