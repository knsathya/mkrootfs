# -*- coding: utf-8 -*-
#
# mkrootfs build classes
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
import logging
from pyshell import PyShell, GitShell
import pkg_resources

supported_rootfs = {
        "minrootfs" :   (None, None),
        "busybox"   :   ("git://git.busybox.net/busybox", "1_29_stable")
}

class RootFS(object):
    def __init__(self, type, src, idir, logger=None):
        self.logger = logger or logging.getLogger(__name__)

        # Create shell objs
        sh = PyShell(wd=os.getcwd())

        if type not in supported_rootfs.keys():
            self.logger.error("Rootfs type %s is not supported", type)
            return

        self.type = type

        self.src = os.path.abspath(src)
        self.idir = os.path.abspath(idir)

        if not os.path.exists(self.src):
            self.logger.warning("Source dir %s does not exists, So creating it.", self.src)
            os.makedirs(self.src)

        if not os.path.exists(self.idir):
            self.logger.warning("Out dir %s does not exists, So creating it.", self.idir)
            os.makedirs(self.idir)

        # Out dir shell
        self.sh = PyShell(wd=self.idir, stream_stdout=True, logger=logger)
        self.git = GitShell(wd=self.src, stream_stdout=True, logger=logger)

        # Adb related properties
        self.add_adb = False

    def build(self, config=None):
        if self.type == "busybox":
            return self._build_busybox(config)
        elif self.type  == "minrootfs":
            return self._build_minrootfs()

        return True

    def _build_minrootfs(self):
        script = pkg_resources.resource_filename('mkrootfs', 'scripts/minrootfs.sh')
        self.sh.cmd("%s %s" % (script, self.idir))

        return True

    def _build_busybox(self, config=None):

        if config is not None and not os.path.exists(config):
            self.logger.error("Invalid config %s", config)
            return False

        src_dir = os.path.join(self.src, "busybox", "src")
        if not os.path.exists(src_dir):
            os.makedirs(src_dir)

        out_dir = os.path.join(self.src, "busybox", "out")
        if not os.path.exists(out_dir):
            os.makedirs(out_dir)

        ret = self.git.add_remote('origin', supported_rootfs[self.type][0], wd=src_dir)
        if not ret[0]:
            self.logger.error("Add remote %s failed" %  supported_rootfs[self.type][0])
            return False

        ret = self.git.cmd("fetch origin")
        if ret[0] != 0:
            self.logger.error("Git remote fetch failed")
            return False

        ret = self.git.checkout('origin', supported_rootfs[self.type][1])
        if not ret:
            self.logger.error("checkout branch %s failed", supported_rootfs[self.type][1])
            return ret

        if config is None:
            ret = self.sh.cmd("make O=%s defconfig" % out_dir, wd=src_dir)
            if ret[0] != 0:
                self.logger.error("make defconfig failed")
                return False
        else:
            self.sh.cmd("cp -f %s %s/.config" % (config, out_dir))

        ret = self.sh.cmd("make", wd=out_dir)
        if ret[0] != 0:
            self.logger.error("make busybox failed")
            return False

        script = pkg_resources.resource_filename('mkrootfs', 'scripts/busybox.sh')
        self.sh.cmd("%s %s" % script, self.idir)

        self.sh.cmd("make PREFIX=%s install" % self.idir , wd=out_dir)












