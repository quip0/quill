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
