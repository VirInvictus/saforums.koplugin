--[[
Parser for showthread.php pages.

Structure contract: spec.md "HTML structure contract", thread page section.
Post bodies are kept as raw inner HTML; cleanup and rewriting happen in the
EPUB builder, not here.
--]]

local htmlparser = require("htmlparser")
local htmltext = require("saforums.htmltext")

local postspageparser = {}

local function parse_post(table_node)
    local post = { seen = false, author_is_op = false }

    post.id = table_node.id and table_node.id:match("post(%d+)$") or nil
    post.index = tonumber(table_node.attributes["data-idx"])

    for _, row in ipairs(table_node:select("tr")) do
        if htmltext.has_class(row, "seen1") or htmltext.has_class(row, "seen2") then
            post.seen = true
            break
        end
    end

    local author = table_node:select("dt.author")[1]
    post.author_name = htmltext.text(author)
    post.author_is_op = htmltext.has_class(author, "op")

    -- Custom title: raw HTML (avatars commonly live inside it) plus clean
    -- text for display.
    local title_cell = table_node:select("dd.title")[1]
    post.custom_title_html = htmltext.content(title_cell)
    post.custom_title = htmltext.text(title_cell)

    -- Avatar: the first image in the userinfo sidebar, wherever the poster
    -- kept it (dedicated slot, custom title, or a wrapping link).
    local avatar_img = table_node:select("td.userinfo img")[1]
    post.avatar_src = avatar_img and avatar_img.attributes.src or nil

    local regdate = table_node:select("dd.registered")[1]
    post.regdate = htmltext.text(regdate)

    local profile_link = table_node:select('ul.profilelinks a[href*="userid"]')[1]
    post.author_id = profile_link and htmltext.query_param(profile_link.attributes.href, "userid") or nil

    post.body_html = htmltext.content(table_node:select("td.postbody")[1])

    -- The postdate cell leads with a "#<index>" permalink; the date follows
    -- it.
    post.date_raw = htmltext.text(table_node:select("td.postdate")[1])
    if post.date_raw then
        -- "#5161" permalink prefix, then any separator junk the cell
        -- carries (undefined cp1252 bytes arrive as U+FFFD); dates start
        -- with a letter or digit, so strip everything before the first one.
        post.date_raw = (post.date_raw:gsub("^#%d*", ""):gsub("^[^%w]+", ""))
    end

    return post
end

--- Parse a posts page into page identity plus the post list.
function postspageparser.parse(html)
    local root = htmlparser.parse(html, 400000)
    local result = { posts = {}, closed = false }

    local body = root:select("body")[1]
    if body then
        result.thread_id = body.attributes["data-thread"]
        result.forum_id = body.attributes["data-forum"]
    end

    local breadcrumb = root:select("div.breadcrumbs")[1]
    if breadcrumb then
        for _, link in ipairs(breadcrumb:select("a")) do
            local thread_id = htmltext.query_param(link.attributes.href, "threadid")
            if thread_id then
                result.title = htmltext.text(link)
                if not result.thread_id then
                    result.thread_id = thread_id
                end
                break
            end
        end
    end

    for _, reply_link in ipairs(root:select('ul.postbuttons a[href*="newreply"]')) do
        for _, img in ipairs(reply_link:select("img")) do
            if (img.attributes.src or ""):find("closed", 1, true) then
                result.closed = true
            end
        end
    end

    for _, table_node in ipairs(root:select("table.post")) do
        result.posts[#result.posts + 1] = parse_post(table_node)
    end

    local pages = root:select("div.pages")[1]
    if pages then
        local attributes = pages.attributes
        result.pagination = {
            current_page = tonumber(attributes["data-current-page"]),
            total_pages = tonumber(attributes["data-total-pages"]),
            base_url = attributes["data-base-url"],
            per_page = tonumber(attributes["data-per-page"]),
        }
    end

    return result
end

return postspageparser
