--[[
SA Forums for KOReader: read forums.somethingawful.com as EPUBs.

Phase 1 flow (see roadmap.md): login or import cookies, browse the forum
index, pick a thread, read the fetched page in the normal reader. Every
thread fetch is noseen=1; nothing is ever marked read as a side effect.

Plugin shape note: KOReader's PluginLoader instantiates plugins as
WidgetContainer classes (pcall(plugin.new, ...)), so this file must return
a class made with WidgetContainer:extend, with registration work inside
init(); a plain table fails to load with a nil-call error.
--]]

local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local ui = require("saforums.ui")

local Saforums = WidgetContainer:extend{
    name = "saforums",
    is_doc_only = false,
    fullname = _("SA Forums"),
    description = _([[Read the Something Awful Forums as EPUBs. Lurker-first: login, forum index, thread lists with unread counts, read-only threads.]]),
}

function Saforums:onDispatcherRegisterActions()
    Dispatcher:registerAction("saforums_open", {
        category = "none",
        event = "OpenSaforums",
        title = _("Open SA Forums"),
        general = true,
    })
end

function Saforums:init()
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

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

function Saforums:addToMainMenu(menu_items)
    menu_items.saforums = {
        text = _("SA Forums"),
        sorting_hint = "more_tools",
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

return Saforums
