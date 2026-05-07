-- MainMenuController
-- Location: StarterPlayer > StarterPlayerScripts > MainMenuController
--
-- Shows a title screen on join with the live game world as the background.
-- Camera locks to area-specific "MenuCamPos_N" Parts in Workspace.
-- Background is blurred using the existing UITheme MenuBlur system.
-- All sizes/positions driven by UIConfig.MainMenu, all colors from UITheme.
-- Player clicks PLAY → black fade transition → camera released → game begins.
--
-- GATE SYSTEM:
--   Creates a BindableEvent "MenuDismissed" in ReplicatedStorage.
--   Sets Attribute "Fired" = true and fires it after Play transition.
--   Other scripts check:
--     local _menuGate = ReplicatedStorage:WaitForChild("MenuDismissed")
--     if not _menuGate:GetAttribute("Fired") then _menuGate.Event:Wait() end
--
-- SETUP:
--   1. Place Parts in Workspace named "MenuCamPos_1", "MenuCamPos_2", etc.
--   2. Set each: Anchored=true, CanCollide=false, Transparency=1
--   3. Fly your Studio camera to the angle you want for that area
--   4. Run in Command Bar: workspace.MenuCamPos_1.CFrame = workspace.CurrentCamera.CFrame
--   5. Repeat for each area

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")

local UITheme = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UITheme"))
local T = UITheme.Get("Custom")
local C = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UIConfig"))
local M = C.MainMenu

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
local FADE_IN_TIME   = M.FadeInTime
local FADE_HOLD_TIME = M.FadeHoldTime
local FADE_OUT_TIME  = M.FadeOutTime
local IDLE_SPEED     = M.IdleSpeed
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
	if not anchor then
		warn("MainMenu: No MenuCamPos found for area " .. area)
		return
	end
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

-- Set initial camera (defaults to area 1, updates when server sends real area)
SnapCameraToArea(DEFAULT_AREA)
StartIdleDrift(DEFAULT_AREA)

-- ✨ NEW: LIFT THE BLACKOUT CURTAIN ✨
-- The camera is now securely locked, so it is safe to reveal the screen!
local blackoutGui = playerGui:FindFirstChild("PreloadBlackout")
if blackoutGui then
	local blackoutFrame = blackoutGui:FindFirstChild("BlackoutFrame")
	if blackoutFrame then
		-- Smoothly fade from pitch black into your gorgeous blurred Main Menu
		TweenService:Create(blackoutFrame, TweenInfo.new(1.0, Enum.EasingStyle.Sine), {
			BackgroundTransparency = 1
		}):Play()
	end
	-- Delete the GUI completely after it finishes fading
	task.delay(1.1, function() blackoutGui:Destroy() end)
end

-- Listen for the server to tell us the player's actual area
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
-- 3. BUILD THE MENU UI (SCALING FIX)
---------------------------------------------------------------
local menuScreen = Instance.new("ScreenGui")
menuScreen.Name = "MainMenu"
menuScreen.DisplayOrder = 100
menuScreen.IgnoreGuiInset = true
menuScreen.ResetOnSpawn = false
menuScreen.Parent = playerGui

-- Vignette overlay
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

-- NEW: Responsive Container bounded by a MaxSize constraint
local container = Instance.new("Frame")
container.Name = "MenuContainer"
container.Size = UDim2.new(0.9, 0, 0.6, 0) -- Uses 90% of screen width, 60% of height
container.Position = UDim2.new(0.05, 0, 0.2, 0) -- 5% from left, 20% down
container.BackgroundTransparency = 1
container.ZIndex = 2
container.Parent = menuScreen

-- Cap the maximum size so it looks great on massive PC screens too
local containerConstraint = Instance.new("UISizeConstraint")
containerConstraint.MaxSize = Vector2.new(600, 450)
containerConstraint.Parent = container

---------------------------------------------------------------
-- TITLE: "AURA INC" (Uses Scale instead of UIConfig Offsets)
---------------------------------------------------------------
local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "Title"
titleLabel.Size = UDim2.new(1, 0, 0.3, 0) -- 30% of the container height
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
titleShadow.Position = UDim2.new(0, 0, 0, 4) -- Tiny offset for shadow
titleShadow.ZIndex = 9
titleShadow.Parent = container

local titleStroke = Instance.new("UIStroke")
titleStroke.Color = T.accentPurple
titleStroke.Thickness = 2
titleStroke.Transparency = 0.3
titleStroke.Parent = titleLabel

---------------------------------------------------------------
-- SUBTITLE
---------------------------------------------------------------
local subtitleLabel = Instance.new("TextLabel")
subtitleLabel.Name = "Subtitle"
subtitleLabel.Size = UDim2.new(0.8, 0, 0.15, 0) -- 15% of container height
subtitleLabel.Position = UDim2.new(0, 0, 0.3, 0) -- Just below title
subtitleLabel.AnchorPoint = Vector2.new(0, 0)
subtitleLabel.BackgroundTransparency = 1
subtitleLabel.Text = "Idle Aura Factory"
subtitleLabel.TextColor3 = T.subText
subtitleLabel.TextScaled = true
subtitleLabel.Font = BODY_FONT
subtitleLabel.TextXAlignment = Enum.TextXAlignment.Left
subtitleLabel.ZIndex = 10
subtitleLabel.Parent = container

---------------------------------------------------------------
-- PLAY BUTTON (Scale size, constraint for aspect ratio)
---------------------------------------------------------------
local playBtn = Instance.new("TextButton")
playBtn.Name = "PlayButton"
playBtn.Size = UDim2.new(0.45, 0, 0.25, 0) -- 45% width of container, 25% height
playBtn.Position = UDim2.new(0, 0, 0.55, 0) -- Below subtitle
playBtn.AnchorPoint = Vector2.new(0, 0)
playBtn.BackgroundColor3 = T.buttonPrimary
playBtn.BorderSizePixel = 0
playBtn.Text = "PLAY"
playBtn.TextColor3 = T.headerText
playBtn.TextScaled = true
playBtn.Font = TITLE_FONT
playBtn.ZIndex = 10
playBtn.AutoButtonColor = false
playBtn.Parent = container

-- Keep the button looking like a rectangle, not a squished square
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

---------------------------------------------------------------
-- UI JUICE: Floating Menu & Play Button Polish
---------------------------------------------------------------
-- 1. Make the entire menu container gently float up and down
TweenService:Create(container, TweenInfo.new(2.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
	Position = container.Position - UDim2.new(0, 0, 0, 12)
}):Play()

-- 2. The Play Button Interactive Juice
local btnScale = Instance.new("UIScale", playBtn)
local isHovering = false

-- Subtle idle pulse (only runs when you aren't hovering over it)
task.spawn(function()
	while playBtn and playBtn.Parent do
		if not isHovering then
			TweenService:Create(btnScale, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {Scale = 1.03}):Play()
		end
		task.wait(1)
		if not playBtn or not playBtn.Parent then break end

		if not isHovering then
			TweenService:Create(btnScale, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {Scale = 1.0}):Play()
		end
		task.wait(1)
	end
end)

-- Hover Effects (Grow and change color)
playBtn.MouseEnter:Connect(function()
	isHovering = true
	TweenService:Create(btnScale, TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {Scale = 1.1}):Play()
	TweenService:Create(playBtn, TweenInfo.new(0.15), {BackgroundColor3 = T.accentPurple}):Play() -- Gives it a nice glow!
end)

-- Leave Effects (Shrink back to normal)
playBtn.MouseLeave:Connect(function()
	isHovering = false
	TweenService:Create(btnScale, TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {Scale = 1.0}):Play()
	TweenService:Create(playBtn, TweenInfo.new(0.2), {BackgroundColor3 = T.buttonPrimary}):Play()
end)

-- Click Down (Squish inwards)
playBtn.MouseButton1Down:Connect(function()
	TweenService:Create(btnScale, TweenInfo.new(0.1, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {Scale = 0.9}):Play()
	if shared.PlayUISound then shared.PlayUISound("6895079853") end -- Optional UI Click Sound
end)

-- Release Click (Bounce back out)
playBtn.MouseButton1Up:Connect(function()
	TweenService:Create(btnScale, TweenInfo.new(0.3, Enum.EasingStyle.Bounce), {Scale = 1.1}):Play()
end)

-- 3. Apply your UITheme Glass-ify features!
task.spawn(function()
	task.wait(0.5) -- Wait for UI to load
	if UITheme and UITheme.ApplyShine then
		UITheme.ApplyShine(playBtn)
	end
	if UITheme and UITheme.ApplyFlair then
		UITheme.ApplyFlair(titleLabel, "Ghost")
	end
end)

---------------------------------------------------------------
-- CREDITS LINE
---------------------------------------------------------------
local creditLabel = Instance.new("TextLabel")
creditLabel.Name = "Credits"
creditLabel.Size = UDim2.new(0.6, 0, 0.1, 0) -- 10% of container height
creditLabel.Position = UDim2.new(0, 0, 0.9, 0) -- Bottom of container
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
-- LOADING SCREEN OVERLAY (Starts invisible)
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
loadingText.TextTransparency = 1 -- Hidden initially
loadingText.ZIndex = 51
loadingText.Parent = blackFade

playBtn.MouseButton1Down:Connect(function()
	if hasPlayed then return end
	hasPlayed = true

	-- Disable button
	playBtn.Active = false
	playBtn.Text = ""

	-- Stop listening for area changes
	if areaConn then areaConn:Disconnect(); areaConn = nil end

	-- PHASE 1: Fade to black and show LOADING text
	TweenService:Create(blackFade, TweenInfo.new(FADE_IN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0
	}):Play()
	TweenService:Create(loadingText, TweenInfo.new(FADE_IN_TIME), {
		TextTransparency = 0
	}):Play()
	task.wait(FADE_IN_TIME)

	-- PHASE 2: While black — release camera, disable blur, show HUD
	if idleConn then idleConn:Disconnect(); idleConn = nil end

	-- Release camera
	camera.CameraType = savedCamType
	local character = player.Character or player.CharacterAdded:Wait()
	local humanoid = character:WaitForChild("Humanoid", 5)
	if humanoid then
		camera.CameraSubject = humanoid
	end

	-- Disable blur and show HUD *behind* the black screen
	UITheme.SetMenuVisible(false)
	mainHUD.Enabled = true

	-- Destroy menu visuals behind the black
	vignette:Destroy()
	container:Destroy()

	-- THE LOADING BUFFER: Wait for Roblox to load, then give scripts 2 seconds to safely sync
	if not game:IsLoaded() then game.Loaded:Wait() end
	loadingText.Text = "LOADING AURAS..."
	task.wait(2) 

	-- PHASE 3: Fade out from black to reveal gameplay
	TweenService:Create(blackFade, TweenInfo.new(FADE_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1
	}):Play()
	TweenService:Create(loadingText, TweenInfo.new(FADE_OUT_TIME), {
		TextTransparency = 1
	}):Play()
	task.wait(FADE_OUT_TIME)

	-- FIRE THE GATE — all waiting scripts now resume
	MenuDismissed:SetAttribute("Fired", true)
	MenuDismissed:Fire()

	-- Full cleanup
	menuScreen:Destroy()
end)

local function RefreshLook()
	UITheme.ApplyFlair(titleLabel, "Shine")	
	UITheme.ApplyFlair(subtitleLabel, "Shine")
	UITheme.ApplyFlair(creditLabel, "Shine")
	UITheme.ApplyFlair(playBtn, "Shine")
end

RefreshLook()
