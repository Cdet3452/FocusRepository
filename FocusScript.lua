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
	local globalHoldActive  = false  
	local globalHoldGeneration = 0    

	-- FORWARD DECLARATIONS
	local UpdateLockedTierProgress = nil
	local RebuildRegularShop = nil 

	for _, tierData in ipairs(UpgradeConfig.Tiers) do
		for upgradeId, cfg in pairs(tierData.upgrades) do
			upgradeState[upgradeId] = { level = 0, maxLevel = cfg.maxLevel, cost = UpgradeConfig.CalculateCost(upgradeId, 0), maxed = false }
		end
	end

	for _, tierData in ipairs(EpicUpgradeConfig.Tiers) do
		for upgradeId, cfg in pairs(tierData.upgrades) do
			epicUpgradeState[upgradeId] = { level = 0, maxLevel = cfg.maxLevel, cost = EpicUpgradeConfig.CalculateCost(upgradeId, 0), maxed = false }
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
			TweenService:Create(particle, tInfo, { Position = endPos, Size = UDim2.new(0, 0, 0, 0), Rotation = particle.Rotation + math.random(-180, 180), BackgroundTransparency = 1 }):Play()
		end
		task.delay(1, function() burstGui:Destroy() end)
	end

	local comboPitch  = 1.0
	local lastBuyTime = tick()

	local function PlayPurchaseSound()
		if tick() - lastBuyTime < 0.3 then comboPitch = math.min(comboPitch + 0.05, 2.5) else comboPitch = 1.0 end
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
			TweenService:Create(targetButton, wobbleInfo, { Position = origPos + UDim2.new(0, 4, 0, 0) }):Play()
		end
	end

	local function FormatNumber(n) return Formatter.Format(n) end
	local function PlayUI(id) if shared.PlayUISound then shared.PlayUISound(id) end end

	-- ─────────────────────────────────────────────────────────────────────────────
	-- ✨ SHOP BUTTON
	-- ─────────────────────────────────────────────────────────────────────────────
	local ShopButton = Instance.new("ImageButton")
	ShopButton.Name              = "ShopButton"
	ShopButton.BackgroundColor3  = T.buttonSecondary
	ShopButton.BorderSizePixel   = 0
	ShopButton.AutoButtonColor   = false
	ShopButton.ZIndex            = 15

	local Faded2 = mainHUD:FindFirstChild("Faded2")
	if Faded2 then
		ShopButton.Parent = Faded2
		ShopButton.Size = UDim2.new(0.85, 0, 0.85, 0)
		local aspect = Instance.new("UIAspectRatioConstraint", ShopButton)
		aspect.AspectRatio = 1.0

		local layout = Faded2:FindFirstChildOfClass("UIListLayout")
		if not layout then
			layout = Instance.new("UIListLayout", Faded2)
			layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
			layout.VerticalAlignment = Enum.VerticalAlignment.Center
			layout.Padding = UDim.new(0, 15)
			layout.SortOrder = Enum.SortOrder.LayoutOrder
		end
		ShopButton.LayoutOrder = 2 
	else
		ShopButton.Size = UDim2.new(0, 60, 0, 60)
		ShopButton.AnchorPoint = Vector2.new(0, 0.5)
		ShopButton.Position = UDim2.new(0, 15, 0.5, 0)
		ShopButton.Parent = mainHUD
	end

	CollectionService:AddTag(ShopButton, "Tutorial_ShopButton")
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
	-- ✨ SHOP PANEL (Scaled for Sleekness)
	-- ─────────────────────────────────────────────────────────────────────────────
	local PANEL_MAX_W = 360; local PANEL_MAX_H = 620; local HEADER_H = 42

	local ShopPanel = Instance.new("Frame")
	ShopPanel.Name              = "ShopPanel"
	-- ✨ THE FIX: Smaller overall footprint (38% width, 72% height) stops it from hitting the bottom HUD!
	ShopPanel.Size              = UDim2.new(0.38, 0, 0.72, 0) 
	ShopPanel.AnchorPoint       = Vector2.new(0, 0) 
	ShopPanel.Position          = UDim2.new(0, -500, 0.08, 0) 
	ShopPanel.BackgroundColor3  = T.panelBG
	ShopPanel.BorderSizePixel   = 0
	ShopPanel.Visible           = false
	ShopPanel.ZIndex            = 10
	ShopPanel.ClipsDescendants  = true
	ShopPanel.Parent            = mainHUD
	CollectionService:AddTag(ShopPanel, "Tutorial_ShopPanel") 
	Instance.new("UICorner", ShopPanel).CornerRadius = UDim.new(0, 10)

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(PANEL_MAX_W, PANEL_MAX_H)
	-- ✨ THE FIX: Extremely small MinSize guarantees it NEVER crosses the middle
	sizeConstraint.MinSize = Vector2.new(245, 300) 
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
	CollectionService:AddTag(CloseButton, "Tutorial_ShopCloseBtn") 
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
		tween:Play(); tween.Completed:Once(function() InfoPopup.Visible = false end)
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
	-- ✨ CARD BUILDER (Foolproof overlap prevention)
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
		icon.Size               = UDim2.new(0, 44, 0, 44)
		icon.Position           = UDim2.new(0, 10, 0.5, -22)
		icon.BackgroundTransparency = 1
		icon.Image              = cfg.iconId or "rbxassetid://0"

		local infoBtn = Instance.new("TextButton", card)
		infoBtn.Size             = UDim2.new(0, 22, 0, 22)
		infoBtn.Position         = UDim2.new(0, 58, 0, 10)
		infoBtn.BackgroundColor3 = T.buttonSecondary
		infoBtn.Text             = "i"
		infoBtn.TextColor3       = T.bodyText
		infoBtn.Font             = Enum.Font.GothamBlack
		infoBtn.TextSize         = 14
		Instance.new("UICorner", infoBtn).CornerRadius = UDim.new(1, 0)
		infoBtn.MouseButton1Click:Connect(function() ShowInfo(cfg.displayName, cfg.description) end)

		-- ✨ Even tighter text bounds to match the new ultra-sleek panel
		local nameLabel = Instance.new("TextLabel", card)
		nameLabel.Size              = UDim2.new(1, -145, 0, 20)
		nameLabel.Position          = UDim2.new(0, 84, 0, 11)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text              = string.upper(cfg.displayName)
		nameLabel.TextColor3        = T.bodyText
		nameLabel.TextScaled        = true
		nameLabel.Font              = Enum.Font.FredokaOne
		nameLabel.TextXAlignment    = Enum.TextXAlignment.Left

		local descLabel = Instance.new("TextLabel", card)
		descLabel.Size              = UDim2.new(1, -140, 0, 36)
		descLabel.Position          = UDim2.new(0, 58, 0, 34)
		descLabel.BackgroundTransparency = 1
		descLabel.Text              = cfg.description
		descLabel.TextColor3        = T.subText
		descLabel.TextWrapped       = true
		descLabel.TextScaled        = true
		descLabel.Font              = Enum.Font.GothamMedium
		descLabel.TextXAlignment    = Enum.TextXAlignment.Left
		descLabel.TextYAlignment    = Enum.TextYAlignment.Top

		local levelLabel = Instance.new("TextLabel", card)
		levelLabel.Size             = UDim2.new(1, -140, 0, 16)
		levelLabel.Position         = UDim2.new(0, 58, 0, 74)
		levelLabel.BackgroundTransparency = 1
		levelLabel.Text             = "Lv. 0 / " .. cfg.maxLevel
		levelLabel.TextColor3       = T.accentGreen
		levelLabel.TextScaled       = true
		levelLabel.Font             = Enum.Font.FredokaOne
		levelLabel.TextXAlignment   = Enum.TextXAlignment.Left

		local buyButton = Instance.new("TextButton", card)
		buyButton.Name             = "PurchaseButton"
		buyButton.Size             = UDim2.new(0, 72, 0, 40) -- Slimmed down to fit smaller width
		buyButton.AnchorPoint      = Vector2.new(1, 0.5)
		buyButton.Position         = UDim2.new(1, -8, 0.5, 0)
		buyButton.BackgroundColor3 = isEpic and T.accentPurple or T.buttonGreen
		buyButton.BorderSizePixel  = 0
		buyButton.TextColor3       = T.bodyText
		buyButton.TextScaled       = true
		buyButton.Font             = Enum.Font.FredokaOne
		CollectionService:AddTag(buyButton, "Tutorial_Buy_" .. upgradeId) 
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
			if globalHoldGeneration ~= myGen then globalHoldGeneration = myGen end
		end

		local function TryBuy()
			if isLoadingData then return false end
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

			pulseTween = TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 0.88 })
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
			if scale then TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), { Scale = 1 }):Play() end
		end)

		local function StopHold()
			holdingBuy = false
			globalHoldActive = false
			if pulseTween then pulseTween:Cancel() end
			local scale = buyButton:FindFirstChildOfClass("UIScale")
			if scale then TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), { Scale = 1 }):Play() end
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
			ref.buyButton.TextColor3   = (actualCash < state.cost) and Color3.fromRGB(255, 100, 100) or Color3.fromRGB(255, 255, 255)
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
			ref.buyButton.TextColor3   = (actualAuras < state.cost) and Color3.fromRGB(255, 100, 100) or Color3.fromRGB(255, 255, 255)
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
				local lockedHeader = CreateLockedTierHeader(tierData.tierName or "Tier " .. tierNum, totalUpgradesBought, tierData.unlockRequirement)
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
	-- ✨ OPEN / CLOSE
	-- ─────────────────────────────────────────────────────────────────────────────
	local function OpenShop()
		shopOpen = true
		ShopPanel.Visible = true
		SwitchToMainTab(activeMainTab)

		-- ✨ Dropped to 8% Y to perfectly center it visually with the new shorter height
		TweenService:Create(ShopPanel, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0, 75, 0.08, 0) }):Play()
		ShopButton.BackgroundColor3 = T.panelStroke
	end

	local function CloseShop()
		shopOpen = false
		PlayUI(SoundConfig.UIClose)

		local tween = TweenService:Create(ShopPanel, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.new(0, -500, 0.08, 0) })
		tween:Play()
		tween.Completed:Once(function() if not shopOpen then ShopPanel.Visible = false end end)
		ShopButton.BackgroundColor3 = T.buttonSecondary
	end

	ShopButton.MouseButton1Down:Connect(function()
		if shopOpen then
			if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_CloseShop") then return end
			CloseShop()
			if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
		else
			if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_OpenShop") then return end
			OpenShop()
			if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
		end
	end)

	CloseButton.MouseButton1Down:Connect(function()
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
	-- BUTTON JUICE & REFRESH LOOK
	-- ─────────────────────────────────────────────────────────────────────────────
	local function AddButtonJuice(btn)
		if not btn then return end
		local scale = btn:FindFirstChildOfClass("UIScale")
		if not scale then scale = Instance.new("UIScale"); scale.Parent = btn end
		btn.MouseEnter:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Sine), { Scale = 1.08 }):Play() end)
		btn.MouseLeave:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Sine), { Scale = 1 }):Play() end)
		btn.MouseButton1Down:Connect(function() TweenService:Create(scale, TweenInfo.new(0.1, Enum.EasingStyle.Sine), { Scale = 0.9 }):Play() end)
		btn.MouseButton1Up:Connect(function() TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), { Scale = 1.08 }):Play() end)
	end

	AddButtonJuice(ShopButton); AddButtonJuice(CloseButton); AddButtonJuice(tabUpgrades); AddButtonJuice(tabEpic)

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

		if not titleFlair then titleFlair = UITheme.ApplyFlair(TitleLabel, "Ghost") end
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

	local forceClose = ReplicatedStorage:FindFirstChild("ForceCloseUI") or Instance.new("BindableEvent")
	forceClose.Name = "ForceCloseUI"
	forceClose.Parent = ReplicatedStorage
	forceClose.Event:Connect(function() if shopOpen then CloseShop() end end)
