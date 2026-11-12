-------------------------------------------------------------------------------
--  World map size: a slider in the options changes the size of the windowed
--  map frame itself (not its scale), so the map gets bigger or smaller while
--  the title, coordinates, buttons and pins keep their size. The map keeps
--  its shape. 100% is Blizzard's size. Made for Leatrix Maps' simple map
--  frame, whose title bar, border and coordinates footer are anchored to the
--  map and follow it; works without it too.
--
--  Only the windowed map: the maximised map is left to Blizzard. Blizzard
--  sizes the map frame itself (opening, quest log, minimise), so the size is
--  put back after each of those. Never changed in combat. At 100% nothing is
--  changed at all (so other addons that size the map are left alone).
--  Same approach as OpenMap's window resize (SetSize + canvas refit).
-------------------------------------------------------------------------------
local _, ns = ...

local InCombatLockdown = InCombatLockdown

local MIN_WIDTH     = 300 -- smallest map area width, map frame units
local DEFAULT_RATIO = 1.5 -- map art shape, used if the default size can't be read

local module = ns.RegisterModule({
    key = "mapResize",
    name = "World Map",
    defaults = {
        mapResizeSize = 100, -- % of Blizzard's windowed map size
    },
    options = {
        { type = "slider", key = "mapResizeSize", label = "Windowed map size",
          tooltip = "Size of the windowed world map, in % of Blizzard's size. Unlike a scale, the map's text and icons "
              .. "keep their size. The map keeps its shape and never gets bigger than the screen. 100% leaves the map "
              .. "alone (use it if another addon, OpenMap e.g., already sizes the map).",
          min = 50, max = 200, step = 5, format = function(v) return v .. "%" end },
    },
})

local installed = false
local map, sc
local defaultW, ratio  -- Blizzard's windowed map area width and its width / height
local applying = false -- our own SetSize is running (the SetSize hooks ignore it)
local pendingAfterCombat = false
local resized = false  -- the map frame has a size of ours (to undo at 100%)

local function Maximized()
    return map.IsMaximized and map:IsMaximized()
end

local function IsUsable(v)
    return type(v) == "number" and not ns.IsSecret(v) and v > 0
end

-- Blizzard's map area size, read once while the windowed map still has it.
local function CaptureDefault()
    if defaultW or Maximized() then return end
    local w, h = sc:GetWidth(), sc:GetHeight()
    if not IsUsable(w) or not IsUsable(h) then return end
    defaultW, ratio = w, w / h
end

-- Settings from the corner grip version (a width in map units) become a %.
local function Migrate()
    local db = ns.db
    if db.mapResizeWidth == nil and db.mapResizeEnabled == nil then return end
    local old = db.mapResizeWidth
    if type(old) == "number" and old > 0 and db.mapResizeEnabled ~= false then
        db.mapResizeSize = math.max(50, math.min(200, math.floor(old / defaultW * 20 + 0.5) * 5))
    end
    db.mapResizeWidth, db.mapResizeEnabled = nil, nil
end

-- Map frame space around the map area (title, border, quest log), measured
-- live so it follows whatever Blizzard and other addons put there.
local function Chrome()
    local fw, fh, w, h = map:GetWidth(), map:GetHeight(), sc:GetWidth(), sc:GetHeight()
    if not (IsUsable(fw) and IsUsable(fh) and IsUsable(w) and IsUsable(h)) then return end
    return fw - w, fh - h
end

local function ClampWidth(w, chromeW, chromeH)
    local r = ratio or DEFAULT_RATIO
    local scale, uiScale = map:GetEffectiveScale(), UIParent:GetEffectiveScale()
    local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
    if IsUsable(scale) and IsUsable(uiScale) and IsUsable(screenW) and IsUsable(screenH) then
        screenW, screenH = screenW * uiScale / scale, screenH * uiScale / scale
        w = math.min(w, screenW - chromeW, (screenH - chromeH) * r)
    end
    return math.max(MIN_WIDTH, w)
end

-- Puts the map at the size from the settings. Returns true if it changed.
local function Apply()
    if applying or not installed or Maximized() then return end
    if InCombatLockdown() then pendingAfterCombat = true; return end
    CaptureDefault()
    if not defaultW then return end
    Migrate()
    local size = tonumber(ns.db.mapResizeSize) or 100
    if size == 100 and not resized then return end
    local chromeW, chromeH = Chrome()
    if not chromeW then return end
    local w = ClampWidth(defaultW * size / 100, chromeW, chromeH)
    local h = w / (ratio or DEFAULT_RATIO)
    resized = (size ~= 100)
    if math.abs(sc:GetWidth() - w) < 0.5 and math.abs(sc:GetHeight() - h) < 0.5 then return end
    applying = true
    map:SetSize(w + chromeW, h + chromeH)
    applying = false
    if sc.OnCanvasSizeChanged then sc:OnCanvasSizeChanged() end
    -- The refit resets the zoom (WorldMap.lua zooms back in on the player).
    if ns.OnWorldMapResized then ns.SafeCall(ns.OnWorldMapResized) end
    return true
end

function module.Refresh()
    Apply()
end
module.OnLoad = module.Refresh

-------------------------------------------------------------------------------
--  Install (Blizzard_WorldMap may be load-on-demand)
-------------------------------------------------------------------------------
local function Install()
    if installed then return end
    map = WorldMapFrame
    sc = map and map.ScrollContainer
    if not sc then return end
    installed = true

    CaptureDefault()

    local function OnLayout()
        if map:IsShown() then Apply() end
    end

    -- Blizzard sizes the map frame when it opens, the quest log is toggled
    -- and the map is minimised: put the size back after each.
    map:HookScript("OnShow", OnLayout)
    for _, method in ipairs({ "SetSize", "SetWidth", "SetHeight" }) do
        hooksecurefunc(map, method, function()
            if not applying then OnLayout() end
        end)
    end
    if map.SynchronizeDisplayState then hooksecurefunc(map, "SynchronizeDisplayState", OnLayout) end

    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    events:RegisterEvent("UI_SCALE_CHANGED")
    events:RegisterEvent("DISPLAY_SIZE_CHANGED")
    events:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then
            if not pendingAfterCombat then return end
            pendingAfterCombat = false
        end
        OnLayout()
    end)

    module.Refresh()
end

if C_AddOns.IsAddOnLoaded("Blizzard_WorldMap") then
    Install()
else
    local loader = CreateFrame("Frame")
    loader:RegisterEvent("ADDON_LOADED")
    loader:SetScript("OnEvent", function(self, _, addonName)
        if addonName == "Blizzard_WorldMap" then
            self:UnregisterEvent("ADDON_LOADED")
            Install()
        end
    end)
end
