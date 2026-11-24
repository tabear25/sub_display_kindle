--[[--
DeskDeck: turns a Kindle into a desk display (Spotify via KoPlay, clock, pomodoro).

This early version only provides a diagnostics screen used during the on-device checks
(docs/DEVICE_CHECKLIST.md): it shows power / sleep / Wi-Fi state and keeps a log of the
power and sleep events KOReader delivers, so we can design the power handling on facts.

@module koplugin.DeskDeck
--]]

local Dispatcher = require("dispatcher")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local Diag = require("deskdeck_diag")

local DeskDeck = WidgetContainer:extend{
    name = "deskdeck",
    is_doc_only = false,
}

function DeskDeck:onDispatcherRegisterActions()
    Dispatcher:registerAction("deskdeck_diag", {
        category = "none", event = "DeskDeckDiag", title = "DeskDeck: 診断", general = true,
    })
end

function DeskDeck:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
    Diag.logStartOnce()
end

function DeskDeck:addToMainMenu(menu_items)
    menu_items.deskdeck = {
        text = "DeskDeck",
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = "診断（実機確認用）",
                callback = function() Diag.show() end,
            },
        },
    }
end

function DeskDeck:onDeskDeckDiag()
    Diag.show()
    return true
end

-- Event log. These handlers must NOT return true: other modules (AutoSuspend, the
-- battery statistics...) need the same events, and returning true stops propagation.
function DeskDeck:onCharging() Diag.logEvent("Charging") end
function DeskDeck:onNotCharging() Diag.logEvent("NotCharging") end
function DeskDeck:onSuspend() Diag.logEvent("Suspend") end
function DeskDeck:onResume() Diag.logEvent("Resume") end
function DeskDeck:onOutOfScreenSaver() Diag.logEvent("OutOfScreenSaver") end
function DeskDeck:onNetworkConnected() Diag.logEvent("NetworkConnected") end
function DeskDeck:onNetworkDisconnected() Diag.logEvent("NetworkDisconnected") end

return DeskDeck
