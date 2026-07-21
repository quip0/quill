--[[
The day's quote, borrowed from Zen UI.

Quill ships no quote list of its own. It reads whatever Zen UI is already
configured to show -- the user's settings/Zen UI/quotes.lua when that file has
entries, Zen's bundled list otherwise -- and picks with Zen's own day index, so
both home screens quote the same line on the same day.
--]]

local M = {}

-- Zen UI lives in its own plugin directory. Every .koplugin dir is on
-- package.path, so these resolve when Zen UI is installed and fail quietly
-- when it is not -- Quill stays standalone either way.
local function zen(module)
    local ok, mod = pcall(require, module)
    if ok and mod then return mod end
    return nil
end

local function dayIndex()
    local now = os.date("*t")
    return (now.year * 366) + now.yday
end

--- Returns { text = ..., author = ... }, or nil when there is nothing to show.
function M.getDaily()
    local HomeQuotes = zen("modules/filebrowser/patches/home/home_quotes")
    if not HomeQuotes or not HomeQuotes.getQuotes then return nil end

    local ok, quotes = pcall(HomeQuotes.getQuotes)
    if not ok or type(quotes) ~= "table" or #quotes == 0 then return nil end

    local today = dayIndex()
    local idx = (today % #quotes) + 1
    local show_author = true

    -- Zen stamps the day whenever the user taps through to a different quote.
    -- Honour that pick (and the author toggle) so the two screens agree.
    local PresetStore = zen("config/preset_store")
    if PresetStore and PresetStore.getSettings then
        local ok_cfg, cfg = pcall(PresetStore.getSettings, "home")
        local qcfg = ok_cfg and type(cfg) == "table" and cfg.quotes
        if type(qcfg) == "table" then
            show_author = qcfg.show_author ~= false
            if qcfg.day_seed == today and type(qcfg.manual_index) == "number" then
                idx = ((qcfg.manual_index - 1) % #quotes) + 1
            end
        end
    end

    local quote = quotes[idx]
    if type(quote) ~= "table" or type(quote.text) ~= "string" or quote.text == "" then
        return nil
    end

    return {
        text = quote.text,
        author = show_author and type(quote.author) == "string" and quote.author or "",
    }
end

return M
