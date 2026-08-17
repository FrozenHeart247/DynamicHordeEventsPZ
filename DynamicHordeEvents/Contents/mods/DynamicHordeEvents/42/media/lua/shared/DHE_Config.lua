-- Dynamic Horde Events B42 Debug
-- Shared config helpers. Reads SandboxVars.DynamicHordeEvents when available.

DynamicHordeEvents = DynamicHordeEvents or {}
DynamicHordeEvents.ID = "DynamicHordeEventsB42"
DynamicHordeEvents.CommandModule = "DynamicHordeEventsB42"
DynamicHordeEvents.Version = "0.10.1-b42.20-indicator"

DynamicHordeEvents.Defaults = {
    Enabled = true,
    EnableEventNotifications = true,
    EnableNormalHorde = true,
    NormalScheduleMode = 1, -- 1=random interval, 2=fixed days + hour
    NormalFixedIntervalDays = 7,
    NormalFixedHour = 22,
    MinSpawnHours = 12,
    MaxSpawnHours = 48,
    CooldownHours = 0,
    MinZombies = 5,
    MaxZombies = 30,
    ScalingMode = 2, -- 1=Off, 2=Days survived, 3=Months survived
    ScalingInterval = 7, -- days or months depending on ScalingMode
    ScalingMultiplierPercent = 10, -- added horde size per interval
    ScalingMaxMultiplierPercent = 150, -- cap; 100=base size, 150=1.5x size
    MinSpawnRadius = 80,
    MaxSpawnRadius = 200,
    DisableAtNight = false,
    NightStartHour = 22,
    NightEndHour = 5,
    EnableDirectionIndicator = true,
    IndicatorSeconds = 20,
    EnableWarningSound = true,
    WarningSound = "DynamicHordeWarning",
    FallbackWarningSound = "ZombieSurprisedPlayer",
    AttractionRadius = 500,
    AttractionVolume = 500,
    EnableNormalHordePursuit = false,
    EnableNormalHordePathAssist = false,
    MPAttractionDelaySeconds = 7,
    EnableMPActiveSpawnClamp = true,
    MPActiveSpawnMaxRadius = 70,
    AvoidIndoorSpawn = true,
    SpawnSearchAttempts = 64,
    Debug = false,
    EnableDebugContextMenu = false,
    EnableDebugHotkey = false,
    TestSpawnRadius = 25,
    TestZombieCount = 10,

    -- Rare ultra-hardcore event layer. Separate from normal horde scaling.
    EnableCataclysmHorde = true,
    CataclysmScheduleMode = 1,
    CataclysmFixedIntervalDays = 90,
    CataclysmFixedHour = 22,
    CataclysmMinDays = 90,
    CataclysmMaxDays = 120,
    CataclysmMinZombies = 200,
    CataclysmMaxZombies = 500,
    CataclysmMinSpawnRadius = 140,
    CataclysmMaxSpawnRadius = 240,
    CataclysmIndicatorSeconds = 25,
    CataclysmAttractionRadius = 800,
    CataclysmAttractionVolume = 800,
    EnableCataclysmPursuit = true,
    CataclysmPursuitHours = 4.0,
    EnableCataclysmWeather = true,
    CataclysmWeatherDurationHours = 8,
    EnableCataclysmFogWind = true,
    CataclysmFogIntensity = 1.0,
    CataclysmWindIntensity = 0.75,
    CataclysmCloudIntensity = 1.0,
    CataclysmDesaturation = 0.45,
    EnableCataclysmScreenEffect = true,
    CataclysmScreenEffectSeconds = 15,

    -- Wandering horde: passes through/near the player area instead of directly targeting the player.
    EnableWanderingHorde = true,
    WanderingScheduleMode = 1,
    WanderingFixedIntervalDays = 1,
    WanderingFixedHour = 22,
    WanderingMinHours = 48,
    WanderingMaxHours = 120,
    WanderingMinZombies = 40,
    WanderingMaxZombies = 120,
    WanderingMinSpawnRadius = 140,
    WanderingMaxSpawnRadius = 220,
    WanderingExitDistance = 300,
    WanderingSpread = 18,
    WanderingIndicatorSeconds = 35,
    WanderingAttractionRadius = 900,
    WanderingAttractionVolume = 900,
    WanderingWarningSound = "DynamicHordeWanderingWarning",

    -- Short survivor voice lines shown above the player when a real event starts.
    EnableNormalHordeSpeech = true,
    EnableCataclysmHordeSpeech = true,
    EnableWanderingHordeSpeech = true,
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
    if type(value) == "string" then value = string.lower(value) end
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
