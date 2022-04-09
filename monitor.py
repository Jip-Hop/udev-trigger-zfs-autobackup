#!/usr/bin/env python3

# To be called by trigger.sh

from os.path import abspath
from subprocess import check_call
import pyudev

# Remember path, in case this folder is overwritten (prevents [Errno 2] No such file or directory)
backup_script = abspath("backup.sh")

print('Using pyudev version: {0}'.format(pyudev.__version__))

monitor = pyudev.Monitor.from_netlink(pyudev.Context())
monitor.filter_by('block')

for device in iter(monitor.poll, None):
    if device.action == "add" and device.get('ID_FS_TYPE') == "zfs_member":
        current_label = device.get('ID_FS_LABEL')
        try:
            check_call([backup_script, current_label])
        except Exception as e:
            print(e)