local menu = {}

local buttons = {}
local hovered = nil
local menuShaders = {}
local activeShader = nil
local menuCanvas = nil

function menu:load()
    local cx = love.graphics.getWidth() / 2
    local cy = love.graphics.getHeight() / 2
    local w, h = 240, 50
    local gap = 20

    local labels = {
        {text = "Play",      action = "play"},
        {text = "Settings",  action = "settings"},
        {text = "Exit",      action = "exit", crossed = true},
    }

    local startY = cy - (#labels * (h + gap) - gap) / 2

    for i, lbl in ipairs(labels) do
        buttons[i] = {
            text    = lbl.text,
            action  = lbl.action,
            crossed = lbl.crossed or false,
            x = cx - w / 2,
            y = startY + (i - 1) * (h + gap),
            w = w,
            h = h,
        }
    end

    if #menuShaders == 0 then
        for i = 1, 5 do
            local ok, s = pcall(love.graphics.newShader, "mgf/menu_shader_" .. i .. ".glsl")
            if ok then
                menuShaders[#menuShaders + 1] = s
            end
        end
    end

    if #menuShaders > 0 then
        activeShader = menuShaders[math.random(#menuShaders)]
    else
        activeShader = nil
    end

    menuCanvas = love.graphics.newCanvas(love.graphics.getWidth(), love.graphics.getHeight())
end

function menu:pickRandom()
    if #menuShaders > 0 then
        activeShader = menuShaders[math.random(#menuShaders)]
    end
end

function menu:update(dt)
    hovered = nil
    local mx, my = love.mouse.getPosition()
    for _, b in ipairs(buttons) do
        if mx >= b.x and mx <= b.x + b.w and my >= b.y and my <= b.y + b.h then
            hovered = b
            break
        end
    end
end

local function drawButton(b, hov)
    if hov then
        love.graphics.setColor(0.25, 0.45, 0.7)
    else
        love.graphics.setColor(0.15, 0.3, 0.55)
    end

    love.graphics.rectangle("fill", b.x, b.y, b.w, b.h, 8, 8)

    if hov then
        love.graphics.setColor(0.5, 0.8, 1)
        love.graphics.rectangle("line", b.x, b.y, b.w, b.h, 8, 8)
    end

    local font = love.graphics.getFont()
    local tw = font:getWidth(b.text)
    local th = font:getHeight()
    local tx = b.x + (b.w - tw) / 2
    local ty = b.y + (b.h - th) / 2

    love.graphics.setColor(1, 1, 1)
    love.graphics.print(b.text, tx, ty)

    if b.crossed then
        love.graphics.setColor(0.9, 0.25, 0.25)
        love.graphics.setLineWidth(3)
        love.graphics.line(b.x + 10, ty + th / 2, b.x + b.w - 10, ty + th / 2)
        love.graphics.setLineWidth(1)
    end
end

function menu:draw()
    if menuCanvas then
        love.graphics.setCanvas(menuCanvas)
    end

    love.graphics.clear(0.08, 0.1, 0.15)

    love.graphics.setColor(1, 1, 1)
    local title = "Main Menu"
    local font = love.graphics.getFont()
    local tw = font:getWidth(title)
    love.graphics.print(title, (love.graphics.getWidth() - tw) / 2, 80)

    for _, b in ipairs(buttons) do
        drawButton(b, b == hovered)
    end

    if menuCanvas then
        love.graphics.setCanvas()
    end

    if activeShader then
        activeShader:send("uTime", love.timer.getTime())
        love.graphics.setShader(activeShader)
    end

    love.graphics.setColor(1, 1, 1)
    if menuCanvas then
        love.graphics.draw(menuCanvas, 0, 0)
    end

    if activeShader then
        love.graphics.setShader()
    end
end

function menu:mousepressed(x, y, button)
    if button ~= 1 then return end
    if hovered then
        if hovered.action == "play" then
            if self.onPlay then self.onPlay() end
        elseif hovered.action == "settings" then
            if self.onSettings then self.onSettings() end
        elseif hovered.action == "exit" then
            love.event.quit()
        end
    end
end

function menu:mousereleased(x, y, button)
end

return menu
