-- PlatformController
-- Location: StarterPlayer > StarterPlayerScripts > PlatformController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local AdminConfig = require(ReplicatedStorage.Modules.AdminConfig)
local Formatter = require(ReplicatedStorage.Modules.NumberFormatter) 

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
local gaurasLabel = mainHUD:WaitForChild("GoldenAurasLabel")

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
	return Formatter.Format(math.floor(tonumber(n) or 0))
end

---------------------------------------------------------------
-- ✨ UNIVERSAL JUICY VISUALS (CASH & AURAS) ✨
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
	popupText.Text = (isAura and "+" or "+$") .. FormatNumber(exactAmount)
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
	payoutBB.Size = UDim2.new(8, 0, 2.5, 0) 
	payoutBB.StudsOffset = Vector3.new(0, 5, 0)
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
	payoutLabel.TextTransparency = 1
	payoutLabel.Parent = payoutBB

	local payoutStroke = Instance.new("UIStroke", payoutLabel)
	payoutStroke.Thickness = 3
	payoutStroke.Color = Color3.fromRGB(0, 40, 0)

	local multBB = Instance.new("BillboardGui")
	multBB.Size = UDim2.new(6, 0, 1.5, 0) 
	multBB.StudsOffset = Vector3.new(0, 2.5, 0)
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
	multLabel.TextTransparency = 1
	multLabel.Parent = multBB

	local multStroke = Instance.new("UIStroke", multLabel)
	multStroke.Thickness = 2.5
	multStroke.Color = Color3.fromRGB(0, 0, 0)

	TweenService:Create(payoutLabel, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
	TweenService:Create(multLabel, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
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
	bb.Size = UDim2.new(10, 0, 2.5, 0) 
	bb.StudsOffset = Vector3.new(0, 7, 0)
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
	label.TextStrokeTransparency = 1
	label.TextTransparency = 0
	label.Parent = bb

	local lStroke = Instance.new("UIStroke", label)
	lStroke.Thickness = 3
	lStroke.Color = Color3.fromRGB(0, 0, 0)

	TweenService:Create(bb, TweenInfo.new(1.8, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { StudsOffset = Vector3.new(0, 18, 0) }):Play()
	task.delay(0.6, function()
		TweenService:Create(label, TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1 }):Play()
		TweenService:Create(lStroke, TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
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
		PlayJuiceEffect(info.amount, "Currency")
	elseif info.action == "playJuice" then
		PlayJuiceEffect(info.amount, info.currencyType)
	else
		table.insert(platformQueue, info)
		task.spawn(ProcessQueue)
	end
end)

local LocalJuiceEvent = ReplicatedStorage:FindFirstChild("LocalJuiceEvent")
if not LocalJuiceEvent then
	LocalJuiceEvent = Instance.new("BindableEvent")
	LocalJuiceEvent.Name = "LocalJuiceEvent"
	LocalJuiceEvent.Parent = ReplicatedStorage
end
LocalJuiceEvent.Event:Connect(function(exactAmount, currencyType)
	PlayJuiceEffect(exactAmount, currencyType)
end)


-- PortalController
-- Location: StarterPlayer > StarterPlayerScripts > PortalController

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")

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
local UpdateHUD        = ReplicatedStorage.RemoteEvents:WaitForChild("UpdateHUD")

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

-- ✨ FLIPBOOK ANIMATION SYSTEM
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

-- UI Setup (StatsPanel)
local StatsPanel = Instance.new("Frame")
StatsPanel.Name="StatsPanel"; StatsPanel.Size = UDim2.new(0.88, 0, 0.82, 0)
StatsPanel.Position = UDim2.new(0.5, 0, 0.5, 0)
StatsPanel.AnchorPoint = Vector2.new(0.5, 0.5)
StatsPanel.BackgroundColor3=T.panelBG; StatsPanel.BorderSizePixel=0
StatsPanel.Visible=false; StatsPanel.ZIndex=30; StatsPanel.ClipsDescendants=true
StatsPanel.Parent=mainHUD
Instance.new("UICorner",StatsPanel).CornerRadius=UDim.new(0,PR)

local sizeConstraint = Instance.new("UISizeConstraint")
sizeConstraint.MaxSize = Vector2.new(PW, PH) 
sizeConstraint.Parent = StatsPanel

local panelStroke=Instance.new("UIStroke"); panelStroke.Color=T.panelStroke; panelStroke.Thickness=2; panelStroke.Parent=StatsPanel

local HeaderBar=Instance.new("Frame"); HeaderBar.Size=UDim2.new(1,0,0,46); HeaderBar.BackgroundColor3=T.headerBG
HeaderBar.BorderSizePixel=0; HeaderBar.ZIndex=31; HeaderBar.Parent=StatsPanel
Instance.new("UICorner",HeaderBar).CornerRadius=UDim.new(0,PR)
local HeaderLabel=Instance.new("TextLabel"); HeaderLabel.Size=UDim2.new(1,-50,1,0); HeaderLabel.Position=UDim2.new(0,16,0,0)
HeaderLabel.BackgroundTransparency=1; HeaderLabel.Text="AREA TRAVEL"; HeaderLabel.TextColor3=T.headerText
HeaderLabel.TextScaled=true; HeaderLabel.Font=T.font; HeaderLabel.TextXAlignment=Enum.TextXAlignment.Left
HeaderLabel.ZIndex=32; HeaderLabel.Parent=HeaderBar
local CloseBtn=Instance.new("TextButton"); CloseBtn.Size=UDim2.new(0,32,0,32); CloseBtn.Position=UDim2.new(1,-40,0.5,-16)
CloseBtn.BackgroundColor3=T.buttonRed; CloseBtn.BorderSizePixel=0; CloseBtn.Text="X"; CloseBtn.TextColor3=T.bodyText
CloseBtn.TextScaled=true; CloseBtn.Font=T.font; CloseBtn.ZIndex=33; CloseBtn.Parent=HeaderBar
CloseBtn:SetAttribute("TutorialTarget", "PortalCloseBtn")
Instance.new("UICorner",CloseBtn).CornerRadius=UDim.new(0,6)

local ScrollContainer = Instance.new("ScrollingFrame")
ScrollContainer.Name = "ScrollContainer"
ScrollContainer.Size = UDim2.new(1, 0, 1, -46) 
ScrollContainer.Position = UDim2.new(0, 0, 0, 46) 
ScrollContainer.BackgroundTransparency = 1
ScrollContainer.BorderSizePixel = 0
ScrollContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
ScrollContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y 
ScrollContainer.ScrollBarThickness = 6
ScrollContainer.Parent = StatsPanel

local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 10) 
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center 
listLayout.Parent = ScrollContainer

local topPadding = Instance.new("UIPadding")
topPadding.PaddingTop = UDim.new(0, 10)
topPadding.PaddingBottom = UDim.new(0, 10)
topPadding.Parent = ScrollContainer

local GoalSection=Instance.new("Frame"); GoalSection.Size=UDim2.new(1,-24,0,90)
GoalSection.BackgroundColor3=T.cardBG; GoalSection.BorderSizePixel=0; GoalSection.ZIndex=31; GoalSection.Parent=ScrollContainer
Instance.new("UICorner",GoalSection).CornerRadius=UDim.new(0,8)
local FarmEvalTitle=Instance.new("TextLabel"); FarmEvalTitle.Size=UDim2.new(1,-12,0,16); FarmEvalTitle.Position=UDim2.new(0,12,0,6)
FarmEvalTitle.BackgroundTransparency=1; FarmEvalTitle.Text="FARM EVALUATION"; FarmEvalTitle.TextColor3=T.subText
FarmEvalTitle.TextScaled=true; FarmEvalTitle.Font=T.font; FarmEvalTitle.TextXAlignment=Enum.TextXAlignment.Left
FarmEvalTitle.ZIndex=32; FarmEvalTitle.Parent=GoalSection
local FarmEvalNumber=Instance.new("TextLabel"); FarmEvalNumber.Name="FarmEvalNumber"
FarmEvalNumber.Size=UDim2.new(1,-12,0,28); FarmEvalNumber.Position=UDim2.new(0,12,0,22)
FarmEvalNumber.BackgroundTransparency=1; FarmEvalNumber.Text="$0"; FarmEvalNumber.TextColor3=T.accentGreen
FarmEvalNumber.TextScaled=true; FarmEvalNumber.Font=T.font; FarmEvalNumber.TextXAlignment=Enum.TextXAlignment.Left
FarmEvalNumber.ZIndex=32; FarmEvalNumber.Parent=GoalSection
local ProgressBG=Instance.new("Frame"); ProgressBG.Size=UDim2.new(1,-24,0,8); ProgressBG.Position=UDim2.new(0,12,0,54)
ProgressBG.BackgroundColor3=Color3.fromRGB(40,50,70); ProgressBG.BorderSizePixel=0; ProgressBG.ZIndex=32; ProgressBG.Parent=GoalSection
Instance.new("UICorner",ProgressBG).CornerRadius=UDim.new(0,4)
local ProgressFill=Instance.new("Frame"); ProgressFill.Name="ProgressFill"; ProgressFill.Size=UDim2.new(0,0,1,0)
ProgressFill.BackgroundColor3=T.accentGreen; ProgressFill.BorderSizePixel=0; ProgressFill.ZIndex=33; ProgressFill.Parent=ProgressBG
Instance.new("UICorner",ProgressFill).CornerRadius=UDim.new(0,4)
local ProgressLabel=Instance.new("TextLabel"); ProgressLabel.Name="ProgressLabel"
ProgressLabel.Size=UDim2.new(1,-12,0,14); ProgressLabel.Position=UDim2.new(0,12,0,66)
ProgressLabel.BackgroundTransparency=1; ProgressLabel.Text=""; ProgressLabel.TextColor3=T.subText
ProgressLabel.TextScaled=true; ProgressLabel.Font=T.fontBody; ProgressLabel.TextXAlignment=Enum.TextXAlignment.Left
ProgressLabel.ZIndex=32; ProgressLabel.Parent=GoalSection

local AreaBrowser=Instance.new("Frame"); AreaBrowser.Size=UDim2.new(1,-24,0,260)
AreaBrowser.BackgroundColor3=T.cardBG; AreaBrowser.BorderSizePixel=0; AreaBrowser.ZIndex=31; AreaBrowser.Parent=ScrollContainer
Instance.new("UICorner",AreaBrowser).CornerRadius=UDim.new(0,8)
local BrowseAreaName=Instance.new("TextLabel"); BrowseAreaName.Size=UDim2.new(0.6, 0, 0, 24)
BrowseAreaName.AnchorPoint=Vector2.new(0.5, 0)
BrowseAreaName.Position=UDim2.new(0.5, 0, 0, 8)
BrowseAreaName.BackgroundTransparency=1; BrowseAreaName.Text="Starter Area"; BrowseAreaName.TextColor3=T.accentBlue
BrowseAreaName.TextScaled=true; BrowseAreaName.Font=T.font; BrowseAreaName.TextXAlignment=Enum.TextXAlignment.Center
BrowseAreaName.ZIndex=32; BrowseAreaName.Parent=AreaBrowser
local AreaIndexLabel=Instance.new("TextLabel"); AreaIndexLabel.Size=UDim2.new(0,60,0,20); AreaIndexLabel.Position=UDim2.new(1,-66,0,10)
AreaIndexLabel.BackgroundTransparency=1; AreaIndexLabel.Text="1/5"; AreaIndexLabel.TextColor3=T.subText
AreaIndexLabel.TextScaled=true; AreaIndexLabel.Font=T.fontBody; AreaIndexLabel.TextXAlignment=Enum.TextXAlignment.Right
AreaIndexLabel.ZIndex=32; AreaIndexLabel.Parent=AreaBrowser
local BrowseAreaMult=Instance.new("TextLabel"); BrowseAreaMult.Size=UDim2.new(1,-20,0,18); BrowseAreaMult.Position=UDim2.new(0,10,0,34)
BrowseAreaMult.BackgroundTransparency=1; BrowseAreaMult.Text="Cube Value: 1.0x base"; BrowseAreaMult.TextColor3=T.accentGold
BrowseAreaMult.TextScaled=true; BrowseAreaMult.Font=T.fontBody; BrowseAreaMult.TextXAlignment=Enum.TextXAlignment.Center
BrowseAreaMult.ZIndex=32; BrowseAreaMult.Parent=AreaBrowser
local LeftArrow=Instance.new("TextButton"); LeftArrow.Size=UDim2.new(0,36,0,36); LeftArrow.Position=UDim2.new(0,8,0,62)
LeftArrow.BackgroundColor3=T.headerBG; LeftArrow.BorderSizePixel=0; LeftArrow.Text="<"; LeftArrow.TextColor3=T.bodyText
LeftArrow.TextScaled=true; LeftArrow.Font=T.font; LeftArrow.ZIndex=33; LeftArrow.Parent=AreaBrowser
Instance.new("UICorner",LeftArrow).CornerRadius=UDim.new(0,18)
local RightArrow=Instance.new("TextButton"); RightArrow.Size=UDim2.new(0,36,0,36); RightArrow.Position=UDim2.new(1,-44,0,62)
RightArrow.BackgroundColor3=T.headerBG; RightArrow.BorderSizePixel=0; RightArrow.Text=">"; RightArrow.TextColor3=T.bodyText
RightArrow.TextScaled=true; RightArrow.Font=T.font; RightArrow.ZIndex=33; RightArrow.Parent=AreaBrowser
RightArrow:SetAttribute("TutorialTarget", "ArrowBtn")
Instance.new("UICorner",RightArrow).CornerRadius=UDim.new(0,18)
local AreaIcon = Instance.new("ImageLabel")
AreaIcon.Name = "AreaIcon" 
AreaIcon.AnchorPoint = Vector2.new(0.5, 0)
AreaIcon.Size = UDim2.new(0, 110, 0, 110)
AreaIcon.Position = UDim2.new(0.5, 0, 0, 54)
AreaIcon.BackgroundTransparency = 1
AreaIcon.BorderSizePixel = 0
AreaIcon.ZIndex = 33
AreaIcon.Image = "" 
AreaIcon.Parent = AreaBrowser
local BrowseStatus=Instance.new("TextLabel"); BrowseStatus.Size=UDim2.new(1,-24,0,20); BrowseStatus.Position=UDim2.new(0,12,0,172)
BrowseStatus.BackgroundTransparency=1; BrowseStatus.Text="CURRENT AREA"; BrowseStatus.TextColor3=T.subText
BrowseStatus.TextScaled=true; BrowseStatus.Font=T.font; BrowseStatus.TextXAlignment=Enum.TextXAlignment.Center
BrowseStatus.ZIndex=32; BrowseStatus.Parent=AreaBrowser
local BrowseProgress=Instance.new("TextLabel"); BrowseProgress.Size=UDim2.new(1,-24,0,28); BrowseProgress.Position=UDim2.new(0,12,0,194)
BrowseProgress.BackgroundTransparency=1; BrowseProgress.Text=""; BrowseProgress.TextColor3=T.subText
BrowseProgress.TextScaled=true; BrowseProgress.Font=T.fontBody; BrowseProgress.TextWrapped=true
BrowseProgress.TextXAlignment=Enum.TextXAlignment.Center; BrowseProgress.ZIndex=32; BrowseProgress.Parent=AreaBrowser
local TravelBtn=Instance.new("TextButton"); TravelBtn.Size=UDim2.new(1,-24,0,38); TravelBtn.Position=UDim2.new(0,12,0,220)
TravelBtn.BackgroundColor3=T.buttonGreen; TravelBtn.BorderSizePixel=0; TravelBtn.Text="TRAVEL"; TravelBtn.TextColor3=T.bodyText
TravelBtn.TextScaled=true; TravelBtn.Font=T.font; TravelBtn.Visible=false; TravelBtn.ZIndex=33; TravelBtn.Parent=AreaBrowser
TravelBtn:SetAttribute("TutorialTarget", "TravelBtn")
Instance.new("UICorner",TravelBtn).CornerRadius=UDim.new(0,8)

local function AddButtonJuice(btn)
	local scale = btn:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", btn)
	btn.MouseEnter:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Sine), {Scale = 1.08}):Play() end)
	btn.MouseLeave:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Sine), {Scale = 1}):Play() end)
	btn.MouseButton1Down:Connect(function() TweenService:Create(scale, TweenInfo.new(0.1, Enum.EasingStyle.Sine), {Scale = 0.9}):Play() end)
	btn.MouseButton1Up:Connect(function() TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), {Scale = 1.08}):Play() end)
end

AddButtonJuice(LeftArrow)
AddButtonJuice(RightArrow)
AddButtonJuice(TravelBtn)
AddButtonJuice(CloseBtn)

TravelBtn.MouseButton1Down:Connect(function()
	if browseIndex == currentArea then return end
	TravelToArea:FireServer(browseIndex)
end)

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
	RightArrow.Visible = AreaRegistry.Get(idx+1) ~= nil

	local highestUnlocked = 1
	for _, v in ipairs(unlockedAreas) do
		if v > highestUnlocked then highestUnlocked = v end
	end

	local unlockReq = areaData.threshold or 0
	local discReq = areaData.discoveryThreshold or (unlockReq * 0.25) 

	if idx <= highestUnlocked then
		local flipbookData = AreaRegistry.GetFlipbook(idx)
		if flipbookData then
			StartFlipbook(idx, AreaIcon)
			AreaIcon.ImageColor3 = Color3.fromRGB(255, 255, 255)
		else
			StopFlipbook()
			-- ✨ Check for static `icon` first, then fallback to `auraPreviewImage`
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
				-- ✨ Static Icon Fallback
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
				-- ✨ Static Icon Fallback + Color Consistency Fix
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
			-- ✨ Static Icon Fallback
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
		-- ✨ Static Icon Fallback
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

LeftArrow.MouseButton1Down:Connect(function()
	if browseIndex > 1 then browseIndex -= 1; PlayUI(SoundConfig.UIArrow); RefreshBrowser() end
end)
RightArrow.MouseButton1Down:Connect(function()
	if AreaRegistry.Get(browseIndex+1) then browseIndex += 1; PlayUI(SoundConfig.UIArrow); RefreshBrowser() end
end)

local StatsBtn=Instance.new("TextButton"); StatsBtn.Name="NextAreaButton"
StatsBtn.Size=UDim2.new(0,C.HUD.NextAreaButtonW,0,C.HUD.NextAreaButtonH)
StatsBtn.Position=UDim2.new(0,156,1,C.HUD.BottomButtonY)
StatsBtn.BackgroundColor3=T.headerBG; StatsBtn.BorderSizePixel=0
StatsBtn.Text="Next Area"; StatsBtn.TextColor3=T.bodyText; StatsBtn.TextScaled=true; StatsBtn.Font=T.font
StatsBtn.Visible = false
StatsBtn.ZIndex=10; StatsBtn.Parent=mainHUD
StatsBtn:SetAttribute("TutorialTarget", "AreaTravelButton")
Instance.new("UICorner",StatsBtn).CornerRadius=UDim.new(0,8)
AddButtonJuice(StatsBtn)

local function OpenPanel()
	panelOpen=true; browseIndex=currentArea; UpdateGoalSection(); RefreshBrowser()
	StatsPanel.Visible=true
	StatsPanel.Size=UDim2.new(0.88, 0, 0, 0)
	TweenService:Create(StatsPanel, TweenInfo.new(0.35,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
		{ Size=UDim2.new(0.88, 0, 0.82, 0) }):Play()
	UITheme.SetMenuVisible(true)
end

local function ClosePanel()
	panelOpen=false; StopFlipbook(); PlayUI(SoundConfig.UIClose)
	TweenService:Create(StatsPanel, TweenInfo.new(0.25,Enum.EasingStyle.Quad,Enum.EasingDirection.In),
		{ Size=UDim2.new(0.88, 0, 0, 0) }):Play()
	UITheme.SetMenuVisible(false)
	task.delay(0.3, function() StatsPanel.Visible=false end)
end
StatsBtn.MouseButton1Down:Connect(function() if panelOpen then ClosePanel() else OpenPanel() end end)
CloseBtn.MouseButton1Down:Connect(ClosePanel)

local function ShowAreaBanner(info)
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

UpdateHUD.OnClientEvent:Connect(function(stats)
	if stats.farmEvaluation ~= nil then liveFarmEval = stats.farmEvaluation end
	if panelOpen then UpdateGoalSection(); RefreshBrowser() end
end)

AreaUpdated.OnClientEvent:Connect(function(info)
	currentArea = info.currentArea or 1
	if currentArea > 1 then player:SetAttribute("TutorialCompleted", true) end
	portalReady = info.portalReady == true
	if info.unlockedAreas then unlockedAreas = info.unlockedAreas end
	MAX_AREA = info.maxArea or AreaRegistry.GetMaxArea()
	if info.portalReady then AddPortalPrompt() else RemovePortalPrompt() end
	if panelOpen then UpdateGoalSection(); RefreshBrowser() end
end)

AreaUnlocked.OnClientEvent:Connect(function(info)
	portalReady = true; AddPortalPrompt()
	if info.unlockedAreas then unlockedAreas = info.unlockedAreas end
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
		if panelOpen then ClosePanel() end
	end
end)

AreaChanged.OnClientEvent:Connect(function(info)
	currentArea = info.newArea or currentArea; browseIndex = currentArea; portalReady = false
	if info.unlockedAreas then unlockedAreas = info.unlockedAreas end
	if panelOpen then ClosePanel() end
	ShowAreaBanner(info)
end)

function AddPortalPrompt()
	if promptAdded then return end; promptAdded = true
	local prompt=Instance.new("ProximityPrompt"); prompt.Name="PortalPrompt"; prompt.ObjectText="Portal"
	prompt.ActionText="Open Area Travel"; prompt.HoldDuration=0.5; prompt.MaxActivationDistance=12
	prompt.Parent=PositionPart
	prompt.Triggered:Connect(function(p) if p == player and not panelOpen then OpenPanel() end end)
end

function RemovePortalPrompt()
	promptAdded=false; local e=PositionPart:FindFirstChild("PortalPrompt"); if e then e:Destroy() end
end

local function RefreshLook()
	UITheme.Apply(StatsPanel, "Panel")
	UITheme.Apply(HeaderBar, "TitleBar")
	UITheme.Apply(GoalSection, "ShopCard")
	UITheme.Apply(AreaBrowser, "ShopCard")
	UITheme.Apply(HeaderBar, "Panel")
	UITheme.Apply(RightArrow, "Panel")
	UITheme.Apply(LeftArrow, "Panel")
	UITheme.Apply(StatsBtn, "Panel")
	UITheme.ApplyShine(AreaBrowser)
	UITheme.ApplyShine(GoalSection)
	UITheme.ApplyShine(StatsPanel)
	GoalSection.BackgroundColor3 = T.cardBG 
	AreaBrowser.BackgroundColor3 = T.cardBG
	local outerStroke = StatsPanel:FindFirstChildWhichIsA("UIStroke")
	if outerStroke then outerStroke.Color = Color3.fromRGB(255, 255, 255) end
end

task.wait(2)
RefreshLook()

-- ClickHandler
-- Location: StarterPlayer > StarterPlayerScripts > ClickHandler

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")

local AdminConfig = require(ReplicatedStorage.Modules.AdminConfig)
local UITheme = require(game:GetService("ReplicatedStorage").Modules.UITheme)
local AreaRegistry = require(ReplicatedStorage.Modules.AreaRegistry) 

-- [NEW] We import the global NumberFormatter so everything looks consistent!
local NumberFormatter = require(ReplicatedStorage.Modules.NumberFormatter)

local ProduceAura = ReplicatedStorage.RemoteEvents:WaitForChild("ProduceAura")
local AuraSpawned = ReplicatedStorage.RemoteEvents:WaitForChild("AuraSpawned")
local UpdateHatchery = ReplicatedStorage.RemoteEvents:WaitForChild("UpdateHatchery")
local ForceStopHold = ReplicatedStorage.RemoteEvents:WaitForChild("ForceStopHold")
local HabitatFull = ReplicatedStorage.RemoteEvents:WaitForChild("HabitatFull")
local UpdateMultiplier = ReplicatedStorage:WaitForChild("UpdateMultiplier")
local HabitatFullEvent = ReplicatedStorage:WaitForChild("HabitatFullEvent")
local CubeMutatedBatch = ReplicatedStorage.RemoteEvents:WaitForChild("CubeMutatedBatch")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local holding = false
local fireRate = AdminConfig.FireRate
local holdStart = nil
local hatcheryEmpty = false
local habitatFull = false

-- [NEW] Track the local interval to properly calculate the 3D per/sec labels
local currentPassiveInterval = AdminConfig.PassiveInterval

local ClickButton = playerGui:WaitForChild("MainHUD"):WaitForChild("ClickButton")
local HatcheryBar = playerGui:WaitForChild("MainHUD"):WaitForChild("HatcheryBar")
local HatcheryFill = HatcheryBar:WaitForChild("Fill")
local HatcheryLabel = HatcheryBar:WaitForChild("Label")

local clickScale = ClickButton:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", ClickButton)
local clickStroke = ClickButton:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke", ClickButton)
clickStroke.Color = Color3.fromRGB(255, 215, 0) -- Pure Gold
clickStroke.Thickness = 0
local basePos = ClickButton.Position
local tiltSide = 1

-- ✨ MILESTONE SYSTEM SETUP
local Camera = workspace.CurrentCamera
local defaultFOV = 70 
local lastMilestone = 1

local MilestoneData = AdminConfig.MilestoneData

local playerMultSpeed = 1.0 
local playerMaxTier = 5     
local lastTierIndex = 1

-- [FIXED] Replaced standalone formatter with the global module
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

local function CloneAuraModel(tierName, currentArea)
	currentArea = currentArea or 1
	local clone = AreaRegistry.FetchAuraModel(currentArea, tierName)
	if clone and not clone.PrimaryPart then
		warn("[Aura] Model '" .. tierName .. "' has no PrimaryPart set! Set PrimaryPart to the main BasePart for reliable positioning.")
	end
	return clone
end

local function CreatePlaceholderPart(color, glow)
	local part = Instance.new("Part")
	part.Size = Vector3.new(1.5, 1.5, 1.5)
	part.Color = color
	part.Anchored = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	if glow then
		local light = Instance.new("PointLight")
		light.Brightness = 3
		light.Range = 8
		light.Color = color
		light.Parent = part
	end
	return part
end

local function SpawnAuraInstance(tierName, color, glow, position, currentArea)
	local auraModel = CloneAuraModel(tierName, currentArea)
	if auraModel then
		auraModel:PivotTo(CFrame.new(position))
		auraModel.Parent = workspace
		if auraModel.PrimaryPart then
			auraModel.PrimaryPart.Anchored = false
			auraModel.PrimaryPart.CanCollide = true
		end
		return auraModel, true
	else
		local part = CreatePlaceholderPart(color, glow)
		part.Position = position
		part.Parent = workspace
		return part, false
	end
end

local function GetRootPart(instance)
	if instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart")
	end
	return instance
end

local function ScaleAura(instance, tierName, animated, fromTierName)
	local targetScale = TierScale[tierName] or 1.0
	local fromScale = fromTierName and (TierScale[fromTierName] or 1.0) or nil

	if instance:IsA("Model") then
		if animated then
			local scaleProxy = Instance.new("NumberValue")
			scaleProxy.Value = fromScale or 1.0

			local scaleTween = TweenService:Create(scaleProxy, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Value = targetScale
			})

			local conn
			conn = scaleProxy.Changed:Connect(function(val)
				if instance and instance.Parent then
					pcall(function() instance:ScaleTo(val) end)
				else
					conn:Disconnect()
				end
			end)

			scaleTween:Play()
			scaleTween.Completed:Connect(function()
				scaleProxy:Destroy()
				if conn then conn:Disconnect() end
			end)
		else
			pcall(function() instance:ScaleTo(targetScale) end)
		end
	elseif instance:IsA("BasePart") then
		local baseSize = 1.5
		local targetSize = Vector3.new(1, 1, 1) * (baseSize * targetScale)
		if animated then
			if fromScale then instance.Size = Vector3.new(1, 1, 1) * (baseSize * fromScale) end
			TweenService:Create(instance, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = targetSize
			}):Play()
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
			emitter.Enabled = true
			emitter:Emit(emitter:GetAttribute("BurstCount") or 15)
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

	local currentTier = 1
	local nextTier = 1

	for i = 1, playerMaxTier do
		if effectiveTime >= MilestoneData[i].time then
			currentTier = i
			nextTier = math.min(i + 1, playerMaxTier)
		end
	end

	if currentTier == playerMaxTier then
		return MilestoneData[currentTier].mult, currentTier
	end

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
		sfxToPlay = Instance.new("Sound")
		sfxToPlay.SoundId = soundValue
		sfxToPlay.Volume = 0.6
	else
		local sfxFolder = ReplicatedStorage:FindFirstChild("SFX") or ReplicatedStorage:FindFirstChild("Sounds")
		if sfxFolder then
			local foundSound = sfxFolder:FindFirstChild(soundValue)
			if foundSound then
				sfxToPlay = foundSound:Clone()
				sfxToPlay.Volume = 0.6
			end
		end
	end

	if sfxToPlay then
		sfxToPlay.Parent = game:GetService("SoundService")
		sfxToPlay:Play()
		Debris:AddItem(sfxToPlay, sfxToPlay.TimeLength > 0 and sfxToPlay.TimeLength or 3)
	end
end

local function SpawnMilestonePopup(multFloor)
	local data = MilestoneData[multFloor]
	if not data then return end 

	PlayMilestoneSound(data.sound)

	local pop = Instance.new("TextLabel")
	pop.Text = data.name .. " (" .. string.format("%.1f", data.mult) .. "x)"
	pop.Font = Enum.Font.FredokaOne 
	pop.TextScaled = true
	pop.TextColor3 = data.color
	pop.BackgroundTransparency = 1
	pop.AnchorPoint = Vector2.new(0.5, 0.5)

	pop.Position = UDim2.new(
		ClickButton.Position.X.Scale, ClickButton.Position.X.Offset, 
		ClickButton.Position.Y.Scale - 0.15, ClickButton.Position.Y.Offset
	)
	pop.Parent = ClickButton.Parent

	local stroke = Instance.new("UIStroke", pop)
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(0, 0, 0)
	pop.Size = UDim2.new(0.1, 0, 0.02, 0) 

	TweenService:Create(pop, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0.35, 0, 0.08, 0),
		Position = UDim2.new(
			pop.Position.X.Scale, pop.Position.X.Offset, 
			ClickButton.Position.Y.Scale - 0.25, ClickButton.Position.Y.Offset
		)
	}):Play()

	task.delay(0.6, function()
		TweenService:Create(pop, TweenInfo.new(0.3), {TextTransparency = 1}):Play()
		TweenService:Create(stroke, TweenInfo.new(0.3), {Transparency = 1}):Play()
		task.delay(0.3, function() pop:Destroy() end)
	end)
end

local function UpdateButtonVisual()
	local col
	local mult = 1
	local currentTierIndex = 1

	if habitatFull then
		col = Color3.fromRGB(180, 60, 60)
	elseif not holding then
		col = Color3.fromRGB(255, 0, 0)
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
	else
		lastTierIndex = 1
	end

	TweenService:Create(ClickButton, TweenInfo.new(0.2), { BackgroundColor3 = col }):Play()

	if holding and not habitatFull then
		tiltSide = tiltSide * -1 
		if mult >= 5.0 then 
			TweenService:Create(ClickButton, TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true), {
				Rotation = 8 * tiltSide
			}):Play()
			clickStroke.Thickness = 12
			clickStroke.Transparency = 0
			TweenService:Create(clickStroke, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Thickness = 0, Transparency = 1}):Play()
		else
			TweenService:Create(ClickButton, TweenInfo.new(0.08, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, true), {
				Rotation = 3 * tiltSide
			}):Play()
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
	local anchor = Instance.new("Part")
	anchor.Size = Vector3.new(0.1, 0.1, 0.1); anchor.Anchored = true; anchor.Transparency = 1; anchor.CanCollide = false
	anchor.Position = position + Vector3.new(0, 3, 0); anchor.Parent = workspace

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 120, 0, 40); bb.StudsOffset = Vector3.new(0, 2, 0)
	bb.AlwaysOnTop = false; bb.Adornee = anchor; bb.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0); label.BackgroundTransparency = 1
	label.Text = tierName:upper(); label.TextColor3 = tierColor; label.TextScaled = true
	label.Font = Enum.Font.GothamBold; label.TextStrokeTransparency = 0.3; label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.Parent = bb

	TweenService:Create(bb, TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffset = Vector3.new(0, 6, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(anchor, 2)
end

local function ShowCubeValue(position, value, color)
	local anchor = Instance.new("Part")
	anchor.Size = Vector3.new(0.1, 0.1, 0.1); anchor.Anchored = true; anchor.Transparency = 1; anchor.CanCollide = false
	anchor.Position = position + Vector3.new(math.random(-1, 1), 2, math.random(-1, 1)); anchor.Parent = workspace

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 80, 0, 25); bb.StudsOffset = Vector3.new(0, 0, 0)
	bb.AlwaysOnTop = false; bb.Adornee = anchor; bb.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0); label.BackgroundTransparency = 1
	-- Keep this white/gold to differentiate it from the green passive income
	label.Text = "Value: $" .. FormatNumber(value); label.TextColor3 = Color3.fromRGB(255, 255, 255); label.TextScaled = true
	label.Font = Enum.Font.Gotham; label.TextStrokeTransparency = 0.4; label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.Parent = bb

	TweenService:Create(bb, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffset = Vector3.new(0, 4, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(anchor, 1.5)
end

-- [NEW] This creates the PERMANENT rate label directly over the 3D Object!
local function AttachPermanentRateLabel(auraInstance, baseValue)
	local rootPart = GetRootPart(auraInstance)
	if not rootPart then return end

	local bb = Instance.new("BillboardGui")
	bb.Name = "PermanentRateLabel"
	bb.Size = UDim2.new(0, 90, 0, 25)
	bb.StudsOffset = Vector3.new(0, 3.5, 0) -- Adjust height hovering above the aura
	bb.AlwaysOnTop = false
	bb.Adornee = rootPart

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1

	-- Calculate rate using exactly what the HUD uses
	local ratePerSec = baseValue / currentPassiveInterval
	label.Text = "+$" .. FormatNumber(ratePerSec) .. "/sec"

	label.TextColor3 = Color3.fromRGB(100, 255, 100) -- Passive Green
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextStrokeTransparency = 0.4
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.Parent = bb

	bb.Parent = rootPart
	return label
end

---------------------------------------------------------------
-- INPUT CONTROLS
---------------------------------------------------------------
local trackedInputs = {}

local function EvaluateHolding()
	local hasInput = false
	for _, _ in pairs(trackedInputs) do hasInput = true; break end

	if hasInput and not holding then
		if hatcheryEmpty then FlashEmpty() return end
		if habitatFull then return end
		holding = true
		holdStart = tick()
		TweenService:Create(clickScale, TweenInfo.new(0.1, Enum.EasingStyle.Sine), {Scale = 0.9}):Play()
		ProduceAura:FireServer("start")
	elseif not hasInput and holding then
		holding = false
		holdStart = nil
		ProduceAura:FireServer("stop")
		UpdateButtonVisual()
		UpdateMultiplier:Fire(1.0)
	end
end

ClickButton.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		trackedInputs[input] = true; EvaluateHolding()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if trackedInputs[input] then trackedInputs[input] = nil; EvaluateHolding() end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if input.KeyCode == Enum.KeyCode.Space and not UserInputService:GetFocusedTextBox() then
		trackedInputs[input] = true; EvaluateHolding()
	end
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
	if not isFull then habitatFull = false; UpdateButtonVisual() end
end)

UpdateHatchery.OnClientEvent:Connect(function(info)
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

ReplicatedStorage.RemoteEvents:WaitForChild("UpdateHUD").OnClientEvent:Connect(function(stats)
	-- [NEW] Keep track of the current interval so the labels are accurate
	if stats.passiveInterval ~= nil then
		currentPassiveInterval = stats.passiveInterval
	end

	if stats.pendingAuras and stats.habitatCapacity then
		if stats.pendingAuras < stats.habitatCapacity and habitatFull then
			habitatFull = false; HabitatFullEvent:Fire(false); UpdateButtonVisual()
		end
	end

	if stats.upgrades then
		local tierUnlocks = {
			{ upgradeId = "unlockOmniMult",      tier = 10 },
			{ upgradeId = "unlockUniversalMult", tier = 9 },
			{ upgradeId = "unlockGodlyMult",     tier = 8 },
			{ upgradeId = "unlockCosmicMult",    tier = 7 },
			{ upgradeId = "unlockMythicMult",    tier = 6 },
		}

		local calculatedMaxTier = 5 
		for _, data in ipairs(tierUnlocks) do
			local upgData = stats.upgrades[data.upgradeId]
			local level = (typeof(upgData) == "table" and upgData.level) or (typeof(upgData) == "number" and upgData) or 0
			if level > 0 then calculatedMaxTier = data.tier; break end
		end

		playerMaxTier = calculatedMaxTier

		local speedData = stats.upgrades["multiplierSpeed"]
		local speedLevel = (typeof(speedData) == "table" and speedData.level) or (typeof(speedData) == "number" and speedData) or 0
		playerMultSpeed = 1.0 + (speedLevel * 0.05) 
	end
end)

task.spawn(function()
	while true do
		if holding then
			if hatcheryEmpty or habitatFull then
				table.clear(trackedInputs); EvaluateHolding()
			else
				ProduceAura:FireServer(); UpdateButtonVisual()
			end
		end
		task.wait(fireRate)
	end
end)

---------------------------------------------------------------
-- AURA MUTATION RESPONSES (CLIENT BOUND)
---------------------------------------------------------------
AuraSpawned.OnClientEvent:Connect(function(info)
	local instance, isCustom = SpawnAuraInstance(info.tier, info.color, info.glow, info.spawnPos, info.currentArea)

	instance:SetAttribute("AuraCube", true)
	ScaleAura(instance, info.tier, false)
	ShowCubeValue(info.spawnPos, info.value, info.color)
	PlayVFX("Spawn", info.spawnPos, 1.0)

	-- [NEW] Attach the permanent rate label right as it spawns!
	local permLabel = AttachPermanentRateLabel(instance, info.value)

	if info.tier == "Legendary" then
		ShowTierPopup(info.spawnPos, "Legendary", Color3.fromRGB(255, 200, 0))
		PlayVFX("Legendary", info.spawnPos, 2.0)
	end

	if info.cubeId then
		cubeDataMap[info.cubeId] = { 
			instance = instance, 
			tierName = info.tier, 
			isCustom = isCustom,
			rateLabel = permLabel -- Save it in case we want to update it later
		}
		instance.AncestryChanged:Connect(function(_, parent)
			if not parent then cubeDataMap[info.cubeId] = nil end
		end)
	end
end)

CubeMutatedBatch.OnClientEvent:Connect(function(batchData)
	for _, info in ipairs(batchData) do
		local cubeData = cubeDataMap[info.cubeId]
		if not cubeData then continue end 

		local instance = cubeData.instance
		if not instance or not instance.Parent then continue end 

		local rootPart = GetRootPart(instance)
		if not rootPart then continue end 
		local position = rootPart.Position

		if info.mutationType == "tierUpgrade" then
			PlayVFX("TierUpgrade", position, 1.5)
			if info.tierName == "Legendary" then PlayVFX("Legendary", position, 2.0) end

			local oldTierName = cubeData.tierName
			local newAura = CloneAuraModel(info.tierName, info.currentArea)

			if newAura then
				newAura:PivotTo(CFrame.new(position))
				newAura.Parent = workspace
				newAura:SetAttribute("AuraCube", true)

				if newAura.PrimaryPart then
					newAura.PrimaryPart.Anchored = false
					newAura.PrimaryPart.CanCollide = true
				end

				ScaleAura(newAura, info.tierName, true, oldTierName)

				-- [NEW] We need to transplant the rate label to the new mutated model!
				if cubeData.rateLabel and cubeData.rateLabel.Parent then
					cubeData.rateLabel.Adornee = GetRootPart(newAura)
					cubeData.rateLabel.Parent = GetRootPart(newAura)
				end

				-- Safely destroy the old model
				instance:Destroy()

				cubeData.instance = newAura
				cubeData.tierName = info.tierName
				cubeData.isCustom = true

				newAura.AncestryChanged:Connect(function(_, parent)
					if not parent then cubeDataMap[info.cubeId] = nil end
				end)
			else
				if rootPart:IsA("BasePart") then
					TweenService:Create(rootPart, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { Color = info.newColor }):Play()
					if info.newGlow then
						local light = rootPart:FindFirstChildOfClass("PointLight")
						if not light then light = Instance.new("PointLight"); light.Parent = rootPart end
						TweenService:Create(light, TweenInfo.new(0.5), { Brightness = 3, Range = 8, Color = info.newColor }):Play()
					end
					ScaleAura(instance, info.tierName, true, oldTierName)
				end
				cubeData.tierName = info.tierName
			end
			ShowTierPopup(position, info.tierName, info.newColor)
		end
	end
end)

---------------------------------------------------------------
-- HUD BUTTON POLISH
---------------------------------------------------------------
local function AddBasicJuice(btn)
	if not btn then return end
	local scale = btn:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", btn)
	btn.MouseEnter:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15), {Scale = 1.08}):Play() end)
	btn.MouseLeave:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15), {Scale = 1}):Play() end)
	btn.MouseButton1Down:Connect(function() TweenService:Create(scale, TweenInfo.new(0.1), {Scale = 0.9}):Play() end)
	btn.MouseButton1Up:Connect(function() TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), {Scale = 1.08}):Play() end)
end

AddBasicJuice(playerGui:WaitForChild("MainHUD"):FindFirstChild("ModeToggle"))
AddBasicJuice(playerGui:WaitForChild("MainHUD"):FindFirstChild("SendButton"))

ReplicatedStorage.RemoteEvents.UpgradeUpdated.OnClientEvent:Connect(function(info)
	if not info or not info.upgrades then return end
	local speedData = info.upgrades["multiplierSpeed"]
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
		local upgData = info.upgrades[data.upgradeId]
		local level = (typeof(upgData) == "table" and upgData.level) or (typeof(upgData) == "number" and upgData) or 0

		if level > 0 then
			calculatedMaxTier = data.tier
			break
		end
	end

	playerMaxTier = calculatedMaxTier
end)

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

local HABITAT_HOLDER = workspace:WaitForChild("HabitatHolder")
local HABITAT_PART   = HABITAT_HOLDER:WaitForChild("Position")
local lastFire          = {}
local holdStart         = {}
local hatchery          = {}
local clickSessionStart = {}

-- Helper to safely retrieve the current area's defined aura models
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

-- Continuous Hatchery Tick Thread
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

-- Continuous Mutation Tick Thread
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

					-- PREVENT MUTATING INTO UNDEFINED TIERS
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

						-- [NEW] We are including currentArea for the Client mutation visuals
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
			if areaModels[checkName] then
				break
			end
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

	-- [NEW] We are including currentArea for the Client to use!
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
		if data and runtime and runtime.cubeCount >= GetHabitatCapacity(data) then
			HabitatFull:FireClient(player)
			return
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
	if runtime.cubeCount >= GetHabitatCapacity(data) then HabitatFull:FireClient(player); return end
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

-- ShippingManager
-- Location: ServerScriptService > ShippingManager

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local HttpService         = game:GetService("HttpService")

local AdminConfig      = require(ReplicatedStorage.Modules.AdminConfig)
local UpgradeConfig    = require(ReplicatedStorage.Modules.UpgradeConfig)
local MutationConfig   = require(ReplicatedStorage.Modules.MutationConfig)
local GameManager      = require(ServerScriptService.GameManager)
local EpicUpgradeConfig = require(ReplicatedStorage.Modules.EpicUpgradeConfig)

local ShipAuras = ReplicatedStorage.RemoteEvents:WaitForChild("ShipAuras")
local UpdateHUD = ReplicatedStorage.RemoteEvents:WaitForChild("UpdateHUD")

local playerTimers   = {}
local activeTrucks   = {}
local playerAutoMode = {}
local pendingPayouts = {}

-- ─────────────────────────────────────────────────────────────────────────────
-- PLAYER LIFECYCLE
-- ─────────────────────────────────────────────────────────────────────────────
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

-- ─────────────────────────────────────────────────────────────────────────────
-- HUD UPDATE HELPER
-- ─────────────────────────────────────────────────────────────────────────────
local function SendHUDUpdate(player)
	local uid     = player.UserId
	local data    = GameManager.GetData(uid)
	local runtime = GameManager.GetRuntime(uid)
	if not data or not runtime then return end

	local totalMutatedValue = runtime.totalMutatedValue
	local pending           = runtime.cubeCount
	local avgValue          = pending > 0 and (totalMutatedValue / pending) or AdminConfig.BaseAuraValue
	local rate              = math.floor(pending * avgValue)

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
		pendingAuras    = pending,
		habitatCapacity = habitatCap,
		rate            = rate,
		passiveInterval = passiveInt,
		totalEarned     = data.totalEarned    or 0,
		soulAuras       = data.soulAuras      or 0,
		farmEvaluation  = data.farmEvaluation or 0,
		shipCooldown    = finalCooldown,
	})
end

-- ─────────────────────────────────────────────────────────────────────────────
-- DISPATCH
-- ─────────────────────────────────────────────────────────────────────────────
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
	for _, cube in ipairs(cubes) do
		totalPayout = totalPayout + MutationConfig.GetMutatedValue(cube)
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
end

-- ─────────────────────────────────────────────────────────────────────────────
-- SERVER EVENT
-- ─────────────────────────────────────────────────────────────────────────────
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

-- AreaTransitionController
-- Location: StarterPlayer > StarterPlayerScripts > AreaTransitionController
--
-- PER-AREA AURA PLACEMENT:
--   yOffset   = studs up/down from Position Part  (e.g. 5 = 5 studs above)
--   yRotation = degrees of Y-axis rotation        (e.g. 90 = quarter turn)
--   Both set in AreaRegistry per area.
--
-- AURA MODEL LOOKUP ORDER:
--   1. ReplicatedStorage/AreaAssets/Area{N}/AuraModel
--   2. workspace/Map/Ignore/Area{N}Aura
--
-- ALL TweenService:Create calls wrapped in pcall.
-- activeSwap has 10s timeout — no permanent deadlock.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local Lighting          = game:GetService("Lighting")

local AreaRegistry = require(ReplicatedStorage.Modules.AreaRegistry)

-- ✨ NEW: Import the custom VFX API
local VFX_API = require(ReplicatedStorage:WaitForChild("vfx"))

local AreaChanged = ReplicatedStorage.RemoteEvents:WaitForChild("AreaChanged")
local AreaUpdated = ReplicatedStorage.RemoteEvents:WaitForChild("AreaUpdated")

local Map        = workspace:WaitForChild("Map")
local AuraHolder = workspace:WaitForChild("AuraHolder")
local HabitatHolder = workspace:WaitForChild("HabitatHolder") 
local AreaAssets = ReplicatedStorage:WaitForChild("AreaAssets")
local MapIgnore  = Map:FindFirstChild("Ignore")
local HabitatPositionPart = HabitatHolder:WaitForChild("Position") 
local PositionPart = AuraHolder:WaitForChild("Position")

local DECORATION_CONTAINER = Map:WaitForChild("Path")

local TWEEN_DURATION = 2.5
local FADE_DURATION  = 0.5
local SWAP_TIMEOUT   = 10

local MAP_PART_COLORS = {
	Floor      = "grassColor",
	AssetFloor = "grassColor",
	Path       = "pathColor",
}

local currentAuraModel = nil
local activeSwap       = false
local swapStartedAt    = 0

---------------------------------------------------------------
-- SAFE TWEEN
---------------------------------------------------------------
local function SafeTween(instance, tweenInfo, properties)
	pcall(function()
		TweenService:Create(instance, tweenInfo, properties):Play()
	end)
end

---------------------------------------------------------------
-- TRANSPARENCY HELPERS
---------------------------------------------------------------
local function SetTransparency(obj, alpha)
	if obj:IsA("BasePart") then
		pcall(function() obj.Transparency = alpha end)
	elseif obj:IsA("Model") then
		for _, p in ipairs(obj:GetDescendants()) do
			if p:IsA("BasePart") then
				pcall(function() p.Transparency = alpha end)
			end
		end
	end
end

local function TweenTransparency(obj, alpha, duration)
	local info   = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	local tweens = {}
	local parts  = {}
	if obj:IsA("BasePart") then
		table.insert(parts, obj)
	elseif obj:IsA("Model") then
		for _, p in ipairs(obj:GetDescendants()) do
			if p:IsA("BasePart") then table.insert(parts, p) end
		end
	end
	for _, part in ipairs(parts) do
		local ok, t = pcall(function()
			return TweenService:Create(part, info, { Transparency = alpha })
		end)
		if ok and t then t:Play(); table.insert(tweens, t) end
	end
	return tweens
end

---------------------------------------------------------------
-- PLACE AT POSITION WITH OFFSET + ROTATION
-- Builds a CFrame from Position Part + yOffset + yRotation.
--   yOffset   = studs along world Y axis
--   yRotation = degrees around world Y axis
---------------------------------------------------------------
local function PlaceAtPosition(obj, yOffset, yRotation)
	local pos      = PositionPart.Position + Vector3.new(0, yOffset or 0, 0)
	local rotation = CFrame.Angles(0, math.rad(yRotation or 0), 0)
	local targetCF = CFrame.new(pos) * rotation

	pcall(function()
		if obj:IsA("Model") then
			obj:PivotTo(targetCF)
		elseif obj:IsA("BasePart") then
			obj.CFrame = targetCF
		end
	end)
end

---------------------------------------------------------------
-- AURA MODEL LOOKUP
---------------------------------------------------------------
local function GetAuraTemplate(areaIndex)
	local folder  = AreaAssets:FindFirstChild("Area" .. areaIndex)
	local rsModel = folder and folder:FindFirstChild("AuraModel")
	if rsModel then return rsModel end

	if MapIgnore then
		local ignoreModel = MapIgnore:FindFirstChild("Area" .. areaIndex .. "Aura")
		if ignoreModel then return ignoreModel end
	end

	warn("[AreaTransition] No AuraModel for area " .. areaIndex
		.. " — checked AreaAssets/Area" .. areaIndex .. "/AuraModel"
		.. " and Map/Ignore/Area" .. areaIndex .. "Aura")
	return nil
end

---------------------------------------------------------------
-- AURA HOLDER SWAP
---------------------------------------------------------------
local function SwapAuraHolder(areaIndex, instant)
	local template = GetAuraTemplate(areaIndex)
	if not template then
		warn("[AreaTransition] Skipping swap — no template for area " .. areaIndex)
		return
	end

	local yOffset   = AreaRegistry.GetYOffset(areaIndex)
	local yRotation = AreaRegistry.GetYRotation(areaIndex)

	if instant then
		for _, child in ipairs(AuraHolder:GetChildren()) do
			if child ~= PositionPart then 
				-- ✨ NEW: Disable old custom VFX before destroying the part
				pcall(function() VFX_API.disable(child) end)
				child:Destroy() 
			end
		end
		currentAuraModel = nil

		local newModel = template:Clone()
		newModel.Parent = AuraHolder
		PlaceAtPosition(newModel, yOffset, yRotation)
		currentAuraModel = newModel

		-- ✨ NEW: Instantly enable the custom VFX once placed in Workspace
		pcall(function() VFX_API.enable(newModel) end)

	else
		if activeSwap and (tick() - swapStartedAt) < SWAP_TIMEOUT then return end
		activeSwap    = true
		swapStartedAt = tick()

		task.spawn(function()
			if currentAuraModel and currentAuraModel.Parent then
				-- ✨ NEW: Disable old custom VFX smoothly as the model fades out
				pcall(function() VFX_API.disable(currentAuraModel) end)

				local outTweens = TweenTransparency(currentAuraModel, 1, FADE_DURATION)
				if #outTweens > 0 then
					outTweens[1].Completed:Wait()
				else
					task.wait(FADE_DURATION)
				end
				if currentAuraModel and currentAuraModel.Parent then
					currentAuraModel:Destroy()
				end
				currentAuraModel = nil
			else
				task.wait(FADE_DURATION)
			end

			local newModel = template:Clone()
			newModel.Parent = AuraHolder
			PlaceAtPosition(newModel, yOffset, yRotation)
			SetTransparency(newModel, 1)
			currentAuraModel = newModel

			-- ✨ NEW: Turn on the new custom VFX so it begins while fading in
			pcall(function() VFX_API.enable(newModel) end)

			TweenTransparency(newModel, 0, FADE_DURATION)

			task.wait(FADE_DURATION)
			activeSwap = false
		end)
	end
end

---------------------------------------------------------------
-- HABITAT MODEL LOOKUP
---------------------------------------------------------------
local function GetHabitatTemplate(areaIndex)
	local folder  = AreaAssets:FindFirstChild("Area" .. areaIndex)
	local rsModel = folder and folder:FindFirstChild("HabitatModel")
	if rsModel then return rsModel end

	if MapIgnore then
		local ignoreModel = MapIgnore:FindFirstChild("Area" .. areaIndex .. "Habitat")
		if ignoreModel then return ignoreModel end
	end

	warn("[AreaTransition] No HabitatModel for area " .. areaIndex
		.. " — checked AreaAssets/Area" .. areaIndex .. "/HabitatModel")
	return nil
end

---------------------------------------------------------------
-- HABITAT SWAP
---------------------------------------------------------------
local currentHabitatModel = nil

local function SwapHabitat(areaIndex, instant)
	local template = GetHabitatTemplate(areaIndex)
	if not template then
		warn("[AreaTransition] Skipping habitat swap — no template for area " .. areaIndex)
		return
	end

	-- Optional: If you want to add yOffset/yRotation to AreaRegistry for habitats later!
	local yOffset = 0 
	local yRotation = 0

	if instant then
		for _, child in ipairs(HabitatHolder:GetChildren()) do
			if child ~= HabitatPositionPart then child:Destroy() end
		end
		currentHabitatModel = nil

		local newModel = template:Clone()
		newModel.Parent = HabitatHolder

		-- Positions it at the HabitatPositionPart
		local targetCF = CFrame.new(HabitatPositionPart.Position + Vector3.new(0, yOffset, 0)) * CFrame.Angles(0, math.rad(yRotation), 0)
		newModel:PivotTo(targetCF)

		currentHabitatModel = newModel
	else
		-- Async Tweening Swap
		task.spawn(function()
			if currentHabitatModel and currentHabitatModel.Parent then
				local outTweens = TweenTransparency(currentHabitatModel, 1, FADE_DURATION)
				if #outTweens > 0 then
					outTweens[1].Completed:Wait()
				else
					task.wait(FADE_DURATION)
				end
				if currentHabitatModel and currentHabitatModel.Parent then
					currentHabitatModel:Destroy()
				end
				currentHabitatModel = nil
			else
				task.wait(FADE_DURATION)
			end

			local newModel = template:Clone()
			newModel.Parent = HabitatHolder

			local targetCF = CFrame.new(HabitatPositionPart.Position + Vector3.new(0, yOffset, 0)) * CFrame.Angles(0, math.rad(yRotation), 0)
			newModel:PivotTo(targetCF)

			SetTransparency(newModel, 1)
			currentHabitatModel = newModel
			TweenTransparency(newModel, 0, FADE_DURATION)
		end)
	end
end
---------------------------------------------------------------
-- MAP COLORS
---------------------------------------------------------------
local function ApplyMapColors(areaData, instant)
	local info = TweenInfo.new(TWEEN_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	for _, part in ipairs(Map:GetChildren()) do
		if part:IsA("BasePart") then
			local key   = MAP_PART_COLORS[part.Name]
			local color = key and areaData[key]
			if color then
				if instant then pcall(function() part.Color = color end)
				else SafeTween(part, info, { Color = color }) end
			end
		end
	end
end

local function ApplyLighting(areaIndex, instant)
	local preset = AreaRegistry.GetLighting(areaIndex)

	-- 1. Tween standard Lighting properties
	local props = {}
	if preset.ClockTime then props.ClockTime = preset.ClockTime end
	if preset.Brightness then props.Brightness = preset.Brightness end
	if preset.FogEnd then props.FogEnd = preset.FogEnd end
	if preset.FogStart then props.FogStart = preset.FogStart end
	if preset.Ambient then props.Ambient = preset.Ambient end
	if preset.FogColor then props.FogColor = preset.FogColor end 

	if instant then
		for prop, val in pairs(props) do pcall(function() Lighting[prop] = val end) end
	elseif next(props) then
		SafeTween(Lighting, TweenInfo.new(TWEEN_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), props)
	end

	-- ✨ 2. Tween Atmosphere properties
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		local atmoProps = {}
		if preset.Density then atmoProps.Density = preset.Density end
		if preset.Haze then atmoProps.Haze = preset.Haze end
		if preset.AtmosphereColor then atmoProps.Color = preset.AtmosphereColor end

		if instant then
			for prop, val in pairs(atmoProps) do pcall(function() atmosphere[prop] = val end) end
		elseif next(atmoProps) then
			SafeTween(atmosphere, TweenInfo.new(TWEEN_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), atmoProps)
		end
	end

	-- ✨ 3. Tween SunRays properties (NEW!)
	local sunRays = Lighting:FindFirstChildOfClass("SunRaysEffect")
	if sunRays then
		local rayProps = {}

		-- Use the preset intensity, or default back to 0.25 if the preset forgot to mention it
		if preset.SunRaysIntensity ~= nil then 
			rayProps.Intensity = preset.SunRaysIntensity 
		else
			rayProps.Intensity = 0.25
		end

		if instant then
			for prop, val in pairs(rayProps) do pcall(function() sunRays[prop] = val end) end
		elseif next(rayProps) then
			SafeTween(sunRays, TweenInfo.new(TWEEN_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), rayProps)
		end
	end
end

---------------------------------------------------------------
-- SKYBOX (Updated to use Presets)
---------------------------------------------------------------
local function ApplySkybox(areaIndex, instant)
	local preset = AreaRegistry.GetLighting(areaIndex)
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if not sky then return end

	local function DoSwap()
		if preset.skyboxBk and preset.skyboxBk ~= "" then pcall(function() sky.SkyboxBk = preset.skyboxBk end) end
		if preset.skyboxDn and preset.skyboxDn ~= "" then pcall(function() sky.SkyboxDn = preset.skyboxDn end) end
		if preset.skyboxFt and preset.skyboxFt ~= "" then pcall(function() sky.SkyboxFt = preset.skyboxFt end) end
		if preset.skyboxLf and preset.skyboxLf ~= "" then pcall(function() sky.SkyboxLf = preset.skyboxLf end) end
		if preset.skyboxRt and preset.skyboxRt ~= "" then pcall(function() sky.SkyboxRt = preset.skyboxRt end) end
		if preset.skyboxUp and preset.skyboxUp ~= "" then pcall(function() sky.SkyboxUp = preset.skyboxUp end) end
	end

	if instant then DoSwap()
	else task.delay(TWEEN_DURATION * 0.5, DoSwap) end
end

---------------------------------------------------------------
-- AURAHOLDER RING TINT
---------------------------------------------------------------
local function ApplyAuraHolderTint(areaData, instant)
	if not areaData.auraHolderColor and not areaData.auraHolderGlow then return end
	local info = TweenInfo.new(TWEEN_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	for _, part in ipairs(AuraHolder:GetDescendants()) do
		if currentAuraModel and part:IsDescendantOf(currentAuraModel) then continue end
		if part == PositionPart then continue end
		if part:IsA("BasePart") and areaData.auraHolderColor then
			if instant then pcall(function() part.Color = areaData.auraHolderColor end)
			else SafeTween(part, info, { Color = areaData.auraHolderColor }) end
		end
		if part:IsA("PointLight") and areaData.auraHolderGlow then
			if instant then pcall(function() part.Color = areaData.auraHolderGlow end)
			else SafeTween(part, info, { Color = areaData.auraHolderGlow }) end
		end
	end
end

---------------------------------------------------------------
-- DECORATIONS
---------------------------------------------------------------
local function FadeDecorations(alpha, duration)
	local info   = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	local tweens = {}
	for _, obj in ipairs(DECORATION_CONTAINER:GetDescendants()) do
		if obj:IsA("BasePart") then
			local ok, t = pcall(function()
				return TweenService:Create(obj, info, { Transparency = alpha })
			end)
			if ok and t then t:Play(); table.insert(tweens, t) end
		end
	end
	if #tweens > 0 then tweens[1].Completed:Wait() end
end

---------------------------------------------------------------
-- DECORATIONS (With Memory Transparency Fix)
---------------------------------------------------------------
local function SwapDecorations(areaIndex)
	local folder = AreaAssets:FindFirstChild("Area" .. areaIndex)
	local newDec = folder and folder:FindFirstChild("Decorations")

	-- 1. Fade OUT old decorations
	for _, child in ipairs(DECORATION_CONTAINER:GetChildren()) do
		for _, desc in ipairs(child:GetDescendants()) do
			if desc:IsA("BasePart") or desc:IsA("Decal") or desc:IsA("Texture") then
				SafeTween(desc, TweenInfo.new(TWEEN_DURATION * 0.5), {Transparency = 1})
			end
		end
	end

	task.wait(TWEEN_DURATION * 0.5)

	-- Destroy the old ones once they are invisible
	for _, child in ipairs(DECORATION_CONTAINER:GetChildren()) do 
		child:Destroy() 
	end

	-- 2. Fade IN new decorations
	if newDec then
		for _, obj in ipairs(newDec:GetChildren()) do
			local clone = obj:Clone()

			-- ✨ THE FIX: Save the original transparency before making it invisible!
			for _, desc in ipairs(clone:GetDescendants()) do
				if desc:IsA("BasePart") or desc:IsA("Decal") or desc:IsA("Texture") then
					-- Memorize its true transparency as an Attribute
					desc:SetAttribute("OrigTrans", desc.Transparency)
					-- Now hide it for the fade-in
					desc.Transparency = 1
				end
			end

			clone.Parent = DECORATION_CONTAINER

			-- ✨ THE FIX: Tween back to the saved value instead of 0!
			for _, desc in ipairs(clone:GetDescendants()) do
				if desc:IsA("BasePart") or desc:IsA("Decal") or desc:IsA("Texture") then
					local targetTrans = desc:GetAttribute("OrigTrans") or 0
					SafeTween(desc, TweenInfo.new(TWEEN_DURATION * 0.5), {Transparency = targetTrans})
				end
			end
		end
	end
end

---------------------------------------------------------------
-- MASTER
---------------------------------------------------------------
local function ApplyAreaConfig(areaIndex, instant)
	local areaData = AreaRegistry.Get(areaIndex)
	SwapAuraHolder(areaIndex, instant)
	SwapHabitat(areaIndex, instant) 
	if areaData then
		ApplyMapColors(areaData, instant)
		ApplyLighting(areaIndex, instant) -- ✨ FIX: Passing areaIndex
		ApplySkybox(areaIndex, instant)   -- ✨ FIX: Passing areaIndex
		ApplyAuraHolderTint(areaData, instant)
	end

	if instant then
		local folder = AreaAssets:FindFirstChild("Area" .. areaIndex)
		local newDec = folder and folder:FindFirstChild("Decorations")
		for _, child in ipairs(DECORATION_CONTAINER:GetChildren()) do child:Destroy() end
		if newDec then
			for _, obj in ipairs(newDec:GetChildren()) do obj:Clone().Parent = DECORATION_CONTAINER end
		end
	else
		task.spawn(function() SwapDecorations(areaIndex) end)
	end
end

---------------------------------------------------------------
-- STARTUP
---------------------------------------------------------------
task.defer(function()
	--print("[AreaTransition] Position Part at:", PositionPart.Position)
	--print("[AreaTransition] Ready — yOffset + yRotation read from AreaRegistry per area")
end)

---------------------------------------------------------------
-- CONNECTIONS
---------------------------------------------------------------
local appliedOnJoin = false

AreaUpdated.OnClientEvent:Connect(function(info)
	if not appliedOnJoin then
		appliedOnJoin = true
		print("[AreaTransition] Join → area", info.currentArea or 1)
		ApplyAreaConfig(info.currentArea or 1, true)
	end
end)

AreaChanged.OnClientEvent:Connect(function(info)
	print("[AreaTransition] AreaChanged →", info.newArea, "(" .. (info.travelType or "?") .. ")")
	ApplyAreaConfig(info.newArea or 1, false)
end)
