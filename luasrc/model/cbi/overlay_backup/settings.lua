-- CBI Model for Overlay Backup Settings

local m, s, o

m = Map("overlay_backup", translate("Overlay Backup Settings"),
    translate("Configure backup and restore settings for overlay filesystem."))

s = m:section(TypedSection, "settings", translate("General Settings"))
s.anonymous = true
s.addremove = false

o = s:option(Value, "backup_path", translate("Default Backup Path"),
    translate("Default directory for storing backup files."))
o.default = "/tmp/upload"
o.rmempty = false

-- Add dropdown with mounted devices
local sys = require "luci.sys"
local mounted = sys.exec("/usr/bin/overlay-backup.sh mounted 2>&1")
for path in mounted:gmatch("[^\r\n]+") do
    if path ~= "" and not path:match("^%[") then
        o:value(path, path)
    end
end
o:value("/tmp/upload", "/tmp/upload")

o = s:option(Flag, "auto_reboot", translate("Auto Reboot After Restore"),
    translate("Automatically reboot the system after restore completes."))
o.default = "1"
o.rmempty = false

return m
