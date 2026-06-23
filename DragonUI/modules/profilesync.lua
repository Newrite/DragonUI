--[[
===============================================================================
DragonUI - Profile Sync via AceComm-3.0
===============================================================================
Handles sending and receiving profiles via addon communication (whisper/party/
raid/guild) with clickable chat links, similar to linking an item.

Uses AceComm-3.0 for automatic chunking/reassembly of large profile strings.
The import StaticPopup dialog is defined here as a fallback so it works even
before the Options addon loads: tab_profiles.lua overwrites it with the
fully-localized version when Options opens.
===============================================================================
]]

local addon = select(2, ...) or DragonUI
if not addon then return end

local LibDeflate = LibStub("LibDeflate")
local Serializer = {}
LibStub("AceSerializer-3.0"):Embed(Serializer)

-- Local references for performance & consistency with other modules
local format = string.format
local strmatch = string.match
local strtrim = string.trim

-- Embed AceComm-3.0 into the core addon for profile sync
LibStub("AceComm-3.0"):Embed(addon.core)

-- Pending profile imports: { [txnId] = profileData (table), ... }
addon._pendingProfileImports = addon._pendingProfileImports or {}

-- Transaction counter for unique IDs
addon._txnCounter = addon._txnCounter or 0

-- ============================================================================
-- TRANSACTION ID GENERATION
-- ============================================================================

function addon.GenerateTxnId()
    addon._txnCounter = (addon._txnCounter + 1) % 65536
    local timePart = math.floor(GetTime() * 100) % 65536
    return format("%04x%04x", addon._txnCounter, timePart)
end

-- ============================================================================
-- SEND: Export current profile and send via AceComm
-- ============================================================================

--- Sends the current profile to one or more players.
-- @param distribution "WHISPER", "PARTY", "RAID", or "GUILD"
-- @param target Player name (only for WHISPER)
-- @param txnId Unique transaction ID (generated if nil)
-- @return true on success, nil on failure
function addon.SendProfile(distribution, target, txnId)
    if not addon.db or not addon.db.profile then return end
    if InCombatLockdown() then
        print("|cFFFF0000[DragonUI]|r " .. "Cannot share profile in combat.")
        return
    end

    -- Export to string (same pipeline as ExportProfileToString)
    local serialized = Serializer:Serialize(addon.db.profile)
    if not serialized then return end
    local compressed = LibDeflate:CompressDeflate(serialized)
    if not compressed then return end
    local encoded = LibDeflate:EncodeForPrint(compressed)
    if not encoded then return end

    txnId = txnId or addon.GenerateTxnId()

    -- Format: txnId|encodedPayload
    local msg = txnId .. "|" .. encoded

    addon.core:SendCommMessage("DragonUI-Profile", msg, distribution, target or nil)
    return true, txnId
end

-- ============================================================================
-- RECEIVE: Incoming profile data via AceComm
-- ============================================================================

addon.core:RegisterComm("DragonUI-Profile", function(prefix, data, distribution, sender)
    if not data or data == "" then return end

    -- Parse: txnId|encodedPayload
    local txnId, encoded = strmatch(data, "^([^|]+)|(.+)$")
    if not txnId or not encoded then return end

    -- Decode
    local decoded = LibDeflate:DecodeForPrint(encoded)
    if not decoded then return end
    local decompressed = LibDeflate:DecompressDeflate(decoded)
    if not decompressed then return end
    local ok, profileData = Serializer:Deserialize(decompressed)
    if not ok or type(profileData) ~= "table" then return end

    -- Store
    addon._pendingProfileImports[txnId] = profileData

    -- Notify the options addon if loaded (so a UI prompt can appear)
    if addon._optionsProfileReceived then
        addon._optionsProfileReceived(txnId, sender, profileData)
    end

    -- Print a clickable link in the receiver's chat
    local link = format("|Hdragonui_profile:%s|h|cff1784d1[DragonUI Profile]|h|r", txnId)
    print(format("|cff1784d1[DragonUI]|r Profile received from %s. %s", sender, link))
    print("|cff888888Click the link above to import the profile.|r")
end)

-- ============================================================================
-- CHAT LINK: Hook SetItemRef to handle clickable profile links
-- ============================================================================

do
    local origSetItemRef = SetItemRef
    SetItemRef = function(link, text, button, chatFrame)
        if link then
            local prefix = strmatch(link, "^([^:]+)")
            if prefix == "dragonui_profile" then
                local txnId = strmatch(link, "^[^:]+:(.+)$")
                if txnId then
                    local data = addon._pendingProfileImports[txnId]
                    if data and type(data) == "table" then
                        -- Show the import name dialog (custom frame if Options
                        -- is loaded, StaticPopup fallback otherwise)
                        if addon._showProfileImportFrame then
                            addon._showProfileImportFrame(data)
                        else
                            local dialog = StaticPopup_Show("DRAGONUI_PROFILE_IMPORT_NAME")
                            if dialog then
                                dialog.data = data
                            end
                        end
                    else
                        print("|cff1784d1[DragonUI]|r Profile data not found. Ask the sender to share again.")
                    end
                end
                return
            end
        end
        if origSetItemRef then
            return origSetItemRef(link, text, button, chatFrame)
        end
    end
end

-- ============================================================================
-- IMPORT STATIC POPUP (fallback — tab_profiles.lua overrides with locale)
-- ============================================================================

if not StaticPopupDialogs["DRAGONUI_PROFILE_IMPORT_NAME"] then
    StaticPopupDialogs["DRAGONUI_PROFILE_IMPORT_NAME"] = {
        text = "Enter a name for the imported profile:",
        button1 = ACCEPT,
        button2 = CANCEL,
        hasEditBox = true,
        maxLetters = 40,
        OnShow = function(self)
            local eb = self.editBox or _G[self:GetName() .. "EditBox"]
            if eb then
                eb:SetHeight(32) -- ajustá este valor
                eb:SetText("Enter profile name")
                eb:HighlightText()
                eb:SetFocus()
            end
        end,
        OnAccept = function(self)
            local eb = self.editBox or _G[self:GetName() .. "EditBox"]
            local name = eb and eb:GetText() and strtrim(eb:GetText())
            if not name or name == "" then return end
            name = name:gsub("|", "")
            if name == "" then return end
            local data = self.data
            if not data or type(data) ~= "table" then return end

            local db = addon.db
            if not db then return end

            db:SetProfile(name)
            db:ResetProfile()

            for k, v in pairs(data) do
                if type(v) == "table" then
                    db.profile[k] = addon.DeepCopy(v)
                else
                    db.profile[k] = v
                end
            end

            print("|cFF00FF00[DragonUI]|r Profile imported: " .. name)
            ReloadUI()
        end,
        EditBoxOnEnterPressed = function(self)
            local parent = self:GetParent()
            StaticPopupDialogs["DRAGONUI_PROFILE_IMPORT_NAME"].OnAccept(parent)
            parent:Hide()
        end,
        EditBoxOnEscapePressed = function(self)
            self:GetParent():Hide()
        end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        preferredIndex = 3,
    }
end
