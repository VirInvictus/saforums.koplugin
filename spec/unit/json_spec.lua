require("spec.stubs")

local json = require("saforums.json")

describe("json", function()
    it("decodes scalars", function()
        assert.equals("hello", json.decode('"hello"'))
        assert.equals(42, json.decode("42"))
        assert.equals(-3.5, json.decode("-3.5"))
        assert.is_true(json.decode("true"))
        assert.is_false(json.decode("false"))
        assert.equals(json.null, json.decode("null"))
    end)

    it("decodes arrays and objects", function()
        assert.same({ 1, "two", { three = 3 } }, json.decode('[1, "two", {"three": 3}]'))
        local object = json.decode('{"a": {"b": [true, null]}}')
        assert.is_true(object.a.b[1])
        assert.equals(json.null, object.a.b[2])
    end)

    it("skips whitespace and allows trailing whitespace only", function()
        assert.same({ 1 }, json.decode('  [ 1 ]  \n'))
        assert.has_error(function() json.decode('[1] trailing') end)
    end)

    it("decodes string escapes", function()
        assert.equals("a\"b\\c/d\ne\tf", json.decode([["a\"b\\c\/d\ne\tf"]]))
    end)

    it("decodes BMP and surrogate-pair unicode escapes", function()
        assert.equals("\xC3\xA9", json.decode([["\u00e9"]]))       -- é
        assert.equals("\xF0\x9F\x99\x83", json.decode([["\uD83D\uDE43"]])) -- upside-down face
    end)

    it("rejects lone surrogates", function()
        assert.has_error(function() json.decode([["\uD83D"]]) end)
        assert.has_error(function() json.decode([["\uDE43"]]) end)
        assert.has_error(function() json.decode([["\uD83Dx"]]) end)
    end)

    it("fails with position on malformed input", function()
        local ok, err = pcall(json.decode, '{"a": }')
        assert.is_false(ok)
        assert.matches("at position 7", tostring(err), 1, true)
    end)

    it("keeps numbers the site actually sends", function()
        local object = json.decode('{"userid": 12345, "ratio": 0.75, "big": 12345678901}')
        assert.equals(12345, object.userid)
        assert.equals(0.75, object.ratio)
        assert.equals(12345678901, object.big)
    end)
end)
