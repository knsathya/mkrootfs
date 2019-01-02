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
import tempfile

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
        self.build_init = False

        if not os.path.exists(self.src):
            self.logger.warning("Source dir %s does not exists, So creating it.", self.src)
            os.makedirs(self.src)

        if not os.path.exists(self.idir):
            self.logger.warning("Out dir %s does not exists, So creating it.", self.idir)
            os.makedirs(self.idir)

        # Out dir shell
        self.sh = PyShell(wd=self.idir, stream_stdout=True, logger=logger)
        self.git = GitShell(wd=self.src, stream_stdout=True, logger=logger)


    def add_adb_gadget(self, params):

        if self.type == "minrootfs":
            self.logger.info("Adb is not supported in minrootfs")

        adbd = pkg_resources.resource_filename('mkrootfs', 'bin/adb/adbd')

        # Copy ADBD && Create configfs update file.
        script = pkg_resources.resource_filename('mkrootfs', 'scripts/adb-gadget.sh')

        self.sh.cmd("%s %s %s %s" % (script, adbd, self.idir, ' '.join(params)))

    def add_zero_gadget(self, params):
        if self.type == "minrootfs":
            self.logger.info("Zero is not supported in minrootfs")

        script = pkg_resources.resource_filename('mkrootfs', 'scripts/zero-gadget.sh')

        self.sh.cmd("%s %s" % (script, self.idir))

    def add_services(self, slist):

        if self.build_init is False:
            self.logger.error("Please run build() before adding services")
            return False

        for service in slist:
            if service[0] == "adb-gadget":
                self.add_adb_gadget(service[1])
            elif service[0] == "zero-gadget":
                self.add_zero_gadget(service[1])

        return True

    def build(self, config=None):

        status = False
        if self.type == "busybox":
            status =  self._build_busybox(config)
        elif self.type  == "minrootfs":
            status =  self._build_minrootfs()

        if status is True:
            self.build_init = True

        return status

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

        git = GitShell(wd=src_dir)

        git.update_shell()

        ret = git.add_remote('origin', supported_rootfs[self.type][0])
        if not ret[0]:
            self.logger.error("Add remote %s failed" %  supported_rootfs[self.type][0])
            return False

        ret = git.cmd("fetch origin")
        if ret[0] != 0:
            self.logger.error("Git remote fetch failed")
            return False

        ret = git.checkout('origin', supported_rootfs[self.type][1])
        if not ret:
            self.logger.error("checkout branch %s failed", supported_rootfs[self.type][1])
            return ret

        if config is None:
            ret = self.sh.cmd("make defconfig", wd=src_dir)
            if ret[0] != 0:
                self.logger.error("make defconfig failed")
                return False
        else:
            self.sh.cmd("cp -f %s %s/.config" % (config, src_dir))

        ret = self.sh.cmd("make", wd=src_dir)
        if ret[0] != 0:
            self.logger.error("make busybox failed")
            return False

        script = pkg_resources.resource_filename('mkrootfs', 'scripts/busybox.sh')

        self.sh.cmd("%s %s" % (script, self.idir))

        self.sh.cmd("make CONFIG_PREFIX=%s install" % self.idir , wd=src_dir)

        self.sh.cmd("make clean", wd=src_dir)

        return True

    def sync_kmodules(self, kmoddir):

        if not os.path.exists(kmoddir):
            self.logger.error("%s is not a valid directory", kmoddir)
            return False

        kmoddir = os.path.abspath(kmoddir)

        self.sh.cmd("rm -fr %s/*" % os.path.join(self.idir, 'lib', 'modules'))
        self.sh.cmd("rsync -a %s/ %s" % (kmoddir, os.path.join(self.idir, 'lib', 'modules')))

        return True

    def update_rootfs(self, udir):

        if not os.path.exists(udir):
            self.logger.error("%s is not a valid directory", udir)
            return False

        udir = os.path.abspath(udir)

        self.sh.cmd("rsync -a %s/ %s" % (udir, self.idir))

        return True

    def gen_image(self, type, name):

        out_dir = os.path.dirname(name)

        if not os.path.exists(out_dir):
            os.makedirs(out_dir)

        if type == 'cpio':
            self.logger.debug("generating cpio rootfs image\n")
            self.sh.cmd("find . | cpio --quiet -H newc -o | gzip -9 -n > %s" % (name), wd=out_dir)
        elif type in ['ext2', 'ext3', 'ext4']:
            self.logger.debug("generating rootfs %s image\n", type)
            self.sh.cmd("dd if=/dev/zero of=%s bs=1M count=1024" % (name), wd=out_dir)
            self.sh.cmd("mkfs.%s -F %s -L rootfs" % (type, name))
            temp_dir = tempfile.mkdtemp()
            self.sh.cmd("sudo mount -o loop,rw,sync %s %s" % (name, temp_dir))
            self.sh.cmd("sudo /usr/bin/rsync -a -D %s/ %s" % (self.idir, temp_dir))
            self.sh.cmd(("sudo umount %s" % temp_dir))
            self.sh.cmd("rm -fr %s", temp_dir)














