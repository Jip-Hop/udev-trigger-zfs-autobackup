# Trigger zfs-autobackup when attaching backup disk

[TrueNAS SCALE](https://www.truenas.com/truenas-scale/) daemon to automatically trigger [`zfs-autobackup`](https://github.com/psy0rz/zfs_autobackup) when an (external) backup disk is attached. Useful to store encrypted backups offline, on disks you can easily swap and store offsite.

Monitors udev events to detect when new disks are attached. If the attached disk has a ZFS pool on it, and the zpool name matches one of the names set in the [config](./config) file, then it will be used as a backup disk. All datasets where the ZFS property `autobackup` matches the zpool name of the backup disk will be automatically backed up using `zfs-autobackup`.

Download this repository somewhere to your data pools. Don't store it on the disks where the TrueNAS base system is installed, or you'll lose these files when TrueNAS is updated. For security reasons, ensure only `root` can modify these files. The `trigger.sh` will be automatically running with `root` privileges, so you don't want anyone to modify what this script does. Then install the dependencies by calling `trigger.sh --install` from the shell. This will install the dependencies locally (using a Python virtual environment) and will survive updates of TrueNAS.

Then add the `autobackup` property to the datasets you want to backup automatically to a backup pool. For example, to automatically backup the dataset `data` to backup pool `offsite1` run: `zfs set autobackup:offsite1=true data`. You can exclude descending datasets. For example to excluding `ix-applications` would work like this: `zfs set autobackup:offsite1=false data/ix-applications`. Now that you've specified which datasets to backup to the backup pool (called `offsite1` in this example), you need to actually create the backup pool `offsite1`. Follow the steps from the output below:

```
Usage: trigger.sh [-h] [-v] [--install]

Daemon to trigger zfs-autobackup when attaching backup disk.

1. Manually create encrypted ZFS pool(s) on removable disk.
2. Manually edit config to specify the names of your backup pool(s).
3. Manually run 'zpool export name_of_backup_pool' from shell and remove disk. Don't export from web interface! Encryption key will removed and auto-unlock will fail!
4. Manually schedule trigger.sh via System Settings -> Advanced -> Init/Shutdown Scripts -> Add -> Description: trigger-zfs-autobackup; Type: Script; Script: /path/to/trigger.sh; When: Post Init -> Save
5. Manually insert backup disk whenever you want to make a backup.
6. Automatic backup is triggered and sends email on completion.

Available options:

-h, --help      Print this help and exit
-v, --verbose   Print script debug info
-i, --install   Install dependencies
```

To temporarily disable executing automatic backups, set `ENABLED=false` in the [config](./config) file.

When rotating two backup disks for offsite storage, the TrueNAS SCALE webinterface may look like this (when both drives are disconnected):

<img width="923" alt="Screenshot 2022-04-09 at 19 20 31" src="https://user-images.githubusercontent.com/2871973/162584798-9321d1ab-6b35-4c7e-bd6a-214f3f56c7e8.png">
