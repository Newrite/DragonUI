--[[
===============================================================================
DragonUI Options Panel - Profiles Tab
===============================================================================
Profile management using AceDB-3.0 API directly.
Provides: select profile, copy, delete, reset, export, import.
===============================================================================
]]

local addon = DragonUI
if not addon then return end

local L = addon.L
local LO = addon.LO
local AceGUI = LibStub("AceGUI-3.0")
local C = addon.PanelControls
local Panel = addon.OptionsPanel

-- ============================================================================
-- SERIALIZATION (same pattern as preset export in tab_general.lua)
-- Uses AceSerializer-3.0 + LibDeflate for compressed, text-safe strings.
-- ============================================================================

local Serializer = {}
LibStub("AceSerializer-3.0"):Embed(Serializer)
local LibDeflate = LibStub("LibDeflate")
local EXPORT_HEADER = "!DUIP1!" -- DragonUI Profile v1

local function ExportProfileToString(profileData)
    local serialized = Serializer:Serialize(profileData)
    if not serialized then return nil end
    local compressed = LibDeflate:CompressDeflate(serialized)
    if not compressed then return nil end
    local encoded = LibDeflate:EncodeForPrint(compressed)
    if not encoded then return nil end
    return EXPORT_HEADER .. encoded
end

local function ImportProfileFromString(str)
    if type(str) ~= "string" then return nil, "empty" end
    str = strtrim(str)
    if str == "" then return nil, "empty" end
    if str:sub(1, #EXPORT_HEADER) ~= EXPORT_HEADER then return nil, "header" end
    local payload = str:sub(#EXPORT_HEADER + 1)
    if payload == "" then return nil, "payload" end
    local decoded = LibDeflate:DecodeForPrint(payload)
    if not decoded then return nil, "decode" end
    local decompressed = LibDeflate:DecompressDeflate(decoded)
    if not decompressed then return nil, "decompress" end
    local ok, data = Serializer:Deserialize(decompressed)
    if not ok or type(data) ~= "table" then return nil, "deserialize" end
    return data
end

-- ============================================================================
-- IMPORT / EXPORT POPUP FRAME (panel-themed dark style)
-- ============================================================================

-- Backdrop definition matching the main panel (panel.lua)
local BD_IE = {
    bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
    tile = false, edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
}

local function SetSafeFont(fs, size, flags)
    if not fs then return end
    local tryFonts = {
        C.Theme.font,
        addon.Fonts and addon.Fonts.PRIMARY,
        STANDARD_TEXT_FONT,
        "Fonts\\FRIZQT__.TTF",
    }
    for _, path in ipairs(tryFonts) do
        if path and fs:SetFont(path, size or 12, flags or "") then
            return
        end
    end
end

local profileIEFrame

local function GetProfileIEFrame()
    if profileIEFrame then return profileIEFrame end

    local f = CreateFrame("Frame", "DragonUI_ProfileIEFrame", UIParent)
    f:SetSize(520, 360)
    f:SetPoint("CENTER")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop(BD_IE)
    f:SetBackdropColor(0.06, 0.06, 0.08, 0.96)
    f:SetBackdropBorderColor(0.20, 0.20, 0.22, 1)
    f:Hide()
    tinsert(UISpecialFrames, "DragonUI_ProfileIEFrame")

    -- Title bar
    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetPoint("TOPLEFT", 1, -1)
    titleBar:SetPoint("TOPRIGHT", -1, -1)
    titleBar:SetHeight(32)
    titleBar:SetBackdrop(BD_IE)
    titleBar:SetBackdropColor(0.08, 0.08, 0.10, 1)
    titleBar:SetBackdropBorderColor(0, 0, 0, 0)

    local titleText = titleBar:CreateFontString(nil, "OVERLAY")
    SetSafeFont(titleText, 15, "OUTLINE")
    titleText:SetPoint("LEFT", 12, 0)
    titleText:SetTextColor(1, 1, 1, 1)
    f.title = titleText

    -- Accent line under title bar
    local accent = f:CreateTexture(nil, "OVERLAY")
    accent:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    accent:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, 0)
    accent:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
    accent:SetHeight(2)
    accent:SetVertexColor(0.09, 0.52, 0.82, 1)

    -- Close button (top-right X) — same style as panel
    local close = CreateFrame("Button", nil, titleBar)
    close:SetSize(20, 20)
    close:SetPoint("RIGHT", -8, 0)
    local closeText = close:CreateFontString(nil, "OVERLAY")
    SetSafeFont(closeText, 16, "OUTLINE")
    closeText:SetPoint("CENTER", 0, 0)
    closeText:SetText("|cffccccccx|r")
    close:SetScript("OnClick", function() f:Hide() end)
    close:SetScript("OnEnter", function() closeText:SetText("|cffff4444x|r") end)
    close:SetScript("OnLeave", function() closeText:SetText("|cffccccccx|r") end)

    -- Content backdrop (dark area behind the edit box)
    local contentBg = CreateFrame("Frame", nil, f)
    contentBg:SetPoint("TOPLEFT", 6, -38)
    contentBg:SetPoint("BOTTOMRIGHT", -6, 48)
    contentBg:SetBackdrop(BD_IE)
    contentBg:SetBackdropColor(0.09, 0.09, 0.11, 1)
    contentBg:SetBackdropBorderColor(0, 0, 0, 0)

    -- ScrollFrame + Multi-line EditBox
    local sf = CreateFrame("ScrollFrame", "DragonUI_ProfileIEScroll", f, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 10, -42)
    sf:SetPoint("BOTTOMRIGHT", -28, 52)

    local eb = CreateFrame("EditBox", "DragonUI_ProfileIEEditBox", sf)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    SetSafeFont(eb, 12, "")
    eb:SetTextColor(0.85, 0.85, 0.85, 1)
    eb:SetWidth(440)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); f:Hide() end)
    sf:SetScrollChild(eb)
    f.editBox = eb
    f.scrollFrame = sf

    -- Left action button (Select All / Import) — styled like panel's SkinButton
    local btn1 = CreateFrame("Button", nil, f)
    btn1:SetSize(120, 24)
    btn1:SetPoint("BOTTOMLEFT", 20, 16)
    btn1:SetBackdrop(BD_IE)
    btn1:SetBackdropColor(0.16, 0.16, 0.18, 1)
    btn1:SetBackdropBorderColor(0.25, 0.25, 0.28, 1)
    local btn1hl = btn1:CreateTexture(nil, "HIGHLIGHT")
    btn1hl:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    btn1hl:SetVertexColor(0.09, 0.52, 0.82, 0.25)
    btn1hl:SetAllPoints()
    local btn1text = btn1:CreateFontString(nil, "OVERLAY")
    SetSafeFont(btn1text, 12, "")
    btn1text:SetPoint("CENTER")
    btn1text:SetTextColor(1, 1, 1, 1)
    f.btn1 = btn1
    f.btn1Text = btn1text

    -- Right action button (Close / Cancel)
    local btn2 = CreateFrame("Button", nil, f)
    btn2:SetSize(120, 24)
    btn2:SetPoint("BOTTOMRIGHT", -20, 16)
    btn2:SetBackdrop(BD_IE)
    btn2:SetBackdropColor(0.16, 0.16, 0.18, 1)
    btn2:SetBackdropBorderColor(0.25, 0.25, 0.28, 1)
    local btn2hl = btn2:CreateTexture(nil, "HIGHLIGHT")
    btn2hl:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    btn2hl:SetVertexColor(0.09, 0.52, 0.82, 0.25)
    btn2hl:SetAllPoints()
    local btn2text = btn2:CreateFontString(nil, "OVERLAY")
    SetSafeFont(btn2text, 12, "")
    btn2text:SetPoint("CENTER")
    btn2text:SetTextColor(1, 1, 1, 1)
    f.btn2 = btn2
    f.btn2Text = btn2text

    profileIEFrame = f
    return f
end

local function ShowProfileExportFrame(exportString)
    local f = GetProfileIEFrame()
    f.title:SetText(LO["Export Profile"] or "Export Profile")
    f.editBox:SetText(exportString)
    f.editBox:SetScript("OnTextChanged", function(self)
        self:SetText(exportString) -- prevent editing
    end)
    f.editBox:SetCursorPosition(0)
    f.btn1Text:SetText(LO["Select All"] or "Select All")
    f.btn1:SetScript("OnClick", function()
        f.editBox:SetFocus()
        f.editBox:HighlightText()
    end)
    f.btn2Text:SetText(LO["Close"] or "Close")
    f.btn2:SetScript("OnClick", function() f:Hide() end)
    f:Show()
    f.editBox:SetFocus()
    f.editBox:HighlightText()
end

local function ShowProfileImportFrame()
    local f = GetProfileIEFrame()
    f.title:SetText(LO["Import Profile"] or "Import Profile")
    f.editBox:SetText("")
    f.editBox:SetScript("OnTextChanged", nil) -- allow editing
    f.btn1Text:SetText(LO["Import"] or "Import")
    f.btn1:SetScript("OnClick", function()
        local text = strtrim(f.editBox:GetText())
        if text == "" then return end
        local data, errType = ImportProfileFromString(text)
        if not data then
            local msg = LO["Invalid profile string."] or "Invalid profile string."
            if errType == "header" then
                msg = LO["Not a valid DragonUI profile string."] or "Not a valid DragonUI profile string."
            end
            print("|cFFFF4444[DragonUI]|r " .. msg)
            return
        end
        f:Hide()
        -- Ask for a profile name
        ShowProfileImportNameFrame(data)
    end)
    f.btn2Text:SetText(LO["Cancel"] or "Cancel")
    f.btn2:SetScript("OnClick", function() f:Hide() end)
    f:Show()
    f.editBox:SetFocus()
end

-- ============================================================================
-- CUSTOM FRAME: Import profile name (dark theme, same as GetProfileIEFrame)
-- ============================================================================

local profileImportNameFrame

local function DoImportProfile(data, name)
    if not data or type(data) ~= "table" then return end
    if not name or name == "" then return end
    name = name:gsub("|", "")
    if name == "" then return end

    local db = addon.db
    if not db then return end

    db:SetProfile(name)
    db:ResetProfile()

    for key, value in pairs(data) do
        if type(value) == "table" then
            db.profile[key] = addon.DeepCopy(value)
        else
            db.profile[key] = value
        end
    end

    print("|cFF00FF00[DragonUI]|r " .. (LO["Profile imported: "] or "Profile imported: ") .. name)
    ReloadUI()
end

local function GetProfileImportNameFrame()
    if profileImportNameFrame then return profileImportNameFrame end

    local f = CreateFrame("Frame", "DragonUI_ProfileImportNameFrame", UIParent)
    f:SetSize(400, 210)
    f:SetPoint("CENTER")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop(BD_IE)
    f:SetBackdropColor(0.06, 0.06, 0.08, 0.96)
    f:SetBackdropBorderColor(0.20, 0.20, 0.22, 1)
    f:Hide()
    tinsert(UISpecialFrames, "DragonUI_ProfileImportNameFrame")

    -- Title bar
    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetPoint("TOPLEFT", 1, -1)
    titleBar:SetPoint("TOPRIGHT", -1, -1)
    titleBar:SetHeight(32)
    titleBar:SetBackdrop(BD_IE)
    titleBar:SetBackdropColor(0.08, 0.08, 0.10, 1)
    titleBar:SetBackdropBorderColor(0, 0, 0, 0)

    local titleText = titleBar:CreateFontString(nil, "OVERLAY")
    SetSafeFont(titleText, 15, "OUTLINE")
    titleText:SetPoint("LEFT", 12, 0)
    titleText:SetTextColor(1, 1, 1, 1)
    f.titleText = titleText

    -- Accent line under title bar
    local accent = f:CreateTexture(nil, "OVERLAY")
    accent:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    accent:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, 0)
    accent:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)
    accent:SetHeight(2)
    accent:SetVertexColor(0.09, 0.52, 0.82, 1)

    -- Close button
    local close = CreateFrame("Button", nil, titleBar)
    close:SetSize(20, 20)
    close:SetPoint("RIGHT", -8, 0)
    local closeText = close:CreateFontString(nil, "OVERLAY")
    SetSafeFont(closeText, 16, "OUTLINE")
    closeText:SetPoint("CENTER")
    closeText:SetText("|cffccccccx|r")
    close:SetScript("OnClick", function() f:Hide() end)
    close:SetScript("OnEnter", function() closeText:SetText("|cffff4444x|r") end)
    close:SetScript("OnLeave", function() closeText:SetText("|cffccccccx|r") end)

    -- Content backdrop
    local contentBg = CreateFrame("Frame", nil, f)
    contentBg:SetPoint("TOPLEFT", 6, -38)
    contentBg:SetPoint("BOTTOMRIGHT", -6, 48)
    contentBg:SetBackdrop(BD_IE)
    contentBg:SetBackdropColor(0.09, 0.09, 0.11, 1)
    contentBg:SetBackdropBorderColor(0, 0, 0, 0)

    -- Description text
    local desc = f:CreateFontString(nil, "OVERLAY")
    SetSafeFont(desc, 12, "")
    desc:SetPoint("TOPLEFT", 16, -48)
    desc:SetTextColor(0.85, 0.85, 0.85, 1)
    f.desc = desc

    -- EditBox for profile name
    local eb = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    eb:SetSize(340, 28)
    eb:SetPoint("TOP", f, "TOP", 0, -80)
    eb:SetAutoFocus(false)
    SetSafeFont(eb, 13, "")
    eb:SetTextColor(0.85, 0.85, 0.85, 1)
    eb:SetMaxLetters(40)
    f.editBox = eb

    -- Save button
    local btn1 = CreateFrame("Button", nil, f)
    btn1:SetSize(120, 24)
    btn1:SetPoint("BOTTOMLEFT", 40, 16)
    btn1:SetBackdrop(BD_IE)
    btn1:SetBackdropColor(0.16, 0.16, 0.18, 1)
    btn1:SetBackdropBorderColor(0.25, 0.25, 0.28, 1)
    local btn1hl = btn1:CreateTexture(nil, "HIGHLIGHT")
    btn1hl:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    btn1hl:SetVertexColor(0.09, 0.52, 0.82, 0.25)
    btn1hl:SetAllPoints()
    local btn1text = btn1:CreateFontString(nil, "OVERLAY")
    SetSafeFont(btn1text, 12, "")
    btn1text:SetPoint("CENTER")
    btn1text:SetTextColor(1, 1, 1, 1)
    f.btn1 = btn1
    f.btn1Text = btn1text

    -- Cancel button
    local btn2 = CreateFrame("Button", nil, f)
    btn2:SetSize(120, 24)
    btn2:SetPoint("BOTTOMRIGHT", -40, 16)
    btn2:SetBackdrop(BD_IE)
    btn2:SetBackdropColor(0.16, 0.16, 0.18, 1)
    btn2:SetBackdropBorderColor(0.25, 0.25, 0.28, 1)
    local btn2hl = btn2:CreateTexture(nil, "HIGHLIGHT")
    btn2hl:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    btn2hl:SetVertexColor(0.09, 0.52, 0.82, 0.25)
    btn2hl:SetAllPoints()
    local btn2text = btn2:CreateFontString(nil, "OVERLAY")
    SetSafeFont(btn2text, 12, "")
    btn2text:SetPoint("CENTER")
    btn2text:SetTextColor(1, 1, 1, 1)
    f.btn2 = btn2
    f.btn2Text = btn2text

    profileImportNameFrame = f
    return f
end

local function ShowProfileImportNameFrame(importedData)
    local f = GetProfileImportNameFrame()
    f.data = importedData
    f.titleText:SetText(LO["Import Profile"] or "Import Profile")
    f.desc:SetText(LO["Enter a name for the imported profile:"] or "Enter a name for the imported profile:")
    f.btn1Text:SetText(LO["Save"] or "Save")
    f.btn2Text:SetText(LO["Cancel"] or "Cancel")

    f.editBox:SetText(LO["Enter profile name"] or "Enter profile name")
    f.editBox:HighlightText()
    f.editBox:SetFocus()

    f.btn1:SetScript("OnClick", function()
        local name = strtrim(f.editBox:GetText() or "")
        if name == "" then return end
        DoImportProfile(f.data, name)
    end)
    f.btn2:SetScript("OnClick", function()
        f:Hide()
    end)
    f.editBox:SetScript("OnEnterPressed", function()
        local name = strtrim(f.editBox:GetText() or "")
        if name == "" then return end
        DoImportProfile(f.data, name)
    end)
    f.editBox:SetScript("OnEscapePressed", function()
        f:Hide()
    end)

    f:Show()
    f.editBox:SetFocus()
end

-- Expose for profilesync.lua (core module) to use when Options is loaded
DragonUI._showProfileImportFrame = ShowProfileImportNameFrame

-- ============================================================================
-- PROFILES TAB BUILDER
-- ============================================================================

local function BuildProfilesTab(scroll)
    local db = addon.db
    if not db then
        C:AddLabel(scroll, "|cFFFF0000" .. LO["Database not available."] .. "|r")
        return
    end

    C:AddLabel(scroll, "|cffFFD700" .. LO["Profiles"] .. "|r", { color = C.Theme.textGold })
    C:AddDescription(scroll, LO["Save and switch between different configurations per character."])
    C:AddSpacer(scroll)

    -- ====================================================================
    -- CURRENT PROFILE
    -- ====================================================================
    local current = C:AddSection(scroll, LO["Current Profile"])

    local currentProfile = db:GetCurrentProfile()
    C:AddLabel(current, LO["Active: "] .. "|cff1784d1" .. currentProfile .. "|r")

    -- ====================================================================
    -- SELECT / CREATE PROFILE
    -- ====================================================================
    local selectSection = C:AddSection(scroll, LO["Switch or Create Profile"])

    -- Build profile list for dropdown
    local function GetProfileList()
        local profiles = {}
        for _, name in ipairs(db:GetProfiles()) do
            profiles[name] = name
        end
        return profiles
    end

    C:AddDropdown(selectSection, {
        label = LO["Select Profile"],
        getFunc = function() return db:GetCurrentProfile() end,
        setFunc = function(val)
            db:SetProfile(val)
            Panel:SelectTab("profiles")
            StaticPopup_Show("DRAGONUI_RELOAD_UI")
        end,
        values = GetProfileList(),
    })

    -- New profile input
    local newName = AceGUI:Create("EditBox")
    newName:SetLabel(LO["New Profile Name"])
    newName:SetWidth(250)
    newName:SetCallback("OnEnterPressed", function(widget, event, text)
        if text and text ~= "" then
            db:SetProfile(text)
            widget:SetText("")
            Panel:SelectTab("profiles")
            StaticPopup_Show("DRAGONUI_RELOAD_UI")
        end
    end)
    selectSection:AddChild(newName)

    -- ====================================================================
    -- COPY FROM
    -- ====================================================================
    local copySection = C:AddSection(scroll, LO["Copy From"])

    C:AddDescription(copySection, LO["Copies all settings from the selected profile into your current one."])

    C:AddDropdown(copySection, {
        label = LO["Copy From"],
        getFunc = function() return nil end,
        setFunc = function(val)
            if val then
                db:CopyProfile(val)
                print("|cFF00FF00[DragonUI]|r " .. LO["Copied profile: "] .. val)
                Panel:SelectTab("profiles")
                StaticPopup_Show("DRAGONUI_RELOAD_UI")
            end
        end,
        values = GetProfileList(),
    })

    -- ====================================================================
    -- DELETE
    -- ====================================================================
    local deleteSection = C:AddSection(scroll, LO["Delete Profile"])

    C:AddDescription(deleteSection, "|cffFF6600" .. LO["Warning:"] .. "|r " .. LO["Warning: Deleting a profile is permanent and cannot be undone."])

    -- Build list excluding current
    local function GetDeletableProfiles()
        local profiles = {}
        local current = db:GetCurrentProfile()
        for _, name in ipairs(db:GetProfiles()) do
            if name ~= current then
                profiles[name] = name
            end
        end
        return profiles
    end

    C:AddDropdown(deleteSection, {
        label = LO["Delete"],
        getFunc = function() return nil end,
        setFunc = function(val)
            if val then
                local dialog = StaticPopup_Show("DRAGONUI_DELETE_PROFILE", val)
                if dialog then
                    dialog.data = val
                end
            end
        end,
        values = GetDeletableProfiles(),
    })

    -- ====================================================================
    -- PROFILE MANAGER — Reset / Export / Import / Share
    -- ====================================================================
    local manager = C:AddSection(scroll, LO["Profile Manager"])

    C:AddDescription(manager, LO["Manage your current profile: reset to defaults, export/import as text, or share in-game."])

    local btnRow1 = C:AddRow(manager)

    C:AddButton(btnRow1, {
        label = LO["Reset Profile"],
        width = 160,
        desc = LO["Restores the current profile to defaults."],
        callback = function()
            StaticPopupDialogs["DRAGONUI_RESET_PROFILE"] = StaticPopupDialogs["DRAGONUI_RESET_PROFILE"] or {
                text = LO["All changes will be lost and the UI will be reloaded.\nAre you sure you want to reset your profile?"],
                button1 = LO["Yes"],
                button2 = LO["No"],
                OnAccept = function()
                    if not addon.db then return end
                    addon.db:ResetProfile()
                    print("|cFF00FF00[DragonUI]|r " .. LO["Profile reset to defaults."])
                    ReloadUI()
                end,
                timeout = 0,
                whileDead = true,
                hideOnEscape = true,
                preferredIndex = 3,
            }
            StaticPopup_Show("DRAGONUI_RESET_PROFILE")
        end,
    })

    local exportBtn
    exportBtn = C:AddButton(btnRow1, {
        label = LO["Export Profile"],
        width = 160,
        desc = LO["Export your current profile as a text string."],
        callback = function()
            local db = addon.db
            if not db or not db.profile then return end

            -- Disable button and show feedback before heavy work
            exportBtn:SetDisabled(true)
            exportBtn:SetText(LO["Exporting..."] or "Exporting...")

            -- Defer to next frame so the UI refreshes before serialization
            C_Timer.After(0.1, function()
                local exportStr = ExportProfileToString(db.profile)
                if exportStr then
                    ShowProfileExportFrame(exportStr)
                else
                    print("|cFFFF4444[DragonUI]|r " .. (LO["Failed to export profile."] or "Failed to export profile."))
                end
                exportBtn:SetDisabled(false)
                exportBtn:SetText(LO["Export Profile"])
            end)
        end,
    })

    C:AddButton(btnRow1, {
        label = LO["Import Profile"],
        width = 160,
        desc = LO["Import a profile from a text string shared by another user."],
        callback = function()
            ShowProfileImportFrame()
        end,
    })

    C:AddSpacer(manager)

    -- Share inline controls
    local shareChannel = "Party"
    local shareRow = C:AddRow(manager)

    C:AddDropdown(shareRow, {
        label = LO["Share to:"] or "Share to:",
        getFunc = function() return shareChannel end,
        setFunc = function(val) shareChannel = val end,
        values = {
            [LO["Whisper"] or "Whisper"] = "Whisper",
            [LO["Party"] or "Party"]     = "Party",
            [LO["Raid"] or "Raid"]       = "Raid",
            [LO["Guild"] or "Guild"]     = "Guild",
        },
        width = 140,
    })

    local shareBtn
    shareBtn = C:AddButton(shareRow, {
        label = LO["Share"] or "Share",
        width = 100,
        callback = function()
            local db = addon.db
            if not db or not db.profile then return end

            -- Disable and show feedback
            shareBtn:SetDisabled(true)
            shareBtn:SetText(LO["Sending..."] or "Sending...")

            C_Timer.After(0.1, function()
                if shareChannel == "Whisper" then
                    -- Use a simple popup to ask for the target
                    StaticPopupDialogs["DRAGONUI_WHISPER_TARGET"] = StaticPopupDialogs["DRAGONUI_WHISPER_TARGET"] or {
                        text = LO["Enter a target player name for whisper."] or "Enter a target player name for whisper.",
                        button1 = LO["Share"] or "Share",
                        button2 = LO["Cancel"] or "Cancel",
                        hasEditBox = true,
                        maxLetters = 32,
                        OnAccept = function(self)
                            local eb = self.editBox or _G[self:GetName() .. "EditBox"]
                            local target = eb and strtrim(eb:GetText() or "")
                            if target and target ~= "" then
                                DragonUI.SendProfile("WHISPER", target)
                            end
                        end,
                        timeout = 0,
                        whileDead = 1,
                        hideOnEscape = 1,
                        preferredIndex = 3,
                    }
                    StaticPopup_Show("DRAGONUI_WHISPER_TARGET")
                    -- Re-enable immediately since the popup handles interaction
                    shareBtn:SetDisabled(false)
                    shareBtn:SetText(LO["Share"] or "Share")
                else
                    local distMap = { Party = "PARTY", Raid = "RAID", Guild = "GUILD" }
                    DragonUI.SendProfile(distMap[shareChannel])
                    -- Keep the button showing "Sending..." so the user sees
                    -- the profile actually arrive in chat before re-enabling
                    C_Timer.After(4.0, function()
                        shareBtn:SetDisabled(false)
                        shareBtn:SetText(LO["Share"] or "Share")
                    end)
                end
            end)
        end,
    })
end

-- Register the tab
Panel:RegisterTab("profiles", LO["Profiles"], BuildProfilesTab, 99)
