#!/usr/bin/env bash

# To be called by monitor.py

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# Init array
typeset -A CONFIG

# Set default values in CONFIG array
CONFIG=(
    [enabled]=false
    [email]=""
    [passphrase]=""
)

IS_BACKUP_POOL=false
POOL=$1
NEWLINE=$'\n'

# Parse config
# https://unix.stackexchange.com/a/206216
while read -r line; do
    if printf -- "%s" "$line" | grep -v '^#' | grep -F = &>/dev/null; then
        varname=$(printf -- "%s" "$line" | cut -d '=' -f 1)
        CONFIG[$varname]=$(printf -- "%s" "$line" | cut -d '=' -f 2-)
        if [[ $IS_BACKUP_POOL == false && $varname == backup_pool_* && ${CONFIG[$varname]} == $POOL ]]; then
            IS_BACKUP_POOL=true
        fi
    fi
done <"${SCRIPT_DIR}/config"

if ! [ "${CONFIG[enabled]}" = true ]; then
    echo "Skip, auto backup is disabled."
    exit
fi

if [[ $IS_BACKUP_POOL == false ]]; then
    echo "Pool ${POOL} is not a backup pool."
    exit
fi

cleanup() {

    OUTPUT+="${NEWLINE}EXPORT ${POOL}"
    zpool export ${POOL}
    # TODO: hint about 'zpool clear ${POOL}' when zpool export fails?

    # Only email if the email config value is not empty
    if ! [ -z "${CONFIG[email]}" ]; then

        if zpool list ${POOL} >/dev/null 2>&1; then
            MESSAGE="NOT safe for removal! Pool ${POOL} is still present."
        else
            MESSAGE="Should be SAFE to remove disk. Pool ${POOL} is no longer present."
        fi

        # Deactivate Python virtual environment for next commands
        (
            deactivate
            # Send email
            printf "%s\n\nFull log output:\n\n%s" "${MESSAGE}" "${OUTPUT}" | mail -s "${SUBJECT}" "${CONFIG[email]}"
        )
    fi
}

main() {
    set -euo pipefail
    # Duplicates stderr onto stdout
    exec 2>&1

    echo "START backup of datasets with zfs property 'autobackup:${POOL}' to pool ${POOL}"

    # TrueNAS won't automatically import the pool once the disk is connected, do so manually
    echo "IMPORT pool ${POOL} without mounting any filesystems"
    zpool import ${POOL} -N

    ENCRYPT=""

    # Use passphrase from config (if it exists) to unlock pool
    if ! [ -z "${CONFIG[passphrase]}" ]; then
        echo "UNLOCK pool ${POOL}"
        if ! echo "${CONFIG[passphrase]}" | zfs load-key "${POOL}"; then
            echo "FAILED to unlock pool"
            exit 1
        else
            echo "SUCCESSFULLY unlocked pool"
            ENCRYPT=" --encrypt"
        fi
    fi

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
    zfs-autobackup -v ${POOL} ${POOL} --allow-empty --no-progress --no-holds --rollback${ENCRYPT}

    # Make dataset readonly, to prevent accidental changes to the backup data
    # NOTE: perhaps instead use --set-properties to make backups readonly?
    zfs set readonly=on ${POOL}

    # TODO: use zfs-autoverify to check backup integrity
}

SUBJECT="ERROR making backup"
trap cleanup EXIT

# Make beep sound
echo -en "\a" >/dev/tty5

# Capture main output, to send log via email
OUTPUT=$(main)

# If we made it until here, no errors happened
SUBJECT="SUCCESSFULLY completed backup"
