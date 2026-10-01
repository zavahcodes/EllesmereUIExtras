if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  Player frame without a power bar (stock styles only: WoW Forever, Blizzard
--  Style, Classic WoW UI). Hides the player's attached power bar and stretches
--  the health bar down over the power track, so the art has no empty slot.
--
--  Unit Frames keeps its namespace private, so this rides the built frame:
--  the stock layout pass always ends a health:SetSize(stock) with the power
--  bar placed and the health mask re-seated at its atlas size, so a SetSize
--  hook queues one stretch for the next frame, after the whole pass. The
--  stretch reads the bars' live geometry, so it holds for every stock kit.
--  frame._blizzArtFrame exists only under a stock style.
-------------------------------------------------------------------------------
local _, ns = ...

local FRAME_NAME = "EllesmereUIUnitFrames_Player"

local player        -- the hooked player frame
local pending       -- the layout pass re-seated the stock geometry
local queued        -- a next-frame Apply is scheduled
local applying      -- our own SetHeight is running (the hook ignores it)
local waitCombat    -- an Apply waits for combat to end

local function Active()
    return ns.db.playerHidePower and player and player._blizzArtFrame ~= nil
end

local function SizeAbsorbs(w, h)
    local hp = player.HealthPrediction and player.HealthPrediction.damageAbsorb
    if not hp then return end
    local bars = { hp, hp._forward, hp._healAbsorb }
    for i = 1, 3 do
        local sb = bars[i]
        if sb and sb.SetSize then sb:SetSize(w, h) end
    end
end

local function Apply()
    queued = nil
    if not Active() or not pending then return end
    if InCombatLockdown() then waitCombat = true; return end
    local health, power = player.Health, player.Power
    if not (health and power) then return end

    -- Only an attached bar has a track to take over: both bars sit on the
    -- same parent anchor (a detached or disabled bar keeps the layout as is).
    local _, hRel, _, _, hy = health:GetPoint(1)
    local _, pRel, _, _, py = power:GetPoint(1)
    if not (hRel and pRel and hRel == pRel and hy and py) then return end
    local stockH = health:GetHeight()
    -- The art's track runs a few pixels past the power bar's own box; the
    -- extra height closes that gap (user-tunable, default 1).
    local newH = (-py + power:GetHeight()) - (-hy) + (ns.db.playerHidePowerExtra or 0)
    if newH <= stockH then return end
    pending = nil

    applying = true
    health:SetHeight(newH)
    applying = nil

    -- The rounded health mask grows by the same amount (its own height is the
    -- atlas size the layout just set, or our earlier stretch when the pass
    -- re-sized the bar without re-seating the mask).
    local mask = health._blizzMask
    if mask then
        local mh = mask:GetHeight()
        if mask._euixStretched and math.abs(mh - mask._euixStretched) < 0.01 then
            mh = mask._euixNative
        end
        mask._euixNative = mh
        mask._euixStretched = mh + (newH - stockH)
        mask:SetHeight(mask._euixStretched)
    end

    SizeAbsorbs(health:GetWidth(), newH)
    power:Hide()
end

local function Queue()
    pending = true
    if queued then return end
    queued = true
    C_Timer.After(0, Apply)
end

local function Hook()
    if player then return true end
    local f = _G[FRAME_NAME]
    if not (f and f.Health) then return false end
    player = f
    hooksecurefunc(f.Health, "SetSize", function()
        if not applying then Queue() end
    end)
    if f.Power then
        hooksecurefunc(f.Power, "Show", function(p)
            if Active() then p:Hide() end
        end)
    end
    return true
end

-- Options callback: on stretches now; off hands the frame back to the stock
-- layout (a Unit Frames reload re-seats sizes and mask, and shows the power
-- bar unless Unit Frames itself hides it).
function ns.RefreshPlayerPower()
    if not Hook() then return end
    if ns.db.playerHidePower then
        -- Re-run the stock layout so the stretch starts from stock sizes
        -- (an extra-height change would otherwise stack on the last one).
        if player._blizzArtFrame and _G._EUF_ReloadFrames and not InCombatLockdown() then
            _G._EUF_ReloadFrames()
        end
        Queue()
    elseif player._blizzArtFrame then
        if player.Power then player.Power:Show() end
        if _G._EUF_ReloadFrames then _G._EUF_ReloadFrames() end
    end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if waitCombat then
            waitCombat = nil
            Apply()
        end
        return
    end
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    -- The frame spawns at Unit Frames' enable; retry briefly if it is late.
    local tries = 0
    local function Try()
        if Hook() then
            if ns.db.playerHidePower then Queue() end
        elseif tries < 10 then
            tries = tries + 1
            C_Timer.After(1, Try)
        end
    end
    Try()
end)
