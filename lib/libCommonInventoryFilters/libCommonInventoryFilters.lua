local myNAME, myVERSION = "libCommonInventoryFilters", 1.10
local libCIF = LibStub:NewLibrary(myNAME, myVERSION)
if not libCIF then return end

local function enableGuildStoreSellFilters()
    local tradingHouseLayout = BACKPACK_TRADING_HOUSE_LAYOUT_FRAGMENT.layoutData

    if not tradingHouseLayout.hiddenFilters then
        tradingHouseLayout.hiddenFilters = {}
    end
    tradingHouseLayout.hiddenFilters[ITEMFILTERTYPE_QUEST] = true
    tradingHouseLayout.inventoryTopOffsetY = 45
    tradingHouseLayout.sortByOffsetY = 63
    tradingHouseLayout.backpackOffsetY = 96

    local originalFilter = tradingHouseLayout.additionalFilter
    if originalFilter then
        function tradingHouseLayout.additionalFilter(slot)
            return originalFilter(slot) and not IsItemBound(slot.bagId, slot.slotIndex)
        end
    else
        function tradingHouseLayout.additionalFilter(slot)
            return not IsItemBound(slot.bagId, slot.slotIndex)
        end
    end

    local tradingHouseHiddenColumns = { statValue = true, age = true }
    local zorgGetTabFilterInfo = PLAYER_INVENTORY.GetTabFilterInfo

    function PLAYER_INVENTORY:GetTabFilterInfo(inventoryType, tabControl)
        if libCIF._tradingHouseModeEnabled then
            local filterType, activeTabText = zorgGetTabFilterInfo(self, inventoryType, tabControl)
            return filterType, activeTabText, tradingHouseHiddenColumns
        else
            return zorgGetTabFilterInfo(self, inventoryType, tabControl)
        end
    end
end

--if the mouse is enabled, cycle its state to refresh the integrity of the control beneath it
local function SafeUpdateList(object, ...)
    local isMouseVisible = SCENE_MANAGER:IsInUIMode()
    if isMouseVisible then HideMouse() end
    object:UpdateList(...)
    if isMouseVisible then ShowMouse() end
end

local function fixSearchBoxBugs()
    -- http://www.esoui.com/forums/showthread.php?t=4551
    -- search box bug #1: stale searchData after swapping equipment
    SHARED_INVENTORY:RegisterCallback("SlotUpdated",
        function(bagId, slotIndex, slotData)
            if slotData and slotData.searchData then
                slotData.searchData.cached = false
                slotData.searchData.cache = nil
            end
        end)

    -- guild bank search box bug #2: wrong inventory updated
    ZO_GuildBankSearchBox:SetHandler("OnTextChanged",
        function(editBox)
            ZO_EditDefaultText_OnTextChanged(editBox)
            SafeUpdateList(PLAYER_INVENTORY, INVENTORY_GUILD_BANK)
        end)

    -- guild bank search box bug #3: wrong search box cleared
    local guildBankScene = SCENE_MANAGER:GetScene("guildBank")
    guildBankScene:RegisterCallback("StateChange",
        function(oldState, newState)
            if newState == SCENE_HIDDEN then
                ZO_PlayerInventory_EndSearch(ZO_GuildBankSearchBox)
            end
        end)
end

local function showSearchBoxes()
    -- new in 3.2: player inventory fragments set the search bar visible when the layout is applied
    BACKPACK_DEFAULT_LAYOUT_FRAGMENT.layoutData.useSearchBar = true
    BACKPACK_MENU_BAR_LAYOUT_FRAGMENT.layoutData.useSearchBar = true
    BACKPACK_MAIL_LAYOUT_FRAGMENT.layoutData.useSearchBar = true
    BACKPACK_PLAYER_TRADE_LAYOUT_FRAGMENT.layoutData.useSearchBar = true
    BACKPACK_STORE_LAYOUT_FRAGMENT.layoutData.useSearchBar = true
    BACKPACK_FENCE_LAYOUT_FRAGMENT.layoutData.useSearchBar = true
    BACKPACK_LAUNDER_LAYOUT_FRAGMENT.layoutData.useSearchBar = true

    -- re-anchoring is necessary because they overlap with sort headers
    ZO_PlayerInventorySearchBox:ClearAnchors()
    ZO_PlayerInventorySearchBox:SetAnchor(BOTTOMRIGHT, nil, TOPRIGHT, -15, -55)
    ZO_PlayerInventorySearchBox:SetHidden(false)

    ZO_PlayerBankSearchBox:ClearAnchors()
    ZO_PlayerBankSearchBox:SetAnchor(BOTTOMRIGHT, nil, TOPRIGHT, -15, -55)
    ZO_PlayerBankSearchBox:SetWidth(ZO_PlayerInventorySearchBox:GetWidth())
    ZO_PlayerBankSearchBox:SetHidden(false)

    ZO_GuildBankSearchBox:ClearAnchors()
    ZO_GuildBankSearchBox:SetAnchor(BOTTOMRIGHT, nil, TOPRIGHT, -15, -55)
    ZO_GuildBankSearchBox:SetWidth(ZO_PlayerInventorySearchBox:GetWidth())
    ZO_GuildBankSearchBox:SetHidden(false)

    ZO_CraftBagSearchBox:ClearAnchors()
    ZO_CraftBagSearchBox:SetAnchor(BOTTOMRIGHT, nil, TOPRIGHT, -15, -55)
    ZO_CraftBagSearchBox:SetWidth(ZO_PlayerInventorySearchBox:GetWidth())
    ZO_CraftBagSearchBox:SetHidden(false)
end

local function onPlayerActivated(eventCode)
    EVENT_MANAGER:UnregisterForEvent(myNAME, eventCode)

    fixSearchBoxBugs()

    if not libCIF._searchBoxesDisabled then
        showSearchBoxes()
    end

    if not libCIF._guildStoreSellFiltersDisabled then
        -- note that this sets trading house layout offsets, so it
        -- has to be done before they are shifted
        enableGuildStoreSellFilters()
    end

    local shiftY = libCIF._backpackLayoutShiftY
    if shiftY then
        local function doShift(layoutData)
            layoutData.sortByOffsetY = layoutData.sortByOffsetY + shiftY
            layoutData.backpackOffsetY = layoutData.backpackOffsetY + shiftY
        end
        doShift(BACKPACK_MENU_BAR_LAYOUT_FRAGMENT.layoutData)
        doShift(BACKPACK_BANK_LAYOUT_FRAGMENT.layoutData)
        doShift(BACKPACK_TRADING_HOUSE_LAYOUT_FRAGMENT.layoutData)
        doShift(BACKPACK_MAIL_LAYOUT_FRAGMENT.layoutData)
        doShift(BACKPACK_PLAYER_TRADE_LAYOUT_FRAGMENT.layoutData)
        doShift(BACKPACK_STORE_LAYOUT_FRAGMENT.layoutData)
        doShift(BACKPACK_FENCE_LAYOUT_FRAGMENT.layoutData)
        doShift(BACKPACK_LAUNDER_LAYOUT_FRAGMENT.layoutData)
        doShift(BACKPACK_GUILD_BANK_LAYOUT_FRAGMENT.layoutData)
    end

    -- ZO_InventoryManager:SetTradingHouseModeEnabled has been removed in 3.2
    -- from now on we have to listen to the scene state change and do the following:
    --  1) saves/restores the current filter
    --      - or would, if the filter wasn't reset in ApplyBackpackLayout
    --      - this simply doesn't work
    --  2) shows the search box and hides the filters tab, or vice versa
    --      - we want to show or hide them according to add-on requirements
    --        specified during start-up
    local savedPlayerInventorySearchBoxAnchor = {false}
    local savedCraftBagSearchBoxAnchor = {false}

    local layoutData = BACKPACK_TRADING_HOUSE_LAYOUT_FRAGMENT.layoutData
    local function SetTradingHouseModeEnabled(enabled)
        libCIF._tradingHouseModeEnabled = enabled

        if enabled then
            layoutData.useSearchBar = true
            layoutData.hideTabBar = false
            ZO_CraftBagSearchBox:SetHidden(false)

            -- move search box if custom sell filters are enabled (AwesomeGuildStore)
            if libCIF._guildStoreSellFiltersDisabled then
                if(not savedPlayerInventorySearchBoxAnchor[1]) then
                    savedPlayerInventorySearchBoxAnchor = {ZO_PlayerInventorySearchBox:GetAnchor(0)}
                    ZO_PlayerInventorySearchBox:ClearAnchors()
                    ZO_PlayerInventorySearchBox:SetAnchor(TOPLEFT, ZO_SharedRightPanelBackground, TOPLEFT, 16, 11)
                end
                if(not savedCraftBagSearchBoxAnchor[1]) then
                    savedCraftBagSearchBoxAnchor = {ZO_CraftBagSearchBox:GetAnchor(0)}
                    ZO_CraftBagSearchBox:ClearAnchors()
                    ZO_CraftBagSearchBox:SetAnchor(BOTTOMLEFT, nil, TOPLEFT, 36, -8)
                end
            end
        else
            layoutData.useSearchBar = libCIF._searchBoxesDisabled
            layoutData.hideTabBar = libCIF._guildStoreSellFiltersDisabled
            ZO_CraftBagSearchBox:SetHidden(libCIF._searchBoxesDisabled)

            -- restore original search box position (FilterIt)
            if savedPlayerInventorySearchBoxAnchor[1] then
                ZO_PlayerInventorySearchBox:ClearAnchors()
                ZO_PlayerInventorySearchBox:SetAnchor(unpack(savedPlayerInventorySearchBoxAnchor, 2))
                savedPlayerInventorySearchBoxAnchor[1] = false
            end
            if savedCraftBagSearchBoxAnchor[1] then
                ZO_CraftBagSearchBox:ClearAnchors()
                ZO_CraftBagSearchBox:SetAnchor(unpack(savedCraftBagSearchBoxAnchor, 2))
                savedCraftBagSearchBoxAnchor[1] = false
            end
        end
    end

    local function SceneStateChange(oldState, newState)
        if newState == SCENE_SHOWING then
            SetTradingHouseModeEnabled(true)
        elseif newState == SCENE_HIDING then
            SetTradingHouseModeEnabled(false)
        end
    end

    TRADING_HOUSE_SCENE:RegisterCallback("StateChange",  SceneStateChange)
end

-- shift backpack sort headers and item list down (shiftY > 0) or up (shiftY < 0)
-- add-ons should only call this from their EVENT_ADD_ON_LOADED handler
function libCIF:addBackpackLayoutShiftY(shiftY)
    libCIF._backpackLayoutShiftY = (libCIF._backpackLayoutShiftY or 0) + shiftY
end

-- tell libCIF to skip enabling inventory filters on guild store sell tab
-- add-ons should only call this from their EVENT_ADD_ON_LOADED handler
function libCIF:disableGuildStoreSellFilters()
    libCIF._guildStoreSellFiltersDisabled = true
end

-- tell libCIF to skip showing inventory search boxes outside guild store sell tab
-- add-ons should only call this from their EVENT_ADD_ON_LOADED handler
function libCIF:disableSearchBoxes()
    libCIF._searchBoxesDisabled = true
end

EVENT_MANAGER:UnregisterForEvent(myNAME, EVENT_PLAYER_ACTIVATED)
EVENT_MANAGER:RegisterForEvent(myNAME, EVENT_PLAYER_ACTIVATED, onPlayerActivated)
