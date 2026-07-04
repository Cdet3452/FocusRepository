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

-- FIX 2: Added pcalls with error capture, warning logs, and correct lastSaveTick logic
local function SaveData(player)
	local uid  = player.UserId
	local data = PlayerData[uid]
	if not data then return end
	local now, last = tick(), lastSaveTick[uid] or 0

	if now - last >= SAVE_COOLDOWN then
		local success, err = pcall(function() PlayerDB:SetAsync("Player_" .. uid, data) end)
		if success then
			lastSaveTick[uid] = tick()
		else
			warn("[GameManager] Immediate save failed for " .. uid .. ": " .. tostring(err))
		end
	else
		if not pendingSave[uid] then
			pendingSave[uid] = true
			task.delay(SAVE_COOLDOWN - (now - last) + 0.5, function()
				pendingSave[uid] = nil
				if player and player.Parent and PlayerData[uid] then
					local success, err = pcall(function() PlayerDB:SetAsync("Player_" .. uid, PlayerData[uid]) end)
					if success then
						lastSaveTick[uid] = tick()
					else
						warn("[GameManager] Delayed save failed for " .. uid .. ": " .. tostring(err))
					end
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

-- FIX 1: Bypass cooldown entirely on leaving, force immediate unthrottled save, capture errors
Players.PlayerRemoving:Connect(function(player)
	local uid = player.UserId
	local data = PlayerData[uid]
	if data then
		local success, err = pcall(function()
			PlayerDB:SetAsync("Player_" .. uid, data)
		end)
		if not success then
			warn("[GameManager] Failed to save data for player " .. uid .. " on leave: " .. tostring(err))
		end
	end

	PlayerData[uid] = nil
	PlayerRuntime[uid] = nil
	lastSaveTick[uid] = nil
	pendingSave[uid] = nil
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

local AdminConfig       = require(ReplicatedStorage.Modules.AdminConfig)
local UpgradeConfig     = require(ReplicatedStorage.Modules.UpgradeConfig)
local EpicUpgradeConfig = require(ReplicatedStorage.Modules:WaitForChild("EpicUpgradeConfig"))
local MutationConfig    = require(ReplicatedStorage.Modules.MutationConfig)
local GameManager       = require(ServerScriptService.GameManager)
local BoostManager      = require(ServerScriptService.BoostManager)

local PurchaseUpgrade     = ReplicatedStorage.RemoteEvents:WaitForChild("PurchaseUpgrade")
local UpgradeUpdated      = ReplicatedStorage.RemoteEvents:WaitForChild("UpgradeUpdated")
local PurchaseEpicUpgrade = ReplicatedStorage.RemoteEvents:WaitForChild("PurchaseEpicUpgrade")
local EpicUpgradeUpdated  = ReplicatedStorage.RemoteEvents:WaitForChild("EpicUpgradeUpdated")

-- ✨ BRIDGENET2 UPGRADE
local BridgeNet2      = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))
local UpdateHUDBridge = BridgeNet2.ServerBridge("UpdateHUD")

-- ✨ THE FIX: Replaced strict time cooldowns with a generous per-frame batch limit!
-- This allows ultra-fast holding without the server dropping your network requests.
local purchasesThisFrame = {}
game:GetService("RunService").Heartbeat:Connect(function()
	table.clear(purchasesThisFrame)
end)

-- Mapping the Index Rewards to the Upgrade Tiers to scale Bank filling
local TierFillAmounts = {
	[1] = 5,

	[2] = 10,

	[3] = 15,

	[4] = 25,

	[5] = 50,

	[6] = 75,

	[7] = 125,
	[8] = 175,
	[9] = 250,
	[10] = 500
}

local function GetUpgradeTierIndex(upgradeId, isEpic)
	local config = isEpic and EpicUpgradeConfig or UpgradeConfig
	for idx, tierData in ipairs(config.Tiers) do
		if tierData.upgrades[upgradeId] then
			return idx
		end
	end
	return 1
end

local function SendFullUpgradeState(player)
	local data = GameManager.GetData(player.UserId)
	if not data then return end

	local state = {}
	for tierNum, tierData in ipairs(UpgradeConfig.Tiers) do
		for upgradeId, cfg in pairs(tierData.upgrades) do
			local currentLevel = data.upgrades[upgradeId] or 0
			state[upgradeId] = {
				level    = currentLevel,
				maxLevel = cfg.maxLevel,
				-- Passed "data" in here to respect the dynamic `habitatDiscount`
				cost     = currentLevel < cfg.maxLevel and UpgradeConfig.CalculateCost(upgradeId, currentLevel, data) or 0,
				maxed    = currentLevel >= cfg.maxLevel,
			}
		end
	end

	UpgradeUpdated:FireClient(player, {
		type     = "fullState",
		upgrades = state,
		currency = data.currency,
	})

	local epicState = {}
	if data.epicUpgrades then
		for tierNum, tierData in ipairs(EpicUpgradeConfig.Tiers) do
			for upgradeId, cfg in pairs(tierData.upgrades) do
				local currentLevel = data.epicUpgrades[upgradeId] or 0
				epicState[upgradeId] = {
					level    = currentLevel,
					maxLevel = cfg.maxLevel,
					cost     = currentLevel < cfg.maxLevel and EpicUpgradeConfig.CalculateCost(upgradeId, currentLevel) or 0,
					maxed    = currentLevel >= cfg.maxLevel,
				}
			end
		end

		EpicUpgradeUpdated:FireClient(player, {
			type        = "fullState",
			upgrades    = epicState,
			goldenAuras = data.goldenAuras
		})
	end


end

Players.PlayerAdded:Connect(function(player)
	task.wait(2)
	SendFullUpgradeState(player)
end)

local function SendHUDAfterPurchase(player, data)
	local uid     = player.UserId
	local runtime = GameManager.GetRuntime(uid)
	if not runtime then return end

	local storedCount = runtime.storedCubeCount or 0
	local activeMV    = runtime.activeMutatedValue or 0

	local boostMult = BoostManager.GetValueMultiplier(uid) * BoostManager.GetSpawnRateMultiplier(uid)
	local rate = math.floor(activeMV * boostMult)

	local upgradesState = {}
	for upgradeId, level in pairs(data.upgrades or {}) do
		upgradesState[upgradeId] = { level = level }
	end

	local epicUpgradesState = {}
	for upgradeId, level in pairs(data.epicUpgrades or {}) do
		epicUpgradesState[upgradeId] = { level = level }
	end

	UpdateHUDBridge:Fire(player, {
		currency        = data.currency,
		goldenAuras     = data.goldenAuras,
		pendingAuras    = storedCount,
		habitatCapacity = UpgradeConfig.GetHabitatCapacity(data),
		shipCapacity    = UpgradeConfig.GetShippingCapacity(data) or AdminConfig.PlatformCapacity,
		rate            = rate,
		passiveInterval = UpgradeConfig.GetPassiveInterval(data),
		totalEarned     = data.totalEarned    or 0,
		soulAuras       = data.soulAuras      or 0,
		farmEvaluation  = data.farmEvaluation or 0,
		upgrades        = upgradesState, 
		epicUpgrades    = epicUpgradesState
	})


end

-- 1. Regular Upgrades
PurchaseUpgrade.OnServerEvent:Connect(function(player, upgradeId)
	local uid = player.UserId

	if type(upgradeId) ~= "string" then return end

	-- Allow up to 20 purchases per physics frame (perfect for high-speed holding)
	purchasesThisFrame[uid] = (purchasesThisFrame[uid] or 0) + 1
	if purchasesThisFrame[uid] > 20 then return end

	local cfg = UpgradeConfig.GetUpgradeConfig(upgradeId)
	if not cfg then return end

	local data = GameManager.GetData(uid)
	if not data then return end
	if not data.upgrades then data.upgrades = {} end

	local currentLevel = data.upgrades[upgradeId] or 0
	if currentLevel >= cfg.maxLevel then return end

	-- Passed "data" in here to respect the dynamic `habitatDiscount`
	local cost = UpgradeConfig.CalculateCost(upgradeId, currentLevel, data)
	if data.currency < cost then return end

	data.currency            = data.currency - cost
	data.upgrades[upgradeId] = currentLevel + 1
	local newLevel           = currentLevel + 1

	local nextCost = 0
	if newLevel < cfg.maxLevel then
		nextCost = UpgradeConfig.CalculateCost(upgradeId, newLevel, data)
	end

	GameManager.SavePlayer(player)

	UpgradeUpdated:FireClient(player, {
		type      = "purchased",
		upgradeId = upgradeId,
		level     = newLevel,
		maxLevel  = cfg.maxLevel,
		cost      = nextCost,
		maxed     = newLevel >= cfg.maxLevel,
		currency  = data.currency,
	})

	local tierIndex = GetUpgradeTierIndex(upgradeId, false)
	local fillAmount = TierFillAmounts[tierIndex] or 5
	local BankFillEvent = ServerScriptService:FindFirstChild("BankFillEvent")
	if BankFillEvent then
		BankFillEvent:Fire(uid, fillAmount)
	end

	SendHUDAfterPurchase(player, data)


end)

-- 2. Epic Upgrades (Research)
PurchaseEpicUpgrade.OnServerEvent:Connect(function(player, upgradeId)
	local uid = player.UserId

	if type(upgradeId) ~= "string" then return end

	-- Allow up to 20 purchases per physics frame (perfect for high-speed holding)
	purchasesThisFrame[uid] = (purchasesThisFrame[uid] or 0) + 1
	if purchasesThisFrame[uid] > 20 then return end

	local cfg = EpicUpgradeConfig.GetUpgradeConfig(upgradeId)
	if not cfg then return end

	local data = GameManager.GetData(uid)
	if not data then return end
	if not data.epicUpgrades then data.epicUpgrades = {} end

	local currentLevel = data.epicUpgrades[upgradeId] or 0
	if currentLevel >= cfg.maxLevel then return end

	local cost = EpicUpgradeConfig.CalculateCost(upgradeId, currentLevel)
	if (data.goldenAuras or 0) < cost then return end

	data.goldenAuras = data.goldenAuras - cost
	data.epicUpgrades[upgradeId] = currentLevel + 1
	local newLevel = currentLevel + 1

	local nextCost = 0
	if newLevel < cfg.maxLevel then
		nextCost = EpicUpgradeConfig.CalculateCost(upgradeId, newLevel)
	end

	GameManager.SavePlayer(player)

	EpicUpgradeUpdated:FireClient(player, {
		type        = "purchased",
		upgradeId   = upgradeId,
		level       = newLevel,
		maxLevel    = cfg.maxLevel,
		cost        = nextCost,
		maxed       = newLevel >= cfg.maxLevel,
		goldenAuras = data.goldenAuras,
	})

	local tierIndex = GetUpgradeTierIndex(upgradeId, true)
	local fillAmount = TierFillAmounts[tierIndex] or 25
	local BankFillEvent = ServerScriptService:FindFirstChild("BankFillEvent")
	if BankFillEvent then
		BankFillEvent:Fire(uid, fillAmount)
	end

	SendHUDAfterPurchase(player, data)


end)

Players.PlayerRemoving:Connect(function(player)
	purchasesThisFrame[player.UserId] = nil
end)

return {}

-- EpicUpgradeManager
-- Location: ServerScriptService > EpicUpgradeManager

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local EpicUpgradeConfig = require(ReplicatedStorage.Modules.EpicUpgradeConfig)
local GameManager       = require(ServerScriptService.GameManager)

local PurchaseEpicUpgrade = ReplicatedStorage.RemoteEvents:WaitForChild("PurchaseEpicUpgrade")
local EpicUpgradeUpdated  = ReplicatedStorage.RemoteEvents:WaitForChild("EpicUpgradeUpdated")

-- ✨ BRIDGENET2 UPGRADE
local BridgeNet2      = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))
local UpdateHUDBridge = BridgeNet2.ServerBridge("UpdateHUD")

PurchaseEpicUpgrade.OnServerEvent:Connect(function(player, upgradeId)
	local uid, data = player.UserId, GameManager.GetData(player.UserId)
	if not data then return end
	local cfg = EpicUpgradeConfig.GetUpgradeConfig(upgradeId)
	if not cfg then return end
	if not data.epicUpgrades then data.epicUpgrades = {} end

	local lv = data.epicUpgrades[upgradeId] or 0
	if lv >= cfg.maxLevel then return end

	local cost = EpicUpgradeConfig.CalculateCost(upgradeId, lv)
	if (data.goldenAuras or 0) < cost then return end

	data.goldenAuras = data.goldenAuras - cost
	data.epicUpgrades[upgradeId] = lv + 1

	local newLv = lv + 1
	local maxed = newLv >= cfg.maxLevel

	EpicUpgradeUpdated:FireClient(player, {
		type = "purchased", 
		upgradeId = upgradeId, 
		level = newLv,
		maxLevel = cfg.maxLevel, 
		-- ✨ FIX: Used `newLv` instead of `lv` to accurately show the NEXT cost!
		cost = maxed and 0 or EpicUpgradeConfig.CalculateCost(upgradeId, newLv), 
		maxed = maxed,
	})

	UpdateHUDBridge:Fire(player, { goldenAuras = data.goldenAuras })
	GameManager.SavePlayer(player)
end)

local function SendFullState(player)
	local data = GameManager.GetData(player.UserId)
	if not data then return end
	local ep = data.epicUpgrades or {}; local payload = {}

	for _, tierData in ipairs(EpicUpgradeConfig.Tiers) do
		for id, cfg in pairs(tierData.upgrades) do
			local lv = ep[id] or 0
			local maxed = lv >= cfg.maxLevel
			local cost = maxed and 0 or EpicUpgradeConfig.CalculateCost(id, lv)

			payload[id] = {
				level = lv, 
				maxLevel = cfg.maxLevel, 
				cost = cost,
				maxed = maxed
			}
		end
	end

	EpicUpgradeUpdated:FireClient(player, { type="fullState", upgrades=payload, goldenAuras=data.goldenAuras or 0 })
end

Players.PlayerAdded:Connect(function(player) task.wait(2); SendFullState(player) end)

local EpicUpgradeManager = {}

function EpicUpgradeManager.GetBonus(uid, upgradeId)
	local cfg = EpicUpgradeConfig.GetUpgradeConfig(upgradeId)
	if not cfg then return 0 end
	local data = GameManager.GetData(uid)
	return cfg.apply(data or { epicUpgrades = {} })
end

function EpicUpgradeManager.GetAllBonuses(uid)
	local data = GameManager.GetData(uid) or { epicUpgrades = {} }
	local b = {}
	for _, tierData in ipairs(EpicUpgradeConfig.Tiers) do
		for id, cfg in pairs(tierData.upgrades) do
			b[id] = cfg.apply(data)
		end
	end
	return b
end

function EpicUpgradeManager.ResendState(player) SendFullState(player) end

return EpicUpgradeManager

-- UpgradeConfig
-- Location: ReplicatedStorage > Modules > UpgradeConfig
local AdminConfig = require(script.Parent.AdminConfig)
local UpgradeConfig = {}

UpgradeConfig.Tiers = {
	[1] = {
		tierName = "Tier 1",
		unlockRequirement = 0,
		upgrades = {
			blockValue = {
				baseCost = 45, costScale = 1.03, maxLevel = 100,
				apply = function(data) return ((data.upgrades and data.upgrades.blockValue) or 0) * 0.1 end,
				displayName = "Glow Enhancement", description = "Increases base aura value by +10%", iconId = "rbxassetid://98075952013490",
			},
			hatcheryCapacity = {
				baseCost = 225, costScale = 1.12, maxLevel = 50,
				apply = function(data) return ((data.upgrades and data.upgrades.hatcheryCapacity) or 0) * 1 end,
				displayName = "Aura Expansion", description = "Increases the max capacity of your Hatchery by 1", iconId = "rbxassetid://140457223774888",
			},
			habitatCapacity = {
				baseCost = 425, costScale = 1.12, maxLevel = 25,
				apply = function(data) return ((data.upgrades and data.upgrades.habitatCapacity) or 0) * 2 end,
				displayName = "Habitat Reservoir", description = "Increase habitat capacity by 2", iconId = "rbxassetid://78419118472133",
			},
			unlockMythicMult = { 
				baseCost = 2500, costScale = 1, maxLevel = 1, 
				apply = function(data) return ((data.upgrades and data.upgrades.unlockMythicMult) or 0) == 1 end,
				displayName = "Mythic Multiplier",
				description = "Allows you to hold past the legendary multiplier! Unlocks the " .. (AdminConfig.MilestoneData[6] and AdminConfig.MilestoneData[6].name or "MYTHIC") .. " tier!",
				iconId = "rbxassetid://113828358885527",
			},
		}
	},
	[2] = {
		tierName = "Tier 2",
		unlockRequirement = 150,
		upgrades = {
			blockValueT2 = {
				baseCost = 1000, costScale = 1.05, maxLevel = 125,
				apply = function(data) return ((data.upgrades and data.upgrades.blockValueT2) or 0) * 0.25 end,
				displayName = "Faster Aura Pulse", description = "Increased aura value by +25%", iconId = "rbxassetid://114779329450267",
			},
			passiveTickSpeedT2 = {
				baseCost = 20000, costScale = 1.45, maxLevel = 5,
				apply = function(data) return ((data.upgrades and data.upgrades.passiveTickSpeedT2) or 0) * 0.05 end,
				displayName = "Advanced Aura Generation", description = "Speeds Up Passive Aura Rate By 0.05s", iconId = "rbxassetid://101759432122769",
			},	
			shipCapacityT1 = {
				baseCost = 8000, costScale = 1.25, maxLevel = 25,
				apply = function(data) return ((data.upgrades and data.upgrades.shipCapacityT1) or 0) * 1 end,	iconId = "rbxassetid://121937028282282",
				displayName = "Shipping Expansion", description = "Increases the max auras a ship can carry by 1.",
			},
			autoDispatchSpeed = {
				baseCost = 15000, costScale = 1.1, maxLevel = 5,
				apply = function(data) return ((data.upgrades and data.upgrades.autoDispatchSpeed) or 0) * 0.1 end,
				displayName = "Premium Fuel", description = "Auto Shipping Speed decreased by 1 Second", iconId = "rbxassetid://72413676865208",
			},
		}
	},
	[3] = {
		tierName = "Tier 3",
		unlockRequirement = 150, 
		upgrades = {
			auraValueT3 = {
				baseCost = 250000, costScale = 1.5, maxLevel = 4,
				apply = function(data) return ((data.upgrades and data.upgrades.auraValueT3) or 0) * 0.5 end,
				displayName = "Aura Purifier", description = "Purifies Your Auras, Increases Value by 50%",  iconId = "rbxassetid://104033623069082",
			},
			hatcheryT3 = {
				baseCost = 300000, costScale = 1.05, maxLevel = 25,
				apply = function(data) return ((data.upgrades and data.upgrades.hatcheryT3) or 0) * 2 end,
				displayName = "Increased Hatchery", description = "Provides even more hatchery space for more auras by 2",  iconId = "rbxassetid://93371640313869",
			},
			habitatT3 = {
				baseCost = 2000000, costScale = 1.4, maxLevel = 15,
				apply = function(data) return ((data.upgrades and data.upgrades.habitatT3) or 0) * 10 end,
				displayName = "Industrial Packaging", description = "Increases Habitat Capacity by 10",  iconId = "rbxassetid://78525019638530",
			},
			droneFrequency = {
				baseCost = 100000, costScale = 1.02, maxLevel = 25,
				apply = function(data) return ((data.upgrades and data.upgrades.droneFrequency) or 0) * 0.1 end,
				displayName = "Unstable Shots", description = "Random Aura Shots happen More Frequently by +1%",  iconId = "rbxassetid://133715967622098",
			},
		}
	},
	[4] = {
		tierName = "Tier 4",
		unlockRequirement = 225, 
		upgrades = {
			auraValueT4 = {
				baseCost = 15000000, costScale = 1.03, maxLevel = 250,
				apply = function(data) return ((data.upgrades and data.upgrades.auraValueT4) or 0) * 0.5 end,
				displayName = "Shinier Auras", description = "Auras Shine Brighter and increase value by 5%",  iconId = "rbxassetid://126092269539671",
			},
			hatcheryT4 = {
				baseCost = 40000000, costScale = 1.05, maxLevel = 20,
				apply = function(data) return ((data.upgrades and data.upgrades.hatcheryT4) or 0) * 5 end,
				displayName = "Advanced Hatchery", description = "Increases Hatchery by 5",  iconId = "rbxassetid://137765991302601",
			},
			autoDispatchSpeedT4 = {
				baseCost = 50000000, costScale = 2, maxLevel = 3,
				apply = function(data) return ((data.upgrades and data.upgrades.autoDispatchSpeed) or 0) * 0.1 end,
				displayName = "Powerful Engines", description = "Auto Shipping Speed decreased by 3 Seconds",  iconId = "rbxassetid://107466504388101",
			},
			conveyerSpeedT1 = {
				baseCost = 15000000, costScale = 2, maxLevel = 10,
				apply = function(data) return ((data.upgrades and data.upgrades.auraValueT6) or 0) * 0.1 end,
				displayName = "Speedy Conveyers", description = "Increases Conveyer Speed by 1%",  iconId = "rbxassetid://134975192722597",
			},
		}
	},
	[5] = {
		tierName = "Tier 5",
		unlockRequirement = 200,
		upgrades = {
			habitatT5 = {
				baseCost = 5e8, costScale = 1.05, maxLevel = 50,
				apply = function(data) return ((data.upgrades and data.upgrades.habitatT5) or 0) * 5 end,
				displayName = "Deep Habitats", description = "House More Auras, Increases Habitat Space by 5",  iconId = "rbxassetid://127255411690284",
			},
			unlockCosmicMult = { 
				baseCost = 2.5e9, costScale = 1, maxLevel = 1, 
				apply = function(data) return ((data.upgrades and data.upgrades.unlockCosmicMult) or 0) == 1 end,
				displayName = "Cosmic Multiplier", 
				description = "Breaks the Mythic limit, unlocking the " .. (AdminConfig.MilestoneData[7] and AdminConfig.MilestoneData[7].name or "COSMIC") .. " tier!",   iconId = "rbxassetid://80891448925628",
			},
			auraValueT5 = {
				baseCost = 1.5e9, costScale = 1.01, maxLevel = 500,
				apply = function(data) return ((data.upgrades and data.upgrades.auraValueT5) or 0) * 0.1 end,
				displayName = "Auric Infuser", description = "Infuse auras with eachother increasing value by 1%",  iconId = "rbxassetid://140398335441235",
			},
			shipCapacityT2 = {
				baseCost = 5e8, costScale = 1.10, maxLevel = 20,
				apply = function(data) return ((data.upgrades and data.upgrades.shipCapacityT2) or 0) * 2 end,
				displayName = "Ships 'In' Ships", description = "Increases the max auras a ship can carry by 2.",  iconId = "rbxassetid://73988181106956",
			},
		}
	},
	[6] = {
		tierName = "Tier 6",
		unlockRequirement = 300,
		upgrades = {
			passiveSpeedT6 = {
				baseCost = 5e10, costScale = 1.5, maxLevel = 25,
				apply = function(data) return ((data.upgrades and data.upgrades.passiveSpeedT6) or 0) * 0.1 end,
				displayName = "Faster Than Light", description = "Auras spawn before you even need them (-0.1s delay).",
			},
			auraValueT6 = {
				baseCost = 1.5e11, costScale = 1.3, maxLevel = 200,
				apply = function(data) return ((data.upgrades and data.upgrades.auraValueT6) or 0) * 5.0 end,
				displayName = "Tachyon Infusion", description = "Infuse auras with speed particles for +500% value per level.",
			},
			doubleSpawnChance = {
				baseCost = 2e10, costScale = 1.35, maxLevel = 25,
				apply = function(data) return ((data.upgrades and data.upgrades.doubleSpawnChance) or 0) * 1 end,
				displayName = "Mitosis Splitting", description = "1% chance for a spawner to generate two auras at once.",
			},
			offlineTimeCap = {
				baseCost = 3.5e10, costScale = 1.4, maxLevel = 25,
				apply = function(data) return ((data.upgrades and data.upgrades.offlineTimeCap) or 0) * 1 end,
				displayName = "Stasis Batteries", description = "Increases max offline earnings time by 1 hour.",
			},
			goldenAuraValue = {
				baseCost = 8e10, costScale = 1.5, maxLevel = 25,
				apply = function(data) return ((data.upgrades and data.upgrades.goldenAuraValue) or 0) * 0.1 end,
				displayName = "Refined Gold", description = "Golden Auras collected grant +10% more premium currency.",
			},
			shippingCapacityT6 = {
				baseCost = 1e11, costScale = 1.45, maxLevel = 25,
				apply = function(data) return ((data.upgrades and data.upgrades.shippingCapacityT6) or 0) * 500 end,
				displayName = "Wormhole Freight", description = "Ships carry +500 more auras through hyperspace.",
			},
			eliteSpawnChance = {
				baseCost = 25000000, costScale = 1.4, maxLevel = 25,
				apply = function(data) return ((data.upgrades and data.upgrades.eliteSpawnChance) or 0) * 1.0 end,
				displayName = "Luckier Shots", description = "Increases the chance of an Elite Aura spawning by 1%.",
			},
		}
	},
	[7] = {
		tierName = "Tier 7",
		unlockRequirement = 500,
		upgrades = {
			hatcheryT7 = {
				baseCost = 1e13, costScale = 1.4, maxLevel = 100,
				apply = function(data) return ((data.upgrades and data.upgrades.hatcheryT7) or 0) * 50 end,
				displayName = "Void Reservoirs", description = "Store energy in the endless void (+50 capacity).",
			},
			habitatT7 = {
				baseCost = 5e13, costScale = 1.45, maxLevel = 100,
				apply = function(data) return ((data.upgrades and data.upgrades.habitatT7) or 0) * 250 end,
				displayName = "Antimatter Containment", description = "Safely store massive amounts of auras (+250 capacity).",
			},
			prestigeMultiplierBonus = {
				baseCost = 2e13, costScale = 1.6, maxLevel = 10,
				apply = function(data) return ((data.upgrades and data.upgrades.prestigeMultiplierBonus) or 0) * 0.05 end,
				displayName = "Soul Memory", description = "Increases the multiplier gained from Prestiging by 5%.",
			},
			droneRewardMulti = {
				baseCost = 8e13, costScale = 1.5, maxLevel = 25,
				apply = function(data) return ((data.upgrades and data.upgrades.droneRewardMulti) or 0) * 0.2 end,
				displayName = "Heavier Payloads", description = "Random drops contain 20% more resources.",
			},
		}
	},
	[8] = {
		tierName = "Tier 8",
		unlockRequirement = 1000,
		upgrades = {
			auraValueT8 = {
				baseCost = 5e15, costScale = 1.35, maxLevel = 250,
				apply = function(data) return ((data.upgrades and data.upgrades.auraValueT8) or 0) * 25.0 end,
				displayName = "Reality Bending", description = "Auras pull value from alternate dimensions (+2,500% value).",
			},
			godlyCritChance = {
				baseCost = 1e16, costScale = 1.4, maxLevel = 25,
				apply = function(data) return ((data.upgrades and data.upgrades.godlyCritChance) or 0) * 0.2 end,
				displayName = "Divine Intervention", description = "0.2% chance for an aura to instantly massively spike its value.",
			},
			habitatT8 = {
				baseCost = 8e16, costScale = 1.5, maxLevel = 100,
				apply = function(data) return ((data.upgrades and data.upgrades.habitatT8) or 0) * 1000 end,
				displayName = "Pocket Universes", description = "Creates entire universes to hold your auras (+1,000 capacity).",
			},
			unlockGodlyMult = { 
				baseCost = 1e17, costScale = 1, maxLevel = 1,
				apply = function(data) return ((data.upgrades and data.upgrades.unlockGodlyMult) or 0) == 1 end,
				displayName = "Godly Multiplier", 
				description = "Reach ascension. Unlocks the " .. (AdminConfig.MilestoneData[8] and AdminConfig.MilestoneData[8].name or "GODLY") .. " tier!",
			},
		}
	},
	[9] = {
		tierName = "Tier 9",
		unlockRequirement = 1500,
		upgrades = {
			habitatT9 = {
				baseCost = 1e19, costScale = 1.5, maxLevel = 150,
				apply = function(data) return ((data.upgrades and data.upgrades.habitatT9) or 0) * 5000 end,
				displayName = "Galaxy Clusters", description = "Your habitats are now comprised of entire galaxies (+5,000 capacity).",
			},
			hatcheryT9 = {
				baseCost = 5e19, costScale = 1.5, maxLevel = 1500,
				apply = function(data) return ((data.upgrades and data.upgrades.hatcheryT9) or 0) * 200 end,
				displayName = "Big Bang Forges", description = "Hatch energy from the birth of new universes (+200 capacity).",
			},
			universalShipping = {
				baseCost = 8e19, costScale = 1.45, maxLevel = 50,
				apply = function(data) return ((data.upgrades and data.upgrades.universalShipping) or 0) * 50000 end,
				displayName = "Teleportation Networks", description = "Instantly beam auras to buyers (+50,000 shipping capacity).",
			},
			unlockUniversalMult = { 
				baseCost = 1e20, costScale = 1, maxLevel = 1, 
				apply = function(data) return ((data.upgrades and data.upgrades.unlockUniversalMult) or 0) == 1 end,
				displayName = "Universal Multiplier", 
				description = "Shatter reality. Unlocks the " .. (AdminConfig.MilestoneData[9] and AdminConfig.MilestoneData[9].name or "UNIVERSAL") .. " tier!",
			},
		}
	},
	[10] = {
		tierName = "Tier 10",
		unlockRequirement = 2500,
		upgrades = {
			auraValueT10 = {
				baseCost = 1e22, costScale = 1.4, maxLevel = 500,
				apply = function(data) return ((data.upgrades and data.upgrades.auraValueT10) or 0) * 150.0 end,
				displayName = "Limitless Potential", description = "The ultimate value upgrade. +15,000% value per level.",
			},
			omniCapacity = {
				baseCost = 5e22, costScale = 1.5, maxLevel = 500,
				apply = function(data) return ((data.upgrades and data.upgrades.omniCapacity) or 0) * 25000 end,
				displayName = "The Final Frontier", description = "Unfathomable space (+25,000 habitat capacity).",
			},
			omniSpeed = {
				baseCost = 8e22, costScale = 1.6, maxLevel = 100,
				apply = function(data) return ((data.upgrades and data.upgrades.omniSpeed) or 0) * 0.2 end,
				displayName = "Time Collapse", description = "Auras generate infinitely fast (-0.2s delay).",
			},
			unlockOmniMult = { 
				baseCost = 5e23, costScale = 1, maxLevel = 1,
				apply = function(data) return ((data.upgrades and data.upgrades.unlockOmniMult) or 0) == 1 end,
				displayName = "Omni Multiplier", 
				description = "The absolute limit. Unlocks the " .. (AdminConfig.MilestoneData[10] and AdminConfig.MilestoneData[10].name or "OMNI") .. " tier!",
			},
		}
	},
}

-- === GLOBAL HELPER FUNCTIONS ===

function UpgradeConfig.GetUpgradeConfig(upgradeId)
	for _, tierData in ipairs(UpgradeConfig.Tiers) do
		if tierData.upgrades[upgradeId] then return tierData.upgrades[upgradeId] end
	end
	return nil
end

function UpgradeConfig.CalculateCost(upgradeId, currentLevel, data)
	local cfg = UpgradeConfig.GetUpgradeConfig(upgradeId)
	if not cfg then return math.huge end
	if currentLevel >= cfg.maxLevel then return math.huge end

	local cost = math.floor(cfg.baseCost * (cfg.costScale ^ currentLevel))

	-- Apply habitat material synthesis discount if applicable
	if data and string.find(string.lower(upgradeId), "habitat") then
		local discountCfg = UpgradeConfig.GetUpgradeConfig("habitatDiscount")
		if discountCfg and discountCfg.apply then
			local discount = discountCfg.apply(data)
			cost = math.floor(cost * (1 - discount))
		end
	end

	return cost
end

function UpgradeConfig.GetHabitatCapacity(data)
	local cap = AdminConfig.BaseHabitatCapacity or 50
	local keys = {"habitatCapacity", "habitatT3", "habitatT5", "habitatT7", "habitatT8", "habitatT9", "omniCapacity"}
	for _, k in ipairs(keys) do
		local cfg = UpgradeConfig.GetUpgradeConfig(k)
		if cfg and cfg.apply then cap = cap + cfg.apply(data) end
	end
	return cap
end

function UpgradeConfig.GetHatcheryMax(data)
	local cap = AdminConfig.HatcheryMax or 100
	local keys = {"hatcheryCapacity", "hatcheryT3", "hatcheryT4", "hatcheryT7", "hatcheryT9"}
	for _, k in ipairs(keys) do
		local cfg = UpgradeConfig.GetUpgradeConfig(k)
		if cfg and cfg.apply then cap = cap + cfg.apply(data) end
	end
	return cap
end

function UpgradeConfig.GetPassiveInterval(data)
	local interval = AdminConfig.PassiveInterval or 10
	local keys = {"passiveTickSpeedT2", "passiveSpeedT6", "omniSpeed"}
	local totalReduction = 0
	for _, k in ipairs(keys) do
		local cfg = UpgradeConfig.GetUpgradeConfig(k)
		if cfg and cfg.apply then totalReduction = totalReduction + cfg.apply(data) end
	end
	return math.max(0.1, interval - totalReduction) -- Cap minimum tick speed to 0.1s
end

function UpgradeConfig.GetTotalValueMultiplier(data)
	local mult = 1.0
	local keys = {"blockValue", "blockValueT2", "auraValueT3", "auraValueT4", "auraValueT5", "auraValueT6", "auraValueT8", "auraValueT10"}
	for _, k in ipairs(keys) do
		local cfg = UpgradeConfig.GetUpgradeConfig(k)
		if cfg and cfg.apply then mult = mult + cfg.apply(data) end
	end
	return mult
end

function UpgradeConfig.GetShippingCapacity(data)
	local cap = AdminConfig.PlatformCapacity or 10
	local keys = {"shipCapacityT1", "shippingCapacityT6", "universalShipping"}
	for _, k in ipairs(keys) do
		local cfg = UpgradeConfig.GetUpgradeConfig(k)
		if cfg and cfg.apply then cap = cap + cfg.apply(data) end
	end
	return cap
end

return UpgradeConfig

local EpicUpgradeConfig = {}

-- 1. TABS REMOVED: Everything sits in one clean panel now!
EpicUpgradeConfig.Tabs = {"Epic"} 

-- 2. DYNAMIC SCALING MATH
local function scaleCost(base, growth, level)
	return math.floor(base * math.pow(growth, level))
end

-- 3. THE UPGRADES
EpicUpgradeConfig.Tiers = {
	{
		tierName = "Permanent Upgrades",
		unlockRequirement = 0,
		upgrades = {
			["epicAuraValue"] = {
				displayName = "Aura Value Multiplier",
				description = "Permanently increases the base value of all generated Auras by +10% per level.",
				iconId = "rbxassetid://79023170440309", 
				maxLevel = 50, category = "Epic", baseCost = 10, costGrowth = 1.3,
				apply = function(d) return 1 + ((d.epicUpgrades and d.epicUpgrades.epicAuraValue) or 0) * 0.1 end
			},
			["epicHoldSpeed"] = {
				displayName = "Turbo Purchasing",
				description = "Increases how fast you buy regular upgrades when holding down the button.",
				iconId = "rbxassetid://83928956442803", 
				maxLevel = 10, category = "Epic", baseCost = 25, costGrowth = 1.5,
				apply = function(d) return 1 + ((d.epicUpgrades and d.epicUpgrades.epicHoldSpeed) or 0) * 0.3 end
			},
			["epicMoveSpeed"] = {
				displayName = "Swiftness",
				description = "Permanently increases your character's walking speed.",
				iconId = "rbxassetid://118830794642672", 
				maxLevel = 15, category = "Epic", baseCost = 15, costGrowth = 1.4,
				apply = function(d) return ((d.epicUpgrades and d.epicUpgrades.epicMoveSpeed) or 0) * 1 end
			},
			["epicClickMilestone"] = {
				displayName = "Milestone Momentum",
				description = "Reduces the clicks/time required to reach the next clicker milestone.",
				iconId = "rbxassetid://79639901121048", 
				maxLevel = 20, category = "Epic", baseCost = 50, costGrowth = 1.6,
				apply = function(d) return ((d.epicUpgrades and d.epicUpgrades.epicClickMilestone) or 0) * 2 end
			},
			["epicPrestigeReward"] = {
				displayName = "Soul Aura Mastery",
				description = "Increases the amount of Soul Auras you receive when prestiging by +5% per level.",
				iconId = "rbxassetid://132836221449559", 
				maxLevel = 25, category = "Epic", baseCost = 100, costGrowth = 1.8,
				apply = function(d) return 1 + ((d.epicUpgrades and d.epicUpgrades.epicPrestigeReward) or 0) * 0.05 end
			},
			["epicShipCooldown"] = {
				displayName = "Shipping Overdrive",
				description = "Permanently decreases the cooldown time of shipping auras by 0.5s per level.",
				iconId = "rbxassetid://128287334405117", 
				maxLevel = 10, category = "Epic", baseCost = 40, costGrowth = 1.5,
				apply = function(d) 
					-- Returns how many seconds to shave off (Level 1 = 0.5s, Level 10 = 5s)
					return ((d.epicUpgrades and d.epicUpgrades.epicShipCooldown) or 0) * 1.5 
				end
			},

			-- =====================================
			-- NEW UPGRADES IMPLEMENTED
			-- =====================================

			["epicShipStorage"] = {
				displayName = "Ship Storage Increase",
				description = "Permanently increases the maximum amount of auras a single ship can carry.",
				iconId = "rbxassetid://119837557643684", 
				maxLevel = 10, category = "Epic", baseCost = 80, costGrowth = 1.6,
				apply = function(d) 
					-- Adds 5 extra slots to platform capacity per level
					return ((d.epicUpgrades and d.epicUpgrades.epicShipStorage) or 0) * 5 
				end
			},
			["epicConveyorThrust"] = {
				displayName = "Golden Conveyer",
				description = "Auras Shot from the Spawner Can Now move on the Conveyer!",
				iconId = "rbxassetid://133910450658029", 
				maxLevel = 1, category = "Epic", baseCost = 150, costGrowth = 1.0,
				apply = function(d) 
					-- Only requires Level 1 to activate logic in ClickHandler
					return (d.epicUpgrades and d.epicUpgrades.epicConveyorThrust) or 0 
				end
			},
			["epicGoldenAuraYield"] = {
				displayName = "Golden Multiplier",
				description = "Increases the amount of Golden Auras you receive when they get shipped.",
				iconId = "rbxassetid://119182511828436", 
				maxLevel = 20, category = "Epic", baseCost = 95, costGrowth = 1.5,
				apply = function(d) 
					-- Yields +1 extra Golden Aura per level
					return ((d.epicUpgrades and d.epicUpgrades.epicGoldenAuraYield) or 0) * 1 
				end
			},
			["epicGoldenChance"] = {
				displayName = "Golden Luck",
				description = "Permanently increases the chance for a shot out aura to be Elite",
				iconId = "rbxassetid://91666080426191", 
				maxLevel = 15, category = "Epic", baseCost = 150, costGrowth = 1.6,
				apply = function(d) 
					-- +2% bonus chance per level
					return ((d.epicUpgrades and d.epicUpgrades.epicGoldenChance) or 0) * 0.02 
				end
			},
			["epicLuck"] = {
				displayName = "Epic Luck Increase",
				description = "Permanently boosts your overall luck percentage by +5% per level, yielding higher tier auras.",
				iconId = "rbxassetid://77583702492506", 
				maxLevel = 25, category = "Epic", baseCost = 200, costGrowth = 1.5,
				apply = function(d) 
					-- Gives +5% luck scaling multiplier
					return ((d.epicUpgrades and d.epicUpgrades.epicLuck) or 0) * 0.05 
				end
			},
			["epicDoubleSpawn"] = {
				displayName = "Aura Duplication",
				description = "Every aura spawned from the spawner is instantly duplicated!",
				iconId = "rbxassetid://76353531333364", 
				maxLevel = 1, category = "Epic", baseCost = 100000, costGrowth = 1.0,
				apply = function(d) 
					-- Binary trigger
					return (d.epicUpgrades and d.epicUpgrades.epicDoubleSpawn) or 0 
				end
			},
		}

	}
}

function EpicUpgradeConfig.GetUpgradeConfig(upgradeId)
	for _, tierData in ipairs(EpicUpgradeConfig.Tiers) do
		if tierData.upgrades[upgradeId] then return tierData.upgrades[upgradeId] end
	end
	return nil
end

function EpicUpgradeConfig.CalculateCost(upgradeId, currentLevel)
	local cfg = EpicUpgradeConfig.GetUpgradeConfig(upgradeId)
	if not cfg then return math.huge end
	if currentLevel >= cfg.maxLevel then return math.huge end
	return scaleCost(cfg.baseCost, cfg.costGrowth, currentLevel)
end

EpicUpgradeConfig.TabColors = { Epic = Color3.fromRGB(150, 80, 255) }
return EpicUpgradeConfig

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local UpgradeConfig     = require(ReplicatedStorage.Modules:WaitForChild("UpgradeConfig"))
local Formatter         = require(ReplicatedStorage.Modules:WaitForChild("NumberFormatter"))
local EpicUpgradeConfig = require(ReplicatedStorage.Modules:WaitForChild("EpicUpgradeConfig"))
local UIConfig          = require(ReplicatedStorage.Modules:WaitForChild("UIConfig"))
local UITheme           = require(ReplicatedStorage.Modules:WaitForChild("UITheme"))
local T                 = UITheme.Get("Custom")
local SoundConfig       = require(ReplicatedStorage.Modules:WaitForChild("SoundConfig"))

local RemoteEvents        = ReplicatedStorage:WaitForChild("RemoteEvents")
local PurchaseUpgrade     = RemoteEvents:WaitForChild("PurchaseUpgrade", 15)
local UpgradeUpdated      = RemoteEvents:WaitForChild("UpgradeUpdated", 15)
local PurchaseEpicUpgrade = RemoteEvents:WaitForChild("PurchaseEpicUpgrade", 15)
local EpicUpgradeUpdated  = RemoteEvents:WaitForChild("EpicUpgradeUpdated", 15)

local ForceCloseUI = ReplicatedStorage:FindFirstChild("ForceCloseUI") or Instance.new("BindableEvent")
ForceCloseUI.Name = "ForceCloseUI"
if not ForceCloseUI.Parent then ForceCloseUI.Parent = ReplicatedStorage end

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainHUD   = playerGui:WaitForChild("MainHUD")

local upgradeState      = {}
local epicUpgradeState  = {}
local currentCurrency   = 0
local liveGoldenAuras   = 0
local shopOpen          = false
local activeMainTab     = "Upgrades"
local regularCardRefs   = {}
local epicCardRefs      = {}
local isLoadingData     = true
local globalHoldActive  = false  
local globalHoldGeneration = 0   

local UpdateLockedTierProgress = nil
local RebuildRegularShop = nil 

for _, tierData in ipairs(UpgradeConfig.Tiers) do
	for upgradeId, cfg in pairs(tierData.upgrades) do
		upgradeState[upgradeId] = { level = 0, maxLevel = cfg.maxLevel, cost = UpgradeConfig.CalculateCost(upgradeId, 0), maxed = false }
	end
end

for _, tierData in ipairs(EpicUpgradeConfig.Tiers) do
	for upgradeId, cfg in pairs(tierData.upgrades) do
		epicUpgradeState[upgradeId] = { level = 0, maxLevel = cfg.maxLevel, cost = EpicUpgradeConfig.CalculateCost(upgradeId, 0), maxed = false }
	end
end

local function PlayUIBurst(targetElement, amount, colorTheme)
	if not shopOpen then return end
	local burstGui = Instance.new("ScreenGui")
	burstGui.Name   = "JuiceBurst"
	burstGui.Parent = playerGui

	local absPos  = targetElement.AbsolutePosition
	local absSize = targetElement.AbsoluteSize
	local center  = absPos + (absSize / 2)

	for i = 1, amount do
		local particle = Instance.new("Frame")
		particle.BackgroundColor3 = colorTheme or Color3.fromRGB(255, 215, 0)
		particle.BorderSizePixel  = 0
		particle.Size             = UDim2.new(0, math.random(6, 12), 0, math.random(6, 12))
		particle.Position         = UDim2.new(0, center.X, 0, center.Y)
		particle.Rotation         = math.random(0, 360)

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent       = particle
		particle.Parent     = burstGui

		local angle    = math.rad(math.random(0, 360))
		local distance = math.random(50, 150)
		local endPos   = UDim2.new(0, center.X + math.cos(angle) * distance, 0, center.Y + math.sin(angle) * distance + 50)

		local tInfo = TweenInfo.new(math.random(4, 7) / 10, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out)
		TweenService:Create(particle, tInfo, { Position = endPos, Size = UDim2.new(0, 0, 0, 0), Rotation = particle.Rotation + math.random(-180, 180), BackgroundTransparency = 1 }):Play()
	end
	task.delay(1, function() burstGui:Destroy() end)
end

local comboPitch  = 1.0
local lastBuyTime = tick()

local function PlayPurchaseSound()
	if tick() - lastBuyTime < 0.3 then comboPitch = math.min(comboPitch + 0.05, 2.5) else comboPitch = 1.0 end
	lastBuyTime = tick()
	local sfxFolder = ReplicatedStorage:FindFirstChild("SFX") or ReplicatedStorage:FindFirstChild("Sounds")
	if sfxFolder and sfxFolder:FindFirstChild("BuyPing") then
		local sfx = sfxFolder.BuyPing:Clone()
		sfx.PlaybackSpeed = comboPitch
		sfx.Parent        = game:GetService("SoundService")
		sfx:Play()
		game.Debris:AddItem(sfx, 2)
	end
end

local function PlayFeedbackSound(soundName, volume)
	local sfxFolder = ReplicatedStorage:FindFirstChild("SFX") or ReplicatedStorage:FindFirstChild("Sounds")
	if sfxFolder then
		local s = sfxFolder:FindFirstChild(soundName)
		if s then
			local sfx = s:Clone()
			sfx.Volume = volume or 0.5
			sfx.Parent = game:GetService("SoundService")
			sfx:Play()
			game.Debris:AddItem(sfx, 3)
		end
	end
end

local lastErrorTime = tick()
local function PlayErrorFeedback(targetButton)
	if tick() - lastErrorTime < 0.25 then return end
	lastErrorTime = tick()
	local sfxFolder = ReplicatedStorage:FindFirstChild("Sounds") or ReplicatedStorage:FindFirstChild("SFX")
	if sfxFolder and sfxFolder:FindFirstChild("ErrorBuzz") then
		local sfx = sfxFolder.ErrorBuzz:Clone()
		sfx.Volume = 0.5
		sfx.Parent = workspace
		sfx:Play()
		game.Debris:AddItem(sfx, 2)
	end
	if targetButton and targetButton.Parent then
		local origPos    = targetButton.Position
		local wobbleInfo = TweenInfo.new(0.04, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 3, true)
		TweenService:Create(targetButton, wobbleInfo, { Position = origPos + UDim2.new(0, 4, 0, 0) }):Play()
	end
end

local function FormatNumber(n) return Formatter.Format(n) end
local function PlayUI(id) if shared.PlayUISound then shared.PlayUISound(id) end end

local ShopButton = Instance.new("ImageButton")
ShopButton.Name              = "ShopButton"
ShopButton.BackgroundColor3  = T.buttonSecondary
ShopButton.BorderSizePixel   = 0
ShopButton.AutoButtonColor   = false
ShopButton.ZIndex            = 15

local Faded2 = mainHUD:FindFirstChild("Faded2")
if Faded2 then
	ShopButton.Parent = Faded2
	ShopButton.Size = UDim2.new(0.85, 0, 0.85, 0)
	local aspect = Instance.new("UIAspectRatioConstraint", ShopButton)
	aspect.AspectRatio = 1.0

	local layout = Faded2:FindFirstChildOfClass("UIListLayout")
	if not layout then
		layout = Instance.new("UIListLayout", Faded2)
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.VerticalAlignment = Enum.VerticalAlignment.Center
		layout.Padding = UDim.new(0, 15)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
	end
	ShopButton.LayoutOrder = 2 
else
	ShopButton.Size = UDim2.new(0, 60, 0, 60)
	ShopButton.AnchorPoint = Vector2.new(0, 0.5)
	ShopButton.Position = UDim2.new(0, 15, 0.5, 0)
	ShopButton.Parent = mainHUD
end

CollectionService:AddTag(ShopButton, "Tutorial_ShopButton")
Instance.new("UICorner", ShopButton).CornerRadius = UDim.new(0.5, 0)

local shopStroke = Instance.new("UIStroke", ShopButton)
shopStroke.Color     = Color3.fromRGB(255, 255, 255)
shopStroke.Thickness = 2

local shopIcon = Instance.new("ImageLabel", ShopButton)
shopIcon.Size               = UDim2.new(0.6, 0, 0.6, 0)
shopIcon.Position           = UDim2.new(0.2, 0, 0.2, 0)
shopIcon.BackgroundTransparency = 1
shopIcon.ScaleType          = Enum.ScaleType.Fit
shopIcon.Image              = UIConfig.Icons.ShopButton or "rbxassetid://14916846070"

local HEADER_H = 44

local ShopPanel = Instance.new("Frame")
ShopPanel.Name              = "ShopPanel"
ShopPanel.Size              = UDim2.new(1, -110, 0.85, 0) 
ShopPanel.AnchorPoint       = Vector2.new(0, 0.5) 
ShopPanel.Position          = UDim2.new(0, -500, 0.5, 0) 
ShopPanel.BackgroundColor3  = T.panelBG
ShopPanel.BorderSizePixel   = 0
ShopPanel.Visible           = false
ShopPanel.ZIndex            = 10
ShopPanel.ClipsDescendants  = true
ShopPanel.Parent            = mainHUD
CollectionService:AddTag(ShopPanel, "Tutorial_ShopPanel") 
Instance.new("UICorner", ShopPanel).CornerRadius = UDim.new(0, 12)

local sizeConstraint = Instance.new("UISizeConstraint")
sizeConstraint.MaxSize = Vector2.new(500, 650)
sizeConstraint.Parent  = ShopPanel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color     = T.panelStroke
panelStroke.Thickness = 2
panelStroke.Parent    = ShopPanel

local TitleBar = Instance.new("Frame")
TitleBar.Name                 = "TitleBar"
TitleBar.Size                 = UDim2.new(1, 0, 0, HEADER_H)
TitleBar.BackgroundColor3     = T.headerBG
TitleBar.BorderSizePixel      = 0
TitleBar.ZIndex               = 11
TitleBar.ClipsDescendants     = true
TitleBar.BackgroundTransparency = 1
TitleBar.Parent               = ShopPanel
Instance.new("UICorner", TitleBar).CornerRadius = UDim.new(0, 12)

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size               = UDim2.new(1, -50, 1, 0)
TitleLabel.Position           = UDim2.new(0, 15, 0, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Text               = "RESEARCH"
TitleLabel.TextColor3         = T.headerText
TitleLabel.TextScaled         = true
TitleLabel.Font               = T.font
TitleLabel.TextXAlignment     = Enum.TextXAlignment.Left
TitleLabel.ZIndex             = 12
TitleLabel.Parent             = TitleBar

local CloseButton = Instance.new("TextButton")
CloseButton.Size             = UDim2.new(0, 28, 0, 28)
CloseButton.Position         = UDim2.new(1, -36, 0.5, -14)
CloseButton.BackgroundColor3 = T.buttonRed
CloseButton.BorderSizePixel  = 0
CloseButton.Text             = "X"
CloseButton.TextColor3       = T.headerText
CloseButton.TextScaled       = true
CloseButton.Font             = T.font
CloseButton.ZIndex           = 9999
CloseButton.Parent           = TitleBar
CollectionService:AddTag(CloseButton, "Tutorial_ShopCloseBtn") 
Instance.new("UICorner", CloseButton).CornerRadius = UDim.new(0, 5)

local InfoPopup = Instance.new("Frame")
InfoPopup.Name                 = "InfoPopup"
InfoPopup.Size                 = UDim2.new(0.85, 0, 0.6, 0)
InfoPopup.Position             = UDim2.new(0.5, 0, 0.5, 0)
InfoPopup.AnchorPoint          = Vector2.new(0.5, 0.5)
InfoPopup.BackgroundColor3     = T.cardBG
InfoPopup.BackgroundTransparency = 0
InfoPopup.ZIndex               = 50
InfoPopup.Visible              = false
InfoPopup.Parent               = ShopPanel
Instance.new("UICorner", InfoPopup).CornerRadius = UDim.new(0, 12)

local AspectConstraint = Instance.new("UIAspectRatioConstraint", InfoPopup)
AspectConstraint.AspectRatio = 1.0
local InfoScale = Instance.new("UIScale", InfoPopup)
InfoScale.Scale = 1

local InfoTitle = Instance.new("TextLabel", InfoPopup)
InfoTitle.Size                 = UDim2.new(1, -20, 0, 35)
InfoTitle.Position             = UDim2.new(0, 10, 0, 10)
InfoTitle.BackgroundTransparency = 1
InfoTitle.Text                 = ""
InfoTitle.TextColor3           = T.headerText
InfoTitle.TextScaled           = true
InfoTitle.Font                 = Enum.Font.GothamBold
InfoTitle.ZIndex               = 51

local InfoDesc = Instance.new("TextLabel", InfoPopup)
InfoDesc.Size                  = UDim2.new(1, -20, 1, -110)
InfoDesc.Position              = UDim2.new(0, 10, 0, 55)
InfoDesc.BackgroundTransparency = 1
InfoDesc.Text                  = ""
InfoDesc.TextColor3            = T.bodyText
InfoDesc.TextWrapped           = true
InfoDesc.TextScaled            = true
InfoDesc.Font                  = T.font
InfoDesc.TextYAlignment        = Enum.TextYAlignment.Top
InfoDesc.ZIndex                = 51

local InfoClose = Instance.new("TextButton", InfoPopup)
InfoClose.Size             = UDim2.new(0.6, 0, 0, 40)
InfoClose.Position         = UDim2.new(0.2, 0, 1, -50)
InfoClose.BackgroundColor3 = T.buttonPrimary
InfoClose.BorderSizePixel  = 0
InfoClose.Text             = "Close"
InfoClose.TextColor3       = T.headerText
InfoClose.TextScaled       = true
InfoClose.Font             = T.font
InfoClose.ZIndex           = 51
Instance.new("UICorner", InfoClose).CornerRadius = UDim.new(0, 8)

local function ShowInfo(title, desc)
	if shared.PlayUISound then shared.PlayUISound(SoundConfig.UIClick or "") end
	InfoTitle.Text = title
	InfoDesc.Text  = desc
	InfoPopup.BackgroundTransparency = 0
	InfoScale.Scale  = 0.5
	InfoPopup.Visible = true
	TweenService:Create(InfoScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

InfoClose.MouseButton1Down:Connect(function()
	if shared.PlayUISound then shared.PlayUISound(SoundConfig.UIClick or "") end
	local tween = TweenService:Create(InfoScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0.5 })
	tween:Play(); tween.Completed:Once(function() InfoPopup.Visible = false end)
end)

local activeShopTabText = "Regular Upgrades"

local MainTabBar = Instance.new("Frame")
MainTabBar.Size                 = UDim2.new(1, -20, 0, 85)
MainTabBar.Position             = UDim2.new(0, 10, 0, HEADER_H + 4)
MainTabBar.BackgroundTransparency = 1
MainTabBar.ZIndex               = 11
MainTabBar.Parent               = ShopPanel

local ShopHoverLabel = Instance.new("TextLabel", MainTabBar)
ShopHoverLabel.Size                 = UDim2.new(1, 0, 0, 20)
ShopHoverLabel.Position             = UDim2.new(0, 0, 0, 0)
ShopHoverLabel.BackgroundTransparency = 1
ShopHoverLabel.TextColor3           = T.bodyText
ShopHoverLabel.TextScaled           = true
ShopHoverLabel.Font                 = T.font
ShopHoverLabel.Text                 = activeShopTabText

local TabBtnFrame = Instance.new("Frame", MainTabBar)
TabBtnFrame.Size                 = UDim2.new(1, 0, 1, -25)
TabBtnFrame.Position             = UDim2.new(0, 0, 0, 25)
TabBtnFrame.BackgroundTransparency = 1

local TabListLayout = Instance.new("UIListLayout", TabBtnFrame)
TabListLayout.FillDirection       = Enum.FillDirection.Horizontal
TabListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
TabListLayout.VerticalAlignment   = Enum.VerticalAlignment.Center
TabListLayout.Padding             = UDim.new(0, 25)

local TAB_COLOR_BASE   = T.buttonSecondary
local TAB_COLOR_HOVER  = T.buttonPrimary
local TAB_COLOR_ACTIVE = Color3.fromRGB(143, 78, 217)

local mainTabButtons = {}
local function MakeMainTab(name, hoverText, iconId)
	local btn = Instance.new("ImageButton", TabBtnFrame)
	btn.Name             = "MainTab_" .. name
	btn.Size             = UDim2.new(0, 48, 0, 48)
	btn.BackgroundColor3 = TAB_COLOR_BASE
	btn.AutoButtonColor  = false
	btn.ZIndex           = 12
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0.5, 0)
	local stroke = Instance.new("UIStroke", btn)
	stroke.Color     = T.panelStroke
	stroke.Thickness = 2
	local icon = Instance.new("ImageLabel", btn)
	icon.Size               = UDim2.new(0.6, 0, 0.6, 0)
	icon.Position           = UDim2.new(0.2, 0, 0.2, 0)
	icon.BackgroundTransparency = 1
	icon.ScaleType          = Enum.ScaleType.Fit
	icon.Image              = iconId

	btn.MouseEnter:Connect(function()
		ShopHoverLabel.Text = hoverText
		if activeMainTab ~= name then btn.BackgroundColor3 = TAB_COLOR_HOVER end
	end)
	btn.MouseLeave:Connect(function()
		ShopHoverLabel.Text = activeShopTabText
		if activeMainTab ~= name then btn.BackgroundColor3 = TAB_COLOR_BASE end
	end)

	mainTabButtons[name] = { btn = btn, stroke = stroke }
	return btn
end

local tabEpic     = MakeMainTab("Epic",     "Epic Research",     UIConfig.Icons.ShopTabEpic or "rbxassetid://14916846070")
local tabUpgrades = MakeMainTab("Upgrades", "Regular Upgrades",  UIConfig.Icons.ShopTabRegular or "rbxassetid://14916846070")
CollectionService:AddTag(tabEpic, "Tutorial_EpicResearchTab")

local CURRENCY_H = 0
local CurrencyLabel = Instance.new("TextLabel")
CurrencyLabel.Name              = "ShopCurrencyLabel"
CurrencyLabel.Size              = UDim2.new(1, -24, 0, CURRENCY_H)
CurrencyLabel.BackgroundTransparency = 1
CurrencyLabel.Text              = "$0"
CurrencyLabel.TextColor3        = T.currencyColor
CurrencyLabel.TextScaled        = true
CurrencyLabel.Font              = T.font
CurrencyLabel.TextXAlignment    = Enum.TextXAlignment.Right
CurrencyLabel.ZIndex            = 11
CurrencyLabel.Parent            = ShopPanel

local function MakeScroll(name, yTop)
	local sf = Instance.new("ScrollingFrame")
	sf.Name                 = name
	sf.Size                 = UDim2.new(1, -20, 1, -(yTop + 10))
	sf.Position             = UDim2.new(0, 10, 0, yTop)
	sf.BackgroundTransparency = 1
	sf.BorderSizePixel      = 0
	sf.ScrollBarThickness   = 4
	sf.ScrollBarImageColor3 = T.subText
	sf.CanvasSize           = UDim2.new(0, 0, 0, 0)
	sf.ZIndex               = 11
	sf.Visible              = false
	sf.ClipsDescendants     = true
	sf.Parent               = ShopPanel

	local pad = Instance.new("UIPadding", sf)
	pad.PaddingTop = UDim.new(0, 5)
	pad.PaddingBottom = UDim.new(0, 15)

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.Parent  = sf

	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		sf.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 25)
	end)
	return sf
end

local REGULAR_SCROLL_TOP = HEADER_H + 95
local RegularScroll      = MakeScroll("RegularScroll", REGULAR_SCROLL_TOP)
local EPIC_SCROLL_TOP    = HEADER_H + 95
local EpicScroll         = MakeScroll("EpicScroll", EPIC_SCROLL_TOP)

local function BuildCard(parent, upgradeId, cfg, isEpic, cardRefsTable)
	local card = Instance.new("Frame")
	card.Name             = "Card_" .. upgradeId
	card.Size             = UDim2.new(1, 0, 0, 100)
	card.BackgroundColor3 = T.cardBG
	card.BorderSizePixel  = 0
	card.Parent           = parent
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)

	local icon = Instance.new("ImageLabel", card)
	icon.Size               = UDim2.new(0, 44, 0, 44)
	icon.Position           = UDim2.new(0, 10, 0.5, -22)
	icon.BackgroundTransparency = 1
	icon.Image              = cfg.iconId or "rbxassetid://0"

	local nameLabel = Instance.new("TextLabel", card)
	nameLabel.Size              = UDim2.new(1, -145, 0, 20)
	nameLabel.Position          = UDim2.new(0, 84, 0, 11)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text              = string.upper(cfg.displayName)
	nameLabel.TextColor3        = T.bodyText
	nameLabel.TextScaled        = true
	nameLabel.Font              = Enum.Font.FredokaOne
	nameLabel.TextXAlignment    = Enum.TextXAlignment.Left

	local descLabel = Instance.new("TextLabel", card)
	descLabel.Size              = UDim2.new(1, -140, 0, 36)
	descLabel.Position          = UDim2.new(0, 58, 0, 34)
	descLabel.BackgroundTransparency = 1
	descLabel.Text              = cfg.description
	descLabel.TextColor3        = T.subText
	descLabel.TextWrapped       = true
	descLabel.TextScaled        = true
	descLabel.Font              = Enum.Font.GothamMedium
	descLabel.TextXAlignment    = Enum.TextXAlignment.Left
	descLabel.TextYAlignment    = Enum.TextYAlignment.Top

	local levelLabel = Instance.new("TextLabel", card)
	levelLabel.Size             = UDim2.new(1, -140, 0, 16)
	levelLabel.Position         = UDim2.new(0, 58, 0, 74)
	levelLabel.BackgroundTransparency = 1
	levelLabel.Text             = "Lv. 0 / " .. cfg.maxLevel
	levelLabel.TextColor3       = T.accentGreen
	levelLabel.TextScaled       = true
	levelLabel.Font             = Enum.Font.FredokaOne
	levelLabel.TextXAlignment   = Enum.TextXAlignment.Left

	local buyButton = Instance.new("TextButton", card)
	buyButton.Name             = "PurchaseButton"
	buyButton.Size             = UDim2.new(0, 72, 0, 40)
	buyButton.AnchorPoint      = Vector2.new(1, 0.5)
	buyButton.Position         = UDim2.new(1, -8, 0.5, 0)
	buyButton.BackgroundColor3 = isEpic and T.accentPurple or T.buttonGreen
	buyButton.BorderSizePixel  = 0
	buyButton.TextColor3       = T.bodyText
	buyButton.TextScaled       = true
	buyButton.Font             = Enum.Font.FredokaOne
	CollectionService:AddTag(buyButton, "Tutorial_Buy_" .. upgradeId) 

	if isEpic and upgradeId == "epicAuraValue" then
		CollectionService:AddTag(buyButton, "Tutorial_BuyEpic_epicAuraValue")
	end

	Instance.new("UICorner", buyButton).CornerRadius = UDim.new(0, 8)

	cardRefsTable[upgradeId] = {
		frame      = card,
		levelLabel = levelLabel,
		buyButton  = buyButton,
		isEpic     = isEpic,
		tab        = cfg.category,
	}

	local holdingBuy    = false
	local buyGeneration = 0

	local function TryBuy()
		if isLoadingData then return false end

		-- FIX: We define a specific action for advancing, and a generic one to fallback to for unlocked purchases
		local specificAction = isEpic and ("Action_BuyEpic_" .. upgradeId) or ("Action_BuyUpgrade_" .. upgradeId)
		local genericAction  = isEpic and "Action_BuyEpic" or "Action_BuyUpgrade"

		local canPerform = true
		if type(shared.TutorialCanPerform) == "function" then
			-- If the specific action matches the step, it flags the advance system
			if shared.TutorialCanPerform(specificAction) then
				canPerform = true
				-- If the step is NOT looking for this specific upgrade, check if generic buying is unlocked
			elseif shared.TutorialCanPerform(genericAction) then
				canPerform = true
			else
				canPerform = false
			end
		end

		if not canPerform then 
			PlayErrorFeedback(buyButton)
			return false 
		end

		if isEpic then
			local state = epicUpgradeState[upgradeId]
			if not state or state.maxed then return false end

			local currentAuras = player:GetAttribute("LiveGoldenAuras") or 0
			local currentAuraSpend = player:GetAttribute("LocalAuraSpend") or 0
			local actualAuras = currentAuras - currentAuraSpend

			if actualAuras < state.cost then PlayErrorFeedback(buyButton); return false end

			local wasMaxedLocally = state.maxed
			player:SetAttribute("LocalAuraSpend", currentAuraSpend + state.cost)

			state.level += 1
			state.maxed  = (state.level >= state.maxLevel)
			state.cost   = state.maxed and 0 or EpicUpgradeConfig.CalculateCost(upgradeId, state.level)

			if state.maxed and not wasMaxedLocally then
				PlayFeedbackSound("MaxOut", 0.6); PlayUIBurst(buyButton, 20)
			else
				PlayPurchaseSound()
			end
			UpdateEpicCard(upgradeId)
			PurchaseEpicUpgrade:FireServer(upgradeId)
			if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
			return true
		else
			local state = upgradeState[upgradeId]
			if not state or state.maxed then return false end

			local currentCash = player:GetAttribute("LiveCurrency") or 0
			local currentSpend = player:GetAttribute("LocalSpend") or 0
			local actualCash = currentCash - currentSpend

			if actualCash < state.cost then PlayErrorFeedback(buyButton); return false end

			local wasMaxedLocally = state.maxed
			player:SetAttribute("LocalSpend", currentSpend + state.cost)

			state.level += 1
			state.maxed  = (state.level >= state.maxLevel)
			state.cost   = state.maxed and 0 or UpgradeConfig.CalculateCost(upgradeId, state.level)

			if state.maxed and not wasMaxedLocally then
				PlayFeedbackSound("MaxOut", 0.6); PlayUIBurst(buyButton, 20)
			else
				PlayPurchaseSound()
			end
			UpdateRegularCard(upgradeId)
			UpdateLockedTierProgress()
			PurchaseUpgrade:FireServer(upgradeId)
			if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
			return true
		end
	end

	local pulseTween = nil

	buyButton.MouseButton1Down:Connect(function()
		local specificAction = isEpic and ("Action_BuyEpic_" .. upgradeId) or ("Action_BuyUpgrade_" .. upgradeId)
		local genericAction  = isEpic and "Action_BuyEpic" or "Action_BuyUpgrade"

		local canPerform = true
		if type(shared.TutorialCanPerform) == "function" then
			if shared.TutorialCanPerform(specificAction) then
				canPerform = true
			elseif shared.TutorialCanPerform(genericAction) then
				canPerform = true
			else
				canPerform = false
			end
		end

		if not canPerform then return end

		globalHoldGeneration += 1
		local myGlobalGen = globalHoldGeneration

		buyGeneration += 1
		local myGen   = buyGeneration
		holdingBuy    = true
		globalHoldActive = true

		local scale = buyButton:FindFirstChildOfClass("UIScale")
		if not scale then
			scale = Instance.new("UIScale")
			scale.Parent = buyButton
		end

		pulseTween = TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 0.88 })
		pulseTween:Play()

		TryBuy()
		task.wait(0.3)
		local holdStart = tick()

		local UserInputService = game:GetService("UserInputService")
		local epicHoldSpeedLevel   = (epicUpgradeState["epicHoldSpeed"] and epicUpgradeState["epicHoldSpeed"].level) or 0
		local holdSpeedMultiplier  = 1 + (epicHoldSpeedLevel * 0.3)

		while holdingBuy and buyGeneration == myGen and globalHoldGeneration == myGlobalGen do
			if not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
				holdingBuy = false; globalHoldActive = false; break
			end
			local success = TryBuy()
			if not success then holdingBuy = false; globalHoldActive = false; break end
			task.wait(math.max(0.02, (0.15 - ((tick() - holdStart) * 0.05)) / holdSpeedMultiplier))
		end

		globalHoldActive = false
		if pulseTween then pulseTween:Cancel() end
		if scale then TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), { Scale = 1 }):Play() end
	end)

	local function StopHold()
		holdingBuy = false
		globalHoldActive = false
		if pulseTween then pulseTween:Cancel() end
		local scale = buyButton:FindFirstChildOfClass("UIScale")
		if scale then TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), { Scale = 1 }):Play() end
	end

	buyButton.MouseButton1Up:Connect(StopHold)
	buyButton.MouseLeave:Connect(StopHold)
end

-- === DYNAMIC EPIC SORTING ===
local epicUpgradesList = {}
for _, tierData in ipairs(EpicUpgradeConfig.Tiers) do
	for upgradeId, cfg in pairs(tierData.upgrades) do
		table.insert(epicUpgradesList, { id = upgradeId, cfg = cfg })
	end
end

table.sort(epicUpgradesList, function(a, b)
	return (a.cfg.baseCost or 0) < (b.cfg.baseCost or 0)
end)

local epicOrderIndex = 1
for _, item in ipairs(epicUpgradesList) do
	BuildCard(EpicScroll, item.id, item.cfg, true, epicCardRefs)
	local ref = epicCardRefs[item.id]
	if ref and ref.frame then
		ref.baseOrder      = epicOrderIndex
		ref.frame.LayoutOrder = epicOrderIndex
		epicOrderIndex     += 1
		ref.frame.Visible  = false
		ref.frame.Parent   = EpicScroll
		if UITheme and UITheme.Apply then UITheme.Apply(ref.frame, "ShopCard") end
	end
end
-- ==========================

function UpdateRegularCard(upgradeId)
	local ref   = regularCardRefs[upgradeId]
	local state = upgradeState[upgradeId]
	if not ref or not state then return end
	if UITheme and UITheme.Apply then UITheme.Apply(ref.frame, "ShopCard") end

	ref.levelLabel.Text = "Lv. " .. state.level .. " / " .. state.maxLevel

	local currentCash   = player:GetAttribute("LiveCurrency") or 0
	local currentSpend  = player:GetAttribute("LocalSpend") or 0
	local actualCash    = currentCash - currentSpend

	if state.level >= state.maxLevel then
		ref.frame.LayoutOrder        = (ref.baseOrder or 0) + 100000
		ref.levelLabel.TextColor3    = Color3.fromRGB(255, 215, 0)
		ref.buyButton.Text           = "MAX"
		ref.buyButton.TextColor3     = Color3.fromRGB(255, 255, 255)
		ref.buyButton.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
	else
		ref.frame.LayoutOrder      = ref.baseOrder or 0
		ref.buyButton.Text         = "$" .. FormatNumber(state.cost)
		ref.buyButton.TextColor3   = (actualCash < state.cost) and Color3.fromRGB(255, 100, 100) or Color3.fromRGB(255, 255, 255)
		ref.buyButton.BackgroundColor3 = Color3.fromRGB(60, 170, 80)
	end
end

function UpdateEpicCard(upgradeId)
	local ref   = epicCardRefs[upgradeId]
	local state = epicUpgradeState[upgradeId]
	if not ref or not state then return end
	if UITheme and UITheme.Apply then UITheme.Apply(ref.frame, "ShopCard") end

	ref.levelLabel.Text = "Lv. " .. state.level .. " / " .. state.maxLevel

	local currentAuras  = player:GetAttribute("LiveGoldenAuras") or 0
	local currentAuraSpend = player:GetAttribute("LocalAuraSpend") or 0
	local actualAuras   = currentAuras - currentAuraSpend

	if state.level >= state.maxLevel then
		ref.frame.LayoutOrder        = (ref.baseOrder or 0) + 100000
		ref.levelLabel.TextColor3    = Color3.fromRGB(255, 215, 0)
		ref.buyButton.Text           = "MAX"
		ref.buyButton.TextColor3     = Color3.fromRGB(255, 255, 255)
		ref.buyButton.BackgroundColor3 = Color3.fromRGB(100, 100, 100)

		local epicIcon = ref.buyButton:FindFirstChild("EpicImage")
		if epicIcon then epicIcon:Destroy() end
	else
		ref.frame.LayoutOrder      = ref.baseOrder or 0
		ref.buyButton.Text         = "🌟" .. FormatNumber(state.cost)
		ref.buyButton.TextColor3   = (actualAuras < state.cost) and Color3.fromRGB(255, 100, 100) or Color3.fromRGB(255, 255, 255)
		ref.buyButton.BackgroundColor3 = Color3.fromRGB(150, 80, 255)

		local epicIcon = ref.buyButton:FindFirstChild("EpicImage")
		if not epicIcon then
			epicIcon = Instance.new("ImageLabel")
			epicIcon.Name = "EpicImage"
			epicIcon.Size = UDim2.new(0, 20, 0, 20)
			epicIcon.Position = UDim2.new(0, 10, 0.5, -10)
			epicIcon.BackgroundTransparency = 1
			epicIcon.Image = "rbxassetid://0"
			epicIcon.Parent = ref.buyButton
		end
	end
end

function UpdateCurrencyDisplay()
	if activeMainTab == "Upgrades" then
		local currentCash = player:GetAttribute("LiveCurrency") or 0
		local currentSpend = player:GetAttribute("LocalSpend") or 0
		local actualCash = currentCash - currentSpend

		CurrencyLabel.Text       = "$" .. FormatNumber(actualCash)
		CurrencyLabel.TextColor3 = T.currencyColor
		CurrencyLabel.Position   = UDim2.new(0, 12, 0, HEADER_H + 34 + 8)
	end
end

local function UpdateAllRegularCards() for id in pairs(regularCardRefs) do UpdateRegularCard(id) end end
local function UpdateAllEpicCards()   for id in pairs(epicCardRefs)    do UpdateEpicCard(id)    end end

UpdateLockedTierProgress = function()
	local totalUpgradesBought = 0
	for _, state in pairs(upgradeState) do
		totalUpgradesBought = totalUpgradesBought + (state.level or 0)
	end

	local lockedHeader = nil
	local required = 0

	for _, child in ipairs(RegularScroll:GetChildren()) do
		if child.Name == "TierHeader_Locked" then
			lockedHeader = child
			required = child:GetAttribute("Required") or 0
			local progressLabel = child:FindFirstChild("ProgressLabel")
			if progressLabel then
				progressLabel.Text = totalUpgradesBought .. " / " .. required .. " Upgrades Needed"
				local progress = totalUpgradesBought / required
				if progress >= 1 then
					progressLabel.TextColor3 = Color3.fromRGB(100, 255, 100) 
				elseif progress >= 0.75 then
					progressLabel.TextColor3 = Color3.fromRGB(255, 200, 100) 
				else
					progressLabel.TextColor3 = Color3.fromRGB(255, 100, 100) 
				end
			end
			break
		end
	end

	if lockedHeader and totalUpgradesBought >= required then
		PlayFeedbackSound("MaxOut", 0.8)
		PlayUIBurst(ShopPanel, 30, Color3.fromRGB(100, 255, 100))
		local scroll = ShopPanel:FindFirstChild("RegularScroll")
		local savedScroll = scroll and scroll.CanvasPosition or Vector2.new(0, 0)
		RebuildRegularShop()
		if scroll then scroll.CanvasPosition = savedScroll end
	end
end

local function CreateTierHeader(tierName)
	local header = Instance.new("Frame")
	header.Name                 = "TierHeader"
	header.Size                 = UDim2.new(1, 0, 0, 30)
	header.BackgroundTransparency = 1

	local label = Instance.new("TextLabel")
	label.Size                  = UDim2.new(1, 0, 1, -5)
	label.BackgroundTransparency = 1
	label.Text                  = string.upper(tierName)
	label.TextColor3            = Color3.fromRGB(220, 220, 220)
	label.TextSize              = 16
	label.Font                  = Enum.Font.GothamBlack
	label.TextXAlignment        = Enum.TextXAlignment.Left
	label.Parent                = header

	local line = Instance.new("Frame")
	line.Size             = UDim2.new(1, 0, 0, 2)
	line.Position         = UDim2.new(0, 0, 1, -2)
	line.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
	line.BorderSizePixel  = 0
	line.Parent           = header
	return header
end

local function CreateLockedTierHeader(tierName, current, required)
	local header = Instance.new("Frame")
	header.Name                 = "TierHeader_Locked"
	header.Size                 = UDim2.new(1, 0, 0, 45)
	header.BackgroundTransparency = 1
	header:SetAttribute("Required", required)

	local label = Instance.new("TextLabel")
	label.Size                  = UDim2.new(1, 0, 0.5, 0)
	label.BackgroundTransparency = 1
	label.Text                  = string.upper(tierName) .. " (LOCKED)"
	label.TextColor3            = Color3.fromRGB(150, 150, 150)
	label.TextSize              = 16
	label.Font                  = Enum.Font.GothamBlack
	label.TextXAlignment        = Enum.TextXAlignment.Left
	label.Parent                = header

	local progress = Instance.new("TextLabel")
	progress.Name               = "ProgressLabel"
	progress.Size               = UDim2.new(1, 0, 0.4, 0)
	progress.Position           = UDim2.new(0, 0, 0.6, 0)
	progress.BackgroundTransparency = 1
	progress.Text               = current .. " / " .. required .. " Upgrades Needed"
	progress.TextColor3         = Color3.fromRGB(255, 100, 100)
	progress.TextSize           = 12
	progress.Font               = Enum.Font.GothamBold
	progress.TextXAlignment     = Enum.TextXAlignment.Left
	progress.Parent             = header

	local line = Instance.new("Frame")
	line.Size             = UDim2.new(1, 0, 0, 2)
	line.Position         = UDim2.new(0, 0, 1, -2)
	line.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
	line.BorderSizePixel  = 0
	line.Parent           = header
	return header
end

RebuildRegularShop = function()
	for _, child in ipairs(RegularScroll:GetChildren()) do
		if child:IsA("Frame") and child.Name ~= "CardTemplate" then
			child:Destroy()
		end
	end
	regularCardRefs = {}

	local totalUpgradesBought = 0
	for _, state in pairs(upgradeState) do
		totalUpgradesBought = totalUpgradesBought + (state.level or 0)
	end

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
					if ref.buyButton then
						ref.buyButton.Name = "Buy_" .. upgradeId
					end
					ref.baseOrder          = listOrder
					ref.frame.LayoutOrder  = listOrder
					listOrder             += 1
					ref.frame.Visible      = true
					ref.frame.Parent       = RegularScroll
					if UITheme and UITheme.Apply then UITheme.Apply(ref.frame, "ShopCard") end
					local myColor = Color3.fromRGB(45, 30, 55)
					ref.frame:SetAttribute("TierColor", myColor)
					ref.frame.BackgroundColor3 = myColor
				end
			end
		else
			local lockedHeader = CreateLockedTierHeader(tierData.tierName or "Tier " .. tierNum, totalUpgradesBought, tierData.unlockRequirement)
			lockedHeader.LayoutOrder = listOrder
			lockedHeader.Parent      = RegularScroll
			break
		end
	end
	UpdateAllRegularCards()
end

RebuildRegularShop()

task.delay(5, function() isLoadingData = false end)

local function SwitchToMainTab(tabName)
	if shared.PlayUISound then shared.PlayUISound(SoundConfig.UIClick or "") end
	activeMainTab     = tabName
	activeShopTabText = (tabName == "Epic") and "Epic Research" or "Regular Upgrades"
	ShopHoverLabel.Text = activeShopTabText

	for name, data in pairs(mainTabButtons) do
		data.btn.BackgroundColor3 = (name == tabName) and TAB_COLOR_ACTIVE or TAB_COLOR_BASE
		data.stroke.Color         = (name == tabName) and T.bodyText or T.panelStroke
	end

	RegularScroll.Visible = (tabName == "Upgrades")
	EpicScroll.Visible    = (tabName == "Epic")

	if tabName == "Epic" then
		for _, ref in pairs(epicCardRefs) do
			if ref and ref.frame then ref.frame.Visible = true end
		end
		if EpicScroll then EpicScroll.CanvasPosition = Vector2.new(0, 0) end
	end
end

tabUpgrades.MouseButton1Down:Connect(function() PlayUI(SoundConfig.UIClick); SwitchToMainTab("Upgrades") end)
tabEpic.MouseButton1Down:Connect(function()     PlayUI(SoundConfig.UIClick); SwitchToMainTab("Epic")     end)

local function OpenShop()
	if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_OpenShop") then return end

	ForceCloseUI:Fire("ShopPanel")

	shopOpen = true
	ShopPanel.Visible = true
	SwitchToMainTab(activeMainTab)

	ShopPanel.Size = UDim2.new(1, -110, 0, 0)
	TweenService:Create(ShopPanel, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.new(1, -110, 0.85, 0), Position = UDim2.new(0, 95, 0.5, 0) }):Play()
	ShopButton.BackgroundColor3 = T.buttonSecondary

	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
end

local function CloseShop()
	if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_CloseShop") then return end

	shopOpen = false
	PlayUI(SoundConfig.UIClose)

	local tween = TweenService:Create(ShopPanel, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.new(0, -500, 0.5, 0) })
	tween:Play()
	tween.Completed:Once(function() if not shopOpen then ShopPanel.Visible = false end end)
	ShopButton.BackgroundColor3 = T.buttonSecondary

	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
end

ShopButton.MouseButton1Down:Connect(function()
	if shopOpen then CloseShop() else OpenShop() end
end)

CloseButton.MouseButton1Down:Connect(CloseShop)

local lastCardUpdate = 0
RunService.Heartbeat:Connect(function()
	if not shopOpen then return end
	local now = tick()
	if now - lastCardUpdate > 0.1 then
		lastCardUpdate = now
		if activeMainTab == "Upgrades" then UpdateAllRegularCards() else UpdateAllEpicCards() end
		UpdateCurrencyDisplay()
	end
end)

if UpgradeUpdated then
	UpgradeUpdated.OnClientEvent:Connect(function(info)
		if info.type == "fullState" then
			isLoadingData = false
			upgradeState   = info.upgrades
			currentCurrency = info.currency
			RebuildRegularShop()
			UpdateCurrencyDisplay()

		elseif info.type == "purchased" then
			player:SetAttribute("LastServerPurchaseTick", tick())
			player:SetAttribute("LocalSpend", 0)
			player:SetAttribute("ForceSyncCurrency", info.currency)

			local current = upgradeState[info.upgradeId]
			if not current or info.level >= current.level then
				upgradeState[info.upgradeId] = {
					level    = info.level,
					maxLevel = info.maxLevel,
					cost     = info.cost,
					maxed    = info.maxed,
				}
			end
			currentCurrency = info.currency

			UpdateRegularCard(info.upgradeId)
			UpdateLockedTierProgress()
			UpdateCurrencyDisplay()
		end
	end)
end

if EpicUpgradeUpdated then
	EpicUpgradeUpdated.OnClientEvent:Connect(function(info)
		if info.type == "fullState" then
			isLoadingData = false
			epicUpgradeState = info.upgrades
			liveGoldenAuras  = info.goldenAuras or liveGoldenAuras
			UpdateAllEpicCards()
			UpdateCurrencyDisplay()

		elseif info.type == "purchased" then
			player:SetAttribute("LastServerPurchaseTick", tick())
			player:SetAttribute("LocalAuraSpend", 0)

			local current = epicUpgradeState[info.upgradeId]
			if not current or info.level >= current.level then
				epicUpgradeState[info.upgradeId] = {
					level    = info.level,
					maxLevel = info.maxLevel,
					cost     = info.cost,
					maxed    = info.maxed,
				}
			end
			UpdateEpicCard(info.upgradeId)
			UpdateCurrencyDisplay()
		end
	end)
end

local function AddButtonJuice(btn)
	if not btn then return end
	local scale = btn:FindFirstChildOfClass("UIScale")
	if not scale then scale = Instance.new("UIScale"); scale.Parent = btn end
	btn.MouseEnter:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Sine), { Scale = 1.08 }):Play() end)
	btn.MouseLeave:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Sine), { Scale = 1 }):Play() end)
	btn.MouseButton1Down:Connect(function() TweenService:Create(scale, TweenInfo.new(0.1, Enum.EasingStyle.Sine), { Scale = 0.9 }):Play() end)
	btn.MouseButton1Up:Connect(function() TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), { Scale = 1.08 }):Play() end)
end

AddButtonJuice(ShopButton); AddButtonJuice(CloseButton); AddButtonJuice(tabUpgrades); AddButtonJuice(tabEpic)

local shopShine    = nil
local titleFlair   = nil
local flairedExtra = false

local function RefreshLook()
	UITheme.Apply(ShopPanel, "Panel")
	UITheme.Apply(ShopPanel, "TitleBar")

	if not shopShine then
		shopShine  = UITheme.ApplyShine(ShopPanel)
		UITheme.ApplyShine(TitleBar)
	end

	if not titleFlair then titleFlair = UITheme.ApplyFlair(TitleLabel, "Ghost") end
	if not flairedExtra then flairedExtra = true end

	for _, scrollName in ipairs({ "RegularScroll", "EpicScroll" }) do
		local scroll = ShopPanel:FindFirstChild(scrollName)
		if scroll then
			local layout = scroll:FindFirstChildOfClass("UIListLayout")
			if layout then layout.SortOrder = Enum.SortOrder.LayoutOrder end
		end
	end

	local outerStroke = ShopPanel:FindFirstChildWhichIsA("UIStroke")
	if outerStroke then outerStroke.Color = Color3.fromRGB(255, 255, 255) end
end

task.wait(2)
RefreshLook()

ForceCloseUI.Event:Connect(function(exceptionPanel)
	if exceptionPanel ~= "ShopPanel" and shopOpen then
		CloseShop()
	end
end)

-- PassiveIncome
-- Location: ServerScriptService > PassiveIncome

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AdminConfig    = require(ReplicatedStorage.Modules.AdminConfig)
local UpgradeConfig  = require(ReplicatedStorage.Modules.UpgradeConfig)
local GameManager    = require(ServerScriptService.GameManager)
local BoostManager   = require(ServerScriptService.BoostManager)

local BridgeNet2      = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))
local UpdateHUDBridge = BridgeNet2.ServerBridge("UpdateHUD")

if script:GetAttribute("Running") then script:Destroy(); return end
script:SetAttribute("Running", true)

local lastSentCurrency   = {}  
local lastSentStored     = {}

Players.PlayerAdded:Connect(function(p)
	lastSentCurrency[p.UserId] = 0
	lastSentStored[p.UserId]   = 0
end)

Players.PlayerRemoving:Connect(function(p)
	lastSentCurrency[p.UserId] = nil
	lastSentStored[p.UserId]   = nil
end)

while true do
	-- ✨ BLAZING FAST 20Hz LOOP (Matches your FocusScript!)
	local dt = task.wait(0.05)

	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("TutorialFrozen") then continue end

		local uid     = player.UserId
		local data    = GameManager.GetData(uid)
		local runtime = GameManager.GetRuntime(uid)
		if not data or not runtime then continue end

		local activeValue = runtime.activeMutatedValue or 0
		local storedCount = runtime.storedCubeCount or 0

		local interval = UpgradeConfig.GetPassiveInterval(data)
		if interval <= 0 then interval = 1 end

		local boostMult = BoostManager.GetValueMultiplier(uid) * BoostManager.GetSpawnRateMultiplier(uid)

		-- Calculate the exact microscopic fraction earned in this 0.05s window
		local fullTickEarned   = activeValue * boostMult
		local fractionalEarned = fullTickEarned * (dt / interval)

		if fractionalEarned > 0 then
			data.currency       = (data.currency       or 0) + fractionalEarned
			data.totalEarned    = (data.totalEarned     or 0) + fractionalEarned
			data.farmEvaluation = (data.farmEvaluation  or 0) + fractionalEarned
		end

		-- Only fire the BridgeNet update if they are actively making money or the habitat changed
		local shouldFire = false
		if not lastSentCurrency[uid] or math.abs(data.currency - lastSentCurrency[uid]) > 0.001 then
			shouldFire = true
		end
		if storedCount ~= lastSentStored[uid] then
			shouldFire = true
		end

		if shouldFire then
			lastSentCurrency[uid] = data.currency
			lastSentStored[uid]   = storedCount

			local habCap = UpgradeConfig.GetHabitatCapacity(data)

			UpdateHUDBridge:Fire(player, {
				currency        = data.currency, 
				pendingAuras    = storedCount, 
				habitatCapacity = habCap,
				rate            = math.floor(fullTickEarned),
				passiveInterval = interval,
				totalEarned     = math.floor(data.totalEarned or 0),
				soulAuras       = data.soulAuras      or 0,
				farmEvaluation  = math.floor(data.farmEvaluation or 0),
				boostMultiplier = boostMult -- ✨ THE FIX: Sync to HUD so labels scale!
			})
		end
	end
end

-- Location: ServerScriptService > AuraPhysicsManager

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")

local AdminConfig = require(ReplicatedStorage.Modules:WaitForChild("AdminConfig"))
local AreaRegistry = require(ReplicatedStorage.Modules:WaitForChild("AreaRegistry"))
local GameManager = require(ServerScriptService:WaitForChild("GameManager"))
local EpicUpgradeConfig = require(ReplicatedStorage.Modules:WaitForChild("EpicUpgradeConfig"))

local BridgeNet2      = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))
local UpdateHUDBridge = BridgeNet2.ServerBridge("UpdateHUD")

local AURA_ORIGIN = workspace:FindFirstChild("AuraModel") or workspace:FindFirstChild("AuraHolder")

local function FadeOutAndDestroy(obj, duration)
	if not obj or not obj.Parent then return end
	if obj:IsA("BasePart") then
		TweenService:Create(obj, TweenInfo.new(duration), {Size = Vector3.zero, Transparency = 1}):Play()
	else
		for _, desc in ipairs(obj:GetDescendants()) do
			if desc:IsA("BasePart") or desc:IsA("Decal") or desc:IsA("Texture") then
				TweenService:Create(desc, TweenInfo.new(duration), {Transparency = 1}):Play()
			end
		end
	end
	Debris:AddItem(obj, duration)
end

local function CreatePhysicsAura(isElite)
	-- Guard clause: Do not spawn if all active players are inside a special area
	local players = game:GetService("Players"):GetPlayers()
	local activePlayersInNormalArea = false

	for _, p in ipairs(players) do
		local data = GameManager.GetData(p.UserId)
		if data and not data.inSpecialArea then
			activePlayersInNormalArea = true
			break
		end
	end

	if not activePlayersInNormalArea and #players > 0 then 
		return 
	end

	if not AURA_ORIGIN then 
		warn("AURA_ORIGIN (AuraModel/AuraHolder) NOT FOUND IN WORKSPACE!")
		return 
	end

	-- 1. CLONE TEMPLATE
	local VFX_FOLDER = ReplicatedStorage:FindFirstChild("VFX")
	local aura
	if VFX_FOLDER and isElite and VFX_FOLDER:FindFirstChild("ElitePhysicsVFX") then
		aura = VFX_FOLDER.ElitePhysicsVFX:Clone()
	elseif VFX_FOLDER and not isElite and VFX_FOLDER:FindFirstChild("PhysicsVFX") then
		aura = VFX_FOLDER.PhysicsVFX:Clone()
	else
		aura = Instance.new("Part")
		aura.Shape = Enum.PartType.Ball; aura.Material = Enum.Material.Neon; aura.Size = Vector3.new(2,2,2)
		aura.Color = isElite and Color3.fromRGB(255, 50, 255) or Color3.fromRGB(50, 255, 255)
	end

	-- 2. SETUP CORE
	local mainPart = aura:IsA("Model") and aura.PrimaryPart or aura
	if not mainPart then aura:Destroy() return end

	mainPart.CanCollide = true
	aura.Parent = workspace
	CollectionService:AddTag(mainPart, "PhysicsAura")

	-- 3. POSITION & LAUNCH
	local spawnPart = AURA_ORIGIN:FindFirstChild("Position")
	if not spawnPart then warn("No 'Position' part in AuraModel!"); return end

	local spawnPos = spawnPart.Position + Vector3.new(0, 5, 0)
	if aura:IsA("Model") then aura:PivotTo(CFrame.new(spawnPos)) else aura.Position = spawnPos end

	task.wait()
	mainPart:SetNetworkOwner(nil)

	-- Launch it
	local angle = math.random() * math.pi * 2
	local outF = math.random(AdminConfig.PhysicsOutwardForceMin, AdminConfig.PhysicsOutwardForceMax)
	local upF = math.random(AdminConfig.PhysicsUpwardForceMin, AdminConfig.PhysicsUpwardForceMax)
	mainPart:ApplyImpulse(Vector3.new(math.cos(angle)*outF, upF, math.sin(angle)*outF) * mainPart.AssemblyMass)

	local sfxFolder = ReplicatedStorage:FindFirstChild("SFX")
	if sfxFolder and sfxFolder:FindFirstChild("AuraShoot") then
		local sfx = sfxFolder.AuraShoot:Clone()
		sfx.Parent = mainPart 
		sfx.RollOffMaxDistance = 500
		sfx.RollOffMinDistance = 10 
		sfx.RollOffMode = Enum.RollOffMode.Linear
		sfx.PlaybackSpeed = 1 + (math.random(-10, 10) / 100) 
		sfx:Play()
		Debris:AddItem(sfx, 2)
	end

	local vfxFolder = ReplicatedStorage:FindFirstChild("VFX")
	if vfxFolder and vfxFolder:FindFirstChild("AuraSpawnVFX") then
		local spawnEffect = vfxFolder.AuraSpawnVFX:Clone()
		spawnEffect.Position = mainPart.Position
		spawnEffect.Parent = workspace

		for _, emitter in ipairs(spawnEffect:GetDescendants()) do
			if emitter:IsA("ParticleEmitter") then
				emitter:Emit(emitter:GetAttribute("EmitCount") or 25) 
			end
		end
		Debris:AddItem(spawnEffect, 3) 
	end

	-- 4. CLICK & REWARDS 
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "AuraPrompt"
	prompt.ActionText = "Collect"
	prompt.ObjectText = isElite and "Elite Aura" or "Golden Aura"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 30
	prompt.RequiresLineOfSight = false 

	prompt.Style = Enum.ProximityPromptStyle.Custom 
	prompt:SetAttribute("IsElite", isElite == true) 
	game:GetService("CollectionService"):AddTag(prompt, "AuraHologram")

	prompt.Parent = mainPart

	-- 5. LANDING LOGIC & LIFETIME START
	local maxB = (isElite and AdminConfig.PhysicsMaxBouncesElite or AdminConfig.PhysicsMaxBouncesRegular) or 1
	local hasLanded = false
	local bounces = 0
	local lastB = 0 

	local despawnTime = isElite and AdminConfig.PhysicsEliteDespawn or AdminConfig.PhysicsRegularDespawn
	if type(despawnTime) ~= "number" then 
		despawnTime = isElite and 45 or 90
	end

	-- Fallback check just in case it gets stuck mid-air or bounces fail
	task.delay(despawnTime + 10, function()
		if aura and aura.Parent and not mainPart:GetAttribute("Landed") then
			FadeOutAndDestroy(aura, 1)
		end
	end)

	mainPart.Touched:Connect(function(hit)
		if hasLanded or (tick() - lastB < 0.15) then return end

		if hit.Position.Y <= mainPart.Position.Y then
			bounces += 1
			lastB = tick()

			local sfxFolder = ReplicatedStorage:FindFirstChild("SFX")
			if sfxFolder and sfxFolder:FindFirstChild("Landing") then
				local sfx = sfxFolder.Landing:Clone()
				sfx.Parent = mainPart
				sfx:Play()
				Debris:AddItem(sfx, 2)
			end

			if bounces > maxB then
				hasLanded = true
				mainPart:SetAttribute("Landed", true) 
				mainPart.AssemblyLinearVelocity = Vector3.zero
				mainPart.AssemblyAngularVelocity = Vector3.zero 

				local vfxFolder = ReplicatedStorage:FindFirstChild("VFX")
				if vfxFolder and vfxFolder:FindFirstChild("AuraLandingVFX") then
					local landingEffect = vfxFolder.AuraLandingVFX:Clone()
					landingEffect.Position = mainPart.Position - Vector3.new(0, mainPart.Size.Y/2, 0)
					landingEffect.Parent = workspace

					for _, emitter in ipairs(landingEffect:GetDescendants()) do
						if emitter:IsA("ParticleEmitter") then
							emitter:Emit(emitter:GetAttribute("EmitCount") or 25) 
						end
					end
					Debris:AddItem(landingEffect, 3)
				end

				-- Firmly planted despawn timer for successful landings
				task.delay(despawnTime, function()
					if aura and aura.Parent then 
						FadeOutAndDestroy(aura, 1) 
					end
				end)
			end
		end
	end)

	prompt.Triggered:Connect(function(player)
		local data = GameManager.GetData(player.UserId)
		local runtime = GameManager.GetRuntime(player.UserId)

		if data and runtime then
			local currentArea = data.currentArea or 1
			local areaMultiplier = AreaRegistry.GetMultiplier(currentArea)
			local baseReward = (isElite and 5 or 1) * areaMultiplier

			local epicBonus = 0
			pcall(function()
				local cfg = EpicUpgradeConfig.GetUpgradeConfig("goldenAuraValue")
				if cfg then
					epicBonus = cfg.apply(data or { epicUpgrades = {} }) or 0
				end
			end)

			local finalAmount = math.floor(baseReward * (1 + epicBonus))

			data.goldenAuras += finalAmount
			UpdateHUDBridge:Fire(player, { goldenAuras = data.goldenAuras })
		end

		local sfxFolder = ReplicatedStorage:FindFirstChild("SFX")
		if sfxFolder and sfxFolder:FindFirstChild("ClassicBass") then
			local sfx = sfxFolder.ClassicBass:Clone()
			sfx.Parent = player.Character and player.Character:FindFirstChild("HumanoidRootPart") or workspace
			sfx:Play()
			Debris:AddItem(sfx, 2)
		end

		mainPart.Anchored = true
		FadeOutAndDestroy(aura, 0.2)
	end)
end

-- Start spawning
task.spawn(function()
	while true do
		task.wait(math.random(AdminConfig.PhysicsSpawnMin, AdminConfig.PhysicsSpawnMax))
		CreatePhysicsAura(math.random(1,100) <= AdminConfig.PhysicsEliteChance)
	end
end)

local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
if RemoteEvents then
	local burstEvent = RemoteEvents:FindFirstChild("TutorialBurst")
	if not burstEvent then
		burstEvent = Instance.new("RemoteEvent")
		burstEvent.Name = "TutorialBurst"
		burstEvent.Parent = RemoteEvents
	end

	burstEvent.OnServerEvent:Connect(function(player, amount)
		if type(amount) ~= "number" or amount > 50 then 
			amount = 25 
		end

		task.spawn(function()
			for i = 1, amount do
				CreatePhysicsAura(false) 
				task.wait(0.05) 
			end
		end)
	end)

	-- Setup remote event to handle physical aura claims from the habitat storage trigger
	local claimEvent = RemoteEvents:FindFirstChild("ClaimPhysicsAura")
	if not claimEvent then
		claimEvent = Instance.new("RemoteEvent")
		claimEvent.Name = "ClaimPhysicsAura"
		claimEvent.Parent = RemoteEvents
	end

	claimEvent.OnServerEvent:Connect(function(player, auraPart)
		if not auraPart or not auraPart:HasTag("PhysicsAura") then return end
		local prompt = auraPart:FindFirstChild("AuraPrompt")

		if prompt and auraPart.Parent then
			local isElite = prompt:GetAttribute("IsElite")
			local data = GameManager.GetData(player.UserId)
			local runtime = GameManager.GetRuntime(player.UserId)

			if data and runtime then
				local currentArea = data.currentArea or 1
				local areaMultiplier = AreaRegistry.GetMultiplier(currentArea)
				local baseReward = (isElite and 5 or 1) * areaMultiplier

				local epicBonus = 0
				pcall(function()
					local cfg = EpicUpgradeConfig.GetUpgradeConfig("goldenAuraValue")
					if cfg then
						epicBonus = cfg.apply(data or { epicUpgrades = {} }) or 0
					end
				end)

				local finalAmount = math.floor(baseReward * (1 + epicBonus))

				data.goldenAuras += finalAmount
				UpdateHUDBridge:Fire(player, { goldenAuras = data.goldenAuras })
			end

			local sfxFolder = ReplicatedStorage:FindFirstChild("SFX")
			if sfxFolder and sfxFolder:FindFirstChild("ClassicBass") then
				local sfx = sfxFolder.ClassicBass:Clone()
				sfx.Parent = player.Character and player.Character:FindFirstChild("HumanoidRootPart") or workspace
				sfx:Play()
				Debris:AddItem(sfx, 2)
			end

			auraPart.Anchored = true
			local auraModel = auraPart.Parent == workspace and auraPart or auraPart.Parent
			FadeOutAndDestroy(auraModel, 0.2)
		end
	end)
end

task.spawn(function()
	task.wait(5)

	while true do
		task.wait(math.random(AdminConfig.PhysicsSpawnMin or 20, AdminConfig.PhysicsSpawnMax or 45)) 

		local allowPassiveSpawns = false
		for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
			local data = GameManager.GetData(player.UserId)
			if data and not data.inSpecialArea and ((data.prestigeCount or 0) > 0 or (data.currentArea or 1) >= 2) then
				allowPassiveSpawns = true
				break
			end
		end

		if allowPassiveSpawns then
			CreatePhysicsAura(math.random(1, 100) <= (AdminConfig.PhysicsEliteChance or 10))
		end
	end
end)

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
local heldAccumulated   = {}
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
	heldAccumulated[p.UserId] = nil
end)

task.spawn(function()
	local PR = ServerScriptService:WaitForChild("PrestigeReset", 30)
	if PR then
		PR.Event:Connect(function(player)
			local uid = player.UserId
			local data = GameManager.GetData(uid)
			hatchery[uid] = data and GetHatcheryMax(data) or AdminConfig.HatcheryMax
			holdStart[uid]=nil; lastFire[uid]=nil
			heldAccumulated[uid] = nil
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
				heldAccumulated[uid] = tick() - holdStart[uid]
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
	if currentTier == playerMaxTier then return AdminConfig.MilestoneData[currentTier].mult, AdminConfig.MilestoneData[currentTier].luck or 0 end

	local timePassed = effectiveTime - GetMilestoneTime(currentTier)
	local timeNeeded = GetMilestoneTime(nextTier) - GetMilestoneTime(currentTier)
	local ratio = timeNeeded > 0 and (timePassed / timeNeeded) or 1 

	local cMult = AdminConfig.MilestoneData[currentTier].mult
	local nMult = AdminConfig.MilestoneData[nextTier].mult
	local smoothMult = cMult + ((nMult - cMult) * ratio)

	local cLuck = AdminConfig.MilestoneData[currentTier].luck or 0
	local nLuck = AdminConfig.MilestoneData[nextTier].luck or 0
	local smoothLuck = cLuck + ((nLuck - cLuck) * ratio)

	return smoothMult, smoothLuck
end

local function SpawnAura(player, data, runtime, holdMult, luckBonus)
	local uid  = player.UserId

	-- Apply Epic Luck BEFORE rolling the tier!
	local epicLuckCfg = EpicUpgradeConfig.GetUpgradeConfig("epicLuck")
	if epicLuckCfg and epicLuckCfg.apply then 
		luckBonus = (luckBonus or 0) + epicLuckCfg.apply(data) 
	end

	-- Now roll utilizing TierConfig's centralized roll math
	local tier = TierConfig.Roll(luckBonus)
	local tierIndex = 1
	for i, t in ipairs(TierConfig.Tiers) do if t.name == tier.name then tierIndex=i; break end end

	local currentArea = data.currentArea or 1
	local areaModels = GetAreaAuraModels(currentArea)

	-- The Area Gating mechanism. If the model isn't here, it downgrades.
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
		if action == "start" then 
			holdStart[player.UserId] = nil 
			heldAccumulated[player.UserId] = nil
		end
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
		if (hatchery[uid] or 0) > 0.5 then 
			holdStart[uid] = now - (heldAccumulated[uid] or 0)
		else 
			UpdateHatcheryBridge:Fire(player, { current = 0, max = data and GetHatcheryMax(data) or AdminConfig.HatcheryMax }) 
		end
		return 
	end

	if action == "stop" then 
		holdStart[uid] = nil
		heldAccumulated[uid] = nil
		return 
	end

	if not data or not runtime then return end

	local capacity = GetHabitatCapacity(data)
	local storedCount = runtime.storedCubeCount or 0

	if storedCount >= capacity then HabitatFull:FireClient(player); return end

	if runtime.cubeCount >= capacity + 60 then return end 

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

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local HttpService         = game:GetService("HttpService")

local AdminConfig       = require(ReplicatedStorage.Modules.AdminConfig)
local UpgradeConfig     = require(ReplicatedStorage.Modules.UpgradeConfig)
local MutationConfig    = require(ReplicatedStorage.Modules.MutationConfig)
local GameManager       = require(ServerScriptService.GameManager)
local EpicUpgradeConfig = require(ReplicatedStorage.Modules.EpicUpgradeConfig)
local BoostManager      = require(ServerScriptService.BoostManager)
local BankConfig        = require(ReplicatedStorage.Modules.BankConfig)

local BridgeNet2      = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))
local UpdateHUDBridge = BridgeNet2.ServerBridge("UpdateHUD")
local ShipAurasBridge = BridgeNet2.ServerBridge("ShipAuras")

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
if not RemoteEvents:FindFirstChild("AuraDiscovered") then
	local ev = Instance.new("RemoteEvent")
	ev.Name = "AuraDiscovered"
	ev.Parent = RemoteEvents
end

local AuraDiscovered = RemoteEvents:WaitForChild("AuraDiscovered")

local playerTimers   = {}
local activeTrucks   = {}
local playerAutoMode = {}
local pendingPayouts = {}

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

local function SendHUDUpdate(player)
	local uid     = player.UserId
	local data    = GameManager.GetData(uid)
	local runtime = GameManager.GetRuntime(uid)
	if not data or not runtime then return end

	local storedCount = runtime.storedCubeCount or 0
	local activeMV    = runtime.activeMutatedValue or 0

	local boostMult = BoostManager.GetValueMultiplier(uid) * BoostManager.GetSpawnRateMultiplier(uid)
	local rate = math.floor(activeMV * boostMult)

	local habitatCap = UpgradeConfig.GetHabitatCapacity(data)
	local passiveInt = UpgradeConfig.GetPassiveInterval(data)

	local shipReduction = 0
	local shipCfg = EpicUpgradeConfig.GetUpgradeConfig("epicShipCooldown")
	if shipCfg and shipCfg.apply then
		shipReduction = shipCfg.apply(data)
	end

	local finalCooldown = math.max(0.5, AdminConfig.ShipInterval - shipReduction)

	UpdateHUDBridge:Fire(player, {
		currency        = data.currency,
		pendingAuras    = storedCount,
		habitatCapacity = habitatCap,
		rate            = rate,
		passiveInterval = passiveInt,
		totalEarned     = data.totalEarned    or 0,
		soulAuras       = data.soulAuras      or 0,
		farmEvaluation  = data.farmEvaluation or 0,
		shipCooldown    = finalCooldown,
		discoveredTiers = data.discoveredTiers or {},
		totalPlatformsShipped = data.totalPlatformsShipped or 0,
		totalCubesProduced    = data.totalCubesProduced or 0,
		shipCapacity          = UpgradeConfig.GetShippingCapacity(data) or AdminConfig.PlatformCapacity,
	})
end

local function TryDispatch(player)
	if AdminConfig.DisableShipping then return end
	local uid     = player.UserId
	local data    = GameManager.GetData(uid)
	local runtime = GameManager.GetRuntime(uid)
	if not data or not runtime then return end
	if data.inSpecialArea then return end
	if (activeTrucks[uid] or 0) >= 50 then return end

	local totalCubes = runtime.cubeCount
	if totalCubes <= 0 then return end

	local epicStorageBoost = 0
	local epicStorageCfg = EpicUpgradeConfig.GetUpgradeConfig("epicShipStorage")
	if epicStorageCfg and epicStorageCfg.apply then 
		epicStorageBoost = epicStorageCfg.apply(data)
	end

	local baseShipCap = UpgradeConfig.GetShippingCapacity and UpgradeConfig.GetShippingCapacity(data) or AdminConfig.PlatformCapacity
	local currentShipCapacity = baseShipCap + epicStorageBoost
	local toCollect = math.min(totalCubes, currentShipCapacity)		
	local cubeIds, cubes = GameManager.CollectOldestCubes(uid, toCollect)
	local collected  = #cubeIds
	if collected == 0 then return end

	local totalPayout = 0

	data.discoveredTiers = data.discoveredTiers or {}
	local newlyDiscovered = {}

	local doubleEarningsOwned = player:GetAttribute("Pass_DoubleEarnings")
	local passMultiplier = doubleEarningsOwned and BankConfig.Gamepasses.DoubleEarnings.bonus or 1.0

	local epicGoldenYield = 0
	local goldenYieldCfg = EpicUpgradeConfig.GetUpgradeConfig("epicGoldenAuraYield")
	if goldenYieldCfg and goldenYieldCfg.apply then epicGoldenYield = goldenYieldCfg.apply(data) end

	for _, cube in ipairs(cubes) do
		totalPayout = totalPayout + (MutationConfig.GetMutatedValue(cube) * passMultiplier)

		if epicGoldenYield > 0 and (cube.isGolden or cube.tierName == "Legendary") then
			data.goldenAuras = (data.goldenAuras or 0) + epicGoldenYield
		end

		local cArea = cube.currentArea or data.currentArea or 1
		local discoverKey = cArea .. "_" .. cube.tierName

		if not data.discoveredTiers[discoverKey] then
			data.discoveredTiers[discoverKey] = true
			table.insert(newlyDiscovered, {name = cube.tierName, color = cube.color, area = cArea})
		end
	end

	activeTrucks[uid] = (activeTrucks[uid] or 0) + 1
	data.totalPlatformsShipped = (data.totalPlatformsShipped or 0) + 1

	GameManager.SavePlayer(player)

	local dispatchId = HttpService:GenerateGUID(false)
	pendingPayouts[uid][dispatchId] = totalPayout

	SendHUDUpdate(player)

	ShipAurasBridge:Fire(player, {
		collected  = collected,
		payout     = totalPayout,
		dispatchId = dispatchId,
		capacity   = currentShipCapacity, -- Appended the capacity here so the client knows it immediately
	})

	if #newlyDiscovered > 0 then
		AuraDiscovered:FireClient(player, newlyDiscovered)
	end

	task.delay(AdminConfig.PlatformSpeed * 4 + 10, function()
		if Players:GetPlayerByUserId(uid) and pendingPayouts[uid] and pendingPayouts[uid][dispatchId] then
			pendingPayouts[uid][dispatchId] = nil
			activeTrucks[uid] = math.max(0, (activeTrucks[uid] or 1) - 1)
		end
	end)
end

ShipAurasBridge:Connect(function(player, payload)
	if type(payload) ~= "table" then return end
	local uid = player.UserId
	local action = payload.action
	local value = payload.value

	if action == "manual" then
		TryDispatch(player)

		local data          = GameManager.GetData(uid)
		local shipReduction = 0
		if data then
			local shipCfg = EpicUpgradeConfig.GetUpgradeConfig("epicShipCooldown")
			if shipCfg and shipCfg.apply then shipReduction = shipCfg.apply(data) end
		end

		playerTimers[uid] = math.max(0.5, AdminConfig.ShipInterval - shipReduction)
		return
	end

	if action == "setMode" then
		playerAutoMode[uid] = (value == "auto")
		return
	end

	if action == "payout" then
		if player:GetAttribute("TutorialFrozen") then return end

		local data = GameManager.GetData(uid)
		if not data then return end

		local dispatchId   = value
		local actualPayout = pendingPayouts[uid] and pendingPayouts[uid][dispatchId]

		if not actualPayout then
			warn("[Security] " .. player.Name .. " attempted invalid platform payout.")
			return
		end

		pendingPayouts[uid][dispatchId] = nil
		activeTrucks[uid] = math.max(0, (activeTrucks[uid] or 1) - 1)

		data.currency       = (data.currency        or 0) + actualPayout
		data.totalEarned    = (data.totalEarned     or 0) + actualPayout
		data.farmEvaluation = (data.farmEvaluation  or 0) + actualPayout

		GameManager.SavePlayer(player)

		SendHUDUpdate(player)

		ShipAurasBridge:Fire(player, {
			action = "payoutConfirmed",
			amount = actualPayout
		})
	end
end)

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local TweenService       = game:GetService("TweenService")
local Debris             = game:GetService("Debris")
local UserInputService   = game:GetService("UserInputService")
local CollectionService  = game:GetService("CollectionService")

local AdminConfig        = require(ReplicatedStorage.Modules:WaitForChild("AdminConfig"))
local Formatter          = require(ReplicatedStorage.Modules:WaitForChild("NumberFormatter"))
local UITheme            = require(ReplicatedStorage.Modules:WaitForChild("UITheme"))

local BridgeNet2             = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))
local UpdateHUDBridge        = BridgeNet2.ClientBridge("UpdateHUD")
local ShipAurasBridge        = BridgeNet2.ClientBridge("ShipAuras")
local UpdateHatcheryBridge   = BridgeNet2.ClientBridge("UpdateHatchery")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local HabitatFull = ReplicatedStorage.RemoteEvents:WaitForChild("HabitatFull")
local mainHUD   = playerGui:WaitForChild("MainHUD")

local isAutoMode          = AdminConfig.AutoDispatch
local HabitatHolder       = workspace:WaitForChild("HabitatHolder")

local GoldenAurasLabel    = mainHUD:FindFirstChild("GoldenAurasLabel", true)
local AurmerLabel         = mainHUD:FindFirstChild("AurmerLabel", true)

local BANK_POPUP_OFFSET_X = 15
local BANK_POPUP_OFFSET_Y = 45

local function AddPaddingToLabel(label)
	if label and not label:FindFirstChildOfClass("UIPadding") then
		local pad = Instance.new("UIPadding", label)
		pad.PaddingLeft = UDim.new(0, 35)
	end
end

AddPaddingToLabel(GoldenAurasLabel)
AddPaddingToLabel(AurmerLabel)

if GoldenAurasLabel then
	local scale = GoldenAurasLabel:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", GoldenAurasLabel)
	scale.Scale = 1.15
end

local displayedCurrency   = 0
local liveGoldenAuras     = 0
local liveAurmers         = 0
local ratePerSecond       = 0
local pendingAuras        = 0
local habitatCapacity     = AdminConfig.BaseHabitatCapacity or 50
local shipCapacity        = AdminConfig.BaseShipCapacity or 5
local passiveInterval     = AdminConfig.PassiveInterval
local currentCooldownTime = 15
local isShipOnCooldown    = false
local sharedCooldownEnd   = 0
local manualCooldownLoopID = 0
local autoLoopID          = 0
local currentHatcheryLevel = AdminConfig.HatcheryMax or 150
local offsetSetTime = 0
local MAX_OFFSET_LIFETIME = 1.5 
local lastActualPending = 0

local localLastPiggyBank  = 0
local isFirstBankLoad     = true

local accumulatedBankDiff = 0
local activeBankPopup = nil
local activeBankTweens = {}

local function FormatCurrency(n)
	local num = tonumber(n) or 0
	if num < 1000 then return string.format("%.2f", num)
	else return Formatter.Format(num) end
end

local function FormatNumber(n) return Formatter.Format(math.floor(tonumber(n) or 0)) end

local hud        = playerGui:WaitForChild("MainHUD")
local curr       = hud:WaitForChild("CurrencyLabel")
local rate       = hud:WaitForChild("RateLabel")
local sendButton = hud:WaitForChild("SendButton")
local modeToggle = hud:WaitForChild("ModeToggle")

CollectionService:AddTag(sendButton, "Tutorial_SendShipBtn")
CollectionService:AddTag(modeToggle, "Tutorial_ToggleShipBtn")

local autoTimerLabel = Instance.new("TextLabel")
autoTimerLabel.Name = "AutoTimerLabel"
autoTimerLabel.Size = UDim2.new(0, 45, 1, 0)
autoTimerLabel.Position = UDim2.new(1, 26, 0, 0)
autoTimerLabel.BackgroundTransparency = 1
autoTimerLabel.Text = ""
autoTimerLabel.TextColor3 = Color3.fromRGB(0, 255, 128)
autoTimerLabel.TextScaled = true
autoTimerLabel.Font = Enum.Font.GothamBold
autoTimerLabel.TextXAlignment = Enum.TextXAlignment.Left
autoTimerLabel.Visible = false
autoTimerLabel.Parent = modeToggle

local autoHabitatLabel = Instance.new("TextLabel")
autoHabitatLabel.Name = "AutoHabitatLabel"
autoHabitatLabel.Size = sendButton.Size
autoHabitatLabel.Position = sendButton.Position
autoHabitatLabel.AnchorPoint = sendButton.AnchorPoint
autoHabitatLabel.BackgroundTransparency = 1
autoHabitatLabel.Font = Enum.Font.FredokaOne
autoHabitatLabel.TextColor3 = Color3.fromRGB(160, 200, 255)
autoHabitatLabel.TextScaled = true
autoHabitatLabel.TextXAlignment = Enum.TextXAlignment.Center
autoHabitatLabel.Visible = false
autoHabitatLabel.Parent = sendButton.Parent

local autoHabStroke = Instance.new("UIStroke", autoHabitatLabel)
autoHabStroke.Thickness = 3
autoHabStroke.Transparency = 0.1
autoHabStroke.Color = Color3.new(0, 0, 0)

local autoHabConstraint = Instance.new("UITextSizeConstraint", autoHabitatLabel)
autoHabConstraint.MaxTextSize = 26

local manualTimerLabel = Instance.new("TextLabel")
manualTimerLabel.Name = "ManualTimerLabel"
manualTimerLabel.Size = UDim2.new(0, 50, 1, 0)
manualTimerLabel.AnchorPoint = Vector2.new(1, 0)
manualTimerLabel.Position = UDim2.new(0, -10, 0, 0)
manualTimerLabel.BackgroundTransparency = 1
manualTimerLabel.Text = ""
manualTimerLabel.TextColor3 = Color3.fromRGB(0, 180, 255)
manualTimerLabel.TextScaled = true
manualTimerLabel.Font = Enum.Font.GothamBold
manualTimerLabel.TextXAlignment = Enum.TextXAlignment.Right
manualTimerLabel.Visible = false
manualTimerLabel.ZIndex = 50
manualTimerLabel.Parent = sendButton

local manualTimerStroke = Instance.new("UIStroke", manualTimerLabel)
manualTimerStroke.Color = Color3.new(0, 0, 0)
manualTimerStroke.Thickness = 2

local function UpdateWalletVisual()
	local pendingCash = player:GetAttribute("LocalPendingPayout") or 0
	curr.Text = "Currency: $" .. FormatCurrency(math.max(0, displayedCurrency - pendingCash))
end

local function UpdateAuraVisual()
	if not GoldenAurasLabel then return end
	local pendingAurasVis = player:GetAttribute("LocalPendingAuras") or 0
	GoldenAurasLabel.Text = FormatNumber(math.max(0, liveGoldenAuras - pendingAurasVis))
end

player:GetAttributeChangedSignal("LocalSpend"):Connect(function()
	local spend = player:GetAttribute("LocalSpend") or 0
	if spend > 0 then
		displayedCurrency = math.max(0, displayedCurrency - spend)
		UpdateWalletVisual()
		player:SetAttribute("LocalSpend", 0)
	end
end)

player:GetAttributeChangedSignal("LocalAuraSpend"):Connect(function()
	local spend = player:GetAttribute("LocalAuraSpend") or 0
	if spend > 0 then
		liveGoldenAuras = math.max(0, liveGoldenAuras - spend)
		UpdateAuraVisual()
		player:SetAttribute("LocalAuraSpend", 0)
	end
end)

player:GetAttributeChangedSignal("LocalPendingPayout"):Connect(UpdateWalletVisual)
player:GetAttributeChangedSignal("LocalPendingAuras"):Connect(UpdateAuraVisual)

player:GetAttributeChangedSignal("LivePiggyBank"):Connect(function()
	local currentBank = player:GetAttribute("LivePiggyBank") or 0
	local diff = currentBank - localLastPiggyBank

	if isFirstBankLoad then
		diff = 0
		isFirstBankLoad = false
	end

	localLastPiggyBank = currentBank

	if diff > 0 and GoldenAurasLabel then
		accumulatedBankDiff = accumulatedBankDiff + diff

		local targetPos = GoldenAurasLabel.AbsolutePosition
		local targetSize = GoldenAurasLabel.AbsoluteSize

		local startX = targetPos.X + (targetSize.X / 2) + BANK_POPUP_OFFSET_X
		local startY = targetPos.Y + targetSize.Y + BANK_POPUP_OFFSET_Y 

		if not activeBankPopup or not activeBankPopup.Parent then
			activeBankPopup = Instance.new("TextLabel")
			activeBankPopup.Font = Enum.Font.FredokaOne
			activeBankPopup.TextScaled = true
			activeBankPopup.TextColor3 = Color3.fromRGB(255, 210, 20)
			activeBankPopup.BackgroundTransparency = 1
			activeBankPopup.Size = UDim2.new(0, 120, 0, 20)
			activeBankPopup.AnchorPoint = Vector2.new(0.5, 0)

			local stroke = Instance.new("UIStroke", activeBankPopup)
			stroke.Color = Color3.fromRGB(80, 40, 0)
			stroke.Thickness = 3

			local effectGui = playerGui:FindFirstChild("JuiceGui_PiggyBank")
			if not effectGui then
				effectGui = Instance.new("ScreenGui")
				effectGui.Name = "JuiceGui_PiggyBank"
				effectGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
				effectGui.DisplayOrder = 100 
				effectGui.IgnoreGuiInset = true 
				effectGui.Parent = playerGui
			end
			activeBankPopup.Parent = effectGui

			local scale = Instance.new("UIScale", activeBankPopup)
			scale.Scale = 1
		end

		for _, tw in ipairs(activeBankTweens) do
			tw:Cancel()
		end
		activeBankTweens = {}

		activeBankPopup.Text = "+" .. Formatter.Format(accumulatedBankDiff) .. " Banked!"
		activeBankPopup.Position = UDim2.new(0, startX, 0, startY)
		activeBankPopup.TextTransparency = 0

		local stroke = activeBankPopup:FindFirstChildOfClass("UIStroke")
		if stroke then stroke.Transparency = 0 end

		local scale = activeBankPopup:FindFirstChildOfClass("UIScale")
		if scale then
			scale.Scale = 1.25
			local popTween = TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {Scale = 1})
			popTween:Play()
		end

		local currentUpdateId = tick()
		activeBankPopup:SetAttribute("UpdateId", currentUpdateId)

		task.delay(0.8, function()
			if activeBankPopup and activeBankPopup:GetAttribute("UpdateId") == currentUpdateId then

				local driftTween = TweenService:Create(activeBankPopup, TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
					Position = UDim2.new(0, startX, 0, startY + 25),
					TextTransparency = 1
				})

				table.insert(activeBankTweens, driftTween)

				if stroke then
					local strokeTween = TweenService:Create(stroke, TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
						Transparency = 1
					})
					table.insert(activeBankTweens, strokeTween)
					strokeTween:Play()
				end

				driftTween:Play()

				driftTween.Completed:Connect(function(playbackState)
					if playbackState == Enum.PlaybackState.Completed then
						if activeBankPopup and activeBankPopup:GetAttribute("UpdateId") == currentUpdateId then
							accumulatedBankDiff = 0
							activeBankPopup:Destroy()
							activeBankPopup = nil
						end
					end
				end)
			end
		end)
	end


end)

local function FormatRate(perSecond)
	if perSecond <= 0 then return "$0.00/sec" end
	return "$" .. FormatCurrency(perSecond) .. "/sec"
end

local function GetRateColor(pending, capacity)
	local ratio = math.clamp((pending or 0) / (capacity or 50), 0, 1)
	if ratio >= 1        then return Color3.fromRGB(255, 60,  60)
	elseif ratio >= 0.75 then return Color3.fromRGB(255, 200,  0)
	elseif ratio >= 0.5  then return Color3.fromRGB(80,  255, 80)
	else                      return Color3.fromRGB(80,  180, 80)
	end
end

local function UpdateHabitatBar(actualPending, capacity)
	local offset = player:GetAttribute("HabitatVisualOffset") or 0
	local capacityToUse = capacity > 0 and capacity or habitatCapacity
	local visualPending = math.clamp(actualPending + offset, 0, capacityToUse)
	local ratio    = math.clamp(visualPending / capacityToUse, 0, 1)
	local color    = GetRateColor(visualPending, capacityToUse)
	local model    = HabitatHolder:FindFirstChild("HabitatModel")

	if model then
		local gui    = model:FindFirstChild("HabitatGui")
		local barBg  = gui and gui:FindFirstChild("BarBackground")
		local barFill = barBg and barBg:FindFirstChild("BarFill")

		if barBg then
			local oldLabel1 = barBg:FindFirstChild("CountLabel")
			local oldLabel2 = barBg:FindFirstChild("AmountLabel")
			if oldLabel1 then oldLabel1.Visible = false end
			if oldLabel2 then oldLabel2.Visible = false end
		end
		
		-- Flash the bar whenever a cube actually lands in storage, even if the
		-- displayed number is temporarily held flat by the offset system.
		if actualPending > lastActualPending and barFill then
			local pulse = barFill:FindFirstChild("StoragePulse") or Instance.new("Frame")
			pulse.Name = "StoragePulse"
			pulse.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
			pulse.BackgroundTransparency = 0.5
			pulse.BorderSizePixel = 0
			pulse.Size = UDim2.new(1, 0, 1, 0)
			pulse.ZIndex = barFill.ZIndex + 1
			pulse.Parent = barFill
			TweenService:Create(pulse, TweenInfo.new(0.3, Enum.EasingStyle.Sine), { BackgroundTransparency = 1 }):Play()
			Debris:AddItem(pulse, 0.35)
		end
		lastActualPending = actualPending

		if barFill then
			TweenService:Create(barFill, TweenInfo.new(0.3), {
				Size = UDim2.new(ratio, 0, 1, 0),
				BackgroundColor3 = color,
			}):Play()
		end

		if gui then
			local textCap = gui:FindFirstChild("3DCapacityLabel")
			if not textCap then
				textCap = Instance.new("TextLabel")
				textCap.Name = "3DCapacityLabel"
				textCap.Size = UDim2.new(1, 0, 1, 0)
				textCap.Position = UDim2.new(0, 0, 0, 0)
				textCap.BackgroundTransparency = 1
				textCap.Font = Enum.Font.GothamBlack 
				textCap.TextScaled = true
				textCap.TextColor3 = Color3.fromRGB(255, 255, 255)
				textCap.Parent = gui

				local stroke = Instance.new("UIStroke", textCap)
				stroke.Thickness = 3
				stroke.Color = Color3.fromRGB(0, 0, 0)
			end

			textCap.Text = FormatNumber(visualPending) .. " / " .. FormatNumber(capacityToUse)

			local prevPending = textCap:GetAttribute("LastPending") or 0

			if visualPending < prevPending then
				textCap.TextColor3 = Color3.fromRGB(100, 255, 128) 
				TweenService:Create(textCap, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					TextColor3 = Color3.fromRGB(255, 255, 255)
				}):Play()
			elseif visualPending >= capacityToUse and capacityToUse > 0 then
				textCap.TextColor3 = Color3.fromRGB(255, 80, 80) 
			elseif visualPending > prevPending then
				if textCap.TextColor3 == Color3.fromRGB(255, 80, 80) then
					textCap.TextColor3 = Color3.fromRGB(255, 255, 255)
				end
			end

			textCap:SetAttribute("LastPending", visualPending)

			local shipTextCap = gui:FindFirstChild("3DShipCapacityLabel")
			if not shipTextCap then
				shipTextCap = Instance.new("TextLabel")
				shipTextCap.Name = "3DShipCapacityLabel"
				shipTextCap.Size = UDim2.new(1, 0, 0.45, 0)
				shipTextCap.Position = UDim2.new(0, 1, 1, 0)
				shipTextCap.BackgroundTransparency = 1
				shipTextCap.Font = Enum.Font.GothamBold 
				shipTextCap.TextScaled = true
				shipTextCap.TextColor3 = Color3.fromRGB(180, 220, 255)
				shipTextCap.Parent = gui

				local stroke = Instance.new("UIStroke", shipTextCap)
				stroke.Thickness = 2
				stroke.Color = Color3.fromRGB(0, 0, 0)
			end

			shipTextCap.Text = "Ship Capacity: " .. FormatNumber(shipCapacity)
		end
	end


end

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

UpdateHatcheryBridge:Connect(function(info)
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

task.spawn(function()
	while true do
		task.wait(0.25)
		local offset = player:GetAttribute("HabitatVisualOffset") or 0
		if offset > 0 and tick() - offsetSetTime > MAX_OFFSET_LIFETIME then
			player:SetAttribute("HabitatVisualOffset", 0)
			UpdateHabitatBar(pendingAuras, habitatCapacity)
		end
	end
end)

local function SyncManualCooldownVisuals()
	if isAutoMode then
		manualTimerLabel.Visible = false
		return
	end

	local progressContainer = sendButton:FindFirstChild("CooldownProgress")
	local fillPart          = progressContainer and progressContainer:FindFirstChild("Fill")
	local textTarget        = sendButton:FindFirstChildOfClass("TextLabel") or sendButton

	local uiStroke = sendButton:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke", sendButton)
	uiStroke.Thickness = 1.5

	if not fillPart then return end

	sendButton.ClipsDescendants = false
	progressContainer.ClipsDescendants = true

	local progCorner = progressContainer:FindFirstChildOfClass("UICorner") or Instance.new("UICorner", progressContainer)
	local btnCorner = sendButton:FindFirstChildOfClass("UICorner")
	if btnCorner then progCorner.CornerRadius = btnCorner.CornerRadius end

	progressContainer.Size     = UDim2.new(1, 0, 1, 0)
	progressContainer.Position = UDim2.new(0, 0, 0, 0)
	progressContainer.AnchorPoint = Vector2.new(0, 0)

	fillPart.BorderSizePixel = 0
	fillPart.AnchorPoint     = Vector2.new(0, 1)
	fillPart.Position        = UDim2.new(0, 0, 1, 0)

	manualCooldownLoopID += 1
	local currentLoop = manualCooldownLoopID
	local timeLeft    = sharedCooldownEnd - tick()

	if timeLeft > 0 then
		sendButton.BackgroundColor3    = Color3.fromRGB(0, 160, 255)
		uiStroke.Color                 = Color3.fromRGB(0, 220, 255)
		fillPart.BackgroundColor3      = Color3.fromRGB(0, 0, 0)
		fillPart.BackgroundTransparency = 0.55

		isShipOnCooldown = true
		if textTarget ~= sendButton then sendButton.Text = "" end

		manualTimerLabel.Visible = true

		local pct = timeLeft / currentCooldownTime
		fillPart.Size = UDim2.new(1, 0, pct, 0)

		TweenService:Create(fillPart, TweenInfo.new(timeLeft, Enum.EasingStyle.Linear), {
			Size = UDim2.new(1, 0, 0, 0)
		}):Play()

		task.spawn(function()
			while manualCooldownLoopID == currentLoop do
				local currentLeft = sharedCooldownEnd - tick()

				if currentLeft <= 0 then break end

				manualTimerLabel.Text = string.format("%.1fs", currentLeft)
				task.wait(0.05) 
			end

			if manualCooldownLoopID == currentLoop then
				isShipOnCooldown  = false
				textTarget.Text   = ""
				fillPart.Size     = UDim2.new(1, 0, 0, 0)
				manualTimerLabel.Visible = false

				if pendingAuras <= 0 then
					sendButton.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
					uiStroke.Color = Color3.fromRGB(50, 50, 50)
				else
					sendButton.BackgroundColor3 = Color3.fromRGB(0, 160, 255)
					uiStroke.Color = Color3.fromRGB(0, 220, 255)
				end
			end
		end)
	else
		isShipOnCooldown = false
		textTarget.Text  = ""
		fillPart.Size    = UDim2.new(1, 0, 0, 0)
		manualTimerLabel.Visible = false

		if pendingAuras <= 0 then
			sendButton.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
			uiStroke.Color = Color3.fromRGB(50, 50, 50)
		else
			sendButton.BackgroundColor3 = Color3.fromRGB(0, 160, 255)
			uiStroke.Color = Color3.fromRGB(0, 220, 255)
		end
	end


end

local function UpdateSendButton()
	if AdminConfig.DisableShipping then
		sendButton.Visible = false
		autoHabitatLabel.Visible = false
		return
	end

	if isAutoMode then
		sendButton.Visible = false
		autoHabitatLabel.Visible = true

		local offset = player:GetAttribute("HabitatVisualOffset") or 0
		local visualPending = math.clamp(pendingAuras + offset, 0, habitatCapacity)

		autoHabitatLabel.Text = "Waiting: " .. FormatNumber(visualPending) .. " / " .. FormatNumber(habitatCapacity)

		if visualPending >= habitatCapacity then
			autoHabitatLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
		elseif visualPending > 0 then
			autoHabitatLabel.TextColor3 = Color3.fromRGB(100, 255, 128)
		else
			autoHabitatLabel.TextColor3 = Color3.fromRGB(160, 160, 180)
		end
	else
		autoHabitatLabel.Visible = false
		sendButton.Visible = true 
		SyncManualCooldownVisuals()
	end


end

player:GetAttributeChangedSignal("HabitatVisualOffset"):Connect(function()
	UpdateHabitatBar(pendingAuras, habitatCapacity)
	UpdateSendButton()
end)

local autoProgressContainer = Instance.new("Frame")
autoProgressContainer.Name             = "AutoProgressContainer"
autoProgressContainer.Size             = UDim2.new(0, 12, 1, 0)
autoProgressContainer.Position         = UDim2.new(1, 8, 0, 0)
autoProgressContainer.BackgroundColor3 = Color3.fromRGB(24, 60, 24)
autoProgressContainer.BorderSizePixel  = 0
autoProgressContainer.Visible          = false
autoProgressContainer.Parent           = modeToggle
Instance.new("UICorner", autoProgressContainer).CornerRadius = UDim.new(0.5, 0)

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
		autoTimerLabel.Visible = true

		task.spawn(function()
			local activeTween = nil

			while isAutoMode and autoLoopID == currentLoop do
				local currentLeft = sharedCooldownEnd - tick()

				if currentLeft <= 0 then
					if pendingAuras > 0 then
						ShipAurasBridge:Fire({ action = "manual" })
						if type(shared.TutorialRecordShipSent) == "function" then shared.TutorialRecordShipSent() end
					end

					sharedCooldownEnd = tick() + currentCooldownTime
					currentLeft = currentCooldownTime

					if activeTween then activeTween:Cancel() end
					autoFill.Size = UDim2.new(1, 0, 1, 0)
					activeTween = TweenService:Create(autoFill, TweenInfo.new(currentLeft, Enum.EasingStyle.Linear), {
						Size = UDim2.new(1, 0, 0, 0)
					})
					activeTween:Play()
				end

				autoTimerLabel.Text = string.format("%.1fs", math.max(0, currentLeft))
				task.wait(0.05) 
			end

			if activeTween then activeTween:Cancel() end
		end)
	else
		modeToggle.BackgroundColor3 = Color3.fromRGB(38, 38, 45)
		textLabel.Text              = "Mode: Manual"
		textLabel.TextColor3        = Color3.fromRGB(220, 230, 240)
		if uiStroke then uiStroke.Color = Color3.fromRGB(100, 180, 220) end

		autoProgressContainer.Visible = false
		autoTimerLabel.Visible = false
	end


end

sendButton.MouseButton1Down:Connect(function()
	if AdminConfig.DisableShipping then return end
	if isAutoMode or isShipOnCooldown or pendingAuras <= 0 then return end

	if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_SendShip") then return end

	ShipAurasBridge:Fire({ action = "manual" })
	sharedCooldownEnd = tick() + currentCooldownTime
	SyncManualCooldownVisuals()

	if type(shared.TutorialRecordShipSent) == "function" then shared.TutorialRecordShipSent() end
	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end


end)

modeToggle.MouseButton1Down:Connect(function()
	if AdminConfig.DisableShipping then return end

	if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_ToggleAutoShip") then return end

	isAutoMode = not isAutoMode
	ShipAurasBridge:Fire({ action = "setMode", value = isAutoMode and "auto" or "manual" })

	UpdateModeToggleVisuals()
	UpdateSendButton()

	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end


end)

UpdateModeToggleVisuals()

if AdminConfig.DisableShipping then
	isAutoMode         = false
	sendButton.Visible = false
	modeToggle.Visible = false
end



UpdateHUDBridge:Connect(function(stats)

	if stats.currency ~= nil then
		displayedCurrency = stats.currency
		player:SetAttribute("LiveCurrency", displayedCurrency)
		UpdateWalletVisual()
	end

	if stats.goldenAuras ~= nil then
		liveGoldenAuras = stats.goldenAuras
		player:SetAttribute("LiveGoldenAuras", liveGoldenAuras)
		UpdateAuraVisual()
	end

	if stats.aurmers ~= nil then
		liveAurmers = stats.aurmers
		player:SetAttribute("LiveAurmers", liveAurmers)
		if AurmerLabel then
			AurmerLabel.Text = FormatNumber(liveAurmers)
		end
	end

	if stats.prestigeCount ~= nil then
		local currentPrestige = player:GetAttribute("PrestigeCount") or 0
		if stats.prestigeCount > currentPrestige then
			player:SetAttribute("PrestigeCount", stats.prestigeCount)
			player:SetAttribute("HabitatVisualOffset", 0)
			pendingAuras = 0
		end
	end

	if stats.currentArea ~= nil then
		local currentArea = player:GetAttribute("CurrentArea") or 1
		if stats.currentArea ~= currentArea then
			player:SetAttribute("CurrentArea", stats.currentArea)
			player:SetAttribute("HabitatVisualOffset", 0)
			pendingAuras = 0
		end
	end

	if stats.shipCapacity ~= nil then
		shipCapacity = stats.shipCapacity
		UpdateHabitatBar(pendingAuras, habitatCapacity)
	end

	-- FIX: ONLY update capacity if it explicitly exists and is valid. Never fall back to nil/0.
	if stats.habitatCapacity ~= nil and stats.habitatCapacity > 0 then
		habitatCapacity = stats.habitatCapacity
	end

	-- AFTER
	if stats.pendingAuras ~= nil then
		if stats.pendingAuras < pendingAuras then
			local diff = pendingAuras - stats.pendingAuras
			local currentOffset = player:GetAttribute("HabitatVisualOffset") or 0
			player:SetAttribute("HabitatVisualOffset", currentOffset + diff)
			offsetSetTime = tick()

		elseif stats.pendingAuras > pendingAuras then
			local increase = stats.pendingAuras - pendingAuras
			local currentOffset = player:GetAttribute("HabitatVisualOffset") or 0
			player:SetAttribute("HabitatVisualOffset", math.max(0, currentOffset - increase))
		end

		pendingAuras = stats.pendingAuras
		UpdateHabitatBar(pendingAuras, habitatCapacity)
		UpdateSendButton() 
	end

	

	if stats.rate ~= nil then
		passiveInterval = stats.passiveInterval or passiveInterval
		local serverRate = stats.rate
		ratePerSecond = (passiveInterval > 0 and serverRate > 0) and serverRate / passiveInterval or 0

		rate.Text = FormatRate(ratePerSecond)
		local offset = player:GetAttribute("HabitatVisualOffset") or 0
		TweenService:Create(rate, TweenInfo.new(0.3), { TextColor3 = GetRateColor(pendingAuras + offset, habitatCapacity) }):Play()	
	end

	if stats.shipCooldown ~= nil then
		currentCooldownTime = stats.shipCooldown
	end


end)

ShipAurasBridge:Connect(function(info)
	if type(info) == "table" and info.action == "payoutConfirmed" then
		local amt = info.amount or 0
		if amt > 0 then
			if type(shared.TutorialRecordEarned) == "function" then shared.TutorialRecordEarned(amt) end
			curr.TextColor3 = Color3.fromRGB(80, 255, 80)
			TweenService:Create(curr, TweenInfo.new(0.5), { TextColor3 = Color3.fromRGB(255, 255, 255) }):Play()
		end
	end
end)

local function RefreshLook()
	if GoldenAurasLabel then UITheme.ApplyFlair(GoldenAurasLabel, "GoldStroke") end
	if AurmerLabel then UITheme.ApplyFlair(AurmerLabel, "AurmerStroke") end
end

task.wait(2)
RefreshLook()

local function ForceSpawnTeleport()
	local char = player.Character or player.CharacterAdded:Wait()
	local spawnLoc = workspace:WaitForChild("SpawnLocation", 10)

	if char and spawnLoc then
		task.wait(0.1) 
		char:PivotTo(spawnLoc.CFrame * CFrame.new(0, (spawnLoc.Size.Y / 2) + 3, 0))
	end


end

task.spawn(ForceSpawnTeleport)

--ClickHandler
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
		local storageAnchors = model:FindFirstChild("StorageAnchors", true)

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
						activeCubes[cid] = nil

						CubeStoredBridge:Fire(cid)

						local visualStoredCount = 0
						for _, d in pairs(cubeDataMap) do
							if d.isStored then visualStoredCount += 1 end
						end

						if visualStoredCount > MAX_VISUAL_STORED then
							pcall(function() PoolManager.ReturnAura(data.instance) end)
							cubeDataMap[cid] = nil
							return
						end

						if data.rateLabel and data.rateLabel.Parent and data.rateLabel.Parent:IsA("BillboardGui") then 
							data.rateLabel.Parent.Enabled = false 
						end

						local root = GetRootPart(auraObj)
						if root then
							if storageAnchors and storageAnchors:IsA("BasePart") then
								-- Scatter cubes naturally within the StorageAnchors local bounding box
								local size = storageAnchors.Size
								local randomLocalOffset = Vector3.new(
									(math.random() - 0.5) * size.X,
									(math.random() - 0.5) * size.Y,
									(math.random() - 0.5) * size.Z
								)
								local targetWorldCFrame = storageAnchors.CFrame * CFrame.new(randomLocalOffset)
								auraObj:PivotTo(targetWorldCFrame)
							else
								-- Fallback for areas without StorageAnchors yet
								local dropOffset = Vector3.new(math.random(-9, -4), math.random(2, 7), math.random(-5, 5))
								auraObj:PivotTo(CFrame.new(storage.Position + dropOffset))
							end

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
		activeCubes[info.cubeId] = true 

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
				activeCubes[id] = nil
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
