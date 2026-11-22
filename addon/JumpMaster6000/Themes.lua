local _, addon = ...

-- Forever identifies the three talent trees by trait group ID.
local groups = {
    [11328] = "Druid-Balance",
    [11347] = "Druid-Feral-Combat",
    [11340] = "Druid-Restoration",
    [11372] = "Hunter-Beast-Mastery",
    [11371] = "Hunter-Marksmanship",
    [11370] = "Hunter-Survival",
    [11582] = "Mage-Arcane",
    [11594] = "Mage-Fire",
    [11601] = "Mage-Frost",
    [11486] = "Paladin-Holy",
    [11541] = "Paladin-Protection",
    [11559] = "Paladin-Retribution",
    [11608] = "Priest-Discipline",
    [11615] = "Priest-Holy",
    [11622] = "Priest-Shadow",
    [11580] = "Rogue-Assassination",
    [11573] = "Rogue-Combat",
    [11572] = "Rogue-Subtlety",
    [11326] = "Shaman-Elemental-Combat",
    [11363] = "Shaman-Enhancement",
    [11362] = "Shaman-Restoration",
    [11629] = "Warlock-Affliction",
    [11636] = "Warlock-Demonology",
    [11637] = "Warlock-Destruction",
    [11650] = "Warrior-Arms",
    [11657] = "Warrior-Fury",
    [11670] = "Warrior-Protection",
}

local textures = { original = "ShadowPriest" }
local names = {}
for _, name in pairs(groups) do
    textures[name:lower()] = name
    names[#names + 1] = name
end
table.sort(names)
textures["druid-restoration"] = "RestorationDruid"
addon.ThemeTextures = textures
addon.ThemeNames = names

function addon.AutomaticTheme()
    if not C_ClassTalents or not C_Traits then
        return
    end
    local configID = C_ClassTalents.GetActiveConfigID()
    local config = configID and C_Traits.GetConfigInfo(configID)
    local treeID = config and config.treeIDs and config.treeIDs[1]
    if not treeID then
        return
    end

    local ids = {}
    for _, group in ipairs(C_Traits.GetGroupDisplayInfoByTreeID(treeID) or {}) do
        if groups[group.groupID] then
            ids[#ids + 1] = group.groupID
        end
    end
    if #ids ~= 3 then
        return
    end

    -- Forever omits currency rows for talent trees with no spent points.
    local rows = C_Traits.GetGroupCurrencyInfo(configID, ids) or {}
    local best, winner = 0, nil
    for _, group in ipairs(rows) do
        local name = groups[group.traitNodeGroupID]
        local currency = group.currencyInfos and group.currencyInfos[1]
        local points = currency and currency.spent
        if not name or type(points) ~= "number" then
            return
        end
        if points > best then
            best, winner = points, name
        elseif points == best then
            winner = nil
        end
    end
    return winner and textures[winner:lower()]
end
