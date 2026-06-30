local Noise = {}
Noise.__index = Noise

local function fade(t)
    return t * t * t * (t * (t * 6 - 15) + 10)
end

local function lerp(a, b, t)
    return a + t * (b - a)
end

local function grad(hash, x, y)
    local h = hash % 4
    if h == 0 then return  x + y
    elseif h == 1 then return -x + y
    elseif h == 2 then return  x - y
    end
    return -x - y
end

function Noise.new(seed)
    local self = setmetatable({}, Noise)
    local p = {}
    for i = 0, 255 do p[i] = i end
    math.randomseed(seed or os.time())
    for i = 255, 1, -1 do
        local j = math.random(0, i)
        p[i], p[j] = p[j], p[i]
    end
    self.p = {}
    for i = 0, 511 do
        self.p[i] = p[i % 256]
    end
    return self
end

function Noise:perlin(x, y)
    local X = math.floor(x) % 256
    local Y = math.floor(y) % 256
    local xf = x - math.floor(x)
    local yf = y - math.floor(y)
    local u = fade(xf)
    local v = fade(yf)

    local aa = self.p[self.p[X] + Y]
    local ab = self.p[self.p[X] + Y + 1]
    local ba = self.p[self.p[X + 1] + Y]
    local bb = self.p[self.p[X + 1] + Y + 1]

    local x1 = lerp(grad(aa, xf, yf), grad(ba, xf - 1, yf), u)
    local x2 = lerp(grad(ab, xf, yf - 1), grad(bb, xf - 1, yf - 1), u)
    return lerp(x1, x2, v)
end

function Noise:octave(x, y, octaves, persistence)
    local total = 0
    local freq = 1
    local amp = 1
    local maxAmp = 0
    for _ = 1, octaves do
        total = total + self:perlin(x * freq, y * freq) * amp
        maxAmp = maxAmp + amp
        freq = freq * 2
        amp = amp * persistence
    end
    return total / maxAmp
end

return Noise
