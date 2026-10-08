require("spec.stubs")

local cp1252 = require("saforums.cp1252")

describe("cp1252", function()
    describe("decode", function()
        it("passes ASCII through untouched", function()
            assert.equals("plain text 123", cp1252.decode("plain text 123"))
        end)

        it("decodes Latin-1 range bytes as UTF-8", function()
            assert.equals("caf\xC3\xA9", cp1252.decode("caf\xE9"))
        end)

        it("decodes the 0x80-0x9F printable range", function()
            assert.equals("\xE2\x82\xAC", cp1252.decode("\x80")) -- euro
            assert.equals("\xE2\x80\xA6", cp1252.decode("\x85")) -- ellipsis
            assert.equals("\xE2\x80\x99", cp1252.decode("\x92")) -- right single quote
            assert.equals("\xE2\x80\x94", cp1252.decode("\x97")) -- em dash
            assert.equals("\xE2\x84\xA2", cp1252.decode("\x99")) -- trademark
        end)

        it("replaces undefined 0x80-0x9F slots with U+FFFD", function()
            for _, byte in ipairs({ 0x81, 0x8D, 0x8F, 0x90, 0x9D }) do
                assert.equals("\xEF\xBF\xBD", cp1252.decode(string.char(byte)))
            end
        end)

        it("handles a mixed document", function()
            local decoded = cp1252.decode("It\x92s caf\xE9 time \x85 \x805")
            assert.equals("It\xE2\x80\x99s caf\xC3\xA9 time \xE2\x80\xA6 \xE2\x82\xAC5", decoded)
        end)
    end)

    describe("encode", function()
        it("passes ASCII through untouched", function()
            assert.equals("username=free_user", cp1252.encode("username=free_user"))
        end)

        it("maps Latin-1 range to single bytes", function()
            assert.equals("caf\xE9", cp1252.encode("caf\xC3\xA9"))
        end)

        it("maps the 0x80-0x9F range", function()
            assert.equals("\x92", cp1252.encode("\xE2\x80\x99"))
            assert.equals("\x85", cp1252.encode("\xE2\x80\xA6"))
        end)

        it("entity-escapes unrepresentable codepoints", function()
            assert.equals("emoji &#128579;", cp1252.encode("emoji \xF0\x9F\x99\x83"))
        end)

        it("replaces malformed UTF-8 with U+FFFD instead of corrupting", function()
            assert.equals("\xEF\xBF\xBD\xEF\xBF\xBD", cp1252.encode("\xC0\x80"))
        end)

        it("round-trips everything cp1252 can carry", function()
            local cp1252_originals = { "na\xEFve", "fa\xE7ade", "don\x92t", "\x805.99", "\x93quote\x94" }
            for _, s in ipairs(cp1252_originals) do
                assert.equals(s, cp1252.encode(cp1252.decode(s)))
            end
        end)
    end)
end)
