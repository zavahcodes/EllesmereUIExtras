if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  Tooltip health bar. EllesmereUIBlizzardSkin hides GameTooltipStatusBar
--  (alpha 0, "Hide Unit Health Strip") and shrinks it to 3 px when reskinned,
--  so instead of fighting over Blizzard's bar we own a separate StatusBar that
--  hangs just below the tooltip. Blizzard's bar is never touched (no taint).
-------------------------------------------------------------------------------
local _, ns = ...
local IsSecret = ns.IsSecret

local FLAT = "Interface\\Buttons\\WHITE8X8"
local THROTTLE = 0.1
local DEFAULT_R, DEFAULT_G, DEFAULT_B = 0.1, 0.8, 0.1

local bar = CreateFrame("StatusBar", "EUIX_TooltipHealthBar", GameTooltip)
bar:SetStatusBarTexture(FLAT)
bar:SetMinMaxValues(0, 1)
bar:SetValue(1)
bar:SetPoint("TOPLEFT", GameTooltip, "BOTTOMLEFT", 1, -2)
bar:SetPoint("TOPRIGHT", GameTooltip, "BOTTOMRIGHT", -1, -2)
bar:SetHeight(8)
bar:Hide()

local bg = bar:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0, 0, 0, 0.6)

-- 1 px border drawn just outside the bar.
local function BorderEdge(p1, p2, x1, y1, x2, y2, horizontal)
    local t = bar:CreateTexture(nil, "BORDER")
    t:SetColorTexture(0, 0, 0, 1)
    t:SetPoint(p1, bar, p1, x1, y1)
    t:SetPoint(p2, bar, p2, x2, y2)
    if horizontal then t:SetHeight(1) else t:SetWidth(1) end
end
BorderEdge("TOPLEFT", "TOPRIGHT", -1, 1, 1, 1, true)
BorderEdge("BOTTOMLEFT", "BOTTOMRIGHT", -1, -1, 1, -1, true)
BorderEdge("TOPLEFT", "BOTTOMLEFT", -1, 1, -1, -1, false)
BorderEdge("TOPRIGHT", "BOTTOMRIGHT", 1, 1, 1, -1, false)

local text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
text:SetPoint("CENTER", bar, "CENTER", 0, 0)

-- EllesmereUI's font DB is only ready after login; applied lazily on first show.
local fontApplied = false
local function ApplyFont()
    fontApplied = true
    local size = ns.db.tooltipHealthTextSize or 10
    -- Fallback: keep the template's own face/flags, change only the size.
    local path, _, flag = text:GetFont()
    flag = flag or ""
    local EUI = EllesmereUI
    if EUI and EUI.GetFontPath then
        local ok, p = pcall(EUI.GetFontPath)
        if ok and p then
            path = p
            flag = ""
            if EUI.GetFontOutlineFlag then
                local okF, f = pcall(EUI.GetFontOutlineFlag)
                if okF and f then flag = f end
            end
        end
    end
    if not path then return end
    text:SetFont(path, size, flag)
    if flag == "" then
        text:SetShadowOffset(1, -1)
        text:SetShadowColor(0, 0, 0, 1)
    end
end

local function ClassColor(classToken)
    if not classToken or IsSecret(classToken) then return nil end
    if EllesmereUI and EllesmereUI.GetClassColor then
        local c = EllesmereUI.GetClassColor(classToken)
        if c then return c.r, c.g, c.b end
    end
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
    if c then return c.r, c.g, c.b end
end

local function BarColor(unit, dead)
    if UnitIsPlayer(unit) then
        local _, classToken = UnitClass(unit)
        local r, g, b = ClassColor(classToken)
        if r then return r, g, b end
        return DEFAULT_R, DEFAULT_G, DEFAULT_B
    end
    if dead then return 0.5, 0.5, 0.5 end
    local tapped = UnitIsTapDenied and UnitIsTapDenied(unit)
    if tapped and not IsSecret(tapped) then return 0.5, 0.5, 0.5 end
    local reaction = UnitReaction and UnitReaction(unit, "player")
    if reaction and not IsSecret(reaction) then
        local fc = FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
        if fc then return fc.r, fc.g, fc.b end
    end
    return DEFAULT_R, DEFAULT_G, DEFAULT_B
end

local function HealthText(unit, cur, max)
    if UnitHealthPercent and CurveConstants and CurveConstants.ScaleTo100 then
        local ok, pct = pcall(UnitHealthPercent, unit, true, CurveConstants.ScaleTo100)
        -- string.format accepts secret numbers, so no comparison is needed here.
        if ok and pct ~= nil then return string.format("%d%%", pct) end
    end
    if cur and max and not IsSecret(cur) and not IsSecret(max) and max > 0 then
        return string.format("%d%%", math.floor(cur / max * 100 + 0.5))
    end
    return ""
end

local function Update(unit)
    local dead = UnitIsDeadOrGhost(unit)
    if IsSecret(dead) then dead = false end
    local cur, max = UnitHealth(unit), UnitHealthMax(unit)
    -- StatusBar takes secret values directly; pcall covers clients that don't.
    pcall(bar.SetMinMaxValues, bar, 0, max or 1)
    pcall(bar.SetValue, bar, dead and 0 or cur or 0)
    bar:SetStatusBarColor(BarColor(unit, dead))
    if ns.db.tooltipHealthText then
        text:SetText(dead and DEAD or HealthText(unit, cur, max))
        text:Show()
    else
        text:Hide()
    end
end

local function HideBar()
    bar.unit = nil
    bar:Hide()
end

local elapsedAcc = 0
bar:SetScript("OnUpdate", function(self, elapsed)
    elapsedAcc = elapsedAcc + elapsed
    if elapsedAcc < THROTTLE then return end
    elapsedAcc = 0
    local unit = self.unit
    if not unit then return end
    -- Once the cursor leaves an NPC, "mouseover" stops existing while the tooltip
    -- is still fading out. Keep the last values frozen: the bar is a child of
    -- GameTooltip, so it fades with it and is hidden by the GameTooltip OnHide hook.
    if not UnitExists(unit) then
        self.unit = nil
        return
    end
    Update(unit)
end)

ns.OnUnitTooltip(function(tt, unit)
    if not unit or not ns.db.tooltipHealthBar then
        HideBar()
        return
    end
    if not fontApplied then ApplyFont() end
    bar:SetHeight(ns.db.tooltipHealthHeight or 8)
    bar.unit = unit
    elapsedAcc = 0
    Update(unit)
    bar:Show()
end)

-- Live apply for the options panel: hide when turned off, else re-apply height/text.
function ns.RefreshTooltipHealth()
    -- Font size is re-applied on the next show even when the bar is hidden now.
    fontApplied = false
    if not bar:IsShown() then return end
    ApplyFont()
    if not ns.db.tooltipHealthBar then
        HideBar()
        return
    end
    bar:SetHeight(ns.db.tooltipHealthHeight or 8)
    if bar.unit and UnitExists(bar.unit) then
        Update(bar.unit)
    elseif not ns.db.tooltipHealthText then
        text:Hide()
    end
end

-- Item/spell tooltips reuse GameTooltip: clear the bar whenever its content is wiped.
GameTooltip:HookScript("OnHide", HideBar)
GameTooltip:HookScript("OnTooltipCleared", HideBar)
