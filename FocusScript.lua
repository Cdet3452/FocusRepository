-- STREAMING_CHUNK:Loading VFX and Core Dependencies...
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")

local AdminConfig = require(ReplicatedStorage.Modules:WaitForChild("AdminConfig"))
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
local tiltSide = 1
local isBankBroken = false

-- STREAMING_CHUNK:Setting up utility tweens...
local function FadeOutAndDestroy(obj, tweenDuration, destroyDelay)
	if not obj or not obj.Parent then return end
	destroyDelay = destroyDelay or tweenDuration

	if obj:IsA("BasePart") then
		TweenService:Create(obj, TweenInfo.new(tweenDuration), {Size = Vector3.zero, Transparency = 1}):Play()
	else
		for _, desc in ipairs(obj:GetDescendants()) do
			if desc:IsA("BasePart") or desc:IsA("Decal") or desc:IsA("Texture") then
				TweenService:Create(desc, TweenInfo.new(tweenDuration), {Transparency = 1}):Play()
			end
		end
	end

	Debris:AddItem(obj, destroyDelay)
end

-- STREAMING_CHUNK:Injecting 40% Premium Animation Logic...
local function PlayPremiumBonusAnimation(amount)
	local premiumGui = Instance.new("ScreenGui")
	premiumGui.Name = "PremiumBonusGui"
	premiumGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	premiumGui.DisplayOrder = 1000
	premiumGui.Parent = playerGui

	local container = Instance.new("Frame")
	container.Size = UDim2.new(0, 350, 0, 100)
	container.Position = UDim2.new(0.5, 0, 0.45, 0)
	container.AnchorPoint = Vector2.new(0.5, 0.5)
	container.BackgroundTransparency = 1
	container.Parent = premiumGui

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0.4, 0)
	title.BackgroundTransparency = 1
	title.Text = "PREMIUM BONUS APPLIED!"
	title.TextColor3 = Color3.fromRGB(180, 100, 255) 
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.Parent = container

	local amtLabel = Instance.new("TextLabel")
	amtLabel.Size = UDim2.new(1, 0, 0.6, 0)
	amtLabel.Position = UDim2.new(0, 0, 0.4, 0)
	amtLabel.BackgroundTransparency = 1
	amtLabel.Text = "+" .. NumberFormatter.Format(amount) .. " GA"
	amtLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
	amtLabel.Font = Enum.Font.GothamBlack
	amtLabel.TextScaled = true
	amtLabel.Parent = container

	local str1 = Instance.new("UIStroke", title)
	str1.Color = Color3.new(0, 0, 0)
	str1.Thickness = 2
	local str2 = Instance.new("UIStroke", amtLabel)
	str2.Color = Color3.new(0, 0, 0)
	str2.Thickness = 3

	local scale = Instance.new("UIScale", container)
	scale.Scale = 0
	TweenService:Create(scale, TweenInfo.new(0.5, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), {Scale = 1}):Play()

	local sfxFolder = ReplicatedStorage:FindFirstChild("SFX") or ReplicatedStorage:FindFirstChild("Sounds")
	if sfxFolder and sfxFolder:FindFirstChild("CashRegister") then
		local sfx = sfxFolder.CashRegister:Clone()
		sfx.Pitch = 0.85 
		sfx.Volume = 1.5
		sfx.Parent = game:GetService("SoundService")
		sfx:Play()
		Debris:AddItem(sfx, 2)
	end

	task.delay(1.5, function()
		TweenService:Create(container, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
			Position = UDim2.new(0.5, 0, 0.35, 0)
		}):Play()
		TweenService:Create(title, TweenInfo.new(1), {TextTransparency = 1}):Play()
		TweenService:Create(amtLabel, TweenInfo.new(1), {TextTransparency = 1}):Play()
		TweenService:Create(str1, TweenInfo.new(1), {Transparency = 1}):Play()
		TweenService:Create(str2, TweenInfo.new(1), {Transparency = 1}):Play()
		task.delay(1.5, function() premiumGui:Destroy() end)
	end)
end

-- STREAMING_CHUNK:Configuring Juice Popups...
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

-- STREAMING_CHUNK:Handling Bank Break Physical Mechanics...
local function SpawnExplosionCubes(totalAmount)
	local totalToSpawn = math.max(1, math.min(totalAmount, 100))
	local aurasValues = table.create(totalToSpawn, 1)
	local remaining = totalAmount - totalToSpawn

	for i = 1, totalToSpawn do
		if remaining >= 499 then
			aurasValues[i] = 500
			remaining -= 499
		elseif remaining >= 49 then
			aurasValues[i] = 50
			remaining -= 49
		end
	end

	if remaining > 0 then
		aurasValues[1] += remaining
	end

	local auraModel = workspace:FindFirstChild("AuraModel", true) or workspace:FindFirstChild("AuraHolder", true)
	local pbAura = auraModel and auraModel:FindFirstChild("PiggyBankAura")
	local spawnPart = pbAura and pbAura:FindFirstChild("Position")

	local spawnPos = spawnPart and spawnPart.Position or Vector3.new(0, 15, 0)
	if spawnPart then
		spawnPos = spawnPos + Vector3.new(0, 5, 0)
	end

	local trigger = workspace:FindFirstChild("GoldenTrigger", true)
	local vfxFolder = ReplicatedStorage:FindFirstChild("VFX")
	local sfxFolder = ReplicatedStorage:FindFirstChild("SFX") or ReplicatedStorage:FindFirstChild("Sounds")

	local function GetAuraDataFromValue(val)
		local templateName = "GoldenAuraSmall"
		if val >= 500 then
			templateName = "GoldenAuraLarge"
		elseif val >= 50 then
			templateName = "GoldenAuraMedium"
		end

		return vfxFolder and vfxFolder:FindFirstChild(templateName)
	end

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

	local visualAmountLeft = totalAmount

	-- STREAMING_CHUNK:Running physics on flying aura pieces...
	for i, cubeValue in ipairs(aurasValues) do
		local template = GetAuraDataFromValue(cubeValue)
		local cube

		if template then
			cube = template:Clone()
		else
			cube = Instance.new("Part")
			cube.Shape = Enum.PartType.Ball
			cube.Size = Vector3.new(2.5, 2.5, 2.5) 
			cube.Color = Color3.fromRGB(255, 215, 0)
			cube.Material = Enum.Material.Neon
		end

		local mainPart = cube:IsA("Model") and (cube.PrimaryPart or cube:FindFirstChildWhichIsA("BasePart")) or cube
		if not mainPart then continue end

		local prompt = cube:FindFirstChildOfClass("ProximityPrompt") or cube:FindFirstChildWhichIsA("ProximityPrompt", true)
		if prompt then prompt:Destroy() end

		mainPart.CanCollide = true
		mainPart.Anchored = false 

		mainPart.CustomPhysicalProperties = PhysicalProperties.new(0.4, 0.3, 0.05, 1, 1) 

		if cube:IsA("Model") then cube:PivotTo(CFrame.new(spawnPos)) else cube.Position = spawnPos end
		cube.Parent = workspace

		CollectionService:AddTag(mainPart, "BankExplosionCube")
		task.delay(1.25, function()
			if mainPart and mainPart.Parent then
				mainPart:SetAttribute("SuckToCenter", true)
			end
		end)

		visualAmountLeft = math.max(0, visualAmountLeft - cubeValue)
		if promptGui then
			local panel = promptGui:FindFirstChild("PromptPanel")
			if panel then
				local counter = panel:FindFirstChild("CounterLabel")
				if counter then
					counter.Text = NumberFormatter.Format(visualAmountLeft) .. " Auras"
				end
			end
		end

		task.wait(0.02)

		local angle = math.random() * math.pi * 2
		local outForce = math.random(AdminConfig.PhysicsOutwardForceMin or 40, AdminConfig.PhysicsOutwardForceMax or 90)
		local upForce = math.random(AdminConfig.PhysicsUpwardForceMin or 70, AdminConfig.PhysicsUpwardForceMax or 120)
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

		-- STREAMING_CHUNK:Catching Physics bounces and collisions...
		connection = mainPart.Touched:Connect(function(hit)
			if hit == trigger then
				if claimed then return end
				claimed = true
				if connection then connection:Disconnect() end

				CollectionService:RemoveTag(mainPart, "BankExplosionCube")

				mainPart.Anchored = true
				mainPart.CanCollide = false

				FadeOutAndDestroy(cube, 0.2, 5.0)

				BankActionBridge:Fire({ action = "claimBankCube", amount = cubeValue })
				PlayJuiceEffect(cubeValue, "Auras")

				if sfxFolder and (sfxFolder:FindFirstChild("BuyPing") or sfxFolder:FindFirstChild("ClassicBass")) then
					local sfx = (sfxFolder:FindFirstChild("BuyPing") or sfxFolder:FindFirstChild("ClassicBass")):Clone()
					sfx.Parent = workspace
					sfx.Volume = 0.6
					sfx.PlaybackSpeed = 1.0 + (math.random(-15, 15)/100)
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
				CollectionService:RemoveTag(mainPart, "BankExplosionCube")

				FadeOutAndDestroy(cube, 0.5, 5.0)

				BankActionBridge:Fire({ action = "claimBankCube", amount = cubeValue })
				PlayJuiceEffect(cubeValue, "Auras")
			end
		end)

		task.wait(0.01)
	end

	-- STREAMING_CHUNK:Cleaning up the physical break instance...
	task.delay(2, function()
		if promptGui then
			local panel = promptGui:FindFirstChild("PromptPanel")
			if panel then
				TweenService:Create(panel, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In), {Position = UDim2.new(0.5, 0, 1.5, 0)}):Play()
				task.delay(0.3, function() if promptGui then promptGui:Destroy(); promptGui = nil end end)
			end
		end
	end)
end

-- STREAMING_CHUNK:Responding to Remote Payloads...
local function TriggerBreakVFX(bankAmount)
	if promptGui then
		local panel = promptGui:FindFirstChild("PromptPanel")
		if panel then
			local title = panel:FindFirstChild("TitleLabel")
			if title then title.Text = "EXTRACTING..." end
			local barBg = panel:FindFirstChild("BarBg")
			if barBg then barBg.Visible = false end
		end
	end

	local sfxFolder = ReplicatedStorage:FindFirstChild("SFX") or ReplicatedStorage:FindFirstChild("Sounds")
	if sfxFolder and sfxFolder:FindFirstChild("MaxOut") then
		local sfx = sfxFolder.MaxOut:Clone()
		sfx.Volume = 1
		sfx.Parent = workspace
		sfx:Play()
		game.Debris:AddItem(sfx, 3)
	end

	SpawnExplosionCubes(bankAmount)
end

BankActionBridge:Connect(function(payload)
	if payload.action == "teleportApproved" then
		if payload.bonusAmount and payload.bonusAmount > 0 then
			PlayPremiumBonusAnimation(payload.bonusAmount)
		end
	elseif payload.action == "bankBroken" then
		isBankBroken = true
		local amount = payload.amount or 0
		TriggerBreakVFX(amount)
	end
end)

-- STREAMING_CHUNK:Constructing Piggybank Extraction Prompt UI...
local function CreateBankAura(currentBankSize)
	isBankBroken = false

	if promptGui then promptGui:Destroy() end

	local staticAura = workspace:FindFirstChild("PiggyBankAura", true)
	if staticAura then
		-- Fix: Verify the target is a BasePart so the tutorial camera math does not fail when targeting step 56.
		local targetPart = staticAura
		if not targetPart:IsA("BasePart") then
			targetPart = staticAura:FindFirstChildWhichIsA("BasePart", true) or staticAura
		end

		CollectionService:AddTag(targetPart, "PiggyBankAuraHolder")
		CollectionService:AddTag(targetPart, "Tutorial_GoldenBankHolder")
	end

	promptGui = Instance.new("ScreenGui")
	promptGui.Name = "PiggyBankPromptGui"
	promptGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	-- Fix: Lowered DisplayOrder so the tutorial highlights aren't obscured underneath the prompt layout.
	promptGui.DisplayOrder = 50 
	promptGui.Parent = playerGui

	local panel = Instance.new("ImageButton", promptGui)
	panel.Name = "PromptPanel"
	panel.Size = UDim2.new(0, 280, 0, 110)

	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 1.5, 0) 
	panel.BackgroundColor3 = T.cardBG
	panel.AutoButtonColor = false
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)

	local stroke = Instance.new("UIStroke", panel)
	stroke.Color = T.accentGold
	stroke.Thickness = 2

	local counterLabel = Instance.new("TextLabel", panel)
	counterLabel.Name = "CounterLabel"
	counterLabel.Size = UDim2.new(1, 0, 0, 35)
	counterLabel.Position = UDim2.new(0.5, 0, 0, -10)
	counterLabel.AnchorPoint = Vector2.new(0.5, 1)
	counterLabel.BackgroundTransparency = 1
	counterLabel.Text = NumberFormatter.Format(currentBankSize) .. " Auras"
	counterLabel.TextColor3 = T.accentGold
	counterLabel.Font = Enum.Font.FredokaOne
	counterLabel.TextScaled = true
	local cStroke = Instance.new("UIStroke", counterLabel)
	cStroke.Color = Color3.new(0, 0, 0)
	cStroke.Thickness = 2

	local title = Instance.new("TextLabel", panel)
	title.Name = "TitleLabel"
	title.Size = UDim2.new(1, 0, 0.4, 0)
	title.Position = UDim2.new(0, 0, 0, 12)
	title.BackgroundTransparency = 1
	title.Text = "BREAK THE BANK"
	title.TextColor3 = T.accentGold
	title.TextScaled = true
	title.Font = Enum.Font.FredokaOne

	local barBg = Instance.new("Frame", panel)
	barBg.Name = "BarBg"
	barBg.Size = UDim2.new(0.85, 0, 0, 24)
	barBg.Position = UDim2.new(0.075, 0, 0.65, 0)
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

	local promptTween = TweenService:Create(panel, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0.90, 0) 
	})
	promptTween:Play()

	-- Fix: Delay the application of the targetTag until the tween has finished so the tutorial captures the final on-screen coordinate.
	promptTween.Completed:Connect(function()
		CollectionService:AddTag(panel, "Tutorial_PiggyBankPrompt")
	end)

	pcall(function()
		UITheme.Apply(panel, "ShopCard")
		UITheme.ApplyShine(panel)
		UITheme.ApplyFlair(title, "Ghost")
	end)

	local function StopHold()
		if not isHolding then return end
		isHolding = false
		TweenService:Create(stroke, TweenInfo.new(0.2), {Thickness = 2}):Play()
		if holdSound then
			holdSound:Stop()
			holdSound:Destroy()
			holdSound = nil
		end

		TweenService:Create(panel, TweenInfo.new(0.15), {Rotation = 0}):Play()
	end

	-- STREAMING_CHUNK:Binding Break Interactions...
	panel.InputBegan:Connect(function(input)
		if isBankBroken then return end
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

-- STREAMING_CHUNK:Executing Render Heartbeat Loops...
RunService.Heartbeat:Connect(function(dt)
	if inSpecialArea then
		local clickBtn = mainHUD:FindFirstChild("ClickButton", true)
		local modeToggle = mainHUD:FindFirstChild("ModeToggle", true)
		local sendBtn = mainHUD:FindFirstChild("SendButton", true)
		local hatcheryBar = mainHUD:FindFirstChild("HatcheryBar", true)
		local travelBtn = mainHUD:FindFirstChild("AreaTravelButton", true) or mainHUD:FindFirstChild("AreaTravelBtn", true)
		local prestigeBtn = mainHUD:FindFirstChild("PrestigeButton", true)

		if clickBtn and clickBtn.Visible then clickBtn.Visible = false end
		if modeToggle and modeToggle.Visible then modeToggle.Visible = false end
		if sendBtn and sendBtn.Visible then sendBtn.Visible = false end
		if hatcheryBar and hatcheryBar.Visible then hatcheryBar.Visible = false end
		if travelBtn and travelBtn.Visible then travelBtn.Visible = false end
		if prestigeBtn and prestigeBtn.Visible then prestigeBtn.Visible = false end

		local targetTrigger = workspace:FindFirstChild("GoldenTrigger", true)
		local targetPos = targetTrigger and targetTrigger.Position

		if targetPos then
			for _, cube in ipairs(CollectionService:GetTagged("BankExplosionCube")) do
				if cube:GetAttribute("SuckToCenter") and cube.Parent and not cube.Anchored then
					local flatTarget = Vector3.new(targetPos.X, cube.Position.Y, targetPos.Z)
					if (flatTarget - cube.Position).Magnitude > 0.5 then
						local direction = (flatTarget - cube.Position).Unit
						cube.AssemblyLinearVelocity = Vector3.new(direction.X * 45, cube.AssemblyLinearVelocity.Y, direction.Z * 45)
					end
				end
			end
		end
	end

	if not inSpecialArea or not promptGui or isBankBroken then return end

	local panel = promptGui:FindFirstChild("PromptPanel")
	if not panel then return end
	local fillBar = panel:FindFirstChild("BarBg") and panel:FindFirstChild("BarBg"):FindFirstChild("Fill")

	if isHolding then
		local holdTime = BankConfig.HoldToBreakTime or 10
		fillProgress = math.clamp(fillProgress + (dt / holdTime), 0, 1)

		tiltSide = tiltSide * -1
		TweenService:Create(panel, TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true), { Rotation = 3 * tiltSide }):Play()

		if fillProgress >= 1.0 then
			isHolding = false
			fillProgress = 0
			TweenService:Create(panel, TweenInfo.new(0.15), {Rotation = 0}):Play()

			BankActionBridge:Fire({ action = "breakBank" })
			-- Fix: Pass "SystemAutoAdvance" to guarantee the tutorial advances correctly regardless of mouse movement.
			if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep("SystemAutoAdvance") end
		end
	else
		local drainRate = BankConfig.DrainRate or 2
		fillProgress = math.clamp(fillProgress - (dt / drainRate), 0, 1)
	end

	if fillBar then
		fillBar.Size = UDim2.new(fillProgress, 0, 1, 0)
	end
end)

-- STREAMING_CHUNK:Monitoring Area Transitions...
player:GetAttributeChangedSignal("InSpecialArea"):Connect(function()
	inSpecialArea = player:GetAttribute("InSpecialArea")

	local clickBtn = mainHUD:FindFirstChild("ClickButton", true)
	local modeToggle = mainHUD:FindFirstChild("ModeToggle", true)
	local sendBtn = mainHUD:FindFirstChild("SendButton", true)
	local hatcheryBar = mainHUD:FindFirstChild("HatcheryBar", true)
	local travelBtn = mainHUD:FindFirstChild("AreaTravelButton", true) or mainHUD:FindFirstChild("AreaTravelBtn", true) 
	local prestigeBtn = mainHUD:FindFirstChild("PrestigeButton", true) 

	if inSpecialArea then
		local bankSize = player:GetAttribute("LivePiggyBank") or 0
		CreateBankAura(bankSize)
		if travelBtn then travelBtn.Visible = false end 
		if prestigeBtn then prestigeBtn.Visible = false end 
	else
		if promptGui then
			promptGui:Destroy()
			promptGui = nil
		end

		if clickBtn then clickBtn.Visible = true end
		if modeToggle then modeToggle.Visible = true end
		if sendBtn then sendBtn.Visible = true end
		if hatcheryBar then hatcheryBar.Visible = true end
		if travelBtn then travelBtn.Visible = true end 
		if prestigeBtn then prestigeBtn.Visible = true end 
	end
end)



-- PortalController
-- Location: StarterPlayer > StarterPlayerScripts > PortalController

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local AreaRegistry = require(ReplicatedStorage.Modules.AreaRegistry)
local SoundConfig  = require(ReplicatedStorage.Modules.SoundConfig)
local C            = require(ReplicatedStorage.Modules.UIConfig)
local Formatter    = require(ReplicatedStorage.Modules.NumberFormatter) 
local UITheme      = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UITheme"))
local T            = UITheme.Get("Custom")

local AreaUpdated      = ReplicatedStorage.RemoteEvents:WaitForChild("AreaUpdated")
local AreaUnlocked     = ReplicatedStorage.RemoteEvents:WaitForChild("AreaUnlocked")
local EnterPortal      = ReplicatedStorage.RemoteEvents:WaitForChild("EnterPortal")
local TravelToArea     = ReplicatedStorage.RemoteEvents:WaitForChild("TravelToArea")
local AreaChanged      = ReplicatedStorage.RemoteEvents:WaitForChild("AreaChanged")
local PrestigeComplete = ReplicatedStorage.RemoteEvents:WaitForChild("PrestigeComplete")

-- BRIDGENET2 UPGRADE
local BridgeNet2      = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))
local UpdateHUDBridge = BridgeNet2.ClientBridge("UpdateHUD")

local ForceCloseUI = ReplicatedStorage:FindFirstChild("ForceCloseUI") or Instance.new("BindableEvent")
ForceCloseUI.Name = "ForceCloseUI"
ForceCloseUI.Parent = ReplicatedStorage

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainHUD   = playerGui:WaitForChild("MainHUD")

local PositionPart = workspace:WaitForChild("AuraHolder"):WaitForChild("Position")

local promptAdded   = false
local currentArea   = 1
local portalReady   = false
local panelOpen     = false
local browseIndex   = 1
local liveFarmEval  = 0
local unlockedAreas = { 1 }
local MAX_AREA      = AreaRegistry.GetMaxArea()

local PW = C.Panels.AreaTravelW
local PH = C.Panels.AreaTravelH
local PR = C.Panels.CornerRadius
local BW = C.Banners.AreaBannerW
local BY = C.Banners.AreaBannerY
local BR = C.Banners.CornerRadius

local function PlayUI(id)
	if shared.PlayUISound then shared.PlayUISound(id) end
end

local function IsUnlocked(idx)
	for _, v in ipairs(unlockedAreas) do if v == idx then return true end end
	return false
end

local AreaAssets = ReplicatedStorage:WaitForChild("AreaAssets")

-- FLIPBOOK ANIMATION SYSTEM
local flipbookConnection = nil
local currentFlipbook = nil
local flipbookFrame = 1
local flipbookTime = 0

local function StopFlipbook()
	if flipbookConnection then
		flipbookConnection:Disconnect()
		flipbookConnection = nil
	end
	currentFlipbook = nil
end

local function StartFlipbook(areaIdx, AreaIcon)
	StopFlipbook()

	local flipbookData = AreaRegistry.GetFlipbook(areaIdx)
	if not flipbookData then return end

	currentFlipbook = flipbookData
	flipbookFrame = 1
	flipbookTime = 0

	if not AreaIcon then return end

	AreaIcon.Image = flipbookData.image
	AreaIcon.ImageRectSize = Vector2.new(flipbookData.frameW, flipbookData.frameH)
	AreaIcon.ImageRectOffset = Vector2.new(0, 0)

	flipbookConnection = RunService.RenderStepped:Connect(function(dt)
		flipbookTime += dt
		local frameTime = 1 / flipbookData.fps

		if flipbookTime >= frameTime then
			flipbookTime = flipbookTime % frameTime
			flipbookFrame = flipbookFrame + 1

			if flipbookFrame > flipbookData.frames then
				flipbookFrame = 1
			end

			local col = (flipbookFrame - 1) % flipbookData.columns
			local row = math.floor((flipbookFrame - 1) / flipbookData.columns)
			local offsetX = col * flipbookData.frameW
			local offsetY = row * flipbookData.frameH

			AreaIcon.ImageRectOffset = Vector2.new(offsetX, offsetY)
		end
	end)
end

-- UI Setup (AreaPanel)
local AreaPanel = Instance.new("Frame")
AreaPanel.Name="AreaTravelPanel"; AreaPanel.Size = UDim2.new(0.88, 0, 0.82, 0)
AreaPanel.Position = UDim2.new(0.5, 0, 0.5, 0)
AreaPanel.AnchorPoint = Vector2.new(0.5, 0.5)
AreaPanel.BackgroundColor3=T.panelBG; AreaPanel.BorderSizePixel=0
AreaPanel.Visible=false; AreaPanel.ZIndex=30; AreaPanel.ClipsDescendants=true
AreaPanel.Parent=mainHUD
CollectionService:AddTag(AreaPanel, "Tutorial_TravelPanel") 
Instance.new("UICorner",AreaPanel).CornerRadius=UDim.new(0,PR)

local sizeConstraint = Instance.new("UISizeConstraint")
sizeConstraint.MaxSize = Vector2.new(PW, PH) 
sizeConstraint.Parent = AreaPanel

local panelStroke=Instance.new("UIStroke"); panelStroke.Color=T.panelStroke; panelStroke.Thickness=2; panelStroke.Parent=AreaPanel

local PortalContentScaler = Instance.new("Frame")
PortalContentScaler.Name = "ContentScaler"
PortalContentScaler.AnchorPoint = Vector2.new(0.5, 0)
PortalContentScaler.Position = UDim2.new(0.5, 0, 0, 0)
PortalContentScaler.BackgroundTransparency = 1
PortalContentScaler.Parent = AreaPanel

local portalContentScale = Instance.new("UIScale")
portalContentScale.Parent = PortalContentScaler

local PORTAL_DESIGN_WIDTH = 480

local function UpdatePortalScale()
	local realWidth = AreaPanel.AbsoluteSize.X
	if realWidth <= 0 then return end
	local scale = realWidth / PORTAL_DESIGN_WIDTH
	if scale > 1.05 then scale = 1.05 end
	portalContentScale.Scale = scale
	PortalContentScaler.Size = UDim2.new(0, PORTAL_DESIGN_WIDTH, 1 / scale, 0)
end

AreaPanel:GetPropertyChangedSignal("AbsoluteSize"):Connect(UpdatePortalScale)
UpdatePortalScale()

local HeaderBar=Instance.new("Frame"); HeaderBar.Size=UDim2.new(1,0,0,46); HeaderBar.BackgroundColor3=T.headerBG
HeaderBar.BorderSizePixel=0; HeaderBar.ZIndex=31; HeaderBar.Parent=PortalContentScaler
Instance.new("UICorner",HeaderBar).CornerRadius=UDim.new(0,PR)
local HeaderLabel=Instance.new("TextLabel"); HeaderLabel.Size=UDim2.new(1,-50,1,0); HeaderLabel.Position=UDim2.new(0,16,0,0)
HeaderLabel.BackgroundTransparency=1; HeaderLabel.Text="AREA TRAVEL"; HeaderLabel.TextColor3=T.headerText
HeaderLabel.TextScaled=true; HeaderLabel.Font=T.font; HeaderLabel.TextXAlignment=Enum.TextXAlignment.Left
HeaderLabel.ZIndex=32; HeaderLabel.Parent=HeaderBar
local CloseBtn=Instance.new("TextButton"); CloseBtn.Size=UDim2.new(0,32,0,32); CloseBtn.Position=UDim2.new(1,-40,0.5,-16)
CloseBtn.BackgroundColor3=T.buttonRed; CloseBtn.BorderSizePixel=0; CloseBtn.Text="X"; CloseBtn.TextColor3=T.bodyText
CloseBtn.TextScaled=true; CloseBtn.Font=T.font; CloseBtn.ZIndex=33; CloseBtn.Parent=HeaderBar
CollectionService:AddTag(CloseBtn, "Tutorial_TravelCloseBtn") 
Instance.new("UICorner",CloseBtn).CornerRadius=UDim.new(0,6)

local ScrollContainer = Instance.new("ScrollingFrame")
ScrollContainer.Name = "ScrollContainer"
ScrollContainer.Parent = AreaPanel -- kept OUTSIDE PortalContentScaler for correct mobile touch scrolling
ScrollContainer.BackgroundTransparency = 1
ScrollContainer.BorderSizePixel = 0
ScrollContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
ScrollContainer.AutomaticCanvasSize = Enum.AutomaticSize.None
ScrollContainer.ScrollBarThickness = 6

local function UpdatePortalScrollBounds()
	local scale = portalContentScale.Scale
	local scaledTop = 46 * scale
	ScrollContainer.Position = UDim2.new(0, 0, 0, scaledTop)
	ScrollContainer.Size     = UDim2.new(1, 0, 1, -scaledTop)
end

portalContentScale:GetPropertyChangedSignal("Scale"):Connect(UpdatePortalScrollBounds)
UpdatePortalScrollBounds()

local PortalCardsScaler = Instance.new("Frame")
PortalCardsScaler.Name = "CardsScaler"
PortalCardsScaler.BackgroundTransparency = 1
PortalCardsScaler.Parent = ScrollContainer

local portalCardsScale = Instance.new("UIScale")
portalCardsScale.Parent = PortalCardsScaler

local PORTAL_CARDS_DESIGN_WIDTH = 460

local function UpdatePortalCardsScale()
	local realWidth = ScrollContainer.AbsoluteSize.X
	local realHeight = ScrollContainer.AbsoluteSize.Y
	if realWidth <= 0 then return end
	local scale = realWidth / PORTAL_CARDS_DESIGN_WIDTH
	if scale > 1.05 then scale = 1.05 end
	portalCardsScale.Scale = scale
	PortalCardsScaler.Size = UDim2.new(0, PORTAL_CARDS_DESIGN_WIDTH, 0, realHeight / scale)
end

ScrollContainer:GetPropertyChangedSignal("AbsoluteSize"):Connect(UpdatePortalCardsScale)
UpdatePortalCardsScale()

local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 5) 
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center 
listLayout.Parent = PortalCardsScaler

local topPadding = Instance.new("UIPadding")
topPadding.PaddingTop = UDim.new(0, 5)
topPadding.PaddingBottom = UDim.new(0, 5)
topPadding.Parent = PortalCardsScaler

local GoalSection=Instance.new("Frame"); GoalSection.Size=UDim2.new(1,-24,0.28,0)
GoalSection.BackgroundColor3=T.cardBG; GoalSection.BorderSizePixel=0; GoalSection.ZIndex=31; GoalSection.Parent=PortalCardsScaler
Instance.new("UICorner",GoalSection).CornerRadius=UDim.new(0,8)

local FarmEvalTitle=Instance.new("TextLabel"); FarmEvalTitle.Size=UDim2.new(1,-24,0.2,0); FarmEvalTitle.Position=UDim2.new(0,12,0.06,0)
FarmEvalTitle.BackgroundTransparency=1; FarmEvalTitle.Text="FARM EVALUATION"; FarmEvalTitle.TextColor3=T.subText
FarmEvalTitle.TextScaled=true; FarmEvalTitle.Font=T.font; FarmEvalTitle.TextXAlignment=Enum.TextXAlignment.Left
FarmEvalTitle.ZIndex=32; FarmEvalTitle.Parent=GoalSection
local FarmEvalNumber=Instance.new("TextLabel"); FarmEvalNumber.Name="FarmEvalNumber"
FarmEvalNumber.Size=UDim2.new(1,-24,0.32,0); FarmEvalNumber.Position=UDim2.new(0,12,0.26,0)
FarmEvalNumber.BackgroundTransparency=1; FarmEvalNumber.Text="$0"; FarmEvalNumber.TextColor3=T.accentGreen
FarmEvalNumber.TextScaled=true; FarmEvalNumber.Font=T.font; FarmEvalNumber.TextXAlignment=Enum.TextXAlignment.Left
FarmEvalNumber.ZIndex=32; FarmEvalNumber.Parent=GoalSection
local ProgressBG=Instance.new("Frame"); ProgressBG.Size=UDim2.new(1,-24,0.16,0); ProgressBG.Position=UDim2.new(0,12,0.62,0)
ProgressBG.BackgroundColor3=Color3.fromRGB(40,50,70); ProgressBG.BorderSizePixel=0; ProgressBG.ZIndex=32; ProgressBG.Parent=GoalSection
Instance.new("UICorner",ProgressBG).CornerRadius=UDim.new(0,4)
local ProgressFill=Instance.new("Frame"); ProgressFill.Name="ProgressFill"; ProgressFill.Size=UDim2.new(0,0,1,0)
ProgressFill.BackgroundColor3=T.accentGreen; ProgressFill.BorderSizePixel=0; ProgressFill.ZIndex=33; ProgressFill.Parent=ProgressBG
Instance.new("UICorner",ProgressFill).CornerRadius=UDim.new(0,4)
local ProgressLabel=Instance.new("TextLabel"); ProgressLabel.Name="ProgressLabel"
ProgressLabel.Size=UDim2.new(1,-24,0.2,0); ProgressLabel.Position=UDim2.new(0,12,0.8,0)
ProgressLabel.BackgroundTransparency=1; ProgressLabel.Text=""; ProgressLabel.TextColor3=T.subText
ProgressLabel.TextScaled=true; ProgressLabel.Font=T.fontBody; ProgressLabel.TextXAlignment=Enum.TextXAlignment.Left
ProgressLabel.ZIndex=32; ProgressLabel.Parent=GoalSection

local AreaBrowser=Instance.new("Frame"); AreaBrowser.Size=UDim2.new(1,-24,0.68,0)
AreaBrowser.BackgroundColor3=T.cardBG; AreaBrowser.BorderSizePixel=0; AreaBrowser.ZIndex=31; AreaBrowser.Parent=PortalCardsScaler
Instance.new("UICorner",AreaBrowser).CornerRadius=UDim.new(0,8)
local BrowseAreaName=Instance.new("TextLabel"); BrowseAreaName.Size=UDim2.new(0.6, 0, 0.09, 0)
BrowseAreaName.AnchorPoint=Vector2.new(0.5, 0)
BrowseAreaName.Position=UDim2.new(0.5, 0, 0.03, 0)
BrowseAreaName.BackgroundTransparency=1; BrowseAreaName.Text="Starter Area"; BrowseAreaName.TextColor3=T.accentBlue
BrowseAreaName.TextScaled=true; BrowseAreaName.Font=T.font; BrowseAreaName.TextXAlignment=Enum.TextXAlignment.Center
BrowseAreaName.ZIndex=32; BrowseAreaName.Parent=AreaBrowser
local AreaIndexLabel=Instance.new("TextLabel"); AreaIndexLabel.Size=UDim2.new(0,60,0.07,0); AreaIndexLabel.Position=UDim2.new(1,-66,0.04,0)
AreaIndexLabel.BackgroundTransparency=1; AreaIndexLabel.Text="1/5"; AreaIndexLabel.TextColor3=T.subText
AreaIndexLabel.TextScaled=true; AreaIndexLabel.Font=T.fontBody; AreaIndexLabel.TextXAlignment=Enum.TextXAlignment.Right
AreaIndexLabel.ZIndex=32; AreaIndexLabel.Parent=AreaBrowser
local BrowseAreaMult=Instance.new("TextLabel"); BrowseAreaMult.Size=UDim2.new(1,-20,0.06,0); BrowseAreaMult.Position=UDim2.new(0,10,0.13,0)
BrowseAreaMult.BackgroundTransparency=1; BrowseAreaMult.Text="Cube Value: 1.0x base"; BrowseAreaMult.TextColor3=T.accentGold
BrowseAreaMult.TextScaled=true; BrowseAreaMult.Font=T.fontBody; BrowseAreaMult.TextXAlignment=Enum.TextXAlignment.Center
BrowseAreaMult.ZIndex=32; BrowseAreaMult.Parent=AreaBrowser
local LeftArrow=Instance.new("TextButton"); LeftArrow.Size=UDim2.new(0,36,0,36); LeftArrow.AnchorPoint=Vector2.new(0,0.5); LeftArrow.Position=UDim2.new(0,8,0.48,0)
LeftArrow.BackgroundColor3=T.headerBG; LeftArrow.BorderSizePixel=0; LeftArrow.Text="<"; LeftArrow.TextColor3=T.bodyText
LeftArrow.TextScaled=true; LeftArrow.Font=T.font; LeftArrow.ZIndex=33; LeftArrow.Parent=AreaBrowser
CollectionService:AddTag(LeftArrow, "Tutorial_LeftArrow") 
Instance.new("UICorner",LeftArrow).CornerRadius=UDim.new(0,18)
local RightArrow=Instance.new("TextButton"); RightArrow.Size=UDim2.new(0,36,0,36); RightArrow.AnchorPoint=Vector2.new(1,0.5); RightArrow.Position=UDim2.new(1,-8,0.48,0)
RightArrow.BackgroundColor3=T.headerBG; RightArrow.BorderSizePixel=0; RightArrow.Text=">"; RightArrow.TextColor3=T.bodyText
RightArrow.TextScaled=true; RightArrow.Font=T.font; RightArrow.ZIndex=33; RightArrow.Parent=AreaBrowser
CollectionService:AddTag(RightArrow, "Tutorial_RightArrow") 
Instance.new("UICorner",RightArrow).CornerRadius=UDim.new(0,18)
local AreaIcon = Instance.new("ImageLabel")
AreaIcon.Name = "AreaIcon" 
AreaIcon.AnchorPoint = Vector2.new(0.5, 0.48)
AreaIcon.Size = UDim2.new(0.4, 0, 0.4, 0)
AreaIcon.Position = UDim2.new(0.5, 0, 0.48, 0)
AreaIcon.BackgroundTransparency = 1
AreaIcon.BorderSizePixel = 0
AreaIcon.ScaleType = Enum.ScaleType.Fit
AreaIcon.ZIndex = 33
AreaIcon.Image = "" 
AreaIcon.Parent = AreaBrowser
local BrowseStatus=Instance.new("TextLabel"); BrowseStatus.Size=UDim2.new(1,-24,0.08,0); BrowseStatus.Position=UDim2.new(0,12,0.75,0)
BrowseStatus.BackgroundTransparency=1; BrowseStatus.Text="CURRENT AREA"; BrowseStatus.TextColor3=T.subText
BrowseStatus.TextScaled=true; BrowseStatus.Font=T.font; BrowseStatus.TextXAlignment=Enum.TextXAlignment.Center
BrowseStatus.ZIndex=32; BrowseStatus.Parent=AreaBrowser
local BrowseProgress=Instance.new("TextLabel"); BrowseProgress.Size=UDim2.new(1,-24,0.1,0); BrowseProgress.Position=UDim2.new(0,12,0.83,0)
BrowseProgress.BackgroundTransparency=1; BrowseProgress.Text=""; BrowseProgress.TextColor3=T.subText
BrowseProgress.TextScaled=true; BrowseProgress.Font=T.fontBody; BrowseProgress.TextWrapped=true
BrowseProgress.TextXAlignment=Enum.TextXAlignment.Center; BrowseProgress.ZIndex=32; BrowseProgress.Parent=AreaBrowser
local TravelBtn=Instance.new("TextButton"); TravelBtn.Size=UDim2.new(1,-24,0.14,0); TravelBtn.Position=UDim2.new(0,12,0.85,0)
TravelBtn.BackgroundColor3=T.buttonGreen; TravelBtn.BorderSizePixel=0; TravelBtn.Text="TRAVEL"; TravelBtn.TextColor3=T.bodyText
TravelBtn.TextScaled=true; TravelBtn.Font=T.font; TravelBtn.Visible=false; TravelBtn.ZIndex=33; TravelBtn.Parent=AreaBrowser
CollectionService:AddTag(TravelBtn, "Tutorial_TravelConfirm") 
Instance.new("UICorner",TravelBtn).CornerRadius=UDim.new(0,8)

local function UpdateGoalSection()
	FarmEvalNumber.Text = "$" .. Formatter.Format(liveFarmEval)
	local nextGoalArea, nextGoalThreshold = nil, nil
	for i = currentArea + 1, MAX_AREA do
		local area = AreaRegistry.Get(i)
		if area and liveFarmEval < (area.threshold or 0) then
			nextGoalArea = i; nextGoalThreshold = area.threshold; break
		end
	end
	if nextGoalThreshold and nextGoalThreshold > 0 then
		local pct = math.clamp(liveFarmEval / nextGoalThreshold, 0, 1)
		TweenService:Create(ProgressFill, TweenInfo.new(0.3), { Size = UDim2.new(pct,0,1,0) }):Play()
		ProgressFill.BackgroundColor3 = pct >= 1 and Color3.fromRGB(80,255,160) or T.accentGreen
		local needed = math.max(0, nextGoalThreshold - liveFarmEval)
		ProgressLabel.Text = needed <= 0
			and "New areas available! Browse below."
			or "$" .. Formatter.Format(needed) .. " to unlock " .. AreaRegistry.GetName(nextGoalArea)
		ProgressLabel.TextColor3 = needed <= 0 and T.accentTeal or T.subText
	elseif portalReady then
		ProgressFill.Size = UDim2.new(1,0,1,0); ProgressFill.BackgroundColor3 = T.accentTeal
		ProgressLabel.Text = "Areas available! Pick a destination."; ProgressLabel.TextColor3 = T.accentTeal
	elseif currentArea >= MAX_AREA then
		ProgressFill.Size = UDim2.new(1,0,1,0); ProgressFill.BackgroundColor3 = T.accentGold
		ProgressLabel.Text = "Maximum area reached."; ProgressLabel.TextColor3 = T.accentGold
	end
end

local function RefreshBrowser()
	local idx = browseIndex
	local areaData = AreaRegistry.Get(idx)	
	if not areaData then return end
	AreaIndexLabel.Text = idx .. " / " .. MAX_AREA

	LeftArrow.Visible  = idx > 1
	RightArrow.Visible = (idx < MAX_AREA) and (AreaRegistry.Get(idx+1) ~= nil)

	local highestUnlocked = 1
	for _, v in ipairs(unlockedAreas) do
		if v > highestUnlocked then highestUnlocked = v end
	end
	if highestUnlocked > MAX_AREA then highestUnlocked = MAX_AREA end

	local unlockReq = areaData.threshold or 0
	local discReq = areaData.discoveryThreshold or (unlockReq * 0.25) 

	if idx <= highestUnlocked then
		local flipbookData = AreaRegistry.GetFlipbook(idx)
		if flipbookData then
			StartFlipbook(idx, AreaIcon)
			AreaIcon.ImageColor3 = Color3.fromRGB(255, 255, 255)
		else
			StopFlipbook()
			AreaIcon.Image = areaData.icon or areaData.auraPreviewImage or ""
			AreaIcon.ImageRectSize = Vector2.new(0, 0)
			AreaIcon.ImageRectOffset = Vector2.new(0, 0)
			AreaIcon.ImageColor3 = Color3.fromRGB(255, 255, 255)
		end
		BrowseAreaName.Text = AreaRegistry.GetName(idx)
		BrowseAreaMult.Text = "Cube Value: " .. string.format("%.1f", AreaRegistry.GetMultiplier(idx)) .. "x base"

		if idx == currentArea then
			BrowseStatus.Text = "CURRENT AREA"; BrowseStatus.TextColor3 = T.accentGreen
			BrowseProgress.Text = "This is your active farm."
			BrowseProgress.TextColor3 = T.accentTeal
			TravelBtn.Visible = false
		else
			BrowseStatus.Text = "PREVIOUS AREA"; BrowseStatus.TextColor3 = T.accentGreen
			BrowseProgress.Text = "Travel back for free (no reset)."
			BrowseProgress.TextColor3 = T.accentGreen
			TravelBtn.Visible = true; TravelBtn.Text = "Travel"
			TravelBtn.BackgroundColor3 = Color3.fromRGB(60,100,60)
		end

	elseif idx == highestUnlocked + 1 then
		if liveFarmEval >= unlockReq then
			local flipbookData = AreaRegistry.GetFlipbook(idx)
			if flipbookData then
				StartFlipbook(idx, AreaIcon)
				AreaIcon.ImageColor3 = Color3.fromRGB(255, 255, 255)
			else
				StopFlipbook()
				AreaIcon.Image = areaData.icon or areaData.auraPreviewImage or ""
				AreaIcon.ImageRectSize = Vector2.new(0, 0)
				AreaIcon.ImageRectOffset = Vector2.new(0, 0)
				AreaIcon.ImageColor3 = Color3.fromRGB(255, 255, 255)
			end
			BrowseAreaName.Text = AreaRegistry.GetName(idx)
			BrowseAreaMult.Text = "Cube Value: " .. string.format("%.1f", AreaRegistry.GetMultiplier(idx)) .. "x base"
			BrowseStatus.Text = "UNLOCKED"; BrowseStatus.TextColor3 = T.accentTeal
			BrowseProgress.Text = "Travel here (resets current run)."
			BrowseProgress.TextColor3 = T.accentTeal
			TravelBtn.Visible = true; TravelBtn.Text = "TRAVEL"
			TravelBtn.BackgroundColor3 = T.buttonGreen

		elseif liveFarmEval >= discReq then
			local flipbookData = AreaRegistry.GetFlipbook(idx)
			if flipbookData then
				StartFlipbook(idx, AreaIcon)
				AreaIcon.ImageColor3 = Color3.fromRGB(180, 180, 180)
			else
				StopFlipbook()
				AreaIcon.Image = areaData.icon or areaData.auraPreviewImage or ""
				AreaIcon.ImageRectSize = Vector2.new(0, 0)
				AreaIcon.ImageRectOffset = Vector2.new(0, 0)
				AreaIcon.ImageColor3 = Color3.fromRGB(180, 180, 180)
			end
			BrowseAreaName.Text = AreaRegistry.GetName(idx)
			BrowseAreaMult.Text = "Cube Value: " .. string.format("%.1f", AreaRegistry.GetMultiplier(idx)) .. "x base"
			BrowseStatus.Text = "DISCOVERED"; BrowseStatus.TextColor3 = T.accentPurple

			local needed = math.max(0, unlockReq - liveFarmEval)
			BrowseProgress.Text = "Requires $"..Formatter.Format(unlockReq).." Farm Eval\n$"..Formatter.Format(needed).." remaining"
			BrowseProgress.TextColor3 = T.subText
			TravelBtn.Visible = false

		else
			StopFlipbook()
			AreaIcon.Image = areaData.icon or areaData.auraPreviewImage or ""
			AreaIcon.ImageRectSize = Vector2.new(0, 0)
			AreaIcon.ImageRectOffset = Vector2.new(0, 0)
			AreaIcon.ImageColor3 = Color3.fromRGB(0, 0, 0) 
			BrowseAreaName.Text = "???"
			BrowseAreaMult.Text = "???x base"
			BrowseStatus.Text = "UNDISCOVERED"; BrowseStatus.TextColor3 = T.subText

			local needed = math.max(0, discReq - liveFarmEval)
			BrowseProgress.Text = "Keep growing to discover what's next.\n$"..Formatter.Format(needed).." to Discover"
			BrowseProgress.TextColor3 = T.subText
			TravelBtn.Visible = false
		end

	else
		StopFlipbook()
		AreaIcon.Image = areaData.icon or areaData.auraPreviewImage or ""
		AreaIcon.ImageRectSize = Vector2.new(0, 0)
		AreaIcon.ImageRectOffset = Vector2.new(0, 0)
		AreaIcon.ImageColor3 = Color3.fromRGB(0, 0, 0)
		BrowseAreaName.Text = "???"
		BrowseAreaMult.Text = "???x base"
		BrowseStatus.Text = "LOCKED"; BrowseStatus.TextColor3 = T.subText
		BrowseProgress.Text = "Unlock previous areas first."
		BrowseProgress.TextColor3 = T.subText
		TravelBtn.Visible = false
	end
end

local travelDebounce = false
TravelBtn.MouseButton1Down:Connect(function()
	if travelDebounce then return end

	if type(shared.TutorialCanPerform) == "function" then
		local canConfirm = shared.TutorialCanPerform("Action_TravelConfirm")
		if not canConfirm then canConfirm = shared.TutorialCanPerform("Action_TravelArea") end
		if not canConfirm then return end
	end

	if browseIndex == currentArea then return end

	travelDebounce = true
	task.delay(0.25, function() travelDebounce = false end)

	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end

	local targetIndex = tonumber(browseIndex)
	if targetIndex then
		TravelToArea:FireServer(targetIndex)
	end
end)

local arrowDebounce = false

LeftArrow.MouseButton1Down:Connect(function()
	if arrowDebounce then return end
	if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_BrowseArea") then return end

	if browseIndex > 1 then 
		arrowDebounce = true
		task.delay(0.15, function() arrowDebounce = false end)

		if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
		browseIndex -= 1; PlayUI(SoundConfig.UIArrow); RefreshBrowser() 
	end
end)

RightArrow.MouseButton1Down:Connect(function()
	if arrowDebounce then return end
	if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_BrowseArea") then return end

	if browseIndex < MAX_AREA and AreaRegistry.Get(browseIndex+1) then 
		arrowDebounce = true
		task.delay(0.15, function() arrowDebounce = false end)

		if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
		browseIndex += 1; PlayUI(SoundConfig.UIArrow); RefreshBrowser() 
	end
end)

local function AddButtonJuice(btn)
	local scale = btn:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = btn
	end

	-- Safely capture original scale from Studio, avoiding zero-scale intro tweens.
	local baseScale = btn:GetAttribute("BaseScale")
	if not baseScale then
		baseScale = scale.Scale
		if baseScale < 0.05 then baseScale = 1 end
		btn:SetAttribute("BaseScale", baseScale)
	end

	local activeTween = nil
	local function TweenTo(targetScale, duration)
		if activeTween then activeTween:Cancel() end
		-- Sine easing strictly prevents mathematically overshooting the visual scale limit 
		activeTween = TweenService:Create(scale, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {Scale = targetScale})
		activeTween:Play()
	end

	local isPressed = false
	local isHovered = false

	btn.MouseEnter:Connect(function()
		isHovered = true
		if not isPressed then
			TweenTo(baseScale * 1.05, 0.15)
		end
	end)

	btn.MouseLeave:Connect(function()
		isHovered = false
		isPressed = false
		TweenTo(baseScale, 0.2)
	end)

	btn.MouseButton1Down:Connect(function()
		isPressed = true
		TweenTo(baseScale * 0.9, 0.1)
	end)

	btn.MouseButton1Up:Connect(function()
		if not isPressed then return end
		isPressed = false
		TweenTo(isHovered and (baseScale * 1.05) or baseScale, 0.2)
	end)
end

local AreaTravelBtn = mainHUD:WaitForChild("AreaButton")
AreaTravelBtn.BackgroundColor3 = T.headerBG
AreaTravelBtn.BorderSizePixel = 0
AreaTravelBtn.AutoButtonColor = false
AreaTravelBtn.ZIndex = 10

CollectionService:AddTag(AreaTravelBtn, "Tutorial_TravelButton")
if not AreaTravelBtn:FindFirstChildOfClass("UICorner") then
	Instance.new("UICorner", AreaTravelBtn).CornerRadius = UDim.new(0.3, 0)
end

local travelBtnStroke = AreaTravelBtn:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke", AreaTravelBtn)
travelBtnStroke.Color = Color3.fromRGB(100, 180, 255)
travelBtnStroke.Thickness = 2

local AreaTravelBtnIcon = AreaTravelBtn:FindFirstChild("Icon") or Instance.new("ImageLabel", AreaTravelBtn)
AreaTravelBtnIcon.Name = "Icon"
AreaTravelBtnIcon.Size = UDim2.new(0.8, 0, 0.8, 0)
AreaTravelBtnIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
AreaTravelBtnIcon.AnchorPoint = Vector2.new(0.5, 0.5)
AreaTravelBtnIcon.BackgroundTransparency = 1
AreaTravelBtnIcon.ScaleType = Enum.ScaleType.Fit
AreaTravelBtnIcon.Image = "rbxassetid://14916846070" 
AreaTravelBtnIcon.ZIndex = 11

if not AreaTravelBtnIcon:FindFirstChildOfClass("UIAspectRatioConstraint") then
	local iconAspect = Instance.new("UIAspectRatioConstraint", AreaTravelBtnIcon)
	iconAspect.AspectRatio = 1.0
end

AddButtonJuice(LeftArrow)
AddButtonJuice(RightArrow)
AddButtonJuice(TravelBtn)
AddButtonJuice(CloseBtn)
AddButtonJuice(AreaTravelBtn)

local function UpdateTravelButtonVisual()
	local canTravel = (#unlockedAreas > 1) or portalReady
	if canTravel then
		TweenService:Create(AreaTravelBtn, TweenInfo.new(0.3), { BackgroundColor3 = Color3.fromRGB(40, 130, 210) }):Play()
		TweenService:Create(travelBtnStroke, TweenInfo.new(0.3), { Color = Color3.fromRGB(150, 220, 255) }):Play()
	else
		TweenService:Create(AreaTravelBtn, TweenInfo.new(0.3), { BackgroundColor3 = Color3.fromRGB(50, 55, 70) }):Play()
		TweenService:Create(travelBtnStroke, TweenInfo.new(0.3), { Color = Color3.fromRGB(100, 180, 255) }):Play()
	end
end

local function OpenPanel()
	ForceCloseUI:Fire("AreaTravelPanel")
	panelOpen=true; browseIndex=currentArea; UpdateGoalSection(); RefreshBrowser()
	AreaPanel.Visible=true
	AreaPanel.Size=UDim2.new(0.88, 0, 0, 0)
	TweenService:Create(AreaPanel, TweenInfo.new(0.35,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
		{ Size=UDim2.new(0.88, 0, 0.82, 0) }):Play()
	UITheme.SetMenuVisible(true)
end

local function ClosePanel()
	panelOpen=false; StopFlipbook(); PlayUI(SoundConfig.UIClose)
	TweenService:Create(AreaPanel, TweenInfo.new(0.25,Enum.EasingStyle.Quad,Enum.EasingDirection.In),
		{ Size=UDim2.new(0.88, 0, 0, 0) }):Play()
	UITheme.SetMenuVisible(false)
	task.delay(0.3, function() AreaPanel.Visible=false end)
end

local panelDebounce = false

AreaTravelBtn.MouseButton1Down:Connect(function()
	if panelDebounce then return end
	panelDebounce = true
	task.delay(0.25, function() panelDebounce = false end)

	if panelOpen then
		if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_CloseTravel") then return end
		if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
		ClosePanel()
	else
		if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_OpenTravel") then return end
		if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
		OpenPanel()
	end
end)

CloseBtn.MouseButton1Down:Connect(function()
	if panelDebounce then return end
	panelDebounce = true
	task.delay(0.25, function() panelDebounce = false end)

	if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_CloseTravel") then return end

	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
	ClosePanel()
end)

local function ShowAreaBanner(info)
	if type(info.newArea) ~= "number" then return end

	if info.travelType == "backward" then return end
	local areaIndex = info.newArea or 2
	local areaData = AreaRegistry.Get(areaIndex)
	local areaName = info.areaName or AreaRegistry.GetName(areaIndex)
	local multText = "Cube Value: "..string.format("%.1f", info.areaMultiplier or 1.0).."x"
	local saText = (info.newSoulAuras and info.newSoulAuras > 0)
		and ("+"..Formatter.Format(info.newSoulAuras).." Soul Auras") or nil
	local accentColor = (areaData and areaData.auraHolderGlow) or T.accentTeal
	local bannerH = saText and 82 or 64
	local banner=Instance.new("Frame"); banner.Size=UDim2.new(0,BW,0,bannerH)
	banner.Position=UDim2.new(0,-(BW+10),0,BY); banner.BackgroundColor3=T.panelBG; banner.BorderSizePixel=0
	banner.ZIndex=55; banner.ClipsDescendants=true; banner.Parent=mainHUD
	Instance.new("UICorner",banner).CornerRadius=UDim.new(0,BR)
	local bs=Instance.new("UIStroke"); bs.Color=accentColor; bs.Thickness=1.5; bs.Parent=banner
	local nameLabel=Instance.new("TextLabel"); nameLabel.Size=UDim2.new(1,-12,0,22); nameLabel.Position=UDim2.new(0,10,0,6)
	nameLabel.BackgroundTransparency=1; nameLabel.Text=areaName; nameLabel.TextColor3=accentColor
	nameLabel.TextScaled=true; nameLabel.Font=T.font; nameLabel.TextXAlignment=Enum.TextXAlignment.Left
	nameLabel.ZIndex=56; nameLabel.Parent=banner
	local multLabel=Instance.new("TextLabel"); multLabel.Size=UDim2.new(1,-12,0,18); multLabel.Position=UDim2.new(0,10,0,30)
	multLabel.BackgroundTransparency=1; multLabel.Text=multText; multLabel.TextColor3=T.accentGold
	multLabel.TextScaled=true; multLabel.Font=T.fontBody; multLabel.TextXAlignment=Enum.TextXAlignment.Left
	multLabel.ZIndex=56; multLabel.Parent=banner
	if saText then
		local saLabel=Instance.new("TextLabel"); saLabel.Size=UDim2.new(1,-12,0,16); saLabel.Position=UDim2.new(0,10,0,52)
		saLabel.BackgroundTransparency=1; saLabel.Text=saText; saLabel.TextColor3=T.accentPurple
		saLabel.TextScaled=true; saLabel.Font=T.fontBody; saLabel.TextXAlignment=Enum.TextXAlignment.Left
		saLabel.ZIndex=56; saLabel.Parent=banner
	end
	TweenService:Create(banner, TweenInfo.new(0.4,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
		{ Position=UDim2.new(0,10,0,BY) }):Play()
	task.delay(4, function()
		TweenService:Create(banner, TweenInfo.new(0.35,Enum.EasingStyle.Quad,Enum.EasingDirection.In),
			{ Position=UDim2.new(0,-(BW+10),0,BY) }):Play()
		task.delay(0.4, function() if banner and banner.Parent then banner:Destroy() end end)
	end)
end

UpdateHUDBridge:Connect(function(stats)
	if stats.farmEvaluation ~= nil then liveFarmEval = stats.farmEvaluation end
	if panelOpen then UpdateGoalSection(); RefreshBrowser() end
end)

AreaUpdated.OnClientEvent:Connect(function(info)
	if type(info.currentArea) == "number" then
		currentArea = info.currentArea
	end

	if currentArea > 1 then player:SetAttribute("TutorialCompleted", true) end
	portalReady = info.portalReady == true
	if info.unlockedAreas then unlockedAreas = info.unlockedAreas end

	MAX_AREA = info.maxArea or AreaRegistry.GetMaxArea()
	if type(browseIndex) == "number" and type(MAX_AREA) == "number" then
		if browseIndex > MAX_AREA then browseIndex = MAX_AREA end
	end

	if info.portalReady then AddPortalPrompt() else RemovePortalPrompt() end

	UpdateTravelButtonVisual()

	if panelOpen then UpdateGoalSection(); RefreshBrowser() end
end)

AreaUnlocked.OnClientEvent:Connect(function(info)
	portalReady = true; AddPortalPrompt()
	if info.unlockedAreas then unlockedAreas = info.unlockedAreas end

	UpdateTravelButtonVisual()

	local count = info.newAreasCount or 1
	local highestName = info.highestNewName or "New Area"
	local PBW = C.Banners.PortalBannerW; local PBH = C.Banners.PortalBannerH
	local banner=Instance.new("Frame"); banner.Size=UDim2.new(0,PBW,0,PBH)
	banner.Position=UDim2.new(0.5,-PBW/2,0,-PBH-10); banner.BackgroundColor3=T.panelBG; banner.BorderSizePixel=0
	banner.ZIndex=60; banner.Parent=mainHUD
	Instance.new("UICorner",banner).CornerRadius=UDim.new(0,BR)
	local bStroke=Instance.new("UIStroke"); bStroke.Color=T.accentTeal; bStroke.Thickness=2; bStroke.Parent=banner
	local bLabel=Instance.new("TextLabel"); bLabel.Size=UDim2.new(1,-20,1,0); bLabel.Position=UDim2.new(0,10,0,0)
	bLabel.BackgroundTransparency=1
	bLabel.Text = count == 1
		and (highestName.." unlocked! Open Area Travel.")
		or (count.." new areas unlocked! Open Area Travel to choose.")
	bLabel.TextColor3=T.accentTeal; bLabel.TextScaled=true; bLabel.Font=T.font; bLabel.ZIndex=61; bLabel.Parent=banner
	TweenService:Create(banner, TweenInfo.new(0.4,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
		{ Position=UDim2.new(0.5,-PBW/2,0,14) }):Play()
	task.delay(5, function()
		TweenService:Create(banner, TweenInfo.new(0.35,Enum.EasingStyle.Quad,Enum.EasingDirection.In),
			{ Position=UDim2.new(0.5,-PBW/2,0,-PBH-10) }):Play()
		task.delay(0.4, function() if banner and banner.Parent then banner:Destroy() end end)
	end)
end)

PrestigeComplete.OnClientEvent:Connect(function(info)
	if info.isPortalEntry then
		portalReady=false; liveFarmEval=0; RemovePortalPrompt()
		UpdateTravelButtonVisual() 
		if panelOpen then ClosePanel() end
	end
end)

AreaChanged.OnClientEvent:Connect(function(info)
	if type(info.newArea) == "number" then
		currentArea = info.newArea 
		browseIndex = currentArea
	end

	portalReady = false
	if info.unlockedAreas then unlockedAreas = info.unlockedAreas end
	UpdateTravelButtonVisual()
	if panelOpen then ClosePanel() end
	ShowAreaBanner(info)
end)

function AddPortalPrompt()
	if promptAdded then return end; promptAdded = true
	local prompt=Instance.new("ProximityPrompt"); prompt.Name="PortalPrompt"; prompt.ObjectText="Portal"
	prompt.ActionText="Open Area Travel"; prompt.HoldDuration=0.5; prompt.MaxActivationDistance=12
	prompt.Parent=PositionPart
	prompt.Triggered:Connect(function(p) 
		if p == player and not panelOpen then 
			if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_OpenTravel") then return end

			if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
			OpenPanel() 
		end 
	end)
end

function RemovePortalPrompt()
	promptAdded=false; local e=PositionPart:FindFirstChild("PortalPrompt"); if e then e:Destroy() end
end

local function RefreshLook()
	UITheme.Apply(AreaPanel, "Panel")
	UITheme.Apply(HeaderBar, "TitleBar")
	UITheme.Apply(GoalSection, "ShopCard")
	UITheme.Apply(AreaBrowser, "ShopCard")
	UITheme.Apply(HeaderBar, "Panel")
	UITheme.Apply(RightArrow, "Panel")
	UITheme.Apply(LeftArrow, "Panel")
	UITheme.Apply(AreaTravelBtn, "Panel")
	UITheme.ApplyShine(AreaBrowser)
	UITheme.ApplyShine(GoalSection)
	UITheme.ApplyShine(AreaPanel)
	GoalSection.BackgroundColor3 = T.cardBG 
	AreaBrowser.BackgroundColor3 = T.cardBG
	local outerStroke = AreaPanel:FindFirstChildWhichIsA("UIStroke")
	if outerStroke then outerStroke.Color = Color3.fromRGB(255, 255, 255) end
end

task.wait(2)
RefreshLook()

ForceCloseUI.Event:Connect(function(exceptionPanel)
	if exceptionPanel ~= "AreaTravelPanel" and panelOpen then ClosePanel() end
end)

-- PrestigeController
-- Location: StarterPlayer > StarterPlayerScripts > PrestigeController

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local AdminConfig       = require(ReplicatedStorage.Modules.AdminConfig)
local PrestigeModule    = require(ReplicatedStorage.Modules.PrestigeModule)
local UITheme           = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UITheme"))
local T                 = UITheme.Get("Custom")
local C                 = require(ReplicatedStorage.Modules.UIConfig)
local Formatter         = require(ReplicatedStorage.Modules.NumberFormatter)
local PoolManager = require(ReplicatedStorage.Modules:WaitForChild("PoolManager"))

-- BRIDGENET2 UPGRADE
local BridgeNet2        = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))
local UpdateHUDBridge   = BridgeNet2.ClientBridge("UpdateHUD")

local ForceCloseUI = ReplicatedStorage:FindFirstChild("ForceCloseUI") or Instance.new("BindableEvent")
ForceCloseUI.Name = "ForceCloseUI"
ForceCloseUI.Parent = ReplicatedStorage

local EXPONENT     = PrestigeModule.EXPONENT
local COEFFICIENT  = PrestigeModule.COEFFICIENT
local BONUS_PER_SA = PrestigeModule.BONUS_PER_SA

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainHUD   = playerGui:WaitForChild("MainHUD")

local RequestPrestige  = ReplicatedStorage.RemoteEvents:WaitForChild("RequestPrestige")
local PrestigeComplete = ReplicatedStorage.RemoteEvents:WaitForChild("PrestigeComplete")
local PreviewPrestige  = ReplicatedStorage.RemoteEvents:WaitForChild("PreviewPrestige")
local AreaChanged      = ReplicatedStorage.RemoteEvents:WaitForChild("AreaChanged")

local PrestigeReady = Instance.new("BindableEvent")
PrestigeReady.Name   = "PrestigeReady"
PrestigeReady.Parent = ReplicatedStorage

local dialogOpen        = false
local dialogCanPrestige = false
local previewPending    = false

local serverTotalEarned    = 0
local displayedTotalEarned = 0
local ratePerSecond        = 0
local serverSoulAuras      = 0
local displayedRunSA       = 0
local barHighWaterMark     = 0
local hasPrestigedThisArea = false

local PRESTIGE_COLOR_ACTIVE   = Color3.fromRGB(120, 50,  160)
local PRESTIGE_COLOR_DISABLED = Color3.fromRGB(60,  55,  70)
local PRESTIGE_COLOR_PENDING  = Color3.fromRGB(80,  40,  110)
local PRESTIGE_COLOR_USED     = Color3.fromRGB(80,  60,  50)

local function CalcSoulAurasLocal(totalEarned)
	if totalEarned <= 0 then return 0 end
	return math.floor((totalEarned ^ EXPONENT) * COEFFICIENT)
end	
local function GetThreshold(n)
	if n <= 0 then return 0 end
	return (n / COEFFICIENT) ^ (1 / EXPONENT)
end
local function PlayUI(id) if shared.PlayUISound then shared.PlayUISound(id) end end

local function GetButtonColor()
	if hasPrestigedThisArea then return PRESTIGE_COLOR_USED end
	if CalcSoulAurasLocal(serverTotalEarned) > 0 then return PRESTIGE_COLOR_ACTIVE end
	return PRESTIGE_COLOR_DISABLED
end
local function GetButtonText()
	if hasPrestigedThisArea then return "Used" end
	return "Prestige"
end

---------------------------------------------------------------
-- Soul Aura display
---------------------------------------------------------------
local SADisplay = mainHUD:WaitForChild("PrestigeBarUI")
SADisplay.BackgroundTransparency = 1
SADisplay.ZIndex = 5

local SACountLabel = SADisplay:FindFirstChild("SACountLabel") or Instance.new("TextLabel")
SACountLabel.Name = "SACountLabel"
SACountLabel.Size = UDim2.new(1,0,0,28)
SACountLabel.Position = UDim2.new(0,0,0,0)
SACountLabel.BackgroundTransparency = 1; SACountLabel.Text = "0 Soul Auras"
SACountLabel.TextColor3 = Color3.fromRGB(200,160,255); SACountLabel.TextScaled = true
SACountLabel.Font = T.font; SACountLabel.TextXAlignment = Enum.TextXAlignment.Center
SACountLabel.ZIndex = 6; SACountLabel.Parent = SADisplay

local BarBG = SADisplay:FindFirstChild("BarBG") or Instance.new("Frame")
BarBG.Name = "BarBG"
BarBG.Size = UDim2.new(1,0,0,12)
BarBG.Position = UDim2.new(0,0,0,32)
BarBG.BackgroundColor3 = Color3.fromRGB(60,30,80); BarBG.BorderSizePixel = 0
BarBG.ZIndex = 6; BarBG.Parent = SADisplay
if not BarBG:FindFirstChildOfClass("UICorner") then
	Instance.new("UICorner", BarBG).CornerRadius = UDim.new(0,5)
end

local BarFill = BarBG:FindFirstChild("BarFill") or Instance.new("Frame")
BarFill.Name = "BarFill"
BarFill.Size = UDim2.new(0,0,1,0)
BarFill.BackgroundColor3 = Color3.fromRGB(255,255,255); BarFill.BorderSizePixel = 0
BarFill.ZIndex = 7; BarFill.Parent = BarBG
if not BarFill:FindFirstChildOfClass("UICorner") then
	Instance.new("UICorner", BarFill).CornerRadius = UDim.new(0,5)
end

local RunSALabel = SADisplay:FindFirstChild("RunSALabel") or Instance.new("TextLabel")
RunSALabel.Name = "RunSALabel"
RunSALabel.Size = UDim2.new(1,0,0,18)
RunSALabel.Position = UDim2.new(0,0,0,48)
RunSALabel.BackgroundTransparency = 1; RunSALabel.Text = "earning..."
RunSALabel.TextColor3 = Color3.fromRGB(160,140,180); RunSALabel.TextScaled = true
RunSALabel.Font = T.fontBody; RunSALabel.TextXAlignment = Enum.TextXAlignment.Left
RunSALabel.ZIndex = 6; RunSALabel.Parent = SADisplay

local MultDisplayLabel = SADisplay:FindFirstChild("MultDisplayLabel") or Instance.new("TextLabel")
MultDisplayLabel.Name = "MultDisplayLabel"
MultDisplayLabel.Size = UDim2.new(1,0,0,18)
MultDisplayLabel.Position = UDim2.new(0,0,0,68)
MultDisplayLabel.BackgroundTransparency = 1; MultDisplayLabel.Text = "+0% earnings bonus"
MultDisplayLabel.TextColor3 = Color3.fromRGB(140,120,170); MultDisplayLabel.TextScaled = true
MultDisplayLabel.Font = T.fontBody; MultDisplayLabel.TextXAlignment = Enum.TextXAlignment.Left
MultDisplayLabel.ZIndex = 6; MultDisplayLabel.Parent = SADisplay

---------------------------------------------------------------
-- Prestige button
---------------------------------------------------------------
local PrestigeButton = mainHUD:WaitForChild("PrestigeButton")
PrestigeButton.BackgroundColor3 = PRESTIGE_COLOR_DISABLED
PrestigeButton.BorderSizePixel = 0
PrestigeButton.AutoButtonColor = false
PrestigeButton.ZIndex = 5

CollectionService:AddTag(PrestigeButton, "Tutorial_PrestigeButton")
if not PrestigeButton:FindFirstChildOfClass("UICorner") then
	Instance.new("UICorner", PrestigeButton).CornerRadius = UDim.new(0.3, 0)
end

local prestigeBtnStroke = PrestigeButton:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke", PrestigeButton)
prestigeBtnStroke.Color = Color3.fromRGB(200, 140, 255)
prestigeBtnStroke.Thickness = 2

local PrestigeButtonIcon = PrestigeButton:FindFirstChild("Icon") or Instance.new("ImageLabel", PrestigeButton)
PrestigeButtonIcon.Name = "Icon"
PrestigeButtonIcon.Size = UDim2.new(0.8, 0, 0.8, 0)
PrestigeButtonIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
PrestigeButtonIcon.AnchorPoint = Vector2.new(0.5, 0.5)
PrestigeButtonIcon.BackgroundTransparency = 1
PrestigeButtonIcon.ScaleType = Enum.ScaleType.Fit
PrestigeButtonIcon.Image = "rbxassetid://14916846070" 
PrestigeButtonIcon.ZIndex = 6

if not PrestigeButtonIcon:FindFirstChildOfClass("UIAspectRatioConstraint") then
	local iconAspect = Instance.new("UIAspectRatioConstraint", PrestigeButtonIcon)
	iconAspect.AspectRatio = 1.0
end

---------------------------------------------------------------
-- Prestige dialog
---------------------------------------------------------------
local D=C.Dialog; local DW=D.W; local DH=D.H; local DHH=D.HeaderH; local GAP=D.LabelGap

local Dialog = Instance.new("Frame")
Dialog.Name="PrestigeDialog"
Dialog.Size=UDim2.new(0.88, 0, 0.72, 0)
Dialog.AnchorPoint=Vector2.new(0.5, 0.5)
Dialog.Position=UDim2.new(0.5, 0, 0.5, 0)
Dialog.BackgroundColor3=Color3.fromRGB(25,20,35); Dialog.BorderSizePixel=0
Dialog.Visible=false; Dialog.ZIndex=20; Dialog.Parent=mainHUD
Dialog.ClipsDescendants = true 
CollectionService:AddTag(Dialog, "Tutorial_PrestigePanel") 
Instance.new("UICorner",Dialog).CornerRadius=UDim.new(0,D.CornerRadius)
local dialogConstraint=Instance.new("UISizeConstraint"); dialogConstraint.MaxSize=Vector2.new(DW,DH); dialogConstraint.Parent=Dialog

local dialogStroke=Instance.new("UIStroke"); dialogStroke.Color=Color3.fromRGB(140,70,200); dialogStroke.Thickness=2; dialogStroke.Parent=Dialog

local DialogContentScaler = Instance.new("Frame")
DialogContentScaler.Name = "ContentScaler"
DialogContentScaler.AnchorPoint = Vector2.new(0.5, 0)
DialogContentScaler.Position = UDim2.new(0.5, 0, 0, 0)
DialogContentScaler.BackgroundTransparency = 1
DialogContentScaler.Parent = Dialog

local dialogContentScale = Instance.new("UIScale")
dialogContentScale.Parent = DialogContentScaler

local DIALOG_DESIGN_WIDTH = 420

local function UpdateDialogScale()
	local realWidth = Dialog.AbsoluteSize.X
	if realWidth <= 0 then return end
	local scale = realWidth / DIALOG_DESIGN_WIDTH
	if scale > 1.05 then scale = 1.05 end
	dialogContentScale.Scale = scale
	DialogContentScaler.Size = UDim2.new(0, DIALOG_DESIGN_WIDTH, 1 / scale, 0)
end

Dialog:GetPropertyChangedSignal("AbsoluteSize"):Connect(UpdateDialogScale)
UpdateDialogScale()

local DialogHeader=Instance.new("Frame"); DialogHeader.Size=UDim2.new(1,0,0,DHH)
DialogHeader.BackgroundColor3=Color3.fromRGB(60,25,90); DialogHeader.BorderSizePixel=0
DialogHeader.ZIndex=21; DialogHeader.Parent=DialogContentScaler
Instance.new("UICorner",DialogHeader).CornerRadius=UDim.new(0,D.CornerRadius)
local DialogTitle=Instance.new("TextLabel"); DialogTitle.Size=UDim2.new(1,-48,1,0); DialogTitle.Position=UDim2.new(0,14,0,0)
DialogTitle.BackgroundTransparency=1; DialogTitle.Text="Prestige?"
DialogTitle.TextColor3=Color3.fromRGB(200,140,255); DialogTitle.TextScaled=true
DialogTitle.Font=T.font; DialogTitle.TextXAlignment=Enum.TextXAlignment.Left; DialogTitle.ZIndex=22; DialogTitle.Parent=DialogHeader

local CBS=D.CloseBtnSize
local DialogCloseBtn=Instance.new("TextButton"); DialogCloseBtn.Size=UDim2.new(0,CBS,0,CBS)
DialogCloseBtn.Position=UDim2.new(1,-(CBS+8),0.5,-CBS/2)
DialogCloseBtn.BackgroundColor3=Color3.fromRGB(180,50,50); DialogCloseBtn.BorderSizePixel=0
DialogCloseBtn.Text="X"; DialogCloseBtn.TextColor3=Color3.fromRGB(255,255,255)
DialogCloseBtn.TextScaled=true; DialogCloseBtn.Font=T.font; DialogCloseBtn.ZIndex=22; DialogCloseBtn.Parent=DialogHeader
CollectionService:AddTag(DialogCloseBtn, "Tutorial_PrestigeCloseBtn") 
Instance.new("UICorner",DialogCloseBtn).CornerRadius=UDim.new(0,5)

local CBH=D.ConfirmBtnH
local ConfirmBtn=Instance.new("TextButton"); ConfirmBtn.Size=UDim2.new(1,-30,0,CBH)
ConfirmBtn.Position=UDim2.new(0,15,1,-(CBH+8))
ConfirmBtn.BackgroundColor3=PRESTIGE_COLOR_ACTIVE; ConfirmBtn.BorderSizePixel=0
ConfirmBtn.Text="Prestige Now"; ConfirmBtn.TextColor3=Color3.fromRGB(255,255,255)
ConfirmBtn.TextScaled=true; ConfirmBtn.Font=T.font; ConfirmBtn.ZIndex=22; ConfirmBtn.Parent=DialogContentScaler
CollectionService:AddTag(ConfirmBtn, "Tutorial_PrestigeConfirm") 
Instance.new("UICorner",ConfirmBtn).CornerRadius=UDim.new(0,8)

local ScrollContainer = Instance.new("ScrollingFrame")
ScrollContainer.Name = "ScrollContainer"
ScrollContainer.Parent = Dialog 
ScrollContainer.BackgroundTransparency = 1
ScrollContainer.BorderSizePixel = 0
ScrollContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
ScrollContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y
ScrollContainer.ScrollBarThickness = 6

local function UpdateDialogScrollBounds()
	local scale = dialogContentScale.Scale
	local scaledTop = (DHH + 5) * scale
	ScrollContainer.Position = UDim2.new(0, 0, 0, scaledTop)
	ScrollContainer.Size = UDim2.new(1, 0, 1, -((DHH + CBH + 20) * scale))
end

dialogContentScale:GetPropertyChangedSignal("Scale"):Connect(UpdateDialogScrollBounds)
UpdateDialogScrollBounds()

local DialogCardsScaler = Instance.new("Frame")
DialogCardsScaler.Name = "CardsScaler"
DialogCardsScaler.BackgroundTransparency = 1
DialogCardsScaler.Parent = ScrollContainer

local dialogCardsScale = Instance.new("UIScale")
dialogCardsScale.Parent = DialogCardsScaler

local DIALOG_CARDS_DESIGN_WIDTH = 400

local function UpdateDialogCardsScale()
	local realWidth = ScrollContainer.AbsoluteSize.X
	if realWidth <= 0 then return end
	local scale = realWidth / DIALOG_CARDS_DESIGN_WIDTH
	if scale > 1.05 then scale = 1.05 end
	dialogCardsScale.Scale = scale
	DialogCardsScaler.Size = UDim2.new(0, DIALOG_CARDS_DESIGN_WIDTH, 1 / scale, 0)
end

ScrollContainer:GetPropertyChangedSignal("AbsoluteSize"):Connect(UpdateDialogCardsScale)
UpdateDialogCardsScale()

local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, GAP)
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
listLayout.Parent = DialogCardsScaler

local function MakeLabel(text, color, h, bold, wrapText)
	local l=Instance.new("TextLabel")
	l.Size=UDim2.new(1,-30,0,h)
	l.BackgroundTransparency=1; l.Text=text; l.TextColor3=color
	l.TextScaled=true; l.Font=bold and T.font or T.fontBody
	l.TextXAlignment=Enum.TextXAlignment.Left; l.ZIndex=21
	if wrapText then l.TextWrapped=true end
	l.Parent=DialogCardsScaler
	return l
end

local EarnedLabel  = MakeLabel("You will earn: +0 Soul Auras",  Color3.fromRGB(255,200,100), D.EarnedH, true)
local BoostLabel   = MakeLabel("",                              Color3.fromRGB(80,220,160),  D.BoostH,  true)
local MultLabel    = MakeLabel("Earnings Bonus: +0% -> +0%",    Color3.fromRGB(180,180,200), D.MultH,   false)
local TotalLabel   = MakeLabel("Total Soul Auras: 0",           Color3.fromRGB(140,140,160), D.TotalH,  false)
local HintLabel    = MakeLabel("Each Soul Aura gives +"..string.format("%.0f",BONUS_PER_SA*100).."% earnings!", Color3.fromRGB(200,160,255), D.HintH, true)
local BonusLabel   = MakeLabel("Kickstart Bonus: $50",          Color3.fromRGB(100,220,100), D.BonusH,  true)
local WarningLabel = MakeLabel("This will RESET your currency, upgrades, and all cubes. Soul Auras are permanent.", Color3.fromRGB(255,100,100), D.WarningH, false, true)

---------------------------------------------------------------
-- Dialog logic
---------------------------------------------------------------
local function CloseDialog()
	dialogOpen=false; dialogCanPrestige=false; PlayUI("6895079853")
	TweenService:Create(Dialog, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Size = UDim2.new(0.88, 0, 0, 0)}):Play()
	UITheme.SetMenuVisible(false)
	task.delay(0.3, function() Dialog.Visible=false end)
end

local function OpenDialogWithPreview(info)
	if dialogOpen then return end
	ForceCloseUI:Fire("PrestigeDialog")
	UITheme.SetMenuVisible(true)
	if info.hasPrestigedThisArea then
		dialogOpen=true; dialogCanPrestige=false
		EarnedLabel.Text="Already prestiged in this area!"; EarnedLabel.TextColor3=Color3.fromRGB(255,100,100)
		BoostLabel.Text=""
		MultLabel.Text="Travel to a new area to prestige again."; MultLabel.TextColor3=Color3.fromRGB(180,180,200)
		TotalLabel.Text="Total Soul Auras: "..Formatter.Format(info.currentSoulAuras or serverSoulAuras)
		BonusLabel.Text=""
		WarningLabel.Text="One prestige per area keeps progression fair. Keep farming or travel!"
		WarningLabel.TextColor3=Color3.fromRGB(200,180,140)
		ConfirmBtn.Text="USED"; ConfirmBtn.BackgroundColor3=PRESTIGE_COLOR_USED
		Dialog.Visible=true
		Dialog.Size=UDim2.new(0.88, 0, 0, 0)
		TweenService:Create(Dialog, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size=UDim2.new(0.88, 0, 0.72, 0)}):Play()
		return
	end
	if (info.newSoulAuras or 0) <= 0 then
		TweenService:Create(PrestigeButton,TweenInfo.new(0.1),{BackgroundColor3=Color3.fromRGB(90,40,120)}):Play()
		task.delay(0.15, function()
			TweenService:Create(PrestigeButton,TweenInfo.new(0.15),{BackgroundColor3=GetButtonColor()}):Play()
		end); return
	end
	dialogCanPrestige=true; dialogOpen=true
	EarnedLabel.Text="You will earn: +"..Formatter.Format(info.newSoulAuras).." Soul Auras"
	EarnedLabel.TextColor3=Color3.fromRGB(255,200,100)
	BoostLabel.Text=info.soulBoostActive and "Soul Boost active - 2x Soul Auras!" or ""
	local currentBonus = (info.currentMultiplier - 1) * 100
	local newBonus = (info.newMultiplier - 1) * 100
	MultLabel.Text = "Earnings Bonus: +"..Formatter.Format(currentBonus).."% -> +"..Formatter.Format(newBonus).."%"
	TotalLabel.Text="Total Soul Auras: "..Formatter.Format(info.currentSoulAuras+info.newSoulAuras)
		.." (was "..Formatter.Format(info.currentSoulAuras)..")"
	BonusLabel.Text="Kickstart Bonus: $"..Formatter.Format(info.prestigeBonus).." to start your next run!"
	WarningLabel.Text="This will RESET your currency, upgrades, and all cubes. Soul Auras are permanent."
	WarningLabel.TextColor3=Color3.fromRGB(255,100,100)
	ConfirmBtn.BackgroundColor3=PRESTIGE_COLOR_ACTIVE; ConfirmBtn.Text="PRESTIGE"
	Dialog.Visible=true
	Dialog.Size=UDim2.new(0.88, 0, 0, 0)
	TweenService:Create(Dialog, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size=UDim2.new(0.88, 0, 0.72, 0)}):Play()
end

local prestigeDebounce = false

PrestigeButton.MouseButton1Down:Connect(function()
	if prestigeDebounce then return end
	prestigeDebounce = true
	task.delay(0.25, function() prestigeDebounce = false end)

	if dialogOpen then
		if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_ClosePrestige") then return end
		if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
		CloseDialog()
		return
	end
	if hasPrestigedThisArea then
		ForceCloseUI:Fire("PrestigeDialog")
		dialogOpen=true; dialogCanPrestige=false
		UITheme.SetMenuVisible(true)
		EarnedLabel.Text="Already prestiged in this area!"; EarnedLabel.TextColor3=Color3.fromRGB(255,100,100)
		BoostLabel.Text=""; MultLabel.Text="Travel to a new area to prestige again."
		MultLabel.TextColor3=Color3.fromRGB(180,180,200)
		TotalLabel.Text="Total Soul Auras: "..Formatter.Format(serverSoulAuras)
		BonusLabel.Text=""
		WarningLabel.Text="One prestige per area. Keep farming or travel!"
		WarningLabel.TextColor3=Color3.fromRGB(200,180,140)
		ConfirmBtn.Text="USED"; ConfirmBtn.BackgroundColor3=PRESTIGE_COLOR_USED
		Dialog.Visible=true
		Dialog.Size=UDim2.new(0.88, 0, 0, 0)
		TweenService:Create(Dialog, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size=UDim2.new(0.88, 0, 0.72, 0)}):Play()
		return
	end
	if previewPending then return end
	if serverTotalEarned<=0 then
		TweenService:Create(PrestigeButton,TweenInfo.new(0.1),{BackgroundColor3=Color3.fromRGB(90,40,120)}):Play()
		task.delay(0.15, function()
			TweenService:Create(PrestigeButton,TweenInfo.new(0.15),{BackgroundColor3=GetButtonColor()}):Play()
		end); return
	end

	if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_OpenPrestige") then return end

	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end

	previewPending=true
	TweenService:Create(PrestigeButton,TweenInfo.new(0.15),{BackgroundColor3=PRESTIGE_COLOR_PENDING}):Play()
	PreviewPrestige:FireServer()

	task.delay(5, function()
		if previewPending then previewPending=false
			TweenService:Create(PrestigeButton,TweenInfo.new(0.2),{BackgroundColor3=GetButtonColor()}):Play()
		end
	end)
end)

PreviewPrestige.OnClientEvent:Connect(function(info)
	previewPending=false
	if info.hasPrestigedThisArea~=nil then hasPrestigedThisArea=info.hasPrestigedThisArea end
	OpenDialogWithPreview(info)
end)

ConfirmBtn.MouseButton1Down:Connect(function()
	if prestigeDebounce then return end
	prestigeDebounce = true
	task.delay(0.25, function() prestigeDebounce = false end)

	if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_PrestigeConfirm") then return end

	if not dialogCanPrestige then CloseDialog(); return end

	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
	PoolManager.ClearPools()
	dialogCanPrestige=false; CloseDialog(); RequestPrestige:FireServer()
end)

DialogCloseBtn.MouseButton1Down:Connect(function()
	if prestigeDebounce then return end
	prestigeDebounce = true
	task.delay(0.25, function() prestigeDebounce = false end)

	if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_ClosePrestige") then return end

	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end

	previewPending=false; CloseDialog()
	TweenService:Create(PrestigeButton,TweenInfo.new(0.2),{BackgroundColor3=GetButtonColor()}):Play()
end)

---------------------------------------------------------------
-- RenderStepped
---------------------------------------------------------------
local buttonWasEnabled = false
RunService.RenderStepped:Connect(function(dt)
	if ratePerSecond>0 then displayedTotalEarned+=ratePerSecond*dt end

	player:SetAttribute("LiveTotalEarned", displayedTotalEarned)

	local runSA=CalcSoulAurasLocal(displayedTotalEarned)
	SACountLabel.Text=Formatter.Format(serverSoulAuras).." Soul Auras"
	if runSA>0 then
		RunSALabel.Text="+"..Formatter.Format(runSA).." on prestige"
		RunSALabel.TextColor3=hasPrestigedThisArea and Color3.fromRGB(140,120,100) or Color3.fromRGB(255,200,100)
	else
		RunSALabel.Text="earning..."
		RunSALabel.TextColor3=Color3.fromRGB(160,140,180)
	end
	local tc=GetThreshold(runSA); local tn=GetThreshold(runSA+1)
	local range=tn-tc; local progress=range>0 and math.clamp((displayedTotalEarned-tc)/range,0,1) or 0
	if runSA~=displayedRunSA then barHighWaterMark=0; displayedRunSA=runSA end
	if progress>barHighWaterMark then barHighWaterMark=progress end
	BarFill.Size=UDim2.new(barHighWaterMark,0,1,0)
	local canPrestige=CalcSoulAurasLocal(serverTotalEarned)>0 and not hasPrestigedThisArea
	if canPrestige~=buttonWasEnabled then
		buttonWasEnabled=canPrestige
		if canPrestige then PrestigeReady:Fire() end
		if not dialogOpen and not previewPending then
			TweenService:Create(PrestigeButton,TweenInfo.new(0.3),{BackgroundColor3=GetButtonColor()}):Play()
		end
	end
end)

---------------------------------------------------------------
-- BRIDGENET2 UPDATEHUD EVENT
---------------------------------------------------------------
UpdateHUDBridge:Connect(function(stats)
	if stats.totalEarned ~= nil then
		serverTotalEarned = stats.totalEarned
		if serverTotalEarned == 0 then
			displayedTotalEarned = 0
			barHighWaterMark = 0
		elseif serverTotalEarned > displayedTotalEarned then 
			displayedTotalEarned = serverTotalEarned 
		end
	end

	if stats.soulAuras then
		serverSoulAuras=stats.soulAuras
		local mult=1+(serverSoulAuras*BONUS_PER_SA)
		local bonusPercent = (mult - 1) * 100
		MultDisplayLabel.Text = mult > 1 and ("+" .. Formatter.Format(bonusPercent) .. "% earnings bonus") or "+0% earnings bonus"
		MultDisplayLabel.TextColor3=mult>1 and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(255, 255, 255)
	end
	if stats.rate and stats.passiveInterval then
		local interval=stats.passiveInterval
		ratePerSecond=(interval>0 and stats.rate>0) and (stats.rate/interval) or 0
	end
	if stats.hasPrestigedThisArea~=nil then
		hasPrestigedThisArea=stats.hasPrestigedThisArea
		if not dialogOpen and not previewPending then
			TweenService:Create(PrestigeButton,TweenInfo.new(0.2),{BackgroundColor3=GetButtonColor()}):Play()
		end
	end
end)

---------------------------------------------------------------
-- PrestigeComplete
---------------------------------------------------------------
PrestigeComplete.OnClientEvent:Connect(function(info)
	if info.blocked then
		TweenService:Create(PrestigeButton,TweenInfo.new(0.1),{BackgroundColor3=Color3.fromRGB(180,60,60)}):Play()
		task.delay(0.2, function() TweenService:Create(PrestigeButton,TweenInfo.new(0.2),{BackgroundColor3=PRESTIGE_COLOR_USED}):Play() end)
		hasPrestigedThisArea=true; return
	end
	if info.hasPrestigedThisArea~=nil then hasPrestigedThisArea=info.hasPrestigedThisArea end

	player:SetAttribute("HabitatVisualOffset", 0)

	for _,obj in ipairs(workspace:GetDescendants()) do
		if obj:GetAttribute("AuraCube") then obj:Destroy() end
	end

	local burstAmount = 0
	if info.prestigeCount == 1 then
		burstAmount = 15 
	elseif info.newSoulAuras and info.newSoulAuras > 0 then
		burstAmount = math.floor(math.pow(info.newSoulAuras, 0.4) * 1.1)
	elseif info.isPortalEntry then
		burstAmount = 15 
	end

	if burstAmount > 0 then
		burstAmount = math.clamp(burstAmount, 1, 50)
		local burstEvent = ReplicatedStorage.RemoteEvents:FindFirstChild("TutorialBurst")
		if burstEvent then burstEvent:FireServer(burstAmount) end
	end

	displayedTotalEarned=0; serverTotalEarned=0; displayedRunSA=0
	ratePerSecond=0; barHighWaterMark=0; previewPending=false
	serverSoulAuras=info.totalSoulAuras
	local flash=Instance.new("Frame"); flash.Size=UDim2.new(1,0,1,0)
	flash.BackgroundColor3=Color3.fromRGB(180,100,255); flash.BackgroundTransparency=0.2
	flash.ZIndex=50; flash.Parent=mainHUD
	TweenService:Create(flash,TweenInfo.new(0.8,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{BackgroundTransparency=1}):Play()
	task.delay(0.9, function() if flash and flash.Parent then flash:Destroy() end end)
	TweenService:Create(PrestigeButton,TweenInfo.new(0.2),{BackgroundColor3=GetButtonColor()}):Play()
	if not info.isPortalEntry then task.delay(0.3, function() ShowPrestigeResultCard(info) end) end
end)

---------------------------------------------------------------
-- AreaChanged
---------------------------------------------------------------
AreaChanged.OnClientEvent:Connect(function(info)
	hasPrestigedThisArea=info.hasPrestigedThisArea or false
	displayedTotalEarned=0; serverTotalEarned=0; displayedRunSA=0
	ratePerSecond=0; barHighWaterMark=0
	TweenService:Create(PrestigeButton,TweenInfo.new(0.2),{BackgroundColor3=GetButtonColor()}):Play()
end)

---------------------------------------------------------------
-- Result card
---------------------------------------------------------------
function ShowPrestigeResultCard(info)
	local CW=C.Cards.PrestigeCardW; local CH=C.Cards.PrestigeCardH
	local card=Instance.new("Frame"); card.Name="PrestigeResultCard"
	card.Size=UDim2.new(0,CW,0,CH); card.Position=UDim2.new(0.5,-CW/2,0,-CH-10)
	card.BackgroundColor3=Color3.fromRGB(22,16,32); card.BorderSizePixel=0
	card.ZIndex=55; card.Parent=mainHUD
	Instance.new("UICorner",card).CornerRadius=UDim.new(0,C.Cards.CornerRadius)
	local cs=Instance.new("UIStroke"); cs.Color=Color3.fromRGB(180,100,255); cs.Thickness=2; cs.Parent=card

	local function AddLabel(text,color,y,h)
		local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,-20,0,h or 28); l.Position=UDim2.new(0,10,0,y)
		l.BackgroundTransparency=1; l.Text=text; l.TextColor3=color
		l.TextScaled=true; l.Font=T.font; l.ZIndex=56; l.Parent=card
	end

	AddLabel("PRESTIGE "..info.prestigeCount.." COMPLETE",Color3.fromRGB(210,160,255),10,36)
	AddLabel("+"..Formatter.Format(info.newSoulAuras).." Soul Auras  ->  "..Formatter.Format(info.totalSoulAuras).." total",
		Color3.fromRGB(255,210,80),52,30)
	local prevBonus = (info.previousMultiplier - 1) * 100
	local newBonus = (info.newMultiplier - 1) * 100
	AddLabel("Earnings Bonus: +"..Formatter.Format(prevBonus).."% -> +"..Formatter.Format(newBonus).."%",
		Color3.fromRGB(160,220,255),88,24)
	AddLabel("Prestige Bonus: $"..Formatter.Format(info.prestigeBonus).." added to your wallet!",
		Color3.fromRGB(100,230,120),118,24)

	local cont=Instance.new("TextButton"); cont.Size=UDim2.new(0,130,0,36)
	cont.Position=UDim2.new(0.5,-65,1,-50)
	cont.BackgroundColor3=Color3.fromRGB(120,50,160); cont.BorderSizePixel=0
	cont.Text="Continue"; cont.TextColor3=Color3.fromRGB(255,255,255)
	cont.TextScaled=true; cont.Font=T.font; cont.ZIndex=57; cont.Parent=card
	Instance.new("UICorner",cont).CornerRadius=UDim.new(0,8)

	TweenService:Create(card,TweenInfo.new(0.45,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
		{Position=UDim2.new(0.5,-CW/2,0.22,0)}):Play()

	local dismissed=false
	local function Dismiss()
		if dismissed then return end; dismissed=true
		TweenService:Create(card,TweenInfo.new(0.4,Enum.EasingStyle.Quad,Enum.EasingDirection.In),
			{Position=UDim2.new(0.5,-CW/2,0,-CH-10)}):Play()
		task.delay(0.5, function() if card and card.Parent then card:Destroy() end end)
	end
	cont.MouseButton1Down:Connect(Dismiss); task.delay(10,Dismiss)
end

---------------------------------------------------------------
-- UI JUICE
---------------------------------------------------------------
local function AddButtonJuice(btn)
	local scale = btn:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = btn
	end

	-- Safely capture original scale from Studio, avoiding zero-scale intro tweens.
	local baseScale = btn:GetAttribute("BaseScale")
	if not baseScale then
		baseScale = scale.Scale
		if baseScale < 0.05 then baseScale = 1 end
		btn:SetAttribute("BaseScale", baseScale)
	end

	local activeTween = nil
	local function TweenTo(targetScale, duration)
		if activeTween then activeTween:Cancel() end
		-- Sine easing strictly prevents mathematically overshooting the visual scale limit 
		activeTween = TweenService:Create(scale, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {Scale = targetScale})
		activeTween:Play()
	end

	local isPressed = false
	local isHovered = false

	btn.MouseEnter:Connect(function()
		isHovered = true
		if not isPressed then
			TweenTo(baseScale * 1.05, 0.15)
		end
	end)

	btn.MouseLeave:Connect(function()
		isHovered = false
		isPressed = false
		TweenTo(baseScale, 0.2)
	end)

	btn.MouseButton1Down:Connect(function()
		isPressed = true
		TweenTo(baseScale * 0.9, 0.1)
	end)

	btn.MouseButton1Up:Connect(function()
		if not isPressed then return end
		isPressed = false
		TweenTo(isHovered and (baseScale * 1.05) or baseScale, 0.2)
	end)
end

AddButtonJuice(PrestigeButton)
AddButtonJuice(ConfirmBtn)
AddButtonJuice(DialogCloseBtn)

local function RefreshLook()
	UITheme.Apply(PrestigeButton, "Panel")
	UITheme.Apply(ConfirmBtn, "Panel")
	UITheme.ApplyShine(Dialog)

	local outerStroke = Dialog:FindFirstChildWhichIsA("UIStroke")
	if outerStroke then
		outerStroke.Color = Color3.fromRGB(165, 20, 255)
	end
end

task.wait(2)
RefreshLook()

ForceCloseUI.Event:Connect(function(exceptionPanel)
	if exceptionPanel ~= "PrestigeDialog" and dialogOpen then CloseDialog() end
end)

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local Lighting          = game:GetService("Lighting")

local UITheme = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UITheme"))
local T = UITheme.Get("Custom")
local C = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UIConfig"))
local M = C.MainMenu

-- ✨ IMPORTS
local PoolManager = require(ReplicatedStorage.Modules:WaitForChild("PoolManager"))
local AreaRegistry = require(ReplicatedStorage.Modules:WaitForChild("AreaRegistry"))

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local mainHUD   = playerGui:WaitForChild("MainHUD", 10)
if not mainHUD then
	warn("[MainMenuController] MainHUD did not appear within 10 seconds! Menu cannot continue normally.")
	local blackoutGui = playerGui:FindFirstChild("PreloadBlackout")
	if blackoutGui then blackoutGui:Destroy() end
	return
end

local camera    = workspace.CurrentCamera

-- Start removing the blackout GUI as early as possible
local blackoutGui = playerGui:FindFirstChild("PreloadBlackout")
if blackoutGui then
	local blackoutFrame = blackoutGui:FindFirstChild("BlackoutFrame")
	if blackoutFrame then
		TweenService:Create(blackoutFrame, TweenInfo.new(1.0, Enum.EasingStyle.Sine), {
			BackgroundTransparency = 1
		}):Play()
	end
	task.delay(1.1, function() blackoutGui:Destroy() end)
end

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local AreaUpdated  = RemoteEvents:WaitForChild("AreaUpdated", 10)

if not AreaUpdated then
	warn("[MainMenuController] AreaUpdated RemoteEvent did not appear within 10 seconds!")
end

local MenuDismissed = Instance.new("BindableEvent")
MenuDismissed.Name = "MenuDismissed"
MenuDismissed.Parent = ReplicatedStorage

local MENU_ENABLED = true

if not MENU_ENABLED then
	MenuDismissed:SetAttribute("Fired", true)
	MenuDismissed:Fire()
	local bgui = playerGui:FindFirstChild("PreloadBlackout")
	if bgui then bgui:Destroy() end
	return
end

local FADE_IN_TIME   = M.FadeInTime or 0.8
local FADE_OUT_TIME  = M.FadeOutTime or 1.2
local IDLE_SPEED     = M.IdleSpeed or 3
local TITLE_FONT     = T.font or Enum.Font.FredokaOne
local BODY_FONT      = T.fontBody or Enum.Font.FredokaOne
local DEFAULT_AREA   = 1

local currentArea     = DEFAULT_AREA
local hasPlayed       = false
local idleConn        = nil
local areaConn        = nil

mainHUD.Enabled = false

local savedCamType    = camera.CameraType
local savedCamSubject = camera.CameraSubject

camera.CameraType = Enum.CameraType.Scriptable

local function GetMenuAnchor(area)
	return workspace:FindFirstChild("MenuCamPos_" .. area)
		or workspace:FindFirstChild("MenuCamPos_1")
		or workspace:FindFirstChild("MenuCamPos")
		or workspace:WaitForChild("MenuCamPos", 5)
end

local function SnapCameraToArea(area)
	local anchor = GetMenuAnchor(area)
	if not anchor then return end
	camera.CFrame = anchor.CFrame
end

---------------------------------------------------------------
-- ✨ PARALLAX CAMERA & MOUSE TRACKING
---------------------------------------------------------------
local targetParallaxX = 0
local targetParallaxY = 0
local currentParallaxX = 0
local currentParallaxY = 0
local PARALLAX_STRENGTH = 4 

UserInputService.InputChanged:Connect(function(input, gameProcessed)
	if hasPlayed then return end
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		local viewSize = camera.ViewportSize
		if viewSize.X > 0 and viewSize.Y > 0 then
			local pos = input.Position
			targetParallaxX = math.clamp((pos.X / viewSize.X) * 2 - 1, -1, 1)
			targetParallaxY = math.clamp((pos.Y / viewSize.Y) * 2 - 1, -1, 1)
		end
	end
end)

local function StartIdleDrift(area)
	if idleConn then idleConn:Disconnect(); idleConn = nil end

	local anchor = GetMenuAnchor(area)
	if not anchor then return end

	local baseCF = anchor.CFrame
	local basePos = baseCF.Position
	local lookTarget = basePos + baseCF.LookVector * 50
	local angle = 0

	idleConn = RunService.RenderStepped:Connect(function(dt)
		angle += dt * IDLE_SPEED
		local idleOffset = CFrame.Angles(0, math.rad(angle * 0.3), 0).LookVector * 0.5

		currentParallaxX = currentParallaxX + (targetParallaxX - currentParallaxX) * 5 * dt
		currentParallaxY = currentParallaxY + (targetParallaxY - currentParallaxY) * 5 * dt

		local pitch = math.rad(-currentParallaxY * PARALLAX_STRENGTH)
		local yaw = math.rad(-currentParallaxX * PARALLAX_STRENGTH)

		local baseLook = CFrame.lookAt(basePos + idleOffset, lookTarget)
		camera.CFrame = baseLook * CFrame.Angles(pitch, yaw, 0)
	end)
end

SnapCameraToArea(DEFAULT_AREA)
StartIdleDrift(DEFAULT_AREA)

---------------------------------------------------------------
-- ✨ MENU UI CONSTRUCTION (Mobile Responsive)
---------------------------------------------------------------
local menuScreen = Instance.new("ScreenGui")
menuScreen.Name = "MainMenu"
menuScreen.DisplayOrder = 100
menuScreen.IgnoreGuiInset = true
menuScreen.ResetOnSpawn = false
menuScreen.Parent = playerGui

local vignette = Instance.new("Frame")
vignette.Name = "Vignette"
vignette.Size = UDim2.new(1, 0, 1, 0)
vignette.BackgroundColor3 = Color3.new(0, 0, 0)
vignette.BackgroundTransparency = 0
vignette.BorderSizePixel = 0
vignette.ZIndex = 1
vignette.Parent = menuScreen

local vigGrad = Instance.new("UIGradient")
vigGrad.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.1),
	NumberSequenceKeypoint.new(0.4, 0.8),
	NumberSequenceKeypoint.new(1, 1),
})
vigGrad.Rotation = 0
vigGrad.Parent = vignette

-- ✨ MAIN CONTAINER (Uses Scale for height/width)
local container = Instance.new("Frame")
container.Name = "MenuContainer"
container.Size = UDim2.new(0.8, 0, 0.7, 0) -- Scaled to 70% of screen height
container.Position = UDim2.new(0.05, 0, 0.5, 0) 
container.AnchorPoint = Vector2.new(0, 0.5)
container.BackgroundTransparency = 1
container.ZIndex = 2
container.Parent = menuScreen

local containerConstraint = Instance.new("UISizeConstraint")
containerConstraint.MaxSize = Vector2.new(800, 700)
containerConstraint.Parent = container

local listLayout = Instance.new("UIListLayout", container)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
listLayout.VerticalAlignment = Enum.VerticalAlignment.Center
listLayout.Padding = UDim.new(0.02, 0) -- Relative padding

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "Title"
titleLabel.Size = UDim2.new(1, 0, 0.25, 0) -- 25% of container height
titleLabel.LayoutOrder = 1
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "AURA INC"
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.TextScaled = true
titleLabel.Font = TITLE_FONT
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.ZIndex = 10
titleLabel.Parent = container
Instance.new("UITextSizeConstraint", titleLabel).MaxTextSize = 120

local titleShadow = titleLabel:Clone()
titleShadow.Name = "TitleShadow"
titleShadow.TextColor3 = T.accentPurple
titleShadow.TextTransparency = 0.2
titleShadow.Position = UDim2.new(0, 5, 0, 5) 
titleShadow.ZIndex = 9
titleShadow.Parent = titleLabel

local titleStroke = Instance.new("UIStroke")
titleStroke.Color = T.accentPurple
titleStroke.Thickness = 4
titleStroke.Parent = titleLabel

local subtitleLabel = Instance.new("TextLabel")
subtitleLabel.Name = "Subtitle"
subtitleLabel.Size = UDim2.new(1, 0, 0.1, 0) 
subtitleLabel.LayoutOrder = 2
subtitleLabel.BackgroundTransparency = 1
subtitleLabel.Text = "Idle Aura Factory"
subtitleLabel.TextColor3 = T.subText
subtitleLabel.TextScaled = true
subtitleLabel.Font = BODY_FONT
subtitleLabel.TextXAlignment = Enum.TextXAlignment.Left
subtitleLabel.ZIndex = 10
subtitleLabel.Parent = container
Instance.new("UITextSizeConstraint", subtitleLabel).MaxTextSize = 45

local spacer = Instance.new("Frame", container)
spacer.LayoutOrder = 3
spacer.Size = UDim2.new(1, 0, 0.05, 0)
spacer.BackgroundTransparency = 1

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "Status"
statusLabel.Size = UDim2.new(1, 0, 0.08, 0) 
statusLabel.LayoutOrder = 4
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "Generating Physics Pools..."
statusLabel.TextColor3 = T.accentGold
statusLabel.TextScaled = true
statusLabel.Font = BODY_FONT
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.ZIndex = 10
statusLabel.Parent = container
Instance.new("UITextSizeConstraint", statusLabel).MaxTextSize = 30

-- ✨ PLAY BUTTON 
local playBtn = Instance.new("TextButton")
playBtn.Name = "PlayButton"
playBtn.Size = UDim2.new(0.6, 0, 0.2, 0) 
playBtn.LayoutOrder = 5
playBtn.BackgroundColor3 = T.buttonPrimary
playBtn.BorderSizePixel = 0
playBtn.Text = "PLAY"
playBtn.TextColor3 = T.headerText
playBtn.TextScaled = true
playBtn.Font = TITLE_FONT
playBtn.ZIndex = 10
playBtn.AutoButtonColor = false
playBtn.Visible = false 
playBtn.Parent = container

local playConstraint = Instance.new("UISizeConstraint", playBtn)
playConstraint.MaxSize = Vector2.new(320, 90)
Instance.new("UICorner", playBtn).CornerRadius = UDim.new(0.2, 0)
Instance.new("UITextSizeConstraint", playBtn).MaxTextSize = 50

local playStroke = Instance.new("UIStroke")
playStroke.Color = T.accentPurple
playStroke.Thickness = 4
playStroke.Parent = playBtn

local playScale = Instance.new("UIScale", playBtn)
playScale.Scale = 0 

-- ✨ SETTINGS BUTTON 
local settingsBtn = Instance.new("TextButton")
settingsBtn.Name = "SettingsButton"
settingsBtn.Size = UDim2.new(0.5, 0, 0.15, 0) 
settingsBtn.LayoutOrder = 6
settingsBtn.BackgroundColor3 = T.buttonPrimary
settingsBtn.BorderSizePixel = 0
settingsBtn.Text = "SETTINGS"
settingsBtn.TextColor3 = T.headerText
settingsBtn.TextScaled = true
settingsBtn.Font = TITLE_FONT
settingsBtn.ZIndex = 10
settingsBtn.AutoButtonColor = false
settingsBtn.Visible = false 
settingsBtn.Parent = container

local setConstraint = Instance.new("UISizeConstraint", settingsBtn)
setConstraint.MaxSize = Vector2.new(250, 65)
Instance.new("UICorner", settingsBtn).CornerRadius = UDim.new(0.2, 0)
Instance.new("UITextSizeConstraint", settingsBtn).MaxTextSize = 35

local setStroke = Instance.new("UIStroke")
setStroke.Color = T.accentPurple
setStroke.Thickness = 4
setStroke.Parent = settingsBtn

local setScale = Instance.new("UIScale", settingsBtn)
setScale.Scale = 0

TweenService:Create(container, TweenInfo.new(3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
	Position = container.Position - UDim2.new(0, 0, 0.02, 0)
}):Play()

-- Button Interactions
local function AddJuice(btn, scaleObj)
	local isHovering = false

	btn.MouseEnter:Connect(function()
		isHovering = true
		TweenService:Create(scaleObj, TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {Scale = 1.05}):Play()
	end)

	btn.MouseLeave:Connect(function()
		isHovering = false
		TweenService:Create(scaleObj, TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {Scale = 1.0}):Play()
	end)

	btn.MouseButton1Down:Connect(function()
		TweenService:Create(scaleObj, TweenInfo.new(0.1, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {Scale = 0.95}):Play()
		if shared.PlayUISound then shared.PlayUISound("6895079853") end
	end)

	btn.MouseButton1Up:Connect(function()
		TweenService:Create(scaleObj, TweenInfo.new(0.3, Enum.EasingStyle.Bounce), {Scale = 1.05}):Play()
	end)
end

AddJuice(playBtn, playScale)
AddJuice(settingsBtn, setScale)

task.spawn(function()
	task.wait(0.5) 
	if UITheme and UITheme.Apply then 
		UITheme.Apply(playBtn, "ShineOutline") 
		UITheme.Apply(settingsBtn, "ShineOutline")
	end

	if UITheme and UITheme.ApplyFlair then 
		UITheme.ApplyFlair(playBtn, "SlowGhost")
		UITheme.ApplyFlair(settingsBtn, "SlowGhost")
		UITheme.ApplyFlair(titleLabel, "SlowGhost") 
		UITheme.ApplyFlair(subtitleLabel, "SlowGhost")
	end
end)

local creditLabel = Instance.new("TextLabel")
creditLabel.Name = "Credits"
creditLabel.Size = UDim2.new(0, 200, 0, 20)
creditLabel.Position = UDim2.new(0, 15, 1, -25)
creditLabel.AnchorPoint = Vector2.new(0, 0)
creditLabel.BackgroundTransparency = 1
creditLabel.Text = "Made by MoldySugar2205"
creditLabel.TextColor3 = T.subText
creditLabel.TextTransparency = 0.3
creditLabel.TextScaled = true
creditLabel.Font = BODY_FONT
creditLabel.TextXAlignment = Enum.TextXAlignment.Left
creditLabel.ZIndex = 10
creditLabel.Parent = menuScreen

---------------------------------------------------------------
-- ✨ THEME APPLICATION LOGIC
---------------------------------------------------------------
local function ApplyAreaTheme(area)
	local primaryColor = T.buttonPrimary
	local strokeColor = T.accentPurple

	pcall(function()
		local areaData = AreaRegistry.Get(area)
		if areaData then
			primaryColor = areaData.previewColor or areaData.auraHolderColor or areaData.grassColor or primaryColor
		end
	end)

	local h, s, v = Color3.toHSV(primaryColor)
	strokeColor = Color3.fromHSV(h, math.clamp(s + 0.2, 0, 1), math.clamp(v - 0.45, 0, 1))

	titleStroke.Color = primaryColor
	titleShadow.TextColor3 = strokeColor
	statusLabel.TextColor3 = primaryColor

	playBtn.BackgroundColor3 = primaryColor
	playStroke.Color = strokeColor

	settingsBtn.BackgroundColor3 = primaryColor
	setStroke.Color = strokeColor
end

ApplyAreaTheme(player:GetAttribute("CurrentArea") or DEFAULT_AREA)

if AreaUpdated then
	areaConn = AreaUpdated.OnClientEvent:Connect(function(info)
		if hasPlayed then return end
		local area = info.currentArea or DEFAULT_AREA
		if area ~= currentArea then
			currentArea = area
			SnapCameraToArea(area)
			StartIdleDrift(area)
			ApplyAreaTheme(area) 
		end
	end)
end

---------------------------------------------------------------
-- ✨ PRE-GAME SETTINGS MENU
---------------------------------------------------------------
local settingsOverlay = Instance.new("Frame")
settingsOverlay.Size = UDim2.new(1, 0, 1, 0)
settingsOverlay.BackgroundColor3 = Color3.new(0,0,0)
settingsOverlay.BackgroundTransparency = 1
settingsOverlay.Visible = false
settingsOverlay.ZIndex = 20
settingsOverlay.Parent = menuScreen

local settingsPanel = Instance.new("Frame")
settingsPanel.Size = UDim2.new(0, 350, 0, 380)
settingsPanel.Position = UDim2.new(0.5, 0, 0.5, 0)
settingsPanel.AnchorPoint = Vector2.new(0.5, 0.5)
settingsPanel.BackgroundColor3 = T.panelBG
settingsPanel.BorderSizePixel = 0
settingsPanel.ZIndex = 21
settingsPanel.Parent = settingsOverlay
Instance.new("UICorner", settingsPanel).CornerRadius = UDim.new(0, 12)
local pStroke = Instance.new("UIStroke", settingsPanel); pStroke.Color = T.panelStroke; pStroke.Thickness = 2

local sHeader = Instance.new("Frame", settingsPanel); sHeader.Size = UDim2.new(1, 0, 0, 45); sHeader.BackgroundColor3 = T.headerBG; sHeader.BorderSizePixel = 0; sHeader.ZIndex = 22; Instance.new("UICorner", sHeader).CornerRadius = UDim.new(0, 12)
local sTitle = Instance.new("TextLabel", sHeader); sTitle.Size = UDim2.new(1, -20, 1, 0); sTitle.Position = UDim2.new(0, 15, 0, 0); sTitle.BackgroundTransparency = 1; sTitle.Text = "SETTINGS"; sTitle.TextColor3 = T.headerText; sTitle.TextScaled = true; sTitle.Font = TITLE_FONT; sTitle.TextXAlignment = Enum.TextXAlignment.Left; sTitle.ZIndex = 23
local sClose = Instance.new("TextButton", sHeader); sClose.Size = UDim2.new(0, 30, 0, 30); sClose.Position = UDim2.new(1, -40, 0.5, -15); sClose.BackgroundColor3 = T.buttonRed; sClose.Text = "X"; sClose.TextColor3 = Color3.fromRGB(255,255,255); sClose.TextScaled = true; sClose.Font = TITLE_FONT; sClose.ZIndex = 23; Instance.new("UICorner", sClose).CornerRadius = UDim.new(0, 6)

local sList = Instance.new("Frame", settingsPanel); sList.Size = UDim2.new(1, -20, 1, -60); sList.Position = UDim2.new(0, 10, 0, 55); sList.BackgroundTransparency = 1; sList.ZIndex = 22
local slistLayout = Instance.new("UIListLayout", sList); slistLayout.Padding = UDim.new(0, 10); slistLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

local function MakeSelectorRow(label, options, defaultIndex, onChange)
	local row = Instance.new("Frame", sList); row.Size = UDim2.new(1, 0, 0, 45); row.BackgroundColor3 = T.cardBG; row.BorderSizePixel = 0; row.ZIndex = 23; Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)
	local lbl = Instance.new("TextLabel", row); lbl.Size = UDim2.new(0.5, 0, 1, 0); lbl.Position = UDim2.new(0, 10, 0, 0); lbl.BackgroundTransparency = 1; lbl.Text = label; lbl.TextColor3 = T.bodyText; lbl.TextScaled = true; lbl.Font = BODY_FONT; lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.ZIndex = 24

	local valLbl = Instance.new("TextLabel", row); valLbl.Size = UDim2.new(0.3, 0, 0.6, 0); valLbl.Position = UDim2.new(0.6, 0, 0.2, 0); valLbl.BackgroundTransparency = 1; valLbl.Text = options[defaultIndex]; valLbl.TextColor3 = T.accentGold; valLbl.TextScaled = true; valLbl.Font = BODY_FONT; valLbl.ZIndex = 24

	local leftBtn = Instance.new("TextButton", row); leftBtn.Size = UDim2.new(0, 25, 0, 25); leftBtn.Position = UDim2.new(0.55, 0, 0.5, -12.5); leftBtn.BackgroundColor3 = T.buttonSecondary; leftBtn.Text = "<"; leftBtn.TextColor3 = T.bodyText; leftBtn.Font = TITLE_FONT; leftBtn.TextScaled = true; leftBtn.ZIndex = 24; Instance.new("UICorner", leftBtn).CornerRadius = UDim.new(0, 6)
	local rightBtn = Instance.new("TextButton", row); rightBtn.Size = UDim2.new(0, 25, 0, 25); rightBtn.Position = UDim2.new(0.9, 0, 0.5, -12.5); rightBtn.BackgroundColor3 = T.buttonSecondary; rightBtn.Text = ">"; rightBtn.TextColor3 = T.bodyText; rightBtn.Font = TITLE_FONT; rightBtn.TextScaled = true; rightBtn.ZIndex = 24; Instance.new("UICorner", rightBtn).CornerRadius = UDim.new(0, 6)

	local currentIndex = defaultIndex
	local function UpdateOpt(dir)
		if shared.PlayUISound then shared.PlayUISound("6895079853") end
		currentIndex = currentIndex + dir
		if currentIndex < 1 then currentIndex = #options end
		if currentIndex > #options then currentIndex = 1 end
		valLbl.Text = options[currentIndex]
		if onChange then onChange(options[currentIndex]) end
	end

	leftBtn.MouseButton1Click:Connect(function() UpdateOpt(-1) end)
	rightBtn.MouseButton1Click:Connect(function() UpdateOpt(1) end)
end

local vols = {"0%", "25%", "50%", "75%", "100%"}
MakeSelectorRow("Music", vols, 5, function(val) print("Music set to", val) end) 
MakeSelectorRow("SFX", vols, 5, function(val) print("SFX set to", val) end)
MakeSelectorRow("Quality", {"Low", "Medium", "High"}, 3, function(val) 
	if val == "Low" then Lighting.GlobalShadows = false else Lighting.GlobalShadows = true end
end)
MakeSelectorRow("Language", {"Auto", "English", "Español", "Français"}, 1, function(val)
	print("Language preference changed to", val)
end)

local panelScale = Instance.new("UIScale", settingsPanel); panelScale.Scale = 0
settingsBtn.MouseButton1Click:Connect(function()
	if shared.PlayUISound then shared.PlayUISound("6895079853") end
	settingsOverlay.Visible = true
	TweenService:Create(settingsOverlay, TweenInfo.new(0.3), {BackgroundTransparency = 0.5}):Play()
	TweenService:Create(panelScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
end)

sClose.MouseButton1Click:Connect(function()
	if shared.PlayUISound then shared.PlayUISound("6895079853") end
	TweenService:Create(settingsOverlay, TweenInfo.new(0.3), {BackgroundTransparency = 1}):Play()
	local tOut = TweenService:Create(panelScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In), {Scale = 0})
	tOut:Play()
	tOut.Completed:Once(function() settingsOverlay.Visible = false end)
end)

---------------------------------------------------------------
-- LOADING SCREEN FADE
---------------------------------------------------------------
local blackFade = Instance.new("Frame")
blackFade.Name = "BlackFade"
blackFade.Size = UDim2.new(1, 0, 1, 0)
blackFade.BackgroundColor3 = Color3.new(0, 0, 0)
blackFade.BackgroundTransparency = 1
blackFade.BorderSizePixel = 0
blackFade.ZIndex = 50
blackFade.Parent = menuScreen

local loadingText = Instance.new("TextLabel")
loadingText.Name = "LoadingText"
loadingText.Size = UDim2.new(1, 0, 0, 50)
loadingText.Position = UDim2.new(0, 0, 0.5, -25)
loadingText.BackgroundTransparency = 1
loadingText.Text = "INITIALIZING SYSTEMS..."
loadingText.TextColor3 = T.accentBlue or Color3.fromRGB(100, 200, 255)
loadingText.TextScaled = true
loadingText.Font = TITLE_FONT
loadingText.TextTransparency = 1
loadingText.ZIndex = 51
loadingText.Parent = blackFade

---------------------------------------------------------------
-- PLAY BUTTON CLICK
---------------------------------------------------------------
playBtn.MouseButton1Down:Connect(function()
	if hasPlayed then return end
	hasPlayed = true

	playBtn.Active = false
	settingsBtn.Active = false

	if areaConn then areaConn:Disconnect(); areaConn = nil end

	TweenService:Create(blackFade, TweenInfo.new(FADE_IN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0
	}):Play()
	TweenService:Create(loadingText, TweenInfo.new(FADE_IN_TIME), {
		TextTransparency = 0
	}):Play()
	task.wait(FADE_IN_TIME)

	if idleConn then idleConn:Disconnect(); idleConn = nil end

	camera.CameraType = savedCamType
	local character = player.Character or player.CharacterAdded:Wait()
	local humanoid = character:WaitForChild("Humanoid", 5)
	if humanoid then
		camera.CameraSubject = humanoid
	end

	mainHUD.Enabled = true

	vignette:Destroy()
	container:Destroy()
	settingsOverlay:Destroy()

	if not game:IsLoaded() then game.Loaded:Wait() end
	loadingText.Text = "LOADING AURAS..."
	task.wait(2) 

	TweenService:Create(blackFade, TweenInfo.new(FADE_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1
	}):Play()
	TweenService:Create(loadingText, TweenInfo.new(FADE_OUT_TIME), {
		TextTransparency = 1
	}):Play()
	task.wait(FADE_OUT_TIME)

	MenuDismissed:SetAttribute("Fired", true)
	MenuDismissed:Fire()

	menuScreen:Destroy()
end)

---------------------------------------------------------------
-- ✨ TRUE BACKGROUND LOADING (POOL CREATION)
---------------------------------------------------------------
task.spawn(function()
	if not game:IsLoaded() then game.Loaded:Wait() end

	local playerArea = player:GetAttribute("CurrentArea") or DEFAULT_AREA
	statusLabel.Text = "Optimizing Physics (Area " .. playerArea .. ")..."

	task.wait(0.2)
	PoolManager.InitializeArea(playerArea)
	statusLabel.Text = "Ready!"
	task.wait(0.3)

	statusLabel.Visible = false
	playBtn.Visible = true
	settingsBtn.Visible = true

	TweenService:Create(playScale, TweenInfo.new(0.6, Enum.EasingStyle.Bounce), {Scale = 1}):Play()
	task.wait(0.15)
	TweenService:Create(setScale, TweenInfo.new(0.6, Enum.EasingStyle.Bounce), {Scale = 1}):Play()
end)
