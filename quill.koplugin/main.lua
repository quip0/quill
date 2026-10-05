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

local SETTING_AS_HOME = "quill_as_home_screen"

function Quill:init()
    if self.ui and self.ui.menu and self.ui.menu.registerToMainMenu then
        self.ui.menu:registerToMainMenu(self)
    end
    self:onDispatcherRegisterActions()

    -- Take over the landing screen. init() runs each time a FileManager is
    -- created -- on startup and every time a book is closed -- which is
    -- exactly when a home screen should appear. Skipped in the reader, so
    -- Zen UI's in-book chrome is left alone.
    if self:isHomeScreen() and self.ui and not self.ui.document then
        -- nextTick, not now: the FileManager is still assembling its layout,
        -- and showing a fullscreen widget mid-setup leaves it half-painted.
        UIManager:nextTick(function() self:showHome() end)
    end

    self:setupDevHooks()
end

function Quill:isHomeScreen()
    local gs = rawget(_G, "G_reader_settings")
    if not gs then return false end
    return gs:nilOrTrue(SETTING_AS_HOME)
end

-- Dev aids for emulator smoke tests, both opt-in via the environment:
--   QUILL_AUTOSHOW=1     open the home page on startup
--   QUILL_SHOT=<path>    dump the screen to a PNG
-- They are independent, so QUILL_SHOT alone captures whatever KOReader
-- itself is showing -- useful for checking other plugins' screens.
function Quill:setupDevHooks()
    if rawget(_G, "__quill_dev_hooks_done") then return end
    rawset(_G, "__quill_dev_hooks_done", true)

    if os.getenv("QUILL_AUTOSHOW") then
        UIManager:scheduleIn(1, function() self:showHome() end)
    end

    local shot = os.getenv("QUILL_SHOT")
    if shot then
        local delay = tonumber(os.getenv("QUILL_SHOT_DELAY")) or 3
        UIManager:scheduleIn(delay, function()
            require("device").screen:shot(shot)
        end)
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
        text = _("Quill"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("Open Quill home"),
                keep_menu_open = false,
                callback = function() self:showHome() end,
            },
            {
                text = _("Use as home screen"),
                help_text = _("Show Quill when the file browser opens, instead of landing in the library."),
                checked_func = function() return self:isHomeScreen() end,
                callback = function()
                    G_reader_settings:flipNilOrTrue(SETTING_AS_HOME)
                end,
            },
        },
    }
end

function Quill:showHome()
    -- One FileManager can be torn down and rebuilt while a page is still up
    -- (and the menu entry is always reachable), so guard against stacking.
    -- The showing page is refreshed rather than left alone: whatever prompted
    -- the call is as good a moment as any for it to catch up on the stats.
    if self.home_page and UIManager:isWidgetShown(self.home_page) then
        self.home_page:refreshStats()
        return
    end
    local HomePage = require("widgets/home_page")
    self.home_page = HomePage:new{}
    UIManager:show(self.home_page)
end

function Quill:onQuillShowHome()
    self:showHome()
    return true
end

return Quill
