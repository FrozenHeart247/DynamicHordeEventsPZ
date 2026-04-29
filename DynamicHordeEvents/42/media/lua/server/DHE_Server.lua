-- Dynamic Horde Events B42
-- Server-side event logic + sandbox-gated debug commands.

require "DHE_Config"

DynamicHordeEvents.Server = DynamicHordeEvents.Server or {}

local nextSpawnHour = nil
local lastSpawnHour = -999999

local function clampRange(minValue, maxValue)
    minValue = math.floor(tonumber(minValue) or 0)
    maxValue = math.floor(tonumber(maxValue) or minValue)
    if maxValue < minValue then maxValue = minValue end
    return minValue, maxValue
end

local function randomBetween(minValue, maxValue)
    minValue, maxValue = clampRange(minValue, maxValue)
    if maxValue <= minValue then return minValue end
    return ZombRand(minValue, maxValue + 1)
end


local function getWorldDaysSurvived()
    local hours = 0
    pcall(function() hours = getGameTime():getWorldAgeHours() end)
    return math.max(0, (tonumber(hours) or 0) / 24.0)
end

local function getHordeScalingMultiplier()
    local mode = math.floor(DynamicHordeEvents.GetNumber("ScalingMode"))
    if mode <= 1 then return 1.0, 0, 0 end

    local daysSurvived = getWorldDaysSurvived()
    local unitsSurvived = daysSurvived
    if mode == 3 then
        unitsSurvived = daysSurvived / 30.0
    end

    local interval = math.max(1, DynamicHordeEvents.GetNumber("ScalingInterval"))
    local steps = math.floor(unitsSurvived / interval)
    if steps <= 0 then return 1.0, steps, daysSurvived end

    local perStepPercent = math.max(0, DynamicHordeEvents.GetNumber("ScalingMultiplierPercent"))
    local maxPercent = math.max(100, DynamicHordeEvents.GetNumber("ScalingMaxMultiplierPercent"))
    local totalPercent = 100 + (steps * perStepPercent)
    if totalPercent > maxPercent then totalPercent = maxPercent end

    return totalPercent / 100.0, steps, daysSurvived
end

local function applyHordeScaling(baseCount)
    baseCount = math.max(1, math.floor(tonumber(baseCount) or 1))
    local multiplier, steps, daysSurvived = getHordeScalingMultiplier()
    local scaled = math.max(1, math.floor((baseCount * multiplier) + 0.5))
    return scaled, multiplier, steps, daysSurvived
end

local function sendDebug(player, text)
    if not DynamicHordeEvents.GetBool("Debug") then return end

    text = tostring(text)
    DynamicHordeEvents.Log(text)
    if player then
        pcall(function()
            sendServerCommand(player, DynamicHordeEvents.CommandModule, "DebugMessage", { text = text })
        end)
    end
end

local function isNightTime()
    local hour = getGameTime():getHour()
    local nightStart = DynamicHordeEvents.GetNumber("NightStartHour")
    local nightEnd = DynamicHordeEvents.GetNumber("NightEndHour")

    if nightStart > nightEnd then
        return hour >= nightStart or hour <= nightEnd
    end
    return hour >= nightStart and hour <= nightEnd
end

local function scheduleNextSpawn(playerForDebug)
    local minHours = DynamicHordeEvents.GetNumber("MinSpawnHours")
    local maxHours = DynamicHordeEvents.GetNumber("MaxSpawnHours")
    local delay = randomBetween(minHours, maxHours)

    nextSpawnHour = getGameTime():getWorldAgeHours() + delay
    sendDebug(playerForDebug, "DHE: next random horde in " .. tostring(delay) .. " hour(s). targetWorldHour=" .. tostring(nextSpawnHour))
end

local function getPlayerList()
    local players = {}

    if isServer and isServer() then
        local onlinePlayers = getOnlinePlayers()
        if onlinePlayers then
            for i = 0, onlinePlayers:size() - 1 do
                local player = onlinePlayers:get(i)
                if player and not player:isDead() then
                    table.insert(players, player)
                end
            end
        end
    else
        local numPlayers = 1
        pcall(function() numPlayers = getNumActivePlayers() end)
        for i = 0, numPlayers - 1 do
            local player = getSpecificPlayer(i)
            if player and not player:isDead() then
                table.insert(players, player)
            end
        end
    end

    return players
end

local function pickTargetPlayer()
    local players = getPlayerList()
    if #players == 0 then return nil end
    return players[randomBetween(1, #players)]
end

local function squareIsUsable(square)
    if not square then return false end
    local solid = false
    pcall(function() solid = square:isSolid() end)
    if solid then return false end
    pcall(function() solid = square:isSolidTrans() end)
    if solid then return false end
    if DynamicHordeEvents.GetBool("AvoidIndoorSpawn") then
        local room = nil
        pcall(function() room = square:getRoom() end)
        if room then return false end
    end
    return true
end

local function findSpawnSquare(player, forceNear)
    local playerSquare = player:getSquare()
    if not playerSquare then return nil end

    local minRadius = DynamicHordeEvents.GetNumber("MinSpawnRadius")
    local maxRadius = DynamicHordeEvents.GetNumber("MaxSpawnRadius")
    local attempts = DynamicHordeEvents.GetNumber("SpawnSearchAttempts")

    if forceNear then
        minRadius = DynamicHordeEvents.GetNumber("TestSpawnRadius")
        maxRadius = minRadius
        attempts = 24
    end

    local z = playerSquare:getZ()

    for _ = 1, attempts do
        local radius = randomBetween(minRadius, maxRadius)
        local angle = ZombRandFloat(0.0, math.pi * 2.0)
        local x = math.floor(playerSquare:getX() + math.cos(angle) * radius)
        local y = math.floor(playerSquare:getY() + math.sin(angle) * radius)
        local square = getCell():getGridSquare(x, y, z)
        if squareIsUsable(square) then return square end
    end

    -- Fallback: player square offset. This may be less clean but helps debugging.
    local radius = minRadius
    for ox = -radius, radius do
        for oy = -radius, radius do
            if math.abs(ox) + math.abs(oy) >= math.max(5, math.floor(radius / 2)) then
                local square = getCell():getGridSquare(playerSquare:getX() + ox, playerSquare:getY() + oy, z)
                if squareIsUsable(square) then return square end
            end
        end
    end

    return nil
end

local function attractHordeToPlayer(player)
    local radius = DynamicHordeEvents.GetNumber("AttractionRadius")
    local volume = DynamicHordeEvents.GetNumber("AttractionVolume")
    local ok, err = pcall(function()
        addSound(player, player:getX(), player:getY(), player:getZ(), radius, volume)
    end)
    if not ok then
        sendDebug(player, "DHE: addSound failed: " .. tostring(err))
    end
end

local function spawnZombieAt(x, y, z)
    local success = false
    local lastErr = nil

    local variants = {
        function() addZombiesInOutfit(x, y, z, 1, nil, nil) end,
        function() addZombiesInOutfit(x, y, z, 1, nil, 0) end,
        function() addZombie(x, y, z, nil, 0, IsoDirections.S) end,
    }

    for _, fn in ipairs(variants) do
        local ok, err = pcall(fn)
        if ok then
            success = true
            break
        else
            lastErr = err
        end
    end

    return success, lastErr
end

local function notifyPlayer(player, sx, sy, sz, count)
    local payload = {
        x = sx,
        y = sy,
        z = sz,
        count = count,
    }

    local delivered = false

    -- MP/dedicated-server path: targeted server command to the selected player.
    local okTargeted, errTargeted = pcall(function()
        sendServerCommand(player, DynamicHordeEvents.CommandModule, "Incoming", payload)
    end)
    if okTargeted then delivered = true end

    -- SP/listen-server fallback: broadcast-style overload. Some B42 SP paths ignore the player overload silently.
    local okBroadcast, errBroadcast = pcall(function()
        sendServerCommand(DynamicHordeEvents.CommandModule, "Incoming", payload)
    end)
    if okBroadcast then delivered = true end

    -- Single-player fallback: do not call Client.SetIncomingTarget directly from server code.
    -- In B42 SP this can play the sound in the wrong context before the HUD target exists.
    -- Instead, drop a pending payload that the client OnTick handler can consume if both sides share globals.
    local okPending, errPending = pcall(function()
        DynamicHordeEvents.PendingIncoming = {
            x = payload.x,
            y = payload.y,
            z = payload.z,
            count = payload.count,
            createdAtMs = getTimestampMs(),
            source = "server-pending-fallback",
        }
    end)
    if okPending then delivered = true end

    if delivered then
        DynamicHordeEvents.DebugPrint("DHE: incoming notification queued/sent for " .. tostring(count) .. " zombies")
    else
        sendDebug(player, "DHE: incoming notification failed: targeted=" .. tostring(errTargeted) .. ", broadcast=" .. tostring(errBroadcast) .. ", pending=" .. tostring(errPending))
    end
end

local function spawnHorde(player, forceNear, forceCount)
    if not player then return false end

    local spawnSquare = findSpawnSquare(player, forceNear)
    if not spawnSquare then
        sendDebug(player, "DHE: failed to find spawn square. Try outside/open area or reduce test radius.")
        return false
    end

    local baseCount = forceCount or randomBetween(
        DynamicHordeEvents.GetNumber("MinZombies"),
        DynamicHordeEvents.GetNumber("MaxZombies")
    )

    local count = baseCount
    local scalingMultiplier, scalingSteps, daysSurvived = 1.0, 0, 0
    if not forceNear and not forceCount then
        count, scalingMultiplier, scalingSteps, daysSurvived = applyHordeScaling(baseCount)
    end

    local sx = spawnSquare:getX()
    local sy = spawnSquare:getY()
    local sz = spawnSquare:getZ()

    local spawned = 0
    local lastErr = nil

    for _ = 1, count do
        local ox = sx + ZombRand(-4, 5)
        local oy = sy + ZombRand(-4, 5)
        local ok, err = spawnZombieAt(ox, oy, sz)
        if ok then
            spawned = spawned + 1
        else
            lastErr = err
        end
    end

    attractHordeToPlayer(player)
    notifyPlayer(player, sx, sy, sz, spawned)

    lastSpawnHour = getGameTime():getWorldAgeHours()
    scheduleNextSpawn(player)

    local scalingText = ""
    if not forceNear and not forceCount and scalingMultiplier and scalingMultiplier > 1.0 then
        scalingText = " | scaled from " .. tostring(baseCount) .. " x" .. string.format("%.2f", scalingMultiplier) .. " after " .. string.format("%.1f", daysSurvived or 0) .. " days"
    end
    sendDebug(player, "DHE: spawned=" .. tostring(spawned) .. "/" .. tostring(count) .. " at " .. tostring(sx) .. "," .. tostring(sy) .. "," .. tostring(sz) .. scalingText)
    if spawned == 0 and lastErr then
        sendDebug(player, "DHE: spawn API failed: " .. tostring(lastErr))
    end

    return spawned > 0
end

function DynamicHordeEvents.Server.Update()
    if not DynamicHordeEvents.GetBool("Enabled") then return end

    if nextSpawnHour == nil then
        scheduleNextSpawn(nil)
        return
    end

    local currentHour = getGameTime():getWorldAgeHours()
    if currentHour < nextSpawnHour then return end

    local cooldown = DynamicHordeEvents.GetNumber("CooldownHours")
    if currentHour - lastSpawnHour < cooldown then return end

    local player = pickTargetPlayer()
    if not player then return end

    if DynamicHordeEvents.GetBool("DisableAtNight") and isNightTime() then
        sendDebug(player, "DHE: random horde skipped because night spawning is disabled.")
        scheduleNextSpawn(player)
        return
    end

    spawnHorde(player, false, nil)
end

function DynamicHordeEvents.Server.OnClientCommand(module, command, player, args)
    if module ~= DynamicHordeEvents.CommandModule then return end

    if command == "TestSpawnNear" then
        sendDebug(player, "DHE: forced TEST spawn near player requested.")
        spawnHorde(player, true, DynamicHordeEvents.GetNumber("TestZombieCount"))
    elseif command == "ForceSpawn" then
        sendDebug(player, "DHE: forced NORMAL spawn requested.")
        spawnHorde(player, false, nil)
    elseif command == "Status" then
        local currentHour = getGameTime():getWorldAgeHours()
        local multiplier, steps, daysSurvived = getHordeScalingMultiplier()
        sendDebug(player, "DHE status: version=" .. tostring(DynamicHordeEvents.Version) .. ", currentHour=" .. tostring(currentHour) .. ", nextSpawnHour=" .. tostring(nextSpawnHour) .. ", enabled=" .. tostring(DynamicHordeEvents.GetBool("Enabled")) .. ", scalingMode=" .. tostring(DynamicHordeEvents.GetNumber("ScalingMode")) .. ", scalingMultiplier=" .. string.format("%.2f", multiplier) .. ", scalingSteps=" .. tostring(steps) .. ", daysSurvived=" .. string.format("%.1f", daysSurvived or 0))
    end
end

Events.OnClientCommand.Add(DynamicHordeEvents.Server.OnClientCommand)
Events.OnGameStart.Add(function() scheduleNextSpawn(nil) end)
Events.EveryTenMinutes.Add(DynamicHordeEvents.Server.Update)
Events.EveryHours.Add(DynamicHordeEvents.Server.Update)
