--[[
Site constants. The login and page-fetch behavior these feed is specified in
spec.md; change both together.
--]]

local config = {
    base_url = "https://forums.somethingawful.com",
    perpage = 40,
    version = "0.4.0",

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
}

function config.user_agent()
    return config.user_agent_fmt:format(config.version)
end

return config
