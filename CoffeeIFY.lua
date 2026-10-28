local CoffeeIFY = {}
CoffeeIFY.__index = CoffeeIFY

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TextService = game:GetService("TextService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local oldGui = playerGui:FindFirstChild("CoffeeIFY")
if oldGui then
	oldGui:Destroy()
end

local function Create(class, props)
	local inst = Instance.new(class)
	for k, v in pairs(props or {}) do
		inst[k] = v
	end
	return inst
end

local function Tween(obj, props, duration, style, dir)
	if not obj or not obj.Parent then
		return nil
	end

	local tw = TweenService:Create(
		obj,
		TweenInfo.new(duration or 0.35, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
		props
	)

	tw:Play()
	return tw
end

local HOVER_SOUND = 408524543
local CLICK_SOUND = 4307186075

local function PlaySound(id, volume)
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://" .. tostring(id)
	sound.Volume = volume or 0.4
	sound.PlaybackSpeed = 1
	sound.Parent = SoundService
	sound:Play()

	sound.Ended:Connect(function()
		if sound then
			sound:Destroy()
		end
	end)

	return sound
end

local function BindActivated(button, callback)
	return button.Activated:Connect(callback)
end

local function MeasureText(text, font, size, width)
	text = tostring(text or "")
	local bounds = TextService:GetTextSize(
		text,
		size,
		font,
		Vector2.new(math.max(width or 1, 1), 10000)
	)
	return math.max(bounds.X, 1), math.max(bounds.Y, 1)
end

local function GetPageWidth(page, fallback)
	local width = page and page.AbsoluteSize.X or 0
	if width > 0 then
		return width
	end

	local ancestor = page
	while ancestor and ancestor.Parent do
		ancestor = ancestor.Parent
		if ancestor:IsA("GuiObject") and ancestor.Name == "Main" then
			local rootWidth = ancestor.AbsoluteSize.X
			if rootWidth <= 0 then
				rootWidth = ancestor.Size.X.Offset
			end
			return math.max(rootWidth - 114, 120)
		end
	end

	return fallback or 260
end


function CoffeeIFY:_Track(connection)
	self._connections = self._connections or {}
	table.insert(self._connections, connection)
	return connection
end

function CoffeeIFY:_CleanupConnections()
	if self._connections then
		for _, connection in ipairs(self._connections) do
			if connection and connection.Connected then
				connection:Disconnect()
			end
		end
		table.clear(self._connections)
	end

	for _, sound in ipairs(self._sounds or {}) do
		if sound then
			sound:Stop()
			sound:Destroy()
		end
	end
	if self._sounds then
		table.clear(self._sounds)
	end
end

function CoffeeIFY:_GetPage(tab)
	if typeof(tab) == "table" then
		return tab.Page
	end

	local tabData = self.tabs and self.tabs[tab]

	if not tabData then
		error(("CoffeeIFY: tab '%s' does not exist."):format(tostring(tab)))
	end

	return tabData.Page
end

function CoffeeIFY.new(config)
	config = config or {}

	local self = setmetatable({}, CoffeeIFY)

	self._connections = {}
	self._sounds = {}
	self._closing = false
	self._minimized = false
	self._notifyStack = {}

	self.gui = Create("ScreenGui", {
		Name = "CoffeeIFY",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = true,
		DisplayOrder = 50,
		Parent = playerGui
	})

	local cam = workspace.CurrentCamera
	while not cam do
		workspace:GetPropertyChangedSignal("CurrentCamera"):Wait()
		cam = workspace.CurrentCamera
	end
	local vp = cam.ViewportSize

	-- Optional proportions. When omitted, auto-fit mobile & PC.
	-- config.Size   = number  -> square side
	-- config.Width / config.Height = pixel size
	-- config.Scale  = multiplier on auto size (default 1)
	-- config.Title  = window title string
	local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local shortSide = math.min(vp.X, vp.Y)

	local autoW, autoH
	if isMobile or vp.X < 700 then
		autoW = math.clamp(vp.X * 0.92, 260, 420)
		autoH = math.clamp(vp.Y * 0.55, 280, 480)
	else
		local base = math.clamp(shortSide * 0.42, 300, 460)
		autoW = base
		autoH = base
	end

	local scale = math.clamp(tonumber(config.Scale) or 1, 0.6, 1.6)
	local winW, winH

	if typeof(config.Size) == "number" then
		winW = math.floor(config.Size * scale)
		winH = winW
	elseif config.Width or config.Height then
		winW = math.floor((tonumber(config.Width) or autoW) * scale)
		winH = math.floor((tonumber(config.Height) or autoH) * scale)
	else
		winW = math.floor(autoW * scale)
		winH = math.floor(autoH * scale)
	end

	winW = math.clamp(winW, 240, math.max(260, vp.X - 24))
	winH = math.clamp(winH, 200, math.max(220, vp.Y - 24))

	self._winW = winW
	self._winH = winH
	self._isMobile = isMobile
	self._autoFit = not (config.Size or config.Width or config.Height)

	self.main = Create("Frame", {
		Name = "Main",
		Size = UDim2.new(0, winW, 0, winH),
		Position = UDim2.new(0.5, -winW / 2, 0.5, -winH / 2),
		BackgroundColor3 = Color3.fromRGB(232, 224, 205),
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Visible = true,
		Parent = self.gui
	})

	Create("UIStroke", {
		Color = Color3.fromRGB(170, 160, 140),
		Thickness = 1.5,
		Parent = self.main
	})

	self.topBar = Create("Frame", {
		Name = "TopBar",
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundColor3 = Color3.fromRGB(42, 38, 34),
		BorderSizePixel = 0,
		Parent = self.main
	})

	self.titleIcon = Create("TextLabel", {
		Text = "◆",
		Size = UDim2.new(0, 26, 1, 0),
		Position = UDim2.new(0, 4, 0, 0),
		BackgroundTransparency = 1,
		TextColor3 = Color3.fromRGB(225, 215, 195),
		Font = Enum.Font.GothamBold,
		TextSize = 18,
		Parent = self.topBar
	})

	self.title = Create("TextLabel", {
		Text = tostring(config.Title or "CoffeeIFY"),
		Size = UDim2.new(1, -100, 1, 0),
		Position = UDim2.new(0, 32, 0, 0),
		BackgroundTransparency = 1,
		TextColor3 = Color3.fromRGB(225, 215, 195),
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = self.topBar
	})

	local minBtn = Create("TextButton", {
		Name = "Minimize",
		Size = UDim2.new(0, 28, 0, 28),
		Position = UDim2.new(1, -56, 0, 0),
		BackgroundTransparency = 1,
		Text = "–",
		TextColor3 = Color3.fromRGB(200, 190, 170),
		Font = Enum.Font.GothamBold,
		TextSize = 18,
		AutoButtonColor = false,
		Parent = self.topBar
	})

	local closeBtn = Create("TextButton", {
		Name = "Close",
		Size = UDim2.new(0, 28, 0, 28),
		Position = UDim2.new(1, -28, 0, 0),
		BackgroundTransparency = 1,
		Text = "×",
		TextColor3 = Color3.fromRGB(200, 190, 170),
		Font = Enum.Font.GothamBold,
		TextSize = 18,
		AutoButtonColor = false,
		Parent = self.topBar
	})

	self.sidebar = Create("Frame", {
		Name = "Sidebar",
		Size = UDim2.new(0, 112, 1, -28), -- a bit wider to the left
		Position = UDim2.new(0, 0, 0, 28),
		BackgroundColor3 = Color3.fromRGB(205, 195, 175),
		BorderSizePixel = 0,
		Parent = self.main
	})

	Create("UIStroke", {
		Color = Color3.fromRGB(170, 160, 140),
		Thickness = 1,
		Parent = self.sidebar
	})

	self.content = Create("Frame", {
		Name = "Content",
		Size = UDim2.new(1, -112, 1, -28),
		Position = UDim2.new(0, 112, 0, 28),
		BackgroundColor3 = Color3.fromRGB(232, 224, 205),
		BorderSizePixel = 0,
		Parent = self.main
	})

	self.contentTitle = Create("TextLabel", {
		Name = "Title",
		Text = "TAB 1",
		Size = UDim2.new(1, -16, 0, 28),
		Position = UDim2.new(0, 12, 0, 6),
		BackgroundTransparency = 1,
		TextColor3 = Color3.fromRGB(35, 30, 25),
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = self.content
	})

	self.pages = Create("Folder", {
		Name = "Pages",
		Parent = self.content
	})

	self.tabs = {}
	self.tabButtons = {}
	self.currentTab = nil
	self.tabCount = 0

	local minimizedSize = UDim2.new(0, self._winW, 0, 28)
	local normalSize = UDim2.new(0, self._winW, 0, self._winH)

	local function setMinimized(value)
		if self._closing then
			return
		end

		self._minimized = value

		if value then
			for _, child in ipairs(self.main:GetChildren()) do
				if child ~= self.topBar and child:IsA("GuiObject") then
					Tween(child, {
						BackgroundTransparency = 1
					}, 0.1)
				end
			end

			Tween(self.main, {
				Size = minimizedSize
			}, 0.22, Enum.EasingStyle.Quad)

			task.delay(0.1, function()
				if self._minimized and not self._closing then
					for _, child in ipairs(self.main:GetChildren()) do
						if child ~= self.topBar and child:IsA("GuiObject") then
							child.Visible = false
						end
					end
				end
			end)
		else
			for _, child in ipairs(self.main:GetChildren()) do
				if child ~= self.topBar and child:IsA("GuiObject") then
					child.Visible = true
				end
			end

			Tween(self.main, {
				Size = normalSize
			}, 0.3, Enum.EasingStyle.Quad)

			task.delay(0.05, function()
				if not self._minimized and not self._closing then
					Tween(self.sidebar, {BackgroundTransparency = 0}, 0.18)
					Tween(self.content, {BackgroundTransparency = 0}, 0.18)

					for _, child in ipairs(self.content:GetDescendants()) do
						if child:IsA("GuiObject") then
							if child:IsA("TextLabel") or child:IsA("TextButton") or child:IsA("TextBox") then
								local props = {}
								if child.TextTransparency < 1 then
									props.TextTransparency = 0
								end
								if next(props) then
									Tween(child, props, 0.18)
								end
							end
						end
					end
				end
			end)
		end
	end

	local spinActive = true
	self:_Track(RunService.RenderStepped:Connect(function(dt)
		if not spinActive or self._closing or not self.titleIcon or not self.titleIcon.Parent then
			return
		end
		self.titleIcon.Rotation = (self.titleIcon.Rotation + dt * 120) % 360
	end))

	self:_Track(minBtn.MouseEnter:Connect(function()
		if self._closing then return end
		PlaySound(HOVER_SOUND, 0.2)
		Tween(minBtn, {TextColor3 = Color3.fromRGB(255, 255, 255)}, 0.15)
	end))

	self:_Track(minBtn.MouseLeave:Connect(function()
		if self._closing then return end
		Tween(minBtn, {TextColor3 = Color3.fromRGB(200, 190, 170)}, 0.15)
	end))

	self:_Track(closeBtn.MouseEnter:Connect(function()
		if self._closing then return end
		PlaySound(HOVER_SOUND, 0.2)
		Tween(closeBtn, {TextColor3 = Color3.fromRGB(255, 120, 120)}, 0.15)
	end))

	self:_Track(closeBtn.MouseLeave:Connect(function()
		if self._closing then return end
		Tween(closeBtn, {TextColor3 = Color3.fromRGB(200, 190, 170)}, 0.15)
	end))

	self:_Track(BindActivated(minBtn, function()
		if self._closing then return end
		PlaySound(CLICK_SOUND, 0.4)
		setMinimized(not self._minimized)
	end))

	local function doClose()
		if self._closing then
			return
		end

		self._closing = true
		spinActive = false
		PlaySound(CLICK_SOUND, 0.45)
		self:_CleanupConnections()

		if self.gui then
			self.gui:Destroy()
		end
	end

	self:_Track(BindActivated(closeBtn, doClose))

	local dragging = false
	local dragStart
	local startPos
	local dragInput

	self:_Track(self.topBar.InputBegan:Connect(function(input)
		if self._closing then
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then

			dragging = true
			dragStart = input.Position
			startPos = self.main.Position
			dragInput = input
		end
	end))

	self:_Track(UserInputService.InputChanged:Connect(function(input)
		if not dragging or self._closing then
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then

			local delta = input.Position - dragStart

			self.main.Position = UDim2.new(
				startPos.X.Scale,
				startPos.X.Offset + delta.X,
				startPos.Y.Scale,
				startPos.Y.Offset + delta.Y
			)
		end
	end))

	self:_Track(UserInputService.InputEnded:Connect(function(input)
		if input == dragInput
			or input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then

			dragging = false
			dragInput = nil
		end
	end))

	self:_Track(cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		if self._closing then
			return
		end

		-- Only auto-refit when user did not lock Width/Height/Size
		if not self._autoFit then
			return
		end

		local newVp = cam.ViewportSize
		local mobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		local short = math.min(newVp.X, newVp.Y)
		local nw, nh

		if mobile or newVp.X < 700 then
			nw = math.clamp(newVp.X * 0.92, 260, 420)
			nh = math.clamp(newVp.Y * 0.55, 280, 480)
		else
			local b = math.clamp(short * 0.42, 300, 460)
			nw, nh = b, b
		end

		nw = math.clamp(math.floor(nw * scale), 240, math.max(260, newVp.X - 24))
		nh = math.clamp(math.floor(nh * scale), 200, math.max(220, newVp.Y - 24))

		self._winW, self._winH = nw, nh
		normalSize = UDim2.new(0, nw, 0, nh)
		minimizedSize = UDim2.new(0, nw, 0, 28)

		if self._minimized then
			self.main.Size = minimizedSize
		else
			self.main.Size = normalSize
			self.main.Position = UDim2.new(0.5, -nw / 2, 0.5, -nh / 2)
		end
	end))

	return self
end

function CoffeeIFY:CreateTab(name)
	if self._closing then
		return
	end

	if self.tabs[name] then
		warn(("CoffeeIFY: tab '%s' already exists."):format(name))
		return self.tabs[name]
	end

	self.tabCount += 1
	local index = self.tabCount

	-- smaller tab height, flush left with sidebar
	local TAB_H = 22
	local TAB_GAP = 26

	local btn = Create("TextButton", {
		Name = name,
		Size = UDim2.new(1, -4, 0, TAB_H), -- almost full width of sidebar
		Position = UDim2.new(0, 2, 0, 6 + (index - 1) * TAB_GAP),
		BackgroundColor3 = Color3.fromRGB(185, 175, 155),
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		Rotation = 0,
		Parent = self.sidebar
	})

	-- top + bottom selection lines (hidden by default)
	local topLine = Create("Frame", {
		Name = "TopLine",
		Size = UDim2.new(1, 0, 0, 1.5),
		Position = UDim2.new(0, 0, 0, 0),
		BackgroundColor3 = Color3.fromRGB(42, 38, 34),
		BorderSizePixel = 0,
		Visible = false,
		Parent = btn
	})

	local bottomLine = Create("Frame", {
		Name = "BottomLine",
		Size = UDim2.new(1, 0, 0, 1.5),
		Position = UDim2.new(0, 0, 1, -1.5),
		BackgroundColor3 = Color3.fromRGB(42, 38, 34),
		BorderSizePixel = 0,
		Visible = false,
		Parent = btn
	})

	local icon = Create("Frame", {
		Size = UDim2.new(0, 7, 0, 7),
		Position = UDim2.new(0, 8, 0.5, -3.5),
		BackgroundColor3 = Color3.fromRGB(70, 60, 50),
		BorderSizePixel = 0,
		Parent = btn
	})

	local label = Create("TextLabel", {
		Text = name,
		Size = UDim2.new(1, -24, 1, 0),
		Position = UDim2.new(0, 20, 0, 0),
		BackgroundTransparency = 1,
		TextColor3 = Color3.fromRGB(45, 40, 35),
		Font = Enum.Font.GothamMedium,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = btn
	})

	local page = Create("ScrollingFrame", {
		Name = name,
		Size = UDim2.new(1, -16, 1, -42),
		Position = UDim2.new(0, 8, 0, 36),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = Color3.fromRGB(140, 130, 110),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = self.pages
	})

	Create("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = page
	})

	Create("UIPadding", {
		PaddingTop = UDim.new(0, 2),
		PaddingBottom = UDim.new(0, 6),
		Parent = page
	})

	local tabData = {
		Button = btn,
		Icon = icon,
		Label = label,
		Page = page,
		Name = name,
		TopLine = topLine,
		BottomLine = bottomLine
	}

	self.tabs[name] = tabData
	self.tabButtons[index] = tabData

	local function glitchTypewriter(targetText)
		if not self.contentTitle or not self.contentTitle.Parent then return end

		local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%&*"
		local final = targetText
		local len = #final
		local host = self.content

		-- black-spot glitch bursts over content header
		task.spawn(function()
			local endAt = os.clock() + 0.32
			while os.clock() < endAt and host and host.Parent do
				if math.random() < 0.6 then
					local w = math.random(8, 48)
					local h = math.random(2, 8)
					local x = math.random(0, math.max(0, (host.AbsoluteSize.X or 120) - w))
					local y = math.random(2, 28)
					local spot = Create("Frame", {
						Name = "GlitchSpot",
						BackgroundColor3 = Color3.new(0, 0, 0),
						BackgroundTransparency = math.random() * 0.2,
						BorderSizePixel = 0,
						Size = UDim2.fromOffset(w, h),
						Position = UDim2.fromOffset(x, y),
						ZIndex = 40,
						Parent = host
					})
					task.delay(0.04 + math.random() * 0.07, function()
						if spot and spot.Parent then
							spot:Destroy()
						end
					end)
				end
				if math.random() < 0.25 then
					local h = math.random(1, 3)
					local line = Create("Frame", {
						Name = "GlitchLine",
						BackgroundColor3 = Color3.new(0, 0, 0),
						BackgroundTransparency = 0.1,
						BorderSizePixel = 0,
						Size = UDim2.new(1, 0, 0, h),
						Position = UDim2.fromOffset(0, math.random(4, 30)),
						ZIndex = 41,
						Parent = host
					})
					task.delay(0.03 + math.random() * 0.05, function()
						if line and line.Parent then
							line:Destroy()
						end
					end)
				end
				task.wait(0.03)
			end
		end)

		-- fast glitch phase
		task.spawn(function()
			for i = 1, 8 do
				if not self.contentTitle or not self.contentTitle.Parent then return end
				local glitched = ""
				for j = 1, len do
					if math.random() > 0.35 then
						local r = math.random(1, #chars)
						glitched = glitched .. chars:sub(r, r)
					else
						glitched = glitched .. final:sub(j, j)
					end
				end
				self.contentTitle.Text = glitched
				task.wait(0.028)
			end

			-- typewriter phase
			self.contentTitle.Text = ""
			for i = 1, len do
				if not self.contentTitle or not self.contentTitle.Parent then return end
				self.contentTitle.Text = final:sub(1, i)
				task.wait(0.035)
			end
			self.contentTitle.Text = final
		end)
	end

	local function select()
		if self._closing then
			return
		end

		PlaySound(CLICK_SOUND, 0.35)

		-- reset all tabs first
		for i, t in pairs(self.tabButtons) do
			Tween(t.Button, {
				BackgroundColor3 = Color3.fromRGB(185, 175, 155),
				Rotation = 0,
				Position = UDim2.new(0, 2, 0, 6 + (i - 1) * 26)
			}, 0.22)
			Tween(t.Label, {TextColor3 = Color3.fromRGB(45, 40, 35)}, 0.2)
			Tween(t.Icon, {BackgroundColor3 = Color3.fromRGB(70, 60, 50)}, 0.2)
			if t.TopLine then t.TopLine.Visible = false end
			if t.BottomLine then t.BottomLine.Visible = false end
			t.Page.Visible = false
		end

		-- selected tab
		Tween(btn, {
			BackgroundColor3 = Color3.fromRGB(48, 43, 38),
			Rotation = 0,
			Position = UDim2.new(0, 2, 0, 6 + (index - 1) * 26)
		}, 0.22)
		Tween(label, {TextColor3 = Color3.fromRGB(230, 220, 200)}, 0.22)
		Tween(icon, {BackgroundColor3 = Color3.fromRGB(230, 220, 200)}, 0.22)

		-- show top + bottom dark lines on selected tab
		topLine.Visible = true
		bottomLine.Visible = true

		-- tilt the tabs BELOW the selected one (weight effect)
		for i, t in pairs(self.tabButtons) do
			if i > index then
				local distance = i - index
				local tilt = -4.5 - (distance * 1.8)
				local offsetX = -3 - (distance * 1.5)

				Tween(t.Button, {
					Rotation = tilt,
					Position = UDim2.new(0, 2 + offsetX, 0, 6 + (i - 1) * 26)
				}, 0.28, Enum.EasingStyle.Back)
			end
		end

		page.Visible = true
		self.currentTab = tabData

		-- glitch + typewriter on the content title
		glitchTypewriter(name)
	end

	self:_Track(btn.MouseEnter:Connect(function()
		if self._closing then return end
		PlaySound(HOVER_SOUND, 0.18)

		if self.currentTab ~= tabData then
			Tween(btn, {BackgroundColor3 = Color3.fromRGB(200, 190, 170)}, 0.15)
		end
	end))

	self:_Track(btn.MouseLeave:Connect(function()
		if self._closing then return end

		if self.currentTab ~= tabData then
			Tween(btn, {BackgroundColor3 = Color3.fromRGB(185, 175, 155)}, 0.15)
		end
	end))

	self:_Track(BindActivated(btn, select))

	if index == 1 then
		select()
	end

	return tabData
end

function CoffeeIFY:CreateButton(tab, text, callback)
	local page = self:_GetPage(tab)
	text = tostring(text or "Button")

	local pageWidth = GetPageWidth(page, 260)
	local naturalWidth = MeasureText(text, Enum.Font.Gotham, 12, 10000)
	local labelWidth = math.max(math.min(math.max(naturalWidth + 6, 80), pageWidth - 36), 70)
	local _, textHeight = MeasureText(text, Enum.Font.Gotham, 12, labelWidth - 4)
	local rowHeight = math.max(26, textHeight + 10)

	local frame = Create("Frame", {
		Size = UDim2.new(1, -12, 0, rowHeight),
		Position = UDim2.new(0, 6, 0, 0),
		BackgroundColor3 = Color3.fromRGB(218, 208, 188),
		BorderSizePixel = 0,
		Parent = page
	})

	local box = Create("Frame", {
		Size = UDim2.new(0, 12, 0, 12),
		Position = UDim2.new(0, 14, 0.5, -6),
		BackgroundColor3 = Color3.fromRGB(40, 35, 30),
		BorderSizePixel = 0,
		Parent = frame
	})

	local label = Create("TextLabel", {
		Text = text,
		Size = UDim2.new(1, -72, 0, math.max(18, rowHeight - 4)),
		Position = UDim2.new(0, 32, 0, 2),
		BackgroundTransparency = 1,
		TextColor3 = Color3.fromRGB(40, 35, 30),
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame
	})

	local btn = Create("TextButton", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Parent = frame
	})

	local hovering = false

	local function resetVisual()
		Tween(frame, {
			BackgroundColor3 = Color3.fromRGB(218, 208, 188),
			Position = UDim2.new(0, 6, 0, 0)
		}, 0.15)
		Tween(box, {
			BackgroundColor3 = Color3.fromRGB(40, 35, 30),
			Size = UDim2.new(0, 12, 0, 12),
			Position = UDim2.new(0, 14, 0.5, -6)
		}, 0.15)
		label.TextXAlignment = Enum.TextXAlignment.Left
		Tween(label, {
			Position = UDim2.new(0, 32, 0, 2),
			Size = UDim2.new(1, -72, 0, math.max(18, rowHeight - 4))
		}, 0.15)
	end

	self:_Track(btn.MouseEnter:Connect(function()
		hovering = true
		PlaySound(HOVER_SOUND, 0.22)
		Tween(frame, {BackgroundColor3 = Color3.fromRGB(230, 220, 200)}, 0.15)
		Tween(box, {Size = UDim2.new(0, 13, 0, 13), Position = UDim2.new(0, 13.5, 0.5, -6.5)}, 0.15)
	end))

	self:_Track(btn.MouseLeave:Connect(function()
		hovering = false
		resetVisual()
	end))

	self:_Track(BindActivated(btn, function()
		PlaySound(CLICK_SOUND, 0.4)

		-- quick press feedback
		Tween(frame, {BackgroundColor3 = Color3.fromRGB(200, 190, 170)}, 0.08)
		Tween(box, {
			BackgroundColor3 = Color3.fromRGB(180, 160, 130),
			Size = UDim2.new(0, 11, 0, 11)
		}, 0.08)

		task.delay(0.1, function()
			if not frame.Parent then return end
			-- always return to normal, then re-apply hover if still over
			resetVisual()
			if hovering then
				task.delay(0.12, function()
					if hovering and frame.Parent then
						Tween(frame, {BackgroundColor3 = Color3.fromRGB(230, 220, 200)}, 0.12)
						Tween(box, {Size = UDim2.new(0, 13, 0, 13), Position = UDim2.new(0, 13.5, 0.5, -6.5)}, 0.12)
					end
				end)
			end
		end)

		if callback then
			task.spawn(callback)
		end
	end))

	return frame
end

function CoffeeIFY:CreateToggle(tab, text, default, callback)
	local page = self:_GetPage(tab)
	text = tostring(text or "Toggle")
	local state = default == true

	local pageWidth = GetPageWidth(page, 260)
	local naturalWidth = MeasureText(text, Enum.Font.Gotham, 12, 10000)
	local labelWidth = math.max(math.min(math.max(naturalWidth + 6, 80), pageWidth - 36), 70)
	local _, textHeight = MeasureText(text, Enum.Font.Gotham, 12, labelWidth - 4)
	local rowHeight = math.max(26, textHeight + 10)

	local frame = Create("Frame", {
		Size = UDim2.new(1, 0, 0, rowHeight),
		BackgroundColor3 = Color3.fromRGB(218, 208, 188),
		BorderSizePixel = 0,
		Parent = page
	})

	local box = Create("Frame", {
		Size = UDim2.new(0, 12, 0, 12),
		Position = UDim2.new(0, 8, 0.5, -6),
		BackgroundColor3 = state and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(40, 35, 30),
		BorderSizePixel = 0,
		Parent = frame
	})

	Create("TextLabel", {
		Text = text,
		Size = UDim2.new(1, -36, 0, math.max(18, rowHeight - 4)),
		Position = UDim2.new(0, 26, 0, 2),
		BackgroundTransparency = 1,
		TextColor3 = Color3.fromRGB(40, 35, 30),
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame
	})

	local btn = Create("TextButton", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Parent = frame
	})

	local hovering = false

	self:_Track(btn.MouseEnter:Connect(function()
		hovering = true
		PlaySound(HOVER_SOUND, 0.22)
		Tween(frame, {BackgroundColor3 = Color3.fromRGB(230, 220, 200)}, 0.15)
		Tween(box, {Size = UDim2.new(0, 13, 0, 13), Position = UDim2.new(0, 7.5, 0.5, -6.5)}, 0.15)
	end))

	self:_Track(btn.MouseLeave:Connect(function()
		hovering = false
		Tween(frame, {BackgroundColor3 = Color3.fromRGB(218, 208, 188)}, 0.15)
		Tween(box, {Size = UDim2.new(0, 12, 0, 12), Position = UDim2.new(0, 8, 0.5, -6)}, 0.15)
	end))

	self:_Track(BindActivated(btn, function()
		PlaySound(CLICK_SOUND, 0.4)
		state = not state

		Tween(frame, {BackgroundColor3 = Color3.fromRGB(200, 190, 170)}, 0.08)
		Tween(box, {
			BackgroundColor3 = state and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(40, 35, 30),
			Size = UDim2.new(0, 11, 0, 11)
		}, 0.1)

		task.delay(0.1, function()
			if not frame.Parent then return end
			Tween(frame, {BackgroundColor3 = Color3.fromRGB(218, 208, 188)}, 0.15)
			Tween(box, {Size = UDim2.new(0, 12, 0, 12), Position = UDim2.new(0, 8, 0.5, -6)}, 0.15)

			if hovering then
				task.delay(0.12, function()
					if hovering and frame.Parent then
						Tween(frame, {BackgroundColor3 = Color3.fromRGB(230, 220, 200)}, 0.12)
						Tween(box, {Size = UDim2.new(0, 13, 0, 13), Position = UDim2.new(0, 7.5, 0.5, -6.5)}, 0.12)
					end
				end)
			end
		end)

		if callback then
			task.spawn(callback, state)
		end
	end))

	return frame
end

function CoffeeIFY:CreateSlider(tab, text, min, max, default, callback)
	local page = self:_GetPage(tab)
	text = tostring(text or "Slider")

	min = tonumber(min) or 0
	max = tonumber(max) or 100

	if max < min then
		min, max = max, min
	end

	if max == min then
		max = min + 1
	end

	local value = math.clamp(tonumber(default) or min, min, max)
	local pageWidth = GetPageWidth(page, 260)
	local naturalWidth = MeasureText(text, Enum.Font.Gotham, 12, 10000)
	local labelWidth = math.clamp(math.ceil(naturalWidth + 28), 70, math.floor(pageWidth * 0.5))
	local _, textHeight = MeasureText(text, Enum.Font.Gotham, 12, math.max(labelWidth - 18, 40))
	local rowHeight = math.max(26, textHeight + 10)
	local barWidth = math.max(64, pageWidth - labelWidth - 28)

	local frame = Create("Frame", {
		Size = UDim2.new(1, 0, 0, rowHeight),
		BackgroundColor3 = Color3.fromRGB(218, 208, 188),
		BorderSizePixel = 0,
		Parent = page
	})

	Create("TextLabel", {
		Text = "≡",
		Size = UDim2.new(0, 16, 1, 0),
		Position = UDim2.new(0, 6, 0, 0),
		BackgroundTransparency = 1,
		TextColor3 = Color3.fromRGB(40, 35, 30),
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextYAlignment = Enum.TextYAlignment.Center,
		Parent = frame
	})

	Create("TextLabel", {
		Text = text,
		Size = UDim2.new(0, labelWidth - 18, 1, -4),
		Position = UDim2.new(0, 22, 0, 2),
		BackgroundTransparency = 1,
		TextColor3 = Color3.fromRGB(40, 35, 30),
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame
	})

	local bar = Create("Frame", {
		Size = UDim2.new(0, barWidth, 0, 3),
		Position = UDim2.new(1, -barWidth - 12, 0.5, -1.5),
		BackgroundColor3 = Color3.fromRGB(155, 145, 125),
		BorderSizePixel = 0,
		Active = true,
		Parent = frame
	})

	local normalized = (value - min) / (max - min)

	local fill = Create("Frame", {
		Size = UDim2.new(normalized, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(70, 60, 50),
		BorderSizePixel = 0,
		Parent = bar
	})

	local knob = Create("Frame", {
		Size = UDim2.new(0, 10, 0, 10),
		Position = UDim2.new(normalized, -5, 0.5, -5),
		BackgroundColor3 = Color3.fromRGB(45, 40, 35),
		BorderSizePixel = 0,
		Active = true,
		Parent = bar
	})

	local dragging = false

	-- mechanical loop sound while holding slider
	local mechSound = Instance.new("Sound")
	mechSound.SoundId = "rbxassetid://9114226706" -- short mechanical tick/loop friendly
	mechSound.Volume = 0.35
	mechSound.Looped = true
	mechSound.Parent = SoundService
	table.insert(self._sounds, mechSound)

	local function stopMech()
		if mechSound.IsPlaying then
			mechSound:Stop()
		end
	end

	local function startMech()
		if not mechSound.IsPlaying then
			mechSound:Play()
		end
	end

	local function updateFromX(x)
		if not bar.Parent then return end

		local width = bar.AbsoluteSize.X
		if width <= 0 then return end

		local rel = math.clamp((x - bar.AbsolutePosition.X) / width, 0, 1)
		value = math.floor(min + (max - min) * rel + 0.5)

		local current = (value - min) / (max - min)
		fill.Size = UDim2.new(current, 0, 1, 0)
		knob.Position = UDim2.new(current, -5, 0.5, -5)

		if callback then
			task.spawn(callback, value)
		end
	end

	local function beginSlider(input)
		if self._closing then return end

		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			PlaySound(CLICK_SOUND, 0.3)
			startMech()
			updateFromX(input.Position.X)
		end
	end

	self:_Track(bar.InputBegan:Connect(beginSlider))
	self:_Track(knob.InputBegan:Connect(beginSlider))

	self:_Track(UserInputService.InputChanged:Connect(function(input)
		if not dragging or self._closing then return end

		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			updateFromX(input.Position.X)
		end
	end))

	self:_Track(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
			stopMech()
		end
	end))

	return frame
end

function CoffeeIFY:CreateTextBox(tab, placeholder, callback)
	local page = self:_GetPage(tab)

	local frame = Create("Frame", {
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundColor3 = Color3.fromRGB(218, 208, 188),
		BorderSizePixel = 0,
		Parent = page
	})

	local box = Create("TextBox", {
		Size = UDim2.new(1, -16, 1, -6),
		Position = UDim2.new(0, 8, 0, 3),
		BackgroundColor3 = Color3.fromRGB(240, 232, 215),
		BorderSizePixel = 0,
		Text = "",
		PlaceholderText = placeholder or "Type here...",
		PlaceholderColor3 = Color3.fromRGB(140, 130, 110),
		TextColor3 = Color3.fromRGB(40, 35, 30),
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		Parent = frame
	})

	Create("UIPadding", {
		PaddingLeft = UDim.new(0, 6),
		Parent = box
	})

	self:_Track(box.FocusLost:Connect(function(enter)
		if callback then
			task.spawn(callback, box.Text, enter)
		end
	end))

	return frame, box
end

function CoffeeIFY:CreateLabel(tab, text)
	local page = self:_GetPage(tab)

	local label = Create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		Text = tostring(text or "Label"),
		TextColor3 = Color3.fromRGB(90, 80, 70),
		Font = Enum.Font.Gotham,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = page
	})

	return label
end

function CoffeeIFY:CreateDropdown(tab, text, options, default, callback, theme)
	local page = self:_GetPage(tab)

	options = options or {"Option 1", "Option 2", "Option 3"}

	if #options == 0 then
		options = {"Option 1"}
	end

	theme = theme or {}

	local t = {
		Bg = theme.Bg or Color3.fromRGB(218, 208, 188),
		ListBg = theme.ListBg or Color3.fromRGB(210, 200, 180),
		Hover = theme.Hover or Color3.fromRGB(200, 190, 170),
		Text = theme.Text or Color3.fromRGB(40, 35, 30),
		SelectedText = theme.SelectedText or Color3.fromRGB(80, 70, 60),
		Stroke = theme.Stroke or Color3.fromRGB(170, 160, 140),
		Arrow = theme.Arrow or Color3.fromRGB(60, 55, 50)
	}

	local selected = default

	local validDefault = false

	for _, option in ipairs(options) do
		if option == selected then
			validDefault = true
			break
		end
	end

	if not validDefault then
		selected = options[1]
	end

	local open = false
	local destroyed = false
	local pageWidth = GetPageWidth(page, 260)
	local naturalLabelWidth = MeasureText(text or "Dropdown", Enum.Font.Gotham, 12, 10000)
	local naturalValueWidth = MeasureText(tostring(selected), Enum.Font.GothamMedium, 11, 10000)
	local labelWidth = math.clamp(math.ceil(naturalLabelWidth + 18), 80, math.floor(pageWidth * 0.52))
	local valueWidth = math.clamp(math.ceil(naturalValueWidth + 24), 70, math.floor(pageWidth * 0.44))
	local _, labelHeight = MeasureText(text or "Dropdown", Enum.Font.Gotham, 12, math.max(labelWidth - 18, 40))
	local _, selectedHeight = MeasureText(tostring(selected), Enum.Font.GothamMedium, 11, math.max(valueWidth - 18, 40))
	local rowHeight = math.max(26, math.max(labelHeight, selectedHeight) + 8)

	local frame = Create("Frame", {
		Size = UDim2.new(1, 0, 0, rowHeight),
		BackgroundColor3 = t.Bg,
		BorderSizePixel = 0,
		ClipsDescendants = false,
		Parent = page
	})

	local mainBtn = Create("TextButton", {
		Size = UDim2.new(1, 0, 0, rowHeight),
		BackgroundColor3 = t.Bg,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		Parent = frame
	})

	Create("TextLabel", {
		Text = text or "Dropdown",
		Size = UDim2.new(0, labelWidth - 10, 1, 0),
		Position = UDim2.new(0, 10, 0, 0),
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Center,
		BackgroundTransparency = 1,
		TextColor3 = t.Text,
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = mainBtn
	})

	local selectedLabel = Create("TextLabel", {
		Name = "Selected",
		Text = tostring(selected),
		Size = UDim2.new(0, valueWidth - 6, 1, 0),
		Position = UDim2.new(1, -valueWidth - 12, 0, 0),
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Center,
		BackgroundTransparency = 1,
		TextColor3 = t.SelectedText,
		Font = Enum.Font.GothamMedium,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = mainBtn
	})

	local arrow = Create("TextLabel", {
		Text = "▾",
		Size = UDim2.new(0, 16, 1, 0),
		Position = UDim2.new(1, -18, 0, 0),
		BackgroundTransparency = 1,
		TextColor3 = t.Arrow,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		Parent = mainBtn
	})

	local list = Create("Frame", {
		Name = "List",
		Size = UDim2.new(1, 0, 0, 0),
		Position = UDim2.new(0, 0, 0, rowHeight),
		BackgroundColor3 = t.ListBg,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Visible = false,
		ZIndex = 20,
		Parent = frame
	})

	Create("UIStroke", {
		Color = t.Stroke,
		Thickness = 1,
		Parent = list
	})

	Create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 1),
		Parent = list
	})

	local function closeDropdown()
		if not open then
			return
		end

		open = false
		arrow.Text = "▾"

		Tween(list, {
			Size = UDim2.new(1, 0, 0, 0)
		}, 0.2)

		task.delay(0.2, function()
			if not open and list.Parent then
				list.Visible = false
			end
		end)
	end

	local function openDropdown()
		if open or destroyed or self._closing then
			return
		end

		open = true
		list.Visible = true

		local height = #options * 24

		Tween(list, {
			Size = UDim2.new(1, 0, 0, height)
		}, 0.22, Enum.EasingStyle.Quad)

		arrow.Text = "▴"
		PlaySound(CLICK_SOUND, 0.3)
	end

	for index, opt in ipairs(options) do
		local optBtn = Create("TextButton", {
			Size = UDim2.new(1, 0, 0, 23),
			BackgroundColor3 = t.Bg,
			BorderSizePixel = 0,
			Text = "  " .. tostring(opt),
			TextColor3 = t.Text,
			Font = Enum.Font.Gotham,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			AutoButtonColor = false,
			ZIndex = 21,
			LayoutOrder = index,
			Parent = list
		})

		self:_Track(optBtn.MouseEnter:Connect(function()
			if self._closing then return end
			PlaySound(HOVER_SOUND, 0.18)
			optBtn.BackgroundColor3 = t.Hover
		end))

		self:_Track(optBtn.MouseLeave:Connect(function()
			if optBtn.Parent then
				optBtn.BackgroundColor3 = t.Bg
			end
		end))

		self:_Track(BindActivated(optBtn, function()
			if self._closing then
				return
			end

			PlaySound(CLICK_SOUND, 0.4)

			selected = opt
			selectedLabel.Text = tostring(selected)

			closeDropdown()

			if callback then
				task.spawn(callback, selected)
			end
		end))
	end

	self:_Track(BindActivated(mainBtn, function()
		if open then
			closeDropdown()
		else
			openDropdown()
		end
	end))

	self:_Track(mainBtn.MouseEnter:Connect(function()
		if self._closing then return end
		PlaySound(HOVER_SOUND, 0.2)

		Tween(mainBtn, {
			BackgroundColor3 = t.Hover
		}, 0.15)
	end))

	self:_Track(mainBtn.MouseLeave:Connect(function()
		if self._closing then return end

		Tween(mainBtn, {
			BackgroundColor3 = t.Bg
		}, 0.15)
	end))

	self:_Track(UserInputService.InputBegan:Connect(function(input)
		if not open or self._closing then
			return
		end

		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end

		local pos = input.Position

		local mainPos = mainBtn.AbsolutePosition
		local mainSize = mainBtn.AbsoluteSize
		local listPos = list.AbsolutePosition
		local listSize = list.AbsoluteSize

		local insideMain =
			pos.X >= mainPos.X
			and pos.X <= mainPos.X + mainSize.X
			and pos.Y >= mainPos.Y
			and pos.Y <= mainPos.Y + mainSize.Y

		local insideList =
			pos.X >= listPos.X
			and pos.X <= listPos.X + listSize.X
			and pos.Y >= listPos.Y
			and pos.Y <= listPos.Y + listSize.Y

		if not insideMain and not insideList then
			closeDropdown()
		end
	end))

	self:_Track(frame.AncestryChanged:Connect(function(_, parent)
		if not parent then
			destroyed = true
			open = false
		end
	end))

	return frame
end

function CoffeeIFY:CreateKeybind(tab, text, default, callback)
	local page = self:_GetPage(tab)

	local key = default or Enum.KeyCode.E
	local listening = false
	text = tostring(text or "Keybind")
	local pageWidth = GetPageWidth(page, 260)
	local naturalWidth = MeasureText(text, Enum.Font.Gotham, 12, 10000)
	local labelWidth = math.clamp(math.ceil(naturalWidth + 18), 90, math.floor(pageWidth * 0.62))
	local _, textHeight = MeasureText(text, Enum.Font.Gotham, 12, math.max(labelWidth - 18, 40))
	local rowHeight = math.max(26, textHeight + 8)

	local frame = Create("Frame", {
		Size = UDim2.new(1, 0, 0, rowHeight),
		BackgroundColor3 = Color3.fromRGB(218, 208, 188),
		BorderSizePixel = 0,
		Parent = page
	})

	Create("TextLabel", {
		Text = text or "Keybind",
		Size = UDim2.new(0, labelWidth - 18, 1, 0),
		Position = UDim2.new(0, 10, 0, 0),
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Center,
		BackgroundTransparency = 1,
		TextColor3 = Color3.fromRGB(40, 35, 30),
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame
	})

	local keyLabel = Create("TextLabel", {
		Name = "Key",
		Text = typeof(key) == "EnumItem" and key.Name or tostring(key),
		Size = UDim2.new(0.35, -10, 0, 18),
		Position = UDim2.new(0.65, 0, 0.5, -9),
		BackgroundColor3 = Color3.fromRGB(50, 45, 40),
		BorderSizePixel = 0,
		TextColor3 = Color3.fromRGB(230, 220, 200),
		Font = Enum.Font.GothamMedium,
		TextSize = 11,
		Parent = frame
	})

	local btn = Create("TextButton", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		Parent = frame
	})

	local function displayKey()
		return typeof(key) == "EnumItem" and key.Name or tostring(key)
	end

	local function cancelListen()
		listening = false
		keyLabel.Text = displayKey()

		Tween(keyLabel, {
			BackgroundColor3 = Color3.fromRGB(50, 45, 40),
			TextColor3 = Color3.fromRGB(230, 220, 200)
		}, 0.2)

		Tween(frame, {
			BackgroundColor3 = Color3.fromRGB(218, 208, 188)
		}, 0.2)
	end

	local function setKey(newKey)
		key = newKey
		keyLabel.Text = displayKey()
		listening = false

		Tween(keyLabel, {
			BackgroundColor3 = Color3.fromRGB(50, 45, 40),
			TextColor3 = Color3.fromRGB(230, 220, 200)
		}, 0.2)

		Tween(frame, {
			BackgroundColor3 = Color3.fromRGB(218, 208, 188)
		}, 0.2)

		PlaySound(CLICK_SOUND, 0.35)
	end

	local function startListen()
		if listening or self._closing then
			return
		end

		PlaySound(HOVER_SOUND, 0.25)

		listening = true
		keyLabel.Text = "..."

		Tween(keyLabel, {
			BackgroundColor3 = Color3.fromRGB(80, 70, 55),
			TextColor3 = Color3.fromRGB(255, 240, 200)
		}, 0.18)

		Tween(frame, {
			BackgroundColor3 = Color3.fromRGB(230, 220, 200)
		}, 0.15)
	end

	self:_Track(btn.MouseEnter:Connect(function()
		if self._closing then return end

		PlaySound(HOVER_SOUND, 0.2)

		Tween(frame, {
			BackgroundColor3 = Color3.fromRGB(230, 220, 200)
		}, 0.15)

		Tween(keyLabel, {
			Size = UDim2.new(0.35, -8, 0, 19)
		}, 0.12)
	end))

	self:_Track(btn.MouseLeave:Connect(function()
		if not listening then
			Tween(frame, {
				BackgroundColor3 = Color3.fromRGB(218, 208, 188)
			}, 0.15)

			Tween(keyLabel, {
				Size = UDim2.new(0.35, -10, 0, 18)
			}, 0.12)
		end
	end))

	self:_Track(BindActivated(btn, startListen))

	self:_Track(UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if self._closing then
			return
		end

		if listening then
			if input.UserInputType == Enum.UserInputType.Keyboard then
				if input.KeyCode == Enum.KeyCode.Escape then
					cancelListen()
				elseif input.KeyCode ~= Enum.KeyCode.Unknown then
					setKey(input.KeyCode)
				end
			end

			return
		end

		if gameProcessed then
			return
		end

		if input.UserInputType == Enum.UserInputType.Keyboard
			and input.KeyCode == key then

			if callback then
				task.spawn(callback, key)
			end
		end
	end))

	return frame, function()
		return key
	end
end

--// Notifications (compact, coffee-themed, with black-spot glitch)
local NOTIFY_ICONS = {
	default = "rbxassetid://6031094678",
	info = "rbxassetid://6031229361",
	success = "rbxassetid://6031094667",
	warning = "rbxassetid://6031071053",
	error = "rbxassetid://6031094677",
	option = "rbxassetid://6031094678",
}

local ALERT_SOUND = 644569388

local function playNotifyGlitch(target, duration)
	duration = duration or 0.34
	local spots = {}
	local endTime = os.clock() + duration
	local conn
	conn = RunService.RenderStepped:Connect(function()
		if not target or not target.Parent or os.clock() > endTime then
			if conn then conn:Disconnect() end
			for _, s in ipairs(spots) do
				if s and s.Parent then s:Destroy() end
			end
			table.clear(spots)
			return
		end

		if math.random() < 0.5 then
			for _ = 1, math.random(1, 3) do
				local w = math.random(5, math.max(10, math.floor((target.AbsoluteSize.X or 160) * 0.4)))
				local h = math.random(2, 7)
				local x = math.random(0, math.max(0, (target.AbsoluteSize.X or 160) - w))
				local y = math.random(0, math.max(0, (target.AbsoluteSize.Y or 40) - h))
				local spot = Create("Frame", {
					BackgroundColor3 = Color3.new(0, 0, 0),
					BackgroundTransparency = math.random() * 0.25,
					BorderSizePixel = 0,
					Size = UDim2.fromOffset(w, h),
					Position = UDim2.fromOffset(x, y),
					ZIndex = (target.ZIndex or 300) + 20,
					Parent = target
				})
				table.insert(spots, spot)
				task.delay(0.04 + math.random() * 0.06, function()
					if spot and spot.Parent then spot:Destroy() end
				end)
			end
		end

		if math.random() < 0.16 then
			local h = math.random(1, 2)
			local line = Create("Frame", {
				BackgroundColor3 = Color3.new(0, 0, 0),
				BackgroundTransparency = 0.12,
				BorderSizePixel = 0,
				Size = UDim2.new(1, 0, 0, h),
				Position = UDim2.fromOffset(0, math.random(0, math.max(0, (target.AbsoluteSize.Y or 40) - h))),
				ZIndex = (target.ZIndex or 300) + 21,
				Parent = target
			})
			table.insert(spots, line)
			task.delay(0.03 + math.random() * 0.04, function()
				if line and line.Parent then line:Destroy() end
			end)
		end
	end)
end

--[[
	CoffeeIFY:Notify

	Simple:
		ui:Notify("Hello")
		ui:Notify("Saved", 3)

	Table:
		ui:Notify({
			Title = "Success",
			Description = "Settings saved",
			Duration = 4,
			Type = "success", -- default | info | success | warning | error | option
			Callback = function(accepted) end, -- for option type
		})
]]
function CoffeeIFY:Notify(opts, durationOrOpts, extra)
	if self._closing then
		return
	end

	local title, description, duration, nType, callback

	if type(opts) == "string" then
		title = opts
		description = ""
		duration = math.max(0, tonumber(durationOrOpts) or 3)
		nType = "default"
	elseif type(opts) == "table" then
		if type(durationOrOpts) == "table" or type(extra) == "table" then
			title = tostring(opts.Title or opts.title or "Notification")
			description = tostring(opts.Description or opts.description or opts.Content or "")
			local mid = type(durationOrOpts) == "table" and durationOrOpts or {}
			local last = type(extra) == "table" and extra or {}
			duration = math.max(0, tonumber(mid.Time or mid.Duration or last.Time or last.Duration) or 3.5)
			nType = string.lower(tostring(mid.Type or mid.type or last.Type or "default"))
			callback = last.Callback or mid.Callback
		else
			title = tostring(opts.Title or opts.title or opts.Text or "Notification")
			description = tostring(opts.Description or opts.description or opts.Content or "")
			duration = math.max(0, tonumber(opts.Duration or opts.duration or opts.Time or durationOrOpts) or 3.5)
			nType = string.lower(tostring(opts.Type or opts.type or "default"))
			callback = opts.Callback or opts.callback
		end
	else
		title = "Notification"
		description = ""
		duration = 3
		nType = "default"
	end

	if nType == "" then
		nType = "default"
	end

	-- smaller card
	local cardW = 210
	local cardH = description ~= "" and 52 or 38
	if nType == "option" then
		cardH = cardH + 22
	end

	local stack = self._notifyStack
	local host = self.gui

	local card = Create("Frame", {
		Name = "Notify",
		BackgroundColor3 = Color3.fromRGB(218, 208, 188),
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(cardW, cardH),
		Position = UDim2.new(1, 16, 1, -24 - cardH),
		ClipsDescendants = true,
		ZIndex = 300,
		Parent = host
	})

	Create("UIStroke", {
		Color = Color3.fromRGB(120, 100, 75),
		Thickness = 1,
		Parent = card
	})

	local accentColor = Color3.fromRGB(120, 80, 50)
	if nType == "success" then
		accentColor = Color3.fromRGB(90, 130, 70)
	elseif nType == "warning" then
		accentColor = Color3.fromRGB(180, 130, 50)
	elseif nType == "error" then
		accentColor = Color3.fromRGB(160, 70, 55)
	elseif nType == "info" then
		accentColor = Color3.fromRGB(100, 120, 150)
	end

	Create("Frame", {
		Name = "Accent",
		BackgroundColor3 = accentColor,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 2, 1, 0),
		ZIndex = 301,
		Parent = card
	})

	local icon = Create("ImageLabel", {
		BackgroundTransparency = 1,
		Image = NOTIFY_ICONS[nType] or NOTIFY_ICONS.default,
		ImageColor3 = accentColor,
		Size = UDim2.fromOffset(16, 16),
		Position = UDim2.fromOffset(8, 10),
		ZIndex = 302,
		Parent = card
	})

	Create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Text = title,
		Font = Enum.Font.GothamBold,
		TextSize = 11,
		TextColor3 = Color3.fromRGB(40, 35, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, -36, 0, 14),
		Position = UDim2.fromOffset(28, 8),
		ZIndex = 302,
		Parent = card
	})

	if description ~= "" then
		Create("TextLabel", {
			Name = "Description",
			BackgroundTransparency = 1,
			Text = description,
			Font = Enum.Font.Gotham,
			TextSize = 10,
			TextColor3 = Color3.fromRGB(90, 80, 70),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextWrapped = true,
			Size = UDim2.new(1, -36, 0, 22),
			Position = UDim2.fromOffset(28, 22),
			ZIndex = 302,
			Parent = card
		})
	end

	local progressBg = Create("Frame", {
		BackgroundColor3 = Color3.fromRGB(190, 180, 160),
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 2),
		Position = UDim2.new(0, 0, 1, -2),
		ZIndex = 303,
		Parent = card
	})

	local progress = Create("Frame", {
		BackgroundColor3 = accentColor,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 304,
		Parent = progressBg
	})

	if nType == "option" then
		local row = Create("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, -12, 0, 18),
			Position = UDim2.new(0, 6, 1, -24),
			ZIndex = 305,
			Parent = card
		})

		Create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			Padding = UDim.new(0, 4),
			Parent = row
		})

		local function makeOpt(labelText, isYes)
			local b = Create("TextButton", {
				BackgroundColor3 = isYes and Color3.fromRGB(48, 43, 38) or Color3.fromRGB(185, 175, 155),
				BorderSizePixel = 0,
				Size = UDim2.fromOffset(22, 16),
				Text = labelText,
				Font = Enum.Font.GothamBold,
				TextSize = 11,
				TextColor3 = isYes and Color3.fromRGB(230, 220, 200) or Color3.fromRGB(40, 35, 30),
				AutoButtonColor = false,
				ZIndex = 306,
				Parent = row
			})
			b.Activated:Connect(function()
				if card.Parent then
					card:Destroy()
				end
				if callback then
					task.spawn(callback, isYes)
				end
			end)
		end

		makeOpt("×", false)
		makeOpt("✓", true)
	end

	-- click to dismiss (non-option)
	if nType ~= "option" then
		local hit = Create("TextButton", {
			BackgroundTransparency = 1,
			Text = "",
			Size = UDim2.fromScale(1, 1),
			ZIndex = 310,
			Parent = card
		})
		hit.Activated:Connect(function()
			if card.Parent then
				card:Destroy()
			end
			if callback then
				task.spawn(callback)
			end
		end)
	end

	PlaySound(ALERT_SOUND, 0.4)

	table.insert(stack, card)

	local function restack()
		local y = 16
		for i = #stack, 1, -1 do
			local c = stack[i]
			if c and c.Parent then
				local h = c.AbsoluteSize.Y
				if h < 1 then h = cardH end
				Tween(c, {
					Position = UDim2.new(1, -cardW - 12, 1, -y - h)
				}, 0.2)
				y = y + h + 6
			else
				table.remove(stack, i)
			end
		end
	end

	task.defer(function()
		if not card.Parent then return end
		restack()
		Tween(card, {
			Position = UDim2.new(1, -cardW - 12, card.Position.Y.Scale, card.Position.Y.Offset)
		}, 0.24, Enum.EasingStyle.Back)
	end)

	playNotifyGlitch(card, 0.36)

	local closed = false
	local function close()
		if closed then return end
		closed = true
		for i, c in ipairs(stack) do
			if c == card then
				table.remove(stack, i)
				break
			end
		end
		if card.Parent then
			Tween(card, {
				Position = UDim2.new(1, 20, card.Position.Y.Scale, card.Position.Y.Offset),
				BackgroundTransparency = 1
			}, 0.18)
			task.delay(0.2, function()
				if card.Parent then
					card:Destroy()
				end
				restack()
			end)
		else
			restack()
		end
	end

	card.Destroying:Connect(function()
		closed = true
		for i, c in ipairs(stack) do
			if c == card then
				table.remove(stack, i)
				break
			end
		end
		task.defer(restack)
	end)

	if duration > 0 and nType ~= "option" then
		Tween(progress, { Size = UDim2.fromScale(0, 1) }, duration, Enum.EasingStyle.Linear)
		task.delay(duration, close)
	elseif nType == "option" then
		progress.Size = UDim2.fromScale(1, 1)
	else
		progress.Visible = false
	end

	return card
end


return CoffeeIFY
