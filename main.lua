local menu = require("imp.menu")
local Terrain = require("mgf.terrain")

local state = "menu"
local terrain
local playerImg
local camX, camY = 0, 0
local camOffX = -300
local camOffY = -200
local zoom = 2.5
local ZOOM_MIN = 0.3
local ZOOM_MAX = 3.0
local ZOOM_SPEED = 0.05

local player = {x = 0, y = 0, w = 12, h = 16, vx = 0, vy = 0, onGround = false, jumps = 0, facing = 1, stamina = 100, maxStamina = 100, flying = false}
local showDebug = false
local worldCache = {}

local GRAVITY = 600
local JUMP_VEL = -380
local MOVE_ACCEL = 1800
local MAX_SPEED = 220
local FRICTION = 1200
local AIR_FRICTION = 300
local FLY_ACCEL = -400
local STAMINA_DRAIN = 30
local STAMINA_REGEN = 15

local function getTilesInRect(px, py, pw, ph)
    local tiles = {}
    local left = math.floor(px / 16)
    local right = math.floor((px + pw - 1) / 16)
    local top = math.floor(py / 16)
    local bottom = math.floor((py + ph - 1) / 16)
    for tx = left, right do
        for ty = top, bottom do
            tiles[#tiles + 1] = {tx = tx, ty = ty}
        end
    end
    return tiles
end

local function isSolid(tx, ty)
    return terrain:getTile(tx, ty) ~= "air"
end

function love.load()
    menu:load()
    menu.onPlay = function()
        terrain = Terrain.new("assets/s.jpg")
        playerImg = love.graphics.newImage("assets/lol.png")
        playerImg:setFilter("nearest", "nearest")
        player.vx = 0
        player.vy = 0
        player.onGround = false
        player.jumps = 0
        player.facing = 1
        player.stamina = 100
        player.flying = false
        worldCache = {}
        for tx = 0, 100 do
            worldCache[tx] = {}
            for ty = 0, 25 do
                worldCache[tx][ty] = terrain:getTile(tx, ty)
            end
        end
        for ty = 0, 100 do
            local tile = terrain:getTile(25, ty)
            if tile ~= "air" then
                player.x = 25 * 16 + 8
                player.y = ty * 16
                break
            end
        end
        state = "game"
    end
end

function love.update(dt)
    if state == "menu" then
        menu:update(dt)
    elseif state == "game" then
        local dt = math.min(dt, 1/30)

        local moveDir = 0
        if love.keyboard.isDown("a") then moveDir = -1 end
        if love.keyboard.isDown("d") then moveDir = 1 end

        if moveDir ~= 0 then
            player.facing = moveDir
        end

        player.flying = false
        if love.keyboard.isDown("w") and player.stamina > 0 then
            player.vy = player.vy + FLY_ACCEL * dt
            player.stamina = math.max(0, player.stamina - STAMINA_DRAIN * dt)
            player.flying = true
            player.jumps = 2
        else
            player.vy = player.vy + GRAVITY * dt
            if player.stamina < player.maxStamina then
                player.stamina = math.min(player.maxStamina, player.stamina + STAMINA_REGEN * dt)
            end
        end

        if moveDir ~= 0 then
            player.vx = player.vx + moveDir * MOVE_ACCEL * dt
        end

        local friction = FRICTION
        if not player.onGround then friction = AIR_FRICTION end
        if moveDir == 0 or player.onGround then
            if player.vx > 0 then
                player.vx = math.max(0, player.vx - friction * dt)
            else
                player.vx = math.min(0, player.vx + friction * dt)
            end
        end

        player.vx = math.max(-MAX_SPEED, math.min(MAX_SPEED, player.vx))

        -- X movement
        local nx = player.x + player.vx * dt
        local px = nx - player.w / 2
        local py = player.y - player.h
        local tiles = getTilesInRect(px, py, player.w, player.h)
        local collides = false
        for _, t in ipairs(tiles) do
            if isSolid(t.tx, t.ty) then
                collides = true
                local tileCX = t.tx * 16 + 8
                if player.vx > 0 or (player.vx == 0 and nx >= tileCX) then
                    nx = t.tx * 16 - player.w / 2
                else
                    nx = (t.tx + 1) * 16 + player.w / 2
                end
                player.vx = 0
                break
            end
        end
        if not collides then
            player.x = nx
        end

        -- Y movement
        local ny = player.y + player.vy * dt
        px = player.x - player.w / 2
        py = ny - player.h
        tiles = getTilesInRect(px, py, player.w, player.h)
        player.onGround = false
        for _, t in ipairs(tiles) do
            if isSolid(t.tx, t.ty) then
                local tileCY = t.ty * 16 + 8
                if player.vy > 0 or (player.vy == 0 and ny >= tileCY) then
                    ny = t.ty * 16
                    player.onGround = true
                    player.jumps = 2
                else
                    ny = (t.ty + 1) * 16 + player.h
                end
                player.vy = 0
                break
            end
        end
        player.y = ny

        local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()

        local camSpeed = 300
        if love.keyboard.isDown("left")  then camOffX = camOffX - camSpeed * dt end
        if love.keyboard.isDown("right") then camOffX = camOffX + camSpeed * dt end
        if love.keyboard.isDown("up")    then camOffY = camOffY - camSpeed * dt end
        if love.keyboard.isDown("down")  then camOffY = camOffY + camSpeed * dt end

        camX = player.x - sw / 2 / zoom + camOffX
        camY = player.y - sh / 2 / zoom + camOffY
    end
end

function love.draw()
    if state == "menu" then
        menu:draw()
    elseif state == "game" then
        local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()
        love.graphics.setBackgroundColor(0.4, 0.6, 0.9)
        love.graphics.setColor(1, 1, 1)
        love.graphics.push()
        love.graphics.translate(sw / 2, sh / 2)
        love.graphics.scale(zoom)
        love.graphics.translate(-sw / 2, -sh / 2)
        terrain:draw(camX, camY, sw / zoom, sh / zoom)

        love.graphics.setColor(1, 1, 1)
        local drawX = player.x - player.w / 2 - camX
        local drawY = player.y - player.h - camY
        if player.facing == -1 then
            love.graphics.draw(playerImg, drawX + player.w, drawY, 0, -1, 1)
        else
            love.graphics.draw(playerImg, drawX, drawY)
        end

        local barW = 30
        local barH = 4
        local barX = drawX + player.w / 2 - barW / 2
        local barY = drawY - 8
        love.graphics.setColor(0.2, 0.2, 0.2, 0.8)
        love.graphics.rectangle("fill", barX, barY, barW, barH)
        local ratio = player.stamina / player.maxStamina
        love.graphics.setColor(1, 1 - ratio, 0.2)
        love.graphics.rectangle("fill", barX, barY, barW * ratio, barH)

        love.graphics.pop()

        love.graphics.setColor(1, 1, 1)
        love.graphics.print("WASD - move | Scroll - zoom (" .. math.floor(zoom * 100) .. "%)", 10, 10)
        love.graphics.print("ESC - menu | F5 - debug", 10, 30)

        -- minimap
        local mmX, mmY = sw - 130, 10
        local ts = 1
        local mmW, mmH = 100 * ts, 25 * ts
        love.graphics.setColor(0, 0, 0, 0.5)
        love.graphics.rectangle("fill", mmX - 5, mmY - 5, mmW + 10, mmH + 10, 4)
        for tx = 0, 99 do
            for ty = 0, 24 do
                local tile = worldCache[tx] and worldCache[tx][ty]
                if tile and tile ~= "air" then
                    if tile == "grass_top" then
                        love.graphics.setColor(0.3, 0.8, 0.2)
                    elseif tile == "dirt" then
                        love.graphics.setColor(0.55, 0.35, 0.15)
                    else
                        love.graphics.setColor(0.5, 0.5, 0.5)
                    end
                    love.graphics.rectangle("fill", mmX + tx * ts, mmY + ty * ts, ts, ts)
                end
            end
        end
        -- player dot
        local pt = math.floor(player.x / 16)
        local py_ = math.floor(player.y / 16)
        love.graphics.setColor(1, 1, 0)
        love.graphics.rectangle("fill", mmX + pt * ts - 1, mmY + py_ * ts - 1, 4, 4)
        -- view rect
        local vx = math.floor((camX - camOffX) / 16)
        local vy = math.floor((camY - camOffY) / 16)
        local vw = math.ceil(sw / zoom / 16)
        local vh = math.ceil(sh / zoom / 16)
        love.graphics.setColor(1, 0, 0, 0.7)
        love.graphics.rectangle("line", mmX + vx * ts, mmY + vy * ts, vw * ts, vh * ts)

        if showDebug then
            local mx, my = love.mouse.getPosition()
            local wmx = (mx - sw / 2) / zoom + sw / 2 + camX
            local wmy = (my - sh / 2) / zoom + sh / 2 + camY

            love.graphics.setColor(1, 1, 0)
            love.graphics.print("Player:  " .. math.floor(player.x) .. ", " .. math.floor(player.y), 10, 60)
            love.graphics.print("Camera:  " .. math.floor(camX) .. ", " .. math.floor(camY), 10, 80)
            love.graphics.print("Off:     " .. math.floor(camOffX) .. ", " .. math.floor(camOffY), 10, 100)
            love.graphics.print("Mouse:   " .. math.floor(wmx) .. ", " .. math.floor(wmy), 10, 120)
            love.graphics.print("Tile XY: " .. math.floor(wmx / 16) .. ", " .. math.floor(wmy / 16), 10, 140)
            love.graphics.print("Tile:    " .. (terrain:getTile(math.floor(wmx / 16), math.floor(wmy / 16)) or "none"), 10, 160)
        end
    end
end

function love.keypressed(key)
    if state == "game" then
        if key == "escape" then
            state = "menu"
        elseif key == "space" and player.jumps > 0 then
            player.vy = JUMP_VEL
            player.jumps = player.jumps - 1
            player.onGround = false
        end
    end
    if key == "f5" then
        showDebug = not showDebug
    end
end

function love.wheelmoved(x, y)
    if state == "game" then
        local old = zoom
        zoom = zoom + y * ZOOM_SPEED * zoom
        zoom = math.max(ZOOM_MIN, math.min(ZOOM_MAX, zoom))
    end
end

function love.mousepressed(x, y, button)
    if state == "menu" then
        menu:mousepressed(x, y, button)
    end
end

function love.mousereleased(x, y, button)
    if state == "menu" then
        menu:mousereleased(x, y, button)
    end
end
