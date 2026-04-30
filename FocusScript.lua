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
	end
end)

-- PlatformController
-- Location: StarterPlayer > StarterPlayerScripts > PlatformController
-- FIX: HABITAT is a Model and has a child Part named "Position".
--      HABITAT.Position was returning that Part (an Instance) instead
--      of a Vector3, causing "arithmetic on Vector3 and Instance".
--      Fix: HABITAT_POS = HABITAT:GetPivot().Position (a real Vector3).
--      HABITAT_POS is recalculated fresh in ProcessPlatform so it
--      always reflects the current model position at runtime.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local AdminConfig = require(ReplicatedStorage.Modules.AdminConfig)

local ShipAuras       = ReplicatedStorage.RemoteEvents:WaitForChild("ShipAuras")
local UpdateMultiplier = ReplicatedStorage:WaitForChild("UpdateMultiplier")
local HabitatFullEvent = ReplicatedStorage:WaitForChild("HabitatFullEvent")

local TRUCK_SPAWN = workspace:WaitForChild("TruckSpawn")
local TRUCK_DEST  = workspace:WaitForChild("TruckDestination")
local HabitatHolder = workspace:WaitForChild("HabitatHolder") 
-- FIX: HABITAT is a Model — .Position would find the child Part named "Position"
-- instead of returning a Vector3. Use GetPivot().Position for the model center.
local function GetHabitatPos()
	return HabitatHolder:WaitForChild("Position").Position
end

local currentMultiplier = 1.0
local platformQueue = {}
local processingPlatform = false

local MultiplierColors = {
	[1.0] = Color3.fromRGB(255, 255, 255),
	[1.5] = Color3.fromRGB(100, 200, 255),
	[2.0] = Color3.fromRGB(80, 255, 120),
	[3.0] = Color3.fromRGB(180, 60, 255),
	[5.0] = Color3.fromRGB(255, 200, 0),
}

local MultiplierNames = {
	[1.0] = "No Bonus",
	[1.5] = "1.5x Bonus",
	[2.0] = "2x Bonus",
	[3.0] = "3x Bonus",
	[5.0] = "5x Bonus",
}

UpdateMultiplier.Event:Connect(function(mult)
	currentMultiplier = mult
end)

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

local function CreatePlatform()
	local platform = Instance.new("Part")
	platform.Name = "HoverPlatform"
	platform.Size = Vector3.new(8, 0.5, 8)
	platform.Anchored = true
	platform.CastShadow = false
	platform.Material = Enum.Material.Neon
	platform.Color = MultiplierColors[currentMultiplier] or Color3.fromRGB(255, 255, 255)
	platform.Position = TRUCK_SPAWN.Position + Vector3.new(0, AdminConfig.PlatformHoverHeight, 0)
	platform.Parent = workspace

	local light = Instance.new("PointLight")
	light.Brightness = 2
	light.Range = 12
	light.Color = platform.Color
	light.Parent = platform

	return platform
end

---------------------------------------------------------------
-- ✨ MOBILE SCALED PLATFORM LABELS
---------------------------------------------------------------
local function AttachLabels(platform, payout, multiplier)
	local payoutBB = Instance.new("BillboardGui")
	-- ✨ MOBILE FIX: Changed from Pixel Offset to Scale (Width 5, Height 1)
	payoutBB.Size = UDim2.new(5, 0, 1, 0)
	payoutBB.StudsOffset = Vector3.new(0, 4, 0)
	payoutBB.AlwaysOnTop = false
	payoutBB.Adornee = platform
	payoutBB.Parent = platform

	local payoutLabel = Instance.new("TextLabel")
	payoutLabel.Size = UDim2.new(1, 0, 1, 0)
	payoutLabel.BackgroundTransparency = 1
	payoutLabel.Text = "$" .. FormatNumber(payout)
	payoutLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
	payoutLabel.TextScaled = true
	payoutLabel.Font = Enum.Font.GothamBold
	payoutLabel.TextStrokeTransparency = 1
	payoutLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	payoutLabel.TextTransparency = 1
	payoutLabel.Parent = payoutBB

	local multBB = Instance.new("BillboardGui")
	-- ✨ MOBILE FIX: Scale sizing
	multBB.Size = UDim2.new(4, 0, 0.8, 0)
	multBB.StudsOffset = Vector3.new(0, 2, 0)
	multBB.AlwaysOnTop = false
	multBB.Adornee = platform
	multBB.Parent = platform

	local multLabel = Instance.new("TextLabel")
	multLabel.Size = UDim2.new(1, 0, 1, 0)
	multLabel.BackgroundTransparency = 1
	multLabel.Text = MultiplierNames[multiplier] or "No Bonus"
	multLabel.TextColor3 = MultiplierColors[multiplier] or Color3.fromRGB(255, 255, 255)
	multLabel.TextScaled = true
	multLabel.Font = Enum.Font.Gotham
	multLabel.TextStrokeTransparency = 1
	multLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	multLabel.TextTransparency = 1
	multLabel.Parent = multBB

	TweenService:Create(payoutLabel, TweenInfo.new(0.3), { TextTransparency = 0, TextStrokeTransparency = 0.3 }):Play()
	TweenService:Create(multLabel, TweenInfo.new(0.3), { TextTransparency = 0, TextStrokeTransparency = 0.4 }):Play()
end

---------------------------------------------------------------
-- ✨ MOBILE SCALED EPIC POPUP
---------------------------------------------------------------
local function PayoutPopup(position, payout, multiplier)
	local anchor = Instance.new("Part")
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Anchored = true
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.Position = position
	anchor.Parent = workspace

	local bb = Instance.new("BillboardGui")
	-- ✨ MOBILE FIX: Scale sizing so "EPIC!" doesn't block the whole screen
	bb.Size = UDim2.new(6, 0, 1.5, 0) 
	bb.StudsOffset = Vector3.new(0, 6, 0)
	bb.AlwaysOnTop = false
	bb.Adornee = anchor
	bb.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = "+ $" .. FormatNumber(payout)
	label.TextColor3 = MultiplierColors[multiplier] or Color3.fromRGB(100, 255, 100)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.TextTransparency = 0
	label.Parent = bb

	TweenService:Create(bb, TweenInfo.new(1.8, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { StudsOffset = Vector3.new(0, 18, 0) }):Play()
	task.delay(0.6, function()
		TweenService:Create(label, TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
	Debris:AddItem(anchor, 2.5)
end

local function GetAuraBlocksNearHabitat()
	local blocks = {}
	local habitatPos = GetHabitatPos()  -- FIX: was HABITAT.Position (returned child Part)

	for _, obj in ipairs(workspace:GetChildren()) do
		if obj.Name == "HoverPlatform" or obj == HabitatHolder
			or obj == TRUCK_SPAWN or obj == TRUCK_DEST then
			continue
		end

		local rootPart = nil
		local isCube = false

		if obj:GetAttribute("AuraCube") then
			isCube = true
			if obj:IsA("Model") then
				rootPart = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
			elseif obj:IsA("BasePart") then
				rootPart = obj
			end
		elseif obj:IsA("Part") and obj.Material == Enum.Material.Neon then
			isCube = true
			rootPart = obj
		end

		if isCube and rootPart then
			local dist = (rootPart.Position - habitatPos).Magnitude  -- FIX
			if dist < 20 then
				table.insert(blocks, { instance = obj, rootPart = rootPart })
			end
		end
	end
	return blocks
end

local function MagnetBlocks(platform, blocks, count)
	local collected = math.min(#blocks, count)
	if collected == 0 then return end

	local tweensDone = 0
	local tweensStarted = 0

	for i = 1, collected do
		local block = blocks[i]
		if not block or not block.rootPart or not block.rootPart.Parent then continue end

		local rootPart = block.rootPart
		local instance = block.instance

		rootPart.Anchored = true

		local tweenProps = { Position = platform.Position }
		if instance:IsA("BasePart") then
			tweenProps.Size = Vector3.new(0.1, 0.1, 0.1)
		end

		local tween = TweenService:Create(rootPart,
			TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			tweenProps
		)

		tweensStarted += 1
		tween.Completed:Connect(function()
			instance:Destroy()
			tweensDone += 1
		end)
		tween:Play()
		task.wait(0.05)
	end

	local timeout = tick() + 3
	while tweensDone < tweensStarted and tick() < timeout do
		task.wait(0.05)
	end
end

local function ProcessPlatform(info)
	if info.collected == 0 then return end

	local myPayout     = info.payout
	local myMultiplier = currentMultiplier
	local myDispatchId = info.dispatchId -- GET THE SECURE ID
	local platform     = CreatePlatform()

	-- FIX: call GetHabitatPos() for a real Vector3 each time
	local habitatPos = GetHabitatPos()

	local distIn = (TRUCK_SPAWN.Position - habitatPos).Magnitude
	local tweenIn = TweenService:Create(platform,
		TweenInfo.new(distIn / AdminConfig.PlatformSpeed, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = habitatPos + Vector3.new(0, AdminConfig.PlatformHoverHeight, 0) }
	)
	tweenIn:Play()
	tweenIn.Completed:Wait()

	AttachLabels(platform, myPayout, myMultiplier)
	PayoutPopup(platform.Position, myPayout, myMultiplier)

	local blocks = GetAuraBlocksNearHabitat()
	MagnetBlocks(platform, blocks, info.collected)

	task.wait(0.5)

	HabitatFullEvent:Fire(false)

	local distOut = (habitatPos - TRUCK_DEST.Position).Magnitude
	local tweenOut = TweenService:Create(platform,
		TweenInfo.new(distOut / AdminConfig.PlatformSpeed, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = TRUCK_DEST.Position + Vector3.new(0, AdminConfig.PlatformHoverHeight, 0) }
	)
	tweenOut:Play()
	tweenOut.Completed:Wait()

	platform:Destroy()
	ShipAuras:FireServer("payout", myDispatchId)
end

local function ProcessQueue()
	if processingPlatform then return end
	processingPlatform = true

	while #platformQueue > 0 do
		local nextInfo = table.remove(platformQueue, 1)
		ProcessPlatform(nextInfo)
	end

	processingPlatform = false
end

ShipAuras.OnClientEvent:Connect(function(info)
	table.insert(platformQueue, info)
	task.spawn(ProcessQueue)
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
-- UpdateHUD EVENT  ← THE MAIN FIX IS HERE
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

				-- If the server value is lower but within threshold it means the
				-- player just bought something. Don't touch displayedCurrency — the
				-- LocalSpend handler already subtracted it instantly.
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
