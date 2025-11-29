#!/bin/sh

# Overlay Restore Script for OpenWrt/iStoreOS
# This script restores the overlay filesystem from a backup

LOG_FILE="/tmp/overlay_restore.log"

log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    echo "[$timestamp] [$level] $message"
}

list_backup_files() {
    local search_path="$1"
    [ -z "$search_path" ] && search_path="/tmp/upload"
    
    if [ -d "$search_path" ]; then
        find "$search_path" -maxdepth 1 -name "*_backup_*.tar.gz" -type f 2>/dev/null | while read file; do
            if [ -f "$file" ]; then
                local filename=$(basename "$file")
                local filesize=$(ls -lh "$file" | awk '{print $5}')
                local filedate=$(ls -l "$file" | awk '{print $6, $7, $8}')
                echo "$file|$filename|$filesize|$filedate"
            fi
        done
    fi
}

validate_backup_file() {
    local backup_file="$1"
    
    if [ ! -f "$backup_file" ]; then
        log "ERROR" "Backup file not found: $backup_file"
        return 1
    fi
    
    # Check if it's a valid tar.gz file
    if ! tar -tzf "$backup_file" >/dev/null 2>&1; then
        log "ERROR" "Invalid backup file format: $backup_file"
        return 1
    fi
    
    # Check if it contains the required files
    local has_overlay=$(tar -tzf "$backup_file" 2>/dev/null | grep -c "overlay_backup.tar.gz")
    if [ "$has_overlay" -eq 0 ]; then
        log "ERROR" "Backup file does not contain overlay_backup.tar.gz"
        return 1
    fi
    
    log "INFO" "Backup file validated successfully"
    return 0
}

restore() {
    local backup_file="$1"
    local auto_reboot="$2"
    
    [ -z "$auto_reboot" ] && auto_reboot="1"
    
    log "INFO" "Starting restore process..."
    log "INFO" "Backup file: $backup_file"
    
    # Validate backup file
    if ! validate_backup_file "$backup_file"; then
        return 1
    fi
    
    local temp_dir="/tmp/overlay_restore_temp_$$"
    
    # Create temporary directory
    mkdir -p "$temp_dir"
    cd "$temp_dir" || {
        log "ERROR" "Failed to enter temporary directory"
        return 1
    }
    
    # Extract main backup archive
    log "INFO" "Extracting backup archive..."
    tar -xzf "$backup_file" -C "$temp_dir" 2>/dev/null
    if [ $? -ne 0 ]; then
        log "ERROR" "Failed to extract backup archive"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Check for overlay backup
    if [ ! -f "$temp_dir/overlay_backup.tar.gz" ]; then
        log "ERROR" "overlay_backup.tar.gz not found in backup"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Restore overlay filesystem
    log "INFO" "Restoring overlay filesystem..."
    tar -xzf "$temp_dir/overlay_backup.tar.gz" -C / 2>/dev/null
    if [ $? -ne 0 ]; then
        log "ERROR" "Failed to restore overlay filesystem"
        rm -rf "$temp_dir"
        return 1
    fi
    
    log "INFO" "Overlay filesystem restored successfully"
    
    # Cleanup
    rm -rf "$temp_dir"
    
    log "INFO" "Restore completed successfully"
    
    # Reboot if auto_reboot is enabled
    if [ "$auto_reboot" = "1" ]; then
        log "INFO" "System will reboot in 5 seconds..."
        sync
        sleep 5
        reboot
    else
        log "INFO" "Auto-reboot disabled. Please reboot manually to apply changes."
    fi
    
    return 0
}

get_backup_info() {
    local backup_file="$1"
    
    if [ ! -f "$backup_file" ]; then
        echo "ERROR: File not found"
        return 1
    fi
    
    local temp_dir="/tmp/overlay_info_temp_$$"
    mkdir -p "$temp_dir"
    
    # Extract only the release info
    tar -xzf "$backup_file" -C "$temp_dir" openwrt_release 2>/dev/null
    
    if [ -f "$temp_dir/openwrt_release" ]; then
        cat "$temp_dir/openwrt_release"
    fi
    
    rm -rf "$temp_dir"
}

# Clear log file at start
> "$LOG_FILE"

# Parse command line arguments
case "$1" in
    restore)
        restore "$2" "$3"
        ;;
    list)
        list_backup_files "$2"
        ;;
    validate)
        validate_backup_file "$2"
        ;;
    info)
        get_backup_info "$2"
        ;;
    *)
        echo "Usage: $0 {restore|list|validate|info} [file] [auto_reboot]"
        echo "  restore [file] [auto_reboot] - Restore from backup file"
        echo "  list [path]                  - List backup files in path"
        echo "  validate [file]              - Validate backup file"
        echo "  info [file]                  - Get backup file info"
        exit 1
        ;;
esac
