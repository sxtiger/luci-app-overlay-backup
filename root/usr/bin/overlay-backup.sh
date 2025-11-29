#!/bin/sh

LOG_FILE="/tmp/overlay_backup.log"

log() {
	local level="$1"
	local message="$2"
	local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
	echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
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
	
	[ -z "$distrib_id" ] && distrib_id="OpenWrt"
	[ -z "$distrib_release" ] && distrib_release="unknown"
	[ -z "$distrib_revision" ] && distrib_revision="0"
	
	echo "${distrib_id}_${distrib_release}_${distrib_revision}_backup_${timestamp}.tar.gz"
}

get_mounted_devices() {
	mount | grep -E "^/dev/(sd|mmcblk|nvme)" | awk '{print $3}' | while read mnt; do
		if [ -w "$mnt" ]; then
			echo "$mnt"
		fi
	done
}

backup() {
	local backup_path="$1"
	
	[ -z "$backup_path" ] && backup_path="/tmp/upload"
	
	if ! mkdir -p "$backup_path" 2>/dev/null; then
		log "ERROR" "Failed to create backup directory: $backup_path"
		echo '{"success":false,"message":"Failed to create backup directory"}'
		return 1
	fi
	
	if [ ! -w "$backup_path" ]; then
		log "ERROR" "Backup directory is not writable: $backup_path"
		echo '{"success":false,"message":"Backup directory is not writable"}'
		return 1
	fi
	
	log "INFO" "Starting backup process..."
	log "INFO" "Backup path: $backup_path"
	
	local backup_filename=$(generate_backup_filename)
	local temp_dir="/tmp/overlay_backup_temp_$$"
	
	mkdir -p "$temp_dir"
	cd "$temp_dir" || {
		log "ERROR" "Failed to enter temporary directory"
		echo '{"success":false,"message":"Failed to create temp directory"}'
		return 1
	}
	
	log "INFO" "Backing up package feeds configuration..."
	[ -f /etc/opkg/distfeeds.conf ] && cp /etc/opkg/distfeeds.conf distfeeds.conf
	
	log "INFO" "Backing up installed packages list..."
	opkg list-installed > packages-list.txt 2>/dev/null
	
	log "INFO" "Backing up system release info..."
	[ -f /etc/openwrt_release ] && cp /etc/openwrt_release openwrt_release
	
	log "INFO" "Backing up overlay filesystem..."
	if [ -d /overlay ]; then
		tar -czf overlay_backup.tar.gz /overlay 2>/dev/null
		if [ $? -ne 0 ]; then
			log "ERROR" "Failed to backup overlay filesystem"
			rm -rf "$temp_dir"
			echo '{"success":false,"message":"Failed to backup overlay"}'
			return 1
		fi
	else
		log "ERROR" "/overlay directory not found"
		rm -rf "$temp_dir"
		echo '{"success":false,"message":"/overlay not found"}'
		return 1
	fi
	
	log "INFO" "Creating final backup archive..."
	tar -czf "${backup_path}/${backup_filename}" \
		distfeeds.conf packages-list.txt openwrt_release overlay_backup.tar.gz 2>/dev/null
	
	if [ $? -eq 0 ]; then
		local file_size=$(ls -lh "${backup_path}/${backup_filename}" | awk '{print $5}')
		log "INFO" "Backup completed: ${backup_path}/${backup_filename}"
		log "INFO" "File size: $file_size"
		rm -rf "$temp_dir"
		echo "{\"success\":true,\"file\":\"${backup_path}/${backup_filename}\",\"filename\":\"${backup_filename}\",\"size\":\"${file_size}\"}"
		return 0
	else
		log "ERROR" "Failed to create backup archive"
		rm -rf "$temp_dir"
		echo '{"success":false,"message":"Failed to create archive"}'
		return 1
	fi
}

list_backups() {
	local backup_path="$1"
	[ -z "$backup_path" ] && backup_path="/tmp/upload"
	
	echo '{"backups":['
	local first=1
	if [ -d "$backup_path" ]; then
		for f in "$backup_path"/*_backup_*.tar.gz; do
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

list_mounted() {
	echo '{"mounted":['
	echo '"/tmp/upload"'
	get_mounted_devices | while read mnt; do
		echo ",\"$mnt\""
	done
	echo ']}'
}

> "$LOG_FILE"

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
		exit 1
		;;
esac
