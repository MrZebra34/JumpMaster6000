local _, addon = ...

local events = CreateFrame("Frame")
local db, character, refresh
local airtime, showAirtime
local airtimeStarted, hideAirtimeAt
local airtimeHeight, airtimeDescending, airJumpRequested
local characterJumps, accountJumps, sessionJumps = 0, 0, 0
local sessionStarted, lastJump
local wasAirborne, groundedSince
local jumpRequested, jumpFromSurface, pendingTakeoff
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
    -- A fall can end on a lethal impact.
    return not (UnitOnTaxi("player") or IsFlying() or UnitInVehicle("player")
        or (not landing and UnitIsDead("player")))
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
    if type(height) ~= "number" or (issecretvalue and issecretvalue(height)) then
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

local function RecordTakeoff(now)
    if not SpendJumpCredit(now) then
        return
    end
    lastJump = now
    characterJumps = characterJumps + 1
    accountJumps = accountJumps + 1
    sessionJumps = sessionJumps + 1
    db.jumps[character] = characterJumps
    refresh()
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
    local swimming = IsSwimming()
    local movementAllowed = CanTrackMovement(landed)
    local canTrack = movementAllowed and (landed or not swimming)
    if jumpFromSurface and (not movementAllowed or IsSubmerged()) then
        jumpRequested, jumpFromSurface = nil, nil
    end
    local withinWindow = jumpRequested and now - jumpRequested <= takeoffWindow
    -- Swimming and falling can overlap briefly as a jump clears the surface.
    local surfaceTakeoff = jumpFromSurface and withinWindow and airborne and canTrack
    TrackAirtime(now, airborne, tookOff or surfaceTakeoff, canTrack)

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
    if withinWindow and (not airborne or (jumpFromSurface and swimming)) then
        return
    end
    jumpRequested, jumpFromSurface = nil, nil

    -- shortcut: a simultaneous ledge fall can resemble takeoff. Use a native jump event if one becomes available.
    if withinWindow and (tookOff or surfaceTakeoff) and canTrack then
        if groundedSince and now < groundedSince + stableGroundTime then
            -- A short landing can be real. Wait for the airborne flag to stay true.
            pendingTakeoff = now
        else
            RecordTakeoff(now)
        end
    end
end

hooksecurefunc("JumpOrAscendStart", function()
    if wasAirborne then
        if not IsFalling() then
            CheckMovement()
        elseif airtimeStarted then
            airJumpRequested = GetTime()
        end
    end
    -- Use the previous frame's state because the original action may have started takeoff already.
    if wasAirborne ~= nil and not jumpRequested then
        local swimming = IsSwimming()
        if (not wasAirborne or (swimming and not airtimeStarted)) and CanTrackMovement() and not IsSubmerged() then
            jumpRequested, jumpFromSurface = GetTime(), swimming
        end
    end
end)

events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_LEAVING_WORLD")
events:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LEAVING_WORLD" then
        wasAirborne, groundedSince = nil, nil
        jumpRequested, jumpFromSurface, pendingTakeoff = nil, nil, nil
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
