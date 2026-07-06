local menu = {}

local menuState = "main"
local hovered = nil
local menuFrames = {}
local frameCount = 0

local mainButtons = {}
local settingsBack = nil
local settingsButtons = {}

local difficultyOptions = {"Easy", "Normal", "Hard"}
local resolutionOptions = {
    {w = 960,  h = 640,  label = "960x640"},
    {w = 1280, h = 720,  label = "1280x720"},
    {w = 1920, h = 1080, label = "1920x1080"},
}

menu.difficulty = "Normal"
menu.paletteEnabled = false
menu.fullscreen = false
menu.resolutionIndex = 1

function menu:load()
    local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()
    local cx = sw / 2
    local cy = sh / 2
    local w, h = 240, 50
    local gap = 20

    local labels = {
        {text = "Play",      action = "play"},
        {text = "Settings",  action = "settings"},
        {text = "Exit",      action = "exit", crossed = true},
    }

    local startY = cy - (#labels * (h + gap) - gap) / 2
    mainButtons = {}
    for i, lbl in ipairs(labels) do
        mainButtons[i] = {
            text    = lbl.text,
            action  = lbl.action,
            crossed = lbl.crossed or false,
            x = cx - w / 2,
            y = startY + (i - 1) * (h + gap),
            w = w,
            h = h,
        }
    end

    settingsBack = {x = 30, y = sh - 60, w = 120, h = 40, text = "Back", action = "back"}

    settingsButtons = {}
    local sy = 120
    local secGap = 60

    settingsButtons[#settingsButtons + 1] = {
        type = "section", text = "DIFFICULTY", x = cx - 200, y = sy
    }
    sy = sy + 35
    for i, diff in ipairs(difficultyOptions) do
        settingsButtons[#settingsButtons + 1] = {
            type = "difficulty", value = diff,
            x = cx - 200 + (i - 1) * 140, y = sy, w = 120, h = 36
        }
    end
    sy = sy + secGap

    settingsButtons[#settingsButtons + 1] = {
        type = "section", text = "PALETTE", x = cx - 200, y = sy
    }
    sy = sy + 35
    settingsButtons[#settingsButtons + 1] = {
        type = "palette", value = "ON/OFF",
        x = cx - 100, y = sy, w = 200, h = 36
    }
    sy = sy + secGap

    settingsButtons[#settingsButtons + 1] = {
        type = "section", text = "SCREEN", x = cx - 200, y = sy
    }
    sy = sy + 35
    settingsButtons[#settingsButtons + 1] = {
        type = "resolution", value = "Resolution",
        x = cx - 200, y = sy, w = 200, h = 36
    }
    settingsButtons[#settingsButtons + 1] = {
        type = "res_left", value = "<",
        x = cx + 20, y = sy, w = 36, h = 36
    }
    settingsButtons[#settingsButtons + 1] = {
        type = "res_right", value = ">",
        x = cx + 60, y = sy, w = 36, h = 36
    }
    sy = sy + 50
    settingsButtons[#settingsButtons + 1] = {
        type = "fullscreen", value = "Fullscreen",
        x = cx - 200, y = sy, w = 200, h = 36
    }
    settingsButtons[#settingsButtons + 1] = {
        type = "apply", value = "Apply",
        x = cx - 100, y = sy + 55, w = 200, h = 40
    }

    if frameCount == 0 then
        for i = 1, 100 do
            local path = string.format("assets/ntr/frames/frame_%04d.png", i)
            local ok, s = pcall(love.graphics.newImage, path)
            if ok then
                s:setFilter("linear", "linear")
                menuFrames[i] = s
                frameCount = i
            else
                break
            end
        end
    end
end

function menu:update(dt)
    hovered = nil
    local mx, my = love.mouse.getPosition()

    if menuState == "main" then
        for _, b in ipairs(mainButtons) do
            if mx >= b.x and mx <= b.x + b.w and my >= b.y and my <= b.y + b.h then
                hovered = b
                break
            end
        end
    elseif menuState == "settings" then
        if mx >= settingsBack.x and mx <= settingsBack.x + settingsBack.w and
           my >= settingsBack.y and my <= settingsBack.y + settingsBack.h then
            hovered = settingsBack
        end
        for _, b in ipairs(settingsButtons) do
            if b.w and b.h and mx >= b.x and mx <= b.x + b.w and my >= b.y and my <= b.y + b.h then
                hovered = b
                break
            end
        end
    end
end

local function drawButton(b, hov)
    if hov then
        love.graphics.setColor(0.25, 0.45, 0.7, 0.9)
    else
        love.graphics.setColor(0.15, 0.3, 0.55, 0.85)
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

local function drawToggle(b, isActive)
    local bx, by, bw, bh = b.x, b.y, b.w, b.h
    if isActive then
        love.graphics.setColor(0.2, 0.7, 0.3, 0.9)
    else
        love.graphics.setColor(0.4, 0.15, 0.15, 0.9)
    end
    love.graphics.rectangle("fill", bx, by, bw, bh, 6)

    if hovered == b then
        love.graphics.setColor(0.5, 0.8, 1)
        love.graphics.rectangle("line", bx, by, bw, bh, 6)
    end

    local font = love.graphics.getFont()
    local label = isActive and "ON" or "OFF"
    local tw = font:getWidth(label)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print(label, bx + (bw - tw) / 2, by + (bh - font:getHeight()) / 2)
end

local function drawSettings()
    local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()

    love.graphics.setColor(1, 1, 1)
    local title = "Settings"
    local font = love.graphics.getFont()
    local tw = font:getWidth(title)
    love.graphics.print(title, (sw - tw) / 2, 40)

    for _, b in ipairs(settingsButtons) do
        if b.type == "section" then
            love.graphics.setColor(1, 0.85, 0)
            love.graphics.print(b.text, b.x, b.y)
            love.graphics.setColor(1, 0.85, 0, 0.3)
            love.graphics.rectangle("fill", b.x, b.y + 22, 400, 1)
        elseif b.type == "difficulty" then
            local isActive = menu.difficulty == b.value
            if isActive then
                love.graphics.setColor(0.2, 0.6, 0.2, 0.9)
            elseif hovered == b then
                love.graphics.setColor(0.25, 0.45, 0.7, 0.9)
            else
                love.graphics.setColor(0.2, 0.2, 0.25, 0.9)
            end
            love.graphics.rectangle("fill", b.x, b.y, b.w, b.h, 6)
            if isActive or hovered == b then
                love.graphics.setColor(isActive and {0.5, 1, 0.5} or {0.5, 0.8, 1})
                love.graphics.rectangle("line", b.x, b.y, b.w, b.h, 6)
            end
            local f = love.graphics.getFont()
            local ltw = f:getWidth(b.value)
            love.graphics.setColor(1, 1, 1)
            love.graphics.print(b.value, b.x + (b.w - ltw) / 2, b.y + (b.h - f:getHeight()) / 2)

        elseif b.type == "palette" then
            drawToggle(b, menu.paletteEnabled)

        elseif b.type == "resolution" then
            love.graphics.setColor(0.2, 0.2, 0.25, 0.9)
            love.graphics.rectangle("fill", b.x, b.y, b.w, b.h, 6)
            local f = love.graphics.getFont()
            local label = resolutionOptions[menu.resolutionIndex].label
            local ltw = f:getWidth(label)
            love.graphics.setColor(1, 1, 1)
            love.graphics.print(label, b.x + (b.w - ltw) / 2, b.y + (b.h - f:getHeight()) / 2)

        elseif b.type == "res_left" or b.type == "res_right" then
            if hovered == b then
                love.graphics.setColor(0.25, 0.45, 0.7, 0.9)
            else
                love.graphics.setColor(0.2, 0.2, 0.25, 0.9)
            end
            love.graphics.rectangle("fill", b.x, b.y, b.w, b.h, 6)
            local f = love.graphics.getFont()
            local ltw = f:getWidth(b.value)
            love.graphics.setColor(1, 1, 1)
            love.graphics.print(b.value, b.x + (b.w - ltw) / 2, b.y + (b.h - f:getHeight()) / 2)

        elseif b.type == "fullscreen" then
            drawToggle(b, menu.fullscreen)

        elseif b.type == "apply" then
            if hovered == b then
                love.graphics.setColor(0.3, 0.6, 0.2, 0.9)
            else
                love.graphics.setColor(0.2, 0.4, 0.15, 0.9)
            end
            love.graphics.rectangle("fill", b.x, b.y, b.w, b.h, 8)
            if hovered == b then
                love.graphics.setColor(0.5, 1, 0.5)
                love.graphics.rectangle("line", b.x, b.y, b.w, b.h, 8)
            end
            local f = love.graphics.getFont()
            local ltw = f:getWidth(b.value)
            love.graphics.setColor(1, 1, 1)
            love.graphics.print(b.value, b.x + (b.w - ltw) / 2, b.y + (b.h - f:getHeight()) / 2)
        end
    end
end

function menu:draw()
    love.graphics.clear(0.05, 0.0, 0.02)

    local sw, sh = love.graphics.getWidth(), love.graphics.getHeight()

    if frameCount > 0 then
        local frameIdx = math.floor(love.timer.getTime() * 6.67) % frameCount + 1
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(menuFrames[frameIdx], 0, 0, 0, sw / 256, sh / 256)
    else
        local steps = 6
        local stepH = sh / steps
        for i = 0, steps - 1 do
            local t = i / (steps - 1)
            love.graphics.setColor(0.05 + 0.25 * t, 0.01 + 0.05 * t, 0.02 + 0.03 * t)
            love.graphics.rectangle("fill", 0, i * stepH, sw, stepH + 1)
        end
    end

    if menuState == "main" then
        love.graphics.setColor(1, 1, 1)
        local title = "Main Menu"
        local font = love.graphics.getFont()
        local tw = font:getWidth(title)
        love.graphics.print(title, (love.graphics.getWidth() - tw) / 2, 80)

        for _, b in ipairs(mainButtons) do
            drawButton(b, b == hovered)
        end
    elseif menuState == "settings" then
        drawSettings()
        drawButton(settingsBack, settingsBack == hovered)
    end
end

function menu:mousepressed(x, y, button)
    if button ~= 1 then return end

    if menuState == "main" then
        if hovered then
            if hovered.action == "play" then
                if self.onPlay then self.onPlay() end
            elseif hovered.action == "settings" then
                menuState = "settings"
            elseif hovered.action == "exit" then
                love.event.quit()
            end
        end
    elseif menuState == "settings" then
        if hovered == settingsBack then
            menuState = "main"
            return
        end
        if hovered then
            if hovered.type == "difficulty" then
                menu.difficulty = hovered.value
            elseif hovered.type == "palette" then
                menu.paletteEnabled = not menu.paletteEnabled
            elseif hovered.type == "fullscreen" then
                menu.fullscreen = not menu.fullscreen
            elseif hovered.type == "res_left" then
                menu.resolutionIndex = menu.resolutionIndex - 1
                if menu.resolutionIndex < 1 then menu.resolutionIndex = #resolutionOptions end
            elseif hovered.type == "res_right" then
                menu.resolutionIndex = menu.resolutionIndex + 1
                if menu.resolutionIndex > #resolutionOptions then menu.resolutionIndex = 1 end
            elseif hovered.type == "apply" then
                local res = resolutionOptions[menu.resolutionIndex]
                love.window.setMode(res.w, res.h, {fullscreen = menu.fullscreen, resizable = false})
                love.window.setTitle("Game")
                self:load()
            end
        end
    end
end

function menu:mousereleased(x, y, button)
end

return menu
