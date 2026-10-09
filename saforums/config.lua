--[[
Site constants. The login and page-fetch behavior these feed is specified in
spec.md; change both together.
--]]

local config = {
    base_url = "https://forums.somethingawful.com",
    perpage = 40,
    version = "0.3.0",

    -- Cookie names the session hangs on (spec: Semantics > Session).
    session_user_cookie = "bbuserid",
    session_password_cookie = "bbpassword",

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
