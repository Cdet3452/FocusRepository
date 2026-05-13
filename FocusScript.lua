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

-- ✨ BRIDGENET2 UPGRADES (The Spammy 6)
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
local clickSessionStart = {}

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
		discoveredTiers = data.discoveredTiers or {}
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
						cubeId = cubeId, 
						mutationType = "valueBonus",
						bonusLevel = nl, 
						bonusPercent = be and math.floor(be.bonus * 100) or 0 
					})
				end

				local maxTier = AdminConfig.MutationMaxTierIndex or 3
				local upgrades = 0

				while cube.tierIndex < maxTier and cube.tierIndex < #TierConfig.Tiers and upgrades < 5 do

					if areaModels then
						local nextTierName = TierConfig.Tiers[cube.tierIndex + 1].name
						if not areaModels[nextTierName] then
							break 
						end
					end

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

						table.insert(mutationBatch, { 
							cubeId = cubeId, 
							mutationType = "tierUpgrade",
							newColor = newTier.color, 
							newGlow = newTier.glow, 
							tierName = newTier.name,
							currentArea = currentArea
						})

						if newTier.name == "Legendary" then
							data.totalLegendaryCubes = (data.totalLegendaryCubes or 0) + 1
						end
					else 
						break 
					end
				end

				if mutated then
					local newMutatedValue = MutationConfig.GetMutatedValue(cube)
					runtime.totalMutatedValue = (runtime.totalMutatedValue or 0) + (newMutatedValue - oldMutatedValue)
					if not cube.isStored then
						runtime.activeMutatedValue = (runtime.activeMutatedValue or 0) + (newMutatedValue - oldMutatedValue)
					end
				end
			end

			if #mutationBatch > 0 then
				CubeMutatedBatchBridge:Fire(player, mutationBatch)
			end
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
		{ upgradeId = "unlockOmniMult",      tier = 10 },
		{ upgradeId = "unlockUniversalMult", tier = 9 },
		{ upgradeId = "unlockGodlyMult",     tier = 8 },
		{ upgradeId = "unlockCosmicMult",    tier = 7 },
		{ upgradeId = "unlockMythicMult",    tier = 6 },
	}

	for _, tData in ipairs(tierUnlocks) do
		local lvl = upgrades[tData.upgradeId]
		local finalLvl = (typeof(lvl) == "table" and lvl.level) or (typeof(lvl) == "number" and lvl) or 0
		if finalLvl > 0 then
			playerMaxTier = tData.tier
			break
		end
	end

	local effectiveTime = holdTime * playerMultSpeed
	local currentTier = 1

	for i = 1, playerMaxTier do
		if AdminConfig.MilestoneData[i] and effectiveTime >= AdminConfig.MilestoneData[i].time then
			currentTier = i
		end
	end

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
		table.insert(adjusted, { tier=tier, chance=chance })
		total += chance
	end

	local r, cum = math.random() * total, 0
	for _, e in ipairs(adjusted) do
		cum += e.chance
		if r <= cum then return e.tier end
	end
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
	local valueUpgrades = {
		"blockValue", "blockValueT2", "auraValueT3", 
		"auraValueT4", "auraValueT6", "auraValueT8", "auraValueT10"
	}

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

	local cubeRecord = {
		spawnTime=tick(), effectiveElapsed=0, lastUpgradeElapsed=0,
		baseValue=totalValue, tierIndex=tierIndex,
		tierName=tier.name, color=tier.color, glow=tier.glow,
		isStored=false,
		currentArea=currentArea 
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

	AuraSpawnedBridge:Fire(player, {
		cubeId=cubeId, tier=tier.name, color=tier.color,
		glow=tier.glow, value=totalValue, spawnPos=spawnPos,
		currentArea = currentArea 
	})
end

ProduceAuraBridge:Connect(function(player, action)
	local uid = player.UserId
	local now = tick()
	local data    = GameManager.GetData(uid)
	local runtime = GameManager.GetRuntime(uid)

	if action == "start" then 
		if data and runtime then
			local storedCount = runtime.storedCubeCount or 0
			if storedCount >= GetHabitatCapacity(data) then
				HabitatFull:FireClient(player)
				return
			end
		end

		if (hatchery[uid] or 0) > 0.5 then 
			holdStart[uid] = now 
		else
			UpdateHatcheryBridge:Fire(player, { current = 0, max = data and GetHatcheryMax(data) or AdminConfig.HatcheryMax })
		end
		return 
	end

	if action == "stop" then 
		holdStart[uid] = nil; return 
	end

	if not data or not runtime then return end

	local capacity = GetHabitatCapacity(data)
	local storedCount = runtime.storedCubeCount or 0

	if storedCount >= capacity then HabitatFull:FireClient(player); return end
	if runtime.cubeCount >= capacity + 150 then return end 

	if (hatchery[uid] or 0) <= 0.5 then 
		UpdateHatcheryBridge:Fire(player, { current = 0, max = data and GetHatcheryMax(data) or AdminConfig.HatcheryMax })
		return 
	end
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

	local holdTime = now - holdStart[uid]
	local holdMult, luckBonus = GetHoldMultiplier(holdTime, data)
	SpawnAura(player, data, runtime, holdMult, luckBonus)
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
		if storedCount >= GetHabitatCapacity(data) then
			HabitatFull:FireClient(player)
		end
	end
end)

CubeSmushedBridge:Connect(function(player, cubeId)
	local uid = player.UserId

	GameManager.RemoveCube(uid, cubeId)
	SendHUDUpdate(player)

	local data = GameManager.GetData(uid)
	UpdateHatcheryBridge:Fire(player, { current = hatchery[uid], max = GetHatcheryMax(data) })
end)

-- BoostManager
-- Location: ServerScriptService > BoostManager (ModuleScript)

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AdminConfig = require(ReplicatedStorage.Modules.AdminConfig)
local GameManager = require(ServerScriptService.GameManager)
local BoostConfig = require(ReplicatedStorage.Modules.BoostConfig)
local AchievementConfig = require(ReplicatedStorage.Modules.AchievementConfig)

-- ✨ BRIDGENET2 UPGRADE
local BridgeNet2      = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))
local UpdateHUDBridge = BridgeNet2.ServerBridge("UpdateHUD")

local function GetOrCreate(name)
	local existing = ReplicatedStorage.RemoteEvents:FindFirstChild(name)
	if existing then return existing end
	local re = Instance.new("RemoteEvent")
	re.Name   = name
	re.Parent = ReplicatedStorage.RemoteEvents
	return re
end

local BuyBoost      = GetOrCreate("BuyBoost")
local ActivateBoost = GetOrCreate("ActivateBoost")
local BoostUpdated  = GetOrCreate("BoostUpdated")

local activeStacks = {}

local function GetActiveStacks(uid, boostId)
	local stacks = activeStacks[uid] or {}
	local count, now = 0, tick()
	for _, entry in ipairs(stacks) do
		if entry.boostId == boostId and entry.endsAt > now then
			count += 1
		end
	end
	return count
end

local function PruneExpired(uid)
	local stacks = activeStacks[uid]
	if not stacks then return end
	local now, pruned = tick(), {}
	for _, entry in ipairs(stacks) do
		if entry.endsAt > now then table.insert(pruned, entry) end
	end
	activeStacks[uid] = pruned
end

local function AdditiveMultiplier(uid, boostId)
	PruneExpired(uid)
	local cfg = BoostConfig.Get(boostId)
	if not cfg then return 1 end
	local bonus  = (cfg.multiplier or 2) - 1 
	local count  = GetActiveStacks(uid, boostId)	
	return 1 + bonus * count
end

local BoostManager = {}

function BoostManager.GetSpawnRateMultiplier(uid)
	return AdditiveMultiplier(uid, "AuraRush")
end

function BoostManager.GetValueMultiplier(uid)
	return AdditiveMultiplier(uid, "SpawnBoost")
end

function BoostManager.IsActive(uid, boostId)
	return GetActiveStacks(uid, boostId) > 0
end

function BoostManager.GetSoulMultiplier(uid)
	PruneExpired(uid)
	local stacks = activeStacks[uid] or {}
	local now    = tick()
	local cfg = BoostConfig.Get("SoulBoost")
	for _, entry in ipairs(stacks) do
		if entry.boostId == "SoulBoost" and entry.endsAt > now then
			return cfg and cfg.multiplier or 2
		end
	end
	return 1
end

local function BuildState(uid)
	PruneExpired(uid)
	local stacks = activeStacks[uid] or {}
	local data   = GameManager.GetData(uid)
	local now    = tick()

	local state = {}

	for boostId, cfg in pairs(BoostConfig.Boosts or {}) do
		local activeList = {}
		for _, entry in ipairs(stacks) do
			if entry.boostId == boostId and entry.endsAt > now then
				table.insert(activeList, math.max(0, entry.endsAt - now))
			end
		end
		state[boostId] = {
			inventoryCount = data and (data.boostInventory and data.boostInventory[boostId] or 0) or 0,
			activeCount    = #activeList,
			activeTimes    = activeList,
			duration       = cfg.duration,
			cost           = cfg.cost,
			multiplier     = cfg.multiplier,
			displayName    = cfg.displayName,
			description    = cfg.description,
			icon           = cfg.icon,
			maxStack       = cfg.maxStack,
			stackable      = cfg.stackable,
		}
	end

	state._goldenAuras = data and (data.goldenAuras or 0) or 0
	return state
end

local function SendState(player)
	BoostUpdated:FireClient(player, BuildState(player.UserId))
end

BuyBoost.OnServerEvent:Connect(function(player, boostId)
	local uid  = player.UserId
	local data = GameManager.GetData(uid)
	if not data then return end

	local cfg = BoostConfig.Get(boostId)
	if not cfg then warn("[BoostManager] Unknown boost:", boostId); return end

	local cost = cfg.cost or 0
	if (data.goldenAuras or 0) < cost then return end
	local isUnlocked = AchievementConfig.IsBoostUnlocked(boostId, data)
	if not isUnlocked then return end 

	data.goldenAuras = (data.goldenAuras or 0) - cost
	data.boostInventory = data.boostInventory or {}
	data.boostInventory[boostId] = (data.boostInventory[boostId] or 0) + 1

	SendState(player)
	UpdateHUDBridge:Fire(player, {
		goldenAuras    = data.goldenAuras,
		boostInventory = data.boostInventory,
	})
end)

ActivateBoost.OnServerEvent:Connect(function(player, boostId)
	local uid  = player.UserId
	local data = GameManager.GetData(uid)
	if not data then return end

	local cfg = BoostConfig.Get(boostId)
	if not cfg then return end

	data.boostInventory = data.boostInventory or {}
	if (data.boostInventory[boostId] or 0) <= 0 then return end

	PruneExpired(uid)
	local currentStacks = GetActiveStacks(uid, boostId)
	if currentStacks >= (cfg.maxStack or 1) then return end

	data.boostInventory[boostId] = data.boostInventory[boostId] - 1

	if cfg.duration == 0 then
		if cfg.effectType == "cashCheck" then
			local payout = math.floor((data.farmEvaluation or 0) * (cfg.multiplier or 5))
			if payout > 0 then
				data.currency    = (data.currency or 0) + payout
				data.totalEarned = (data.totalEarned or 0) + payout

				UpdateHUDBridge:Fire(player, {
					currency      = data.currency,
					totalEarned   = data.totalEarned,
					instantPayout = payout 
				})
			end
		end

		SendState(player)
		return
	end

	activeStacks[uid] = activeStacks[uid] or {}
	table.insert(activeStacks[uid], {
		boostId = boostId,
		endsAt  = tick() + cfg.duration,
	})

	SendState(player)

	task.delay(cfg.duration, function()
		PruneExpired(uid)
		if player and player.Parent then SendState(player) end
	end)
end)

Players.PlayerAdded:Connect(function(player)
	activeStacks[player.UserId] = {}
	task.wait(2)
	SendState(player)
end)

Players.PlayerRemoving:Connect(function(player)
	activeStacks[player.UserId] = nil
end)

task.spawn(function()
	while true do
		task.wait(5)
		for _, player in ipairs(Players:GetPlayers()) do
			if activeStacks[player.UserId] and #activeStacks[player.UserId] > 0 then
				SendState(player)
			end
		end
	end
end)

return BoostManager

-- BoostController
-- Location: StarterPlayer > StarterPlayerScripts > BoostController

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local AdminConfig       = require(ReplicatedStorage.Modules.AdminConfig)
local SoundConfig       = require(ReplicatedStorage.Modules.SoundConfig)
local BoostConfig       = require(ReplicatedStorage.Modules.BoostConfig) 
local AchievementConfig = require(ReplicatedStorage.Modules.AchievementConfig)
local UITheme           = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UITheme"))
local T                 = UITheme.Get("Custom")

local BuyBoost      = ReplicatedStorage.RemoteEvents:WaitForChild("BuyBoost")
local ActivateBoost = ReplicatedStorage.RemoteEvents:WaitForChild("ActivateBoost")
local BoostUpdated  = ReplicatedStorage.RemoteEvents:WaitForChild("BoostUpdated")

-- ✨ BRIDGENET2 UPGRADE
local BridgeNet2      = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))
local UpdateHUDBridge = BridgeNet2.ClientBridge("UpdateHUD")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainHUD   = playerGui:WaitForChild("MainHUD")

local boostState = {}
local panelOpen  = false
local liveGold   = 0

local function PlayUI(id)
	if shared.PlayUISound then shared.PlayUISound(id) end
end

local function FormatTime(s)
	s = math.ceil(s or 0)
	if s <= 0 then return "0:00" end
	return string.format("%d:%02d", math.floor(s/60), s % 60)
end

---------------------------------------------------------------
-- ✨ ACTIVE BOOST STRIP 
---------------------------------------------------------------
local BoostStrip = Instance.new("Frame")
BoostStrip.Name = "ActiveBoostStrip"
BoostStrip.Size = UDim2.new(0.14, 0, 0.5, 0) 
BoostStrip.AnchorPoint = Vector2.new(1, 0)
BoostStrip.Position = UDim2.new(0.98, 0, 0.5, 0) 
BoostStrip.BackgroundTransparency = 1
BoostStrip.ZIndex = 60; BoostStrip.Visible = false; BoostStrip.Parent = mainHUD

local StripLayout = Instance.new("UIListLayout")
StripLayout.FillDirection = Enum.FillDirection.Vertical
StripLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right 
StripLayout.VerticalAlignment = Enum.VerticalAlignment.Top
StripLayout.Padding = UDim.new(0, 6)
StripLayout.Parent = BoostStrip

local stripSlots = {}

for _, boostId in ipairs(BoostConfig.ShopOrder) do
	local cfg   = BoostConfig.Get(boostId)
	if not cfg then continue end
	local color = cfg.color

	local slot = Instance.new("Frame")
	slot.Name = "Slot_" .. boostId
	slot.Size = UDim2.new(1, 0, 0, 42)  
	slot.BackgroundColor3 = T.cardBG; slot.BorderSizePixel = 0
	slot.ZIndex = 61; slot.Visible = false; slot.Parent = BoostStrip
	Instance.new("UICorner", slot).CornerRadius = UDim.new(0, 8)
	local ss = Instance.new("UIStroke"); ss.Color = color; ss.Thickness = 1.5; ss.Parent = slot

	local iconFrame = Instance.new("Frame", slot)
	iconFrame.Size = UDim2.new(0, 32, 0, 32)
	iconFrame.Position = UDim2.new(0, 5, 0.5, -16)
	iconFrame.BackgroundColor3 = color
	iconFrame.BackgroundTransparency = 0.8
	Instance.new("UICorner", iconFrame).CornerRadius = UDim.new(0, 6)

	local iconLbl = Instance.new("ImageLabel", iconFrame)
	iconLbl.Size = UDim2.new(0.8, 0, 0.8, 0)
	iconLbl.Position = UDim2.new(0.1, 0, 0.1, 0)
	iconLbl.BackgroundTransparency = 1; iconLbl.Image = cfg.icon or ""
	iconLbl.ScaleType = Enum.ScaleType.Fit
	iconLbl.ZIndex = 62

	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size = UDim2.new(0.5, 0, 0.45, 0)
	nameLbl.Position = UDim2.new(0, 45, 0, 4)
	nameLbl.BackgroundTransparency = 1; nameLbl.Text = cfg.displayName or boostId
	nameLbl.TextColor3 = color; nameLbl.TextScaled = true
	nameLbl.Font = Enum.Font.FredokaOne; nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.ZIndex = 62; nameLbl.Parent = slot

	local shadow = nameLbl:Clone()
	shadow.Name = "Shadow"
	shadow.ZIndex = 61
	shadow.TextColor3 = Color3.fromRGB(0,0,0)
	shadow.TextTransparency = 0.5
	shadow.Position = nameLbl.Position + UDim2.new(0,1,0,1)
	shadow.Parent = slot

	local timeLbl = Instance.new("TextLabel")
	timeLbl.Name = "TimeLabel"
	timeLbl.Size = UDim2.new(0.25, 0, 0.55, 0)
	timeLbl.Position = UDim2.new(1, -55, 0, 2)
	timeLbl.BackgroundTransparency = 1; timeLbl.Text = "0:30"
	timeLbl.TextColor3 = color; timeLbl.TextScaled = true
	timeLbl.Font = Enum.Font.FredokaOne; timeLbl.TextXAlignment = Enum.TextXAlignment.Right
	timeLbl.ZIndex = 62; timeLbl.Parent = slot

	local stackLbl = Instance.new("TextLabel")
	stackLbl.Name = "StackLabel"
	stackLbl.Size = UDim2.new(0.5, 0, 0.35, 0)
	stackLbl.Position = UDim2.new(0, 45, 0.5, 3)
	stackLbl.BackgroundTransparency = 1; stackLbl.Text = ""
	stackLbl.TextColor3 = T.subText; stackLbl.TextScaled = true
	stackLbl.Font = Enum.Font.GothamMedium; stackLbl.TextXAlignment = Enum.TextXAlignment.Left
	stackLbl.ZIndex = 62; stackLbl.Parent = slot

	stripSlots[boostId] = { slot = slot, timeLbl = timeLbl, stackLbl = stackLbl }
end

-- ─────────────────────────────────────────────────────────────────────────────
-- ✨ BOOST MENU BUTTON (Moved to Left Sidebar)
-- ─────────────────────────────────────────────────────────────────────────────
local BoostsBtn = Instance.new("ImageButton")
BoostsBtn.Name = "BoostsButton"
BoostsBtn.BackgroundColor3 = T.buttonPrimary; BoostsBtn.BorderSizePixel = 0
BoostsBtn.AutoButtonColor = false
BoostsBtn.ZIndex = 10

local Faded2 = mainHUD:FindFirstChild("Faded2")
if Faded2 then
	BoostsBtn.Parent = Faded2
	BoostsBtn.Size = UDim2.new(0.85, 0, 0.85, 0)
	local aspect = Instance.new("UIAspectRatioConstraint", BoostsBtn)
	aspect.AspectRatio = 1.0

	-- Keep layout clean in the sidebar
	local layout = Faded2:FindFirstChildOfClass("UIListLayout")
	if not layout then
		layout = Instance.new("UIListLayout", Faded2)
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.Padding = UDim.new(0, 15)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
	end
	BoostsBtn.LayoutOrder = 3 -- Stacks beautifully under the Shop button!
else
	BoostsBtn.Size = UDim2.new(0, 60, 0, 60)
	BoostsBtn.AnchorPoint = Vector2.new(1, 1) 
	BoostsBtn.Position = UDim2.new(0.98, 0, 0.77, 0) 
	BoostsBtn.Parent = mainHUD
end

BoostsBtn:SetAttribute("TutorialTarget", "BoostsButton")
Instance.new("UICorner", BoostsBtn).CornerRadius = UDim.new(0.5, 0)

local bbStroke = Instance.new("UIStroke", BoostsBtn)
bbStroke.Color = T.accentPurple; bbStroke.Thickness = 2

local boostIcon = Instance.new("ImageLabel", BoostsBtn)
boostIcon.Size = UDim2.new(0.6, 0, 0.6, 0); boostIcon.Position = UDim2.new(0.2, 0, 0.2, 0)
boostIcon.BackgroundTransparency = 1; boostIcon.ScaleType = Enum.ScaleType.Fit
boostIcon.Image = "rbxassetid://14916846070" 

CollectionService:AddTag(BoostsBtn, "Tutorial_BoostMenuBtn")

---------------------------------------------------------------
-- ✨ BOOST SHOP PANEL (Left Slide-out format)
---------------------------------------------------------------
local ShopPanel = Instance.new("Frame")
ShopPanel.Name = "BoostShopPanel"
ShopPanel.Size = UDim2.new(0.85, 0, 0.8, 0) 
ShopPanel.AnchorPoint = Vector2.new(0, 0.5) 
ShopPanel.Position = UDim2.new(0, -500, 0.5, 0) -- Hidden to the left
ShopPanel.BackgroundColor3 = T.panelBG; ShopPanel.BorderSizePixel = 0
ShopPanel.Visible = false; ShopPanel.ZIndex = 40
ShopPanel.ClipsDescendants = true
ShopPanel.Parent = mainHUD
CollectionService:AddTag(ShopPanel, "Tutorial_BoostShopPanel")
Instance.new("UICorner", ShopPanel).CornerRadius = UDim.new(0, 14)

local sizeConstraint = Instance.new("UISizeConstraint")
sizeConstraint.MaxSize = Vector2.new(380, 520)
sizeConstraint.Parent = ShopPanel

local shopStroke = Instance.new("UIStroke")
shopStroke.Color = T.accentPurple; shopStroke.Thickness = 2; shopStroke.Parent = ShopPanel

local ShopHeader = Instance.new("Frame")
ShopHeader.Size = UDim2.new(1, 0, 0, 46)
ShopHeader.BackgroundColor3 = T.headerBG; ShopHeader.BorderSizePixel = 0
ShopHeader.ZIndex = 41; ShopHeader.Parent = ShopPanel
Instance.new("UICorner", ShopHeader).CornerRadius = UDim.new(0, 14)

local ShopTitle = Instance.new("TextLabel")
ShopTitle.Size = UDim2.new(1, -50, 1, 0); ShopTitle.Position = UDim2.new(0, 14, 0, 0)
ShopTitle.BackgroundTransparency = 1; ShopTitle.Text = "BOOST SHOP"
ShopTitle.TextColor3 = T.headerText; ShopTitle.TextScaled = true
ShopTitle.Font = Enum.Font.FredokaOne; ShopTitle.TextXAlignment = Enum.TextXAlignment.Left
ShopTitle.ZIndex = 42; ShopTitle.Parent = ShopHeader

local ShopClose = Instance.new("TextButton")
ShopClose.Size = UDim2.new(0, 32, 0, 32); ShopClose.Position = UDim2.new(1, -40, 0.5, -16)
ShopClose.BackgroundColor3 = T.buttonRed; ShopClose.BorderSizePixel = 0
ShopClose.Text = "X"; ShopClose.TextColor3 = T.bodyText
ShopClose.TextScaled = true; ShopClose.Font = Enum.Font.FredokaOne
ShopClose.ZIndex = 9999; ShopClose.Parent = ShopHeader
CollectionService:AddTag(ShopClose, "Tutorial_BoostShopClose")
Instance.new("UICorner", ShopClose).CornerRadius = UDim.new(0, 6)

local ScrollContainer = Instance.new("ScrollingFrame")
ScrollContainer.Name = "ScrollContainer"
ScrollContainer.Size = UDim2.new(1, 0, 1, -56) 
ScrollContainer.Position = UDim2.new(0, 0, 0, 56)
ScrollContainer.BackgroundTransparency = 1
ScrollContainer.BorderSizePixel = 0
ScrollContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
ScrollContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y
ScrollContainer.ScrollBarThickness = 6
ScrollContainer.Parent = ShopPanel

local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 10)
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
listLayout.Parent = ScrollContainer

local topPadding = Instance.new("UIPadding")
topPadding.PaddingTop = UDim.new(0, 5)
topPadding.PaddingBottom = UDim.new(0, 15)
topPadding.Parent = ScrollContainer

local function AddButtonJuice(btn)
	local scale = btn:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = btn
	end

	btn.MouseEnter:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Sine), {Scale = 1.05}):Play() end)
	btn.MouseLeave:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Sine), {Scale = 1}):Play() end)
	btn.MouseButton1Down:Connect(function() TweenService:Create(scale, TweenInfo.new(0.1, Enum.EasingStyle.Sine), {Scale = 0.95}):Play() end)
	btn.MouseButton1Up:Connect(function() TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), {Scale = 1.05}):Play() end)
end

AddButtonJuice(BoostsBtn)
AddButtonJuice(ShopClose)

local cardRefs = {}

local function BuildCards()
	for i, boostId in ipairs(BoostConfig.ShopOrder) do
		local cfg = BoostConfig.Get(boostId)
		if not cfg then continue end
		local color = cfg.color

		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, -20, 0, 105) 
		card.BackgroundColor3 = T.cardBG; card.BorderSizePixel = 0
		card.ZIndex = 41; card.Parent = ScrollContainer
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)

		local cs = Instance.new("UIStroke"); cs.Color = color; cs.Thickness = 1.5; cs.Parent = card

		local iconFrame = Instance.new("Frame", card)
		iconFrame.Size = UDim2.new(0, 48, 0, 48)
		iconFrame.Position = UDim2.new(0, 10, 0.5, -24)
		iconFrame.BackgroundColor3 = color
		iconFrame.BackgroundTransparency = 0.85
		Instance.new("UICorner", iconFrame).CornerRadius = UDim.new(0, 10)

		local iconLbl = Instance.new("ImageLabel", iconFrame)
		iconLbl.Size = UDim2.new(0.7, 0, 0.7, 0); iconLbl.Position = UDim2.new(0.15, 0, 0.15, 0)
		iconLbl.BackgroundTransparency = 1; iconLbl.Image = cfg.icon or ""
		iconLbl.ScaleType = Enum.ScaleType.Fit; iconLbl.ZIndex = 42

		local nameLbl = Instance.new("TextLabel")
		nameLbl.Size = UDim2.new(0.5, 0, 0, 22); nameLbl.Position = UDim2.new(0, 68, 0, 10)
		nameLbl.BackgroundTransparency = 1; nameLbl.Text = string.upper(cfg.displayName or boostId)
		nameLbl.TextColor3 = color; nameLbl.TextScaled = true
		nameLbl.Font = Enum.Font.FredokaOne; nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		nameLbl.ZIndex = 42; nameLbl.Parent = card

		local shadow = nameLbl:Clone()
		shadow.Name = "Shadow"; shadow.ZIndex = 41; shadow.TextColor3 = Color3.fromRGB(0,0,0)
		shadow.TextTransparency = 0.6; shadow.Position = nameLbl.Position + UDim2.new(0,2,0,2)
		shadow.Parent = card

		local descLbl = Instance.new("TextLabel")
		descLbl.Size = UDim2.new(0.65, 0, 0, 36); descLbl.Position = UDim2.new(0, 68, 0, 35)
		descLbl.BackgroundTransparency = 1; descLbl.Text = cfg.description or ""
		descLbl.TextColor3 = T.subText; descLbl.TextScaled = true; descLbl.TextWrapped = true
		descLbl.Font = Enum.Font.GothamMedium; descLbl.TextXAlignment = Enum.TextXAlignment.Left; descLbl.TextYAlignment = Enum.TextYAlignment.Top
		descLbl.ZIndex = 42; descLbl.Parent = card

		local durLbl = Instance.new("TextLabel")
		durLbl.Size = UDim2.new(0.65, 0, 0, 14); durLbl.Position = UDim2.new(0, 68, 0, 75)
		durLbl.BackgroundTransparency = 1; durLbl.Text = cfg.duration == 0 and "Instant Use" or (FormatTime(cfg.duration) .. " duration")
		durLbl.TextColor3 = Color3.fromRGB(130, 135, 160); durLbl.TextScaled = true
		durLbl.Font = Enum.Font.GothamMedium; durLbl.TextXAlignment = Enum.TextXAlignment.Left
		durLbl.ZIndex = 42; durLbl.Parent = card

		local buyBtn = Instance.new("TextButton")
		buyBtn.Size = UDim2.new(0, 90, 0, 40); buyBtn.Position = UDim2.new(1, -100, 0, 10)
		buyBtn.BorderSizePixel = 0; buyBtn.TextScaled = true; buyBtn.Font = Enum.Font.FredokaOne
		buyBtn.ZIndex = 42; buyBtn.Parent = card
		Instance.new("UICorner", buyBtn).CornerRadius = UDim.new(0, 8)
		CollectionService:AddTag(buyBtn, "Tutorial_BuyBoost_" .. boostId)
		AddButtonJuice(buyBtn)

		local actBtn = Instance.new("TextButton")
		actBtn.Size = UDim2.new(0, 90, 0, 40); actBtn.Position = UDim2.new(1, -100, 0, 55)
		actBtn.BorderSizePixel = 0; actBtn.TextScaled = true; actBtn.Font = Enum.Font.FredokaOne
		actBtn.ZIndex = 42; actBtn.Parent = card
		Instance.new("UICorner", actBtn).CornerRadius = UDim.new(0, 8)
		CollectionService:AddTag(actBtn, "Tutorial_UseBoost_" .. boostId)
		AddButtonJuice(actBtn)

		local invBadge = Instance.new("TextLabel")
		invBadge.Size = UDim2.new(0, 28, 0, 20); invBadge.Position = UDim2.new(0, 10, 1, -30)
		invBadge.BackgroundColor3 = Color3.fromRGB(20, 20, 30); invBadge.BorderSizePixel = 0
		invBadge.Text = "x0"; invBadge.TextColor3 = T.bodyText
		invBadge.TextScaled = true; invBadge.Font = Enum.Font.FredokaOne
		invBadge.ZIndex = 43; invBadge.Parent = card
		Instance.new("UICorner", invBadge).CornerRadius = UDim.new(0, 6)
		local invStroke = Instance.new("UIStroke", invBadge)
		invStroke.Color = T.panelStroke; invStroke.Thickness = 1.5

		cardRefs[boostId] = { card=card, cs=cs, buyBtn=buyBtn, actBtn=actBtn, invBadge=invBadge, descLbl=descLbl, color=color }

		buyBtn.MouseButton1Down:Connect(function() 
			if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_BuyBoost_" .. boostId) then return end
			BuyBoost:FireServer(boostId) 
			if type(shared.TutorialRecordBoostBought) == "function" then shared.TutorialRecordBoostBought(boostId) end
			if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
		end)

		actBtn.MouseButton1Down:Connect(function()
			if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_UseBoost_" .. boostId) then return end
			local state = boostState[boostId]
			if not state or (state.inventoryCount or 0) <= 0 then return end
			ActivateBoost:FireServer(boostId)
			if type(shared.TutorialRecordBoostUsed) == "function" then shared.TutorialRecordBoostUsed(boostId) end
			if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
		end)
	end
end

BuildCards()
local latestStats = {}

local function RefreshCards()
	for boostId, refs in pairs(cardRefs) do
		local cfg         = BoostConfig.Get(boostId)
		local state       = boostState[boostId]
		local color       = refs.color
		local invCount    = state and (state.inventoryCount or 0) or 0
		local activeCount = state and (state.activeCount or 0) or 0
		local cost        = cfg and cfg.cost or 0
		local canAfford   = liveGold >= cost
		local atCap       = activeCount >= (cfg and cfg.maxStack or 1)

		local isUnlocked, lockReason = AchievementConfig.IsBoostUnlocked(boostId, latestStats)

		refs.invBadge.Text       = "x" .. invCount
		refs.invBadge.TextColor3 = invCount > 0 and T.accentGold or T.subText

		if not isUnlocked then
			refs.buyBtn.Text             = "LOCKED"
			refs.buyBtn.BackgroundColor3 = T.buttonRed
			refs.buyBtn.TextColor3       = T.bodyText

			refs.actBtn.Text             = "Locked"
			refs.actBtn.BackgroundColor3 = T.buttonDisabled
			refs.actBtn.TextColor3       = T.subText

			refs.descLbl.Text = "Requires: " .. lockReason
			refs.descLbl.TextColor3 = T.buttonRed
		else
			refs.descLbl.Text = cfg.description or ""
			refs.descLbl.TextColor3 = T.subText

			refs.buyBtn.Text             = cost .. " ⭐"
			refs.buyBtn.TextColor3       = T.bodyText
			refs.buyBtn.BackgroundColor3 = canAfford and T.buttonGreen or T.buttonDisabled

			if invCount <= 0 then
				refs.actBtn.Text             = "No Stock"
				refs.actBtn.BackgroundColor3 = T.buttonDisabled
				refs.actBtn.TextColor3       = T.subText
			elseif atCap then
				refs.actBtn.Text             = "MAX (" .. FormatTime(state and state.activeTimes and state.activeTimes[1] or 0) .. ")"
				refs.actBtn.BackgroundColor3 = Color3.fromRGB(40, 80, 50)
				refs.actBtn.TextColor3       = color
			else
				refs.actBtn.Text             = "Activate"
				refs.actBtn.BackgroundColor3 = color
				refs.actBtn.TextColor3       = T.bodyText
			end
		end
	end
end

local function RefreshStrip()
	local anyActive = false
	for _, boostId in ipairs(BoostConfig.ShopOrder) do
		local state = boostState[boostId]
		local refs  = stripSlots[boostId]
		if not refs then continue end
		if state and (state.activeCount or 0) > 0 then
			anyActive = true; refs.slot.Visible = true
			local minTime = math.huge
			for _, t in ipairs(state.activeTimes or {}) do if t < minTime then minTime = t end end
			refs.timeLbl.Text  = FormatTime(minTime)
			refs.stackLbl.Text = state.activeCount > 1 and ("x" .. state.activeCount) or ""
		else
			refs.slot.Visible = false
		end
	end
	BoostStrip.Visible = anyActive
end

local function OpenPanel()
	panelOpen = true; ShopPanel.Visible = true
	RefreshCards()

	-- ✨ Slide in from the left to dock neatly next to the sidebar
	TweenService:Create(ShopPanel, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0, 90, 0.5, 0)
	}):Play()
	UITheme.SetMenuVisible(true)
end

local function ClosePanel()
	panelOpen = false
	PlayUI(SoundConfig.UIClose)

	-- ✨ Slide back out off the screen
	local tween = TweenService:Create(ShopPanel, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = UDim2.new(0, -500, 0.5, 0)
	})
	tween:Play()
	tween.Completed:Once(function() if not panelOpen then ShopPanel.Visible = false end end)

	UITheme.SetMenuVisible(false)
end

BoostsBtn.MouseButton1Down:Connect(function() 
	if panelOpen then
		if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_CloseBoostShop") then return end
		ClosePanel()
	else
		if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_OpenBoostShop") then return end
		OpenPanel()
	end 
	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
end)

ShopClose.MouseButton1Down:Connect(function()
	if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_CloseBoostShop") then return end
	ClosePanel()
	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
end)

BoostUpdated.OnClientEvent:Connect(function(state)
	if state._goldenAuras ~= nil then liveGold = state._goldenAuras; state._goldenAuras = nil end
	boostState = state; RefreshStrip()
	if panelOpen then RefreshCards() end
end)

UpdateHUDBridge:Connect(function(stats)
	for key, value in pairs(stats) do
		latestStats[key] = value
	end
	if stats.goldenAuras ~= nil then liveGold = stats.goldenAuras end
	if stats.boostInventory then
		for boostId, count in pairs(stats.boostInventory) do
			if boostState[boostId] then boostState[boostId].inventoryCount = count end
		end
	end
	if panelOpen then RefreshCards() end
end)

RunService.RenderStepped:Connect(function(dt)
	local anyActive = false
	for _, boostId in ipairs(BoostConfig.ShopOrder) do
		local state = boostState[boostId]
		if state and state.activeTimes and #state.activeTimes > 0 then
			anyActive = true
			local clean = {}
			for _, t in ipairs(state.activeTimes) do
				local newT = math.max(0, t - dt)
				if newT > 0 then table.insert(clean, newT) end
			end
			state.activeTimes = clean; state.activeCount = #clean
			local refs = stripSlots[boostId]
			if refs then
				if #clean > 0 then
					local minTime = math.huge
					for _, t in ipairs(clean) do if t < minTime then minTime = t end end
					refs.timeLbl.Text  = FormatTime(minTime)
					refs.stackLbl.Text = #clean > 1 and ("x" .. #clean) or ""
					refs.slot.Visible  = true
				else
					refs.slot.Visible = false
				end
			end
		end
	end
	BoostStrip.Visible = anyActive
end)

local shopShine = nil
local function RefreshLook()
	UITheme.Apply(ShopPanel, "Panel")
	UITheme.Apply(ShopHeader, "TitleBar")
	if not shopShine then
		shopShine = UITheme.ApplyShine(ShopPanel)
	end
	for _, card in ipairs(ScrollContainer:GetChildren()) do
		if card:IsA("Frame") then
			UITheme.Apply(card, "ShopCard")
		end
	end
end

task.wait(1) 
RefreshLook()

local forceClose = ReplicatedStorage:FindFirstChild("ForceCloseUI") or Instance.new("BindableEvent")
forceClose.Name = "ForceCloseUI"
forceClose.Parent = ReplicatedStorage
forceClose.Event:Connect(function()
	if panelOpen then ClosePanel() end
end)
