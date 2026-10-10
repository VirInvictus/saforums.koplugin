--[[
Parser for forumdisplay.php and bookmarkthreads.php pages.

Structure contract: spec.md "HTML structure contract", thread list section.
When the live site drifts, update the fixture and this parser in the same
commit. Selectors use only the subset the vendored htmlparser supports;
fixtures carry synthetic text with the real element shape.
--]]

local htmlparser = require("htmlparser")
local htmltext = require("saforums.htmltext")

local threadlistparser = {}

local function parse_row(row)
    local thread = { announcement = false }

    thread.id = row.id and row.id:match("%d+") or nil

    local title_cell = row:select("td.title")[1]
    local title_link = title_cell and title_cell:select("a.thread_title")[1]
    local announcement_link = title_cell and title_cell:select("a.announcement")[1]
    if not title_link and announcement_link then
        thread.announcement = true
        thread.title = htmltext.text(announcement_link)
    else
        thread.title = htmltext.text(title_link)
    end
    thread.sticky = htmltext.has_class(title_cell, "title_sticky")

    local author_link = row:select("td.author a")[1]
    thread.author_name = htmltext.text(author_link)
    thread.author_id = author_link and htmltext.query_param(author_link.attributes.href, "userid") or nil

    local lastseen = row:select("div.lastseen")[1]
    if lastseen then
        local count = lastseen:select("a.count b")[1]
        thread.unread_count = count and tonumber(htmltext.text(count)) or nil
        thread.is_read = #lastseen:select("a.x") > 0
    else
        -- No lastseen cell at all: the poster has never opened it.
        thread.unread_count = nil
        thread.is_read = false
    end

    local replies_cell = row:select("td.replies")[1]
    local replies_text = htmltext.text(replies_cell)
    thread.replies = replies_text and tonumber((replies_text:gsub(",", ""))) or nil

    local lastpost = row:select("td.lastpost")[1]
    if lastpost then
        thread.last_post_author = htmltext.text(lastpost:select("a.author")[1])
        thread.last_post_date = htmltext.text(lastpost:select("div.date")[1])
    end

    -- Rating: the img's title reads "N votes, <m.mm> average" in some word
    -- order; the numbers parse out regardless.
    local rating_img = row:select("td.rating img")[1]
    if rating_img then
        local title = htmltext.decode_entities(rating_img.attributes.title or "")
        thread.rating_votes = tonumber(((title:match("(%d[%d,]*)%s*votes") or ""):gsub(",", "")))
        thread.rating_average = tonumber(title:match("(%d+%.%d+)"))
    end

    thread.star = tonumber(htmltext.class_match(row:select("td.star")[1], "^bm(%d)$"))

    local icon_img = row:select("td.icon img")[1]
    if icon_img then
        thread.icon_src = icon_img.attributes.src
        local icon_link = row:select("td.icon a")[1]
        thread.icon_id = icon_link and htmltext.query_param(icon_link.attributes.href, "posticon") or nil
    end

    thread.closed = htmltext.has_class(row, "closed")

    return thread
end

--- Parse a thread list page into { threads, announcements, thread_tags,
--- pagination, forum_id, can_post }. Announcement rows land separately from
--- threads (spec: HTML structure contract). Unread counts include the
--- original post, per the site's own convention; replies do not.
function threadlistparser.parse(html)
    local root = htmlparser.parse(html, 200000)
    local result = { threads = {}, announcements = {} }

    for _, row in ipairs(root:select("tr.thread")) do
        local parsed = parse_row(row)
        if parsed.announcement then
            result.announcements[#result.announcements + 1] = parsed
        else
            result.threads[#result.threads + 1] = parsed
        end
    end

    local tags_block = root:select("div.thread_tags")[1]
    if tags_block then
        result.thread_tags = {}
        for _, link in ipairs(tags_block:select("a[href*='posticon']")) do
            local name = htmltext.text(link)
            local img = link:select("img")[1]
            if (not name or name == "") and img then
                name = htmltext.decode_entities(img.attributes.alt or "")
            end
            result.thread_tags[#result.thread_tags + 1] = {
                id = htmltext.query_param(link.attributes.href, "posticon"),
                name = name,
            }
        end
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

    local body = root:select("body")[1]
    result.forum_id = body and body.attributes["data-forum"] or nil

    result.can_post = #root:select('ul.postbuttons a[href*="newthread"]') > 0

    return result
end

return threadlistparser
