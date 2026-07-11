--[[
  DragonUI - Boss Frames (boss.lua)

  Custom DragonUI boss frames — NOT Blizzard's.
  Built from scratch using CreateFrame (no SecureUnitButtonTemplate).
  Uses Dragonflight-styled DragonUI textures.

  Architecture:
  - Config: addon.db.profile.unitframe.boss
  - Atlas: texture:set_atlas(name, true) (from utils/atlas.lua)
  - Editor: RegisterEditableFrame for drag positioning
  - Visibility: RegisterUnitWatch(bossFrame) per boss frame — required because
    INSTANCE_ENCOUNTER_ENGAGE_UNIT does NOT exist in 3.3.5a (MCP Ch.25).
    RegisterUnitWatch auto-shows/hides frames based on UnitExists("bossN").
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

-- Atlas border name by classification (boss frames always >= elite)
local CLASSIFICATION_ATLAS = {
    worldboss = "TargetFrame-TextureFrame-Elite",
    elite     = "TargetFrame-TextureFrame-Elite",
    rareelite = "TargetFrame-TextureFrame-RareElite",
    rare      = "TargetFrame-TextureFrame-Rare",
}
local DEFAULT_BOSS_ATLAS = "TargetFrame-TextureFrame-Elite"

-- Blizzard can re-anchor TextureFrame back to its default screen position; lock it.
local function HookTextureFrameSetPoint(textureFrame, bossFrame)
    if textureFrame.__DragonUI_SetPointHooked then return end
    hooksecurefunc(textureFrame, "SetPoint", function(self, ...)
        if self._DragonUI_SettingPoint or InCombatLockdown() then return end
        self._DragonUI_SettingPoint = true
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", bossFrame, "TOPLEFT", 0, 0)
        self._DragonUI_SettingPoint = nil
    end)
    textureFrame.__DragonUI_SetPointHooked = true
end

-- Re-anchor border (called from hooks after Blizzard resets)
local function UpdateBossFrameBorder(bossFrame)
    if not bossFrame.DragonUI_FrameBorder or not bossFrame.DragonUI_FrameBG then return end
    bossFrame.DragonUI_FrameBG:ClearAllPoints()
    bossFrame.DragonUI_FrameBG:SetPoint("TOPLEFT", bossFrame, "TOPLEFT", 0, -8)
    -- Border is on its own overlay frame — just reanchor the frame
    local borderFrame = bossFrame.DragonUI_BorderFrame
    if borderFrame then
        borderFrame:ClearAllPoints()
        borderFrame:SetAllPoints(bossFrame)
        borderFrame:SetFrameLevel(bossFrame:GetFrameLevel() + 2)
    end
    -- Blizzard TextureFrame above border AND above decoFrame (elite dragon).
    -- borderFrame = N+2, decoFrame (child) = N+3, TextureFrame must be N+4.
    local frameName = bossFrame:GetName()
    if frameName then
        local textureFrame = _G[frameName .. "TextureFrame"]
        if textureFrame and borderFrame then
            textureFrame._DragonUI_SettingPoint = true
            textureFrame:ClearAllPoints()
            textureFrame:SetPoint("TOPLEFT", bossFrame, "TOPLEFT", 0, 0)
            textureFrame._DragonUI_SettingPoint = nil
            textureFrame:SetFrameLevel(borderFrame:GetFrameLevel() + 2)
            HookTextureFrameSetPoint(textureFrame, bossFrame)
        end
    end
    -- Decoration frame (child of borderFrame) always renders above border
    local decoFrame = bossFrame.DragonUI_DecoFrame
    if decoFrame then
        decoFrame:ClearAllPoints()
        decoFrame:SetAllPoints(bossFrame)
    end
    bossFrame.DragonUI_FrameBorder:ClearAllPoints()
    bossFrame.DragonUI_FrameBorder:SetPoint(
        "TOPLEFT", bossFrame.DragonUI_FrameBG, "TOPLEFT", 0, 0)
end

-- Re-apply custom flash styling on our mirror texture (on BorderFrame)
local function EnforceFlashStyle(flashTex, parentFrame)
    if not flashTex then return end
    -- Hide the Blizzard flash — we use our own mirror
    flashTex:SetAlpha(0)

    local bossFrame = parentFrame

    -- Create mirror flash on bossFrame itself (once).
    -- bossFrame is level N, borderFrame is level N+2, so the flash
    -- naturally renders BELOW the border — correct "glow behind border" look.
    if not bossFrame.DragonUI_Flash then
        local mirror = bossFrame:CreateTexture(nil, "OVERLAY")
        mirror:SetDrawLayer("OVERLAY", 7)
        bossFrame.DragonUI_Flash = mirror
        -- Sync: when Blizzard shows/hides the original flash, mirror it
        hooksecurefunc(flashTex, "Show", function() mirror:Show() end)
        hooksecurefunc(flashTex, "Hide", function() mirror:Hide() end)
        mirror:Hide()
    end

    local mirror = bossFrame.DragonUI_Flash
    mirror:SetTexture(TEXTURES.THREAT)
    mirror:SetTexCoord(0, 376/512, 0, 134/256)
    mirror:SetVertexColor(1, 0, 0, 1)
    mirror:SetBlendMode("ADD")
    mirror:SetAlpha(0.7)
    mirror:SetDrawLayer("OVERLAY", 7)
    mirror:ClearAllPoints()
    mirror:SetPoint("BOTTOMLEFT", bossFrame, "BOTTOMLEFT", 3, 25)
    mirror:SetSize(188, 67)
    -- Match current visibility
    if flashTex:IsShown() then mirror:Show() else mirror:Hide() end
end

-- ============================================================================
-- CREATE CUSTOM BOSS FRAME
-- ============================================================================

local function CreateBossFrameWidget(name, index)
    -- Main frame — normal frame, no secure template
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

    -- ---- Name background (rounded, target-style) ----
    local nameBG = frame:CreateTexture(name .. "NameBG", "BORDER")
    nameBG:SetDrawLayer("BORDER", 1)
    nameBG:SetTexture("Interface\\AddOns\\DragonUI\\Textures\\UIUnitFrame2x_PTR")
    nameBG:SetTexCoord(536 / 1024, 804 / 1024, 168 / 512, 199 / 512) -- red (hostile)
    nameBG:SetVertexColor(1, 1, 1, 1)
    nameBG:SetBlendMode("ADD")
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

    -- ---- Health text (left = percentage, right = current) ----
    local healthPct = healthBar:CreateFontString(name .. "HealthPct", "OVERLAY")
    healthPct:SetDrawLayer("OVERLAY")
    healthPct:SetFont("Fonts/FRIZQT__.TTF", 10, "THICK")
    healthPct:SetTextColor(1, 1, 1)
    healthPct:SetJustifyH("LEFT")
    frame.healthPct = healthPct

    local healthText = healthBar:CreateFontString(name .. "HealthText", "OVERLAY")
    healthText:SetDrawLayer("OVERLAY")
    healthText:SetFont("Fonts/FRIZQT__.TTF", 10, "THICK")
    healthText:SetTextColor(1, 1, 1)
    healthText:SetJustifyH("RIGHT")
    frame.healthText = healthText

    -- ---- Power text (left = percentage, right = current) ----
    local powerPct = manaBar:CreateFontString(name .. "PowerPct", "OVERLAY")
    powerPct:SetDrawLayer("OVERLAY")
    powerPct:SetFont("Fonts\\FRIZQT__.TTF", 8, "THICK")
    powerPct:SetTextColor(1, 1, 1)
    powerPct:SetJustifyH("LEFT")
    frame.powerPct = powerPct

    local powerText = manaBar:CreateFontString(name .. "PowerText", "OVERLAY")
    powerText:SetDrawLayer("OVERLAY")
    powerText:SetFont("Fonts\\FRIZQT__.TTF", 8, "THICK")
    powerText:SetTextColor(1, 1, 1)
    powerText:SetJustifyH("RIGHT")
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
    nameBG:SetPoint("BOTTOMLEFT", healthBar, "TOPLEFT", -0.5, 0.2)
    nameBG:SetSize(135, 14)

    -- Name text
    nameText:ClearAllPoints()
    nameText:SetPoint("BOTTOM", healthBar, "TOP", 10, 3)
    nameText:SetWidth(90)

    -- Level text
    levelText:ClearAllPoints()
    levelText:SetPoint("BOTTOMRIGHT", healthBar, "TOPLEFT", 18, 3)

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

    -- High level icon (skull)
    local highLevelTex = _G[frame:GetName() .. "TextureFrameHighLevelTexture"]
    if highLevelTex and levelText then
        highLevelTex:ClearAllPoints()
        highLevelTex:SetPoint("CENTER", levelText, "CENTER", -9, 6)
        highLevelTex:set_atlas("TargetFrame-HighLevelIcon", true)
    end

    -- Power text (left = pct, right = current)
    if frame.powerPct then
        frame.powerPct:ClearAllPoints()
        frame.powerPct:SetPoint("LEFT", manaBar, "LEFT", 6, 0)
    end
    if frame.powerText then
        frame.powerText:ClearAllPoints()
        frame.powerText:SetPoint("RIGHT", manaBar, "RIGHT", -6, 0)
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
        if frame.healthPct then frame.healthPct:SetText(pct .. "%") end
        if frame.healthText then frame.healthText:SetText(AbbreviateNumber(curHP)) end
    else
        if frame.healthPct then frame.healthPct:SetText("") end
        if frame.healthText then frame.healthText:SetText(curHP) end
    end

    -- Mana / Power
    local curMP = UnitMana(unit)
    local maxMP = UnitManaMax(unit)
    if maxMP > 0 then
        frame.manaBar:SetMinMaxValues(0, maxMP)
        frame.manaBar:SetValue(curMP)
        frame.manaBar:Show()
        frame.manaBar:SetStatusBarColor(0.02, 0.32, 0.71)
        if frame.powerPct or frame.powerText then
            local pct = math.floor(curMP / maxMP * 100)
            if frame.powerPct then frame.powerPct:SetText(pct .. "%") end
            if frame.powerText then
                frame.powerText:SetText(AbbreviateNumber(curMP))
                frame.powerText:Show()
            end
        end
    else
        frame.manaBar:Hide()
        if frame.powerText then frame.powerText:Hide() end
        if frame.powerPct then frame.powerPct:Hide() end
    end


    -- Threat indicator
    if frame.threatIndicator then
        frame.threatIndicator:ClearAllPoints()
        frame.threatIndicator:SetPoint("BOTTOMLEFT", 0, 0)
        frame.threatIndicator:set_atlas("TargetFrame-Status", true)
    end

    -- Threat / combat glow — hide Blizzard's, use our custom
    local threatIndicator = _G[frame:GetName() .. "ThreatIndicator"]
    if threatIndicator then
        threatIndicator:Hide()
    end
end

-- ============================================================================
-- POSITION BOSS FRAMES
-- HIDE BLIZZARD BACKGROUNDS
-- ============================================================================

local function HideBlizzardBossBackgrounds()
    local backgrounds = {
        _G.Boss1TargetFrameBackground,
        _G.Boss2TargetFrameBackground,
        _G.Boss3TargetFrameBackground,
        _G.Boss4TargetFrameBackground,
    }
    for _, bg in ipairs(backgrounds) do
        if bg then bg:SetAlpha(0) end
    end
end

-- ============================================================================
-- CLASSIFICATION HOOK (re-apply styling after Blizzard resets it)
-- ============================================================================

local function HookClassification()
    if BossModule.classificationHooked then return end

    hooksecurefunc("TargetFrame_CheckClassification", function(self, forceNormalTexture)
        -- Only process boss frames
        local frameName = self:GetName()
        if not frameName or not frameName:match("^Boss%dTargetFrame$") then return end
        if InCombatLockdown() then return end

        -- Hide Blizzard border (we use our own custom textures)
        local blizzBorder = _G[frameName .. "TextureFrameTexture"]
        if blizzBorder then blizzBorder:SetAlpha(0) end

        -- Re-apply bar size and anchor — Blizzard also re-anchors these here.
        local portrait = _G[frameName .. "Portrait"]
        local healthBar = _G[frameName .. "HealthBar"]
        if healthBar then
            healthBar:SetSize(125, 20)
            if portrait then
                healthBar:ClearAllPoints()
                healthBar:SetPoint("RIGHT", portrait, "LEFT", -1, 0)
            end
        end

        local manaBar = _G[frameName .. "ManaBar"]
        if manaBar then
            manaBar:SetSize(132, 9)
            if portrait then
                manaBar:ClearAllPoints()
                manaBar:SetPoint("RIGHT", portrait, "LEFT", 6.5, -16.5)
            end
        end

        local nameText = _G[frameName .. "TextureFrameName"]
        if nameText then
            nameText:ClearAllPoints()
            local healthBar = _G[frameName .. "HealthBar"]
            if healthBar then
                nameText:SetPoint("BOTTOM", healthBar, "TOP", 4, 3)
            end
        end

        local levelText = _G[frameName .. "TextureFrameLevelText"]
        if levelText then
            levelText:ClearAllPoints()
            local healthBar = _G[frameName .. "HealthBar"]
            if healthBar then
                levelText:SetPoint("BOTTOMRIGHT", healthBar, "TOPLEFT", 18, 3)
            end
        end

        local pvpIcon = _G[frameName .. "TextureFramePVPIcon"]
        if pvpIcon then
            pvpIcon:ClearAllPoints()
            pvpIcon:SetPoint("CENTER", self, "BOTTOMRIGHT", 6, 14)
        end

        -- Update border textures
        UpdateBossFrameBorder(self)

        -- Re-enforce elite decoration on decoFrame
        local portrait = _G[frameName .. "Portrait"]
        if self.DragonUI_Elite and portrait then
            local unit = self.unit or self:GetAttribute("unit")
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
                self.DragonUI_Elite:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
                self.DragonUI_Elite:SetSize(coords[5], coords[6])
                self.DragonUI_Elite:ClearAllPoints()
                self.DragonUI_Elite:SetPoint("CENTER", portrait, "CENTER", coords[7], coords[8])
                self.DragonUI_Elite:SetDrawLayer("OVERLAY", 6)
                self.DragonUI_Elite:Show()
            end
        end

        -- Re-enforce flash after classification change
        local flashTex = _G[frameName .. "Flash"]
        EnforceFlashStyle(flashTex, self)

        -- Re-enforce raid target icon draw layer (like target_style.lua)
        local raidTargetIcon = _G[frameName .. "TextureFrameRaidTargetIcon"]
        if raidTargetIcon then
            raidTargetIcon:SetDrawLayer("OVERLAY", 7)
            raidTargetIcon:SetSize(24, 24)
            raidTargetIcon:ClearAllPoints()
            local portrait = _G[frameName .. "Portrait"]
            if portrait then
                raidTargetIcon:SetPoint("CENTER", portrait, "TOP", 0, 5)
            end
        end
    end)

    BossModule.classificationHooked = true
end

-- ============================================================================
-- HEALTH BAR COLOR HOOK
-- ============================================================================

local function HookHealthBarColor()
    if BossModule.healthHooked then return end

    hooksecurefunc("UnitFrameHealthBar_Update", function(statusbar, unit)
        if not statusbar or statusbar.lockValues then return end
        if not unit or not unit:match("^boss%d$") then return end
        if unit ~= statusbar.unit then return end
        if InCombatLockdown() then return end

        -- Re-enforce bar sizing — Blizzard can reset during combat
        statusbar:SetSize(125, 20)
        local parent = statusbar:GetParent()
        if parent then statusbar:SetFrameLevel(parent:GetFrameLevel() + 1) end
        local statusBarTex = statusbar:GetStatusBarTexture()
        if statusBarTex then
            statusBarTex:SetAllPoints(statusbar)
        end
    end)

    BossModule.healthHooked = true
end

-- ============================================================================
-- TARGET FRAME UPDATE HOOK — re-enforce reskin after Blizzard resets layout
-- ============================================================================
-- Blizzard's TargetFrame_Update runs during combat and can reset health/mana
-- bar sizes, anchors, and the boss frame size itself. This hook fires after
-- every such update to maintain our Dragonflight styling.

local function HookTargetFrameUpdate()
    if BossModule.targetFrameUpdateHooked then return end

    local function RefreshBossTargetFrameLayout(self)
        local frameName = self:GetName()
        if not frameName or not frameName:match("^Boss%dTargetFrame$") then return end

        -- Find which wrapper this boss frame belongs to
        local bossIdx = tonumber(frameName:match("Boss(%d)TargetFrame"))
        local positionAnchor = bossIdx and
            (BossModule.secureAnchors[bossIdx] or BossModule.wrapperFrames[bossIdx])
        if positionAnchor then
            -- Re-anchor boss frame to our wrapper — Blizzard's TargetFrame_Update
            -- repositions frames to their default location during combat.
            -- (SetPoint hook also enforces this, but we double-check here.)
            self._DragonUI_SettingPoint = true
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", positionAnchor, "TOPLEFT", 0, 0)
            self:SetHitRectInsets(0, 0, 0, 0)
            self._DragonUI_SettingPoint = nil
        end

        -- Re-enforce portrait positioning and refresh texture
        local portrait = _G[frameName .. "Portrait"]
        if portrait then
            portrait:ClearAllPoints()
            portrait:SetSize(56, 56)
            portrait:SetPoint("TOPRIGHT", self, "TOPRIGHT", -47, -15)
            portrait:SetDrawLayer("ARTWORK", 1)
            local unit = self.unit or self:GetAttribute("unit")
            if unit and UnitExists(unit) then
                SetPortraitTexture(portrait, unit)
            end
        end

        -- Re-enforce health bar sizing and position
        local healthBar = _G[frameName .. "HealthBar"]
        if healthBar and portrait then
            healthBar:ClearAllPoints()
            healthBar:SetSize(125, 20)
            healthBar:SetPoint("RIGHT", portrait, "LEFT", -1, 0)
            healthBar:SetFrameLevel(self:GetFrameLevel() + 1)
            local statusBarTex = healthBar:GetStatusBarTexture()
            if statusBarTex then
                statusBarTex:SetAllPoints(healthBar)
            end
        end

        -- Re-enforce mana bar sizing and position
        local manaBar = _G[frameName .. "ManaBar"]
        if manaBar and portrait then
            manaBar:ClearAllPoints()
            manaBar:SetSize(132, 9)
            manaBar:SetPoint("RIGHT", portrait, "LEFT", 6.5, -16.5)
            manaBar:SetFrameLevel(self:GetFrameLevel() + 1)
            local statusBarTex = manaBar:GetStatusBarTexture()
            if statusBarTex then
                statusBarTex:SetAllPoints(manaBar)
            end
        end

        -- Hide Blizzard border and re-anchor our textures
        local blizzBorder = _G[frameName .. "TextureFrameTexture"]
        if blizzBorder then blizzBorder:SetAlpha(0) end
        UpdateBossFrameBorder(self)

        -- Re-enforce elite decoration on decoFrame
        if self.DragonUI_Elite and portrait then
            local unit = self.unit or self:GetAttribute("unit")
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
                self.DragonUI_Elite:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
                self.DragonUI_Elite:SetSize(coords[5], coords[6])
                self.DragonUI_Elite:ClearAllPoints()
                self.DragonUI_Elite:SetPoint("CENTER", portrait, "CENTER", coords[7], coords[8])
                self.DragonUI_Elite:SetDrawLayer("OVERLAY", 6)
                self.DragonUI_Elite:Show()
            end
        end

        -- Re-enforce name background
        local nameBG = _G[frameName .. "NameBackground"]
        if nameBG and healthBar then
            nameBG:ClearAllPoints()
            nameBG:SetPoint("BOTTOMLEFT", healthBar, "TOPLEFT", -2, -5)
            nameBG:SetSize(135, 18)
            nameBG:SetTexture(TEXTURES.NAME_BACKGROUND)
        end

        -- Re-enforce flash (race condition fix)
        local flashTex = _G[frameName .. "Flash"]
        EnforceFlashStyle(flashTex, self)

        -- Re-enforce raid target icon draw layer (like target_style.lua)
        local raidTargetIcon = _G[frameName .. "TextureFrameRaidTargetIcon"]
        if raidTargetIcon then
            raidTargetIcon:SetDrawLayer("OVERLAY", 7)
            raidTargetIcon:SetSize(24, 24)
            raidTargetIcon:ClearAllPoints()
            if portrait then
                raidTargetIcon:SetPoint("CENTER", portrait, "TOP", 0, 5)
            end
        end

        -- Re-hide Blizzard background
        local bg = _G[frameName .. "Background"]
        if bg then bg:SetAlpha(0) end
    end

    hooksecurefunc("TargetFrame_Update", function(self)
        if InCombatLockdown() then
            if addon.CombatQueue and self and self.GetName then
                local frameName = self:GetName()
                if frameName and frameName:match("^Boss%dTargetFrame$") then
                    addon.CombatQueue:Add("boss_targetframe_update_" .. frameName, function()
                        if self and self.GetName and self:GetName() == frameName and not InCombatLockdown() then
                            RefreshBossTargetFrameLayout(self)
                        end
                    end)
                end
            end
            return
        end

        RefreshBossTargetFrameLayout(self)
    end)

    BossModule.targetFrameUpdateHooked = true
end

-- ============================================================================
-- POSITIONING
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

                if addon.VisibilityFade then
                    addon.VisibilityFade.Register("boss" .. i, bf, {
                        dbTable = function() return UF.GetConfig("boss") end,
                        clickThrough = true,
                    })
                end
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
                    bf:ClearAllPoints()
                    bf:SetPoint("TOPLEFT", w, "TOPLEFT", 0, 0)
                    bf:Show()
                    UpdateBossFrame(bf)
                    if addon.VisibilityFade then
                        addon.VisibilityFade.Update("boss" .. idx)
                    end
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
            if bf then
                bf:Hide()
            end
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

    for i = 1, NUM_BOSS_FRAMES do
        if addon.VisibilityFade then
            addon.VisibilityFade.Update("boss" .. i)
        end
    end
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
