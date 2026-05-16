-- MainMenuController
-- Location: StarterPlayer > StarterPlayerScripts > MainMenuController
--
-- Shows a title screen on join with the live game world as the background.
-- Camera locks to area-specific "MenuCamPos_N" Parts in Workspace.
-- Background is blurred using the existing UITheme MenuBlur system.
-- All sizes/positions driven by UIConfig.MainMenu, all colors from UITheme.
-- Player clicks PLAY → black fade transition → camera released → game begins.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local ContentProvider   = game:GetService("ContentProvider")

local UITheme = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UITheme"))
local T = UITheme.Get("Custom")
local C = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UIConfig"))
local M = C.MainMenu

-- ✨ IMPORT POOL MANAGER
local PoolManager = require(ReplicatedStorage.Modules:WaitForChild("PoolManager"))

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainHUD   = playerGui:WaitForChild("MainHUD")
local camera    = workspace.CurrentCamera

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local AreaUpdated  = RemoteEvents:WaitForChild("AreaUpdated")

---------------------------------------------------------------
-- GATE: Create the BindableEvent other scripts wait on
---------------------------------------------------------------
local MenuDismissed = Instance.new("BindableEvent")
MenuDismissed.Name = "MenuDismissed"
MenuDismissed.Parent = ReplicatedStorage

---------------------------------------------------------------
-- DEV TOGGLE: Set to false to skip the menu entirely
---------------------------------------------------------------
local MENU_ENABLED = true

if not MENU_ENABLED then
	MenuDismissed:SetAttribute("Fired", true)
	MenuDismissed:Fire()
	return
end

---------------------------------------------------------------
-- CONSTANTS (driven by UIConfig.MainMenu)
---------------------------------------------------------------
local FADE_IN_TIME   = M.FadeInTime or 0.8
local FADE_HOLD_TIME = M.FadeHoldTime or 1
local FADE_OUT_TIME  = M.FadeOutTime or 1.2
local IDLE_SPEED     = M.IdleSpeed or 5
local LEFT           = M.LeftMargin
local TITLE_FONT     = T.font or Enum.Font.FredokaOne
local BODY_FONT      = T.fontBody or Enum.Font.FredokaOne
local DEFAULT_AREA   = 1

---------------------------------------------------------------
-- STATE
---------------------------------------------------------------
local currentArea     = DEFAULT_AREA
local hasPlayed       = false
local idleConn        = nil
local areaConn        = nil

---------------------------------------------------------------
-- 1. HIDE THE GAME HUD IMMEDIATELY
---------------------------------------------------------------
mainHUD.Enabled = false

---------------------------------------------------------------
-- 2. LOCK CAMERA + BLUR
---------------------------------------------------------------
local savedCamType    = camera.CameraType
local savedCamSubject = camera.CameraSubject

camera.CameraType = Enum.CameraType.Scriptable

-- Enable the existing UITheme blur system
UITheme.SetMenuVisible(true)

---------------------------------------------------------------
-- CAMERA HELPERS
---------------------------------------------------------------
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
		local offset = CFrame.Angles(0, math.rad(angle * 0.3), 0).LookVector * 0.5
		camera.CFrame = CFrame.lookAt(basePos + offset, lookTarget)
	end)
end

-- Set initial camera
SnapCameraToArea(DEFAULT_AREA)
StartIdleDrift(DEFAULT_AREA)

-- Lift the Blackout Curtain
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

-- Listen for Area changes (if they happen while in the menu)
areaConn = AreaUpdated.OnClientEvent:Connect(function(info)
	if hasPlayed then return end
	local area = info.currentArea or DEFAULT_AREA
	if area ~= currentArea then
		currentArea = area
		SnapCameraToArea(area)
		StartIdleDrift(area)
	end
end)

---------------------------------------------------------------
-- 3. BUILD THE MENU UI
---------------------------------------------------------------
local menuScreen = Instance.new("ScreenGui")
menuScreen.Name = "MainMenu"
menuScreen.DisplayOrder = 100
menuScreen.IgnoreGuiInset = true
menuScreen.ResetOnSpawn = false
menuScreen.Parent = playerGui

local vignette = Instance.new("Frame")
vignette.Name = "Vignette"
vignette.Size = UDim2.new(1, 0, 1, 0)
vignette.BackgroundColor3 = Color3.new(0, 0, 0)
vignette.BackgroundTransparency = M.VignetteDim or 0.5
vignette.BorderSizePixel = 0
vignette.ZIndex = 1
vignette.Parent = menuScreen

local vigGrad = Instance.new("UIGradient")
vigGrad.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.4, 0.6),
	NumberSequenceKeypoint.new(1, 0),
})
vigGrad.Parent = vignette

local container = Instance.new("Frame")
container.Name = "MenuContainer"
container.Size = UDim2.new(0.9, 0, 0.6, 0)
container.Position = UDim2.new(0.05, 0, 0.2, 0) 
container.BackgroundTransparency = 1
container.ZIndex = 2
container.Parent = menuScreen

local containerConstraint = Instance.new("UISizeConstraint")
containerConstraint.MaxSize = Vector2.new(600, 450)
containerConstraint.Parent = container

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "Title"
titleLabel.Size = UDim2.new(1, 0, 0.3, 0) 
titleLabel.Position = UDim2.new(0, 0, 0, 0)
titleLabel.AnchorPoint = Vector2.new(0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "AURA INC"
titleLabel.TextColor3 = T.headerText
titleLabel.TextScaled = true
titleLabel.Font = TITLE_FONT
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.ZIndex = 10
titleLabel.Parent = container

local titleShadow = titleLabel:Clone()
titleShadow.Name = "TitleShadow"
titleShadow.TextColor3 = T.accentPurple
titleShadow.TextTransparency = 0.5
titleShadow.Position = UDim2.new(0, 0, 0, 4) 
titleShadow.ZIndex = 9
titleShadow.Parent = container

local titleStroke = Instance.new("UIStroke")
titleStroke.Color = T.accentPurple
titleStroke.Thickness = 2
titleStroke.Transparency = 0.3
titleStroke.Parent = titleLabel

local subtitleLabel = Instance.new("TextLabel")
subtitleLabel.Name = "Subtitle"
subtitleLabel.Size = UDim2.new(0.8, 0, 0.15, 0) 
subtitleLabel.Position = UDim2.new(0, 0, 0.3, 0) 
subtitleLabel.AnchorPoint = Vector2.new(0, 0)
subtitleLabel.BackgroundTransparency = 1
subtitleLabel.Text = "Idle Aura Factory"
subtitleLabel.TextColor3 = T.subText
subtitleLabel.TextScaled = true
subtitleLabel.Font = BODY_FONT
subtitleLabel.TextXAlignment = Enum.TextXAlignment.Left
subtitleLabel.ZIndex = 10
subtitleLabel.Parent = container

-- ✨ THE "PRE-LOADING" STATUS TEXT
local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "Status"
statusLabel.Size = UDim2.new(0.8, 0, 0.1, 0) 
statusLabel.Position = UDim2.new(0, 0, 0.5, 0) 
statusLabel.AnchorPoint = Vector2.new(0, 0)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "Generating Physics Pools..."
statusLabel.TextColor3 = T.accentGold
statusLabel.TextScaled = true
statusLabel.Font = BODY_FONT
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.ZIndex = 10
statusLabel.Parent = container

-- PLAY BUTTON
local playBtn = Instance.new("TextButton")
playBtn.Name = "PlayButton"
playBtn.Size = UDim2.new(0.45, 0, 0.25, 0) 
playBtn.Position = UDim2.new(0, 0, 0.65, 0) 
playBtn.AnchorPoint = Vector2.new(0, 0)
playBtn.BackgroundColor3 = T.buttonPrimary
playBtn.BorderSizePixel = 0
playBtn.Text = "PLAY"
playBtn.TextColor3 = T.headerText
playBtn.TextScaled = true
playBtn.Font = TITLE_FONT
playBtn.ZIndex = 10
playBtn.AutoButtonColor = false
playBtn.Visible = false -- ✨ HIDDEN UNTIL LOADING FINISHES
playBtn.Parent = container

local btnConstraint = Instance.new("UIAspectRatioConstraint")
btnConstraint.AspectRatio = 2.5 
btnConstraint.Parent = playBtn

Instance.new("UICorner", playBtn).CornerRadius = UDim.new(0, 12)

local playStroke = Instance.new("UIStroke")
playStroke.Color = T.accentPurple
playStroke.Thickness = T.StrokeThickness or 2
playStroke.Transparency = 0.2
playStroke.Parent = playBtn

local playGrad = Instance.new("UIGradient")
playGrad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 180, 220)),
})
playGrad.Rotation = 90
playGrad.Parent = playBtn

-- Container Float Tween
TweenService:Create(container, TweenInfo.new(2.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
	Position = container.Position - UDim2.new(0, 0, 0, 12)
}):Play()

-- Button Interactions
local btnScale = Instance.new("UIScale", playBtn)
local isHovering = false

task.spawn(function()
	while playBtn and playBtn.Parent do
		if not isHovering and playBtn.Visible then
			TweenService:Create(btnScale, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {Scale = 1.03}):Play()
		end
		task.wait(1)
		if not playBtn or not playBtn.Parent then break end

		if not isHovering and playBtn.Visible then
			TweenService:Create(btnScale, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {Scale = 1.0}):Play()
		end
		task.wait(1)
	end
end)

playBtn.MouseEnter:Connect(function()
	isHovering = true
	TweenService:Create(btnScale, TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {Scale = 1.1}):Play()
	TweenService:Create(playBtn, TweenInfo.new(0.15), {BackgroundColor3 = T.accentPurple}):Play()
end)

playBtn.MouseLeave:Connect(function()
	isHovering = false
	TweenService:Create(btnScale, TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {Scale = 1.0}):Play()
	TweenService:Create(playBtn, TweenInfo.new(0.2), {BackgroundColor3 = T.buttonPrimary}):Play()
end)

playBtn.MouseButton1Down:Connect(function()
	TweenService:Create(btnScale, TweenInfo.new(0.1, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {Scale = 0.9}):Play()
	if shared.PlayUISound then shared.PlayUISound("6895079853") end
end)

playBtn.MouseButton1Up:Connect(function()
	TweenService:Create(btnScale, TweenInfo.new(0.3, Enum.EasingStyle.Bounce), {Scale = 1.1}):Play()
end)

task.spawn(function()
	task.wait(0.5) 
	if UITheme and UITheme.ApplyShine then UITheme.ApplyShine(playBtn) end
	if UITheme and UITheme.ApplyFlair then UITheme.ApplyFlair(titleLabel, "Ghost") end
end)

local creditLabel = Instance.new("TextLabel")
creditLabel.Name = "Credits"
creditLabel.Size = UDim2.new(0.6, 0, 0.1, 0)
creditLabel.Position = UDim2.new(0, 0, 0.9, 0)
creditLabel.AnchorPoint = Vector2.new(0, 0)
creditLabel.BackgroundTransparency = 1
creditLabel.Text = "Made by MoldySugar2205"
creditLabel.TextColor3 = T.subText
creditLabel.TextTransparency = 0.3
creditLabel.TextScaled = true
creditLabel.Font = BODY_FONT
creditLabel.TextXAlignment = Enum.TextXAlignment.Left
creditLabel.ZIndex = 10
creditLabel.Parent = container

---------------------------------------------------------------
-- LOADING SCREEN OVERLAY
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
	playBtn.Text = ""

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

	UITheme.SetMenuVisible(false)
	mainHUD.Enabled = true

	vignette:Destroy()
	container:Destroy()

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

local function RefreshLook()
	UITheme.ApplyFlair(titleLabel, "Shine")	
	UITheme.ApplyFlair(subtitleLabel, "Shine")
	UITheme.ApplyFlair(creditLabel, "Shine")
	UITheme.ApplyFlair(playBtn, "Shine")
end

RefreshLook()

---------------------------------------------------------------
-- ✨ TRUE BACKGROUND LOADING (POOL CREATION) ✨
---------------------------------------------------------------
task.spawn(function()
	if not game:IsLoaded() then game.Loaded:Wait() end

	local playerArea = player:GetAttribute("CurrentArea") or DEFAULT_AREA
	statusLabel.Text = "Optimizing Performance (Area " .. playerArea .. ")..."

	-- Yield a split second so the text updates visibly
	task.wait(0.2)

	-- We instruct the PoolManager to physically create all the Auras and cache them
	-- Note: Because this creates ~300 parts, it WILL cause a tiny spike, 
	-- but the player won't feel it because they are just staring at the Menu!
	PoolManager.InitializeArea(playerArea)

	statusLabel.Text = "Ready!"
	task.wait(0.3)

	-- The pools are built, the game is 100% lag-free. Show the PLAY button!
	statusLabel.Visible = false
	playBtn.Visible = true

	-- Pop the play button in with a nice tween
	playBtn.Size = UDim2.new(0,0,0,0)
	TweenService:Create(playBtn, TweenInfo.new(0.5, Enum.EasingStyle.Bounce), {
		Size = UDim2.new(0.45, 0, 0.25, 0)
	}):Play()
end)

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
	local sf = Instance.new("ScrollingFrame", Panel); sf.Size = UDim2.new(1, -20, 1, -135); sf.Position = UDim2.new(0, 10, 0, 125); sf.BackgroundTransparency = 1; sf.BorderSizePixel = 0; sf.ScrollBarThickness = 4; sf.Visible = false; local layout = Instance.new("UIListLayout", sf); layout.Padding = UDim.new(0, 8); layout.HorizontalAlignment = Enum.HorizontalAlignment.Center; layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function() sf.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 10) end); scrolls[name] = sf
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

MakeTab("Challenges", "Boosts", "rbxassetid://14916846070"); MakeTab("Index", "Auras", "rbxassetid://14916846070"); MakeTab("Badges", "Badges", "rbxassetid://14916846070"); MakeTab("Leaderboard", "Top 10", "rbxassetid://14916846070"); MakeTab("Settings", "Settings", "rbxassetid://14923131909") 

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
	RefreshData(); RefreshStats(); TitleLabel.Text = (tabName == "Settings") and "SETTINGS" or "MENU"
	TweenService:Create(Panel, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = UDim2.new(0.85, 0, 0.75, 0)}):Play()
	UITheme.SetMenuVisible(true)
end

AchieveBtn.MouseButton1Down:Connect(function()
	if not panelOpen and type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_OpenAchievements") then return end
	if panelOpen and type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_CloseAchievements") then return end
	if panelOpen then CloseBtn.MouseButton1Down:Fire() else OpenToTab("Challenges", "Boosts") end
	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
end)
CloseBtn.MouseButton1Down:Connect(function()
	if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_CloseAchievements") then return end
	PlayUI(SoundConfig.UIClose or ""); panelOpen = false; TweenService:Create(Panel, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Size = UDim2.new(0.85, 0, 0, 0)}):Play(); UITheme.SetMenuVisible(false); task.delay(0.25, function() Panel.Visible = false end)
	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
end)

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


-- TutorialConfig
-- Location: ReplicatedStorage > Modules > TutorialConfig

local TutorialConfig = {}

TutorialConfig.TutorialEndArea = 5

-- The Ghost Hand / Pointer asset
TutorialConfig.PointerImage = "rbxassetid://14914009728"
TutorialConfig.PointerSize = UDim2.new(0, 75, 0, 75)

-- Default Styling
TutorialConfig.DefaultColor = Color3.fromRGB(100, 200, 255)
TutorialConfig.DefaultIcon  = "rbxassetid://14914018910"

-- THE FSM SEQUENCE
TutorialConfig.Steps = {

	-- ✨ STEP 1: Welcome & First Click
	[1] = {
		id           = "a1_welcome_click",
		action       = "Action_ClickRedButton",
		targetTag    = "Tutorial_ClickButton",

		bannerTitle  = "Welcome to Aura Inc!",
		bannerBody   = "Spam Click the Red Button below to produce your first Auras.",

		icon         = "rbxassetid://14922082255", 
		color        = Color3.fromRGB(143, 255, 131), 
	},

	-- ✨ STEP 2: Cinematic Camera Follow
	[2] = {
		id               = "a1_watch_aura",
		action           = "Action_Wait",
		
		cameraTrackMode  = "FollowAura", 
		target3D         = "Aura",       
		duration         = 5,          
		allowClicking = true, 

		bannerTitle  = "Generating Profit",
		bannerBody   = "Each Aura generates cash every second based on its rarity.",

		icon         = "rbxassetid://14914018910",
		color        = Color3.fromRGB(255, 255, 255), 
	},

	-- ✨ STEP 3: Produce Bulk
	[3] = {
		id           = "a1_produce_25",
		action       = "Action_ClickRedButton",
		targetTag    = "Tutorial_ClickButton",
		cameraTarget = "Tutorial_AuraHolderCam",

		requireCubesProduced = 25,
		failsafeDuration = 35, 
		bannerTitle  = "Producing Auras",
		bannerBody   = "Keep clicking to produce 25 Auras! The more you make, the more money you earn.",
		duration     = 0, 

		icon         = "rbxassetid://14914018910",
		color        = Color3.fromRGB(130, 226, 255), 
	},

	-- ✨ STEP 4: Farm up Cash
	[4] = {
		id           = "a1_farm_150",
		action       = "Action_ClickRedButton",

		requireCurrency = 150,

		bannerTitle  = "Stacking Cash",
		bannerBody   = "Your Auras are passively generating income while on the Conveyer. Keep producing until you save up $150!",
		duration     = 0,
		failsafeDuration = 25, 
		icon         = "rbxassetid://14924185885",
		color        = Color3.fromRGB(150, 255, 150), 
	},

	-- ✨ STEP 5: Unlock Shop
	[5] = {
		id           = "a1_open_shop",
		action       = "Action_OpenShop",
		targetTag    = "Tutorial_ShopButton",

		unlockTags    = {"Tutorial_ShopButton"},
		unlockActions = {"Action_OpenShop", "Action_CloseShop"},

		bannerTitle  = "Open The Shop",
		bannerBody   = "You have enough Money! Click the Shop icon to view your upgrades.",

		icon         = "rbxassetid://14915225073",
		color        = Color3.fromRGB(123, 216, 250),
	},

	-- ✨ STEP 6: First Upgrade
	[6] = {
		id             = "a1_buy_blockValue",
		action         = "Action_BuyUpgrade",
		targetTag      = "Tutorial_Buy_blockValue",

		unlockTags     = {"Tutorial_Buy_blockValue"},

		menuTag        = "Tutorial_ShopPanel",
		menuOpenBtnTag = "Tutorial_ShopButton",

		bannerTitle  = "Increase Value",
		bannerBody   = "Buy the Value upgrade to increase the Value of your Auras by +10%",

		icon         = "rbxassetid://14917128076",
		color        = Color3.fromRGB(142, 206, 255), 
	},

	-- ✨ STEP 7: Habitat Fill
	[7] = {
		id           = "a1_fill_habitat",
		action       = "Action_ClickRedButton",
		targetTag    = "Tutorial_ClickButton",

		requireHabitatFull = true,
		duration           = 0, 

		bannerTitle  = "Keep Producing",
		bannerBody   = "Close the shop and keep Producing Auras. Spam Click or HOLD the red button To keep producing Auras.",

		icon         = "rbxassetid://14914018910",
		color        = Color3.fromRGB(130, 226, 255),
	},

	-- ✨ STEP 8: Watch Aura Die
	[8] = {
		id               = "a1_watch_aura_die",
		action           = "Action_Wait",

		cameraTrackMode  = "FollowAura",
		cameraOffset     = Vector3.new(0, 22, 28), 

		requireRateZero  = true, 
		duration         = 0, 

		bannerTitle  = "Incinerated!",
		bannerBody   = "Since your habitat Got full, Auras get incinerated. Wait for your Rate to hit $0.",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(255, 0, 4), 
	},

	-- ✨ STEP 9: Pan to Habitat
	[9] = {
		id           = "a1_look_at_habitat",
		action       = "Action_Wait",
		cameraTarget = "Tutorial_HabitatCam",

		duration     = 7, 

		bannerTitle  = "Habitat is Full!",
		bannerBody   = "Your storage is completely Full. You need to clear some Space.",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(255, 155, 155), 
	},

	-- ✨ STEP 10: Send Ship
	[10] = {
		id           = "a1_send_ship",
		action       = "Action_SendShip",
		targetTag    = "Tutorial_SendShipBtn",

		unlockTags    = {"Tutorial_SendShipBtn"},
		unlockActions = {"Action_SendShip"},

		bannerTitle  = "Clear Space",
		bannerBody   = "Click the newly unlocked SEND button to clear out your habitat of the Auras.",

		icon         = "rbxassetid://14915225073",
		color        = Color3.fromRGB(100, 255, 255), 
	},

	-- ✨ STEP 11: Watch Ship
	[11] = {
		id           = "a1_wait_for_ship",
		action       = "Action_Wait",
		cameraTarget = "Tutorial_ShippingCam",

		requirePlatformsShipped = 2,

		bannerTitle  = "Ship Delivery",
		bannerBody   = "Ships collect all your Auras and pay out the cash directly to your wallet. Send 2 Ships Out.",
		duration     = 0,

		icon         = "rbxassetid://14914018910",
		color        = Color3.fromRGB(150, 200, 255), 
	},

	-- ✨ STEP 12: Auto Ship
	[12] = {
		id           = "a1_toggle_auto",
		action       = "Action_ToggleAutoShip",
		targetTag    = "Tutorial_ToggleShipBtn",

		unlockTags    = {"Tutorial_ToggleShipBtn"},
		unlockActions = {"Action_ToggleAutoShip"},

		bannerTitle  = "Automate Ships",
		bannerBody   = "Click the new unlocked Toggle Button to automate your shipments!",

		icon         = "rbxassetid://14915225073",
		color        = Color3.fromRGB(50, 150, 50), 
	},

	-- ✨ STEP 13: Business as usual
	[13] = {
		id           = "a1_farm_500",
		action       = "Action_ClickRedButton",

		requireCurrency = 500,

		bannerTitle  = "More Upgrades!",
		bannerBody   = "Make $500 to afford your next upgrade.",
		duration     = 0,

		icon         = "rbxassetid://14924185885",
		color        = Color3.fromRGB(150, 255, 150),
	},

	[14] = {
		id             = "a1_buy_auraExpansion",
		action         = "Action_BuyUpgrade",
		targetTag      = "Tutorial_Buy_hatcheryCapacity",

		unlockTags     = {"Tutorial_Buy_hatcheryCapacity"},

		menuTag        = "Tutorial_ShopPanel",
		menuOpenBtnTag = "Tutorial_ShopButton",

		bannerTitle  = "More Hatchery",
		bannerBody   = "Buy the Aura Expansion upgrade to increase your Hatchery space!",

		icon         = "rbxassetid://14917128076",
		color        = Color3.fromRGB(105, 255, 250), 
	},

	[15] = {
		id           = "a1_farm_1500",
		action       = "Action_ClickRedButton",

		requireCurrency = 1500,

		bannerTitle  = "Growing the Factory",
		bannerBody   = "Make $1500 to afford the Habitat upgrade, allowing you to store more auras! Buy the aura value upgrade if you feel stuck.",
		duration     = 0,

		icon         = "rbxassetid://14924185885",
		color        = Color3.fromRGB(87, 255, 98),
	},

	[16] = {
		id             = "a1_buy_habitatCapacity",
		action         = "Action_BuyUpgrade",
		targetTag      = "Tutorial_Buy_habitatCapacity",

		unlockTags     = {"Tutorial_Buy_habitatCapacity"},

		menuTag        = "Tutorial_ShopPanel",
		menuOpenBtnTag = "Tutorial_ShopButton",

		bannerTitle  = "More Habitat Space",
		bannerBody   = "Buy the Habitat Reservoir Upgrade to store more Auras before they get Incinirated!",

		icon         = "rbxassetid://14917128076",
		color        = Color3.fromRGB(120, 248, 255),
	},

	[17] = {
		id           = "a1_multiply",
		action       = "Action_ClickRedButton",

		reachMultiplier = 5,

		bannerTitle  = "Hatchery Multipliers",
		bannerBody   = "Hold the Red button to reach the legendary multiplier! Make sure you have enough Hatchery and Space",
		duration     = 0,

		icon         = "rbxassetid://14924185885",
		color        = Color3.fromRGB(255, 255, 0), 
	},

	[18] = {
		id           = "a1_farm_25000",
		action       = "Action_ClickRedButton",

		requireCurrency = 5000,

		bannerTitle  = "Mythic Multiplier",
		bannerBody   = "Multipliers Increase Ship and Aura Value. Save up $5,000 to afford the Mythic Multiplier! Upgrade Aura Value If Stuck.",
		duration     = 0,

		icon         = "rbxassetid://14924185885",
		color        = Color3.fromRGB(137, 255, 110), 
	},

	[19] = {
		id             = "a1_buy_mythicMult",
		action         = "Action_BuyUpgrade",
		targetTag      = "Tutorial_Buy_unlockMythicMult", 

		unlockTags     = {"Tutorial_Buy_unlockMythicMult"},

		menuTag        = "Tutorial_ShopPanel",
		menuOpenBtnTag = "Tutorial_ShopButton",

		bannerTitle  = "Mythic Multiplier",
		bannerBody   = "Buy the Mythic Multiplier to hold past the legendary multiplier limit!",

		icon         = "rbxassetid://14917128076",
		color        = Color3.fromRGB(80, 246, 255),
	},

	[20] = {
		id           = "a1_multiply",
		action       = "Action_ClickRedButton",

		reachMultiplier = 10,

		bannerTitle  = "Hatchery Multipliers",
		bannerBody   = "Hold the Red button to reach the Mythic multiplier! Make sure to have plenty of Hatchery and Space",
		duration     = 0,

		icon         = "rbxassetid://14924185885",
		color        = Color3.fromRGB(134, 24, 161), 
	},

	[21] = {
		id           = "a1_open_prestige",
		action       = "Action_OpenPrestige",
		targetTag    = "Tutorial_PrestigeButton",

		unlockTags    = {"Tutorial_PrestigeButton", "Tutorial_PrestigeCloseBtn"},
		unlockActions = {"Action_OpenPrestige", "Action_ClosePrestige"},

		bannerTitle  = "How to Prestige",
		bannerBody   = "Click the Prestige button to restart with a massive permanent earnings multiplier.",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(180, 100, 255),
	},

	[22] = {
		id             = "a1_confirm_prestige",
		action         = "Action_PrestigeConfirm",
		targetTag      = "Tutorial_PrestigeConfirm",

		unlockTags     = {"Tutorial_PrestigeConfirm"},
		unlockActions  = {"Action_PrestigeConfirm"},

		menuTag        = "Tutorial_PrestigePanel",
		menuOpenBtnTag = "Tutorial_PrestigeButton",

		bannerTitle  = "Confirm Prestige",
		bannerBody   = "Click 'Prestige Now' to get your Soul Auras and increase your earnings permentantly.",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(215, 121, 255),
	},
	[23] = {
		id           = "a1_post_prestige_pan",
		action       = "Action_Wait", 
		duration     = 0,             
		allowClicking = true, 
		cameraTrackMode = "FollowPhysicsAura", 
		cameraOffset    = Vector3.new(0, 15, 25), 

		requireStepGoldenAuras = 10, 

		bannerTitle  = "Golden Auras",
		bannerBody   = "Collect Auras that spawn from the Producer OR claim your mailbox rewards!",

		icon         = "rbxassetid://4483362458",
		color        = Color3.fromRGB(255, 215, 0),
	},

	-- ✨ STEP 24: Farm for the next area
	[24] = {
		id           = "a1_farm_area2",
		action       = "Action_Wait", 
		duration     = 0,             
		allowClicking = true, 
		requireFarmEval = 50000, 
		unlockTags    = {"Tutorial_TravelButton", "Tutorial_TravelCloseBtn"},
		unlockActions = {"Action_OpenTravel", "Action_CloseTravel"},
		bannerTitle  = "Reaching More Areas",
		bannerBody   = "Open the travel menu to unlock the next Area. Your farm evaluation is based on the total amount of money made in that area.",

		icon         = "rbxassetid://14924185885",
		color        = Color3.fromRGB(126, 255, 212),
	},

	-- ✨ STEP 25: Open Area Travel
	[25] = {
		id           = "a1_open_travel",
		action       = "Action_OpenTravel",
		targetTag    = "Tutorial_TravelButton",

		bannerTitle  = "New Area Unlocked!",
		bannerBody   = "Click the Area Travel button to open the travel menu.",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(100, 200, 255),
	},

	-- ✨ STEP 26: Browse to Area 2
	[26] = {
		id             = "a1_travel_arrow",
		action         = "Action_ClickRightArrow",
		targetTag      = "Tutorial_RightArrow",

		unlockTags     = {"Tutorial_RightArrow"},
		unlockActions  = {"Action_ClickRightArrow", "Action_ClickLeftArrow"},

		menuTag        = "Tutorial_TravelPanel",
		menuOpenBtnTag = "Tutorial_TravelButton",
		fallbackStepId = "a1_open_travel", 

		bannerTitle  = "Browse Areas",
		bannerBody   = "Click the Arrows to view the newly unlocked area and other areas.",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(150, 200, 255),
	},

	-- ✨ STEP 27: Confirm Travel
	[27] = {
		id             = "a1_confirm_travel",
		action         = "Action_TravelConfirm",
		targetTag      = "Tutorial_TravelConfirm",

		unlockTags     = {"Tutorial_TravelConfirm"},
		unlockActions  = {"Action_TravelConfirm"},

		menuTag        = "Tutorial_TravelPanel",
		menuOpenBtnTag = "Tutorial_TravelButton",
		fallbackStepId = "a1_open_travel",

		bannerTitle  = "Travel Now",
		bannerBody   = "Click TRAVEL to jump to the new Area!",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(107, 255, 161),
	},

	-- ✨ STEP 28: Open Boost Shop
	[28] = {
		id           = "a1_open_boosts",
		action       = "Action_OpenBoostShop",
		targetTag    = "Tutorial_BoostMenuBtn",

		unlockTags    = {"Tutorial_BoostMenuBtn", "Tutorial_BoostShopClose", "Tutorial_BoostTab_Shop", "Tutorial_BoostTab_Inventory"},
		unlockActions = {"Action_OpenBoostShop", "Action_CloseBoostShop", "Action_BoostTab_Shop", "Action_BoostTab_Inventory"},

		bannerTitle  = "Area Boosts and Multipliers",
		bannerBody   = "Auras in this area have much higher base values! Open the new Boosts menu.",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(75, 255, 174),
	},

	-- ✨ STEP 29: Buy Aura Spawner Boost
	[29] = {
		id           = "a1_buy_boost1",
		action       = "Action_BuyBoost_AuraRush",
		targetTag    = "Tutorial_BuyBoost_AuraRush",

		unlockTags    = {"Tutorial_BuyBoost_AuraRush"},
		unlockActions = {"Action_BuyBoost_AuraRush"},

		menuTag        = "Tutorial_BoostShopPanel",
		menuOpenBtnTag = "Tutorial_BoostMenuBtn",

		requireBoostBought = { id = "AuraRush", count = 1 },

		bannerTitle  = "Buy a Boost",
		bannerBody   = "Buy the Aura Rush Boost using your Golden Auras.",

		icon         = "rbxassetid://4483362458",
		color        = Color3.fromRGB(114, 213, 255),
	},

	-- ✨ STEP 30: Switch to Inventory Tab
	[30] = {
		id           = "a1_click_inv_tab",
		action       = "Action_BoostTab_Inventory",
		targetTag    = "Tutorial_BoostTab_Inventory",

		menuTag        = "Tutorial_BoostShopPanel",
		menuOpenBtnTag = "Tutorial_BoostMenuBtn",

		bannerTitle  = "Check Inventory",
		bannerBody   = "Click the INVENTORY tab at the top of the menu to view the boosts you own.",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(103, 111, 255),
	},

	-- ✨ STEP 31: Use Aura Spawner Boost
	[31] = {
		id           = "a1_use_boost1",
		action       = "Action_UseBoost_AuraRush",
		targetTag    = "Tutorial_UseBoost_AuraRush",

		unlockTags    = {"Tutorial_UseBoost_AuraRush"},
		unlockActions = {"Action_UseBoost_AuraRush"},

		menuTag        = "Tutorial_BoostShopPanel",
		menuOpenBtnTag = "Tutorial_BoostMenuBtn",

		requireBoostUsed = { id = "AuraRush", count = 1 },

		bannerTitle  = "Activate the Boost",
		bannerBody   = "Click ACTIVATE to use your new Aura Rush boost!",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(103, 111, 255),
	},

	-- ✨ STEP 32: Spawn 30 Auras
	[32] = {
		id           = "a1_spawn_30",
		action       = "Action_Wait", 
		targetTag    = "Tutorial_ClickButton",
		allowClicking = true, 

		requireCubesProduced = 30,
		duration     = 0,

		bannerTitle  = "Double Spawn Speed",
		bannerBody   = "Your boost is now active. Produce 30 Auras with the increased spawn speed.",

		icon         = "rbxassetid://14914018910",
		color        = Color3.fromRGB(105, 255, 200),
	},

	-- ✨ STEP 33: Open Boost Shop Again
	[33] = {
		id           = "a1_open_boosts2",
		action       = "Action_OpenBoostShop",
		targetTag    = "Tutorial_BoostMenuBtn",

		bannerTitle  = "Buy More Boosts",
		bannerBody   = "Open up the boosts menu again to buy more boosts.",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(106, 255, 188),
	},

	-- ✨ STEP 34: Switch back to Shop Tab
	[34] = {
		id           = "a1_click_shop_tab",
		action       = "Action_BoostTab_Shop",
		targetTag    = "Tutorial_BoostTab_Shop",

		menuTag        = "Tutorial_BoostShopPanel",
		menuOpenBtnTag = "Tutorial_BoostMenuBtn",

		bannerTitle  = "Return to Shop",
		bannerBody   = "Click the SHOP tab to view the boosts available for purchase.",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(114, 213, 255),
	},

	-- ✨ STEP 35: Buy 5 Aura Spawners
	[35] = {
		id           = "a1_buy_boost3",
		action       = "Action_BuyBoost_AuraRush",
		targetTag    = "Tutorial_BuyBoost_AuraRush",

		menuTag        = "Tutorial_BoostShopPanel",
		menuOpenBtnTag = "Tutorial_BoostMenuBtn",
		duration = 0,
		requireBoostBought = { id = "AuraRush", count = 5 },

		bannerTitle  = "Buy More Aura Rush Boosts",
		bannerBody   = "Buy 5 more Aura Rush Boosts. Note Boosts can stack for even faster production and MONEY.",

		icon         = "rbxassetid://4483362458",
		color        = Color3.fromRGB(101, 255, 199),
	},

	-- ✨ STEP 36: Mass Produce 150 Auras
	[36] = {
		id           = "a1_spawn_150",
		action       = "Action_Wait",
		targetTag    = "Tutorial_ClickButton",
		allowClicking = true, 

		requireCubesProduced = 150,
		duration     = 0,

		bannerTitle  = "Mass Production",
		bannerBody   = "Produce 150 Auras. Don't forget you can use those boosts you just bought!",

		icon         = "rbxassetid://14914018910",
		color        = Color3.fromRGB(130, 226, 255),
	},

	-- ✨ STEP 37: Open Achievements
	[37] = {
		id           = "a1_open_achievements",
		action       = "Action_OpenAchievements",
		targetTag    = "Tutorial_AchieveMenuBtn",

		unlockTags    = {"Tutorial_AchieveMenuBtn", "Tutorial_AchieveCloseBtn", "Tutorial_AchieveTab_Challenges"},
		unlockActions = {"Action_OpenAchievements", "Action_CloseAchievements", "Action_ClickAchieveTab_Challenges"},

		bannerTitle  = "Achievements Unlocked!",
		bannerBody   = "You've hit a major milestone! Click the new Achievements button to view your Progression.",

		icon         = "rbxassetid://14923131909",
		color        = Color3.fromRGB(255, 200, 50),
	},

	-- ✨ STEP 38: Claim Boost Challenge
	[38] = {
		id           = "a1_claim_boost_chal",
		action       = "Action_ClaimChallenge_unlock_spawnboost",
		targetTag    = "Tutorial_AchieveRow_Chal_unlock_spawnboost",

		unlockTags    = {"Tutorial_AchieveRow_Chal_unlock_spawnboost"},
		unlockActions = {"Action_ClaimChallenge_unlock_spawnboost"},

		menuTag        = "Tutorial_AchievePanel",
		menuOpenBtnTag = "Tutorial_AchieveMenuBtn",

		bannerTitle  = "Claim Your Rewards",
		bannerBody   = "You reached Area 2! Click the green 'CLAIM' button on the Explorer challenge to unlock the Value Boost.",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(80, 255, 100),
	},

	-- ✨ STEP 39: Click Index Tab
	[39] = {
		id           = "a1_click_index_tab",
		action       = "Action_ClickAchieveTab_Index",
		targetTag    = "Tutorial_AchieveTab_Index",

		unlockTags    = {"Tutorial_AchieveTab_Index"},
		unlockActions = {"Action_ClickAchieveTab_Index"},

		menuTag        = "Tutorial_AchievePanel",
		menuOpenBtnTag = "Tutorial_AchieveMenuBtn",

		bannerTitle  = "The Aura Index",
		bannerBody   = "Click the Auras tab. Here you can track every single Aura you have discovered across all Areas!",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(100, 200, 255),
	},

	-- ✨ STEP 40: Claim Aura Index Reward
	[40] = {
		id           = "a1_claim_index_reward",
		action       = "Action_ClaimAura_1_Common",
		targetTag    = "Tutorial_AchieveRow_Index_1",

		unlockTags    = {"Tutorial_AchieveRow_Index_1"},
		unlockActions = {"Action_ClaimAura_1_Common"},

		menuTag        = "Tutorial_AchievePanel",
		menuOpenBtnTag = "Tutorial_AchieveMenuBtn",

		bannerTitle  = "Discovery Bonus",
		bannerBody   = "Click on the Area 1 Common Aura to claim a Golden Aura bonus for discovering it!",

		icon         = "rbxassetid://4483362458",
		color        = Color3.fromRGB(255, 215, 0),
	},

	-- ✨ STEP 41: Click Badges Tab
	[41] = {
		id           = "a1_click_badges_tab",
		action       = "Action_ClickAchieveTab_Badges",
		targetTag    = "Tutorial_AchieveTab_Badges",

		unlockTags    = {"Tutorial_AchieveTab_Badges"},
		unlockActions = {"Action_ClickAchieveTab_Badges"},

		menuTag        = "Tutorial_AchievePanel",
		menuOpenBtnTag = "Tutorial_AchieveMenuBtn",

		bannerTitle  = "Roblox Badges",
		bannerBody   = "Click the Badges tab. You can officially earn Roblox Badges for reaching massive milestones.",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(255, 100, 255),
	},

	-- ✨ STEP 42: Claim Badge
	[42] = {
		id           = "a1_claim_badge_1",
		action       = "Action_ClaimBadge_1", 
		targetTag    = "Tutorial_AchieveRow_Badge_1",

		unlockTags    = {"Tutorial_AchieveRow_Badge_1"},
		unlockActions = {"Action_ClaimBadge_1"},

		menuTag        = "Tutorial_AchievePanel",
		menuOpenBtnTag = "Tutorial_AchieveMenuBtn",

		bannerTitle  = "Claim Badge",
		bannerBody   = "Click the First Prestige badge to officially unlock it on your Roblox profile!",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(200, 150, 255),
	},

	-- ✨ STEP 43: Click Leaderboard Tab
	[43] = {
		id           = "a1_click_leaderboard",
		action       = "Action_ClickAchieveTab_Leaderboard",
		targetTag    = "Tutorial_AchieveTab_Leaderboard",

		unlockTags    = {"Tutorial_AchieveTab_Leaderboard"},
		unlockActions = {"Action_ClickAchieveTab_Leaderboard"},

		menuTag        = "Tutorial_AchievePanel",
		menuOpenBtnTag = "Tutorial_AchieveMenuBtn",

		bannerTitle  = "Global Rankings",
		bannerBody   = "Click the Top 10 tab to view the Global Leaderboard.",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(255, 150, 50),
	},

	-- ✨ STEP 44: Click Settings Tab
	[44] = {
		id           = "a1_click_settings",
		action       = "Action_ClickAchieveTab_Settings",
		targetTag    = "Tutorial_AchieveTab_Settings",

		unlockTags    = {"Tutorial_AchieveTab_Settings"},
		unlockActions = {"Action_ClickAchieveTab_Settings"},

		menuTag        = "Tutorial_AchievePanel",
		menuOpenBtnTag = "Tutorial_AchieveMenuBtn",

		bannerTitle  = "Customize Your Farm",
		bannerBody   = "Finally, click the Settings tab. You can customize the game audio and mechanics here.",

		icon         = "rbxassetid://14923131909",
		color        = Color3.fromRGB(150, 255, 255),
	},

	-- ✨ STEP 45: Toggle Jumping
	[45] = {
		id           = "a1_toggle_jump",
		action       = "Action_ToggleSetting_jump",
		targetTag    = "Tutorial_SettingToggle_jump",

		unlockTags    = {"Tutorial_SettingToggle_jump"},
		unlockActions = {"Action_ToggleSetting_jump"},

		menuTag        = "Tutorial_AchievePanel",
		menuOpenBtnTag = "Tutorial_AchieveMenuBtn",

		bannerTitle  = "Disable Jumping",
		bannerBody   = "Click to disable Jumping. (You can also quick-toggle jumping at any time by pressing 'T' on your keyboard!)",

		icon         = "rbxassetid://14923131909",
		color        = Color3.fromRGB(255, 100, 100),
	},

	-- ✨ STEP 46: Open Area Travel
	[46] = {
		id           = "a1_final_travel",
		action       = "Action_OpenTravel",
		targetTag    = "Tutorial_TravelButton",

		bannerTitle  = "Check the Next Area",
		bannerBody   = "Good job learning the mechanics to make a TON of money! Open the Area Panel",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(100, 255, 150),
	},

	-- ✨ STEP 47: Browse to Area 3
	[47] = {
		id             = "a1_travel_arrow_3",
		action         = "Action_ClickRightArrow",
		targetTag      = "Tutorial_RightArrow",

		menuTag        = "Tutorial_TravelPanel",
		menuOpenBtnTag = "Tutorial_TravelButton",
		fallbackStepId = "a1_final_travel", 

		bannerTitle  = "Browse Areas",
		bannerBody   = "Click the Arrows to view more areas",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(150, 200, 255),
	},

	-- ✨ STEP 48: Confirm Travel to Area 3 (End of Area 2)
	[48] = {
		id             = "a1_confirm_travel_3",
		action         = "Action_TravelConfirm",
		targetTag      = "Tutorial_TravelConfirm",

		menuTag        = "Tutorial_TravelPanel",
		menuOpenBtnTag = "Tutorial_TravelButton",
		fallbackStepId = "a1_final_travel",

		bannerTitle  = "Get yo money up",
		bannerBody   = "Once you have enough farm evaluation head to the next area to Unlock More Important Things!",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(107, 255, 161),
	},
}

function TutorialConfig.GetStepByIndex(index)
	return TutorialConfig.Steps[index]
end

function TutorialConfig.GetStepById(id)
	for _, step in ipairs(TutorialConfig.Steps) do
		if step.id == id then return step end
	end
	return nil
end

return TutorialConfig
