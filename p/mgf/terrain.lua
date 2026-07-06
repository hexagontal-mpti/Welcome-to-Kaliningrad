local Terrain = {}
Terrain.__index = Terrain

local TILE_SIZE = 16
local MAX_X = 100
local MAX_Y = 50

local SPRITES = {
    stone     = {x = 1, y = 0},
    dirt      = {x = 2, y = 0},
    grass_top = {x = 3, y = 0},
}

function Terrain.new(imagePath, hellImage)
    local self = setmetatable({}, Terrain)
    self.image = love.graphics.newImage(imagePath)
    self.image:setFilter("nearest", "nearest")
    self.hellImage = hellImage

    self.quads = {}
    for name, sp in pairs(SPRITES) do
        self.quads[name] = love.graphics.newQuad(
            sp.x * TILE_SIZE, sp.y * TILE_SIZE,
            TILE_SIZE, TILE_SIZE,
            self.image:getWidth(), self.image:getHeight()
        )
    end

    self.hellQuads = {}
    for blockIdx = 1, 4 do
        local bx = (blockIdx - 1) % 2
        local by = math.floor((blockIdx - 1) / 2)
        for localY = 0, 7 do
            for localX = 0, 7 do
                local idx = (blockIdx - 1) * 64 + localY * 8 + localX + 1
                self.hellQuads[idx] = love.graphics.newQuad(
                    bx * 128 + localX * 16, by * 128 + localY * 16,
                    16, 16,
                    256, 256
                )
            end
        end
    end

    self.chunkW = 64
    self.chunkH = 32
    self.chunks = {}
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
        local surfaceY = math.floor(12 + h * (self.chunkH * 0.3))

        for y = 1, self.chunkH do
            local worldY = wy + y - 1

            if worldY >= 18 then
                if worldY >= 48 then
                    grid[x][y] = "hell"
                else
                    local ch = self.noise:octave((wx + x) * 0.03, 100, 3, 0.5)
                    local ceilingH = math.floor(24 + ch * 4)
                    if ceilingH < 22 then ceilingH = 22 end
                    if ceilingH > 28 then ceilingH = 28 end
                    local fh = self.noise:octave((wx + x) * 0.03, 200, 3, 0.5)
                    local floorH = math.floor(41 + fh * 3)
                    if floorH < 38 then floorH = 38 end
                    if floorH > 44 then floorH = 44 end
                    if worldY < ceilingH or worldY > floorH then
                        local hole = self.noise:octave((wx + x) * 0.06, (wy + y) * 0.06 + 300, 2, 0.5)
                        if hole < -0.4 then
                            grid[x][y] = "air"
                        else
                            grid[x][y] = "hell"
                        end
                    else
                        local island = self.noise:octave((wx + x) * 0.08, (wy + y) * 0.08 + 400, 2, 0.5)
                        if island > 0.45 then
                            grid[x][y] = "hell"
                        else
                            grid[x][y] = "air"
                        end
                    end
                end
            elseif y == surfaceY then
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

function Terrain:setTile(x, y, tileType)
    if x < 0 or x > MAX_X or y < 0 or y > MAX_Y then return end
    local cx = math.floor(x / self.chunkW)
    local cy = math.floor(y / self.chunkH)
    local lx = x - cx * self.chunkW + 1
    local ly = y - cy * self.chunkH + 1
    local chunk = self:generateChunk(cx, cy)
    chunk[lx][ly] = tileType
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
            if tile == "hell" and self.hellImage then
                local blockX = math.floor(tx / 8)
                local blockY = math.floor(ty / 8)
                local hellBlock = (blockX + blockY) % 4 + 1
                local localX = tx % 8
                local localY = ty % 8
                local idx = (hellBlock - 1) * 64 + localY * 8 + localX + 1
                love.graphics.draw(self.hellImage, self.hellQuads[idx],
                    tx * TILE_SIZE - camX,
                    ty * TILE_SIZE - camY)
            else
                local quad = self.quads[tile]
                if quad then
                    love.graphics.draw(self.image, quad,
                        tx * TILE_SIZE - camX,
                        ty * TILE_SIZE - camY)
                end
            end
        end
    end
end

return Terrain
