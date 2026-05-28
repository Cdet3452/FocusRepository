-- BankController
-- Location: StarterPlayer > StarterPlayerScripts > BankController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")

local BankConfig = require(ReplicatedStorage.Modules:WaitForChild("BankConfig"))
local BridgeNet2 = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))
local UITheme = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UITheme"))
local T = UITheme.Get("Custom")

local BankActionBridge = BridgeNet2.ClientBridge("BankAction")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local inSpecialArea = false
local centralAura = nil
local promptGui = nil
local fillProgress = 0
local isHolding = false
local holdSound = nil

local function TriggerBreakVFX()
	if promptGui then
		local panel = promptGui:FindFirstChild("PromptPanel")
		if panel then
			TweenService:Create(panel, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In), {Position = UDim2.new(1, -140, 1.2, 0)}):Play()
			task.delay(0.3, function() if promptGui then promptGui:Destroy(); promptGui = nil end end)
		end
	end

	if centralAura then
		-- 1. Bulge and Flash White
		local bulgeSize = centralAura.Size * 1.5
		TweenService:Create(centralAura, TweenInfo.new(0.3, Enum.EasingStyle.Bounce), {
			Size = bulgeSize, 
			Color = Color3.fromRGB(255, 255, 255)
		}):Play()

		task.delay(0.3, function()
			-- 2. Explode!
			local att = Instance.new("Attachment", centralAura)
			local pe = Instance.new("ParticleEmitter", att)
			pe.Color = ColorSequence.new(Color3.fromRGB(255, 215, 0))
			pe.Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 0)})
			pe.Speed = NumberRange.new(40, 90)
			pe.Drag = 3
			pe.EmissionDirection = Enum.NormalId.Top
			pe.EmitCount = 150
			pe:Emit(150)

			-- Explosion / Cash Sound
			local sfxFolder = ReplicatedStorage:FindFirstChild("SFX") or ReplicatedStorage:FindFirstChild("Sounds")
			if sfxFolder and sfxFolder:FindFirstChild("MaxOut") then
				local sfx = sfxFolder.MaxOut:Clone()
				sfx.Volume = 1
				sfx.Parent = workspace
				sfx:Play()
				game.Debris:AddItem(sfx, 3)
			end

			centralAura.Transparency = 1
			task.delay(2, function()
				if centralAura then centralAura:Destroy(); centralAura = nil end
			end)
		end)
	end
end

local function CreateBankAura(currentBankSize)
	if centralAura then centralAura:Destroy() end
	if promptGui then promptGui:Destroy() end

	-- 1. Spawn the Physical 3D Cube
	centralAura = Instance.new("Part")
	centralAura.Name = "PiggyBankAura"
	centralAura.Anchored = true
	centralAura.Material = Enum.Material.Neon
	centralAura.Color = Color3.fromRGB(255, 215, 0)
	centralAura.Position = Vector3.new(0, 15, 0)

	local scale = BankConfig.CalculateAuraScale and BankConfig.CalculateAuraScale(currentBankSize) or 1
	centralAura.Size = Vector3.new(4, 4, 4) * scale
	centralAura.Parent = workspace

	-- Tag for Tutorial Step 51 (3D Camera Target)
	CollectionService:AddTag(centralAura, "PiggyBankAuraHolder")

	-- 2. Create the 2D ScreenGui Popup
	promptGui = Instance.new("ScreenGui")
	promptGui.Name = "PiggyBankPromptGui"
	promptGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	promptGui.Parent = playerGui

	local panel = Instance.new("ImageButton", promptGui)
	panel.Name = "PromptPanel"
	panel.Size = UDim2.new(0, 220, 0, 85)
	panel.AnchorPoint = Vector2.new(1, 1)

	-- Starts hidden below the screen, slides up to the left of the Boost/Shop buttons
	panel.Position = UDim2.new(1, -140, 1.2, 0) 
	panel.BackgroundColor3 = T.cardBG
	panel.AutoButtonColor = false
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)

	local stroke = Instance.new("UIStroke", panel)
	stroke.Color = T.accentGold
	stroke.Thickness = 2

	-- Tag for Tutorial Step 52 (Click Target)
	CollectionService:AddTag(panel, "Tutorial_PiggyBankPrompt")

	local title = Instance.new("TextLabel", panel)
	title.Size = UDim2.new(1, 0, 0.4, 0)
	title.Position = UDim2.new(0, 0, 0, 8)
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

	-- Slide the panel onto the screen!
	TweenService:Create(panel, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(1, -140, 1, -25)
	}):Play()

	-- 3. Input Handling exactly on the UI Panel
	local function StopHold()
		if not isHolding then return end
		isHolding = false
		TweenService:Create(stroke, TweenInfo.new(0.2), {Thickness = 2}):Play()
		if holdSound then
			holdSound:Stop()
			holdSound:Destroy()
			holdSound = nil
		end
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
	if not inSpecialArea or not promptGui then return end

	local panel = promptGui:FindFirstChild("PromptPanel")
	if not panel then return end
	local fillBar = panel:FindFirstChild("BarBg"):FindFirstChild("Fill")

	if isHolding then
		-- Default to 10 seconds if BankConfig doesn't specify
		local holdTime = BankConfig.HoldToBreakTime or 10
		fillProgress = math.clamp(fillProgress + (dt / holdTime), 0, 1)

		if fillProgress >= 1.0 then
			isHolding = false
			fillProgress = 0
			BankActionBridge:Fire({ action = "breakBank" })
			if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
			TriggerBreakVFX()
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
		if centralAura then
			centralAura:Destroy()
			centralAura = nil
		end
		if promptGui then
			promptGui:Destroy()
			promptGui = nil
		end
	end
end)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local MarketplaceService = game:GetService("MarketplaceService")

local UITheme = require(ReplicatedStorage.Modules:WaitForChild("UITheme"))
local T = UITheme.Get("Custom")
local SoundConfig = require(ReplicatedStorage.Modules:WaitForChild("SoundConfig"))
local NumberFormatter = require(ReplicatedStorage.Modules:WaitForChild("NumberFormatter"))
local BridgeNet2 = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))
local BankConfig = require(ReplicatedStorage.Modules:WaitForChild("BankConfig"))

local UpdateHUDBridge = BridgeNet2.ClientBridge("UpdateHUD")
local BankActionBridge = BridgeNet2.ClientBridge("BankAction")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainHUD = playerGui:WaitForChild("MainHUD")

local ForceCloseUI = ReplicatedStorage:FindFirstChild("ForceCloseUI") or Instance.new("BindableEvent")
ForceCloseUI.Name = "ForceCloseUI"
if not ForceCloseUI.Parent then ForceCloseUI.Parent = ReplicatedStorage end

local panelOpen = false
local currentAurmers = 0
local currentBank = 0
local currentArea = 1

local function AddButtonJuice(btn)
	local scale = btn:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", btn)
	btn.MouseEnter:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Sine), {Scale = 1.05}):Play() end)
	btn.MouseLeave:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Sine), {Scale = 1}):Play() end)
	btn.MouseButton1Down:Connect(function() TweenService:Create(scale, TweenInfo.new(0.1, Enum.EasingStyle.Sine), {Scale = 0.95}):Play() end)
	btn.MouseButton1Up:Connect(function() TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), {Scale = 1.05}):Play() end)
end

local StoreBtn = Instance.new("ImageButton")
StoreBtn.Name = "StoreButton"
StoreBtn.Size = UDim2.new(0.85, 0, 0.85, 0)
StoreBtn.BackgroundColor3 = T.buttonSecondary
StoreBtn.BorderSizePixel = 0
StoreBtn.LayoutOrder = 3
Instance.new("UICorner", StoreBtn).CornerRadius = UDim.new(0.5, 0)
Instance.new("UIAspectRatioConstraint", StoreBtn).AspectRatio = 1.0
local btnStroke = Instance.new("UIStroke", StoreBtn)
btnStroke.Color = Color3.fromRGB(125, 255, 162)
btnStroke.Thickness = 2
local btnIcon = Instance.new("ImageLabel", StoreBtn)
btnIcon.Size = UDim2.new(0.6, 0, 0.6, 0)
btnIcon.Position = UDim2.new(0.2, 0, 0.2, 0)
btnIcon.BackgroundTransparency = 1
btnIcon.ScaleType = Enum.ScaleType.Fit
btnIcon.Image = "rbxassetid://14923161672"
AddButtonJuice(StoreBtn)

local Faded2 = mainHUD:FindFirstChild("Faded2")
if Faded2 then StoreBtn.Parent = Faded2 end
CollectionService:AddTag(StoreBtn, "Tutorial_StoreButton")

local Panel = Instance.new("Frame", mainHUD)
Panel.Name = "StorePanel"
Panel.Size = UDim2.new(0.85, 0, 0.75, 0)
Panel.Position = UDim2.new(0.5, 0, 0.5, 0)
Panel.AnchorPoint = Vector2.new(0.5, 0.5)
Panel.BackgroundColor3 = T.panelBG
Panel.BorderSizePixel = 0
Panel.Visible = false
Panel.ZIndex = 40
Panel.ClipsDescendants = true
Instance.new("UICorner", Panel).CornerRadius = UDim.new(0, 12)
Instance.new("UISizeConstraint", Panel).MaxSize = Vector2.new(500, 650)
local panelStroke = Instance.new("UIStroke", Panel)
panelStroke.Color = T.panelStroke
panelStroke.Thickness = 2
CollectionService:AddTag(Panel, "Tutorial_StorePanel")

local Header = Instance.new("Frame", Panel)
Header.Size = UDim2.new(1, 0, 0, 46)
Header.BackgroundColor3 = T.headerBG
Header.BorderSizePixel = 0
Header.ZIndex = 41
Instance.new("UICorner", Header).CornerRadius = UDim.new(0, 12)

local TitleLabel = Instance.new("TextLabel", Header)
TitleLabel.Size = UDim2.new(1, -50, 1, 0)
TitleLabel.Position = UDim2.new(0, 16, 0, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Text = "STORE & BANK"
TitleLabel.TextColor3 = T.headerText
TitleLabel.TextScaled = true
TitleLabel.Font = T.font
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.ZIndex = 42

local CloseBtn = Instance.new("TextButton", Header)
CloseBtn.Size = UDim2.new(0, 32, 0, 32)
CloseBtn.Position = UDim2.new(1, -40, 0.5, -16)
CloseBtn.BackgroundColor3 = T.buttonRed
CloseBtn.BorderSizePixel = 0
CloseBtn.Text = "X"
CloseBtn.TextColor3 = T.bodyText
CloseBtn.TextScaled = true
CloseBtn.Font = T.font
CloseBtn.ZIndex = 43
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 6)
AddButtonJuice(CloseBtn)

local ScrollFrame = Instance.new("ScrollingFrame", Panel)
ScrollFrame.Size = UDim2.new(1, 0, 1, -46)
ScrollFrame.Position = UDim2.new(0, 0, 0, 46)
ScrollFrame.BackgroundTransparency = 1
ScrollFrame.BorderSizePixel = 0
ScrollFrame.ScrollBarThickness = 6
ScrollFrame.ScrollBarImageColor3 = T.accentGold
ScrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
ScrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
ScrollFrame.ZIndex = 41

local Layout = Instance.new("UIListLayout", ScrollFrame)
Layout.SortOrder = Enum.SortOrder.LayoutOrder
Layout.Padding = UDim.new(0, 15)
Layout.HorizontalAlignment = Enum.HorizontalAlignment.Center

local TopPadding = Instance.new("UIPadding", ScrollFrame)
TopPadding.PaddingTop = UDim.new(0, 15)
TopPadding.PaddingBottom = UDim.new(0, 15)

local VisualElements = {}

local function CreateSectionLabel(text, order)
	local lbl = Instance.new("TextLabel", ScrollFrame)
	lbl.Size = UDim2.new(1, -30, 0, 24)
	lbl.BackgroundTransparency = 1
	lbl.Text = text
	lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
	lbl.TextScaled = true
	lbl.Font = Enum.Font.FredokaOne
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.LayoutOrder = order
	return lbl
end

local function CreateCard(parent, sizeY, order)
	local card = Instance.new("Frame", parent)
	card.Size = UDim2.new(1, -30, 0, sizeY)
	card.BackgroundColor3 = T.cardBG
	card.BorderSizePixel = 0
	card.LayoutOrder = order
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 8)
	table.insert(VisualElements, card)
	return card
end

-- 1. PIGGY BANK ROW
local BankCard = CreateCard(ScrollFrame, 130, 1)

local BankTitle = Instance.new("TextLabel", BankCard)
BankTitle.Size = UDim2.new(1, -24, 0, 24)
BankTitle.Position = UDim2.new(0, 12, 0, 12)
BankTitle.BackgroundTransparency = 1
BankTitle.Text = "GOLDEN AURA PIGGYBANK"
BankTitle.TextColor3 = T.accentGold
BankTitle.TextScaled = true
BankTitle.Font = Enum.Font.FredokaOne

local BankAmountLabel = Instance.new("TextLabel", BankCard)
BankAmountLabel.Size = UDim2.new(1, -24, 0, 32)
BankAmountLabel.Position = UDim2.new(0, 12, 0, 40)
BankAmountLabel.BackgroundTransparency = 1
BankAmountLabel.Text = "Stored: 0 GA"
BankAmountLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
BankAmountLabel.TextScaled = true
BankAmountLabel.Font = Enum.Font.GothamBold

local TeleportBtn = Instance.new("TextButton", BankCard)
TeleportBtn.Size = UDim2.new(0.6, 0, 0, 36)
TeleportBtn.Position = UDim2.new(0.2, 0, 0, 82)
TeleportBtn.BackgroundColor3 = T.buttonPrimary
TeleportBtn.BorderSizePixel = 0
TeleportBtn.Text = "Teleport (Cost: 1 Aurmer)"
TeleportBtn.TextColor3 = T.bodyText
TeleportBtn.TextScaled = true
TeleportBtn.Font = Enum.Font.FredokaOne
Instance.new("UICorner", TeleportBtn).CornerRadius = UDim.new(0, 8)
CollectionService:AddTag(TeleportBtn, "Tutorial_TeleportPiggyBankBtn")
AddButtonJuice(TeleportBtn)
table.insert(VisualElements, TeleportBtn)

-- 2. DEVELOPER PRODUCTS ROW
CreateSectionLabel("GOLDEN AURAS", 2)

local currentProductOrder = 3
local productLabels = {}

for key, product in pairs(BankConfig.DeveloperProducts) do
	local pCard = CreateCard(ScrollFrame, 70, currentProductOrder)
	currentProductOrder += 1

	local pIcon = Instance.new("ImageLabel", pCard)
	pIcon.Size = UDim2.new(0, 46, 0, 46)
	pIcon.Position = UDim2.new(0, 12, 0.5, -23)
	pIcon.BackgroundTransparency = 1
	pIcon.ScaleType = Enum.ScaleType.Fit
	pIcon.Image = product.icon or "rbxassetid://14923131909" 

	local pName = Instance.new("TextLabel", pCard)
	pName.Size = UDim2.new(0.6, -55, 0.4, 0)
	pName.Position = UDim2.new(0, 68, 0, 10)
	pName.BackgroundTransparency = 1
	pName.Text = product.name
	pName.TextColor3 = Color3.fromRGB(255, 215, 0)
	pName.TextScaled = true
	pName.Font = Enum.Font.FredokaOne
	pName.TextXAlignment = Enum.TextXAlignment.Left

	local pYield = Instance.new("TextLabel", pCard)
	pYield.Size = UDim2.new(0.6, -55, 0.35, 0)
	pYield.Position = UDim2.new(0, 68, 0.5, 5)
	pYield.BackgroundTransparency = 1
	pYield.Text = "Yields: " .. product.baseAmount .. " GA"
	pYield.TextColor3 = Color3.fromRGB(200, 200, 200)
	pYield.TextScaled = true
	pYield.Font = Enum.Font.Gotham
	pYield.TextXAlignment = Enum.TextXAlignment.Left

	table.insert(productLabels, {label = pYield, base = product.baseAmount})

	local pBuy = Instance.new("TextButton", pCard)
	pBuy.Size = UDim2.new(0.3, 0, 0.7, 0)
	pBuy.Position = UDim2.new(0.65, 0, 0.15, 0)
	pBuy.BackgroundColor3 = Color3.fromRGB(0, 180, 80)
	pBuy.Text = product.priceStr
	pBuy.TextColor3 = Color3.fromRGB(255, 255, 255)
	pBuy.TextScaled = true
	pBuy.Font = Enum.Font.FredokaOne
	Instance.new("UICorner", pBuy).CornerRadius = UDim.new(0, 6)
	AddButtonJuice(pBuy)
	table.insert(VisualElements, pBuy)

	pBuy.MouseButton1Down:Connect(function()
		MarketplaceService:PromptProductPurchase(player, product.id)
	end)
end

-- 3. GAMEPASSES ROW
CreateSectionLabel("GAMEPASSES", currentProductOrder)
currentProductOrder += 1

for key, pass in pairs(BankConfig.Gamepasses) do
	local gCard = CreateCard(ScrollFrame, 80, currentProductOrder)
	currentProductOrder += 1

	local gIcon = Instance.new("ImageLabel", gCard)
	gIcon.Size = UDim2.new(0, 50, 0, 50)
	gIcon.Position = UDim2.new(0, 12, 0.5, -25)
	gIcon.BackgroundTransparency = 1
	gIcon.ScaleType = Enum.ScaleType.Fit
	gIcon.Image = pass.icon or "rbxassetid://14923131909" 

	local gName = Instance.new("TextLabel", gCard)
	gName.Size = UDim2.new(0.6, -60, 0.35, 0)
	gName.Position = UDim2.new(0, 72, 0, 10)
	gName.BackgroundTransparency = 1
	gName.Text = pass.name
	gName.TextColor3 = Color3.fromRGB(150, 200, 255)
	gName.TextScaled = true
	gName.Font = Enum.Font.FredokaOne
	gName.TextXAlignment = Enum.TextXAlignment.Left

	local gDesc = Instance.new("TextLabel", gCard)
	gDesc.Size = UDim2.new(0.6, -60, 0.35, 0)
	gDesc.Position = UDim2.new(0, 72, 0.5, 5)
	gDesc.BackgroundTransparency = 1
	gDesc.Text = pass.desc
	gDesc.TextColor3 = Color3.fromRGB(200, 200, 200)
	gDesc.TextScaled = true
	gDesc.Font = Enum.Font.Gotham
	gDesc.TextXAlignment = Enum.TextXAlignment.Left

	local gBuy = Instance.new("TextButton", gCard)
	gBuy.Size = UDim2.new(0.3, 0, 0.6, 0)
	gBuy.Position = UDim2.new(0.65, 0, 0.2, 0)
	gBuy.BackgroundColor3 = Color3.fromRGB(180, 50, 150)
	gBuy.Text = "VIEW"
	gBuy.TextColor3 = Color3.fromRGB(255, 255, 255)
	gBuy.TextScaled = true
	gBuy.Font = Enum.Font.FredokaOne
	Instance.new("UICorner", gBuy).CornerRadius = UDim.new(0, 6)
	AddButtonJuice(gBuy)
	table.insert(VisualElements, gBuy)

	gBuy.MouseButton1Down:Connect(function()
		MarketplaceService:PromptGamePassPurchase(player, pass.id)
	end)
end

local function OpenPanel()
	if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_OpenStore") then return end

	ForceCloseUI:Fire("StorePanel")

	if shared.PlayUISound then shared.PlayUISound(SoundConfig.UIOpen or "") end
	panelOpen = true
	Panel.Visible = true
	Panel.Size = UDim2.new(0.85, 0, 0, 0)
	TweenService:Create(Panel, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = UDim2.new(0.85, 0, 0.75, 0)}):Play()
	UITheme.SetMenuVisible(true)

	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
end

local function ClosePanel()
	if not panelOpen then return end
	if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_CloseStore") then return end

	if shared.PlayUISound then shared.PlayUISound(SoundConfig.UIClose or "") end
	panelOpen = false
	TweenService:Create(Panel, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Size = UDim2.new(0.85, 0, 0, 0)}):Play()
	UITheme.SetMenuVisible(false)
	task.delay(0.25, function() Panel.Visible = false end)

	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
end

StoreBtn.MouseButton1Down:Connect(function()
	if panelOpen then ClosePanel() else OpenPanel() end
end)

CloseBtn.MouseButton1Down:Connect(ClosePanel)

ForceCloseUI.Event:Connect(function(exceptionPanel)
	if exceptionPanel ~= "StorePanel" and panelOpen then
		ClosePanel()
	end
end)

TeleportBtn.MouseButton1Down:Connect(function()
	if player:GetAttribute("InSpecialArea") then
		if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_TeleportHome") then return end
		BankActionBridge:Fire({ action = "returnToFarm" })
	else
		if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_TeleportPiggyBank") then return end
		if currentAurmers >= 1 then
			BankActionBridge:Fire({ action = "teleportToBank" })
		else
			if shared.PlayUISound then shared.PlayUISound(SoundConfig.ErrorBuzz or "") end
		end
	end
end)

UpdateHUDBridge:Connect(function(stats)
	if stats.aurmers ~= nil then currentAurmers = stats.aurmers end
	if stats.piggyBank ~= nil then 
		currentBank = stats.piggyBank
		BankAmountLabel.Text = "Stored: " .. NumberFormatter.Format(currentBank) .. " GA"
	end
	if stats.currentArea ~= nil then
		currentArea = stats.currentArea
		for _, data in ipairs(productLabels) do
			local scaledYield = BankConfig.CalculateProductYield(data.base, currentArea)
			data.label.Text = "Yields: " .. NumberFormatter.Format(scaledYield) .. " GA"
		end
	end
end)

BankActionBridge:Connect(function(payload)
	if payload.action == "teleportApproved" then
		player:SetAttribute("InSpecialArea", true)
		TeleportBtn.Text = "Return to Farm"
		TeleportBtn.BackgroundColor3 = T.buttonGreen

		CollectionService:RemoveTag(TeleportBtn, "Tutorial_TeleportPiggyBankBtn")
		CollectionService:AddTag(TeleportBtn, "Tutorial_TeleportHomeBtn")

		ClosePanel()
		if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end

	elseif payload.action == "returnApproved" then
		player:SetAttribute("InSpecialArea", false)
		TeleportBtn.Text = "Teleport (Cost: 1 Aurmer)"
		TeleportBtn.BackgroundColor3 = T.buttonPrimary

		CollectionService:RemoveTag(TeleportBtn, "Tutorial_TeleportHomeBtn")
		CollectionService:AddTag(TeleportBtn, "Tutorial_TeleportPiggyBankBtn")

		ClosePanel()
		if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
	end
end)

local function RefreshLook()
	UITheme.Apply(Panel, "Panel")
	UITheme.Apply(Header, "TitleBar")

	for _, element in ipairs(VisualElements) do
		if element:IsA("Frame") then
			UITheme.Apply(element, "ShopCard")
			UITheme.ApplyShine(element)
		elseif element:IsA("TextButton") then
			UITheme.Apply(element, "Panel")
		end
	end

	UITheme.ApplyShine(Panel)

	local outerStroke = Panel:FindFirstChildWhichIsA("UIStroke")
	if outerStroke then outerStroke.Color = Color3.fromRGB(255, 255, 255) end
end

task.spawn(function()
	task.wait(2)
	RefreshLook()
end)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local MarketplaceService = game:GetService("MarketplaceService")

local BankConfig = require(ReplicatedStorage.Modules:WaitForChild("BankConfig"))
local GameManager = require(ServerScriptService:WaitForChild("GameManager"))
local BridgeNet2 = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))

local UpdateHUDBridge = BridgeNet2.ServerBridge("UpdateHUD")
local BankActionBridge = BridgeNet2.ServerBridge("BankAction")

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
	if not data then return end

	if payload.action == "teleportToBank" then
		local currentAurmers = data.aurmers or 0
		if currentAurmers >= 1 then
			data.aurmers = currentAurmers - 1
			data.inSpecialArea = true

			UpdateHUDBridge:Fire(player, { aurmers = data.aurmers })
			BankActionBridge:Fire(player, { action = "teleportApproved" })
		end

	elseif payload.action == "breakBank" then
		if not data.inSpecialArea then return end

		local bankAmount = data.piggyBank or 0

		if GamepassCache[player.UserId] and GamepassCache[player.UserId].BonusBreak then
			bankAmount = math.floor(bankAmount * BankConfig.Gamepasses.BonusBreak.bonus)
		end

		data.goldenAuras = (data.goldenAuras or 0) + bankAmount
		data.piggyBank = 0

		UpdateHUDBridge:Fire(player, { 
			goldenAuras = data.goldenAuras,
			piggyBank = data.piggyBank
		})
		BankActionBridge:Fire(player, { action = "bankBroken", amount = bankAmount })
		GameManager.SavePlayer(player)

	elseif payload.action == "returnToFarm" then
		data.inSpecialArea = false
		BankActionBridge:Fire(player, { action = "returnApproved" })
	end
end)

return BankManager

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

local BankConfig = {}

BankConfig.LogBaseOffset = 10
BankConfig.MaxVisualScale = 25.0 
BankConfig.HoldToBreakTime = 10.0 
BankConfig.DrainRate = 1.5 

-- NOTE: Replace the 'id' numbers with your actual Gamepass/Developer Product IDs from the Roblox Creator Dashboard.
-- NOTE: For custom images, replace the numbers in the 'icon' string but KEEP the "rbxassetid://" prefix!

BankConfig.Gamepasses = {
	FasterFill = { id = 12314214, name = "Faster Piggy Bank Fill", desc = "Bank fills 2x faster!", multiplier = 2.0, icon = "rbxassetid://72044223502876" },
	BonusBreak = { id = 12314214, name = "40% Bonus Auras", desc = "Get 40% more Auras on break.", bonus = 1.4, icon = "rbxassetid://72044223502876" },
	DoubleEarnings = { id = 12314214, name = "2x Permanent Earnings", desc = "Double all factory income.", bonus = 2.0, icon = "rbxassetid://72044223502876" }
}

BankConfig.DeveloperProducts = {
	Tier1 = { id = 12314214, name = "Handful of Auras", baseAmount = 500, priceStr = "99 R$", icon = "rbxassetid://72044223502876" },
	Tier2 = { id = 12314214, name = "Stack of Auras", baseAmount = 2500, priceStr = "399 R$", icon = "rbxassetid://72044223502876" },
	Tier3 = { id = 12314214, name = "Vault of Auras", baseAmount = 10000, priceStr = "899 R$", icon = "rbxassetid://72044223502876" }
}

function BankConfig.CalculateEffectiveDeposit(baseAmount, currentBankSize, fillMultiplier)
	if baseAmount <= 0 then return 0 end
	fillMultiplier = fillMultiplier or 1.0

	local denominator = math.log10(currentBankSize + BankConfig.LogBaseOffset)
	local effectiveAmount = (baseAmount * fillMultiplier) / denominator

	return math.max(1, math.floor(effectiveAmount))
end

function BankConfig.CalculateAuraScale(currentBankSize)
	local scale = 1.0 + math.log10(currentBankSize + 1)
	return math.min(scale, BankConfig.MaxVisualScale)
end

function BankConfig.CalculateProductYield(baseAmount, currentArea)
	local scaleFactor = 1.0 + ((currentArea - 1) * 0.5)
	return math.floor(baseAmount * scaleFactor)
end

return BankConfig

-- Written by Lightning_Game27

--// Services
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")
local PlayerService = game:GetService("Players") 
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

--// Values
local Camera = workspace.CurrentCamera
local BorderHighlight = script:WaitForChild("Highlight")
local PromptTemplate = script:WaitForChild("PromptTemplate")

--// Prompt Images
local GamepadButtonImage = {
	--// Xbox
	ButtonX = "rbxasset://textures/ui/Controls/xboxX@3x.png",
	ButtonY = "rbxasset://textures/ui/Controls/xboxY@3x.png",
	ButtonA = "rbxasset://textures/ui/Controls/xboxA@3x.png",
	ButtonB = "rbxasset://textures/ui/Controls/xboxB@3x.png",
	ButtonSelect = "rbxasset://textures/ui/Controls/xboxView@3x.png",
	ButtonStart = "rbxasset://textures/ui/Controls/xboxmenu@3x.png",
	
	--// PlayStation
	ButtonSquare = "rbxasset://textures/ui/Controls/PlayStationController/ButtonSquare@3x.png",
	ButtonTriangle = "rbxasset://textures/ui/Controls/PlayStationController/ButtonTriangle@3x.png",
	ButtonCross = "rbxasset://textures/ui/Controls/PlayStationController/ButtonCross@3x.png",
	ButtonCircle = "rbxasset://textures/ui/Controls/PlayStationController/ButtonCircle@3x.png",
	DPadLeft = "rbxasset://textures/ui/Controls/PlayStationController/DPadLeft@3x.png",
	DPadRight = "rbxasset://textures/ui/Controls/PlayStationController/DPadRight@3x.png",
	DPadUp = "rbxasset://textures/ui/Controls/PlayStationController/DPadUp@3x.png",
	DPadDown = "rbxasset://textures/ui/Controls/PlayStationController/DPadDown@3x.png",
	ButtonTouchpad = "rbxasset://textures/ui/Controls/PlayStationController/ButtonTouchpad@3x.png",
	ButtonOptions = "rbxasset://textures/ui/Controls/PlayStationController/ButtonOptions@3x.png",
	ButtonL1 = "rbxasset://textures/ui/Controls/PlayStationController/ButtonL1@3x.png",
	ButtonR1 = "rbxasset://textures/ui/Controls/PlayStationController/ButtonR1@3x.png",
	ButtonL2 = "rbxasset://textures/ui/Controls/PlayStationController/ButtonL2@3x.png",
	ButtonR2 = "rbxasset://textures/ui/Controls/PlayStationController/ButtonR2@3x.png",
	ButtonL3 = "rbxasset://textures/ui/Controls/PlayStationController/ButtonL3@3x.png",
	ButtonR3 = "rbxasset://textures/ui/Controls/PlayStationController/ButtonR3@3x.png",
	Thumbstick1 = "rbxasset://textures/ui/Controls/PlayStationController/Thumbstick1@3x.png",
	Thumbstick2 = "rbxasset://textures/ui/Controls/PlayStationController/Thumbstick2@3x.png",
}

local KeyboardButtonImage = {
	[Enum.KeyCode.Backspace] = "rbxasset://textures/ui/Controls/backspace.png",
	[Enum.KeyCode.Return] = "rbxasset://textures/ui/Controls/return.png",
	[Enum.KeyCode.LeftShift] = "rbxasset://textures/ui/Controls/shift.png",
	[Enum.KeyCode.RightShift] = "rbxasset://textures/ui/Controls/shift.png",
	[Enum.KeyCode.Tab] = "rbxasset://textures/ui/Controls/tab.png",
}
local KeyboardButtonIconMapping = {
	["'"] = "rbxasset://textures/ui/Controls/apostrophe.png",
	[","] = "rbxasset://textures/ui/Controls/comma.png",
	["`"] = "rbxasset://textures/ui/Controls/graveaccent.png",
	["."] = "rbxasset://textures/ui/Controls/period.png",
	[" "] = "rbxasset://textures/ui/Controls/spacebar.png",
}
local KeyCodeToTextMapping = {
	[Enum.KeyCode.LeftControl] = "Ctrl",
	[Enum.KeyCode.RightControl] = "Ctrl",
	[Enum.KeyCode.LeftAlt] = "Alt",
	[Enum.KeyCode.RightAlt] = "Alt",
	[Enum.KeyCode.F1] = "F1",
	[Enum.KeyCode.F2] = "F2",
	[Enum.KeyCode.F3] = "F3",
	[Enum.KeyCode.F4] = "F4",
	[Enum.KeyCode.F5] = "F5",
	[Enum.KeyCode.F6] = "F6",
	[Enum.KeyCode.F7] = "F7",
	[Enum.KeyCode.F8] = "F8",
	[Enum.KeyCode.F9] = "F9",
	[Enum.KeyCode.F10] = "F10",
	[Enum.KeyCode.F11] = "F11",
	[Enum.KeyCode.F12] = "F12",
}

--// Player
local Player = PlayerService.LocalPlayer
local PlayerUI = Player:WaitForChild("PlayerGui")
local Character = Player.Character or Player.CharacterAdded:Wait()

--// Common Functions
local function GetFaceNormals(Part: BasePart)
	local PartCF = Part.CFrame
	return {
		Back = -PartCF.LookVector,
		Front = PartCF.LookVector,
		Bottom = -PartCF.UpVector,
		Top = PartCF.UpVector,
		Left = PartCF.RightVector,
		Right = -PartCF.RightVector
	}
end

local function GetClosestFace(Part: BasePart, DisabledSides: {string})
	local FaceNormals = GetFaceNormals(Part)
	local ClosestFace = nil
	local HighestDotProduct = -math.huge

	local CameraPos = Camera.CFrame.Position
	local CameraLook = Camera.CFrame.LookVector
	
	DisabledSides = DisabledSides or {}

	for Face, Normal in pairs(FaceNormals) do
		if table.find(DisabledSides, Face) then
			continue
		end
		
		local DirectionToPart = (CameraPos - Part.Position).Unit
		local DotProduct = Normal:Dot(DirectionToPart)

		local ViewDotProduct = Normal:Dot(-CameraLook) -- Negative because we want the face facing the camera
		if DotProduct > HighestDotProduct and ViewDotProduct > 0 then -- Face must be visible (angle < 90°)
			HighestDotProduct = DotProduct
			ClosestFace = Face
		end
	end

	return ClosestFace
end

local Hologram = {}
Hologram.__index = Hologram

Hologram.GlobalTweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Exponential)
Hologram.Holograms = {}

local function Tween(Object, Property: string, Value)
	local NewTween = TweenService:Create(Object, Hologram.GlobalTweenInfo, {[Property] = Value})
	NewTween:Play()

	return NewTween
end

function Hologram.InitialiseGlobally(CheckTag: boolean?, ShowBeam: boolean?)
	CheckTag = CheckTag or false
	ShowBeam = ShowBeam or false

	for _, Prompt in pairs(workspace:GetDescendants()) do
		if Prompt:IsA("ProximityPrompt") then
			print(Prompt.Name)
			Hologram.Holograms[Prompt] = Hologram.New(Prompt, Vector3.zero, CheckTag, ShowBeam)
		end
	end
end

function Hologram.New(Prompt: ProximityPrompt, StudsOffset: Vector3?, CheckTag: boolean?, ShowBeam: boolean?)
	if CheckTag then
		if not Prompt:HasTag("Hologram") then
			warn("ProximityPrompt does not have CollectionService Tag 'Hologram'.")
			return
		end
	end
	
	if Prompt.Style ~= Enum.ProximityPromptStyle.Custom then
		warn("ProximityPrompt style is not custom. This prompt is not being registered.")
		return
	end

	local self = setmetatable({}, Hologram)
	self.ActionText = Prompt.ActionText
	self.ObjectText = Prompt.ObjectText
	self.PromptName = Prompt.Name
	self.KeyboardKeyCode = Prompt.KeyboardKeyCode
	self.HoldDuration = Prompt.HoldDuration
	self.Prompt = Prompt
	self.ShowBeam = ShowBeam or false
	self.StudsOffset = StudsOffset or Vector3.zero
	self.Colours = {
		Primary = Color3.fromRGB(0, 144, 255),
		Secondary = Color3.fromRGB(0, 0, 0),
		Tertiary = Color3.fromRGB(255, 255, 255)
	}
	self.UUID = os.clock() + math.random()
	self.BillboardActive = false
	self.DynamicUpdateActive = false
	self.isDeleting = false
	self.AlwaysOnTop = false
	self.DisabledSides = {}
	self.DistanceFromPart = 1

	if Prompt.Parent:IsA("BasePart") or Prompt.Parent:IsA("Attachment") then
		self.PromptParent = Prompt.Parent
	elseif Prompt.Parent:IsA("Model") and Prompt.Parent.PrimaryPart ~= nil then
		self.PromptParent = Prompt.Parent.PrimaryPart
	else
		error("Hologram requires ProximityPrompt to be parented to a BasePart, Attachment or Model with a PrimaryPart.")
	end

	Prompt.PromptShown:Connect(function(InputType: Enum.ProximityPromptInputType)
		self:OnPromptShown(InputType)
	end)

	Prompt.PromptHidden:Connect(function(InputType: Enum.ProximityPromptInputType)
		self:OnPromptHidden(InputType)
	end)

	Prompt.PromptButtonHoldBegan:Connect(function()
		self:PromptHolding()
	end)

	Prompt.Triggered:Connect(function()
		self:PromptTriggered()
	end)

	Hologram.Holograms[Prompt] = self

	return self
end

function Hologram:CreatePrompt()	
	if self.ClonedPrompt ~= nil then
		self.ClonedPrompt:Destroy()
	end

	for _, Attachment in pairs(self.PromptParent:GetChildren()) do
		if Attachment:IsA("Attachment") and string.find(Attachment.Name, "Beam" .. self.PromptName .. self.UUID) then
			Attachment:Destroy()
		end
	end

	self.ClonedPrompt = PromptTemplate:Clone()

	self.KeyCodePart = self.ClonedPrompt.KeyCode
	self.KeyCodeUI = self.KeyCodePart.HologramKeyCodeUI
	self.KeyCodeBackground = self.KeyCodeUI.Background
	self.KeyCodeText = self.KeyCodeBackground.KeyCode
	self.KeyCodeImage = self.KeyCodeBackground.KeyCodeImage
	self.KeyCodeProgress = self.KeyCodeBackground.Progress

	self.InstructionPart = self.ClonedPrompt.Instruction
	self.InstructionUI = self.InstructionPart.HologramInstructionUI
	self.InstructionBackground = self.InstructionUI.Background
	self.ActionUIText = self.InstructionBackground.Action
	self.ObjectUIText = self.InstructionBackground.Object
	self.InvisibleButton = self.InstructionBackground.InvisiButton

	self.DesignPart = self.ClonedPrompt.Design
	self.DesignUI = self.DesignPart.HologramDesignUI
	self.DesignImage = self.DesignUI.Image

	self.KeyCodeUI.Name = "Hologram" .. self.PromptName .. self.UUID .. "KeyCodeUI"
	self.InstructionUI.Name = "Hologram" .. self.PromptName .. self.UUID .. "InstructionUI"
	self.DesignUI.Name = "Hologram" .. self.PromptName .. self.UUID .. "DesignUI"

	self.Beam = self.KeyCodePart.Beam
	self.BeamAttachment = self.KeyCodePart.Attachment
	self.BeamAttachment.Name = "Beam" .. self.PromptName .. self.UUID
	self.TransparencyValue = self.Beam:WaitForChild("TransparencyValue")

	self.ClonedPrompt.Name = "Hologram" .. self.PromptName .. self.UUID
	self.ClonedPrompt.Parent = self.PromptParent

	self.KeyCodeUI.Parent = PlayerUI
	self.InstructionUI.Parent = PlayerUI
	self.DesignUI.Parent = PlayerUI

	self.KeyCodeUI.AlwaysOnTop = self.AlwaysOnTop
	self.InstructionUI.AlwaysOnTop = self.AlwaysOnTop
	self.DesignUI.AlwaysOnTop = self.AlwaysOnTop

	self.BeamConnect = self.TransparencyValue:GetPropertyChangedSignal("Value"):Connect(function()
		self.Beam.Transparency = NumberSequence.new(self.TransparencyValue.Value)
	end)
end

function Hologram:DestroyPrompt()
	if self.ClonedPrompt == nil then return end

	for _, PromptUI in pairs(PlayerUI:GetChildren()) do
		if string.find(PromptUI.Name, "Hologram" .. self.PromptName .. self.UUID) then
			PromptUI:Destroy()
		end
	end

	if self.HoldEndedConnection then
		self.HoldEndedConnection:Disconnect()
	end

	self.BeamConnect:Disconnect()

	if self.InvisiButtonConnect then
		self.InvisiButtonConnect:Disconnect()
	end

	if self.BillboardUI then
		self.BillboardUI:Disconnect()
	end
	
	if self.DynamicUI then
		self.DynamicUI:Disconnect()
	end

	self.ClonedPrompt:Destroy()
	self.ClonedPrompt = nil

	--BorderHighlight.Adornee = nil

	self.isDeleting = false
end

function Hologram:OnPromptShown(InputType: Enum.ProximityPromptInputType)
	repeat RunService.RenderStepped:Wait() until self.isDeleting == false

	self:CreatePrompt()
	if not self.ClonedPrompt then return end

	local LastClosestFace = GetClosestFace(self.PromptParent, self.DisabledSides)
	
	if not LastClosestFace then
		self:OnPromptHidden(InputType)
		return
	end

	local FaceNormal = GetFaceNormals(self.PromptParent)[LastClosestFace]
	local FacePosition = self.PromptParent.Position + (FaceNormal * (self.PromptParent.Size / 2)) + (FaceNormal * self.DistanceFromPart)
	
	local KeyCodeLeftExtent = self.KeyCodePart.Size.X / 2
	local InstructionLeftExtent = self.InstructionPart.Size.X / 2
	local XOffset = KeyCodeLeftExtent - InstructionLeftExtent

	self.KeyCodeText.TextTransparency = 1
	self.ActionUIText.TextTransparency = 1
	self.ObjectUIText.TextTransparency = 1

	self.InstructionBackground.Transparency = 1
	self.KeyCodeBackground.Transparency = 1

	self.DesignImage.ImageTransparency = 1
	self.KeyCodeImage.ImageTransparency = 1

	self.DesignImage.ImageColor3 = self.Colours.Primary
	self.KeyCodeProgress.BackgroundColor3 = self.Colours.Primary

	self.InstructionBackground.BackgroundColor3 = self.Colours.Secondary
	self.KeyCodeBackground.BackgroundColor3 = self.Colours.Secondary

	self.KeyCodeText.TextColor3 = self.Colours.Tertiary
	self.KeyCodeImage.ImageColor3 = self.Colours.Tertiary
	self.ActionUIText.TextColor3 = self.Colours.Tertiary
	self.ObjectUIText.TextColor3 = self.Colours.Tertiary

	if self.BillboardActive == true then
		self.BillboardUI = RunService.RenderStepped:Connect(function()
			if not self.ClonedPrompt or not self.ClonedPrompt.PrimaryPart then self.BillboardUI:Disconnect() return end

			local PartCFrame = self.PromptParent.CFrame
			local WorldOffset = PartCFrame:PointToWorldSpace(self.StudsOffset)
			local CameraPosition = Camera.CFrame.Position

			self.ClonedPrompt:PivotTo(CFrame.lookAt(WorldOffset, CameraPosition, Vector3.new(0, 1, 0)))

			self.DesignPart.CFrame = self.KeyCodePart.CFrame + (self.KeyCodePart.CFrame.LookVector * 0.05)
			self.InstructionPart.CFrame = self.KeyCodePart.CFrame + (self.KeyCodePart.CFrame.LookVector * -0.05) + (self.KeyCodePart.CFrame.RightVector * XOffset)
		end)
	elseif self.DynamicUpdateActive == true then
		self.ClonedPrompt:PivotTo(CFrame.new(FacePosition, FacePosition + FaceNormal))
		self.ClonedPrompt:PivotTo(self.ClonedPrompt.PrimaryPart.CFrame + (self.ClonedPrompt.PrimaryPart.CFrame.LookVector * (self.StudsOffset.Z)) + (self.ClonedPrompt.PrimaryPart.CFrame.RightVector * (self.StudsOffset.X)) + (self.ClonedPrompt.PrimaryPart.CFrame.UpVector * (self.StudsOffset.Y)))

		self.DesignPart.CFrame = self.KeyCodePart.CFrame + (self.KeyCodePart.CFrame.LookVector * 1)
		self.InstructionPart.CFrame = self.KeyCodePart.CFrame + (self.KeyCodePart.CFrame.LookVector * -1) + (self.KeyCodePart.CFrame.RightVector * XOffset)
		
		self.DynamicUI = Camera:GetPropertyChangedSignal("CFrame"):Connect(function()
			if not self.ClonedPrompt or not self.ClonedPrompt.PrimaryPart then
				self.DynamicUI:Disconnect()
				return
			end

			local CurrentClosestFace = GetClosestFace(self.PromptParent, self.DisabledSides)
			if CurrentClosestFace ~= LastClosestFace then
				FaceNormal = GetFaceNormals(self.PromptParent)[CurrentClosestFace]
				if FaceNormal == nil then return end
				FacePosition = self.PromptParent.Position + (FaceNormal * (self.PromptParent.Size / 2)) + (FaceNormal * self.DistanceFromPart)
				
				self.ClonedPrompt:PivotTo(CFrame.new(FacePosition, FacePosition + FaceNormal))
				self.ClonedPrompt:PivotTo(self.ClonedPrompt.PrimaryPart.CFrame + (self.ClonedPrompt.PrimaryPart.CFrame.LookVector * (self.StudsOffset.Z)) + (self.ClonedPrompt.PrimaryPart.CFrame.RightVector * (self.StudsOffset.X)) + (self.ClonedPrompt.PrimaryPart.CFrame.UpVector * (self.StudsOffset.Y)))

				self.DesignPart.CFrame = self.KeyCodePart.CFrame + (self.KeyCodePart.CFrame.LookVector * 1)
				self.InstructionPart.CFrame = self.KeyCodePart.CFrame + (self.KeyCodePart.CFrame.LookVector * -1) + (self.KeyCodePart.CFrame.RightVector * XOffset)
				
				Tween(self.DesignPart, "CFrame", self.DesignPart.CFrame * CFrame.new(0, 0, 0.95))
				Tween(self.InstructionPart, "CFrame", self.InstructionPart.CFrame * CFrame.new(0, 0, -0.95))

				LastClosestFace = CurrentClosestFace
			end
		end)
	else
		self.ClonedPrompt:PivotTo(CFrame.new(FacePosition, FacePosition + FaceNormal))
		self.ClonedPrompt:PivotTo(self.ClonedPrompt.PrimaryPart.CFrame + (self.ClonedPrompt.PrimaryPart.CFrame.LookVector * (self.StudsOffset.Z)) + (self.ClonedPrompt.PrimaryPart.CFrame.RightVector * (self.StudsOffset.X)) + (self.ClonedPrompt.PrimaryPart.CFrame.UpVector * (self.StudsOffset.Y)))

		self.DesignPart.CFrame = self.KeyCodePart.CFrame + (self.KeyCodePart.CFrame.LookVector * 1)
		self.InstructionPart.CFrame = self.KeyCodePart.CFrame + (self.KeyCodePart.CFrame.LookVector * -1) + (self.KeyCodePart.CFrame.RightVector * XOffset)
	end

	if self.ShowBeam == true then
		BorderHighlight.Adornee = self.PromptParent
		
		local Humanoid: Humanoid = Character:WaitForChild("Humanoid")
		
		if Humanoid then
			if Humanoid.RigType == Enum.HumanoidRigType.R6 then
				self.Beam.Attachment1 = Character.Torso.BodyFrontAttachment
			elseif Humanoid.RigType == Enum.HumanoidRigType.R15 then
				self.Beam.Attachment1 = Character.UpperTorso.BodyFrontAttachment
			end
			
			self.BeamAttachment.Parent = self.PromptParent
			Tween(self.TransparencyValue, "Value", 0)
		end
	end

	if InputType == Enum.ProximityPromptInputType.Gamepad then
		local MappedKey = UserInputService:GetStringForKeyCode(self.Prompt.GamepadKeyCode) 
		
		if GamepadButtonImage[MappedKey] then
			self.KeyCodeImage.Image = GamepadButtonImage[MappedKey]
		end
	elseif InputType == Enum.ProximityPromptInputType.Touch then
		self.KeyCodeImage.Image = "rbxasset://textures/ui/Controls/TouchTapIcon.png"
	else
		local ButtonTextString = UserInputService:GetStringForKeyCode(self.Prompt.KeyboardKeyCode)

		local ButtonTextImage = KeyboardButtonImage[self.Prompt.KeyboardKeyCode]
		if ButtonTextImage == nil then
			ButtonTextImage = KeyboardButtonIconMapping[ButtonTextString]
		end

		if ButtonTextImage == nil then
			local KeyCodeMappedText = KeyCodeToTextMapping[self.Prompt.KeyboardKeyCode]
			if KeyCodeMappedText then
				ButtonTextString = KeyCodeMappedText
			end
		end

		if ButtonTextImage then
			self.KeyCodeImage.Image = ButtonTextImage
		elseif ButtonTextString ~= nil and ButtonTextString ~= "" then
			self.KeyCodeText.Text = ButtonTextString
		else
			error(
				"ProximityPrompt '"
					.. self.Prompt.Name
					.. "' has an unsupported keycode for rendering UI: "
					.. tostring(self.Prompt.KeyboardKeyCode)
			)
		end
	end

	self.ActionUIText.Text = self.Prompt.ActionText
	self.ObjectUIText.Text = self.Prompt.ObjectText

	self.InvisiButtonConnect = self.InvisibleButton.InputBegan:Connect(function(Input: InputObject)
		if Input.UserInputType == Enum.UserInputType.Touch or Input.UserInputType == Enum.UserInputType.MouseButton1 then
			self.Prompt:InputHoldBegin()
		end
	end)

	self.ImageHoldEndedConnection = self.InvisibleButton.InputEnded:Connect(function(Input: InputObject)
		if Input.UserInputType == Enum.UserInputType.Touch or Input.UserInputType == Enum.UserInputType.MouseButton1 then
			self.Prompt:InputHoldEnd()
		end
	end)

	if self.BillboardActive == false then
		Tween(self.DesignPart, "CFrame", self.DesignPart.CFrame * CFrame.new(0, 0, 0.95))
		Tween(self.InstructionPart, "CFrame", self.InstructionPart.CFrame * CFrame.new(0, 0, -0.95))
	end

	Tween(self.DesignImage, "ImageTransparency", 0)
	Tween(self.KeyCodeImage, "ImageTransparency", 0)

	Tween(self.ActionUIText, "TextTransparency", 0)
	Tween(self.ObjectUIText, "TextTransparency", 0)
	Tween(self.KeyCodeText, "TextTransparency", 0)

	Tween(self.InstructionBackground, "Transparency", 0.8)
	local FinalTween = Tween(self.KeyCodeBackground, "Transparency", 0)
	FinalTween.Completed:Wait()
end

function Hologram:OnPromptHidden(InputType: Enum.ProximityPromptInputType)
	if not self.ClonedPrompt then return end
	self.isDeleting = true

	if self.ShowBeam then
		BorderHighlight.Adornee = nil
		Tween(self.TransparencyValue, "Value", 1)

		self.Beam.Attachment1 = nil
		self.BeamAttachment.Parent = self.KeyCodePart
	end

	Tween(self.DesignPart, "CFrame", self.DesignPart.CFrame * CFrame.new(0, 0, -0.95))
	Tween(self.InstructionPart, "CFrame", self.InstructionPart.CFrame * CFrame.new(0, 0, 0.95))

	Tween(self.DesignImage, "ImageTransparency", 1)
	Tween(self.KeyCodeImage, "ImageTransparency", 1)

	Tween(self.ActionUIText, "TextTransparency", 1)
	Tween(self.ObjectUIText, "TextTransparency", 1)
	Tween(self.KeyCodeText, "TextTransparency", 1)

	Tween(self.InstructionBackground, "Transparency", 1)
	local FinalTween = Tween(self.KeyCodeBackground, "Transparency", 1)
	FinalTween.Completed:Wait()

	self:DestroyPrompt()
end

function Hologram:PromptHolding()	
	local Fill = TweenService:Create(self.KeyCodeProgress, TweenInfo.new(self.HoldDuration, Enum.EasingStyle.Sine), {Size = UDim2.fromScale(1, 1)})
	Fill:Play()

	local Size = TweenService:Create(self.DesignImage, TweenInfo.new(self.HoldDuration, Enum.EasingStyle.Sine), {Size = UDim2.fromScale(0.9, 0.9)})
	Size:Play()

	local function PromptHoldEnded()
		Fill:Cancel()
		Size:Cancel()

		Tween(self.KeyCodeProgress, "Size", UDim2.fromScale(1, 0))
		Tween(self.DesignImage, "Size", UDim2.fromScale(1, 1))

		if self.HoldEndedConnection then
			self.HoldEndedConnection:Disconnect()
		end
	end

	self.HoldEndedConnection = self.Prompt.PromptButtonHoldEnded:Connect(PromptHoldEnded)
end

function Hologram:PromptTriggered()
	if self.HoldDuration > 0 then return end

	local Size = TweenService:Create(self.DesignImage, TweenInfo.new(0.1, Enum.EasingStyle.Sine), {Size = UDim2.fromScale(0.9, 0.9)})
	Size:Play()
	Size.Completed:Wait()

	TweenService:Create(self.DesignImage, TweenInfo.new(0.1, Enum.EasingStyle.Sine), {Size = UDim2.fromScale(1, 1)}):Play()
end

--// Settings

--[[
	Sets whether the Hologram is always visible, despite obstructions.
]]
function Hologram:SetAlwaysOnTop(isOnTop: boolean)
	self.AlwaysOnTop = isOnTop
end

--[[
	Sets primary colour of the Hologram. Default: Blue.
]]
function Hologram:SetPrimaryColour(Colour: Color3)
	self.Colours.Primary = Colour
end

--[[
	Sets secondary colour of the Hologram. Default: Black.
]]
function Hologram:SetSecondaryColour(Colour: Color3)
	self.Colours.Secondary = Colour
end

--[[
	Sets tertiary colour of the Hologram. Default: White.
]]
function Hologram:SetTertiaryColour(Colour: Color3)
	self.Colours.Tertiary = Colour
end

--[[
	Sets Vector3 offset of how far you want the Hologram from its Parent.
]]
function Hologram:SetStudsOffset(StudsOffset: Vector3)
	self.StudsOffset = StudsOffset
end

--[[
	Enable/Disable Beam+Highlight effect.
]]
function Hologram:SetBeam(ShowBeam: boolean)
	self.ShowBeam = ShowBeam
end

--[[
	Sets whether the Hologram acts like a BillboardGui.
]]
function Hologram:SetBillboardActive(isActive: boolean)
	self.BillboardActive = isActive
	self.DynamicUpdateActive = isActive and false 
end

--[[
	Sets whether the Hologram dynamically updates as player moves around.
]]
function Hologram:SetDynamicUpdate(isActive: boolean)
	self.DynamicUpdateActive = isActive
	self.BillboardActive = isActive and false
end

--[[
	Disable certain sides from which Hologram cannot be viewed.
]]

function Hologram:SetDisabledSides(Sides: {string})
	self.DisabledSides = Sides or {}
end

--[[
	Set the distance from which Hologram appears on its parent.
]]

function Hologram:SetDistanceFromPart(Distance: number)
	self.DistanceFromPart = Distance
end

return Hologram

-- UpgradeConfig --
-- Location: ReplicatedStorage > Modules > UpgradeConfig
local AdminConfig = require(script.Parent.AdminConfig)
local UpgradeConfig = {}

UpgradeConfig.Tiers = {
	[1] = {
		tierName = "Tier 1",
		unlockRequirement = 0,
		upgrades = {
			blockValue = {
				baseCost = 45, 
				costScale = 1.03, 
				maxLevel = 100,
				apply = function(data) 
					local lv = (data.upgrades and data.upgrades.blockValue) or 0
					return (lv * 0.1) 
				end,
				displayName = "Glow Enhancement",
				description = "Increases base aura value by +10%", 
				iconId = "rbxassetid://14917130166",
			},
			hatcheryCapacity = {
				baseCost = 475, costScale = 1.02, maxLevel = 50,
				apply = function(data) return (AdminConfig.HatcheryMax or 100) + (((data.upgrades and data.upgrades.hatcheryCapacity) or 0) * 1) end,
				displayName = "Aura Expansion", description = "Increases the max capacity of your Hatchery by 1", iconId = "rbxassetid://14923548733",
			},
			habitatCapacity = {
				baseCost = 850, costScale = 1.05, maxLevel = 25,
				apply = function(data) return (AdminConfig.BaseHabitatCapacity or 50) + (((data.upgrades and data.upgrades.habitatCapacity) or 0) * 2) end,
				displayName = "Habitat Reservoir", description = "Increase habitat capacity by 2", iconId = "rbxassetid://14915711292",
			},
			unlockMythicMult = { 
				baseCost = 5000, costScale = 1, maxLevel = 1, 
				apply = function(data) return ((data.upgrades and data.upgrades.unlockMythicMult) or 0) == 1 end,
				displayName = "Mythic Multiplier",
				description = "Allows you to hold past the legendary multiplier! Unlocks the " .. (AdminConfig.MilestoneData[6] and AdminConfig.MilestoneData[6].name or "MYTHIC") .. " tier!",
				iconId = "rbxassetid://14921959974",
			}, --176 total max upgrades
		}
	},
	[2] = {
		tierName = "Tier 2",
		unlockRequirement = 150,
		upgrades = {
			blockValueT2 = {
				baseCost = 1000, costScale = 1.2, maxLevel = 125,
				apply = function(data) return (((data.upgrades and data.upgrades.blockValueT2) or 0) * 0.05) end,
				displayName = "Faster Aura Pulse", description = "Increased aura value by +5%", iconId = "rbxassetid://14923455396",
			},
			passiveTickSpeedT2 = {
				baseCost = 20000, costScale = 1.45, maxLevel = 5,
				apply = function(data) return (((data.upgrades and data.upgrades.passiveTickSpeedT2) or 0) * 0.05) end,
				displayName = "Advanced Aura Generation", description = "Increases Passive Value Of Auras by 5%", iconId = "rbxassetid://14921959974",
			},	
			shipCapacityT1 = {
				baseCost = 8000, costScale = 1.25, maxLevel = 25,
				apply = function(data) return ((data.upgrades and data.upgrades.shipCapacityT1) or 0) * 1 end,
				displayName = "Shipping Expansion", description = "Increases the max auras a ship can carry by 1.",
			}, --155 total max upgrades
		}
	},
	[3] = {
		tierName = "Tier 3",
		unlockRequirement = 150, 
		upgrades = {
			auraValueT3 = {
				baseCost = 250000, costScale = 1.15, maxLevel = 4,
				apply = function(data) return (((data.upgrades and data.upgrades.auraValueT3) or 0) * 0.25) end,
				displayName = "Aura Purifier", description = "Purifies Your Auras, Increases Value by 25%",
			},
			hatcheryT3 = {
				baseCost = 750000, costScale = 1.3, maxLevel = 25,
				apply = function(data) return (((data.upgrades and data.upgrades.hatcheryT3) or 0) * 2) end,
				displayName = "Increased Hatchery", description = "Provides even more hatchery space for more auras by 2",
			},
			habitatT3 = {
				baseCost = 2000000, costScale = 1.4, maxLevel = 15,
				apply = function(data) return (((data.upgrades and data.upgrades.habitatT3) or 0) * 10) end,
				displayName = "Industrial Packaging", description = "Increases Habitat Capacity by 10",
			},
			droneFrequency = {
				baseCost = 500000, costScale = 1.4, maxLevel = 25,
				apply = function(data) return ((data.upgrades and data.upgrades.droneFrequency) or 0) * 1 end,
				displayName = "Unstable Area", description = "Random Aura Shots appear more frequently. 1% higher chance for more.",
			},--69 total max upgrades
		}
	},
	[4] = {
		tierName = "Tier 4",
		unlockRequirement = 225, 
		upgrades = {
			auraValueT4 = {
				baseCost = 15000000, costScale = 1.25, maxLevel = 250,
				apply = function(data) return ((data.upgrades and data.upgrades.auraValueT4) or 0) * 0.01 end,
				displayName = "Shinier Auras", description = "Auras Shine Brighter and increase value by 1%",
			},
			hatcheryT4 = {
				baseCost = 40000000, costScale = 1.35, maxLevel = 20,
				apply = function(data) return ((data.upgrades and data.upgrades.hatcheryT4) or 0) * 5 end,
				displayName = "Advanced Hatchery", description = "Increases Hatchery by 5",
			},
			eliteSpawnChance = {
				baseCost = 25000000, costScale = 1.4, maxLevel = 25,
				apply = function(data) return ((data.upgrades and data.upgrades.eliteSpawnChance) or 0) * 1.0 end,
				displayName = "Luckier Shots", description = "Increases the chance of an Elite Aura spawning by 1%.",
			},
			
		}
	},
	[5] = {
		tierName = "Tier 5",
		unlockRequirement = 200,
		upgrades = {
			habitatT5 = {
				baseCost = 5e8, costScale = 1.4, maxLevel = 50,
				apply = function(data) return ((data.upgrades and data.upgrades.habitatT5) or 0) * 2000 end,
				displayName = "Stellar Habitats", description = "House your auras inside miniature stars (+2,000 capacity).",
			},
			-- ✨ NEW: Habitat Cost Reduction
			habitatDiscount = {
				baseCost = 1e8, costScale = 1.5, maxLevel = 10,
				apply = function(data) return ((data.upgrades and data.upgrades.habitatDiscount) or 0) * 0.05 end,
				displayName = "Material Synthesis", description = "Reduces the cost of upgrading habitats by 5%.",
			},
			-- ✨ NEW: Automated Dispatch
			autoDispatchSpeed = {
				baseCost = 7.5e8, costScale = 1.3, maxLevel = 25,
				apply = function(data) return ((data.upgrades and data.upgrades.autoDispatchSpeed) or 0) * 0.2 end,
				displayName = "Logistics AI", description = "Auto-shipping speed increased by 20%.",
			},
			unlockCosmicMult = { 
				baseCost = 2.5e9, costScale = 1, maxLevel = 1, 
				apply = function(data) return ((data.upgrades and data.upgrades.unlockCosmicMult) or 0) == 1 end,
				displayName = "Cosmic Multiplier", 
				description = "Shatters the Mythic limit, unlocking the " .. (AdminConfig.MilestoneData[7] and AdminConfig.MilestoneData[7].name or "COSMIC") .. " tier!",
			},
		}
	},
	[6] = {
		tierName = "Tier 6",
		unlockRequirement = 300,
		upgrades = {
			passiveSpeedT6 = {
				baseCost = 5e10, costScale = 1.5, maxLevel = 25,
				apply = function(data) return ((data.upgrades and data.upgrades.passiveSpeedT6) or 0) * 0.5 end,
				displayName = "Faster Than Light", description = "Auras spawn before you even need them (-50% delay).",
			},
			auraValueT6 = {
				baseCost = 1.5e11, costScale = 1.3, maxLevel = 200,
				apply = function(data) return ((data.upgrades and data.upgrades.auraValueT6) or 0) * 5.0 end,
				displayName = "Tachyon Infusion", description = "Infuse auras with speed particles for +500% value per level.",
			},
			-- ✨ NEW TIER 6 PADDING (All Max Level 25 for easy tweaking)
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
				apply = function(data) return ((data.upgrades and data.upgrades.shippingCapacityT6) or 0) * 5000 end,
				displayName = "Wormhole Freight", description = "Ships carry +5,000 more auras through hyperspace.",
			},
		}
	},
	[7] = {
		tierName = "Tier 7",
		unlockRequirement = 500,
		upgrades = {
			hatcheryT7 = {
				baseCost = 1e13, costScale = 1.4, maxLevel = 100,
				apply = function(data) return ((data.upgrades and data.upgrades.hatcheryT7) or 0) * 10000 end,
				displayName = "Void Reservoirs", description = "Store energy in the endless void (+10,000 capacity).",
			},
			habitatT7 = {
				baseCost = 5e13, costScale = 1.45, maxLevel = 100,
				apply = function(data) return ((data.upgrades and data.upgrades.habitatT7) or 0) * 50000 end,
				displayName = "Antimatter Containment", description = "Safely store massive amounts of auras (+50,000 capacity).",
			},
			-- ✨ NEW
			prestigeMultiplierBonus = {
				baseCost = 2e13, costScale = 1.6, maxLevel = 10,
				apply = function(data) return ((data.upgrades and data.upgrades.prestigeMultiplierBonus) or 0) * 0.05 end,
				displayName = "Soul Memory", description = "Increases the multiplier gained from Prestiging by 5%.",
			},
			droneRewardMulti = {
				baseCost = 8e13, costScale = 1.5, maxLevel = 25,
				apply = function(data) return ((data.upgrades and data.upgrades.droneRewardMulti) or 0) * 0.5 end,
				displayName = "Heavier Payloads", description = "Random drops contain 50% more resources.",
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
			-- ✨ NEW
			godlyCritChance = {
				baseCost = 1e16, costScale = 1.4, maxLevel = 25,
				apply = function(data) return ((data.upgrades and data.upgrades.godlyCritChance) or 0) * 0.2 end,
				displayName = "Divine Intervention", description = "0.2% chance for an aura to instantly max out its value.",
			},
			habitatT8 = {
				baseCost = 8e16, costScale = 1.5, maxLevel = 100,
				apply = function(data) return ((data.upgrades and data.upgrades.habitatT8) or 0) * 250000 end,
				displayName = "Pocket Universes", description = "Creates entire universes to hold your auras (+250,000 capacity).",
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
				apply = function(data) return ((data.upgrades and data.upgrades.habitatT9) or 0) * 1000000 end,
				displayName = "Galaxy Clusters", description = "Your habitats are now comprised of entire galaxies (+1M capacity).",
			},
			hatcheryT9 = {
				baseCost = 5e19, costScale = 1.5, maxLevel = 150,
				apply = function(data) return ((data.upgrades and data.upgrades.hatcheryT9) or 0) * 500000 end,
				displayName = "Big Bang Forges", description = "Hatch energy from the birth of new universes (+500k capacity).",
			},
			-- ✨ NEW
			universalShipping = {
				baseCost = 8e19, costScale = 1.45, maxLevel = 50,
				apply = function(data) return ((data.upgrades and data.upgrades.universalShipping) or 0) * 1000000 end,
				displayName = "Teleportation Networks", description = "Instantly beam auras to buyers (+1M shipping capacity).",
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
			-- ✨ NEW
			omniCapacity = {
				baseCost = 5e22, costScale = 1.5, maxLevel = 500,
				apply = function(data) return ((data.upgrades and data.upgrades.omniCapacity) or 0) * 10000000 end,
				displayName = "The Final Frontier", description = "Unfathomable space (+10M habitat capacity).",
			},
			omniSpeed = {
				baseCost = 8e22, costScale = 1.6, maxLevel = 100,
				apply = function(data) return ((data.upgrades and data.upgrades.omniSpeed) or 0) * 2.0 end,
				displayName = "Time Collapse", description = "Auras generate infinitely fast (-200% delay multiplier).",
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

-- HELPER: Used by Spawner, Manager, and HUD to find math without knowing the Tier
function UpgradeConfig.GetUpgradeConfig(upgradeId)
	for _, tierData in ipairs(UpgradeConfig.Tiers) do
		if tierData.upgrades[upgradeId] then
			return tierData.upgrades[upgradeId]
		end
	end
	return nil
end

-- HELPER: Used by Shop and Manager to calculate cost
function UpgradeConfig.CalculateCost(upgradeId, currentLevel)
	local cfg = UpgradeConfig.GetUpgradeConfig(upgradeId)
	if not cfg then return math.huge end
	if currentLevel >= cfg.maxLevel then return math.huge end

	-- Exponential Cost Formula: Base * (Scale ^ Level)
	return math.floor(cfg.baseCost * (cfg.costScale ^ currentLevel))
end

return UpgradeConfig
