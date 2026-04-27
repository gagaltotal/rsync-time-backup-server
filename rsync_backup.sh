#!/usr/bin/env bash

# =============================================================================
# Rsync Backup Script Server - version 1.0.2
# =============================================================================

APPNAME=$(basename "$0" | sed "s/\.sh$//")
BOLD='\033[1m'
RESET='\033[0m'

set -o pipefail
set -o nounset

MAX_SPACE_RETRIES=5

# =============================================================================
# Banner
# =============================================================================

banner() {
        echo -e "${BOLD}
  ██████╗ ███████╗██╗   ██╗███╗   ██╗ ██████╗    ███████╗███████╗██████╗ ██╗   ██╗███████╗██████╗
  ██╔══██╗██╔════╝╚██╗ ██╔╝████╗  ██║██╔════╝    ██╔════╝██╔════╝██╔══██╗██║   ██║██╔════╝██╔══██╗
  ██████╔╝███████╗ ╚████╔╝ ██╔██╗ ██║██║         ███████╗█████╗  ██████╔╝██║   ██║█████╗  ██████╔╝
  ██╔══██╗╚════██║  ╚██╔╝  ██║╚██╗██║██║         ╚════██║██╔══╝  ██╔══██╗╚██╗ ██╔╝██╔══╝  ██╔══██╗
  ██║  ██║███████║   ██║   ██║ ╚████║╚██████╗    ███████║███████╗██║  ██║ ╚████╔╝ ███████╗██║  ██║
  ╚═╝  ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═══╝ ╚═════╝    ╚══════╝╚══════╝╚═╝  ╚═╝  ╚═══╝  ╚══════╝╚═╝  ╚═╝
  Rsync Backup Script Server - version 1.0.2
  Author: ghostgtr666 - github.com/gagaltotal
${RESET}"
}

banner

# =============================================================================
# Log functions
# =============================================================================

fn_log_info()  { printf '%s: %s\n' "$APPNAME" "$1"; }
fn_log_warn()  { printf '%s: [WARNING] %s\n' "$APPNAME" "$1" >&2; }
fn_log_error() { printf '%s: [ERROR] %s\n' "$APPNAME" "$1" >&2; }

fn_ssh_cmd_to_string() {
        if [ ${#SSH_CMD[@]} -gt 0 ]; then
                printf '%s' "${SSH_CMD[*]}"
        fi
}

fn_log_info_cmd() {
        local message="$1"
        if [ -n "${SSH_DEST_FOLDER_PREFIX:-}" ]; then
                printf '%s: %s '\''%s'\''\n' "$APPNAME" "$(fn_ssh_cmd_to_string)" "$message"
        else
                printf '%s: %s\n' "$APPNAME" "$message"
        fi
}

# =============================================================================
# SSH functions
# =============================================================================

fn_is_ssh_target() {
        [[ "$1" =~ ^([A-Za-z0-9._%+\-]+)@([A-Za-z0-9.\-]+):(.+)$ ]]
}

fn_build_ssh_cmd() {
        SSH_CMD=(ssh -p "$SSH_PORT")
        if [ -n "$ID_RSA" ]; then
                SSH_CMD+=( -i "$ID_RSA" )
        fi
        SSH_CMD+=( "${SSH_USER}@${SSH_HOST}" )
}

fn_parse_ssh() {
        if fn_is_ssh_target "$DEST_FOLDER"; then
                SSH_USER=${BASH_REMATCH[1]}
                SSH_HOST=${BASH_REMATCH[2]}
                SSH_DEST_FOLDER=${BASH_REMATCH[3]}
                SSH_DEST_FOLDER_PREFIX="${SSH_USER}@${SSH_HOST}:"
                fn_build_ssh_cmd
        elif fn_is_ssh_target "$SRC_FOLDER"; then
                SSH_USER=${BASH_REMATCH[1]}
                SSH_HOST=${BASH_REMATCH[2]}
                SSH_SRC_FOLDER=${BASH_REMATCH[3]}
                SSH_SRC_FOLDER_PREFIX="${SSH_USER}@${SSH_HOST}:"
                fn_build_ssh_cmd
        fi
}

# =============================================================================
# Shell escape utility — properly escape arguments for remote shell execution
# =============================================================================

fn_shell_escape() {
        printf '%q' "$1"
}

# =============================================================================
# Command execution functions
# =============================================================================

fn_run_cmd() {
        local command="$1"
        if [ -n "${SSH_DEST_FOLDER_PREFIX:-}" ]; then
                "${SSH_CMD[@]}" "$command"
        else
                bash -c "$command"
        fi
}

fn_run_cmd_src() {
        local command="$1"
        if [ -n "${SSH_SRC_FOLDER_PREFIX:-}" ]; then
                "${SSH_CMD[@]}" "$command"
        else
                bash -c "$command"
        fi
}

fn_find() {
        local target="$1"
        shift
        local extra="$*"
        if [ -n "$extra" ]; then
                fn_run_cmd "find $(fn_shell_escape "$target") $extra"
        else
                fn_run_cmd "find $(fn_shell_escape "$target")"
        fi
}

# =============================================================================
# Filesystem utility functions
# =============================================================================

fn_get_absolute_path() {
        fn_run_cmd "cd $(fn_shell_escape "$1") && pwd"
}

fn_mkdir() {
        fn_run_cmd "mkdir -p -- $(fn_shell_escape "$1")"
}

fn_rm_file() {
        fn_run_cmd "rm -f -- $(fn_shell_escape "$1")"
}

fn_rm_dir() {
        fn_run_cmd "rm -rf -- $(fn_shell_escape "$1")"
}

fn_touch() {
        fn_run_cmd "touch -- $(fn_shell_escape "$1")"
}

fn_ln() {
        fn_run_cmd "ln -s -- $(fn_shell_escape "$1") $(fn_shell_escape "$2")"
}

fn_test_file_exists_src() {
        fn_run_cmd_src "test -e $(fn_shell_escape "$1")"
}

fn_df_t_src() {
        fn_run_cmd_src "df -T $(fn_shell_escape "$1")"
}

fn_df_t() {
        fn_run_cmd "df -T $(fn_shell_escape "$1")"
}

# =============================================================================
# Signal handling — ensure clean exit on CTRL+C
# =============================================================================

fn_terminate_script() {
        fn_log_info "SIGINT caught."
        if [ -n "${INPROGRESS_FILE:-}" ] && [ -n "${DEST_FOLDER:-}" ]; then
                fn_rm_file "$INPROGRESS_FILE" 2>/dev/null || true
        fi
        exit 1
}

trap 'fn_terminate_script' SIGINT

# =============================================================================
# Usage display
# =============================================================================

fn_display_usage() {
        echo "Usage: $(basename "$0") [OPTION]... <[USER@HOST:]SOURCE> <[USER@HOST:]DESTINATION> [exclude-pattern-file]"
        echo ""
        echo "Options"
        echo " -p, --port             SSH port."
        echo " -h, --help             Display this help message."
        echo " -i, --id_rsa           Specify the private ssh key to use."
        echo " --rsync-get-flags      Display the default rsync flags that are used for backup. If using remote"
        echo "                        drive over SSH, --compress will be added."
        echo " --rsync-set-flags      Set the rsync flags that are going to be used for backup."
        echo " --rsync-append-flags   Append the rsync flags that are going to be used for backup."
        echo " --log-dir              Set the log file directory. If this flag is set, generated files will"
        echo "                        not be managed by the script - in particular they will not be"
        echo "                        automatically deleted."
        echo "                        Default: $LOG_DIR"
        echo " --log-to-destination   Set the log file directory to the destination directory. If this flag"
        echo "                        is set, generated files will not be managed by the script - in particular"
        echo "                        they will not be automatically deleted."
        echo " --strategy             Set the expiration strategy. Default: \"1:1 30:7 365:30\" means after one"
        echo "                        day, keep one backup per day. After 30 days, keep one backup every 7 days."
        echo "                        After 365 days keep one backup every 30 days."
        echo " --no-auto-expire       Disable automatically deleting backups when out of space. Instead an error"
        echo "                        is logged, and the backup is aborted."
        echo ""
        echo "For more detailed help"
}

# =============================================================================
# Date parsing
# =============================================================================

fn_parse_date() {
        case "$OSTYPE" in
                linux*|cygwin*|netbsd*)
                        date -d "${1:0:10} ${1:11:2}:${1:13:2}:${1:15:2}" +%s ;;
                FreeBSD*|darwin*)
                        date -j -f "%Y-%m-%d-%H%M%S" "$1" "+%s" ;;
                *)
                        local yy=$((10#${1:0:4}))
                        local mm=$((10#${1:5:2}))
                        local dd=$((10#${1:8:2}))
                        local hh=$((10#${1:11:2}))
                        local mi=$((10#${1:13:2}))
                        local ss=$((10#${1:15:2}))
                        perl -e 'use Time::Local; print timelocal('"$ss"','"$mi"','"$hh"','"$dd"','"$((mm - 1))"','"$yy"'),"\n";' ;;
        esac
}

# =============================================================================
# Backup management functions
# =============================================================================

fn_backup_marker_path() { echo "$1/backup.marker"; }

fn_find_backup_marker() { fn_find "$(fn_backup_marker_path "$1")" 2>/dev/null; }

fn_find_backups() {
        fn_run_cmd "find $(fn_shell_escape "$DEST_FOLDER/") -maxdepth 1 -type d -name '????-??-??-??????' -prune | sort -r"
}

fn_expire_backup() {
        local backup_path="$1"

        if [ -z "$(fn_find_backup_marker "$(dirname -- "$backup_path")")" ]; then
                fn_log_error "$backup_path is not on a backup destination - aborting."
                exit 1
        fi

        fn_log_info "Expiring $backup_path"
        fn_rm_dir "$backup_path"
}

fn_expire_backups() {
        local current_timestamp=$EPOCH
        local last_kept_timestamp=9999999999

        local backup_to_keep="$1"

        # Read backups into array safely using mapfile
        local backups=()
        mapfile -t backups < <(fn_find_backups | sort)

        local oldest_backup_to_keep="${backups[0]:-}"

        local backup_dir
        for backup_dir in "${backups[@]}"; do
                [ -z "$backup_dir" ] && continue

                local backup_date
                backup_date=$(basename "$backup_dir")
                local backup_timestamp
                backup_timestamp=$(fn_parse_date "$backup_date")

                if [ -z "$backup_timestamp" ]; then
                        fn_log_warn "Could not parse date: $backup_dir"
                        continue
                fi

                if [ "$backup_dir" == "$backup_to_keep" ]; then
                        break
                fi

                if [ "$backup_dir" == "$oldest_backup_to_keep" ]; then
                        last_kept_timestamp=$backup_timestamp
                        continue
                fi

                local strategy_token
                for strategy_token in $(echo "$EXPIRATION_STRATEGY" | tr " " "\n" | sort -r -n); do
                        IFS=':' read -r -a t <<< "$strategy_token"

                        local cut_off_timestamp=$((current_timestamp - ${t[0]} * 86400))
                        local cut_off_interval_days=${t[1]}

                        if [ "$backup_timestamp" -le "$cut_off_timestamp" ]; then

                                if [ "$cut_off_interval_days" -eq 0 ]; then
                                        fn_expire_backup "$backup_dir"
                                        break
                                fi

                                local last_kept_timestamp_days=$((last_kept_timestamp / 86400))
                                local backup_timestamp_days=$((backup_timestamp / 86400))
                                local interval_since_last_kept_days=$((backup_timestamp_days - last_kept_timestamp_days))

                                if [ "$interval_since_last_kept_days" -lt "$cut_off_interval_days" ]; then
                                        fn_expire_backup "$backup_dir"
                                        break
                                else
                                        last_kept_timestamp=$backup_timestamp
                                        break
                                fi
                        fi
                done
        done
}

# =============================================================================
# Variable initialization
# =============================================================================

SSH_USER=""
SSH_HOST=""
SSH_DEST_FOLDER=""
SSH_SRC_FOLDER=""
SSH_CMD=()
SSH_DEST_FOLDER_PREFIX=""
SSH_SRC_FOLDER_PREFIX=""
SSH_PORT="22"
ID_RSA=""

SRC_FOLDER=""
DEST_FOLDER=""
EXCLUSION_FILE=""
LOG_DIR="$HOME/.$APPNAME"
AUTO_DELETE_LOG="1"
LOG_TO_DEST="0"
EXPIRATION_STRATEGY="1:1 30:7 365:30"
AUTO_EXPIRE="1"

RSYNC_FLAGS="-D --numeric-ids --links --hard-links --one-file-system --itemize-changes --times --recursive --perms --owner --group --stats --human-readable"

# =============================================================================
# Argument parsing with proper validation
# =============================================================================

while [ $# -gt 0 ]; do
        case "$1" in
                -h|-\?|--help)
                        fn_display_usage
                        exit 0
                        ;;
                -p|--port)
                        if [ $# -lt 2 ]; then
                                fn_log_error "Option --port requires an argument."
                                exit 1
                        fi
                        shift
                        SSH_PORT="$1"
                        ;;
                -i|--id_rsa)
                        if [ $# -lt 2 ]; then
                                fn_log_error "Option --id_rsa requires an argument."
                                exit 1
                        fi
                        shift
                        ID_RSA="$1"
                        ;;
                --rsync-get-flags)
                        echo "$RSYNC_FLAGS"
                        exit 0
                        ;;
                --rsync-set-flags)
                        if [ $# -lt 2 ]; then
                                fn_log_error "Option --rsync-set-flags requires an argument."
                                exit 1
                        fi
                        shift
                        RSYNC_FLAGS="$1"
                        ;;
                --rsync-append-flags)
                        if [ $# -lt 2 ]; then
                                fn_log_error "Option --rsync-append-flags requires an argument."
                                exit 1
                        fi
                        shift
                        RSYNC_FLAGS="$RSYNC_FLAGS $1"
                        ;;
                --strategy)
                        if [ $# -lt 2 ]; then
                                fn_log_error "Option --strategy requires an argument."
                                exit 1
                        fi
                        shift
                        EXPIRATION_STRATEGY="$1"
                        ;;
                --log-dir)
                        if [ $# -lt 2 ]; then
                                fn_log_error "Option --log-dir requires an argument."
                                exit 1
                        fi
                        shift
                        LOG_DIR="$1"
                        AUTO_DELETE_LOG="0"
                        ;;
                --log-to-destination)
                        LOG_TO_DEST="1"
                        AUTO_DELETE_LOG="0"
                        ;;
                --no-auto-expire)
                        AUTO_EXPIRE="0"
                        ;;
                --)
                        shift
                        SRC_FOLDER="${1:-}"
                        DEST_FOLDER="${2:-}"
                        EXCLUSION_FILE="${3:-}"
                        break
                        ;;
                -*)
                        fn_log_error "Unknown option: \"$1\""
                        fn_log_info ""
                        fn_display_usage
                        exit 1
                        ;;
                *)
                        SRC_FOLDER="$1"
                        DEST_FOLDER="${2:-}"
                        EXCLUSION_FILE="${3:-}"
                        break
        esac

        shift
done

if [[ -z "$SRC_FOLDER" || -z "$DEST_FOLDER" ]]; then
        fn_display_usage
        exit 1
fi

# Remove trailing slash from destination
DEST_FOLDER="${DEST_FOLDER%/}"

# =============================================================================
# Parse SSH configuration
# =============================================================================

fn_parse_ssh

if [ -n "$SSH_DEST_FOLDER" ]; then
        DEST_FOLDER="$SSH_DEST_FOLDER"
fi

if [ -n "$SSH_SRC_FOLDER" ]; then
        SRC_FOLDER="$SSH_SRC_FOLDER"
fi

# =============================================================================
# Validate source folder exists
# =============================================================================

if ! fn_test_file_exists_src "${SRC_FOLDER}"; then
        fn_log_error "Source folder \"${SRC_FOLDER}\" does not exist - aborting."
        exit 1
fi

# Remove trailing slash from source
SRC_FOLDER="${SRC_FOLDER%/}"

# Validate that paths do not contain single quotes
for ARG in "$SRC_FOLDER" "$DEST_FOLDER" "$EXCLUSION_FILE"; do
        if [[ "$ARG" == *"'"* ]]; then
                fn_log_error 'Source and destination directories may not contain single quote characters.'
                exit 1
        fi
done

# =============================================================================
# Check that the destination drive is a backup drive
# =============================================================================

if [ -z "$(fn_find_backup_marker "$DEST_FOLDER")" ]; then
        fn_log_info "Safety check failed - the destination does not appear to be a backup folder or drive (marker file not found)."
        fn_log_info "If it is indeed a backup folder, you may add the marker file by running the following command:"
        fn_log_info ""
        fn_log_info_cmd "mkdir -p -- \"$DEST_FOLDER\" ; touch \"$(fn_backup_marker_path "$DEST_FOLDER")\""
        fn_log_info ""
        exit 1
fi

# =============================================================================
# Check source and destination file-system type (df -T /dest)
# =============================================================================

if [[ "$(fn_df_t_src "${SRC_FOLDER}" 2>/dev/null | awk '{print $2}' | grep -c -i -e "fat")" -gt 0 ]]; then
        fn_log_info "Source file-system is a version of FAT."
        fn_log_info "Using the --modify-window rsync parameter with value 2."
        RSYNC_FLAGS="${RSYNC_FLAGS} --modify-window=2"
elif [[ "$(fn_df_t "${DEST_FOLDER}" 2>/dev/null | awk '{print $2}' | grep -c -i -e "fat")" -gt 0 ]]; then
        fn_log_info "Destination file-system is a version of FAT."
        fn_log_info "Using the --modify-window rsync parameter with value 2."
        RSYNC_FLAGS="${RSYNC_FLAGS} --modify-window=2"
fi

# =============================================================================
# Setup additional variables
# =============================================================================

NOW=$(date +"%Y-%m-%d-%H%M%S")
EPOCH=$(date "+%s")
KEEP_ALL_DATE=$((EPOCH - 86400))
KEEP_DAILIES_DATE=$((EPOCH - 2678400))

DEST="$DEST_FOLDER/$NOW"
PREVIOUS_DEST="$(fn_find_backups | head -n 1)"
INPROGRESS_FILE="$DEST_FOLDER/backup.inprogress"
MYPID="$$"

# =============================================================================
# Create log folder if it doesn't exist
# =============================================================================

if [[ $LOG_TO_DEST == "1" ]]; then
        LOG_DIR="$DEST_FOLDER/.$APPNAME"
fi

if [ ! -d "$LOG_DIR" ]; then
        fn_log_info "Creating log folder in '$LOG_DIR'..."
        mkdir -- "$LOG_DIR"
fi

# =============================================================================
# Handle case where a previous backup failed or was interrupted
# =============================================================================

if [ -n "$(fn_find "$INPROGRESS_FILE")" ]; then
        if [ "$OSTYPE" == "cygwin" ]; then
                RUNNINGPID="$(fn_run_cmd "cat $(fn_shell_escape "$INPROGRESS_FILE")")"
                RUNNINGCMD="$(procps -wwfo cmd -p "$RUNNINGPID" --no-headers 2>/dev/null | grep "$APPNAME")"
                if [ $? -eq 0 ]; then
                        fn_log_error "Previous backup task is still active - aborting (command: $RUNNINGCMD)."
                        exit 1
                fi
        elif [[ "$OSTYPE" == "netbsd"* ]]; then
                RUNNINGPID="$(fn_run_cmd "cat $(fn_shell_escape "$INPROGRESS_FILE")")"
                if ps -axp "$RUNNINGPID" -o "command" 2>/dev/null | grep "$APPNAME" > /dev/null; then
                        fn_log_error "Previous backup task is still active - aborting."
                        exit 1
                fi
        else
                RUNNINGPID="$(fn_run_cmd "cat $(fn_shell_escape "$INPROGRESS_FILE")")"
                if ps -p "$RUNNINGPID" -o command 2>/dev/null | grep "$APPNAME" > /dev/null; then
                        fn_log_error "Previous backup task is still active - aborting."
                        exit 1
                fi
        fi

        if [ -n "$PREVIOUS_DEST" ]; then
                fn_log_info "$SSH_DEST_FOLDER_PREFIX$INPROGRESS_FILE already exists - the previous backup failed or was interrupted. Backup will resume from there."
                fn_run_cmd "mv -- $(fn_shell_escape "$PREVIOUS_DEST") $(fn_shell_escape "$DEST")"
                local_backup_count="$(fn_find_backups | wc -l)"
                if [ "$local_backup_count" -gt 1 ]; then
                        PREVIOUS_DEST="$(fn_find_backups | sed -n '2p')"
                else
                        PREVIOUS_DEST=""
                fi
                fn_run_cmd "echo $MYPID > $(fn_shell_escape "$INPROGRESS_FILE")"
        fi
fi

# =============================================================================
# Main backup loop with retry limit
# =============================================================================

retry_count=0

while [ $retry_count -lt $MAX_SPACE_RETRIES ]; do

        # =========================================================================
        # Check if we are doing an incremental backup (if previous backup exists)
        # =========================================================================
        LINK_DEST_OPTION=""
        if [ -z "$PREVIOUS_DEST" ]; then
                fn_log_info "No previous backup - creating new one."
        else
                PREVIOUS_DEST="$(fn_get_absolute_path "$PREVIOUS_DEST")"
                fn_log_info "Previous backup found - doing incremental backup from $SSH_DEST_FOLDER_PREFIX$PREVIOUS_DEST"
                LINK_DEST_OPTION="--link-dest=$(fn_shell_escape "$PREVIOUS_DEST")"
        fi

        # =========================================================================
        # Create destination folder if it doesn't already exist
        # =========================================================================
        if [ -z "$(fn_find "$DEST" "-type d" 2>/dev/null)" ]; then
                fn_log_info "Creating destination $SSH_DEST_FOLDER_PREFIX$DEST"
                fn_mkdir "$DEST"
        fi

        # =========================================================================
        # Purge certain old backups before beginning new backup
        # =========================================================================
        if [ -n "$PREVIOUS_DEST" ]; then
                fn_expire_backups "$PREVIOUS_DEST"
        else
                fn_expire_backups "$DEST"
        fi

        # =========================================================================
        # Start backup — build rsync command as an array (no eval)
        # =========================================================================
        LOG_FILE="$LOG_DIR/$(date +"%Y-%m-%d-%H%M%S").log"

        fn_log_info "Starting backup..."
        fn_log_info "From: $SSH_SRC_FOLDER_PREFIX$SRC_FOLDER/"
        fn_log_info "To:   $SSH_DEST_FOLDER_PREFIX$DEST/"

        RSYNC_CMD=(rsync)

        local effective_flags="$RSYNC_FLAGS"
        if [ ${#SSH_CMD[@]} -gt 0 ]; then
                effective_flags="$effective_flags --compress"
                if [ -n "$ID_RSA" ]; then
                        RSYNC_CMD+=( -e "ssh -p $SSH_PORT -i $ID_RSA -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" )
                else
                        RSYNC_CMD+=( -e "ssh -p $SSH_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" )
                fi
        fi

        read -ra FLAGS_ARRAY <<< "$effective_flags"
        RSYNC_CMD+=( "${FLAGS_ARRAY[@]}" )

        RSYNC_CMD+=( --log-file="$LOG_FILE" )

        if [ -n "$EXCLUSION_FILE" ]; then
                RSYNC_CMD+=( --exclude-from="$EXCLUSION_FILE" )
        fi

        if [ -n "$LINK_DEST_OPTION" ]; then
                RSYNC_CMD+=( "$LINK_DEST_OPTION" )
        fi

        RSYNC_CMD+=( -- "${SSH_SRC_FOLDER_PREFIX}${SRC_FOLDER}/" "${SSH_DEST_FOLDER_PREFIX}${DEST}/" )

        fn_log_info "Running command:"
        fn_log_info "${RSYNC_CMD[*]}"

        fn_run_cmd "echo $MYPID > $(fn_shell_escape "$INPROGRESS_FILE")"

        "${RSYNC_CMD[@]}"

        # =========================================================================
        # Check if we ran out of space
        # =========================================================================
        NO_SPACE_LEFT=""
        if [ -f "$LOG_FILE" ]; then
                NO_SPACE_LEFT="$(grep -E "No space left on device \(28\)|Result too large \(34\)" "$LOG_FILE" 2>/dev/null || true)"
        fi

        if [ -n "$NO_SPACE_LEFT" ]; then

                if [[ $AUTO_EXPIRE == "0" ]]; then
                        fn_log_error "No space left on device, and automatic purging of old backups is disabled."
                        fn_rm_file "$INPROGRESS_FILE"
                        exit 1
                fi

                fn_log_warn "No space left on device - removing oldest backup and resuming."

                local_backup_count="$(fn_find_backups | wc -l)"
                if [[ "$local_backup_count" -lt "2" ]]; then
                        fn_log_error "No space left on device, and no old backup to delete."
                        fn_rm_file "$INPROGRESS_FILE"
                        exit 1
                fi

                fn_expire_backup "$(fn_find_backups | tail -n 1)"

                retry_count=$((retry_count + 1))
                if [ $retry_count -ge $MAX_SPACE_RETRIES ]; then
                        fn_log_error "Maximum retry attempts ($MAX_SPACE_RETRIES) reached - aborting."
                        fn_rm_file "$INPROGRESS_FILE"
                        exit 1
                fi

                continue
        fi

        # =========================================================================
        # Check whether rsync reported any errors
        # =========================================================================
        EXIT_CODE="1"
        if [ -f "$LOG_FILE" ] && [ -n "$(grep "rsync error:" "$LOG_FILE" 2>/dev/null)" ]; then
                fn_log_error "Rsync reported an error. Run this command for more details: grep -E 'rsync:|rsync error:' '$LOG_FILE'"
        elif [ -f "$LOG_FILE" ] && [ -n "$(grep "rsync:" "$LOG_FILE" 2>/dev/null)" ]; then
                fn_log_warn "Rsync reported a warning. Run this command for more details: grep -E 'rsync:|rsync error:' '$LOG_FILE'"
        else
                fn_log_info "Backup completed without errors."
                if [[ $AUTO_DELETE_LOG == "1" ]]; then
                        rm -f -- "$LOG_FILE"
                fi
                EXIT_CODE="0"
        fi

        # =========================================================================
        # Add symlink to last backup
        # =========================================================================
        if [ "$EXIT_CODE" = "0" ]; then
                fn_rm_file "$DEST_FOLDER/latest"
                fn_ln "$(basename -- "$DEST")" "$DEST_FOLDER/latest"

                fn_rm_file "$INPROGRESS_FILE"
        fi

        exit $EXIT_CODE
done

fn_log_error "Unexpected exit from backup loop."
fn_rm_file "$INPROGRESS_FILE"
exit 1