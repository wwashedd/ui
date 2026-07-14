local function rndName()
    local len = math.random(12, 22)
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local name = ""
    for i = 1, len do
        name = name .. chars:sub(math.random(1, #chars), math.random(1, #chars))
    end
    return name
end

local function getService(name)
    local success, svc = pcall(function()
        local cloneref = cloneref or function(x) return x end
        return cloneref(game:GetService(name))
    end)
    if success then return svc end
    return game:GetService(name)
end

local Players = getService("Players")
local UserInputService = getService("UserInputService")
local CoreGui = getService("CoreGui")
local RunService = getService("RunService")

local function getGUIContainer()
    -- Try each method in order, returning on first success.
    local methods = {
        -- 1. gethui (if available)
        function()
            if gethui then
                local gui = gethui()
                if gui then return gui end
            end
            return nil
        end,
        -- 2. syn.protect_gui (if available)
        function()
            if syn and syn.protect_gui then
                local success, result = pcall(syn.protect_gui, Instance.new("ScreenGui"))
                if success and result then return result end
            end
            return nil
        end,
        -- 3. CoreGui (with pcall)
        function()
            local success, container = pcall(function() return CoreGui end)
            if success and container then
                local gui = Instance.new("ScreenGui")
                gui.Parent = container
                return gui
            end
            return nil
        end,
        -- 4. PlayerGui (with robust waiting)
        function()
            local player = Players.LocalPlayer
            if not player then
                -- wait up to 5 seconds for LocalPlayer
                for i = 1, 50 do
                    player = Players.LocalPlayer
                    if player then break end
                    task.wait(0.1)
                end
            end
            if player then
                local playerGui = player:FindFirstChild("PlayerGui")
                if not playerGui then
                    -- wait up to 3 seconds for PlayerGui
                    for i = 1, 30 do
                        playerGui = player:FindFirstChild("PlayerGui")
                        if playerGui then break end
                        task.wait(0.1)
                    end
                end
                if playerGui then
                    local gui = Instance.new("ScreenGui")
                    gui.Parent = playerGui
                    return gui
                else
                    -- Try to parent directly to the player (some executors allow this)
                    local success, gui = pcall(function()
                        local g = Instance.new("ScreenGui")
                        g.Parent = player
                        return g
                    end)
                    if success and gui then
                        return gui
                    end
                end
            end
            return nil
        end,
        -- 5. Absolute last resort: retry CoreGui (maybe it works now)
        function()
            local success, container = pcall(function() return CoreGui end)
            if success and container then
                local gui = Instance.new("ScreenGui")
                gui.Parent = container
                return gui
            end
            return nil
        end
    }

    -- Iterate methods until one returns a valid ScreenGui
    for _, method in ipairs(methods) do
        local success, result = pcall(method)
        if success and result and result:IsA("ScreenGui") then
            return result
        end
    end

    -- If all fail, throw a clear error
    error("No GUI container available after all fallbacks")
end

local GUI_CONTAINER = getGUIContainer()

local _globalBorderColor = Color3.fromRGB(255, 0, 0)

local function addBorder(obj, thickness)
    thickness = thickness or 1
    local stroke = Instance.new("UIStroke")
    stroke.Name = rndName()
    stroke.Thickness = thickness
    stroke.Color = _globalBorderColor
    stroke.Parent = obj
    return stroke
end

local function clamp(val, min, max)
    return math.max(min, math.min(max, val))
end

-- ============================================================
-- Window class
-- ============================================================
local Window = {}
Window.__index = Window

function Window.new(title, size)
    size = size or UDim2.new(0, 450, 0, 350)
    local self = setmetatable({}, Window)
    self.title = title or "Window"
    self.tabs = {}
    self.currentTab = nil
    self.visible = true
    self.controls = {}

    local main = Instance.new("Frame")
    main.Name = rndName()
    main.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    main.BackgroundTransparency = 0
    main.Size = size
    main.Position = UDim2.new(0.5, -size.X.Offset/2, 0.5, -size.Y.Offset/2)
    main.Parent = GUI_CONTAINER
    addBorder(main)
    self.main = main

    local topbar = Instance.new("Frame")
    topbar.Name = rndName()
    topbar.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    topbar.BackgroundTransparency = 0
    topbar.Size = UDim2.new(1, 0, 0, 30)
    topbar.Position = UDim2.new(0, 0, 0, 0)
    topbar.Parent = main
    addBorder(topbar)
    self.topbar = topbar

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = rndName()
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = self.title
    titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    titleLabel.TextSize = 16
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Size = UDim2.new(1, -30, 1, 0)
    titleLabel.Position = UDim2.new(0, 6, 0, 0)
    titleLabel.Parent = topbar
    self.titleLabel = titleLabel

    local closeBtn = Instance.new("TextButton")
    closeBtn.Name = rndName()
    closeBtn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    closeBtn.BackgroundTransparency = 0
    closeBtn.Size = UDim2.new(0, 24, 1, 0)
    closeBtn.Position = UDim2.new(1, -24, 0, 0)
    closeBtn.Text = "X"
    closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeBtn.TextSize = 16
    closeBtn.Parent = topbar
    addBorder(closeBtn)
    closeBtn.MouseButton1Click:Connect(function()
        self:ToggleVisibility()
    end)
    self.closeBtn = closeBtn

    local content = Instance.new("Frame")
    content.Name = rndName()
    content.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    content.BackgroundTransparency = 0
    content.Size = UDim2.new(1, 0, 1, -30)
    content.Position = UDim2.new(0, 0, 0, 30)
    content.Parent = main
    addBorder(content)
    self.content = content

    self.tabBar = nil

    local dragging = false
    local dragOffset = Vector2.new()
    topbar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragOffset = input.Position - main.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local pos = input.Position - dragOffset
            main.Position = UDim2.new(0, pos.X, 0, pos.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)

    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if input.KeyCode == Enum.KeyCode.F4 then
            self:ToggleVisibility()
        end
    end)

    return self
end

function Window:ToggleVisibility()
    self.visible = not self.visible
    self.main.Visible = self.visible
end

function Window:CreateTab(name)
    if not self.tabBar then
        self.tabBar = Instance.new("Frame")
        self.tabBar.Name = rndName()
        self.tabBar.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        self.tabBar.BackgroundTransparency = 0
        self.tabBar.Size = UDim2.new(1, 0, 0, 30)
        self.tabBar.Position = UDim2.new(0, 0, 0, 0)
        self.tabBar.Parent = self.content
        addBorder(self.tabBar)
    end

    local tab = setmetatable({}, Tab)
    tab.name = name
    tab.window = self
    tab._y = 6
    tab.controls = {}

    local frame = Instance.new("Frame")
    frame.Name = rndName()
    frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    frame.BackgroundTransparency = 0
    frame.Size = UDim2.new(1, 0, 1, -30)
    frame.Position = UDim2.new(0, 0, 0, 30)
    frame.Visible = false
    frame.Parent = self.content
    addBorder(frame)
    tab.frame = frame

    local btn = Instance.new("TextButton")
    btn.Name = rndName()
    btn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    btn.BackgroundTransparency = 0
    btn.Size = UDim2.new(0, 80, 1, -2)
    btn.Position = UDim2.new(0, #self.tabs * 82 + 4, 0, 1)
    btn.Text = name
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.TextSize = 14
    btn.Parent = self.tabBar
    addBorder(btn)
    btn.MouseButton1Click:Connect(function()
        self:SelectTab(tab)
    end)
    tab.button = btn

    table.insert(self.tabs, tab)
    return tab
end

function Window:SelectTab(tab)
    for _, t in ipairs(self.tabs) do
        t.frame.Visible = (t == tab)
        if t.button then
            t.button.BackgroundColor3 = (t == tab) and Color3.fromRGB(255, 0, 0) or Color3.fromRGB(0, 0, 0)
        end
    end
    self.currentTab = tab
end

function Window:SetTitle(newTitle)
    self.title = newTitle
    self.titleLabel.Text = newTitle
end

function Window:SetSize(newSize)
    self.main.Size = newSize
end

function Window:AddFooter(text)
    if self.footer then return end
    local footer = Instance.new("Frame")
    footer.Name = rndName()
    footer.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    footer.BackgroundTransparency = 0
    footer.Size = UDim2.new(1, 0, 0, 24)
    footer.Position = UDim2.new(0, 0, 1, -24)
    footer.Parent = self.main
    addBorder(footer)
    local label = Instance.new("TextLabel")
    label.Name = rndName()
    label.BackgroundTransparency = 1
    label.Text = text or ""
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextSize = 12
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.Size = UDim2.new(1, 0, 1, 0)
    label.Parent = footer
    self.footer = footer
    self.footerLabel = label
    self.content.Size = UDim2.new(1, 0, 1, -54)
end

function Window:SetFooterText(text)
    if self.footerLabel then
        self.footerLabel.Text = text
    end
end

function Window:Destroy()
    if self.main then
        self.main:Destroy()
    end
    -- remove from registry (will be implemented later)
end

-- ============================================================
-- Tab class and basic controls
-- ============================================================
local Tab = {}
Tab.__index = Tab

function Tab:CreateButton(text, callback)
    local frame = self.frame
    local y = self._y
    local btn = Instance.new("TextButton")
    btn.Name = rndName()
    btn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    btn.BackgroundTransparency = 0
    btn.Size = UDim2.new(0, 140, 0, 30)
    btn.Position = UDim2.new(0, 6, 0, y)
    btn.Text = text
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.TextSize = 14
    btn.Parent = frame
    addBorder(btn)
    btn.MouseButton1Click:Connect(callback)
    self._y = self._y + 36
    table.insert(self.controls, btn)
    return btn
end

function Tab:CreateToggle(text, default, callback)
    local frame = self.frame
    local y = self._y
    default = default or false

    local label = Instance.new("TextLabel")
    label.Name = rndName()
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextSize = 14
    label.Size = UDim2.new(0, 150, 0, 30)
    label.Position = UDim2.new(0, 6, 0, y)
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame
    table.insert(self.controls, label)

    local onBtn = Instance.new("TextButton")
    onBtn.Name = rndName()
    onBtn.BackgroundColor3 = default and Color3.fromRGB(255, 0, 0) or Color3.fromRGB(0, 0, 0)
    onBtn.BackgroundTransparency = 0
    onBtn.Size = UDim2.new(0, 40, 0, 30)
    onBtn.Position = UDim2.new(0, 160, 0, y)
    onBtn.Text = "ON"
    onBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    onBtn.TextSize = 14
    onBtn.Parent = frame
    addBorder(onBtn)
    table.insert(self.controls, onBtn)

    local offBtn = Instance.new("TextButton")
    offBtn.Name = rndName()
    offBtn.BackgroundColor3 = default and Color3.fromRGB(0, 0, 0) or Color3.fromRGB(255, 0, 0)
    offBtn.BackgroundTransparency = 0
    offBtn.Size = UDim2.new(0, 40, 0, 30)
    offBtn.Position = UDim2.new(0, 202, 0, y)
    offBtn.Text = "OFF"
    offBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    offBtn.TextSize = 14
    offBtn.Parent = frame
    addBorder(offBtn)
    table.insert(self.controls, offBtn)

    local state = default
    local function setState(newState)
        state = newState
        onBtn.BackgroundColor3 = state and Color3.fromRGB(255, 0, 0) or Color3.fromRGB(0, 0, 0)
        offBtn.BackgroundColor3 = state and Color3.fromRGB(0, 0, 0) or Color3.fromRGB(255, 0, 0)
        if callback then callback(state) end
    end

    onBtn.MouseButton1Click:Connect(function()
        if not state then setState(true) end
    end)
    offBtn.MouseButton1Click:Connect(function()
        if state then setState(false) end
    end)

    self._y = self._y + 36
    return { setState = setState, getState = function() return state end }
end

function Tab:CreateSlider(text, min, max, default, callback)
    local frame = self.frame
    local y = self._y
    min = min or 0
    max = max or 100
    default = default or (min + max) / 2
    local value = clamp(default, min, max)

    local label = Instance.new("TextLabel")
    label.Name = rndName()
    label.BackgroundTransparency = 1
    label.Text = text .. ": " .. tostring(math.floor(value))
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextSize = 14
    label.Size = UDim2.new(0, 150, 0, 30)
    label.Position = UDim2.new(0, 6, 0, y)
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame
    table.insert(self.controls, label)

    local track = Instance.new("Frame")
    track.Name = rndName()
    track.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    track.BackgroundTransparency = 0
    track.Size = UDim2.new(0, 160, 0, 10)
    track.Position = UDim2.new(0, 160, 0, y + 10)
    track.Parent = frame
    addBorder(track, 1)
    table.insert(self.controls, track)

    local fill = Instance.new("Frame")
    fill.Name = rndName()
    fill.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
    fill.BackgroundTransparency = 0
    fill.Size = UDim2.new((value - min) / (max - min), 0, 1, 0)
    fill.Position = UDim2.new(0, 0, 0, 0)
    fill.Parent = track
    table.insert(self.controls, fill)

    local thumb = Instance.new("TextButton")
    thumb.Name = rndName()
    thumb.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    thumb.BackgroundTransparency = 0
    thumb.Size = UDim2.new(0, 12, 0, 18)
    thumb.Position = UDim2.new((value - min) / (max - min), -6, 0, -4)
    thumb.Text = ""
    thumb.Parent = track
    addBorder(thumb, 1)
    table.insert(self.controls, thumb)

    local sliderData = {
        value = value,
        min = min,
        max = max,
        track = track,
        fill = fill,
        thumb = thumb,
        label = label,
        callback = callback,
    }

    local function updateSlider(newValue)
        newValue = clamp(newValue, min, max)
        if newValue == sliderData.value then return end
        sliderData.value = newValue
        local ratio = (newValue - min) / (max - min)
        fill.Size = UDim2.new(ratio, 0, 1, 0)
        thumb.Position = UDim2.new(ratio, -6, 0, -4)
        label.Text = text .. ": " .. tostring(math.floor(newValue))
        if callback then callback(newValue) end
    end

    local function getValueFromMouse(mousePos)
        local trackAbsPos = track.AbsolutePosition
        local trackSize = track.AbsoluteSize
        local relativeX = mousePos.X - trackAbsPos.X
        local ratio = clamp(relativeX / trackSize.X, 0, 1)
        return min + ratio * (max - min)
    end

    local dragging = false
    thumb.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            local newVal = getValueFromMouse(input.Position)
            updateSlider(newVal)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local newVal = getValueFromMouse(input.Position)
            updateSlider(newVal)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            local newVal = getValueFromMouse(input.Position)
            updateSlider(newVal)
        end
    end)

    self._y = self._y + 40
    table.insert(self.controls, sliderData)
    return {
        setValue = updateSlider,
        getValue = function() return sliderData.value end
    }
end

function Tab:CreateColorInput(defaultText, callback)
    local frame = self.frame
    local y = self._y

    local label = Instance.new("TextLabel")
    label.Name = rndName()
    label.BackgroundTransparency = 1
    label.Text = "Color (R,G,B):"
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextSize = 14
    label.Size = UDim2.new(0, 150, 0, 30)
    label.Position = UDim2.new(0, 6, 0, y)
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame
    table.insert(self.controls, label)

    local box = Instance.new("TextBox")
    box.Name = rndName()
    box.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    box.BackgroundTransparency = 0
    box.Size = UDim2.new(0, 120, 0, 30)
    box.Position = UDim2.new(0, 160, 0, y)
    box.Text = defaultText or "255,0,0"
    box.TextColor3 = Color3.fromRGB(255, 255, 255)
    box.TextSize = 14
    box.Parent = frame
    addBorder(box)
    table.insert(self.controls, box)

    local function parseAndApply()
        local text = box.Text
        local parts = {}
        for part in string.gmatch(text, "[^,]+") do
            table.insert(parts, tonumber(part))
        end
        if #parts == 3 then
            local r, g, b = parts[1], parts[2], parts[3]
            if r and g and b and r >= 0 and r <= 255 and g >= 0 and g <= 255 and b >= 0 and b <= 255 then
                if callback then callback(r, g, b) end
                return
            end
        end
    end

    box.FocusLost:Connect(function(enterPressed)
        if enterPressed then parseAndApply() end
    end)

    self._y = self._y + 36
    return box
end

function Tab:CreateDropdown(text, options, default, callback)
    local frame = self.frame
    local y = self._y

    local label = Instance.new("TextLabel")
    label.Name = rndName()
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextSize = 14
    label.Size = UDim2.new(0, 150, 0, 30)
    label.Position = UDim2.new(0, 6, 0, y)
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame
    table.insert(self.controls, label)

    local dropdownBtn = Instance.new("TextButton")
    dropdownBtn.Name = rndName()
    dropdownBtn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    dropdownBtn.BackgroundTransparency = 0
    dropdownBtn.Size = UDim2.new(0, 120, 0, 30)
    dropdownBtn.Position = UDim2.new(0, 160, 0, y)
    dropdownBtn.Text = "Select..."
    dropdownBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    dropdownBtn.TextSize = 14
    dropdownBtn.Parent = frame
    addBorder(dropdownBtn)
    table.insert(self.controls, dropdownBtn)

    local dropContainer = Instance.new("Frame")
    dropContainer.Name = rndName()
    dropContainer.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    dropContainer.BackgroundTransparency = 0
    dropContainer.Size = UDim2.new(0, 120, 0, 0)
    dropContainer.Position = UDim2.new(0, 160, 0, y + 30)
    dropContainer.Visible = false
    dropContainer.Parent = frame
    addBorder(dropContainer)
    table.insert(self.controls, dropContainer)

    local selectedIndex = default and 1 or 1
    if default then
        for i, opt in ipairs(options) do
            if opt == default then selectedIndex = i break end
        end
    end
    local selectedValue = options[selectedIndex] or options[1]
    dropdownBtn.Text = selectedValue

    for i, opt in ipairs(options) do
        local btn = Instance.new("TextButton")
        btn.Name = rndName()
        btn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        btn.BackgroundTransparency = 0
        btn.Size = UDim2.new(1, -2, 0, 26)
        btn.Position = UDim2.new(0, 1, 0, (i-1)*26 + 1)
        btn.Text = opt
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        btn.TextSize = 14
        btn.Parent = dropContainer
        addBorder(btn)
        btn.MouseButton1Click:Connect(function()
            selectedValue = opt
            selectedIndex = i
            dropdownBtn.Text = opt
            dropContainer.Visible = false
            if callback then callback(opt, i) end
        end)
    end
    dropContainer.Size = UDim2.new(0, 120, 0, #options * 26 + 2)

    dropdownBtn.MouseButton1Click:Connect(function()
        dropContainer.Visible = not dropContainer.Visible
    end)

    self._y = self._y + 36
    return {
        getValue = function() return selectedValue end,
        getIndex = function() return selectedIndex end,
        setValue = function(val)
            for i, opt in ipairs(options) do
                if opt == val then
                    selectedIndex = i
                    selectedValue = opt
                    dropdownBtn.Text = opt
                    if callback then callback(opt, i) end
                    break
                end
            end
        end
    }
end

function Tab:CreateKeybind(text, defaultKey, callback)
    local frame = self.frame
    local y = self._y

    local label = Instance.new("TextLabel")
    label.Name = rndName()
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextSize = 14
    label.Size = UDim2.new(0, 150, 0, 30)
    label.Position = UDim2.new(0, 6, 0, y)
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame
    table.insert(self.controls, label)

    local bindBtn = Instance.new("TextButton")
    bindBtn.Name = rndName()
    bindBtn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    bindBtn.BackgroundTransparency = 0
    bindBtn.Size = UDim2.new(0, 80, 0, 30)
    bindBtn.Position = UDim2.new(0, 160, 0, y)
    bindBtn.Text = defaultKey or "None"
    bindBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    bindBtn.TextSize = 14
    bindBtn.Parent = frame
    addBorder(bindBtn)
    table.insert(self.controls, bindBtn)

    local currentKey = defaultKey or "None"
    local listening = false

    local function setKey(keyName)
        currentKey = keyName
        bindBtn.Text = keyName
        if callback then callback(keyName) end
    end

    bindBtn.MouseButton1Click:Connect(function()
        if listening then
            listening = false
            bindBtn.Text = currentKey
            return
        end
        listening = true
        bindBtn.Text = "Press a key..."
    end)

    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if listening then
            local key = input.KeyCode
            if key then
                setKey(tostring(key))
                listening = false
            end
        end
    end)

    self._y = self._y + 36
    return {
        getKey = function() return currentKey end,
        setKey = setKey
    }
end

function Tab:CreateLabel(text, fontSize)
    local frame = self.frame
    local y = self._y
    local label = Instance.new("TextLabel")
    label.Name = rndName()
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextSize = fontSize or 14
    label.Size = UDim2.new(1, -12, 0, 24)
    label.Position = UDim2.new(0, 6, 0, y)
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame
    table.insert(self.controls, label)
    self._y = self._y + 28
    return label
end

function Tab:CreateMultiToggle(text, options, defaultIndex, callback)
    local frame = self.frame
    local y = self._y

    local label = Instance.new("TextLabel")
    label.Name = rndName()
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextSize = 14
    label.Size = UDim2.new(0, 150, 0, 30)
    label.Position = UDim2.new(0, 6, 0, y)
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame
    table.insert(self.controls, label)

    local selectedIndex = defaultIndex or 1
    local buttons = {}
    local xOffset = 160
    for i, opt in ipairs(options) do
        local btn = Instance.new("TextButton")
        btn.Name = rndName()
        btn.BackgroundColor3 = (i == selectedIndex) and Color3.fromRGB(255, 0, 0) or Color3.fromRGB(0, 0, 0)
        btn.BackgroundTransparency = 0
        btn.Size = UDim2.new(0, 60, 0, 30)
        btn.Position = UDim2.new(0, xOffset + (i-1)*64, 0, y)
        btn.Text = opt
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        btn.TextSize = 14
        btn.Parent = frame
        addBorder(btn)
        table.insert(self.controls, btn)
        table.insert(buttons, btn)
        btn.MouseButton1Click:Connect(function()
            if selectedIndex == i then return end
            for j, b in ipairs(buttons) do
                b.BackgroundColor3 = (j == i) and Color3.fromRGB(255, 0, 0) or Color3.fromRGB(0, 0, 0)
            end
            selectedIndex = i
            if callback then callback(i, options[i]) end
        end)
    end

    self._y = self._y + 36
    return {
        getIndex = function() return selectedIndex end,
        getValue = function() return options[selectedIndex] end,
        setIndex = function(idx)
            if idx < 1 or idx > #options then return end
            for j, b in ipairs(buttons) do
                b.BackgroundColor3 = (j == idx) and Color3.fromRGB(255, 0, 0) or Color3.fromRGB(0, 0, 0)
            end
            selectedIndex = idx
            if callback then callback(idx, options[idx]) end
        end
    }
end

function Tab:CreateProgressBar(text, max, default)
    local frame = self.frame
    local y = self._y

    local label = Instance.new("TextLabel")
    label.Name = rndName()
    label.BackgroundTransparency = 1
    label.Text = text .. ": 0/" .. tostring(max)
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextSize = 14
    label.Size = UDim2.new(0, 200, 0, 24)
    label.Position = UDim2.new(0, 6, 0, y)
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame
    table.insert(self.controls, label)

    local track = Instance.new("Frame")
    track.Name = rndName()
    track.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    track.BackgroundTransparency = 0
    track.Size = UDim2.new(0, 200, 0, 12)
    track.Position = UDim2.new(0, 6, 0, y + 26)
    track.Parent = frame
    addBorder(track, 1)
    table.insert(self.controls, track)

    local fill = Instance.new("Frame")
    fill.Name = rndName()
    fill.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
    fill.BackgroundTransparency = 0
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.Position = UDim2.new(0, 0, 0, 0)
    fill.Parent = track
    table.insert(self.controls, fill)

    local current = default or 0
    local function setValue(val)
        current = clamp(val, 0, max)
        fill.Size = UDim2.new(current/max, 0, 1, 0)
        label.Text = text .. ": " .. tostring(math.floor(current)) .. "/" .. tostring(max)
    end
    setValue(current)

    self._y = self._y + 44
    return {
        setValue = setValue,
        getValue = function() return current end
    }
end

-- Global window registry
local _windows = {}

-- Override Window.new to auto-register
local _origWindowNew = Window.new
Window.new = function(title, size)
    local win = _origWindowNew(title, size)
    table.insert(_windows, win)
    return win
end

-- Extend Window.Destroy to remove from registry
local _origDestroy = Window.Destroy
Window.Destroy = function(self)
    if self.main then
        self.main:Destroy()
    end
    for i, w in ipairs(_windows) do
        if w == self then
            table.remove(_windows, i)
            break
        end
    end
end

-- ============================================================
-- Additional Tab methods
-- ============================================================

-- Color Picker (grid of swatches)
function Tab:CreateColorPicker(text, defaultColor, callback)
    local frame = self.frame
    local y = self._y

    local label = Instance.new("TextLabel")
    label.Name = rndName()
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextSize = 14
    label.Size = UDim2.new(0, 150, 0, 30)
    label.Position = UDim2.new(0, 6, 0, y)
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame
    table.insert(self.controls, label)

    local preview = Instance.new("Frame")
    preview.Name = rndName()
    preview.BackgroundColor3 = defaultColor or Color3.fromRGB(255, 0, 0)
    preview.BackgroundTransparency = 0
    preview.Size = UDim2.new(0, 30, 0, 30)
    preview.Position = UDim2.new(0, 160, 0, y)
    preview.Parent = frame
    addBorder(preview)
    table.insert(self.controls, preview)

    local gridFrame = Instance.new("Frame")
    gridFrame.Name = rndName()
    gridFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    gridFrame.BackgroundTransparency = 0
    gridFrame.Size = UDim2.new(0, 200, 0, 200)
    gridFrame.Position = UDim2.new(0, 160, 0, y + 36)
    gridFrame.Visible = false
    gridFrame.Parent = frame
    addBorder(gridFrame)
    table.insert(self.controls, gridFrame)

    -- Generate colors
    local colors = {}
    for h = 0, 7 do
        for s = 0, 7 do
            table.insert(colors, Color3.fromHSV(h/8, s/8, 1))
        end
    end
    local extraColors = {
        Color3.fromRGB(255,0,0), Color3.fromRGB(0,255,0), Color3.fromRGB(0,0,255),
        Color3.fromRGB(255,255,0), Color3.fromRGB(255,0,255), Color3.fromRGB(0,255,255),
        Color3.fromRGB(255,255,255), Color3.fromRGB(0,0,0)
    }
    for _, c in ipairs(extraColors) do table.insert(colors, c) end

    local swatchSize = 20
    for i, color in ipairs(colors) do
        local swatch = Instance.new("TextButton")
        swatch.Name = rndName()
        swatch.BackgroundColor3 = color
        swatch.BackgroundTransparency = 0
        swatch.Size = UDim2.new(0, swatchSize, 0, swatchSize)
        local row = math.floor((i-1) / 8)
        local col = (i-1) % 8
        swatch.Position = UDim2.new(0, col * (swatchSize + 2) + 2, 0, row * (swatchSize + 2) + 2)
        swatch.Text = ""
        swatch.Parent = gridFrame
        addBorder(swatch, 1)
        swatch.MouseButton1Click:Connect(function()
            preview.BackgroundColor3 = color
            gridFrame.Visible = false
            if callback then callback(color) end
        end)
    end

    preview.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            gridFrame.Visible = not gridFrame.Visible
        end
    end)

    self._y = self._y + 240
    return {
        getColor = function() return preview.BackgroundColor3 end,
        setColor = function(c)
            preview.BackgroundColor3 = c
            if callback then callback(c) end
        end
    }
end

-- Group (collapsible section)
function Tab:CreateGroup(text, defaultOpen)
    local frame = self.frame
    local y = self._y

    local header = Instance.new("TextButton")
    header.Name = rndName()
    header.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    header.BackgroundTransparency = 0
    header.Size = UDim2.new(1, -12, 0, 30)
    header.Position = UDim2.new(0, 6, 0, y)
    header.Text = text .. " [▼]"
    header.TextColor3 = Color3.fromRGB(255, 255, 255)
    header.TextSize = 14
    header.TextXAlignment = Enum.TextXAlignment.Left
    header.Parent = frame
    addBorder(header)
    table.insert(self.controls, header)

    local open = defaultOpen or true
    local groupFrame = Instance.new("Frame")
    groupFrame.Name = rndName()
    groupFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    groupFrame.BackgroundTransparency = 0
    groupFrame.Size = UDim2.new(1, -12, 0, 0) -- will be sized dynamically
    groupFrame.Position = UDim2.new(0, 6, 0, y + 34)
    groupFrame.Parent = frame
    addBorder(groupFrame)
    table.insert(self.controls, groupFrame)

    header.MouseButton1Click:Connect(function()
        open = not open
        groupFrame.Visible = open
        header.Text = text .. (open and " [▼]" or " [▶]")
    end)
    groupFrame.Visible = open
    self._y = self._y + 34 + (open and 4 or 0)

    return {
        frame = groupFrame,
        setOpen = function(state)
            open = state
            groupFrame.Visible = open
            header.Text = text .. (open and " [▼]" or " [▶]")
        end,
        isOpen = function() return open end
    }
end

-- Separator
function Tab:CreateSeparator()
    local frame = self.frame
    local y = self._y
    local line = Instance.new("Frame")
    line.Name = rndName()
    line.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
    line.BackgroundTransparency = 0
    line.Size = UDim2.new(1, -12, 0, 2)
    line.Position = UDim2.new(0, 6, 0, y)
    line.Parent = frame
    table.insert(self.controls, line)
    self._y = self._y + 10
    return line
end

-- Paragraph (multi‑line text)
function Tab:CreateParagraph(text, fontSize)
    local frame = self.frame
    local y = self._y
    local label = Instance.new("TextLabel")
    label.Name = rndName()
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextSize = fontSize or 14
    label.Size = UDim2.new(1, -12, 0, 0)
    label.Position = UDim2.new(0, 6, 0, y)
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextWrapped = true
    label.Parent = frame
    local width = self.window.main.Size.X.Offset - 24
    local charWidth = 7
    local charsPerLine = math.floor(width / charWidth)
    local lines = math.max(1, math.ceil(#text / charsPerLine))
    local height = lines * 18 + 4
    label.Size = UDim2.new(1, -12, 0, height)
    table.insert(self.controls, label)
    self._y = self._y + height + 8
    return label
end

-- Make tab scrollable (converts frame to ScrollingFrame)
function Tab:MakeScrollable()
    if self._scrollable then return end
    local frame = self.frame
    local scrolling = Instance.new("ScrollingFrame")
    scrolling.Name = rndName()
    scrolling.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    scrolling.BackgroundTransparency = 0
    scrolling.Size = UDim2.new(1, 0, 1, 0)
    scrolling.Position = UDim2.new(0, 0, 0, 0)
    scrolling.CanvasSize = UDim2.new(0, 0, 0, 0)
    scrolling.ScrollBarThickness = 8
    scrolling.ScrollBarImageColor3 = Color3.fromRGB(255, 0, 0)
    scrolling.Parent = frame
    local children = frame:GetChildren()
    for _, child in ipairs(children) do
        if child ~= scrolling then
            child.Parent = scrolling
        end
    end
    self.frame = scrolling
    self._scrollable = true
    return self
end

-- Update canvas size for scrollable tabs
function Tab:UpdateCanvas()
    if not self._scrollable then return end
    local scrolling = self.frame
    local maxY = 0
    for _, child in ipairs(scrolling:GetChildren()) do
        if child:IsA("Frame") or child:IsA("TextButton") or child:IsA("TextLabel") or child:IsA("TextBox") then
            local pos = child.Position
            local size = child.Size
            local y = pos.Y.Offset + size.Y.Offset
            if y > maxY then maxY = y end
        end
    end
    scrolling.CanvasSize = UDim2.new(0, 0, 0, maxY + 20)
end

-- ============================================================
-- Window: Closable Tab
-- ============================================================
function Window:CreateClosableTab(name, onClose)
    local tab = self:CreateTab(name)
    local btn = tab.button
    local closeBtn = Instance.new("TextButton")
    closeBtn.Name = rndName()
    closeBtn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    closeBtn.BackgroundTransparency = 0
    closeBtn.Size = UDim2.new(0, 16, 0, 16)
    closeBtn.Position = UDim2.new(1, -18, 0, 5)
    closeBtn.Text = "X"
    closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeBtn.TextSize = 10
    closeBtn.Parent = btn
    addBorder(closeBtn)
    closeBtn.MouseButton1Click:Connect(function()
        tab.frame:Destroy()
        btn:Destroy()
        for i, t in ipairs(self.tabs) do
            if t == tab then
                table.remove(self.tabs, i)
                break
            end
        end
        if onClose then onClose() end
        if #self.tabs == 0 then
            self.tabBar.Visible = false
        end
    end)
    return tab
end

-- ============================================================
-- Window: Minimize Button
-- ============================================================
function Window:AddMinimizeButton()
    if self.minimizeBtn then return end
    local btn = Instance.new("TextButton")
    btn.Name = rndName()
    btn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    btn.BackgroundTransparency = 0
    btn.Size = UDim2.new(0, 24, 1, 0)
    btn.Position = UDim2.new(1, -48, 0, 0)
    btn.Text = "_"
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.TextSize = 16
    btn.Parent = self.topbar
    addBorder(btn)
    btn.MouseButton1Click:Connect(function()
        self.content.Visible = not self.content.Visible
        local currentSize = self.main.Size
        if self.content.Visible then
            if self._savedSize then
                self.main.Size = self._savedSize
            end
        else
            self._savedSize = currentSize
            self.main.Size = UDim2.new(currentSize.X.Scale, currentSize.X.Offset, 0, 30)
        end
    end)
    self.minimizeBtn = btn
end

-- ============================================================
-- RetroUI API (partial)
-- ============================================================
local RetroUI = {
    CreateWindow = function(title, size) return Window.new(title, size) end,
    GetWindows = function() return _windows end,
    CloseAll = function()
        for _, win in ipairs(_windows) do
            win:Destroy()
        end
        _windows = {}
    end,
    FindWindow = function(title)
        for _, win in ipairs(_windows) do
            if win.title == title then
                return win
            end
        end
        return nil
    end,
    HideAll = function()
        for _, win in ipairs(_windows) do
            win.main.Visible = false
        end
    end,
    ShowAll = function()
        for _, win in ipairs(_windows) do
            win.main.Visible = true
        end
    end,
}

local HttpService = getService("HttpService")

-- Notification System (toast messages)

local NotificationContainer = nil

local function getNotificationContainer()
    if NotificationContainer and NotificationContainer.Parent then
        return NotificationContainer
    end
    local container = Instance.new("Frame")
    container.Name = rndName()
    container.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    container.BackgroundTransparency = 1
    container.Size = UDim2.new(0, 300, 0, 0)
    container.Position = UDim2.new(1, -310, 0, 10)
    container.Parent = GUI_CONTAINER
    container.Visible = true
    NotificationContainer = container
    return container
end

function RetroUI.Notify(title, message, duration)
    duration = duration or 3
    local container = getNotificationContainer()

    local notif = Instance.new("Frame")
    notif.Name = rndName()
    notif.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    notif.BackgroundTransparency = 0
    notif.Size = UDim2.new(1, -2, 0, 50)
    notif.Position = UDim2.new(0, 1, 0, 0)
    notif.Parent = container
    addBorder(notif)

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = rndName()
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = title or "Notification"
    titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    titleLabel.TextSize = 14
    titleLabel.Size = UDim2.new(1, -8, 0, 20)
    titleLabel.Position = UDim2.new(0, 4, 0, 2)
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.Parent = notif

    local msgLabel = Instance.new("TextLabel")
    msgLabel.Name = rndName()
    msgLabel.BackgroundTransparency = 1
    msgLabel.Text = message or ""
    msgLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    msgLabel.TextSize = 12
    msgLabel.Size = UDim2.new(1, -8, 0, 20)
    msgLabel.Position = UDim2.new(0, 4, 0, 24)
    msgLabel.TextXAlignment = Enum.TextXAlignment.Left
    msgLabel.Parent = notif

    local closeBtn = Instance.new("TextButton")
    closeBtn.Name = rndName()
    closeBtn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    closeBtn.BackgroundTransparency = 0
    closeBtn.Size = UDim2.new(0, 16, 0, 16)
    closeBtn.Position = UDim2.new(1, -18, 0, 2)
    closeBtn.Text = "X"
    closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeBtn.TextSize = 12
    closeBtn.Parent = notif
    addBorder(closeBtn)
    closeBtn.MouseButton1Click:Connect(function()
        notif:Destroy()
        RetroUI._rearrangeNotifications()
    end)

    local children = container:GetChildren()
    local maxY = 0
    for _, child in ipairs(children) do
        if child ~= notif and child:IsA("Frame") then
            local pos = child.Position
            local size = child.Size
            local bottom = pos.Y.Offset + size.Y.Offset
            if bottom > maxY then maxY = bottom end
        end
    end
    notif.Position = UDim2.new(0, 1, 0, maxY + 4)
    container.Size = UDim2.new(0, 300, 0, maxY + notif.Size.Y.Offset + 4)

    task.delay(duration, function()
        if notif and notif.Parent then
            notif:Destroy()
            RetroUI._rearrangeNotifications()
        end
    end)

    return notif
end

function RetroUI._rearrangeNotifications()
    local container = getNotificationContainer()
    local children = container:GetChildren()
    local yOffset = 4
    for _, child in ipairs(children) do
        if child:IsA("Frame") then
            child.Position = UDim2.new(0, 1, 0, yOffset)
            yOffset = yOffset + child.Size.Y.Offset + 4
        end
    end
    container.Size = UDim2.new(0, 300, 0, yOffset)
end

-- ============================================================
-- Dialog System (popups with buttons)
-- ============================================================

function RetroUI.Dialog(title, message, buttons)
    local dialog = Instance.new("Frame")
    dialog.Name = rndName()
    dialog.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    dialog.BackgroundTransparency = 0
    dialog.Size = UDim2.new(0, 300, 0, 150)
    dialog.Position = UDim2.new(0.5, -150, 0.5, -75)
    dialog.Parent = GUI_CONTAINER
    addBorder(dialog)

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = rndName()
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = title or "Dialog"
    titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    titleLabel.TextSize = 16
    titleLabel.Size = UDim2.new(1, 0, 0, 30)
    titleLabel.Position = UDim2.new(0, 0, 0, 6)
    titleLabel.TextXAlignment = Enum.TextXAlignment.Center
    titleLabel.Parent = dialog

    local msgLabel = Instance.new("TextLabel")
    msgLabel.Name = rndName()
    msgLabel.BackgroundTransparency = 1
    msgLabel.Text = message or ""
    msgLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    msgLabel.TextSize = 14
    msgLabel.Size = UDim2.new(1, -12, 0, 60)
    msgLabel.Position = UDim2.new(0, 6, 0, 36)
    msgLabel.TextXAlignment = Enum.TextXAlignment.Center
    msgLabel.TextWrapped = true
    msgLabel.Parent = dialog

    local btnY = 110
    local totalWidth = #buttons * 80
    local startX = (300 - totalWidth) / 2
    for i, btnData in ipairs(buttons) do
        local btn = Instance.new("TextButton")
        btn.Name = rndName()
        btn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        btn.BackgroundTransparency = 0
        btn.Size = UDim2.new(0, 70, 0, 30)
        btn.Position = UDim2.new(0, startX + (i-1)*80, 0, btnY)
        btn.Text = btnData.text or "Button"
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        btn.TextSize = 14
        btn.Parent = dialog
        addBorder(btn)
        btn.MouseButton1Click:Connect(function()
            if btnData.callback then btnData.callback() end
            dialog:Destroy()
        end)
    end

    if #buttons == 0 then
        local btn = Instance.new("TextButton")
        btn.Name = rndName()
        btn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        btn.BackgroundTransparency = 0
        btn.Size = UDim2.new(0, 70, 0, 30)
        btn.Position = UDim2.new(0.5, -35, 0, btnY)
        btn.Text = "OK"
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        btn.TextSize = 14
        btn.Parent = dialog
        addBorder(btn)
        btn.MouseButton1Click:Connect(function()
            dialog:Destroy()
        end)
    end

    local dragging = false
    local dragOffset = Vector2.new()
    titleLabel.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragOffset = input.Position - dialog.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local pos = input.Position - dragOffset
            dialog.Position = UDim2.new(0, pos.X, 0, pos.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)

    return dialog
end

-- ============================================================
-- Input Dialog (popup with text box)
-- ============================================================

function RetroUI.InputDialog(title, message, defaultText, callback)
    local dialog = Instance.new("Frame")
    dialog.Name = rndName()
    dialog.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    dialog.BackgroundTransparency = 0
    dialog.Size = UDim2.new(0, 300, 0, 160)
    dialog.Position = UDim2.new(0.5, -150, 0.5, -80)
    dialog.Parent = GUI_CONTAINER
    addBorder(dialog)

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = rndName()
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text = title or "Input"
    titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    titleLabel.TextSize = 16
    titleLabel.Size = UDim2.new(1, 0, 0, 30)
    titleLabel.Position = UDim2.new(0, 0, 0, 6)
    titleLabel.TextXAlignment = Enum.TextXAlignment.Center
    titleLabel.Parent = dialog

    local msgLabel = Instance.new("TextLabel")
    msgLabel.Name = rndName()
    msgLabel.BackgroundTransparency = 1
    msgLabel.Text = message or ""
    msgLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    msgLabel.TextSize = 14
    msgLabel.Size = UDim2.new(1, -12, 0, 24)
    msgLabel.Position = UDim2.new(0, 6, 0, 36)
    msgLabel.TextXAlignment = Enum.TextXAlignment.Left
    msgLabel.Parent = dialog

    local box = Instance.new("TextBox")
    box.Name = rndName()
    box.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    box.BackgroundTransparency = 0
    box.Size = UDim2.new(1, -12, 0, 30)
    box.Position = UDim2.new(0, 6, 0, 64)
    box.Text = defaultText or ""
    box.TextColor3 = Color3.fromRGB(255, 255, 255)
    box.TextSize = 14
    box.Parent = dialog
    addBorder(box)

    local okBtn = Instance.new("TextButton")
    okBtn.Name = rndName()
    okBtn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    okBtn.BackgroundTransparency = 0
    okBtn.Size = UDim2.new(0, 70, 0, 30)
    okBtn.Position = UDim2.new(0.5, -75, 0, 120)
    okBtn.Text = "OK"
    okBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    okBtn.TextSize = 14
    okBtn.Parent = dialog
    addBorder(okBtn)
    okBtn.MouseButton1Click:Connect(function()
        if callback then callback(box.Text) end
        dialog:Destroy()
    end)

    local cancelBtn = Instance.new("TextButton")
    cancelBtn.Name = rndName()
    cancelBtn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    cancelBtn.BackgroundTransparency = 0
    cancelBtn.Size = UDim2.new(0, 70, 0, 30)
    cancelBtn.Position = UDim2.new(0.5, 5, 0, 120)
    cancelBtn.Text = "Cancel"
    cancelBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    cancelBtn.TextSize = 14
    cancelBtn.Parent = dialog
    addBorder(cancelBtn)
    cancelBtn.MouseButton1Click:Connect(function()
        dialog:Destroy()
    end)

    local dragging = false
    local dragOffset = Vector2.new()
    titleLabel.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragOffset = input.Position - dialog.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local pos = input.Position - dragOffset
            dialog.Position = UDim2.new(0, pos.X, 0, pos.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)

    return dialog
end

-- ============================================================
-- Settings Save/Load (using JSON if available)
-- ============================================================

function RetroUI.SaveSettings(filename, data)
    if writefile then
        local success, err = pcall(function()
            writefile(filename, HttpService:JSONEncode(data))
        end)
        if success then
            RetroUI.Notify("Settings Saved", "Saved to " .. filename)
            return true
        else
            RetroUI.Notify("Save Failed", tostring(err))
            return false
        end
    else
        RetroUI.Notify("Save Failed", "writefile not available")
        return false
    end
end

function RetroUI.LoadSettings(filename)
    if readfile then
        local success, data = pcall(function()
            local content = readfile(filename)
            return HttpService:JSONDecode(content)
        end)
        if success then
            RetroUI.Notify("Settings Loaded", "Loaded from " .. filename)
            return data
        else
            RetroUI.Notify("Load Failed", tostring(data))
            return nil
        end
    else
        RetroUI.Notify("Load Failed", "readfile not available")
        return nil
    end
end

RetroUI.Notify = RetroUI.Notify
RetroUI.Dialog = RetroUI.Dialog
RetroUI.InputDialog = RetroUI.InputDialog
RetroUI.SaveSettings = RetroUI.SaveSettings
RetroUI.LoadSettings = RetroUI.LoadSettings

-- Advanced Color Picker (HSV sliders)
function Tab:CreateColorPickerAdvanced(text, defaultColor, callback)
    local frame = self.frame
    local y = self._y

    local label = Instance.new("TextLabel")
    label.Name = rndName()
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextSize = 14
    label.Size = UDim2.new(0, 150, 0, 30)
    label.Position = UDim2.new(0, 6, 0, y)
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame
    table.insert(self.controls, label)

    local preview = Instance.new("Frame")
    preview.Name = rndName()
    preview.BackgroundColor3 = defaultColor or Color3.fromRGB(255, 0, 0)
    preview.BackgroundTransparency = 0
    preview.Size = UDim2.new(0, 30, 0, 30)
    preview.Position = UDim2.new(0, 160, 0, y)
    preview.Parent = frame
    addBorder(preview)
    table.insert(self.controls, preview)

    local pickerFrame = Instance.new("Frame")
    pickerFrame.Name = rndName()
    pickerFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    pickerFrame.BackgroundTransparency = 0
    pickerFrame.Size = UDim2.new(0, 220, 0, 120)
    pickerFrame.Position = UDim2.new(0, 160, 0, y + 36)
    pickerFrame.Visible = false
    pickerFrame.Parent = frame
    addBorder(pickerFrame)
    table.insert(self.controls, pickerFrame)

    local h, s, v = preview.BackgroundColor3:ToHSV()

    local function updateColor()
        local newColor = Color3.fromHSV(h, s, v)
        preview.BackgroundColor3 = newColor
        if callback then callback(newColor) end
    end

    local function makeSlider(labelText, yPos, getter, setter)
        local lbl = Instance.new("TextLabel")
        lbl.Name = rndName()
        lbl.BackgroundTransparency = 1
        lbl.Text = labelText
        lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
        lbl.TextSize = 12
        lbl.Size = UDim2.new(0, 30, 0, 20)
        lbl.Position = UDim2.new(0, 4, 0, yPos)
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = pickerFrame
        table.insert(self.controls, lbl)

        local track = Instance.new("Frame")
        track.Name = rndName()
        track.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
        track.BackgroundTransparency = 0
        track.Size = UDim2.new(0, 160, 0, 10)
        track.Position = UDim2.new(0, 40, 0, yPos + 4)
        track.Parent = pickerFrame
        addBorder(track, 1)
        table.insert(self.controls, track)

        local fill = Instance.new("Frame")
        fill.Name = rndName()
        fill.BackgroundColor3 = Color3.fromHSV(h, s, v)
        fill.BackgroundTransparency = 0
        fill.Size = UDim2.new(getter(), 0, 1, 0)
        fill.Position = UDim2.new(0, 0, 0, 0)
        fill.Parent = track
        table.insert(self.controls, fill)

        local thumb = Instance.new("TextButton")
        thumb.Name = rndName()
        thumb.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        thumb.BackgroundTransparency = 0
        thumb.Size = UDim2.new(0, 12, 0, 18)
        thumb.Position = UDim2.new(getter(), -6, 0, -4)
        thumb.Text = ""
        thumb.Parent = track
        addBorder(thumb, 1)
        table.insert(self.controls, thumb)

        local dragging = false
        local function updateThumb(val)
            setter(val)
            fill.Size = UDim2.new(val, 0, 1, 0)
            thumb.Position = UDim2.new(val, -6, 0, -4)
            updateColor()
        end

        local function getMouseVal(mousePos)
            local absPos = track.AbsolutePosition
            local size = track.AbsoluteSize
            return clamp((mousePos.X - absPos.X) / size.X, 0, 1)
        end

        thumb.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true
                updateThumb(getMouseVal(input.Position))
            end
        end)
        UserInputService.InputChanged:Connect(function(input)
            if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                updateThumb(getMouseVal(input.Position))
            end
        end)
        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = false
            end
        end)
        track.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                updateThumb(getMouseVal(input.Position))
            end
        end)

        return { fill = fill, thumb = thumb, update = updateThumb }
    end

    local hueSlider = makeSlider("Hue", 4,
        function() return h end,
        function(val) h = val end
    )
    local satSlider = makeSlider("Sat", 34,
        function() return s end,
        function(val) s = val end
    )
    local valSlider = makeSlider("Val", 64,
        function() return v end,
        function(val) v = val end
    )

    preview.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            pickerFrame.Visible = not pickerFrame.Visible
        end
    end)

    self._y = self._y + 160
    return {
        getColor = function() return preview.BackgroundColor3 end,
        setColor = function(c)
            preview.BackgroundColor3 = c
            h, s, v = c:ToHSV()
            hueSlider.update(h)
            satSlider.update(s)
            valSlider.update(v)
        end
    }
end

-- ============================================================
-- List View
-- ============================================================
function Tab:CreateList(text, items, defaultIndex, callback)
    local frame = self.frame
    local y = self._y

    local label = Instance.new("TextLabel")
    label.Name = rndName()
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextSize = 14
    label.Size = UDim2.new(0, 150, 0, 30)
    label.Position = UDim2.new(0, 6, 0, y)
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame
    table.insert(self.controls, label)

    local listFrame = Instance.new("ScrollingFrame")
    listFrame.Name = rndName()
    listFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    listFrame.BackgroundTransparency = 0
    listFrame.Size = UDim2.new(0, 200, 0, 120)
    listFrame.Position = UDim2.new(0, 160, 0, y)
    listFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    listFrame.ScrollBarThickness = 6
    listFrame.ScrollBarImageColor3 = Color3.fromRGB(255, 0, 0)
    listFrame.Parent = frame
    addBorder(listFrame)
    table.insert(self.controls, listFrame)

    local buttons = {}
    local selectedIndex = defaultIndex or 1
    if selectedIndex < 1 then selectedIndex = 1 end
    if selectedIndex > #items then selectedIndex = #items end

    local function updateSelection(index)
        selectedIndex = index
        for i, btn in ipairs(buttons) do
            btn.BackgroundColor3 = (i == index) and Color3.fromRGB(255, 0, 0) or Color3.fromRGB(0, 0, 0)
        end
        if callback then callback(items[index], index) end
    end

    local yOffset = 4
    for i, item in ipairs(items) do
        local itemText = type(item) == "table" and item.text or tostring(item)
        local btn = Instance.new("TextButton")
        btn.Name = rndName()
        btn.BackgroundColor3 = (i == selectedIndex) and Color3.fromRGB(255, 0, 0) or Color3.fromRGB(0, 0, 0)
        btn.BackgroundTransparency = 0
        btn.Size = UDim2.new(1, -4, 0, 26)
        btn.Position = UDim2.new(0, 2, 0, yOffset)
        btn.Text = itemText
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        btn.TextSize = 14
        btn.TextXAlignment = Enum.TextXAlignment.Left
        btn.Parent = listFrame
        addBorder(btn)
        btn.MouseButton1Click:Connect(function()
            updateSelection(i)
        end)
        table.insert(buttons, btn)
        yOffset = yOffset + 28
    end
    listFrame.CanvasSize = UDim2.new(0, 0, 0, yOffset + 4)

    self._y = self._y + 130
    return {
        getSelected = function() return items[selectedIndex], selectedIndex end,
        setSelected = function(idx)
            if idx >= 1 and idx <= #items then updateSelection(idx) end
        end,
        addItem = function(itemText)
            table.insert(items, itemText)
            -- Rebuild would be needed; we keep it simple, user can recreate
        end
    }
end

-- ============================================================
-- Tree View (simplified)
-- ============================================================
function Tab:CreateTree(text, treeData, callback)
    local frame = self.frame
    local y = self._y

    local label = Instance.new("TextLabel")
    label.Name = rndName()
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextSize = 14
    label.Size = UDim2.new(0, 150, 0, 30)
    label.Position = UDim2.new(0, 6, 0, y)
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame
    table.insert(self.controls, label)

    local treeFrame = Instance.new("ScrollingFrame")
    treeFrame.Name = rndName()
    treeFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    treeFrame.BackgroundTransparency = 0
    treeFrame.Size = UDim2.new(0, 250, 0, 150)
    treeFrame.Position = UDim2.new(0, 160, 0, y)
    treeFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    treeFrame.ScrollBarThickness = 6
    treeFrame.ScrollBarImageColor3 = Color3.fromRGB(255, 0, 0)
    treeFrame.Parent = frame
    addBorder(treeFrame)
    table.insert(self.controls, treeFrame)

    local yOffset = 4
    local function buildTree(parentFrame, data, depth, path)
        for _, nodeData in ipairs(data) do
            local nodeText = nodeData.text or "Node"
            local children = nodeData.children or {}
            local isOpen = false

            local nodeBtn = Instance.new("TextButton")
            nodeBtn.Name = rndName()
            nodeBtn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
            nodeBtn.BackgroundTransparency = 0
            nodeBtn.Size = UDim2.new(1, -4, 0, 26)
            nodeBtn.Position = UDim2.new(0, depth * 16 + 2, 0, yOffset)
            nodeBtn.Text = (children and #children > 0 and (isOpen and "▼ " or "▶ ")) or "  " .. nodeText
            nodeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
            nodeBtn.TextSize = 14
            nodeBtn.TextXAlignment = Enum.TextXAlignment.Left
            nodeBtn.Parent = parentFrame
            addBorder(nodeBtn)
            table.insert(self.controls, nodeBtn)

            local nodePath = table.clone(path)
            table.insert(nodePath, nodeText)

            nodeBtn.MouseButton1Click:Connect(function()
                if children and #children > 0 then
                    isOpen = not isOpen
                    nodeBtn.Text = (isOpen and "▼ " or "▶ ") .. nodeText
                end
                if callback then callback(nodeData, nodePath) end
            end)

            yOffset = yOffset + 28
            if children and #children > 0 then
                -- We could recursively build children here but we skip for simplicity
            end
        end
    end

    buildTree(treeFrame, treeData, 0, {})
    treeFrame.CanvasSize = UDim2.new(0, 0, 0, yOffset + 4)

    self._y = self._y + 160
    return {}
end

-- ============================================================
-- Timeline (simple)
-- ============================================================
function Tab:CreateTimeline(text, duration, callback)
    local frame = self.frame
    local y = self._y

    local label = Instance.new("TextLabel")
    label.Name = rndName()
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextSize = 14
    label.Size = UDim2.new(0, 150, 0, 30)
    label.Position = UDim2.new(0, 6, 0, y)
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame
    table.insert(self.controls, label)

    local track = Instance.new("Frame")
    track.Name = rndName()
    track.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    track.BackgroundTransparency = 0
    track.Size = UDim2.new(0, 200, 0, 20)
    track.Position = UDim2.new(0, 160, 0, y + 5)
    track.Parent = frame
    addBorder(track, 1)
    table.insert(self.controls, track)

    local marker = Instance.new("TextButton")
    marker.Name = rndName()
    marker.BackgroundColor3 = Color3.fromRGB(255, 0, 0)
    marker.BackgroundTransparency = 0
    marker.Size = UDim2.new(0, 6, 0, 24)
    marker.Position = UDim2.new(0, 0, 0, -2)
    marker.Text = ""
    marker.Parent = track
    addBorder(marker, 1)
    table.insert(self.controls, marker)

    local currentPos = 0
    local function updateMarker(pos)
        currentPos = clamp(pos, 0, 1)
        marker.Position = UDim2.new(currentPos, -3, 0, -2)
        if callback then callback(currentPos * duration) end
    end

    local dragging = false
    marker.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            local absPos = track.AbsolutePosition
            local size = track.AbsoluteSize
            local relX = input.Position.X - absPos.X
            updateMarker(relX / size.X)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local absPos = track.AbsolutePosition
            local size = track.AbsoluteSize
            local relX = input.Position.X - absPos.X
            updateMarker(relX / size.X)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)

    self._y = self._y + 40
    return {
        setPosition = function(seconds)
            updateMarker(seconds / duration)
        end,
        getPosition = function() return currentPos * duration end
    }
end

-- ============================================================
-- File Picker (simple text box with browse button)
-- ============================================================
function Tab:CreateFilePicker(text, defaultPath, callback)
    local frame = self.frame
    local y = self._y

    local label = Instance.new("TextLabel")
    label.Name = rndName()
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextSize = 14
    label.Size = UDim2.new(0, 150, 0, 30)
    label.Position = UDim2.new(0, 6, 0, y)
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame
    table.insert(self.controls, label)

    local box = Instance.new("TextBox")
    box.Name = rndName()
    box.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    box.BackgroundTransparency = 0
    box.Size = UDim2.new(0, 160, 0, 30)
    box.Position = UDim2.new(0, 160, 0, y)
    box.Text = defaultPath or ""
    box.TextColor3 = Color3.fromRGB(255, 255, 255)
    box.TextSize = 14
    box.Parent = frame
    addBorder(box)
    table.insert(self.controls, box)

    local browseBtn = Instance.new("TextButton")
    browseBtn.Name = rndName()
    browseBtn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    browseBtn.BackgroundTransparency = 0
    browseBtn.Size = UDim2.new(0, 50, 0, 30)
    browseBtn.Position = UDim2.new(0, 324, 0, y)
    browseBtn.Text = "Browse"
    browseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    browseBtn.TextSize = 14
    browseBtn.Parent = frame
    addBorder(browseBtn)
    table.insert(self.controls, browseBtn)

    browseBtn.MouseButton1Click:Connect(function()
        RetroUI.InputDialog("File Path", "Enter a file path:", box.Text, function(input)
            box.Text = input
            if callback then callback(input) end
        end)
    end)

    box.FocusLost:Connect(function(enterPressed)
        if enterPressed and callback then callback(box.Text) end
    end)

    self._y = self._y + 36
    return box
end

-- ============================================================
-- Global Hotkey Manager
-- ============================================================
local HotkeyManager = {}
local hotkeys = {}

function HotkeyManager.Register(keyName, callback, description)
    if not keyName or type(keyName) ~= "string" then return end
    hotkeys[keyName] = { callback = callback, description = description or "" }
end

function HotkeyManager.Unregister(keyName)
    hotkeys[keyName] = nil
end

-- Global listener
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    local key = input.KeyCode
    if key then
        local keyName = tostring(key)
        local hk = hotkeys[keyName]
        if hk and hk.callback then
            hk.callback()
        end
    end
end)

-- Tab method: create a global keybind
function Tab:CreateGlobalKeybind(text, defaultKey, callback, description)
    local keybindObj = self:CreateKeybind(text, defaultKey, function(keyName)
        if keybindObj._registeredKey then
            HotkeyManager.Unregister(keybindObj._registeredKey)
        end
        if keyName and keyName ~= "None" then
            HotkeyManager.Register(keyName, function()
                if callback then callback() end
            end, description or text)
            keybindObj._registeredKey = keyName
        end
    end)
    if defaultKey and defaultKey ~= "None" then
        HotkeyManager.Register(defaultKey, function()
            if callback then callback() end
        end, description or text)
        keybindObj._registeredKey = defaultKey
    end
    return keybindObj
end

-- ============================================================
-- Global border color setter
-- ============================================================
function RetroUI.SetBorderColor(color)
    _globalBorderColor = color
    -- override addBorder to use new color
    local _origAddBorder = addBorder
    addBorder = function(obj, thickness)
        thickness = thickness or 1
        local stroke = Instance.new("UIStroke")
        stroke.Name = rndName()
        stroke.Thickness = thickness
        stroke.Color = _globalBorderColor
        stroke.Parent = obj
        return stroke
    end
end

-- Add FindWindows method (pattern search)
function RetroUI.FindWindows(pattern)
    local result = {}
    for _, win in ipairs(_windows) do
        if string.find(win.title, pattern) then
            table.insert(result, win)
        end
    end
    return result
end

RetroUI.HotkeyManager = HotkeyManager
RetroUI.SetBorderColor = RetroUI.SetBorderColor
RetroUI.FindWindows = RetroUI.FindWindows

return RetroUI
