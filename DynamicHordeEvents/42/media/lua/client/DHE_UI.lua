-- Dynamic Horde Events B42 Debug
-- Texture-capable indicator. Still render-only: no ISPanel, no mouse capture.

require "DHE_Config"

local DHE_UI = {
    ring = nil,
    blip = nil,
    alert = nil,
    redOverlay = nil,
    textureStatusLogged = false,
    lastHeartbeatAt = 0,
    lastRenderErrorAt = 0,
}

local function normalizeAngleDegrees(degrees)
    degrees = degrees % 360
    if degrees < 0 then degrees = degrees + 360 end
    return degrees
end

local function getCompassLabel(degrees)
    degrees = normalizeAngleDegrees(degrees)
    if degrees >= 337.5 or degrees < 22.5 then return "E" end
    if degrees < 67.5 then return "SE" end
    if degrees < 112.5 then return "S" end
    if degrees < 157.5 then return "SW" end
    if degrees < 202.5 then return "W" end
    if degrees < 247.5 then return "NW" end
    if degrees < 292.5 then return "N" end
    return "NE"
end

local function drawShadowText(font, x, y, text, r, g, b, a)
    text = tostring(text or "")
    getTextManager():DrawString(font, x + 2, y + 2, text, 0, 0, 0, math.min(a or 1, 0.85))
    getTextManager():DrawString(font, x, y, text, r or 1, g or 1, b or 1, a or 1)
end

local function drawShadowTextCentre(font, x, y, text, r, g, b, a)
    text = tostring(text or "")
    getTextManager():DrawStringCentre(font, x + 2, y + 2, text, 0, 0, 0, math.min(a or 1, 0.85))
    getTextManager():DrawStringCentre(font, x, y, text, r or 1, g or 1, b or 1, a or 1)
end

local function loadTextures()
    if DHE_UI.ring ~= nil then return true end

    DHE_UI.ring = getTexture("media/ui/dhe_ring.png")
    DHE_UI.blip = getTexture("media/ui/dhe_blip.png")
    DHE_UI.alert = getTexture("media/ui/dhe_alert.png")
    DHE_UI.redOverlay = getTexture("media/ui/dhe_red_overlay.png")

    if not DHE_UI.textureStatusLogged then
        DHE_UI.textureStatusLogged = true
        if DHE_UI.ring and DHE_UI.blip and DHE_UI.alert then
            DynamicHordeEvents.DebugPrint("DHE UI textures loaded")
        else
            DynamicHordeEvents.DebugPrint("DHE UI textures not loaded, text fallback will be used")
        end
    end

    return DHE_UI.ring ~= nil and DHE_UI.blip ~= nil and DHE_UI.alert ~= nil
end

function DynamicHordeEvents.PreloadHordeUITextures()
    pcall(loadTextures)
end

-- Kick texture loading as early as this file is loaded. PZ loads PNG assets async,
-- so lazy-loading only on the first horde can make the first marker appear late.
pcall(loadTextures)
if Events.OnGameBoot then Events.OnGameBoot.Add(DynamicHordeEvents.PreloadHordeUITextures) end
if Events.OnGameStart then Events.OnGameStart.Add(DynamicHordeEvents.PreloadHordeUITextures) end
if Events.OnCreatePlayer then Events.OnCreatePlayer.Add(function() DynamicHordeEvents.PreloadHordeUITextures() end) end

local function renderLastMessage()
    if DynamicHordeEvents.Client and DynamicHordeEvents.Client.LastMessage then
        local ageMsg = getTimestampMs() - (DynamicHordeEvents.Client.LastMessageAt or 0)
        if ageMsg < 12000 then
            drawShadowText(UIFont.Small, 20, 70, DynamicHordeEvents.Client.LastMessage, 1, 1, 1, 1)
        end
    end
end

local function renderCataclysmScreenEffect(target, now)
    if not target or target.eventType ~= "cataclysm" then return end
    if not DynamicHordeEvents.GetBool("EnableCataclysmScreenEffect") then return end
    if not UIManager or not UIManager.DrawTexture then return end

    local effectSeconds = tonumber(target.screenEffectSeconds) or DynamicHordeEvents.GetNumber("CataclysmScreenEffectSeconds")
    if effectSeconds <= 0 then return end

    local elapsed = (now - (target.createdAtMs or now)) / 1000.0
    if elapsed > effectSeconds then return end

    local fade = 1.0
    if elapsed < 2.0 then fade = elapsed / 2.0 end
    if effectSeconds - elapsed < 3.0 then fade = math.min(fade, math.max(0, (effectSeconds - elapsed) / 3.0)) end

    local pulse = 0.55 + 0.45 * math.abs(math.sin(now / 180.0))
    local alpha = 0.10 * fade * pulse
    local overlay = DHE_UI.redOverlay
    if not overlay then
        pcall(function() overlay = getTexture("media/ui/dhe_red_overlay.png") end)
        DHE_UI.redOverlay = overlay
    end
    if not overlay then return end

    local w = getCore():getScreenWidth()
    local h = getCore():getScreenHeight()
    pcall(function()
        UIManager.DrawTexture(overlay, 0, 0, w, h, alpha)
    end)
end

local function drawTextureWidget(target, centerX, centerY, angleRad, label, distance, secondsLeft, alpha)
    if not loadTextures() then return false end
    if not UIManager or not UIManager.DrawTexture then return false end

    local ok, err = pcall(function()
        local size = 160
        local x = centerX - size / 2
        local y = centerY - size / 2
        UIManager.DrawTexture(DHE_UI.ring, x, y, size, size, alpha)
        UIManager.DrawTexture(DHE_UI.alert, centerX - 20, centerY - 20, 40, 40, alpha)

        local r = 60
        local bs = 18
        local bx = centerX + math.cos(angleRad) * r - bs / 2
        local by = centerY + math.sin(angleRad) * r - bs / 2
        UIManager.DrawTexture(DHE_UI.blip, bx, by, bs, bs, alpha)
    end)

    if not ok then
        local now = getTimestampMs()
        if now - DHE_UI.lastRenderErrorAt > 3000 then
            DHE_UI.lastRenderErrorAt = now
            DynamicHordeEvents.Log("DHE texture draw failed: " .. tostring(err))
        end
        return false
    end
    return true
end

local function renderFallbackBox(target, centerX, centerY, label, distance, secondsLeft, alpha)
    local title = "HORDE"
    if target and target.eventType == "cataclysm" then title = "CATACLYSM" end
    drawShadowTextCentre(UIFont.Medium, centerX, centerY - 34, title, 1, 0.05, 0.05, alpha)
    drawShadowTextCentre(UIFont.Medium, centerX, centerY - 12, "[" .. label .. "]", 1, 0.25, 0.25, alpha)
    drawShadowTextCentre(UIFont.Small, centerX, centerY + 12, string.format("%.0f tiles", distance), 1, 1, 1, alpha)
    drawShadowTextCentre(UIFont.Small, centerX, centerY + 30, string.format("count:%d  %ds", target.count or 0, math.max(0, math.floor(secondsLeft))), 1, 1, 1, alpha)
end

local function renderIndicatorRaw()
    renderLastMessage()

    if not DynamicHordeEvents.GetBool("EnableDirectionIndicator") then return end
    if not DynamicHordeEvents.Client or not DynamicHordeEvents.Client.Target then return end

    local target = DynamicHordeEvents.Client.Target
    local now = getTimestampMs()
    local indicatorSeconds = DynamicHordeEvents.GetNumber("IndicatorSeconds")
    if target.eventType == "cataclysm" then indicatorSeconds = DynamicHordeEvents.GetNumber("CataclysmIndicatorSeconds") end
    local lifeMs = math.max(5000, indicatorSeconds * 1000)
    target.expiresAtMs = target.expiresAtMs or ((target.createdAtMs or now) + lifeMs)

    if now >= target.expiresAtMs then
        DynamicHordeEvents.Client.Target = nil
        DynamicHordeEvents.DebugPrint("DHE indicator expired")
        return
    end

    local player = getSpecificPlayer(0)
    if not player then return end

    local dx = target.x - player:getX()
    local dy = target.y - player:getY()
    local angleRad = math.atan2(dy, dx)
    local angleDeg = math.deg(angleRad)
    local distance = math.sqrt(dx * dx + dy * dy)
    local label = getCompassLabel(angleDeg)
    local secondsLeft = (target.expiresAtMs - now) / 1000.0

    local fade = 1.0
    if secondsLeft <= 5 then fade = math.max(0.25, secondsLeft / 5.0) end
    local pulse = 0.86 + 0.14 * math.abs(math.sin(now / 220.0))
    local alpha = fade * pulse

    renderCataclysmScreenEffect(target, now)

    local screenW = getCore():getScreenWidth()
    local centerX = screenW - 135
    local centerY = 120

    if now - DHE_UI.lastHeartbeatAt > 2500 then
        DHE_UI.lastHeartbeatAt = now
        DynamicHordeEvents.DebugPrint("DHE UI render target active: label=" .. tostring(label) .. ", dist=" .. tostring(math.floor(distance)))
    end

    local textured = drawTextureWidget(target, centerX, centerY, angleRad, label, distance, secondsLeft, alpha)
    if not textured then
        renderFallbackBox(target, centerX, centerY, label, distance, secondsLeft, alpha)
    else
        -- Keep text visible even while texture assets are warming up on the first event.
        local title = "HORDE INCOMING"
        local detail = string.format("%s | %.0f tiles | %d", label, distance, target.count or 0)
        if target.eventType == "cataclysm" then
            title = "CATACLYSM HORDE"
            detail = string.format("%s | %.0f tiles | ~%d", label, distance, target.count or 0)
        end
        drawShadowTextCentre(UIFont.Medium, centerX, centerY + 92, title, 1, 0.1, 0.1, alpha)
        drawShadowTextCentre(UIFont.Small, centerX, centerY + 112, detail, 1, 1, 1, alpha)
    end
end

local function renderIndicator()
    local ok, err = pcall(renderIndicatorRaw)
    if not ok then
        local now = getTimestampMs()
        if now - DHE_UI.lastRenderErrorAt > 3000 then
            DHE_UI.lastRenderErrorAt = now
            DynamicHordeEvents.Log("DHE UI render failed: " .. tostring(err))
        end
    end
end

-- Prefer the UI render pass. OnRenderTick/OnPostRender can be affected by indoor/roof
-- rendering states in B42. OnPostUIDraw fires after the UI frame and keeps the HUD visible
-- indoors without creating an ISPanel that could capture mouse input.
if Events.OnPostUIDraw then
    Events.OnPostUIDraw.Add(renderIndicator)
    DynamicHordeEvents.DebugPrint("DHE UI hooked to OnPostUIDraw")
elseif Events.OnRenderTick then
    Events.OnRenderTick.Add(renderIndicator)
    DynamicHordeEvents.DebugPrint("DHE UI hooked to OnRenderTick fallback")
elseif Events.OnPostRender then
    Events.OnPostRender.Add(renderIndicator)
    DynamicHordeEvents.DebugPrint("DHE UI hooked to OnPostRender fallback")
end
