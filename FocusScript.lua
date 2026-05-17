-- ClickHandler
-- Location: StarterPlayer > StarterPlayerScripts > ClickHandler

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

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local holding = false

-- ✨ Dynamic Sync State
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

local function FormatNumber(n)
	return NumberFormatter.Format(n)
end	

---------------------------------------------------------------
-- AURA MODEL FOLDERS & INSTANTIATION
---------------------------------------------------------------
local VFXFolder = ReplicatedStorage:FindFirstChild("VFX")
local cubeDataMap = {}

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
	local heavyProps = PhysicalProperties.new(100, 0.3, 0, 1, 100) 
	if instance:IsA("BasePart") then instance.CustomPhysicalProperties = heavyProps
	elseif instance:IsA("Model") then
		for _, part in ipairs(instance:GetDescendants()) do
			if part:IsA("BasePart") then part.CustomPhysicalProperties = heavyProps end
		end
	end
end

local function SpawnAuraInstance(tierName, color, glow, position, currentArea)
	currentArea = currentArea or 1
	local auraModel = PoolManager.GetAura(currentArea, tierName)

	if auraModel:IsA("Model") then
		auraModel:PivotTo(CFrame.new(position))
		if auraModel.PrimaryPart then
			auraModel.PrimaryPart.Anchored = false
			auraModel.PrimaryPart.CanCollide = true
			auraModel.PrimaryPart.CollisionGroup = "Auras"
		end
	elseif auraModel:IsA("BasePart") then
		auraModel.Position = position
		auraModel.Anchored = false
		auraModel.CanCollide = true
		auraModel.CollisionGroup = "Auras"
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

	auraModel.Parent = workspace
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

---------------------------------------------------------------
-- VFX SYSTEM
---------------------------------------------------------------
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

---------------------------------------------------------------
-- GAMEPLAY VISUAL LOGIC
---------------------------------------------------------------
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

	local bb = Instance.new("BillboardGui"); bb.Name = "PermanentRateLabel"; bb.Size = UDim2.new(0, 90, 0, 25); bb.StudsOffset = Vector3.new(0, 0.5, 0); bb.AlwaysOnTop = false; bb.Adornee = rootPart

	local label = Instance.new("TextLabel"); label.Size = UDim2.new(1, 0, 1, 0); label.BackgroundTransparency = 1
	local ratePerSec = baseValue / currentPassiveInterval
	label.Text = "+$" .. FormatNumber(ratePerSec) .. "/sec"

	label.TextColor3 = auraColor or Color3.fromRGB(100, 255, 100); label.Font = Enum.Font.GothamBold; label.TextScaled = true
	label.TextTransparency = 0.2; label.TextStrokeTransparency = 0.6; label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0); label.Parent = bb

	bb.Parent = rootPart
	return label -- We return the TextLabel
end

---------------------------------------------------------------
-- ✨ DYNAMIC LABEL REFRESH
---------------------------------------------------------------
local function RefreshAllRateLabels()
	for id, data in pairs(cubeDataMap) do
		if data.rateLabel and data.baseValue and not data.isStored then
			local ratePerSec = (data.baseValue * globalBoostMultiplier) / currentPassiveInterval
			data.rateLabel.Text = "+$" .. FormatNumber(ratePerSec) .. "/sec"

			if data.rateLabel.Parent then
				local scale = data.rateLabel.Parent:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", data.rateLabel.Parent)
				TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), {Scale = 1.2}):Play()
				task.delay(0.2, function() TweenService:Create(scale, TweenInfo.new(0.2), {Scale = 1}):Play() end)
			end
		end
	end
end

---------------------------------------------------------------
-- DYNAMIC TRIGGER HOOKS
---------------------------------------------------------------
local AuraHolder = workspace:WaitForChild("AuraHolder")
local HabitatHolder = workspace:WaitForChild("HabitatHolder")

local function UpdateHabitatBar(actualPending, max)
	local offset = player:GetAttribute("HabitatVisualOffset") or 0
	local current = actualPending + offset

	local habitatModel = HabitatHolder:FindFirstChildWhichIsA("Model")
	if not habitatModel then return end

	local habitatGui = habitatModel:FindFirstChild("HabitatGui", true)
	if not habitatGui then return end

	local bg = habitatGui:FindFirstChild("BarBackground")
	if not bg then return end

	local fill = bg:FindFirstChild("BarFill")
	local textLabel = bg:FindFirstChild("CountLabel") or bg:FindFirstChild("AmountLabel")

	if fill and max > 0 then
		local ratio = math.clamp(current / max, 0, 1)

		TweenService:Create(fill, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(ratio, 0, 1, 0)
		}):Play()

		local targetColor = Color3.fromRGB(80, 220, 80)
		if ratio >= 1 then targetColor = Color3.fromRGB(255, 60, 60)
		elseif ratio >= 0.8 then targetColor = Color3.fromRGB(255, 200, 0) end

		TweenService:Create(fill, TweenInfo.new(0.2), {BackgroundColor3 = targetColor}):Play()

		if textLabel then
			if current >= max then
				textLabel.Text = "FULL!"
				textLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
			else
				textLabel.Text = math.floor(current) .. " / " .. max
				textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
			end
		end
	end
end

player:GetAttributeChangedSignal("HabitatVisualOffset"):Connect(function()
	UpdateHabitatBar(latestPendingAuras, latestHabitatCapacity)
end)

local function GetAuraCubeFromHit(hit)
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
					for id, data in pairs(cubeDataMap) do
						if data.instance == auraObj then
							if data.isStored then return end
							CubeSmushedBridge:Fire(id)
							local root = GetRootPart(auraObj)
							local pos = (root and root.Position) or hit.Position
							PlayVFX("Spawn", pos, 0.5) 

							PoolManager.ReturnAura(data.instance) 
							cubeDataMap[id] = nil
							break
						end
					end
				end
			end)
		end

		-- ✨ FIX: Loop through ALL ConveyerPaths instead of just finding the first one
		for _, conveyer in ipairs(model:GetDescendants()) do
			if conveyer.Name == "ConveyerPath" and conveyer:IsA("BasePart") then
				local forwardBeam = conveyer:FindFirstChild("Foward") or conveyer:FindFirstChild("Forward")
				local backwardBeam = conveyer:FindFirstChild("Backward")

				if forwardBeam then forwardBeam.Enabled = not habitatFull end
				if backwardBeam then backwardBeam.Enabled = habitatFull end

				-- ✨ DYNAMIC VELOCITY: Uses the part's local X-axis instead of the world's X-axis
				if habitatFull then 
					conveyer.AssemblyLinearVelocity = conveyer.CFrame.RightVector * 10
				else 
					conveyer.AssemblyLinearVelocity = conveyer.CFrame.RightVector * -5 
				end
			end
		end

		local storageBelt = model:FindFirstChild("StorageBelt", true)
		if not storageBelt then
			local habModel = HabitatHolder:FindFirstChildWhichIsA("Model")
			if habModel then storageBelt = habModel:FindFirstChild("StorageBelt", true) end
		end
		if storageBelt then storageBelt.AssemblyLinearVelocity = Vector3.new(-5, 0, 0) end
	end)
end

local function HookHabitatModel(model)
	task.delay(0.1, function()
		local storage = model:FindFirstChild("StorageTrigger", true)
		if storage then
			storage.Touched:Connect(function(hit)
				local auraObj = GetAuraCubeFromHit(hit)
				if auraObj then
					for id, data in pairs(cubeDataMap) do
						if data.instance == auraObj and not data.isStored then
							data.isStored = true

							if data.rateLabel and data.rateLabel.Parent and data.rateLabel.Parent:IsA("BillboardGui") then 
								data.rateLabel.Parent.Enabled = false 
							end

							local root = GetRootPart(auraObj)
							if root then
								local dropOffset = Vector3.new(-10, 4, math.random(-4, 4))
								auraObj:PivotTo(CFrame.new(storage.Position + dropOffset))
								root.AssemblyLinearVelocity = Vector3.new(0, -10, 0)
								root.AssemblyAngularVelocity = Vector3.new(math.random(-5, 5), math.random(-5, 5), math.random(-5, 5))
							end

							CubeStoredBridge:Fire(id)
							break
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

---------------------------------------------------------------
-- INPUT CONTROLS & TUTORIAL GATING
---------------------------------------------------------------
local trackedInputs = {}

local function EvaluateHolding()
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

	-- ✨ FIX: Loop through ALL aura models, and ALL of their ConveyerPaths
	for _, auraModel in ipairs(AuraHolder:GetChildren()) do
		if auraModel:IsA("Model") then
			for _, conveyer in ipairs(auraModel:GetDescendants()) do
				if conveyer.Name == "ConveyerPath" and conveyer:IsA("BasePart") then
					local forwardBeam = conveyer:FindFirstChild("Foward") or conveyer:FindFirstChild("Forward")
					local backwardBeam = conveyer:FindFirstChild("Backward")

					-- ✨ DYNAMIC VELOCITY: Uses the part's local X-axis instead of the world's X-axis
					if isFull then 
						conveyer.AssemblyLinearVelocity = conveyer.CFrame.RightVector * 10 
						if forwardBeam then forwardBeam.Enabled = false end
						if backwardBeam then backwardBeam.Enabled = true end
					else 
						conveyer.AssemblyLinearVelocity = conveyer.CFrame.RightVector * -5 
						if forwardBeam then forwardBeam.Enabled = true end
						if backwardBeam then backwardBeam.Enabled = false end
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

	if stats.pendingAuras ~= nil and stats.habitatCapacity ~= nil then
		latestPendingAuras = stats.pendingAuras
		latestHabitatCapacity = stats.habitatCapacity

		if stats.pendingAuras < stats.habitatCapacity and habitatFull then
			habitatFull = false; HabitatFullEvent:Fire(false); UpdateButtonVisual()
		end
		UpdateHabitatBar(stats.pendingAuras, stats.habitatCapacity)
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

---------------------------------------------------------------
-- AURA MUTATION RESPONSES (BRIDGENET2)
---------------------------------------------------------------
AuraSpawnedBridge:Connect(function(info)
	local instance, isCustom = SpawnAuraInstance(info.tier, info.color, info.glow, info.spawnPos, info.currentArea)

	instance:SetAttribute("AuraCube", true)
	ScaleAura(instance, info.tier, false)
	ShowCubeValue(info.spawnPos, info.value, info.color)
	PlayVFX("Spawn", info.spawnPos, 1.0)

	local permLabel = AttachPermanentRateLabel(instance, info.value, info.color)

	if info.tier == "Legendary" then
		ShowTierPopup(info.spawnPos, "Legendary", Color3.fromRGB(255, 200, 0))
		PlayVFX("Legendary", info.spawnPos, 2.0)
	end

	if info.cubeId then
		cubeDataMap[info.cubeId] = { 
			instance = instance, 
			tierName = info.tier, 
			isCustom = isCustom,
			rateLabel = permLabel,
			baseValue = info.value 
		}
		instance.AncestryChanged:Connect(function(_, parent)
			if not parent then cubeDataMap[info.cubeId] = nil end
		end)
	end
end)

CubeMutatedBatchBridge:Connect(function(batchData)
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
			local newAura = PoolManager.GetAura(info.currentArea, info.tierName)

			if newAura:IsA("Model") then
				newAura:PivotTo(CFrame.new(position))
				if newAura.PrimaryPart then
					newAura.PrimaryPart.Anchored = false
					newAura.PrimaryPart.CanCollide = true
					newAura.PrimaryPart.CollisionGroup = "Auras"
				end
			elseif newAura:IsA("BasePart") then
				newAura.Position = position
				newAura.Anchored = false
				newAura.CanCollide = true
				newAura.CollisionGroup = "Auras"
				newAura.Color = info.newColor
			end

			for _, desc in ipairs(newAura:GetDescendants()) do
				if desc:IsA("ParticleEmitter") or desc:IsA("Trail") then desc.Enabled = true end
			end

			newAura.Parent = workspace
			newAura:SetAttribute("AuraCube", true)
			ScaleAura(newAura, info.tierName, true, oldTierName)
			ApplyHeavyPhysics(newAura)

			if cubeData.rateLabel and cubeData.rateLabel.Parent and cubeData.rateLabel.Parent:IsA("BillboardGui") then
				local bb = cubeData.rateLabel.Parent
				bb.Adornee = GetRootPart(newAura)
				bb.Parent = GetRootPart(newAura)
				cubeData.rateLabel.TextColor3 = info.newColor or Color3.fromRGB(100, 255, 100)
				if cubeData.isStored then bb.Enabled = false end
			end

			PoolManager.ReturnAura(instance)
			cubeData.instance = newAura; cubeData.tierName = info.tierName; cubeData.isCustom = true
			newAura.AncestryChanged:Connect(function(_, parent) if not parent then cubeDataMap[info.cubeId] = nil end end)

			ShowTierPopup(position, info.tierName, info.newColor)
		end

		if cubeData.rateLabel and cubeData.rateLabel.Parent and not cubeData.isStored then
			local ratePerSec = ((cubeData.baseValue or 0) * globalBoostMultiplier) / currentPassiveInterval
			cubeData.rateLabel.Text = "+$" .. FormatNumber(ratePerSec) .. "/sec"
		end
	end
end)

---------------------------------------------------------------
-- ✨ ANTI-STUCK / FALL-OFF FAILSAFE ✨
---------------------------------------------------------------
task.spawn(function()
	while true do
		task.wait(1.5)
		local now = tick()

		for id, data in pairs(cubeDataMap) do
			if not data.isStored and data.instance and data.instance.Parent then
				local root = GetRootPart(data.instance)
				if root then
					local currentPos = root.Position
					if not data.spawnY then
						data.spawnY = currentPos.Y; data.lastPos = currentPos; data.lastMovedTime = now
					end
					if currentPos.Y < data.spawnY - 12 then
						CubeSmushedBridge:Fire(id)
						PlayVFX("Spawn", currentPos, 0.5)
						PoolManager.ReturnAura(data.instance)
						cubeDataMap[id] = nil
						continue
					end

					local dist = (currentPos - data.lastPos).Magnitude
					if dist < 0.25 then
						if now - data.lastMovedTime > 8 then
							CubeSmushedBridge:Fire(id)
							PlayVFX("Spawn", currentPos, 0.5)
							PoolManager.ReturnAura(data.instance)
							cubeDataMap[id] = nil
						end
					else
						data.lastPos = currentPos; data.lastMovedTime = now
					end
				end
			end
		end
	end
end)
