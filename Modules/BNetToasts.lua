-------------------------------------------------------------------------------
--  Battle.net toasts: hides the BNToastFrame pop-up shown when a Battle.net
--  friend comes online (and, optionally, goes offline).
--
--  The client already has these switches (CVars showToastOnline and
--  showToastOffline, the "Online/Offline Friends" boxes of Retail's Social
--  options), but Forever's options menu doesn't show them. This module only
--  sets the CVars; Blizzard's toast code checks them itself, so no frame is
--  touched. Turning an option off sets its CVar back to the game default (1).
--  The chat line for a friend coming online is not affected.
-------------------------------------------------------------------------------
local _, ns = ...

local CVARS = {
    bnetHideOnlineToast  = "showToastOnline",
    bnetHideOfflineToast = "showToastOffline",
}

local module = ns.RegisterModule({
    key = "bnetToasts",
    name = "Battle.net toasts",
    defaults = {
        bnetHideOnlineToast = true,
        bnetHideOfflineToast = false,
    },
    options = {
        { type = "checkbox", key = "bnetHideOnlineToast", label = "Hide friend online toasts",
          tooltip = "Hides the pop-up shown when a Battle.net friend comes online "
              .. "(the game's showToastOnline setting, missing from Forever's Social options)." },
        { type = "checkbox", key = "bnetHideOfflineToast", label = "Hide friend offline toasts",
          tooltip = "Hides the pop-up shown when a Battle.net friend goes offline "
              .. "(the game's showToastOffline setting)." },
    },
})

local GetCVar = C_CVar and C_CVar.GetCVar or GetCVar
local SetCVar = C_CVar and C_CVar.SetCVar or SetCVar

local function Apply()
    if not (GetCVar and SetCVar) then return end
    for key, cvar in pairs(CVARS) do
        local want = ns.db[key] and "0" or "1"
        local current = GetCVar(cvar)
        if current ~= nil and current ~= want then
            SetCVar(cvar, want)
        end
    end
end

module.Refresh = Apply

module.OnLoad = function()
    Apply()
    -- Apply once more after login, in case anything resets the CVars on startup.
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        Apply()
    end)
end
