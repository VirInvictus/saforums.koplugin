--[[
Site constants. The login and page-fetch behavior these feed is specified in
spec.md; change both together.
--]]

local config = {
    base_url = "https://forums.somethingawful.com",
    perpage = 40,
    version = "0.5.0",

    -- Cookie names the session hangs on (spec: Semantics > Session).
    session_user_cookie = "bbuserid",
    session_password_cookie = "bbpassword",

    -- Session cookies ride only on this organization's hosts; third-party
    -- image hosts never see them.
    cookie_host_suffix = "somethingawful.com",

    -- Forums whose tweaks hide the registration date (the reference
    -- client's ForumTweaks: FYAD 26, 154, 196, BYOB 268; YOSPOS 219 keeps
    -- its regdate despite the folklore).
    hide_regdate_forums = {
        ["26"] = true,
        ["154"] = true,
        ["196"] = true,
        ["268"] = true,
    },

    -- Honest UA per spec: no browser impersonation.
    user_agent_fmt = "saforums.koplugin/%s (KOReader)",

    -- Politeness ceilings (spec: Semantics > Politeness), seconds.
    request_block_timeout = 10,
    request_total_timeout = 30,

    -- Image fetches (avatars, tap-to-view) get their own, tighter ceilings:
    -- a slow image host must not stall the reading view for long.
    image_block_timeout = 5,
    image_total_timeout = 15,

    -- List cache TTLs (spec: Semantics > Politeness), seconds: forum lists
    -- 15 min, bookmarks 10 min, forums index 6 h, announcement bodies 20 h.
    cache_ttl_forum_list = 15 * 60,
    cache_ttl_bookmarks = 10 * 60,
    cache_ttl_index = 6 * 3600,
    cache_ttl_announcements = 20 * 3600,

    -- Bookmark star letters, keyed by the td.star class number (bm0..bm5;
    -- the mapping is the reference client's: orange, red, yellow, cyan,
    -- green, purple).
    star_letters = {
        [0] = "[O]",
        [1] = "[R]",
        [2] = "[Y]",
        [3] = "[C]",
        [4] = "[G]",
        [5] = "[P]",
    },
}

function config.user_agent()
    return config.user_agent_fmt:format(config.version)
end

return config
