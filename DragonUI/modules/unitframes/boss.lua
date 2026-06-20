--[[
  DragonUI - Boss Frames (boss.lua)

  Custom DragonUI boss frames — NOT Blizzard's.
  Built from scratch using CreateFrame (no SecureUnitButtonTemplate).
  Uses Dragonflight-styled DragonUI textures.

  Architecture:
  - Each boss frame is a normal (non-secure) frame created by us
  - TEXTURES from uf_core: targetStyle.BOSS (elite dragon border)
  - Visibility: UNIT_HEALTH event — show/hide based on UnitExists("bossN")
  - Positioning: anchored to our wrapper/overlay like other DragonUI widgets
]]

local _, addon = ...
local L = addon.L

local UF = addon.UF
if not UF then return end

-- ============================================================================
-- CONFIG ACCESS
-- ============================================================================

local function GetConfig()
    return UF.GetConfig("boss")
end

local function IsEnabled()
    return UF.IsEnabled("boss")
end

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local NUM_BOSS_FRAMES = 4

-- Frame dimensions (match original boss frame native size)
local FRAME_WIDTH = 200
local FRAME_HEIGHT = 100

-- Portrait (circular, same as target_style)
local PORTRAIT_SIZE = 45

-- Health bar (positioned relative to portrait like target_style)
local HEALTH_BAR_WIDTH = 100
local HEALTH_BAR_HEIGHT = 16

-- Mana bar
local MANA_BAR_WIDTH = 106
local MANA_BAR_HEIGHT = 7

-- ============================================================================
-- MODULE STATE
-- ============================================================================

local BossModule = UF.CreateModule("boss")
BossModule.bossFrames = {}    -- Our custom boss frames, indexed 1-4
BossModule.wrapperFrames = {} -- Positioning wrappers
BossModule.configured = false

if addon.RegisterModule then
    addon:RegisterModule("boss", BossModule,
        (L and L["Boss Frames"]) or "Boss Frames",
        (L and L["Dragonflight-styled boss target frames"]) or "Dragonflight-styled boss target frames")
end

-- ============================================================================
-- TEXTURE & LAYOUT CONSTANTS
-- ============================================================================

local TEXTURES = UF.TEXTURES.targetStyle
local BOSS_COORDS = UF.BOSS_COORDS.targetStyle
local PORTRAIT_MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

-- ============================================================================
-- CREATE CUSTOM BOSS FRAME
-- ============================================================================

local function CreateBossFrameWidget(name, index)
    -- Main frame — normal frame, NOT secure
    local frame = CreateFrame("Frame", name, UIParent)
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    frame:SetFrameLevel(100)
    frame:SetFrameStrata("MEDIUM")
    frame:Hide() -- Hidden by default until boss appears

    -- Store reference
    frame.unit = "boss" .. index
    frame.index = index

    -- ---- Background (dark fill behind bars) ----
    -- local bg = frame:CreateTexture(name .. "BG", "BACKGROUND")
    -- bg:SetDrawLayer("BACKGROUND", -7)
    -- bg:SetTexture(TEXTURES.BACKGROUND)
    -- bg:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -8)
    -- bg:SetSize(FRAME_WIDTH, FRAME_HEIGHT - 8)
    -- frame.background = bg

    -- ---- Border frame (on its own overlay frame above bars) ----
    local borderFrame = CreateFrame("Frame", name .. "BorderFrame", frame)
    borderFrame:SetAllPoints(frame)
    borderFrame:EnableMouse(false)
    borderFrame:SetFrameLevel(frame:GetFrameLevel() + 2)
    frame.borderFrame = borderFrame

    -- ---- Frame border texture (Dragonflight elite dragon border) ----
    local border = borderFrame:CreateTexture(name .. "Border", "OVERLAY")

    border:SetDrawLayer("OVERLAY", 5)
    border:SetTexture(TEXTURES.BORDER)
    border:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -7)
    border:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    frame.border = border

    -- ---- Elite decoration (dragon on decoFrame, child of borderFrame) ----
    local decoFrame = CreateFrame("Frame", name .. "DecoFrame", borderFrame)
    decoFrame:SetAllPoints(portrait)
    decoFrame:EnableMouse(false)
    frame.decoFrame = decoFrame

    local elite = decoFrame:CreateTexture(name .. "Elite", "OVERLAY")
    elite:SetDrawLayer("OVERLAY", 6)
    elite:SetTexture(TEXTURES.BOSS)
    elite:Hide()
    frame.eliteDecoration = elite

    -- ---- Portrait ----
    local portrait = CreateFrame("Frame", name .. "PortraitFrame", frame)
    portrait:SetSize(PORTRAIT_SIZE, PORTRAIT_SIZE)
    portrait:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -38, -12)
    portrait:EnableMouse(false)

    local portraitTex = portrait:CreateTexture(name .. "Portrait", "ARTWORK")
    portraitTex:SetAllPoints(portrait)
    portraitTex:SetTexCoord(0, 1, 0, 1)
    portrait.tex = portraitTex
    frame.portrait = portrait

    -- ---- Portrait circular mask ----
    -- local portraitMask = frame:CreateTexture(name .. "PortraitMask", "BACKGROUND")
    -- portraitMask:SetDrawLayer("BACKGROUND", 1)
    -- portraitMask:SetTexture(PORTRAIT_MASK)
    -- portraitMask:SetVertexColor(0, 0, 0, 1)
    -- portraitMask:SetPoint("CENTER", portrait, "CENTER", 0, 0)
    -- portraitMask:SetSize(PORTRAIT_SIZE, PORTRAIT_SIZE)
    -- frame.portraitMask = portraitMask

    -- ---- Health bar ----
    local healthBar = CreateFrame("StatusBar", name .. "HealthBar", frame)
    healthBar:SetSize(HEALTH_BAR_WIDTH, HEALTH_BAR_HEIGHT)
    healthBar:SetPoint("RIGHT", portrait, "LEFT", -1, 0)
    healthBar:SetFrameLevel(frame:GetFrameLevel() + 1)
    healthBar:SetStatusBarTexture(TEXTURES.BAR_PREFIX .. "Health")
    healthBar:GetStatusBarTexture():SetDrawLayer("ARTWORK", 1)
    healthBar:GetStatusBarTexture():SetVertexColor(1, 1, 1, 1)
    frame.healthBar = healthBar

    -- ---- Mana bar ----
    local manaBar = CreateFrame("StatusBar", name .. "ManaBar", frame)
    manaBar:SetSize(MANA_BAR_WIDTH, MANA_BAR_HEIGHT)
    manaBar:SetPoint("RIGHT", portrait, "LEFT", 5, -13)
    manaBar:SetFrameLevel(frame:GetFrameLevel() + 1)
    manaBar:SetStatusBarTexture(TEXTURES.BAR_PREFIX .. "Mana")
    manaBar:GetStatusBarTexture():SetDrawLayer("ARTWORK", 1)
    manaBar:GetStatusBarTexture():SetVertexColor(1, 1, 1, 1)
    frame.manaBar = manaBar

    -- ---- Name background ----
    local nameBG = frame:CreateTexture(name .. "NameBG", "BORDER")
    nameBG:SetDrawLayer("BORDER", 1)
    nameBG:SetTexture("Interface\\Buttons\\WHITE8X8")
    nameBG:SetVertexColor(0, 0, 0, 0.55)
    frame.nameBackground = nameBG

    -- ---- Name text ----
    local nameText = frame:CreateFontString(name .. "NameText", "OVERLAY")
    nameText:SetDrawLayer("OVERLAY", 2)
    nameText:SetFont("Fonts/FRIZQT__.TTF", 9, "THICK")
    nameText:SetTextColor(1, 0.96, 0.45)
    frame.nameText = nameText

    -- ---- Level text ----
    local levelText = frame:CreateFontString(name .. "LevelText", "OVERLAY")
    levelText:SetDrawLayer("OVERLAY", 2)
    levelText:SetFont("Fonts/FRIZQT__.TTF", 9, "THICK")
    levelText:SetTextColor(1, 0.82, 0)
    frame.levelText = levelText

    -- ---- Health text ----
    local healthText = healthBar:CreateFontString(name .. "HealthText", "OVERLAY")
    healthText:SetDrawLayer("OVERLAY")
    healthText:SetFont("Fonts/FRIZQT__.TTF", 10, "THICK")
    healthText:SetTextColor(1, 1, 1)
    healthText:SetWidth(HEALTH_BAR_WIDTH - 4)
    healthText:SetJustifyH("LEFT")
    frame.healthText = healthText

    -- ---- Power text ----
    local powerText = manaBar:CreateFontString(name .. "PowerText", "OVERLAY")
    powerText:SetDrawLayer("OVERLAY")
    powerText:SetFont("Fonts\\FRIZQT__.TTF", 8, "THICK")
    powerText:SetTextColor(1, 1, 1)
    powerText:SetWidth(MANA_BAR_WIDTH - 4)
    powerText:SetJustifyH("LEFT")
    frame.powerText = powerText

    -- ---- Flash texture (threat glow) — custom, hidden initially ----
    local flashTex = frame:CreateTexture(name .. "FlashMirror", "OVERLAY")
    flashTex:SetDrawLayer("OVERLAY", 7)
    flashTex:SetTexture(TEXTURES.THREAT)
    flashTex:SetTexCoord(0, 376/512, 0, 134/256)
    flashTex:SetVertexColor(1, 0, 0, 1)
    flashTex:SetBlendMode("ADD")
    flashTex:SetAlpha(0.7)
    flashTex:SetSize(188, 67)
    flashTex:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 3, 25)
    flashTex:Hide()
    frame.flashMirror = flashTex

    return frame
end

-- ============================================================================
-- APPLY LAYOUT — position all child elements relative to frame
-- ============================================================================

local function ApplyBossFrameLayout(frame)
    if not frame or not frame.healthBar then return end

    local portrait = frame.portrait
    local healthBar = frame.healthBar
    local manaBar = frame.manaBar
    local nameBG = frame.nameBackground
    local nameText = frame.nameText
    local levelText = frame.levelText
    local elite = frame.eliteDecoration

    -- Portrait
    portrait:ClearAllPoints()
    portrait:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -38, -12)

    -- Health bar
    healthBar:ClearAllPoints()
    healthBar:SetPoint("RIGHT", portrait, "LEFT", -1, 0)
    healthBar:SetFrameLevel(frame:GetFrameLevel() + 1)

    -- Mana bar
    manaBar:ClearAllPoints()
    manaBar:SetPoint("RIGHT", portrait, "LEFT", 5, -13)
    manaBar:SetFrameLevel(frame:GetFrameLevel() + 1)

    -- Name background
    nameBG:ClearAllPoints()
    nameBG:SetPoint("BOTTOMLEFT", healthBar, "TOPLEFT", -2, -5)
    nameBG:SetSize(108, 14)

    -- Name text
    nameText:ClearAllPoints()
    nameText:SetPoint("BOTTOMLEFT", healthBar, "TOPLEFT", 32, 2)
    nameText:SetWidth(90)

    -- Level text
    levelText:ClearAllPoints()
    levelText:SetPoint("BOTTOMRIGHT", healthBar, "TOPLEFT", 14, 2)

    -- Elite dragon (positioned relative to portrait)
    local unit = frame.unit
    local classification
    if unit and UnitExists(unit) then
        classification = UnitClassification(unit)
    end
    local coords
    if classification == "worldboss" then
        coords = BOSS_COORDS.rareelite
    elseif classification == "elite" then
        coords = BOSS_COORDS.elite
    elseif classification == "rareelite" then
        coords = BOSS_COORDS.rareelite
    elseif classification == "rare" then
        coords = BOSS_COORDS.rare
    else
        coords = BOSS_COORDS.rareelite
    end
    if coords then
        elite:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        elite:SetSize(79, 67)
        elite:ClearAllPoints()
        elite:SetPoint("CENTER", portrait, "CENTER", 8, coords[8])
        elite:Show()
    end

    -- Health text
    if frame.healthText then
        frame.healthText:ClearAllPoints()
        frame.healthText:SetPoint("LEFT", healthBar, "LEFT", 0, 0)
    end

    -- Power text
    if frame.powerText then
        frame.powerText:ClearAllPoints()
        frame.powerText:SetPoint("LEFT", manaBar, "LEFT", 0, 0)
    end



    -- Flash mirror positioning
    frame.flashMirror:ClearAllPoints()
    frame.flashMirror:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 3, 25)
end

-- ============================================================================
-- NUMBER FORMATTING
-- ============================================================================

local function AbbreviateNumber(val)
    if val >= 1e9 then
        return ("%.1fb"):format(val / 1e9)
    elseif val >= 1e6 then
        return ("%.1fm"):format(val / 1e6)
    elseif val >= 1e4 then
        return ("%.1fk"):format(val / 1e4)
    elseif val >= 1e3 then
        return ("%.0fk"):format(val / 1e3)
    end
    return tostring(val)
end

-- ============================================================================
-- UPDATE BOSS FRAME — refresh all data from unit
-- ============================================================================

local function UpdateBossFrame(frame)
    if not frame or not frame.unit then return end

    local unit = frame.unit

    -- Portrait
    if UnitExists(unit) then
        SetPortraitTexture(frame.portrait.tex, unit)
    else
        frame.portrait.tex:SetTexture(nil)
    end

    -- Name
    local name = UnitName(unit) or ""
    frame.nameText:SetText(name)

    -- Level
    local level = UnitLevel(unit)
    local levelColor
    if GetDifficultyColor then
        local r, g, b = GetDifficultyColor(level)
        levelColor = {r = r or 1, g = g or 0.82, b = b or 0}
    elseif GetQuestDifficultyColor then
        local color = GetQuestDifficultyColor(level)
        levelColor = {r = color.r, g = color.g, b = color.b}
    else
        levelColor = {r = 1, g = 0.82, b = 0}
    end
    frame.levelText:SetText(level)
    frame.levelText:SetTextColor(levelColor.r, levelColor.g, levelColor.b)

    -- Health
    local curHP = UnitHealth(unit)
    local maxHP = UnitHealthMax(unit)
    frame.healthBar:SetMinMaxValues(0, maxHP)
    frame.healthBar:SetValue(curHP)
    if maxHP > 0 then
        local pct = math.floor(curHP / maxHP * 100)
        frame.healthText:SetText(pct .. "% " .. AbbreviateNumber(curHP))
    else
        frame.healthText:SetText(curHP)
    end

    -- Mana / Power
    local curMP = UnitMana(unit)
    local maxMP = UnitManaMax(unit)
    if maxMP > 0 then
        frame.manaBar:SetMinMaxValues(0, maxMP)
        frame.manaBar:SetValue(curMP)
        frame.manaBar:Show()
        frame.manaBar:SetStatusBarColor(0.02, 0.32, 0.71)
        if frame.powerText then
            local pct = math.floor(curMP / maxMP * 100)
            frame.powerText:SetText(pct .. "% " .. AbbreviateNumber(curMP))
            frame.powerText:Show()
    end
    else
        frame.manaBar:Hide()
        if frame.powerText then
            frame.powerText:Hide()
        end
    end



    -- Threat / combat glow — hide Blizzard's, use our custom
    local threatIndicator = _G[frame:GetName() .. "ThreatIndicator"]
    if threatIndicator then
        threatIndicator:Hide()
    end
end

-- ============================================================================
-- POSITION BOSS FRAMES
-- ============================================================================

local function PositionBossFrames()
    if InCombatLockdown() then return end

    local config = GetConfig()
    local scale = config.scale or 1.0

    for i = 1, NUM_BOSS_FRAMES do
        local wrapper = BossModule.wrapperFrames[i]
        local bf = BossModule.bossFrames[i]
        if wrapper then
            wrapper:SetScale(scale)

            if i == 1 then
                -- First frame: anchor to overlay or default position
                if BossModule.overlay then
                    wrapper:ClearAllPoints()
                    wrapper:SetPoint("TOP", BossModule.overlay, "TOP", 20, 0)
                else
                    wrapper:ClearAllPoints()
                    wrapper:SetPoint(
                        config.anchor or "TOPRIGHT",
                        UIParent,
                        config.anchorParent or "TOPRIGHT",
                        config.x or -180,
                        config.y or -370
                    )
                end
            else
                -- Stack below previous
                wrapper:ClearAllPoints()
                wrapper:SetPoint("TOP", BossModule.wrapperFrames[i - 1], "BOTTOM", 0, 0)
            end
        end

        -- Position our custom boss frame to its wrapper
        if bf and wrapper then
            bf:ClearAllPoints()
            bf:SetPoint("TOPLEFT", wrapper, "TOPLEFT", 0, 0)
        end
    end
end

-- ============================================================================
-- EDITOR MODE
-- ============================================================================

local function SetupEditorMode()
    local totalHeight = NUM_BOSS_FRAMES * 75 - 6
    BossModule.overlay = addon.CreateUIFrame(178, totalHeight, "boss")

    if BossModule.overlay.editorText then
        local L = addon.L
        BossModule.overlay.editorText:SetText((L and (L["boss"] or L["Boss Frames"])) or "Boss Frames")
    end

    -- Initial position
    BossModule.overlay:ClearAllPoints()
    BossModule.overlay:SetPoint(
        "TOPRIGHT", UIParent, "TOPRIGHT", -180, -370
    )

    BossModule.overlay:HookScript("OnDragStop", function(self)
        self.DragonUI_WasDragged = true
    end)

    addon:RegisterEditableFrame({
        name = "boss",
        frame = BossModule.overlay,
        configPath = {"widgets", "boss"},
        hasTarget = function()
            return true
        end,
        showTest = function()
            if BossModule.overlay then
                BossModule.overlay:Show()
            end
            -- Show all boss frames in test mode
            for i = 1, NUM_BOSS_FRAMES do
                local bf = BossModule.bossFrames[i]
                if bf then
                    -- Use player as placeholder data
                    SetPortraitTexture(bf.portrait.tex, "player")
                    bf.nameText:SetText(UnitName("player"))
                    bf.levelText:SetText(UnitLevel("player"))
                    local curHP = UnitHealth("player")
                    local maxHP = UnitHealthMax("player")
                    bf.healthBar:SetMinMaxValues(0, maxHP)
                    bf.healthBar:SetValue(curHP)
                    bf.healthText:SetText(curHP .. "/" .. maxHP)
                    bf.manaBar:SetMinMaxValues(0, UnitManaMax("player"))
                    bf.manaBar:SetValue(UnitMana("player"))
                    bf:Show()
                end
            end
        end,
        hideTest = function()
            for i = 1, NUM_BOSS_FRAMES do
                local bf = BossModule.bossFrames[i]
                if bf then
                    bf:Hide()
                end
            end
        end,
        onHide = function()
            if BossModule.overlay and BossModule.overlay.DragonUI_WasDragged then
                local config = GetConfig()
                if config then
                    config.override = true
                end
                PositionBossFrames()
                BossModule.overlay.DragonUI_WasDragged = nil
            end
        end,
        module = BossModule
    })
end

-- ============================================================================
-- APPLY / RESTORE
-- ============================================================================

local function ApplyBossFramePosition()
    if not BossModule.overlay then return end
    local config = GetConfig()
    if config and config.override then
        if addon.db and addon.db.profile and addon.db.profile.widgets then
            local widgetConfig = addon.db.profile.widgets.boss
            if widgetConfig and widgetConfig.posX and widgetConfig.posY then
                local anchor = widgetConfig.anchor or "CENTER"
                BossModule.overlay:ClearAllPoints()
                BossModule.overlay:SetPoint(anchor, UIParent, anchor, widgetConfig.posX, widgetConfig.posY)
                return
            end
        end
    end
    -- Default
    if config then
        BossModule.overlay:ClearAllPoints()
        BossModule.overlay:SetPoint(
            config.anchor or "TOPRIGHT",
            UIParent,
            config.anchorParent or "TOPRIGHT",
            config.x or -180,
            config.y or -370
        )
    else
        BossModule.overlay:ClearAllPoints()
        BossModule.overlay:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -180, -370)
    end
end

-- ============================================================================
-- EVENT HANDLING
-- ============================================================================

local eventsFrame = CreateFrame("Frame")
BossModule.eventsFrame = eventsFrame

eventsFrame:SetScript("OnEvent", function(self, event, ...)
    if not IsEnabled() then return end

    if event == "ADDON_LOADED" then
        local name = ...
        if name == "DragonUI" then
            SetupEditorMode()
            ApplyBossFramePosition()
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Move Blizzard default boss frames off-screen
        for i = 1, NUM_BOSS_FRAMES do
            local bf = _G["Boss" .. i .. "TargetFrame"]
            if bf then
                bf:ClearAllPoints()
                bf:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 5000, 0)
            end
        end
        -- Also hide the main container if it exists
        local bossFrame = _G["BossFrame"]
        if bossFrame then
            bossFrame:ClearAllPoints()
            bossFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 5000, 0)
        end

        -- Create our custom boss frames if not already created
        if not BossModule.bossFrames[1] then
            for i = 1, NUM_BOSS_FRAMES do
                local name = "DragonUIBossFrame" .. i
                local bf = CreateBossFrameWidget(name, i)
                BossModule.bossFrames[i] = bf

                -- Create wrapper for positioning
                local wrapper = addon.CreateUIFrame(200, 75, "Boss" .. i .. "Frame")
                BossModule.wrapperFrames[i] = wrapper

                -- Apply layout
                ApplyBossFrameLayout(bf)
                ApplyBossFrameLayout(bf) -- twice for safety
            end
        end

        PositionBossFrames()

    elseif event == "UNIT_HEALTH" then
        local unit = ...
        if unit and unit:match("^boss%d$") then
            local idx = tonumber(unit:match("boss(%d)"))
            local bf = BossModule.bossFrames[idx]
            local w = BossModule.wrapperFrames[idx]
            if bf and w then
                if UnitExists(unit) and not UnitIsDeadOrGhost(unit) then
                    -- Position to wrapper, update data, show
                    bf:ClearAllPoints()
                    bf:SetPoint("TOPLEFT", w, "TOPLEFT", 0, 0)
                    bf:Show()
                    UpdateBossFrame(bf)
                else
                    bf:Hide()
                end
            end
        end

    elseif event == "UNIT_PORTRAIT_UPDATE" then
        local unit = ...
        if unit and unit:match("^boss%d$") then
            local idx = tonumber(unit:match("boss(%d)"))
            local bf = BossModule.bossFrames[idx]
            if bf and bf:IsShown() then
                SetPortraitTexture(bf.portrait.tex, unit)
            end
        end

    elseif event == "UNIT_NAME_UPDATE" then
        local unit = ...
        if unit and unit:match("^boss%d$") then
            local idx = tonumber(unit:match("boss(%d)"))
            local bf = BossModule.bossFrames[idx]
            if bf and bf:IsShown() then
                local name = UnitName(unit)
                bf.nameText:SetText(name or "")
            end
        end

    elseif event == "UNIT_LEVEL" then
        local unit = ...
        if unit and unit:match("^boss%d$") then
            local idx = tonumber(unit:match("boss(%d)"))
            local bf = BossModule.bossFrames[idx]
            if bf and bf:IsShown() then
                UpdateBossFrame(bf)
            end
        end

    elseif event == "UNIT_MAXHP"
        or event == "UNIT_MANA" or event == "UNIT_MAXMANA"
        or event == "UNIT_ENERGY" or event == "UNIT_RAGE"
        or event == "UNIT_FOCUS" or event == "UNIT_RUNIC_POWER"
        or event == "UNIT_DISPLAYPOWER" or event == "UNIT_MAXPOWER"
    then
        local unit = ...
        if unit and unit:match("^boss%d$") then
            local idx = tonumber(unit:match("boss(%d)"))
            local bf = BossModule.bossFrames[idx]
            if bf and bf:IsShown() then
                UpdateBossFrame(bf)
            end
        end

    elseif event == "PLAYER_LEAVING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        -- Hide all boss frames when leaving instance/zone
        for i = 1, NUM_BOSS_FRAMES do
            local bf = BossModule.bossFrames[i]
            if bf then bf:Hide() end
        end

    elseif event == "PLAYER_REGEN_ENABLED" then
        PositionBossFrames()


    end
end)

eventsFrame:RegisterEvent("ADDON_LOADED")
eventsFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventsFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventsFrame:RegisterEvent("UNIT_HEALTH")
eventsFrame:RegisterEvent("UNIT_MAXHP")
eventsFrame:RegisterEvent("UNIT_PORTRAIT_UPDATE")
eventsFrame:RegisterEvent("UNIT_NAME_UPDATE")
eventsFrame:RegisterEvent("UNIT_LEVEL")
eventsFrame:RegisterEvent("UNIT_MANA")
eventsFrame:RegisterEvent("UNIT_MAXMANA")
eventsFrame:RegisterEvent("UNIT_ENERGY")
eventsFrame:RegisterEvent("UNIT_RAGE")
eventsFrame:RegisterEvent("UNIT_FOCUS")
eventsFrame:RegisterEvent("UNIT_RUNIC_POWER")
eventsFrame:RegisterEvent("UNIT_DISPLAYPOWER")
eventsFrame:RegisterEvent("UNIT_MAXPOWER")
eventsFrame:RegisterEvent("PLAYER_LEAVING_WORLD")
eventsFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

-- Periodic cleanup — every 3 seconds, hide frames whose unit is gone
local function BossCleanup_OnUpdate(self, elapsed)
    self.elapsed = (self.elapsed or 0) + elapsed
    if self.elapsed < 3 then return end
    self.elapsed = 0
    for i = 1, NUM_BOSS_FRAMES do
        local bf = BossModule.bossFrames[i]
        if bf and bf:IsShown() and bf.unit then
            if not UnitExists(bf.unit) or UnitIsDeadOrGhost(bf.unit) then
                bf:Hide()
            end
        end
    end
end
eventsFrame:SetScript("OnUpdate", BossCleanup_OnUpdate)

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function addon.RefreshBossFrames()
    if not BossModule.configured then return end
    if InCombatLockdown() then return end
    if not IsEnabled() then
        addon:ShouldDeferModuleDisable("boss", BossModule)
        return
    end

    for i = 1, NUM_BOSS_FRAMES do
        local bf = BossModule.bossFrames[i]
        if bf then
            ApplyBossFrameLayout(bf)
        end
    end

    PositionBossFrames()
end

-- Store reference
addon.BossModule = BossModule

-- Profile change callbacks
local function OnProfileChanged()
    if not IsEnabled() then
        addon:ShouldDeferModuleDisable("boss", BossModule)
        return
    end

    if addon.RefreshBossFrames then
        addon.RefreshBossFrames()
    end
end

local profileFrame = CreateFrame("Frame")
profileFrame:RegisterEvent("PLAYER_LOGIN")
profileFrame:SetScript("OnEvent", function(self, event)
    if addon.db and addon.db.RegisterCallback then
        addon.db.RegisterCallback(BossModule, "OnProfileChanged", OnProfileChanged)
        addon.db.RegisterCallback(BossModule, "OnProfileCopied", OnProfileChanged)
        addon.db.RegisterCallback(BossModule, "OnProfileReset", OnProfileChanged)
    end
    self:UnregisterAllEvents()
end)

-- ============================================================================
-- DEBUG / TEST COMMANDS
-- ============================================================================

local function PrintBossDebug()
    print("=== DragonUI Custom Boss Frames ===")
    for i = 1, NUM_BOSS_FRAMES do
        local bf = BossModule.bossFrames[i]
        local w = BossModule.wrapperFrames[i]
        print("Boss"..i.." exists:", bf ~= nil, "Shown:", bf and bf:IsShown() or false, "Wrapper:", w ~= nil)
        if bf and w then
            print("  Wrapper:", w:GetLeft(), w:GetTop())
            print("  BossFrame:", bf:GetLeft(), bf:GetTop(), "Shown:", bf:IsShown())
        end
    end
    print("================================")
end

SLASH_DRAGONUI_BOSSDEBUG1 = "/bossdebug"
SlashCmdList["DRAGONUI_BOSSDEBUG"] = PrintBossDebug

SLASH_DRAGONUI_BOSSTEST1 = "/bosstest"
SlashCmdList["DRAGONUI_BOSSTEST"] = function(msg)
    local bossIdx = tonumber(msg)
    local startIdx = bossIdx or 1
    local endIdx = bossIdx or NUM_BOSS_FRAMES
    for i = startIdx, endIdx do
        local bf = BossModule.bossFrames[i]
        local w = BossModule.wrapperFrames[i]
        if bf and w then
            bf:ClearAllPoints()
            bf:SetPoint("TOPLEFT", w, "TOPLEFT", 0, 0)
            -- Use player as test data
            SetPortraitTexture(bf.portrait.tex, "player")
            bf.nameText:SetText(UnitName("player"))
            bf.levelText:SetText(UnitLevel("player"))
            local curHP = UnitHealth("player")
            local maxHP = UnitHealthMax("player")
            bf.healthBar:SetMinMaxValues(0, maxHP)
            bf.healthBar:SetValue(curHP)
            bf.healthText:SetText(curHP .. "/" .. maxHP)
            bf.manaBar:SetMinMaxValues(0, UnitManaMax("player"))
            bf.manaBar:SetValue(UnitMana("player"))
            bf:Show()
            print("Boss" .. i .. " shown (player data)")
        end
    end
end
