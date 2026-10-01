if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  Options: a page in Blizzard's Settings panel (Esc > Options > AddOns >
--  EllesmereUI Extras). EllesmereUI's own panel only accepts its whitelisted
--  suite folders (EllesmereUI:RegisterModule), so Extras lives here instead.
--  Settings write straight into EllesmereUIExtrasDB and features read ns.db on
--  every call, so every toggle applies live.
-------------------------------------------------------------------------------
local _, ns = ...

local CATEGORY_NAME = "EllesmereUI Extras"

function ns.InitOptions()
    if ns.settingsCategory or not (Settings and Settings.RegisterVerticalLayoutCategory) then return end
    local DEFAULTS = ns.DEFAULTS
    local category, layout = Settings.RegisterVerticalLayoutCategory(CATEGORY_NAME)
    ns.settingsCategory = category

    local function Register(key, varType, label)
        return Settings.RegisterAddOnSetting(category, "EUIX_" .. key, key, ns.db,
            varType, label, DEFAULTS[key])
    end

    local function AddCheckbox(key, label, tooltip, onChange)
        local setting = Register(key, Settings.VarType.Boolean, label)
        Settings.CreateCheckbox(category, setting, tooltip)
        if onChange then setting:SetValueChangedCallback(onChange) end
        return setting
    end

    local function AddSlider(key, label, tooltip, minV, maxV, step, onChange)
        local setting = Register(key, Settings.VarType.Number, label)
        local options = Settings.CreateSliderOptions(minV, maxV, step)
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
        Settings.CreateSlider(category, setting, options, tooltip)
        if onChange then setting:SetValueChangedCallback(onChange) end
        return setting
    end

    local function AddDropdown(key, label, tooltip, choices, onChange)
        local setting = Register(key, Settings.VarType.String, label)
        local function GetOptions()
            local container = Settings.CreateControlTextContainer()
            for i = 1, #choices do container:Add(choices[i][1], choices[i][2]) end
            return container:GetData()
        end
        Settings.CreateDropdown(category, setting, GetOptions, tooltip)
        if onChange then setting:SetValueChangedCallback(onChange) end
        return setting
    end

    local function RefreshHealth()
        if ns.RefreshTooltipHealth then ns.RefreshTooltipHealth() end
    end

    if layout and CreateSettingsListSectionHeaderInitializer then
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Tooltip"))
    end

    AddCheckbox("tooltipHealthBar", "Show health bar",
        "Shows a health bar below unit tooltips (players and NPCs), colored by class or reaction.",
        RefreshHealth)
    AddCheckbox("tooltipHealthText", "Show health percentage",
        "Shows the health percentage on top of the tooltip health bar.",
        RefreshHealth)
    AddSlider("tooltipHealthHeight", "Health bar height",
        "Height of the tooltip health bar, in pixels.",
        4, 16, 1, RefreshHealth)
    AddSlider("tooltipHealthTextSize", "Health percentage size",
        "Font size of the health percentage on the tooltip health bar.",
        6, 18, 1, RefreshHealth)
    AddCheckbox("tooltipTarget", "Show target of target",
        "Adds a Target: line with who the hovered player or NPC is targeting (>> YOU << in red when it's you). "
        .. "Skipped automatically when EllesmereUI's own \"Show Unit Target\" option is enabled.")

    if layout and CreateSettingsListSectionHeaderInitializer then
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Unit Frames"))
    end

    AddCheckbox("playerHidePower", "Hide player power bar",
        "WoW Forever, Blizzard Style and Classic WoW UI only: hides the player frame's power bar "
        .. "and stretches the health bar into its space.",
        function() if ns.RefreshPlayerPower then ns.RefreshPlayerPower() end end)
    AddSlider("playerHidePowerExtra", "Health bar extra height",
        "Extra pixels added below the stretched player health bar so it reaches the frame's bottom edge.",
        0, 8, 1, function() if ns.RefreshPlayerPower then ns.RefreshPlayerPower() end end)

    if layout and CreateSettingsListSectionHeaderInitializer then
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Chat Bubbles"))
    end

    local function RefreshBubbles()
        if ns.RefreshChatBubbles then ns.RefreshChatBubbles() end
    end

    AddCheckbox("chatBubbleCustom", "Customize chat bubble font",
        "Applies the size and outline below to Blizzard's chat bubbles (also inside instances). "
        .. "Off restores Blizzard's default font.",
        RefreshBubbles)
    AddSlider("chatBubbleFontSize", "Chat bubble font size",
        "Font size of the text inside chat bubbles.",
        8, 24, 1, RefreshBubbles)
    AddDropdown("chatBubbleOutline", "Chat bubble outline",
        "Outline drawn around the chat bubble text.",
        { { "NONE", "None" }, { "OUTLINE", "Outline" }, { "THICKOUTLINE", "Thick outline" } },
        RefreshBubbles)

    if layout and CreateSettingsListSectionHeaderInitializer then
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Loot Rolls"))
    end

    AddCheckbox("lootRollVotes", "Show roll votes",
        "On loot roll popups, shows how many group members picked Need, Greed, Disenchant, Transmog or Pass "
        .. "on each button. Hovering a button lists who picked it, in class colors.",
        function() if ns.RefreshLootRollVotes then ns.RefreshLootRollVotes() end end)

    Settings.RegisterAddOnCategory(category)
end

SLASH_EUIEXTRAS1 = "/euix"
SLASH_EUIEXTRAS2 = "/ellesmereuiextras"
SlashCmdList.EUIEXTRAS = function()
    local category = ns.settingsCategory
    if category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(category:GetID())
    end
end
