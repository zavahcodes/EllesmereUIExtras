-------------------------------------------------------------------------------
--  ZavahTweaks: core. Saved settings, a tiny module registry, shared
--  secret-value/color helpers and a single unit-tooltip post call that every
--  tooltip module registers into.
--
--  Adding a feature = one file in Modules/ that calls ns.RegisterModule{...}
--  and one line in the .toc. The core merges its defaults into the saved
--  variables, builds its options section and calls its OnLoad once settings
--  are ready. Modules read ns.db at call time, so options apply live.
--
--  Module spec:
--    key      unique id (string)
--    name     section header in the options panel (consecutive modules with
--             the same name share one header)
--    defaults { settingKey = defaultValue, ... }
--    options  list of controls, each one of:
--               { type = "checkbox", key, label, tooltip }
--               { type = "slider",   key, label, tooltip, min, max, step }
--               { type = "dropdown", key, label, tooltip, choices = { {value, text}, ... } }
--    OnLoad   optional fn(db), called once after saved variables load
--    Refresh  optional fn(db), called whenever one of its settings changes
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

ns.modules = {}
ns.DEFAULTS = {}

-- Live table; replaced by the saved one on ADDON_LOADED.
ns.db = {}

function ns.RegisterModule(module)
    assert(type(module) == "table" and module.key, "ZavahTweaks: module needs a key")
    for k, v in pairs(module.defaults or {}) do
        assert(ns.DEFAULTS[k] == nil, "ZavahTweaks: duplicate setting " .. k)
        ns.DEFAULTS[k] = v
        ns.db[k] = v
    end
    ns.modules[#ns.modules + 1] = module
    return module
end

local function SafeCall(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then geterrorhandler()(err) end
end
ns.SafeCall = SafeCall

-------------------------------------------------------------------------------
--  Shared helpers
-------------------------------------------------------------------------------
local issecretvalue = issecretvalue
function ns.IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end
local IsSecret = ns.IsSecret

-- r, g, b for a class token (EllesmereUI's palette first, then Blizzard's), or nil.
function ns.ClassColor(classToken)
    if not classToken or IsSecret(classToken) then return nil end
    if EllesmereUI and EllesmereUI.GetClassColor then
        local c = EllesmereUI.GetClassColor(classToken)
        if c then return c.r, c.g, c.b end
    end
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
    if c then return c.r, c.g, c.b end
end

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

-------------------------------------------------------------------------------
--  Unit tooltip dispatcher. Callbacks run as fn(tt, unit, data); unit may be
--  nil (modules hide their extras then).
-------------------------------------------------------------------------------
local unitTooltipCallbacks = {}
function ns.OnUnitTooltip(fn)
    unitTooltipCallbacks[#unitTooltipCallbacks + 1] = fn
end

local function OnUnitTooltip(tt, data)
    if tt ~= GameTooltip or tt:IsForbidden() then return end
    local unit = ns.ResolveTooltipUnit(tt, data)
    for i = 1, #unitTooltipCallbacks do
        SafeCall(unitTooltipCallbacks[i], tt, unit, data)
    end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnitTooltip)
else
    GameTooltip:HookScript("OnTooltipSetUnit", OnUnitTooltip)
end

-------------------------------------------------------------------------------
--  Loader
-------------------------------------------------------------------------------
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
    if name ~= ADDON_NAME then return end
    self:UnregisterEvent("ADDON_LOADED")
    ZavahTweaksDB = ZavahTweaksDB or {}
    for k, v in pairs(ns.DEFAULTS) do
        if ZavahTweaksDB[k] == nil then ZavahTweaksDB[k] = v end
    end
    ns.db = ZavahTweaksDB
    for _, module in ipairs(ns.modules) do
        if module.OnLoad then SafeCall(module.OnLoad, ns.db) end
    end
    if ns.InitOptions then ns.InitOptions() end
end)
