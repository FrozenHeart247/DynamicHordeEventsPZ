-- Dynamic Horde Events B42
-- Client command handling: warning sound + UI target. Debug messages are sandbox-gated.

require "DHE_Config"

DynamicHordeEvents.Client = DynamicHordeEvents.Client or {}
DynamicHordeEvents.Client.Target = nil
DynamicHordeEvents.Client.LastMessage = nil
DynamicHordeEvents.Client.LastMessageAt = 0
DynamicHordeEvents.Client.LastPendingHandledAt = 0
DynamicHordeEvents.Client.PendingSpeech = nil
DynamicHordeEvents.Client.CataclysmPursuits = DynamicHordeEvents.Client.CataclysmPursuits or {}

local CATACLYSM_CLIENT_PURSUIT_UPDATE_MS = 1000
local CATACLYSM_CLIENT_PURSUIT_REPORT_MS = 10000

local function getPlayer()
    return getSpecificPlayer(0)
end


local NORMAL_HORDE_LINES = {
    "Fuck... I hear a horde nearby. I think they're coming here.",
    "Shit. That's not just wandering. They're heading this way!",
    "Great. A whole damn crowd, and of course they found me.",
    "I hear them. Too many footsteps... way too close.",
    "I heard something over there. Should stay careful",
    "Goddamn wanderers. Why can't you just die. Oh, right they're already dead.",
    "Yeah fuckers! Come and get me!",
    "Yeah I like company but not that sort of a company.",
    "Hey... Isn't it... I.. I know that guy.... Gotta make a proper burials for him",
}

local CATACLYSM_HORDE_LINES = {
    "Fuck, fuck, fuck... I really don't like the sound of that.",
    "Shit... sounds like the whole city is coming for my ass.",
    "God damn it, why right now? Fight them or run?",
    "No. No, that's not a horde. That's a fucking wall of dead.",
    "Yeah, this sounds like trouble, grave trouble. Should've written a will earlier",
    "Fuuuuuuck! Why can't you sit in one place?'. I'll need a good bottle of whiskey after that... If I survive",
}

local WANDERING_HORDE_LINES = {
    "Hold on... that's a moving horde. Maybe I can stay quiet.",
    "Shit. They're passing through. Don't make a sound.",
    "That's a lot of dead on the move. Better let them pass.",
    "Keep it quiet... maybe they won't notice me.",
    "Hey! That's my neighborhood... Hope they wont stay long here. Better not provoke them.",
    "Is there a parade or what? Dont feel like joining. Better stay quite.",
}

local function randomLine(lines)
    if not lines or #lines == 0 then return nil end
    local index = ZombRand(1, #lines + 1)
    return lines[index]
end

function DynamicHordeEvents.Client.SayHordeLine(eventType)
    local player = getPlayer()
    if not player then return end

    local line = nil
    local kind = tostring(eventType or "normal")
    if kind == "cataclysm" then
        if not DynamicHordeEvents.GetBool("EnableCataclysmHordeSpeech") then return end
        line = randomLine(CATACLYSM_HORDE_LINES)
    elseif kind == "wandering" then
        if not DynamicHordeEvents.GetBool("EnableWanderingHordeSpeech") then return end
        line = randomLine(WANDERING_HORDE_LINES)
    else
        if not DynamicHordeEvents.GetBool("EnableNormalHordeSpeech") then return end
        line = randomLine(NORMAL_HORDE_LINES)
    end

    if line and line ~= "" then
        local ok, err = pcall(function() player:Say(line) end)
        if ok then
            DynamicHordeEvents.DebugPrint("DHE: horde speech said: " .. tostring(line))
        else
            DynamicHordeEvents.DebugPrint("DHE: horde speech failed: " .. tostring(err))
        end
    end
end

function DynamicHordeEvents.Client.QueueHordeLine(eventType)
    -- Delay survivor speech a little so debug ShowMessage/player:Say calls do not overwrite it instantly.
    DynamicHordeEvents.Client.PendingSpeech = {
        eventType = tostring(eventType or "normal"),
        speakAtMs = getTimestampMs() + 900,
    }
    DynamicHordeEvents.DebugPrint("DHE: horde speech queued: " .. tostring(eventType or "normal"))
end

function DynamicHordeEvents.Client.ProcessPendingSpeech()
    local pending = DynamicHordeEvents.Client.PendingSpeech
    if not pending then return end
    if getTimestampMs() < (tonumber(pending.speakAtMs) or 0) then return end

    DynamicHordeEvents.Client.PendingSpeech = nil
    DynamicHordeEvents.Client.SayHordeLine(pending.eventType)
end

function DynamicHordeEvents.Client.ShowMessage(text)
    -- Debug overlay/chat messages are intentionally hidden unless sandbox Debug is enabled.
    if not DynamicHordeEvents.GetBool("Debug") then return end

    text = tostring(text or "")
    DynamicHordeEvents.Client.LastMessage = text
    DynamicHordeEvents.Client.LastMessageAt = getTimestampMs()
    DynamicHordeEvents.Log(text)

    local player = getPlayer()
    if player then
        pcall(function() player:Say(text) end)
    end
end

local function trySound(label, fn)
    local ok, err = pcall(fn)
    if ok then
        DynamicHordeEvents.DebugPrint("DHE sound ok: " .. tostring(label))
        return true
    end
    DynamicHordeEvents.DebugPrint("DHE sound failed: " .. tostring(label) .. " / " .. tostring(err))
    return false
end

local function playOneSound(soundName)
    local player = getPlayer()
    if not soundName or soundName == "" then return false end

    if player and player.getEmitter then
        local emitter = nil
        pcall(function() emitter = player:getEmitter() end)
        if emitter and emitter.playSound and trySound("emitter:" .. soundName, function() emitter:playSound(soundName) end) then return true end
    end

    if player and player.playSoundLocal then
        if trySound("playSoundLocal:" .. soundName, function() player:playSoundLocal(soundName) end) then return true end
    end

    if player and player.playSound then
        if trySound("playSound:" .. soundName, function() player:playSound(soundName) end) then return true end
    end

    return false
end

function DynamicHordeEvents.Client.PlayWarningSound(eventType)
    if not DynamicHordeEvents.GetBool("EnableWarningSound") then
        DynamicHordeEvents.Client.ShowMessage("DHE: warning sound disabled in sandbox")
        return false
    end

    local preferred = tostring(DynamicHordeEvents.Get("WarningSound") or "DynamicHordeWarning")
    if tostring(eventType or "normal") == "wandering" then
        preferred = tostring(DynamicHordeEvents.Get("WanderingWarningSound") or "DynamicHordeWanderingWarning")
    end
    if playOneSound(preferred) then
        DynamicHordeEvents.Client.ShowMessage("DHE: sound test ok: " .. preferred)
        return true
    end

    local fallbacks = {
        tostring(DynamicHordeEvents.Get("FallbackWarningSound") or "ZombieSurprisedPlayer"),
        "MetaScream",
        "ZombieSurprisedPlayer",
        "ZombieCognition",
    }

    for _, soundName in ipairs(fallbacks) do
        if soundName ~= preferred and playOneSound(soundName) then
            DynamicHordeEvents.Client.ShowMessage("DHE: sound fallback ok: " .. soundName)
            return true
        end
    end

    DynamicHordeEvents.Client.ShowMessage("DHE: warning sound failed; check console.txt")
    return false
end

function DynamicHordeEvents.Client.SetIncomingTarget(args, silent)
    args = args or {}
    local now = getTimestampMs()
    local indicatorSeconds = DynamicHordeEvents.GetNumber("IndicatorSeconds")
    if args.eventType == "cataclysm" then
        indicatorSeconds = DynamicHordeEvents.GetNumber("CataclysmIndicatorSeconds")
    elseif args.eventType == "wandering" then
        indicatorSeconds = DynamicHordeEvents.GetNumber("WanderingIndicatorSeconds")
    end
    local lifeMs = math.max(5000, indicatorSeconds * 1000)
    DynamicHordeEvents.Client.Target = {
        x = tonumber(args.x) or 0,
        y = tonumber(args.y) or 0,
        z = tonumber(args.z) or 0,
        count = tonumber(args.count) or 0,
        createdAtMs = now,
        expiresAtMs = now + lifeMs,
        debugOnly = args.debugOnly == true,
        eventType = tostring(args.eventType or "normal"),
        screenEffectSeconds = tonumber(args.screenEffectSeconds) or 0,
    }
    if not args.debugOnly then DynamicHordeEvents.Client.QueueHordeLine(DynamicHordeEvents.Client.Target.eventType) end
    if not silent then DynamicHordeEvents.Client.PlayWarningSound(DynamicHordeEvents.Client.Target.eventType) end
    DynamicHordeEvents.Client.ShowMessage("DHE: target set, count=" .. tostring(DynamicHordeEvents.Client.Target.count))
end

function DynamicHordeEvents.Client.TestUIOnly()
    local player = getPlayer()
    if not player then
        DynamicHordeEvents.Client.ShowMessage("DHE: no player for UI test")
        return
    end
    DynamicHordeEvents.Client.SetIncomingTarget({
        x = player:getX() + 35,
        y = player:getY() - 15,
        z = player:getZ(),
        count = 123,
        debugOnly = true,
    }, true)
    DynamicHordeEvents.Client.ShowMessage("DHE: UI-only test target created")
end

function DynamicHordeEvents.Client.TestSoundOnly()
    DynamicHordeEvents.Client.PlayWarningSound()
end

function DynamicHordeEvents.Client.TestIndicatorAndSound()
    DynamicHordeEvents.Client.TestUIOnly()
    DynamicHordeEvents.Client.PlayWarningSound()
    DynamicHordeEvents.Client.ShowMessage("DHE: UI + sound local test fired")
end

function DynamicHordeEvents.Client.TestCataclysmUIOnly()
    local player = getPlayer()
    if not player then
        DynamicHordeEvents.Client.ShowMessage("DHE: no player for cataclysm UI test")
        return
    end
    DynamicHordeEvents.Client.SetIncomingTarget({
        x = player:getX() - 80,
        y = player:getY() + 45,
        z = player:getZ(),
        count = 250,
        debugOnly = true,
        eventType = "cataclysm",
        screenEffectSeconds = DynamicHordeEvents.GetNumber("CataclysmScreenEffectSeconds"),
    }, true)
    DynamicHordeEvents.Client.ShowMessage("DHE: cataclysm UI-only test target created")
end

function DynamicHordeEvents.Client.TestCataclysmIndicatorAndSound()
    DynamicHordeEvents.Client.TestCataclysmUIOnly()
    DynamicHordeEvents.Client.PlayWarningSound("cataclysm")
    DynamicHordeEvents.Client.ShowMessage("DHE: cataclysm UI + sound local test fired")
end

function DynamicHordeEvents.Client.TestWanderingUIOnly()
    local player = getPlayer()
    if not player then
        DynamicHordeEvents.Client.ShowMessage("DHE: no player for wandering UI test")
        return
    end
    DynamicHordeEvents.Client.SetIncomingTarget({
        x = player:getX() + 90,
        y = player:getY() + 10,
        z = player:getZ(),
        count = 80,
        debugOnly = true,
        eventType = "wandering",
        routeTargetX = player:getX() - 120,
        routeTargetY = player:getY() - 10,
    }, true)
    DynamicHordeEvents.Client.ShowMessage("DHE: wandering UI-only test target created")
end

function DynamicHordeEvents.Client.TestWanderingIndicatorAndSound()
    DynamicHordeEvents.Client.TestWanderingUIOnly()
    DynamicHordeEvents.Client.PlayWarningSound("wandering")
    DynamicHordeEvents.Client.ShowMessage("DHE: wandering UI + sound local test fired")
end

function DynamicHordeEvents.Client.ClearTarget()
    DynamicHordeEvents.Client.Target = nil
    DynamicHordeEvents.Client.ShowMessage("DHE: indicator cleared")
end

function DynamicHordeEvents.Client.Request(command)
    local player = getPlayer()
    if not player then
        DynamicHordeEvents.Log("No player available for command " .. tostring(command))
        return
    end
    DynamicHordeEvents.Client.ShowMessage("DHE: sending command " .. tostring(command))
    sendClientCommand(player, DynamicHordeEvents.CommandModule, command, {})
end

local function clientNowMs()
    local ms = 0
    pcall(function() ms = getTimestampMs() end)
    return tonumber(ms) or 0
end

local function localPlayerForPursuit(pursuit)
    local player = getPlayer()
    if not player then return nil end

    if pursuit.targetOnlineID ~= nil then
        local onlineId = nil
        pcall(function() onlineId = player:getOnlineID() end)
        if tostring(onlineId) == tostring(pursuit.targetOnlineID) then return player end
    end

    local dx = math.abs((player:getX() or 0) - (pursuit.targetX or 0))
    local dy = math.abs((player:getY() or 0) - (pursuit.targetY or 0))
    if dx <= 6 and dy <= 6 then return player end

    return nil
end

local function zombieLooksValid(zombie)
    if not zombie then return false end
    local dead = false
    local ok = pcall(function() dead = zombie:isDead() end)
    return (not ok) or dead ~= true
end

local function zombieInsidePursuitArea(zombie, pursuit)
    if not zombieLooksValid(zombie) then return false end

    local zx, zy, zz = 0, 0, 0
    local ok = pcall(function()
        zx = zombie:getX()
        zy = zombie:getY()
        zz = zombie:getZ()
    end)
    if not ok then return false end

    local targetZ = tonumber(pursuit.targetZ) or tonumber(pursuit.z) or 0
    if math.abs((tonumber(zz) or 0) - targetZ) > 0.6 then return false end

    local margin = math.max(40, tonumber(pursuit.margin) or 100)
    local minX = math.min(tonumber(pursuit.spawnX) or 0, tonumber(pursuit.targetX) or 0) - margin
    local maxX = math.max(tonumber(pursuit.spawnX) or 0, tonumber(pursuit.targetX) or 0) + margin
    local minY = math.min(tonumber(pursuit.spawnY) or 0, tonumber(pursuit.targetY) or 0) - margin
    local maxY = math.max(tonumber(pursuit.spawnY) or 0, tonumber(pursuit.targetY) or 0) + margin

    return zx >= minX and zx <= maxX and zy >= minY and zy <= maxY
end

local function commandLocalCataclysmZombie(zombie, pursuit, targetPlayer)
    local tx = tonumber(pursuit.targetX) or 0
    local ty = tonumber(pursuit.targetY) or 0
    local tz = tonumber(pursuit.targetZ) or tonumber(pursuit.z) or 0
    local sx = math.floor(tx)
    local sy = math.floor(ty)
    local sz = math.floor(tz)

    local applied = false
    local function try(fn)
        local ok = pcall(fn)
        if ok then applied = true end
    end

    try(function() zombie:setLastHeardSound(sx, sy, sz) end)
    if targetPlayer then
        try(function() zombie:setTarget(targetPlayer) end)
        try(function() zombie:addAggro(targetPlayer, 1000.0) end)
        try(function() zombie:spotted(targetPlayer, true) end)
    end
    try(function() zombie:pathToLocation(sx, sy, sz) end)
    try(function() zombie:pathToLocationF(tx, ty, tz) end)
    try(function() zombie:pathToSound(sx, sy, sz) end)
    try(function() zombie:setUseless(false) end)
    try(function() zombie:makeInactive(false) end)
    try(function() zombie:setVariable("bMoving", true) end)

    return applied
end

function DynamicHordeEvents.Client.ReceiveCataclysmPursuit(args)
    args = args or {}
    local id = tostring(args.id or "cataclysm")
    local now = clientNowMs()
    local pursuit = DynamicHordeEvents.Client.CataclysmPursuits[id] or {}

    pursuit.id = id
    pursuit.spawnX = tonumber(args.spawnX) or pursuit.spawnX or 0
    pursuit.spawnY = tonumber(args.spawnY) or pursuit.spawnY or 0
    pursuit.z = tonumber(args.z) or pursuit.z or 0
    pursuit.targetX = tonumber(args.targetX) or pursuit.targetX or 0
    pursuit.targetY = tonumber(args.targetY) or pursuit.targetY or 0
    pursuit.targetZ = tonumber(args.targetZ) or pursuit.targetZ or pursuit.z
    pursuit.margin = tonumber(args.margin) or pursuit.margin or 100
    pursuit.count = tonumber(args.count) or pursuit.count or 0
    pursuit.targetOnlineID = args.targetOnlineID
    pursuit.expiresAtMs = now + math.max(3000, tonumber(args.clientLifeMs) or 10000)
    pursuit.nextUpdateAtMs = math.min(tonumber(pursuit.nextUpdateAtMs) or now, now)

    DynamicHordeEvents.Client.CataclysmPursuits[id] = pursuit
end

function DynamicHordeEvents.Client.ApplyCataclysmPursuit(pursuit)
    local cell = getCell()
    if not cell then return 0 end

    local zombies = nil
    local okList = pcall(function() zombies = cell:getZombieList() end)
    if not okList or not zombies then return 0 end

    local targetPlayer = localPlayerForPursuit(pursuit)
    local applied = 0
    for i = 0, zombies:size() - 1 do
        local zombie = zombies:get(i)
        if zombieInsidePursuitArea(zombie, pursuit) then
            if commandLocalCataclysmZombie(zombie, pursuit, targetPlayer) then
                applied = applied + 1
            end
        end
    end

    return applied
end

function DynamicHordeEvents.Client.UpdateCataclysmPursuits()
    local pending = DynamicHordeEvents.PendingCataclysmPursuit
    if pending then
        DynamicHordeEvents.PendingCataclysmPursuit = nil
        DynamicHordeEvents.Client.ReceiveCataclysmPursuit(pending)
    end

    local now = clientNowMs()
    for id, pursuit in pairs(DynamicHordeEvents.Client.CataclysmPursuits) do
        if now >= (tonumber(pursuit.expiresAtMs) or 0) then
            DynamicHordeEvents.Client.CataclysmPursuits[id] = nil
        elseif now >= (tonumber(pursuit.nextUpdateAtMs) or 0) then
            local applied = DynamicHordeEvents.Client.ApplyCataclysmPursuit(pursuit)
            pursuit.nextUpdateAtMs = now + CATACLYSM_CLIENT_PURSUIT_UPDATE_MS
            if now >= (tonumber(pursuit.nextReportAtMs) or 0) then
                DynamicHordeEvents.DebugPrint("DHE: cataclysm client pursuit nudged " .. tostring(applied) .. " local zombie(s)")
                pursuit.nextReportAtMs = now + CATACLYSM_CLIENT_PURSUIT_REPORT_MS
            end
        end
    end
end


function DynamicHordeEvents.Client.ConsumePendingIncoming()
    DynamicHordeEvents.Client.ProcessPendingSpeech()
    local pending = DynamicHordeEvents.PendingIncoming
    if not pending then return end

    local createdAt = tonumber(pending.createdAtMs) or 0
    if createdAt > 0 and createdAt == DynamicHordeEvents.Client.LastPendingHandledAt then return end

    DynamicHordeEvents.Client.LastPendingHandledAt = createdAt
    DynamicHordeEvents.PendingIncoming = nil
    DynamicHordeEvents.Client.SetIncomingTarget(pending, false)
    DynamicHordeEvents.DebugPrint("DHE: consumed pending incoming payload")
end

if Events.OnTick then
    Events.OnTick.Add(DynamicHordeEvents.Client.ConsumePendingIncoming)
    Events.OnTick.Add(DynamicHordeEvents.Client.UpdateCataclysmPursuits)
end

function DynamicHordeEvents.Client.OnServerCommand(module, command, args)
    if module ~= DynamicHordeEvents.CommandModule then return end

    if command == "Incoming" then
        DynamicHordeEvents.Client.SetIncomingTarget(args, false)
    elseif command == "CataclysmPursuitUpdate" then
        DynamicHordeEvents.Client.ReceiveCataclysmPursuit(args)
    elseif command == "DebugMessage" then
        DynamicHordeEvents.Client.ShowMessage(args and args.text or "DHE: debug message")
    end
end

Events.OnServerCommand.Add(DynamicHordeEvents.Client.OnServerCommand)

Events.OnGameStart.Add(function()
    DynamicHordeEvents.Client.Target = nil
    DynamicHordeEvents.Client.PendingSpeech = nil
    DynamicHordeEvents.Client.CataclysmPursuits = {}
    DynamicHordeEvents.DebugPrint("DHE client loaded " .. tostring(DynamicHordeEvents.Version))
end)
