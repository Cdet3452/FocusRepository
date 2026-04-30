-- ShopController
-- Location: StarterPlayer > StarterPlayerScripts > ShopController

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")

local UpgradeConfig     = require(ReplicatedStorage.Modules.UpgradeConfig)
local Formatter         = require(ReplicatedStorage.Modules.NumberFormatter)
local EpicUpgradeConfig = require(ReplicatedStorage.Modules.EpicUpgradeConfig)
local T                 = require(ReplicatedStorage.Modules.UITheme).Get()
local SoundConfig       = require(ReplicatedStorage.Modules.SoundConfig)
local UITheme = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UITheme"))
local T = UITheme.Get("Custom") 
local RemoteEvents      = ReplicatedStorage:WaitForChild("RemoteEvents")
local PurchaseUpgrade     = RemoteEvents:WaitForChild("PurchaseUpgrade", 15)
local UpgradeUpdated      = RemoteEvents:WaitForChild("UpgradeUpdated", 15)
local PurchaseEpicUpgrade = RemoteEvents:WaitForChild("PurchaseEpicUpgrade", 15)
local EpicUpgradeUpdated  = RemoteEvents:WaitForChild("EpicUpgradeUpdated", 15)

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainHUD   = playerGui:WaitForChild("MainHUD")

local upgradeState     = {}
local epicUpgradeState  = {}
local currentCurrency   = 0
local liveGoldenAuras   = 0
local shopOpen          = false
local activeMainTab     = "Upgrades"
local activeEpicSubTab  = "Active"
local regularCardRefs   = {}
local epicCardRefs      = {}
local isLoadingData     = true

---------------------------------------------------------------
-- INITIALIZATION (TIERED)
---------------------------------------------------------------
for _, tierData in ipairs(UpgradeConfig.Tiers) do
	for upgradeId, cfg in pairs(tierData.upgrades) do
		upgradeState[upgradeId] = {
			level = 0, maxLevel = cfg.maxLevel,
			cost = UpgradeConfig.CalculateCost(upgradeId, 0), maxed = false,
		}
	end
end

for _, tierData in ipairs(EpicUpgradeConfig.Tiers) do
	for upgradeId, cfg in pairs(tierData.upgrades) do
		epicUpgradeState[upgradeId] = {
			level = 0, maxLevel = cfg.maxLevel,
			cost = EpicUpgradeConfig.CalculateCost(upgradeId, 0), maxed = false,
		}
	end
end

local function PlayUIBurst(targetElement, amount, colorTheme)
	if not shopOpen then return end
	local burstGui = Instance.new("ScreenGui")
	burstGui.Name = "JuiceBurst"
	burstGui.Parent = playerGui

	local absPos = targetElement.AbsolutePosition
	local absSize = targetElement.AbsoluteSize
	local center = absPos + (absSize / 2)

	for i = 1, amount do
		local particle = Instance.new("Frame")
		particle.BackgroundColor3 = colorTheme or Color3.fromRGB(255, 215, 0) -- Default Gold
		particle.BorderSizePixel = 0
		particle.Size = UDim2.new(0, math.random(6, 12), 0, math.random(6, 12))
		particle.Position = UDim2.new(0, center.X, 0, center.Y)
		particle.Rotation = math.random(0, 360)

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = particle
		particle.Parent = burstGui

		local angle = math.rad(math.random(0, 360))
		local distance = math.random(50, 150)
		local endPos = UDim2.new(0, center.X + math.cos(angle) * distance, 0, center.Y + math.sin(angle) * distance + 50) 

		local tInfo = TweenInfo.new(math.random(4, 7)/10, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out)
		local tween = TweenService:Create(particle, tInfo, {
			Position = endPos,
			Size = UDim2.new(0, 0, 0, 0),
			Rotation = particle.Rotation + math.random(-180, 180),
			BackgroundTransparency = 1
		})
		tween:Play()
	end

	task.delay(1, function() burstGui:Destroy() end)
end

local comboPitch = 1.0
local lastBuyTime = tick()

local function PlayPurchaseSound()
	if tick() - lastBuyTime < 0.3 then
		comboPitch = math.min(comboPitch + 0.05, 2.5) 
	else
		comboPitch = 1.0 
	end
	lastBuyTime = tick()

	local soundsFolder = ReplicatedStorage:FindFirstChild("SFX") or ReplicatedStorage:FindFirstChild("Sounds")
	if soundsFolder and soundsFolder:FindFirstChild("BuyPing") then
		local sfx = soundsFolder.BuyPing:Clone() 
		sfx.PlaybackSpeed = comboPitch
		sfx.Parent = game:GetService("SoundService")
		sfx:Play()
		game.Debris:AddItem(sfx, 2)
	end
end

local function PlayFeedbackSound(soundName, volume)
	local soundsFolder = ReplicatedStorage:FindFirstChild("SFX") or ReplicatedStorage:FindFirstChild("Sounds")
	local soundToPlay = nil

	if soundsFolder then
		soundToPlay = soundsFolder:FindFirstChild(soundName)
	end

	if soundToPlay then
		local sfx = soundToPlay:Clone()
		sfx.Volume = volume or 0.5
		sfx.Parent = game:GetService("SoundService") 
		sfx:Play()
		game.Debris:AddItem(sfx, 3)
	else
		warn("⚠️ UI Sound Missing: You need to add a sound named '" .. tostring(soundName) .. "' inside ReplicatedStorage.SFX!")
	end
end

local lastErrorTime = tick()

local function PlayErrorFeedback(targetButton)
	if tick() - lastErrorTime < 0.25 then return end
	lastErrorTime = tick()

	local soundsFolder = ReplicatedStorage:FindFirstChild("Sounds") or ReplicatedStorage:FindFirstChild("SFX")
	if soundsFolder and soundsFolder:FindFirstChild("ErrorBuzz") then
		local sfx = soundsFolder.ErrorBuzz:Clone()
		sfx.Volume = 0.5 
		sfx.Parent = workspace
		sfx:Play()
		game.Debris:AddItem(sfx, 2)
	end

	if targetButton and targetButton.Parent then
		local origPos = targetButton.Position
		local wobbleInfo = TweenInfo.new(0.04, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 3, true)
		TweenService:Create(targetButton, wobbleInfo, {Position = origPos + UDim2.new(0, 4, 0, 0)}):Play()
	end
end

-----------------------------------------------------------
-- HELPERS
---------------------------------------------------------------
local function FormatNumber(n) return Formatter.Format(n) end
local function PlayUI(id) if shared.PlayUISound then shared.PlayUISound(id) end end

local ShopButton = Instance.new("ImageButton")
ShopButton.Name="ShopButton"; ShopButton.Size=UDim2.new(0,60,0,60)
ShopButton.AnchorPoint = Vector2.new(1, 1) -- ✨ Anchors perfectly to bottom right
ShopButton.Position = UDim2.new(0.98, 0, 0.95, 0) -- ✨ Scaled position
ShopButton.BackgroundColor3=T.buttonSecondary; ShopButton.BorderSizePixel=0
ShopButton.AutoButtonColor = false
ShopButton.ZIndex=5; ShopButton.Parent=mainHUD
ShopButton:SetAttribute("TutorialTarget", "ShopButton")
Instance.new("UICorner",ShopButton).CornerRadius=UDim.new(0.5, 0)

local shopStroke = Instance.new("UIStroke", ShopButton)
shopStroke.Color = T.accentGold; shopStroke.Thickness = 2

local shopIcon = Instance.new("ImageLabel", ShopButton)
shopIcon.Size = UDim2.new(0.6, 0, 0.6, 0); shopIcon.Position = UDim2.new(0.2, 0, 0.2, 0)
shopIcon.BackgroundTransparency = 1; shopIcon.ScaleType = Enum.ScaleType.Fit
shopIcon.Image = "rbxassetid://14916846070" -- 🖼️ PLACEHOLDER: Cart Icon ID


---------------------------------------------------------------
-- SHOP PANEL
---------------------------------------------------------------
local PANEL_MAX_W=420; local PANEL_MAX_H=510; local HEADER_H=42
local MAINTAB_H=34; local SUBTAB_H=30; local CURRENCY_H=0

local ShopPanel=Instance.new("Frame"); ShopPanel.Name="ShopPanel"
ShopPanel.Size=UDim2.new(0.88, 0, 0.82, 0)
ShopPanel.AnchorPoint=Vector2.new(0.5, 0.5)
ShopPanel.Position=UDim2.new(0.5, 0, 0.5, 0)
ShopPanel.BackgroundColor3=T.panelBG; ShopPanel.BorderSizePixel=0
ShopPanel.Visible=false; ShopPanel.ZIndex=10; ShopPanel.ClipsDescendants=true
ShopPanel.Parent=mainHUD
Instance.new("UICorner",ShopPanel).CornerRadius=UDim.new(0,10)
local sizeConstraint=Instance.new("UISizeConstraint"); sizeConstraint.MaxSize=Vector2.new(PANEL_MAX_W, PANEL_MAX_H); sizeConstraint.Parent=ShopPanel
local panelStroke=Instance.new("UIStroke"); panelStroke.Color=T.panelStroke; panelStroke.Thickness=2; panelStroke.Parent=ShopPanel

local TitleBar=Instance.new("Frame"); TitleBar.Name="TitleBar"
TitleBar.Size=UDim2.new(1,0,0,HEADER_H)
TitleBar.BackgroundColor3=T.headerBG; TitleBar.BorderSizePixel=0; TitleBar.ZIndex=11; TitleBar.Parent=ShopPanel
TitleBar.ClipsDescendants=true 
TitleBar.BackgroundTransparency = 1
Instance.new("UICorner",TitleBar).CornerRadius=UDim.new(0,10)
local TitleLabel=Instance.new("TextLabel"); TitleLabel.Size=UDim2.new(1,-50,1,0); TitleLabel.Position=UDim2.new(0,15,0,0)
TitleLabel.BackgroundTransparency=1; TitleLabel.Text="RESEARCH"; TitleLabel.TextColor3=T.headerText
TitleLabel.TextScaled=true; TitleLabel.Font=T.font; TitleLabel.TextXAlignment=Enum.TextXAlignment.Left
TitleLabel.ZIndex=12; TitleLabel.Parent=TitleBar
local CloseButton=Instance.new("TextButton"); CloseButton.Size=UDim2.new(0,30,0,30); CloseButton.Position=UDim2.new(1,-35,0,6)
CloseButton.BackgroundColor3=T.buttonRed; CloseButton.BorderSizePixel=0; CloseButton.Text="X"; CloseButton.TextColor3=T.bodyText
CloseButton.TextScaled=true; CloseButton.Font=T.font; CloseButton.ZIndex=9999; CloseButton.Parent=TitleBar
CloseButton:SetAttribute("TutorialTarget", "ShopCloseBtn")
Instance.new("UICorner",CloseButton).CornerRadius=UDim.new(0,6)

---------------------------------------------------------------
-- INFO POPUP (SCALED & CONSTRAINED SQUARE)
---------------------------------------------------------------
local InfoPopup = Instance.new("Frame")
InfoPopup.Name = "InfoPopup"
InfoPopup.Size = UDim2.new(0.85, 0, 0.6, 0) -- ✨ Now sizes relative to the Shop Panel!
InfoPopup.Position = UDim2.new(0.5, 0, 0.5, 0)
InfoPopup.AnchorPoint = Vector2.new(0.5, 0.5)
InfoPopup.BackgroundColor3 = T.cardBG 
InfoPopup.BackgroundTransparency = 0 
InfoPopup.ZIndex = 50
InfoPopup.Visible = false
InfoPopup.Parent = ShopPanel -- ✨ PARENT CHANGED FROM mainHUD TO ShopPanel
Instance.new("UICorner", InfoPopup).CornerRadius = UDim.new(0, 12)

-- ✨ FORCES IT TO BE A SQUARE REGARDLESS OF SCREEN SIZE
local AspectConstraint = Instance.new("UIAspectRatioConstraint", InfoPopup)
AspectConstraint.AspectRatio = 1.0 -- 1.0 means a perfect 1:1 square!

local InfoScale = Instance.new("UIScale", InfoPopup)
InfoScale.Scale = 1

local InfoTitle = Instance.new("TextLabel", InfoPopup)
InfoTitle.Size = UDim2.new(1, -20, 0, 35)
InfoTitle.Position = UDim2.new(0, 10, 0, 10)
InfoTitle.BackgroundTransparency = 1
InfoTitle.Text = ""
InfoTitle.TextColor3 = T.headerText
InfoTitle.TextScaled = true
InfoTitle.Font = Enum.Font.GothamBold
InfoTitle.ZIndex = 51

local InfoDesc = Instance.new("TextLabel", InfoPopup)
InfoDesc.Size = UDim2.new(1, -20, 1, -110)
InfoDesc.Position = UDim2.new(0, 10, 0, 55)
InfoDesc.BackgroundTransparency = 1
InfoDesc.Text = ""
InfoDesc.TextColor3 = T.bodyText
InfoDesc.TextWrapped = true
InfoDesc.TextScaled = true
InfoDesc.Font = T.font
InfoDesc.TextYAlignment = Enum.TextYAlignment.Top
InfoDesc.ZIndex = 51

local InfoClose = Instance.new("TextButton", InfoPopup)
InfoClose.Size = UDim2.new(0.6, 0, 0, 40) -- Made slightly narrower to fit the square look
InfoClose.Position = UDim2.new(0.2, 0, 1, -50)
InfoClose.BackgroundColor3 = T.buttonPrimary
InfoClose.BorderSizePixel = 0
InfoClose.Text = "Close"
InfoClose.TextColor3 = T.headerText
InfoClose.TextScaled = true
InfoClose.Font = T.font
InfoClose.ZIndex = 51
Instance.new("UICorner", InfoClose).CornerRadius = UDim.new(0, 8)

local function ShowInfo(title, desc)
	if shared.PlayUISound then shared.PlayUISound(SoundConfig.UIClick or "") end
	InfoTitle.Text = title
	InfoDesc.Text = desc
	InfoPopup.BackgroundTransparency = 0 

	InfoScale.Scale = 0.5
	InfoPopup.Visible = true
	game:GetService("TweenService"):Create(InfoScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
end

InfoClose.MouseButton1Down:Connect(function()
	if shared.PlayUISound then shared.PlayUISound(SoundConfig.UIClick or "") end
	local tween = game:GetService("TweenService"):Create(InfoScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In), {Scale = 0.5})
	tween:Play()
	tween.Completed:Once(function()
		InfoPopup.Visible = false
	end)
end)

---------------------------------------------------------------
-- CIRCULAR SHOP TABS
---------------------------------------------------------------
local activeShopTabText = "Regular Upgrades"

local MainTabBar = Instance.new("Frame")
MainTabBar.Size = UDim2.new(1, -20, 0, 85) -- ✨ Made taller (was 75)
MainTabBar.Position = UDim2.new(0, 10, 0, HEADER_H + 4)
MainTabBar.BackgroundTransparency = 1; MainTabBar.ZIndex = 11; MainTabBar.Parent = ShopPanel

-- ✨ MOVED TEXT TO THE TOP OF THE BAR
local ShopHoverLabel = Instance.new("TextLabel", MainTabBar)
ShopHoverLabel.Size = UDim2.new(1, 0, 0, 20)
ShopHoverLabel.Position = UDim2.new(0, 0, 0, 0) -- Locks perfectly to the top
ShopHoverLabel.BackgroundTransparency = 1; ShopHoverLabel.TextColor3 = T.bodyText
ShopHoverLabel.TextScaled = true; ShopHoverLabel.Font = T.font
ShopHoverLabel.Text = activeShopTabText

-- ✨ PUSHED THE BUTTONS DOWN SO THEY DON'T OVERLAP
local TabBtnFrame = Instance.new("Frame", MainTabBar)
TabBtnFrame.Size = UDim2.new(1, 0, 1, -25)
TabBtnFrame.Position = UDim2.new(0, 0, 0, 25) -- Pushed down 25 pixels
TabBtnFrame.BackgroundTransparency = 1

local TabListLayout = Instance.new("UIListLayout", TabBtnFrame)
TabListLayout.FillDirection = Enum.FillDirection.Horizontal
TabListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
TabListLayout.VerticalAlignment = Enum.VerticalAlignment.Center
TabListLayout.Padding = UDim.new(0, 25)

-- (Keep your local mainTabButtons = {} and MakeMainTab function exactly as it is below this!)

local TAB_COLOR_BASE   = T.buttonSecondary
local TAB_COLOR_HOVER  = T.buttonPrimary    -- Color when mouse is over it
local TAB_COLOR_ACTIVE = T.accentGold       -- Color when tab is selected

local mainTabButtons = {}
local function MakeMainTab(name, hoverText, iconId)
	local btn = Instance.new("ImageButton", TabBtnFrame)
	btn.Name = "MainTab_" .. name
	btn.Size = UDim2.new(0, 48, 0, 48)
	btn.BackgroundColor3 = TAB_COLOR_BASE; btn.AutoButtonColor = false
	btn.ZIndex = 12
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0.5, 0)

	local stroke = Instance.new("UIStroke", btn)
	stroke.Color = T.panelStroke; stroke.Thickness = 2

	local icon = Instance.new("ImageLabel", btn)
	icon.Size = UDim2.new(0.6, 0, 0.6, 0); icon.Position = UDim2.new(0.2, 0, 0.2, 0)
	icon.BackgroundTransparency = 1; icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = iconId

	-- ✨ SMART HOVER LOGIC
	btn.MouseEnter:Connect(function() 
		ShopHoverLabel.Text = hoverText 
		if activeMainTab ~= name then btn.BackgroundColor3 = TAB_COLOR_HOVER end
	end)

	btn.MouseLeave:Connect(function() 
		ShopHoverLabel.Text = activeShopTabText 
		if activeMainTab ~= name then btn.BackgroundColor3 = TAB_COLOR_BASE end
	end)

	mainTabButtons[name] = {btn = btn, stroke = stroke}
	return btn
end
local tabEpic     = MakeMainTab("Epic", "Epic Research", "rbxassetid://14916846070")

local tabUpgrades = MakeMainTab("Upgrades", "Regular Upgrades", "rbxassetid://14916846070")

-----------------------------
-- CURRENCY LABEL
---------------------------------------------------------------
local CurrencyLabel=Instance.new("TextLabel"); CurrencyLabel.Name="ShopCurrencyLabel"
CurrencyLabel.Size=UDim2.new(1,-24,0,CURRENCY_H); CurrencyLabel.BackgroundTransparency=1
CurrencyLabel.Text="$0"; CurrencyLabel.TextColor3=T.currencyColor; CurrencyLabel.TextScaled=true
CurrencyLabel.Font=T.font; CurrencyLabel.TextXAlignment=Enum.TextXAlignment.Right
CurrencyLabel.ZIndex=11; CurrencyLabel.Parent=ShopPanel

local function MakeScroll(name,yTop)
	local sf=Instance.new("ScrollingFrame"); sf.Name=name
	sf.Size=UDim2.new(1,-20,1,-(yTop+10)); sf.Position=UDim2.new(0,10,0,yTop)
	sf.BackgroundTransparency=1; sf.BorderSizePixel=0; sf.ScrollBarThickness=4; sf.ScrollBarImageColor3=T.subText
	sf.CanvasSize=UDim2.new(0,0,0,0); sf.ZIndex=11; sf.Visible=false; sf.Parent=ShopPanel

	-- ✨ THIS IS THE MAGIC LINE THAT STOPS SCROLL OVERLAP:
	sf.ClipsDescendants = true 

	local layout=Instance.new("UIListLayout"); layout.Padding=UDim.new(0,8); layout.Parent=sf
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		sf.CanvasSize=UDim2.new(0,0,0,layout.AbsoluteContentSize.Y+10)
	end); return sf
end

-- ✨ Math fixed: Pushed down to clear the 85px tall MainTabBar
local REGULAR_SCROLL_TOP = HEADER_H + 95 
local RegularScroll = MakeScroll("RegularScroll", REGULAR_SCROLL_TOP)
local EPIC_SCROLL_TOP = HEADER_H + 95
local EpicScroll = MakeScroll("EpicScroll", EPIC_SCROLL_TOP)

local activeEpicSubTab = "Epic"
---------------------------------------------------------------
-- CARD BUILDER
---------------------------------------------------------------
local function BuildCard(parent, upgradeId, cfg, isEpic, cardRefsTable)
	local card = Instance.new("Frame")
	card.Name = "Card_"..upgradeId
	card.Size = UDim2.new(1, 0, 0, 100)
	card.BackgroundColor3 = T.cardBG 
	card.BorderSizePixel = 0; card.Parent = parent
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)

	local icon = Instance.new("ImageLabel", card)
	icon.Size = UDim2.new(0, 50, 0, 50); icon.Position = UDim2.new(0, 15, 0.5, -25)
	icon.BackgroundTransparency = 1
	icon.Image = cfg.iconId or "rbxassetid://0" 

	local infoBtn = Instance.new("TextButton", card)
	infoBtn.Size = UDim2.new(0, 22, 0, 22); infoBtn.Position = UDim2.new(0, 75, 0, 12)
	infoBtn.BackgroundColor3 = T.buttonSecondary 
	infoBtn.Text = "i"; infoBtn.TextColor3 = T.bodyText
	infoBtn.Font = Enum.Font.GothamBlack; infoBtn.TextSize = 14
	Instance.new("UICorner", infoBtn).CornerRadius = UDim.new(1, 0)
	infoBtn.MouseButton1Click:Connect(function() ShowInfo(cfg.displayName, cfg.description) end)

	local nameLabel = Instance.new("TextLabel", card)
	nameLabel.Size = UDim2.new(0.74, -120, 0, 24); nameLabel.Position = UDim2.new(0, 102, 0, 11)
	nameLabel.BackgroundTransparency = 1; nameLabel.Text = string.upper(cfg.displayName)
	nameLabel.TextColor3 = T.bodyText 
	nameLabel.TextScaled = true; nameLabel.Font = Enum.Font.FredokaOne
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left

	local descLabel = Instance.new("TextLabel", card)
	descLabel.Size = UDim2.new(0.74, -95, 0, 36); descLabel.Position = UDim2.new(0, 75, 0, 38)
	descLabel.BackgroundTransparency = 1; descLabel.Text = cfg.description
	descLabel.TextColor3 = T.subText 
	descLabel.TextWrapped = true; descLabel.TextSize = 16; descLabel.Font = Enum.Font.GothamMedium
	descLabel.TextXAlignment = Enum.TextXAlignment.Left; descLabel.TextYAlignment = Enum.TextYAlignment.Top

	local levelLabel = Instance.new("TextLabel", card)
	levelLabel.Size = UDim2.new(0.74, -95, 0, 18); levelLabel.Position = UDim2.new(0, 75, 0, 76)
	levelLabel.BackgroundTransparency = 1; levelLabel.Text = "Lv. 0 / "..cfg.maxLevel
	levelLabel.TextColor3 = T.accentGreen
	levelLabel.TextSize = 16; levelLabel.Font = Enum.Font.FredokaOne; levelLabel.TextXAlignment = Enum.TextXAlignment.Left

	local buyButton = Instance.new("TextButton", card)
	buyButton.Name = "PurchaseButton" -- ✨ ADDED NAME so particle script can find it
	buyButton.Size = UDim2.new(0.24, 0, 0, 46); buyButton.AnchorPoint = Vector2.new(1, 0.5)
	buyButton.Position = UDim2.new(1, -12, 0.5, 0)
	buyButton.BackgroundColor3 = isEpic and T.accentPurple or T.buttonGreen
	buyButton.BorderSizePixel = 0; buyButton.TextColor3 = T.bodyText
	buyButton.TextScaled = true; buyButton.Font = Enum.Font.FredokaOne
	Instance.new("UICorner", buyButton).CornerRadius = UDim.new(0, 8)

	cardRefsTable[upgradeId] = {
		frame = card, levelLabel = levelLabel, buyButton = buyButton, isEpic = isEpic, tab = cfg.category
	}

	local holdingBuy = false; local buyGeneration = 0

	-- ✨ THE MEMORY FIX: Checks if you have ever passed the tutorial
	local tutorialLockLifted = false
	local function IsTutorialFinished()
		if tutorialLockLifted then return true end -- If we already lifted it, keep it lifted forever!
		if liveGoldenAuras > 0 then tutorialLockLifted = true; return true end -- You prestiged!
		for _, state in pairs(epicUpgradeState) do
			if state.level > 0 then tutorialLockLifted = true; return true end -- You have epic upgrades!
		end
		local valState = upgradeState["blockValue"]
		if valState and valState.level > 0 then tutorialLockLifted = true; return true end -- You bought the tutorial upgrade!
		return false
	end

	local function TryBuy()
		if isEpic then
			local state = epicUpgradeState[upgradeId]
			if not state or state.maxed then return end 

			-- ✨ THE EPIC TUTORIAL LOCK (Uses Memory):
			if not IsTutorialFinished() then
				PlayErrorFeedback(buyButton) -- Buzz error
				return -- Cancel the purchase!
			end
			-- ✨ ==========================================

			if liveGoldenAuras < state.cost then PlayErrorFeedback(buyButton); return end

			local wasMaxedLocally = state.maxed; liveGoldenAuras -= state.cost; state.level += 1
			state.maxed = (state.level >= state.maxLevel)
			state.cost = state.maxed and 0 or EpicUpgradeConfig.CalculateCost(upgradeId, state.level)

			if state.maxed and not wasMaxedLocally then PlayFeedbackSound("MaxOut", 0.6); PlayUIBurst(buyButton, 20) else PlayPurchaseSound() end
			UpdateEpicCard(upgradeId); UpdateCurrencyDisplay(); PurchaseEpicUpgrade:FireServer(upgradeId)
		else
			local state = upgradeState[upgradeId]
			if not state or state.maxed then return end 

			-- ✨ THE REGULAR TUTORIAL LOCK (Uses Memory):
			if not IsTutorialFinished() and upgradeId ~= "blockValue" then
				PlayErrorFeedback(buyButton) -- Shake the wrong button and play error sound
				return -- Cancel the purchase entirely!
			end
			-- ✨ ==========================================

			if currentCurrency < state.cost then PlayErrorFeedback(buyButton); return end

			local wasMaxedLocally = state.maxed; currentCurrency -= state.cost; state.level += 1
			state.maxed = (state.level >= state.maxLevel)
			state.cost = state.maxed and 0 or UpgradeConfig.CalculateCost(upgradeId, state.level)

			if state.maxed and not wasMaxedLocally then PlayFeedbackSound("MaxOut", 0.6); PlayUIBurst(buyButton, 20) else PlayPurchaseSound() end
			UpdateRegularCard(upgradeId); UpdateCurrencyDisplay(); PurchaseUpgrade:FireServer(upgradeId)
		end
	end

	local pulseTween = nil

	buyButton.MouseButton1Down:Connect(function()
		buyGeneration += 1
		local myGen = buyGeneration
		holdingBuy = true

		local scale = buyButton:FindFirstChildOfClass("UIScale")
		if not scale then 
			scale = Instance.new("UIScale")
			scale.Parent = buyButton 
		end

		pulseTween = TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {Scale = 0.88})
		pulseTween:Play()

		TryBuy() 
		task.wait(0.3) 
		local holdStart = tick()

		local UserInputService = game:GetService("UserInputService")
		
		
		local epicHoldSpeedLevel = (epicUpgradeState["epicHoldSpeed"] and epicUpgradeState["epicHoldSpeed"].level) or 0
		local holdSpeedMultiplier = 1 + (epicHoldSpeedLevel * 0.3) -- +30% speed per level

		while holdingBuy and buyGeneration == myGen do
			if not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
				holdingBuy = false
				break
			end
			TryBuy()
			-- Base speed gets divided by your epic speed multiplier!
			task.wait(math.max(0.01, (0.15 - ((tick() - holdStart) * 0.05)) / holdSpeedMultiplier))
		end

		if pulseTween then pulseTween:Cancel() end
		if scale then TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), {Scale = 1}):Play() end
	end)

	buyButton.MouseButton1Up:Connect(function() 
		holdingBuy = false 
		if pulseTween then pulseTween:Cancel() end
		local scale = buyButton:FindFirstChildOfClass("UIScale")
		if scale then TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), {Scale = 1}):Play() end
	end)

	buyButton.MouseLeave:Connect(function() 
		holdingBuy = false 
		if pulseTween then pulseTween:Cancel() end
		local scale = buyButton:FindFirstChildOfClass("UIScale")
		if scale then TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), {Scale = 1}):Play() end
	end)
end

---------------------------------------------------------------
-- BUILD CARDS & DYNAMIC REBUILDER
---------------------------------------------------------------
local epicOrderIndex = 1
for _, tab in ipairs(EpicUpgradeConfig.Tabs) do
	for _, tierData in ipairs(EpicUpgradeConfig.Tiers) do
		for upgradeId, cfg in pairs(tierData.upgrades) do
			BuildCard(EpicScroll, upgradeId, cfg, true, epicCardRefs) 

			local ref = epicCardRefs[upgradeId]
			if ref and ref.frame then
				ref.baseOrder = epicOrderIndex
				ref.frame.LayoutOrder = epicOrderIndex
				epicOrderIndex += 1

				ref.frame.Visible = false 
				ref.frame.Parent = EpicScroll

				if UITheme and UITheme.Apply then UITheme.Apply(ref.frame, "ShopCard") end
			end
		end
	end
end

function UpdateRegularCard(upgradeId)
	local ref=regularCardRefs[upgradeId]; local state=upgradeState[upgradeId]
	if not ref or not state then return end

	if UITheme and UITheme.Apply then
		UITheme.Apply(ref.frame, "ShopCard")
	end

	ref.levelLabel.Text="Lv. "..state.level.." / "..state.maxLevel

	if state.level >= state.maxLevel then
		ref.frame.LayoutOrder = (ref.baseOrder or 0) + 100000 
		ref.levelLabel.TextColor3=Color3.fromRGB(255, 215, 0) 
		ref.buyButton.Text="MAX"
		ref.buyButton.TextColor3=Color3.fromRGB(255, 255, 255) 
		ref.buyButton.BackgroundColor3=Color3.fromRGB(100, 100, 100)
	else
		ref.frame.LayoutOrder = ref.baseOrder or 0 

		if currentCurrency<state.cost then
			ref.buyButton.Text="$"..FormatNumber(state.cost)
			ref.buyButton.TextColor3=Color3.fromRGB(255, 100, 100) 
			ref.buyButton.BackgroundColor3=Color3.fromRGB(60, 170, 80) 
		else
			ref.buyButton.Text="$"..FormatNumber(state.cost)
			ref.buyButton.TextColor3=Color3.fromRGB(255, 255, 255) 
			ref.buyButton.BackgroundColor3=Color3.fromRGB(60, 170, 80) 
		end
	end
end

function UpdateEpicCard(upgradeId)
	local ref=epicCardRefs[upgradeId]; local state=epicUpgradeState[upgradeId]
	if not ref or not state then return end

	if UITheme and UITheme.Apply then
		UITheme.Apply(ref.frame, "ShopCard")
	end

	ref.levelLabel.Text="Lv. "..state.level.." / "..state.maxLevel

	if state.level >= state.maxLevel then
		ref.frame.LayoutOrder = (ref.baseOrder or 0) + 100000 
		ref.levelLabel.TextColor3=Color3.fromRGB(255, 215, 0)
		ref.buyButton.Text="MAX"
		ref.buyButton.TextColor3=Color3.fromRGB(255, 255, 255)
		ref.buyButton.BackgroundColor3=Color3.fromRGB(100, 100, 100)
	else
		ref.frame.LayoutOrder = ref.baseOrder or 0 

		if liveGoldenAuras<state.cost then
			ref.buyButton.Text="✦ "..FormatNumber(state.cost)
			ref.buyButton.TextColor3=Color3.fromRGB(255, 100, 100) 
			ref.buyButton.BackgroundColor3=Color3.fromRGB(150, 80, 255) 
		else
			ref.buyButton.Text="✦ "..FormatNumber(state.cost)
			ref.buyButton.TextColor3=Color3.fromRGB(255, 255, 255) 
			ref.buyButton.BackgroundColor3=Color3.fromRGB(150, 80, 255) 
		end
	end
end
local function UpdateAllRegularCards() for id in pairs(regularCardRefs) do UpdateRegularCard(id) end end
local function UpdateAllEpicCards() for id in pairs(epicCardRefs) do UpdateEpicCard(id) end end

local function CreateTierHeader(tierName)
	local header = Instance.new("Frame")
	header.Name = "TierHeader"; header.Size = UDim2.new(1, 0, 0, 30); header.BackgroundTransparency = 1

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, -5); label.Position = UDim2.new(0, 0, 0, 0); label.BackgroundTransparency = 1
	label.Text = string.upper(tierName); label.TextColor3 = Color3.fromRGB(220, 220, 220)
	label.TextSize = 16; label.Font = Enum.Font.GothamBlack; 
	label.TextXAlignment = Enum.TextXAlignment.Left 
	label.Parent = header

	local line = Instance.new("Frame")
	line.Size = UDim2.new(1, 0, 0, 2); line.Position = UDim2.new(0, 0, 1, -2) 
	line.BackgroundColor3 = Color3.fromRGB(100, 100, 100); line.BorderSizePixel = 0; line.Parent = header
	return header
end

local function CreateLockedTierHeader(tierName, current, required)
	local header = Instance.new("Frame")
	header.Name = "TierHeader_Locked"; header.Size = UDim2.new(1, 0, 0, 45); header.BackgroundTransparency = 1
	header:SetAttribute("Required", required) 

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0.5, 0); label.Position = UDim2.new(0, 0, 0, 0); label.BackgroundTransparency = 1
	label.Text = string.upper(tierName) .. " (LOCKED)"; label.TextColor3 = Color3.fromRGB(150, 150, 150)
	label.TextSize = 16; label.Font = Enum.Font.GothamBlack; 
	label.TextXAlignment = Enum.TextXAlignment.Left; label.Parent = header

	local progress = Instance.new("TextLabel")
	progress.Name = "ProgressLabel" 
	progress.Size = UDim2.new(1, 0, 0.4, 0); progress.Position = UDim2.new(0, 0, 0.6, 0); progress.BackgroundTransparency = 1
	progress.Text = current .. " / " .. required .. " Upgrades Needed"
	progress.TextColor3 = Color3.fromRGB(255, 100, 100) 
	progress.TextSize = 12; progress.Font = Enum.Font.GothamBold; 
	progress.TextXAlignment = Enum.TextXAlignment.Left; progress.Parent = header

	local line = Instance.new("Frame")
	line.Size = UDim2.new(1, 0, 0, 2); line.Position = UDim2.new(0, 0, 1, -2)
	line.BackgroundColor3 = Color3.fromRGB(80, 80, 80); line.BorderSizePixel = 0; line.Parent = header
	return header
end

local function RebuildRegularShop()
	for _, child in ipairs(RegularScroll:GetChildren()) do
		if child:IsA("Frame") and child.Name ~= "CardTemplate" then
			if not string.find(child.Name, "TierHeader") then UITheme.Apply(child, "ShopCard") end
			child:Destroy() 
		end
	end
	regularCardRefs = {}

	local totalUpgradesBought = 0
	for _, state in pairs(upgradeState) do totalUpgradesBought = totalUpgradesBought + (state.level or 0) end

	local listOrder = 1 

	for tierNum, tierData in ipairs(UpgradeConfig.Tiers) do
		if totalUpgradesBought >= tierData.unlockRequirement then
			local header = CreateTierHeader(tierData.tierName or "Tier " .. tierNum)
			header.LayoutOrder = listOrder
			listOrder += 1
			header.Parent = RegularScroll

			for upgradeId, cfg in pairs(tierData.upgrades) do
				BuildCard(RegularScroll, upgradeId, cfg, false, regularCardRefs) 
				local ref = regularCardRefs[upgradeId]

				if ref and ref.frame then
					-- ✨ THE FIX: Just these 3 lines! (Deleted the old local buyBtn line)
					if ref.buyButton then
						ref.buyButton.Name = "Buy_" .. upgradeId
					end
					-- ✨ ==========================================

					ref.baseOrder = listOrder
					ref.frame.LayoutOrder = listOrder
					listOrder += 1

					ref.frame.Visible = true
					ref.frame.Parent = RegularScroll

					if UITheme and UITheme.Apply then UITheme.Apply(ref.frame, "ShopCard") end
					local myColor = Color3.fromRGB(45, 30, 55)
					ref.frame:SetAttribute("TierColor", myColor)
					ref.frame.BackgroundColor3 = myColor
				end
			end
		else
			local lockedHeader = CreateLockedTierHeader(tierData.tierName or "Tier " .. tierNum, totalUpgradesBought, tierData.unlockRequirement)
			lockedHeader.LayoutOrder = listOrder
			lockedHeader.Parent = RegularScroll
			break 
		end
	end
	UpdateAllRegularCards()
end 
RebuildRegularShop() 

task.delay(1, function()
	isLoadingData = false
end)

function UpdateCurrencyDisplay()
	if activeMainTab=="Upgrades" then
		CurrencyLabel.Text="$"..FormatNumber(currentCurrency); CurrencyLabel.TextColor3=T.currencyColor
		CurrencyLabel.Position=UDim2.new(0,12,0,HEADER_H+MAINTAB_H+8)
	end
end

---------------------------------------------------------------
-- TAB SWITCHING
---------------------------------------------------------------
local function HighlightMainTab(tabName)
	for name,btn in pairs(mainTabButtons) do btn.BackgroundColor3=(name==tabName) and T.panelStroke or T.buttonSecondary end
end
local function SwitchToMainTab(tabName)
	if shared.PlayUISound then shared.PlayUISound(SoundConfig.UIClick or "") end
	activeMainTab = tabName
	
	activeShopTabText = (tabName == "Epic") and "Epic Research" or "Regular Upgrades"
	ShopHoverLabel.Text = activeShopTabText

	for name, data in pairs(mainTabButtons) do
		data.btn.BackgroundColor3 = (name == tabName) and TAB_COLOR_ACTIVE or TAB_COLOR_BASE
		data.stroke.Color = (name == tabName) and T.bodyText or T.panelStroke
	end

	RegularScroll.Visible = (tabName == "Upgrades")
	EpicScroll.Visible    = (tabName == "Epic")

	-- ✨ Instantly show ALL epic cards when switching to the Epic tab
	if tabName == "Epic" then
		for id, ref in pairs(epicCardRefs) do
			if ref and ref.frame then
				ref.frame.Visible = true 
			end
		end
		if EpicScroll then EpicScroll.CanvasPosition = Vector2.new(0,0) end
	end
end

tabUpgrades.MouseButton1Down:Connect(function() PlayUI(SoundConfig.UIClick); SwitchToMainTab("Upgrades") end)
tabEpic.MouseButton1Down:Connect(function() PlayUI(SoundConfig.UIClick); SwitchToMainTab("Epic") end)

---------------------------------------------------------------
-- OPEN / CLOSE
---------------------------------------------------------------
local function OpenShop()
	shopOpen=true; ShopPanel.Visible=true; ShopPanel.Size=UDim2.new(0.88, 0, 0, 0)
	SwitchToMainTab(activeMainTab)
	TweenService:Create(ShopPanel,TweenInfo.new(0.3,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
		{Size=UDim2.new(0.88, 0, 0.82, 0)}):Play()
	UITheme.SetMenuVisible(true)
	ShopButton.BackgroundColor3=T.panelStroke
end
local function CloseShop()
	shopOpen=false; PlayUI(SoundConfig.UIClose)
	TweenService:Create(ShopPanel,TweenInfo.new(0.22,Enum.EasingStyle.Quad,Enum.EasingDirection.In),
		{Size=UDim2.new(0.88, 0, 0, 0)}):Play()
	UITheme.SetMenuVisible(false)
	task.delay(0.25, function() ShopPanel.Visible=false end)
	ShopButton.BackgroundColor3=T.buttonSecondary
end
ShopButton.MouseButton1Down:Connect(function() if shopOpen then CloseShop() else OpenShop() end end)
CloseButton.MouseButton1Down:Connect(CloseShop)

---------------------------------------------------------------
-- CURRENCY SYNC
---------------------------------------------------------------
local ratePerSecond=0
local UpdateHUD=ReplicatedStorage.RemoteEvents:WaitForChild("UpdateHUD")
UpdateHUD.OnClientEvent:Connect(function(stats)
	if stats.currency~=nil then
		if stats.currency>currentCurrency then currentCurrency=stats.currency end
	end
	if stats.goldenAuras~=nil then liveGoldenAuras=stats.goldenAuras end
	if stats.rate and stats.passiveInterval then
		local interval=stats.passiveInterval
		ratePerSecond=(interval>0 and stats.rate>0) and (stats.rate/interval) or 0
	end
end)

---------------------------------------------------------------
-- LIVE UPDATE LOOP
---------------------------------------------------------------
local lastCardUpdate=0
RunService.Heartbeat:Connect(function(dt)
	if not shopOpen then return end
	if ratePerSecond>0 then currentCurrency+=ratePerSecond*dt end
	local now=tick()
	if now-lastCardUpdate>0.3 then
		lastCardUpdate=now
		if activeMainTab=="Upgrades" then UpdateAllRegularCards() else UpdateAllEpicCards() end
		UpdateCurrencyDisplay()
	end
end)

---------------------------------------------------------------
-- SERVER EVENTS (Cleaned of Sound/UI logic)
---------------------------------------------------------------
if UpgradeUpdated then
	UpgradeUpdated.OnClientEvent:Connect(function(info)
		if info.type=="fullState" then
			upgradeState=info.upgrades; currentCurrency=info.currency; 
			RebuildRegularShop()
			UpdateCurrencyDisplay()

		elseif info.type=="purchased" then
			local current = upgradeState[info.upgradeId]

			if not current or info.level >= current.level then
				upgradeState[info.upgradeId]={level=info.level,maxLevel=info.maxLevel,cost=info.cost,maxed=info.maxed}
			end
			currentCurrency = info.currency

			local scroll = ShopPanel:FindFirstChild("RegularScroll")
			local savedScroll = scroll and scroll.CanvasPosition or Vector2.new(0, 0)

			-- ✨ Safely updates the shop tiers WITHOUT triggering ghost sounds!
			RebuildRegularShop()
			UpdateCurrencyDisplay()

			if scroll then
				scroll.CanvasPosition = savedScroll
			end
		end
	end)
end

if EpicUpgradeUpdated then
	EpicUpgradeUpdated.OnClientEvent:Connect(function(info)
		if info.type=="fullState" then
			epicUpgradeState=info.upgrades; liveGoldenAuras=info.goldenAuras or liveGoldenAuras
			UpdateAllEpicCards(); UpdateCurrencyDisplay()

		elseif info.type=="purchased" then
			local current = epicUpgradeState[info.upgradeId]

			if not current or info.level >= current.level then
				epicUpgradeState[info.upgradeId]={level=info.level,maxLevel=info.maxLevel,cost=info.cost,maxed=info.maxed}
			end
			UpdateEpicCard(info.upgradeId); UpdateCurrencyDisplay()
		end
	end)
end

---------------------------------------------------------------
-- UI JUICE: Button Hover & Click Animations
---------------------------------------------------------------
local function AddButtonJuice(btn)
	local scale = btn:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = btn
	end

	btn.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Sine), {Scale = 1.08}):Play()
	end)

	btn.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Sine), {Scale = 1}):Play()
	end)

	btn.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1, Enum.EasingStyle.Sine), {Scale = 0.9}):Play()
	end)

	btn.MouseButton1Up:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), {Scale = 1.08}):Play()
	end)
end

AddButtonJuice(ShopButton)
AddButtonJuice(CloseButton)
AddButtonJuice(ShopButton)
AddButtonJuice(tabUpgrades)
AddButtonJuice(tabEpic)
AddButtonJuice(CloseButton)
---------------------------------------------------------------
-- REFRESH LOOK + APPLY SHINE TO TITLE BAR
---------------------------------------------------------------
local shopShine = nil
local titleFlair = nil
local TitleShine = nil
local flairedExtraUI = false

local function RefreshLook()
	UITheme.Apply(ShopPanel, "Panel")
	UITheme.Apply(ShopPanel, "TitleBar")

	if not shopShine then
		shopShine = UITheme.ApplyShine(ShopPanel)
		TitleShine = UITheme.ApplyShine(TitleBar)
	end

	if not titleFlair then
		titleFlair = UITheme.ApplyFlair(TitleLabel, "Ghost")
	end

	-- ✨ THE FLAIR INJECTOR FOR ALL CIRCLES AND LINES
	if not flairedExtraUI then
		flairedExtraUI = true
		-- Flair all the new circular tabs!
	end

	for _, scrollName in ipairs({"RegularScroll", "EpicScroll"}) do
		local scroll = ShopPanel:FindFirstChild(scrollName) 
		if scroll then
			local layout = scroll:FindFirstChildOfClass("UIListLayout")
			if layout then layout.SortOrder = Enum.SortOrder.LayoutOrder end
		end
	end

	local outerStroke = ShopPanel:FindFirstChildWhichIsA("UIStroke")
	if outerStroke then
		outerStroke.Color = Color3.fromRGB(255, 255, 255) 
	end
end

task.wait(2)
RefreshLook()
