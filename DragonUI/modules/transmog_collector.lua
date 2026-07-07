-- =============================================================================
-- Transmog Collector Module
-- Automatically collects transmog appearances when looting new items.
-- Uses C_AppearanceCollection.CollectItemAppearance(guid) (Ascension API).
-- =============================================================================

local addon = select(2, ...)
local L = addon.L

local TransmogCollector = {
    applied = false,
}

if addon.RegisterModule then
    addon:RegisterModule("transmog_collector", TransmogCollector,
        "Transmog Collector",
        "Automatically collect new transmog appearances when looting items.",
        {
            lifecycle = {
                apply   = "ApplyTransmogCollectorSystem",
                restore = "RestoreTransmogCollectorSystem",
                refresh = "RefreshTransmogCollectorSystem",
            },
        })
end

-- =============================================================================
-- MODULE STATE
-- =============================================================================

local function IsModuleEnabled()
    return addon:IsModuleEnabled("transmog_collector")
end

-- =============================================================================
-- INTERNAL STATE
-- =============================================================================

local eventFrame          -- BAG_UPDATE listener
local scanQueue     = {} -- {bag, slot} entries pending scan
local isScanning    = false
local knownCache    = nil  -- { [guid] = true } for current session (memory only)

-- =============================================================================
-- BAG SCANNER
-- =============================================================================

--- Check if an item can be transmog-collected (matches Ascension macro filter).
--- Class IDs < 5 cover Weapon, Armor, Container, and Consumable (macro uses < 5).
--- If item info isn't cached yet, still try collection.
local function IsCollectableItem(itemID)
    if not itemID then return false end
    local _, _, classID = GetItemInfo(itemID)
    if not classID then return true end  -- not cached, try anyway
    return classID < 5
end

--- Check if the Ascension collection API is available.
local function IsCollectionAvailable()
    return C_AppearanceCollection
        and type(C_AppearanceCollection.CollectItemAppearance) == "function"
end

local function ScanQueueProcessor()
    if not TransmogCollector.applied then return end
    if #scanQueue == 0 then
        isScanning = false
        return
    end

    isScanning = true
    local entry = tremove(scanQueue, 1)
    local bag = entry.bag
    local slot = entry.slot
    local guid = GetContainerItemGUID(bag, slot)

    if not guid or knownCache[guid] then
        -- Already seen or no GUID, skip to next
        addon:After(0, ScanQueueProcessor)
        return
    end
    knownCache[guid] = true

    local itemID = GetContainerItemID(bag, slot)
    if IsCollectableItem(itemID) and IsCollectionAvailable() then
        C_AppearanceCollection.CollectItemAppearance(guid)
    end

    -- Process next item in queue
    addon:After(0.05, ScanQueueProcessor)
end

--- Scan all bag slots for new items and queue them for processing.
local function ScanBags()
    if not TransmogCollector.applied then return end
    if isScanning then return end
    isScanning = true

    for bag = 0, NUM_BAG_SLOTS or 4 do
        local numSlots = GetContainerNumSlots(bag)
        if numSlots then
            for slot = 1, numSlots do
                local itemID = GetContainerItemID(bag, slot)
                if itemID then
                    tinsert(scanQueue, {bag = bag, slot = slot})
                end
            end
        end
    end

    isScanning = false

    if #scanQueue > 0 then
        addon:After(0.1, ScanQueueProcessor)
    end
end

-- =============================================================================
-- EVENT HANDLER
-- =============================================================================

local function OnEvent(self, event, ...)
    if not IsModuleEnabled() then return end
    if event == "BAG_UPDATE" then
        -- Delay slightly to let bag settle after loot
        addon:After(0.3, ScanBags)
    end
end

-- =============================================================================
-- LIFECYCLE
-- =============================================================================

function addon.ApplyTransmogCollectorSystem()
    if TransmogCollector.applied then return end
    TransmogCollector.applied = true

    -- Fresh session cache
    knownCache = {}

    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:SetScript("OnEvent", OnEvent)
    end
    eventFrame:RegisterEvent("BAG_UPDATE")

    -- Initial scan: process all items in bags
    if IsCollectionAvailable() then
        addon:After(0.5, ScanBags)
    end
end

function addon.RestoreTransmogCollectorSystem()
    TransmogCollector.applied = false

    if eventFrame then
        eventFrame:UnregisterEvent("BAG_UPDATE")
    end

    wipe(scanQueue)
    isScanning = false
end

function addon.RefreshTransmogCollectorSystem()
    if TransmogCollector.applied then
        addon.RestoreTransmogCollectorSystem()
        addon.ApplyTransmogCollectorSystem()
    elseif IsModuleEnabled() then
        addon.ApplyTransmogCollectorSystem()
    end
end
