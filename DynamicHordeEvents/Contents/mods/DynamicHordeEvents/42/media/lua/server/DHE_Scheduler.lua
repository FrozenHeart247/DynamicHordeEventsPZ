-- Persistent event scheduling for Dynamic Horde Events.

require "DHE_Config"

DynamicHordeEvents.Scheduler = DynamicHordeEvents.Scheduler or {}
local Scheduler = DynamicHordeEvents.Scheduler

Scheduler.ModDataKey = "DynamicHordeEventsB42_Scheduler"
Scheduler.SchemaVersion = 1

local EVENT_ORDER = { "normal", "wandering", "cataclysm" }
local EVENT_DEFINITIONS = {
    normal = {
        enabledKey = "EnableNormalHorde",
        modeKey = "NormalScheduleMode",
        randomMinKey = "MinSpawnHours",
        randomMaxKey = "MaxSpawnHours",
        randomUnitHours = 1,
        fixedDaysKey = "NormalFixedIntervalDays",
        fixedHourKey = "NormalFixedHour",
        cooldownKey = "CooldownHours",
    },
    wandering = {
        enabledKey = "EnableWanderingHorde",
        modeKey = "WanderingScheduleMode",
        randomMinKey = "WanderingMinHours",
        randomMaxKey = "WanderingMaxHours",
        randomUnitHours = 1,
        fixedDaysKey = "WanderingFixedIntervalDays",
        fixedHourKey = "WanderingFixedHour",
    },
    cataclysm = {
        enabledKey = "EnableCataclysmHorde",
        modeKey = "CataclysmScheduleMode",
        randomMinKey = "CataclysmMinDays",
        randomMaxKey = "CataclysmMaxDays",
        randomUnitHours = 24,
        fixedDaysKey = "CataclysmFixedIntervalDays",
        fixedHourKey = "CataclysmFixedHour",
    },
}

local memoryRoot = {
    schemaVersion = Scheduler.SchemaVersion,
    events = {},
    meta = {},
}
local runtimeInitialized = false

local function clampInteger(value, minimum, maximum)
    value = math.floor(tonumber(value) or minimum)
    if value < minimum then value = minimum end
    if maximum ~= nil and value > maximum then value = maximum end
    return value
end

local function randomBetween(minimum, maximum)
    minimum = math.floor(tonumber(minimum) or 0)
    maximum = math.floor(tonumber(maximum) or minimum)
    if maximum < minimum then maximum = minimum end
    if maximum == minimum then return minimum end

    if type(ZombRand) == "function" then
        return ZombRand(minimum, maximum + 1)
    end
    return math.random(minimum, maximum)
end

local function getRoot()
    local root = nil
    if ModData and ModData.getOrCreate then
        pcall(function()
            root = ModData.getOrCreate(Scheduler.ModDataKey)
        end)
    end
    if type(root) ~= "table" then root = memoryRoot end

    root.schemaVersion = Scheduler.SchemaVersion
    if type(root.events) ~= "table" then root.events = {} end
    if type(root.meta) ~= "table" then root.meta = {} end
    return root
end

local function getEventState(eventType)
    local root = getRoot()
    local state = root.events[eventType]
    if type(state) ~= "table" then
        state = {}
        root.events[eventType] = state
    end
    return state
end

local function getPolicy(eventType)
    local definition = EVENT_DEFINITIONS[eventType]
    if not definition then return nil end

    local mode = clampInteger(DynamicHordeEvents.GetNumber(definition.modeKey), 1, 2)
    local randomMinimum = clampInteger(DynamicHordeEvents.GetNumber(definition.randomMinKey), 1)
    local randomMaximum = clampInteger(DynamicHordeEvents.GetNumber(definition.randomMaxKey), randomMinimum)
    local fixedDays = clampInteger(DynamicHordeEvents.GetNumber(definition.fixedDaysKey), 1)
    local fixedHour = clampInteger(DynamicHordeEvents.GetNumber(definition.fixedHourKey), 0, 23)
    local cooldown = 0
    if definition.cooldownKey then
        cooldown = clampInteger(DynamicHordeEvents.GetNumber(definition.cooldownKey), 0)
    end

    local policy = {
        eventType = eventType,
        definition = definition,
        mode = mode,
        randomMinimum = randomMinimum,
        randomMaximum = randomMaximum,
        randomUnitHours = definition.randomUnitHours,
        fixedDays = fixedDays,
        fixedHour = fixedHour,
        cooldownHours = cooldown,
    }
    policy.fingerprint = table.concat({
        tostring(mode),
        tostring(randomMinimum),
        tostring(randomMaximum),
        tostring(definition.randomUnitHours),
        tostring(fixedDays),
        tostring(fixedHour),
        tostring(cooldown),
    }, ":")
    return policy
end

local function eventEnabled(policy)
    return DynamicHordeEvents.GetBool("Enabled")
        and DynamicHordeEvents.GetBool(policy.definition.enabledKey)
end

local function getClockHour(fallbackWorldHour)
    local hour = nil
    local minute = 0
    pcall(function()
        local gameTime = getGameTime()
        hour = gameTime:getHour()
        if gameTime.getMinutes then minute = gameTime:getMinutes() end
    end)
    if hour == nil then return fallbackWorldHour % 24 end
    return clampInteger(hour, 0, 23) + (clampInteger(minute, 0, 59) / 60)
end

local function nextFixedHour(policy, fromHour, previousDeadline)
    local intervalHours = policy.fixedDays * 24
    local target = nil

    if previousDeadline ~= nil then
        target = tonumber(previousDeadline) + intervalHours
    else
        local currentClockHour = getClockHour(fromHour)
        target = fromHour + intervalHours + (policy.fixedHour - currentClockHour)
    end

    while target <= fromHour + 0.0001 do
        target = target + intervalHours
    end
    return target
end

local function scheduleFrom(state, policy, fromHour, reason, previousDeadline)
    local target = nil
    local rolledDelay = nil
    if policy.mode == 2 then
        target = nextFixedHour(policy, fromHour, previousDeadline)
    else
        rolledDelay = randomBetween(policy.randomMinimum, policy.randomMaximum) * policy.randomUnitHours
        target = fromHour + rolledDelay
    end

    local lastSuccessHour = tonumber(state.lastSuccessHour)
    if policy.eventType == "normal" and policy.cooldownHours > 0 and lastSuccessHour ~= nil then
        local cooldownDeadline = lastSuccessHour + policy.cooldownHours
        if policy.mode == 2 then
            local fixedIntervalHours = policy.fixedDays * 24
            while target < cooldownDeadline - 0.0001 do
                target = target + fixedIntervalHours
            end
        else
            target = math.max(target, cooldownDeadline)
        end
    end

    state.nextHour = target
    state.nextAttemptHour = target
    state.lastScheduleReason = tostring(reason or "scheduled")
    state.lastRolledDelayHours = rolledDelay
    state.policyFingerprint = policy.fingerprint
    return target
end

function Scheduler.GetWorldHour()
    local hour = 0
    pcall(function()
        hour = getGameTime():getWorldAgeHours()
    end)
    return math.max(0, tonumber(hour) or 0)
end

function Scheduler.EnsureEvent(eventType, worldHour)
    local policy = getPolicy(eventType)
    if not policy then return nil, nil end

    worldHour = tonumber(worldHour) or Scheduler.GetWorldHour()
    local state = getEventState(eventType)
    local policyChanged = state.policyFingerprint ~= nil and state.policyFingerprint ~= policy.fingerprint

    if policyChanged then
        state.nextHour = nil
        state.nextAttemptHour = nil
        state.lastScheduleReason = "sandbox-settings-changed"
    end
    state.policyFingerprint = policy.fingerprint

    if not eventEnabled(policy) then
        if state.pausedAtHour == nil then state.pausedAtHour = worldHour end
        return state, policy
    end

    if state.pausedAtHour ~= nil then
        local pausedDuration = math.max(0, worldHour - (tonumber(state.pausedAtHour) or worldHour))
        if state.nextHour ~= nil then state.nextHour = tonumber(state.nextHour) + pausedDuration end
        if state.nextAttemptHour ~= nil then state.nextAttemptHour = tonumber(state.nextAttemptHour) + pausedDuration end
        state.pausedAtHour = nil
    end

    if state.nextHour == nil then
        scheduleFrom(state, policy, worldHour, policyChanged and "settings-changed" or "initialized", nil)
    elseif state.nextAttemptHour == nil then
        state.nextAttemptHour = state.nextHour
    end

    return state, policy
end

function Scheduler.Initialize(worldHour)
    worldHour = tonumber(worldHour) or Scheduler.GetWorldHour()
    for _, eventType in ipairs(EVENT_ORDER) do
        Scheduler.EnsureEvent(eventType, worldHour)
    end
    runtimeInitialized = true
    return getRoot()
end

function Scheduler.IsInitialized()
    return runtimeInitialized
end

function Scheduler.IsDue(eventType, worldHour)
    worldHour = tonumber(worldHour) or Scheduler.GetWorldHour()
    local state, policy = Scheduler.EnsureEvent(eventType, worldHour)
    if not state or not policy or not eventEnabled(policy) then return false end

    local deadline = tonumber(state.nextHour)
    local nextAttempt = tonumber(state.nextAttemptHour) or deadline
    if deadline == nil then return false end
    return worldHour + 0.0001 >= deadline and worldHour + 0.0001 >= nextAttempt
end

function Scheduler.MarkSuccess(eventType, worldHour)
    worldHour = tonumber(worldHour) or Scheduler.GetWorldHour()
    local state, policy = Scheduler.EnsureEvent(eventType, worldHour)
    if not state or not policy then return nil end

    local completedDeadline = tonumber(state.nextHour)
    state.lastSuccessHour = worldHour
    state.lastResult = "success"
    state.failureCount = 0
    return scheduleFrom(
        state,
        policy,
        worldHour,
        "event-completed",
        policy.mode == 2 and completedDeadline or nil
    )
end

function Scheduler.MarkSkipped(eventType, worldHour, reason)
    worldHour = tonumber(worldHour) or Scheduler.GetWorldHour()
    local state, policy = Scheduler.EnsureEvent(eventType, worldHour)
    if not state or not policy then return nil end

    local skippedDeadline = tonumber(state.nextHour)
    state.lastResult = "skipped:" .. tostring(reason or "unknown")
    return scheduleFrom(
        state,
        policy,
        worldHour,
        state.lastResult,
        policy.mode == 2 and skippedDeadline or nil
    )
end

function Scheduler.DeferFailure(eventType, worldHour, retryHours, reason)
    worldHour = tonumber(worldHour) or Scheduler.GetWorldHour()
    local state = Scheduler.EnsureEvent(eventType, worldHour)
    if not state then return nil end

    retryHours = math.max(1 / 6, tonumber(retryHours) or 1)
    state.nextAttemptHour = worldHour + retryHours
    state.lastResult = "failed:" .. tostring(reason or "spawn")
    state.failureCount = (tonumber(state.failureCount) or 0) + 1
    return state.nextAttemptHour
end

function Scheduler.GetSnapshot(eventType, worldHour)
    worldHour = tonumber(worldHour) or Scheduler.GetWorldHour()
    local state, policy = Scheduler.EnsureEvent(eventType, worldHour)
    if not state or not policy then return nil end

    return {
        eventType = eventType,
        enabled = eventEnabled(policy),
        mode = policy.mode,
        nextHour = tonumber(state.nextHour),
        nextAttemptHour = tonumber(state.nextAttemptHour),
        lastSuccessHour = tonumber(state.lastSuccessHour),
        lastResult = state.lastResult,
        failureCount = tonumber(state.failureCount) or 0,
        pausedAtHour = tonumber(state.pausedAtHour),
        fixedDays = policy.fixedDays,
        fixedHour = policy.fixedHour,
        randomMinimum = policy.randomMinimum,
        randomMaximum = policy.randomMaximum,
        randomUnitHours = policy.randomUnitHours,
    }
end

function Scheduler.GetMeta(key)
    return getRoot().meta[key]
end

function Scheduler.SetMeta(key, value)
    getRoot().meta[key] = value
end

return Scheduler
