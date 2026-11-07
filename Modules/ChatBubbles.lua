if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  Chat bubbles: font size and outline for Blizzard's own chat bubbles. Works
--  on the shared ChatBubbleFont object rather than the bubble frames, so it
--  also applies inside instances (where the frames are forbidden) and restyles
--  bubbles already on screen. The typeface stays Blizzard's. EllesmereUIChat's
--  own bubbles are not touched (they carry their own size setting).
-------------------------------------------------------------------------------
local _, ns = ...

local FALLBACK_FONT = "Fonts\\FRIZQT__.TTF"

local module = ns.RegisterModule({
    key = "chatBubbles",
    name = "Chat Bubbles",
    defaults = {
        chatBubbleCustom   = false,
        chatBubbleFontSize = 13,
        chatBubbleOutline  = "OUTLINE",
    },
    options = {
        { type = "checkbox", key = "chatBubbleCustom", label = "Customize chat bubble font",
          tooltip = "Applies the size and outline below to Blizzard's chat bubbles (also inside instances). "
              .. "Off restores Blizzard's default font." },
        { type = "slider", key = "chatBubbleFontSize", label = "Chat bubble font size",
          tooltip = "Font size of the text inside chat bubbles.", min = 8, max = 24, step = 1 },
        { type = "dropdown", key = "chatBubbleOutline", label = "Chat bubble outline",
          tooltip = "Outline drawn around the chat bubble text.",
          choices = { { "NONE", "None" }, { "OUTLINE", "Outline" }, { "THICKOUTLINE", "Thick outline" } } },
    },
})

local fontObj = ChatBubbleFont
-- Blizzard's original font, captured before we ever change it, so turning the
-- feature off restores it without a reload.
local origPath, origSize, origFlags
local applied = false

if fontObj then
    origPath, origSize, origFlags = fontObj:GetFont()
end

local function OutlineFlag(v)
    if v == "OUTLINE" or v == "THICKOUTLINE" then return v end
    return ""
end

function module.Refresh()
    if not fontObj then return end
    local db = ns.db
    if db.chatBubbleCustom then
        local path = origPath or FALLBACK_FONT
        local size = db.chatBubbleFontSize or ns.DEFAULTS.chatBubbleFontSize
        local flag = OutlineFlag(db.chatBubbleOutline)
        -- SetFont answers false for a path that no longer resolves and leaves the
        -- object with no font at all, so retry with the stock one.
        if not fontObj:SetFont(path, size, flag) then
            fontObj:SetFont(FALLBACK_FONT, size, flag)
        end
        applied = true
    elseif applied then
        if origPath then
            fontObj:SetFont(origPath, origSize, origFlags or "")
        end
        applied = false
    end
end

-- Re-applied on every load screen in case something resets the font object.
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function()
    if ns.db.chatBubbleCustom then module.Refresh() end
end)

module.OnLoad = module.Refresh
