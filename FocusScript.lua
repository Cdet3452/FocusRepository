-- MainMenuController
-- Location: StarterPlayer > StarterPlayerScripts > MainMenuController

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local Lighting          = game:GetService("Lighting")

local UITheme = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UITheme"))
local T = UITheme.Get("Custom")
local C = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UIConfig"))
local M = C.MainMenu

-- ✨ IMPORTS
local PoolManager = require(ReplicatedStorage.Modules:WaitForChild("PoolManager"))
local AreaRegistry = require(ReplicatedStorage.Modules:WaitForChild("AreaRegistry"))

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainHUD   = playerGui:WaitForChild("MainHUD")
local camera    = workspace.CurrentCamera

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local AreaUpdated  = RemoteEvents:WaitForChild("AreaUpdated")

local MenuDismissed = Instance.new("BindableEvent")
MenuDismissed.Name = "MenuDismissed"
MenuDismissed.Parent = ReplicatedStorage

local MENU_ENABLED = true

if not MENU_ENABLED then
	MenuDismissed:SetAttribute("Fired", true)
	MenuDismissed:Fire()
	return
end

local FADE_IN_TIME   = M.FadeInTime or 0.8
local FADE_OUT_TIME  = M.FadeOutTime or 1.2
local IDLE_SPEED     = M.IdleSpeed or 3
local TITLE_FONT     = T.font or Enum.Font.FredokaOne
local BODY_FONT      = T.fontBody or Enum.Font.FredokaOne
local DEFAULT_AREA   = 1

local currentArea     = DEFAULT_AREA
local hasPlayed       = false
local idleConn        = nil
local areaConn        = nil

mainHUD.Enabled = false

local savedCamType    = camera.CameraType
local savedCamSubject = camera.CameraSubject

camera.CameraType = Enum.CameraType.Scriptable

local function GetMenuAnchor(area)
	return workspace:FindFirstChild("MenuCamPos_" .. area)
		or workspace:FindFirstChild("MenuCamPos_1")
		or workspace:FindFirstChild("MenuCamPos")
		or workspace:WaitForChild("MenuCamPos", 5)
end

local function SnapCameraToArea(area)
	local anchor = GetMenuAnchor(area)
	if not anchor then return end
	camera.CFrame = anchor.CFrame
end

---------------------------------------------------------------
-- ✨ PARALLAX CAMERA & MOUSE TRACKING
---------------------------------------------------------------
local targetParallaxX = 0
local targetParallaxY = 0
local currentParallaxX = 0
local currentParallaxY = 0
local PARALLAX_STRENGTH = 4 

UserInputService.InputChanged:Connect(function(input, gameProcessed)
	if hasPlayed then return end
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		local viewSize = camera.ViewportSize
		if viewSize.X > 0 and viewSize.Y > 0 then
			local pos = input.Position
			targetParallaxX = math.clamp((pos.X / viewSize.X) * 2 - 1, -1, 1)
			targetParallaxY = math.clamp((pos.Y / viewSize.Y) * 2 - 1, -1, 1)
		end
	end
end)

local function StartIdleDrift(area)
	if idleConn then idleConn:Disconnect(); idleConn = nil end

	local anchor = GetMenuAnchor(area)
	if not anchor then return end

	local baseCF = anchor.CFrame
	local basePos = baseCF.Position
	local lookTarget = basePos + baseCF.LookVector * 50
	local angle = 0

	idleConn = RunService.RenderStepped:Connect(function(dt)
		angle += dt * IDLE_SPEED
		local idleOffset = CFrame.Angles(0, math.rad(angle * 0.3), 0).LookVector * 0.5

		currentParallaxX = currentParallaxX + (targetParallaxX - currentParallaxX) * 5 * dt
		currentParallaxY = currentParallaxY + (targetParallaxY - currentParallaxY) * 5 * dt

		local pitch = math.rad(-currentParallaxY * PARALLAX_STRENGTH)
		local yaw = math.rad(-currentParallaxX * PARALLAX_STRENGTH)

		local baseLook = CFrame.lookAt(basePos + idleOffset, lookTarget)
		camera.CFrame = baseLook * CFrame.Angles(pitch, yaw, 0)
	end)
end

SnapCameraToArea(DEFAULT_AREA)
StartIdleDrift(DEFAULT_AREA)

local blackoutGui = playerGui:FindFirstChild("PreloadBlackout")
if blackoutGui then
	local blackoutFrame = blackoutGui:FindFirstChild("BlackoutFrame")
	if blackoutFrame then
		TweenService:Create(blackoutFrame, TweenInfo.new(1.0, Enum.EasingStyle.Sine), {
			BackgroundTransparency = 1
		}):Play()
	end
	task.delay(1.1, function() blackoutGui:Destroy() end)
end

---------------------------------------------------------------
-- ✨ MENU UI CONSTRUCTION
---------------------------------------------------------------
local menuScreen = Instance.new("ScreenGui")
menuScreen.Name = "MainMenu"
menuScreen.DisplayOrder = 100
menuScreen.IgnoreGuiInset = true
menuScreen.ResetOnSpawn = false
menuScreen.Parent = playerGui

-- ✨ Horizontal Vignette (Dark on left, transparent on right)
local vignette = Instance.new("Frame")
vignette.Name = "Vignette"
vignette.Size = UDim2.new(1, 0, 1, 0)
vignette.BackgroundColor3 = Color3.new(0, 0, 0)
vignette.BackgroundTransparency = 0
vignette.BorderSizePixel = 0
vignette.ZIndex = 1
vignette.Parent = menuScreen

local vigGrad = Instance.new("UIGradient")
vigGrad.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.1),
	NumberSequenceKeypoint.new(0.4, 0.8),
	NumberSequenceKeypoint.new(1, 1),
})
vigGrad.Rotation = 0 -- Left to Right
vigGrad.Parent = vignette

-- ✨ MAIN CONTAINER (Left-Aligned, Even Larger Scale)
local container = Instance.new("Frame")
container.Name = "MenuContainer"
container.Size = UDim2.new(0.9, 0, 0.8, 0)
container.Position = UDim2.new(0.08, 0, 0.5, 0) -- 8% margin from the left edge
container.AnchorPoint = Vector2.new(0, 0.5)
container.BackgroundTransparency = 1
container.ZIndex = 2
container.Parent = menuScreen

local containerConstraint = Instance.new("UISizeConstraint")
containerConstraint.MaxSize = Vector2.new(900, 900)
containerConstraint.Parent = container

local listLayout = Instance.new("UIListLayout", container)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left -- Align to left
listLayout.VerticalAlignment = Enum.VerticalAlignment.Center
listLayout.Padding = UDim.new(0, 15)

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "Title"
titleLabel.Size = UDim2.new(1, 0, 0, 120) -- Bigger Title
titleLabel.LayoutOrder = 1
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "AURA INC"
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.TextScaled = true
titleLabel.Font = TITLE_FONT
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.ZIndex = 10
titleLabel.Parent = container

local titleShadow = titleLabel:Clone()
titleShadow.Name = "TitleShadow"
titleShadow.TextColor3 = T.accentPurple
titleShadow.TextTransparency = 0.2
titleShadow.Position = UDim2.new(0, 5, 0, 5) 
titleShadow.ZIndex = 9
titleShadow.Parent = titleLabel

local titleStroke = Instance.new("UIStroke")
titleStroke.Color = T.accentPurple
titleStroke.Thickness = 4
titleStroke.Transparency = 0
titleStroke.Parent = titleLabel

local subtitleLabel = Instance.new("TextLabel")
subtitleLabel.Name = "Subtitle"
subtitleLabel.Size = UDim2.new(1, 0, 0, 45) 
subtitleLabel.LayoutOrder = 2
subtitleLabel.BackgroundTransparency = 1
subtitleLabel.Text = "Idle Aura Factory"
subtitleLabel.TextColor3 = T.subText
subtitleLabel.TextScaled = true
subtitleLabel.Font = BODY_FONT
subtitleLabel.TextXAlignment = Enum.TextXAlignment.Left
subtitleLabel.ZIndex = 10
subtitleLabel.Parent = container

local spacer = Instance.new("Frame", container)
spacer.LayoutOrder = 3
spacer.Size = UDim2.new(1, 0, 0, 15)
spacer.BackgroundTransparency = 1

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "Status"
statusLabel.Size = UDim2.new(1, 0, 0, 30) 
statusLabel.LayoutOrder = 4
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "Generating Physics Pools..."
statusLabel.TextColor3 = T.accentGold
statusLabel.TextScaled = true
statusLabel.Font = BODY_FONT
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.ZIndex = 10
statusLabel.Parent = container

-- ✨ PLAY BUTTON (Massive & Sleek)
local playBtn = Instance.new("TextButton")
playBtn.Name = "PlayButton"
playBtn.Size = UDim2.new(0, 320, 0, 90) -- Bigger Play Button
playBtn.LayoutOrder = 5
playBtn.BackgroundColor3 = T.buttonPrimary
playBtn.BorderSizePixel = 0
playBtn.Text = "PLAY"
playBtn.TextColor3 = T.headerText
playBtn.TextScaled = true
playBtn.Font = TITLE_FONT
playBtn.ZIndex = 10
playBtn.AutoButtonColor = false
playBtn.Visible = false 
playBtn.Parent = container

Instance.new("UICorner", playBtn).CornerRadius = UDim.new(0, 14)
Instance.new("UITextSizeConstraint", playBtn).MaxTextSize = 50

local playStroke = Instance.new("UIStroke")
playStroke.Color = T.accentPurple
playStroke.Thickness = 4
playStroke.Parent = playBtn

local playScale = Instance.new("UIScale", playBtn)
playScale.Scale = 0 

-- ✨ SETTINGS BUTTON (Tucked underneath)
local settingsBtn = Instance.new("TextButton")
settingsBtn.Name = "SettingsButton"
settingsBtn.Size = UDim2.new(0, 250, 0, 65) -- Bigger Settings Button
settingsBtn.LayoutOrder = 6
settingsBtn.BackgroundColor3 = T.buttonPrimary
settingsBtn.BorderSizePixel = 0
settingsBtn.Text = "SETTINGS"
settingsBtn.TextColor3 = T.headerText
settingsBtn.TextScaled = true
settingsBtn.Font = TITLE_FONT
settingsBtn.ZIndex = 10
settingsBtn.AutoButtonColor = false
settingsBtn.Visible = false 
settingsBtn.Parent = container

Instance.new("UICorner", settingsBtn).CornerRadius = UDim.new(0, 12)
Instance.new("UITextSizeConstraint", settingsBtn).MaxTextSize = 35

local setStroke = Instance.new("UIStroke")
setStroke.Color = T.accentPurple
setStroke.Thickness = 4
setStroke.Parent = settingsBtn

local setScale = Instance.new("UIScale", settingsBtn)
setScale.Scale = 0

TweenService:Create(container, TweenInfo.new(3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
	Position = container.Position - UDim2.new(0, 0, 0.02, 0)
}):Play()

-- Button Interactions
local function AddJuice(btn, scaleObj)
	local isHovering = false

	btn.MouseEnter:Connect(function()
		isHovering = true
		TweenService:Create(scaleObj, TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {Scale = 1.05}):Play()
	end)

	btn.MouseLeave:Connect(function()
		isHovering = false
		TweenService:Create(scaleObj, TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {Scale = 1.0}):Play()
	end)

	btn.MouseButton1Down:Connect(function()
		TweenService:Create(scaleObj, TweenInfo.new(0.1, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {Scale = 0.95}):Play()
		if shared.PlayUISound then shared.PlayUISound("6895079853") end
	end)

	btn.MouseButton1Up:Connect(function()
		TweenService:Create(scaleObj, TweenInfo.new(0.3, Enum.EasingStyle.Bounce), {Scale = 1.05}):Play()
	end)
end

AddJuice(playBtn, playScale)
AddJuice(settingsBtn, setScale)

task.spawn(function()
	task.wait(0.5) 
	-- ✨ Automatically applies the ShineOutline theme to our buttons!
	if UITheme and UITheme.Apply then 
		UITheme.Apply(playBtn, "ShineOutline") 
		UITheme.Apply(settingsBtn, "ShineOutline")
	end

	if UITheme and UITheme.ApplyFlair then 
		-- ✨ Apply the beautiful SlowGhost to EVERYTHING (including Play button!)
		UITheme.ApplyFlair(playBtn, "SlowGhost")
		UITheme.ApplyFlair(settingsBtn, "SlowGhost")
		UITheme.ApplyFlair(titleLabel, "SlowGhost") 
		UITheme.ApplyFlair(subtitleLabel, "SlowGhost")
	end
end)

local creditLabel = Instance.new("TextLabel")
creditLabel.Name = "Credits"
creditLabel.Size = UDim2.new(0, 200, 0, 20)
creditLabel.Position = UDim2.new(0, 15, 1, -25)
creditLabel.AnchorPoint = Vector2.new(0, 0)
creditLabel.BackgroundTransparency = 1
creditLabel.Text = "Made by MoldySugar2205"
creditLabel.TextColor3 = T.subText
creditLabel.TextTransparency = 0.3
creditLabel.TextScaled = true
creditLabel.Font = BODY_FONT
creditLabel.TextXAlignment = Enum.TextXAlignment.Left
creditLabel.ZIndex = 10
creditLabel.Parent = menuScreen

---------------------------------------------------------------
-- ✨ THEME APPLICATION LOGIC (Dynamic from AreaRegistry)
---------------------------------------------------------------
local function ApplyAreaTheme(area)
	local primaryColor = T.buttonPrimary
	local strokeColor = T.accentPurple

	pcall(function()
		local areaData = AreaRegistry.Get(area)
		if areaData then
			primaryColor = areaData.previewColor or areaData.auraHolderColor or areaData.grassColor or primaryColor
		end
	end)

	local h, s, v = Color3.toHSV(primaryColor)
	strokeColor = Color3.fromHSV(h, math.clamp(s + 0.2, 0, 1), math.clamp(v - 0.45, 0, 1))

	titleStroke.Color = primaryColor
	titleShadow.TextColor3 = strokeColor
	statusLabel.TextColor3 = primaryColor

	playBtn.BackgroundColor3 = primaryColor
	playStroke.Color = strokeColor

	settingsBtn.BackgroundColor3 = primaryColor
	setStroke.Color = strokeColor
end

ApplyAreaTheme(player:GetAttribute("CurrentArea") or DEFAULT_AREA)

areaConn = AreaUpdated.OnClientEvent:Connect(function(info)
	if hasPlayed then return end
	local area = info.currentArea or DEFAULT_AREA
	if area ~= currentArea then
		currentArea = area
		SnapCameraToArea(area)
		StartIdleDrift(area)
		ApplyAreaTheme(area) 
	end
end)

---------------------------------------------------------------
-- ✨ PRE-GAME SETTINGS MENU (Middle of Screen)
---------------------------------------------------------------
local settingsOverlay = Instance.new("Frame")
settingsOverlay.Size = UDim2.new(1, 0, 1, 0)
settingsOverlay.BackgroundColor3 = Color3.new(0,0,0)
settingsOverlay.BackgroundTransparency = 1
settingsOverlay.Visible = false
settingsOverlay.ZIndex = 20
settingsOverlay.Parent = menuScreen

local settingsPanel = Instance.new("Frame")
settingsPanel.Size = UDim2.new(0, 350, 0, 380)
settingsPanel.Position = UDim2.new(0.5, 0, 0.5, 0)
settingsPanel.AnchorPoint = Vector2.new(0.5, 0.5)
settingsPanel.BackgroundColor3 = T.panelBG
settingsPanel.BorderSizePixel = 0
settingsPanel.ZIndex = 21
settingsPanel.Parent = settingsOverlay
Instance.new("UICorner", settingsPanel).CornerRadius = UDim.new(0, 12)
local pStroke = Instance.new("UIStroke", settingsPanel); pStroke.Color = T.panelStroke; pStroke.Thickness = 2

local sHeader = Instance.new("Frame", settingsPanel); sHeader.Size = UDim2.new(1, 0, 0, 45); sHeader.BackgroundColor3 = T.headerBG; sHeader.BorderSizePixel = 0; sHeader.ZIndex = 22; Instance.new("UICorner", sHeader).CornerRadius = UDim.new(0, 12)
local sTitle = Instance.new("TextLabel", sHeader); sTitle.Size = UDim2.new(1, -20, 1, 0); sTitle.Position = UDim2.new(0, 15, 0, 0); sTitle.BackgroundTransparency = 1; sTitle.Text = "SETTINGS"; sTitle.TextColor3 = T.headerText; sTitle.TextScaled = true; sTitle.Font = TITLE_FONT; sTitle.TextXAlignment = Enum.TextXAlignment.Left; sTitle.ZIndex = 23
local sClose = Instance.new("TextButton", sHeader); sClose.Size = UDim2.new(0, 30, 0, 30); sClose.Position = UDim2.new(1, -40, 0.5, -15); sClose.BackgroundColor3 = T.buttonRed; sClose.Text = "X"; sClose.TextColor3 = Color3.fromRGB(255,255,255); sClose.TextScaled = true; sClose.Font = TITLE_FONT; sClose.ZIndex = 23; Instance.new("UICorner", sClose).CornerRadius = UDim.new(0, 6)

local sList = Instance.new("Frame", settingsPanel); sList.Size = UDim2.new(1, -20, 1, -60); sList.Position = UDim2.new(0, 10, 0, 55); sList.BackgroundTransparency = 1; sList.ZIndex = 22
local slistLayout = Instance.new("UIListLayout", sList); slistLayout.Padding = UDim.new(0, 10); slistLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

local function MakeSelectorRow(label, options, defaultIndex, onChange)
	local row = Instance.new("Frame", sList); row.Size = UDim2.new(1, 0, 0, 45); row.BackgroundColor3 = T.cardBG; row.BorderSizePixel = 0; row.ZIndex = 23; Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)
	local lbl = Instance.new("TextLabel", row); lbl.Size = UDim2.new(0.5, 0, 1, 0); lbl.Position = UDim2.new(0, 10, 0, 0); lbl.BackgroundTransparency = 1; lbl.Text = label; lbl.TextColor3 = T.bodyText; lbl.TextScaled = true; lbl.Font = BODY_FONT; lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.ZIndex = 24

	local valLbl = Instance.new("TextLabel", row); valLbl.Size = UDim2.new(0.3, 0, 0.6, 0); valLbl.Position = UDim2.new(0.6, 0, 0.2, 0); valLbl.BackgroundTransparency = 1; valLbl.Text = options[defaultIndex]; valLbl.TextColor3 = T.accentGold; valLbl.TextScaled = true; valLbl.Font = BODY_FONT; valLbl.ZIndex = 24

	local leftBtn = Instance.new("TextButton", row); leftBtn.Size = UDim2.new(0, 25, 0, 25); leftBtn.Position = UDim2.new(0.55, 0, 0.5, -12.5); leftBtn.BackgroundColor3 = T.buttonSecondary; leftBtn.Text = "<"; leftBtn.TextColor3 = T.bodyText; leftBtn.Font = TITLE_FONT; leftBtn.TextScaled = true; leftBtn.ZIndex = 24; Instance.new("UICorner", leftBtn).CornerRadius = UDim.new(0, 6)
	local rightBtn = Instance.new("TextButton", row); rightBtn.Size = UDim2.new(0, 25, 0, 25); rightBtn.Position = UDim2.new(0.9, 0, 0.5, -12.5); rightBtn.BackgroundColor3 = T.buttonSecondary; rightBtn.Text = ">"; rightBtn.TextColor3 = T.bodyText; rightBtn.Font = TITLE_FONT; rightBtn.TextScaled = true; rightBtn.ZIndex = 24; Instance.new("UICorner", rightBtn).CornerRadius = UDim.new(0, 6)

	local currentIndex = defaultIndex
	local function UpdateOpt(dir)
		if shared.PlayUISound then shared.PlayUISound("6895079853") end
		currentIndex = currentIndex + dir
		if currentIndex < 1 then currentIndex = #options end
		if currentIndex > #options then currentIndex = 1 end
		valLbl.Text = options[currentIndex]
		if onChange then onChange(options[currentIndex]) end
	end

	leftBtn.MouseButton1Click:Connect(function() UpdateOpt(-1) end)
	rightBtn.MouseButton1Click:Connect(function() UpdateOpt(1) end)
end

local vols = {"0%", "25%", "50%", "75%", "100%"}
MakeSelectorRow("Music", vols, 5, function(val) print("Music set to", val) end) 
MakeSelectorRow("SFX", vols, 5, function(val) print("SFX set to", val) end)

MakeSelectorRow("Quality", {"Low", "Medium", "High"}, 3, function(val) 
	if val == "Low" then Lighting.GlobalShadows = false else Lighting.GlobalShadows = true end
end)

MakeSelectorRow("Language", {"Auto", "English", "Español", "Français"}, 1, function(val)
	print("Language preference changed to", val)
end)

local panelScale = Instance.new("UIScale", settingsPanel); panelScale.Scale = 0
settingsBtn.MouseButton1Click:Connect(function()
	if shared.PlayUISound then shared.PlayUISound("6895079853") end
	settingsOverlay.Visible = true
	TweenService:Create(settingsOverlay, TweenInfo.new(0.3), {BackgroundTransparency = 0.5}):Play()
	TweenService:Create(panelScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
end)

sClose.MouseButton1Click:Connect(function()
	if shared.PlayUISound then shared.PlayUISound("6895079853") end
	TweenService:Create(settingsOverlay, TweenInfo.new(0.3), {BackgroundTransparency = 1}):Play()
	local tOut = TweenService:Create(panelScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In), {Scale = 0})
	tOut:Play()
	tOut.Completed:Once(function() settingsOverlay.Visible = false end)
end)

---------------------------------------------------------------
-- LOADING SCREEN FADE
---------------------------------------------------------------
local blackFade = Instance.new("Frame")
blackFade.Name = "BlackFade"
blackFade.Size = UDim2.new(1, 0, 1, 0)
blackFade.BackgroundColor3 = Color3.new(0, 0, 0)
blackFade.BackgroundTransparency = 1
blackFade.BorderSizePixel = 0
blackFade.ZIndex = 50
blackFade.Parent = menuScreen

local loadingText = Instance.new("TextLabel")
loadingText.Name = "LoadingText"
loadingText.Size = UDim2.new(1, 0, 0, 50)
loadingText.Position = UDim2.new(0, 0, 0.5, -25)
loadingText.BackgroundTransparency = 1
loadingText.Text = "INITIALIZING SYSTEMS..."
loadingText.TextColor3 = T.accentBlue or Color3.fromRGB(100, 200, 255)
loadingText.TextScaled = true
loadingText.Font = TITLE_FONT
loadingText.TextTransparency = 1
loadingText.ZIndex = 51
loadingText.Parent = blackFade

---------------------------------------------------------------
-- PLAY BUTTON CLICK
---------------------------------------------------------------
playBtn.MouseButton1Down:Connect(function()
	if hasPlayed then return end
	hasPlayed = true

	playBtn.Active = false
	settingsBtn.Active = false

	if areaConn then areaConn:Disconnect(); areaConn = nil end

	TweenService:Create(blackFade, TweenInfo.new(FADE_IN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0
	}):Play()
	TweenService:Create(loadingText, TweenInfo.new(FADE_IN_TIME), {
		TextTransparency = 0
	}):Play()
	task.wait(FADE_IN_TIME)

	if idleConn then idleConn:Disconnect(); idleConn = nil end

	camera.CameraType = savedCamType
	local character = player.Character or player.CharacterAdded:Wait()
	local humanoid = character:WaitForChild("Humanoid", 5)
	if humanoid then
		camera.CameraSubject = humanoid
	end

	mainHUD.Enabled = true

	vignette:Destroy()
	container:Destroy()
	settingsOverlay:Destroy()

	if not game:IsLoaded() then game.Loaded:Wait() end
	loadingText.Text = "LOADING AURAS..."
	task.wait(2) 

	TweenService:Create(blackFade, TweenInfo.new(FADE_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1
	}):Play()
	TweenService:Create(loadingText, TweenInfo.new(FADE_OUT_TIME), {
		TextTransparency = 1
	}):Play()
	task.wait(FADE_OUT_TIME)

	MenuDismissed:SetAttribute("Fired", true)
	MenuDismissed:Fire()

	menuScreen:Destroy()
end)

---------------------------------------------------------------
-- ✨ TRUE BACKGROUND LOADING (POOL CREATION) ✨
---------------------------------------------------------------
task.spawn(function()
	if not game:IsLoaded() then game.Loaded:Wait() end

	local playerArea = player:GetAttribute("CurrentArea") or DEFAULT_AREA
	statusLabel.Text = "Optimizing Physics (Area " .. playerArea .. ")..."

	task.wait(0.2)

	PoolManager.InitializeArea(playerArea)

	statusLabel.Text = "Ready!"
	task.wait(0.3)

	statusLabel.Visible = false

	playBtn.Visible = true
	settingsBtn.Visible = true

	TweenService:Create(playScale, TweenInfo.new(0.6, Enum.EasingStyle.Bounce), {Scale = 1}):Play()
	task.wait(0.15)
	TweenService:Create(setScale, TweenInfo.new(0.6, Enum.EasingStyle.Bounce), {Scale = 1}):Play()
end)



-- ShopController
-- Location: StarterPlayer > StarterPlayerScripts > ShopController

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local UpgradeConfig     = require(ReplicatedStorage.Modules.UpgradeConfig)
local Formatter         = require(ReplicatedStorage.Modules.NumberFormatter)
local EpicUpgradeConfig = require(ReplicatedStorage.Modules.EpicUpgradeConfig)
local UITheme           = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UITheme"))
local T                 = UITheme.Get("Custom")
local SoundConfig       = require(ReplicatedStorage.Modules.SoundConfig)

local RemoteEvents        = ReplicatedStorage:WaitForChild("RemoteEvents")
local PurchaseUpgrade     = RemoteEvents:WaitForChild("PurchaseUpgrade", 15)
local UpgradeUpdated      = RemoteEvents:WaitForChild("UpgradeUpdated", 15)
local PurchaseEpicUpgrade = RemoteEvents:WaitForChild("PurchaseEpicUpgrade", 15)
local EpicUpgradeUpdated  = RemoteEvents:WaitForChild("EpicUpgradeUpdated", 15)

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainHUD   = playerGui:WaitForChild("MainHUD")

local upgradeState      = {}
local epicUpgradeState  = {}
local currentCurrency   = 0
local liveGoldenAuras   = 0
local shopOpen          = false
local activeMainTab     = "Upgrades"
local regularCardRefs   = {}
local epicCardRefs      = {}
local isLoadingData     = true
local globalHoldActive  = false  
local globalHoldGeneration = 0    

-- FORWARD DECLARATIONS
local UpdateLockedTierProgress = nil
local RebuildRegularShop = nil 

-- ─────────────────────────────────────────────────────────────────────────────
-- INITIALIZATION
-- ─────────────────────────────────────────────────────────────────────────────
for _, tierData in ipairs(UpgradeConfig.Tiers) do
	for upgradeId, cfg in pairs(tierData.upgrades) do
		upgradeState[upgradeId] = {
			level    = 0,
			maxLevel = cfg.maxLevel,
			cost     = UpgradeConfig.CalculateCost(upgradeId, 0),
			maxed    = false,
		}
	end
end

for _, tierData in ipairs(EpicUpgradeConfig.Tiers) do
	for upgradeId, cfg in pairs(tierData.upgrades) do
		epicUpgradeState[upgradeId] = {
			level    = 0,
			maxLevel = cfg.maxLevel,
			cost     = EpicUpgradeConfig.CalculateCost(upgradeId, 0),
			maxed    = false,
		}
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- VFX / SOUND HELPERS
-- ─────────────────────────────────────────────────────────────────────────────
local function PlayUIBurst(targetElement, amount, colorTheme)
	if not shopOpen then return end
	local burstGui = Instance.new("ScreenGui")
	burstGui.Name   = "JuiceBurst"
	burstGui.Parent = playerGui

	local absPos  = targetElement.AbsolutePosition
	local absSize = targetElement.AbsoluteSize
	local center  = absPos + (absSize / 2)

	for i = 1, amount do
		local particle = Instance.new("Frame")
		particle.BackgroundColor3 = colorTheme or Color3.fromRGB(255, 215, 0)
		particle.BorderSizePixel  = 0
		particle.Size             = UDim2.new(0, math.random(6, 12), 0, math.random(6, 12))
		particle.Position         = UDim2.new(0, center.X, 0, center.Y)
		particle.Rotation         = math.random(0, 360)

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent       = particle
		particle.Parent     = burstGui

		local angle    = math.rad(math.random(0, 360))
		local distance = math.random(50, 150)
		local endPos   = UDim2.new(0, center.X + math.cos(angle) * distance, 0, center.Y + math.sin(angle) * distance + 50)

		local tInfo = TweenInfo.new(math.random(4, 7) / 10, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out)
		TweenService:Create(particle, tInfo, {
			Position             = endPos,
			Size                 = UDim2.new(0, 0, 0, 0),
			Rotation             = particle.Rotation + math.random(-180, 180),
			BackgroundTransparency = 1,
		}):Play()
	end

	task.delay(1, function() burstGui:Destroy() end)
end

local comboPitch  = 1.0
local lastBuyTime = tick()

local function PlayPurchaseSound()
	if tick() - lastBuyTime < 0.3 then
		comboPitch = math.min(comboPitch + 0.05, 2.5)
	else
		comboPitch = 1.0
	end
	lastBuyTime = tick()

	local sfxFolder = ReplicatedStorage:FindFirstChild("SFX") or ReplicatedStorage:FindFirstChild("Sounds")
	if sfxFolder and sfxFolder:FindFirstChild("BuyPing") then
		local sfx = sfxFolder.BuyPing:Clone()
		sfx.PlaybackSpeed = comboPitch
		sfx.Parent        = game:GetService("SoundService")
		sfx:Play()
		game.Debris:AddItem(sfx, 2)
	end
end

local function PlayFeedbackSound(soundName, volume)
	local sfxFolder = ReplicatedStorage:FindFirstChild("SFX") or ReplicatedStorage:FindFirstChild("Sounds")
	if sfxFolder then
		local s = sfxFolder:FindFirstChild(soundName)
		if s then
			local sfx = s:Clone()
			sfx.Volume = volume or 0.5
			sfx.Parent = game:GetService("SoundService")
			sfx:Play()
			game.Debris:AddItem(sfx, 3)
			return
		end
	end
end

local lastErrorTime = tick()

local function PlayErrorFeedback(targetButton)
	if tick() - lastErrorTime < 0.25 then return end
	lastErrorTime = tick()

	local sfxFolder = ReplicatedStorage:FindFirstChild("Sounds") or ReplicatedStorage:FindFirstChild("SFX")
	if sfxFolder and sfxFolder:FindFirstChild("ErrorBuzz") then
		local sfx = sfxFolder.ErrorBuzz:Clone()
		sfx.Volume = 0.5
		sfx.Parent = workspace
		sfx:Play()
		game.Debris:AddItem(sfx, 2)
	end

	if targetButton and targetButton.Parent then
		local origPos    = targetButton.Position
		local wobbleInfo = TweenInfo.new(0.04, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 3, true)
		TweenService:Create(targetButton, wobbleInfo, {
			Position = origPos + UDim2.new(0, 4, 0, 0)
		}):Play()
	end
end

local function FormatNumber(n) return Formatter.Format(n) end
local function PlayUI(id) if shared.PlayUISound then shared.PlayUISound(id) end end

-- ─────────────────────────────────────────────────────────────────────────────
-- ✨ SHOP BUTTON (Moved to Left Sidebar)
-- ─────────────────────────────────────────────────────────────────────────────
local ShopButton = Instance.new("ImageButton")
ShopButton.Name              = "ShopButton"
ShopButton.BackgroundColor3  = T.buttonSecondary
ShopButton.BorderSizePixel   = 0
ShopButton.AutoButtonColor   = false
ShopButton.ZIndex            = 15

local Faded2 = mainHUD:FindFirstChild("Faded2")
if Faded2 then
	ShopButton.Parent = Faded2
	ShopButton.Size = UDim2.new(0.85, 0, 0.85, 0)
	local aspect = Instance.new("UIAspectRatioConstraint", ShopButton)
	aspect.AspectRatio = 1.0

	-- Ensure Faded2 cleanly stacks the Shop button beneath the Achievement button
	local layout = Faded2:FindFirstChildOfClass("UIListLayout")
	if not layout then
		layout = Instance.new("UIListLayout", Faded2)
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.Padding = UDim.new(0, 15)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
	end
	ShopButton.LayoutOrder = 2 
else
	-- Fallback if Faded2 is missing
	ShopButton.Size = UDim2.new(0, 60, 0, 60)
	ShopButton.AnchorPoint = Vector2.new(0, 0.5)
	ShopButton.Position = UDim2.new(0, 15, 0.5, 0)
	ShopButton.Parent = mainHUD
end

CollectionService:AddTag(ShopButton, "Tutorial_ShopButton")
Instance.new("UICorner", ShopButton).CornerRadius = UDim.new(0.5, 0)

local shopStroke = Instance.new("UIStroke", ShopButton)
shopStroke.Color     = T.accentGold
shopStroke.Thickness = 2

local shopIcon = Instance.new("ImageLabel", ShopButton)
shopIcon.Size               = UDim2.new(0.6, 0, 0.6, 0)
shopIcon.Position           = UDim2.new(0.2, 0, 0.2, 0)
shopIcon.BackgroundTransparency = 1
shopIcon.ScaleType          = Enum.ScaleType.Fit
shopIcon.Image              = "rbxassetid://14916846070"

-- ─────────────────────────────────────────────────────────────────────────────
-- ✨ SHOP PANEL (Left Slide-out format)
-- ─────────────────────────────────────────────────────────────────────────────
local PANEL_MAX_W = 420; local PANEL_MAX_H = 800; local HEADER_H = 42

local ShopPanel = Instance.new("Frame")
ShopPanel.Name              = "ShopPanel"
ShopPanel.Size              = UDim2.new(0.85, 0, 0.88, 0) 
ShopPanel.AnchorPoint       = Vector2.new(0, 0.5) 
ShopPanel.Position          = UDim2.new(0, -500, 0.5, 0) -- Hidden to the left initially
ShopPanel.BackgroundColor3  = T.panelBG
ShopPanel.BorderSizePixel   = 0
ShopPanel.Visible           = false
ShopPanel.ZIndex            = 10
ShopPanel.ClipsDescendants  = true
ShopPanel.Parent            = mainHUD
CollectionService:AddTag(ShopPanel, "Tutorial_ShopPanel") 
Instance.new("UICorner", ShopPanel).CornerRadius = UDim.new(0, 10)

local sizeConstraint = Instance.new("UISizeConstraint")
sizeConstraint.MaxSize = Vector2.new(PANEL_MAX_W, PANEL_MAX_H)
sizeConstraint.Parent  = ShopPanel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color     = T.panelStroke
panelStroke.Thickness = 2
panelStroke.Parent    = ShopPanel

local TitleBar = Instance.new("Frame")
TitleBar.Name                 = "TitleBar"
TitleBar.Size                 = UDim2.new(1, 0, 0, HEADER_H)
TitleBar.BackgroundColor3     = T.headerBG
TitleBar.BorderSizePixel      = 0
TitleBar.ZIndex               = 11
TitleBar.ClipsDescendants     = true
TitleBar.BackgroundTransparency = 1
TitleBar.Parent               = ShopPanel
Instance.new("UICorner", TitleBar).CornerRadius = UDim.new(0, 10)

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size               = UDim2.new(1, -50, 1, 0)
TitleLabel.Position           = UDim2.new(0, 15, 0, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Text               = "RESEARCH"
TitleLabel.TextColor3         = T.headerText
TitleLabel.TextScaled         = true
TitleLabel.Font               = T.font
TitleLabel.TextXAlignment     = Enum.TextXAlignment.Left
TitleLabel.ZIndex             = 12
TitleLabel.Parent             = TitleBar

local CloseButton = Instance.new("TextButton")
CloseButton.Size             = UDim2.new(0, 30, 0, 30)
CloseButton.Position         = UDim2.new(1, -35, 0, 6)
CloseButton.BackgroundColor3 = T.buttonRed
CloseButton.BorderSizePixel  = 0
CloseButton.Text             = "X"
CloseButton.TextColor3       = T.bodyText
CloseButton.TextScaled       = true
CloseButton.Font             = T.font
CloseButton.ZIndex           = 9999
CloseButton.Parent           = TitleBar
CollectionService:AddTag(CloseButton, "Tutorial_ShopCloseBtn") 
Instance.new("UICorner", CloseButton).CornerRadius = UDim.new(0, 6)

-- ─────────────────────────────────────────────────────────────────────────────
-- INFO POPUP
-- ─────────────────────────────────────────────────────────────────────────────
local InfoPopup = Instance.new("Frame")
InfoPopup.Name                 = "InfoPopup"
InfoPopup.Size                 = UDim2.new(0.85, 0, 0.6, 0)
InfoPopup.Position             = UDim2.new(0.5, 0, 0.5, 0)
InfoPopup.AnchorPoint          = Vector2.new(0.5, 0.5)
InfoPopup.BackgroundColor3     = T.cardBG
InfoPopup.BackgroundTransparency = 0
InfoPopup.ZIndex               = 50
InfoPopup.Visible              = false
InfoPopup.Parent               = ShopPanel
Instance.new("UICorner", InfoPopup).CornerRadius = UDim.new(0, 12)

local AspectConstraint = Instance.new("UIAspectRatioConstraint", InfoPopup)
AspectConstraint.AspectRatio = 1.0
local InfoScale = Instance.new("UIScale", InfoPopup)
InfoScale.Scale = 1

local InfoTitle = Instance.new("TextLabel", InfoPopup)
InfoTitle.Size                 = UDim2.new(1, -20, 0, 35)
InfoTitle.Position             = UDim2.new(0, 10, 0, 10)
InfoTitle.BackgroundTransparency = 1
InfoTitle.Text                 = ""
InfoTitle.TextColor3           = T.headerText
InfoTitle.TextScaled           = true
InfoTitle.Font                 = Enum.Font.GothamBold
InfoTitle.ZIndex               = 51

local InfoDesc = Instance.new("TextLabel", InfoPopup)
InfoDesc.Size                  = UDim2.new(1, -20, 1, -110)
InfoDesc.Position              = UDim2.new(0, 10, 0, 55)
InfoDesc.BackgroundTransparency = 1
InfoDesc.Text                  = ""
InfoDesc.TextColor3            = T.bodyText
InfoDesc.TextWrapped           = true
InfoDesc.TextScaled            = true
InfoDesc.Font                  = T.font
InfoDesc.TextYAlignment        = Enum.TextYAlignment.Top
InfoDesc.ZIndex                = 51

local InfoClose = Instance.new("TextButton", InfoPopup)
InfoClose.Size             = UDim2.new(0.6, 0, 0, 40)
InfoClose.Position         = UDim2.new(0.2, 0, 1, -50)
InfoClose.BackgroundColor3 = T.buttonPrimary
InfoClose.BorderSizePixel  = 0
InfoClose.Text             = "Close"
InfoClose.TextColor3       = T.headerText
InfoClose.TextScaled       = true
InfoClose.Font             = T.font
InfoClose.ZIndex           = 51
Instance.new("UICorner", InfoClose).CornerRadius = UDim.new(0, 8)

local function ShowInfo(title, desc)
	if shared.PlayUISound then shared.PlayUISound(SoundConfig.UIClick or "") end
	InfoTitle.Text = title
	InfoDesc.Text  = desc
	InfoPopup.BackgroundTransparency = 0
	InfoScale.Scale  = 0.5
	InfoPopup.Visible = true
	TweenService:Create(InfoScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

InfoClose.MouseButton1Down:Connect(function()
	if shared.PlayUISound then shared.PlayUISound(SoundConfig.UIClick or "") end
	local tween = TweenService:Create(InfoScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0.5 })
	tween:Play()
	tween.Completed:Once(function() InfoPopup.Visible = false end)
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- MAIN TAB BAR
-- ─────────────────────────────────────────────────────────────────────────────
local activeShopTabText = "Regular Upgrades"

local MainTabBar = Instance.new("Frame")
MainTabBar.Size                 = UDim2.new(1, -20, 0, 85)
MainTabBar.Position             = UDim2.new(0, 10, 0, HEADER_H + 4)
MainTabBar.BackgroundTransparency = 1
MainTabBar.ZIndex               = 11
MainTabBar.Parent               = ShopPanel

local ShopHoverLabel = Instance.new("TextLabel", MainTabBar)
ShopHoverLabel.Size                 = UDim2.new(1, 0, 0, 20)
ShopHoverLabel.Position             = UDim2.new(0, 0, 0, 0)
ShopHoverLabel.BackgroundTransparency = 1
ShopHoverLabel.TextColor3           = T.bodyText
ShopHoverLabel.TextScaled           = true
ShopHoverLabel.Font                 = T.font
ShopHoverLabel.Text                 = activeShopTabText

local TabBtnFrame = Instance.new("Frame", MainTabBar)
TabBtnFrame.Size                 = UDim2.new(1, 0, 1, -25)
TabBtnFrame.Position             = UDim2.new(0, 0, 0, 25)
TabBtnFrame.BackgroundTransparency = 1

local TabListLayout = Instance.new("UIListLayout", TabBtnFrame)
TabListLayout.FillDirection       = Enum.FillDirection.Horizontal
TabListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
TabListLayout.VerticalAlignment   = Enum.VerticalAlignment.Center
TabListLayout.Padding             = UDim.new(0, 25)

local TAB_COLOR_BASE   = T.buttonSecondary
local TAB_COLOR_HOVER  = T.buttonPrimary
local TAB_COLOR_ACTIVE = T.accentGold

local mainTabButtons = {}

local function MakeMainTab(name, hoverText, iconId)
	local btn = Instance.new("ImageButton", TabBtnFrame)
	btn.Name             = "MainTab_" .. name
	btn.Size             = UDim2.new(0, 48, 0, 48)
	btn.BackgroundColor3 = TAB_COLOR_BASE
	btn.AutoButtonColor  = false
	btn.ZIndex           = 12
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0.5, 0)

	local stroke = Instance.new("UIStroke", btn)
	stroke.Color     = T.panelStroke
	stroke.Thickness = 2

	local icon = Instance.new("ImageLabel", btn)
	icon.Size               = UDim2.new(0.6, 0, 0.6, 0)
	icon.Position           = UDim2.new(0.2, 0, 0.2, 0)
	icon.BackgroundTransparency = 1
	icon.ScaleType          = Enum.ScaleType.Fit
	icon.Image              = iconId

	btn.MouseEnter:Connect(function()
		ShopHoverLabel.Text = hoverText
		if activeMainTab ~= name then btn.BackgroundColor3 = TAB_COLOR_HOVER end
	end)
	btn.MouseLeave:Connect(function()
		ShopHoverLabel.Text = activeShopTabText
		if activeMainTab ~= name then btn.BackgroundColor3 = TAB_COLOR_BASE end
	end)

	mainTabButtons[name] = { btn = btn, stroke = stroke }
	return btn
end

local tabEpic     = MakeMainTab("Epic",     "Epic Research",     "rbxassetid://14916846070")
local tabUpgrades = MakeMainTab("Upgrades", "Regular Upgrades",  "rbxassetid://14916846070")

-- ─────────────────────────────────────────────────────────────────────────────
-- CURRENCY LABEL
-- ─────────────────────────────────────────────────────────────────────────────
local CURRENCY_H = 0
local CurrencyLabel = Instance.new("TextLabel")
CurrencyLabel.Name              = "ShopCurrencyLabel"
CurrencyLabel.Size              = UDim2.new(1, -24, 0, CURRENCY_H)
CurrencyLabel.BackgroundTransparency = 1
CurrencyLabel.Text              = "$0"
CurrencyLabel.TextColor3        = T.currencyColor
CurrencyLabel.TextScaled        = true
CurrencyLabel.Font              = T.font
CurrencyLabel.TextXAlignment    = Enum.TextXAlignment.Right
CurrencyLabel.ZIndex            = 11
CurrencyLabel.Parent            = ShopPanel

-- ─────────────────────────────────────────────────────────────────────────────
-- SCROLL FRAMES
-- ─────────────────────────────────────────────────────────────────────────────
local function MakeScroll(name, yTop)
	local sf = Instance.new("ScrollingFrame")
	sf.Name                 = name
	sf.Size                 = UDim2.new(1, -20, 1, -(yTop + 10))
	sf.Position             = UDim2.new(0, 10, 0, yTop)
	sf.BackgroundTransparency = 1
	sf.BorderSizePixel      = 0
	sf.ScrollBarThickness   = 4
	sf.ScrollBarImageColor3 = T.subText
	sf.CanvasSize           = UDim2.new(0, 0, 0, 0)
	sf.ZIndex               = 11
	sf.Visible              = false
	sf.ClipsDescendants     = true
	sf.Parent               = ShopPanel

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.Parent  = sf
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		sf.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 10)
	end)
	return sf
end

local REGULAR_SCROLL_TOP = HEADER_H + 95
local RegularScroll      = MakeScroll("RegularScroll", REGULAR_SCROLL_TOP)
local EPIC_SCROLL_TOP    = HEADER_H + 95
local EpicScroll         = MakeScroll("EpicScroll", EPIC_SCROLL_TOP)

-- ─────────────────────────────────────────────────────────────────────────────
-- CARD BUILDER
-- ─────────────────────────────────────────────────────────────────────────────
local function BuildCard(parent, upgradeId, cfg, isEpic, cardRefsTable)
	local card = Instance.new("Frame")
	card.Name             = "Card_" .. upgradeId
	card.Size             = UDim2.new(1, 0, 0, 100)
	card.BackgroundColor3 = T.cardBG
	card.BorderSizePixel  = 0
	card.Parent           = parent
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)

	local icon = Instance.new("ImageLabel", card)
	icon.Size               = UDim2.new(0, 50, 0, 50)
	icon.Position           = UDim2.new(0, 15, 0.5, -25)
	icon.BackgroundTransparency = 1
	icon.Image              = cfg.iconId or "rbxassetid://0"

	local infoBtn = Instance.new("TextButton", card)
	infoBtn.Size             = UDim2.new(0, 22, 0, 22)
	infoBtn.Position         = UDim2.new(0, 75, 0, 12)
	infoBtn.BackgroundColor3 = T.buttonSecondary
	infoBtn.Text             = "i"
	infoBtn.TextColor3       = T.bodyText
	infoBtn.Font             = Enum.Font.GothamBlack
	infoBtn.TextSize         = 14
	Instance.new("UICorner", infoBtn).CornerRadius = UDim.new(1, 0)
	infoBtn.MouseButton1Click:Connect(function() ShowInfo(cfg.displayName, cfg.description) end)

	local nameLabel = Instance.new("TextLabel", card)
	nameLabel.Size              = UDim2.new(0.74, -120, 0, 24)
	nameLabel.Position          = UDim2.new(0, 102, 0, 11)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text              = string.upper(cfg.displayName)
	nameLabel.TextColor3        = T.bodyText
	nameLabel.TextScaled        = true
	nameLabel.Font              = Enum.Font.FredokaOne
	nameLabel.TextXAlignment    = Enum.TextXAlignment.Left

	local descLabel = Instance.new("TextLabel", card)
	descLabel.Size              = UDim2.new(0.74, -95, 0, 36)
	descLabel.Position          = UDim2.new(0, 75, 0, 38)
	descLabel.BackgroundTransparency = 1
	descLabel.Text              = cfg.description
	descLabel.TextColor3        = T.subText
	descLabel.TextWrapped       = true
	descLabel.TextSize          = 16
	descLabel.Font              = Enum.Font.GothamMedium
	descLabel.TextXAlignment    = Enum.TextXAlignment.Left
	descLabel.TextYAlignment    = Enum.TextYAlignment.Top

	local levelLabel = Instance.new("TextLabel", card)
	levelLabel.Size             = UDim2.new(0.74, -95, 0, 18)
	levelLabel.Position         = UDim2.new(0, 75, 0, 76)
	levelLabel.BackgroundTransparency = 1
	levelLabel.Text             = "Lv. 0 / " .. cfg.maxLevel
	levelLabel.TextColor3       = T.accentGreen
	levelLabel.TextSize         = 16
	levelLabel.Font             = Enum.Font.FredokaOne
	levelLabel.TextXAlignment   = Enum.TextXAlignment.Left

	local buyButton = Instance.new("TextButton", card)
	buyButton.Name             = "PurchaseButton"
	buyButton.Size             = UDim2.new(0.24, 0, 0, 46)
	buyButton.AnchorPoint      = Vector2.new(1, 0.5)
	buyButton.Position         = UDim2.new(1, -12, 0.5, 0)
	buyButton.BackgroundColor3 = isEpic and T.accentPurple or T.buttonGreen
	buyButton.BorderSizePixel  = 0
	buyButton.TextColor3       = T.bodyText
	buyButton.TextScaled       = true
	buyButton.Font             = Enum.Font.FredokaOne
	CollectionService:AddTag(buyButton, "Tutorial_Buy_" .. upgradeId) 
	Instance.new("UICorner", buyButton).CornerRadius = UDim.new(0, 8)

	cardRefsTable[upgradeId] = {
		frame      = card,
		levelLabel = levelLabel,
		buyButton  = buyButton,
		isEpic     = isEpic,
		tab        = cfg.category,
	}

	local holdingBuy    = false
	local buyGeneration = 0

	local function StopAllOtherHolds(myGen)
		if globalHoldGeneration ~= myGen then
			globalHoldGeneration = myGen
		end
	end

	local function TryBuy()
		if isLoadingData then return false end

		if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_BuyUpgrade") then return false end

		if isEpic then
			local state = epicUpgradeState[upgradeId]
			if not state or state.maxed then return false end

			local currentAuras = player:GetAttribute("LiveGoldenAuras") or 0
			local currentAuraSpend = player:GetAttribute("LocalAuraSpend") or 0
			local actualAuras = currentAuras - currentAuraSpend

			if actualAuras < state.cost then PlayErrorFeedback(buyButton); return false end

			local wasMaxedLocally = state.maxed
			player:SetAttribute("LocalAuraSpend", currentAuraSpend + state.cost)

			state.level += 1
			state.maxed  = (state.level >= state.maxLevel)
			state.cost   = state.maxed and 0 or EpicUpgradeConfig.CalculateCost(upgradeId, state.level)

			if state.maxed and not wasMaxedLocally then
				PlayFeedbackSound("MaxOut", 0.6); PlayUIBurst(buyButton, 20)
			else
				PlayPurchaseSound()
			end
			UpdateEpicCard(upgradeId)
			PurchaseEpicUpgrade:FireServer(upgradeId)

			if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
			return true
		else
			local state = upgradeState[upgradeId]
			if not state or state.maxed then return false end

			local currentCash = player:GetAttribute("LiveCurrency") or 0
			local currentSpend = player:GetAttribute("LocalSpend") or 0
			local actualCash = currentCash - currentSpend

			if actualCash < state.cost then PlayErrorFeedback(buyButton); return false end

			local wasMaxedLocally = state.maxed
			player:SetAttribute("LocalSpend", currentSpend + state.cost)

			state.level += 1
			state.maxed  = (state.level >= state.maxLevel)
			state.cost   = state.maxed and 0 or UpgradeConfig.CalculateCost(upgradeId, state.level)

			if state.maxed and not wasMaxedLocally then
				PlayFeedbackSound("MaxOut", 0.6); PlayUIBurst(buyButton, 20)
			else
				PlayPurchaseSound()
			end
			UpdateRegularCard(upgradeId)
			UpdateLockedTierProgress()
			PurchaseUpgrade:FireServer(upgradeId)

			if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
			return true
		end
	end

	local pulseTween = nil

	buyButton.MouseButton1Down:Connect(function()
		if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_BuyUpgrade") then return end

		globalHoldGeneration += 1
		local myGlobalGen = globalHoldGeneration

		buyGeneration += 1
		local myGen   = buyGeneration
		holdingBuy    = true
		globalHoldActive = true

		local scale = buyButton:FindFirstChildOfClass("UIScale")
		if not scale then
			scale = Instance.new("UIScale")
			scale.Parent = buyButton
		end

		pulseTween = TweenService:Create(scale,
			TweenInfo.new(0.12, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Scale = 0.88 })
		pulseTween:Play()

		TryBuy()
		task.wait(0.3)
		local holdStart = tick()

		local UserInputService = game:GetService("UserInputService")
		local epicHoldSpeedLevel   = (epicUpgradeState["epicHoldSpeed"] and epicUpgradeState["epicHoldSpeed"].level) or 0
		local holdSpeedMultiplier  = 1 + (epicHoldSpeedLevel * 0.3)

		while holdingBuy and buyGeneration == myGen and globalHoldGeneration == myGlobalGen do
			if not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
				holdingBuy = false; globalHoldActive = false; break
			end
			local success = TryBuy()
			if not success then holdingBuy = false; globalHoldActive = false; break end
			task.wait(math.max(0.02, (0.15 - ((tick() - holdStart) * 0.05)) / holdSpeedMultiplier))
		end

		globalHoldActive = false
		if pulseTween then pulseTween:Cancel() end
		if scale then
			TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), { Scale = 1 }):Play()
		end
	end)

	local function StopHold()
		holdingBuy = false
		globalHoldActive = false
		if pulseTween then pulseTween:Cancel() end
		local scale = buyButton:FindFirstChildOfClass("UIScale")
		if scale then
			TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), { Scale = 1 }):Play()
		end
	end

	buyButton.MouseButton1Up:Connect(StopHold)
	buyButton.MouseLeave:Connect(StopHold)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- BUILD EPIC CARDS
-- ─────────────────────────────────────────────────────────────────────────────
local epicOrderIndex = 1
for _, tierData in ipairs(EpicUpgradeConfig.Tiers) do
	for upgradeId, cfg in pairs(tierData.upgrades) do
		BuildCard(EpicScroll, upgradeId, cfg, true, epicCardRefs)

		local ref = epicCardRefs[upgradeId]
		if ref and ref.frame then
			ref.baseOrder      = epicOrderIndex
			ref.frame.LayoutOrder = epicOrderIndex
			epicOrderIndex    += 1
			ref.frame.Visible  = false
			ref.frame.Parent   = EpicScroll
			if UITheme and UITheme.Apply then UITheme.Apply(ref.frame, "ShopCard") end
		end
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- CARD UPDATE FUNCTIONS
-- ─────────────────────────────────────────────────────────────────────────────
function UpdateRegularCard(upgradeId)
	local ref   = regularCardRefs[upgradeId]
	local state = upgradeState[upgradeId]
	if not ref or not state then return end
	if UITheme and UITheme.Apply then UITheme.Apply(ref.frame, "ShopCard") end

	ref.levelLabel.Text = "Lv. " .. state.level .. " / " .. state.maxLevel

	local currentCash   = player:GetAttribute("LiveCurrency") or 0
	local currentSpend  = player:GetAttribute("LocalSpend") or 0
	local actualCash    = currentCash - currentSpend

	if state.level >= state.maxLevel then
		ref.frame.LayoutOrder        = (ref.baseOrder or 0) + 100000
		ref.levelLabel.TextColor3    = Color3.fromRGB(255, 215, 0)
		ref.buyButton.Text           = "MAX"
		ref.buyButton.TextColor3     = Color3.fromRGB(255, 255, 255)
		ref.buyButton.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
	else
		ref.frame.LayoutOrder      = ref.baseOrder or 0
		ref.buyButton.Text         = "$" .. FormatNumber(state.cost)
		ref.buyButton.TextColor3   = (actualCash < state.cost)
			and Color3.fromRGB(255, 100, 100) or Color3.fromRGB(255, 255, 255)
		ref.buyButton.BackgroundColor3 = Color3.fromRGB(60, 170, 80)
	end
end

function UpdateEpicCard(upgradeId)
	local ref   = epicCardRefs[upgradeId]
	local state = epicUpgradeState[upgradeId]
	if not ref or not state then return end
	if UITheme and UITheme.Apply then UITheme.Apply(ref.frame, "ShopCard") end

	ref.levelLabel.Text = "Lv. " .. state.level .. " / " .. state.maxLevel

	local currentAuras  = player:GetAttribute("LiveGoldenAuras") or 0
	local currentAuraSpend = player:GetAttribute("LocalAuraSpend") or 0
	local actualAuras   = currentAuras - currentAuraSpend

	if state.level >= state.maxLevel then
		ref.frame.LayoutOrder        = (ref.baseOrder or 0) + 100000
		ref.levelLabel.TextColor3    = Color3.fromRGB(255, 215, 0)
		ref.buyButton.Text           = "MAX"
		ref.buyButton.TextColor3     = Color3.fromRGB(255, 255, 255)
		ref.buyButton.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
	else
		ref.frame.LayoutOrder      = ref.baseOrder or 0
		ref.buyButton.Text         = "✦ " .. FormatNumber(state.cost)
		ref.buyButton.TextColor3   = (actualAuras < state.cost)
			and Color3.fromRGB(255, 100, 100) or Color3.fromRGB(255, 255, 255)
		ref.buyButton.BackgroundColor3 = Color3.fromRGB(150, 80, 255)
	end
end

function UpdateCurrencyDisplay()
	if activeMainTab == "Upgrades" then
		local currentCash = player:GetAttribute("LiveCurrency") or 0
		local currentSpend = player:GetAttribute("LocalSpend") or 0
		local actualCash = currentCash - currentSpend

		CurrencyLabel.Text       = "$" .. FormatNumber(actualCash)
		CurrencyLabel.TextColor3 = T.currencyColor
		CurrencyLabel.Position   = UDim2.new(0, 12, 0, HEADER_H + 34 + 8)
	end
end

local function UpdateAllRegularCards() for id in pairs(regularCardRefs) do UpdateRegularCard(id) end end
local function UpdateAllEpicCards()   for id in pairs(epicCardRefs)    do UpdateEpicCard(id)    end end

UpdateLockedTierProgress = function()
	local totalUpgradesBought = 0
	for _, state in pairs(upgradeState) do
		totalUpgradesBought = totalUpgradesBought + (state.level or 0)
	end

	local lockedHeader = nil
	local required = 0

	for _, child in ipairs(RegularScroll:GetChildren()) do
		if child.Name == "TierHeader_Locked" then
			lockedHeader = child
			required = child:GetAttribute("Required") or 0
			local progressLabel = child:FindFirstChild("ProgressLabel")
			if progressLabel then
				progressLabel.Text = totalUpgradesBought .. " / " .. required .. " Upgrades Needed"
				local progress = totalUpgradesBought / required
				if progress >= 1 then
					progressLabel.TextColor3 = Color3.fromRGB(100, 255, 100) 
				elseif progress >= 0.75 then
					progressLabel.TextColor3 = Color3.fromRGB(255, 200, 100) 
				else
					progressLabel.TextColor3 = Color3.fromRGB(255, 100, 100) 
				end
			end
			break
		end
	end

	if lockedHeader and totalUpgradesBought >= required then
		PlayFeedbackSound("MaxOut", 0.8)
		PlayUIBurst(ShopPanel, 30, Color3.fromRGB(100, 255, 100))
		local scroll = ShopPanel:FindFirstChild("RegularScroll")
		local savedScroll = scroll and scroll.CanvasPosition or Vector2.new(0, 0)
		RebuildRegularShop()
		if scroll then scroll.CanvasPosition = savedScroll end
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- TIER HEADERS
-- ─────────────────────────────────────────────────────────────────────────────
local function CreateTierHeader(tierName)
	local header = Instance.new("Frame")
	header.Name                 = "TierHeader"
	header.Size                 = UDim2.new(1, 0, 0, 30)
	header.BackgroundTransparency = 1

	local label = Instance.new("TextLabel")
	label.Size                  = UDim2.new(1, 0, 1, -5)
	label.BackgroundTransparency = 1
	label.Text                  = string.upper(tierName)
	label.TextColor3            = Color3.fromRGB(220, 220, 220)
	label.TextSize              = 16
	label.Font                  = Enum.Font.GothamBlack
	label.TextXAlignment        = Enum.TextXAlignment.Left
	label.Parent                = header

	local line = Instance.new("Frame")
	line.Size             = UDim2.new(1, 0, 0, 2)
	line.Position         = UDim2.new(0, 0, 1, -2)
	line.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
	line.BorderSizePixel  = 0
	line.Parent           = header
	return header
end

local function CreateLockedTierHeader(tierName, current, required)
	local header = Instance.new("Frame")
	header.Name                 = "TierHeader_Locked"
	header.Size                 = UDim2.new(1, 0, 0, 45)
	header.BackgroundTransparency = 1
	header:SetAttribute("Required", required)

	local label = Instance.new("TextLabel")
	label.Size                  = UDim2.new(1, 0, 0.5, 0)
	label.BackgroundTransparency = 1
	label.Text                  = string.upper(tierName) .. " (LOCKED)"
	label.TextColor3            = Color3.fromRGB(150, 150, 150)
	label.TextSize              = 16
	label.Font                  = Enum.Font.GothamBlack
	label.TextXAlignment        = Enum.TextXAlignment.Left
	label.Parent                = header

	local progress = Instance.new("TextLabel")
	progress.Name               = "ProgressLabel"
	progress.Size               = UDim2.new(1, 0, 0.4, 0)
	progress.Position           = UDim2.new(0, 0, 0.6, 0)
	progress.BackgroundTransparency = 1
	progress.Text               = current .. " / " .. required .. " Upgrades Needed"
	progress.TextColor3         = Color3.fromRGB(255, 100, 100)
	progress.TextSize           = 12
	progress.Font               = Enum.Font.GothamBold
	progress.TextXAlignment     = Enum.TextXAlignment.Left
	progress.Parent             = header

	local line = Instance.new("Frame")
	line.Size             = UDim2.new(1, 0, 0, 2)
	line.Position         = UDim2.new(0, 0, 1, -2)
	line.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
	line.BorderSizePixel  = 0
	line.Parent           = header
	return header
end

-- ─────────────────────────────────────────────────────────────────────────────
-- REBUILD REGULAR SHOP
-- ─────────────────────────────────────────────────────────────────────────────
RebuildRegularShop = function()
	for _, child in ipairs(RegularScroll:GetChildren()) do
		if child:IsA("Frame") and child.Name ~= "CardTemplate" then
			child:Destroy()
		end
	end
	regularCardRefs = {}

	local totalUpgradesBought = 0
	for _, state in pairs(upgradeState) do
		totalUpgradesBought = totalUpgradesBought + (state.level or 0)
	end

	local listOrder = 1

	for tierNum, tierData in ipairs(UpgradeConfig.Tiers) do
		if totalUpgradesBought >= tierData.unlockRequirement then
			local header = CreateTierHeader(tierData.tierName or "Tier " .. tierNum)
			header.LayoutOrder = listOrder
			listOrder += 1
			header.Parent = RegularScroll

			for upgradeId, cfg in pairs(tierData.upgrades) do
				BuildCard(RegularScroll, upgradeId, cfg, false, regularCardRefs)
				local ref = regularCardRefs[upgradeId]

				if ref and ref.frame then
					if ref.buyButton then
						ref.buyButton.Name = "Buy_" .. upgradeId
					end
					ref.baseOrder          = listOrder
					ref.frame.LayoutOrder  = listOrder
					listOrder             += 1
					ref.frame.Visible      = true
					ref.frame.Parent       = RegularScroll
					if UITheme and UITheme.Apply then UITheme.Apply(ref.frame, "ShopCard") end
					local myColor = Color3.fromRGB(45, 30, 55)
					ref.frame:SetAttribute("TierColor", myColor)
					ref.frame.BackgroundColor3 = myColor
				end
			end
		else
			local lockedHeader = CreateLockedTierHeader(
				tierData.tierName or "Tier " .. tierNum,
				totalUpgradesBought,
				tierData.unlockRequirement
			)
			lockedHeader.LayoutOrder = listOrder
			lockedHeader.Parent      = RegularScroll
			break
		end
	end
	UpdateAllRegularCards()
end

RebuildRegularShop()

task.delay(5, function() isLoadingData = false end)

-- ─────────────────────────────────────────────────────────────────────────────
-- TAB SWITCHING
-- ─────────────────────────────────────────────────────────────────────────────
local function SwitchToMainTab(tabName)
	if shared.PlayUISound then shared.PlayUISound(SoundConfig.UIClick or "") end
	activeMainTab     = tabName
	activeShopTabText = (tabName == "Epic") and "Epic Research" or "Regular Upgrades"
	ShopHoverLabel.Text = activeShopTabText

	for name, data in pairs(mainTabButtons) do
		data.btn.BackgroundColor3 = (name == tabName) and TAB_COLOR_ACTIVE or TAB_COLOR_BASE
		data.stroke.Color         = (name == tabName) and T.bodyText or T.panelStroke
	end

	RegularScroll.Visible = (tabName == "Upgrades")
	EpicScroll.Visible    = (tabName == "Epic")

	if tabName == "Epic" then
		for _, ref in pairs(epicCardRefs) do
			if ref and ref.frame then ref.frame.Visible = true end
		end
		if EpicScroll then EpicScroll.CanvasPosition = Vector2.new(0, 0) end
	end
end

tabUpgrades.MouseButton1Down:Connect(function() PlayUI(SoundConfig.UIClick); SwitchToMainTab("Upgrades") end)
tabEpic.MouseButton1Down:Connect(function()     PlayUI(SoundConfig.UIClick); SwitchToMainTab("Epic")     end)

-- ─────────────────────────────────────────────────────────────────────────────
-- ✨ OPEN / CLOSE (Modified for Slide-out & No Blur)
-- ─────────────────────────────────────────────────────────────────────────────
local function OpenShop()
	shopOpen = true
	ShopPanel.Visible = true
	SwitchToMainTab(activeMainTab)

	-- Slide in from the left, docking next to the left sidebar margin
	TweenService:Create(ShopPanel,
		TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0, 90, 0.5, 0) }
	):Play()

	ShopButton.BackgroundColor3 = T.panelStroke
end

local function CloseShop()
	shopOpen = false
	PlayUI(SoundConfig.UIClose)

	-- Slide back out off the left side of the screen
	local tween = TweenService:Create(ShopPanel,
		TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = UDim2.new(0, -500, 0.5, 0) }
	)
	tween:Play()
	tween.Completed:Once(function()
		if not shopOpen then ShopPanel.Visible = false end
	end)

	ShopButton.BackgroundColor3 = T.buttonSecondary
end

ShopButton.MouseButton1Down:Connect(function()
	if shopOpen then
		if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_CloseShop") then return end
		CloseShop()
		if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
	else
		if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_OpenShop") then return end
		OpenShop()
		if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
	end
end)

CloseButton.MouseButton1Down:Connect(function()
	if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_CloseShop") then return end
	CloseShop()
	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- LIVE UPDATE LOOP
-- ─────────────────────────────────────────────────────────────────────────────
local lastCardUpdate = 0
RunService.Heartbeat:Connect(function()
	if not shopOpen then return end
	local now = tick()
	if now - lastCardUpdate > 0.1 then
		lastCardUpdate = now
		if activeMainTab == "Upgrades" then UpdateAllRegularCards() else UpdateAllEpicCards() end
		UpdateCurrencyDisplay()
	end
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- SERVER EVENTS
-- ─────────────────────────────────────────────────────────────────────────────
if UpgradeUpdated then
	UpgradeUpdated.OnClientEvent:Connect(function(info)
		if info.type == "fullState" then
			isLoadingData = false
			upgradeState   = info.upgrades
			currentCurrency = info.currency
			RebuildRegularShop()
			UpdateCurrencyDisplay()

		elseif info.type == "purchased" then
			player:SetAttribute("LastServerPurchaseTick", tick())
			player:SetAttribute("LocalSpend", 0)
			player:SetAttribute("ForceSyncCurrency", info.currency)

			local current = upgradeState[info.upgradeId]
			if not current or info.level >= current.level then
				upgradeState[info.upgradeId] = {
					level    = info.level,
					maxLevel = info.maxLevel,
					cost     = info.cost,
					maxed    = info.maxed,
				}
			end
			currentCurrency = info.currency

			UpdateRegularCard(info.upgradeId)
			UpdateLockedTierProgress()
			UpdateCurrencyDisplay()
		end
	end)
end

if EpicUpgradeUpdated then
	EpicUpgradeUpdated.OnClientEvent:Connect(function(info)
		if info.type == "fullState" then
			isLoadingData = false
			epicUpgradeState = info.upgrades
			liveGoldenAuras  = info.goldenAuras or liveGoldenAuras
			UpdateAllEpicCards()
			UpdateCurrencyDisplay()

		elseif info.type == "purchased" then
			player:SetAttribute("LastServerPurchaseTick", tick())
			player:SetAttribute("LocalAuraSpend", 0)

			local current = epicUpgradeState[info.upgradeId]
			if not current or info.level >= current.level then
				epicUpgradeState[info.upgradeId] = {
					level    = info.level,
					maxLevel = info.maxLevel,
					cost     = info.cost,
					maxed    = info.maxed,
				}
			end
			UpdateEpicCard(info.upgradeId)
			UpdateCurrencyDisplay()
		end
	end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- BUTTON JUICE
-- ─────────────────────────────────────────────────────────────────────────────
local function AddButtonJuice(btn)
	if not btn then return end
	local scale = btn:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = btn
	end

	btn.MouseEnter:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Sine), { Scale = 1.08 }):Play() end)
	btn.MouseLeave:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Sine), { Scale = 1 }):Play() end)
	btn.MouseButton1Down:Connect(function() TweenService:Create(scale, TweenInfo.new(0.1, Enum.EasingStyle.Sine), { Scale = 0.9 }):Play() end)
	btn.MouseButton1Up:Connect(function() TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), { Scale = 1.08 }):Play() end)
end

AddButtonJuice(ShopButton)
AddButtonJuice(CloseButton)
AddButtonJuice(tabUpgrades)
AddButtonJuice(tabEpic)

-- ─────────────────────────────────────────────────────────────────────────────
-- REFRESH LOOK
-- ─────────────────────────────────────────────────────────────────────────────
local shopShine    = nil
local titleFlair   = nil
local flairedExtra = false

local function RefreshLook()
	UITheme.Apply(ShopPanel, "Panel")
	UITheme.Apply(ShopPanel, "TitleBar")

	if not shopShine then
		shopShine  = UITheme.ApplyShine(ShopPanel)
		UITheme.ApplyShine(TitleBar)
	end

	if not titleFlair then
		titleFlair = UITheme.ApplyFlair(TitleLabel, "Ghost")
	end

	if not flairedExtra then flairedExtra = true end

	for _, scrollName in ipairs({ "RegularScroll", "EpicScroll" }) do
		local scroll = ShopPanel:FindFirstChild(scrollName)
		if scroll then
			local layout = scroll:FindFirstChildOfClass("UIListLayout")
			if layout then layout.SortOrder = Enum.SortOrder.LayoutOrder end
		end
	end

	local outerStroke = ShopPanel:FindFirstChildWhichIsA("UIStroke")
	if outerStroke then outerStroke.Color = Color3.fromRGB(255, 255, 255) end
end

task.wait(2)
RefreshLook()

-- ✨ TUTORIAL OVERRIDE: Close shop when camera pans
local forceClose = ReplicatedStorage:FindFirstChild("ForceCloseUI") or Instance.new("BindableEvent")
forceClose.Name = "ForceCloseUI"
forceClose.Parent = ReplicatedStorage
forceClose.Event:Connect(function()
	if shopOpen then CloseShop() end
end)


-- TutorialController
-- Location: StarterPlayer > StarterPlayerScripts > TutorialController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local TutorialConfig = require(ReplicatedStorage.Modules.TutorialConfig)
local UITheme = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UITheme"))
local T = UITheme.Get("Custom")
local SoundConfig = require(ReplicatedStorage.Modules.SoundConfig)
local Formatter = require(ReplicatedStorage.Modules.NumberFormatter)

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local TutorialStepComplete = RemoteEvents:WaitForChild("TutorialStepComplete", 10)

local BridgeNet2 = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))
local UpdateHUDBridge = BridgeNet2.ClientBridge("UpdateHUD")

local ForceCloseUI = ReplicatedStorage:FindFirstChild("ForceCloseUI")
if not ForceCloseUI then
	ForceCloseUI = Instance.new("BindableEvent")
	ForceCloseUI.Name = "ForceCloseUI"
	ForceCloseUI.Parent = ReplicatedStorage
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = Workspace.CurrentCamera

---------------------------------------------------------------
-- STATE
---------------------------------------------------------------
local currentStepIndex = 1
local tutorialComplete = false
local tutorialActive = false

local activeFallbackStep = nil
local lastDisplayedStepId = nil 

local actionMatchedForAdvance = false 
local isAdvancing = false 

local liveStats = {
	currency = 0,
	totalEarned = 0,
	farmEvaluation = 0,
	soulAuras = 0,
	goldenAuras = 0,
	prestigeCount = 0,
	currentArea = 1,
	totalCubesProduced = 0,
	totalPlatformsShipped = 0,
	totalLegendaryCubes = 0,
	piggyBank = 0,

	pendingAuras = 0,
	habitatCapacity = 99999,
	rate = 0,
	currentMultiplier = 1,

	boostsBought = {},
	boostsUsed = {}
}

local UpdateMultiplier = ReplicatedStorage:WaitForChild("UpdateMultiplier")
UpdateMultiplier.Event:Connect(function(mult)
	liveStats.currentMultiplier = mult
end)

local baselineCubes = 0
local baselineShipped = 0
local baselineGoldenAuras = 0
local baselineBoostsBought = {}
local baselineBoostsUsed = {}

local function GetStepCubes() return math.max(0, liveStats.totalCubesProduced - baselineCubes) end
local function GetStepShipped() return math.max(0, liveStats.totalPlatformsShipped - baselineShipped) end
local function GetStepBoostsBought(id) return math.max(0, (liveStats.boostsBought[id] or 0) - (baselineBoostsBought[id] or 0)) end
local function GetStepBoostsUsed(id) return math.max(0, (liveStats.boostsUsed[id] or 0) - (baselineBoostsUsed[id] or 0)) end

local function GetStepGoldenAuras() 
	local current = player:GetAttribute("LiveGoldenAuras") or liveStats.goldenAuras
	return math.max(0, current - baselineGoldenAuras) 
end

local lockedAura = nil

local function GetActiveAura()
	if lockedAura and lockedAura.Parent and lockedAura.Parent.Name == "AuraHolder" and lockedAura:GetAttribute("AuraCube") then 
		return lockedAura 
	end
	local auraHolder = Workspace:FindFirstChild("AuraHolder")
	if auraHolder then
		local children = auraHolder:GetChildren()
		for i = #children, 1, -1 do
			local child = children[i]
			if child:GetAttribute("AuraCube") then lockedAura = child; return child end
		end
	end
	return nil
end

local currentTrackedPhysicsAura = nil

local function GetActivePhysicsAura()
	if currentTrackedPhysicsAura and currentTrackedPhysicsAura.Parent and not currentTrackedPhysicsAura:GetAttribute("Landed") then
		return currentTrackedPhysicsAura
	end

	local auras = CollectionService:GetTagged("PhysicsAura")
	for _, aura in ipairs(auras) do
		if aura and aura.Parent and not aura:GetAttribute("Landed") then
			currentTrackedPhysicsAura = aura
			return aura
		end
	end

	currentTrackedPhysicsAura = nil
	return nil
end

shared.TutorialRecordAuraSpawned = function() liveStats.totalCubesProduced += 1 end
shared.TutorialRecordShipSent = function() task.delay(4, function() liveStats.totalPlatformsShipped += 1 end) end
shared.TutorialRecordBoostBought = function(id) liveStats.boostsBought[id] = (liveStats.boostsBought[id] or 0) + 1 end
shared.TutorialRecordBoostUsed = function(id) liveStats.boostsUsed[id] = (liveStats.boostsUsed[id] or 0) + 1 end

local tutorialGui = nil
local activePointer = nil
local activeHighlight = nil
local questBanner = nil
local trackingConnection = nil

-- ✨ PANEL AWARENESS
local PANELS_TO_CHECK = {
	"Tutorial_AchievePanel",
	"Tutorial_ShopPanel",
	"Tutorial_PrestigePanel",
	"Tutorial_TravelPanel",
	"Tutorial_BoostShopPanel"
}

-- ✨ HUD HARDCODED DIRECTIONS (Prevents Jitter!)
local HUD_DIRECTIONS = {
	Tutorial_ClickButton    = "TOP_HIGH",  
	Tutorial_ToggleShipBtn  = "TOP",
	Tutorial_SendShipBtn    = "TOP",
	Tutorial_TravelButton   = "TOP",
	Tutorial_PrestigeButton = "RIGHT", 
	Tutorial_ShopButton     = "RIGHT", 
	Tutorial_BoostMenuBtn   = "RIGHT", 
	Tutorial_AchieveMenuBtn = "RIGHT", 
	Tutorial_LbTab_Top10    = "LEFT",  
	Tutorial_LbTab_AurasGenerated = "LEFT",
	Tutorial_LbTab_MostMoneyMade = "LEFT",
}

---------------------------------------------------------------
-- VISIBILITY & GATING EVALUATION
---------------------------------------------------------------
local function IsVisibleOnScreen(guiObject)
	local current = guiObject
	while current and current ~= game do
		if current:IsA("GuiObject") and not current.Visible then return false
		elseif current:IsA("LayerCollector") and not current.Enabled then return false end
		current = current.Parent
	end
	return true
end

local function GetActivePanel()
	for _, tag in ipairs(PANELS_TO_CHECK) do
		local panel = CollectionService:GetTagged(tag)[1]
		if panel and IsVisibleOnScreen(panel) then return panel end
	end
	return nil
end

local function MeetsStrictGates(step)
	if not step then return false end

	local currentCash = player:GetAttribute("LiveCurrency") or liveStats.currency
	local currentGoldenAuras = player:GetAttribute("LiveGoldenAuras") or liveStats.goldenAuras

	if step.requireHabitatFull and liveStats.pendingAuras < liveStats.habitatCapacity then return false end
	if step.requireRateZero and liveStats.rate > 0.1 then return false end
	if step.reachMultiplier and liveStats.currentMultiplier < step.reachMultiplier then return false end

	if step.requireCubesProduced and GetStepCubes() < step.requireCubesProduced then return false end
	if step.requirePlatformsShipped and GetStepShipped() < step.requirePlatformsShipped then return false end
	if step.requireBoostBought and GetStepBoostsBought(step.requireBoostBought.id) < step.requireBoostBought.count then return false end
	if step.requireBoostUsed and GetStepBoostsUsed(step.requireBoostUsed.id) < step.requireBoostUsed.count then return false end

	if step.requireGoldenAuras and currentGoldenAuras < step.requireGoldenAuras then return false end
	if step.requireStepGoldenAuras and GetStepGoldenAuras() < step.requireStepGoldenAuras then return false end

	if step.requireCurrency and currentCash < step.requireCurrency then return false end
	if step.requireFarmEval and liveStats.farmEvaluation < step.requireFarmEval then return false end
	if step.requireSoulAuras and liveStats.soulAuras < step.requireSoulAuras then return false end
	if step.requirePrestigeCount and liveStats.prestigeCount < step.requirePrestigeCount then return false end
	if step.requireArea and liveStats.currentArea < step.requireArea then return false end
	if step.requireLegendaryCubes and liveStats.totalLegendaryCubes < step.requireLegendaryCubes then return false end
	if step.requirePiggyBankValue and liveStats.piggyBank < step.requirePiggyBankValue then return false end

	return true
end

---------------------------------------------------------------
-- LOGIC-LEVEL GATING (The Soft Lock)
---------------------------------------------------------------
shared.TutorialCanPerform = function(requestedAction)
	actionMatchedForAdvance = false 

	if tutorialComplete or not tutorialActive then return true end

	local activeStep = activeFallbackStep or TutorialConfig.GetStepByIndex(currentStepIndex)
	if not activeStep then return true end

	if activeStep.action == "Action_Wait" and not activeStep.allowClicking then
		if activeStep.duration and activeStep.duration > 0 then
			if shared.PlayUISound then shared.PlayUISound(SoundConfig.ErrorBuzz or "") end
			return false
		end
		if requestedAction == "Action_ClickRedButton" then
			if shared.PlayUISound then shared.PlayUISound(SoundConfig.ErrorBuzz or "") end
			return false
		end
	end

	if not activeStep.action then return true end
	if activeStep.action == requestedAction then actionMatchedForAdvance = true; return true end

	local isPermanentlyUnlocked = false
	for i = 1, currentStepIndex do
		local pastStep = TutorialConfig.GetStepByIndex(i)
		if pastStep then
			if i < currentStepIndex and pastStep.action == requestedAction then
				isPermanentlyUnlocked = true; break
			end
			if pastStep.unlockActions then
				for _, act in ipairs(pastStep.unlockActions) do
					if act == requestedAction then isPermanentlyUnlocked = true; break end
				end
			end
		end
	end
	if isPermanentlyUnlocked then return true end

	if requestedAction == "Action_ClickRedButton" and not MeetsStrictGates(activeStep) then return true end
	if shared.PlayUISound then shared.PlayUISound(SoundConfig.ErrorBuzz or "") end
	return false
end

---------------------------------------------------------------
-- INITIALIZATION & UI
---------------------------------------------------------------
local function InitTutorialUI()
	tutorialGui = Instance.new("ScreenGui"); tutorialGui.Name = "TutorialOverlays"; tutorialGui.DisplayOrder = 1000 
	tutorialGui.ResetOnSpawn = false; tutorialGui.Parent = playerGui

	activeHighlight = Instance.new("Frame"); activeHighlight.Name = "TutorialHighlight"
	activeHighlight.BackgroundColor3 = Color3.new(1, 1, 1); activeHighlight.BackgroundTransparency = 1 
	activeHighlight.Interactable = false; activeHighlight.Active = false; activeHighlight.Visible = false
	activeHighlight.ZIndex = 99; activeHighlight.Parent = tutorialGui

	local highlightStroke = Instance.new("UIStroke", activeHighlight)
	highlightStroke.Color = TutorialConfig.DefaultColor; highlightStroke.Thickness = 3; highlightStroke.Transparency = 0.2
	Instance.new("UICorner", activeHighlight).CornerRadius = UDim.new(0, 8)
	TweenService:Create(highlightStroke, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {Transparency = 0.8}):Play()

	activePointer = Instance.new("ImageLabel"); activePointer.Name = "GhostHand"
	activePointer.Size = TutorialConfig.PointerSize; activePointer.BackgroundTransparency = 1
	activePointer.Image = TutorialConfig.PointerImage; activePointer.AnchorPoint = Vector2.new(0.5, 0.5)
	activePointer.Visible = false; activePointer.Active = false; activePointer.ZIndex = 100; activePointer.Parent = tutorialGui

	questBanner = Instance.new("Frame"); questBanner.Name = "QuestBanner"
	questBanner.Size = UDim2.new(0.85, 0, 0, 130); questBanner.AnchorPoint = Vector2.new(0.5, 0)
	questBanner.Position = UDim2.new(0.5, 0, 0, -250); questBanner.BackgroundColor3 = T.panelBG or Color3.fromRGB(20, 20, 30)
	questBanner.BorderSizePixel = 0; questBanner.Visible = false; questBanner.Active = false; questBanner.Parent = tutorialGui
	Instance.new("UICorner", questBanner).CornerRadius = UDim.new(0, 12)

	local sizeConstraint = Instance.new("UISizeConstraint", questBanner)
	sizeConstraint.MaxSize = Vector2.new(650, 130); sizeConstraint.MinSize = Vector2.new(280, 85)
	Instance.new("UIScale", questBanner)

	local bgGrad = Instance.new("UIGradient", questBanner)
	bgGrad.Rotation = 90
	bgGrad.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0.95) })

	local stroke = Instance.new("UIStroke", questBanner); stroke.Name = "BannerStroke"
	stroke.Color = TutorialConfig.DefaultColor; stroke.Thickness = 2.5; stroke.Transparency = 0.1
	local strokeGrad = Instance.new("UIGradient", stroke); strokeGrad.Name = "StrokeGradient"; strokeGrad.Rotation = 45

	local iconFrame = Instance.new("Frame", questBanner); iconFrame.Name = "IconFrame"
	iconFrame.Size = UDim2.new(0, 72, 0, 72); iconFrame.AnchorPoint = Vector2.new(0, 0.5)
	iconFrame.Position = UDim2.new(0, 14, 0.5, 0); iconFrame.BackgroundColor3 = TutorialConfig.DefaultColor
	iconFrame.BackgroundTransparency = 0.85; iconFrame.Active = false
	Instance.new("UICorner", iconFrame).CornerRadius = UDim.new(0, 12)
	Instance.new("UIStroke", iconFrame).Color = TutorialConfig.DefaultColor

	local icon = Instance.new("ImageLabel", iconFrame); icon.Name = "IconImage"
	icon.Size = UDim2.new(0.65, 0, 0.65, 0); icon.Position = UDim2.new(0.175, 0, 0.175, 0)
	icon.BackgroundTransparency = 1; icon.Image = TutorialConfig.DefaultIcon
	icon.ScaleType = Enum.ScaleType.Fit; icon.Active = false

	local title = Instance.new("TextLabel", questBanner); title.Name = "Title"
	title.Size = UDim2.new(1, -100, 0.35, 0); title.Position = UDim2.new(0, 96, 0.08, 0)
	title.BackgroundTransparency = 1; title.TextColor3 = TutorialConfig.DefaultColor
	title.TextScaled = true; title.Font = Enum.Font.FredokaOne; title.TextXAlignment = Enum.TextXAlignment.Left; title.Active = false
	local titleConstraint = Instance.new("UITextSizeConstraint", title); titleConstraint.MaxTextSize = 34; titleConstraint.MinTextSize = 14

	local titleShadow = title:Clone(); titleShadow.Name = "TitleShadow"; titleShadow.TextColor3 = Color3.new(0, 0, 0)
	titleShadow.TextTransparency = 0.6; titleShadow.Position = UDim2.new(0, 98, 0.08, 2)
	titleShadow.ZIndex = title.ZIndex - 1; titleShadow.Parent = questBanner

	local body = Instance.new("TextLabel", questBanner); body.Name = "Body"
	body.Size = UDim2.new(1, -100, 0.5, 0); body.Position = UDim2.new(0, 96, 0.45, 0)
	body.BackgroundTransparency = 1; body.TextColor3 = T.bodyText or Color3.fromRGB(230, 230, 240)
	body.TextWrapped = true; body.TextScaled = true; body.RichText = true
	body.Font = Enum.Font.GothamMedium; body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top; body.Active = false
	local bodyConstraint = Instance.new("UITextSizeConstraint", body); bodyConstraint.MaxTextSize = 22; bodyConstraint.MinTextSize = 10
end

local function AutoScrollToTarget(target)
	local scrollFrame = target:FindFirstAncestorOfClass("ScrollingFrame")
	if scrollFrame then
		local relativeY = (target.AbsolutePosition.Y - scrollFrame.AbsolutePosition.Y) + scrollFrame.CanvasPosition.Y
		local targetCanvasY = relativeY - (scrollFrame.AbsoluteSize.Y / 2) + (target.AbsoluteSize.Y / 2)
		local maxScroll = math.max(0, scrollFrame.AbsoluteCanvasSize.Y - scrollFrame.AbsoluteSize.Y)
		TweenService:Create(scrollFrame, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CanvasPosition = Vector2.new(scrollFrame.CanvasPosition.X, math.clamp(targetCanvasY, 0, maxScroll))
		}):Play()
	end
end

local function HideBanner()
	if not questBanner or not questBanner.Visible then return end
	TweenService:Create(questBanner, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.new(0.5, 0, 0, -250) }):Play()
	task.delay(0.4, function() if lastDisplayedStepId == nil then questBanner.Visible = false end end)
end

-- ======================================================================================
-- ✨ 🛠️ YOU CAN EDIT BANNER POSITIONS HERE! 🛠️ ✨
-- UDim2.new(ScaleX, OffsetX, ScaleY, OffsetY)
-- Scale is 0 to 1 (0.5 is center). Offset is raw pixels!
-- ======================================================================================
local function GetBannerTarget()
	local activePanel = GetActivePanel()
	local screenW = camera.ViewportSize.X

	if activePanel then
		local panelName = activePanel.Name

		-- Safely get the Banner's rendered width to calculate padding
		local bannerW = questBanner.AbsoluteSize.X * 0.85
		if bannerW < 10 then bannerW = 650 * 0.85 end 

		if panelName == "ShopPanel" then
			-- Shop is on the Left. Target: Put banner to the right, top-aligned.
			local panelRightEdge = activePanel.AbsolutePosition.X + activePanel.AbsoluteSize.X
			local targetPixelX = panelRightEdge + 75 + (bannerW / 2)
			targetPixelX = math.min(targetPixelX, screenW - (bannerW / 2) - 10)

			return UDim2.new(0, targetPixelX, 0, math.max(15, activePanel.AbsolutePosition.Y)), 0.85

		elseif panelName == "BoostShopPanel" then
			-- Boosts are on the Left. Target: Top-Center open space!
			return UDim2.new(0.5, 0, 0, 15), 0.85

		elseif panelName == "TravelPanel" then
			-- Area Travel is centered. Target: Top-Center open space!
			return UDim2.new(0.5, 0, 0, 45), 0.85

		elseif panelName == "PrestigePanel" then
			-- Prestige is centered. Target: Top-Center open space!
			return UDim2.new(0.5, 0, 0, 15), 0.85

		elseif panelName == "AchievementPanel" then
			-- Achievements are centered. Target: The empty void below the panel (Y = -190)
			return UDim2.new(0.5, 0, 1, -300), 0.85

		else
			-- Fallback for any other panel that might open
			return UDim2.new(0.5, 0, 0, 15), 0.85
		end
	else
		-- 🛠️ NO PANELS OPEN: Default to Normal Top-Center
		return UDim2.new(0.5, 0, 0, 15), 1.0
	end
end
-- ======================================================================================

local function ShowBanner(step)
	local stepColor = step.color or TutorialConfig.DefaultColor
	questBanner.Title.Text = step.bannerTitle; questBanner.TitleShadow.Text = step.bannerTitle; questBanner.Body.Text = step.bannerBody
	questBanner.Title.TextColor3 = stepColor; questBanner.IconFrame.BackgroundColor3 = stepColor; questBanner.IconFrame.UIStroke.Color = stepColor
	questBanner.IconFrame.IconImage.Image = step.icon or TutorialConfig.DefaultIcon

	if activeHighlight then
		local stroke = activeHighlight:FindFirstChildOfClass("UIStroke")
		if stroke then stroke.Color = stepColor end
	end

	local strokeGrad = questBanner.BannerStroke:FindFirstChild("StrokeGradient")
	if strokeGrad then
		strokeGrad.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)), ColorSequenceKeypoint.new(1, stepColor) })
	end

	local targetPos, targetScale = GetBannerTarget()

	if not questBanner.Visible then
		questBanner.Position = UDim2.new(0.5, 0, 0, -250); questBanner.Visible = true
		TweenService:Create(questBanner, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = targetPos }):Play()
	else
		TweenService:Create(questBanner, TweenInfo.new(0.4, Enum.EasingStyle.Sine), { Position = targetPos }):Play()
	end

	local scaleObj = questBanner:FindFirstChildOfClass("UIScale")
	if scaleObj then
		TweenService:Create(scaleObj, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = targetScale }):Play()
	end

	if shared.PlayUISound then shared.PlayUISound(SoundConfig.TutorialHint or "6895079853") end
end

---------------------------------------------------------------
-- CORE LOOP (RenderStepped)
---------------------------------------------------------------
local function StartTrackingLoop()
	if trackingConnection then trackingConnection:Disconnect() end

	local bounceTime = 0
	local isAutoScrolling = false

	trackingConnection = RunService.RenderStepped:Connect(function(dt)
		local allLockedTags = {}; local currentUnlockedTags = {}

		for i, stp in ipairs(TutorialConfig.Steps) do
			if stp.unlockTags then
				for _, tag in ipairs(stp.unlockTags) do
					allLockedTags[tag] = true
					if tutorialComplete or i <= currentStepIndex then currentUnlockedTags[tag] = true end
				end
			end
		end

		for tag, _ in pairs(allLockedTags) do
			local isUnlocked = currentUnlockedTags[tag] or tutorialComplete
			local elements = CollectionService:GetTagged(tag)
			for _, el in ipairs(elements) do
				local overlay = el:FindFirstChild("TutorialLockOverlay")
				if not isUnlocked then
					if not overlay then
						overlay = Instance.new("TextButton"); overlay.Name = "TutorialLockOverlay"; overlay.Size = UDim2.new(1, 0, 1, 0)
						overlay.Position = UDim2.new(0, 0, 0, 0); overlay.AnchorPoint = Vector2.new(0, 0)
						overlay.BackgroundColor3 = Color3.fromRGB(15, 15, 20); overlay.BackgroundTransparency = 0.5
						overlay.ZIndex = 99998; overlay.Text = ""; overlay.AutoButtonColor = false

						local corner = el:FindFirstChildOfClass("UICorner")
						if corner then corner:Clone().Parent = overlay end

						local icon = Instance.new("ImageLabel"); icon.Name = "PadlockIcon"; icon.Size = UDim2.new(0, 24, 0, 24)
						icon.AnchorPoint = Vector2.new(0.5, 0.5); icon.Position = UDim2.new(0.5, 0, 0.5, 0)
						icon.BackgroundTransparency = 1; icon.Image = "rbxassetid://7059346373"; icon.ImageColor3 = Color3.fromRGB(255, 255, 255)
						icon.ScaleType = Enum.ScaleType.Fit; icon.ZIndex = 99999; icon.Parent = overlay

						overlay.Parent = el
					end
				else
					if overlay then overlay:Destroy() end
				end
			end
		end

		if tutorialComplete then 
			if activePointer then activePointer.Visible = false end
			if activeHighlight then activeHighlight.Visible = false end
			HideBanner()
			if trackingConnection then trackingConnection:Disconnect() end
			return 
		end

		bounceTime += dt * 5
		local bounceOffset = math.abs(math.sin(bounceTime)) * 15

		local step = activeFallbackStep or TutorialConfig.GetStepByIndex(currentStepIndex)
		if not step then return end

		if not activeFallbackStep then
			if not MeetsStrictGates(step) then
				if step.fallbackStepId then
					local foundFallback = TutorialConfig.GetStepById(step.fallbackStepId)
					if foundFallback then activeFallbackStep = foundFallback; step = activeFallbackStep end
				end
			end
		else
			local originalStep = TutorialConfig.GetStepByIndex(currentStepIndex)
			if originalStep and MeetsStrictGates(originalStep) then
				activeFallbackStep = nil; step = originalStep
			end
		end

		if not step then return end 

		if step.bannerTitle then
			if lastDisplayedStepId ~= step.id then
				lastDisplayedStepId = step.id
				ShowBanner(step)
				if step.cameraTarget or step.cameraTrackMode then ForceCloseUI:Fire() end
			end

			-- ✨ SMOOTH DYNAMIC BANNER AVOIDANCE
			if questBanner and questBanner.Visible then
				local targetPos, targetScale = GetBannerTarget()
				questBanner.Position = questBanner.Position:Lerp(targetPos, 0.15)
				local scaleObj = questBanner:FindFirstChildOfClass("UIScale")
				if scaleObj then
					scaleObj.Scale = scaleObj.Scale + ((targetScale - scaleObj.Scale) * 0.15)
				end
			end

			local progressText = ""
			local checkStep = activeFallbackStep and TutorialConfig.GetStepByIndex(currentStepIndex) or step

			if checkStep.requireCubesProduced then
				local capCubes = math.min(GetStepCubes(), checkStep.requireCubesProduced)
				progressText = "\n<b><font color='rgb(100, 255, 100)'>Progress: " .. capCubes .. " / " .. checkStep.requireCubesProduced .. "</font></b>"
			elseif checkStep.requirePlatformsShipped then
				local capShipped = math.min(GetStepShipped(), checkStep.requirePlatformsShipped)
				progressText = "\n<b><font color='rgb(100, 255, 100)'>Progress: " .. capShipped .. " / " .. checkStep.requirePlatformsShipped .. "</font></b>"
			elseif checkStep.requireCurrency then
				local currentCash = player:GetAttribute("LiveCurrency") or liveStats.currency
				local capCash = math.min(math.floor(currentCash), checkStep.requireCurrency)
				progressText = "\n<b><font color='rgb(100, 255, 100)'>Progress: $" .. capCash .. " / $" .. checkStep.requireCurrency .. "</font></b>"
			elseif checkStep.reachMultiplier then
				local currentMult = liveStats.currentMultiplier or 1
				local capMult = math.min(currentMult, checkStep.reachMultiplier)
				progressText = "\n<b><font color='rgb(255, 255, 50)'>Progress: " .. string.format("%.1f", capMult) .. "x / " .. string.format("%.1f", checkStep.reachMultiplier) .. "x</font></b>"
			elseif checkStep.requireStepGoldenAuras then
				local capGA = math.min(GetStepGoldenAuras(), checkStep.requireStepGoldenAuras)
				progressText = "\n<b><font color='rgb(255, 215, 0)'>Progress: " .. capGA .. " / " .. checkStep.requireStepGoldenAuras .. " GA</font></b>"
			elseif checkStep.requireFarmEval then
				local capFE = math.min(math.floor(liveStats.farmEvaluation), checkStep.requireFarmEval)
				progressText = "\n<b><font color='rgb(100, 255, 100)'>Progress: $" .. Formatter.Format(capFE) .. " / $" .. Formatter.Format(checkStep.requireFarmEval) .. "</font></b>"
			elseif checkStep.requireBoostBought then
				local cap = math.min(GetStepBoostsBought(checkStep.requireBoostBought.id), checkStep.requireBoostBought.count)
				progressText = "\n<b><font color='rgb(100, 255, 100)'>Progress: " .. cap .. " / " .. checkStep.requireBoostBought.count .. "</font></b>"
			elseif checkStep.requireBoostUsed then
				local cap = math.min(GetStepBoostsUsed(checkStep.requireBoostUsed.id), checkStep.requireBoostUsed.count)
				progressText = "\n<b><font color='rgb(100, 255, 100)'>Progress: " .. cap .. " / " .. checkStep.requireBoostUsed.count .. "</font></b>"
			end
			questBanner.Body.Text = step.bannerBody .. progressText

		else
			if lastDisplayedStepId ~= nil then lastDisplayedStepId = nil; HideBanner() end
		end

		local targetToTrack2D = nil
		local targetToTrack3D = nil

		if step.target3D then
			if string.find(string.lower(step.target3D), "aura") then
				local aura = GetActiveAura()
				if aura then targetToTrack3D = aura:IsA("Model") and aura:GetPivot().Position or aura.Position end
			else
				local obj = CollectionService:GetTagged(step.target3D)[1]
				if obj then targetToTrack3D = obj:IsA("Model") and obj:GetPivot().Position or obj.Position end
			end
		elseif step.targetTag then
			if step.menuTag and step.menuOpenBtnTag then
				local menuInstances = CollectionService:GetTagged(step.menuTag)
				local menuIsOpen = false
				for _, menu in ipairs(menuInstances) do
					if IsVisibleOnScreen(menu) then menuIsOpen = true; break end
				end
				targetToTrack2D = menuIsOpen and CollectionService:GetTagged(step.targetTag)[1] or CollectionService:GetTagged(step.menuOpenBtnTag)[1]
			else
				targetToTrack2D = CollectionService:GetTagged(step.targetTag)[1]
			end
		end

		if targetToTrack3D then
			local screenPos, onScreen = camera:WorldToViewportPoint(targetToTrack3D)
			if onScreen and screenPos.Z > 0 then
				activePointer.Visible = true; activeHighlight.Visible = false 
				activePointer.Rotation = 0
				activePointer.Position = UDim2.new(0, screenPos.X, 0, screenPos.Y - (activePointer.Size.Y.Offset / 2) - bounceOffset)
			else
				activePointer.Visible = false; activeHighlight.Visible = false
			end

		elseif targetToTrack2D and targetToTrack2D:IsA("GuiObject") then
			if targetToTrack2D.AbsoluteSize.Magnitude > 0 and IsVisibleOnScreen(targetToTrack2D) then
				activePointer.Visible = true; activeHighlight.Visible = true

				local tgtX, tgtY, tgtW, tgtH
				local scaleObj = targetToTrack2D:FindFirstChildOfClass("UIScale")

				if scaleObj and scaleObj.Scale ~= 1 and not targetToTrack2D.Parent:FindFirstChildOfClass("UIListLayout") then
					local scale = scaleObj.Scale
					local trueW = targetToTrack2D.AbsoluteSize.X / scale
					local trueH = targetToTrack2D.AbsoluteSize.Y / scale
					local anchorX = targetToTrack2D.AnchorPoint.X
					local anchorY = targetToTrack2D.AnchorPoint.Y
					local anchorAbsX = targetToTrack2D.AbsolutePosition.X + (targetToTrack2D.AbsoluteSize.X * anchorX)
					local anchorAbsY = targetToTrack2D.AbsolutePosition.Y + (targetToTrack2D.AbsoluteSize.Y * anchorY)
					tgtX = anchorAbsX - (trueW * anchorX)
					tgtY = anchorAbsY - (trueH * anchorY)
					tgtW = trueW
					tgtH = trueH
				else
					tgtX = targetToTrack2D.AbsolutePosition.X
					tgtY = targetToTrack2D.AbsolutePosition.Y
					tgtW = targetToTrack2D.AbsoluteSize.X
					tgtH = targetToTrack2D.AbsoluteSize.Y

					if scaleObj and scaleObj.Scale ~= 1 then
						tgtW = tgtW / scaleObj.Scale
						tgtH = tgtH / scaleObj.Scale
						tgtX = tgtX + ((targetToTrack2D.AbsoluteSize.X - tgtW) / 2)
						tgtY = tgtY + ((targetToTrack2D.AbsoluteSize.Y - tgtH) / 2)
					end
				end

				local screenW = camera.ViewportSize.X
				local screenH = camera.ViewportSize.Y

				local centerX = tgtX + (tgtW / 2)
				local centerY = tgtY + (tgtH / 2)

				local padding = 15
				local pointerW = activePointer.Size.X.Offset
				local pointerH = activePointer.Size.Y.Offset

				local pX, pY, rot
				local dir = "BOTTOM" 

				local tagCheck = step.targetTag or ""

				if HUD_DIRECTIONS[tagCheck] then
					dir = HUD_DIRECTIONS[tagCheck]
				elseif tagCheck:match("Tutorial_AchieveRow") or tagCheck:match("Tutorial_BuyBoost") or tagCheck:match("Tutorial_UseBoost") then
					dir = "RIGHT"
				else
					if centerX < screenW * 0.3 then dir = "RIGHT"
					elseif centerX > screenW * 0.7 then dir = "LEFT"
					elseif centerY > screenH * 0.5 then dir = "TOP"
					else dir = "BOTTOM" end
				end

				if dir == "RIGHT" then
					pX = centerX + (tgtW / 2) + (pointerW / 2) + padding + bounceOffset
					pY = centerY
					rot = 90
				elseif dir == "LEFT" then
					pX = centerX - (tgtW / 2) - (pointerW / 2) - padding - bounceOffset
					pY = centerY
					rot = -90
				elseif dir == "TOP_HIGH" then
					pX = centerX
					pY = centerY - (tgtH / 2) - (pointerH / 2) - 45 - bounceOffset
					rot = 0
				elseif dir == "TOP" then
					pX = centerX
					pY = centerY - (tgtH / 2) - (pointerH / 2) - padding - bounceOffset
					rot = 0
				elseif dir == "BOTTOM" then
					if tgtW > 200 then
						pX = tgtX + tgtW - 55 
					else
						pX = centerX
					end
					pY = centerY + (tgtH / 2) + (pointerH / 2) + 2 + bounceOffset 
					rot = 180
				end

				local targetPointerPos = UDim2.new(0, pX, 0, pY)
				activePointer.Position = activePointer.Position:Lerp(targetPointerPos, 0.3)
				activePointer.Rotation = rot

				local targetHighPos = UDim2.new(0, tgtX - 6, 0, tgtY - 6)
				local targetHighSize = UDim2.new(0, tgtW + 12, 0, tgtH + 12)

				activeHighlight.Position = activeHighlight.Position:Lerp(targetHighPos, 0.4)
				activeHighlight.Size = activeHighlight.Size:Lerp(targetHighSize, 0.4)

				local targetCorner = targetToTrack2D:FindFirstChildOfClass("UICorner")
				local highlightCorner = activeHighlight:FindFirstChildOfClass("UICorner")
				if targetCorner and highlightCorner then highlightCorner.CornerRadius = targetCorner.CornerRadius end

				local scrollFrame = targetToTrack2D:FindFirstAncestorOfClass("ScrollingFrame")
				if scrollFrame and not isAutoScrolling then
					local targetY2 = targetToTrack2D.AbsolutePosition.Y; local scrollY = scrollFrame.AbsolutePosition.Y
					local scrollBottom = scrollY + scrollFrame.AbsoluteSize.Y

					if (targetY2 + tgtH < scrollY) or (targetY2 > scrollBottom) then
						isAutoScrolling = true; AutoScrollToTarget(targetToTrack2D)
						task.delay(0.5, function() isAutoScrolling = false end)
					end
				end
			else
				activePointer.Visible = false; activeHighlight.Visible = false
			end
		else
			activePointer.Visible = false; activeHighlight.Visible = false
		end

		if step.cameraTrackMode == "FollowAura" then
			local aura = GetActiveAura()
			if aura then
				if camera.CameraType ~= Enum.CameraType.Scriptable then camera.CameraType = Enum.CameraType.Scriptable end
				local targetPos = aura:IsA("Model") and aura:GetPivot().Position or aura.Position
				local offset = step.cameraOffset or Vector3.new(0, 8, 10) 
				camera.CFrame = camera.CFrame:Lerp(CFrame.new(targetPos + offset, targetPos), 0.025) 
			else
				local fallbackCam = CollectionService:GetTagged("Tutorial_AuraHolderCam")[1]
				if fallbackCam then
					if camera.CameraType ~= Enum.CameraType.Scriptable then camera.CameraType = Enum.CameraType.Scriptable end
					local desiredCFrame = fallbackCam:IsA("Model") and fallbackCam:GetPivot() or fallbackCam.CFrame
					camera.CFrame = camera.CFrame:Lerp(desiredCFrame, 0.025)
				end
			end

		elseif step.cameraTrackMode == "FollowPhysicsAura" then
			local physicsAura = GetActivePhysicsAura()

			local cameraTimeExpired = false
			if step.cameraDuration then
				if not step._cameraStartTime then step._cameraStartTime = tick() end
				if tick() - step._cameraStartTime >= step.cameraDuration then
					cameraTimeExpired = true
				end
			end

			if physicsAura and not cameraTimeExpired then
				step._returningToPlayer = nil 
				if camera.CameraType ~= Enum.CameraType.Scriptable then camera.CameraType = Enum.CameraType.Scriptable end
				local targetPos = physicsAura:IsA("Model") and physicsAura:GetPivot().Position or physicsAura.Position
				local offset = step.cameraOffset or Vector3.new(0, 15, 25) 
				camera.CFrame = camera.CFrame:Lerp(CFrame.new(targetPos + offset, targetPos), 0.05) 
			else
				if camera.CameraType == Enum.CameraType.Scriptable then
					if not step._returningToPlayer then
						step._returningToPlayer = true
						local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
						if hrp then
							local targetCF = CFrame.new(hrp.Position + Vector3.new(0, 8, 12), hrp.Position)
							local tween = TweenService:Create(camera, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {CFrame = targetCF})
							tween:Play()
							tween.Completed:Once(function()
								if step._returningToPlayer then
									camera.CameraType = Enum.CameraType.Custom
									camera.CameraSubject = player.Character:FindFirstChild("Humanoid")
								end
							end)
						else
							camera.CameraType = Enum.CameraType.Custom
						end
					end
				end
			end

		elseif step.cameraTarget then
			local camTarget = CollectionService:GetTagged(step.cameraTarget)[1]
			if not camTarget or not camTarget.Parent then
				if camera.CameraType ~= Enum.CameraType.Custom then
					camera.CameraType = Enum.CameraType.Custom
					if player.Character and player.Character:FindFirstChild("Humanoid") then
						camera.CameraSubject = player.Character:FindFirstChild("Humanoid")
					end
				end
			else
				if camera.CameraType ~= Enum.CameraType.Scriptable then camera.CameraType = Enum.CameraType.Scriptable end
				local desiredCFrame = camTarget:IsA("Model") and camTarget:GetPivot() or camTarget.CFrame
				camera.CFrame = camera.CFrame:Lerp(desiredCFrame, 0.03)
			end
		else
			if camera.CameraType ~= Enum.CameraType.Custom then
				camera.CameraType = Enum.CameraType.Custom
				if player.Character and player.Character:FindFirstChild("Humanoid") then
					camera.CameraSubject = player.Character:FindFirstChild("Humanoid")
				end
			end
		end

		if not step._startTime then step._startTime = tick() end

		if step.duration and step.duration > 0 then
			if tick() - step._startTime >= step.duration then shared.AdvanceTutorialStep(true) end
		elseif step.duration == 0 then
			if MeetsStrictGates(step) and not activeFallbackStep then shared.AdvanceTutorialStep(true) 
			elseif step.failsafeDuration and (tick() - step._startTime >= step.failsafeDuration) then shared.AdvanceTutorialStep(true) end
		end
	end)
end

---------------------------------------------------------------
-- EXTERNAL ADVANCEMENT (Server or Local UI)
---------------------------------------------------------------
shared.AdvanceTutorialStep = function(forceAdvance)
	if isAdvancing then return end 
	if tutorialComplete then return end
	if activeFallbackStep then return end

	local currentStepData = TutorialConfig.GetStepByIndex(currentStepIndex)
	if currentStepData and currentStepData.duration ~= 0 and not forceAdvance then
		if not actionMatchedForAdvance then return end
	end

	actionMatchedForAdvance = false; lockedAura = nil 

	if currentStepData and currentStepData.duration == 0 and not forceAdvance then
		if not MeetsStrictGates(currentStepData) then return end
	end

	isAdvancing = true 

	if currentStepData then TutorialStepComplete:FireServer(currentStepData.id) end
	currentStepIndex += 1

	baselineCubes = liveStats.totalCubesProduced
	baselineShipped = liveStats.totalPlatformsShipped
	baselineGoldenAuras = player:GetAttribute("LiveGoldenAuras") or liveStats.goldenAuras
	for k, v in pairs(liveStats.boostsBought) do baselineBoostsBought[k] = v end
	for k, v in pairs(liveStats.boostsUsed) do baselineBoostsUsed[k] = v end

	local nextStep = TutorialConfig.GetStepByIndex(currentStepIndex)

	if not nextStep then
		tutorialComplete = true
		if activePointer then activePointer.Visible = false end
		if activeHighlight then activeHighlight.Visible = false end
		HideBanner()
		if trackingConnection then trackingConnection:Disconnect() end

		camera.CameraType = Enum.CameraType.Custom
		if player.Character and player.Character:FindFirstChild("Humanoid") then
			camera.CameraSubject = player.Character:FindFirstChild("Humanoid")
		end

		TutorialStepComplete:FireServer("__tutorialComplete__")

		local successSound = Instance.new("Sound")
		successSound.SoundId = "rbxassetid://4612385808"; successSound.Volume = 0.6
		successSound.Parent = game:GetService("SoundService"); successSound:Play()
		game:GetService("Debris"):AddItem(successSound, 4)
	end

	task.delay(0.1, function() isAdvancing = false end)
end

---------------------------------------------------------------
-- STATE RECONCILIATION & DATA SYNC
---------------------------------------------------------------
UpdateHUDBridge:Connect(function(stats)
	if stats.currency ~= nil then liveStats.currency = stats.currency end
	if stats.totalEarned ~= nil then liveStats.totalEarned = stats.totalEarned end
	if stats.farmEvaluation ~= nil then liveStats.farmEvaluation = stats.farmEvaluation end
	if stats.soulAuras ~= nil then liveStats.soulAuras = stats.soulAuras end
	if stats.goldenAuras ~= nil then liveStats.goldenAuras = stats.goldenAuras end
	if stats.prestigeCount ~= nil then liveStats.prestigeCount = stats.prestigeCount end
	if stats.currentArea ~= nil then liveStats.currentArea = stats.currentArea end

	if stats.pendingAuras ~= nil then liveStats.pendingAuras = stats.pendingAuras end
	if stats.habitatCapacity ~= nil then liveStats.habitatCapacity = stats.habitatCapacity end
	if stats.rate ~= nil then liveStats.rate = stats.rate end

	if stats.totalCubesProduced ~= nil then liveStats.totalCubesProduced = math.max(liveStats.totalCubesProduced, stats.totalCubesProduced) end
	if stats.totalPlatformsShipped ~= nil then liveStats.totalPlatformsShipped = math.max(liveStats.totalPlatformsShipped, stats.totalPlatformsShipped) end
	if stats.totalLegendaryCubes ~= nil then liveStats.totalLegendaryCubes = math.max(liveStats.totalLegendaryCubes, stats.totalLegendaryCubes) end
	if stats.piggyBank ~= nil then liveStats.piggyBank = stats.piggyBank end

	if stats.tutorialComplete ~= nil then tutorialComplete = stats.tutorialComplete end

	if stats.tutorialProgress and not tutorialComplete then
		local highestCompletedIndex = 0

		for index, stepData in ipairs(TutorialConfig.Steps) do
			if stats.tutorialProgress[stepData.id] then highestCompletedIndex = index end
		end

		if highestCompletedIndex >= currentStepIndex then
			currentStepIndex = highestCompletedIndex + 1

			baselineCubes = liveStats.totalCubesProduced
			baselineShipped = liveStats.totalPlatformsShipped
			baselineGoldenAuras = player:GetAttribute("LiveGoldenAuras") or liveStats.goldenAuras
			for k, v in pairs(liveStats.boostsBought) do baselineBoostsBought[k] = v end
			for k, v in pairs(liveStats.boostsUsed) do baselineBoostsUsed[k] = v end

			if not TutorialConfig.GetStepByIndex(currentStepIndex) then
				tutorialComplete = true
				if trackingConnection then trackingConnection:Disconnect() end
				if questBanner then HideBanner() end
				if activePointer then activePointer.Visible = false end
				if activeHighlight then activeHighlight.Visible = false end
			end
		end
	end
end)

---------------------------------------------------------------
-- BOOT & MENU GATE
---------------------------------------------------------------
task.spawn(function()
	local menuGate = ReplicatedStorage:WaitForChild("MenuDismissed", 10)
	if menuGate and not menuGate:GetAttribute("Fired") then menuGate.Event:Wait() end

	local character = player.Character or player.CharacterAdded:Wait()
	local humanoid = character:WaitForChild("Humanoid", 5)
	camera.CameraType = Enum.CameraType.Custom
	if humanoid then camera.CameraSubject = humanoid end

	tutorialActive = true
	InitTutorialUI()
	StartTrackingLoop()
end)

-- BoostController
-- Location: StarterPlayer > StarterPlayerScripts > BoostController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local AdminConfig = require(ReplicatedStorage.Modules.AdminConfig)
local SoundConfig = require(ReplicatedStorage.Modules.SoundConfig)
local BoostConfig = require(ReplicatedStorage.Modules.BoostConfig) 
local AchievementConfig = require(ReplicatedStorage.Modules.AchievementConfig)
local UITheme = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UITheme"))
local T = UITheme.Get("Custom")

local BuyBoost = ReplicatedStorage.RemoteEvents:WaitForChild("BuyBoost")
local ActivateBoost = ReplicatedStorage.RemoteEvents:WaitForChild("ActivateBoost")
local BoostUpdated = ReplicatedStorage.RemoteEvents:WaitForChild("BoostUpdated")
local BridgeNet2 = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))
local UpdateHUDBridge = BridgeNet2.ClientBridge("UpdateHUD")

local player = Players.LocalPlayer
local mainHUD = player:WaitForChild("PlayerGui"):WaitForChild("MainHUD")

local boostState = {}; local panelOpen = false; local liveGold = 0; local latestStats = {}
local activeTab = "Shop"

local function PlayUI(id) if shared.PlayUISound then shared.PlayUISound(id) end end
local function FormatTime(s) s = math.ceil(s or 0); if s <= 0 then return "0:00" end; return string.format("%d:%02d", math.floor(s/60), s % 60) end

---------------------------------------------------------------
-- ✨ MENU BUTTON
---------------------------------------------------------------
local BoostsBtn = Instance.new("ImageButton"); BoostsBtn.Name = "BoostsButton"; BoostsBtn.BackgroundColor3 = T.buttonPrimary; BoostsBtn.BorderSizePixel = 0; BoostsBtn.AutoButtonColor = false; BoostsBtn.ZIndex = 10
local Faded2 = mainHUD:FindFirstChild("Faded2")
if Faded2 then BoostsBtn.Parent = Faded2; BoostsBtn.Size = UDim2.new(0.85, 0, 0.85, 0); Instance.new("UIAspectRatioConstraint", BoostsBtn).AspectRatio = 1.0; local layout = Faded2:FindFirstChildOfClass("UIListLayout"); if not layout then layout = Instance.new("UIListLayout", Faded2); layout.HorizontalAlignment = Enum.HorizontalAlignment.Center; layout.VerticalAlignment = Enum.VerticalAlignment.Center; layout.Padding = UDim.new(0, 15); layout.SortOrder = Enum.SortOrder.LayoutOrder end; BoostsBtn.LayoutOrder = 3 
else BoostsBtn.Size = UDim2.new(0, 60, 0, 60); BoostsBtn.AnchorPoint = Vector2.new(1, 1); BoostsBtn.Position = UDim2.new(0.98, 0, 0.77, 0); BoostsBtn.Parent = mainHUD end
BoostsBtn:SetAttribute("TutorialTarget", "BoostsButton"); Instance.new("UICorner", BoostsBtn).CornerRadius = UDim.new(0.5, 0)
local bbStroke = Instance.new("UIStroke", BoostsBtn); bbStroke.Color = T.accentPurple; bbStroke.Thickness = 2
local boostIcon = Instance.new("ImageLabel", BoostsBtn); boostIcon.Size = UDim2.new(0.6, 0, 0.6, 0); boostIcon.Position = UDim2.new(0.2, 0, 0.2, 0); boostIcon.BackgroundTransparency = 1; boostIcon.ScaleType = Enum.ScaleType.Fit; boostIcon.Image = "rbxassetid://14916846070" 
CollectionService:AddTag(BoostsBtn, "Tutorial_BoostMenuBtn")

---------------------------------------------------------------
-- ✨ SHOP PANEL & TABS (Strictly Docked & Capped)
---------------------------------------------------------------
local ShopPanel = Instance.new("Frame"); ShopPanel.Name = "BoostShopPanel"
ShopPanel.Size = UDim2.new(0.9, 0, 0.60, 0) 
ShopPanel.AnchorPoint = Vector2.new(1, 1)
ShopPanel.Position = UDim2.new(1, -15, 2, 0) 
ShopPanel.BackgroundColor3 = T.panelBG; ShopPanel.BorderSizePixel = 0; ShopPanel.Visible = false; ShopPanel.ZIndex = 40; ShopPanel.ClipsDescendants = true; ShopPanel.Parent = mainHUD
CollectionService:AddTag(ShopPanel, "Tutorial_BoostShopPanel")
Instance.new("UICorner", ShopPanel).CornerRadius = UDim.new(0, 12)

-- ✨ THE FIX: MaxSize locked to 440 to fit under currency
Instance.new("UISizeConstraint", ShopPanel).MaxSize = Vector2.new(360, 440) 

local shopStroke = Instance.new("UIStroke", ShopPanel); shopStroke.Color = Color3.fromRGB(255, 255, 255); shopStroke.Thickness = 1.5 

local ShopHeader = Instance.new("Frame"); ShopHeader.Name = "TitleBar"; ShopHeader.Size = UDim2.new(1, 0, 0, 40); ShopHeader.BackgroundColor3 = T.headerBG; ShopHeader.BorderSizePixel = 0; ShopHeader.ZIndex = 41; ShopHeader.Parent = ShopPanel; Instance.new("UICorner", ShopHeader).CornerRadius = UDim.new(0, 12)
local ShopTitle = Instance.new("TextLabel"); ShopTitle.Size = UDim2.new(1, -50, 1, 0); ShopTitle.Position = UDim2.new(0, 14, 0, 0); ShopTitle.BackgroundTransparency = 1; ShopTitle.Text = "BOOSTS"; ShopTitle.TextColor3 = T.headerText; ShopTitle.TextScaled = true; ShopTitle.Font = T.font; ShopTitle.TextXAlignment = Enum.TextXAlignment.Left; ShopTitle.ZIndex = 42; ShopTitle.Parent = ShopHeader
local ShopClose = Instance.new("TextButton"); ShopClose.Size = UDim2.new(0, 28, 0, 28); ShopClose.Position = UDim2.new(1, -36, 0.5, -14); ShopClose.BackgroundColor3 = T.buttonRed; ShopClose.BorderSizePixel = 0; ShopClose.Text = "X"; ShopClose.TextColor3 = Color3.fromRGB(255, 255, 255); ShopClose.TextScaled = true; ShopClose.Font = T.font; ShopClose.ZIndex = 9999; ShopClose.Parent = ShopHeader
CollectionService:AddTag(ShopClose, "Tutorial_BoostShopClose"); Instance.new("UICorner", ShopClose).CornerRadius = UDim.new(0, 5)

local TabContainer = Instance.new("Frame", ShopPanel)
TabContainer.Size = UDim2.new(1, 0, 0, 40); TabContainer.Position = UDim2.new(0, 0, 0, 40); TabContainer.BackgroundColor3 = T.headerBG; TabContainer.BorderSizePixel = 0; TabContainer.ZIndex = 41
local TabListLayout = Instance.new("UIListLayout", TabContainer); TabListLayout.FillDirection = Enum.FillDirection.Horizontal; TabListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center; TabListLayout.VerticalAlignment = Enum.VerticalAlignment.Center; TabListLayout.Padding = UDim.new(0, 10)

local shopTabBtn = Instance.new("TextButton", TabContainer); shopTabBtn.Size = UDim2.new(0.45, 0, 0.7, 0); shopTabBtn.BackgroundColor3 = T.buttonSecondary; shopTabBtn.Text = "SHOP"; shopTabBtn.TextColor3 = T.bodyText; shopTabBtn.Font = T.font; shopTabBtn.TextScaled = true; Instance.new("UICorner", shopTabBtn).CornerRadius = UDim.new(0, 6)
local invTabBtn = Instance.new("TextButton", TabContainer); invTabBtn.Size = UDim2.new(0.45, 0, 0.7, 0); invTabBtn.BackgroundColor3 = T.buttonSecondary; invTabBtn.Text = "INVENTORY"; invTabBtn.TextColor3 = T.bodyText; invTabBtn.Font = T.font; invTabBtn.TextScaled = true; Instance.new("UICorner", invTabBtn).CornerRadius = UDim.new(0, 6)

CollectionService:AddTag(shopTabBtn, "Tutorial_BoostTab_Shop")
CollectionService:AddTag(invTabBtn, "Tutorial_BoostTab_Inventory")

local ShopScroll = Instance.new("ScrollingFrame", ShopPanel); ShopScroll.Name = "ShopScroll"; ShopScroll.Size = UDim2.new(1, 0, 1, -80); ShopScroll.Position = UDim2.new(0, 0, 0, 80); ShopScroll.BackgroundTransparency = 1; ShopScroll.BorderSizePixel = 0; ShopScroll.ScrollBarThickness = 6; ShopScroll.Visible = true; Instance.new("UIListLayout", ShopScroll).Padding = UDim.new(0, 8); local spad = Instance.new("UIPadding", ShopScroll); spad.PaddingTop = UDim.new(0,8); spad.PaddingLeft = UDim.new(0,8); spad.PaddingRight = UDim.new(0,8)
local InvScroll = Instance.new("ScrollingFrame", ShopPanel); InvScroll.Name = "InvScroll"; InvScroll.Size = UDim2.new(1, 0, 1, -80); InvScroll.Position = UDim2.new(0, 0, 0, 80); InvScroll.BackgroundTransparency = 1; InvScroll.BorderSizePixel = 0; InvScroll.ScrollBarThickness = 6; InvScroll.Visible = false; Instance.new("UIListLayout", InvScroll).Padding = UDim.new(0, 8); local ipad = Instance.new("UIPadding", InvScroll); ipad.PaddingTop = UDim.new(0,8); ipad.PaddingLeft = UDim.new(0,8); ipad.PaddingRight = UDim.new(0,8)

local function AddButtonJuice(btn)
	local scale = btn:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", btn)
	btn.MouseEnter:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15), {Scale = 1.05}):Play() end)
	btn.MouseLeave:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15), {Scale = 1}):Play() end)
	btn.MouseButton1Down:Connect(function() TweenService:Create(scale, TweenInfo.new(0.1), {Scale = 0.95}):Play() end)
	btn.MouseButton1Up:Connect(function() TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), {Scale = 1.05}):Play() end)
end
AddButtonJuice(BoostsBtn); AddButtonJuice(ShopClose); AddButtonJuice(shopTabBtn); AddButtonJuice(invTabBtn)

local function SetActiveTab(tabName)
	activeTab = tabName
	if tabName == "Shop" then
		shopTabBtn.BackgroundColor3 = T.buttonPrimary; shopTabBtn.TextColor3 = T.bodyText
		invTabBtn.BackgroundColor3 = T.buttonSecondary; invTabBtn.TextColor3 = T.subText
		ShopScroll.Visible = true; InvScroll.Visible = false
	else
		shopTabBtn.BackgroundColor3 = T.buttonSecondary; shopTabBtn.TextColor3 = T.subText
		invTabBtn.BackgroundColor3 = T.buttonPrimary; invTabBtn.TextColor3 = T.bodyText
		ShopScroll.Visible = false; InvScroll.Visible = true
	end
end
SetActiveTab("Shop") 

shopTabBtn.MouseButton1Down:Connect(function()
	if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_BoostTab_Shop") then return end
	PlayUI(SoundConfig.UIClick or ""); SetActiveTab("Shop")
	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
end)
invTabBtn.MouseButton1Down:Connect(function()
	if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_BoostTab_Inventory") then return end
	PlayUI(SoundConfig.UIClick or ""); SetActiveTab("Inventory")
	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
end)

local cardRefs = {}

local function BuildCards()
	for i, boostId in ipairs(BoostConfig.ShopOrder) do
		local cfg = BoostConfig.Get(boostId); if not cfg then continue end; local color = cfg.color

		local sCard = Instance.new("Frame", ShopScroll); sCard.Size = UDim2.new(1, -8, 0, 75); sCard.BackgroundColor3 = T.cardBG; sCard.BorderSizePixel = 0; Instance.new("UICorner", sCard).CornerRadius = UDim.new(0, 8)
		local sIcon = Instance.new("ImageLabel", sCard); sIcon.Size = UDim2.new(0, 36, 0, 36); sIcon.Position = UDim2.new(0, 10, 0.5, -18); sIcon.BackgroundTransparency = 1; sIcon.Image = cfg.icon or ""; sIcon.ImageColor3 = color; sIcon.ScaleType = Enum.ScaleType.Fit
		local sName = Instance.new("TextLabel", sCard); sName.Size = UDim2.new(0.5, 0, 0, 18); sName.Position = UDim2.new(0, 56, 0, 10); sName.BackgroundTransparency = 1; sName.Text = string.upper(cfg.displayName or boostId); sName.TextColor3 = T.bodyText; sName.TextScaled = true; sName.Font = T.font; sName.TextXAlignment = Enum.TextXAlignment.Left
		local sDesc = Instance.new("TextLabel", sCard); sDesc.Size = UDim2.new(0.5, 0, 0, 30); sDesc.Position = UDim2.new(0, 56, 0, 30); sDesc.BackgroundTransparency = 1; sDesc.Text = cfg.description or ""; sDesc.TextColor3 = T.subText; sDesc.TextScaled = true; sDesc.TextWrapped = true; sDesc.Font = T.fontBody; sDesc.TextXAlignment = Enum.TextXAlignment.Left; sDesc.TextYAlignment = Enum.TextYAlignment.Top

		local buyBtn = Instance.new("TextButton", sCard); buyBtn.Size = UDim2.new(0, 75, 0, 34); buyBtn.Position = UDim2.new(1, -85, 0.5, -17); buyBtn.BackgroundColor3 = T.buttonGreen; buyBtn.BorderSizePixel = 0; buyBtn.TextScaled = true; buyBtn.Font = T.font; buyBtn.TextColor3 = Color3.fromRGB(255, 255, 255); Instance.new("UICorner", buyBtn).CornerRadius = UDim.new(0, 6); CollectionService:AddTag(buyBtn, "Tutorial_BuyBoost_" .. boostId); AddButtonJuice(buyBtn)

		local iCard = Instance.new("Frame", InvScroll); iCard.Size = UDim2.new(1, -8, 0, 75); iCard.BackgroundColor3 = T.cardBG; iCard.BorderSizePixel = 0; Instance.new("UICorner", iCard).CornerRadius = UDim.new(0, 8)
		local iIcon = Instance.new("ImageLabel", iCard); iIcon.Size = UDim2.new(0, 36, 0, 36); iIcon.Position = UDim2.new(0, 10, 0.5, -18); iIcon.BackgroundTransparency = 1; iIcon.Image = cfg.icon or ""; iIcon.ImageColor3 = color; iIcon.ScaleType = Enum.ScaleType.Fit
		local iName = Instance.new("TextLabel", iCard); iName.Size = UDim2.new(0.5, 0, 0, 18); iName.Position = UDim2.new(0, 56, 0, 10); iName.BackgroundTransparency = 1; iName.Text = string.upper(cfg.displayName or boostId); iName.TextColor3 = T.bodyText; iName.TextScaled = true; iName.Font = T.font; iName.TextXAlignment = Enum.TextXAlignment.Left

		local iOwned = Instance.new("TextLabel", iCard); iOwned.Size = UDim2.new(0.5, 0, 0, 14); iOwned.Position = UDim2.new(0, 56, 0, 30); iOwned.BackgroundTransparency = 1; iOwned.Text = "Owned: 0"; iOwned.TextColor3 = T.accentGold; iOwned.TextScaled = true; iOwned.Font = T.fontBody; iOwned.TextXAlignment = Enum.TextXAlignment.Left
		local iStatus = Instance.new("TextLabel", iCard); iStatus.Size = UDim2.new(0.5, 0, 0, 14); iStatus.Position = UDim2.new(0, 56, 0, 46); iStatus.BackgroundTransparency = 1; iStatus.Text = "Inactive"; iStatus.TextColor3 = T.subText; iStatus.TextScaled = true; iStatus.Font = T.fontBody; iStatus.TextXAlignment = Enum.TextXAlignment.Left

		local iTimer = Instance.new("TextLabel", iCard); iTimer.Size = UDim2.new(0, 65, 0, 30); iTimer.Position = UDim2.new(1, -160, 0.5, -15); iTimer.BackgroundTransparency = 1; iTimer.Text = ""; iTimer.TextColor3 = color; iTimer.TextScaled = true; iTimer.Font = Enum.Font.FredokaOne; iTimer.TextXAlignment = Enum.TextXAlignment.Right

		local actBtn = Instance.new("TextButton", iCard); actBtn.Size = UDim2.new(0, 75, 0, 34); actBtn.Position = UDim2.new(1, -85, 0.5, -17); actBtn.BackgroundColor3 = color; actBtn.BorderSizePixel = 0; actBtn.TextScaled = true; actBtn.Font = T.font; actBtn.TextColor3 = Color3.fromRGB(255, 255, 255); Instance.new("UICorner", actBtn).CornerRadius = UDim.new(0, 6); CollectionService:AddTag(actBtn, "Tutorial_UseBoost_" .. boostId); AddButtonJuice(actBtn)

		cardRefs[boostId] = { sCard=sCard, iCard=iCard, buyBtn=buyBtn, actBtn=actBtn, sDesc=sDesc, iOwned=iOwned, iStatus=iStatus, iTimer=iTimer }

		buyBtn.MouseButton1Down:Connect(function() 
			if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_BuyBoost_" .. boostId) then return end
			local isUnlocked = AchievementConfig.IsBoostUnlocked(boostId, latestStats)
			local cost = cfg and cfg.cost or 0
			if not isUnlocked or liveGold < cost then PlayUI(SoundConfig.ErrorBuzz or ""); return end
			BuyBoost:FireServer(boostId) 
			if type(shared.TutorialRecordBoostBought) == "function" then shared.TutorialRecordBoostBought(boostId) end
			if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
		end)

		actBtn.MouseButton1Down:Connect(function()
			if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_UseBoost_" .. boostId) then return end
			local isUnlocked = AchievementConfig.IsBoostUnlocked(boostId, latestStats)
			local state = boostState[boostId]
			local activeCount = state and (state.activeCount or 0) or 0
			local atCap = activeCount >= (cfg and cfg.maxStack or 1)
			if not isUnlocked or not state or (state.inventoryCount or 0) <= 0 or atCap then PlayUI(SoundConfig.ErrorBuzz or ""); return end
			ActivateBoost:FireServer(boostId)
			if type(shared.TutorialRecordBoostUsed) == "function" then shared.TutorialRecordBoostUsed(boostId) end
			if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
		end)
	end
end

BuildCards()

local function RefreshCards()
	for boostId, refs in pairs(cardRefs) do
		local cfg = BoostConfig.Get(boostId); local state = boostState[boostId]
		local isUnlocked, lockReason = AchievementConfig.IsBoostUnlocked(boostId, latestStats)
		local cost = cfg and cfg.cost or 0; local canAfford = liveGold >= cost
		local invCount = state and (state.inventoryCount or 0) or 0

		if not isUnlocked then
			refs.buyBtn.Text = "LOCKED"; refs.buyBtn.BackgroundColor3 = T.buttonRed; refs.buyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
			refs.sDesc.Text = lockReason; refs.sDesc.TextColor3 = T.buttonRed
		else
			refs.sDesc.Text = cfg.description or ""; refs.sDesc.TextColor3 = T.subText
			refs.buyBtn.Text = cost .. " ⭐"; refs.buyBtn.TextColor3 = Color3.fromRGB(255, 255, 255); refs.buyBtn.BackgroundColor3 = canAfford and T.buttonGreen or T.buttonDisabled
		end

		refs.iOwned.Text = "Owned: " .. invCount
		refs.iOwned.TextColor3 = invCount > 0 and T.accentGold or T.subText
	end
end

local function OpenPanel()
	panelOpen = true; ShopPanel.Visible = true; RefreshCards()
	-- ✨ THE FIX: Tucked nicely on the screen's bottom edge (-15)
	TweenService:Create(ShopPanel, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(1, -15, 1, -15) }):Play()
end

local function ClosePanel()
	panelOpen = false; PlayUI(SoundConfig.UIClose)
	local tween = TweenService:Create(ShopPanel, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.new(1, -15, 2, 0) })
	tween:Play(); tween.Completed:Once(function() if not panelOpen then ShopPanel.Visible = false end end)
end

BoostsBtn.MouseButton1Down:Connect(function() 
	if panelOpen then if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_CloseBoostShop") then return end; ClosePanel()
	else if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_OpenBoostShop") then return end; OpenPanel() end 
	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
end)
ShopClose.MouseButton1Down:Connect(function()
	if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_CloseBoostShop") then return end; ClosePanel()
	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
end)

BoostUpdated.OnClientEvent:Connect(function(state)
	if state._goldenAuras ~= nil then liveGold = state._goldenAuras; state._goldenAuras = nil end
	boostState = state; if panelOpen then RefreshCards() end
end)

UpdateHUDBridge:Connect(function(stats)
	for key, value in pairs(stats) do latestStats[key] = value end
	if stats.goldenAuras ~= nil then liveGold = stats.goldenAuras end
	if stats.boostInventory then for boostId, count in pairs(stats.boostInventory) do if boostState[boostId] then boostState[boostId].inventoryCount = count end end end
	if panelOpen then RefreshCards() end
end)

RunService.RenderStepped:Connect(function(dt)
	-- Auto-skim past Step 33 if the Shop is already Open!
	if panelOpen and type(shared.TutorialCanPerform) == "function" and shared.TutorialCanPerform("Action_OpenBoostShop") then
		if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
	end

	for _, boostId in ipairs(BoostConfig.ShopOrder) do
		local state = boostState[boostId]; local refs = cardRefs[boostId]; if not refs then continue end
		local activeCount, minTime = 0, 0

		if state and state.activeTimes and #state.activeTimes > 0 then
			local clean = {}; minTime = math.huge
			for _, t in ipairs(state.activeTimes) do
				local newT = math.max(0, t - dt)
				if newT > 0 then table.insert(clean, newT); if newT < minTime then minTime = newT end end
			end
			state.activeTimes = clean; state.activeCount = #clean; activeCount = #clean
		end

		local isUnlocked = AchievementConfig.IsBoostUnlocked(boostId, latestStats)
		if not isUnlocked then
			refs.actBtn.Text = "LOCKED"; refs.actBtn.BackgroundColor3 = T.buttonRed; refs.actBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
			refs.iStatus.Text = "Unlock in Progression Menu"; refs.iStatus.TextColor3 = T.buttonRed
			refs.iTimer.Text = ""
		else
			local invCount = state and (state.inventoryCount or 0) or 0
			local atCap = activeCount >= (BoostConfig.Get(boostId).maxStack or 1)

			if activeCount > 0 then 
				refs.iStatus.Text = "Active" .. (activeCount > 1 and (" (x"..activeCount..")") or "")
				refs.iStatus.TextColor3 = BoostConfig.Get(boostId).color
				refs.iTimer.Text = FormatTime(minTime)
			else 
				refs.iStatus.Text = "Inactive"
				refs.iStatus.TextColor3 = T.subText 
				refs.iTimer.Text = ""
			end

			if invCount <= 0 then 
				refs.actBtn.Text = "NO STOCK"; refs.actBtn.BackgroundColor3 = T.buttonDisabled; refs.actBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
			elseif atCap then 
				refs.actBtn.Text = "MAXED"; refs.actBtn.BackgroundColor3 = T.buttonDisabled; refs.actBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
			else 
				refs.actBtn.Text = "ACTIVATE"; refs.actBtn.BackgroundColor3 = BoostConfig.Get(boostId).color; refs.actBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
			end
		end
	end
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- ✨ REFRESH LOOK (Matches your ShopController flair and stroke)
-- ─────────────────────────────────────────────────────────────────────────────
local shopShine    = nil
local titleFlair   = nil
local flairedExtra = false

local function RefreshLook()
	UITheme.Apply(ShopPanel, "Panel")
	UITheme.Apply(ShopHeader, "TitleBar")

	if not shopShine then
		shopShine  = UITheme.ApplyShine(ShopPanel)
		UITheme.ApplyShine(ShopHeader)
	end

	if not titleFlair then
		titleFlair = UITheme.ApplyFlair(ShopTitle, "Ghost")
	end

	if not flairedExtra then flairedExtra = true end

	for _, scrollName in ipairs({ "ShopScroll", "InvScroll" }) do
		local scroll = ShopPanel:FindFirstChild(scrollName)
		if scroll then
			local layout = scroll:FindFirstChildOfClass("UIListLayout")
			if layout then layout.SortOrder = Enum.SortOrder.LayoutOrder end
		end
	end

	local outerStroke = ShopPanel:FindFirstChildWhichIsA("UIStroke")
	if outerStroke then outerStroke.Color = Color3.fromRGB(255, 255, 255) end

	for _, card in ipairs(ShopScroll:GetChildren()) do if card:IsA("Frame") then UITheme.Apply(card, "ShopCard") end end
	for _, card in ipairs(InvScroll:GetChildren()) do if card:IsA("Frame") then UITheme.Apply(card, "ShopCard") end end
end

task.wait(2)
RefreshLook()

local forceClose = ReplicatedStorage:FindFirstChild("ForceCloseUI") or Instance.new("BindableEvent")
forceClose.Name = "ForceCloseUI"; forceClose.Parent = ReplicatedStorage
forceClose.Event:Connect(function() if panelOpen then ClosePanel() end end)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local UITheme = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UITheme"))
local T = UITheme.Get("Custom")
local SoundConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SoundConfig"))
local AchievementConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("AchievementConfig"))
local TierConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("TierConfig"))
local Formatter = require(ReplicatedStorage.Modules.NumberFormatter)
local BridgeNet2 = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))
local UpdateHUDBridge = BridgeNet2.ClientBridge("UpdateHUD")

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local ClaimChallenge = RemoteEvents:WaitForChild("ClaimChallenge")
local ClaimAuraIndex = RemoteEvents:WaitForChild("ClaimAuraIndex")
local ClaimBadge = RemoteEvents:WaitForChild("ClaimBadge")
local AuraDiscovered = RemoteEvents:WaitForChild("AuraDiscovered", 5)

local SettingsChanged = ReplicatedStorage:FindFirstChild("SettingsChanged") or Instance.new("BindableEvent")
SettingsChanged.Name = "SettingsChanged"; SettingsChanged.Parent = ReplicatedStorage

local player = Players.LocalPlayer
local mainHUD = player:WaitForChild("PlayerGui"):WaitForChild("MainHUD")
local Faded2 = mainHUD:WaitForChild("Faded2") 

local panelOpen, activeTab, activeTabText = false, "Challenges", "Boosts"
local latestStats = {}
local sfxEnabled, musicEnabled, jumpEnabled = true, true, true 
local liveSoulAuras, liveRunEarnings, liveRate, livePrestiges = 0, 0, 0, 0
local toggleRefs, statValueRefs = {}, {}

local function PlayUI(id) if shared.PlayUISound then shared.PlayUISound(id) end end

local AreaAuraNames = { [1] = {"Gear", "Screw", "Tin Can", "Old Tire", "Intact Radio"}, [2] = {"Rusted Nail", "Scrap Pipe", "Bent Gear", "Engine Scrap", "Corroded Core"} }
for i=3,20 do AreaAuraNames[i] = {"Common", "Uncommon", "Rare", "Epic", "Legendary"} end

local function PlayClaimVFX(rowFrame)
	PlayUI(SoundConfig.MaxOut or "rbxassetid://4612385808")
	local flash = Instance.new("Frame", rowFrame); flash.Size = UDim2.new(1,0,1,0); flash.BackgroundColor3 = Color3.fromRGB(255, 255, 255); flash.ZIndex = 50; flash.BorderSizePixel = 0
	Instance.new("UICorner", flash).CornerRadius = UDim.new(0, 8)
	TweenService:Create(flash, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 1}):Play()
	task.delay(0.4, function() flash:Destroy() end)
	for i = 1, 8 do
		local particle = Instance.new("Frame", rowFrame); particle.Size = UDim2.new(0, 10, 0, 10); particle.BackgroundColor3 = T.accentGold; particle.AnchorPoint = Vector2.new(0.5, 0.5); particle.Position = UDim2.new(0.5, 0, 0.5, 0); particle.ZIndex = 51; Instance.new("UICorner", particle).CornerRadius = UDim.new(1, 0)
		local angle = math.rad(math.random(0, 360)); local dist = math.random(30, 80); local endPos = UDim2.new(0.5, math.cos(angle)*dist, 0.5, math.sin(angle)*dist)
		TweenService:Create(particle, TweenInfo.new(0.5, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), {Position = endPos, Size = UDim2.new(0,0,0,0), BackgroundTransparency = 1}):Play()
		task.delay(0.5, function() particle:Destroy() end)
	end
end

local AchieveBtn = Instance.new("ImageButton", Faded2); AchieveBtn.Name = "AchievementButton"; AchieveBtn.Size = UDim2.new(0.85, 0, 0.85, 0); AchieveBtn.BackgroundColor3 = T.buttonSecondary; AchieveBtn.BorderSizePixel = 0; AchieveBtn.LayoutOrder = 1; Instance.new("UICorner", AchieveBtn).CornerRadius = UDim.new(0.5, 0); Instance.new("UIAspectRatioConstraint", AchieveBtn).AspectRatio = 1.0; local btnStroke = Instance.new("UIStroke", AchieveBtn); btnStroke.Color = T.accentGold; btnStroke.Thickness = 1; local btnIcon = Instance.new("ImageLabel", AchieveBtn); btnIcon.Size = UDim2.new(0.7, 0, 0.7, 0); btnIcon.Position = UDim2.new(0.15, 0, 0.15, 0); btnIcon.BackgroundTransparency = 1; btnIcon.ScaleType = Enum.ScaleType.Fit; btnIcon.Image = "rbxassetid://14923131909"
CollectionService:AddTag(AchieveBtn, "Tutorial_AchieveMenuBtn")

local Panel = Instance.new("Frame", mainHUD); Panel.Name = "AchievementPanel"; Panel.Size = UDim2.new(0.85, 0, 0.75, 0); Panel.Position = UDim2.new(0.5, 0, 0.5, 0); Panel.AnchorPoint = Vector2.new(0.5, 0.5); Panel.BackgroundColor3 = T.panelBG; Panel.BorderSizePixel = 0; Panel.Visible = false; Panel.ZIndex = 40; Panel.ClipsDescendants = true; Instance.new("UICorner", Panel).CornerRadius = UDim.new(0, 12); Instance.new("UISizeConstraint", Panel).MaxSize = Vector2.new(500, 550); local panelStroke = Instance.new("UIStroke", Panel); panelStroke.Color = T.panelStroke; panelStroke.Thickness = 2
CollectionService:AddTag(Panel, "Tutorial_AchievePanel")

local Header = Instance.new("Frame", Panel); Header.Size = UDim2.new(1, 0, 0, 44); Header.BackgroundColor3 = T.headerBG; Header.BorderSizePixel = 0; Header.ZIndex = 41
local TitleLabel = Instance.new("TextLabel", Header); TitleLabel.Size = UDim2.new(1, -50, 1, 0); TitleLabel.Position = UDim2.new(0, 14, 0, 0); TitleLabel.BackgroundTransparency = 1; TitleLabel.Text = "MENU"; TitleLabel.TextColor3 = T.headerText; TitleLabel.TextScaled = true; TitleLabel.Font = T.font; TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
local CloseBtn = Instance.new("TextButton", Header); CloseBtn.Size = UDim2.new(0, 28, 0, 28); CloseBtn.Position = UDim2.new(1, -36, 0.5, -14); CloseBtn.BackgroundColor3 = T.buttonRed; CloseBtn.Text = "X"; CloseBtn.TextColor3 = T.headerText; CloseBtn.TextScaled = true; CloseBtn.Font = T.font; Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 5); CloseBtn.ZIndex = 9999
CollectionService:AddTag(CloseBtn, "Tutorial_AchieveCloseBtn")

local TabContainer = Instance.new("Frame", Panel); TabContainer.Size = UDim2.new(1, 0, 0, 75); TabContainer.Position = UDim2.new(0, 0, 0, 44); TabContainer.BackgroundTransparency = 1; TabContainer.ZIndex = 41
local HoverLabel = Instance.new("TextLabel", TabContainer); HoverLabel.Size = UDim2.new(1, 0, 0, 20); HoverLabel.Position = UDim2.new(0, 0, 1, -15); HoverLabel.BackgroundTransparency = 1; HoverLabel.Text = "Boosts"; HoverLabel.TextColor3 = T.bodyText; HoverLabel.TextScaled = true; HoverLabel.Font = T.font
local TabButtonFrame = Instance.new("Frame", TabContainer); TabButtonFrame.Size = UDim2.new(1, 0, 1, -20); TabButtonFrame.BackgroundTransparency = 1; local TabListLayout = Instance.new("UIListLayout", TabButtonFrame); TabListLayout.FillDirection = Enum.FillDirection.Horizontal; TabListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center; TabListLayout.VerticalAlignment = Enum.VerticalAlignment.Center; TabListLayout.Padding = UDim.new(0, 12)

local tabBtns, scrolls = {}, {}
local function MakeTab(name, hoverText, iconId)
	local btn = Instance.new("ImageButton", TabButtonFrame); btn.Size = UDim2.new(0, 45, 0, 45); btn.BackgroundColor3 = T.buttonSecondary; btn.AutoButtonColor = false; Instance.new("UICorner", btn).CornerRadius = UDim.new(0.5, 0); local tStroke = Instance.new("UIStroke", btn); tStroke.Color = T.panelStroke; tStroke.Thickness = 2; local icon = Instance.new("ImageLabel", btn); icon.Size = UDim2.new(0.6, 0, 0.6, 0); icon.Position = UDim2.new(0.2, 0, 0.2, 0); icon.BackgroundTransparency = 1; icon.ScaleType = Enum.ScaleType.Fit; icon.Image = iconId; tabBtns[name] = {btn = btn, stroke = tStroke}; CollectionService:AddTag(btn, "Tutorial_AchieveTab_" .. name)

	if name ~= "Leaderboard" then
		local sf = Instance.new("ScrollingFrame", Panel); sf.Size = UDim2.new(1, -20, 1, -135); sf.Position = UDim2.new(0, 10, 0, 125); sf.BackgroundTransparency = 1; sf.BorderSizePixel = 0; sf.ScrollBarThickness = 4; sf.Visible = false; local layout = Instance.new("UIListLayout", sf); layout.Padding = UDim.new(0, 8); layout.HorizontalAlignment = Enum.HorizontalAlignment.Center; layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function() sf.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 10) end); scrolls[name] = sf
	end

	btn.MouseEnter:Connect(function() HoverLabel.Text = hoverText end); btn.MouseLeave:Connect(function() HoverLabel.Text = activeTabText end)
	btn.MouseButton1Down:Connect(function()
		if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_ClickAchieveTab_" .. name) then return end
		PlayUI(SoundConfig.UIClick or ""); activeTab = name; activeTabText = hoverText; HoverLabel.Text = activeTabText
		for k, t in pairs(tabBtns) do t.btn.BackgroundColor3 = (k == name) and T.accentGold or T.buttonSecondary; t.stroke.Color = (k == name) and T.bodyText or T.panelStroke end
		for k, s in pairs(scrolls) do s.Visible = (k == name) end
		TitleLabel.Text = (name == "Settings") and "SETTINGS" or "PROGRESSION"
		if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
	end)
end

MakeTab("Challenges", "Boosts", "rbxassetid://14916846070"); MakeTab("Index", "Auras", "rbxassetid://14916846070"); MakeTab("Badges", "Badges", "rbxassetid://14916846070"); MakeTab("Leaderboard", "Leaderboard", "rbxassetid://14916846070"); MakeTab("Settings", "Settings", "rbxassetid://14923131909") 

-- ✨ INJECT LEADERBOARD SUB-TABS & DATA (Completely separated Vertical Layout)
local lbWrapper = Instance.new("Frame", Panel)
lbWrapper.Name = "LeaderboardWrapper"
lbWrapper.Size = UDim2.new(1, -20, 1, -135)
lbWrapper.Position = UDim2.new(0, 10, 0, 125)
lbWrapper.BackgroundTransparency = 1
lbWrapper.Visible = false
scrolls["Leaderboard"] = lbWrapper 

local lbSubTabContainer = Instance.new("Frame", lbWrapper)
lbSubTabContainer.Name = "SubTabContainer"
lbSubTabContainer.Size = UDim2.new(0, 55, 1, 0)
lbSubTabContainer.BackgroundTransparency = 1

local lbSubTabLayout = Instance.new("UIListLayout", lbSubTabContainer)
lbSubTabLayout.FillDirection = Enum.FillDirection.Vertical
lbSubTabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
lbSubTabLayout.VerticalAlignment = Enum.VerticalAlignment.Top
lbSubTabLayout.Padding = UDim.new(0, 15)

-- The actual scrolling area for the rows now sits to the right of the buttons!
local lbScroll = Instance.new("ScrollingFrame", lbWrapper)
lbScroll.Size = UDim2.new(1, -65, 1, 0)
lbScroll.Position = UDim2.new(0, 65, 0, 0)
lbScroll.BackgroundTransparency = 1
lbScroll.BorderSizePixel = 0
lbScroll.ScrollBarThickness = 4

local lbContentLayout = Instance.new("UIListLayout", lbScroll)
lbContentLayout.Padding = UDim.new(0, 8)
lbContentLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

lbContentLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	lbScroll.CanvasSize = UDim2.new(0, 0, 0, lbContentLayout.AbsoluteContentSize.Y + 10)
end)

local activeLbTab = "Auras Generated"
local lbSubBtns = {}

local function BuildLeaderboardRows(tabName)
	for _, child in ipairs(lbScroll:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end

	local data = {}
	if tabName == "Top 10" then
		data = {
			{rank=1, name="MoldySugar2205", val="999.9M Soul Auras"},
			{rank=2, name="MoldySugar2205", val="50.2M Soul Auras"},
			{rank=3, name="MoldySugar2205", val="10.5M Soul Auras"},
			{rank=4, name="MoldySugar2205", val="5.1M Soul Auras"},
			{rank=5, name="MoldySugar2205", val="2.0M Soul Auras"},
		}
	elseif tabName == "Auras Generated" then
		data = {
			{rank=1, name="MoldySugar2205", val="5.2B Auras"},
			{rank=2, name="MoldySugar2205", val="1.1B Auras"},
			{rank=3, name="MoldySugar2205", val="800M Auras"},
			{rank=4, name="MoldySugar2205", val="500M Auras"},
			{rank=5, name="MoldySugar2205", val="150M Auras"},
		}
	elseif tabName == "Most Money Made" then
		data = {
			{rank=1, name="MoldySugar2205", val="$999.9B"},
			{rank=2, name="MoldySugar2205", val="$500.5B"},
			{rank=3, name="MoldySugar2205", val="$150.0B"},
			{rank=4, name="MoldySugar2205", val="$50.0B"},
			{rank=5, name="MoldySugar2205", val="$10.0B"},
		}
	end

	for i, p in ipairs(data) do
		local row = Instance.new("Frame", lbScroll)
		row.Size = UDim2.new(1, 0, 0, 45)
		row.BackgroundColor3 = T.cardBG
		Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)

		-- ✨ PERFECT TEXT SCALING & WRAPPING
		local rankLbl = Instance.new("TextLabel", row)
		rankLbl.Size = UDim2.new(0, 40, 1, 0)
		rankLbl.Position = UDim2.new(0, 10, 0, 0)
		rankLbl.BackgroundTransparency = 1
		rankLbl.Text = "#" .. p.rank
		rankLbl.TextColor3 = (p.rank==1) and Color3.fromRGB(255,215,0) or ((p.rank==2) and Color3.fromRGB(192,192,192) or ((p.rank==3) and Color3.fromRGB(205,127,50) or T.subText))
		rankLbl.Font = Enum.Font.GothamBold
		rankLbl.TextScaled = true
		rankLbl.TextWrapped = true
		local rConstraint = Instance.new("UITextSizeConstraint", rankLbl); rConstraint.MaxTextSize = 22

		local nameLbl = Instance.new("TextLabel", row)
		nameLbl.Size = UDim2.new(0.45, -50, 1, 0)
		nameLbl.Position = UDim2.new(0, 60, 0, 0)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Text = p.name
		nameLbl.TextColor3 = T.bodyText
		nameLbl.Font = Enum.Font.GothamMedium
		nameLbl.TextScaled = true
		nameLbl.TextWrapped = true
		nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		local nConstraint = Instance.new("UITextSizeConstraint", nameLbl); nConstraint.MaxTextSize = 18

		local valLbl = Instance.new("TextLabel", row)
		valLbl.Size = UDim2.new(0.55, -20, 1, 0)
		valLbl.Position = UDim2.new(0.45, 10, 0, 0)
		valLbl.BackgroundTransparency = 1
		valLbl.Text = p.val
		valLbl.TextColor3 = T.accentGold
		valLbl.Font = Enum.Font.GothamBold
		valLbl.TextScaled = true
		valLbl.TextWrapped = true
		valLbl.TextXAlignment = Enum.TextXAlignment.Right
		local vConstraint = Instance.new("UITextSizeConstraint", valLbl); vConstraint.MaxTextSize = 18

		UITheme.Apply(row, "Card")
	end
end

local function MakeLbSubTab(tabName, iconId)
	local btn = Instance.new("ImageButton", lbSubTabContainer)
	btn.Size = UDim2.new(0, 45, 0, 45)
	btn.BackgroundColor3 = (tabName == activeLbTab) and T.accentGold or T.buttonSecondary
	btn.AutoButtonColor = false
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0.5, 0)

	local tStroke = Instance.new("UIStroke", btn)
	tStroke.Color = (tabName == activeLbTab) and T.bodyText or T.panelStroke
	tStroke.Thickness = 2

	local icon = Instance.new("ImageLabel", btn)
	icon.Size = UDim2.new(0.6, 0, 0.6, 0)
	icon.Position = UDim2.new(0.2, 0, 0.2, 0)
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = iconId

	CollectionService:AddTag(btn, "Tutorial_LbTab_" .. string.gsub(tabName, " ", ""))
	lbSubBtns[tabName] = {btn = btn, stroke = tStroke}

	btn.MouseEnter:Connect(function() HoverLabel.Text = tabName end)
	btn.MouseLeave:Connect(function() HoverLabel.Text = activeTabText end)

	btn.MouseButton1Down:Connect(function()
		if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_ClickLbTab_" .. string.gsub(tabName, " ", "")) then return end
		PlayUI(SoundConfig.UIClick or "")
		activeLbTab = tabName
		HoverLabel.Text = tabName
		for k, t in pairs(lbSubBtns) do
			t.btn.BackgroundColor3 = (k == tabName) and T.accentGold or T.buttonSecondary
			t.stroke.Color = (k == tabName) and T.bodyText or T.panelStroke
		end
		BuildLeaderboardRows(activeLbTab)
		if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
	end)

	local scale = Instance.new("UIScale", btn)
	btn.MouseEnter:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15), {Scale = 1.05}):Play() end)
	btn.MouseLeave:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15), {Scale = 1}):Play() end)
	btn.MouseButton1Down:Connect(function() TweenService:Create(scale, TweenInfo.new(0.1), {Scale = 0.95}):Play() end)
	btn.MouseButton1Up:Connect(function() TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), {Scale = 1.05}):Play() end)
end

MakeLbSubTab("Top 10", "rbxassetid://14916846070") -- Star
MakeLbSubTab("Auras Generated", "rbxassetid://4483362458") -- Aura
MakeLbSubTab("Most Money Made", "rbxassetid://14924185885") -- Cash

BuildLeaderboardRows(activeLbTab)
-- ✨ END LEADERBOARD INJECTION

local setScroll = scrolls["Settings"]; local pad = Instance.new("UIPadding", setScroll); pad.PaddingTop = UDim.new(0, 5)
local function MakeToggleRow(labelText, settingKey)
	local row = Instance.new("Frame", setScroll); row.Size = UDim2.new(1, -10, 0, 42); row.BackgroundColor3 = T.cardBG; row.BorderSizePixel = 0; row.ZIndex = 41; Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)
	local lbl = Instance.new("TextLabel", row); lbl.Size = UDim2.new(0.6, 0, 1, 0); lbl.Position = UDim2.new(0, 15, 0, 0); lbl.BackgroundTransparency = 1; lbl.Text = labelText; lbl.TextColor3 = T.subText; lbl.TextScaled = true; lbl.Font = T.fontBody; lbl.TextXAlignment = Enum.TextXAlignment.Left
	local toggle = Instance.new("TextButton", row); toggle.Size = UDim2.new(0, 60, 0, 30); toggle.Position = UDim2.new(1, -70, 0.5, -15); toggle.BorderSizePixel = 0; toggle.TextScaled = true; toggle.Font = T.font; Instance.new("UICorner", toggle).CornerRadius = UDim.new(0, 6); CollectionService:AddTag(toggle, "Tutorial_SettingToggle_" .. settingKey)
	local function Refresh(isOn) toggle.Text = isOn and "ON" or "OFF"; toggle.TextColor3 = T.bodyText; toggle.BackgroundColor3 = isOn and T.buttonGreen or T.buttonRed end
	local isOn = true; if settingKey == "sfx" then isOn = sfxEnabled elseif settingKey == "music" then isOn = musicEnabled elseif settingKey == "jump" then isOn = jumpEnabled end
	Refresh(isOn); toggleRefs[settingKey] = Refresh
	toggle.MouseButton1Down:Connect(function()
		if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_ToggleSetting_" .. settingKey) then return end
		PlayUI(SoundConfig.UIClick or ""); if settingKey == "sfx" then sfxEnabled = not sfxEnabled; isOn = sfxEnabled elseif settingKey == "music" then musicEnabled = not musicEnabled; isOn = musicEnabled elseif settingKey == "jump" then jumpEnabled = not jumpEnabled; isOn = jumpEnabled end
		Refresh(isOn); SettingsChanged:Fire(settingKey, isOn)
		if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
	end)
end
MakeToggleRow("Sound Effects", "sfx"); MakeToggleRow("Music", "music"); MakeToggleRow("Jumping", "jump") 

local div1 = Instance.new("Frame", setScroll); div1.Size = UDim2.new(1, -20, 0, 2); div1.BackgroundColor3 = T.panelStroke; div1.BorderSizePixel = 0
local statsTitle = Instance.new("TextLabel", setScroll); statsTitle.Size = UDim2.new(1, -20, 0, 20); statsTitle.BackgroundTransparency = 1; statsTitle.Text = "FARM STATS"; statsTitle.TextColor3 = T.subText; statsTitle.TextScaled = true; statsTitle.Font = T.font; statsTitle.TextXAlignment = Enum.TextXAlignment.Left
local function MakeStatRow(labelText, refKey)
	local row = Instance.new("Frame", setScroll); row.Size = UDim2.new(1, -20, 0, 26); row.BackgroundTransparency = 1; local lbl = Instance.new("TextLabel", row); lbl.Size = UDim2.new(0.55, 0, 1, 0); lbl.BackgroundTransparency = 1; lbl.Text = labelText; lbl.TextColor3 = T.subText; lbl.TextScaled = true; lbl.Font = T.fontBody; lbl.TextXAlignment = Enum.TextXAlignment.Left; local val = Instance.new("TextLabel", row); val.Size = UDim2.new(0.45, 0, 1, 0); val.Position = UDim2.new(0.55, 0, 0, 0); val.BackgroundTransparency = 1; val.Text = "0"; val.TextColor3 = T.accentBlue; val.TextScaled = true; val.Font = T.font; val.TextXAlignment = Enum.TextXAlignment.Right; statValueRefs[refKey] = val
end
MakeStatRow("Soul Auras", "soul"); MakeStatRow("This Run", "run"); MakeStatRow("Rate", "rate"); MakeStatRow("Prestiges", "prestige")
local function RefreshStats() if statValueRefs.soul then statValueRefs.soul.Text = Formatter.Format(liveSoulAuras) end; if statValueRefs.run then statValueRefs.run.Text = "$" .. Formatter.Format(liveRunEarnings) end; if statValueRefs.rate then statValueRefs.rate.Text = "$" .. Formatter.Format(liveRate) .. "/s" end; if statValueRefs.prestige then statValueRefs.prestige.Text = Formatter.Format(livePrestiges) end end

local function CreateInteractiveRow(parent, id, claimActionId, onClaimCallback)
	local row = parent:FindFirstChild(id)
	if not row then
		row = Instance.new("TextButton", parent); row.Name = id; row.Text = ""; row.AutoButtonColor = false; row.Size = UDim2.new(1, -8, 0, 64); row.BackgroundColor3 = T.cardBG; Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8); local stroke = Instance.new("UIStroke", row); stroke.Name = "Stroke"; stroke.Thickness = 1; local icon = Instance.new("ImageLabel", row); icon.Name = "Icon"; icon.Size = UDim2.new(0, 40, 0, 40); icon.Position = UDim2.new(0, 12, 0.5, -20); icon.ScaleType = Enum.ScaleType.Fit; Instance.new("UICorner", icon).CornerRadius = UDim.new(1, 0); local tLbl = Instance.new("TextLabel", row); tLbl.Name = "Title"; tLbl.Size = UDim2.new(0.6, 0, 0, 20); tLbl.Position = UDim2.new(0, 64, 0, 10); tLbl.BackgroundTransparency = 1; tLbl.TextColor3 = T.bodyText; tLbl.TextScaled = true; tLbl.Font = T.font; tLbl.TextXAlignment = Enum.TextXAlignment.Left; local dLbl = Instance.new("TextLabel", row); dLbl.Name = "Desc"; dLbl.Size = UDim2.new(0.6, 0, 0, 16); dLbl.Position = UDim2.new(0, 64, 0, 32); dLbl.BackgroundTransparency = 1; dLbl.TextColor3 = T.subText; dLbl.TextScaled = true; dLbl.Font = T.fontBody; dLbl.TextXAlignment = Enum.TextXAlignment.Left; local sLbl = Instance.new("TextLabel", row); sLbl.Name = "Status"; sLbl.Size = UDim2.new(0, 80, 0, 24); sLbl.Position = UDim2.new(1, -90, 0.5, -12); sLbl.BackgroundTransparency = 1; sLbl.TextScaled = true; sLbl.Font = T.font; sLbl.TextXAlignment = Enum.TextXAlignment.Right
		UITheme.Apply(row, "Card"); CollectionService:AddTag(row, "Tutorial_AchieveRow_" .. id)
		local scale = Instance.new("UIScale", row)
		row.MouseEnter:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15), {Scale = 1.02}):Play() end)
		row.MouseLeave:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15), {Scale = 1}):Play(); row.Desc.Text = row:GetAttribute("BaseDesc") or "" end)
		row.MouseButton1Down:Connect(function()
			TweenService:Create(scale, TweenInfo.new(0.1), {Scale = 0.95}):Play()
			if row:GetAttribute("RowState") == "CLAIMABLE" then
				if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform(claimActionId) then return end
				PlayClaimVFX(row); onClaimCallback(); if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
			else
				PlayUI(SoundConfig.UIClick or ""); local showingReq = not row:GetAttribute("ShowingReq"); row:SetAttribute("ShowingReq", showingReq)
				if showingReq and row:GetAttribute("ReqDesc") ~= "" then row.Desc.Text = row:GetAttribute("ReqDesc"); row.Desc.TextColor3 = T.accentGold else row.Desc.Text = row:GetAttribute("BaseDesc"); row.Desc.TextColor3 = T.subText end
			end
		end)
		row.MouseButton1Up:Connect(function() TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), {Scale = 1.02}):Play() end)
	end
	return row
end

local function RefreshData()
	local claimedChallenges, claimedAuras, claimedBadges, discoveredTiers = latestStats.claimedChallenges or {}, latestStats.claimedAuras or {}, latestStats.claimedBadges or {}, latestStats.discoveredTiers or {}

	for i, chal in ipairs(AchievementConfig.Challenges) do
		local current = latestStats[chal.statKey] or 0
		local isDone = current >= chal.goal; local isClaimed = claimedChallenges[chal.id] == true
		local rowId = "Chal_" .. chal.id
		local row = CreateInteractiveRow(scrolls["Challenges"], rowId, "Action_ClaimChallenge_" .. chal.id, function() ClaimChallenge:FireServer(chal.id) end)
		row.Title.Text = chal.title; row.Icon.Image = chal.iconId; row:SetAttribute("BaseDesc", chal.rewardText); row:SetAttribute("ReqDesc", "Requires: " .. chal.desc)
		if isClaimed then row:SetAttribute("RowState", "CLAIMED"); row.Status.Text = "UNLOCKED"; row.Status.TextColor3 = T.subText; row.BackgroundColor3 = T.cardBG; row.Stroke.Color = T.accentBlue; row.Desc.Text = chal.rewardText; row.Desc.TextColor3 = T.subText
		elseif isDone then row:SetAttribute("RowState", "CLAIMABLE"); row.Status.Text = "CLAIM!"; row.Status.TextColor3 = Color3.fromRGB(255, 255, 255); row.BackgroundColor3 = Color3.fromRGB(80, 160, 60); row.Stroke.Color = Color3.fromRGB(120, 255, 100); row.Desc.Text = "Click to Unlock!"; row.Desc.TextColor3 = Color3.fromRGB(200, 255, 200)
		else row:SetAttribute("RowState", "LOCKED"); row.Status.Text = current .. " / " .. chal.goal; row.Status.TextColor3 = T.subText; row.BackgroundColor3 = T.cardBG; row.Stroke.Color = T.subText; row.Desc.Text = (not row:GetAttribute("ShowingReq")) and chal.rewardText or ("Requires: " .. chal.desc); row.Desc.TextColor3 = T.subText end
	end

	local indexCount = 1
	for aIdx = 1, 20 do
		local areaNames = AreaAuraNames[aIdx]
		if not areaNames then continue end
		for tIdx = 1, 5 do
			local tier = TierConfig.Tiers[tIdx]
			if not tier then continue end
			local auraKey = aIdx .. "_" .. tier.name; local discovered = discoveredTiers[auraKey] == true; local isClaimed = claimedAuras[auraKey] == true
			local rewardGA = AchievementConfig.AuraTierRewards[tier.name] or 5
			local row = CreateInteractiveRow(scrolls["Index"], "Index_" .. indexCount, "Action_ClaimAura_" .. aIdx .. "_" .. tier.name, function() ClaimAuraIndex:FireServer(aIdx, tier.name) end)
			row.Icon.Image = "rbxassetid://0"
			if isClaimed then row:SetAttribute("RowState", "CLAIMED"); row.Title.Text = areaNames[tIdx] .. " Aura"; row.Title.TextColor3 = tier.color; row.Status.Text = "FOUND"; row.Status.TextColor3 = T.subText; row.BackgroundColor3 = T.cardBG; row.Stroke.Color = tier.color; row:SetAttribute("BaseDesc", "Area " .. aIdx); row:SetAttribute("ReqDesc", ""); row.Desc.Text = "Area " .. aIdx; row.Desc.TextColor3 = T.subText
			elseif discovered then row:SetAttribute("RowState", "CLAIMABLE"); row.Title.Text = areaNames[tIdx] .. " Aura"; row.Title.TextColor3 = Color3.fromRGB(255, 255, 255); row.Status.Text = "CLAIM +" .. rewardGA .. " GA!"; row.Status.TextColor3 = Color3.fromRGB(255, 215, 0); row.BackgroundColor3 = Color3.fromRGB(150, 110, 20); row.Stroke.Color = Color3.fromRGB(255, 215, 0); row:SetAttribute("BaseDesc", "Click to claim reward!"); row:SetAttribute("ReqDesc", ""); row.Desc.Text = "Click to claim reward!"; row.Desc.TextColor3 = Color3.fromRGB(255, 240, 150)
			else row:SetAttribute("RowState", "LOCKED"); row.Title.Text = "???"; row.Title.TextColor3 = Color3.fromRGB(100, 100, 100); row.Status.Text = "???"; row.Status.TextColor3 = T.buttonRed; row.BackgroundColor3 = T.cardBG; row.Stroke.Color = Color3.fromRGB(50, 50, 50); row:SetAttribute("BaseDesc", "Undiscovered"); row:SetAttribute("ReqDesc", "Area " .. aIdx); row.Desc.Text = "Undiscovered"; row.Desc.TextColor3 = T.subText end
			indexCount += 1
		end
	end

	for i, badge in ipairs(AchievementConfig.Badges) do
		local current = latestStats[badge.statKey] or 0; local isDone = current >= badge.goal; local isClaimed = claimedBadges[i] == true
		local row = CreateInteractiveRow(scrolls["Badges"], "Badge_" .. i, "Action_ClaimBadge_" .. i, function() ClaimBadge:FireServer(i) end)
		row.Title.Text = badge.title; row.Icon.Image = badge.iconId; row:SetAttribute("BaseDesc", badge.desc); row:SetAttribute("ReqDesc", "Goal: " .. badge.goal)
		if isClaimed then row:SetAttribute("RowState", "CLAIMED"); row.Status.Text = "OWNED"; row.Status.TextColor3 = T.subText; row.BackgroundColor3 = T.cardBG; row.Stroke.Color = T.accentGold; row.Desc.Text = badge.desc; row.Desc.TextColor3 = T.subText
		elseif isDone then row:SetAttribute("RowState", "CLAIMABLE"); row.Status.Text = "CLAIM BADGE!"; row.Status.TextColor3 = Color3.fromRGB(255, 255, 255); row.BackgroundColor3 = Color3.fromRGB(120, 60, 180); row.Stroke.Color = Color3.fromRGB(200, 100, 255); row.Desc.Text = "Click to receive Badge!"; row.Desc.TextColor3 = Color3.fromRGB(230, 200, 255)
		else row:SetAttribute("RowState", "LOCKED"); row.Status.Text = current .. " / " .. badge.goal; row.Status.TextColor3 = T.subText; row.BackgroundColor3 = T.cardBG; row.Stroke.Color = T.subText; row.Desc.Text = badge.desc; row.Desc.TextColor3 = T.subText end
	end
end

UpdateHUDBridge:Connect(function(stats)
	for key, value in pairs(stats) do latestStats[key] = value end
	if stats.soulAuras ~= nil then liveSoulAuras = stats.soulAuras end; if stats.totalEarned ~= nil then liveRunEarnings = stats.totalEarned end; if stats.rate ~= nil and stats.passiveInterval ~= nil and stats.passiveInterval > 0 then liveRate = stats.rate / stats.passiveInterval end; if stats.prestigeCount ~= nil then livePrestiges = stats.prestigeCount end
	if stats.settings then
		if stats.settings.sfxEnabled ~= nil then sfxEnabled = stats.settings.sfxEnabled; if toggleRefs.sfx then toggleRefs.sfx(sfxEnabled) end end
		if stats.settings.musicEnabled ~= nil then musicEnabled = stats.settings.musicEnabled; if toggleRefs.music then toggleRefs.music(musicEnabled) end end
		if stats.settings.jumpEnabled ~= nil then jumpEnabled = stats.settings.jumpEnabled; if toggleRefs.jump then toggleRefs.jump(jumpEnabled) end end
	end
	if panelOpen then RefreshData(); RefreshStats() end
end)

local function OpenToTab(tabName, hoverText)
	PlayUI(SoundConfig.UIOpen or ""); panelOpen = true; Panel.Visible = true; Panel.Size = UDim2.new(0.85, 0, 0, 0); activeTab = tabName; activeTabText = hoverText; HoverLabel.Text = activeTabText
	for k, t in pairs(tabBtns) do t.btn.BackgroundColor3 = (k == activeTab) and T.accentGold or T.buttonSecondary; t.stroke.Color = (k == activeTab) and T.bodyText or T.panelStroke end
	for k, s in pairs(scrolls) do s.Visible = (k == activeTab) end
	RefreshData(); RefreshStats(); TitleLabel.Text = (tabName == "Settings") and "SETTINGS" or "PROGRESSION"
	TweenService:Create(Panel, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = UDim2.new(0.85, 0, 0.75, 0)}):Play()
	UITheme.SetMenuVisible(true)
end

local function ClosePanel()
	if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_CloseAchievements") then return end
	PlayUI(SoundConfig.UIClose or ""); panelOpen = false; TweenService:Create(Panel, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Size = UDim2.new(0.85, 0, 0, 0)}):Play(); UITheme.SetMenuVisible(false); task.delay(0.25, function() Panel.Visible = false end)
	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
end

AchieveBtn.MouseButton1Down:Connect(function()
	if not panelOpen then
		if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_OpenAchievements") then return end
		OpenToTab("Challenges", "Boosts")
		if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
	else
		ClosePanel()
	end
end)

CloseBtn.MouseButton1Down:Connect(ClosePanel)

local function AddButtonJuice(btn)
	local scale = btn:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", btn)
	btn.MouseEnter:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15), {Scale = 1.08}):Play() end)
	btn.MouseLeave:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15), {Scale = 1}):Play() end)
	btn.MouseButton1Down:Connect(function() TweenService:Create(scale, TweenInfo.new(0.1), {Scale = 0.9}):Play() end)
	btn.MouseButton1Up:Connect(function() TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), {Scale = 1.08}):Play() end)
end
AddButtonJuice(AchieveBtn); AddButtonJuice(CloseBtn)
for _, t in pairs(tabBtns) do AddButtonJuice(t.btn) end

task.spawn(function() task.wait(1); UITheme.Apply(Panel, "Panel"); UITheme.Apply(Header, "TitleBar"); UITheme.ApplyShine(Panel) end)

---------------------------------------------------------------
-- ✨ THE FIX: JUMP ENFORCER LOGIC
---------------------------------------------------------------
local defaultJumpHeight = 7.2
local defaultJumpPower = 50

local function UpdateJumpState(character, canJump)
	if not character then return end
	local humanoid = character:WaitForChild("Humanoid", 3)
	if humanoid then
		if humanoid.JumpHeight > 0 then defaultJumpHeight = humanoid.JumpHeight end
		if humanoid.JumpPower > 0 then defaultJumpPower = humanoid.JumpPower end

		if canJump then
			humanoid.UseJumpPower = not humanoid.UseJumpPower 
			humanoid.JumpHeight = defaultJumpHeight
			humanoid.JumpPower = defaultJumpPower
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		else
			humanoid.JumpHeight = 0
			humanoid.JumpPower = 0
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		end
	end
end

SettingsChanged.Event:Connect(function(key, value)
	if key == "jump" then UpdateJumpState(player.Character, value) end
end)

player.CharacterAdded:Connect(function(char)
	task.wait(0.1) UpdateJumpState(char, jumpEnabled)
end)

if player.Character then UpdateJumpState(player.Character, jumpEnabled) end

-- ✨ TUTORIAL OVERRIDE
local forceClose = ReplicatedStorage:FindFirstChild("ForceCloseUI") or Instance.new("BindableEvent")
forceClose.Name = "ForceCloseUI"; forceClose.Parent = ReplicatedStorage
forceClose.Event:Connect(function() if panelOpen then CloseBtn.MouseButton1Down:Fire() end end)
