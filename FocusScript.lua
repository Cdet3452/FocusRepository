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
	CollectionService:AddTag(mainPart, "PhysicsAura") -- ✨ NEW: Tag for camera tracking!

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

				-- ✨ NEW: Massive Lifetime Buffs
				local despawnTime = isElite and AdminConfig.PhysicsEliteDespawn or AdminConfig.PhysicsRegularDespawn
				if type(despawnTime) ~= "number" then 
					despawnTime = isElite and 45 or 90 -- Makes them last a really long time if not configured!
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
-- 💥 TUTORIAL BURST LISTENER & PASSIVE SPAWNS
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
		-- The massive burst on Prestige #1 to guarantee they can complete Step 23
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
end

-- Start spawning (Passive loop)
task.spawn(function()
	-- Give GameManager time to load
	task.wait(5)
	local GameManager = require(game:GetService("ServerScriptService"):WaitForChild("GameManager"))

	while true do
		-- Revert to normal, slower spawn rates (e.g. every 20-45 seconds depending on your AdminConfig)
		task.wait(math.random(AdminConfig.PhysicsSpawnMin or 20, AdminConfig.PhysicsSpawnMax or 45)) 

		-- ✨ THE FIX: Only allow passive spawns if a player is in Area 2 OR has Prestiged!
		local allowPassiveSpawns = false
		for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
			local data = GameManager.GetData(player.UserId)
			if data and ((data.prestigeCount or 0) > 0 or (data.currentArea or 1) >= 2) then
				allowPassiveSpawns = true
				break
			end
		end

		if allowPassiveSpawns then
			CreatePhysicsAura(math.random(1, 100) <= (AdminConfig.PhysicsEliteChance or 10))
		end
	end
end)

-- BankController
-- Location: StarterPlayer > StarterPlayerScripts > BankController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")

local BankConfig = require(ReplicatedStorage.Modules:WaitForChild("BankConfig"))
local BridgeNet2 = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))
local NumberFormatter = require(ReplicatedStorage.Modules:WaitForChild("NumberFormatter"))
local UITheme = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UITheme"))
local T = UITheme.Get("Custom")

local BankActionBridge = BridgeNet2.ClientBridge("BankAction")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainHUD = playerGui:WaitForChild("MainHUD")

local gaurasLabel = mainHUD:FindFirstChild("GoldenAurasLabel", true) or mainHUD:FindFirstChild("GAuras", true) or mainHUD
local currLabel = mainHUD:FindFirstChild("CurrencyLabel", true) or mainHUD:FindFirstChild("Cash", true) or mainHUD

local inSpecialArea = false
local promptGui = nil
local fillProgress = 0
local isHolding = false
local holdSound = nil
local tiltSide = 1 -- Used for the shaking animation

-- =========================================================================
-- AUTOMATED CONVEYOR AI
-- =========================================================================
local function SetupConveyors()
	local trigger = workspace:FindFirstChild("StorageTrigger", true) or workspace:FindFirstChild("GoldenTrigger", true)
	if not trigger then return end

	local targetPos = trigger.Position

	-- Find every conveyor path and programmatically set its velocity to point towards the center hole
	for _, child in ipairs(workspace:GetDescendants()) do
		if string.find(child.Name, "Conveyer") and child:IsA("BasePart") then
			local direction = (targetPos - child.Position).Unit
			direction = Vector3.new(direction.X, 0, direction.Z).Unit 
			child.AssemblyLinearVelocity = direction * 25 
		end
	end


end

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

-- =========================================================================
-- JUICY UI EFFECTS
-- =========================================================================
local function PlayJuiceEffect(exactAmount, currencyType)
	local isAura = (currencyType == "Auras")
	local targetLabel = isAura and gaurasLabel or currLabel

	local pendingKey = isAura and "LocalPendingAuras" or "LocalPendingPayout"
	local addKey = isAura and "VisualAurasToAdd" or "VisualCashToAdd"

	local currentPending = player:GetAttribute(pendingKey) or 0
	player:SetAttribute(pendingKey, currentPending + exactAmount)

	local targetPos = targetLabel.AbsolutePosition
	local targetSize = targetLabel.AbsoluteSize

	local popupWidth = 250
	local popupHeight = 70
	local startX = targetPos.X - popupWidth - 40 
	local startY = targetPos.Y + (targetSize.Y / 2) - (popupHeight / 2) 

	local endPos2D = targetPos + (targetSize / 2)

	local effectGui = Instance.new("ScreenGui")
	effectGui.Name = "JuiceGui_" .. currencyType
	effectGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	effectGui.Parent = playerGui

	local popupText = Instance.new("TextLabel")
	popupText.Text = (isAura and "+" or "+$") .. NumberFormatter.Format(exactAmount)
	popupText.Font = Enum.Font.FredokaOne
	popupText.TextScaled = true
	popupText.TextColor3 = isAura and Color3.fromRGB(255, 215, 0) or Color3.fromRGB(85, 255, 127)
	popupText.BackgroundTransparency = 1
	popupText.TextXAlignment = Enum.TextXAlignment.Right 
	popupText.Size = UDim2.new(0, popupWidth, 0, popupHeight)
	popupText.Position = UDim2.new(0, startX, 0, startY)
	popupText.ZIndex = 100
	popupText.Parent = effectGui

	local textStroke = Instance.new("UIStroke", popupText)
	textStroke.Color = isAura and Color3.fromRGB(80, 50, 0) or Color3.fromRGB(0, 50, 0)
	textStroke.Thickness = 3

	local textScale = Instance.new("UIScale", popupText)
	textScale.Scale = 0

	TweenService:Create(textScale, TweenInfo.new(0.4, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), {Scale = 1.2}):Play()

	task.delay(0.6, function()
		TweenService:Create(popupText, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			Position = UDim2.new(0, startX - 120, 0, startY),
			TextTransparency = 1
		}):Play()
		TweenService:Create(textStroke, TweenInfo.new(0.8), {Transparency = 1}):Play()
	end)

	local sfxFolder = ReplicatedStorage:FindFirstChild("SFX") or ReplicatedStorage:FindFirstChild("Sounds")
	if sfxFolder and sfxFolder:FindFirstChild("CashRegister") then
		local sfx = sfxFolder.CashRegister:Clone()
		if isAura then sfx.Pitch = 1.3 end 
		sfx.Parent = game:GetService("SoundService")
		sfx:Play()
		Debris:AddItem(sfx, 2)
	end

	local iconCount = 10
	local iconSize = 40
	local iconId = "rbxassetid://14916846070" 

	if isAura then
		iconId = "rbxassetid://4483362458" 
		if exactAmount < 100 then
			iconCount = math.min(exactAmount, 30)
			iconSize = 35 
		elseif exactAmount < 1000 then
			iconCount = math.min(math.ceil(exactAmount / 10), 30)
			iconSize = 55 
		else
			iconCount = math.min(math.ceil(exactAmount / 100), 30)
			iconSize = 80 
		end
	end

	local chunkAmount = exactAmount / iconCount
	local coinsHit = 0

	for i = 1, iconCount do
		local coin = Instance.new("ImageLabel")
		coin.Image = iconId
		if isAura then coin.ImageColor3 = Color3.fromRGB(255, 215, 0) end 
		coin.BackgroundTransparency = 1
		coin.Size = UDim2.new(0, iconSize, 0, iconSize)

		local coinStartX = startX + popupWidth - (iconSize * 1.5)
		local coinStartY = startY + (popupHeight / 2) - (iconSize / 2)

		coin.Position = UDim2.new(0, coinStartX, 0, coinStartY)
		coin.ZIndex = 90
		coin.Parent = effectGui

		local randomOffsetX = math.random(-80, 80)
		local randomOffsetY = math.random(-80, 80)
		local burstPos = UDim2.new(0, coinStartX + randomOffsetX, 0, coinStartY + randomOffsetY)

		local burstTween = TweenService:Create(coin, TweenInfo.new(0.3, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), {
			Position = burstPos,
			Rotation = math.random(-180, 180)
		})
		burstTween:Play()

		burstTween.Completed:Connect(function()
			local flyTween = TweenService:Create(coin, TweenInfo.new(0.4 + (i * 0.02), Enum.EasingStyle.Back, Enum.EasingDirection.In), {
				Position = UDim2.new(0, endPos2D.X - (iconSize/2), 0, endPos2D.Y - (iconSize/2)),
				Size = UDim2.new(0, iconSize/2, 0, iconSize/2),
				ImageTransparency = 0.3
			})
			flyTween:Play()

			flyTween.Completed:Connect(function()
				if coin.Parent then coin:Destroy() end
				coinsHit += 1

				player:SetAttribute(addKey, chunkAmount)

				local pending = player:GetAttribute(pendingKey) or 0
				player:SetAttribute(pendingKey, math.max(0, pending - chunkAmount))

				if sfxFolder and sfxFolder:FindFirstChild("CoinTick") then
					local sfx = sfxFolder.CoinTick:Clone()
					sfx.Pitch = (isAura and 1.8 or 1.5) + (math.random()*0.2)
					sfx.Parent = game:GetService("SoundService")
					sfx:Play()
					Debris:AddItem(sfx, 1)
				end

				local ts = targetLabel:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", targetLabel)
				ts.Scale = 1.1
				TweenService:Create(ts, TweenInfo.new(0.1, Enum.EasingStyle.Sine), {Scale = 1}):Play()
			end)
		end)
	end

	task.delay(3, function()
		if effectGui.Parent then effectGui:Destroy() end
		if coinsHit < iconCount then
			local remaining = (iconCount - coinsHit) * chunkAmount
			player:SetAttribute(addKey, remaining)
			player:SetAttribute(pendingKey, 0)
		end
	end)


end

-- =========================================================================
-- PHYSICAL CUBE SPAWNER
-- =========================================================================
local function SpawnExplosionCubes(totalAmount)
	local MAX_PHYSICS_CUBES = 100

	local EXPLOSION_FORCE_OUT_MIN = 40

	local EXPLOSION_FORCE_OUT_MAX = 90

	local EXPLOSION_FORCE_UP_MIN = 70

	local EXPLOSION_FORCE_UP_MAX = 120

	local BOUNCE_LIMIT = 1

	-- ✨ THE FIX: Spawns exactly `totalAmount` of cubes, capping at 100 to prevent lag.
	-- If totalAmount = 110, baseValue = 1. remainder = 10. Cube 1 is worth 11, Cubes 2-100 are worth 1.
	local numCubes = math.max(1, math.min(totalAmount, MAX_PHYSICS_CUBES))
	local baseValue = math.floor(totalAmount / numCubes)
	local remainder = totalAmount - (baseValue * numCubes)

	local trigger = workspace:FindFirstChild("StorageTrigger", true) or workspace:FindFirstChild("GoldenTrigger", true)
	local centralAura = workspace:FindFirstChild("DynamicPiggyBankAura")
	local spawnPos = centralAura and (centralAura:IsA("Model") and centralAura:GetPivot().Position or centralAura.Position) or Vector3.new(0, 15, 0)

	local vfxFolder = ReplicatedStorage:FindFirstChild("VFX")
	local sfxFolder = ReplicatedStorage:FindFirstChild("SFX") or ReplicatedStorage:FindFirstChild("Sounds")

	local areaAssets = ReplicatedStorage:FindFirstChild("AreaAssets")
	local piggyBankFolder = areaAssets and areaAssets:FindFirstChild("PiggyBank")
	local piggyAurasFolder = piggyBankFolder and piggyBankFolder:FindFirstChild("Auras")

	-- 1. Mass Spawn VFX
	if vfxFolder and vfxFolder:FindFirstChild("AuraSpawnVFX") then
		local spawnEffect = vfxFolder.AuraSpawnVFX:Clone()
		spawnEffect.Position = spawnPos
		spawnEffect.Parent = workspace
		for _, emitter in ipairs(spawnEffect:GetDescendants()) do
			if emitter:IsA("ParticleEmitter") then
				emitter:Emit(emitter:GetAttribute("EmitCount") or 35) 
			end
		end
		Debris:AddItem(spawnEffect, 3) 
	end

	local function GetAuraDataFromValue(val)
		local templateName = "GoldenAuraSmall"
		local scale = 1.0

		if val < 10 then
			templateName = "GoldenAuraSmall"
			scale = 1.0
		elseif val < 100 then
			templateName = "GoldenAuraSmall"
			scale = 1.35
		elseif val < 1000 then
			templateName = "GoldenAuraMedium"
			scale = 1.85
		elseif val < 10000 then
			templateName = "GoldenAuraLarge"
			scale = 2.5
		else
			templateName = "GoldenAuraLarge"
			scale = 3.5
		end

		local template = piggyAurasFolder and piggyAurasFolder:FindFirstChild(templateName)
		return template, scale
	end

	for i = 1, numCubes do
		local cubeValue = baseValue
		if i == 1 then cubeValue += remainder end

		local template, scaleMult = GetAuraDataFromValue(cubeValue)
		local cube

		if template then
			cube = template:Clone()
			if cube:IsA("BasePart") then cube.Color = Color3.fromRGB(255, 215, 0) end
			for _, desc in ipairs(cube:GetDescendants()) do
				if desc:IsA("BasePart") then desc.Color = Color3.fromRGB(255, 215, 0) end
			end
		else
			cube = Instance.new("Part")
			cube.Shape = Enum.PartType.Ball
			cube.Size = Vector3.new(2.5, 2.5, 2.5) 
			cube.Color = Color3.fromRGB(255, 215, 0)
			cube.Material = Enum.Material.Neon
		end

		-- ✨ THE FIX: Safely falls back to BasePart if the model doesn't have a PrimaryPart assigned!
		local mainPart = cube:IsA("Model") and (cube.PrimaryPart or cube:FindFirstChildWhichIsA("BasePart")) or cube
		if not mainPart then continue end

		local prompt = cube:FindFirstChildOfClass("ProximityPrompt") or cube:FindFirstChildWhichIsA("ProximityPrompt", true)
		if prompt then prompt:Destroy() end

		if cube:IsA("Model") then
			cube:ScaleTo(scaleMult)
		elseif cube:IsA("BasePart") then
			cube.Size = Vector3.new(2.5, 2.5, 2.5) * scaleMult
		end

		mainPart.CanCollide = true
		mainPart.CustomPhysicalProperties = PhysicalProperties.new(0.2, 0.1, 0.5, 1, 1) 
		if cube:IsA("Model") then cube:PivotTo(CFrame.new(spawnPos)) else cube.Position = spawnPos end
		cube.Parent = workspace

		local angle = (math.pi * 2 / numCubes) * i
		local outForce = math.random(EXPLOSION_FORCE_OUT_MIN, EXPLOSION_FORCE_OUT_MAX)
		local upForce = math.random(EXPLOSION_FORCE_UP_MIN, EXPLOSION_FORCE_UP_MAX)
		mainPart:ApplyImpulse(Vector3.new(math.cos(angle)*outForce, upForce, math.sin(angle)*outForce) * mainPart.AssemblyMass)

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

		local claimed = false
		local bounceCount = 0
		local lastBounce = 0
		local connection

		connection = mainPart.Touched:Connect(function(hit)
			if hit == trigger then
				if claimed then return end
				claimed = true
				if connection then connection:Disconnect() end

				mainPart.Anchored = true
				mainPart.CanCollide = false
				FadeOutAndDestroy(cube, 0.2)

				BankActionBridge:Fire({ action = "claimBankCube", amount = cubeValue })
				PlayJuiceEffect(cubeValue, "Auras")

				if sfxFolder and (sfxFolder:FindFirstChild("BuyPing") or sfxFolder:FindFirstChild("ClassicBass")) then
					local sfx = (sfxFolder:FindFirstChild("BuyPing") or sfxFolder:FindFirstChild("ClassicBass")):Clone()
					sfx.Parent = workspace
					local pitchAdjust = math.clamp(1.0 - (scaleMult * 0.1), 0.5, 1.0)
					sfx.Volume = 0.6
					sfx.PlaybackSpeed = pitchAdjust + (math.random(-15, 15)/100)
					sfx:Play()
					Debris:AddItem(sfx, 2)
				end
				return
			end

			if hit.Position.Y <= mainPart.Position.Y and (tick() - lastBounce > 0.15) then
				bounceCount += 1
				lastBounce = tick()

				if sfxFolder and sfxFolder:FindFirstChild("Landing") then
					local sfx = sfxFolder.Landing:Clone()
					sfx.Parent = mainPart
					sfx:Play()
					Debris:AddItem(sfx, 2)
				end
			end
		end)

		task.delay(15, function()
			if not claimed and cube.Parent then 
				claimed = true
				if connection then connection:Disconnect() end
				FadeOutAndDestroy(cube, 0.5)
				BankActionBridge:Fire({ action = "claimBankCube", amount = cubeValue })
				PlayJuiceEffect(cubeValue, "Auras")
			end
		end)

		task.wait(0.01)
	end


end

-- =========================================================================
-- VISUAL BREAK SEQUENCE
-- =========================================================================
local function TriggerBreakVFX(bankAmount)
	if promptGui then
		local panel = promptGui:FindFirstChild("PromptPanel")
		if panel then
			TweenService:Create(panel, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In), {Position = UDim2.new(1, -140, 1.2, 0)}):Play()
			task.delay(0.3, function() if promptGui then promptGui:Destroy(); promptGui = nil end end)
		end
	end

	local centralAura = workspace:FindFirstChild("DynamicPiggyBankAura")
	if centralAura then
		-- ✨ THE FIX: Dynamically scales the actual Map Model before exploding
		if centralAura:IsA("Model") then
			local currentScale = centralAura:GetScale()
			local bulgeScale = currentScale * 1.5
			local scaleProxy = Instance.new("NumberValue")
			scaleProxy.Value = currentScale

			local t = TweenService:Create(scaleProxy, TweenInfo.new(0.3, Enum.EasingStyle.Bounce), {Value = bulgeScale})
			local conn
			conn = scaleProxy.Changed:Connect(function(v)
				if centralAura and centralAura.Parent then centralAura:ScaleTo(v) else conn:Disconnect() end
			end)
			t:Play()
			t.Completed:Connect(function() scaleProxy:Destroy(); if conn then conn:Disconnect() end end)

			-- Flash White
			for _, desc in ipairs(centralAura:GetDescendants()) do
				if desc:IsA("BasePart") then
					TweenService:Create(desc, TweenInfo.new(0.3), {Color = Color3.fromRGB(255, 255, 255)}):Play()
				end
			end
		else
			local bulgeSize = centralAura.Size * 1.5
			TweenService:Create(centralAura, TweenInfo.new(0.3, Enum.EasingStyle.Bounce), {
				Size = bulgeSize, 
				Color = Color3.fromRGB(255, 255, 255)
			}):Play()
		end

		task.delay(0.3, function()
			local mainPart = centralAura:IsA("Model") and (centralAura.PrimaryPart or centralAura:FindFirstChildWhichIsA("BasePart")) or centralAura
			if mainPart then
				local att = Instance.new("Attachment", mainPart)
				local pe = Instance.new("ParticleEmitter", att)
				pe.Color = ColorSequence.new(Color3.fromRGB(255, 215, 0))
				pe.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 0)})
				pe.Speed = NumberRange.new(40, 90)
				pe.Drag = 3
				pe.EmissionDirection = Enum.NormalId.Top
				pe.EmitCount = 150
				pe:Emit(150)
			end

			local sfxFolder = ReplicatedStorage:FindFirstChild("SFX") or ReplicatedStorage:FindFirstChild("Sounds")
			if sfxFolder and sfxFolder:FindFirstChild("MaxOut") then
				local sfx = sfxFolder.MaxOut:Clone()
				sfx.Volume = 1
				sfx.Parent = workspace
				sfx:Play()
				game.Debris:AddItem(sfx, 3)
			end

			if centralAura:IsA("Model") then
				for _, part in ipairs(centralAura:GetDescendants()) do
					if part:IsA("BasePart") then part.Transparency = 1 end
				end
			else
				centralAura.Transparency = 1
			end

			SetupConveyors()
			SpawnExplosionCubes(bankAmount)

			task.delay(2, function()
				if centralAura then centralAura:Destroy() end
			end)
		end)
	end


end

BankActionBridge:Connect(function(payload)
	if payload.action == "bankBroken" then
		local amount = payload.amount or 0
		TriggerBreakVFX(amount)
	end
end)

-- =========================================================================
-- AURA SPAWN & GUI LOGIC
-- =========================================================================
local function CreateBankAura(currentBankSize)
	local existingAura = workspace:FindFirstChild("DynamicPiggyBankAura")
	if existingAura then existingAura:Destroy() end
	if promptGui then promptGui:Destroy() end

	local staticAura = workspace:FindFirstChild("PiggyBankAura", true)
	if staticAura then
		CollectionService:AddTag(staticAura, "PiggyBankAuraHolder")
	end

	-- ✨ THE FIX: Spawns the physical GoldenAuraLarge model in the center of the room
	local areaAssets = ReplicatedStorage:FindFirstChild("AreaAssets")
	local piggyBankFolder = areaAssets and areaAssets:FindFirstChild("PiggyBank")
	local piggyAurasFolder = piggyBankFolder and piggyBankFolder:FindFirstChild("Auras")
	local template = piggyAurasFolder and piggyAurasFolder:FindFirstChild("GoldenAuraLarge")

	local trigger = workspace:FindFirstChild("StorageTrigger", true) or workspace:FindFirstChild("GoldenTrigger", true)
	local spawnPos = staticAura and staticAura.Position or (trigger and trigger.Position + Vector3.new(0, 15, 0)) or Vector3.new(0, 15, 0)

	local centralAura
	local scale = BankConfig.CalculateAuraScale and BankConfig.CalculateAuraScale(currentBankSize) or 1

	if template then
		centralAura = template:Clone()
		centralAura.Name = "DynamicPiggyBankAura"

		if centralAura:IsA("Model") then
			centralAura:ScaleTo(scale * 1.5) 
			local primary = centralAura.PrimaryPart or centralAura:FindFirstChildWhichIsA("BasePart")
			if primary then primary.Anchored = true end
			centralAura:PivotTo(CFrame.new(spawnPos))
		end
	else
		centralAura = Instance.new("Part")
		centralAura.Name = "DynamicPiggyBankAura"
		centralAura.Anchored = true
		centralAura.Material = Enum.Material.Neon
		centralAura.Color = Color3.fromRGB(255, 215, 0)
		centralAura.Position = spawnPos
		centralAura.Size = Vector3.new(4, 4, 4) * scale
	end

	centralAura.Parent = workspace

	promptGui = Instance.new("ScreenGui")
	promptGui.Name = "PiggyBankPromptGui"
	promptGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	promptGui.DisplayOrder = 100 
	promptGui.Parent = playerGui

	local panel = Instance.new("ImageButton", promptGui)
	panel.Name = "PromptPanel"
	panel.Size = UDim2.new(0, 220, 0, 85)
	panel.AnchorPoint = Vector2.new(1, 1)
	panel.Position = UDim2.new(1, -140, 1.2, 0) 
	panel.BackgroundColor3 = T.cardBG
	panel.AutoButtonColor = false
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)

	local stroke = Instance.new("UIStroke", panel)
	stroke.Color = T.accentGold
	stroke.Thickness = 2

	CollectionService:AddTag(panel, "Tutorial_PiggyBankPrompt")

	local title = Instance.new("TextLabel", panel)
	title.Size = UDim2.new(1, 0, 0.4, 0)
	title.Position = UDim2.new(0, 0, 0, 10)
	title.BackgroundTransparency = 1
	title.Text = "BREAK THE BANK"
	title.TextColor3 = T.accentGold
	title.TextScaled = true
	title.Font = Enum.Font.FredokaOne

	local barBg = Instance.new("Frame", panel)
	barBg.Name = "BarBg"
	barBg.Size = UDim2.new(0.85, 0, 0, 20)
	barBg.Position = UDim2.new(0.075, 0, 0.6, 0)
	barBg.BackgroundColor3 = T.panelBG
	Instance.new("UICorner", barBg).CornerRadius = UDim.new(0.5, 0)

	local barBgStroke = Instance.new("UIStroke", barBg)
	barBgStroke.Color = T.panelStroke
	barBgStroke.Thickness = 1

	local fill = Instance.new("Frame", barBg)
	fill.Name = "Fill"
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = T.accentGold
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0.5, 0)

	TweenService:Create(panel, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(1, -140, 1, -25)
	}):Play()

	local function StopHold()
		if not isHolding then return end
		isHolding = false
		TweenService:Create(stroke, TweenInfo.new(0.2), {Thickness = 2}):Play()
		if holdSound then
			holdSound:Stop()
			holdSound:Destroy()
			holdSound = nil
		end

		-- ✨ THE FIX: Instantly return to straight angle on release
		TweenService:Create(panel, TweenInfo.new(0.15), {Rotation = 0}):Play()
	end

	panel.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_BreakPiggyBank") then return end

			isHolding = true
			TweenService:Create(stroke, TweenInfo.new(0.2), {Thickness = 4}):Play()

			local sfxFolder = ReplicatedStorage:FindFirstChild("SFX") or ReplicatedStorage:FindFirstChild("Sounds")
			if sfxFolder and sfxFolder:FindFirstChild("ChargeUp") then
				holdSound = sfxFolder.ChargeUp:Clone()
				holdSound.Parent = workspace
				holdSound:Play()
			end
		end
	end)

	panel.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			StopHold()
		end
	end)
	panel.MouseLeave:Connect(StopHold)


end

RunService.Heartbeat:Connect(function(dt)
	-- ✨ THE FIX: Aggressively hide normal factory buttons so they never clip into the prompt
	if inSpecialArea then
		local clickBtn = mainHUD:FindFirstChild("ClickButton", true)
		local modeToggle = mainHUD:FindFirstChild("ModeToggle", true)
		local sendBtn = mainHUD:FindFirstChild("SendButton", true)
		local hatcheryBar = mainHUD:FindFirstChild("HatcheryBar", true)

		if clickBtn and clickBtn.Visible then clickBtn.Visible = false end
		if modeToggle and modeToggle.Visible then modeToggle.Visible = false end
		if sendBtn and sendBtn.Visible then sendBtn.Visible = false end
		if hatcheryBar and hatcheryBar.Visible then hatcheryBar.Visible = false end
	end

	if not inSpecialArea or not promptGui then return end

	local panel = promptGui:FindFirstChild("PromptPanel")
	if not panel then return end
	local fillBar = panel:FindFirstChild("BarBg"):FindFirstChild("Fill")

	if isHolding then
		local holdTime = BankConfig.HoldToBreakTime or 10
		fillProgress = math.clamp(fillProgress + (dt / holdTime), 0, 1)

		-- ✨ THE FIX: Active shaking/tilting animation while charging up the break!
		tiltSide = tiltSide * -1
		TweenService:Create(panel, TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true), { Rotation = 3 * tiltSide }):Play()

		if fillProgress >= 1.0 then
			isHolding = false
			fillProgress = 0
			TweenService:Create(panel, TweenInfo.new(0.15), {Rotation = 0}):Play()

			BankActionBridge:Fire({ action = "breakBank" })
			if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
		end
	else
		local drainRate = BankConfig.DrainRate or 2
		fillProgress = math.clamp(fillProgress - (dt / drainRate), 0, 1)
	end

	if fillBar then
		fillBar.Size = UDim2.new(fillProgress, 0, 1, 0)
	end


end)

player:GetAttributeChangedSignal("InSpecialArea"):Connect(function()
	inSpecialArea = player:GetAttribute("InSpecialArea")

	if inSpecialArea then
		local bankSize = player:GetAttribute("LivePiggyBank") or 0
		CreateBankAura(bankSize)
	else
		local cAura = workspace:FindFirstChild("DynamicPiggyBankAura")
		if cAura then cAura:Destroy() end

		if promptGui then
			promptGui:Destroy()
			promptGui = nil
		end

		-- Return to farm: Restore the farm HUD elements securely
		local clickBtn = mainHUD:FindFirstChild("ClickButton", true)
		local modeToggle = mainHUD:FindFirstChild("ModeToggle", true)
		local sendBtn = mainHUD:FindFirstChild("SendButton", true)
		local hatcheryBar = mainHUD:FindFirstChild("HatcheryBar", true)

		if clickBtn then clickBtn.Visible = true end
		if modeToggle then modeToggle.Visible = true end
		if sendBtn then sendBtn.Visible = true end
		if hatcheryBar then hatcheryBar.Visible = true end
	end


end)

-- AchievementController
-- Location: StarterPlayer > StarterPlayerScripts > AchievementController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")

local UITheme = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UITheme"))
local T = UITheme.Get("Custom")
local SoundConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SoundConfig"))
local AchievementConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("AchievementConfig"))
local TierConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("TierConfig"))
local AdminConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("AdminConfig"))
local AreaRegistry = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("AreaRegistry"))
local Formatter = require(ReplicatedStorage.Modules.NumberFormatter)
local BridgeNet2 = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))

local UpdateHUDBridge = BridgeNet2.ClientBridge("UpdateHUD")
local LeaderboardBridge = BridgeNet2.ClientBridge("UpdateLeaderboards")
local UIConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UIConfig"))

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local ClaimChallenge = RemoteEvents:WaitForChild("ClaimChallenge")
local ClaimAuraIndex = RemoteEvents:WaitForChild("ClaimAuraIndex")
local ClaimBadge = RemoteEvents:WaitForChild("ClaimBadge")
local AuraDiscovered = RemoteEvents:WaitForChild("AuraDiscovered", 5)

local ForceCloseUI = ReplicatedStorage:FindFirstChild("ForceCloseUI") or Instance.new("BindableEvent")
ForceCloseUI.Name = "ForceCloseUI"
if not ForceCloseUI.Parent then ForceCloseUI.Parent = ReplicatedStorage end

local SettingsChanged = ReplicatedStorage:FindFirstChild("SettingsChanged") or Instance.new("BindableEvent")
SettingsChanged.Name = "SettingsChanged"; SettingsChanged.Parent = ReplicatedStorage

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainHUD = playerGui:WaitForChild("MainHUD")
local Faded2 = mainHUD:WaitForChild("Faded2") 

local gaurasLabel = mainHUD:FindFirstChild("GoldenAurasLabel", true) or mainHUD:FindFirstChild("GAuras", true) or mainHUD
local currLabel = mainHUD:FindFirstChild("CurrencyLabel", true) or mainHUD:FindFirstChild("Cash", true) or mainHUD

local panelOpen, activeTab, activeTabText = false, "Challenges", "Boosts"
local latestStats = {}
local sfxEnabled, musicEnabled, jumpEnabled = true, true, true 
local liveSoulAuras, liveRunEarnings, liveRate, livePrestiges = 0, 0, 0, 0
local toggleRefs, statValueRefs = {}, {}
local rowCallbacks = {}

-- Stores the live global data sent from the server
local liveLeaderboardData = {
	["Top 10"] = {},
	["Auras Generated"] = {},
	["Most Money Made"] = {},
	["Farm Evaluation"] = {},
	["Total Prestiges"] = {},
	["Legendary Auras"] = {},
	["Platforms Shipped"] = {}
}

local function PlayUI(id) 
	if not id or id == "" then return end
	id = string.gsub(id, "rbxassetid://rbxassetid://", "rbxassetid://")
	if shared.PlayUISound then shared.PlayUISound(id) end 
end

---------------------------------------------------------------
-- UNIVERSAL JUICY VISUALS (CASH & AURAS) 
---------------------------------------------------------------
local function PlayJuiceEffect(exactAmount, currencyType)
	local isAura = (currencyType == "Auras")
	local targetLabel = isAura and gaurasLabel or currLabel

	local pendingKey = isAura and "LocalPendingAuras" or "LocalPendingPayout"
	local addKey = isAura and "VisualAurasToAdd" or "VisualCashToAdd"

	local currentPending = player:GetAttribute(pendingKey) or 0
	player:SetAttribute(pendingKey, currentPending + exactAmount)

	local targetPos = targetLabel.AbsolutePosition
	local targetSize = targetLabel.AbsoluteSize

	local popupWidth = 250
	local popupHeight = 70
	local startX = targetPos.X - popupWidth - 40 
	local startY = targetPos.Y + (targetSize.Y / 2) - (popupHeight / 2) 

	local endPos2D = targetPos + (targetSize / 2)

	local effectGui = Instance.new("ScreenGui")
	effectGui.Name = "JuiceGui_" .. currencyType
	effectGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	effectGui.Parent = playerGui

	local popupText = Instance.new("TextLabel")
	popupText.Text = (isAura and "+" or "+$") .. Formatter.Format(exactAmount)
	popupText.Font = Enum.Font.FredokaOne
	popupText.TextScaled = true
	popupText.TextColor3 = isAura and Color3.fromRGB(255, 215, 0) or Color3.fromRGB(85, 255, 127)
	popupText.BackgroundTransparency = 1
	popupText.TextXAlignment = Enum.TextXAlignment.Right 
	popupText.Size = UDim2.new(0, popupWidth, 0, popupHeight)
	popupText.Position = UDim2.new(0, startX, 0, startY)
	popupText.ZIndex = 100
	popupText.Parent = effectGui

	local textStroke = Instance.new("UIStroke", popupText)
	textStroke.Color = isAura and Color3.fromRGB(80, 50, 0) or Color3.fromRGB(0, 50, 0)
	textStroke.Thickness = 3

	local textScale = Instance.new("UIScale", popupText)
	textScale.Scale = 0

	TweenService:Create(textScale, TweenInfo.new(0.4, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), {Scale = 1.2}):Play()

	task.delay(0.6, function()
		TweenService:Create(popupText, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			Position = UDim2.new(0, startX - 120, 0, startY),
			TextTransparency = 1
		}):Play()
		TweenService:Create(textStroke, TweenInfo.new(0.8), {Transparency = 1}):Play()
	end)

	local sfxFolder = ReplicatedStorage:FindFirstChild("SFX") or ReplicatedStorage:FindFirstChild("Sounds")
	if sfxFolder and sfxFolder:FindFirstChild("CashRegister") then
		local sfx = sfxFolder.CashRegister:Clone()
		if isAura then sfx.Pitch = 1.3 end 
		sfx.Parent = game:GetService("SoundService")
		sfx:Play()
		Debris:AddItem(sfx, 2)
	end

	local iconCount = 10
	local iconSize = 40
	local iconId = "rbxassetid://14916846070" 

	if isAura then
		iconId = "rbxassetid://4483362458" 
		if exactAmount < 100 then
			iconCount = math.min(exactAmount, 30)
			iconSize = 35 
		elseif exactAmount < 1000 then
			iconCount = math.min(math.ceil(exactAmount / 10), 30)
			iconSize = 55 
		else
			iconCount = math.min(math.ceil(exactAmount / 100), 30)
			iconSize = 80 
		end
	end

	local chunkAmount = exactAmount / iconCount
	local coinsHit = 0

	for i = 1, iconCount do
		local coin = Instance.new("ImageLabel")
		coin.Image = iconId
		if isAura then coin.ImageColor3 = Color3.fromRGB(255, 215, 0) end 
		coin.BackgroundTransparency = 1
		coin.Size = UDim2.new(0, iconSize, 0, iconSize)

		local coinStartX = startX + popupWidth - (iconSize * 1.5)
		local coinStartY = startY + (popupHeight / 2) - (iconSize / 2)

		coin.Position = UDim2.new(0, coinStartX, 0, coinStartY)
		coin.ZIndex = 90
		coin.Parent = effectGui

		local randomOffsetX = math.random(-80, 80)
		local randomOffsetY = math.random(-80, 80)
		local burstPos = UDim2.new(0, coinStartX + randomOffsetX, 0, coinStartY + randomOffsetY)

		local burstTween = TweenService:Create(coin, TweenInfo.new(0.3, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), {
			Position = burstPos,
			Rotation = math.random(-180, 180)
		})
		burstTween:Play()

		burstTween.Completed:Connect(function()
			local flyTween = TweenService:Create(coin, TweenInfo.new(0.4 + (i * 0.02), Enum.EasingStyle.Back, Enum.EasingDirection.In), {
				Position = UDim2.new(0, endPos2D.X - (iconSize/2), 0, endPos2D.Y - (iconSize/2)),
				Size = UDim2.new(0, iconSize/2, 0, iconSize/2),
				ImageTransparency = 0.3
			})
			flyTween:Play()

			flyTween.Completed:Connect(function()
				if coin.Parent then coin:Destroy() end
				coinsHit += 1

				player:SetAttribute(addKey, chunkAmount)

				local pending = player:GetAttribute(pendingKey) or 0
				player:SetAttribute(pendingKey, math.max(0, pending - chunkAmount))

				if sfxFolder and sfxFolder:FindFirstChild("CoinTick") then
					local sfx = sfxFolder.CoinTick:Clone()
					sfx.Pitch = (isAura and 1.8 or 1.5) + (math.random()*0.2)
					sfx.Parent = game:GetService("SoundService")
					sfx:Play()
					Debris:AddItem(sfx, 1)
				end

				local ts = targetLabel:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", targetLabel)
				ts.Scale = 1.1
				TweenService:Create(ts, TweenInfo.new(0.1, Enum.EasingStyle.Sine), {Scale = 1}):Play()
			end)
		end)
	end

	task.delay(3, function()
		if effectGui.Parent then effectGui:Destroy() end
		if coinsHit < iconCount then
			local remaining = (iconCount - coinsHit) * chunkAmount
			player:SetAttribute(addKey, remaining)
			player:SetAttribute(pendingKey, 0)
		end
	end)
end

local AreaAuras = AchievementConfig.AreaAuras

local function PlayClaimVFX(rowFrame)
	PlayUI(SoundConfig.MaxOut or "rbxassetid://4612384643")

	local flash = Instance.new("Frame", rowFrame); flash.Size = UDim2.new(1,0,1,0); flash.BackgroundColor3 = Color3.fromRGB(255, 255, 255); flash.ZIndex = 50; flash.BorderSizePixel = 0
	Instance.new("UICorner", flash).CornerRadius = UDim.new(0, 8)
	TweenService:Create(flash, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 1}):Play()
	task.delay(0.4, function() flash:Destroy() end)
	for i = 1, 8 do
		local particle = Instance.new("Frame", rowFrame); particle.Size = UDim2.new(0, 10, 0, 10); particle.BackgroundColor3 = T.accentGold; particle.AnchorPoint = Vector2.new(0.5, 0.5); particle.Position = UDim2.new(0.5, 0, 0.5, 0); particle.ZIndex = 51; Instance.new("UICorner", particle).CornerRadius = UDim.new(1, 0)
		local angle = math.rad(math.random(0, 360)); local dist = math.random(30, 80); local endPos = UDim2.new(0.5, math.cos(angle)*dist, 0.5, math.sin(angle)*dist)
		TweenService:Create(particle, TweenInfo.new(0.5, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), {Position = endPos, Size = UDim2.new(0,0,0,0), BackgroundTransparency = 1}):Play()
		task.delay(0.5, function() particle:Destroy() end)
	end
end

local AchieveBtn = Instance.new("ImageButton", Faded2); AchieveBtn.Name = "AchievementButton"; AchieveBtn.Size = UDim2.new(0.85, 0, 0.85, 0); AchieveBtn.BackgroundColor3 = T.buttonSecondary; AchieveBtn.BorderSizePixel = 0; AchieveBtn.LayoutOrder = 1; Instance.new("UICorner", AchieveBtn).CornerRadius = UDim.new(0.5, 0); Instance.new("UIAspectRatioConstraint", AchieveBtn).AspectRatio = 1.0; local btnStroke = Instance.new("UIStroke", AchieveBtn); btnStroke.Color = Color3.fromRGB(255, 243, 111); btnStroke.Thickness = 2; local btnIcon = Instance.new("ImageLabel", AchieveBtn); btnIcon.Size = UDim2.new(0.7, 0, 0.7, 0); btnIcon.Position = UDim2.new(0.15, 0, 0.15, 0); btnIcon.BackgroundTransparency = 1; btnIcon.ScaleType = Enum.ScaleType.Fit; btnIcon.Image = UIConfig.Icons.AchieveButton or "rbxassetid://14923131909"
CollectionService:AddTag(AchieveBtn, "Tutorial_AchieveMenuBtn")

local Panel = Instance.new("Frame", mainHUD)
Panel.Name = "AchievementPanel"
Panel.Size = UDim2.new(1, -110, 0.85, 0) 
Panel.Position = UDim2.new(0, -500, 0.5, 0) 
Panel.AnchorPoint = Vector2.new(0, 0.5) 
Panel.BackgroundColor3 = T.panelBG
Panel.BorderSizePixel = 0
Panel.Visible = false
Panel.ZIndex = 40
Panel.ClipsDescendants = true
Instance.new("UICorner", Panel).CornerRadius = UDim.new(0, 12)
Instance.new("UISizeConstraint", Panel).MaxSize = Vector2.new(500, 650)
local panelStroke = Instance.new("UIStroke", Panel); panelStroke.Color = T.panelStroke; panelStroke.Thickness = 2
CollectionService:AddTag(Panel, "Tutorial_AchievePanel")

local Header = Instance.new("Frame", Panel); Header.Size = UDim2.new(1, 0, 0, 44); Header.BackgroundColor3 = T.headerBG; Header.BorderSizePixel = 0; Header.ZIndex = 41
local TitleLabel = Instance.new("TextLabel", Header); TitleLabel.Size = UDim2.new(1, -50, 1, 0); TitleLabel.Position = UDim2.new(0, 14, 0, 0); TitleLabel.BackgroundTransparency = 1; TitleLabel.Text = "MENU"; TitleLabel.TextColor3 = T.headerText; TitleLabel.TextScaled = true; TitleLabel.Font = T.font; TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
local CloseBtn = Instance.new("TextButton", Header); CloseBtn.Size = UDim2.new(0, 28, 0, 28); CloseBtn.Position = UDim2.new(1, -36, 0.5, -14); CloseBtn.BackgroundColor3 = T.buttonRed; CloseBtn.Text = "X"; CloseBtn.TextColor3 = T.headerText; CloseBtn.TextScaled = true; CloseBtn.Font = T.font; Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 5); CloseBtn.ZIndex = 9999
CollectionService:AddTag(CloseBtn, "Tutorial_AchieveCloseBtn")

local TabContainer = Instance.new("Frame", Panel); TabContainer.Size = UDim2.new(1, 0, 0, 75); TabContainer.Position = UDim2.new(0, 0, 0, 44); TabContainer.BackgroundTransparency = 1; TabContainer.ZIndex = 41
local HoverLabel = Instance.new("TextLabel", TabContainer); HoverLabel.Size = UDim2.new(1, 0, 0, 20); HoverLabel.Position = UDim2.new(0, 0, 1, -15); HoverLabel.BackgroundTransparency = 1; HoverLabel.Text = "Boosts"; HoverLabel.TextColor3 = T.bodyText; HoverLabel.TextScaled = true; HoverLabel.Font = T.font
local TabButtonFrame = Instance.new("Frame", TabContainer); TabButtonFrame.Size = UDim2.new(1, 0, 1, -20); TabButtonFrame.BackgroundTransparency = 1; local TabListLayout = Instance.new("UIListLayout", TabButtonFrame); TabListLayout.FillDirection = Enum.FillDirection.Horizontal; TabListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center; TabListLayout.VerticalAlignment = Enum.VerticalAlignment.Center; TabListLayout.Padding = UDim.new(0, 12)

local tabBtns, scrolls = {}, {}
local function MakeTab(name, hoverText, iconId)
	local btn = Instance.new("ImageButton", TabButtonFrame); btn.Size = UDim2.new(0, 45, 0, 45); btn.BackgroundColor3 = T.buttonSecondary; btn.AutoButtonColor = false; Instance.new("UICorner", btn).CornerRadius = UDim.new(0.5, 0); local tStroke = Instance.new("UIStroke", btn); tStroke.Color = T.panelStroke; tStroke.Thickness = 2; local icon = Instance.new("ImageLabel", btn); icon.Size = UDim2.new(0.6, 0, 0.6, 0); icon.Position = UDim2.new(0.2, 0, 0.2, 0); icon.BackgroundTransparency = 1; icon.ScaleType = Enum.ScaleType.Fit; icon.Image = iconId; tabBtns[name] = {btn = btn, stroke = tStroke}; CollectionService:AddTag(btn, "Tutorial_AchieveTab_" .. name)

	if name ~= "Leaderboard" then
		local sf = Instance.new("ScrollingFrame", Panel); sf.Size = UDim2.new(1, -20, 1, -135); sf.Position = UDim2.new(0, 10, 0, 125); sf.BackgroundTransparency = 1; sf.BorderSizePixel = 0; sf.ScrollBarThickness = 4; sf.Visible = false
		local layout = Instance.new("UIListLayout", sf)
		layout.Padding = UDim.new(0, 8)
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.SortOrder = Enum.SortOrder.LayoutOrder 
		layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function() sf.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 10) end)
		scrolls[name] = sf
	end

	btn.MouseEnter:Connect(function() HoverLabel.Text = hoverText end); btn.MouseLeave:Connect(function() HoverLabel.Text = activeTabText end)
	btn.MouseButton1Down:Connect(function()
		if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_ClickAchieveTab_" .. name) then return end
		PlayUI(SoundConfig.UIClick or ""); activeTab = name; activeTabText = hoverText; HoverLabel.Text = activeTabText
		for k, t in pairs(tabBtns) do t.btn.BackgroundColor3 = (k == name) and T.accentGold or T.buttonSecondary; t.stroke.Color = (k == name) and T.bodyText or T.panelStroke end
		for k, s in pairs(scrolls) do s.Visible = (k == name) end
		TitleLabel.Text = (name == "Settings") and "SETTINGS" or "PROGRESSION"
		if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
	end)
end

MakeTab("Challenges", "Boosts", UIConfig.Icons.AchieveTabChallenges or "rbxassetid://14916846070"); MakeTab("Index", "Auras", UIConfig.Icons.AchieveTabIndex or "rbxassetid://14916846070"); MakeTab("Badges", "Badges", UIConfig.Icons.AchieveTabBadges or "rbxassetid://14916846070"); MakeTab("Leaderboard", "Leaderboard", UIConfig.Icons.AchieveTabLeaderboard or "rbxassetid://14916846070"); MakeTab("Settings", "Settings", UIConfig.Icons.AchieveTabSettings or "rbxassetid://14923131909") 

local lbWrapper = Instance.new("Frame", Panel)
lbWrapper.Name = "LeaderboardWrapper"
lbWrapper.Size = UDim2.new(1, -20, 1, -135)
lbWrapper.Position = UDim2.new(0, 10, 0, 125)
lbWrapper.BackgroundTransparency = 1
lbWrapper.Visible = false
scrolls["Leaderboard"] = lbWrapper 

local lbSubTabContainer = Instance.new("ScrollingFrame", lbWrapper)
lbSubTabContainer.Name = "SubTabContainer"
lbSubTabContainer.Size = UDim2.new(0, 55, 1, 0)
lbSubTabContainer.BackgroundTransparency = 1
lbSubTabContainer.BorderSizePixel = 0
lbSubTabContainer.ScrollBarThickness = 0

local lbSubTabLayout = Instance.new("UIListLayout", lbSubTabContainer)
lbSubTabLayout.FillDirection = Enum.FillDirection.Vertical
lbSubTabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
lbSubTabLayout.VerticalAlignment = Enum.VerticalAlignment.Top
lbSubTabLayout.Padding = UDim.new(0, 15)
lbSubTabLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	lbSubTabContainer.CanvasSize = UDim2.new(0, 0, 0, lbSubTabLayout.AbsoluteContentSize.Y + 20)
end)

local lbScroll = Instance.new("ScrollingFrame", lbWrapper)
lbScroll.Size = UDim2.new(1, -65, 1, 0)
lbScroll.Position = UDim2.new(0, 65, 0, 0)
lbScroll.BackgroundTransparency = 1
lbScroll.BorderSizePixel = 0
lbScroll.ScrollBarThickness = 4

local lbContentLayout = Instance.new("UIListLayout", lbScroll)
lbContentLayout.Padding = UDim.new(0, 8)
lbContentLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

lbContentLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	lbScroll.CanvasSize = UDim2.new(0, 0, 0, lbContentLayout.AbsoluteContentSize.Y + 10)
end)

local activeLbTab = "Auras Generated"
local lbSubBtns = {}

local function BuildLeaderboardRows(tabName)
	for _, child in ipairs(lbScroll:GetChildren()) do if child:IsA("Frame") then child:Destroy() end end

	local data = liveLeaderboardData[tabName] or {}

	if #data == 0 then
		local loadingLbl = Instance.new("TextLabel", lbScroll)
		loadingLbl.Size = UDim2.new(1, 0, 0, 45)
		loadingLbl.BackgroundTransparency = 1
		loadingLbl.Text = "Awaiting live data..."
		loadingLbl.TextColor3 = T.subText
		loadingLbl.Font = Enum.Font.GothamMedium
		loadingLbl.TextScaled = true
		return
	end

	for _, p in ipairs(data) do
		local row = Instance.new("Frame", lbScroll)
		row.Size = UDim2.new(1, 0, 0, 45)
		row.BackgroundColor3 = T.cardBG
		Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)

		local rankLbl = Instance.new("TextLabel", row)
		rankLbl.Size = UDim2.new(0, 40, 1, 0)
		rankLbl.Position = UDim2.new(0, 10, 0, 0)
		rankLbl.BackgroundTransparency = 1
		rankLbl.Text = "#" .. p.rank
		rankLbl.TextColor3 = (p.rank==1) and Color3.fromRGB(255,215,0) or ((p.rank==2) and Color3.fromRGB(192,192,192) or ((p.rank==3) and Color3.fromRGB(205,127,50) or T.subText))
		rankLbl.Font = Enum.Font.GothamBold
		rankLbl.TextScaled = true
		rankLbl.TextWrapped = true
		Instance.new("UITextSizeConstraint", rankLbl).MaxTextSize = 22

		local nameLbl = Instance.new("TextLabel", row)
		nameLbl.Size = UDim2.new(0.45, -50, 1, 0)
		nameLbl.Position = UDim2.new(0, 60, 0, 0)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Text = p.name
		nameLbl.TextColor3 = T.bodyText
		nameLbl.Font = Enum.Font.GothamMedium
		nameLbl.TextScaled = true
		nameLbl.TextWrapped = true
		nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		Instance.new("UITextSizeConstraint", nameLbl).MaxTextSize = 18

		-- ✨ NEW: Formatting perfectly syncs across all types of leaderboards
		local displayValue = ""
		if tabName == "Top 10" then
			displayValue = Formatter.Format(p.val) .. " Soul Auras"
		elseif tabName == "Auras Generated" then
			displayValue = Formatter.Format(p.val) .. " Auras"
		elseif tabName == "Most Money Made" then
			displayValue = "$" .. Formatter.Format(p.val)
		elseif tabName == "Farm Evaluation" then
			displayValue = "$" .. Formatter.Format(p.val)
		elseif tabName == "Total Prestiges" then
			displayValue = Formatter.Format(p.val) .. " Prestiges"
		elseif tabName == "Legendary Auras" then
			displayValue = Formatter.Format(p.val) .. " Legendaries"
		elseif tabName == "Platforms Shipped" then
			displayValue = Formatter.Format(p.val) .. " Shipped"
		end

		local valLbl = Instance.new("TextLabel", row)
		valLbl.Size = UDim2.new(0.55, -20, 1, 0)
		valLbl.Position = UDim2.new(0.45, 10, 0, 0)
		valLbl.BackgroundTransparency = 1
		valLbl.Text = displayValue
		valLbl.TextColor3 = T.accentGold
		valLbl.Font = Enum.Font.GothamBold
		valLbl.TextScaled = true
		valLbl.TextWrapped = true
		valLbl.TextXAlignment = Enum.TextXAlignment.Right
		Instance.new("UITextSizeConstraint", valLbl).MaxTextSize = 18

		UITheme.Apply(row, "Card")
	end
end

LeaderboardBridge:Connect(function(newData)
	if newData then
		liveLeaderboardData = newData
		if activeTab == "Leaderboard" then
			BuildLeaderboardRows(activeLbTab)
		end
	end
end)

local function MakeLbSubTab(tabName, iconId)
	local btn = Instance.new("ImageButton", lbSubTabContainer)
	btn.Size = UDim2.new(0, 45, 0, 45)
	btn.BackgroundColor3 = (tabName == activeLbTab) and T.accentGold or T.buttonSecondary
	btn.AutoButtonColor = false
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0.5, 0)

	local tStroke = Instance.new("UIStroke", btn)
	tStroke.Color = (tabName == activeLbTab) and T.bodyText or T.panelStroke
	tStroke.Thickness = 2

	local icon = Instance.new("ImageLabel", btn)
	icon.Size = UDim2.new(0.6, 0, 0.6, 0)
	icon.Position = UDim2.new(0.2, 0, 0.2, 0)
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = iconId

	CollectionService:AddTag(btn, "Tutorial_LbTab_" .. string.gsub(tabName, " ", ""))
	lbSubBtns[tabName] = {btn = btn, stroke = tStroke}

	btn.MouseEnter:Connect(function() HoverLabel.Text = tabName end)
	btn.MouseLeave:Connect(function() HoverLabel.Text = activeTabText end)

	btn.MouseButton1Down:Connect(function()
		if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_ClickLbTab_" .. string.gsub(tabName, " ", "")) then return end
		PlayUI(SoundConfig.UIClick or "")
		activeLbTab = tabName
		HoverLabel.Text = tabName
		for k, t in pairs(lbSubBtns) do
			t.btn.BackgroundColor3 = (k == tabName) and T.accentGold or T.buttonSecondary
			t.stroke.Color = (k == tabName) and T.bodyText or T.panelStroke
		end
		BuildLeaderboardRows(activeLbTab)
		if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
	end)

	local scale = Instance.new("UIScale", btn)
	btn.MouseEnter:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15), {Scale = 1.05}):Play() end)
	btn.MouseLeave:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15), {Scale = 1}):Play() end)
	btn.MouseButton1Down:Connect(function() TweenService:Create(scale, TweenInfo.new(0.1), {Scale = 0.95}):Play() end)
	btn.MouseButton1Up:Connect(function() TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), {Scale = 1.05}):Play() end)
end

-- ✨ NEW: 4 Added Leaderboards
MakeLbSubTab("Top 10", "rbxassetid://14916846070") 
MakeLbSubTab("Auras Generated", "rbxassetid://4483362458") 
MakeLbSubTab("Most Money Made", "rbxassetid://14924185885") 
MakeLbSubTab("Farm Evaluation", "rbxassetid://14951953206")
MakeLbSubTab("Total Prestiges", "rbxassetid://14959712404")
MakeLbSubTab("Legendary Auras", "rbxassetid://14949477468")
MakeLbSubTab("Platforms Shipped", "rbxassetid://14958914404")

BuildLeaderboardRows(activeLbTab)

local setScroll = scrolls["Settings"]; local pad = Instance.new("UIPadding", setScroll); pad.PaddingTop = UDim.new(0, 5)
local function MakeToggleRow(labelText, settingKey)
	local row = Instance.new("Frame", setScroll); row.Size = UDim2.new(1, -10, 0, 42); row.BackgroundColor3 = T.cardBG; row.BorderSizePixel = 0; row.ZIndex = 41; Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)
	local lbl = Instance.new("TextLabel", row); lbl.Size = UDim2.new(0.6, 0, 1, 0); lbl.Position = UDim2.new(0, 15, 0, 0); lbl.BackgroundTransparency = 1; lbl.Text = labelText; lbl.TextColor3 = T.subText; lbl.TextScaled = true; lbl.Font = T.fontBody; lbl.TextXAlignment = Enum.TextXAlignment.Left
	local toggle = Instance.new("TextButton", row); toggle.Size = UDim2.new(0, 60, 0, 30); toggle.Position = UDim2.new(1, -70, 0.5, -15); toggle.BorderSizePixel = 0; toggle.TextScaled = true; toggle.Font = T.font; Instance.new("UICorner", toggle).CornerRadius = UDim.new(0, 6); CollectionService:AddTag(toggle, "Tutorial_SettingToggle_" .. settingKey)
	local function Refresh(isOn) toggle.Text = isOn and "ON" or "OFF"; toggle.TextColor3 = T.bodyText; toggle.BackgroundColor3 = isOn and T.buttonGreen or T.buttonRed end
	local isOn = true; if settingKey == "sfx" then isOn = sfxEnabled elseif settingKey == "music" then isOn = musicEnabled elseif settingKey == "jump" then isOn = jumpEnabled end
	Refresh(isOn); toggleRefs[settingKey] = Refresh
	toggle.MouseButton1Down:Connect(function()
		if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_ToggleSetting_" .. settingKey) then return end
		PlayUI(SoundConfig.UIClick or ""); if settingKey == "sfx" then sfxEnabled = not sfxEnabled; isOn = sfxEnabled elseif settingKey == "music" then musicEnabled = not musicEnabled; isOn = musicEnabled elseif settingKey == "jump" then jumpEnabled = not jumpEnabled; isOn = jumpEnabled end
		Refresh(isOn); SettingsChanged:Fire(settingKey, isOn)
		if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
	end)
end
MakeToggleRow("Sound Effects", "sfx"); MakeToggleRow("Music", "music"); MakeToggleRow("Jumping", "jump") 

local div1 = Instance.new("Frame", setScroll); div1.Size = UDim2.new(1, -20, 0, 2); div1.BackgroundColor3 = T.panelStroke; div1.BorderSizePixel = 0
local statsTitle = Instance.new("TextLabel", setScroll); statsTitle.Size = UDim2.new(1, -20, 0, 20); statsTitle.BackgroundTransparency = 1; statsTitle.Text = "FARM STATS"; statsTitle.TextColor3 = T.subText; statsTitle.TextScaled = true; statsTitle.Font = T.font; statsTitle.TextXAlignment = Enum.TextXAlignment.Left
local function MakeStatRow(labelText, refKey)
	local row = Instance.new("Frame", setScroll); row.Size = UDim2.new(1, -20, 0, 26); row.BackgroundTransparency = 1; local lbl = Instance.new("TextLabel", row); lbl.Size = UDim2.new(0.55, 0, 1, 0); lbl.BackgroundTransparency = 1; lbl.Text = labelText; lbl.TextColor3 = T.subText; lbl.TextScaled = true; lbl.Font = T.fontBody; lbl.TextXAlignment = Enum.TextXAlignment.Left; local val = Instance.new("TextLabel", row); val.Size = UDim2.new(0.45, 0, 1, 0); val.Position = UDim2.new(0.55, 0, 0, 0); val.BackgroundTransparency = 1; val.Text = "0"; val.TextColor3 = T.accentBlue; val.TextScaled = true; val.Font = T.font; val.TextXAlignment = Enum.TextXAlignment.Right; statValueRefs[refKey] = val
end
MakeStatRow("Soul Auras", "soul"); MakeStatRow("This Run", "run"); MakeStatRow("Rate", "rate"); MakeStatRow("Prestiges", "prestige")
local function RefreshStats() if statValueRefs.soul then statValueRefs.soul.Text = Formatter.Format(liveSoulAuras) end; if statValueRefs.run then statValueRefs.run.Text = "$" .. Formatter.Format(liveRunEarnings) end; if statValueRefs.rate then statValueRefs.rate.Text = "$" .. Formatter.Format(liveRate) .. "/s" end; if statValueRefs.prestige then statValueRefs.prestige.Text = Formatter.Format(livePrestiges) end end

local function CreateInteractiveRow(parent, id, claimActionId, onClaimCallback)
	local row = parent:FindFirstChild(id)

	rowCallbacks[id] = onClaimCallback

	if not row then
		row = Instance.new("TextButton", parent); row.Name = id; row.Text = ""; row.AutoButtonColor = false; row.Size = UDim2.new(1, -8, 0, 64); row.BackgroundColor3 = T.cardBG; Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8); local stroke = Instance.new("UIStroke", row); stroke.Name = "Stroke"; stroke.Thickness = 1

		local icon = Instance.new("ImageLabel", row); icon.Name = "Icon"; icon.Size = UDim2.new(0, 50, 0, 50); icon.Position = UDim2.new(0, 8, 0.5, -25); icon.ScaleType = Enum.ScaleType.Fit; icon.BackgroundTransparency = 1; Instance.new("UICorner", icon).CornerRadius = UDim.new(1, 0)

		local tLbl = Instance.new("TextLabel", row); tLbl.Name = "Title"; tLbl.Size = UDim2.new(0.5, 0, 0, 20); tLbl.Position = UDim2.new(0, 66, 0, 10); tLbl.BackgroundTransparency = 1; tLbl.TextColor3 = T.bodyText; tLbl.TextScaled = true; tLbl.Font = T.font; tLbl.TextXAlignment = Enum.TextXAlignment.Left
		local dLbl = Instance.new("TextLabel", row); dLbl.Name = "Desc"; dLbl.Size = UDim2.new(0.5, 0, 0, 24); dLbl.Position = UDim2.new(0, 66, 0, 32); dLbl.BackgroundTransparency = 1; dLbl.TextColor3 = T.subText; dLbl.TextScaled = true; dLbl.TextWrapped = true; dLbl.Font = T.fontBody; dLbl.TextXAlignment = Enum.TextXAlignment.Left

		local sLbl = Instance.new("TextLabel", row); sLbl.Name = "Status"; sLbl.Size = UDim2.new(0.3, 0, 0, 24); sLbl.Position = UDim2.new(1, -10, 0.5, -12); sLbl.AnchorPoint = Vector2.new(1, 0); sLbl.BackgroundTransparency = 1; sLbl.TextScaled = true; sLbl.Font = T.font; sLbl.TextXAlignment = Enum.TextXAlignment.Right

		UITheme.Apply(row, "Card"); CollectionService:AddTag(row, "Tutorial_AchieveRow_" .. id)
		local scale = Instance.new("UIScale", row)
		row.MouseEnter:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15), {Scale = 1.02}):Play() end)
		row.MouseLeave:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15), {Scale = 1}):Play(); row.Desc.Text = row:GetAttribute("BaseDesc") or "" end)

		row.MouseButton1Down:Connect(function()
			TweenService:Create(scale, TweenInfo.new(0.1), {Scale = 0.95}):Play()
			if row:GetAttribute("RowState") == "CLAIMABLE" then
				if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform(claimActionId) then return end
				PlayClaimVFX(row); 
				if rowCallbacks[id] then rowCallbacks[id]() end 
				if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
			else
				PlayUI(SoundConfig.UIClick or ""); local showingReq = not row:GetAttribute("ShowingReq"); row:SetAttribute("ShowingReq", showingReq)
				if showingReq and row:GetAttribute("ReqDesc") ~= "" then row.Desc.Text = row:GetAttribute("ReqDesc"); row.Desc.TextColor3 = T.accentGold else row.Desc.Text = row:GetAttribute("BaseDesc"); row.Desc.TextColor3 = T.subText end
			end
		end)
		row.MouseButton1Up:Connect(function() TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), {Scale = 1.02}):Play() end)
	end

	return row
end

local function RefreshData()
	local claimedChallenges, claimedAuras, claimedBadges, discoveredTiers = latestStats.claimedChallenges or {}, latestStats.claimedAuras or {}, latestStats.claimedBadges or {}, latestStats.discoveredTiers or {}

	for i, chal in ipairs(AchievementConfig.Challenges) do
		local current = latestStats[chal.statKey] or 0
		local isDone = current >= chal.goal; local isClaimed = claimedChallenges[chal.id] == true
		local rowId = "Chal_" .. chal.id
		local row = CreateInteractiveRow(scrolls["Challenges"], rowId, "Action_ClaimChallenge_" .. chal.id, function() ClaimChallenge:FireServer(chal.id) end)
		row.LayoutOrder = i 
		row.Title.Text = chal.title; row.Icon.Image = chal.iconId; row:SetAttribute("BaseDesc", chal.rewardText); row:SetAttribute("ReqDesc", "Requires: " .. chal.desc)
		if isClaimed then row:SetAttribute("RowState", "CLAIMED"); row.Status.Text = "UNLOCKED"; row.Status.TextColor3 = T.subText; row.BackgroundColor3 = T.cardBG; row.Stroke.Color = T.accentBlue; row.Desc.Text = chal.rewardText; row.Desc.TextColor3 = T.subText
		elseif isDone then row:SetAttribute("RowState", "CLAIMABLE"); row.Status.Text = "CLAIM!"; row.Status.TextColor3 = Color3.fromRGB(255, 255, 255); row.BackgroundColor3 = Color3.fromRGB(80, 160, 60); row.Stroke.Color = Color3.fromRGB(120, 255, 100); row.Desc.Text = "Click to Unlock!"; row.Desc.TextColor3 = Color3.fromRGB(200, 255, 200)
		else row:SetAttribute("RowState", "LOCKED"); row.Status.Text = Formatter.Format(current) .. " / " .. Formatter.Format(chal.goal); row.Status.TextColor3 = T.subText; row.BackgroundColor3 = T.cardBG; row.Stroke.Color = T.subText; row.Desc.Text = (not row:GetAttribute("ShowingReq")) and chal.rewardText or ("Requires: " .. chal.desc); row.Desc.TextColor3 = T.subText end
	end

	local indexCount = 1
	for aIdx = 1, #AreaAuras do
		local areaData = AreaAuras[aIdx]
		if not areaData then continue end

		local headerId = "AreaHeader_" .. aIdx
		local header = scrolls["Index"]:FindFirstChild(headerId)
		if not header then
			header = Instance.new("TextLabel", scrolls["Index"])
			header.Name = headerId
			header.Size = UDim2.new(1, -8, 0, 30)
			header.BackgroundTransparency = 1
			header.Text = "- AREA " .. aIdx .. " -"
			header.TextColor3 = T.accentGold
			header.Font = Enum.Font.GothamBold
			header.TextSize = 18
			header.TextXAlignment = Enum.TextXAlignment.Center
		end
		header.LayoutOrder = aIdx * 100 

		local areaMult = 1.0
		if type(AreaRegistry.GetMultiplier) == "function" then
			areaMult = AreaRegistry.GetMultiplier(aIdx)
		end

		for tIdx, auraData in ipairs(areaData) do
			local tierName = auraData.tier
			local auraName = auraData.name

			local tierColor = Color3.fromRGB(255, 255, 255)
			local tierMultiplier = 1
			if TierConfig and TierConfig.Tiers then
				for _, t in ipairs(TierConfig.Tiers) do
					if t.name == tierName then
						tierColor = t.color
						tierMultiplier = t.multiplier or 1
						break
					end
				end
			end

			local auraKey = aIdx .. "_" .. tierName
			local discovered = discoveredTiers[auraKey] == true
			local isClaimed = claimedAuras[auraKey] == true
			local rewardGA = AchievementConfig.AuraTierRewards[tierName] or 5

			local baseVal = math.floor((AdminConfig.BaseAuraValue or 1) * tierMultiplier * areaMult)
			local valueDesc = "Base Value: $" .. Formatter.Format(baseVal)

			local row = CreateInteractiveRow(scrolls["Index"], "Index_" .. indexCount, "Action_ClaimAura_" .. aIdx .. "_" .. tierName, function() 
				ClaimAuraIndex:FireServer(aIdx, tierName) 
				PlayJuiceEffect(rewardGA, "Auras")
			end)
			row.LayoutOrder = (aIdx * 100) + tIdx

			if auraData.iconId and auraData.iconId ~= "" then
				local cleanId = string.gsub(auraData.iconId, "rbxassetid://", "")
				row.Icon.Image = "rbxassetid://" .. cleanId
			else
				row.Icon.Image = "rbxassetid://0"
			end

			if isClaimed then 
				row:SetAttribute("RowState", "CLAIMED")
				row.Title.Text = auraName
				row.Title.TextColor3 = tierColor
				row.Status.Text = "FOUND"
				row.Status.TextColor3 = T.subText
				row.BackgroundColor3 = T.cardBG
				row.Stroke.Color = tierColor
				row:SetAttribute("BaseDesc", valueDesc)
				row:SetAttribute("ReqDesc", "")
				row.Desc.Text = valueDesc
				row.Desc.TextColor3 = T.subText

				row.Icon.ImageColor3 = Color3.fromRGB(255, 255, 255)
				row.Icon.ImageTransparency = 0
			elseif discovered then 
				row:SetAttribute("RowState", "CLAIMABLE")
				row.Title.Text = auraName
				row.Title.TextColor3 = Color3.fromRGB(255, 255, 255)
				row.Status.Text = "CLAIM +" .. rewardGA .. " GA!"
				row.Status.TextColor3 = Color3.fromRGB(255, 215, 0)
				row.BackgroundColor3 = Color3.fromRGB(150, 110, 20)
				row.Stroke.Color = Color3.fromRGB(255, 215, 0)
				row:SetAttribute("BaseDesc", "Click to claim reward!")
				row:SetAttribute("ReqDesc", "")
				row.Desc.Text = "Click to claim reward!"
				row.Desc.TextColor3 = Color3.fromRGB(255, 240, 150)

				row.Icon.ImageColor3 = Color3.fromRGB(255, 255, 255)
				row.Icon.ImageTransparency = 0
			else 
				row:SetAttribute("RowState", "LOCKED")
				row.Title.Text = "???"
				row.Title.TextColor3 = Color3.fromRGB(100, 100, 100)
				row.Status.Text = "???"
				row.Status.TextColor3 = T.buttonRed
				row.BackgroundColor3 = T.cardBG
				row.Stroke.Color = Color3.fromRGB(50, 50, 50)
				row:SetAttribute("BaseDesc", "Undiscovered")
				row:SetAttribute("ReqDesc", valueDesc)
				row.Desc.Text = "Undiscovered"
				row.Desc.TextColor3 = T.subText 

				row.Icon.ImageColor3 = Color3.new(0, 0, 0)
				row.Icon.ImageTransparency = 0.5 
			end
			indexCount += 1
		end
	end

	for i, badge in ipairs(AchievementConfig.Badges) do
		local current = latestStats[badge.statKey] or 0; local isDone = current >= badge.goal; local isClaimed = claimedBadges[i] == true
		local row = CreateInteractiveRow(scrolls["Badges"], "Badge_" .. i, "Action_ClaimBadge_" .. i, function() ClaimBadge:FireServer(i) end)
		row.LayoutOrder = i 
		row.Title.Text = badge.title; row.Icon.Image = badge.iconId; row:SetAttribute("BaseDesc", badge.desc); row:SetAttribute("ReqDesc", "Goal: " .. Formatter.Format(badge.goal))

		-- ✨ NEW: Hide the normal text label
		row.Status.Visible = false

		-- ✨ NEW: Add the progress bar container
		local barBg = row:FindFirstChild("ProgressBarBg")
		if not barBg then
			barBg = Instance.new("Frame", row)
			barBg.Name = "ProgressBarBg"
			barBg.Size = UDim2.new(0.3, 0, 0, 24)
			barBg.Position = UDim2.new(1, -10, 0.5, 0)
			barBg.AnchorPoint = Vector2.new(1, 0.5)
			barBg.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
			barBg.BorderSizePixel = 0
			Instance.new("UICorner", barBg).CornerRadius = UDim.new(0, 8)

			local stroke = Instance.new("UIStroke", barBg)
			stroke.Color = T.panelStroke
			stroke.Thickness = 1

			local barFill = Instance.new("Frame", barBg)
			barFill.Name = "ProgressBarFill"
			barFill.Size = UDim2.new(0, 0, 1, 0)
			barFill.BackgroundColor3 = T.accentGold
			barFill.BorderSizePixel = 0
			Instance.new("UICorner", barFill).CornerRadius = UDim.new(0, 8)

			local barText = Instance.new("TextLabel", barBg)
			barText.Name = "ProgressBarText"
			barText.Size = UDim2.new(1, 0, 1, 0)
			barText.BackgroundTransparency = 1
			barText.TextColor3 = Color3.fromRGB(255, 255, 255)
			barText.TextScaled = true
			barText.Font = T.font
			local pad = Instance.new("UIPadding", barText)
			pad.PaddingTop = UDim.new(0, 3); pad.PaddingBottom = UDim.new(0, 3)
		end

		local fillRatio = math.clamp(current / badge.goal, 0, 1)
		barBg.ProgressBarFill.Size = UDim2.new(fillRatio, 0, 1, 0)

		if isClaimed then 
			row:SetAttribute("RowState", "CLAIMED"); row.BackgroundColor3 = T.cardBG; row.Stroke.Color = T.accentGold; row.Desc.Text = badge.desc; row.Desc.TextColor3 = T.subText
			barBg.ProgressBarFill.BackgroundColor3 = Color3.fromRGB(150, 150, 150)
			barBg.ProgressBarText.Text = "OWNED"
		elseif isDone then 
			row:SetAttribute("RowState", "CLAIMABLE"); row.BackgroundColor3 = Color3.fromRGB(120, 60, 180); row.Stroke.Color = Color3.fromRGB(200, 100, 255); row.Desc.Text = "Click to receive Badge!"; row.Desc.TextColor3 = Color3.fromRGB(230, 200, 255)
			barBg.ProgressBarFill.BackgroundColor3 = Color3.fromRGB(100, 255, 100)
			barBg.ProgressBarText.Text = "CLAIM!"
		else 
			row:SetAttribute("RowState", "LOCKED"); row.BackgroundColor3 = T.cardBG; row.Stroke.Color = T.subText; row.Desc.Text = badge.desc; row.Desc.TextColor3 = T.subText 
			barBg.ProgressBarFill.BackgroundColor3 = T.subText
			barBg.ProgressBarText.Text = Formatter.Format(current) .. " / " .. Formatter.Format(badge.goal)
		end

		local icon = row:FindFirstChild("Icon")
		if icon then
			icon.ImageColor3 = Color3.new(1, 1, 1)
			icon.ImageTransparency = 0
		end
	end
end

UpdateHUDBridge:Connect(function(stats)
	for key, value in pairs(stats) do latestStats[key] = value end
	if stats.soulAuras ~= nil then liveSoulAuras = stats.soulAuras end; if stats.totalEarned ~= nil then liveRunEarnings = stats.totalEarned end; if stats.rate ~= nil and stats.passiveInterval ~= nil and stats.passiveInterval > 0 then liveRate = stats.rate / stats.passiveInterval end; if stats.prestigeCount ~= nil then livePrestiges = stats.prestigeCount end
	if stats.settings then
		if stats.settings.sfxEnabled ~= nil then sfxEnabled = stats.settings.sfxEnabled; if toggleRefs.sfx then toggleRefs.sfx(sfxEnabled) end end
		if stats.settings.musicEnabled ~= nil then musicEnabled = stats.settings.musicEnabled; if toggleRefs.music then toggleRefs.music(musicEnabled) end end
		if stats.settings.jumpEnabled ~= nil then jumpEnabled = stats.settings.jumpEnabled; if toggleRefs.jump then toggleRefs.jump(jumpEnabled) end end
	end
	if panelOpen then RefreshData(); RefreshStats() end
end)

local function OpenToTab(tabName, hoverText)
	ForceCloseUI:Fire("AchievementPanel")

	PlayUI(SoundConfig.UIOpen or "")
	panelOpen = true
	Panel.Visible = true
	Panel.Size = UDim2.new(1, -110, 0.85, 0)
	activeTab = tabName
	activeTabText = hoverText
	HoverLabel.Text = activeTabText
	for k, t in pairs(tabBtns) do t.btn.BackgroundColor3 = (k == activeTab) and T.accentGold or T.buttonSecondary; t.stroke.Color = (k == activeTab) and T.bodyText or T.panelStroke end
	for k, s in pairs(scrolls) do s.Visible = (k == activeTab) end
	RefreshData(); RefreshStats(); TitleLabel.Text = (tabName == "Settings") and "SETTINGS" or "PROGRESSION"

	TweenService:Create(Panel, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0, 95, 0.5, 0) }):Play()
end

local function ClosePanel()
	if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_CloseAchievements") then return end
	PlayUI(SoundConfig.UIClose or "")
	panelOpen = false
	TweenService:Create(Panel, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.new(0, -500, 0.5, 0) }):Play()
	task.delay(0.25, function() if not panelOpen then Panel.Visible = false end end)
	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
end

AchieveBtn.MouseButton1Down:Connect(function()
	if not panelOpen then
		if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_OpenAchievements") then return end
		OpenToTab("Challenges", "Boosts")
		if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
	else
		ClosePanel()
	end
end)

CloseBtn.MouseButton1Down:Connect(ClosePanel)

local function AddButtonJuice(btn)
	local scale = btn:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", btn)
	btn.MouseEnter:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15), {Scale = 1.08}):Play() end)
	btn.MouseLeave:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15), {Scale = 1}):Play() end)
	btn.MouseButton1Down:Connect(function() TweenService:Create(scale, TweenInfo.new(0.1), {Scale = 0.9}):Play() end)
	btn.MouseButton1Up:Connect(function() TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), {Scale = 1.08}):Play() end)
end
AddButtonJuice(AchieveBtn); AddButtonJuice(CloseBtn)
for _, t in pairs(tabBtns) do AddButtonJuice(t.btn) end

task.spawn(function() task.wait(1); UITheme.Apply(Panel, "Panel"); UITheme.Apply(Header, "TitleBar"); UITheme.ApplyShine(Panel) end)

local defaultJumpHeight = 7.2
local defaultJumpPower = 50

local function UpdateJumpState(character, canJump)
	if not character then return end
	local humanoid = character:WaitForChild("Humanoid", 3)
	if humanoid then
		if humanoid.JumpHeight > 0 then defaultJumpHeight = humanoid.JumpHeight end
		if humanoid.JumpPower > 0 then defaultJumpPower = humanoid.JumpPower end

		if canJump then
			humanoid.UseJumpPower = not humanoid.UseJumpPower 
			humanoid.JumpHeight = defaultJumpHeight
			humanoid.JumpPower = defaultJumpPower
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		else
			humanoid.JumpHeight = 0
			humanoid.JumpPower = 0
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		end
	end
end

SettingsChanged.Event:Connect(function(key, value)
	if key == "jump" then UpdateJumpState(player.Character, value) end
end)

player.CharacterAdded:Connect(function(char)
	task.wait(0.1) UpdateJumpState(char, jumpEnabled)
end)

if player.Character then UpdateJumpState(player.Character, jumpEnabled) end

ForceCloseUI.Event:Connect(function(exceptionPanel)
	if exceptionPanel ~= "AchievementPanel" and panelOpen then 
		ClosePanel() 
	end 
end)

-- BankManager
-- Location: ServerScriptService > BankManager

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local MarketplaceService = game:GetService("MarketplaceService")

local BankConfig = require(ReplicatedStorage.Modules:WaitForChild("BankConfig"))
local GameManager = require(ServerScriptService:WaitForChild("GameManager"))
local BridgeNet2 = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))

local UpdateHUDBridge = BridgeNet2.ServerBridge("UpdateHUD")
local BankActionBridge = BridgeNet2.ServerBridge("BankAction")
local AreaChanged = ReplicatedStorage.RemoteEvents:WaitForChild("AreaChanged")

local BankManager = {}
local GamepassCache = {}

local function CheckGamepasses(player)
	GamepassCache[player.UserId] = {}
	for key, passData in pairs(BankConfig.Gamepasses) do
		pcall(function()
			GamepassCache[player.UserId][key] = MarketplaceService:UserOwnsGamePassAsync(player.UserId, passData.id)
		end)
	end
end

Players.PlayerAdded:Connect(CheckGamepasses)

Players.PlayerRemoving:Connect(function(player)
	GamepassCache[player.UserId] = nil
	local data = GameManager.GetData(player.UserId)
	if data and data.pendingBankPayout and data.pendingBankPayout > 0 then
		data.goldenAuras = (data.goldenAuras or 0) + data.pendingBankPayout
		data.pendingBankPayout = 0
		GameManager.SavePlayer(player)
	end
end)

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
	if wasPurchased then
		for key, passData in pairs(BankConfig.Gamepasses) do
			if passData.id == passId then
				if not GamepassCache[player.UserId] then GamepassCache[player.UserId] = {} end
				GamepassCache[player.UserId][key] = true
				break
			end
		end
	end
end)

local BankFillEvent = Instance.new("BindableEvent")
BankFillEvent.Name = "BankFillEvent"
BankFillEvent.Parent = ServerScriptService

BankFillEvent.Event:Connect(function(userId, baseAmount)
	local data = GameManager.GetData(userId)
	if not data then return end

	local fillMultiplier = 1.0
	if GamepassCache[userId] and GamepassCache[userId].FasterFill then
		fillMultiplier = BankConfig.Gamepasses.FasterFill.multiplier
	end

	local currentBank = data.piggyBank or 0
	local effectiveDeposit = BankConfig.CalculateEffectiveDeposit(baseAmount, currentBank, fillMultiplier)

	data.piggyBank = currentBank + effectiveDeposit

	local player = Players:GetPlayerByUserId(userId)
	if player then
		UpdateHUDBridge:Fire(player, { piggyBank = data.piggyBank })
		BankActionBridge:Fire(player, { action = "fillVisual", amount = effectiveDeposit })
	end
end)

BankActionBridge:Connect(function(player, payload)
	local data = GameManager.GetData(player.UserId)
	local runtime = GameManager.GetRuntime(player.UserId)
	if not data then return end

	if payload.action == "teleportToBank" then
		local currentAurmers = data.aurmers or 0
		if currentAurmers >= 1 then
			data.aurmers = currentAurmers - 1
			data.inSpecialArea = true

			-- ✨ THE FIX: We MUST wipe active server cubes so they stop ticking in the vault!
			if runtime and runtime.cubes then
				for cubeId, _ in pairs(runtime.cubes) do
					GameManager.RemoveCube(player.UserId, cubeId)
				end
			end

			UpdateHUDBridge:Fire(player, { aurmers = data.aurmers })
			BankActionBridge:Fire(player, { action = "teleportApproved" })

			-- Inform the client to swap the 3D visual models to the Piggy Bank!
			AreaChanged:FireClient(player, { newArea = "PiggyBank" })
		end

	elseif payload.action == "breakBank" then
		if not data.inSpecialArea then return end

		local bankAmount = data.piggyBank or 0
		if bankAmount <= 0 then return end

		if GamepassCache[player.UserId] and GamepassCache[player.UserId].BonusBreak then
			bankAmount = math.floor(bankAmount * BankConfig.Gamepasses.BonusBreak.bonus)
		end

		data.piggyBank = 0
		data.pendingBankPayout = bankAmount

		UpdateHUDBridge:Fire(player, { piggyBank = data.piggyBank })
		BankActionBridge:Fire(player, { action = "bankBroken", amount = bankAmount })
		GameManager.SavePlayer(player)

	elseif payload.action == "claimBankCube" then
		local claimAmt = payload.amount or 0
		if not data.pendingBankPayout or data.pendingBankPayout <= 0 then return end

		claimAmt = math.min(claimAmt, data.pendingBankPayout)
		data.pendingBankPayout -= claimAmt
		data.goldenAuras = (data.goldenAuras or 0) + claimAmt

		if data.pendingBankPayout < 0.1 then 
			data.goldenAuras = math.ceil(data.goldenAuras)
			data.pendingBankPayout = 0 
		end

		UpdateHUDBridge:Fire(player, { goldenAuras = math.floor(data.goldenAuras) })

	elseif payload.action == "returnToFarm" then
		data.inSpecialArea = false

		-- ✨ THE FIX: Wipe any leftover invisible cubes before going home
		if runtime and runtime.cubes then
			for cubeId, _ in pairs(runtime.cubes) do
				GameManager.RemoveCube(player.UserId, cubeId)
			end
		end

		BankActionBridge:Fire(player, { action = "returnApproved" })

		-- Inform the client to swap the 3D visual models back to the Farm!
		AreaChanged:FireClient(player, { newArea = data.currentArea })
	end
end)

return BankManager
