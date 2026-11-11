-------------------------------------------------------------------------------
--  Zygor world map button: hides the round Zygor button (and its POI menu)
--  that Zygor Guides puts on the world map border (frame "ZygorWorldMapMenu",
--  created by Zygor's MapCoords:SetupMapButtons at startup).
--
--  The frame is created some time after login, so it's looked up lazily every
--  time the world map opens. Its OnShow is hooked once so it stays hidden even
--  if Zygor shows it again. Zygor's code and settings are not touched; turning
--  the option off shows the button again.
-------------------------------------------------------------------------------
local _, ns = ...

local FRAME_NAME = "ZygorWorldMapMenu"

local module = ns.RegisterModule({
    key = "zygorMapButton",
    name = "Zygor Guides",
    defaults = {
        zygorHideMapButton = true,
    },
    options = {
        { type = "checkbox", key = "zygorHideMapButton", label = "Hide Zygor world map button",
          tooltip = "Hides the Zygor button (and its points-of-interest menu) on the world map border. "
              .. "Only does something when Zygor Guides is loaded." },
    },
})

local hooked = false

local function Apply()
    local frame = _G[FRAME_NAME]
    if not frame then return end
    if not hooked then
        hooked = true
        frame:HookScript("OnShow", function(self)
            if ns.db.zygorHideMapButton then self:Hide() end
        end)
    end
    frame:SetShown(not ns.db.zygorHideMapButton)
end

module.Refresh = Apply

local mapHooked = false
local function HookMap()
    if mapHooked or not WorldMapFrame then return end
    mapHooked = true
    WorldMapFrame:HookScript("OnShow", Apply)
end

module.OnLoad = function()
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function(self, event, addonName)
        if event == "ADDON_LOADED" and addonName ~= "Blizzard_WorldMap" then return end
        HookMap()
        Apply()
        if mapHooked and hooked then
            self:UnregisterAllEvents()
        end
    end)
end
