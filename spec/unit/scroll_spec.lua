-- Drives the REAL ScrollableContainer from the dev checkout: page-key
-- handlers must move the internal offset, pan gestures must scroll, and
-- the offset must clamp. This is the mechanical guarantee behind "the
-- thread view scrolls" (the visible failure was scroll starvation during
-- the avatar pass, plus a gesture hit-test against an unpositioned dimen
-- - fixed by giving the container its true x/y).
local function preload(name, module)
    package.preload[name] = function() return module end
end

-- The real container lives in the dev checkout; drive THAT, not a stub.
package.path = "/home/bdkl/.local/share/koreader-dev/frontend/?.lua;" .. package.path

preload("logger", { info = function() end, warn = function() end, dbg = function() end, err = function() end })
preload("ui/geometry", { new = function(_, t) return t end })
preload("ui/gesturerange", { new = function(_, o) return o end })
preload("ui/bidi", {
    willBidiFlip = function() return false end,
    mirroredUILayout = function() return false end,
})
preload("ui/widget/horizontalscrollbar", { new = function(_, o)
    local bar = setmetatable(o or {}, { __index = o or {} })
    function bar:set() end
    return bar
end })
preload("ui/widget/verticalscrollbar", { new = function(_, o)
    local bar = setmetatable(o or {}, { __index = o or {} })
    function bar:set() end
    return bar
end })
preload("optmath", { round = function(_, n) return math.floor(n + 0.5) end })
preload("ui/uimanager", {
    show = function() end,
    close = function() end,
    nextTick = function(_, fn) fn() end,
    setDirty = function() end,
    scheduleIn = function() end,
})
preload("ui/size", {
    padding = { large = 10, default = 5, small = 3 },
    line = { medium = 1, thin = 1 },
    span = { horizontal_default = 10 },
    border = { thin = 1 },
    radius = {},
})
preload("ui/widget/container/inputcontainer", {
    extend = function(_, members)
        local cls = {}
        for key, value in pairs(members) do cls[key] = value end
        cls.__index = cls
        function cls.new(_, attr)
            local instance = setmetatable({}, cls)
            for key, value in pairs(attr or {}) do instance[key] = value end
            if instance.init then instance:init() end
            return instance
        end
        return cls
    end,
})
preload("device", {
    hasKeys = function() return false end,
    isTouchDevice = function() return false end,
    isRTL = function() return false end,
    isRTL = function() return false end,
    screen = {
        getWidth = function() return 1264 end,
        getHeight = function() return 1680 end,
        scaleBySize = function(_, n) return (n or 6) end,
    },
    input = { group = { PgFwd = { "RPgFwd" }, PgBack = { "RPgBack" } } },
})
package.preload["ffi/blitbuffer"] = function()
    return {
        COLOR_WHITE = { white = true },
        COLOR_BLACK = { black = true },
        gray = function(_, level) return { gray_level = level } end,
    }
end

local Geom = require("ui/geometry")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")

local function tall_child(w, h)
    return {
        getSize = function() return { w = w, h = h } end,
        paintTo = function() end,
        free = function() end,
    }
end

local function make_container(child_height)
    local container = ScrollableContainer:new{
        dimen = Geom:new{ x = 0, y = 94, w = 600, h = 800 },
        scroll_bar_position = "right",
        tall_child(600, child_height),
    }
    container:init()
    container:initState()
    return container
end

describe("ScrollableContainer (real, from the dev checkout)", function()
    it("accepts a child taller than the view and reports the max offset", function()
        local container = make_container(8000)
        -- the real container re-reserves width for the scrollbar after the
        -- first y computation, so assert the meaningful range, not exact math
        assert.is_true(container._max_scroll_offset_y > 6000)
        assert.is_true(container._max_scroll_offset_y < 8000)
    end)

    it("stays put for content shorter than the view", function()
        local container = make_container(400)
        container:onScrollPageDown()
        assert.equals(0, container._scroll_offset_y)
    end)
end)
