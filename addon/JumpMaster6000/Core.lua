local _, addon = ...

local events = CreateFrame("Frame")
local db, character, refresh
local characterJumps, accountJumps, sessionJumps = 0, 0, 0
local sessionStarted, lastJump
local wasAirborne, jumpRequested
local recentJumps, lastSettledJump = {}, nil
local takeoffWindow = 0.25
local burstLimit, burstWindow, pauseDuration = 4, 1, 300
local jumpDataVersion = 1

local function ReadStats()
    local now = GetTime()
    local elapsed = now - sessionStarted
    local pace = elapsed >= 1 and math.floor(sessionJumps * 3600 / elapsed + 0.5) or 0
    return characterJumps, accountJumps, sessionJumps, pace, math.floor(now - (lastJump or sessionStarted))
end

local function CanCountJump()
    return not (IsSwimming() or IsFlying() or UnitOnTaxi("player")
        or UnitInVehicle("player") or UnitIsDead("player"))
end

local function AnnouncePause()
    print("JumpMaster6000 removed a burst of jumps and paused jump credit for 5 minutes.")
    local media = LibStub and LibStub("LibSharedMedia-3.0", true)
    local sound = media and media:Fetch("sound", "Big Yankie Devil", true)
    sound = sound or [[Interface\AddOns\ElvUI\Game\Shared\Media\Sounds\YankieBangBang.ogg]]
    if not PlaySoundFile(sound, "SFX") then
        PlaySound(SOUNDKIT.RAID_WARNING, "SFX")
    end
end

local function RecordTakeoff(now)
    if db.jumpCreditPausedUntil then
        if GetServerTime() < db.jumpCreditPausedUntil then
            return
        end
        db.jumpCreditPausedUntil = nil
    end

    while recentJumps[1] and now >= recentJumps[1] + burstWindow do
        lastSettledJump = table.remove(recentJumps, 1)
    end

    local credit = 1
    if #recentJumps == burstLimit - 1 then
        -- The triggering jump is uncredited. Undo only the already counted jumps inside the window.
        credit = -#recentJumps
        recentJumps = {}
        lastJump = lastSettledJump
        db.jumpCreditPausedUntil = GetServerTime() + pauseDuration
    else
        recentJumps[#recentJumps + 1] = now
        lastJump = now
    end
    characterJumps = characterJumps + credit
    accountJumps = accountJumps + credit
    sessionJumps = sessionJumps + credit
    db.jumps[character] = characterJumps
    refresh()

    if credit < 0 then
        AnnouncePause()
    end
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
        RecordTakeoff(now)
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
        if type(db.jumpDataVersion) ~= "number" or db.jumpDataVersion < jumpDataVersion then
            db.jumps = {}
            db.jumpDataVersion = jumpDataVersion
        end
        db.jumps = type(db.jumps) == "table" and db.jumps or {}
        db.jumpCreditPausedUntil = tonumber(db.jumpCreditPausedUntil)
        for guid, count in pairs(db.jumps) do
            if type(count) == "number" and count >= 0 and count < math.huge then
                accountJumps = accountJumps + count
                if guid == character then
                    characterJumps = count
                end
            end
        end
        sessionStarted = GetTime()
        refresh = addon.CreatePanel(db, ReadStats)
    end

    wasAirborne = not not IsFalling()
    self:SetScript("OnUpdate", CheckTakeoff)
end)
