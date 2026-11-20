local _, addon = ...

local events = CreateFrame("Frame")
local db, character, refresh
local characterJumps, accountJumps, sessionJumps = 0, 0, 0
local sessionStarted, lastJump
local wasAirborne, jumpRequested
local takeoffWindow = 0.25

local function ReadStats()
    local now = GetTime()
    local elapsed = now - sessionStarted
    local pace = elapsed >= 1 and math.floor(sessionJumps * 3600 / elapsed + 0.5) or 0
    return characterJumps, accountJumps, sessionJumps, pace, math.floor(now - lastJump)
end

local function CanCountJump()
    return not (IsSwimming() or IsFlying() or UnitOnTaxi("player")
        or UnitInVehicle("player") or UnitIsDead("player"))
end

local function CheckTakeoff()
    local airborne = not not IsFalling()
    local tookOff = airborne and not wasAirborne
    wasAirborne = airborne
    if not jumpRequested then
        return
    end

    local now = GetTime()
    local withinWindow = now - jumpRequested <= takeoffWindow
    if not airborne and withinWindow then
        return
    end
    jumpRequested = nil

    -- shortcut: a simultaneous ledge fall can resemble takeoff. Use a native jump event if one becomes available.
    if withinWindow and tookOff and CanCountJump() then
        characterJumps = characterJumps + 1
        accountJumps = accountJumps + 1
        sessionJumps = sessionJumps + 1
        db.jumps[character] = characterJumps
        lastJump = now
        refresh()
    end
end

hooksecurefunc("JumpOrAscendStart", function()
    -- Use the previous frame's state because the original action may have started takeoff already.
    if wasAirborne == false and CanCountJump() then
        jumpRequested = jumpRequested or GetTime()
    end
end)

events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_LEAVING_WORLD")
events:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LEAVING_WORLD" then
        wasAirborne, jumpRequested = nil, nil
        self:SetScript("OnUpdate", nil)
        return
    end

    if not character then
        character = UnitGUID("player")
        if not character then
            return
        end

        db = type(JumpMaster6000DB) == "table" and JumpMaster6000DB or {}
        JumpMaster6000DB = db
        db.jumps = type(db.jumps) == "table" and db.jumps or {}
        for guid, count in pairs(db.jumps) do
            if type(count) == "number" and count >= 0 and count < math.huge then
                accountJumps = accountJumps + count
                if guid == character then
                    characterJumps = count
                end
            end
        end
        sessionStarted = GetTime()
        lastJump = sessionStarted
        refresh = addon.CreatePanel(db, ReadStats)
    end

    wasAirborne = not not IsFalling()
    self:SetScript("OnUpdate", CheckTakeoff)
end)
