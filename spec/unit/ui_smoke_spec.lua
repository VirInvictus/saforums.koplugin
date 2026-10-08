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
    screen = { getWidth = function() return 1264 end, getHeight = function() return 1680 end, scaleBySize = function(_, n) return n end },
    input = { group = { Back = "Back" } },
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
