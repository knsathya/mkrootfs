# -*- coding: utf-8 -*-
#
# makerootfs command line tool
#
# Copyright (C) 2018 Sathya Kuppuswamy
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# @Author  : Sathya Kupppuswamy(sathyaosid@gmail.com)
# @History :
#            @v0.0 - Initial update
# @TODO    :
#
#

import os
import click
import logging
from mkrootfs import RootFS, supported_rootfs
import os
import click
import logging
from mkrootfs import RootFS, supported_rootfs

logger = logging.getLogger(__name__)
logging.basicConfig(format='%(message)s')
logger.setLevel(logging.INFO)


@click.command()
@click.option('--config-file', '-c', default=None, type=click.Path(exists=True), help='Rootfs config file')
@click.option('--debug/--no-debug', default=False)
@click.option('--src-dir', '-s', type=click.Path(), default=os.getcwd())
@click.option('--install-dir', '-i', type=click.Path(), default=os.path.join(os.getcwd(), 'rootfs'))
@click.option('--adb-gadget', nargs=4, default=None, type=str, help='Manufacturer, Product, VendorId, ProductId')
@click.option('--zero-gadget/--no-zero-gadget', default=False, help='Add zero gadget support')
@click.option('--out-type', type=click.Choice(['ext2', 'ext3', 'ext4', 'cpio']), help="Output image type")
@click.option('--out-image', default=None, type=click.Path(exists=False), help='Output image file')
@click.option('--kmod-dir', default=None, type=click.Path(exists=False), help='Kernel modules directory')
@click.option('--sync-dir', default=None, type=click.Path(exists=False), help='Rootfs update directory')
@click.argument('type', type=click.Choice(supported_rootfs.keys()))

def cli(type, config_file, src_dir, install_dir, debug, adb_gadget, zero_gadget,
        out_type, out_image, kmod_dir, sync_dir):

    if debug:
        logger.level = logging.DEBUG

    obj = RootFS(type, src_dir, install_dir, logger)

    obj.build(config=config_file)

    services = []

    if len(adb_gadget) > 0:
        services.append(('adb-gadget', adb_gadget))

    if zero_gadget:
        services.append(('zero-gadget', []))

    obj.add_services(services)

    if kmod_dir is not None:
        obj.sync_kmodules(kmod_dir)

    if sync_dir is not None:
        obj.update_rootfs(sync_dir)

    obj.gen_image(out_type, out_image)




