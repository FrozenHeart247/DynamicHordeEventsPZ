-- Dynamic Horde Events B42
-- Client command handling: warning sound + UI target. Debug messages are sandbox-gated.

require "DHE_Config"

DynamicHordeEvents.Client = DynamicHordeEvents.Client or {}
DynamicHordeEvents.Client.Target = nil
DynamicHordeEvents.Client.LastMessage = nil
DynamicHordeEvents.Client.LastMessageAt = 0
DynamicHordeEvents.Client.LastPendingHandledAt = 0

local function getPlayer()
    return getSpecificPlayer(0)
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

function DynamicHordeEvents.Client.PlayWarningSound()
    if not DynamicHordeEvents.GetBool("EnableWarningSound") then
        DynamicHordeEvents.Client.ShowMessage("DHE: warning sound disabled in sandbox")
        return false
    end

    local preferred = tostring(DynamicHordeEvents.Get("WarningSound") or "DynamicHordeWarning")
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
    local lifeMs = math.max(5000, DynamicHordeEvents.GetNumber("IndicatorSeconds") * 1000)
    DynamicHordeEvents.Client.Target = {
        x = tonumber(args.x) or 0,
        y = tonumber(args.y) or 0,
        z = tonumber(args.z) or 0,
        count = tonumber(args.count) or 0,
        createdAtMs = now,
        expiresAtMs = now + lifeMs,
        debugOnly = args.debugOnly == true,
    }
    if not silent then DynamicHordeEvents.Client.PlayWarningSound() end
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


function DynamicHordeEvents.Client.ConsumePendingIncoming()
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
end

function DynamicHordeEvents.Client.OnServerCommand(module, command, args)
    if module ~= DynamicHordeEvents.CommandModule then return end

    if command == "Incoming" then
        DynamicHordeEvents.Client.SetIncomingTarget(args, false)
    elseif command == "DebugMessage" then
        DynamicHordeEvents.Client.ShowMessage(args and args.text or "DHE: debug message")
    end
end

Events.OnServerCommand.Add(DynamicHordeEvents.Client.OnServerCommand)

Events.OnGameStart.Add(function()
    DynamicHordeEvents.Client.Target = nil
    DynamicHordeEvents.DebugPrint("DHE client loaded " .. tostring(DynamicHordeEvents.Version))
end)
