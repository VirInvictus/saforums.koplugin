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
preload("dispatcher", {
    registerAction = function() end,
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
end)
