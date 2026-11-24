--[[
Smoke test for deskdeck.koplugin/deskdeck_diag.lua, runnable without KOReader:
    luajit tests/diag_smoke_test.lua
KOReader modules are replaced by small stubs, so this only proves that the report, the
event log and the dialog wiring run without Lua errors. Set TMPDIR to choose where the
throwaway settings directory is created.
--]]

package.path = "deskdeck.koplugin/?.lua;" .. package.path

local tmp_root = os.getenv("TMPDIR") or "/tmp"
local settings_dir = string.format("%s/deskdeck_diag_test_%d", tmp_root, os.time())
assert(os.execute("mkdir -p '" .. settings_dir .. "'") == 0 or true)

local failures = 0
local function check(cond, msg)
    if cond then
        print("ok   " .. msg)
    else
        failures = failures + 1
        print("FAIL " .. msg)
    end
end

-- Minimal lfs replacement (attributes / dir / currentdir), enough for the diag module.
local fake_lfs = {}
function fake_lfs.attributes(path, field)
    local f = io.open(path, "r")
    if not f then
        local ok = os.execute("test -d '" .. path .. "'")
        if ok == 0 or ok == true then
            local attrs = { mode = "directory" }
            return field and attrs[field] or attrs
        end
        return nil
    end
    local size = f:seek("end")
    f:close()
    local attrs = { mode = "file", size = size }
    if field then return attrs[field] end
    return attrs
end
function fake_lfs.dir(path)
    local p = io.popen("ls -a '" .. path .. "' 2>/dev/null")
    local names = {}
    for name in p:lines() do names[#names + 1] = name end
    p:close()
    local i = 0
    return function() i = i + 1; return names[i] end
end
function fake_lfs.currentdir() return os.getenv("PWD") or "." end

-- Very small JSON decoder stub: enough for the koplay.json shape.
local fake_json = {}
function fake_json.decode(s)
    local t = {}
    for k, v in s:gmatch('"([%w_]+)"%s*:%s*"([^"]*)"') do t[k] = v end
    for k, v in s:gmatch('"([%w_]+)"%s*:%s*(%d+)') do t[k] = tonumber(v) end
    if not next(t) then error("not json") end
    return t
end

local shown = {}
package.preload["datastorage"] = function()
    return { getSettingsDir = function() return settings_dir end }
end
package.preload["device"] = function()
    return {
        model = "KindlePaperWhite4",
        isKindle = function() return true end,
        screen = {
            getWidth = function() return 1072 end,
            getHeight = function() return 1448 end,
            getDPI = function() return 300 end,
        },
        powerd = {
            getCapacity = function() return 87 end,
            isCharging = function() return true end,
            isCharged = function() return false end,
            lipc_handle = {
                get_int_property = function(_self, _service, prop)
                    if prop == "preventScreenSaver" then error("property not readable") end
                    return 1
                end,
                get_string_property = function() return "active" end,
            },
        },
    }
end
package.preload["ui/uimanager"] = function()
    return {
        show = function(_self, w) shown[#shown + 1] = w end,
        close = function() end,
    }
end
package.preload["libs/libkoreader-lfs"] = function() return fake_lfs end
package.preload["logger"] = function()
    local function nop() end
    return { warn = nop, info = nop, dbg = nop, err = nop }
end
package.preload["ui/network/manager"] = function()
    return {
        isWifiOn = function() return true end,
        isConnected = function() error("simulated failure") end,
    }
end
package.preload["pluginshare"] = function() return {} end
package.preload["version"] = function()
    return { getCurrentRevision = function() return "v2026.07.2" end }
end
package.preload["json"] = function() return fake_json end
local function widgetStub()
    return { new = function(_self, o) return o end }
end
package.preload["ui/widget/textviewer"] = widgetStub
package.preload["ui/widget/infomessage"] = widgetStub
package.preload["ui/widget/confirmbox"] = widgetStub

_G.G_reader_settings = { readSetting = function() return nil end }

local Diag = require("deskdeck_diag")

-- 1. Event log
Diag.logStartOnce()
Diag.logStartOnce() -- second call must not log again
Diag.logEvent("Charging")
local log = io.open(settings_dir .. "/deskdeck_diag.log"):read("*a")
local _, starts = log:gsub("KOReaderStart", "")
check(starts == 1, "KOReaderStart is logged once")
check(log:find("Charging", 1, true) and log:find("cap=87%", 1, true), "event line carries the power summary")

-- 2. Report without koplay.json
local report = Diag.report()
check(report:find("koplay.json: なし", 1, true) ~= nil, "report says koplay.json is missing")
check(report:find("1072x1448, 300 dpi", 1, true) ~= nil, "report shows the screen size")
check(report:find("error: ", 1, true) ~= nil, "failing calls are reported, not raised")

-- 3. Report with koplay.json: shows the date, never the token or the Client ID
local secret = "SECRET-REFRESH-TOKEN-123"
local f = io.open(settings_dir .. "/koplay.json", "w")
-- 1795474800 = 2026-11-23 23:00 UTC = 2026-11-24 08:00 UTC+9: the date must follow UTC+9
f:write('{"client_id":"CLIENTID-XYZ","refresh_token":"' .. secret .. '","authorized_at":1795474800}')
f:close()
report = Diag.report()
check(report:find("認可日 2026-11-24", 1, true) ~= nil, "authorization date shown in UTC+9")
check(report:find("失効の目安 2027-05-25", 1, true) ~= nil, "expiry estimate is about 6 months later")
check(report:find(secret, 1, true) == nil, "refresh token is never shown")
check(report:find("CLIENTID-XYZ", 1, true) == nil, "Client ID is never shown")

-- 4. Saved report
local ok, path = Diag.saveReport()
check(ok and io.open(path) ~= nil, "report file is written")
check(io.open(path):read("*a"):find(secret, 1, true) == nil, "saved report has no token")

-- 5. Log trimming keeps the newest lines
local big = io.open(settings_dir .. "/deskdeck_diag.log", "a")
for i = 1, 2000 do big:write(string.format("filler line %04d %s\n", i, string.rep("x", 40))) end
big:close()
Diag.logEvent("NotCharging")
local lines = {}
for line in io.lines(settings_dir .. "/deskdeck_diag.log") do lines[#lines + 1] = line end
check(#lines <= 400, "log trimmed to at most 400 lines (got " .. #lines .. ")")
check(lines[#lines]:find("NotCharging", 1, true) ~= nil, "newest line kept after trimming")

-- 6. Dialog wiring
Diag.show()
local viewer = shown[#shown]
check(type(viewer) == "table" and viewer.title == "DeskDeck 診断", "viewer is shown")
check(#viewer.buttons_table == 2 and #viewer.buttons_table[1] == 2, "viewer has the 4 buttons")

os.execute("rm -rf '" .. settings_dir .. "'")
if failures > 0 then
    print(failures .. " check(s) failed")
    os.exit(1)
end
print("all checks passed")
