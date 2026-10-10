--[[
Device-facing flow: login, cookie import, forum index, thread lists, and
opening a thread as an EPUB in the reader. Everything network-adjacent here
runs only on the device; the pure layers underneath are the tested part.

Read-state discipline lives in the URLs this module builds: every thread
fetch carries noseen=1 (spec: Semantics > Read state); nothing in Phase 1
marks anything read.
--]]

local DataStorage = require("datastorage")
local Device = require("device")
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
local htmltext = require("saforums.htmltext")
local indexparser = require("saforums.indexparser")
local json = require("saforums.json")
local listcache = require("saforums.listcache")
local postblocks = require("saforums.postblocks")
local postspageparser = require("saforums.postspageparser")
local session_mod = require("saforums.session")
local threadlistparser = require("saforums.threadlistparser")

local ui = {}

local SaforumsUI = {}
SaforumsUI.__index = SaforumsUI

--- The plugin's directory under the device data dir (shelf, avatars,
--- viewed images).
local function data_dir()
    return (DataStorage:getFullDataDir() or DataStorage:getDataDir()) .. "/saforums"
end

function ui.new()
    local self = setmetatable({}, SaforumsUI)
    self.settings = LuaSettings:open(
        ("%s/%s"):format(DataStorage:getSettingsDir(), "saforums_settings.lua"))
    self.session = session_mod.new()
    self.session:load(self.settings:readSetting("saforums"))
    -- List caches and per-surface state (spec: Politeness; settings-backed
    -- so stale-while-revalidate survives restarts).
    self.cache = listcache.new(self.settings:readSetting("saforums_list_cache"))
    self.forums_state = self.settings:readSetting("saforums_forums_state") or { favorites = {}, collapsed = {} }
    self.bookmark_filter = self.settings:readSetting("saforums_bookmark_filter") or "all"
    self.tag_filters = self.settings:readSetting("saforums_tag_filters") or {}
    self.read_announcements = self.settings:readSetting("saforums_read_announcements") or {}
    return self
end

function SaforumsUI:save_list_state()
    self.settings:saveSetting("saforums_list_cache", self.cache.entries)
    self.settings:saveSetting("saforums_forums_state", self.forums_state)
    self.settings:saveSetting("saforums_bookmark_filter", self.bookmark_filter)
    self.settings:saveSetting("saforums_tag_filters", self.tag_filters)
    self.settings:saveSetting("saforums_read_announcements", self.read_announcements)
    self.settings:flush()
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

function SaforumsUI:show_forum_index(opts)
    opts = opts or {}
    local cached = self.cache:get("index")
    local fresh = cached ~= nil and self.cache:fresh("index", config.cache_ttl_index)
    if cached then
        self:render_forum_index(cached)
    end
    if fresh and not opts.force then
        return
    end
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
            self.cache:put("index", parsed.flat)
            self:save_list_state()
            if cached then
                self:message(_("Forum list refreshed."), 1)
            else
                self:render_forum_index(parsed.flat)
            end
        end)
    end)
end

function SaforumsUI:forum_has_children(flat, forum)
    local index
    for position, candidate in ipairs(flat) do
        if candidate == forum then index = position break end
    end
    local next_entry = flat[index + 1]
    return next_entry ~= nil and next_entry.depth > 0
end

--- True when the entry sits under a depth-0 forum that is collapsed away.
function SaforumsUI:forum_is_hidden(flat, forum)
    local hidden = false
    for _position, candidate in ipairs(flat) do
        if candidate == forum then
            return hidden
        end
        if candidate.depth == 0 and self:forum_has_children(flat, candidate) then
            hidden = self.forums_state.collapsed[candidate.id] or false
        end
    end
    return hidden
end

function SaforumsUI:render_forum_index(flat)
    local items = {}
    items[#items + 1] = { text = _("Refresh forum list"), refresh_index = true }

    local by_id = {}
    for _idx, forum in ipairs(flat) do by_id[forum.id] = forum end
    if #self.forums_state.favorites > 0 then
        items[#items + 1] = { text = _("Favorites:"), no_action = true }
        for _idx, id in ipairs(self.forums_state.favorites) do
            local forum = by_id[id]
            if forum then
                items[#items + 1] = {
                    text = forum.title,
                    forum_id = forum.id,
                    forum_title = forum.title,
                }
            end
        end
    end

    for _idx, forum in ipairs(flat) do
        local grouped = forum.depth == 0 and self:forum_has_children(flat, forum)
        if grouped then
            local collapsed = self.forums_state.collapsed[forum.id] and true or false
            items[#items + 1] = {
                text = (collapsed and "+ " or "- ") .. forum.title,
                forum = forum,
                forum_id = forum.id,
                forum_title = forum.title,
                group = true,
            }
        elseif not self:forum_is_hidden(flat, forum) then
            items[#items + 1] = {
                text = string.rep("    ", forum.depth) .. forum.title,
                forum = forum,
                forum_id = forum.id,
                forum_title = forum.title,
                keep_menu = true,
            }
        end
    end

    self:show_menu(_("Forums"), items, function(item)
        if item.refresh_index then
            self:show_forum_index({ force = true })
        elseif item.group then
            -- a group header tap toggles its section
            local id = item.forum.id
            self.forums_state.collapsed[id] = not self.forums_state.collapsed[id] or nil
            self:save_list_state()
            self:render_forum_index(flat)
        elseif item.forum_id then
            -- a previous forum's list must not stay stacked beneath the new one
            pcall(function() UIManager:close(self._list_menu) end)
            self:show_thread_list(item.forum_id, 1, item.forum_title)
        end
    end, function(item)
        if item.forum or item.forum_id then
            return self:forum_hold_menu(flat, item)
        end
    end)
end

function SaforumsUI:forum_hold_menu(flat, item)
    local ButtonDialog = require("ui/widget/buttondialog")
    local dialog
    local buttons = {}
    local function add(text, callback)
        buttons[#buttons + 1] = { text = text, callback = function()
            UIManager:close(dialog)
            pcall(function() UIManager:close(self._last_menu) end)
            callback()
        end }
    end

    local forum_id = item.forum_id or (item.forum and item.forum.id)
    local forum_title = item.forum_title
    local is_favorite = false
    for _idx, id in ipairs(self.forums_state.favorites) do
        if id == forum_id then is_favorite = true break end
    end

    add(_("Open forum"), function()
        self:show_thread_list(forum_id, 1, forum_title)
    end)
    add(is_favorite and _("Unpin from favorites") or _("Pin to favorites"), function()
        if is_favorite then
            local kept = {}
            for _idx, id in ipairs(self.forums_state.favorites) do
                if id ~= forum_id then kept[#kept + 1] = id end
            end
            self.forums_state.favorites = kept
        else
            self.forums_state.favorites[#self.forums_state.favorites + 1] = forum_id
        end
        self:save_list_state()
        self:render_forum_index(flat)
    end)
    if is_favorite then
        add(_("Move up in favorites"), function()
            self:move_favorite(forum_id, -1)
            self:render_forum_index(flat)
        end)
        add(_("Move down in favorites"), function()
            self:move_favorite(forum_id, 1)
            self:render_forum_index(flat)
        end)
    end
    if item.group or (item.forum and item.forum.depth == 0) then
        local collapsed = self.forums_state.collapsed[forum_id] and true or false
        add(collapsed and _("Expand section") or _("Collapse section"), function()
            self.forums_state.collapsed[forum_id] = not collapsed or nil
            self:save_list_state()
            self:render_forum_index(flat)
        end)
    end

    dialog = ButtonDialog:new{ buttons = { buttons } }
    UIManager:show(dialog)
end

function SaforumsUI:move_favorite(forum_id, delta)
    local favorites = self.forums_state.favorites
    local position
    for idx, id in ipairs(favorites) do
        if id == forum_id then position = idx break end
    end
    if not position then return end
    local target = position + delta
    if target < 1 or target > #favorites then return end
    favorites[position], favorites[target] = favorites[target], favorites[position]
    self:save_list_state()
end

function SaforumsUI:show_thread_list(forum_id, page_number, title, opts)
    opts = opts or {}
    local url = config.base_url .. "/forumdisplay.php?forumid=" .. forum_id
        .. "&perpage=" .. config.perpage .. "&pagenumber=" .. page_number
    if self.tag_filters[tostring(forum_id)] then
        url = url .. "&posticon=" .. self.tag_filters[tostring(forum_id)]
    end
    self:render_thread_list(url, page_number, title, "forum", forum_id, opts)
end

--- The bookmark shelf: same rows as a forum list, but tapping a thread is
--- the explicit continue-reading action (spec: Read state), and holding
--- one offers the lurker-management actions.
function SaforumsUI:show_bookmarks(page_number, opts)
    opts = opts or {}
    local url = config.base_url .. "/bookmarkthreads.php?action=view"
        .. "&perpage=" .. config.perpage .. "&pagenumber=" .. page_number
    self:render_thread_list(url, page_number, _("Bookmarks"), "bookmarks", nil, opts)
end

function SaforumsUI:list_cache_key(source, forum_id, page_number)
    if source == "bookmarks" then
        return "bookmarks:" .. page_number
    end
    local tag = self.tag_filters[tostring(forum_id)]
    return "forumlist:" .. forum_id .. ":" .. page_number .. (tag and (":" .. tag) or "")
end

--- Stale-while-revalidate list flow (spec: Politeness): a fresh cache
--- renders with no request at all; a stale cache renders immediately and
--- the refetch swaps the list in place; no cache fetches as today.
function SaforumsUI:render_thread_list(list_url, page_number, title, source, forum_id, opts)
    opts = opts or {}
    local key = self:list_cache_key(source, forum_id, page_number)
    local ttl = source == "bookmarks" and config.cache_ttl_bookmarks or config.cache_ttl_forum_list
    local cached = self.cache:get(key)
    local fresh = cached ~= nil and self.cache:fresh(key, ttl)

    if cached then
        self:render_list_page(cached, page_number, title, source, forum_id, list_url)
    end
    if fresh and not opts.force then
        return
    end

    local token = {}
    self._list_token = token
    self:message(_("Fetching threads…"))
    self:when_online(function()
        local result = self.session:get(list_url)
        if self:show_result_error(result) then return end
        local parsed = threadlistparser.parse(result.body or "")
        self.cache:put(key, parsed)
        self:save_list_state()
        if not cached then
            self:render_list_page(parsed, page_number, title, source, forum_id, list_url)
        elseif self._list_token == token then
            pcall(function() UIManager:close(self._last_menu) end)
            self:render_list_page(parsed, page_number, title, source, forum_id, list_url)
        else
            self:message(_("List updated."), 1)
        end
    end)
end

--- List cache entries for lists a mutation just invalidated (read state,
--- bookmarks, stars all change what the lists show).
function SaforumsUI:forget_list_cache()
    local doomed = {}
    for key in pairs(self.cache.entries) do
        if key:find("^forumlist:") or key:find("^bookmarks:") then
            doomed[#doomed + 1] = key
        end
    end
    for _idx, key in ipairs(doomed) do
        self.cache:forget(key)
    end
end

function SaforumsUI:bookmark_filter_label(key)
    if key == "unread" then return _("unread") end
    if key == "read" then return _("read") end
    local star = key:match("^star(%d)$")
    if star then return config.star_letters[tonumber(star)] or key end
    return _("all")
end

--- Bookmarks-only client-side filter (persisted): all, unread, read, or a
--- single star color.
function SaforumsUI:filter_bookmarks(threads, source)
    if source ~= "bookmarks" or self.bookmark_filter == "all" then
        return threads
    end
    local filter = self.bookmark_filter
    local star = filter:match("^star(%d)$")
    local out = {}
    for _idx, thread in ipairs(threads) do
        if filter == "unread" and thread.unread_count then
            out[#out + 1] = thread
        elseif filter == "read" and thread.is_read then
            out[#out + 1] = thread
        elseif star and thread.star == tonumber(star) then
            out[#out + 1] = thread
        end
    end
    return out
end

--- One row: title line (with sticky/closed markers and the star letter)
--- over a secondary line (pages, replies, rating, killed-by/posted-by).
function SaforumsUI:thread_list_item(thread, source)
    local title = thread.title or "?"
    if thread.sticky then title = _("[sticky] ") .. title end
    local star_letter = thread.star and config.star_letters[thread.star] or nil
    if star_letter then title = title .. " " .. star_letter end
    if thread.closed then title = title .. _(" (closed)") end

    local parts = {}
    local pages = thread.replies and (math.floor(thread.replies / config.perpage) + 1) or nil
    if pages and pages > 1 then
        parts[#parts + 1] = string.format(_("%d pages"), pages)
    end
    if thread.replies then
        parts[#parts + 1] = string.format(_("%d replies"), thread.replies)
    end
    if thread.rating_average then
        parts[#parts + 1] = string.format(_("%.1f (%d votes)"),
            thread.rating_average, thread.rating_votes or 0)
    end
    if thread.is_read or thread.unread_count then
        if thread.last_post_author then
            parts[#parts + 1] = _("Killed by ") .. thread.last_post_author
        end
    elseif thread.author_name then
        parts[#parts + 1] = _("Posted by ") .. thread.author_name
    end
    local secondary = #parts > 0 and table.concat(parts, " · ") or nil

    return {
        text = secondary and (title .. "\n" .. secondary) or title,
        mandatory = thread.unread_count and tostring(thread.unread_count) or (thread.is_read and "✓" or nil),
        bold = thread.unread_count ~= nil or nil,
        thread = thread,
        keep_menu = true,
    }
end

function SaforumsUI:render_list_page(parsed, page_number, title, source, forum_id, list_url)
    local items = {}
    items[#items + 1] = { text = _("Refresh list"), refresh = true }

    if source == "bookmarks" then
        items[#items + 1] = {
            text = _("Filter: ") .. self:bookmark_filter_label(self.bookmark_filter),
            bookmark_filter = true,
        }
    elseif parsed.thread_tags and #parsed.thread_tags > 0 then
        local active = self.tag_filters[tostring(forum_id)]
        local label = _("all tags")
        if active then
            for _idx, tag in ipairs(parsed.thread_tags) do
                if tag.id == active then label = tag.name end
            end
        end
        items[#items + 1] = { text = _("Tag filter: ") .. label, tag_filter = true }
    end

    for _idx, announcement in ipairs(parsed.announcements or {}) do
        local seen = self.read_announcements[announcement.title or ""] and true or false
        items[#items + 1] = {
            text = _("[ann] ") .. (announcement.title or "?") .. (seen and "" or _(" (new)")),
            announcement = announcement,
            keep_menu = true,
        }
    end

    if page_number > 1 then
        items[#items + 1] = { text = _("… newer page"), goto_page = page_number - 1 }
    end

    for _idx, thread in ipairs(self:filter_bookmarks(parsed.threads, source)) do
        items[#items + 1] = self:thread_list_item(thread, source)
    end

    local total = parsed.pagination and parsed.pagination.total_pages
    if total and total > 1 then
        items[#items + 1] = { text = _("Jump to page…"), jump = true }
    end
    local show_older
    if total then
        show_older = page_number < total
    else
        show_older = #parsed.threads >= config.perpage
    end
    if show_older then
        items[#items + 1] = { text = _("… older page"), goto_page = page_number + 1 }
    end

    local list_title = title .. "  (" .. page_number .. "/" .. (total or "?") .. ")"
    local menu = self:show_menu(list_title, items, function(item)
        self:list_item_tapped(item, parsed, page_number, title, source, forum_id, list_url)
    end, function(item)
        if item.thread then
            return self:thread_hold_menu(item.thread, source)
        end
    end)
    self._list_menu = menu
end

function SaforumsUI:list_item_tapped(item, parsed, page_number, title, source, forum_id, list_url)
    if item.refresh then
        self:render_thread_list(list_url, page_number, title, source, forum_id, { force = true })
    elseif item.bookmark_filter then
        self:show_bookmark_filter_menu(parsed, page_number, title, source, forum_id, list_url)
    elseif item.tag_filter then
        self:show_tag_filter_menu(parsed, page_number, title, forum_id)
    elseif item.announcement then
        self:open_announcement(forum_id, item.announcement)
    elseif item.goto_page then
        if source == "bookmarks" then
            self:show_bookmarks(item.goto_page)
        else
            self:show_thread_list(forum_id, item.goto_page, title)
        end
    elseif item.jump then
        self:show_list_jump_dialog(parsed, page_number, title, source, forum_id)
    elseif item.thread then
        if source == "bookmarks" or item.thread.unread_count then
            -- the tap is the explicit continue-reading action
            self:open_thread(item.thread, { mode = "continue" })
        else
            self:open_thread(item.thread, { page = 1, mode = "browse" })
        end
    end
end

function SaforumsUI:show_bookmark_filter_menu(parsed, page_number, title, source, forum_id, list_url)
    local ButtonDialog = require("ui/widget/buttondialog")
    local dialog
    local flat = {}
    local function add(key, label)
        flat[#flat + 1] = { text = label, callback = function()
            UIManager:close(dialog)
            self.bookmark_filter = key
            self:save_list_state()
            pcall(function() UIManager:close(self._last_menu) end)
            self:render_list_page(parsed, page_number, title, source, forum_id, list_url)
        end }
    end
    add("all", _("All"))
    add("unread", _("Unread"))
    add("read", _("Read"))
    for star = 0, 5 do
        add("star" .. star, config.star_letters[star])
    end
    local rows = {}
    for index, button in ipairs(flat) do
        local row = math.floor((index - 1) / 3) + 1
        rows[row] = rows[row] or {}
        table.insert(rows[row], button)
    end
    dialog = ButtonDialog:new{ buttons = rows }
    UIManager:show(dialog)
end

function SaforumsUI:show_tag_filter_menu(parsed, page_number, title, forum_id)
    local ButtonDialog = require("ui/widget/buttondialog")
    local dialog
    local key = tostring(forum_id)
    local flat = {}
    local function add(tag_id, label)
        flat[#flat + 1] = { text = label, callback = function()
            UIManager:close(dialog)
            self.tag_filters[key] = tag_id or nil
            self:forget_list_cache()
            self:save_list_state()
            pcall(function() UIManager:close(self._last_menu) end)
            self:show_thread_list(forum_id, 1, title)
        end }
    end
    add(nil, _("All tags"))
    for _idx, tag in ipairs(parsed.thread_tags or {}) do
        add(tag.id, tag.name or tag.id)
    end
    local rows = {}
    for index, button in ipairs(flat) do
        local row = math.floor((index - 1) / 3) + 1
        rows[row] = rows[row] or {}
        table.insert(rows[row], button)
    end
    dialog = ButtonDialog:new{ buttons = rows }
    UIManager:show(dialog)
end

function SaforumsUI:show_list_jump_dialog(parsed, page_number, title, source, forum_id)
    local total = parsed.pagination and parsed.pagination.total_pages or 1
    local dialog
    dialog = InputDialog:new{
        title = _("Jump to page"),
        input_type = "number",
        input = tostring(page_number),
        buttons = { {
            {
                text = _("Cancel"),
                callback = function()
                    UIManager:close(dialog)
                end,
            },
            {
                text = _("Jump"),
                is_enter = true,
                callback = function()
                    local target = tonumber(dialog:getInputText())
                    UIManager:close(dialog)
                    if target and target >= 1 and target <= total and target ~= page_number then
                        if source == "bookmarks" then
                            self:show_bookmarks(target)
                        else
                            self:show_thread_list(forum_id, target, title)
                        end
                    end
                end,
            },
        } },
    }
    UIManager:show(dialog)
end

--- Hold actions on a thread row, in the reference client's order (minus
--- author profiles, which land with Wave D). Conditions follow thread
--- state: mark-read only for never-opened threads, mark-unread only for
--- seen ones, bookmark removal when the bookmark is known.
function SaforumsUI:thread_hold_menu(thread, source)
    local ButtonDialog = require("ui/widget/buttondialog")
    local dialog
    local buttons = {}
    local function add(text, callback)
        buttons[#buttons + 1] = { text = text, callback = function()
            UIManager:close(dialog)
            callback()
        end }
    end

    add(_("Open first page"), function()
        self:open_thread(thread, { page = 1, mode = "browse" })
    end)
    if thread.unread_count then
        add(_("Open at first unread"), function()
            self:open_thread(thread, { mode = "continue" })
        end)
    end
    local pages = thread.replies and (math.floor(thread.replies / config.perpage) + 1) or 1
    if pages > 1 then
        add(string.format(_("Open last page (%d)"), pages), function()
            self:open_thread(thread, { page = pages, mode = "browse" })
        end)
    end
    if thread.id then
        add(_("Copy link"), function()
            self:copy_text(config.base_url .. "/showthread.php?threadid=" .. thread.id
                .. "&perpage=" .. config.perpage .. "&noseen=1", _("Link copied."))
        end)
    end
    if thread.title then
        add(_("Copy title"), function()
            self:copy_text(thread.title, _("Title copied."))
        end)
    end
    if thread.unread_count == nil and not thread.is_read then
        add(_("Mark read"), function()
            self:mark_thread_read(thread)
        end)
    else
        add(_("Mark unread"), function()
            self:mark_thread_unread(thread)
        end)
    end
    add(_("Set star…"), function()
        self:show_star_menu(thread)
    end)
    if source == "bookmarks" or thread.star then
        add(_("Remove bookmark"), function()
            self:set_bookmark(thread, false)
        end)
    else
        add(_("Add bookmark"), function()
            self:set_bookmark(thread, true)
        end)
    end

    local rows = {}
    for index, button in ipairs(buttons) do
        local row = math.floor((index - 1) / 2) + 1
        rows[row] = rows[row] or {}
        table.insert(rows[row], button)
    end
    dialog = ButtonDialog:new{ buttons = rows }
    UIManager:show(dialog)
end

function SaforumsUI:mark_thread_read(thread)
    self:when_online(function()
        local result = self.session:get(config.base_url .. "/showthread.php?threadid=" .. thread.id
            .. "&perpage=" .. config.perpage .. "&goto=lastpost")
        if result.kind == "ok" then
            self:forget_list_cache()
            self:save_list_state()
            self:message(_("Thread marked read."), 2)
        else
            self:show_result_error(result)
        end
    end)
end

function SaforumsUI:mark_thread_unread(thread)
    self:when_online(function()
        local result = self.session:request("POST", config.base_url .. "/showthread.php",
            { threadid = thread.id, action = "resetseen", json = "1" })
        if result.kind == "ok" then
            self:forget_list_cache()
            self:save_list_state()
            self:message(_("Thread marked unread."), 2)
        else
            self:show_result_error(result)
        end
    end)
end

function SaforumsUI:set_bookmark(thread, adding)
    self:when_online(function()
        local result = self.session:request("POST", config.base_url .. "/bookmarkthreads.php",
            { json = "1", action = adding and "add" or "remove", threadid = thread.id })
        if result.kind == "ok" then
            self:forget_list_cache()
            self:save_list_state()
            self:message(adding and _("Bookmarked.") or _("Bookmark removed."), 2)
        else
            self:show_result_error(result)
        end
    end)
end

function SaforumsUI:show_star_menu(thread)
    local ButtonDialog = require("ui/widget/buttondialog")
    local dialog
    local flat = {}
    local function add(category, label)
        flat[#flat + 1] = { text = label, callback = function()
            UIManager:close(dialog)
            self:set_star(thread, category)
        end }
    end
    add(-1, _("None"))
    for star = 0, 5 do
        add(star, config.star_letters[star])
    end
    local rows = {}
    for index, button in ipairs(flat) do
        local row = math.floor((index - 1) / 4) + 1
        rows[row] = rows[row] or {}
        table.insert(rows[row], button)
    end
    dialog = ButtonDialog:new{ buttons = rows }
    UIManager:show(dialog)
end

--- Setting a star is the reference client's bookmark-color write: the same
--- action=add POST carries category_id (-1 clears the star).
function SaforumsUI:set_star(thread, category)
    self:when_online(function()
        local result = self.session:request("POST", config.base_url .. "/bookmarkthreads.php",
            { json = "1", action = "add", threadid = thread.id, category_id = tostring(category) })
        if result.kind == "ok" then
            self:forget_list_cache()
            self:save_list_state()
            self:message(_("Star set."), 2)
        else
            self:show_result_error(result)
        end
    end)
end

--- Announcements: the body comes from announcement.php (read-only), parsed
--- from its td.postbody cells, cached per forum, and read state is local,
--- tracked by title (spec: Read state).
function SaforumsUI:open_announcement(forum_id, announcement)
    self:message(_("Fetching announcement…"))
    self:when_online(function()
        local key = "announcements:" .. tostring(forum_id)
        local body_html
        if self.cache:fresh(key, config.cache_ttl_announcements) then
            body_html = self.cache:get(key)
        else
            local result = self.session:get(config.base_url .. "/announcement.php?forumid=" .. forum_id)
            if self:show_result_error(result) then return end
            body_html = self:parse_announcement_body(result.body or "")
            if body_html then
                self.cache:put(key, body_html)
                self:save_list_state()
            end
        end
        if not body_html then
            self:message(_("The announcement body did not parse."), 3)
            return
        end
        self.read_announcements[announcement.title or ""] = true
        self:save_list_state()
        local ThreadView = require("saforums.threadview")
        UIManager:show(ThreadView:new{
            title = announcement.title or _("Announcement"),
            posts = { {
                index = 1,
                author_name = announcement.author_name,
                author_is_op = true,
                date_raw = announcement.last_post_date,
                body_html = body_html,
                seen = true,
            } },
            avatars = {},
            forum_id = forum_id,
            username = self:username(),
            page = 1,
            total_pages = 1,
            on_close = function() end,
        })
    end)
end

function SaforumsUI:parse_announcement_body(html)
    local htmlparser = require("htmlparser")
    local root = htmlparser.parse(html, 200000)
    local parts = {}
    for _idx, postbody in ipairs(root:select("td.postbody")) do
        parts[#parts + 1] = htmltext.content(postbody)
    end
    if #parts == 0 then
        return nil
    end
    return table.concat(parts, "<br/>")
end

function SaforumsUI:open_thread(thread, opts)
    opts = opts or {}
    -- A thread on top invalidates any pending stale-while-revalidate swap:
    -- the list beneath the thread must not be swapped out mid-read.
    self._list_token = nil
    local page = opts.page or 1
    local mode = opts.mode or "browse"
    self:message(_("Fetching thread…"))
    self:when_online(function()
        local url = config.base_url .. "/showthread.php?threadid=" .. thread.id
            .. "&perpage=" .. config.perpage
        if mode == "continue" then
            url = url .. "&goto=newpost"
        else
            url = url .. "&pagenumber=" .. page .. "&noseen=1"
        end
        local result = self.session:get(url)
        if self:show_result_error(result) then return end
        local parsed = postspageparser.parse(result.body or "")
        if #parsed.posts == 0 then
            self:message(_("No posts found on that page."), 3)
            return
        end

        -- Where to land: an explicit jump target wins; else the first post
        -- the page still reports unseen.
        local jump_index = result.jump_index
        if not jump_index then
            for _idx, post in ipairs(parsed.posts) do
                if not post.seen then
                    jump_index = post.index
                    break
                end
            end
        end

        local thread_id = parsed.thread_id or thread.id
        local pagination = parsed.pagination or {}
        local this_page = pagination.current_page or page
        local total_pages = pagination.total_pages or page

        -- Continue-mode: seen tint approximates the pre-view state (the
        -- fetch itself marks the page read server-side).
        if mode == "continue" and jump_index then
            for _idx, post in ipairs(parsed.posts) do
                post.seen = post.index < jump_index
            end
        end

        logger.info(string.format("saforums: rendering page %s/%s with %d posts",
            tostring(this_page), tostring(total_pages), #parsed.posts))

        local ThreadView = require("saforums.threadview")
        local view
        view = ThreadView:new{
            title = parsed.title or thread.title,
            posts = parsed.posts,
            avatars = {},
            thread_id = thread_id,
            forum_id = parsed.forum_id,
            username = self:username(),
            page = this_page,
            total_pages = total_pages,
            jump_index = jump_index,
            on_close = function() end,
            on_page_action = function(action, target)
                if action == "jump" then
                    self:open_thread(thread, { page = target, mode = "browse" })
                    return
                end
                local delta = action == "nextpage" and 1 or -1
                local next_target = this_page + delta
                if next_target >= 1 and next_target <= total_pages then
                    self:open_thread(thread, { page = next_target, mode = "browse" })
                end
            end,
            on_post_hold = function(post)
                self:show_post_menu(view, post)
            end,
            on_image_tap = function(src, label)
                self:open_image(src, label)
            end,
        }
        UIManager:show(view)

        -- Avatars are a second pass AFTER first paint: one scheduled step
        -- per fetch, yielding to the event loop between each. No overlay,
        -- no toast, nothing between the user and the posts. The view swaps
        -- the avatars in with one repaint when the pass completes; closing
        -- the view sets a flag that stops the pass.
        local avatar_cache = require("saforums.avatars")
        local pending = {}
        local seen_poster = {}
        for _idx, post in ipairs(parsed.posts) do
            local uid = post.author_id
            if uid and post.avatar_src and not seen_poster[uid]
                and avatar_cache.is_avatar_candidate(post.avatar_src) then
                seen_poster[uid] = true
                pending[#pending + 1] = { uid = uid, src = post.avatar_src }
            end
        end
        if #pending > 0 then
            local dir = data_dir()
            if not lfs.attributes(dir, "mode") then
                lfs.mkdir(dir)
            end
            local avatar_cache_dir = dir .. "/avatars"
            local avatars = {}
            local function fetch_step(i)
                if view.discarded or i > #pending then
                    if next(avatars) then
                        view:set_avatars(avatars)
                    end
                    return
                end
                local item = pending[i]
                local cached = avatar_cache.ensure(avatar_cache_dir, self.session, item.uid, item.src)
                if cached then
                    avatars[item.uid] = cached
                end
                UIManager:scheduleIn(0.25, function()
                    fetch_step(i + 1)
                end)
            end
            UIManager:scheduleIn(1.0, function()
                fetch_step(1)
            end)
        end
    end)
end

--- The logged-in user's name, when the plugin performed the login (cookie
--- imports skip it; mentions simply go unmarked then).
function SaforumsUI:username()
    return self.settings:readSetting("saforums_username")
end

--- Permalink to one post (the reference client's format: noseen always,
--- page only past the first, the post addressed by fragment).
function ui.post_permalink(thread_id, page, post_id)
    local url = config.base_url .. "/showthread.php?threadid=" .. thread_id
        .. "&perpage=" .. config.perpage .. "&noseen=1"
    if page and page > 1 then
        url = url .. "&pagenumber=" .. page
    end
    return url .. "#post" .. post_id
end

function SaforumsUI:copy_text(text, toast_text)
    local input = Device.input
    if input and input.setClipboardText then
        input.setClipboardText(text)
        self:message(toast_text, 2)
    else
        self:message(_("This device has no clipboard."), 3)
    end
end

--- The post's body as plain text, one block per line: paragraphs and
--- spoilers as their text, quotes led by their header, images and embeds
--- by their placeholder label. PTF/bold markers are presentation, not
--- content, and come off.
function SaforumsUI:post_plain_text(post)
    local lines = {}
    local sanitized = require("saforums.posthtml").sanitize_body(post.body_html)
    for _idx, block in ipairs(postblocks.parse(sanitized)) do
        local text = block.text or block.label or ""
        text = text:gsub(postblocks.PTF_HEADER, "")
        text = text:gsub(postblocks.BOLD_START, ""):gsub(postblocks.BOLD_END, "")
        if block.type == "quote" and block.header then
            lines[#lines + 1] = block.header
        end
        if text ~= "" then
            lines[#lines + 1] = text
        end
    end
    return table.concat(lines, "\n")
end

--- Hold on a post: the lurker's per-post actions (spec: Read state makes
--- the setseen write an explicit user action only).
function SaforumsUI:show_post_menu(view, post)
    local ButtonDialog = require("ui/widget/buttondialog")
    local dialog
    local buttons = {}

    if post.id and view.thread_id then
        buttons[#buttons + 1] = {
            text = _("Copy post URL"),
            callback = function()
                UIManager:close(dialog)
                self:copy_text(
                    ui.post_permalink(view.thread_id, view.page, post.id),
                    _("Link copied."))
            end,
        }
        buttons[#buttons + 1] = {
            text = _("Copy post BBcode"),
            callback = function()
                UIManager:close(dialog)
                self:copy_post_bbcode(view, post)
            end,
        }
    end
    buttons[#buttons + 1] = {
        text = _("Copy post text"),
        callback = function()
            UIManager:close(dialog)
            self:copy_text(self:post_plain_text(post), _("Post text copied."))
        end,
    }
    buttons[#buttons + 1] = {
        text = _("Mark read to here"),
        callback = function()
            UIManager:close(dialog)
            self:mark_read_to_here(view, post)
        end,
    }
    buttons[#buttons + 1] = {
        text = _("Close"),
        callback = function()
            UIManager:close(dialog)
        end,
    }

    dialog = ButtonDialog:new{
        buttons = { buttons },
    }
    UIManager:show(dialog)
end

--- The post's BBcode from the site's own quote form (the reference
--- client's copy path): a read-only GET of newreply.php with the post id,
--- whose vbform carries the quoted text in its message textarea.
function SaforumsUI:copy_post_bbcode(view, post)
    self:message(_("Fetching BBcode…"))
    self:when_online(function()
        local url = config.base_url .. "/newreply.php?action=newreply&postid=" .. post.id
        local result = self.session:get(url)
        if self:show_result_error(result) then return end
        local quoted = (result.body or ""):match('<textarea[^>]*name="message"[^>]*>(.-)</textarea>')
        if not quoted then
            self:message(_("The quote form did not answer; nothing copied."), 4)
            return
        end
        self:copy_text(htmltext.decode_entities(quoted), _("BBcode copied."))
    end)
end

function SaforumsUI:mark_read_to_here(view, post)
    self:when_online(function()
        local result = self.session:request("POST", config.base_url .. "/showthread.php",
            { action = "setseen", threadid = view.thread_id, index = post.index })
        if result.kind == "ok" then
            view:set_seen_up_to(post.index)
            self:message(_("Marked read to post #") .. post.index .. ".", 2)
        else
            self:show_result_error(result)
        end
    end)
end

--- Cache a fetched image under the data dir, keyed by its URL. Returns the
--- path, or nil when the disk refuses.
function SaforumsUI:cache_image(src, bytes)
    local dir = data_dir() .. "/images"
    if not lfs.attributes(dir, "mode") then
        local created = lfs.mkdir(dir)
        if not created then
            logger.warn("saforums: image cache dir unusable:", dir)
            return nil
        end
    end
    local stem = (src:gsub("[^%w]", "")):sub(1, 96)
    local _, ext = require("saforums.avatars").mime_for(src)
    local path = dir .. "/" .. stem .. "-" .. #src .. "." .. ext
    if lfs.attributes(path, "mode") then
        return path
    end
    local file = io.open(path, "wb")
    if not file then
        logger.warn("saforums: cannot write image cache:", path)
        return nil
    end
    file:write(bytes)
    file:close()
    return path
end

--- Tap on an image block: fetch and show it full-screen; a dead fetch says
--- so in the image's own words.
function SaforumsUI:open_image(src, label)
    self:message(_("Fetching image…"))
    self:when_online(function()
        local result = self.session:get(src, { raw = true })
        if result.kind == "cloudflare" then
            self:show_result_error(result)
            return
        end
        if result.kind ~= "ok" or not result.body or #result.body == 0 then
            UIManager:show(InfoMessage:new{
                text = _("[dead image: ") .. (label or _("image")) .. "]",
                timeout = 4,
            })
            return
        end
        local path = self:cache_image(src, result.body)
        if not path then
            self:message(_("Could not store the image."), 3)
            return
        end
        local ImageViewer = require("ui/widget/imageviewer")
        UIManager:show(ImageViewer:new{
            file = path,
            fullscreen = true,
            with_title_bar = true,
            title_text = label or _("image"),
        })
    end)
end

--- Rough landing ratio for a jump target: posts are roughly uniform, so
--- the first unseen post sits at (index-1)/count of the scroll height.
function SaforumsUI:jump_ratio(jump_index, posts)
    if not jump_index or #posts == 0 then return 0 end
    local ratio = (jump_index - 1) / #posts
    if ratio < 0 then ratio = 0 end
    if ratio > 0.95 then ratio = 0.95 end
    return ratio
end

--- Per-thread, per-page scroll positions for the in-app view.
function SaforumsUI:get_position(thread_id, page)
    local positions = self.settings:readSetting("saforums_positions") or {}
    return positions[thread_id .. ":" .. page]
end

function SaforumsUI:save_position(thread_id, page, ratio)
    local positions = self.settings:readSetting("saforums_positions") or {}
    positions[thread_id .. ":" .. page] = ratio
    self.settings:saveSetting("saforums_positions", positions)
    self.settings:flush()
end

-- ---------------------------------------------------------------------------
-- Menu plumbing

function SaforumsUI:show_menu(title, items, on_select, on_hold)
    local menu = Menu:new{
        title = title,
        item_table = items,
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        onMenuSelect = function(menu_self, item)
            -- Items that open a screen on top of this one (threads,
            -- announcements, forums) keep the menu stacked beneath them, so
            -- closing that screen reveals the list exactly where it was.
            if not item.keep_menu then
                UIManager:close(menu_self)
            end
            if not item.no_action and on_select then
                on_select(item)
            end
        end,
        onMenuHold = function(menu_self, item)
            if on_hold then
                local hold_menu = on_hold(item)
                if hold_menu then
                    UIManager:show(hold_menu)
                end
            end
        end,
    }
    self._last_menu = menu
    UIManager:show(menu)
    return menu
end

ui.SaforumsUI = SaforumsUI

return ui
