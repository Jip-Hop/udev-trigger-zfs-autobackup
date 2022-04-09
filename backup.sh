#!/usr/bin/env bash

# To be called by monitor.py

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
. "${SCRIPT_DIR}/config"

if ! [ "$ENABLED" = true ]; then
    echo "Skip, auto backup is disabled."
    exit
fi

POOL=$1

if [[ ! " ${BACKUP_POOL[*]} " =~ " ${POOL} " ]]; then
    echo "Pool ${POOL} is not a backup pool."
    exit
fi

cleanup() {

    if mountpoint -q "/mnt/${POOL}"; then
        MESSAGE="Pool ${POOL} is still mounted at '/mnt/${POOL}'. Not safe for removal!"
    else
        MESSAGE="Pool ${POOL} is NOT mounted at '/mnt/${POOL}'. Should be safe to remove."
    fi

    # Deactivate Python virtual environment for next commands
    (
        deactivate
        # Send email to root user (need to have configured the email address for root user in TrueNAS web interface)
        printf "%s\n\nFull log output:\n\n%s" "${MESSAGE}" "${OUTPUT}" | mail -s "${SUBJECT}" "root"
    )
}

main() {
    set -euo pipefail
    # Duplicates stderr onto stdout 
    exec 2>&1

    echo "START backup of datasets with zfs property 'autobackup:${POOL}' to pool ${POOL}"

    # TrueNAS won't automatically import the pool once the disk is connected, do so manually
    echo "IMPORT pool ${POOL}"
    zpool import ${POOL}

    echo "after manual error"
    # TrueNAS won't automatically unlock the pool once the disk is imported, do so manually
    # TrueNAS will use the key stored in it's database (no need to manually provide this)
    echo "UNLOCK pool ${POOL}"
    cli -c "storage dataset unlock id=${POOL}"

    # Rollback to latest existing snapshot on this dataset (discard all changes made to a file system since latest snapshot)
    # Speed up by using --allow-empty --no-progress
    # Backup to encrypted pool (should have been manually created before!)
    echo "BACKUP to pool ${POOL}"
    zfs-autobackup -v ${POOL} ${POOL} --encrypt --allow-empty --no-progress --rollback

    # TODO: Should I use --no-holds to prevent this error:
    # ! [Source] STDERR > cannot hold snapshot 'data@offsite1-20220409123946': tag already exists on this dataset

    # TODO: Should I use --rollback if dataset is also set to readonly?

    # Mount readonly in the future, to prevent accidental changes to the backup data
    # NOTE: perhaps instead use --set-properties to make backups readonly?
    zfs set readonly=on ${POOL}

    # TODO: use zfs-autoverify to check backup integrity

    echo "EXPORT pool ${POOL}"
    zpool export ${POOL}

    # TODO: hint about 'zpool clear ${POOL}' when zpool export fails?
}

SUBJECT="ERROR MAKING BACKUP"
trap cleanup EXIT

# Make beep sound
echo -en "\a" >/dev/tty5

# Capture main output, to send log via email
# TODO: capture stderr too
OUTPUT=$(main)
echo "${OUTPUT}"

# TODO: actually check output of above commands to determine success
SUBJECT="SUCCESSFULLY COMPLETED BACKUP"
