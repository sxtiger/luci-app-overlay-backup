#!/bin/sh

LOG_FILE="/tmp/overlay_restore.log"

log() {
	local level="$1"
	local message="$2"
	local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
	echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
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
			local filedate=$(ls -l "$f" | awk '{print $6, $7, $8}')
			[ $first -eq 0 ] && echo ","
			echo "{\"path\":\"$f\",\"filename\":\"$filename\",\"size\":\"$filesize\",\"date\":\"$filedate\"}"
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
	
	if ! tar -tzf "$backup_file" >/dev/null 2>&1; then
		echo '{"valid":false,"message":"Invalid archive format"}'
		return 1
	fi
	
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
	
	if [ ! -f "$backup_file" ]; then
		log "ERROR" "Backup file not found: $backup_file"
		echo '{"success":false,"message":"Backup file not found"}'
		return 1
	fi
	
	local temp_dir="/tmp/overlay_restore_temp_$$"
	mkdir -p "$temp_dir"
	cd "$temp_dir" || {
		log "ERROR" "Failed to create temp directory"
		echo '{"success":false,"message":"Failed to create temp directory"}'
		return 1
	}
	
	log "INFO" "Extracting backup archive..."
	tar -xzf "$backup_file" -C "$temp_dir" 2>/dev/null
	if [ $? -ne 0 ]; then
		log "ERROR" "Failed to extract backup archive"
		rm -rf "$temp_dir"
		echo '{"success":false,"message":"Failed to extract archive"}'
		return 1
	fi
	
	if [ ! -f "$temp_dir/overlay_backup.tar.gz" ]; then
		log "ERROR" "overlay_backup.tar.gz not found"
		rm -rf "$temp_dir"
		echo '{"success":false,"message":"Invalid backup format"}'
		return 1
	fi
	
	log "INFO" "Restoring overlay filesystem..."
	tar -xzf "$temp_dir/overlay_backup.tar.gz" -C / 2>/dev/null
	if [ $? -ne 0 ]; then
		log "ERROR" "Failed to restore overlay"
		rm -rf "$temp_dir"
		echo '{"success":false,"message":"Failed to restore overlay"}'
		return 1
	fi
	
	rm -rf "$temp_dir"
	log "INFO" "Restore completed successfully"
	
	if [ "$auto_reboot" = "1" ]; then
		log "INFO" "System will reboot in 5 seconds..."
		echo '{"success":true,"message":"Restore complete, rebooting...","reboot":true}'
		sync
		sleep 5
		reboot
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
	mkdir -p "$temp_dir"
	
	tar -xzf "$backup_file" -C "$temp_dir" openwrt_release 2>/dev/null
	
	if [ -f "$temp_dir/openwrt_release" ]; then
		echo '{"success":true,"info":"'
		cat "$temp_dir/openwrt_release" | tr '\n' ' ' | sed 's/"/\\"/g'
		echo '"}'
	else
		echo '{"success":true,"info":"No release info available"}'
	fi
	
	rm -rf "$temp_dir"
}

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
