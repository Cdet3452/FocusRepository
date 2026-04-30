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
	if (activeTrucks[uid] or 0) >= AdminConfig.MaxTrucks then return end

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

task.spawn(function()
	while true do
		task.wait(1)
		for _, player in ipairs(Players:GetPlayers()) do
			if player:GetAttribute("TutorialFrozen") then continue end
			local uid = player.UserId
			if not playerAutoMode[uid] then continue end

			-- ✨ Get player's specific upgraded interval
			local data = GameManager.GetData(uid)
			local shipReduction = 0
			if data then
				local shipCfg = EpicUpgradeConfig.GetUpgradeConfig("epicShipCooldown")
				if shipCfg and shipCfg.apply then shipReduction = shipCfg.apply(data) end
			end
			local currentInterval = math.max(1, AdminConfig.ShipInterval - shipReduction)

			-- Use the upgraded interval instead of the base config!
			playerTimers[uid] = (playerTimers[uid] or currentInterval) - 1
			if playerTimers[uid] <= 0 then
				playerTimers[uid] = currentInterval
				TryDispatch(player)
			end
		end
	end
end)

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
