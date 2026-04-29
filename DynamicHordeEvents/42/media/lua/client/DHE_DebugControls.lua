-- Dynamic Horde Events B42 Debug
-- Test controls: right-click context menu, F6/F7/F8 hotkeys.

require "DHE_Config"

local function addDebugContext(playerIndex, context, worldObjects, test)
    if not DynamicHordeEvents.GetBool("EnableDebugContextMenu") then return end
    if test then return true end

    context:addOption("DHE: Test UI only", nil, function()
        DynamicHordeEvents.Client.TestUIOnly()
    end)

    context:addOption("DHE: Test sound only", nil, function()
        DynamicHordeEvents.Client.TestSoundOnly()
    end)

    context:addOption("DHE: Test UI + sound only", nil, function()
        DynamicHordeEvents.Client.TestIndicatorAndSound()
    end)

    context:addOption("DHE: Test spawn near player", nil, function()
        DynamicHordeEvents.Client.Request("TestSpawnNear")
    end)

    context:addOption("DHE: Force normal horde event", nil, function()
        DynamicHordeEvents.Client.Request("ForceSpawn")
    end)

    context:addOption("DHE: Clear indicator", nil, function()
        DynamicHordeEvents.Client.ClearTarget()
    end)

    context:addOption("DHE: Print status", nil, function()
        DynamicHordeEvents.Client.Request("Status")
    end)
end

Events.OnFillWorldObjectContextMenu.Add(addDebugContext)

local function onKeyPressed(key)
    if not DynamicHordeEvents.GetBool("EnableDebugHotkey") then return end

    local f6 = Keyboard and Keyboard.KEY_F6 or nil
    local f7 = Keyboard and Keyboard.KEY_F7 or nil
    local f8 = Keyboard and Keyboard.KEY_F8 or nil

    if f6 and key == f6 then
        DynamicHordeEvents.Client.Request("TestSpawnNear")
    elseif f7 and key == f7 then
        DynamicHordeEvents.Client.TestIndicatorAndSound()
    elseif f8 and key == f8 then
        DynamicHordeEvents.Client.ClearTarget()
    end
end

if Events.OnKeyPressed then
    Events.OnKeyPressed.Add(onKeyPressed)
end
