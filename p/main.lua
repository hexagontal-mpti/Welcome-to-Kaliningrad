local menu = require("imp.menu")
local Terrain = require("mgf.terrain")

local state = "menu"
local terrain
local playerImg
local camX, camY = 0, 0
local camOffX = -300
local camOffY = -200
local zoom = 2.5

local paletteEnabled = false
local paletteShader
local paletteCanvas
local paletteImg

local player = {x = 0, y = 0, w = 12, h = 16, vx = 0, vy = 0, onGround = false, jumps = 0, facing = 1, flying = false}
local showDebug = false
local worldCache = {}
local items = {}
local goldImg
local goldTimer = 0
local goldCount = 0
local GOLD_SPAWN_INTERVAL = 5
local GOLD_SPAWN_ABOVE = 32
local ITEM_SIZE = 12
local ITEM_GRAVITY = 600
local PICKUP_DIST = 24
local shopOpen = false
local shopImg

local GRAVITY = 600
local JUMP_VEL = -380
local MOVE_ACCEL = 1800
local MAX_SPEED = 220
local FRICTION = 1200
local AIR_FRICTION = 300
local FLY_ACCEL = -400
local STAMINA_DRAIN = 30

local STAMINA_SECTIONS = 5
local STAMINA_SECTION_MAX = 20
local STAMINA_MAX = STAMINA_SECTIONS * STAMINA_SECTION_MAX
local STAMINA_REGEN_PER_SECTION = 2
local STAMINA_SECTION_DELAY = 1.0
local staminaSectionTimer = 0
local staminaRegenActive = false
local stamina = STAMINA_MAX

local bulletTypes = {
    {name = "Basic",  speed = 400, cost = 0,  damage = 1, color = {0.3, 0.6, 1.0, 1.0}, gravity = 120, bounces = 0},
    {name = "Fast",   speed = 700, cost = 5,  damage = 1, color = {0.3, 1.0, 0.4, 1.0}, gravity = 50,  bounces = 0},
    {name = "Heavy",  speed = 250, cost = 10, damage = 3, color = {1.0, 0.3, 0.2, 1.0}, gravity = 300, bounces = 2},
    {name = "Poison", speed = 350, cost = 15, damage = 2, color = {0.7, 0.2, 1.0, 1.0}, gravity = 80,  bounces = 1},
}
local selectedBullet = 1
local bullets = {}
local particles = {}
local bulletShader
local particleShader
local bulletImg
local particleImg
local shootCooldown = 0
local SHOOT_CD = 0.25
local TRAIL_INTERVAL = 0.03
local trailTimer = 0

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

local function getStaminaSection()
    for i = STAMINA_SECTIONS, 1, -1 do
        if stamina < i * STAMINA_SECTION_MAX then
            return i
        end
    end
    return 0
end

local function getStaminaInSection()
    local sec = getStaminaSection()
    if sec == 0 then return STAMINA_SECTION_MAX end
    return stamina - (sec - 1) * STAMINA_SECTION_MAX
end

local function drainStamina(amount)
    stamina = math.max(0, stamina - amount)
    staminaRegenActive = false
    staminaSectionTimer = STAMINA_SECTION_DELAY
end

local function regenStamina(dt)
    if not staminaRegenActive then
        staminaSectionTimer = staminaSectionTimer - dt
        if staminaSectionTimer <= 0 then
            staminaRegenActive = true
        end
        return
    end
    if stamina < STAMINA_MAX then
        stamina = math.min(STAMINA_MAX, stamina + STAMINA_REGEN_PER_SECTION * dt)
    end
end

local function spawnImpact(x, y, color, count)
    for i = 1, count do
        local angle = math.random() * math.pi * 2
        local speed = 60 + math.random() * 140
        particles[#particles + 1] = {
            x = x, y = y,
            vx = math.cos(angle) * speed,
            vy = math.sin(angle) * speed,
            life = 0.3 + math.random() * 0.4,
            maxLife = 0.3 + math.random() * 0.4,
            size = 3 + math.random() * 3,
            color = color,
            type = "impact",
        }
    end
end

local function spawnTrail(x, y, color)
    particles[#particles + 1] = {
        x = x + (math.random() - 0.5) * 4,
        y = y + (math.random() - 0.5) * 4,
        vx = (math.random() - 0.5) * 20,
        vy = (math.random() - 0.5) * 20,
        life = 0.2 + math.random() * 0.15,
        maxLife = 0.2 + math.random() * 0.15,
        size = 2 + math.random() * 2,
        color = {color[1], color[2], color[3], 1.0},
        type = "trail",
    }
end

local function spawnMuzzle(x, y, color, dx, dy)
    for i = 1, 4 do
        local spread = (math.random() - 0.5) * 0.8
        local a = math.atan2(dy, dx) + spread
        local speed = 80 + math.random() * 120
        particles[#particles + 1] = {
            x = x, y = y,
            vx = math.cos(a) * speed,
            vy = math.sin(a) * speed,
            life = 0.15 + math.random() * 0.1,
            maxLife = 0.15 + math.random() * 0.1,
            size = 2 + math.random() * 3,
            color = {color[1], color[2], color[3], 1.0},
            type = "muzzle",
        }
    end
end

function love.load()
    menu:load()
    menu.onPlay = function()
        terrain = Terrain.new("assets/s.jpg")
        playerImg = love.graphics.newImage("assets/lol.png")
        playerImg:setFilter("nearest", "nearest")
        goldImg = love.graphics.newImage("assets/g.png")
        goldImg:setFilter("nearest", "nearest")
        shopImg = love.graphics.newImage("assets/b.png")
        shopImg:setFilter("nearest", "nearest")

        bulletImg = love.graphics.newCanvas(16, 16)
        love.graphics.setCanvas(bulletImg)
        love.graphics.clear(0, 0, 0, 0)
        love.graphics.setColor(1, 1, 1)
        love.graphics.circle("fill", 8, 8, 6)
        love.graphics.setCanvas()

        particleImg = love.graphics.newCanvas(8, 8)
        love.graphics.setCanvas(particleImg)
        love.graphics.clear(0, 0, 0, 0)
        love.graphics.setColor(1, 1, 1)
        love.graphics.circle("fill", 4, 4, 4)
        love.graphics.setCanvas()

        local ok1, s1 = pcall(love.graphics.newShader, "mgf/bullet_shader.glsl")
        bulletShader = ok1 and s1 or nil
        local ok2, s2 = pcall(love.graphics.newShader, "mgf/particle_shader.glsl")
        particleShader = ok2 and s2 or nil

        local ok3, s3 = pcall(love.graphics.newShader, "mgf/palette_shader.glsl")
        paletteShader = ok3 and s3 or nil

        paletteImg = love.graphics.newImage("assets/gss/p.png")
        paletteImg:setFilter("nearest", "nearest")

        local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()
        paletteCanvas = love.graphics.newCanvas(sw, sh)

        player.vx = 0
        player.vy = 0
        player.onGround = false
        player.jumps = 0
        player.facing = 1
        player.flying = false
        stamina = STAMINA_MAX
        staminaRegenActive = true
        staminaSectionTimer = 0
        items = {}
        bullets = {}
        particles = {}
        goldTimer = GOLD_SPAWN_INTERVAL
        goldCount = 0
        selectedBullet = 1
        shootCooldown = 0
        trailTimer = 0
        shopOpen = false
        paletteEnabled = false
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
        shootCooldown = math.max(0, shootCooldown - dt)
        trailTimer = trailTimer - dt

        if not shopOpen then
            local moveDir = 0
            if love.keyboard.isDown("a") then moveDir = -1 end
            if love.keyboard.isDown("d") then moveDir = 1 end

            if moveDir ~= 0 then
                player.facing = moveDir
            end

            player.flying = false
            if love.keyboard.isDown("w") and stamina > 0 then
                player.vy = player.vy + FLY_ACCEL * dt
                drainStamina(STAMINA_DRAIN * dt)
                player.flying = true
                player.jumps = 2
            else
                player.vy = player.vy + GRAVITY * dt
                regenStamina(dt)
            end

            if moveDir ~= 0 then
                player.vx = player.vx + moveDir * MOVE_ACCEL * dt
            end

            if moveDir == 0 then
                local friction = player.onGround and FRICTION or AIR_FRICTION
                if player.vx > 0 then
                    player.vx = math.max(0, player.vx - friction * dt)
                elseif player.vx < 0 then
                    player.vx = math.min(0, player.vx + friction * dt)
                end
            end

            player.vx = math.max(-MAX_SPEED, math.min(MAX_SPEED, player.vx))

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
        end

        local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()

        local camSpeed = 300
        if showDebug then
            if love.keyboard.isDown("left")  then camOffX = camOffX - camSpeed * dt end
            if love.keyboard.isDown("right") then camOffX = camOffX + camSpeed * dt end
            if love.keyboard.isDown("up")    then camOffY = camOffY - camSpeed * dt end
            if love.keyboard.isDown("down")  then camOffY = camOffY + camSpeed * dt end
        end

        camX = player.x - sw / 2 / zoom + camOffX
        camY = player.y - sh / 2 / zoom + camOffY

        goldTimer = goldTimer - dt
        if goldTimer <= 0 then
            goldTimer = GOLD_SPAWN_INTERVAL
            local spawnX = player.x + (math.random() - 0.5) * 32
            local spawnY = player.y - GOLD_SPAWN_ABOVE * 16
            items[#items + 1] = {x = spawnX, y = spawnY, vx = (math.random() - 0.5) * 60, vy = 0}
        end

        for i = #items, 1, -1 do
            local item = items[i]
            item.vy = item.vy + ITEM_GRAVITY * dt
            item.x = item.x + item.vx * dt
            local ny = item.y + item.vy * dt
            local tx = math.floor(item.x / 16)
            local ty = math.floor((ny + ITEM_SIZE / 2) / 16)
            if isSolid(tx, ty) then
                ny = ty * 16 - ITEM_SIZE / 2
                item.vy = 0
                item.vx = 0
            end
            item.y = ny
            local dx = item.x - player.x
            local dy = item.y - player.y
            if dx * dx + dy * dy < PICKUP_DIST * PICKUP_DIST then
                goldCount = goldCount + 1
                table.remove(items, i)
            end
        end

        for i = #bullets, 1, -1 do
            local b = bullets[i]
            b.vy = b.vy + b.gravity * dt
            b.x = b.x + b.vx * dt
            b.y = b.y + b.vy * dt
            b.life = b.life - dt
            b.dist = b.dist + math.sqrt(b.vx * b.vx + b.vy * b.vy) * dt

            local hitX = false
            local hitY = false
            local tx = math.floor(b.x / 16)
            local ty = math.floor(b.y / 16)

            local txPrev = math.floor((b.x - b.vx * dt) / 16)
            local tyPrev = math.floor((b.y - b.vy * dt) / 16)

            if isSolid(tx, tyPrev) then
                hitX = true
            end
            if isSolid(txPrev, ty) then
                hitY = true
            end
            if isSolid(tx, ty) then
                hitX = true
                hitY = true
            end

            if hitX then
                if b.bouncesLeft > 0 then
                    b.vx = -b.vx * 0.7
                    b.bouncesLeft = b.bouncesLeft - 1
                    spawnImpact(b.x, b.y, b.color, 3)
                else
                    spawnImpact(b.x, b.y, b.color, 6)
                    table.remove(bullets, i)
                end
            elseif hitY then
                if b.bouncesLeft > 0 then
                    b.vy = -b.vy * 0.7
                    b.bouncesLeft = b.bouncesLeft - 1
                    spawnImpact(b.x, b.y, b.color, 3)
                else
                    spawnImpact(b.x, b.y, b.color, 6)
                    table.remove(bullets, i)
                end
            elseif b.life <= 0 or b.dist > 800 then
                table.remove(bullets, i)
            end
        end

        if trailTimer <= 0 then
            trailTimer = TRAIL_INTERVAL
            for _, b in ipairs(bullets) do
                spawnTrail(b.x, b.y, b.color)
            end
        end

        for i = #particles, 1, -1 do
            local p = particles[i]
            p.x = p.x + p.vx * dt
            p.y = p.y + p.vy * dt
            p.life = p.life - dt
            if p.type == "impact" then
                p.vx = p.vx * 0.92
                p.vy = p.vy * 0.92
            elseif p.type == "trail" then
                p.vy = p.vy + 30 * dt
            end
            if p.life <= 0 then
                table.remove(particles, i)
            end
        end
    end
end

function love.draw()
    if state == "menu" then
        menu:draw()
    elseif state == "game" then
        local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()

        love.graphics.setCanvas(paletteCanvas)
        love.graphics.clear(0.4, 0.6, 0.9, 1)
        love.graphics.setColor(1, 1, 1)
        love.graphics.push()
        love.graphics.translate(sw / 2, sh / 2)
        love.graphics.scale(zoom)
        love.graphics.translate(-sw / 2, -sh / 2)
        terrain:draw(camX, camY, sw / zoom, sh / zoom)

        for _, p in ipairs(particles) do
            local alpha = p.life / p.maxLife
            local s = p.size * (0.5 + alpha * 0.5)
            love.graphics.setColor(p.color[1], p.color[2], p.color[3], alpha * 0.8)
            love.graphics.rectangle("fill", p.x - s / 2 - camX, p.y - s / 2 - camY, s, s)
        end

        if bulletShader then
            love.graphics.setShader(bulletShader)
            for _, b in ipairs(bullets) do
                bulletShader:send("uColor", b.color)
                bulletShader:send("uTime", love.timer.getTime())
                love.graphics.setColor(1, 1, 1)
                love.graphics.draw(bulletImg, b.x - 8 - camX, b.y - 8 - camY)
            end
            love.graphics.setShader()
        else
            for _, b in ipairs(bullets) do
                love.graphics.setColor(b.color[1], b.color[2], b.color[3], b.color[4])
                love.graphics.rectangle("fill", b.x - 4 - camX, b.y - 4 - camY, 8, 8)
            end
        end

        love.graphics.setColor(1, 1, 1)
        local drawX = player.x - player.w / 2 - camX
        local drawY = player.y - player.h - 16 - camY
        if player.facing == -1 then
            love.graphics.draw(playerImg, drawX + player.w, drawY, 0, -1, 1)
        else
            love.graphics.draw(playerImg, drawX, drawY)
        end

        for _, item in ipairs(items) do
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(goldImg, item.x - ITEM_SIZE / 2 - camX, item.y - ITEM_SIZE / 2 - camY)
        end

        love.graphics.pop()

        love.graphics.setColor(1, 1, 1)
        love.graphics.print("WASD - move | I - shop | LMB - shoot | P - palette", 10, 10)
        love.graphics.print("ESC - menu | F5 - debug + camera", 10, 30)

        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.rectangle("fill", 10, 50, 120, 22, 4)
        love.graphics.setColor(1, 0.85, 0)
        love.graphics.print("Gold: " .. math.ceil(goldTimer) .. "s", 16, 54)
        local barGoldW = 108
        local barGoldH = 4
        local barGoldX = 16
        local barGoldY = 66
        love.graphics.setColor(0.3, 0.3, 0.3)
        love.graphics.rectangle("fill", barGoldX, barGoldY, barGoldW, barGoldH)
        local goldRatio = 1 - goldTimer / GOLD_SPAWN_INTERVAL
        love.graphics.setColor(1, 0.85, 0)
        love.graphics.rectangle("fill", barGoldX, barGoldY, barGoldW * goldRatio, barGoldH)

        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.rectangle("fill", 10, 80, 120, 22, 4)
        love.graphics.setColor(1, 0.85, 0)
        love.graphics.draw(goldImg, 16, 82, 0, 1.5, 1.5)
        love.graphics.print("x " .. goldCount, 38, 84)

        local secBarX = 10
        local secBarY = 110
        local secBarW = 100
        local secBarH = 14
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.rectangle("fill", secBarX - 2, secBarY - 2, secBarW + 4, secBarH + 4, 3)
        for i = 0, STAMINA_SECTIONS - 1 do
            local sx = secBarX + i * (secBarW / STAMINA_SECTIONS)
            local sw2 = secBarW / STAMINA_SECTIONS - 2
            love.graphics.setColor(0.15, 0.15, 0.2)
            love.graphics.rectangle("fill", sx + 1, secBarY + 1, sw2, secBarH - 2, 2)
            local sectionBottom = i * STAMINA_SECTION_MAX
            local sectionTop = (i + 1) * STAMINA_SECTION_MAX
            if stamina >= sectionTop then
                love.graphics.setColor(0.2, 0.8, 1.0)
                love.graphics.rectangle("fill", sx + 1, secBarY + 1, sw2, secBarH - 2, 2)
            elseif stamina > sectionBottom then
                local fill = (stamina - sectionBottom) / STAMINA_SECTION_MAX
                love.graphics.setColor(0.2, 0.8, 1.0)
                love.graphics.rectangle("fill", sx + 1, secBarY + 1 + (1 - fill) * (secBarH - 2), sw2, fill * (secBarH - 2), 2)
            end
        end
        love.graphics.setColor(1, 1, 1, 0.9)
        love.graphics.print("STAMINA", secBarX, secBarY - 12)

        local selType = bulletTypes[selectedBullet]
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.rectangle("fill", 10, 140, 160, 40, 4)
        love.graphics.setColor(selType.color[1], selType.color[2], selType.color[3])
        love.graphics.rectangle("fill", 16, 146, 12, 12)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(selType.name, 34, 144)
        love.graphics.setColor(0.7, 0.7, 0.7)
        love.graphics.print("DMG:" .. selType.damage .. " SPD:" .. selType.speed .. " $" .. selType.cost, 34, 158)
        love.graphics.setColor(0.5, 0.5, 0.5)
        love.graphics.print("[Q/E] switch", 10, 184)

        if paletteEnabled then
            love.graphics.setColor(0.2, 0.8, 0.2, 0.7)
            love.graphics.rectangle("fill", 10, 196, 80, 16, 3)
            love.graphics.setColor(1, 1, 1)
            love.graphics.print("PALETTE", 16, 198)
        end

        if shopOpen then
            love.graphics.setColor(0, 0, 0, 0.7)
            love.graphics.rectangle("fill", 0, 0, sw, sh)

            local shopW = 360
            local shopH = 300
            local shopX = sw / 2 - shopW / 2
            local shopY = sh / 2 - shopH / 2

            love.graphics.setColor(0.15, 0.15, 0.2, 0.95)
            love.graphics.rectangle("fill", shopX, shopY, shopW, shopH, 8)
            love.graphics.setColor(1, 0.85, 0)
            love.graphics.rectangle("line", shopX, shopY, shopW, shopH, 8)

            love.graphics.setColor(1, 0.85, 0)
            love.graphics.print("SHOP", shopX + shopW / 2 - 20, shopY + 10)
            love.graphics.setColor(0.6, 0.6, 0.6)
            love.graphics.print("Gold: " .. goldCount, shopX + shopW - 80, shopY + 10)

            local slotSize = 64
            local slotGap = 16
            local totalSlotsW = #bulletTypes * slotSize + (#bulletTypes - 1) * slotGap
            local slotsStartX = shopX + (shopW - totalSlotsW) / 2
            local slotsY = shopY + 45

            for i, bt in ipairs(bulletTypes) do
                local sx = slotsStartX + (i - 1) * (slotSize + slotGap)
                love.graphics.setColor(0.25, 0.25, 0.3, 0.9)
                love.graphics.rectangle("fill", sx, slotsY, slotSize, slotSize, 4)
                if selectedBullet == i then
                    love.graphics.setColor(bt.color[1], bt.color[2], bt.color[3])
                else
                    love.graphics.setColor(0.5, 0.5, 0.5)
                end
                love.graphics.rectangle("line", sx, slotsY, slotSize, slotSize, 4)

                love.graphics.setColor(bt.color[1], bt.color[2], bt.color[3])
                love.graphics.rectangle("fill", sx + slotSize / 2 - 10, slotsY + 10, 20, 20, 3)

                love.graphics.setColor(1, 1, 1)
                love.graphics.print(bt.name, sx + 4, slotsY + 36)
                love.graphics.setColor(0.7, 0.7, 0.7)
                love.graphics.print("$" .. bt.cost, sx + 4, slotsY + 50)

                love.graphics.setColor(0.5, 0.5, 0.5)
                love.graphics.print("[" .. i .. "]", sx + slotSize - 20, slotsY + slotSize - 14)
            end

            love.graphics.setColor(0.5, 0.5, 0.5)
            love.graphics.print("Press I to close | 1-4 select", shopX + shopW / 2 - 75, shopY + shopH - 24)
        end

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
        local pt = math.floor(player.x / 16)
        local py_ = math.floor(player.y / 16)
        love.graphics.setColor(1, 1, 0)
        love.graphics.rectangle("fill", mmX + pt * ts - 1, mmY + py_ * ts - 1, 4, 4)
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
            love.graphics.print("Player:  " .. math.floor(player.x) .. ", " .. math.floor(player.y), 10, 220)
            love.graphics.print("Camera:  " .. math.floor(camX) .. ", " .. math.floor(camY), 10, 240)
            love.graphics.print("Off:     " .. math.floor(camOffX) .. ", " .. math.floor(camOffY), 10, 260)
            love.graphics.print("Mouse:   " .. math.floor(wmx) .. ", " .. math.floor(wmy), 10, 280)
            love.graphics.print("Tile XY: " .. math.floor(wmx / 16) .. ", " .. math.floor(wmy / 16), 10, 300)
            love.graphics.print("Tile:    " .. (terrain:getTile(math.floor(wmx / 16), math.floor(wmy / 16)) or "none"), 10, 320)
            love.graphics.print("Bullets: " .. #bullets, 10, 340)
            love.graphics.print("Parts:   " .. #particles, 10, 360)
            love.graphics.print("Stamina: " .. math.floor(stamina) .. "/" .. STAMINA_MAX, 10, 380)
        end

        love.graphics.setCanvas()

        if paletteEnabled and paletteShader and paletteImg then
            love.graphics.setShader(paletteShader)
            paletteShader:send("uPalette", paletteImg)
            paletteShader:send("uEnabled", true)
        end
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(paletteCanvas, 0, 0)
        if paletteEnabled then
            love.graphics.setShader()
        end
    end
end

function love.keypressed(key)
    if state == "game" then
        if key == "escape" then
            state = "menu"
            menu:pickRandom()
        elseif key == "space" and player.jumps > 0 then
            player.vy = JUMP_VEL
            player.jumps = player.jumps - 1
            player.onGround = false
        elseif key == "i" then
            shopOpen = not shopOpen
        elseif key == "q" then
            selectedBullet = selectedBullet - 1
            if selectedBullet < 1 then selectedBullet = #bulletTypes end
        elseif key == "e" then
            selectedBullet = selectedBullet + 1
            if selectedBullet > #bulletTypes then selectedBullet = 1 end
        elseif key == "1" and shopOpen then
            selectedBullet = 1
        elseif key == "2" and shopOpen and #bulletTypes >= 2 then
            selectedBullet = 2
        elseif key == "3" and shopOpen and #bulletTypes >= 3 then
            selectedBullet = 3
        elseif key == "4" and shopOpen and #bulletTypes >= 4 then
            selectedBullet = 4
        elseif key == "p" then
            paletteEnabled = not paletteEnabled
        end
    end
    if key == "f5" then
        showDebug = not showDebug
    end
end

function love.mousepressed(x, y, button)
    if state == "menu" then
        menu:mousepressed(x, y, button)
    elseif state == "game" and button == 1 and not shopOpen then
        if shootCooldown <= 0 then
            local selType = bulletTypes[selectedBullet]
            if goldCount >= selType.cost then
                goldCount = goldCount - selType.cost
                local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()
                local wmx = (x - sw / 2) / zoom + sw / 2 + camX
                local wmy = (y - sh / 2) / zoom + sh / 2 + camY
                local dx = wmx - player.x
                local dy = wmy - (player.y - player.h / 2)
                local len = math.sqrt(dx * dx + dy * dy)
                if len > 0 then
                    dx = dx / len
                    dy = dy / len
                end
                local bColor = selType.color
                bullets[#bullets + 1] = {
                    x = player.x,
                    y = player.y - player.h / 2,
                    vx = dx * selType.speed,
                    vy = dy * selType.speed,
                    gravity = selType.gravity,
                    color = {bColor[1], bColor[2], bColor[3], bColor[4]},
                    damage = selType.damage,
                    bouncesLeft = selType.bounces,
                    life = 3.0,
                    dist = 0,
                }
                spawnMuzzle(player.x, player.y - player.h / 2, selType.color, dx, dy)
                shootCooldown = SHOOT_CD
            end
        end
    end
end

function love.mousereleased(x, y, button)
    if state == "menu" then
        menu:mousereleased(x, y, button)
    end
end
