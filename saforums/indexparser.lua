--[[
Parser for the site's JSON side-channel: index.php?json=1 and the login
response, which share the same document shape (spec: endpoints table).

The site is loose about types (ids arrive as numbers or strings, booleans as
1/0), so ids are normalized to strings on the way through.
--]]

local json = require("saforums.json")
local htmltext = require("saforums.htmltext")

local indexparser = {}

local function normalize_id(value)
    if value == nil then return nil end
    return tostring(value)
end

local function collect(forum, depth, out)
    out[#out + 1] = {
        id = normalize_id(forum.id),
        title = htmltext.trim(htmltext.decode_entities(forum.title or "")),
        title_short = forum.title_short and htmltext.trim(htmltext.decode_entities(tostring(forum.title_short))) or nil,
        has_threads = forum.has_threads == 1 or forum.has_threads == true,
        depth = depth,
    }
    for _, sub in ipairs(forum.sub_forums or {}) do
        collect(sub, depth + 1, out)
    end
end

--- Parse an index/login JSON document into { user, forums, flat } where
--- flat is the depth-annotated forum list a menu renders directly.
function indexparser.parse(json_text)
    local document = type(json_text) == "string" and json.decode(json_text) or json_text
    local result = { forums = {}, flat = {} }

    local user = document.user
    if user then
        result.user = {
            userid = normalize_id(user.userid),
            username = user.username and tostring(user.username) or nil,
            role = user.role,
        }
    end

    for _, forum in ipairs(document.forums or {}) do
        local parsed = { id = normalize_id(forum.id), sub_forums = {} }
        parsed.title = htmltext.trim(htmltext.decode_entities(forum.title or ""))
        parsed.has_threads = forum.has_threads == 1 or forum.has_threads == true
        for _, sub in ipairs(forum.sub_forums or {}) do
            parsed.sub_forums[#parsed.sub_forums + 1] = sub
        end
        result.forums[#result.forums + 1] = parsed
        collect(parsed, 0, result.flat)
    end

    return result
end

return indexparser
