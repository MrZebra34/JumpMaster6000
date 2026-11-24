local addonName, addon = ...

local events = CreateFrame("Frame")
local db, character, refresh
local airtime, showAirtime
local airtimeStarted, hideAirtimeAt
local characterJumps, accountJumps, sessionJumps = 0, 0, 0
local sessionStarted, sessionSaved, lastJump
local characterSessions
local signalTimes = {420, 600, 720, 840, 900}
local nextSignal = 1
local signalFile = "Interface\\AddOns\\" .. addonName .. "\\Media\\Signal.ogg"
local warningSound = "Interface\\AddOns\\" .. addonName .. "\\Media\\Signal2.ogg"
local pauseSound = "Interface\\AddOns\\" .. addonName .. "\\Media\\Signal3.ogg"
local wasAirborne, wasWet, groundedSince
local jumpRequested
local jumpHeld, jumpInputAt, waterJumpAt, waterContactAt
local takeoffWindow, surfaceExitWindow = 0.25, 0.30
local stableGroundTime = 0.05
local spotRadius, spotLimit = 0.7, 10
-- Same-spot and water takeoffs closer than this to the last credited jump are treated as duplicates.
local minimumSpacing = 0.25
local spotX, spotY, spotMap
local spotJumps = 0
-- Moving jumps: a burst of ten, then at most 100 credits a minute at any cadence.
local dryBudget = {capacity = 10, perSecond = 100 / 60}
-- Sustained spam: warn at 22 and pause all credit for a minute at 30 takeoffs on land within 12 seconds, standing or moving.
local spamWindow, spamWarning, spamLimit, pauseDuration = 12, 22, 30, 60
local spamTakeoffs, spamWarnedAt = {}, nil
local waterBudget = {capacity = 1.7, perSecond = 1.3}
local jumpDataVersion = 1
local airtimeThreshold, airtimeHold = 1.5, 3

local function JumpsPerHour(jumps, seconds)
    return seconds >= 1 and math.floor(jumps * 3600 / seconds + 0.5) or 0
end

local function ReadStats()
    local now = GetTime()
    local pace = JumpsPerHour(sessionJumps, now - sessionStarted)
    return characterJumps, accountJumps, sessionJumps, pace, math.floor(now - (lastJump or sessionStarted))
end

local function ReadCharacterPace()
    if sessionSaved then
        return JumpsPerHour(characterSessions.jumps, characterSessions.seconds)
    end
    return JumpsPerHour(characterSessions.jumps + sessionJumps, characterSessions.seconds + (GetTime() - sessionStarted))
end

function addon.FormatCharacterName(name, realm)
    if name and name ~= "" then
        return name .. "-" .. (realm and realm ~= "" and realm or GetNormalizedRealmName())
    end
end

local function CanTrackMovement(landing)
    -- A fall can end on a lethal impact.
    return not (UnitOnTaxi("player") or IsFlying() or UnitInVehicle("player")
        or (not landing and UnitIsDead("player")))
end

local function IsWet()
    return IsSwimming() or IsSubmerged()
end

local function ReadableNumber(value)
    return type(value) == "number" and not (issecretvalue and issecretvalue(value))
end

local function SavedDuration(seconds)
    return type(seconds) == "number" and seconds >= 0 and seconds < math.huge and seconds or 0
end

local function ResetAirtime()
    if airtimeStarted or hideAirtimeAt then
        airtimeStarted, hideAirtimeAt = nil, nil
        showAirtime()
    end
end

local function UpdateAirtime(now, airborne)
    local duration = now - airtimeStarted
    if not airborne then
        airtimeStarted = nil
    end
    if duration <= airtimeThreshold then
        return
    end

    local previousBest = airtime.longest
    local longest = math.max(previousBest, duration)
    local total = airtime.total + duration
    if not airborne then
        airtime.longest, airtime.total = longest, total
    end
    hideAirtimeAt = not airborne and now + airtimeHold or nil
    local progress = previousBest > 0 and math.min(duration / previousBest, 1) or 0
    showAirtime(duration, airborne and previousBest or longest, total, progress)
end

local function TrackAirtime(now, airborne, tookOff, canTrack)
    if not canTrack then
        ResetAirtime()
        return
    end

    if tookOff then
        ResetAirtime()
        airtimeStarted = now
    end
    if airtimeStarted then
        UpdateAirtime(now, airborne)
    end
    if hideAirtimeAt and now >= hideAirtimeAt then
        hideAirtimeAt = nil
        showAirtime()
    end
end

local function SpendJumpCredit(budget, now)
    local elapsed = now - (budget.updatedAt or now)
    budget.credits = math.min(budget.capacity, (budget.credits or budget.capacity) + elapsed * budget.perSecond)
    budget.updatedAt = now
    if budget.credits < 1 then
        return false
    end

    budget.credits = budget.credits - 1
    return true
end

local function InSameJumpSpot()
    local x, y, _, map = UnitPosition("player")
    if not (ReadableNumber(x) and ReadableNumber(y) and ReadableNumber(map)) then
        -- shortcut: zero speed stands in for a fixed spot when coordinates are unavailable.
        local speed = GetUnitSpeed("player")
        return ReadableNumber(speed) and speed == 0
    end
    if spotMap == map and (x - spotX)^2 + (y - spotY)^2 <= spotRadius^2 then
        return true
    end
    spotX, spotY, spotMap = x, y, map
    return false
end

local function AnnouncePause()
    print("JumpMaster6000 paused jump credit for 1 minute after sustained jump spam.")
    PlaySoundFile(pauseSound, "Master")
end

-- Returns true when this takeoff starts a credit pause.
local function DetectSpam(now)
    while spamTakeoffs[1] and spamTakeoffs[1] <= now - spamWindow do
        table.remove(spamTakeoffs, 1)
    end
    spamTakeoffs[#spamTakeoffs + 1] = now
    if #spamTakeoffs >= spamLimit then
        spamTakeoffs, spamWarnedAt = {}, nil
        db.creditPausedUntil = GetServerTime() + pauseDuration
        AnnouncePause()
        return true
    end
    if #spamTakeoffs >= spamWarning and not (spamWarnedAt and now < spamWarnedAt + spamWindow) then
        spamWarnedAt = now
        print("JumpMaster6000: keep jumping this fast and jump credit pauses for 1 minute.")
        PlaySoundFile(warningSound, "Master")
    end
end

local function RecordTakeoff(now, fromWater)
    if db.creditPausedUntil then
        if GetServerTime() < db.creditPausedUntil then
            return
        end
        db.creditPausedUntil = nil
    end
    if not fromWater and DetectSpam(now) then
        return
    end
    local sameSpot = InSameJumpSpot()
    if not sameSpot then
        spotJumps = 0
    end
    if spotJumps >= spotLimit or ((fromWater or sameSpot) and lastJump and now < lastJump + minimumSpacing) then
        return
    end
    if not SpendJumpCredit(fromWater and waterBudget or dryBudget, now) then
        return
    end
    spotJumps = spotJumps + 1
    lastJump = now
    nextSignal = 1
    characterJumps = characterJumps + 1
    accountJumps = accountJumps + 1
    sessionJumps = sessionJumps + 1
    db.jumps[character] = characterJumps
    refresh()
end

local function TrackWater(now, wet, airborne, movementAllowed)
    if not movementAllowed or (waterJumpAt and now - waterJumpAt > surfaceExitWindow) then
        waterJumpAt = nil
    end

    if wet then
        waterContactAt = now
        jumpRequested = nil
        if movementAllowed then
            if jumpHeld then
                waterJumpAt = now
            elseif not waterJumpAt and jumpInputAt and now - jumpInputAt <= surfaceExitWindow then
                waterJumpAt = jumpInputAt
            end
        end
    elseif airborne and waterJumpAt then
        waterJumpAt, jumpInputAt = nil, nil
        RecordTakeoff(now, true)
    elseif not airborne and waterContactAt
        and now >= math.max(waterContactAt, groundedSince or 0) + stableGroundTime then
        -- A dry falling sample can be another water hop. Re-arm Air Time on dry ground.
        waterContactAt, waterJumpAt, jumpInputAt = nil, nil, nil
    end
end

local function CheckMovement(now)
    local airborne = not not IsFalling()
    local tookOff = airborne and not wasAirborne
    local landed = wasAirborne and not airborne
    local wet = IsWet()
    local leftWaterOnGround = wasWet and not wet and not airborne
    wasAirborne, wasWet = airborne, wet
    if not (wet or waterContactAt or landed or tookOff or jumpRequested or airtimeStarted or hideAirtimeAt) then
        return
    end

    local movementAllowed = CanTrackMovement(landed)
    if landed or leftWaterOnGround then
        groundedSince = now
    end
    TrackWater(now, wet, airborne, movementAllowed)
    TrackAirtime(now, airborne, tookOff, movementAllowed and not waterContactAt)

    if not jumpRequested then
        return
    end
    local withinWindow = now - jumpRequested <= takeoffWindow
    if not airborne and withinWindow then
        return
    end
    jumpRequested = nil

    -- shortcut: a simultaneous ledge fall can resemble takeoff. Use a native jump event if one becomes available.
    if withinWindow and tookOff and movementAllowed and not wet then
        jumpInputAt = nil
        RecordTakeoff(now)
    end
end

local function OnUpdate()
    local now = GetTime()
    CheckMovement(now)
    local idle = now - (lastJump or sessionStarted)
    local delay = signalTimes[nextSignal]
    if delay and idle >= delay then
        repeat
            nextSignal = nextSignal + 1
            delay = signalTimes[nextSignal]
        until not delay or idle < delay
        PlaySoundFile(signalFile, "Master")
    end
end

hooksecurefunc("JumpOrAscendStart", function()
    -- The native action may have left the water before this post-hook runs.
    local fromWater = wasWet or IsWet()
    local now = GetTime()
    if wasAirborne ~= nil and fromWater then
        waterContactAt = now
    end
    if wasAirborne then
        if not IsFalling() then
            CheckMovement(now)
        elseif airtimeStarted then
            -- shortcut: discard a possible missed landing until the client exposes a reliable landing signal.
            ResetAirtime()
        end
    end
    if wasAirborne ~= nil and CanTrackMovement() then
        jumpHeld, jumpInputAt = true, now
        if fromWater then
            waterJumpAt, jumpRequested = now, nil
        elseif not wasAirborne then
            waterJumpAt = nil
            jumpRequested = jumpRequested or now
            if IsFalling() then
                CheckMovement(now)
            end
        end
    end
end)

hooksecurefunc("AscendStop", function()
    jumpHeld = nil
end)

events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_LEAVING_WORLD")
events:RegisterEvent("PLAYER_LOGOUT")
events:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGOUT" then
        if sessionStarted and not sessionSaved then
            sessionSaved = true
            characterSessions.jumps = characterSessions.jumps + sessionJumps
            characterSessions.seconds = characterSessions.seconds + (GetTime() - sessionStarted)
            local history = characterSessions.history
            table.insert(history, 1, {time = GetServerTime(), jumps = sessionJumps})
            history[11] = nil
            self:SetScript("OnUpdate", nil)
        end
        return
    end

    if event == "PLAYER_LEAVING_WORLD" then
        wasAirborne, wasWet, groundedSince = nil, nil, nil
        jumpRequested = nil
        jumpHeld, jumpInputAt, waterJumpAt, waterContactAt = nil, nil, nil, nil
        spotX, spotY, spotMap, spotJumps = nil, nil, nil, 0
        if showAirtime then
            ResetAirtime()
        end
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
        db.names = type(db.names) == "table" and db.names or {}
        db.names[character] = addon.FormatCharacterName(UnitFullName("player")) or db.names[character]
        db.sessions = type(db.sessions) == "table" and db.sessions or {}
        characterSessions = type(db.sessions[character]) == "table" and db.sessions[character] or {}
        characterSessions.jumps = SavedDuration(characterSessions.jumps)
        characterSessions.seconds = SavedDuration(characterSessions.seconds)
        characterSessions.history = type(characterSessions.history) == "table" and characterSessions.history or {}
        db.sessions[character] = characterSessions
        db.jumpCreditPausedAt, db.jumpCreditPausedUntil = nil, nil
        -- Keep an active pause across reloads, but never longer than one pause from now.
        local pausedUntil = tonumber(db.creditPausedUntil)
        db.creditPausedUntil = pausedUntil and math.min(pausedUntil, GetServerTime() + pauseDuration) or nil
        for guid, count in pairs(db.jumps) do
            if type(count) == "number" and count >= 0 and count < math.huge then
                accountJumps = accountJumps + count
                if guid == character then
                    characterJumps = count
                end
            else
                db.jumps[guid] = nil
            end
        end
        db.airtime = type(db.airtime) == "table" and db.airtime or {}
        airtime = type(db.airtime[character]) == "table" and db.airtime[character] or {}
        airtime.longest = SavedDuration(airtime.longest)
        airtime.total = SavedDuration(airtime.total)
        db.airtime[character] = airtime
        sessionStarted = GetTime()
        refresh = addon.CreatePanel(db, ReadStats, characterSessions.history, ReadCharacterPace, airtime)
        showAirtime = addon.CreateAirtimeBar(db, airtime)
    end

    wasAirborne, wasWet, groundedSince = not not IsFalling(), IsWet(), nil
    self:SetScript("OnUpdate", OnUpdate)
end)
