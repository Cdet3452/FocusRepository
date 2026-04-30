-- PlatformController
-- Location: StarterPlayer > StarterPlayerScripts > PlatformController

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

local Camera = workspace.CurrentCamera
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainHUD = playerGui:WaitForChild("MainHUD")
local currLabel = mainHUD:WaitForChild("CurrencyLabel")

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

---------------------------------------------------------------
-- ✨ PERFECTLY SYNCED JUICY VISUALS ✨
---------------------------------------------------------------
local function PlayShippingJuice(exactAmount)
	-- Log the pending payout so the UI knows to wait for the coins!
	local currentPending = player:GetAttribute("LocalPendingPayout") or 0
	player:SetAttribute("LocalPendingPayout", currentPending + exactAmount)

	local currPos = currLabel.AbsolutePosition
	local currSize = currLabel.AbsoluteSize

	local popupWidth = 200
	local startX = currPos.X - popupWidth - 20 
	local startY = currPos.Y + (currSize.Y / 2) - 40 

	local endPos2D = currPos + (currSize / 2)

	local effectGui = Instance.new("ScreenGui")
	effectGui.Name = "ShippingJuiceGui"
	effectGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	effectGui.Parent = playerGui

	local popupText = Instance.new("TextLabel")
	popupText.Text = "+$" .. FormatNumber(exactAmount)
	popupText.Font = Enum.Font.FredokaOne
	popupText.TextScaled = true
	popupText.TextColor3 = Color3.fromRGB(85, 255, 127)
	popupText.BackgroundTransparency = 1
	popupText.Size = UDim2.new(0, popupWidth, 0, 80)
	popupText.Position = UDim2.new(0, startX, 0, startY)
	popupText.ZIndex = 100
	popupText.Parent = effectGui

	local textStroke = Instance.new("UIStroke", popupText)
	textStroke.Color = Color3.fromRGB(0, 50, 0)
	textStroke.Thickness = 3

	local textScale = Instance.new("UIScale", popupText)
	textScale.Scale = 0

	TweenService:Create(textScale, TweenInfo.new(0.4, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), {Scale = 1.2}):Play()

	task.delay(0.6, function()
		TweenService:Create(popupText, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			Position = UDim2.new(0, startX, 0, startY - 80),
			TextTransparency = 1
		}):Play()
		TweenService:Create(textStroke, TweenInfo.new(0.8), {Transparency = 1}):Play()
	end)

	local sfxFolder = ReplicatedStorage:FindFirstChild("SFX") or ReplicatedStorage:FindFirstChild("Sounds")
	if sfxFolder and sfxFolder:FindFirstChild("CashRegister") then
		local sfx = sfxFolder.CashRegister:Clone()
		sfx.Parent = game:GetService("SoundService")
		sfx:Play()
		Debris:AddItem(sfx, 2)
	end

	local CASH_ICON_ID = "rbxassetid://14916846070" 

	-- Math out the chunk for each coin
	local chunkAmount = exactAmount / 10
	local coinsHit = 0

	for i = 1, 10 do
		local coin = Instance.new("ImageLabel")
		coin.Image = CASH_ICON_ID
		coin.BackgroundTransparency = 1
		coin.Size = UDim2.new(0, 40, 0, 40)
		coin.Position = UDim2.new(0, startX + (popupWidth/2) - 20, 0, startY + 20)
		coin.ZIndex = 90
		coin.Parent = effectGui

		local randomOffsetX = math.random(-80, 80)
		local randomOffsetY = math.random(-80, 80)
		local burstPos = UDim2.new(0, startX + (popupWidth/2) - 20 + randomOffsetX, 0, startY + 20 + randomOffsetY)

		local burstTween = TweenService:Create(coin, TweenInfo.new(0.3, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), {
			Position = burstPos,
			Rotation = math.random(-180, 180)
		})
		burstTween:Play()

		burstTween.Completed:Connect(function()
			local flyTween = TweenService:Create(coin, TweenInfo.new(0.4 + (i * 0.02), Enum.EasingStyle.Back, Enum.EasingDirection.In), {
				Position = UDim2.new(0, endPos2D.X - 20, 0, endPos2D.Y - 20),
				Size = UDim2.new(0, 20, 0, 20),
				ImageTransparency = 0.3
			})
			flyTween:Play()

			flyTween.Completed:Connect(function()
				if coin.Parent then coin:Destroy() end
				coinsHit += 1

				-- ADD CASH TO THE BANK VISUALLY
				player:SetAttribute("VisualCashToAdd", chunkAmount)

				-- REMOVE FROM PENDING LOCK
				local pending = player:GetAttribute("LocalPendingPayout") or 0
				player:SetAttribute("LocalPendingPayout", math.max(0, pending - chunkAmount))

				if sfxFolder and sfxFolder:FindFirstChild("CoinTick") then
					local sfx = sfxFolder.CoinTick:Clone()
					sfx.Pitch = 1.5 + (math.random()*0.2)
					sfx.Parent = game:GetService("SoundService")
					sfx:Play()
					Debris:AddItem(sfx, 1)
				end

				local ts = currLabel:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", currLabel)
				ts.Scale = 1.1
				TweenService:Create(ts, TweenInfo.new(0.1, Enum.EasingStyle.Sine), {Scale = 1}):Play()
			end)
		end)
	end

	-- FAILSAFE: Ensure the lock clears and money deposits even if a player lags out of tweens
	task.delay(3, function()
		if effectGui.Parent then effectGui:Destroy() end
		if coinsHit < 10 then
			local remaining = (10 - coinsHit) * chunkAmount
			player:SetAttribute("VisualCashToAdd", remaining)
			player:SetAttribute("LocalPendingPayout", 0)
		end
	end)
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

local function PayoutPopup(position, payout, multiplier)
	local anchor = Instance.new("Part")
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Anchored = true
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.Position = position
	anchor.Parent = workspace

	local bb = Instance.new("BillboardGui")
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
	local habitatPos = GetHabitatPos()  

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
			local dist = (rootPart.Position - habitatPos).Magnitude  
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
	local myDispatchId = info.dispatchId
	local platform     = CreatePlatform()

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
	if info.action == "payoutConfirmed" then
		PlayShippingJuice(info.amount)
	else
		table.insert(platformQueue, info)
		task.spawn(ProcessQueue)
	end
end)
