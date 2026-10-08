--[[
Device-facing flow: login, cookie import, forum index, thread lists, and
opening a thread as an EPUB in the reader. Everything network-adjacent here
runs only on the device; the pure layers underneath are the tested part.

Read-state discipline lives in the URLs this module builds: every thread
fetch carries noseen=1 (spec: Semantics > Read state); nothing in Phase 1
marks anything read.
--]]

local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local LuaSettings = require("luasettings")
local Menu = require("ui/widget/menu")
local NetworkMgr = require("ui/network/manager")
local ReaderUI = require("apps/reader/readerui")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local _ = require("gettext")

local config = require("saforums.config")
local threadhtml = require("saforums.threadhtml")
local indexparser = require("saforums.indexparser")
local json = require("saforums.json")
local postspageparser = require("saforums.postspageparser")
local session_mod = require("saforums.session")
local threadlistparser = require("saforums.threadlistparser")

local ui = {}

local SaforumsUI = {}
SaforumsUI.__index = SaforumsUI

function ui.new()
    local self = setmetatable({}, SaforumsUI)
    self.settings = LuaSettings:open(
        ("%s/%s"):format(DataStorage:getSettingsDir(), "saforums_settings.lua"))
    self.session = session_mod.new()
    self.session:load(self.settings:readSetting("saforums"))
    return self
end

--- Thread-book shelf LRU (spec: Rendering; policy set 2026-10-08): oldest
--- books beyond the cap are deleted at plugin start, sidecars included.
function ui.enforce_retention()
    local retention = require("saforums.retention")
    local settings = LuaSettings:open(
        ("%s/%s"):format(DataStorage:getSettingsDir(), "saforums_settings.lua"))
    local cap = tonumber(settings:readSetting("saforums_retention_cap")) or 100
    local dir = (DataStorage:getFullDataDir() or DataStorage:getDataDir()) .. "/saforums"
    retention.enforce(dir, cap)
end

function SaforumsUI:save_session()
    self.settings:saveSetting("saforums", self.session:to_table())
    self.settings:flush()
end

function SaforumsUI:message(text, timeout)
    local toast = InfoMessage:new{ text = text, timeout = timeout or 2 }
    UIManager:show(toast)
    return toast
end

--- Map a session result to a human message; true when it was an error.
function SaforumsUI:show_result_error(result)
    if not result or result.kind == "ok" then return false end
    local text
    if result.kind == "cloudflare" then
        text = _("SA is showing a Cloudflare challenge, which this device cannot solve. "
            .. "Open the forums in a normal browser once to clear it, or import your "
            .. "session cookies from the SA Forums menu.")
    elseif result.kind == "logged_out" then
        text = _("Your session expired on the server. Log in again from the SA Forums menu.")
    elseif result.kind == "not_json" then
        text = _("The site answered with an HTML page instead of JSON. The login likely failed.")
    elseif result.kind == "transport_error" then
        text = _("Network error: ") .. tostring(result.error or "unknown")
    else
        text = _("The site returned HTTP ") .. tostring(result.code or "?")
    end
    UIManager:show(InfoMessage:new{ text = text, timeout = 6 })
    return true
end

-- ---------------------------------------------------------------------------
-- Network guard

function SaforumsUI:when_online(action)
    NetworkMgr:runWhenOnline(action)
end

-- ---------------------------------------------------------------------------
-- Session flows

function SaforumsUI:ensure_session(then_run)
    if self.session:has_session() then
        then_run()
        return
    end
    self:prompt_login(then_run)
end

function SaforumsUI:prompt_login(then_run)
    local dialog
    dialog = InputDialog:new{
        title = _("Log in to the SA Forums"),
        input = self.settings:readSetting("saforums_username"),
        input_hint = _("username"),
        text = _("Your cookies are stored on this device only."),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Next: password"),
                    is_enter = true,
                    callback = function()
                        local username = dialog:getInputText()
                        if username == "" then return end
                        UIManager:close(dialog)
                        self:prompt_password(username, then_run)
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
end

function SaforumsUI:prompt_password(username, then_run)
    local dialog
    dialog = InputDialog:new{
        title = _("Password for ") .. username,
        input_type = "password",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Log in"),
                    is_enter = true,
                    callback = function()
                        local password = dialog:getInputText()
                        if password == "" then return end
                        UIManager:close(dialog)
                        local toast = self:message(_("Logging in…"), nil)
                        self:when_online(function()
                            local document, result = self.session:login(username, password)
                            pcall(function() UIManager:close(toast) end)
                            if document then
                                self.settings:saveSetting("saforums_username", username)
                                self:save_session()
                                self:message(_("Logged in as ") .. tostring(document.user and document.user.username or username))
                                if then_run then then_run() end
                            else
                                if result and result.kind == "not_json" then
                                    self:message(_("Login failed: wrong username or password."), 5)
                                else
                                    self:show_result_error(result)
                                end
                            end
                        end)
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
end

function SaforumsUI:import_cookies()
    self:import_cookie(config.session_user_cookie, function()
        self:import_cookie(config.session_password_cookie, function()
            self:save_session()
            self:message(_("Cookies imported. Session restored."), 3)
        end)
    end)
end

function SaforumsUI:import_cookie(name, then_run)
    local dialog
    dialog = InputDialog:new{
        title = _("Paste cookie: ") .. name,
        text = _("From a logged-in desktop browser session (devtools: Application > Cookies)."),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter = true,
                    callback = function()
                        local value = dialog:getInputText()
                        if value == "" then return end
                        UIManager:close(dialog)
                        self.session.jar:load({ [name] = { value = value, path = "/" } })
                        then_run()
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
end

function SaforumsUI:clear_session()
    self.session.jar:clear_session()
    self:save_session()
    self:message(_("Session cleared."), 2)
end

-- ---------------------------------------------------------------------------
-- Browsing flows

function SaforumsUI:show_forum_index()
    self:ensure_session(function()
        self:when_online(function()
            local result = self.session:get(config.base_url .. "/index.php?json=1")
            if self:show_result_error(result) then return end
            local ok, document = pcall(json.decode, result.body or "")
            if not ok then
                self:message(_("The site answered with something that is not a forum index."), 4)
                return
            end
            local parsed = indexparser.parse(document)
            local items = {}
            for _idx, forum in ipairs(parsed.flat) do
                items[#items + 1] = {
                    text = string.rep("    ", forum.depth) .. forum.title,
                    forum_id = forum.id,
                }
            end
            self:show_menu(_("Forums"), items, function(item)
                self:show_thread_list(item.forum_id, 1, item.text)
            end)
        end)
    end)
end

function SaforumsUI:show_thread_list(forum_id, page_number, title)
    self:when_online(function()
        local url = config.base_url .. "/forumdisplay.php?forumid=" .. forum_id
            .. "&perpage=" .. config.perpage .. "&pagenumber=" .. page_number
        local result = self.session:get(url)
        if self:show_result_error(result) then return end
        local parsed = threadlistparser.parse(result.body or "")
        local items = {}
        if page_number > 1 then
            items[#items + 1] = {
                text = _("… previous page"),
                goto_page = page_number - 1,
            }
        end
        for _idx, thread in ipairs(parsed.threads) do
            local text = thread.title
            if thread.sticky then text = _("[sticky] ") .. text end
            if thread.closed then text = text .. _(" (closed)") end
            items[#items + 1] = {
                text = text,
                mandatory = thread.unread_count and tostring(thread.unread_count) or (thread.is_read and "✓" or nil),
                bold = thread.unread_count ~= nil or nil,
                thread = thread,
            }
        end
        local total = parsed.pagination and parsed.pagination.total_pages or 1
        if page_number < total then
            items[#items + 1] = {
                text = _("… next page"),
                goto_page = page_number + 1,
            }
        end

        local list_title = (title or _("Threads")) .. "  (" .. page_number .. "/" .. total .. ")"
        self:show_menu(list_title, items, function(item)
            if item.goto_page then
                self:show_thread_list(forum_id, item.goto_page, title)
            elseif item.thread then
                self:open_thread(item.thread, 1)
            end
        end)
    end)
end

--- Fetch one thread page without touching server-side read state (noseen=1),
--- and render it in the in-app thread view. No files, no ReaderUI, no
--- history entries (spec: Rendering).
function SaforumsUI:open_thread(thread, page_number)
    self:message(_("Fetching thread…"))
    self:when_online(function()
        local url = config.base_url .. "/showthread.php?threadid=" .. thread.id
            .. "&perpage=" .. config.perpage .. "&pagenumber=" .. page_number .. "&noseen=1"
        local result = self.session:get(url)
        if self:show_result_error(result) then return end
        local parsed = postspageparser.parse(result.body or "")
        if #parsed.posts == 0 then
            self:message(_("No posts found on that page."), 3)
            return
        end

        -- Avatars: fetched once per poster and cached on device; failures
        -- are cosmetic (the post renders without one).
        local dir = (DataStorage:getFullDataDir() or DataStorage:getDataDir()) .. "/saforums"
        if not lfs.attributes(dir, "mode") then
            local created, mkdir_err = lfs.mkdir(dir)
            if not created then
                logger.warn("saforums: mkdir failed for", dir, ":", tostring(mkdir_err))
            end
        end
        local avatar_cache = require("saforums.avatars")
        local avatars, seen_poster = {}, {}
        for _idx, post in ipairs(parsed.posts) do
            local uid = post.author_id
            if uid and post.avatar_src and not seen_poster[uid] then
                seen_poster[uid] = true
                local cached = avatar_cache.ensure(dir .. "/avatars", self.session, uid, post.avatar_src)
                if cached then
                    -- Relative to the resource directory mupdf resolves images against.
                    avatars[uid] = "avatars/" .. cached:match("([^/]+)$")
                end
            end
        end

        local thread_id = parsed.thread_id or thread.id
        local ThreadView = require("saforums.threadview")
        local view = ThreadView:new{
            title = parsed.title or thread.title,
            html_body = threadhtml.render({
                title = parsed.title or thread.title,
                posts = parsed.posts,
                avatars = avatars,
            }),
            resource_directory = dir,
            saved_ratio = self:get_position(thread_id),
            on_close = function(ratio)
                self:save_position(thread_id, ratio)
            end,
        }
        UIManager:show(view)
    end)
end

--- Per-thread scroll positions for the in-app view (settings-backed).
function SaforumsUI:get_position(thread_id)
    local positions = self.settings:readSetting("saforums_positions") or {}
    return positions[thread_id]
end

function SaforumsUI:save_position(thread_id, ratio)
    local positions = self.settings:readSetting("saforums_positions") or {}
    positions[thread_id] = ratio
    self.settings:saveSetting("saforums_positions", positions)
    self.settings:flush()
end

-- ---------------------------------------------------------------------------
-- Menu plumbing

function SaforumsUI:show_menu(title, items, on_select)
    local menu = Menu:new{
        title = title,
        item_table = items,
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        onMenuSelect = function(menu_self, item)
            UIManager:close(menu_self)
            on_select(item)
        end,
    }
    UIManager:show(menu)
end

ui.SaforumsUI = SaforumsUI

return ui
