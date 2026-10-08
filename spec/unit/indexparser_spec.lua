require("spec.stubs")

local indexparser = require("saforums.indexparser")

local function fixture(name)
    local handle = io.open("spec/fixtures/" .. name, "r")
    local content = handle:read("*a")
    handle:close()
    return content
end

describe("indexparser", function()
    local result

    before_each(function()
        result = indexparser.parse(fixture("index.json"))
    end)

    it("extracts the current user with a string id", function()
        assert.equals("555", result.user.userid)
        assert.equals("FixtureUser", result.user.username)
        assert.equals("member", result.user.role)
    end)

    it("walks top-level forums and their subforums", function()
        assert.equals(2, #result.forums)
        assert.equals("1", result.forums[1].id)
        assert.is_true(result.forums[1].has_threads)
    end)

    it("decodes entities in titles", function()
        assert.equals("Fixtures & Test Data", result.forums[2].title)
    end)

    it("flattens the tree with depths for menu rendering", function()
        assert.equals(3, #result.flat)
        assert.equals("General Discussion", result.flat[1].title)
        assert.equals(0, result.flat[1].depth)
        assert.equals("Fixture Front Page Discussion", result.flat[2].title)
        assert.equals(1, result.flat[2].depth)
        assert.equals("26", result.flat[2].id)
    end)

    it("tolerates an absent user section", function()
        local anonymous = indexparser.parse('{"forums": [], "stats": {}}')
        assert.is_nil(anonymous.user)
        assert.equals(0, #anonymous.flat)
    end)

    it("rejects malformed JSON loudly", function()
        assert.has_error(function() indexparser.parse('{"forums": [') end)
    end)

    it("accepts the login response shape", function()
        local login = indexparser.parse(fixture("login_success.json"))
        assert.equals("FixtureUser", login.user.username)
    end)
end)
