--[[
The in-app thread view: posts composed from KOReader's own widgets - no
HTML engine, no files, no history entries (spec: Rendering). The design
is the grayscale Awful posts-view port: post cards, seen tint, avatar
beside the name-and-date block, dense body text, the frog end marker.

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
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconButton = require("ui/widget/iconbutton")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
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

local postblocks = require("saforums.postblocks")

local Screen = Device.screen

local ThreadView = InputContainer:extend{
    title = "",
    posts = nil,     -- parsed posts (postspageparser output)
    avatars = nil,   -- user id -> absolute cache path
    discarded = false,
    page = 1,
    total_pages = 1,
    on_close = nil,       -- called on back
    on_page_action = nil, -- receives "prevpage" or "nextpage"
}

-- Design tokens: the grayscale translation of Awful's posts-view theme.
local TINT_SEEN = Blitbuffer.gray(0.09)
local INK_META = Blitbuffer.gray(0.4)
local RULE = Blitbuffer.gray(0.2)

local BODY_SIZE = Screen:scaleBySize(14)
local SMALL_SIZE = Screen:scaleBySize(11)
local NAME_SIZE = Screen:scaleBySize(16)
local AVATAR_SIZE = Screen:scaleBySize(40)

local function body_face()
    return Font:getFace("cfont", BODY_SIZE)
end

local function small_face()
    return Font:getFace("cfont", SMALL_SIZE)
end

local function name_face()
    return Font:getFace("cfont", NAME_SIZE)
end

local function post_card(post, inner_width, is_first)
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
    -- the ScrollableContainer into horizontal mode (the glitch).
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
        text = (post.author_name or "?") .. (post.author_is_op and "  [OP]" or ""),
        face = name_face(),
        bold = true,
        width = name_width,
    }
    if post.custom_title and post.custom_title ~= "" then
        name_block[#name_block + 1] = TextBoxWidget:new{
            text = post.custom_title,
            face = small_face(),
            fgcolor = INK_META,
            width = name_width,
        }
    end
    if post.date_raw and post.date_raw ~= "" then
        name_block[#name_block + 1] = TextBoxWidget:new{
            text = post.date_raw .. (post.index and ("  - post #" .. post.index) or ""),
            face = small_face(),
            fgcolor = INK_META,
            width = name_width,
        }
    end
    if post.regdate and post.regdate ~= "" then
        name_block[#name_block + 1] = TextBoxWidget:new{
            text = "joined " .. post.regdate,
            face = small_face(),
            fgcolor = INK_META,
            width = name_width,
        }
    end
    header[#header + 1] = VerticalGroup:new(name_block)
    content[#content + 1] = HorizontalGroup:new(header)
    content[#content + 1] = VerticalSpan:new{ width = Screen:scaleBySize(6) }

    for _block_idx, block in ipairs(postblocks.parse(post.body_html)) do
        if block.type == "quote" then
            local quote_parts = {}
            if block.header then
                quote_parts[#quote_parts + 1] = TextWidget:new{
                    text = block.header,
                    face = small_face(),
                    fgcolor = INK_META,
                }
            end
            quote_parts[#quote_parts + 1] = TextBoxWidget:new{
                text = block.text,
                face = body_face(),
                width = inner_width - Screen:scaleBySize(18),
            }
            content[#content + 1] = HorizontalGroup:new{
                LineWidget:new{
                    dimen = Geom:new{ w = Screen:scaleBySize(2), h = Screen:scaleBySize(30) },
                    background = RULE,
                },
                VerticalSpan:new{ width = Screen:scaleBySize(8) },
                VerticalGroup:new(quote_parts),
            }
        elseif block.type == "image" then
            content[#content + 1] = TextWidget:new{
                text = block.label,
                face = small_face(),
                fgcolor = INK_META,
            }
        else
            content[#content + 1] = TextBoxWidget:new{
                text = block.text,
                face = body_face(),
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
        fgcolor = Blitbuffer.gray(0.2),
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
        page_label,
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
    for idx, post in ipairs(self.posts or {}) do
        thread_parts[#thread_parts + 1] = post_card(post, inner_width, idx == 1)
        thread_parts[#thread_parts + 1] = VerticalSpan:new{ width = Screen:scaleBySize(4) }
    end
    if self.page >= self.total_pages then
        thread_parts[#thread_parts + 1] = TextWidget:new{
            text = _("The frog says: GET OUT."),
            face = small_face(),
            fgcolor = INK_META,
        }
    end

    -- dimen needs the real x/y: the container hit-tests gestures against
    -- this rectangle (pos:intersectWith), so an unpositioned Geom makes
    -- every pan/swipe bounce off.
    local content_height = 0
    for _part_idx, part in ipairs(thread_parts) do
        local ok, sz = pcall(function() return part:getSize() end)
        if ok and sz then content_height = content_height + (sz.h or 0) end
    end
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
        VerticalGroup:new(thread_parts),
    }

    local layout = VerticalGroup:new{
        titlebar,
        scrollable,
        CenterContainer:new{
            dimen = Geom:new{ w = screen_w, h = bar_height },
            bar,
        },
    }

    return FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        margin = 0,
        padding = 0,
        layout,
    }
end

-- Progressive avatar refresh: swap in fetched avatars and repaint.
function ThreadView:set_avatars(avatars)
    self.avatars = avatars
    self[1] = self:build()
    UIManager:setDirty(self, "full")
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

    self[1] = self:build()
end

function ThreadView:onPageAction(action)
    if self.on_page_action then
        self.on_page_action(action)
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
