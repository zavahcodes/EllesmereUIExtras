if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  Options: a page in Blizzard's Settings panel (Esc > Options > AddOns >
--  EllesmereUI Extras), built from the registered modules. EllesmereUI's own
--  panel only accepts its whitelisted suite folders (EllesmereUI:RegisterModule),
--  so Extras lives here instead. One section per module name, in .toc order.
--  Settings write straight into EllesmereUIExtrasDB.
-------------------------------------------------------------------------------
local _, ns = ...

local CATEGORY_NAME = "EllesmereUI Extras"

function ns.InitOptions()
    if ns.settingsCategory or not (Settings and Settings.RegisterVerticalLayoutCategory) then return end
    local category, layout = Settings.RegisterVerticalLayoutCategory(CATEGORY_NAME)
    ns.settingsCategory = category

    local function Register(key, varType, label)
        return Settings.RegisterAddOnSetting(category, "EUIX_" .. key, key, ns.db,
            varType, label, ns.DEFAULTS[key])
    end

    local builders = {
        checkbox = function(opt)
            local setting = Register(opt.key, Settings.VarType.Boolean, opt.label)
            Settings.CreateCheckbox(category, setting, opt.tooltip)
            return setting
        end,
        slider = function(opt)
            local setting = Register(opt.key, Settings.VarType.Number, opt.label)
            local options = Settings.CreateSliderOptions(opt.min, opt.max, opt.step)
            options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
            Settings.CreateSlider(category, setting, options, opt.tooltip)
            return setting
        end,
        dropdown = function(opt)
            local setting = Register(opt.key, Settings.VarType.String, opt.label)
            local function GetOptions()
                local container = Settings.CreateControlTextContainer()
                for _, choice in ipairs(opt.choices) do container:Add(choice[1], choice[2]) end
                return container:GetData()
            end
            Settings.CreateDropdown(category, setting, GetOptions, opt.tooltip)
            return setting
        end,
    }

    local lastHeader
    for _, module in ipairs(ns.modules) do
        if module.options and #module.options > 0 then
            if module.name and module.name ~= lastHeader
                and layout and CreateSettingsListSectionHeaderInitializer then
                layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(module.name))
                lastHeader = module.name
            end
            for _, opt in ipairs(module.options) do
                local build = builders[opt.type]
                assert(build, "EllesmereUIExtras: unknown option type " .. tostring(opt.type))
                local setting = build(opt)
                if module.Refresh then
                    setting:SetValueChangedCallback(function() ns.SafeCall(module.Refresh, ns.db) end)
                end
            end
        end
    end

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
