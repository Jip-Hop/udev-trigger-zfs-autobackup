#!/usr/bin/env bash

# To be called by monitor.py

set -euo pipefail

# Set default config values here, so variables are always defined
# Overridden by sourcing the config file
ENABLED=false
EMAIL=''
BACKUP_POOL[0]=''

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
. "${SCRIPT_DIR}/config"

if ! [ "${ENABLED}" = true ]; then
    echo "Skip, auto backup is disabled."
    exit
fi

POOL=$1

if [[ ! " ${BACKUP_POOL[*]} " =~ " ${POOL} " ]]; then
    echo "Pool ${POOL} is not a backup pool."
    exit
fi

cleanup() {

    # Only email if the EMAIL variable is not empty
    if ! [ -z "${EMAIL}" ]; then

        if zpool list ${POOL} 2>/dev/null; then
            MESSAGE="Pool ${POOL} is present. Not safe for removal!"
        else
            MESSAGE="Pool ${POOL} is NOT present. Should be safe to remove."
        fi

        # Deactivate Python virtual environment for next commands
        (
            deactivate
            # Send email to root user (need to have configured the email address for root user in TrueNAS web interface)
            printf "%s\n\nFull log output:\n\n%s" "${MESSAGE}" "${OUTPUT}" | mail -s "${SUBJECT}" "${EMAIL}"
        )
    fi
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

    # TODO: optionally use a generic unlock method, reading passphrase from the config file
    # That way this script could be used on non-TrueNAS systems too
    cli -c "storage dataset unlock id=${POOL}"

    # Backup to encrypted pool (should have been manually created before!)
    #
    # Speed up by using --allow-empty --no-progress --no-holds
    #
    # It's safe to use --no-holds as long as the user doesn't manually delete datasets/snapshots on the backup target
    # It also helps to prevent the following error:
    # ! [Source] STDERR > cannot hold snapshot 'data@offsite1-20220409123946': tag already exists on this dataset
    #
    # Use --rollback to make backup target consistent with the last snapshot (undo changes made to the dataset)
    # This won't result in extra data needing to be send
    # Normally, rollback shouldn't have to do anything (there shouldn't be changes after the last backup)
    # Also the pool is set to readonly to prevent accidental changes
    # Both of these measures help prevent this error:
    # "cannot receive incremental stream: destination has been modified since most recent snapshot"

    echo "BACKUP to pool ${POOL}"
    zfs-autobackup -v ${POOL} ${POOL} --encrypt --allow-empty --no-progress --no-holds --rollback

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
OUTPUT=$(main)
echo "${OUTPUT}"

# TODO: actually check output of above commands to determine success
SUBJECT="SUCCESSFULLY COMPLETED BACKUP"
