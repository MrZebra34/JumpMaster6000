local _, addon = ...

local events = CreateFrame("Frame")
local db, character, refresh
local characterJumps, accountJumps, sessionJumps = 0, 0, 0
local sessionStarted, lastJump
local wasAirborne, jumpRequested
local recentJumps, lastSettledJump = {}, nil
local burstWarnedAt, lastAcceptedTakeoff
local devBypass = false
local takeoffWindow = 0.25
local minimumTakeoffSpacing = 0.25
local burstLimit, burstWindow, pauseDuration = 8, 3, 60
local warningGrace, warningWindow = 3, 15
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
    print("JumpMaster6000 removed a burst of jumps and paused jump credit for 1 minute.")
    local media = LibStub and LibStub("LibSharedMedia-3.0", true)
    local sound = media and media:Fetch("sound", "Big Yankie Devil", true)
    sound = sound or [[Interface\AddOns\ElvUI\Game\Shared\Media\Sounds\YankieBangBang.ogg]]
    if not PlaySoundFile(sound, "SFX") then
        PlaySound(SOUNDKIT.RAID_WARNING, "SFX")
    end
end

local function GetJumpCredit(now)
    if lastAcceptedTakeoff and now < lastAcceptedTakeoff + minimumTakeoffSpacing then
        return 0
    end

    if db.jumpCreditPausedAt then
        if GetServerTime() < db.jumpCreditPausedAt + pauseDuration then
            return 0
        end
        db.jumpCreditPausedAt = nil
    end

    -- A repeat burst must start after the grace period.
    if burstWarnedAt and now < burstWarnedAt + warningGrace then
        lastSettledJump = now
        return 1
    end

    while recentJumps[1] and now >= recentJumps[1] + burstWindow do
        lastSettledJump = table.remove(recentJumps, 1)
    end

    if #recentJumps == burstLimit - 1 then
        local credit = -#recentJumps
        recentJumps = {}
        if not burstWarnedAt or now >= burstWarnedAt + warningWindow then
            burstWarnedAt, lastSettledJump = now, now
            print("JumpMaster6000 saw a fast burst. Slow down to avoid a jump credit pause.")
            return 1
        end

        -- The triggering jump is uncredited. Undo only the already counted jumps inside the window.
        burstWarnedAt = nil
        db.jumpCreditPausedAt = GetServerTime()
        return credit
    end

    recentJumps[#recentJumps + 1] = now
    return 1
end

local function RecordTakeoff(now)
    local credit = devBypass and 1 or GetJumpCredit(now)
    if credit == 0 then
        return
    end
    if credit > 0 then
        lastAcceptedTakeoff = now
    end
    lastJump = credit > 0 and now or lastSettledJump
    characterJumps = characterJumps + credit
    accountJumps = accountJumps + credit
    sessionJumps = sessionJumps + credit
    db.jumps[character] = characterJumps
    refresh()

    if credit < 0 then
        AnnouncePause()
    end
end

function addon.ToggleDevBypass()
    devBypass = not devBypass
    recentJumps, lastSettledJump = {}, lastJump
    burstWarnedAt, lastAcceptedTakeoff = nil, nil
    print(devBypass and "JumpMaster6000 developer bypass enabled." or "JumpMaster6000 developer bypass disabled.")
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
        lastAcceptedTakeoff = nil
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
        -- v0.3.2 saved the expiry of a 300-second pause.
        local oldPauseEnd = tonumber(db.jumpCreditPausedUntil)
        db.jumpCreditPausedAt = tonumber(db.jumpCreditPausedAt) or (oldPauseEnd and oldPauseEnd - 300)
        db.jumpCreditPausedUntil = nil
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
