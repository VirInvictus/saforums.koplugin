--[[
SA Forums for KOReader: read forums.somethingawful.com as EPUBs.

Phase 1 flow (see roadmap.md): login or import cookies, browse the forum
index, pick a thread, read the fetched page in the normal reader. Every
thread fetch is noseen=1; nothing is ever marked read as a side effect.
--]]

local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local ui = require("saforums.ui")

local Saforums = {
    name = "saforums",
    fullname = _("SA Forums"),
    description = _([[Read the Something Awful Forums as EPUBs. Lurker-first: login, forum index, thread lists with unread counts, read-only threads.]]),
}

function Saforums:onOpenSaforums()
    ui.new():show_forum_index()
end

function Saforums:onLogin()
    ui.new():ensure_session(function()
        UIManager:show(InfoMessage:new{
            text = _("Already logged in. Use Clear session to log out."),
            timeout = 3,
        })
    end)
end

function Saforums:onImportCookies()
    ui.new():import_cookies()
end

function Saforums:onClearSession()
    ui.new():clear_session()
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
        sub_item_table = {
            {
                text = _("Browse forums"),
                callback = function() self:onOpenSaforums() end,
            },
            {
                text = _("Log in…"),
                callback = function() self:onLogin() end,
            },
            {
                text = _("Import session cookies…"),
                callback = function() self:onImportCookies() end,
            },
            {
                text = _("Clear session"),
                callback = function() self:onClearSession() end,
            },
        },
    }
end

Saforums:registerDispatcher()

return Saforums
