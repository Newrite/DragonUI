--[[
================================================================================
DragonUI Options Panel - Auras Tab
================================================================================
Weapon enchant separation options.
================================================================================
]]

local addon = DragonUI
if not addon then return end

local floor = math.floor
local LO = addon.LO
local C = addon.PanelControls
local Panel = addon.OptionsPanel

local function RefreshTargetFocusAuraTimers()
    if addon.RefreshAuraCooldownTextSystem then
        addon.RefreshAuraCooldownTextSystem()
    end
end

local function RefreshPlayerAuraSpacing()
    if addon.BuffFrameModule and addon.BuffFrameModule.RefreshAuraSpacing then
        addon.BuffFrameModule:RefreshAuraSpacing()
        return
    end

    if BuffFrame_UpdateAllBuffAnchors then
        BuffFrame_UpdateAllBuffAnchors()
    end
    if addon.BuffFrameModule then
        addon.BuffFrameModule:UpdatePosition()
    end
end

local AURA_ANCHORS = {
    TOP = LO["Top"],
    BOTTOM = LO["Bottom"],
    LEFT = LO["Left"],
    RIGHT = LO["Right"],
    CENTER = LO["Center"],
    TOPLEFT = LO["Top Left"],
    TOPRIGHT = LO["Top Right"],
    BOTTOMLEFT = LO["Bottom Left"],
    BOTTOMRIGHT = LO["Bottom Right"],
}

local AURA_FONTS = {
    actionbar = LO["Actionbar Font"],
    primary = LO["Primary Font"],
    narrow = LO["Narrow Font"],
    arial = LO["Arial Font"],
    system = LO["System Font"],
}

local function GetAuraCooldownConfig()
    local modules = addon.db and addon.db.profile and addon.db.profile.modules
    modules = modules or {}
    modules.auracooldowns = modules.auracooldowns or {}
    modules.auracooldowns.target = modules.auracooldowns.target or {}
    modules.auracooldowns.focus = modules.auracooldowns.focus or {}
    modules.auracooldowns.buffs = modules.auracooldowns.buffs or {}
    modules.auracooldowns.debuffs = modules.auracooldowns.debuffs or {}

    if modules.auracooldowns.target.max_duration_minutes == nil and type(modules.auracooldowns.target.max_duration) == "number" then
        modules.auracooldowns.target.max_duration_minutes = floor((modules.auracooldowns.target.max_duration / 60) + 0.5)
    end
    if modules.auracooldowns.focus.max_duration_minutes == nil and type(modules.auracooldowns.focus.max_duration) == "number" then
        modules.auracooldowns.focus.max_duration_minutes = floor((modules.auracooldowns.focus.max_duration / 60) + 0.5)
    end

    if modules.auracooldowns.target.enabled == nil then
        local timerUnits = modules.auracooldowns.timer_units
        modules.auracooldowns.target.enabled = modules.auracooldowns.timers_enabled == true and (timerUnits == "target" or timerUnits == "both") or false
    end
    if modules.auracooldowns.focus.enabled == nil then
        local timerUnits = modules.auracooldowns.timer_units
        modules.auracooldowns.focus.enabled = modules.auracooldowns.timers_enabled == true and (timerUnits == "focus" or timerUnits == "both") or false
    end

    modules.auracooldowns.timers_enabled = modules.auracooldowns.target.enabled == true or modules.auracooldowns.focus.enabled == true
    modules.auracooldowns.enabled = modules.auracooldowns.icons_enabled == true or modules.auracooldowns.timers_enabled == true

    return modules.auracooldowns
end

local function IsTimerCustomizationEnabled()
    return GetAuraCooldownConfig().timers_enabled == true
end

local function IsIconCustomizationEnabled()
    return GetAuraCooldownConfig().icons_enabled == true
end

local function SyncAuraModuleEnabled(cfg)
    cfg.enabled = cfg.icons_enabled == true or cfg.timers_enabled == true
end

local function SetAuraFeatureEnabled(featureKey, value)
    local cfg = GetAuraCooldownConfig()
    cfg[featureKey] = value and true or false
    SyncAuraModuleEnabled(cfg)
end

local function SyncAuraTimerState(cfg)
    cfg.timers_enabled = cfg.target.enabled == true or cfg.focus.enabled == true
    SyncAuraModuleEnabled(cfg)
end

local function SetAuraUnitEnabled(unitKey, value)
    local cfg = GetAuraCooldownConfig()
    cfg[unitKey].enabled = value and true or false
    SyncAuraTimerState(cfg)
end

local function IsTargetTimerSettingsDisabled()
    return not IsTimerCustomizationEnabled() or GetAuraCooldownConfig().target.enabled ~= true
end

local function IsFocusTimerSettingsDisabled()
    return not IsTimerCustomizationEnabled() or GetAuraCooldownConfig().focus.enabled ~= true
end

local function GetAuraCooldownDefaults()
    local defaults = addon.defaults
        and addon.defaults.profile
        and addon.defaults.profile.modules
        and addon.defaults.profile.modules.auracooldowns
    return defaults
end

local function ResetAuraTimerSettings()
    local defaults = GetAuraCooldownDefaults()
    if not defaults then return end

    local cfg = GetAuraCooldownConfig()

    cfg.duration_anchor = defaults.duration_anchor
    cfg.duration_offset_x = defaults.duration_offset_x
    cfg.duration_offset_y = defaults.duration_offset_y
    cfg.duration_font = defaults.duration_font

    cfg.target.enabled = defaults.target and defaults.target.enabled == true or false
    cfg.target.min_duration = defaults.target and defaults.target.min_duration or 0
    cfg.target.max_duration_minutes = defaults.target and defaults.target.max_duration_minutes or 0
    cfg.target.font_size = defaults.target and defaults.target.font_size or 11

    cfg.focus.enabled = defaults.focus and defaults.focus.enabled == true or false
    cfg.focus.min_duration = defaults.focus and defaults.focus.min_duration or 0
    cfg.focus.max_duration_minutes = defaults.focus and defaults.focus.max_duration_minutes or 0
    cfg.focus.font_size = defaults.focus and defaults.focus.font_size or 11

    SyncAuraTimerState(cfg)
end

local function ResetAuraIconSettings()
    local defaults = GetAuraCooldownDefaults()
    if not defaults then return end

    local cfg = GetAuraCooldownConfig()

    cfg.icons_enabled = defaults.icons_enabled == true
    cfg.stack_anchor = defaults.stack_anchor
    cfg.stack_offset_x = defaults.stack_offset_x
    cfg.stack_offset_y = defaults.stack_offset_y
    cfg.count_font = defaults.count_font
    cfg.buffs = addon.DeepCopy(defaults.buffs or {}, {})
    cfg.debuffs = addon.DeepCopy(defaults.debuffs or {}, {})

    SyncAuraModuleEnabled(cfg)
end

-- ============================================================================
-- AURAS TAB BUILDER
-- ============================================================================

local function GetAuraBordersField(field)
    local m = addon.db.profile.modules
    return m and m.auraborders and m.auraborders[field]
end

local function IsAuraBordersEnabled()
    return GetAuraBordersField("enabled") == true
end

local function RefreshAuraBorders()
    if addon.RefreshAuraBordersSystem then
        addon.RefreshAuraBordersSystem()
    end
end

local selectedStandardAuraUnit = "target"
local selectedAuraBarUnit = "target"

local AURA_ICON_UNITS = {
    buffframe = LO["Blizzard Aura Frame"],
    player = LO["Player"],
    target = LO["Target"],
    focus = LO["Focus"],
    pet = LO["Pet"],
    tot = LO["Target of Target"],
    fot = LO["Target of Focus"],
    party = LO["Party"],
    boss = LO["Boss"],
    arena = LO["Arena"],
}

local AURA_BAR_UNITS = {
    player = LO["Player"],
    target = LO["Target"],
    focus = LO["Focus"],
}

local AURA_CASTER_FILTERS = {
    all = LO["All Casters"],
    mine = LO["Cast by Me"],
    others = LO["Cast by Others"],
}

local AURA_OWNERSHIP_STYLES = {
    normal = LO["Original Colors"],
    desaturate = LO["Desaturate Other Casters"],
}

local AURA_SORT_METHODS = {
    index = LO["Blizzard Order"],
    mine_first = LO["Mine First"],
    time_asc = LO["Soonest Expiring First"],
    time_desc = LO["Latest Expiring First"],
    duration_asc = LO["Shortest Duration First"],
    duration_desc = LO["Longest Duration First"],
    name = LO["Name"],
}

local AURA_BAR_GROWTH = {
    DOWN = LO["Down"],
    UP = LO["Up"],
}

local AURA_BAR_ICON_SIDE = {
    LEFT = LO["Left"],
    RIGHT = LO["Right"],
}

local AURA_BAR_TEXT_OUTLINES = {
    NONE = LO["No Outline"],
    OUTLINE = LO["Outline"],
    THICKOUTLINE = LO["Thick Outline"],
}

local AURA_BAR_ICON_BORDER_MODES = {
    aura = LO["Aura Color"],
    border = LO["Bar Border Color"],
    custom = LO["Custom Color"],
}

local AURA_ICON_GROWTH_X = {
    RIGHT = LO["Right"],
    LEFT = LO["Left"],
}

local AURA_ICON_GROWTH_Y = {
    DOWN = LO["Down"],
    UP = LO["Up"],
}

local AURA_BAR_WIDGET_KEYS = {
    player = "playerAuraBars",
    target = "targetAuraBars",
    focus = "focusAuraBars",
}

local function GetAuraMediaChoices(mediaType, includeNone, includeSame)
    local choices = addon.GetAuraCustomizationMediaChoices
        and addon.GetAuraCustomizationMediaChoices(mediaType) or {}
    if includeNone then choices.__none__ = LO["None"] end
    if includeSame then choices.__same__ = LO["Same as Bar Texture"] end
    return choices
end

local function RebuildAurasTabPreservingScroll()
    local oldScroll = Panel and Panel.scrollWidget
    local scrollValue = oldScroll and oldScroll.scrollbar and oldScroll.scrollbar:GetValue() or 0
    Panel:SelectTab("auras")

    local rebuiltScroll = Panel.scrollWidget
    local function RestoreScroll()
        if Panel.currentTab ~= "auras" or Panel.scrollWidget ~= rebuiltScroll or not rebuiltScroll then return end
        if rebuiltScroll.SetScroll then rebuiltScroll:SetScroll(scrollValue) end
        if rebuiltScroll.scrollbar then rebuiltScroll.scrollbar:SetValue(scrollValue) end
    end
    RestoreScroll()
    if addon.After then addon:After(0, RestoreScroll) end
end

local function CopyDefaults(source)
    if addon.DeepCopy then
        return addon.DeepCopy(source or {}, {})
    end

    local copy = {}
    for key, value in pairs(source or {}) do
        copy[key] = type(value) == "table" and CopyDefaults(value) or value
    end
    return copy
end

local function GetAuraCustomizationConfig()
    local profile = addon.db and addon.db.profile
    if not profile then return nil end

    profile.modules = profile.modules or {}
    local cfg = profile.modules.aura_customization
    if not cfg then
        local defaults = addon.defaults and addon.defaults.profile and addon.defaults.profile.modules
            and addon.defaults.profile.modules.aura_customization
        cfg = CopyDefaults(defaults)
        profile.modules.aura_customization = cfg
    end

    cfg.enabled = cfg.enabled ~= false
    cfg.icons = cfg.icons or {}
    cfg.bars = cfg.bars or {}
    return cfg
end

local function GetAuraDisplayConfig(displayType, unitKey)
    local cfg = GetAuraCustomizationConfig()
    if not cfg then return {} end

    local displays = cfg[displayType]
    if not displays[unitKey] then
        local defaults = addon.defaults and addon.defaults.profile and addon.defaults.profile.modules
            and addon.defaults.profile.modules.aura_customization
        local displayDefaults = defaults and defaults[displayType] and defaults[displayType][unitKey]
        displays[unitKey] = CopyDefaults(displayDefaults)
    end
    return displays[unitKey]
end

local function RefreshAuraCustomization()
    if addon.RefreshAuraCustomizationSystem then
        addon.RefreshAuraCustomizationSystem()
    end
end

local function ResetAuraDisplayConfig(displayType, unitKey)
    local cfg = GetAuraCustomizationConfig()
    local defaults = addon.defaults and addon.defaults.profile and addon.defaults.profile.modules
        and addon.defaults.profile.modules.aura_customization
    if not cfg or not defaults or not defaults[displayType] or not defaults[displayType][unitKey] then return end

    cfg[displayType][unitKey] = CopyDefaults(defaults[displayType][unitKey])
    RefreshAuraCustomization()
end

local function ResetAuraBarPosition(unitKey)
    local widgetKey = AURA_BAR_WIDGET_KEYS[unitKey]
    local profile = addon.db and addon.db.profile
    local defaults = addon.defaults and addon.defaults.profile and addon.defaults.profile.widgets
    if not widgetKey or not profile or not defaults or not defaults[widgetKey] then return end

    profile.widgets = profile.widgets or {}
    profile.widgets[widgetKey] = CopyDefaults(defaults[widgetKey])
    local state = addon.AuraCustomizationModule and addon.AuraCustomizationModule.barFrames
        and addon.AuraCustomizationModule.barFrames[unitKey]
    if state and state.anchor and addon.ApplyWidgetPositionFromDB then
        addon.ApplyWidgetPositionFromDB(widgetKey, state.anchor)
    end
end

local function AddAuraFilterControls(section, getConfig, isDisabled)
    C:AddHeading(section, LO["Visibility and Ownership"])

    C:AddToggle(section, {
        label = LO["Show Buffs"],
        getFunc = function() return getConfig().show_buffs ~= false end,
        setFunc = function(value) getConfig().show_buffs = value and true or false end,
        callback = RefreshAuraCustomization,
        disabled = isDisabled,
    })

    C:AddToggle(section, {
        label = LO["Show Debuffs"],
        getFunc = function() return getConfig().show_debuffs ~= false end,
        setFunc = function(value) getConfig().show_debuffs = value and true or false end,
        callback = RefreshAuraCustomization,
        disabled = isDisabled,
    })

    C:AddDropdown(section, {
        label = LO["Caster Filter"],
        desc = LO["Choose whether to show all auras, only auras applied by you, or only auras applied by others."],
        values = AURA_CASTER_FILTERS,
        getFunc = function() return getConfig().caster or "all" end,
        setFunc = function(value) getConfig().caster = value end,
        callback = RefreshAuraCustomization,
        disabled = isDisabled,
        width = 240,
    })

    C:AddDropdown(section, {
        label = LO["Other Casters' Auras"],
        desc = LO["Keep other casters' auras in their original colors or render them desaturated."],
        values = AURA_OWNERSHIP_STYLES,
        getFunc = function() return getConfig().other_style or "normal" end,
        setFunc = function(value) getConfig().other_style = value end,
        callback = RefreshAuraCustomization,
        disabled = isDisabled,
        width = 240,
    })

    C:AddColorPicker(section, {
        label = LO["Other Casters' Tint"],
        desc = LO["Tint used for desaturated auras applied by other casters."],
        getFunc = function()
            local color = getConfig().other_color
            return color and color.r or 0.55, color and color.g or 0.55, color and color.b or 0.55
        end,
        setFunc = function(r, g, b)
            getConfig().other_color = { r = r, g = g, b = b }
        end,
        callback = RefreshAuraCustomization,
        disabled = isDisabled,
        hasAlpha = false,
    })

    C:AddHeading(section, LO["Sorting and Duration"])

    C:AddDropdown(section, {
        label = LO["Aura Sort Method"],
        values = AURA_SORT_METHODS,
        getFunc = function() return getConfig().sort or "index" end,
        setFunc = function(value) getConfig().sort = value end,
        callback = RefreshAuraCustomization,
        disabled = isDisabled,
        width = 240,
    })

    C:AddToggle(section, {
        label = LO["Permanent Auras Last"],
        desc = LO["Place auras without a duration after timed auras."],
        getFunc = function() return getConfig().no_duration_last ~= false end,
        setFunc = function(value) getConfig().no_duration_last = value and true or false end,
        callback = RefreshAuraCustomization,
        disabled = isDisabled,
    })

    C:AddToggle(section, {
        label = LO["Include Permanent Auras"],
        desc = LO["Allow auras without a finite duration to pass this display's filters."],
        getFunc = function() return getConfig().include_no_duration ~= false end,
        setFunc = function(value) getConfig().include_no_duration = value and true or false end,
        callback = RefreshAuraCustomization,
        disabled = isDisabled,
    })

    C:AddSlider(section, {
        label = LO["Minimum Aura Duration (Seconds)"],
        desc = LO["Hide timed auras whose total duration is shorter than this value. Use 0 to disable this limit."],
        min = 0, max = 120, step = 1,
        width = 240,
        getFunc = function() return tonumber(getConfig().min_duration) or 0 end,
        setFunc = function(value) getConfig().min_duration = value end,
        callback = RefreshAuraCustomization,
        disabled = isDisabled,
    })

    C:AddSlider(section, {
        label = LO["Maximum Aura Duration (Minutes)"],
        desc = LO["Hide timed auras whose total duration is longer than this value. Use 0 to disable this limit."],
        min = 0, max = 180, step = 1,
        width = 240,
        getFunc = function() return tonumber(getConfig().max_duration_minutes) or 0 end,
        setFunc = function(value) getConfig().max_duration_minutes = value end,
        callback = RefreshAuraCustomization,
        disabled = isDisabled,
    })

    C:AddHeading(section, LO["Spell Filters"])
    C:AddDescription(section,
        LO["Enter exact spell names or spell IDs separated by commas, semicolons, or new lines. Blacklist entries always win; a non-empty whitelist hides every aura not listed."])

    C:AddEditBox(section, {
        label = LO["Aura Whitelist"],
        getFunc = function() return getConfig().whitelist or "" end,
        setFunc = function(value) getConfig().whitelist = value or "" end,
        callback = RefreshAuraCustomization,
        disabled = isDisabled,
        width = 460,
    })

    C:AddEditBox(section, {
        label = LO["Aura Blacklist"],
        getFunc = function() return getConfig().blacklist or "" end,
        setFunc = function(value) getConfig().blacklist = value or "" end,
        callback = RefreshAuraCustomization,
        disabled = isDisabled,
        width = 460,
    })
end

local function BuildAurasTab(scroll)
    -- ====================================================================
    -- AURA BORDERS
    -- ====================================================================
    local borderSection = C:AddSection(scroll, LO["Aura Borders"])

    C:AddToggle(borderSection, {
        label = LO["Enable Aura Borders"],
        desc = LO["Show modern borders around buff and debuff icons."],
        getFunc = function() return IsAuraBordersEnabled() end,
        setFunc = function(val)
            C:EnsureModuleTable("auraborders").enabled = val
        end,
        callback = function()
            RefreshAuraBorders()
            -- Rebuild so the style dropdown / color enable-state refresh at once.
            RebuildAurasTabPreservingScroll()
        end,
        requiresReload = false,
    })

    C:AddDropdown(borderSection, {
        label = LO["Border Style"],
        values = {
            [1] = LO["Rounded"],
            [2] = LO["Square"],
        },
        getFunc = function()
            return GetAuraBordersField("custom_border") and 1 or 2
        end,
        setFunc = function(val)
            C:EnsureModuleTable("auraborders").custom_border = (val == 1)
        end,
        callback = RefreshAuraBorders,
        disabled = function() return not IsAuraBordersEnabled() end,
        width = 200,
    })

    C:AddColorPicker(borderSection, {
        label = LO["Buff Border Color"],
        getFunc = function()
            local c = GetAuraBordersField("buff_color")
            if c and c.r then return c.r, c.g, c.b end
            return 0.6, 0.6, 0.6
        end,
        setFunc = function(r, g, b)
            C:EnsureModuleTable("auraborders").buff_color = { r = r, g = g, b = b }
        end,
        callback = RefreshAuraBorders,
        disabled = function() return not IsAuraBordersEnabled() end,
        hasAlpha = false,
    })

    C:AddSpacer(scroll)

    -- ====================================================================
    -- WEAPON ENCHANTS
    -- ====================================================================
    local weaponSection = C:AddSection(scroll, LO["Weapon Enchants"])

    C:AddDescription(weaponSection,
        LO["Weapon enchant icons include rogue poisons, sharpening stones, wizard oils, and similar temporary weapon enhancements."])

    C:AddToggle(weaponSection, {
        label = LO["Separate Weapon Enchants"],
        desc = LO["Detach weapon enchant icons (poisons, sharpening stones, etc.) from the buff bar into their own independently moveable frame. Position it freely using Editor Mode."],
        getFunc = function()
            return addon.db.profile.buffs and addon.db.profile.buffs.separate_weapon_enchants
        end,
        setFunc = function(val)
            if not addon.db.profile.buffs then addon.db.profile.buffs = {} end
            addon.db.profile.buffs.separate_weapon_enchants = val
        end,
        callback = function(val)
            if addon.BuffFrameModule then
                addon.BuffFrameModule:ToggleWeaponEnchantSeparation(val)
            end
        end,
        requiresReload = false,
    })

    C:AddDescription(weaponSection,
        "|cff888888" .. LO["When enabled, a 'Weapon Enchants' mover appears in Editor Mode that you can drag to any position on screen."] .. "|r")

    C:AddSpacer(scroll)
    local playerAuraSpacingSection = C:AddSection(scroll, LO["Player Aura Spacing"])

    C:AddSlider(playerAuraSpacingSection, {
        label = LO["Buff Horizontal Gap"],
        dbPath = "buffs.buff_horizontal_gap",
        min = 0, max = 20, step = 1,
        width = 220,
        callback = RefreshPlayerAuraSpacing,
    })

    C:AddSlider(playerAuraSpacingSection, {
        label = LO["Debuff Horizontal Gap"],
        dbPath = "buffs.debuff_horizontal_gap",
        min = 0, max = 20, step = 1,
        width = 220,
        callback = RefreshPlayerAuraSpacing,
    })

    -- ====================================================================
    -- TARGET/FOCUS AURA CUSTOMIZATION
    -- ====================================================================
    C:AddSpacer(scroll)
    local timerSection = C:AddSection(scroll, LO["Aura Timers"])
    local iconSection
    local dynamicWidgets = {}
    local isRefreshingAuraWidgets = false

    local function RegisterDynamicWidget(widget, disabledFunc, valueFunc)
        table.insert(dynamicWidgets, { widget = widget, disabledFunc = disabledFunc, valueFunc = valueFunc })
        return widget
    end

    local function RefreshAuraControlStates()
        isRefreshingAuraWidgets = true
        for _, entry in ipairs(dynamicWidgets) do
            if entry.widget and entry.widget.SetValue and entry.valueFunc then
                entry.widget:SetValue(entry.valueFunc())
            end
            if entry.widget and entry.widget.SetDisabled and entry.disabledFunc then
                entry.widget:SetDisabled(entry.disabledFunc())
            end
        end
        isRefreshingAuraWidgets = false
    end

    local function RefreshAuraUI()
        RefreshAuraControlStates()
        RefreshTargetFocusAuraTimers()
    end

    C:AddDescription(timerSection, LO["Show aura timers on Target and Focus independently."])
    C:AddDescription(timerSection,
        LO["These controls style Blizzard target/focus aura buttons. When attached filtered icons are enabled below, their own layout and duration settings take over for that unit."])

    RegisterDynamicWidget(C:AddToggle(timerSection, {
        label = LO["Enable Target Aura Timers"],
        getFunc = function()
            return GetAuraCooldownConfig().target.enabled == true
        end,
        setFunc = function(val)
            SetAuraUnitEnabled("target", val)
        end,
        callback = function()
            if isRefreshingAuraWidgets then return end
            RefreshAuraUI()
        end,
        requiresReload = false,
    }), nil, function()
        return GetAuraCooldownConfig().target.enabled == true
    end)

    RegisterDynamicWidget(C:AddToggle(timerSection, {
        label = LO["Enable Focus Aura Timers"],
        getFunc = function()
            return GetAuraCooldownConfig().focus.enabled == true
        end,
        setFunc = function(val)
            SetAuraUnitEnabled("focus", val)
        end,
        callback = function()
            if isRefreshingAuraWidgets then return end
            RefreshAuraUI()
        end,
        requiresReload = false,
    }), nil, function()
        return GetAuraCooldownConfig().focus.enabled == true
    end)

    C:AddHeading(timerSection, LO["Timer Text Settings"])

    RegisterDynamicWidget(C:AddDropdown(timerSection, {
        label = LO["Duration Text Anchor"],
        dbPath = "modules.auracooldowns.duration_anchor",
        values = AURA_ANCHORS,
        width = 220,
        disabled = function()
            return not IsTimerCustomizationEnabled()
        end,
        callback = RefreshTargetFocusAuraTimers,
    }), function()
        return not IsTimerCustomizationEnabled()
    end, function()
        return GetAuraCooldownConfig().duration_anchor
    end)

    RegisterDynamicWidget(C:AddSlider(timerSection, {
        label = LO["Duration X Offset"],
        dbPath = "modules.auracooldowns.duration_offset_x",
        min = -50, max = 50, step = 1,
        width = 220,
        disabled = function()
            return not IsTimerCustomizationEnabled()
        end,
        callback = RefreshTargetFocusAuraTimers,
    }), function()
        return not IsTimerCustomizationEnabled()
    end, function()
        return GetAuraCooldownConfig().duration_offset_x
    end)

    RegisterDynamicWidget(C:AddSlider(timerSection, {
        label = LO["Duration Y Offset"],
        dbPath = "modules.auracooldowns.duration_offset_y",
        min = -50, max = 50, step = 1,
        width = 220,
        disabled = function()
            return not IsTimerCustomizationEnabled()
        end,
        callback = RefreshTargetFocusAuraTimers,
    }), function()
        return not IsTimerCustomizationEnabled()
    end, function()
        return GetAuraCooldownConfig().duration_offset_y
    end)

    RegisterDynamicWidget(C:AddDropdown(timerSection, {
        label = LO["Duration Font"],
        dbPath = "modules.auracooldowns.duration_font",
        values = AURA_FONTS,
        width = 220,
        disabled = function()
            return not IsTimerCustomizationEnabled()
        end,
        callback = RefreshTargetFocusAuraTimers,
    }), function()
        return not IsTimerCustomizationEnabled()
    end, function()
        return GetAuraCooldownConfig().duration_font
    end)

    C:AddHeading(timerSection, LO["Target Aura Timer Settings"])

    RegisterDynamicWidget(C:AddSlider(timerSection, {
        label = LO["Target Aura Timer Size"],
        dbPath = "modules.auracooldowns.target.font_size",
        min = 6, max = 30, step = 1,
        width = 220,
        disabled = IsTargetTimerSettingsDisabled,
        callback = RefreshTargetFocusAuraTimers,
    }), IsTargetTimerSettingsDisabled, function()
        return GetAuraCooldownConfig().target.font_size
    end)

    RegisterDynamicWidget(C:AddSlider(timerSection, {
        label = LO["Target Aura Minimum Duration (Seconds)"],
        desc = LO["Only show aura timers when remaining duration is above this value (seconds)."],
        dbPath = "modules.auracooldowns.target.min_duration",
        min = 0, max = 60, step = 1,
        width = 220,
        disabled = IsTargetTimerSettingsDisabled,
        callback = RefreshTargetFocusAuraTimers,
    }), IsTargetTimerSettingsDisabled, function()
        return GetAuraCooldownConfig().target.min_duration
    end)

    RegisterDynamicWidget(C:AddSlider(timerSection, {
        label = LO["Target Aura Maximum Duration (Minutes)"],
        desc = LO["Only show aura timers when remaining duration is below this value (minutes). Use 0 to disable this limit."],
        dbPath = "modules.auracooldowns.target.max_duration_minutes",
        min = 0, max = 180, step = 1,
        width = 220,
        disabled = IsTargetTimerSettingsDisabled,
        callback = RefreshTargetFocusAuraTimers,
    }), IsTargetTimerSettingsDisabled, function()
        return GetAuraCooldownConfig().target.max_duration_minutes
    end)

    C:AddHeading(timerSection, LO["Focus Aura Timer Settings"])

    RegisterDynamicWidget(C:AddSlider(timerSection, {
        label = LO["Focus Aura Timer Size"],
        dbPath = "modules.auracooldowns.focus.font_size",
        min = 6, max = 30, step = 1,
        width = 220,
        disabled = IsFocusTimerSettingsDisabled,
        callback = RefreshTargetFocusAuraTimers,
    }), IsFocusTimerSettingsDisabled, function()
        return GetAuraCooldownConfig().focus.font_size
    end)

    RegisterDynamicWidget(C:AddSlider(timerSection, {
        label = LO["Focus Aura Minimum Duration (Seconds)"],
        desc = LO["Only show aura timers when remaining duration is above this value (seconds)."],
        dbPath = "modules.auracooldowns.focus.min_duration",
        min = 0, max = 60, step = 1,
        width = 220,
        disabled = IsFocusTimerSettingsDisabled,
        callback = RefreshTargetFocusAuraTimers,
    }), IsFocusTimerSettingsDisabled, function()
        return GetAuraCooldownConfig().focus.min_duration
    end)

    RegisterDynamicWidget(C:AddSlider(timerSection, {
        label = LO["Focus Aura Maximum Duration (Minutes)"],
        desc = LO["Only show aura timers when remaining duration is below this value (minutes). Use 0 to disable this limit."],
        dbPath = "modules.auracooldowns.focus.max_duration_minutes",
        min = 0, max = 180, step = 1,
        width = 220,
        disabled = IsFocusTimerSettingsDisabled,
        callback = RefreshTargetFocusAuraTimers,
    }), IsFocusTimerSettingsDisabled, function()
        return GetAuraCooldownConfig().focus.max_duration_minutes
    end)

    C:AddSpacer(timerSection)

    C:AddButton(timerSection, {
        label = LO["Reset Aura Timers"],
        width = 220,
        callback = function()
            ResetAuraTimerSettings()
            RefreshAuraUI()
            print("|cFF00FF00[DragonUI]|r " .. LO["Aura timer settings reset."])
        end,
    })

    C:AddSpacer(scroll)
    iconSection = C:AddSection(scroll, LO["Aura Icon Customization"])

    C:AddDescription(iconSection, LO["Customize icon size, scale, and stack text for target/focus auras."])

    RegisterDynamicWidget(C:AddToggle(iconSection, {
        label = LO["Customize Aura Icons"],
        desc = LO["Enable custom icon styling for target/focus aura icons."],
        getFunc = IsIconCustomizationEnabled,
        setFunc = function(val)
            SetAuraFeatureEnabled("icons_enabled", val)
        end,
        callback = function()
            if isRefreshingAuraWidgets then return end
            RefreshAuraUI()
        end,
        requiresReload = false,
    }), nil, function()
        return IsIconCustomizationEnabled()
    end)

    C:AddHeading(iconSection, LO["Stack Text Settings"])

    RegisterDynamicWidget(C:AddDropdown(iconSection, {
        label = LO["Stack Text Anchor"],
        dbPath = "modules.auracooldowns.stack_anchor",
        values = AURA_ANCHORS,
        width = 220,
        disabled = function()
            return not IsIconCustomizationEnabled()
        end,
        callback = RefreshTargetFocusAuraTimers,
    }), function()
        return not IsIconCustomizationEnabled()
    end, function()
        return GetAuraCooldownConfig().stack_anchor
    end)

    RegisterDynamicWidget(C:AddSlider(iconSection, {
        label = LO["Stack X Offset"],
        dbPath = "modules.auracooldowns.stack_offset_x",
        min = -50, max = 50, step = 1,
        width = 220,
        disabled = function()
            return not IsIconCustomizationEnabled()
        end,
        callback = RefreshTargetFocusAuraTimers,
    }), function()
        return not IsIconCustomizationEnabled()
    end, function()
        return GetAuraCooldownConfig().stack_offset_x
    end)

    RegisterDynamicWidget(C:AddSlider(iconSection, {
        label = LO["Stack Y Offset"],
        dbPath = "modules.auracooldowns.stack_offset_y",
        min = -50, max = 50, step = 1,
        width = 220,
        disabled = function()
            return not IsIconCustomizationEnabled()
        end,
        callback = RefreshTargetFocusAuraTimers,
    }), function()
        return not IsIconCustomizationEnabled()
    end, function()
        return GetAuraCooldownConfig().stack_offset_y
    end)

    RegisterDynamicWidget(C:AddDropdown(iconSection, {
        label = LO["Stack Font"],
        dbPath = "modules.auracooldowns.count_font",
        values = AURA_FONTS,
        width = 220,
        disabled = function()
            return not IsIconCustomizationEnabled()
        end,
        callback = RefreshTargetFocusAuraTimers,
    }), function()
        return not IsIconCustomizationEnabled()
    end, function()
        return GetAuraCooldownConfig().count_font
    end)

    C:AddHeading(iconSection, LO["Aura Buffs"])

    RegisterDynamicWidget(C:AddSlider(iconSection, {
        label = LO["Buff Icon Size"],
        dbPath = "modules.auracooldowns.buffs.icon_size",
        min = 0, max = 64, step = 1,
        width = 220,
        disabled = function()
            return not IsIconCustomizationEnabled()
        end,
        callback = RefreshTargetFocusAuraTimers,
    }), function()
        return not IsIconCustomizationEnabled()
    end, function()
        return GetAuraCooldownConfig().buffs.icon_size
    end)

    RegisterDynamicWidget(C:AddSlider(iconSection, {
        label = LO["Buff Icon Scale"],
        dbPath = "modules.auracooldowns.buffs.icon_scale",
        min = 0.5, max = 3, step = 0.01,
        width = 220,
        disabled = function()
            return not IsIconCustomizationEnabled()
        end,
        callback = RefreshTargetFocusAuraTimers,
    }), function()
        return not IsIconCustomizationEnabled()
    end, function()
        return GetAuraCooldownConfig().buffs.icon_scale
    end)

    RegisterDynamicWidget(C:AddSlider(iconSection, {
        label = LO["Buff Stack Font Size"],
        dbPath = "modules.auracooldowns.buffs.stack_font_size",
        min = 0, max = 30, step = 1,
        width = 220,
        disabled = function()
            return not IsIconCustomizationEnabled()
        end,
        callback = RefreshTargetFocusAuraTimers,
    }), function()
        return not IsIconCustomizationEnabled()
    end, function()
        return GetAuraCooldownConfig().buffs.stack_font_size
    end)

    C:AddHeading(iconSection, LO["Aura Debuffs"])

    RegisterDynamicWidget(C:AddSlider(iconSection, {
        label = LO["Debuff Icon Size"],
        dbPath = "modules.auracooldowns.debuffs.icon_size",
        min = 0, max = 64, step = 1,
        width = 220,
        disabled = function()
            return not IsIconCustomizationEnabled()
        end,
        callback = RefreshTargetFocusAuraTimers,
    }), function()
        return not IsIconCustomizationEnabled()
    end, function()
        return GetAuraCooldownConfig().debuffs.icon_size
    end)

    RegisterDynamicWidget(C:AddSlider(iconSection, {
        label = LO["Debuff Icon Scale"],
        dbPath = "modules.auracooldowns.debuffs.icon_scale",
        min = 0.5, max = 3, step = 0.01,
        width = 220,
        disabled = function()
            return not IsIconCustomizationEnabled()
        end,
        callback = RefreshTargetFocusAuraTimers,
    }), function()
        return not IsIconCustomizationEnabled()
    end, function()
        return GetAuraCooldownConfig().debuffs.icon_scale
    end)

    RegisterDynamicWidget(C:AddSlider(iconSection, {
        label = LO["Debuff Stack Font Size"],
        dbPath = "modules.auracooldowns.debuffs.stack_font_size",
        min = 0, max = 30, step = 1,
        width = 220,
        disabled = function()
            return not IsIconCustomizationEnabled()
        end,
        callback = RefreshTargetFocusAuraTimers,
    }), function()
        return not IsIconCustomizationEnabled()
    end, function()
        return GetAuraCooldownConfig().debuffs.stack_font_size
    end)

    C:AddSpacer(iconSection)

    C:AddButton(iconSection, {
        label = LO["Reset Aura Customization"],
        width = 220,
        callback = function()
            ResetAuraIconSettings()
            RefreshAuraUI()
            print("|cFF00FF00[DragonUI]|r " .. LO["Aura icon customization settings reset."])
        end,
    })

    RefreshAuraControlStates()

    -- ====================================================================
    -- ATTACHED UNIT-FRAME AURA ICONS + STANDALONE BLIZZARD FRAME FILTER
    -- ====================================================================
    C:AddSpacer(scroll)
    local standardFilterSection = C:AddSection(scroll, LO["Unit-Frame Aura Icons"])

    C:AddDescription(standardFilterSection,
        LO["Attach independently filtered aura icons to DragonUI unit frames. Player, target, focus, pet, party, boss, arena, and target-of-target families share the same renderer but keep separate settings."])
    C:AddDescription(standardFilterSection,
        LO["The Blizzard aura frame by the minimap is configured separately, so persistent buffs can remain there while timed combat auras are shown on the player frame."])

    C:AddDropdown(standardFilterSection, {
        label = LO["Configure Aura Icons For"],
        values = AURA_ICON_UNITS,
        getFunc = function() return selectedStandardAuraUnit end,
        setFunc = function(value) selectedStandardAuraUnit = value end,
        callback = RebuildAurasTabPreservingScroll,
        width = 240,
    })

    local function GetStandardAuraConfig()
        return GetAuraDisplayConfig("icons", selectedStandardAuraUnit)
    end

    local function StandardAuraControlsDisabled()
        return GetStandardAuraConfig().enabled ~= true
    end

    C:AddToggle(standardFilterSection, {
        label = selectedStandardAuraUnit == "buffframe" and LO["Filter Blizzard Aura Frame"]
            or LO["Enable Attached Aura Icons"],
        desc = selectedStandardAuraUnit == "buffframe"
            and LO["Filter and sort the standalone Blizzard buff/debuff frame without changing attached player-frame auras."]
            or LO["Show a filtered aura icon group anchored directly to this unit frame."],
        getFunc = function() return GetStandardAuraConfig().enabled == true end,
        setFunc = function(value)
            GetStandardAuraConfig().enabled = value and true or false
            if value then GetAuraCustomizationConfig().enabled = true end
        end,
        callback = function()
            RefreshAuraCustomization()
            RebuildAurasTabPreservingScroll()
        end,
        requiresReload = false,
    })

    C:AddSlider(standardFilterSection, {
        label = LO["Maximum Buff Icons"],
        min = 0, max = 32, step = 1,
        width = 240,
        getFunc = function() return tonumber(GetStandardAuraConfig().max_buffs) or 32 end,
        setFunc = function(value) GetStandardAuraConfig().max_buffs = value end,
        callback = RefreshAuraCustomization,
        disabled = StandardAuraControlsDisabled,
    })

    C:AddSlider(standardFilterSection, {
        label = LO["Maximum Debuff Icons"],
        min = 0, max = 32, step = 1,
        width = 240,
        getFunc = function() return tonumber(GetStandardAuraConfig().max_debuffs) or 16 end,
        setFunc = function(value) GetStandardAuraConfig().max_debuffs = value end,
        callback = RefreshAuraCustomization,
        disabled = StandardAuraControlsDisabled,
    })

    if selectedStandardAuraUnit ~= "buffframe" then
        C:AddHeading(standardFilterSection, LO["Attached Icon Layout"])
        C:AddDescription(standardFilterSection,
            LO["Attached icon groups always follow their unit frame; configure their anchor and offsets here instead of moving them in Editor Mode."])

        C:AddDropdown(standardFilterSection, {
            label = LO["Attach To Unit Frame"],
            values = AURA_ANCHORS,
            getFunc = function() return GetStandardAuraConfig().anchor or "BOTTOMLEFT" end,
            setFunc = function(value) GetStandardAuraConfig().anchor = value end,
            callback = RefreshAuraCustomization,
            disabled = StandardAuraControlsDisabled,
            width = 240,
        })

        C:AddSlider(standardFilterSection, {
            label = LO["Aura Icon X Offset"],
            min = -250, max = 250, step = 1,
            width = 240,
            getFunc = function() return tonumber(GetStandardAuraConfig().offset_x) or 0 end,
            setFunc = function(value) GetStandardAuraConfig().offset_x = value end,
            callback = RefreshAuraCustomization,
            disabled = StandardAuraControlsDisabled,
        })

        C:AddSlider(standardFilterSection, {
            label = LO["Aura Icon Y Offset"],
            min = -250, max = 250, step = 1,
            width = 240,
            getFunc = function() return tonumber(GetStandardAuraConfig().offset_y) or 0 end,
            setFunc = function(value) GetStandardAuraConfig().offset_y = value end,
            callback = RefreshAuraCustomization,
            disabled = StandardAuraControlsDisabled,
        })

        C:AddSlider(standardFilterSection, {
            label = LO["Buff Icon Size"],
            min = 8, max = 64, step = 1,
            width = 240,
            getFunc = function() return tonumber(GetStandardAuraConfig().buff_size) or 17 end,
            setFunc = function(value) GetStandardAuraConfig().buff_size = value end,
            callback = RefreshAuraCustomization,
            disabled = StandardAuraControlsDisabled,
        })

        C:AddSlider(standardFilterSection, {
            label = LO["Debuff Icon Size"],
            min = 8, max = 64, step = 1,
            width = 240,
            getFunc = function() return tonumber(GetStandardAuraConfig().debuff_size) or 17 end,
            setFunc = function(value) GetStandardAuraConfig().debuff_size = value end,
            callback = RefreshAuraCustomization,
            disabled = StandardAuraControlsDisabled,
        })

        C:AddSlider(standardFilterSection, {
            label = LO["Attached Aura Scale"],
            min = 0.5, max = 2.5, step = 0.01,
            width = 240,
            getFunc = function() return tonumber(GetStandardAuraConfig().scale) or 1 end,
            setFunc = function(value) GetStandardAuraConfig().scale = value end,
            callback = RefreshAuraCustomization,
            disabled = StandardAuraControlsDisabled,
        })

        C:AddSlider(standardFilterSection, {
            label = LO["Icons Per Row"],
            min = 1, max = 20, step = 1,
            width = 240,
            getFunc = function() return tonumber(GetStandardAuraConfig().per_row) or 8 end,
            setFunc = function(value) GetStandardAuraConfig().per_row = value end,
            callback = RefreshAuraCustomization,
            disabled = StandardAuraControlsDisabled,
        })

        C:AddSlider(standardFilterSection, {
            label = LO["Horizontal Icon Spacing"],
            min = 0, max = 20, step = 1,
            width = 240,
            getFunc = function() return tonumber(GetStandardAuraConfig().spacing_x) or 2 end,
            setFunc = function(value) GetStandardAuraConfig().spacing_x = value end,
            callback = RefreshAuraCustomization,
            disabled = StandardAuraControlsDisabled,
        })

        C:AddSlider(standardFilterSection, {
            label = LO["Vertical Icon Spacing"],
            min = 0, max = 20, step = 1,
            width = 240,
            getFunc = function() return tonumber(GetStandardAuraConfig().spacing_y) or 2 end,
            setFunc = function(value) GetStandardAuraConfig().spacing_y = value end,
            callback = RefreshAuraCustomization,
            disabled = StandardAuraControlsDisabled,
        })

        C:AddDropdown(standardFilterSection, {
            label = LO["Horizontal Growth Direction"],
            values = AURA_ICON_GROWTH_X,
            getFunc = function() return GetStandardAuraConfig().growth_x or "RIGHT" end,
            setFunc = function(value) GetStandardAuraConfig().growth_x = value end,
            callback = RefreshAuraCustomization,
            disabled = StandardAuraControlsDisabled,
            width = 240,
        })

        C:AddDropdown(standardFilterSection, {
            label = LO["Vertical Growth Direction"],
            values = AURA_ICON_GROWTH_Y,
            getFunc = function() return GetStandardAuraConfig().growth_y or "DOWN" end,
            setFunc = function(value) GetStandardAuraConfig().growth_y = value end,
            callback = RefreshAuraCustomization,
            disabled = StandardAuraControlsDisabled,
            width = 240,
        })

        C:AddToggle(standardFilterSection, {
            label = LO["Show Cooldown Swipe"],
            getFunc = function() return GetStandardAuraConfig().show_cooldown ~= false end,
            setFunc = function(value) GetStandardAuraConfig().show_cooldown = value and true or false end,
            callback = RefreshAuraCustomization,
            disabled = StandardAuraControlsDisabled,
        })

        C:AddToggle(standardFilterSection, {
            label = LO["Show Aura Duration Text"],
            getFunc = function() return GetStandardAuraConfig().show_duration ~= false end,
            setFunc = function(value) GetStandardAuraConfig().show_duration = value and true or false end,
            callback = RefreshAuraCustomization,
            disabled = StandardAuraControlsDisabled,
        })

        C:AddSlider(standardFilterSection, {
            label = LO["Aura Duration Font Size"],
            min = 6, max = 24, step = 1,
            width = 240,
            getFunc = function() return tonumber(GetStandardAuraConfig().duration_font_size) or 10 end,
            setFunc = function(value) GetStandardAuraConfig().duration_font_size = value end,
            callback = RefreshAuraCustomization,
            disabled = StandardAuraControlsDisabled,
        })
    end

    AddAuraFilterControls(standardFilterSection, GetStandardAuraConfig, StandardAuraControlsDisabled)

    C:AddSpacer(standardFilterSection)
    C:AddButton(standardFilterSection, {
        label = LO["Reset Selected Aura Icon Settings"],
        width = 280,
        callback = function()
            ResetAuraDisplayConfig("icons", selectedStandardAuraUnit)
            RebuildAurasTabPreservingScroll()
        end,
    })

    -- ====================================================================
    -- MOVABLE AURA BARS
    -- ====================================================================
    C:AddSpacer(scroll)
    local auraBarSection = C:AddSection(scroll, LO["Aura Bars"])

    C:AddDescription(auraBarSection,
        LO["Show auras as independently filtered horizontal status bars. Each player's, target's, and focus's bar group has its own Editor Mode mover and does not alter standard aura icons."])

    C:AddDropdown(auraBarSection, {
        label = LO["Configure Aura Bars For"],
        values = AURA_BAR_UNITS,
        getFunc = function() return selectedAuraBarUnit end,
        setFunc = function(value) selectedAuraBarUnit = value end,
        callback = RebuildAurasTabPreservingScroll,
        width = 240,
    })

    local function GetAuraBarConfig()
        return GetAuraDisplayConfig("bars", selectedAuraBarUnit)
    end

    local function AuraBarControlsDisabled()
        return GetAuraBarConfig().enabled ~= true
    end

    C:AddToggle(auraBarSection, {
        label = LO["Enable Aura Bars"],
        getFunc = function() return GetAuraBarConfig().enabled == true end,
        setFunc = function(value)
            GetAuraBarConfig().enabled = value and true or false
            if value then GetAuraCustomizationConfig().enabled = true end
        end,
        callback = function()
            RefreshAuraCustomization()
            RebuildAurasTabPreservingScroll()
        end,
        requiresReload = false,
    })

    C:AddHeading(auraBarSection, LO["Aura Bar Appearance"])

    C:AddSlider(auraBarSection, {
        label = LO["Maximum Aura Bars"],
        min = 1, max = 40, step = 1,
        width = 240,
        getFunc = function() return tonumber(GetAuraBarConfig().max_bars) or 8 end,
        setFunc = function(value) GetAuraBarConfig().max_bars = value end,
        callback = RefreshAuraCustomization,
        disabled = AuraBarControlsDisabled,
    })

    C:AddSlider(auraBarSection, {
        label = LO["Aura Bar Width"],
        min = 80, max = 500, step = 1,
        width = 240,
        getFunc = function() return tonumber(GetAuraBarConfig().width) or 250 end,
        setFunc = function(value) GetAuraBarConfig().width = value end,
        callback = RefreshAuraCustomization,
        disabled = AuraBarControlsDisabled,
    })

    C:AddSlider(auraBarSection, {
        label = LO["Aura Bar Height"],
        min = 8, max = 50, step = 1,
        width = 240,
        getFunc = function() return tonumber(GetAuraBarConfig().height) or 18 end,
        setFunc = function(value) GetAuraBarConfig().height = value end,
        callback = RefreshAuraCustomization,
        disabled = AuraBarControlsDisabled,
    })

    C:AddSlider(auraBarSection, {
        label = LO["Aura Bar Scale"],
        min = 0.5, max = 2.5, step = 0.01,
        width = 240,
        getFunc = function() return tonumber(GetAuraBarConfig().scale) or 1 end,
        setFunc = function(value) GetAuraBarConfig().scale = value end,
        callback = RefreshAuraCustomization,
        disabled = AuraBarControlsDisabled,
    })

    C:AddSlider(auraBarSection, {
        label = LO["Aura Bar Spacing"],
        min = 0, max = 20, step = 1,
        width = 240,
        getFunc = function() return tonumber(GetAuraBarConfig().spacing) or 2 end,
        setFunc = function(value) GetAuraBarConfig().spacing = value end,
        callback = RefreshAuraCustomization,
        disabled = AuraBarControlsDisabled,
    })

    C:AddSlider(auraBarSection, {
        label = LO["Aura Bar Font Size"],
        min = 6, max = 24, step = 1,
        width = 240,
        getFunc = function() return tonumber(GetAuraBarConfig().font_size) or 10 end,
        setFunc = function(value) GetAuraBarConfig().font_size = value end,
        callback = RefreshAuraCustomization,
        disabled = AuraBarControlsDisabled,
    })

    C:AddHeading(auraBarSection, LO["Aura Bar Media and Borders"])
    C:AddDescription(auraBarSection,
        LO["Media lists include DragonUI fallbacks and every compatible texture, border, or font currently registered in LibSharedMedia by addons such as Details and ElvUI."])

    C:AddDropdown(auraBarSection, {
        label = LO["Aura Bar Texture"],
        values = GetAuraMediaChoices("statusbar"),
        getFunc = function() return GetAuraBarConfig().texture or "Blizzard" end,
        setFunc = function(value) GetAuraBarConfig().texture = value end,
        callback = RefreshAuraCustomization,
        disabled = AuraBarControlsDisabled,
        width = 300,
    })

    C:AddDropdown(auraBarSection, {
        label = LO["Aura Bar Background Texture"],
        values = GetAuraMediaChoices("statusbar", false, true),
        getFunc = function() return GetAuraBarConfig().background_texture or "Flat" end,
        setFunc = function(value) GetAuraBarConfig().background_texture = value end,
        callback = RefreshAuraCustomization,
        disabled = AuraBarControlsDisabled,
        width = 300,
    })

    C:AddColorPicker(auraBarSection, {
        label = LO["Aura Bar Background Color"],
        getFunc = function()
            local color = GetAuraBarConfig().background_color
            return color and color.r or 0.05, color and color.g or 0.05,
                color and color.b or 0.05, color and color.a or 0.90
        end,
        setFunc = function(r, g, b, a)
            GetAuraBarConfig().background_color = { r = r, g = g, b = b, a = a or 1 }
        end,
        callback = RefreshAuraCustomization,
        disabled = AuraBarControlsDisabled,
        hasAlpha = true,
    })

    C:AddDropdown(auraBarSection, {
        label = LO["Aura Bar Border Texture"],
        values = GetAuraMediaChoices("border", true),
        getFunc = function() return GetAuraBarConfig().border_texture or "DragonUI 1 Pixel" end,
        setFunc = function(value) GetAuraBarConfig().border_texture = value end,
        callback = RefreshAuraCustomization,
        disabled = AuraBarControlsDisabled,
        width = 300,
    })

    C:AddSlider(auraBarSection, {
        label = LO["Aura Bar Border Size"],
        min = 1, max = 24, step = 1,
        width = 240,
        getFunc = function() return tonumber(GetAuraBarConfig().border_size) or 1 end,
        setFunc = function(value) GetAuraBarConfig().border_size = value end,
        callback = RefreshAuraCustomization,
        disabled = AuraBarControlsDisabled,
    })

    C:AddSlider(auraBarSection, {
        label = LO["Aura Bar Border Inset"],
        min = 0, max = 12, step = 1,
        width = 240,
        getFunc = function() return tonumber(GetAuraBarConfig().border_inset) or 0 end,
        setFunc = function(value) GetAuraBarConfig().border_inset = value end,
        callback = RefreshAuraCustomization,
        disabled = AuraBarControlsDisabled,
    })

    C:AddColorPicker(auraBarSection, {
        label = LO["Aura Bar Border Color"],
        getFunc = function()
            local color = GetAuraBarConfig().border_color
            return color and color.r or 0, color and color.g or 0,
                color and color.b or 0, color and color.a or 1
        end,
        setFunc = function(r, g, b, a)
            GetAuraBarConfig().border_color = { r = r, g = g, b = b, a = a or 1 }
        end,
        callback = RefreshAuraCustomization,
        disabled = AuraBarControlsDisabled,
        hasAlpha = true,
    })

    C:AddHeading(auraBarSection, LO["Aura Bar Text and Icon Border"])

    C:AddDropdown(auraBarSection, {
        label = LO["Aura Bar Font"],
        values = GetAuraMediaChoices("font"),
        getFunc = function() return GetAuraBarConfig().font or "DragonUI Narrow" end,
        setFunc = function(value) GetAuraBarConfig().font = value end,
        callback = RefreshAuraCustomization,
        disabled = AuraBarControlsDisabled,
        width = 300,
    })

    C:AddDropdown(auraBarSection, {
        label = LO["Aura Bar Text Outline"],
        values = AURA_BAR_TEXT_OUTLINES,
        getFunc = function() return GetAuraBarConfig().text_outline or "OUTLINE" end,
        setFunc = function(value) GetAuraBarConfig().text_outline = value end,
        callback = RefreshAuraCustomization,
        disabled = AuraBarControlsDisabled,
        width = 240,
    })

    C:AddColorPicker(auraBarSection, {
        label = LO["Aura Bar Text Color"],
        getFunc = function()
            local color = GetAuraBarConfig().text_color
            return color and color.r or 1, color and color.g or 1,
                color and color.b or 1, color and color.a or 1
        end,
        setFunc = function(r, g, b, a)
            GetAuraBarConfig().text_color = { r = r, g = g, b = b, a = a or 1 }
        end,
        callback = RefreshAuraCustomization,
        disabled = AuraBarControlsDisabled,
        hasAlpha = true,
    })

    C:AddDropdown(auraBarSection, {
        label = LO["Aura Bar Icon Border Texture"],
        values = GetAuraMediaChoices("border", true),
        getFunc = function() return GetAuraBarConfig().icon_border_texture or "DragonUI 1 Pixel" end,
        setFunc = function(value) GetAuraBarConfig().icon_border_texture = value end,
        callback = RefreshAuraCustomization,
        disabled = AuraBarControlsDisabled,
        width = 300,
    })

    C:AddSlider(auraBarSection, {
        label = LO["Aura Bar Icon Border Size"],
        min = 1, max = 24, step = 1,
        width = 240,
        getFunc = function() return tonumber(GetAuraBarConfig().icon_border_size) or 1 end,
        setFunc = function(value) GetAuraBarConfig().icon_border_size = value end,
        callback = RefreshAuraCustomization,
        disabled = AuraBarControlsDisabled,
    })

    C:AddSlider(auraBarSection, {
        label = LO["Aura Bar Icon Border Inset"],
        min = 0, max = 12, step = 1,
        width = 240,
        getFunc = function() return tonumber(GetAuraBarConfig().icon_border_inset) or 0 end,
        setFunc = function(value) GetAuraBarConfig().icon_border_inset = value end,
        callback = RefreshAuraCustomization,
        disabled = AuraBarControlsDisabled,
    })

    C:AddDropdown(auraBarSection, {
        label = LO["Aura Bar Icon Border Coloring"],
        values = AURA_BAR_ICON_BORDER_MODES,
        getFunc = function() return GetAuraBarConfig().icon_border_mode or "aura" end,
        setFunc = function(value) GetAuraBarConfig().icon_border_mode = value end,
        callback = RefreshAuraCustomization,
        disabled = AuraBarControlsDisabled,
        width = 240,
    })

    C:AddColorPicker(auraBarSection, {
        label = LO["Aura Bar Icon Border Color"],
        getFunc = function()
            local color = GetAuraBarConfig().icon_border_color
            return color and color.r or 0, color and color.g or 0,
                color and color.b or 0, color and color.a or 1
        end,
        setFunc = function(r, g, b, a)
            GetAuraBarConfig().icon_border_color = { r = r, g = g, b = b, a = a or 1 }
        end,
        callback = RefreshAuraCustomization,
        disabled = AuraBarControlsDisabled,
        hasAlpha = true,
    })

    C:AddDropdown(auraBarSection, {
        label = LO["Aura Bar Growth Direction"],
        values = AURA_BAR_GROWTH,
        getFunc = function() return GetAuraBarConfig().growth or "DOWN" end,
        setFunc = function(value) GetAuraBarConfig().growth = value end,
        callback = RefreshAuraCustomization,
        disabled = AuraBarControlsDisabled,
        width = 240,
    })

    C:AddToggle(auraBarSection, {
        label = LO["Show Aura Bar Icons"],
        getFunc = function() return GetAuraBarConfig().show_icon ~= false end,
        setFunc = function(value) GetAuraBarConfig().show_icon = value and true or false end,
        callback = RefreshAuraCustomization,
        disabled = AuraBarControlsDisabled,
    })

    C:AddDropdown(auraBarSection, {
        label = LO["Aura Bar Icon Side"],
        values = AURA_BAR_ICON_SIDE,
        getFunc = function() return GetAuraBarConfig().icon_side or "LEFT" end,
        setFunc = function(value) GetAuraBarConfig().icon_side = value end,
        callback = RefreshAuraCustomization,
        disabled = AuraBarControlsDisabled,
        width = 240,
    })

    C:AddColorPicker(auraBarSection, {
        label = LO["Buff Bar Color"],
        getFunc = function()
            local color = GetAuraBarConfig().buff_color
            return color and color.r or 0.2, color and color.g or 0.55, color and color.b or 1
        end,
        setFunc = function(r, g, b) GetAuraBarConfig().buff_color = { r = r, g = g, b = b } end,
        callback = RefreshAuraCustomization,
        disabled = AuraBarControlsDisabled,
        hasAlpha = false,
    })

    C:AddColorPicker(auraBarSection, {
        label = LO["Debuff Bar Color"],
        getFunc = function()
            local color = GetAuraBarConfig().debuff_color
            return color and color.r or 0.8, color and color.g or 0.1, color and color.b or 0.1
        end,
        setFunc = function(r, g, b) GetAuraBarConfig().debuff_color = { r = r, g = g, b = b } end,
        callback = RefreshAuraCustomization,
        disabled = AuraBarControlsDisabled,
        hasAlpha = false,
    })

    C:AddToggle(auraBarSection, {
        label = LO["Use Dispel-Type Debuff Colors"],
        desc = LO["Color debuff bars by Magic, Curse, Disease, or Poison instead of the custom debuff color."],
        getFunc = function() return GetAuraBarConfig().debuff_type_color ~= false end,
        setFunc = function(value) GetAuraBarConfig().debuff_type_color = value and true or false end,
        callback = RefreshAuraCustomization,
        disabled = AuraBarControlsDisabled,
    })

    AddAuraFilterControls(auraBarSection, GetAuraBarConfig, AuraBarControlsDisabled)

    C:AddSpacer(auraBarSection)
    C:AddDescription(auraBarSection,
        "|cff1784d1" .. LO["Move the selected bar group through Editor Mode. Aura bar filters and standard icon filters are completely independent."] .. "|r")
    C:AddButton(auraBarSection, {
        label = LO["Reset Selected Aura Bars"],
        width = 280,
        callback = function()
            ResetAuraDisplayConfig("bars", selectedAuraBarUnit)
            ResetAuraBarPosition(selectedAuraBarUnit)
            RebuildAurasTabPreservingScroll()
        end,
    })

    -- ====================================================================
    -- RESET POSITION
    -- ====================================================================
    C:AddSpacer(scroll)
    local resetSection = C:AddSection(scroll, LO["Positions"])

    C:AddButton(resetSection, {
        label = LO["Reset Buff Frame Position"],
        width = 220,
        callback = function()
            if addon.BuffFrameModule then
                addon.BuffFrameModule:ResetBuffFramePosition()
            end
            print("|cFF00FF00[DragonUI]|r " .. LO["Buff frame position reset."])
        end,
    })

    C:AddButton(resetSection, {
        label = LO["Reset Weapon Enchant Position"],
        width = 220,
        callback = function()
            if addon.db.profile.widgets and addon.db.profile.widgets.weapon_enchants then
                local w = addon.db.profile.widgets.weapon_enchants
                w.anchor = "TOPRIGHT"
                w.posX = -100
                w.posY = -15
                w.custom_position = false
            end
            if addon.BuffFrameModule then
                addon.BuffFrameModule:UpdateWeaponEnchantPosition()
            end
            print("|cFF00FF00[DragonUI]|r " .. LO["Weapon enchant position reset."])
        end,
    })

    C:AddSpacer(resetSection)

    local isDebuffDetached = C:GetDBValue("widgets.debuffs.custom_position")
    if isDebuffDetached then
        C:AddDescription(resetSection, "|cff1784d1- " .. LO["Debuffs detached - positioned freely via Editor Mode"] .. "|r")
    else
        C:AddDescription(resetSection, "|cffaaaaaa- " .. LO["Debuffs attached - follow buff row"] .. "|r")
    end

    C:AddButton(resetSection, {
        label = LO["Reset Debuff Position"],
        width = 220,
        disabled = function()
            return not C:GetDBValue("widgets.debuffs.custom_position")
        end,
        callback = function()
            if addon.BuffFrameModule then
                addon.BuffFrameModule:ResetDebuffPosition()
            end
            print("|cFF00FF00[DragonUI]|r " .. LO["Debuff position reset."])
            RebuildAurasTabPreservingScroll()
        end,
    })
end

-- Register the tab (order 12 — after Enhancements, before Profiles)
Panel:RegisterTab("auras", LO["Auras"], BuildAurasTab, 12)
