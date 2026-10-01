if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  Target of target: a "Target:" line showing who the hovered player or NPC is
--  targeting. Updated IN PLACE on refresh passes (Blizzard re-runs unit post
--  calls while the tooltip is up), so the line is never appended twice. Stands
--  down when EllesmereUI's own "Show Unit Target" option is on, to avoid a
--  duplicate row.
-------------------------------------------------------------------------------
local _, ns = ...
local IsSecret = ns.IsSecret

local LABEL = "Target:"
local YOU_TEXT = ">> YOU <<"

local function ClassColor(classToken)
    if not classToken or IsSecret(classToken) then return nil end
    if EllesmereUI and EllesmereUI.GetClassColor then
        local c = EllesmereUI.GetClassColor(classToken)
        if c then return c.r, c.g, c.b end
    end
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
    if c then return c.r, c.g, c.b end
end

-- Returns name, r, g, b for the target token, or nil when there is nothing to show.
local function TargetInfo(tu)
    if not UnitExists(tu) then return nil end
    if UnitIsUnit(tu, "player") then return YOU_TEXT, 1, 0.2, 0.2 end
    local name = UnitName(tu)
    if not name or IsSecret(name) then return nil end
    local r, g, b = 0.9, 0.9, 0.9
    if UnitIsPlayer(tu) then
        local _, classToken = UnitClass(tu)
        local cr, cg, cb = ClassColor(classToken)
        if cr then r, g, b = cr, cg, cb end
    else
        local reaction = UnitReaction and UnitReaction(tu, "player")
        if reaction and not IsSecret(reaction) then
            local fc = FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
            if fc then r, g, b = fc.r, fc.g, fc.b end
        end
    end
    return name, r, g, b
end

local function FindLabelLine(tt)
    for i = 2, (tt.NumLines and tt:NumLines() or 0) do
        local lineL = _G["GameTooltipTextLeft" .. i]
        local txt = lineL and lineL:GetText()
        if txt and not IsSecret(txt) and txt == LABEL then return i end
    end
end

ns.OnUnitTooltip(function(tt, unit)
    if not unit or not ns.db.tooltipTarget then return end
    if EllesmereUIDB and EllesmereUIDB.tooltipShowTarget then return end
    local tu = unit .. "target"
    if C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret then
        local s = C_Secrets.ShouldUnitIdentityBeSecret(tu)
        if IsSecret(s) or s == true then return end
    end
    local name, r, g, b = TargetInfo(tu)
    local idx = FindLabelLine(tt)
    if idx then
        local lineR = _G["GameTooltipTextRight" .. idx]
        if not lineR then return end
        if name then
            lineR:SetText(name)
            lineR:SetTextColor(r, g, b)
        else
            -- Target dropped mid-hover: keep the row, blank the value.
            lineR:SetText("-")
            lineR:SetTextColor(0.6, 0.6, 0.6)
        end
    elseif name then
        tt:AddDoubleLine(LABEL, name, 1, 1, 1, r, g, b)
    end
end)
