-------------------------------------------------------------------------------
--  Baganator: keep bag layout while open. In Baganator's category view the
--  items jump around while the bag is open: selling, disenchanting, opening
--  or closing a vendor all re-arrange it. With this on, the bag is arranged
--  only when it opens; until it closes every item stays where it was, gone
--  items always leave an empty hole and new items go at the end of their
--  category.
--
--  Why it moves: Baganator keeps holes for removed items itself, but drops
--  them as soon as any category gains an item (disenchant materials), and it
--  splits grouped stacks when a vendor (bank, mail...) opens and groups them
--  again when it closes, which re-arranges everything twice.
--
--  How: on the backpack category view frame (instance methods; Baganator's
--  mixins are frozen):
--    * UpdateForCharacter: the stack splitting state is held at what it was
--      when the bag opened, so grouping never flips while it's open.
--    * LayoutManager:Display: each category's items are put back in the order
--      shown before (a snapshot taken when the bag opened), with Baganator's
--      own "empty" placeholders where items went missing.
--  Single bag view is untouched (it never re-arranges). Bank views too.
-------------------------------------------------------------------------------
local _, ns = ...

local VIEW_PREFIX = "Baganator_CategoryViewBackpackViewFrame"

-- Baganator's internal refresh reasons (Core/Constants.lua RefreshReason).
local REFRESH_SORTS     = 128
local REFRESH_CHARACTER = 1024

local module = ns.RegisterModule({
    key = "baganatorFreeze",
    name = "Baganator",
    defaults = {
        baganatorFreezeLayout = true,
    },
    options = {
        { type = "checkbox", key = "baganatorFreezeLayout", label = "Keep bag layout while open",
          tooltip = "Category view: the bag is arranged only when it opens. Selling, disenchanting or opening and "
              .. "closing a vendor no longer move items around; gone items leave an empty hole until the bag is "
              .. "closed and new items go at the end of their category. "
              .. "Stacks stay grouped at a vendor if the bag was opened first. A category that wasn't shown when the "
              .. "bag opened (e.g. Recent) still pushes the ones under it down. Only does something when Baganator "
              .. "is loaded." },
    },
})

local function Enabled()
    return ns.db.baganatorFreezeLayout
end

-------------------------------------------------------------------------------
--  Reordering one category's items to match the last layout shown
-------------------------------------------------------------------------------
local holeCount = 0
local function Hole(bagID, slotID)
    holeCount = holeCount + 1
    -- Same shape as Baganator's own placeholder (BagLayout.lua Display), plus a
    -- unique key so its stack grouping never merges two holes.
    return { isDummy = true, dummyType = "empty", bagID = bagID, slotID = slotID, key = "zavahHole" .. holeCount }
end

-- What makes an item "the same" between two renders: its grouping key when
-- items are grouped (one button per key), the exact item otherwise.
local function Identity(item, grouping)
    if grouping then return item.key end
    return item.keyGUID or ((item.bagID or "?") .. "_" .. (item.slotID or "?"))
end

-- Snapshot of a result list: one unit per button, in order.
local function Snapshot(results, grouping)
    local units, seen = {}, {}
    for _, item in ipairs(results) do
        if item.isDummy then
            units[#units + 1] = { hole = true, bagID = item.bagID, slotID = item.slotID }
        else
            local id = Identity(item, grouping)
            if id ~= nil and not (grouping and seen[id]) then
                seen[id] = true
                units[#units + 1] = { id = id, bagID = item.bagID, slotID = item.slotID }
            end
        end
    end
    return units
end

-- New result list for `results` in the order of `units`.
local function Reorder(results, units, grouping)
    -- Current items by identity, in their current order.
    local queues, order = {}, {}
    for _, item in ipairs(results) do
        local id = Identity(item, grouping)
        if id == nil then
            id = item
        end
        if not queues[id] then
            queues[id] = {}
            order[#order + 1] = id
        end
        table.insert(queues[id], item)
    end

    -- Takes one button's worth of items: all of a key when grouping.
    local function Take(id)
        local queue = queues[id]
        if not queue or #queue == 0 then return nil end
        if grouping then
            queues[id] = {}
            return queue
        end
        return { table.remove(queue, 1) }
    end

    local slots = {} -- one entry per button: a list of items, or a hole
    for _, unit in ipairs(units) do
        local items = unit.id ~= nil and Take(unit.id)
        if items then
            slots[#slots + 1] = items
        else
            -- Gone (or a hole already): stays an empty hole until the bag closes.
            slots[#slots + 1] = { Hole(unit.bagID, unit.slotID) }
        end
    end

    -- New items: at the end of the category, never into a hole.
    for _, id in ipairs(order) do
        local items = Take(id)
        while items do
            slots[#slots + 1] = items
            items = Take(id)
        end
    end

    local out = {}
    for _, slot in ipairs(slots) do
        for _, item in ipairs(slot) do out[#out + 1] = item end
    end
    return out
end

-------------------------------------------------------------------------------
--  Patching a backpack category view frame
-------------------------------------------------------------------------------
local patched = {}

local function CategoryKey(details)
    return tostring(details.source) .. "_" .. tostring(details.label) .. "_"
        .. tostring(details.groupLabel) .. "_" .. tostring(details.autoIndex)
end

local function Patch(frame)
    if not frame or patched[frame] or type(frame.UpdateForCharacter) ~= "function" then return end
    local manager = frame.LayoutManager
    if not manager or type(manager.Display) ~= "function" then return end
    patched[frame] = true

    local held      -- stack splitting state held while open: { transfer, socketing }
    local snapshots -- category key -> units shown, while open
    local snapGrouping

    local function Reset()
        held, snapshots, snapGrouping = nil, nil, nil
        -- Back to the real stack splitting state (the vendor may have closed
        -- while it was held), so the next open starts from it.
        if frame.zavahRealSplit then
            frame.splitStacksDueToTransfer, frame.splitStacksDueToSocketing = frame.zavahRealSplit[1], frame.zavahRealSplit[2]
            frame.zavahRealSplit = nil
        end
    end
    frame.zavahFreezeReset = Reset

    -- Hold the stack splitting state (vendor, bank, mail, socketing) at what it
    -- was when the bag opened, so grouping doesn't flip while it's open.
    local origUpdate = frame.UpdateForCharacter
    frame.UpdateForCharacter = function(self, ...)
        if Enabled() and self:IsVisible() and self.isLive then
            -- (the real state, to put back if the option is turned off)
            self.zavahRealSplit = { self.splitStacksDueToTransfer, self.splitStacksDueToSocketing }
            if held then
                self.splitStacksDueToTransfer, self.splitStacksDueToSocketing = held[1], held[2]
            else
                held = { self.splitStacksDueToTransfer, self.splitStacksDueToSocketing }
            end
        end
        return origUpdate(self, ...)
    end

    local origDisplay = manager.Display
    manager.Display = function(self, bagWidth, bagIndexes, bagTypes, composed, ...)
        local ok, err = pcall(function()
            local container = self:GetParent()
            local refresh = container.refreshState or {}
            -- (an item on the cursor, addToCategoryMode, is not a reason: Baganator's
            -- add/remove buttons are added after this and aren't in the snapshot)
            if not Enabled() or not container.isLive
                or refresh[REFRESH_SORTS] or refresh[REFRESH_CHARACTER]
                or type(composed) ~= "table" or type(composed.details) ~= "table" then
                snapshots = nil -- taken again on the next render
                return
            end
            local grouping = container.isGrouping and true or false
            if snapshots and snapGrouping ~= grouping then snapshots = nil end

            local fresh = snapshots == nil
            local newSnapshots = {}
            for _, details in ipairs(composed.details) do
                if type(details.results) == "table" and not details.emptySlots then
                    local key = CategoryKey(details)
                    local units = not fresh and snapshots[key]
                    if units then
                        details.results = Reorder(details.results, units, grouping)
                    end
                    newSnapshots[key] = Snapshot(details.results, grouping)
                end
            end
            snapshots, snapGrouping = newSnapshots, grouping
        end)
        if not ok then
            snapshots = nil
            geterrorhandler()(err)
        end
        return origDisplay(self, bagWidth, bagIndexes, bagTypes, composed, ...)
    end

    -- Closing the bag: the next open is arranged as usual.
    manager:HookScript("OnHide", Reset)
end

local function PatchCurrent()
    local api = Baganator and Baganator.API and Baganator.API.Skins
    local skin = api and api.GetCurrentSkin and api.GetCurrentSkin()
    if skin then Patch(_G[VIEW_PREFIX .. skin]) end
end

-------------------------------------------------------------------------------
--  Settings / install
-------------------------------------------------------------------------------
function module.Refresh()
    for frame in pairs(patched) do
        if frame.zavahFreezeReset then frame.zavahFreezeReset() end
    end
    if Baganator and Baganator.API and Baganator.API.RequestLayoutUpdate then
        ns.SafeCall(Baganator.API.RequestLayoutUpdate)
    end
end

local function Install()
    if not (C_AddOns.IsAddOnLoaded("Baganator") and Baganator) then return end
    PatchCurrent()
    -- Frames are created at login and when the skin changes.
    local registry = Baganator.CallbackRegistry
    if registry and registry.RegisterCallback then
        pcall(registry.RegisterCallback, registry, "BackpackFrameChanged", function(_, frame)
            Patch(frame)
            PatchCurrent()
        end, module)
    end
end

module.OnLoad = function()
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")
        -- After Baganator's own PLAYER_LOGIN, which creates the frames.
        C_Timer.After(0, Install)
    end)
    if IsLoggedIn() then
        f:UnregisterEvent("PLAYER_LOGIN")
        Install()
    end
end
