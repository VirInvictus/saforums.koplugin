require("spec.stubs")

local config = require("saforums.config")

-- The plugin marketplaces regex these out of _meta.lua (App Store and
-- Storefront both extract plain quoted strings for name and version); a
-- gettext wrapper here would silently break update detection.
local meta_text
do
    local handle = io.open("_meta.lua", "r")
    meta_text = handle:read("*a")
    handle:close()
end

local function meta_field(field)
    return meta_text:match(field .. '%s*=%s*"([^"]+)"')
end

describe("_meta.lua marketplace contract", function()
    it("carries a plain-string name matching the plugin id", function()
        assert.equals("saforums", meta_field("name"))
    end)

    it("carries a plain-string version in lockstep with VERSION", function()
        local version = io.open("VERSION", "r"):read("*l")
        assert.equals(version, meta_field("version"))
        assert.equals(config.version, meta_field("version"))
    end)
end)
