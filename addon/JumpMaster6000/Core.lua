local addonName, addon = ...

local events = CreateFrame("Frame")
local db, character, refresh
local airtime, showAirtime
local airtimeStarted, hideAirtimeAt
local airtimeHeight, airtimeDescending, airJumpRequested
local characterJumps, accountJumps, sessionJumps = 0, 0, 0
local sessionStarted, sessionSaved, lastJump
local characterSessions
local activityAt, nextSignal
local signalTimes = {420, 600, 720, 840, 900}
local signalFile = "Interface\\AddOns\\" .. addonName .. "\\Media\\Signal.ogg"
local wasAirborne, wasWet, groundedSince
local jumpRequested, pendingTakeoff
local jumpHeld, jumpInputAt, waterJumpAt, waterContactAt
local takeoffWindow, surfaceExitWindow = 0.25, 0.30
local stableGroundTime, shortContactAirtime = 0.05, 0.20
local duplicateInterval = 0.30
local spotRadius, spotInterval, spotLimit = 0.7, 0.8, 10
local spotX, spotY, spotMap
local spotJumps = 0
local creditsPerSecond = 1.3
local creditCapacity = 3 - creditsPerSecond -- Keeps the burst to two credits per rolling second.
local credits, lastCreditUpdate = creditCapacity, nil
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
    airtimeStarted, hideAirtimeAt = nil, nil
    airtimeHeight, airtimeDescending, airJumpRequested = nil, nil, nil
    showAirtime()
end

local function UpdateAirtime(now, airborne)
    local duration = now - airtimeStarted
    local previousBest = airtime.longest
    local longest = math.max(previousBest, duration)
    local total = airtime.total + duration
    if not airborne then
        airtimeStarted = nil
        airtime.longest, airtime.total = longest, total
    end
    if duration > airtimeThreshold then
        hideAirtimeAt = not airborne and now + airtimeHold or nil
        local progress = previousBest > 0 and math.min(duration / previousBest, 1) or 0
        showAirtime(duration, airborne and previousBest or longest, total, progress)
    end
end

local function RejumpedBetweenSamples(now)
    local _, _, height = UnitPosition("player")
    if not ReadableNumber(height) then
        airtimeHeight, airtimeDescending = nil, nil
        return false
    end

    local change = airtimeHeight and height - airtimeHeight or 0
    airtimeHeight = height
    if change < -0.02 then
        airtimeDescending = true
    elseif change > 0.02 then
        local wasDescending = airtimeDescending
        airtimeDescending = false
        -- A jump press alone can happen mid-fall. A new ascent indicates a re-jump.
        return wasDescending and airJumpRequested and now - airJumpRequested <= takeoffWindow
    end
    return false
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
        if airborne and RejumpedBetweenSamples(now) then
            UpdateAirtime(now, false)
            ResetAirtime()
            airtimeStarted = now
        else
            UpdateAirtime(now, airborne)
        end
    end
    if hideAirtimeAt and now >= hideAirtimeAt then
        hideAirtimeAt = nil
        showAirtime()
    end
end

local function SpendJumpCredit(now)
    local elapsed = now - (lastCreditUpdate or now)
    credits = math.min(creditCapacity, credits + elapsed * creditsPerSecond)
    lastCreditUpdate = now
    if credits < 1 then
        return false
    end

    credits = credits - 1
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

local function RecordTakeoff(now)
    activityAt, nextSignal = now, 1
    if not InSameJumpSpot() then
        spotJumps = 0
    end
    if spotJumps >= spotLimit or (lastJump and now < lastJump + duplicateInterval)
        or (spotJumps > 0 and now < lastJump + spotInterval) then
        return
    end
    if not SpendJumpCredit(now) then
        return
    end
    spotJumps = spotJumps + 1
    lastJump = now
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
        jumpRequested, pendingTakeoff = nil, nil
        if movementAllowed then
            if jumpHeld then
                waterJumpAt = now
            elseif not waterJumpAt and jumpInputAt and now - jumpInputAt <= surfaceExitWindow then
                waterJumpAt = jumpInputAt
            end
        end
    elseif airborne and waterJumpAt then
        waterJumpAt, jumpInputAt = nil, nil
        RecordTakeoff(now)
    elseif not airborne and not waterJumpAt and waterContactAt
        and now >= math.max(waterContactAt, groundedSince or 0) + stableGroundTime then
        -- A dry falling sample can be another water hop. Re-arm Air Time on dry ground.
        waterContactAt = nil
    end
end

local function CheckMovement(now)
    local airborne = not not IsFalling()
    local tookOff = airborne and not wasAirborne
    local landed = wasAirborne and not airborne
    local wet = IsWet()
    local leftWaterOnGround = wasWet and not wet and not airborne
    wasAirborne, wasWet = airborne, wet
    if not (wet or waterContactAt or landed or tookOff or pendingTakeoff or jumpRequested or airtimeStarted or hideAirtimeAt) then
        return
    end

    local movementAllowed = CanTrackMovement(landed)
    if landed or leftWaterOnGround then
        groundedSince = now
    end
    TrackWater(now, wet, airborne, movementAllowed)
    TrackAirtime(now, airborne, tookOff, movementAllowed and not waterContactAt)

    local canTrack = movementAllowed and not wet
    if pendingTakeoff then
        if not airborne or not canTrack then
            pendingTakeoff = nil
        elseif now >= pendingTakeoff + shortContactAirtime then
            local takeoffTime = pendingTakeoff
            pendingTakeoff = nil
            RecordTakeoff(takeoffTime)
        end
    end

    if not jumpRequested then
        return
    end
    local withinWindow = now - jumpRequested <= takeoffWindow
    if not airborne and withinWindow then
        return
    end
    jumpRequested = nil

    -- shortcut: a simultaneous ledge fall can resemble takeoff. Use a native jump event if one becomes available.
    if withinWindow and tookOff and canTrack then
        jumpInputAt = nil
        if groundedSince and now < groundedSince + stableGroundTime then
            -- A short landing can be real. Wait for the airborne flag to stay true.
            pendingTakeoff = now
        else
            RecordTakeoff(now)
        end
    end
end

local function OnUpdate()
    local now = GetTime()
    CheckMovement(now)
    local delay = signalTimes[nextSignal]
    if delay and now - activityAt >= delay then
        repeat
            nextSignal = nextSignal + 1
            delay = signalTimes[nextSignal]
        until not delay or now - activityAt < delay
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
            airJumpRequested = now
        end
    end
    if wasAirborne ~= nil and CanTrackMovement() then
        jumpHeld, jumpInputAt = true, now
        if fromWater then
            waterJumpAt, jumpRequested, pendingTakeoff = now, nil, nil
        elseif not wasAirborne then
            waterJumpAt = nil
            jumpRequested = jumpRequested or now
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
        jumpRequested, pendingTakeoff = nil, nil
        jumpHeld, jumpInputAt, waterJumpAt, waterContactAt = nil, nil, nil, nil
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
        activityAt, nextSignal = sessionStarted, 1
        refresh = addon.CreatePanel(db, ReadStats, characterSessions.history, ReadCharacterPace)
        showAirtime = addon.CreateAirtimeBar(db, airtime)
    end

    wasAirborne, wasWet, groundedSince = not not IsFalling(), IsWet(), nil
    self:SetScript("OnUpdate", OnUpdate)
end)
