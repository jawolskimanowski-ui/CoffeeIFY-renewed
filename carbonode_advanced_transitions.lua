--[[
  Carbonode  –  Lightweight dark-blue UI Library
  Style matches the diamond loading / dark navy panels from the provided screenshots.
  Mobile: draggable diamond toggle button
  PC: RightShift to open/close
  Intro: 2-second diamond → 4 muted squares → instant-blue reassembly → UI
  AUTH tab + key system (3 fails or 5 min timeout → unload)
  Double-column sections, toggles, buttons, textboxes, dropdowns, colorpicker, notifications
]]

local Library = {}
Library.__index = Library

local HttpService       = game:GetService("HttpService")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local TextService       = game:GetService("TextService")
local CoreGui           = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Mouse       = LocalPlayer:GetMouse()

-- ──────────────────────────────────────────────
-- Theme (single dark-blue theme matching screenshots)
-- ──────────────────────────────────────────────
-- Colors matched to the screenshots (deep navy card, blue accent tabs/toggles)
local Theme = {
    -- Deep blue-violet surfaces from the mockup; accent sampled to suit the logo.
    Paper      = Color3.fromRGB(28, 26, 47),
    Row        = Color3.fromRGB(35, 33, 55),
    Input      = Color3.fromRGB(24, 23, 41),
    Accent     = Color3.fromRGB(0, 105, 255),
    AccentDim  = Color3.fromRGB(0, 72, 185),
    Ink        = Color3.fromRGB(232, 235, 247),
    Desc       = Color3.fromRGB(151, 153, 173),
    Line       = Color3.fromRGB(20, 23, 42),
    Cream      = Color3.fromRGB(245, 248, 255),
    Danger     = Color3.fromRGB(220, 65, 85),
    Success    = Color3.fromRGB(65, 200, 140),
}

-- ──────────────────────────────────────────────
-- Sound system (CoffeeIFY-renewed assets – same pathway as original UILibrary)
-- ──────────────────────────────────────────────
Library.SoundEnabled = true
Library.SoundVolume  = 0.75

local SoundService = game:GetService("SoundService")
local Debris       = game:GetService("Debris")

local BASE = "https://github.com/jawolskimanowski-ui/CoffeeIFY-renewed/raw/refs/heads/main/"
local SOUND_URLS = {
    notify     = BASE .. "mixkit-sci-fi-positive-notification-266.wav",
    notifyAlt  = BASE .. "Robotic-female-sound-effect-warning.mp3",
    click      = BASE .. "Button%20Click%202%20-%20Kaino.mp3",
    hover      = BASE .. "mixkit-sci-fi-click-900.wav",
    select     = BASE .. "mixkit-sci-fi-confirmation-914.wav",
    transition = BASE .. "dragon-studio-futuristic-transition-499653.mp3",
    transitionAlt = BASE .. "mixkit-fast-sci-fi-transition-sweep-3114.wav",
    slider     = BASE .. "mixkit-water-sci-fi-bleep-902.wav",
    reject     = BASE .. "mixkit-sci-fi-reject-notification-896.wav",
    zoom       = BASE .. "mixkit-sci-fi-interface-zoom-890.wav",
}

local ASSET_FOLDER = "Carbonode"
local soundIds = {}          -- name → resolved asset id
local downloadStarted = false
local retryPending = {}

local function getExec(name)
    local ok, v = pcall(function()
        return (_G and _G[name]) or (getgenv and getgenv()[name]) or (getfenv and getfenv(0)[name])
    end)
    return (ok and type(v) == "function") and v or nil
end

local function resolveAsset(path)
    local asset = getExec("getcustomasset") or getExec("getsynasset")
    if not asset then return nil end
    local ok, id = pcall(asset, path)
    if ok and type(id) == "string" and id ~= "" then return id end
    return nil
end

local function downloadSound(name, url)
    local write = getExec("writefile")
    if not write then return nil end

    local makefolder = getExec("makefolder")
    local isfolder   = getExec("isfolder")
    local isfile     = getExec("isfile")

    local path = ASSET_FOLDER .. "/" .. name .. (string.find(url, "%.wav") and ".wav" or ".mp3")
    local fallback = "Carbonode_" .. name .. (string.find(url, "%.wav") and ".wav" or ".mp3")

    if makefolder then
        local folderReady = false
        if isfolder then
            local ok, exists = pcall(isfolder, ASSET_FOLDER)
            folderReady = ok and exists == true
        end
        if not folderReady then pcall(makefolder, ASSET_FOLDER) end
    end

    if isfile then
        local ok, exists = pcall(isfile, path)
        if ok and exists then return path end
        local ok2, exists2 = pcall(isfile, fallback)
        if ok2 and exists2 then return fallback end
    end

    local ok, data = pcall(function() return game:HttpGet(url) end)
    if not ok or type(data) ~= "string" or data == "" then return nil end

    if pcall(write, path, data) then return path end
    if pcall(write, fallback, data) then return fallback end
    return nil
end

local function ensureSounds()
    if downloadStarted then return end
    downloadStarted = true
    task.spawn(function()
        for name, url in pairs(SOUND_URLS) do
            local path = downloadSound(name, url)
            if path then
                soundIds[name] = resolveAsset(path)
            end
        end
    end)
end

local function playSound(name, volumeMul)
    if not Library.SoundEnabled then return end
    ensureSounds()

    local id = soundIds[name]
    if not id then
        -- retry a few times while download finishes
        if retryPending[name] then return end
        retryPending[name] = true
        task.spawn(function()
            for _ = 1, 20 do
                task.wait(0.15)
                id = soundIds[name]
                if id then break end
            end
            retryPending[name] = nil
            if id then
                local s = Instance.new("Sound")
                s.Name = "Carbonode_" .. name
                s.SoundId = id
                s.Volume = math.clamp((Library.SoundVolume or 0.75) * (volumeMul or 1), 0, 1)
                s.Parent = SoundService
                pcall(function() s:Play() end)
                Debris:AddItem(s, 8)
            end
        end)
        return
    end

    local s = Instance.new("Sound")
    s.Name = "Carbonode_" .. name
    s.SoundId = id
    s.Volume = math.clamp((Library.SoundVolume or 0.75) * (volumeMul or 1), 0, 1)
    s.Parent = SoundService
    pcall(function() s:Play() end)
    Debris:AddItem(s, 8)
end

-- Public SFX hook used throughout the library
Library._sfx = function(name)
    name = tostring(name or "")
    if name == "notify" then
        playSound("notify", 0.9)
    elseif name == "hover" then
        playSound("hover", 0.35)
    elseif name == "select" or name == "click" or name == "toggleOn" or name == "toggleOff" then
        playSound("click", 0.55)
    elseif name == "transition" or name == "tab" then
        playSound("transition", 0.7)
    elseif name == "slider" then
        playSound("zoom", 0.45)  -- interface zoom for slider
    elseif name == "reject" then
        playSound("reject", 0.7)
    elseif name == "zoom" then
        playSound("zoom", 0.6)
    else
        playSound("click", 0.45)
    end
end

-- Start downloading in background as soon as the library loads
ensureSounds()

-- ──────────────────────────────────────────────
-- Achievement / Easter-egg system
-- ──────────────────────────────────────────────
Library.Achievements = Library.Achievements or {}
Library._unlockedAchievements = Library._unlockedAchievements or {}

-- Register an achievement
-- Library:RegisterAchievement("id", { Title = "...", Description = "...", Sound = "rbxassetid://..." or url })
function Library:RegisterAchievement(id, data)
    if type(id) ~= "string" or id == "" then return false end
    self.Achievements[id] = {
        Title = data.Title or id,
        Description = data.Description or "",
        Sound = data.Sound,          -- rbxassetid or raw url (will be handled)
        Icon = data.Icon,
        Secret = data.Secret == true,
    }
    return true
end

-- Unlock + notify + play sound
function Library:UnlockAchievement(id)
    if self._unlockedAchievements[id] then return false end -- already unlocked
    local ach = self.Achievements[id]
    if not ach then return false end

    self._unlockedAchievements[id] = true

    -- Special achievement notification
    self:Notify({
        Title = "🏆 ACHIEVEMENT UNLOCKED",
        Description = ach.Title .. (ach.Description ~= "" and ("\n" .. ach.Description) or ""),
        Duration = 5.5,
    })

    -- Play achievement sound (same download pathway style as original UILibrary)
    if ach.Sound and self.SoundEnabled then
        task.spawn(function()
            local SoundService = game:GetService("SoundService")
            local Debris = game:GetService("Debris")
            local soundId = tostring(ach.Sound)

            local function getExec(name)
                local ok, v = pcall(function()
                    return (_G and _G[name]) or (getgenv and getgenv()[name]) or (getfenv and getfenv(0)[name])
                end)
                return (ok and type(v) == "function") and v or nil
            end

            -- Download pathway identical in spirit to the original library
            if string.find(soundId, "http", 1, true) then
                local write = getExec("writefile")
                local getasset = getExec("getcustomasset") or getExec("getsynasset")
                local makefolder = getExec("makefolder")
                local isfolder = getExec("isfolder")
                local isfile = getExec("isfile")

                if write and getasset then
                    local ASSET_FOLDER = "Carbonode"
                    local path = ASSET_FOLDER .. "/Achievement_" .. id .. ".mp3"
                    local fallback = "Carbonode_Achievement_" .. id .. ".mp3"

                    -- ensure folder
                    if makefolder then
                        local folderOk = false
                        if isfolder then
                            local ok, exists = pcall(isfolder, ASSET_FOLDER)
                            folderOk = ok and exists == true
                        end
                        if not folderOk then
                            pcall(makefolder, ASSET_FOLDER)
                        end
                    end

                    -- already cached?
                    local cached = false
                    if isfile then
                        local ok, exists = pcall(isfile, path)
                        if ok and exists then
                            cached = true
                        else
                            local ok2, exists2 = pcall(isfile, fallback)
                            if ok2 and exists2 then
                                path = fallback
                                cached = true
                            end
                        end
                    end

                    if not cached then
                        local ok, data = pcall(function() return game:HttpGet(soundId) end)
                        if ok and type(data) == "string" and #data > 0 then
                            local wrote = pcall(write, path, data)
                            if not wrote then
                                pcall(write, fallback, data)
                                path = fallback
                            end
                        end
                    end

                    local assetOk, assetId = pcall(getasset, path)
                    if assetOk and type(assetId) == "string" and assetId ~= "" then
                        soundId = assetId
                    end
                end
            end

            local s = Instance.new("Sound")
            s.Name = "Carbonode_Achievement_" .. id
            s.SoundId = soundId
            s.Volume = math.clamp((tonumber(self.SoundVolume) or 0.7) * 0.95, 0, 1)
            s.Parent = SoundService
            pcall(function() s:Play() end)
            Debris:AddItem(s, 20)
        end)
    end

    return true
end

-- Built-in Easter egg: type "67"
Library:RegisterAchievement("67", {
    Title = "67",
    Description = "You found the secret.",
    Secret = true,
    -- Same pathway style as the original UILibrary (raw GitHub mp3)
    Sound = "https://github.com/jawolskimanowski-ui/CoffeeIFY-renewed/raw/refs/heads/main/67_kid.mp3",
})

-- Global detector for typing "67" anywhere in the UI (TextBoxes) or as a key sequence
local function setupEasterEgg67(gui, connectSignal)
    local buffer = ""
    local lastTime = 0

    -- Detect in any TextBox
    local function hookTextBox(box)
        if box:GetAttribute("_67Hooked") then return end
        box:SetAttribute("_67Hooked", true)
        box:GetPropertyChangedSignal("Text"):Connect(function()
            local txt = string.lower(tostring(box.Text or ""))
            if string.find(txt, "67", 1, true) then
                Library:UnlockAchievement("67")
            end
        end)
    end

    -- Watch for new TextBoxes
    gui.DescendantAdded:Connect(function(obj)
        if obj:IsA("TextBox") then
            task.defer(hookTextBox, obj)
        end
    end)
    for _, obj in ipairs(gui:GetDescendants()) do
        if obj:IsA("TextBox") then
            hookTextBox(obj)
        end
    end

    -- Also allow typing 6 then 7 quickly as a key sequence (even outside textboxes)
    connectSignal(UserInputService.InputBegan, function(input, gp)
        if gp then return end
        if input.KeyCode == Enum.KeyCode.Six or input.KeyCode == Enum.KeyCode.KeypadSix then
            buffer = "6"
            lastTime = tick()
        elseif (input.KeyCode == Enum.KeyCode.Seven or input.KeyCode == Enum.KeyCode.KeypadSeven) and buffer == "6" and (tick() - lastTime) < 1.2 then
            buffer = ""
            Library:UnlockAchievement("67")
        else
            buffer = ""
        end
    end)
end

-- ──────────────────────────────────────────────
-- Helpers
-- ──────────────────────────────────────────────
local function new(class, props, parent)
    local i = Instance.new(class)
    for k, v in pairs(props or {}) do
        i[k] = v
    end
    if parent then i.Parent = parent end
    return i
end

local function tw(inst, t, props, style, dir)
    local info = TweenInfo.new(t or 0.25, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out)
    local tween = TweenService:Create(inst, info, props)
    tween:Play()
    return tween
end

local function isPointer(input)
    return input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
end

local function isMobile()
    return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function getExecutor(name)
    local ok, v = pcall(function() return _G[name] or (getgenv and getgenv()[name]) end)
    if ok and type(v) == "function" then return v end
    return nil
end

-- Simple icon map (lucide-style names → rbxassetid). Extend as needed.
local Icons = {
    ["home"]        = "rbxassetid://10734950309",
    ["settings"]    = "rbxassetid://10734950309", -- gear fallback
    ["gear"]        = "rbxassetid://10734950309",
    ["key"]         = "rbxassetid://10734950309",
    ["shield"]      = "rbxassetid://10734950309",
    ["heart"]       = "rbxassetid://10734950309",
    ["user"]        = "rbxassetid://10734950309",
    ["log"]         = "rbxassetid://10734950309",
    ["page"]        = "rbxassetid://10734950309",
    ["chevron-down"]= "rbxassetid://10709781958",
    ["x"]           = "rbxassetid://10709791523",
    ["check"]       = "rbxassetid://10709790644",
}

local function resolveIcon(name)
    if type(name) ~= "string" then return nil end
    if string.find(name, "rbxassetid://", 1, true) then return name end
    return Icons[name] or Icons["page"]
end

-- Text glyphs keep the compact tab bar crisp without relying on unrelated
-- placeholder image IDs. Callers can still pass their own icon asset IDs.
local TAB_GLYPHS = {
    cloud = "☁", page = "☁", logs = "≡", log = "≡",
    settings = "⚙", gear = "⚙", key = "◇", home = "⌂",
}

-- ──────────────────────────────────────────────
-- Notification system
-- ──────────────────────────────────────────────
local NotifyContainer
local function EnsureNotifyContainer(gui)
    if NotifyContainer and NotifyContainer.Parent then return end
    NotifyContainer = new("Frame", {
        Name = "NotifyContainer",
        Size = UDim2.new(0, 280, 1, 0),
        Position = UDim2.new(1, -300, 0, 20),
        BackgroundTransparency = 1,
        ZIndex = 200,
    }, gui)
    new("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 8),
        VerticalAlignment = Enum.VerticalAlignment.Top,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
    }, NotifyContainer)
end

function Library:Notify(opts)
    opts = type(opts) == "table" and opts or { Title = tostring(opts), Duration = 3 }
    local title = opts.Title or "Notice"
    local desc  = opts.Description or opts.Text or ""
    local dur   = opts.Duration or 3.5

    if Library._sfx then Library._sfx("notify") end

    if not NotifyContainer then return end

    local card = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        BackgroundColor3 = Theme.Paper,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        ZIndex = 201,
    }, NotifyContainer)
    new("UICorner", { CornerRadius = UDim.new(0, 8) }, card)
    local stroke = new("UIStroke", { Color = Theme.Line, Thickness = 1 }, card)

    local accentBar = new("Frame", {
        Size = UDim2.new(0, 3, 1, 0),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        ZIndex = 202,
    }, card)

    local tLabel = new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(14, 8),
        Size = UDim2.new(1, -28, 0, 18),
        Font = Enum.Font.Code,
        TextSize = 14,
        TextColor3 = Theme.Ink,
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = title,
        ZIndex = 202,
    }, card)

    local dLabel = new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(14, 28),
        Size = UDim2.new(1, -28, 0, 0),
        Font = Enum.Font.Code,
        TextSize = 12,
        TextColor3 = Theme.Desc,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        TextWrapped = true,
        Text = desc,
        ZIndex = 202,
    }, card)

    local textSize = TextService:GetTextSize(desc, 12, Enum.Font.Code, Vector2.new(250, 400))
    local height = math.clamp(textSize.Y + 44, 48, 120)
    dLabel.Size = UDim2.new(1, -28, 0, textSize.Y)

    card.Size = UDim2.new(1, 0, 0, 0)
    tw(card, 0.35, { Size = UDim2.new(1, 0, 0, height) }, Enum.EasingStyle.Back)

    task.delay(dur, function()
        if not card.Parent then return end
        tw(card, 0.3, { Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1 })
        task.wait(0.32)
        card:Destroy()
    end)
end

-- ──────────────────────────────────────────────
-- CreateWindow
-- ──────────────────────────────────────────────
function Library:CreateWindow(WindowName, Config)
    Config = Config or {}
    local self = setmetatable({}, Library)

    local KeySystemEnabled = Config.KeySystem == true
    local ExpectedKey      = tostring((Config.KeySystemConfig and (Config.KeySystemConfig.Key or Config.KeySystemConfig.ExpectedKey)) or "KEY")
    local KeyNote          = (Config.KeySystemConfig and Config.KeySystemConfig.Note) or "Enter the access key to unlock categories."
    local KeyAuthenticated = not KeySystemEnabled
    local KeyFailClicks    = 0
    local KeyStartTime     = tick()
    local KEY_TIMEOUT      = 300 -- 5 minutes
    local MAX_FAILS        = 3

    local connections = {}
    local function connect(sig, fn)
        local c = sig:Connect(fn)
        table.insert(connections, c)
        return c
    end

    -- ScreenGui
    local gui = new("ScreenGui", {
        Name = "Carbonode_" .. HttpService:GenerateGUID(false),
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        IgnoreGuiInset = true,
        DisplayOrder = 50,
    })
    pcall(function() gui.Parent = CoreGui end)
    if not gui.Parent then gui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

    EnsureNotifyContainer(gui)

    -- Activate Easter-egg / achievement detectors
    setupEasterEgg67(gui, connect)

    -- ──────────────────────────────────────────────
    -- INTRO  (2-second Carbonode diamond assembly)
    -- The four pieces separate and lose their blue; on reassembly the blue
    -- returns instantly, matching the supplied animation frames.
    -- ──────────────────────────────────────────────
    local introDone = false
    local animRunning = true
    local introFrame = new("Frame", {
        Name = "Intro",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1, -- leave the game world visible behind the mark
        BorderSizePixel = 0,
        ZIndex = 300,
    }, gui)

    local introCard = new("Frame", {
        Name = "IntroCard",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(236, 180),
        BackgroundColor3 = Theme.Paper,
        BorderSizePixel = 0,
        ZIndex = 301,
    }, introFrame)
    new("UICorner", { CornerRadius = UDim.new(0, 4) }, introCard)
    local introStroke = new("UIStroke", {
        Color = Theme.Line,
        Thickness = 1,
        Transparency = 0.1,
    }, introCard)

    local introCenter = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(80, 80),
        BackgroundTransparency = 1,
        ZIndex = 302,
    }, introCard)

    local diamondSquares = {}
    local separatedPositions = {
        UDim2.fromScale(0.50, 0.28), -- top
        UDim2.fromScale(0.72, 0.50), -- right
        UDim2.fromScale(0.50, 0.72), -- bottom
        UDim2.fromScale(0.28, 0.50), -- left
    }
    for i = 1, 4 do
        local square = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(40, 40),
            BackgroundColor3 = Theme.Accent,
            BackgroundTransparency = 0,
            BorderSizePixel = 0,
            Rotation = 45,
            ZIndex = 303,
        }, introCenter)
        new("UICorner", { CornerRadius = UDim.new(0, 2) }, square)
        diamondSquares[i] = square
    end

    task.spawn(function()
        -- 0.00–0.55s: one blue diamond separates into four neutral squares.
        for i, square in ipairs(diamondSquares) do
            tw(square, 0.55, {
                Position = separatedPositions[i],
                Size = UDim2.fromOffset(20, 20),
                Rotation = 0,
                BackgroundColor3 = Color3.fromRGB(61, 65, 80),
                BackgroundTransparency = 0.28,
            }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
        end
        task.wait(0.55)
        if not animRunning or not introFrame.Parent then return end

        -- Stay separated briefly, with the blue fully gone.
        task.wait(0.25)
        if not animRunning or not introFrame.Parent then return end

        -- 0.80–1.25s: restore blue instantly, then bring the pieces together.
        for _, square in ipairs(diamondSquares) do
            square.BackgroundColor3 = Theme.Accent
            square.BackgroundTransparency = 0
            tw(square, 0.45, {
                Position = UDim2.fromScale(0.5, 0.5),
                Size = UDim2.fromOffset(40, 40),
                Rotation = 45,
            }, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
        end
        task.wait(0.45)
        if not animRunning or not introFrame.Parent then return end

        -- Hold the completed blue diamond, then clear the loading card.
        task.wait(0.35)
        if not animRunning or not introFrame.Parent then return end
        tw(introStroke, 0.4, { Transparency = 1 })
        tw(introCard, 0.4, { BackgroundTransparency = 1 })
        for _, square in ipairs(diamondSquares) do
            tw(square, 0.32, { BackgroundTransparency = 1 })
        end
        task.wait(0.4)
        if introFrame.Parent then introFrame:Destroy() end
        animRunning = false
        introDone = true
    end)

    -- Main UI is constructed underneath while this two-second animation plays.

    -- ──────────────────────────────────────────
    -- MAIN WINDOW  (matches screenshot: single card + top horizontal tabs)
    -- Auto-size: not cramped, scales with viewport on small screens
    -- ──────────────────────────────────────────
    local baseW = (Config.Size and Config.Size.X.Offset > 0) and Config.Size.X.Offset or 600
    local baseH = (Config.Size and Config.Size.Y.Offset > 0) and Config.Size.Y.Offset or 456
    local cam = workspace.CurrentCamera
    local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
    -- Match the mockup by default, but never let the window spill off-screen.
    local maxW = math.min(baseW, math.max(260, vp.X - 32))
    local maxH = math.min(baseH, math.max(240, vp.Y - 48))
    local WindowSize = UDim2.fromOffset(maxW, maxH)

    local Main = new("Frame", {
        Name = "Main",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = WindowSize,
        BackgroundColor3 = Theme.Paper,
        BorderSizePixel = 0,
        Visible = false,
        ClipsDescendants = true,
        ZIndex = 10,
    }, gui)
    new("UICorner", { CornerRadius = UDim.new(0, 5) }, Main)
    new("UIStroke", { Color = Theme.Line, Thickness = 1 }, Main)

    -- Optional overall scale (Config.Scale = 0.85..1.2)
    local uiScale = new("UIScale", {
        Scale = math.clamp(tonumber(Config.Scale) or 1, 0.75, 1.25),
    }, Main)

    -- ──────────────────────────────────────────
    -- Carbonode logo watermark (faint, large, behind UI)
    -- ──────────────────────────────────────────
    local LOGO_URL = "https://raw.githubusercontent.com/jawolskimanowski-ui/CoffeeIFY-renewed/refs/heads/main/file_000000000bdc8207b7dacd3eabdb50b7.png"
    local watermark = new("ImageLabel", {
        Name = "CarbonodeWatermark",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.55),
        Size = UDim2.fromScale(0.92, 0.85),
        BackgroundTransparency = 1,
        Image = "",
        ImageTransparency = 0.96, -- barely visible brand watermark
        ImageColor3 = Color3.fromRGB(80, 140, 255), -- blue tint (diamond / arcs)
        ScaleType = Enum.ScaleType.Fit,
        ZIndex = 10,
    }, Main)

    -- Download logo same pathway as sounds
    task.spawn(function()
        local function getExec(name)
            local ok, v = pcall(function()
                return (_G and _G[name]) or (getgenv and getgenv()[name]) or (getfenv and getfenv(0)[name])
            end)
            return (ok and type(v) == "function") and v or nil
        end
        local write = getExec("writefile")
        local getasset = getExec("getcustomasset") or getExec("getsynasset")
        local makefolder = getExec("makefolder")
        local isfile = getExec("isfile")
        if not write or not getasset then return end

        local folder = "Carbonode"
        if makefolder then pcall(makefolder, folder) end
        local path = folder .. "/logo.png"
        local fallback = "Carbonode_logo.png"

        local cached = false
        if isfile then
            local ok, exists = pcall(isfile, path)
            if ok and exists then cached = true
            else
                local ok2, exists2 = pcall(isfile, fallback)
                if ok2 and exists2 then path = fallback; cached = true end
            end
        end

        if not cached then
            local ok, data = pcall(function() return game:HttpGet(LOGO_URL) end)
            if ok and type(data) == "string" and #data > 0 then
                if not pcall(write, path, data) then
                    pcall(write, fallback, data)
                    path = fallback
                end
            end
        end

        local assetOk, assetId = pcall(getasset, path)
        if assetOk and type(assetId) == "string" and assetId ~= "" and watermark.Parent then
            watermark.Image = assetId
        end
    end)

    -- Top tab bar (horizontal, like the screenshots)
    local TabBar = new("Frame", {
        Name = "TabBar",
        Size = UDim2.new(1, 0, 0, 42),
        BackgroundColor3 = Theme.Paper,
        BorderSizePixel = 0,
        ZIndex = 11,
    }, Main)

    local TabList = new("Frame", {
        Name = "TabList",
        Position = UDim2.fromOffset(12, 0),
        Size = UDim2.new(1, -56, 1, 0),
        BackgroundTransparency = 1,
        ZIndex = 12,
    }, TabBar)
    new("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 4),
        VerticalAlignment = Enum.VerticalAlignment.Center,
    }, TabList)

    -- Gear top-right
    local GearBtn = new("TextButton", {
        Name = "Gear",
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.fromOffset(28, 28),
        BackgroundColor3 = Theme.Input,
        BorderSizePixel = 0,
        Text = "⚙",
        Font = Enum.Font.Code,
        TextSize = 14,
        TextColor3 = Theme.Ink,
        AutoButtonColor = false,
        ZIndex = 13,
    }, TabBar)
    new("UICorner", { CornerRadius = UDim.new(0, 6) }, GearBtn)

    -- Subtle divider under tabs
    local tabDivider = new("Frame", {
        Position = UDim2.new(0, 0, 1, -1),
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = Theme.Line,
        BorderSizePixel = 0,
        ZIndex = 12,
    }, TabBar)

    -- Content area (full width under tabs)
    local Content = new("Frame", {
        Name = "Content",
        Position = UDim2.fromOffset(0, 42),
        Size = UDim2.new(1, 0, 1, -42),
        BackgroundTransparency = 1,
        ClipsDescendants = true,
        ZIndex = 11,
    }, Main)

    -- Dragging from tab bar
    local dragging, dragStart, startPos
    connect(TabBar.InputBegan, function(input)
        if isPointer(input) then
            dragging = true
            dragStart = input.Position
            startPos = Main.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    connect(UserInputService.InputChanged, function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)

    -- Keep a CloseBtn reference for compatibility (hidden, gear handles settings)
    local CloseBtn = GearBtn

    -- ──────────────────────────────────────────
    -- Open / Close with fade
    -- ──────────────────────────────────────────
    local windowOpen = false
    local unloading = false
    local function SetWindowOpen(state, instant)
        if unloading then return end
        if state == windowOpen and not instant then return end
        windowOpen = state
        if state then
            Main.Visible = true
            Main.BackgroundTransparency = 1
            for _, d in ipairs(Main:GetDescendants()) do
                if d:IsA("GuiObject") and d ~= Main then
                    if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
                        if d:GetAttribute("_origText") == nil then
                            d:SetAttribute("_origText", d.TextTransparency)
                        end
                        d.TextTransparency = 1
                    end
                    if d:IsA("ImageLabel") or d:IsA("ImageButton") then
                        if d:GetAttribute("_origImage") == nil then
                            d:SetAttribute("_origImage", d.ImageTransparency)
                        end
                        d.ImageTransparency = 1
                    end
                    if d.BackgroundTransparency < 1 then
                        d:SetAttribute("_origBG", d.BackgroundTransparency)
                        d.BackgroundTransparency = 1
                    end
                end
            end
            tw(Main, instant and 0 or 0.35, { BackgroundTransparency = 0 })
            for _, d in ipairs(Main:GetDescendants()) do
                if d:IsA("GuiObject") then
                    if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
                        local originalText = d:GetAttribute("_origText")
                        tw(d, instant and 0 or 0.3, { TextTransparency = originalText ~= nil and originalText or 0 })
                    end
                    if d:IsA("ImageLabel") or d:IsA("ImageButton") then
                        local originalImage = d:GetAttribute("_origImage")
                        tw(d, instant and 0 or 0.3, { ImageTransparency = originalImage ~= nil and originalImage or 0 })
                    end
                    local orig = d:GetAttribute("_origBG")
                    if orig then
                        tw(d, instant and 0 or 0.3, { BackgroundTransparency = orig })
                    end
                end
            end
        else
            -- fade out (slightly slower)
            tw(Main, instant and 0 or 0.45, { BackgroundTransparency = 1 })
            for _, d in ipairs(Main:GetDescendants()) do
                if d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox") then
                    tw(d, instant and 0 or 0.4, { TextTransparency = 1 })
                end
                if d:IsA("ImageLabel") or d:IsA("ImageButton") then
                    tw(d, instant and 0 or 0.4, { ImageTransparency = 1 })
                end
            end
            task.delay(instant and 0 or 0.5, function()
                if not windowOpen then Main.Visible = false end
            end)
        end
    end

    -- Advanced outro: port the original library's strip-wipe language while
    -- retaining Carbonode's diamond breakup / reassembly as the brand signature.
    local OutroStyle = tostring(Config.OutroStyle or "Crosscut")
    local validOutroStyles = {
        Classic = true, Shutter = true, Slash = true, Pinstripe = true,
        ["Reverse Slash"] = true, Crosscut = true, ["Swipe Left"] = true,
        Fade = true, Diamond = true,
    }
    if not validOutroStyles[OutroStyle] then OutroStyle = "Crosscut" end

    local function UnloadUI()
        if unloading then return end
        unloading = true
        animRunning = false
        if Library._sfx then Library._sfx("transition") end

        -- Remove a still-running intro so it cannot fight the outro tweens.
        local runningIntro = gui:FindFirstChild("Intro")
        if runningIntro then runningIntro:Destroy() end

        local outroFrame = new("Frame", {
            Name = "CarbonodeOutro",
            Size = UDim2.fromScale(1, 1),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ZIndex = 500,
        }, gui)

        local outroCard = new("Frame", {
            Name = "OutroCard",
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(236, 180),
            BackgroundColor3 = Theme.Paper,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ZIndex = 501,
        }, outroFrame)
        new("UICorner", { CornerRadius = UDim.new(0, 4) }, outroCard)
        local outroStroke = new("UIStroke", {
            Color = Theme.Line,
            Thickness = 1,
            Transparency = 1,
        }, outroCard)
        local outroCenter = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(80, 80),
            BackgroundTransparency = 1,
            ZIndex = 502,
        }, outroCard)

        local outroSquares = {}
        for i = 1, 4 do
            local square = new("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.fromScale(0.5, 0.5),
                Size = UDim2.fromOffset(40, 40),
                BackgroundColor3 = Theme.Accent,
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Rotation = 45,
                ZIndex = 503,
            }, outroCenter)
            new("UICorner", { CornerRadius = UDim.new(0, 2) }, square)
            outroSquares[i] = square
        end

        local function fadeTree(root, duration)
            if not root then return end
            local objects = { root }
            for _, object in ipairs(root:GetDescendants()) do
                table.insert(objects, object)
            end
            for _, object in ipairs(objects) do
                if object:IsA("GuiObject") then
                    local goals = {}
                    if object.BackgroundTransparency < 1 then goals.BackgroundTransparency = 1 end
                    if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
                        goals.TextTransparency = 1
                        goals.TextStrokeTransparency = 1
                    end
                    if object:IsA("ImageLabel") or object:IsA("ImageButton") then
                        goals.ImageTransparency = 1
                    end
                    if object:IsA("ScrollingFrame") then goals.ScrollBarImageTransparency = 1 end
                    if next(goals) then tw(object, duration, goals, Enum.EasingStyle.Quart, Enum.EasingDirection.In) end
                elseif object:IsA("UIStroke") then
                    tw(object, duration, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
                end
            end
        end

        -- Strip geometry is a Carbonode-local version of the original library's
        -- Classic / Shutter / Slash / Pinstripe / Reverse Slash / Crosscut wipe.
        local stripPresets = {
            Classic = { n = 9, angle = -13, barW = 0.22 },
            Shutter = { n = 12, angle = 0, barW = 0.20, fixedR = 0.5, step = 0.018 },
            Slash = { n = 7, angle = 24, barW = 0.30 },
            Pinstripe = { n = 16, angle = 0, barW = 0.095, step = 0.012 },
            ["Reverse Slash"] = { n = 8, angle = -27, barW = 0.27 },
            Crosscut = { n = 22, angle = 35, alternateAngle = -35, barW = 1.08, step = 0.010 },
        }

        local stripBands = {}
        local function createStripWipe(style)
            local preset = stripPresets[style]
            if not preset or not Main or not Main.Parent then return end
            local absPos = Main.AbsolutePosition
            local absSize = Main.AbsoluteSize
            local W = math.max(absSize.X, 1)
            local H = math.max(absSize.Y, 1)
            local maxAngle = math.max(math.abs(preset.angle or 0), math.abs(preset.alternateAngle or 0))
            local angleRad = math.rad(maxAngle)
            local pad = 0.9 * H * math.abs(math.sin(angleRad))
                + 0.5 * W * (preset.barW or 0) * math.abs(math.cos(angleRad))
                + 0.16 * W
            local x0, x1 = -pad, W + pad
            local spacing = (x1 - x0) / math.max(preset.n - 1, 1)
            local barWidth = math.max(W * preset.barW, spacing * math.cos(math.rad(preset.angle or 0)) * 1.45)

            for i = 1, preset.n do
                local r = preset.fixedR or Random.new():NextNumber(0.1, 0.9)
                local xc = x0 + (i - 1) * spacing
                local angle = preset.alternateAngle and (i % 2 == 0 and preset.alternateAngle or preset.angle) or preset.angle
                local band = new("Frame", {
                    Name = "OutroWipeBand",
                    Position = UDim2.fromOffset(absPos.X, absPos.Y + r * H),
                    Size = UDim2.fromOffset(W, 0),
                    BackgroundTransparency = 1,
                    BorderSizePixel = 0,
                    ClipsDescendants = true,
                    ZIndex = 500,
                }, outroFrame)
                local bar = new("Frame", {
                    AnchorPoint = Vector2.new(0.5, 0.5),
                    Position = UDim2.fromOffset(xc, H / 2 - r * H),
                    Size = UDim2.fromOffset(barWidth, H * 1.8),
                    Rotation = angle,
                    BackgroundColor3 = Theme.Paper,
                    BackgroundTransparency = 1,
                    BorderSizePixel = 0,
                    ZIndex = 500,
                }, band)
                new("UIStroke", { Color = Theme.Line, Thickness = 1, Transparency = 1 }, bar)
                local step = preset.step and math.min(preset.step, 0.22 / math.max(preset.n - 1, 1)) or nil
                local delayTime = step and ((i - 1) * step) or ((i - 1) / math.max(preset.n - 1, 1)) * 0.18
                table.insert(stripBands, { band = band, bar = bar, x = absPos.X, y = absPos.Y, w = W, h = H, r = r, xc = xc, delay = delayTime })
            end
        end

        local mainBasePosition = Main.Position
        local mainBaseRotation = Main.Rotation
        if not Main.Visible then Main.Visible = true end

        -- The window exits left, matching the original Slide Left motion.
        -- Other outro styles layer an animated strip wipe over the same exit.
        if OutroStyle ~= "Fade" and OutroStyle ~= "Diamond" and OutroStyle ~= "Swipe Left" then
            createStripWipe(OutroStyle)
        end
        fadeTree(Main, 0.55)
        local mainWidth = math.max(Main.AbsoluteSize.X, Main.Size.X.Offset, 1)
        local exitX = (OutroStyle == "Swipe Left" or OutroStyle == "Crosscut" or OutroStyle == "Slash" or OutroStyle == "Reverse Slash") and -mainWidth * 1.08 or -mainWidth * 0.72
        tw(Main, 0.62, {
            Position = UDim2.new(mainBasePosition.X.Scale, mainBasePosition.X.Offset + exitX, mainBasePosition.Y.Scale, mainBasePosition.Y.Offset),
            Rotation = mainBaseRotation - ((OutroStyle == "Glitch") and 1.5 or 0.5),
        }, Enum.EasingStyle.Quart, Enum.EasingDirection.In)

        local toggleFrame = gui:FindFirstChild("CarbonodeToggle")
        fadeTree(toggleFrame, 0.24)
        fadeTree(NotifyContainer, 0.24)

        -- Grow the strip bands across the old window, with a compact stagger.
        for _, item in ipairs(stripBands) do
            task.delay(item.delay, function()
                if item.band and item.band.Parent then
                    tw(item.band, 0.34, {
                        Position = UDim2.fromOffset(item.x, item.y),
                        Size = UDim2.fromOffset(item.w, item.h),
                    }, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
                    tw(item.bar, 0.34, {
                        Position = UDim2.fromOffset(item.xc, item.h / 2),
                        BackgroundTransparency = 0.04,
                    }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
                    local stroke = item.bar:FindFirstChildOfClass("UIStroke")
                    if stroke then tw(stroke, 0.28, { Transparency = 0.35 }) end
                end
            end)
        end

        task.spawn(function()
            -- Reveal the brand card after the old window has begun its exit.
            task.wait(0.20)
            if not gui.Parent then return end
            tw(outroCard, 0.28, { BackgroundTransparency = 0 }, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
            tw(outroStroke, 0.28, { Transparency = 0.12 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
            for _, square in ipairs(outroSquares) do
                square.BackgroundColor3 = Theme.Accent
                square.BackgroundTransparency = 0
            end

            -- Diamond breaks into four muted squares.
            for i, square in ipairs(outroSquares) do
                tw(square, 0.48, {
                    Position = separatedPositions[i],
                    Size = UDim2.fromOffset(20, 20),
                    Rotation = 0,
                    BackgroundColor3 = Color3.fromRGB(61, 65, 80),
                    BackgroundTransparency = 0.22,
                }, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
            end
            task.wait(0.48)
            task.wait(0.16)

            -- Blue returns instantly at the start of assembly, as in the intro.
            for _, square in ipairs(outroSquares) do
                square.BackgroundColor3 = Theme.Accent
                square.BackgroundTransparency = 0
                tw(square, 0.46, {
                    Position = UDim2.fromScale(0.5, 0.5),
                    Size = UDim2.fromOffset(40, 40),
                    Rotation = 45,
                }, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
            end
            task.wait(0.46)
            task.wait(0.24)

            tw(outroStroke, 0.36, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
            tw(outroCard, 0.36, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
            for _, square in ipairs(outroSquares) do
                tw(square, 0.30, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
            end
            for _, item in ipairs(stripBands) do
                if item.band and item.band.Parent then
                    tw(item.bar, 0.22, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
                end
            end
            task.wait(0.38)

            for _, connection in ipairs(connections) do
                pcall(function() connection:Disconnect() end)
            end
            if gui.Parent then gui:Destroy() end
        end)
    end

    -- ──────────────────────────────────────────
    -- Toggle: RightShift (PC) + diamond button (always available, styled for mobile)
    -- ──────────────────────────────────────────
    local toggleKey = Enum.KeyCode.RightShift

    -- Diamond toggle button (dark card + bright blue diamond, draggable)
    -- Always created so mobile users always have it; also useful on PC
    local CarbonodeBtn = new("TextButton", {
        Name = "CarbonodeToggle",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.92, 0, 0.55, 0),
        Size = UDim2.fromOffset(58, 58),
        BackgroundColor3 = Color3.fromRGB(16, 20, 32),
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        ZIndex = 100,
        Visible = true,
    }, gui)
    new("UICorner", { CornerRadius = UDim.new(0, 10) }, CarbonodeBtn)
    new("UIStroke", { Color = Color3.fromRGB(35, 45, 70), Thickness = 1 }, CarbonodeBtn)

    -- Soft glow behind diamond
    local glow = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(30, 30),
        BackgroundColor3 = Theme.Accent,
        BackgroundTransparency = 0.85,
        BorderSizePixel = 0,
        Rotation = 45,
        ZIndex = 100,
    }, CarbonodeBtn)
    new("UICorner", { CornerRadius = UDim.new(0, 4) }, glow)

    -- Bright blue diamond
    local inner = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(20, 20),
        BackgroundColor3 = Theme.Accent,
        BorderSizePixel = 0,
        Rotation = 45,
        ZIndex = 101,
    }, CarbonodeBtn)
    new("UICorner", { CornerRadius = UDim.new(0, 3) }, inner)

    -- Drag vs click (only treat as drag if moved > 8px)
    local dDragging, dMoved, dStart, dPos
    connect(CarbonodeBtn.InputBegan, function(input)
        if isPointer(input) then
            dDragging = true
            dMoved = false
            dStart = input.Position
            dPos = CarbonodeBtn.Position
        end
    end)
    connect(UserInputService.InputChanged, function(input)
        if dDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dStart
            if math.abs(delta.X) > 8 or math.abs(delta.Y) > 8 then
                dMoved = true
            end
            if dMoved then
                CarbonodeBtn.Position = UDim2.new(dPos.X.Scale, dPos.X.Offset + delta.X, dPos.Y.Scale, dPos.Y.Offset + delta.Y)
            end
        end
    end)
    connect(UserInputService.InputEnded, function(input)
        if isPointer(input) and dDragging then
            dDragging = false
            if not dMoved then
                -- pure click → toggle window
                if Library._sfx then Library._sfx("select") end
                SetWindowOpen(not windowOpen)
            end
        end
    end)

    -- PC: RightShift
    connect(UserInputService.InputBegan, function(input, gp)
        if gp then return end
        if input.KeyCode == toggleKey then
            SetWindowOpen(not windowOpen)
        end
    end)

    -- ──────────────────────────────────────────
    -- Category / Tab system
    -- ──────────────────────────────────────────
    local categories = {}
    local currentPage = nil
    local pages = {}

    -- Page transitions port the original library's motion language, but keep
    -- Carbonode's compact single-column pages and restrained timing.
    local PageTransitionStyle = tostring(Config.PageTransition or "Slide Left")
    local PageTransitionDuration = math.clamp(tonumber(Config.PageTransitionDuration) or 0.32, 0.18, 0.65)
    local validPageTransitions = {
        ["Slide Left"] = true, ["Swipe Left"] = true, ["Slide Right"] = true,
        Cascade = true, Pop = true, Glitch = true, Fade = true, None = true,
    }
    if not validPageTransitions[PageTransitionStyle] then
        PageTransitionStyle = "Slide Left"
    end
    local pageTransitionBusy = false
    local queuedPageName = nil

    local function collectPageTargets(root)
        local targets = {}
        local objects = { root }
        for _, descendant in ipairs(root:GetDescendants()) do
            table.insert(objects, descendant)
        end
        for _, object in ipairs(objects) do
            local properties = {}
            if object:IsA("GuiObject") then
                properties.BackgroundTransparency = object.BackgroundTransparency
            end
            if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
                properties.TextTransparency = object.TextTransparency
                properties.TextStrokeTransparency = object.TextStrokeTransparency
            end
            if object:IsA("ImageLabel") or object:IsA("ImageButton") then
                properties.ImageTransparency = object.ImageTransparency
            end
            if object:IsA("ScrollingFrame") then
                properties.ScrollBarImageTransparency = object.ScrollBarImageTransparency
            end
            if object:IsA("UIStroke") then
                properties.Transparency = object.Transparency
            end
            for property, value in pairs(properties) do
                if type(value) == "number" and value < 0.999 then
                    table.insert(targets, { instance = object, property = property, value = value })
                end
            end
        end
        return targets
    end

    local function tweenPageTargets(targets, transparency, duration, delayTime)
        for index, target in ipairs(targets) do
            local object = target.instance
            if object and object.Parent then
                local stagger = delayTime and ((index - 1) * delayTime) or 0
                task.delay(stagger, function()
                    if object and object.Parent then
                        tw(object, duration, { [target.property] = transparency == nil and target.value or transparency },
                            Enum.EasingStyle.Quint,
                            transparency == nil and Enum.EasingDirection.Out or Enum.EasingDirection.In)
                    end
                end)
            end
        end
    end

    local selectCategory
    selectCategory = function(name)
        if unloading or not gui.Parent then return end
        if not KeyAuthenticated and name ~= "AUTH" then
            self:Notify({ Title = "LOCKED", Description = "Complete AUTH first.", Duration = 2.5 })
            return
        end
        local nextData = categories[name]
        if not nextData or not nextData.page then return end
        if pageTransitionBusy then
            queuedPageName = name
            return
        end
        if currentPage == name then return end

        local previousData = currentPage and categories[currentPage] or nil
        local previousPage = previousData and previousData.page or nil
        local nextPage = nextData.page
        local switching = previousPage and previousPage ~= nextPage

        if switching and Library._sfx then Library._sfx("transition") end

        for n, data in pairs(categories) do
            local selected = (n == name)
            local tabColor = selected and Theme.Accent or Theme.Desc
            if data.icon then data.icon.TextColor3 = tabColor end
            if data.label then data.label.TextColor3 = tabColor end
            if data.underline then data.underline.BackgroundTransparency = selected and 0 or 1 end
        end
        currentPage = name

        if not switching or PageTransitionStyle == "None" then
            for n, data in pairs(categories) do
                if data.page then data.page.Visible = (n == name) end
            end
            nextPage.Position = UDim2.fromOffset(0, 0)
            return
        end

        pageTransitionBusy = true
        local style = PageTransitionStyle == "Swipe Left" and "Slide Left" or PageTransitionStyle
        local duration = PageTransitionDuration
        local width = math.max(Content.AbsoluteSize.X, nextPage.AbsoluteSize.X, 1)
        local oldPosition = previousPage.Position
        local newPosition = nextPage.Position
        local direction = (style == "Slide Right") and 1 or -1
        local offset = math.max(26, width * 0.11)

        local oldTargets = collectPageTargets(previousPage)
        local newTargets = collectPageTargets(nextPage)
        local scaleObject
        local oldEnd = oldPosition
        local newStart = newPosition

        if style == "Slide Left" or style == "Slide Right" or style == "Cascade" or style == "Glitch" then
            oldEnd = UDim2.new(oldPosition.X.Scale, oldPosition.X.Offset + direction * offset, oldPosition.Y.Scale, oldPosition.Y.Offset)
            newStart = UDim2.new(newPosition.X.Scale, newPosition.X.Offset - direction * offset, newPosition.Y.Scale, newPosition.Y.Offset)
        elseif style == "Pop" then
            scaleObject = new("UIScale", { Scale = 0.91 }, nextPage)
        end

        -- The old page exits while the new page enters from the opposite edge.
        nextPage.Position = newStart
        nextPage.Visible = true
        for _, target in ipairs(newTargets) do
            if target.instance and target.instance.Parent then
                pcall(function() target.instance[target.property] = 1 end)
            end
        end

        if style == "Pop" and scaleObject then
            tw(scaleObject, duration, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
        else
            tw(nextPage, duration, { Position = newPosition },
                style == "Glitch" and Enum.EasingStyle.Quint or Enum.EasingStyle.Quart,
                Enum.EasingDirection.Out)
        end
        tw(previousPage, duration * 0.88, { Position = oldEnd }, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
        tweenPageTargets(oldTargets, 1, duration * 0.72, 0)

        -- Fade in by visual row, matching the original library's Cascade / Slide Left feel.
        local rows = {}
        for _, child in ipairs(nextPage:GetChildren()) do
            if child:IsA("GuiObject") and child.Visible then
                local rowTargets = {}
                for _, target in ipairs(newTargets) do
                    if target.instance == child or target.instance:IsDescendantOf(child) then
                        table.insert(rowTargets, target)
                    end
                end
                if #rowTargets > 0 then table.insert(rows, rowTargets) end
            end
        end
        local rowStagger = (style == "Cascade" and 0.065) or (style == "Glitch" and 0.012) or 0.026
        for rowIndex, rowTargets in ipairs(rows) do
            task.delay((rowIndex - 1) * rowStagger, function()
                for _, target in ipairs(rowTargets) do
                    if target.instance and target.instance.Parent then
                        tw(target.instance, duration * 0.78, { [target.property] = target.value },
                            Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
                    end
                end
            end)
        end

        if style == "Glitch" then
            task.delay(0.055, function()
                if nextPage.Parent and nextPage.Visible then
                    tw(nextPage, 0.045, { Position = UDim2.new(newPosition.X.Scale, newPosition.X.Offset + 7, newPosition.Y.Scale, newPosition.Y.Offset - 1) }, Enum.EasingStyle.Linear)
                end
            end)
            task.delay(0.105, function()
                if nextPage.Parent and nextPage.Visible then
                    tw(nextPage, 0.075, { Position = newPosition }, Enum.EasingStyle.Quint)
                end
            end)
        end

        task.delay(duration + math.max(#rows - 1, 0) * rowStagger + 0.08, function()
            if previousPage and previousPage.Parent then
                previousPage.Visible = false
                previousPage.Position = oldPosition
                for _, target in ipairs(oldTargets) do
                    if target.instance and target.instance.Parent then
                        pcall(function() target.instance[target.property] = target.value end)
                    end
                end
            end
            if nextPage and nextPage.Parent then
                nextPage.Position = newPosition
                for _, target in ipairs(newTargets) do
                    if target.instance and target.instance.Parent then
                        pcall(function() target.instance[target.property] = target.value end)
                    end
                end
            end
            if scaleObject and scaleObject.Parent then scaleObject:Destroy() end
            pageTransitionBusy = false
            local queued = queuedPageName
            queuedPageName = nil
            if queued and queued ~= currentPage then selectCategory(queued) end
        end)
    end

    local WindowAPI = {}

    function WindowAPI:CreateCategory(name, iconName, visible)
        if visible == nil then visible = true end

        -- Compact horizontal tab: muted glyph + label, blue when selected.
        local btn = new("TextButton", {
            Name = name,
            Size = UDim2.fromOffset(0, 28),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Text = "",
            AutoButtonColor = false,
            LayoutOrder = #categories + 1,
            Visible = visible,
            ZIndex = 13,
        }, TabList)
        new("UIPadding", {
            PaddingLeft = UDim.new(0, 8),
            PaddingRight = UDim.new(0, 8),
        }, btn)
        new("UIListLayout", {
            FillDirection = Enum.FillDirection.Horizontal,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 5),
            VerticalAlignment = Enum.VerticalAlignment.Center,
        }, btn)

        local glyphKey = string.lower(tostring(iconName or ""))
        local glyphText = TAB_GLYPHS[glyphKey]
        if not glyphText and string.find(glyphKey, "cloud", 1, true) then glyphText = "☁" end
        if not glyphText and (string.find(glyphKey, "log", 1, true) or string.find(glyphKey, "list", 1, true)) then glyphText = "≡" end
        if not glyphText and string.find(glyphKey, "setting", 1, true) then glyphText = "⚙" end
        if not glyphText and string.find(glyphKey, "key", 1, true) then glyphText = "◇" end
        if not glyphText and string.find(glyphKey, "home", 1, true) then glyphText = "⌂" end
        local tabIcon = new("TextLabel", {
            Size = UDim2.fromOffset(15, 24),
            BackgroundTransparency = 1,
            Font = Enum.Font.Gotham,
            TextSize = 14,
            TextColor3 = Theme.Desc,
            Text = glyphText or "",
            TextXAlignment = Enum.TextXAlignment.Center,
            LayoutOrder = 1,
            ZIndex = 14,
        }, btn)
        local tabLabel = new("TextLabel", {
            Size = UDim2.new(0, 0, 1, 0),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundTransparency = 1,
            Font = Enum.Font.Code,
            TextSize = 13,
            TextColor3 = Theme.Desc,
            Text = tostring(name),
            TextXAlignment = Enum.TextXAlignment.Left,
            LayoutOrder = 2,
            ZIndex = 14,
        }, btn)

        local underline = nil -- active state is communicated by the icon and label color

        local contentWidth = math.clamp(tonumber(Config.ContentWidth) or 0.5, 0.35, 1)
        local page = new("ScrollingFrame", {
            Name = name .. "Page",
            Size = UDim2.new(contentWidth, 0, 1, 0),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ScrollBarThickness = 2,
            ScrollBarImageColor3 = Theme.Accent,
            CanvasSize = UDim2.new(0, 0, 0, 0),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            Visible = false,
            ZIndex = 12,
        }, Content)
        new("UIPadding", {
            PaddingTop = UDim.new(0, 14),
            PaddingBottom = UDim.new(0, 16),
            PaddingLeft = UDim.new(0, 16),
            PaddingRight = UDim.new(0, 16),
        }, page)
        new("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 8),
        }, page)

        -- Single column (matches the simple card in screenshots)
        -- leftCol/rightCol still exist for API compat but both point to page
        local leftCol, rightCol = page, page

        categories[name] = { btn = btn, page = page, left = leftCol, right = rightCol, underline = underline, icon = tabIcon, label = tabLabel }
        pages[name] = page

        connect(btn.MouseEnter, function()
            if Library._sfx then Library._sfx("hover") end
        end)
        connect(btn.MouseButton1Click, function()
            selectCategory(name)
        end)

        local tabAPI = {}

        local function getColumn(side)
            return page -- single column
        end

        -- Section (simple header like "section 1" in screenshot)
        function tabAPI:CreateSection(title, side)
            local parent = getColumn(side)
            local sec = new("Frame", {
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundTransparency = 1,
                LayoutOrder = #parent:GetChildren(),
                ZIndex = 13,
            }, parent)
            new("UIListLayout", {
                SortOrder = Enum.SortOrder.LayoutOrder,
                Padding = UDim.new(0, 6),
            }, sec)

            if title and title ~= "" then
                new("TextLabel", {
                    Size = UDim2.new(1, 0, 0, 16),
                    BackgroundTransparency = 1,
                    Font = Enum.Font.Code,
                    TextSize = 12,
                    TextColor3 = Theme.Desc,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Text = tostring(title),
                    LayoutOrder = 0,
                    ZIndex = 14,
                }, sec)
            end
            return sec
        end

        -- Label
        function tabAPI:CreateLabel(text, side)
            local parent = getColumn(side)
            local lbl = new("TextLabel", {
                Size = UDim2.new(1, 0, 0, 18),
                BackgroundTransparency = 1,
                Font = Enum.Font.Code,
                TextSize = 12,
                TextColor3 = Theme.Desc,
                TextXAlignment = Enum.TextXAlignment.Left,
                Text = tostring(text or ""),
                LayoutOrder = #parent:GetChildren(),
                ZIndex = 13,
            }, parent)
            return lbl
        end

        -- Paragraph: low-contrast inset card with a title and supporting text.
        function tabAPI:CreateParagraph(title, body, side)
            local parent = getColumn(side)
            local card = new("Frame", {
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundColor3 = Theme.Row,
                BorderSizePixel = 0,
                LayoutOrder = #parent:GetChildren(),
                ZIndex = 13,
            }, parent)
            new("UICorner", { CornerRadius = UDim.new(0, 5) }, card)
            new("UIPadding", {
                PaddingTop = UDim.new(0, 8),
                PaddingBottom = UDim.new(0, 8),
                PaddingLeft = UDim.new(0, 10),
                PaddingRight = UDim.new(0, 10),
            }, card)
            new("UIListLayout", {
                SortOrder = Enum.SortOrder.LayoutOrder,
                Padding = UDim.new(0, 2),
            }, card)
            local heading = new("TextLabel", {
                Size = UDim2.new(1, 0, 0, 16),
                BackgroundTransparency = 1,
                Font = Enum.Font.Code,
                TextSize = 13,
                TextColor3 = Theme.Ink,
                TextXAlignment = Enum.TextXAlignment.Left,
                Text = tostring(title or ""),
                LayoutOrder = 1,
                ZIndex = 14,
            }, card)
            local p = new("TextLabel", {
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundTransparency = 1,
                Font = Enum.Font.Code,
                TextSize = 11,
                TextColor3 = Theme.Desc,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextYAlignment = Enum.TextYAlignment.Top,
                TextWrapped = true,
                Text = tostring(body or ""),
                LayoutOrder = 2,
                ZIndex = 14,
            }, card)
            p:SetAttribute("_CarbonodeParagraphTitle", title or "")
            return p
        end

        -- Toggle (pill switch matching screenshot)
        function tabAPI:CreateToggle(text, default, callback, side)
            local parent = getColumn(side)
            local row = new("Frame", {
                Size = UDim2.new(1, 0, 0, 36),
                BackgroundColor3 = Theme.Row,
                BorderSizePixel = 0,
                LayoutOrder = #parent:GetChildren(),
                ZIndex = 13,
            }, parent)
            new("UICorner", { CornerRadius = UDim.new(0, 5) }, row)

            local lbl = new("TextLabel", {
                Position = UDim2.fromOffset(10, 0),
                Size = UDim2.new(1, -56, 1, 0),
                BackgroundTransparency = 1,
                Font = Enum.Font.Code,
                TextSize = 13,
                TextColor3 = Theme.Ink,
                TextXAlignment = Enum.TextXAlignment.Left,
                Text = tostring(text or "Toggle"),
                ZIndex = 14,
            }, row)

            local track = new("Frame", {
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -10, 0.5, 0),
                Size = UDim2.fromOffset(36, 18),
                BackgroundColor3 = Color3.fromRGB(40, 45, 60),
                BorderSizePixel = 0,
                ZIndex = 14,
            }, row)
            new("UICorner", { CornerRadius = UDim.new(1, 0) }, track)

            local knob = new("Frame", {
                Position = UDim2.fromOffset(2, 2),
                Size = UDim2.fromOffset(14, 14),
                BackgroundColor3 = Color3.fromRGB(120, 130, 150),
                BorderSizePixel = 0,
                ZIndex = 15,
            }, track)
            new("UICorner", { CornerRadius = UDim.new(1, 0) }, knob)

            local state = default == true
            local function render()
                -- Off: dark gray track + muted knob. On: blue ring/knob (screenshot style)
                tw(track, 0.18, { BackgroundColor3 = state and Color3.fromRGB(30, 50, 100) or Color3.fromRGB(40, 45, 60) })
                tw(knob, 0.18, {
                    Position = state and UDim2.fromOffset(20, 2) or UDim2.fromOffset(2, 2),
                    BackgroundColor3 = state and Theme.Accent or Color3.fromRGB(120, 130, 150),
                })
            end
            render()

            local btn = new("TextButton", {
                Size = UDim2.fromScale(1, 1),
                BackgroundTransparency = 1,
                Text = "",
                ZIndex = 16,
            }, row)
            connect(btn.MouseEnter, function()
                if Library._sfx then Library._sfx("hover") end
            end)
            connect(btn.MouseButton1Click, function()
                state = not state
                render()
                if Library._sfx then Library._sfx(state and "toggleOn" or "toggleOff") end
                if callback then pcall(callback, state) end
            end)

            return {
                Set = function(_, v) state = v == true; render() end,
                Get = function() return state end,
            }
        end

        -- ──────────────────────────────────────────
        -- Futuristic Slider (inspired by original tick/dot design, redesigned)
        -- Thin glowing track + diamond ticks + glowing diamond thumb + value badge
        -- Plays "slider" sound on value change (same hook as original library)
        -- ──────────────────────────────────────────
        function tabAPI:CreateSlider(text, min, max, default, callback, side)
            -- Flexible args: CreateSlider("Speed", 0, 100, 50, fn) or with side
            if type(min) == "function" then
                callback = min; min = 0; max = 100; default = 0
            elseif type(default) == "function" then
                callback = default; default = min; min = 0; max = 100
            elseif type(callback) == "string" then
                side = callback; callback = nil
            end
            if type(side) == "function" then
                callback = side; side = "Left"
            end

            min = tonumber(min) or 0
            max = tonumber(max) or 100
            if min > max then min, max = max, min end
            local value = math.clamp(tonumber(default) or min, min, max)

            local parent = getColumn(side)
            local row = new("Frame", {
                Size = UDim2.new(1, 0, 0, 42),
                BackgroundTransparency = 1,
                LayoutOrder = #parent:GetChildren(),
                ZIndex = 13,
            }, parent)

            -- Label + value badge
            local lbl = new("TextLabel", {
                Size = UDim2.new(1, -70, 0, 16),
                BackgroundTransparency = 1,
                Font = Enum.Font.Code,
                TextSize = 12,
                TextColor3 = Theme.Ink,
                TextXAlignment = Enum.TextXAlignment.Left,
                Text = tostring(text or "Slider"),
                ZIndex = 14,
            }, row)

            local badge = new("TextLabel", {
                AnchorPoint = Vector2.new(1, 0),
                Position = UDim2.new(1, 0, 0, 0),
                Size = UDim2.fromOffset(52, 16),
                BackgroundColor3 = Theme.AccentDim,
                BorderSizePixel = 0,
                Font = Enum.Font.Code,
                TextSize = 11,
                TextColor3 = Theme.Cream,
                Text = tostring(value),
                ZIndex = 14,
            }, row)
            new("UICorner", { CornerRadius = UDim.new(0, 4) }, badge)

            -- Track container
            local track = new("Frame", {
                Position = UDim2.fromOffset(0, 22),
                Size = UDim2.new(1, 0, 0, 16),
                BackgroundTransparency = 1,
                Active = true,
                ZIndex = 14,
            }, row)

            -- Background rail
            local rail = new("Frame", {
                AnchorPoint = Vector2.new(0, 0.5),
                Position = UDim2.new(0, 0, 0.5, 0),
                Size = UDim2.new(1, 0, 0, 4),
                BackgroundColor3 = Theme.Input,
                BorderSizePixel = 0,
                ZIndex = 14,
            }, track)
            new("UICorner", { CornerRadius = UDim.new(1, 0) }, rail)

            -- Glowing fill
            local fill = new("Frame", {
                AnchorPoint = Vector2.new(0, 0.5),
                Position = UDim2.new(0, 0, 0.5, 0),
                Size = UDim2.new(0, 0, 0, 4),
                BackgroundColor3 = Theme.Accent,
                BorderSizePixel = 0,
                ZIndex = 15,
            }, track)
            new("UICorner", { CornerRadius = UDim.new(1, 0) }, fill)
            -- subtle glow stroke
            local fillStroke = new("UIStroke", {
                Color = Theme.Accent,
                Thickness = 1,
                Transparency = 0.55,
            }, fill)

            -- Diamond ticks (futuristic look)
            local TICK_COUNT = 12
            local ticks = {}
            for i = 1, TICK_COUNT do
                local t = new("Frame", {
                    AnchorPoint = Vector2.new(0.5, 0.5),
                    Position = UDim2.new((i - 0.5) / TICK_COUNT, 0, 0.5, 0),
                    Size = UDim2.fromOffset(5, 5),
                    BackgroundColor3 = Theme.Line,
                    BorderSizePixel = 0,
                    Rotation = 45, -- diamond shape
                    ZIndex = 16,
                }, track)
                new("UICorner", { CornerRadius = UDim.new(0, 1) }, t)
                ticks[i] = t
            end

            -- Glowing diamond thumb
            local thumb = new("Frame", {
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.new(0, 0, 0.5, 0),
                Size = UDim2.fromOffset(12, 12),
                BackgroundColor3 = Theme.Cream,
                BorderSizePixel = 0,
                Rotation = 45,
                ZIndex = 18,
            }, track)
            new("UICorner", { CornerRadius = UDim.new(0, 2) }, thumb)
            local thumbStroke = new("UIStroke", {
                Color = Theme.Accent,
                Thickness = 1.5,
                Transparency = 0.2,
            }, thumb)

            local function render()
                local f = (max == min) and 0 or (value - min) / (max - min)
                badge.Text = tostring(math.floor(value + 0.5))
                fill.Size = UDim2.new(f, 0, 0, 4)
                thumb.Position = UDim2.new(f, 0, 0.5, 0)

                for i, t in ipairs(ticks) do
                    local filled = ((i - 0.5) / TICK_COUNT) <= f + 0.001
                    t.BackgroundColor3 = filled and Theme.Accent or Theme.Line
                    t.BackgroundTransparency = filled and 0 or 0.4
                end
            end
            render()

            local dragging = false
            local function updateFromX(x)
                local rel = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
                local newVal = math.clamp(math.floor(min + (max - min) * rel + 0.5), min, max)
                if newVal ~= value then
                    value = newVal
                    render()
                    -- Keep original sound hook
                    if Library._sfx then
                        pcall(Library._sfx, "slider")
                    end
                    if callback then pcall(callback, value) end
                end
            end

            connect(track.InputBegan, function(input)
                if isPointer(input) then
                    dragging = true
                    updateFromX(input.Position.X)
                end
            end)
            connect(UserInputService.InputChanged, function(input)
                if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                    updateFromX(input.Position.X)
                end
            end)
            connect(UserInputService.InputEnded, function(input)
                if isPointer(input) then dragging = false end
            end)

            -- Hover glow on thumb
            connect(track.MouseEnter, function()
                tw(thumbStroke, 0.15, { Transparency = 0 })
                tw(thumb, 0.15, { Size = UDim2.fromOffset(14, 14) })
            end)
            connect(track.MouseLeave, function()
                if not dragging then
                    tw(thumbStroke, 0.15, { Transparency = 0.2 })
                    tw(thumb, 0.15, { Size = UDim2.fromOffset(12, 12) })
                end
            end)

            return {
                Set = function(_, v)
                    local n = tonumber(v)
                    if not n then return false end
                    value = math.clamp(n, min, max)
                    render()
                    if callback then pcall(callback, value) end
                    return true
                end,
                Get = function() return value end,
            }
        end

        -- Button
        function tabAPI:CreateButton(text, callback, side)
            local parent = getColumn(side)
            local btn = new("TextButton", {
                Size = UDim2.new(1, 0, 0, 34),
                BackgroundColor3 = Theme.Row,
                BorderSizePixel = 0,
                Font = Enum.Font.Code,
                TextSize = 13,
                TextColor3 = Theme.Ink,
                Text = tostring(text or "Button"),
                AutoButtonColor = false,
                LayoutOrder = #parent:GetChildren(),
                ZIndex = 13,
            }, parent)
            new("UICorner", { CornerRadius = UDim.new(0, 6) }, btn)

            connect(btn.MouseEnter, function()
                tw(btn, 0.15, { BackgroundColor3 = Theme.AccentDim })
                if Library._sfx then Library._sfx("hover") end
            end)
            connect(btn.MouseLeave, function()
                tw(btn, 0.15, { BackgroundColor3 = Theme.Row })
            end)
            connect(btn.MouseButton1Click, function()
                if Library._sfx then Library._sfx("select") end
                if callback then pcall(callback) end
            end)
            return btn
        end

        -- Textbox
        function tabAPI:CreateTextbox(placeholder, default, callback, side)
            local parent = getColumn(side)
            local box = new("TextBox", {
                Size = UDim2.new(1, 0, 0, 30),
                BackgroundColor3 = Theme.Row,
                BorderSizePixel = 0,
                Font = Enum.Font.Code,
                TextSize = 13,
                TextColor3 = Theme.Ink,
                PlaceholderText = tostring(placeholder or "Type here..."),
                PlaceholderColor3 = Theme.Desc,
                Text = tostring(default or ""),
                ClearTextOnFocus = false,
                LayoutOrder = #parent:GetChildren(),
                ZIndex = 13,
            }, parent)
            new("UICorner", { CornerRadius = UDim.new(0, 6) }, box)
            new("UIStroke", { Color = Theme.Line, Thickness = 1 }, box)
            new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, box)

            connect(box.FocusLost, function(enter)
                if callback then pcall(callback, box.Text, enter) end
            end)
            return {
                Get = function() return box.Text end,
                Set = function(_, v) box.Text = tostring(v or "") end,
            }
        end

        -- Dropdown (simple)
        function tabAPI:CreateDropdown(text, options, default, callback, side)
            options = options or {}
            local parent = getColumn(side)
            local open = false
            local selected = default or options[1] or ""

            local row = new("Frame", {
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundTransparency = 1,
                LayoutOrder = #parent:GetChildren(),
                ZIndex = 13,
            }, parent)
            new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }, row)

            local header = new("TextButton", {
                Size = UDim2.new(1, 0, 0, 30),
                BackgroundColor3 = Theme.Input,
                BorderSizePixel = 0,
                Font = Enum.Font.Code,
                TextSize = 13,
                TextColor3 = Theme.Ink,
                Text = "  " .. tostring(text) .. "  ·  " .. tostring(selected),
                TextXAlignment = Enum.TextXAlignment.Left,
                AutoButtonColor = false,
                LayoutOrder = 0,
                ZIndex = 14,
            }, row)
            new("UICorner", { CornerRadius = UDim.new(0, 6) }, header)
            new("UIStroke", { Color = Theme.Line, Thickness = 1 }, header)

            local listFrame = new("Frame", {
                Size = UDim2.new(1, 0, 0, 0),
                AutomaticSize = Enum.AutomaticSize.Y,
                BackgroundColor3 = Theme.Paper,
                BorderSizePixel = 0,
                Visible = false,
                ClipsDescendants = true,
                LayoutOrder = 1,
                ZIndex = 20,
            }, row)
            new("UICorner", { CornerRadius = UDim.new(0, 6) }, listFrame)
            new("UIStroke", { Color = Theme.Line, Thickness = 1 }, listFrame)
            new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 1) }, listFrame)

            local function setOpen(v)
                open = v
                listFrame.Visible = v
            end

            for i, opt in ipairs(options) do
                local optBtn = new("TextButton", {
                    Size = UDim2.new(1, 0, 0, 26),
                    BackgroundColor3 = Theme.Input,
                    BorderSizePixel = 0,
                    Font = Enum.Font.Code,
                    TextSize = 12,
                    TextColor3 = Theme.Desc,
                    Text = "  " .. tostring(opt),
                    TextXAlignment = Enum.TextXAlignment.Left,
                    AutoButtonColor = false,
                    LayoutOrder = i,
                    ZIndex = 21,
                }, listFrame)
                connect(optBtn.MouseButton1Click, function()
                    selected = opt
                    header.Text = "  " .. tostring(text) .. "  ·  " .. tostring(selected)
                    setOpen(false)
                    if callback then pcall(callback, selected) end
                end)
            end

            connect(header.MouseButton1Click, function()
                setOpen(not open)
            end)

            return {
                Get = function() return selected end,
                Set = function(_, v)
                    selected = v
                    header.Text = "  " .. tostring(text) .. "  ·  " .. tostring(selected)
                end,
            }
        end

        -- ColorPicker (basic working version)
        function tabAPI:CreateColorPicker(text, default, callback, side)
            default = typeof(default) == "Color3" and default or Theme.Accent
            local parent = getColumn(side)
            local current = default

            local row = new("Frame", {
                Size = UDim2.new(1, 0, 0, 30),
                BackgroundTransparency = 1,
                LayoutOrder = #parent:GetChildren(),
                ZIndex = 13,
            }, parent)

            local lbl = new("TextLabel", {
                Size = UDim2.new(1, -40, 1, 0),
                BackgroundTransparency = 1,
                Font = Enum.Font.Code,
                TextSize = 13,
                TextColor3 = Theme.Ink,
                TextXAlignment = Enum.TextXAlignment.Left,
                Text = tostring(text or "Color"),
                ZIndex = 14,
            }, row)

            local swatch = new("TextButton", {
                AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, 0, 0.5, 0),
                Size = UDim2.fromOffset(28, 22),
                BackgroundColor3 = current,
                BorderSizePixel = 0,
                Text = "",
                AutoButtonColor = false,
                ZIndex = 14,
            }, row)
            new("UICorner", { CornerRadius = UDim.new(0, 5) }, swatch)
            new("UIStroke", { Color = Theme.Line, Thickness = 1 }, swatch)

            -- Simple HSV popup
            local popup
            connect(swatch.MouseButton1Click, function()
                if popup and popup.Parent then
                    popup:Destroy()
                    popup = nil
                    return
                end
                popup = new("Frame", {
                    AnchorPoint = Vector2.new(1, 0),
                    Position = UDim2.new(1, 0, 1, 6),
                    Size = UDim2.fromOffset(160, 130),
                    BackgroundColor3 = Theme.Paper,
                    BorderSizePixel = 0,
                    ZIndex = 50,
                }, row)
                new("UICorner", { CornerRadius = UDim.new(0, 8) }, popup)
                new("UIStroke", { Color = Theme.Line, Thickness = 1 }, popup)

                local h, s, v = Color3.toHSV(current)
                local function apply()
                    current = Color3.fromHSV(h, s, v)
                    swatch.BackgroundColor3 = current
                    if callback then pcall(callback, current) end
                end

                -- Hue slider
                local hueBar = new("Frame", {
                    Position = UDim2.fromOffset(10, 10),
                    Size = UDim2.new(1, -20, 0, 14),
                    BackgroundColor3 = Color3.fromRGB(255, 0, 0),
                    BorderSizePixel = 0,
                    ZIndex = 51,
                }, popup)
                new("UICorner", { CornerRadius = UDim.new(0, 4) }, hueBar)
                local hueGrad = new("UIGradient", {
                    Color = ColorSequence.new({
                        ColorSequenceKeypoint.new(0, Color3.fromRGB(255,0,0)),
                        ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255,255,0)),
                        ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0,255,0)),
                        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0,255,255)),
                        ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0,0,255)),
                        ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255,0,255)),
                        ColorSequenceKeypoint.new(1, Color3.fromRGB(255,0,0)),
                    }),
                }, hueBar)

                local function makeSlider(y, labelText, init, setFn)
                    local bar = new("Frame", {
                        Position = UDim2.fromOffset(10, y),
                        Size = UDim2.new(1, -20, 0, 14),
                        BackgroundColor3 = Theme.Input,
                        BorderSizePixel = 0,
                        ZIndex = 51,
                    }, popup)
                    new("UICorner", { CornerRadius = UDim.new(0, 4) }, bar)
                    local fill = new("Frame", {
                        Size = UDim2.new(init, 0, 1, 0),
                        BackgroundColor3 = Theme.Accent,
                        BorderSizePixel = 0,
                        ZIndex = 52,
                    }, bar)
                    new("UICorner", { CornerRadius = UDim.new(0, 4) }, fill)
                    local dragging = false
                    local function update(x)
                        local rel = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
                        fill.Size = UDim2.new(rel, 0, 1, 0)
                        setFn(rel)
                        apply()
                    end
                    connect(bar.InputBegan, function(inp)
                        if isPointer(inp) then
                            dragging = true
                            update(inp.Position.X)
                        end
                    end)
                    connect(UserInputService.InputChanged, function(inp)
                        if dragging and (inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch) then
                            update(inp.Position.X)
                        end
                    end)
                    connect(UserInputService.InputEnded, function(inp)
                        if isPointer(inp) then dragging = false end
                    end)
                    return bar
                end

                makeSlider(32, "S", s, function(val) s = val end)
                makeSlider(52, "V", v, function(val) v = val end)
                makeSlider(72, "H", h, function(val) h = val end)

                local closeP = new("TextButton", {
                    Position = UDim2.fromOffset(10, 98),
                    Size = UDim2.new(1, -20, 0, 22),
                    BackgroundColor3 = Theme.Input,
                    BorderSizePixel = 0,
                    Font = Enum.Font.Code,
                    TextSize = 12,
                    TextColor3 = Theme.Ink,
                    Text = "Close",
                    ZIndex = 51,
                }, popup)
                new("UICorner", { CornerRadius = UDim.new(0, 5) }, closeP)
                connect(closeP.MouseButton1Click, function()
                    if popup then popup:Destroy(); popup = nil end
                end)
            end)

            return {
                Get = function() return current end,
                Set = function(_, c)
                    if typeof(c) == "Color3" then
                        current = c
                        swatch.BackgroundColor3 = c
                    end
                end,
            }
        end

        return tabAPI, page, btn
    end

    -- ──────────────────────────────────────────
    -- AUTH tab (key system)
    -- ──────────────────────────────────────────
    if KeySystemEnabled then
        local AuthTab, AuthPage = WindowAPI:CreateCategory("AUTH", "key", true)

        AuthTab:CreateLabel("KEY SYSTEM")
        AuthTab:CreateParagraph("Access", KeyNote, "Left")

        local keyBox = AuthTab:CreateTextbox("Enter key...", "", nil, "Left")

        AuthTab:CreateButton("VERIFY KEY", function()
            local typed = keyBox.Get()
            typed = tostring(typed or ""):gsub("^%s+", ""):gsub("%s+$", "")

            if typed ~= "" and string.upper(typed) == string.upper(ExpectedKey) then
                KeyAuthenticated = true
                KeyFailClicks = 0
                self:Notify({ Title = "AUTHENTICATED", Description = "Categories unlocked.", Duration = 3 })
                -- reveal other categories
                for name, data in pairs(categories) do
                    if name ~= "AUTH" then
                        data.btn.Visible = true
                    end
                end
                -- switch to first non-auth
                for name, _ in pairs(categories) do
                    if name ~= "AUTH" then
                        selectCategory(name)
                        break
                    end
                end
            else
                KeyFailClicks = KeyFailClicks + 1
                self:Notify({
                    Title = "INVALID KEY",
                    Description = string.format("Attempts: %d / %d", KeyFailClicks, MAX_FAILS),
                    Duration = 3,
                })
                if KeyFailClicks >= MAX_FAILS then
                    self:Notify({ Title = "FAILED", Description = "Too many attempts. Unloading.", Duration = 2 })
                    task.delay(1.2, UnloadUI)
                end
            end
        end, "Left")

        -- Timeout checker
        task.spawn(function()
            while not KeyAuthenticated and gui.Parent and not unloading do
                if tick() - KeyStartTime > KEY_TIMEOUT then
                    self:Notify({ Title = "TIMEOUT", Description = "Key entry window expired.", Duration = 2.5 })
                    task.delay(1, UnloadUI)
                    break
                end
                task.wait(2)
            end
        end)

        -- Hide other tabs until auth
        for name, data in pairs(categories) do
            if name ~= "AUTH" then
                data.btn.Visible = false
            end
        end
        selectCategory("AUTH")
    end

    -- ──────────────────────────────────────────
    -- Settings panel (gear)
    -- ──────────────────────────────────────────
    local settingsOpen = false
    local SettingsPanel = new("Frame", {
        Name = "Settings",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -8, 0, 42),
        Size = UDim2.fromOffset(200, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = Theme.Paper,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 40,
    }, Main)
    new("UICorner", { CornerRadius = UDim.new(0, 8) }, SettingsPanel)
    new("UIStroke", { Color = Theme.Line, Thickness = 1 }, SettingsPanel)
    new("UIPadding", {
        PaddingTop = UDim.new(0, 10),
        PaddingBottom = UDim.new(0, 10),
        PaddingLeft = UDim.new(0, 10),
        PaddingRight = UDim.new(0, 10),
    }, SettingsPanel)
    new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }, SettingsPanel)

    local function addSettingLabel(t)
        new("TextLabel", {
            Size = UDim2.new(1, 0, 0, 16),
            BackgroundTransparency = 1,
            Font = Enum.Font.Code,
            TextSize = 12,
            TextColor3 = Theme.Desc,
            TextXAlignment = Enum.TextXAlignment.Left,
            Text = t,
            ZIndex = 41,
        }, SettingsPanel)
    end

    addSettingLabel("Toggle Key: RightShift")
    addSettingLabel("Mobile: Drag diamond")
    addSettingLabel("Theme: Dark Blue")

    local unloadBtn = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 26),
        BackgroundColor3 = Theme.Danger,
        BorderSizePixel = 0,
        Font = Enum.Font.Code,
        TextSize = 12,
        TextColor3 = Theme.Cream,
        Text = "Unload UI",
        ZIndex = 41,
    }, SettingsPanel)
    new("UICorner", { CornerRadius = UDim.new(0, 5) }, unloadBtn)
    connect(unloadBtn.MouseButton1Click, UnloadUI)

    connect(GearBtn.MouseButton1Click, function()
        settingsOpen = not settingsOpen
        SettingsPanel.Visible = settingsOpen
    end)

    -- ──────────────────────────────────────────
    -- Reveal after intro
    -- ──────────────────────────────────────────
    task.spawn(function()
        while not introDone and gui.Parent and not unloading do task.wait(0.1) end
        if not gui.Parent or unloading then return end
        if Config.StartOpen ~= false then
            SetWindowOpen(true)
            self:Notify({
                Title = "Ready",
                Description = isMobile() and "Tap the diamond to toggle." or "RightShift or diamond button to toggle.",
                Duration = 3.5,
            })
        end
    end)

    -- Public API
    WindowAPI.Main = Main
    WindowAPI.Notify = function(_, ...) return self:Notify(...) end
    WindowAPI.SetVisible = SetWindowOpen
    WindowAPI.Unload = UnloadUI
    WindowAPI.SetPageTransition = function(_, style)
        style = tostring(style or "")
        if validPageTransitions[style] then
            PageTransitionStyle = style
            return true
        end
        return false
    end
    WindowAPI.SetOutroStyle = function(_, style)
        style = tostring(style or "")
        if validOutroStyles[style] then
            OutroStyle = style
            return true
        end
        return false
    end
    WindowAPI.UnlockAchievement = function(_, id) return Library:UnlockAchievement(id) end
    WindowAPI.RegisterAchievement = function(_, id, data) return Library:RegisterAchievement(id, data) end

    return WindowAPI
end

return Library
