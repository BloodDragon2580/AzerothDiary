local ADDON_NAME, AD = ...

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")

local trackedEvents = {
    "PLAYER_LOGIN",
    "PLAYER_LOGOUT",
    "PLAYER_ENTERING_WORLD",
    "ACHIEVEMENT_EARNED",
    "NEW_MOUNT_ADDED",
    "NEW_PET_ADDED",
    "NEW_TOY_ADDED",
    "TRANSMOG_COLLECTION_SOURCE_ADDED",
    "PLAYER_LEVEL_UP",
    "BOSS_KILL",
    "CHALLENGE_MODE_COMPLETED",
    "QUEST_TURNED_IN",
    "PLAYER_MONEY",
    "PLAYER_EQUIPMENT_CHANGED",
    "PLAYER_AVG_ITEM_LEVEL_UPDATE",
    "PLAYER_REGEN_ENABLED",
    "ITEM_DATA_LOAD_RESULT",
}

local function registerTrackedEvents()
    for _, event in ipairs(trackedEvents) do
        eventFrame:RegisterEvent(event)
    end
end

local function handleSlash(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "" or msg == "open" then
        AD:ToggleWindow()
    elseif msg == "add" or msg == "new" then
        AD:ShowWindow("add")
    elseif msg == "export" or msg == "html" then
        AD:ShowWindow("export")
    elseif msg == "settings" or msg == "config" then
        AD:ShowWindow("settings")
    elseif msg == "minimap" then
        AD.db.settings.showMinimap = not AD.db.settings.showMinimap
        AD:UpdateMinimapVisibility()
        AD:RefreshSettings()
    elseif msg == "help" then
        print("|cffffcc55Azeroth Diary:|r " .. AD:L("SLASH_HELP"))
    else
        print("|cffffcc55Azeroth Diary:|r " .. AD:L("SLASH_HELP"))
    end
end

SLASH_AZEROTHDIARY1 = "/adiary"
SLASH_AZEROTHDIARY2 = "/azerothdiary"
SlashCmdList.AZEROTHDIARY = handleSlash

local handlers = {}

handlers.PLAYER_LOGIN = function()
    AD:UpdateCharacterSnapshot()
    AD:InitializeTrackingBaselines()
    AD:RepairTransmogEntries(true)
    AD:UpdateMinimapVisibility()
    if not AD.db.welcomeShown then
        AD.db.welcomeShown = true
        print("|cffffcc55Azeroth Diary:|r " .. AD:L("WELCOME"))
    end
end

handlers.PLAYER_LOGOUT = function()
    AD:UpdateCharacterSnapshot()
end

handlers.PLAYER_ENTERING_WORLD = function()
    AD:UpdateCharacterSnapshot()
end

handlers.ACHIEVEMENT_EARNED = function(_, achievementID, alreadyEarned)
    AD:OnAchievementEarned(achievementID, alreadyEarned)
end

handlers.NEW_MOUNT_ADDED = function(_, mountID)
    AD:OnNewMountAdded(mountID)
end

handlers.NEW_PET_ADDED = function(_, petGUID)
    AD:OnNewPetAdded(petGUID)
end

handlers.NEW_TOY_ADDED = function(_, itemID)
    AD:OnNewToyAdded(itemID)
end

handlers.TRANSMOG_COLLECTION_SOURCE_ADDED = function(_, sourceID)
    AD:OnTransmogAdded(sourceID)
end

handlers.PLAYER_LEVEL_UP = function(_, level)
    AD:OnPlayerLevelUp(level)
end

handlers.BOSS_KILL = function(_, encounterID, encounterName)
    AD:OnBossKill(encounterID, encounterName)
end

handlers.CHALLENGE_MODE_COMPLETED = function()
    AD:OnChallengeModeCompleted()
end

handlers.QUEST_TURNED_IN = function(_, questID, xpReward, moneyReward)
    AD:OnQuestTurnedIn(questID, xpReward, moneyReward)
end

handlers.PLAYER_MONEY = function()
    AD:OnPlayerMoney()
end

handlers.PLAYER_EQUIPMENT_CHANGED = function()
    AD:QueueItemLevelCheck()
end

handlers.PLAYER_AVG_ITEM_LEVEL_UPDATE = function()
    AD:QueueItemLevelCheck()
end

handlers.PLAYER_REGEN_ENABLED = function()
    AD:OnPlayerRegenEnabled()
end

handlers.ITEM_DATA_LOAD_RESULT = function(_, itemID, success)
    AD:OnItemDataLoadResult(itemID, success)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon ~= ADDON_NAME then return end
        AD:InitializeDB()
        AD:CreateUI()
        if UISpecialFrames then table.insert(UISpecialFrames, "AzerothDiaryMainFrame") end
        registerTrackedEvents()
        return
    end
    local handler = handlers[event]
    if handler then handler(event, ...) end
end)
