-- ShippingManager
-- Location: ServerScriptService > ShippingManager
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local HttpService = game:GetService("HttpService")

local AdminConfig = require(ReplicatedStorage.Modules.AdminConfig)
local UpgradeConfig = require(ReplicatedStorage.Modules.UpgradeConfig)
local MutationConfig = require(ReplicatedStorage.Modules.MutationConfig)
local GameManager = require(ServerScriptService.GameManager)
local EpicUpgradeConfig = require(ReplicatedStorage.Modules.EpicUpgradeConfig)
local ShipAuras = ReplicatedStorage.RemoteEvents:WaitForChild("ShipAuras")
local UpdateHUD = ReplicatedStorage.RemoteEvents:WaitForChild("UpdateHUD")

local playerTimers = {}
local activeTrucks = {}
local playerAutoMode = {}
local pendingPayouts = {} -- SECURE PAYOUT STORAGE: [uid] = { [dispatchId] = amount }

Players.PlayerAdded:Connect(function(player)
	playerTimers[player.UserId] = AdminConfig.ShipInterval
	activeTrucks[player.UserId] = 0
	playerAutoMode[player.UserId] = AdminConfig.AutoDispatch
	pendingPayouts[player.UserId] = {}
end)

Players.PlayerRemoving:Connect(function(player)
	playerTimers[player.UserId] = nil
	activeTrucks[player.UserId] = nil
	playerAutoMode[player.UserId] = nil
	pendingPayouts[player.UserId] = nil
end)

local function SendHUDUpdate(player)
	local uid = player.UserId
	local data = GameManager.GetData(uid)
	local runtime = GameManager.GetRuntime(uid)
	if not data or not runtime then return end

	-- No more looping! Instant O(1) lookup.
	local totalMutatedValue = runtime.totalMutatedValue

	local pending = runtime.cubeCount
	local avgValue = pending > 0 and (totalMutatedValue / pending) or AdminConfig.BaseAuraValue
	local rate = math.floor(pending * avgValue)

	local habCfg = UpgradeConfig.GetUpgradeConfig("habitatCapacity")
	local habitatCap = (habCfg and habCfg.apply) and habCfg.apply(data) or AdminConfig.BaseHabitatCapacity

	local tickCfg = UpgradeConfig.GetUpgradeConfig("passiveTickSpeed")
	local passiveInt = (tickCfg and tickCfg.apply) and tickCfg.apply(data) or AdminConfig.PassiveInterval

	-- ✨ NEW: Calculate the upgraded cooldown time
	local shipReduction = 0
	local shipCfg = EpicUpgradeConfig.GetUpgradeConfig("epicShipCooldown")
	if shipCfg and shipCfg.apply then
		shipReduction = shipCfg.apply(data)
	end
	local finalCooldown = math.max(1, AdminConfig.ShipInterval - shipReduction)

	UpdateHUD:FireClient(player, {
		currency        = data.currency,
		pendingAuras    = pending,
		habitatCapacity = habitatCap,
		rate            = rate,
		passiveInterval = passiveInt,
		totalEarned     = data.totalEarned    or 0,
		soulAuras       = data.soulAuras      or 0,
		farmEvaluation  = data.farmEvaluation or 0,
		shipCooldown    = finalCooldown, -- ✨ SEND TO UI!
	})
end

local function TryDispatch(player)
	if AdminConfig.DisableShipping then return end
	local uid = player.UserId
	local data = GameManager.GetData(uid)
	local runtime = GameManager.GetRuntime(uid)
	if not data or not runtime then return end
	-- ✨ MAX TRUCKS FIX: Allow up to 50 queued trucks so fast upgraded cooldowns are never blocked!
	if (activeTrucks[uid] or 0) >= 50 then return end
	local totalCubes = runtime.cubeCount
	if totalCubes <= 0 then return end

	local toCollect = math.min(totalCubes, AdminConfig.PlatformCapacity)
	local cubeIds, cubes = GameManager.CollectOldestCubes(uid, toCollect)
	local collected = #cubeIds
	if collected == 0 then return end

	local totalPayout = 0
	for _, cube in ipairs(cubes) do
		totalPayout = totalPayout + MutationConfig.GetMutatedValue(cube)
	end

	activeTrucks[uid] = (activeTrucks[uid] or 0) + 1
	data.totalPlatformsShipped = (data.totalPlatformsShipped or 0) + 1

	-- SECURE ID GENERATION
	local dispatchId = HttpService:GenerateGUID(false)
	pendingPayouts[uid][dispatchId] = totalPayout

	SendHUDUpdate(player)

	ShipAuras:FireClient(player, {
		collected  = collected,
		payout     = totalPayout,
		dispatchId = dispatchId -- Send ID to client instead of trusting it later
	})
end

ShipAuras.OnServerEvent:Connect(function(player, action, value)
	local uid = player.UserId

	if action == "manual" then
		TryDispatch(player)

		-- ✨ SERVER FIX 1: Reset the server's auto-timer when they manually ship!
		-- This prevents the server from accidentally double-shipping 1 second later.
		local data = GameManager.GetData(uid)
		local shipReduction = 0
		if data then
			local shipCfg = EpicUpgradeConfig.GetUpgradeConfig("epicShipCooldown")
			if shipCfg and shipCfg.apply then shipReduction = shipCfg.apply(data) end
		end
		playerTimers[uid] = math.max(1, AdminConfig.ShipInterval - shipReduction)
		return
	end

	if action == "setMode" then
		playerAutoMode[uid] = (value == "auto")
		-- ✨ SERVER FIX 2: We REMOVED the timer reset here! 
		-- Now the server perfectly preserves the exact time left, just like the UI!
		return
	end

	if action == "payout" then
		if player:GetAttribute("TutorialFrozen") then return end
		local data = GameManager.GetData(uid)
		if not data then return end

		-- SECURITY CHECK: value is now the dispatchId, NOT the money amount
		local dispatchId = value
		local actualPayout = pendingPayouts[uid] and pendingPayouts[uid][dispatchId]

		if not actualPayout then 
			warn("[Security] Player " .. player.Name .. " attempted invalid platform payout.")
			return 
		end

		-- Clear the memory so it can't be fired twice
		pendingPayouts[uid][dispatchId] = nil

		activeTrucks[uid] = math.max(0, (activeTrucks[uid] or 1) - 1)
		data.currency       = (data.currency or 0)       + actualPayout
		data.totalEarned    = (data.totalEarned or 0)    + actualPayout
		data.farmEvaluation = (data.farmEvaluation or 0) + actualPayout

		SendHUDUpdate(player)
	end
end)

-- PassiveIncome
-- Location: ServerScriptService > PassiveIncome
-- CHANGE: farmEvaluation now included in UpdateHUD payload so client
--         gets the real value on every passive tick without waiting for AreaUpdated.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AdminConfig = require(ReplicatedStorage.Modules.AdminConfig)
local UpgradeConfig = require(ReplicatedStorage.Modules.UpgradeConfig)
local MutationConfig = require(ReplicatedStorage.Modules.MutationConfig)
local GameManager = require(ServerScriptService.GameManager)

local UpdateHUD = ReplicatedStorage.RemoteEvents:WaitForChild("UpdateHUD")

if script:GetAttribute("Running") then script:Destroy() return end
script:SetAttribute("Running", true)

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

local playerTimers = {}

Players.PlayerAdded:Connect(function(p) playerTimers[p.UserId] = 0 end)
Players.PlayerRemoving:Connect(function(p) playerTimers[p.UserId] = nil end)

while true do
	task.wait(0.5)
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("TutorialFrozen") then continue end
		local uid = player.UserId
		local data = GameManager.GetData(uid)
		local runtime = GameManager.GetRuntime(uid)
		if not data or not runtime then continue end
		if runtime.cubeCount <= 0 then continue end

		local interval = GetPassiveInterval(data)
		playerTimers[uid] = (playerTimers[uid] or 0) + 0.5

		if playerTimers[uid] >= interval then
			playerTimers[uid] = 0

			-- No more looping! Instant O(1) lookup.
			local totalMutatedValue = runtime.totalMutatedValue

			local passiveEarned = math.floor(totalMutatedValue)
			if passiveEarned <= 0 then continue end

			data.currency       = (data.currency or 0)       + passiveEarned
			data.totalEarned    = (data.totalEarned or 0)    + passiveEarned
			data.farmEvaluation = (data.farmEvaluation or 0) + passiveEarned

			local habitatCap = GetHabitatCapacity(data)
			local pending = runtime.cubeCount
			local avgValue = pending > 0 and (totalMutatedValue / pending) or AdminConfig.BaseAuraValue
			local rate = math.floor(pending * avgValue)

			UpdateHUD:FireClient(player, {
				currency        = data.currency,
				pendingAuras    = pending,
				habitatCapacity = habitatCap,
				rate            = rate,
				passiveInterval = interval,
				totalEarned     = data.totalEarned     or 0,
				soulAuras       = data.soulAuras       or 0,
				farmEvaluation  = data.farmEvaluation  or 0,  -- ADDED
			})
		end
	end
end

-- Put this at the very bottom of ServerScriptService > PassiveIncome
local RemoteEvents = game:GetService("ReplicatedStorage"):WaitForChild("RemoteEvents")
local TutorialFreeze = RemoteEvents:FindFirstChild("TutorialFreeze")

-- If the event doesn't exist yet, create it automatically!
if not TutorialFreeze then
	TutorialFreeze = Instance.new("RemoteEvent")
	TutorialFreeze.Name = "TutorialFreeze"
	TutorialFreeze.Parent = RemoteEvents
end

TutorialFreeze.OnServerEvent:Connect(function(player, isFrozen)
	player:SetAttribute("TutorialFrozen", isFrozen)
end)

-- UIController
-- Location: StarterPlayer > StarterPlayerScripts > UIController
-- FIX: Habitat bar no longer resets to 0 when a partial UpdateHUD fires
--      (e.g. from BoostManager which only sends goldenAuras/boostInventory).
--      Now only updates habitat bar, rate, and currency when those fields
--      are explicitly present in the payload.
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local AdminConfig       = require(ReplicatedStorage.Modules.AdminConfig)
local Formatter         = require(ReplicatedStorage.Modules.NumberFormatter)
local UITheme = require(game:GetService("ReplicatedStorage").Modules.UITheme)

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local UpdateHUD = ReplicatedStorage.RemoteEvents:WaitForChild("UpdateHUD")
local ShipAuras = ReplicatedStorage.RemoteEvents:WaitForChild("ShipAuras")
local mainHUD   = playerGui:WaitForChild("MainHUD")

local isAutoMode = AdminConfig.AutoDispatch
local HabitatHolder = workspace:WaitForChild("HabitatHolder")
local GoldenAurasLabel = mainHUD:WaitForChild("GoldenAurasLabel")
	
local serverCurrency     = 0
local prevServerCurrency = 0
local displayedCurrency  = 0
local ratePerSecond      = 0
local pendingAuras       = 0
local habitatCapacity    = AdminConfig.BaseHabitatCapacity
local passiveInterval    = AdminConfig.PassiveInterval
local currentCooldownTime = 15
local isShipOnCooldown = false

local lastSpendTick = 0
local liveGoldenAuras = 0

-- ✨ NEW: Listen for instant purchases triggered by the Shop!
player:GetAttributeChangedSignal("LocalSpend"):Connect(function()
	local spend = player:GetAttribute("LocalSpend") or 0
	if spend > 0 then
		displayedCurrency = math.max(0, displayedCurrency - spend)
		lastSpendTick = tick()
		player:SetAttribute("LocalSpend", 0) -- Reset
	end
end)

player:GetAttributeChangedSignal("LocalAuraSpend"):Connect(function()
	local spend = player:GetAttribute("LocalAuraSpend") or 0
	if spend > 0 then
		liveGoldenAuras = math.max(0, liveGoldenAuras - spend)
		player:SetAttribute("LiveGoldenAuras", liveGoldenAuras)
		GoldenAurasLabel.Text = "GAURAS: " .. liveGoldenAuras
		lastSpendTick = tick()
		player:SetAttribute("LocalAuraSpend", 0)
	end
end)

local function FormatNumber(n) return Formatter.Format(n) end
local function FormatRate(perSecond)
	if perSecond <= 0 then return "$0/sec" end
	return "$" .. Formatter.Format(perSecond) .. "/sec"
end
local function GetRateColor(pending, capacity)
	local ratio = math.clamp((pending or 0) / (capacity or 50), 0, 1)
	if ratio >= 1     then return Color3.fromRGB(255, 60,  60)
	elseif ratio >= 0.75 then return Color3.fromRGB(255, 200, 0)
	elseif ratio >= 0.5  then return Color3.fromRGB(80,  255, 80)
	else                      return Color3.fromRGB(80,  180, 80) end
end

local function UpdateHabitatBar(pending, capacity)
	local ratio = math.clamp((pending or 0) / (capacity or 50), 0, 1)
	local color = GetRateColor(pending, capacity)
	local currentModel = HabitatHolder:FindFirstChild("HabitatModel")
	if currentModel then
		local currentGui = currentModel:FindFirstChild("HabitatGui")
		local barBg = currentGui and currentGui:FindFirstChild("BarBackground")
		local barFill = barBg and barBg:FindFirstChild("BarFill")
		if barFill then
			TweenService:Create(barFill, TweenInfo.new(0.3), { Size = UDim2.new(ratio, 0, 1, 0), BackgroundColor3 = color }):Play()
		end
	end
end

local hud        = playerGui:WaitForChild("MainHUD")
local curr       = hud:WaitForChild("CurrencyLabel")
local rate       = hud:WaitForChild("RateLabel")
local sendButton = hud:WaitForChild("SendButton")
local modeToggle = hud:WaitForChild("ModeToggle")

local sharedCooldownEnd = 0
local manualCooldownLoopID = 0

player:GetAttributeChangedSignal("LocalSpend"):Connect(function()
	local spend = player:GetAttribute("LocalSpend") or 0
	if spend > 0 then
		displayedCurrency = math.max(0, displayedCurrency - spend)
		lastSpendTick = tick() -- Activate Rollback Shield!
		player:SetAttribute("LocalSpend", 0)
	end
end)

player:GetAttributeChangedSignal("LocalAuraSpend"):Connect(function()
	local spend = player:GetAttribute("LocalAuraSpend") or 0
	if spend > 0 then
		liveGoldenAuras = math.max(0, (liveGoldenAuras or 0) - spend)
		GoldenAurasLabel.Text = "GAURAS: " .. liveGoldenAuras
		lastSpendTick = tick() -- Activate Rollback Shield!
		player:SetAttribute("LocalAuraSpend", 0)
	end
end)
-----------------------------------------------------------------------------
-- ✨ NEON BLUE MANUAL BUTTON (Dark Transparent Overlay)
-----------------------------------------------------------------------------
local function SyncManualCooldownVisuals()
	if isAutoMode or not sendButton.Visible then return end

	local progressContainer = sendButton:FindFirstChild("CooldownProgress")
	local fillPart = progressContainer and progressContainer:FindFirstChild("Fill")
	local textTarget = sendButton:FindFirstChildOfClass("TextLabel") or sendButton

	local uiStroke = sendButton:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke", sendButton)
	uiStroke.Thickness = 1.5

	if not fillPart then return end

	sendButton.ClipsDescendants = true 
	progressContainer.Size = UDim2.new(1, 0, 1, 0)
	progressContainer.Position = UDim2.new(0, 0, 0, 0)
	progressContainer.AnchorPoint = Vector2.new(0, 0)

	fillPart.BorderSizePixel = 0
	fillPart.AnchorPoint = Vector2.new(0, 1)
	fillPart.Position = UDim2.new(0, 0, 1, 0)
	for _, child in ipairs(fillPart:GetChildren()) do
		if child:IsA("UICorner") or child:IsA("UIAspectRatioConstraint") or child:IsA("UIStroke") then child:Destroy() end
	end

	manualCooldownLoopID = manualCooldownLoopID + 1
	local currentLoop = manualCooldownLoopID
	local timeLeft = sharedCooldownEnd - tick()

	-- ✨ SHADOW FIX 1: The base button is ALWAYS bright neon blue underneath!
	sendButton.BackgroundColor3 = Color3.fromRGB(0, 160, 255)
	uiStroke.Color = Color3.fromRGB(0, 220, 255) 

	-- ✨ SHADOW FIX 2: The Fill is forced to be a black, semi-transparent shadow!
	fillPart.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	fillPart.BackgroundTransparency = 0.55

	if timeLeft > 0 then
		isShipOnCooldown = true
		if textTarget ~= sendButton then sendButton.Text = "" end

		task.spawn(function()
			while timeLeft > 0 and manualCooldownLoopID == currentLoop do
				local percentage = timeLeft / currentCooldownTime

				TweenService:Create(fillPart, TweenInfo.new(0.1, Enum.EasingStyle.Linear), {
					Size = UDim2.new(1, 0, percentage, 0)
				}):Play()

				task.wait(0.1)
				timeLeft = sharedCooldownEnd - tick() 
			end

			if manualCooldownLoopID == currentLoop then
				isShipOnCooldown = false
				textTarget.Text = ""
				fillPart.Size = UDim2.new(1, 0, 0, 0) -- Hides the shadow when ready!
			end
		end)
	else
		isShipOnCooldown = false
		textTarget.Text = ""
		fillPart.Size = UDim2.new(1, 0, 0, 0) -- Hides the shadow when ready!
	end
end

-----------------------------------------------------------------------------
-- ✨ VISIBILITY HANDLER
-----------------------------------------------------------------------------
local function UpdateSendButton()
	if AdminConfig.DisableShipping then sendButton.Visible = false; return end
	sendButton.Visible = not isAutoMode and (pendingAuras or 0) > 0
	if sendButton.Visible then
		SyncManualCooldownVisuals()
	end
end

-----------------------------------------------------------------------------
-- ✨ NEW: AUTO MODE COOLDOWN BAR SETUP (WITH STROKE & COLOR MATCHING)
-----------------------------------------------------------------------------
local autoProgressContainer = Instance.new("Frame")
autoProgressContainer.Name = "AutoProgressContainer"
autoProgressContainer.Size = UDim2.new(0, 12, 1, 0)
autoProgressContainer.Position = UDim2.new(1, 8, 0, 0) 
autoProgressContainer.BackgroundColor3 = Color3.fromRGB(24, 60, 24) 
autoProgressContainer.BorderSizePixel = 0
autoProgressContainer.Visible = false
autoProgressContainer.Parent = modeToggle

Instance.new("UICorner", autoProgressContainer).CornerRadius = UDim.new(0.5, 0)

local autoStroke = Instance.new("UIStroke")
autoStroke.Color = Color3.fromRGB(0, 255, 128) 
autoStroke.Thickness = 1.5
autoStroke.Parent = autoProgressContainer

local autoFillClip = Instance.new("Frame")
autoFillClip.Size = UDim2.new(1, 0, 1, 0)
autoFillClip.BackgroundTransparency = 1
autoFillClip.ClipsDescendants = true
autoFillClip.Parent = autoProgressContainer
Instance.new("UICorner", autoFillClip).CornerRadius = UDim.new(0.5, 0)

local autoFill = Instance.new("Frame")
autoFill.Name = "Fill"
autoFill.Size = UDim2.new(1, 0, 1, 0)
autoFill.Position = UDim2.new(0, 0, 1, 0)
autoFill.AnchorPoint = Vector2.new(0, 1) 
autoFill.BackgroundColor3 = Color3.fromRGB(0, 255, 128) 
autoFill.BorderSizePixel = 0
autoFill.Parent = autoFillClip

local autoLoopID = 0

-----------------------------------------------------------------------------
-- ✨ UPDATED MODE TOGGLE VISUALS (Universal Sync)
-----------------------------------------------------------------------------
local function UpdateModeToggleVisuals()
	local textLabel = modeToggle:FindFirstChildOfClass("TextLabel") or modeToggle
	local uiStroke = modeToggle:FindFirstChildOfClass("UIStroke")

	autoLoopID = autoLoopID + 1 
	local currentLoop = autoLoopID

	if isAutoMode then
		modeToggle.BackgroundColor3 = Color3.fromRGB(24, 60, 24)
		textLabel.Text = "[AUTO ACTIVE]"
		textLabel.TextColor3 = Color3.fromRGB(0, 255, 128)
		if uiStroke then uiStroke.Color = Color3.fromRGB(0, 255, 128) end

		autoProgressContainer.Visible = true

		task.spawn(function()
			while isAutoMode and autoLoopID == currentLoop do
				local timeLeft = sharedCooldownEnd - tick()

				-- If the timer hits 0, it shipped! Start a fresh loop!
				if timeLeft <= 0 then
					sharedCooldownEnd = tick() + currentCooldownTime
					timeLeft = currentCooldownTime

					-- ✨ THE PERFECT SYNC FIX: Let the flawless UI clock trigger the truck!
					-- If there are actually Auras in the base, send the truck instantly!
					if (pendingAuras or 0) > 0 then
						ShipAuras:FireServer("manual")
					end
				end

				local percentage = timeLeft / currentCooldownTime
				autoFill.Size = UDim2.new(1, 0, percentage, 0)

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
		textLabel.Text = "Mode: Manual"
		textLabel.TextColor3 = Color3.fromRGB(220, 230, 240)
		if uiStroke then uiStroke.Color = Color3.fromRGB(100, 180, 220) end

		autoProgressContainer.Visible = false
	end
end

sendButton.MouseButton1Down:Connect(function()
	if AdminConfig.DisableShipping then return end
	if isAutoMode or isShipOnCooldown or (pendingAuras or 0) <= 0 then return end

	ShipAuras:FireServer("manual")

	-- Set the Universal Timer
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

-- INITIAL SETUP
UpdateModeToggleVisuals()
sendButton.Visible = false

if AdminConfig.DisableShipping then
	isAutoMode         = false
	sendButton.Visible = false
	modeToggle.Visible = false
end

UpdateHUD.OnClientEvent:Connect(function(stats)
	-- Shield the UI from laggy server updates for 1.0s after buying an item
	local safeToSync = (tick() - lastSpendTick) > 1.0 

	if stats.goldenAuras ~= nil and safeToSync then
		liveGoldenAuras = stats.goldenAuras
		GoldenAurasLabel.Text = "GAURAS: " .. liveGoldenAuras
	end

	if stats.currency ~= nil then
		local newServerCurrency = stats.currency

		if safeToSync then
			-- Calculate how far out of sync the UI is from the Server
			local drift = math.abs(newServerCurrency - displayedCurrency)

			-- ✨ DRIFT CATCHER: If an Admin command gives you money, or you prestige, SNAP instantly!
			if drift > (ratePerSecond * 3) + 10 then 
				displayedCurrency = newServerCurrency

				-- Flash green if we got rich, red if we went broke
				if newServerCurrency > prevServerCurrency then
					curr.TextColor3 = Color3.fromRGB(80, 255, 80)
				else
					curr.TextColor3 = Color3.fromRGB(255, 80, 80)
				end
				TweenService:Create(curr, TweenInfo.new(0.4), { TextColor3 = Color3.fromRGB(255, 255, 255) }):Play()
			end
		end

		prevServerCurrency = newServerCurrency
		serverCurrency = newServerCurrency
	end

	if stats.pendingAuras ~= nil then
		pendingAuras = stats.pendingAuras
		habitatCapacity = stats.habitatCapacity or habitatCapacity
		UpdateHabitatBar(pendingAuras, habitatCapacity)
		UpdateSendButton()
	end

	if stats.rate ~= nil then
		passiveInterval = stats.passiveInterval or passiveInterval
		local serverRate = stats.rate
		-- Calculate the smooth tick rate for the visual counter
		ratePerSecond = (passiveInterval > 0 and serverRate > 0) and serverRate / passiveInterval or 0
		rate.Text = FormatRate(ratePerSecond)
		TweenService:Create(rate, TweenInfo.new(0.3), { TextColor3 = GetRateColor(pendingAuras, habitatCapacity) }):Play()
	end

	if stats.shipCooldown ~= nil then currentCooldownTime = stats.shipCooldown end
end)

-----------------------------------------------------------------------------
-- ✨ 3. THE VISUAL TICKER
-----------------------------------------------------------------------------
RunService.RenderStepped:Connect(function(dt)
	-- Because the PassiveIncome script officially awards this, we smoothly tick it up visually!
	if ratePerSecond > 0 then
		displayedCurrency += ratePerSecond * dt
	end

	-- Broadcast the flawless math to the Shop!
	player:SetAttribute("LiveCurrency", displayedCurrency) 
	player:SetAttribute("LiveGoldenAuras", liveGoldenAuras)
	curr.Text = "Currency: $" .. FormatNumber(displayedCurrency)
end)

local function RefreshLook()
	UITheme.ApplyFlair(GoldenAurasLabel, "GoldStroke")
end
task.wait(2)
RefreshLook()

-- ShopController
-- Location: StarterPlayer > StarterPlayerScripts > ShopController

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")

local UpgradeConfig     = require(ReplicatedStorage.Modules.UpgradeConfig)
local Formatter         = require(ReplicatedStorage.Modules.NumberFormatter)
local EpicUpgradeConfig = require(ReplicatedStorage.Modules.EpicUpgradeConfig)
local T                 = require(ReplicatedStorage.Modules.UITheme).Get()
local SoundConfig       = require(ReplicatedStorage.Modules.SoundConfig)
local UITheme = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UITheme"))
local T = UITheme.Get("Custom") 
local RemoteEvents      = ReplicatedStorage:WaitForChild("RemoteEvents")
local PurchaseUpgrade     = RemoteEvents:WaitForChild("PurchaseUpgrade", 15)
local UpgradeUpdated      = RemoteEvents:WaitForChild("UpgradeUpdated", 15)
local PurchaseEpicUpgrade = RemoteEvents:WaitForChild("PurchaseEpicUpgrade", 15)
local EpicUpgradeUpdated  = RemoteEvents:WaitForChild("EpicUpgradeUpdated", 15)

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainHUD   = playerGui:WaitForChild("MainHUD")

local upgradeState     = {}
local epicUpgradeState  = {}
local currentCurrency   = 0
local liveGoldenAuras   = 0
local lastSpendTick = 0 -- ✨ Tracks when we last spent money!
local shopOpen          = false
local activeMainTab     = "Upgrades"
local activeEpicSubTab  = "Active"
local regularCardRefs   = {}
local epicCardRefs      = {}
local isLoadingData     = true

---------------------------------------------------------------
-- INITIALIZATION (TIERED)
---------------------------------------------------------------
for _, tierData in ipairs(UpgradeConfig.Tiers) do
	for upgradeId, cfg in pairs(tierData.upgrades) do
		upgradeState[upgradeId] = {
			level = 0, maxLevel = cfg.maxLevel,
			cost = UpgradeConfig.CalculateCost(upgradeId, 0), maxed = false,
		}
	end
end

for _, tierData in ipairs(EpicUpgradeConfig.Tiers) do
	for upgradeId, cfg in pairs(tierData.upgrades) do
		epicUpgradeState[upgradeId] = {
			level = 0, maxLevel = cfg.maxLevel,
			cost = EpicUpgradeConfig.CalculateCost(upgradeId, 0), maxed = false,
		}
	end
end

local function PlayUIBurst(targetElement, amount, colorTheme)
	if not shopOpen then return end
	local burstGui = Instance.new("ScreenGui")
	burstGui.Name = "JuiceBurst"
	burstGui.Parent = playerGui

	local absPos = targetElement.AbsolutePosition
	local absSize = targetElement.AbsoluteSize
	local center = absPos + (absSize / 2)

	for i = 1, amount do
		local particle = Instance.new("Frame")
		particle.BackgroundColor3 = colorTheme or Color3.fromRGB(255, 215, 0) -- Default Gold
		particle.BorderSizePixel = 0
		particle.Size = UDim2.new(0, math.random(6, 12), 0, math.random(6, 12))
		particle.Position = UDim2.new(0, center.X, 0, center.Y)
		particle.Rotation = math.random(0, 360)

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = particle
		particle.Parent = burstGui

		local angle = math.rad(math.random(0, 360))
		local distance = math.random(50, 150)
		local endPos = UDim2.new(0, center.X + math.cos(angle) * distance, 0, center.Y + math.sin(angle) * distance + 50) 

		local tInfo = TweenInfo.new(math.random(4, 7)/10, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out)
		local tween = TweenService:Create(particle, tInfo, {
			Position = endPos,
			Size = UDim2.new(0, 0, 0, 0),
			Rotation = particle.Rotation + math.random(-180, 180),
			BackgroundTransparency = 1
		})
		tween:Play()
	end

	task.delay(1, function() burstGui:Destroy() end)
end

local comboPitch = 1.0
local lastBuyTime = tick()

local function PlayPurchaseSound()
	if tick() - lastBuyTime < 0.3 then
		comboPitch = math.min(comboPitch + 0.05, 2.5) 
	else
		comboPitch = 1.0 
	end
	lastBuyTime = tick()

	local soundsFolder = ReplicatedStorage:FindFirstChild("SFX") or ReplicatedStorage:FindFirstChild("Sounds")
	if soundsFolder and soundsFolder:FindFirstChild("BuyPing") then
		local sfx = soundsFolder.BuyPing:Clone() 
		sfx.PlaybackSpeed = comboPitch
		sfx.Parent = game:GetService("SoundService")
		sfx:Play()
		game.Debris:AddItem(sfx, 2)
	end
end

local function PlayFeedbackSound(soundName, volume)
	local soundsFolder = ReplicatedStorage:FindFirstChild("SFX") or ReplicatedStorage:FindFirstChild("Sounds")
	local soundToPlay = nil

	if soundsFolder then
		soundToPlay = soundsFolder:FindFirstChild(soundName)
	end

	if soundToPlay then
		local sfx = soundToPlay:Clone()
		sfx.Volume = volume or 0.5
		sfx.Parent = game:GetService("SoundService") 
		sfx:Play()
		game.Debris:AddItem(sfx, 3)
	else
		warn("⚠️ UI Sound Missing: You need to add a sound named '" .. tostring(soundName) .. "' inside ReplicatedStorage.SFX!")
	end
end

local lastErrorTime = tick()

local function PlayErrorFeedback(targetButton)
	if tick() - lastErrorTime < 0.25 then return end
	lastErrorTime = tick()

	local soundsFolder = ReplicatedStorage:FindFirstChild("Sounds") or ReplicatedStorage:FindFirstChild("SFX")
	if soundsFolder and soundsFolder:FindFirstChild("ErrorBuzz") then
		local sfx = soundsFolder.ErrorBuzz:Clone()
		sfx.Volume = 0.5 
		sfx.Parent = workspace
		sfx:Play()
		game.Debris:AddItem(sfx, 2)
	end

	if targetButton and targetButton.Parent then
		local origPos = targetButton.Position
		local wobbleInfo = TweenInfo.new(0.04, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 3, true)
		TweenService:Create(targetButton, wobbleInfo, {Position = origPos + UDim2.new(0, 4, 0, 0)}):Play()
	end
end

-----------------------------------------------------------
-- HELPERS
---------------------------------------------------------------
local function FormatNumber(n) return Formatter.Format(n) end
local function PlayUI(id) if shared.PlayUISound then shared.PlayUISound(id) end end

local ShopButton = Instance.new("ImageButton")
ShopButton.Name="ShopButton"; ShopButton.Size=UDim2.new(0,60,0,60)
ShopButton.AnchorPoint = Vector2.new(1, 1) -- ✨ Anchors perfectly to bottom right
ShopButton.Position = UDim2.new(0.98, 0, 0.95, 0) -- ✨ Scaled position
ShopButton.BackgroundColor3=T.buttonSecondary; ShopButton.BorderSizePixel=0
ShopButton.AutoButtonColor = false
ShopButton.ZIndex=5; ShopButton.Parent=mainHUD
ShopButton:SetAttribute("TutorialTarget", "ShopButton")
Instance.new("UICorner",ShopButton).CornerRadius=UDim.new(0.5, 0)

local shopStroke = Instance.new("UIStroke", ShopButton)
shopStroke.Color = T.accentGold; shopStroke.Thickness = 2

local shopIcon = Instance.new("ImageLabel", ShopButton)
shopIcon.Size = UDim2.new(0.6, 0, 0.6, 0); shopIcon.Position = UDim2.new(0.2, 0, 0.2, 0)
shopIcon.BackgroundTransparency = 1; shopIcon.ScaleType = Enum.ScaleType.Fit
shopIcon.Image = "rbxassetid://14916846070" -- 🖼️ PLACEHOLDER: Cart Icon ID


---------------------------------------------------------------
-- SHOP PANEL
---------------------------------------------------------------
local PANEL_MAX_W=420; local PANEL_MAX_H=510; local HEADER_H=42
local MAINTAB_H=34; local SUBTAB_H=30; local CURRENCY_H=0

local ShopPanel=Instance.new("Frame"); ShopPanel.Name="ShopPanel"
ShopPanel.Size=UDim2.new(0.88, 0, 0.82, 0)
ShopPanel.AnchorPoint=Vector2.new(0.5, 0.5)
ShopPanel.Position=UDim2.new(0.5, 0, 0.5, 0)
ShopPanel.BackgroundColor3=T.panelBG; ShopPanel.BorderSizePixel=0
ShopPanel.Visible=false; ShopPanel.ZIndex=10; ShopPanel.ClipsDescendants=true
ShopPanel.Parent=mainHUD
Instance.new("UICorner",ShopPanel).CornerRadius=UDim.new(0,10)
local sizeConstraint=Instance.new("UISizeConstraint"); sizeConstraint.MaxSize=Vector2.new(PANEL_MAX_W, PANEL_MAX_H); sizeConstraint.Parent=ShopPanel
local panelStroke=Instance.new("UIStroke"); panelStroke.Color=T.panelStroke; panelStroke.Thickness=2; panelStroke.Parent=ShopPanel

local TitleBar=Instance.new("Frame"); TitleBar.Name="TitleBar"
TitleBar.Size=UDim2.new(1,0,0,HEADER_H)
TitleBar.BackgroundColor3=T.headerBG; TitleBar.BorderSizePixel=0; TitleBar.ZIndex=11; TitleBar.Parent=ShopPanel
TitleBar.ClipsDescendants=true 
TitleBar.BackgroundTransparency = 1
Instance.new("UICorner",TitleBar).CornerRadius=UDim.new(0,10)
local TitleLabel=Instance.new("TextLabel"); TitleLabel.Size=UDim2.new(1,-50,1,0); TitleLabel.Position=UDim2.new(0,15,0,0)
TitleLabel.BackgroundTransparency=1; TitleLabel.Text="RESEARCH"; TitleLabel.TextColor3=T.headerText
TitleLabel.TextScaled=true; TitleLabel.Font=T.font; TitleLabel.TextXAlignment=Enum.TextXAlignment.Left
TitleLabel.ZIndex=12; TitleLabel.Parent=TitleBar
local CloseButton=Instance.new("TextButton"); CloseButton.Size=UDim2.new(0,30,0,30); CloseButton.Position=UDim2.new(1,-35,0,6)
CloseButton.BackgroundColor3=T.buttonRed; CloseButton.BorderSizePixel=0; CloseButton.Text="X"; CloseButton.TextColor3=T.bodyText
CloseButton.TextScaled=true; CloseButton.Font=T.font; CloseButton.ZIndex=9999; CloseButton.Parent=TitleBar
CloseButton:SetAttribute("TutorialTarget", "ShopCloseBtn")
Instance.new("UICorner",CloseButton).CornerRadius=UDim.new(0,6)

---------------------------------------------------------------
-- INFO POPUP (SCALED & CONSTRAINED SQUARE)
---------------------------------------------------------------
local InfoPopup = Instance.new("Frame")
InfoPopup.Name = "InfoPopup"
InfoPopup.Size = UDim2.new(0.85, 0, 0.6, 0) -- ✨ Now sizes relative to the Shop Panel!
InfoPopup.Position = UDim2.new(0.5, 0, 0.5, 0)
InfoPopup.AnchorPoint = Vector2.new(0.5, 0.5)
InfoPopup.BackgroundColor3 = T.cardBG 
InfoPopup.BackgroundTransparency = 0 
InfoPopup.ZIndex = 50
InfoPopup.Visible = false
InfoPopup.Parent = ShopPanel -- ✨ PARENT CHANGED FROM mainHUD TO ShopPanel
Instance.new("UICorner", InfoPopup).CornerRadius = UDim.new(0, 12)

-- ✨ FORCES IT TO BE A SQUARE REGARDLESS OF SCREEN SIZE
local AspectConstraint = Instance.new("UIAspectRatioConstraint", InfoPopup)
AspectConstraint.AspectRatio = 1.0 -- 1.0 means a perfect 1:1 square!

local InfoScale = Instance.new("UIScale", InfoPopup)
InfoScale.Scale = 1

local InfoTitle = Instance.new("TextLabel", InfoPopup)
InfoTitle.Size = UDim2.new(1, -20, 0, 35)
InfoTitle.Position = UDim2.new(0, 10, 0, 10)
InfoTitle.BackgroundTransparency = 1
InfoTitle.Text = ""
InfoTitle.TextColor3 = T.headerText
InfoTitle.TextScaled = true
InfoTitle.Font = Enum.Font.GothamBold
InfoTitle.ZIndex = 51

local InfoDesc = Instance.new("TextLabel", InfoPopup)
InfoDesc.Size = UDim2.new(1, -20, 1, -110)
InfoDesc.Position = UDim2.new(0, 10, 0, 55)
InfoDesc.BackgroundTransparency = 1
InfoDesc.Text = ""
InfoDesc.TextColor3 = T.bodyText
InfoDesc.TextWrapped = true
InfoDesc.TextScaled = true
InfoDesc.Font = T.font
InfoDesc.TextYAlignment = Enum.TextYAlignment.Top
InfoDesc.ZIndex = 51

local InfoClose = Instance.new("TextButton", InfoPopup)
InfoClose.Size = UDim2.new(0.6, 0, 0, 40) -- Made slightly narrower to fit the square look
InfoClose.Position = UDim2.new(0.2, 0, 1, -50)
InfoClose.BackgroundColor3 = T.buttonPrimary
InfoClose.BorderSizePixel = 0
InfoClose.Text = "Close"
InfoClose.TextColor3 = T.headerText
InfoClose.TextScaled = true
InfoClose.Font = T.font
InfoClose.ZIndex = 51
Instance.new("UICorner", InfoClose).CornerRadius = UDim.new(0, 8)

local function ShowInfo(title, desc)
	if shared.PlayUISound then shared.PlayUISound(SoundConfig.UIClick or "") end
	InfoTitle.Text = title
	InfoDesc.Text = desc
	InfoPopup.BackgroundTransparency = 0 

	InfoScale.Scale = 0.5
	InfoPopup.Visible = true
	game:GetService("TweenService"):Create(InfoScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
end

InfoClose.MouseButton1Down:Connect(function()
	if shared.PlayUISound then shared.PlayUISound(SoundConfig.UIClick or "") end
	local tween = game:GetService("TweenService"):Create(InfoScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In), {Scale = 0.5})
	tween:Play()
	tween.Completed:Once(function()
		InfoPopup.Visible = false
	end)
end)

---------------------------------------------------------------
-- CIRCULAR SHOP TABS
---------------------------------------------------------------
local activeShopTabText = "Regular Upgrades"

local MainTabBar = Instance.new("Frame")
MainTabBar.Size = UDim2.new(1, -20, 0, 85) -- ✨ Made taller (was 75)
MainTabBar.Position = UDim2.new(0, 10, 0, HEADER_H + 4)
MainTabBar.BackgroundTransparency = 1; MainTabBar.ZIndex = 11; MainTabBar.Parent = ShopPanel

-- ✨ MOVED TEXT TO THE TOP OF THE BAR
local ShopHoverLabel = Instance.new("TextLabel", MainTabBar)
ShopHoverLabel.Size = UDim2.new(1, 0, 0, 20)
ShopHoverLabel.Position = UDim2.new(0, 0, 0, 0) -- Locks perfectly to the top
ShopHoverLabel.BackgroundTransparency = 1; ShopHoverLabel.TextColor3 = T.bodyText
ShopHoverLabel.TextScaled = true; ShopHoverLabel.Font = T.font
ShopHoverLabel.Text = activeShopTabText

-- ✨ PUSHED THE BUTTONS DOWN SO THEY DON'T OVERLAP
local TabBtnFrame = Instance.new("Frame", MainTabBar)
TabBtnFrame.Size = UDim2.new(1, 0, 1, -25)
TabBtnFrame.Position = UDim2.new(0, 0, 0, 25) -- Pushed down 25 pixels
TabBtnFrame.BackgroundTransparency = 1

local TabListLayout = Instance.new("UIListLayout", TabBtnFrame)
TabListLayout.FillDirection = Enum.FillDirection.Horizontal
TabListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
TabListLayout.VerticalAlignment = Enum.VerticalAlignment.Center
TabListLayout.Padding = UDim.new(0, 25)

-- (Keep your local mainTabButtons = {} and MakeMainTab function exactly as it is below this!)

local TAB_COLOR_BASE   = T.buttonSecondary
local TAB_COLOR_HOVER  = T.buttonPrimary    -- Color when mouse is over it
local TAB_COLOR_ACTIVE = T.accentGold       -- Color when tab is selected

local mainTabButtons = {}
local function MakeMainTab(name, hoverText, iconId)
	local btn = Instance.new("ImageButton", TabBtnFrame)
	btn.Name = "MainTab_" .. name
	btn.Size = UDim2.new(0, 48, 0, 48)
	btn.BackgroundColor3 = TAB_COLOR_BASE; btn.AutoButtonColor = false
	btn.ZIndex = 12
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0.5, 0)

	local stroke = Instance.new("UIStroke", btn)
	stroke.Color = T.panelStroke; stroke.Thickness = 2

	local icon = Instance.new("ImageLabel", btn)
	icon.Size = UDim2.new(0.6, 0, 0.6, 0); icon.Position = UDim2.new(0.2, 0, 0.2, 0)
	icon.BackgroundTransparency = 1; icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = iconId

	-- ✨ SMART HOVER LOGIC
	btn.MouseEnter:Connect(function() 
		ShopHoverLabel.Text = hoverText 
		if activeMainTab ~= name then btn.BackgroundColor3 = TAB_COLOR_HOVER end
	end)

	btn.MouseLeave:Connect(function() 
		ShopHoverLabel.Text = activeShopTabText 
		if activeMainTab ~= name then btn.BackgroundColor3 = TAB_COLOR_BASE end
	end)

	mainTabButtons[name] = {btn = btn, stroke = stroke}
	return btn
end
local tabEpic     = MakeMainTab("Epic", "Epic Research", "rbxassetid://14916846070")

local tabUpgrades = MakeMainTab("Upgrades", "Regular Upgrades", "rbxassetid://14916846070")

-----------------------------
-- CURRENCY LABEL
---------------------------------------------------------------
local CurrencyLabel=Instance.new("TextLabel"); CurrencyLabel.Name="ShopCurrencyLabel"
CurrencyLabel.Size=UDim2.new(1,-24,0,CURRENCY_H); CurrencyLabel.BackgroundTransparency=1
CurrencyLabel.Text="$0"; CurrencyLabel.TextColor3=T.currencyColor; CurrencyLabel.TextScaled=true
CurrencyLabel.Font=T.font; CurrencyLabel.TextXAlignment=Enum.TextXAlignment.Right
CurrencyLabel.ZIndex=11; CurrencyLabel.Parent=ShopPanel

local function MakeScroll(name,yTop)
	local sf=Instance.new("ScrollingFrame"); sf.Name=name
	sf.Size=UDim2.new(1,-20,1,-(yTop+10)); sf.Position=UDim2.new(0,10,0,yTop)
	sf.BackgroundTransparency=1; sf.BorderSizePixel=0; sf.ScrollBarThickness=4; sf.ScrollBarImageColor3=T.subText
	sf.CanvasSize=UDim2.new(0,0,0,0); sf.ZIndex=11; sf.Visible=false; sf.Parent=ShopPanel

	-- ✨ THIS IS THE MAGIC LINE THAT STOPS SCROLL OVERLAP:
	sf.ClipsDescendants = true 

	local layout=Instance.new("UIListLayout"); layout.Padding=UDim.new(0,8); layout.Parent=sf
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		sf.CanvasSize=UDim2.new(0,0,0,layout.AbsoluteContentSize.Y+10)
	end); return sf
end

-- ✨ Math fixed: Pushed down to clear the 85px tall MainTabBar
local REGULAR_SCROLL_TOP = HEADER_H + 95 
local RegularScroll = MakeScroll("RegularScroll", REGULAR_SCROLL_TOP)
local EPIC_SCROLL_TOP = HEADER_H + 95
local EpicScroll = MakeScroll("EpicScroll", EPIC_SCROLL_TOP)

local activeEpicSubTab = "Epic"
---------------------------------------------------------------
-- CARD BUILDER
---------------------------------------------------------------
local function BuildCard(parent, upgradeId, cfg, isEpic, cardRefsTable)
	local card = Instance.new("Frame")
	card.Name = "Card_"..upgradeId
	card.Size = UDim2.new(1, 0, 0, 100)
	card.BackgroundColor3 = T.cardBG 
	card.BorderSizePixel = 0; card.Parent = parent
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)

	local icon = Instance.new("ImageLabel", card)
	icon.Size = UDim2.new(0, 50, 0, 50); icon.Position = UDim2.new(0, 15, 0.5, -25)
	icon.BackgroundTransparency = 1
	icon.Image = cfg.iconId or "rbxassetid://0" 

	local infoBtn = Instance.new("TextButton", card)
	infoBtn.Size = UDim2.new(0, 22, 0, 22); infoBtn.Position = UDim2.new(0, 75, 0, 12)
	infoBtn.BackgroundColor3 = T.buttonSecondary 
	infoBtn.Text = "i"; infoBtn.TextColor3 = T.bodyText
	infoBtn.Font = Enum.Font.GothamBlack; infoBtn.TextSize = 14
	Instance.new("UICorner", infoBtn).CornerRadius = UDim.new(1, 0)
	infoBtn.MouseButton1Click:Connect(function() ShowInfo(cfg.displayName, cfg.description) end)

	local nameLabel = Instance.new("TextLabel", card)
	nameLabel.Size = UDim2.new(0.74, -120, 0, 24); nameLabel.Position = UDim2.new(0, 102, 0, 11)
	nameLabel.BackgroundTransparency = 1; nameLabel.Text = string.upper(cfg.displayName)
	nameLabel.TextColor3 = T.bodyText 
	nameLabel.TextScaled = true; nameLabel.Font = Enum.Font.FredokaOne
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left

	local descLabel = Instance.new("TextLabel", card)
	descLabel.Size = UDim2.new(0.74, -95, 0, 36); descLabel.Position = UDim2.new(0, 75, 0, 38)
	descLabel.BackgroundTransparency = 1; descLabel.Text = cfg.description
	descLabel.TextColor3 = T.subText 
	descLabel.TextWrapped = true; descLabel.TextSize = 16; descLabel.Font = Enum.Font.GothamMedium
	descLabel.TextXAlignment = Enum.TextXAlignment.Left; descLabel.TextYAlignment = Enum.TextYAlignment.Top

	local levelLabel = Instance.new("TextLabel", card)
	levelLabel.Size = UDim2.new(0.74, -95, 0, 18); levelLabel.Position = UDim2.new(0, 75, 0, 76)
	levelLabel.BackgroundTransparency = 1; levelLabel.Text = "Lv. 0 / "..cfg.maxLevel
	levelLabel.TextColor3 = T.accentGreen
	levelLabel.TextSize = 16; levelLabel.Font = Enum.Font.FredokaOne; levelLabel.TextXAlignment = Enum.TextXAlignment.Left

	local buyButton = Instance.new("TextButton", card)
	buyButton.Name = "PurchaseButton" -- ✨ ADDED NAME so particle script can find it
	buyButton.Size = UDim2.new(0.24, 0, 0, 46); buyButton.AnchorPoint = Vector2.new(1, 0.5)
	buyButton.Position = UDim2.new(1, -12, 0.5, 0)
	buyButton.BackgroundColor3 = isEpic and T.accentPurple or T.buttonGreen
	buyButton.BorderSizePixel = 0; buyButton.TextColor3 = T.bodyText
	buyButton.TextScaled = true; buyButton.Font = Enum.Font.FredokaOne
	Instance.new("UICorner", buyButton).CornerRadius = UDim.new(0, 8)

	cardRefsTable[upgradeId] = {
		frame = card, levelLabel = levelLabel, buyButton = buyButton, isEpic = isEpic, tab = cfg.category
	}

	local holdingBuy = false; local buyGeneration = 0

	-- ✨ THE MEMORY FIX: Checks if you have ever passed the tutorial
	local tutorialLockLifted = false
	local function IsTutorialFinished()
		if tutorialLockLifted then return true end -- If we already lifted it, keep it lifted forever!
		if liveGoldenAuras > 0 then tutorialLockLifted = true; return true end -- You prestiged!
		for _, state in pairs(epicUpgradeState) do
			if state.level > 0 then tutorialLockLifted = true; return true end -- You have epic upgrades!
		end
		local valState = upgradeState["blockValue"]
		if valState and valState.level > 0 then tutorialLockLifted = true; return true end -- You bought the tutorial upgrade!
		return false
	end


	local function TryBuy()
		if isEpic then
			local state = epicUpgradeState[upgradeId]
			if not state or state.maxed then return false end 

			if not IsTutorialFinished() then PlayErrorFeedback(buyButton); return false end
			local currentAuras = player:GetAttribute("LiveGoldenAuras") or 0
			if currentAuras < state.cost then PlayErrorFeedback(buyButton); return false end

			local wasMaxedLocally = state.maxed
			player:SetAttribute("LocalAuraSpend", state.cost) -- ✨ Tell UIController to deduct!

			state.level += 1
			state.maxed = (state.level >= state.maxLevel)
			state.cost = state.maxed and 0 or EpicUpgradeConfig.CalculateCost(upgradeId, state.level)

			if state.maxed and not wasMaxedLocally then PlayFeedbackSound("MaxOut", 0.6); PlayUIBurst(buyButton, 20) else PlayPurchaseSound() end
			UpdateEpicCard(upgradeId); UpdateCurrencyDisplay(); PurchaseEpicUpgrade:FireServer(upgradeId)
			return true 
		else
			local state = upgradeState[upgradeId]
			if not state or state.maxed then return false end 

			if not IsTutorialFinished() and upgradeId ~= "blockValue" then PlayErrorFeedback(buyButton); return false end
			local currentCash = player:GetAttribute("LiveCurrency") or 0
			if currentCash < state.cost then PlayErrorFeedback(buyButton); return false end

			local wasMaxedLocally = state.maxed
			player:SetAttribute("LocalSpend", state.cost) -- ✨ Tell UIController to deduct!

			state.level += 1
			state.maxed = (state.level >= state.maxLevel)
			state.cost = state.maxed and 0 or UpgradeConfig.CalculateCost(upgradeId, state.level)

			if state.maxed and not wasMaxedLocally then PlayFeedbackSound("MaxOut", 0.6); PlayUIBurst(buyButton, 20) else PlayPurchaseSound() end
			UpdateRegularCard(upgradeId); UpdateCurrencyDisplay(); PurchaseUpgrade:FireServer(upgradeId)
			return true 
		end
	end

	local pulseTween = nil

	buyButton.MouseButton1Down:Connect(function()
		buyGeneration += 1
		local myGen = buyGeneration
		holdingBuy = true

		local scale = buyButton:FindFirstChildOfClass("UIScale")
		if not scale then 
			scale = Instance.new("UIScale")
			scale.Parent = buyButton 
		end

		pulseTween = TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {Scale = 0.88})
		pulseTween:Play()

		TryBuy() 
		task.wait(0.3) 
		local holdStart = tick()

		local UserInputService = game:GetService("UserInputService")
		
		
		local epicHoldSpeedLevel = (epicUpgradeState["epicHoldSpeed"] and epicUpgradeState["epicHoldSpeed"].level) or 0
		local holdSpeedMultiplier = 1 + (epicHoldSpeedLevel * 0.3) -- +30% speed per level

		while holdingBuy and buyGeneration == myGen do
			if not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
				holdingBuy = false
				break
			end

			local success = TryBuy()
			if not success then
				holdingBuy = false
				break
			end

			task.wait(math.max(0.02, (0.15 - ((tick() - holdStart) * 0.05)) / holdSpeedMultiplier))
		end

		if pulseTween then pulseTween:Cancel() end
		if scale then TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), {Scale = 1}):Play() end
	end)

	buyButton.MouseButton1Up:Connect(function() 
		holdingBuy = false 
		if pulseTween then pulseTween:Cancel() end
		local scale = buyButton:FindFirstChildOfClass("UIScale")
		if scale then TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), {Scale = 1}):Play() end
	end)

	buyButton.MouseLeave:Connect(function() 
		holdingBuy = false 
		if pulseTween then pulseTween:Cancel() end
		local scale = buyButton:FindFirstChildOfClass("UIScale")
		if scale then TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), {Scale = 1}):Play() end
	end)
end

---------------------------------------------------------------
-- BUILD CARDS & DYNAMIC REBUILDER
---------------------------------------------------------------
local epicOrderIndex = 1
for _, tab in ipairs(EpicUpgradeConfig.Tabs) do
	for _, tierData in ipairs(EpicUpgradeConfig.Tiers) do
		for upgradeId, cfg in pairs(tierData.upgrades) do
			BuildCard(EpicScroll, upgradeId, cfg, true, epicCardRefs) 

			local ref = epicCardRefs[upgradeId]
			if ref and ref.frame then
				ref.baseOrder = epicOrderIndex
				ref.frame.LayoutOrder = epicOrderIndex
				epicOrderIndex += 1

				ref.frame.Visible = false 
				ref.frame.Parent = EpicScroll

				if UITheme and UITheme.Apply then UITheme.Apply(ref.frame, "ShopCard") end
			end
		end
	end
end

function UpdateRegularCard(upgradeId)
	local ref=regularCardRefs[upgradeId]; local state=upgradeState[upgradeId]
	if not ref or not state then return end
	if UITheme and UITheme.Apply then UITheme.Apply(ref.frame, "ShopCard") end

	ref.levelLabel.Text="Lv. "..state.level.." / "..state.maxLevel
	local currentCash = player:GetAttribute("LiveCurrency") or 0

	if state.level >= state.maxLevel then
		ref.frame.LayoutOrder = (ref.baseOrder or 0) + 100000 
		ref.levelLabel.TextColor3=Color3.fromRGB(255, 215, 0) 
		ref.buyButton.Text="MAX"
		ref.buyButton.TextColor3=Color3.fromRGB(255, 255, 255) 
		ref.buyButton.BackgroundColor3=Color3.fromRGB(100, 100, 100)
	else
		ref.frame.LayoutOrder = ref.baseOrder or 0 
		ref.buyButton.Text="$"..FormatNumber(state.cost)
		if currentCash < state.cost then
			ref.buyButton.TextColor3=Color3.fromRGB(255, 100, 100) 
			ref.buyButton.BackgroundColor3=Color3.fromRGB(60, 170, 80) 
		else
			ref.buyButton.TextColor3=Color3.fromRGB(255, 255, 255) 
			ref.buyButton.BackgroundColor3=Color3.fromRGB(60, 170, 80) 
		end
	end
end

function UpdateEpicCard(upgradeId)
	local ref=epicCardRefs[upgradeId]; local state=epicUpgradeState[upgradeId]
	if not ref or not state then return end
	if UITheme and UITheme.Apply then UITheme.Apply(ref.frame, "ShopCard") end

	ref.levelLabel.Text="Lv. "..state.level.." / "..state.maxLevel
	local currentAuras = player:GetAttribute("LiveGoldenAuras") or 0

	if state.level >= state.maxLevel then
		ref.frame.LayoutOrder = (ref.baseOrder or 0) + 100000 
		ref.levelLabel.TextColor3=Color3.fromRGB(255, 215, 0)
		ref.buyButton.Text="MAX"
		ref.buyButton.TextColor3=Color3.fromRGB(255, 255, 255)
		ref.buyButton.BackgroundColor3=Color3.fromRGB(100, 100, 100)
	else
		ref.frame.LayoutOrder = ref.baseOrder or 0 
		ref.buyButton.Text="✦ "..FormatNumber(state.cost)
		if currentAuras < state.cost then
			ref.buyButton.TextColor3=Color3.fromRGB(255, 100, 100) 
			ref.buyButton.BackgroundColor3=Color3.fromRGB(150, 80, 255) 
		else
			ref.buyButton.TextColor3=Color3.fromRGB(255, 255, 255) 
			ref.buyButton.BackgroundColor3=Color3.fromRGB(150, 80, 255) 
		end
	end
end

function UpdateCurrencyDisplay()
	if activeMainTab=="Upgrades" then
		local currentCash = player:GetAttribute("LiveCurrency") or 0
		CurrencyLabel.Text="$"..FormatNumber(currentCash)
		CurrencyLabel.TextColor3=T.currencyColor
		CurrencyLabel.Position=UDim2.new(0,12,0,HEADER_H+MAINTAB_H+8)
	end
end

local function UpdateAllRegularCards() for id in pairs(regularCardRefs) do UpdateRegularCard(id) end end
local function UpdateAllEpicCards() for id in pairs(epicCardRefs) do UpdateEpicCard(id) end end

local function CreateTierHeader(tierName)
	local header = Instance.new("Frame")
	header.Name = "TierHeader"; header.Size = UDim2.new(1, 0, 0, 30); header.BackgroundTransparency = 1

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, -5); label.Position = UDim2.new(0, 0, 0, 0); label.BackgroundTransparency = 1
	label.Text = string.upper(tierName); label.TextColor3 = Color3.fromRGB(220, 220, 220)
	label.TextSize = 16; label.Font = Enum.Font.GothamBlack; 
	label.TextXAlignment = Enum.TextXAlignment.Left 
	label.Parent = header

	local line = Instance.new("Frame")
	line.Size = UDim2.new(1, 0, 0, 2); line.Position = UDim2.new(0, 0, 1, -2) 
	line.BackgroundColor3 = Color3.fromRGB(100, 100, 100); line.BorderSizePixel = 0; line.Parent = header
	return header
end

local function CreateLockedTierHeader(tierName, current, required)
	local header = Instance.new("Frame")
	header.Name = "TierHeader_Locked"; header.Size = UDim2.new(1, 0, 0, 45); header.BackgroundTransparency = 1
	header:SetAttribute("Required", required) 

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0.5, 0); label.Position = UDim2.new(0, 0, 0, 0); label.BackgroundTransparency = 1
	label.Text = string.upper(tierName) .. " (LOCKED)"; label.TextColor3 = Color3.fromRGB(150, 150, 150)
	label.TextSize = 16; label.Font = Enum.Font.GothamBlack; 
	label.TextXAlignment = Enum.TextXAlignment.Left; label.Parent = header

	local progress = Instance.new("TextLabel")
	progress.Name = "ProgressLabel" 
	progress.Size = UDim2.new(1, 0, 0.4, 0); progress.Position = UDim2.new(0, 0, 0.6, 0); progress.BackgroundTransparency = 1
	progress.Text = current .. " / " .. required .. " Upgrades Needed"
	progress.TextColor3 = Color3.fromRGB(255, 100, 100) 
	progress.TextSize = 12; progress.Font = Enum.Font.GothamBold; 
	progress.TextXAlignment = Enum.TextXAlignment.Left; progress.Parent = header

	local line = Instance.new("Frame")
	line.Size = UDim2.new(1, 0, 0, 2); line.Position = UDim2.new(0, 0, 1, -2)
	line.BackgroundColor3 = Color3.fromRGB(80, 80, 80); line.BorderSizePixel = 0; line.Parent = header
	return header
end

local function RebuildRegularShop()
	for _, child in ipairs(RegularScroll:GetChildren()) do
		if child:IsA("Frame") and child.Name ~= "CardTemplate" then
			if not string.find(child.Name, "TierHeader") then UITheme.Apply(child, "ShopCard") end
			child:Destroy() 
		end
	end
	regularCardRefs = {}

	local totalUpgradesBought = 0
	for _, state in pairs(upgradeState) do totalUpgradesBought = totalUpgradesBought + (state.level or 0) end

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
					-- ✨ THE FIX: Just these 3 lines! (Deleted the old local buyBtn line)
					if ref.buyButton then
						ref.buyButton.Name = "Buy_" .. upgradeId
					end
					-- ✨ ==========================================

					ref.baseOrder = listOrder
					ref.frame.LayoutOrder = listOrder
					listOrder += 1

					ref.frame.Visible = true
					ref.frame.Parent = RegularScroll

					if UITheme and UITheme.Apply then UITheme.Apply(ref.frame, "ShopCard") end
					local myColor = Color3.fromRGB(45, 30, 55)
					ref.frame:SetAttribute("TierColor", myColor)
					ref.frame.BackgroundColor3 = myColor
				end
			end
		else
			local lockedHeader = CreateLockedTierHeader(tierData.tierName or "Tier " .. tierNum, totalUpgradesBought, tierData.unlockRequirement)
			lockedHeader.LayoutOrder = listOrder
			lockedHeader.Parent = RegularScroll
			break 
		end
	end
	UpdateAllRegularCards()
end 
RebuildRegularShop() 

task.delay(1, function()
	isLoadingData = false
end)



---------------------------------------------------------------
-- TAB SWITCHING
---------------------------------------------------------------
local function HighlightMainTab(tabName)
	for name,btn in pairs(mainTabButtons) do btn.BackgroundColor3=(name==tabName) and T.panelStroke or T.buttonSecondary end
end
local function SwitchToMainTab(tabName)
	if shared.PlayUISound then shared.PlayUISound(SoundConfig.UIClick or "") end
	activeMainTab = tabName
	
	activeShopTabText = (tabName == "Epic") and "Epic Research" or "Regular Upgrades"
	ShopHoverLabel.Text = activeShopTabText

	for name, data in pairs(mainTabButtons) do
		data.btn.BackgroundColor3 = (name == tabName) and TAB_COLOR_ACTIVE or TAB_COLOR_BASE
		data.stroke.Color = (name == tabName) and T.bodyText or T.panelStroke
	end

	RegularScroll.Visible = (tabName == "Upgrades")
	EpicScroll.Visible    = (tabName == "Epic")

	-- ✨ Instantly show ALL epic cards when switching to the Epic tab
	if tabName == "Epic" then
		for id, ref in pairs(epicCardRefs) do
			if ref and ref.frame then
				ref.frame.Visible = true 
			end
		end
		if EpicScroll then EpicScroll.CanvasPosition = Vector2.new(0,0) end
	end
end

tabUpgrades.MouseButton1Down:Connect(function() PlayUI(SoundConfig.UIClick); SwitchToMainTab("Upgrades") end)
tabEpic.MouseButton1Down:Connect(function() PlayUI(SoundConfig.UIClick); SwitchToMainTab("Epic") end)

---------------------------------------------------------------
-- OPEN / CLOSE
---------------------------------------------------------------
local function OpenShop()
	shopOpen=true; ShopPanel.Visible=true; ShopPanel.Size=UDim2.new(0.88, 0, 0, 0)
	SwitchToMainTab(activeMainTab)
	TweenService:Create(ShopPanel,TweenInfo.new(0.3,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
		{Size=UDim2.new(0.88, 0, 0.82, 0)}):Play()
	UITheme.SetMenuVisible(true)
	ShopButton.BackgroundColor3=T.panelStroke
end
local function CloseShop()
	shopOpen=false; PlayUI(SoundConfig.UIClose)
	TweenService:Create(ShopPanel,TweenInfo.new(0.22,Enum.EasingStyle.Quad,Enum.EasingDirection.In),
		{Size=UDim2.new(0.88, 0, 0, 0)}):Play()
	UITheme.SetMenuVisible(false)
	task.delay(0.25, function() ShopPanel.Visible=false end)
	ShopButton.BackgroundColor3=T.buttonSecondary
end
ShopButton.MouseButton1Down:Connect(function() if shopOpen then CloseShop() else OpenShop() end end)
CloseButton.MouseButton1Down:Connect(CloseShop)



---------------------------------------------------------------
-- LIVE UPDATE LOOP
---------------------------------------------------------------
local lastCardUpdate=0
RunService.Heartbeat:Connect(function(dt)
	-- No more messy math here! Just visual updates!
	if not shopOpen then return end

	local now=tick()
	-- ✨ Faster updates! Buttons now snap red/green almost instantly
	if now-lastCardUpdate > 0.1 then 
		lastCardUpdate=now
		if activeMainTab=="Upgrades" then UpdateAllRegularCards() else UpdateAllEpicCards() end
		UpdateCurrencyDisplay()
	end
end)
---------------------------------------------------------------
-- SERVER EVENTS (Cleaned of Sound/UI logic)
---------------------------------------------------------------
if UpgradeUpdated then
	UpgradeUpdated.OnClientEvent:Connect(function(info)
		if info.type=="fullState" then
			upgradeState=info.upgrades; currentCurrency=info.currency; 
			RebuildRegularShop()
			UpdateCurrencyDisplay()

		elseif info.type=="purchased" then
			local current = upgradeState[info.upgradeId]

			if not current or info.level >= current.level then
				upgradeState[info.upgradeId]={level=info.level,maxLevel=info.maxLevel,cost=info.cost,maxed=info.maxed}
			end
			currentCurrency = info.currency

			local scroll = ShopPanel:FindFirstChild("RegularScroll")
			local savedScroll = scroll and scroll.CanvasPosition or Vector2.new(0, 0)

			-- ✨ Safely updates the shop tiers WITHOUT triggering ghost sounds!
			RebuildRegularShop()
			UpdateCurrencyDisplay()

			if scroll then
				scroll.CanvasPosition = savedScroll
			end
		end
	end)
end

if EpicUpgradeUpdated then
	EpicUpgradeUpdated.OnClientEvent:Connect(function(info)
		if info.type=="fullState" then
			epicUpgradeState=info.upgrades; liveGoldenAuras=info.goldenAuras or liveGoldenAuras
			UpdateAllEpicCards(); UpdateCurrencyDisplay()

		elseif info.type=="purchased" then
			local current = epicUpgradeState[info.upgradeId]

			if not current or info.level >= current.level then
				epicUpgradeState[info.upgradeId]={level=info.level,maxLevel=info.maxLevel,cost=info.cost,maxed=info.maxed}
			end
			UpdateEpicCard(info.upgradeId); UpdateCurrencyDisplay()
		end
	end)
end

---------------------------------------------------------------
-- UI JUICE: Button Hover & Click Animations
---------------------------------------------------------------
local function AddButtonJuice(btn)
	local scale = btn:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = btn
	end

	btn.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Sine), {Scale = 1.08}):Play()
	end)

	btn.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Sine), {Scale = 1}):Play()
	end)

	btn.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1, Enum.EasingStyle.Sine), {Scale = 0.9}):Play()
	end)

	btn.MouseButton1Up:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), {Scale = 1.08}):Play()
	end)
end

AddButtonJuice(ShopButton)
AddButtonJuice(CloseButton)
AddButtonJuice(ShopButton)
AddButtonJuice(tabUpgrades)
AddButtonJuice(tabEpic)
AddButtonJuice(CloseButton)
---------------------------------------------------------------
-- REFRESH LOOK + APPLY SHINE TO TITLE BAR
---------------------------------------------------------------
local shopShine = nil
local titleFlair = nil
local TitleShine = nil
local flairedExtraUI = false

local function RefreshLook()
	UITheme.Apply(ShopPanel, "Panel")
	UITheme.Apply(ShopPanel, "TitleBar")

	if not shopShine then
		shopShine = UITheme.ApplyShine(ShopPanel)
		TitleShine = UITheme.ApplyShine(TitleBar)
	end

	if not titleFlair then
		titleFlair = UITheme.ApplyFlair(TitleLabel, "Ghost")
	end

	-- ✨ THE FLAIR INJECTOR FOR ALL CIRCLES AND LINES
	if not flairedExtraUI then
		flairedExtraUI = true
		-- Flair all the new circular tabs!
	end

	for _, scrollName in ipairs({"RegularScroll", "EpicScroll"}) do
		local scroll = ShopPanel:FindFirstChild(scrollName) 
		if scroll then
			local layout = scroll:FindFirstChildOfClass("UIListLayout")
			if layout then layout.SortOrder = Enum.SortOrder.LayoutOrder end
		end
	end

	local outerStroke = ShopPanel:FindFirstChildWhichIsA("UIStroke")
	if outerStroke then
		outerStroke.Color = Color3.fromRGB(255, 255, 255) 
	end
end

task.wait(2)
RefreshLook()

-- AuraSpawner
-- Location: ServerScriptService > AuraSpawner
-- FIX: areaMult now reads from AreaRegistry.GetMultiplier() — the authoritative source.
--      AdminConfig.AreaValueMultipliers is no longer used here.
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

local AuraSpawned    = ReplicatedStorage.RemoteEvents:WaitForChild("AuraSpawned")
local ProduceAura    = ReplicatedStorage.RemoteEvents:WaitForChild("ProduceAura")
local UpdateHatchery = ReplicatedStorage.RemoteEvents:WaitForChild("UpdateHatchery")
local UpdateHUD      = ReplicatedStorage.RemoteEvents:WaitForChild("UpdateHUD")
local HabitatFull    = ReplicatedStorage.RemoteEvents:WaitForChild("HabitatFull")
local CubeMutated    = ReplicatedStorage.RemoteEvents:WaitForChild("CubeMutated")

local HABITAT_HOLDER = workspace:WaitForChild("HabitatHolder")
local HABITAT_PART = HABITAT_HOLDER:WaitForChild("Position")
local lastFire          = {}
local holdStart         = {}
local hatchery          = {}
local clickSessionStart = {}
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
	clickSessionStart[p.UserId] = nil
end)
Players.PlayerRemoving:Connect(function(p)
	hatchery[p.UserId]=nil; holdStart[p.UserId]=nil
	lastFire[p.UserId]=nil; clickSessionStart[p.UserId]=nil
end)

task.spawn(function()
	local PR = ServerScriptService:WaitForChild("PrestigeReset", 30)
	if PR then
		PR.Event:Connect(function(player)
			local uid = player.UserId
			local data = GameManager.GetData(uid)
			hatchery[uid] = data and GetHatcheryMax(data) or AdminConfig.HatcheryMax
			holdStart[uid]=nil; lastFire[uid]=nil; clickSessionStart[uid]=nil
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
				UpdateHatchery:FireClient(player, { current=hatchery[uid], max=hatchMax })
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

local function SendHUDUpdate(player)
	local uid = player.UserId
	local data = GameManager.GetData(uid)
	local runtime = GameManager.GetRuntime(uid)
	if not data or not runtime then return end
	local totalMV = runtime.totalMutatedValue or 0
	local pending = runtime.cubeCount
	local avgVal  = pending > 0 and (totalMV/pending) or AdminConfig.BaseAuraValue
	local rate    = math.floor(pending * avgVal)
	local passTickCfg = UpgradeConfig.GetUpgradeConfig("passiveTickSpeed")
	
	local passInt = (passTickCfg and passTickCfg.apply) and passTickCfg.apply(data) or AdminConfig.PassiveInterval
	local displayRate = math.floor(rate * BoostManager.GetValueMultiplier(uid) * BoostManager.GetSpawnRateMultiplier(uid))
	UpdateHUD:FireClient(player, {
		currency=data.currency, pendingAuras=pending,
		habitatCapacity=GetHabitatCapacity(data), rate=displayRate,
		passiveInterval=passInt, totalEarned=data.totalEarned or 0,
		soulAuras=data.soulAuras or 0, farmEvaluation=data.farmEvaluation or 0,
		goldenAuras=data.goldenAuras or 0, boostInventory=data.boostInventory or {},
		prestigeCount=data.prestigeCount or 0,
		upgrades=data.upgrades or {},
		totalCubesProduced = data.totalCubesProduced or 0,
		currentArea        = data.currentArea or 1,
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

			-- 1. Initialize our batch for this specific tick
			local mutationBatch = {}

			for cubeId, cube in pairs(runtime.cubes) do
				-- 2. Store the value before any mutations happen
				local oldMutatedValue = MutationConfig.GetMutatedValue(cube)
				local mutated = false

				local prev = cube.effectiveElapsed
				cube.effectiveElapsed += dt
				local pl = MutationConfig.GetValueBonusLevel(prev)
				local nl = MutationConfig.GetValueBonusLevel(cube.effectiveElapsed)

				if nl > pl then
					mutated = true
					local be = MutationConfig.ValueBonuses[nl]
					-- Add to batch instead of firing immediately
					table.insert(mutationBatch, { 
						cubeId = cubeId, 
						mutationType = "valueBonus",
						bonusLevel = nl, 
						bonusPercent = be and math.floor(be.bonus * 100) or 0 
					})
				end

				local maxTier = AdminConfig.MutationMaxTierIndex or 3
				local upgrades = 0

				while cube.tierIndex < maxTier and cube.tierIndex < #TierConfig.Tiers and upgrades < 5 do
					local timeSince = cube.effectiveElapsed - (cube.lastUpgradeElapsed or 0)
					local bestChance, bestTime = 0, 0

					for _, threshold in ipairs(MutationConfig.TierUpgrades) do
						if timeSince >= threshold.time then 
							bestChance = threshold.chance
							bestTime = threshold.time 
						end
					end

					if bestChance <= 0 then break end

					if math.random() <= bestChance then
						local oldTier = TierConfig.Tiers[cube.tierIndex]
						cube.tierIndex += 1
						local newTier = TierConfig.Tiers[cube.tierIndex]

						cube.baseValue = math.floor(cube.baseValue * (newTier.multiplier/oldTier.multiplier))
						cube.color = newTier.color
						cube.glow = newTier.glow
						cube.tierName = newTier.name
						cube.lastUpgradeElapsed = (cube.lastUpgradeElapsed or 0) + bestTime
						upgrades += 1
						mutated = true

						-- Add to batch instead of firing immediately
						table.insert(mutationBatch, { 
							cubeId = cubeId, 
							mutationType = "tierUpgrade",
							newColor = newTier.color, 
							newGlow = newTier.glow, 
							tierName = newTier.name 
						})

						if newTier.name == "Legendary" then
							data.totalLegendaryCubes = (data.totalLegendaryCubes or 0) + 1
						end
					else 
						break 
					end
				end

				-- 3. Calculate the delta and apply it to the running total
				if mutated then
					local newMutatedValue = MutationConfig.GetMutatedValue(cube)
					runtime.totalMutatedValue = (runtime.totalMutatedValue or 0) + (newMutatedValue - oldMutatedValue)
				end
			end

			-- 4. Send the entire batch in ONE RemoteEvent
			if #mutationBatch > 0 then
				ReplicatedStorage.RemoteEvents.CubeMutatedBatch:FireClient(player, mutationBatch)
			end

			SendHUDUpdate(player)
		end
	end
end)

local function GetHoldMultiplier(holdTime, data)
	local upgrades = data and data.upgrades or {}

	-- Extract speed level
	local speedData = upgrades["multiplierSpeed"]
	local speedLevel = (typeof(speedData) == "table" and speedData.level) or (typeof(speedData) == "number" and speedData) or 0
	local playerMultSpeed = 1.0 + (speedLevel * 0.05)

	-- Extract Mythic Unlock (Tier 6)
	local playerMaxTier = 5
	local mythicData = upgrades["unlockMythicMult"]
	local mythicLevel = (typeof(mythicData) == "table" and mythicData.level) or (typeof(mythicData) == "number" and mythicData) or 0
	if mythicLevel > 0 then playerMaxTier = 6 end

	local effectiveTime = holdTime * playerMultSpeed
	local currentTier = 1

	for i = 1, playerMaxTier do
		if AdminConfig.MilestoneData[i] and effectiveTime >= AdminConfig.MilestoneData[i].time then
			currentTier = i
		end
	end

	-- Smooth Math to perfectly match the client
	local nextTier = math.min(currentTier + 1, playerMaxTier)
	if currentTier == playerMaxTier then
		return AdminConfig.MilestoneData[currentTier].mult, AdminConfig.MilestoneData[currentTier].luck
	end

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
		table.insert(adjusted, { tier=tier, chance=chance }); total += chance
	end
	local r, cum = math.random()*total, 0
	for _, e in ipairs(adjusted) do
		cum += e.chance; if r <= cum then return e.tier end
	end
	return tiers[1]
end

local function SpawnAura(player, data, runtime, holdMult, luckBonus)
	local uid  = player.UserId
	local tier = RollWithLuck(luckBonus)
	local tierIndex = 1
	for i, t in ipairs(TierConfig.Tiers) do if t.name == tier.name then tierIndex=i; break end end

	-- ✨ THE ADDITIVE MATH FIX: Gather ALL Value Upgrades!
	local totalValueMultiplier = 1.0 -- Starts at 100% base value
	local valueUpgrades = {
		"blockValue", "blockValueT2", "auraValueT3", 
		"auraValueT4", "auraValueT6", "auraValueT8", "auraValueT10"
	}

	for _, upgradeId in ipairs(valueUpgrades) do
		local cfg = UpgradeConfig.GetUpgradeConfig(upgradeId)
		if cfg and cfg.apply then
			totalValueMultiplier += cfg.apply(data) -- Additively stack the percentages!
		end
	end

	local prestigeMult    = PrestigeModule.GetMultiplier(data.soulAuras)
	local areaMult        = AreaRegistry.GetMultiplier(data.currentArea or 1)
	local boostValueMult  = BoostManager.GetValueMultiplier(uid)
	local _, weatherValueMult = WeatherManager.GetMultipliers(uid)

	-- Apply the strictly additive totalValueMultiplier
	local baseValue  = math.floor(AdminConfig.BaseAuraValue * tier.multiplier * totalValueMultiplier * prestigeMult * areaMult * boostValueMult * weatherValueMult)
	local totalValue = baseValue + math.floor(baseValue * (holdMult - 1))

	local spawnPos = HABITAT_PART.Position + Vector3.new(math.random(-3,3), 10, math.random(-3,3))	
	local cubeRecord = {
		spawnTime=tick(), effectiveElapsed=0, lastUpgradeElapsed=0,
		baseValue=totalValue, tierIndex=tierIndex,
		tierName=tier.name, color=tier.color, glow=tier.glow,
	}
	if AdminConfig.MutationInstantMax then
		local mb = MutationConfig.ValueBonuses[#MutationConfig.ValueBonuses]
		if mb then cubeRecord.effectiveElapsed = mb.time + 1 end
	end

	local cubeId = GameManager.AddCube(uid, cubeRecord)
	if not cubeId then return end
	data.totalCubesProduced = (data.totalCubesProduced or 0) + 1
	if tier.name == "Legendary" then data.totalLegendaryCubes = (data.totalLegendaryCubes or 0) + 1 end
	runtime.lastActiveTime = tick()

	AuraSpawned:FireClient(player, {
		cubeId=cubeId, tier=tier.name, color=tier.color,
		glow=tier.glow, value=totalValue, spawnPos=spawnPos,
	})
end

ProduceAura.OnServerEvent:Connect(function(player, action)
	local uid = player.UserId
	local now = tick()
	if action == "start" then if (hatchery[uid] or 0) > 0 then holdStart[uid]=now end; return end
	if action == "stop"  then holdStart[uid]=nil; return end
	if (hatchery[uid] or 0) <= 0 then return end
	if not holdStart[uid] then return end

	local rushMult = BoostManager.GetSpawnRateMultiplier(uid)
	local weatherSpawnMult, _ = WeatherManager.GetMultipliers(uid)

		-- ClickHandler
-- Location: StarterPlayer > StarterPlayerScripts > ClickHandler
-- CHANGES: Added local FormatNumber (K/M/B/T/Q)
--          ShowCubeValue: label.Text now uses FormatNumber instead of tostring
--          Everything else identical to your uploaded script.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")
local AdminConfig = require(ReplicatedStorage.Modules.AdminConfig)
local UITheme = require(game:GetService("ReplicatedStorage").Modules.UITheme)

local ProduceAura = ReplicatedStorage.RemoteEvents:WaitForChild("ProduceAura")
local AuraSpawned = ReplicatedStorage.RemoteEvents:WaitForChild("AuraSpawned")
local UpdateHatchery = ReplicatedStorage.RemoteEvents:WaitForChild("UpdateHatchery")
local ForceStopHold = ReplicatedStorage.RemoteEvents:WaitForChild("ForceStopHold")
local HabitatFull = ReplicatedStorage.RemoteEvents:WaitForChild("HabitatFull")
local CubeMutated = ReplicatedStorage.RemoteEvents:WaitForChild("CubeMutated")
local UpdateMultiplier = ReplicatedStorage:WaitForChild("UpdateMultiplier")
local HabitatFullEvent = ReplicatedStorage:WaitForChild("HabitatFullEvent")
local CubeMutatedBatch = ReplicatedStorage.RemoteEvents:WaitForChild("CubeMutatedBatch")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local holding = false
local fireRate = AdminConfig.FireRate
local holdStart = nil
local hatcheryEmpty = false
local habitatFull = false

local ClickButton = playerGui:WaitForChild("MainHUD"):WaitForChild("ClickButton")
local HatcheryBar = playerGui:WaitForChild("MainHUD"):WaitForChild("HatcheryBar")
local HatcheryFill = HatcheryBar:WaitForChild("Fill")
local HatcheryLabel = HatcheryBar:WaitForChild("Label")
local clickScale = ClickButton:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", ClickButton)
local clickStroke = ClickButton:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke", ClickButton)
clickStroke.Color = Color3.fromRGB(255, 215, 0) -- Pure Gold
clickStroke.Thickness = 0
local basePos = ClickButton.Position
local tiltSide = 1

-- ✨ MILESTONE SYSTEM SETUP
local Camera = workspace.CurrentCamera
local defaultFOV = 70 -- Standard Roblox camera FOV
local lastMilestone = 1

local MilestoneData = AdminConfig.MilestoneData

local playerMultSpeed = 1.0 -- Increased by "Synaptic Overdrive" upgrade
local playerMaxTier = 5     -- Increased by "Epic Core Resonance" tier unlock upgrade
local lastTierIndex = 1
-- ADDED: FormatNumber so cube value popups show K/M instead of raw numbers
local function FormatNumber(n)
	n = math.floor(n or 0)
	if n >= 1e15 then return string.format("%.3f Q", n / 1e15)
	elseif n >= 1e12 then return string.format("%.3f T", n / 1e12)
	elseif n >= 1e9  then return string.format("%.3f B", n / 1e9)
	elseif n >= 1e6  then return string.format("%.3f M", n / 1e6)
	elseif n >= 1e3  then return string.format("%.1fK", n / 1e3)
	end
	local s = tostring(n)
	local result = ""
	local count = 0
	for i = #s, 1, -1 do
		if count > 0 and count % 3 == 0 then result = "," .. result end
		result = s:sub(i, i) .. result
		count += 1
	end
	return result
end	

---------------------------------------------------------------
-- AURA MODEL FOLDERS
---------------------------------------------------------------
local AurasFolder = ReplicatedStorage:FindFirstChild("Auras")
local VFXFolder = ReplicatedStorage:FindFirstChild("VFX")

local cubeDataMap = {}

local TierScale = {
	Common    = 1.0,
	Uncommon  = 1.15,
	Rare      = 1.3,
	Epic      = 1.5,
	Legendary = 1.75,
}

local function CloneAuraModel(tierName)
	if not AurasFolder then return nil end
	local template = AurasFolder:FindFirstChild(tierName)
	if not template then return nil end
	local clone = template:Clone()
	if not clone.PrimaryPart then
		warn("[Aura] Model '" .. tierName .. "' has no PrimaryPart set! Set PrimaryPart to the main BasePart (e.g. " .. tierName .. "VFX) for reliable positioning.")
	end
	return clone
end

local function CreatePlaceholderPart(color, glow)
	local part = Instance.new("Part")
	part.Size = Vector3.new(1.5, 1.5, 1.5)
	part.Color = color
	part.Anchored = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	if glow then
		local light = Instance.new("PointLight")
		light.Brightness = 3
		light.Range = 8
		light.Color = color
		light.Parent = part
	end
	return part
end

local function SpawnAuraInstance(tierName, color, glow, position)
	local auraModel = CloneAuraModel(tierName)
	if auraModel then
		auraModel:PivotTo(CFrame.new(position))
		auraModel.Parent = workspace
		if auraModel.PrimaryPart then
			auraModel.PrimaryPart.Anchored = false
			auraModel.PrimaryPart.CanCollide = true
		end
		return auraModel, true
	else
		local part = CreatePlaceholderPart(color, glow)
		part.Position = position
		part.Parent = workspace
		return part, false
	end
end

local function GetRootPart(instance)
	if instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart")
	end
	return instance
end

local function ScaleAura(instance, tierName, animated, fromTierName)
	local targetScale = TierScale[tierName] or 1.0
	local fromScale = fromTierName and (TierScale[fromTierName] or 1.0) or nil

	if instance:IsA("Model") then
		if fromScale and animated then
			pcall(function() instance:ScaleTo(fromScale) end)
		end
		if animated then
			local root = instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart")
			if root and root:IsA("BasePart") then
				local currentSize = root.Size
				local ratio = targetScale / (fromScale or targetScale)
				local targetSize = currentSize * ratio
				TweenService:Create(root, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Size = targetSize
				}):Play()
			end
		else
			pcall(function() instance:ScaleTo(targetScale) end)
		end
	elseif instance:IsA("BasePart") then
		local baseSize = 1.5
		local targetSize = Vector3.new(1, 1, 1) * (baseSize * targetScale)
		if animated then
			if fromScale then
				instance.Size = Vector3.new(1, 1, 1) * (baseSize * fromScale)
			end
			TweenService:Create(instance, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = targetSize
			}):Play()
		else
			instance.Size = targetSize
		end
	end
end

---------------------------------------------------------------
-- VFX SYSTEM
---------------------------------------------------------------
local function PlayVFX(effectName, position, duration)
	if not VFXFolder then return end
	local template = VFXFolder:FindFirstChild(effectName)
	if not template then return end

	local vfx = template:Clone()

	if vfx:IsA("Model") then
		vfx:PivotTo(CFrame.new(position))
	elseif vfx:IsA("BasePart") then
		vfx.Position = position
	end

	for _, obj in ipairs(vfx:GetDescendants()) do
		if obj:IsA("BasePart") then
			obj.Anchored = true
			obj.Transparency = 1
			obj.CanCollide = false
			obj.CastShadow = false
		end
	end
	if vfx:IsA("BasePart") then
		vfx.Anchored = true
		vfx.Transparency = 1
		vfx.CanCollide = false
		vfx.CastShadow = false
	end

	vfx.Parent = workspace

	for _, emitter in ipairs(vfx:GetDescendants()) do
		if emitter:IsA("ParticleEmitter") then
			emitter.Enabled = true
		end
	end
	for _, emitter in ipairs(vfx:GetDescendants()) do
		if emitter:IsA("ParticleEmitter") then
			emitter:Emit(emitter:GetAttribute("BurstCount") or 15)
		end
	end

	task.delay((duration or 1.0) * 0.5, function()
		if vfx and vfx.Parent then
			for _, emitter in ipairs(vfx:GetDescendants()) do
				if emitter:IsA("ParticleEmitter") then
					emitter.Enabled = false
				end
			end
		end
	end)

	Debris:AddItem(vfx, duration or 1.5)
end

-- ✨ PROGRESSION STATS (These can be updated later by shop upgrades!)
local playerMultSpeed = 1.0  -- 1.0 is base speed
local playerMaxMult = 5.0    -- The highest tier they can reach
local baseGrowthPerSecond = 0.8 -- At 0.8, it takes exactly 5 seconds to hit 5.0x

local function GetCurrentMultiplier()
	if not holding or not holdStart then return 1.0, 1 end

	local holdTime = tick() - holdStart
	local effectiveTime = holdTime * playerMultSpeed 

	local currentTier = 1
	local nextTier = 1

	-- 1. Find which tier we are currently in
	for i = 1, playerMaxTier do
		if effectiveTime >= MilestoneData[i].time then
			currentTier = i
			nextTier = math.min(i + 1, playerMaxTier)
		end
	end

	-- 2. If we hit the max tier, lock it at that multiplier
	if currentTier == playerMaxTier then
		return MilestoneData[currentTier].mult, currentTier
	end

	-- 3. SMOOTH MATH: Calculate the exact decimal between the current and next tier
	local timePassedInTier = effectiveTime - MilestoneData[currentTier].time
	local timeNeededForNext = MilestoneData[nextTier].time - MilestoneData[currentTier].time
	local progressRatio = timePassedInTier / timeNeededForNext

	local currentMult = MilestoneData[currentTier].mult
	local nextMult = MilestoneData[nextTier].mult
	local smoothMult = currentMult + ((nextMult - currentMult) * progressRatio)

	return smoothMult, currentTier
end

-- ✨ PASTE THIS NEW FUNCTION RIGHT HERE
local function PlayMilestoneSound(soundValue)
	if not soundValue or soundValue == "" then return end
	local sfxToPlay = nil

	if string.find(soundValue, "rbxassetid://") then
		sfxToPlay = Instance.new("Sound")
		sfxToPlay.SoundId = soundValue
		sfxToPlay.Volume = 0.6
	else
		local sfxFolder = ReplicatedStorage:FindFirstChild("SFX") or ReplicatedStorage:FindFirstChild("Sounds")
		if sfxFolder then
			local foundSound = sfxFolder:FindFirstChild(soundValue)
			if foundSound then
				sfxToPlay = foundSound:Clone()
				sfxToPlay.Volume = 0.6
			else
				warn("⚠️ Could not find sound named '" .. soundValue .. "' in ReplicatedStorage.SFX!")
			end
		end
	end

	if sfxToPlay then
		sfxToPlay.Parent = game:GetService("SoundService")
		sfxToPlay:Play()
		local duration = sfxToPlay.TimeLength > 0 and sfxToPlay.TimeLength or 3
		Debris:AddItem(sfxToPlay, duration)
	end
end

local function SpawnMilestonePopup(multFloor)
	local data = MilestoneData[multFloor]
	if not data then return end 

	PlayMilestoneSound(data.sound)

	local pop = Instance.new("TextLabel")
	pop.Text = data.name .. " (" .. string.format("%.1f", data.mult) .. "x)"
	pop.Font = Enum.Font.FredokaOne 
	pop.TextScaled = true
	pop.TextColor3 = data.color
	pop.BackgroundTransparency = 1
	pop.AnchorPoint = Vector2.new(0.5, 0.5)

	-- ✨ MOBILE FIX 1: Starts floating 15% above the button instead of 120 pixels
	pop.Position = UDim2.new(
		ClickButton.Position.X.Scale, ClickButton.Position.X.Offset, 
		ClickButton.Position.Y.Scale - 0.15, ClickButton.Position.Y.Offset
	)
	pop.Parent = ClickButton.Parent

	local stroke = Instance.new("UIStroke", pop)
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(0, 0, 0)

	-- ✨ MOBILE FIX 2: Tiny starting size using Scale instead of flat pixels
	pop.Size = UDim2.new(0.1, 0, 0.02, 0) 

	-- ✨ MOBILE FIX 3: Grows to 35% of the screen width, and floats up an extra 10%
	TweenService:Create(pop, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0.35, 0, 0.08, 0),
		Position = UDim2.new(
			pop.Position.X.Scale, pop.Position.X.Offset, 
			ClickButton.Position.Y.Scale - 0.25, ClickButton.Position.Y.Offset
		)
	}):Play()

	task.delay(0.6, function()
		TweenService:Create(pop, TweenInfo.new(0.3), {TextTransparency = 1}):Play()
		TweenService:Create(stroke, TweenInfo.new(0.3), {Transparency = 1}):Play()
		task.delay(0.3, function() pop:Destroy() end)
	end)
end

local function GetColorForMultiplier(multValue)
	local floorMult = math.floor(multValue)
	local highestTier = 1
	local chosenColor = Color3.fromRGB(255, 0, 0) -- Default Red for Tier 1

	for tier, data in pairs(MilestoneData) do
		if floorMult >= tier and tier >= highestTier then
			highestTier = tier
			chosenColor = data.color
		end
	end
	return chosenColor
end

local function UpdateButtonVisual()
	local col
	local mult = 1
	local currentTierIndex = 1

	if habitatFull then
		col = Color3.fromRGB(180, 60, 60)
	elseif not holding then
		col = Color3.fromRGB(255, 0, 0)
	else
		-- Get both the exact multiplier and the Tier Index (1-5)
		mult, currentTierIndex = GetCurrentMultiplier()
		col = MilestoneData[currentTierIndex].color
		UpdateMultiplier:Fire(mult)
	end

	-- ✨ SCREEN EFFECT: Warp speed camera FOV!
	local targetFOV = defaultFOV + (mult * 1.2)
	if not holding then targetFOV = defaultFOV end
	TweenService:Create(Camera, TweenInfo.new(0.3, Enum.EasingStyle.Sine), {FieldOfView = targetFOV}):Play()

	-- ✨ BULLETPROOF MILESTONE POPUPS
	if holding then
		if currentTierIndex > lastTierIndex then
			-- If they upgraded tiers, spawn the popup for the new tier!
			-- We skip tier 1 ("NORMAL") so it doesn't pop up immediately on click.
			if currentTierIndex > 1 then
				SpawnMilestonePopup(currentTierIndex)
			end
			lastTierIndex = currentTierIndex
		end
	else
		lastTierIndex = 1
	end

	TweenService:Create(ClickButton, TweenInfo.new(0.2), { BackgroundColor3 = col }):Play()

	-- ... (Keep your alternating tilt/shake code below here exactly as it is!)

	if holding and not habitatFull then
		-- Flip the tilt direction every single time it fires
		tiltSide = tiltSide * -1 

		if mult >= 5.0 then 
			-- ✨ LEGENDARY: Violent alternating rotation (8 degrees)
			TweenService:Create(ClickButton, TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true), {
				Rotation = 8 * tiltSide
			}):Play()

			-- Fast, aggressive golden energy bleed
			clickStroke.Thickness = 12
			clickStroke.Transparency = 0
			TweenService:Create(clickStroke, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Thickness = 0, Transparency = 1}):Play()
		else
			-- ✨ NORMAL: Gentle alternating tilt (3 degrees)
			TweenService:Create(ClickButton, TweenInfo.new(0.08, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, true), {
				Rotation = 3 * tiltSide
			}):Play()
		end
	elseif not holding then
		-- Reset rotation and scale safely when let go
		TweenService:Create(ClickButton, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Rotation = 0}):Play()
		TweenService:Create(clickScale, TweenInfo.new(0.15), {Scale = 1}):Play()
	end
end

-- 3. UpdateHatcheryBar
local function UpdateHatcheryBar(current, max)
	local ratio = math.clamp(current / max, 0, 1)
	TweenService:Create(HatcheryFill, TweenInfo.new(0.1), {
		Size = UDim2.new(ratio, 0, 1, 0)
	}):Play()
	local color
	if ratio > 0.5 then color = Color3.fromRGB(80, 220, 80)
	elseif ratio > 0.25 then color = Color3.fromRGB(255, 200, 0)
	else color = Color3.fromRGB(255, 60, 60) end
	TweenService:Create(HatcheryFill, TweenInfo.new(0.1), { BackgroundColor3 = color }):Play()
	HatcheryLabel.Text = "Hatchery: " .. math.floor(current) .. " / " .. max
	hatcheryEmpty = (current <= 0)
end

-- 4. FlashEmpty
local function FlashEmpty()
	TweenService:Create(HatcheryFill, TweenInfo.new(0.1), {
		BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	}):Play()
	task.delay(0.1, function()
		TweenService:Create(HatcheryFill, TweenInfo.new(0.1), {
			BackgroundColor3 = Color3.fromRGB(255, 60, 60)
		}):Play()
	end)
end

-- 5. ShowTierPopup
local function ShowTierPopup(position, tierName, tierColor)
	local anchor = Instance.new("Part")
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Anchored = true
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.Position = position + Vector3.new(0, 3, 0)
	anchor.Parent = workspace

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 120, 0, 40)
	bb.StudsOffset = Vector3.new(0, 2, 0)
	bb.AlwaysOnTop = false
	bb.Adornee = anchor
	bb.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = tierName:upper()
	label.TextColor3 = tierColor
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextStrokeTransparency = 0.3
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.Parent = bb

	TweenService:Create(bb,
		TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ StudsOffset = Vector3.new(0, 6, 0) }
	):Play()
	TweenService:Create(label,
		TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }
	):Play()

	Debris:AddItem(anchor, 2)
end

-- 6. ShowCubeValue
local function ShowCubeValue(position, value, color)
	local anchor = Instance.new("Part")
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Anchored = true
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.Position = position + Vector3.new(math.random(-1, 1), 2, math.random(-1, 1))
	anchor.Parent = workspace

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 80, 0, 25)
	bb.StudsOffset = Vector3.new(0, 0, 0)
	bb.AlwaysOnTop = false
	bb.Adornee = anchor
	bb.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = "$" .. FormatNumber(value)  -- CHANGED: was tostring(value)
	label.TextColor3 = color
	label.TextScaled = true
	label.Font = Enum.Font.Gotham
	label.TextStrokeTransparency = 0.4
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.Parent = bb

	TweenService:Create(bb,
		TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ StudsOffset = Vector3.new(0, 4, 0) }
	):Play()
	TweenService:Create(label,
		TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }
	):Play()

	Debris:AddItem(anchor, 1.5)
end

---------------------------------------------------------------
-- 8 & 9. HOLD STATE EVALUATION (MOBILE FIX & SPACEBAR)
---------------------------------------------------------------
local trackedInputs = {}

local function EvaluateHolding()
	local hasInput = false
	for _, _ in pairs(trackedInputs) do
		hasInput = true
		break
	end

	if hasInput and not holding then
		-- Start Holding
		if hatcheryEmpty then FlashEmpty() return end
		if habitatFull then return end
		holding = true
		holdStart = tick()

		-- ✨ TACTILE PRESS: Heavy center squish before the rotations start
		TweenService:Create(clickScale, TweenInfo.new(0.1, Enum.EasingStyle.Sine), {Scale = 0.9}):Play()

		ProduceAura:FireServer("start")
	elseif not hasInput and holding then
		-- Stop Holding
		holding = false
		holdStart = nil
		ProduceAura:FireServer("stop")
		UpdateButtonVisual()
		UpdateMultiplier:Fire(1.0)
	end
end

---------------------------------------------------------------
-- 10. INPUT CONNECTIONS
---------------------------------------------------------------
ClickButton.InputBegan:Connect(function(input)
	-- Track the exact touch or click
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		trackedInputs[input] = true
		EvaluateHolding()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	-- Only stop holding if the EXACT touch/click/key that started it has been released
	if trackedInputs[input] then
		trackedInputs[input] = nil
		EvaluateHolding()
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	-- Spacebar support (Allows jumping because it doesn't block the input!)
	if input.KeyCode == Enum.KeyCode.Space then
		if not UserInputService:GetFocusedTextBox() then -- Ignores Spacebar if typing in chat
			trackedInputs[input] = true
			EvaluateHolding()
		end
	end
end)

-- Prevents the button getting "stuck" if the player alt-tabs out of Roblox
UserInputService.WindowFocusReleased:Connect(function()
	table.clear(trackedInputs)
	EvaluateHolding()
end)

ForceStopHold.OnClientEvent:Connect(function()
	table.clear(trackedInputs)
	EvaluateHolding()
end)

HabitatFull.OnClientEvent:Connect(function()
	habitatFull = true
	HabitatFullEvent:Fire(true)
	table.clear(trackedInputs)
	EvaluateHolding()
end)

HabitatFullEvent.Event:Connect(function(isFull)
	if not isFull then
		habitatFull = false
		UpdateButtonVisual()
	end
end)

UpdateHatchery.OnClientEvent:Connect(function(info)
	UpdateHatcheryBar(info.current, info.max)
end)

local UpdateHUDEvent = ReplicatedStorage.RemoteEvents:WaitForChild("UpdateHUD")
UpdateHUDEvent.OnClientEvent:Connect(function(stats)
	-- 1. Check Habitat
	if stats.pendingAuras and stats.habitatCapacity then
		if stats.pendingAuras < stats.habitatCapacity and habitatFull then
			habitatFull = false
			HabitatFullEvent:Fire(false)
			UpdateButtonVisual()
		end
	end

	-- ✨ THE FIX: Constantly check upgrades so the client never forgets!
	if stats.upgrades then
		-- ✨ THE SCALABLE TIER UNLOCK SYSTEM (Now syncing correctly on HUD update!)
		local tierUnlocks = {
			{ upgradeId = "unlockOmniMult",      tier = 10 },
			{ upgradeId = "unlockUniversalMult", tier = 9 },
			{ upgradeId = "unlockGodlyMult",     tier = 8 },
			{ upgradeId = "unlockCosmicMult",    tier = 7 },
			{ upgradeId = "unlockMythicMult",    tier = 6 },
		}

		local calculatedMaxTier = 5 -- Default max tier (Legendary) if they bought nothing

		-- Check upgrades from top to bottom
		for _, data in ipairs(tierUnlocks) do
			local upgData = stats.upgrades[data.upgradeId]
			local level = (typeof(upgData) == "table" and upgData.level) or (typeof(upgData) == "number" and upgData) or 0

			if level > 0 then
				calculatedMaxTier = data.tier
				break -- We found their highest unlock, so stop checking!
			end
		end

		-- Apply the properly calculated cap
		playerMaxTier = calculatedMaxTier

		-- Sync the Speed Multiplier
		local speedData = stats.upgrades["multiplierSpeed"]
		local speedLevel = (typeof(speedData) == "table" and speedData.level) or (typeof(speedData) == "number" and speedData) or 0
		playerMultSpeed = 1.0 + (speedLevel * 0.05) 
	end
end)

-- 11. Fire loop
task.spawn(function()
	while true do
		if holding then
			if hatcheryEmpty or habitatFull then
				-- ✨ THE FIX: Properly tell the new input system to stop holding
				table.clear(trackedInputs)
				EvaluateHolding()
			else
				ProduceAura:FireServer()
				UpdateButtonVisual()
			end
		end
		task.wait(fireRate)
	end
end)

---------------------------------------------------------------
-- 12. AuraSpawned
---------------------------------------------------------------
AuraSpawned.OnClientEvent:Connect(function(info)
	local instance, isCustom = SpawnAuraInstance(info.tier, info.color, info.glow, info.spawnPos)

	instance:SetAttribute("AuraCube", true)
	ScaleAura(instance, info.tier, false)
	ShowCubeValue(info.spawnPos, info.value, info.color)
	PlayVFX("Spawn", info.spawnPos, 1.0)

	if info.tier == "Legendary" then
		ShowTierPopup(info.spawnPos, "Legendary", Color3.fromRGB(255, 200, 0))
		PlayVFX("Legendary", info.spawnPos, 2.0)
	end

	if info.cubeId then
		cubeDataMap[info.cubeId] = {
			instance = instance,
			tierName = info.tier,
			isCustom = isCustom,
		}

		if instance:IsA("Model") then
			instance.AncestryChanged:Connect(function(_, parent)
				if not parent then cubeDataMap[info.cubeId] = nil end
			end)
		else
			instance.AncestryChanged:Connect(function(_, parent)
				if not parent then cubeDataMap[info.cubeId] = nil end
			end)
		end
	end
end)

CubeMutatedBatch.OnClientEvent:Connect(function(batchData)
	-- Loop through every mutation the server sent in this batch
	for _, info in ipairs(batchData) do

		local cubeData = cubeDataMap[info.cubeId]
		if not cubeData then continue end -- CHANGED: Use continue instead of return

		local instance = cubeData.instance
		if not instance or not instance.Parent then continue end -- CHANGED

		local rootPart = GetRootPart(instance)
		if not rootPart then continue end -- CHANGED
		local position = rootPart.Position

		if info.mutationType == "tierUpgrade" then
			PlayVFX("TierUpgrade", position, 1.5)
			if info.tierName == "Legendary" then
				PlayVFX("Legendary", position, 2.0)
			end

			local oldTierName = cubeData.tierName
			local newAura = CloneAuraModel(info.tierName)
			if newAura then
				newAura:PivotTo(CFrame.new(position))
				newAura.Parent = workspace
				newAura:SetAttribute("AuraCube", true)
				ScaleAura(newAura, info.tierName, true, oldTierName)

				if newAura.PrimaryPart then
					newAura.PrimaryPart.Anchored = false
					newAura.PrimaryPart.CanCollide = true
				end

				instance:Destroy()

				cubeData.instance = newAura
				cubeData.tierName = info.tierName
				cubeData.isCustom = true

				newAura.AncestryChanged:Connect(function(_, parent)
					if not parent then cubeDataMap[info.cubeId] = nil end
				end)
			else
				if rootPart:IsA("BasePart") then
					TweenService:Create(rootPart, TweenInfo.new(0.5, Enum.EasingStyle.Quad), {
						Color = info.newColor
					}):Play()

					if info.newGlow then
						local light = rootPart:FindFirstChildOfClass("PointLight")
						if not light then
							light = Instance.new("PointLight")
							light.Parent = rootPart
						end
						TweenService:Create(light, TweenInfo.new(0.5), {
							Brightness = 3,
							Range = 8,
							Color = info.newColor,
						}):Play()
					end

					ScaleAura(instance, info.tierName, true, oldTierName)
				end

				cubeData.tierName = info.tierName
			end

			ShowTierPopup(position, info.tierName, info.newColor)

		elseif info.mutationType == "valueBonus" then
			-- Silent
		end
	end
end)

---------------------------------------------------------------
-- HUD BUTTON POLISH
---------------------------------------------------------------
local function AddBasicJuice(btn)
	if not btn then return end
	local scale = btn:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", btn)
	btn.MouseEnter:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15), {Scale = 1.08}):Play() end)
	btn.MouseLeave:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15), {Scale = 1}):Play() end)
	btn.MouseButton1Down:Connect(function() TweenService:Create(scale, TweenInfo.new(0.1), {Scale = 0.9}):Play() end)
	btn.MouseButton1Up:Connect(function() TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), {Scale = 1.08}):Play() end)
end

AddBasicJuice(playerGui:WaitForChild("MainHUD"):FindFirstChild("ModeToggle"))
AddBasicJuice(playerGui:WaitForChild("MainHUD"):FindFirstChild("SendButton"))

ReplicatedStorage.RemoteEvents.UpgradeUpdated.OnClientEvent:Connect(function(info)
	if not info or not info.upgrades then return end

	-- 1. Setup Speed
	local speedData = info.upgrades["multiplierSpeed"]
	local speedLevel = (typeof(speedData) == "table" and speedData.level) or (typeof(speedData) == "number" and speedData) or 0
	playerMultSpeed = 1.0 + (speedLevel * 0.05) 

	-- ✨ 2. THE NEW SCALABLE TIER UNLOCK SYSTEM
	-- List your highest upgrades at the top, down to the lowest.
	local tierUnlocks = {
		{ upgradeId = "unlockOmniMult",      tier = 10 },
		{ upgradeId = "unlockUniversalMult", tier = 9 },
		{ upgradeId = "unlockGodlyMult",     tier = 8 },
		{ upgradeId = "unlockCosmicMult",    tier = 7 },
		{ upgradeId = "unlockMythicMult",    tier = 6 },
	}

	local calculatedMaxTier = 5 -- Default max tier (Legendary) if they bought nothing

	-- Check upgrades from top to bottom. The first one they own becomes their max tier!
	for _, data in ipairs(tierUnlocks) do
		local upgData = info.upgrades[data.upgradeId]
		local level = (typeof(upgData) == "table" and upgData.level) or (typeof(upgData) == "number" and upgData) or 0

		if level > 0 then
			calculatedMaxTier = data.tier
			break -- We found their highest unlock, so stop checking!
		end
	end

	-- Apply the newly calculated cap
	playerMaxTier = calculatedMaxTier
end)
	local effectiveFireRate = AdminConfig.FireRate / (rushMult * weatherSpawnMult)
	if lastFire[uid] then
		local timeSinceLast = now - lastFire[uid]
		if timeSinceLast > 3 then clickSessionStart[uid] = now end
		if not clickSessionStart[uid] then clickSessionStart[uid] = now end
		local sessionLength = now - clickSessionStart[uid]
		if sessionLength > 300 then effectiveFireRate *= 2 end
		if sessionLength > 600 then effectiveFireRate *= 4 end
		if timeSinceLast < effectiveFireRate then return end
	else
		clickSessionStart[uid] = now
	end
	lastFire[uid] = now

	local data    = GameManager.GetData(uid)
	local runtime = GameManager.GetRuntime(uid)
	if not data or not runtime then return end
	if runtime.cubeCount >= GetHabitatCapacity(data) then HabitatFull:FireClient(player); return end

	local holdTime = now - holdStart[uid]
	local holdMult, luckBonus = GetHoldMultiplier(holdTime, data)
	SpawnAura(player, data, runtime, holdMult, luckBonus)
	SendHUDUpdate(player)
	UpdateHatchery:FireClient(player, { current=hatchery[uid], max=GetHatcheryMax(data) })
end)
