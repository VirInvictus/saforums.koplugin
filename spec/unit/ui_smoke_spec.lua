require("spec.stubs")

-- The device-facing modules pull in half of KOReader. These stubs exist so
-- they at least LOAD here: every typo, missing require, or top-level crash
-- gets caught by busted instead of only on the device.
local function preload(name, module)
    if not package.loaded[name] and not package.preload[name] then
        package.preload[name] = function()
            return module
        end
    end
end

local widget = setmetatable({ new = function(self, options) return options end }, {})
preload("ui/widget/infomessage", widget)
preload("ui/widget/inputdialog", widget)
preload("ui/widget/confirmbox", widget)
preload("ui/widget/menu", widget)
preload("ui/uimanager", {
    show = function() end,
    close = function() end,
    nextTick = function(_, callback) callback() end,
    setDirty = function() end,
})
preload("datastorage", {
    getSettingsDir = function() return "/tmp/saforums-test" end,
    getDataDir = function() return "/tmp/saforums-test" end,
    getFullDataDir = function() return "/tmp/saforums-test" end,
})
preload("luasettings", {
    open = function()
        return {
            readSetting = function() return nil end,
            saveSetting = function() end,
            flush = function() end,
        }
    end,
})
preload("ui/network/manager", {
    runWhenOnline = function(_, callback) callback() end,
})
preload("apps/reader/readerui", {
    showReader = function() end,
})
preload("libs/libkoreader-lfs", {
    attributes = function() return nil end,
    mkdir = function() end,
})
local dispatcher_stub = { registerAction = function() end }
preload("dispatcher", dispatcher_stub)
-- The thread view widget chain (device-only modules).
preload("ffi/blitbuffer", { COLOR_WHITE = {}, gray = function(_, level) return { level = level } end })
preload("ui/geometry", { new = function(_, t) return t end })
preload("ui/widget/verticalgroup", { new = function(_, items) return items end })
preload("ui/widget/container/framecontainer", { new = function(_, options) return options end })
preload("device", {
    hasKeys = function() return false end,
    isTouchDevice = function() return true end,
    screen = { getWidth = function() return 1264 end, getHeight = function() return 1680 end, scaleBySize = function(_, n) return n end },
    input = {
        group = { Back = "Back" },
        setClipboardText = function(text) end,
        hasClipboardText = function() return true end,
    },
})
preload("ui/font", { getFace = function(_, face, size) return { name = face, size = size } end })
preload("ui/widget/textwidget", { new = function(_, o) return o end })
preload("ui/widget/textboxwidget", { new = function(_, o) return o end })
preload("ui/widget/imagewidget", { new = function(_, o) return o end })
preload("ui/widget/linewidget", { new = function(_, o) return o end })
preload("ui/widget/horizontalgroup", { new = function(_, items) items.getSize = function() return { h = 30 } end; return items end })
preload("ui/widget/horizontalspan", { new = function(_, o) return o end })
preload("ui/widget/verticalspan", { new = function(_, o) return o end })
preload("ui/widget/iconbutton", { new = function(_, o) return o end })
preload("ui/widget/container/scrollablecontainer", { new = function(_, o) return o end })
preload("ui/gesturerange", { new = function(_, o) return o end })
preload("ui/widget/buttondialog", widget)
preload("ui/widget/imageviewer", widget)
preload("ui/trapper", {
    wrap = function(_, fn) fn() end,
    info = function() return true end,
})
preload("ui/widget/container/inputcontainer", {
    extend = function(_, members)
        local cls = {}
        for key, value in pairs(members) do cls[key] = value end
        cls.__index = cls
        function cls.new(_, attr)
            local instance = setmetatable({}, cls)
            for key, value in pairs(attr or {}) do
                instance[key] = value
            end
            if instance.init then
                instance:init()
            end
            return instance
        end
        return cls
    end,
})
preload("ui/widget/titlebar", {
    new = function(_, options)
        options.getHeight = function() return 40 end
        return options
    end,
})
preload("ui/size", {
    padding = { large = 10, default = 5 },
    line = { medium = 1 },
})
preload("ui/widget/buttontable", {
    new = function(_, options)
        options.getSize = function() return { h = 40 } end
        return options
    end,
})
preload("ui/widget/container/centercontainer", {
    new = function(_, options) return options end,
})
preload("ui/widget/scrollhtmlwidget", {
    new = function(_, options)
        options.getCurrentRatio = function() return 0 end
        options.onScrollDown = function() end
        options.onScrollUp = function() end
        options.scrollToRatio = function() end
        return options
    end,
})
-- Mirrors the real WidgetContainer class system closely enough to catch the
-- failure class that cost us a device round-trip: PluginLoader does
-- pcall(plugin.new, plugin, attr), so a plugin module without .new dies
-- there, not at require time.
preload("ui/widget/container/widgetcontainer", {
    extend = function(_, members)
        local cls = {}
        for key, value in pairs(members) do
            cls[key] = value
        end
        cls.__index = cls
        function cls.new(_, attr)
            local instance = setmetatable({}, cls)
            for key, value in pairs(attr or {}) do
                instance[key] = value
            end
            if instance.init then
                instance:init()
            end
            return instance
        end
        return cls
    end,
})

local ui = require("saforums.ui")

-- Wave A interaction helpers: the widget stubs hand back the options
-- tables they were built with, so the view tree is walkable and the tap
-- callbacks are invocable directly.
local function collect_texts(node, out)
    out = out or {}
    if type(node) == "table" then
        if type(node.text) == "string" then
            out[#out + 1] = node.text
        end
        for _i, child in ipairs(node) do
            collect_texts(child, out)
        end
        if node.content then
            collect_texts(node.content, out)
        end
    end
    return out
end

local function has_text(texts, needle)
    for _i, text in ipairs(texts) do
        if text:find(needle, 1, true) then return true end
    end
    return false
end

local function find_taparea(node, needle)
    if type(node) ~= "table" then return nil end
    if node.content and node.callback and type(node.content) == "table"
        and type(node.content.text) == "string"
        and node.content.text:find(needle, 1, true) then
        return node
    end
    for _i, child in ipairs(node) do
        local found = find_taparea(child, needle)
        if found then return found end
    end
    if node.content then
        return find_taparea(node.content, needle)
    end
    return nil
end

local function simple_view(posts, extra)
    local threadview = require("saforums.threadview")
    local options = {
        title = "t",
        posts = posts,
        avatars = {},
        page = 1,
        total_pages = 2,
    }
    for key, value in pairs(extra or {}) do
        options[key] = value
    end
    return threadview:new(options)
end

describe("device UI (smoke)", function()
    it("modules load and the UI object constructs", function()
        local instance = ui.new()
        assert.is_not_nil(instance.session)
        assert.is_function(instance.show_forum_index)
    end)

    it("menu plumbing hands the selected item to the flow", function()
        local captured
        widget.new = function(_, options)
            captured = options
            return options
        end
        local chosen
        ui.SaforumsUI:show_menu(nil, { { text = "pick me", marker = 42 } }, function(item)
            chosen = item
        end)
        -- The widget stub never fires callbacks on its own: select like the
        -- real menu would.
        captured.onMenuSelect(captured, captured.item_table[1])
        assert.equals(42, chosen.marker)
    end)

    it("error mapping treats ok as not-an-error and surfaces the rest", function()
        local instance = ui.new()
        assert.is_false(instance:show_result_error(nil))
        assert.is_false(instance:show_result_error({ kind = "ok" }))
        assert.is_true(instance:show_result_error({ kind = "cloudflare" }))
        assert.is_true(instance:show_result_error({ kind = "http_error", code = 500 }))
    end)

    it("main.lua loads with the dispatcher stubbed", function()
        local plugin = require("main")
        assert.equals("saforums", plugin.name)
        assert.is_function(plugin.addToMainMenu)
    end)

    it("thread view constructs natively against the widget stubs", function()
        local threadview = require("saforums.threadview")
        local closed = false
        local paged
        local view = threadview:new{
            title = "t",
            posts = { { author_name = "a", body_html = "<b>x</b>", index = 1 } },
            avatars = {},
            page = 2,
            total_pages = 3,
            on_close = function() closed = true end,
            on_page_action = function(action) paged = action end,
        }
        assert.is_not_nil(view[1]) -- the frame was built
        view:onPageAction("nextpage")
        assert.equals("nextpage", paged)
        view:handleBack()
        assert.is_true(closed)
    end)

    it("open_thread drives parsed posts all the way into the view", function()
        -- regression: the native pivot's ui rewiring silently no-op'd, so
        -- ThreadView received the old html_body interface and rendered an
        -- empty frog page. This drives the real open_thread with a canned
        -- session response and asserts posts arrive.
        local shown
        package.loaded["ui/uimanager"].show = function(_, widget)
            shown = widget
        end
        package.loaded["ui/uimanager"].setDirty = function() end
        local fixture
        do
            local handle = io.open("spec/fixtures/postspage.html", "r")
            fixture = handle:read("*a")
            handle:close()
        end
        local instance = ui.new()
        instance.session.get = function(_, url, opts)
            assert.is_nil(opts) -- browse fetches are text; raw is for binaries
            return { kind = "ok", code = 200, body = fixture }
        end
        instance:open_thread({ id = "4231003", title = "t" }, { page = 1, mode = "browse" })
        assert.is_not_nil(shown, "no view was shown")
        assert.equals(3, #shown.posts)
        assert.equals(1, shown.page)
        assert.equals(7, shown.total_pages)
        package.loaded["ui/uimanager"].show = function() end
    end)

    it("main.lua instantiates the way PluginLoader does", function()
        local plugin = require("main")
        local registered
        -- registerAction is a method: (self, name, action-table).
        dispatcher_stub.registerAction = function(_, name, action)
            registered = action
        end
        local menus = {}
        local instance = plugin.new(plugin, {
            ui = { menu = { registerToMainMenu = function(_, entry) menus[#menus + 1] = entry end } },
        })
        assert.equals("saforums", instance.name)
        assert.is_truthy(registered)
        assert.equals("OpenSaforums", registered.event)
        assert.equals(1, #menus)
        assert.is_function(menus[1].addToMainMenu)
        local menu_items = {}
        menus[1]:addToMainMenu(menu_items)
        assert.equals("tools", menu_items.saforums.sorting_hint)
        dispatcher_stub.registerAction = function() end
    end)
end)

describe("wave A: reading parity interactions", function()
    it("quote collapse shows the toggle and flips per quote", function()
        local postblocks = require("saforums.postblocks")
        local real_collapsed = postblocks.collapsed_text
        postblocks.collapsed_text = function() return "first three lines", 4 end
        local view = simple_view({
            { author_name = "a", index = 1, body_html = "<blockquote>long quote</blockquote>" },
        })

        assert.is_truthy(has_text(collect_texts(view), "+4 lines"))
        view:toggle_quote(1, 1)
        assert.is_truthy(view:quote_is_expanded(1, 1))
        assert.is_truthy(has_text(collect_texts(view), "less"))
        assert.is_falsy(has_text(collect_texts(view), "+4 lines"))
        view:toggle_quote(1, 1)
        assert.is_false(view:quote_is_expanded(1, 1))
        assert.is_truthy(has_text(collect_texts(view), "+4 lines"))
        postblocks.collapsed_text = real_collapsed
    end)

    it("spoilers render masked and toggle per post", function()
        local view = simple_view({
            { author_name = "a", index = 1,
                body_html = 'before<span class="spoiler">[spoiler] shh [/spoiler]</span>' },
        })
        assert.is_false(view:spoilers_revealed(1))
        assert.is_truthy(has_text(collect_texts(view), "spoiler (tap to view)"))
        view:toggle_spoilers(1)
        assert.is_truthy(view:spoilers_revealed(1))
        local texts = collect_texts(view)
        assert.is_truthy(has_text(texts, "shh"))
        assert.is_falsy(has_text(texts, "tap to view"))
        view:toggle_spoilers(1)
        assert.is_false(view:spoilers_revealed(1))
    end)

    it("holding a card hands that post to the action menu", function()
        local held
        local view = simple_view({
            { author_name = "a", index = 1, body_html = "x" },
        }, { on_post_hold = function(post) held = post end })
        local top = view._scrollable.dimen.y
        assert.is_truthy(view:onHold(nil, { pos = { x = 100, y = top } }))
        assert.equals("a", held.author_name)
        held = nil
        assert.is_falsy(view:onHold(nil, { pos = { x = 100, y = top + 5000 } }))
        assert.is_nil(held)
    end)

    it("mark-read-to-here retints locally up to the index", function()
        local view = simple_view({
            { author_name = "a", index = 1, body_html = "x", seen = true },
            { author_name = "b", index = 2, body_html = "y" },
            { author_name = "c", index = 3, body_html = "z" },
        })
        view:set_seen_up_to(2)
        assert.is_true(view.posts[1].seen)
        assert.is_true(view.posts[2].seen)
        assert.is_falsy(view.posts[3].seen)
    end)

    it("the page label opens the jump dialog and passes a valid target", function()
        local shown_dialog
        package.loaded["ui/uimanager"].show = function(_, w) shown_dialog = w end
        local jumped
        local view = simple_view({
            { author_name = "a", index = 1, body_html = "x" },
        }, { page = 2, total_pages = 5, on_page_action = function(action, target) jumped = { action, target } end })

        view:show_jump_dialog()
        assert.is_not_nil(shown_dialog)
        shown_dialog.getInputText = function() return "4" end
        shown_dialog.buttons[1][2].callback()
        assert.equals("jump", jumped[1])
        assert.equals(4, jumped[2])

        jumped = nil
        view:show_jump_dialog()
        shown_dialog.getInputText = function() return "9" end
        shown_dialog.buttons[1][2].callback()
        assert.is_nil(jumped)
        package.loaded["ui/uimanager"].show = function() end
    end)

    it("role badges render after the name and forums can hide the regdate", function()
        local base = {
            author_name = "Mod Person", index = 1, body_html = "x",
            author_is_mod = true, author_is_platinum = true,
            regdate = "Jan 1, 2010",
        }
        local shown_view = simple_view({ base }, { forum_id = "46" })
        local texts = collect_texts(shown_view)
        assert.is_truthy(has_text(texts, "[mod] [PT]"))
        assert.is_truthy(has_text(texts, "joined Jan 1, 2010"))

        local hidden_view = simple_view({ base }, { forum_id = "26" })
        assert.is_falsy(has_text(collect_texts(hidden_view), "joined Jan 1, 2010"))
    end)

    it("the last page carries the end marker, earlier pages do not", function()
        local last = simple_view({
            { author_name = "a", index = 1, body_html = "x" },
        }, { page = 2, total_pages = 2 })
        assert.is_truthy(has_text(collect_texts(last), "End of the thread"))

        local early = simple_view({
            { author_name = "a", index = 1, body_html = "x" },
        }, { page = 1, total_pages = 2 })
        assert.is_falsy(has_text(collect_texts(early), "End of the thread"))
    end)

    it("tapping an image block hands its URL to the viewer flow", function()
        local tapped
        local view = simple_view({
            { author_name = "a", index = 1,
                body_html = '<span class="imgref" src="https://img.fixture.invalid/x.png">[image: x.png]</span>' },
        }, { on_image_tap = function(src, label) tapped = { src, label } end })
        local area = find_taparea(view[1], "x.png")
        assert.is_not_nil(area)
        area.callback()
        assert.equals("https://img.fixture.invalid/x.png", tapped[1])
        assert.equals("[image: x.png]", tapped[2])
    end)

    it("embed placeholders render as plain meta labels", function()
        local view = simple_view({
            { author_name = "a", index = 1,
                body_html = '<span class="embedref">[tweet: @someone]</span>' },
        })
        assert.is_truthy(has_text(collect_texts(view), "[tweet: @someone]"))
    end)
    it("copy post BBcode fetches the quote form and decodes entities", function()
        local instance = ui.new()
        local clipboard
        package.loaded["device"].input.setClipboardText = function(text) clipboard = text end
        instance.session.get = function(_, url)
            assert.matches("newreply%.php%?action=newreply&postid=77", url)
            return { kind = "ok", code = 200,
                body = '<form><textarea name="message" rows="10">[quote=dude]hi &amp; bye[/quote]</textarea></form>' }
        end

        instance:copy_post_bbcode({ thread_id = "42" }, { id = "77" })
        assert.equals("[quote=dude]hi & bye[/quote]", clipboard)
        package.loaded["device"].input.setClipboardText = function() end
    end)

    it("copy post BBcode reports a missing quote form instead of pasting junk", function()
        local instance = ui.new()
        local clipboard
        package.loaded["device"].input.setClipboardText = function(text) clipboard = text end
        local told
        instance.message = function(_, text, _timeout) told = text end
        instance.session.get = function()
            return { kind = "ok", code = 200, body = "<html>no form here</html>" }
        end

        instance:copy_post_bbcode({ thread_id = "42" }, { id = "77" })
        assert.is_nil(clipboard)
        assert.is_truthy(told)
        package.loaded["device"].input.setClipboardText = function() end
    end)
end)

describe("wave A: post actions", function()
    it("permalinks follow the reference format", function()
        assert.equals(
            "https://forums.somethingawful.com/showthread.php?threadid=42&perpage=40&noseen=1#post77",
            ui.post_permalink("42", 1, "77"))
        assert.equals(
            "https://forums.somethingawful.com/showthread.php?threadid=42&perpage=40&noseen=1&pagenumber=3#post77",
            ui.post_permalink("42", 3, "77"))
    end)

    it("copy post text strips the presentation markers", function()
        local instance = ui.new()
        local text = instance:post_plain_text({
            body_html = "<blockquote><h4>x posted:</h4>quoted <b>words</b></blockquote>tail",
        })
        assert.equals("x posted:\nquoted words\ntail", text)
    end)

    it("the post menu wires copy and mark-read actions", function()
        local buttondialog = require("ui/widget/buttondialog")
        local dialog_options
        buttondialog.new = function(_, options)
            dialog_options = options
            return options
        end
        local clipboard
        package.loaded["device"].input.setClipboardText = function(text) clipboard = text end

        local instance = ui.new()
        local seen_to
        local fake_view = {
            thread_id = "42",
            page = 1,
            set_seen_up_to = function(_, index) seen_to = index end,
        }
        local posted
        instance.session.request = function(_, method, url, fields)
            posted = { method = method, url = url, fields = fields }
            return { kind = "ok" }
        end

        instance:show_post_menu(fake_view, { id = "77", index = 5, body_html = "words" })
        -- hold the dialog's own table: later widget.new calls (toasts) must
        -- not re-point us at them
        local dlg = dialog_options
        assert.equals(5, #dlg.buttons[1])

        dlg.buttons[1][1].callback() -- copy URL
        assert.equals("https://forums.somethingawful.com/showthread.php?threadid=42&perpage=40&noseen=1#post77",
            clipboard)

        dlg.buttons[1][4].callback() -- mark read to here
        assert.equals("POST", posted.method)
        assert.equals("setseen", posted.fields.action)
        assert.equals("42", posted.fields.threadid)
        assert.equals(5, posted.fields.index)
        assert.equals(5, seen_to)

        package.loaded["ui/widget/buttondialog"].new = function(_, options) return options end
        package.loaded["device"].input.setClipboardText = function() end
    end)
    it("images open in the viewer from the cache; dead ones say so", function()
        local instance = ui.new()
        local shown_widget
        package.loaded["ui/uimanager"].show = function(_, w) shown_widget = w end
        instance.cache_image = function(_, src, bytes)
            return "/tmp/saforums-test-cache/" .. (#bytes) .. ".png"
        end
        instance.session.get = function(_, url, opts)
            assert.is_true(opts ~= nil and opts.raw == true)
            if url:find("dead", 1, true) then
                return { kind = "http_error", code = 404 }
            end
            return { kind = "ok", code = 200, body = "PNGDATA" }
        end

        instance:open_image("https://img.fixture.invalid/live.png", "[image: live.png]")
        assert.is_truthy(shown_widget and shown_widget.file
            and shown_widget.file:find("cache", 1, true))

        shown_widget = nil
        instance:open_image("https://img.fixture.invalid/dead.png", "[image: dead.png]")
        assert.is_truthy(shown_widget and shown_widget.text
            and shown_widget.text:find("[dead image: [image: dead.png]]", 1, true))
        package.loaded["ui/uimanager"].show = function() end
    end)

    it("image caching degrades gracefully when the disk refuses", function()
        local instance = ui.new()
        assert.is_nil(instance:cache_image("https://x.fixture.invalid/a.png", "bytes"))
    end)
end)
