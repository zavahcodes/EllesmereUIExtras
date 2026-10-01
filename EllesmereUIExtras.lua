if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUIExtras: core. Saved settings, secret-value helpers and a single
--  unit-tooltip post call that every tooltip feature registers into.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local DEFAULTS = {
    tooltipHealthBar    = true,
    tooltipHealthText   = true,
    tooltipHealthHeight = 8,
    tooltipHealthTextSize = 10,
    tooltipTarget       = true,
}
ns.DEFAULTS = DEFAULTS

-- Live table; replaced by the saved one on ADDON_LOADED. Features read ns.db at call time.
ns.db = CopyTable(DEFAULTS)

local issecretvalue = issecretvalue
function ns.IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end
local IsSecret = ns.IsSecret

-- Clean (non-secret, existing) unit token for a unit tooltip, or nil. data.guid from the
-- tooltip's own data pass is the identity; "mouseover" is only accepted when it provably
-- maps to that guid, so a lagging cursor-focus token never misattributes the tooltip.
function ns.ResolveTooltipUnit(tt, data)
    local guid = data and data.guid
    if guid and IsSecret(guid) then guid = nil end
    local ok, _, u = pcall(tt.GetUnit, tt)
    if ok and u and not IsSecret(u) and UnitExists(u) then
        return u
    end
    if guid and UnitTokenFromGUID then
        local tu = UnitTokenFromGUID(guid)
        if tu and not IsSecret(tu) and UnitExists(tu) then return tu end
    end
    if guid and UnitExists("mouseover") then
        local mg = UnitGUID("mouseover")
        if mg and not IsSecret(mg) and mg == guid then return "mouseover" end
    end
    return nil
end

-- Callbacks run as fn(tt, unit, data); unit may be nil (features hide their extras then).
local unitTooltipCallbacks = {}
function ns.OnUnitTooltip(fn)
    unitTooltipCallbacks[#unitTooltipCallbacks + 1] = fn
end

local function OnUnitTooltip(tt, data)
    if tt ~= GameTooltip or tt:IsForbidden() then return end
    local unit = ns.ResolveTooltipUnit(tt, data)
    for i = 1, #unitTooltipCallbacks do
        local ok, err = pcall(unitTooltipCallbacks[i], tt, unit, data)
        if not ok then geterrorhandler()(err) end
    end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnitTooltip)
else
    GameTooltip:HookScript("OnTooltipSetUnit", OnUnitTooltip)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
    if name ~= ADDON_NAME then return end
    self:UnregisterEvent("ADDON_LOADED")
    EllesmereUIExtrasDB = EllesmereUIExtrasDB or {}
    for k, v in pairs(DEFAULTS) do
        if EllesmereUIExtrasDB[k] == nil then EllesmereUIExtrasDB[k] = v end
    end
    ns.db = EllesmereUIExtrasDB
    if ns.InitOptions then ns.InitOptions() end
end)
