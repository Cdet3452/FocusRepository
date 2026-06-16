ok they are all in now i already own all the gamepasses for some reason in studio but that prob normal, they all properly work but the dev products are not working at all sadly. also for the 40+ extra i want it to be calculated when you go in the piggy bank area so they teleport in and then an animation plays adding to the amount stored you have being 40% also i know these that the 499 ga text is still offset incorrectly when you don't have the gamepasses bought yet when its only supposed to offset when you have them bought, its perfect when you have them all unlocked though just add the refresh look to them. these would be the effected scripts:
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BankConfig = require(ReplicatedStorage.Modules:WaitForChild("BankConfig"))
local GameManager = require(ServerScriptService:WaitForChild("GameManager"))
local BridgeNet2 = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))
local UpdateHUDBridge = BridgeNet2.ServerBridge("UpdateHUD")
local MonetizationManager = {}

local function ProcessReceipt(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then return Enum.ProductPurchaseDecision.NotProcessedYet end

	local data = GameManager.GetData(player.UserId)
	if not data then return Enum.ProductPurchaseDecision.NotProcessedYet end

	-- Aurmer Key: gives 1 vault key, not golden auras
	local aurmerProduct = BankConfig.DeveloperProducts.Aurmer
	if aurmerProduct and aurmerProduct.id ~= 0 and aurmerProduct.id == receiptInfo.ProductId then
		data.aurmers = (data.aurmers or 0) + 1
		UpdateHUDBridge:Fire(player, { aurmers = data.aurmers })
		GameManager.SavePlayer(player)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	-- GA tier products
	for key, productData in pairs(BankConfig.DeveloperProducts) do
		if key ~= "Aurmer" and productData.id ~= 0 and productData.id == receiptInfo.ProductId then
			local rewardAmount = BankConfig.CalculateProductYield(productData.baseAmount, data.currentArea or 1)
			data.goldenAuras = (data.goldenAuras or 0) + rewardAmount
			UpdateHUDBridge:Fire(player, { goldenAuras = data.goldenAuras })
			-- fires the golden aura juice animation on the client
			local ShipAurasBridge = BridgeNet2.ServerBridge("ShipAuras")
			ShipAurasBridge:Fire(player, { action = "playJuice", amount = rewardAmount, currencyType = "Auras" })
			GameManager.SavePlayer(player)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end

	return Enum.ProductPurchaseDecision.NotProcessedYet
end

MarketplaceService.ProcessReceipt = ProcessReceipt

return MonetizationManager

-- StoreController
-- Location: StarterPlayer > StarterPlayerScripts > StoreController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local MarketplaceService = game:GetService("MarketplaceService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

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

-- ✨ THE FIX: Global Tooltip System for "Thank You!"

local TooltipGui = Instance.new("ScreenGui", playerGui)
TooltipGui.Name = "GamepassTooltipGui"
TooltipGui.DisplayOrder = 2000

local TooltipLabel = Instance.new("TextLabel", TooltipGui)
TooltipLabel.Size = UDim2.new(0, 240, 0, 32)
TooltipLabel.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
TooltipLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
TooltipLabel.Font = Enum.Font.GothamMedium
TooltipLabel.TextSize = 14
TooltipLabel.Text = "Thank you for supporting the game!"
TooltipLabel.Visible = false
TooltipLabel.ZIndex = 50
Instance.new("UICorner", TooltipLabel).CornerRadius = UDim.new(0, 6)
local tipStroke = Instance.new("UIStroke", TooltipLabel)
tipStroke.Color = Color3.fromRGB(255, 215, 0)
tipStroke.Thickness = 1.5

RunService.RenderStepped:Connect(function()
	if TooltipLabel.Visible then
		local mousePos = UserInputService:GetMouseLocation()
		TooltipLabel.Position = UDim2.new(0, mousePos.X + 15, 0, mousePos.Y + 15)
	end
end)

local function BindTooltip(uiElement)
	uiElement.MouseEnter:Connect(function() TooltipLabel.Visible = true end)
	uiElement.MouseLeave:Connect(function() TooltipLabel.Visible = false end)
	uiElement.SelectionLost:Connect(function() TooltipLabel.Visible = false end)
end

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
local GamepassBuyButtons = {}

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

local BankCard = CreateCard(ScrollFrame, 130, 1)

local BankTitle = Instance.new("TextLabel", BankCard)
BankTitle.Size = UDim2.new(1, -24, 0, 24)
BankTitle.Position = UDim2.new(0, 12, 0, 12)
BankTitle.BackgroundTransparency = 1
BankTitle.Text = "GOLDEN AURA PIGGYBANK"
BankTitle.TextColor3 = T.accentGold
BankTitle.TextScaled = true
BankTitle.Font = Enum.Font.FredokaOne

-- ✨ THE FIX: Made full width again so the text does NOT offset or squish
local BankAmountLabel = Instance.new("TextLabel", BankCard)
BankAmountLabel.Size = UDim2.new(1, -24, 0, 32)
BankAmountLabel.Position = UDim2.new(0, 12, 0, 40)
BankAmountLabel.BackgroundTransparency = 1
BankAmountLabel.Text = "Stored: 0 GA"
BankAmountLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
BankAmountLabel.TextScaled = true
BankAmountLabel.Font = Enum.Font.GothamBold
BankAmountLabel.TextXAlignment = Enum.TextXAlignment.Left

-- ✨ THE FIX: Perk Badges grouped together dynamically as an overlay on the right!
local BankBadges = Instance.new("Frame", BankCard)
BankBadges.Size = UDim2.new(0.5, -12, 0, 32)
BankBadges.Position = UDim2.new(1, -12, 0, 40)
BankBadges.AnchorPoint = Vector2.new(1, 0)
BankBadges.BackgroundTransparency = 1
local bbLayout = Instance.new("UIListLayout", BankBadges)
bbLayout.FillDirection = Enum.FillDirection.Horizontal
bbLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
bbLayout.VerticalAlignment = Enum.VerticalAlignment.Center
bbLayout.Padding = UDim.new(0, 6)

local function CreateBankBadge(text, color, strokeColor)
	local badge = Instance.new("TextLabel", BankBadges)
	badge.Size = UDim2.new(0, 0, 0, 22)
	badge.AutomaticSize = Enum.AutomaticSize.X
	badge.BackgroundColor3 = color
	badge.TextColor3 = Color3.fromRGB(255, 255, 255)
	badge.Font = Enum.Font.FredokaOne
	badge.TextSize = 14
	badge.Text = " " .. text .. " "
	badge.Visible = false
	Instance.new("UICorner", badge).CornerRadius = UDim.new(0, 5)
	local strk = Instance.new("UIStroke", badge)
	strk.Color = strokeColor
	strk.Thickness = 1.5
	BindTooltip(badge)
	return badge
end

-- Moved the 2x Earnings badge here to group them all cleanly!
local Badge_FasterFill = CreateBankBadge("2x Fill", Color3.fromRGB(0, 120, 200), Color3.fromRGB(0, 50, 100))
local Badge_BonusBreak = CreateBankBadge("+40% Auras", Color3.fromRGB(150, 50, 200), Color3.fromRGB(80, 0, 100))
local Badge_DoubleCash = CreateBankBadge("2x Cash", Color3.fromRGB(0, 150, 60), Color3.fromRGB(0, 80, 0))

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

local AurmerCard = CreateCard(ScrollFrame, 80, 2)

local aIcon = Instance.new("ImageLabel", AurmerCard)
aIcon.Size = UDim2.new(0, 50, 0, 50)
aIcon.Position = UDim2.new(0, 12, 0.5, -25)
aIcon.BackgroundTransparency = 1
aIcon.ScaleType = Enum.ScaleType.Fit
aIcon.Image = "rbxassetid://14949477468"

local aName = Instance.new("TextLabel", AurmerCard)
aName.Size = UDim2.new(0.6, -60, 0.35, 0)
aName.Position = UDim2.new(0, 72, 0, 10)
aName.BackgroundTransparency = 1
aName.Text = "AURMER KEY"
aName.TextColor3 = Color3.fromRGB(255, 180, 50)
aName.TextScaled = true
aName.Font = Enum.Font.FredokaOne
aName.TextXAlignment = Enum.TextXAlignment.Left

local aDesc = Instance.new("TextLabel", AurmerCard)
aDesc.Size = UDim2.new(0.6, -60, 0.35, 0)
aDesc.Position = UDim2.new(0, 72, 0.5, 5)
aDesc.BackgroundTransparency = 1
aDesc.Text = "Required to enter the Golden Vault."
aDesc.TextColor3 = Color3.fromRGB(200, 200, 200)
aDesc.TextScaled = true
aDesc.Font = Enum.Font.Gotham
aDesc.TextXAlignment = Enum.TextXAlignment.Left

local aBuy = Instance.new("TextButton", AurmerCard)
aBuy.Size = UDim2.new(0.3, 0, 0.6, 0)
aBuy.Position = UDim2.new(0.65, 0, 0.2, 0)
aBuy.BackgroundColor3 = Color3.fromRGB(255, 150, 50)
aBuy.Text = "99 R$"
aBuy.TextColor3 = Color3.fromRGB(255, 255, 255)
aBuy.TextScaled = true
aBuy.Font = Enum.Font.FredokaOne
Instance.new("UICorner", aBuy).CornerRadius = UDim.new(0, 6)
AddButtonJuice(aBuy)
table.insert(VisualElements, aBuy)

aBuy.MouseButton1Down:Connect(function()
	local productId = (BankConfig.DeveloperProducts and BankConfig.DeveloperProducts.Aurmer and BankConfig.DeveloperProducts.Aurmer.id) or 0
	if productId > 0 then
		MarketplaceService:PromptProductPurchase(player, productId)
	else
		warn("Aurmer Product ID not set in BankConfig!")
	end
end)

CreateSectionLabel("GOLDEN AURAS", 3)

local currentProductOrder = 4
local productLabels = {}

for key, product in pairs(BankConfig.DeveloperProducts) do
	if key == "Aurmer" then continue end

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

	GamepassBuyButtons[key] = gBuy
	table.insert(VisualElements, gBuy)

	gBuy.MouseButton1Down:Connect(function()
		if player:GetAttribute("Pass_" .. key) then return end
		MarketplaceService:PromptGamePassPurchase(player, pass.id)
	end)


end

-- ✨ THE FIX: Instantly sync Gamepass attributes into Visuals!

local function SyncGamepasses()
	local hasFasterFill = player:GetAttribute("Pass_FasterFill")
	local hasBonusBreak = player:GetAttribute("Pass_BonusBreak")
	local hasDoubleCash = player:GetAttribute("Pass_DoubleEarnings")

	-- Toggle Badges On/Off
	Badge_FasterFill.Visible = hasFasterFill == true
	Badge_BonusBreak.Visible = hasBonusBreak == true
	Badge_DoubleCash.Visible = hasDoubleCash == true

	-- Update the Shop List Buttons
	local function SetOwned(btn)
		if not btn then return end
		btn.Text = "OWNED"
		btn.BackgroundColor3 = Color3.fromRGB(90, 90, 100)
		btn.TextColor3 = Color3.fromRGB(200, 200, 200)
		btn.Interactable = false
	end

	if hasFasterFill then SetOwned(GamepassBuyButtons["FasterFill"]) end
	if hasBonusBreak then SetOwned(GamepassBuyButtons["BonusBreak"]) end
	if hasDoubleCash then SetOwned(GamepassBuyButtons["DoubleEarnings"]) end


end

-- Re-sync any time the server validates a new purchase
player:GetAttributeChangedSignal("Pass_FasterFill"):Connect(SyncGamepasses)
player:GetAttributeChangedSignal("Pass_BonusBreak"):Connect(SyncGamepasses)
player:GetAttributeChangedSignal("Pass_DoubleEarnings"):Connect(SyncGamepasses)
SyncGamepasses() -- Initial check on load

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
	TooltipLabel.Visible = false
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

-- BankConfig
-- Location: ReplicatedStorage > Modules > BankConfig

local BankConfig = {}

BankConfig.LogBaseOffset = 10
BankConfig.MaxVisualScale = 25.0
BankConfig.HoldToBreakTime = 10.0
BankConfig.DrainRate = 1.5

-- TODO: Replace the '0' values with your actual Gamepass/Developer Product IDs from the Roblox Creator Dashboard.
-- NOTE: For custom images, replace the numbers in the 'icon' string but KEEP the "rbxassetid://" prefix!

BankConfig.Gamepasses = {
	FasterFill = { id = 1880968328, name = "Faster Piggy Bank Fill", desc = "Bank fills 2x faster!", multiplier = 2.0, icon = "rbxassetid://124989446214292" },
	BonusBreak = { id = 1880740639, name = "40% Bonus Auras", desc = "Get 40% more Auras on break.", bonus = 1.4, icon = "rbxassetid://118097196707066" },
	DoubleEarnings = { id = 1881574273, name = "2x Permanent Ship Earnings", desc = "Double all factory income.", bonus = 2.0, icon = "rbxassetid://130113307538169" }
}

BankConfig.DeveloperProducts = {
	Aurmer = { id = 3605050516, name = "Aurmer", baseAmount = 0, priceStr = "99 R$", icon = "rbxassetid://94528788784857" },
	Tier1 = { id = 3605050187, name = "Handful of Auras", baseAmount = 500, priceStr = "99 R$", icon = "rbxassetid://135937002201231" },
	Tier2 = { id = 3605050309, name = "Stack of Auras", baseAmount = 2500, priceStr = "399 R$", icon = "rbxassetid://108357904529996" },
	Tier3 = { id = 3605050434, name = "Vault of Auras", baseAmount = 10000, priceStr = "899 R$", icon = "rbxassetid://122544939290207" }
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

return BankConfig-- BankController
-- Location: StarterPlayer > StarterPlayerScripts > BankController

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
	if payload.action == "bankBroken" then
		isBankBroken = true
		local amount = payload.amount or 0
		TriggerBreakVFX(amount)
	end
end)

local function CreateBankAura(currentBankSize)
	isBankBroken = false

	if promptGui then promptGui:Destroy() end

	local staticAura = workspace:FindFirstChild("PiggyBankAura", true)
	if staticAura then
		CollectionService:AddTag(staticAura, "PiggyBankAuraHolder")
	end

	promptGui = Instance.new("ScreenGui")
	promptGui.Name = "PiggyBankPromptGui"
	promptGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	promptGui.DisplayOrder = 100 
	promptGui.Parent = playerGui

	local panel = Instance.new("ImageButton", promptGui)
	panel.Name = "PromptPanel"
	-- ✨ THE FIX: Made the button significantly larger for better presence!
	panel.Size = UDim2.new(0, 280, 0, 110)

	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 1.5, 0) 
	panel.BackgroundColor3 = T.cardBG
	panel.AutoButtonColor = false
	Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)

	local stroke = Instance.new("UIStroke", panel)
	stroke.Color = T.accentGold
	stroke.Thickness = 2

	CollectionService:AddTag(panel, "Tutorial_PiggyBankPrompt")

	local counterLabel = Instance.new("TextLabel", panel)
	counterLabel.Name = "CounterLabel"
	-- Adjusted size/position for new panel scale
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
	-- Adjusted size/position for new panel scale
	title.Size = UDim2.new(1, 0, 0.4, 0)
	title.Position = UDim2.new(0, 0, 0, 12)
	title.BackgroundTransparency = 1
	title.Text = "BREAK THE BANK"
	title.TextColor3 = T.accentGold
	title.TextScaled = true
	title.Font = Enum.Font.FredokaOne

	local barBg = Instance.new("Frame", panel)
	barBg.Name = "BarBg"
	-- Adjusted size/position for new panel scale
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

	-- ✨ THE FIX: Tweens to 0.90 so it sits lower and out of the way of the Auras
	TweenService:Create(panel, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0.90, 0) 
	}):Play()

	-- ✨ THE FIX: Apply UITheme visual flair directly to the newly created elements
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

RunService.Heartbeat:Connect(function(dt)
	if inSpecialArea then
		local clickBtn = mainHUD:FindFirstChild("ClickButton", true)
		local modeToggle = mainHUD:FindFirstChild("ModeToggle", true)
		local sendBtn = mainHUD:FindFirstChild("SendButton", true)
		local hatcheryBar = mainHUD:FindFirstChild("HatcheryBar", true)
		-- ✨ THE FIX: Correctly finding AreaTravelButton based on PortalController's exact naming
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

	local clickBtn = mainHUD:FindFirstChild("ClickButton", true)
	local modeToggle = mainHUD:FindFirstChild("ModeToggle", true)
	local sendBtn = mainHUD:FindFirstChild("SendButton", true)
	local hatcheryBar = mainHUD:FindFirstChild("HatcheryBar", true)
	-- ✨ THE FIX: Correctly finding AreaTravelButton based on PortalController's exact naming
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

tell me which script id be missing
