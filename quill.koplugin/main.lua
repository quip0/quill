--[[
Quill -- a single-page reading dashboard for KOReader.

Scope: Quill owns the home screen only. It deliberately does not touch the
reader view, so Zen UI's in-book chrome keeps working alongside it.
--]]

local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Quill = WidgetContainer:extend{
    name = "quill",
    is_doc_only = false,
}

function Quill:init()
    if self.ui and self.ui.menu and self.ui.menu.registerToMainMenu then
        self.ui.menu:registerToMainMenu(self)
    end
    self:onDispatcherRegisterActions()

    -- Dev aid: QUILL_AUTOSHOW=1 opens the home page on startup, so the
    -- emulator can be smoke-tested without driving the UI by hand.
    if os.getenv("QUILL_AUTOSHOW") and not rawget(_G, "__quill_autoshown") then
        rawset(_G, "__quill_autoshown", true)
        UIManager:scheduleIn(1, function() self:showHome() end)
        -- QUILL_SHOT=<path> also dumps the rendered page to a PNG.
        local shot = os.getenv("QUILL_SHOT")
        if shot then
            UIManager:scheduleIn(3, function()
                require("device").screen:shot(shot)
            end)
        end
    end
end

function Quill:onDispatcherRegisterActions()
    local ok, Dispatcher = pcall(require, "dispatcher")
    if not ok then return end
    Dispatcher:registerAction("quill_home", {
        category = "none",
        event = "QuillShowHome",
        title = _("Quill home"),
        general = true,
    })
end

function Quill:addToMainMenu(menu_items)
    menu_items.quill = {
        text = _("Quill home"),
        sorting_hint = "tools",
        callback = function() self:showHome() end,
    }
end

function Quill:showHome()
    local HomePage = require("widgets/home_page")
    UIManager:show(HomePage:new{})
end

function Quill:onQuillShowHome()
    self:showHome()
    return true
end

return Quill
