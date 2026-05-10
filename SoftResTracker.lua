-- SoftRes Tracker v1.0
-- Features: Whisper -sr, 1SR/2SR limit, Multi-item whisper, Same-item multiple reservations,
--           Unique player count, Drop-down reset, Item icons, Per-item clear buttons, Scrollable popups
--
-- UI redesigned with fresh layout and navy/steel-blue color scheme.
-- Logic is identical to original; only visual structure has changed.

-- =========================
-- Saved Variables
-- =========================
SoftResTrackerDB = SoftResTrackerDB or {
    mode         = 1,
    reserves     = {},
    framePos     = nil,
    frameVisible = false,
    minimapPos   = 225,
    locked       = false,
}

-- Forward declarations so button OnClick scripts defined before the
-- function bodies can reference them safely at call time.
local UpdateBoard
local UpdateButtonStates
local SoftResTracker_ShowExportWindow

-- =========================
-- Debounce Table
-- =========================
local lastWhisperTime = {}

-- =========================
-- Addon Sync
-- =========================
local ADDON_PREFIX = "SoftResTracker"

local function BroadcastReserve(itemID, playerName)
    if GetNumRaidMembers() > 0 then
        SendAddonMessage(ADDON_PREFIX, "ADD:"..itemID..":"..playerName, "RAID")
    end
end

local function BroadcastRemove(itemID, playerName)
    if GetNumRaidMembers() > 0 then
        SendAddonMessage(ADDON_PREFIX, "REM:"..itemID..":"..playerName, "RAID")
    end
end

local function BroadcastReset()
    if GetNumRaidMembers() > 0 then
        SendAddonMessage(ADDON_PREFIX, "RESET", "RAID")
    end
end

local function BroadcastFullSync()
    if GetNumRaidMembers() > 0 then
        for itemID, players in pairs(SoftResTrackerDB.reserves) do
            for _, p in ipairs(players) do
                SendAddonMessage(ADDON_PREFIX, "ADD:"..itemID..":"..p, "RAID")
            end
        end
    end
end

-- =========================
-- Utility: Class Coloring
-- =========================
local function ColorizePlayer(name)
    local _, class = UnitClass(name)
    if class and RAID_CLASS_COLORS[class] then
        local c = RAID_CLASS_COLORS[class]
        return string.format("|cff%02x%02x%02x%s|r",
            c.r * 255, c.g * 255, c.b * 255, name)
    end
    return name
end

-- =========================
-- Check if Player is in Group/Raid
-- =========================
local function IsPlayerInGroup(name)
    name = name:lower()
    if GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            local n = GetRaidRosterInfo(i)
            if n then n = string.match(n, "^[^-]+") end
            if n and n:lower() == name then return true end
        end
    elseif GetNumPartyMembers() > 0 then
        for i = 1, GetNumPartyMembers() do
            local unit = "party"..i
            local n = UnitName(unit)
            if n and n:lower() == name then return true end
        end
        local me = UnitName("player")
        if me and me:lower() == name then return true end
    else
        local me = UnitName("player")
        if me and me:lower() == name then return true end
    end
    return false
end

-- ============================================================
-- MAIN FRAME
-- Fresh layout:
--   ┌──────────────────────────────────────┐
--   │ ≡ SoftRes Tracker         [1SR][2SR][✕] │  header (30px) — draggable
--   ├──────────────────────────────────────┤
--   │ [Reserves][Missing SR]  [Lock][Import]│  controls (26px)
--   ├──────────────────────────────────────┤
--   │ 🔍 [Search..................][X]     │  search (22px, Reserves tab only)
--   ├──────────────────────────────────────┤
--   │  scrollable content area             │
--   ├──────────────────────────────────────┤
--   │ [Loot][How to SR][Reset][Announce]   │  footer (28px)
--   └──────────────────────────────────────┘
-- ============================================================
local frame = CreateFrame("Frame", "SoftResTrackerFrame", UIParent, "SRTBaseFrameTemplate")
frame:SetSize(310, 400)
frame:SetPoint("CENTER", 0, -20)
frame:SetBackdropColor(0.04, 0.07, 0.11, 0.93)
frame:EnableMouse(true)

-- ── Header strip (visual only — gives the title bar a distinct background) ──
local headerBG = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
headerBG:SetPoint("TOPLEFT",  frame, "TOPLEFT",   5,  -5)
headerBG:SetPoint("TOPRIGHT", frame, "TOPRIGHT",  -5, -5)
headerBG:SetHeight(30)
headerBG:SetTexture(0.07, 0.13, 0.20, 0.95)

-- ── Separator line between header and controls ──
local headerSep = frame:CreateTexture(nil, "ARTWORK")
headerSep:SetPoint("TOPLEFT",  frame, "TOPLEFT",  5, -35)
headerSep:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -35)
headerSep:SetHeight(1)
headerSep:SetTexture(0.25, 0.55, 0.82, 0.60)

-- ── Title text ──
local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("LEFT", frame, "TOPLEFT", 14, -20)
title:SetText("|cff4dc4f7SoftRes Tracker|r")

-- ── Drag zone: transparent frame covering just the header strip ──
local headerDrag = CreateFrame("Frame", nil, frame)
headerDrag:SetPoint("TOPLEFT",  frame, "TOPLEFT",   5,   -5)
headerDrag:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -170, -5)
headerDrag:SetHeight(30)
headerDrag:EnableMouse(true)
headerDrag:RegisterForDrag("LeftButton")
headerDrag:SetScript("OnDragStart", function() frame:StartMoving() end)
headerDrag:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
    local point, _, relativePoint, x, y = frame:GetPoint()
    SoftResTrackerDB.framePos = { point = point, relativePoint = relativePoint, x = x, y = y }
end)

-- ── Close button (top-right of header) ──
local btnClose = CreateFrame("Button", "SoftResTrackerCloseBtn", frame, "SRTSmallButtonTemplate")
btnClose:SetSize(22, 20)
btnClose:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -7, -9)
btnClose:SetText("X")
btnClose:SetScript("OnClick", function()
    frame:Hide()
    SoftResTrackerDB.frameVisible = false
end)

-- ── 1SR / 2SR buttons — wider so text isn't clipped ──
local btn2SR = CreateFrame("Button", "SoftResTracker2SRButton", frame, "SRTSmallButtonTemplate")
btn2SR:SetSize(36, 20)
btn2SR:SetPoint("RIGHT", btnClose, "LEFT", -3, 0)
btn2SR:SetText("2SR")
btn2SR:SetScript("OnClick", function()
    SoftResTrackerDB.mode = 2
    print("SoftRes Tracker: Set mode to 2 SR")
    UpdateBoard()
end)

local btn1SR = CreateFrame("Button", "SoftResTracker1SRButton", frame, "SRTSmallButtonTemplate")
btn1SR:SetSize(36, 20)
btn1SR:SetPoint("RIGHT", btn2SR, "LEFT", -3, 0)
btn1SR:SetText("1SR")
btn1SR:SetScript("OnClick", function()
    SoftResTrackerDB.mode = 1
    print("SoftRes Tracker: Set mode to 1 SR")
    UpdateBoard()
end)

-- ── Import CSV button — in the header row, left of 1SR ──
local importFrame, importBox   -- forward declarations
local btnImport = CreateFrame("Button", "SoftResTrackerImportButton", frame, "SRTSmallButtonTemplate")
btnImport:SetSize(54, 20)
btnImport:SetPoint("RIGHT", btn1SR, "LEFT", -3, 0)
btnImport:SetText("Import")
btnImport:SetScript("OnClick", function()
    if importFrame:IsShown() then
        importFrame:Hide()
    else
        importFrame:Show()
        importBox:SetFocus()
    end
end)

-- ============================================================
-- CONTROLS ROW — tabs + Lock (below header)
-- ============================================================

local activeTab = "reserves"

local tabReserves = CreateFrame("Button", "SoftResTrackerTabReserves", frame, "SRTTabTemplate")
tabReserves:SetSize(112, 22)
tabReserves:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -38)
tabReserves:SetText("Reserves")

local tabList = CreateFrame("Button", "SoftResTrackerTabList", frame, "SRTTabTemplate")
tabList:SetSize(112, 22)
tabList:SetPoint("LEFT", tabReserves, "RIGHT", 2, 0)
tabList:SetText("Missing SR")

-- ── Lock button (right side of controls row) ──
local btnLock = CreateFrame("Button", "SoftResTrackerLockButton", frame, "SRTSmallButtonTemplate")
btnLock:SetSize(56, 20)
btnLock:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -40)
btnLock:SetText("Lock")

local function UpdateLockButton()
    if SoftResTrackerDB.locked then
        btnLock:SetText("|cffff5555Unlock|r")
    else
        btnLock:SetText("Lock")
    end
end

btnLock:SetScript("OnClick", function()
    SoftResTrackerDB.locked = not SoftResTrackerDB.locked
    UpdateLockButton()
    if SoftResTrackerDB.locked then
        print("SoftRes Tracker: Reservations are now |cffff5555locked|r.")
    else
        print("SoftRes Tracker: Reservations are now |cff44ff44open|r.")
    end
end)

-- ── Separator line between controls and search/content ──
local controlSep = frame:CreateTexture(nil, "ARTWORK")
controlSep:SetPoint("TOPLEFT",  frame, "TOPLEFT",  5, -62)
controlSep:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -62)
controlSep:SetHeight(1)
controlSep:SetTexture(0.15, 0.35, 0.55, 0.45)

-- ============================================================
-- SEARCH ROW
-- ============================================================
local searchBox = CreateFrame("EditBox", "SoftResTrackerSearchBox", frame, "SRTEditBoxTemplate")
searchBox:SetSize(215, 20)
searchBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -68)
searchBox:SetAutoFocus(false)
searchBox:SetMaxLetters(50)

local searchPlaceholder = frame:CreateFontString(nil, "OVERLAY", "SRTMutedFontTemplate")
searchPlaceholder:SetPoint("LEFT", searchBox, "LEFT", 5, 0)
searchPlaceholder:SetText("Search item or player...")

searchBox:SetScript("OnEditFocusGained", function(self)
    searchPlaceholder:Hide()
    self:HighlightText()
end)
searchBox:SetScript("OnEditFocusLost", function(self)
    if self:GetText() == "" then searchPlaceholder:Show() end
    self:HighlightText(0, 0)
end)

-- Hook shift-click item links into search box when focused
local origInsertLink = ChatEdit_InsertLink
ChatEdit_InsertLink = function(link)
    if searchBox and searchBox:HasFocus() then
        local itemName = link:match("%[(.-)%]")
        if itemName then
            searchBox:SetText(itemName)
            searchPlaceholder:Hide()
            UpdateBoard()
            return true
        end
    end
    return origInsertLink(link)
end

searchBox:SetScript("OnEscapePressed", function(self)
    self:SetText("")
    self:ClearFocus()
    if searchPlaceholder then searchPlaceholder:Show() end
    UpdateBoard()
end)
searchBox:SetScript("OnTextChanged", function(self)
    if self:GetText() == "" then
        searchPlaceholder:Show()
    else
        searchPlaceholder:Hide()
    end
    UpdateBoard()
end)

local searchClear = CreateFrame("Button", nil, frame, "SRTSmallButtonTemplate")
searchClear:SetSize(22, 20)
searchClear:SetText("X")
searchClear:SetPoint("LEFT", searchBox, "RIGHT", 4, 0)
searchClear:SetScript("OnClick", function()
    searchBox:SetText("")
    searchBox:ClearFocus()
    searchPlaceholder:Show()
    UpdateBoard()
end)

-- ── Search separator ──
local searchSep = frame:CreateTexture(nil, "ARTWORK")
searchSep:SetPoint("TOPLEFT",  frame, "TOPLEFT",  5, -91)
searchSep:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -91)
searchSep:SetHeight(1)
searchSep:SetTexture(0.15, 0.35, 0.55, 0.30)

-- ============================================================
-- FOOTER ACTION BUTTONS (bottom of frame)
-- ============================================================

-- ── Loot button ──
local btnLoot = CreateFrame("Button", "SoftResTrackerLootButton", frame, "SRTSmallButtonTemplate")
btnLoot:SetSize(50, 22)
btnLoot:SetText("Loot")
btnLoot:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 8)
btnLoot:SetScript("OnClick", function()
    local lines = {}
    for itemID, players in pairs(SoftResTrackerDB.reserves) do
        local itemName = GetItemInfo(itemID) or ("Item "..itemID)
        table.insert(lines, itemName.." ("..table.concat(players, ", ")..")")
    end
    if #lines == 0 then
        print("SoftRes Tracker: Nothing reserved yet.")
        return
    end
    local messages = {}
    local current = ""
    for _, line in ipairs(lines) do
        local sep = (current == "") and "" or ", "
        local candidate = current..sep..line
        if #candidate <= 255 then
            current = candidate
        else
            if current ~= "" then table.insert(messages, current) end
            current = (#line > 255) and line:sub(1, 255) or line
        end
    end
    if current ~= "" then table.insert(messages, current) end
    for _, msg in ipairs(messages) do
        SendChatMessage(msg, "RAID", nil, nil)
    end
end)

-- ── How to SR button ──
local btnSR = CreateFrame("Button", "SoftResTrackerSRButton", frame, "SRTSmallButtonTemplate")
btnSR:SetSize(70, 22)
btnSR:SetText("How to SR")
btnSR:SetPoint("LEFT", btnLoot, "RIGHT", 4, 0)
btnSR:SetScript("OnClick", function()
    SendChatMessage("To soft reserve an item, whisper me: -sr [shift-click item]", "RAID", nil, nil)
    SendChatMessage("To check your SRs, whisper me: -mysr", "RAID", nil, nil)
end)

-- ── Reset button ──
local btnReset = CreateFrame("Button", "SoftResTrackerResetButton", frame, "SRTDangerButtonTemplate")
btnReset:SetSize(50, 22)
btnReset:SetText("Reset")
btnReset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)

-- ── Announce Missing (shown only on Missing SR tab) ──
local btnAnnounce = CreateFrame("Button", "SoftResTrackerAnnounceButton", frame, "SRTButtonTemplate")
btnAnnounce:SetSize(120, 22)
btnAnnounce:SetText("Announce Missing")
btnAnnounce:SetPoint("RIGHT", btnReset, "LEFT", -4, 0)
btnAnnounce:Hide()

-- ── Export button (shown only on Reserves tab) ──
local btnExport = CreateFrame("Button", "SoftResTrackerExportButton", frame, "SRTSmallButtonTemplate")
btnExport:SetSize(54, 22)
btnExport:SetText("Export")
btnExport:SetPoint("RIGHT", btnReset, "LEFT", -4, 0)
btnExport:SetScript("OnClick", function()
    SoftResTracker_ShowExportWindow()
end)
btnAnnounce:SetScript("OnClick", function()
    local reservedCount = {}
    for _, players in pairs(SoftResTrackerDB.reserves) do
        for _, p in ipairs(players) do
            local key = p:lower()
            reservedCount[key] = (reservedCount[key] or 0) + 1
        end
    end
    local missing = {}
    if GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            local rName = GetRaidRosterInfo(i)
            if rName then rName = rName:match("^[^-]+") end
            if rName then
                local count = reservedCount[rName:lower()] or 0
                local needed = SoftResTrackerDB.mode - count
                if needed > 0 then table.insert(missing, rName.."(-"..needed..")") end
            end
        end
    elseif GetNumPartyMembers() > 0 then
        for i = 1, GetNumPartyMembers() do
            local rName = UnitName("party"..i)
            if rName then
                local count = reservedCount[rName:lower()] or 0
                local needed = SoftResTrackerDB.mode - count
                if needed > 0 then table.insert(missing, rName.."(-"..needed..")") end
            end
        end
        local me = UnitName("player")
        if me then
            local count = reservedCount[me:lower()] or 0
            local needed = SoftResTrackerDB.mode - count
            if needed > 0 then table.insert(missing, me.."(-"..needed..")") end
        end
    else
        print("SoftRes Tracker: Not in a group.")
        return
    end
    if #missing == 0 then
        SendChatMessage("Everyone has used all their SRs!", "RAID_WARNING", nil, nil)
    else
        local header  = "Missing SR(s): "
        local fullMsg = header..table.concat(missing, ", ")
        if #fullMsg <= 255 then
            SendChatMessage(fullMsg, "RAID_WARNING", nil, nil)
        else
            SendChatMessage(header, "RAID_WARNING", nil, nil)
            local current = ""
            for _, p in ipairs(missing) do
                local sep = (current == "") and "" or ", "
                local candidate = current..sep..p
                if #candidate <= 255 then
                    current = candidate
                else
                    SendChatMessage(current, "RAID_WARNING", nil, nil)
                    current = p
                end
            end
            if current ~= "" then SendChatMessage(current, "RAID_WARNING", nil, nil) end
        end
    end
end)

-- ── Footer separator ──
local footerSep = frame:CreateTexture(nil, "ARTWORK")
footerSep:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT",  5, 32)
footerSep:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -5, 32)
footerSep:SetHeight(1)
footerSep:SetTexture(0.15, 0.35, 0.55, 0.45)

-- ============================================================
-- RESET CONFIRM POPUP
-- ============================================================
local confirmFrame = CreateFrame("Frame", "SoftResTrackerConfirmFrame", UIParent, "SRTBaseFrameTemplate")
confirmFrame:SetSize(230, 95)
confirmFrame:SetPoint("CENTER")
confirmFrame:SetFrameStrata("DIALOG")
confirmFrame:SetBackdropColor(0.04, 0.07, 0.11, 0.97)
confirmFrame:Hide()

local confirmText = confirmFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
confirmText:SetPoint("TOP", confirmFrame, "TOP", 0, -20)
confirmText:SetText("|cffff9955Clear all reservations?|r")

local btnConfirmYes = CreateFrame("Button", nil, confirmFrame, "SRTDangerButtonTemplate")
btnConfirmYes:SetSize(90, 24)
btnConfirmYes:SetText("Yes, Reset")
btnConfirmYes:SetPoint("BOTTOMLEFT", confirmFrame, "BOTTOMLEFT", 14, 12)
btnConfirmYes:SetScript("OnClick", function()
    SoftResTrackerDB.reserves = {}
    BroadcastReset()
    print("SoftRes Tracker: All reservations cleared")
    UpdateBoard()
    confirmFrame:Hide()
end)

local btnConfirmNo = CreateFrame("Button", nil, confirmFrame, "SRTButtonTemplate")
btnConfirmNo:SetSize(80, 24)
btnConfirmNo:SetText("Cancel")
btnConfirmNo:SetPoint("BOTTOMRIGHT", confirmFrame, "BOTTOMRIGHT", -14, 12)
btnConfirmNo:SetScript("OnClick", function()
    confirmFrame:Hide()
end)

btnReset:SetScript("OnClick", function()
    if confirmFrame:IsShown() then
        confirmFrame:Hide()
    else
        confirmFrame:Show()
    end
end)

-- ============================================================
-- SCROLLFRAME — Reserves tab content
-- ============================================================
local scrollFrame = CreateFrame("ScrollFrame", "SoftResTrackerScrollFrame", frame, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT",     8,  -94)
scrollFrame:SetPoint("BOTTOMRIGHT", -28, 34)
scrollFrame:EnableMouse(true)
scrollFrame:SetScript("OnMouseDown", function()
    if searchBox then searchBox:ClearFocus() end
end)

local content = CreateFrame("Frame", nil, scrollFrame)
content:SetSize(1, 1)
content:EnableMouse(true)
content:SetScript("OnMouseDown", function()
    if searchBox then searchBox:ClearFocus() end
end)
scrollFrame:SetScrollChild(content)

-- ============================================================
-- LIST PANEL — Missing SR tab content
-- ============================================================
local listPanel = CreateFrame("Frame", "SoftResTrackerListPanel", frame)
listPanel:SetPoint("TOPLEFT",     8,  -66)
listPanel:SetPoint("BOTTOMRIGHT", -8,  34)
listPanel:EnableMouse(false)
listPanel:Hide()

local myResScroll = CreateFrame("ScrollFrame", "SoftResTrackerMyResScroll", listPanel, "UIPanelScrollFrameTemplate")
myResScroll:SetPoint("TOPLEFT",     listPanel, "TOPLEFT",     0,   0)
myResScroll:SetPoint("BOTTOMRIGHT", listPanel, "BOTTOMRIGHT", -20, 0)

local myResContent = CreateFrame("Frame", nil, myResScroll)
myResContent:SetSize(1, 1)
myResScroll:SetScrollChild(myResContent)

local myResContainer = nil

function UpdateMyReserves()
    if myResContainer then
        myResContainer:Hide()
        myResContainer:SetParent(nil)
        myResContainer = nil
    end

    myResContainer = CreateFrame("Frame", nil, myResContent)
    myResContainer:SetSize(265, 1)
    myResContainer:SetPoint("TOPLEFT", 0, 0)

    local reservedCount = {}
    for _, players in pairs(SoftResTrackerDB.reserves) do
        for _, p in ipairs(players) do
            local key = p:lower()
            reservedCount[key] = (reservedCount[key] or 0) + 1
        end
    end

    local missing = {}
    if GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            local rName = GetRaidRosterInfo(i)
            if rName then rName = rName:match("^[^-]+") end
            if rName then
                local count  = reservedCount[rName:lower()] or 0
                local needed = SoftResTrackerDB.mode - count
                if needed > 0 then table.insert(missing, { name = rName, missing = needed }) end
            end
        end
    elseif GetNumPartyMembers() > 0 then
        for i = 1, GetNumPartyMembers() do
            local rName = UnitName("party"..i)
            if rName then
                local count  = reservedCount[rName:lower()] or 0
                local needed = SoftResTrackerDB.mode - count
                if needed > 0 then table.insert(missing, { name = rName, missing = needed }) end
            end
        end
        local me = UnitName("player")
        if me then
            local count  = reservedCount[me:lower()] or 0
            local needed = SoftResTrackerDB.mode - count
            if needed > 0 then table.insert(missing, { name = me, missing = needed }) end
        end
    end

    local yOffset = -5

    if #missing == 0 then
        local noText = myResContainer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        noText:SetPoint("TOP", myResContainer, "TOP", 0, -20)
        noText:SetJustifyH("CENTER")
        if GetNumRaidMembers() == 0 and GetNumPartyMembers() == 0 then
            noText:SetText("|cff888888No group found.|r")
        else
            noText:SetText("|cff44ff44Everyone has used all their SR(s).|r")
        end
        myResContainer:SetHeight(60)
    else
        local headerText = myResContainer:CreateFontString(nil, "OVERLAY", "SRTAccentFontTemplate")
        headerText:SetPoint("TOPLEFT", myResContainer, "TOPLEFT", 5, yOffset)
        headerText:SetWidth(255)
        headerText:SetJustifyH("CENTER")
        headerText:SetText(#missing.." player(s) missing SR(s)")
        yOffset = yOffset - 28

        for i, entry in ipairs(missing) do
            local rowFrame = CreateFrame("Frame", nil, myResContainer)
            rowFrame:SetSize(255, 22)
            rowFrame:SetPoint("TOPLEFT", 5, yOffset)

            local bg = rowFrame:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            if i % 2 == 0 then
                bg:SetTexture(0.10, 0.18, 0.26, 0.40)
            else
                bg:SetTexture(0.06, 0.10, 0.15, 0.25)
            end

            local nameText = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            nameText:SetPoint("LEFT",  rowFrame, "LEFT",   8, 0)
            nameText:SetPoint("RIGHT", rowFrame, "CENTER", 0, 0)
            nameText:SetJustifyH("LEFT")
            nameText:SetText(entry.name)

            local missingText = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            missingText:SetPoint("LEFT",  rowFrame, "CENTER", 0, 0)
            missingText:SetPoint("RIGHT", rowFrame, "RIGHT", -8, 0)
            missingText:SetJustifyH("RIGHT")
            missingText:SetText("|cffff5555-"..entry.missing.." SR|r")

            yOffset = yOffset - 23
        end
        myResContainer:SetHeight(-yOffset + 10)
    end

    myResContent:SetHeight(myResContainer:GetHeight() + 10)
end

-- ============================================================
-- TAB SWITCHING
-- ============================================================
local function SetTabActive(tab, btn)
    -- Brighten the accent line on the active tab
    local accentLine = _G[btn:GetName().."AccentLine"]
    if accentLine then
        accentLine:SetTexture(0.28, 0.75, 1.00, 1.0)
    end
    btn:SetNormalFontObject("GameFontHighlightSmall")
    btn:Disable()
end

local function SetTabInactive(btn)
    local accentLine = _G[btn:GetName().."AccentLine"]
    if accentLine then
        accentLine:SetTexture(0.20, 0.48, 0.72, 0.45)
    end
    btn:SetNormalFontObject("GameFontNormalSmall")
    btn:Enable()
end

local function SwitchTab(tab)
    activeTab = tab
    if tab == "reserves" then
        scrollFrame:Show()
        listPanel:Hide()
        SetTabActive("reserves", tabReserves)
        SetTabInactive(tabList)
        searchBox:Show()
        if searchBox:GetText() == "" then searchPlaceholder:Show() else searchPlaceholder:Hide() end
        searchClear:Show()
        btnAnnounce:Hide()
        btnExport:Show()
    else
        scrollFrame:Hide()
        listPanel:Show()
        SetTabInactive(tabReserves)
        SetTabActive("list", tabList)
        searchBox:Hide()
        searchPlaceholder:Hide()
        searchClear:Hide()
        UpdateMyReserves()
        btnAnnounce:Show()
        btnExport:Hide()
    end
end

tabReserves:SetScript("OnClick", function() SwitchTab("reserves") end)
tabList:SetScript("OnClick",     function() SwitchTab("list")     end)
SwitchTab("reserves")

-- ============================================================
-- BUTTON PERMISSION CHECK
-- ============================================================
local function IsLeaderOrSolo()
    if GetNumRaidMembers() > 0 then
        return UnitIsRaidOfficer("player") or UnitIsPartyLeader("player")
    elseif GetNumPartyMembers() > 0 then
        return UnitIsPartyLeader("player")
    else
        return true
    end
end

UpdateButtonStates = function()
    local allowed = IsLeaderOrSolo()
    if allowed then
        btn1SR:Show()
        btn2SR:Show()
        btnReset:Show()
        btnLock:Show()
    else
        btn1SR:Hide()
        btn2SR:Hide()
        btnReset:Hide()
        btnLock:Hide()
    end
end

-- ============================================================
-- GET PLAYER SR COUNT
-- ============================================================
local function GetPlayerSRCount(name)
    local count = 0
    for _, players in pairs(SoftResTrackerDB.reserves) do
        for _, p in ipairs(players) do
            if p:lower() == name:lower() then
                count = count + 1
            end
        end
    end
    return count
end

-- ============================================================
-- POPUP: Item Reservations (scrollable, per-item)
-- ============================================================
-- Lua-side popup registry — never touches _G for these frames
local itemPopups = {}
local popupScrollCounter = 0

local function ShowItemPlayers(itemID, itemName)
    local players = SoftResTrackerDB.reserves[itemID] or {}
    if #players == 0 then
        print("SoftRes Tracker: No players have reserved "..(itemName or itemID))
        return
    end

    -- If popup is already open for this item, just bring it to front
    if itemPopups[itemID] and itemPopups[itemID]:IsShown() then
        itemPopups[itemID]:Raise()
        return
    end

    local maxH   = 300
    local itemH  = #players * 20 + 50
    local popupH = math.min(itemH, maxH)

    -- nil name — no global registration, no $parent concat risk
    local popup = CreateFrame("Frame", nil, UIParent, "SRTBaseFrameTemplate")
    itemPopups[itemID] = popup
    popup:SetSize(230, popupH)
    popup:SetPoint("CENTER")
    popup:SetFrameStrata("DIALOG")
    popup:SetBackdropColor(0.04, 0.07, 0.11, 0.96)
    popup:Show()

    -- Header strip
    local popupHeaderBG = popup:CreateTexture(nil, "BACKGROUND", nil, 1)
    popupHeaderBG:SetPoint("TOPLEFT",  popup, "TOPLEFT",   5,  -5)
    popupHeaderBG:SetPoint("TOPRIGHT", popup, "TOPRIGHT",  -5, -5)
    popupHeaderBG:SetHeight(24)
    popupHeaderBG:SetTexture(0.07, 0.13, 0.20, 0.95)

    local header = popup:CreateFontString(nil, "OVERLAY", "SRTHeaderFontTemplate")
    header:SetPoint("LEFT",  popup, "TOPLEFT",  10, -17)
    header:SetPoint("RIGHT", popup, "TOPRIGHT", -60, -17)
    header:SetJustifyH("LEFT")
    header:SetText(itemName or ("Item "..itemID))

    local closeBtn = CreateFrame("Button", nil, popup, "SRTSmallButtonTemplate")
    closeBtn:SetSize(44, 18)
    closeBtn:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -6, -8)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function()
        popup:Hide()
        itemPopups[itemID] = nil
    end)

    -- ScrollFrame needs a unique global name for UIPanelScrollFrameTemplate internals
    popupScrollCounter = popupScrollCounter + 1
    local scroll = CreateFrame("ScrollFrame", "SRTPopupScroll"..popupScrollCounter, popup, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     popup, "TOPLEFT",      6,  -32)
    scroll:SetPoint("BOTTOMRIGHT", popup, "BOTTOMRIGHT", -26,   6)

    local sc = CreateFrame("Frame", nil, scroll)
    sc:SetSize(1, #players * 20)
    scroll:SetScrollChild(sc)

    local yOff = 0
    for _, player in ipairs(players) do
        -- Named button so SRTButtonTemplate $parent children resolve safely
        popupScrollCounter = popupScrollCounter + 1
        local pBtn = CreateFrame("Button", "SRTPopupBtn"..popupScrollCounter, sc, "UIPanelButtonTemplate")
        pBtn:SetSize(180, 18)
        pBtn:SetPoint("TOPLEFT", 5, -yOff)
        pBtn:SetText(player)
        pBtn:SetNormalFontObject("GameFontNormalSmall")
        pBtn:SetHighlightFontObject("GameFontHighlightSmall")
        pBtn:SetScript("OnClick", function()
            local list = SoftResTrackerDB.reserves[itemID]
            if list then
                for i = 1, #list do
                    if list[i]:lower() == player:lower() then
                        table.remove(list, i)
                        break
                    end
                end
                if #list == 0 then SoftResTrackerDB.reserves[itemID] = nil end
            end
            BroadcastRemove(itemID, player)
            print("SoftRes Tracker: Removed "..player.." from "..(itemName or itemID))
            UpdateBoard()
            popup:Hide()
            itemPopups[itemID] = nil
        end)
        yOff = yOff + 20
    end
end

-- ============================================================
-- UPDATE BOARD (Reserves tab)
-- ============================================================
UpdateBoard = function()
    for _, child in ipairs({ content:GetChildren() }) do
        child:Hide()
        child:SetParent(UIParent)  -- avoid nil-parent errors on scripted frames in 3.3.5a
    end
    content.buttons = {}

    local searchText = searchBox and searchBox:GetText():lower() or ""

    -- Count unique players
    local playersSet = {}
    for _, players in pairs(SoftResTrackerDB.reserves) do
        for _, p in ipairs(players) do playersSet[p] = true end
    end
    local totalPlayers = 0
    for _ in pairs(playersSet) do totalPlayers = totalPlayers + 1 end

    local yOffset = -5

    -- Unique player count header
    local headerFrame = CreateFrame("Frame", nil, content)
    headerFrame:SetSize(265, 22)
    headerFrame:SetPoint("TOPLEFT", 4, yOffset)

    local header = headerFrame:CreateFontString(nil, "OVERLAY", "SRTHeaderFontTemplate")
    header:SetPoint("LEFT", headerFrame, "LEFT", 0, 0)
    header:SetText("Unique Players: ".."|cffffcc00"..totalPlayers.."|r")
    yOffset = yOffset - 28

    local stripeToggle = true
    for itemID, players in pairs(SoftResTrackerDB.reserves) do
        local itemName, _, _, _, _, _, _, _, _, itemIcon = GetItemInfo(itemID)
        local icon = itemIcon or "Interface\\Icons\\INV_Misc_QuestionMark"

        -- Search filter
        local show = true
        if searchText ~= "" then
            local nameMatch   = itemName and itemName:lower():find(searchText, 1, true)
            local playerMatch = false
            for _, p in ipairs(players) do
                if p:lower():find(searchText, 1, true) then
                    playerMatch = true
                    break
                end
            end
            if not nameMatch and not playerMatch then show = false end
        end

        if show then
            local frameHeight = 22 + (#players * 17)
            local itemFrame   = CreateFrame("Frame", nil, content)
            itemFrame:SetSize(265, frameHeight)
            itemFrame:SetPoint("TOPLEFT", 4, yOffset)

            -- Alternating row background
            local bg = itemFrame:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            if stripeToggle then
                bg:SetTexture(0.10, 0.18, 0.26, 0.35)
            else
                bg:SetTexture(0.05, 0.09, 0.13, 0.20)
            end
            stripeToggle = not stripeToggle

            -- Item icon
            local iconTex = itemFrame:CreateTexture(nil, "ARTWORK")
            iconTex:SetSize(16, 16)
            iconTex:SetPoint("TOPLEFT", 5, -3)
            iconTex:SetTexture(icon)

            -- Item name
            local itemText = itemFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            itemText:SetPoint("LEFT",  iconTex,    "RIGHT",    5,  0)
            itemText:SetPoint("RIGHT", itemFrame, "TOPRIGHT", -58, -3)
            itemText:SetJustifyH("LEFT")
            itemText:SetText(itemName or ("Item "..itemID))

            -- Tooltip trigger over the icon + name strip
            local tooltipBtn = CreateFrame("Frame", nil, itemFrame)
            tooltipBtn:SetPoint("TOPLEFT",  itemFrame, "TOPLEFT",  0,    0)
            tooltipBtn:SetPoint("BOTTOMRIGHT", itemFrame, "TOPRIGHT", 0, -22)
            tooltipBtn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink("item:"..itemID)
                GameTooltip:Show()
            end)
            tooltipBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

            -- Player list
            local playerY = -22
            for _, player in ipairs(players) do
                local playerText = itemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                playerText:SetPoint("TOPLEFT", 10, playerY)
                playerText:SetText("  · "..ColorizePlayer(player))
                playerY = playerY - 17
            end

            -- View/Remove button
            local itemBtn = CreateFrame("Button", nil, itemFrame, "SRTSmallButtonTemplate")
            itemBtn:SetSize(50, 18)
            itemBtn:SetPoint("TOPRIGHT", itemFrame, "TOPRIGHT", -4, -2)
            itemBtn:SetText("View")
            itemBtn:SetScript("OnClick", function()
                ShowItemPlayers(itemID, itemName)
            end)
            if not IsLeaderOrSolo() then itemBtn:Hide() end

            yOffset = yOffset - frameHeight - 4
        end
    end

    content:SetHeight(-yOffset + 10)
    if UpdateMyReserves then UpdateMyReserves() end
end

-- ============================================================
-- CSV IMPORT WINDOW
-- ============================================================
importFrame = CreateFrame("Frame", "SoftResTrackerImportFrame", UIParent, "SRTBaseFrameTemplate")
importFrame:SetSize(430, 330)
importFrame:SetPoint("CENTER")
importFrame:SetFrameStrata("DIALOG")
importFrame:SetBackdropColor(0.04, 0.07, 0.11, 0.97)
importFrame:EnableMouse(true)
importFrame:SetMovable(true)
importFrame:RegisterForDrag("LeftButton")
importFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
importFrame:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
importFrame:Hide()

-- Import window header strip
local importHeaderBG = importFrame:CreateTexture(nil, "BACKGROUND", nil, 1)
importHeaderBG:SetPoint("TOPLEFT",  importFrame, "TOPLEFT",   5,  -5)
importHeaderBG:SetPoint("TOPRIGHT", importFrame, "TOPRIGHT",  -5, -5)
importHeaderBG:SetHeight(30)
importHeaderBG:SetTexture(0.07, 0.13, 0.20, 0.95)

local importTitle = importFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
importTitle:SetPoint("LEFT", importFrame, "TOPLEFT", 14, -20)
importTitle:SetText("|cff4dc4f7SoftRes CSV Import|r")

local importCloseBtn = CreateFrame("Button", nil, importFrame, "SRTSmallButtonTemplate")
importCloseBtn:SetSize(22, 22)
importCloseBtn:SetPoint("TOPRIGHT", importFrame, "TOPRIGHT", -7, -8)
importCloseBtn:SetText("X")
importCloseBtn:SetScript("OnClick", function() importFrame:Hide() end)

local importHeaderSep = importFrame:CreateTexture(nil, "ARTWORK")
importHeaderSep:SetPoint("TOPLEFT",  importFrame, "TOPLEFT",   5, -35)
importHeaderSep:SetPoint("TOPRIGHT", importFrame, "TOPRIGHT",  -5, -35)
importHeaderSep:SetHeight(1)
importHeaderSep:SetTexture(0.25, 0.55, 0.82, 0.60)

local importDesc = importFrame:CreateFontString(nil, "OVERLAY", "SRTMutedFontTemplate")
importDesc:SetPoint("TOP",   importFrame, "TOP",  0, -48)
importDesc:SetWidth(400)
importDesc:SetJustifyH("CENTER")
importDesc:SetText("Paste your softres.it CSV export below, then click Import.\nGet it from: softres.it → Export → CSV")

local importScroll = CreateFrame("ScrollFrame", "SoftResTrackerImportScroll", importFrame, "UIPanelScrollFrameTemplate")
importScroll:SetPoint("TOPLEFT",     importFrame, "TOPLEFT",     10, -76)
importScroll:SetPoint("BOTTOMRIGHT", importFrame, "BOTTOMRIGHT", -30, 50)

importBox = CreateFrame("EditBox", "SoftResTrackerImportBox", importScroll)
importBox:SetMultiLine(true)
importBox:SetMaxLetters(0)
importBox:SetAutoFocus(false)
importBox:SetFontObject("ChatFontNormal")
importBox:SetWidth(380)
importBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
importScroll:SetScrollChild(importBox)

local importPlaceholder = importFrame:CreateFontString(nil, "OVERLAY", "SRTMutedFontTemplate")
importPlaceholder:SetPoint("TOPLEFT", importScroll, "TOPLEFT", 5, -3)
importPlaceholder:SetText("Paste CSV here...\nExample (softres.it format):\nName,ReservedItemId,ReservedItemName\nPlayerOne,19019,Thunderfury\nPlayerTwo,17182,Ring of Binding\n\nColumn order is detected automatically.")

importBox:SetScript("OnEditFocusGained", function(self)
    importPlaceholder:Hide()
end)
importBox:SetScript("OnTextChanged", function(self)
    if self:GetText() == "" then importPlaceholder:Show() else importPlaceholder:Hide() end
end)

local importStatus = importFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
importStatus:SetPoint("BOTTOMLEFT", importFrame, "BOTTOMLEFT", 12, 10)
importStatus:SetWidth(260)
importStatus:SetJustifyH("LEFT")
importStatus:SetText("")

-- ── CSV parsing (identical logic) ──
local function SplitCSVLine(line)
    local cols = {}
    local i = 1
    local len = #line
    while i <= len do
        local val = ""
        if line:sub(i, i) == '"' then
            i = i + 1
            while i <= len do
                local c = line:sub(i, i)
                if c == '"' then
                    if line:sub(i+1, i+1) == '"' then
                        val = val..'"'
                        i = i + 2
                    else
                        i = i + 1
                        break
                    end
                else
                    val = val..c
                    i = i + 1
                end
            end
            if line:sub(i, i) == ',' then i = i + 1 end
        else
            local s = i
            while i <= len and line:sub(i, i) ~= ',' do i = i + 1 end
            val = line:sub(s, i-1)
            if line:sub(i, i) == ',' then i = i + 1 end
        end
        table.insert(cols, val:match("^%s*(.-)%s*$"))
    end
    if line:sub(len, len) == ',' then table.insert(cols, "") end
    return cols
end

local function ParseAndImportCSV(csvText)
    local imported, skipped = 0, 0
    local PLAYER_KEYS = { name=true, player=true, playername=true, character=true,
                          ["player name"]=true, ["character name"]=true }
    local ITEMID_KEYS = { reserveditemid=true, itemid=true, item_id=true,
                          ["item id"]=true, id=true, reserveditem=true }
    local headerCols, playerCol, itemIDCol = nil, nil, nil

    for line in (csvText.."\n"):gmatch("([^\r\n]*)\r?\n") do
        line = line:match("^%s*(.-)%s*$")
        if line ~= "" then
            local cols = SplitCSVLine(line)
            if headerCols == nil then
                local lowerCols = {}
                for i, c in ipairs(cols) do lowerCols[i] = c:lower() end
                for i, colName in ipairs(lowerCols) do
                    if PLAYER_KEYS[colName] then playerCol = i end
                    if ITEMID_KEYS[colName] then itemIDCol = i end
                end
                if playerCol and itemIDCol then
                    headerCols = lowerCols
                else
                    headerCols = {}
                    local numericCol = nil
                    for i, c in ipairs(cols) do
                        if tonumber(c) then numericCol = i; break end
                    end
                    if numericCol then
                        itemIDCol = numericCol
                        for i, c in ipairs(cols) do
                            if i ~= numericCol and c ~= "" and tonumber(c) == nil then
                                playerCol = i; break
                            end
                        end
                        if playerCol and itemIDCol then
                            local pName = cols[playerCol]
                            local iID   = tonumber(cols[itemIDCol])
                            if pName and pName ~= "" and iID then
                                SoftResTrackerDB.reserves[iID] = SoftResTrackerDB.reserves[iID] or {}
                                local exists = false
                                for _, p in ipairs(SoftResTrackerDB.reserves[iID]) do
                                    if p:lower() == pName:lower() then exists = true; break end
                                end
                                if not exists then
                                    table.insert(SoftResTrackerDB.reserves[iID], pName)
                                    imported = imported + 1
                                else
                                    skipped = skipped + 1
                                end
                            else
                                skipped = skipped + 1
                            end
                        end
                    end
                end
            else
                if playerCol and itemIDCol and #cols >= math.max(playerCol, itemIDCol) then
                    local pName = cols[playerCol]
                    local iID   = tonumber(cols[itemIDCol])
                    if pName and pName ~= "" and iID then
                        SoftResTrackerDB.reserves[iID] = SoftResTrackerDB.reserves[iID] or {}
                        local exists = false
                        for _, p in ipairs(SoftResTrackerDB.reserves[iID]) do
                            if p:lower() == pName:lower() then exists = true; break end
                        end
                        if not exists then
                            table.insert(SoftResTrackerDB.reserves[iID], pName)
                            imported = imported + 1
                        else
                            skipped = skipped + 1
                        end
                    else
                        skipped = skipped + 1
                    end
                else
                    skipped = skipped + 1
                end
            end
        end
    end
    return imported, skipped
end

local btnImportDo = CreateFrame("Button", nil, importFrame, "SRTButtonTemplate")
btnImportDo:SetSize(80, 22)
btnImportDo:SetText("Import")
btnImportDo:SetPoint("BOTTOMRIGHT", importFrame, "BOTTOMRIGHT", -38, 10)
btnImportDo:SetScript("OnClick", function()
    local text = importBox:GetText()
    if text == "" then
        importStatus:SetText("|cffff5555Paste CSV data first.|r")
        return
    end
    local imported, skipped = ParseAndImportCSV(text)
    UpdateBoard()
    BroadcastFullSync()
    if imported > 0 then
        importStatus:SetText("|cff44ff44Imported "..imported.." reserve(s). Skipped "..skipped..".|r")
        print("SoftRes Tracker: CSV imported — "..imported.." reserve(s) added, "..skipped.." skipped.")
    else
        importStatus:SetText("|cffff5555No valid rows found. Check CSV format.|r")
    end
end)

local btnImportClear = CreateFrame("Button", nil, importFrame, "SRTSmallButtonTemplate")
btnImportClear:SetSize(60, 22)
btnImportClear:SetText("Clear")
btnImportClear:SetPoint("RIGHT", btnImportDo, "LEFT", -5, 0)
btnImportClear:SetScript("OnClick", function()
    importBox:SetText("")
    importBox:ClearFocus()
    importPlaceholder:Show()
    importStatus:SetText("")
end)

-- ============================================================
-- ROLLFOR EXPORT  (base64-encoded JSON for /sr import window)
-- Format: {"players":[{"name":"Player","itemId":12345}, ...]}
-- ============================================================

-- Pure Lua 5.1 base64 encoder (no external libraries needed)
local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function Base64Encode(data)
    local result = {}
    local padding = ""
    local len = #data
    -- Process 3 bytes at a time
    for i = 1, len - 2, 3 do
        local b1, b2, b3 = string.byte(data, i, i+2)
        local n = b1 * 65536 + b2 * 256 + b3
        result[#result+1] = string.sub(b64chars, math.floor(n/262144)+1, math.floor(n/262144)+1)
        result[#result+1] = string.sub(b64chars, math.floor(n/4096)%64+1, math.floor(n/4096)%64+1)
        result[#result+1] = string.sub(b64chars, math.floor(n/64)%64+1, math.floor(n/64)%64+1)
        result[#result+1] = string.sub(b64chars, n%64+1, n%64+1)
    end
    -- Handle remaining 1 or 2 bytes
    local rem = len % 3
    if rem == 1 then
        local b1 = string.byte(data, len)
        local n = b1 * 65536
        result[#result+1] = string.sub(b64chars, math.floor(n/262144)+1, math.floor(n/262144)+1)
        result[#result+1] = string.sub(b64chars, math.floor(n/4096)%64+1, math.floor(n/4096)%64+1)
        padding = "=="
    elseif rem == 2 then
        local b1, b2 = string.byte(data, len-1, len)
        local n = b1 * 65536 + b2 * 256
        result[#result+1] = string.sub(b64chars, math.floor(n/262144)+1, math.floor(n/262144)+1)
        result[#result+1] = string.sub(b64chars, math.floor(n/4096)%64+1, math.floor(n/4096)%64+1)
        result[#result+1] = string.sub(b64chars, math.floor(n/64)%64+1, math.floor(n/64)%64+1)
        padding = "="
    end
    return table.concat(result) .. padding
end

-- Build the RollFor-compatible base64 JSON string from current reserves
local function BuildRollForExport()
    -- Group items by player: playerItems[name] = {itemId, itemId, ...}
    local playerItems = {}
    local playerOrder = {}
    for itemID, players in pairs(SoftResTrackerDB.reserves) do
        for _, playerName in ipairs(players) do
            if not playerItems[playerName] then
                playerItems[playerName] = {}
                table.insert(playerOrder, playerName)
            end
            table.insert(playerItems[playerName], itemID)
        end
    end
    if #playerOrder == 0 then return nil end

    -- Build "softreserves" array: [{"name":"X","items":[{"id":N,"quality":0},...]}]
    local srEntries = {}
    table.sort(playerOrder)
    for _, playerName in ipairs(playerOrder) do
        local itemParts = {}
        for _, itemID in ipairs(playerItems[playerName]) do
            local _, _, quality = GetItemInfo(itemID)
            quality = quality or 0
            table.insert(itemParts, '{"id":' .. tostring(itemID) .. ',"quality":' .. tostring(quality) .. '}')
        end
        table.insert(srEntries,
            '{"name":"' .. playerName .. '","items":[' .. table.concat(itemParts, ",") .. ']}'
        )
    end

    local json = '{"metadata":{"id":"SRT","instance":0,"instances":[],"origin":"raidres"},'
              .. '"softreserves":[' .. table.concat(srEntries, ",") .. '],'
              .. '"hardreserves":[]}'
    return Base64Encode(json)
end

-- Scrollable export popup window
local exportWindow
SoftResTracker_ShowExportWindow = function()
    if exportWindow then
        exportWindow:Show()
        local encoded = BuildRollForExport()
        if not encoded then
            exportWindow.editBox:SetText("No reservations to export.")
        else
            exportWindow.editBox:SetText(encoded)
            exportWindow.editBox:SetFocus()
            exportWindow.editBox:HighlightText()
        end
        return
    end

    local f = CreateFrame("Frame", "SoftResTrackerExportWindow", UIParent)
    f:SetSize(520, 180)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })

    -- Title bar
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", f, "TOP", 0, -14)
    title:SetText("SoftRes Tracker - RollFor Export")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Instruction label
    local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -38)
    label:SetText("Copy this into RollFor's /sr import window:")

    -- Scroll frame + edit box
    local scrollFrame = CreateFrame("ScrollFrame", "SoftResTrackerExportScroll", f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -56)
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, 14)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(454)
    editBox:SetAutoFocus(false)
    editBox:SetScript("OnEscapePressed", function() f:Hide() end)
    scrollFrame:SetScrollChild(editBox)

    f.editBox = editBox
    exportWindow = f

    local encoded = BuildRollForExport()
    if not encoded then
        editBox:SetText("No reservations to export.")
    else
        editBox:SetText(encoded)
        editBox:SetFocus()
        editBox:HighlightText()
    end

    f:Show()
end

-- ============================================================
-- SLASH COMMANDS (identical logic)
-- ============================================================
SLASH_SOFTRESTRACKER1 = "/srt"
SlashCmdList["SOFTRESTRACKER"] = function(msg)
    local playerName, itemStr = msg:match("^clearplayer%s+([%w]+)%s*(.*)")

    if msg:lower() == "1sr" then
        SoftResTrackerDB.mode = 1
        print("SoftRes Tracker: 1 SR mode")
        return
    elseif msg:lower() == "2sr" then
        SoftResTrackerDB.mode = 2
        print("SoftRes Tracker: 2 SR mode")
        return
    elseif msg:lower() == "reset" then
        SoftResTrackerDB.reserves = {}
        print("SoftRes Tracker: All reservations cleared")
        UpdateBoard()
        return
    elseif msg:lower() == "toggle" then
        if frame:IsShown() then frame:Hide() else frame:Show() end
        SoftResTrackerDB.frameVisible = frame:IsShown()
        return
    elseif msg:lower() == "import" then
        if importFrame:IsShown() then importFrame:Hide()
        else importFrame:Show(); importBox:SetFocus() end
        return
    elseif msg:lower() == "export" then
        SoftResTracker_ShowExportWindow()
        return
    elseif playerName then
        local removedAny = false
        local function RemovePlayerFromItem(itemID)
            local list = SoftResTrackerDB.reserves[itemID]
            if list then
                for i = #list, 1, -1 do
                    if list[i]:lower() == playerName:lower() then
                        table.remove(list, i)
                        removedAny = true
                    end
                end
                if #list == 0 then SoftResTrackerDB.reserves[itemID] = nil end
            end
        end
        if itemStr ~= "" then
            local itemID = tonumber(itemStr) or tonumber(string.match(itemStr, "Hitem:(%d+)"))
            if not itemID then print("Invalid item. Use numeric ID or item link."); return end
            RemovePlayerFromItem(itemID)
        else
            for id, _ in pairs(SoftResTrackerDB.reserves) do RemovePlayerFromItem(id) end
        end
        if removedAny then
            print("SoftRes Tracker: Cleared SRs for "..playerName)
            UpdateBoard()
        else
            print("SoftRes Tracker: No SRs found for "..playerName)
        end
        return
    end

    print("|cff4dc4f7SoftRes Tracker commands:|r")
    print("  1SR, 2SR       |cffffffffSet SR limit|r")
    print("  reset          |cffffffffClear all reservations|r")
    print("  toggle         |cffffffffShow/hide the board|r")
    print("  clearplayer |cffffff00<n>|r  |cffffffffRemove a player's SR(s)|r")
    print("  import         |cffffffffOpen CSV import window|r")
    print("  export         |cffffffffExport SRs as RollFor base64 for /sr import|r")
    print("|cff4dc4f7Whisper commands:|r")
    print("  |cffffff00-sr [item]|r    |cffffffffReserve an item (whisper)|r")
    print("  |cffffff00-mysr|r         |cffffffffCheck your current SR(s) (whisper)|r")
    print("  |cffffff00-[item]|r       |cffffffffCheck how many reserved an item|r")
end

-- ============================================================
-- MINIMAP BUTTON
-- ============================================================
local function CreateMinimapButton()
    local button = CreateFrame("Button", "SoftResTrackerMinimapButton", Minimap)
    button:SetSize(33, 33)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:EnableMouse(true)
    button:RegisterForClicks("AnyUp")

    -- Icon 20x20 — positioned to sit inside the ring's visual hole
    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", button, "TOPLEFT", 6, -6)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_08")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Border 56x56 from button TOPLEFT — extends past the 33x33 button, that's fine
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(56, 56)
    border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    -- Glow — small, sits only over the icon area inside the ring
    local hl = button:CreateTexture(nil, "OVERLAY")
    hl:SetSize(28, 28)
    hl:SetPoint("TOPLEFT", button, "TOPLEFT", 3, -3)
    hl:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    hl:SetBlendMode("ADD")
    hl:Hide()

    -- Position helpers
    local radius = 80
    local function UpdatePosition()
        local angle = math.rad(SoftResTrackerDB.minimapPos or 225)
        button:ClearAllPoints()
        button:SetPoint("CENTER", Minimap, "CENTER",
            radius * math.cos(angle),
            radius * math.sin(angle))
    end
    UpdatePosition()

    -- Shift+drag: move around the minimap ring
    local dragging = false
    button:SetScript("OnMouseDown", function(self, btn)
        if IsShiftKeyDown() then
            dragging = true
            button:SetScript("OnUpdate", function()
                local cx, cy = Minimap:GetCenter()
                local scale  = Minimap:GetEffectiveScale()
                local mx, my = GetCursorPosition()
                mx, my = mx / scale - cx, my / scale - cy
                SoftResTrackerDB.minimapPos = math.deg(math.atan2(my, mx))
                UpdatePosition()
            end)
        end
    end)
    button:SetScript("OnMouseUp", function()
        dragging = false
        button:SetScript("OnUpdate", nil)
    end)

    button:SetScript("OnEnter", function(self)
        hl:Show()
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cff4dc4f7SoftRes Tracker|r")
        GameTooltip:AddLine("|cffffffffClick to toggle|r")
        GameTooltip:AddLine("|cffaaaaaaShift+drag to reposition|r")
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        hl:Hide()
        GameTooltip:Hide()
    end)
    button:SetScript("OnClick", function(self, btn)
        if IsShiftKeyDown() then return end  -- ignore clicks during drag
        if frame:IsShown() then frame:Hide() else frame:Show() end
        SoftResTrackerDB.frameVisible = frame:IsShown()
    end)
end

-- ============================================================
-- EVENT HANDLING
-- ============================================================
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("CHAT_MSG_WHISPER")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("RAID_ROSTER_UPDATE")
frame:RegisterEvent("PARTY_LEADER_CHANGED")
frame:RegisterEvent("PARTY_MEMBERS_CHANGED")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        if SoftResTrackerDB.framePos then
            local fp = SoftResTrackerDB.framePos
            frame:SetPoint(fp.point, UIParent, fp.relativePoint, fp.x, fp.y)
        else
            frame:SetPoint("CENTER", 0, -20)
        end

        if SoftResTrackerDB.frameVisible then
            frame:Show()
        else
            frame:Hide()
        end

        CreateMinimapButton()
        UpdateBoard()
        UpdateButtonStates()
        UpdateLockButton()

        if GetNumRaidMembers() > 0 then
            SendAddonMessage(ADDON_PREFIX, "SYNC_REQ", "RAID")
        end
        return

    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, channel, sender = ...
        if prefix ~= ADDON_PREFIX then return end
        local senderName = sender:match("^(.-)-") or sender
        local myName     = UnitName("player")
        if senderName:lower() == myName:lower() then return end

        if msg == "RESET" then
            SoftResTrackerDB.reserves = {}
            UpdateBoard()
        elseif msg == "SYNC_REQ" then
            BroadcastFullSync()
        else
            local action, itemIDStr, playerName = msg:match("^(%w+):(%d+):(.+)$")
            local itemID = tonumber(itemIDStr)
            if action and itemID and playerName then
                if action == "ADD" then
                    SoftResTrackerDB.reserves[itemID] = SoftResTrackerDB.reserves[itemID] or {}
                    table.insert(SoftResTrackerDB.reserves[itemID], playerName)
                    UpdateBoard()
                elseif action == "REM" then
                    local list = SoftResTrackerDB.reserves[itemID]
                    if list then
                        for i = #list, 1, -1 do
                            if list[i]:lower() == playerName:lower() then
                                table.remove(list, i); break
                            end
                        end
                        if #list == 0 then SoftResTrackerDB.reserves[itemID] = nil end
                    end
                    UpdateBoard()
                end
            end
        end
        return

    elseif event == "RAID_ROSTER_UPDATE" then
        if GetNumRaidMembers() > 0 then
            local raidMembers = {}
            for i = 1, GetNumRaidMembers() do
                local name = GetRaidRosterInfo(i)
                if name then name = string.match(name, "^[^-]+") end
                if name then raidMembers[name:lower()] = true end  -- lowercase key for safe compare
            end
            local changed = false
            for itemID, players in pairs(SoftResTrackerDB.reserves) do
                for i = #players, 1, -1 do
                    if not raidMembers[players[i]:lower()] then  -- compare lowercase
                        print("SoftRes Tracker: Removed "..players[i].." (left raid)")
                        table.remove(players, i)
                        changed = true
                    end
                end
                if #players == 0 then SoftResTrackerDB.reserves[itemID] = nil end
            end
            if changed then UpdateBoard() end
        end
        UpdateButtonStates()

    elseif event == "PARTY_LEADER_CHANGED" or event == "PARTY_MEMBERS_CHANGED" then
        UpdateButtonStates()
        UpdateBoard()

    elseif event == "CHAT_MSG_WHISPER" then
        local msg, sender = ...
        local name = sender:match("^(.-)-") or sender

        local now = GetTime()
        if lastWhisperTime[name] and (now - lastWhisperTime[name]) < 2 then return end
        lastWhisperTime[name] = now

        if msg:match("^%-") then
            if msg:lower():match("^%-sr") then
                if SoftResTrackerDB.locked then
                    SendChatMessage("Reservations are currently locked.", "WHISPER", nil, name)
                    return
                end
                if not msg:match("Hitem:%d+") then
                    SendChatMessage("To reserve an item, shift-click it and whisper: -sr [item link]", "WHISPER", nil, name)
                    return
                end
            elseif msg:lower():match("^%-mysr") then
                local myItems = {}
                for itemID, players in pairs(SoftResTrackerDB.reserves) do
                    local count = 0
                    for _, p in ipairs(players) do
                        if p:lower() == name:lower() then
                            count = count + 1
                        end
                    end
                    if count > 0 then
                        local itemName, itemLink = GetItemInfo(itemID)
                        local link = itemLink or itemName or ("Item "..itemID)
                        table.insert(myItems, { id = itemID, link = link, count = count })
                    end
                end
                local srCount   = GetPlayerSRCount(name)
                local remaining = SoftResTrackerDB.mode - srCount
                if #myItems == 0 then
                    SendChatMessage("You have no soft reserves. You have "..SoftResTrackerDB.mode.." SRs available. Whisper: -sr [item link] to reserve.", "WHISPER", nil, name)
                else
                    SendChatMessage("Your SRs ("..remaining.." slots remaining):", "WHISPER", nil, name)
                    for _, item in ipairs(myItems) do
                        local msg = item.count > 1 and (item.link .. " x" .. item.count) or item.link
                        SendChatMessage(msg, "WHISPER", nil, name)
                    end
                end
                return
            else
                local itemID = tonumber(msg:match("Hitem:(%d+)"))
                if itemID then
                    local itemName, itemLink = GetItemInfo(itemID)
                    local link  = itemLink or itemName or ("Item "..itemID)
                    local players = SoftResTrackerDB.reserves[itemID] or {}
                    local count   = #players
                    if count == 0 then
                        SendChatMessage(link.." has no reservations.", "WHISPER", nil, name)
                    elseif count == 1 then
                        SendChatMessage(link.." has 1 reservation: "..players[1], "WHISPER", nil, name)
                    else
                        SendChatMessage(link.." has "..count.." reservations: "..table.concat(players, ", "), "WHISPER", nil, name)
                    end
                end
                return
            end
        end

        if not msg:lower():match("^%-sr") then return end

        local srCount   = GetPlayerSRCount(name)
        local remaining = SoftResTrackerDB.mode - srCount

        -- Extract item IDs directly from the hyperlink token. In 3.3.5a the
        -- colour prefix (|cff…) is sometimes stripped or malformed when a
        -- whisper passes through the CHAT_MSG_WHISPER event, so we match
        -- |Hitem: directly and reconstruct a display link from the item name.
        local orderedItems = {}
        for iIDstr in msg:gmatch("|Hitem:(%d+)") do
            local iID = tonumber(iIDstr)
            if iID then
                local iName, iLink = GetItemInfo(iID)
                local link = iLink or iName or ("Item "..iID)
                table.insert(orderedItems, { id = iID, link = link })
            end
        end

        if #orderedItems == 0 then return end

        local totalAdded = 0
        local msgParts   = {}
        local addedIDs   = {}

        local seenInThisMsg = {}  -- guard: prevent same item twice in one whisper
        for _, item in ipairs(orderedItems) do
            if remaining <= 0 then break end
            if not seenInThisMsg[item.id] then
                seenInThisMsg[item.id] = true
                SoftResTrackerDB.reserves[item.id] = SoftResTrackerDB.reserves[item.id] or {}
                table.insert(SoftResTrackerDB.reserves[item.id], name)
                table.insert(msgParts, item.link)
                table.insert(addedIDs, item.id)
                remaining  = remaining  - 1
                totalAdded = totalAdded + 1
            end
        end

        if totalAdded > 0 then
            UpdateBoard()
            for _, itemID in ipairs(addedIDs) do BroadcastReserve(itemID, name) end
            SendChatMessage(
                "Reserved: "..table.concat(msgParts, ", ")..
                " (You have "..remaining.." SR(s) left)",
                "WHISPER", nil, name
            )
        end

        if #orderedItems > totalAdded and remaining <= 0 then
            SendChatMessage(
                "You have reached your SR limit ("..SoftResTrackerDB.mode..").",
                "WHISPER", nil, name
            )
        end
    end
end)
