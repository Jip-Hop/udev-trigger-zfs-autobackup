#!/usr/bin/env bash

set -euo pipefail

SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
cd ${SCRIPT_DIR}

STEPS=$(
    cat <<EOF
1. Manually create (encrypted) ZFS pool(s) on removable disk(s).
2. Manually edit config to specify the names of your backup pool(s) and the encryption passphrase.
3. Manually schedule trigger.sh to run at system startup. On TrueNAS SCALE: System Settings -> Advanced -> Init/Shutdown Scripts -> Add -> Description: trigger-zfs-autobackup; Type: Script; Script: /path/to/trigger.sh; When: Post Init -> Save
4. Manually insert backup disk whenever you want to make a backup.
5. Automatic backup is triggered and sends email on completion.
EOF
)

usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [-h] [-v] [--install]

Daemon to trigger zfs-autobackup when attaching backup disk.

$STEPS

Available options:

-h, --help      Print this help and exit
-v, --verbose   Print script debug info
-i, --install   Install dependencies
EOF
    exit
}

VENV="${SCRIPT_DIR}/venv"

# Default values of variables set from params
INSTALL=false

parse_params() {

    while :; do
        case "${1-}" in
        -h | --help) usage ;;
        -v | --verbose) set -x ;;
        -i | --install) INSTALL=true ;;
        -?*) die "Unknown option: $1" ;;
        *) break ;;
        esac
        shift
    done

    args=("$@")

    return 0
}

parse_params "$@"

if [ "$INSTALL" = true ]; then

    echo "Creating Python virtual environment..."
    # Create Python virtual environment (isolated from Python installation on TrueNAS SCALE)
    # Use --without-pip because ensurepip is not available.
    python3 -m venv "${VENV}" --without-pip

    # Activate the virtual environment
    . "${VENV}/bin/activate"

    # Install pip inside virtual environment
    curl -fSL https://bootstrap.pypa.io/get-pip.py | python3
    # Install our dependencies inside the virtual environment
    python3 -m pip install -r requirements.txt

    echo "Done installing!"
    echo "Follow these steps next:"
    echo ""
    echo -e "$STEPS"

    exit
fi

if ! [ -d "${VENV}" ]; then
    echo -e "Virtual environment not found at ${VENV}.\nDid you run \"${SCRIPT_NAME} --install\" yet?"
    exit
fi

# Activate the virtual environment
. "${VENV}/bin/activate"

# Export deactivate function and the variables it depends on,
# so child scripts can deactivate Python virtual environment
# https://stackoverflow.com/a/37216784
# export _OLD_VIRTUAL_PATH _OLD_VIRTUAL_PYTHONHOME _OLD_VIRTUAL_PS1 VIRTUAL_ENV
# export -f deactivate

# Start monitoring udev events
echo "Spawn monitor.py in the background..."
# (cd "${SCRIPT_DIR}" && python3 monitor.py &)
python3 monitor2.py config.yaml