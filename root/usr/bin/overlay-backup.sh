#!/bin/sh

# Overlay Backup Script for OpenWrt/iStoreOS
# This script backs up the overlay filesystem along with package list and feeds config

LOG_FILE="/tmp/overlay_backup.log"

log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    echo "[$timestamp] [$level] $message"
}

get_release_info() {
    local key="$1"
    if [ -f /etc/openwrt_release ]; then
        grep "^${key}=" /etc/openwrt_release | cut -d"'" -f2
    else
        echo ""
    fi
}

generate_backup_filename() {
    local distrib_id=$(get_release_info "DISTRIB_ID")
    local distrib_release=$(get_release_info "DISTRIB_RELEASE")
    local distrib_revision=$(get_release_info "DISTRIB_REVISION")
    local timestamp=$(date '+%Y%m%d%H%M')
    
    # Default to OpenWrt if DISTRIB_ID is empty
    [ -z "$distrib_id" ] && distrib_id="OpenWrt"
    [ -z "$distrib_release" ] && distrib_release="unknown"
    [ -z "$distrib_revision" ] && distrib_revision="0"
    
    echo "${distrib_id}_${distrib_release}_${distrib_revision}_backup_${timestamp}.tar.gz"
}

get_mounted_devices() {
    # Get list of mounted storage devices (excluding system mounts)
    mount | grep -E "^/dev/(sd|mmcblk|nvme)" | awk '{print $3}' | while read mnt; do
        # Check if writable
        if [ -w "$mnt" ]; then
            echo "$mnt"
        fi
    done
}

backup() {
    local backup_path="$1"
    
    # Validate backup path
    if [ -z "$backup_path" ]; then
        backup_path="/tmp/upload"
    fi
    
    # Create backup directory if not exists
    if ! mkdir -p "$backup_path" 2>/dev/null; then
        log "ERROR" "Failed to create backup directory: $backup_path"
        return 1
    fi
    
    # Check if directory is writable
    if [ ! -w "$backup_path" ]; then
        log "ERROR" "Backup directory is not writable: $backup_path"
        return 1
    fi
    
    log "INFO" "Starting backup process..."
    log "INFO" "Backup path: $backup_path"
    
    # Generate backup filename
    local backup_filename=$(generate_backup_filename)
    local temp_dir="/tmp/overlay_backup_temp_$$"
    
    # Create temporary directory
    mkdir -p "$temp_dir"
    cd "$temp_dir" || {
        log "ERROR" "Failed to enter temporary directory"
        return 1
    }
    
    # Backup package feeds configuration
    log "INFO" "Backing up package feeds configuration..."
    if [ -f /etc/opkg/distfeeds.conf ]; then
        cp /etc/opkg/distfeeds.conf distfeeds.conf
    else
        log "WARNING" "distfeeds.conf not found, skipping..."
    fi
    
    # Backup installed packages list
    log "INFO" "Backing up installed packages list..."
    opkg list-installed > packages-list.txt 2>/dev/null
    
    # Backup system release info
    log "INFO" "Backing up system release info..."
    if [ -f /etc/openwrt_release ]; then
        cp /etc/openwrt_release openwrt_release
    fi
    
    # Backup overlay filesystem
    log "INFO" "Backing up overlay filesystem..."
    if [ -d /overlay ]; then
        tar -czf overlay_backup.tar.gz /overlay 2>/dev/null
        if [ $? -ne 0 ]; then
            log "ERROR" "Failed to backup overlay filesystem"
            rm -rf "$temp_dir"
            return 1
        fi
    else
        log "ERROR" "/overlay directory not found"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Create final backup archive
    log "INFO" "Creating final backup archive..."
    tar -czf "${backup_path}/${backup_filename}" distfeeds.conf packages-list.txt openwrt_release overlay_backup.tar.gz 2>/dev/null
    
    if [ $? -eq 0 ]; then
        log "INFO" "Backup completed successfully"
        log "INFO" "Backup file: ${backup_path}/${backup_filename}"
        
        # Get file size
        local file_size=$(ls -lh "${backup_path}/${backup_filename}" | awk '{print $5}')
        log "INFO" "Backup file size: $file_size"
        
        # Cleanup temporary directory
        rm -rf "$temp_dir"
        
        echo "${backup_path}/${backup_filename}"
        return 0
    else
        log "ERROR" "Failed to create final backup archive"
        rm -rf "$temp_dir"
        return 1
    fi
}

list_backups() {
    local backup_path="$1"
    [ -z "$backup_path" ] && backup_path="/tmp/upload"
    
    if [ -d "$backup_path" ]; then
        ls -la "$backup_path"/*_backup_*.tar.gz 2>/dev/null | while read line; do
            echo "$line"
        done
    fi
}

list_mounted() {
    get_mounted_devices
}

# Clear log file at start
> "$LOG_FILE"

# Parse command line arguments
case "$1" in
    backup)
        backup "$2"
        ;;
    list)
        list_backups "$2"
        ;;
    mounted)
        list_mounted
        ;;
    filename)
        generate_backup_filename
        ;;
    *)
        echo "Usage: $0 {backup|list|mounted|filename} [path]"
        echo "  backup [path]  - Create backup to specified path"
        echo "  list [path]    - List backup files in path"
        echo "  mounted        - List mounted storage devices"
        echo "  filename       - Generate backup filename"
        exit 1
        ;;
esac
