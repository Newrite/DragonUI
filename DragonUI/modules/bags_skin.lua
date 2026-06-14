-- ============================================================================
-- Bag Skin Module for DragonUI
-- Applies retail-style (Dragonflight) textures to bags.
-- Works with Combuctor (when enabled) or default Blizzard ContainerFrames.
-- ============================================================================

local addon = select(2, ...)
local L = addon.L

local gmatch = string.gmatch

-- ============================================================================
-- MODULE STATE
-- ============================================================================

local BagSkinModule = {
    applied = false,
    hooks = {},
    frames = {},
    originalStates = {},
}

-- Register with ModuleRegistry
if addon.RegisterModule then
    addon:RegisterModule("bags_skin", BagSkinModule,
        (L and L["Bag Skin"]) or "Bag Skin",
        (L and L["Retail-style textures for bags (Combuctor + default)"]) or
        "Retail-style textures for bags (Combuctor + default)")
end

-- ============================================================================
-- TEXTURE PATHS
-- ============================================================================

local assets = addon._dir

local T = {
    -- Item slot textures (bagsitemslot2x from Dragonflight)
    slot_bg           = assets .. 'bagsitemslot2x',
    slot_bank_bg      = assets .. 'bagsitembankslot2x',
    slot_depress      = assets .. 'ui-quickslot-depress',
    slot_highlight    = assets .. 'buttonhilight-square',
    slot_border       = assets .. 'ui-quickslot2',

    -- Frame border (retail nineslice)
    frame_metal       = assets .. 'uiframemetal2x',
    frame_metal_h     = assets .. 'uiframemetalhorizontal2x',
    frame_metal_v     = assets .. 'uiframemetalvertical2x',
    frame_bg          = assets .. 'ui-background-rock',

    -- Close button
    close_btn         = assets .. 'redbutton2x',

    -- Backpack button
    bigbag            = assets .. 'bigbag',
    bigbag_highlight  = assets .. 'bigbagHighlight',
    bagslot           = assets .. 'bagslots2x',
    bagslot_cutout    = assets .. 'bagslotCutout',

    -- Bag border / mask for item slots
    bag_border        = assets .. 'bagborder2',
    bag_border_empty  = assets .. 'bagborderempty2',
    bag_highlight2    = assets .. 'baghighlight2',
    bag_mask          = assets .. 'bagmask',
}

-- ============================================================================
-- HELPER: Apply nineslice to a frame (retail-style border)
-- ============================================================================

local function AddNineSlice(frame)
    if frame._BagSkin_NineSlice then return end

    local ns = {}
    frame._BagSkin_NineSlice = ns

    ns.TopLeftCorner     = frame:CreateTexture(nil, 'ARTWORK')
    ns.TopRightCorner    = frame:CreateTexture(nil, 'ARTWORK')
    ns.BottomLeftCorner  = frame:CreateTexture(nil, 'ARTWORK')
    ns.BottomRightCorner = frame:CreateTexture(nil, 'ARTWORK')
    ns.TopEdge           = frame:CreateTexture(nil, 'ARTWORK')
    ns.BottomEdge        = frame:CreateTexture(nil, 'ARTWORK')
    ns.LeftEdge          = frame:CreateTexture(nil, 'ARTWORK')
    ns.RightEdge         = frame:CreateTexture(nil, 'ARTWORK')

    -- Background panel
    local bg = CreateFrame('Frame', nil, frame)
    bg:SetPoint('TOPLEFT', frame, 'TOPLEFT', 3, -18)
    bg:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -3, 3)
    bg:SetFrameLevel(0)
    ns.Bg = bg

    -- Solid background texture (slightly transparent)
    local bgTex = bg:CreateTexture(nil, 'BACKGROUND')
    bgTex:SetTexture(T.frame_bg)
    bgTex:SetAllPoints(bg)
    bgTex:SetAlpha(0.85)
    ns.BgTex = bgTex

    -- Corners
    local tlc = ns.TopLeftCorner
    tlc:SetTexture(T.frame_metal)
    tlc:SetTexCoord(0.00195312, 0.294922, 0.00195312, 0.294922)
    tlc:SetSize(75, 74)
    tlc:SetPoint('TOPLEFT', -12, 16)

    local trc = ns.TopRightCorner
    trc:SetTexture(T.frame_metal)
    trc:SetTexCoord(0.298828, 0.591797, 0.00195312, 0.294922)
    trc:SetSize(75, 74)
    trc:SetPoint('TOPRIGHT', 4, 16)

    local blc = ns.BottomLeftCorner
    blc:SetTexture(T.frame_metal)
    blc:SetTexCoord(0.298828, 0.423828, 0.298828, 0.423828)
    blc:SetSize(32, 32)
    blc:SetPoint('BOTTOMLEFT', -12, -3)

    local brc = ns.BottomRightCorner
    brc:SetTexture(T.frame_metal)
    brc:SetTexCoord(0.427734, 0.552734, 0.298828, 0.423828)
    brc:SetSize(32, 32)
    brc:SetPoint('BOTTOMRIGHT', 4, -3)

    -- Top/Bottom edges
    local te = ns.TopEdge
    te:SetTexture(T.frame_metal_h)
    te:SetTexCoord(0, 1, 0.00390625, 0.589844)
    te:SetSize(32, 74)
    te:SetPoint('TOPLEFT', tlc, 'TOPRIGHT', 0, 0)
    te:SetPoint('TOPRIGHT', trc, 'TOPLEFT', 0, 0)

    local be = ns.BottomEdge
    be:SetTexture(T.frame_metal_h)
    be:SetTexCoord(0, 0.5, 0.597656, 0.847656)
    be:SetSize(16, 32)
    be:SetPoint('TOPLEFT', blc, 'TOPRIGHT', 0, 0)
    be:SetPoint('TOPRIGHT', brc, 'TOPLEFT', 0, 0)

    -- Left/Right edges
    local le = ns.LeftEdge
    le:SetTexture(T.frame_metal_v)
    le:SetTexCoord(0.00195312, 0.294922, 0, 1)
    le:SetSize(75, 16)
    le:SetPoint('TOPLEFT', tlc, 'BOTTOMLEFT', 0, 0)
    le:SetPoint('BOTTOMLEFT', blc, 'TOPLEFT', 0, 0)

    local re = ns.RightEdge
    re:SetTexture(T.frame_metal_v)
    re:SetTexCoord(0.298828, 0.591797, 0, 1)
    re:SetSize(75, 16)
    re:SetPoint('TOPRIGHT', trc, 'BOTTOMRIGHT', 0, 0)
    re:SetPoint('BOTTOMRIGHT', brc, 'TOPRIGHT', 0, 0)

    -- Close button restyle
    local closeBtn = frame.ClosePanelButton or _G[frame:GetName() .. 'CloseButton']
    if closeBtn then
        closeBtn:SetSize(24, 24)
        local nt = closeBtn:GetNormalTexture()
        if nt then
            nt:SetTexture(T.close_btn)
            nt:SetTexCoord(0.152344, 0.292969, 0.0078125, 0.304688)
        end
        local pt = closeBtn:GetPushedTexture()
        if pt then
            pt:SetTexture(T.close_btn)
            pt:SetTexCoord(0.152344, 0.292969, 0.320312, 0.617188)
        end
    end
end

-- ============================================================================
-- ITEM SLOT RESTYLE (for ContainerFrameItemButtonTemplate-based buttons)
-- ============================================================================

local function RetailItemSlot(btn)
    if btn._BagSkin_Applied then return end
    btn._BagSkin_Applied = true

    -- NormalTexture → BagsItemSlot2x
    local nt = btn:GetNormalTexture()
    if nt then
        nt:SetTexture(T.slot_bg)
        nt:SetSize(37, 37)
        nt:SetPoint('CENTER', 0, 0)
        nt:SetDrawLayer('BACKGROUND', 3)
    end

    -- PushedTexture → ui-quickslot-depress
    local pt = btn:GetPushedTexture()
    if pt then
        pt:SetTexture(T.slot_depress)
        pt:SetSize(37, 37)
        pt:SetPoint('CENTER', 0, 0)
    end

    -- HighlightTexture → buttonhilight-square
    local ht = btn:GetHighlightTexture()
    if ht then
        ht:SetTexture(T.slot_highlight)
        ht:SetSize(37, 37)
        ht:SetPoint('CENTER', 0, 0)
    end

    -- Hide IconBorder
    if btn.IconBorder then
        btn.IconBorder:Hide()
    end

    -- Add border overlay
    if not btn._BagSkin_Border then
        local border = btn:CreateTexture(nil, 'BACKGROUND')
        border:SetTexture(T.slot_border)
        border:SetSize(64, 64)
        border:SetPoint('CENTER', 0, -1)
        border:SetDrawLayer('BACKGROUND', 4)
        btn._BagSkin_Border = border
    end
end

-- ============================================================================
-- BAG SLOT RESTYLE (Combuctor bag buttons + CharacterBag0-3Slot)
-- ============================================================================

local function RetailBagSlot(btn)
    if btn._BagSkin_Applied then return end
    btn._BagSkin_Applied = true

    local size = 30.5

    -- NormalTexture → bagslots2x
    local nt = btn:GetNormalTexture()
    if nt then
        nt:SetTexture(T.bagslot)
        nt:SetTexCoord(0.576172, 0.695312, 0.5, 0.976562)
        nt:SetSize(size, size)
        nt:SetPoint('CENTER', 2, -1)
        nt:SetDrawLayer('BORDER', 0)
    end

    -- HighlightTexture
    local ht = btn:GetHighlightTexture()
    if ht then
        ht:SetTexture(T.bagslot)
        ht:SetTexCoord(0.699219, 0.818359, 0.0078125, 0.484375)
        ht:SetSize(size, size)
        ht:ClearAllPoints()
        ht:SetPoint('CENTER', 2, -1)
    end

    -- PushedTexture
    local pt = btn:GetPushedTexture()
    if pt then
        pt:SetTexture(T.bagslot)
        pt:SetTexCoord(0.699219, 0.818359, 0.0078125, 0.484375)
        pt:SetSize(size, size)
        pt:ClearAllPoints()
        pt:SetPoint('CENTER', 2, -1)
    end
end

-- ============================================================================
-- BACKPACK BUTTON RESTYLE
-- ============================================================================

local function RetailBackpackButton()
    local btn = MainMenuBarBackpackButton
    if not btn or btn._BagSkin_Backpack then return end
    btn._BagSkin_Backpack = true

    -- Texture
    SetItemButtonTexture(btn, T.bigbag)
    btn:SetHighlightTexture(T.bigbag_highlight)
    btn:SetPushedTexture(T.bigbag_highlight)
    btn:SetCheckedTexture(T.bigbag_highlight)

    -- Hide old normal texture
    if MainMenuBarBackpackButtonNormalTexture then
        MainMenuBarBackpackButtonNormalTexture:Hide()
        MainMenuBarBackpackButtonNormalTexture:SetTexture()
    end

    -- Border overlay
    if not btn._BagSkin_Border then
        local border = btn:CreateTexture(nil, 'OVERLAY')
        border:SetTexture(T.bagslot_cutout)
        border:SetPoint('TOPLEFT', btn, 'TOPLEFT', 0, 0)
        border:SetPoint('BOTTOMRIGHT', btn, 'BOTTOMRIGHT', 0, 0)
        btn._BagSkin_Border = border
    end
end

-- ============================================================================
-- BLIZZARD BAGS: Restyle ContainerFrames (when Combuctor is OFF)
-- ============================================================================

local function BlizzardSkinFrame(frame)
    if not frame or frame._BagSkin_Blizzard then return end
    frame._BagSkin_Blizzard = true

    local name = frame:GetName()
    if not name then return end

    -- Hide Blizzard background textures
    local bgParts = { 'BackgroundTop', 'BackgroundMiddle1', 'BackgroundMiddle2', 'BackgroundBottom' }
    for _, part in ipairs(bgParts) do
        local tex = _G[name .. part]
        if tex then tex:SetAlpha(0) end
    end

    -- Backpack (ContainerFrame1): solo icono bigbag, sin border
    local isBackpack = (name == 'ContainerFrame1')

    -- Restyle portrait (or create one if missing, e.g. backpack)
    local port = _G[name .. 'Portrait']
    if not port then
        port = frame:CreateTexture(name .. 'Portrait', 'ARTWORK')
    end
    -- Backpack siempre usa bigbag.blp
    if isBackpack and port then
        port:SetTexture(T.bigbag)
    end

    if port then
        port:SetAlpha(1)
        local portSize = isBackpack and 58 or 36
        local portOffX = isBackpack and -12 or -4
        local portOffY = isBackpack and 10 or 1
        port:SetSize(portSize, portSize)
        port:ClearAllPoints()
        port:SetPoint('TOPLEFT', frame, 'TOPLEFT', portOffX, portOffY)
        if port.SetDrawLayer then
            port:SetDrawLayer('OVERLAY', 1)
        end
    end

    -- Bag icon border (solo para bolsas que NO son el backpack)
    if port and not isBackpack and not frame._BagSkin_PortraitBorder then
        local borderFrame = CreateFrame('Frame', nil, frame)
        borderFrame:SetSize(48, 48)
        borderFrame:SetPoint('TOPLEFT', frame, 'TOPLEFT', -10, 5)

        -- Obtener frame level de forma segura
        local portLevel = 0
        if port.GetFrameLevel then
            portLevel = port:GetFrameLevel()
        elseif frame.GetFrameLevel then
            portLevel = frame:GetFrameLevel()
        end
        borderFrame:SetFrameLevel(portLevel + 10)

        local pp = borderFrame:CreateTexture(nil, 'OVERLAY')
        pp:SetTexture(T.bag_border)
        pp:SetAllPoints(borderFrame)
        pp:SetDrawLayer('OVERLAY', 7)

        frame._BagSkin_PortraitBorder = borderFrame
    end

    -- Add nineslice border
    AddNineSlice(frame)

    -- Reposition Bg from nineslice to frame bounds
    if frame._BagSkin_NineSlice then
        local ns = frame._BagSkin_NineSlice
        ns.Bg:SetPoint('TOPLEFT', frame, 'TOPLEFT', 3, -18)
        ns.Bg:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -3, 3)
    end

    -- Restyle title
    local title = _G[name .. 'Name']
    if title then
        title:ClearAllPoints()
        title:SetPoint('TOP', frame, 'TOP', 0, -7)
        title:SetFontObject('GameFontNormal')
    end
end

local function BlizzardSkinItemSlots(frame)
    for i = 1, 36 do
        local btn = _G[frame:GetName() .. 'Item' .. i]
        if btn then
            RetailItemSlot(btn)
        end
    end
end

local function BlizzardApply()
    if BagSkinModule.hooks.blizzard then return end

    -- Hook ContainerFrame_Update to restyle frames when bags open/update
    local origContainerFrameUpdate = _G.ContainerFrame_Update
    if not BagSkinModule.originalStates.ContainerFrame_Update then
        BagSkinModule.originalStates.ContainerFrame_Update = origContainerFrameUpdate
    end

    _G.ContainerFrame_Update = function(frame, ...)
        if origContainerFrameUpdate then
            origContainerFrameUpdate(frame, ...)
        end

        if not frame then return end
        BlizzardSkinFrame(frame)
        BlizzardSkinItemSlots(frame)
    end

    -- Restyle existing container frames
    for i = 1, 13 do
        local frame = _G['ContainerFrame' .. i]
        if frame then
            BlizzardSkinFrame(frame)
            BlizzardSkinItemSlots(frame)
        end
    end

    -- Restyle backpack button
    RetailBackpackButton()

    -- Restyle bag slots (CharacterBag0-3Slot)
    for i = 0, 3 do
        local slot = _G['CharacterBag' .. i .. 'Slot']
        if slot then
            RetailBagSlot(slot)
        end
    end

    BagSkinModule.hooks.blizzard = true
end

local function BlizzardRestore()
    if not BagSkinModule.hooks.blizzard then return end

    -- Restore ContainerFrame_Update
    if BagSkinModule.originalStates.ContainerFrame_Update then
        _G.ContainerFrame_Update = BagSkinModule.originalStates.ContainerFrame_Update
        BagSkinModule.originalStates.ContainerFrame_Update = nil
    end

    BagSkinModule.hooks.blizzard = nil
end

-- ============================================================================
-- COMBUCTOR: Restyle frames (when Combuctor is ON)
-- ============================================================================

local function CombuctorSkinFrame(frame)
    if not frame or frame._BagSkin_Combuctor then return end
    frame._BagSkin_Combuctor = true

    -- Hide old textures
    local regions = { frame:GetRegions() }
    for _, child in ipairs(regions) do
        if child:GetObjectType() == 'Texture' then
            child:SetTexture('')
        end
    end

    -- Add nineslice border
    AddNineSlice(frame)

    -- Ajustar NineSlice para que no tape el header
    if frame._BagSkin_NineSlice then
        local ns = frame._BagSkin_NineSlice
        ns.Bg:SetPoint('TOPLEFT',     frame, 'TOPLEFT',     3, -18)
        ns.Bg:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -3, 3)
    end

    -- Icon/Portrait
    local icon = _G[frame:GetName() .. 'IconButton']
    if icon then
        icon:SetSize(36, 36)
        icon:ClearAllPoints()
        icon:SetPoint('TOPLEFT', frame, 'TOPLEFT', -4, 4)
        
        -- Ocultar la textura interna del botón de Combuctor
        local iconTex = icon:GetNormalTexture()
        if iconTex then iconTex:SetAlpha(0) end
        
        -- Crear nuestra propia textura encima
        if not icon._BagSkin_CustomTex then
            local tex = icon:CreateTexture(nil, 'OVERLAY', nil, 1)
            tex:SetTexture(T.bigbag)
            tex:SetAllPoints(icon)
            icon._BagSkin_CustomTex = tex
        end
        
        icon:EnableMouse(false) -- deshabilitar click del portrait
    end

    -- Borde encima del icon
    if icon and not frame._BagSkin_PortraitBorder then
        local borderFrame = CreateFrame('Frame', nil, frame)
        borderFrame:SetSize(48, 48)
        borderFrame:SetPoint('TOPLEFT', frame, 'TOPLEFT', -10, 8)

        local iconLevel = 0
        if icon.GetFrameLevel then
            iconLevel = icon:GetFrameLevel()
        elseif frame.GetFrameLevel then
            iconLevel = frame:GetFrameLevel()
        end
        borderFrame:SetFrameLevel(iconLevel + 10)

        local pp = borderFrame:CreateTexture(nil, 'OVERLAY')
        pp:SetTexture(T.bag_border)
        pp:SetAllPoints(borderFrame)
        pp:SetDrawLayer('OVERLAY', 7)

        frame._BagSkin_PortraitBorder = borderFrame
    end

    -- CloseButton
    local close = _G[frame:GetName() .. 'CloseButton']
    if close then
        close:ClearAllPoints()
        close:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', 8, 8)
    end

    -- Title: ocultar
    local title = _G[frame:GetName() .. 'Title']
    if title then
        title:SetText('')
        title:ClearAllPoints()
        title:SetPoint('TOP', frame, 'TOP', 0, -10)
    end

    -- Search
    local search = _G[frame:GetName() .. 'Search']
    if search then
        search:ClearAllPoints()
        search:SetPoint('TOPLEFT',  frame, 'TOPLEFT',  84, -44)
        search:SetPoint('TOPRIGHT', frame, 'TOPRIGHT', -116, -44)
    end

    -- Reset: a la derecha del search
    local reset = _G[frame:GetName() .. 'Reset']
    if reset then
        reset:ClearAllPoints()
        local s = _G[frame:GetName() .. 'Search']
        if s then
            reset:SetPoint('LEFT', s, 'RIGHT', 2, 0)
        end
    end

    -- BagToggle: a la derecha del reset
    local bagToggle = _G[frame:GetName() .. 'BagToggle']
    if bagToggle then
        bagToggle:ClearAllPoints()
        if reset then
            bagToggle:SetPoint('LEFT', reset, 'RIGHT', 2, 0)
        end
    end

    -- Disable portrait click
    local portBtn = _G[frame:GetName() .. 'PortraitButton']
    if portBtn then portBtn:EnableMouse(false) end
end

local function CombuctorSkinItems(frame)
    -- Find all item buttons within this frame (children using ContainerFrameItemButtonTemplate)
    -- They are named DragonUI_CombuctorItemX and parented to dummy bag frames
    for _, child in ipairs({ frame:GetChildren() }) do
        if child:GetObjectType() == 'Frame' then
            for _, subchild in ipairs({ child:GetChildren() }) do
                if subchild:GetObjectType() == 'Button' and subchild:GetName() then
                    local name = subchild:GetName()
                    if name:find('DragonUI_CombuctorItem') then
                        RetailItemSlot(subchild)
                    end
                end
            end
        end
    end
end

local function CombuctorSkinBagSlots(frame)
    for _, child in ipairs({ frame:GetChildren() }) do
        if child:GetObjectType() == 'Frame' then
            for _, subchild in ipairs({ child:GetChildren() }) do
                if subchild:GetObjectType() == 'Button' and subchild:GetName() then
                    local name = subchild:GetName()
                    if name:find('DragonUI_CombuctorBag') then
                        RetailBagSlot(subchild)
                        -- Re-apply here because RetailBagSlot checks _BagSkin_Applied
                        -- Clear it so it applies again with our textures
                    end
                end
            end
        end
    end
end

local function CombuctorApply()
    if BagSkinModule.hooks.combuctor then return end

    -- Hook Combuctor's ApplyCombuctorSystem via hooksecurefunc
    if addon.ApplyCombuctorSystem then
        if not BagSkinModule.originalStates.ApplyCombuctorSystem then
            BagSkinModule.originalStates.ApplyCombuctorSystem = addon.ApplyCombuctorSystem
        end

        addon.ApplyCombuctorSystem = function(...)
            local orig = BagSkinModule.originalStates.ApplyCombuctorSystem
            if orig then orig(...) end

            -- Apply to all Combuctor frames
            for i = 1, 2 do
                local frame = _G['DragonUI_CombuctorFrame' .. i]
                if frame then
                    CombuctorSkinFrame(frame)
                    CombuctorSkinItems(frame)
                    CombuctorSkinBagSlots(frame)
                end
            end

            -- Backpack button (Combuctor shows it)
            RetailBackpackButton()
        end
    end

    -- Hook RefreshCombuctorFrames for dynamic items
    if addon.RefreshCombuctorFrames then
        if not BagSkinModule.originalStates.RefreshCombuctorFrames then
            BagSkinModule.originalStates.RefreshCombuctorFrames = addon.RefreshCombuctorFrames
        end

        addon.RefreshCombuctorFrames = function(...)
            local orig = BagSkinModule.originalStates.RefreshCombuctorFrames
            if orig then orig(...) end

            for i = 1, 2 do
                local frame = _G['DragonUI_CombuctorFrame' .. i]
                if frame then
                    CombuctorSkinItems(frame)
                    CombuctorSkinBagSlots(frame)
                end
            end
        end
    end

    -- Apply to default character bag slots on the action bar
    for i = 0, 3 do
        local slot = _G['CharacterBag' .. i .. 'Slot']
        if slot then
            RetailBagSlot(slot)
        end
    end

    -- Apply immediately if combuctor is already initialized
    for i = 1, 2 do
        local frame = _G['DragonUI_CombuctorFrame' .. i]
        if frame then
            
            CombuctorSkinFrame(frame)
            CombuctorSkinItems(frame)
            CombuctorSkinBagSlots(frame)
        end
    end

    RetailBackpackButton()

    BagSkinModule.hooks.combuctor = true
end

local function CombuctorRestore()
    if not BagSkinModule.hooks.combuctor then return end

    -- Restore ApplyCombuctorSystem
    if BagSkinModule.originalStates.ApplyCombuctorSystem then
        addon.ApplyCombuctorSystem = BagSkinModule.originalStates.ApplyCombuctorSystem
        BagSkinModule.originalStates.ApplyCombuctorSystem = nil
    end

    -- Restore RefreshCombuctorFrames
    if BagSkinModule.originalStates.RefreshCombuctorFrames then
        addon.RefreshCombuctorFrames = BagSkinModule.originalStates.RefreshCombuctorFrames
        BagSkinModule.originalStates.RefreshCombuctorFrames = nil
    end

    BagSkinModule.hooks.combuctor = nil
end

-- ============================================================================
-- APPLY / RESTORE
-- ============================================================================

local function ApplyBagSkin()
    if BagSkinModule.applied then return end

    local isCombuctor = addon.IsModuleEnabled and addon:IsModuleEnabled('combuctor')

    if isCombuctor then
        CombuctorApply()
    else
        BlizzardApply()
    end

    BagSkinModule.applied = true
end

local function RestoreBagSkin()
    if not BagSkinModule.applied then return end

    CombuctorRestore()
    BlizzardRestore()

    BagSkinModule.applied = false
end

-- ============================================================================
-- PROFILE CHANGE HANDLER
-- ============================================================================

local function OnProfileChanged()
    if addon.IsModuleEnabled and addon:IsModuleEnabled('bags_skin') then
        if not BagSkinModule.applied then
            ApplyBagSkin()
        end
    else
        if addon.ShouldDeferModuleDisable and addon:ShouldDeferModuleDisable('bags_skin', BagSkinModule) then
            return
        end
        RestoreBagSkin()
    end
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

local initFrame = CreateFrame('Frame')
initFrame:RegisterEvent('ADDON_LOADED')
initFrame:RegisterEvent('PLAYER_ENTERING_WORLD')

initFrame:SetScript('OnEvent', function(self, event, arg1)
    if event == 'ADDON_LOADED' and arg1 == 'DragonUI' then
        if not addon.IsModuleEnabled or not addon:IsModuleEnabled('bags_skin') then return end

        -- Register profile callbacks after AceDB is ready
        addon:After(0.5, function()
            if addon.db and addon.db.RegisterCallback then
                addon.db.RegisterCallback(addon, 'OnProfileChanged', OnProfileChanged)
                addon.db.RegisterCallback(addon, 'OnProfileCopied', OnProfileChanged)
                addon.db.RegisterCallback(addon, 'OnProfileReset', OnProfileChanged)
            end
        end)

    elseif event == 'PLAYER_ENTERING_WORLD' then
        if not addon.IsModuleEnabled or not addon:IsModuleEnabled('bags_skin') then return end
        ApplyBagSkin()
    end
end)

-- ============================================================================
-- EXPORTS
-- ============================================================================

addon.ApplyBagSkin = ApplyBagSkin
addon.RestoreBagSkin = RestoreBagSkin
