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

-- AuraSpawner
-- Location: ServerScriptService > AuraSpawner

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local TierConfig     = require(ReplicatedStorage.Modules.TierConfig)
local UpgradeConfig  = require(ReplicatedStorage.Modules.UpgradeConfig)
local PrestigeModule = require(ReplicatedStorage.Modules.PrestigeModule)
local AdminConfig    = require(ReplicatedStorage.Modules.AdminConfig)
local MutationConfig = require(ReplicatedStorage.Modules.MutationConfig)
local AreaRegistry   = require(ReplicatedStorage.Modules.AreaRegistry)
local GameManager    = require(ServerScriptService.GameManager)
local BoostManager   = require(ServerScriptService.BoostManager)
local WeatherManager = require(ServerScriptService.WeatherManager) 

local HabitatFull    = ReplicatedStorage.RemoteEvents:WaitForChild("HabitatFull")

-- ✨ BRIDGENET2 UPGRADES
local BridgeNet2             = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))
local UpdateHUDBridge        = BridgeNet2.ServerBridge("UpdateHUD")
local ProduceAuraBridge      = BridgeNet2.ServerBridge("ProduceAura")
local AuraSpawnedBridge      = BridgeNet2.ServerBridge("AuraSpawned")
local UpdateHatcheryBridge   = BridgeNet2.ServerBridge("UpdateHatchery")
local CubeMutatedBatchBridge = BridgeNet2.ServerBridge("CubeMutatedBatch")
local CubeSmushedBridge      = BridgeNet2.ServerBridge("CubeSmushed")
local CubeStoredBridge       = BridgeNet2.ServerBridge("CubeStored")

local HABITAT_HOLDER = workspace:WaitForChild("HabitatHolder")
local HABITAT_PART   = HABITAT_HOLDER:WaitForChild("Position")
local AURA_HOLDER    = workspace:WaitForChild("AuraHolder") 

local lastFire          = {}
local holdStart         = {}
local hatchery          = {}

local function GetAreaAuraModels(areaId)
	local config = nil
	if type(AreaRegistry.GetArea) == "function" then
		config = AreaRegistry.GetArea(areaId)
	elseif type(AreaRegistry.GetAreaConfig) == "function" then
		config = AreaRegistry.GetAreaConfig(areaId)
	elseif AreaRegistry.Areas then
		config = AreaRegistry.Areas[areaId]
	end
	return config and config.auraModels or nil
end

local function GetHatcheryMax(data)
	local cfg = UpgradeConfig.GetUpgradeConfig("hatcheryCapacity")
	return (cfg and cfg.apply) and cfg.apply(data) or AdminConfig.HatcheryMax
end

local function GetHabitatCapacity(data)
	local cfg = UpgradeConfig.GetUpgradeConfig("habitatCapacity")
	return (cfg and cfg.apply) and cfg.apply(data) or AdminConfig.BaseHabitatCapacity
end

local function GetMutationSpeedMult(data)
	local cfg = UpgradeConfig.GetUpgradeConfig("mutationSpeed")
	return (cfg and cfg.apply) and cfg.apply(data) or 1
end

Players.PlayerAdded:Connect(function(p)
	hatchery[p.UserId] = AdminConfig.HatcheryMax
end)

Players.PlayerRemoving:Connect(function(p)
	hatchery[p.UserId]=nil; holdStart[p.UserId]=nil; lastFire[p.UserId]=nil
end)

task.spawn(function()
	local PR = ServerScriptService:WaitForChild("PrestigeReset", 30)
	if PR then
		PR.Event:Connect(function(player)
			local uid = player.UserId
			local data = GameManager.GetData(uid)
			hatchery[uid] = data and GetHatcheryMax(data) or AdminConfig.HatcheryMax
			holdStart[uid]=nil; lastFire[uid]=nil
		end)
	end
end)

task.spawn(function()
	while true do
		task.wait(0.1)
		for _, player in ipairs(Players:GetPlayers()) do
			local uid = player.UserId
			local data = GameManager.GetData(uid)
			local hatchMax = data and GetHatcheryMax(data) or AdminConfig.HatcheryMax
			local prev = hatchery[uid] or hatchMax

			if holdStart[uid] then
				hatchery[uid] = math.max(0, prev - AdminConfig.HatcheryDrainRate * 0.1)
			else
				hatchery[uid] = math.min(hatchMax, prev + AdminConfig.HatcheryRefillRate * 0.1)
			end

			if hatchery[uid] ~= prev then
				UpdateHatcheryBridge:Fire(player, { current=hatchery[uid], max=hatchMax })
			end

			if hatchery[uid] <= 0 and holdStart[uid] then
				holdStart[uid] = nil
				ReplicatedStorage.RemoteEvents.ForceStopHold:FireClient(player)
			end
		end
	end
end)

local function GetAFKSpeed(runtime)
	local idleTime = tick() - runtime.lastActiveTime
	local speed = MutationConfig.AFKDecay[1].speed
	for _, e in ipairs(MutationConfig.AFKDecay) do
		if idleTime >= e.time then speed = e.speed end
	end
	return speed
end

local function GetEffectiveFireRate(uid)
	local rushMult = BoostManager.GetSpawnRateMultiplier(uid)
	local weatherSpawnMult, _ = WeatherManager.GetMultipliers(uid)
	local effectiveFireRate = AdminConfig.FireRate / (rushMult * weatherSpawnMult)
	if effectiveFireRate < 0.05 then effectiveFireRate = 0.05 end
	return effectiveFireRate
end

local function SendHUDUpdate(player)
	local uid = player.UserId
	local data = GameManager.GetData(uid)
	local runtime = GameManager.GetRuntime(uid)
	if not data or not runtime then return end

	local storedCount = runtime.storedCubeCount or 0
	local activeMV = runtime.activeMutatedValue or 0

	local boostMult = BoostManager.GetValueMultiplier(uid) * BoostManager.GetSpawnRateMultiplier(uid)
	local displayRate = math.floor(activeMV * boostMult)

	local passTickCfg = UpgradeConfig.GetUpgradeConfig("passiveTickSpeed")
	local passInt = (passTickCfg and passTickCfg.apply) and passTickCfg.apply(data) or AdminConfig.PassiveInterval

	UpdateHUDBridge:Fire(player, {
		currency        = data.currency, 
		pendingAuras    = storedCount, 
		habitatCapacity = GetHabitatCapacity(data), 
		rate            = displayRate,
		passiveInterval = passInt, 
		totalEarned     = data.totalEarned or 0,
		soulAuras       = data.soulAuras or 0, 
		farmEvaluation  = data.farmEvaluation or 0,
		goldenAuras     = data.goldenAuras or 0, 
		boostInventory  = data.boostInventory or {},
		prestigeCount   = data.prestigeCount or 0,
		upgrades        = data.upgrades or {},
		totalCubesProduced = data.totalCubesProduced or 0,
		currentArea     = data.currentArea or 1,
		discoveredTiers = data.discoveredTiers or {},
		currentFireRate = GetEffectiveFireRate(uid) 
	})
end

task.spawn(function()
	while true do
		local tickInterval = AdminConfig.MutationTickInterval or MutationConfig.CheckInterval
		task.wait(tickInterval)

		for _, player in ipairs(Players:GetPlayers()) do
			local uid = player.UserId
			local data = GameManager.GetData(uid)
			local runtime = GameManager.GetRuntime(uid)
			if not data or not runtime then continue end

			local dt = tickInterval * GetAFKSpeed(runtime) * GetMutationSpeedMult(data) * (AdminConfig.MutationSpeedMultiplier or 1)
			local mutationBatch = {}
			local currentArea = data.currentArea or 1
			local areaModels = GetAreaAuraModels(currentArea)

			for cubeId, cube in pairs(runtime.cubes) do
				local oldMutatedValue = MutationConfig.GetMutatedValue(cube)
				local mutated = false

				local prev = cube.effectiveElapsed
				cube.effectiveElapsed += dt
				local pl = MutationConfig.GetValueBonusLevel(prev)
				local nl = MutationConfig.GetValueBonusLevel(cube.effectiveElapsed)

				if nl > pl then
					mutated = true
					local be = MutationConfig.ValueBonuses[nl]
					table.insert(mutationBatch, { 
						cubeId = cubeId, mutationType = "valueBonus", bonusLevel = nl, 
						bonusPercent = be and math.floor(be.bonus * 100) or 0 
					})
				end

				local maxTier = AdminConfig.MutationMaxTierIndex or 3
				local upgrades = 0

				while cube.tierIndex < maxTier and cube.tierIndex < #TierConfig.Tiers and upgrades < 5 do
					if areaModels then
						local nextTierName = TierConfig.Tiers[cube.tierIndex + 1].name
						if not areaModels[nextTierName] then break end
					end

					local timeSince = cube.effectiveElapsed - (cube.lastUpgradeElapsed or 0)
					local bestChance, bestTime = 0, 0
					for _, threshold in ipairs(MutationConfig.TierUpgrades) do
						if timeSince >= threshold.time then bestChance = threshold.chance; bestTime = threshold.time end
					end

					if bestChance <= 0 then break end

					if math.random() <= bestChance then
						local oldTier = TierConfig.Tiers[cube.tierIndex]
						cube.tierIndex += 1
						local newTier = TierConfig.Tiers[cube.tierIndex]
						cube.baseValue = math.floor(cube.baseValue * (newTier.multiplier/oldTier.multiplier))
						cube.color = newTier.color; cube.glow = newTier.glow; cube.tierName = newTier.name
						cube.lastUpgradeElapsed = (cube.lastUpgradeElapsed or 0) + bestTime
						upgrades += 1; mutated = true

						table.insert(mutationBatch, { 
							cubeId = cubeId, mutationType = "tierUpgrade",
							newColor = newTier.color, newGlow = newTier.glow, 
							tierName = newTier.name, currentArea = currentArea
						})

						if newTier.name == "Legendary" then data.totalLegendaryCubes = (data.totalLegendaryCubes or 0) + 1 end
					else break end
				end

				if mutated then
					local newMutatedValue = MutationConfig.GetMutatedValue(cube)
					runtime.totalMutatedValue = (runtime.totalMutatedValue or 0) + (newMutatedValue - oldMutatedValue)
					if not cube.isStored then runtime.activeMutatedValue = (runtime.activeMutatedValue or 0) + (newMutatedValue - oldMutatedValue) end
				end
			end

			if #mutationBatch > 0 then CubeMutatedBatchBridge:Fire(player, mutationBatch) end
			SendHUDUpdate(player)
		end
	end
end)

local function GetHoldMultiplier(holdTime, data)
	local upgrades = data and data.upgrades or {}
	local speedData = upgrades["multiplierSpeed"]
	local speedLevel = (typeof(speedData) == "table" and speedData.level) or (typeof(speedData) == "number" and speedData) or 0
	local playerMultSpeed = 1.0 + (speedLevel * 0.05)

	local playerMaxTier = 5
	local tierUnlocks = {
		{ upgradeId = "unlockOmniMult", tier = 10 }, { upgradeId = "unlockUniversalMult", tier = 9 },
		{ upgradeId = "unlockGodlyMult", tier = 8 }, { upgradeId = "unlockCosmicMult", tier = 7 },
		{ upgradeId = "unlockMythicMult", tier = 6 },
	}

	for _, tData in ipairs(tierUnlocks) do
		local lvl = upgrades[tData.upgradeId]
		local finalLvl = (typeof(lvl) == "table" and lvl.level) or (typeof(lvl) == "number" and lvl) or 0
		if finalLvl > 0 then playerMaxTier = tData.tier; break end
	end

	local effectiveTime = holdTime * playerMultSpeed
	local currentTier = 1

	for i = 1, playerMaxTier do
		if AdminConfig.MilestoneData[i] and effectiveTime >= AdminConfig.MilestoneData[i].time then currentTier = i end
	end

	local nextTier = math.min(currentTier + 1, playerMaxTier)
	if currentTier == playerMaxTier then return AdminConfig.MilestoneData[currentTier].mult, AdminConfig.MilestoneData[currentTier].luck end

	local timePassed = effectiveTime - AdminConfig.MilestoneData[currentTier].time
	local timeNeeded = AdminConfig.MilestoneData[nextTier].time - AdminConfig.MilestoneData[currentTier].time
	local ratio = timePassed / timeNeeded

	local cMult = AdminConfig.MilestoneData[currentTier].mult
	local nMult = AdminConfig.MilestoneData[nextTier].mult
	local smoothMult = cMult + ((nMult - cMult) * ratio)

	return smoothMult, AdminConfig.MilestoneData[currentTier].luck
end

local function RollWithLuck(luckBonus)
	local tiers = TierConfig.Tiers
	local adjusted, total = {}, 0
	for _, tier in ipairs(tiers) do
		local chance = tier.chance
		if tier.name ~= "Common" then chance += luckBonus/(#tiers-1) end
		table.insert(adjusted, { tier=tier, chance=chance })
		total += chance
	end

	local r, cum = math.random() * total, 0
	for _, e in ipairs(adjusted) do cum += e.chance; if r <= cum then return e.tier end end
	return tiers[1]
end

local function SpawnAura(player, data, runtime, holdMult, luckBonus)
	local uid  = player.UserId
	local tier = RollWithLuck(luckBonus)
	local tierIndex = 1
	for i, t in ipairs(TierConfig.Tiers) do if t.name == tier.name then tierIndex=i; break end end

	local currentArea = data.currentArea or 1
	local areaModels = GetAreaAuraModels(currentArea)

	if areaModels then
		while tierIndex > 1 do
			local checkName = TierConfig.Tiers[tierIndex].name
			if areaModels[checkName] then break end
			tierIndex -= 1
		end
		tier = TierConfig.Tiers[tierIndex] 
	end

	local totalValueMultiplier = 1.0 
	local valueUpgrades = {"blockValue", "blockValueT2", "auraValueT3", "auraValueT4", "auraValueT6", "auraValueT8", "auraValueT10"}

	for _, upgradeId in ipairs(valueUpgrades) do
		local cfg = UpgradeConfig.GetUpgradeConfig(upgradeId)
		if cfg and cfg.apply then totalValueMultiplier += cfg.apply(data) end
	end

	local prestigeMult    = PrestigeModule.GetMultiplier(data.soulAuras)
	local areaMult        = AreaRegistry.GetMultiplier(data.currentArea or 1)
	local boostValueMult  = BoostManager.GetValueMultiplier(uid)
	local _, weatherValueMult = WeatherManager.GetMultipliers(uid)

	local calcMultFloat = totalValueMultiplier * prestigeMult * areaMult * boostValueMult * weatherValueMult
	local baseValue = math.floor(AdminConfig.BaseAuraValue * tier.multiplier * calcMultFloat)
	local totalValue = baseValue + math.floor(baseValue * (holdMult - 1))

	local spawnPos = HABITAT_PART.Position + Vector3.new(math.random(-3,3), 10, math.random(-3,3))	

	local areaFolder = ReplicatedStorage:FindFirstChild("AreaAssets") and ReplicatedStorage.AreaAssets:FindFirstChild("Area" .. currentArea)
	if areaFolder then
		local auraModel = areaFolder:FindFirstChild("AuraModel")
		if auraModel then
			local spawnPoint = auraModel:FindFirstChild("AuraSpawnPoint", true)
			if spawnPoint and spawnPoint:IsA("BasePart") then
				local size = spawnPoint.Size
				local randX = (math.random() - 0.5) * size.X
				local randZ = (math.random() - 0.5) * size.Z
				spawnPos = (spawnPoint.CFrame * CFrame.new(randX, 0, randZ)).Position
			end
		end
	end

	local cubeRecord = { spawnTime=tick(), effectiveElapsed=0, lastUpgradeElapsed=0, baseValue=totalValue, tierIndex=tierIndex, tierName=tier.name, color=tier.color, glow=tier.glow, isStored=false, currentArea=currentArea }

	if AdminConfig.MutationInstantMax then
		local mb = MutationConfig.ValueBonuses[#MutationConfig.ValueBonuses]
		if mb then cubeRecord.effectiveElapsed = mb.time + 1 end
	end

	local cubeId = GameManager.AddCube(uid, cubeRecord)
	if not cubeId then return end

	data.totalCubesProduced = (data.totalCubesProduced or 0) + 1
	if tier.name == "Legendary" then data.totalLegendaryCubes = (data.totalLegendaryCubes or 0) + 1 end
	runtime.lastActiveTime = tick()

	AuraSpawnedBridge:Fire(player, { cubeId=cubeId, tier=tier.name, color=tier.color, glow=tier.glow, value=totalValue, spawnPos=spawnPos, currentArea = currentArea })
end

ProduceAuraBridge:Connect(function(player, action)
	local uid = player.UserId
	local now = tick()
	local data = GameManager.GetData(uid)
	local runtime = GameManager.GetRuntime(uid)

	if action == "start" then 
		if data and runtime then
			local storedCount = runtime.storedCubeCount or 0
			if storedCount >= GetHabitatCapacity(data) then HabitatFull:FireClient(player); return end
		end
		if (hatchery[uid] or 0) > 0.5 then holdStart[uid] = now 
		else UpdateHatcheryBridge:Fire(player, { current = 0, max = data and GetHatcheryMax(data) or AdminConfig.HatcheryMax }) end
		return 
	end

	if action == "stop" then holdStart[uid] = nil; return end
	if not data or not runtime then return end

	local capacity = GetHabitatCapacity(data)
	local storedCount = runtime.storedCubeCount or 0

	if storedCount >= capacity then HabitatFull:FireClient(player); return end

	-- ✨ THE FIX: We bumped the conveyor backup failsafe from 150 to 600 so fast boosts don't falsely trigger the anti-lag cutoff!
	if runtime.cubeCount >= capacity + 600 then return end 

	if (hatchery[uid] or 0) <= 0.5 then 
		UpdateHatcheryBridge:Fire(player, { current = 0, max = data and GetHatcheryMax(data) or AdminConfig.HatcheryMax })
		return 
	end
	if not holdStart[uid] then return end

	local rushMult = BoostManager.GetSpawnRateMultiplier(uid)
	local weatherSpawnMult, _ = WeatherManager.GetMultipliers(uid)
	local effectiveFireRate = AdminConfig.FireRate / (rushMult * weatherSpawnMult)
	local spawnCount = 1

	if effectiveFireRate < 0.05 then
		spawnCount = math.floor(0.05 / effectiveFireRate)
		effectiveFireRate = 0.05
	end

	if lastFire[uid] then
		local timeSinceLast = now - lastFire[uid]
		if timeSinceLast < (effectiveFireRate - 0.015) then return end 
	end
	lastFire[uid] = now

	local holdTime = now - holdStart[uid]
	local holdMult, luckBonus = GetHoldMultiplier(holdTime, data)

	for i = 1, spawnCount do SpawnAura(player, data, runtime, holdMult, luckBonus) end
	SendHUDUpdate(player)
	UpdateHatcheryBridge:Fire(player, { current=hatchery[uid], max=GetHatcheryMax(data) })
end)

CubeStoredBridge:Connect(function(player, cubeId)
	local uid = player.UserId
	local runtime = GameManager.GetRuntime(uid)
	local data = GameManager.GetData(uid)
	if runtime and runtime.cubes[cubeId] then
		GameManager.MarkCubeStored(uid, cubeId)
		SendHUDUpdate(player)
		local storedCount = runtime.storedCubeCount or 0
		if storedCount >= GetHabitatCapacity(data) then HabitatFull:FireClient(player) end
	end
end)

CubeSmushedBridge:Connect(function(player, cubeId)
	local uid = player.UserId
	GameManager.RemoveCube(uid, cubeId)
	SendHUDUpdate(player)
	local data = GameManager.GetData(uid)
	UpdateHatcheryBridge:Fire(player, { current = hatchery[uid], max = GetHatcheryMax(data) })
end)
