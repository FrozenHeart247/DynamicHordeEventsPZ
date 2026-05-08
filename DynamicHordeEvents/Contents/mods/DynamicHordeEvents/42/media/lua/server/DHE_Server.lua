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

local function multiplayerServerRuntimeActive()
    local active = false
    pcall(function()
        active = isServer and isServer() == true
    end)
    return active
end

local function applyMPActiveSpawnClamp(minRadius, maxRadius)
    minRadius = tonumber(minRadius) or 0
    maxRadius = tonumber(maxRadius) or minRadius
    if maxRadius < minRadius then maxRadius = minRadius end

    if not multiplayerServerRuntimeActive() or not DynamicHordeEvents.GetBool("EnableMPActiveSpawnClamp") then
        return minRadius, maxRadius
    end

    local activeMax = math.max(30, DynamicHordeEvents.GetNumber("MPActiveSpawnMaxRadius"))
    minRadius = math.min(minRadius, activeMax)
    maxRadius = math.min(maxRadius, activeMax)
    if maxRadius < minRadius then minRadius = maxRadius end
    return minRadius, maxRadius
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
    local clampedForMP = false

    if forceNear then
        minRadius = DynamicHordeEvents.GetNumber("TestSpawnRadius")
        maxRadius = minRadius
        attempts = 24
    else
        local originalMinRadius = minRadius
        local originalMaxRadius = maxRadius
        minRadius, maxRadius = applyMPActiveSpawnClamp(minRadius, maxRadius)
        clampedForMP = minRadius ~= originalMinRadius or maxRadius ~= originalMaxRadius
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

    if clampedForMP then
        sendDebug(player, "DHE: MP active spawn clamp used for normal horde radius " .. tostring(minRadius) .. "-" .. tostring(maxRadius))
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
    local fallbackMinRadius, fallbackMaxRadius = applyMPActiveSpawnClamp(
        DynamicHordeEvents.GetNumber("MinSpawnRadius"),
        DynamicHordeEvents.GetNumber("MaxSpawnRadius")
    )
    square = tryRandomRing(
        fallbackMinRadius,
        fallbackMaxRadius,
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

local function serverRuntimeActive()
    local active = false
    pcall(function()
        active = isServer and isServer() == true
    end)
    return active
end

local function emitAttractionSound(player, x, y, z, radius, volume, label, quiet)
    x = math.floor(tonumber(x) or 0)
    y = math.floor(tonumber(y) or 0)
    z = math.floor(tonumber(z) or 0)
    radius = math.max(1, math.floor(tonumber(radius) or 1))
    volume = math.max(1, math.floor(tonumber(volume) or 1))

    local source = player
    local okAny = false
    local failures = {}
    local worldSound = nil

    local function try(mode, fn)
        local ok, result = pcall(fn)
        if ok then
            okAny = true
            return result
        end
        table.insert(failures, tostring(mode) .. "=" .. tostring(result))
        return nil
    end

    if WorldSoundManager and WorldSoundManager.instance and WorldSoundManager.instance.addSound then
        worldSound = try("WorldSoundManager:addSound", function()
            return WorldSoundManager.instance:addSound(source, x, y, z, radius, volume, false, 0.0, 1.0, false, true, false)
        end) or worldSound
    end

    if not okAny then
        worldSound = try("addSound", function()
            return addSound(source, x, y, z, radius, volume)
        end) or worldSound
    end

    if worldSound and ZombiePopulationManager and ZombiePopulationManager.instance and ZombiePopulationManager.instance.addWorldSound then
        try("ZombiePopulationManager:addWorldSound", function()
            ZombiePopulationManager.instance:addWorldSound(worldSound, true)
        end)
    end

    local square = nil
    pcall(function() square = getCell():getGridSquare(x, y, z) end)
    if not okAny and square and AddNoiseToken then
        try("AddNoiseToken", function()
            AddNoiseToken(square, radius)
        end)
    end

    if not okAny and player and label ~= "wandering" and AddWorldSound then
        try("AddWorldSound", function()
            AddWorldSound(player, radius, volume)
        end)
    end

    if okAny then
        if not quiet then
            sendDebug(player, "DHE: " .. tostring(label or "horde") .. " attraction emitted at " .. tostring(x) .. "," .. tostring(y) .. "," .. tostring(z) .. " radius=" .. tostring(radius) .. " volume=" .. tostring(volume))
        end
    elseif not quiet then
        sendDebug(player, "DHE: " .. tostring(label or "horde") .. " attraction failed: " .. table.concat(failures, "; "))
    end

    return okAny
end

local pendingAttractionSounds = {}
local ATTRACTION_SOUND_DELAY_TICKS_SP = 8

local function getAttractionSoundDelay()
    if serverRuntimeActive() then
        local seconds = math.max(1, DynamicHordeEvents.GetNumber("MPAttractionDelaySeconds"))
        return math.max(1, math.floor((seconds * 10) + 0.5)), seconds
    end
    return ATTRACTION_SOUND_DELAY_TICKS_SP, 0.8
end

local function queueAttractionSound(player, x, y, z, radius, volume, label, quiet)
    local delayTicks, delaySeconds = getAttractionSoundDelay()
    table.insert(pendingAttractionSounds, {
        player = player,
        x = x,
        y = y,
        z = z,
        radius = radius,
        volume = volume,
        label = label,
        quiet = quiet,
        ticks = delayTicks,
    })
    if not quiet then
        sendDebug(player, "DHE: " .. tostring(label or "horde") .. " attraction queued in " .. tostring(delaySeconds) .. " sec (" .. tostring(delayTicks) .. " tick(s))")
    end
end

local function updateAttractionSounds()
    if #pendingAttractionSounds == 0 then return end

    local i = 1
    while i <= #pendingAttractionSounds do
        local sound = pendingAttractionSounds[i]
        sound.ticks = (sound.ticks or 0) - 1
        if sound.ticks <= 0 then
            emitAttractionSound(sound.player, sound.x, sound.y, sound.z, sound.radius, sound.volume, sound.label, sound.quiet)
            table.remove(pendingAttractionSounds, i)
        else
            i = i + 1
        end
    end
end

local function attractHordeToPlayer(player)
    local radius = DynamicHordeEvents.GetNumber("AttractionRadius")
    local volume = DynamicHordeEvents.GetNumber("AttractionVolume")
    queueAttractionSound(player, player:getX(), player:getY(), player:getZ(), radius, volume, "normal", false)
end

local function attractCataclysmToPlayer(player)
    local radius = DynamicHordeEvents.GetNumber("CataclysmAttractionRadius")
    local volume = DynamicHordeEvents.GetNumber("CataclysmAttractionVolume")
    queueAttractionSound(player, player:getX(), player:getY(), player:getZ(), radius, volume, "cataclysm", false)
end

local function attractWanderingToExitPoint(player, targetX, targetY, targetZ)
    local radius = DynamicHordeEvents.GetNumber("WanderingAttractionRadius")
    local volume = DynamicHordeEvents.GetNumber("WanderingAttractionVolume")
    queueAttractionSound(player, targetX, targetY, targetZ, radius, volume, "wandering", false)
end

local cataclysmPursuitZombies = {}
local cataclysmPursuitSyncs = {}
local cataclysmPursuitSyncId = 0
local spawnCataclysmCatchup = nil
local CATACLYSM_PURSUIT_REFRESH_MS = 3000
local CATACLYSM_PURSUIT_PATH_REFRESH_MS = 15000
local CATACLYSM_PURSUIT_SYNC_MS = 3000
local CATACLYSM_PURSUIT_CLIENT_LIFE_MS = 10000
local CATACLYSM_CATCHUP_DISTANCE = 85
local CATACLYSM_CATCHUP_MIN_MS = 15000
local CATACLYSM_CATCHUP_FAIL_RETRY_MS = 5000
local CATACLYSM_CATCHUP_SPAWN_RADIUS = 85
local CATACLYSM_CATCHUP_BATCH_FRACTION = 0.25
local CATACLYSM_CATCHUP_MAX_BATCH = 80

local function getCataclysmPursuitHours()
    return math.max(0.25, DynamicHordeEvents.GetNumber("CataclysmPursuitHours"))
end

local function worldAgeHours()
    local hours = 0
    pcall(function() hours = getGameTime():getWorldAgeHours() end)
    return tonumber(hours) or 0
end

local function nowMs()
    local ms = 0
    pcall(function() ms = getTimestampMs() end)
    return tonumber(ms) or 0
end

local function getCataclysmPursuitStartDelayMs()
    local _, delaySeconds = getAttractionSoundDelay()
    return math.max(0, math.floor(((tonumber(delaySeconds) or 0) + 0.5) * 1000))
end

local function getPlayerOnlineId(player)
    local onlineId = nil
    if player then
        pcall(function() onlineId = player:getOnlineID() end)
    end
    return onlineId
end

local function sendCataclysmPursuitSync(sync)
    if not sync or not sync.player then return 0 end

    local targetX = sync.player:getX()
    local targetY = sync.player:getY()
    local targetZ = sync.player:getZ()
    local payload = {
        id = sync.id,
        spawnX = sync.spawnX,
        spawnY = sync.spawnY,
        z = sync.z,
        targetX = targetX,
        targetY = targetY,
        targetZ = targetZ,
        margin = sync.margin,
        count = sync.count,
        clientLifeMs = CATACLYSM_PURSUIT_CLIENT_LIFE_MS,
        targetOnlineID = sync.targetOnlineID,
    }

    local sent = 0
    local players = getPlayerList()
    for _, recipient in ipairs(players) do
        local ok = pcall(function()
            sendServerCommand(recipient, DynamicHordeEvents.CommandModule, "CataclysmPursuitUpdate", payload)
        end)
        if ok then sent = sent + 1 end
    end

    if sent <= 0 and not serverRuntimeActive() then
        pcall(function()
            DynamicHordeEvents.PendingCataclysmPursuit = payload
            sent = 1
        end)
    end

    return sent
end

local function startCataclysmPursuitSync(player, spawnX, spawnY, z, count)
    local pursuitHours = getCataclysmPursuitHours()
    local startDelayMs = getCataclysmPursuitStartDelayMs()
    if not DynamicHordeEvents.GetBool("EnableCataclysmPursuit") then return false, pursuitHours, startDelayMs / 1000.0 end

    cataclysmPursuitSyncId = cataclysmPursuitSyncId + 1
    local now = worldAgeHours()
    local ms = nowMs()
    local margin = 100

    table.insert(cataclysmPursuitSyncs, {
        id = cataclysmPursuitSyncId,
        player = player,
        spawnX = spawnX,
        spawnY = spawnY,
        z = z,
        count = count,
        margin = margin,
        anchorX = spawnX,
        anchorY = spawnY,
        lastTargetX = player:getX(),
        lastTargetY = player:getY(),
        targetOnlineID = getPlayerOnlineId(player),
        expiresAt = now + pursuitHours,
        nextSyncAtMs = ms + startDelayMs,
        nextCatchupAtMs = ms + startDelayMs + CATACLYSM_CATCHUP_MIN_MS,
        catchupSpawned = 0,
        catchupMax = math.max(0, math.floor(tonumber(count) or 0)),
        started = false,
    })

    return true, pursuitHours, startDelayMs / 1000.0
end

local function playerIsDeadOrMissing(player)
    if not player then return true end
    local ok, dead = pcall(function() return player:isDead() end)
    return ok and dead == true
end

local function zombieIsDeadOrMissing(zombie)
    if not zombie then return true end
    local ok, dead = pcall(function() return zombie:isDead() end)
    return ok and dead == true
end

local function commandCataclysmZombieAtPlayer(zombie, player, forcePath)
    if zombieIsDeadOrMissing(zombie) or playerIsDeadOrMissing(player) then return false end

    local applied = false
    local function try(fn)
        local ok = pcall(fn)
        if ok then applied = true end
    end

    local px = player:getX()
    local py = player:getY()
    local pz = player:getZ()
    local sx = math.floor(px)
    local sy = math.floor(py)
    local sz = math.floor(pz)

    try(function() zombie:setTarget(player) end)
    try(function() zombie:addAggro(player, 1000.0) end)
    try(function() zombie:spotted(player, true) end)
    try(function() zombie:setLastHeardSound(sx, sy, sz) end)
    try(function() zombie:setUseless(false) end)
    try(function() zombie:makeInactive(false) end)
    try(function() zombie:setVariable("bMoving", true) end)

    if forcePath then
        try(function() zombie:pathToCharacter(player) end)
        try(function() zombie:pathToSound(sx, sy, sz) end)
        try(function() zombie:pathToLocationF(px, py, pz) end)
    end

    return applied
end

local function clearCataclysmZombieTarget(zombie, player)
    if not zombie then return end

    pcall(function()
        if zombie:getTarget() == player then
            zombie:setTarget(nil)
        end
    end)
    pcall(function() zombie:clearAggroList() end)
end

local function startCataclysmPursuit(player, zombies)
    local pursuitHours = getCataclysmPursuitHours()
    local startDelayMs = getCataclysmPursuitStartDelayMs()
    if not DynamicHordeEvents.GetBool("EnableCataclysmPursuit") then return 0, pursuitHours, false, startDelayMs / 1000.0 end
    if not zombies or #zombies == 0 then return 0, pursuitHours, true, startDelayMs / 1000.0 end

    local now = worldAgeHours()
    local expiresAt = now + pursuitHours
    local startAtMs = nowMs() + startDelayMs
    local added = 0

    for _, zombie in ipairs(zombies) do
        if not zombieIsDeadOrMissing(zombie) then
            table.insert(cataclysmPursuitZombies, {
                zombie = zombie,
                player = player,
                expiresAt = expiresAt,
                nextRefreshAtMs = startAtMs,
                nextPathAtMs = startAtMs,
                started = false,
            })
            added = added + 1
        end
    end

    return added, pursuitHours, true, startDelayMs / 1000.0
end

local function updateCataclysmPursuit()
    if #cataclysmPursuitZombies == 0 then return end

    local now = worldAgeHours()
    local ms = nowMs()
    local enabled = DynamicHordeEvents.GetBool("EnableCataclysmPursuit")
    local startedCount = 0
    local debugPlayer = nil
    local i = 1
    while i <= #cataclysmPursuitZombies do
        local entry = cataclysmPursuitZombies[i]
        if not enabled or now >= (entry.expiresAt or 0) or zombieIsDeadOrMissing(entry.zombie) or playerIsDeadOrMissing(entry.player) then
            clearCataclysmZombieTarget(entry.zombie, entry.player)
            table.remove(cataclysmPursuitZombies, i)
        elseif ms >= (entry.nextRefreshAtMs or 0) then
            local wasStarted = entry.started
            local forcePath = (not entry.started) or ms >= (entry.nextPathAtMs or 0)
            commandCataclysmZombieAtPlayer(entry.zombie, entry.player, forcePath)
            entry.started = true
            if not wasStarted then
                startedCount = startedCount + 1
                debugPlayer = debugPlayer or entry.player
            end
            entry.nextRefreshAtMs = ms + CATACLYSM_PURSUIT_REFRESH_MS
            if forcePath then
                entry.nextPathAtMs = ms + CATACLYSM_PURSUIT_PATH_REFRESH_MS
            end
            i = i + 1
        else
            i = i + 1
        end
    end

    if startedCount > 0 then
        sendDebug(debugPlayer, "DHE: CATACLYSM pursuit started for " .. tostring(startedCount) .. " zombie(s)")
    end
end

local function updateCataclysmPursuitSyncs()
    if #cataclysmPursuitSyncs == 0 then return end

    local now = worldAgeHours()
    local ms = nowMs()
    local enabled = DynamicHordeEvents.GetBool("EnableCataclysmPursuit")
    local i = 1
    while i <= #cataclysmPursuitSyncs do
        local sync = cataclysmPursuitSyncs[i]
        if not enabled or now >= (sync.expiresAt or 0) or playerIsDeadOrMissing(sync.player) then
            table.remove(cataclysmPursuitSyncs, i)
        elseif ms >= (sync.nextSyncAtMs or 0) then
            local wasStarted = sync.started
            if spawnCataclysmCatchup then
                spawnCataclysmCatchup(sync)
            end
            local sent = sendCataclysmPursuitSync(sync)
            sync.started = true
            sync.nextSyncAtMs = ms + CATACLYSM_PURSUIT_SYNC_MS
            if not wasStarted then
                sendDebug(sync.player, "DHE: CATACLYSM client pursuit sync started for " .. tostring(sent) .. " client(s)")
            end
            i = i + 1
        else
            i = i + 1
        end
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

local globalCreateHordeInAreaTo = createHordeInAreaTo
local globalSpawnHorde = spawnHorde

local function collectSpawnedZombies(result)
    local zombies = {}
    if result == nil then return zombies end

    local okZombie, isZombie = pcall(function()
        return result:isZombie()
    end)
    if okZombie and isZombie then
        table.insert(zombies, result)
        return zombies
    end

    local okSize, size = pcall(function()
        return result:size()
    end)
    size = tonumber(size) or 0
    if okSize and size > 0 then
        for i = 0, size - 1 do
            local okItem, item = pcall(function()
                return result:get(i)
            end)
            if okItem and item then
                local okItemZombie, itemIsZombie = pcall(function()
                    return item:isZombie()
                end)
                if okItemZombie and itemIsZombie then
                    table.insert(zombies, item)
                end
            end
        end
    end

    return zombies
end

local function appendZombies(target, source)
    if not source then return end
    for _, zombie in ipairs(source) do
        table.insert(target, zombie)
    end
end

local function spawnZombieAt(x, y, z)
    local success = false
    local lastErr = nil
    local spawnMode = nil
    local spawnedZombies = {}

    local variants = {
        {
            mode = "vzm-now",
            fn = function()
                if not (VirtualZombieManager and VirtualZombieManager.instance and VirtualZombieManager.instance.createRealZombieNow) then
                    return nil
                end
                return VirtualZombieManager.instance:createRealZombieNow(x + 0.5, y + 0.5, z)
            end,
        },
        {
            mode = "vzm-real",
            fn = function()
                if not (VirtualZombieManager and VirtualZombieManager.instance and VirtualZombieManager.instance.createRealZombie) then
                    return nil
                end
                return VirtualZombieManager.instance:createRealZombie(x + 0.5, y + 0.5, z)
            end,
        },
        {
            mode = "createZombie",
            fn = function()
                if type(createZombie) ~= "function" then return nil end
                return createZombie(x, y, z, nil, 0, IsoDirections.S)
            end,
        },
        {
            mode = "outfit",
            fn = function() return addZombiesInOutfit(x, y, z, 1, nil, nil) end,
        },
        {
            mode = "outfit-dir",
            fn = function() return addZombiesInOutfit(x, y, z, 1, nil, 0) end,
        },
    }

    for _, variant in ipairs(variants) do
        local ok, result = pcall(variant.fn)
        local zombies = ok and collectSpawnedZombies(result) or {}
        if ok and #zombies > 0 then
            success = true
            spawnMode = variant.mode
            spawnedZombies = zombies
            break
        else
            lastErr = ok and (tostring(variant.mode) .. " returned no zombie") or result
        end
    end

    return success, lastErr, spawnMode, spawnedZombies
end

local function spawnZombieClusterManual(centerX, centerY, z, count, spread)
    local spawned = 0
    local lastErr = nil
    local firstMode = nil
    local spawnedZombies = {}

    for _ = 1, count do
        local ox = math.floor(centerX + ZombRand(-spread, spread + 1))
        local oy = math.floor(centerY + ZombRand(-spread, spread + 1))
        local square = findNearbySpawnableSquare(ox, oy, z, spread)
        if square then
            local ok, err, mode, zombies = spawnZombieAt(square:getX(), square:getY(), square:getZ())
            if ok then
                spawned = spawned + 1
                firstMode = firstMode or mode
                appendZombies(spawnedZombies, zombies)
            else
                lastErr = err
            end
        end
    end

    return spawned, lastErr, firstMode, spawnedZombies
end

local function spawnZombieCluster(player, centerX, centerY, z, count, spread, targetX, targetY, label)
    count = math.max(0, math.floor(tonumber(count) or 0))
    if count <= 0 then return 0, nil, "none" end

    spread = math.max(1, math.floor(tonumber(spread) or 1))
    z = math.floor(tonumber(z) or 0)

    local x1 = math.floor(centerX - spread)
    local y1 = math.floor(centerY - spread)
    local width = math.max(1, spread * 2 + 1)
    local height = width
    local x2 = x1 + width - 1
    local y2 = y1 + height - 1
    local tx = math.floor(tonumber(targetX) or centerX)
    local ty = math.floor(tonumber(targetY) or centerY)
    local lastErr = nil
    local function noteSpawnApiFailure(mode, err)
        lastErr = err
        sendDebug(player, "DHE: " .. tostring(label or "horde") .. " spawn API failed: " .. tostring(mode) .. " | " .. tostring(err))
    end

    -- Keep behavior sound-driven: spawn real server-side zombies, then let one queued noise event attract them.
    local spawned, manualErr, manualMode, spawnedZombies = spawnZombieClusterManual(centerX, centerY, z, count, spread)
    if manualErr ~= nil then lastErr = manualErr end
    if spawned > 0 then
        return spawned, lastErr, "manual-" .. tostring(manualMode or "server"), spawnedZombies
    end

    -- Last resort only: if direct real-zombie spawning fails entirely, ask the population manager.
    if serverRuntimeActive() and spawned <= 0 then
        local hordeInAreaTo = globalCreateHordeInAreaTo or createHordeInAreaTo
        if type(hordeInAreaTo) == "function" then
            local ok, err = pcall(function()
                hordeInAreaTo(x1, y1, width, height, tx, ty, count)
            end)
            if ok then return count, nil, "createHordeInAreaTo", nil end
            noteSpawnApiFailure("createHordeInAreaTo", err)
        end

        if ZombiePopulationManager and ZombiePopulationManager.instance then
            local ok, err = pcall(function()
                ZombiePopulationManager.instance:createHordeInAreaTo(x1, y1, width, height, tx, ty, count)
            end)
            if ok then return count, nil, "ZombiePopulationManager:createHordeInAreaTo", nil end
            noteSpawnApiFailure("ZombiePopulationManager:createHordeInAreaTo", err)
        end

        local hordeSpawn = globalSpawnHorde
        if type(hordeSpawn) == "function" then
            local ok, err = pcall(function()
                hordeSpawn(x1, y1, x2, y2, z, count)
            end)
            if ok then return count, nil, "spawnHorde", nil end
            noteSpawnApiFailure("spawnHorde", err)
        end
    end

    return spawned, lastErr, "none", nil
end

spawnCataclysmCatchup = function(sync)
    if not sync or playerIsDeadOrMissing(sync.player) then return 0 end

    local ms = nowMs()
    if ms < (sync.nextCatchupAtMs or 0) then return 0 end

    local px = sync.player:getX()
    local py = sync.player:getY()
    local pz = sync.player:getZ()
    local anchorX = tonumber(sync.anchorX) or tonumber(sync.spawnX) or px
    local anchorY = tonumber(sync.anchorY) or tonumber(sync.spawnY) or py
    local dx = px - anchorX
    local dy = py - anchorY
    local distance = math.sqrt((dx * dx) + (dy * dy))
    if distance < CATACLYSM_CATCHUP_DISTANCE then return 0 end

    local remaining = math.max(0, (tonumber(sync.catchupMax) or 0) - (tonumber(sync.catchupSpawned) or 0))
    if remaining <= 0 then
        sync.nextCatchupAtMs = ms + CATACLYSM_CATCHUP_MIN_MS
        return 0
    end

    local moveX = px - (tonumber(sync.lastTargetX) or anchorX)
    local moveY = py - (tonumber(sync.lastTargetY) or anchorY)
    local moveLen = math.sqrt((moveX * moveX) + (moveY * moveY))
    if moveLen < 3 then
        moveX = dx
        moveY = dy
        moveLen = distance
    end
    if moveLen <= 0 then
        sync.nextCatchupAtMs = ms + CATACLYSM_CATCHUP_FAIL_RETRY_MS
        return 0
    end

    local dirX = moveX / moveLen
    local dirY = moveY / moveLen
    local baseX = math.floor(px - (dirX * CATACLYSM_CATCHUP_SPAWN_RADIUS))
    local baseY = math.floor(py - (dirY * CATACLYSM_CATCHUP_SPAWN_RADIUS))
    local baseZ = math.floor(tonumber(pz) or tonumber(sync.z) or 0)
    local baseSquare = findUsableSquareNearPoint(baseX, baseY, baseZ, 18, true)
    if not baseSquare then
        sync.nextCatchupAtMs = ms + CATACLYSM_CATCHUP_FAIL_RETRY_MS
        sendDebug(sync.player, "DHE: CATACLYSM catch-up skipped: no square near " .. tostring(baseX) .. "," .. tostring(baseY) .. "," .. tostring(baseZ))
        return 0
    end

    local batch = math.floor((tonumber(sync.count) or 0) * CATACLYSM_CATCHUP_BATCH_FRACTION)
    batch = math.min(remaining, math.max(12, math.min(CATACLYSM_CATCHUP_MAX_BATCH, batch)))

    local sx = baseSquare:getX()
    local sy = baseSquare:getY()
    local sz = baseSquare:getZ()
    local spawned, err, mode = spawnZombieCluster(
        sync.player,
        sx,
        sy,
        sz,
        batch,
        7,
        px,
        py,
        "cataclysm-catchup"
    )

    if spawned <= 0 then
        sync.nextCatchupAtMs = ms + CATACLYSM_CATCHUP_FAIL_RETRY_MS
        if err then sendDebug(sync.player, "DHE: CATACLYSM catch-up spawn failed: " .. tostring(err)) end
        return 0
    end

    sync.spawnX = sx
    sync.spawnY = sy
    sync.z = sz
    sync.anchorX = sx
    sync.anchorY = sy
    sync.lastTargetX = px
    sync.lastTargetY = py
    sync.catchupSpawned = (tonumber(sync.catchupSpawned) or 0) + spawned
    sync.nextCatchupAtMs = ms + CATACLYSM_CATCHUP_MIN_MS

    sendDebug(sync.player, "DHE: CATACLYSM catch-up spawned=" .. tostring(spawned) .. "/" .. tostring(batch) .. " via=" .. tostring(mode) .. " near " .. tostring(sx) .. "," .. tostring(sy) .. "," .. tostring(sz) .. " dist=" .. tostring(math.floor(distance)) .. " extra=" .. tostring(sync.catchupSpawned) .. "/" .. tostring(sync.catchupMax))
    return spawned
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

    -- SP fallback: broadcast-style overload. Some B42 SP paths ignore the player overload silently.
    local okBroadcast = false
    local errBroadcast = nil
    if not serverRuntimeActive() then
        okBroadcast, errBroadcast = pcall(function()
            sendServerCommand(DynamicHordeEvents.CommandModule, "Incoming", payload)
        end)
        if okBroadcast then delivered = true end
    end

    -- Single-player fallback: do not call Client.SetIncomingTarget directly from server code.
    -- In B42 SP this can play the sound in the wrong context before the HUD target exists.
    -- Instead, drop a pending payload that the client OnTick handler can consume if both sides share globals.
    local okPending = false
    local errPending = nil
    if not serverRuntimeActive() then
        okPending, errPending = pcall(function()
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
    end

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

    local spawned, lastErr, spawnMode = spawnZombieCluster(
        player,
        sx,
        sy,
        sz,
        count,
        4,
        player:getX(),
        player:getY(),
        "normal"
    )

    attractHordeToPlayer(player)
    notifyPlayer(player, sx, sy, sz, spawned, "normal", DynamicHordeEvents.GetNumber("IndicatorSeconds"), 0)

    lastSpawnHour = getGameTime():getWorldAgeHours()
    scheduleNextSpawn(player)

    local scalingText = ""
    if not forceNear and not forceCount and scalingMultiplier and scalingMultiplier > 1.0 then
        scalingText = " | scaled from " .. tostring(baseCount) .. " x" .. string.format("%.2f", scalingMultiplier) .. " after " .. string.format("%.1f", daysSurvived or 0) .. " days"
    end
    sendDebug(player, "DHE: spawned=" .. tostring(spawned) .. "/" .. tostring(count) .. " via=" .. tostring(spawnMode) .. " at " .. tostring(sx) .. "," .. tostring(sy) .. "," .. tostring(sz) .. scalingText)
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

    local wanderingMinRadius, wanderingMaxRadius = applyMPActiveSpawnClamp(
        DynamicHordeEvents.GetNumber("WanderingMinSpawnRadius"),
        DynamicHordeEvents.GetNumber("WanderingMaxSpawnRadius")
    )
    local spawnRadius = randomBetween(wanderingMinRadius, wanderingMaxRadius)
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
            wanderingMinRadius,
            wanderingMaxRadius,
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
        local clusterSpawned, err, mode = spawnZombieCluster(
            player,
            cluster.x,
            cluster.y,
            routeZ,
            cluster.count,
            cluster.spread,
            tx,
            ty,
            "wandering"
        )
        spawned = spawned + clusterSpawned
        if err ~= nil then lastErr = err end
        sendDebug(player, "DHE: wandering cluster spawned=" .. tostring(clusterSpawned) .. "/" .. tostring(cluster.count) .. " via=" .. tostring(mode) .. " near " .. tostring(cluster.x) .. "," .. tostring(cluster.y) .. "," .. tostring(routeZ) .. " spread=" .. tostring(cluster.spread))
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
    local cataclysmZombies = {}
    for _, cluster in ipairs(clusters) do
        local clusterSpawned, err, mode, zombies = spawnZombieCluster(
            player,
            cluster.x,
            cluster.y,
            sz,
            cluster.count,
            cluster.spread,
            px,
            py,
            "cataclysm"
        )
        spawned = spawned + clusterSpawned
        if err ~= nil then lastErr = err end
        appendZombies(cataclysmZombies, zombies)
        sendDebug(player, "DHE: cataclysm cluster spawned=" .. tostring(clusterSpawned) .. "/" .. tostring(cluster.count) .. " via=" .. tostring(mode) .. " near " .. tostring(cluster.x) .. "," .. tostring(cluster.y) .. "," .. tostring(sz))
    end

    if spawned <= 0 then
        sendDebug(player, "DHE: cataclysm found base square but spawned 0 zombies. base=" .. tostring(sx) .. "," .. tostring(sy) .. "," .. tostring(sz))
        if lastErr then sendDebug(player, "DHE: cataclysm spawn API failed: " .. tostring(lastErr)) end
        return false
    end

    local pursued, pursuitHours, pursuitEnabled, pursuitDelaySeconds = startCataclysmPursuit(player, cataclysmZombies)
    if pursuitEnabled then
        sendDebug(player, "DHE: CATACLYSM pursuit queued for " .. tostring(pursued) .. "/" .. tostring(#cataclysmZombies) .. " zombie(s), starts in " .. tostring(pursuitDelaySeconds) .. " sec, duration=" .. tostring(pursuitHours) .. " game hour(s)")
    else
        sendDebug(player, "DHE: CATACLYSM pursuit disabled in sandbox")
    end

    local syncEnabled, syncHours, syncDelaySeconds = startCataclysmPursuitSync(player, sx, sy, sz, spawned)
    if syncEnabled then
        sendDebug(player, "DHE: CATACLYSM client pursuit sync queued, starts in " .. tostring(syncDelaySeconds) .. " sec, duration=" .. tostring(syncHours) .. " game hour(s)")
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
Events.OnTick.Add(updateAttractionSounds)
Events.OnTick.Add(updateCataclysmPursuit)
Events.OnTick.Add(updateCataclysmPursuitSyncs)
Events.OnGameStart.Add(function()
    scheduleNextSpawn(nil)
    if DynamicHordeEvents.GetBool("EnableCataclysmHorde") then scheduleNextCataclysm(nil) end
    if DynamicHordeEvents.GetBool("EnableWanderingHorde") then scheduleNextWandering(nil) end
end)
Events.EveryTenMinutes.Add(DynamicHordeEvents.Server.Update)
Events.EveryHours.Add(DynamicHordeEvents.Server.Update)
