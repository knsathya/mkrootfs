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
import pkg_resources
from mkrootfs import RootFS, supported_rootfs

logger = logging.getLogger(__name__)
logging.basicConfig(format='%(message)s')
logger.setLevel(logging.INFO)

@click.group(chain=True)
@click.option('--rootfs-type', '-t', default='busybox', type=click.Choice(supported_rootfs.keys()), help='Rootfs type')
@click.option('--src-dir', '-s', type=click.Path(), default=os.path.join(os.getcwd(), 'src'), help='rootfs source dir')
@click.option('--install-dir', '-i', type=click.Path(), default=os.path.join(os.getcwd(), 'rootfs'),
              help='rootfs install dir')
@click.option('--out-dir', '-o', type=click.Path(), default=os.path.join(os.getcwd(), 'out'), help='rootfs out dir')
@click.option('--debug/--no-debug', default=False)
@click.pass_context
def cli(ctx, rootfs_type, src_dir, install_dir, out_dir, debug):
    ctx.obj = {}
    ctx.obj['ROOTFS_TYPE'] = rootfs_type
    ctx.obj['SRC_DIR'] = src_dir
    ctx.obj['INSTALL_DIR'] = install_dir
    ctx.obj['OUT_DIR'] = out_dir
    ctx.obj['DEBUG'] = debug
    if ctx.obj['DEBUG']:
        logger.level = logging.DEBUG

    ctx.obj['OBJ'] = RootFS(ctx.obj['ROOTFS_TYPE'], ctx.obj['SRC_DIR'], ctx.obj['INSTALL_DIR'],
                            ctx.obj['OUT_DIR'], logger)

@cli.command('build', short_help='Build rootfs')
@click.option('--config', '-c',
              default=pkg_resources.resource_filename('mkrootfs', 'configs/busybox/1_29_stable.config'),
              type=click.Path(exists=True), help='Rootfs config file')
@click.option('--diffconfig', '-d',
              default=pkg_resources.resource_filename('mkrootfs', 'configs/busybox/1_29_stable.diffconfig'),
              type=click.Path(exists=True), help='Rootfs diff config file')
@click.option('--src-branch', '-b', default="1_29_stable", type=str, help='Rootfs git branch')
@click.option('--src-url', '-u', default="git://git.busybox.net/busybox", type=str, help='Rootfs git url')
@click.option('--arch', default="x86_64", type=str, help='Build ARCH name')
@click.option('--cross-compile', default=None, type=str, help='cross compile')
@click.option('--cflags', default=None, type=str, help='cross compile')
@click.pass_context
def build(ctx, config, diffconfig, src_branch, src_url, arch, cross_compile, cflags):
    click.echo('Building rootfs %s' % (ctx.obj['ROOTFS_TYPE']))
    ctx.obj['OBJ'].build(src_url, src_branch, config, diffconfig, arch, cross_compile, cflags)

@cli.command('add-service', short_help='Add rootfs services')
@click.option('--adb-gadget/--no-adb-gadget', default=False, help='Add adb gadget support')
@click.option('--adb-params', nargs=4, default=[], type=str, help='Manufacturer, Product, VendorId, ProductId')
@click.option('--zero-gadget/--no-zero-gadget', default=False, help='Add zero gadget support')
@click.pass_context
def add_service(ctx, adb_gadget, adb_params, zero_gadget):
    services = []

    if adb_gadget:
        services.append(('adb-gadget', adb_params))

    if zero_gadget:
        services.append(('zero-gadget', []))

    if len(services) > 0:
        ctx.obj['OBJ'].add_services(services)


@cli.command('gen-image', short_help='Generate rootfs image')
@click.option('--out-type', type=click.Choice(['ext2', 'ext3', 'ext4', 'cpio']), help="Output image type")
@click.option('--out-image', default=None, type=click.Path(exists=False), help='Output image file')
@click.pass_context
def gen_image(ctx, out_type, out_image):
    click.echo('Generating rootfs image %s' % (out_image))
    ctx.obj['OBJ'].gen_image(out_type, out_image)


@cli.command('update', short_help='Update rootfs')
@click.option('--update-spath', type=click.Path(), default=None, help='Source path for update')
@click.option('--update-dpath', type=click.Path(), default=None, help='Destination path for update')
@click.pass_context
def update(ctx, update_spath, update_dpath):
    click.echo('Update rootfs %s %s' % (update_spath, update_dpath))
    ctx.obj['OBJ'].update_rootfs(update_spath, update_dpath)


@cli.command(short_help='Show help contents')
@click.pass_context
def help(ctx):
    print(ctx.parent.get_help())


if __name__ == '__main__':
    cli(obj={})

