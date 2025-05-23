#!/usr/bin/env bash

# qidea.sh - Sync JSON event logs from S3 and prepare them for viewing in IntelliJ IDEA
# Usage: qidea [options]
# Options:
#   --pull              Only sync files without opening IntelliJ IDEA
#   --min-age DURATION  Only sync files newer than this duration (e.g., 2h, 1d)
#   --max-age DURATION  Only sync files older than this duration (e.g., 12h, 7d)
#   --bucket NAME       Specify a different S3 bucket name
#   --date YYYY/MM/DD   Use a specific date instead of today
#   --verbose, -v       Increase verbosity (can be used multiple times)
#   --help, -h          Show this help message

# Set default configuration
QIDEA_CONFIG="${HOME}/.config/qidea/config"
DEFAULT_BUCKET="test:queue-history-handler-service-test"
DEFAULT_VERBOSITY=1  # 0=quiet, 1=normal, 2=verbose, 3=debug

# Initialize global variables
BUCKET_NAME=""
DATE_PATH=""
TARGET_DIR=""
TMP_DIR=""
VERBOSITY=""
RCLONE_OPTS=()
OPEN_IDEA=true

# Error codes
readonly E_SUCCESS=0
readonly E_GENERAL=1
readonly E_MKDIR=2
readonly E_RCLONE=3
readonly E_IDEA=4
readonly E_ARGS=5

#######################################
# Log messages with appropriate verbosity levels
# Arguments:
#   $1 - Required verbosity level to display this message
#   $2 - Message to log
#   $3 - Optional log level (INFO, WARN, ERROR, DEBUG)
# Returns:
#   None
#######################################
log() {
    local req_level=$1
    local message=$2
    local level=${3:-INFO}
    local timestamp

    # Only show message if verbosity is high enough
    if [[ ${VERBOSITY} -ge ${req_level} ]]; then
        timestamp=$(date '+%Y-%m-%d %H:%M:%S')

        # Color the output based on log level
        case ${level} in
            INFO)  echo -e "\033[0m${timestamp} [${level}] ${message}\033[0m" ;;
            WARN)  echo -e "\033[0;33m${timestamp} [${level}] ${message}\033[0m" >&2 ;;
            ERROR) echo -e "\033[0;31m${timestamp} [${level}] ${message}\033[0m" >&2 ;;
            DEBUG) echo -e "\033[0;36m${timestamp} [${level}] ${message}\033[0m" ;;
            *)     echo -e "\033[0m${timestamp} [${level}] ${message}\033[0m" ;;
        esac
    fi
}

#######################################
# Display help message
# Arguments:
#   None
# Returns:
#   None
#######################################
show_help() {
    sed -n 's/^# //p' "${BASH_SOURCE[0]}" | grep -v "!/usr/bin/env bash"
}

#######################################
# Parse command line arguments
# Arguments:
#   All command line arguments ($@)
# Returns:
#   0 on success, non-zero on failure
#######################################
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --pull)
                OPEN_IDEA=false
                shift
                ;;
            --min-age)
                if [[ -z "$2" || "$2" == --* ]]; then
                    log 0 "Error: --min-age requires a duration argument" "ERROR"
                    return ${E_ARGS}
                fi
                RCLONE_OPTS+=("--min-age" "$2")
                shift 2
                ;;
            --max-age)
                if [[ -z "$2" || "$2" == --* ]]; then
                    log 0 "Error: --max-age requires a duration argument" "ERROR"
                    return ${E_ARGS}
                fi
                RCLONE_OPTS+=("--max-age" "$2")
                shift 2
                ;;
            --bucket)
                if [[ -z "$2" || "$2" == --* ]]; then
                    log 0 "Error: --bucket requires a name argument" "ERROR"
                    return ${E_ARGS}
                fi
                BUCKET_NAME="$2"
                shift 2
                ;;
            --date)
                if [[ -z "$2" || "$2" == --* ]]; then
                    log 0 "Error: --date requires a YYYY/MM/DD argument" "ERROR"
                    return ${E_ARGS}
                fi
                DATE_PATH="$2"
                shift 2
                ;;
            --verbose|-v)
                ((VERBOSITY++))
                shift
                ;;
            --help|-h)
                show_help
                exit ${E_SUCCESS}
                ;;
            *)
                log 0 "Unknown option: $1" "ERROR"
                show_help
                return ${E_ARGS}
                ;;
        esac
    done

    return ${E_SUCCESS}
}

#######################################
# Load configuration from file
# Arguments:
#   None
# Returns:
#   None
#######################################
load_config() {
    # Set defaults first
    BUCKET_NAME="${DEFAULT_BUCKET}"
    VERBOSITY="${DEFAULT_VERBOSITY}"

    # Load from config file if it exists
    if [[ -f "${QIDEA_CONFIG}" ]]; then
        log 2 "Loading configuration from ${QIDEA_CONFIG}" "DEBUG"
        # shellcheck source=/dev/null
        source "${QIDEA_CONFIG}"
    else
        log 2 "No configuration file found at ${QIDEA_CONFIG}" "DEBUG"
    fi

    # Set date path if not specified
    if [[ -z "${DATE_PATH}" ]]; then
        DATE_PATH=$(date +%Y/%m/%d)
    fi

    log 3 "Configuration: BUCKET_NAME=${BUCKET_NAME}, DATE_PATH=${DATE_PATH}, VERBOSITY=${VERBOSITY}" "DEBUG"
}

#######################################
# Setup directories and prepare environment
# Arguments:
#   None
# Returns:
#   0 on success, non-zero on failure
#######################################
setup_directories() {
    TARGET_DIR="$(pwd)/buckets/${DATE_PATH}"
    log 1 "Target directory: ${TARGET_DIR}"

    # Check if any symlink exists in the target_dir and use it to determine tmp_dir
    if [[ -d "${TARGET_DIR}" && $(find "${TARGET_DIR}" -type l 2>/dev/null | wc -l) -gt 0 ]]; then
        local first_link
        first_link=$(find "${TARGET_DIR}" -type l | head -n 1)
        TMP_DIR=$(dirname "$(readlink -f "${first_link}" 2>/dev/null || echo "")")

        if [[ ! -d "${TMP_DIR}" ]]; then
            log 1 "Source of existing symlinks is no longer present. Cleaning up symlinks..." "WARN"
            find "${TARGET_DIR}" -type l -exec rm {} + 2>/dev/null
            TMP_DIR=$(mktemp -d)
            log 1 "Created new temporary directory: ${TMP_DIR}"
        else
            log 2 "Found existing symlinks. Temp directory set to: ${TMP_DIR}" "DEBUG"
        fi
    else
        TMP_DIR=$(mktemp -d)
        log 1 "Created new temporary directory: ${TMP_DIR}"
    fi

    if ! mkdir -p "${TARGET_DIR}"; then
        log 0 "Failed to create target directory ${TARGET_DIR}" "ERROR"
        return ${E_MKDIR}
    else
        log 2 "Target directory ${TARGET_DIR} created successfully" "DEBUG"
    fi

    return ${E_SUCCESS}
}

#######################################
# Sync files from S3 using rclone
# Arguments:
#   None
# Returns:
#   0 on success, non-zero on failure
#######################################
sync_from_s3() {
    local start_time
    local end_time
    local duration

    log 1 "Starting rclone sync from bucket ${BUCKET_NAME}/${DATE_PATH}/ to ${TMP_DIR}..."

    # Add verbosity flags to rclone based on our verbosity level
    local rclone_verbosity=()
    if [[ ${VERBOSITY} -ge 3 ]]; then
        rclone_verbosity=("-vv")
    elif [[ ${VERBOSITY} -ge 2 ]]; then
        rclone_verbosity=("-v")
    fi

    start_time=$(date +%s)

    log 1 "Executing: rclone sync ${rclone_verbosity[*]} ${BUCKET_NAME}/${DATE_PATH}/ ${TMP_DIR} --progress --ignore-existing --transfers 8 --checkers 16 --stats 10s ${RCLONE_OPTS[*]}" "DEBUG"
    if ! rclone sync "${rclone_verbosity[@]}" "${BUCKET_NAME}/${DATE_PATH}/" "${TMP_DIR}" \
        --progress \
        --ignore-existing \
        --transfers 8 \
        --checkers 16 \
        --stats 10s \
        "${RCLONE_OPTS[@]}"; then
        log 0 "Failed to sync S3 bucket" "ERROR"
        return ${E_RCLONE}
    fi

    end_time=$(date +%s)
    duration=$((end_time - start_time))
    log 1 "rclone sync completed successfully in ${duration} seconds"

    return ${E_SUCCESS}
}

#######################################
# Create symlinks for JSON files
# Arguments:
#   None
# Returns:
#   0 on success, non-zero on failure
#######################################
create_symlinks() {
    local file_count=0
    local new_symlinks=0

    log 1 "Processing files in temp directory: ${TMP_DIR}"

    for file in "${TMP_DIR}"/*; do
        local symlink_path="${TARGET_DIR}/${file##*/}.json"
        if [[ -f "${file}" ]] && [[ ! -e "${symlink_path}" ]]; then
            ((file_count++))
            ln -s "${file}" "${symlink_path}"
            touch -r "${file}" "${symlink_path}" # use the timestamp of the original file
            ((new_symlinks++))
            log 3 "Created symlink: ${symlink_path} -> ${file}" "DEBUG"
        fi
    done

    log 1 "Processed ${file_count} files, created ${new_symlinks} new symlinks"

    return ${E_SUCCESS}
}

#######################################
# Open IntelliJ IDEA with the target directory
# Arguments:
#   None
# Returns:
#   0 on success, non-zero on failure
#######################################
open_intellij() {
    if [[ "${OPEN_IDEA}" == "true" ]]; then
        log 1 "Launching IntelliJ IDEA with directory: ${TARGET_DIR}"

        if [[ "${OPEN_IDEA}" == "true" ]]; then
            # Use exec to replace this process with IDEA, keeping terminal window open
            exec idea "${TARGET_DIR}"
            # Note: Code after exec will not be executed unless exec fails
            log 0 "Failed to exec IntelliJ IDEA" "ERROR"
            return ${E_IDEA}
        fi
    else
        log 1 "Skipping IntelliJ IDEA launch as requested"
    fi

    return ${E_SUCCESS}
}


#######################################
# Main function to orchestrate the workflow
# Arguments:
#   All command line arguments ($@)
# Returns:
#   0 on success, non-zero on failure
#######################################
qidea() {
    local exit_code

    # Enable error tracing and exit on error
    set -o errexit
    set -o pipefail

    log 2 "Starting qidea function execution..." "DEBUG"

    # Parse command line arguments
    if ! parse_args "$@"; then
        return ${E_ARGS}
    fi

    # Load configuration
    load_config

    # Setup directories
    if ! setup_directories; then
        return ${E_MKDIR}
    fi

    # Sync files from S3
    if ! sync_from_s3; then
        return ${E_RCLONE}
    fi

    # Create symlinks
    if ! create_symlinks; then
        return ${E_GENERAL}
    fi

    # Print success message
    log 1 "Sync completed successfully:"
    log 1 "  from: ${TMP_DIR}"
    log 1 "  to:   ${TARGET_DIR}"
    
    # Open IntelliJ IDEA
    if ! open_intellij; then
        return ${E_IDEA}
    fi

    # If we reach here, it means we're in pull-only mode (--pull option)
    if [[ "${OPEN_IDEA}" == "false" ]]; then
        log 1 "Files are available in: ${TARGET_DIR}"
    fi
    
    return ${E_SUCCESS}
}

# If this script is being executed directly (not sourced), run the function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    qidea "$@"
fi
