-- Dynamic Horde Events B42
-- Server-side event logic + sandbox-gated debug commands.

require "DHE_Config"

DynamicHordeEvents.Server = DynamicHordeEvents.Server or {}

local nextSpawnHour = nil
local lastSpawnHour = -999999
local nextCataclysmDay = nil
local lastCataclysmDay = -999999
local nextWanderingHour = nil
local lastWanderingHour = -999999
local cataclysmWeatherAdminResetHour = nil

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

local function scheduleNextCataclysm(playerForDebug)
    local minDays = DynamicHordeEvents.GetNumber("CataclysmMinDays")
    local maxDays = DynamicHordeEvents.GetNumber("CataclysmMaxDays")
    local delay = randomBetween(minDays, maxDays)

    nextCataclysmDay = getWorldDaysSurvived() + delay
    sendDebug(playerForDebug, "DHE: next cataclysm horde in " .. tostring(delay) .. " day(s). targetWorldDay=" .. tostring(nextCataclysmDay))
end

local function scheduleNextWandering(playerForDebug)
    local minHours = DynamicHordeEvents.GetNumber("WanderingMinHours")
    local maxHours = DynamicHordeEvents.GetNumber("WanderingMaxHours")
    local delay = randomBetween(minHours, maxHours)

    nextWanderingHour = getGameTime():getWorldAgeHours() + delay
    sendDebug(playerForDebug, "DHE: next wandering horde in " .. tostring(delay) .. " hour(s). targetWorldHour=" .. tostring(nextWanderingHour))
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

local function findSpawnSquareCustom(player, minRadius, maxRadius, attempts)
    local playerSquare = player:getSquare()
    if not playerSquare then return nil end

    minRadius = math.max(10, tonumber(minRadius) or 10)
    maxRadius = math.max(minRadius, tonumber(maxRadius) or minRadius)
    attempts = math.max(1, tonumber(attempts) or 64)

    local px = playerSquare:getX()
    local py = playerSquare:getY()
    local pz = playerSquare:getZ()

    -- B42 only exposes already-loaded grid squares here. A 140-240 tile cataclysm radius
    -- can easily point into unloaded chunks and return nil forever. Try the requested
    -- radius first, then progressively fall back to closer loaded rings.
    local zCandidates = { pz }
    if pz ~= 0 then table.insert(zCandidates, 0) end

    local function tryRandomRing(rMin, rMax, tryCount, strictOutdoor)
        for _, z in ipairs(zCandidates) do
            for _ = 1, tryCount do
                local radius = randomBetween(rMin, rMax)
                local angle = ZombRandFloat(0.0, math.pi * 2.0)
                local x = math.floor(px + math.cos(angle) * radius)
                local y = math.floor(py + math.sin(angle) * radius)
                local square = getCell():getGridSquare(x, y, z)
                if square then
                    if squareIsUsable(square) then return square end
                    if not strictOutdoor then
                        local solid = false
                        pcall(function() solid = square:isSolid() end)
                        if not solid then return square end
                    end
                end
            end
        end
        return nil
    end

    -- 1) requested cataclysm distance
    local square = tryRandomRing(minRadius, maxRadius, attempts, true)
    if square then return square end

    -- 2) normal horde distance, usually more likely to be loaded
    square = tryRandomRing(
        DynamicHordeEvents.GetNumber("MinSpawnRadius"),
        DynamicHordeEvents.GetNumber("MaxSpawnRadius"),
        attempts,
        true
    )
    if square then return square end

    -- 3) closer emergency distance for debug / dense towns / indoor starts
    square = tryRandomRing(35, math.max(60, math.floor(minRadius / 2)), attempts, true)
    if square then return square end

    -- 4) last resort: allow non-solid indoor/covered squares, otherwise the whole event dies.
    square = tryRandomRing(20, math.max(40, math.floor(minRadius / 3)), attempts, false)
    if square then return square end

    return nil
end

local function findNearbySpawnableSquare(x, y, z, spread)
    spread = math.max(1, math.floor(tonumber(spread) or 1))

    local square = getCell():getGridSquare(x, y, z)
    if squareIsUsable(square) then return square end

    for _ = 1, 8 do
        local ox = x + ZombRand(-spread, spread + 1)
        local oy = y + ZombRand(-spread, spread + 1)
        square = getCell():getGridSquare(ox, oy, z)
        if squareIsUsable(square) then return square end
    end

    -- fallback for indoor/covered loaded cells: non-solid is better than spawning nothing.
    square = getCell():getGridSquare(x, y, z)
    if square then
        local solid = false
        pcall(function() solid = square:isSolid() end)
        if not solid then return square end
    end

    return nil
end

local function findUsableSquareNearPoint(x, y, z, spread, allowIndoorFallback)
    spread = math.max(1, math.floor(tonumber(spread) or 1))

    local square = getCell():getGridSquare(math.floor(x), math.floor(y), z)
    if squareIsUsable(square) then return square end

    for _ = 1, 40 do
        local ox = math.floor(x + ZombRand(-spread, spread + 1))
        local oy = math.floor(y + ZombRand(-spread, spread + 1))
        square = getCell():getGridSquare(ox, oy, z)
        if squareIsUsable(square) then return square end
    end

    if allowIndoorFallback then
        for _ = 1, 20 do
            local ox = math.floor(x + ZombRand(-spread, spread + 1))
            local oy = math.floor(y + ZombRand(-spread, spread + 1))
            square = getCell():getGridSquare(ox, oy, z)
            if square then
                local solid = false
                pcall(function() solid = square:isSolid() end)
                if not solid then return square end
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

local function attractCataclysmToPlayer(player)
    local radius = DynamicHordeEvents.GetNumber("CataclysmAttractionRadius")
    local volume = DynamicHordeEvents.GetNumber("CataclysmAttractionVolume")
    local ok, err = pcall(function()
        addSound(player, player:getX(), player:getY(), player:getZ(), radius, volume)
    end)
    if not ok then
        sendDebug(player, "DHE: cataclysm addSound failed: " .. tostring(err))
    end
end

local function attractWanderingToExitPoint(player, targetX, targetY, targetZ)
    local radius = DynamicHordeEvents.GetNumber("WanderingAttractionRadius")
    local volume = DynamicHordeEvents.GetNumber("WanderingAttractionVolume")
    local ok, err = pcall(function()
        addSound(player, targetX, targetY, targetZ, radius, volume)
    end)
    if not ok then
        sendDebug(player, "DHE: wandering addSound failed: " .. tostring(err))
    else
        sendDebug(player, "DHE: wandering attraction point at " .. tostring(math.floor(targetX)) .. "," .. tostring(math.floor(targetY)) .. "," .. tostring(targetZ) .. " radius=" .. tostring(radius))
    end
end

local function getClimateFloatConstant(cm, name, fallback)
    local value = nil

    if ClimateManager and ClimateManager[name] ~= nil then
        value = ClimateManager[name]
    elseif cm and cm[name] ~= nil then
        value = cm[name]
    end

    if value == nil then value = fallback end
    return value
end

local function setClimateAdminFloat(player, cm, label, id, value)
    if not cm or id == nil then
        sendDebug(player, "DHE: cataclysm weather admin skipped: " .. tostring(label) .. " id=nil")
        return false
    end

    local ok, err = pcall(function()
        local cf = cm:getClimateFloat(id)
        if not cf then error("climate float is nil") end

        if cf.setAdminValue then
            cf:setAdminValue(value)
        elseif cf.setOverride then
            cf:setOverride(value)
        elseif cf.setModdedValue then
            cf:setModdedValue(value)
        else
            error("no supported setter")
        end

        if cf.setEnableAdmin then
            cf:setEnableAdmin(true)
        elseif cf.setEnableOverride then
            cf:setEnableOverride(true)
        elseif cf.setEnableModded then
            cf:setEnableModded(true)
        end
    end)

    if ok then
        sendDebug(player, "DHE: cataclysm weather admin ok: " .. tostring(label) .. "=" .. tostring(value))
        return true
    end

    sendDebug(player, "DHE: cataclysm weather admin failed: " .. tostring(label) .. " | " .. tostring(err))
    return false
end

local function resetCataclysmWeatherOverrides(player)
    local cm = nil
    if getClimateManager then
        local ok, result = pcall(function() return getClimateManager() end)
        if ok then cm = result end
    end
    if not cm then return end

    local ids = {
        getClimateFloatConstant(cm, "FLOAT_FOG_INTENSITY", 5),
        getClimateFloatConstant(cm, "FLOAT_WIND_INTENSITY", 6),
        getClimateFloatConstant(cm, "FLOAT_WIND_ANGLE_INTENSITY", 7),
        getClimateFloatConstant(cm, "FLOAT_CLOUD_INTENSITY", 8),
        getClimateFloatConstant(cm, "FLOAT_DESATURATION", 0),
        getClimateFloatConstant(cm, "FLOAT_VIEW_DISTANCE", 10),
    }

    for _, id in ipairs(ids) do
        pcall(function()
            local cf = cm:getClimateFloat(id)
            if cf then
                if cf.setEnableAdmin then cf:setEnableAdmin(false) end
                if cf.setEnableOverride then cf:setEnableOverride(false) end
                if cf.setEnableModded then cf:setEnableModded(false) end
            end
        end)
    end

    pcall(function()
        if cm.transmitClientChangeAdminVars then
            cm:transmitClientChangeAdminVars()
        end
    end)

    cataclysmWeatherAdminResetHour = nil
    sendDebug(player, "DHE: cataclysm fog/wind admin overrides reset.")
end

local function applyCataclysmFogWindOverrides(player, cm, duration)
    if not DynamicHordeEvents.GetBool("EnableCataclysmFogWind") then return end
    if not cm then return end

    local fog = DynamicHordeEvents.GetNumber("CataclysmFogIntensity")
    local wind = DynamicHordeEvents.GetNumber("CataclysmWindIntensity")
    local clouds = DynamicHordeEvents.GetNumber("CataclysmCloudIntensity")
    local desat = DynamicHordeEvents.GetNumber("CataclysmDesaturation")

    if fog < 0 then fog = 0 elseif fog > 1 then fog = 1 end
    if wind < 0 then wind = 0 elseif wind > 1 then wind = 1 end
    if clouds < 0 then clouds = 0 elseif clouds > 1 then clouds = 1 end
    if desat < 0 then desat = 0 elseif desat > 1 then desat = 1 end

    setClimateAdminFloat(player, cm, "fog", getClimateFloatConstant(cm, "FLOAT_FOG_INTENSITY", 5), fog)
    setClimateAdminFloat(player, cm, "wind", getClimateFloatConstant(cm, "FLOAT_WIND_INTENSITY", 6), wind)
    setClimateAdminFloat(player, cm, "windAngle", getClimateFloatConstant(cm, "FLOAT_WIND_ANGLE_INTENSITY", 7), 1.0)
    setClimateAdminFloat(player, cm, "clouds", getClimateFloatConstant(cm, "FLOAT_CLOUD_INTENSITY", 8), clouds)
    setClimateAdminFloat(player, cm, "desaturation", getClimateFloatConstant(cm, "FLOAT_DESATURATION", 0), desat)

    -- Lower view distance a bit during the cataclysm if fog is high. This is safe-wrapped by setClimateAdminFloat.
    if fog >= 0.60 then
        setClimateAdminFloat(player, cm, "viewDistance", getClimateFloatConstant(cm, "FLOAT_VIEW_DISTANCE", 10), 0.45)
    end

    if getGameTime then
        local currentHour = getGameTime():getWorldAgeHours()
        cataclysmWeatherAdminResetHour = currentHour + math.max(1, duration)
        sendDebug(player, "DHE: cataclysm fog/wind override reset scheduled at worldHour=" .. tostring(cataclysmWeatherAdminResetHour))
    end

    if cm.transmitClientChangeAdminVars then
        pcall(function() cm:transmitClientChangeAdminVars() end)
    end
end

local function triggerCataclysmWeather(player)
    if not DynamicHordeEvents.GetBool("EnableCataclysmWeather") then return end

    local duration = DynamicHordeEvents.GetNumber("CataclysmWeatherDurationHours")
    if duration <= 0 then duration = 8 end

    local cm = nil
    if getClimateManager then
        local ok, result = pcall(function() return getClimateManager() end)
        if ok then cm = result end
    end

    local usedPrimaryWeather = false

    local function tryWeather(label, fn)
        local ok, err = pcall(fn)
        if ok then
            sendDebug(player, "DHE: cataclysm weather ok: " .. tostring(label))
            return true
        else
            sendDebug(player, "DHE: cataclysm weather failed: " .. tostring(label) .. " | " .. tostring(err))
            return false
        end
    end

    -- Preferred B42 path: built-in tropical storm weather period.
    if cm and cm.transmitTriggerTropical then
        usedPrimaryWeather = tryWeather("transmitTriggerTropical(" .. tostring(duration) .. ")", function()
            cm:transmitTriggerTropical(duration)
        end)
    end

    -- Fallback: hard storm / thunderstorm trigger if tropical is unavailable or fails.
    if not usedPrimaryWeather and cm and cm.transmitTriggerStorm then
        usedPrimaryWeather = tryWeather("transmitTriggerStorm(" .. tostring(duration) .. ")", function()
            cm:transmitTriggerStorm(duration)
        end)
    end

    if not usedPrimaryWeather and cm and cm.transmitServerTriggerStorm then
        usedPrimaryWeather = tryWeather("transmitServerTriggerStorm(" .. tostring(duration) .. ")", function()
            cm:transmitServerTriggerStorm(duration)
        end)
    end

    -- Layer additional fog / wind / dark-cloud atmosphere over the tropical storm.
    -- Uses admin climate floats because modded/override floats can be ignored by normal weather updates.
    applyCataclysmFogWindOverrides(player, cm, duration)

    -- Extra fallback layering. These are intentionally pcall-safe because B42 weather access
    -- can vary by SP/MP context and minor version. They should not break the event.
    if cm and cm.transmitServerStartRain then
        tryWeather("transmitServerStartRain(1.0)", function()
            cm:transmitServerStartRain(1.0)
        end)
    end

    if cm and cm.triggerCustomWeather then
        tryWeather("triggerCustomWeather(1.0, true)", function()
            cm:triggerCustomWeather(1.0, true)
        end)
    end

    if cm and cm.triggerCustomWeatherStage then
        tryWeather("triggerCustomWeatherStage(3, " .. tostring(duration) .. ")", function()
            cm:triggerCustomWeatherStage(3, duration)
        end)
    end

    if cm and cm.transmitServerTriggerLightning and player then
        tryWeather("transmitServerTriggerLightning", function()
            cm:transmitServerTriggerLightning(math.floor(player:getX()), math.floor(player:getY()), true, true, true)
        end)
    end

    if cm and cm.transmitClientChangeAdminVars then
        tryWeather("transmitClientChangeAdminVars", function()
            cm:transmitClientChangeAdminVars()
        end)
    end

    sendDebug(player, "DHE: cataclysm severe weather trigger attempted, durationHours=" .. tostring(duration))
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

local function notifyPlayer(player, sx, sy, sz, count, eventType, indicatorSeconds, screenEffectSeconds)
    local payload = {
        x = sx,
        y = sy,
        z = sz,
        count = count,
        eventType = tostring(eventType or "normal"),
        indicatorSeconds = indicatorSeconds,
        screenEffectSeconds = screenEffectSeconds,
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
            eventType = payload.eventType,
            indicatorSeconds = payload.indicatorSeconds,
            screenEffectSeconds = payload.screenEffectSeconds,
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
    notifyPlayer(player, sx, sy, sz, spawned, "normal", DynamicHordeEvents.GetNumber("IndicatorSeconds"), 0)

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

local function spawnWanderingHorde(player, forceCount)
    if not player then return false end

    local playerSquare = player:getSquare()
    if not playerSquare then return false end

    local px = playerSquare:getX()
    local py = playerSquare:getY()
    local playerZ = playerSquare:getZ()

    -- Wandering hordes should be ground-level events. If the player is upstairs,
    -- using playerZ would try to find outdoor spawn squares on z=1, which often
    -- means "nothing useful exists here". Keep x/y from the player, but search on z=0.
    local routeZ = 0

    local angle = ZombRandFloat(0.0, math.pi * 2.0)
    local dirX = math.cos(angle)
    local dirY = math.sin(angle)
    local perpX = -dirY
    local perpY = dirX

    local spawnRadius = randomBetween(
        DynamicHordeEvents.GetNumber("WanderingMinSpawnRadius"),
        DynamicHordeEvents.GetNumber("WanderingMaxSpawnRadius")
    )
    local exitDistance = math.max(spawnRadius + 60, DynamicHordeEvents.GetNumber("WanderingExitDistance"))
    local spread = math.max(6, DynamicHordeEvents.GetNumber("WanderingSpread"))

    -- Horde starts on one side of the player and gets attracted to a point far beyond the player.
    -- This simulates a passing/wandering horde rather than a direct assault.
    local sx = math.floor(px - dirX * spawnRadius)
    local sy = math.floor(py - dirY * spawnRadius)
    local tx = math.floor(px + dirX * exitDistance)
    local ty = math.floor(py + dirY * exitDistance)

    local baseSquare = findUsableSquareNearPoint(sx, sy, routeZ, math.max(8, math.floor(spread * 1.2)), true)
    if not baseSquare then
        -- Loaded chunks can be awkward. Fall back to normal search, but keep the exit point behavior.
        baseSquare = findSpawnSquareCustom(
            player,
            DynamicHordeEvents.GetNumber("WanderingMinSpawnRadius"),
            DynamicHordeEvents.GetNumber("WanderingMaxSpawnRadius"),
            DynamicHordeEvents.GetNumber("SpawnSearchAttempts")
        )
    end

    if not baseSquare then
        sendDebug(player, "DHE: failed to find wandering spawn square. playerZ=" .. tostring(playerZ) .. ", routeZ=" .. tostring(routeZ))
        return false
    end

    sx = baseSquare:getX()
    sy = baseSquare:getY()
    routeZ = baseSquare:getZ()

    local count = forceCount or randomBetween(
        DynamicHordeEvents.GetNumber("WanderingMinZombies"),
        DynamicHordeEvents.GetNumber("WanderingMaxZombies")
    )

    -- Compact formation: keep the route behavior, but avoid the old "wall of zombies" look.
    -- Important: existing saves can keep old WanderingSpread values, so the code itself
    -- uses smaller internal spreads/offsets instead of relying only on changed defaults.
    local mainCount = math.floor(count * 0.74)
    local leftCount = math.floor(count * 0.08)
    local rightCount = math.floor(count * 0.08)
    local rearCount = count - mainCount - leftCount - rightCount

    local mainSpread = math.max(4, math.floor(spread * 0.28))
    local sideOffset = math.max(4, math.floor(spread * 0.25))
    local sideSpread = math.max(3, math.floor(spread * 0.18))
    local rearOffset = math.max(6, math.floor(spread * 0.35))
    local rearSpread = math.max(4, math.floor(spread * 0.22))

    local clusters = {
        { x = sx, y = sy, count = mainCount, spread = mainSpread },
        { x = sx + math.floor(perpX * sideOffset), y = sy + math.floor(perpY * sideOffset), count = leftCount, spread = sideSpread },
        { x = sx - math.floor(perpX * sideOffset), y = sy - math.floor(perpY * sideOffset), count = rightCount, spread = sideSpread },
        { x = sx - math.floor(dirX * rearOffset), y = sy - math.floor(dirY * rearOffset), count = rearCount, spread = rearSpread },
    }

    local spawned = 0
    local lastErr = nil
    for _, cluster in ipairs(clusters) do
        local clusterSpawned = 0
        for _ = 1, cluster.count do
            local ox = cluster.x + ZombRand(-cluster.spread, cluster.spread + 1)
            local oy = cluster.y + ZombRand(-cluster.spread, cluster.spread + 1)
            local square = findNearbySpawnableSquare(ox, oy, routeZ, cluster.spread)
            if square then
                local ok, err = spawnZombieAt(square:getX(), square:getY(), square:getZ())
                if ok then
                    spawned = spawned + 1
                    clusterSpawned = clusterSpawned + 1
                else
                    lastErr = err
                end
            end
        end
        sendDebug(player, "DHE: wandering cluster spawned=" .. tostring(clusterSpawned) .. "/" .. tostring(cluster.count) .. " near " .. tostring(cluster.x) .. "," .. tostring(cluster.y) .. "," .. tostring(routeZ) .. " spread=" .. tostring(cluster.spread))
    end

    if spawned <= 0 then
        sendDebug(player, "DHE: wandering found base square but spawned 0 zombies. base=" .. tostring(sx) .. "," .. tostring(sy) .. "," .. tostring(routeZ) .. ", playerZ=" .. tostring(playerZ))
        if lastErr then sendDebug(player, "DHE: wandering spawn API failed: " .. tostring(lastErr)) end
        return false
    end

    attractWanderingToExitPoint(player, tx, ty, routeZ)
    notifyPlayer(
        player,
        sx,
        sy,
        routeZ,
        spawned,
        "wandering",
        DynamicHordeEvents.GetNumber("WanderingIndicatorSeconds"),
        0
    )

    lastWanderingHour = getGameTime():getWorldAgeHours()
    scheduleNextWandering(player)

    sendDebug(player, "DHE: WANDERING spawned=" .. tostring(spawned) .. "/" .. tostring(count) .. " at " .. tostring(sx) .. "," .. tostring(sy) .. "," .. tostring(routeZ) .. " exit=" .. tostring(tx) .. "," .. tostring(ty) .. " playerZ=" .. tostring(playerZ) .. " configuredSpread=" .. tostring(spread))
    return spawned > 0
end

local function spawnCataclysmHorde(player)
    if not player then return false end

    local spawnSquare = findSpawnSquareCustom(
        player,
        DynamicHordeEvents.GetNumber("CataclysmMinSpawnRadius"),
        DynamicHordeEvents.GetNumber("CataclysmMaxSpawnRadius"),
        DynamicHordeEvents.GetNumber("SpawnSearchAttempts")
    )

    if not spawnSquare then
        sendDebug(player, "DHE: failed to find cataclysm spawn square.")
        return false
    end

    local count = randomBetween(
        DynamicHordeEvents.GetNumber("CataclysmMinZombies"),
        DynamicHordeEvents.GetNumber("CataclysmMaxZombies")
    )

    local sx = spawnSquare:getX()
    local sy = spawnSquare:getY()
    local sz = spawnSquare:getZ()

    local playerSquare = player:getSquare()
    local px, py = player:getX(), player:getY()
    if playerSquare then px, py = playerSquare:getX(), playerSquare:getY() end

    local angle = math.atan2(sy - py, sx - px)
    local perpX = math.cos(angle + math.pi / 2.0)
    local perpY = math.sin(angle + math.pi / 2.0)

    local mainCount = math.floor(count * 0.60)
    local leftCount = math.floor(count * 0.20)
    local rightCount = count - mainCount - leftCount

    local clusters = {
        { x = sx, y = sy, count = mainCount, spread = 10 },
        { x = sx + math.floor(perpX * 18), y = sy + math.floor(perpY * 18), count = leftCount, spread = 8 },
        { x = sx - math.floor(perpX * 18), y = sy - math.floor(perpY * 18), count = rightCount, spread = 8 },
    }

    local spawned = 0
    local lastErr = nil
    for _, cluster in ipairs(clusters) do
        local clusterSpawned = 0
        for _ = 1, cluster.count do
            local ox = cluster.x + ZombRand(-cluster.spread, cluster.spread + 1)
            local oy = cluster.y + ZombRand(-cluster.spread, cluster.spread + 1)
            local square = findNearbySpawnableSquare(ox, oy, sz, cluster.spread)
            if square then
                local ok, err = spawnZombieAt(square:getX(), square:getY(), square:getZ())
                if ok then
                    spawned = spawned + 1
                    clusterSpawned = clusterSpawned + 1
                else
                    lastErr = err
                end
            end
        end
        sendDebug(player, "DHE: cataclysm cluster spawned=" .. tostring(clusterSpawned) .. "/" .. tostring(cluster.count) .. " near " .. tostring(cluster.x) .. "," .. tostring(cluster.y) .. "," .. tostring(sz))
    end

    if spawned <= 0 then
        sendDebug(player, "DHE: cataclysm found base square but spawned 0 zombies. base=" .. tostring(sx) .. "," .. tostring(sy) .. "," .. tostring(sz))
        if lastErr then sendDebug(player, "DHE: cataclysm spawn API failed: " .. tostring(lastErr)) end
        return false
    end

    attractCataclysmToPlayer(player)
    triggerCataclysmWeather(player)
    notifyPlayer(
        player,
        sx,
        sy,
        sz,
        spawned,
        "cataclysm",
        DynamicHordeEvents.GetNumber("CataclysmIndicatorSeconds"),
        DynamicHordeEvents.GetNumber("CataclysmScreenEffectSeconds")
    )

    lastCataclysmDay = getWorldDaysSurvived()
    scheduleNextCataclysm(player)

    sendDebug(player, "DHE: CATACLYSM spawned=" .. tostring(spawned) .. "/" .. tostring(count) .. " at " .. tostring(sx) .. "," .. tostring(sy) .. "," .. tostring(sz))
    if spawned == 0 and lastErr then
        sendDebug(player, "DHE: cataclysm spawn API failed: " .. tostring(lastErr))
    end

    return spawned > 0
end

function DynamicHordeEvents.Server.Update()
    if not DynamicHordeEvents.GetBool("Enabled") then return end

    if cataclysmWeatherAdminResetHour ~= nil and getGameTime and getGameTime():getWorldAgeHours() >= cataclysmWeatherAdminResetHour then
        resetCataclysmWeatherOverrides(nil)
    end

    if nextSpawnHour == nil then
        scheduleNextSpawn(nil)
    end
    if nextCataclysmDay == nil and DynamicHordeEvents.GetBool("EnableCataclysmHorde") then
        scheduleNextCataclysm(nil)
    end
    if nextWanderingHour == nil and DynamicHordeEvents.GetBool("EnableWanderingHorde") then
        scheduleNextWandering(nil)
    end

    local currentHour = getGameTime():getWorldAgeHours()
    local currentDay = getWorldDaysSurvived()

    if DynamicHordeEvents.GetBool("EnableCataclysmHorde") and nextCataclysmDay ~= nil and currentDay >= nextCataclysmDay then
        local cPlayer = pickTargetPlayer()
        if cPlayer then
            spawnCataclysmHorde(cPlayer)
        end
    end

    if DynamicHordeEvents.GetBool("EnableWanderingHorde") and nextWanderingHour ~= nil and currentHour >= nextWanderingHour then
        local wPlayer = pickTargetPlayer()
        if wPlayer then
            spawnWanderingHorde(wPlayer, nil)
        end
    end

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
    elseif command == "ForceCataclysm" then
        sendDebug(player, "DHE: forced CATACLYSM spawn requested.")
        spawnCataclysmHorde(player)
    elseif command == "ForceWandering" then
        sendDebug(player, "DHE: forced WANDERING spawn requested.")
        spawnWanderingHorde(player, nil)
    elseif command == "Status" then
        local currentHour = getGameTime():getWorldAgeHours()
        local multiplier, steps, daysSurvived = getHordeScalingMultiplier()
        sendDebug(player, "DHE status: version=" .. tostring(DynamicHordeEvents.Version) .. ", currentHour=" .. tostring(currentHour) .. ", nextSpawnHour=" .. tostring(nextSpawnHour) .. ", enabled=" .. tostring(DynamicHordeEvents.GetBool("Enabled")) .. ", scalingMode=" .. tostring(DynamicHordeEvents.GetNumber("ScalingMode")) .. ", scalingMultiplier=" .. string.format("%.2f", multiplier) .. ", scalingSteps=" .. tostring(steps) .. ", daysSurvived=" .. string.format("%.1f", daysSurvived or 0) .. ", nextCataclysmDay=" .. tostring(nextCataclysmDay) .. ", nextWanderingHour=" .. tostring(nextWanderingHour))
    end
end

Events.OnClientCommand.Add(DynamicHordeEvents.Server.OnClientCommand)
Events.OnGameStart.Add(function()
    scheduleNextSpawn(nil)
    if DynamicHordeEvents.GetBool("EnableCataclysmHorde") then scheduleNextCataclysm(nil) end
    if DynamicHordeEvents.GetBool("EnableWanderingHorde") then scheduleNextWandering(nil) end
end)
Events.EveryTenMinutes.Add(DynamicHordeEvents.Server.Update)
Events.EveryHours.Add(DynamicHordeEvents.Server.Update)
