-------------------------------------------------------------------------------
--  EllesmereUI character sheet: outline on the text EllesmereUI's Forever skin
--  draws beside each item slot (the item's stats, a weapon's DPS and the
--  enchant name). EllesmereUI only outlines the enchant in its Colored Text
--  mode and keeps the rest flat.
--
--  How: that text lives on one unnamed overlay frame parented to
--  PaperDollItemsFrame, holding only font strings, built the first time the
--  sheet is skinned/shown. We find it, then hook SetFont on each of its font
--  strings so every font EllesmereUI applies (options changes, enchant mode,
--  per-slot repaints) gets our outline flag added on top. Path and size stay
--  EllesmereUI's. Nothing runs without EllesmereUI or while the option is off
--  (the hook passes the font through untouched).
-------------------------------------------------------------------------------
local _, ns = ...

local MIN_FONTSTRINGS = 20 -- the overlay holds 2-3 font strings per slot

local module = ns.RegisterModule({
    key = "euiCharSheetOutline",
    name = "EllesmereUI Character Sheet",
    defaults = {
        euiCharSheetOutline = "OUTLINE",
    },
    options = {
        { type = "dropdown", key = "euiCharSheetOutline", label = "Slot text outline",
          tooltip = "Outline on the text EllesmereUI shows beside each item slot of the character sheet "
              .. "(item stats, weapon DPS, enchant). None leaves EllesmereUI's own font as is.",
          choices = { { "NONE", "None" }, { "OUTLINE", "Outline" }, { "THICKOUTLINE", "Thick outline" } } },
    },
})

local hooked = {}   -- [fontString] = true
local original = {} -- [fontString] = flags EllesmereUI last asked for
local applying = false

local function WantedFlag()
    local v = ns.db.euiCharSheetOutline
    if v == "OUTLINE" or v == "THICKOUTLINE" then return v end
    return nil
end

-- EllesmereUI's flags plus our outline: any OUTLINE/THICKOUTLINE of theirs is
-- replaced, other tokens (SLUG, MONOCHROME) are kept.
local function MergeFlags(flags, outline)
    local out = {}
    for token in tostring(flags or ""):gmatch("[^,%s]+") do
        local up = token:upper()
        if up ~= "OUTLINE" and up ~= "THICKOUTLINE" and up ~= "THICK" then
            out[#out + 1] = token
        end
    end
    if outline then table.insert(out, 1, outline) end
    return table.concat(out, ", ")
end

local function Apply(fs)
    local path, size = fs:GetFont()
    if not path then return end
    local base = original[fs] or ""
    local outline = WantedFlag()
    local flags = outline and MergeFlags(base, outline) or base
    applying = true
    fs:SetFont(path, size, flags)
    applying = false
end

local function OnSetFont(fs, _, _, flags)
    if applying then return end
    original[fs] = flags or ""
    if WantedFlag() then Apply(fs) end
end

-- The overlay: an unnamed child of PaperDollItemsFrame with only font strings.
local function FindOverlay()
    local host = _G.PaperDollItemsFrame
    if not host then return nil end
    for _, child in ipairs({ host:GetChildren() }) do
        if not child:GetName() and child:GetNumRegions() >= MIN_FONTSTRINGS then
            local allText = true
            for _, region in ipairs({ child:GetRegions() }) do
                if region:GetObjectType() ~= "FontString" then allText = false; break end
            end
            if allText then return child end
        end
    end
end

local overlay
local function Attach()
    if overlay then return true end
    overlay = FindOverlay()
    if not overlay then return false end
    for _, fs in ipairs({ overlay:GetRegions() }) do
        if not hooked[fs] then
            hooked[fs] = true
            local _, _, flags = fs:GetFont()
            original[fs] = flags or ""
            hooksecurefunc(fs, "SetFont", OnSetFont)
            Apply(fs)
        end
    end
    return true
end

local function TryAttach()
    if overlay or not ns.db.euiCharSheetOutline or ns.db.euiCharSheetOutline == "NONE" then return end
    if not Attach() then
        -- EllesmereUI may build the overlay in its own OnShow hook, which can
        -- run after ours: look again next frame.
        C_Timer.After(0, Attach)
    end
end

-- Option changed: restyle what we already hold, or attach now if the sheet
-- has been built since (otherwise the next sheet open does it).
function module.Refresh()
    if not overlay then TryAttach(); return end
    for fs in pairs(hooked) do Apply(fs) end
end

module.OnLoad = function()
    if not C_AddOns.IsAddOnLoaded("EllesmereUIBlizzardSkin") and not C_AddOns.IsAddOnLoaded("EllesmereUI") then
        return
    end
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")
        TryAttach()
        if _G.CharacterFrame then _G.CharacterFrame:HookScript("OnShow", TryAttach) end
        if _G.PaperDollItemsFrame then _G.PaperDollItemsFrame:HookScript("OnShow", TryAttach) end
    end)
end
