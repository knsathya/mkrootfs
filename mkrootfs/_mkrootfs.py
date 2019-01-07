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
from klibs import KernelConfig

valid_str = lambda x: True if x is not None and isinstance(x, basestring) and len(x) > 0 else False

supported_rootfs = {
        "minrootfs" :   (None, None),
        "busybox"   :   ("git://git.busybox.net/busybox", "1_29_stable")
}

class RootFS(object):
    def __init__(self, type, src, idir, out=None, logger=None):
        self.logger = logger or logging.getLogger(__name__)

        if type not in supported_rootfs.keys():
            self.logger.error("Rootfs type %s is not supported", type)
            return

        self.type = type
        self.src = os.path.join(os.path.abspath(src), "busybox" if type == "minrootfs" else type)
        self.out = os.path.join(os.path.abspath(out), self.type) if out is not None else self.src
        self.idir = os.path.join(os.path.abspath(idir), self.type)
        self.cc = None
        self.arch = "x86_64"
        self.cflags = []
        self.build_init = False
        self.config = None
        self.diffconfig = None
        self.src_url = None
        self.src_branch = None

        if not os.path.exists(self.src):
            self.logger.warning("Source dir %s does not exists, So creating it.", self.src)
            os.makedirs(self.src)

        if not os.path.exists(self.idir):
            self.logger.warning("Install dir %s does not exists, So creating it.", self.idir)
            os.makedirs(self.idir)

        if not os.path.exists(self.out):
            self.logger.warning("Out dir %s does not exists, So creating it.", self.out)
            os.makedirs(self.out)

        # Out dir shell
        self.sh = PyShell(wd=self.idir, stream_stdout=True, logger=logger)
        self.git = GitShell(wd=self.src, stream_stdout=True, logger=logger)

        for subdir in ['dev','etc', 'lib', 'proc', 'tmp', 'sys' ,'media', 'mnt' ,'opt'
            ,'var' ,'home','root','usr','var']:
            if os.path.exists(os.path.join(self.idir, subdir)):
                self.build_init = True
            else:
                self.build_init = False
                break

    def add_adb_gadget(self, params):

        if self.type == "minrootfs":
            self.logger.info("Adb is not supported in minrootfs")

        adbd = pkg_resources.resource_filename('mkrootfs', 'bin/adb/adbd')

        # Copy ADBD && Create configfs update file.
        script = pkg_resources.resource_filename('mkrootfs', 'scripts/adb-gadget.sh')

        if len(params) > 0:
            self.sh.cmd("%s %s %s %s" % (script, self.idir, adbd,  ' '.join(params)))
        else:
            self.sh.cmd("%s %s %s" % (script, self.idir, adbd))

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

    def build(self, src_url=None, src_branch=None, config=None, diff_config=None, arch="x86_64", cc=None, cflags=None):
        status = False

        self.src_url = src_url
        self.src_branch = src_branch
        self.config = config
        self.diffconfig = diff_config
        self.arch = arch
        self.cc = cc
        self.cflags = [cflags] if cflags is not None else []

        if self.type == "busybox":
            status =  self._build_busybox()
        elif self.type  == "minrootfs":
            status =  self._build_minrootfs()

        if status is True:
            self.build_init = True

        return status

    def _busybox_init(self, src_dir):

        if self.config is not None and not os.path.exists(self.config):
            self.logger.error("Invalid config %s", self.config)
            return False

        if self.src_branch is not None and not valid_str(self.src_branch):
            self.logger.error("Invalid branch %s", self.src_branch)
            return False

        if not os.path.exists(src_dir):
            os.makedirs(src_dir)

        git = GitShell(wd=src_dir)

        git.update_shell()

        src_url = supported_rootfs[self.type][0] if self.src_url is None else self.src_url
        if self.src_branch is None:
            self.src_branch = supported_rootfs[self.type][1]

        ret = git.add_remote('origin', src_url)
        if not ret[0]:
            self.logger.error("Add remote %s failed" %  src_url)
            return False

        ret = git.cmd("fetch origin")
        if ret[0] != 0:
            self.logger.error("Git remote fetch failed")
            return False

        ret = git.checkout('origin', self.src_branch)
        if not ret:
            self.logger.error("checkout branch %s failed", self.src_branch)
            return ret

    def _busybox_make(self, src_dir, script):

        def format_cmd(target=None, flags=''):

            cmd = ["make"]

            cmd.append("ARCH=%s" % self.arch)
            if self.cc is not None:
                cmd.append("CROSS_COMPILE=%s" % self.cc)

            if len(flags) > 0:
                cmd.append(flags)

            if len(self.cflags) > 0:
                cmd += self.cflags

            cmd.append("CONFIG_PREFIX=%s" % self.idir)

            cmd.append("-C %s" % src_dir)
            cmd.append("O=%s" % self.out)

            if target is not None:
                cmd.append("%s" % target)

            return ' '.join(cmd)

        ret = self.sh.cmd(format_cmd("defconfig"), wd=src_dir)
        if ret[0] != 0:
            self.logger.error("make defconfig failed")
            return False

        if self.config is not None:
            self.sh.cmd("cp -f %s %s/.config" % (self.config, self.out))

        if self.diffconfig is not None:
            kobj = KernelConfig(os.path.join(self.out, '.config'))
            kobj.merge_config(self.diffconfig)

        ret = self.sh.cmd(format_cmd(), wd=self.out)
        if ret[0] != 0:
            self.logger.error("make failed")
            return False

        self.sh.cmd("%s %s" % (script, self.idir))

        ret = self.sh.cmd(format_cmd("install"), wd=self.out)
        if ret[0] != 0:
            self.logger.error("make install failed")
            return False

    def _build_minrootfs(self):

        script = pkg_resources.resource_filename('mkrootfs', 'scripts/minrootfs.sh')

        if self._busybox_init(self.src) is False:
            self.logger.error("Minrootfs init failed")
            return False

        if self._busybox_make(self.src, script) is False:
            self.logger.error("Minrootfs make failed")
            return False

        return True

    def _build_busybox(self):

        script = pkg_resources.resource_filename('mkrootfs', 'scripts/busybox.sh')

        if self._busybox_init(self.src) is False:
            self.logger.error("Busybox init failed")
            return False

        if self._busybox_make(self.src, script) is False:
            self.logger.error("Busybox make failed")
            return False

        return True

    def update_rootfs(self, spath, dpath):
        if spath is None or dpath is None or not os.path.exists(spath):
            self.logger.error("%s is not a valid file/directory", spath)
            return False

        spath = os.path.abspath(spath)
        dpath = os.path.abspath(dpath)

        if os.path.isfile(spath):
            self.sh.cmd("cp %s %s" % (spath, dpath))
        else:
            self.sh.cmd("rsync -a %s/ %s" % (spath, dpath))

        return True

    def set_hostname(self, hostname):
        fobj = open(os.path.join(self.idir, 'etc', 'hostname'), 'w+')
        fobj.truncate()
        fobj.write(hostname)
        fobj.close()

    def gen_image(self, type, name):

        out_dir = os.path.dirname(name)

        if not os.path.exists(out_dir):
            os.makedirs(out_dir)

        if type == 'cpio':
            self.logger.debug("generating cpio rootfs image\n")
            self.sh.cmd("find . -print0 | cpio --null --create --format=newc | gzip --best > %s" % (name), wd=self.idir)
        elif type in ['ext2', 'ext3', 'ext4']:
            self.logger.debug("generating rootfs %s image\n", type)
            self.sh.cmd("dd if=/dev/zero of=%s bs=1M count=1024" % (name), wd=out_dir)
            self.sh.cmd("mkfs.%s -F %s -L rootfs" % (type, name))
            temp_dir = tempfile.mkdtemp()
            self.sh.cmd("sudo mount -o loop,rw,sync %s %s" % (name, temp_dir))
            self.sh.cmd("sudo /usr/bin/rsync -a -D %s/ %s" % (self.idir, temp_dir))
            self.sh.cmd(("sudo umount %s" % temp_dir))
            self.sh.cmd("rm -fr %s", temp_dir)














