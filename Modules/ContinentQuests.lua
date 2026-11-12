-------------------------------------------------------------------------------
--  Quest icons on continent maps: the continent and Azeroth maps show an icon
--  for every quest in the log from every zone (Blizzard shows only the
--  super-tracked one there; a zone's quests are on that zone's own map). The
--  icons keep their size at any zoom; hovering shows the objectives, clicking
--  super-tracks the quest and opens its zone's map.
--
--  A data provider of our own on the world map, with its own pin template
--  (ContinentQuests.xml). Blizzard's providers and pins are not changed.
--  Idea from OpenMap's "Quests from every zone" (Map/Quests.lua), which does
--  the same for its stitched map.
-------------------------------------------------------------------------------
local _, ns = ...

local TEMPLATE = "ZavahTweaksContinentQuestPinTemplate"
local SAME     = 0.002 -- one quest's icons this close (normalized) are one (a city repeats its zone's)
local EVERY    = 0.5   -- seconds; the quest log changes in bursts

local module = ns.RegisterModule({
    key = "continentQuests",
    name = "World Map",
    defaults = {
        continentQuests = true,
        continentQuestsScale = 100, -- icon size, %
    },
    options = {
        { type = "checkbox", key = "continentQuests", label = "Quest icons on continent maps",
          tooltip = "Shows the quests in your log from every zone on the continent and Azeroth maps (Blizzard only shows "
              .. "the tracked one there). Hover an icon for its objectives; click it to track the quest and open its zone. "
              .. "Hidden with the map's Quest Objectives filter off. Turn it off if another addon (OpenMap, e.g.) already "
              .. "does this." },
        { type = "slider", key = "continentQuestsScale", label = "Continent quest icon size",
          tooltip = "Size of the quest icons on the continent and Azeroth maps, in %.",
          min = 50, max = 200, step = 10, format = function(v) return v .. "%" end },
    },
})

local installed = false
local map, provider

local function Enabled()
    return ns.db.continentQuests
end

-- Atlas if the client has it, the texture otherwise.
local function Look(tex, atlas, file)
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        tex:SetAtlas(atlas)
    else
        tex:SetTexture(file)
        tex:SetTexCoord(0, 1, 0, 1)
    end
end

-------------------------------------------------------------------------------
--  Pin (template in ContinentQuests.xml)
-------------------------------------------------------------------------------
ZavahTweaksContinentQuestPinMixin = CreateFromMixins(MapCanvasPinMixin)
local Pin = ZavahTweaksContinentQuestPinMixin

function Pin:OnLoad()
    self:UseFrameLevelType("PIN_FRAME_LEVEL_ACTIVE_QUEST")
    self:SetScalingLimits(1, 1.0, 1.2)
    Look(self.Badge, "UI-QuestPoi-QuestNumber", "Interface\\GossipFrame\\ActiveQuestIcon")
end

function Pin:OnAcquired(info)
    self.info = info
    -- Same on-screen size at any zoom, times the size setting.
    local s = (tonumber(ns.db.continentQuestsScale) or 100) / 100
    self:SetScalingLimits(1, s, 1.2 * s)
    self:ApplyCurrentScale()
    self:SetPosition(info.x, info.y)
    if info.complete then
        Look(self.Mark, "UI-QuestPoi-QuestBangTurnIn", "Interface\\GossipFrame\\ActiveQuestIcon")
    else
        Look(self.Mark, "Quest-In-Progress-Icon-yellow", "Interface\\GossipFrame\\IncompleteQuestIcon")
    end
end

function Pin:OnReleased()
    MapCanvasPinMixin.OnReleased(self)
    self.info = nil
end

function Pin:OnMouseEnter()
    local info = self.info
    if not info then return end
    local id = info.questID
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(C_QuestLog.GetTitleForQuestID(id) or "?", 1, 0.82, 0)
    local index = C_QuestLog.GetLogIndexForQuestID(id)
    if info.complete then
        GameTooltip:AddLine(QUEST_WATCH_QUEST_READY or "Ready for turn-in", 0.5, 0.95, 0.4)
    elseif index and GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
        for i = 1, GetNumQuestLeaderBoards(index) or 0 do
            local text, _, finished = GetQuestLogLeaderBoard(i, index)
            if text and not finished then GameTooltip:AddLine((QUEST_DASH or "- ") .. text, 1, 1, 1, true) end
        end
    end
    GameTooltip:AddLine("Click: track this quest and open its zone", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

function Pin:OnMouseLeave()
    if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
end

function Pin:OnMouseClickAction(button)
    local info = self.info
    if button ~= "LeftButton" or not info then return end
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
        C_SuperTrack.SetSuperTrackedQuestID(info.questID)
    end
    -- Switching the map ourselves: never in combat, and with the pin guards on
    -- (WorldMap.lua) so the map's pins don't get blocked in a later combat.
    if not InCombatLockdown() and info.zoneID then
        if ns.InstallPinGuards then ns.InstallPinGuards() end
        self:GetMap():SetMapID(info.zoneID)
    end
end

-------------------------------------------------------------------------------
--  Data provider
-------------------------------------------------------------------------------
provider = CreateFromMixins(MapCanvasDataProviderMixin)

local zonesCache = {}
local function Zones(mapID)
    local zones = zonesCache[mapID]
    if not zones then
        zones = {}
        for _, child in ipairs(C_Map.GetMapChildrenInfo(mapID, Enum.UIMapType.Zone, true) or {}) do
            zones[#zones + 1] = child.mapID
        end
        zonesCache[mapID] = zones
    end
    return zones
end

-- A zone map position on map mapID, or nil if it's not on it.
local function ToMap(zoneID, x, y, mapID)
    local instance, worldPos = C_Map.GetWorldPosFromMapPos(zoneID, CreateVector2D(x, y))
    if not instance or not worldPos then return end
    local _, pos = C_Map.GetMapPosFromWorldPos(instance, worldPos, mapID)
    if not pos then return end
    local mx, my = pos:GetXY()
    if not mx or mx < 0 or mx > 1 or my < 0 or my > 1 then return end
    return mx, my
end

function provider:RemoveAllData()
    self:GetMap():RemoveAllPinsByTemplate(TEMPLATE)
end

function provider:RefreshAllData()
    self:RemoveAllData()
    if not Enabled() or not GetCVarBool("questPOI") then return end
    local m = self:GetMap()
    local mapID = m:GetMapID()
    local mapInfo = mapID and C_Map.GetMapInfo(mapID)
    if not mapInfo then return end
    local continent = mapInfo.mapType == Enum.UIMapType.Continent
    if not continent and mapInfo.mapType ~= Enum.UIMapType.World then return end

    -- Blizzard already shows the super-tracked quest on a continent.
    local tracked = continent and C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID
        and C_SuperTrack.GetSuperTrackedQuestID()
    local seen = {}
    for _, zoneID in ipairs(Zones(mapID)) do
        for _, q in ipairs(C_QuestLog.GetQuestsOnMap(zoneID) or {}) do
            local id = q.questID
            if id and q.x and q.y and not q.isMapIndicatorQuest and id ~= tracked
                and (not HaveQuestData or HaveQuestData(id)) then
                local x, y = ToMap(zoneID, q.x, q.y, mapID)
                if x then
                    local key = id .. ":" .. math.floor(x / SAME) .. ":" .. math.floor(y / SAME)
                    if not seen[key] then
                        seen[key] = true
                        m:AcquirePin(TEMPLATE, {
                            questID = id, zoneID = zoneID, x = x, y = y,
                            complete = C_QuestLog.IsComplete(id) or false,
                        })
                    end
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Refreshing (one refresh per burst of quest log updates)
-------------------------------------------------------------------------------
local pending = false
local function RefreshNow()
    pending = false
    if installed and map:IsShown() then provider:RefreshAllData() end
end
local function RefreshSoon()
    if pending or not installed or not map:IsShown() then return end
    pending = true
    C_Timer.After(EVERY, RefreshNow)
end

function module.Refresh()
    if installed then provider:RefreshAllData() end
end

-------------------------------------------------------------------------------
--  Install (Blizzard_WorldMap may be load-on-demand)
-------------------------------------------------------------------------------
local function Install()
    if installed then return end
    map = WorldMapFrame
    if not map or not map.AddDataProvider or not C_QuestLog.GetQuestsOnMap then return end
    installed = true
    map:AddDataProvider(provider)

    local events = CreateFrame("Frame")
    for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_POI_UPDATE", "QUEST_WATCH_LIST_CHANGED",
                         "SUPER_TRACKING_CHANGED", "CVAR_UPDATE" }) do
        pcall(events.RegisterEvent, events, e)
    end
    events:SetScript("OnEvent", function(_, event, cvar)
        if event == "CVAR_UPDATE" and cvar ~= "questPOI" then return end
        RefreshSoon()
    end)
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
