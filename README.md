# Trigger zfs-autobackup when attaching backup disk

Automatically trigger [`zfs-autobackup`](https://github.com/psy0rz/zfs_autobackup) when an (external) backup disk is attached using the `udev-trigger-zfs-autobackup` daemon. Useful to store encrypted backups offline, on disks you can easily swap and store offsite. Works with USB, eSATA and disks in hotswap trays.

Specifically made for and tested on [TrueNAS SCALE](https://www.truenas.com/truenas-scale/), but made in a generic way so it should work on other hosts too. Please report if you try it on another host, like Proxmox or Ubuntu.

Monitors udev events to detect when new disks are attached. If the attached disk has a ZFS pool on it, and the zpool name matches one of the names set in the [config](./config) file, then it will be used as a backup disk. All datasets where the ZFS property `autobackup` matches the zpool name of the backup disk will be automatically backed up using `zfs-autobackup`.

## Usage
```
Usage: trigger.sh [-h] [-v] [--install]

Daemon to trigger zfs-autobackup when attaching backup disk.

1. Manually create (encrypted) ZFS pool(s) on removable disk(s).
2. Manually edit config to specify the names of your backup pool(s) and the encryption passphrase.
3. Manually schedule trigger.sh to run at system startup. On TrueNAS SCALE: System Settings -> Advanced -> Init/Shutdown Scripts -> Add -> Description: trigger-zfs-autobackup; Type: Script; Script: /path/to/trigger.sh; When: Post Init -> Save
4. Manually insert backup disk whenever you want to make a backup.
5. Automatic backup is triggered and sends email on completion.

Available options:

-h, --help      Print this help and exit
-v, --verbose   Print script debug info
-i, --install   Install dependencies
```

## Security

For security reasons, ensure only `root` can modify the `udev-trigger-zfs-autobackup` files. The scripts will be automatically executed with `root` privileges, so you don't want anyone to modify what they do.

## Setup

### Prepare backup disk

If `udev-trigger-zfs-autobackup` is already installed, then temporarily disable the trigger by editing [config](./config) (set enabled to false).

Execute the following commands to prepare a backup disk to use with `udev-trigger-zfs-autobackup`. Please read the commands (and comments!) carefully before executing them. You have to change several values.

```bash
# Carefully determine which disk to format as backup disk!
# All data on it will be lost permanently!
DISK=/dev/disk/by-id/usb-SanDisk_Ultra_Fit_XXXXXXXXXXXXXXXXXXXX-0:0
# Decide on a name for your backup pool
POOL=offsite1

wipefs -a $DISK
sgdisk --zap-all $DISK
sgdisk --new=1:0:0 --typecode=1:BF00 $DISK

# Use failmode=continue to prevent system from hanging on unclean device disconnect
# If you don't want to use encryption, then remove the encryption and keylocation options
zpool create \
    -O encryption=aes-256-gcm \
    -O keylocation=prompt -O keyformat=passphrase \
    -O acltype=posixacl \
    -O compression=zstd \
    -O atime=off \
    -O aclmode=discard \
    -O aclinherit=passthrough \
    -o failmode=continue \
    -R /mnt \
    $POOL $DISK

# If using encryption, you'll be asked to type your passphrase two times. Don't forget to manually edit the config file and put the passphrase in there when installing udev-trigger-zfs-autobackup

# Export the pool and manually disconnect the disk
zpool export $POOL

# Manually set autobackup:offsite1 on the datasets you want to backup (exchange offsite1 for the value chosen voor POOL above)
```

Don't forget to re-enable the backups by editing [config](./config) in case you had installed `udev-trigger-zfs-autobackup` before.

### Install udev-trigger-zfs-autobackup

Download this repository on the system you want to backup. Then install the dependencies by calling `trigger.sh --install` from the shell. This will install the dependencies locally using a Python virtual environment. The installation makes no modifications system outside of its installation directory. This is to ensure `udev-trigger-zfs-autobackup` will survive updates of TrueNAS SCALE (as long as you store it on one of your data pools, and not on the disks where the TrueNAS base system is installed).

### Edit config

You need to edit the [config](./config) file. Specify the names of your backup pools via config values starting with `backup_pool_`. Also specify your encryption passphrase. You need to use the same passphrase for all of your backup pools.

### Schedule udev-trigger-zfs-autobackup

The [trigger.sh](./trigger.sh) script needs to run on system startup. You need to manually this, for example using `cron` or `systemd`. On TrueNAS SCALE you can schedule the script via the web interface: System Settings -> Advanced -> Init/Shutdown Scripts -> Add -> Description: trigger-zfs-autobackup; Type: Script; Script: /path/to/trigger.sh; When: Post Init -> Save.

### Choose data sources

Add the `autobackup` property to the datasets you want to backup automatically to a backup pool. For example, to automatically backup the dataset `data` to backup pool `offsite1` run: `zfs set autobackup:offsite1=true data`. You can exclude descending datasets. For example excluding `ix-applications` would work like this: `zfs set autobackup:offsite1=false data/ix-applications`.

## Trigger backup

Connect your backup disk to trigger the automatic backup. You'll hear a beep confirming the start of the backup and you'll receive an email with the summary of the backup job.

## Disable automatic backup

To (temporarily) disable executing automatic backups, set `enabled=false` in [config](./config).