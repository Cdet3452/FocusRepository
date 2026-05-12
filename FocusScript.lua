-- AuraPhysicsManager
-- Location: ServerScriptService > AuraPhysicsManager

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")

local AdminConfig = require(ReplicatedStorage.Modules:WaitForChild("AdminConfig"))
local GameManager = require(ServerScriptService:WaitForChild("GameManager"))

-- ✨ BRIDGENET2 UPGRADE
local BridgeNet2      = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))
local UpdateHUDBridge = BridgeNet2.ServerBridge("UpdateHUD")

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
		Debris:AddItem(spawnEffect, 3) 
	end

	-- 9. CLICK & REWARDS 
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

				local despawnTime = isElite and AdminConfig.PhysicsEliteDespawn or AdminConfig.PhysicsRegularDespawn
				if type(despawnTime) ~= "number" then 
					despawnTime = 15 
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
			local r = isElite and 5 or 1 
			data.goldenAuras += r

			-- ✨ BRIDGENET2 FIX
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

-- =======================================================
-- 💥 TUTORIAL BURST LISTENER
-- =======================================================
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
			amount = 15 
		end

		task.spawn(function()
			for i = 1, amount do
				CreatePhysicsAura(false) 
				task.wait(0.15) 
			end
		end)
	end)
end

-- AuraHologramBridge (LocalScript)
-- Location: StarterPlayer > StarterPlayerScripts > AuraHologramBridge

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Hologram = require(ReplicatedStorage.Modules:WaitForChild("HologramModule"))

local function ApplyHologram(prompt)
	-- Determine color based on rarity attribute
	local isElite = prompt:GetAttribute("IsElite")
	local holoColor = isElite and Color3.fromRGB(255, 50, 255) or Color3.fromRGB(50, 255, 255)

	-- Create the cool hologram beam
	local auraHolo = Hologram.New(prompt, Vector3.new(0, 3, 0), false, true)
	auraHolo:SetBillboardActive(true)
	auraHolo:SetAlwaysOnTop(true)
	auraHolo:SetPrimaryColour(holoColor)
	auraHolo:SetTertiaryColour(Color3.fromRGB(255, 255, 255))

	-- ✨ LOCAL JUICE TRIGGER & ANTI-SPAM LOCK ✨
	prompt.Triggered:Connect(function(player)
		-- Instantly lock the prompt locally so it can't be spammed
		if prompt:GetAttribute("ClaimedLocally") then return end
		prompt:SetAttribute("ClaimedLocally", true)
		prompt.Enabled = false

		if player == Players.LocalPlayer then
			local amount = isElite and 5 or 1
			local LocalJuiceEvent = ReplicatedStorage:FindFirstChild("LocalJuiceEvent")
			if LocalJuiceEvent then
				LocalJuiceEvent:Fire(amount, "Auras")
			end
		end
	end)
end

-- 1. Catch new auras that spawn while playing
CollectionService:GetInstanceAddedSignal("AuraHologram"):Connect(ApplyHologram)

-- 2. Catch any auras that were already on the ground when you joined
for _, prompt in ipairs(CollectionService:GetTagged("AuraHologram")) do
	ApplyHologram(prompt)
end
