--[[--
DeskDeck diagnostics: a read-only status report plus an event log.

Reads (never writes) KOReader state, sysfs power-supply files and powerd lipc properties.
The only files it writes are in KOReader's settings directory:
    deskdeck_diag.log         event log (power, sleep, Wi-Fi), trimmed to the last lines
    deskdeck_diag_report.txt  the current report, when "レポート保存" is pressed
It never prints Spotify tokens or the Client ID: for koplay.json it only reports whether the
file exists and its authorization date.
--]]

local DataStorage = require("datastorage")
local Device = require("device")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local Diag = {}

local SETTINGS_DIR = DataStorage:getSettingsDir()
local LOG_FILE = SETTINGS_DIR .. "/deskdeck_diag.log"
local REPORT_FILE = SETTINGS_DIR .. "/deskdeck_diag_report.txt"
local MAX_LOG_BYTES = 64 * 1024
local KEEP_LOG_LINES = 400
local SHOW_LOG_LINES = 20
local DISPLAY_OFFSET = 9 * 3600 -- DeskDeck's default display time zone: UTC+9
local TOKEN_LIFETIME = 182 * 24 * 3600 -- Spotify: about 6 months from the authorization

local start_logged = false

--- Calls f(...) and returns its first result, or a short error text instead of raising.
local function safe(f, ...)
    if type(f) ~= "function" then return "n/a" end
    local ok, v = pcall(f, ...)
    if ok then return v end
    return "error: " .. tostring(v)
end

local function yesno(v)
    if v == true then return "はい" end
    if v == false then return "いいえ" end
    return tostring(v)
end

local function fmtTime(t, offset)
    return os.date("!%Y-%m-%d %H:%M:%S", t + (offset or 0))
end

local function readFirstLine(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local line = f:read("*l")
    f:close()
    return line
end

--- One line per /sys/class/power_supply entry, with the fields that tell charging state.
local function powerSupplyLines()
    local base = "/sys/class/power_supply"
    local lines = {}
    if lfs.attributes(base, "mode") ~= "directory" then
        return { "（" .. base .. " がありません）" }
    end
    for name in lfs.dir(base) do
        if name ~= "." and name ~= ".." then
            local fields = {}
            for _, key in ipairs{ "type", "online", "present", "status", "charging", "capacity" } do
                local v = readFirstLine(base .. "/" .. name .. "/" .. key)
                if v then table.insert(fields, key .. "=" .. v) end
            end
            table.insert(lines, name .. ": " .. table.concat(fields, " "))
        end
    end
    table.sort(lines)
    return lines
end

--- Short power summary used in every log line.
function Diag.powerSummary()
    local powerd = Device.powerd
    if not powerd then return "powerd=n/a" end
    return string.format("cap=%s%% charging=%s charged=%s",
        tostring(safe(powerd.getCapacity, powerd)),
        tostring(safe(powerd.isCharging, powerd)),
        tostring(safe(powerd.isCharged, powerd)))
end

local function trimLog()
    local size = lfs.attributes(LOG_FILE, "size") or 0
    if size <= MAX_LOG_BYTES then return end
    local lines = {}
    for line in io.lines(LOG_FILE) do lines[#lines + 1] = line end
    local first = math.max(1, #lines - KEEP_LOG_LINES + 1)
    local tmp = LOG_FILE .. ".tmp"
    local out = io.open(tmp, "w")
    if not out then return end
    out:write(table.concat(lines, "\n", first, #lines), "\n")
    out:close()
    os.rename(tmp, LOG_FILE)
end

local function appendLog(line)
    local f = io.open(LOG_FILE, "a")
    if not f then
        logger.warn("DeskDeck: cannot write", LOG_FILE)
        return
    end
    f:write(line, "\n")
    f:close()
    pcall(trimLog)
end

function Diag.logEvent(name)
    local now = os.time()
    appendLog(string.format("%s (UTC+9)  %-19s %s", fmtTime(now, DISPLAY_OFFSET), name, Diag.powerSummary()))
end

--- Logs "KOReaderStart" once per KOReader process (plugins are re-created on every screen switch).
function Diag.logStartOnce()
    if start_logged then return end
    start_logged = true
    Diag.logEvent("KOReaderStart")
end

local function lastLogLines(n)
    local lines = {}
    local f = io.open(LOG_FILE, "r")
    if not f then return lines end
    for line in f:lines() do
        lines[#lines + 1] = line
        if #lines > n then table.remove(lines, 1) end
    end
    f:close()
    return lines
end

local function koplayAuthLine()
    local path = SETTINGS_DIR .. "/koplay.json"
    local f = io.open(path, "r")
    if not f then return "koplay.json: なし" end
    local content = f:read("*a")
    f:close()
    local ok, data = pcall(require("json").decode, content)
    if not ok or type(data) ~= "table" then
        return "koplay.json: あり（読み取れません。壊れている可能性があります）"
    end
    local has_token = type(data.refresh_token) == "string" and data.refresh_token ~= ""
    local at = tonumber(data.authorized_at)
    local when
    if at then
        when = string.format("認可日 %s、失効の目安 %s",
            os.date("!%Y-%m-%d", at + DISPLAY_OFFSET), os.date("!%Y-%m-%d", at + TOKEN_LIFETIME + DISPLAY_OFFSET))
    else
        when = "認可日の記録なし"
    end
    return string.format("koplay.json: あり（トークン %s、%s）", has_token and "あり" or "なし", when)
end

function Diag.report()
    local now = os.time()
    local powerd = Device.powerd
    local screen = Device.screen
    local NetworkMgr = require("ui/network/manager")
    local PluginShare = require("pluginshare")
    local out = {}
    local function add(s) out[#out + 1] = s end

    add("■ 時刻")
    add("  UTC+9 での表示: " .. fmtTime(now, DISPLAY_OFFSET))
    add("  システム時刻(UTC): " .. fmtTime(now))
    add("  システムのローカル時刻: " .. os.date("%Y-%m-%d %H:%M:%S", now))

    add("")
    add("■ 端末")
    add("  KOReader: " .. tostring(safe(function() return require("version"):getCurrentRevision() end)))
    add("  機種: " .. tostring(Device.model))
    add(string.format("  画面: %sx%s, %s dpi",
        tostring(safe(screen.getWidth, screen)), tostring(safe(screen.getHeight, screen)),
        tostring(safe(screen.getDPI, screen))))

    add("")
    add("■ 給電")
    if powerd then
        add("  電池: " .. tostring(safe(powerd.getCapacity, powerd)) .. "%")
        add("  充電中 isCharging: " .. yesno(safe(powerd.isCharging, powerd)))
        add("  満充電 isCharged: " .. yesno(safe(powerd.isCharged, powerd)))
        local h = powerd.lipc_handle
        if h then
            add("  lipc isCharging: " .. tostring(safe(h.get_int_property, h, "com.lab126.powerd", "isCharging")))
            add("  lipc state: " .. tostring(safe(h.get_string_property, h, "com.lab126.powerd", "state")))
            add("  lipc preventScreenSaver: " .. tostring(safe(h.get_int_property, h, "com.lab126.powerd", "preventScreenSaver")))
        end
    else
        add("  powerd: なし")
    end
    add("  power_supply:")
    for _, line in ipairs(powerSupplyLines()) do add("    " .. line) end

    add("")
    add("■ スリープ関連")
    local suspend = G_reader_settings:readSetting("auto_suspend_timeout_seconds")
    add("  KOReaderの自動スリープ: " .. (suspend and (tostring(suspend) .. " 秒") or "未設定（既定 900 秒）"))
    add("  pause_auto_suspend: " .. yesno(PluginShare.pause_auto_suspend == true))
    add("  keepalive: " .. yesno(PluginShare.keepalive == true))

    add("")
    add("■ Wi-Fi")
    add("  Wi-Fi オン: " .. yesno(safe(NetworkMgr.isWifiOn, NetworkMgr)))
    add("  接続: " .. yesno(safe(NetworkMgr.isConnected, NetworkMgr)))

    add("")
    add("■ ファイル")
    add("  " .. koplayAuthLine())
    local ca_size = lfs.attributes("data/ca-bundle.crt", "size")
    add("  CA証明書 data/ca-bundle.crt: " .. (ca_size and string.format("あり（%d KB）", math.floor(ca_size / 1024)) or "なし"))
    add("  KOReader のフォルダ: " .. tostring(safe(lfs.currentdir)))

    add("")
    add(string.format("■ 記録（新しい順、最大 %d 件。全体は settings/deskdeck_diag.log）", SHOW_LOG_LINES))
    local lines = lastLogLines(SHOW_LOG_LINES)
    if #lines == 0 then add("  （まだありません）") end
    for i = #lines, 1, -1 do add("  " .. lines[i]) end

    return table.concat(out, "\n")
end

function Diag.saveReport()
    local f = io.open(REPORT_FILE, "w")
    if not f then return false end
    f:write(Diag.report(), "\n")
    f:close()
    return true, REPORT_FILE
end

function Diag.show()
    local InfoMessage = require("ui/widget/infomessage")
    local TextViewer = require("ui/widget/textviewer")
    local viewer
    viewer = TextViewer:new{
        title = "DeskDeck 診断",
        text = Diag.report(),
        buttons_table = {
            {
                {
                    text = "更新",
                    callback = function()
                        UIManager:close(viewer)
                        Diag.show()
                    end,
                },
                {
                    text = "レポート保存",
                    callback = function()
                        local ok, path = Diag.saveReport()
                        UIManager:show(InfoMessage:new{
                            text = ok and ("保存しました:\n" .. path) or "保存できませんでした",
                            timeout = 3,
                        })
                    end,
                },
            },
            {
                {
                    text = "記録を消去",
                    callback = function()
                        local ConfirmBox = require("ui/widget/confirmbox")
                        UIManager:show(ConfirmBox:new{
                            text = "診断の記録（deskdeck_diag.log）を消去しますか？",
                            ok_text = "消去",
                            ok_callback = function()
                                os.remove(LOG_FILE)
                                UIManager:close(viewer)
                                Diag.show()
                            end,
                        })
                    end,
                },
                {
                    text = "閉じる",
                    callback = function() UIManager:close(viewer) end,
                },
            },
        },
    }
    UIManager:show(viewer)
end

return Diag
