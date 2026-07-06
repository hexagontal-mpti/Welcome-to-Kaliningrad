local Terrain = require("mgf.terrain")

local terrain
local camX, camY = 0, 0
local speed = 200

function love.load()
    love.graphics.setBackgroundColor(0.4, 0.6, 0.9)
    terrain = Terrain.new("assets/s.jpg")
end

function love.update(dt)
    local dx, dy = 0, 0
    if love.keyboard.isDown("a") or love.keyboard.isDown("left")  then dx = dx - 1 end
    if love.keyboard.isDown("d") or love.keyboard.isDown("right") then dx = dx + 1 end
    if love.keyboard.isDown("w") or love.keyboard.isDown("up")    then dy = dy - 1 end
    if love.keyboard.isDown("s") or love.keyboard.isDown("down")  then dy = dy + 1 end
    camX = camX + dx * speed * dt
    camY = camY + dy * speed * dt
end

function love.draw()
    terrain:draw(camX, camY, love.graphics.getWidth(), love.graphics.getHeight())

    love.graphics.setColor(1, 1, 1)
    love.graphics.print("WASD - move", 10, 10)
end
