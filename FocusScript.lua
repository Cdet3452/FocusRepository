-- AreaManager
-- Location: ServerScriptService > AreaManager
--
-- PHASE 4 — AREA CHOICE + PRESTIGE LIMIT SUPPORT:
--   FIX: MergeUnlockedAreas never removes saved unlocks.
--   FIX: hasPrestigedThisArea reset on ALL area travel (forward + backward).
--   TravelToArea server handler for player-chosen destinations.
--   Batched AreaUnlocked notification.
--   AreaRegistry is sole source for thresholds/names/multipliers.

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AdminConfig    = require(ReplicatedStorage.Modules.AdminConfig)
local UpgradeConfig  = require(ReplicatedStorage.Modules.UpgradeConfig)
local PrestigeModule = require(ReplicatedStorage.Modules.PrestigeModule)
local AreaRegistry   = require(ReplicatedStorage.Modules.AreaRegistry)
local GameManager    = require(ServerScriptService.GameManager)
local BoostManager   = require(ServerScriptService.BoostManager)

local AreaUpdated  = ReplicatedStorage.RemoteEvents:WaitForChild("AreaUpdated")
local AreaUnlocked = ReplicatedStorage.RemoteEvents:WaitForChild("AreaUnlocked")
local EnterPortal  = ReplicatedStorage.RemoteEvents:WaitForChild("EnterPortal")
local TravelToArea = ReplicatedStorage.RemoteEvents:WaitForChild("TravelToArea")
local AreaChanged  = ReplicatedStorage.RemoteEvents:WaitForChild("AreaChanged")

local PrestigeComplete = ReplicatedStorage.RemoteEvents:WaitForChild("PrestigeComplete")
local UpgradeUpdated   = ReplicatedStorage.RemoteEvents:WaitForChild("UpgradeUpdated")
local UpdateHUD        = ReplicatedStorage.RemoteEvents:WaitForChild("UpdateHUD")
local UpdateHatchery   = ReplicatedStorage.RemoteEvents:WaitForChild("UpdateHatchery")

local lastPortalEntry = {}
local lastUnlockCount = {}
local PORTAL_COOLDOWN = 3

---------------------------------------------------------------
-- UNLOCK CALCULATION — MERGES with saved list, never removes
---------------------------------------------------------------
local function MergeUnlockedAreas(data, farmEval)
	local currentArea = data.currentArea or 1
	local maxArea     = AreaRegistry.GetMaxArea()
	local seen, merged = {}, {}
	if type(data.unlockedAreas) == "table" then
		for _, v in ipairs(data.unlockedAreas) do
			if not seen[v] then seen[v] = true; table.insert(merged, v) end
		end
	end
	for i = 1, currentArea do
		if AreaRegistry.Areas[i] and not seen[i] then
			seen[i] = true; table.insert(merged, i)
		end
	end
	for i = currentArea + 1, maxArea do
		local area = AreaRegistry.Areas[i]
		if area and farmEval >= (area.threshold or 0) then
			if not seen[i] then seen[i] = true; table.insert(merged, i) end
		end
	end
	table.sort(merged)
	data.unlockedAreas = merged
	return merged
end

---------------------------------------------------------------
-- FORWARD TRAVEL — prestige-style reset + area change
---------------------------------------------------------------
local function DoForwardTravel(player, targetArea)
	local uid     = player.UserId
	local data    = GameManager.GetData(uid)
	local runtime = GameManager.GetRuntime(uid)
	if not data then return false end

	local earned       = data.totalEarned or 0
	local rawSoulAuras = PrestigeModule.CalcSoulAuras(earned)
	local soulMult     = BoostManager.GetSoulMultiplier(uid)
	local newSoulAuras = math.floor(rawSoulAuras * soulMult)

	local previousSoulAuras  = data.soulAuras or 0
	local previousMultiplier = PrestigeModule.GetMultiplier(previousSoulAuras)

	local bonusPercent  = AdminConfig.PrestigeStartBonusPercent or 0.05
	local prestigeBonus = math.max(math.floor(earned * bonusPercent), 50)

	if newSoulAuras > 0 then
		data.soulAuras = previousSoulAuras + newSoulAuras
	end
	data.prestigeCount = (data.prestigeCount or 0) + 1
	local newMultiplier = PrestigeModule.GetMultiplier(data.soulAuras)

	-- Add target to unlocked BEFORE resetting
	if type(data.unlockedAreas) ~= "table" then data.unlockedAreas = { 1 } end
	local has = false
	for _, v in ipairs(data.unlockedAreas) do if v == targetArea then has = true end end
	if not has then table.insert(data.unlockedAreas, targetArea); table.sort(data.unlockedAreas) end

	-- Reset run data
	data.currentArea            = targetArea
	data.hasPrestigedThisArea   = false   -- PRESTIGE LIMIT: reset on area travel
	data.currency               = prestigeBonus
	data.totalEarned            = 0
	data.farmEvaluation         = 0
	data.pendingAuras           = 0
	data.pendingPayout          = 0
	data.pendingBonusPayout     = 0
	data.lastPayout             = 0

	for key, _ in pairs(data.upgrades) do data.upgrades[key] = 0 end

	if runtime then
		runtime.cubes          = {}
		runtime.cubeOrder      = {}
		runtime.cubeCount      = 0
		runtime.nextCubeId     = 1
		runtime.lastActiveTime = tick()
		runtime.sessionStart   = tick()
	end

	lastUnlockCount[uid] = nil

	local PrestigeReset = ServerScriptService:FindFirstChild("PrestigeReset")
	if PrestigeReset then PrestigeReset:Fire(player) end

	PrestigeComplete:FireClient(player, {
		newSoulAuras         = newSoulAuras,
		totalSoulAuras       = data.soulAuras,
		previousMultiplier   = previousMultiplier,
		newMultiplier        = newMultiplier,
		prestigeCount        = data.prestigeCount,
		prestigeBonus        = prestigeBonus,
		isPortalEntry        = true,
		soulBoostActive      = soulMult > 1,
		hasPrestigedThisArea = false,
	})

	local resetState = {}
	for _, tierData in ipairs(UpgradeConfig.Tiers) do
		for upgradeId, cfg in pairs(tierData.upgrades) do
			resetState[upgradeId] = {
				level    = 0,
				maxLevel = cfg.maxLevel,
				cost     = UpgradeConfig.CalculateCost(upgradeId, 0),
				maxed    = false,
			}
		end
	end
	UpgradeUpdated:FireClient(player, {
		type     = "fullState",
		upgrades = resetState,
		currency = prestigeBonus,
	})

	UpdateHatchery:FireClient(player, {
		current = AdminConfig.HatcheryMax,
		max     = AdminConfig.HatcheryMax,
	})

	task.wait(0.3)
	UpdateHUD:FireClient(player, {
		currency             = data.currency,
		pendingAuras         = 0,
		habitatCapacity      = AdminConfig.BaseHabitatCapacity,
		rate                 = 0,
		passiveInterval      = AdminConfig.PassiveInterval,
		totalEarned          = 0,
		soulAuras            = data.soulAuras or 0,
		farmEvaluation       = 0,
		hasPrestigedThisArea = false,
	})

	AreaChanged:FireClient(player, {
		newArea            = targetArea,
		areaName           = AreaRegistry.GetName(targetArea),
		areaMultiplier     = AreaRegistry.GetMultiplier(targetArea),
		newSoulAuras       = newSoulAuras,
		totalSoulAuras     = data.soulAuras,
		previousMultiplier = previousMultiplier,
		newMultiplier      = newMultiplier,
		unlockedAreas      = data.unlockedAreas,
	})

	GameManager.SavePlayer(player)
	return true
end

local function DoBackwardTravel(player, targetArea)
	local uid  = player.UserId
	local data = GameManager.GetData(uid)
	if not data then return false end

	local isUnlocked = false
	if type(data.unlockedAreas) == "table" then
		for _, v in ipairs(data.unlockedAreas) do
			if v == targetArea then isUnlocked = true; break end
		end
	end
	if not isUnlocked then return false end

	data.currentArea          = targetArea
	-- REMOVED: data.hasPrestigedThisArea = false (This prevents the exploit)
	lastUnlockCount[uid]      = nil

	AreaChanged:FireClient(player, {
		newArea              = targetArea,
		areaName             = AreaRegistry.GetName(targetArea),
		areaMultiplier       = AreaRegistry.GetMultiplier(targetArea),
		travelType           = "backward",
		unlockedAreas        = data.unlockedAreas,
		hasPrestigedThisArea = data.hasPrestigedThisArea, -- Send current state to client
	})

	GameManager.SavePlayer(player)
	return true
end

---------------------------------------------------------------
-- TRAVEL TO AREA
---------------------------------------------------------------
TravelToArea.OnServerEvent:Connect(function(player, targetArea)
	local uid = player.UserId
	local now = tick()
	if lastPortalEntry[uid] and now - lastPortalEntry[uid] < PORTAL_COOLDOWN then return end
	local data = GameManager.GetData(uid)
	if not data then return end
	targetArea = tonumber(targetArea)
	if not targetArea or not AreaRegistry.Get(targetArea) then return end
	local currentArea = data.currentArea or 1
	if targetArea == currentArea then return end
	lastPortalEntry[uid] = now
	if targetArea > currentArea then
		local isUnlocked = false
		if type(data.unlockedAreas) == "table" then
			for _, v in ipairs(data.unlockedAreas) do
				if v == targetArea then isUnlocked = true; break end
			end
		end
		if not isUnlocked then return end
		DoForwardTravel(player, targetArea)
	else
		DoBackwardTravel(player, targetArea)
	end
end)

---------------------------------------------------------------
-- ENTER PORTAL (convenience)
---------------------------------------------------------------
EnterPortal.OnServerEvent:Connect(function(player)
	local uid = player.UserId
	local now = tick()
	if lastPortalEntry[uid] and now - lastPortalEntry[uid] < PORTAL_COOLDOWN then return end
	local data = GameManager.GetData(uid)
	if not data then return end
	local bestArea = AreaRegistry.GetBestNextArea(data.currentArea or 1, data.farmEvaluation or 0)
	if not bestArea then return end
	lastPortalEntry[uid] = now
	DoForwardTravel(player, bestArea)
end)

---------------------------------------------------------------
-- 1-SECOND PUSH
---------------------------------------------------------------
task.spawn(function()
	while true do
		task.wait(1)
		for _, player in ipairs(Players:GetPlayers()) do
			local uid  = player.UserId
			local data = GameManager.GetData(uid)
			if not data then continue end

			local currentArea = data.currentArea or 1
			local farmEval    = data.farmEvaluation or 0
			local unlocked    = MergeUnlockedAreas(data, farmEval)

			local prevCount     = lastUnlockCount[uid] or #unlocked
			local newCount      = #unlocked
			local newlyUnlocked = newCount - prevCount

			local nextGoalArea, nextGoalThreshold = nil, nil
			for i = currentArea + 1, AreaRegistry.GetMaxArea() do
				local area = AreaRegistry.Areas[i]
				if area and farmEval < (area.threshold or 0) then
					nextGoalArea = i; nextGoalThreshold = area.threshold; break
				end
			end

			local portalReady = false
			for _, v in ipairs(unlocked) do
				if v > currentArea then portalReady = true; break end
			end

			AreaUpdated:FireClient(player, {
				currentArea          = currentArea,
				areaName             = AreaRegistry.GetName(currentArea),
				farmEvaluation       = farmEval,
				nextThreshold        = nextGoalThreshold,
				nextArea             = nextGoalArea,
				nextAreaName         = nextGoalArea and AreaRegistry.GetName(nextGoalArea) or nil,
				portalReady          = portalReady,
				unlockedAreas        = unlocked,
				maxArea              = AreaRegistry.GetMaxArea(),
				hasPrestigedThisArea = data.hasPrestigedThisArea == true,
			})

			if newlyUnlocked > 0 and prevCount > 0 then
				local highestNew = unlocked[#unlocked]
				AreaUnlocked:FireClient(player, {
					newAreasCount  = newlyUnlocked,
					highestNew     = highestNew,
					highestNewName = AreaRegistry.GetName(highestNew),
					unlockedAreas  = unlocked,
				})
			end

			lastUnlockCount[uid] = newCount
		end
	end
end)

---------------------------------------------------------------
-- PLAYER JOIN / LEAVE
---------------------------------------------------------------
Players.PlayerAdded:Connect(function(player)
	lastUnlockCount[player.UserId] = nil
	lastPortalEntry[player.UserId] = nil
end)
Players.PlayerRemoving:Connect(function(player)
	lastUnlockCount[player.UserId] = nil
	lastPortalEntry[player.UserId] = nil
end)


local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")

local AdminConfig = require(ReplicatedStorage.Modules:WaitForChild("AdminConfig"))
local GameManager = require(ServerScriptService:WaitForChild("GameManager"))

-- 🛡️ SAFETY CHECK: Using the correct name from your screenshot
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
	if not AURA_ORIGIN then 
		warn("❌ AURA_ORIGIN (AuraModel/AuraHolder) NOT FOUND IN WORKSPACE!")
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

	-- 3. POSITION & LAUNCH
	local spawnPart = AURA_ORIGIN:FindFirstChild("Position")
	if not spawnPart then warn("❌ No 'Position' part in AuraModel!"); return end

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

		-- ✨ THE 3D BOOST FIX:
		sfx.RollOffMaxDistance = 500 -- How many studs away you can still hear it
		sfx.RollOffMinDistance = 10  -- Distance before the volume starts dropping
		sfx.RollOffMode = Enum.RollOffMode.Linear -- Makes the drop-off feel more natural

		sfx.PlaybackSpeed = 1 + (math.random(-10, 10) / 100) 
		sfx:Play()
		Debris:AddItem(sfx, 2)
	end

	-- ✨ NEW: SPAWN VFX
	local vfxFolder = ReplicatedStorage:FindFirstChild("VFX")
	if vfxFolder and vfxFolder:FindFirstChild("AuraSpawnVFX") then
		local spawnEffect = vfxFolder.AuraSpawnVFX:Clone()
		spawnEffect.Position = mainPart.Position
		spawnEffect.Parent = workspace

		-- Tell all ParticleEmitters inside the part to burst!
		for _, emitter in ipairs(spawnEffect:GetDescendants()) do
			if emitter:IsA("ParticleEmitter") then
				emitter:Emit(emitter:GetAttribute("EmitCount") or 25) 
			end
		end
		Debris:AddItem(spawnEffect, 3) -- Deletes the effect part after 3 seconds
	end

	-- 9. CLICK & REWARDS (🛡️ Back to Custom Style)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "AuraPrompt"
	prompt.ActionText = "Collect"
	prompt.ObjectText = isElite and "Elite Aura" or "Golden Aura"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 30
	prompt.RequiresLineOfSight = false 

	-- 🛡️ Hide the default bubble and tag it for the cool UI
	prompt.Style = Enum.ProximityPromptStyle.Custom 
	prompt:SetAttribute("IsElite", isElite == true) 
	game:GetService("CollectionService"):AddTag(prompt, "AuraHologram")

	prompt.Parent = mainPart


	-- 5. LANDING LOGIC & LIFETIME START
	local maxB = (isElite and AdminConfig.PhysicsMaxBouncesElite or AdminConfig.PhysicsMaxBouncesRegular) or 1
	local hasLanded = false

	-- ✨ THE FIX: We must define these so the script has numbers to calculate!
	local bounces = 0
	local lastB = 0 

	mainPart.Touched:Connect(function(hit)
		-- Now lastB has a starting value of 0, so tick() - lastB won't crash!
		if hasLanded or (tick() - lastB < 0.15) then return end

		if hit.Position.Y <= mainPart.Position.Y then
			-- Now bounces has a starting value, so we can safely add 1 to it!
			bounces += 1
			lastB = tick()

			-- 🎵 SOUND SPOT 1: Touches the ground / Bounces
			local sfxFolder = ReplicatedStorage:FindFirstChild("SFX")
			if sfxFolder and sfxFolder:FindFirstChild("Landing") then
				local sfx = sfxFolder.Landing:Clone()
				sfx.Parent = mainPart
				sfx:Play()
				Debris:AddItem(sfx, 2)
			end

			if bounces > maxB then
				hasLanded = true
				mainPart.AssemblyLinearVelocity = Vector3.zero
				mainPart.AssemblyAngularVelocity = Vector3.zero 

				-- ✨ NEW: LANDING VFX
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

				-- 🛡️ LIFETIME STARTS NOW
				local despawnTime = isElite and AdminConfig.PhysicsEliteDespawn or AdminConfig.PhysicsRegularDespawn
				if type(despawnTime) ~= "number" then 
					despawnTime = 15 -- Will stay on the ground for 15 seconds!
				end

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
			-- ✨ THE GOLDEN AURA MATH FIX: 
			-- Elite gives 5 Golden Auras, Regular gives 1. (Change these numbers if you want!)
			local r = isElite and 5 or 1 

			data.goldenAuras += r

			local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
			if RemoteEvents and RemoteEvents:FindFirstChild("UpdateHUD") then
				RemoteEvents.UpdateHUD:FireClient(player, { goldenAuras = data.goldenAuras })
			end
		end

		-- 🎵 SOUND SPOT 2: When Collected
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

-- =======================================================
-- 💥 TUTORIAL BURST LISTENER
-- =======================================================
local RemoteEvents = ReplicatedStorage:FindFirstChild("RemoteEvents")
if RemoteEvents then
	local burstEvent = RemoteEvents:FindFirstChild("TutorialBurst")
	if not burstEvent then
		-- Auto-create the remote if it doesn't exist yet so you don't have to!
		burstEvent = Instance.new("RemoteEvent")
		burstEvent.Name = "TutorialBurst"
		burstEvent.Parent = RemoteEvents
	end

	burstEvent.OnServerEvent:Connect(function(player, amount)
		-- 🛡️ Anti-Exploit: Cap at 25 so hackers can't spawn 10,000 and crash the server
		if type(amount) ~= "number" or amount > 50 then 
			amount = 15 
		end

		-- 💥 Trigger the Burst
		task.spawn(function()
			for i = 1, amount do
				-- Pass 'false' so it only drops standard Golden Auras, not game-breaking Elites
				CreatePhysicsAura(false) 
				task.wait(0.15) -- The delay makes them pop out like a fountain
			end
		end)
	end)
end

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

local AuraSpawned    = ReplicatedStorage.RemoteEvents:WaitForChild("AuraSpawned")
local ProduceAura    = ReplicatedStorage.RemoteEvents:WaitForChild("ProduceAura")
local UpdateHatchery = ReplicatedStorage.RemoteEvents:WaitForChild("UpdateHatchery")
local UpdateHUD      = ReplicatedStorage.RemoteEvents:WaitForChild("UpdateHUD")
local HabitatFull    = ReplicatedStorage.RemoteEvents:WaitForChild("HabitatFull")
local CubeMutated    = ReplicatedStorage.RemoteEvents:WaitForChild("CubeMutated")
local CubeSmushed    = ReplicatedStorage.RemoteEvents:WaitForChild("CubeSmushed")

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
if not RemoteEvents:FindFirstChild("CubeStored") then
	local ev = Instance.new("RemoteEvent")
	ev.Name = "CubeStored"
	ev.Parent = RemoteEvents
end
local CubeStored = RemoteEvents:WaitForChild("CubeStored")

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

-- ✨ Uses optimized counters directly
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

	UpdateHUD:FireClient(player, {
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
				ReplicatedStorage.RemoteEvents.CubeMutatedBatch:FireClient(player, mutationBatch)
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

	AuraSpawned:FireClient(player, {
		cubeId=cubeId, tier=tier.name, color=tier.color,
		glow=tier.glow, value=totalValue, spawnPos=spawnPos,
		currentArea = currentArea 
	})
end

ProduceAura.OnServerEvent:Connect(function(player, action)
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
			UpdateHatchery:FireClient(player, { current = 0, max = data and GetHatcheryMax(data) or AdminConfig.HatcheryMax })
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
		UpdateHatchery:FireClient(player, { current = 0, max = data and GetHatcheryMax(data) or AdminConfig.HatcheryMax })
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
	UpdateHatchery:FireClient(player, { current=hatchery[uid], max=GetHatcheryMax(data) })
end)

CubeStored.OnServerEvent:Connect(function(player, cubeId)
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

CubeSmushed.OnServerEvent:Connect(function(player, cubeId)
	local uid = player.UserId

	-- ✨ THIS FIXED IT: Destroys the aura properly via the manager so it strips its value from your income!
	GameManager.RemoveCube(uid, cubeId)
	SendHUDUpdate(player)

	local data = GameManager.GetData(uid)
	UpdateHatchery:FireClient(player, { current = hatchery[uid], max = GetHatcheryMax(data) })
end)

-- BoostManager
-- Location: ServerScriptService > BoostManager (ModuleScript)
--
-- STACKING CHANGE: Additive like Egg Inc Bird Feed.
--   Formula: total = 1 + (multiplier - 1) * activeStackCount

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AdminConfig = require(ReplicatedStorage.Modules.AdminConfig)
local GameManager = require(ServerScriptService.GameManager)
local BoostConfig = require(ReplicatedStorage.Modules.BoostConfig)
local AchievementConfig = require(ReplicatedStorage.Modules.AchievementConfig)

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

local activeStacks = {}  -- [uid] = { {boostId, endsAt}, ... }

---------------------------------------------------------------
-- Helpers
---------------------------------------------------------------
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

---------------------------------------------------------------
-- ADDITIVE multiplier helper
---------------------------------------------------------------
local function AdditiveMultiplier(uid, boostId)
	PruneExpired(uid)
	local cfg = BoostConfig.Get(boostId)
	if not cfg then return 1 end
	local bonus  = (cfg.multiplier or 2) - 1 
	local count  = GetActiveStacks(uid, boostId)	
	return 1 + bonus * count
end

---------------------------------------------------------------
-- Public API
---------------------------------------------------------------
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

---------------------------------------------------------------
-- BUY
---------------------------------------------------------------
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
	ReplicatedStorage.RemoteEvents.UpdateHUD:FireClient(player, {
		goldenAuras    = data.goldenAuras,
		boostInventory = data.boostInventory,
	})
end)

---------------------------------------------------------------
-- ACTIVATE
---------------------------------------------------------------
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

	-- ✨ FIX: Handle Instant / One-Shot Boosts (Like CashCheck)
	if cfg.duration == 0 then
		if cfg.effectType == "cashCheck" then
			local payout = math.floor((data.farmEvaluation or 0) * (cfg.multiplier or 5))
			if payout > 0 then
				data.currency    = (data.currency or 0) + payout
				data.totalEarned = (data.totalEarned or 0) + payout

				-- Send a special flag so the UI knows it is allowed to snap UPWARD!
				ReplicatedStorage.RemoteEvents.UpdateHUD:FireClient(player, {
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

---------------------------------------------------------------
-- Player lifecycle
---------------------------------------------------------------
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

-- EpicUpgradeManager
-- Location: ServerScriptService > EpicUpgradeManager
--
-- Purchases permanent upgrades with Golden Auras.
-- Public API: GetBonus(uid, id), GetAllBonuses(uid), ResendState(player)
-- REQUIRES: RemoteEvents PurchaseEpicUpgrade, EpicUpgradeUpdated

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local EpicUpgradeConfig = require(ReplicatedStorage.Modules.EpicUpgradeConfig)
local GameManager       = require(ServerScriptService.GameManager)

local PurchaseEpicUpgrade = ReplicatedStorage.RemoteEvents:WaitForChild("PurchaseEpicUpgrade")
local EpicUpgradeUpdated  = ReplicatedStorage.RemoteEvents:WaitForChild("EpicUpgradeUpdated")
local UpdateHUD           = ReplicatedStorage.RemoteEvents:WaitForChild("UpdateHUD")

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
	local newLv = lv + 1; local maxed = newLv >= cfg.maxLevel
	EpicUpgradeUpdated:FireClient(player, {
		type="purchased", upgradeId=upgradeId, level=newLv,
		maxLevel=cfg.maxLevel, cost=maxed and 0 or EpicUpgradeConfig.CalculateCost(upgradeId, lv), maxed=maxed,
	})
	UpdateHUD:FireClient(player, { goldenAuras = data.goldenAuras })
	GameManager.SavePlayer(player)
end)

local function SendFullState(player)
	local data = GameManager.GetData(player.UserId)
	if not data then return end
	local ep = data.epicUpgrades or {}; local payload = {}
	-- SURGICAL FIX: Open Tiers first, then find Upgrades
	for _, tierData in ipairs(EpicUpgradeConfig.Tiers) do
		for id, cfg in pairs(tierData.upgrades) do
			local lv = ep[id] or 0
			local maxed = lv >= cfg.maxLevel
			-- Calculate cost using the new dynamic function
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
	local cfg = EpicUpgradeConfig.GetUpgradeConfig(upgradeId); if not cfg then return 0 end
	local data = GameManager.GetData(uid); return cfg.apply(data or { epicUpgrades = {} })
end
function EpicUpgradeManager.GetAllBonuses(uid)
	local data = GameManager.GetData(uid) or { epicUpgrades = {} }; local b = {}
	-- SURGICAL FIX: Nested loop to find all active bonuses
	for _, tierData in ipairs(EpicUpgradeConfig.Tiers) do
		for id, cfg in pairs(tierData.upgrades) do
			b[id] = cfg.apply(data)
		end
	end
	return b
end
function EpicUpgradeManager.ResendState(player) SendFullState(player) end
return EpicUpgradeManager

-- GameManager
-- Location: ServerScriptService > GameManager

local DataStoreService  = game:GetService("DataStoreService")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDB       = DataStoreService:GetDataStore("PlayerData_v1")
local AdminConfig    = require(ReplicatedStorage.Modules.AdminConfig)
local UpgradeConfig  = require(ReplicatedStorage.Modules.UpgradeConfig)
local MutationConfig = require(ReplicatedStorage.Modules.MutationConfig)

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
		settings = { sfxEnabled=true, musicEnabled=true },
		farmEvaluation = 0,
		currentArea    = 1,
		unlockedAreas  = { 1 },
		goldenAuras = AdminConfig.GoldenAuraStart or 10,
		boostInventory = { AuraRush=0, SpawnBoost=0, SoulBoost=0 },
		hasPrestigedThisArea = false,
		epicUpgrades         = {},
		tutorialProgress     = {},
		tutorialComplete     = false,
		claimedMail          = {},
		unlockedMail         = {},
	}
end

local function DefaultRuntime()
	return {
		cubes              = {},
		cubeOrder          = {},
		cubeCount          = 0,
		storedCubeCount    = 0,      -- ✨ Pre-tracked for fast HUD updates
		activeMutatedValue = 0,      -- ✨ Pre-tracked for fast Passive Income
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

	-- ✨ RESTORED: Admin Config Wipe Flags!
	if AdminConfig.WipeMoneyOnLoad then
		d.currency=0; d.totalEarned=0; d.pendingAuras=0; d.pendingPayout=0; d.pendingBonusPayout=0; d.lastPayout=0
		for k in pairs(d.upgrades) do d.upgrades[k] = 0 end
		d.totalCubesProduced=0; d.totalPlatformsShipped=0; d.totalLegendaryCubes=0
		d.piggyBank=0; d.piggyBankBroken=0; d.farmEvaluation=0; d.goldenAuras=AdminConfig.GoldenAuraStart or 10
		d.boostInventory={ AuraRush=0, SpawnBoost=0, SoulBoost=0 }
		d.hasPrestigedThisArea=false; d.claimedMail={}; d.tutorialProgress={}; d.tutorialComplete=false
	end

	if AdminConfig.WipePrestigeOnLoad then d.soulAuras=0; d.prestigeCount=0; d.hasPrestigedThisArea=false end
	if AdminConfig.WipeAreaOnLoad then d.currentArea=1; d.farmEvaluation=0; d.unlockedAreas={ 1 }; d.hasPrestigedThisArea=false end
	if AdminConfig.WipeEpicOnLoad then d.goldenAuras = AdminConfig.GoldenAuraStart or 0; d.epicUpgrades = {} end
	if AdminConfig.WipeAchievementsOnLoad then d.totalCubesProduced=0; d.totalLegendaryCubes=0; d.totalPlatformsShipped=0 end

	-- Ensure structures exist
	if not d.epicUpgrades     then d.epicUpgrades     = {} end
	if not d.tutorialProgress then d.tutorialProgress = {} end
	if d.tutorialComplete == nil then d.tutorialComplete = false end
	if not d.claimedMail      then d.claimedMail      = {} end
	if not d.unlockedMail     then d.unlockedMail     = {} end
	if d.hasPrestigedThisArea == nil then d.hasPrestigedThisArea = false end

	-- ✨ RESTORED: Initial HUD & Upgrade Synchronization
	task.wait(1)
	if not player or not player.Parent then return end

	local habCfg = UpgradeConfig.GetUpgradeConfig("habitatCapacity")
	local habCap  = (habCfg and habCfg.apply) and habCfg.apply(d) or AdminConfig.BaseHabitatCapacity
	local tickCfg = UpgradeConfig.GetUpgradeConfig("passiveTickSpeed")
	local passInt = (tickCfg and tickCfg.apply) and tickCfg.apply(d) or AdminConfig.PassiveInterval

	local upgradesState = {}
	for upgradeId, level in pairs(d.upgrades or {}) do upgradesState[upgradeId] = { level = level } end

	ReplicatedStorage.RemoteEvents.UpdateHUD:FireClient(player, {
		currency=d.currency, pendingAuras=0, habitatCapacity=habCap, rate=0, passiveInterval=passInt,
		totalEarned=d.totalEarned or 0, soulAuras=d.soulAuras or 0, farmEvaluation=d.farmEvaluation or 0,
		goldenAuras=d.goldenAuras or 0, boostInventory=d.boostInventory or {}, settings=d.settings or {},
		prestigeCount=d.prestigeCount or 0, hasPrestigedThisArea=d.hasPrestigedThisArea or false,
		tutorialProgress=d.tutorialProgress or {}, tutorialComplete=d.tutorialComplete or false,
		epicUpgrades=d.epicUpgrades or {}, totalCubesProduced=d.totalCubesProduced or 0,
		currentArea=d.currentArea or 1, upgrades=upgradesState,
	})

	task.delay(0.5, function()
		if not player or not player.Parent then return end
		local resetState = {}
		for tierNum, tierData in ipairs(UpgradeConfig.Tiers) do
			for upgradeId, cfg in pairs(tierData.upgrades) do
				local lv = d.upgrades[upgradeId] or 0
				local maxed = lv >= cfg.maxLevel
				resetState[upgradeId] = { level=lv, maxLevel=cfg.maxLevel, cost=maxed and 0 or UpgradeConfig.CalculateCost(upgradeId, lv), maxed=maxed }
			end
		end
		local UpgradeUpdated = ReplicatedStorage.RemoteEvents:FindFirstChild("UpgradeUpdated")
		if UpgradeUpdated then UpgradeUpdated:FireClient(player, { type="fullState", upgrades=resetState, currency=d.currency }) end
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
		if stepId == "__tutorialComplete__" then data.tutorialComplete = true
		elseif type(stepId) == "string" and #stepId < 100 then data.tutorialProgress[stepId] = true end
	end)
end)

local GameManager = {}

function GameManager.GetData(uid)    return PlayerData[uid]    end
function GameManager.GetRuntime(uid) return PlayerRuntime[uid] end
function GameManager.SavePlayer(p)   SaveData(p)               end

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
	end

	table.insert(runtime.cubeOrder, id)
	runtime.cubeCount += 1
	return id
end

function GameManager.MarkCubeStored(uid, cubeId)
	local runtime = PlayerRuntime[uid]
	if not runtime then return end
	local cube = runtime.cubes[cubeId]
	if cube and not cube.isStored then
		cube.isStored = true
		runtime.storedCubeCount += 1
		runtime.activeMutatedValue -= MutationConfig.GetMutatedValue(cube)
	end
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

	runtime.cubes[cubeId] = nil
	runtime.cubeCount -= 1
end

function GameManager.CollectOldestCubes(uid, count)
	local runtime = PlayerRuntime[uid]
	if not runtime then return {}, {} end
	local collected, collectedCubes, newOrder = {}, {}, {}
	local needed = count
	for _, cubeId in ipairs(runtime.cubeOrder) do
		if runtime.cubes[cubeId] then
			if needed > 0 then
				table.insert(collected, cubeId)
				table.insert(collectedCubes, runtime.cubes[cubeId])
				GameManager.RemoveCube(uid, cubeId) 
				needed -= 1
			else
				table.insert(newOrder, cubeId)
			end
		end
	end
	runtime.cubeOrder = newOrder
	return collected, collectedCubes
end

game:BindToClose(function()
	print("[GameManager] Server shutting down. Forcing final save for all players...")
	for _, player in ipairs(Players:GetPlayers()) do SaveData(player) end
	task.wait(2) 
end)

return GameManager

-- MailManager
-- Location: ServerScriptService > MailManager

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MailConfig  = require(ReplicatedStorage.Modules.MailConfig)
local GameManager = require(ServerScriptService.GameManager)

local ClaimMail   = ReplicatedStorage.RemoteEvents:WaitForChild("ClaimMail")
local MailUpdated = ReplicatedStorage.RemoteEvents:WaitForChild("MailUpdated")
local UpdateHUD   = ReplicatedStorage.RemoteEvents:WaitForChild("UpdateHUD")
local ShipAuras   = ReplicatedStorage.RemoteEvents:WaitForChild("ShipAuras")

local function IsMailAvailable(entry, data)
	if not data then return false end
	if not data.claimedMail then data.claimedMail = {} end
	if data.claimedMail[entry.id] then return false end
	if entry.area and (data.currentArea or 1) ~= entry.area then
		if entry.trigger == "areaEnter" then
			local visited = false
			if type(data.unlockedAreas) == "table" then
				for _, v in ipairs(data.unlockedAreas) do
					if v == entry.area then visited = true; break end
				end
			end
			if not visited then return false end
		else
			return false
		end
	end
	local trigger = entry.trigger
	local tv      = entry.triggerValue
	if trigger == "always" then return true
	elseif trigger == "areaEnter" then
		if entry.area then
			if type(data.unlockedAreas) == "table" then
				for _, v in ipairs(data.unlockedAreas) do
					if v == entry.area then return true end
				end
			end
			return (data.currentArea or 1) >= entry.area
		end
		return true
	elseif trigger == "firstPrestige" then return (data.prestigeCount or 0) >= 1
	elseif trigger == "prestigeCount" then return (data.prestigeCount or 0) >= (tv or 1)
	elseif trigger == "currencyReached" then return (data.currency or 0) >= (tv or 0)
	elseif trigger == "farmEvalReached" then return (data.farmEvaluation or 0) >= (tv or 0)
	elseif trigger == "soulAurasReached" then return (data.soulAuras or 0) >= (tv or 0)
	elseif trigger == "goldenAurasReached" then return (data.goldenAuras or 0) >= (tv or 0)
	elseif trigger == "giftCollected" then return data.claimedMail["__giftFlag__"] == true
	elseif trigger == "manual" then
		return data.unlockedMail and data.unlockedMail[entry.id] == true
	end
	return false
end

local function GetAvailableMail(data)
	if not data then return {}, {} end
	if not data.claimedMail then data.claimedMail = {} end
	local available, claimed = {}, {}
	for _, entry in ipairs(MailConfig.Entries) do
		if data.claimedMail[entry.id] then
			table.insert(claimed, entry.id)
		elseif IsMailAvailable(entry, data) then
			table.insert(available, {
				id = entry.id, title = entry.title, body = entry.body,
				icon = entry.icon or "", sender = entry.sender or MailConfig.DefaultSender,
				rewards = entry.rewards or {},
				color = entry.color,
			})
		end
	end
	return available, claimed
end

local function SendMailState(player)
	local data = GameManager.GetData(player.UserId)
	if not data then return end
	local available, claimed = GetAvailableMail(data)
	MailUpdated:FireClient(player, {
		available   = available,
		claimed     = claimed,
		unreadCount = #available,
	})
end

ClaimMail.OnServerEvent:Connect(function(player, mailId)
	local uid  = player.UserId
	local data = GameManager.GetData(uid)
	if not data then return end
	if not data.claimedMail then data.claimedMail = {} end
	if data.claimedMail[mailId] then return end
	local entry = MailConfig.GetEntry(mailId)
	if not entry then return end
	if not IsMailAvailable(entry, data) then return end
	data.claimedMail[mailId] = true
	local rewards = entry.rewards or {}

	if rewards.goldenAuras and rewards.goldenAuras > 0 then
		data.goldenAuras = (data.goldenAuras or 0) + rewards.goldenAuras
		ShipAuras:FireClient(player, {action = "playJuice", amount = rewards.goldenAuras, currencyType = "Auras"})
	end
	if rewards.currency and rewards.currency > 0 then
		data.currency = (data.currency or 0) + rewards.currency
		ShipAuras:FireClient(player, {action = "playJuice", amount = rewards.currency, currencyType = "Currency"})
	end

	if rewards.boosts and type(rewards.boosts) == "table" then
		if not data.boostInventory then data.boostInventory = {} end
		for boostId, count in pairs(rewards.boosts) do
			data.boostInventory[boostId] = (data.boostInventory[boostId] or 0) + count
		end
	end

	UpdateHUD:FireClient(player, {
		goldenAuras    = data.goldenAuras,
		currency       = data.currency,
		boostInventory = data.boostInventory,
	})
	SendMailState(player)
	GameManager.SavePlayer(player)
end)

-- Periodic check every 5 seconds
task.spawn(function()
	while true do
		task.wait(5)
		for _, player in ipairs(Players:GetPlayers()) do SendMailState(player) end
	end
end)

Players.PlayerAdded:Connect(function(player)
	task.wait(4)
	SendMailState(player)
	task.wait(3)
	if player and player.Parent then SendMailState(player) end
end)

task.delay(6, function()
	for _, player in ipairs(Players:GetPlayers()) do SendMailState(player) end
end)

local MailManager = {}
function MailManager.UnlockMail(player, mailId)
	local data = GameManager.GetData(player.UserId)
	if not data then return end
	if not data.unlockedMail then data.unlockedMail = {} end
	data.unlockedMail[mailId] = true
	SendMailState(player)
end
function MailManager.FlagGiftCollected(player)
	local data = GameManager.GetData(player.UserId)
	if not data then return end
	if not data.claimedMail then data.claimedMail = {} end
	data.claimedMail["__giftFlag__"] = true
end
return MailManager

-- PrestigeHandler
-- Location: ServerScriptService > PrestigeHandler
--
-- ONE PRESTIGE PER AREA — blocks if hasPrestigedThisArea is true.
-- AreaManager resets the flag on any area travel.

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AdminConfig    = require(ReplicatedStorage.Modules.AdminConfig)
local UpgradeConfig  = require(ReplicatedStorage.Modules.UpgradeConfig)
local PrestigeModule = require(ReplicatedStorage.Modules.PrestigeModule)
local GameManager    = require(ServerScriptService.GameManager)
local BoostManager   = require(ServerScriptService.BoostManager)

local RequestPrestige  = ReplicatedStorage.RemoteEvents:WaitForChild("RequestPrestige")
local PrestigeComplete = ReplicatedStorage.RemoteEvents:WaitForChild("PrestigeComplete")
local UpdateHUD        = ReplicatedStorage.RemoteEvents:WaitForChild("UpdateHUD")
local UpgradeUpdated   = ReplicatedStorage.RemoteEvents:WaitForChild("UpgradeUpdated")
local UpdateHatchery   = ReplicatedStorage.RemoteEvents:WaitForChild("UpdateHatchery")

local PrestigeReset = Instance.new("BindableEvent")
PrestigeReset.Name   = "PrestigeReset"
PrestigeReset.Parent = ServerScriptService

local lastPrestige      = {}
local PRESTIGE_COOLDOWN = 2

RequestPrestige.OnServerEvent:Connect(function(player)
	local uid = player.UserId
	local now = tick()

	if lastPrestige[uid] and now - lastPrestige[uid] < PRESTIGE_COOLDOWN then return end
	lastPrestige[uid] = now

	local data    = GameManager.GetData(uid)
	local runtime = GameManager.GetRuntime(uid)
	if not data then warn("[PrestigeHandler] No data for player:", uid); return end

	-- ONE PRESTIGE PER AREA
	if data.hasPrestigedThisArea then
		PrestigeComplete:FireClient(player, {
			blocked              = true,
			reason               = "Already prestiged in this area. Travel to a new area to prestige again!",
			hasPrestigedThisArea = true,
		})
		return
	end

	local earned       = data.totalEarned or 0
	local rawSoulAuras = PrestigeModule.CalcSoulAuras(earned)
	if rawSoulAuras <= 0 then return end

	local soulMult     = BoostManager.GetSoulMultiplier(uid)
	local newSoulAuras = math.floor(rawSoulAuras * soulMult)

	local previousSoulAuras  = data.soulAuras or 0
	local previousMultiplier = PrestigeModule.GetMultiplier(previousSoulAuras)

	local bonusPercent  = AdminConfig.PrestigeStartBonusPercent or 0.05
	local prestigeBonus = math.max(math.floor(earned * bonusPercent), 50)

	data.soulAuras              = previousSoulAuras + newSoulAuras
	data.prestigeCount          = (data.prestigeCount or 0) + 1
	data.hasPrestigedThisArea   = true
	local newMultiplier = PrestigeModule.GetMultiplier(data.soulAuras)

	data.currency           = prestigeBonus
	data.totalEarned        = 0
	data.pendingAuras       = 0
	data.pendingPayout      = 0
	data.pendingBonusPayout = 0
	data.lastPayout         = 0

	for key, _ in pairs(data.upgrades) do data.upgrades[key] = 0 end

	if runtime then
		runtime.cubes          = {}
		runtime.cubeOrder      = {}
		runtime.cubeCount      = 0
		runtime.nextCubeId     = 1
		runtime.lastActiveTime = tick()
		runtime.sessionStart   = tick()
	end

	PrestigeReset:Fire(player)

	PrestigeComplete:FireClient(player, {
		newSoulAuras         = newSoulAuras,
		totalSoulAuras       = data.soulAuras,
		previousMultiplier   = previousMultiplier,
		newMultiplier        = newMultiplier,
		prestigeCount        = data.prestigeCount,
		prestigeBonus        = prestigeBonus,
		soulBoostActive      = soulMult > 1,
		hasPrestigedThisArea = true,
	})

	local resetState = {}
	for _, tierData in ipairs(UpgradeConfig.Tiers) do
		for upgradeId, cfg in pairs(tierData.upgrades) do
			resetState[upgradeId] = {
				level    = 0,
				maxLevel = cfg.maxLevel,
				cost     = UpgradeConfig.CalculateCost(upgradeId, 0),
				maxed    = false,
			}
		end
	end
	UpgradeUpdated:FireClient(player, {
		type     = "fullState",
		upgrades = resetState,
		currency = prestigeBonus,
	})

	UpdateHatchery:FireClient(player, {
		current = AdminConfig.HatcheryMax,
		max     = AdminConfig.HatcheryMax,
	})

	task.wait(0.3)
	UpdateHUD:FireClient(player, {
		currency             = data.currency,
		pendingAuras         = 0,
		habitatCapacity      = AdminConfig.BaseHabitatCapacity,
		rate                 = 0,
		passiveInterval      = AdminConfig.PassiveInterval,
		totalEarned          = 0,
		soulAuras            = data.soulAuras      or 0,
		farmEvaluation       = data.farmEvaluation or 0,
		goldenAuras          = data.goldenAuras    or 0,
		boostInventory       = data.boostInventory or {},
		prestigeCount        = data.prestigeCount  or 0,
		hasPrestigedThisArea = true,
	})

	GameManager.SavePlayer(player)
end)

---------------------------------------------------------------
-- Preview
---------------------------------------------------------------
local PreviewPrestige = ReplicatedStorage.RemoteEvents:WaitForChild("PreviewPrestige")

PreviewPrestige.OnServerEvent:Connect(function(player)
	local data = GameManager.GetData(player.UserId)
	if not data then return end

	local earned       = data.totalEarned or 0
	local rawSoulAuras = PrestigeModule.CalcSoulAuras(earned)
	local currentSA    = data.soulAuras or 0
	local currentMult  = PrestigeModule.GetMultiplier(currentSA)
	local soulMult     = BoostManager.GetSoulMultiplier(player.UserId)
	local newSoulAuras = math.floor(rawSoulAuras * soulMult)
	local newMult      = PrestigeModule.GetMultiplier(currentSA + newSoulAuras)
	local bonusPercent  = AdminConfig.PrestigeStartBonusPercent or 0.05
	local prestigeBonus = math.max(math.floor(earned * bonusPercent), 50)

	PreviewPrestige:FireClient(player, {
		totalEarned          = earned,
		newSoulAuras         = newSoulAuras,
		currentSoulAuras     = currentSA,
		currentMultiplier    = currentMult,
		newMultiplier        = newMult,
		prestigeCount        = data.prestigeCount or 0,
		prestigeBonus        = prestigeBonus,
		soulBoostActive      = soulMult > 1,
		hasPrestigedThisArea = data.hasPrestigedThisArea == true,
	})
end)

-- ShippingManager
-- Location: ServerScriptService > ShippingManager

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

local ShipAuras = ReplicatedStorage.RemoteEvents:WaitForChild("ShipAuras")
local UpdateHUD = ReplicatedStorage.RemoteEvents:WaitForChild("UpdateHUD")

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
		pendingAuras    = storedCount,
		habitatCapacity = habitatCap,
		rate            = rate,
		passiveInterval = passiveInt,
		totalEarned     = data.totalEarned    or 0,
		soulAuras       = data.soulAuras      or 0,
		farmEvaluation  = data.farmEvaluation or 0,
		shipCooldown    = finalCooldown,
		discoveredTiers = data.discoveredTiers or {} 
	})
end

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

	data.discoveredTiers = data.discoveredTiers or {}
	local newlyDiscovered = {}

	for _, cube in ipairs(cubes) do
		totalPayout = totalPayout + MutationConfig.GetMutatedValue(cube)

		local cArea = cube.currentArea or data.currentArea or 1
		local discoverKey = cArea .. "_" .. cube.tierName

		if not data.discoveredTiers[discoverKey] then
			data.discoveredTiers[discoverKey] = true
			table.insert(newlyDiscovered, {name = cube.tierName, color = cube.color, area = cArea})
		end
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

	if #newlyDiscovered > 0 then
		AuraDiscovered:FireClient(player, newlyDiscovered)
	end
end

ShipAuras.OnServerEvent:Connect(function(player, action, value)
	local uid = player.UserId

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

		data.currency       = (data.currency       or 0) + actualPayout
		data.totalEarned    = (data.totalEarned     or 0) + actualPayout
		data.farmEvaluation = (data.farmEvaluation  or 0) + actualPayout

		SendHUDUpdate(player)

		ShipAuras:FireClient(player, {
			action = "payoutConfirmed",
			amount = actualPayout
		})
	end
end)

-- UpgradeManager
-- Location: ServerScriptService > UpgradeManager

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AdminConfig   = require(ReplicatedStorage.Modules.AdminConfig)
local UpgradeConfig = require(ReplicatedStorage.Modules.UpgradeConfig)
local MutationConfig = require(ReplicatedStorage.Modules.MutationConfig)
local GameManager   = require(ServerScriptService.GameManager)
local BoostManager  = require(ServerScriptService.BoostManager)

local PurchaseUpgrade = ReplicatedStorage.RemoteEvents:WaitForChild("PurchaseUpgrade")
local UpgradeUpdated  = ReplicatedStorage.RemoteEvents:WaitForChild("UpgradeUpdated")
local UpdateHUD       = ReplicatedStorage.RemoteEvents:WaitForChild("UpdateHUD")

local lastPurchase = {}
local PURCHASE_COOLDOWN = 0.05

local function GetHabitatCapacity(data)
	local cfg = UpgradeConfig.GetUpgradeConfig("habitatCapacity")
	if cfg and cfg.apply then return cfg.apply(data) end
	return AdminConfig.BaseHabitatCapacity or 50
end

local function GetPassiveInterval(data)
	local cfg = UpgradeConfig.GetUpgradeConfig("passiveTickSpeed")
	if cfg and cfg.apply then return cfg.apply(data) end
	return AdminConfig.PassiveInterval or 10
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
				cost     = currentLevel < cfg.maxLevel and UpgradeConfig.CalculateCost(upgradeId, currentLevel) or 0,
				maxed    = currentLevel >= cfg.maxLevel,
			}
		end
	end

	UpgradeUpdated:FireClient(player, {
		type     = "fullState",
		upgrades = state,
		currency = data.currency,
	})
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

	UpdateHUD:FireClient(player, {
		currency        = data.currency,
		pendingAuras    = storedCount,
		habitatCapacity = GetHabitatCapacity(data),
		rate            = rate,
		passiveInterval = GetPassiveInterval(data),
		totalEarned     = data.totalEarned    or 0,
		soulAuras       = data.soulAuras      or 0,
		farmEvaluation  = data.farmEvaluation or 0,
		upgrades        = upgradesState, 
	})
end

PurchaseUpgrade.OnServerEvent:Connect(function(player, upgradeId)
	local uid = player.UserId
	local now = tick()

	if type(upgradeId) ~= "string" then return end
	if lastPurchase[uid] and now - lastPurchase[uid] < PURCHASE_COOLDOWN then return end
	lastPurchase[uid] = now

	local cfg = UpgradeConfig.GetUpgradeConfig(upgradeId)
	if not cfg then return end

	local data = GameManager.GetData(uid)
	if not data then return end
	if not data.upgrades then data.upgrades = {} end

	local currentLevel = data.upgrades[upgradeId] or 0
	if currentLevel >= cfg.maxLevel then return end

	local cost = UpgradeConfig.CalculateCost(upgradeId, currentLevel)
	if data.currency < cost then return end

	data.currency            = data.currency - cost
	data.upgrades[upgradeId] = currentLevel + 1
	local newLevel           = currentLevel + 1

	local nextCost = 0
	if newLevel < cfg.maxLevel then
		nextCost = UpgradeConfig.CalculateCost(upgradeId, newLevel)
	end

	UpgradeUpdated:FireClient(player, {
		type      = "purchased",
		upgradeId = upgradeId,
		level     = newLevel,
		maxLevel  = cfg.maxLevel,
		cost      = nextCost,
		maxed     = newLevel >= cfg.maxLevel,
		currency  = data.currency,
	})

	SendHUDAfterPurchase(player, data)
end)

Players.PlayerRemoving:Connect(function(player)
	lastPurchase[player.UserId] = nil
end)
