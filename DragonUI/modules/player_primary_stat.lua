local addon = select(2, ...)
local L = addon.L

local Module = {}
addon.PlayerPrimaryStatModule = Module

if addon.RegisterModule then
    addon:RegisterModule("playerPrimaryStat", Module,
        (L and L["PlayerPrimaryStat"]) or "PlayerPrimaryStat",
        (L and L["Primary stat icon movability widget"]) or "Primary stat icon movability widget")
end

local anchor
local deferredUpdate = false

local DEFAULT_ANCHOR = "TOPLEFT"
local DEFAULT_X = 80
local DEFAULT_Y = -6

local function IsEditorActive()
    return addon.EditorMode and addon.EditorMode.IsActive and addon.EditorMode:IsActive()
end

local function ApplyAnchorPosition()
    if not anchor then return end
    if InCombatLockdown() then return end

    local cfg = addon.db and addon.db.profile and addon.db.profile.widgets
        and addon.db.profile.widgets.playerPrimaryStat
    if not cfg then return end

    anchor:ClearAllPoints()
    anchor:SetPoint(cfg.anchor or DEFAULT_ANCHOR, UIParent,
        cfg.anchor or DEFAULT_ANCHOR, cfg.posX or DEFAULT_X, cfg.posY or DEFAULT_Y)
end

local function ApplyPrimaryStatPosition()
    if InCombatLockdown() then
        deferredUpdate = true
        return
    end

    local stat = PlayerPrimaryStat
    if not stat or not anchor then return end

    if IsEditorActive() then return end

    stat:ClearAllPoints()
    stat:SetPoint("CENTER", anchor, "CENTER", 0, 0)
end

local original_SetPoint

local function OnEnable()
    if anchor then return end

    anchor = addon.CreateUIFrame(30, 30, "PlayerPrimaryStat")

    original_SetPoint = PlayerPrimaryStat.SetPoint
    PlayerPrimaryStat.SetPoint = function(self, ...)
        if IsEditorActive() then return end
        return original_SetPoint(self, ...)
    end

    addon:RegisterEditableFrame({
        name = "playerPrimaryStat",
        frame = anchor,
        blizzardFrame = PlayerPrimaryStat,
        configPath = {"widgets", "playerPrimaryStat"},
        editorVisible = function() return true end,
        showTest = function()
            anchor:Show()
            local cfg = addon.db.profile.widgets.playerPrimaryStat
            if cfg and not cfg.custom_position then
                anchor:ClearAllPoints()
                anchor:SetPoint("TOPLEFT", PlayerFrame, "TOPLEFT", 88, -2)
            else
                ApplyAnchorPosition()
            end
        end,
        onHide = function()
            local w = addon.db.profile.widgets.playerPrimaryStat
            if w then
                local isDefault = w.anchor == DEFAULT_ANCHOR
                    and math.abs((w.posX or 0) - DEFAULT_X) <= 5
                    and math.abs((w.posY or 0) - DEFAULT_Y) <= 5
                w.custom_position = not isDefault
            end
            ApplyAnchorPosition()
            ApplyPrimaryStatPosition()
        end,
        module = Module,
    })

    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function(self, event)
        if deferredUpdate then
            deferredUpdate = false
            ApplyAnchorPosition()
            ApplyPrimaryStatPosition()
        end
    end)

    ApplyAnchorPosition()
    ApplyPrimaryStatPosition()
end

local function OnDisable()
    if not anchor then return end

    anchor:Hide()

    if original_SetPoint then
        PlayerPrimaryStat.SetPoint = original_SetPoint
        original_SetPoint = nil
    end

    PlayerPrimaryStat:ClearAllPoints()
    PlayerPrimaryStat:SetPoint("TOPLEFT", PlayerFrame, "TOPLEFT", 88, -2)
end

Module.Enable = OnEnable
Module.Disable = OnDisable
