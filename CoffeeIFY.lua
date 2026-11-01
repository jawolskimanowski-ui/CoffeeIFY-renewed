-- UILibrary optional customization points:
--   Library:RegisterExtension("Name", function(window, library) ... end)
--   Config.Extensions = { "Name" }                 -- opt-in registered add-on
--   category:CreateSection / CreateParagraph       -- reusable information blocks
--   category:CreateBadge / CreateProgressBar       -- status and progress widgets
--   category:CreateActionCard / CreateCustomFrame  -- custom controls and layouts
--   window:SetThemeColor("Accent", Color3.fromRGB(...))
-- Optional layout:
--   local layout = { ify = "1" }
--   layout.ify = "2"
--   local window = Library:CreateWindow("Lucent", { layout = layout })
-- Layout defaults. Set Library.layout.ify to "2" for a two-column window,
-- or pass Config.layout = { ify = "2" } to configure a single window.
--[[
CHANGELOG (compared with the original UILibrary.lua)

- Enhanced: delayed drag handling, draggable notification cards, optional theme
  gradients/direction, persisted drag/gradient preferences, and public setters.
- Extensible: opt-in extension registry, themed helper components, and theme
  color getter/setter support.
- Two-column: layout.ify supports "1" (original) and "2" (balanced columns),
  with compact control layouts and responsive fallback.
- Settings fix: Settings is built synchronously and ClearItems preserves the
  two-column containers when controls are rebuilt.
- Current: Settings and the internal Hello page are pinned to column 1; Hello
  is built synchronously and contains the visible changelog.

The original UILibrary.lua and UILibrary_original.lua were byte-identical.
The temporary SettingsRestored.lua is the single-column settings-timing branch;
TwoColumn_SettingsFixed.lua is the two-column branch used for this build.
]]

local Library = {}
Library.layout = Library.layout or { ify = "1" }
function Library:SetLayoutMode(value)
    self.layout = type(self.layout) == "table" and self.layout or {}
    self.layout.ify = tostring(value) == "2" and "2" or "1"
    return self.layout.ify
end

local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local ConfigFileName = "UI_Config.json"
local EnableSave = true

local Flags = {}
local ThemeSettings = {}

-- Built-in defaults keep the library functional even when the optional Nier
-- sound pack cannot be fetched or compiled.
Library.SoundEnabled = true
Library.SoundVolume = 1
function Library:SetSoundEnabled(state)
    self.SoundEnabled = state == true
end
function Library:SetSoundVolume(value)
    local volume = tonumber(value)
    if not volume or volume ~= volume then
        return false
    end
    self.SoundVolume = math.clamp(volume, 0, 1)
    return true
end

-- Optional extension registry.
-- Register an add-on once, then opt into it per window with Config.Extensions.
-- Extensions are never executed unless the user explicitly enables them.
Library.Extensions = Library.Extensions or {}

function Library:RegisterExtension(name, callback)
    if type(name) ~= "string" or name == "" or type(callback) ~= "function" then
        return false, "RegisterExtension expects a non-empty name and a function."
    end
    self.Extensions[name] = callback
    return true
end

function Library:UnregisterExtension(name)
    if type(name) ~= "string" or self.Extensions[name] == nil then
        return false
    end
    self.Extensions[name] = nil
    return true
end

function Library:GetExtension(name)
    return type(name) == "string" and self.Extensions[name] or nil
end

--[[
OPTIONAL EXTENSION EXAMPLE

Library:RegisterExtension("StatusPanel", function(window, library)
    local tab = window:CreateCategory("EXTRAS", "lucide-sparkles")
    tab:CreateSection("Extra tools", "Only appears when this extension is enabled.")
    tab:CreateParagraph("About", "Use these helpers to build optional UI without editing core controls.")
    tab:CreateBadge("Extension", "ACTIVE")
end)

local window = Library:CreateWindow("My UI", {
    Extensions = { "StatusPanel" },
})

You can also pass a direct callback in Config.Extensions:
    Extensions = { function(window, library) ... end }
]]

local WHITE = Color3.new(1, 1, 1)

local function getExecutorFunction(name)
    local ok, value = pcall(function()
        return _G and _G[name] or nil
    end)
    if ok and type(value) == "function" then
        return value
    end

    ok, value = pcall(function()
        return getfenv and getfenv(0)[name] or nil
    end)
    if ok and type(value) == "function" then
        return value
    end

    local getgenvFunction
    ok, getgenvFunction = pcall(function()
        return (_G and _G.getgenv) or (getfenv and getfenv(0) and getfenv(0).getgenv)
    end)
    if ok and type(getgenvFunction) == "function" then
        local envOk, env = pcall(getgenvFunction)
        if envOk and type(env) == "table" and type(env[name]) == "function" then
            return env[name]
        end
    end
    return nil
end

local function fileApiReady()
    return getExecutorFunction("writefile") ~= nil
    and getExecutorFunction("readfile") ~= nil
    and getExecutorFunction("isfile") ~= nil
end

local function SaveConfig(frame)
    if not EnableSave or not frame or not fileApiReady() then
        return
    end
    local camera = workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(1920, 1080)
    local pos = frame.AbsolutePosition
    local baseSize = frame.Size
    local absoluteSize = frame.AbsoluteSize

    local data = {
        Width = baseSize.X.Scale == 0 and baseSize.X.Offset or absoluteSize.X,
        Height = baseSize.Y.Scale == 0 and baseSize.Y.Offset or absoluteSize.Y,
    }
if pos.X < 0 or pos.Y < 0 or pos.X + absoluteSize.X > viewport.X or pos.Y + absoluteSize.Y > viewport.Y then
    data.PosScaleX, data.PosScaleY = 0.5, 0.5
    data.PosX = -(baseSize.X.Offset / 2)
    data.PosY = -(baseSize.Y.Offset / 2)
else

    data.PosScaleX, data.PosScaleY = frame.Position.X.Scale, frame.Position.Y.Scale
    data.PosX, data.PosY = frame.Position.X.Offset, frame.Position.Y.Offset
end

data.Flags = {}
for name, flag in pairs(Flags) do
    data.Flags[name] = flag.Value
end
data.Theme = ThemeSettings

local ok, json = pcall(function()
    return HttpService:JSONEncode(data)
end)
if ok then
    local write = getExecutorFunction("writefile")
    if write then
        pcall(write, ConfigFileName, json)
    end
end
end

local function LoadConfig()
    if not EnableSave or not fileApiReady() then
        return
    end
    local isFile = getExecutorFunction("isfile")
    local read = getExecutorFunction("readfile")
    if not isFile or not read then
        return
    end
    local existsOk, exists = pcall(isFile, ConfigFileName)
    if not existsOk or not exists then
        return
    end
    local ok, content = pcall(read, ConfigFileName)
    if not ok or not content then
        return
    end
    local ok2, data = pcall(function()
        return HttpService:JSONDecode(content)
    end)
    if ok2 and type(data) == "table" and data.Width and data.Height then
        local size = UDim2.fromOffset(data.Width, data.Height)
        local pos
        if data.PosX ~= nil and data.PosY ~= nil then
            pos = UDim2.new(
            tonumber(data.PosScaleX) or 0,
            tonumber(data.PosX) or 0,
            tonumber(data.PosScaleY) or 0,
            tonumber(data.PosY) or 0
            )
        end
        return size, pos, data.Flags, data.Theme
    end
end

local Icons = {}
local ICON_URL = "https://github.com/PMLOLHUB/assets-library-/raw/refs/heads/main/Icon"

do
    local okSource, source = pcall(function()
        return game:HttpGet(ICON_URL)
    end)

    if okSource and type(source) == "string" and source ~= "" then
        local compiler = getExecutorFunction("loadstring")
        if not compiler then
            local ok, value = pcall(function() return loadstring end)
            if ok and type(value) == "function" then
                compiler = value
            end
        end

        if compiler then
            local okChunk, chunk = pcall(compiler, source)
            if okChunk and type(chunk) == "function" then
                local okIcons, remoteIcons = pcall(chunk)
                if okIcons and type(remoteIcons) == "table" then
                    Icons = remoteIcons
                end
            end
        end
    end
end

Library.Icons = Icons

local function resolveIcon(name)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    if string.find(name, "rbxassetid://", 1, true) then
        return name
    end
    return Icons[name]
end

local Translations = {
    en = {
        PresetHeader = "Preset Themes",
        PresetLabel = "Choose a Preset Theme",
        TransparencyLabel = "Transparency (%)",
        OverallScaleLabel = "Overall UI Scale (%)",
        ToggleButtonScaleLabel = "Toggle Button Size (%)",
        ToggleKeyLabel = "Toggle Key",
        PressKey = "Press a key... (Esc = cancel)",
        MobileStyleLabel = "ui Button",
        SoundVolumeLabel = "Sound Volume (%)",
        PageAnimationLabel = "Page Transition",
        OpenCloseAnimationLabel = "Window",
    },
th = {
    PresetHeader = "ธีมสำเร็จรูป",
    PresetLabel = "เลือกธีมสำเร็จรูป",
    TransparencyLabel = "ความโปร่งแสง (%)",
    OverallScaleLabel = "ขนาด UI โดยรวม (%)",
    ToggleButtonScaleLabel = "ขนาดปุ่มเปิด/ปิด (%)",
    ToggleKeyLabel = "ปุ่มเปิด/ปิด",
    PressKey = "กดปุ่มบนคีย์บอร์ด... (Esc = ยกเลิก)",
    MobileStyleLabel = "รูปแบบปุ่มเปิด/ปิด (มือถือ)",
    SoundVolumeLabel = "ระดับเสียง (%)",
    PageAnimationLabel = "สไตล์แอนิเมชันเปลี่ยนหน้า",
    OpenCloseAnimationLabel = "สไตล์แอนิเมชันเปิด / ปิด UI",
},
}

local Presets = {
    Paper = { Paper = { 204, 198, 174 }, Row = { 172, 166, 149 }, Input = { 226, 220, 198 }, Accent = { 54, 50, 44 }, Ink = { 72, 66, 52 }, Cream = { 252, 248, 220 }, Line = { 158, 152, 129 }, Team = { 120, 110, 80 } },
    Dusk = { Paper = { 196, 184, 170 }, Row = { 172, 158, 144 }, Input = { 228, 216, 204 }, Accent = { 70, 52, 58 }, Ink = { 70, 54, 56 }, Cream = { 244, 232, 222 }, Line = { 150, 134, 124 }, Team = { 150, 90, 100 } },
    Moss = { Paper = { 198, 202, 176 }, Row = { 172, 178, 148 }, Input = { 224, 230, 200 }, Accent = { 46, 60, 44 }, Ink = { 52, 64, 48 }, Cream = { 236, 242, 218 }, Line = { 146, 154, 124 }, Team = { 90, 130, 80 } },
    Gold = { Paper = { 222, 205, 158 }, Row = { 204, 181, 123 }, Input = { 244, 232, 194 }, Accent = { 132, 91, 20 }, Ink = { 86, 62, 24 }, Cream = { 255, 247, 215 }, Line = { 184, 151, 79 }, Team = { 218, 165, 32 } },
    Sakura = { Paper = { 236, 208, 212 }, Row = { 214, 184, 190 }, Input = { 248, 230, 232 }, Accent = { 92, 52, 62 }, Ink = { 96, 56, 66 }, Cream = { 255, 244, 244 }, Line = { 190, 150, 158 }, Team = { 200, 100, 120 } },
    Lavender = { Paper = { 212, 204, 230 }, Row = { 184, 174, 210 }, Input = { 234, 228, 246 }, Accent = { 58, 46, 90 }, Ink = { 66, 54, 98 }, Cream = { 248, 244, 255 }, Line = { 164, 152, 194 }, Team = { 130, 100, 190 } },
    Graphite = { Paper = { 36, 38, 42 }, Row = { 52, 55, 60 }, Input = { 24, 25, 28 }, Accent = { 206, 116, 40 }, Ink = { 236, 238, 242 }, Cream = { 250, 250, 252 }, Line = { 76, 80, 88 }, Team = { 240, 150, 60 } },
    Forest = { Paper = { 16, 32, 22 }, Row = { 26, 52, 36 }, Input = { 10, 21, 14 }, Accent = { 46, 140, 78 }, Ink = { 226, 246, 230 }, Cream = { 242, 255, 244 }, Line = { 50, 92, 64 }, Team = { 120, 220, 130 } },
    Matrix = { Paper = { 6, 14, 8 }, Row = { 12, 30, 16 }, Input = { 3, 8, 4 }, Accent = { 0, 150, 52 }, Ink = { 150, 255, 170 }, Cream = { 214, 255, 224 }, Line = { 20, 84, 36 }, Team = { 0, 255, 90 } },
    Twilight = { Paper = { 30, 16, 36 }, Row = { 50, 28, 60 }, Input = { 19, 10, 23 }, Accent = { 190, 84, 146 }, Ink = { 250, 230, 246 }, Cream = { 255, 242, 252 }, Line = { 104, 56, 112 }, Team = { 255, 150, 200 } },
    Cyberpunk = { Paper = { 16, 12, 28 }, Row = { 32, 20, 52 }, Input = { 9, 7, 18 }, Accent = { 210, 30, 140 }, Ink = { 236, 226, 255 }, Cream = { 250, 240, 255 }, Line = { 84, 40, 116 }, Team = { 255, 222, 40 } },
    Sunset = { Paper = { 34, 18, 32 }, Row = { 58, 30, 48 }, Input = { 22, 11, 20 }, Accent = { 220, 92, 78 }, Ink = { 255, 230, 220 }, Cream = { 255, 240, 230 }, Line = { 110, 56, 84 }, Team = { 255, 170, 90 } },
    Ember = { Paper = { 26, 18, 16 }, Row = { 48, 30, 26 }, Input = { 16, 10, 9 }, Accent = { 206, 84, 32 }, Ink = { 252, 232, 220 }, Cream = { 255, 244, 234 }, Line = { 96, 56, 46 }, Team = { 255, 140, 60 } },
    Obsidian = { Paper = { 18, 18, 20 }, Row = { 32, 32, 36 }, Input = { 10, 10, 12 }, Accent = { 150, 150, 162 }, Ink = { 235, 235, 240 }, Cream = { 250, 250, 252 }, Line = { 62, 62, 70 }, Team = { 230, 230, 236 } },
    Noir = { Paper = { 12, 12, 12 }, Row = { 26, 24, 22 }, Input = { 6, 6, 6 }, Accent = { 176, 138, 54 }, Ink = { 240, 232, 214 }, Cream = { 252, 246, 232 }, Line = { 70, 62, 48 }, Team = { 222, 184, 80 } },
    Olive = { Paper = { 24, 26, 14 }, Row = { 42, 46, 24 }, Input = { 15, 17, 8 }, Accent = { 112, 126, 36 }, Ink = { 240, 244, 220 }, Cream = { 252, 255, 236 }, Line = { 80, 88, 44 }, Team = { 186, 204, 70 } },
    Wine = { Paper = { 32, 12, 24 }, Row = { 56, 22, 42 }, Input = { 20, 7, 15 }, Accent = { 150, 32, 80 }, Ink = { 250, 226, 236 }, Cream = { 255, 240, 246 }, Line = { 100, 42, 72 }, Team = { 230, 90, 140 } },
    Crimson = { Paper = { 28, 14, 18 }, Row = { 50, 24, 30 }, Input = { 18, 8, 11 }, Accent = { 190, 36, 60 }, Ink = { 250, 228, 230 }, Cream = { 255, 242, 242 }, Line = { 104, 44, 54 }, Team = { 255, 90, 110 } },
    Amethyst = { Paper = { 26, 18, 40 }, Row = { 44, 32, 68 }, Input = { 16, 11, 26 }, Accent = { 140, 90, 220 }, Ink = { 240, 230, 255 }, Cream = { 248, 242, 255 }, Line = { 88, 66, 128 }, Team = { 190, 140, 255 } },
    Mocha = { Paper = { 30, 22, 18 }, Row = { 52, 38, 30 }, Input = { 19, 13, 10 }, Accent = { 168, 118, 72 }, Ink = { 250, 236, 220 }, Cream = { 255, 246, 232 }, Line = { 96, 72, 54 }, Team = { 222, 170, 110 } },
    Christmas = { Paper = { 24, 52, 38 }, Row = { 36, 72, 54 }, Input = { 15, 36, 27 }, Accent = { 214, 40, 48 }, Ink = { 244, 248, 238 }, Cream = { 255, 250, 238 }, Line = { 74, 118, 92 }, Team = { 255, 214, 92 } },
    Halloween = { Paper = { 28, 20, 32 }, Row = { 48, 30, 48 }, Input = { 18, 13, 23 }, Accent = { 255, 112, 28 }, Ink = { 245, 221, 255 }, Cream = { 255, 239, 214 }, Line = { 112, 62, 102 }, Team = { 173, 255, 66 } },
}
-- Ordered by tone: light themes, then dark themes grouped by hue, special themes last.
local PresetOrder = { "Paper", "Gold", "Dusk", "Sakura", "Lavender", "Moss", "Obsidian", "Graphite", "Noir", "Forest", "Olive", "Matrix", "Twilight", "Amethyst", "Cyberpunk", "Wine", "Crimson", "Sunset", "Ember", "Mocha", "Halloween", "Christmas" }
Library.Presets = Presets

local FontPresets = {}
for _, fontEnum in ipairs(Enum.Font:GetEnumItems()) do
    local name = fontEnum.Name
    local okBold, boldEnum = pcall(function()
        return Enum.Font[name .. "Bold"]
    end)
    FontPresets[name] = { Regular = fontEnum, Bold = (okBold and boldEnum) or fontEnum }
end

local function new(class, props, parent)
    local inst = Instance.new(class)
    for k, v in pairs(props) do
        inst[k] = v
    end
    if parent then
        inst.Parent = parent
    end

    if Library._onNew then
        Library._onNew(inst, class, props)
    end
    return inst
end

local function tw(inst, dur, props)
    if not dur or dur <= 0 then
        for k, v in pairs(props) do
            inst[k] = v
        end
        return
    end
    TweenService:Create(inst, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

local function c3(t)
    return Color3.fromRGB(t[1], t[2], t[3])
end

local function arr(c)
    return { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) }
end

local function isPointer(input)
    return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function isMove(input)
    return input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch
end

local function joinList(list)
    local t = {}
    for i, v in ipairs(list) do
        t[i] = tostring(v)
    end
    return table.concat(t, ", ")
end

local function toHex(c)
    local function b(n)
        return string.format("%02X", math.clamp(math.floor(n * 255 + 0.5), 0, 255))
    end
    return "#" .. b(c.R) .. b(c.G) .. b(c.B)
end

function Library:CreateWindow(WindowName, Config)
    Config = Config or {}

    local suppliedLayout = type(Config.layout) == "table" and Config.layout
        or (type(Config.Layout) == "table" and Config.Layout)
        or Library.layout
    local layout = {
        ify = tostring(suppliedLayout.ify or suppliedLayout.Ify or "1"),
        Gap = math.clamp(tonumber(suppliedLayout.Gap or suppliedLayout.gap) or 14, 6, 28),
        Responsive = suppliedLayout.Responsive ~= false and suppliedLayout.responsive ~= false,
    }
    if layout.ify ~= "2" then layout.ify = "1" end

    local ToggleConfig = Config.ToggleConfig or {}
    local isFirstTab = true
    local KeySystemEnabled = Config.KeySystem == true
    local KeyAuthenticated = not KeySystemEnabled
    local KeyFailClicks = 0
    local KeySystemConfig = type(Config.KeySystemConfig) == "table" and Config.KeySystemConfig or {}
    local ExpectedKey = tostring(KeySystemConfig.Key or KeySystemConfig.ExpectedKey or "KEY")
    local KeyNote = KeySystemConfig.Note or "Enter the access key to unlock categories."

    local connections = {}
    local function connect(signal, fn)
        local c = signal:Connect(fn)
        table.insert(connections, c)
        return c
    end

    local Theme = {}
    local function loadPreset(p)
        for token, v in pairs(p) do
            Theme[token] = c3(v)
        end
    end
    loadPreset(Presets.Paper)
    if type(Config.Theme) == "string" and Presets[Config.Theme] then
        loadPreset(Presets[Config.Theme])
    end
    local function cfgColor(key, token)
        if typeof(Config[key]) == "Color3" then
            Theme[token] = Config[key]
        end
    end
    cfgColor("BackgroundColor", "Paper")
    cfgColor("ElementColor", "Row")
    cfgColor("ButtonColor", "Row")
    cfgColor("InputColor", "Input")
    cfgColor("ThemeColor", "Accent")
    cfgColor("CategoryColor", "Accent")
    cfgColor("TextColor", "Ink")
    cfgColor("TeamColor", "Team")

    local GTrans = math.clamp(tonumber(Config.ElementTransparency) or 0.08, 0, 0.9)
    local DragDelayMs = math.clamp(tonumber(Config.DragDelayMs or Config.DragDelay) or 140, 0, 600)
    local GradientEffectsEnabled = Config.GradientEffects == true
    local GradientDirectionOrder = { "Diagonal", "Horizontal", "Vertical" }
    local GradientDirection = "Diagonal"
    local FontScale = math.clamp(tonumber(Config.FontScale) or 1, 0.75, 1.35)
    local OverallScalePercent = math.clamp(tonumber(Config.OverallScale) or 100, 70, 130)
    local ToggleButtonScalePercent = math.clamp(tonumber(Config.ToggleButtonScale) or 100, 50, 180)
    local mainUIScale, stripUIScale, toggleUIScale
    local FontFamily = (Config.FontFamily and FontPresets[Config.FontFamily]) and Config.FontFamily or "Gotham"
    local Language = "en"
    local cfgLang = Config.Language and string.lower(tostring(Config.Language))
    if cfgLang == "th" or cfgLang == "thai" then
        Language = "th"
    end

    -- Page Transition Style: Pop + 3 other styles
    --   Pop        : the page scales up from its center with a soft Back overshoot while rows fade in
    --   Cascade    : rows fade in one after another while the page slides in from the left
    --   Glitch     : page jitters in and the text scrambles with a glitch shake
    --   Slide Left : the whole page slides in from the right while rows fade in
    local PageAnimationOrder = { "Pop", "Cascade", "Glitch", "Slide Left" }

    -- Window Open / Close Style: all options use the same strip-wipe animation family.
    --   Shutter       : straight vertical bars with a centered collapse
    --   Slash         : wide diagonal bars angled upward
    --   Pinstripe     : thin vertical bars with a quicker stagger
    --   Reverse Slash : wide diagonal bars angled in the opposite direction
    --   Crosscut      : alternating diagonal bars for a crossed-strip effect
    local OpenCloseAnimationOrder = { "Classic", "Shutter", "Pinstripe", "Crosscut" }

    local function containsOption(options, value)
        for _, option in ipairs(options) do
            if option == value then return true end
        end
        return false
    end
    local PageAnimation = "Pop"
    local OpenCloseAnimation = "Classic"
    local CurrentPreset = (type(Config.Theme) == "string" and Presets[Config.Theme]) and Config.Theme or "Paper"
    local BorderEnabled = Config.BorderEnabled ~= false
    local BgImage = Config.BackgroundImage or ""
    local BgImageTransparency = math.clamp(tonumber(Config.BackgroundImageTransparency) or 0.5, 0, 1)
    local BgImageEnabled = BgImage ~= ""
    if Config.BackgroundImageEnabled ~= nil then
        BgImageEnabled = Config.BackgroundImageEnabled
    end

    local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
    local MobileStyleOrder = { "Classic", "Circle", "Diamond", "Pill", "Bracket" }
    local function validStyle(name)
        for _, n in ipairs(MobileStyleOrder) do
            if n == name then return true end
        end
        return false
    end
    local MobileStyle = validStyle(Config.MobileButtonStyle) and Config.MobileButtonStyle or "Classic"

    local toggleKey = Config.ToggleKey
    if toggleKey == nil then
        toggleKey = Enum.KeyCode.RightShift
    end
    local listeningKey = false

    local savedSize, savedPos, savedFlags, savedTheme = LoadConfig()
    if type(savedTheme) == "table" then
        if validStyle(savedTheme.MobileStyle) then MobileStyle = savedTheme.MobileStyle end
        if type(savedTheme.PresetName) == "string" and Presets[savedTheme.PresetName] then CurrentPreset = savedTheme.PresetName end
        if containsOption(PageAnimationOrder, savedTheme.PageAnimation) then PageAnimation = savedTheme.PageAnimation end
        if containsOption(OpenCloseAnimationOrder, savedTheme.OpenCloseAnimation) then OpenCloseAnimation = savedTheme.OpenCloseAnimation end
        if toggleKey ~= false and type(savedTheme.ToggleKey) == "string" then
            local okK, keyEnum = pcall(function()
                return Enum.KeyCode[savedTheme.ToggleKey]
            end)
            if okK and keyEnum then toggleKey = keyEnum end
        end
        if type(savedTheme.Colors) == "table" then
            for token, v in pairs(savedTheme.Colors) do
                if Theme[token] and type(v) == "table" and v[3] then
                    Theme[token] = c3(v)
                end
            end
        end
        if savedTheme.Transparency ~= nil then GTrans = savedTheme.Transparency end
        if savedTheme.FontScale ~= nil then
            FontScale = math.clamp(tonumber(savedTheme.FontScale) or 1, 0.75, 1.35)
        end
        if savedTheme.OverallScalePercent ~= nil then
            OverallScalePercent = math.clamp(tonumber(savedTheme.OverallScalePercent) or 100, 70, 130)
        end
        if savedTheme.ToggleButtonScalePercent ~= nil then
            ToggleButtonScalePercent = math.clamp(tonumber(savedTheme.ToggleButtonScalePercent) or 100, 50, 180)
        end
        if savedTheme.FontFamily and FontPresets[savedTheme.FontFamily] then FontFamily = savedTheme.FontFamily end
        if savedTheme.Language == "th" or savedTheme.Language == "en" then Language = savedTheme.Language end
        if savedTheme.BorderEnabled ~= nil then BorderEnabled = savedTheme.BorderEnabled end
        if savedTheme.BackgroundImage ~= nil then BgImage = savedTheme.BackgroundImage end
        if savedTheme.BackgroundImageTransparency ~= nil then
            BgImageTransparency = math.clamp(tonumber(savedTheme.BackgroundImageTransparency) or 0.5, 0, 1)
        end
        if savedTheme.BackgroundImageEnabled ~= nil then BgImageEnabled = savedTheme.BackgroundImageEnabled end
        if savedTheme.SoundVolume ~= nil then
            Library.SoundVolume = math.clamp(tonumber(savedTheme.SoundVolume) or 1, 0, 1)
        end
        if savedTheme.DragDelayMs ~= nil then
            DragDelayMs = math.clamp(tonumber(savedTheme.DragDelayMs) or 140, 0, 600)
        end
        if savedTheme.GradientEffects ~= nil then
            GradientEffectsEnabled = savedTheme.GradientEffects == true
        end
        if containsOption(GradientDirectionOrder, savedTheme.GradientDirection) then
            GradientDirection = savedTheme.GradientDirection
        end
    end
    local SavedFlags = savedFlags or {}

    local themed, lookers, glass, fontObjects = {}, {}, {}, {}
    local gradientObjects = {}

    local function resolve(spec)
        if type(spec) == "function" then
            return spec(Theme)
        end
        return Theme[spec]
    end
    local function bind(inst, prop, spec)
        inst[prop] = resolve(spec)
        table.insert(themed, { inst, prop, spec })
        return inst
    end
    local function refreshTheme()
        for i = #themed, 1, -1 do
            local e = themed[i]
            if e[1].Parent == nil then
                table.remove(themed, i)
            else
                e[1][e[2]] = resolve(e[3])
            end
        end
        for i = #lookers, 1, -1 do
            local l = lookers[i]
            if l.row.Parent == nil then
                table.remove(lookers, i)
            else
                l.fn(false)
            end
        end
    end

    local function applyFont(inst, size, bold)
        local preset = FontPresets[FontFamily] or FontPresets.Gotham
        inst.Font = bold and preset.Bold or preset.Regular
        inst.TextSize = math.floor(size * FontScale + 0.5)
    end
    local function bindFont(inst, size, bold)
        applyFont(inst, size, bold)
        table.insert(fontObjects, { instance = inst, size = size, bold = bold })
    end

    local function bindGlass(inst)
        inst.BackgroundTransparency = GTrans
        table.insert(glass, inst)
    end

    local GradientAngles = { Diagonal = 35, Horizontal = 0, Vertical = 90 }
    local function makeGradientSequence(baseColor, targetColor)
        local function channel(target, base)
            return math.clamp(target / math.max(base, 0.025), 0, 1)
        end
        local tint = Color3.new(
            channel(targetColor.R, baseColor.R),
            channel(targetColor.G, baseColor.G),
            channel(targetColor.B, baseColor.B)
        )
        return ColorSequence.new(Color3.new(1, 1, 1), tint)
    end

    local function applyGradientSettings()
        local baseAngle = GradientAngles[GradientDirection] or GradientAngles.Diagonal
        for index = #gradientObjects, 1, -1 do
            local entry = gradientObjects[index]
            local gradient = entry.object
            if not gradient or gradient.Parent == nil then
                table.remove(gradientObjects, index)
            else
                gradient.Enabled = GradientEffectsEnabled
                gradient.Rotation = baseAngle
            end
        end
    end

    local function addGradient(parent, colorProvider)
        local gradient = new("UIGradient", {
            Rotation = GradientAngles[GradientDirection] or GradientAngles.Diagonal,
            Enabled = GradientEffectsEnabled,
        }, parent)
        bind(gradient, "Color", colorProvider)
        table.insert(gradientObjects, { object = gradient })
        applyGradientSettings()
        return gradient
    end

    local function setGradientEffects(enabled)
        GradientEffectsEnabled = enabled == true
        applyGradientSettings()
        return GradientEffectsEnabled
    end

    local function setGradientDirection(direction)
        if not containsOption(GradientDirectionOrder, direction) then
            return false
        end
        GradientDirection = direction
        applyGradientSettings()
        return true
    end

    local function setDragDelay(milliseconds)
        local value = tonumber(milliseconds)
        if not value or value ~= value then
            return false
        end
        DragDelayMs = math.clamp(math.floor(value + 0.5), 0, 600)
        return true
    end

local function makeRaiseController(root, raisedScale)
    local originalZ = {}
    local scale = new("UIScale", { Scale = 1 }, root)
    local function setRaised(raised, animate)
        local offset = raised and 28 or 0
        local targets = { root }
        for _, descendant in ipairs(root:GetDescendants()) do
            table.insert(targets, descendant)
        end
        for _, object in ipairs(targets) do
            if object:IsA("GuiObject") then
                if originalZ[object] == nil then originalZ[object] = object.ZIndex end
                object.ZIndex = originalZ[object] + offset
            end
        end
        if scale.Parent then
            local targetScale = raised and (raisedScale or 1.04) or 1
            if animate then
                TweenService:Create(scale, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = targetScale }):Play()
            else
                scale.Scale = targetScale
            end
        end
    end
    return setRaised
end

    local function setGlass(t)
        GTrans = math.clamp(t, 0, 0.9)
        for i = #glass, 1, -1 do
            if glass[i].Parent == nil then
                table.remove(glass, i)
            else
                glass[i].BackgroundTransparency = GTrans
            end
        end
    end

    local function inputColor(t)
        return t.Input
    end
    local function listColor(t)
        return t.Row:Lerp(t.Paper, 0.5)
    end
    local function dimInk(t)
        return t.Ink:Lerp(t.Paper, 0.45)
    end

    -- Singleton guard: remove the previous copy before creating this one.
    -- The registry covers executor reloads; root scanning covers older builds
    -- that predate the registry attribute.
    local singletonEnv
    do
        local getgenvFunction = getExecutorFunction("getgenv")
        if getgenvFunction then
            local ok, env = pcall(getgenvFunction)
            if ok and type(env) == "table" then singletonEnv = env end
        end
        if not singletonEnv then
            local ok, env = pcall(function() return _G end)
            if ok and type(env) == "table" then singletonEnv = env end
        end

        if singletonEnv then
            local previous = rawget(singletonEnv, "__UILibrary_MainUI")
            if typeof(previous) == "Instance" then
                pcall(function() previous:Destroy() end)
            end
        end

        local roots = {}
        local function addRoot(root)
            if not root then return end
            for _, existing in ipairs(roots) do
                if existing == root then return end
            end
            table.insert(roots, root)
        end
        local getHiddenUI = getExecutorFunction("gethui")
        if getHiddenUI then
            local ok, hiddenUI = pcall(getHiddenUI)
            if ok then addRoot(hiddenUI) end
        end
        local okCore, coreGui = pcall(function() return game:GetService("CoreGui") end)
        if okCore then addRoot(coreGui) end
        local okPlayer, playerGui = pcall(function()
            return LocalPlayer and (LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 2))
        end)
        if okPlayer then addRoot(playerGui) end

        for _, root in ipairs(roots) do
            for _, child in ipairs(root:GetChildren()) do
                if child:IsA("ScreenGui") and (child.Name == "MainUI" or child:GetAttribute("UILibraryManaged") == "CoffeeIFY") then
                    pcall(function() child:Destroy() end)
                end
            end
        end
    end

    local gui = new("ScreenGui", {
        Name = "MainUI",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = Config.DisplayOrder or 999,
    })
    gui:SetAttribute("UILibraryManaged", "CoffeeIFY")
    if singletonEnv then
        pcall(function() rawset(singletonEnv, "__UILibrary_MainUI", gui) end)
    end
    gui.Destroying:Connect(function()
        for _, connection in ipairs(connections) do
            pcall(function() connection:Disconnect() end)
        end
        pcall(function()
            local introBlur = game:GetService("Lighting"):FindFirstChild("IntroBlur")
            if introBlur then introBlur:Destroy() end
        end)
        if singletonEnv then
            pcall(function()
                if rawget(singletonEnv, "__UILibrary_MainUI") == gui then
                    rawset(singletonEnv, "__UILibrary_MainUI", nil)
                end
            end)
        end
    end)

do
    local placed = false
    local getHiddenUI = getExecutorFunction("gethui")
    if getHiddenUI then
        local ok, hiddenUI = pcall(getHiddenUI)
        if ok and hiddenUI then
            placed = pcall(function()
                gui.Parent = hiddenUI
            end) and gui.Parent ~= nil
        end
    end

    if not placed then
        local ok, coreGui = pcall(function()
            return game:GetService("CoreGui")
        end)
        if ok and coreGui then
            placed = pcall(function()
                gui.Parent = coreGui
            end) and gui.Parent ~= nil
        end
    end

    if not placed then
        local ok, playerGui = pcall(function()
            return LocalPlayer and (LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 10))
        end)
        if ok and playerGui then
            placed = pcall(function()
                gui.Parent = playerGui
            end) and gui.Parent ~= nil
        end
    end

    if not placed then
        error("[UI] Unable to parent ScreenGui. This executor may restrict GUI access.")
    end
end

local camera = workspace.CurrentCamera
local vp = camera and camera.ViewportSize or Vector2.new(1280, 720)
local defaultWidth = layout.ify == "2" and 760 or 580
local startSize = savedSize or UDim2.fromOffset(math.min(defaultWidth, math.floor(vp.X * 0.94)), math.min(330, math.floor(vp.Y * 0.8)))
local startPos = savedPos or UDim2.new(0.5, -startSize.X.Offset / 2, 0.5, -startSize.Y.Offset / 2)

local main = new("Frame", {
    Name = "MainFrame",
    Size = startSize,
    Position = startPos,
    BorderSizePixel = 0,
    ClipsDescendants = true,
    Visible = false,
}, gui)
mainUIScale = new("UIScale", { Scale = OverallScalePercent / 100 }, main)
bind(main, "BackgroundColor3", "Paper")
bindGlass(main)
addGradient(main, function(t)
    return makeGradientSequence(t.Paper, t.Paper:Lerp(t.Accent, 0.13))
end)
local mainStroke = new("UIStroke", { Thickness = 1, Enabled = BorderEnabled }, main)
bind(mainStroke, "Color", "Line")

local bgImageLabel = new("ImageLabel", {
    Name = "CustomBackgroundImage",
    BackgroundTransparency = 1,
    Size = UDim2.fromScale(1, 1),
    ZIndex = 0,
    Image = BgImage,
    ImageTransparency = BgImageTransparency,
    ScaleType = Enum.ScaleType.Crop,
    Visible = BgImageEnabled and BgImage ~= "",
}, main)
local function UpdateBackgroundImage(id)
    BgImage = id or ""
    bgImageLabel.Image = BgImage
    bgImageLabel.Visible = BgImageEnabled and BgImage ~= ""
end
local function UpdateBackgroundImageTransparency(t)
    BgImageTransparency = t
    bgImageLabel.ImageTransparency = t
end
local function UpdateBackgroundImageEnabled(state)
    BgImageEnabled = state
    bgImageLabel.Visible = BgImageEnabled and BgImage ~= ""
end

local function persistTheme()
    local colors = {}
    for token, col in pairs(Theme) do
        colors[token] = arr(col)
    end
    ThemeSettings.Colors = colors
    ThemeSettings.PresetName = CurrentPreset
    ThemeSettings.PageAnimation = PageAnimation
    ThemeSettings.OpenCloseAnimation = OpenCloseAnimation
    ThemeSettings.Transparency = GTrans
    ThemeSettings.FontFamily = FontFamily
    ThemeSettings.FontScale = FontScale
    ThemeSettings.Language = Language
    ThemeSettings.BorderEnabled = BorderEnabled
    ThemeSettings.BackgroundImage = BgImage
    ThemeSettings.BackgroundImageTransparency = BgImageTransparency
    ThemeSettings.BackgroundImageEnabled = BgImageEnabled
    ThemeSettings.MobileStyle = MobileStyle
    ThemeSettings.ToggleKey = toggleKey and toggleKey.Name or nil
    ThemeSettings.OverallScalePercent = OverallScalePercent
    ThemeSettings.ToggleButtonScalePercent = ToggleButtonScalePercent
    ThemeSettings.SoundVolume = Library.SoundVolume
    ThemeSettings.DragDelayMs = DragDelayMs
    ThemeSettings.GradientEffects = GradientEffectsEnabled
    ThemeSettings.GradientDirection = GradientDirection
end
persistTheme()
local function save()
    persistTheme()
    SaveConfig(main)
end

local function setFontFamily(name)
    if type(name) ~= "string" or not FontPresets[name] then return false end
    FontFamily = name
    for index = #fontObjects, 1, -1 do
        local entry = fontObjects[index]
        if not entry.instance or entry.instance.Parent == nil then
            table.remove(fontObjects, index)
        else
            applyFont(entry.instance, entry.size, entry.bold)
        end
    end
    persistTheme()
    return true
end

local function setFontScale(percent)
    local value = tonumber(percent)
    if not value or value ~= value then return false end
    FontScale = math.clamp(value / 100, 0.75, 1.35)
    for index = #fontObjects, 1, -1 do
        local entry = fontObjects[index]
        if not entry.instance or entry.instance.Parent == nil then
            table.remove(fontObjects, index)
        else
            applyFont(entry.instance, entry.size, entry.bold)
        end
    end
    persistTheme()
    return true
end

local dragControllers = {}
local activeDragState = nil

local function finishDrag(state, input)
    if state.input ~= input then
        return
    end

    state.input = nil
    state.pending = false
    state.dragging = false
    if activeDragState == state then
        activeDragState = nil
    end
    if state.changedConnection then
        state.changedConnection:Disconnect()
        state.changedConnection = nil
    end

    if state.moved and state.onEnd then
        pcall(state.onEnd)
    end
end

-- One pair of global listeners services every draggable target. This avoids
-- leaving a permanent InputChanged listener behind for each temporary toast.
connect(UserInputService.InputChanged, function(input)
    for _, state in ipairs(dragControllers) do
        if state.input and isMove(input) then
            local pointerType = state.input.UserInputType
            if (pointerType == Enum.UserInputType.Touch and input == state.input)
                or (pointerType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement) then
                state.pointerPosition = input.Position

                if state.dragging and state.dragStart then
                    local delta = state.pointerPosition - state.dragStart
                    if delta.Magnitude > 4 then
                        if not state.moved then
                            state.moved = true
                            if state.onBegin then
                                pcall(state.onBegin)
                            end
                        end

                        local scaleFactor = state.scaleProvider and state.scaleProvider() or 1
                        scaleFactor = math.max(tonumber(scaleFactor) or 1, 0.01)
                        local startPosition = state.startPosition
                        state.target.Position = UDim2.new(
                            startPosition.X.Scale,
                            startPosition.X.Offset + delta.X / scaleFactor,
                            startPosition.Y.Scale,
                            startPosition.Y.Offset + delta.Y / scaleFactor
                        )
                        if state.onMove then
                            pcall(state.onMove, state.target, delta)
                        end
                    end
                end
            end
        end
    end
end)

connect(UserInputService.InputEnded, function(input)
    for _, state in ipairs(dragControllers) do
        if state.input == input then
            finishDrag(state, input)
        end
    end
end)

local function makeDraggable(handle, target, onEnd, scaleProvider, delayProvider, onBegin, onMove)
    target = target or handle
    local state = {
        target = target,
        onEnd = onEnd,
        scaleProvider = scaleProvider,
        onBegin = onBegin,
        onMove = onMove,
        input = nil,
        pending = false,
        dragging = false,
        moved = false,
    }
    table.insert(dragControllers, state)

    local function removeController()
        if state.input then
            state.input = nil
            state.pending = false
            state.dragging = false
            if activeDragState == state then
                activeDragState = nil
            end
            if state.changedConnection then
                state.changedConnection:Disconnect()
                state.changedConnection = nil
            end
        end
        for index = #dragControllers, 1, -1 do
            if dragControllers[index] == state then
                table.remove(dragControllers, index)
                break
            end
        end
    end

    handle.InputBegan:Connect(function(input)
        if not isPointer(input) or state.input or activeDragState then
            return
        end

        activeDragState = state
        state.input = input
        state.pending = true
        state.dragging = false
        state.moved = false
        state.pointerPosition = input.Position
        state.startPosition = target.Position
        state.dragStart = nil

        local delayValue = type(delayProvider) == "function" and delayProvider() or delayProvider
        delayValue = math.clamp(tonumber(delayValue) or 0, 0, 2)
        local function activate()
            if state.input ~= input or not state.pending then
                return
            end
            state.pending = false
            state.dragging = true
            state.dragStart = state.pointerPosition
            state.startPosition = target.Position
        end

        state.changedConnection = input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End or input.UserInputState == Enum.UserInputState.Cancel then
                finishDrag(state, input)
            end
        end)

        if delayValue <= 0 then
            activate()
        else
            task.delay(delayValue, activate)
        end
    end)

    target.Destroying:Connect(removeController)
    if handle ~= target then
        handle.Destroying:Connect(removeController)
    end

    return function()
        return state.moved
    end
end

local function clampGuiToViewport(target)
    if not target or not target.Parent then
        return
    end
    local currentCamera = workspace.CurrentCamera
    local viewport = currentCamera and currentCamera.ViewportSize or Vector2.new(1280, 720)
    local absolutePosition = target.AbsolutePosition
    local absoluteSize = target.AbsoluteSize
    local clampedX = math.clamp(absolutePosition.X, 0, math.max(0, viewport.X - absoluteSize.X))
    local clampedY = math.clamp(absolutePosition.Y, 0, math.max(0, viewport.Y - absoluteSize.Y))
    local offsetX = clampedX - absolutePosition.X
    local offsetY = clampedY - absolutePosition.Y
    if offsetX ~= 0 or offsetY ~= 0 then
        local position = target.Position
        target.Position = UDim2.new(
            position.X.Scale, position.X.Offset + offsetX,
            position.Y.Scale, position.Y.Offset + offsetY
        )
    end
end

local function makeDrag(obj, update, onEnd)
    local dragging = false
    connect(obj.InputBegan, function(input)
        if isPointer(input) then
            dragging = true
            update(input)
        end
    end)
    connect(UserInputService.InputChanged, function(input)
        if dragging and isMove(input) then
            update(input)
        end
    end)
    connect(UserInputService.InputEnded, function(input)
        if dragging and isPointer(input) then
            dragging = false
            if onEnd then
                onEnd()
            end
        end
    end)
end

local TITLE_H = 22
local STRIP_H = 9
local SIDE_W = 0.29
local BODY_TOP = TITLE_H + STRIP_H

local top = new("Frame", { Name = "TopBar", Size = UDim2.new(1, 0, 0, TITLE_H), BorderSizePixel = 0, ZIndex = 3 }, main)
bind(top, "BackgroundColor3", function(t)
    return t.Accent:Lerp(t.Cream, 0.07)
end)
addGradient(top, function(t)
    local base = t.Accent:Lerp(t.Cream, 0.07)
    return makeGradientSequence(base, base:Lerp(t.Paper, 0.22))
end)

local titleX = 24
if Config.Logo and Config.Logo ~= "" then
    new("ImageLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 6, 0.5, -7),
        Size = UDim2.fromOffset(14, 14),
        Image = Config.Logo,
        ZIndex = 4,
    }, top)
titleX = 26
else
    local dia = new("Frame", {
        Position = UDim2.new(0, 8, 0.5, -4),
        Size = UDim2.fromOffset(8, 8),
        Rotation = 45,
        BorderSizePixel = 0,
        ZIndex = 4,
    }, top)
bind(dia, "BackgroundColor3", "Cream")
end

local titleLabel = new("TextLabel", {
    BackgroundTransparency = 1,
    Position = UDim2.new(0, titleX, 0, 0),
    Size = UDim2.new(1, -titleX - 30, 1, 0),
    Text = WindowName or "UI",
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
    ZIndex = 4,
}, top)
bindFont(titleLabel, 12, true)
bind(titleLabel, "TextColor3", "Cream")

local gearBtn = new("ImageButton", {
    Name = "SettingsGearBtn",
    BackgroundTransparency = 1,
    Position = UDim2.new(1, -21, 0.5, -7),
    Size = UDim2.fromOffset(14, 14),
    Image = Icons["lucide-settings"] or "",
    ImageTransparency = 0.45,
    ZIndex = 5,
}, top)
bind(gearBtn, "ImageColor3", "Cream")
local setGearRaised = makeRaiseController(gearBtn, 1.08)
gearBtn.MouseEnter:Connect(function()
    setGearRaised(true, true)
    tw(gearBtn, 0.12, { ImageTransparency = 0 })
    if Library._sfx then Library._sfx("hover") end
end)
gearBtn.MouseLeave:Connect(function()
    setGearRaised(false, true)
    tw(gearBtn, 0.12, { ImageTransparency = 0.45 })
end)
if UserInputService.TouchEnabled then
    local gearTouch
    gearBtn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch then
            gearTouch = input
            setGearRaised(true, true)
            if Library._sfx then Library._sfx("hover") end
        end
    end)
    connect(UserInputService.InputEnded, function(input)
        if gearTouch and input == gearTouch then
            gearTouch = nil
            setGearRaised(false, true)
        end
    end)
end

local function hline(parent, pos, size)
    local f = new("Frame", { Position = pos, Size = size, BorderSizePixel = 0, ZIndex = 2 }, parent)
    bind(f, "BackgroundColor3", "Line")
    return f
end

local function dotStrip(yPos)
    local strip = new("Frame", {
        Name = "DotStrip",
        BackgroundTransparency = 1,
        Position = yPos,
        Size = UDim2.new(1, 0, 0, STRIP_H),
        ClipsDescendants = true,
        ZIndex = 2,
    }, main)
local ln = new("Frame", { Size = UDim2.new(1, 0, 0, 1), BorderSizePixel = 0, BackgroundTransparency = 0.35 }, strip)
bind(ln, "BackgroundColor3", "Line")
local CELL = 22
for i = 0, math.ceil(900 / CELL) do
    local cx = i * CELL + 11
    for _, d in ipairs({ { -3, 3 }, { 3, 3 }, { 0, 6 } }) do
        local dot = new("Frame", {
            Position = UDim2.fromOffset(cx + d[1], d[2]),
            Size = UDim2.fromOffset(1, 1),
            BorderSizePixel = 0,
            BackgroundTransparency = 0.45,
        }, strip)
    bind(dot, "BackgroundColor3", "Ink")
end
end
return strip
end
dotStrip(UDim2.fromOffset(0, TITLE_H))
dotStrip(UDim2.new(0, 0, 1, -STRIP_H))

local decor = new("Frame", {
    Name = "Decor",
    BackgroundTransparency = 1,
    Size = UDim2.fromScale(1, 1),
    ClipsDescendants = true,
    ZIndex = 0,
}, main)
local function decoLine(pos, length, rot)
    local f = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = pos,
        Size = UDim2.fromOffset(length, 1),
        Rotation = rot,
        BorderSizePixel = 0,
        BackgroundTransparency = 0.88,
        ZIndex = 0,
    }, decor)
bind(f, "BackgroundColor3", "Line")
end
local function decoArc(pos, diameter)
    local c = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = pos,
        Size = UDim2.fromOffset(diameter, diameter),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 0,
    }, decor)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, c)
local s = new("UIStroke", { Thickness = 1, Transparency = 0.7 }, c)
bind(s, "Color", "Line")
end
decoLine(UDim2.new(0.26, 0, 0.43, 0), 320, 60)
decoLine(UDim2.new(0.26, 14, 0.43, 0), 320, 60)
decoLine(UDim2.new(0.73, 0, 0.64, 0), 270, 42)
decoLine(UDim2.new(0.8, 20, 0.7, 0), 200, 40)
decoLine(UDim2.new(0.45, 0, 0.28, 0), 180, -25)
decoLine(UDim2.new(0.62, 8, 0.82, 0), 160, 55)
decoArc(UDim2.new(1, 0, 1, -4), 200)
decoArc(UDim2.new(1, 0, 1, -4), 218)

local body = new("Frame", {
    Name = "Body",
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(0, BODY_TOP),
    Size = UDim2.new(1, 0, 1, -(BODY_TOP + STRIP_H)),
}, main)

local Sidebar = new("ScrollingFrame", {
    Name = "Sidebar",
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Size = UDim2.new(SIDE_W, 0, 1, 0),
    ScrollBarThickness = 0,
    CanvasSize = UDim2.new(),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, body)
new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 13) }, Sidebar)
new("UIPadding", { PaddingTop = UDim.new(0, 20), PaddingBottom = UDim.new(0, 10) }, Sidebar)

local divider = new("Frame", {
    Name = "Divider",
    Position = UDim2.new(SIDE_W, 0, 0, 0),
    Size = UDim2.new(0, 9, 1, 0),
    BorderSizePixel = 0,
    BackgroundTransparency = 0.55,
    ZIndex = 2,
}, body)
bind(divider, "BackgroundColor3", "Line")
hline(divider, UDim2.fromOffset(0, 0), UDim2.new(0, 1, 1, 0))
hline(divider, UDim2.fromOffset(8, 0), UDim2.new(0, 1, 1, 0))

local ContentContainer = new("Frame", {
    Name = "ContentContainer",
    BackgroundTransparency = 1,
    ClipsDescendants = true,
    Position = UDim2.new(SIDE_W, 9, 0, 0),
    Size = UDim2.new(1 - SIDE_W, -9, 1, 0),
}, body)

local rail = new("Frame", {
    Name = "Rail",
    BackgroundTransparency = 1,
    Position = UDim2.new(1, -15, 0, 14),
    Size = UDim2.new(0, 9, 1, -22),
    ZIndex = 5,
}, ContentContainer)
local railStroke = new("UIStroke", { Thickness = 1 }, rail)
bind(railStroke, "Color", "Line")

makeDraggable(top, main, function()
    save()
end, function()
    return OverallScalePercent / 100
end, function()
    return DragDelayMs / 1000
end, nil, function(target)
    clampGuiToViewport(target)
end)

local resizeBtn = new("TextButton", {
    Name = "ResizeBtn",
    BackgroundTransparency = 1,
    Position = UDim2.new(1, -15, 1, -15),
    Size = UDim2.fromOffset(15, 15),
    Text = "◢",
    TextTransparency = 0.55,
    ZIndex = 10,
}, main)
bindFont(resizeBtn, 11, true)
bind(resizeBtn, "TextColor3", "Accent")
do
    local resizing, resizeStart, startAbs = false, nil, nil
    connect(resizeBtn.InputBegan, function(input)
        if isPointer(input) then
            resizing = true
            resizeStart = input.Position
            startAbs = Vector2.new(main.Size.X.Offset, main.Size.Y.Offset)
        end
    end)
    connect(UserInputService.InputChanged, function(input)
        if resizing and isMove(input) then
            local d = input.Position - resizeStart
            local scaleFactor = math.max(OverallScalePercent / 100, 0.01)
            main.Size = UDim2.fromOffset(
            math.clamp(startAbs.X + d.X / scaleFactor, 360, 900),
            math.clamp(startAbs.Y + d.Y / scaleFactor, 240, 650)
            )
        end
    end)
    connect(UserInputService.InputEnded, function(input)
        if resizing and isPointer(input) then
            resizing = false
            save()
        end
    end)
end

local stripHost = new("Frame", {
    Name = "Strips",
    BackgroundTransparency = 1,
    ClipsDescendants = true,
    Visible = false,
    ZIndex = 60,
}, gui)
stripUIScale = new("UIScale", { Scale = OverallScalePercent / 100 }, stripHost)
local rng = Random.new()
local animating = false
local pendingThemeAction = nil
local runThemeTransition

-- Strip-wipe variants (Window Open / Close Style).
-- Each style uses the same strip system; settings control the strip count, angle, width and timing.
--   n               : number of strips
--   angle           : strip rotation in degrees
--   alternateAngle  : optional angle used on every second strip
--   barW            : strip width as a fraction of the window width
--   fixedR          : collapse each strip to this height (0..1) instead of a random one
--   step            : seconds between strips (sequential). Without it the timing is random
--   dynamicPad      : widen the strip range so angled strips still cover the whole window
local StripVariants = {
    Classic = { n = 9, angle = -13, barW = 0.22 },
    Shutter = { n = 12, angle = 0, barW = 0.2, fixedR = 0.5, step = 0.018, dynamicPad = true },
    Slash = { n = 7, angle = 24, barW = 0.3, dynamicPad = true },
    Pinstripe = { n = 16, angle = 0, barW = 0.095, step = 0.012, dynamicPad = true },
    ["Reverse Slash"] = { n = 8, angle = -27, barW = 0.27, dynamicPad = true },
    -- Wider, denser alternating diagonals prevent gaps on tall and narrow windows.
    Crosscut = { n = 22, angle = 35, alternateAngle = -35, barW = 1.08, step = 0.010, dynamicPad = true },
}

local function flushPendingThemeAction()
    local action = pendingThemeAction
    pendingThemeAction = nil
    if action then
        task.defer(function()
            if runThemeTransition then
                runThemeTransition(action)
            end
        end)
    end
end

local function buildStrips(W, H, collapsed, variant)
    variant = variant or StripVariants.Classic
    local n = variant.n

    for _, child in ipairs(stripHost:GetChildren()) do
        if child ~= stripUIScale then
            child:Destroy()
        end
    end

    local x0, x1
    if variant.dynamicPad then
        local maxAngle = math.max(math.abs(variant.angle or 0), math.abs(variant.alternateAngle or 0))
        local angleRad = math.rad(maxAngle)
        -- Use the rotated rectangle's horizontal bounds (bar height is 1.8 * H).
        -- The extra margin keeps angled strips extending beyond every window edge.
        local pad = 0.9 * H * math.abs(math.sin(angleRad))
            + 0.5 * W * (variant.barW or 0) * math.abs(math.cos(angleRad))
            + 0.16 * W
        x0, x1 = -pad, W + pad
    else
        x0, x1 = -0.08 * W, 1.12 * W
    end

    -- Make neighbouring strips always overlap (no hairline gaps), like Classic does.
    local spacing = (x1 - x0) / math.max(n - 1, 1)
    local barWidth = W * variant.barW
    if not variant.alternateAngle then
        barWidth = math.max(barWidth, spacing * math.cos(math.rad(variant.angle or 0)) * 1.45)
    end
    -- Keep the sequential delay spread inside Classic's 0..0.22s window.
    local stepDelay = variant.step and math.min(variant.step, 0.22 / math.max(n - 1, 1)) or nil

    local list = {}
    for i = 1, n do
        local r
        if variant.fixedR then
            r = variant.fixedR
        elseif variant.rByIndex then
            r = 0.1 + 0.8 * ((i - 1) / math.max(n - 1, 1))
        else
            r = rng:NextNumber(0.1, 0.9)
        end
        local xc = x0 + (i - 1) * ((x1 - x0) / math.max(n - 1, 1))
        local stripAngle = variant.alternateAngle and (i % 2 == 0 and variant.alternateAngle or variant.angle) or variant.angle

        local band = new("Frame", {
            BackgroundTransparency = 1,
            ClipsDescendants = true,
            ZIndex = 60,
            Position = collapsed and UDim2.fromOffset(0, r * H) or UDim2.fromOffset(0, 0),
            Size = collapsed and UDim2.fromOffset(W, 0) or UDim2.fromOffset(W, H),
        }, stripHost)
    local bar = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        BorderSizePixel = 0,
        ZIndex = 60,
        Position = UDim2.fromOffset(xc, H / 2 - (collapsed and r * H or 0)),
        Size = UDim2.fromOffset(barWidth, H * 1.8),
        Rotation = stripAngle,
        BackgroundColor3 = Theme.Paper,
        BackgroundTransparency = collapsed and 0 or 1,
    }, band)
local stroke = new("UIStroke", {
    Thickness = 1,
    Color = Theme.Line,
    Transparency = collapsed and 0.4 or 1,
}, bar)
local delay = stepDelay and ((i - 1) * stepDelay) or rng:NextNumber(0, 0.22)
list[i] = { band = band, bar = bar, stroke = stroke, r = r, xc = xc, delay = delay }
end
return list
end

local function playStrips(opening, variant)
    local W, H = main.Size.X.Offset, main.Size.Y.Offset
    stripHost.Position = main.Position
    stripHost.Size = main.Size
    local list = buildStrips(W, H, opening, variant)
    stripHost.Visible = true

    local grow = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
    local fade = TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local quick = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local maxDelay = 0
    for _, s in ipairs(list) do
        maxDelay = math.max(maxDelay, s.delay)
    end
    -- Total fade / cover spread is fixed (same as Classic's 9 strips), so styles with
    -- more strips are not slower or choppier.
    local fadeSpread = 0.315
    local coverSpread = 0.27
    local fadeStep = fadeSpread / math.max(#list, 1)
    local coverStep = coverSpread / math.max(#list, 1)

    -- The window's outline sits outside the strips, so fade it together with them.
    local strokeT = mainStroke.Transparency

    local function finish()
        stripHost.Visible = false
        mainStroke.Transparency = strokeT
        for _, child in ipairs(stripHost:GetChildren()) do
            if child ~= stripUIScale then
                child:Destroy()
            end
        end
        animating = false
        flushPendingThemeAction()
    end

    if opening then
        mainStroke.Transparency = 1

        for _, s in ipairs(list) do
            task.delay(s.delay, function()
                TweenService:Create(s.band, grow, { Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(W, H) }):Play()
                TweenService:Create(s.bar, grow, { Position = UDim2.fromOffset(s.xc, H / 2) }):Play()
            end)
        end

        task.delay(maxDelay + 0.33, function()
            main.Visible = true
            TweenService:Create(mainStroke, fade, { Transparency = strokeT }):Play()
            for i, s in ipairs(list) do
                task.delay((i - 1) * fadeStep, function()
                    TweenService:Create(s.bar, fade, { BackgroundTransparency = 1 }):Play()
                    TweenService:Create(s.stroke, fade, { Transparency = 1 }):Play()
                end)
            end
            task.delay(fadeSpread + 0.36, finish)
        end)
    else
        -- Solid backing under the strips: whatever the strip geometry, the window is
        -- completely hidden before it is switched off.
        local backing = new("Frame", {
            Name = "CloseCover",
            Size = UDim2.fromOffset(W, H),
            BackgroundColor3 = Theme.Paper,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            ZIndex = 59,
        }, stripHost)
        TweenService:Create(mainStroke, TweenInfo.new(coverSpread + 0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 1 }):Play()
        task.delay(coverSpread * 0.8, function()
            if backing.Parent then
                TweenService:Create(backing, quick, { BackgroundTransparency = 0 }):Play()
            end
        end)

        for i, s in ipairs(list) do
            task.delay((#list - i) * coverStep, function()
                TweenService:Create(s.bar, quick, { BackgroundTransparency = 0 }):Play()
                TweenService:Create(s.stroke, quick, { Transparency = 0.4 }):Play()
            end)
        end

        task.delay(coverSpread + 0.3, function()
            main.Visible = false
            mainStroke.Transparency = strokeT
            if backing.Parent then
                TweenService:Create(backing, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
            end
            for _, s in ipairs(list) do
                task.delay(s.delay, function()
                    TweenService:Create(s.band, grow, { Position = UDim2.fromOffset(0, s.r * H), Size = UDim2.fromOffset(W, 0) }):Play()
                    TweenService:Create(s.bar, grow, { Position = UDim2.fromOffset(s.xc, H / 2 - s.r * H) }):Play()
                end)
            end
            task.delay(maxDelay + 0.34, finish)
        end)
    end
end

local function offsetUDim2(position, dx, dy)
    return UDim2.new(position.X.Scale, position.X.Offset + dx, position.Y.Scale, position.Y.Offset + dy)
end

local function scaleUDim2(size, factor)
    return UDim2.new(size.X.Scale * factor, size.X.Offset * factor, size.Y.Scale * factor, size.Y.Offset * factor)
end

local function collectTransparencyTargets(root)
    local targets = {}
    local objects = { root }
    for _, descendant in ipairs(root:GetDescendants()) do
        table.insert(objects, descendant)
    end
    for _, object in ipairs(objects) do
        local props = {}
        if object:IsA("GuiObject") then
            props.BackgroundTransparency = object.BackgroundTransparency
        end
        if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
            props.TextTransparency = object.TextTransparency
            props.TextStrokeTransparency = object.TextStrokeTransparency
        end
        if object:IsA("ImageLabel") or object:IsA("ImageButton") then
            props.ImageTransparency = object.ImageTransparency
        end
        if object:IsA("ScrollingFrame") then
            props.ScrollBarImageTransparency = object.ScrollBarImageTransparency
        end
        if object:IsA("UIStroke") then
            props.Transparency = object.Transparency
        end
        for property, value in pairs(props) do
            if type(value) == "number" and value < 0.999 then
                table.insert(targets, { instance = object, property = property, value = value })
            end
        end
    end
    table.sort(targets, function(a, b)
        local ay = a.instance:IsA("GuiObject") and a.instance.AbsolutePosition.Y or 0
        local by = b.instance:IsA("GuiObject") and b.instance.AbsolutePosition.Y or 0
        return ay < by
    end)
    return targets
end

local function restoreTransparencyTargets(targets)
    for _, target in ipairs(targets) do
        if target.instance and target.instance.Parent then
            pcall(function() target.instance[target.property] = target.value end)
        end
    end
end

local function playWindowStyle(shouldOpen, style)
    if style == "None" then
        main.Visible = shouldOpen
        return
    end

    animating = true
    local basePosition = main.Position
    local baseSize = main.Size
    local width = math.max(main.AbsoluteSize.X, baseSize.X.Offset, 1)
    local height = math.max(main.AbsoluteSize.Y, baseSize.Y.Offset, 1)
    local duration = (style == "Glitch" and 0.34) or (style == "Pop" and 0.38) or 0.30
    local motionPosition = basePosition
    local motionSize = baseSize

    if style == "Slide Left" then
        motionPosition = offsetUDim2(basePosition, -width * 0.88, 0)
    elseif style == "Slide Right" then
        motionPosition = offsetUDim2(basePosition, width * 0.88, 0)
    elseif style == "Slide Up" then
        motionPosition = offsetUDim2(basePosition, 0, -height * 0.88)
    elseif style == "Slide Down" then
        motionPosition = offsetUDim2(basePosition, 0, height * 0.88)
    elseif style == "Glitch" then
        motionPosition = offsetUDim2(basePosition, -18, 3)
    elseif style == "Zoom" or style == "Pop" then
        local factor = style == "Pop" and 0.78 or 0.88
        motionSize = scaleUDim2(baseSize, factor)
        motionPosition = offsetUDim2(basePosition, width * (1 - factor) / 2, height * (1 - factor) / 2)
    end

    local transparencyTargets = collectTransparencyTargets(main)
    if shouldOpen then
        main.Visible = true
        main.Position = (style == "Fade") and basePosition or motionPosition
        main.Size = (style == "Zoom" or style == "Pop") and motionSize or baseSize
        for _, target in ipairs(transparencyTargets) do
            if target.instance and target.instance.Parent then
                pcall(function() target.instance[target.property] = 1 end)
            end
        end

        local easingStyle = style == "Pop" and Enum.EasingStyle.Back or (style == "Zoom" and Enum.EasingStyle.Quint or Enum.EasingStyle.Quart)
        local info = TweenInfo.new(duration, easingStyle, Enum.EasingDirection.Out)
        local motion = TweenService:Create(main, info, { Position = basePosition, Size = baseSize })
        motion:Play()
        for index, target in ipairs(transparencyTargets) do
            if target.instance and target.instance.Parent then
                local fadeInfo = TweenInfo.new(style == "Glitch" and 0.18 or duration * 0.86, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
                local tween = TweenService:Create(target.instance, fadeInfo, { [target.property] = target.value })
                if style == "Glitch" then
                    task.delay((index - 1) % 4 * 0.018, function()
                        if animating and target.instance and target.instance.Parent then tween:Play() end
                    end)
                else
                    tween:Play()
                end
            end
        end
        if style == "Glitch" then
            task.delay(0.05, function()
                if animating and main.Parent then
                    TweenService:Create(main, TweenInfo.new(0.07, Enum.EasingStyle.Linear), { Position = offsetUDim2(basePosition, 10, -2) }):Play()
                end
            end)
            task.delay(0.13, function()
                if animating and main.Parent then
                    TweenService:Create(main, TweenInfo.new(0.09, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Position = basePosition }):Play()
                end
            end)
        end
        task.delay(duration + 0.08, function()
            if main.Parent then
                main.Position = basePosition
                main.Size = baseSize
            end
            animating = false
            flushPendingThemeAction()
        end)
    else
        local outPosition = (style == "Fade") and basePosition or motionPosition
        local outSize = (style == "Zoom" or style == "Pop") and motionSize or baseSize
        local easingStyle = style == "Pop" and Enum.EasingStyle.Back or Enum.EasingStyle.Quad
        local info = TweenInfo.new(duration * 0.82, easingStyle, Enum.EasingDirection.In)
        local motion = TweenService:Create(main, info, { Position = outPosition, Size = outSize })
        motion:Play()
        for _, target in ipairs(transparencyTargets) do
            if target.instance and target.instance.Parent then
                TweenService:Create(target.instance, TweenInfo.new(duration * 0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { [target.property] = 1 }):Play()
            end
        end
        if style == "Glitch" then
            task.delay(0.08, function()
                if animating and main.Parent then
                    TweenService:Create(main, TweenInfo.new(0.06, Enum.EasingStyle.Linear), { Position = offsetUDim2(basePosition, 12, -2) }):Play()
                end
            end)
        end
        task.delay(duration + 0.02, function()
            if main.Parent then
                main.Visible = false
                main.Position = basePosition
                main.Size = baseSize
                restoreTransparencyTargets(transparencyTargets)
            end
            animating = false
            flushPendingThemeAction()
        end)
    end
end

local sfxInitialized = false
local authOutroStarted = false
local function SetWindowOpen(shouldOpen)
    if authOutroStarted and shouldOpen then return end
    if animating or shouldOpen == main.Visible then
        return
    end

    if Library._reloadAllSfx and not sfxInitialized then
        sfxInitialized = true
        task.defer(Library._reloadAllSfx)
    end
    if Library._sfx then
        Library._sfx(shouldOpen and "open" or "close")
    end

    local stripVariant = StripVariants[OpenCloseAnimation]
    if stripVariant then
        animating = true
        playStrips(shouldOpen, stripVariant)
        return
    end
    playWindowStyle(shouldOpen, OpenCloseAnimation)
end

local function DestroyAfterAuthOutro()
    if authOutroStarted then return end
    authOutroStarted = true
    task.spawn(function()
        -- Let an in-progress intro/open animation finish before starting the outro.
        local deadline = os.clock() + 2
        while animating and gui.Parent and os.clock() < deadline do
            task.wait(0.05)
        end
        if not gui.Parent then return end

        if not main.Visible then main.Visible = true end
        if not animating then
            SetWindowOpen(false)
        else
            -- Defensive fallback if an executor leaves an animation locked.
            local targetPosition = offsetUDim2(main.Position, 0, 18)
            TweenService:Create(main, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
                Position = targetPosition,
                BackgroundTransparency = 1,
            }):Play()
        end

        task.wait(OpenCloseAnimation == "None" and 0.12 or 1.15)
        if gui.Parent then gui:Destroy() end
    end)
end

runThemeTransition = function(applyChange)
    if type(applyChange) ~= "function" then
        return
    end
    if animating then
        pendingThemeAction = applyChange
        return
    end
    if not main.Visible then
        applyChange()
        return
    end

    animating = true
    local W, H = main.Size.X.Offset, main.Size.Y.Offset
    local oldPaper = Theme.Paper
    stripHost.Position = main.Position
    stripHost.Size = main.Size
    local list = buildStrips(W, H, false)
    local cover = new("Frame", {
        Name = "ThemeCover",
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.fromOffset(W, H),
        BackgroundColor3 = oldPaper,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 59,
        Active = false,
    }, stripHost)
stripHost.Visible = true

local coverIn = TweenInfo.new(0.26, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
local colorTween = TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
local revealTween = TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local stripeTween = TweenInfo.new(0.30, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local maxStripeDelay = (#list - 1) * 0.025

local function finish()
    stripHost.Visible = false
    for _, child in ipairs(stripHost:GetChildren()) do
        if child ~= stripUIScale then
            child:Destroy()
        end
    end
    animating = false
    flushPendingThemeAction()
end

TweenService:Create(cover, coverIn, { BackgroundTransparency = 0 }):Play()
for i, strip in ipairs(list) do
    task.delay((#list - i) * 0.025, function()
        if not strip.bar.Parent then return end
        TweenService:Create(strip.bar, coverIn, { BackgroundTransparency = 0 }):Play()
        TweenService:Create(strip.stroke, coverIn, { Transparency = 0.4 }):Play()
    end)
end

task.delay(maxStripeDelay + 0.29, function()
    local ok, err = pcall(applyChange)
    if not ok then
        warn("[UI] Theme transition failed: " .. tostring(err))
    end

    local newPaper, newLine = Theme.Paper, Theme.Line

    for _, strip in ipairs(list) do
        if strip.bar.Parent then
            TweenService:Create(strip.bar, colorTween, { BackgroundColor3 = newPaper }):Play()
            TweenService:Create(strip.stroke, colorTween, { Color = newLine }):Play()
        end
    end
    TweenService:Create(cover, colorTween, { BackgroundColor3 = newPaper }):Play()

    task.delay(0.25, function()

        TweenService:Create(cover, revealTween, { BackgroundTransparency = 1 }):Play()
        for i, strip in ipairs(list) do
            task.delay((i - 1) * 0.025, function()
                if not strip.bar.Parent then return end
                TweenService:Create(strip.bar, stripeTween, { BackgroundTransparency = 1 }):Play()
                TweenService:Create(strip.stroke, stripeTween, { Transparency = 1 }):Play()
            end)
        end
        task.delay(maxStripeDelay + 0.36, finish)
    end)
end)
end

local toggleBtn = new("ImageButton", {
    Name = "ToggleBtn",
    Position = UDim2.fromOffset(20, 20),
    Size = UDim2.fromOffset(44, 44),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    AutoButtonColor = false,
    Image = "",
}, gui)
toggleUIScale = new("UIScale", { Scale = ToggleButtonScalePercent / 100 }, toggleBtn)
local setToggleBtnRaised = makeRaiseController(toggleBtn, 1.08)
local tbVisual = new("Frame", {
    Name = "Visual",
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Size = UDim2.fromScale(1, 1),
}, toggleBtn)

local CENTER = Vector2.new(0.5, 0.5)

local function buildToggleVisual(style)
    tbVisual:ClearAllChildren()
    local hasImg = ToggleConfig.Image and ToggleConfig.Image ~= ""

    local function glyph(parent, size, colorToken, imgScale)
        if hasImg then
            return new("ImageLabel", {
                BackgroundTransparency = 1,
                AnchorPoint = CENTER,
                Position = UDim2.fromScale(0.5, 0.5),
                Size = UDim2.fromScale(imgScale or 0.6, imgScale or 0.6),
                Image = ToggleConfig.Image,
                ZIndex = 3,
            }, parent)
    end
    local t = new("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        Text = ToggleConfig.Text or "◆",
        ZIndex = 3,
    }, parent)
bindFont(t, size, true)
bind(t, "TextColor3", colorToken)
return t
end

if style == "Circle" then

    toggleBtn.Size = UDim2.fromOffset(46, 46)
    local disc = new("Frame", { Size = UDim2.fromScale(1, 1), BorderSizePixel = 0 }, tbVisual)
    bind(disc, "BackgroundColor3", "Accent")
    new("UICorner", { CornerRadius = UDim.new(1, 0) }, disc)
    local st = new("UIStroke", { Thickness = 2 }, disc)
    bind(st, "Color", "Line")
    local ring = new("Frame", {
        AnchorPoint = CENTER,
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.new(1, -10, 1, -10),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
    }, disc)
new("UICorner", { CornerRadius = UDim.new(1, 0) }, ring)
local rs = new("UIStroke", { Thickness = 1, Transparency = 0.55 }, ring)
bind(rs, "Color", "Cream")
glyph(disc, 16, "Cream")

elseif style == "Diamond" then

    toggleBtn.Size = UDim2.fromOffset(56, 56)
    local outer = new("Frame", {
        AnchorPoint = CENTER,
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(38, 38),
        Rotation = 45,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
    }, tbVisual)
local os = new("UIStroke", { Thickness = 1 }, outer)
bind(os, "Color", "Accent")
local inner = new("Frame", {
    AnchorPoint = CENTER,
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(30, 30),
    Rotation = 45,
    BorderSizePixel = 0,
}, tbVisual)
bind(inner, "BackgroundColor3", "Accent")
local ist = new("UIStroke", { Thickness = 1 }, inner)
bind(ist, "Color", "Line")
glyph(tbVisual, 16, "Cream", 0.45)

elseif style == "Pill" then

    toggleBtn.Size = UDim2.fromOffset(80, 30)
    local pill = new("Frame", { Size = UDim2.fromScale(1, 1), BorderSizePixel = 0 }, tbVisual)
    bind(pill, "BackgroundColor3", "Accent")
    new("UICorner", { CornerRadius = UDim.new(1, 0) }, pill)
    local st = new("UIStroke", { Thickness = 1 }, pill)
    bind(st, "Color", "Line")
    if hasImg then
        new("ImageLabel", {
            BackgroundTransparency = 1,
            Position = UDim2.new(0, 9, 0.5, -8),
            Size = UDim2.fromOffset(16, 16),
            Image = ToggleConfig.Image,
            ZIndex = 3,
        }, pill)
else
    local dia = new("Frame", {
        Position = UDim2.new(0, 13, 0.5, -4),
        Size = UDim2.fromOffset(8, 8),
        Rotation = 45,
        BorderSizePixel = 0,
        ZIndex = 3,
    }, pill)
bind(dia, "BackgroundColor3", "Cream")
end
local lab = new("TextLabel", {
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(30, 0),
    Size = UDim2.new(1, -38, 1, 0),
    Text = ToggleConfig.Text or "MENU",
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
    ZIndex = 3,
}, pill)
bindFont(lab, 12, true)
bind(lab, "TextColor3", "Cream")

elseif style == "Bracket" then

    toggleBtn.Size = UDim2.fromOffset(46, 46)
    local panel = new("Frame", {
        Size = UDim2.fromScale(1, 1),
        BorderSizePixel = 0,
        BackgroundTransparency = 0.15,
    }, tbVisual)
bind(panel, "BackgroundColor3", "Paper")
for _, c in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
    local anchor = Vector2.new(c[1], c[2])
    local pos = UDim2.fromScale(c[1], c[2])
    local h = new("Frame", {
        AnchorPoint = anchor, Position = pos,
        Size = UDim2.fromOffset(12, 2), BorderSizePixel = 0, ZIndex = 2,
    }, panel)
bind(h, "BackgroundColor3", "Accent")
local v = new("Frame", {
    AnchorPoint = anchor, Position = pos,
    Size = UDim2.fromOffset(2, 12), BorderSizePixel = 0, ZIndex = 2,
}, panel)
bind(v, "BackgroundColor3", "Accent")
end
glyph(panel, 16, "Accent")

else

    toggleBtn.Size = UDim2.fromOffset(44, 44)
    local box = new("Frame", { Size = UDim2.fromScale(1, 1), BorderSizePixel = 0 }, tbVisual)
    bind(box, "BackgroundColor3", "Accent")
    local st = new("UIStroke", { Thickness = 1 }, box)
    bind(st, "Color", "Line")
    glyph(box, 16, "Cream")
end
end
buildToggleVisual(MobileStyle)

local function SetMobileStyle(name)
    if not validStyle(name) then return end
    MobileStyle = name
    buildToggleVisual(MobileStyle)
    persistTheme()
end

local function SetOverallScale(percent)
    OverallScalePercent = math.clamp(math.floor((tonumber(percent) or 100) + 0.5), 70, 130)
    if mainUIScale then mainUIScale.Scale = OverallScalePercent / 100 end
    if stripUIScale then stripUIScale.Scale = OverallScalePercent / 100 end
    persistTheme()
end

local function SetToggleButtonScale(percent)
    ToggleButtonScalePercent = math.clamp(math.floor((tonumber(percent) or 100) + 0.5), 50, 180)
    if toggleUIScale then toggleUIScale.Scale = ToggleButtonScalePercent / 100 end
    persistTheme()
end

toggleBtn.Visible = isMobile
local tbMoved = makeDraggable(toggleBtn, nil, nil, function()
    return ToggleButtonScalePercent / 100
end, function()
    return DragDelayMs / 1000
end, nil, function(target)
    clampGuiToViewport(target)
end)
toggleBtn.MouseEnter:Connect(function()
    setToggleBtnRaised(true, true)
    if Library._sfx then Library._sfx("hover") end
end)
toggleBtn.MouseLeave:Connect(function() setToggleBtnRaised(false, true) end)
if UserInputService.TouchEnabled then
    local toggleTouch
    toggleBtn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch then
            toggleTouch = input
            setToggleBtnRaised(true, true)
            if Library._sfx then Library._sfx("hover") end
        end
    end)
    connect(UserInputService.InputEnded, function(input)
        if toggleTouch and input == toggleTouch then
            toggleTouch = nil
            setToggleBtnRaised(false, true)
        end
    end)
end
toggleBtn.MouseButton1Click:Connect(function()
    if not tbMoved() then
        if Library._sfx then Library._sfx("select") end
        SetWindowOpen(not main.Visible)
    end
end)

local toastHolder = new("Frame", {
    Name = "Toasts",
    Position = UDim2.fromScale(0, 0),
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    ClipsDescendants = false,
    Active = false,
}, gui)

local toastEntries = {}
local function layoutToastEntries()
    local stackOffset = 20
    for index = #toastEntries, 1, -1 do
        local entry = toastEntries[index]
        if not entry.slot or entry.slot.Parent == nil then
            table.remove(toastEntries, index)
        elseif not entry.dragged then
            entry.slot.AnchorPoint = Vector2.new(0, 1)
            entry.slot.Position = UDim2.new(0, 20, 1, -stackOffset)
            stackOffset += entry.height + 6
        end
    end
end

local function removeToastEntry(entry)
    if entry.removed then
        return
    end
    entry.removed = true
    for index = #toastEntries, 1, -1 do
        if toastEntries[index] == entry then
            table.remove(toastEntries, index)
            break
        end
    end
    layoutToastEntries()
end

local function Notify(text, duration, opts)
    if type(text) == "table" then
        opts = text
        text = opts.Text or opts.Description or ""
    end
    opts = type(opts) == "table" and opts or {}
    text = tostring(text or opts.Text or opts.Description or "")
    local title = opts.Title
    duration = math.max(0, tonumber(duration or opts.Duration or opts.Time) or 3.2)

    if Library._sfx then
        Library._sfx("notify")
    end

    local fullText = title and (tostring(title) .. (text ~= "" and ("  ·  " .. text) or "")) or text
    local lab = new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(16, 0),
        Text = "",
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ZIndex = 3,
    })
    bindFont(lab, 14, false)
    bind(lab, "TextColor3", "Ink")

    local okW, sz = pcall(function()
        return TextService:GetTextSize(fullText, lab.TextSize, lab.Font, Vector2.new(600, 40))
    end)
    local w = math.clamp((okW and sz.X or 260) + 42, 210, 480)

    local slot = new("Frame", {
        BackgroundTransparency = 1,
        ClipsDescendants = true,
        Size = UDim2.fromOffset(w, 38),
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 20, 1, -20),
        Active = true,
        ZIndex = 50,
    }, toastHolder)
    local card = new("Frame", {
        Size = UDim2.fromScale(1, 1),
        Position = UDim2.fromScale(-1, 0),
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Active = true,
        ZIndex = 50,
    }, slot)

    local toastEntry = { slot = slot, height = 38, dragged = false, removed = false }
    table.insert(toastEntries, toastEntry)
    layoutToastEntries()
    makeDraggable(card, slot, nil, nil, function()
        return DragDelayMs / 1000
    end, function()
        toastEntry.dragged = true
        -- Reparenting brings the held toast above its siblings without changing
        -- any of its accent rails, typography, glitch, or slide animations.
        slot.Parent = nil
        slot.Parent = toastHolder
        layoutToastEntries()
    end, function(target)
        clampGuiToViewport(target)
    end)
    slot.Destroying:Connect(function()
        removeToastEntry(toastEntry)
    end)
    bind(card, "BackgroundColor3", function(t)
        return t.Paper:Lerp(t.Cream, 0.12)
    end)
    local cardStroke = new("UIStroke", { Thickness = 1 }, card)
    bind(cardStroke, "Color", "Line")
    -- Notification accent: slightly slimmer main indigo rail plus a fine parallel pinstripe.
    -- Both stay in the left gutter; the label keeps its existing 16px inset and is never covered.
    local bar = new("Frame", {
        Name = "AccentRail",
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.new(0, 3, 1, 0),
        BorderSizePixel = 0,
        ZIndex = 52,
    }, card)
    bind(bar, "BackgroundColor3", "Accent")

    local accentPinstripe = new("Frame", {
        Name = "AccentPinstripe",
        Position = UDim2.fromOffset(6, 0),
        Size = UDim2.new(0, 1, 1, 0),
        BorderSizePixel = 0,
        ZIndex = 52,
    }, card)
    bind(accentPinstripe, "BackgroundColor3", "Accent")

    lab.Size = UDim2.new(1, -28, 1, 0)
    lab.Parent = card

    -- Premium glitch: brief, sparse, high-ZIndex black micro-rectangles that fade, never dense spam
    local function premiumGlitch(target, ms)
        local endAt = os.clock() + (ms or 0.28)
        local spots = {}
        task.spawn(function()
            while os.clock() < endAt and target and target.Parent do
                if math.random() < 0.42 then
                    local aw = math.max(12, target.AbsoluteSize.X)
                    local ah = math.max(10, target.AbsoluteSize.Y)
                    local sw = math.random(4, math.min(28, math.floor(aw * 0.22)))
                    local sh = math.random(1, 3)
                    local sx = math.random(0, math.max(0, aw - sw))
                    local sy = math.random(0, math.max(0, ah - sh))
                    local spot = new("Frame", {
                        BackgroundColor3 = Color3.new(0, 0, 0),
                        BackgroundTransparency = 0.15 + math.random() * 0.35,
                        BorderSizePixel = 0,
                        Size = UDim2.fromOffset(sw, sh),
                        Position = UDim2.fromOffset(sx, sy),
                        ZIndex = 60,
                        Parent = target,
                    })
                    table.insert(spots, spot)
                    task.delay(0.035 + math.random() * 0.05, function()
                        if spot and spot.Parent then
                            tw(spot, 0.06, { BackgroundTransparency = 1 })
                            task.delay(0.07, function()
                                if spot and spot.Parent then spot:Destroy() end
                            end)
                        end
                    end)
                end
                task.wait(0.028)
            end
            for _, s in ipairs(spots) do
                if s and s.Parent then s:Destroy() end
            end
        end)
    end

    -- Typewriter + light scramble intro
    local SCRAMBLE = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789·-/+#"
    task.spawn(function()
        local target = fullText
        local len = #target
        -- short scramble phase
        for _ = 1, 5 do
            if not lab.Parent then return end
            local buf = {}
            for i = 1, len do
                if math.random() > 0.4 then
                    local r = math.random(1, #SCRAMBLE)
                    buf[i] = SCRAMBLE:sub(r, r)
                else
                    buf[i] = target:sub(i, i)
                end
            end
            lab.Text = table.concat(buf)
            task.wait(0.022)
        end
        -- typewriter
        lab.Text = ""
        for i = 1, len do
            if not lab.Parent then return end
            lab.Text = target:sub(1, i)
            task.wait(0.018)
        end
        lab.Text = target
    end)

    TweenService:Create(card, TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
        Position = UDim2.fromScale(0, 0),
    }):Play()
    premiumGlitch(card, 0.34)

    task.delay(duration, function()
        if not slot.Parent then return end
        premiumGlitch(card, 0.18)
        local out = TweenService:Create(card, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            Position = UDim2.fromScale(-1, 0),
            BackgroundTransparency = 0.4,
        })
        out:Play()
        out.Completed:Wait()
        if slot.Parent then slot:Destroy() end
    end)
end

local SettingsState = { open = false }
local ToggleSettingsVisibility = function() end
local OpenSettingsFn = function() end
local CloseSettingsFn = function() end
gearBtn.MouseButton1Click:Connect(function()
    if Library._sfx then Library._sfx("select") end
    ToggleSettingsVisibility()
end)

local pageAnimationStates = {}

local SCRAMBLE_GLYPHS = {
    "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
    "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
    "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "+", "-", "=", "/", "\\", "<", ">", "#", "$", "%", "*"
}

local function splitTextCharacters(value)
    local characters = {}
    local ok = pcall(function()
        if utf8 and utf8.graphemes then
            for first, last in utf8.graphemes(value) do
                table.insert(characters, string.sub(value, first, last))
            end
        else
            for _, codepoint in utf8.codes(value) do
                table.insert(characters, utf8.char(codepoint))
            end
        end
    end)
    if not ok or #characters == 0 then
        return { value }
    end
    return characters
end

local function scramblePageText(entry, state, page)
    local instance = entry.instance
    if not instance or not instance.Parent then return end

    entry.target = instance.Text
    local characters = splitTextCharacters(entry.target)
    if #characters == 0 or entry.target:match("^%s*$") then return end

    local duration = math.clamp(#characters * 0.022, 0.18, 0.42)
    local started = os.clock()
    while os.clock() - started < duration do
        if pageAnimationStates[page] ~= state or state.cancelled or not page.Visible or not instance.Parent then
            return
        end

        local currentText = instance.Text
        if entry.lastRendered == nil or currentText ~= entry.lastRendered then
            entry.target = currentText
            characters = splitTextCharacters(entry.target)
            duration = math.clamp(#characters * 0.022, 0.18, 0.42)
        end

        local progress = math.clamp((os.clock() - started) / duration, 0, 1)
        local lockedCount = math.floor(progress * #characters)
        local output = {}
        for index, character in ipairs(characters) do
            if index <= lockedCount or character:match("^%s+$") then
                output[index] = character
            else
                output[index] = SCRAMBLE_GLYPHS[math.random(1, #SCRAMBLE_GLYPHS)]
            end
        end

        local rendered = table.concat(output)
        entry.lastRendered = rendered
        instance.Text = rendered
        task.wait(0.035)
    end

    if instance.Parent and entry.lastRendered ~= nil and instance.Text == entry.lastRendered then
        instance.Text = entry.target
    end
    entry.lastRendered = nil
end

local function getFadeProperties(instance)
    local props = {}
    if instance:IsA("GuiObject") then
        props.BackgroundTransparency = instance.BackgroundTransparency
    end
    if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
        props.TextTransparency = instance.TextTransparency
        props.TextStrokeTransparency = instance.TextStrokeTransparency
    end
    if instance:IsA("ImageLabel") or instance:IsA("ImageButton") then
        props.ImageTransparency = instance.ImageTransparency
    end
    if instance:IsA("ScrollingFrame") then
        props.ScrollBarImageTransparency = instance.ScrollBarImageTransparency
    end
    if instance:IsA("UIStroke") then
        props.Transparency = instance.Transparency
    end
    return props
end

local function cancelPageAnimation(page)
    local state = pageAnimationStates[page]
    if not state then return end
    state.cancelled = true
    for _, tween in ipairs(state.tweens) do
        pcall(function() tween:Cancel() end)
    end
    for _, entry in ipairs(state.textEntries or {}) do
        if entry.instance and entry.instance.Parent and entry.lastRendered ~= nil and entry.instance.Text == entry.lastRendered then
            pcall(function()
                entry.instance.Text = entry.target
            end)
        end
        entry.lastRendered = nil
    end
    for _, original in ipairs(state.originals) do
        if original.instance and original.instance.Parent then
            pcall(function()
                original.instance[original.property] = original.value
            end)
        end
    end
    if state.basePosition and page.Parent then
        pcall(function() page.Position = state.basePosition end)
    end
    if state.scaleObject and state.scaleObject.Parent then
        state.scaleObject:Destroy()
    end
    pageAnimationStates[page] = nil
end

local PAGE_POP_SCALE = 0.86

local function AnimatePageIn(page)
    if not page then return end
    cancelPageAnimation(page)

    local basePos = page:GetAttribute("BasePosition")
    if not basePos then
        basePos = page.Position
        page:SetAttribute("BasePosition", basePos)
    end

    do
        local style = PageAnimation
        page.Position = basePos
        if style == "None" then
            return
        end

        local width = math.max(page.AbsoluteSize.X, 1)
        local height = math.max(page.AbsoluteSize.Y, 1)
        local startPosition = basePos
        if style == "Slide Left" then
            startPosition = offsetUDim2(basePos, width * 0.075, 0)
        elseif style == "Slide Right" then
            startPosition = offsetUDim2(basePos, -width * 0.075, 0)
        elseif style == "Slide Up" then
            startPosition = offsetUDim2(basePos, 0, height * 0.075)
        elseif style == "Slide Down" then
            startPosition = offsetUDim2(basePos, 0, -height * 0.075)
        elseif style == "Cascade" then
            startPosition = offsetUDim2(basePos, -width * 0.05, 0)
        elseif style == "Glitch" then
            startPosition = offsetUDim2(basePos, -14, 2)
        elseif style == "Pop" then
            local ui = (mainUIScale and mainUIScale.Scale) or 1
            startPosition = offsetUDim2(basePos, (width / ui) * (1 - PAGE_POP_SCALE) / 2, (height / ui) * (1 - PAGE_POP_SCALE) / 2)
        end

        local state = { tweens = {}, originals = {}, cancelled = false, basePosition = basePos, textEntries = {} }
        pageAnimationStates[page] = state
        local scaleTween
        if style == "Zoom" or style == "Pop" then
            local scaleObject = Instance.new("UIScale")
            scaleObject.Name = "PageTransitionScale"
            scaleObject.Scale = style == "Pop" and PAGE_POP_SCALE or 0.90
            scaleObject.Parent = page
            state.scaleObject = scaleObject
            scaleTween = TweenService:Create(scaleObject, TweenInfo.new(0.30, style == "Pop" and Enum.EasingStyle.Back or Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Scale = 1 })
            table.insert(state.tweens, scaleTween)
            scaleTween:Play()
        end

        page.Position = startPosition
        local moveTween = TweenService:Create(page, TweenInfo.new(style == "Glitch" and 0.24 or 0.28, style == "Pop" and Enum.EasingStyle.Back or Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Position = basePos })
        table.insert(state.tweens, moveTween)
        moveTween:Play()
        if style == "Glitch" then
            task.delay(0.045, function()
                if pageAnimationStates[page] == state and not state.cancelled and page.Visible then
                    local jitter = TweenService:Create(page, TweenInfo.new(0.045, Enum.EasingStyle.Linear), { Position = offsetUDim2(basePos, 8, -1) })
                    table.insert(state.tweens, jitter)
                    jitter:Play()
                end
            end)
            task.delay(0.10, function()
                if pageAnimationStates[page] == state and not state.cancelled and page.Visible then
                    local settle = TweenService:Create(page, TweenInfo.new(0.12, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Position = basePos })
                    table.insert(state.tweens, settle)
                    settle:Play()
                end
            end)
        end

        local items = {}
        for _, child in ipairs(page:GetChildren()) do
            if child:IsA("GuiObject") and child ~= state.scaleObject then
                table.insert(items, child)
            end
        end
        table.sort(items, function(a, b)
            if a.LayoutOrder == b.LayoutOrder then
                return a.AbsolutePosition.Y < b.AbsolutePosition.Y
            end
            return a.LayoutOrder < b.LayoutOrder
        end)

        local itemTargets = {}
        local itemTextTargets = {}
        for _, item in ipairs(items) do
            local targets = {}
            local textTargets = {}
            local objects = { item }
            for _, descendant in ipairs(item:GetDescendants()) do
                table.insert(objects, descendant)
            end
            for _, object in ipairs(objects) do
                local canFade = (object:IsA("GuiObject") and object.Visible) or (object:IsA("UIStroke") and object.Enabled)
                if canFade then
                    for property, originalValue in pairs(getFadeProperties(object)) do
                        if type(originalValue) == "number" and originalValue < 0.999 then
                            local target = { instance = object, property = property, value = originalValue }
                            table.insert(state.originals, target)
                            table.insert(targets, target)
                            pcall(function() object[property] = 1 end)
                        end
                    end
                end
                if style == "Glitch" and (object:IsA("TextLabel") or object:IsA("TextButton")) and object.Visible and object.Text ~= "" and not object.RichText then
                    local textEntry = { instance = object, target = object.Text, lastRendered = nil }
                    table.insert(textTargets, textEntry)
                    table.insert(state.textEntries, textEntry)
                end
            end
            table.insert(itemTargets, targets)
            table.insert(itemTextTargets, textTargets)
        end

        local stagger = style == "Cascade" and 0.045 or 0.018
        local fadeInfo = TweenInfo.new(style == "Glitch" and 0.18 or 0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
        for index, item in ipairs(items) do
            local targets = itemTargets[index]
            local textTargets = itemTextTargets[index]
            task.delay((style == "Fade" and 0 or (index - 1) * stagger), function()
                if pageAnimationStates[page] ~= state or state.cancelled or not page.Visible then
                    return
                end
                for _, target in ipairs(targets) do
                    if target.instance and target.instance.Parent then
                        local tween = TweenService:Create(target.instance, fadeInfo, { [target.property] = target.value })
                        table.insert(state.tweens, tween)
                        tween:Play()
                    end
                end
                for _, entry in ipairs(textTargets) do
                    task.spawn(scramblePageText, entry, state, page)
                end
            end)
        end

        task.delay(math.max(#items - 1, 0) * stagger + 0.65, function()
            if pageAnimationStates[page] == state then
                pageAnimationStates[page] = nil
                if state.scaleObject and state.scaleObject.Parent then state.scaleObject:Destroy() end
            end
        end)
        return
    end
end

local WindowElements = {}

function WindowElements:OpenSettings() OpenSettingsFn() end
function WindowElements:CloseSettings() CloseSettingsFn() end
function WindowElements:ToggleSettings() ToggleSettingsVisibility() end

function WindowElements:CreateCategory(CategoryName, IconName, Hidden)
    local CategoryElements = {}
    CategoryName = string.upper(tostring(CategoryName or "TAB"))

    local btn = new("TextButton", {
        Name = CategoryName,
        Size = UDim2.new(1, 0, 0, 25),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = "",
        Visible = not Hidden,
    }, Sidebar)
btn:SetAttribute("CategorySelected", false)

local tabFill = new("Frame", {
    Name = "Fill",
    Size = UDim2.new(1, -16, 1, 0),
    BorderSizePixel = 0,
    ClipsDescendants = true,
    ZIndex = 1,
}, btn)
bind(tabFill, "BackgroundColor3", "Row")
addGradient(tabFill, function(t)
    return makeGradientSequence(t.Row, t.Row:Lerp(t.Accent, 0.18))
end)
local tabWipe = new("Frame", { Name = "Wipe", Size = UDim2.new(0, 0, 1, 0), BorderSizePixel = 0 }, tabFill)
bind(tabWipe, "BackgroundColor3", "Accent")
local selLineTop = new("Frame", {
    Position = UDim2.new(0, 0, 0, -3), Size = UDim2.new(1, 0, 0, 1), BorderSizePixel = 0, Visible = false,
}, btn)
local selLineBot = new("Frame", {
    Position = UDim2.new(0, 0, 1, 2), Size = UDim2.new(1, 0, 0, 1), BorderSizePixel = 0, Visible = false,
}, btn)
bind(selLineTop, "BackgroundColor3", "Accent")
bind(selLineBot, "BackgroundColor3", "Accent")

local catAsset = resolveIcon(IconName)
local catMarker
if catAsset then
    catMarker = new("ImageLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 5, 0.5, -8),
        Size = UDim2.fromOffset(16, 16),
        Image = catAsset,
        ZIndex = 2,
    }, btn)
else
    catMarker = new("Frame", {
        Position = UDim2.new(0, 6, 0.5, -6),
        Size = UDim2.fromOffset(12, 12),
        BorderSizePixel = 0,
        ZIndex = 2,
    }, btn)
end
local catLabel = new("TextLabel", {
    BackgroundTransparency = 1,
    Position = UDim2.new(0, catAsset and 28 or 25, 0, 0),
    Size = UDim2.new(1, -(catAsset and 44 or 41), 1, 0),
    Text = CategoryName,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
    ZIndex = 2,
}, btn)
bindFont(catLabel, 13, false)

local catHover = false
local setCategoryRaised = makeRaiseController(btn, 1.035)
local function catLook(animate)
    local selected = btn:GetAttribute("CategorySelected") == true
    local dur = animate and 0.16 or 0
    local lit = selected or catHover
    -- Hover: full indigo wipe, stay inset (not moved right)
    -- Selected: full indigo + expanded (moved right) + selection lines
    local fillSize = selected and UDim2.new(1, 0, 1, 0) or UDim2.new(1, -16, 1, 0)
    tw(tabFill, dur, { Size = fillSize })
    tw(tabWipe, dur, { Size = lit and UDim2.new(1, 0, 1, 0) or UDim2.new(0, 0, 1, 0) })
    selLineTop.Visible = selected
    selLineBot.Visible = selected
    -- Raise ZIndex above siblings when hovered or selected
    setCategoryRaised(selected or catHover, animate)
    tw(catLabel, dur, { TextColor3 = lit and Theme.Cream or Theme.Ink })
    local markCol = lit and Theme.Cream or Theme.Accent
    if catAsset then
        catMarker.ImageColor3 = markCol
    else
        catMarker.BackgroundColor3 = markCol
    end
end
btn.MouseEnter:Connect(function()
    catHover = true
    catLook(true)
    if Library._sfx then Library._sfx("hover") end
end)
btn.MouseLeave:Connect(function() catHover = false; catLook(true) end)
if UserInputService.TouchEnabled then
    local categoryTouch
    btn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch then
            categoryTouch = input
            catHover = true
            catLook(true)
            if Library._sfx then Library._sfx("hover") end
        end
    end)
    connect(UserInputService.InputEnded, function(input)
        if categoryTouch and input == categoryTouch then
            categoryTouch = nil
            catHover = false
            catLook(true)
        end
    end)
end
btn:GetAttributeChangedSignal("CategorySelected"):Connect(function() catLook(true) end)
table.insert(lookers, { row = btn, fn = catLook })
catLook(false)

local CategoryPage = new("ScrollingFrame", {
    Name = CategoryName .. "Page",
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Size = UDim2.fromScale(1, 1),
    ScrollBarThickness = 0,
    CanvasSize = UDim2.new(),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    Visible = false,
}, ContentContainer)
new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 7) }, CategoryPage)
new("UIPadding", {
    PaddingLeft = UDim.new(0, 22), PaddingRight = UDim.new(0, 40),
    PaddingTop = UDim.new(0, 16), PaddingBottom = UDim.new(0, 14),
}, CategoryPage)

local heading = new("Frame", {
    Name = "Heading",
    BackgroundTransparency = 1,
    Size = UDim2.new(1, 0, 0, 36),
    LayoutOrder = 0,
}, CategoryPage)
local headShadow = new("TextLabel", {
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(-9, 2),
    Size = UDim2.new(1, 11, 1, 0),
    Text = CategoryName,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTransparency = 0.5,
}, heading)
bindFont(headShadow, 24, false)
bind(headShadow, "TextColor3", function(t)
    return t.Line:Lerp(t.Ink, 0.15)
end)
local headLabel = new("TextLabel", {
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(-11, 0),
    Size = UDim2.new(1, 11, 1, 0),
    Text = CategoryName,
    TextXAlignment = Enum.TextXAlignment.Left,
    ZIndex = 2,
}, heading)
bindFont(headLabel, 24, false)
bind(headLabel, "TextColor3", "Ink")

-- The one-column path remains the original CategoryPage list. In two-column
-- mode controls are allocated to whichever column currently has less content.
local viewportWidth = vp and vp.X or 1280
local useTwoColumns = layout.ify == "2" and (not layout.Responsive or viewportWidth >= 680)
local ColumnsHost
local ColumnFrames = {}
local ColumnHeights = { 0, 0 }
if useTwoColumns then
    ColumnsHost = new("Frame", {
        Name = "ColumnsHost",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, -62, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder = 1,
        ClipsDescendants = false,
    }, CategoryPage)
    new("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        VerticalAlignment = Enum.VerticalAlignment.Top,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, layout.Gap),
    }, ColumnsHost)

    for index, sideName in ipairs({ "Left", "Right" }) do
        local column = new("Frame", {
            Name = sideName .. "Column",
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Size = UDim2.new(0.5, -layout.Gap / 2, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            LayoutOrder = index,
            ClipsDescendants = false,
        }, ColumnsHost)
        new("UIListLayout", {
            FillDirection = Enum.FillDirection.Vertical,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 7),
        }, column)
        ColumnFrames[index] = column
    end
end

local function categoryItemParent(estimatedHeight)
    if not useTwoColumns then
        return CategoryPage
    end

    local height = math.max(tonumber(estimatedHeight) or 28, 1) + 7

    -- Internal utility pages stay in column 1. Regular user categories keep
    -- the height-balanced allocator across both columns.
    if CategoryName == "SETTINGS" or CategoryName == "HELLO" then
        ColumnHeights[1] += height
        return ColumnFrames[1]
    end

    local index = ColumnHeights[1] <= ColumnHeights[2] and 1 or 2
    ColumnHeights[index] += height
    return ColumnFrames[index]
end

local railThumb = new("Frame", {
    Name = CategoryName .. "Thumb",
    BorderSizePixel = 0,
    Visible = false,
    ZIndex = 6,
}, rail)
bind(railThumb, "BackgroundColor3", "Accent")
local function syncThumb()
    local canvas, view = CategoryPage.AbsoluteCanvasSize.Y, CategoryPage.AbsoluteWindowSize.Y
    if not CategoryPage.Visible or canvas <= view + 1 then
        railThumb.Visible = false
        return
    end
    local h = math.clamp(view / canvas, 0.1, 1)
    local maxScroll = math.max(canvas - view, 1)
    local y = math.clamp(CategoryPage.CanvasPosition.Y / maxScroll, 0, 1) * (1 - h)
    railThumb.Size = UDim2.new(1, -4, h, 0)
    railThumb.Position = UDim2.new(0, 2, y, 0)
    railThumb.Visible = true
end
CategoryPage:GetPropertyChangedSignal("CanvasPosition"):Connect(syncThumb)
CategoryPage:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(syncThumb)
CategoryPage:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(syncThumb)
CategoryPage:GetPropertyChangedSignal("Visible"):Connect(syncThumb)

local order = 0
local function nextOrder()
    order += 1
    return order
end

-- Remove only generated controls. Keep the category's layout containers alive,
-- because control factories retain references to the two column frames.
function CategoryElements:ClearItems()
    if useTwoColumns and ColumnsHost and ColumnsHost.Parent then
        for index, column in ipairs(ColumnFrames) do
            for _, child in ipairs(column:GetChildren()) do
                if not child:IsA("UIListLayout") then
                    child:Destroy()
                end
            end
            ColumnHeights[index] = 0
        end
    else
        for _, child in ipairs(CategoryPage:GetChildren()) do
            if not (child:IsA("UIListLayout") or child:IsA("UIPadding") or child.Name == "Heading") then
                child:Destroy()
            end
        end
    end
    order = 0
end

local function SelectTab(silent)
    -- AUTH tab is always allowed while locked; everything else is blocked
    local isAuthTab = (CategoryName == "AUTH")
    if KeySystemEnabled and not KeyAuthenticated and not isAuthTab then
        Notify("Complete authentication first.", 3.5)
        return
    end
    if not silent and Library._sfx then Library._sfx("select") end
    SettingsState.open = false
    for _, page in ipairs(ContentContainer:GetChildren()) do
        if page:IsA("ScrollingFrame") then
            cancelPageAnimation(page)
            page.Visible = false
        end
    end
    for _, b in ipairs(Sidebar:GetChildren()) do
        if b:IsA("TextButton") then
            b:SetAttribute("CategorySelected", false)
        end
    end
    CategoryPage.Visible = true
    AnimatePageIn(CategoryPage)
    btn:SetAttribute("CategorySelected", true)
end
if not Hidden then
    btn.MouseButton1Click:Connect(function() SelectTab(false) end)
    if isFirstTab and (not KeySystemEnabled or KeyAuthenticated) then
        SelectTab(true)
        isFirstTab = false
    elseif isFirstTab then
        isFirstTab = false
    end
end

local function newRow(className, height)
    local row = new(className, {
        Size = UDim2.new(1, 0, 0, height or 28),
        BorderSizePixel = 0,
        LayoutOrder = nextOrder(),
    }, categoryItemParent(height or 28))
if className == "TextButton" then
    row.AutoButtonColor = false
    row.Text = ""
end
bind(row, "BackgroundColor3", "Row")
bindGlass(row)
addGradient(row, function(t)
    return makeGradientSequence(t.Row, t.Row:Lerp(t.Accent, 0.12))
end)
return row
end

local function addMarker(parent, iconName)
    local asset = resolveIcon(iconName)
    if asset then
        local img = new("ImageLabel", {
            BackgroundTransparency = 1,
            Position = UDim2.new(0, 7, 0.5, -8),
            Size = UDim2.fromOffset(16, 16),
            Image = asset,
        }, parent)
    return img, true
end
local sq = new("Frame", {
    Position = UDim2.new(0, 7, 0.5, -6),
    Size = UDim2.fromOffset(12, 12),
    BorderSizePixel = 0,
}, parent)
local st = new("UIStroke", { Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, sq)
bind(st, "Color", "Accent")
return sq, false
end

local function addLabel(parent, text, x, scale, reserve)
    x = x - 6
    local l = new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, x, 0, 0),
        Size = UDim2.new(scale or 1, -(x + 10 + (reserve or 0)), 1, 0),
        Text = text,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, parent)
bindFont(l, 13, false)
return l
end

local function hoverable(o)
    local state = { hover = false, pressed = false }
    local setRaised = makeRaiseController(o.row, 1.04)
    local fullSize = o.wipeHeight and UDim2.new(1, 0, 0, o.wipeHeight) or UDim2.new(1, 0, 1, 0)
    local emptySize = o.wipeHeight and UDim2.new(0, 0, 0, o.wipeHeight) or UDim2.new(0, 0, 1, 0)

    local wipe = new("Frame", {
        Name = "Wipe",
        BorderSizePixel = 0,
        ZIndex = 0,
        Size = emptySize,
    }, o.row)
bind(wipe, "BackgroundColor3", "Accent")
new("UIGradient", {
    Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(0.8, 0),
        NumberSequenceKeypoint.new(1, 0.55),
    }),
}, wipe)

local dia, tail
if not o.noDiamond then
    dia = new("Frame", {
        Position = UDim2.new(0, -15, 0.5, -3),
        Size = UDim2.fromOffset(6, 6),
        Rotation = 45,
        BorderSizePixel = 0,
        Visible = false,
    }, o.row)
tail = new("Frame", {
    Position = UDim2.new(0, -21, 0.5, 0),
    Size = UDim2.fromOffset(5, 1),
    BorderSizePixel = 0,
    Visible = false,
}, o.row)
local function markColor(t)
    return t.Line:Lerp(t.Accent, 0.55)
end
bind(dia, "BackgroundColor3", markColor)
bind(tail, "BackgroundColor3", markColor)
end

local function look(animate)
    local h = state.hover
    local dur = animate and 0.14 or 0
    tw(wipe, dur, { Size = h and fullSize or emptySize })
    for _, l in ipairs(o.labels) do
        tw(l, dur, { TextColor3 = h and Theme.Cream or (o.color or Theme.Ink) })
    end
    local active = o.active and o.active() or false
    setRaised(h or state.pressed or active, animate)
    if o.hasIcon then
        o.marker.ImageColor3 = (h or active) and Theme.Cream or Theme.Accent
    else
        o.marker.BackgroundColor3 = (h or active) and Theme.Cream or Theme.Accent
    end
    if dia then
        dia.Visible = h
        tail.Visible = h
    end
end
local target = o.target or o.row
target.MouseEnter:Connect(function()
    state.hover = true
    look(true)
    if Library._sfx then Library._sfx("hover") end
end)
target.MouseLeave:Connect(function() state.hover = false; look(true) end)
if UserInputService.TouchEnabled then
    local activeTouch
    target.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch then
            activeTouch = input
            state.pressed = true
            look(true)
            if Library._sfx then Library._sfx("hover") end
        end
    end)
    connect(UserInputService.InputEnded, function(input)
        if activeTouch and input == activeTouch then
            activeTouch = nil
            state.pressed = false
            look(true)
        end
    end)
end
table.insert(lookers, { row = o.row, fn = look })
look(false)
return state, look, wipe
end

local function inputBox(row, placeholder, text, width)
    local bg = new("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -8, 0.5, 0),
        Size = UDim2.fromOffset(width or 150, 20),
        BorderSizePixel = 0,
    }, row)
bind(bg, "BackgroundColor3", inputColor)
local st = new("UIStroke", { Thickness = 1 }, bg)
bind(st, "Color", "Line")
local tb = new("TextBox", {
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(6, 0),
    Size = UDim2.new(1, -12, 1, 0),
    PlaceholderText = placeholder or "",
    Text = text or "",
    ClearTextOnFocus = false,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
}, bg)
bindFont(tb, 12, false)
bind(tb, "TextColor3", "Ink")
bind(tb, "PlaceholderColor3", dimInk)
return tb
end

function CategoryElements:CreateLabel(Text, IconName, TextColor)
    if typeof(IconName) == "Color3" then
        TextColor = IconName
        IconName = nil
    end
    local holder = new("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 26),
        LayoutOrder = nextOrder(),
    }, categoryItemParent(26))
local x = 0
local asset = resolveIcon(IconName)
if asset then
    local img = new("ImageLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 0, 0.5, -8),
        Size = UDim2.fromOffset(16, 16),
        Image = asset,
    }, holder)
bind(img, "ImageColor3", "Accent")
x = 22
end
local l = new("TextLabel", {
    BackgroundTransparency = 1,
    Position = UDim2.new(0, x, 0, 0),
    Size = UDim2.new(1, -x, 1, -2),
    Text = Text,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
}, holder)
bindFont(l, 14, true)
if TextColor then
    l.TextColor3 = TextColor
else
    bind(l, "TextColor3", "Accent")
end
hline(holder, UDim2.new(0, 0, 1, -1), UDim2.new(1, 0, 0, 1))
return l
end

function CategoryElements:CreateButton(ButtonText, IconName, TextColor, Callback)
    if type(IconName) == "function" then
        Callback = IconName; IconName = nil; TextColor = nil
    end
    if typeof(IconName) == "Color3" then
        Callback = TextColor; TextColor = IconName; IconName = nil
    end
    if type(TextColor) == "function" then
        Callback = TextColor; TextColor = nil
    end

    local row = newRow("TextButton")
    local marker, hasIcon = addMarker(row, IconName)
    local lbl = addLabel(row, ButtonText, hasIcon and 32 or 30)
    local state, look, wipe = hoverable({
        row = row, marker = marker, hasIcon = hasIcon, labels = { lbl }, color = TextColor,
    })

row.MouseButton1Click:Connect(function()
    if Library._sfx then Library._sfx("select") end
    wipe.BackgroundColor3 = Theme.Accent:Lerp(Theme.Cream, 0.35)
    task.delay(0.1, function()
        wipe.BackgroundColor3 = Theme.Accent
        if UserInputService.TouchEnabled then
            state.hover = false
        end
        look(true)
    end)
    if Callback then
        task.spawn(Callback)
    end
end)

return {
    SetText = function(t)
        lbl.Text = tostring(t)
    end,
}
end

function CategoryElements:CreateTextbox(TextboxText, IconName, Placeholder, Flag, Callback)
    if type(Flag) == "function" then
        Callback = Flag; Flag = nil
    end
    local restored = nil
    if Flag and SavedFlags[Flag] ~= nil then
        restored = SavedFlags[Flag]
    end

    local row = newRow("Frame", useTwoColumns and 48 or 28)
    local marker, hasIcon = addMarker(row, IconName)
    local textboxWidth = useTwoColumns and 118 or 150
    local lbl = addLabel(row, TextboxText, hasIcon and 32 or 30, 1, textboxWidth + 8)
    bind(lbl, "TextColor3", "Ink")
    if hasIcon then bind(marker, "ImageColor3", "Accent") else bind(marker, "BackgroundColor3", "Accent") end

    local tb = inputBox(row, Placeholder, restored ~= nil and tostring(restored) or "", textboxWidth)
    if useTwoColumns then
        lbl.Position = UDim2.new(0, hasIcon and 32 or 24, 0, 0)
        lbl.Size = UDim2.new(1, hasIcon and -44 or -34, 0, 20)
        marker.Position = UDim2.new(0, 7, 0, hasIcon and 2 or 4)
        tb.Parent.AnchorPoint = Vector2.new(0, 0)
        tb.Parent.Position = UDim2.fromOffset(8, 24)
        tb.Parent.Size = UDim2.new(1, -16, 0, 20)
    end
    if Flag then
        Flags[Flag] = { Type = "Textbox", Value = tb.Text }
    end
    tb.FocusLost:Connect(function()
        if Flag then
            Flags[Flag].Value = tb.Text
            save()
        end
        if Callback then
            Callback(tb.Text)
        end
    end)

    return {
        Get = function()
            return tb.Text
        end,
        Set = function(v)
            tb.Text = tostring(v or "")
            if Flag then
                Flags[Flag].Value = tb.Text
            end
        end,
        TextBox = tb,
    }
end

function CategoryElements:CreateNumberTextbox(LabelText, IconName, DefaultNumber, Flag, Callback)
    if type(Flag) == "function" then
        Callback = Flag; Flag = nil
    end
    if Flag and SavedFlags[Flag] ~= nil then
        DefaultNumber = SavedFlags[Flag]
    end

    local row = newRow("Frame", useTwoColumns and 48 or 28)
    local marker, hasIcon = addMarker(row, IconName)
    local textboxWidth = useTwoColumns and 118 or 150
    local lbl = addLabel(row, LabelText, hasIcon and 32 or 30, 1, textboxWidth + 8)
    bind(lbl, "TextColor3", "Ink")
    if hasIcon then bind(marker, "ImageColor3", "Accent") else bind(marker, "BackgroundColor3", "Accent") end

    local tb = inputBox(row, tostring(DefaultNumber or ""), DefaultNumber and tostring(DefaultNumber) or "", textboxWidth)
    if useTwoColumns then
        lbl.Position = UDim2.new(0, hasIcon and 32 or 24, 0, 0)
        lbl.Size = UDim2.new(1, hasIcon and -44 or -34, 0, 20)
        marker.Position = UDim2.new(0, 7, 0, hasIcon and 2 or 4)
        tb.Parent.AnchorPoint = Vector2.new(0, 0)
        tb.Parent.Position = UDim2.fromOffset(8, 24)
        tb.Parent.Size = UDim2.new(1, -16, 0, 20)
    end
    if Flag then
        Flags[Flag] = { Type = "NumberTextbox", Value = tonumber(tb.Text) }
    end
    tb.FocusLost:Connect(function()
        local n = tonumber(tb.Text)
        if Flag then
            Flags[Flag].Value = n
            save()
        end
        if Callback then
            Callback(n)
        end
    end)

    return {
        Get = function()
            return tonumber(tb.Text)
        end,
        GetText = function()
            return tb.Text
        end,
        Set = function(v)
            local n = tonumber(v)
            if not n or n ~= n then return false end
            tb.Text = tostring(n)
            if Flag then Flags[Flag].Value = n end
            if Callback then Callback(n) end
            return true
        end,
        TextBox = tb,
    }
end

function CategoryElements:CreateSearchBar(Placeholder, IconName, Callback)
    if type(IconName) == "function" then
        Callback = IconName; IconName = nil
    end
    IconName = IconName or "lucide-search"

    local row = newRow("Frame")
    local img = new("ImageLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 8, 0.5, -8),
        Size = UDim2.fromOffset(16, 16),
        Image = resolveIcon(IconName) or "",
    }, row)
bind(img, "ImageColor3", "Accent")
local tb = new("TextBox", {
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(32, 0),
    Size = UDim2.new(1, -42, 1, 0),
    PlaceholderText = Placeholder or "Search",
    Text = "",
    ClearTextOnFocus = false,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
}, row)
bindFont(tb, 13, false)
bind(tb, "TextColor3", "Ink")
bind(tb, "PlaceholderColor3", dimInk)
tb:GetPropertyChangedSignal("Text"):Connect(function()
    if Callback then
        Callback(tb.Text)
    end
end)
return {
    Get = function() return tb.Text end,
    Set = function(value) tb.Text = tostring(value or "") end,
    TextBox = tb,
}
end

function CategoryElements:CreateToggle(ToggleText, IconName, DefaultState, Flag, Callback)
    if type(IconName) == "boolean" then
        Callback = Flag; Flag = DefaultState; DefaultState = IconName; IconName = nil
    end
    if type(Flag) == "function" then
        Callback = Flag; Flag = nil
    end
    if Flag and SavedFlags[Flag] ~= nil then
        DefaultState = SavedFlags[Flag]
    end
    local current = DefaultState == true
    if Flag then
        Flags[Flag] = { Type = "Toggle", Value = current }
    end

    local row = newRow("TextButton")
    local marker, hasIcon = addMarker(row, IconName)
    local lbl = addLabel(row, ToggleText, hasIcon and 32 or 30, 1, 44)
    local val = new("TextLabel", {
        BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.fromOffset(40, 20),
        TextXAlignment = Enum.TextXAlignment.Right,
    }, row)
bindFont(val, 11, true)
local _, look = hoverable({
    row = row, marker = marker, hasIcon = hasIcon, labels = { lbl, val },
    active = function() return current end,
})

local function apply(fire)
    val.Text = current and "ON" or "OFF"
    look(true)
    if fire and Callback then
        task.spawn(Callback, current)
    end
end
apply(true)

row.MouseButton1Click:Connect(function()
    current = not current
    if Flag then
        Flags[Flag].Value = current
        save()
    end
    apply(true)
    if Library._sfx then
        Library._sfx(current and "toggleOn" or "toggleOff")
    end
end)

row:SetAttribute("NoSelectSfx", true)

return {
    Set = function(v)
        current = v == true
        if Flag then Flags[Flag].Value = current end
        apply(true)
    end,
    Get = function() return current end,
}
end

function CategoryElements:CreateSlider(SliderText, IconName, Min, Max, Default, Flag, Callback)
    if type(IconName) == "number" then
        Callback = Flag; Flag = Default; Default = Max; Max = Min; Min = IconName; IconName = nil
    end
    if type(Flag) == "function" then
        Callback = Flag; Flag = nil
    end

    Min = tonumber(Min) or 0
    Max = tonumber(Max) or 100
    if Min ~= Min then Min = 0 end
    if Max ~= Max then Max = 100 end
    if Min > Max then Min, Max = Max, Min end
    if Flag and SavedFlags[Flag] ~= nil then
        Default = SavedFlags[Flag]
    end
    local defaultNumber = tonumber(Default)
    if not defaultNumber or defaultNumber ~= defaultNumber then defaultNumber = Min end
    local value = math.clamp(defaultNumber, Min, Max)
    if Flag then
        Flags[Flag] = { Type = "Slider", Value = value }
    end

    local row = newRow("Frame")
    local badge = new("TextLabel", {
        Position = UDim2.new(0, 7, 0.5, -7),
        Size = UDim2.fromOffset(18, 14),
        BorderSizePixel = 0,
    }, row)
bind(badge, "BackgroundColor3", "Accent")
bind(badge, "TextColor3", "Cream")
bindFont(badge, 10, true)

local iconImg
local asset = resolveIcon(IconName)
if asset then
    iconImg = new("ImageLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.fromOffset(16, 16),
        Image = asset,
    }, row)
bind(iconImg, "ImageColor3", "Accent")
end
local lbl = addLabel(row, SliderText, 36, 0.6)
bind(lbl, "TextColor3", "Ink")

local function layout()
    local bw = math.max(16, 8 + 6 * #badge.Text)
    badge.Size = UDim2.fromOffset(bw, 14)
    local x = 7 + bw + 8
    if iconImg then
        iconImg.Position = UDim2.new(0, x, 0.5, -8)
        x = x + 22
    end
    lbl.Position = UDim2.new(0, x, 0, 0)
    lbl.Size = UDim2.new(1, -(x + (useTwoColumns and 108 or 140)), 1, 0)
end

local track = new("Frame", {
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -16, 0.5, 0),
    Size = UDim2.new(0.3, 0, 0, 22),
    BackgroundTransparency = 1,
    Active = true,
}, row)
new("UISizeConstraint", { MinSize = Vector2.new(72, 22), MaxSize = Vector2.new(120, 22) }, track)

local N = 32
local ticks, dots = {}, {}
for i = 1, N do
    local px = (i - 0.5) / N
    dots[i] = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(px, 0, 0.5, 0),
        Size = UDim2.fromOffset(1, 1),
        BorderSizePixel = 0,
    }, track)
ticks[i] = new("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(px, 0, 0.5, 0),
    Size = UDim2.fromOffset(1, 8),
    BorderSizePixel = 0,
}, track)
end
local thumb = new("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Size = UDim2.fromOffset(2, 12),
    BorderSizePixel = 0,
    ZIndex = 2,
}, track)
bind(thumb, "BackgroundColor3", "Ink")

local function render()
    local f = (Max == Min) and 0 or (value - Min) / (Max - Min)
    badge.Text = tostring(value)
    layout()
    thumb.Position = UDim2.new(f, 0, 0.5, 0)
    for i = 1, N do
        local filled = ((i - 0.5) / N) <= f
        ticks[i].BackgroundColor3 = Theme.Ink
        ticks[i].BackgroundTransparency = filled and 0 or 1
        dots[i].BackgroundColor3 = Theme.Ink
        dots[i].BackgroundTransparency = filled and 1 or 0.35
    end
end
render()
table.insert(lookers, { row = row, fn = render })

makeDrag(track, function(input)
    local rel = math.clamp((input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
    local newValue = math.clamp(math.floor(Min + (Max - Min) * rel + 0.5), Min, Max)
    local changed = newValue ~= value
    value = newValue
    render()
    if changed and Library._sfx then

        Library._sfx("slider")
    end
    if Flag then
        Flags[Flag].Value = value
    end
    if Callback then
        Callback(value)
    end
end, function()
if Flag then
    save()
end
end)

return {
    Set = function(v)
        local numeric = tonumber(v)
        if not numeric or numeric ~= numeric then return false end
        local nextValue = math.clamp(numeric, Min, Max)
        local changed = nextValue ~= value
        value = nextValue
        if Flag then Flags[Flag].Value = value end
        render()
        if changed and Callback then Callback(value) end
        return true
    end,
    Get = function() return value end,
}
end

function CategoryElements:CreateColorPicker(PickerText, IconName, DefaultColor, Flag, Callback)
    if typeof(IconName) == "Color3" then
        Callback = Flag; Flag = DefaultColor; DefaultColor = IconName; IconName = nil
    end
    if type(Flag) == "function" then
        Callback = Flag; Flag = nil
    end
    if Flag and SavedFlags[Flag] ~= nil then
        local sv = SavedFlags[Flag]
        if type(sv) == "table" and sv[3] then
            DefaultColor = Color3.fromRGB(sv[1], sv[2], sv[3])
        end
    end
    DefaultColor = DefaultColor or WHITE

    local Hue, Sat, Val = DefaultColor:ToHSV()
    local current = DefaultColor
    if Flag then
        Flags[Flag] = { Type = "ColorPicker", Value = arr(DefaultColor) }
    end

    local expanded = false
    local container = newRow("Frame", 28)
    container.ClipsDescendants = true
    local header = new("TextButton", {
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        Size = UDim2.new(1, 0, 0, 28),
    }, container)
local marker, hasIcon = addMarker(header, IconName)
local lbl = addLabel(header, PickerText, hasIcon and 32 or 30, 1, 100)
local hexLbl = new("TextLabel", {
    BackgroundTransparency = 1,
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -32, 0.5, 0),
    Size = UDim2.fromOffset(62, 20),
    TextXAlignment = Enum.TextXAlignment.Right,
}, header)
bindFont(hexLbl, 11, true)
local swatch = new("Frame", {
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -10, 0.5, 0),
    Size = UDim2.fromOffset(16, 16),
    BorderSizePixel = 0,
    BackgroundColor3 = DefaultColor,
}, header)
local sst = new("UIStroke", { Thickness = 1 }, swatch)
bind(sst, "Color", "Accent")

hoverable({
    row = container, target = header, marker = marker, hasIcon = hasIcon,
    labels = { lbl, hexLbl }, noDiamond = true, wipeHeight = 28,
})

local svBox = new("Frame", {
    Position = UDim2.fromOffset(8, 34), Size = UDim2.new(1, -16, 0, 92),
    BorderSizePixel = 0, BackgroundColor3 = Color3.fromHSV(Hue, 1, 1),
    ClipsDescendants = true, Visible = false,
}, container)
local satO = new("Frame", { Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, BackgroundColor3 = WHITE }, svBox)
new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }) }, satO)
local valO = new("Frame", { Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, BackgroundColor3 = Color3.new(0, 0, 0) }, svBox)
new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) }) }, valO)
local svCursor = new("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(9, 9),
    BorderSizePixel = 0, BackgroundColor3 = WHITE, ZIndex = 5,
}, svBox)
new("UIStroke", { Thickness = 2, Color = Color3.new(0, 0, 0) }, svCursor)
local svBtn = new("TextButton", {
    BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Size = UDim2.fromScale(1, 1), ZIndex = 6,
}, svBox)

local hueBar = new("Frame", {
    Position = UDim2.fromOffset(8, 132), Size = UDim2.new(1, -16, 0, 14),
    BorderSizePixel = 0, Visible = false,
}, container)
new("UIGradient", {
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromHSV(0, 1, 1)),
        ColorSequenceKeypoint.new(0.166, Color3.fromHSV(1 / 6, 1, 1)),
        ColorSequenceKeypoint.new(0.333, Color3.fromHSV(2 / 6, 1, 1)),
        ColorSequenceKeypoint.new(0.5, Color3.fromHSV(3 / 6, 1, 1)),
        ColorSequenceKeypoint.new(0.666, Color3.fromHSV(4 / 6, 1, 1)),
        ColorSequenceKeypoint.new(0.833, Color3.fromHSV(5 / 6, 1, 1)),
        ColorSequenceKeypoint.new(1, Color3.fromHSV(1, 1, 1)),
    }),
}, hueBar)
local hueCursor = new("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(Hue, 0, 0.5, 0),
    Size = UDim2.new(0, 5, 1, 4), BorderSizePixel = 0, BackgroundColor3 = WHITE, ZIndex = 5,
}, hueBar)
new("UIStroke", { Thickness = 2, Color = Color3.new(0, 0, 0) }, hueCursor)
local hueBtn = new("TextButton", {
    BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Size = UDim2.fromScale(1, 1), ZIndex = 6,
}, hueBar)

local function refreshHex()
    hexLbl.Text = toHex(current)
end
refreshHex()
local function commit()
    current = Color3.fromHSV(Hue, Sat, Val)
    svBox.BackgroundColor3 = Color3.fromHSV(Hue, 1, 1)
    svCursor.Position = UDim2.new(Sat, 0, 1 - Val, 0)
    hueCursor.Position = UDim2.new(Hue, 0, 0.5, 0)
    swatch.BackgroundColor3 = current
    refreshHex()
    if Flag then
        Flags[Flag].Value = arr(current)
    end
    if Callback then
        Callback(current)
    end
end
svCursor.Position = UDim2.new(Sat, 0, 1 - Val, 0)

makeDrag(svBtn, function(input)
    Sat = math.clamp((input.Position.X - svBox.AbsolutePosition.X) / svBox.AbsoluteSize.X, 0, 1)
    Val = 1 - math.clamp((input.Position.Y - svBox.AbsolutePosition.Y) / svBox.AbsoluteSize.Y, 0, 1)
    svCursor.Position = UDim2.new(Sat, 0, 1 - Val, 0)
    commit()
end, function()
if Flag then save() end
end)
makeDrag(hueBtn, function(input)
    Hue = math.clamp((input.Position.X - hueBar.AbsolutePosition.X) / hueBar.AbsoluteSize.X, 0, 1)
    hueCursor.Position = UDim2.new(Hue, 0, 0.5, 0)
    svBox.BackgroundColor3 = Color3.fromHSV(Hue, 1, 1)
    commit()
end, function()
if Flag then save() end
end)

header.MouseButton1Click:Connect(function()
    if Library._sfx then Library._sfx("select") end
    expanded = not expanded
    svBox.Visible = expanded
    hueBar.Visible = expanded
    TweenService:Create(container, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
        Size = UDim2.new(1, 0, 0, expanded and 154 or 28),
    }):Play()
end)

return {
    Get = function() return current end,
    Set = function(color)
        if typeof(color) ~= "Color3" then return false end
        Hue, Sat, Val = color:ToHSV()
        commit()
        return true
    end,
    GetHex = function() return toHex(current) end,
    Container = container,
}
end

local function buildDropdown(multi, text, icon, options, default, flag, callback)
    options = type(options) == "table" and options or {}
    local selSet, selOrder, currentVal = {}, {}, nil
    if multi then
        if type(default) == "table" then
            for _, v in ipairs(default) do
                if v ~= nil and not selSet[v] then
                    selSet[v] = true
                    table.insert(selOrder, v)
                end
            end
        end
    else
        currentVal = default
    end
    if flag then
        Flags[flag] = { Type = multi and "MultiDropdown" or "Dropdown", Value = multi and selOrder or currentVal }
    end

    local isOpen = false
    local container = newRow("Frame", 28)
    container.ClipsDescendants = true
    local header = new("TextButton", {
        BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Size = UDim2.new(1, 0, 0, 28),
    }, container)
local marker, hasIcon = addMarker(header, icon)
local lbl = addLabel(header, "", hasIcon and 32 or 30, 1, 22)
local arrow = new("TextLabel", {
    BackgroundTransparency = 1,
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -8, 0.5, 0),
    Size = UDim2.fromOffset(16, 20),
    Text = "▼",
}, header)
bindFont(arrow, 10, true)
hoverable({
    row = container, target = header, marker = marker, hasIcon = hasIcon,
    labels = { lbl, arrow }, noDiamond = true, wipeHeight = 28,
})

local function headerText()
    if multi then
        return text .. " : " .. (#selOrder == 0 and "None" or joinList(selOrder))
    end
    return text .. " : " .. (currentVal ~= nil and tostring(currentVal) or "")
end
lbl.Text = headerText()

local listTop = multi and 56 or 30
local listFrame = new("Frame", {
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(0, 28),
    Size = UDim2.new(1, 0, 1, -28),
}, container)
bind(listFrame, "BackgroundColor3", listColor)

local search = new("TextBox", {
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(4, 3),
    Size = UDim2.new(1, -8, 0, 24),
    PlaceholderText = "Search",
    Text = "",
    ClearTextOnFocus = false,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
}, listFrame)
new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, search)
bind(search, "BackgroundColor3", inputColor)
bind(search, "TextColor3", "Ink")
bind(search, "PlaceholderColor3", dimInk)
bindFont(search, 12, false)

local scroll = new("ScrollingFrame", {
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(0, listTop),
    Size = UDim2.new(1, 0, 1, -listTop),
    ScrollBarThickness = 3,
    CanvasSize = UDim2.new(),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, listFrame)
bind(scroll, "ScrollBarImageColor3", "Accent")
new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, scroll)

local entries = {}
local function visibleCount()
    local n = 0
    for _, e in ipairs(entries) do
        if e.btn.Visible then n += 1 end
    end
    return n
end
local function updateSize()
    local target = isOpen and (28 + listTop + math.min(visibleCount(), 6) * 24 + 4) or 28
    TweenService:Create(container, TweenInfo.new(0.18), { Size = UDim2.new(1, 0, 0, target) }):Play()
    arrow.Text = isOpen and "▲" or "▼"
end
local function paintMarks()
    for _, e in ipairs(entries) do
        local selected
        if multi then selected = selSet[e.value] == true else selected = currentVal == e.value end
        e.mark.Text = selected and "◆" or ""
        if e.setRaised then e.setRaised(selected or e.hovering or e.pressed, true) end
    end
    lbl.Text = headerText()
end
local function fire()
    if flag then
        Flags[flag].Value = multi and selOrder or currentVal
        save()
    end
    if callback then
        callback(multi and selOrder or currentVal)
    end
end
local function setChecked(e, state, silent)
    if state and not selSet[e.value] then
        selSet[e.value] = true
        table.insert(selOrder, e.value)
    elseif (not state) and selSet[e.value] then
        selSet[e.value] = nil
        for i, v in ipairs(selOrder) do
            if v == e.value then table.remove(selOrder, i) break end
        end
    end
    if not silent then
        paintMarks()
        fire()
    end
end

local function addOption(opt)
    local b = new("TextButton", {
        BackgroundTransparency = 1, BorderSizePixel = 0, AutoButtonColor = false,
        Text = "", Size = UDim2.new(1, 0, 0, 24),
    }, scroll)
local mark = new("TextLabel", {
    BackgroundTransparency = 1, Position = UDim2.fromOffset(8, 0), Size = UDim2.fromOffset(16, 24),
}, b)
bindFont(mark, 10, true)
bind(mark, "TextColor3", "Accent")
local ol = new("TextLabel", {
    BackgroundTransparency = 1, Position = UDim2.fromOffset(28, 0), Size = UDim2.new(1, -36, 1, 0),
    Text = tostring(opt), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
}, b)
bindFont(ol, 13, false)
bind(ol, "TextColor3", "Ink")
local entry = { btn = b, value = opt, mark = mark, text = string.lower(tostring(opt)), hovering = false, pressed = false }
entry.setRaised = makeRaiseController(b, 1.025)
table.insert(entries, entry)

b.MouseEnter:Connect(function()
    entry.hovering = true
    entry.setRaised(true, true)
    if Library._sfx then Library._sfx("hover") end
    b.BackgroundTransparency = 0
    b.BackgroundColor3 = Theme.Accent
    ol.TextColor3 = Theme.Cream
    mark.TextColor3 = Theme.Cream
end)
b.MouseLeave:Connect(function()
    entry.hovering = false
    local selected = multi and selSet[opt] == true or (not multi and currentVal == opt)
    entry.setRaised(selected or entry.pressed, true)
    b.BackgroundTransparency = 1
    ol.TextColor3 = Theme.Ink
    mark.TextColor3 = Theme.Accent
end)
if UserInputService.TouchEnabled then
    local optionTouch
    b.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch then
            optionTouch = input
            entry.pressed = true
            entry.setRaised(true, true)
            if Library._sfx then Library._sfx("hover") end
        end
    end)
    connect(UserInputService.InputEnded, function(input)
        if optionTouch and input == optionTouch then
            optionTouch = nil
            entry.pressed = false
            local selected = multi and selSet[opt] == true or (not multi and currentVal == opt)
            entry.setRaised(selected or entry.hovering, true)
        end
    end)
end
b.MouseButton1Click:Connect(function()
    if Library._sfx then Library._sfx("select") end
    if multi then
        setChecked(entry, not selSet[opt])
    else
        currentVal = opt
        isOpen = false
        paintMarks()
        updateSize()
        fire()
    end
end)
end

local function rebuild(newOptions)
    newOptions = type(newOptions) == "table" and newOptions or {}
    for _, e in ipairs(entries) do
        e.btn:Destroy()
    end
    table.clear(entries)
    for _, opt in ipairs(newOptions) do
        if opt ~= nil then addOption(opt) end
    end

    if multi then
        local available = {}
        for _, e in ipairs(entries) do available[e.value] = true end
        for i = #selOrder, 1, -1 do
            local selected = selOrder[i]
            if not available[selected] then
                selSet[selected] = nil
                table.remove(selOrder, i)
            end
        end
    elseif currentVal ~= nil then
        local found = false
        for _, e in ipairs(entries) do
            if e.value == currentVal then found = true break end
        end
        if not found then currentVal = nil end
    end

    paintMarks()
    updateSize()
end

if multi then
    local quick = new("Frame", {
        BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 0, 24),
    }, listFrame)
local function quickBtn(txt, xScale, fn)
    local qb = new("TextButton", {
        BorderSizePixel = 0, AutoButtonColor = false, Text = txt,
        Position = UDim2.new(xScale, xScale == 0 and 4 or 2, 0, 1),
        Size = UDim2.new(0.5, -6, 0, 22),
    }, quick)
bind(qb, "BackgroundColor3", "Row")
bind(qb, "TextColor3", "Ink")
bindFont(qb, 12, true)
local setQuickRaised = makeRaiseController(qb, 1.04)
qb.MouseEnter:Connect(function()
    setQuickRaised(true, true)
    if Library._sfx then Library._sfx("hover") end
end)
qb.MouseLeave:Connect(function() setQuickRaised(false, true) end)
qb.MouseButton1Click:Connect(function()
    if Library._sfx then Library._sfx("select") end
    fn()
end)
end
quickBtn("Select All", 0, function()
    for _, e in ipairs(entries) do
        if e.btn.Visible then setChecked(e, true, true) end
    end
    paintMarks()
    fire()
end)
quickBtn("Clear All", 0.5, function()
    for _, e in ipairs(entries) do
        if e.btn.Visible then setChecked(e, false, true) end
    end
    paintMarks()
    fire()
end)
end

header.MouseButton1Click:Connect(function()
    if Library._sfx then Library._sfx("select") end
    isOpen = not isOpen
    search.Text = ""
    for _, e in ipairs(entries) do
        e.btn.Visible = true
    end
    updateSize()
end)
search:GetPropertyChangedSignal("Text"):Connect(function()
    local q = string.lower(search.Text or "")
    for _, e in ipairs(entries) do
        e.btn.Visible = q == "" or string.find(e.text, q, 1, true) ~= nil
    end
    updateSize()
end)

rebuild(options)

local api = {}
function api:Refresh(newOptions)
    options = type(newOptions) == "table" and newOptions or options
    rebuild(options)
end
function api:SetOptions(newOptions)
    options = type(newOptions) == "table" and newOptions or {}
    if multi then
        selSet = {}
        table.clear(selOrder)
    end
    rebuild(options)
    if multi then fire() end
end
if multi then
    function api:GetSelected()
        return selOrder
    end
    function api:SetSelected(list)
        if type(list) ~= "table" then list = {} end
        table.clear(selSet)
        table.clear(selOrder)
        local available = {}
        for _, e in ipairs(entries) do
            available[e.value] = true
        end
        for _, value in ipairs(list) do
            if value ~= nil and available[value] and not selSet[value] then
                selSet[value] = true
                table.insert(selOrder, value)
            end
        end
        paintMarks()
        fire()
    end
else
    function api:GetValue()
        return currentVal
    end
    function api:SetValue(v)
        currentVal = v
        paintMarks()
        fire()
    end
end
return api
end

function CategoryElements:CreateDropdown(DropdownText, IconName, Options, Default, Flag, Callback)
    if type(IconName) == "table" then
        Callback = Flag; Flag = Default; Default = Options; Options = IconName; IconName = nil
    end
    if type(Flag) == "function" then
        Callback = Flag; Flag = nil
    end
    if type(Default) == "function" then
        Callback = Default; Default = nil; Flag = nil
    end
    if Flag and SavedFlags[Flag] ~= nil then
        Default = SavedFlags[Flag]
    end
    return buildDropdown(false, DropdownText, IconName, Options, Default, Flag, Callback)
end

function CategoryElements:CreateMultiDropdown(DropdownText, IconName, Options, DefaultSelected, Flag, Callback)
    if type(IconName) == "table" then
        Callback = Flag; Flag = DefaultSelected; DefaultSelected = Options; Options = IconName; IconName = nil
    end
    if type(Flag) == "function" then
        Callback = Flag; Flag = nil
    end
    if type(DefaultSelected) == "function" then
        Callback = DefaultSelected; DefaultSelected = nil; Flag = nil
    end
    if Flag and type(SavedFlags[Flag]) == "table" then
        DefaultSelected = SavedFlags[Flag]
    end
    return buildDropdown(true, DropdownText, IconName, Options, DefaultSelected, Flag, Callback)
end

-- Optional layout helpers. Each one creates a real, themed component and returns
-- a small controller so scripts can update or remove it after creation.
function CategoryElements:CreateSection(Title, Subtitle)
    Title = tostring(Title or "SECTION")
    local hasSubtitle = Subtitle ~= nil and tostring(Subtitle) ~= ""
    local height = hasSubtitle and 50 or 32
    local holder = new("Frame", {
        Name = "ExtensionSection",
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, height),
        LayoutOrder = nextOrder(),
    }, categoryItemParent(height))

    local headingLabel = new("TextLabel", {
        Name = "SectionTitle",
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(0, 1),
        Size = UDim2.new(1, 0, 0, 20),
        Text = Title,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, holder)
    bindFont(headingLabel, 14, true)
    bind(headingLabel, "TextColor3", "Accent")

    local subtitleLabel
    if hasSubtitle then
        subtitleLabel = new("TextLabel", {
            Name = "SectionDescription",
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(0, 22),
            Size = UDim2.new(1, 0, 0, 17),
            Text = tostring(Subtitle),
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
        }, holder)
        bindFont(subtitleLabel, 10, false)
        bind(subtitleLabel, "TextColor3", "Ink")
        subtitleLabel.TextTransparency = 0.18
    end
    hline(holder, UDim2.new(0, 0, 1, -2), UDim2.new(1, 0, 0, 1))

    return {
        Instance = holder,
        SetTitle = function(_, value) headingLabel.Text = tostring(value or "") end,
        SetSubtitle = function(_, value)
            if not subtitleLabel then
                subtitleLabel = new("TextLabel", {
                    Name = "SectionDescription",
                    BackgroundTransparency = 1,
                    Position = UDim2.fromOffset(0, 22),
                    Size = UDim2.new(1, 0, 0, 17),
                    TextXAlignment = Enum.TextXAlignment.Left,
                    TextTruncate = Enum.TextTruncate.AtEnd,
                }, holder)
                bindFont(subtitleLabel, 10, false)
                bind(subtitleLabel, "TextColor3", "Ink")
                subtitleLabel.TextTransparency = 0.18
            end
            local valueText = tostring(value or "")
            subtitleLabel.Text = valueText
            subtitleLabel.Visible = valueText ~= ""
            holder.Size = UDim2.new(1, 0, 0, valueText ~= "" and 50 or 32)
        end,
        Destroy = function() if holder.Parent then holder:Destroy() end end,
    }
end

function CategoryElements:CreateDivider(LabelText)
    local holder = new("Frame", {
        Name = "ExtensionDivider",
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 20),
        LayoutOrder = nextOrder(),
    }, categoryItemParent(20))
    local label = new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.new(1, 0, 1, 0),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Visible = LabelText ~= nil and tostring(LabelText) ~= "",
    }, holder)
    bindFont(label, 9, true)
    bind(label, "TextColor3", "Line")
    local line = hline(holder, UDim2.new(0, 0, 0.5, 0), UDim2.new(1, 0, 0, 1))

    local function setLabel(value)
        local valueText = value ~= nil and tostring(value) or ""
        label.Text = string.upper(valueText)
        label.Visible = valueText ~= ""
        line.Position = label.Visible and UDim2.new(0, 0, 1, -1) or UDim2.new(0, 0, 0.5, 0)
        return true
    end
    setLabel(LabelText)
    return {
        Instance = holder,
        SetLabel = function(_, value) return setLabel(value) end,
        Destroy = function() if holder.Parent then holder:Destroy() end end,
    }
end

function CategoryElements:CreateSpacer(Height)
    local value = math.clamp(tonumber(Height) or 8, 2, 80)
    local spacer = new("Frame", {
        Name = "ExtensionSpacer",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, value),
        LayoutOrder = nextOrder(),
    }, categoryItemParent(value))
    return {
        Instance = spacer,
        SetHeight = function(_, newHeight)
            local n = tonumber(newHeight)
            if n then
                value = math.clamp(n, 2, 80)
                spacer.Size = UDim2.new(1, 0, 0, value)
            end
        end,
        Destroy = function() if spacer.Parent then spacer:Destroy() end end,
    }
end

function CategoryElements:CreateParagraph(Title, Text)
    local titleText = tostring(Title or "")
    local bodyText = tostring(Text or "")
    local holder = newRow("Frame", 58)
    holder.Name = "ExtensionParagraph"
    holder.ClipsDescendants = true

    local titleLabel
    if titleText ~= "" then
        titleLabel = new("TextLabel", {
            Name = "ParagraphTitle",
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(12, 7),
            Size = UDim2.new(1, -24, 0, 18),
            Text = titleText,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
        }, holder)
        bindFont(titleLabel, 12, true)
        bind(titleLabel, "TextColor3", "Accent")
    end

    local bodyLabel = new("TextLabel", {
        Name = "ParagraphText",
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(12, titleText ~= "" and 28 or 9),
        Size = UDim2.new(1, -24, 0, 24),
        Text = bodyText,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        TextWrapped = true,
    }, holder)
    bindFont(bodyLabel, 11, false)
    bind(bodyLabel, "TextColor3", "Ink")

    local function resizeParagraph()
        if not holder.Parent then return end
        local availableWidth
        if useTwoColumns then
            local parentWidth = holder.Parent and holder.Parent.AbsoluteSize.X or CategoryPage.AbsoluteSize.X
            availableWidth = math.max(96, (parentWidth > 0 and parentWidth or 240) - 28)
        else
            availableWidth = math.max(120, (CategoryPage.AbsoluteSize.X > 0 and CategoryPage.AbsoluteSize.X or 360) - 52)
        end
        local preset = FontPresets[FontFamily] or FontPresets.Gotham
        local size = math.max(9, math.floor(11 * FontScale + 0.5))
        local ok, bounds = pcall(function()
            return TextService:GetTextSize(bodyLabel.Text, size, preset.Regular, Vector2.new(availableWidth, 1000))
        end)
        local bodyHeight = ok and math.max(18, bounds.Y) or 36
        bodyLabel.Size = UDim2.new(1, -24, 0, bodyHeight)
        local top = titleText ~= "" and 28 or 9
        bodyLabel.Position = UDim2.fromOffset(12, top)
        holder.Size = UDim2.new(1, 0, 0, top + bodyHeight + 10)
    end
    resizeParagraph()
    local resizeConnection = connect(holder.Parent:GetPropertyChangedSignal("AbsoluteSize"), resizeParagraph)

    return {
        Instance = holder,
        SetText = function(_, value)
            bodyLabel.Text = tostring(value or "")
            resizeParagraph()
        end,
        SetTitle = function(_, value)
            titleText = tostring(value or "")
            if titleText == "" and titleLabel then
                titleLabel:Destroy()
                titleLabel = nil
            elseif titleText ~= "" and not titleLabel then
                titleLabel = new("TextLabel", {
                    Name = "ParagraphTitle",
                    BackgroundTransparency = 1,
                    Position = UDim2.fromOffset(12, 7),
                    Size = UDim2.new(1, -24, 0, 18),
                    Text = titleText,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    TextTruncate = Enum.TextTruncate.AtEnd,
                }, holder)
                bindFont(titleLabel, 12, true)
                bind(titleLabel, "TextColor3", "Accent")
            elseif titleLabel then
                titleLabel.Text = titleText
            end
            resizeParagraph()
        end,
        Destroy = function()
            if resizeConnection then resizeConnection:Disconnect(); resizeConnection = nil end
            if holder.Parent then holder:Destroy() end
        end,
    }
end

function CategoryElements:CreateBadge(LabelText, BadgeText, BadgeColor)
    local holder = new("Frame", {
        Name = "ExtensionBadgeRow",
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 28),
        LayoutOrder = nextOrder(),
    }, categoryItemParent(28))
    local label = new("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -112, 1, 0),
        Text = tostring(LabelText or "Status"),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, holder)
    bindFont(label, 12, false)
    bind(label, "TextColor3", "Ink")

    local pill = new("Frame", {
        Name = "BadgePill",
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.fromOffset(96, 21),
        BorderSizePixel = 0,
    }, holder)
    local color = typeof(BadgeColor) == "Color3" and BadgeColor or Theme.Accent
    pill.BackgroundColor3 = color:Lerp(Theme.Paper, 0.22)
    local stroke = new("UIStroke", { Thickness = 1, Transparency = 0.45 }, pill)
    stroke.Color = color
    local pillText = new("TextLabel", {
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        Text = tostring(BadgeText or "READY"),
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, pill)
    bindFont(pillText, 9, true)
    pillText.TextColor3 = color

    local function setBadgeColor(nextColor)
        if typeof(nextColor) ~= "Color3" then return false end
        color = nextColor
        pill.BackgroundColor3 = color:Lerp(Theme.Paper, 0.22)
        stroke.Color = color
        pillText.TextColor3 = color
        return true
    end
    return {
        Instance = holder,
        SetLabel = function(_, value) label.Text = tostring(value or "") end,
        SetText = function(_, value) pillText.Text = tostring(value or "") end,
        SetColor = function(_, value) return setBadgeColor(value) end,
        Destroy = function() if holder.Parent then holder:Destroy() end end,
    }
end

function CategoryElements:CreateProgressBar(Title, DefaultValue, MaxValue, BarColor)
    local maximum = math.max(tonumber(MaxValue) or 100, 0.0001)
    local value = math.clamp(tonumber(DefaultValue) or 0, 0, maximum)
    local holder = newRow("Frame", 43)
    holder.Name = "ExtensionProgressBar"
    local titleLabel = new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(10, 4),
        Size = UDim2.new(1, -20, 0, 16),
        Text = tostring(Title or "Progress"),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, holder)
    bindFont(titleLabel, 11, true)
    bind(titleLabel, "TextColor3", "Ink")

    local track = new("Frame", {
        Name = "Track",
        Position = UDim2.new(0, 10, 1, -13),
        Size = UDim2.new(1, -20, 0, 5),
        BorderSizePixel = 0,
    }, holder)
    bind(track, "BackgroundColor3", "Line")
    local fill = new("Frame", {
        Name = "Fill",
        Size = UDim2.new(value / maximum, 0, 1, 0),
        BorderSizePixel = 0,
        BackgroundColor3 = typeof(BarColor) == "Color3" and BarColor or Theme.Accent,
    }, track)
    local function update(nextValue)
        local numeric = tonumber(nextValue)
        if not numeric then return false end
        value = math.clamp(numeric, 0, maximum)
        tw(fill, 0.18, { Size = UDim2.new(value / maximum, 0, 1, 0) })
        return true
    end
    return {
        Instance = holder,
        SetValue = function(_, nextValue) return update(nextValue) end,
        GetValue = function() return value end,
        SetMax = function(_, nextMax)
            local numeric = tonumber(nextMax)
            if not numeric or numeric <= 0 then return false end
            maximum = numeric
            update(value)
            return true
        end,
        SetTitle = function(_, nextTitle) titleLabel.Text = tostring(nextTitle or "") end,
        SetColor = function(_, nextColor)
            if typeof(nextColor) ~= "Color3" then return false end
            fill.BackgroundColor3 = nextColor
            return true
        end,
        Destroy = function() if holder.Parent then holder:Destroy() end end,
    }
end

function CategoryElements:CreateActionCard(Title, Description, ButtonText, Callback)
    local holder = newRow("Frame", 62)
    holder.Name = "ExtensionActionCard"
    local titleLabel = new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(11, 7),
        Size = UDim2.new(1, -118, 0, 17),
        Text = tostring(Title or "Action"),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, holder)
    bindFont(titleLabel, 11, true)
    bind(titleLabel, "TextColor3", "Ink")
    local descriptionLabel = new("TextLabel", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(11, 27),
        Size = UDim2.new(1, -118, 0, 25),
        Text = tostring(Description or ""),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        TextWrapped = true,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, holder)
    bindFont(descriptionLabel, 9, false)
    bind(descriptionLabel, "TextColor3", "Ink")
    descriptionLabel.TextTransparency = 0.18

    local action = new("TextButton", {
        Name = "ActionButton",
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -9, 0.5, 0),
        Size = UDim2.fromOffset(92, 27),
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Text = tostring(ButtonText or "RUN"),
    }, holder)
    bind(action, "BackgroundColor3", "Accent")
    bind(action, "TextColor3", "Cream")
    bindFont(action, 9, true)
    local enabled = true
    local callback = Callback
    connect(action.MouseEnter, function()
        if enabled then tw(action, 0.12, { BackgroundColor3 = Theme.Team }) end
    end)
    connect(action.MouseLeave, function()
        tw(action, 0.12, { BackgroundColor3 = Theme.Accent })
    end)
    connect(action.MouseButton1Click, function()
        if not enabled then return end
        if Library._sfx then Library._sfx("select") end
        if type(callback) == "function" then
            task.spawn(function()
                local ok, err = pcall(callback)
                if not ok then Notify("Extension action failed: " .. tostring(err), 4) end
            end)
        end
    end)
    return {
        Instance = holder,
        SetTitle = function(_, value) titleLabel.Text = tostring(value or "") end,
        SetDescription = function(_, value) descriptionLabel.Text = tostring(value or "") end,
        SetButtonText = function(_, value) action.Text = tostring(value or "") end,
        SetCallback = function(_, value)
            if type(value) ~= "function" and value ~= nil then return false end
            callback = value
            return true
        end,
        SetEnabled = function(_, state)
            enabled = state == true
            action.Active = enabled
            action.BackgroundTransparency = enabled and 0 or 0.55
            action.TextTransparency = enabled and 0 or 0.35
            return enabled
        end,
        Destroy = function() if holder.Parent then holder:Destroy() end end,
    }
end

function CategoryElements:CreateCustomFrame(Name, Height, Options)
    Options = type(Options) == "table" and Options or {}
    local frame = new("Frame", {
        Name = tostring(Name or "CustomExtensionFrame"),
        Size = UDim2.new(1, 0, 0, math.clamp(tonumber(Height) or 72, 24, 500)),
        BorderSizePixel = 0,
        BackgroundTransparency = Options.BackgroundTransparency ~= nil and math.clamp(tonumber(Options.BackgroundTransparency) or 0, 0, 1) or GTrans,
        LayoutOrder = nextOrder(),
        ClipsDescendants = Options.ClipsDescendants == true,
    }, categoryItemParent(math.clamp(tonumber(Height) or 72, 24, 500)))
    if typeof(Options.BackgroundColor3) == "Color3" then
        frame.BackgroundColor3 = Options.BackgroundColor3
    else
        bind(frame, "BackgroundColor3", type(Options.ThemeColor) == "string" and Theme[Options.ThemeColor] and Options.ThemeColor or "Row")
    end
    if Options.Glass == true or (Options.Glass ~= false and Options.BackgroundTransparency == nil) then
        bindGlass(frame)
    end
    if Options.Gradient == true then
        addGradient(frame, function(t) return makeGradientSequence(t.Row, t.Row:Lerp(t.Accent, 0.18)) end)
    end
    return frame
end

-- Fourth return value is a stable parent for content that must remain in
-- column 1 (or the page itself when the one-column layout is active).
return CategoryElements, CategoryPage, btn, ColumnFrames[1] or CategoryPage
end

WindowElements.Flags = Flags
WindowElements.Layout = { ify = layout.ify, ActiveColumns = useTwoColumns and 2 or 1 }
function WindowElements:GetLayoutMode()
    return layout.ify
end
function WindowElements:GetActiveColumnCount()
    return useTwoColumns and 2 or 1
end
WindowElements.ApplyTeamColor = function(instance, property)
    bind(instance, property or "BackgroundColor3", "Team")
end
WindowElements.UpdateTeamColor = function(color)
    runThemeTransition(function()
        Theme.Team = color
        refreshTheme()
    end)
end
WindowElements.GetTeamColor = function()
    return Theme.Team
end
WindowElements.UpdateBackgroundImage = UpdateBackgroundImage
WindowElements.UpdateBackgroundImageTransparency = UpdateBackgroundImageTransparency
WindowElements.UpdateBackgroundImageEnabled = UpdateBackgroundImageEnabled
WindowElements.GetTheme = function()
    local copy = {}
    for k, v in pairs(Theme) do copy[k] = v end
    return copy
end

function WindowElements:SetThemeColor(token, color)
    local allowed = { Paper = true, Row = true, Input = true, Accent = true, Ink = true, Cream = true, Line = true, Team = true }
    if not allowed[token] or typeof(color) ~= "Color3" then return false end
    runThemeTransition(function()
        Theme[token] = color
        refreshTheme()
        persistTheme()
        save()
    end)
    return true
end

function WindowElements:GetThemeColor(token)
    return Theme[token]
end

function WindowElements:CreateExtensionCategory(name, iconName, hidden)
    return self:CreateCategory(name, iconName, hidden)
end

function WindowElements:RunExtension(name, ...)
    local callback = Library:GetExtension(name)
    if type(callback) ~= "function" then
        return false, "Extension is not registered: " .. tostring(name)
    end
    local args = table.pack(...)
    local ok, result = pcall(function()
        return callback(self, Library, table.unpack(args, 1, args.n))
    end)
    if not ok then
        Notify("Extension '" .. tostring(name) .. "' failed: " .. tostring(result), 5)
        return false, result
    end
    return true, result
end

function WindowElements:Notify(text, duration, opts)
    Notify(text, duration, opts)
end
function WindowElements:IsAuthenticated()
    return KeyAuthenticated == true
end
function WindowElements:SetAuthenticated(state)
    KeyAuthenticated = state == true
    if KeyAuthenticated then
        KeyFailClicks = 0
        Notify({ Title = "AUTHENTICATED", Description = "Categories unlocked.", Duration = 3 })
    end
end
function WindowElements:EnableKeySystem(expectedKey, note)
    KeySystemEnabled = true
    KeyAuthenticated = false
    KeyFailClicks = 0
    authOutroStarted = false
    if expectedKey then ExpectedKey = tostring(expectedKey) end
    if note then KeyNote = tostring(note) end
end
function WindowElements:DisableKeySystem()
    KeySystemEnabled = false
    KeyAuthenticated = true
    KeyFailClicks = 0
end
function WindowElements:GetFlag(name)
    local f = Flags[name]
    return f and f.Value or nil
end
function WindowElements:SetFlag(name, value)
    if Flags[name] then
        Flags[name].Value = value
        save()
    end
end
function WindowElements:SaveConfiguration() save() end
function WindowElements:Show() SetWindowOpen(true) end
function WindowElements:Hide() SetWindowOpen(false) end
function WindowElements:ToggleVisibility() SetWindowOpen(not main.Visible) end
function WindowElements:Destroy()
    for _, c in ipairs(connections) do
        pcall(function() c:Disconnect() end)
    end
    if gui and gui.Parent then gui:Destroy() end
end

connect(UserInputService.InputBegan, function(input, processed)
    if listeningKey or processed or not toggleKey then
        return
    end
    if input.KeyCode == toggleKey then
        SetWindowOpen(not main.Visible)
    end
end)

function WindowElements:SetToggleKey(key)
    if typeof(key) == "EnumItem" and key.EnumType == Enum.KeyCode then
        toggleKey = key
        persistTheme()
        save()
    end
end
function WindowElements:SetMobileStyle(name)
    SetMobileStyle(name)
    save()
end
function WindowElements:SetDragDelay(milliseconds)
    if setDragDelay(milliseconds) then
        save()
        return true
    end
    return false
end
function WindowElements:GetDragDelay()
    return DragDelayMs
end
function WindowElements:SetGradientEffects(enabled)
    setGradientEffects(enabled)
    save()
    return GradientEffectsEnabled
end
function WindowElements:GetGradientEffects()
    return GradientEffectsEnabled
end
function WindowElements:SetGradientDirection(direction)
    if setGradientDirection(direction) then
        save()
        return true
    end
    return false
end
function WindowElements:GetGradientDirection()
    return GradientDirection
end

if Config.ShowSettingsTab ~= false then
    do
        -- Create Settings synchronously so the gear button is ready as soon as
        -- CreateWindow returns; task.defer left a window where clicks did nothing.
        local SettingsTab, SettingsPage = WindowElements:CreateCategory("Settings", "lucide-settings", true)
        local PreviousPage = nil

        local function ShowSettingsPanel()
            if SettingsState.open then return end
            PreviousPage = nil
            for _, page in ipairs(ContentContainer:GetChildren()) do
                if page:IsA("ScrollingFrame") and page ~= SettingsPage and page.Visible then
                    PreviousPage = page
                    cancelPageAnimation(page)
                    page.Visible = false
                end
            end
            SettingsPage.Visible = true
            AnimatePageIn(SettingsPage)
            SettingsState.open = true
        end
        local function HideSettingsPanel()
            if not SettingsState.open then return end
            cancelPageAnimation(SettingsPage)
            SettingsPage.Visible = false
            if PreviousPage and PreviousPage.Parent then
                PreviousPage.Visible = true
                AnimatePageIn(PreviousPage)
            end
            SettingsState.open = false
        end
        ToggleSettingsVisibility = function()
            if SettingsState.open then HideSettingsPanel() else ShowSettingsPanel() end
        end
        OpenSettingsFn = ShowSettingsPanel
        CloseSettingsFn = HideSettingsPanel

        local TransPercent = math.floor(GTrans * 100 + 0.5)
        local volumeSaveToken = 0
        local dragDelaySaveToken = 0
        local BuildSettingsUI

        local function applyPreset(name)
            if not Presets[name] then return end
            runThemeTransition(function()
                loadPreset(Presets[name])
                CurrentPreset = name
                refreshTheme()
                persistTheme()
                BuildSettingsUI()
                save()
            end)
        end

        BuildSettingsUI = function()
            local T = Translations[Language] or Translations.en
            SettingsTab:ClearItems()

            SettingsTab:CreateLabel(T.PresetHeader, "lucide-palette")
            SettingsTab:CreateDropdown(T.PresetLabel, "lucide-palette", PresetOrder, CurrentPreset, nil, function(selected)
                applyPreset(selected)
            end)

            SettingsTab:CreateDropdown(T.PageAnimationLabel, "lucide-panels-top-left", PageAnimationOrder, PageAnimation, nil, function(selected)
                if not containsOption(PageAnimationOrder, selected) then return end
                PageAnimation = selected
                persistTheme()
                save()
            end)

            SettingsTab:CreateDropdown(T.OpenCloseAnimationLabel, "lucide-sparkles", OpenCloseAnimationOrder, OpenCloseAnimation, nil, function(selected)
                if not containsOption(OpenCloseAnimationOrder, selected) then return end
                OpenCloseAnimation = selected
                persistTheme()
                save()
            end)

            SettingsTab:CreateToggle("Gradient Effects", "lucide-palette", GradientEffectsEnabled, function(enabled)
                setGradientEffects(enabled)
                save()
            end)

            SettingsTab:CreateDropdown("Gradient Direction", "lucide-palette", GradientDirectionOrder, GradientDirection, nil, function(selected)
                if setGradientDirection(selected) then save() end
            end)

            SettingsTab:CreateSlider("Drag Hold Delay (ms)", "lucide-move", 0, 600, DragDelayMs, function(value)
                if setDragDelay(value) then
                    dragDelaySaveToken += 1
                    local token = dragDelaySaveToken
                    task.delay(0.4, function()
                        if token == dragDelaySaveToken then save() end
                    end)
                end
            end)

            local fontFamilyOptions = {}
            for fontName in pairs(FontPresets) do
                table.insert(fontFamilyOptions, fontName)
            end
            table.sort(fontFamilyOptions)
            SettingsTab:CreateDropdown("Font Family", "lucide-type", fontFamilyOptions, FontFamily, nil, function(selected)
                if setFontFamily(selected) then save() end
            end)

            SettingsTab:CreateSlider("Font Scale (%)", "lucide-text-cursor-input", 75, 135, math.floor(FontScale * 100 + 0.5), function(v)
                if setFontScale(v) then save() end
            end)

            SettingsTab:CreateToggle("Window Border", "lucide-square", BorderEnabled, function(enabled)
                BorderEnabled = enabled == true
                mainStroke.Enabled = BorderEnabled
                persistTheme()
                save()
            end)

            SettingsTab:CreateToggle("Background Image", "lucide-image", BgImageEnabled, function(enabled)
                UpdateBackgroundImageEnabled(enabled == true)
                persistTheme()
                save()
            end)

            local backgroundAssetBox = SettingsTab:CreateTextbox("Background Image Asset ID", "lucide-image", "rbxassetid://...", nil, function(value)
                UpdateBackgroundImage(value)
                persistTheme()
                save()
            end)
            if backgroundAssetBox and backgroundAssetBox.Set then
                backgroundAssetBox.Set(BgImage)
            end

            SettingsTab:CreateSlider("Background Image Transparency (%)", "lucide-image", 0, 100, math.floor(BgImageTransparency * 100 + 0.5), function(v)
                UpdateBackgroundImageTransparency(v / 100)
                persistTheme()
                save()
            end)

            SettingsTab:CreateSlider(T.OverallScaleLabel, "lucide-scaling", 70, 130, OverallScalePercent, "OverallScalePercent", function(v)
                SetOverallScale(v)
            end)

            SettingsTab:CreateSlider(T.TransparencyLabel, "lucide-glasses", 0, 90, TransPercent, function(v)
                TransPercent = v
                setGlass(v / 100)
                persistTheme()
            end)

            SettingsTab:CreateSlider(T.SoundVolumeLabel, "lucide-volume-2", 0, 100, math.floor(Library.SoundVolume * 100 + 0.5), function(v)
                Library:SetSoundVolume(v / 100)
                persistTheme()

                volumeSaveToken += 1
                local token = volumeSaveToken
                task.delay(0.5, function()
                    if token == volumeSaveToken then
                        save()
                    end
                end)
            end)

            if isMobile then
                SettingsTab:CreateDropdown(T.MobileStyleLabel, "lucide-smartphone", MobileStyleOrder, MobileStyle, nil, function(selected)
                    SetMobileStyle(selected)
                    save()
                end)

                SettingsTab:CreateSlider(T.ToggleButtonScaleLabel, "lucide-move", 50, 180, ToggleButtonScalePercent, "ToggleButtonScalePercent", function(v)
                    SetToggleButtonScale(v)
                end)
            else
                local keyBtn
                local function keyText()
                    return T.ToggleKeyLabel .. " : " .. (toggleKey and toggleKey.Name or "None")
                end
                keyBtn = SettingsTab:CreateButton(keyText(), "lucide-keyboard", function()
                    if listeningKey then return end
                    listeningKey = true
                    keyBtn.SetText(T.PressKey)
                    local conn
                    conn = connect(UserInputService.InputBegan, function(input)
                        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
                        if input.KeyCode == Enum.KeyCode.Unknown then return end
                        conn:Disconnect()
                        if input.KeyCode ~= Enum.KeyCode.Escape then
                            toggleKey = input.KeyCode
                            persistTheme()
                            save()
                        end
                        keyBtn.SetText(keyText())
                        task.defer(function()
                            listeningKey = false
                        end)
                    end)
                end)
            end
        end

        BuildSettingsUI()
    end
end

-- Internal Hello tab. It is created synchronously and permanently pinned
-- to column 1, even while user-created categories use the two-column allocator.
do
    local HelloTab, HelloPage, _, HelloColumnOne = WindowElements:CreateCategory("Hello", "lucide-heart", false)
    local HelloContentParent = HelloColumnOne or HelloPage

    local playerName = (LocalPlayer and (LocalPlayer.DisplayName ~= "" and LocalPlayer.DisplayName or LocalPlayer.Name)) or "User"
    local username = (LocalPlayer and LocalPlayer.Name) or ""
    local profileHeader = new("Frame", {
        Name = "ProfileWelcome",
        Size = UDim2.new(1, 0, 0, 66),
        LayoutOrder = 1,
        BackgroundTransparency = 1,
        ZIndex = 70,
    }, HelloContentParent)

    local avatar = new("ImageLabel", {
        Name = "UserAvatar",
        Position = UDim2.fromOffset(2, 5),
        Size = UDim2.fromOffset(54, 54),
        BackgroundColor3 = Theme.Row,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        Image = "",
        ScaleType = Enum.ScaleType.Crop,
        ZIndex = 82,
    }, profileHeader)
    new("UICorner", { CornerRadius = UDim.new(1, 0) }, avatar)
    local avatarStroke = new("UIStroke", { Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, avatar)
    bind(avatarStroke, "Color", "Accent")

    local welcomeText = new("TextLabel", {
        Name = "WelcomeText",
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(68, 10),
        Size = UDim2.new(1, -72, 0, 26),
        Text = "Welcome, " .. tostring(playerName),
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ZIndex = 81,
    }, profileHeader)
    bindFont(welcomeText, 16, true)
    bind(welcomeText, "TextColor3", "Ink")

    local usernameText = new("TextLabel", {
        Name = "UsernameText",
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(69, 36),
        Size = UDim2.new(1, -73, 0, 18),
        Text = username ~= "" and ("@" .. username) or "",
        TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd,
        ZIndex = 81,
    }, profileHeader)
    bindFont(usernameText, 11, false)
    bind(usernameText, "TextColor3", "Accent")

    if LocalPlayer then
        task.spawn(function()
            local okThumb, imageUrl = pcall(function()
                local content, _ = Players:GetUserThumbnailAsync(
                    LocalPlayer.UserId,
                    Enum.ThumbnailType.HeadShot,
                    Enum.ThumbnailSize.Size150x150
                )
                return content
            end)
            if okThumb and type(imageUrl) == "string" and avatar.Parent then
                avatar.Image = imageUrl
            end
        end)
    end

    -- Hello content is authored directly inside HelloContentParent. This is
    -- intentional: the changelog must be visible in the actual Hello page and
    -- must never be sent through the normal two-column allocator.
    local helloIntro = new("TextLabel", {
        Name = "HelloIntro",
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Position = UDim2.new(),
        LayoutOrder = 2,
        Text = "Welcome to the library. The notes below summarize the changes made since the original UILibrary.lua.",
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        TextWrapped = true,
    }, HelloContentParent)
    bindFont(helloIntro, 12, false)
    bind(helloIntro, "TextColor3", "Ink")

    -- Visible changelog panel, parented directly to the internal Hello page's
    -- first column (or the page itself in one-column mode).
    local changelogPanel = new("Frame", {
        Name = "HelloChangelogPanel",
        BackgroundTransparency = 0.12,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder = 3,
        ClipsDescendants = false,
    }, HelloContentParent)
    bind(changelogPanel, "BackgroundColor3", "Row")
    bindGlass(changelogPanel)
    new("UICorner", { CornerRadius = UDim.new(0, 7) }, changelogPanel)
    local changelogStroke = new("UIStroke", {
        Thickness = 1,
        Transparency = 0.58,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, changelogPanel)
    bind(changelogStroke, "Color", "Line")
    new("UIPadding", {
        PaddingLeft = UDim.new(0, 12),
        PaddingRight = UDim.new(0, 12),
        PaddingTop = UDim.new(0, 11),
        PaddingBottom = UDim.new(0, 11),
    }, changelogPanel)
    new("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 7),
    }, changelogPanel)

    local changelogHeading = new("TextLabel", {
        Name = "ChangelogHeading",
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 19),
        LayoutOrder = 1,
        Text = "CHANGELOG",
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
    }, changelogPanel)
    bindFont(changelogHeading, 14, true)
    bind(changelogHeading, "TextColor3", "Accent")

    local changelogSubheading = new("TextLabel", {
        Name = "ChangelogSubheading",
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 16),
        LayoutOrder = 2,
        Text = "ORIGINAL UILIBRARY.LUA  →  CURRENT BUILD",
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, changelogPanel)
    bindFont(changelogSubheading, 9, true)
    bind(changelogSubheading, "TextColor3", "Ink")
    changelogSubheading.TextTransparency = 0.22

    local function addHelloChangelogEntry(entryOrder, title, description)
        local entry = new("Frame", {
            Name = "ChangelogEntry",
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            LayoutOrder = entryOrder,
        }, changelogPanel)
        new("UIListLayout", {
            FillDirection = Enum.FillDirection.Vertical,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 2),
        }, entry)

        local entryTitle = new("TextLabel", {
            Name = "EntryTitle",
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 16),
            LayoutOrder = 1,
            Text = title,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Center,
            TextTruncate = Enum.TextTruncate.AtEnd,
        }, entry)
        bindFont(entryTitle, 11, true)
        bind(entryTitle, "TextColor3", "Accent")

        local entryBody = new("TextLabel", {
            Name = "EntryDescription",
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            LayoutOrder = 2,
            Text = description,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
            TextWrapped = true,
        }, entry)
        bindFont(entryBody, 10, false)
        bind(entryBody, "TextColor3", "Ink")
        entryBody.TextTransparency = 0.08
    end

    addHelloChangelogEntry(3, "INTERACTION & NOTIFICATIONS",
        "Added delayed hold-to-drag behavior and independently draggable notifications. The existing notification rail styling and slide/typewriter effects were retained. Drag timing and optional gradient preferences are configurable and saved.")
    addHelloChangelogEntry(4, "THEME & GRADIENTS",
        "Added optional theme gradients with direction choices, plus live theme-color modification for developers. Gradients can remain disabled to preserve the original flat appearance.")
    addHelloChangelogEntry(5, "LAYOUT",
        "Added layout.ify = \"1\" for the original single-column layout and layout.ify = \"2\" for balanced double columns. Responsive mode can fall back to one column on narrow screens. Internal Settings and Hello content are pinned to column 1.")
    addHelloChangelogEntry(6, "DEVELOPER EXTENSIONS",
        "Added extension registration and lookup/execution helpers, plus reusable Section, Divider, Spacer, Paragraph, Badge, ProgressBar, ActionCard, and CustomFrame components with update/destroy methods.")
    addHelloChangelogEntry(7, "SETTINGS & INTERNAL PAGES",
        "Settings initialization and rebuilding now preserve their column containers. The Hello page is created synchronously, and its profile header, changelog, and credits are parented directly to its first-column content area.")

    -- Credits remain below the changelog and are also pinned to column 1.
    local credits = new("TextLabel", {
        Name = "HelloCredits",
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 48),
        AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder = 4,
        Text = "Visual design & most of the core script: Nier\nAdditional UI work: jawolskimanowski\nFeedback: jawolskimanowski@gmail.com",
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        TextWrapped = true,
    }, HelloContentParent)
    bindFont(credits, 10, false)
    bind(credits, "TextColor3", "Ink")
    credits.TextTransparency = 0.2
end

-- Internal AUTH tab when key system is requested
if KeySystemEnabled then
    task.defer(function()
        local AuthTab, AuthPage, AuthBtn = WindowElements:CreateCategory("AUTH", "lucide-key", false)
        AuthTab:CreateLabel("KEY SYSTEM", "lucide-shield")
        AuthTab:CreateLabel(KeyNote)
        AuthTab:CreateLabel("Type the key below, then press VERIFY KEY.")

        local keyBox = AuthTab:CreateTextbox("Access Key", nil, "Enter key...", "AuthKeyInput", nil)
        local lastTyped = ""

        AuthTab:CreateButton("VERIFY KEY", function()
            if authOutroStarted then return end
            local typed = ""
            if keyBox and keyBox.Get then
                typed = tostring(keyBox.Get() or "")
            end
            if typed == "" then
                for _, d in ipairs(AuthPage:GetDescendants()) do
                    if d:IsA("TextBox") then
                        typed = d.Text or ""
                        break
                    end
                end
            end
            if Flags.AuthKeyInput and Flags.AuthKeyInput.Value then
                if typed == "" then typed = tostring(Flags.AuthKeyInput.Value) end
            end
            typed = tostring(typed or ""):gsub("^%s+", ""):gsub("%s+$", "")
            lastTyped = typed

            if typed ~= "" and string.upper(typed) == string.upper(ExpectedKey) then
                KeyAuthenticated = true
                KeyFailClicks = 0
                Notify({ Title = "AUTHENTICATED", Description = "Welcome. Categories unlocked.", Duration = 3.5 })
                -- open first non-AUTH category if any
                for _, b in ipairs(Sidebar:GetChildren()) do
                    if b:IsA("TextButton") and b.Name ~= "AUTH" and b.Visible then
                        -- fire select by simulating attribute + visibility via click if possible
                        pcall(function()
                            for _, page in ipairs(ContentContainer:GetChildren()) do
                                if page:IsA("ScrollingFrame") then
                                    page.Visible = false
                                end
                            end
                            for _, bb in ipairs(Sidebar:GetChildren()) do
                                if bb:IsA("TextButton") then
                                    bb:SetAttribute("CategorySelected", false)
                                end
                            end
                            b:SetAttribute("CategorySelected", true)
                            local targetPage = ContentContainer:FindFirstChild(b.Name .. "Page")
                            if targetPage then
                                targetPage.Visible = true
                                if AnimatePageIn then AnimatePageIn(targetPage) end
                            end
                        end)
                        break
                    end
                end
            else
                KeyFailClicks = KeyFailClicks + 1
                Notify({ Title = "INVALID KEY", Description = "Complete authentication first. (" .. tostring(KeyFailClicks) .. "/3)", Duration = 3 })
                if KeyFailClicks >= 3 then
                    Notify({ Title = "AUTHENTICATION FAILED", Description = "The interface is closing.", Duration = 2.5 })
                    DestroyAfterAuthOutro()
                end
            end
        end)

        -- Force AUTH visible first when locked
        task.wait()
        for _, b in ipairs(Sidebar:GetChildren()) do
            if b:IsA("TextButton") then
                b:SetAttribute("CategorySelected", b.Name == "AUTH")
            end
        end
        for _, page in ipairs(ContentContainer:GetChildren()) do
            if page:IsA("ScrollingFrame") then
                page.Visible = (page.Name == "AUTHPage")
            end
        end
        if AuthBtn then
            AuthBtn:SetAttribute("CategorySelected", true)
        end
    end)
end

-- Intro / tutorial overlay: blur outside, focus UI
if Config.ShowIntro ~= false then
    task.defer(function()
        local blur = Instance.new("BlurEffect")
        blur.Name = "IntroBlur"
        blur.Size = 0
        blur.Parent = game:GetService("Lighting")
        tw(blur, 0.45, { Size = 18 })

        local overlay = new("Frame", {
            Name = "IntroOverlay",
            Size = UDim2.fromScale(1, 1),
            BackgroundColor3 = Color3.new(0, 0, 0),
            BackgroundTransparency = 0.55,
            ZIndex = 100,
            BorderSizePixel = 0,
        }, gui)

        local card = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(340, 210),
            BorderSizePixel = 0,
            ZIndex = 101,
            BackgroundTransparency = 0.05,
        }, overlay)
        bind(card, "BackgroundColor3", "Paper")
        local st = new("UIStroke", { Thickness = 1 }, card)
        bind(st, "Color", "Line")

        local title = new("TextLabel", {
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(18, 14),
            Size = UDim2.new(1, -36, 0, 28),
            Text = "WELCOME",
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = 102,
        }, card)
        bindFont(title, 16, true)
        bind(title, "TextColor3", "Ink")

        local body = new("TextLabel", {
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(18, 48),
            Size = UDim2.new(1, -36, 0, 110),
            Text = "• Drag the top bar to move\n• Use the sidebar to switch categories\n• Gear icon opens Settings (themes, scale, animations)\n• Toggle key hides / shows the window\n• Complete AUTH first if a key system is enabled",
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
            TextWrapped = true,
            ZIndex = 102,
        }, card)
        bindFont(body, 13, false)
        bind(body, "TextColor3", "Ink")

        local dismiss = new("TextButton", {
            AnchorPoint = Vector2.new(0.5, 1),
            Position = UDim2.new(0.5, 0, 1, -16),
            Size = UDim2.fromOffset(120, 28),
            Text = "GOT IT",
            BorderSizePixel = 0,
            AutoButtonColor = false,
            ZIndex = 103,
        }, card)
        bind(dismiss, "BackgroundColor3", "Accent")
        bind(dismiss, "TextColor3", "Cream")
        bindFont(dismiss, 13, true)
        local setDismissRaised = makeRaiseController(dismiss, 1.04)
        dismiss.MouseEnter:Connect(function()
            setDismissRaised(true, true)
            if Library._sfx then Library._sfx("hover") end
        end)
        dismiss.MouseLeave:Connect(function() setDismissRaised(false, true) end)

        local function closeIntro()
            tw(overlay, 0.25, { BackgroundTransparency = 1 })
            tw(blur, 0.35, { Size = 0 })
            task.delay(0.4, function()
                if overlay.Parent then overlay:Destroy() end
                if blur.Parent then blur:Destroy() end
            end)
        end
        dismiss.MouseButton1Click:Connect(function()
            if Library._sfx then Library._sfx("select") end
            closeIntro()
        end)
        -- auto-dismiss after long delay
        task.delay(12, function()
            if overlay.Parent then closeIntro() end
        end)
    end)
end

-- Extensions are opt-in. Config.Extensions may contain registered names,
-- direct callbacks, or records: { Name = "Name", Enabled = true, Run = function(...) end }.
if type(Config.Extensions) == "table" then
    for key, entry in pairs(Config.Extensions) do
        local extensionName = nil
        local extensionCallback = nil
        local enabled = true

        if type(entry) == "string" then
            extensionName = entry
        elseif type(entry) == "function" then
            extensionName = "InlineExtension_" .. tostring(key)
            extensionCallback = entry
        elseif type(entry) == "table" then
            extensionName = tostring(entry.Name or key)
            enabled = entry.Enabled ~= false
            extensionCallback = entry.Run or entry.Callback
        elseif type(key) == "string" and entry == true then
            extensionName = key
        end

        if enabled and extensionName then
            extensionCallback = type(extensionCallback) == "function" and extensionCallback or Library:GetExtension(extensionName)
            if type(extensionCallback) == "function" then
                local ok, err = pcall(extensionCallback, WindowElements, Library)
                if not ok then
                    Notify("Extension '" .. extensionName .. "' failed: " .. tostring(err), 5)
                end
            end
        end
    end
end

if Config.StartOpen ~= false then
    task.defer(function()
        SetWindowOpen(true)
        if toggleKey and not isMobile and Config.ToggleHint ~= false then
            Notify("Press [ " .. toggleKey.Name .. " ] to hide GUI", 4)
        end
    end)
end

return WindowElements
end

local SOUND_URL = "https://github.com/PMLOLHUB/assets-library-/raw/refs/heads/main/NierSound.lua"

do
    local okSource, source = pcall(function()
        return game:HttpGet(SOUND_URL)
    end)
    if okSource and type(source) == "string" and source ~= "" then
        local compiler = getExecutorFunction("loadstring")
        if not compiler then
            local ok, value = pcall(function() return loadstring end)
            if ok and type(value) == "function" then compiler = value end
        end
        if compiler then
            local okChunk, chunk = pcall(compiler, source)
            if okChunk and type(chunk) == "function" then
                local okModule, module = pcall(chunk)
                if okModule and type(module) == "function" then
                    pcall(module, Library)
                end
            end
        end
    end
end

-- Extra custom MP3s. These supplement the original Nier effects:
-- * robotic warning voice: notification events only
-- * button click: hover/select/toggle events only
-- Slider, open, and close sounds remain exclusively Nier sounds.
do
    local SoundService = game:GetService("SoundService")
    local Debris = game:GetService("Debris")
    local NOTIFY_MP3_URL = "https://github.com/jawolskimanowski-ui/CoffeeIFY-renewed/raw/refs/heads/main/Robotic-female-sound-effect-warning.mp3"
    local CLICK_MP3_URL = "https://github.com/jawolskimanowski-ui/CoffeeIFY-renewed/raw/refs/heads/main/Button%20Click%202%20-%20Kaino.mp3"
    local ASSET_FOLDER = "UILibrary"
    local NOTIFY_PATH = ASSET_FOLDER .. "/NotifySound.mp3"
    local CLICK_PATH = ASSET_FOLDER .. "/ClickSound.mp3"
    local NOTIFY_FALLBACK_PATH = "UILibrary_NotifySound.mp3"
    local CLICK_FALLBACK_PATH = "UILibrary_ClickSound.mp3"
    local notifyId, clickId = nil, nil
    local notifyPath, clickPath = NOTIFY_PATH, CLICK_PATH
    local downloadStarted = false
    local retryPending = {}

    local function getAssetFunction()
        return getExecutorFunction("getcustomasset") or getExecutorFunction("getsynasset")
    end

    local function resolve(path)
        local asset = getAssetFunction()
        if not asset then return nil end
        local ok, id = pcall(asset, path)
        if ok and type(id) == "string" and id ~= "" then
            return id
        end
        return nil
    end

    local function download(path, fallbackPath, url)
        local write = getExecutorFunction("writefile")
        if not write then return nil end

        local makeFolder = getExecutorFunction("makefolder")
        local isFolder = getExecutorFunction("isfolder")
        local folderReady = false
        if makeFolder then
            if isFolder then
                local ok, exists = pcall(isFolder, ASSET_FOLDER)
                folderReady = ok and exists == true
            end
            if not folderReady then
                local ok = pcall(makeFolder, ASSET_FOLDER)
                folderReady = ok
            end
        end
        if not folderReady then
            path = fallbackPath
        end

        local isFile = getExecutorFunction("isfile")
        if isFile then
            local ok, exists = pcall(isFile, path)
            if ok and exists then return path end
        end

        local ok, data = pcall(function()
            return game:HttpGet(url)
        end)
        if not ok or type(data) ~= "string" or data == "" then
            return nil
        end
        local wrote = pcall(write, path, data)
        if wrote then return path end

        if path ~= fallbackPath then
            wrote = pcall(write, fallbackPath, data)
            if wrote then return fallbackPath end
        end
        return nil
    end

    local function refreshIds()
        notifyId = resolve(notifyPath) or notifyId
        clickId = resolve(clickPath) or clickId
    end

    local function ensureDownloads()
        if downloadStarted then return end
        downloadStarted = true
        task.spawn(function()
            notifyPath = download(NOTIFY_PATH, NOTIFY_FALLBACK_PATH, NOTIFY_MP3_URL) or notifyPath
            clickPath = download(CLICK_PATH, CLICK_FALLBACK_PATH, CLICK_MP3_URL) or clickPath
            refreshIds()
        end)
    end

    local function playId(id, volume)
        if Library.SoundEnabled == false or not id then return end
        local sound = Instance.new("Sound")
        sound.Name = "UILibrary_CustomSfx"
        sound.SoundId = id
        sound.Volume = math.clamp((tonumber(Library.SoundVolume) or 1) * (volume or 1), 0, 1)
        sound.Parent = SoundService
        sound.Ended:Connect(function()
            if sound.Parent then sound:Destroy() end
        end)
        Debris:AddItem(sound, 10)
        local ok = pcall(function() sound:Play() end)
        if not ok and sound.Parent then sound:Destroy() end
    end

    local function playWhenReady(kind, volume)
        refreshIds()
        local id = kind == "notify" and notifyId or clickId
        if id then
            playId(id, volume)
            return
        end
        if retryPending[kind] then return end
        retryPending[kind] = true
        task.spawn(function()
            for _ = 1, 24 do
                if Library.SoundEnabled == false then break end
                task.wait(0.125)
                refreshIds()
                id = kind == "notify" and notifyId or clickId
                if id then
                    playId(id, volume)
                    break
                end
            end
            retryPending[kind] = nil
        end)
    end

    ensureDownloads()
    local baseSfx = Library._sfx
    Library._sfx = function(name, ...)
        name = tostring(name or "")
        if type(baseSfx) == "function" then
            pcall(baseSfx, name, ...)
        end

        if Library.SoundEnabled == false then return end
        if name == "notify" then
            playWhenReady("notify", 0.9)
        elseif name == "hover" or name == "select" or name == "toggleOn" or name == "toggleOff" then
            playWhenReady("click", 0.55)
        end
        -- No custom click sound is assigned to slider/open/close/alert.
    end
end

return Library
