-- BoostController
-- Location: StarterPlayer > StarterPlayerScripts > BoostController

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")

local AdminConfig       = require(ReplicatedStorage.Modules.AdminConfig)
local SoundConfig       = require(ReplicatedStorage.Modules.SoundConfig)
local BoostConfig       = require(ReplicatedStorage.Modules.BoostConfig) 
local AchievementConfig = require(ReplicatedStorage.Modules.AchievementConfig)
local UITheme           = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UITheme"))
local T                 = UITheme.Get("Custom")

local BuyBoost      = ReplicatedStorage.RemoteEvents:WaitForChild("BuyBoost")
local ActivateBoost = ReplicatedStorage.RemoteEvents:WaitForChild("ActivateBoost")
local BoostUpdated  = ReplicatedStorage.RemoteEvents:WaitForChild("BoostUpdated")
local UpdateHUD     = ReplicatedStorage.RemoteEvents:WaitForChild("UpdateHUD")

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
		AddButtonJuice(buyBtn)

		local actBtn = Instance.new("TextButton")
		actBtn.Size = UDim2.new(0, 90, 0, 40); actBtn.Position = UDim2.new(1, -100, 0, 55)
		actBtn.BorderSizePixel = 0; actBtn.TextScaled = true; actBtn.Font = Enum.Font.FredokaOne
		actBtn.ZIndex = 42; actBtn.Parent = card
		Instance.new("UICorner", actBtn).CornerRadius = UDim.new(0, 8)
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

		buyBtn.MouseButton1Down:Connect(function() BuyBoost:FireServer(boostId) end)
		actBtn.MouseButton1Down:Connect(function()
			local state = boostState[boostId]
			if not state or (state.inventoryCount or 0) <= 0 then return end
			ActivateBoost:FireServer(boostId)
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

BoostsBtn.MouseButton1Down:Connect(function() if panelOpen then ClosePanel() else OpenPanel() end end)
ShopClose.MouseButton1Down:Connect(ClosePanel)

BoostUpdated.OnClientEvent:Connect(function(state)
	if state._goldenAuras ~= nil then liveGold = state._goldenAuras; state._goldenAuras = nil end
	boostState = state; RefreshStrip()
	if panelOpen then RefreshCards() end
end)

UpdateHUD.OnClientEvent:Connect(function(stats)
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

-- ✨ TUTORIAL OVERRIDE: Close shop when camera pans
local forceClose = ReplicatedStorage:FindFirstChild("ForceCloseUI") or Instance.new("BindableEvent")
forceClose.Name = "ForceCloseUI"
forceClose.Parent = ReplicatedStorage
forceClose.Event:Connect(function()
	if panelOpen then ClosePanel() end
end)

-- AchievementController
-- Location: StarterPlayer > StarterPlayerScripts > AchievementController

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local UITheme           = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UITheme"))
local T                 = UITheme.Get("Custom")
local SoundConfig       = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SoundConfig"))
local AchievementConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("AchievementConfig"))
local TierConfig        = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("TierConfig"))
local UpdateHUD         = ReplicatedStorage.RemoteEvents:WaitForChild("UpdateHUD")
local AuraDiscovered    = ReplicatedStorage:WaitForChild("RemoteEvents"):WaitForChild("AuraDiscovered", 5)

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainHUD   = playerGui:WaitForChild("MainHUD")
local Faded2 = mainHUD:WaitForChild("Faded2") 
local panelOpen = false
local activeTab = "Challenges"
local activeTabText = "Boosts" 
local latestStats = {}

local function PlayUI(id) if shared.PlayUISound then shared.PlayUISound(id) end end

---------------------------------------------------------------
-- ✨ ROADMAP INTEGRATION: Area -> Rarity Names & Icons
---------------------------------------------------------------
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

-- ✨ ADDED: Icon library for every single aura! Paste your image IDs here.
local AreaAuraIcons = {
	[1] = {"rbxassetid://0", "rbxassetid://0", "rbxassetid://0", "rbxassetid://0", "rbxassetid://0"},
	[2] = {"rbxassetid://0", "rbxassetid://0", "rbxassetid://0", "rbxassetid://0", "rbxassetid://0"},
	[3] = {"rbxassetid://0", "rbxassetid://0", "rbxassetid://0", "rbxassetid://0", "rbxassetid://0"},
	[4] = {"rbxassetid://0", "rbxassetid://0", "rbxassetid://0", "rbxassetid://0", "rbxassetid://0"},
	[5] = {"rbxassetid://0", "rbxassetid://0", "rbxassetid://0", "rbxassetid://0", "rbxassetid://0"},
	[6] = {"rbxassetid://0", "rbxassetid://0", "rbxassetid://0", "rbxassetid://0", "rbxassetid://0"},
	[7] = {"rbxassetid://0", "rbxassetid://0", "rbxassetid://0", "rbxassetid://0", "rbxassetid://0"},
	[8] = {"rbxassetid://0", "rbxassetid://0", "rbxassetid://0", "rbxassetid://0", "rbxassetid://0"},
	[9] = {"rbxassetid://0", "rbxassetid://0", "rbxassetid://0", "rbxassetid://0", "rbxassetid://0"},
	[10] = {"rbxassetid://0", "rbxassetid://0", "rbxassetid://0", "rbxassetid://0", "rbxassetid://0"},
	[11] = {"rbxassetid://0", "rbxassetid://0", "rbxassetid://0", "rbxassetid://0", "rbxassetid://0"},
	[12] = {"rbxassetid://0", "rbxassetid://0", "rbxassetid://0", "rbxassetid://0", "rbxassetid://0"},
	[13] = {"rbxassetid://0", "rbxassetid://0", "rbxassetid://0", "rbxassetid://0", "rbxassetid://0"},
	[14] = {"rbxassetid://0", "rbxassetid://0", "rbxassetid://0", "rbxassetid://0", "rbxassetid://0"},
	[15] = {"rbxassetid://0", "rbxassetid://0", "rbxassetid://0", "rbxassetid://0", "rbxassetid://0"},
	[16] = {"rbxassetid://0", "rbxassetid://0", "rbxassetid://0", "rbxassetid://0", "rbxassetid://0"},
	[17] = {"rbxassetid://0", "rbxassetid://0", "rbxassetid://0", "rbxassetid://0", "rbxassetid://0"},
	[18] = {"rbxassetid://0", "rbxassetid://0", "rbxassetid://0", "rbxassetid://0", "rbxassetid://0"},
	[19] = {"rbxassetid://0", "rbxassetid://0", "rbxassetid://0", "rbxassetid://0", "rbxassetid://0"},
	[20] = {"rbxassetid://0", "rbxassetid://0", "rbxassetid://0", "rbxassetid://0", "rbxassetid://0"}
}

---------------------------------------------------------------
-- 1. THE CIRCULAR BUTTON
---------------------------------------------------------------
local AchieveBtn = Instance.new("ImageButton", Faded2) 
AchieveBtn.Name = "AchievementButton"
AchieveBtn.Size = UDim2.new(0.85, 0, 0.85, 0) 
AchieveBtn.Position = UDim2.new(0.95, 0, 0.5, 0) 
AchieveBtn.AnchorPoint = Vector2.new(1, 0.5) 
AchieveBtn.BackgroundColor3 = T.buttonSecondary
AchieveBtn.BorderSizePixel = 0
AchieveBtn.AutoButtonColor = false
AchieveBtn.ZIndex = 15
Instance.new("UICorner", AchieveBtn).CornerRadius = UDim.new(0.5, 0)

local achieveAspect = Instance.new("UIAspectRatioConstraint", AchieveBtn)
achieveAspect.AspectRatio = 1.0 

local btnStroke = Instance.new("UIStroke", AchieveBtn)
btnStroke.Color = T.accentGold; btnStroke.Thickness = 1

local btnIcon = Instance.new("ImageLabel", AchieveBtn)
btnIcon.Size = UDim2.new(0.7, 0, 0.7, 0)
btnIcon.Position = UDim2.new(0.15, 0, 0.15, 0)
btnIcon.BackgroundTransparency = 1; btnIcon.ScaleType = Enum.ScaleType.Fit
btnIcon.Image = "rbxassetid://14916846070"

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
local TitleLabel = Instance.new("TextLabel", Header); TitleLabel.Size = UDim2.new(1, -50, 1, 0); TitleLabel.Position = UDim2.new(0, 14, 0, 0); TitleLabel.BackgroundTransparency = 1; TitleLabel.Text = "PROGRESSION"; TitleLabel.TextColor3 = T.headerText; TitleLabel.TextScaled = true; TitleLabel.Font = T.font; TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
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
TabListLayout.FillDirection = Enum.FillDirection.Horizontal; TabListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center; TabListLayout.VerticalAlignment = Enum.VerticalAlignment.Center; TabListLayout.Padding = UDim.new(0, 20)

local tabBtns = {}; local scrolls = {}

local function MakeTab(name, hoverText, iconId)
	local btn = Instance.new("ImageButton", TabButtonFrame)
	btn.Size = UDim2.new(0, 45, 0, 45); btn.BackgroundColor3 = T.buttonSecondary; btn.AutoButtonColor = false
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0.5, 0)
	btn:SetAttribute("TutorialTarget", name .. "Tab")

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
	end)
end

MakeTab("Challenges", "Boosts", "rbxassetid://14916846070")
MakeTab("Index", "Auras", "rbxassetid://14916846070")
MakeTab("Badges", "Badges", "rbxassetid://14916846070")
MakeTab("Leaderboard", "Top 10", "rbxassetid://14916846070")

---------------------------------------------------------------
-- 4. DYNAMIC CONTENT BUILDER
---------------------------------------------------------------
local function UpdateOrCreateRow(parent, id, title, titleColor, desc, hoverDesc, iconImage, iconColor, statusText, statusColor)
	local row = parent:FindFirstChild(id)

	if not row then
		row = Instance.new("TextButton", parent)
		row.Name = id; row.Text = ""; row.AutoButtonColor = false
		row.Size = UDim2.new(1, -8, 0, 64); row.BackgroundColor3 = T.cardBG
		Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)

		local stroke = Instance.new("UIStroke", row); stroke.Name = "Stroke"; stroke.Thickness = 1

		local icon = Instance.new("ImageLabel", row); icon.Name = "Icon"; icon.Size = UDim2.new(0, 40, 0, 40); icon.Position = UDim2.new(0, 12, 0.5, -20); icon.ScaleType = Enum.ScaleType.Fit; Instance.new("UICorner", icon).CornerRadius = UDim.new(1, 0)

		local tLbl = Instance.new("TextLabel", row); tLbl.Name = "Title"; tLbl.Size = UDim2.new(0.6, 0, 0, 20); tLbl.Position = UDim2.new(0, 64, 0, 10); tLbl.BackgroundTransparency = 1; tLbl.TextColor3 = T.bodyText; tLbl.TextScaled = true; tLbl.Font = T.font; tLbl.TextXAlignment = Enum.TextXAlignment.Left
		local dLbl = Instance.new("TextLabel", row); dLbl.Name = "Desc"; dLbl.Size = UDim2.new(0.6, 0, 0, 16); dLbl.Position = UDim2.new(0, 64, 0, 32); dLbl.BackgroundTransparency = 1; tLbl.TextColor3 = T.subText; dLbl.TextScaled = true; dLbl.Font = T.fontBody; dLbl.TextXAlignment = Enum.TextXAlignment.Left
		local sLbl = Instance.new("TextLabel", row); sLbl.Name = "Status"; sLbl.Size = UDim2.new(0, 80, 0, 24); sLbl.Position = UDim2.new(1, -90, 0.5, -12); sLbl.BackgroundTransparency = 1; sLbl.TextScaled = true; sLbl.Font = T.font; sLbl.TextXAlignment = Enum.TextXAlignment.Right

		UITheme.Apply(row, "Card")

		row:SetAttribute("IsHovering", false)
		row.MouseEnter:Connect(function() 
			row:SetAttribute("IsHovering", true)
			local hd = row:GetAttribute("HoverDesc")
			if hd and hd ~= "" then
				row.Desc.Text = hd; row.Desc.TextColor3 = T.accentGold
			end
		end)
		row.MouseLeave:Connect(function() 
			row:SetAttribute("IsHovering", false)
			row.Desc.Text = row:GetAttribute("NormalDesc") or ""; row.Desc.TextColor3 = T.subText 
		end)
	end

	row:SetAttribute("NormalDesc", desc)
	row:SetAttribute("HoverDesc", hoverDesc)

	row.Title.Text = title
	row.Title.TextColor3 = titleColor or T.bodyText 
	row.Status.Text = statusText
	row.Status.TextColor3 = statusColor
	row.Icon.Image = iconImage
	row.Icon.BackgroundColor3 = iconColor
	row.Stroke.Color = iconColor

	if row:GetAttribute("IsHovering") and hoverDesc and hoverDesc ~= "" then
		row.Desc.Text = hoverDesc; row.Desc.TextColor3 = T.accentGold
	else
		row.Desc.Text = desc; row.Desc.TextColor3 = T.subText
	end
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

	-- ✨ DYNAMIC INDEX UPDATE: All 100 Auras across all Areas!
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

			-- ✨ STRICT DISCOVERY: Only relies on the server's tracked history! No auto-unlocking.
			local discovered = discoveredTiers[aIdx .. "_" .. tier.name] == true

			local statusText = discovered and "Found" or "???"
			local statusColor = discovered and T.buttonGreen or T.buttonRed

			-- ✨ Black out the colors if it hasn't been discovered yet
			local auraTitleColor = discovered and tier.color or Color3.fromRGB(100, 100, 100)
			local iconColor = discovered and tier.color or Color3.fromRGB(50, 50, 50)
			local iconImg = (discovered and areaIcons and areaIcons[tIdx]) and areaIcons[tIdx] or "rbxassetid://0"

			-- Replaced multiplier text with the Area location
			UpdateOrCreateRow(scrolls["Index"], "Index_"..indexCount, auraTitle, auraTitleColor, "Area " .. aIdx, nil, iconImg, iconColor, statusText, statusColor)
			indexCount += 1
		end
	end

	for i, badge in ipairs(AchievementConfig.Badges) do
		UpdateOrCreateRow(scrolls["Badges"], "Badge_"..i, badge.title, T.bodyText, badge.desc, nil, badge.iconId, T.accentGold, "BADGE", T.subText)
	end

	UpdateOrCreateRow(scrolls["Leaderboard"], "Leader_1", "1. MoldySugar2205", T.bodyText, "Total Earnings", nil, "rbxassetid://0", T.accentGold, "Top Player", T.accentGreen)
end

UpdateHUD.OnClientEvent:Connect(function(stats)
	for key, value in pairs(stats) do latestStats[key] = value end
	if panelOpen then RefreshData() end
end)

---------------------------------------------------------------
-- ✨ 5. DISCOVERY BANNER SYSTEM
---------------------------------------------------------------
local bannerQueue = {}
local isShowingDiscovery = false

local function ShowNextDiscovery()
	if isShowingDiscovery or #bannerQueue == 0 then return end
	isShowingDiscovery = true
	local info = table.remove(bannerQueue, 1)

	PlayUI(SoundConfig.UIOpen or "") 

	local banner = Instance.new("Frame")
	banner.Size = UDim2.new(0, 260, 0, 70)
	banner.Position = UDim2.new(0, -300, 0.4, 0) -- Starts offscreen left
	banner.BackgroundColor3 = T.panelBG
	banner.BorderSizePixel = 0
	banner.ZIndex = 100
	Instance.new("UICorner", banner).CornerRadius = UDim.new(0, 8)

	local stroke = Instance.new("UIStroke", banner)
	stroke.Color = info.color
	stroke.Thickness = 2

	local icon = Instance.new("ImageLabel", banner)
	icon.Size = UDim2.new(0, 50, 0, 50)
	icon.Position = UDim2.new(0, 10, 0.5, -25)
	icon.BackgroundTransparency = 1
	icon.Image = "rbxassetid://14916846070" 
	icon.ImageColor3 = info.color

	local title = Instance.new("TextLabel", banner)
	title.Size = UDim2.new(1, -70, 0, 20)
	title.Position = UDim2.new(0, 70, 0, 12)
	title.BackgroundTransparency = 1
	title.Text = "NEW AURA UNLOCKED!"
	title.TextColor3 = T.subText
	title.Font = T.fontBody
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left

	local nameLbl = Instance.new("TextLabel", banner)
	nameLbl.Size = UDim2.new(1, -70, 0, 24)
	nameLbl.Position = UDim2.new(0, 70, 0, 34)
	nameLbl.BackgroundTransparency = 1
	-- ✨ Matches the exact roadmap name
	nameLbl.Text = string.upper(info.actualName or info.name) .. " AURA"
	nameLbl.TextColor3 = info.color
	nameLbl.Font = T.font
	nameLbl.TextScaled = true
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left

	banner.Parent = mainHUD

	-- Slide IN
	TweenService:Create(banner, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Position = UDim2.new(0, 20, 0.4, 0)}):Play()

	-- Wait 4 seconds, then Slide OUT
	task.delay(4, function()
		TweenService:Create(banner, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Position = UDim2.new(0, -300, 0.4, 0)}):Play()
		task.delay(0.5, function()
			if banner.Parent then banner:Destroy() end
			isShowingDiscovery = false
			ShowNextDiscovery() 
		end)
	end)
end

if AuraDiscovered then
	AuraDiscovered.OnClientEvent:Connect(function(discoveries)
		for _, d in ipairs(discoveries) do
			local areaNames = AreaAuraNames[d.area] or AreaAuraNames[1]
			local tierIndex = 1
			for i, t in ipairs(TierConfig.Tiers) do
				if t.name == d.name then tierIndex = i; break end
			end

			-- Only queue up discoveries for the 5 physical auras per area
			if tierIndex <= 5 then
				d.actualName = areaNames[tierIndex]
				table.insert(bannerQueue, d)
			end
		end
		ShowNextDiscovery()
	end)
end

---------------------------------------------------------------
-- 6. BUTTON JUICE & OPEN/CLOSE
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

AchieveBtn.MouseButton1Down:Connect(function()
	if panelOpen then
		PlayUI(SoundConfig.UIClose or "")
		panelOpen = false
		TweenService:Create(Panel, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Size = UDim2.new(0.85, 0, 0, 0)}):Play()
		UITheme.SetMenuVisible(false)
		task.delay(0.25, function() Panel.Visible = false end)
	else
		PlayUI(SoundConfig.UIOpen or "")
		panelOpen = true; Panel.Visible = true; Panel.Size = UDim2.new(0.85, 0, 0, 0)

		for k, t in pairs(tabBtns) do 
			t.btn.BackgroundColor3 = (k == activeTab) and T.accentGold or T.buttonSecondary 
			t.stroke.Color = (k == activeTab) and T.bodyText or T.panelStroke
		end
		scrolls[activeTab].Visible = true
		HoverLabel.Text = activeTabText
		RefreshData()

		TweenService:Create(Panel, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = UDim2.new(0.85, 0, 0.75, 0)}):Play()
		UITheme.SetMenuVisible(true)
	end
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
