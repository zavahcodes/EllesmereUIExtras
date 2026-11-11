-------------------------------------------------------------------------------
--  Baganator combat guard: stops the "ADDON_ACTION_BLOCKED ... Baganator_
--  *BackpackViewFrame*:SetShown()" error when the bag key is pressed in combat.
--
--  Why: Baganator replaces the global ToggleAllBags (the OPENALLBAGS binding)
--  with its own function, so the call is addon code. Its live item buttons
--  inherit ContainerFrameItemButtonTemplate, which is protected; while they are
--  laid out in the backpack frame that frame is protected too, and showing or
--  hiding it from addon code in combat is blocked. Whether the frame is
--  protected at that moment depends on its current layout, which is why the
--  error only shows up sometimes.
--
--  Fix: wrap ToggleAllBags. In combat, if the backpack frame is protected the
--  toggle is skipped (it could not work anyway) and, optionally, done once
--  combat ends. Otherwise Baganator runs as usual.
-------------------------------------------------------------------------------
local _, ns = ...

local VIEW_PREFIXES = {
    "Baganator_CategoryViewBackpackViewFrame",
    "Baganator_SingleViewBackpackViewFrame",
}

-- True when any of the current skin's backpack frames is protected right now.
local function BackpackProtected()
    local api = Baganator and Baganator.API and Baganator.API.Skins
    local group = api and api.GetCurrentSkin and api.GetCurrentSkin()
    if not group then return false end
    for _, prefix in ipairs(VIEW_PREFIXES) do
        local frame = _G[prefix .. group]
        if frame and frame:IsProtected() then return true end
    end
    return false
end

local installed = false

local function Install()
    if installed or type(ToggleAllBags) ~= "function" then return end
    if not (C_AddOns.IsAddOnLoaded("Baganator") and Baganator) then return end
    installed = true

    local original = ToggleAllBags
    local pending, warned = false, false

    local regen = CreateFrame("Frame")
    regen:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        warned = false
        if pending then
            pending = false
            ns.SafeCall(original)
        end
    end)

    ToggleAllBags = function(...)
        if ns.db.baganatorCombatGuard and InCombatLockdown() and BackpackProtected() then
            if ns.db.baganatorCombatDefer then
                -- A second press in the same combat cancels the queued toggle.
                pending = not pending
            end
            regen:RegisterEvent("PLAYER_REGEN_ENABLED")
            if not warned then
                warned = true
                print("|cff33ff99ZavahTweaks|r: bags can't be opened or closed in combat right now"
                    .. (ns.db.baganatorCombatDefer and "; they will toggle when combat ends." or "."))
            end
            return
        end
        return original(...)
    end
end

ns.RegisterModule({
    key = "baganatorCombat",
    name = "Baganator",
    defaults = {
        baganatorCombatGuard = true,
        baganatorCombatDefer = true,
    },
    options = {
        { type = "checkbox", key = "baganatorCombatGuard", label = "Prevent bag errors in combat",
          tooltip = "When Baganator's bags can't be opened or closed in combat (Blizzard blocks it), "
              .. "the bag key does nothing instead of raising an ADDON_ACTION_BLOCKED error. "
              .. "Only does something when Baganator is loaded." },
        { type = "checkbox", key = "baganatorCombatDefer", label = "Toggle bags when combat ends",
          tooltip = "If the bag key was pressed while blocked, open/close the bags as soon as combat ends. "
              .. "Pressing it again during the same combat cancels it." },
    },
    OnLoad = function()
        -- Baganator swaps ToggleAllBags in its own ADDON_LOADED; PLAYER_LOGIN is
        -- guaranteed to run after that.
        if IsLoggedIn() then
            Install()
        else
            local f = CreateFrame("Frame")
            f:RegisterEvent("PLAYER_LOGIN")
            f:SetScript("OnEvent", function(self)
                self:UnregisterEvent("PLAYER_LOGIN")
                Install()
            end)
        end
    end,
    Refresh = function()
        -- Nothing to undo: the wrapper checks the settings on every call.
    end,
})
