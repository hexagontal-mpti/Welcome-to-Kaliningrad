local Terrain = {}
Terrain.__index = Terrain

local TILE_SIZE = 16
local MAX_X = 100
local MAX_Y = 25

local SPRITES = {
    stone     = {x = 1, y = 0},
    dirt      = {x = 2, y = 0},
    grass_top = {x = 3, y = 0},
}

function Terrain.new(imagePath)
    local self = setmetatable({}, Terrain)
    self.image = love.graphics.newImage(imagePath)
    self.image:setFilter("nearest", "nearest")

    self.quads = {}
    for name, sp in pairs(SPRITES) do
        self.quads[name] = love.graphics.newQuad(
            sp.x * TILE_SIZE, sp.y * TILE_SIZE,
            TILE_SIZE, TILE_SIZE,
            self.image:getWidth(), self.image:getHeight()
        )
    end

    self.chunkW = 64
    self.chunkH = 32
    self.chunks = {}
    self.surfaceBase = math.floor(self.chunkH * 0.4)
    self.noise = require("mgf.noise").new(os.time())

    return self
end

function Terrain:generateChunk(cx, cy)
    local key = cx .. "," .. cy
    if self.chunks[key] then return self.chunks[key] end

    local grid = {}
    for x = 1, self.chunkW do
        grid[x] = {}
        for y = 1, self.chunkH do
            grid[x][y] = "air"
        end
    end

    local wx = cx * self.chunkW
    local wy = cy * self.chunkH

    for x = 1, self.chunkW do
        local h = self.noise:octave((wx + x) * 0.03, 0, 4, 0.5)
        local surfaceY = math.floor(self.surfaceBase + h * (self.chunkH * 0.3))

        for y = 1, self.chunkH do
            if y == surfaceY then
                grid[x][y] = "grass_top"
            elseif y > surfaceY then
                local below = y - surfaceY
                if below <= 3 then
                    grid[x][y] = "dirt"
                else
                    local cave = self.noise:octave((wx + x) * 0.06, (wy + y) * 0.06, 3, 0.5)
                    if cave < -0.15 then
                        grid[x][y] = "air"
                    elseif below <= 6 then
                        grid[x][y] = "dirt"
                    elseif cave < 0.15 then
                        grid[x][y] = "dirt"
                    else
                        grid[x][y] = "stone"
                    end
                end
            end
        end
    end

    self.chunks[key] = grid
    return grid
end

function Terrain:getTile(x, y)
    if x < 0 or x > MAX_X or y < 0 or y > MAX_Y then return "air" end
    local cx = math.floor(x / self.chunkW)
    local cy = math.floor(y / self.chunkH)
    local lx = x - cx * self.chunkW + 1
    local ly = y - cy * self.chunkH + 1
    local chunk = self:generateChunk(cx, cy)
    if chunk[lx] and chunk[lx][ly] then
        return chunk[lx][ly]
    end
    return "air"
end

function Terrain:draw(camX, camY, screenW, screenH)
    local cx = math.floor((camX + screenW / 2) / TILE_SIZE)
    local cy = math.floor((camY + screenH / 2) / TILE_SIZE)
    local r = 100
    local startTX = cx - r
    local startTY = cy - r
    local endTX = cx + r
    local endTY = cy + r

    for tx = startTX, endTX do
        for ty = startTY, endTY do
            local tile = self:getTile(tx, ty)
            local quad = self.quads[tile]
            if quad then
                love.graphics.draw(self.image, quad,
                    tx * TILE_SIZE - camX,
                    ty * TILE_SIZE - camY)
            end
        end
    end
end

return Terrain
