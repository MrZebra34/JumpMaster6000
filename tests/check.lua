local root = "addon/JumpMaster6000/"
local toc = assert(io.open(root .. "JumpMaster6000.toc")):read("*a")
assert(toc:find("## Interface: 16001", 1, true))
assert(toc:find("## SavedVariables: JumpMaster6000DB", 1, true))
local license = assert(io.open("LICENSE", "rb"))
local bundledLicense = assert(io.open(root .. "LICENSE", "rb"))
assert(license:read("*a") == bundledLicense:read("*a"), "the addon bundles the repository's MIT license")
license:close()
bundledLicense:close()
local registry = {}
assert(loadfile(root .. "Themes.lua"))("JumpMaster6000", registry)
local themeCount = 0
for _, theme in pairs(registry.ThemeTextures) do
    themeCount = themeCount + 1
    local file = assert(io.open(root .. "Media/" .. theme .. ".tga", "rb"))
    local texture = file:read("*a")
    file:close()
    assert(#texture == 18 + 1024 * 512 * 4, theme .. " texture size")
    assert(texture:byte(3) == 2 and texture:sub(13, 18) == string.char(0, 4, 0, 2, 32, 8),
        theme .. " uncompressed 32-bit power-of-two TGA")
    assert(texture:byte(22) == 0 and texture:byte(22 + (256 * 1024 + 512) * 4) >= 240,
        theme .. " transparent exterior and opaque interior")
end
assert(themeCount == 28, "27 specs plus the original panel")
local ornament = assert(io.open(root .. "Media/AirtimeOrnament.tga", "rb")):read("*a")
assert(#ornament == 18 + 256 * 64 * 4)
assert(ornament:sub(13, 18) == string.char(0, 1, 64, 0, 32, 8) and ornament:byte(22) == 0)

local now, guid, airborne, movement, height = 20, "Player-A", false
local events, panel, bar, jumpStart, jumpStop, tick
local inCombat = false
local configID, spent, missingTexture
local treeID = 1089
local talentGroups = {
    [1089] = {11328, 11347, 11340},
    [1114] = {11608, 11615, 11622},
}
C_ClassTalents = {GetActiveConfigID = function() return configID end}
C_Traits = {
    GetConfigInfo = function(id) return id == configID and {treeIDs = {treeID}} end,
    GetGroupDisplayInfoByTreeID = function(id)
        local groups = assert(talentGroups[id])
        return {{groupID = groups[1]}, {groupID = groups[2]}, {groupID = groups[3]}}
    end,
    GetGroupCurrencyInfo = function(id, groups)
        assert(id == configID and #groups == 3)
        local rows = {}
        for i = #groups, 1, -1 do
            local group = groups[i]
            local points = spent[group]
            if points and points > 0 then
                rows[#rows + 1] = {traitNodeGroupID = group, currencyInfos = {{spent = points}}}
            end
        end
        return rows
    end,
}
local methods = {
    SetScript = function(self, event, fn) self[event] = fn end,
    RegisterEvent = function(self, event)
        self.events = self.events or {}
        self.events[event] = true
    end,
    UnregisterEvent = function(self, event) self.events[event] = nil end,
    IsVisible = function(self) return self.shown end,
    IsShown = function(self) return self.shown end,
    SetShown = function(self, shown)
        if self.shown == shown then return end
        self.shown = shown
        local callback = shown and self.OnShow or not shown and self.OnHide
        if callback then callback(self) end
    end,
    Hide = function(self) self:SetShown(false) end,
    Show = function(self) self:SetShown(true) end,
    CreateTexture = function(self, _, layer)
        local texture = setmetatable({shown = true, layer = layer}, getmetatable(self))
        table.insert(self.textures, texture)
        return texture
    end,
    CreateFontString = function(self)
        local text = setmetatable({shown = true}, getmetatable(self))
        table.insert(self.texts, text)
        return text
    end,
    SetText = function(self, text) self.text = text end,
    GetText = function(self) return self.text end,
    SetFontHeight = function(self, size) self.fontSize = size end,
    SetTextScale = function(self, scale) self.textScale = scale end,
    SetTextColor = function(self, ...) self.color = {...} end,
    SetShadowColor = function(self, ...) self.shadowColor = {...} end,
    SetShadowOffset = function(self, ...) self.shadowOffset = {...} end,
    GetStringWidth = function(self) return #self.text * self.fontSize * 0.55 * self.textScale end,
    SetTexture = function(self, asset) self.asset = asset end,
    GetTexture = function(self) if self.asset ~= missingTexture then return self.asset end end,
    GetCenter = function(self) return self.x, self.y end,
    GetLeft = function(self) return self.left end,
    GetTop = function(self) return self.top end,
    ClearAllPoints = function(self) self.points = {} end,
    SetPoint = function(self, point, ...)
        self.points = self.points or {}
        self.points[point] = {...}
    end,
    SetSize = function(self, width, height) self.width, self.height = width, height end,
    SetWidth = function(self, width) self.width = width end,
    SetTexCoord = function(self, ...) self.uv = {...} end,
    SetMouseClickEnabled = function(self, enabled) self.mouseClickEnabled = enabled end,
    SetPassThroughButtons = function(self, ...)
        assert(not inCombat, "mouse passthrough cannot be changed during combat")
        self.passThroughButtons = {...}
    end,
}
for name in ([[
    EnableMouse RegisterForDrag SetAllPoints SetBlendMode
    SetClampedToScreen SetFrameStrata SetHeight
    SetHighlightFontObject SetJustifyH SetMovable SetNormalFontObject SetSpacing
    SetVertexColor SetUserPlaced
]]):gmatch("%w+") do
    methods[name] = function() end
end

UIParent = setmetatable({x = 1000, y = 500}, {__index = methods})
SlashCmdList = {}
local themeMenu
local menuMethods = {}
function menuMethods:CreateTitle(title) self.title = title end
function menuMethods:CreateDivider() end
function menuMethods:CreateButton(label)
    local child = setmetatable({entries = {}}, getmetatable(self))
    self.entries[label] = child
    return child
end
function menuMethods:CreateRadio(label, isSelected, select, value)
    assert(not self.entries[label], "duplicate menu option")
    self.entries[label] = {
        checked = function() return isSelected(value) end,
        pick = function() select(value) end,
    }
end
MenuUtil = {CreateContextMenu = function(owner, generate)
    themeMenu = setmetatable({entries = {}, owner = owner}, {__index = menuMethods})
    generate(owner, themeMenu)
end}
function CreateFrame(_, _, parent, template)
    local frame = setmetatable({shown = true, texts = {}, children = {}, textures = {}, template = template},
        getmetatable(UIParent))
    if not parent then events = frame
    elseif parent == UIParent and panel then bar = frame
    elseif parent == UIParent then panel = frame
    else table.insert(parent.children, frame) end
    return frame
end
function methods:ShowHighlighted() self:Show() end
function methods:StartMoving() self.moving = true end
function methods:StopMovingOrSizing() self.moving = false end

local editCallbacks = {}
EventRegistry = {RegisterCallback = function(_, name, callback) editCallbacks[name] = callback end}
function InCombatLockdown() return inCombat end
GameTooltip = {
    SetOwner = function(self, owner) self.owner = owner end,
    IsOwned = function(self, owner) return self.owner == owner end,
    SetText = function(self, title) self.title, self.lines = title, {} end,
    AddLine = function(self, left) table.insert(self.lines, {left}) end,
    AddDoubleLine = function(self, left, right) table.insert(self.lines, {left, right}) end,
    Show = function() end,
    Hide = function(self) self.owner = nil end,
}
function hooksecurefunc(name, fn)
    if name == "JumpOrAscendStart" then
        jumpStart = fn
    else
        assert(name == "AscendStop")
        jumpStop = fn
    end
end

local function jump()
    jumpStart()
    jumpStop()
end
function GetTime() return now end
function GetServerTime() return 1700000000 + math.floor(now) end
date = os.date
function UnitGUID(unit) assert(unit == "player"); return guid end
function UnitFullName(unit) assert(unit == "player"); return guid == "Player-A" and "Alpha" or "Bravo" end
function GetNormalizedRealmName() return "HomeRealm" end
function GetPlayerInfoByGUID(playerGUID)
    if playerGUID == "Player-B" then
        return nil, nil, nil, nil, nil, "Bravo", "OtherRealm"
    end
end
PlaySoundFile = function() end
function IsFalling() return airborne end
local position
function UnitPosition(unit)
    assert(unit == "player")
    if position then return position.x, position.y, height, position.map end
    return now * 20, 0, height, 1
end
function GetUnitSpeed(unit) assert(unit == "player"); return position and position.speed end
function IsSwimming() return movement == "swim" or movement == "underwater" end
function IsSubmerged() return movement == "underwater" or movement == "submerged only" end
function IsFlying() return movement == "fly" end
function UnitOnTaxi() return movement == "taxi" end
function UnitInVehicle() return movement == "vehicle" end
function UnitIsDead() return movement == "dead" end
function BreakUpLargeNumbers(n) return tostring(n) end
C_Timer = {NewTicker = function(interval, callback)
    assert(interval == 1 and not tick)
    tick = callback
    return {Cancel = function() tick = nil end}
end}

local function Load()
    panel, bar = nil, nil
    local addon = {}
    for filename in toc:gmatch("[\r\n]([%a]+%.lua)") do
        assert(loadfile(root .. filename))("JumpMaster6000", addon)
    end
    events:OnEvent("PLAYER_ENTERING_WORLD")
end

local function Check(character, account, session, pace, idle)
    local full, compact = panel.children[2], panel.children[3]
    if compact:IsShown() then
        assert(not full:IsShown(), "borderless layout")
        for index, value in ipairs({character, account, session, pace, idle}) do
            assert(compact.texts[index * 2].text == value, "minimal stat " .. index)
        end
        return
    end
    assert(full:IsShown() and full.textures[1].asset == "Interface\\AddOns\\JumpMaster6000\\Media\\ShadowPriest.tga",
        "full layout")
    assert(full.texts[2].text == character and full.texts[4].text == account, "lifetime totals")
    assert(full.texts[6].text == session and full.texts[8].text == pace, "session rate")
    assert(full.texts[10].text == idle, "time without a jump")
end

local function Airborne(state)
    airborne = state
    events:OnUpdate()
end

JumpMaster6000DB = {
    jumpDataVersion = 1, jumps = {["Player-A"] = 7, ["Player-B"] = 18},
    jumpCreditPausedAt = 1700000000, jumpCreditPausedUntil = 1700000300,
}
configID, treeID, spent = 29, 1114, {[11622] = 22}
inCombat = true
Load()
local function CheckTooltipClickRules(expected)
    for index = 2, 3 do
        local children = panel.children[index].children
        for targetIndex = 2, #children do
            local buttons = children[targetIndex].passThroughButtons
            assert((buttons and table.concat(buttons, ",")) == expected, "tooltip click pass-through")
        end
    end
end
assert(panel.mouseClickEnabled and panel.events.PLAYER_REGEN_ENABLED and not panel.passThroughButtons)
CheckTooltipClickRules(nil)
inCombat = false
panel:OnEvent("PLAYER_REGEN_ENABLED")
assert(not panel.events.PLAYER_REGEN_ENABLED
    and table.concat(panel.passThroughButtons, ",") == "LeftButton,MiddleButton,Button4,Button5",
    "restore passthrough for other buttons after combat")
CheckTooltipClickRules("LeftButton,MiddleButton,Button4,Button5")
local previewArt = panel.children[2].textures[1]
local previewTicker = tick
local function Media(file)
    return "Interface\\AddOns\\JumpMaster6000\\Media\\" .. file .. ".tga"
end
assert(previewArt.asset == Media("Priest-Shadow"), "auto resolves Shadow when the empty trees are omitted")
local function CheckThemeRightClick(target)
    local priorMenu = themeMenu
    target:OnMouseUp("LeftButton", true)
    target:OnMouseUp("RightButton", false)
    assert(themeMenu == priorMenu, "only a right release inside the target opens the selector")
    target:OnMouseUp("RightButton", true)
    assert(themeMenu ~= priorMenu and themeMenu.owner == panel and themeMenu.title == "JumpMaster6000 Themes")
end
CheckThemeRightClick(panel)
CheckThemeRightClick(panel.children[1])
CheckThemeRightClick(panel.children[4])
for _, target in ipairs(panel.children[2].children) do
    CheckThemeRightClick(target)
end
assert(panel:IsShown() and not JumpMaster6000DB.minimal, "right-click preserves full mode")
SlashCmdList.JUMPMASTER6000("  THEMES ")
assert(themeMenu.owner == UIParent and themeMenu.title == "JumpMaster6000 Themes", "slash opens the same selector")
local automatic = themeMenu.entries["Automatic (follow talents)"]
local original = themeMenu.entries["Original Shadow Priest"]
assert(automatic.checked() and not original.checked(), "automatic is the default selection")
original.pick()
assert(original.checked() and not automatic.checked() and previewArt.asset == Media("ShadowPriest"))
automatic.pick()
assert(automatic.checked() and previewArt.asset == Media("Priest-Shadow"), "auto restores the new Shadow artwork")
configID, treeID, spent = nil, 1089, nil
panel:OnEvent("ACTIVE_COMBAT_CONFIG_CHANGED", configID)
Check("7", "25", "0", "0", "00:00")
for _, name in ipairs(registry.ThemeNames) do
    local class, spec = name:match("^([^-]+)-(.+)$")
    local option = themeMenu.entries[class].entries[(spec:gsub("-", " "))]
    option.pick()
    assert(option.checked() and previewArt.asset == Media(registry.ThemeTextures[name:lower()]), name .. " preview")
end
assert(panel:IsShown() and tick == previewTicker and not JumpMaster6000DB.hidden, "preview keeps the panel open")
local previewFields = panel.children[2].texts
local characterNumber, accountNumber = previewFields[2], previewFields[4]
assert(characterNumber.shadowOffset[1] == 2 and characterNumber.shadowOffset[2] == -2
    and characterNumber.shadowColor[4] == 1, "character number shadow")
assert(accountNumber.shadowOffset[1] == 1.5 and accountNumber.shadowOffset[2] == -1.5, "account number shadow")
local priest = themeMenu.entries.Priest.entries
priest.Holy.pick()
assert(previewFields[4].color[1] == 0.22 and previewFields[10].color[1] == 0.22, "contrast on pale side and footer")
assert(accountNumber.shadowColor[1] == 1 and accountNumber.shadowColor[4] == 0.85, "account shadow contrasts with dark ink")
priest.Shadow.pick()
assert(previewFields[4].color[1] == 0.98 and previewFields[10].color[1] == 0.87, "switch restores light text")
assert(accountNumber.shadowColor[1] == 0 and accountNumber.shadowColor[4] == 1, "account shadow contrasts with light ink")
configID, spent = 29, {[11340] = 22, [11328] = 12}
panel:OnEvent("ACTIVE_COMBAT_CONFIG_CHANGED", configID)
assert(previewArt.asset == Media("Priest-Shadow"), "preview survives a talent event")
SlashCmdList.JUMPMASTER6000()
assert(not panel:IsShown(), "plain slash hides the tracker")
SlashCmdList.JUMPMASTER6000("themes")
assert(not panel:IsShown() and themeMenu.entries.Priest.entries.Shadow.checked(), "selector opens while hidden and remembers the current choice")
themeMenu.entries["Automatic (follow talents)"].pick()
assert(not panel:IsShown(), "choosing a theme preserves visibility")
SlashCmdList.JUMPMASTER6000()
assert(previewArt.asset == Media("RestorationDruid"), "auto uses points from the active config")
spent[11328] = 30
panel:OnEvent("TRAIT_CONFIG_UPDATED", 42)
assert(previewArt.asset == Media("RestorationDruid"), "ignore another config's updates")
panel:OnEvent("TRAIT_CONFIG_UPDATED", configID)
assert(previewArt.asset == Media("Druid-Balance"), "active talent update")
missingTexture = Media("Druid-Balance")
panel:OnEvent("TRAIT_CONFIG_UPDATED", configID)
assert(previewArt.asset == Media("ShadowPriest"), "missing theme art falls back")
missingTexture = nil
spent[11340] = 30
panel:OnEvent("TRAIT_CONFIG_UPDATED", configID)
assert(previewArt.asset == Media("ShadowPriest"), "no unique leader uses original")
spent = {}
panel:OnEvent("ACTIVE_COMBAT_CONFIG_CHANGED", configID)
assert(previewArt.asset == Media("ShadowPriest"), "no points uses original")
configID = nil
Check("7", "25", "0", "0", "00:00")
local accountTarget = panel.children[2].children[2]
accountTarget:OnEnter()
assert(GameTooltip.title == "Account jumps" and #GameTooltip.lines == 2)
assert(GameTooltip.lines[1][1] == "Bravo-OtherRealm" and GameTooltip.lines[1][2] == "18")
assert(GameTooltip.lines[2][1] == "Alpha-HomeRealm" and GameTooltip.lines[2][2] == "7")
accountTarget:OnLeave()
assert(not GameTooltip.owner)
local sessionTarget = panel.children[2].children[3]
sessionTarget:OnEnter()
assert(GameTooltip.lines[1][1] == "No completed sessions yet")
sessionTarget:OnLeave()
assert(not JumpMaster6000DB.jumpCreditPausedAt and not JumpMaster6000DB.jumpCreditPausedUntil)
now = 80
jump()
events:OnUpdate()
jump()
Airborne(true)
Check("8", "26", "1", "60", "00:00")
jump()
events:OnUpdate()
Airborne(false)
Airborne(true)
Airborne(false)
jump()
now = 81
Airborne(true)
Airborne(false)
for _, mode in ipairs({"swim", "fly", "taxi", "vehicle", "dead"}) do
    movement = mode
    jump()
    Airborne(true)
    Airborne(false)
end
movement = nil
assert(JumpMaster6000DB.jumps[guid] == 8, "ignored transitions")

SlashCmdList.JUMPMASTER6000()
assert(not panel:IsShown() and not tick and JumpMaster6000DB.hidden)
now = 140
airborne = true
jump()
events:OnUpdate()
assert(JumpMaster6000DB.jumps[guid] == 9, "hidden tracking")
Airborne(false)
jump()
events:OnEvent("PLAYER_LEAVING_WORLD")
assert(not events.OnUpdate)
events:OnEvent("PLAYER_ENTERING_WORLD")
Airborne(true)
Airborne(false)
SlashCmdList.JUMPMASTER6000()
Check("9", "27", "2", "60", "00:00")
now = 3739
tick()
Check("9", "27", "2", "2", "59:59")
now = 3740
tick()
Check("9", "27", "2", "2", "01:00:00")

local full, compact, toggle = panel.children[2], panel.children[3], panel.children[4]
local currentTicker = tick
assert(toggle.text == "-" and toggle.points.CENTER[1] == full and toggle.points.CENTER[3] == 229)
assert(full.children[1].points.CENTER[3] == 250, "close button in artwork socket")
toggle:OnClick()
local compactClose = compact.children[1]
assert(compactClose.points.TOPRIGHT[1] == -20)
assert(toggle.text == "+" and toggle.points.TOP[1] == compactClose and toggle.points.TOP[2] == "BOTTOM")
assert(panel.width == 188 and panel.height == 106)
assert(panel.points.TOPLEFT[2] == "TOPLEFT" and panel.points.TOPLEFT[3] == 24 and panel.points.TOPLEFT[4] == -132)
assert(tick == currentTicker and JumpMaster6000DB.minimal, "mode switch lifecycle")
for _, target in ipairs(compact.children) do
    CheckThemeRightClick(target)
end
assert(panel:IsShown() and JumpMaster6000DB.minimal, "right-click preserves compact mode")
Check("9", "27", "2", "2", "01:00:00")
now = 3741
tick()
Check("9", "27", "2", "2", "01:00:01")

panel.left, panel.top = 766, 703
panel.children[1]:OnDragStop()
assert(JumpMaster6000DB.x == -100 and JumpMaster6000DB.y == 110)
assert(panel.points.TOPLEFT[3] == -234 and panel.points.TOPLEFT[4] == 203)
compact.children[1]:OnClick()
assert(not panel:IsShown() and not tick and JumpMaster6000DB.hidden)

guid = "Player-B"
Load()
assert(not panel:IsShown() and panel.children[3]:IsShown(), "preferred mode on login")
assert(panel.points.TOPLEFT[3] == -234 and panel.points.TOPLEFT[4] == 203, "saved anchor on login")
SlashCmdList.JUMPMASTER6000()
Check("18", "27", "0", "0", "00:00")
panel.children[4]:OnClick()
assert(not JumpMaster6000DB.minimal and panel.width == 268 and panel.height == 186)
Check("18", "27", "0", "0", "00:00")

local function CheckAnchor(left, top)
    local anchor = panel.points.TOPLEFT
    assert(anchor[1] == UIParent and anchor[2] == "CENTER" and anchor[3] == left and anchor[4] == top,
        ("expected panel position (%d, %d), got (%s, %s)"):format(left, top, tostring(anchor[3]), tostring(anchor[4])))
end

local header, mode = panel.children[1], panel.children[4]
mode:OnClick()
for _, positions in ipairs({
    {-400, 200, -400, 200},
    {200, 200, 78, 200},
    {-400, -100, -400, -12},
    {200, -100, 78, -12},
}) do
    local left, top, fullLeft, fullTop = unpack(positions)
    panel.left, panel.top = UIParent.x + left, UIParent.y + top
    header:OnDragStop()
    CheckAnchor(left, top)
    mode:OnClick()
    CheckAnchor(fullLeft, fullTop)
    mode:OnClick()
    CheckAnchor(left, top)
end

mode:OnClick()
panel.left, panel.top = UIParent.x + 200, UIParent.y - 100
header:OnDragStop()
CheckAnchor(200, -100)
mode:OnClick()
CheckAnchor(322, -188)
mode:OnClick()
CheckAnchor(200, -100)
mode:OnClick()
panel.left, panel.top = UIParent.x - 92, UIParent.y + 52
header:OnDragStop()
mode:OnClick()
CheckAnchor(-214, 140)
panel.left, panel.top = UIParent.x - 213, UIParent.y + 139
header:OnDragStop()
CheckAnchor(-213, 139)
mode:OnClick()
CheckAnchor(-91, 51)
mode:OnClick()
panel.left, panel.top = UIParent.x - 217, UIParent.y + 142
header:OnDragStop()
CheckAnchor(-217, 142)
mode:OnClick()
CheckAnchor(-217, 142)
mode:OnClick()
panel.children[2].children[1]:OnClick()
assert(not panel:IsShown() and not tick, "full close")

JumpMaster6000DB = {jumpDataVersion = 1, jumps = { [guid] = 1234567890 }}
Load()
Check("1234567890", "1234567890", "0", "0", "00:00")
local readouts = panel.children[2].texts
assert(readouts[2].textScale < 1 and readouts[2]:GetStringWidth() <= 128.01)
assert(readouts[4].textScale < 1 and readouts[4]:GetStringWidth() <= 89.01)
now = now + 360000
tick()
Check("1234567890", "1234567890", "0", "0", "100:00:00")
assert(readouts[10].textScale < 1 and readouts[10]:GetStringWidth() <= 51.01)
jump()
Airborne(true)
assert(readouts[10].text == "00:00" and readouts[10].textScale == 1, "timer scale restored after jump")

-- The upgrade resets all legacy character counts once, while retaining panel settings.
SlashCmdList.JUMPMASTER6000()
Airborne(false)
local firstJump = math.floor(now) + 10
now, guid = firstJump, "Player-A"
JumpMaster6000DB = {
    jumps = {["Player-A"] = 7, ["Player-B"] = 18},
    hidden = true, minimal = true, x = -100, y = 110,
}
Load()
assert(JumpMaster6000DB.jumpDataVersion == 1 and not next(JumpMaster6000DB.jumps))
assert(not panel:IsShown() and panel.children[3]:IsShown())
CheckAnchor(-234, 203)
SlashCmdList.JUMPMASTER6000()
Check("0", "0", "0", "0", "00:00")

local function JumpAndLand()
    jump()
    Airborne(true)
    Airborne(false)
end

JumpAndLand()
Check("1", "1", "1", "0", "00:00")

-- A transient takeoff after a brief ground contact has to last long enough to count.
now = firstJump + 0.02
jump()
Airborne(true)
now = firstJump + 0.09
Airborne(false)
Check("1", "1", "1", "0", "00:00")

now = firstJump + 0.28125
Airborne(true)
now = firstJump + 0.34375
Airborne(false)
local quickTakeoff = firstJump + 0.375
now = quickTakeoff
jump()
Airborne(true)
now = quickTakeoff + 0.199
events:OnUpdate()
Check("1", "1", "1", "0", "00:00")
now = quickTakeoff + 0.20
events:OnUpdate()
Check("2", "2", "2", "0", "00:00")
now = firstJump + 1.0625 - 0.05
Airborne(false)
now = now + 0.05
JumpAndLand()
Check("3", "3", "3", "10165", "00:00")

-- Start a second session with a full budget and confirm the account retains the first character.
SlashCmdList.JUMPMASTER6000()
local budgetStart = firstJump + 10
now, guid = budgetStart, "Player-B"
Load()
SlashCmdList.JUMPMASTER6000()
Check("0", "3", "0", "0", "00:00")
JumpAndLand()
now = budgetStart + 0.28125
JumpAndLand()
assert(JumpMaster6000DB.jumps[guid] == 1, "the duplicate interval applies while moving")
now = budgetStart + 0.30
jump()
Airborne(true)
now = now + 0.20
events:OnUpdate()
Airborne(false)
Check("2", "5", "2", "0", "00:00")

-- The former developer command cannot bypass an exhausted budget.
SlashCmdList.JUMPMASTER6000("dev")
now = budgetStart + 0.9375
JumpAndLand()
SlashCmdList.JUMPMASTER6000()
Check("2", "5", "2", "0", "00:00")
now = budgetStart + 1.015625
JumpAndLand()
assert(JumpMaster6000DB.jumps[guid] == 3, "moving jumps can spend a refilled credit")

-- Sustained normal jumps still count when the next input follows landing by only 20 ms.
for index = 0, 11 do
    local takeoff = budgetStart + 5 + index * 0.80
    now = takeoff
    jump()
    Airborne(true)
    now = takeoff + 0.20
    events:OnUpdate()
    now = takeoff + 0.78
    Airborne(false)
end
assert(JumpMaster6000DB.jumps[guid] == 15, "rapid normal re-jumps keep counting")

-- The same threshold applies to the overlay and both saved totals.
SlashCmdList.JUMPMASTER6000()
local start = 500
now, guid, airborne = start, "Player-A", false
JumpMaster6000DB = {
    jumpDataVersion = 1, jumps = {[guid] = 7}, hidden = true,
    airtime = {[guid] = {longest = -5, total = "invalid"}, ["Player-B"] = {longest = 3, total = 10}},
}
Load()
local stats = JumpMaster6000DB.airtime[guid]
assert(stats.longest == 0 and stats.total == 0 and not bar:IsShown())
assert(bar.points.CENTER[1] == UIParent and bar.points.CENTER[2] == "CENTER")
assert(#bar.textures == 3)
for _, layer in ipairs(bar.textures) do
    assert(layer.layer == "ARTWORK" and layer.asset:match("AirtimeOrnament%.tga$"), "transparent ornament layers")
end
for _, duration in ipairs({0.5, 1, 1.5}) do
    Airborne(true)
    now = now + duration
    Airborne(false)
    assert(stats.longest == 0 and stats.total == 0 and not bar:IsShown(), "short hops do not accrue airtime")
    now = now + 0.25
end

start = now
now = start + 1
Airborne(true)
now = start + 2.5
events:OnUpdate()
assert(not bar:IsShown(), "exact threshold stays hidden")
now = start + 2.75
events:OnUpdate()
assert(bar:IsShown() and not panel:IsShown(), "airtime bar works independently")
assert(bar.texts[2].text == "1.75 s" and bar.texts[5].text == "0.00 s" and bar.texts[6].text == "1.75 s")
assert(stats.total == 0, "airtime in progress stays out of saved totals")
now = start + 3.25
Airborne(false)
assert(bar.texts[2].text == "2.25 s" and stats.longest == 2.25 and stats.total == 2.25)
now = start + 6
events:OnUpdate()
assert(bar:IsShown() and bar.texts[2].text == "2.25 s", "landing holds the final reading")
now = start + 6.25
events:OnUpdate()
assert(not bar:IsShown(), "landing reading expires after three seconds")

-- Reject taxi travel and cancel an unfinished stretch when taxi starts or the world unloads.
for _, interruption in ipairs({"taxi", "zone"}) do
    now = now + 1
    Airborne(true)
    now = now + 2
    events:OnUpdate()
    assert(bar:IsShown())
    if interruption == "taxi" then
        movement = "taxi"
        events:OnUpdate()
        now = now + 30
        events:OnUpdate()
        movement = nil
    else
        events:OnEvent("PLAYER_LEAVING_WORLD")
        now = now + 30
        events:OnEvent("PLAYER_ENTERING_WORLD")
    end
    events:OnUpdate()
    Airborne(false)
    assert(not bar:IsShown() and stats.total == 2.25, "discard interrupted attempts")
end
movement = "taxi"
Airborne(true)
now = now + 30
events:OnUpdate()
Airborne(false)
movement = nil
assert(not bar:IsShown() and stats.total == 2.25, "ignore the entire flight path")

now = now + 1
Airborne(true)
now = now + 4
movement = "dead"
Airborne(false)
movement = nil
assert(bar:IsShown() and stats.longest == 4 and stats.total == 6.25, "lethal landing counts")
Load()
assert(JumpMaster6000DB.airtime[guid].total == 6.25 and not bar:IsShown(), "persist completed airtime")
assert(JumpMaster6000DB.airtime["Player-B"].total == 10 and JumpMaster6000DB.jumps[guid] == 7)

local track, fill, tip = unpack(bar.textures)
start = now + 1
now = start
Airborne(true)
now = start + 2
events:OnUpdate()
assert(fill:IsShown() and fill.width == track.width / 2 and fill.uv[2] == 0.5, "clip the ornament at half the best")
assert(tip:IsShown() and tip.points.CENTER[3] == fill.width, "the glint follows the cut")
assert(bar.texts[2].text == "2.00 s" and bar.texts[5].text == "4.00 s")
now = start + 5
events:OnUpdate()
assert(fill.width == track.width and fill.uv[2] == 1 and not tip:IsShown(), "cap the fill at the best")
assert(bar.texts[2].text == "5.00 s" and bar.texts[5].text == "4.00 s", "the timer keeps counting")
Airborne(false)
assert(bar.texts[5].text == "5.00 s" and fill.width == track.width, "hold the new record on landing")

JumpMaster6000DB.airtime[guid] = nil
Load()
now = now + 1
Airborne(true)
now = now + 2
events:OnUpdate()
assert(bar:IsShown() and bar.texts[5].text == "0.00 s", "show the timer on the first attempt")
assert(not bar.textures[2]:IsShown() and not bar.textures[3]:IsShown(), "no fill without a recorded best")

-- The held result of a long fall must disappear as soon as the next attempt begins.
Airborne(false)
assert(bar:IsShown())
now = now + 0.125
Airborne(true)
assert(not bar:IsShown(), "new takeoff clears the held result")
now = now + 0.75
Airborne(false)

-- Re-jumps can land just before the jump hook, or before any callback sees the ground.
for _, missedLanding in ipairs({false, true}) do
    JumpMaster6000DB = {jumpDataVersion = 1, hidden = true}
    Load()
    now, height = now + 1, 100
    jump()
    Airborne(true)
    for _ = 1, 4 do
        now, height = now + 0.50, 99
        events:OnUpdate()
        now = now + 0.375
        airborne = missedLanding
        jump()
        height = 100
        Airborne(true)
        assert(not bar:IsShown(), "repeated short jumps never qualify as a single fall")
    end
    now = now + 0.25
    events:OnUpdate()
    Airborne(false)
    assert(JumpMaster6000DB.airtime[guid].total == 0, "short re-jumps do not accrue airtime")
    assert(JumpMaster6000DB.jumps[guid] == (missedLanding and 1 or 5),
        "re-jump credit requires a sampled landing until Forever exposes a reliable signal")
end

-- A native takeoff already visible to the hook survives a delayed OnUpdate.
JumpMaster6000DB = {jumpDataVersion = 1, hidden = true}
Load()
now, airborne = now + 1, true
jump()
assert(JumpMaster6000DB.jumps[guid] == 1, "credit the takeoff visible inside the hook")
now = now + 0.266
events:OnUpdate()
Airborne(false)
assert(JumpMaster6000DB.jumps[guid] == 1, "the delayed frame cannot duplicate the takeoff")

-- An airborne jump input cancels a visible attempt and leaves no new record.
local beforeInterruptedFall = JumpMaster6000DB.airtime[guid].total
now, height = now + 1, 100
Airborne(true)
now, height = now + 2, 84
events:OnUpdate()
assert(bar.texts[2].text == "2.00 s")
jump()
assert(not bar:IsShown(), "another jump input clears the current measurement immediately")
now, height = now + 0.5, 80
Airborne(false)
assert(JumpMaster6000DB.airtime[guid].total == beforeInterruptedFall, "discard the incomplete measurement")

-- Missed landings cannot merge hops, regardless of the available height samples.
for _, heightRate in ipairs({false, 0, -1, 1}) do
    JumpMaster6000DB = {jumpDataVersion = 1, hidden = true}
    Load()
    local ambiguousStart = now + 1
    local stats = JumpMaster6000DB.airtime[guid]
    for hop = 0, 2 do
        local takeoff = ambiguousStart + hop * 0.75
        now = takeoff
        jump()
        now = takeoff + (hop > 0 and 0.26 or 0)
        height = heightRate and 100 + heightRate * (now - ambiguousStart) or nil
        Airborne(true)
        now = takeoff + 0.50
        height = heightRate and 100 + heightRate * (now - ambiguousStart) or nil
        events:OnUpdate()
        assert(not bar:IsShown(), "uncertain re-jumps must not display a merged timer")
    end
    now = ambiguousStart + 2.25
    Airborne(false)
    assert(stats.longest == 0 and stats.total == 0, "discard the uncertain attempt")
    now, height = ambiguousStart + 3, nil
    Airborne(true)
    now = now + 2
    Airborne(false)
    assert(bar:IsShown() and stats.longest == 2 and stats.total == 2,
        "track a new uninterrupted fall after observed ground")
end

-- A surface jump can have a falling sample while the swimming flag is still active.
JumpMaster6000DB = {jumpDataVersion = 1, hidden = true}
Load()
local waterStats = JumpMaster6000DB.airtime[guid]
for index, alreadyFalling in ipairs({false, true}) do
    now, movement, height = now + 1, "swim", nil
    if alreadyFalling then Airborne(true) end
    jump()
    now = now + 0.0625
    Airborne(true)
    assert((JumpMaster6000DB.jumps[guid] or 0) == index - 1, "wait for the water exit")
    now, movement = now + 0.0625, nil
    events:OnUpdate()
    assert(JumpMaster6000DB.jumps[guid] == index, "confirmed surface jump")
    now, movement = now + 0.5, "swim"
    Airborne(false)
    assert(waterStats.total == 0 and not bar:IsShown(), "surface hops stay out of Air Time")
end

for index, kind in ipairs({"submerged at the hook", "dry by the post-hook", "submerged on the first falling frame"}) do
    now, movement, height = now + 1, "swim", nil
    Airborne(kind == "dry by the post-hook")
    if kind == "submerged at the hook" then movement = "underwater" end
    if kind == "dry by the post-hook" then movement = nil end
    jump()
    if kind == "submerged on the first falling frame" then
        movement = "submerged only"
    end
    now = now + 0.0625
    Airborne(true)
    if movement then
        assert(JumpMaster6000DB.jumps[guid] == index + 1, "wet falling sample must wait")
    end
    now, movement = now + 0.0625, nil
    events:OnUpdate()
    assert(JumpMaster6000DB.jumps[guid] == index + 2, kind)
    events:OnUpdate()
    assert(JumpMaster6000DB.jumps[guid] == index + 2, "one credit per surface hop")
    now, movement = now + 0.5, "swim"
    Airborne(false)
end
assert(waterStats.total == 0, "surface-hop variants stay out of Air Time")

-- Ordinary ascent can reach the surface while the player is still swimming.
now, movement = now + 1, "underwater"
jump()
now, movement = now + 0.125, "swim"
Airborne(true)
assert(JumpMaster6000DB.jumps[guid] == 5, "resurfacing in the water earns no credit")
now, movement = now + 0.25, nil
events:OnUpdate()
assert(JumpMaster6000DB.jumps[guid] == 5, "an expired request cannot credit a later fall")
Airborne(false)

for _, kind in ipairs({"height alone", "no jump input"}) do
    now, movement, height = now + 1, "swim", 100
    events:OnUpdate()
    if kind == "height alone" then jump() end
    now, movement, height = now + 0.125, nil, 101
    Airborne(kind == "no jump input")
    assert(JumpMaster6000DB.jumps[guid] == 5, kind)
    now, movement = now + 0.5, "swim"
    Airborne(false)
end

-- Held input can produce additional water hops without another jump start.
now, movement = now + 1, "swim"
jumpStart()
for index = 1, 4 do
    now, movement = now + 0.0625, nil
    Airborne(true)
    events:OnUpdate()
    assert(JumpMaster6000DB.jumps[guid] == 5 + index, "one credit per held water re-hop")
    now, movement = now + 0.75, "submerged only"
    Airborne(true)
    assert(not bar:IsShown() and waterStats.total == 0, "held water hops never build up Air Time")
end
jumpStop()
now, movement = now + 0.0625, nil
Airborne(true)
assert(JumpMaster6000DB.jumps[guid] == 10, "allow a takeoff armed before release")
now, movement = now + 0.75, "submerged only"
Airborne(true)
now, movement = now + 0.0625, nil
Airborne(true)
assert(JumpMaster6000DB.jumps[guid] == 10, "release prevents arming another re-hop")

-- A tap just before a brief water contact still applies to the next exit.
now = now + 0.625
jump()
now, movement = now + 0.0625, "submerged only"
Airborne(true)
now, movement = now + 0.0625, nil
Airborne(true)
assert(JumpMaster6000DB.jumps[guid] == 11, "a recent tap can precede the wet sample")
now = now + 0.25
Airborne(false)
now = now + 0.01
Airborne(true)
now = now + 2
events:OnUpdate()
assert(not bar:IsShown(), "a brief dry-ground flag does not re-arm Air Time")
Airborne(false)

-- A splash cancels an active dry fall, and dry ground lets the next fall qualify.
now = now + 1
events:OnUpdate()
Airborne(true)
now = now + 2
events:OnUpdate()
assert(bar:IsShown(), "dry fall can qualify")
local hideCalls = 0
bar.Hide = function(self)
    hideCalls = hideCalls + 1
    methods.Hide(self)
end
movement = "swim"
Airborne(false)
assert(not bar:IsShown() and waterStats.total == 0, "water landing discards the attempt")
for _ = 1, 3 do
    now = now + 0.0625
    events:OnUpdate()
end
assert(hideCalls == 1, "swimming only hides the bar when canceling an attempt")
now, movement = now + 0.0625, nil
events:OnUpdate()
now = now + 0.0625
events:OnUpdate()
Airborne(true)
now = now + 2
Airborne(false)
assert(bar:IsShown() and waterStats.total == 2, "dry ground re-arms Air Time")

-- Stable dry ground ends a water request before its normal timeout.
JumpMaster6000DB = {jumpDataVersion = 1, hidden = true}
Load()
now, movement = now + 1, "swim"
Airborne(false)
jump()
now, movement = now + 0.0625, nil
events:OnUpdate()
now = now + 0.0625
events:OnUpdate()
now = now + 0.0625
Airborne(true)
assert(not JumpMaster6000DB.jumps[guid], "a stale water request cannot credit a dry fall")
now = now + 2
Airborne(false)
assert(JumpMaster6000DB.airtime[guid].total == 2, "the dry fall counts toward Air Time")

-- A fixed anchor keeps small movements and height changes in the same streak.
JumpMaster6000DB = {jumpDataVersion = 1, hidden = true}
Load()
now = now + 1
local spotStart = now
position = {x = 100, y = -100, map = 1}
JumpAndLand()
now, position.x, position.y, height = spotStart + 0.5, 100.49, -99.51, 105
JumpAndLand()
assert(JumpMaster6000DB.jumps[guid] == 1, "the stationary interval uses a horizontal radius")
now = spotStart + 0.8
for count = 2, 10 do
    position.x = count % 2 == 0 and 100.49 or 99.51
    JumpAndLand()
    assert(JumpMaster6000DB.jumps[guid] == count, "each eligible stationary jump up to ten counts")
    now = now + 0.8
end
now = now + 5
JumpAndLand()
assert(JumpMaster6000DB.jumps[guid] == 10, "refilling the global budget does not clear the spot cap")
now = now + 0.125
position.x, position.y = 100.75, -100
JumpAndLand()
assert(JumpMaster6000DB.jumps[guid] == 11, "moving outside the radius starts a new streak")

-- When coordinates are unavailable, a readable zero speed still limits in-place jumps.
position = {speed = 0}
now = now + 1
JumpAndLand()
assert(JumpMaster6000DB.jumps[guid] == 12)
now = now + 0.5
JumpAndLand()
assert(JumpMaster6000DB.jumps[guid] == 12, "unavailable coordinates still use the speed fallback")
position.speed = 7
now = now + 0.05
JumpAndLand()
assert(JumpMaster6000DB.jumps[guid] == 13, "known movement can start a new streak")

position.speed = 0
for _ = 1, 9 do
    now = now + 1
    JumpAndLand()
end
assert(JumpMaster6000DB.jumps[guid] == 22, "fill the spot streak before zoning")
events:OnEvent("PLAYER_LEAVING_WORLD")
events:OnEvent("PLAYER_ENTERING_WORLD")
now = now + 0.125
JumpAndLand()
assert(JumpMaster6000DB.jumps[guid] == 22, "zoning preserves the duplicate interval")
for count = 23, 24 do
    now = now + 1
    JumpAndLand()
    assert(JumpMaster6000DB.jumps[guid] == count, "zoning clears the spot cap without coordinates")
end

-- A fresh UI instance keeps the old counts and saves completed sessions by character.
guid, position, now = "Player-A", nil, 10000
JumpMaster6000DB = {jumpDataVersion = 1, hidden = true, jumps = {["Player-A"] = 70}}
for index = 1, 11 do
    local started = now
    Load()
    now = started + 10
    JumpAndLand()
    if index == 1 then
        events:OnEvent("PLAYER_LEAVING_WORLD")
        now = started + 20
        events:OnEvent("PLAYER_ENTERING_WORLD")
        JumpAndLand()
    end
    now = started + (index == 1 and 90 or 60)
    events:OnEvent("PLAYER_LOGOUT")
    events:OnEvent("PLAYER_LOGOUT")
end
local stats = JumpMaster6000DB.sessions[guid]
assert(#stats.history == 10 and stats.history[1].time == GetServerTime())
assert(stats.history[10].time == GetServerTime() - 9 * 60 and stats.history[10].jumps == 1)
assert(stats.jumps == 12 and stats.seconds == 690 and JumpMaster6000DB.jumps[guid] == 82)
JumpMaster6000DB.airtime[guid] = {total = 123, longest = 0.75}
Load()
SlashCmdList.JUMPMASTER6000()
local full = panel.children[2]
full.children[4]:OnEnter()
assert(GameTooltip.title == "Character average" and GameTooltip.lines[1][2] == "63",
    "weighted average includes sessions outside the history window")
assert(GameTooltip.lines[3][1] == "Air Time")
assert(GameTooltip.lines[4][1] == "Total" and GameTooltip.lines[4][2] == "02:03")
assert(GameTooltip.lines[5][1] == "Longest" and GameTooltip.lines[5][2] == "0.75 s")
now = now + 25
Airborne(true)
now = now + 2
Airborne(false)
now = now + 3
events:OnUpdate()
tick()
assert(GameTooltip.lines[1][2] == "60", "current session time updates the tooltip")
assert(GameTooltip.lines[4][2] == "02:05" and GameTooltip.lines[5][2] == "2.00 s",
    "completed Air Time updates the open tooltip")
full.children[4]:OnLeave()
panel.children[4]:OnClick()
local compact = panel.children[3]
assert(compact.texts[11].text == "Total Air Time" and compact.texts[12].text == "02:05",
    "minimal mode displays the current character's total Air Time")
assert(compact.texts[13].text == "Longest Air Time" and compact.texts[14].text == "2.00 s",
    "minimal mode displays the current character's longest Air Time")
compact.children[3]:OnEnter()
assert(GameTooltip.title == "Past sessions" and #GameTooltip.lines == 11)
assert(GameTooltip.lines[2][1] == date("%Y-%m-%d %H:%M", stats.history[1].time) and GameTooltip.lines[2][2] == "1")
compact.children[3]:OnLeave()
compact.children[4]:OnEnter()
assert(#GameTooltip.lines == 1 and GameTooltip.lines[1][2] == "60", "compact hourly tooltip")
compact.children[4]:OnLeave()
compact.children[2]:OnEnter()
assert(GameTooltip.lines[1][1] == "Alpha-HomeRealm" and GameTooltip.lines[1][2] == "82")
compact.children[2]:OnLeave()
SlashCmdList.JUMPMASTER6000()

assert(not bar:IsShown())
editCallbacks["EditMode.Enter"]()
local selection = bar.children[1]
assert(bar:IsShown() and selection:IsShown() and selection.template == "EditModeSystemSelectionTemplate")
assert(bar.texts[2].text == "0.00 s", "the preview is separate from active Air Time")
selection:OnDragStart()
assert(bar.moving)
bar.x, bar.y = UIParent.x + 90, UIParent.y - 150
selection:OnDragStop()
assert(not bar.moving and bar.points.CENTER[3] == 90 and bar.points.CENTER[4] == -150)
Airborne(true)
now = now + 2
events:OnUpdate()
assert(bar.texts[2].text == "0.00 s")
editCallbacks["EditMode.Exit"]()
assert(bar:IsShown() and not selection:IsShown() and bar.texts[2].text == "2.00 s")
Airborne(false)
events:OnEvent("PLAYER_LOGOUT")

guid, now = "Player-B", now + 1
Load()
assert(bar.points.CENTER[3] == 90 and bar.points.CENTER[4] == -150 and not bar:IsShown())
assert(#JumpMaster6000DB.sessions[guid].history == 0 and #stats.history == 10)
editCallbacks["EditMode.Enter"]()
editCallbacks["EditMode.Exit"]()
assert(not bar:IsShown(), "the inactive bar hides when Edit Mode closes")
print("JumpMaster6000 Lua 5.1 smoke checks passed")
