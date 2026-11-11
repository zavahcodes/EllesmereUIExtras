-------------------------------------------------------------------------------
--  Pawn tooltip cache: fixes the FPS drop while an item tooltip is open with
--  Pawn enabled, without touching Pawn's code.
--
--  Why: bag addons (Baganator) refresh the item tooltip constantly while it is
--  open, and every refresh runs Pawn's PawnUpdateTooltip -> PawnGetItemData.
--  On Forever, Pawn can't trust its own item cache (PawnItemCacheCanAssumeComplete
--  is only true on Draenor+), so even on a cache hit it rebuilds its hidden
--  PawnPrivateTooltip1 with SetHyperlink to compare line counts: a second full
--  tooltip build (Blizzard processing, every addon's post calls, layout) on
--  every refresh.
--
--  Fix: wrap the global PawnGetItemData with a short memo keyed by item link.
--  Only complete results (with Values) are kept; the memo is wiped whenever
--  Pawn clears its caches or tooltips, when gear changes, and entries expire
--  after a few seconds anyway. Upgrade checks still run every time against
--  the current gear; only the per-item stat parsing is reused.
-------------------------------------------------------------------------------
local _, ns = ...

local TTL = 5 -- seconds

ns.RegisterModule({
    key = "pawnFix",
    name = "Pawn",
    defaults = {
        pawnTooltipCache = true,
    },
    options = {
        { type = "checkbox", key = "pawnTooltipCache", label = "Cache Pawn item data",
          tooltip = "Fixes the FPS drop while an item tooltip is open with Pawn enabled: "
              .. "Pawn re-reads the item's stats on every tooltip refresh, so its result is reused "
              .. "for a few seconds. Only does something when Pawn is loaded." },
    },
    OnLoad = function()
        if type(PawnGetItemData) ~= "function" then return end

        local memo = {} -- [itemLink] = { item = Item, time = GetTime() }
        local function Wipe() wipe(memo) end

        local original = PawnGetItemData
        PawnGetItemData = function(itemLink, ...)
            if not ns.db.pawnTooltipCache or type(itemLink) ~= "string" then
                return original(itemLink, ...)
            end
            local now = GetTime()
            local entry = memo[itemLink]
            if entry and now - entry.time < TTL then
                return entry.item
            end
            local item = original(itemLink, ...)
            if item and item.Values then
                memo[itemLink] = { item = item, time = now }
            else
                memo[itemLink] = nil
            end
            return item
        end

        for _, name in ipairs({ "PawnClearCache", "PawnClearCacheValuesOnly", "PawnResetTooltips", "PawnUncacheItem" }) do
            if type(_G[name]) == "function" then hooksecurefunc(name, Wipe) end
        end

        local events = CreateFrame("Frame")
        events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        events:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
        events:SetScript("OnEvent", Wipe)
    end,
    Refresh = function()
        -- Nothing to undo: the wrapper checks the setting on every call.
    end,
})
