-- LuCI Controller for Overlay Backup
-- Copyright 2024 GPL-3.0 License

module("luci.controller.overlay_backup", package.seeall)

function index()
    if not nixio.fs.access("/etc/config/overlay_backup") then
        return
    end
    
    local page = entry({"admin", "system", "overlay_backup"}, alias("admin", "system", "overlay_backup", "backup"), _("Overlay Backup"), 90)
    page.dependent = true
    page.acl_depends = { "luci-app-overlay-backup" }
    
    entry({"admin", "system", "overlay_backup", "backup"}, template("overlay_backup/backup"), _("Backup"), 1)
    entry({"admin", "system", "overlay_backup", "restore"}, template("overlay_backup/restore"), _("Restore"), 2)
    entry({"admin", "system", "overlay_backup", "settings"}, cbi("overlay_backup/settings"), _("Settings"), 3)
    entry({"admin", "system", "overlay_backup", "log"}, template("overlay_backup/log"), _("Log"), 4)
    
    -- API endpoints
    entry({"admin", "system", "overlay_backup", "api", "backup"}, call("action_backup")).leaf = true
    entry({"admin", "system", "overlay_backup", "api", "restore"}, call("action_restore")).leaf = true
    entry({"admin", "system", "overlay_backup", "api", "list_backups"}, call("action_list_backups")).leaf = true
    entry({"admin", "system", "overlay_backup", "api", "list_mounted"}, call("action_list_mounted")).leaf = true
    entry({"admin", "system", "overlay_backup", "api", "delete_backup"}, call("action_delete_backup")).leaf = true
    entry({"admin", "system", "overlay_backup", "api", "get_filename"}, call("action_get_filename")).leaf = true
    entry({"admin", "system", "overlay_backup", "api", "get_log"}, call("action_get_log")).leaf = true
    entry({"admin", "system", "overlay_backup", "api", "upload"}, call("action_upload"), nil).leaf = true
    entry({"admin", "system", "overlay_backup", "api", "backup_info"}, call("action_backup_info")).leaf = true
end

function action_backup()
    local http = require "luci.http"
    local uci = require "luci.model.uci".cursor()
    local sys = require "luci.sys"
    
    local backup_path = http.formvalue("path") or uci:get("overlay_backup", "main", "backup_path") or "/tmp/upload"
    
    local result = sys.exec("/usr/bin/overlay-backup.sh backup " .. luci.util.shellquote(backup_path) .. " 2>&1")
    local lines = {}
    for line in result:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end
    
    local backup_file = nil
    local success = false
    
    for _, line in ipairs(lines) do
        if line:match("%.tar%.gz$") and not line:match("%[") then
            backup_file = line
            success = true
        end
    end
    
    http.prepare_content("application/json")
    http.write_json({
        success = success,
        file = backup_file,
        log = result
    })
end

function action_restore()
    local http = require "luci.http"
    local uci = require "luci.model.uci".cursor()
    local sys = require "luci.sys"
    
    local backup_file = http.formvalue("file")
    local auto_reboot = uci:get("overlay_backup", "main", "auto_reboot") or "1"
    
    if not backup_file or backup_file == "" then
        http.prepare_content("application/json")
        http.write_json({
            success = false,
            message = "No backup file specified"
        })
        return
    end
    
    -- Validate file first
    local validate_result = sys.exec("/usr/bin/overlay-restore.sh validate " .. luci.util.shellquote(backup_file) .. " 2>&1")
    
    if validate_result:match("ERROR") then
        http.prepare_content("application/json")
        http.write_json({
            success = false,
            message = validate_result
        })
        return
    end
    
    -- Fork the restore process
    local pid = nixio.fork()
    if pid == 0 then
        -- Child process
        nixio.setsid()
        os.execute("/usr/bin/overlay-restore.sh restore " .. luci.util.shellquote(backup_file) .. " " .. auto_reboot .. " >/dev/null 2>&1 &")
        os.exit(0)
    end
    
    http.prepare_content("application/json")
    http.write_json({
        success = true,
        message = "Restore process started",
        auto_reboot = auto_reboot
    })
end

function action_list_backups()
    local http = require "luci.http"
    local uci = require "luci.model.uci".cursor()
    local sys = require "luci.sys"
    local fs = require "nixio.fs"
    
    local search_path = http.formvalue("path") or uci:get("overlay_backup", "main", "backup_path") or "/tmp/upload"
    
    local backups = {}
    local result = sys.exec("/usr/bin/overlay-restore.sh list " .. luci.util.shellquote(search_path) .. " 2>&1")
    
    for line in result:gmatch("[^\r\n]+") do
        local path, filename, size, date = line:match("([^|]+)|([^|]+)|([^|]+)|(.+)")
        if path and filename then
            table.insert(backups, {
                path = path,
                filename = filename,
                size = size,
                date = date
            })
        end
    end
    
    http.prepare_content("application/json")
    http.write_json({
        success = true,
        backups = backups
    })
end

function action_list_mounted()
    local http = require "luci.http"
    local sys = require "luci.sys"
    
    local mounted = {}
    local result = sys.exec("/usr/bin/overlay-backup.sh mounted 2>&1")
    
    for line in result:gmatch("[^\r\n]+") do
        if line ~= "" and not line:match("^%[") then
            table.insert(mounted, line)
        end
    end
    
    -- Always include /tmp/upload as an option
    table.insert(mounted, 1, "/tmp/upload")
    
    http.prepare_content("application/json")
    http.write_json({
        success = true,
        mounted = mounted
    })
end

function action_delete_backup()
    local http = require "luci.http"
    local fs = require "nixio.fs"
    
    local file = http.formvalue("file")
    
    if not file or file == "" then
        http.prepare_content("application/json")
        http.write_json({
            success = false,
            message = "No file specified"
        })
        return
    end
    
    -- Security check - only allow deleting backup files
    if not file:match("_backup_.*%.tar%.gz$") then
        http.prepare_content("application/json")
        http.write_json({
            success = false,
            message = "Invalid backup file"
        })
        return
    end
    
    if fs.unlink(file) then
        http.prepare_content("application/json")
        http.write_json({
            success = true,
            message = "File deleted successfully"
        })
    else
        http.prepare_content("application/json")
        http.write_json({
            success = false,
            message = "Failed to delete file"
        })
    end
end

function action_get_filename()
    local http = require "luci.http"
    local sys = require "luci.sys"
    
    local filename = sys.exec("/usr/bin/overlay-backup.sh filename 2>&1"):gsub("%s+$", "")
    
    http.prepare_content("application/json")
    http.write_json({
        success = true,
        filename = filename
    })
end

function action_get_log()
    local http = require "luci.http"
    local fs = require "nixio.fs"
    
    local log_type = http.formvalue("type") or "backup"
    local log_file = (log_type == "restore") and "/tmp/overlay_restore.log" or "/tmp/overlay_backup.log"
    
    local content = fs.readfile(log_file) or ""
    
    http.prepare_content("application/json")
    http.write_json({
        success = true,
        log = content
    })
end

function action_upload()
    local http = require "luci.http"
    local sys = require "luci.sys"
    local fs = require "nixio.fs"
    local uci = require "luci.model.uci".cursor()
    
    local upload_path = uci:get("overlay_backup", "main", "backup_path") or "/tmp/upload"
    fs.mkdirr(upload_path)
    
    local fp
    local filename
    
    http.setfilehandler(
        function(meta, chunk, eof)
            if not fp then
                if meta and meta.name == "backup_file" and meta.file then
                    filename = meta.file
                    -- Security check
                    if filename:match("_backup_.*%.tar%.gz$") or filename:match("backup%.tar%.gz$") then
                        fp = io.open(upload_path .. "/" .. filename, "w")
                    end
                end
            end
            if fp and chunk then
                fp:write(chunk)
            end
            if fp and eof then
                fp:close()
            end
        end
    )
    
    -- Process the upload
    local vals = http.formvaluetable("backup_file")
    
    http.prepare_content("application/json")
    
    if filename then
        http.write_json({
            success = true,
            message = "File uploaded successfully",
            filename = filename,
            path = upload_path .. "/" .. filename
        })
    else
        http.write_json({
            success = false,
            message = "Upload failed or invalid file format"
        })
    end
end

function action_backup_info()
    local http = require "luci.http"
    local sys = require "luci.sys"
    
    local file = http.formvalue("file")
    
    if not file or file == "" then
        http.prepare_content("application/json")
        http.write_json({
            success = false,
            message = "No file specified"
        })
        return
    end
    
    local info = sys.exec("/usr/bin/overlay-restore.sh info " .. luci.util.shellquote(file) .. " 2>&1")
    
    http.prepare_content("application/json")
    http.write_json({
        success = true,
        info = info
    })
end
