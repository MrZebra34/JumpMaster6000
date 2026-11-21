local addonName, addon = ...
local fullWidth, fullHeight = 268, 186
local compactWidth, compactHeight = 188, 78
local compactRightInset, compactBottomInset = 42, 8

local function ExpansionOffset(left, top, width, height)
    -- Align inward growth to the compact stats, inside the control gutter and bottom padding.
    local x = left + width / 2 > 0 and compactWidth - compactRightInset - fullWidth or 0
    local y = top - height / 2 < 0 and fullHeight - compactHeight + compactBottomInset or 0
    return x, y
end

local function FormatDuration(seconds)
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor(seconds / 60) % 60
    if hours > 0 then
        return ("%02d:%02d:%02d"):format(hours, minutes, seconds % 60)
    end
    return ("%02d:%02d"):format(minutes, seconds % 60)
end

local function TextButton(parent, label)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(18, 20)
    button:SetNormalFontObject(GameFontHighlight)
    button:SetHighlightFontObject(GameFontNormal)
    button:SetText(label)
    return button
end

local function FitText(field, text, maxWidth)
    if field:GetText() == text then
        return
    end
    field:SetTextScale(1)
    field:SetText(text)
    local width = field:GetStringWidth()
    if width > maxWidth then
        field:SetTextScale(maxWidth / width)
    end
end

local function FormatAirtime(seconds)
    if seconds >= 60 then
        return FormatDuration(math.floor(seconds))
    end
    return ("%.2f s"):format(seconds)
end

function addon.CreateAirtimeBar(db, stats)
    local bar = CreateFrame("Frame", nil, UIParent)
    bar:Hide()
    bar:SetSize(298, 58)
    bar:SetFrameStrata("HIGH")
    bar:SetClampedToScreen(true)
    bar:SetMovable(true)

    local function AnchorBar()
        bar:ClearAllPoints()
        bar:SetPoint("CENTER", UIParent, "CENTER", db.airtimeX or 0, db.airtimeY or 0)
    end
    AnchorBar()

    local ornament = "Interface\\AddOns\\" .. addonName .. "\\Media\\AirtimeOrnament.tga"
    local trackWidth, trackHeight = 264, 34
    local track = bar:CreateTexture(nil, "ARTWORK", nil, 0)
    track:SetTexture(ornament)
    track:SetPoint("CENTER", 0, -18)
    track:SetSize(trackWidth, trackHeight)
    track:SetVertexColor(0.65, 0.54, 0.74, 0.65)

    local fill = bar:CreateTexture(nil, "ARTWORK", nil, 1)
    fill:SetTexture(ornament)
    fill:SetPoint("LEFT", track, "LEFT")
    fill:SetHeight(trackHeight)
    fill:SetVertexColor(1, 0.84, 1)

    local tip = bar:CreateTexture(nil, "ARTWORK", nil, 2)
    tip:SetTexture(ornament)
    -- Sample the center diamond to highlight the moving end of the fill.
    tip:SetTexCoord(0.47, 0.53, 0.37, 0.63)
    tip:SetSize(7, 8)
    tip:SetVertexColor(1, 0.77, 1)
    tip:SetBlendMode("ADD")

    local function Readout(x, y, size, r, g, b, label)
        local field = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        field:SetPoint("CENTER", bar, "CENTER", x, y)
        field:SetFontHeight(size)
        field:SetTextColor(r, g, b)
        field:SetShadowColor(0.025, 0.012, 0.04, 0.92)
        field:SetShadowOffset(1, -1)
        if label then
            field:SetText(label)
        end
        return field
    end

    Readout(0, 24, 11, 0.99, 0.85, 0.68, "Air Time")
    local timer = Readout(0, 6, 24, 0.93, 0.81, 1)
    Readout(-99, 16, 11, 0.88, 0.79, 0.93, "Longest Air Time")
    Readout(99, 16, 11, 0.88, 0.79, 0.93, "Total Air Time")
    local longest = Readout(-99, 1, 14, 0.98, 0.94, 0.91)
    local total = Readout(99, 1, 14, 0.98, 0.94, 0.91)

    local function Render(duration, longestDuration, totalDuration, progress)
        if not duration then
            bar:Hide()
            return
        end

        FitText(timer, FormatAirtime(duration), 100)
        FitText(longest, FormatAirtime(longestDuration), 94)
        FitText(total, FormatAirtime(totalDuration), 94)

        local filledWidth = trackWidth * progress
        if progress > 0 then
            fill:SetWidth(filledWidth)
            fill:SetTexCoord(0, progress, 0, 1)
            tip:SetPoint("CENTER", track, "LEFT", filledWidth, 0)
        end
        fill:SetShown(progress > 0)
        tip:SetShown(progress > 0 and progress < 1)
        bar:Show()
    end

    local selection, editing, dragging
    local liveDuration, liveLongest, liveTotal, liveProgress
    local function FinishDrag()
        if dragging then
            dragging = false
            bar:StopMovingOrSizing()
            local x, y = bar:GetCenter()
            local centerX, centerY = UIParent:GetCenter()
            db.airtimeX, db.airtimeY = x - centerX, y - centerY
            bar:SetUserPlaced(false)
            AnchorBar()
        end
    end

    EventRegistry:RegisterCallback("EditMode.Enter", function()
        if not selection then
            selection = CreateFrame("Frame", nil, bar, "EditModeSystemSelectionTemplate")
            selection.system = {GetSystemName = function() return "Air Time" end}
            selection:SetAllPoints()
            selection:SetFrameStrata("HIGH")
            selection:SetScript("OnMouseDown", nil)
            selection:SetScript("OnEnter", nil)
            selection:SetScript("OnLeave", nil)
            selection:SetScript("OnDragStart", function()
                if not InCombatLockdown() then
                    dragging = true
                    bar:StartMoving()
                end
            end)
            selection:SetScript("OnDragStop", FinishDrag)
        end
        editing = true
        Render(0, stats.longest, stats.total, 0)
        selection:ShowHighlighted()
    end)

    EventRegistry:RegisterCallback("EditMode.Exit", function()
        if editing then
            FinishDrag()
            editing = false
            selection:Hide()
            Render(liveDuration, liveLongest, liveTotal, liveProgress)
        end
    end)

    return function(duration, longestDuration, totalDuration, progress)
        liveDuration, liveLongest, liveTotal, liveProgress = duration, longestDuration, totalDuration, progress
        if not editing then
            Render(duration, longestDuration, totalDuration, progress)
        end
    end
end

function addon.CreatePanel(db, readStats, history, readCharacterPace)
    local panel = CreateFrame("Frame", nil, UIParent)
    panel:Hide()
    panel:SetFrameStrata("MEDIUM")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)

    local function AnchorAtSavedPosition()
        panel:ClearAllPoints()
        if type(db.x) == "number" and type(db.y) == "number" then
            -- Preserve the compact position encoded by existing saves.
            local left, top = db.x - fullWidth / 2, db.y + fullHeight / 2
            if not db.minimal then
                local x, y = ExpansionOffset(left, top, compactWidth, compactHeight)
                left, top = left + x, top + y
            end
            panel:SetPoint("TOPLEFT", UIParent, "CENTER", left, top)
        else
            panel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 24, -132)
        end
    end

    local header = CreateFrame("Frame", nil, panel)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        panel:StartMoving()
    end)
    header:SetScript("OnDragStop", function()
        panel:StopMovingOrSizing()
        local screenX, screenY = UIParent:GetCenter()
        local left, top = panel:GetLeft() - screenX, panel:GetTop() - screenY
        if not db.minimal then
            local x, y = ExpansionOffset(left, top, fullWidth, fullHeight)
            left, top = left - x, top - y
        end
        db.x, db.y = left + fullWidth / 2, top - fullHeight / 2
        AnchorAtSavedPosition()
    end)

    local function Close()
        db.hidden = true
        panel:Hide()
    end

    local full = CreateFrame("Frame", nil, panel)
    full:SetAllPoints()
    local artwork = full:CreateTexture(nil, "BACKGROUND")
    artwork:SetAllPoints()
    artwork:SetTexture("Interface\\AddOns\\" .. addonName .. "\\Media\\ShadowPriest.tga")

    local close = TextButton(full, "×")
    close:SetPoint("CENTER", full, "TOPLEFT", 250, -19)
    close:SetScript("OnClick", Close)

    local function AccountTooltip(tooltip)
        local rows = {}
        for guid, jumps in pairs(db.jumps) do
            local name = db.names[guid]
            if not name and type(guid) == "string" and guid:match("^Player%-") then
                local _, _, _, _, _, cachedName, realm = GetPlayerInfoByGUID(guid)
                name = addon.FormatCharacterName(cachedName, realm)
                db.names[guid] = name
            end
            rows[#rows + 1] = {name = name or "Unknown character", jumps = jumps}
        end
        table.sort(rows, function(a, b)
            if a.jumps == b.jumps then
                return a.name < b.name
            end
            return a.jumps > b.jumps
        end)
        tooltip:SetText("Account jumps")
        if #rows == 0 then
            tooltip:AddLine("No jumps recorded yet", 1, 1, 1)
        end
        for _, row in ipairs(rows) do
            tooltip:AddDoubleLine(row.name, BreakUpLargeNumbers(row.jumps), 1, 1, 1, 1, 1, 1)
        end
    end

    local function SessionTooltip(tooltip)
        tooltip:SetText("Past sessions")
        if #history == 0 then
            tooltip:AddLine("No completed sessions yet", 1, 1, 1)
            return
        end
        tooltip:AddDoubleLine("Session ended", "Jumps")
        for _, session in ipairs(history) do
            tooltip:AddDoubleLine(date("%Y-%m-%d %H:%M", session.time), BreakUpLargeNumbers(session.jumps),
                1, 1, 1, 1, 1, 1)
        end
    end

    local function PaceTooltip(tooltip)
        tooltip:SetText("Character average")
        tooltip:AddDoubleLine("Jumps per hour", BreakUpLargeNumbers(readCharacterPace()), 1, 1, 1, 1, 1, 1)
    end

    local tooltipOwner
    local function CreateTooltipTarget(parent, fill)
        local target = CreateFrame("Frame", nil, parent)
        target:EnableMouse(true)
        target.fillTooltip = fill
        target:SetScript("OnEnter", function(self)
            tooltipOwner = self
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            fill(GameTooltip)
            GameTooltip:Show()
        end)
        local function HideTooltip(self)
            if tooltipOwner == self then
                tooltipOwner = nil
                if GameTooltip:IsOwned(self) then
                    GameTooltip:Hide()
                end
            end
        end
        target:SetScript("OnLeave", HideTooltip)
        target:SetScript("OnHide", HideTooltip)
        return target
    end

    local function Readout(point, x, y, size, label)
        local field = full:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        field:SetPoint(point, full, "TOPLEFT", x, y)
        field:SetFontHeight(size)
        field:SetTextColor(0.98, 0.94, 0.86)
        if label then
            field:SetText(label)
        end
        return field
    end

    local title = Readout("LEFT", 43, -18, 16)
    FitText(title, "JumpMaster6000", 122)
    title:SetTextColor(0.99, 0.85, 0.59)
    local character = Readout("CENTER", 79, -93, 40)
    Readout("CENTER", 79, -123, 12, "Character jumps")
    local account = Readout("CENTER", 210, -70, 25)
    Readout("CENTER", 210, -51, 10, "Account jumps")
    local session = Readout("CENTER", 210, -119, 25)
    Readout("CENTER", 210, -101, 10, "Session jumps")
    local pace = Readout("RIGHT", 126, -162, 16)
    FitText(Readout("LEFT", 19, -162, 10), "Jumps per hour", 60)
    local idle = Readout("RIGHT", 254, -162, 13)
    idle:SetTextColor(0.87, 0.72, 1)
    FitText(Readout("LEFT", 144, -162, 9), "Since last jump", 56)

    local accountTarget = CreateTooltipTarget(full, AccountTooltip)
    accountTarget:SetPoint("TOPLEFT", 164, -42)
    accountTarget:SetSize(92, 46)
    local sessionTarget = CreateTooltipTarget(full, SessionTooltip)
    sessionTarget:SetPoint("TOPLEFT", 164, -92)
    sessionTarget:SetSize(92, 46)
    local paceTarget = CreateTooltipTarget(full, PaceTooltip)
    paceTarget:SetPoint("TOPLEFT", 82, -151)
    paceTarget:SetSize(47, 22)

    local compact = CreateFrame("Frame", nil, panel)
    compact:SetAllPoints()

    local compactClose = TextButton(compact, "x")
    compactClose:SetPoint("TOPRIGHT", -20, 0)
    compactClose:SetScript("OnClick", Close)

    local compactValues = {}
    local previousLabel
    local tooltips = { [2] = AccountTooltip, [3] = SessionTooltip, [4] = PaceTooltip }
    for index, name in ipairs({"Character jumps", "Account jumps", "Session jumps", "Jumps per hour", "Since last jump"}) do
        local label = compact:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetText(name)
        if previousLabel then
            label:SetPoint("TOPLEFT", previousLabel, "BOTTOMLEFT", 0, -3)
        else
            label:SetPoint("TOPLEFT", 4, -4)
        end
        local value = compact:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        value:SetPoint("TOPRIGHT", label, "TOPLEFT", compactWidth - compactRightInset - 4, 0)
        compactValues[index] = value
        previousLabel = label

        if tooltips[index] then
            local target = CreateTooltipTarget(compact, tooltips[index])
            target:SetPoint("TOPLEFT", label, "TOPLEFT")
            target:SetPoint("BOTTOMRIGHT", value, "BOTTOMRIGHT")
        end
    end

    local toggle = TextButton(panel, "-")

    local function Refresh()
        if panel:IsVisible() then
            local characterJumps, accountJumps, sessionJumps, jumpsPerHour, seconds = readStats()
            local characterText = BreakUpLargeNumbers(characterJumps)
            local accountText = BreakUpLargeNumbers(accountJumps)
            local sessionText = BreakUpLargeNumbers(sessionJumps)
            local paceText = BreakUpLargeNumbers(jumpsPerHour)
            local idleText = FormatDuration(seconds)
            if db.minimal then
                compactValues[1]:SetText(characterText)
                compactValues[2]:SetText(accountText)
                compactValues[3]:SetText(sessionText)
                compactValues[4]:SetText(paceText)
                compactValues[5]:SetText(idleText)
            else
                FitText(character, characterText, 128)
                FitText(account, accountText, 89)
                FitText(session, sessionText, 89)
                FitText(pace, paceText, 43)
                FitText(idle, idleText, 51)
            end
            if tooltipOwner and GameTooltip:IsOwned(tooltipOwner) then
                tooltipOwner.fillTooltip(GameTooltip)
                GameTooltip:Show()
            end
        end
    end

    local function ApplyMode()
        local minimal = not not db.minimal
        header:ClearAllPoints()
        toggle:ClearAllPoints()
        if minimal then
            panel:SetSize(compactWidth, compactHeight)
            header:SetPoint("TOPLEFT", 0, 0)
            header:SetPoint("TOPRIGHT", -40, 0)
            header:SetHeight(18)
            toggle:SetPoint("TOP", compactClose, "BOTTOM", 0, 0)
        else
            panel:SetSize(fullWidth, fullHeight)
            header:SetPoint("TOPLEFT", 12, -7)
            header:SetPoint("TOPRIGHT", -53, -7)
            header:SetHeight(25)
            toggle:SetPoint("CENTER", full, "TOPLEFT", 229, -19)
        end
        full:SetShown(not minimal)
        compact:SetShown(minimal)
        toggle:SetText(minimal and "+" or "-")
        AnchorAtSavedPosition()
        Refresh()
    end

    toggle:SetScript("OnClick", function()
        db.minimal = not db.minimal
        ApplyMode()
    end)
    toggle:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(db.minimal and "Show full panel" or "Show minimal panel")
        GameTooltip:Show()
    end)
    toggle:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local ticker
    panel:SetScript("OnShow", function()
        Refresh()
        ticker = C_Timer.NewTicker(1, Refresh)
    end)
    panel:SetScript("OnHide", function()
        if ticker then
            ticker:Cancel()
            ticker = nil
        end
    end)

    SLASH_JUMPMASTER60001 = "/jumpmaster6000"
    SLASH_JUMPMASTER60002 = "/jm6k"
    SlashCmdList.JUMPMASTER6000 = function()
        db.hidden = panel:IsShown()
        panel:SetShown(not db.hidden)
    end

    ApplyMode()
    panel:SetShown(not db.hidden)
    return Refresh
end
