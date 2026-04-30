-- ShippingManager
-- Location: ServerScriptService > ShippingManager
-- FIXES:
--   1. SendHUDUpdate now stamps lastSentCurrency so PassiveIncome dedup table
--      stays consistent (both paths write to the same source of truth)
--   2. Payout UpdateHUD fires unconditionally (payout is always a genuine
--      increase — UIController's directional-snap logic will sync up correctly)
--   3. Minor: activeTrucks guard raised to 50 so fast cooldowns aren't blocked

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local HttpService         = game:GetService("HttpService")

local AdminConfig      = require(ReplicatedStorage.Modules.AdminConfig)
local UpgradeConfig    = require(ReplicatedStorage.Modules.UpgradeConfig)
local MutationConfig   = require(ReplicatedStorage.Modules.MutationConfig)
local GameManager      = require(ServerScriptService.GameManager)
local EpicUpgradeConfig = require(ReplicatedStorage.Modules.EpicUpgradeConfig)

local ShipAuras = ReplicatedStorage.RemoteEvents:WaitForChild("ShipAuras")
local UpdateHUD = ReplicatedStorage.RemoteEvents:WaitForChild("UpdateHUD")

local playerTimers   = {}
local activeTrucks   = {}
local playerAutoMode = {}
local pendingPayouts = {}  -- SECURE: [uid][dispatchId] = amount

-- ─────────────────────────────────────────────────────────────────────────────
-- PLAYER LIFECYCLE
-- ─────────────────────────────────────────────────────────────────────────────
Players.PlayerAdded:Connect(function(player)
	playerTimers[player.UserId]   = AdminConfig.ShipInterval
	activeTrucks[player.UserId]   = 0
	playerAutoMode[player.UserId] = AdminConfig.AutoDispatch
	pendingPayouts[player.UserId] = {}
end)

Players.PlayerRemoving:Connect(function(player)
	playerTimers[player.UserId]   = nil
	activeTrucks[player.UserId]   = nil
	playerAutoMode[player.UserId] = nil
	pendingPayouts[player.UserId] = nil
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- HUD UPDATE HELPER
-- ─────────────────────────────────────────────────────────────────────────────
local function SendHUDUpdate(player)
	local uid     = player.UserId
	local data    = GameManager.GetData(uid)
	local runtime = GameManager.GetRuntime(uid)
	if not data or not runtime then return end

	local totalMutatedValue = runtime.totalMutatedValue
	local pending           = runtime.cubeCount
	local avgValue          = pending > 0 and (totalMutatedValue / pending) or AdminConfig.BaseAuraValue
	local rate              = math.floor(pending * avgValue)

	local habCfg      = UpgradeConfig.GetUpgradeConfig("habitatCapacity")
	local habitatCap  = (habCfg and habCfg.apply) and habCfg.apply(data) or AdminConfig.BaseHabitatCapacity

	local tickCfg    = UpgradeConfig.GetUpgradeConfig("passiveTickSpeed")
	local passiveInt = (tickCfg and tickCfg.apply) and tickCfg.apply(data) or AdminConfig.PassiveInterval

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
		shipCooldown    = finalCooldown,
	})
end

-- ─────────────────────────────────────────────────────────────────────────────
-- DISPATCH
-- ─────────────────────────────────────────────────────────────────────────────
local function TryDispatch(player)
	if AdminConfig.DisableShipping then return end
	local uid     = player.UserId
	local data    = GameManager.GetData(uid)
	local runtime = GameManager.GetRuntime(uid)
	if not data or not runtime then return end
	if (activeTrucks[uid] or 0) >= 50 then return end

	local totalCubes = runtime.cubeCount
	if totalCubes <= 0 then return end

	local toCollect  = math.min(totalCubes, AdminConfig.PlatformCapacity)
	local cubeIds, cubes = GameManager.CollectOldestCubes(uid, toCollect)
	local collected  = #cubeIds
	if collected == 0 then return end

	local totalPayout = 0
	for _, cube in ipairs(cubes) do
		totalPayout = totalPayout + MutationConfig.GetMutatedValue(cube)
	end

	activeTrucks[uid] = (activeTrucks[uid] or 0) + 1
	data.totalPlatformsShipped = (data.totalPlatformsShipped or 0) + 1

	local dispatchId = HttpService:GenerateGUID(false)
	pendingPayouts[uid][dispatchId] = totalPayout

	SendHUDUpdate(player)

	ShipAuras:FireClient(player, {
		collected  = collected,
		payout     = totalPayout,
		dispatchId = dispatchId,
	})
end

-- ─────────────────────────────────────────────────────────────────────────────
-- SERVER EVENT
-- ─────────────────────────────────────────────────────────────────────────────
ShipAuras.OnServerEvent:Connect(function(player, action, value)
	local uid = player.UserId

	-- ── Manual ship ──────────────────────────────────────────────────────────
	if action == "manual" then
		TryDispatch(player)

		local data          = GameManager.GetData(uid)
		local shipReduction = 0
		if data then
			local shipCfg = EpicUpgradeConfig.GetUpgradeConfig("epicShipCooldown")
			if shipCfg and shipCfg.apply then shipReduction = shipCfg.apply(data) end
		end
		playerTimers[uid] = math.max(1, AdminConfig.ShipInterval - shipReduction)
		return
	end

	-- ── Mode toggle ───────────────────────────────────────────────────────────
	if action == "setMode" then
		playerAutoMode[uid] = (value == "auto")
		return
	end

	-- ── Payout confirmation ───────────────────────────────────────────────────
	if action == "payout" then
		if player:GetAttribute("TutorialFrozen") then return end

		local data = GameManager.GetData(uid)
		if not data then return end

		-- SECURITY: value is the dispatchId, not a money amount
		local dispatchId   = value
		local actualPayout = pendingPayouts[uid] and pendingPayouts[uid][dispatchId]

		if not actualPayout then
			warn("[Security] " .. player.Name .. " attempted invalid platform payout.")
			return
		end

		-- Clear so it can't fire twice
		pendingPayouts[uid][dispatchId] = nil
		activeTrucks[uid] = math.max(0, (activeTrucks[uid] or 1) - 1)

		data.currency       = (data.currency       or 0) + actualPayout
		data.totalEarned    = (data.totalEarned     or 0) + actualPayout
		data.farmEvaluation = (data.farmEvaluation  or 0) + actualPayout

		-- Payout is always a genuine increase — UIController's "server is higher"
		-- branch will sync up cleanly without any snap concerns.
		SendHUDUpdate(player)

		-- ✨ NEW: Fire explicit, exact confirmation back to the client for UI juice!
		ShipAuras:FireClient(player, {
			action = "payoutConfirmed",
			amount = actualPayout
		})
	end
end)


-- UIController
-- Location: StarterPlayer > StarterPlayerScripts > UIController
-- FIXES:
--   1. Directional snap logic: server being lower after a purchase no longer snaps display down
--   2. Safe window extended to 2.5s (was 1.2s) so PassiveIncome can't fire within it
--   3. LastServerPurchaseTick attribute also extends the safe window on server confirmation
--   4. Habitat bar / rate / currency only update when those fields are present in payload

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local AdminConfig       = require(ReplicatedStorage.Modules.AdminConfig)
local Formatter         = require(ReplicatedStorage.Modules.NumberFormatter)
local UITheme           = require(ReplicatedStorage.Modules.UITheme)

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local UpdateHUD = ReplicatedStorage.RemoteEvents:WaitForChild("UpdateHUD")
local ShipAuras = ReplicatedStorage.RemoteEvents:WaitForChild("ShipAuras")
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

-- ─────────────────────────────────────────────────────────────────────────────
-- SPEND TRACKERS
-- ─────────────────────────────────────────────────────────────────────────────
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
		GoldenAurasLabel.Text = "GAURAS: " .. liveGoldenAuras
		lastSpendTick = tick()
		player:SetAttribute("LocalAuraSpend", 0)
	end
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- HELPERS
-- ─────────────────────────────────────────────────────────────────────────────
local function FormatNumber(n) return Formatter.Format(n) end

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

-- ─────────────────────────────────────────────────────────────────────────────
-- HUD REFS
-- ─────────────────────────────────────────────────────────────────────────────
local hud        = playerGui:WaitForChild("MainHUD")
local curr       = hud:WaitForChild("CurrencyLabel")
local rate       = hud:WaitForChild("RateLabel")
local sendButton = hud:WaitForChild("SendButton")
local modeToggle = hud:WaitForChild("ModeToggle")

-- ─────────────────────────────────────────────────────────────────────────────
-- MANUAL BUTTON COOLDOWN VISUALS
-- ─────────────────────────────────────────────────────────────────────────────
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

-- ─────────────────────────────────────────────────────────────────────────────
-- SEND BUTTON VISIBILITY
-- ─────────────────────────────────────────────────────────────────────────────
local function UpdateSendButton()
	if AdminConfig.DisableShipping then sendButton.Visible = false; return end
	sendButton.Visible = not isAutoMode and (pendingAuras or 0) > 0
	if sendButton.Visible then
		SyncManualCooldownVisuals()
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- AUTO MODE COOLDOWN BAR
-- ─────────────────────────────────────────────────────────────────────────────
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

-- ─────────────────────────────────────────────────────────────────────────────
-- MODE TOGGLE VISUALS
-- ─────────────────────────────────────────────────────────────────────────────
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

-- ─────────────────────────────────────────────────────────────────────────────
-- BUTTON CONNECTIONS
-- ─────────────────────────────────────────────────────────────────────────────
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

-- INITIAL SETUP
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
	-- ── Safe-window: don't let the server overwrite display money right after
	--    a purchase. Uses BOTH the local spend tick AND the server confirmation
	--    tick so neither path can sneak through early.
	local serverPurchaseTick = player:GetAttribute("LastServerPurchaseTick") or 0
	local safeToSync = (tick() - math.max(lastSpendTick, serverPurchaseTick)) > 2.5

	-- ── Golden auras ──────────────────────────────────────────────────────────
	if stats.goldenAuras ~= nil and safeToSync then
		liveGoldenAuras = stats.goldenAuras
		GoldenAurasLabel.Text = "GAURAS: " .. liveGoldenAuras
	end

	-- ── Currency  ─────────────────────────────────────────────────────────────
	if stats.currency ~= nil then
		local newServerCurrency = stats.currency

		if safeToSync then
			local snapThreshold = math.max(500, ratePerSecond * 8)

			if newServerCurrency > displayedCurrency then
				-- Server has MORE (payout landed, admin gave money) → always sync up
				displayedCurrency = newServerCurrency
				curr.TextColor3 = Color3.fromRGB(80, 255, 80)
				TweenService:Create(curr, TweenInfo.new(0.4), {
					TextColor3 = Color3.fromRGB(255, 255, 255)
				}):Play()

			elseif (displayedCurrency - newServerCurrency) > snapThreshold then
				-- Server is MUCH lower than display → genuine desync, snap down
				displayedCurrency = newServerCurrency
				curr.TextColor3 = Color3.fromRGB(255, 80, 80)
				TweenService:Create(curr, TweenInfo.new(0.4), {
					TextColor3 = Color3.fromRGB(255, 255, 255)
				}):Play()
			end
		end

		prevServerCurrency = newServerCurrency
		serverCurrency     = newServerCurrency
	end

	-- ── Pending auras / habitat ───────────────────────────────────────────────
	if stats.pendingAuras ~= nil then
		pendingAuras    = stats.pendingAuras
		habitatCapacity = stats.habitatCapacity or habitatCapacity
		UpdateHabitatBar(pendingAuras, habitatCapacity)
		UpdateSendButton()
	end

	-- ── Rate ──────────────────────────────────────────────────────────────────
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

	-- ── Ship cooldown ─────────────────────────────────────────────────────────
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

-- ─────────────────────────────────────────────────────────────────────────────
-- THEME FLAIR
-- ─────────────────────────────────────────────────────────────────────────────
local function RefreshLook()
	UITheme.ApplyFlair(GoldenAurasLabel, "GoldStroke")
end
task.wait(2)
RefreshLook()

-- PortalController
-- Location: StarterPlayer > StarterPlayerScripts > PortalController
-- All sizes read from ReplicatedStorage/Modules/UIConfig
--
-- PHASE 4 FIX: All travel goes through TravelToArea (was EnterPortal for forward).
--   Forward unlocked: green TRAVEL button.  Backward: GO BACK button.
--   Batched unlock banner.  ProximityPrompt opens panel.
-- MOBILE FIX: StatsPanel uses Scale + UISizeConstraint + AutomaticCanvasSize ScrollContainer.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")

local AreaRegistry = require(ReplicatedStorage.Modules.AreaRegistry)
local SoundConfig  = require(ReplicatedStorage.Modules.SoundConfig)
local T            = require(ReplicatedStorage.Modules.UITheme).Get()
local C            = require(ReplicatedStorage.Modules.UIConfig)
local Formatter    = require(ReplicatedStorage.Modules.NumberFormatter) -- Omega Formatter linked!
local UITheme = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("UITheme"))
local T = UITheme.Get("Custom")
local AreaUpdated      = ReplicatedStorage.RemoteEvents:WaitForChild("AreaUpdated")
local AreaUnlocked     = ReplicatedStorage.RemoteEvents:WaitForChild("AreaUnlocked")
local EnterPortal      = ReplicatedStorage.RemoteEvents:WaitForChild("EnterPortal")
local TravelToArea     = ReplicatedStorage.RemoteEvents:WaitForChild("TravelToArea")
local AreaChanged      = ReplicatedStorage.RemoteEvents:WaitForChild("AreaChanged")
local PrestigeComplete = ReplicatedStorage.RemoteEvents:WaitForChild("PrestigeComplete")
local UpdateHUD        = ReplicatedStorage.RemoteEvents:WaitForChild("UpdateHUD")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainHUD   = playerGui:WaitForChild("MainHUD")

local PositionPart = workspace:WaitForChild("AuraHolder"):WaitForChild("Position")

local promptAdded   = false
local currentArea   = 1
local portalReady   = false
local panelOpen     = false
local browseIndex   = 1
local liveFarmEval  = 0
local unlockedAreas = { 1 }
local MAX_AREA      = AreaRegistry.GetMaxArea()

local PW = C.Panels.AreaTravelW
local PH = C.Panels.AreaTravelH
local PR = C.Panels.CornerRadius
local BW = C.Banners.AreaBannerW
local BY = C.Banners.AreaBannerY
local BR = C.Banners.CornerRadius

local function PlayUI(id)
	if shared.PlayUISound then shared.PlayUISound(id) end
end

local function IsUnlocked(idx)
	for _, v in ipairs(unlockedAreas) do if v == idx then return true end end
	return false
end

---------------------------------------------------------------
-- Viewport preview (unchanged)
---------------------------------------------------------------
local AreaAssets = ReplicatedStorage:WaitForChild("AreaAssets")
local previewRotationConn, previewModelInViewport = nil, nil

local function LoadAreaPreview(viewport, worldModel, areaIndex)
	if previewRotationConn then previewRotationConn:Disconnect(); previewRotationConn = nil end
	previewModelInViewport = nil; worldModel:ClearAllChildren()
	local auraFolder = AreaAssets:FindFirstChild("Area" .. areaIndex)
	auraFolder = auraFolder and auraFolder:FindFirstChild("Auras")
	local auraModel = auraFolder and auraFolder:FindFirstChildWhichIsA("Model")
	local displayModel
	if auraModel then
		displayModel = auraModel:Clone(); displayModel.Parent = worldModel
	else
		local areaData = AreaRegistry.Get(areaIndex)
		local color = (areaData and areaData.auraPreviewColor) or Color3.fromRGB(200,200,200)
		local sphere = Instance.new("Part")
		sphere.Shape = Enum.PartType.Ball; sphere.Size = Vector3.new(3,3,3)
		sphere.Color = color; sphere.Material = Enum.Material.Neon
		sphere.Anchored = true; sphere.CastShadow = false; sphere.Position = Vector3.new(0,0,0)
		local glow = Instance.new("PointLight"); glow.Brightness=3; glow.Range=10; glow.Color=color; glow.Parent=sphere
		local model = Instance.new("Model"); model.Name="PreviewModel"; model.PrimaryPart=sphere
		sphere.Parent = model; model.Parent = worldModel; displayModel = model
	end
	local cf, size = displayModel:GetBoundingBox()
	local center, radius = cf.Position, math.max(size.X, size.Y, size.Z)
	local camera = Instance.new("Camera"); camera.FieldOfView = 45
	camera.CFrame = CFrame.new(center + Vector3.new(0, radius*0.2, radius*2.2), center)
	camera.Parent = worldModel; viewport.CurrentCamera = camera
	previewModelInViewport = displayModel
	local angle = 0
	previewRotationConn = RunService.RenderStepped:Connect(function(dt)
		if not previewModelInViewport or not previewModelInViewport.Parent then
			previewRotationConn:Disconnect(); previewRotationConn = nil; return
		end
		angle += dt * 40
		local p = previewModelInViewport:GetBoundingBox()
		previewModelInViewport:PivotTo(CFrame.new(p.Position) * CFrame.Angles(0, math.rad(angle), 0))
	end)
end

---------------------------------------------------------------
-- UI CONSTRUCTION (Responsive Mobile Setup)
---------------------------------------------------------------
local StatsPanel = Instance.new("Frame")
StatsPanel.Name="StatsPanel"; StatsPanel.Size = UDim2.new(0.88, 0, 0.82, 0)
StatsPanel.Position = UDim2.new(0.5, 0, 0.5, 0)
StatsPanel.AnchorPoint = Vector2.new(0.5, 0.5)
StatsPanel.BackgroundColor3=T.panelBG; StatsPanel.BorderSizePixel=0
StatsPanel.Visible=false; StatsPanel.ZIndex=30; StatsPanel.ClipsDescendants=true
StatsPanel.Parent=mainHUD
Instance.new("UICorner",StatsPanel).CornerRadius=UDim.new(0,PR)

-- Secret Weapon: Keeps it from getting massive on PC
local sizeConstraint = Instance.new("UISizeConstraint")
sizeConstraint.MaxSize = Vector2.new(PW, PH) 
sizeConstraint.Parent = StatsPanel

local panelStroke=Instance.new("UIStroke"); panelStroke.Color=T.panelStroke; panelStroke.Thickness=2; panelStroke.Parent=StatsPanel

local HeaderBar=Instance.new("Frame"); HeaderBar.Size=UDim2.new(1,0,0,46); HeaderBar.BackgroundColor3=T.headerBG
HeaderBar.BorderSizePixel=0; HeaderBar.ZIndex=31; HeaderBar.Parent=StatsPanel
Instance.new("UICorner",HeaderBar).CornerRadius=UDim.new(0,PR)
local HeaderLabel=Instance.new("TextLabel"); HeaderLabel.Size=UDim2.new(1,-50,1,0); HeaderLabel.Position=UDim2.new(0,16,0,0)
HeaderLabel.BackgroundTransparency=1; HeaderLabel.Text="AREA TRAVEL"; HeaderLabel.TextColor3=T.headerText
HeaderLabel.TextScaled=true; HeaderLabel.Font=T.font; HeaderLabel.TextXAlignment=Enum.TextXAlignment.Left
HeaderLabel.ZIndex=32; HeaderLabel.Parent=HeaderBar
local CloseBtn=Instance.new("TextButton"); CloseBtn.Size=UDim2.new(0,32,0,32); CloseBtn.Position=UDim2.new(1,-40,0.5,-16)
CloseBtn.BackgroundColor3=T.buttonRed; CloseBtn.BorderSizePixel=0; CloseBtn.Text="X"; CloseBtn.TextColor3=T.bodyText
CloseBtn.TextScaled=true; CloseBtn.Font=T.font; CloseBtn.ZIndex=33; CloseBtn.Parent=HeaderBar
CloseBtn:SetAttribute("TutorialTarget", "PortalCloseBtn")
Instance.new("UICorner",CloseBtn).CornerRadius=UDim.new(0,6)

---------------------------------------------------------------
-- MOBILE SCROLL FIX: The ScrollContainer
---------------------------------------------------------------
local ScrollContainer = Instance.new("ScrollingFrame")
ScrollContainer.Name = "ScrollContainer"
ScrollContainer.Size = UDim2.new(1, 0, 1, -46) -- Fills remaining space under Header
ScrollContainer.Position = UDim2.new(0, 0, 0, 46) 
ScrollContainer.BackgroundTransparency = 1
ScrollContainer.BorderSizePixel = 0
ScrollContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
ScrollContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y 
ScrollContainer.ScrollBarThickness = 6
ScrollContainer.Parent = StatsPanel

local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 10) 
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center -- Centers everything!
listLayout.Parent = ScrollContainer
-- Add a tiny bit of padding at the top so it doesn't touch the header
local topPadding = Instance.new("UIPadding")
topPadding.PaddingTop = UDim.new(0, 10)
topPadding.PaddingBottom = UDim.new(0, 10)
topPadding.Parent = ScrollContainer


-- Goal section (Now parented to ScrollContainer)
local GoalSection=Instance.new("Frame"); GoalSection.Size=UDim2.new(1,-24,0,90)
GoalSection.BackgroundColor3=T.cardBG; GoalSection.BorderSizePixel=0; GoalSection.ZIndex=31; GoalSection.Parent=ScrollContainer
Instance.new("UICorner",GoalSection).CornerRadius=UDim.new(0,8)
local FarmEvalTitle=Instance.new("TextLabel"); FarmEvalTitle.Size=UDim2.new(1,-12,0,16); FarmEvalTitle.Position=UDim2.new(0,12,0,6)
FarmEvalTitle.BackgroundTransparency=1; FarmEvalTitle.Text="FARM EVALUATION"; FarmEvalTitle.TextColor3=T.subText
FarmEvalTitle.TextScaled=true; FarmEvalTitle.Font=T.font; FarmEvalTitle.TextXAlignment=Enum.TextXAlignment.Left
FarmEvalTitle.ZIndex=32; FarmEvalTitle.Parent=GoalSection
local FarmEvalNumber=Instance.new("TextLabel"); FarmEvalNumber.Name="FarmEvalNumber"
FarmEvalNumber.Size=UDim2.new(1,-12,0,28); FarmEvalNumber.Position=UDim2.new(0,12,0,22)
FarmEvalNumber.BackgroundTransparency=1; FarmEvalNumber.Text="$0"; FarmEvalNumber.TextColor3=T.accentGreen
FarmEvalNumber.TextScaled=true; FarmEvalNumber.Font=T.font; FarmEvalNumber.TextXAlignment=Enum.TextXAlignment.Left
FarmEvalNumber.ZIndex=32; FarmEvalNumber.Parent=GoalSection
local ProgressBG=Instance.new("Frame"); ProgressBG.Size=UDim2.new(1,-24,0,8); ProgressBG.Position=UDim2.new(0,12,0,54)
ProgressBG.BackgroundColor3=Color3.fromRGB(40,50,70); ProgressBG.BorderSizePixel=0; ProgressBG.ZIndex=32; ProgressBG.Parent=GoalSection
Instance.new("UICorner",ProgressBG).CornerRadius=UDim.new(0,4)
local ProgressFill=Instance.new("Frame"); ProgressFill.Name="ProgressFill"; ProgressFill.Size=UDim2.new(0,0,1,0)
ProgressFill.BackgroundColor3=T.accentGreen; ProgressFill.BorderSizePixel=0; ProgressFill.ZIndex=33; ProgressFill.Parent=ProgressBG
Instance.new("UICorner",ProgressFill).CornerRadius=UDim.new(0,4)
local ProgressLabel=Instance.new("TextLabel"); ProgressLabel.Name="ProgressLabel"
ProgressLabel.Size=UDim2.new(1,-12,0,14); ProgressLabel.Position=UDim2.new(0,12,0,66)
ProgressLabel.BackgroundTransparency=1; ProgressLabel.Text=""; ProgressLabel.TextColor3=T.subText
ProgressLabel.TextScaled=true; ProgressLabel.Font=T.fontBody; ProgressLabel.TextXAlignment=Enum.TextXAlignment.Left
ProgressLabel.ZIndex=32; ProgressLabel.Parent=GoalSection

-- Area browser (Now parented to ScrollContainer)
local AreaBrowser=Instance.new("Frame"); AreaBrowser.Size=UDim2.new(1,-24,0,260)
AreaBrowser.BackgroundColor3=T.cardBG; AreaBrowser.BorderSizePixel=0; AreaBrowser.ZIndex=31; AreaBrowser.Parent=ScrollContainer
Instance.new("UICorner",AreaBrowser).CornerRadius=UDim.new(0,8)
local BrowseAreaName=Instance.new("TextLabel"); BrowseAreaName.Size=UDim2.new(0.6, 0, 0, 24)
BrowseAreaName.AnchorPoint=Vector2.new(0.5, 0)
BrowseAreaName.Position=UDim2.new(0.5, 0, 0, 8)
BrowseAreaName.BackgroundTransparency=1; BrowseAreaName.Text="Starter Area"; BrowseAreaName.TextColor3=T.accentBlue
BrowseAreaName.TextScaled=true; BrowseAreaName.Font=T.font; BrowseAreaName.TextXAlignment=Enum.TextXAlignment.Center
BrowseAreaName.ZIndex=32; BrowseAreaName.Parent=AreaBrowser
local AreaIndexLabel=Instance.new("TextLabel"); AreaIndexLabel.Size=UDim2.new(0,60,0,20); AreaIndexLabel.Position=UDim2.new(1,-66,0,10)
AreaIndexLabel.BackgroundTransparency=1; AreaIndexLabel.Text="1/5"; AreaIndexLabel.TextColor3=T.subText
AreaIndexLabel.TextScaled=true; AreaIndexLabel.Font=T.fontBody; AreaIndexLabel.TextXAlignment=Enum.TextXAlignment.Right
AreaIndexLabel.ZIndex=32; AreaIndexLabel.Parent=AreaBrowser
local BrowseAreaMult=Instance.new("TextLabel"); BrowseAreaMult.Size=UDim2.new(1,-20,0,18); BrowseAreaMult.Position=UDim2.new(0,10,0,34)
BrowseAreaMult.BackgroundTransparency=1; BrowseAreaMult.Text="Cube Value: 1.0x base"; BrowseAreaMult.TextColor3=T.accentGold
BrowseAreaMult.TextScaled=true; BrowseAreaMult.Font=T.fontBody; BrowseAreaMult.TextXAlignment=Enum.TextXAlignment.Center
BrowseAreaMult.ZIndex=32; BrowseAreaMult.Parent=AreaBrowser
local LeftArrow=Instance.new("TextButton"); LeftArrow.Size=UDim2.new(0,36,0,36); LeftArrow.Position=UDim2.new(0,8,0,62)
LeftArrow.BackgroundColor3=T.headerBG; LeftArrow.BorderSizePixel=0; LeftArrow.Text="<"; LeftArrow.TextColor3=T.bodyText
LeftArrow.TextScaled=true; LeftArrow.Font=T.font; LeftArrow.ZIndex=33; LeftArrow.Parent=AreaBrowser
Instance.new("UICorner",LeftArrow).CornerRadius=UDim.new(0,18)
local RightArrow=Instance.new("TextButton"); RightArrow.Size=UDim2.new(0,36,0,36); RightArrow.Position=UDim2.new(1,-44,0,62)
RightArrow.BackgroundColor3=T.headerBG; RightArrow.BorderSizePixel=0; RightArrow.Text=">"; RightArrow.TextColor3=T.bodyText
RightArrow.TextScaled=true; RightArrow.Font=T.font; RightArrow.ZIndex=33; RightArrow.Parent=AreaBrowser
RightArrow:SetAttribute("TutorialTarget", "ArrowBtn")
Instance.new("UICorner",RightArrow).CornerRadius=UDim.new(0,18)
local AreaIcon = Instance.new("ImageLabel")
AreaIcon.Name = "AreaIcon" 
AreaIcon.AnchorPoint = Vector2.new(0.5, 0)
AreaIcon.Size = UDim2.new(0, 110, 0, 110)
AreaIcon.Position = UDim2.new(0.5, 0, 0, 54)
AreaIcon.BackgroundTransparency = 1
AreaIcon.BorderSizePixel = 0
AreaIcon.ZIndex = 33
AreaIcon.Image = "" 
AreaIcon.Parent = AreaBrowser
local BrowseStatus=Instance.new("TextLabel"); BrowseStatus.Size=UDim2.new(1,-24,0,20); BrowseStatus.Position=UDim2.new(0,12,0,172)
BrowseStatus.BackgroundTransparency=1; BrowseStatus.Text="CURRENT AREA"; BrowseStatus.TextColor3=T.subText
BrowseStatus.TextScaled=true; BrowseStatus.Font=T.font; BrowseStatus.TextXAlignment=Enum.TextXAlignment.Center
BrowseStatus.ZIndex=32; BrowseStatus.Parent=AreaBrowser
local BrowseProgress=Instance.new("TextLabel"); BrowseProgress.Size=UDim2.new(1,-24,0,28); BrowseProgress.Position=UDim2.new(0,12,0,194)
BrowseProgress.BackgroundTransparency=1; BrowseProgress.Text=""; BrowseProgress.TextColor3=T.subText
BrowseProgress.TextScaled=true; BrowseProgress.Font=T.fontBody; BrowseProgress.TextWrapped=true
BrowseProgress.TextXAlignment=Enum.TextXAlignment.Center; BrowseProgress.ZIndex=32; BrowseProgress.Parent=AreaBrowser
local TravelBtn=Instance.new("TextButton"); TravelBtn.Size=UDim2.new(1,-24,0,38); TravelBtn.Position=UDim2.new(0,12,0,220)
TravelBtn.BackgroundColor3=T.buttonGreen; TravelBtn.BorderSizePixel=0; TravelBtn.Text="TRAVEL"; TravelBtn.TextColor3=T.bodyText
TravelBtn.TextScaled=true; TravelBtn.Font=T.font; TravelBtn.Visible=false; TravelBtn.ZIndex=33; TravelBtn.Parent=AreaBrowser
TravelBtn:SetAttribute("TutorialTarget", "TravelBtn")
Instance.new("UICorner",TravelBtn).CornerRadius=UDim.new(0,8)
---------------------------------------------------------------
-- UI JUICE: Button Hover & Click Animations
---------------------------------------------------------------
local function AddButtonJuice(btn)
	-- Ensure the button has a UIScale object to animate
	local scale = btn:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = btn
	end

	-- Hover in: Slight grow
	btn.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Sine), {Scale = 1.08}):Play()
	end)

	-- Hover out: Return to normal
	btn.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Sine), {Scale = 1}):Play()
	end)

	-- Click down: Shrink inwards
	btn.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1, Enum.EasingStyle.Sine), {Scale = 0.9}):Play()
	end)

	-- Release click: Bounce back to hover size
	btn.MouseButton1Up:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), {Scale = 1.08}):Play()
	end)
end

-- ✨ Apply the juice to your Area Browser buttons!
AddButtonJuice(LeftArrow)
AddButtonJuice(RightArrow)
AddButtonJuice(TravelBtn)
AddButtonJuice(CloseBtn)

-- (Optional: You can also scroll down and add `AddButtonJuice(CloseBtn)` where your Close button is!)
---------------------------------------------------------------
-- TRAVEL BUTTON
---------------------------------------------------------------
TravelBtn.MouseButton1Down:Connect(function()
	if browseIndex == currentArea then return end
	TravelToArea:FireServer(browseIndex)
end)

---------------------------------------------------------------
-- UpdateGoalSection
---------------------------------------------------------------
local function UpdateGoalSection()
	FarmEvalNumber.Text = "$" .. Formatter.Format(liveFarmEval)
	local nextGoalArea, nextGoalThreshold = nil, nil
	for i = currentArea + 1, MAX_AREA do
		local area = AreaRegistry.Get(i)
		if area and liveFarmEval < (area.threshold or 0) then
			nextGoalArea = i; nextGoalThreshold = area.threshold; break
		end
	end
	if nextGoalThreshold and nextGoalThreshold > 0 then
		local pct = math.clamp(liveFarmEval / nextGoalThreshold, 0, 1)
		TweenService:Create(ProgressFill, TweenInfo.new(0.3), { Size = UDim2.new(pct,0,1,0) }):Play()
		ProgressFill.BackgroundColor3 = pct >= 1 and Color3.fromRGB(80,255,160) or T.accentGreen
		local needed = math.max(0, nextGoalThreshold - liveFarmEval)
		ProgressLabel.Text = needed <= 0
			and "New areas available! Browse below."
			or "$" .. Formatter.Format(needed) .. " to unlock " .. AreaRegistry.GetName(nextGoalArea)
		ProgressLabel.TextColor3 = needed <= 0 and T.accentTeal or T.subText
	elseif portalReady then
		ProgressFill.Size = UDim2.new(1,0,1,0); ProgressFill.BackgroundColor3 = T.accentTeal
		ProgressLabel.Text = "Areas available! Pick a destination."; ProgressLabel.TextColor3 = T.accentTeal
	elseif currentArea >= MAX_AREA then
		ProgressFill.Size = UDim2.new(1,0,1,0); ProgressFill.BackgroundColor3 = T.accentGold
		ProgressLabel.Text = "Maximum area reached."; ProgressLabel.TextColor3 = T.accentGold
	end
end

local function RefreshBrowser()
	local idx = browseIndex
	local areaData = AreaRegistry.Get(idx)	
	if not areaData then return end
	local AreaIcon = AreaBrowser:FindFirstChild("AreaIcon")
	if not AreaIcon then return end
	AreaIndexLabel.Text = idx .. " / " .. MAX_AREA
	LeftArrow.Visible  = idx > 1
	RightArrow.Visible = AreaRegistry.Get(idx+1) ~= nil

	-- Calculate highest unlocked to know what is "Next"
	local highestUnlocked = 1
	for _, v in ipairs(unlockedAreas) do
		if v > highestUnlocked then highestUnlocked = v end
	end

	local unlockReq = areaData.threshold or 0
	-- If you haven't added a discovery threshold to the registry yet, it defaults to 25% of the unlock cost!
	local discReq = areaData.discoveryThreshold or (unlockReq * 0.25) 

	-- ✨ STATE 1: ALREADY UNLOCKED OR CURRENT
	if idx <= highestUnlocked then
		AreaIcon.Image = areaData.auraPreviewImage or ""
		AreaIcon.ImageColor3 = Color3.fromRGB(255, 255, 255) -- Full Color
		BrowseAreaName.Text = AreaRegistry.GetName(idx)
		BrowseAreaMult.Text = "Cube Value: " .. string.format("%.1f", AreaRegistry.GetMultiplier(idx)) .. "x base"

		if idx == currentArea then
			BrowseStatus.Text = "CURRENT AREA"; BrowseStatus.TextColor3 = T.accentGreen
			BrowseProgress.Text = "This is your active farm."
			BrowseProgress.TextColor3 = T.accentTeal
			TravelBtn.Visible = false
		else
			BrowseStatus.Text = "PREVIOUS AREA"; BrowseStatus.TextColor3 = T.accentGreen
			BrowseProgress.Text = "Travel back for free (no reset)."
			BrowseProgress.TextColor3 = T.accentGreen
			TravelBtn.Visible = true; TravelBtn.Text = "Travel"
			TravelBtn.BackgroundColor3 = Color3.fromRGB(60,100,60)
		end

		-- ✨ STATE 2: THE VERY NEXT AREA
	elseif idx == highestUnlocked + 1 then
		if liveFarmEval >= unlockReq then
			-- It is fully funded, ready to travel!
			AreaIcon.Image = areaData.auraPreviewImage or ""
			AreaIcon.ImageColor3 = Color3.fromRGB(255, 255, 255) -- Full Color
			BrowseAreaName.Text = AreaRegistry.GetName(idx)
			BrowseAreaMult.Text = "Cube Value: " .. string.format("%.1f", AreaRegistry.GetMultiplier(idx)) .. "x base"
			BrowseStatus.Text = "UNLOCKED"; BrowseStatus.TextColor3 = T.accentTeal
			BrowseProgress.Text = "Travel here (resets current run)."
			BrowseProgress.TextColor3 = T.accentTeal
			TravelBtn.Visible = true; TravelBtn.Text = "TRAVEL"
			TravelBtn.BackgroundColor3 = T.buttonGreen

		elseif liveFarmEval >= discReq then
			-- ✨ IT IS DISCOVERED! Full color, revealed stats, but CANNOT travel yet!
			AreaIcon.Image = areaData.auraPreviewImage or ""
			AreaIcon.ImageColor3 = Color3.fromRGB(255, 255, 255) -- Full Color!
			BrowseAreaName.Text = AreaRegistry.GetName(idx)
			BrowseAreaMult.Text = "Cube Value: " .. string.format("%.1f", AreaRegistry.GetMultiplier(idx)) .. "x base"
			BrowseStatus.Text = "DISCOVERED"; BrowseStatus.TextColor3 = T.accentPurple

			local needed = math.max(0, unlockReq - liveFarmEval)
			BrowseProgress.Text = "Requires $"..Formatter.Format(unlockReq).." Farm Eval\n$"..Formatter.Format(needed).." remaining"
			BrowseProgress.TextColor3 = T.subText
			TravelBtn.Visible = false

		else
			-- ✨ IT IS UNDISCOVERED! Black Silhouette, hidden stats!
			AreaIcon.Image = areaData.auraPreviewImage or ""
			AreaIcon.ImageColor3 = Color3.fromRGB(0, 0, 0) -- Pitch Black!
			BrowseAreaName.Text = "???"
			BrowseAreaMult.Text = "???x base"
			BrowseStatus.Text = "UNDISCOVERED"; BrowseStatus.TextColor3 = T.subText

			local needed = math.max(0, discReq - liveFarmEval)
			BrowseProgress.Text = "Keep growing to discover what's next.\n$"..Formatter.Format(needed).." to Discover"
			BrowseProgress.TextColor3 = T.subText
			TravelBtn.Visible = false
		end

		-- ✨ STATE 3: TOO FAR AHEAD (Completely Hidden)
	else
		AreaIcon.Image = areaData.auraPreviewImage or ""
		AreaIcon.ImageColor3 = Color3.fromRGB(0, 0, 0)
		BrowseAreaName.Text = "???"
		BrowseAreaMult.Text = "???x base"
		BrowseStatus.Text = "LOCKED"; BrowseStatus.TextColor3 = T.subText
		BrowseProgress.Text = "Unlock previous areas first."
		BrowseProgress.TextColor3 = T.subText
		TravelBtn.Visible = false
	end
end

LeftArrow.MouseButton1Down:Connect(function()
	if browseIndex > 1 then browseIndex -= 1; PlayUI(SoundConfig.UIArrow); RefreshBrowser() end
end)
RightArrow.MouseButton1Down:Connect(function()
	if AreaRegistry.Get(browseIndex+1) then browseIndex += 1; PlayUI(SoundConfig.UIArrow); RefreshBrowser() end
end)

---------------------------------------------------------------
-- Next Area button & Panel Logic
---------------------------------------------------------------
local StatsBtn=Instance.new("TextButton"); StatsBtn.Name="NextAreaButton"
StatsBtn.Size=UDim2.new(0,C.HUD.NextAreaButtonW,0,C.HUD.NextAreaButtonH)
StatsBtn.Position=UDim2.new(0,156,1,C.HUD.BottomButtonY)
StatsBtn.BackgroundColor3=T.headerBG; StatsBtn.BorderSizePixel=0
StatsBtn.Text="Next Area"; StatsBtn.TextColor3=T.bodyText; StatsBtn.TextScaled=true; StatsBtn.Font=T.font
StatsBtn.Visible = false -- ADD THIS LINE RIGHT HERE!
StatsBtn.ZIndex=10; StatsBtn.Parent=mainHUD
StatsBtn:SetAttribute("TutorialTarget", "AreaTravelButton")
Instance.new("UICorner",StatsBtn).CornerRadius=UDim.new(0,8)
AddButtonJuice(StatsBtn)

local function OpenPanel()
	panelOpen=true; browseIndex=currentArea; UpdateGoalSection(); RefreshBrowser()
	StatsPanel.Visible=true
	StatsPanel.Size=UDim2.new(0.88, 0, 0, 0)
	TweenService:Create(StatsPanel, TweenInfo.new(0.35,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
		{ Size=UDim2.new(0.88, 0, 0.82, 0) }):Play()
	UITheme.SetMenuVisible(true)
end

local function ClosePanel()
	panelOpen=false; PlayUI(SoundConfig.UIClose)
	TweenService:Create(StatsPanel, TweenInfo.new(0.25,Enum.EasingStyle.Quad,Enum.EasingDirection.In),
		{ Size=UDim2.new(0.88, 0, 0, 0) }):Play()
	UITheme.SetMenuVisible(false)
	task.delay(0.3, function() StatsPanel.Visible=false end)
end
StatsBtn.MouseButton1Down:Connect(function() if panelOpen then ClosePanel() else OpenPanel() end end)
CloseBtn.MouseButton1Down:Connect(ClosePanel)

---------------------------------------------------------------
-- ShowAreaBanner
---------------------------------------------------------------
local function ShowAreaBanner(info)
	if info.travelType == "backward" then return end
	local areaIndex = info.newArea or 2
	local areaData = AreaRegistry.Get(areaIndex)
	local areaName = info.areaName or AreaRegistry.GetName(areaIndex)
	local multText = "Cube Value: "..string.format("%.1f", info.areaMultiplier or 1.0).."x"
	local saText = (info.newSoulAuras and info.newSoulAuras > 0)
		and ("+"..Formatter.Format(info.newSoulAuras).." Soul Auras") or nil
	local accentColor = (areaData and areaData.auraHolderGlow) or T.accentTeal
	local bannerH = saText and 82 or 64
	local banner=Instance.new("Frame"); banner.Size=UDim2.new(0,BW,0,bannerH)
	banner.Position=UDim2.new(0,-(BW+10),0,BY); banner.BackgroundColor3=T.panelBG; banner.BorderSizePixel=0
	banner.ZIndex=55; banner.ClipsDescendants=true; banner.Parent=mainHUD
	Instance.new("UICorner",banner).CornerRadius=UDim.new(0,BR)
	local bs=Instance.new("UIStroke"); bs.Color=accentColor; bs.Thickness=1.5; bs.Parent=banner
	local nameLabel=Instance.new("TextLabel"); nameLabel.Size=UDim2.new(1,-12,0,22); nameLabel.Position=UDim2.new(0,10,0,6)
	nameLabel.BackgroundTransparency=1; nameLabel.Text=areaName; nameLabel.TextColor3=accentColor
	nameLabel.TextScaled=true; nameLabel.Font=T.font; nameLabel.TextXAlignment=Enum.TextXAlignment.Left
	nameLabel.ZIndex=56; nameLabel.Parent=banner
	local multLabel=Instance.new("TextLabel"); multLabel.Size=UDim2.new(1,-12,0,18); multLabel.Position=UDim2.new(0,10,0,30)
	multLabel.BackgroundTransparency=1; multLabel.Text=multText; multLabel.TextColor3=T.accentGold
	multLabel.TextScaled=true; multLabel.Font=T.fontBody; multLabel.TextXAlignment=Enum.TextXAlignment.Left
	multLabel.ZIndex=56; multLabel.Parent=banner
	if saText then
		local saLabel=Instance.new("TextLabel"); saLabel.Size=UDim2.new(1,-12,0,16); saLabel.Position=UDim2.new(0,10,0,52)
		saLabel.BackgroundTransparency=1; saLabel.Text=saText; saLabel.TextColor3=T.accentPurple
		saLabel.TextScaled=true; saLabel.Font=T.fontBody; saLabel.TextXAlignment=Enum.TextXAlignment.Left
		saLabel.ZIndex=56; saLabel.Parent=banner
	end
	TweenService:Create(banner, TweenInfo.new(0.4,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
		{ Position=UDim2.new(0,10,0,BY) }):Play()
	task.delay(4, function()
		TweenService:Create(banner, TweenInfo.new(0.35,Enum.EasingStyle.Quad,Enum.EasingDirection.In),
			{ Position=UDim2.new(0,-(BW+10),0,BY) }):Play()
		task.delay(0.4, function() if banner and banner.Parent then banner:Destroy() end end)
	end)
end

---------------------------------------------------------------
-- EVENT CONNECTIONS
---------------------------------------------------------------
UpdateHUD.OnClientEvent:Connect(function(stats)
	if stats.farmEvaluation ~= nil then liveFarmEval = stats.farmEvaluation end
	if panelOpen then UpdateGoalSection(); RefreshBrowser() end
end)

AreaUpdated.OnClientEvent:Connect(function(info)
	currentArea = info.currentArea or 1
	portalReady = info.portalReady == true
	if info.unlockedAreas then unlockedAreas = info.unlockedAreas end
	MAX_AREA = info.maxArea or AreaRegistry.GetMaxArea()
	if info.portalReady then AddPortalPrompt() else RemovePortalPrompt() end
	if panelOpen then UpdateGoalSection(); RefreshBrowser() end
end)

AreaUnlocked.OnClientEvent:Connect(function(info)
	portalReady = true; AddPortalPrompt()
	if info.unlockedAreas then unlockedAreas = info.unlockedAreas end
	local count = info.newAreasCount or 1
	local highestName = info.highestNewName or "New Area"
	local PBW = C.Banners.PortalBannerW; local PBH = C.Banners.PortalBannerH
	local banner=Instance.new("Frame"); banner.Size=UDim2.new(0,PBW,0,PBH)
	banner.Position=UDim2.new(0.5,-PBW/2,0,-PBH-10); banner.BackgroundColor3=T.panelBG; banner.BorderSizePixel=0
	banner.ZIndex=60; banner.Parent=mainHUD
	Instance.new("UICorner",banner).CornerRadius=UDim.new(0,BR)
	local bStroke=Instance.new("UIStroke"); bStroke.Color=T.accentTeal; bStroke.Thickness=2; bStroke.Parent=banner
	local bLabel=Instance.new("TextLabel"); bLabel.Size=UDim2.new(1,-20,1,0); bLabel.Position=UDim2.new(0,10,0,0)
	bLabel.BackgroundTransparency=1
	bLabel.Text = count == 1
		and (highestName.." unlocked! Open Area Travel.")
		or (count.." new areas unlocked! Open Area Travel to choose.")
	bLabel.TextColor3=T.accentTeal; bLabel.TextScaled=true; bLabel.Font=T.font; bLabel.ZIndex=61; bLabel.Parent=banner
	TweenService:Create(banner, TweenInfo.new(0.4,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
		{ Position=UDim2.new(0.5,-PBW/2,0,14) }):Play()
	task.delay(5, function()
		TweenService:Create(banner, TweenInfo.new(0.35,Enum.EasingStyle.Quad,Enum.EasingDirection.In),
			{ Position=UDim2.new(0.5,-PBW/2,0,-PBH-10) }):Play()
		task.delay(0.4, function() if banner and banner.Parent then banner:Destroy() end end)
	end)
end)

PrestigeComplete.OnClientEvent:Connect(function(info)
	if info.isPortalEntry then
		portalReady=false; liveFarmEval=0; RemovePortalPrompt()
		if panelOpen then ClosePanel() end
	end
end)

AreaChanged.OnClientEvent:Connect(function(info)
	currentArea = info.newArea or currentArea; browseIndex = currentArea; portalReady = false
	if info.unlockedAreas then unlockedAreas = info.unlockedAreas end
	if panelOpen then ClosePanel() end
	ShowAreaBanner(info)
end)

---------------------------------------------------------------
-- ProximityPrompt — opens panel so player can CHOOSE
---------------------------------------------------------------
function AddPortalPrompt()
	if promptAdded then return end; promptAdded = true
	local prompt=Instance.new("ProximityPrompt"); prompt.Name="PortalPrompt"; prompt.ObjectText="Portal"
	prompt.ActionText="Open Area Travel"; prompt.HoldDuration=0.5; prompt.MaxActivationDistance=12
	prompt.Parent=PositionPart
	prompt.Triggered:Connect(function(p) if p == player and not panelOpen then OpenPanel() end end)
end
function RemovePortalPrompt()
	promptAdded=false; local e=PositionPart:FindFirstChild("PortalPrompt"); if e then e:Destroy() end
end

local function RefreshLook()
	UITheme.Apply(StatsPanel, "Panel")
	UITheme.Apply(HeaderBar, "TitleBar")
	UITheme.Apply(GoalSection, "ShopCard")
	UITheme.Apply(AreaBrowser, "ShopCard")
	UITheme.Apply(HeaderBar, "Panel")
	UITheme.Apply(RightArrow, "Panel")
	UITheme.Apply(LeftArrow, "Panel")
	UITheme.Apply(StatsBtn, "Panel")
	UITheme.ApplyShine(AreaBrowser)
	UITheme.ApplyShine(GoalSection)
	UITheme.ApplyShine(StatsPanel)
	GoalSection.BackgroundColor3 = T.cardBG 
	AreaBrowser.BackgroundColor3 = T.cardBG
	local outerStroke = StatsPanel:FindFirstChildWhichIsA("UIStroke")
	if outerStroke then
		outerStroke.Color = Color3.fromRGB(255, 255, 255) -- Change these RGB numbers to whatever color you want!
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

-- PassiveIncome
-- Location: ServerScriptService > PassiveIncome
-- FIXES:
--   1. Deduplication: only fires UpdateHUD when currency actually changed,
--      so stale lower-currency packets can't sneak past UIController's safe window
--   2. TutorialFreeze remote creation moved to top so it is always registered
--   3. Removed unreachable code that was below the infinite while-loop

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AdminConfig    = require(ReplicatedStorage.Modules.AdminConfig)
local UpgradeConfig  = require(ReplicatedStorage.Modules.UpgradeConfig)
local GameManager    = require(ServerScriptService.GameManager)
local BoostManager   = require(ServerScriptService.BoostManager)
local UpdateHUD      = ReplicatedStorage.RemoteEvents:WaitForChild("UpdateHUD")

-- Guard against duplicate scripts
if script:GetAttribute("Running") then script:Destroy(); return end
script:SetAttribute("Running", true)

-- ─────────────────────────────────────────────────────────────────────────────
-- TUTORIAL FREEZE REMOTE  (set up at the top so it is always available)
-- ─────────────────────────────────────────────────────────────────────────────
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

-- ─────────────────────────────────────────────────────────────────────────────
-- HELPERS
-- ─────────────────────────────────────────────────────────────────────────────
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

-- ─────────────────────────────────────────────────────────────────────────────
-- PER-PLAYER STATE
-- ─────────────────────────────────────────────────────────────────────────────
local playerTimers       = {}  -- accumulated time since last tick
local lastSentCurrency   = {}  -- dedupe: last currency value we sent to each player

Players.PlayerAdded:Connect(function(p)
	playerTimers[p.UserId]     = 0
	lastSentCurrency[p.UserId] = 0
end)

Players.PlayerRemoving:Connect(function(p)
	playerTimers[p.UserId]     = nil
	lastSentCurrency[p.UserId] = nil
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- MAIN LOOP
-- ─────────────────────────────────────────────────────────────────────────────
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

			-- ── FIX: only fire UpdateHUD if the currency value actually changed.
			--    This prevents a stale, lower currency value from reaching
			--    UIController within 2.5 s of a purchase and triggering a snap.
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
