local ADDON_NAME, AD = ...

AD.VERSION = "1.1"
AD.SCHEMA_VERSION = 3

AD.DEFAULTS = {
    schemaVersion = AD.SCHEMA_VERSION,
    nextEntryId = 1,
    entries = {},
    characters = {},
    bossFirstKills = {},
    mythicPlusBests = {},
    minimap = {
        hide = false,
        minimapPos = 225,
    },
    settings = {
        language = "auto",
        showMinimap = true,
        showToasts = true,
        bossFirstOnly = true,
        mythicPlusBestOnly = true,
        itemLevelStep = 2,
        htmlWowheadTooltips = true,
        tracking = {
            achievement = true,
            mount = true,
            pet = true,
            toy = true,
            transmog = true,
            boss = true,
            mythicplus = true,
            level = true,
            gold = true,
            itemlevel = true,
            quest = false,
        },
    },
}

AD.KIND_INFO = {
    achievement = { category = "collection", label = "KIND_ACHIEVEMENT", icon = "Interface\\Icons\\Achievement_General" },
    mount = { category = "collection", label = "KIND_MOUNT", icon = "Interface\\Icons\\Ability_Mount_RidingHorse" },
    pet = { category = "collection", label = "KIND_PET", icon = "Interface\\Icons\\INV_Box_PetCarrier_01" },
    toy = { category = "collection", label = "KIND_TOY", icon = "Interface\\Icons\\INV_Misc_Toy_10" },
    transmog = { category = "collection", label = "KIND_TRANSMOG", icon = "Interface\\Icons\\INV_Misc_EngGizmos_19" },
    boss = { category = "adventures", label = "KIND_BOSS", icon = "Interface\\Icons\\Achievement_Boss_LichKing" },
    mythicplus = { category = "adventures", label = "KIND_MPLUS", icon = "Interface\\Icons\\Achievement_ChallengeMode_Gold" },
    level = { category = "progress", label = "KIND_LEVEL", icon = "Interface\\Icons\\Achievement_Level_80" },
    gold = { category = "progress", label = "KIND_GOLD", icon = "Interface\\Icons\\INV_Misc_Coin_01" },
    itemlevel = { category = "progress", label = "KIND_ITEMLEVEL", icon = "Interface\\Icons\\INV_Chest_Cloth_17" },
    quest = { category = "progress", label = "KIND_QUEST", icon = "Interface\\Icons\\INV_Misc_Note_05" },
    manual = { category = "manual", label = "KIND_MANUAL", icon = "Interface\\Icons\\INV_Misc_Book_09" },
}

local function deepCopy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for k, v in pairs(value) do
        result[k] = deepCopy(v)
    end
    return result
end

local function mergeDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if target[k] == nil then
            target[k] = deepCopy(v)
        elseif type(v) == "table" and type(target[k]) == "table" then
            mergeDefaults(target[k], v)
        end
    end
end

function AD:InitializeDB()
    if type(AzerothDiaryDB) ~= "table" then
        AzerothDiaryDB = deepCopy(self.DEFAULTS)
    else
        local oldSchema = AzerothDiaryDB.schemaVersion or 0

        -- v2: migrate the hand-built minimap button settings to LibDBIcon.
        if oldSchema < 2 then
            local oldSettings = AzerothDiaryDB.settings or {}
            AzerothDiaryDB.minimap = AzerothDiaryDB.minimap or {}
            if AzerothDiaryDB.minimap.hide == nil then
                AzerothDiaryDB.minimap.hide = oldSettings.showMinimap == false
            end
            if AzerothDiaryDB.minimap.minimapPos == nil then
                AzerothDiaryDB.minimap.minimapPos = oldSettings.minimapAngle or 225
            end
        end

        -- v3: HTML export can optionally include Wowhead links/tooltips.
        -- Existing memories already keep the relevant Blizzard IDs where available,
        -- so no entry rewrite is necessary; mergeDefaults adds the new preference.
        if oldSchema < 3 then
            AzerothDiaryDB.settings = AzerothDiaryDB.settings or {}
            if AzerothDiaryDB.settings.htmlWowheadTooltips == nil then
                AzerothDiaryDB.settings.htmlWowheadTooltips = true
            end
        end

        mergeDefaults(AzerothDiaryDB, self.DEFAULTS)
        AzerothDiaryDB.schemaVersion = self.SCHEMA_VERSION
    end

    self.db = AzerothDiaryDB
    self.db.settings.showMinimap = not self.db.minimap.hide
    self:UpdateCharacterSnapshot()
end

function AD:GetLanguage()
    local configured = self.db and self.db.settings and self.db.settings.language or "auto"
    if configured == "deDE" or configured == "enUS" then
        return configured
    end
    return GetLocale() == "deDE" and "deDE" or "enUS"
end

function AD:L(key, ...)
    local locale = self:GetLanguage()
    local tableForLocale = self.Locales and self.Locales[locale]
    local fallback = self.Locales and self.Locales.enUS
    local value = tableForLocale and tableForLocale[key] or fallback and fallback[key] or key
    if select("#", ...) > 0 then
        local ok, formatted = pcall(string.format, value, ...)
        if ok then return formatted end
    end
    return value
end

function AD:GetCharacterKey()
    local name = UnitName("player") or "Unknown"
    local realm = GetNormalizedRealmName and GetNormalizedRealmName() or GetRealmName() or "UnknownRealm"
    return name .. "-" .. realm
end

function AD:GetCharacterDisplayName(charKey)
    local char = self.db and self.db.characters and self.db.characters[charKey]
    if char and char.name then
        return char.name
    end
    return charKey or "Unknown"
end

function AD:UpdateCharacterSnapshot()
    if not self.db then return end
    local charKey = self:GetCharacterKey()
    local name = UnitName("player") or "Unknown"
    local realm = GetRealmName() or "Unknown Realm"
    local _, classFile = UnitClass("player")
    local level = UnitLevel("player") or 0
    local faction = UnitFactionGroup("player")
    local money = GetMoney and GetMoney() or 0
    local equipped = nil
    if GetAverageItemLevel and not InCombatLockdown() then
        local ok, _, equippedValue = pcall(GetAverageItemLevel)
        if ok and type(equippedValue) == "number" then equipped = equippedValue end
    end

    local char = self.db.characters[charKey] or {}
    char.name = name
    char.realm = realm
    char.class = classFile
    char.level = level
    char.faction = faction
    char.lastSeen = time()
    char.money = money
    if equipped then
        char.currentItemLevel = equipped
        if not char.bestItemLevel or equipped > char.bestItemLevel then
            char.bestItemLevel = equipped
        end
    end
    self.db.characters[charKey] = char
    self.charKey = charKey
end

function AD:GetLocation()
    local zone = GetZoneText and GetZoneText() or ""
    local subZone = GetSubZoneText and GetSubZoneText() or ""
    if not zone or zone == "" then zone = self:L("ZONE_UNKNOWN") end
    return zone, subZone
end

function AD:AddEntry(kind, data, options)
    if not self.db then return nil end
    if not self.KIND_INFO[kind] then return nil end

    self:UpdateCharacterSnapshot()
    local zone, subZone = self:GetLocation()
    local char = self.db.characters[self.charKey] or {}
    local entry = {
        id = self.db.nextEntryId or 1,
        ts = time(),
        kind = kind,
        charKey = self.charKey,
        charName = char.name,
        realm = char.realm,
        class = char.class,
        level = UnitLevel("player") or char.level,
        zone = zone,
        subZone = subZone,
        data = data or {},
    }
    self.db.nextEntryId = entry.id + 1
    table.insert(self.db.entries, entry)

    if self.RefreshUI then self:RefreshUI() end
    if not options or options.toast ~= false then
        if self.db.settings.showToasts and self.ShowToast then self:ShowToast(entry) end
    end
    return entry
end

function AD:DeleteEntry(entryId)
    if not self.db then return false end
    for i = #self.db.entries, 1, -1 do
        if self.db.entries[i].id == entryId then
            table.remove(self.db.entries, i)
            if self.RefreshUI then self:RefreshUI() end
            return true
        end
    end
    return false
end

function AD:GetKindLabel(kind)
    local info = self.KIND_INFO[kind]
    return info and self:L(info.label) or kind
end

function AD:GetKindIcon(kind, entry)
    if entry and entry.data and entry.data.icon then return entry.data.icon end
    local info = self.KIND_INFO[kind]
    return info and info.icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

function AD:GetEntryTitle(entry)
    local d = entry.data or {}
    if entry.kind == "achievement" then
        return self:L("ENTRY_ACHIEVEMENT", d.name or ("Achievement #" .. tostring(d.id or "?")))
    elseif entry.kind == "mount" then
        return self:L("ENTRY_MOUNT", d.name or self:L("UNKNOWN_MOUNT"))
    elseif entry.kind == "pet" then
        return self:L("ENTRY_PET", d.name or self:L("UNKNOWN_PET"))
    elseif entry.kind == "toy" then
        return self:L("ENTRY_TOY", d.name or self:L("UNKNOWN_TOY"))
    elseif entry.kind == "transmog" then
        return self:L("ENTRY_TRANSMOG", d.name or self:L("UNKNOWN_TRANSMOG"))
    elseif entry.kind == "boss" then
        return self:L("ENTRY_BOSS", d.name or "Boss")
    elseif entry.kind == "mythicplus" then
        return self:L("ENTRY_MPLUS", d.name or self:L("UNKNOWN_DUNGEON"), tonumber(d.level) or 0)
    elseif entry.kind == "level" then
        return self:L("ENTRY_LEVEL", tonumber(d.level) or 0)
    elseif entry.kind == "gold" then
        return self:L("ENTRY_GOLD", self:FormatGoldShort(tonumber(d.amount) or 0))
    elseif entry.kind == "itemlevel" then
        return self:L("ENTRY_ITEMLEVEL", tonumber(d.itemLevel) or 0)
    elseif entry.kind == "quest" then
        return self:L("ENTRY_QUEST", d.name or self:L("UNKNOWN_QUEST", tonumber(d.id) or 0))
    elseif entry.kind == "manual" then
        return d.title or self:L("KIND_MANUAL")
    end
    return self:GetKindLabel(entry.kind)
end

function AD:GetEntryDetail(entry)
    local d = entry.data or {}
    if entry.kind == "achievement" then
        return self:L("ENTRY_ACHIEVEMENT_DETAIL", tonumber(d.points) or 0)
    elseif entry.kind == "boss" then
        return self:L("ENTRY_BOSS_DETAIL", d.instance or entry.zone or "", d.difficulty or self:L("UNKNOWN_DIFFICULTY"))
    elseif entry.kind == "mythicplus" then
        local suffix = d.durationText and (" • " .. d.durationText) or ""
        return d.onTime and self:L("ENTRY_MPLUS_DETAIL_TIMED", suffix) or self:L("ENTRY_MPLUS_DETAIL_OVERTIME", suffix)
    elseif entry.kind == "quest" then
        return self:L("ENTRY_QUEST_DETAIL")
    elseif entry.kind == "manual" then
        return d.note or ""
    elseif entry.kind == "transmog" and d.itemLink then
        return d.itemLink
    end
    return d.detail or ""
end

function AD:FormatGoldShort(copper)
    local gold = math.floor((tonumber(copper) or 0) / 10000)
    if gold >= 1000000 then
        local value = gold / 1000000
        return string.format(value >= 10 and "%.0fM" or "%.1fM", value)
    elseif gold >= 1000 then
        local value = gold / 1000
        return string.format(value >= 10 and "%.0fk" or "%.1fk", value)
    end
    return tostring(gold)
end

function AD:FormatDate(ts, includeTime)
    local t = date("*t", ts or time())
    if self:GetLanguage() == "deDE" then
        if includeTime then
            return string.format("%02d.%02d.%04d • %02d:%02d", t.day, t.month, t.year, t.hour, t.min)
        end
        return string.format("%02d.%02d.%04d", t.day, t.month, t.year)
    end
    if includeTime then
        return string.format("%04d-%02d-%02d • %02d:%02d", t.year, t.month, t.day, t.hour, t.min)
    end
    return string.format("%04d-%02d-%02d", t.year, t.month, t.day)
end

function AD:GetFilteredEntries(filterGroup, currentCharacterOnly, searchText)
    local result = {}
    local needle = string.lower(searchText or "")
    for i = #self.db.entries, 1, -1 do
        local entry = self.db.entries[i]
        local info = self.KIND_INFO[entry.kind]
        local groupMatches = filterGroup == "all" or (info and info.category == filterGroup)
        local charMatches = not currentCharacterOnly or entry.charKey == self.charKey
        local searchMatches = true
        if needle ~= "" then
            local haystack = table.concat({
                self:GetEntryTitle(entry) or "",
                self:GetEntryDetail(entry) or "",
                entry.charName or "",
                entry.zone or "",
                self:GetKindLabel(entry.kind) or "",
            }, " ")
            searchMatches = string.find(string.lower(haystack), needle, 1, true) ~= nil
        end
        if groupMatches and charMatches and searchMatches then
            result[#result + 1] = entry
        end
    end
    return result
end

function AD:GetOverviewStats(currentCharacterOnly)
    local stats = {
        total = 0,
        today = 0,
        activeDays = {},
        characters = {},
        kinds = {},
        characterCounts = {},
    }
    local now = date("*t")
    for _, entry in ipairs(self.db.entries) do
        if not currentCharacterOnly or entry.charKey == self.charKey then
            stats.total = stats.total + 1
            local t = date("*t", entry.ts)
            local dayKey = string.format("%04d-%02d-%02d", t.year, t.month, t.day)
            stats.activeDays[dayKey] = true
            stats.characters[entry.charKey] = true
            stats.kinds[entry.kind] = (stats.kinds[entry.kind] or 0) + 1
            stats.characterCounts[entry.charKey] = (stats.characterCounts[entry.charKey] or 0) + 1
            if t.year == now.year and t.month == now.month and t.day == now.day then
                stats.today = stats.today + 1
            end
        end
    end

    local activeDaysCount, characterCount = 0, 0
    for _ in pairs(stats.activeDays) do activeDaysCount = activeDaysCount + 1 end
    for _ in pairs(stats.characters) do characterCount = characterCount + 1 end
    stats.activeDaysCount = activeDaysCount
    stats.characterCount = characterCount

    local bestKey, bestCount = nil, 0
    for key, count in pairs(stats.characterCounts) do
        if count > bestCount then bestKey, bestCount = key, count end
    end
    stats.mostActiveKey = bestKey
    stats.mostActiveCount = bestCount
    return stats
end

function AD:GetOnThisDayEntries(limit, currentCharacterOnly)
    limit = limit or 3
    local result = {}
    local now = date("*t")
    for i = #self.db.entries, 1, -1 do
        local entry = self.db.entries[i]
        local t = date("*t", entry.ts)
        if t.month == now.month and t.day == now.day and t.year < now.year then
            if not currentCharacterOnly or entry.charKey == self.charKey then
                result[#result + 1] = entry
                if #result >= limit then break end
            end
        end
    end
    return result
end
