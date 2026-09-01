local ADDON_NAME, AD = ...

local GOLD_MILESTONES = {
    10000 * 10000,       -- 10k gold
    50000 * 10000,       -- 50k
    100000 * 10000,      -- 100k
    250000 * 10000,      -- 250k
    500000 * 10000,      -- 500k
    1000000 * 10000,     -- 1m
    2500000 * 10000,     -- 2.5m
    5000000 * 10000,     -- 5m
    10000000 * 10000,    -- 10m
}

function AD:IsTracking(kind)
    return self.db and self.db.settings and self.db.settings.tracking and self.db.settings.tracking[kind]
end

function AD:InitializeTrackingBaselines()
    if not self.db then return end
    self:UpdateCharacterSnapshot()
    local char = self.db.characters[self.charKey]
    char.goldMilestones = char.goldMilestones or {}
    local money = GetMoney and GetMoney() or 0
    char.lastMoney = money
    for _, threshold in ipairs(GOLD_MILESTONES) do
        if money >= threshold then char.goldMilestones[tostring(threshold)] = true end
    end

    if GetAverageItemLevel and not InCombatLockdown() then
        local ok, _, equipped = pcall(GetAverageItemLevel)
        if ok and type(equipped) == "number" then
            char.bestItemLevel = math.max(char.bestItemLevel or 0, equipped)
            char.lastLoggedItemLevel = char.lastLoggedItemLevel or equipped
            char.currentItemLevel = equipped
        end
    end
end

function AD:OnAchievementEarned(achievementID, alreadyEarned)
    if not self:IsTracking("achievement") or alreadyEarned then return end
    local id, name, points, _, _, _, _, description, _, icon = GetAchievementInfo(achievementID)
    self:AddEntry("achievement", {
        id = id or achievementID,
        name = name or ("Achievement #" .. tostring(achievementID)),
        points = points or 0,
        detail = description or "",
        icon = icon,
    })
end

function AD:OnNewMountAdded(mountID)
    if not self:IsTracking("mount") then return end
    local name, spellID, icon
    if C_MountJournal and C_MountJournal.GetMountInfoByID then
        local ok
        ok, name, spellID, icon = pcall(C_MountJournal.GetMountInfoByID, mountID)
        if not ok then name, spellID, icon = nil, nil, nil end
    end
    self:AddEntry("mount", {
        id = mountID,
        spellID = spellID,
        name = name or self:L("UNKNOWN_MOUNT"),
        icon = icon,
    })
end

function AD:OnNewPetAdded(petGUID)
    if not self:IsTracking("pet") then return end
    local speciesID, customName, level, name, icon
    if C_PetJournal and C_PetJournal.GetPetInfoByPetID then
        local ok, species, custom, petLevel, xp, maxXp, displayID, isFavorite, speciesName, speciesIcon = pcall(C_PetJournal.GetPetInfoByPetID, petGUID)
        if ok then
            speciesID, customName, level, name, icon = species, custom, petLevel, speciesName, speciesIcon
        end
    end
    self:AddEntry("pet", {
        guid = petGUID,
        speciesID = speciesID,
        name = customName or name or self:L("UNKNOWN_PET"),
        speciesName = name,
        petLevel = level,
        icon = icon,
    })
end

function AD:OnNewToyAdded(itemID)
    if not self:IsTracking("toy") then return end
    local toyName, icon
    if C_ToyBox and C_ToyBox.GetToyInfo then
        local ok, _, n, i = pcall(C_ToyBox.GetToyInfo, itemID)
        if ok then toyName, icon = n, i end
    end
    self:AddEntry("toy", {
        id = itemID,
        name = toyName or self:L("UNKNOWN_TOY"),
        icon = icon,
    })
end

local function transmogLinkLabel(itemLink)
    if type(itemLink) ~= "string" or itemLink == "" then return nil end
    local label = itemLink:match("|h%[(.-)%]|h")
    if not label or label == "" then return nil end
    return label
end

local function transmogItemIDFromLink(itemLink)
    if type(itemLink) ~= "string" then return nil end
    return tonumber(itemLink:match("|Hitem:(%d+)"))
end

function AD:IsFallbackTransmogName(name)
    return not name or name == "" or name == "Neue Vorlage" or name == "New appearance"
end

function AD:IsUsableTransmogItemLink(itemLink)
    return transmogLinkLabel(itemLink) ~= nil
end

function AD:HydrateTransmogEntry(entry, requestMissing)
    if not entry or entry.kind ~= "transmog" then return false end
    local d = entry.data or {}
    entry.data = d

    local sourceID = tonumber(d.sourceID)
    local itemID = tonumber(d.itemID)

    if sourceID and C_TransmogCollection then
        if C_TransmogCollection.GetSourceInfo then
            local ok, info = pcall(C_TransmogCollection.GetSourceInfo, sourceID)
            if ok and type(info) == "table" then
                itemID = tonumber(info.itemID) or itemID
                if not self:IsFallbackTransmogName(info.name) then d.name = info.name end
            end
        end

        if C_TransmogCollection.GetAppearanceSourceInfo then
            local ok, info = pcall(C_TransmogCollection.GetAppearanceSourceInfo, sourceID)
            if ok and type(info) == "table" then
                if info.icon then d.icon = info.icon end
                itemID = itemID or transmogItemIDFromLink(info.itemLink)
                if self:IsUsableTransmogItemLink(info.itemLink) then
                    d.itemLink = info.itemLink
                    if self:IsFallbackTransmogName(d.name) then
                        d.name = transmogLinkLabel(info.itemLink)
                    end
                end
            end
        end
    end

    itemID = itemID or transmogItemIDFromLink(d.itemLink)
    if itemID then d.itemID = itemID end

    if itemID and C_Item then
        if C_Item.GetItemNameByID then
            local ok, itemName = pcall(C_Item.GetItemNameByID, itemID)
            if ok and not self:IsFallbackTransmogName(itemName) then d.name = itemName end
        end

        if C_Item.GetItemInfo then
            local ok, itemName, itemLink, _, _, _, _, _, _, _, itemIcon = pcall(C_Item.GetItemInfo, itemID)
            if ok then
                if not self:IsFallbackTransmogName(itemName) then d.name = itemName end
                if self:IsUsableTransmogItemLink(itemLink) then d.itemLink = itemLink end
                if itemIcon then d.icon = itemIcon end
            end
        end
    end

    -- Blizzard can return a working hyperlink whose visible label is literally [] while
    -- the item is not cached. Never keep/export that placeholder as diary text.
    if d.itemLink and not self:IsUsableTransmogItemLink(d.itemLink) then
        d.itemLink = nil
    end

    if self:IsFallbackTransmogName(d.name) then
        d.name = self:L("UNKNOWN_TRANSMOG")
        if requestMissing and itemID and C_Item and C_Item.RequestLoadItemDataByID then
            self.pendingTransmogItems = self.pendingTransmogItems or {}
            self.pendingTransmogItems[itemID] = self.pendingTransmogItems[itemID] or {}
            self.pendingTransmogItems[itemID][entry.id] = true
            pcall(C_Item.RequestLoadItemDataByID, tostring(itemID))
        end
        return false
    end

    return true
end

function AD:RepairTransmogEntries(requestMissing)
    if not self.db or not self.db.entries then return end
    local changed = false
    for _, entry in ipairs(self.db.entries) do
        if entry.kind == "transmog" then
            local beforeName = entry.data and entry.data.name
            local beforeLink = entry.data and entry.data.itemLink
            local beforeItemID = entry.data and entry.data.itemID
            self:HydrateTransmogEntry(entry, requestMissing)
            local d = entry.data or {}
            if beforeName ~= d.name or beforeLink ~= d.itemLink or beforeItemID ~= d.itemID then
                changed = true
            end
        end
    end
    if changed and self.RefreshUI then self:RefreshUI() end
end

function AD:OnItemDataLoadResult(itemID, success)
    itemID = tonumber(itemID)
    if not itemID then return end

    local pending = self.pendingTransmogItems and self.pendingTransmogItems[itemID]
    if not pending then return end
    local changed = false

    if self.db and self.db.entries then
        for _, entry in ipairs(self.db.entries) do
            if entry.kind == "transmog" then
                local d = entry.data or {}
                local linkedID = tonumber(d.itemID) or transmogItemIDFromLink(d.itemLink)
                if linkedID == itemID and (pending or self:IsFallbackTransmogName(d.name) or not self:IsUsableTransmogItemLink(d.itemLink)) then
                    local beforeName, beforeLink = d.name, d.itemLink
                    self:HydrateTransmogEntry(entry, false)
                    if beforeName ~= d.name or beforeLink ~= d.itemLink then changed = true end
                end
            end
        end
    end

    if self.pendingTransmogItems then self.pendingTransmogItems[itemID] = nil end
    if changed and self.RefreshUI then self:RefreshUI() end
end

function AD:OnTransmogAdded(sourceID)
    if not self:IsTracking("transmog") then return end

    local name, itemID, itemLink, icon
    if C_TransmogCollection then
        if C_TransmogCollection.GetSourceInfo then
            local ok, info = pcall(C_TransmogCollection.GetSourceInfo, sourceID)
            if ok and type(info) == "table" then
                name = info.name
                itemID = info.itemID
            end
        end
        if C_TransmogCollection.GetAppearanceSourceInfo then
            local ok, info = pcall(C_TransmogCollection.GetAppearanceSourceInfo, sourceID)
            if ok and type(info) == "table" then
                itemLink = self:IsUsableTransmogItemLink(info.itemLink) and info.itemLink or nil
                icon = info.icon
                itemID = itemID or transmogItemIDFromLink(info.itemLink)
                if self:IsFallbackTransmogName(name) and itemLink then
                    name = transmogLinkLabel(itemLink)
                end
            end
        end
        if not itemID and C_TransmogCollection.GetSourceItemID then
            local ok, id = pcall(C_TransmogCollection.GetSourceItemID, sourceID)
            if ok then itemID = id end
        end
    end

    if self:IsFallbackTransmogName(name) and itemID and C_Item and C_Item.GetItemNameByID then
        local ok, itemName = pcall(C_Item.GetItemNameByID, itemID)
        if ok then name = itemName end
    end

    local entry = self:AddEntry("transmog", {
        sourceID = sourceID,
        itemID = itemID,
        itemLink = itemLink,
        name = (not self:IsFallbackTransmogName(name)) and name or self:L("UNKNOWN_TRANSMOG"),
        icon = icon,
    })

    -- Re-check all available metadata and request uncached item data if necessary.
    self:HydrateTransmogEntry(entry, true)
end

function AD:OnPlayerLevelUp(level)
    if not self:IsTracking("level") then return end
    self:AddEntry("level", { level = tonumber(level) or UnitLevel("player") or 0 })
end

function AD:OnBossKill(encounterID, encounterName)
    if not self:IsTracking("boss") then return end
    local instanceName, instanceType, difficultyID, difficultyName = GetInstanceInfo()
    difficultyID = difficultyID or 0
    local charKey = self.charKey or self:GetCharacterKey()
    self.db.bossFirstKills[charKey] = self.db.bossFirstKills[charKey] or {}
    local key = tostring(encounterID or encounterName or "boss") .. ":" .. tostring(difficultyID)

    if self.db.settings.bossFirstOnly and self.db.bossFirstKills[charKey][key] then return end
    self.db.bossFirstKills[charKey][key] = true

    self:AddEntry("boss", {
        encounterID = encounterID,
        name = encounterName or "Boss",
        instance = instanceName or self:L("ZONE_UNKNOWN"),
        instanceType = instanceType,
        difficultyID = difficultyID,
        difficulty = difficultyName or self:L("UNKNOWN_DIFFICULTY"),
    })
end

local function formatDuration(milliseconds)
    if type(milliseconds) ~= "number" or milliseconds <= 0 then return nil end
    local seconds = math.floor(milliseconds / 1000)
    local mins = math.floor(seconds / 60)
    local secs = seconds % 60
    return string.format("%d:%02d", mins, secs)
end

function AD:OnChallengeModeCompleted()
    if not self:IsTracking("mythicplus") then return end
    C_Timer.After(0.6, function()
        if not AD.db or not C_ChallengeMode or not C_ChallengeMode.GetChallengeCompletionInfo then return end
        local ok, info = pcall(C_ChallengeMode.GetChallengeCompletionInfo)
        if not ok or type(info) ~= "table" then return end
        local mapID = tonumber(info.mapChallengeModeID) or 0
        local level = tonumber(info.level) or 0
        if mapID == 0 or level == 0 then return end

        local charKey = AD.charKey or AD:GetCharacterKey()
        AD.db.mythicPlusBests[charKey] = AD.db.mythicPlusBests[charKey] or {}
        local previous = tonumber(AD.db.mythicPlusBests[charKey][tostring(mapID)]) or 0
        if AD.db.settings.mythicPlusBestOnly and level <= previous then return end
        AD.db.mythicPlusBests[charKey][tostring(mapID)] = math.max(previous, level)

        local dungeonName = AD:L("UNKNOWN_DUNGEON")
        if C_ChallengeMode.GetMapUIInfo then
            local mapOk, name = pcall(C_ChallengeMode.GetMapUIInfo, mapID)
            if mapOk and name and name ~= "" then dungeonName = name end
        end
        AD:AddEntry("mythicplus", {
            mapID = mapID,
            name = dungeonName,
            level = level,
            onTime = info.onTime and true or false,
            keystoneUpgradeLevels = info.keystoneUpgradeLevels,
            duration = info.time,
            durationText = formatDuration(info.time),
            oldScore = info.oldOverallDungeonScore,
            newScore = info.newOverallDungeonScore,
            isMapRecord = info.isMapRecord,
        })
    end)
end

function AD:OnQuestTurnedIn(questID, xpReward, moneyReward)
    if not self:IsTracking("quest") then return end
    local function saveQuest()
        local name
        if C_QuestLog and C_QuestLog.GetTitleForQuestID then
            local ok, result = pcall(C_QuestLog.GetTitleForQuestID, questID)
            if ok then name = result end
        end
        AD:AddEntry("quest", {
            id = questID,
            name = name or AD:L("UNKNOWN_QUEST", tonumber(questID) or 0),
            xp = xpReward,
            money = moneyReward,
        })
    end

    if C_QuestLog and C_QuestLog.RequestLoadQuestByID then
        pcall(C_QuestLog.RequestLoadQuestByID, questID)
        C_Timer.After(0.4, saveQuest)
    else
        saveQuest()
    end
end

function AD:OnPlayerMoney()
    if not self:IsTracking("gold") then return end
    local char = self.db.characters[self.charKey]
    if not char then return end
    char.goldMilestones = char.goldMilestones or {}
    local current = GetMoney and GetMoney() or 0
    local previous = char.lastMoney or current
    char.lastMoney = current
    char.money = current

    if current <= previous then return end
    for _, threshold in ipairs(GOLD_MILESTONES) do
        local key = tostring(threshold)
        if previous < threshold and current >= threshold and not char.goldMilestones[key] then
            char.goldMilestones[key] = true
            self:AddEntry("gold", { amount = threshold })
        end
    end
end

function AD:CheckItemLevel()
    if not self:IsTracking("itemlevel") then return end
    if InCombatLockdown() then
        self.pendingItemLevelCheck = true
        return
    end
    if not GetAverageItemLevel then return end
    local ok, _, equipped = pcall(GetAverageItemLevel)
    if not ok or type(equipped) ~= "number" or equipped <= 0 then return end

    local char = self.db.characters[self.charKey]
    if not char then return end
    local step = tonumber(self.db.settings.itemLevelStep) or 2
    local baseline = tonumber(char.lastLoggedItemLevel)
    if not baseline then
        char.lastLoggedItemLevel = equipped
        char.bestItemLevel = math.max(char.bestItemLevel or 0, equipped)
        char.currentItemLevel = equipped
        return
    end

    char.bestItemLevel = math.max(char.bestItemLevel or 0, equipped)
    char.currentItemLevel = equipped
    if equipped >= baseline + step then
        char.lastLoggedItemLevel = equipped
        self:AddEntry("itemlevel", { itemLevel = equipped })
    end
end

function AD:QueueItemLevelCheck()
    if self.itemLevelTimer then self.itemLevelTimer:Cancel() end
    self.itemLevelTimer = C_Timer.NewTimer(1.2, function()
        AD.itemLevelTimer = nil
        AD:CheckItemLevel()
    end)
end

function AD:OnPlayerRegenEnabled()
    if self.pendingItemLevelCheck then
        self.pendingItemLevelCheck = nil
        self:QueueItemLevelCheck()
    end
end
