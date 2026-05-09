-- UIController
-- Location: StarterPlayer > StarterPlayerScripts > UIController

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local Debris            = game:GetService("Debris")
local UserInputService  = game:GetService("UserInputService") 
local CollectionService = game:GetService("CollectionService") -- ✨ NEW: Added for Tutorial Tags

local AdminConfig       = require(ReplicatedStorage.Modules.AdminConfig)
local Formatter         = require(ReplicatedStorage.Modules.NumberFormatter)
local UITheme           = require(ReplicatedStorage.Modules.UITheme)

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local UpdateHUD = ReplicatedStorage.RemoteEvents:WaitForChild("UpdateHUD")
local ShipAuras = ReplicatedStorage.RemoteEvents:WaitForChild("ShipAuras")
local HabitatFull = ReplicatedStorage.RemoteEvents:WaitForChild("HabitatFull")
local UpdateHatchery = ReplicatedStorage.RemoteEvents:WaitForChild("UpdateHatchery")
local mainHUD   = playerGui:WaitForChild("MainHUD")

local isAutoMode          = AdminConfig.AutoDispatch
local HabitatHolder       = workspace:WaitForChild("HabitatHolder")
local GoldenAurasLabel    = mainHUD:WaitForChild("GoldenAurasLabel")

local serverCurrency      = 0
local prevServerCurrency  = 0
local displayedCurrency   = 0
local ratePerSecond       = 0
local pendingAuras        = 0
local habitatCapacity     = AdminConfig.BaseHabitatCapacity
local passiveInterval     = AdminConfig.PassiveInterval
local currentCooldownTime = 15
local isShipOnCooldown    = false
local sharedCooldownEnd   = 0
local manualCooldownLoopID = 0
local lastSpendTick       = 0
local liveGoldenAuras     = 0
local autoLoopID          = 0
local isFirstCurrencySync = true
local currentHatcheryLevel = AdminConfig.HatcheryMax or 150 

-- [FIXED] Bypass math.floor so the formatter handles decimals properly
local function FormatNumber(n) return Formatter.Format(n) end

-- ─────────────────────────────────────────────────────────────────────────────
-- ✨ SYNCING VISUAL CASH & AURA TICK UP ✨
-- ─────────────────────────────────────────────────────────────────────────────
player:GetAttributeChangedSignal("VisualCashToAdd"):Connect(function()
	local addAmount = player:GetAttribute("VisualCashToAdd") or 0
	if addAmount > 0 then
		displayedCurrency += addAmount

		-- ✨ TUTORIAL FIX: Record strictly additive income for step goals
		if type(shared.TutorialRecordEarned) == "function" then shared.TutorialRecordEarned(addAmount) end

		player:SetAttribute("VisualCashToAdd", 0) 
	end
end)

player:GetAttributeChangedSignal("VisualAurasToAdd"):Connect(function()
	local addAmount = player:GetAttribute("VisualAurasToAdd") or 0
	if addAmount > 0 then
		liveGoldenAuras += addAmount
		GoldenAurasLabel.Text = "GAURAS: " .. FormatNumber(liveGoldenAuras) 
		player:SetAttribute("VisualAurasToAdd", 0) 
	end
end)

player:GetAttributeChangedSignal("LocalSpend"):Connect(function()
	local spend = player:GetAttribute("LocalSpend") or 0
	if spend > 0 then
		displayedCurrency = math.max(0, displayedCurrency - spend)
		lastSpendTick = tick()
		player:SetAttribute("LocalSpend", 0)
	end
end)

player:GetAttributeChangedSignal("LocalAuraSpend"):Connect(function()
	local spend = player:GetAttribute("LocalAuraSpend") or 0
	if spend > 0 then
		liveGoldenAuras = math.max(0, (liveGoldenAuras or 0) - spend)
		GoldenAurasLabel.Text = "GAURAS: " .. FormatNumber(liveGoldenAuras) 
		lastSpendTick = tick()
		player:SetAttribute("LocalAuraSpend", 0)
	end
end)

player:GetAttributeChangedSignal("ForceSyncCurrency"):Connect(function()
	local serverValue = player:GetAttribute("ForceSyncCurrency")
	if serverValue and serverValue > 0 then
		local diff = serverValue - displayedCurrency
		if diff > 0 and type(shared.TutorialRecordEarned) == "function" then 
			shared.TutorialRecordEarned(diff) 
		end

		displayedCurrency = serverValue
		player:SetAttribute("ForceSyncCurrency", 0)
	end
end)

local function FormatRate(perSecond)
	if perSecond <= 0 then return "$0/sec" end
	return "$" .. Formatter.Format(perSecond) .. "/sec"
end

local function GetRateColor(pending, capacity)
	local ratio = math.clamp((pending or 0) / (capacity or 50), 0, 1)
	if ratio >= 1        then return Color3.fromRGB(255, 60,  60)
	elseif ratio >= 0.75 then return Color3.fromRGB(255, 200,  0)
	elseif ratio >= 0.5  then return Color3.fromRGB(80,  255, 80)
	else                      return Color3.fromRGB(80,  180, 80)
	end
end

local function UpdateHabitatBar(pending, capacity)
	local ratio    = math.clamp((pending or 0) / (capacity or 50), 0, 1)
	local color    = GetRateColor(pending, capacity)
	local model    = HabitatHolder:FindFirstChild("HabitatModel")
	if model then
		local gui    = model:FindFirstChild("HabitatGui")
		local barBg  = gui and gui:FindFirstChild("BarBackground")
		local barFill = barBg and barBg:FindFirstChild("BarFill")
		if barFill then
			TweenService:Create(barFill, TweenInfo.new(0.3), {
				Size = UDim2.new(ratio, 0, 1, 0),
				BackgroundColor3 = color,
			}):Play()
		end
	end
end

local hud        = playerGui:WaitForChild("MainHUD")
local curr       = hud:WaitForChild("CurrencyLabel")
local rate       = hud:WaitForChild("RateLabel")
local sendButton = hud:WaitForChild("SendButton")
local modeToggle = hud:WaitForChild("ModeToggle")

-- ✨ TUTORIAL: Auto-tagging the UI elements
CollectionService:AddTag(sendButton, "Tutorial_SendShipBtn")
CollectionService:AddTag(modeToggle, "Tutorial_ToggleShipBtn")

-- ─────────────────────────────────────────────────────────────────────────────
-- ✨ WARNING POPUP SYSTEM
-- ─────────────────────────────────────────────────────────────────────────────
local activeAlerts = {}

local function ShowAlertPopup(alertType, text, iconColor)
	if tick() - (activeAlerts[alertType] or 0) < 2.5 then return end
	activeAlerts[alertType] = tick()

	local ratePos = rate.AbsolutePosition
	local rateSize = rate.AbsoluteSize

	local alertW = 200
	local alertH = 40
	local padding = 15

	local endX = ratePos.X - padding
	local startX = endX + 40
	local startY = ratePos.Y + (rateSize.Y / 2)

	local effectGui = Instance.new("ScreenGui")
	effectGui.Name = "AlertGui_" .. alertType
	effectGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	effectGui.Parent = playerGui

	local alertFrame = Instance.new("Frame")
	alertFrame.Size = UDim2.new(0, alertW, 0, alertH)
	alertFrame.AnchorPoint = Vector2.new(1, 0.5)
	alertFrame.Position = UDim2.new(0, startX, 0, startY)
	alertFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
	alertFrame.BorderSizePixel = 0
	alertFrame.BackgroundTransparency = 1 
	alertFrame.Parent = effectGui

	local corner = Instance.new("UICorner", alertFrame)
	corner.CornerRadius = UDim.new(0.5, 0)

	local stroke = Instance.new("UIStroke", alertFrame)
	stroke.Color = iconColor
	stroke.Thickness = 2
	stroke.Transparency = 1

	local icon = Instance.new("ImageLabel", alertFrame)
	icon.Size = UDim2.new(0, 20, 0, 20)
	icon.Position = UDim2.new(0, 10, 0.5, -10)
	icon.BackgroundTransparency = 1
	icon.Image = "rbxassetid://7733658504" 
	icon.ImageColor3 = iconColor
	icon.ImageTransparency = 1

	local msg = Instance.new("TextLabel", alertFrame)
	msg.Size = UDim2.new(1, -40, 1, 0)
	msg.Position = UDim2.new(0, 35, 0, 0)
	msg.BackgroundTransparency = 1
	msg.Text = text
	msg.TextColor3 = iconColor
	msg.Font = Enum.Font.GothamBold
	msg.TextScaled = true
	msg.TextTransparency = 1
	msg.TextXAlignment = Enum.TextXAlignment.Left

	local uipadding = Instance.new("UIPadding", msg)
	uipadding.PaddingTop = UDim.new(0, 6)
	uipadding.PaddingBottom = UDim.new(0, 6)

	local sfxFolder = ReplicatedStorage:FindFirstChild("SFX") or ReplicatedStorage:FindFirstChild("Sounds")
	if sfxFolder and sfxFolder:FindFirstChild("ErrorBuzz") then
		local sfx = sfxFolder.ErrorBuzz:Clone()
		sfx.Parent = game:GetService("SoundService")
		sfx.Volume = 0.5
		sfx:Play()
		Debris:AddItem(sfx, 2)
	end

	TweenService:Create(alertFrame, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0, endX, 0, startY),
		BackgroundTransparency = 0.1
	}):Play()
	TweenService:Create(stroke, TweenInfo.new(0.4), {Transparency = 0}):Play()
	TweenService:Create(icon, TweenInfo.new(0.4), {ImageTransparency = 0}):Play()
	TweenService:Create(msg, TweenInfo.new(0.4), {TextTransparency = 0}):Play()

	task.delay(2, function()
		if not alertFrame.Parent then return end
		TweenService:Create(alertFrame, TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
			Position = UDim2.new(0, startX, 0, startY),
			BackgroundTransparency = 1
		}):Play()
		TweenService:Create(stroke, TweenInfo.new(0.3), {Transparency = 1}):Play()
		TweenService:Create(icon, TweenInfo.new(0.3), {ImageTransparency = 1}):Play()
		TweenService:Create(msg, TweenInfo.new(0.3), {TextTransparency = 1}):Play()
		Debris:AddItem(effectGui, 0.4)
	end)
end

HabitatFull.OnClientEvent:Connect(function()
	ShowAlertPopup("HabitatFull", "HABITAT FULL!", Color3.fromRGB(255, 80, 80))
end)

UpdateHatchery.OnClientEvent:Connect(function(info)
	currentHatcheryLevel = info.current
	if info.current <= 0 then
		ShowAlertPopup("HatcheryEmpty", "HATCHERY EMPTY!", Color3.fromRGB(255, 180, 50))
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then

		local clickedMainButton = false
		if gameProcessed then
			local guis = playerGui:GetGuiObjectsAtPosition(input.Position.X, input.Position.Y)
			for _, gui in ipairs(guis) do
				if gui.Name == "ClickButton" then
					clickedMainButton = true
					break
				end
			end
		end

		if not clickedMainButton then return end

		if currentHatcheryLevel <= 0.5 then
			ShowAlertPopup("HatcheryEmpty", "HATCHERY EMPTY!", Color3.fromRGB(255, 180, 50))
		elseif pendingAuras >= habitatCapacity then
			ShowAlertPopup("HabitatFull", "HABITAT FULL!", Color3.fromRGB(255, 80, 80))
		end
	end
end)

local function SyncManualCooldownVisuals()
	if isAutoMode or not sendButton.Visible then return end

	local progressContainer = sendButton:FindFirstChild("CooldownProgress")
	local fillPart          = progressContainer and progressContainer:FindFirstChild("Fill")
	local textTarget        = sendButton:FindFirstChildOfClass("TextLabel") or sendButton

	local uiStroke = sendButton:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke", sendButton)
	uiStroke.Thickness = 1.5

	if not fillPart then return end

	sendButton.ClipsDescendants = true
	progressContainer.Size     = UDim2.new(1, 0, 1, 0)
	progressContainer.Position = UDim2.new(0, 0, 0, 0)
	progressContainer.AnchorPoint = Vector2.new(0, 0)

	fillPart.BorderSizePixel = 0
	fillPart.AnchorPoint     = Vector2.new(0, 1)
	fillPart.Position        = UDim2.new(0, 0, 1, 0)
	for _, child in ipairs(fillPart:GetChildren()) do
		if child:IsA("UICorner") or child:IsA("UIAspectRatioConstraint") or child:IsA("UIStroke") then
			child:Destroy()
		end
	end

	manualCooldownLoopID += 1
	local currentLoop = manualCooldownLoopID
	local timeLeft    = sharedCooldownEnd - tick()

	sendButton.BackgroundColor3    = Color3.fromRGB(0, 160, 255)
	uiStroke.Color                 = Color3.fromRGB(0, 220, 255)
	fillPart.BackgroundColor3      = Color3.fromRGB(0, 0, 0)
	fillPart.BackgroundTransparency = 0.55

	if timeLeft > 0 then
		isShipOnCooldown = true
		if textTarget ~= sendButton then sendButton.Text = "" end

		task.spawn(function()
			while timeLeft > 0 and manualCooldownLoopID == currentLoop do
				local pct = timeLeft / currentCooldownTime
				TweenService:Create(fillPart, TweenInfo.new(0.1, Enum.EasingStyle.Linear), {
					Size = UDim2.new(1, 0, pct, 0)
				}):Play()
				task.wait(0.1)
				timeLeft = sharedCooldownEnd - tick()
			end

			if manualCooldownLoopID == currentLoop then
				isShipOnCooldown  = false
				textTarget.Text   = ""
				fillPart.Size     = UDim2.new(1, 0, 0, 0)
			end
		end)
	else
		isShipOnCooldown = false
		textTarget.Text  = ""
		fillPart.Size    = UDim2.new(1, 0, 0, 0)
	end
end

local function UpdateSendButton()
	if AdminConfig.DisableShipping then sendButton.Visible = false; return end
	sendButton.Visible = not isAutoMode and (pendingAuras or 0) > 0
	if sendButton.Visible then
		SyncManualCooldownVisuals()
	end
end

local autoProgressContainer = Instance.new("Frame")
autoProgressContainer.Name             = "AutoProgressContainer"
autoProgressContainer.Size             = UDim2.new(0, 12, 1, 0)
autoProgressContainer.Position         = UDim2.new(1, 8, 0, 0)
autoProgressContainer.BackgroundColor3 = Color3.fromRGB(24, 60, 24)
autoProgressContainer.BorderSizePixel  = 0
autoProgressContainer.Visible          = false
autoProgressContainer.Parent           = modeToggle
Instance.new("UICorner", autoProgressContainer).CornerRadius = UDim.new(0.5, 0)

local autoStroke = Instance.new("UIStroke")
autoStroke.Color     = Color3.fromRGB(0, 255, 128)
autoStroke.Thickness = 1.5
autoStroke.Parent    = autoProgressContainer

local autoFillClip = Instance.new("Frame")
autoFillClip.Size                 = UDim2.new(1, 0, 1, 0)
autoFillClip.BackgroundTransparency = 1
autoFillClip.ClipsDescendants     = true
autoFillClip.Parent               = autoProgressContainer
Instance.new("UICorner", autoFillClip).CornerRadius = UDim.new(0.5, 0)

local autoFill = Instance.new("Frame")
autoFill.Name             = "Fill"
autoFill.Size             = UDim2.new(1, 0, 1, 0)
autoFill.Position         = UDim2.new(0, 0, 1, 0)
autoFill.AnchorPoint      = Vector2.new(0, 1)
autoFill.BackgroundColor3 = Color3.fromRGB(0, 255, 128)
autoFill.BorderSizePixel  = 0
autoFill.Parent           = autoFillClip

local function UpdateModeToggleVisuals()
	local textLabel = modeToggle:FindFirstChildOfClass("TextLabel") or modeToggle
	local uiStroke  = modeToggle:FindFirstChildOfClass("UIStroke")

	autoLoopID += 1
	local currentLoop = autoLoopID

	if isAutoMode then
		modeToggle.BackgroundColor3 = Color3.fromRGB(24, 60, 24)
		textLabel.Text              = "[AUTO ACTIVE]"
		textLabel.TextColor3        = Color3.fromRGB(0, 255, 128)
		if uiStroke then uiStroke.Color = Color3.fromRGB(0, 255, 128) end

		autoProgressContainer.Visible = true

		task.spawn(function()
			while isAutoMode and autoLoopID == currentLoop do
				local timeLeft = sharedCooldownEnd - tick()

				if timeLeft <= 0 then
					sharedCooldownEnd = tick() + currentCooldownTime
					timeLeft = currentCooldownTime

					if (pendingAuras or 0) > 0 then
						ShipAuras:FireServer("manual")
						if type(shared.TutorialRecordShipSent) == "function" then shared.TutorialRecordShipSent() end
					end
				end

				local pct = timeLeft / currentCooldownTime
				autoFill.Size = UDim2.new(1, 0, pct, 0)

				local tween = TweenService:Create(autoFill, TweenInfo.new(timeLeft, Enum.EasingStyle.Linear), {
					Size = UDim2.new(1, 0, 0, 0)
				})
				tween:Play()

				local elapsed = 0
				while elapsed < timeLeft and isAutoMode and autoLoopID == currentLoop do
					task.wait(0.1)
					elapsed += 0.1
				end

				if tween then tween:Cancel() end
			end
		end)
	else
		modeToggle.BackgroundColor3 = Color3.fromRGB(38, 38, 45)
		textLabel.Text              = "Mode: Manual"
		textLabel.TextColor3        = Color3.fromRGB(220, 230, 240)
		if uiStroke then uiStroke.Color = Color3.fromRGB(100, 180, 220) end

		autoProgressContainer.Visible = false
	end
end

---------------------------------------------------------------
-- ✨ SEND BUTTON CLICK
---------------------------------------------------------------
sendButton.MouseButton1Down:Connect(function()
	if AdminConfig.DisableShipping then return end
	if isAutoMode or isShipOnCooldown or (pendingAuras or 0) <= 0 then return end

	-- LOGIC GATING
	if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_SendShip") then return end

	ShipAuras:FireServer("manual")
	sharedCooldownEnd = tick() + currentCooldownTime
	SyncManualCooldownVisuals()

	-- ✨ FIX: Record ship sent locally to advance the FSM ship-payout step!
	if type(shared.TutorialRecordShipSent) == "function" then shared.TutorialRecordShipSent() end

	-- ADVANCE TUTORIAL
	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
end)

---------------------------------------------------------------
-- ✨ MODE TOGGLE CLICK
---------------------------------------------------------------
modeToggle.MouseButton1Down:Connect(function()
	if AdminConfig.DisableShipping then return end

	-- LOGIC GATING
	if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_ToggleAutoShip") then return end

	isAutoMode = not isAutoMode
	ShipAuras:FireServer("setMode", isAutoMode and "auto" or "manual")

	UpdateModeToggleVisuals()
	UpdateSendButton()

	-- ADVANCE TUTORIAL
	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
end)

UpdateModeToggleVisuals()
sendButton.Visible = false

if AdminConfig.DisableShipping then
	isAutoMode         = false
	sendButton.Visible = false
	modeToggle.Visible = false
end

-- ─────────────────────────────────────────────────────────────────────────────
-- UpdateHUD EVENT
-- ─────────────────────────────────────────────────────────────────────────────
UpdateHUD.OnClientEvent:Connect(function(stats)
	local serverPurchaseTick = player:GetAttribute("LastServerPurchaseTick") or 0
	local safeToSync = (tick() - math.max(lastSpendTick, serverPurchaseTick)) > 2.5

	if stats.goldenAuras ~= nil and safeToSync then
		local pendingAuras = player:GetAttribute("LocalPendingAuras") or 0
		local effectiveServerAuras = stats.goldenAuras - pendingAuras

		if effectiveServerAuras ~= liveGoldenAuras then
			liveGoldenAuras = effectiveServerAuras
			GoldenAurasLabel.Text = "GAURAS: " .. FormatNumber(liveGoldenAuras) 
		end
	end

	if stats.currency ~= nil then
		local newServerCurrency = stats.currency

		if safeToSync then
			local dynamicInterval = math.max(5, (passiveInterval or 1) * 2) 
			local snapThreshold = math.max(500, ratePerSecond * dynamicInterval)

			local pendingPayout = player:GetAttribute("LocalPendingPayout") or 0
			local effectiveServerCurrency = newServerCurrency - pendingPayout

			local diff = effectiveServerCurrency - displayedCurrency

			-- ✨ THE FIX: We completely deleted the "diff > snapThreshold" upward snap!
			-- The game will ONLY snap up exactly once when the player joins the game to load their save file.
			if isFirstCurrencySync then
				isFirstCurrencySync = false
				displayedCurrency = effectiveServerCurrency
			elseif diff < -snapThreshold then
				-- It is still allowed to snap DOWN (e.g., when buying upgrades or prestiging)
				displayedCurrency = effectiveServerCurrency
				curr.TextColor3 = Color3.fromRGB(255, 80, 80)
				TweenService:Create(curr, TweenInfo.new(0.4), {
					TextColor3 = Color3.fromRGB(255, 255, 255)
				}):Play()
			end
		end

		prevServerCurrency = newServerCurrency
		serverCurrency     = newServerCurrency
	end

	if stats.pendingAuras ~= nil then
		pendingAuras    = stats.pendingAuras
		habitatCapacity = stats.habitatCapacity or habitatCapacity
		UpdateHabitatBar(pendingAuras, habitatCapacity)
		UpdateSendButton()
	end

	if stats.rate ~= nil then
		passiveInterval = stats.passiveInterval or passiveInterval
		local serverRate = stats.rate
		ratePerSecond = (passiveInterval > 0 and serverRate > 0)
			and serverRate / passiveInterval or 0
		rate.Text = FormatRate(ratePerSecond)
		TweenService:Create(rate, TweenInfo.new(0.3), {
			TextColor3 = GetRateColor(pendingAuras, habitatCapacity)
		}):Play()
	end

	if stats.shipCooldown ~= nil then
		currentCooldownTime = stats.shipCooldown
	end
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- SMOOTH TICKER
-- ─────────────────────────────────────────────────────────────────────────────
RunService.RenderStepped:Connect(function(dt)
	if ratePerSecond > 0 then
		local added = ratePerSecond * dt
		displayedCurrency += added
		if type(shared.TutorialRecordEarned) == "function" then shared.TutorialRecordEarned(added) end
	end

	player:SetAttribute("LiveCurrency",     displayedCurrency)
	player:SetAttribute("LiveGoldenAuras",  liveGoldenAuras)
	curr.Text = "Currency: $" .. FormatNumber(displayedCurrency)
end)

local function RefreshLook()
	UITheme.ApplyFlair(GoldenAurasLabel, "GoldStroke")
end
task.wait(2)
RefreshLook()

Skip to main content
Creator Hub
Forum
DistanceFade - A transparency falloff effect for your games
Resources
Community Resources

Log in to Forum

​

​
DistanceFade - A transparency falloff effect for your games
Resources
Community Resources
Aug 2024
Jan 29

xander22
xander_z22

7
Aug 2024
Hi, I made this module for a game I’m working on and I wanted to release it to the community for use in your own projects

thumbnail
thumbnail
1280×540 42.3 KB

Showcase Video
What is DistanceFade?
DistanceFade is a module that aims to recreate transparency falloff shaders commonly found in games outside of Roblox.
The module essentially works by “projecting” the effect onto a table of target parts. The parts can be arranged with varying sizes and rotations to create different shapes for the effect (the thumbnail is 3 parts arranged in a curve, for example). 21 different customization settings allow for more complicated effects like animated textures, texture offsets, colors and more.

Note:
The module as it is now is more of a foundation than a perfect solution… it isn’t perfectly optimized and still has some flaws. I made it for a specific use case in my game (map barriers that fade in when close), but designed the module to be fairly flexible in what it can be used for. I probably won’t be updating it so feel free to modify and redistribute it as you see fit

If you like my work / want some more assets you can support me on Patreon
If you’re interested in other stuff I make it’ll be on my yt channel here

Examples




Awesome 3D illusion and color gradient effects by Powerbow
Really cool parallax mapping effect by Bobcat
Download
DistanceFade.rbxm (15.6 KB)

 Template models
Toolbox Model

Basic Usage
Step 1 - Initialization
Require the module and initialize it using the .new() constructor. You can have multiple forcefield objects running in the same script
local DistanceFade = require(game.ReplicatedStorage.DistanceFade) -- or wherever the module is located
local distanceFadeObj = DistanceFade.new() --initialize the object
Step 2 - Add target faces
DistanceFade works by applying the effect to individual BasePart faces. For every face you want to have the effect on, you need to use :AddFace() with 2 parameters, the target part and the Enum.NormalId of the face
local partToAdd -- can be any BasePart
distanceFadeObj:AddFace(partToAdd, Enum.NormalId.Front) -- can add to any face, in this case the front and back of the part
distanceFadeObj:AddFace(partToAdd, Enum.NormalId.Back)
Step 3 - Running the effect
Use :Step() to update the simulation at any time. Use Heartbeat for a visually smooth effect. TargetPos parameter is a Vector3
game:GetService("RunService").Heartbeat:Connect(function()
	local targetPos -- the position the effect is centered around
	distanceFadeObj:Step(targetPos) -- if parameter is nil, automatically targets local character's root part
end)
Step 4 - Apply settings
Use :UpdateSettings() to update the effect at any time (applies settings to all faces of that object). If you want to update the effect on individual faces, use :UpdateFaceSettings() (overwrites the object settings)
game:GetService("RunService").Heartbeat:Connect(function()
	local newSettings = {} --table of settings to modify. Full list below
	distanceFadeObj:UpdateSettings(newSettings)

	local targetPos -- the position the effect is centered around
	distanceFadeObj:Step(targetPos) -- if parameter is nil, automatically targets local character's root part
end)
Full list of settings:

local DEFAULT_SETTINGS = {
	["DistanceOuter"] = 16, -- Distance at which the effect starts to appear
	["DistanceInner"] = 4, -- Distance at which the effect is fully visible
	["EffectRadius"] = 16, -- Size of the effect when in range
	["EffectRadiusMin"] = 0, -- Size of the effect when out of range
	["EdgeDistanceCalculations"] = false, -- When set to true, distance to target is calculated from the face edges rather than the face itself. Can be more accurate in certain cases
	["Texture"] = "rbxassetid://18838056070", -- TextureId
	["TextureTransparency"] = 0, -- Transparency of the texture when in range
	["TextureTransparencyMin"] = 1, -- Transparency of the texture when out of range
	["BackgroundTransparency"] = 1, -- Transparency of the texture background when in range
	["BackgroundTransparencyMin"] = 1, -- Transparency of the texture background when out of range
	["TextureColor"] = Color3.fromRGB(255, 255, 255), -- Color of the texture
	["BackgroundColor"] = Color3.fromRGB(255, 255, 255), -- Color of the texture background
	["TextureSize"] = Vector2.new(8, 8), -- Size of the texture in studs per tile. Can potentially cause clipping issues if greater than EffectRadius * 2
	["TextureOffset"] = Vector2.new(0, 0), -- Texture offset in studs
	-- SurfaceGui settings
	["ZOffset"] = 0,
	["AlwaysOnTop"] = false,
	["Brightness"] = 1,
	["LightInfluence"] = 0,
	["MaxDistance"] = 1000,
	["PixelsPerStud"] = 100,
	["SizingMode"] = Enum.SurfaceGuiSizingMode.PixelsPerStud
}
More advanced examples can be found in the template models dropdown above. Also make sure to read through the module code if you want more in-depth explanations of each function. Please leave any questions or feedback and I’ll do my best to help


