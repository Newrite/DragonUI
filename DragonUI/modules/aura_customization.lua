local addon = select(2, ...)

-- ============================================================================
-- DragonUI - Unit Aura Customization
-- One filtering/sorting source feeds two deliberately separate displays:
--   * attached aura icons on DragonUI unit frames;
--   * independently movable aura bars for player, target, and focus.
-- Blizzard's minimap BuffFrame remains an optional, separately filtered display.
-- ============================================================================

local AuraCustomizationModule = {
    initialized = false,
    applied = false,
    sourceLoaded = false,
    registered = false,
    registrationError = nil,
    hooksInstalled = false,
    restoring = false,
    eventFrame = nil,
    updateFrame = nil,
    standardActive = {},
    attachedFrames = {},
    barFrames = {},
    preview = {},
    mediaRegistered = false,
    mediaCallbackRegistered = false,
}
addon.AuraCustomizationModule = AuraCustomizationModule

local _G = getfenv(0)
local ceil = math.ceil
local floor = math.floor
local max = math.max
local min = math.min
local sort = table.sort
local format = string.format
local lower = string.lower
local gmatch = string.gmatch
local UnitBuff = UnitBuff
local UnitDebuff = UnitDebuff
local UnitExists = UnitExists
local UnitIsUnit = UnitIsUnit
local GetTime = GetTime

local ICON_UNIT_KEYS = {
    "buffframe", "player", "target", "focus", "pet", "tot", "fot", "party", "boss", "arena",
}
local BAR_UNIT_KEYS = { "player", "target", "focus" }
local BAR_FRAME_NAMES = {
    player = "PlayerAuraBars",
    target = "TargetAuraBars",
    focus = "FocusAuraBars",
}
local BAR_WIDGET_KEYS = {
    player = "playerAuraBars",
    target = "targetAuraBars",
    focus = "focusAuraBars",
}
local MAX_PLAYER_BUFFS = _G.BUFF_MAX_DISPLAY or _G.BUFF_ACTUAL_DISPLAY or 32
local MAX_PLAYER_DEBUFFS = _G.DEBUFF_MAX_DISPLAY or 16
local MAX_SCAN_AURAS = 80
local UPDATE_INTERVAL = 0.1
local ICON_CROP = 0.06
local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local BACKDROP = {
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = WHITE_TEXTURE,
    tile = false,
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
}
local AURA_MEDIA = {
    statusbar = {
        ["Blizzard"] = "Interface\\TargetingFrame\\UI-StatusBar",
        ["DragonUI Smooth"] = "Interface\\AddOns\\DragonUI\\assets\\statusbarfill",
        ["DragonUI Nameplate"] = "Interface\\AddOns\\DragonUI\\Textures\\Nameplates\\bar-fill",
        ["Flat"] = WHITE_TEXTURE,
    },
    border = {
        ["DragonUI 1 Pixel"] = WHITE_TEXTURE,
        ["Blizzard Tooltip"] = "Interface\\Tooltips\\UI-Tooltip-Border",
    },
    font = {
        ["DragonUI Narrow"] = (addon.Fonts and addon.Fonts.NARROW) or "Fonts\\ARIALN.TTF",
        ["Friz Quadrata"] = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF",
        ["Arial Narrow"] = "Fonts\\ARIALN.TTF",
    },
}
local backdropCache = {}
local VALID_STRATA = {
    BACKGROUND = true,
    LOW = true,
    MEDIUM = true,
    HIGH = true,
    DIALOG = true,
    FULLSCREEN = true,
    FULLSCREEN_DIALOG = true,
    TOOLTIP = true,
}

local ATTACHED_DESCRIPTORS = {
    { id = "player", configKey = "player", unit = "player", frameName = "PlayerFrame" },
    { id = "target", configKey = "target", unit = "target", frameName = "TargetFrame",
        stockPrefix = "TargetFrame", stockBuffs = 32, stockDebuffs = 16 },
    { id = "focus", configKey = "focus", unit = "focus", frameName = "FocusFrame",
        stockPrefix = "FocusFrame", stockBuffs = 32, stockDebuffs = 16 },
    { id = "pet", configKey = "pet", unit = "pet", frameName = "PetFrame" },
    { id = "tot", configKey = "tot", unit = "targettarget", frameName = "TargetFrameToT",
        stockPrefix = "TargetFrameToT", stockBuffs = 0, stockDebuffs = 4 },
    { id = "fot", configKey = "fot", unit = "focustarget", frameName = "FocusFrameToT",
        stockPrefix = "FocusFrameToT", stockBuffs = 0, stockDebuffs = 4 },
}

for i = 1, 4 do
    ATTACHED_DESCRIPTORS[#ATTACHED_DESCRIPTORS + 1] = {
        id = "party" .. i,
        configKey = "party",
        unit = "party" .. i,
        frameName = "PartyMemberFrame" .. i,
        stockPrefix = "PartyMemberFrame" .. i,
        stockBuffs = 4,
        stockDebuffs = 4,
    }
    ATTACHED_DESCRIPTORS[#ATTACHED_DESCRIPTORS + 1] = {
        id = "boss" .. i,
        configKey = "boss",
        unit = "boss" .. i,
        frameName = "Boss" .. i .. "TargetFrame",
        stockPrefix = "Boss" .. i .. "TargetFrame",
        stockBuffs = 32,
        stockDebuffs = 16,
    }
end

for i = 1, 5 do
    ATTACHED_DESCRIPTORS[#ATTACHED_DESCRIPTORS + 1] = {
        id = "arena" .. i,
        configKey = "arena",
        unit = "arena" .. i,
        frameName = "ArenaEnemyFrame" .. i,
        stockPrefix = "ArenaEnemyFrame" .. i,
        stockBuffs = 4,
        stockDebuffs = 4,
    }
end

local filterTextCache = {}

local function CopyTable(source)
    if type(source) ~= "table" then return source end
    local copy = {}
    for key, value in pairs(source) do
        copy[key] = type(value) == "table" and CopyTable(value) or value
    end
    return copy
end

local function GetConfig()
    return addon:GetModuleConfig("aura_customization")
end

local function IsModuleEnabled()
    return addon:IsModuleEnabled("aura_customization")
end

local function GetDisplayConfig(displayType, unitKey)
    local cfg = GetConfig()
    if not cfg then return nil end
    cfg[displayType] = cfg[displayType] or {}
    if not cfg[displayType][unitKey] then
        local defaults = addon.defaults and addon.defaults.profile and addon.defaults.profile.modules
            and addon.defaults.profile.modules.aura_customization
        local source = defaults and defaults[displayType] and defaults[displayType][unitKey]
        cfg[displayType][unitKey] = CopyTable(source or {})
    end
    return cfg[displayType][unitKey]
end

local function IsEditorActive()
    return addon.EditorMode and addon.EditorMode.IsActive and addon.EditorMode:IsActive()
end

local function ResolvePlayerAuraUnit()
    if _G.PlayerFrame and _G.PlayerFrame.unit and UnitExists(_G.PlayerFrame.unit) then
        return _G.PlayerFrame.unit
    end
    return "player"
end

local function ResolveBarUnit(unitKey)
    if unitKey == "player" then return ResolvePlayerAuraUnit() end
    return unitKey
end

local function ResolveDescriptorUnit(descriptor)
    if descriptor.configKey == "player" then return ResolvePlayerAuraUnit() end
    return descriptor.unit
end

local function Trim(value)
    if type(value) ~= "string" then return "" end
    return value:match("^%s*(.-)%s*$") or ""
end

local function ParseFilterText(value)
    value = type(value) == "string" and value or ""
    local cached = filterTextCache[value]
    if cached then return cached end

    local parsed = { ids = {}, names = {}, hasEntries = false }
    for token in gmatch(value, "[^,;\r\n]+") do
        token = Trim(token)
        if token ~= "" then
            local spellID = tonumber(token)
            if spellID then
                parsed.ids[spellID] = true
            else
                parsed.names[lower(token)] = true
            end
            parsed.hasEntries = true
        end
    end

    filterTextCache[value] = parsed
    return parsed
end

local function MatchesFilterList(aura, parsed)
    if not parsed or not parsed.hasEntries then return false end
    if aura.spellID and parsed.ids[aura.spellID] then return true end
    return aura.name and parsed.names[lower(aura.name)] == true
end

local function IsPlayerCaster(caster)
    if caster == "player" or caster == "vehicle" then return true end
    return caster and UnitIsUnit and UnitExists(caster) and UnitIsUnit(caster, "player") or false
end

local function ShouldIncludeAura(aura, cfg)
    if not aura or not cfg then return false end

    local blacklist = ParseFilterText(cfg.blacklist)
    if MatchesFilterList(aura, blacklist) then return false end

    local whitelist = ParseFilterText(cfg.whitelist)
    if whitelist.hasEntries and not MatchesFilterList(aura, whitelist) then return false end

    local casterFilter = cfg.caster or "all"
    if casterFilter == "mine" and not aura.isMine then return false end
    if casterFilter == "others" and aura.isMine then return false end

    if aura.noDuration then
        return cfg.include_no_duration ~= false
    end

    local duration = aura.duration or 0
    local minDuration = tonumber(cfg.min_duration) or 0
    local maxDurationMinutes = tonumber(cfg.max_duration_minutes) or 0
    if minDuration > 0 and duration < minDuration then return false end
    if maxDurationMinutes > 0 and duration > maxDurationMinutes * 60 then return false end
    return true
end

local function ScanAuraType(unit, configKey, filter, auraType, cfg)
    local result = {}
    if not unit or not UnitExists(unit) then return result end

    local auraAPI = auraType == "buff" and UnitBuff or UnitDebuff
    local queryFilter = auraType == "debuff" and (configKey == "target" or configKey == "focus")
        and "INCLUDE_NAME_PLATE_ONLY" or nil

    for index = 1, MAX_SCAN_AURAS do
        local name, rank, icon, count, debuffType, duration, expirationTime,
            caster, isStealable, shouldConsolidate, spellID = auraAPI(unit, index, queryFilter)
        if not name then break end

        local aura = {
            unit = unit,
            index = index,
            filter = filter,
            queryFilter = queryFilter,
            auraType = auraType,
            name = name,
            rank = rank,
            icon = icon,
            count = count or 0,
            debuffType = debuffType,
            duration = duration or 0,
            expirationTime = expirationTime or 0,
            caster = caster,
            isStealable = isStealable,
            shouldConsolidate = shouldConsolidate,
            spellID = spellID,
        }
        aura.noDuration = aura.duration <= 0 or aura.expirationTime <= 0
        aura.isMine = IsPlayerCaster(caster)

        if ShouldIncludeAura(aura, cfg) then
            result[#result + 1] = aura
        end
    end
    return result
end

local function AuraSortValue(aura, method)
    if method == "time_asc" or method == "time_desc" then
        return aura.noDuration and math.huge or aura.expirationTime
    elseif method == "duration_asc" or method == "duration_desc" then
        return aura.noDuration and math.huge or aura.duration
    elseif method == "name" then
        return lower(aura.name or "")
    end
    return aura.index or 0
end

local function SortAuras(auras, cfg)
    local method = cfg and cfg.sort or "index"
    local noDurationLast = not cfg or cfg.no_duration_last ~= false

    sort(auras, function(a, b)
        if noDurationLast and a.noDuration ~= b.noDuration then
            return not a.noDuration
        end
        if method == "mine_first" and a.isMine ~= b.isMine then
            return a.isMine
        end
        if method == "index" and a.auraType ~= b.auraType then
            return a.auraType == "buff"
        end

        local av = AuraSortValue(a, method)
        local bv = AuraSortValue(b, method)
        if av ~= bv then
            if method == "time_desc" or method == "duration_desc" then return av > bv end
            return av < bv
        end
        if a.auraType ~= b.auraType then return a.auraType == "buff" end
        return (a.index or 0) < (b.index or 0)
    end)
end

local function CollectConfiguredAuras(unit, configKey, cfg, combine)
    local buffs = {}
    local debuffs = {}
    if cfg and cfg.show_buffs ~= false then
        buffs = ScanAuraType(unit, configKey, "HELPFUL", "buff", cfg)
        SortAuras(buffs, cfg)
    end
    if cfg and cfg.show_debuffs ~= false then
        debuffs = ScanAuraType(unit, configKey, "HARMFUL", "debuff", cfg)
        SortAuras(debuffs, cfg)
    end

    local maxBuffs = max(0, tonumber(cfg and cfg.max_buffs) or #buffs)
    local maxDebuffs = max(0, tonumber(cfg and cfg.max_debuffs) or #debuffs)
    while #buffs > maxBuffs do table.remove(buffs) end
    while #debuffs > maxDebuffs do table.remove(debuffs) end

    if not combine then return buffs, debuffs end
    local combined = {}
    for i = 1, #buffs do combined[#combined + 1] = buffs[i] end
    for i = 1, #debuffs do combined[#combined + 1] = debuffs[i] end
    SortAuras(combined, cfg)
    return combined
end

local function SetDesaturated(texture, enabled)
    if not texture then return end
    if texture.SetDesaturated then
        texture:SetDesaturated(enabled and true or false)
    elseif _G.SetDesaturation then
        _G.SetDesaturation(texture, enabled and 1 or nil)
    end
end

local function GetColor(color, fallbackR, fallbackG, fallbackB)
    if color and color.r then return color.r, color.g, color.b end
    return fallbackR, fallbackG, fallbackB
end

local function GetColorAlpha(color, fallbackR, fallbackG, fallbackB, fallbackA)
    if color and color.r then
        return color.r, color.g, color.b, color.a == nil and fallbackA or color.a
    end
    return fallbackR, fallbackG, fallbackB, fallbackA
end

local function GetSharedMedia()
    if not (_G.LibStub and _G.LibStub.GetLibrary) then return nil end
    local ok, media = pcall(_G.LibStub.GetLibrary, _G.LibStub, "LibSharedMedia-3.0", true)
    if ok then return media end
    return nil
end

local function RegisterAuraMedia()
    local media = GetSharedMedia()
    if not media then return nil end

    if not AuraCustomizationModule.mediaRegistered then
        AuraCustomizationModule.mediaRegistered = true
        for mediaType, entries in pairs(AURA_MEDIA) do
            for name, path in pairs(entries) do
                pcall(media.Register, media, mediaType, name, path)
            end
        end
    end

    if not AuraCustomizationModule.mediaCallbackRegistered and media.RegisterCallback then
        local registered = pcall(media.RegisterCallback, AuraCustomizationModule, "LibSharedMedia_Registered",
            function(_, mediaType)
                if AuraCustomizationModule.applied
                    and (mediaType == "statusbar" or mediaType == "border" or mediaType == "font") then
                    for i = 1, #BAR_UNIT_KEYS do
                        AuraCustomizationModule:RefreshBars(BAR_UNIT_KEYS[i])
                    end
                end
            end)
        AuraCustomizationModule.mediaCallbackRegistered = registered
    end
    return media
end

local function ResolveAuraMedia(mediaType, name, fallbackName)
    if name == "__none__" then return nil end
    local builtins = AURA_MEDIA[mediaType]
    if builtins and builtins[name] then return builtins[name] end

    local media = RegisterAuraMedia()
    if media and media.Fetch and name then
        local ok, path = pcall(media.Fetch, media, mediaType, name, true)
        if ok and path then return path end
    end
    return builtins and builtins[fallbackName] or nil
end

local function GetAuraBackdrop(edgeFile, edgeSize, inset)
    edgeSize = max(1, tonumber(edgeSize) or 1)
    inset = max(0, tonumber(inset) or 0)
    local key = tostring(edgeFile or "none") .. ":" .. edgeSize .. ":" .. inset
    local backdrop = backdropCache[key]
    if not backdrop then
        backdrop = {
            bgFile = WHITE_TEXTURE,
            edgeFile = edgeFile,
            tile = false,
            edgeSize = edgeSize,
            insets = { left = inset, right = inset, top = inset, bottom = inset },
        }
        backdropCache[key] = backdrop
    end
    return backdrop
end

function addon.GetAuraCustomizationMediaChoices(mediaType)
    local values = {}
    for name in pairs(AURA_MEDIA[mediaType] or {}) do values[name] = name end

    local media = RegisterAuraMedia()
    local mediaTable = media and media.HashTable and media:HashTable(mediaType)
    if mediaTable then
        for name in pairs(mediaTable) do values[name] = name end
    end
    return values
end

local function FormatTime(seconds)
    seconds = max(0, seconds or 0)
    if seconds < 5 then return format("%.1f", seconds) end
    if seconds < 60 then return tostring(ceil(seconds)) end
    if seconds < 3600 then return format("%dm", ceil(seconds / 60)) end
    if seconds < 86400 then return format("%dh", ceil(seconds / 3600)) end
    return format("%dd", ceil(seconds / 86400))
end

-- ============================================================================
-- Optional filtering of Blizzard's standalone minimap aura frame
-- ============================================================================

local function GetStockButtonRegions(button)
    if not button or not button.GetName then return end
    local name = button:GetName()
    if not name then return end
    return _G[name .. "Icon"] or button.icon,
        _G[name .. "Count"] or button.count,
        _G[name .. "Cooldown"] or button.cooldown or button.cd,
        _G[name .. "Border"] or button.border,
        _G[name .. "Stealable"] or button.stealable,
        _G[name .. "Duration"] or button.duration
end

local function ApplyOwnershipStyle(button, icon, aura, cfg, isUnitFrame)
    local desaturate = aura and not aura.isMine and cfg and cfg.other_style == "desaturate"
    local r, g, b
    if desaturate then r, g, b = GetColor(cfg.other_color, 0.55, 0.55, 0.55) end
    if addon.RefreshFilteredAuraBorder then
        addon.RefreshFilteredAuraBorder(button, aura and aura.auraType == "debuff", isUnitFrame, r, g, b)
    end
    SetDesaturated(icon, desaturate)
    if desaturate then icon:SetVertexColor(r, g, b, 1) else icon:SetVertexColor(1, 1, 1, 1) end
end

local function ResetStockButtonVisual(button)
    local icon = GetStockButtonRegions(button)
    if icon then
        SetDesaturated(icon, false)
        icon:SetVertexColor(1, 1, 1, 1)
    end
    if button then
        button.consolidated = nil
        if button.symbol then button.symbol:Hide() end
    end
end

local function ApplyAuraToStockButton(button, aura, cfg)
    if not button or not aura then return false end
    local icon, countText, cooldown, border, _, durationText = GetStockButtonRegions(button)
    if not icon then return false end

    button.unit = aura.unit
    button.filter = aura.filter
    button.index = aura.index
    button.id = aura.index
    button.consolidated = nil
    if button.SetID then button:SetID(aura.index) end
    icon:SetTexture(aura.icon)

    if border and aura.auraType == "debuff" then
        local color = DebuffTypeColor and (DebuffTypeColor[aura.debuffType or "none"] or DebuffTypeColor.none)
        if color then border:SetVertexColor(color.r, color.g, color.b) end
    end
    ApplyOwnershipStyle(button, icon, aura, cfg, false)

    if countText then
        if (aura.count or 0) > 1 then
            countText:SetText(aura.count)
            countText:Show()
        else
            countText:SetText("")
            countText:Hide()
        end
    end

    if cooldown then
        local duration = aura.noDuration and 0 or aura.duration
        local start = duration > 0 and (aura.expirationTime - duration) or 0
        if duration > 0 and cooldown.SetCooldown then
            cooldown:SetCooldown(start, duration)
            cooldown:Show()
        else
            if cooldown.SetCooldown then cooldown:SetCooldown(0, 0) end
            cooldown:Hide()
        end
    end

    if durationText then
        if not aura.noDuration then
            local remaining = aura.expirationTime - GetTime()
            if _G.securecall and _G.AuraButton_UpdateDuration then
                _G.securecall("AuraButton_UpdateDuration", button, remaining)
            else
                durationText:SetText(FormatTime(remaining))
                if _G.SHOW_BUFF_DURATIONS == "1" then durationText:Show() else durationText:Hide() end
            end
            button.timeLeft = remaining
            button.exitTime = nil
            button:SetAlpha(1)
            if _G.AuraButton_OnUpdate then button:SetScript("OnUpdate", _G.AuraButton_OnUpdate) end
        else
            durationText:SetText("")
            durationText:Hide()
            button.timeLeft = nil
            button.exitTime = nil
            button:SetScript("OnUpdate", nil)
        end
    end

    button:Show()
    return true
end

local function RenderStockButtonGroup(prefix, auras, absoluteMax, cfg)
    for slot = 1, absoluteMax do
        local button = _G[prefix .. slot]
        if button then
            local displayed = slot <= #auras and ApplyAuraToStockButton(button, auras[slot], cfg)
            if not displayed then
                ResetStockButtonVisual(button)
                button.timeLeft = nil
                button.exitTime = nil
                button:SetScript("OnUpdate", nil)
                button:Hide()
            end
        end
    end
end

local function RenderBlizzardAuraFrame(cfg)
    local unit = ResolvePlayerAuraUnit()
    local buffs, debuffs = CollectConfiguredAuras(unit, "buffframe", cfg, false)
    if addon.db and addon.db.profile and addon.db.profile.buffs and addon.db.profile.buffs.buffs_hidden then
        buffs = {}
    end

    RenderStockButtonGroup("BuffButton", buffs, MAX_PLAYER_BUFFS, cfg)
    RenderStockButtonGroup("DebuffButton", debuffs, MAX_PLAYER_DEBUFFS, cfg)
    if BuffFrame then BuffFrame.numConsolidated = 0 end
    if _G.ConsolidatedBuffs then _G.ConsolidatedBuffs:Hide() end
    if _G.ConsolidatedBuffsTooltip then _G.ConsolidatedBuffsTooltip:Hide() end
    if _G.BuffFrame_UpdateAllBuffAnchors then _G.BuffFrame_UpdateAllBuffAnchors() end
    AuraCustomizationModule.standardActive.buffframe = true
end

local function RestoreBlizzardAuraFrame()
    if not AuraCustomizationModule.standardActive.buffframe then return end
    AuraCustomizationModule.standardActive.buffframe = nil
    AuraCustomizationModule.restoring = true
    for i = 1, MAX_PLAYER_BUFFS do ResetStockButtonVisual(_G["BuffButton" .. i]) end
    for i = 1, MAX_PLAYER_DEBUFFS do ResetStockButtonVisual(_G["DebuffButton" .. i]) end
    if _G.BuffFrame_Update then _G.BuffFrame_Update() end
    AuraCustomizationModule.restoring = false
end

-- ============================================================================
-- Unit-frame attached aura icons
-- ============================================================================

local function GetAttachmentPoints(anchor)
    if anchor == "TOP" then return "BOTTOM", "TOP" end
    if anchor == "TOPRIGHT" then return "BOTTOMRIGHT", "TOPRIGHT" end
    if anchor == "RIGHT" then return "LEFT", "RIGHT" end
    if anchor == "BOTTOMRIGHT" then return "TOPRIGHT", "BOTTOMRIGHT" end
    if anchor == "BOTTOM" then return "TOP", "BOTTOM" end
    if anchor == "BOTTOMLEFT" then return "TOPLEFT", "BOTTOMLEFT" end
    if anchor == "LEFT" then return "RIGHT", "LEFT" end
    if anchor == "CENTER" then return "CENTER", "CENTER" end
    return "BOTTOMLEFT", "TOPLEFT"
end

local function ApplySafeStrata(frame, owner)
    local strata = owner and owner.GetFrameStrata and owner:GetFrameStrata()
    frame:SetFrameStrata(VALID_STRATA[strata] and strata or "MEDIUM")
end

local function OnAttachedAuraEnter(self)
    local aura = self.aura
    if not aura then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if aura.auraType == "debuff" and GameTooltip.SetUnitDebuff then
        GameTooltip:SetUnitDebuff(aura.unit, aura.index, aura.queryFilter)
    elseif aura.auraType == "buff" and GameTooltip.SetUnitBuff then
        GameTooltip:SetUnitBuff(aura.unit, aura.index, aura.queryFilter)
    elseif GameTooltip.SetUnitAura then
        GameTooltip:SetUnitAura(aura.unit, aura.index, aura.filter)
    end
end

local function OnAuraLeave()
    GameTooltip:Hide()
end

local function OnAttachedAuraClick(self, button)
    local aura = self.aura
    if button == "RightButton" and aura and (aura.unit == "player" or aura.unit == "vehicle")
        and aura.auraType == "buff" and _G.CancelUnitBuff then
        _G.CancelUnitBuff(aura.unit, aura.index, aura.filter)
    end
end

local function CreateAttachedAuraButton(state, slot)
    local buttonName = "DragonUI_AttachedAura_" .. state.descriptor.id .. "_" .. slot
    local button = CreateFrame("Button", buttonName, state.root)
    button._duiAttachedAura = true
    button:SetBackdrop(BACKDROP)
    button:SetBackdropColor(0, 0, 0, 0.85)
    button:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)
    button:SetScript("OnEnter", OnAttachedAuraEnter)
    button:SetScript("OnLeave", OnAuraLeave)
    button:RegisterForClicks("RightButtonUp")
    button:SetScript("OnClick", OnAttachedAuraClick)

    local icon = button:CreateTexture(buttonName .. "Icon", "ARTWORK")
    icon:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
    button.icon = icon

    local cooldown = CreateFrame("Cooldown", buttonName .. "Cooldown", button, "CooldownFrameTemplate")
    cooldown:SetAllPoints(button)
    cooldown:SetFrameLevel(button:GetFrameLevel() + 1)
    button.cooldown = cooldown

    local count = button:CreateFontString(buttonName .. "Count", "OVERLAY")
    count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    count:SetJustifyH("RIGHT")
    button.count = count

    local duration = button:CreateFontString(buttonName .. "Duration", "OVERLAY")
    duration:SetPoint("TOP", button, "BOTTOM", 0, -1)
    duration:SetJustifyH("CENTER")
    button.durationText = duration

    state.buttons[slot] = button
    return button
end

local function GetAttachedBorderColor(aura, cfg)
    if not aura.isMine and cfg.other_style == "desaturate" then
        return GetColor(cfg.other_color, 0.55, 0.55, 0.55)
    end
    if aura.auraType == "debuff" and DebuffTypeColor then
        local color = DebuffTypeColor[aura.debuffType or "none"] or DebuffTypeColor.none
        if color then return color.r, color.g, color.b end
    end
    local borderCfg = addon:GetModuleConfig("auraborders")
    return GetColor(borderCfg and borderCfg.buff_color, 0.2, 0.2, 0.2)
end

local function ApplyAuraToAttachedButton(button, aura, cfg)
    button.aura = aura
    local size = aura.auraType == "debuff" and (tonumber(cfg.debuff_size) or 17)
        or (tonumber(cfg.buff_size) or 17)
    size = max(8, size)
    button:SetSize(size, size)
    button.icon:SetTexture(aura.icon)

    local desaturate = not aura.isMine and cfg.other_style == "desaturate"
    local tintR, tintG, tintB = GetColor(cfg.other_color, 0.55, 0.55, 0.55)
    SetDesaturated(button.icon, desaturate)
    if desaturate then
        button.icon:SetVertexColor(tintR, tintG, tintB, 1)
    else
        button.icon:SetVertexColor(1, 1, 1, 1)
    end

    local borderR, borderG, borderB = GetAttachedBorderColor(aura, cfg)
    local bordersEnabled = addon:IsModuleEnabled("auraborders")
    button._duiFallbackBorderColor = { borderR, borderG, borderB }
    button:SetBackdropBorderColor(borderR, borderG, borderB, bordersEnabled and 0 or 1)
    if addon.RefreshFilteredAuraBorder then
        local appliedR = desaturate and tintR or borderR
        local appliedG = desaturate and tintG or borderG
        local appliedB = desaturate and tintB or borderB
        addon.RefreshFilteredAuraBorder(button, aura.auraType == "debuff", true,
            appliedR, appliedG, appliedB)
    end

    local fontPath = (addon.Fonts and addon.Fonts.NARROW) or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    local countSize = max(8, min(18, floor(size * 0.55)))
    button.count:SetFont(fontPath, countSize, "OUTLINE")
    if (aura.count or 0) > 1 then
        button.count:SetText(aura.count)
        button.count:Show()
    else
        button.count:SetText("")
        button.count:Hide()
    end

    local durationValue = aura.noDuration and 0 or aura.duration
    local start = durationValue > 0 and aura.expirationTime - durationValue or 0
    if cfg.show_cooldown ~= false and durationValue > 0 and button.cooldown.SetCooldown then
        button.cooldown:SetCooldown(start, durationValue)
        button.cooldown:Show()
    else
        if button.cooldown.SetCooldown then button.cooldown:SetCooldown(0, 0) end
        button.cooldown:Hide()
    end

    button.durationText:SetFont(fontPath, max(6, tonumber(cfg.duration_font_size) or 10), "OUTLINE")
    if cfg.show_duration ~= false and durationValue > 0 then
        button.durationText:SetText(FormatTime(aura.expirationTime - GetTime()))
        button.durationText:Show()
    else
        button.durationText:SetText("")
        button.durationText:Hide()
    end
    button:Show()
end

local function EnsureAttachedState(descriptor)
    local owner = _G[descriptor.frameName]
    if not owner then return nil end

    local state = AuraCustomizationModule.attachedFrames[descriptor.id]
    if state then
        if state.root:GetParent() ~= owner then state.root:SetParent(owner) end
        state.owner = owner
        return state
    end

    local rootName = "DragonUI_AttachedAuras_" .. descriptor.id
    local root = CreateFrame("Frame", rootName, owner)
    root:SetSize(20, 20)
    root:EnableMouse(false)
    root:SetFrameLevel(owner:GetFrameLevel() + 20)
    ApplySafeStrata(root, owner)
    root:Hide()

    state = { descriptor = descriptor, owner = owner, root = root, buttons = {} }
    AuraCustomizationModule.attachedFrames[descriptor.id] = state

    if owner.HookScript and not owner["_duiAuraShowHook_" .. descriptor.id] then
        owner:HookScript("OnShow", function()
            if AuraCustomizationModule.applied then
                AuraCustomizationModule:RefreshStandard(descriptor.configKey)
            end
        end)
        owner["_duiAuraShowHook_" .. descriptor.id] = true
    end
    return state
end

local function HideStockButtons(descriptor)
    if not descriptor.stockPrefix then return end
    for i = 1, descriptor.stockBuffs or 0 do
        local button = _G[descriptor.stockPrefix .. "Buff" .. i]
        if button then button:Hide() end
    end
    for i = 1, descriptor.stockDebuffs or 0 do
        local button = _G[descriptor.stockPrefix .. "Debuff" .. i]
        if button then button:Hide() end
    end
end

local function ClearStockAuraLayoutReservation(descriptor)
    if descriptor.configKey ~= "target" and descriptor.configKey ~= "focus"
        and descriptor.configKey ~= "boss" then
        return
    end

    local owner = _G[descriptor.frameName]
    if not owner then return end
    owner.auraRows = 0
    owner.spellbarAnchor = nil
    if owner.spellbar and _G.Target_Spellbar_AdjustPosition then
        _G.Target_Spellbar_AdjustPosition(owner.spellbar)
    end
end

local function RestoreStockButtons(descriptor)
    if not descriptor.stockPrefix then return end
    local owner = _G[descriptor.frameName]
    if not owner then return end

    AuraCustomizationModule.restoring = true
    if (descriptor.configKey == "target" or descriptor.configKey == "focus" or descriptor.configKey == "boss")
        and _G.TargetFrame_UpdateAuras then
        _G.TargetFrame_UpdateAuras(owner)
    elseif descriptor.configKey == "party" and _G.PartyMemberFrame_UpdateMember then
        _G.PartyMemberFrame_UpdateMember(owner)
    elseif descriptor.configKey == "arena" and _G.ArenaEnemyFrame_Update then
        _G.ArenaEnemyFrame_Update(owner)
    elseif (descriptor.configKey == "tot" or descriptor.configKey == "fot")
        and _G.TargetofTarget_Update then
        _G.TargetofTarget_Update(owner)
    end
    AuraCustomizationModule.restoring = false
end

local function PositionAttachedState(state, cfg)
    local root = state.root
    local owner = state.owner
    local rootPoint, ownerPoint = GetAttachmentPoints(cfg.anchor or "BOTTOMLEFT")
    root:ClearAllPoints()
    root:SetPoint(rootPoint, owner, ownerPoint, tonumber(cfg.offset_x) or 0, tonumber(cfg.offset_y) or 0)
    root:SetScale(max(0.25, tonumber(cfg.scale) or 1))
    root:SetFrameLevel(owner:GetFrameLevel() + 20)
    ApplySafeStrata(root, owner)
end

local function RenderAttachedDescriptor(descriptor, cfg)
    local state = EnsureAttachedState(descriptor)
    if not state then return end
    local unit = ResolveDescriptorUnit(descriptor)
    if not UnitExists(unit) then
        state.root:Hide()
        HideStockButtons(descriptor)
        ClearStockAuraLayoutReservation(descriptor)
        return
    end

    local auras = CollectConfiguredAuras(unit, descriptor.configKey, cfg, true)
    PositionAttachedState(state, cfg)

    local maxSize = max(8, tonumber(cfg.buff_size) or 17, tonumber(cfg.debuff_size) or 17)
    state.root:SetSize(maxSize, maxSize)
    local perRow = max(1, floor(tonumber(cfg.per_row) or 8))
    local stepX = maxSize + max(0, tonumber(cfg.spacing_x) or 2)
    local stepY = maxSize + max(0, tonumber(cfg.spacing_y) or 2)
    local xSign = cfg.growth_x == "LEFT" and -1 or 1
    local ySign = cfg.growth_y == "UP" and 1 or -1

    for slot = 1, #auras do
        local button = state.buttons[slot] or CreateAttachedAuraButton(state, slot)
        local column = (slot - 1) % perRow
        local row = floor((slot - 1) / perRow)
        button:ClearAllPoints()
        button:SetPoint("CENTER", state.root, "CENTER", column * stepX * xSign, row * stepY * ySign)
        ApplyAuraToAttachedButton(button, auras[slot], cfg)
    end
    for slot = #auras + 1, #state.buttons do
        state.buttons[slot].aura = nil
        state.buttons[slot]:Hide()
    end

    HideStockButtons(descriptor)
    ClearStockAuraLayoutReservation(descriptor)
    AuraCustomizationModule.standardActive[descriptor.id] = true
    if #auras > 0 then state.root:Show() else state.root:Hide() end
end

local function RestoreAttachedDescriptor(descriptor)
    local state = AuraCustomizationModule.attachedFrames[descriptor.id]
    if state then
        state.root:Hide()
        for i = 1, #state.buttons do
            state.buttons[i].aura = nil
            state.buttons[i]:Hide()
        end
    end
    if AuraCustomizationModule.standardActive[descriptor.id] then
        AuraCustomizationModule.standardActive[descriptor.id] = nil
        RestoreStockButtons(descriptor)
    end
end

local function RefreshAttachedFamily(configKey)
    local cfg = GetDisplayConfig("icons", configKey)
    for i = 1, #ATTACHED_DESCRIPTORS do
        local descriptor = ATTACHED_DESCRIPTORS[i]
        if descriptor.configKey == configKey then
            if AuraCustomizationModule.applied and cfg and cfg.enabled == true then
                RenderAttachedDescriptor(descriptor, cfg)
            else
                RestoreAttachedDescriptor(descriptor)
            end
        end
    end
end

-- ============================================================================
-- Independent aura bars (player / target / focus only)
-- ============================================================================

local function OnAuraBarEnter(self)
    OnAttachedAuraEnter(self)
end

local function OnAuraBarClick(self, button)
    local aura = self.aura
    if button == "RightButton" and aura and (aura.unit == "player" or aura.unit == "vehicle")
        and aura.auraType == "buff" and _G.CancelUnitBuff then
        _G.CancelUnitBuff(aura.unit, aura.index, aura.filter)
    end
end

local function CreateAuraBarRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetBackdrop(BACKDROP)
    row:SetBackdropColor(0.03, 0.03, 0.03, 0.92)
    row:SetBackdropBorderColor(0, 0, 0, 1)
    row:RegisterForClicks("RightButtonUp")
    row:SetScript("OnEnter", OnAuraBarEnter)
    row:SetScript("OnLeave", OnAuraLeave)
    row:SetScript("OnClick", OnAuraBarClick)

    local iconHolder = CreateFrame("Frame", nil, row)
    iconHolder:SetBackdrop(BACKDROP)
    iconHolder:SetBackdropColor(0, 0, 0, 1)
    iconHolder:SetBackdropBorderColor(0, 0, 0, 1)
    row.iconHolder = iconHolder

    local icon = iconHolder:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", iconHolder, "TOPLEFT", 1, -1)
    icon:SetPoint("BOTTOMRIGHT", iconHolder, "BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
    row.icon = icon

    local bar = CreateFrame("StatusBar", nil, row)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    row.bar = bar

    local background = bar:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(bar)
    background:SetTexture("Interface\\Buttons\\WHITE8X8")
    background:SetVertexColor(0.05, 0.05, 0.05, 0.9)
    row.background = background

    local nameText = bar:CreateFontString(nil, "OVERLAY")
    nameText:SetPoint("LEFT", bar, "LEFT", 3, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    row.nameText = nameText

    local timeText = bar:CreateFontString(nil, "OVERLAY")
    timeText:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
    timeText:SetJustifyH("RIGHT")
    row.timeText = timeText
    nameText:SetPoint("RIGHT", timeText, "LEFT", -5, 0)
    return row
end

local function GetBarColor(aura, cfg)
    if not aura.isMine and cfg.other_style == "desaturate" then
        return GetColor(cfg.other_color, 0.45, 0.45, 0.45)
    end
    if aura.auraType == "debuff" then
        if cfg.debuff_type_color ~= false and DebuffTypeColor then
            local color = DebuffTypeColor[aura.debuffType or "none"] or DebuffTypeColor.none
            if color then return color.r, color.g, color.b end
        end
        return GetColor(cfg.debuff_color, 0.8, 0.1, 0.1)
    end
    return GetColor(cfg.buff_color, 0.2, 0.55, 1)
end

local function LayoutAuraBarRow(row, cfg)
    local width = max(40, tonumber(cfg.width) or 250)
    local height = max(8, tonumber(cfg.height) or 18)
    local showIcon = cfg.show_icon ~= false
    local iconSide = cfg.icon_side or "LEFT"
    local iconGap = showIcon and 2 or 0

    row:SetSize(width, height)
    row.iconHolder:ClearAllPoints()
    row.bar:ClearAllPoints()
    if showIcon then
        row.iconHolder:SetSize(height, height)
        row.iconHolder:Show()
        if iconSide == "RIGHT" then
            row.iconHolder:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
            row.bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
            row.bar:SetPoint("BOTTOMRIGHT", row.iconHolder, "BOTTOMLEFT", -iconGap, 0)
        else
            row.iconHolder:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
            row.bar:SetPoint("TOPLEFT", row.iconHolder, "TOPRIGHT", iconGap, 0)
            row.bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
        end
    else
        row.iconHolder:Hide()
        row.bar:SetAllPoints(row)
    end

    local statusbarTexture = ResolveAuraMedia("statusbar", cfg.texture, "Blizzard")
    local backgroundName = cfg.background_texture == "__same__" and cfg.texture or cfg.background_texture
    local backgroundTexture = ResolveAuraMedia("statusbar", backgroundName, "Flat")
    row.bar:SetStatusBarTexture(statusbarTexture)
    row.background:SetTexture(backgroundTexture)
    row.background:SetVertexColor(GetColorAlpha(cfg.background_color, 0.05, 0.05, 0.05, 0.90))

    local borderTexture = ResolveAuraMedia("border", cfg.border_texture, "DragonUI 1 Pixel")
    row:SetBackdrop(GetAuraBackdrop(borderTexture, cfg.border_size, cfg.border_inset))
    row:SetBackdropColor(0, 0, 0, 0)
    row:SetBackdropBorderColor(GetColorAlpha(cfg.border_color, 0, 0, 0, 1))

    local iconBorderTexture = ResolveAuraMedia("border", cfg.icon_border_texture, "DragonUI 1 Pixel")
    row.iconHolder:SetBackdrop(GetAuraBackdrop(iconBorderTexture, cfg.icon_border_size, cfg.icon_border_inset))
    row.iconHolder:SetBackdropColor(0, 0, 0, 1)

    local fontPath = ResolveAuraMedia("font", cfg.font, "DragonUI Narrow")
    local fontSize = max(6, tonumber(cfg.font_size) or 10)
    local outline = cfg.text_outline or "OUTLINE"
    if outline == "NONE" then outline = "" end
    row.nameText:SetFont(fontPath, fontSize, outline)
    row.timeText:SetFont(fontPath, fontSize, outline)
    local textR, textG, textB, textA = GetColorAlpha(cfg.text_color, 1, 1, 1, 1)
    row.nameText:SetTextColor(textR, textG, textB, textA)
    row.timeText:SetTextColor(textR, textG, textB, textA)
end

local function ApplyAuraToBarRow(row, aura, cfg)
    row.aura = aura
    LayoutAuraBarRow(row, cfg)
    row.icon:SetTexture(aura.icon)
    local desaturate = not aura.isMine and cfg.other_style == "desaturate"
    SetDesaturated(row.icon, desaturate)
    if desaturate then
        row.icon:SetVertexColor(GetColor(cfg.other_color, 0.45, 0.45, 0.45))
    else
        row.icon:SetVertexColor(1, 1, 1, 1)
    end

    local countSuffix = (aura.count or 0) > 1 and format(" [%d]", aura.count) or ""
    row.nameText:SetText((aura.name or "") .. countSuffix)
    if aura.noDuration then
        row.bar:SetMinMaxValues(0, 1)
        row.bar:SetValue(1)
        row.timeText:SetText("")
    else
        local remaining = max(0, aura.expirationTime - GetTime())
        row.bar:SetMinMaxValues(0, max(0.1, aura.duration))
        row.bar:SetValue(remaining)
        row.timeText:SetText(FormatTime(remaining))
    end

    local r, g, b = GetBarColor(aura, cfg)
    row.bar:SetStatusBarColor(r, g, b)
    local borderR, borderG, borderB, borderA
    if cfg.icon_border_mode == "border" then
        borderR, borderG, borderB, borderA = GetColorAlpha(cfg.border_color, 0, 0, 0, 1)
    elseif cfg.icon_border_mode == "custom" then
        borderR, borderG, borderB, borderA = GetColorAlpha(cfg.icon_border_color, 0, 0, 0, 1)
    else
        borderR, borderG, borderB, borderA = r, g, b, 1
    end
    row.iconHolder:SetBackdropBorderColor(borderR, borderG, borderB, borderA)
    row:Show()
end

local function BuildPreviewAuras(unitKey)
    local now = GetTime()
    return {
        { unit = unitKey, index = 1, filter = "HELPFUL", auraType = "buff", name = "Wild Growth",
            icon = "Interface\\Icons\\Ability_Druid_Flourish", count = 1, duration = 12,
            expirationTime = now + 8.4, isMine = true, noDuration = false, spellID = 48438 },
        { unit = unitKey, index = 2, filter = "HELPFUL", auraType = "buff", name = "Resounding Protection",
            icon = "Interface\\Icons\\Spell_Holy_PowerWordShield", count = 1, duration = 15,
            expirationTime = now + 12, isMine = false, noDuration = false, spellID = 269279 },
        { unit = unitKey, index = 1, filter = "HARMFUL", auraType = "debuff", name = "Shadow Word: Pain",
            icon = "Interface\\Icons\\Spell_Shadow_ShadowWordPain", count = 1, debuffType = "Magic", duration = 18,
            expirationTime = now + 6.5, isMine = true, noDuration = false, spellID = 48125 },
        { unit = unitKey, index = 2, filter = "HARMFUL", auraType = "debuff", name = "Weakened Soul",
            icon = "Interface\\Icons\\Spell_Holy_AshesToAshes", count = 1, debuffType = "Magic", duration = 15,
            expirationTime = now + 3.4, isMine = false, noDuration = false, spellID = 6788 },
    }
end

local function FilterPreviewAuras(unitKey, cfg)
    local result = {}
    local preview = BuildPreviewAuras(unitKey)
    for i = 1, #preview do
        local aura = preview[i]
        local typeEnabled = aura.auraType == "buff" and cfg.show_buffs ~= false
            or aura.auraType == "debuff" and cfg.show_debuffs ~= false
        if typeEnabled and ShouldIncludeAura(aura, cfg) then result[#result + 1] = aura end
    end
    SortAuras(result, cfg)
    return result
end

local function EnsureBarFrame(unitKey)
    local state = AuraCustomizationModule.barFrames[unitKey]
    if state then return state end

    local cfg = GetDisplayConfig("bars", unitKey) or {}
    local frameName = BAR_FRAME_NAMES[unitKey]
    local widgetKey = BAR_WIDGET_KEYS[unitKey]
    local anchor = addon.CreateUIFrame(max(40, cfg.width or 250), max(8, cfg.height or 18), frameName)
    anchor:SetFrameStrata("MEDIUM")
    anchor:SetFrameLevel(30)
    addon.ApplyWidgetPositionFromDB(widgetKey, anchor)

    state = { anchor = anchor, rows = {}, unit = unitKey }
    AuraCustomizationModule.barFrames[unitKey] = state

    addon:RegisterEditableFrame({
        name = widgetKey,
        frame = anchor,
        configPath = { "widgets", widgetKey },
        editorVisible = function()
            local barCfg = GetDisplayConfig("bars", unitKey)
            return barCfg and barCfg.enabled == true
        end,
        showTest = function()
            AuraCustomizationModule.preview[unitKey] = true
            anchor._duiAuraEditorPrepared = true
            anchor:SetFrameStrata("FULLSCREEN")
            AuraCustomizationModule:RefreshBars(unitKey)
        end,
        hideTest = function()
            AuraCustomizationModule.preview[unitKey] = nil
            anchor._duiAuraEditorPrepared = nil
            anchor:SetFrameStrata("MEDIUM")
            AuraCustomizationModule:RefreshBars(unitKey)
        end,
        onShow = function()
            anchor._duiAuraEditorPrepared = true
            anchor:SetFrameStrata("FULLSCREEN")
        end,
        onHide = function()
            anchor._duiAuraEditorPrepared = nil
            anchor:SetFrameStrata("MEDIUM")
        end,
        onNudge = function()
            AuraCustomizationModule:RefreshBars(unitKey)
        end,
        module = AuraCustomizationModule,
    })

    anchor:Hide()
    return state
end

function AuraCustomizationModule:RefreshBars(unitKey)
    local cfg = GetDisplayConfig("bars", unitKey)
    local state = EnsureBarFrame(unitKey)
    if not self.applied or not cfg or cfg.enabled ~= true then
        state.anchor:Hide()
        for i = 1, #state.rows do state.rows[i]:Hide() end
        return
    end

    local editorPreview = self.preview[unitKey] or IsEditorActive()
    local unit = ResolveBarUnit(unitKey)
    local auras
    if editorPreview then
        auras = FilterPreviewAuras(unitKey, cfg)
        if not state.anchor._duiAuraEditorPrepared and addon.HideUIFrame then
            addon.HideUIFrame(state.anchor)
            state.anchor._duiAuraEditorPrepared = true
        end
        state.anchor:SetFrameStrata("FULLSCREEN")
    elseif UnitExists(unit) then
        auras = CollectConfiguredAuras(unit, unitKey, cfg, true)
        state.anchor:SetFrameStrata("MEDIUM")
    else
        auras = {}
    end

    local maxBars = max(1, tonumber(cfg.max_bars) or 8)
    local shown = min(#auras, maxBars)
    local width = max(40, tonumber(cfg.width) or 250)
    local height = max(8, tonumber(cfg.height) or 18)
    local spacing = max(0, tonumber(cfg.spacing) or 2)
    local growth = cfg.growth or "DOWN"
    state.anchor:SetSize(width, height)
    state.anchor:SetScale(max(0.25, tonumber(cfg.scale) or 1))

    for i = 1, shown do
        local row = state.rows[i]
        if not row then
            row = CreateAuraBarRow(state.anchor)
            state.rows[i] = row
        end
        ApplyAuraToBarRow(row, auras[i], cfg)
        row:EnableMouse(not editorPreview)
        row:ClearAllPoints()
        if i == 1 then
            row:SetPoint(growth == "UP" and "BOTTOM" or "TOP", state.anchor,
                growth == "UP" and "BOTTOM" or "TOP", 0, 0)
        elseif growth == "UP" then
            row:SetPoint("BOTTOM", state.rows[i - 1], "TOP", 0, spacing)
        else
            row:SetPoint("TOP", state.rows[i - 1], "BOTTOM", 0, -spacing)
        end
    end
    for i = shown + 1, #state.rows do
        state.rows[i].aura = nil
        state.rows[i]:Hide()
    end
    if shown > 0 or editorPreview then state.anchor:Show() else state.anchor:Hide() end
end

-- ============================================================================
-- Public refresh API and lifecycle
-- ============================================================================

function AuraCustomizationModule:RefreshStandard(unitKey)
    if unitKey == "buffframe" then
        local cfg = GetDisplayConfig("icons", "buffframe")
        if self.applied and cfg and cfg.enabled == true then
            RenderBlizzardAuraFrame(cfg)
        else
            RestoreBlizzardAuraFrame()
        end
        return
    end
    RefreshAttachedFamily(unitKey)
end

function AuraCustomizationModule:RefreshStandardAll()
    for i = 1, #ICON_UNIT_KEYS do self:RefreshStandard(ICON_UNIT_KEYS[i]) end
end

function AuraCustomizationModule:RefreshUnit(unitKey)
    self:RefreshStandard(unitKey)
    if BAR_FRAME_NAMES[unitKey] then self:RefreshBars(unitKey) end
end

function AuraCustomizationModule:RefreshAll()
    self:RefreshStandardAll()
    for i = 1, #BAR_UNIT_KEYS do self:RefreshBars(BAR_UNIT_KEYS[i]) end
end

function addon.IsAuraIconFilteringEnabled(unitKey)
    if not AuraCustomizationModule.applied or AuraCustomizationModule.restoring then return false end
    local cfg = GetDisplayConfig("icons", unitKey)
    return cfg and cfg.enabled == true or false
end

local function UpdateVisibleTimers()
    local now = GetTime()
    local refreshFamilies = {}

    for _, state in pairs(AuraCustomizationModule.attachedFrames) do
        local cfg = GetDisplayConfig("icons", state.descriptor.configKey)
        for i = 1, #state.buttons do
            local button = state.buttons[i]
            local aura = button.aura
            if button:IsShown() and aura and not aura.noDuration then
                local remaining = max(0, aura.expirationTime - now)
                if cfg and cfg.show_duration ~= false then
                    button.durationText:SetText(FormatTime(remaining))
                    button.durationText:Show()
                end
                if remaining <= 0 then refreshFamilies[state.descriptor.configKey] = true end
            end
        end
    end

    for unitKey, state in pairs(AuraCustomizationModule.barFrames) do
        local expired = false
        for i = 1, #state.rows do
            local row = state.rows[i]
            if row:IsShown() and row.aura and not row.aura.noDuration then
                local remaining = max(0, row.aura.expirationTime - now)
                row.bar:SetValue(remaining)
                row.timeText:SetText(FormatTime(remaining))
                if remaining <= 0 then expired = true end
            end
        end
        if expired then AuraCustomizationModule:RefreshBars(unitKey) end
    end

    for configKey in pairs(refreshFamilies) do
        AuraCustomizationModule:RefreshStandard(configKey)
    end
end

local function EnsureUpdateFrame()
    if AuraCustomizationModule.updateFrame then return end
    local frame = CreateFrame("Frame")
    frame.elapsed = 0
    frame:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if self.elapsed < UPDATE_INTERVAL then return end
        self.elapsed = 0
        UpdateVisibleTimers()
    end)
    AuraCustomizationModule.updateFrame = frame
end

local function RefreshForAuraUnit(unit)
    if not unit then return end
    if unit == "player" or unit == "vehicle" then
        AuraCustomizationModule:RefreshStandard("buffframe")
        AuraCustomizationModule:RefreshStandard("player")
        AuraCustomizationModule:RefreshBars("player")
    elseif unit == "target" then
        AuraCustomizationModule:RefreshStandard("target")
        AuraCustomizationModule:RefreshBars("target")
    elseif unit == "focus" then
        AuraCustomizationModule:RefreshStandard("focus")
        AuraCustomizationModule:RefreshBars("focus")
    elseif unit == "pet" then
        AuraCustomizationModule:RefreshStandard("pet")
    elseif unit == "targettarget" then
        AuraCustomizationModule:RefreshStandard("tot")
    elseif unit == "focustarget" then
        AuraCustomizationModule:RefreshStandard("fot")
    elseif unit:match("^party%d+$") then
        AuraCustomizationModule:RefreshStandard("party")
    elseif unit:match("^boss%d+$") then
        AuraCustomizationModule:RefreshStandard("boss")
    elseif unit:match("^arena%d+$") then
        AuraCustomizationModule:RefreshStandard("arena")
    end
end

local function InstallHooks()
    if AuraCustomizationModule.hooksInstalled then return end

    if _G.BuffFrame_Update then
        hooksecurefunc("BuffFrame_Update", function()
            if AuraCustomizationModule.applied and not AuraCustomizationModule.restoring then
                AuraCustomizationModule:RefreshStandard("buffframe")
                AuraCustomizationModule:RefreshBars("player")
            end
        end)
    end

    if _G.TargetFrame_UpdateAuras then
        hooksecurefunc("TargetFrame_UpdateAuras", function(frame)
            if not AuraCustomizationModule.applied or AuraCustomizationModule.restoring then return end
            local frameName = frame and frame.GetName and frame:GetName()
            if frameName == "TargetFrame" then
                AuraCustomizationModule:RefreshStandard("target")
                AuraCustomizationModule:RefreshBars("target")
            elseif frameName == "FocusFrame" then
                AuraCustomizationModule:RefreshStandard("focus")
                AuraCustomizationModule:RefreshBars("focus")
            elseif frameName and frameName:match("^Boss%dTargetFrame$") then
                AuraCustomizationModule:RefreshStandard("boss")
            end
        end)
    end

    if _G.PartyMemberFrame_UpdateMember then
        hooksecurefunc("PartyMemberFrame_UpdateMember", function(frame)
            if not AuraCustomizationModule.applied or AuraCustomizationModule.restoring then return end
            local frameName = frame and frame.GetName and frame:GetName()
            if frameName and frameName:match("^PartyMemberFrame%d+$") then
                AuraCustomizationModule:RefreshStandard("party")
            end
        end)
    end
    AuraCustomizationModule.hooksInstalled = true
end

local function EnsureEventFrame()
    if AuraCustomizationModule.eventFrame then return end
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("UNIT_AURA")
    frame:RegisterEvent("PLAYER_TARGET_CHANGED")
    frame:RegisterEvent("PLAYER_FOCUS_CHANGED")
    frame:RegisterEvent("UNIT_PET")
    frame:RegisterEvent("PARTY_MEMBERS_CHANGED")
    frame:RegisterEvent("RAID_ROSTER_UPDATE")
    frame:RegisterEvent("ADDON_LOADED")
    frame:SetScript("OnEvent", function(_, event, arg1)
        if not AuraCustomizationModule.applied then return end
        if event == "UNIT_AURA" then
            RefreshForAuraUnit(arg1)
        elseif event == "PLAYER_TARGET_CHANGED" then
            AuraCustomizationModule:RefreshStandard("target")
            AuraCustomizationModule:RefreshStandard("tot")
            AuraCustomizationModule:RefreshBars("target")
        elseif event == "PLAYER_FOCUS_CHANGED" then
            AuraCustomizationModule:RefreshStandard("focus")
            AuraCustomizationModule:RefreshStandard("fot")
            AuraCustomizationModule:RefreshBars("focus")
        elseif event == "UNIT_PET" then
            AuraCustomizationModule:RefreshStandard("pet")
        elseif event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
            AuraCustomizationModule:RefreshStandard("party")
        elseif event == "ADDON_LOADED" then
            if arg1 == "Blizzard_ArenaUI" then AuraCustomizationModule:RefreshStandard("arena") end
            local alreadyWatchingMedia = AuraCustomizationModule.mediaCallbackRegistered
            if RegisterAuraMedia() and not alreadyWatchingMedia then
                for i = 1, #BAR_UNIT_KEYS do
                    AuraCustomizationModule:RefreshBars(BAR_UNIT_KEYS[i])
                end
            end
        else
            AuraCustomizationModule:RefreshAll()
            addon:After(0.5, function()
                if AuraCustomizationModule.applied then AuraCustomizationModule:RefreshAll() end
            end)
        end
    end)
    AuraCustomizationModule.eventFrame = frame
end

function addon.ApplyAuraCustomizationSystem()
    AuraCustomizationModule.initialized = true
    RegisterAuraMedia()
    InstallHooks()
    EnsureEventFrame()
    EnsureUpdateFrame()
    for i = 1, #BAR_UNIT_KEYS do
        local unitKey = BAR_UNIT_KEYS[i]
        local state = EnsureBarFrame(unitKey)
        if not IsEditorActive() and addon.ApplyWidgetPositionFromDB then
            addon.ApplyWidgetPositionFromDB(BAR_WIDGET_KEYS[unitKey], state.anchor)
        end
    end
    AuraCustomizationModule.applied = true
    AuraCustomizationModule.updateFrame:Show()
    AuraCustomizationModule:RefreshAll()
end

function addon.RestoreAuraCustomizationSystem()
    AuraCustomizationModule.applied = false
    RestoreBlizzardAuraFrame()
    for i = 1, #ATTACHED_DESCRIPTORS do RestoreAttachedDescriptor(ATTACHED_DESCRIPTORS[i]) end
    for i = 1, #BAR_UNIT_KEYS do
        local state = AuraCustomizationModule.barFrames[BAR_UNIT_KEYS[i]]
        if state then state.anchor:Hide() end
    end
    AuraCustomizationModule.restoring = false
    AuraCustomizationModule.preview = {}
    if AuraCustomizationModule.updateFrame then AuraCustomizationModule.updateFrame:Hide() end
end

function addon.RefreshAuraCustomizationSystem()
    if IsModuleEnabled() then
        addon.ApplyAuraCustomizationSystem()
    else
        addon.RestoreAuraCustomizationSystem()
    end
end

-- Register only after every lifecycle function exists. Keeping this call guarded
-- makes load failures observable on old clients instead of aborting the entire file.
AuraCustomizationModule.sourceLoaded = true
if addon.RegisterModule then
    local ok, result = pcall(addon.RegisterModule, addon,
        "aura_customization",
        AuraCustomizationModule,
        "Aura Filtering and Bars",
        "Filter, sort, color, and display unit-frame auras as icons or bars.",
        {
            lifecycle = {
                apply = addon.ApplyAuraCustomizationSystem,
                restore = addon.RestoreAuraCustomizationSystem,
                refresh = addon.RefreshAuraCustomizationSystem,
            },
        })

    if ok then
        local info = addon.ModuleRegistry and addon.ModuleRegistry.GetInfo
            and addon.ModuleRegistry:GetInfo("aura_customization")
        AuraCustomizationModule.registered = result == true
            or (info and info.module == AuraCustomizationModule) or false
    else
        AuraCustomizationModule.registrationError = tostring(result)
        if addon.Error then
            addon:Error("Aura customization registration failed:", AuraCustomizationModule.registrationError)
        end
    end
else
    AuraCustomizationModule.registrationError = "addon.RegisterModule is unavailable"
end
