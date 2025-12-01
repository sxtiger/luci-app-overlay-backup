#!/bin/sh

# Overlay Restore Script for OpenWrt
# Handles restoration of overlay filesystem correctly

LOG_FILE="/tmp/overlay_restore.log"

log() {
	local level="$1"
	local message="$2"
	local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
	echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Find the actual overlay upper directory
find_overlay_upper() {
	if [ -d "/overlay/upper" ]; then
		echo "/overlay/upper"
	elif [ -d "/overlay" ]; then
		local upperdir=$(mount | grep "overlay" | grep -oE "upperdir=[^,)]+" | cut -d= -f2)
		if [ -n "$upperdir" ] && [ -d "$upperdir" ]; then
			echo "$upperdir"
		else
			echo "/overlay"
		fi
	else
		echo ""
	fi
}

list_backup_files() {
	local search_path="$1"
	[ -z "$search_path" ] && search_path="/tmp/upload"
	
	echo '{"backups":['
	local first=1
	if [ -d "$search_path" ]; then
		for f in "$search_path"/*_backup_*.tar.gz "$search_path"/backup.tar.gz; do
			[ -f "$f" ] || continue
			local filename=$(basename "$f")
			local filesize=$(ls -lh "$f" | awk '{print $5}')
			local filedate=$(stat -c "%Y" "$f" 2>/dev/null || stat -f "%m" "$f" 2>/dev/null)
			local formatted_date=$(date -d "@$filedate" '+%Y-%m-%d %H:%M' 2>/dev/null || date -r "$filedate" '+%Y-%m-%d %H:%M' 2>/dev/null || ls -l "$f" | awk '{print $6, $7, $8}')
			[ $first -eq 0 ] && echo ","
			echo "{\"path\":\"$f\",\"filename\":\"$filename\",\"size\":\"$filesize\",\"date\":\"$formatted_date\"}"
			first=0
		done
	fi
	echo ']}'
}

validate_backup_file() {
	local backup_file="$1"
	
	if [ ! -f "$backup_file" ]; then
		echo '{"valid":false,"message":"File not found"}'
		return 1
	fi
	
	# Check if it's a valid gzip archive
	if ! gzip -t "$backup_file" 2>/dev/null; then
		echo '{"valid":false,"message":"Invalid gzip archive"}'
		return 1
	fi
	
	# Check if it's a valid tar archive
	if ! tar -tzf "$backup_file" >/dev/null 2>&1; then
		echo '{"valid":false,"message":"Invalid tar archive"}'
		return 1
	fi
	
	# Check for overlay_backup.tar.gz inside
	local has_overlay=$(tar -tzf "$backup_file" 2>/dev/null | grep -c "overlay_backup.tar.gz")
	if [ "$has_overlay" -eq 0 ]; then
		echo '{"valid":false,"message":"No overlay backup found in archive"}'
		return 1
	fi
	
	echo '{"valid":true,"message":"Backup file is valid"}'
	return 0
}

restore() {
	local backup_file="$1"
	local auto_reboot="$2"
	
	[ -z "$auto_reboot" ] && auto_reboot="1"
	
	log "INFO" "Starting restore process..."
	log "INFO" "Backup file: $backup_file"
	
	# Validate backup file
	if [ ! -f "$backup_file" ]; then
		log "ERROR" "Backup file not found: $backup_file"
		echo '{"success":false,"message":"Backup file not found"}'
		return 1
	fi
	
	# Find overlay directory
	local overlay_dir=$(find_overlay_upper)
	
	if [ -z "$overlay_dir" ] || [ ! -d "$overlay_dir" ]; then
		log "ERROR" "Overlay directory not found"
		echo '{"success":false,"message":"Overlay directory not found"}'
		return 1
	fi
	
	log "INFO" "Target overlay directory: $overlay_dir"
	
	# Create temp directory
	local temp_dir="/tmp/overlay_restore_temp_$$"
	rm -rf "$temp_dir" 2>/dev/null
	mkdir -p "$temp_dir"
	
	cd "$temp_dir" || {
		log "ERROR" "Failed to create temp directory"
		echo '{"success":false,"message":"Failed to create temp directory"}'
		return 1
	}
	
	# Extract outer archive
	log "INFO" "Extracting backup archive..."
	tar -xzf "$backup_file" -C "$temp_dir" 2>/dev/null
	if [ $? -ne 0 ]; then
		log "ERROR" "Failed to extract backup archive"
		rm -rf "$temp_dir"
		echo '{"success":false,"message":"Failed to extract archive"}'
		return 1
	fi
	
	# Check for overlay backup
	if [ ! -f "$temp_dir/overlay_backup.tar.gz" ]; then
		log "ERROR" "overlay_backup.tar.gz not found in archive"
		rm -rf "$temp_dir"
		echo '{"success":false,"message":"Invalid backup format - missing overlay data"}'
		return 1
	fi
	
	# Check backup metadata if available
	if [ -f "$temp_dir/backup_meta.txt" ]; then
		log "INFO" "Backup metadata found:"
		cat "$temp_dir/backup_meta.txt" >> "$LOG_FILE"
	fi
	
	# Verify overlay backup archive
	log "INFO" "Verifying overlay backup archive..."
	if ! tar -tzf "$temp_dir/overlay_backup.tar.gz" >/dev/null 2>&1; then
		log "ERROR" "Overlay backup archive is corrupted"
		rm -rf "$temp_dir"
		echo '{"success":false,"message":"Overlay backup is corrupted"}'
		return 1
	fi
	
	# Count files in backup
	local backup_files=$(tar -tzf "$temp_dir/overlay_backup.tar.gz" 2>/dev/null | wc -l)
	log "INFO" "Backup contains $backup_files items"
	
	# Sync filesystem before restore
	log "INFO" "Syncing filesystem..."
	sync
	
	# Restore overlay filesystem
	log "INFO" "Restoring overlay filesystem to: $overlay_dir"
	
	# Extract overlay backup to the correct directory
	# The backup was created with relative paths, so we extract directly to overlay_dir
	cd "$overlay_dir" || {
		log "ERROR" "Failed to access overlay directory"
		rm -rf "$temp_dir"
		echo '{"success":false,"message":"Failed to access overlay directory"}'
		return 1
	}
	
	# Extract with overwrite
	tar -xzf "$temp_dir/overlay_backup.tar.gz" --overwrite 2>/dev/null
	local restore_result=$?
	
	if [ $restore_result -ne 0 ]; then
		log "ERROR" "Failed to restore overlay (tar exit code: $restore_result)"
		rm -rf "$temp_dir"
		echo '{"success":false,"message":"Failed to restore overlay"}'
		return 1
	fi
	
	# Cleanup
	rm -rf "$temp_dir"
	
	# Sync after restore
	log "INFO" "Syncing filesystem after restore..."
	sync
	
	log "INFO" "Restore completed successfully"
	
	if [ "$auto_reboot" = "1" ]; then
		log "INFO" "System will reboot in 5 seconds..."
		echo '{"success":true,"message":"Restore complete, rebooting...","reboot":true}'
		
		# Sync and reboot
		sync
		sleep 5
		reboot -f
	else
		echo '{"success":true,"message":"Restore complete, please reboot manually","reboot":false}'
	fi
	
	return 0
}

get_backup_info() {
	local backup_file="$1"
	
	if [ ! -f "$backup_file" ]; then
		echo '{"success":false,"message":"File not found"}'
		return 1
	fi
	
	local temp_dir="/tmp/overlay_info_temp_$$"
	rm -rf "$temp_dir" 2>/dev/null
	mkdir -p "$temp_dir"
	
	# Extract info files
	tar -xzf "$backup_file" -C "$temp_dir" openwrt_release backup_meta.txt 2>/dev/null
	
	local info=""
	
	if [ -f "$temp_dir/backup_meta.txt" ]; then
		info=$(cat "$temp_dir/backup_meta.txt" | tr '\n' ' ' | sed 's/"/\\"/g')
	elif [ -f "$temp_dir/openwrt_release" ]; then
		info=$(cat "$temp_dir/openwrt_release" | tr '\n' ' ' | sed 's/"/\\"/g')
	else
		info="No release info available"
	fi
	
	rm -rf "$temp_dir"
	
	echo "{\"success\":true,\"info\":\"$info\"}"
}

# Initialize log file
> "$LOG_FILE"

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
		exit 1
		;;
esac
