if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  Loot roll votes: on Blizzard's loot roll popups (GroupLootFrame), each roll
--  button (Need / Greed / Disenchant / Transmog / Pass) shows how many group
--  members picked it, and hovering the button lists them in class colors.
--
--  Three sources feed the same per-roll table (whichever the client has):
--   * legacy C_LootHistory (LOOT_HISTORY_ROLL_CHANGED, what ElvUI uses): gives
--     the rollID directly.
--   * modern C_LootHistory drops (LOOT_HISTORY_UPDATE_DROP): rebuilt whole on
--     every update. Once either history source fires, chat parsing stands down.
--   * CHAT_MSG_LOOT "X has selected Need for: [item]" lines: fallback for
--     clients where the loot history never fires.
--  Drops/lines carry an item link, not a rollID, so they are matched to the
--  open popups by link (lowest rollID first when the same item drops twice).
--
--  Frames are only touched from our own events / next-frame timers, never from
--  inside Blizzard's container layout pass.
-------------------------------------------------------------------------------
local _, ns = ...
local IsSecret = ns.IsSecret

local KINDS = { "need", "greed", "disenchant", "transmog", "pass" }
local BUTTON_KEYS = {
    need       = "NeedButton",
    greed      = "GreedButton",
    disenchant = "DisenchantButton",
    transmog   = "TransmogButton",
    pass       = "PassButton",
}
local KIND_LABEL = {
    need       = NEED or "Need",
    greed      = GREED or "Greed",
    disenchant = ROLL_DISENCHANT or "Disenchant",
    transmog   = TRANSMOGRIFY or "Transmog",
    pass       = PASS or "Pass",
}

-- rolls[rollID] = { link = itemLink, players = { [name] = { kind = , class = } } }
local rolls = {}
-- "encounterID:lootListID" -> rollID, so a history drop keeps its popup once bound.
local dropToRoll = {}
local historySeen = false

local countTexts = {}   -- [button] = FontString
local hooked = {}       -- [button] = true

-------------------------------------------------------------------------------
--  Helpers
-------------------------------------------------------------------------------
local function ClassColor(classToken)
    if not classToken or IsSecret(classToken) then return 0.9, 0.9, 0.9 end
    if EllesmereUI and EllesmereUI.GetClassColor then
        local c = EllesmereUI.GetClassColor(classToken)
        if c then return c.r, c.g, c.b end
    end
    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken]
    if c then return c.r, c.g, c.b end
    return 0.9, 0.9, 0.9
end

local function ItemID(link)
    return link and tonumber(link:match("item:(%d+)"))
end

local function ShortName(name)
    if Ambiguate then return Ambiguate(name, "short") end
    return (name:gsub("%-.*$", ""))
end

-- Popups currently up, keyed by rollID.
local function ForEachRollFrame(fn)
    local seen = {}
    local c = GroupLootContainer
    local maxN = (c and type(c.maxIndex) == "number" and c.maxIndex) or 0
    maxN = math.max(maxN, NUM_GROUP_LOOT_FRAMES or 4)
    for i = 1, maxN do
        local f = _G["GroupLootFrame" .. i]
        if f and not seen[f] then seen[f] = true; fn(f) end
    end
    if c and type(c.rollFrames) == "table" then
        for _, f in pairs(c.rollFrames) do
            if not seen[f] then seen[f] = true; fn(f) end
        end
    end
end

local function GetButton(f, kind)
    local key = BUTTON_KEYS[kind]
    local b = f[key]
    if not b then
        local name = f:GetName()
        b = name and _G[name .. key]
    end
    return b
end

-- Walk up from a roll button to the popup that carries rollID.
local function RollIDFor(btn)
    local p = btn:GetParent()
    for _ = 1, 3 do
        if not p then return nil end
        if p.rollID then return p.rollID end
        p = p:GetParent()
    end
end

local function KindOf(btn)
    local f = btn:GetParent()
    for _ = 1, 3 do
        if not f then return nil end
        for kind, key in pairs(BUTTON_KEYS) do
            if f[key] == btn then return kind end
        end
        f = f:GetParent()
    end
end

local function EnsureRoll(rollID)
    local r = rolls[rollID]
    if not r then
        r = { players = {} }
        rolls[rollID] = r
    end
    if not r.link and GetLootRollItemLink then
        local link = GetLootRollItemLink(rollID)
        if link and not IsSecret(link) then r.link = link end
    end
    return r
end

-- Open rolls for this item, lowest rollID first; exact link beats item ID.
local function CandidateRolls(link)
    local exact, loose = {}, {}
    local id = ItemID(link)
    for rollID, r in pairs(rolls) do
        if r.link == link then
            exact[#exact + 1] = rollID
        elseif id and ItemID(r.link) == id then
            loose[#loose + 1] = rollID
        end
    end
    table.sort(exact)
    table.sort(loose)
    for i = 1, #loose do exact[#exact + 1] = loose[i] end
    return exact
end

-------------------------------------------------------------------------------
--  Display
-------------------------------------------------------------------------------
local function CountText(btn)
    local fs = countTexts[btn]
    if fs then return fs end
    fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightOutline")
    local path, _, flag = fs:GetFont()
    local EUI = EllesmereUI
    if EUI and EUI.GetFontPath then
        local ok, p = pcall(EUI.GetFontPath)
        if ok and p then path = p end
    end
    fs:SetFont(path or "Fonts\\FRIZQT__.TTF", 13, flag ~= "" and flag or "OUTLINE")
    fs:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 3, -1)
    fs:SetJustifyH("RIGHT")
    countTexts[btn] = fs
    return fs
end

local function Voters(rollID, kind)
    local list = {}
    local r = rollID and rolls[rollID]
    if not r then return list end
    for name, v in pairs(r.players) do
        if v.kind == kind then list[#list + 1] = { name = name, class = v.class } end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

local function OnButtonEnter(btn)
    if not ns.db.lootRollVotes then return end
    local kind = KindOf(btn)
    local voters = Voters(RollIDFor(btn), kind)
    if #voters == 0 then return end
    local tt = GameTooltip
    if tt:IsForbidden() then return end
    if not tt:IsOwned(btn) then tt:SetOwner(btn, "ANCHOR_RIGHT") end
    if tt:NumLines() == 0 then tt:SetText(KIND_LABEL[kind] or "") end
    tt:AddLine(" ")
    for i = 1, #voters do
        local r, g, b = ClassColor(voters[i].class)
        tt:AddLine(ShortName(voters[i].name), r, g, b)
    end
    tt:Show()
end

local function RefreshFrame(f)
    local rollID = f.rollID
    local active = ns.db.lootRollVotes and f:IsShown() and rollID and rolls[rollID]
    for i = 1, #KINDS do
        local kind = KINDS[i]
        local btn = GetButton(f, kind)
        if btn then
            if not hooked[btn] then
                hooked[btn] = true
                btn:HookScript("OnEnter", OnButtonEnter)
            end
            local n = active and #Voters(rollID, kind) or 0
            if n > 0 then
                local fs = CountText(btn)
                fs:SetText(n)
                fs:Show()
            elseif countTexts[btn] then
                countTexts[btn]:Hide()
            end
            -- Votes changed under the cursor: rebuild the open tooltip.
            if GameTooltip:IsOwned(btn) and btn:IsMouseOver() then
                local fn = btn:GetScript("OnEnter")
                if fn then
                    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT") -- clears the old lines
                    fn(btn)
                end
            end
        end
    end
end

local function RefreshAll()
    ForEachRollFrame(RefreshFrame)
end
ns.RefreshLootRollVotes = RefreshAll

local refreshQueued = false
local function QueueRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = false
        RefreshAll()
    end)
end

-------------------------------------------------------------------------------
--  Source 1: C_LootHistory
-------------------------------------------------------------------------------
local STATE_KIND = {}
do
    local S = Enum and Enum.EncounterLootDropRollState
    if S then
        if S.NeedMainSpec then STATE_KIND[S.NeedMainSpec] = "need" end
        if S.NeedOffSpec then STATE_KIND[S.NeedOffSpec] = "need" end
        if S.Transmog then STATE_KIND[S.Transmog] = "transmog" end
        if S.Greed then STATE_KIND[S.Greed] = "greed" end
        if S.Pass then STATE_KIND[S.Pass] = "pass" end
        if S.Disenchant then STATE_KIND[S.Disenchant] = "disenchant" end
    end
end

local function OnHistoryDrop(encounterID, lootListID)
    if not (C_LootHistory and C_LootHistory.GetSortedInfoForDrop) then return end
    local drop = C_LootHistory.GetSortedInfoForDrop(encounterID, lootListID)
    if not drop or not drop.rollInfos then return end
    local link = drop.itemHyperlink
    if not link or IsSecret(link) then return end

    local key = tostring(encounterID) .. ":" .. tostring(lootListID)
    local rollID = dropToRoll[key]
    if not (rollID and rolls[rollID]) then
        rollID = nil
        local bound = {}
        for _, rid in pairs(dropToRoll) do bound[rid] = true end
        local cands = CandidateRolls(link)
        for i = 1, #cands do
            if not bound[cands[i]] then rollID = cands[i]; break end
        end
        if not rollID then return end
        dropToRoll[key] = rollID
    end

    historySeen = true
    local players = {}
    for _, info in ipairs(drop.rollInfos) do
        local name = info.playerName
        local kind = STATE_KIND[info.state]
        if kind and name and not IsSecret(name) then
            players[name] = { kind = kind, class = info.playerClass }
        end
    end
    rolls[rollID].players = players
    QueueRefresh()
end

-------------------------------------------------------------------------------
--  Source 1b: legacy (Classic) C_LootHistory, the API ElvUI uses. It names the
--  rollID directly, so no link matching is needed; it can also fire before
--  the popup is up, which EnsureRoll simply pre-creates.
-------------------------------------------------------------------------------
local LEGACY_KIND = {
    [LOOT_ROLL_TYPE_PASS or 0]       = "pass",
    [LOOT_ROLL_TYPE_NEED or 1]       = "need",
    [LOOT_ROLL_TYPE_GREED or 2]      = "greed",
    [LOOT_ROLL_TYPE_DISENCHANT or 3] = "disenchant",
}
if LOOT_ROLL_TYPE_TRANSMOG then LEGACY_KIND[LOOT_ROLL_TYPE_TRANSMOG] = "transmog" end

local function OnLegacyRollChanged(itemIdx, playerIdx)
    local LH = C_LootHistory
    if not (LH and LH.GetItem and LH.GetPlayerInfo) then return end
    local rollID = LH.GetItem(itemIdx)
    local name, class, rollType = LH.GetPlayerInfo(itemIdx, playerIdx)
    local kind = rollType and LEGACY_KIND[rollType]
    if not (rollID and kind and name) or IsSecret(name) then return end
    historySeen = true
    EnsureRoll(rollID).players[name] = { kind = kind, class = class }
    QueueRefresh()
end

-------------------------------------------------------------------------------
--  Source 2: CHAT_MSG_LOOT lines
-------------------------------------------------------------------------------
-- Turns a GlobalStrings format ("%s has selected Need for: %s", or positional
-- "%1$s") into an anchored pattern plus the argument index of each capture.
local function ToPattern(fmt)
    local order, n = {}, 0
    local p = fmt:gsub("%%(%d?)%$?s", function(pos)
        n = n + 1
        order[n] = tonumber(pos) or n
        return "\001"
    end)
    p = p:gsub("[%(%)%.%+%-%*%?%[%]%^%$%%]", "%%%0")
    p = p:gsub("\001", "(.+)")
    return "^" .. p .. "$", order
end

-- Order matters: "auto" and "self" lines would also match the generic ones.
local CHAT_PATTERNS = {}
do
    local defs = {
        { "LOOT_ROLL_PASSED_AUTO",        "pass" },
        { "LOOT_ROLL_PASSED_AUTO_FEMALE", "pass" },
        { "LOOT_ROLL_NEED_SELF",          "need",       true },
        { "LOOT_ROLL_GREED_SELF",         "greed",      true },
        { "LOOT_ROLL_DISENCHANT_SELF",    "disenchant", true },
        { "LOOT_ROLL_TRANSMOG_SELF",      "transmog",   true },
        { "LOOT_ROLL_PASSED_SELF",        "pass",       true },
        { "LOOT_ROLL_NEED",               "need" },
        { "LOOT_ROLL_GREED",              "greed" },
        { "LOOT_ROLL_DISENCHANT",         "disenchant" },
        { "LOOT_ROLL_TRANSMOG",           "transmog" },
        { "LOOT_ROLL_PASSED",             "pass" },
    }
    for _, d in ipairs(defs) do
        local fmt = _G[d[1]]
        if type(fmt) == "string" then
            local pat, order = ToPattern(fmt)
            CHAT_PATTERNS[#CHAT_PATTERNS + 1] = { pat = pat, order = order, kind = d[2], self = d[3] }
        end
    end
end

local function OnLootChat(msg)
    if historySeen or not msg or IsSecret(msg) or not next(rolls) then return end
    for _, cp in ipairs(CHAT_PATTERNS) do
        local caps = { msg:match(cp.pat) }
        if caps[1] then
            local args = {}
            for i = 1, #caps do args[cp.order[i]] = caps[i] end
            local name, link
            if cp.self then
                name, link = UnitName("player"), args[1]
            else
                name, link = args[1], args[2]
            end
            if not (name and link) then return end
            local _, class = UnitClass(name)
            if cp.self then _, class = UnitClass("player") end
            -- Same item dropped twice: the first open roll this player hasn't voted on.
            local cands = CandidateRolls(link)
            for i = 1, #cands do
                local r = rolls[cands[i]]
                if not r.players[name] then
                    r.players[name] = { kind = cp.kind, class = class }
                    QueueRefresh()
                    return
                end
            end
            return
        end
    end
end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("START_LOOT_ROLL")
ev:RegisterEvent("CANCEL_LOOT_ROLL")
ev:RegisterEvent("CHAT_MSG_LOOT")
pcall(ev.RegisterEvent, ev, "LOOT_HISTORY_UPDATE_DROP")
pcall(ev.RegisterEvent, ev, "LOOT_HISTORY_ROLL_CHANGED")
ev:SetScript("OnEvent", function(_, event, ...)
    if event == "START_LOOT_ROLL" then
        -- Not wiped: legacy history may already have votes for this rollID.
        local rollID = ...
        if rollID then EnsureRoll(rollID) end
        QueueRefresh()
    elseif event == "LOOT_HISTORY_ROLL_CHANGED" then
        OnLegacyRollChanged(...)
    elseif event == "CANCEL_LOOT_ROLL" then
        local rollID = ...
        if rollID then
            rolls[rollID] = nil
            for key, rid in pairs(dropToRoll) do
                if rid == rollID then dropToRoll[key] = nil end
            end
        end
        QueueRefresh()
    elseif event == "LOOT_HISTORY_UPDATE_DROP" then
        OnHistoryDrop(...)
    elseif event == "CHAT_MSG_LOOT" then
        OnLootChat(...)
    end
end)
