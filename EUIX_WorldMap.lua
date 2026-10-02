if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  World map: every open shows the player's zone fully zoomed in and centered
--  on the player, and keeps following the player while open. Dragging the map
--  stops following until the next open (or a double-click on the map). With
--  the map open, entering a new zone switches to its map. One on/off setting.
--
--  Based on Persistent World Map by LudiusMaximus
--  (MIT License, Copyright (c) 2020-2026 LudiusMaximus).
--  The original's taint workaround layer (custom pin tooltips, in-instance
--  OnShow copy, combat frame juggling) is not ported. Instead the map is never
--  switched in combat or inside instances, and once we have changed the map
--  ourselves the pins' protected calls are skipped in combat (refreshed when
--  combat ends), which is the part of that layer that prevents
--  ADDON_ACTION_BLOCKED.
-------------------------------------------------------------------------------
local _, ns = ...

local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local IsInInstance = IsInInstance

local PAN_TIME     = 0.3  -- smooth pan back to the player on double-click, seconds
local DOUBLE_CLICK = 0.25 -- max seconds between the clicks of a double-click

local installed = false
local map, sc -- WorldMapFrame, WorldMapFrame.ScrollContainer

-- Keep the player centered; set on every open, cleared by dragging the map.
local following = false

local function Enabled()
    return ns.db.worldMapEnabled
end

-- Switching the map ourselves (SetMapID) is left to Blizzard in combat and
-- inside instances.
local function CanReposition()
    return not InCombatLockdown() and not IsInInstance()
end

local function PlayerMapID()
    return MapUtil and MapUtil.GetDisplayableMapForPlayer and MapUtil.GetDisplayableMapForPlayer()
end

-------------------------------------------------------------------------------
--  Pin guards: after we set the map, Blizzard's pin setup runs under our
--  taint and its protected SetPassThroughButtons / SetPropagateMouseClicks
--  calls are blocked in combat. Shadow them per pin to skip in combat and
--  refresh the map once combat ends. Installed lazily, only once we've
--  actually changed the map, so an unused feature adds no taint.
-------------------------------------------------------------------------------
local pinGuardsInstalled = false
local refreshAfterCombat = false

local function PatchPin(pin)
    if not pin or pin.euixPinGuarded then return end
    pin.euixPinGuarded = true
    local origPassThrough = pin.SetPassThroughButtons
    if origPassThrough then
        pin.SetPassThroughButtons = function(self, ...)
            if InCombatLockdown() then refreshAfterCombat = true; return end
            return origPassThrough(self, ...)
        end
    end
    local origPropagate = pin.SetPropagateMouseClicks
    if origPropagate then
        pin.SetPropagateMouseClicks = function(self, ...)
            if InCombatLockdown() then refreshAfterCombat = true; return end
            return origPropagate(self, ...)
        end
    end
end

local function WrapPool(pool)
    if type(pool) ~= "table" or pool.euixPinGuarded or not pool.Acquire then return end
    pool.euixPinGuarded = true
    local origAcquire = pool.Acquire
    pool.Acquire = function(self, ...)
        local pin, isNew = origAcquire(self, ...)
        if pin then PatchPin(pin) end
        return pin, isNew
    end
    if pool.EnumerateActive then
        for pin in pool:EnumerateActive() do PatchPin(pin) end
    end
end

local function WrapAllPools()
    if not pinGuardsInstalled or type(map.pinPools) ~= "table" then return end
    for _, pool in pairs(map.pinPools) do WrapPool(pool) end
end

local function InstallPinGuards()
    if pinGuardsInstalled or type(map.pinPools) ~= "table" then return end
    pinGuardsInstalled = true
    WrapAllPools()
    -- Catch pools created later. If something already put a metatable there,
    -- leave it alone; WrapAllPools also runs on every SetMapID.
    if getmetatable(map.pinPools) == nil then
        setmetatable(map.pinPools, {
            __newindex = function(t, key, pool)
                rawset(t, key, pool)
                WrapPool(pool)
            end,
        })
    end
end

local combatFrame = CreateFrame("Frame")
combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatFrame:SetScript("OnEvent", function()
    if refreshAfterCombat and map and map:IsShown() and not InCombatLockdown() then
        map:OnMapChanged()
    end
    refreshAfterCombat = false
end)

-------------------------------------------------------------------------------
--  Player pin ping
-------------------------------------------------------------------------------
local function PlayerPing()
    if type(map.dataProviders) ~= "table" then return end
    for provider in pairs(map.dataProviders) do
        if type(provider) == "table" and provider.ShouldShowUnit and provider.pin
            and provider.pin.StartPlayerPing then
            local ok, shows = pcall(provider.ShouldShowUnit, provider, "player")
            if ok and shows then
                pcall(provider.pin.StartPlayerPing, provider.pin, 2, 0.25)
                -- Keeps the pin from flickering in size.
                if provider.pin.SynchronizePinSizes then
                    pcall(provider.pin.SynchronizePinSizes, provider.pin)
                end
                return
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Smooth pan. A fast ticker instead of OnUpdate: OnUpdate made the quest
--  blobs flicker in the original.
-------------------------------------------------------------------------------
local panTicker, panStartTime
local panScale, startX, targetX, startY, targetY

local function EaseOutQuart(t)
    local inv = 1 - t
    inv = inv * inv
    return 1 - inv * inv
end

local function ClampedPanAndZoom(scale, x, y)
    local xMin, xMax, yMin, yMax = sc:CalculateScrollExtentsAtScale(scale)
    if xMin then
        x = Clamp(x, xMin, xMax)
        y = Clamp(y, yMin, yMax)
    end
    sc:InstantPanAndZoom(scale, x, y, true)
end

local function PanStop()
    if panTicker then
        panTicker:Cancel()
        panTicker = nil
    end
    panStartTime, panScale, startX, targetX, startY, targetY = nil, nil, nil, nil, nil, nil
end

local function PanTick()
    local elapsed = GetTime() - panStartTime
    if elapsed >= PAN_TIME then
        ClampedPanAndZoom(panScale, targetX, targetY)
        PanStop()
        return
    end
    local t = EaseOutQuart(elapsed / PAN_TIME)
    ClampedPanAndZoom(panScale, startX + t * (targetX - startX), startY + t * (targetY - startY))
end

local function PanTo(x, y)
    panStartTime, panScale = GetTime(), sc:GetCanvasScale()
    startX, startY = sc:GetCurrentScrollX(), sc:GetCurrentScrollY()
    targetX, targetY = x, y
    if not panTicker then
        panTicker = C_Timer.NewTicker(0.01, PanTick)
    end
end

-------------------------------------------------------------------------------
--  Following the player
-------------------------------------------------------------------------------
local followStartTimer -- running while the double-click pan is in progress

local function UpdateThirdPartyPinScales()
    -- Third-party pins (RareScanner and others) often size themselves once at
    -- acquire time via :UpdateScale() and ignore canvas scale changes.
    local function Walk(frame, depth)
        if not frame or depth > 4 then return end
        if type(frame.UpdateScale) == "function" then pcall(frame.UpdateScale, frame) end
        if frame.GetChildren then
            for _, child in ipairs({ frame:GetChildren() }) do Walk(child, depth + 1) end
        end
    end
    Walk(sc.Child, 0)
end

-- Fully zoomed in, centered on the player. No-op where the player isn't on
-- the shown map (instances, other continents): that map stays Blizzard's.
local function ZoomToPlayer()
    local mapID = map:GetMapID()
    local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return end
    local x, y = pos:GetXY()
    PanStop()
    ClampedPanAndZoom(sc:GetScaleForMaxZoom(), x, y)
    UpdateThirdPartyPinScales()
end

local function StartFollowing()
    if following then return end
    following = true
    local pos = C_Map.GetPlayerMapPosition(map:GetMapID(), "player")
    if pos and sc:GetCanvasScale() > sc:GetScaleForMinZoom() then
        PlayerPing()
        PanTo(pos:GetXY())
        followStartTimer = C_Timer.NewTimer(PAN_TIME, function() followStartTimer = nil end)
    end
end

local function StopFollowing()
    if followStartTimer then
        followStartTimer:Cancel()
        followStartTimer = nil
    end
    PanStop()
    following = false
end

-------------------------------------------------------------------------------
--  Opening the map / changing zones
-------------------------------------------------------------------------------
local lastViewedMapWasCurrentMap = false

local function ResetMap(preserveZoom)
    if not CanReposition() then return end
    local playerMap = PlayerMapID()
    if not playerMap then return end
    InstallPinGuards()
    local prevScale = sc:GetCanvasScale()
    map:SetMapID(playerMap)
    if preserveZoom and prevScale then
        local scale = Clamp(prevScale, sc:GetScaleForMinZoom(), sc:GetScaleForMaxZoom())
        ClampedPanAndZoom(scale, sc:GetCurrentScrollX(), sc:GetCurrentScrollY())
    end
    lastViewedMapWasCurrentMap = true
end

-- Follow the player into a new zone when they were looking at their own.
local function CheckMap()
    if not Enabled() or not map:IsShown() then return end
    if lastViewedMapWasCurrentMap and CanReposition() and map:GetMapID() ~= PlayerMapID() then
        -- Keep the zoom while following.
        ResetMap(following)
    end
end

-- Post hook of ToggleWorldMap / ToggleQuestLog (OnShow fires too early).
local function OnMapOpened()
    if not Enabled() or not map:IsShown() then return end
    StopFollowing()
    following = true
    lastViewedMapWasCurrentMap = true
    if CanReposition() and map:GetMapID() ~= PlayerMapID() then
        ResetMap()
    end
    ZoomToPlayer()
end

function ns.RefreshWorldMap()
    if not installed then return end
    if not Enabled() then StopFollowing() end
end

-------------------------------------------------------------------------------
--  Install (Blizzard_WorldMap may be load-on-demand)
-------------------------------------------------------------------------------
local function Install()
    if installed then return end
    map = WorldMapFrame
    sc = map and map.ScrollContainer
    if not sc or not sc.InstantPanAndZoom then return end
    installed = true

    -- Dragging stops following; a double-click starts it again.
    local isMouseDown, lastCursorX, lastCursorY = false, nil, nil
    local lastClickTime = 0

    sc:HookScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" or not Enabled() then return end
        isMouseDown = true
        lastCursorX, lastCursorY = self:GetCursorPosition()
        if self:CanPan() then
            PanStop()
            if followStartTimer then StopFollowing() end
        end
    end)

    sc:HookScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" then return end
        isMouseDown = false
        if not Enabled() then return end
        local now = GetTime()
        if now - lastClickTime < DOUBLE_CLICK then
            StartFollowing()
        end
        lastClickTime = now
    end)

    sc:HookScript("OnUpdate", function(self)
        if not Enabled() then return end

        if isMouseDown then
            PanStop()
            local cx, cy = self:GetCursorPosition()
            if following and (cx ~= lastCursorX or cy ~= lastCursorY) then
                StopFollowing()
            end
        end

        if following and not followStartTimer then
            if not self.targetScale or not self.scrollXExtentsMin or not self.scrollXExtentsMax
                or not self.scrollYExtentsMin or not self.scrollYExtentsMax then
                return
            end
            local mapID = map:GetMapID()
            local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
            if not pos then return end
            local x, y = pos:GetXY()
            x = Clamp(x, self.scrollXExtentsMin, self.scrollXExtentsMax)
            y = Clamp(y, self.scrollYExtentsMin, self.scrollYExtentsMax)
            if self.currentScrollX ~= x then
                self.currentScrollX, self.targetScrollX = x, x
                self:SetNormalizedHorizontalScroll(x)
            end
            if self.currentScrollY ~= y then
                self.currentScrollY, self.targetScrollY = y, y
                self:SetNormalizedVerticalScroll(y)
            end
        end
    end)

    if _G.ToggleWorldMap then hooksecurefunc("ToggleWorldMap", OnMapOpened) end
    if _G.ToggleQuestLog then hooksecurefunc("ToggleQuestLog", OnMapOpened) end

    -- Toggling the quest side panel resizes the canvas and resets the zoom.
    local spt = map.SidePanelToggle
    if spt then
        local function AfterToggle()
            if Enabled() and following then ZoomToPlayer() end
        end
        if spt.CloseButton then spt.CloseButton:HookScript("OnClick", AfterToggle) end
        if spt.OpenButton then spt.OpenButton:HookScript("OnClick", AfterToggle) end
    end

    hooksecurefunc(map, "SetMapID", function(self, mapID)
        WrapAllPools()
        if not Enabled() or not self:IsShown() then return end
        lastViewedMapWasCurrentMap = (mapID == PlayerMapID())
    end)

    -- Some map changes (leaving every zone, e.g.) come with no event.
    local checkTicker
    map:HookScript("OnShow", function()
        if not checkTicker then checkTicker = C_Timer.NewTicker(1, CheckMap) end
    end)
    map:HookScript("OnHide", function()
        StopFollowing()
        if checkTicker then checkTicker:Cancel(); checkTicker = nil end
    end)

    local events = CreateFrame("Frame")
    events:RegisterEvent("ZONE_CHANGED")
    events:RegisterEvent("ZONE_CHANGED_INDOORS")
    events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:SetScript("OnEvent", CheckMap)

    ns.RefreshWorldMap()
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
