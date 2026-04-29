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

local HABITAT_PART = workspace:WaitForChild("HabitatModel").Position

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

-- VFXController
-- Location: StarterPlayer > StarterPlayerScripts > VFXController
--
-- CHANGES:
--   VFX_CONFIG entries now support a `scale` field.
--   EmitVFX passes scale to shared.vfx.emit(scale, clone).
--   scale = 1 is default, 2 = double size, 0.5 = half size.
--
-- SETUP:
--   VFX templates in ReplicatedStorage/VFX/ OR directly in workspace.
--   InvertedDistortion is in workspace — the script finds it there automatically.
--
-- ADDING NEW VFX:
--   1. Add the VFX Model to workspace or ReplicatedStorage/VFX/
--   2. Add an entry to VFX_CONFIG with vfxName, positions, and scale
--   3. That's it — no other changes needed

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris            = game:GetService("Debris")

local player = Players.LocalPlayer

local VFX_FOLDER = ReplicatedStorage:FindFirstChild("VFX")
local AuraHolder = workspace:WaitForChild("AuraHolder")
local Habitat = workspace:WaitForChild("HabitatModel").Position

---------------------------------------------------------------
-- VFX CONFIG
-- vfxName  = name of Model in ReplicatedStorage/VFX/ or workspace
-- positions = where to emit: "AuraHolder", "Habitat", "Character", or Vector3
-- scale    = size multiplier passed to shared.vfx.emit(scale, ...)
--            1.0 = default, 2.0 = twice as big, 0.5 = half size
---------------------------------------------------------------
local VFX_CONFIG = {
	Prestige = {
		vfxName   = "InvertedDistortion",
		positions = { "Habitat" },
		scale     = 1.5,
	},
	PortalEnter = {
		vfxName   = "InvertedDistortion",
		positions = { "Habitat" },
		scale     = 2.0,
	},
	AreaUnlocked = {
		vfxName   = "InvertedDistortion",
		positions = { "Habitat" },
		scale     = 1.0,
	},
	ShopPurchase = {
		vfxName   = "",   -- fill in when you have a purchase VFX
		positions = { "Character" },
		scale     = 1.0,
	},
	BoostActivated = {
		vfxName   = "",
		positions = { "AuraHolder" },
		scale     = 7.0,
	},
	TierUpgrade = {
		vfxName   = "",
		positions = { "AuraHolder" },
		scale     = 1.0,
	},
	LegendarySpawn = {
		vfxName   = "",
		positions = { "AuraHolder" },
		scale     = 1.5,
	},
}

local EMIT_CLEANUP_DELAY = 6

---------------------------------------------------------------
-- GetWorldPosition
---------------------------------------------------------------
local function GetWorldPosition(target)
	if typeof(target) == "Vector3" then return target end

	if target == "AuraHolder" then
		return AuraHolder:GetPivot().Position
	end
	

	if target == "Habitat" then
		return Habitat:GetPivot().Position
	end

	if target == "Character" then
		local char = player.Character
		if char then
			local hrp = char:FindFirstChild("HumanoidRootPart")
			if hrp then return hrp.Position end
		end
		return AuraHolder:GetPivot().Position
	end

	return Vector3.new(0, 0, 0)
end

---------------------------------------------------------------
-- EmitVFX
-- Finds the VFX template, clones it, moves it to worldPos,
-- calls shared.vfx.emit(scale, clone), then Debris cleans it up.
---------------------------------------------------------------
local function EmitVFX(vfxName, worldPos, scale)
	if not vfxName or vfxName == "" then return end

	-- Wait for Forge to initialize (shared.vfx set by ForgeInit)
	if not shared.vfx then
		local waited = 0
		repeat task.wait(0.1); waited += 0.1
		until shared.vfx or waited >= 10
		if not shared.vfx then
			warn("[VFXController] shared.vfx not available — Forge not initialized")
			return
		end
	end

	scale = scale or 1

	-- Check ReplicatedStorage/VFX/ first, then workspace directly
	local template = VFX_FOLDER and VFX_FOLDER:FindFirstChild(vfxName)

	if template then
		-- Clone from template so the original is reusable
		local clone = template:Clone()
		clone.Parent = workspace

		if clone:IsA("Model") then
			clone:PivotTo(CFrame.new(worldPos))
		elseif clone:IsA("BasePart") then
			clone.CFrame = CFrame.new(worldPos)
		end

		local ok, err = pcall(function()
			if scale ~= 1 then
				shared.vfx.emit(scale, clone)
			else
				shared.vfx.emit(clone)
			end
		end)
		if not ok then warn("[VFXController] Emit error: " .. tostring(err)) end

		Debris:AddItem(clone, EMIT_CLEANUP_DELAY)

	else
		-- No template — look for it directly in workspace (e.g. InvertedDistortion)
		local wsObj = workspace:FindFirstChild(vfxName)
		if wsObj then
			-- Move it to the target position and emit in-place
			if wsObj:IsA("Model") then
				wsObj:PivotTo(CFrame.new(worldPos))
			elseif wsObj:IsA("BasePart") then
				wsObj.CFrame = CFrame.new(worldPos)
			end

			local ok, err = pcall(function()
				if scale ~= 1 then
					shared.vfx.emit(scale, wsObj)
				else
					shared.vfx.emit(wsObj)
				end
			end)
			if not ok then warn("[VFXController] Emit error: " .. tostring(err)) end
		else
			warn("[VFXController] VFX not found in VFX folder or workspace: '" .. vfxName .. "'")
		end
	end
end

---------------------------------------------------------------
-- FireEvent — looks up config and emits at all positions
---------------------------------------------------------------
local function FireEvent(eventName)
	local cfg = VFX_CONFIG[eventName]
	if not cfg or not cfg.vfxName or cfg.vfxName == "" then return end

	for _, target in ipairs(cfg.positions or {}) do
		EmitVFX(cfg.vfxName, GetWorldPosition(target), cfg.scale)
	end
end

---------------------------------------------------------------
-- Public API
-- shared.VFXController is set so other LocalScripts can use it:
--   shared.VFXController.Fire("Prestige")
--   shared.VFXController.FireAt("InvertedDistortion", Vector3.new(0,10,0), 2.0)
--   shared.VFXController.FireAtTarget("InvertedDistortion", "AuraHolder", 1.5)
---------------------------------------------------------------
local VFXController = {}

function VFXController.Fire(eventName)
	FireEvent(eventName)
end

function VFXController.FireAt(vfxName, worldPos, scale)
	EmitVFX(vfxName, worldPos, scale)
end

function VFXController.FireAtTarget(vfxName, target, scale)
	EmitVFX(vfxName, GetWorldPosition(target), scale)
end

shared.VFXController = VFXController

---------------------------------------------------------------
-- Event hooks — auto-fire VFX on game events
---------------------------------------------------------------
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")

-- Prestige or portal entry
local PrestigeComplete = RemoteEvents:WaitForChild("PrestigeComplete")
PrestigeComplete.OnClientEvent:Connect(function(info)
	if info.isPortalEntry then
		FireEvent("PortalEnter")
	else
		FireEvent("Prestige")
	end
end)

-- Portal threshold hit
local AreaUnlocked = RemoteEvents:WaitForChild("AreaUnlocked")
AreaUnlocked.OnClientEvent:Connect(function()
	FireEvent("AreaUnlocked")
end)

-- Shop upgrade purchased
local UpgradeUpdated = RemoteEvents:WaitForChild("UpgradeUpdated")
UpgradeUpdated.OnClientEvent:Connect(function(info)
	if info.type == "purchased" then
		FireEvent("ShopPurchase")
	end
end)

-- Boost activated
local BoostUpdated = RemoteEvents:WaitForChild("BoostUpdated")
local prevActiveCounts = {}
BoostUpdated.OnClientEvent:Connect(function(state)
	for boostId, data in pairs(state) do
		if type(data) == "table" and data.activeCount then
			local prev = prevActiveCounts[boostId] or 0
			if data.activeCount > prev then
				FireEvent("BoostActivated")
			end
			prevActiveCounts[boostId] = data.activeCount
		end
	end
end)

-- Tier upgrade / legendary
local CubeMutated = RemoteEvents:WaitForChild("CubeMutated")
CubeMutated.OnClientEvent:Connect(function(info)
	if info.mutationType == "tierUpgrade" then
		if info.tierName == "Legendary" then
			FireEvent("LegendarySpawn")
		else
			FireEvent("TierUpgrade")
		end
	end
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

local HABITAT        = workspace:WaitForChild("Habitat")
local HabitatGui     = HABITAT:WaitForChild("HabitatGui")
local BarBackground  = HabitatGui:WaitForChild("BarBackground")
local BarFill        = BarBackground:WaitForChild("BarFill")
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

local function FormatNumber(n)
	return Formatter.Format(n)
end

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
	TweenService:Create(BarFill, TweenInfo.new(0.3), {
		Size = UDim2.new(ratio, 0, 1, 0)
	}):Play()
	local color
	if ratio >= 1     then color = Color3.fromRGB(255, 60,  60)
	elseif ratio >= 0.75 then color = Color3.fromRGB(255, 200, 0)
	elseif ratio >= 0.5  then color = Color3.fromRGB(80,  255, 80)
	else                      color = Color3.fromRGB(80,  180, 80) end
	TweenService:Create(BarFill, TweenInfo.new(0.3), { BackgroundColor3 = color }):Play()
end

local hud        = playerGui:WaitForChild("MainHUD")
local curr       = hud:WaitForChild("CurrencyLabel")
local rate       = hud:WaitForChild("RateLabel")
local sendButton = hud:WaitForChild("SendButton")
local modeToggle = hud:WaitForChild("ModeToggle")

local function UpdateSendButton()
	if AdminConfig.DisableShipping then sendButton.Visible = false; return end
	sendButton.Visible = not isAutoMode and (pendingAuras or 0) > 0
end
-----------------------------------------------------------------------------
-- ✨ NEW MODE TOGGLE VISUALS (AUTO ACTIVE INDICATOR)
-----------------------------------------------------------------------------
local function UpdateModeToggleVisuals()
	local textLabel = modeToggle:FindFirstChildOfClass("TextLabel") or modeToggle
	local uiStroke = modeToggle:FindFirstChildOfClass("UIStroke")

	if isAutoMode then
		modeToggle.BackgroundColor3 = Color3.fromRGB(24, 60, 24) -- Dark green background
		textLabel.Text = "[AUTO ACTIVE]"
		textLabel.TextColor3 = Color3.fromRGB(0, 255, 128) -- Neon Green Text
		if uiStroke then uiStroke.Color = Color3.fromRGB(0, 255, 128) end -- Green border
	else
		modeToggle.BackgroundColor3 = Color3.fromRGB(38, 38, 45) -- Default dark background
		textLabel.Text = "Mode: Manual"
		textLabel.TextColor3 = Color3.fromRGB(220, 230, 240) -- Default subtext color
		if uiStroke then uiStroke.Color = Color3.fromRGB(100, 180, 220) end -- Muted Cyan border
	end
end

-----------------------------------------------------------------------------
-- ✨ NEW VISUAL COOLDOWN (VERTICAL DRAIN BAR & TEXT FIX)
-----------------------------------------------------------------------------
local function UpdateShipButtonCooldownVisuals()
	local progressContainer = sendButton:FindFirstChild("CooldownProgress")
	local fillPart = progressContainer and progressContainer:FindFirstChild("Fill")

	if not fillPart then
		warn("[UI] Could not find CooldownProgress container or Fill part.")
		return
	end

	isShipOnCooldown = true

	-- ✨ THE DRAIN FIX: Force the bar to anchor to the bottom so it drains top-to-bottom
	fillPart.AnchorPoint = Vector2.new(0, 1)
	fillPart.Position = UDim2.new(0, 0, 1, 0)

	-- ✨ THE OVERLAP FIX: Find the TextLabel if it exists, otherwise use the button itself
	local textTarget = sendButton:FindFirstChildOfClass("TextLabel") or sendButton
	if textTarget ~= sendButton then
		sendButton.Text = "" -- Erase button text to guarantee no overlaps!
	end

	-- 1. Turn button grey and red warning border
	sendButton.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
	local uiStroke = sendButton:FindFirstChildOfClass("UIStroke")
	if uiStroke then uiStroke.Color = Color3.fromRGB(255, 50, 50) end

	-- 2. Make sure text is visible (since we fixed the overlap)
	textTarget.TextTransparency = 0 

	-- 3. The Vertical Drain Loop
	fillPart.Size = UDim2.new(1, 0, 1, 0) -- Start Full
	local timeLeft = currentCooldownTime
	local step = 0.05

	while timeLeft > 0 do
		local percentage = timeLeft / currentCooldownTime

		-- Update text cleanly
		textTarget.Text = "COOLDOWN (" .. string.format("%.1f", timeLeft) .. "s)"

		-- Animate the bar draining down
		TweenService:Create(fillPart, TweenInfo.new(step, Enum.EasingStyle.Linear), {
			Size = UDim2.new(1, 0, percentage, 0)
		}):Play()

		task.wait(step)
		timeLeft -= step
	end

	-- 4. Unlock and Restore
	isShipOnCooldown = false
	textTarget.Text = ""
	sendButton.BackgroundColor3 = Color3.fromRGB(0, 255, 128) -- Default green
	if uiStroke then uiStroke.Color = Color3.fromRGB(0, 255, 255) end -- Default cyan border
end

-- SHIP BUTTON CLICK
sendButton.MouseButton1Down:Connect(function()
	if AdminConfig.DisableShipping then return end

	-- Prevent clicking if Auto is on, if it's on cooldown, or if no auras
	if isAutoMode or isShipOnCooldown or (pendingAuras or 0) <= 0 then return end

	-- Tell server, then start visual loop
	ShipAuras:FireServer("manual")
	UpdateShipButtonCooldownVisuals()
end)

-- TOGGLE BUTTON CLICK
modeToggle.MouseButton1Down:Connect(function()
	if AdminConfig.DisableShipping then return end

	isAutoMode = not isAutoMode
	ShipAuras:FireServer("setMode", isAutoMode and "auto" or "manual")

	-- Update both button visuals
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

	if stats.goldenAuras ~= nil then
		GoldenAurasLabel.Text = "GAURAS: " .. stats.goldenAuras
	end
	
	if stats.currency ~= nil then
		local newServerCurrency = stats.currency
		if newServerCurrency < prevServerCurrency then
			displayedCurrency = newServerCurrency
			curr.TextColor3 = Color3.fromRGB(255, 80, 80)
			TweenService:Create(curr, TweenInfo.new(0.3), {
				TextColor3 = Color3.fromRGB(255, 255, 255)
			}):Play()
		elseif newServerCurrency > displayedCurrency then
			displayedCurrency = newServerCurrency
		end
		prevServerCurrency = newServerCurrency
		serverCurrency     = newServerCurrency
	end

	-- Habitat bar: FIX — only update when pendingAuras is explicitly included
	if stats.pendingAuras ~= nil then
		pendingAuras    = stats.pendingAuras
		habitatCapacity = stats.habitatCapacity or habitatCapacity
		UpdateHabitatBar(pendingAuras, habitatCapacity)
		UpdateSendButton()
	end

	-- Rate label: only update when rate is explicitly included
	if stats.rate ~= nil then
		passiveInterval = stats.passiveInterval or passiveInterval
		local serverRate = stats.rate
		ratePerSecond = (passiveInterval > 0 and serverRate > 0)
			and serverRate / passiveInterval or 0

		rate.Text = FormatRate(ratePerSecond)
		local targetColor = GetRateColor(pendingAuras, habitatCapacity)
		TweenService:Create(rate, TweenInfo.new(0.3), { TextColor3 = targetColor }):Play()
	end

	-- ✨ THE NEW FIX: Catch the ship cooldown math!
	if stats.shipCooldown ~= nil then
		currentCooldownTime = stats.shipCooldown
	end
end)

RunService.RenderStepped:Connect(function(dt)
	if ratePerSecond > 0 then
		displayedCurrency += ratePerSecond * dt
	end
	curr.Text = "Currency: $" .. FormatNumber(displayedCurrency)
end)


local function RefreshLook()
	UITheme.ApplyFlair(GoldenAurasLabel, "GoldStroke")
end

task.wait(2)
RefreshLook()

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
local HABITAT     = workspace:WaitForChild("Habitat")

-- FIX: HABITAT is a Model — .Position would find the child Part named "Position"
-- instead of returning a Vector3. Use GetPivot().Position for the model center.
local function GetHabitatPos()
	return HABITAT:GetPivot().Position
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

local function AttachLabels(platform, payout, multiplier)
	local payoutBB = Instance.new("BillboardGui")
	payoutBB.Size = UDim2.new(0, 200, 0, 40)
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
	multBB.Size = UDim2.new(0, 160, 0, 28)
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

	TweenService:Create(payoutLabel, TweenInfo.new(0.3), {
		TextTransparency = 0, TextStrokeTransparency = 0.3
	}):Play()
	TweenService:Create(multLabel, TweenInfo.new(0.3), {
		TextTransparency = 0, TextStrokeTransparency = 0.4
	}):Play()
end

local function PayoutPopup(position, payout, multiplier)
	local anchor = Instance.new("Part")
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Anchored = true
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.Position = position
	anchor.Parent = workspace

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 300, 0, 80)
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

	TweenService:Create(bb,
		TweenInfo.new(1.8, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ StudsOffset = Vector3.new(0, 18, 0) }
	):Play()

	task.delay(0.6, function()
		TweenService:Create(label,
			TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ TextTransparency = 1, TextStrokeTransparency = 1 }
		):Play()
	end)

	Debris:AddItem(anchor, 2.5)
end

local function GetAuraBlocksNearHabitat()
	local blocks = {}
	local habitatPos = GetHabitatPos()  -- FIX: was HABITAT.Position (returned child Part)

	for _, obj in ipairs(workspace:GetChildren()) do
		if obj.Name == "HoverPlatform" or obj == HABITAT
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
