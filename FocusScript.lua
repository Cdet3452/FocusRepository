-- ShopController
-- Location: StarterPlayer > StarterPlayerScripts > ShopController

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local UpgradeConfig     = require(ReplicatedStorage.Modules.UpgradeConfig)
local Formatter         = require(ReplicatedStorage.Modules.NumberFormatter)
local EpicUpgradeConfig = require(ReplicatedStorage.Modules.EpicUpgradeConfig)
local UITheme           = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UITheme"))
local T                 = UITheme.Get("Custom")
local SoundConfig       = require(ReplicatedStorage.Modules.SoundConfig)

local RemoteEvents        = ReplicatedStorage:WaitForChild("RemoteEvents")
local PurchaseUpgrade     = RemoteEvents:WaitForChild("PurchaseUpgrade", 15)
local UpgradeUpdated      = RemoteEvents:WaitForChild("UpgradeUpdated", 15)
local PurchaseEpicUpgrade = RemoteEvents:WaitForChild("PurchaseEpicUpgrade", 15)
local EpicUpgradeUpdated  = RemoteEvents:WaitForChild("EpicUpgradeUpdated", 15)

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainHUD   = playerGui:WaitForChild("MainHUD")

local upgradeState      = {}
local epicUpgradeState  = {}
local currentCurrency   = 0
local liveGoldenAuras   = 0
local shopOpen          = false
local activeMainTab     = "Upgrades"
local regularCardRefs   = {}
local epicCardRefs      = {}
local isLoadingData     = true
local globalHoldActive  = false  -- Global flag to prevent multiple simultaneous holds
local globalHoldGeneration = 0    -- Global generation counter

-- FORWARD DECLARATIONS
local UpdateLockedTierProgress = nil
local RebuildRegularShop = nil 

-- ─────────────────────────────────────────────────────────────────────────────
-- INITIALIZATION
-- ─────────────────────────────────────────────────────────────────────────────
for _, tierData in ipairs(UpgradeConfig.Tiers) do
	for upgradeId, cfg in pairs(tierData.upgrades) do
		upgradeState[upgradeId] = {
			level    = 0,
			maxLevel = cfg.maxLevel,
			cost     = UpgradeConfig.CalculateCost(upgradeId, 0),
			maxed    = false,
		}
	end
end

for _, tierData in ipairs(EpicUpgradeConfig.Tiers) do
	for upgradeId, cfg in pairs(tierData.upgrades) do
		epicUpgradeState[upgradeId] = {
			level    = 0,
			maxLevel = cfg.maxLevel,
			cost     = EpicUpgradeConfig.CalculateCost(upgradeId, 0),
			maxed    = false,
		}
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- VFX / SOUND HELPERS
-- ─────────────────────────────────────────────────────────────────────────────
local function PlayUIBurst(targetElement, amount, colorTheme)
	if not shopOpen then return end
	local burstGui = Instance.new("ScreenGui")
	burstGui.Name   = "JuiceBurst"
	burstGui.Parent = playerGui

	local absPos  = targetElement.AbsolutePosition
	local absSize = targetElement.AbsoluteSize
	local center  = absPos + (absSize / 2)

	for i = 1, amount do
		local particle = Instance.new("Frame")
		particle.BackgroundColor3 = colorTheme or Color3.fromRGB(255, 215, 0)
		particle.BorderSizePixel  = 0
		particle.Size             = UDim2.new(0, math.random(6, 12), 0, math.random(6, 12))
		particle.Position         = UDim2.new(0, center.X, 0, center.Y)
		particle.Rotation         = math.random(0, 360)

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent       = particle
		particle.Parent     = burstGui

		local angle    = math.rad(math.random(0, 360))
		local distance = math.random(50, 150)
		local endPos   = UDim2.new(0, center.X + math.cos(angle) * distance, 0, center.Y + math.sin(angle) * distance + 50)

		local tInfo = TweenInfo.new(math.random(4, 7) / 10, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out)
		TweenService:Create(particle, tInfo, {
			Position             = endPos,
			Size                 = UDim2.new(0, 0, 0, 0),
			Rotation             = particle.Rotation + math.random(-180, 180),
			BackgroundTransparency = 1,
		}):Play()
	end

	task.delay(1, function() burstGui:Destroy() end)
end

local comboPitch  = 1.0
local lastBuyTime = tick()

local function PlayPurchaseSound()
	if tick() - lastBuyTime < 0.3 then
		comboPitch = math.min(comboPitch + 0.05, 2.5)
	else
		comboPitch = 1.0
	end
	lastBuyTime = tick()

	local sfxFolder = ReplicatedStorage:FindFirstChild("SFX") or ReplicatedStorage:FindFirstChild("Sounds")
	if sfxFolder and sfxFolder:FindFirstChild("BuyPing") then
		local sfx = sfxFolder.BuyPing:Clone()
		sfx.PlaybackSpeed = comboPitch
		sfx.Parent        = game:GetService("SoundService")
		sfx:Play()
		game.Debris:AddItem(sfx, 2)
	end
end

local function PlayFeedbackSound(soundName, volume)
	local sfxFolder = ReplicatedStorage:FindFirstChild("SFX") or ReplicatedStorage:FindFirstChild("Sounds")
	if sfxFolder then
		local s = sfxFolder:FindFirstChild(soundName)
		if s then
			local sfx = s:Clone()
			sfx.Volume = volume or 0.5
			sfx.Parent = game:GetService("SoundService")
			sfx:Play()
			game.Debris:AddItem(sfx, 3)
			return
		end
	end
end

local lastErrorTime = tick()

local function PlayErrorFeedback(targetButton)
	if tick() - lastErrorTime < 0.25 then return end
	lastErrorTime = tick()

	local sfxFolder = ReplicatedStorage:FindFirstChild("Sounds") or ReplicatedStorage:FindFirstChild("SFX")
	if sfxFolder and sfxFolder:FindFirstChild("ErrorBuzz") then
		local sfx = sfxFolder.ErrorBuzz:Clone()
		sfx.Volume = 0.5
		sfx.Parent = workspace
		sfx:Play()
		game.Debris:AddItem(sfx, 2)
	end

	if targetButton and targetButton.Parent then
		local origPos    = targetButton.Position
		local wobbleInfo = TweenInfo.new(0.04, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 3, true)
		TweenService:Create(targetButton, wobbleInfo, {
			Position = origPos + UDim2.new(0, 4, 0, 0)
		}):Play()
	end
end

local function FormatNumber(n) return Formatter.Format(n) end
local function PlayUI(id) if shared.PlayUISound then shared.PlayUISound(id) end end

-- ─────────────────────────────────────────────────────────────────────────────
-- SHOP BUTTON
-- ─────────────────────────────────────────────────────────────────────────────
local ShopButton = Instance.new("ImageButton")
ShopButton.Name              = "ShopButton"
ShopButton.Size              = UDim2.new(0, 60, 0, 60)
ShopButton.AnchorPoint       = Vector2.new(1, 1)
ShopButton.Position          = UDim2.new(0.98, 0, 0.95, 0)
ShopButton.BackgroundColor3  = T.buttonSecondary
ShopButton.BorderSizePixel   = 0
ShopButton.AutoButtonColor   = false
ShopButton.ZIndex            = 5
ShopButton.Parent            = mainHUD
CollectionService:AddTag(ShopButton, "Tutorial_ShopButton") -- Tutorial Tracker Tag
Instance.new("UICorner", ShopButton).CornerRadius = UDim.new(0.5, 0)

local shopStroke = Instance.new("UIStroke", ShopButton)
shopStroke.Color     = T.accentGold
shopStroke.Thickness = 2

local shopIcon = Instance.new("ImageLabel", ShopButton)
shopIcon.Size               = UDim2.new(0.6, 0, 0.6, 0)
shopIcon.Position           = UDim2.new(0.2, 0, 0.2, 0)
shopIcon.BackgroundTransparency = 1
shopIcon.ScaleType          = Enum.ScaleType.Fit
shopIcon.Image              = "rbxassetid://14916846070"

-- ─────────────────────────────────────────────────────────────────────────────
-- SHOP PANEL
-- ─────────────────────────────────────────────────────────────────────────────
local PANEL_MAX_W = 420; local PANEL_MAX_H = 510; local HEADER_H = 42

local ShopPanel = Instance.new("Frame")
ShopPanel.Name              = "ShopPanel"
ShopPanel.Size              = UDim2.new(0.88, 0, 0.82, 0)
ShopPanel.AnchorPoint       = Vector2.new(0.5, 0.5)
ShopPanel.Position          = UDim2.new(0.5, 0, 0.5, 0)
ShopPanel.BackgroundColor3  = T.panelBG
ShopPanel.BorderSizePixel   = 0
ShopPanel.Visible           = false
ShopPanel.ZIndex            = 10
ShopPanel.ClipsDescendants  = true
ShopPanel.Parent            = mainHUD
CollectionService:AddTag(ShopPanel, "Tutorial_ShopPanel") -- Tutorial Tracker Tag
Instance.new("UICorner", ShopPanel).CornerRadius = UDim.new(0, 10)

local sizeConstraint = Instance.new("UISizeConstraint")
sizeConstraint.MaxSize = Vector2.new(PANEL_MAX_W, PANEL_MAX_H)
sizeConstraint.Parent  = ShopPanel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color     = T.panelStroke
panelStroke.Thickness = 2
panelStroke.Parent    = ShopPanel

local TitleBar = Instance.new("Frame")
TitleBar.Name                 = "TitleBar"
TitleBar.Size                 = UDim2.new(1, 0, 0, HEADER_H)
TitleBar.BackgroundColor3     = T.headerBG
TitleBar.BorderSizePixel      = 0
TitleBar.ZIndex               = 11
TitleBar.ClipsDescendants     = true
TitleBar.BackgroundTransparency = 1
TitleBar.Parent               = ShopPanel
Instance.new("UICorner", TitleBar).CornerRadius = UDim.new(0, 10)

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size               = UDim2.new(1, -50, 1, 0)
TitleLabel.Position           = UDim2.new(0, 15, 0, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Text               = "RESEARCH"
TitleLabel.TextColor3         = T.headerText
TitleLabel.TextScaled         = true
TitleLabel.Font               = T.font
TitleLabel.TextXAlignment     = Enum.TextXAlignment.Left
TitleLabel.ZIndex             = 12
TitleLabel.Parent             = TitleBar

local CloseButton = Instance.new("TextButton")
CloseButton.Size             = UDim2.new(0, 30, 0, 30)
CloseButton.Position         = UDim2.new(1, -35, 0, 6)
CloseButton.BackgroundColor3 = T.buttonRed
CloseButton.BorderSizePixel  = 0
CloseButton.Text             = "X"
CloseButton.TextColor3       = T.bodyText
CloseButton.TextScaled       = true
CloseButton.Font             = T.font
CloseButton.ZIndex           = 9999
CloseButton.Parent           = TitleBar
CollectionService:AddTag(CloseButton, "Tutorial_ShopCloseBtn") -- Tutorial Tracker Tag
Instance.new("UICorner", CloseButton).CornerRadius = UDim.new(0, 6)

-- ─────────────────────────────────────────────────────────────────────────────
-- INFO POPUP
-- ─────────────────────────────────────────────────────────────────────────────
local InfoPopup = Instance.new("Frame")
InfoPopup.Name                 = "InfoPopup"
InfoPopup.Size                 = UDim2.new(0.85, 0, 0.6, 0)
InfoPopup.Position             = UDim2.new(0.5, 0, 0.5, 0)
InfoPopup.AnchorPoint          = Vector2.new(0.5, 0.5)
InfoPopup.BackgroundColor3     = T.cardBG
InfoPopup.BackgroundTransparency = 0
InfoPopup.ZIndex               = 50
InfoPopup.Visible              = false
InfoPopup.Parent               = ShopPanel
Instance.new("UICorner", InfoPopup).CornerRadius = UDim.new(0, 12)

local AspectConstraint = Instance.new("UIAspectRatioConstraint", InfoPopup)
AspectConstraint.AspectRatio = 1.0
local InfoScale = Instance.new("UIScale", InfoPopup)
InfoScale.Scale = 1

local InfoTitle = Instance.new("TextLabel", InfoPopup)
InfoTitle.Size                 = UDim2.new(1, -20, 0, 35)
InfoTitle.Position             = UDim2.new(0, 10, 0, 10)
InfoTitle.BackgroundTransparency = 1
InfoTitle.Text                 = ""
InfoTitle.TextColor3           = T.headerText
InfoTitle.TextScaled           = true
InfoTitle.Font                 = Enum.Font.GothamBold
InfoTitle.ZIndex               = 51

local InfoDesc = Instance.new("TextLabel", InfoPopup)
InfoDesc.Size                  = UDim2.new(1, -20, 1, -110)
InfoDesc.Position              = UDim2.new(0, 10, 0, 55)
InfoDesc.BackgroundTransparency = 1
InfoDesc.Text                  = ""
InfoDesc.TextColor3            = T.bodyText
InfoDesc.TextWrapped           = true
InfoDesc.TextScaled            = true
InfoDesc.Font                  = T.font
InfoDesc.TextYAlignment        = Enum.TextYAlignment.Top
InfoDesc.ZIndex                = 51

local InfoClose = Instance.new("TextButton", InfoPopup)
InfoClose.Size             = UDim2.new(0.6, 0, 0, 40)
InfoClose.Position         = UDim2.new(0.2, 0, 1, -50)
InfoClose.BackgroundColor3 = T.buttonPrimary
InfoClose.BorderSizePixel  = 0
InfoClose.Text             = "Close"
InfoClose.TextColor3       = T.headerText
InfoClose.TextScaled       = true
InfoClose.Font             = T.font
InfoClose.ZIndex           = 51
Instance.new("UICorner", InfoClose).CornerRadius = UDim.new(0, 8)

local function ShowInfo(title, desc)
	if shared.PlayUISound then shared.PlayUISound(SoundConfig.UIClick or "") end
	InfoTitle.Text = title
	InfoDesc.Text  = desc
	InfoPopup.BackgroundTransparency = 0
	InfoScale.Scale  = 0.5
	InfoPopup.Visible = true
	TweenService:Create(InfoScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

InfoClose.MouseButton1Down:Connect(function()
	if shared.PlayUISound then shared.PlayUISound(SoundConfig.UIClick or "") end
	local tween = TweenService:Create(InfoScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0.5 })
	tween:Play()
	tween.Completed:Once(function() InfoPopup.Visible = false end)
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- MAIN TAB BAR
-- ─────────────────────────────────────────────────────────────────────────────
local activeShopTabText = "Regular Upgrades"

local MainTabBar = Instance.new("Frame")
MainTabBar.Size                 = UDim2.new(1, -20, 0, 85)
MainTabBar.Position             = UDim2.new(0, 10, 0, HEADER_H + 4)
MainTabBar.BackgroundTransparency = 1
MainTabBar.ZIndex               = 11
MainTabBar.Parent               = ShopPanel

local ShopHoverLabel = Instance.new("TextLabel", MainTabBar)
ShopHoverLabel.Size                 = UDim2.new(1, 0, 0, 20)
ShopHoverLabel.Position             = UDim2.new(0, 0, 0, 0)
ShopHoverLabel.BackgroundTransparency = 1
ShopHoverLabel.TextColor3           = T.bodyText
ShopHoverLabel.TextScaled           = true
ShopHoverLabel.Font                 = T.font
ShopHoverLabel.Text                 = activeShopTabText

local TabBtnFrame = Instance.new("Frame", MainTabBar)
TabBtnFrame.Size                 = UDim2.new(1, 0, 1, -25)
TabBtnFrame.Position             = UDim2.new(0, 0, 0, 25)
TabBtnFrame.BackgroundTransparency = 1

local TabListLayout = Instance.new("UIListLayout", TabBtnFrame)
TabListLayout.FillDirection       = Enum.FillDirection.Horizontal
TabListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
TabListLayout.VerticalAlignment   = Enum.VerticalAlignment.Center
TabListLayout.Padding             = UDim.new(0, 25)

local TAB_COLOR_BASE   = T.buttonSecondary
local TAB_COLOR_HOVER  = T.buttonPrimary
local TAB_COLOR_ACTIVE = T.accentGold

local mainTabButtons = {}

local function MakeMainTab(name, hoverText, iconId)
	local btn = Instance.new("ImageButton", TabBtnFrame)
	btn.Name             = "MainTab_" .. name
	btn.Size             = UDim2.new(0, 48, 0, 48)
	btn.BackgroundColor3 = TAB_COLOR_BASE
	btn.AutoButtonColor  = false
	btn.ZIndex           = 12
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0.5, 0)

	local stroke = Instance.new("UIStroke", btn)
	stroke.Color     = T.panelStroke
	stroke.Thickness = 2

	local icon = Instance.new("ImageLabel", btn)
	icon.Size               = UDim2.new(0.6, 0, 0.6, 0)
	icon.Position           = UDim2.new(0.2, 0, 0.2, 0)
	icon.BackgroundTransparency = 1
	icon.ScaleType          = Enum.ScaleType.Fit
	icon.Image              = iconId

	btn.MouseEnter:Connect(function()
		ShopHoverLabel.Text = hoverText
		if activeMainTab ~= name then btn.BackgroundColor3 = TAB_COLOR_HOVER end
	end)
	btn.MouseLeave:Connect(function()
		ShopHoverLabel.Text = activeShopTabText
		if activeMainTab ~= name then btn.BackgroundColor3 = TAB_COLOR_BASE end
	end)

	mainTabButtons[name] = { btn = btn, stroke = stroke }
	return btn
end

local tabEpic     = MakeMainTab("Epic",     "Epic Research",     "rbxassetid://14916846070")
local tabUpgrades = MakeMainTab("Upgrades", "Regular Upgrades",  "rbxassetid://14916846070")

-- ─────────────────────────────────────────────────────────────────────────────
-- CURRENCY LABEL
-- ─────────────────────────────────────────────────────────────────────────────
local CURRENCY_H = 0
local CurrencyLabel = Instance.new("TextLabel")
CurrencyLabel.Name              = "ShopCurrencyLabel"
CurrencyLabel.Size              = UDim2.new(1, -24, 0, CURRENCY_H)
CurrencyLabel.BackgroundTransparency = 1
CurrencyLabel.Text              = "$0"
CurrencyLabel.TextColor3        = T.currencyColor
CurrencyLabel.TextScaled        = true
CurrencyLabel.Font              = T.font
CurrencyLabel.TextXAlignment    = Enum.TextXAlignment.Right
CurrencyLabel.ZIndex            = 11
CurrencyLabel.Parent            = ShopPanel

-- ─────────────────────────────────────────────────────────────────────────────
-- SCROLL FRAMES
-- ─────────────────────────────────────────────────────────────────────────────
local function MakeScroll(name, yTop)
	local sf = Instance.new("ScrollingFrame")
	sf.Name                 = name
	sf.Size                 = UDim2.new(1, -20, 1, -(yTop + 10))
	sf.Position             = UDim2.new(0, 10, 0, yTop)
	sf.BackgroundTransparency = 1
	sf.BorderSizePixel      = 0
	sf.ScrollBarThickness   = 4
	sf.ScrollBarImageColor3 = T.subText
	sf.CanvasSize           = UDim2.new(0, 0, 0, 0)
	sf.ZIndex               = 11
	sf.Visible              = false
	sf.ClipsDescendants     = true
	sf.Parent               = ShopPanel

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.Parent  = sf
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		sf.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 10)
	end)
	return sf
end

local REGULAR_SCROLL_TOP = HEADER_H + 95
local RegularScroll      = MakeScroll("RegularScroll", REGULAR_SCROLL_TOP)
local EPIC_SCROLL_TOP    = HEADER_H + 95
local EpicScroll         = MakeScroll("EpicScroll", EPIC_SCROLL_TOP)

-- ─────────────────────────────────────────────────────────────────────────────
-- CARD BUILDER
-- ─────────────────────────────────────────────────────────────────────────────
local function BuildCard(parent, upgradeId, cfg, isEpic, cardRefsTable)
	local card = Instance.new("Frame")
	card.Name             = "Card_" .. upgradeId
	card.Size             = UDim2.new(1, 0, 0, 100)
	card.BackgroundColor3 = T.cardBG
	card.BorderSizePixel  = 0
	card.Parent           = parent
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)

	local icon = Instance.new("ImageLabel", card)
	icon.Size               = UDim2.new(0, 50, 0, 50)
	icon.Position           = UDim2.new(0, 15, 0.5, -25)
	icon.BackgroundTransparency = 1
	icon.Image              = cfg.iconId or "rbxassetid://0"

	local infoBtn = Instance.new("TextButton", card)
	infoBtn.Size             = UDim2.new(0, 22, 0, 22)
	infoBtn.Position         = UDim2.new(0, 75, 0, 12)
	infoBtn.BackgroundColor3 = T.buttonSecondary
	infoBtn.Text             = "i"
	infoBtn.TextColor3       = T.bodyText
	infoBtn.Font             = Enum.Font.GothamBlack
	infoBtn.TextSize         = 14
	Instance.new("UICorner", infoBtn).CornerRadius = UDim.new(1, 0)
	infoBtn.MouseButton1Click:Connect(function() ShowInfo(cfg.displayName, cfg.description) end)

	local nameLabel = Instance.new("TextLabel", card)
	nameLabel.Size              = UDim2.new(0.74, -120, 0, 24)
	nameLabel.Position          = UDim2.new(0, 102, 0, 11)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text              = string.upper(cfg.displayName)
	nameLabel.TextColor3        = T.bodyText
	nameLabel.TextScaled        = true
	nameLabel.Font              = Enum.Font.FredokaOne
	nameLabel.TextXAlignment    = Enum.TextXAlignment.Left

	local descLabel = Instance.new("TextLabel", card)
	descLabel.Size              = UDim2.new(0.74, -95, 0, 36)
	descLabel.Position          = UDim2.new(0, 75, 0, 38)
	descLabel.BackgroundTransparency = 1
	descLabel.Text              = cfg.description
	descLabel.TextColor3        = T.subText
	descLabel.TextWrapped       = true
	descLabel.TextSize          = 16
	descLabel.Font              = Enum.Font.GothamMedium
	descLabel.TextXAlignment    = Enum.TextXAlignment.Left
	descLabel.TextYAlignment    = Enum.TextYAlignment.Top

	local levelLabel = Instance.new("TextLabel", card)
	levelLabel.Size             = UDim2.new(0.74, -95, 0, 18)
	levelLabel.Position         = UDim2.new(0, 75, 0, 76)
	levelLabel.BackgroundTransparency = 1
	levelLabel.Text             = "Lv. 0 / " .. cfg.maxLevel
	levelLabel.TextColor3       = T.accentGreen
	levelLabel.TextSize         = 16
	levelLabel.Font             = Enum.Font.FredokaOne
	levelLabel.TextXAlignment   = Enum.TextXAlignment.Left

	local buyButton = Instance.new("TextButton", card)
	buyButton.Name             = "PurchaseButton"
	buyButton.Size             = UDim2.new(0.24, 0, 0, 46)
	buyButton.AnchorPoint      = Vector2.new(1, 0.5)
	buyButton.Position         = UDim2.new(1, -12, 0.5, 0)
	buyButton.BackgroundColor3 = isEpic and T.accentPurple or T.buttonGreen
	buyButton.BorderSizePixel  = 0
	buyButton.TextColor3       = T.bodyText
	buyButton.TextScaled       = true
	buyButton.Font             = Enum.Font.FredokaOne
	CollectionService:AddTag(buyButton, "Tutorial_Buy_" .. upgradeId) -- Tutorial Tracker Tag
	Instance.new("UICorner", buyButton).CornerRadius = UDim.new(0, 8)

	cardRefsTable[upgradeId] = {
		frame      = card,
		levelLabel = levelLabel,
		buyButton  = buyButton,
		isEpic     = isEpic,
		tab        = cfg.category,
	}

	local holdingBuy    = false
	local buyGeneration = 0

	local function StopAllOtherHolds(myGen)
		if globalHoldGeneration ~= myGen then
			globalHoldGeneration = myGen
		end
	end

	local function TryBuy()
		if isLoadingData then return false end

		-- ✨ TUTORIAL ADAPTATION: Prevent accidental multi-buys if the FSM advances while holding!
		if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_BuyUpgrade") then return false end

		if isEpic then
			local state = epicUpgradeState[upgradeId]
			if not state or state.maxed then return false end

			local currentAuras = player:GetAttribute("LiveGoldenAuras") or 0
			local currentAuraSpend = player:GetAttribute("LocalAuraSpend") or 0
			local actualAuras = currentAuras - currentAuraSpend

			if actualAuras < state.cost then PlayErrorFeedback(buyButton); return false end

			local wasMaxedLocally = state.maxed
			player:SetAttribute("LocalAuraSpend", currentAuraSpend + state.cost)

			state.level += 1
			state.maxed  = (state.level >= state.maxLevel)
			state.cost   = state.maxed and 0 or EpicUpgradeConfig.CalculateCost(upgradeId, state.level)

			if state.maxed and not wasMaxedLocally then
				PlayFeedbackSound("MaxOut", 0.6); PlayUIBurst(buyButton, 20)
			else
				PlayPurchaseSound()
			end
			UpdateEpicCard(upgradeId)
			PurchaseEpicUpgrade:FireServer(upgradeId)

			if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
			return true
		else
			local state = upgradeState[upgradeId]
			if not state or state.maxed then return false end

			local currentCash = player:GetAttribute("LiveCurrency") or 0
			local currentSpend = player:GetAttribute("LocalSpend") or 0
			local actualCash = currentCash - currentSpend

			if actualCash < state.cost then PlayErrorFeedback(buyButton); return false end

			local wasMaxedLocally = state.maxed
			player:SetAttribute("LocalSpend", currentSpend + state.cost)

			state.level += 1
			state.maxed  = (state.level >= state.maxLevel)
			state.cost   = state.maxed and 0 or UpgradeConfig.CalculateCost(upgradeId, state.level)

			if state.maxed and not wasMaxedLocally then
				PlayFeedbackSound("MaxOut", 0.6); PlayUIBurst(buyButton, 20)
			else
				PlayPurchaseSound()
			end
			UpdateRegularCard(upgradeId)
			UpdateLockedTierProgress()
			PurchaseUpgrade:FireServer(upgradeId)

			if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
			return true
		end
	end

	local pulseTween = nil

	buyButton.MouseButton1Down:Connect(function()
		-- LOGIC GATING: Ask TutorialController for permission
		if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_BuyUpgrade") then return end

		globalHoldGeneration += 1
		local myGlobalGen = globalHoldGeneration

		buyGeneration += 1
		local myGen   = buyGeneration
		holdingBuy    = true
		globalHoldActive = true

		local scale = buyButton:FindFirstChildOfClass("UIScale")
		if not scale then
			scale = Instance.new("UIScale")
			scale.Parent = buyButton
		end

		pulseTween = TweenService:Create(scale,
			TweenInfo.new(0.12, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Scale = 0.88 })
		pulseTween:Play()

		TryBuy()
		task.wait(0.3)
		local holdStart = tick()

		local UserInputService = game:GetService("UserInputService")
		local epicHoldSpeedLevel   = (epicUpgradeState["epicHoldSpeed"] and epicUpgradeState["epicHoldSpeed"].level) or 0
		local holdSpeedMultiplier  = 1 + (epicHoldSpeedLevel * 0.3)

		while holdingBuy and buyGeneration == myGen and globalHoldGeneration == myGlobalGen do
			if not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
				holdingBuy = false; globalHoldActive = false; break
			end
			local success = TryBuy()
			if not success then holdingBuy = false; globalHoldActive = false; break end
			task.wait(math.max(0.02, (0.15 - ((tick() - holdStart) * 0.05)) / holdSpeedMultiplier))
		end

		globalHoldActive = false
		if pulseTween then pulseTween:Cancel() end
		if scale then
			TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), { Scale = 1 }):Play()
		end
	end)

	local function StopHold()
		holdingBuy = false
		globalHoldActive = false
		if pulseTween then pulseTween:Cancel() end
		local scale = buyButton:FindFirstChildOfClass("UIScale")
		if scale then
			TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), { Scale = 1 }):Play()
		end
	end

	buyButton.MouseButton1Up:Connect(StopHold)
	buyButton.MouseLeave:Connect(StopHold)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- BUILD EPIC CARDS
-- ─────────────────────────────────────────────────────────────────────────────
local epicOrderIndex = 1
for _, tierData in ipairs(EpicUpgradeConfig.Tiers) do
	for upgradeId, cfg in pairs(tierData.upgrades) do
		BuildCard(EpicScroll, upgradeId, cfg, true, epicCardRefs)

		local ref = epicCardRefs[upgradeId]
		if ref and ref.frame then
			ref.baseOrder      = epicOrderIndex
			ref.frame.LayoutOrder = epicOrderIndex
			epicOrderIndex    += 1
			ref.frame.Visible  = false
			ref.frame.Parent   = EpicScroll
			if UITheme and UITheme.Apply then UITheme.Apply(ref.frame, "ShopCard") end
		end
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- CARD UPDATE FUNCTIONS
-- ─────────────────────────────────────────────────────────────────────────────
function UpdateRegularCard(upgradeId)
	local ref   = regularCardRefs[upgradeId]
	local state = upgradeState[upgradeId]
	if not ref or not state then return end
	if UITheme and UITheme.Apply then UITheme.Apply(ref.frame, "ShopCard") end

	ref.levelLabel.Text = "Lv. " .. state.level .. " / " .. state.maxLevel

	local currentCash   = player:GetAttribute("LiveCurrency") or 0
	local currentSpend  = player:GetAttribute("LocalSpend") or 0
	local actualCash    = currentCash - currentSpend

	if state.level >= state.maxLevel then
		ref.frame.LayoutOrder        = (ref.baseOrder or 0) + 100000
		ref.levelLabel.TextColor3    = Color3.fromRGB(255, 215, 0)
		ref.buyButton.Text           = "MAX"
		ref.buyButton.TextColor3     = Color3.fromRGB(255, 255, 255)
		ref.buyButton.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
	else
		ref.frame.LayoutOrder      = ref.baseOrder or 0
		ref.buyButton.Text         = "$" .. FormatNumber(state.cost)
		ref.buyButton.TextColor3   = (actualCash < state.cost)
			and Color3.fromRGB(255, 100, 100) or Color3.fromRGB(255, 255, 255)
		ref.buyButton.BackgroundColor3 = Color3.fromRGB(60, 170, 80)
	end
end

function UpdateEpicCard(upgradeId)
	local ref   = epicCardRefs[upgradeId]
	local state = epicUpgradeState[upgradeId]
	if not ref or not state then return end
	if UITheme and UITheme.Apply then UITheme.Apply(ref.frame, "ShopCard") end

	ref.levelLabel.Text = "Lv. " .. state.level .. " / " .. state.maxLevel

	local currentAuras  = player:GetAttribute("LiveGoldenAuras") or 0
	local currentAuraSpend = player:GetAttribute("LocalAuraSpend") or 0
	local actualAuras   = currentAuras - currentAuraSpend

	if state.level >= state.maxLevel then
		ref.frame.LayoutOrder        = (ref.baseOrder or 0) + 100000
		ref.levelLabel.TextColor3    = Color3.fromRGB(255, 215, 0)
		ref.buyButton.Text           = "MAX"
		ref.buyButton.TextColor3     = Color3.fromRGB(255, 255, 255)
		ref.buyButton.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
	else
		ref.frame.LayoutOrder      = ref.baseOrder or 0
		ref.buyButton.Text         = "✦ " .. FormatNumber(state.cost)
		ref.buyButton.TextColor3   = (actualAuras < state.cost)
			and Color3.fromRGB(255, 100, 100) or Color3.fromRGB(255, 255, 255)
		ref.buyButton.BackgroundColor3 = Color3.fromRGB(150, 80, 255)
	end
end

function UpdateCurrencyDisplay()
	if activeMainTab == "Upgrades" then
		local currentCash = player:GetAttribute("LiveCurrency") or 0
		local currentSpend = player:GetAttribute("LocalSpend") or 0
		local actualCash = currentCash - currentSpend

		CurrencyLabel.Text       = "$" .. FormatNumber(actualCash)
		CurrencyLabel.TextColor3 = T.currencyColor
		CurrencyLabel.Position   = UDim2.new(0, 12, 0, HEADER_H + 34 + 8)
	end
end

local function UpdateAllRegularCards() for id in pairs(regularCardRefs) do UpdateRegularCard(id) end end
local function UpdateAllEpicCards()   for id in pairs(epicCardRefs)    do UpdateEpicCard(id)    end end

UpdateLockedTierProgress = function()
	local totalUpgradesBought = 0
	for _, state in pairs(upgradeState) do
		totalUpgradesBought = totalUpgradesBought + (state.level or 0)
	end

	local lockedHeader = nil
	local required = 0

	for _, child in ipairs(RegularScroll:GetChildren()) do
		if child.Name == "TierHeader_Locked" then
			lockedHeader = child
			required = child:GetAttribute("Required") or 0
			local progressLabel = child:FindFirstChild("ProgressLabel")
			if progressLabel then
				progressLabel.Text = totalUpgradesBought .. " / " .. required .. " Upgrades Needed"
				local progress = totalUpgradesBought / required
				if progress >= 1 then
					progressLabel.TextColor3 = Color3.fromRGB(100, 255, 100) 
				elseif progress >= 0.75 then
					progressLabel.TextColor3 = Color3.fromRGB(255, 200, 100) 
				else
					progressLabel.TextColor3 = Color3.fromRGB(255, 100, 100) 
				end
			end
			break
		end
	end

	if lockedHeader and totalUpgradesBought >= required then
		PlayFeedbackSound("MaxOut", 0.8)
		PlayUIBurst(ShopPanel, 30, Color3.fromRGB(100, 255, 100))
		local scroll = ShopPanel:FindFirstChild("RegularScroll")
		local savedScroll = scroll and scroll.CanvasPosition or Vector2.new(0, 0)
		RebuildRegularShop()
		if scroll then scroll.CanvasPosition = savedScroll end
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- TIER HEADERS
-- ─────────────────────────────────────────────────────────────────────────────
local function CreateTierHeader(tierName)
	local header = Instance.new("Frame")
	header.Name                 = "TierHeader"
	header.Size                 = UDim2.new(1, 0, 0, 30)
	header.BackgroundTransparency = 1

	local label = Instance.new("TextLabel")
	label.Size                  = UDim2.new(1, 0, 1, -5)
	label.BackgroundTransparency = 1
	label.Text                  = string.upper(tierName)
	label.TextColor3            = Color3.fromRGB(220, 220, 220)
	label.TextSize              = 16
	label.Font                  = Enum.Font.GothamBlack
	label.TextXAlignment        = Enum.TextXAlignment.Left
	label.Parent                = header

	local line = Instance.new("Frame")
	line.Size             = UDim2.new(1, 0, 0, 2)
	line.Position         = UDim2.new(0, 0, 1, -2)
	line.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
	line.BorderSizePixel  = 0
	line.Parent           = header
	return header
end

local function CreateLockedTierHeader(tierName, current, required)
	local header = Instance.new("Frame")
	header.Name                 = "TierHeader_Locked"
	header.Size                 = UDim2.new(1, 0, 0, 45)
	header.BackgroundTransparency = 1
	header:SetAttribute("Required", required)

	local label = Instance.new("TextLabel")
	label.Size                  = UDim2.new(1, 0, 0.5, 0)
	label.BackgroundTransparency = 1
	label.Text                  = string.upper(tierName) .. " (LOCKED)"
	label.TextColor3            = Color3.fromRGB(150, 150, 150)
	label.TextSize              = 16
	label.Font                  = Enum.Font.GothamBlack
	label.TextXAlignment        = Enum.TextXAlignment.Left
	label.Parent                = header

	local progress = Instance.new("TextLabel")
	progress.Name               = "ProgressLabel"
	progress.Size               = UDim2.new(1, 0, 0.4, 0)
	progress.Position           = UDim2.new(0, 0, 0.6, 0)
	progress.BackgroundTransparency = 1
	progress.Text               = current .. " / " .. required .. " Upgrades Needed"
	progress.TextColor3         = Color3.fromRGB(255, 100, 100)
	progress.TextSize           = 12
	progress.Font               = Enum.Font.GothamBold
	progress.TextXAlignment     = Enum.TextXAlignment.Left
	progress.Parent             = header

	local line = Instance.new("Frame")
	line.Size             = UDim2.new(1, 0, 0, 2)
	line.Position         = UDim2.new(0, 0, 1, -2)
	line.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
	line.BorderSizePixel  = 0
	line.Parent           = header
	return header
end

-- ─────────────────────────────────────────────────────────────────────────────
-- REBUILD REGULAR SHOP
-- ─────────────────────────────────────────────────────────────────────────────
RebuildRegularShop = function()
	for _, child in ipairs(RegularScroll:GetChildren()) do
		if child:IsA("Frame") and child.Name ~= "CardTemplate" then
			child:Destroy()
		end
	end
	regularCardRefs = {}

	local totalUpgradesBought = 0
	for _, state in pairs(upgradeState) do
		totalUpgradesBought = totalUpgradesBought + (state.level or 0)
	end

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
					if ref.buyButton then
						ref.buyButton.Name = "Buy_" .. upgradeId
					end
					ref.baseOrder          = listOrder
					ref.frame.LayoutOrder  = listOrder
					listOrder             += 1
					ref.frame.Visible      = true
					ref.frame.Parent       = RegularScroll
					if UITheme and UITheme.Apply then UITheme.Apply(ref.frame, "ShopCard") end
					local myColor = Color3.fromRGB(45, 30, 55)
					ref.frame:SetAttribute("TierColor", myColor)
					ref.frame.BackgroundColor3 = myColor
				end
			end
		else
			local lockedHeader = CreateLockedTierHeader(
				tierData.tierName or "Tier " .. tierNum,
				totalUpgradesBought,
				tierData.unlockRequirement
			)
			lockedHeader.LayoutOrder = listOrder
			lockedHeader.Parent      = RegularScroll
			break
		end
	end
	UpdateAllRegularCards()
end

RebuildRegularShop()

task.delay(5, function() isLoadingData = false end)

-- ─────────────────────────────────────────────────────────────────────────────
-- TAB SWITCHING
-- ─────────────────────────────────────────────────────────────────────────────
local function SwitchToMainTab(tabName)
	if shared.PlayUISound then shared.PlayUISound(SoundConfig.UIClick or "") end
	activeMainTab     = tabName
	activeShopTabText = (tabName == "Epic") and "Epic Research" or "Regular Upgrades"
	ShopHoverLabel.Text = activeShopTabText

	for name, data in pairs(mainTabButtons) do
		data.btn.BackgroundColor3 = (name == tabName) and TAB_COLOR_ACTIVE or TAB_COLOR_BASE
		data.stroke.Color         = (name == tabName) and T.bodyText or T.panelStroke
	end

	RegularScroll.Visible = (tabName == "Upgrades")
	EpicScroll.Visible    = (tabName == "Epic")

	if tabName == "Epic" then
		for _, ref in pairs(epicCardRefs) do
			if ref and ref.frame then ref.frame.Visible = true end
		end
		if EpicScroll then EpicScroll.CanvasPosition = Vector2.new(0, 0) end
	end
end

tabUpgrades.MouseButton1Down:Connect(function() PlayUI(SoundConfig.UIClick); SwitchToMainTab("Upgrades") end)
tabEpic.MouseButton1Down:Connect(function()     PlayUI(SoundConfig.UIClick); SwitchToMainTab("Epic")     end)

-- ─────────────────────────────────────────────────────────────────────────────
-- OPEN / CLOSE
-- ─────────────────────────────────────────────────────────────────────────────
local function OpenShop()
	shopOpen = true
	ShopPanel.Visible = true
	ShopPanel.Size    = UDim2.new(0.88, 0, 0, 0)
	SwitchToMainTab(activeMainTab)
	TweenService:Create(ShopPanel,
		TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.new(0.88, 0, 0.82, 0) }
	):Play()
	UITheme.SetMenuVisible(true)
	ShopButton.BackgroundColor3 = T.panelStroke
end

local function CloseShop()
	shopOpen = false
	PlayUI(SoundConfig.UIClose)
	TweenService:Create(ShopPanel,
		TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Size = UDim2.new(0.88, 0, 0, 0) }
	):Play()
	UITheme.SetMenuVisible(false)
	task.delay(0.25, function() ShopPanel.Visible = false end)
	ShopButton.BackgroundColor3 = T.buttonSecondary
end

ShopButton.MouseButton1Down:Connect(function()
	if shopOpen then
		-- LOGIC GATING
		if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_CloseShop") then return end
		CloseShop()
		if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
	else
		-- LOGIC GATING
		if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_OpenShop") then return end
		OpenShop()
		if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
	end
end)

CloseButton.MouseButton1Down:Connect(function()
	-- LOGIC GATING
	if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_CloseShop") then return end
	CloseShop()
	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- LIVE UPDATE LOOP
-- ─────────────────────────────────────────────────────────────────────────────
local lastCardUpdate = 0
RunService.Heartbeat:Connect(function()
	if not shopOpen then return end
	local now = tick()
	if now - lastCardUpdate > 0.1 then
		lastCardUpdate = now
		if activeMainTab == "Upgrades" then UpdateAllRegularCards() else UpdateAllEpicCards() end
		UpdateCurrencyDisplay()
	end
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- SERVER EVENTS
-- ─────────────────────────────────────────────────────────────────────────────
if UpgradeUpdated then
	UpgradeUpdated.OnClientEvent:Connect(function(info)
		if info.type == "fullState" then
			isLoadingData = false
			upgradeState   = info.upgrades
			currentCurrency = info.currency
			RebuildRegularShop()
			UpdateCurrencyDisplay()

		elseif info.type == "purchased" then
			player:SetAttribute("LastServerPurchaseTick", tick())
			player:SetAttribute("LocalSpend", 0)
			player:SetAttribute("ForceSyncCurrency", info.currency)

			local current = upgradeState[info.upgradeId]
			if not current or info.level >= current.level then
				upgradeState[info.upgradeId] = {
					level    = info.level,
					maxLevel = info.maxLevel,
					cost     = info.cost,
					maxed    = info.maxed,
				}
			end
			currentCurrency = info.currency

			-- ✨ FIX: Smoothly update the card instead of completely deleting and rebuilding the entire shop!
			UpdateRegularCard(info.upgradeId)
			UpdateLockedTierProgress()
			UpdateCurrencyDisplay()
		end
	end)
end

if EpicUpgradeUpdated then
	EpicUpgradeUpdated.OnClientEvent:Connect(function(info)
		if info.type == "fullState" then
			isLoadingData = false
			epicUpgradeState = info.upgrades
			liveGoldenAuras  = info.goldenAuras or liveGoldenAuras
			UpdateAllEpicCards()
			UpdateCurrencyDisplay()

		elseif info.type == "purchased" then
			player:SetAttribute("LastServerPurchaseTick", tick())
			player:SetAttribute("LocalAuraSpend", 0)

			local current = epicUpgradeState[info.upgradeId]
			if not current or info.level >= current.level then
				epicUpgradeState[info.upgradeId] = {
					level    = info.level,
					maxLevel = info.maxLevel,
					cost     = info.cost,
					maxed    = info.maxed,
				}
			end
			UpdateEpicCard(info.upgradeId)
			UpdateCurrencyDisplay()
		end
	end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- BUTTON JUICE
-- ─────────────────────────────────────────────────────────────────────────────
local function AddButtonJuice(btn)
	if not btn then return end
	local scale = btn:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = btn
	end

	btn.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Sine), { Scale = 1.08 }):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Sine), { Scale = 1 }):Play()
	end)
	btn.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1, Enum.EasingStyle.Sine), { Scale = 0.9 }):Play()
	end)
	btn.MouseButton1Up:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), { Scale = 1.08 }):Play()
	end)
end

AddButtonJuice(ShopButton)
AddButtonJuice(CloseButton)
AddButtonJuice(tabUpgrades)
AddButtonJuice(tabEpic)

-- ─────────────────────────────────────────────────────────────────────────────
-- REFRESH LOOK
-- ─────────────────────────────────────────────────────────────────────────────
local shopShine    = nil
local titleFlair   = nil
local flairedExtra = false

local function RefreshLook()
	UITheme.Apply(ShopPanel, "Panel")
	UITheme.Apply(ShopPanel, "TitleBar")

	if not shopShine then
		shopShine  = UITheme.ApplyShine(ShopPanel)
		UITheme.ApplyShine(TitleBar)
	end

	if not titleFlair then
		titleFlair = UITheme.ApplyFlair(TitleLabel, "Ghost")
	end

	if not flairedExtra then flairedExtra = true end

	for _, scrollName in ipairs({ "RegularScroll", "EpicScroll" }) do
		local scroll = ShopPanel:FindFirstChild(scrollName)
		if scroll then
			local layout = scroll:FindFirstChildOfClass("UIListLayout")
			if layout then layout.SortOrder = Enum.SortOrder.LayoutOrder end
		end
	end

	local outerStroke = ShopPanel:FindFirstChildWhichIsA("UIStroke")
	if outerStroke then outerStroke.Color = Color3.fromRGB(255, 255, 255) end
end

task.wait(2)
RefreshLook()

-- ✨ TUTORIAL OVERRIDE: Close shop when camera pans
local forceClose = ReplicatedStorage:FindFirstChild("ForceCloseUI") or Instance.new("BindableEvent")
forceClose.Name = "ForceCloseUI"
forceClose.Parent = ReplicatedStorage
forceClose.Event:Connect(function()
	if shopOpen then CloseShop() end
end)

-- AchievementController (Unified Master Menu)
-- Location: StarterPlayer > StarterPlayerScripts > AchievementController

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local UITheme           = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UITheme"))
local T                 = UITheme.Get("Custom")
local SoundConfig       = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SoundConfig"))
local AchievementConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("AchievementConfig"))
local TierConfig        = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("TierConfig"))
local AuraDiscovered    = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("AuraDiscovered", 5)
local Formatter         = require(ReplicatedStorage.Modules.NumberFormatter)

-- ✨ BRIDGENET2 UPGRADE
local BridgeNet2      = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))
local UpdateHUDBridge = BridgeNet2.ClientBridge("UpdateHUD")

local SettingsChanged = ReplicatedStorage:FindFirstChild("SettingsChanged")
if not SettingsChanged then
	SettingsChanged = Instance.new("BindableEvent")
	SettingsChanged.Name = "SettingsChanged"
	SettingsChanged.Parent = ReplicatedStorage
end

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainHUD   = playerGui:WaitForChild("MainHUD")
local Faded2    = mainHUD:WaitForChild("Faded2") 

local panelOpen = false
local activeTab = "Challenges"
local activeTabText = "Boosts" 
local latestStats = {}

-- Settings State
local sfxEnabled   = true
local musicEnabled = true
local jumpEnabled  = true 

local liveSoulAuras   = 0
local liveRunEarnings = 0
local liveRate        = 0
local livePrestiges   = 0

local toggleRefs    = {}
local statValueRefs = {}

local function PlayUI(id) if shared.PlayUISound then shared.PlayUISound(id) end end

local AreaAuraNames = {
	[1] = {"Gear", "Screw", "Tin Can", "Old Tire", "Intact Radio"},
	[2] = {"Rusted Nail", "Scrap Pipe", "Bent Gear", "Engine Scrap", "Corroded Core"},
	[3] = {"Foil Ball", "Candy Wrapper", "Aluminum Sheet", "Silver Leaf", "Mylar Balloon"},
	[4] = {"Tin Block", "Zinc Plate", "Lead Pipe", "Nickel Coin", "Pewter Idol"},
	[5] = {"Iron Ore", "Steel Beam", "Cast Iron Wheel", "Chrome Bumper", "Tungsten Rod"},
	[6] = {"Copper Wire", "Brass Gear", "Bronze Statue", "Titanium Plate", "Cobalt Shard"},
	[7] = {"Silver Bar", "Gold Nugget", "Platinum Ring", "Palladium Coin", "Rhodium Ingot"},
	[8] = {"PVC Pipe", "Kevlar Weave", "Teflon Block", "Carbon Fiber Roll", "Graphene Sheet"},
	[9] = {"Glowing Sludge", "Radium Dial", "Uranium Rod", "Plutonium Core", "Antimatter Vial"},
	[10] = {"Amethyst Cluster", "Raw Sapphire", "Uncut Ruby", "Emerald Chunk", "Opal Geode"},
	[11] = {"Polished Topaz", "Faceted Sapphire", "Cut Ruby", "Perfect Emerald", "Flawless Diamond"},
	[12] = {"Silicon Wafer", "Microchip", "RAM Stick", "Quantum Processor", "AI Core"},
	[13] = {"Neon Tube", "Plasma Arc", "Laser Diode", "Hard Light", "Photon Cell"},
	[14] = {"Quark", "Tachyon", "Boson", "Tesseract", "Schrodinger Cat"},
	[15] = {"Moon Rock", "Mars Dust", "Comet Ice", "Asteroid Core", "Solar Flare"},
	[16] = {"Stardust", "Pulsar Pulse", "Quasar Light", "Supernova Remnant", "Galaxy Spiral"},
	[17] = {"Shadow Matter", "Void Residue", "Event Horizon", "Singularity", "Hawking Radiation"},
	[18] = {"Paradox", "Timeline Thread", "Parallel Shard", "Alternate Reality", "Multiverse Core"},
	[19] = {"Static", "Kinetic", "Thermal", "Ethereal", "Infinite Energy"},
	[20] = {"Concept", "Truth", "Existence", "Reality", "Omnipotence"}
}

local AreaAuraIcons = {}
for i = 1, 20 do AreaAuraIcons[i] = {"rbxassetid://0", "rbxassetid://0", "rbxassetid://0", "rbxassetid://0", "rbxassetid://0"} end

---------------------------------------------------------------
-- 1. THE SINGLE MENU BUTTON (Gear with Sparkles)
---------------------------------------------------------------
local AchieveBtn = Instance.new("ImageButton", Faded2) 
AchieveBtn.Name = "AchievementButton"
AchieveBtn.Size = UDim2.new(0.85, 0, 0.85, 0)
AchieveBtn.Position = UDim2.new(0.5, 0, 0.5, 0) -- Centered perfectly in the frame!
AchieveBtn.AnchorPoint = Vector2.new(0.5, 0.5) 
AchieveBtn.BackgroundColor3 = T.buttonSecondary
AchieveBtn.BorderSizePixel = 0
AchieveBtn.AutoButtonColor = false
AchieveBtn.ZIndex = 15
Instance.new("UICorner", AchieveBtn).CornerRadius = UDim.new(0.5, 0)

local achieveAspect = Instance.new("UIAspectRatioConstraint", AchieveBtn)
achieveAspect.AspectRatio = 1.0 

local btnStroke = Instance.new("UIStroke", AchieveBtn)
btnStroke.Color = T.accentGold
btnStroke.Thickness = 1

local btnIcon = Instance.new("ImageLabel", AchieveBtn)
btnIcon.Size = UDim2.new(0.7, 0, 0.7, 0)
btnIcon.Position = UDim2.new(0.15, 0, 0.15, 0)
btnIcon.BackgroundTransparency = 1
btnIcon.ScaleType = Enum.ScaleType.Fit
btnIcon.Image = "rbxassetid://14923131909" -- Your Gear with Sparkles Icon!

-- Tutorial Hook
CollectionService:AddTag(AchieveBtn, "Tutorial_AchieveMenuBtn")

---------------------------------------------------------------
-- 2. THE MAIN PANEL & HEADER
---------------------------------------------------------------
local Panel = Instance.new("Frame", mainHUD)
Panel.Name = "AchievementPanel"; Panel.Size = UDim2.new(0.85, 0, 0.75, 0); Panel.Position = UDim2.new(0.5, 0, 0.5, 0); Panel.AnchorPoint = Vector2.new(0.5, 0.5)
Panel.BackgroundColor3 = T.panelBG; Panel.BorderSizePixel = 0; Panel.Visible = false; Panel.ZIndex = 40; Panel.ClipsDescendants = true
Instance.new("UICorner", Panel).CornerRadius = UDim.new(0, 12)
local sizeConstraint = Instance.new("UISizeConstraint", Panel); sizeConstraint.MaxSize = Vector2.new(500, 550) 
local panelStroke = Instance.new("UIStroke", Panel); panelStroke.Color = T.panelStroke; panelStroke.Thickness = 2

local Header = Instance.new("Frame", Panel)
Header.Size = UDim2.new(1, 0, 0, 44); Header.BackgroundColor3 = T.headerBG; Header.BorderSizePixel = 0; Header.ZIndex = 41
local TitleLabel = Instance.new("TextLabel", Header); TitleLabel.Size = UDim2.new(1, -50, 1, 0); TitleLabel.Position = UDim2.new(0, 14, 0, 0); TitleLabel.BackgroundTransparency = 1; TitleLabel.Text = "MENU"; TitleLabel.TextColor3 = T.headerText; TitleLabel.TextScaled = true; TitleLabel.Font = T.font; TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
local CloseBtn = Instance.new("TextButton", Header); CloseBtn.Size = UDim2.new(0, 28, 0, 28); CloseBtn.Position = UDim2.new(1, -36, 0.5, -14); CloseBtn.BackgroundColor3 = T.buttonRed; CloseBtn.Text = "X"; CloseBtn.TextColor3 = T.headerText; CloseBtn.TextScaled = true; CloseBtn.Font = T.font; Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 5); CloseBtn.ZIndex = 9999

---------------------------------------------------------------
-- 3. CIRCULAR TABS & HOVER LABEL
---------------------------------------------------------------
local TabContainer = Instance.new("Frame", Panel)
TabContainer.Size = UDim2.new(1, 0, 0, 75); TabContainer.Position = UDim2.new(0, 0, 0, 44); TabContainer.BackgroundTransparency = 1; TabContainer.ZIndex = 41

local HoverLabel = Instance.new("TextLabel", TabContainer)
HoverLabel.Size = UDim2.new(1, 0, 0, 20); HoverLabel.Position = UDim2.new(0, 0, 1, -15); HoverLabel.BackgroundTransparency = 1
HoverLabel.Text = "Boosts"; HoverLabel.TextColor3 = T.bodyText; HoverLabel.TextScaled = true; HoverLabel.Font = T.font

local TabButtonFrame = Instance.new("Frame", TabContainer)
TabButtonFrame.Size = UDim2.new(1, 0, 1, -20); TabButtonFrame.Position = UDim2.new(0, 0, 0, 0); TabButtonFrame.BackgroundTransparency = 1
local TabListLayout = Instance.new("UIListLayout", TabButtonFrame)
TabListLayout.FillDirection = Enum.FillDirection.Horizontal; TabListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center; TabListLayout.VerticalAlignment = Enum.VerticalAlignment.Center; TabListLayout.Padding = UDim.new(0, 12)

local tabBtns = {}; local scrolls = {}

local function MakeTab(name, hoverText, iconId)
	local btn = Instance.new("ImageButton", TabButtonFrame)
	btn.Size = UDim2.new(0, 45, 0, 45); btn.BackgroundColor3 = T.buttonSecondary; btn.AutoButtonColor = false
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0.5, 0)

	local tStroke = Instance.new("UIStroke", btn)
	tStroke.Color = T.panelStroke; tStroke.Thickness = 2

	local icon = Instance.new("ImageLabel", btn)
	icon.Size = UDim2.new(0.6, 0, 0.6, 0); icon.Position = UDim2.new(0.2, 0, 0.2, 0); icon.BackgroundTransparency = 1; icon.ScaleType = Enum.ScaleType.Fit; icon.Image = iconId
	tabBtns[name] = {btn = btn, stroke = tStroke}

	local sf = Instance.new("ScrollingFrame", Panel)
	sf.Size = UDim2.new(1, -20, 1, -135); sf.Position = UDim2.new(0, 10, 0, 125); sf.BackgroundTransparency = 1; sf.BorderSizePixel = 0; sf.ScrollBarThickness = 4; sf.Visible = false
	local layout = Instance.new("UIListLayout", sf); layout.Padding = UDim.new(0, 8); layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function() sf.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 10) end)
	scrolls[name] = sf

	btn.MouseEnter:Connect(function() HoverLabel.Text = hoverText end)
	btn.MouseLeave:Connect(function() HoverLabel.Text = activeTabText end)

	btn.MouseButton1Down:Connect(function()
		PlayUI(SoundConfig.UIClick or "")
		activeTab = name; activeTabText = hoverText; HoverLabel.Text = activeTabText
		for k, t in pairs(tabBtns) do 
			t.btn.BackgroundColor3 = (k == name) and T.accentGold or T.buttonSecondary 
			t.stroke.Color = (k == name) and T.bodyText or T.panelStroke
		end
		for k, s in pairs(scrolls) do s.Visible = (k == name) end
		TitleLabel.Text = (name == "Settings") and "SETTINGS" or "PROGRESSION"
	end)
end

MakeTab("Challenges", "Boosts", "rbxassetid://14916846070")
MakeTab("Index", "Auras", "rbxassetid://14916846070")
MakeTab("Badges", "Badges", "rbxassetid://14916846070")
MakeTab("Leaderboard", "Top 10", "rbxassetid://14916846070")
MakeTab("Settings", "Settings", "rbxassetid://14923131909") -- Settings Tab!

---------------------------------------------------------------
-- 4. BUILD SETTINGS TAB CONTENT
---------------------------------------------------------------
local setScroll = scrolls["Settings"]
local pad = Instance.new("UIPadding", setScroll); pad.PaddingTop = UDim.new(0, 5)

local function MakeToggleRow(labelText, settingKey)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -10, 0, 42); row.BackgroundColor3 = T.cardBG; row.BorderSizePixel = 0
	row.ZIndex = 41; row.Parent = setScroll
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)

	local lbl = Instance.new("TextLabel", row)
	lbl.Size = UDim2.new(0.6, 0, 1, 0); lbl.Position = UDim2.new(0, 15, 0, 0); lbl.BackgroundTransparency = 1
	lbl.Text = labelText; lbl.TextColor3 = T.subText; lbl.TextScaled = true; lbl.Font = T.fontBody; lbl.TextXAlignment = Enum.TextXAlignment.Left

	local toggle = Instance.new("TextButton", row)
	toggle.Size = UDim2.new(0, 60, 0, 30); toggle.Position = UDim2.new(1, -70, 0.5, -15); toggle.BorderSizePixel = 0
	toggle.TextScaled = true; toggle.Font = T.font; Instance.new("UICorner", toggle).CornerRadius = UDim.new(0, 6)

	local function Refresh(isOn)
		toggle.Text = isOn and "ON" or "OFF"
		toggle.TextColor3 = T.bodyText
		toggle.BackgroundColor3 = isOn and T.buttonGreen or T.buttonRed
	end

	local isOn = true
	if settingKey == "sfx" then isOn = sfxEnabled
	elseif settingKey == "music" then isOn = musicEnabled
	elseif settingKey == "jump" then isOn = jumpEnabled end

	Refresh(isOn)
	toggleRefs[settingKey] = Refresh

	toggle.MouseButton1Down:Connect(function()
		PlayUI(SoundConfig.UIClick or "")
		if settingKey == "sfx" then sfxEnabled = not sfxEnabled; isOn = sfxEnabled
		elseif settingKey == "music" then musicEnabled = not musicEnabled; isOn = musicEnabled
		elseif settingKey == "jump" then jumpEnabled = not jumpEnabled; isOn = jumpEnabled end
		Refresh(isOn)
		SettingsChanged:Fire(settingKey, isOn)
	end)
end

MakeToggleRow("Sound Effects", "sfx")
MakeToggleRow("Music", "music")
MakeToggleRow("Jumping", "jump") 

local div1 = Instance.new("Frame", setScroll); div1.Size = UDim2.new(1, -20, 0, 2); div1.BackgroundColor3 = T.panelStroke; div1.BorderSizePixel = 0
local statsTitle = Instance.new("TextLabel", setScroll); statsTitle.Size = UDim2.new(1, -20, 0, 20); statsTitle.BackgroundTransparency = 1; statsTitle.Text = "FARM STATS"; statsTitle.TextColor3 = T.subText; statsTitle.TextScaled = true; statsTitle.Font = T.font; statsTitle.TextXAlignment = Enum.TextXAlignment.Left

local function MakeStatRow(labelText, refKey)
	local row = Instance.new("Frame", setScroll); row.Size = UDim2.new(1, -20, 0, 26); row.BackgroundTransparency = 1
	local lbl = Instance.new("TextLabel", row); lbl.Size = UDim2.new(0.55, 0, 1, 0); lbl.BackgroundTransparency = 1; lbl.Text = labelText; lbl.TextColor3 = T.subText; lbl.TextScaled = true; lbl.Font = T.fontBody; lbl.TextXAlignment = Enum.TextXAlignment.Left
	local val = Instance.new("TextLabel", row); val.Size = UDim2.new(0.45, 0, 1, 0); val.Position = UDim2.new(0.55, 0, 0, 0); val.BackgroundTransparency = 1; val.Text = "0"; val.TextColor3 = T.accentBlue; val.TextScaled = true; val.Font = T.font; val.TextXAlignment = Enum.TextXAlignment.Right
	statValueRefs[refKey] = val
end

MakeStatRow("Soul Auras", "soul")
MakeStatRow("This Run", "run")
MakeStatRow("Rate", "rate")
MakeStatRow("Prestiges", "prestige")

local div2 = Instance.new("Frame", setScroll); div2.Size = UDim2.new(1, -20, 0, 2); div2.BackgroundColor3 = T.panelStroke; div2.BorderSizePixel = 0

local function Credit(text, color)
	local l = Instance.new("TextLabel", setScroll); l.Size = UDim2.new(1, -20, 0, 18); l.BackgroundTransparency = 1; l.Text = text; l.TextColor3 = color; l.TextScaled = true; l.Font = T.fontBody; l.TextXAlignment = Enum.TextXAlignment.Left
end
Credit("Aura Inc", Color3.fromRGB(85, 100, 135))
Credit("Made by MoldySugar2205", Color3.fromRGB(65, 80,  110))
Credit("Phase 4", Color3.fromRGB(50, 65,  90))

local function RefreshStats()
	if statValueRefs.soul     then statValueRefs.soul.Text     = Formatter.Format(liveSoulAuras) end
	if statValueRefs.run      then statValueRefs.run.Text      = "$" .. Formatter.Format(liveRunEarnings) end
	if statValueRefs.rate     then statValueRefs.rate.Text     = "$" .. Formatter.Format(liveRate) .. "/s" end
	if statValueRefs.prestige then statValueRefs.prestige.Text = Formatter.Format(livePrestiges) end
end

---------------------------------------------------------------
-- 5. BUILD ACHIEVEMENT CONTENT (Existing)
---------------------------------------------------------------
local function UpdateOrCreateRow(parent, id, title, titleColor, desc, hoverDesc, iconImage, iconColor, statusText, statusColor)
	local row = parent:FindFirstChild(id)
	if not row then
		row = Instance.new("TextButton", parent)
		row.Name = id; row.Text = ""; row.AutoButtonColor = false; row.Size = UDim2.new(1, -8, 0, 64); row.BackgroundColor3 = T.cardBG
		Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)
		local stroke = Instance.new("UIStroke", row); stroke.Name = "Stroke"; stroke.Thickness = 1
		local icon = Instance.new("ImageLabel", row); icon.Name = "Icon"; icon.Size = UDim2.new(0, 40, 0, 40); icon.Position = UDim2.new(0, 12, 0.5, -20); icon.ScaleType = Enum.ScaleType.Fit; Instance.new("UICorner", icon).CornerRadius = UDim.new(1, 0)
		local tLbl = Instance.new("TextLabel", row); tLbl.Name = "Title"; tLbl.Size = UDim2.new(0.6, 0, 0, 20); tLbl.Position = UDim2.new(0, 64, 0, 10); tLbl.BackgroundTransparency = 1; tLbl.TextColor3 = T.bodyText; tLbl.TextScaled = true; tLbl.Font = T.font; tLbl.TextXAlignment = Enum.TextXAlignment.Left
		local dLbl = Instance.new("TextLabel", row); dLbl.Name = "Desc"; dLbl.Size = UDim2.new(0.6, 0, 0, 16); dLbl.Position = UDim2.new(0, 64, 0, 32); dLbl.BackgroundTransparency = 1; tLbl.TextColor3 = T.subText; dLbl.TextScaled = true; dLbl.Font = T.fontBody; dLbl.TextXAlignment = Enum.TextXAlignment.Left
		local sLbl = Instance.new("TextLabel", row); sLbl.Name = "Status"; sLbl.Size = UDim2.new(0, 80, 0, 24); sLbl.Position = UDim2.new(1, -90, 0.5, -12); sLbl.BackgroundTransparency = 1; sLbl.TextScaled = true; sLbl.Font = T.font; sLbl.TextXAlignment = Enum.TextXAlignment.Right
		UITheme.Apply(row, "Card")
		row:SetAttribute("IsHovering", false)
		row.MouseEnter:Connect(function() row:SetAttribute("IsHovering", true); local hd = row:GetAttribute("HoverDesc"); if hd and hd ~= "" then row.Desc.Text = hd; row.Desc.TextColor3 = T.accentGold end end)
		row.MouseLeave:Connect(function() row:SetAttribute("IsHovering", false); row.Desc.Text = row:GetAttribute("NormalDesc") or ""; row.Desc.TextColor3 = T.subText end)
	end
	row:SetAttribute("NormalDesc", desc)
	row:SetAttribute("HoverDesc", hoverDesc)
	row.Title.Text = title; row.Title.TextColor3 = titleColor or T.bodyText 
	row.Status.Text = statusText; row.Status.TextColor3 = statusColor
	row.Icon.Image = iconImage; row.Icon.BackgroundColor3 = iconColor; row.Stroke.Color = iconColor
	if row:GetAttribute("IsHovering") and hoverDesc and hoverDesc ~= "" then row.Desc.Text = hoverDesc; row.Desc.TextColor3 = T.accentGold
	else row.Desc.Text = desc; row.Desc.TextColor3 = T.subText end
end

local function RefreshData()
	for i, chal in ipairs(AchievementConfig.Challenges) do
		local current = latestStats[chal.statKey] or 0
		local isDone = current >= chal.goal
		local statusText = isDone and "UNLOCKED" or (current .. " / " .. chal.goal)
		local statusColor = isDone and T.buttonGreen or T.subText
		local hoverReq = not isDone and ("Requires: " .. chal.desc) or "Boost Unlocked!"
		UpdateOrCreateRow(scrolls["Challenges"], "Chal_"..i, chal.title, T.bodyText, chal.rewardText, hoverReq, chal.iconId, T.accentBlue, statusText, statusColor)
	end

	local discoveredTiers = latestStats.discoveredTiers or {}
	local indexCount = 1
	for aIdx = 1, 20 do
		local areaNames = AreaAuraNames[aIdx]
		local areaIcons = AreaAuraIcons[aIdx]
		if not areaNames then continue end
		for tIdx = 1, 5 do
			local tier = TierConfig.Tiers[tIdx]
			if not tier then continue end
			local actualName = areaNames[tIdx]
			local auraTitle = actualName .. " Aura"
			local discovered = discoveredTiers[aIdx .. "_" .. tier.name] == true
			local statusText = discovered and "Found" or "???"
			local statusColor = discovered and T.buttonGreen or T.buttonRed
			local auraTitleColor = discovered and tier.color or Color3.fromRGB(100, 100, 100)
			local iconColor = discovered and tier.color or Color3.fromRGB(50, 50, 50)
			local iconImg = (discovered and areaIcons and areaIcons[tIdx]) and areaIcons[tIdx] or "rbxassetid://0"
			UpdateOrCreateRow(scrolls["Index"], "Index_"..indexCount, auraTitle, auraTitleColor, "Area " .. aIdx, nil, iconImg, iconColor, statusText, statusColor)
			indexCount += 1
		end
	end

	for i, badge in ipairs(AchievementConfig.Badges) do
		UpdateOrCreateRow(scrolls["Badges"], "Badge_"..i, badge.title, T.bodyText, badge.desc, nil, badge.iconId, T.accentGold, "BADGE", T.subText)
	end
	UpdateOrCreateRow(scrolls["Leaderboard"], "Leader_1", "1. MoldySugar2205", T.bodyText, "Total Earnings", nil, "rbxassetid://0", T.accentGold, "Top Player", T.accentGreen)
end

---------------------------------------------------------------
-- 6. BRIDGENET2 LISTENER
---------------------------------------------------------------
UpdateHUDBridge:Connect(function(stats)
	for key, value in pairs(stats) do latestStats[key] = value end

	if stats.soulAuras   ~= nil then liveSoulAuras   = stats.soulAuras   end
	if stats.totalEarned ~= nil then liveRunEarnings = stats.totalEarned end
	if stats.rate ~= nil and stats.passiveInterval ~= nil and stats.passiveInterval > 0 then
		liveRate = stats.rate / stats.passiveInterval
	end
	if stats.prestigeCount ~= nil then livePrestiges = stats.prestigeCount end

	if stats.settings then
		if stats.settings.sfxEnabled ~= nil then
			sfxEnabled = stats.settings.sfxEnabled
			if toggleRefs.sfx then toggleRefs.sfx(sfxEnabled) end
			SettingsChanged:Fire("sfx", sfxEnabled)
		end
		if stats.settings.musicEnabled ~= nil then
			musicEnabled = stats.settings.musicEnabled
			if toggleRefs.music then toggleRefs.music(musicEnabled) end
			SettingsChanged:Fire("music", musicEnabled)
		end
		if stats.settings.jumpEnabled ~= nil then
			jumpEnabled = stats.settings.jumpEnabled
			if toggleRefs.jump then toggleRefs.jump(jumpEnabled) end
			SettingsChanged:Fire("jump", jumpEnabled)
		end
	end

	if panelOpen then 
		RefreshData() 
		RefreshStats()
	end
end)

---------------------------------------------------------------
-- 7. DISCOVERY BANNER SYSTEM
---------------------------------------------------------------
local bannerQueue = {}
local isShowingDiscovery = false

local function ShowNextDiscovery()
	if isShowingDiscovery or #bannerQueue == 0 then return end
	isShowingDiscovery = true
	local info = table.remove(bannerQueue, 1)
	PlayUI(SoundConfig.UIOpen or "") 

	local banner = Instance.new("Frame", mainHUD)
	banner.Size = UDim2.new(0, 260, 0, 70); banner.Position = UDim2.new(0, -300, 0.4, 0); banner.BackgroundColor3 = T.panelBG; banner.BorderSizePixel = 0; banner.ZIndex = 100
	Instance.new("UICorner", banner).CornerRadius = UDim.new(0, 8)
	local stroke = Instance.new("UIStroke", banner); stroke.Color = info.color; stroke.Thickness = 2
	local icon = Instance.new("ImageLabel", banner); icon.Size = UDim2.new(0, 50, 0, 50); icon.Position = UDim2.new(0, 10, 0.5, -25); icon.BackgroundTransparency = 1; icon.Image = "rbxassetid://14916846070"; icon.ImageColor3 = info.color
	local title = Instance.new("TextLabel", banner); title.Size = UDim2.new(1, -70, 0, 20); title.Position = UDim2.new(0, 70, 0, 12); title.BackgroundTransparency = 1; title.Text = "NEW AURA UNLOCKED!"; title.TextColor3 = T.subText; title.Font = T.fontBody; title.TextScaled = true; title.TextXAlignment = Enum.TextXAlignment.Left
	local nameLbl = Instance.new("TextLabel", banner); nameLbl.Size = UDim2.new(1, -70, 0, 24); nameLbl.Position = UDim2.new(0, 70, 0, 34); nameLbl.BackgroundTransparency = 1; nameLbl.Text = string.upper(info.actualName or info.name) .. " AURA"; nameLbl.TextColor3 = info.color; nameLbl.Font = T.font; nameLbl.TextScaled = true; nameLbl.TextXAlignment = Enum.TextXAlignment.Left

	TweenService:Create(banner, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Position = UDim2.new(0, 20, 0.4, 0)}):Play()

	task.delay(4, function()
		TweenService:Create(banner, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Position = UDim2.new(0, -300, 0.4, 0)}):Play()
		task.delay(0.5, function() if banner.Parent then banner:Destroy() end; isShowingDiscovery = false; ShowNextDiscovery() end)
	end)
end

if AuraDiscovered then
	AuraDiscovered.OnClientEvent:Connect(function(discoveries)
		for _, d in ipairs(discoveries) do
			local areaNames = AreaAuraNames[d.area] or AreaAuraNames[1]
			local tierIndex = 1
			for i, t in ipairs(TierConfig.Tiers) do if t.name == d.name then tierIndex = i; break end end
			if tierIndex <= 5 then d.actualName = areaNames[tierIndex]; table.insert(bannerQueue, d) end
		end
		ShowNextDiscovery()
	end)
end

---------------------------------------------------------------
-- 8. BUTTON JUICE & OPEN/CLOSE
---------------------------------------------------------------
local function AddButtonJuice(btn)
	local scale = btn:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", btn)
	btn.MouseEnter:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15), {Scale = 1.08}):Play() end)
	btn.MouseLeave:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15), {Scale = 1}):Play() end)
	btn.MouseButton1Down:Connect(function() TweenService:Create(scale, TweenInfo.new(0.1), {Scale = 0.9}):Play() end)
	btn.MouseButton1Up:Connect(function() TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), {Scale = 1.08}):Play() end)
end

AddButtonJuice(AchieveBtn); AddButtonJuice(CloseBtn)
for _, t in pairs(tabBtns) do AddButtonJuice(t.btn) end

local function OpenToTab(tabName, hoverText)
	PlayUI(SoundConfig.UIOpen or "")
	panelOpen = true; Panel.Visible = true; Panel.Size = UDim2.new(0.85, 0, 0, 0)

	activeTab = tabName; activeTabText = hoverText; HoverLabel.Text = activeTabText
	for k, t in pairs(tabBtns) do 
		t.btn.BackgroundColor3 = (k == activeTab) and T.accentGold or T.buttonSecondary 
		t.stroke.Color = (k == activeTab) and T.bodyText or T.panelStroke
	end
	for k, s in pairs(scrolls) do s.Visible = (k == activeTab) end

	RefreshData()
	RefreshStats()

	TitleLabel.Text = (tabName == "Settings") and "SETTINGS" or "MENU"

	TweenService:Create(Panel, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = UDim2.new(0.85, 0, 0.75, 0)}):Play()
	UITheme.SetMenuVisible(true)
end

AchieveBtn.MouseButton1Down:Connect(function()
	if not panelOpen and type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_OpenAchievements") then return end
	if panelOpen then CloseBtn.MouseButton1Down:Fire() else OpenToTab("Challenges", "Boosts") end
end)

CloseBtn.MouseButton1Down:Connect(function()
	PlayUI(SoundConfig.UIClose or ""); panelOpen = false
	TweenService:Create(Panel, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Size = UDim2.new(0.85, 0, 0, 0)}):Play()
	UITheme.SetMenuVisible(false); task.delay(0.25, function() Panel.Visible = false end)
end)

task.spawn(function()
	task.wait(1)
	UITheme.Apply(Panel, "Panel")
	UITheme.Apply(Header, "TitleBar")
	UITheme.ApplyShine(Panel)
end)

---------------------------------------------------------------
-- JUMP ENFORCER LOGIC
---------------------------------------------------------------
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

-- BoostController
-- Location: StarterPlayer > StarterPlayerScripts > BoostController

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local AdminConfig       = require(ReplicatedStorage.Modules.AdminConfig)
local SoundConfig       = require(ReplicatedStorage.Modules.SoundConfig)
local BoostConfig       = require(ReplicatedStorage.Modules.BoostConfig) 
local AchievementConfig = require(ReplicatedStorage.Modules.AchievementConfig)
local UITheme           = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UITheme"))
local T                 = UITheme.Get("Custom")

local BuyBoost      = ReplicatedStorage.RemoteEvents:WaitForChild("BuyBoost")
local ActivateBoost = ReplicatedStorage.RemoteEvents:WaitForChild("ActivateBoost")
local BoostUpdated  = ReplicatedStorage.RemoteEvents:WaitForChild("BoostUpdated")

-- ✨ BRIDGENET2 UPGRADE
local BridgeNet2      = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))
local UpdateHUDBridge = BridgeNet2.ClientBridge("UpdateHUD")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainHUD   = playerGui:WaitForChild("MainHUD")

local boostState = {}
local panelOpen  = false
local liveGold   = 0

local function PlayUI(id)
	if shared.PlayUISound then shared.PlayUISound(id) end
end

local function FormatTime(s)
	s = math.ceil(s or 0)
	if s <= 0 then return "0:00" end
	return string.format("%d:%02d", math.floor(s/60), s % 60)
end

---------------------------------------------------------------
-- ✨ ACTIVE BOOST STRIP (Sleek & Polished)
---------------------------------------------------------------
local BoostStrip = Instance.new("Frame")
BoostStrip.Name = "ActiveBoostStrip"
BoostStrip.Size = UDim2.new(0.14, 0, 0.5, 0) 
BoostStrip.AnchorPoint = Vector2.new(1, 0)
BoostStrip.Position = UDim2.new(0.98, 0, 0.5, 0) 
BoostStrip.BackgroundTransparency = 1
BoostStrip.ZIndex = 60; BoostStrip.Visible = false; BoostStrip.Parent = mainHUD

local StripLayout = Instance.new("UIListLayout")
StripLayout.FillDirection = Enum.FillDirection.Vertical
StripLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right 
StripLayout.VerticalAlignment = Enum.VerticalAlignment.Top
StripLayout.Padding = UDim.new(0, 6)
StripLayout.Parent = BoostStrip

local stripSlots = {}

for _, boostId in ipairs(BoostConfig.ShopOrder) do
	local cfg   = BoostConfig.Get(boostId)
	if not cfg then continue end
	local color = cfg.color

	local slot = Instance.new("Frame")
	slot.Name = "Slot_" .. boostId
	slot.Size = UDim2.new(1, 0, 0, 42)  
	slot.BackgroundColor3 = T.cardBG; slot.BorderSizePixel = 0
	slot.ZIndex = 61; slot.Visible = false; slot.Parent = BoostStrip
	Instance.new("UICorner", slot).CornerRadius = UDim.new(0, 8)
	local ss = Instance.new("UIStroke"); ss.Color = color; ss.Thickness = 1.5; ss.Parent = slot

	local iconFrame = Instance.new("Frame", slot)
	iconFrame.Size = UDim2.new(0, 32, 0, 32)
	iconFrame.Position = UDim2.new(0, 5, 0.5, -16)
	iconFrame.BackgroundColor3 = color
	iconFrame.BackgroundTransparency = 0.8
	Instance.new("UICorner", iconFrame).CornerRadius = UDim.new(0, 6)

	local iconLbl = Instance.new("ImageLabel", iconFrame)
	iconLbl.Size = UDim2.new(0.8, 0, 0.8, 0)
	iconLbl.Position = UDim2.new(0.1, 0, 0.1, 0)
	iconLbl.BackgroundTransparency = 1; iconLbl.Image = cfg.icon or ""
	iconLbl.ScaleType = Enum.ScaleType.Fit
	iconLbl.ZIndex = 62

	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size = UDim2.new(0.5, 0, 0.45, 0)
	nameLbl.Position = UDim2.new(0, 45, 0, 4)
	nameLbl.BackgroundTransparency = 1; nameLbl.Text = cfg.displayName or boostId
	nameLbl.TextColor3 = color; nameLbl.TextScaled = true
	nameLbl.Font = Enum.Font.FredokaOne; nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.ZIndex = 62; nameLbl.Parent = slot

	local shadow = nameLbl:Clone()
	shadow.Name = "Shadow"
	shadow.ZIndex = 61
	shadow.TextColor3 = Color3.fromRGB(0,0,0)
	shadow.TextTransparency = 0.5
	shadow.Position = nameLbl.Position + UDim2.new(0,1,0,1)
	shadow.Parent = slot

	local timeLbl = Instance.new("TextLabel")
	timeLbl.Name = "TimeLabel"
	timeLbl.Size = UDim2.new(0.25, 0, 0.55, 0)
	timeLbl.Position = UDim2.new(1, -55, 0, 2)
	timeLbl.BackgroundTransparency = 1; timeLbl.Text = "0:30"
	timeLbl.TextColor3 = color; timeLbl.TextScaled = true
	timeLbl.Font = Enum.Font.FredokaOne; timeLbl.TextXAlignment = Enum.TextXAlignment.Right
	timeLbl.ZIndex = 62; timeLbl.Parent = slot

	local stackLbl = Instance.new("TextLabel")
	stackLbl.Name = "StackLabel"
	stackLbl.Size = UDim2.new(0.5, 0, 0.35, 0)
	stackLbl.Position = UDim2.new(0, 45, 0.5, 3)
	stackLbl.BackgroundTransparency = 1; stackLbl.Text = ""
	stackLbl.TextColor3 = T.subText; stackLbl.TextScaled = true
	stackLbl.Font = Enum.Font.GothamMedium; stackLbl.TextXAlignment = Enum.TextXAlignment.Left
	stackLbl.ZIndex = 62; stackLbl.Parent = slot

	stripSlots[boostId] = { slot = slot, timeLbl = timeLbl, stackLbl = stackLbl }
end

local BoostsBtn = Instance.new("ImageButton")
BoostsBtn.Name = "BoostsButton"
BoostsBtn.Size = UDim2.new(0, 60, 0, 60)
BoostsBtn.AnchorPoint = Vector2.new(1, 1) 
BoostsBtn.Position = UDim2.new(0.98, 0, 0.77, 0) 
BoostsBtn.BackgroundColor3 = T.buttonPrimary; BoostsBtn.BorderSizePixel = 0
BoostsBtn.AutoButtonColor = false
BoostsBtn.ZIndex = 10; BoostsBtn.Parent = mainHUD
BoostsBtn:SetAttribute("TutorialTarget", "BoostsButton")
Instance.new("UICorner", BoostsBtn).CornerRadius = UDim.new(0.5, 0)

local bbStroke = Instance.new("UIStroke", BoostsBtn)
bbStroke.Color = T.accentPurple; bbStroke.Thickness = 2

local boostIcon = Instance.new("ImageLabel", BoostsBtn)
boostIcon.Size = UDim2.new(0.6, 0, 0.6, 0); boostIcon.Position = UDim2.new(0.2, 0, 0.2, 0)
boostIcon.BackgroundTransparency = 1; boostIcon.ScaleType = Enum.ScaleType.Fit
boostIcon.Image = "rbxassetid://14916846070" 

-- ✨ TUTORIAL TAG
CollectionService:AddTag(BoostsBtn, "Tutorial_BoostMenuBtn")

---------------------------------------------------------------
-- ✨ BOOST SHOP PANEL (Tutorial Style)
---------------------------------------------------------------
local ShopPanel = Instance.new("Frame")
ShopPanel.Name = "BoostShopPanel"
ShopPanel.Size = UDim2.new(0.85, 0, 0.8, 0) 
ShopPanel.Position = UDim2.new(0.5, 0, 0.5, 0)
ShopPanel.AnchorPoint = Vector2.new(0.5, 0.5) 
ShopPanel.BackgroundColor3 = T.panelBG; ShopPanel.BorderSizePixel = 0
ShopPanel.Visible = false; ShopPanel.ZIndex = 40
ShopPanel.ClipsDescendants = true
ShopPanel.Parent = mainHUD
CollectionService:AddTag(ShopPanel, "Tutorial_BoostShopPanel")
Instance.new("UICorner", ShopPanel).CornerRadius = UDim.new(0, 14)

local sizeConstraint = Instance.new("UISizeConstraint")
sizeConstraint.MaxSize = Vector2.new(380, 520)
sizeConstraint.Parent = ShopPanel

local shopStroke = Instance.new("UIStroke")
shopStroke.Color = T.accentPurple; shopStroke.Thickness = 2; shopStroke.Parent = ShopPanel

local ShopHeader = Instance.new("Frame")
ShopHeader.Size = UDim2.new(1, 0, 0, 46)
ShopHeader.BackgroundColor3 = T.headerBG; ShopHeader.BorderSizePixel = 0
ShopHeader.ZIndex = 41; ShopHeader.Parent = ShopPanel
Instance.new("UICorner", ShopHeader).CornerRadius = UDim.new(0, 14)

local ShopTitle = Instance.new("TextLabel")
ShopTitle.Size = UDim2.new(1, -50, 1, 0); ShopTitle.Position = UDim2.new(0, 14, 0, 0)
ShopTitle.BackgroundTransparency = 1; ShopTitle.Text = "BOOST SHOP"
ShopTitle.TextColor3 = T.headerText; ShopTitle.TextScaled = true
ShopTitle.Font = Enum.Font.FredokaOne; ShopTitle.TextXAlignment = Enum.TextXAlignment.Left
ShopTitle.ZIndex = 42; ShopTitle.Parent = ShopHeader

local ShopClose = Instance.new("TextButton")
ShopClose.Size = UDim2.new(0, 32, 0, 32); ShopClose.Position = UDim2.new(1, -40, 0.5, -16)
ShopClose.BackgroundColor3 = T.buttonRed; ShopClose.BorderSizePixel = 0
ShopClose.Text = "X"; ShopClose.TextColor3 = T.bodyText
ShopClose.TextScaled = true; ShopClose.Font = Enum.Font.FredokaOne
ShopClose.ZIndex = 9999; ShopClose.Parent = ShopHeader
CollectionService:AddTag(ShopClose, "Tutorial_BoostShopClose")
Instance.new("UICorner", ShopClose).CornerRadius = UDim.new(0, 6)

local ScrollContainer = Instance.new("ScrollingFrame")
ScrollContainer.Name = "ScrollContainer"
ScrollContainer.Size = UDim2.new(1, 0, 1, -56) 
ScrollContainer.Position = UDim2.new(0, 0, 0, 56)
ScrollContainer.BackgroundTransparency = 1
ScrollContainer.BorderSizePixel = 0
ScrollContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
ScrollContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y
ScrollContainer.ScrollBarThickness = 6
ScrollContainer.Parent = ShopPanel

local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 10)
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
listLayout.Parent = ScrollContainer

local topPadding = Instance.new("UIPadding")
topPadding.PaddingTop = UDim.new(0, 5)
topPadding.PaddingBottom = UDim.new(0, 15)
topPadding.Parent = ScrollContainer

local function AddButtonJuice(btn)
	local scale = btn:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = btn
	end

	btn.MouseEnter:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Sine), {Scale = 1.05}):Play() end)
	btn.MouseLeave:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Sine), {Scale = 1}):Play() end)
	btn.MouseButton1Down:Connect(function() TweenService:Create(scale, TweenInfo.new(0.1, Enum.EasingStyle.Sine), {Scale = 0.95}):Play() end)
	btn.MouseButton1Up:Connect(function() TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), {Scale = 1.05}):Play() end)
end

AddButtonJuice(BoostsBtn)
AddButtonJuice(ShopClose)

local cardRefs = {}

local function BuildCards()
	for i, boostId in ipairs(BoostConfig.ShopOrder) do
		local cfg = BoostConfig.Get(boostId)
		if not cfg then continue end
		local color = cfg.color

		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, -20, 0, 105) 
		card.BackgroundColor3 = T.cardBG; card.BorderSizePixel = 0
		card.ZIndex = 41; card.Parent = ScrollContainer
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)

		local cs = Instance.new("UIStroke"); cs.Color = color; cs.Thickness = 1.5; cs.Parent = card

		local iconFrame = Instance.new("Frame", card)
		iconFrame.Size = UDim2.new(0, 48, 0, 48)
		iconFrame.Position = UDim2.new(0, 10, 0.5, -24)
		iconFrame.BackgroundColor3 = color
		iconFrame.BackgroundTransparency = 0.85
		Instance.new("UICorner", iconFrame).CornerRadius = UDim.new(0, 10)

		local iconLbl = Instance.new("ImageLabel", iconFrame)
		iconLbl.Size = UDim2.new(0.7, 0, 0.7, 0); iconLbl.Position = UDim2.new(0.15, 0, 0.15, 0)
		iconLbl.BackgroundTransparency = 1; iconLbl.Image = cfg.icon or ""
		iconLbl.ScaleType = Enum.ScaleType.Fit; iconLbl.ZIndex = 42

		local nameLbl = Instance.new("TextLabel")
		nameLbl.Size = UDim2.new(0.5, 0, 0, 22); nameLbl.Position = UDim2.new(0, 68, 0, 10)
		nameLbl.BackgroundTransparency = 1; nameLbl.Text = string.upper(cfg.displayName or boostId)
		nameLbl.TextColor3 = color; nameLbl.TextScaled = true
		nameLbl.Font = Enum.Font.FredokaOne; nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		nameLbl.ZIndex = 42; nameLbl.Parent = card

		local shadow = nameLbl:Clone()
		shadow.Name = "Shadow"; shadow.ZIndex = 41; shadow.TextColor3 = Color3.fromRGB(0,0,0)
		shadow.TextTransparency = 0.6; shadow.Position = nameLbl.Position + UDim2.new(0,2,0,2)
		shadow.Parent = card

		local descLbl = Instance.new("TextLabel")
		descLbl.Size = UDim2.new(0.65, 0, 0, 36); descLbl.Position = UDim2.new(0, 68, 0, 35)
		descLbl.BackgroundTransparency = 1; descLbl.Text = cfg.description or ""
		descLbl.TextColor3 = T.subText; descLbl.TextScaled = true; descLbl.TextWrapped = true
		descLbl.Font = Enum.Font.GothamMedium; descLbl.TextXAlignment = Enum.TextXAlignment.Left; descLbl.TextYAlignment = Enum.TextYAlignment.Top
		descLbl.ZIndex = 42; descLbl.Parent = card

		local durLbl = Instance.new("TextLabel")
		durLbl.Size = UDim2.new(0.65, 0, 0, 14); durLbl.Position = UDim2.new(0, 68, 0, 75)
		durLbl.BackgroundTransparency = 1; durLbl.Text = cfg.duration == 0 and "Instant Use" or (FormatTime(cfg.duration) .. " duration")
		durLbl.TextColor3 = Color3.fromRGB(130, 135, 160); durLbl.TextScaled = true
		durLbl.Font = Enum.Font.GothamMedium; durLbl.TextXAlignment = Enum.TextXAlignment.Left
		durLbl.ZIndex = 42; durLbl.Parent = card

		local buyBtn = Instance.new("TextButton")
		buyBtn.Size = UDim2.new(0, 90, 0, 40); buyBtn.Position = UDim2.new(1, -100, 0, 10)
		buyBtn.BorderSizePixel = 0; buyBtn.TextScaled = true; buyBtn.Font = Enum.Font.FredokaOne
		buyBtn.ZIndex = 42; buyBtn.Parent = card
		Instance.new("UICorner", buyBtn).CornerRadius = UDim.new(0, 8)
		CollectionService:AddTag(buyBtn, "Tutorial_BuyBoost_" .. boostId)
		AddButtonJuice(buyBtn)

		local actBtn = Instance.new("TextButton")
		actBtn.Size = UDim2.new(0, 90, 0, 40); actBtn.Position = UDim2.new(1, -100, 0, 55)
		actBtn.BorderSizePixel = 0; actBtn.TextScaled = true; actBtn.Font = Enum.Font.FredokaOne
		actBtn.ZIndex = 42; actBtn.Parent = card
		Instance.new("UICorner", actBtn).CornerRadius = UDim.new(0, 8)
		CollectionService:AddTag(actBtn, "Tutorial_UseBoost_" .. boostId)
		AddButtonJuice(actBtn)

		local invBadge = Instance.new("TextLabel")
		invBadge.Size = UDim2.new(0, 28, 0, 20); invBadge.Position = UDim2.new(0, 10, 1, -30)
		invBadge.BackgroundColor3 = Color3.fromRGB(20, 20, 30); invBadge.BorderSizePixel = 0
		invBadge.Text = "x0"; invBadge.TextColor3 = T.bodyText
		invBadge.TextScaled = true; invBadge.Font = Enum.Font.FredokaOne
		invBadge.ZIndex = 43; invBadge.Parent = card
		Instance.new("UICorner", invBadge).CornerRadius = UDim.new(0, 6)
		local invStroke = Instance.new("UIStroke", invBadge)
		invStroke.Color = T.panelStroke; invStroke.Thickness = 1.5

		cardRefs[boostId] = { card=card, cs=cs, buyBtn=buyBtn, actBtn=actBtn, invBadge=invBadge, descLbl=descLbl, color=color }

		buyBtn.MouseButton1Down:Connect(function() 
			if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_BuyBoost_" .. boostId) then return end
			BuyBoost:FireServer(boostId) 
			if type(shared.TutorialRecordBoostBought) == "function" then shared.TutorialRecordBoostBought(boostId) end
			if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
		end)

		actBtn.MouseButton1Down:Connect(function()
			if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_UseBoost_" .. boostId) then return end
			local state = boostState[boostId]
			if not state or (state.inventoryCount or 0) <= 0 then return end
			ActivateBoost:FireServer(boostId)
			if type(shared.TutorialRecordBoostUsed) == "function" then shared.TutorialRecordBoostUsed(boostId) end
			if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
		end)
	end
end

BuildCards()
local latestStats = {}

local function RefreshCards()
	for boostId, refs in pairs(cardRefs) do
		local cfg         = BoostConfig.Get(boostId)
		local state       = boostState[boostId]
		local color       = refs.color
		local invCount    = state and (state.inventoryCount or 0) or 0
		local activeCount = state and (state.activeCount or 0) or 0
		local cost        = cfg and cfg.cost or 0
		local canAfford   = liveGold >= cost
		local atCap       = activeCount >= (cfg and cfg.maxStack or 1)

		local isUnlocked, lockReason = AchievementConfig.IsBoostUnlocked(boostId, latestStats)

		refs.invBadge.Text       = "x" .. invCount
		refs.invBadge.TextColor3 = invCount > 0 and T.accentGold or T.subText

		if not isUnlocked then
			refs.buyBtn.Text             = "LOCKED"
			refs.buyBtn.BackgroundColor3 = T.buttonRed
			refs.buyBtn.TextColor3       = T.bodyText

			refs.actBtn.Text             = "Locked"
			refs.actBtn.BackgroundColor3 = T.buttonDisabled
			refs.actBtn.TextColor3       = T.subText

			refs.descLbl.Text = "Requires: " .. lockReason
			refs.descLbl.TextColor3 = T.buttonRed
		else
			refs.descLbl.Text = cfg.description or ""
			refs.descLbl.TextColor3 = T.subText

			refs.buyBtn.Text             = cost .. " ⭐"
			refs.buyBtn.TextColor3       = T.bodyText
			refs.buyBtn.BackgroundColor3 = canAfford and T.buttonGreen or T.buttonDisabled

			if invCount <= 0 then
				refs.actBtn.Text             = "No Stock"
				refs.actBtn.BackgroundColor3 = T.buttonDisabled
				refs.actBtn.TextColor3       = T.subText
			elseif atCap then
				refs.actBtn.Text             = "MAX (" .. FormatTime(state and state.activeTimes and state.activeTimes[1] or 0) .. ")"
				refs.actBtn.BackgroundColor3 = Color3.fromRGB(40, 80, 50)
				refs.actBtn.TextColor3       = color
			else
				refs.actBtn.Text             = "Activate"
				refs.actBtn.BackgroundColor3 = color
				refs.actBtn.TextColor3       = T.bodyText
			end
		end
	end
end

local function RefreshStrip()
	local anyActive = false
	for _, boostId in ipairs(BoostConfig.ShopOrder) do
		local state = boostState[boostId]
		local refs  = stripSlots[boostId]
		if not refs then continue end
		if state and (state.activeCount or 0) > 0 then
			anyActive = true; refs.slot.Visible = true
			local minTime = math.huge
			for _, t in ipairs(state.activeTimes or {}) do if t < minTime then minTime = t end end
			refs.timeLbl.Text  = FormatTime(minTime)
			refs.stackLbl.Text = state.activeCount > 1 and ("x" .. state.activeCount) or ""
		else
			refs.slot.Visible = false
		end
	end
	BoostStrip.Visible = anyActive
end

local function OpenPanel()
	panelOpen = true; ShopPanel.Visible = true
	ShopPanel.Size = UDim2.new(0.85, 0, 0, 0)
	RefreshCards()
	TweenService:Create(ShopPanel, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0.85, 0, 0.8, 0)
	}):Play()
	UITheme.SetMenuVisible(true)
end

local function ClosePanel()
	panelOpen = false
	PlayUI(SoundConfig.UIClose)
	TweenService:Create(ShopPanel, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Size = UDim2.new(0.85, 0, 0, 0)
	}):Play()
	UITheme.SetMenuVisible(false)
	task.delay(0.3, function() ShopPanel.Visible = false end)
end

BoostsBtn.MouseButton1Down:Connect(function() 
	-- ✨ THE FIX: Respect the lock in BOTH directions (Opening AND Closing)
	if panelOpen then
		if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_CloseBoostShop") then return end
		ClosePanel()
	else
		if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_OpenBoostShop") then return end
		OpenPanel()
	end 

	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
end)

ShopClose.MouseButton1Down:Connect(function()
	if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_CloseBoostShop") then return end
	ClosePanel()
	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
end)

BoostUpdated.OnClientEvent:Connect(function(state)
	if state._goldenAuras ~= nil then liveGold = state._goldenAuras; state._goldenAuras = nil end
	boostState = state; RefreshStrip()
	if panelOpen then RefreshCards() end
end)

UpdateHUDBridge:Connect(function(stats)
	for key, value in pairs(stats) do
		latestStats[key] = value
	end
	if stats.goldenAuras ~= nil then liveGold = stats.goldenAuras end
	if stats.boostInventory then
		for boostId, count in pairs(stats.boostInventory) do
			if boostState[boostId] then boostState[boostId].inventoryCount = count end
		end
	end
	if panelOpen then RefreshCards() end
end)

RunService.RenderStepped:Connect(function(dt)
	local anyActive = false
	for _, boostId in ipairs(BoostConfig.ShopOrder) do
		local state = boostState[boostId]
		if state and state.activeTimes and #state.activeTimes > 0 then
			anyActive = true
			local clean = {}
			for _, t in ipairs(state.activeTimes) do
				local newT = math.max(0, t - dt)
				if newT > 0 then table.insert(clean, newT) end
			end
			state.activeTimes = clean; state.activeCount = #clean
			local refs = stripSlots[boostId]
			if refs then
				if #clean > 0 then
					local minTime = math.huge
					for _, t in ipairs(clean) do if t < minTime then minTime = t end end
					refs.timeLbl.Text  = FormatTime(minTime)
					refs.stackLbl.Text = #clean > 1 and ("x" .. #clean) or ""
					refs.slot.Visible  = true
				else
					refs.slot.Visible = false
				end
			end
		end
	end
	BoostStrip.Visible = anyActive
end)

local shopShine = nil
local function RefreshLook()
	UITheme.Apply(ShopPanel, "Panel")
	UITheme.Apply(ShopHeader, "TitleBar")
	if not shopShine then
		shopShine = UITheme.ApplyShine(ShopPanel)
	end
	for _, card in ipairs(ScrollContainer:GetChildren()) do
		if card:IsA("Frame") then
			UITheme.Apply(card, "ShopCard")
		end
	end
end

task.wait(1) 
RefreshLook()

local forceClose = ReplicatedStorage:FindFirstChild("ForceCloseUI") or Instance.new("BindableEvent")
forceClose.Name = "ForceCloseUI"
forceClose.Parent = ReplicatedStorage
forceClose.Event:Connect(function()
	if panelOpen then ClosePanel() end
end)
