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

-- Top-of-Tools placement, Storefront's mechanism: KOReader orders menu
-- entries through these order tables, and entries missing from them land
-- wherever default sorting leaves them (second page, in practice on the
-- Oasis). Inserting our id near the front of order.tools pins us at the
-- top of the Tools section in both the file manager and the reader.
local function is_item_in_order(tbl, target_id)
    if type(tbl) ~= "table" then return false end
    for _pos, val in ipairs(tbl) do
        if val == target_id then
            return true
        elseif type(val) == "table" then
            if is_item_in_order(val, target_id) then
                return true
            end
        end
    end
    return false
end

local function inject_saforums_into_tools_menu()
    local menu_orders = {
        "ui/elements/reader_menu_order",
        "ui/elements/filemanager_menu_order",
    }
    for _idx, order_path in ipairs(menu_orders) do
        local ok, order = pcall(require, order_path)
        if ok and type(order) == "table" and type(order.tools) == "table" then
            if not is_item_in_order(order, "saforums") then
                table.insert(order.tools, 2, "saforums")
            end
        end
    end
end

local Saforums = WidgetContainer:extend{
    name = "saforums",
    is_doc_only = false,
    fullname = _("SA Forums"),
    description = _([[Read the Something Awful Forums on your e-reader. Lurker-first: login, forum index, thread lists with unread counts, read-only threads.]]),
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
    pcall(ui.enforce_retention)
end

function Saforums:onOpenSaforums()
    ui.new():show_forum_index()
end

function Saforums:onOpenBookmarks()
    ui.new():show_bookmarks(1)
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
    inject_saforums_into_tools_menu()
    menu_items.saforums = {
        text = _("SA Forums"),
        -- "tools" is the section App Store and Storefront live in; the
        -- injection above pins the position within it.
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("Browse forums"),
                callback = function() self:onOpenSaforums() end,
            },
            {
                text = _("Bookmarks"),
                callback = function() self:onOpenBookmarks() end,
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
