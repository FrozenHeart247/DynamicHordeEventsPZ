-- Dynamic Horde Events B42 Debug
-- Shared config helpers. Reads SandboxVars.DynamicHordeEvents when available.

DynamicHordeEvents = DynamicHordeEvents or {}
DynamicHordeEvents.ID = "DynamicHordeEventsB42"
DynamicHordeEvents.CommandModule = "DynamicHordeEventsB42"
DynamicHordeEvents.Version = "0.6.1-cataclysm-spawn-fix"

DynamicHordeEvents.Defaults = {
    Enabled = true,
    MinSpawnHours = 12,
    MaxSpawnHours = 48,
    CooldownHours = 0,
    MinZombies = 5,
    MaxZombies = 30,
    ScalingMode = 1, -- 1=Off, 2=Days survived, 3=Months survived
    ScalingInterval = 7, -- days or months depending on ScalingMode
    ScalingMultiplierPercent = 25, -- added horde size per interval
    ScalingMaxMultiplierPercent = 300, -- cap; 100=base size, 300=triple size
    MinSpawnRadius = 80,
    MaxSpawnRadius = 150,
    DisableAtNight = false,
    NightStartHour = 22,
    NightEndHour = 5,
    EnableDirectionIndicator = false,
    IndicatorSeconds = 20,
    EnableWarningSound = true,
    WarningSound = "DynamicHordeWarning",
    FallbackWarningSound = "ZombieSurprisedPlayer",
    AttractionRadius = 500,
    AttractionVolume = 500,
    AvoidIndoorSpawn = true,
    SpawnSearchAttempts = 64,
    Debug = false,
    EnableDebugContextMenu = false,
    EnableDebugHotkey = false,
    TestSpawnRadius = 25,
    TestZombieCount = 10,

    -- Rare ultra-hardcore event layer. Separate from normal horde scaling.
    EnableCataclysmHorde = true,
    CataclysmMinDays = 90,
    CataclysmMaxDays = 120,
    CataclysmMinZombies = 150,
    CataclysmMaxZombies = 300,
    CataclysmMinSpawnRadius = 140,
    CataclysmMaxSpawnRadius = 240,
    CataclysmIndicatorSeconds = 45,
    CataclysmAttractionRadius = 800,
    CataclysmAttractionVolume = 800,
    EnableCataclysmWeather = true,
    EnableCataclysmScreenEffect = true,
    CataclysmScreenEffectSeconds = 15,
}

local function readSandboxValue(key)
    if SandboxVars and SandboxVars.DynamicHordeEvents and SandboxVars.DynamicHordeEvents[key] ~= nil then
        return SandboxVars.DynamicHordeEvents[key]
    end
    return DynamicHordeEvents.Defaults[key]
end

function DynamicHordeEvents.Get(key)
    return readSandboxValue(key)
end

function DynamicHordeEvents.GetNumber(key)
    local value = tonumber(readSandboxValue(key))
    if value == nil then return tonumber(DynamicHordeEvents.Defaults[key]) or 0 end
    return value
end

function DynamicHordeEvents.GetBool(key)
    local value = readSandboxValue(key)
    return value == true or value == 1 or value == "true"
end

function DynamicHordeEvents.Log(message)
    print("[DynamicHordeEvents] " .. tostring(message))
end

function DynamicHordeEvents.DebugPrint(message)
    if DynamicHordeEvents.GetBool("Debug") then
        DynamicHordeEvents.Log(message)
    end
end
