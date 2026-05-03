-- PassiveIncome
-- Location: ServerScriptService > PassiveIncome

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AdminConfig    = require(ReplicatedStorage.Modules.AdminConfig)
local UpgradeConfig  = require(ReplicatedStorage.Modules.UpgradeConfig)
local GameManager    = require(ServerScriptService.GameManager)
local BoostManager   = require(ServerScriptService.BoostManager)
local UpdateHUD      = ReplicatedStorage.RemoteEvents:WaitForChild("UpdateHUD")

if script:GetAttribute("Running") then script:Destroy(); return end
script:SetAttribute("Running", true)

local RemoteEvents   = ReplicatedStorage:WaitForChild("RemoteEvents")
local TutorialFreeze = RemoteEvents:FindFirstChild("TutorialFreeze")
if not TutorialFreeze then
	TutorialFreeze      = Instance.new("RemoteEvent")
	TutorialFreeze.Name = "TutorialFreeze"
	TutorialFreeze.Parent = RemoteEvents
end

TutorialFreeze.OnServerEvent:Connect(function(player, isFrozen)
	player:SetAttribute("TutorialFrozen", isFrozen)
end)

local function GetPassiveInterval(data)
	local cfg = UpgradeConfig.GetUpgradeConfig("passiveTickSpeed")
	if cfg and cfg.apply then return cfg.apply(data) end
	return AdminConfig.PassiveInterval
end

local function GetHabitatCapacity(data)
	local cfg = UpgradeConfig.GetUpgradeConfig("habitatCapacity")
	if cfg and cfg.apply then return cfg.apply(data) end
	return AdminConfig.BaseHabitatCapacity
end

local playerTimers       = {}  
local lastSentCurrency   = {}  

Players.PlayerAdded:Connect(function(p)
	playerTimers[p.UserId]     = 0
	lastSentCurrency[p.UserId] = 0
end)

Players.PlayerRemoving:Connect(function(p)
	playerTimers[p.UserId]     = nil
	lastSentCurrency[p.UserId] = nil
end)

while true do
	task.wait(0.5)

	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("TutorialFrozen") then continue end

		local uid     = player.UserId
		local data    = GameManager.GetData(uid)
		local runtime = GameManager.GetRuntime(uid)
		if not data or not runtime then continue end
		if runtime.cubeCount <= 0 then continue end

		local interval = GetPassiveInterval(data)
		playerTimers[uid] = (playerTimers[uid] or 0) + 0.5

		if playerTimers[uid] >= interval then
			playerTimers[uid] = 0

			local totalMutatedValue = runtime.totalMutatedValue
			local boostMult         = BoostManager.GetValueMultiplier(uid) * BoostManager.GetSpawnRateMultiplier(uid)
			local passiveEarned     = math.floor(totalMutatedValue * boostMult)
			if passiveEarned <= 0 then continue end

			data.currency       = (data.currency       or 0) + passiveEarned
			data.totalEarned    = (data.totalEarned     or 0) + passiveEarned
			data.farmEvaluation = (data.farmEvaluation  or 0) + passiveEarned

			if data.currency ~= lastSentCurrency[uid] then
				lastSentCurrency[uid] = data.currency

				local habitatCap = GetHabitatCapacity(data)
				local pending    = runtime.cubeCount
				local avgValue   = pending > 0 and (totalMutatedValue / pending) or AdminConfig.BaseAuraValue
				local rate       = math.floor(pending * avgValue * boostMult)

				UpdateHUD:FireClient(player, {
					currency        = data.currency,
					pendingAuras    = pending,
					habitatCapacity = habitatCap,
					rate            = rate,
					passiveInterval = interval,
					totalEarned     = data.totalEarned    or 0,
					soulAuras       = data.soulAuras      or 0,
					farmEvaluation  = data.farmEvaluation or 0,
				})
			end
		end
	end
end

-- UIController
-- Location: StarterPlayer > StarterPlayerScripts > UIController

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local Debris            = game:GetService("Debris")
local UserInputService  = game:GetService("UserInputService") 
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

local currentHatcheryLevel = AdminConfig.HatcheryMax or 150 

local function FormatNumber(n) return Formatter.Format(math.floor(n)) end

-- ─────────────────────────────────────────────────────────────────────────────
-- ✨ SYNCING VISUAL CASH & AURA TICK UP ✨
-- ─────────────────────────────────────────────────────────────────────────────
player:GetAttributeChangedSignal("VisualCashToAdd"):Connect(function()
	local addAmount = player:GetAttribute("VisualCashToAdd") or 0
	if addAmount > 0 then
		displayedCurrency += addAmount
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

-- ✨ FIX: Force sync currency when server confirms purchase
player:GetAttributeChangedSignal("ForceSyncCurrency"):Connect(function()
	local serverValue = player:GetAttribute("ForceSyncCurrency")
	if serverValue and serverValue > 0 then
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

-- ─────────────────────────────────────────────────────────────────────────────
-- ✨ WARNING POPUP SYSTEM (HABITAT FULL / EMPTY HATCHERY)
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

-- ✨ INSTANT LOCAL CLICK DETECTION (Filtered strictly to the red Clicker Button)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then

		local clickedMainButton = false

		-- Only check if they actually clicked a UI element
		if gameProcessed then
			local guis = playerGui:GetGuiObjectsAtPosition(input.Position.X, input.Position.Y)
			for _, gui in ipairs(guis) do
				-- ✨ FIX: Now it EXACTLY targets the "ClickButton" you showed in the screenshot!
				if gui.Name == "ClickButton" then
					clickedMainButton = true
					break
				end
			end
		end

		-- If they clicked the background, the shop, or the screen travel button, ignore it.
		if not clickedMainButton then return end

		-- Trigger the error if they are clicking the red button when they shouldn't be
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

sendButton.MouseButton1Down:Connect(function()
	if AdminConfig.DisableShipping then return end
	if isAutoMode or isShipOnCooldown or (pendingAuras or 0) <= 0 then return end

	ShipAuras:FireServer("manual")
	sharedCooldownEnd = tick() + currentCooldownTime
	SyncManualCooldownVisuals()
end)

modeToggle.MouseButton1Down:Connect(function()
	if AdminConfig.DisableShipping then return end

	isAutoMode = not isAutoMode
	ShipAuras:FireServer("setMode", isAutoMode and "auto" or "manual")

	UpdateModeToggleVisuals()
	UpdateSendButton()
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

			if diff > snapThreshold then
				displayedCurrency = effectiveServerCurrency
				curr.TextColor3 = Color3.fromRGB(80, 255, 80)
				TweenService:Create(curr, TweenInfo.new(0.4), {
					TextColor3 = Color3.fromRGB(255, 255, 255)
				}):Play()

			elseif diff < -snapThreshold then
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
		displayedCurrency += ratePerSecond * dt
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
