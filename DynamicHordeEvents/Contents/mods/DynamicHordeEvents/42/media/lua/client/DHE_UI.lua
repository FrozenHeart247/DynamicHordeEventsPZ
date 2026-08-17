-- Dynamic Horde Events B42 indicator UI.

require "DHE_Config"
require "ISUI/ISPanel"

local WIDGET_WIDTH = 260
local WIDGET_HEIGHT = 145
local MARKER_CENTER_X = WIDGET_WIDTH / 2
local MARKER_CENTER_Y = 56
local MARKER_SIZE = 64
local EVENT_ICON_SIZE = 56
local ARROW_SIZE = 30
local ARROW_ORBIT = 40
local DRAG_RADIUS = 58
local DRAG_THRESHOLD = 5
local LAYOUT_KEY = "DynamicHordeEventsIndicatorLayout"

DynamicHordeEvents.IndicatorUI = DynamicHordeEvents.IndicatorUI or {}
local DHE_UI = DynamicHordeEvents.IndicatorUI
DHE_UI.textures = DHE_UI.textures or {}
DHE_UI.widget = DHE_UI.widget or nil
DHE_UI.textureStatusLogged = DHE_UI.textureStatusLogged or false
DHE_UI.lastHeartbeatAt = DHE_UI.lastHeartbeatAt or 0
DHE_UI.lastRenderErrorAt = DHE_UI.lastRenderErrorAt or 0

local EVENT_TEXTURES = {
    normal = "media/textures/DHE_NormalHorde.png",
    wandering = "media/textures/DHE_WanderingHorde.png",
    cataclysm = "media/textures/DHE_CataclysmHorde.png",
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

local function loadTexture(path)
    local texture = nil
    pcall(function() texture = getTexture(path) end)
    return texture
end

local function loadTextures()
    local textures = DHE_UI.textures
    textures.marker = textures.marker or loadTexture("media/textures/DHE_Marker.png")
    textures.arrow = textures.arrow or loadTexture("media/textures/DHE_Arrow.png")
    textures.normal = textures.normal or loadTexture(EVENT_TEXTURES.normal)
    textures.wandering = textures.wandering or loadTexture(EVENT_TEXTURES.wandering)
    textures.cataclysm = textures.cataclysm or loadTexture(EVENT_TEXTURES.cataclysm)
    textures.redOverlay = textures.redOverlay or loadTexture("media/ui/dhe_red_overlay.png")

    local ready = textures.marker ~= nil
        and textures.arrow ~= nil
        and textures.normal ~= nil
        and textures.wandering ~= nil
        and textures.cataclysm ~= nil

    if not DHE_UI.textureStatusLogged then
        DHE_UI.textureStatusLogged = true
        if ready then
            DynamicHordeEvents.DebugPrint("DHE indicator textures loaded")
        else
            DynamicHordeEvents.DebugPrint("DHE indicator textures not loaded, fallback rendering will be used")
        end
    end
    return ready
end

function DynamicHordeEvents.PreloadHordeUITextures()
    pcall(loadTextures)
end

local function playerScreenBounds(playerNum)
    if getPlayerScreenLeft and getPlayerScreenTop
        and getPlayerScreenWidth and getPlayerScreenHeight then
        return getPlayerScreenLeft(playerNum),
            getPlayerScreenTop(playerNum),
            getPlayerScreenWidth(playerNum),
            getPlayerScreenHeight(playerNum)
    end
    return 0, 0, getCore():getScreenWidth(), getCore():getScreenHeight()
end

local function getLayout(player)
    if not player or not player.getModData then return nil end
    local modData = player:getModData()
    if type(modData[LAYOUT_KEY]) ~= "table" then
        modData[LAYOUT_KEY] = { version = 1 }
    end
    local layout = modData[LAYOUT_KEY]
    layout.version = 1
    return layout
end

local function defaultPosition(playerNum)
    local left, top, width = playerScreenBounds(playerNum)
    return left + math.max(0, width - WIDGET_WIDTH - 10), top + 55
end

local function savedPosition(player, playerNum)
    local layout = getLayout(player)
    if not layout then return nil, nil end

    local nx = tonumber(layout.nx)
    local ny = tonumber(layout.ny)
    if nx == nil or ny == nil then return nil, nil end

    local left, top, width, height = playerScreenBounds(playerNum)
    local availableWidth = math.max(0, width - WIDGET_WIDTH)
    local availableHeight = math.max(0, height - WIDGET_HEIGHT)
    return left + math.max(0, math.min(1, nx)) * availableWidth,
        top + math.max(0, math.min(1, ny)) * availableHeight
end

local function saveWidgetPosition(widget)
    local player = getSpecificPlayer(widget.playerNum)
    local layout = getLayout(player)
    if not layout then return end

    local left, top, width, height = playerScreenBounds(widget.playerNum)
    local availableWidth = math.max(1, width - widget.width)
    local availableHeight = math.max(1, height - widget.height)
    layout.nx = math.max(0, math.min(1, (widget.x - left) / availableWidth))
    layout.ny = math.max(0, math.min(1, (widget.y - top) / availableHeight))
end

local function renderRotatedTexture(texture, centerX, centerY, width, height, angle, r, g, b, a)
    if not texture or not getRenderer then return false end
    local renderer = getRenderer()
    if not renderer then return false end

    local halfWidth = width / 2
    local halfHeight = height / 2
    local cosAngle = math.cos(angle)
    local sinAngle = math.sin(angle)
    local x1 = centerX - cosAngle * halfWidth + sinAngle * halfHeight
    local y1 = centerY - sinAngle * halfWidth - cosAngle * halfHeight
    local x2 = centerX + cosAngle * halfWidth + sinAngle * halfHeight
    local y2 = centerY + sinAngle * halfWidth - cosAngle * halfHeight
    local x3 = centerX + cosAngle * halfWidth - sinAngle * halfHeight
    local y3 = centerY + sinAngle * halfWidth + cosAngle * halfHeight
    local x4 = centerX - cosAngle * halfWidth - sinAngle * halfHeight
    local y4 = centerY - sinAngle * halfWidth + cosAngle * halfHeight
    renderer:render(texture, x1, y1, x2, y2, x3, y3, x4, y4, r, g, b, a, nil)
    return true
end

local function visualState(target, player, now)
    if not target or not player then return nil end

    local dx = (tonumber(target.x) or 0) - player:getX()
    local dy = (tonumber(target.y) or 0) - player:getY()
    local screenDX = (dx - dy) * 0.5
    local screenDY = (dx + dy) * 0.25
    local screenAngle = math.atan2(screenDY, screenDX)
    local worldAngle = math.atan2(dy, dx)
    local distance = math.sqrt(dx * dx + dy * dy)
    local secondsLeft = ((tonumber(target.expiresAtMs) or now) - now) / 1000.0

    local fade = 1.0
    if secondsLeft <= 5 then fade = math.max(0.25, secondsLeft / 5.0) end
    local pulse = 0.86 + 0.14 * math.abs(math.sin(now / 220.0))
    local alpha = fade * pulse
    local eventType = tostring(target.eventType or "normal")
    local label = getCompassLabel(math.deg(worldAngle))
    local count = tonumber(target.count) or 0

    local title = "HORDE INCOMING"
    local detail = string.format("%s | %.0f tiles | %d", label, distance, count)
    local color = { r = 1.0, g = 0.76, b = 0.05 }
    if eventType == "cataclysm" then
        title = "CATACLYSM HORDE"
        detail = string.format("%s | %.0f tiles | ~%d", label, distance, count)
        color = { r = 1.0, g = 0.08, b = 0.08 }
    elseif eventType == "wandering" then
        title = "WANDERING HORDE"
        detail = string.format("passing %s | %.0f tiles | ~%d", label, distance, count)
        color = { r = 0.78, g = 0.12, b = 0.96 }
    end

    return {
        alpha = alpha,
        angle = screenAngle,
        distance = distance,
        eventType = eventType,
        title = title,
        detail = detail,
        color = color,
    }
end

DHEIndicatorWidget = ISPanel:derive("DHEIndicatorWidget")

function DHEIndicatorWidget:initialise()
    ISPanel.initialise(self)
    loadTextures()
end

function DHEIndicatorWidget:clampToPlayerScreen()
    local left, top, width, height = playerScreenBounds(self.playerNum)
    self:setX(math.max(left, math.min(self.x, left + math.max(0, width - self.width))))
    self:setY(math.max(top, math.min(self.y, top + math.max(0, height - self.height))))
end

function DHEIndicatorWidget:isDragHandle(x, y)
    local dx = x - MARKER_CENTER_X
    local dy = y - MARKER_CENTER_Y
    return dx * dx + dy * dy <= DRAG_RADIUS * DRAG_RADIUS
end

function DHEIndicatorWidget:onMouseDown(x, y)
    if not self:isDragHandle(x, y) then return false end
    self.dragging = true
    self.dragMoved = false
    self.dragStartMouseX = getMouseX()
    self.dragStartMouseY = getMouseY()
    self.dragStartX = self.x
    self.dragStartY = self.y
    self:setCapture(true)
    self:bringToTop()
    return true
end

function DHEIndicatorWidget:updateDrag()
    if not self.dragging then return end
    local dx = getMouseX() - self.dragStartMouseX
    local dy = getMouseY() - self.dragStartMouseY
    if not self.dragMoved and (math.abs(dx) >= DRAG_THRESHOLD or math.abs(dy) >= DRAG_THRESHOLD) then
        self.dragMoved = true
    end
    if self.dragMoved then
        self:setX(self.dragStartX + dx)
        self:setY(self.dragStartY + dy)
        self:clampToPlayerScreen()
    end
end

function DHEIndicatorWidget:onMouseMove(dx, dy)
    self:updateDrag()
end

function DHEIndicatorWidget:onMouseMoveOutside(dx, dy)
    self:updateDrag()
end

function DHEIndicatorWidget:finishDrag()
    if not self.dragging then return end
    self:updateDrag()
    local moved = self.dragMoved
    self.dragging = false
    self.dragMoved = false
    self:setCapture(false)
    self:clampToPlayerScreen()
    if moved then saveWidgetPosition(self) end
end

function DHEIndicatorWidget:onMouseUp(x, y)
    self:finishDrag()
    return true
end

function DHEIndicatorWidget:onMouseUpOutside(x, y)
    self:finishDrag()
    return true
end

function DHEIndicatorWidget:prerender()
    local target = DynamicHordeEvents.Client and DynamicHordeEvents.Client.Target or nil
    local player = getSpecificPlayer(self.playerNum)
    local state = visualState(target, player, getTimestampMs())
    self.visualState = state
    if not state then return end

    loadTextures()
    local textures = DHE_UI.textures
    local hovered = self:isMouseOver() or self.dragging
    local markerSize = hovered and MARKER_SIZE + 4 or MARKER_SIZE
    local markerX = MARKER_CENTER_X - markerSize / 2
    local markerY = MARKER_CENTER_Y - markerSize / 2

    if textures.marker then
        self:drawTextureScaledAspect(textures.marker, markerX, markerY, markerSize, markerSize, state.alpha, 1, 1, 1)
    else
        self:drawRectBorder(markerX, markerY, markerSize, markerSize, state.alpha, 0.68, 0.58, 0.66)
    end

    local eventTexture = textures[state.eventType] or textures.normal
    if eventTexture then
        self:drawTextureScaledAspect(
            eventTexture,
            MARKER_CENTER_X - EVENT_ICON_SIZE / 2,
            MARKER_CENTER_Y - EVENT_ICON_SIZE / 2,
            EVENT_ICON_SIZE,
            EVENT_ICON_SIZE,
            state.alpha,
            1,
            1,
            1
        )
    else
        self:drawTextCentre("!", MARKER_CENTER_X, MARKER_CENTER_Y - 12, state.color.r, state.color.g, state.color.b, state.alpha, UIFont.Medium)
    end

    self:drawTextCentre(state.title, MARKER_CENTER_X, 99, state.color.r, state.color.g, state.color.b, state.alpha, UIFont.Medium)
    self:drawTextCentre(state.detail, MARKER_CENTER_X, 120, 1, 1, 1, state.alpha, UIFont.Small)
end

function DHEIndicatorWidget:render()
    ISPanel.render(self)
    local state = self.visualState
    if not state then return end

    local arrowCenterX = self.x + MARKER_CENTER_X + math.cos(state.angle) * ARROW_ORBIT
    local arrowCenterY = self.y + MARKER_CENTER_Y + math.sin(state.angle) * ARROW_ORBIT
    local rendered = renderRotatedTexture(
        DHE_UI.textures.arrow,
        arrowCenterX,
        arrowCenterY,
        ARROW_SIZE,
        ARROW_SIZE,
        state.angle,
        1,
        1,
        1,
        state.alpha
    )
    if not rendered and DHE_UI.textures.arrow then
        self:drawTextureScaledAspect(
            DHE_UI.textures.arrow,
            MARKER_CENTER_X + math.cos(state.angle) * ARROW_ORBIT - ARROW_SIZE / 2,
            MARKER_CENTER_Y + math.sin(state.angle) * ARROW_ORBIT - ARROW_SIZE / 2,
            ARROW_SIZE,
            ARROW_SIZE,
            state.alpha,
            1,
            1,
            1
        )
    end
end

function DHEIndicatorWidget:new(playerNum, x, y)
    local o = ISPanel.new(self, x, y, WIDGET_WIDTH, WIDGET_HEIGHT)
    o.playerNum = playerNum or 0
    o.background = false
    o.moveWithMouse = false
    o.dragging = false
    o.dragMoved = false
    o:setWantMouseEvents(true)
    return o
end

local function ensureWidget()
    if DHE_UI.widget then return DHE_UI.widget end
    local playerNum = 0
    local player = getSpecificPlayer(playerNum)
    if not player then return nil end

    local x, y = savedPosition(player, playerNum)
    if x == nil or y == nil then x, y = defaultPosition(playerNum) end

    local widget = DHEIndicatorWidget:new(playerNum, x, y)
    widget:initialise()
    widget:addToUIManager()
    widget:setAlwaysOnTop(true)
    widget:clampToPlayerScreen()
    widget:setVisible(false)
    DHE_UI.widget = widget
    return widget
end

local function hideWidget()
    if DHE_UI.widget then DHE_UI.widget:setVisible(false) end
end

local function removeWidget()
    if not DHE_UI.widget then return end
    DHE_UI.widget:setVisible(false)
    DHE_UI.widget:removeFromUIManager()
    DHE_UI.widget = nil
end

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
    if effectSeconds - elapsed < 3.0 then
        fade = math.min(fade, math.max(0, (effectSeconds - elapsed) / 3.0))
    end

    local pulse = 0.55 + 0.45 * math.abs(math.sin(now / 180.0))
    local alpha = 0.10 * fade * pulse
    loadTextures()
    local overlay = DHE_UI.textures.redOverlay
    if not overlay then return end

    local width = getCore():getScreenWidth()
    local height = getCore():getScreenHeight()
    pcall(function() UIManager.DrawTexture(overlay, 0, 0, width, height, alpha) end)
end

local function updateIndicatorRaw()
    renderLastMessage()

    if not DynamicHordeEvents.Client or not DynamicHordeEvents.Client.Target then
        hideWidget()
        return
    end

    local target = DynamicHordeEvents.Client.Target
    if target.debugOnly ~= true and not DynamicHordeEvents.GetBool("EnableEventNotifications") then
        DynamicHordeEvents.Client.Target = nil
        hideWidget()
        return
    end

    local now = getTimestampMs()
    local indicatorSeconds = DynamicHordeEvents.GetNumber("IndicatorSeconds")
    if target.eventType == "cataclysm" then
        indicatorSeconds = DynamicHordeEvents.GetNumber("CataclysmIndicatorSeconds")
    elseif target.eventType == "wandering" then
        indicatorSeconds = DynamicHordeEvents.GetNumber("WanderingIndicatorSeconds")
    end
    local lifeMs = math.max(5000, indicatorSeconds * 1000)
    target.expiresAtMs = target.expiresAtMs or ((target.createdAtMs or now) + lifeMs)

    renderCataclysmScreenEffect(target, now)

    if now >= target.expiresAtMs then
        DynamicHordeEvents.Client.Target = nil
        hideWidget()
        DynamicHordeEvents.DebugPrint("DHE indicator expired")
        return
    end

    if not DynamicHordeEvents.GetBool("EnableDirectionIndicator") then
        hideWidget()
        return
    end

    local widget = ensureWidget()
    if not widget then return end
    widget:setVisible(true)

    if now - DHE_UI.lastHeartbeatAt > 2500 then
        DHE_UI.lastHeartbeatAt = now
        local player = getSpecificPlayer(0)
        local state = visualState(target, player, now)
        DynamicHordeEvents.DebugPrint("DHE UI render target active: dist=" .. tostring(state and math.floor(state.distance) or "unknown"))
    end
end

local function updateIndicator()
    local ok, err = pcall(updateIndicatorRaw)
    if not ok then
        local now = getTimestampMs()
        if now - DHE_UI.lastRenderErrorAt > 3000 then
            DHE_UI.lastRenderErrorAt = now
            DynamicHordeEvents.Log("DHE UI render failed: " .. tostring(err))
        end
    end
end

local function onResolutionChange()
    local widget = DHE_UI.widget
    if not widget then return end
    local player = getSpecificPlayer(widget.playerNum)
    local x, y = savedPosition(player, widget.playerNum)
    if x ~= nil and y ~= nil then
        widget:setX(x)
        widget:setY(y)
    end
    widget:clampToPlayerScreen()
end

pcall(loadTextures)
if Events.OnGameBoot then Events.OnGameBoot.Add(DynamicHordeEvents.PreloadHordeUITextures) end
if Events.OnGameStart then Events.OnGameStart.Add(DynamicHordeEvents.PreloadHordeUITextures) end
if Events.OnCreatePlayer then
    Events.OnCreatePlayer.Add(function(playerNum)
        if playerNum == 0 then
            DynamicHordeEvents.PreloadHordeUITextures()
            ensureWidget()
        end
    end)
end
if Events.OnPlayerDeath then Events.OnPlayerDeath.Add(function() removeWidget() end) end
if Events.OnResolutionChange then Events.OnResolutionChange.Add(onResolutionChange) end

if Events.OnPostUIDraw then
    Events.OnPostUIDraw.Add(updateIndicator)
    DynamicHordeEvents.DebugPrint("DHE UI hooked to OnPostUIDraw")
elseif Events.OnRenderTick then
    Events.OnRenderTick.Add(updateIndicator)
    DynamicHordeEvents.DebugPrint("DHE UI hooked to OnRenderTick fallback")
elseif Events.OnPostRender then
    Events.OnPostRender.Add(updateIndicator)
    DynamicHordeEvents.DebugPrint("DHE UI hooked to OnPostRender fallback")
end
