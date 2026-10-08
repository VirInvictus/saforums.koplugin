--[[
The in-app thread view: a full-screen scrollable HTML widget, the live
reading surface (spec: Rendering). Modeled on the webbrowser plugin's
markdown viewer, which is the proven full-screen ScrollHtmlWidget shape
on this KOReader generation.

No ReaderUI, no files, no history entries, no sidecars: closing saves the
scroll ratio through on_close and that is the whole lifecycle.
--]]

local Blitbuffer = require("blitbuffer")
local Device = require("device")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local TitleBar = require("ui/widget/titlebar")
local ScrollHtmlWidget = require("ui/widget/scrollhtmlwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local FrameContainer = require("ui/widget/container/framecontainer")
local _ = require("gettext")

local threadhtml = require("saforums.threadhtml")

local Screen = Device.screen

local ThreadView = InputContainer:extend{
    title = "",
    html_body = nil,
    saved_ratio = nil,
    on_close = nil, -- receives the final scroll ratio (0..1)
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

    self.scroll_widget = ScrollHtmlWidget:new{
        html_body = self.html_body,
        css = threadhtml.css,
        width = screen_w,
        height = screen_h - titlebar:getHeight(),
        dialog = self,
        html_link_tapped_callback = function(link)
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
