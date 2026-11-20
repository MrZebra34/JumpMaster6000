local _, addon = ...

local events = CreateFrame("Frame")
local db, character, refresh
local airtime, showAirtime
local airtimeStarted, hideAirtimeAt
local characterJumps, accountJumps, sessionJumps = 0, 0, 0
local sessionStarted, lastJump
local wasAirborne, groundedSince
local jumpRequested, pendingTakeoff
local devBypass = false
local takeoffWindow = 0.25
local stableGroundTime, shortContactAirtime = 0.05, 0.20
local creditCapacity, creditsPerSecond = 6, 1.5
local credits, lastCreditUpdate = creditCapacity, nil
local jumpDataVersion = 1
local airtimeThreshold, airtimeHold = 1.5, 3

local function ReadStats()
    local now = GetTime()
    local elapsed = now - sessionStarted
    local pace = elapsed >= 1 and math.floor(sessionJumps * 3600 / elapsed + 0.5) or 0
    return characterJumps, accountJumps, sessionJumps, pace, math.floor(now - (lastJump or sessionStarted))
end

local function CanTrackMovement(landing)
    -- A fall can end in water or on a lethal impact.
    return not (UnitOnTaxi("player") or IsFlying() or UnitInVehicle("player")
        or (not landing and (IsSwimming() or UnitIsDead("player"))))
end

local function SavedDuration(seconds)
    return type(seconds) == "number" and seconds >= 0 and seconds < math.huge and seconds or 0
end

local function ResetAirtime()
    airtimeStarted, hideAirtimeAt = nil, nil
    showAirtime()
end

local function TrackAirtime(now, airborne, tookOff, canTrack)
    if not canTrack then
        ResetAirtime()
        return
    end

    if tookOff then
        airtimeStarted = now
    end
    if airtimeStarted then
        local duration = now - airtimeStarted
        local longest = math.max(airtime.longest, duration)
        local total = airtime.total + duration
        if not airborne then
            airtimeStarted = nil
            airtime.longest, airtime.total = longest, total
        end
        if duration > airtimeThreshold then
            hideAirtimeAt = not airborne and now + airtimeHold or nil
            showAirtime(duration, longest, total)
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

local function RecordTakeoff(now)
    if not devBypass and not SpendJumpCredit(now) then
        return
    end
    lastJump = now
    characterJumps = characterJumps + 1
    accountJumps = accountJumps + 1
    sessionJumps = sessionJumps + 1
    db.jumps[character] = characterJumps
    refresh()
end

function addon.ToggleDevBypass()
    devBypass = not devBypass
    pendingTakeoff = nil
    print(devBypass and "JumpMaster6000 developer bypass enabled." or "JumpMaster6000 developer bypass disabled.")
end

local function CheckMovement()
    local airborne = not not IsFalling()
    local tookOff = airborne and not wasAirborne
    local landed = wasAirborne and not airborne
    wasAirborne = airborne
    if not (landed or tookOff or pendingTakeoff or jumpRequested or airtimeStarted or hideAirtimeAt) then
        return
    end

    local now = GetTime()
    local canTrack = CanTrackMovement(landed)
    TrackAirtime(now, airborne, tookOff, canTrack)

    if landed then
        groundedSince = now
    end
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
        if not devBypass and groundedSince and now < groundedSince + stableGroundTime then
            -- A short landing can be real. Wait for the airborne flag to stay true.
            pendingTakeoff = now
        else
            RecordTakeoff(now)
        end
    end
end

hooksecurefunc("JumpOrAscendStart", function()
    -- Use the previous frame's state because the original action may have started takeoff already.
    if wasAirborne == false and CanTrackMovement() then
        jumpRequested = jumpRequested or GetTime()
    end
end)

events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_LEAVING_WORLD")
events:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LEAVING_WORLD" then
        wasAirborne, groundedSince = nil, nil
        jumpRequested, pendingTakeoff = nil, nil
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
        db.jumpCreditPausedAt, db.jumpCreditPausedUntil = nil, nil
        for guid, count in pairs(db.jumps) do
            if type(count) == "number" and count >= 0 and count < math.huge then
                accountJumps = accountJumps + count
                if guid == character then
                    characterJumps = count
                end
            end
        end
        db.airtime = type(db.airtime) == "table" and db.airtime or {}
        airtime = type(db.airtime[character]) == "table" and db.airtime[character] or {}
        airtime.longest = SavedDuration(airtime.longest)
        airtime.total = SavedDuration(airtime.total)
        db.airtime[character] = airtime
        sessionStarted = GetTime()
        refresh = addon.CreatePanel(db, ReadStats)
        showAirtime = addon.CreateAirtimeBar()
    end

    wasAirborne, groundedSince = not not IsFalling(), nil
    self:SetScript("OnUpdate", CheckMovement)
end)
