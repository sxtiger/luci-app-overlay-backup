#!/bin/sh

# Overlay Backup Script for OpenWrt
# Handles backup of overlay filesystem correctly

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
	
	# Clean up revision (remove special chars)
	distrib_revision=$(echo "$distrib_revision" | sed 's/[^a-zA-Z0-9._-]//g')
	
	echo "${distrib_id}_${distrib_release}_${distrib_revision}_backup_${timestamp}.tar.gz"
}

get_mounted_devices() {
	mount | grep -E "^/dev/(sd|mmcblk|nvme)" | awk '{print $3}' | while read mnt; do
		if [ -d "$mnt" ] && [ -w "$mnt" ]; then
			echo "$mnt"
		fi
	done
}

# Find the actual overlay upper directory
find_overlay_upper() {
	# Check common overlay mount points
	if [ -d "/overlay/upper" ]; then
		echo "/overlay/upper"
	elif [ -d "/overlay" ]; then
		# Check if /overlay itself contains the modified files
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

backup() {
	local backup_path="$1"
	
	[ -z "$backup_path" ] && backup_path="/tmp/upload"
	
	# Create backup directory
	if ! mkdir -p "$backup_path" 2>/dev/null; then
		log "ERROR" "Failed to create backup directory: $backup_path"
		echo '{"success":false,"message":"Failed to create backup directory"}'
		return 1
	fi
	
	# Check if writable
	if [ ! -w "$backup_path" ]; then
		log "ERROR" "Backup directory is not writable: $backup_path"
		echo '{"success":false,"message":"Backup directory is not writable"}'
		return 1
	fi
	
	log "INFO" "Starting backup process..."
	log "INFO" "Backup path: $backup_path"
	
	local backup_filename=$(generate_backup_filename)
	local temp_dir="/tmp/overlay_backup_temp_$$"
	
	# Clean up any existing temp dir
	rm -rf "$temp_dir" 2>/dev/null
	mkdir -p "$temp_dir"
	
	cd "$temp_dir" || {
		log "ERROR" "Failed to enter temporary directory"
		echo '{"success":false,"message":"Failed to create temp directory"}'
		return 1
	}
	
	# Backup package feeds configuration
	log "INFO" "Backing up package feeds configuration..."
	if [ -f /etc/opkg/distfeeds.conf ]; then
		cp /etc/opkg/distfeeds.conf distfeeds.conf 2>/dev/null
	fi
	if [ -f /etc/opkg/customfeeds.conf ]; then
		cp /etc/opkg/customfeeds.conf customfeeds.conf 2>/dev/null
	fi
	
	# Backup installed packages list
	log "INFO" "Backing up installed packages list..."
	opkg list-installed > packages-list.txt 2>/dev/null
	
	# Backup user-installed packages (not part of base system)
	opkg list-user-installed > packages-user.txt 2>/dev/null || true
	
	# Backup system release info
	log "INFO" "Backing up system release info..."
	[ -f /etc/openwrt_release ] && cp /etc/openwrt_release openwrt_release
	[ -f /etc/os-release ] && cp /etc/os-release os-release 2>/dev/null
	
	# Find overlay directory
	local overlay_dir=$(find_overlay_upper)
	
	if [ -z "$overlay_dir" ] || [ ! -d "$overlay_dir" ]; then
		log "ERROR" "Overlay directory not found"
		rm -rf "$temp_dir"
		echo '{"success":false,"message":"Overlay directory not found"}'
		return 1
	fi
	
	log "INFO" "Found overlay directory: $overlay_dir"
	
	# Check if overlay has content
	local file_count=$(find "$overlay_dir" -type f 2>/dev/null | wc -l)
	log "INFO" "Overlay contains $file_count files"
	
	if [ "$file_count" -eq 0 ]; then
		log "WARNING" "Overlay directory is empty"
	fi
	
	# Backup overlay filesystem using relative paths
	# This is critical for correct restoration
	log "INFO" "Backing up overlay filesystem..."
	
	cd "$overlay_dir" || {
		log "ERROR" "Failed to enter overlay directory"
		rm -rf "$temp_dir"
		echo '{"success":false,"message":"Failed to access overlay"}'
		return 1
	}
	
	# Create tar with relative paths (no leading /)
	# Exclude work directory and other non-essential items
	tar -czf "$temp_dir/overlay_backup.tar.gz" \
		--exclude='./work' \
		--exclude='./upper/work' \
		--exclude='./.fs_state' \
		--exclude='*.pid' \
		--exclude='*.lock' \
		. 2>/dev/null
	
	local tar_result=$?
	
	cd "$temp_dir"
	
	if [ $tar_result -ne 0 ]; then
		log "ERROR" "Failed to backup overlay filesystem (tar exit code: $tar_result)"
		rm -rf "$temp_dir"
		echo '{"success":false,"message":"Failed to backup overlay"}'
		return 1
	fi
	
	# Verify the backup archive
	if [ ! -s "$temp_dir/overlay_backup.tar.gz" ]; then
		log "ERROR" "Backup archive is empty"
		rm -rf "$temp_dir"
		echo '{"success":false,"message":"Backup archive is empty"}'
		return 1
	fi
	
	# Create metadata file
	cat > "$temp_dir/backup_meta.txt" << EOF
backup_version=2
backup_date=$(date '+%Y-%m-%d %H:%M:%S')
overlay_source=$overlay_dir
file_count=$file_count
openwrt_version=$(get_release_info "DISTRIB_RELEASE")
openwrt_revision=$(get_release_info "DISTRIB_REVISION")
EOF
	
	# Create final backup archive
	log "INFO" "Creating final backup archive..."
	tar -czf "${backup_path}/${backup_filename}" \
		backup_meta.txt \
		distfeeds.conf \
		customfeeds.conf \
		packages-list.txt \
		packages-user.txt \
		openwrt_release \
		os-release \
		overlay_backup.tar.gz 2>/dev/null
	
	if [ $? -eq 0 ] && [ -f "${backup_path}/${backup_filename}" ]; then
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
			local filedate=$(stat -c "%Y" "$f" 2>/dev/null || stat -f "%m" "$f" 2>/dev/null)
			local formatted_date=$(date -d "@$filedate" '+%Y-%m-%d %H:%M' 2>/dev/null || date -r "$filedate" '+%Y-%m-%d %H:%M' 2>/dev/null || ls -l "$f" | awk '{print $6, $7, $8}')
			[ $first -eq 0 ] && echo ","
			echo "{\"path\":\"$f\",\"filename\":\"$filename\",\"size\":\"$filesize\",\"date\":\"$formatted_date\"}"
			first=0
		done
	fi
	echo ']}'
}

list_mounted() {
	echo '{"mounted":['
	echo '"/tmp/upload"'
	get_mounted_devices | while read mnt; do
		[ -n "$mnt" ] && echo ",\"$mnt\""
	done
	echo ']}'
}

# Initialize log file
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
