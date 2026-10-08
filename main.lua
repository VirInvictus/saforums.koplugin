--[[
SA Forums for KOReader: lurker-core skeleton.

Phase 0 stub. The plugin loads, registers a menu entry, and does nothing
else yet. Phase 1 replaces the body of openMainMenu with the real
forum/thread browsing flow (see roadmap.md).
--]]

local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local Saforums = {
    name = "saforums",
    fullname = _("SA Forums"),
    description = _([[Read the Something Awful Forums as EPUBs.]]),
}

function Saforums:onOpenSaforums()
    UIManager:show(InfoMessage:new{
        text = _("SA Forums plugin is not implemented yet (Phase 0 skeleton)."),
        timeout = 3,
    })
end

function Saforums:registerDispatcher()
    Dispatcher:registerAction("saforums_open", {
        category = "none",
        event = "OpenSaforums",
        title = _("Open SA Forums"),
        general = true,
    })
end

function Saforums:addToMainMenu(menu_items)
    menu_items.saforums = {
        text = _("SA Forums"),
        callback = function()
            self:onOpenSaforums()
        end,
    }
end

Saforums:registerDispatcher()

return Saforums
