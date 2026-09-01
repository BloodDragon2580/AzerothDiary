local ADDON_NAME, AD = ...

local floor, max, min = math.floor, math.max, math.min
local ROWS_PER_PAGE = 7
local TIMELINE_ROW_HEIGHT = 50
local TIMELINE_ROW_STEP = 55
local TIMELINE_FOOTER_HEIGHT = 36

local function setBackdrop(frame, r, g, b, a, borderA)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(r or 0.04, g or 0.055, b or 0.09, a or 0.97)
    frame:SetBackdropBorderColor(0.20, 0.25, 0.36, borderA or 0.9)
end

local function createPanel(parent)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    setBackdrop(frame, 0.045, 0.06, 0.095, 0.96, 0.8)
    return frame
end

local function createButton(parent, text, width, height)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width or 120, height or 30)
    setBackdrop(button, 0.09, 0.12, 0.18, 1, 1)
    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    button.text:SetPoint("CENTER")
    button.text:SetText(text or "")
    button:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.14, 0.18, 0.28, 1)
        self:SetBackdropBorderColor(0.85, 0.66, 0.32, 1)
    end)
    button:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.09, 0.12, 0.18, 1)
        self:SetBackdropBorderColor(0.20, 0.25, 0.36, 1)
    end)
    return button
end

local function createEditBox(parent, width, height, multiLine)
    local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    box:SetSize(width, height)
    box:SetAutoFocus(false)
    box:SetFontObject("ChatFontNormal")
    box:SetTextInsets(10, 10, 7, 7)
    box:SetMultiLine(multiLine and true or false)
    setBackdrop(box, 0.025, 0.035, 0.06, 1, 1)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return box
end

local function createCheckbox(parent, label)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check.label = check:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    check.label:SetPoint("LEFT", check, "RIGHT", 5, 0)
    check.label:SetJustifyH("LEFT")
    check.label:SetText(label or "")
    return check
end

local function setButtonActive(button, active)
    if active then
        button:SetBackdropColor(0.19, 0.15, 0.08, 1)
        button:SetBackdropBorderColor(0.88, 0.67, 0.31, 1)
        button.text:SetTextColor(1, 0.83, 0.46)
    else
        button:SetBackdropColor(0.09, 0.12, 0.18, 1)
        button:SetBackdropBorderColor(0.20, 0.25, 0.36, 1)
        button.text:SetTextColor(1, 0.82, 0.35)
    end
end

function AD:CreateUI()
    if self.frame then return end
    self.uiState = self.uiState or {
        tab = "timeline",
        filterGroup = "all",
        currentCharacterOnly = false,
        page = 1,
        exportCurrent = false,
    }

    local frame = CreateFrame("Frame", "AzerothDiaryMainFrame", UIParent, "BackdropTemplate")
    frame:SetSize(940, 650)
    frame:SetPoint("CENTER")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frame:SetFrameStrata("DIALOG")
    setBackdrop(frame, 0.025, 0.035, 0.06, 0.985, 1)
    frame:Hide()
    self.frame = frame

    local accent = frame:CreateTexture(nil, "ARTWORK")
    accent:SetColorTexture(0.84, 0.62, 0.25, 1)
    accent:SetPoint("TOPLEFT", 0, 0)
    accent:SetPoint("TOPRIGHT", 0, 0)
    accent:SetHeight(3)

    local book = frame:CreateTexture(nil, "ARTWORK")
    book:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    book:SetSize(44, 44)
    book:SetPoint("TOPLEFT", 20, -19)
    self.headerIcon = book

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    title:SetPoint("TOPLEFT", book, "TOPRIGHT", 12, -2)
    title:SetTextColor(1, 0.82, 0.4)
    self.titleText = title

    local tagline = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tagline:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
    tagline:SetTextColor(0.63, 0.69, 0.80)
    self.taglineText = tagline

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -7, -7)

    local tabs = {}
    local tabDefs = {
        { key = "timeline", lkey = "TAB_TIMELINE", width = 120 },
        { key = "overview", lkey = "TAB_OVERVIEW", width = 120 },
        { key = "add", lkey = "TAB_ADD", width = 145 },
        { key = "export", lkey = "TAB_EXPORT", width = 110 },
        { key = "settings", lkey = "TAB_SETTINGS", width = 135 },
    }
    local previous
    for _, def in ipairs(tabDefs) do
        local b = createButton(frame, "", def.width, 32)
        if not previous then
            b:SetPoint("TOPLEFT", 20, -80)
        else
            b:SetPoint("LEFT", previous, "RIGHT", 8, 0)
        end
        b.key = def.key
        b.lkey = def.lkey
        b:SetScript("OnClick", function(selfButton) AD:SetTab(selfButton.key) end)
        tabs[def.key] = b
        previous = b
    end
    self.tabs = tabs

    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", 20, -124)
    content:SetPoint("BOTTOMRIGHT", -20, 20)
    self.content = content

    self:CreateTimelinePanel(content)
    self:CreateOverviewPanel(content)
    self:CreateAddPanel(content)
    self:CreateExportPanel(content)
    self:CreateSettingsPanel(content)
    self:CreateToast()
    self:SetupMinimapButton()

    StaticPopupDialogs["AZEROTH_DIARY_DELETE"] = {
        text = "Delete this memory?",
        button1 = YES,
        button2 = NO,
        OnAccept = function(_, data)
            if data and AD:DeleteEntry(data) then
                print("|cffffcc55Azeroth Diary:|r " .. AD:L("DELETED"))
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }

    self:ApplyUILanguage()
    self:SetTab("timeline")
end

function AD:CreateTimelinePanel(parent)
    -- The timeline uses the same framed panel treatment as the other tabs.
    -- This keeps the outer border continuous at all UI scales instead of
    -- leaving search/filter/list controls visually floating on the main frame.
    local panel = createPanel(parent)
    panel:SetAllPoints()
    self.timelinePanel = panel

    local search = createEditBox(panel, 300, 32, false)
    search:SetPoint("TOPLEFT", 10, -10)
    self.timelineSearch = search
    local placeholder = search:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    placeholder:SetPoint("LEFT", 10, 0)
    search.placeholder = placeholder
    search:SetScript("OnTextChanged", function(selfBox)
        selfBox.placeholder:SetShown(selfBox:GetText() == "")
        AD.uiState.page = 1
        AD:RefreshTimeline()
    end)

    local scope = createButton(panel, "", 170, 32)
    scope:SetPoint("LEFT", search, "RIGHT", 10, 0)
    self.scopeButton = scope
    scope:SetScript("OnClick", function()
        AD.uiState.currentCharacterOnly = not AD.uiState.currentCharacterOnly
        AD.uiState.page = 1
        AD:RefreshTimeline()
        AD:RefreshOverview()
    end)

    local filters = {}
    local defs = {
        { key = "all", lkey = "FILTER_ALL", width = 78 },
        { key = "progress", lkey = "FILTER_PROGRESS", width = 105 },
        { key = "collection", lkey = "FILTER_COLLECTION", width = 105 },
        { key = "adventures", lkey = "FILTER_ADVENTURES", width = 112 },
        { key = "manual", lkey = "FILTER_MANUAL", width = 102 },
    }
    local prev
    for _, def in ipairs(defs) do
        local b = createButton(panel, "", def.width, 28)
        if not prev then
            b:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -10)
        else
            b:SetPoint("LEFT", prev, "RIGHT", 7, 0)
        end
        b.key = def.key
        b.lkey = def.lkey
        b:SetScript("OnClick", function(selfButton)
            AD.uiState.filterGroup = selfButton.key
            AD.uiState.page = 1
            AD:RefreshTimeline()
        end)
        filters[def.key] = b
        prev = b
    end
    self.filterButtons = filters

    local rows = {}
    local rowTop = -84
    for i = 1, ROWS_PER_PAGE do
        local row = createPanel(panel)
        row:SetPoint("TOPLEFT", 10, rowTop - ((i - 1) * TIMELINE_ROW_STEP))
        row:SetPoint("TOPRIGHT", -10, rowTop - ((i - 1) * TIMELINE_ROW_STEP))
        row:SetHeight(TIMELINE_ROW_HEIGHT)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(36, 36)
        row.icon:SetPoint("LEFT", 10, 0)

        row.kind = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.kind:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, -3)
        row.kind:SetTextColor(0.9, 0.68, 0.3)

        row.title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.title:SetPoint("TOPLEFT", row.kind, "BOTTOMLEFT", 0, -2)
        row.title:SetPoint("RIGHT", -205, 0)
        row.title:SetJustifyH("LEFT")
        row.title:SetWordWrap(false)

        row.meta = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.meta:SetPoint("RIGHT", -42, 0)
        row.meta:SetWidth(160)
        row.meta:SetJustifyH("RIGHT")

        row.delete = createButton(row, "×", 28, 28)
        row.delete:SetPoint("RIGHT", -8, 0)
        row.delete.text:SetFontObject("GameFontNormalLarge")
        row.delete:SetScript("OnClick", function(selfButton)
            if not selfButton.entryId then return end
            StaticPopupDialogs["AZEROTH_DIARY_DELETE"].text = AD:L("DELETE_CONFIRM")
            StaticPopup_Show("AZEROTH_DIARY_DELETE", nil, nil, selfButton.entryId)
        end)
        row:Hide()
        rows[i] = row
    end
    self.timelineRows = rows

    local noEntries = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    noEntries:SetPoint("CENTER", 0, -10)
    noEntries:SetWidth(600)
    noEntries:SetJustifyH("CENTER")
    self.noEntriesText = noEntries

    -- Keep pagination in a dedicated footer so timeline rows can never
    -- overlap or intercept the navigation controls.
    local footer = CreateFrame("Frame", nil, panel)
    footer:SetPoint("BOTTOMLEFT", 10, 6)
    footer:SetPoint("BOTTOMRIGHT", -10, 6)
    footer:SetHeight(TIMELINE_FOOTER_HEIGHT)
    footer:SetFrameLevel(panel:GetFrameLevel() + 20)
    self.timelineFooter = footer

    local prevPage = createButton(footer, "", 110, 30)
    prevPage:SetPoint("LEFT", 0, 0)
    prevPage:SetScript("OnClick", function()
        AD.uiState.page = max(1, AD.uiState.page - 1)
        AD:RefreshTimeline()
    end)
    self.prevPageButton = prevPage

    local nextPage = createButton(footer, "", 110, 30)
    nextPage:SetPoint("RIGHT", 0, 0)
    nextPage:SetScript("OnClick", function()
        AD.uiState.page = AD.uiState.page + 1
        AD:RefreshTimeline()
    end)
    self.nextPageButton = nextPage

    local pageText = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    pageText:SetPoint("CENTER", 0, 0)
    self.pageText = pageText
end

function AD:CreateOverviewPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()
    panel:Hide()
    self.overviewPanel = panel

    local cards = {}
    for i = 1, 4 do
        local card = createPanel(panel)
        card:SetSize(205, 94)
        if i == 1 then
            card:SetPoint("TOPLEFT", 0, 0)
        else
            card:SetPoint("LEFT", cards[i - 1], "RIGHT", 12, 0)
        end
        card.label = card:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        card.label:SetPoint("TOPLEFT", 14, -14)
        card.value = card:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        card.value:SetPoint("BOTTOMLEFT", 14, 15)
        card.value:SetTextColor(1, 0.82, 0.4)
        cards[i] = card
    end
    self.overviewCards = cards

    local onThisDay = createPanel(panel)
    onThisDay:SetPoint("TOPLEFT", 0, -112)
    onThisDay:SetSize(525, 390)
    self.onThisDayPanel = onThisDay
    onThisDay.title = onThisDay:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    onThisDay.title:SetPoint("TOPLEFT", 16, -16)
    onThisDay.title:SetTextColor(1, 0.82, 0.4)
    onThisDay.lines = {}
    for i = 1, 4 do
        local line = onThisDay:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        line:SetPoint("TOPLEFT", 16, -56 - ((i - 1) * 76))
        line:SetWidth(490)
        line:SetJustifyH("LEFT")
        line:SetJustifyV("TOP")
        onThisDay.lines[i] = line
    end

    local breakdown = createPanel(panel)
    breakdown:SetPoint("TOPLEFT", onThisDay, "TOPRIGHT", 12, 0)
    breakdown:SetPoint("BOTTOMRIGHT", 0, 0)
    self.breakdownPanel = breakdown
    breakdown.title = breakdown:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    breakdown.title:SetPoint("TOPLEFT", 16, -16)
    breakdown.title:SetTextColor(1, 0.82, 0.4)
    breakdown.lines = {}
    for i = 1, 10 do
        local line = breakdown:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        line:SetPoint("TOPLEFT", 16, -52 - ((i - 1) * 28))
        line:SetWidth(315)
        line:SetJustifyH("LEFT")
        breakdown.lines[i] = line
    end
    breakdown.footer = breakdown:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    breakdown.footer:SetPoint("BOTTOMLEFT", 16, 18)
    breakdown.footer:SetWidth(315)
    breakdown.footer:SetJustifyH("LEFT")
end

function AD:CreateAddPanel(parent)
    local panel = createPanel(parent)
    panel:SetAllPoints()
    panel:Hide()
    self.addPanel = panel

    local titleLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleLabel:SetPoint("TOPLEFT", 24, -24)
    self.addTitleLabel = titleLabel

    local titleBox = createEditBox(panel, 820, 38, false)
    titleBox:SetPoint("TOPLEFT", titleLabel, "BOTTOMLEFT", 0, -8)
    self.addTitleBox = titleBox
    local titlePlaceholder = titleBox:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    titlePlaceholder:SetPoint("LEFT", 10, 0)
    titleBox.placeholder = titlePlaceholder
    titleBox:SetScript("OnTextChanged", function(selfBox)
        selfBox.placeholder:SetShown(selfBox:GetText() == "")
    end)

    local noteLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    noteLabel:SetPoint("TOPLEFT", titleBox, "BOTTOMLEFT", 0, -22)
    self.addNoteLabel = noteLabel

    local noteFrame = createPanel(panel)
    noteFrame:SetPoint("TOPLEFT", noteLabel, "BOTTOMLEFT", 0, -8)
    noteFrame:SetSize(820, 290)

    local noteScroll = CreateFrame("ScrollFrame", nil, noteFrame, "UIPanelScrollFrameTemplate")
    noteScroll:SetPoint("TOPLEFT", 7, -7)
    noteScroll:SetPoint("BOTTOMRIGHT", -27, 7)
    local noteBox = CreateFrame("EditBox", nil, noteScroll)
    noteBox:SetMultiLine(true)
    noteBox:SetAutoFocus(false)
    noteBox:SetFontObject("ChatFontNormal")
    noteBox:SetWidth(770)
    noteBox:SetHeight(275)
    noteBox:SetTextInsets(4, 4, 4, 4)
    noteBox:SetScript("OnEscapePressed", function(selfBox) selfBox:ClearFocus() end)
    noteScroll:SetScrollChild(noteBox)
    self.addNoteBox = noteBox
    self.addNoteScroll = noteScroll

    local location = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    location:SetPoint("TOPLEFT", noteFrame, "BOTTOMLEFT", 0, -16)
    location:SetWidth(600)
    location:SetJustifyH("LEFT")
    self.addLocationText = location

    local clear = createButton(panel, "", 120, 34)
    clear:SetPoint("BOTTOMRIGHT", -156, 24)
    clear:SetScript("OnClick", function()
        AD.addTitleBox:SetText("")
        AD.addNoteBox:SetText("")
    end)
    self.addClearButton = clear

    local save = createButton(panel, "", 146, 34)
    save:SetPoint("BOTTOMRIGHT", -24, 24)
    save:SetScript("OnClick", function()
        local titleText = AD.addTitleBox:GetText() or ""
        titleText = titleText:gsub("^%s+", ""):gsub("%s+$", "")
        local noteText = AD.addNoteBox:GetText() or ""
        if titleText == "" then return end
        AD:AddEntry("manual", { title = titleText, note = noteText })
        AD.addTitleBox:SetText("")
        AD.addNoteBox:SetText("")
        print("|cffffcc55Azeroth Diary:|r " .. AD:L("ADD_SAVED"))
        AD:SetTab("timeline")
    end)
    self.addSaveButton = save
end

function AD:CreateExportPanel(parent)
    local panel = createPanel(parent)
    panel:SetAllPoints()
    panel:Hide()
    self.exportPanel = panel

    local heading = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    heading:SetPoint("TOPLEFT", 20, -18)
    heading:SetTextColor(1, 0.82, 0.4)
    self.exportHeading = heading

    local info = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    info:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -10)
    info:SetWidth(820)
    info:SetJustifyH("LEFT")
    info:SetJustifyV("TOP")
    self.exportInfo = info

    local scope = createButton(panel, "", 280, 32)
    scope:SetPoint("TOPLEFT", 20, -160)
    scope:SetScript("OnClick", function()
        AD.uiState.exportCurrent = not AD.uiState.exportCurrent
        AD:RefreshExport()
    end)
    self.exportScopeButton = scope

    local generate = createButton(panel, "", 160, 32)
    generate:SetPoint("LEFT", scope, "RIGHT", 10, 0)
    generate:SetScript("OnClick", function()
        local html, count = AD:GenerateHTML(AD.uiState.exportCurrent, AD.db.settings.htmlWowheadTooltips == true)
        AD.exportEditBox:SetText(html)
        AD.exportEditBox:SetFocus()
        AD.exportEditBox:HighlightText()
        local lines = AD.exportEditBox:GetNumLines() or 1
        AD.exportEditBox:SetHeight(max(360, min(lines * 15 + 30, 120000)))
        AD.exportStatus:SetText(AD:L("EXPORT_READY", count))
    end)
    self.exportGenerateButton = generate

    local status = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    status:SetPoint("LEFT", generate, "RIGHT", 12, 0)
    status:SetWidth(330)
    status:SetJustifyH("LEFT")
    self.exportStatus = status

    local wowhead = createCheckbox(panel, "")
    wowhead:SetPoint("TOPLEFT", 20, -199)
    wowhead:SetScript("OnClick", function(selfCheck)
        AD.db.settings.htmlWowheadTooltips = selfCheck:GetChecked() and true or false
        AD.exportEditBox:SetText("")
        AD.exportStatus:SetText("")
    end)
    self.exportWowheadCheckbox = wowhead

    local codeFrame = createPanel(panel)
    codeFrame:SetPoint("TOPLEFT", 20, -232)
    codeFrame:SetPoint("BOTTOMRIGHT", -20, 58)
    self.exportCodeFrame = codeFrame

    local scroll = CreateFrame("ScrollFrame", nil, codeFrame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", -27, 8)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject("ChatFontNormal")
    edit:SetWidth(800)
    edit:SetHeight(360)
    edit:SetTextInsets(4, 4, 4, 4)
    edit:SetMaxLetters(0)
    edit:SetScript("OnEscapePressed", function(selfBox) selfBox:ClearFocus() end)
    scroll:SetScrollChild(edit)
    self.exportEditBox = edit

    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", 20, 18)
    hint:SetWidth(820)
    hint:SetJustifyH("LEFT")
    self.exportHint = hint
end

function AD:CreateSettingsPanel(parent)
    local panel = createPanel(parent)
    panel:SetAllPoints()
    panel:Hide()
    self.settingsPanel = panel

    local general = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    general:SetPoint("TOPLEFT", 20, -18)
    general:SetTextColor(1, 0.82, 0.4)
    self.settingsGeneralTitle = general

    local languageLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    languageLabel:SetPoint("TOPLEFT", 20, -58)
    self.settingsLanguageLabel = languageLabel

    local langButtons = {}
    local langDefs = {
        { value = "auto", lkey = "SETTINGS_LANGUAGE_AUTO", width = 100 },
        { value = "deDE", lkey = "SETTINGS_LANGUAGE_DE", width = 100 },
        { value = "enUS", lkey = "SETTINGS_LANGUAGE_EN", width = 100 },
    }
    local prev
    for _, def in ipairs(langDefs) do
        local b = createButton(panel, "", def.width, 28)
        if not prev then
            b:SetPoint("TOPLEFT", languageLabel, "BOTTOMLEFT", 0, -8)
        else
            b:SetPoint("LEFT", prev, "RIGHT", 7, 0)
        end
        b.value = def.value
        b.lkey = def.lkey
        b:SetScript("OnClick", function(selfButton)
            AD.db.settings.language = selfButton.value
            AD:ApplyUILanguage()
            AD:RefreshUI()
            print("|cffffcc55Azeroth Diary:|r " .. AD:L("SETTINGS_RELOAD_LANGUAGE"))
        end)
        langButtons[#langButtons + 1] = b
        prev = b
    end
    self.languageButtons = langButtons

    local minimap = createCheckbox(panel, "")
    minimap:SetPoint("TOPLEFT", 20, -136)
    minimap.lkey = "SETTINGS_MINIMAP"
    minimap:SetScript("OnClick", function(selfCheck)
        AD.db.settings.showMinimap = selfCheck:GetChecked() and true or false
        AD:UpdateMinimapVisibility()
    end)
    self.minimapCheckbox = minimap

    local toasts = createCheckbox(panel, "")
    toasts:SetPoint("TOPLEFT", 20, -170)
    toasts.lkey = "SETTINGS_TOASTS"
    toasts:SetScript("OnClick", function(selfCheck)
        AD.db.settings.showToasts = selfCheck:GetChecked() and true or false
    end)
    self.toastsCheckbox = toasts

    local bossFirst = createCheckbox(panel, "")
    bossFirst:SetPoint("TOPLEFT", 430, -136)
    bossFirst.lkey = "SETTINGS_BOSS_FIRST"
    bossFirst:SetScript("OnClick", function(selfCheck)
        AD.db.settings.bossFirstOnly = selfCheck:GetChecked() and true or false
    end)
    self.bossFirstCheckbox = bossFirst

    local mplusBest = createCheckbox(panel, "")
    mplusBest:SetPoint("TOPLEFT", 430, -170)
    mplusBest.lkey = "SETTINGS_MPLUS_BEST"
    mplusBest:SetScript("OnClick", function(selfCheck)
        AD.db.settings.mythicPlusBestOnly = selfCheck:GetChecked() and true or false
    end)
    self.mplusBestCheckbox = mplusBest

    local trackingTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    trackingTitle:SetPoint("TOPLEFT", 20, -222)
    trackingTitle:SetTextColor(1, 0.82, 0.4)
    self.settingsTrackingTitle = trackingTitle

    local trackingDefs = {
        { kind = "achievement", lkey = "TRACK_ACHIEVEMENTS" },
        { kind = "mount", lkey = "TRACK_MOUNTS" },
        { kind = "pet", lkey = "TRACK_PETS" },
        { kind = "toy", lkey = "TRACK_TOYS" },
        { kind = "transmog", lkey = "TRACK_TRANSMOG" },
        { kind = "boss", lkey = "TRACK_BOSSES" },
        { kind = "mythicplus", lkey = "TRACK_MPLUS" },
        { kind = "level", lkey = "TRACK_LEVEL" },
        { kind = "gold", lkey = "TRACK_GOLD" },
        { kind = "itemlevel", lkey = "TRACK_ITEMLEVEL" },
        { kind = "quest", lkey = "TRACK_QUESTS" },
    }
    local checks = {}
    for i, def in ipairs(trackingDefs) do
        local c = createCheckbox(panel, "")
        local col = (i > 6) and 1 or 0
        local row = col == 0 and (i - 1) or (i - 7)
        c:SetPoint("TOPLEFT", 20 + (col * 405), -260 - (row * 34))
        c.kind = def.kind
        c.lkey = def.lkey
        c:SetScript("OnClick", function(selfCheck)
            AD.db.settings.tracking[selfCheck.kind] = selfCheck:GetChecked() and true or false
        end)
        checks[#checks + 1] = c
    end
    self.trackingCheckboxes = checks

    local questWarning = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    questWarning:SetPoint("BOTTOMLEFT", 20, 20)
    questWarning:SetWidth(820)
    questWarning:SetJustifyH("LEFT")
    self.questWarning = questWarning
end

function AD:ApplyUILanguage()
    if not self.frame then return end
    self.titleText:SetText(self:L("ADDON_TITLE"))
    self.taglineText:SetText(self:L("TAGLINE"))

    for _, b in pairs(self.tabs) do b.text:SetText(self:L(b.lkey)) end
    self.timelineSearch.placeholder:SetText(self:L("SEARCH"))
    for _, b in pairs(self.filterButtons) do b.text:SetText(self:L(b.lkey)) end
    self.prevPageButton.text:SetText(self:L("PREVIOUS"))
    self.nextPageButton.text:SetText(self:L("NEXT"))
    self.noEntriesText:SetText(self:L("NO_ENTRIES"))

    self.overviewCards[1].label:SetText(self:L("TOTAL_MEMORIES"))
    self.overviewCards[2].label:SetText(self:L("TODAY"))
    self.overviewCards[3].label:SetText(self:L("ACTIVE_DAYS"))
    self.overviewCards[4].label:SetText(self:L("CHARACTERS"))
    self.onThisDayPanel.title:SetText(self:L("TODAY_IN_AZEROTH"))
    self.breakdownPanel.title:SetText(self:L("CATEGORY_BREAKDOWN"))

    self.addTitleLabel:SetText(self:L("ADD_TITLE"))
    self.addNoteLabel:SetText(self:L("ADD_NOTE"))
    self.addTitleBox.placeholder:SetText(self:L("ADD_PLACEHOLDER_TITLE"))
    self.addClearButton.text:SetText(self:L("ADD_CANCEL"))
    self.addSaveButton.text:SetText(self:L("ADD_SAVE"))

    self.exportHeading:SetText(self:L("EXPORT_TITLE"))
    self.exportInfo:SetText(self:L("EXPORT_TEXT"))
    self.exportGenerateButton.text:SetText(self:L("EXPORT_GENERATE"))
    self.exportWowheadCheckbox.label:SetText(self:L("EXPORT_WOWHEAD"))
    self.exportHint:SetText(self:L("EXPORT_COPY_HINT"))

    self.settingsGeneralTitle:SetText(self:L("SETTINGS_GENERAL"))
    self.settingsLanguageLabel:SetText(self:L("SETTINGS_LANGUAGE"))
    for _, b in ipairs(self.languageButtons) do b.text:SetText(self:L(b.lkey)) end
    self.minimapCheckbox.label:SetText(self:L(self.minimapCheckbox.lkey))
    self.toastsCheckbox.label:SetText(self:L(self.toastsCheckbox.lkey))
    self.bossFirstCheckbox.label:SetText(self:L(self.bossFirstCheckbox.lkey))
    self.mplusBestCheckbox.label:SetText(self:L(self.mplusBestCheckbox.lkey))
    self.settingsTrackingTitle:SetText(self:L("SETTINGS_TRACKING"))
    for _, c in ipairs(self.trackingCheckboxes) do c.label:SetText(self:L(c.lkey)) end
    self.questWarning:SetText(self:L("SETTINGS_QUESTS_WARNING"))

    self:RefreshUI()
end

function AD:SetTab(tab)
    if not self.frame then return end
    self.uiState.tab = tab
    self.timelinePanel:SetShown(tab == "timeline")
    self.overviewPanel:SetShown(tab == "overview")
    self.addPanel:SetShown(tab == "add")
    self.exportPanel:SetShown(tab == "export")
    self.settingsPanel:SetShown(tab == "settings")
    for key, b in pairs(self.tabs) do setButtonActive(b, key == tab) end

    if tab == "add" then
        local zone, sub = self:GetLocation()
        local place = zone
        if sub and sub ~= "" and sub ~= zone then place = zone .. " • " .. sub end
        self.addLocationText:SetText("|cffffcc55📍|r " .. place .. "   |cff8f9bb3" .. (UnitName("player") or "") .. "|r")
    elseif tab == "export" then
        self:RefreshExport()
    elseif tab == "overview" then
        self:RefreshOverview()
    elseif tab == "settings" then
        self:RefreshSettings()
    else
        self:RefreshTimeline()
    end
end

function AD:ShowWindow(tab)
    self:CreateUI()
    self.frame:Show()
    self.frame:Raise()
    self:SetTab(tab or self.uiState.tab or "timeline")
end

function AD:ToggleWindow()
    self:CreateUI()
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        self:ShowWindow("timeline")
    end
end

function AD:RefreshUI()
    if not self.frame then return end
    self:RefreshTimeline()
    self:RefreshOverview()
    self:RefreshExport()
    self:RefreshSettings()
end

function AD:RefreshTimeline()
    if not self.timelinePanel or not self.db then return end
    local entries = self:GetFilteredEntries(self.uiState.filterGroup, self.uiState.currentCharacterOnly, self.timelineSearch:GetText() or "")
    local pages = max(1, math.ceil(#entries / ROWS_PER_PAGE))
    self.uiState.page = min(max(1, self.uiState.page), pages)
    local startIndex = ((self.uiState.page - 1) * ROWS_PER_PAGE) + 1

    for i, row in ipairs(self.timelineRows) do
        local entry = entries[startIndex + i - 1]
        if entry then
            row:Show()
            row.icon:SetTexture(self:GetKindIcon(entry.kind, entry))
            row.kind:SetText(self:GetKindLabel(entry.kind))
            row.title:SetText(self:GetEntryTitle(entry))
            row.meta:SetText(string.format("%s\n|cff6f7f9e%s|r", self:FormatDate(entry.ts, true), entry.charName or ""))
            row.entry = entry
            row.delete.entryId = entry.id
            row:SetScript("OnEnter", function(selfRow)
                local shownEntry = selfRow.entry
                if not shownEntry then return end
                GameTooltip:SetOwner(selfRow, "ANCHOR_RIGHT")
                GameTooltip:SetText(AD:GetEntryTitle(shownEntry), 1, 0.82, 0.4)
                local detail = AD:GetEntryDetail(shownEntry)
                if detail and detail ~= "" then GameTooltip:AddLine(detail, 1, 1, 1, true) end
                local place = shownEntry.zone or ""
                if shownEntry.subZone and shownEntry.subZone ~= "" and shownEntry.subZone ~= place then place = place .. " • " .. shownEntry.subZone end
                GameTooltip:AddLine(place, 0.55, 0.62, 0.75, true)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        else
            row:Hide()
            row.entry = nil
            row.delete.entryId = nil
        end
    end

    self.noEntriesText:SetShown(#entries == 0)
    self.pageText:SetText(self:L("PAGE", self.uiState.page, pages))
    self.prevPageButton:SetEnabled(self.uiState.page > 1)
    self.nextPageButton:SetEnabled(self.uiState.page < pages)
    self.prevPageButton:SetAlpha(self.uiState.page > 1 and 1 or 0.45)
    self.nextPageButton:SetAlpha(self.uiState.page < pages and 1 or 0.45)
    self.scopeButton.text:SetText(self.uiState.currentCharacterOnly and self:L("CURRENT_CHARACTER") or self:L("WARBAND"))
    for key, b in pairs(self.filterButtons) do setButtonActive(b, key == self.uiState.filterGroup) end
end

function AD:RefreshOverview()
    if not self.overviewPanel or not self.db then return end
    local stats = self:GetOverviewStats(self.uiState.currentCharacterOnly)
    self.overviewCards[1].value:SetText(stats.total)
    self.overviewCards[2].value:SetText(stats.today)
    self.overviewCards[3].value:SetText(stats.activeDaysCount)
    self.overviewCards[4].value:SetText(stats.characterCount)

    local oldEntries = self:GetOnThisDayEntries(4, self.uiState.currentCharacterOnly)
    for i, line in ipairs(self.onThisDayPanel.lines) do
        local entry = oldEntries[i]
        if entry then
            line:SetText(string.format("|cffffcc55%s|r\n%s\n|cff72809c%s • %s|r", self:FormatDate(entry.ts, false), self:GetEntryTitle(entry), entry.charName or "", entry.zone or ""))
        elseif i == 1 then
            line:SetText("|cff8f9bb3" .. self:L("TODAY_EMPTY") .. "|r")
        else
            line:SetText("")
        end
    end

    local kindCounts = {}
    for kind, count in pairs(stats.kinds) do kindCounts[#kindCounts + 1] = { kind = kind, count = count } end
    table.sort(kindCounts, function(a, b)
        if a.count == b.count then return AD:GetKindLabel(a.kind) < AD:GetKindLabel(b.kind) end
        return a.count > b.count
    end)
    for i, line in ipairs(self.breakdownPanel.lines) do
        local item = kindCounts[i]
        if item then
            line:SetText(string.format("|cffffcc55%4d|r   %s", item.count, self:GetKindLabel(item.kind)))
        else
            line:SetText("")
        end
    end
    if stats.mostActiveKey then
        self.breakdownPanel.footer:SetText(string.format("%s:\n|cffffcc55%s|r  (%d)", self:L("MOST_ACTIVE_CHARACTER"), self:GetCharacterDisplayName(stats.mostActiveKey), stats.mostActiveCount))
    else
        self.breakdownPanel.footer:SetText("")
    end
end

function AD:RefreshExport()
    if not self.exportPanel or not self.db then return end
    self.exportScopeButton.text:SetText(self.uiState.exportCurrent and self:L("EXPORT_CURRENT") or self:L("EXPORT_ALL"))
    if self.exportWowheadCheckbox then
        self.exportWowheadCheckbox:SetChecked(self.db.settings.htmlWowheadTooltips == true)
    end
end

function AD:RefreshSettings()
    if not self.settingsPanel or not self.db then return end
    self.minimapCheckbox:SetChecked(self.db.settings.showMinimap)
    self.toastsCheckbox:SetChecked(self.db.settings.showToasts)
    self.bossFirstCheckbox:SetChecked(self.db.settings.bossFirstOnly)
    self.mplusBestCheckbox:SetChecked(self.db.settings.mythicPlusBestOnly)
    for _, c in ipairs(self.trackingCheckboxes) do c:SetChecked(self.db.settings.tracking[c.kind]) end
    for _, b in ipairs(self.languageButtons) do setButtonActive(b, self.db.settings.language == b.value) end
end

function AD:CreateToast()
    if self.toast then return end
    local toast = CreateFrame("Frame", "AzerothDiaryToast", UIParent, "BackdropTemplate")
    toast:SetSize(470, 72)
    toast:SetPoint("TOP", UIParent, "TOP", 0, -155)
    toast:SetFrameStrata("DIALOG")
    setBackdrop(toast, 0.035, 0.05, 0.085, 0.98, 1)
    toast:Hide()
    toast.icon = toast:CreateTexture(nil, "ARTWORK")
    toast.icon:SetSize(46, 46)
    toast.icon:SetPoint("LEFT", 12, 0)
    toast.kind = toast:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    toast.kind:SetPoint("TOPLEFT", toast.icon, "TOPRIGHT", 12, -5)
    toast.kind:SetTextColor(0.95, 0.72, 0.32)
    toast.title = toast:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    toast.title:SetPoint("TOPLEFT", toast.kind, "BOTTOMLEFT", 0, -5)
    toast.title:SetPoint("RIGHT", -12, 0)
    toast.title:SetJustifyH("LEFT")

    local group = toast:CreateAnimationGroup()
    local wait = group:CreateAnimation("Alpha")
    wait:SetFromAlpha(1)
    wait:SetToAlpha(1)
    wait:SetDuration(3.2)
    wait:SetOrder(1)
    local fade = group:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetDuration(0.65)
    fade:SetOrder(2)
    group:SetScript("OnFinished", function() toast:Hide(); toast:SetAlpha(1) end)
    toast.anim = group
    self.toast = toast
end

function AD:ShowToast(entry)
    if not entry then return end
    if not self.toast then self:CreateToast() end
    self.toast.anim:Stop()
    self.toast:SetAlpha(1)
    self.toast.icon:SetTexture(self:GetKindIcon(entry.kind, entry))
    self.toast.kind:SetText(self:GetKindLabel(entry.kind))
    self.toast.title:SetText(self:GetEntryTitle(entry))
    self.toast:Show()
    self.toast.anim:Play()
end

local MINIMAP_BROKER_NAME = "AzerothDiary"

function AD:SetupMinimapButton()
    if self.minimapRegistered then
        self:UpdateMinimapVisibility()
        return
    end

    local LDB = LibStub and LibStub:GetLibrary("LibDataBroker-1.1", true)
    local DBIcon = LibStub and LibStub:GetLibrary("LibDBIcon-1.0", true)
    if not LDB or not DBIcon then
        print("|cffff5555Azeroth Diary:|r Minimap libraries could not be loaded.")
        return
    end

    local dataObject = LDB:GetDataObjectByName(MINIMAP_BROKER_NAME)
    if not dataObject then
        dataObject = LDB:NewDataObject(MINIMAP_BROKER_NAME, {
            type = "launcher",
            text = "Azeroth Diary",
            label = "Azeroth Diary",
            icon = "Interface\\Icons\\INV_Misc_Book_09",
            OnClick = function(_, mouseButton)
                if mouseButton == "RightButton" then
                    AD:ShowWindow("add")
                elseif IsShiftKeyDown() then
                    AD:ShowWindow("export")
                else
                    AD:ToggleWindow()
                end
            end,
            OnTooltipShow = function(tooltip)
                tooltip:AddLine(AD:L("ADDON_TITLE"), 1, 0.82, 0.4)
                tooltip:AddLine(AD:L("MINIMAP_LEFT"), 1, 1, 1)
                tooltip:AddLine(AD:L("MINIMAP_RIGHT"), 1, 1, 1)
                tooltip:AddLine(AD:L("MINIMAP_SHIFT"), 0.7, 0.75, 0.85)
            end,
        })
    end

    self.minimapDataObject = dataObject
    self.minimapIcon = DBIcon

    if not DBIcon:IsRegistered(MINIMAP_BROKER_NAME) then
        DBIcon:Register(MINIMAP_BROKER_NAME, dataObject, self.db.minimap)
    else
        DBIcon:Refresh(MINIMAP_BROKER_NAME, self.db.minimap)
    end

    self.minimapButton = DBIcon:GetMinimapButton(MINIMAP_BROKER_NAME)
    self.minimapRegistered = true
    self:UpdateMinimapVisibility()
end

function AD:UpdateMinimapVisibility()
    if not self.db then return end

    self.db.minimap = self.db.minimap or { hide = false, minimapPos = 225 }
    local show = self.db.settings.showMinimap ~= false
    self.db.minimap.hide = not show

    if not self.minimapIcon then return end
    if show then
        self.minimapIcon:Show(MINIMAP_BROKER_NAME)
    else
        self.minimapIcon:Hide(MINIMAP_BROKER_NAME)
    end
end
