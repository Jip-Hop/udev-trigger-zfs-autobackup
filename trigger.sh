#!/usr/bin/env bash

set -euo pipefail

SCRIPT_NAME=$(basename "${BASH_SOURCE[0]}")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

STEPS=$(
    cat <<EOF
1. Manually create (encrypted) ZFS pool(s) on removable disk(s).
2. Manually edit config to specify the names of your backup pool(s), the zfs-autobackup parameters and the encryption passphrase.
3. Manually schedule 'trigger.sh --start' to run at system startup.
   On TrueNAS SCALE: System Settings -> Advanced -> Init/Shutdown Scripts -> Add
    Description: trigger-zfs-autobackup;
    Type: Script;
    Script: '/path/to/trigger.sh --start /path/to/config.yaml';
    When: Post Init
   -> Save
4. Manually insert backup disk whenever you want to make a backup.
5. Automatic backup is triggered and sends email on completion.
EOF
)

usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [-h] [-v] [--install] [--start] [--stop]

Daemon to trigger zfs-autobackup when attaching backup disk.

$STEPS

Available options:

-h, --help                       Print this help and exit
-v, --verbose                    Print script debug info
-i, --install [HEAD,tag,hash]    Install dependencies
-s, --start /path/to/config.yaml Start the udev monitor
-p, --stop                       Stop the udev monitor

EOF
    exit
}

VENV="./venv"

# Default values of variables set from params
INSTALL=0
START=0
CONFIG_PATH=""
STOP=0
VERBOSE=0
INSTALL_PARAMS=""

# Define the GitHub repository URL
REPO_URL="https://github.com/ghan1t/udev-trigger-zfs-autobackup.git"

# Function to check if Git is installed
check_git() {
    if ! command -v git &> /dev/null; then
        echo "Git is not installed. Please install Git and try again."
        exit 1
    fi
}

# Function to check if the reference is likely a commit hash
is_commit_hash() {
    [[ $1 =~ ^[0-9a-f]{7,40}$ ]]
}

# Function to clone the repository
clone_repo() {
    local ref=$1

    # Print the current directory
    echo "Current directory: $(pwd)"

    # Ask the user for confirmation
    while true; do
        read -p "Do you want to install the script in this directory? (Y/N): " answer
        case $answer in
            [Yy]* ) 
                echo "Proceeding with installation..."
                # Insert installation commands here
                break
                ;;
            [Nn]* ) 
                echo "Installation aborted."
                exit 0
                ;;
            * ) 
                echo "Please answer Y or N."
                ;;
        esac
    done

    if [ -d "./.git" ]; then
        echo "Repository already exists. Updating..."
        git fetch --tags --depth 1
        if [ -z "$ref" ]; then
            ref=$(git describe --tags `git rev-list --tags --max-count=1`)
        elif [ "$ref" = "HEAD" ]; then
            ref="main"
        # If the ref is a commit hash, fetch the full history
        elif is_commit_hash "$ref"; then
            git fetch --unshallow
        fi
        git checkout $ref
    else
        if [ -z "$ref" ]; then
            echo "Cloning repository and checking out the newest tag..."
            git clone --depth 1 $REPO_URL .
            ref=$(git describe --tags `git rev-list --tags --max-count=1`)
            git checkout $ref
        elif [ "$ref" = "HEAD" ]; then
            echo "Cloning repository and checking out the HEAD of main branch..."
            git clone --branch main --depth 1 $REPO_URL .
        elif is_commit_hash "$ref"; then
            echo "Cloning repository for a specific commit..."
            git clone $REPO_URL .
            git checkout $ref
        else
            echo "Cloning repository and checking out $ref..."
            git clone --branch $ref --depth 1 $REPO_URL .
        fi
    fi
}

# Function to install Python dependencies
install_dependencies() {
    echo "Installing Python dependencies..."
    # Check if the virtual environment directory exists
    if [ -d "${VENV}" ]; then
        echo "Virtual environment already exists. Activating and updating dependencies."
    else
        echo "Creating Python virtual environment..."
        # Create Python virtual environment (isolated from Python installation on TrueNAS SCALE)
        # Use --without-pip because ensurepip is not available.
        python3 -m venv "${VENV}" --without-pip
    fi
    # Activate the virtual environment
    . "${VENV}/bin/activate"

    # Install pip inside virtual environment
    curl -fSL https://bootstrap.pypa.io/get-pip.py | python3
    # Install our dependencies inside the virtual environment
    python3 -m pip install -r requirements.txt
    
}

# Function to handle start
start_application() {
    cd ${SCRIPT_DIR}
    echo "Starting the application..."
    if ! [ -d "${VENV}" ]; then
        echo -e "Virtual environment not found at ${VENV}.\nDid you run \"${SCRIPT_NAME} --install\" yet?"
        exit
    fi
    # Activate the virtual environment
    echo "Activating python venv in ${VENV}"
    . "${VENV}/bin/activate"

    # Start monitoring udev events
    echo "Spawn monitor.py in the background..."
    (cd "${SCRIPT_DIR}" && python3 monitor.py $CONFIG_PATH &)
    # python3 monitor.py $CONFIG_PATH
}

# Function to handle stop
stop_application() {
    cd ${SCRIPT_DIR}
    echo "Stopping the application..."
    # Find the PID of the python process running 'monitor.py'
    pid=$(pgrep -f 'python.*monitor.py')

    # Check if the PID was found
    if [ -n "$pid" ]; then
        echo "Killing process with PID: $pid"
        kill "$pid"
    else
        echo "No running process found for 'monitor.py'"
    fi
}

parse_params() {

    while :; do
        case "${1-}" in
            -h | --help)
                usage
                ;;
            -v | --verbose) 
                set -x
                VERBOSE=1
                shift
                ;;
            -i | --install)
                INSTALL=1
                echo "install"
                shift
                if [ -z "${1-}" ] || [[ "${1-}" =~ ^- ]]; then
                    INSTALL_PARAMS="main"
                else
                    INSTALL_PARAMS="$1"
                    shift
                fi
                ;;
            -s | --start)
                START=1
                shift
                if [ -z "${1-}" ] || [[ "${1-}" =~ ^- ]]; then
                    die "missing path to config.yaml file"
                else
                    CONFIG_PATH="$1"
                    shift
                fi
                ;;
            -p | --stop)
                STOP=1
                shift
                ;;
            -?*) die "Unknown option: $1" ;;
            *) break ;;
        esac
    done

    args=("$@")

    return 0
}

die() {
    echo "$*" 1>&2
    exit 1
}

# Main function to parse arguments and control flow
main() { 

    check_git

    parse_params "$@"

    # Check if exactly one argument is provided
    # Sum the variables
    sum=$((INSTALL + START + STOP))
    if [ "$sum" -gt 1 ]; then
        die "Error: More than one variable is set to true."
    elif [ "$sum" -eq 0 ]; then
        usage
        exit
    fi

    if [ "$INSTALL" = 1 ]; then
        # checkout script from github
        clone_repo "$INSTALL_PARAMS"
        install_dependencies
        
        echo "Done installing!"
        echo "Follow these steps next:"
        echo ""
        echo -e "$STEPS"

        exit
    fi

    if [ "$START" = 1 ]; then
       start_application
       exit
    fi

    if [ "$STOP" = 1 ]; then
       stop_application
       exit
    fi
    
}

main "$@"