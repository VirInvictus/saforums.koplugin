--[[
The in-app thread view: a full-screen scrollable HTML widget, the live
reading surface (spec: Rendering). Modeled on the webbrowser plugin's
markdown viewer, which is the proven full-screen ScrollHtmlWidget shape
on this KOReader generation.

No ReaderUI, no files, no history entries, no sidecars: closing saves the
scroll ratio through on_close and that is the whole lifecycle.
--]]

local Blitbuffer = require("ffi/blitbuffer") -- module lives at the install root on this generation
local Device = require("device")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local TitleBar = require("ui/widget/titlebar")
local ScrollHtmlWidget = require("ui/widget/scrollhtmlwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Size = require("ui/size")
local _ = require("gettext")

local ButtonTable = require("ui/widget/buttontable")
local threadhtml = require("saforums.threadhtml")

local Screen = Device.screen

local ThreadView = InputContainer:extend{
    title = "",
    html_body = nil,
    resource_directory = nil, -- base dir for relative image paths (avatars)
    saved_ratio = nil,
    page = 1,
    total_pages = 1,
    on_close = nil, -- receives the final scroll ratio (0..1)
    on_page_action = nil, -- receives "prevpage" or "nextpage"
}

function ThreadView:init()
    local screen_w = Screen:getWidth()
    local screen_h = Screen:getHeight()

    self.align = "center"
    self.region = Geom:new{ x = 0, y = 0, w = screen_w, h = screen_h }

    if Device:hasKeys() then
        self.key_events = {
            Close = { { Device.input.group.Back } },
            ScrollDown = { { "RPgFwd", "LPgFwd" } },
            ScrollUp = { { "RPgBack", "LPgBack" } },
        }
    end

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

    -- Native page selector: the same bottom-bar pattern as the file
    -- manager's list pagination, per Brandon's call (HTML nav removed).
    local page_buttons = {
        {
            text = "\226\171\194\171", -- << newer
            enabled = self.page > 1,
            callback = function()
                self:onPageAction("prevpage")
            end,
        },
        {
            text = self.page .. " / " .. self.total_pages,
            enabled = false,
        },
        {
            text = "\226\171\194\187 older", -- >> older
            enabled = self.page < self.total_pages,
            callback = function()
                self:onPageAction("nextpage")
            end,
        },
    }
    self.button_table = ButtonTable:new{
        width = screen_w - 2 * Size.padding.large,
        buttons = { page_buttons },
        zero_sep = true,
        show_parent = self,
    }
    local buttons_height = self.button_table:getSize().h

    local content_height = screen_h - titlebar:getHeight() - buttons_height
    if content_height < 0 then
        content_height = screen_h
    end

    self.scroll_widget = ScrollHtmlWidget:new{
        html_body = self.html_body,
        css = threadhtml.css,
        html_resource_directory = self.resource_directory,
        -- Dense by request: Awful squishes; the stock default (24) is a
        -- large-print edition by comparison. Becomes a setting in Phase 4.
        default_font_size = Screen:scaleBySize(14),
        width = screen_w,
        height = content_height,
        dialog = self,
        html_link_tapped_callback = function(link)
            if link and link:find("^saforums:") then
                if self.on_page_action then
                    self.on_page_action(link:match("^saforums:(.+)$"))
                end
                return
            end
            -- Links are inert in the lurker view (Phase 6 revisits them).
            UIManager:show(require("ui/widget/infomessage"):new{
                text = _("Links are read-only in this view."),
                timeout = 2,
            })
        end,
    }

    local layout = VerticalGroup:new{
        titlebar,
        self.scroll_widget,
        CenterContainer:new{
            dimen = Geom:new{ w = screen_w, h = buttons_height },
            self.button_table,
        },
    }

    local frame = FrameContainer:new{
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        layout,
    }

    self[1] = frame

    if self.saved_ratio and self.saved_ratio > 0 then
        local ratio = self.saved_ratio
        UIManager:nextTick(function()
            if self.scroll_widget then
                self.scroll_widget:scrollToRatio(ratio)
            end
        end)
    end
end

function ThreadView:onPageAction(action)
    if self.on_page_action then
        self.on_page_action(action)
    end
end

function ThreadView:onScrollDown()
    self.scroll_widget:onScrollDown()
    return true
end

function ThreadView:onScrollUp()
    self.scroll_widget:onScrollUp()
    return true
end

function ThreadView:handleBack()
    local ratio = 0
    if self.scroll_widget and self.scroll_widget.getCurrentRatio then
        ratio = self.scroll_widget:getCurrentRatio() or 0
    end
    if self.on_close then
        self.on_close(ratio)
    end
    UIManager:close(self)
end

function ThreadView:onClose()
    self:handleBack()
end

return ThreadView
