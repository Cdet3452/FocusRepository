local DataStoreService  = game:GetService("DataStoreService")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDB       = DataStoreService:GetDataStore("PlayerData_v1")
local AdminConfig    = require(ReplicatedStorage.Modules.AdminConfig)	
local UpgradeConfig  = require(ReplicatedStorage.Modules.UpgradeConfig)
local MutationConfig = require(ReplicatedStorage.Modules.MutationConfig)
local EpicUpgradeConfig = require(ReplicatedStorage.Modules:WaitForChild("EpicUpgradeConfig"))

local BridgeNet2      = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))
local UpdateHUDBridge = BridgeNet2.ServerBridge("UpdateHUD")
local BankActionBridge = BridgeNet2.ServerBridge("BankAction")

local AreaChanged = ReplicatedStorage.RemoteEvents:WaitForChild("AreaChanged")

local SAVE_COOLDOWN = 7

local function DefaultData()
	return {
		currency      = 0,
		totalEarned   = 0,
		soulAuras     = 0,
		prestigeCount = 0,
		pendingAuras        = 0,
		upgrades = { dropRate=0, blockValue=0, habitatCapacity=0, autoShipper=0, mutationSpeed=0, mutationTierChance=0, passiveTickSpeed=0, hatcheryCapacity=0 },
		totalCubesProduced    = 0,
		totalPlatformsShipped = 0,
		totalLegendaryCubes   = 0,
		totalMythicCubes      = 0,
		totalDivineCubes      = 0,
		totalCelestialCubes   = 0,
		totalCosmicCubes      = 0,
		totalOmniCubes        = 0,
		settings = { sfxEnabled=true, musicEnabled=true },
		farmEvaluation = 0,
		currentArea    = 1,
		unlockedAreas  = { 1 },
		goldenAuras = AdminConfig.GoldenAuraStart or 10,
		piggyBank = 0,
		highestPiggyBank = 0,
		piggyBankBroken = 0,
		aurmers = 0,
		inSpecialArea = false,
		boostInventory = { AuraRush=0, SpawnBoost=0, SoulBoost=0 },
		hasPrestigedThisArea = false,
		epicUpgrades         = {},
		tutorialProgress     = {},
		tutorialComplete     = false,
		claimedMail          = {},
		unlockedMail         = {},
		claimedBadges        = {},
		claimedChallenges    = {},
		claimedAuras         = {},
		discoveredTiers      = {}
	}
end

local function DefaultRuntime()
	return {
		cubes              = {},

		-- O(1) Amortized Queue System
		cubeQueue          = {},
		cubeQueueHead      = 1,
		cubeQueueTail      = 0,

		cubeCount          = 0,
		storedCubeCount    = 0,

		activeMutatedValue = 0,

		nextCubeId         = 1,
		totalMutatedValue  = 0,
		lastActiveTime     = tick(),
		sessionStart       = tick(),
	}
end

local PlayerData    = {}
local PlayerRuntime = {}
local lastSaveTick  = {}
local pendingSave   = {}

local function DeepMerge(saved, defaults)
	for key, defaultValue in pairs(defaults) do
		if saved[key] == nil then
			saved[key] = defaultValue
		elseif type(defaultValue) == "table" and type(saved[key]) == "table" and not getmetatable(saved[key]) then
			if defaultValue[1] == nil then DeepMerge(saved[key], defaultValue) end
		end
	end
end

local function EnsureUnlockedAreas(data)
	if type(data.unlockedAreas) ~= "table" then data.unlockedAreas = { 1 } end
	local has1, hasCurrent = false, false
	for _, v in ipairs(data.unlockedAreas) do
		if v == 1 then has1 = true end
		if v == data.currentArea then hasCurrent = true end
	end
	if not has1 then table.insert(data.unlockedAreas, 1) end
	if not hasCurrent and data.currentArea ~= 1 then table.insert(data.unlockedAreas, data.currentArea) end
end

local function SaveData(player)
	local uid  = player.UserId
	local data = PlayerData[uid]
	if not data then return end
	local now, last = tick(), lastSaveTick[uid] or 0
	if now - last >= SAVE_COOLDOWN then
		lastSaveTick[uid] = now
		pcall(function() PlayerDB:SetAsync("Player_" .. uid, data) end)
	else
		if not pendingSave[uid] then
			pendingSave[uid] = true
			task.delay(SAVE_COOLDOWN - (now - last) + 0.5, function()
				pendingSave[uid] = nil
				if player and player.Parent and PlayerData[uid] then
					pcall(function() PlayerDB:SetAsync("Player_" .. uid, PlayerData[uid]) end)
					lastSaveTick[uid] = tick()
				end
			end)
		end
	end
end

local function LoadData(player)
	local key      = "Player_" .. player.UserId
	local ok, data = pcall(function() return PlayerDB:GetAsync(key) end)

	if ok and data then
		DeepMerge(data, DefaultData())
		PlayerData[player.UserId] = data
	else
		PlayerData[player.UserId] = DefaultData()
	end

	local d = PlayerData[player.UserId]
	EnsureUnlockedAreas(d)
	PlayerRuntime[player.UserId] = DefaultRuntime()

	if AdminConfig.WipeMoneyOnLoad then
		d.currency=0; d.totalEarned=0; d.pendingAuras=0; d.pendingPayout=0; d.pendingBonusPayout=0; d.lastPayout=0
		for k in pairs(d.upgrades) do d.upgrades[k] = 0 end
		d.totalCubesProduced=0; d.totalPlatformsShipped=0; d.totalLegendaryCubes=0
		d.totalMythicCubes=0; d.totalDivineCubes=0; d.totalCelestialCubes=0; d.totalCosmicCubes=0; d.totalOmniCubes=0
		d.piggyBank=0; d.highestPiggyBank=0; d.piggyBankBroken=0; d.farmEvaluation=0; d.goldenAuras=AdminConfig.GoldenAuraStart or 10
		d.aurmers=0; d.inSpecialArea=false
		d.boostInventory={ AuraRush=0, SpawnBoost=0, SoulBoost=0 }
		d.hasPrestigedThisArea=false; d.claimedMail={}; d.tutorialProgress={}; d.tutorialComplete=false
	end

	if AdminConfig.WipePrestigeOnLoad then d.soulAuras=0; d.prestigeCount=0; d.hasPrestigedThisArea=false end
	if AdminConfig.WipeAreaOnLoad then d.currentArea=1; d.farmEvaluation=0; d.unlockedAreas={ 1 }; d.hasPrestigedThisArea=false end
	if AdminConfig.WipeEpicOnLoad then d.goldenAuras = AdminConfig.GoldenAuraStart or 0; d.epicUpgrades = {} end

	if AdminConfig.WipeAchievementsOnLoad then 
		d.totalCubesProduced=0; d.totalPlatformsShipped=0; d.totalLegendaryCubes=0
		d.totalMythicCubes=0; d.totalDivineCubes=0; d.totalCelestialCubes=0; d.totalCosmicCubes=0; d.totalOmniCubes=0
		d.claimedBadges={}; d.claimedChallenges={}; d.claimedAuras={}; d.discoveredTiers={}
	end

	if not d.epicUpgrades     then d.epicUpgrades     = {} end
	if not d.tutorialProgress then d.tutorialProgress = {} end
	if d.tutorialComplete == nil then d.tutorialComplete = false end
	if not d.claimedMail      then d.claimedMail      = {} end
	if not d.unlockedMail     then d.unlockedMail     = {} end
	if d.hasPrestigedThisArea == nil then d.hasPrestigedThisArea = false end

	d.inSpecialArea = false

	task.wait(1)
	if not player or not player.Parent then return end

	local upgradesState = {}
	for upgradeId, level in pairs(d.upgrades or {}) do upgradesState[upgradeId] = { level = level } end

	local epicUpgradesState = {}
	for upgradeId, level in pairs(d.epicUpgrades or {}) do epicUpgradesState[upgradeId] = { level = level } end

	UpdateHUDBridge:Fire(player, {
		currency=d.currency, pendingAuras=0, 
		habitatCapacity = UpgradeConfig.GetHabitatCapacity(d), 
		shipCapacity = UpgradeConfig.GetShippingCapacity(d) or (AdminConfig.PlatformCapacity or 5), rate=0, 
		passiveInterval = UpgradeConfig.GetPassiveInterval(d),
		totalEarned=d.totalEarned or 0, soulAuras=d.soulAuras or 0, farmEvaluation=d.farmEvaluation or 0,
		goldenAuras=d.goldenAuras or 0, 
		piggyBank=d.piggyBank or 0, piggyBankBroken=d.piggyBankBroken or 0, highestPiggyBank=d.highestPiggyBank or 0,
		aurmers=d.aurmers or 0, inSpecialArea=d.inSpecialArea or false,
		boostInventory=d.boostInventory or {}, settings=d.settings or {},
		prestigeCount=d.prestigeCount or 0, hasPrestigedThisArea=d.hasPrestigedThisArea or false,
		tutorialProgress=d.tutorialProgress or {}, tutorialComplete=d.tutorialComplete or false,
		epicUpgrades=epicUpgradesState, totalCubesProduced=d.totalCubesProduced or 0,
		currentArea=d.currentArea or 1, upgrades=upgradesState,
	})

	player:SetAttribute("LivePiggyBank", d.piggyBank or 0)
	player:SetAttribute("HighestPiggyBank", d.highestPiggyBank or 0)
	player:SetAttribute("PiggyBankBroken", d.piggyBankBroken or 0)

	task.delay(0.5, function()
		if not player or not player.Parent then return end

		local resetState = {}
		for tierNum, tierData in ipairs(UpgradeConfig.Tiers) do
			for upgradeId, cfg in pairs(tierData.upgrades) do
				local lv = d.upgrades[upgradeId] or 0
				local maxed = lv >= cfg.maxLevel
				resetState[upgradeId] = { level=lv, maxLevel=cfg.maxLevel, cost=maxed and 0 or UpgradeConfig.CalculateCost(upgradeId, lv, d), maxed=maxed }
			end
		end
		local UpgradeUpdated = ReplicatedStorage.RemoteEvents:FindFirstChild("UpgradeUpdated")
		if UpgradeUpdated then UpgradeUpdated:FireClient(player, { type="fullState", upgrades=resetState, currency=d.currency }) end

		local epicResetState = {}
		for tierNum, tierData in ipairs(EpicUpgradeConfig.Tiers) do
			for upgradeId, cfg in pairs(tierData.upgrades) do
				local lv = d.epicUpgrades[upgradeId] or 0
				local maxed = lv >= cfg.maxLevel
				epicResetState[upgradeId] = { level=lv, maxLevel=cfg.maxLevel, cost=maxed and 0 or EpicUpgradeConfig.CalculateCost(upgradeId, lv), maxed=maxed }
			end
		end
		local EpicUpgradeUpdated = ReplicatedStorage.RemoteEvents:FindFirstChild("EpicUpgradeUpdated")
		if EpicUpgradeUpdated then EpicUpgradeUpdated:FireClient(player, { type="fullState", upgrades=epicResetState, goldenAuras=d.goldenAuras or 0 }) end
	end)
end

Players.PlayerAdded:Connect(LoadData)

Players.PlayerRemoving:Connect(function(player)
	SaveData(player)
	PlayerData[player.UserId] = nil
	PlayerRuntime[player.UserId] = nil
end)

local lastPeriodicSave = tick()
game:GetService("RunService").Heartbeat:Connect(function()
	if tick() - lastPeriodicSave >= 60 then
		lastPeriodicSave = tick()
		for _, p in ipairs(Players:GetPlayers()) do SaveData(p) end
	end
end)

task.spawn(function()
	local TutorialStepComplete = ReplicatedStorage.RemoteEvents:WaitForChild("TutorialStepComplete", 10)
	if not TutorialStepComplete then return end
	TutorialStepComplete.OnServerEvent:Connect(function(player, stepId)
		local uid  = player.UserId
		local data = PlayerData[uid]
		if not data then return end
		if not data.tutorialProgress then data.tutorialProgress = {} end
		if stepId == "tutorialComplete" then data.tutorialComplete = true
		elseif type(stepId) == "string" and #stepId < 100 then data.tutorialProgress[stepId] = true end
	end)
end)

local GameManager = {}

function GameManager.GetData(uid)    return PlayerData[uid]    end
function GameManager.GetRuntime(uid) return PlayerRuntime[uid] end
function GameManager.SavePlayer(p)   SaveData(p)               end

function GameManager.PerformPrestigeReset(player)
	local uid = player.UserId
	local runtime = PlayerRuntime[uid]
	if runtime then
		runtime.cubes = {}
		-- Reset O(1) Queue
		runtime.cubeQueue = {}
		runtime.cubeQueueHead = 1
		runtime.cubeQueueTail = 0

		runtime.cubeCount = 0
		runtime.activeMutatedValue = 0
		runtime.storedCubeCount = 0
		runtime.totalMutatedValue = 0
		runtime.lastActiveTime = tick()
		runtime.sessionStart = tick()
	end
	SaveData(player)
end

function GameManager.AddGoldenAuras(uid, amount)
	local data = PlayerData[uid]
	if not data then return 0 end

	local epicBonus = 0
	pcall(function()
		local EpicUpgradeManager = require(ReplicatedStorage.Modules:WaitForChild("EpicUpgradeManager"))
		epicBonus = EpicUpgradeManager.GetBonus(uid, "goldenAuraValue") or 0
	end)

	local finalAmount = math.floor(amount * (1 + epicBonus))
	data.goldenAuras = (data.goldenAuras or 0) + finalAmount

	local player = Players:GetPlayerByUserId(uid)
	if player then
		UpdateHUDBridge:Fire(player, { goldenAuras = data.goldenAuras })
	end

	return finalAmount
end

function GameManager.AddPiggyBank(uid, rawAmount)
	local BankFillEvent = game:GetService("ServerScriptService"):FindFirstChild("BankFillEvent")
	if BankFillEvent then
		BankFillEvent:Fire(uid, rawAmount)
	else
		warn("[GameManager] BankFillEvent not found! PiggyBank visual routing failed.")
	end
end

function GameManager.AddCube(uid, cubeRecord)
	local runtime = PlayerRuntime[uid]
	if not runtime then return nil end

	local id = runtime.nextCubeId
	runtime.nextCubeId += 1	
	runtime.cubes[id] = cubeRecord

	local val = MutationConfig.GetMutatedValue(cubeRecord)
	runtime.totalMutatedValue += val

	if not cubeRecord.isStored then
		runtime.activeMutatedValue += val
	else
		runtime.storedCubeCount += 1

		-- Append straight to the queue if spawned directly into storage
		runtime.cubeQueueTail += 1
		runtime.cubeQueue[runtime.cubeQueueTail] = id
	end

	runtime.cubeCount += 1
	return id
end

-- AFTER
function GameManager.MarkCubeStored(uid, cubeId)
	local runtime = PlayerRuntime[uid]
	local data    = PlayerData[uid]
	if not runtime or not data then return false end

	local cube = runtime.cubes[cubeId]
	if not cube or cube.isStored then return false end

	-- HARD CAP: never let storedCubeCount exceed current habitat capacity,
	-- even if this cube was already in-flight before the gate tripped.
	local capacity = UpgradeConfig.GetHabitatCapacity(data)
	if runtime.storedCubeCount >= capacity then
		return false
	end

	cube.isStored = true
	runtime.storedCubeCount += 1
	runtime.activeMutatedValue -= MutationConfig.GetMutatedValue(cube)

	runtime.cubeQueueTail += 1
	runtime.cubeQueue[runtime.cubeQueueTail] = cubeId

	return true
end

function GameManager.RemoveCube(uid, cubeId)
	local runtime = PlayerRuntime[uid]
	if not runtime or not runtime.cubes[cubeId] then return end
	local cube = runtime.cubes[cubeId]

	local val = MutationConfig.GetMutatedValue(cube)
	runtime.totalMutatedValue -= val

	if cube.isStored then
		runtime.storedCubeCount -= 1
	else
		runtime.activeMutatedValue -= val
	end

	-- O(1) Memory clear. CollectOldestCubes will just skip it.
	runtime.cubes[cubeId] = nil
	runtime.cubeCount -= 1
end

function GameManager.CollectOldestCubes(uid, count)
	local runtime = PlayerRuntime[uid]
	if not runtime then return {}, {} end

	local collected, collectedCubes = {}, {}
	local needed = count

	-- O(1) Amortized Iteration. We only iterate front values and discard them.
	while needed > 0 and runtime.cubeQueueHead <= runtime.cubeQueueTail do
		local cubeId = runtime.cubeQueue[runtime.cubeQueueHead]

		-- Clean up queue table memory behind us as we move the head forward
		runtime.cubeQueue[runtime.cubeQueueHead] = nil
		runtime.cubeQueueHead += 1

		local cube = runtime.cubes[cubeId]

		-- Verify it exists and is stored (avoids edge cases if it was somehow removed/smushed early)
		if cube and cube.isStored then
			table.insert(collected, cubeId)
			table.insert(collectedCubes, cube)

			-- Run removal logic to decrease totals/values properly
			GameManager.RemoveCube(uid, cubeId)

			needed -= 1
		end
	end

	-- If queue becomes entirely empty, reset indexes to prevent number overflow 
	-- (though it takes quintillions to overflow, standard practice)
	if runtime.cubeQueueHead > runtime.cubeQueueTail then
		runtime.cubeQueueHead = 1
		runtime.cubeQueueTail = 0
	end

	return collected, collectedCubes
end

game:BindToClose(function()
	print("[GameManager] Server shutting down. Forcing final save for all players...")
	for _, player in ipairs(Players:GetPlayers()) do SaveData(player) end
	task.wait(2)
end)

return GameManager

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
local EpicUpgradeConfig = require(ReplicatedStorage.Modules:WaitForChild("EpicUpgradeConfig"))

local HabitatFull    = ReplicatedStorage.RemoteEvents:WaitForChild("HabitatFull")

local BridgeNet2             = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))
local UpdateHUDBridge        = BridgeNet2.ServerBridge("UpdateHUD")
local ProduceAuraBridge      = BridgeNet2.ServerBridge("ProduceAura")
local AuraSpawnedBridge      = BridgeNet2.ServerBridge("AuraSpawned")
local UpdateHatcheryBridge   = BridgeNet2.ServerBridge("UpdateHatchery")
local CubeMutatedBatchBridge = BridgeNet2.ServerBridge("CubeMutatedBatch")
local CubeSmushedBridge      = BridgeNet2.ServerBridge("CubeSmushed")
local CubeStoredBridge       = BridgeNet2.ServerBridge("CubeStored")

local HABITAT_HOLDER = workspace:WaitForChild("HabitatHolder")

local function GetServerHabitatPos()
	local posPart = HABITAT_HOLDER:FindFirstChild("Position", true)
	if posPart and posPart:IsA("BasePart") then
		return posPart.Position
	end
	return HABITAT_HOLDER:GetPivot().Position
end

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
	if type(UpgradeConfig.GetHatcheryMax) == "function" then
		return UpgradeConfig.GetHatcheryMax(data)
	end
	return AdminConfig.HatcheryMax or 150
end

local function GetHabitatCapacity(data)
	if type(UpgradeConfig.GetHabitatCapacity) == "function" then
		return UpgradeConfig.GetHabitatCapacity(data)
	end
	return AdminConfig.BaseHabitatCapacity or 50
end

local function GetMutationSpeedMult(data)
	local cfg = UpgradeConfig.GetUpgradeConfig("mutationSpeed")
	return (cfg and cfg.apply) and cfg.apply(data) or 1
end

local function TrackTierSpawn(data, tierName)
	if tierName == "Legendary" then data.totalLegendaryCubes = (data.totalLegendaryCubes or 0) + 1
	elseif tierName == "Mythic" then data.totalMythicCubes = (data.totalMythicCubes or 0) + 1
	elseif tierName == "Divine" then data.totalDivineCubes = (data.totalDivineCubes or 0) + 1
	elseif tierName == "Celestial" then data.totalCelestialCubes = (data.totalCelestialCubes or 0) + 1
	elseif tierName == "Cosmic" then data.totalCosmicCubes = (data.totalCosmicCubes or 0) + 1
	elseif tierName == "Omni" then data.totalOmniCubes = (data.totalOmniCubes or 0) + 1
	end
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

			local hasInstaHatchery = BoostManager.IsActive(uid, "InstaHatchery")
			local refillMultiplier = BoostManager.GetHatcheryMultiplier(uid)

			if hasInstaHatchery then
				hatchery[uid] = hatchMax
			else
				if holdStart[uid] then
					hatchery[uid] = math.max(0, prev - AdminConfig.HatcheryDrainRate * 0.1)
				else
					hatchery[uid] = math.min(hatchMax, prev + (AdminConfig.HatcheryRefillRate * refillMultiplier * 0.1))
				end
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

	UpdateHUDBridge:Fire(player, {
		currency        = data.currency, 
		pendingAuras    = storedCount, 
		habitatCapacity = GetHabitatCapacity(data), 
		rate            = displayRate,
		passiveInterval = UpgradeConfig.GetPassiveInterval(data), 
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
		currentFireRate = GetEffectiveFireRate(uid),
		boostMultiplier = boostMult ,
		shipCapacity    = UpgradeConfig.GetShippingCapacity(data) or AdminConfig.PlatformCapacity,
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

						local auraKey = currentArea .. "_" .. newTier.name
						if not data.discoveredTiers then data.discoveredTiers = {} end
						if not data.discoveredTiers[auraKey] then
							data.discoveredTiers[auraKey] = true
							GameManager.SavePlayer(player)
							UpdateHUDBridge:Fire(player, { discoveredTiers = data.discoveredTiers })
						end

						table.insert(mutationBatch, { 
							cubeId = cubeId, mutationType = "tierUpgrade",
							newColor = newTier.color, newGlow = newTier.glow, 
							tierName = newTier.name, currentArea = currentArea
						})

						TrackTierSpawn(data, newTier.name)
					else break end
				end

				if mutated then
					local newMutatedValue = MutationConfig.GetMutatedValue(cube)
					runtime.totalMutatedValue = (runtime.totalMutatedValue or 0) + (newMutatedValue - oldMutatedValue)
					if not cube.isStored then runtime.activeMutatedValue = (runtime.activeMutatedValue or 0) + (newMutatedValue - oldMutatedValue) end

					if #mutationBatch > 0 then
						for i = #mutationBatch, 1, -1 do
							if mutationBatch[i].cubeId == cubeId then
								mutationBatch[i].newValue = newMutatedValue
								break
							end
						end
					end
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

	local milestoneReduction = 0
	local clickMilestoneCfg = EpicUpgradeConfig.GetUpgradeConfig("epicClickMilestone")
	if clickMilestoneCfg and clickMilestoneCfg.apply then
		milestoneReduction = clickMilestoneCfg.apply(data)
	end

	local function GetMilestoneTime(index)
		if not AdminConfig.MilestoneData[index] then return 999999 end
		return math.max(0, AdminConfig.MilestoneData[index].time - milestoneReduction)
	end

	local effectiveTime = holdTime * playerMultSpeed
	local currentTier = 1

	for i = 1, playerMaxTier do
		if AdminConfig.MilestoneData[i] and effectiveTime >= GetMilestoneTime(i) then currentTier = i end
	end

	local nextTier = math.min(currentTier + 1, playerMaxTier)
	if currentTier == playerMaxTier then return AdminConfig.MilestoneData[currentTier].mult, AdminConfig.MilestoneData[currentTier].luck end

	local timePassed = effectiveTime - GetMilestoneTime(currentTier)
	local timeNeeded = GetMilestoneTime(nextTier) - GetMilestoneTime(currentTier)
	local ratio = timeNeeded > 0 and (timePassed / timeNeeded) or 1 

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
		if tier.name ~= "Common" then 
			chance = chance * (1 + (luckBonus or 0)) 
		end
		table.insert(adjusted, { tier=tier, chance=chance })
		total += chance
	end

	local r = math.random() * total
	local cum = 0
	local rolledTier = nil

	for _, e in ipairs(adjusted) do 
		cum += e.chance
		if not rolledTier and r <= cum then 
			rolledTier = e.tier 
		end 
	end

	rolledTier = rolledTier or tiers[1]
	return rolledTier
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

	local totalValueMultiplier = UpgradeConfig.GetTotalValueMultiplier(data)

	local prestigeMult    = PrestigeModule.GetMultiplier(data.soulAuras, data)
	local areaMult        = AreaRegistry.GetMultiplier(data.currentArea or 1)
	local boostValueMult  = BoostManager.GetValueMultiplier(uid)
	local _, weatherValueMult = WeatherManager.GetMultipliers(uid)

	local epicLuckCfg = EpicUpgradeConfig.GetUpgradeConfig("epicLuck")
	if epicLuckCfg and epicLuckCfg.apply then luckBonus = (luckBonus or 0) + epicLuckCfg.apply(data) end

	local calcMultFloat = totalValueMultiplier * prestigeMult * areaMult * boostValueMult * weatherValueMult
	local baseValue = math.floor(AdminConfig.BaseAuraValue * tier.multiplier * calcMultFloat)

	local godlyCritCfg = UpgradeConfig.GetUpgradeConfig("godlyCritChance")
	local critChance = (godlyCritCfg and godlyCritCfg.apply) and godlyCritCfg.apply(data) or 0
	local isGodlyCrit = false

	if critChance > 0 and (math.random() * 100) <= critChance then
		isGodlyCrit = true
		baseValue = baseValue * 500 
	end

	local totalValue = baseValue + math.floor(baseValue * (holdMult - 1))

	local spawnPos = GetServerHabitatPos() + Vector3.new(math.random(-3,3), 10, math.random(-3,3))  
	local activeAuraModel = workspace:FindFirstChild("AuraHolder") and workspace.AuraHolder:FindFirstChildWhichIsA("Model")
	if activeAuraModel then
		local spawnPoint = activeAuraModel:FindFirstChild("AuraSpawnPoint", true)
		if spawnPoint and spawnPoint:IsA("BasePart") then
			local size = spawnPoint.Size
			local randX = (math.random() - 0.5) * size.X
			local randZ = (math.random() - 0.5) * size.Z
			spawnPos = (spawnPoint.CFrame * CFrame.new(randX, 0, randZ)).Position
		end
	end

	local cubeRecord = { spawnTime=tick(), effectiveElapsed=0, lastUpgradeElapsed=0, baseValue=totalValue, tierIndex=tierIndex, tierName=tier.name, color=tier.color, glow=tier.glow, isStored=false, currentArea=currentArea }

	if AdminConfig.MutationInstantMax then
		local mb = MutationConfig.ValueBonuses[#MutationConfig.ValueBonuses]
		if mb then cubeRecord.effectiveElapsed = mb.time + 1 end
	end

	local cubeId = GameManager.AddCube(uid, cubeRecord)
	if not cubeId then return end

	local epicDoubleSpawn = EpicUpgradeConfig.GetUpgradeConfig("epicDoubleSpawn")
	if epicDoubleSpawn and epicDoubleSpawn.apply and epicDoubleSpawn.apply(data) > 0 then
		local doubleCubeId = GameManager.AddCube(uid, cubeRecord)
		if doubleCubeId then
			AuraSpawnedBridge:Fire(player, { cubeId=doubleCubeId, tier=tier.name, color=tier.color, glow=tier.glow, value=totalValue, spawnPos=spawnPos, currentArea = currentArea, isGodlyCrit = isGodlyCrit })
			data.totalCubesProduced = (data.totalCubesProduced or 0) + 1
			TrackTierSpawn(data, tier.name)
		end
	end

	local auraKey = currentArea .. "_" .. tier.name
	if not data.discoveredTiers then data.discoveredTiers = {} end
	if not data.discoveredTiers[auraKey] then
		data.discoveredTiers[auraKey] = true
		GameManager.SavePlayer(player)
		UpdateHUDBridge:Fire(player, { discoveredTiers = data.discoveredTiers })
	end

	data.totalCubesProduced = (data.totalCubesProduced or 0) + 1
	TrackTierSpawn(data, tier.name)

	runtime.lastActiveTime = tick()

	AuraSpawnedBridge:Fire(player, { cubeId=cubeId, tier=tier.name, color=tier.color, glow=tier.glow, value=totalValue, spawnPos=spawnPos, currentArea = currentArea, isGodlyCrit = isGodlyCrit })
end

ProduceAuraBridge:Connect(function(player, action)
	if player:GetAttribute("IsTransitioning") or player:GetAttribute("InSpecialArea") then
		if action == "start" then holdStart[player.UserId] = nil end
		return
	end

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

	if runtime.cubeCount >= capacity + 1000 then return end 

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

	local doubleSpawnCfg = UpgradeConfig.GetUpgradeConfig("doubleSpawnChance")
	local doubleChance = (doubleSpawnCfg and doubleSpawnCfg.apply) and doubleSpawnCfg.apply(data) or 0

	for i = 1, spawnCount do 
		SpawnAura(player, data, runtime, holdMult, luckBonus) 

		if doubleChance > 0 and math.random(1, 100) <= doubleChance then
			SpawnAura(player, data, runtime, holdMult, luckBonus) 
		end
	end

	SendHUDUpdate(player)
	UpdateHatcheryBridge:Fire(player, { current=hatchery[uid], max=GetHatcheryMax(data) })
end)

-- AFTER
CubeStoredBridge:Connect(function(player, cubeId)
	local uid = player.UserId
	local runtime = GameManager.GetRuntime(uid)
	local data = GameManager.GetData(uid)
	if runtime and runtime.cubes[cubeId] then
		local wasStored = GameManager.MarkCubeStored(uid, cubeId)
		SendHUDUpdate(player)

		local storedCount = runtime.storedCubeCount or 0
		if storedCount >= GetHabitatCapacity(data) then HabitatFull:FireClient(player) end

		if not wasStored then
			-- Habitat was already full when this in-flight cube landed — reject it
			-- instead of letting storedCubeCount silently overflow.
			CubeStoredBridge:Fire(player, { rejected = true, cubeId = cubeId })
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

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")

local AdminConfig = require(ReplicatedStorage.Modules.AdminConfig)
local UITheme = require(ReplicatedStorage.Modules.UITheme)
local AreaRegistry = require(ReplicatedStorage.Modules.AreaRegistry)
local NumberFormatter = require(ReplicatedStorage.Modules.NumberFormatter)

local PoolManager = require(ReplicatedStorage.Modules:WaitForChild("PoolManager"))

local BridgeNet2             = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))
local UpdateHUDBridge        = BridgeNet2.ClientBridge("UpdateHUD")
local ProduceAuraBridge      = BridgeNet2.ClientBridge("ProduceAura")
local AuraSpawnedBridge      = BridgeNet2.ClientBridge("AuraSpawned")
local UpdateHatcheryBridge   = BridgeNet2.ClientBridge("UpdateHatchery")
local CubeMutatedBatchBridge = BridgeNet2.ClientBridge("CubeMutatedBatch")
local CubeSmushedBridge      = BridgeNet2.ClientBridge("CubeSmushed")
local CubeStoredBridge       = BridgeNet2.ClientBridge("CubeStored")

local ForceStopHold = ReplicatedStorage.RemoteEvents:WaitForChild("ForceStopHold")
local HabitatFull = ReplicatedStorage.RemoteEvents:WaitForChild("HabitatFull")
local UpdateMultiplier = ReplicatedStorage:WaitForChild("UpdateMultiplier")
local HabitatFullEvent = ReplicatedStorage:WaitForChild("HabitatFullEvent")
local AreaChanged = ReplicatedStorage.RemoteEvents:WaitForChild("AreaChanged")
local PrestigeComplete = ReplicatedStorage.RemoteEvents:WaitForChild("PrestigeComplete")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local holding = false
local isAreaLoading = false 

local currentFireRate = AdminConfig.FireRate
local globalBoostMultiplier = 1
local currentPassiveInterval = AdminConfig.PassiveInterval

local holdStart = nil
local hatcheryEmpty = false
local habitatFull = false

local ClickButton = playerGui:WaitForChild("MainHUD"):WaitForChild("ClickButton")
local HatcheryBar = playerGui:WaitForChild("MainHUD"):WaitForChild("HatcheryBar")
local HatcheryFill = HatcheryBar:WaitForChild("Fill")
local HatcheryLabel = HatcheryBar:WaitForChild("Label")

local ModeToggle = playerGui:WaitForChild("MainHUD"):WaitForChild("ModeToggle")
local SendButton = playerGui:WaitForChild("MainHUD"):WaitForChild("SendButton")

CollectionService:AddTag(ClickButton, "Tutorial_ClickButton")
CollectionService:AddTag(ModeToggle, "Tutorial_ToggleShipBtn")
CollectionService:AddTag(SendButton, "Tutorial_SendShipBtn")

local clickScale = ClickButton:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", ClickButton)

local ringFrame = ClickButton:FindFirstChild("ActionRing")
if not ringFrame then
	ringFrame = Instance.new("Frame")
	ringFrame.Name = "ActionRing"
	ringFrame.Size = UDim2.new(1, 0, 1, 0)
	ringFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	ringFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	ringFrame.BackgroundTransparency = 1
	ringFrame.ZIndex = ClickButton.ZIndex - 1

	local btnCorner = ClickButton:FindFirstChildOfClass("UICorner")
	if btnCorner then btnCorner:Clone().Parent = ringFrame end
	ringFrame.Parent = ClickButton
end

local clickStroke = ringFrame:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke", ringFrame)
clickStroke.Color = Color3.fromRGB(255, 215, 0)
clickStroke.Thickness = 0
clickStroke.Transparency = 1

local basePos = ClickButton.Position
local tiltSide = 1

local Camera = workspace.CurrentCamera
local defaultFOV = 70
local lastMilestone = 1

local MilestoneData = AdminConfig.MilestoneData

local playerMultSpeed = 1.0
local playerMaxTier = 5

local lastTierIndex = 1

local latestPendingAuras = 0
local latestHabitatCapacity = 50 

-- NEW LIMITS: Cap physical cube limits and active tracker
local MAX_VISUAL_STORED = 1000
local activeCubes = {} -- Only contains cubes currently on the conveyor

local function FormatNumber(n)
	return NumberFormatter.Format(n)
end

local VFXFolder = ReplicatedStorage:FindFirstChild("VFX")
local cubeDataMap = {}

local LocalAuraReclaimedEvent = ReplicatedStorage:FindFirstChild("LocalAuraReclaimedEvent")
if not LocalAuraReclaimedEvent then
	LocalAuraReclaimedEvent = Instance.new("BindableEvent")
	LocalAuraReclaimedEvent.Name = "LocalAuraReclaimedEvent"
	LocalAuraReclaimedEvent.Parent = ReplicatedStorage
end

LocalAuraReclaimedEvent.Event:Connect(function(instance)
	local cid = instance:GetAttribute("CubeId")
	local data = cid and cubeDataMap[cid]
	if data then
		if data.ancestryConn then data.ancestryConn:Disconnect() end
		cubeDataMap[cid] = nil
		activeCubes[cid] = nil
	end
end)


local TierScale = {
	Common    = 1.0,
	Uncommon  = 1.15,
	Rare      = 1.3,
	Epic      = 1.5,
	Legendary = 1.75,
}

local function GetRootPart(instance)
	if instance:IsA("Model") then return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart") end
	return instance
end

local function ApplyHeavyPhysics(instance)
	local heavyProps = PhysicalProperties.new(100, 2.0, 0, 100, 100)
	if instance:IsA("BasePart") then instance.CustomPhysicalProperties = heavyProps
	elseif instance:IsA("Model") then
		for _, part in ipairs(instance:GetDescendants()) do
			if part:IsA("BasePart") then part.CustomPhysicalProperties = heavyProps end
		end
	end
end

local function SpawnAuraInstance(tierName, color, glow, position, currentArea)
	currentArea = currentArea or 1

	local auraModel = nil
	local isCustom = false
	local success = false
	local attempts = 0

	while not success and attempts < 3 do
		attempts += 1
		auraModel = PoolManager.GetAura(currentArea, tierName)

		if not auraModel then
			warn("PoolManager returned nil for Area: " .. tostring(currentArea) .. ", Tier: " .. tostring(tierName))
			return nil, false
		end

		success = pcall(function()
			auraModel.Parent = workspace
		end)

		if not success then
			warn("[ClickHandler] Pool returned a destroyed instance. Retrying...")
		end
	end

	if not success or not auraModel then 
		return nil, false 
	end

	if auraModel:IsA("Model") then
		auraModel:PivotTo(CFrame.new(position))
		local primary = auraModel.PrimaryPart or auraModel:FindFirstChildWhichIsA("BasePart")

		if primary then
			primary.Anchored = false
			primary.CanCollide = true
			primary.CanTouch = true
			primary.CanQuery = true
			primary.CollisionGroup = "Auras"
			primary.CastShadow = false
		end

		for _, desc in ipairs(auraModel:GetDescendants()) do
			if desc:IsA("BasePart") and desc ~= primary then
				desc.CanCollide = false
				desc.CanTouch = false
				desc.CanQuery = false
				desc.CastShadow = false
			end
		end

	elseif auraModel:IsA("BasePart") then
		auraModel.Position = position
		auraModel.Anchored = false
		auraModel.CanCollide = true
		auraModel.CanTouch = true
		auraModel.CanQuery = true
		auraModel.CollisionGroup = "Auras"
		auraModel.CastShadow = false
		auraModel.Color = color
		if glow then
			local light = auraModel:FindFirstChildOfClass("PointLight")
			if not light then light = Instance.new("PointLight"); light.Parent = auraModel end
			light.Brightness = 3; light.Range = 8; light.Color = color
		end
	end

	for _, desc in ipairs(auraModel:GetDescendants()) do
		if desc:IsA("ParticleEmitter") or desc:IsA("Trail") then
			desc.Enabled = true
		end
	end

	ApplyHeavyPhysics(auraModel)
	return auraModel, true
end

local function ScaleAura(instance, tierName, animated, fromTierName)
	local targetScale = TierScale[tierName] or 1.0
	local fromScale = fromTierName and (TierScale[fromTierName] or 1.0) or nil

	if instance:IsA("Model") then
		if animated then
			local scaleProxy = Instance.new("NumberValue")
			scaleProxy.Value = fromScale or 1.0
			local scaleTween = TweenService:Create(scaleProxy, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Value = targetScale })
			local conn
			conn = scaleProxy.Changed:Connect(function(val)
				if instance and instance.Parent then pcall(function() instance:ScaleTo(val) end) else conn:Disconnect() end
			end)
			scaleTween:Play()
			scaleTween.Completed:Connect(function() scaleProxy:Destroy(); if conn then conn:Disconnect() end end)
		else
			pcall(function() instance:ScaleTo(targetScale) end)
		end
	elseif instance:IsA("BasePart") then
		local baseSize = 1.5
		local targetSize = Vector3.new(1, 1, 1) * (baseSize * targetScale)
		if animated then
			if fromScale then instance.Size = Vector3.new(1, 1, 1) * (baseSize * fromScale) end
			TweenService:Create(instance, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = targetSize }):Play()
		else
			instance.Size = targetSize
		end
	end
end

local function PlayVFX(effectName, position, duration)
	if not VFXFolder then return end
	local template = VFXFolder:FindFirstChild(effectName)
	if not template then return end
	local vfx = template:Clone()

	if vfx:IsA("Model") then vfx:PivotTo(CFrame.new(position))
	elseif vfx:IsA("BasePart") then vfx.Position = position end

	for _, obj in ipairs(vfx:GetDescendants()) do
		if obj:IsA("BasePart") then
			obj.Anchored = true; obj.Transparency = 1; obj.CanCollide = false; obj.CastShadow = false
		end
	end
	if vfx:IsA("BasePart") then
		vfx.Anchored = true; vfx.Transparency = 1; vfx.CanCollide = false; vfx.CastShadow = false
	end
	vfx.Parent = workspace

	for _, emitter in ipairs(vfx:GetDescendants()) do
		if emitter:IsA("ParticleEmitter") then
			emitter.Enabled = true; emitter:Emit(emitter:GetAttribute("BurstCount") or 15)
		end
	end
	task.delay((duration or 1.0) * 0.5, function()
		if vfx and vfx.Parent then
			for _, emitter in ipairs(vfx:GetDescendants()) do
				if emitter:IsA("ParticleEmitter") then emitter.Enabled = false end
			end
		end
	end)
	Debris:AddItem(vfx, duration or 1.5)
end

local function GetCurrentMultiplier()
	if not holding or not holdStart then return 1.0, 1 end
	local holdTime = tick() - holdStart
	local effectiveTime = holdTime * playerMultSpeed

	local currentTier = 1; local nextTier = 1
	for i = 1, playerMaxTier do
		if effectiveTime >= MilestoneData[i].time then
			currentTier = i; nextTier = math.min(i + 1, playerMaxTier)
		end
	end

	if currentTier == playerMaxTier then return MilestoneData[currentTier].mult, currentTier end

	local timePassedInTier = effectiveTime - MilestoneData[currentTier].time
	local timeNeededForNext = MilestoneData[nextTier].time - MilestoneData[currentTier].time
	local progressRatio = timePassedInTier / timeNeededForNext

	local currentMult = MilestoneData[currentTier].mult
	local nextMult = MilestoneData[nextTier].mult
	local smoothMult = currentMult + ((nextMult - currentMult) * progressRatio)

	return smoothMult, currentTier
end

local function PlayMilestoneSound(soundValue)
	if not soundValue or soundValue == "" then return end
	local sfxToPlay = nil
	if string.find(soundValue, "rbxassetid://") then
		sfxToPlay = Instance.new("Sound"); sfxToPlay.SoundId = soundValue; sfxToPlay.Volume = 0.6
	else
		local sfxFolder = ReplicatedStorage:FindFirstChild("SFX") or ReplicatedStorage:FindFirstChild("Sounds")
		if sfxFolder then
			local foundSound = sfxFolder:FindFirstChild(soundValue)
			if foundSound then sfxToPlay = foundSound:Clone(); sfxToPlay.Volume = 0.6 end
		end
	end
	if sfxToPlay then
		sfxToPlay.Parent = game:GetService("SoundService"); sfxToPlay:Play()
		Debris:AddItem(sfxToPlay, sfxToPlay.TimeLength > 0 and sfxToPlay.TimeLength or 3)
	end
end

local function SpawnMilestonePopup(multFloor)
	local data = MilestoneData[multFloor]
	if not data then return end

	PlayMilestoneSound(data.sound)

	local pop = Instance.new("TextLabel")
	pop.Text = data.name .. " (" .. string.format("%.1f", data.mult) .. "x)"
	pop.Font = Enum.Font.FredokaOne; pop.TextScaled = true; pop.TextColor3 = data.color
	pop.BackgroundTransparency = 1; pop.AnchorPoint = Vector2.new(0.5, 0.5)

	pop.Position = UDim2.new(
		ClickButton.Position.X.Scale, ClickButton.Position.X.Offset, 
		ClickButton.Position.Y.Scale - 0.15, ClickButton.Position.Y.Offset
	)
	pop.Parent = ClickButton.Parent

	local stroke = Instance.new("UIStroke", pop); stroke.Thickness = 3; stroke.Color = Color3.fromRGB(0, 0, 0)
	pop.Size = UDim2.new(0.1, 0, 0.02, 0) 

	TweenService:Create(pop, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0.35, 0, 0.08, 0),
		Position = UDim2.new(pop.Position.X.Scale, pop.Position.X.Offset, ClickButton.Position.Y.Scale - 0.25, ClickButton.Position.Y.Offset)
	}):Play()

	task.delay(0.6, function()
		TweenService:Create(pop, TweenInfo.new(0.3), {TextTransparency = 1}):Play()
		TweenService:Create(stroke, TweenInfo.new(0.3), {Transparency = 1}):Play()
		task.delay(0.3, function() pop:Destroy() end)
	end)
end

local function UpdateButtonVisual()
	local col; local mult = 1; local currentTierIndex = 1
	if habitatFull then col = Color3.fromRGB(180, 60, 60)
	elseif not holding then col = Color3.fromRGB(255, 0, 0)
	else
		mult, currentTierIndex = GetCurrentMultiplier()
		col = MilestoneData[currentTierIndex].color
		UpdateMultiplier:Fire(mult)
	end

	local targetFOV = defaultFOV + (mult * 1.2)
	if not holding then targetFOV = defaultFOV end
	TweenService:Create(Camera, TweenInfo.new(0.3, Enum.EasingStyle.Sine), {FieldOfView = targetFOV}):Play()

	if holding then
		if currentTierIndex > lastTierIndex then
			if currentTierIndex > 1 then SpawnMilestonePopup(currentTierIndex) end
			lastTierIndex = currentTierIndex
		end
	else lastTierIndex = 1 end

	TweenService:Create(ClickButton, TweenInfo.new(0.2), { BackgroundColor3 = col }):Play()

	if holding and not habitatFull then
		tiltSide = tiltSide * -1 
		if mult >= 5.0 then 
			TweenService:Create(ClickButton, TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true), { Rotation = 8 * tiltSide }):Play()
			clickStroke.Thickness = 12; clickStroke.Transparency = 0
			TweenService:Create(clickStroke, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Thickness = 0, Transparency = 1}):Play()
		else
			TweenService:Create(ClickButton, TweenInfo.new(0.08, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, true), { Rotation = 3 * tiltSide }):Play()
		end
	elseif not holding then
		TweenService:Create(ClickButton, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Rotation = 0}):Play()
		TweenService:Create(clickScale, TweenInfo.new(0.15), {Scale = 1}):Play()
	end
end

local function UpdateHatcheryBar(current, max)
	local ratio = math.clamp(current / max, 0, 1)
	TweenService:Create(HatcheryFill, TweenInfo.new(0.1), { Size = UDim2.new(ratio, 0, 1, 0) }):Play()

	local color = Color3.fromRGB(255, 60, 60)
	if ratio > 0.5 then color = Color3.fromRGB(80, 220, 80)
	elseif ratio > 0.25 then color = Color3.fromRGB(255, 200, 0) end

	TweenService:Create(HatcheryFill, TweenInfo.new(0.1), { BackgroundColor3 = color }):Play()
	HatcheryLabel.Text = "Hatchery: " .. math.floor(current) .. " / " .. max
	hatcheryEmpty = (current <= 0)
end

local function FlashEmpty()
	TweenService:Create(HatcheryFill, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(255, 255, 255) }):Play()
	task.delay(0.1, function() TweenService:Create(HatcheryFill, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(255, 60, 60) }):Play() end)
end

local function ShowTierPopup(position, tierName, tierColor)
	local anchor = Instance.new("Part"); anchor.Size = Vector3.new(0.1, 0.1, 0.1); anchor.Anchored = true; anchor.Transparency = 1; anchor.CanCollide = false
	anchor.Position = position + Vector3.new(0, 3, 0); anchor.Parent = workspace

	local bb = Instance.new("BillboardGui"); bb.Size = UDim2.new(0, 120, 0, 40); bb.StudsOffset = Vector3.new(0, 2, 0)
	bb.AlwaysOnTop = false; bb.Adornee = anchor; bb.Parent = anchor

	local label = Instance.new("TextLabel"); label.Size = UDim2.new(1, 0, 1, 0); label.BackgroundTransparency = 1
	label.Text = tierName:upper(); label.TextColor3 = tierColor; label.TextScaled = true
	label.Font = Enum.Font.GothamBold; label.TextStrokeTransparency = 0.3; label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0); label.Parent = bb

	TweenService:Create(bb, TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffset = Vector3.new(0, 6, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(anchor, 2)
end

local function ShowCubeValue(position, value, color)
	local anchor = Instance.new("Part"); anchor.Size = Vector3.new(0.1, 0.1, 0.1); anchor.Anchored = true; anchor.Transparency = 1; anchor.CanCollide = false
	anchor.Position = position + Vector3.new(math.random(-1, 1), 2, math.random(-1, 1)); anchor.Parent = workspace

	local bb = Instance.new("BillboardGui"); bb.Size = UDim2.new(0, 80, 0, 25); bb.StudsOffset = Vector3.new(0, 0, 0)
	bb.AlwaysOnTop = false; bb.Adornee = anchor; bb.Parent = anchor

	local label = Instance.new("TextLabel"); label.Size = UDim2.new(1, 0, 1, 0); label.BackgroundTransparency = 1
	label.Text = "Value: $" .. FormatNumber(value); label.TextColor3 = Color3.fromRGB(255, 255, 255); label.TextScaled = true
	label.Font = Enum.Font.Gotham; label.TextStrokeTransparency = 0.4; label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0); label.Parent = bb

	TweenService:Create(bb, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffset = Vector3.new(0, 4, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(anchor, 1.5)
end

local function AttachPermanentRateLabel(auraInstance, baseValue, auraColor)
	local rootPart = GetRootPart(auraInstance)
	if not rootPart then return end

	local bb = Instance.new("BillboardGui")
	bb.Name = "PermanentRateLabel"
	bb.Size = UDim2.new(0, 90, 0, 25)
	bb.StudsOffset = Vector3.new(0, 0.5, 0)
	bb.AlwaysOnTop = false
	bb.MaxDistance = 35 
	bb.Adornee = rootPart

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1

	local ratePerSec = baseValue / currentPassiveInterval
	label.Text = "+$" .. FormatNumber(ratePerSec) .. "/sec"

	label.TextColor3 = auraColor or Color3.fromRGB(100, 255, 100)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextTransparency = 0.2
	label.TextStrokeTransparency = 0.6
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.Parent = bb

	bb.Parent = rootPart
	return label
end

local function RefreshAllRateLabels()
	for id, data in pairs(cubeDataMap) do
		if data.rateLabel and data.baseValue and not data.isStored then
			local ratePerSec = (data.baseValue * globalBoostMultiplier) / currentPassiveInterval
			data.rateLabel.Text = "+$" .. FormatNumber(ratePerSec) .. "/sec"
		end
	end
end

local AuraHolder = workspace:WaitForChild("AuraHolder")
local HabitatHolder = workspace:WaitForChild("HabitatHolder")

local function GetAuraCubeFromHit(hit)
	if hit.Name == "ExplodedGoldenAura" or hit.Name == "DynamicPiggyBankAura" then return nil end
	if hit:GetAttribute("AuraCube") then return hit end

	local p = hit.Parent; if p and p:GetAttribute("AuraCube") then return p end
	local m = hit:FindFirstAncestorWhichIsA("Model"); if m and m:GetAttribute("AuraCube") then return m end
	return nil
end

local function HookAuraModel(model)
	task.delay(0.1, function()
		local smush = model:FindFirstChild("SmushTrigger", true)
		if smush then
			smush.Touched:Connect(function(hit)
				local auraObj = GetAuraCubeFromHit(hit)
				if auraObj then
					local cid = auraObj:GetAttribute("CubeId")
					local data = cid and cubeDataMap[cid]

					if data then
						if data.isStored then return end
						CubeSmushedBridge:Fire(cid)
						local root = GetRootPart(auraObj)
						local pos = (root and root.Position) or hit.Position
						PlayVFX("Spawn", pos, 0.5)

						pcall(function() PoolManager.ReturnAura(data.instance) end)
						cubeDataMap[cid] = nil
						activeCubes[cid] = nil
					end
				end
			end)
		end

		for _, conveyer in ipairs(model:GetDescendants()) do
			if (conveyer.Name == "ConveyerPath" or conveyer.Name == "ConveyerPathCorner") and conveyer:IsA("BasePart") then
				local forwardBeam = conveyer:FindFirstChild("Foward") or conveyer:FindFirstChild("Forward")
				local backwardBeam = conveyer:FindFirstChild("Backward")

				if forwardBeam then forwardBeam.Enabled = not habitatFull end
				if backwardBeam then backwardBeam.Enabled = habitatFull end

				if not conveyer:GetAttribute("OriginalVelocity") then
					conveyer:SetAttribute("OriginalVelocity", conveyer.AssemblyLinearVelocity)
				end

				local origVel = conveyer:GetAttribute("OriginalVelocity")

				if habitatFull then 
					conveyer.AssemblyLinearVelocity = origVel * -2
				else 
					conveyer.AssemblyLinearVelocity = origVel 
				end
			end
		end
	end)
end

local function HookHabitatModel(model)
	task.delay(0.1, function()
		local storage = model:FindFirstChild("StorageTrigger", true)
		if storage then
			storage.Touched:Connect(function(hit)
				if hit:HasTag("PhysicsAura") or (hit.Parent and hit.Parent:HasTag("PhysicsAura")) then
					local physicsPart = hit:HasTag("PhysicsAura") and hit or hit.Parent
					local claimEvent = ReplicatedStorage:FindFirstChild("RemoteEvents") and ReplicatedStorage.RemoteEvents:FindFirstChild("ClaimPhysicsAura")
					if claimEvent then
						claimEvent:FireServer(physicsPart)
					end
					return
				end

				local auraObj = GetAuraCubeFromHit(hit)
				if auraObj then
					local cid = auraObj:GetAttribute("CubeId")
					local data = cid and cubeDataMap[cid]

					if data and not data.isStored then
						data.isStored = true
						auraObj:SetAttribute("IsStored", true)
						activeCubes[cid] = nil -- No longer active, stop checking in loop

						CubeStoredBridge:Fire(cid)

						-- PERFORMANCE CAP: Destroy physical instances if visual array overflows
						local visualStoredCount = 0
						for _, d in pairs(cubeDataMap) do
							if d.isStored then visualStoredCount += 1 end
						end

						if visualStoredCount > MAX_VISUAL_STORED then
							pcall(function() PoolManager.ReturnAura(data.instance) end)
							cubeDataMap[cid] = nil
							return
						end

						-- If we are under the visual cap, keep the instance rendering normally:
						if data.rateLabel and data.rateLabel.Parent and data.rateLabel.Parent:IsA("BillboardGui") then 
							data.rateLabel.Parent.Enabled = false 
						end

						local root = GetRootPart(auraObj)
						if root then
							local dropOffset = Vector3.new(-10, 4, math.random(-4, 4))
							auraObj:PivotTo(CFrame.new(storage.Position + dropOffset))

							if auraObj:IsA("Model") then
								for _, desc in ipairs(auraObj:GetDescendants()) do
									if desc:IsA("BasePart") then
										desc.Anchored = true
										desc.CanCollide = false
										desc.CanTouch = false
										desc.CanQuery = false
									end
								end
							elseif auraObj:IsA("BasePart") then
								auraObj.Anchored = true
								auraObj.CanCollide = false
								auraObj.CanTouch = false
								auraObj.CanQuery = false
							end
						end
					end
				end
			end)
		end
	end)
end

AuraHolder.ChildAdded:Connect(function(child) if child:IsA("Model") then HookAuraModel(child) end end)
HabitatHolder.ChildAdded:Connect(function(child) if child:IsA("Model") then HookHabitatModel(child) end end)

for _, child in ipairs(AuraHolder:GetChildren()) do if child:IsA("Model") then HookAuraModel(child) end end
for _, child in ipairs(HabitatHolder:GetChildren()) do if child:IsA("Model") then HookHabitatModel(child) end end

local trackedInputs = {}

local function EvaluateHolding()
	if isAreaLoading then return end 

	local hasInput = false
	for _, _ in pairs(trackedInputs) do hasInput = true; break end

	if hasInput and not holding then
		if type(shared.TutorialCanPerform) == "function" then
			if not shared.TutorialCanPerform("Action_ClickRedButton") then table.clear(trackedInputs); return end
		end

		if hatcheryEmpty then FlashEmpty() return end
		if habitatFull then return end

		holding = true; holdStart = tick()
		TweenService:Create(clickScale, TweenInfo.new(0.1, Enum.EasingStyle.Sine), {Scale = 0.9}):Play()
		ProduceAuraBridge:Fire("start")

		if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
	elseif not hasInput and holding then
		holding = false; holdStart = nil
		ProduceAuraBridge:Fire("stop")
		UpdateButtonVisual(); UpdateMultiplier:Fire(1.0)
	end
end

ClickButton.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		trackedInputs[input] = true; EvaluateHolding()
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if input.KeyCode == Enum.KeyCode.Space and not UserInputService:GetFocusedTextBox() then
		local player = game:GetService("Players").LocalPlayer
		if player:GetAttribute("InSpecialArea") then return end

		trackedInputs[input] = true; EvaluateHolding()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if trackedInputs[input] then trackedInputs[input] = nil; EvaluateHolding() end
end)

UserInputService.WindowFocusReleased:Connect(function()
	table.clear(trackedInputs); EvaluateHolding()
end)

ForceStopHold.OnClientEvent:Connect(function()
	table.clear(trackedInputs); EvaluateHolding()
end)

HabitatFull.OnClientEvent:Connect(function()
	habitatFull = true; HabitatFullEvent:Fire(true); table.clear(trackedInputs); EvaluateHolding()
end)

HabitatFullEvent.Event:Connect(function(isFull)
	habitatFull = isFull
	if not isFull then 
		UpdateButtonVisual() 
	end

	local targetedConveyors = {}

	for _, auraModel in ipairs(AuraHolder:GetChildren()) do
		if auraModel:IsA("Model") then
			for _, conveyer in ipairs(auraModel:GetDescendants()) do
				if string.find(conveyer.Name, "Storage") or string.find(conveyer:GetFullName(), "HabitatStorageModel") then
					continue
				end

				if (conveyer.Name == "ConveyerPath" or conveyer.Name == "ConveyerPathCorner") and conveyer:IsA("BasePart") then
					table.insert(targetedConveyors, conveyer:GetFullName())

					local forwardBeam = conveyer:FindFirstChild("Foward") or conveyer:FindFirstChild("Forward")
					local backwardBeam = conveyer:FindFirstChild("Backward")

					if forwardBeam then forwardBeam.Enabled = not isFull end
					if backwardBeam then backwardBeam.Enabled = isFull end

					if not conveyer:GetAttribute("OriginalVelocity") then
						conveyer:SetAttribute("OriginalVelocity", conveyer.AssemblyLinearVelocity)
					end

					local origVel = conveyer:GetAttribute("OriginalVelocity")

					if isFull then 
						conveyer.AssemblyLinearVelocity = origVel * -2
					else 
						conveyer.AssemblyLinearVelocity = origVel 
					end
				end
			end
		end
	end
end)

UpdateHatcheryBridge:Connect(function(info)
	local finalMax = info.max
	local localHatchLvl = player:GetAttribute("LocalHatcheryLevel")

	if localHatchLvl then
		local UpgradeConfig = require(ReplicatedStorage.Modules.UpgradeConfig)
		local cfg = UpgradeConfig.GetUpgradeConfig("hatcheryCapacity")
		if cfg and cfg.apply then
			local predictedMax = cfg.apply({ upgrades = { hatcheryCapacity = localHatchLvl } })
			finalMax = math.max(info.max, predictedMax)
		end
	end
	UpdateHatcheryBar(info.current, finalMax)
end)

local localUpgradesState = {}

local function RecalculateMaxTier()
	local speedData = localUpgradesState["multiplierSpeed"]
	local speedLevel = (typeof(speedData) == "table" and speedData.level) or (typeof(speedData) == "number" and speedData) or 0
	playerMultSpeed = 1.0 + (speedLevel * 0.05)

	local tierUnlocks = {
		{ upgradeId = "unlockOmniMult",      tier = 10 },
		{ upgradeId = "unlockUniversalMult", tier = 9 },
		{ upgradeId = "unlockGodlyMult",     tier = 8 },
		{ upgradeId = "unlockCosmicMult",    tier = 7 },
		{ upgradeId = "unlockMythicMult",    tier = 6 },
	}

	local calculatedMaxTier = 5 
	for _, data in ipairs(tierUnlocks) do
		local upgData = localUpgradesState[data.upgradeId]
		local level = (typeof(upgData) == "table" and upgData.level) or (typeof(upgData) == "number" and upgData) or 0
		if level > 0 then calculatedMaxTier = data.tier; break end
	end
	playerMaxTier = calculatedMaxTier
end

ReplicatedStorage.RemoteEvents.UpgradeUpdated.OnClientEvent:Connect(function(info)
	if not info then return end
	if info.type == "fullState" and info.upgrades then
		localUpgradesState = info.upgrades; RecalculateMaxTier()
	elseif info.type == "purchased" then
		if not localUpgradesState[info.upgradeId] then localUpgradesState[info.upgradeId] = {} end
		if type(localUpgradesState[info.upgradeId]) == "number" then localUpgradesState[info.upgradeId] = { level = info.level }
		else localUpgradesState[info.upgradeId].level = info.level end
		RecalculateMaxTier()
	end
end)

local EpicUpgradeUpdated = ReplicatedStorage.RemoteEvents:FindFirstChild("EpicUpgradeUpdated")
if EpicUpgradeUpdated then
	EpicUpgradeUpdated.OnClientEvent:Connect(function(info)
		if not info then return end
		if info.type == "fullState" and info.upgrades then
			for k,v in pairs(info.upgrades) do localUpgradesState[k] = v end; RecalculateMaxTier()
		elseif info.type == "purchased" then
			if not localUpgradesState[info.upgradeId] then localUpgradesState[info.upgradeId] = {} end
			if type(localUpgradesState[info.upgradeId]) == "number" then localUpgradesState[info.upgradeId] = { level = info.level }
			else localUpgradesState[info.upgradeId].level = info.level end
			RecalculateMaxTier()
		end
	end)
end

UpdateHUDBridge:Connect(function(stats)
	local needsRefresh = false

	if stats.passiveInterval ~= nil and stats.passiveInterval ~= currentPassiveInterval then 
		currentPassiveInterval = stats.passiveInterval
		needsRefresh = true
	end

	if stats.boostMultiplier ~= nil and stats.boostMultiplier ~= globalBoostMultiplier then
		globalBoostMultiplier = stats.boostMultiplier
		needsRefresh = true
	end

	if stats.currentFireRate ~= nil then
		currentFireRate = stats.currentFireRate
	end

	if stats.upgrades then
		for k, v in pairs(stats.upgrades) do localUpgradesState[k] = v end
		RecalculateMaxTier()
	end

	if stats.pendingAuras ~= nil then
		latestPendingAuras = stats.pendingAuras
	end

	if stats.habitatCapacity ~= nil and stats.habitatCapacity > 0 then
		latestHabitatCapacity = stats.habitatCapacity
	end

	if stats.pendingAuras ~= nil then
		if stats.pendingAuras < latestHabitatCapacity and habitatFull then
			habitatFull = false
			HabitatFullEvent:Fire(false)
			UpdateButtonVisual()
		end
	end

	if needsRefresh then RefreshAllRateLabels() end
end)

task.spawn(function()
	while true do
		if holding then
			if hatcheryEmpty or habitatFull then
				table.clear(trackedInputs); EvaluateHolding()
			else
				ProduceAuraBridge:Fire(); UpdateButtonVisual()
			end
		end
		task.wait(currentFireRate)
	end
end)

AuraSpawnedBridge:Connect(function(info)
	if isAreaLoading then return end 

	local activeAuraModel = workspace:FindFirstChild("AuraHolder") and workspace.AuraHolder:FindFirstChildWhichIsA("Model")
	local safeSpawnPos = info.spawnPos
	if activeAuraModel then
		local spawnPoint = activeAuraModel:FindFirstChild("AuraSpawnPoint", true)
		if spawnPoint and spawnPoint:IsA("BasePart") then
			local size = spawnPoint.Size
			local randX = (math.random() - 0.5) * size.X
			local randZ = (math.random() - 0.5) * size.Z
			safeSpawnPos = (spawnPoint.CFrame * CFrame.new(randX, 0, randZ)).Position
		end
	end

	local instance, isCustom = SpawnAuraInstance(info.tier, info.color, info.glow, safeSpawnPos, info.currentArea)

	if not instance then return end

	instance:SetAttribute("AuraCube", true)
	instance:SetAttribute("IsStored", false)
	instance:SetAttribute("CubeId", info.cubeId)
	ScaleAura(instance, info.tier, false)
	ShowCubeValue(safeSpawnPos, info.value, info.color)
	PlayVFX("Spawn", safeSpawnPos, 1.0)

	local permLabel = AttachPermanentRateLabel(instance, info.value, info.color)

	if info.tier == "Legendary" then
		ShowTierPopup(safeSpawnPos, "Legendary", Color3.fromRGB(255, 200, 0))
		PlayVFX("Legendary", safeSpawnPos, 2.0)
	end

	if info.cubeId then
		cubeDataMap[info.cubeId] = { 
			instance = instance, 
			tierName = info.tier, 
			isCustom = isCustom,
			rateLabel = permLabel,
			baseValue = info.value 
		}
		activeCubes[info.cubeId] = true -- Register it in the active window

		cubeDataMap[info.cubeId].ancestryConn = instance.AncestryChanged:Connect(function(_, parent)
			if not parent then 
				cubeDataMap[info.cubeId] = nil 
				activeCubes[info.cubeId] = nil
			end
		end)
	end

	local thrustLevel = 0
	if localUpgradesState["epicConveyorThrust"] then
		thrustLevel = (typeof(localUpgradesState["epicConveyorThrust"]) == "table" and localUpgradesState["epicConveyorThrust"].level) or (typeof(localUpgradesState["epicConveyorThrust"]) == "number" and localUpgradesState["epicConveyorThrust"]) or 0
	end

	if thrustLevel > 0 then
		local root = GetRootPart(instance)
		if root then
			root.AssemblyLinearVelocity = root.AssemblyLinearVelocity + Vector3.new(0, 5, 25)
		end
	end
end)

CubeMutatedBatchBridge:Connect(function(batchData)
	if isAreaLoading then return end

	for _, info in ipairs(batchData) do
		local cubeData = cubeDataMap[info.cubeId]
		if not cubeData then continue end

		if info.newValue then
			cubeData.baseValue = info.newValue
		end

		local instance = cubeData.instance
		if not instance or not instance.Parent then continue end 

		local rootPart = GetRootPart(instance)
		if not rootPart then continue end 
		local position = rootPart.Position

		if info.mutationType == "tierUpgrade" then
			PlayVFX("TierUpgrade", position, 1.5)
			if info.tierName == "Legendary" then PlayVFX("Legendary", position, 2.0) end

			local oldTierName = cubeData.tierName

			local newAura = nil
			local success = false
			local attempts = 0

			while not success and attempts < 3 do
				attempts += 1
				newAura = PoolManager.GetAura(info.currentArea, info.tierName)
				if newAura then
					success = pcall(function() newAura.Parent = workspace end)
				end
			end

			if not success or not newAura then continue end

			if newAura:IsA("Model") then
				newAura:PivotTo(CFrame.new(position))
				local primary = newAura.PrimaryPart or newAura:FindFirstChildWhichIsA("BasePart")

				if primary then
					primary.Anchored = false
					primary.CanCollide = true
					primary.CanTouch = true
					primary.CanQuery = true
					primary.CollisionGroup = "Auras"
					primary.CastShadow = false
				end

				for _, desc in ipairs(newAura:GetDescendants()) do
					if desc:IsA("BasePart") and desc ~= primary then
						desc.CanCollide = false
						desc.CanTouch = false
						desc.CanQuery = false
						desc.CastShadow = false
					end
				end

			elseif newAura:IsA("BasePart") then
				newAura.Position = position
				newAura.Anchored = false
				newAura.CanCollide = true
				newAura.CanTouch = true
				newAura.CanQuery = true
				newAura.CollisionGroup = "Auras"
				newAura.CastShadow = false
				newAura.Color = info.newColor
			end

			for _, desc in ipairs(newAura:GetDescendants()) do
				if desc:IsA("ParticleEmitter") or desc:IsA("Trail") then desc.Enabled = true end
			end

			newAura:SetAttribute("AuraCube", true)
			newAura:SetAttribute("IsStored", cubeData.isStored or false)
			newAura:SetAttribute("CubeId", info.cubeId)
			ScaleAura(newAura, info.tierName, true, oldTierName)
			ApplyHeavyPhysics(newAura)

			if cubeData.rateLabel and cubeData.rateLabel.Parent and cubeData.rateLabel.Parent:IsA("BillboardGui") then
				local bb = cubeData.rateLabel.Parent
				bb.Adornee = GetRootPart(newAura)
				bb.Parent = GetRootPart(newAura)
				cubeData.rateLabel.TextColor3 = info.newColor or Color3.fromRGB(100, 255, 100)
				if cubeData.isStored then bb.Enabled = false end
			end

			pcall(function() PoolManager.ReturnAura(instance) end)
			cubeData.instance = newAura; cubeData.tierName = info.tierName; cubeData.isCustom = true
			if cubeData.ancestryConn then cubeData.ancestryConn:Disconnect() end
			local conn = newAura.AncestryChanged:Connect(function(_, parent)
				if not parent then 
					cubeDataMap[info.cubeId] = nil 
					activeCubes[info.cubeId] = nil
				end
			end)
			cubeData.ancestryConn = conn
			ShowTierPopup(position, info.tierName, info.newColor)
		end

		if cubeData.rateLabel and cubeData.rateLabel.Parent and not cubeData.isStored then
			local ratePerSec = ((cubeData.baseValue or 0) * globalBoostMultiplier) / currentPassiveInterval
			cubeData.rateLabel.Text = "+$" .. FormatNumber(ratePerSec) .. "/sec"
		end
	end
end)

-- Server rejected storing this cube because habitat was actually full (in-flight overflow)
CubeStoredBridge:Connect(function(payload)
	if type(payload) ~= "table" or not payload.rejected then return end
	local cid = payload.cubeId
	local data = cid and cubeDataMap[cid]
	if not data then return end

	if data.instance then
		local root = GetRootPart(data.instance)
		if root then PlayVFX("Spawn", root.Position, 0.5) end
		pcall(function() PoolManager.ReturnAura(data.instance) end)
	end
	if data.ancestryConn then data.ancestryConn:Disconnect() end
	cubeDataMap[cid] = nil
	activeCubes[cid] = nil
end)

-- OPTIMIZED ROLLING WINDOW: Only checks instances actively falling to the void
task.spawn(function()
	while true do
		task.wait(1.5)
		local now = tick()

		for id, _ in pairs(activeCubes) do
			local data = cubeDataMap[id]
			if data and not data.isStored and data.instance and data.instance.Parent then
				local root = GetRootPart(data.instance)
				if root then
					local currentPos = root.Position
					if not data.spawnY then
						data.spawnY = currentPos.Y; data.lastPos = currentPos; data.lastMovedTime = now
					end

					if currentPos.Y < data.spawnY - 12 then
						CubeSmushedBridge:Fire(id)
						PlayVFX("Spawn", currentPos, 0.5)
						pcall(function() PoolManager.ReturnAura(data.instance) end)
						cubeDataMap[id] = nil
						activeCubes[id] = nil
						continue
					end

					local dist = (currentPos - data.lastPos).Magnitude
					if dist < 0.25 then
						if now - data.lastMovedTime > 8 then
							CubeSmushedBridge:Fire(id)
							PlayVFX("Spawn", currentPos, 0.5)
							pcall(function() PoolManager.ReturnAura(data.instance) end)
							cubeDataMap[id] = nil
							activeCubes[id] = nil
						end
					else
						data.lastPos = currentPos; data.lastMovedTime = now
					end
				end
			else
				activeCubes[id] = nil -- Clean up invalid entries from window
			end
		end
	end
end)

AreaChanged.OnClientEvent:Connect(function()
	isAreaLoading = true 

	for id, data in pairs(cubeDataMap) do
		if data.instance then
			pcall(function() data.instance:Destroy() end)
		end
	end
	table.clear(cubeDataMap)
	table.clear(activeCubes)
	lastTierIndex = 1

	PoolManager.ClearPools()

	if holding then
		holding = false
		holdStart = nil
		ProduceAuraBridge:Fire("stop")
		UpdateButtonVisual()
		UpdateMultiplier:Fire(1.0)
		table.clear(trackedInputs)
	end

	task.delay(3, function()
		isAreaLoading = false
	end)
end)

PrestigeComplete.OnClientEvent:Connect(function(info)
	table.clear(trackedInputs)
	holding = false
	holdStart = nil
	ProduceAuraBridge:Fire("stop")
	UpdateButtonVisual()
	UpdateMultiplier:Fire(1.0)
end)

-- =====================================================================
-- 1. MODULE: AreaRegistry
-- Location: ReplicatedStorage > Modules > AreaRegistry
-- =====================================================================
local AreaRegistry = {}

AreaRegistry.LightingPresets = {

	-- 🏭 PHASE 1: THE GRIME (Areas 1-3)
	["Area1_DeepScrapyard"] = {
		ClockTime = 12, Brightness = 0.3, SunRaysIntensity = 0,
		Ambient = Color3.fromRGB(70, 60, 50), FogColor = Color3.fromRGB(90, 80, 65),
		FogStart = 20, FogEnd = 60, Density = 0.7, Haze = 10, AtmosphereColor = Color3.fromRGB(90, 80, 65)
	},
	["Area2_RustyWastes"] = {
		ClockTime = 14, Brightness = 0.4, SunRaysIntensity = 0,
		Ambient = Color3.fromRGB(80, 65, 50), FogColor = Color3.fromRGB(100, 85, 60),
		FogStart = 20, FogEnd = 80, Density = 0.6, Haze = 8, AtmosphereColor = Color3.fromRGB(100, 91, 70)
	},
	["Area3_IndustrialOutskirts"] = {
		ClockTime = 16, Brightness = 3, SunRaysIntensity = 0.2,
		Ambient = Color3.fromRGB(124, 115, 105), FogColor = Color3.fromRGB(125, 117, 111),
		FogStart = 0, FogEnd = 0, Density = 0, Haze = 0, AtmosphereColor = Color3.fromRGB(120, 116, 113)
	},

	-- ☣️ PHASE 2: TOXIC ZONES (Areas 4-5)
	["Area4_ChemicalSpill"] = {
		ClockTime = 17, Brightness = 0.4, SunRaysIntensity = 0,
		Ambient = Color3.fromRGB(60, 75, 50), FogColor = Color3.fromRGB(75, 90, 55),
		FogStart = 0, FogEnd = 0, Density = 0, Haze = 2, AtmosphereColor = Color3.fromRGB(75, 90, 55)
	},
	["Area5_BioHazard"] = {
		ClockTime = 15.7, Brightness = 0.3, SunRaysIntensity = 0.37,
		Ambient = Color3.fromRGB(209, 209, 209), FogColor = Color3.fromRGB(230, 230, 230),
		FogStart = 0, FogEnd = 0, Density = 0, Haze = 3, AtmosphereColor = Color3.fromRGB(203, 208, 109)
	},

	-- 🌆 PHASE 3: TWILIGHT SLUMS (Areas 6-8)
	["Area6_SunsetStrip"] = {
		ClockTime = 17.8, Brightness = 0.6, SunRaysIntensity = 0.1,
		Ambient = Color3.fromRGB(70, 40, 40), FogColor = Color3.fromRGB(90, 40, 30),
		FogStart = 20, FogEnd = 150, Density = 0.5, Haze = 4, AtmosphereColor = Color3.fromRGB(120, 50, 40)
	},
	["Area7_TwilightSector"] = {
		ClockTime = 18.2, Brightness = 0.4, SunRaysIntensity = 0,
		Ambient = Color3.fromRGB(40, 30, 60), FogColor = Color3.fromRGB(35, 25, 55),
		FogStart = 20, FogEnd = 180, Density = 0.55, Haze = 4, AtmosphereColor = Color3.fromRGB(35, 25, 55)
	},
	["Area8_NeonSlums"] = {
		ClockTime = 0, Brightness = 0.5, SunRaysIntensity = 0,
		Ambient = Color3.fromRGB(30, 20, 50), FogColor = Color3.fromRGB(20, 10, 40),
		FogStart = 25, FogEnd = 200, Density = 0.5, Haze = 3, AtmosphereColor = Color3.fromRGB(40, 20, 80)
	},

	-- 🌃 PHASE 4: CYBER CITY (Areas 9-10)
	["Area9_LowerCyber"] = {
		ClockTime = 0, Brightness = 0.7, SunRaysIntensity = 0,
		Ambient = Color3.fromRGB(25, 25, 55), FogColor = Color3.fromRGB(15, 15, 45),
		FogStart = 30, FogEnd = 250, Density = 0.4, Haze = 2, AtmosphereColor = Color3.fromRGB(20, 20, 60)
	},
	["Area10_CyberCore"] = {
		ClockTime = 0, Brightness = 1, SunRaysIntensity = 0,
		Ambient = Color3.fromRGB(20, 30, 60), FogColor = Color3.fromRGB(10, 20, 50),
		FogStart = 50, FogEnd = 400, Density = 0.25, Haze = 1, AtmosphereColor = Color3.fromRGB(15, 25, 65)
	},

	-- 🌐 PHASE 5: CORPORATE STERILITY (Areas 11-13)
	["Area11_GlassFacility"] = {
		ClockTime = 12, Brightness = 2.0, SunRaysIntensity = 0.4,
		Ambient = Color3.fromRGB(130, 130, 140), FogColor = Color3.fromRGB(200, 220, 240),
		FogStart = 100, FogEnd = 1500, Density = 0.15, Haze = 0, AtmosphereColor = Color3.fromRGB(200, 220, 240)
	},
	["Area12_CrystalLab"] = {
		ClockTime = 14, Brightness = 2.5, SunRaysIntensity = 0.5,
		Ambient = Color3.fromRGB(150, 150, 150), FogColor = Color3.fromRGB(220, 240, 255),
		FogStart = 150, FogEnd = 2500, Density = 0.1, Haze = 0, AtmosphereColor = Color3.fromRGB(220, 240, 255)
	},
	["Area13_QuantumGrid"] = {
		ClockTime = 14, Brightness = 2.2, SunRaysIntensity = 0.3,
		Ambient = Color3.fromRGB(100, 180, 200), FogColor = Color3.fromRGB(150, 255, 255),
		FogStart = 200, FogEnd = 3000, Density = 0.05, Haze = 0, AtmosphereColor = Color3.fromRGB(150, 255, 255)
	},

	-- 🌌 PHASE 6: REALITY BREAKING (Areas 14-16)
	["Area14_PlasmaCore"] = {
		ClockTime = 17.5, Brightness = 1.8, SunRaysIntensity = 0.3,
		Ambient = Color3.fromRGB(150, 80, 150), FogColor = Color3.fromRGB(200, 100, 200),
		FogStart = 100, FogEnd = 2000, Density = 0.2, Haze = 2, AtmosphereColor = Color3.fromRGB(200, 100, 200)
	},
	["Area15_CosmicRift"] = {
		ClockTime = 6, Brightness = 1.5, SunRaysIntensity = 0.2,
		Ambient = Color3.fromRGB(100, 30, 150), FogColor = Color3.fromRGB(70, 0, 100),
		FogStart = 50, FogEnd = 1000, Density = 0.3, Haze = 4, AtmosphereColor = Color3.fromRGB(150, 0, 255)
	},
	["Area16_DarkMatter"] = {
		ClockTime = 0, Brightness = 0.8, SunRaysIntensity = 0,
		Ambient = Color3.fromRGB(80, 10, 20), FogColor = Color3.fromRGB(40, 0, 5),
		FogStart = 30, FogEnd = 600, Density = 0.5, Haze = 6, AtmosphereColor = Color3.fromRGB(120, 0, 10)
	},

	-- ⬛ PHASE 7: THE VOID (Areas 17-20)
	["Area17_EventHorizon"] = {
		ClockTime = 0, Brightness = 0.4, SunRaysIntensity = 0,
		Ambient = Color3.fromRGB(30, 10, 40), FogColor = Color3.fromRGB(15, 5, 20),
		FogStart = 50, FogEnd = 800, Density = 0.3, Haze = 3, AtmosphereColor = Color3.fromRGB(20, 5, 30)
	},
	["Area18_DeepSpace"] = {
		ClockTime = 0, Brightness = 0.2, SunRaysIntensity = 0,
		Ambient = Color3.fromRGB(15, 15, 25), FogColor = Color3.fromRGB(5, 5, 15),
		FogStart = 100, FogEnd = 1500, Density = 0.15, Haze = 1, AtmosphereColor = Color3.fromRGB(5, 5, 15)
	},
	["Area19_TheAbyss"] = {
		ClockTime = 0, Brightness = 0.05, SunRaysIntensity = 0,
		Ambient = Color3.fromRGB(5, 5, 5), FogColor = Color3.fromRGB(2, 2, 2),
		FogStart = 200, FogEnd = 3000, Density = 0.05, Haze = 0, AtmosphereColor = Color3.fromRGB(2, 2, 2)
	},
	["Area20_UniversalVoid"] = {
		ClockTime = 0, Brightness = 0, SunRaysIntensity = 0,
		Ambient = Color3.fromRGB(0, 0, 0), FogColor = Color3.fromRGB(0, 0, 0),
		FogStart = 500, FogEnd = 5000, Density = 0, Haze = 0, AtmosphereColor = Color3.fromRGB(0, 0, 0)
	},

	-- ✨ SPECIAL: THE GOLDEN VAULT (Piggy Bank)
	["Area_PiggyBank"] = {
		ClockTime = 12, Brightness = 3.0, SunRaysIntensity = 0.5,
		Ambient = Color3.fromRGB(200, 150, 50), FogColor = Color3.fromRGB(255, 240, 150),
		FogStart = 50, FogEnd = 1000, Density = 0.1, Haze = 0, AtmosphereColor = Color3.fromRGB(255, 215, 0)
	}
}

AreaRegistry.Areas = {
	[1] = { 
		name             = "Green Scrapyard",     
		threshold        = 0,   
		valueMultiplier  = 1.0, 
		yOffset          = -2.7, 
		yRotation        = 180, 
		auraPreviewColor = Color3.fromRGB(200, 200, 200), 
		grassColor       = Color3.fromRGB(92, 197, 53), 
		pathColor        = Color3.fromRGB(163, 130, 88), 
		ambientColor     = Color3.fromRGB(90, 90, 100), 
		fogColor         = Color3.fromRGB(180, 200, 220), 
		auraHolderColor  = Color3.fromRGB(255, 255, 255), 
		auraHolderGlow   = Color3.fromRGB(255, 255, 255), 
		lightingPreset   = "Area1_DeepScrapyard", 
		icon = "rbxassetid://71630626823279",
		auraModels       = { Common = "GearAura", Uncommon = "ScrewAura", Rare = "BottleAura", Epic = "TireAura", Legendary = "RadioAura" }
	},
	[2] = { 
		name             = "Industrial Rust",    
		threshold = 2.5e4,
		valueMultiplier  = 1.5, 
		yOffset          = -4.5, 
		yRotation        = 180, 
		auraPreviewColor = Color3.fromRGB(180, 100, 50), 
		grassColor       = Color3.fromRGB(104, 160, 98), 
		pathColor        = Color3.fromRGB(132, 140, 81), 
		ambientColor     = Color3.fromRGB(80, 100, 80), 
		fogColor         = Color3.fromRGB(160, 200, 160), 
		auraHolderColor  = Color3.fromRGB(187, 255, 183), 
		auraHolderGlow   = Color3.fromRGB(100, 255, 100), 
		lightingPreset   = "Area2_RustyWastes", 
		icon = "rbxassetid://130447112533927",
		auraModels       = { Common = "GearAura", Uncommon = "ScrapMetalAura", Rare = "BarrelAura", Epic = "OilAura", Legendary = "BrokenweaponAura" }
	},
	[3] = { 
		name             = "Foil Scrapyard",        
		threshold        = 2.5e5, 
		valueMultiplier  = 4.0, 
		yOffset          = -2.8, 
		yRotation        = 180, 
		auraPreviewColor = Color3.fromRGB(220, 230, 255), 
		grassColor       = Color3.fromRGB(180, 190, 200), 
		pathColor        = Color3.fromRGB(150, 160, 170), 
		ambientColor     = Color3.fromRGB(100, 110, 120), 
		fogColor         = Color3.fromRGB(200, 210, 220), 
		auraHolderColor  = Color3.fromRGB(220, 230, 255), 
		auraHolderGlow   = Color3.fromRGB(240, 250, 255), 
		lightingPreset   = "Area3_IndustrialOutskirts", 
		icon = "rbxassetid://127570555675325",
		auraModels       = { Common = "FoilBallAura", Uncommon = "CandyAura", Rare = "CrushedCanAura", Epic = "CapAura", Legendary = "SilverLeafAura", Mythic = "BalloonAura" }
	},
	[4] = { 
		name             = "Cheap Metal",        
		threshold        = 5e6, 
		valueMultiplier  = 8.0, 
		yOffset          = -2.8, 
		yRotation        = 180, 
		auraPreviewColor = Color3.fromRGB(150, 150, 160), 
		grassColor       = Color3.fromRGB(130, 130, 140), 
		pathColor        = Color3.fromRGB(100, 100, 110), 
		ambientColor     = Color3.fromRGB(80, 80, 90), 
		fogColor         = Color3.fromRGB(140, 140, 150), 
		auraHolderColor  = Color3.fromRGB(170, 170, 180), 
		auraHolderGlow   = Color3.fromRGB(190, 190, 200), 
		lightingPreset   = "Area4_ChemicalSpill", 
		icon = "rbxassetid://114952653386252",
		auraModels       = { Common = "PlateAura", Uncommon = "PipeAura", Rare = "CoinAura", Epic = "WheelAura", Legendary = "ShoppingAura", Mythic = "StatueAura" }
	},
	[5] = { 
		name             = "Solid Metal",   
		threshold        = 5e7, 
		valueMultiplier  = 20.0,
		yOffset          = -3.0,   
		yRotation        = 0,   
		auraPreviewColor = Color3.fromRGB(90, 95, 100), 
		grassColor       = Color3.fromRGB(80, 85, 90), 
		pathColor        = Color3.fromRGB(60, 65, 70), 
		ambientColor     = Color3.fromRGB(50, 55, 60), 
		fogColor         = Color3.fromRGB(100, 105, 110), 
		auraHolderColor  = Color3.fromRGB(120, 125, 130), 
		auraHolderGlow   = Color3.fromRGB(140, 145, 150), 
		lightingPreset   = "Area5_BioHazard", 
		icon = "rbxassetid://71630626823279",
		auraModels       = { Common = "StoneAura", Uncommon = "IronoreAura", Rare = "CopperingotAura", Epic = "MeteoriteAura", Legendary = "EmeraldAura", Mythic = "DiamondAura", Divine = "SadrockModel", Celestial = "TimeoreAura" }
	},
	[6] = {
		name             = "Refined Alloys",
		threshold        = 5e9,
		valueMultiplier  = 75.0,
		yOffset          = -4.5,
		yRotation        = 180,
		auraPreviewColor = Color3.fromRGB(200, 120, 50),
		grassColor       = Color3.fromRGB(160, 90, 40),
		pathColor        = Color3.fromRGB(120, 70, 30),
		ambientColor     = Color3.fromRGB(90, 50, 20),
		fogColor         = Color3.fromRGB(180, 100, 60),
		auraHolderColor  = Color3.fromRGB(220, 140, 80),
		auraHolderGlow   = Color3.fromRGB(255, 180, 100),
		lightingPreset   = "Area6_RefinedAlloys", 
		auraModels       = { Common = "CopperWire", Uncommon = "BrassGear", Rare = "BronzeStatue", Epic = "TitaniumPlate", Legendary = "CobaltShard" }
	},
	[7] = {
		name             = "Precious Metals",
		threshold        = 5e12,
		valueMultiplier  = 350.0,
		yOffset          = -4.5,
		yRotation        = 180,
		auraPreviewColor = Color3.fromRGB(255, 215, 0),
		grassColor       = Color3.fromRGB(200, 170, 0),
		pathColor        = Color3.fromRGB(150, 120, 0),
		ambientColor     = Color3.fromRGB(120, 100, 20),
		fogColor         = Color3.fromRGB(255, 230, 100),
		auraHolderColor  = Color3.fromRGB(255, 240, 150),
		auraHolderGlow   = Color3.fromRGB(255, 255, 200),
		lightingPreset   = "Area7_PreciousMetals", 
		auraModels       = { Common = "SilverBar", Uncommon = "GoldNugget", Rare = "PlatinumRing", Epic = "PalladiumCoin", Legendary = "RhodiumIngot" }
	},
	[8] = {
		name             = "Industrial Synthetics",
		threshold        = 5e15,
		valueMultiplier  = 2500.0,
		yOffset          = -4.5,
		yRotation        = 180,
		auraPreviewColor = Color3.fromRGB(230, 230, 230),
		grassColor       = Color3.fromRGB(40, 40, 40),
		pathColor        = Color3.fromRGB(20, 20, 20),
		ambientColor     = Color3.fromRGB(60, 60, 60),
		fogColor         = Color3.fromRGB(100, 100, 100),
		auraHolderColor  = Color3.fromRGB(255, 255, 255),
		auraHolderGlow   = Color3.fromRGB(200, 200, 255),
		lightingPreset   = "Area8_Synthetics", 
		auraModels       = { Common = "PVC_Pipe", Uncommon = "KevlarWeave", Rare = "TeflonBlock", Epic = "CarbonFiberRoll", Legendary = "GrapheneSheet" }
	},
	[9] = {
		name             = "Volatile Materials",
		threshold        = 5e19,
		valueMultiplier  = 50000.0,
		yOffset          = -4.5,
		yRotation        = 180,
		auraPreviewColor = Color3.fromRGB(100, 255, 100),
		grassColor       = Color3.fromRGB(30, 50, 30),
		pathColor        = Color3.fromRGB(20, 40, 20),
		ambientColor     = Color3.fromRGB(40, 70, 40),
		fogColor         = Color3.fromRGB(80, 200, 80),
		auraHolderColor  = Color3.fromRGB(150, 255, 150),
		auraHolderGlow   = Color3.fromRGB(0, 255, 0),
		lightingPreset   = "Area9_Volatile", 
		auraModels       = { Common = "GlowingSludge", Uncommon = "RadiumDial", Rare = "UraniumRod", Epic = "PlutoniumCore", Legendary = "AntimatterVial" }
	},
	[10] = {
		name             = "Rough Gemstones",
		threshold        = 5e25,
		valueMultiplier  = 1000000.0,
		yOffset          = -4.5,
		yRotation        = 180,
		auraPreviewColor = Color3.fromRGB(200, 100, 255),
		grassColor       = Color3.fromRGB(90, 50, 120),
		pathColor        = Color3.fromRGB(60, 30, 80),
		ambientColor     = Color3.fromRGB(100, 60, 130),
		fogColor         = Color3.fromRGB(180, 120, 255),
		auraHolderColor  = Color3.fromRGB(230, 150, 255),
		auraHolderGlow   = Color3.fromRGB(200, 50, 255),
		lightingPreset   = "Area10_RoughGems", 
		auraModels       = { Common = "AmethystCluster", Uncommon = "RawSapphire", Rare = "UncutRuby", Epic = "EmeraldChunk", Legendary = "OpalGeode" }
	},
	[11] = {
		name             = "Polished Gems",
		threshold        = 5e32,
		valueMultiplier  = 5e7,
		yOffset          = -4.5,
		yRotation        = 180,
		auraPreviewColor = Color3.fromRGB(150, 255, 255),
		grassColor       = Color3.fromRGB(200, 240, 255),
		pathColor        = Color3.fromRGB(180, 220, 255),
		ambientColor     = Color3.fromRGB(100, 200, 255),
		fogColor         = Color3.fromRGB(180, 255, 255),
		auraHolderColor  = Color3.fromRGB(220, 255, 255),
		auraHolderGlow   = Color3.fromRGB(255, 255, 255),
		lightingPreset   = "Area11_PolishedGems", 
		auraModels       = { Common = "PolishedTopaz", Uncommon = "FacetedSapphire", Rare = "CutRuby", Epic = "PerfectEmerald", Legendary = "FlawlessDiamond" }
	},
	[12] = {
		name             = "High-Tech Computing",
		threshold        = 5e40,
		valueMultiplier  = 2.5e9,
		yOffset          = -4.5,
		yRotation        = 180,
		auraPreviewColor = Color3.fromRGB(50, 200, 100),
		grassColor       = Color3.fromRGB(20, 40, 30),
		pathColor        = Color3.fromRGB(15, 30, 20),
		ambientColor     = Color3.fromRGB(30, 60, 40),
		fogColor         = Color3.fromRGB(40, 120, 80),
		auraHolderColor  = Color3.fromRGB(100, 255, 150),
		auraHolderGlow   = Color3.fromRGB(50, 255, 100),
		lightingPreset   = "Area12_HighTech", 
		auraModels       = { Common = "SiliconWafer", Uncommon = "Microchip", Rare = "RAM_Stick", Epic = "QuantumProcessor", Legendary = "AI_Core" }
	},
	[13] = {
		name             = "Neon & Plasma",
		threshold        = 5e50,
		valueMultiplier  = 1.5e11,
		yOffset          = -4.5,
		yRotation        = 180,
		auraPreviewColor = Color3.fromRGB(255, 50, 150),
		grassColor       = Color3.fromRGB(40, 10, 30),
		pathColor        = Color3.fromRGB(20, 5, 15),
		ambientColor     = Color3.fromRGB(60, 20, 50),
		fogColor         = Color3.fromRGB(100, 20, 80),
		auraHolderColor  = Color3.fromRGB(255, 100, 200),
		auraHolderGlow   = Color3.fromRGB(255, 0, 150),
		lightingPreset   = "Area13_Neon", 
		auraModels       = { Common = "NeonTube", Uncommon = "PlasmaArc", Rare = "LaserDiode", Epic = "HardLight", Legendary = "PhotonCell" }
	},
	[14] = {
		name             = "Quantum Mechanics",
		threshold        = 5e62,
		valueMultiplier  = 1e14,
		yOffset          = -4.5,
		yRotation        = 180,
		auraPreviewColor = Color3.fromRGB(255, 255, 255),
		grassColor       = Color3.fromRGB(200, 200, 255),
		pathColor        = Color3.fromRGB(150, 150, 200),
		ambientColor     = Color3.fromRGB(100, 100, 150),
		fogColor         = Color3.fromRGB(200, 200, 255),
		auraHolderColor  = Color3.fromRGB(255, 255, 255),
		auraHolderGlow   = Color3.fromRGB(100, 200, 255),
		lightingPreset   = "Area14_Quantum", 
		auraModels       = { Common = "Quark", Uncommon = "Tachyon", Rare = "Boson", Epic = "Tesseract", Legendary = "SchrodingerCat" }
	},
	[15] = {
		name             = "Celestial Matter",
		threshold        = 5e75,
		valueMultiplier  = 5e16,
		yOffset          = -4.5,
		yRotation        = 180,
		auraPreviewColor = Color3.fromRGB(150, 200, 255),
		grassColor       = Color3.fromRGB(30, 40, 60),
		pathColor        = Color3.fromRGB(20, 25, 40),
		ambientColor     = Color3.fromRGB(40, 50, 80),
		fogColor         = Color3.fromRGB(80, 100, 150),
		auraHolderColor  = Color3.fromRGB(200, 230, 255),
		auraHolderGlow   = Color3.fromRGB(100, 150, 255),
		lightingPreset   = "Area15_Celestial", 
		auraModels       = { Common = "MoonRock", Uncommon = "MarsDust", Rare = "CometIce", Epic = "AsteroidCore", Legendary = "SolarFlare" }
	},
	[16] = {
		name             = "Cosmic Phenomena",
		threshold        = 5e90,
		valueMultiplier  = 2e19,
		yOffset          = -4.5,
		yRotation        = 180,
		auraPreviewColor = Color3.fromRGB(200, 50, 255),
		grassColor       = Color3.fromRGB(20, 10, 40),
		pathColor        = Color3.fromRGB(10, 5, 20),
		ambientColor     = Color3.fromRGB(40, 20, 80),
		fogColor         = Color3.fromRGB(80, 30, 150),
		auraHolderColor  = Color3.fromRGB(255, 150, 255),
		auraHolderGlow   = Color3.fromRGB(150, 50, 255),
		lightingPreset   = "Area16_Cosmic", 
		auraModels       = { Common = "Stardust", Uncommon = "PulsarPulse", Rare = "QuasarLight", Epic = "SupernovaRemnant", Legendary = "GalaxySpiral" }
	},
	[17] = {
		name             = "Dark Matter",
		threshold        = 5e108,
		valueMultiplier  = 1e22,
		yOffset          = -4.5,
		yRotation        = 180,
		auraPreviewColor = Color3.fromRGB(20, 0, 40),
		grassColor       = Color3.fromRGB(10, 0, 15),
		pathColor        = Color3.fromRGB(5, 0, 10),
		ambientColor     = Color3.fromRGB(15, 5, 30),
		fogColor         = Color3.fromRGB(5, 0, 10),
		auraHolderColor  = Color3.fromRGB(50, 0, 100),
		auraHolderGlow   = Color3.fromRGB(255, 0, 50),
		lightingPreset   = "Area17_DarkMatter", 
		auraModels       = { Common = "ShadowMatter", Uncommon = "VoidResidue", Rare = "EventHorizon", Epic = "Singularity", Legendary = "HawkingRadiation" }
	},
	[18] = {
		name             = "Multiversal Elements",
		threshold        = 5e128,
		valueMultiplier  = 5e25,
		yOffset          = -4.5,
		yRotation        = 180,
		auraPreviewColor = Color3.fromRGB(0, 255, 255),
		grassColor       = Color3.fromRGB(30, 30, 30),
		pathColor        = Color3.fromRGB(15, 15, 15),
		ambientColor     = Color3.fromRGB(50, 50, 50),
		fogColor         = Color3.fromRGB(100, 200, 255),
		auraHolderColor  = Color3.fromRGB(255, 0, 255),
		auraHolderGlow   = Color3.fromRGB(0, 255, 255),
		lightingPreset   = "Area18_Multiverse", 
		auraModels       = { Common = "Paradox", Uncommon = "TimelineThread", Rare = "ParallelShard", Epic = "AlternateReality", Legendary = "MultiverseCore" }
	},
	[19] = {
		name             = "Pure Energy",
		threshold        = 5e150,
		valueMultiplier  = 2e29,
		yOffset          = -4.5,
		yRotation        = 180,
		auraPreviewColor = Color3.fromRGB(255, 255, 200),
		grassColor       = Color3.fromRGB(200, 200, 150),
		pathColor        = Color3.fromRGB(255, 255, 200),
		ambientColor     = Color3.fromRGB(255, 255, 255),
		fogColor         = Color3.fromRGB(255, 255, 200),
		auraHolderColor  = Color3.fromRGB(255, 255, 255),
		auraHolderGlow   = Color3.fromRGB(255, 255, 150),
		lightingPreset   = "Area19_PureEnergy", 
		auraModels       = { Common = "Static", Uncommon = "Kinetic", Rare = "Thermal", Epic = "Ethereal", Legendary = "InfiniteEnergy" }
	},
	[20] = {
		name             = "The Absolute",
		threshold        = 5e175,
		valueMultiplier  = 1e34,
		yOffset          = -4.5,
		yRotation        = 180,
		auraPreviewColor = Color3.fromRGB(255, 215, 0),
		grassColor       = Color3.fromRGB(255, 255, 255),
		pathColor        = Color3.fromRGB(200, 200, 200),
		ambientColor     = Color3.fromRGB(255, 240, 200),
		fogColor         = Color3.fromRGB(255, 255, 255),
		auraHolderColor  = Color3.fromRGB(255, 215, 0),
		auraHolderGlow   = Color3.fromRGB(255, 255, 255),
		lightingPreset   = "Area20_TheAbsolute", 
		auraModels       = { Common = "Concept", Uncommon = "Truth", Rare = "Existence", Epic = "Reality", Legendary = "Omnipotence" }
	},

	-- ✨ SPECIAL: THE GOLDEN VAULT (Piggy Bank)
	["PiggyBank"] = {
		name             = "The Golden Vault",
		isSpecial        = true,
		valueMultiplier  = 1.0,
		yOffset          = -4.5,
		yRotation        = 0,
		auraPreviewColor = Color3.fromRGB(255, 215, 0),
		grassColor       = Color3.fromRGB(255, 230, 100),
		pathColor        = Color3.fromRGB(255, 200, 50),
		ambientColor     = Color3.fromRGB(255, 215, 0),
		fogColor         = Color3.fromRGB(255, 240, 150),
		auraHolderColor  = Color3.fromRGB(255, 255, 255),
		auraHolderGlow   = Color3.fromRGB(255, 215, 0),
		lightingPreset   = "Area_PiggyBank",
		icon             = "rbxassetid://14949477468",
		auraModels       = { Common = "GoldenCube" }
	}
}

function AreaRegistry.Get(idx)            return AreaRegistry.Areas[idx] end
function AreaRegistry.GetName(idx)        return (AreaRegistry.Areas[idx] and AreaRegistry.Areas[idx].name) or ("Area "..idx) end
function AreaRegistry.GetThreshold(idx)   return AreaRegistry.Areas[idx] and AreaRegistry.Areas[idx].threshold or nil end
function AreaRegistry.GetMultiplier(idx)  return (AreaRegistry.Areas[idx] and AreaRegistry.Areas[idx].valueMultiplier) or 1.0 end
function AreaRegistry.GetYOffset(idx)     return (AreaRegistry.Areas[idx] and AreaRegistry.Areas[idx].yOffset)    or 0 end
function AreaRegistry.GetYRotation(idx)   return (AreaRegistry.Areas[idx] and AreaRegistry.Areas[idx].yRotation)  or 0 end

function AreaRegistry.GetFlipbook(idx)
	local area = AreaRegistry.Areas[idx]
	if not area or not area.flipbookImage then return nil end
	return {
		image = area.flipbookImage,
		frames = area.flipbookFrames or 1,
		fps = area.flipbookFPS or 12,
		frameW = area.flipbookFrameW or 128,
		frameH = area.flipbookFrameH or 128,
		columns = area.flipbookColumns or area.flipbookFrames or 1,
	}
end

function AreaRegistry.GetLighting(idx)
	local area = AreaRegistry.Areas[idx]
	if not area or not area.lightingPreset then return AreaRegistry.LightingPresets["ClearDay"] end
	return AreaRegistry.LightingPresets[area.lightingPreset] or AreaRegistry.LightingPresets["ClearDay"]
end

function AreaRegistry.GetMaxArea()
	local max = 0
	for k in pairs(AreaRegistry.Areas) do 
		if type(k) == "number" and k > max then max = k end 
	end
	return max
end

function AreaRegistry.GetBestNextArea(currentArea, farmEvaluation)
	local maxArea  = AreaRegistry.GetMaxArea()
	local bestArea = nil
	for i = currentArea + 1, maxArea do
		local area = AreaRegistry.Areas[i]
		if area and not area.isSpecial and farmEvaluation >= (area.threshold or 0) then
			bestArea = i
		end
	end
	return bestArea
end

function AreaRegistry.CanAdvance(currentArea, farmEvaluation)
	local best = AreaRegistry.GetBestNextArea(currentArea, farmEvaluation)
	if best then return true, best end
	return false, nil
end

-- =====================================================================
-- 3-STEP FALLBACK HELPER: FETCHES 3D MODEL SAFELY
-- =====================================================================
function AreaRegistry.FetchAuraModel(areaIndex, rarityName)
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local AreaAssets = ReplicatedStorage:FindFirstChild("AreaAssets")
	local GlobalAuras = ReplicatedStorage:FindFirstChild("Auras")

	local areaConfig = AreaRegistry.Areas[areaIndex]
	if not areaConfig then return nil end

	local expectedModelName = areaConfig.auraModels and areaConfig.auraModels[rarityName]

	if expectedModelName and AreaAssets then
		local areaFolder = AreaAssets:FindFirstChild("Area" .. tostring(areaIndex))

		if type(areaIndex) == "string" then
			areaFolder = AreaAssets:FindFirstChild(areaIndex)
		end

		if areaFolder and areaFolder:FindFirstChild("Auras") then
			local specificModel = areaFolder.Auras:FindFirstChild(expectedModelName)
			if specificModel then
				return specificModel:Clone() 
			end
		end

		-- Do not warn if this is a special area designed to bypass normal loading
		if not areaConfig.isSpecial then
			warn("[AreaRegistry] Missing physical model: " .. tostring(expectedModelName) .. " in Area " .. tostring(areaIndex) .. ". Falling back to placeholder.")
		end
	end

	if GlobalAuras then
		local placeholderModel = GlobalAuras:FindFirstChild(rarityName)
		if placeholderModel then
			return placeholderModel:Clone() 
		end
	end

	if not areaConfig.isSpecial then
		warn("CRITICAL [AreaRegistry]: No custom model OR placeholder found for rarity: " .. tostring(rarityName))
	end

	return nil
end

return AreaRegistry
