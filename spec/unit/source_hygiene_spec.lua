-- Source hygiene for the device-facing files.
--
-- gettext's function is named `_`, so in any file where it is in scope a
-- `for _, x in ipairs(...)` loop shadows it with the loop index, and the
-- first `_("literal")` inside that loop body crashes with "attempt to call
-- local '_' (a number value)". That exact crash took down the thread list
-- on the first live pass (sticky threads hit the marker line). This spec
-- keeps the whole class out of the codebase: in gettext-scoped files,
-- loop placeholders must be named.

local GETTEXT_SCOPED_FILES = {
    "main.lua",
    "saforums/ui.lua",
}

describe("source hygiene", function()
    for _, file in ipairs(GETTEXT_SCOPED_FILES) do
        it(file .. " never shadows gettext's _ with a loop variable", function()
            local handle = io.open(file, "r")
            assert.is_truthy(handle, "could not read " .. file)
            local source = handle:read("*a")
            handle:close()

            local offenders = {}
            local line_no = 0
            for line in source:gmatch("[^\n]*") do
                line_no = line_no + 1
                if line:find("for%s+_[%s,=]") then
                    offenders[#offenders + 1] = line_no .. ": " .. line
                end
            end
            assert.equals(0, #offenders,
                "underscore loop placeholders found (they shadow gettext):\n"
                .. table.concat(offenders, "\n"))
        end)
    end
end)
