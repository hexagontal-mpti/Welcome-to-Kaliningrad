local menu = require("imp.menu")
local Terrain = require("mgf.terrain")

local state = "menu"
local terrain
local playerImg
local camX, camY = 0, 0
local camOffX = -300
local camOffY = -200
local zoom = 3.125

local paletteEnabled = false
local paletteShader
local paletteCanvas
local rgbCanvas
local paletteImg
local rgbEnabled = true
local rgbShader = nil

local player = {x = 0, y = 0, w = 12, h = 16, vx = 0, vy = 0, onGround = false, jumps = 0, facing = 1, flying = false, jumping = false, jumpCharge = 0, wallSlide = false, wallDir = 0, invulnTimer = 0}
local showDebug = false
local showMap = false
local mapQuadrant = 1
local worldCache = {}
local items = {}
local goldImg
local goldTimer = 0
local goldCount = 0
local exp = 0
local GOLD_SPAWN_INTERVAL = 5
local GOLD_SPAWN_ABOVE = 32
local ITEM_SIZE = 12
local ITEM_GRAVITY = 600
local PICKUP_DIST = 24
local shopOpen = false
local shopImg
local diffMultiplier = 1

local clouds = {}
local CLOUD_COUNT = 12

local plantImg
local plantQuads = {}
local plants = {}
local levitateTimer = 0

local bgm
local mouseImg
local mouseQuads = {}
local mice = {}

local slimeImg
local slimeQuads = {}
local slimes = {}

local q4EnemyImg
local q4EnemyQuads = {}
local q4Enemies = {}

local stoneImg
local stoneX = -100
local stoneY = -100
local stone1X = -100
local stone1Y = -100
local stoneHitCount = 0
local tipText = ""
local tipTimer = 0
local goldenRainTimer = 0
local zoneEntered = false
local goldRainSpawnTimer = 0
local gameStartTime = 0
local chamberUnlocked = false
local chapter = 1
local showEndScreen = false
local endScreenTimer = 0
local ch2Complete = false
local showCh2End = false
local ch2EndTimer = 0
local gamePaused = false
local pauseButtons = {}
local pauseHovered = nil
local hellImg
local hellQuads = {}
local hellTileIdx = 1

local GRAVITY = 600
local JUMP_VEL = -300
local MOVE_ACCEL = 1800
local MAX_SPEED = 220
local FRICTION = 1200
local AIR_FRICTION = 300
local FLY_ACCEL = -400
local STAMINA_DRAIN = 30
local STAMINA_SECTIONS = 3
local STAMINA_SECTION_MAX = 15
local STAMINA_MAX = STAMINA_SECTIONS * STAMINA_SECTION_MAX
local STAMINA_REGEN_PER_SECTION = 2
local STAMINA_SECTION_DELAY = 1.0
local staminaSectionTimer = 0
local staminaRegenActive = false
local stamina = STAMINA_MAX

local bulletTypes = {
    {name = "Basic",  speed = 400, cost = 0,  damage = 1, color = {0.3, 0.6, 1.0, 1.0}, gravity = 120, bounces = 0},
    {name = "Fast",   speed = 700, cost = 2,  damage = 1, color = {0.3, 1.0, 0.4, 1.0}, gravity = 50,  bounces = 0},
    {name = "Heavy",  speed = 250, cost = 4,  damage = 2, color = {1.0, 0.3, 0.2, 1.0}, gravity = 300, bounces = 2},
    {name = "Poison", speed = 350, cost = 7,  damage = 3, color = {0.7, 0.2, 1.0, 1.0}, gravity = 80,  bounces = 1},
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

local function initResources()
    playerImg = love.graphics.newImage("assets/lol.png")
    playerImg:setFilter("nearest", "nearest")
    goldImg = love.graphics.newImage("assets/g.png")
    goldImg:setFilter("nearest", "nearest")
    shopImg = love.graphics.newImage("assets/b.png")
    shopImg:setFilter("nearest", "nearest")

    local ok, s = pcall(love.audio.newSource, "assets/ntr/f.mp3", "stream")
    bgm = ok and s or nil
    if bgm then bgm:setLooping(true); bgm:play() end

    mouseImg = love.graphics.newImage("assets/gss/b.png")
    mouseImg:setFilter("nearest", "nearest")
    mouseQuads = {}
    for i = 0, 3 do
        mouseQuads[i + 1] = love.graphics.newQuad(i * 64, 0, 64, 64, mouseImg:getDimensions())
    end

    slimeImg = love.graphics.newImage("assets/ntr/s.png")
    slimeImg:setFilter("nearest", "nearest")
    slimeQuads = {}
    for i = 0, 5 do
        slimeQuads[i + 1] = love.graphics.newQuad(i * 64, 128, 64, 64, slimeImg:getDimensions())
    end

    q4EnemyImg = love.graphics.newImage("assets/ntr/v.png")
    q4EnemyImg:setFilter("nearest", "nearest")
    q4EnemyQuads = {}
    for i = 0, 3 do
        q4EnemyQuads[i + 1] = love.graphics.newQuad(i * 64, 128, 64, 64, q4EnemyImg:getDimensions())
    end

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

    local ok4, s4 = pcall(love.graphics.newShader, "mgf/game_rgb.glsl")
    rgbShader = ok4 and s4 or nil

    paletteImg = love.graphics.newImage("assets/gss/p.png")
    paletteImg:setFilter("nearest", "nearest")

    local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()
    paletteCanvas = love.graphics.newCanvas(sw, sh)
    rgbCanvas = love.graphics.newCanvas(sw, sh)

    stoneImg = love.graphics.newImage("assets/gss/c.png")
    stoneImg:setFilter("nearest", "nearest")

    plantImg = love.graphics.newImage("assets/gss/plnts.png")
    plantImg:setFilter("nearest", "nearest")
    plantQuads = {}
    for i = 0, 4 do
        plantQuads[i + 1] = love.graphics.newQuad(i * 8, 0, 8, 8, plantImg:getDimensions())
    end

    hellImg = love.graphics.newImage("assets/svn/hll.png")
    hellImg:setFilter("nearest", "nearest")
    hellQuads = {}
    for i = 0, 1 do
        for j = 0, 1 do
            hellQuads[#hellQuads + 1] = love.graphics.newQuad(i * 128, j * 128, 128, 128, 256, 256)
        end
    end

    terrain = Terrain.new("assets/s.jpg", hellImg)
end

local function initState()
    player.vx = 0
    player.vy = 0
    player.onGround = false
    player.jumps = 0
    player.facing = 1
    player.flying = false
    player.invulnTimer = 0
    stamina = STAMINA_MAX
    staminaRegenActive = true
    staminaSectionTimer = 0
    hellTileIdx = math.random(1, 4)
    items = {}
    bullets = {}
    particles = {}
    goldCount = 0
    exp = 0
    stoneHitCount = 0
    tipText = ""
    tipTimer = 0
    goldenRainTimer = 0
    zoneEntered = false
    goldRainSpawnTimer = 0
    chapter = 1
    mapQuadrant = 1
    chamberUnlocked = false
    showEndScreen = false
    endScreenTimer = 0
    ch2Complete = false
    showCh2End = false
    ch2EndTimer = 0
    gameStartTime = love.timer.getTime()
    selectedBullet = 1
    shootCooldown = 0
    trailTimer = 0
    shopOpen = false
    paletteEnabled = menu.paletteEnabled or false
    q4Enemies = {}

    local diff = menu.difficulty or "Normal"
    if diff == "Easy" then
        diffMultiplier = 1.5
    elseif diff == "Hard" then
        diffMultiplier = 0.6
    else
        diffMultiplier = 1.0
    end
    goldTimer = GOLD_SPAWN_INTERVAL * diffMultiplier
end

local function initWorld()
    worldCache = {}
    for tx = 0, 100 do
        worldCache[tx] = {}
        for ty = 0, 49 do
            worldCache[tx][ty] = terrain:getTile(tx, ty)
        end
    end

    stoneX = -100
    stoneY = -100
    local spots = {}
    for tx = 0, 45 do
        local ty
        for ty2 = 0, 24 do
            if worldCache[tx] and worldCache[tx][ty2] == "grass_top" then
                ty = ty2
                break
            end
        end
        if ty then
            local flat = true
            for i = 0, 4 do
                if not (worldCache[tx + i] and worldCache[tx + i][ty] == "grass_top") then
                    flat = false
                    break
                end
            end
            if flat then
                spots[#spots + 1] = {tx = tx + 2, ty = ty}
            end
        end
    end
    if #spots > 0 then
        local pick = spots[math.random(1, #spots)]
        stoneX = pick.tx * 16 + 8 - 24
        stoneY = pick.ty * 16 - 24
        stone1X = stoneX
        stone1Y = stoneY
        player.x = stoneX + 24
        player.y = stoneY + 24
    end

    clouds = {}
    for i = 1, CLOUD_COUNT do
        clouds[i] = {
            x = math.random(-200, 1200),
            y = math.random(-100, 20),
            w = 80 + math.random() * 120,
            h = 16 + math.random() * 20,
            speed = 8 + math.random() * 15,
            puffs = {},
        }
        local n = 3 + math.random(4)
        for p = 1, n do
            clouds[i].puffs[p] = {
                ox = (math.random() - 0.5) * clouds[i].w * 0.6,
                oy = (math.random() - 0.5) * clouds[i].h * 0.4,
                r = 12 + math.random() * 18,
            }
        end
    end

    plants = {}
    for tx = 0, 99 do
        for ty = 0, 24 do
            if worldCache[tx] and worldCache[tx][ty] == "grass_top" then
                if math.random() < 0.4 then
                    local py = ty * 16 - 8
                    local px = tx * 16 + math.random(2, 6)
                    plants[#plants + 1] = {
                        x = px,
                        y = py,
                        quadIdx = math.random(1, 5),
                    }
                end
            end
        end
    end

    mice = {}
    for i = 1, 3 do
        local mx = math.random(50, 94)
        local my = 0
        for ty = 0, 24 do
            if worldCache[mx] and worldCache[mx][ty] == "grass_top" then
                my = ty * 16 - math.random(80, 160)
                break
            end
        end
        mice[#mice + 1] = {
            x = mx * 16 + 24,
            y = my,
            dir = math.random() < 0.5 and -1 or 1,
            animTimer = math.random() * 2,
            frame = 1,
            alive = true,
            hp = 3,
            maxHp = 3,
            hitTimer = 0,
            targetY = my,
            vy = 0,
            changeTimer = math.random() * 3,
            attackTimer = math.random() * 5,
            diving = false,
            diveTargetX = 0,
            diveTargetY = 0,
            returnY = my,
        }
    end

    slimes = {}
    for i = 1, 3 do
        local sx = math.random(50, 94)
        for ty = 0, 24 do
            if worldCache[sx] and worldCache[sx][ty] == "grass_top" then
                slimes[#slimes + 1] = {
                    x = sx * 16 + 24,
                    y = ty * 16 - 20,
                    dir = math.random() < 0.5 and -1 or 1,
                    animTimer = math.random() * 2,
                    frame = 1,
                    alive = true,
                    hp = 3,
                    maxHp = 3,
                    hitTimer = 0,
                    hopTimer = math.random() * 2,
                    vy = 0,
                    onGround = false,
                    hopCount = 0,
                }
                break
            end
        end
    end

    q4Enemies = {}
    for i = 1, 2 do
        local ex = math.random(78, 94)
        for ty = 35, 44 do
            if terrain:getTile(ex, ty) == "hell" then
                q4Enemies[#q4Enemies + 1] = {
                    x = ex * 16 + 24,
                    y = ty * 16 - 32,
                    dir = -1,
                    animTimer = math.random() * 2,
                    frame = 1,
                    alive = true,
                    hp = 5,
                    maxHp = 5,
                    hitTimer = 0,
                    shootTimer = 2 + math.random() * 2,
                }
                break
            end
        end
    end

    gamePaused = false
    pauseButtons = {}
    local pw, ph = 220, 44
    local pGap = 12
    local pLabels = {"Resume", "Save Progress", "New Game", "Main Menu"}
    local pActions = {"resume", "save", "newgame", "exit"}
    local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()
    local totalH = #pLabels * ph + (#pLabels - 1) * pGap
    local startY = sh / 2 - totalH / 2
    for i, lbl in ipairs(pLabels) do
        pauseButtons[i] = {
            text = lbl,
            action = pActions[i],
            x = sw / 2 - pw / 2,
            y = startY + (i - 1) * (ph + pGap),
            w = pw,
            h = ph,
        }
    end
end

function initGame()
    math.randomseed(os.time())
    initResources()
    initState()
    initWorld()
    state = "game"
end

function love.load()
    menu:load()
    menu.onPlay = initGame
end

function love.update(dt)
    if state == "menu" then
        menu:update(dt)
    elseif state == "game" then
        if gamePaused then return end
        local dt = math.min(dt, 1/30)
        shootCooldown = math.max(0, shootCooldown - dt)
        trailTimer = trailTimer - dt
        levitateTimer = levitateTimer + dt
        player.invulnTimer = math.max(0, player.invulnTimer - dt)
        tipTimer = math.max(0, tipTimer - dt)
        if showEndScreen then
            endScreenTimer = endScreenTimer + dt
        end
        if showCh2End then
            ch2EndTimer = ch2EndTimer + dt
        end

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

            if player.jumping then
                player.jumpCharge = math.min(1.0, player.jumpCharge + dt)
            end

            if player.wallSlide and not love.keyboard.isDown("w") then
                player.vy = player.vy + GRAVITY * 0.3 * dt
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
            local wallHit = 0
            for _, t in ipairs(tiles) do
                if isSolid(t.tx, t.ty) then
                    collides = true
                    local tileCX = t.tx * 16 + 8
                    if player.vx > 0 or (player.vx == 0 and nx >= tileCX) then
                        nx = t.tx * 16 - player.w / 2
                        wallHit = 1
                    else
                        nx = (t.tx + 1) * 16 + player.w / 2
                        wallHit = -1
                    end
                    player.vx = 0
                    break
                end
            end
            if not collides then
                player.x = nx
                player.wallSlide = false
                player.wallDir = 0
            else
                player.wallSlide = not player.onGround and player.vy > 0
                player.wallDir = player.wallSlide and wallHit or 0
            end

            if collides and player.onGround and moveDir ~= 0 then
                local checkTx = math.floor((player.x + moveDir * 9) / 16)
                local checkTy = math.floor((player.y - 8) / 16)
                if isSolid(checkTx, checkTy) and not isSolid(checkTx, checkTy - 1) then
                    player.vy = JUMP_VEL
                    player.jumps = player.jumps - 1
                    player.onGround = false
                end
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
                        player.jumping = false
                        player.jumpCharge = 0
                        player.wallSlide = false
                        player.wallDir = 0
                    else
                        ny = (t.ty + 1) * 16 + player.h
                    end
                    player.vy = 0
                    break
                end
            end
            player.y = ny

            local WORLD_W = 100 * 16
            if player.x < -8 then
                player.x = WORLD_W - 16
                for ty = 0, 24 do
                    local tile = terrain:getTile(math.floor((player.x + 8) / 16), ty)
                    if tile ~= "air" then
                        player.y = ty * 16
                        player.vy = 0
                        break
                    end
                end
            elseif player.x > WORLD_W + 8 then
                player.x = 16
                for ty = 0, 24 do
                    local tile = terrain:getTile(math.floor(player.x / 16), ty)
                    if tile ~= "air" then
                        player.y = ty * 16
                        player.vy = 0
                        break
                    end
                end
            end
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

        for _, c in ipairs(clouds) do
            c.x = c.x + c.speed * dt
            if c.x - c.w / 2 > camX + sw / zoom + 200 then
                c.x = camX - 200
                c.y = math.random(-100, 20)
            end
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
                goldCount = goldCount + 5
                table.remove(items, i)
            end
        end

        if not zoneEntered and player.x > 75 * 16 then
            zoneEntered = true
            goldenRainTimer = 15
            goldRainSpawnTimer = 0
            tipText = "GOLDEN RAIN! 15s"
            tipTimer = 15
        end

        if goldenRainTimer > 0 then
            goldenRainTimer = math.max(0, goldenRainTimer - dt)
            goldRainSpawnTimer = goldRainSpawnTimer - dt
            if goldRainSpawnTimer <= 0 then
                goldRainSpawnTimer = 0.3
                local spawnX = player.x + (math.random() - 0.5) * 48
                local spawnY = player.y - math.random(8, 20) * 16
                items[#items + 1] = {x = spawnX, y = spawnY, vx = (math.random() - 0.5) * 80, vy = 0}
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

            local removed = false

            if hitX then
                if b.bouncesLeft > 0 then
                    b.vx = -b.vx * 0.7
                    b.bouncesLeft = b.bouncesLeft - 1
                    spawnImpact(b.x, b.y, b.color, 3)
                else
                    spawnImpact(b.x, b.y, b.color, 6)
                    table.remove(bullets, i)
                    removed = true
                end
            elseif hitY then
                if b.bouncesLeft > 0 then
                    b.vy = -b.vy * 0.7
                    b.bouncesLeft = b.bouncesLeft - 1
                    spawnImpact(b.x, b.y, b.color, 3)
                else
                    spawnImpact(b.x, b.y, b.color, 6)
                    table.remove(bullets, i)
                    removed = true
                end
            elseif b.life <= 0 or b.dist > 800 then
                table.remove(bullets, i)
                removed = true
            end

            if not removed then
                local hit = false
                for _, m in ipairs(mice) do
                    if m.alive and math.abs(b.x - m.x) < 32 and math.abs(b.y - m.y) < 32 then
                        m.hp = m.hp - b.damage
                        m.hitTimer = 0.15
                        spawnImpact(b.x, b.y, b.color, 6)
                        if m.hp <= 0 then
                            m.alive = false
                            spawnImpact(m.x, m.y, {0.5, 0.3, 0.1}, 8)
                            goldCount = goldCount + 1
                            exp = exp + 1
                        end
                        hit = true
                        break
                    end
                end
                if not hit then
                    for _, s in ipairs(slimes) do
                        if s.alive and math.abs(b.x - s.x) < 32 and math.abs(b.y - s.y) < 32 then
                            s.hp = s.hp - b.damage
                            s.hitTimer = 0.15
                            spawnImpact(b.x, b.y, b.color, 6)
                            if s.hp <= 0 then
                                s.alive = false
                                spawnImpact(s.x, s.y, {0.2, 0.8, 0.2}, 8)
                                goldCount = goldCount + 1
                                exp = exp + 1
                            end
                            hit = true
                            break
                        end
                    end
                end
                if not hit then
                    for _, e in ipairs(q4Enemies) do
                        if e.alive and math.abs(b.x - e.x) < 32 and math.abs(b.y - e.y) < 32 then
                            e.hp = e.hp - b.damage
                            e.hitTimer = 0.15
                            spawnImpact(b.x, b.y, b.color, 6)
                            if e.hp <= 0 then
                                e.alive = false
                                spawnImpact(e.x, e.y, {0.8, 0.2, 0.1}, 10)
                                goldCount = goldCount + 2
                                exp = exp + 2
                            end
                            hit = true
                            break
                        end
                    end
                end
                if not hit and not b.fromPlayer then
                    if player.invulnTimer <= 0 and math.abs(b.x - player.x) < 24 and math.abs(b.y - (player.y - 8)) < 24 then
                        player.vy = -180
                        player.vx = (b.x > player.x and 1 or -1) * 180
                        player.invulnTimer = 0.5
                        hit = true
                    end
                end
                if hit then
                    table.remove(bullets, i)
                end
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

        for _, m in ipairs(mice) do
            if m.alive then
                m.animTimer = m.animTimer + dt
                if m.animTimer > 0.15 then
                    m.animTimer = 0
                    m.frame = m.frame % 4 + 1
                end
                m.hitTimer = math.max(0, m.hitTimer - dt)

                if m.diving then
                    local ddx = m.diveTargetX - m.x
                    local ddy = m.diveTargetY - m.y
                    local dist = math.sqrt(ddx * ddx + ddy * ddy)
                    if dist < 16 then
                        m.diving = false
                        m.vy = -200
                        m.targetY = m.returnY
                        m.changeTimer = 1.5 + math.random() * 2
                    else
                        m.x = m.x + ddx / dist * 200 * dt
                        m.y = m.y + ddy / dist * 200 * dt

                        if player.invulnTimer <= 0 and math.abs(m.x - player.x) < 24 and math.abs(m.y - (player.y - 8)) < 24 then
                            player.vy = -200
                            player.vx = (m.x > player.x and 1 or -1) * 200
                            player.invulnTimer = 0.5
                        end
                    end
                else
                    m.attackTimer = m.attackTimer - dt
                    if m.attackTimer <= 0 then
                        local aDist = math.sqrt((m.x - player.x)^2 + (m.y - (player.y - 8))^2)
                        if aDist < 25 * 16 then
                            m.attackTimer = 3 + math.random() * 3
                            m.diving = true
                            m.diveTargetX = player.x + (math.random() - 0.5) * 60
                            m.diveTargetY = player.y - 8 + (math.random() - 0.5) * 60
                            m.returnY = m.targetY
                        end
                    end

                    m.changeTimer = m.changeTimer - dt
                    if m.changeTimer <= 0 then
                        m.changeTimer = 1.5 + math.random() * 2
                        m.dir = math.random() < 0.5 and -1 or 1
                        if not m.diving then
                            m.targetY = m.returnY + (math.random() - 0.5) * 60
                        end
                    end
                    local frontX = math.floor((m.x + m.dir * 36) / 16)
                    local midY = math.floor((m.y + 24) / 16)
                    if isSolid(frontX, midY) then
                        m.dir = -m.dir
                    end
                    m.x = m.x + m.dir * 50 * dt
                    m.vy = m.vy + (m.targetY - m.y) * 0.5 * dt
                    m.vy = m.vy * 0.92
                    m.y = m.y + m.vy * dt
                end
            end
        end

        for _, s in ipairs(slimes) do
            if s.alive then
                s.animTimer = s.animTimer + dt
                if s.animTimer > 0.12 then
                    s.animTimer = 0
                    s.frame = s.frame % 6 + 1
                end
                s.hitTimer = math.max(0, s.hitTimer - dt)
                s.hopTimer = s.hopTimer - dt
                if s.hopTimer <= 0 and s.onGround then
                    s.hopTimer = 0.8 + math.random() * 0.6
                    s.vy = -250 - math.random() * 100
                    s.hopCount = s.hopCount + 1
                    if s.hopCount >= 2 then
                        s.hopCount = 0
                        s.dir = player.x < s.x and -1 or 1
                    elseif math.random() < 0.4 then
                        s.dir = -s.dir
                    end
                end
                local frontX = math.floor((s.x + s.dir * 36) / 16)
                local midY = math.floor((s.y + 24) / 16)
                if isSolid(frontX, midY) then
                    s.dir = -s.dir
                end
                s.x = s.x + s.dir * 60 * dt
                s.vy = s.vy + 600 * dt
                local ny = s.y + s.vy * dt
                local ty = math.floor((ny + 32) / 16)
                local tx = math.floor(s.x / 16)
                s.onGround = false
                if isSolid(tx, ty) then
                    ny = ty * 16 - 32
                    s.vy = 0
                    s.onGround = true
                end
                s.y = ny
            end
        end

        for _, e in ipairs(q4Enemies) do
            if e.alive then
                e.animTimer = e.animTimer + dt
                if e.animTimer > 0.15 then
                    e.animTimer = 0
                    e.frame = e.frame % 4 + 1
                end
                e.hitTimer = math.max(0, e.hitTimer - dt)

                local dist = math.sqrt((e.x - player.x)^2 + (e.y - (player.y - 8))^2)

                e.shootTimer = e.shootTimer - dt
                if e.shootTimer <= 0 and dist < 400 then
                    e.shootTimer = 2 + math.random() * 1.5
                    table.insert(bullets, {
                        x = e.x,
                        y = e.y - 16,
                        vx = (player.x - e.x) / dist * 250,
                        vy = (player.y - 8 - e.y) / dist * 250,
                        gravity = 0,
                        color = {1, 0.3, 0.1, 1},
                        damage = 1,
                        bouncesLeft = 0,
                        life = 3,
                        dist = 0,
                        fromPlayer = false,
                    })
                end

                if dist < 400 then
                    e.dir = player.x < e.x and -1 or 1
                end

                local floatY = math.sin(love.timer.getTime() * 2 + e.x) * 0.8
                e.y = e.y + floatY * dt * 2
            end
        end

        if chapter == 2 and #q4Enemies > 0 and not ch2Complete then
            local allDead = true
            for _, e in ipairs(q4Enemies) do
                if e.alive then allDead = false; break end
            end
            if allDead then
                ch2Complete = true
                showCh2End = true
                ch2EndTimer = 0
            end
        end
    end
end

local function drawScene()
    local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()
    love.graphics.setCanvas(paletteCanvas)
    if player.y > 17 * 16 then
        love.graphics.clear(0.5, 0.08, 0.05, 1)
    else
        love.graphics.clear(0.4, 0.6, 0.9, 1)
    end
    love.graphics.setColor(1, 1, 1)
    love.graphics.push()
    love.graphics.translate(sw / 2, sh / 2)
    love.graphics.scale(zoom)
    love.graphics.translate(-sw / 2, -sh / 2)

    for _, c in ipairs(clouds) do
        local cx = c.x - camX
        local cy = c.y - camY
        if cx + c.w > 0 and cx - c.w < sw / zoom and cy + c.h > -50 and cy - c.h < sh / zoom + 50 then
            for _, p in ipairs(c.puffs) do
                love.graphics.setColor(1, 1, 1, 0.35)
                love.graphics.circle("fill", cx + p.ox, cy + p.oy, p.r)
            end
        end
    end

    terrain:draw(camX, camY, sw / zoom, sh / zoom)

    for _, pl in ipairs(plants) do
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(plantImg, plantQuads[pl.quadIdx], pl.x - 4 - camX, pl.y - camY)
    end

    if stoneX > -100 and stoneY > -100 then
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(stoneImg, love.graphics.newQuad(0, 24, 48, 24, 48, 48), stoneX - camX, stoneY - camY)

        local dx = player.x - (stoneX + 24)
        local dy = (player.y - 12) - stoneY
        if dx * dx + dy * dy < 60 * 60 then
            local cx = stoneX + 24 - camX
            local cy = stoneY - 4 - camY
            local pw, ph = 140, 24
            local px = cx - pw / 2
            local py = cy - ph

            love.graphics.setColor(0, 0.1, 0.15, 0.85)
            love.graphics.rectangle("fill", px, py, pw, ph, 3)

            love.graphics.setColor(0.3, 0.9, 1)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", px, py, pw, ph, 3)
            love.graphics.setLineWidth(1)

            love.graphics.setColor(0.5, 1, 0.8)
            local font = love.graphics.getFont()
            local txt = "CLICK TO MINE"
            local tw = font:getWidth(txt)
            love.graphics.print(txt, cx - tw / 2, py + (ph - font:getHeight()) / 2)
        end
    end

    for _, m in ipairs(mice) do
        if m.alive then
            if m.hitTimer > 0 then
                love.graphics.setColor(1, 0.4, 0.4)
            else
                love.graphics.setColor(1, 1, 1)
            end
            local dx = m.dir == -1 and m.x + 32 - camX or m.x - 32 - camX
            love.graphics.draw(mouseImg, mouseQuads[m.frame], math.floor(dx), math.floor(m.y - 32 - camY), 0, m.dir, 1)

            local barW = 36
            local barH = 5
            local segW = barW / m.maxHp
            local barX = m.x - barW / 2 - camX
            local barY = m.y - 36 - camY
            love.graphics.setColor(0.2, 0.2, 0.2, 0.8)
            love.graphics.rectangle("fill", barX, barY, barW, barH, 2)
            for s = 0, m.hp - 1 do
                love.graphics.setColor(0.2, 1.0, 0.3, 0.9)
                love.graphics.rectangle("fill", barX + s * segW + 1, barY + 1, segW - 2, barH - 2, 1)
            end
        end
    end

    for _, s in ipairs(slimes) do
        if s.alive then
            if s.hitTimer > 0 then
                love.graphics.setColor(1, 0.4, 0.4)
            else
                love.graphics.setColor(1, 1, 1)
            end
            local dx = s.dir == -1 and s.x + 32 - camX or s.x - 32 - camX
            love.graphics.draw(slimeImg, slimeQuads[s.frame], math.floor(dx), math.floor(s.y - 16 - camY), 0, s.dir, 1)

            local barW = 36
            local barH = 5
            local segW = barW / s.maxHp
            local barX = s.x - barW / 2 - camX
            local barY = s.y - 20 - camY
            love.graphics.setColor(0.2, 0.2, 0.2, 0.8)
            love.graphics.rectangle("fill", barX, barY, barW, barH, 2)
            for hp = 0, s.hp - 1 do
                love.graphics.setColor(0.2, 1.0, 0.3, 0.9)
                love.graphics.rectangle("fill", barX + hp * segW + 1, barY + 1, segW - 2, barH - 2, 1)
            end
        end
    end

    for _, e in ipairs(q4Enemies) do
        if e.alive then
            if e.hitTimer > 0 then
                love.graphics.setColor(1, 0.4, 0.4)
            else
                love.graphics.setColor(1, 1, 1)
            end
            love.graphics.draw(q4EnemyImg, q4EnemyQuads[e.frame], math.floor(e.x - 32 - camX), math.floor(e.y - 32 - camY), 0, e.dir, 1)

            local barW = 36
            local barH = 5
            local segW = barW / e.maxHp
            local barX = e.x - barW / 2 - camX
            local barY = e.y - 36 - camY
            love.graphics.setColor(0.2, 0.2, 0.2, 0.8)
            love.graphics.rectangle("fill", barX, barY, barW, barH, 2)
            for hp = 0, e.hp - 1 do
                love.graphics.setColor(0.2, 1.0, 0.3, 0.9)
                love.graphics.rectangle("fill", barX + hp * segW + 1, barY + 1, segW - 2, barH - 2, 1)
            end
        end
    end

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

    if player.invulnTimer > 0 and math.floor(player.invulnTimer * 10) % 2 == 0 then
        love.graphics.setColor(1, 1, 1, 0.4)
    else
        love.graphics.setColor(1, 1, 1)
    end
    local drawX = player.x - player.w / 2 - camX
    local floatOff = math.sin(levitateTimer * 2.5) * 1.5
    local drawY = player.y - player.h - 16 - camY + floatOff
    if player.facing == -1 then
        love.graphics.draw(playerImg, drawX + player.w, drawY, 0, -1, 1)
    else
        love.graphics.draw(playerImg, drawX, drawY)
    end

    if player.jumping then
        local bx = player.x - 12 - camX
        local by = player.y - player.h - 16 - 8 - camY + floatOff
        local bw = 24
        local fillW = bw * (player.jumpCharge / 1.0)
        love.graphics.setColor(0.2, 0.8, 1)
        love.graphics.rectangle("fill", bx, by, fillW, 4)
        love.graphics.setColor(0.5, 1, 1, 0.4)
        love.graphics.rectangle("line", bx, by, bw, 4)
    end

    if player.wallSlide then
        local wx = player.x + player.wallDir * (player.w / 2 + 2) - camX
        local wy = player.y - player.h / 2 - camY
        love.graphics.setColor(0.6, 0.6, 0.6, 0.6)
        for i = 0, 3 do
            love.graphics.circle("fill", wx + (math.random() - 0.5) * 4, wy + (i - 1.5) * 6, 1.5)
        end
        love.graphics.setColor(1, 1, 1)
    end

    for _, item in ipairs(items) do
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(goldImg, item.x - ITEM_SIZE / 2 - camX, item.y - ITEM_SIZE / 2 - camY)
    end

    love.graphics.pop()
end

function love.draw()
    if state == "menu" then
        menu:draw()
    elseif state == "game" then
        drawScene()

        local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()
        love.graphics.setColor(1, 1, 1)
        love.graphics.print("WASD - move | I - shop | LMB - shoot | P - palette", 10, 10)
        love.graphics.print("ESC - menu | F5 - debug + camera", 10, 30)

        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.rectangle("fill", 10, 50, 120, 22, 4)
        love.graphics.setColor(1, 0.85, 0)
        love.graphics.draw(goldImg, 16, 52, 0, 1.5, 1.5)
        love.graphics.print("x " .. goldCount, 38, 54)
        love.graphics.setColor(1, 0.6, 0, 0.7)
        love.graphics.print("x5", 80, 54)

        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.rectangle("fill", 10, 108, 120, 22, 4)
        love.graphics.setColor(0.6, 0.3, 1.0)
        love.graphics.print("EXP: " .. exp, 16, 112)

        local secBarX = 10
        local secBarY = 136
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

        if goldenRainTimer > 0 then
            love.graphics.setColor(0, 0, 0, 0.6)
            love.graphics.rectangle("fill", 10, 164, 130, 20, 4)
            love.graphics.setColor(1, 0.85, 0)
            local gLabel = "GOLDEN RAIN " .. math.ceil(goldenRainTimer) .. "s"
            love.graphics.print(gLabel, 16, 168)
        end

        local selType = bulletTypes[selectedBullet]
        love.graphics.setColor(0, 0, 0, 0.6)
        local selY = goldenRainTimer > 0 and 190 or 166
        love.graphics.rectangle("fill", 10, selY, 160, 40, 4)
        love.graphics.setColor(selType.color[1], selType.color[2], selType.color[3])
        love.graphics.rectangle("fill", 16, selY + 6, 12, 12)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print(selType.name, 34, selY + 4)
        love.graphics.setColor(0.7, 0.7, 0.7)
        love.graphics.print("DMG:" .. selType.damage .. " SPD:" .. selType.speed .. " $" .. selType.cost, 34, selY + 18)
        love.graphics.setColor(0.5, 0.5, 0.5)
        love.graphics.print("[Q/E] switch", 10, selY + 44)

        if paletteEnabled then
            love.graphics.setColor(0.2, 0.8, 0.2, 0.7)
            love.graphics.rectangle("fill", 10, selY + 56, 80, 16, 3)
            love.graphics.setColor(1, 1, 1)
            love.graphics.print("PALETTE", 16, selY + 58)
        end

        if tipTimer > 0 and tipText ~= "" then
            local tw = love.graphics.getFont():getWidth(tipText)
            local px = sw / 2 - tw / 2 - 16
            local py = 80
            local pw = tw + 32
            local ph = 32
            love.graphics.setColor(0, 0.1, 0.15, 0.85)
            love.graphics.rectangle("fill", px, py, pw, ph, 3)
            love.graphics.setColor(0.3, 0.9, 1)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", px, py, pw, ph, 3)
            love.graphics.setLineWidth(1)
            love.graphics.setColor(0.5, 1, 0.8)
            love.graphics.print(tipText, px + 16, py + (ph - love.graphics.getFont():getHeight()) / 2)
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

        local mmHell = player.y > 17 * 16
        local mmX, mmY = sw - 130, 10
        local ts = 0.5
        local mmW, mmH = 100 * ts, 50 * ts
        if mmHell then
            love.graphics.setColor(0.1, 0, 0, 0.6)
        else
            love.graphics.setColor(0, 0, 0, 0.5)
        end
        love.graphics.rectangle("fill", mmX - 5, mmY - 5, mmW + 10, mmH + 10, 4)
        for tx = 0, 99 do
            for ty = 0, 49 do
                local tile = worldCache[tx] and worldCache[tx][ty]
                if tile and tile ~= "air" then
                    if mmHell then
                        if tile == "grass_top" or tile == "dirt" then
                            love.graphics.setColor(0.4, 0.08, 0.02)
                        else
                            love.graphics.setColor(0.25, 0.04, 0)
                        end
                    else
                        if tile == "grass_top" or tile == "dirt" then
                            love.graphics.setColor(0.55, 0.35, 0.15)
                        else
                            love.graphics.setColor(0.4, 0.4, 0.4)
                        end
                    end
                    love.graphics.rectangle("fill", mmX + tx * ts, mmY + ty * ts, ts, ts)
                end
            end
        end
        local pt = math.floor(player.x / 16)
        local py_ = math.floor(player.y / 16)
        if mmHell then
            love.graphics.setColor(1, 0.3, 0)
        else
            love.graphics.setColor(1, 1, 0)
        end
        love.graphics.rectangle("fill", mmX + pt * ts - 1, mmY + py_ * ts - 1, 4, 4)

        if not chamberUnlocked then
            if mmHell then
                love.graphics.setColor(1, 0.2, 0, 0.7)
            else
                love.graphics.setColor(0.3, 0.9, 1, 0.7)
            end
            love.graphics.print("[F] UNLOCK LOWER LEVEL", mmX - 4, mmY + mmH + 8)
        end

        if showMap then
            local mapIsHell = mapQuadrant >= 3
            local mapBg1, mapBg2, mapBg3, mapBg4
            local mapGrid1, mapGrid2, mapGrid3, mapGrid4
            local mapTitle1, mapTitle2, mapTitle3, mapTitle4
            local mapSub1, mapSub2, mapSub3, mapSub4
            if mapIsHell then
                mapBg1, mapBg2, mapBg3, mapBg4 = 0.15, 0, 0, 0.9
                mapGrid1, mapGrid2, mapGrid3, mapGrid4 = 0.5, 0, 0, 0.4
                mapTitle1, mapTitle2, mapTitle3, mapTitle4 = 0.8, 0, 0, 0.7
                mapSub1, mapSub2, mapSub3, mapSub4 = 0.5, 0, 0, 0.5
            else
                mapBg1, mapBg2, mapBg3, mapBg4 = 0, 0.15, 0, 0.9
                mapGrid1, mapGrid2, mapGrid3, mapGrid4 = 0, 0.5, 0, 0.4
                mapTitle1, mapTitle2, mapTitle3, mapTitle4 = 0, 0.8, 0, 0.7
                mapSub1, mapSub2, mapSub3, mapSub4 = 0, 0.5, 0, 0.5
            end

            love.graphics.setColor(0, 0, 0, 0.85)
            love.graphics.rectangle("fill", 0, 0, sw, sh)

            local mapW, mapH = 400, 200
            local mapX = sw / 2 - mapW / 2
            local mapY = sh / 2 - mapH / 2

            love.graphics.setColor(mapBg1, mapBg2, mapBg3, mapBg4)
            love.graphics.rectangle("fill", mapX, mapY, mapW, mapH)

            love.graphics.setColor(mapGrid1, mapGrid2, mapGrid3, mapGrid4)
            for gx = 0, 20 do
                local gxPos = mapX + gx * (mapW / 20)
                love.graphics.line(gxPos, mapY, gxPos, mapY + mapH)
            end
            for gy = 0, 10 do
                local gyPos = mapY + gy * (mapH / 15)
                love.graphics.line(mapX, gyPos, mapX + mapW, gyPos)
            end

            local quadLabels = {"TL", "TR", "BL", "BR"}
            local quadNames = {"Top-Left", "Top-Right", "Hell-Left", "Hell-Right"}
            for q = 1, 4 do
                local isHell = q >= 3
                local qx = mapX + ((q - 1) % 2) * (mapW / 2)
                local qy = mapY + math.floor((q - 1) / 2) * (mapH / 2)
                local qw = mapW / 2
                local qh = mapH / 2

                if q == mapQuadrant then
                    if isHell then
                        love.graphics.setColor(0.8, 0, 0, 0.3)
                    else
                        love.graphics.setColor(0, 0.8, 0, 0.3)
                    end
                    love.graphics.rectangle("fill", qx, qy, qw, qh)
                    if isHell then
                        love.graphics.setColor(1, 0, 0, 0.8)
                    else
                        love.graphics.setColor(0, 1, 0, 0.8)
                    end
                    love.graphics.setLineWidth(2)
                    love.graphics.rectangle("line", qx, qy, qw, qh)
                    love.graphics.setLineWidth(1)
                else
                    if isHell then
                        love.graphics.setColor(0.6, 0, 0, 0.3)
                    else
                        love.graphics.setColor(0, 0.6, 0, 0.3)
                    end
                    love.graphics.rectangle("line", qx, qy, qw, qh)
                end

                if isHell then
                    love.graphics.setColor(0.45, 0, 0, 0.6)
                else
                    love.graphics.setColor(0, 0.45, 0, 0.6)
                end
                love.graphics.print(q .. " - " .. quadNames[q], qx + 8, qy + 8)
            end

            local quad = mapQuadrant
            local hell = quad >= 3
            local offX = (quad - 1) % 2 == 0 and 0 or 50
            local offY = quad < 3 and 0 or 25
            local qw, qh = 50, 25
            local scaleX = (mapW / 2) / qw
            local scaleY = (mapH / 2) / qh
            local baseX = mapX + ((quad - 1) % 2) * (mapW / 2)
            local baseY = mapY + math.floor((quad - 1) / 2) * (mapH / 2)

            if hell and hellImg then
                love.graphics.setColor(1, 1, 1, 0.35)
                love.graphics.draw(hellImg, hellQuads[hellTileIdx],
                    baseX, baseY, 0, (mapW/2)/128, (mapH/2)/128)
            end

            for tx = offX, offX + qw - 1 do
                for ty = offY, offY + qh - 1 do
                    local tile = worldCache[tx] and worldCache[tx][ty]
                    if tile and tile ~= "air" then
                        if hell then
                            if tile == "grass_top" or tile == "dirt" then
                                love.graphics.setColor(0.5, 0.1, 0.05, 0.6)
                            else
                                love.graphics.setColor(0.3, 0.05, 0, 0.5)
                            end
                        else
                            if tile == "grass_top" or tile == "dirt" then
                                love.graphics.setColor(0, 0.4, 0, 0.5)
                            else
                                love.graphics.setColor(0, 0.2, 0, 0.4)
                            end
                        end
                        love.graphics.rectangle("fill", baseX + (tx - offX) * scaleX, baseY + (ty - offY) * scaleY, scaleX + 1, scaleY + 1)
                    end
                end
            end

            local px = baseX + (player.x / 16 - offX) * scaleX
            local pmy = baseY + (player.y / 16 - offY) * scaleY
            local blink = 0.5 + 0.5 * math.sin(love.timer.getTime() * 6)
            if hell then
                love.graphics.setColor(1, 0.3, 0, blink)
            else
                love.graphics.setColor(0, 1, 0, blink)
            end
            love.graphics.circle("fill", px, pmy, 4)
            if hell then
                love.graphics.setColor(1, 0.3, 0.3, blink * 0.5)
            else
                love.graphics.setColor(0.3, 1, 0.3, blink * 0.5)
            end
            love.graphics.circle("line", px, pmy, 8)

            love.graphics.setColor(mapTitle1, mapTitle2, mapTitle3, mapTitle4)
            local font = love.graphics.getFont()
            love.graphics.print("MAP [" .. quadLabels[mapQuadrant] .. "]", mapX + 10, mapY + 10)
            love.graphics.setColor(mapSub1, mapSub2, mapSub3, mapSub4)
            love.graphics.print("1-4 switch | M close", mapX + mapW - 140, mapY + 10)

            if not chamberUnlocked then
                love.graphics.setColor(1, 0.85, 0, 0.6)
                local hint = "Press F with 256G to unlock"
                local hw = love.graphics.getFont():getWidth(hint)
                love.graphics.print(hint, mapX + (mapW - hw) / 2, mapY + mapH - 56)

                local bx = mapX + mapW / 2 - 80
                local by = mapY + mapH - 40
                local bw, bh = 160, 30
                love.graphics.setColor(0.6, 0.4, 0, 0.8)
                love.graphics.rectangle("fill", bx, by, bw, bh, 4)
                love.graphics.setColor(1, 0.85, 0)
                love.graphics.setLineWidth(2)
                love.graphics.rectangle("line", bx, by, bw, bh, 4)
                love.graphics.setLineWidth(1)
                love.graphics.setColor(1, 1, 0)
                local unlockText = "UNLOCK (256G)"
                local tw = love.graphics.getFont():getWidth(unlockText)
                love.graphics.print(unlockText, bx + (bw - tw) / 2, by + (bh - love.graphics.getFont():getHeight()) / 2)
            end
        end

        if showDebug then
            local mx, my = love.mouse.getPosition()
            local wmx = (mx - sw / 2) / zoom + sw / 2 + camX
            local wmy = (my - sh / 2) / zoom + sh / 2 + camY

            love.graphics.setColor(1, 1, 0)
            love.graphics.print("Player:  " .. math.floor(player.x) .. ", " .. math.floor(player.y), 10, 246)
            love.graphics.print("Camera:  " .. math.floor(camX) .. ", " .. math.floor(camY), 10, 266)
            love.graphics.print("Off:     " .. math.floor(camOffX) .. ", " .. math.floor(camOffY), 10, 286)
            love.graphics.print("Mouse:   " .. math.floor(wmx) .. ", " .. math.floor(wmy), 10, 306)
            love.graphics.print("Tile XY: " .. math.floor(wmx / 16) .. ", " .. math.floor(wmy / 16), 10, 326)
            love.graphics.print("Tile:    " .. (terrain:getTile(math.floor(wmx / 16), math.floor(wmy / 16)) or "none"), 10, 346)
            love.graphics.print("Bullets: " .. #bullets, 10, 366)
            love.graphics.print("Parts:   " .. #particles, 10, 386)
            love.graphics.print("Stamina: " .. math.floor(stamina) .. "/" .. STAMINA_MAX, 10, 406)
            love.graphics.setColor(1, 1, 0)
            love.graphics.print("FPS: " .. love.timer.getFPS(), 10, 426)
            love.graphics.print("EXP: " .. exp, 10, 446)
            love.graphics.setColor(1, 0.5, 0)
            love.graphics.print("Stone1(Q1): " .. math.floor(stone1X) .. ", " .. math.floor(stone1Y) ..
                " tile: " .. math.floor((stone1X + 24) / 16) .. "," .. math.floor(stone1Y / 16 + 1), 10, 466)
            love.graphics.print("Stone (cur): " .. math.floor(stoneX) .. ", " .. math.floor(stoneY) ..
                " tile: " .. math.floor((stoneX + 24) / 16) .. "," .. math.floor(stoneY / 16 + 1), 10, 486)
            if stoneX > -100 then
                local stx = math.floor((stoneX + 24) / 16)
                local sty = math.floor(stoneY / 16 + 1)
                love.graphics.print("  tile@: " .. (terrain:getTile(stx, sty) or "none"), 10, 506)
                love.graphics.print("  tile0@: " .. (terrain:getTile(stx, sty - 1) or "none"), 10, 526)
            end
        end

        love.graphics.setCanvas()

        if paletteEnabled and paletteShader and paletteImg then
            love.graphics.setCanvas(rgbCanvas)
            love.graphics.clear(0, 0, 0, 0)
            love.graphics.setShader(paletteShader)
            paletteShader:send("uPalette", paletteImg)
            paletteShader:send("uEnabled", true)
            love.graphics.setColor(1, 1, 1)
            love.graphics.draw(paletteCanvas, 0, 0)
            love.graphics.setShader()
            love.graphics.setCanvas()
        end

        local srcCanvas = (paletteEnabled and paletteShader and paletteImg) and rgbCanvas or paletteCanvas

        if rgbEnabled and rgbShader then
            rgbShader:send("uTime", love.timer.getTime())
            love.graphics.setShader(rgbShader)
        end
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(srcCanvas, 0, 0)
        if rgbEnabled and rgbShader then
            love.graphics.setShader()
        end

        if gamePaused then
            local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()
            love.graphics.setColor(0, 0, 0, 0.75)
            love.graphics.rectangle("fill", 0, 0, sw, sh)

            love.graphics.setColor(1, 0.85, 0)
            local ptxt = "PAUSED"
            love.graphics.print(ptxt, (sw - love.graphics.getFont():getWidth(ptxt)) / 2, 60)

            local mx, my = love.mouse.getPosition()
            pauseHovered = nil
            for _, b in ipairs(pauseButtons) do
                if mx >= b.x and mx <= b.x + b.w and my >= b.y and my <= b.y + b.h then
                    pauseHovered = b
                end
            end
            for _, b in ipairs(pauseButtons) do
                if pauseHovered == b then
                    love.graphics.setColor(0.25, 0.45, 0.7, 0.9)
                else
                    love.graphics.setColor(0.15, 0.3, 0.55, 0.85)
                end
                love.graphics.rectangle("fill", b.x, b.y, b.w, b.h, 8)
                if pauseHovered == b then
                    love.graphics.setColor(0.5, 0.8, 1)
                    love.graphics.rectangle("line", b.x, b.y, b.w, b.h, 8)
                end
                love.graphics.setColor(1, 1, 1)
                local tw = love.graphics.getFont():getWidth(b.text)
                love.graphics.print(b.text, b.x + (b.w - tw) / 2, b.y + (b.h - love.graphics.getFont():getHeight()) / 2)
            end
        end

        if showEndScreen then
            local elapsed = love.timer.getTime() - gameStartTime
            local mins = math.floor(elapsed / 60)
            local secs = math.floor(elapsed % 60)
            local timeStr = string.format("%02d:%02d", mins, secs)
            local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()

            local alpha = math.min(1, endScreenTimer / 2)
            love.graphics.setColor(0, 0, 0, alpha * 0.85)
            love.graphics.rectangle("fill", 0, 0, sw, sh)

            love.graphics.setColor(1, 0.85, 0, alpha)
            local font = love.graphics.getFont()
            local line1 = "CHAPTER I COMPLETE"
            local tw = font:getWidth(line1)
            love.graphics.print(line1, (sw - tw) / 2, sh / 2 - 40)

            love.graphics.setColor(0.3, 0.9, 1, alpha)
            local line2 = "TIME: " .. timeStr
            local tw2 = font:getWidth(line2)
            love.graphics.print(line2, (sw - tw2) / 2, sh / 2)

            if endScreenTimer > 3 then
                love.graphics.setColor(0.5, 1, 0.8, alpha * (endScreenTimer - 3))
                local line3 = "F - ENTER HELL"
                local tw3 = font:getWidth(line3)
                love.graphics.print(line3, (sw - tw3) / 2, sh / 2 + 50)
            end
        end

        if showCh2End then
            local elapsed = love.timer.getTime() - gameStartTime
            local mins = math.floor(elapsed / 60)
            local secs = math.floor(elapsed % 60)
            local timeStr = string.format("%02d:%02d", mins, secs)
            local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()

            local alpha = math.min(1, ch2EndTimer / 2)
            love.graphics.setColor(0, 0, 0, alpha * 0.85)
            love.graphics.rectangle("fill", 0, 0, sw, sh)

            love.graphics.setColor(0.9, 0.2, 0.1, alpha)
            local font = love.graphics.getFont()
            local line1 = "CHAPTER II COMPLETE"
            local tw = font:getWidth(line1)
            love.graphics.print(line1, (sw - tw) / 2, sh / 2 - 40)

            love.graphics.setColor(0.3, 0.9, 1, alpha)
            local line2 = "TIME: " .. timeStr
            local tw2 = font:getWidth(line2)
            love.graphics.print(line2, (sw - tw2) / 2, sh / 2)

            if ch2EndTimer > 3 then
                love.graphics.setColor(0.5, 1, 0.8, alpha * (ch2EndTimer - 3))
                local line3 = "F - ENTER CHAPTER 3"
                local tw3 = font:getWidth(line3)
                love.graphics.print(line3, (sw - tw3) / 2, sh / 2 + 50)
            end
        end
    end
end

function love.keypressed(key)
    if state == "game" then
        if key == "escape" then
            if showEndScreen then
                showEndScreen = false
            elseif showCh2End then
                showCh2End = false
            elseif gamePaused then
                gamePaused = false
            else
                gamePaused = true
            end
        elseif gamePaused then
            return
        elseif key == "space" then
            if player.wallSlide then
                player.jumping = false
                player.vy = JUMP_VEL * 1.3
                player.vx = player.wallDir * -MAX_SPEED * 1.5
                local wd = player.wallDir
                player.wallSlide = false
                player.wallDir = 0
                player.onGround = false
                player.facing = -wd
            elseif player.jumps > 0 and not player.jumping then
                player.jumping = true
                player.jumpCharge = 0
            end
        elseif key == "i" then
            shopOpen = not shopOpen
        elseif key == "q" then
            selectedBullet = selectedBullet - 1
            if selectedBullet < 1 then selectedBullet = #bulletTypes end
        elseif key == "e" then
            selectedBullet = selectedBullet + 1
            if selectedBullet > #bulletTypes then selectedBullet = 1 end
        elseif key == "1" then
            if showMap then
                mapQuadrant = 1
            elseif showDebug then
                player.x = 25 * 16; player.y = 6 * 16 + 8; player.vx = 0; player.vy = 0
            elseif shopOpen then
                selectedBullet = 1
            end
        elseif key == "2" then
            if showMap then
                mapQuadrant = 2
            elseif showDebug then
                player.x = 75 * 16; player.y = 6 * 16 + 8; player.vx = 0; player.vy = 0
            elseif shopOpen and #bulletTypes >= 2 then
                selectedBullet = 2
            end
        elseif key == "3" then
            if showMap then
                mapQuadrant = 3
            elseif showDebug then
                player.x = 25 * 16; player.y = 19 * 16 + 8; player.vx = 0; player.vy = 0
            elseif shopOpen and #bulletTypes >= 3 then
                selectedBullet = 3
            end
        elseif key == "4" then
            if showMap then
                mapQuadrant = 4
            elseif showDebug then
                player.x = 75 * 16; player.y = 19 * 16 + 8; player.vx = 0; player.vy = 0
            elseif shopOpen and #bulletTypes >= 4 then
                selectedBullet = 4
            end
        elseif key == "p" then
            paletteEnabled = not paletteEnabled
        elseif key == "m" then
            showMap = not showMap
        elseif key == "f" then
            if showEndScreen and chamberUnlocked and endScreenTimer > 3 then
                local sx = 25 * 16
                local surfY = 12
                for ty = 0, 14 do
                    if terrain:getTile(25, ty) == "grass_top" then
                        surfY = ty
                        break
                    end
                end
                for dx = -1, 1 do
                    local tx = 25 + dx
                    for dy = surfY, 26 do
                        terrain:setTile(tx, dy, "air")
                        if worldCache[tx] then
                            worldCache[tx][dy] = "air"
                        end
                    end
                end

                local hellSpots = {}
                for tx = 0, 45 do
                    for ty = 35, 44 do
                        if terrain:getTile(tx, ty) == "hell" then
                            local flat = true
                            for i = 0, 4 do
                                if terrain:getTile(tx + i, ty) ~= "hell" then
                                    flat = false
                                    break
                                end
                            end
                            if flat then
                                hellSpots[#hellSpots + 1] = {tx = tx + 2, ty = ty}
                                break
                            end
                        end
                    end
                end
                if #hellSpots > 0 then
                    local pick = hellSpots[math.random(1, #hellSpots)]
                    stoneX = pick.tx * 16 + 8 - 24
                    stoneY = pick.ty * 16 - 24
                    player.x = stoneX + 24
                    player.y = stoneY + 24
                else
                    player.x = sx
                    player.y = surfY * 16
                end
                player.vx = 0
                player.vy = 0
                player.onGround = false
                showEndScreen = false
                mapQuadrant = 3
                chapter = 2
                tipText = "CHAPTER II - HELL"
                tipTimer = 3
            elseif showCh2End and ch2Complete and ch2EndTimer > 3 then
                showCh2End = false
                chapter = 3
                tipText = "CHAPTER III - COMING SOON"
                tipTimer = 3
            elseif not chamberUnlocked then
                if goldCount >= 256 then
                    goldCount = goldCount - 256
                    chamberUnlocked = true
                    showEndScreen = true
                    endScreenTimer = 0
                end
            end
        end
    end
    if key == "f5" then
        showDebug = not showDebug
    end
end

function love.keyreleased(key)
    if state == "game" and key == "space" and player.jumping then
        player.jumping = false
        local minJump, maxJump = 0.2, 1.0
        local t = math.max(0, math.min(1, (player.jumpCharge - minJump) / (maxJump - minJump)))
        player.vy = JUMP_VEL * (1 + t * 1.5)
        player.jumps = player.jumps - 1
        player.onGround = false
    end
end

function love.mousepressed(x, y, button)
    if state == "menu" then
        menu:mousepressed(x, y, button)
    elseif state == "game" and button == 1 then
        if gamePaused then
            for _, b in ipairs(pauseButtons) do
                if x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
                    if b.action == "resume" then
                        gamePaused = false
                    elseif b.action == "newgame" then
                        love.load()
                    elseif b.action == "save" then
                        tipText = "PROGRESS SAVED"
                        tipTimer = 3
                        gamePaused = false
                    elseif b.action == "exit" then
                        state = "menu"
                        if bgm then bgm:stop() end
                    end
                    return
                end
            end
            return
        end
        if shopOpen then return end
        if stoneX > -100 then
            local dx = player.x - (stoneX + 24)
            local dy = (player.y - 12) - stoneY
            if dx * dx + dy * dy < 60 * 60 then
                stoneHitCount = stoneHitCount + 1
                spawnImpact(stoneX + 24, stoneY, {0.6, 0.6, 0.6}, 8)
                goldCount = goldCount + 3
                exp = exp + 1

                local tips = {
                    "WASD — WALK AND FLY",
                    "I — OPEN SHOP",
                    "M — OPEN MAP",
                }
                tipText = tips[((stoneHitCount - 1) % 3) + 1]
                tipTimer = 5

                if stoneHitCount % 3 == 0 then
                    player.x = stoneX + 24
                    player.y = stoneY + 24
                    player.vy = 0
                    player.vx = 0
                    player.onGround = false
                end
                return
            end
        end
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

                local spread = player.onGround and 0.08 or 0.18
                local a = math.atan2(dy, dx) + (math.random() - 0.5) * spread * 2
                dx = math.cos(a)
                dy = math.sin(a)

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
                    fromPlayer = true,
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
