--[[
The in-app thread view: posts composed from KOReader's own widgets - no
HTML engine, no files, no history entries (spec: Rendering). The design
is the grayscale Awful posts-view port: white post cards on a light page,
seen posts tinted, avatar beside the name-and-date block, dense body text,
quotes collapsing past three lines, spoilers as inverted cards, and the
centered frog end marker.

Interaction: taps land on the blocks that offer them (quote expand,
spoiler reveal, image view, page jump); holding a post opens its action
menu (the view hit-tests the hold against the card rects it recorded at
build time). Holds are deliberately ignored by the ScrollableContainer so
they reach this handler; drag-scrolling stays with pan and swipe.

Body text renders through TextBoxWidget, so inline bold comes from the
PTF markers postblocks embeds; italic runs render plain (v1 limitation,
recorded in the spec).
--]]

local Blitbuffer = require("ffi/blitbuffer") -- module lives at the install root on this generation
local Device = require("device")
local logger = require("logger")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconButton = require("ui/widget/iconbutton")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local LineWidget = require("ui/widget/linewidget")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")

local config = require("saforums.config")
local postblocks = require("saforums.postblocks")
local posthtml = require("saforums.posthtml")

local Screen = Device.screen

local ThreadView = InputContainer:extend{
    title = "",
    posts = nil,     -- parsed posts (postspageparser output)
    avatars = nil,   -- user id -> absolute cache path
    thread_id = nil, -- for permalinks and setseen
    forum_id = nil,  -- body[data-forum]; drives per-forum tweaks
    username = nil,  -- logged-in user: mention and quoted-you markers
    discarded = false,
    page = 1,
    total_pages = 1,
    on_close = nil,       -- called on back
    on_page_action = nil, -- receives "prevpage", "nextpage", or ("jump", n)
    on_post_hold = nil,   -- receives the held post (action menu)
    on_image_tap = nil,   -- receives (src, label) for image blocks with a URL
}

-- Design tokens: the grayscale translation of Awful's posts-view theme
-- (page #f4f3f3, rules #ddd, meta ink 30% black, seen tint #e6eff8
-- flattened to its luminance, quote bar #999, quote headers #555).
local BG_PAGE = Blitbuffer.gray(0.045)
local TINT_SEEN = Blitbuffer.gray(0.07)
local INK_META = Blitbuffer.gray(0.3)
local RULE = Blitbuffer.gray(0.13)
local RULE_QUOTE = Blitbuffer.gray(0.4)
local INK_QUOTE_HEADER = Blitbuffer.gray(0.667)

local BODY_SIZE = Screen:scaleBySize(14)
local SMALL_SIZE = Screen:scaleBySize(11)
local NAME_SIZE = Screen:scaleBySize(16)
local AVATAR_SIZE = Screen:scaleBySize(40)
local QUOTE_COLLAPSED_LINES = postblocks.QUOTE_COLLAPSED_LINES

local function body_face()
    return Font:getFace("cfont", BODY_SIZE)
end

local function small_face()
    return Font:getFace("cfont", SMALL_SIZE)
end

local function name_face()
    return Font:getFace("cfont", NAME_SIZE)
end

-- A tappable region around any widget: taps are the one gesture the
-- ScrollableContainer does not claim, so these fire from inside the
-- scrolled content.
local TapArea = InputContainer:extend{
    content = nil,
    callback = nil,
}

function TapArea:init()
    self.ges_events = {
        TapSelectArea = {
            GestureRange:new{
                ges = "tap",
                range = function() return self.dimen end,
            },
        },
    }
    self[1] = self.content
end

function TapArea:onTapSelectArea()
    if self.callback then
        self.callback()
    end
    return true
end

local function meta_label(text, face)
    return TextWidget:new{
        text = text,
        face = face or small_face(),
        fgcolor = INK_META,
    }
end

function ThreadView:quote_is_expanded(post_idx, block_idx)
    local expanded = self._expanded_quotes
    return expanded and expanded[post_idx .. ":" .. block_idx] or false
end

function ThreadView:toggle_quote(post_idx, block_idx)
    self._expanded_quotes = self._expanded_quotes or {}
    local key = post_idx .. ":" .. block_idx
    self._expanded_quotes[key] = not self._expanded_quotes[key] or nil
    self:refresh_preserving_scroll()
end

function ThreadView:spoilers_revealed(post_idx)
    local revealed = self._revealed_spoilers
    return revealed and revealed[post_idx] or false
end

function ThreadView:toggle_spoilers(post_idx)
    self._revealed_spoilers = self._revealed_spoilers or {}
    self._revealed_spoilers[post_idx] = not self._revealed_spoilers[post_idx] or nil
    self:refresh_preserving_scroll()
end

--- Mark every post at or before this index seen and repaint the card list
--- in place (the mark-read-to-here action's local half).
function ThreadView:set_seen_up_to(index)
    for _idx, post in ipairs(self.posts or {}) do
        if post.index and post.index <= index then
            post.seen = true
        end
    end
    self:refresh_preserving_scroll()
end

local function widget_height(widget, fallback)
    local ok, size = pcall(function() return widget:getSize() end)
    if ok and size and size.h then
        return size.h
    end
    return fallback
end

local function quote_block_widget(view, post_idx, block_idx, block, width, bg)
    local parts = {}
    if block.header then
        local header_text = block.header
        if block.mentions_you then
            header_text = header_text .. " " .. _("(you)")
        end
        parts[#parts + 1] = TextBoxWidget:new{
            text = header_text,
            face = small_face(),
            bold = block.mentions_you or nil,
            fgcolor = INK_QUOTE_HEADER,
            bgcolor = bg,
            width = width,
        }
    end

    -- Lay the quote out once: the full widget is the expanded rendering,
    -- and its line list tells us whether it needs collapsing at all.
    local full = TextBoxWidget:new{
        text = block.text,
        face = body_face(),
        bgcolor = bg,
        width = width,
    }
    local collapsed, remaining = postblocks.collapsed_text(full, QUOTE_COLLAPSED_LINES)
    local expanded = view:quote_is_expanded(post_idx, block_idx)
    if collapsed and not expanded then
        parts[#parts + 1] = TextBoxWidget:new{
            text = collapsed,
            face = body_face(),
            bgcolor = bg,
            width = width,
        }
        parts[#parts + 1] = TapArea:new{
            content = meta_label(string.format(_("+%d lines"), remaining)),
            callback = function() view:toggle_quote(post_idx, block_idx) end,
        }
    else
        parts[#parts + 1] = full
        if collapsed then
            parts[#parts + 1] = TapArea:new{
                content = meta_label(_("less")),
                callback = function() view:toggle_quote(post_idx, block_idx) end,
            }
        end
    end

    local group = VerticalGroup:new(parts)
    return HorizontalGroup:new{
        LineWidget:new{
            dimen = Geom:new{ w = Screen:scaleBySize(2), h = widget_height(group, Screen:scaleBySize(30)) },
            background = RULE_QUOTE,
        },
        VerticalSpan:new{ width = Screen:scaleBySize(8) },
        group,
    }
end

local function spoiler_block_widget(view, post_idx, block, width)
    local revealed = view:spoilers_revealed(post_idx)
    local padding = Screen:scaleBySize(6)
    local card = FrameContainer:new{
        background = Blitbuffer.COLOR_BLACK,
        bordersize = 0,
        margin = 0,
        padding = padding,
        -- TextBoxWidget fills its own buffer with bgcolor, so the card's
        -- black must be carried here too, not just the frame's background.
        TextBoxWidget:new{
            text = revealed and block.text or _("spoiler (tap to view)"),
            face = body_face(),
            fgcolor = revealed and Blitbuffer.COLOR_WHITE or Blitbuffer.gray(0.6),
            bgcolor = Blitbuffer.COLOR_BLACK,
            width = width - 2 * padding,
        },
    }
    return TapArea:new{
        content = card,
        callback = function() view:toggle_spoilers(post_idx) end,
    }
end

local function badges_for(post)
    local badges = {}
    if post.author_is_admin then badges[#badges + 1] = "[admin]" end
    if post.author_is_mod then badges[#badges + 1] = "[mod]" end
    if post.author_is_platinum then badges[#badges + 1] = "[PT]" end
    if post.author_is_op then badges[#badges + 1] = "[OP]" end
    if #badges == 0 then return "" end
    return "  " .. table.concat(badges, " ")
end

local function post_card(view, post_idx, post, inner_width, is_first)
    local card = {}

    if not is_first then
        card[#card + 1] = LineWidget:new{
            dimen = Geom:new{ w = inner_width, h = Screen:scaleBySize(1) },
            background = RULE,
        }
    end

    local background = post.seen and TINT_SEEN or Blitbuffer.COLOR_WHITE
    local content = {}

    local header = {}
    -- Every header line is a width-bounded TextBoxWidget: a free-width
    -- TextWidget with a long custom title overflows the screen and throws
    -- the ScrollableContainer into horizontal mode (the glitch). Each also
    -- carries the card background: TextBoxWidget fills its own buffer with
    -- its bgcolor default (white), which would otherwise paint over the
    -- seen tint.
    local name_width = inner_width - (post.avatar_file and (AVATAR_SIZE + Screen:scaleBySize(8)) or 0)
    if post.avatar_file then
        header[#header + 1] = ImageWidget:new{
            file = post.avatar_file,
            width = AVATAR_SIZE,
            height = AVATAR_SIZE,
        }
        header[#header + 1] = HorizontalSpan:new{ width = Screen:scaleBySize(8) }
    end
    local name_block = {}
    name_block[#name_block + 1] = TextBoxWidget:new{
        text = (post.author_name or "?") .. badges_for(post),
        face = name_face(),
        bold = true,
        bgcolor = background,
        width = name_width,
    }
    if post.custom_title and post.custom_title ~= "" then
        name_block[#name_block + 1] = TextBoxWidget:new{
            text = post.custom_title,
            face = small_face(),
            fgcolor = INK_META,
            bgcolor = background,
            width = name_width,
        }
    end
    if post.date_raw and post.date_raw ~= "" then
        name_block[#name_block + 1] = TextBoxWidget:new{
            text = post.date_raw .. (post.index and ("  - post #" .. post.index) or ""),
            face = small_face(),
            fgcolor = INK_META,
            bgcolor = background,
            width = name_width,
        }
    end
    -- Some forums hide the regdate in their tweaks (config's list, from the
    -- reference client's ForumTweaks).
    if post.regdate and post.regdate ~= ""
        and not (view.forum_id and config.hide_regdate_forums[view.forum_id]) then
        name_block[#name_block + 1] = TextBoxWidget:new{
            text = "joined " .. post.regdate,
            face = small_face(),
            fgcolor = INK_META,
            bgcolor = background,
            width = name_width,
        }
    end
    header[#header + 1] = VerticalGroup:new(name_block)
    content[#content + 1] = HorizontalGroup:new(header)
    content[#content + 1] = VerticalSpan:new{ width = Screen:scaleBySize(6) }

    for block_idx, block in ipairs(postblocks.parse(
            posthtml.sanitize_body(post.body_html), { username = view.username })) do
        if block.type == "quote" then
            content[#content + 1] = quote_block_widget(
                view, post_idx, block_idx, block, inner_width - Screen:scaleBySize(18), background)
        elseif block.type == "spoiler" then
            content[#content + 1] = spoiler_block_widget(view, post_idx, block, inner_width)
        elseif block.type == "image" then
            local label = meta_label(block.label)
            if block.src and view.on_image_tap then
                content[#content + 1] = TapArea:new{
                    content = label,
                    callback = function() view.on_image_tap(block.src, block.label) end,
                }
            else
                content[#content + 1] = label
            end
        elseif block.type == "embed" then
            content[#content + 1] = meta_label(block.label)
        else
            content[#content + 1] = TextBoxWidget:new{
                text = block.text,
                face = body_face(),
                bgcolor = background,
                width = inner_width,
            }
        end
        content[#content + 1] = VerticalSpan:new{ width = Screen:scaleBySize(6) }
    end

    card[#card + 1] = FrameContainer:new{
        background = background,
        bordersize = 0,
        margin = 0,
        padding = Screen:scaleBySize(8),
        VerticalGroup:new(content),
    }
    return VerticalGroup:new(card)
end

-- Rebuilds the whole widget tree. Used for progressive avatar refresh;
-- scroll position resets (this runs once per thread, after first paint).
function ThreadView:build()
    local screen_w = Screen:getWidth()
    local screen_h = Screen:getHeight()

    local titlebar = TitleBar:new{
        width = screen_w,
        align = "left",
        with_bottom_line = true,
        title = self.title or "",
        left_icon = "appbar.navigation",
        left_icon_tap_callback = function()
            self:handleBack()
        end,
        close_callback = function()
            self:handleBack()
        end,
        show_parent = self,
    }

    local page_label = TextWidget:new{
        text = string.format("%s %d / %d", _("page"), self.page, self.total_pages),
        face = Font:getFace("cfont", Screen:scaleBySize(12)),
        fgcolor = INK_META,
    }
    -- The label doubles as the jump control (Selectotron parity): a light
    -- outline says it is pressable, the tap opens the page dialog.
    local page_button = TapArea:new{
        content = FrameContainer:new{
            background = Blitbuffer.COLOR_WHITE,
            bordersize = 1,
            margin = 0,
            padding = Screen:scaleBySize(4),
            page_label,
        },
        callback = function() self:show_jump_dialog() end,
    }
    local bar = HorizontalGroup:new{
        IconButton:new{
            icon = "chevron.left",
            icon_width_height = Screen:scaleBySize(30),
            enabled = self.page > 1,
            callback = function() self:onPageAction("prevpage") end,
            show_parent = self,
        },
        HorizontalSpan:new{ width = Screen:scaleBySize(24) },
        page_button,
        HorizontalSpan:new{ width = Screen:scaleBySize(24) },
        IconButton:new{
            icon = "chevron.right",
            icon_width_height = Screen:scaleBySize(30),
            enabled = self.page < self.total_pages,
            callback = function() self:onPageAction("nextpage") end,
            show_parent = self,
        },
    }
    local bar_height = bar:getSize().h

    local inner_width = screen_w - Screen:scaleBySize(16)
    local thread_parts = {}
    local post_rects = {}
    local content_height = 0
    for post_idx, post in ipairs(self.posts or {}) do
        if self.avatars and post.author_id then
            post.avatar_file = self.avatars[post.author_id]
        end
        local card = post_card(self, post_idx, post, inner_width, post_idx == 1)
        local span = VerticalSpan:new{ width = Screen:scaleBySize(4) }
        local card_height = widget_height(card, 0)
        post_rects[#post_rects + 1] = {
            post_idx = post_idx,
            top = content_height,
            bottom = content_height + card_height,
        }
        content_height = content_height + card_height + Screen:scaleBySize(4)
        thread_parts[#thread_parts + 1] = card
        thread_parts[#thread_parts + 1] = span
    end
    if self.page >= self.total_pages then
        -- Centered, spaced, and exactly one frog (spec: Voice).
        thread_parts[#thread_parts + 1] = VerticalSpan:new{ width = Screen:scaleBySize(24) }
        content_height = content_height + Screen:scaleBySize(24)
        thread_parts[#thread_parts + 1] = TextBoxWidget:new{
            text = _("End of the thread"),
            face = small_face(),
            fgcolor = INK_META,
            bgcolor = BG_PAGE,
            width = inner_width,
            alignment = "center",
        }
        thread_parts[#thread_parts + 1] = TextBoxWidget:new{
            text = _("The frog says: GET OUT."),
            face = small_face(),
            fgcolor = INK_META,
            bgcolor = BG_PAGE,
            width = inner_width,
            alignment = "center",
        }
    end

    -- dimen needs the real x/y: the container hit-tests gestures against
    -- this rectangle (pos:intersectWith), so an unpositioned Geom makes
    -- every pan/swipe bounce off.
    local scroll_h = screen_h - titlebar:getHeight() - bar_height
    logger.info(string.format(
        "saforums: view %dx%d, titlebar %d, bar %d, scroll area %dx%d, %d parts, content height %d",
        screen_w, screen_h, titlebar:getHeight(), bar_height,
        screen_w, scroll_h, #thread_parts, content_height))

    local scrollable = ScrollableContainer:new{
        dimen = Geom:new{
            x = 0,
            y = titlebar:getHeight(),
            w = screen_w,
            h = scroll_h,
        },
        scroll_bar_position = "right",
        show_parent = self,
        -- Holds belong to the post action menu, not drag-scrolling; pan
        -- and swipe keep the scroll.
        ignore_events = { "hold", "hold_pan", "hold_release" },
        VerticalGroup:new(thread_parts),
    }
    -- UIManager routes inner subwidget repaints through the cropping widget
    -- (scrollablecontainer.lua header comment, lines 4-11); without this,
    -- button flashes and InfoMessage dismissals leak outside the scroll area.
    self.cropping_widget = scrollable

    local layout = VerticalGroup:new{
        titlebar,
        scrollable,
        CenterContainer:new{
            dimen = Geom:new{ w = screen_w, h = bar_height },
            bar,
        },
    }

    self._scrollable = scrollable
    self._post_rects = post_rects
    self._content_height = content_height
    self._scroll_h = scroll_h

    return FrameContainer:new{
        background = BG_PAGE,
        bordersize = 0,
        margin = 0,
        padding = 0,
        layout,
    }
end

-- Rebuild with the widgets' state toggled (spoilers, quote collapse, seen
-- tint) while keeping the reader's place: carry the old scroll offset onto
-- the new container, clamped to the new content height.
function ThreadView:refresh_preserving_scroll()
    local offset = nil
    if self._scrollable and self._scrollable.getScrolledOffset then
        offset = self._scrollable:getScrolledOffset()
    end
    self[1] = self:build()
    if offset and self._scrollable and self._scrollable.setScrolledOffset then
        local max_offset = math.max(0, (self._content_height or 0) - (self._scroll_h or 0))
        offset.y = math.min(offset.y or 0, max_offset)
        self._scrollable:setScrolledOffset(offset)
    end
    UIManager:setDirty(self, "full")
end

-- Progressive avatar refresh: swap in fetched avatars and repaint.
function ThreadView:set_avatars(avatars)
    self.avatars = avatars
    self[1] = self:build()
    UIManager:setDirty(self, "full")
end

function ThreadView:show_jump_dialog()
    local dialog
    dialog = InputDialog:new{
        title = _("Jump to page"),
        input_type = "number",
        input = tostring(self.page or 1),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Jump"),
                    is_enter = true,
                    callback = function()
                        local target = tonumber(dialog:getInputText())
                        UIManager:close(dialog)
                        if target and target >= 1 and target <= (self.total_pages or 1)
                            and target ~= self.page then
                            self:onPageAction("jump", target)
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
end

function ThreadView:init()
    local screen_w = Screen:getWidth()
    local screen_h = Screen:getHeight()

    self.align = "center"
    self.region = Geom:new{ x = 0, y = 0, w = screen_w, h = screen_h }

    if Device:hasKeys() then
        self.key_events = {
            Close = { { Device.input.group.Back } },
        }
        -- Page keys are deliberately NOT claimed: unhandled events fall
        -- through to the ScrollableContainer, which scrolls the thread.
    end
    if Device:isTouchDevice() then
        self.ges_events = {
            Hold = {
                GestureRange:new{
                    ges = "hold",
                    range = Geom:new{ x = 0, y = 0, w = screen_w, h = screen_h },
                },
            },
        }
    end

    self[1] = self:build()
end

-- Hold anywhere on a post opens its action menu: hit-test the position
-- against the card rects recorded at build time, translated from content
-- space by the container's current scroll offset.
function ThreadView:onHold(_, ges)
    if not self.on_post_hold or not self._post_rects then
        return false
    end
    if not ges or not ges.pos or not self._scrollable or not self._scrollable.dimen then
        return false
    end
    local offset = 0
    if self._scrollable.getScrolledOffset then
        offset = self._scrollable:getScrolledOffset().y or 0
    end
    local content_y = ges.pos.y - (self._scrollable.dimen.y or 0) + offset
    for _idx, rect in ipairs(self._post_rects) do
        if content_y >= rect.top and content_y <= rect.bottom then
            local post = self.posts and self.posts[rect.post_idx]
            if post then
                self.on_post_hold(post)
            end
            return true
        end
    end
    return false
end

function ThreadView:onPageAction(action, target)
    if self.on_page_action then
        self.on_page_action(action, target)
    end
end

function ThreadView:handleBack()
    self.discarded = true -- stops any pending scheduled avatar pass
    if self.on_close then
        self.on_close(nil)
    end
    UIManager:close(self)
end

function ThreadView:onClose()
    self:handleBack()
end

return ThreadView
