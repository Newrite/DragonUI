-- ============================================================================
-- DragonUI - Buff Frame Module
-- Based on RetailUI by Dmitriy (MIT License)
-- Adapted for DragonUI with Dragonflight-inspired positioning control.
--
-- KEY DESIGN (inspired by Ascension's clean BuffFrame pattern):
--   Instead of overriding SetPoint/ClearAllPoints or competing with
--   anchor chain via scattered hooks, we let native
--   BuffFrame_UpdateAllBuffAnchors run first, then move the ENTIRE BuffFrame
--   (with all its children already correctly anchored) to follow our
--   dragonUIBuffFrame in ONE pass. No per-icon re-anchoring, no offset
--   caching, no absolute UIParent positioning of sub-frames.
-- ============================================================================

local addon = select(2, ...);

local BuffFrameModule = {}
addon.BuffFrameModule = BuffFrameModule

-- Register with ModuleRegistry (if available)
if addon.RegisterModule then
    addon:RegisterModule("buffs", BuffFrameModule,
        (addon.L and addon.L["Buff Frame"]) or "Buff Frame",
        (addon.L and addon.L["Custom buff frame styling, positioning and toggle button"]) or "Custom buff frame styling, positioning and toggle button")
end

-- Local variables
local buffFrame = nil
local toggleButton = nil
local dragonUIBuffFrame = nil
local dragonUIWeaponBuffFrame = nil
local buffsHiddenByToggle = false
local weaponEnchantsAreSeparated = false

-- Default buff frame position (must match database.lua defaults)
local BUFF_DEFAULT_ANCHOR = "TOPRIGHT"
local BUFF_DEFAULT_POSX = -270
local BUFF_DEFAULT_POSY = -15

-- Y position when a GM ticket or GM chat panel is open
local BUFF_TICKET_POSY = -60

-- Save original BuffFrame method BEFORE anything modifies it
local original_BuffFrame_SetPoint = BuffFrame.SetPoint

-- Default weapon enchant frame position
local WEAPON_DEFAULT_ANCHOR = "TOPRIGHT"
local WEAPON_DEFAULT_POSX = -270
local WEAPON_DEFAULT_POSY = -170

-- Flag: when true, our SetPoint override is active
local buffFramePositionLocked = false


-- Check if buff frame is at default position (not moved by editor)
-- Uses a saved flag instead of coordinate comparison to avoid stale profile values
local function IsBuffFrameAtDefaultPosition()
    if not addon.db or not addon.db.profile or not addon.db.profile.widgets or not addon.db.profile.widgets.buffs then
        return true  -- safe default: treat as default position
    end
    return not addon.db.profile.widgets.buffs.custom_position
end

-- Check if weapon enchant separation is enabled in the profile
local function IsWeaponEnchantSeparationEnabled()
    return addon.db and addon.db.profile and addon.db.profile.buffs
        and addon.db.profile.buffs.separate_weapon_enchants
end

-- Check if weapon enchant frame is at its default position
local function IsWeaponEnchantAtDefaultPosition()
    if not addon.db or not addon.db.profile or not addon.db.profile.widgets
       or not addon.db.profile.widgets.weapon_enchants then
        return true
    end
    return not addon.db.profile.widgets.weapon_enchants.custom_position
end


-- ============================================================================
-- HELPER: Re-anchor BuffFrame to dragonUIBuffFrame
-- Called after every layout pass so BuffFrame follows our controlled frame.
-- Children (ConsolidatedBuffs, TempEnchantFrame, BuffButtons) stay correctly
-- positioned relative to BuffFrame because Blizzard just laid them out.
-- ============================================================================
local function AnchorBuffFrameToDragonUI()
    if not buffFramePositionLocked or not dragonUIBuffFrame then return end
    original_BuffFrame_SetPoint(BuffFrame, "TOPRIGHT", dragonUIBuffFrame, "TOPRIGHT", 0, 0)
end

-- ============================================================================
-- HELPER: Anchor ConsolidatedBuffs to BuffFrame (fresh, no cached offset)
-- Blizzard's native layout anchors CB to BuffFrame, but something may break
-- that relationship. This re-establishes it with the standard offset.
-- ============================================================================
local function AnchorConsolidatedBuffs()
    if not ConsolidatedBuffs or not buffFramePositionLocked then return end
    -- Standard WotLK offset: CB sits at BuffFrame's TOPRIGHT
    ConsolidatedBuffs:ClearAllPoints()
    ConsolidatedBuffs:SetPoint("TOPRIGHT", BuffFrame, "TOPRIGHT", -4, -5)
end

-- ============================================================================
-- HELPER: Anchor VanityBuffs in the buff chain
-- The chain is: BuffFrame → ConsolidatedBuffs → VanityBuffs →
--               TemporaryEnchantFrame → BuffButton1 → ...
-- VanityBuffs anchors FROM ConsolidatedBuffs (not to TempEnchantFrame,
-- which would create a circular chain).
-- Uses frame-relative anchoring inspired by Ascension's clean pattern,
-- NOT absolute UIParent coordinates (which broke on scale changes).
-- ============================================================================
local function AnchorVanityBuffs()
    if not VanityBuffs then return end
    VanityBuffs:ClearAllPoints()
    if BuffFrame.numConsolidated > 0 then
        -- CB visible: VanityBuffs sits to CB's LEFT
        VanityBuffs:SetPoint("TOPRIGHT", ConsolidatedBuffs, "TOPLEFT", -6, 0)
    else
        -- CB hidden: VanityBuffs at CB's position (same spot as BuffFrame TOPRIGHT)
        VanityBuffs:SetPoint("TOPRIGHT", ConsolidatedBuffs, "TOPRIGHT", 0, 0)
    end
end


-- ============================================================================
-- TOGGLE BUTTON
-- ============================================================================

-- Create the collapse/expand toggle button
local function CreateToggleButton(frame)
    if toggleButton then return end

    toggleButton = CreateFrame('Button', nil, UIParent)
    toggleButton.toggle = true
    toggleButton:SetSize(9, 17)
    toggleButton:SetHitRectInsets(0, 0, 0, 0)

    local normalTexture = toggleButton:CreateTexture(nil, "BORDER")
    normalTexture:SetAllPoints(toggleButton)
    normalTexture:set_atlas('CollapseButton-Right', true)
    toggleButton:SetNormalTexture(normalTexture)

    local highlightTexture = toggleButton:CreateTexture(nil, "ARTWORK")
    highlightTexture:SetAllPoints(toggleButton)
    highlightTexture:set_atlas('CollapseButton-Right', true)
    toggleButton:SetHighlightTexture(highlightTexture)

    toggleButton:SetScript("OnClick", function(self)
        self.toggle = not self.toggle
        if not self.toggle then
            -- HIDE buffs
            buffsHiddenByToggle = true
            if addon.db and addon.db.profile and addon.db.profile.buffs then
                addon.db.profile.buffs.buffs_hidden = true
            end
            local normalTexture = self:GetNormalTexture()
            normalTexture:set_atlas('CollapseButton-Left', true)
            local highlightTex = toggleButton:GetHighlightTexture()
            if highlightTex then
                highlightTex:set_atlas('CollapseButton-Left', true)
            end

            for index = 1, BUFF_ACTUAL_DISPLAY do
                local button = _G['BuffButton' .. index]
                if button then
                    button:Hide()
                end
            end
            if VanityBuffs then VanityBuffs:Hide() end
            if TemporaryEnchantFrame then TemporaryEnchantFrame:Hide() end
        else
            -- SHOW buffs
            buffsHiddenByToggle = false
            if addon.db and addon.db.profile and addon.db.profile.buffs then
                addon.db.profile.buffs.buffs_hidden = false
            end
            local normalTexture = self:GetNormalTexture()
            normalTexture:set_atlas('CollapseButton-Right', true)
            local highlightTex = toggleButton:GetHighlightTexture()
            if highlightTex then
                highlightTex:set_atlas('CollapseButton-Right', true)
            end

            for index = 1, BUFF_ACTUAL_DISPLAY do
                local button = _G['BuffButton' .. index]
                if button then
                    button:Show()
                end
            end
            if VanityBuffs then VanityBuffs:Show() end
            if TemporaryEnchantFrame then TemporaryEnchantFrame:Show() end
            if BuffFrame_UpdateAllBuffAnchors then
                BuffFrame_UpdateAllBuffAnchors()
            end
        end
    end)

    -- Initial position (corrected on every layout pass by the hook)
    if ConsolidatedBuffs then
        toggleButton:SetPoint("LEFT", ConsolidatedBuffs, "RIGHT", 4, -6)
    else
        toggleButton:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -12, -6)
    end
end

-- Show/hide toggle button based on condition
local function ShowToggleButtonIf(condition)
    if toggleButton then
        if condition then
            toggleButton:Show()
        else
            toggleButton:Hide()
        end
    end
end

-- Count active buffs on a unit
local function GetUnitBuffCount(unit, range)
    local count = 0
    for index = 1, range do
        local name = UnitBuff(unit, index)
        if name then
            count = count + 1
        end
    end
    return count
end

-- ============================================================================
-- POSITIONING SYSTEM
-- We override BuffFrame.SetPoint so that NO Blizzard code can move BuffFrame
-- independently of dragonUIBuffFrame. Every SetPoint call redirects to anchor
-- it to our frame. Unlike the old approach, we do NOT noop ClearAllPoints
-- (that broke other code paths) — we only redirect SetPoint. Children are
-- never orphaned because we always maintain the anchor relationship.
-- ============================================================================

-- Update the position of dragonUIBuffFrame (BuffFrame follows via override)
function BuffFrameModule:UpdatePosition()
    if not dragonUIBuffFrame then return end
    if not addon.db or not addon.db.profile or not addon.db.profile.widgets or not addon.db.profile.widgets.buffs then
        return
    end

    local widgetOptions = addon.db.profile.widgets.buffs

    if IsBuffFrameAtDefaultPosition() then
        -- Default position: shift down when ticket/GM panel is open
        local ticketOpen = (TicketStatusFrame and TicketStatusFrame:IsShown())
                        or (GMChatStatusFrame and GMChatStatusFrame:IsShown())
        local posY = ticketOpen and BUFF_TICKET_POSY or BUFF_DEFAULT_POSY
        dragonUIBuffFrame:ClearAllPoints()
        dragonUIBuffFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", BUFF_DEFAULT_POSX, posY)
    else
        -- Custom position (user-placed via editor): use saved coordinates
        dragonUIBuffFrame:ClearAllPoints()
        dragonUIBuffFrame:SetPoint(
            widgetOptions.anchor, UIParent, widgetOptions.anchor,
            widgetOptions.posX, widgetOptions.posY)
    end
end

-- ============================================================================
-- WEAPON ENCHANT SEPARATION SYSTEM
-- Creates an independent moveable frame for TempEnchant1/2/3 (weapon poisons,
-- sharpening stones, etc.), detaching them from the regular buff anchor chain.
-- ============================================================================

-- Update the weapon enchant frame position from saved profile data
function BuffFrameModule:UpdateWeaponEnchantPosition()
    if not dragonUIWeaponBuffFrame then return end
    if not addon.db or not addon.db.profile or not addon.db.profile.widgets
       or not addon.db.profile.widgets.weapon_enchants then return end

    local wOpts = addon.db.profile.widgets.weapon_enchants

    if IsWeaponEnchantAtDefaultPosition() then
        dragonUIWeaponBuffFrame:ClearAllPoints()
        dragonUIWeaponBuffFrame:SetPoint(WEAPON_DEFAULT_ANCHOR, UIParent, "TOPRIGHT",
            WEAPON_DEFAULT_POSX, WEAPON_DEFAULT_POSY)
    else
        dragonUIWeaponBuffFrame:ClearAllPoints()
        dragonUIWeaponBuffFrame:SetPoint(
            wOpts.anchor, UIParent, wOpts.anchor,
            wOpts.posX, wOpts.posY)
    end
end

-- Anchor TemporaryEnchantFrame to our weapon enchant frame
local function AnchorWeaponEnchantsToFrame()
    if not TemporaryEnchantFrame or not dragonUIWeaponBuffFrame then return end
    TemporaryEnchantFrame:ClearAllPoints()
    TemporaryEnchantFrame:SetPoint("TOPRIGHT", dragonUIWeaponBuffFrame, "TOPRIGHT", 0, 0)
end

-- Restore TemporaryEnchantFrame to the natural buff chain
local function RestoreWeaponEnchantsToChain()
    if not TemporaryEnchantFrame then return end
    local cb = _G.ConsolidatedBuffs
    if cb then
        TemporaryEnchantFrame:ClearAllPoints()
        if cb:IsShown() then
            TemporaryEnchantFrame:SetPoint("TOPRIGHT", cb, "TOPLEFT", -6, 0)
        else
            TemporaryEnchantFrame:SetPoint("TOPRIGHT", cb, "TOPRIGHT", 0, 0)
        end
    end
end

-- Create (or show) the weapon enchant anchor frame and register with editor.
-- Called from Enable() and from the runtime toggle.
function BuffFrameModule:SetupWeaponEnchantSeparation()
    if not IsWeaponEnchantSeparationEnabled() then
        -- Feature disabled — make sure runtime flag is off and clean up
        if weaponEnchantsAreSeparated then
            weaponEnchantsAreSeparated = false
            RestoreWeaponEnchantsToChain()
            if dragonUIWeaponBuffFrame then
                dragonUIWeaponBuffFrame:Hide()
            end
        end
        return
    end

    weaponEnchantsAreSeparated = true

    -- Create the frame once
    if not dragonUIWeaponBuffFrame then
        -- Size matches roughly 3 temp enchant icons (30px each + spacing)
        dragonUIWeaponBuffFrame = addon.CreateUIFrame(100, 34, "WeaponEnchants")

        addon:RegisterEditableFrame({
            name = "weapon_enchants",
            frame = dragonUIWeaponBuffFrame,
            blizzardFrame = TemporaryEnchantFrame,
            configPath = {"widgets", "weapon_enchants"},
            onHide = function()
                -- After editor saves, check if position matches the default
                local w = addon.db.profile.widgets.weapon_enchants
                if w then
                    local isDefault = w.anchor == WEAPON_DEFAULT_ANCHOR
                        and math.abs(w.posX - WEAPON_DEFAULT_POSX) <= 5
                        and math.abs(w.posY - WEAPON_DEFAULT_POSY) <= 5
                    w.custom_position = not isDefault
                end
                self:UpdateWeaponEnchantPosition()
                AnchorWeaponEnchantsToFrame()
            end,
            module = self
        })
    end

    dragonUIWeaponBuffFrame:Show()
    self:UpdateWeaponEnchantPosition()
    AnchorWeaponEnchantsToFrame()
end

-- Runtime toggle: switch weapon enchant separation on/off without reload
function BuffFrameModule:ToggleWeaponEnchantSeparation(enabled)
    if not addon.db or not addon.db.profile or not addon.db.profile.buffs then return end
    addon.db.profile.buffs.separate_weapon_enchants = enabled
    self:SetupWeaponEnchantSeparation()
    -- Force a buff layout refresh so the anchor chain updates immediately
    if BuffFrame_UpdateAllBuffAnchors then
        BuffFrame_UpdateAllBuffAnchors()
    end
end

-- Toggle module on/off
function BuffFrameModule:Toggle(enabled)
    if not addon.db or not addon.db.profile then return end

    addon.db.profile.buffs.enabled = enabled

    if enabled then
        self:Enable()
    else
        if addon:ShouldDeferModuleDisable("buffs", self) then
            return
        end
        self:Disable()
    end
end

-- Enable the buff frame module
function BuffFrameModule:Enable()
    if not addon.db.profile.buffs.enabled then return end
    if dragonUIBuffFrame then return end  -- already enabled

    -- Create auxiliary frame for editor mode
    dragonUIBuffFrame = addon.CreateUIFrame(BuffFrame:GetWidth(), BuffFrame:GetHeight(), "Auras")

    -- Register with editor system
    addon:RegisterEditableFrame({
        name = "buffs",
        frame = dragonUIBuffFrame,
        blizzardFrame = BuffFrame,
        configPath = {"widgets", "buffs"},
        onHide = function()
            -- After editor saves position, check if it matches the default
            local w = addon.db.profile.widgets.buffs
            local isDefault = w.anchor == BUFF_DEFAULT_ANCHOR
                and math.abs(w.posX - BUFF_DEFAULT_POSX) <= 5
                and math.abs(w.posY - BUFF_DEFAULT_POSY) <= 5
            w.custom_position = not isDefault
            self:UpdatePosition()
            -- Force a full buff layout recalculation so that the icons follow
            if BuffFrame_UpdateAllBuffAnchors then
                BuffFrame_UpdateAllBuffAnchors()
            end
        end,
        module = self
    })

    -- ========================================================================
    -- WEAPON ENCHANT SEPARATION (FEATURE)
    -- When enabled, weapon enchant icons (TempEnchant1/2/3) are detached from
    -- the regular buff chain and anchored to their own independently-moveable
    -- frame.
    -- ========================================================================
    self:SetupWeaponEnchantSeparation()

    -- ========================================================================
    -- SETPOINT OVERRIDE
    -- We override BuffFrame.SetPoint to redirect EVERY SetPoint call to anchor
    -- BuffFrame to our dragonUIBuffFrame. This prevents Blizzard from moving
    -- BuffFrame away from our controlled position.
    --
    -- KEY DESIGN: Unlike the old approach, we do NOT noop ClearAllPoints
    -- (which broke Blizzard's UIParent_ManageFramePositions), and we do NOT
    -- call ClearAllPoints ourselves inside the override (which would orphan
    -- children during layout). We simply redirect the anchor point.
    --
    -- Because all children (CB, TempEnchant, BuffButtons) are anchored to
    -- BuffFrame, they follow when the parent moves. No per-icon re-anchoring
    -- is needed in the common case.
    -- ========================================================================
    buffFramePositionLocked = true

    BuffFrame.SetPoint = function(self, ...)
        if not buffFramePositionLocked or not dragonUIBuffFrame then
            -- Module disabled or not ready: use original behavior
            return original_BuffFrame_SetPoint(self, ...)
        end
        -- Redirect: anchor BuffFrame to our controlled frame instead of
        -- wherever Blizzard tried to put it. Children follow automatically
        -- because they're anchored to BuffFrame.
        return original_BuffFrame_SetPoint(self, "TOPRIGHT", dragonUIBuffFrame, "TOPRIGHT", 0, 0)
    end

    -- Set initial position: anchor BuffFrame to our controlled frame.
    BuffFrame:ClearAllPoints()
    original_BuffFrame_SetPoint(BuffFrame, "TOPRIGHT", dragonUIBuffFrame, "TOPRIGHT", 0, 0)
    BuffFrameModule:UpdatePosition()

    -- ========================================================================
    -- HOOK: BuffFrame_UpdateAllBuffAnchors — THE ONE AUTHORITATIVE HOOK
    --
    -- After Blizzard lays out ALL children (ConsolidatedBuffs, VanityBuffs,
    -- TemporaryEnchantFrame, BuffButtons, DebuffButtons), we do a single
    -- corrective pass:
    --
    -- 1. Ensure ConsolidatedBuffs is anchored to BuffFrame (handles rare cases
    --    where Blizzard's native anchor was lost)
    -- 2. Anchor VanityBuffs cleanly in the frame chain
    -- 3. Handle weapon enchant separation (re-parent TempEnchantFrame if needed)
    -- 4. Anchor first DebuffButton below the last buff row
    -- 5. Position the toggle button to the right of ConsolidatedBuffs
    -- 6. Apply the hidden-by-toggle state
    -- 7. Re-anchor BuffFrame to dragonUIBuffFrame (moves everything as a unit)
    --
    -- No per-icon offsets cached. No absolute UIParent positioning.
    -- No competing hooks. This is THE ONLY place we fix icon positions.
    -- ========================================================================
    if not BuffFrameModule._hookedBuffAnchors then
        BuffFrameModule._hookedBuffAnchors = true
        hooksecurefunc("BuffFrame_UpdateAllBuffAnchors", function()
            if not buffFramePositionLocked then return end

            -- 1) Ensure ConsolidatedBuffs is anchored to BuffFrame
            if ConsolidatedBuffs then
                local _, rel = ConsolidatedBuffs:GetPoint(1)
                if not rel or rel ~= BuffFrame then
                    AnchorConsolidatedBuffs()
                end
            end

            -- 2) Anchor VanityBuffs cleanly in the frame chain
            if VanityBuffs then
                AnchorVanityBuffs()
            end

            -- 3) Handle weapon enchant separation
            if weaponEnchantsAreSeparated then
                -- Blizzard's VanityBuffs_OnShow put TempEnchantFrame in the
                -- normal chain. Undo that and re-parent to our frame.
                AnchorWeaponEnchantsToFrame()

                -- When enchants are separated, BuffButton1 would anchor to
                -- TempEnchantFrame (which is now on its own frame). Re-anchor
                -- the first non-consolidated buff to ConsolidatedBuffs so the
                -- icon chain is correct.
                local numVisible = 0
                for i = 1, BUFF_ACTUAL_DISPLAY do
                    local btn = _G["BuffButton" .. i]
                    if btn and btn:IsShown() and not btn.consolidated then
                        numVisible = numVisible + 1
                        if numVisible == 1 then
                            btn:ClearAllPoints()
                            if ConsolidatedBuffs and ConsolidatedBuffs:IsShown() then
                                btn:SetPoint("TOPRIGHT", ConsolidatedBuffs, "TOPLEFT", -6, 0)
                            else
                                btn:SetPoint("TOPRIGHT", dragonUIBuffFrame, "TOPRIGHT", 0, 0)
                            end
                        end
                        break
                    end
                end
            end

            -- 4) Fix first debuff position: anchor below the last buff row
            --    Blizzard anchors debuffs to ConsolidatedBuffs, but since we
            --    moved BuffFrame (and CB with it), the default debuff position
            --    is too far right. Re-anchor below the last visible buff.
            local lastBuffInLastRow = nil
            local numVisible = 0
            local slack = weaponEnchantsAreSeparated and 0 or (BuffFrame.numEnchants or 0)
            local perRow = BUFFS_PER_ROW or 16
            for i = 1, BUFF_ACTUAL_DISPLAY do
                local btn = _G["BuffButton" .. i]
                if btn and btn:IsShown() and not btn.consolidated then
                    numVisible = numVisible + 1
                    local idx = numVisible + slack
                    if idx > 1 and math.fmod(idx, perRow) == 1 then
                        -- New row starts here — store this as "first in last row"
                        lastBuffInLastRow = btn
                    end
                    -- Always track the LAST visible buff
                    lastBuffInLastRow = btn
                end
            end
            -- The first debuff's anchor determines where ALL debuffs sit
            -- (each subsequent debuff chains from the previous one).
            -- We only need to fix DebuffButton1 — Blizzard handles the rest.
            local debuff1 = _G["DebuffButton1"]
            if debuff1 then
                local debuffY = -60  -- gap below last buff row
                debuff1:ClearAllPoints()
                if lastBuffInLastRow then
                    debuff1:SetPoint("TOPRIGHT", lastBuffInLastRow, "BOTTOMRIGHT", 0, debuffY)
                elseif dragonUIBuffFrame then
                    debuff1:SetPoint("TOPRIGHT", dragonUIBuffFrame, "BOTTOMRIGHT", 0, debuffY)
                end
            end

            -- 5) Position the toggle button to the right of ConsolidatedBuffs
            if toggleButton then
                toggleButton:ClearAllPoints()
                if ConsolidatedBuffs then
                    toggleButton:SetPoint("LEFT", ConsolidatedBuffs, "RIGHT", 4, -6)
                else
                    toggleButton:SetPoint("TOPRIGHT", dragonUIBuffFrame, "TOPRIGHT", 12, -6)
                end
            end

            -- 6) Respect buff toggle: re-hide buffs if user collapsed them
            if buffsHiddenByToggle then
                for i = 1, BUFF_ACTUAL_DISPLAY do
                    local btn = _G["BuffButton" .. i]
                    if btn then
                        btn:Hide()
                    end
                end
                if VanityBuffs then VanityBuffs:Hide() end
                if TemporaryEnchantFrame then TemporaryEnchantFrame:Hide() end
            end

            -- 7) MOVE BUFFRAME TO OUR CONTROLLED POSITION (final step)
            --    After Blizzard laid out all children relative to BuffFrame,
            --    we move the entire frame+children as a unit to follow
            --    dragonUIBuffFrame. No flicker because this is the last thing
            --    that happens in the layout pass.
            AnchorBuffFrameToDragonUI()
        end)
    end

    -- ========================================================================
    -- HOOK: UIParent_ManageFramePositions — fires on ticket open/close and
    -- other layout events. We update our frame position and ensure the anchor
    -- chain is intact. This does NOT re-lay out icons — that's the job of
    -- the BuffFrame_UpdateAllBuffAnchors hook, which fires on UNIT_AURA.
    -- ========================================================================
    if not BuffFrameModule._hookedManagePositions then
        BuffFrameModule._hookedManagePositions = true
        hooksecurefunc("UIParent_ManageFramePositions", function()
            if not dragonUIBuffFrame then return end
            if not addon.db or not addon.db.profile or not addon.db.profile.buffs
               or not addon.db.profile.buffs.enabled then return end
            -- UpdatePosition() is safe at ANY position: at default it shifts
            -- for tickets, at custom it re-applies the saved coords (no-op).
            BuffFrameModule:UpdatePosition()
            -- Re-anchor BuffFrame to dragonUIBuffFrame — Blizzard may have
            -- moved BuffFrame during UIParent_ManageFramePositions, and our
            -- SetPoint override handles most cases, but in rare instances
            -- (profile change, reload) the override may not fire. This ensures
            -- the anchor is solid.
            AnchorBuffFrameToDragonUI()
            -- Also ensure ConslidatedBuffs didn't lose its anchor to BuffFrame
            if ConsolidatedBuffs then
                local _, rel = ConsolidatedBuffs:GetPoint(1)
                if not rel or rel ~= BuffFrame then
                    AnchorConsolidatedBuffs()
                end
            end
        end)
    end

    -- ========================================================================
    -- TICKET FRAME HOOKS — update position without re-laying out icons
    -- ========================================================================
    if not BuffFrameModule._hookedTicketFrame then
        BuffFrameModule._hookedTicketFrame = true
        local function OnTicketChange()
            if dragonUIBuffFrame and IsBuffFrameAtDefaultPosition() then
                BuffFrameModule:UpdatePosition()
                AnchorBuffFrameToDragonUI()
            end
        end
        if TicketStatusFrame then
            hooksecurefunc(TicketStatusFrame, "Show", OnTicketChange)
            hooksecurefunc(TicketStatusFrame, "Hide", OnTicketChange)
        end
        if GMChatStatusFrame then
            hooksecurefunc(GMChatStatusFrame, "Show", OnTicketChange)
            hooksecurefunc(GMChatStatusFrame, "Hide", OnTicketChange)
        end
    end

    -- ========================================================================
    -- EVENTS
    -- ========================================================================
    if not buffFrame then
        buffFrame = CreateFrame("Frame")
        buffFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        buffFrame:RegisterEvent("UNIT_AURA")
        buffFrame:RegisterEvent("UNIT_ENTERED_VEHICLE")
        buffFrame:RegisterEvent("UNIT_EXITED_VEHICLE")

        buffFrame:SetScript("OnEvent", function(self, event, unit)
            if event == "PLAYER_ENTERING_WORLD" then
                CreateToggleButton(dragonUIBuffFrame)
                ShowToggleButtonIf(GetUnitBuffCount("player", 16) > 0)
                BuffFrameModule:UpdatePosition()

                -- Restore buff toggle state from saved profile
                if addon.db and addon.db.profile and addon.db.profile.buffs
                   and addon.db.profile.buffs.buffs_hidden then
                    buffsHiddenByToggle = true
                    toggleButton.toggle = false
                    local normalTex = toggleButton:GetNormalTexture()
                    normalTex:set_atlas('CollapseButton-Left', true)
                    local highlightTex = toggleButton:GetHighlightTexture()
                    if highlightTex then
                        highlightTex:set_atlas('CollapseButton-Left', true)
                    end
                    for index = 1, BUFF_ACTUAL_DISPLAY do
                        local button = _G['BuffButton' .. index]
                        if button then button:Hide() end
                    end
                    if VanityBuffs then VanityBuffs:Hide() end
                    if TemporaryEnchantFrame then TemporaryEnchantFrame:Hide() end
                end

                -- Reposition the GM ticket frame so it doesn't overlap the minimap
                if TicketStatusFrame then
                    TicketStatusFrame:ClearAllPoints()
                    TicketStatusFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -270, -5)
                end
            elseif event == "UNIT_AURA" then
                if unit == 'vehicle' then
                    ShowToggleButtonIf(GetUnitBuffCount("vehicle", 16) > 0)
                elseif unit == 'player' then
                    ShowToggleButtonIf(GetUnitBuffCount("player", 16) > 0)
                end
            elseif event == "UNIT_ENTERED_VEHICLE" then
                if unit == 'player' then
                    ShowToggleButtonIf(GetUnitBuffCount("vehicle", 16) > 0)
                end
            elseif event == "UNIT_EXITED_VEHICLE" then
                if unit == 'player' then
                    ShowToggleButtonIf(GetUnitBuffCount("player", 16) > 0)
                end
            end
        end)
    end
end

-- Disable the buff frame module
function BuffFrameModule:Disable()
    -- Restore original BuffFrame positioning method
    buffFramePositionLocked = false
    BuffFrame.SetPoint = original_BuffFrame_SetPoint

    -- Clean up weapon enchant separation
    if weaponEnchantsAreSeparated then
        weaponEnchantsAreSeparated = false
        RestoreWeaponEnchantsToChain()
    end
    if dragonUIWeaponBuffFrame then
        dragonUIWeaponBuffFrame:Hide()
        -- Don't nil it — may be re-enabled without reload
    end

    if buffFrame then
        buffFrame:UnregisterAllEvents()
        buffFrame:SetScript("OnEvent", nil)
        buffFrame = nil
    end

    if toggleButton then
        toggleButton:Hide()
        toggleButton = nil
    end

    if dragonUIBuffFrame then
        dragonUIBuffFrame:Hide()
        dragonUIBuffFrame = nil
    end
end

-- Initialization
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(self, event, addonName)
    if addonName == "DragonUI" then
        if addon.db and addon.db.profile and addon.db.profile.buffs and addon.db.profile.buffs.enabled then
            BuffFrameModule:Enable()
        end
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

-- Refresh callback for options panel
function addon:RefreshBuffFrame()
    if BuffFrameModule and addon.db.profile.buffs.enabled then
        BuffFrameModule:UpdatePosition()
    end
end
