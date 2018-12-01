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

logger = logging.getLogger(__name__)
logging.basicConfig(format='%(message)s')
logger.setLevel(logging.INFO)


@click.command()
@click.option('--config-file', '-c', default=None, type=click.Path(exists=True), help='Rootfs config file')
@click.option('--debug/--no-debug', default=False)
@click.option('--src-dir', type=click.Path(), default=os.getcwd())
@click.option('--install-dir', type=click.Path(), default=os.path.join(os.getcwd(), 'rootfs'))
@click.argument('type', type=click.Choice(supported_rootfs.keys()))
def cli(type, config_file, src_dir, install_dir, debug):

    obj = RootFS(type, src_dir, install_dir, logger)
    obj.build(config=config_file)




