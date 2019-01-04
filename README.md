# mkrootfs

Build your own rootfs image. Currently this app supports busybox or minrootfs types.

Usage:

```
Usage: makerootfs [OPTIONS] COMMAND1 [ARGS]... [COMMAND2 [ARGS]...]...

Options:
  -t, --rootfs-type [busybox|minrootfs]
                                  Rootfs type
  -s, --src-dir PATH
  -i, --rootfs-dir PATH           rootfs dir
  --debug / --no-debug
  --help                          Show this message and exit.

Commands:
  add-service  Add rootfs services
  build        Build rootfs
  gen-image    Generate rootfs image
  help         Show help contents
  update       Update rootfs


```
