-- BoostController
-- Location: StarterPlayer > StarterPlayerScripts > BoostController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local AdminConfig = require(ReplicatedStorage.Modules.AdminConfig)
local SoundConfig = require(ReplicatedStorage.Modules.SoundConfig)
local BoostConfig = require(ReplicatedStorage.Modules.BoostConfig) 
local AchievementConfig = require(ReplicatedStorage.Modules.AchievementConfig)
local UITheme = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UITheme"))
local T = UITheme.Get("Custom")

local BuyBoost = ReplicatedStorage.RemoteEvents:WaitForChild("BuyBoost")
local ActivateBoost = ReplicatedStorage.RemoteEvents:WaitForChild("ActivateBoost")
local BoostUpdated = ReplicatedStorage.RemoteEvents:WaitForChild("BoostUpdated")
local BridgeNet2 = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))
local UpdateHUDBridge = BridgeNet2.ClientBridge("UpdateHUD")

local player = Players.LocalPlayer
local mainHUD = player:WaitForChild("PlayerGui"):WaitForChild("MainHUD")

local boostState = {}; local panelOpen = false; local liveGold = 0; local latestStats = {}
local activeTab = "Shop"

local function PlayUI(id) if shared.PlayUISound then shared.PlayUISound(id) end end
local function FormatTime(s) s = math.ceil(s or 0); if s <= 0 then return "0:00" end; return string.format("%d:%02d", math.floor(s/60), s % 60) end

---------------------------------------------------------------
-- ✨ MENU BUTTON
---------------------------------------------------------------
local BoostsBtn = Instance.new("ImageButton"); BoostsBtn.Name = "BoostsButton"; BoostsBtn.BackgroundColor3 = T.buttonPrimary; BoostsBtn.BorderSizePixel = 0; BoostsBtn.AutoButtonColor = false; BoostsBtn.ZIndex = 10
local Faded2 = mainHUD:FindFirstChild("Faded2")
if Faded2 then BoostsBtn.Parent = Faded2; BoostsBtn.Size = UDim2.new(0.85, 0, 0.85, 0); Instance.new("UIAspectRatioConstraint", BoostsBtn).AspectRatio = 1.0; local layout = Faded2:FindFirstChildOfClass("UIListLayout"); if not layout then layout = Instance.new("UIListLayout", Faded2); layout.HorizontalAlignment = Enum.HorizontalAlignment.Center; layout.VerticalAlignment = Enum.VerticalAlignment.Center; layout.Padding = UDim.new(0, 15); layout.SortOrder = Enum.SortOrder.LayoutOrder end; BoostsBtn.LayoutOrder = 3 
else BoostsBtn.Size = UDim2.new(0, 60, 0, 60); BoostsBtn.AnchorPoint = Vector2.new(1, 1); BoostsBtn.Position = UDim2.new(0.98, 0, 0.77, 0); BoostsBtn.Parent = mainHUD end
BoostsBtn:SetAttribute("TutorialTarget", "BoostsButton"); Instance.new("UICorner", BoostsBtn).CornerRadius = UDim.new(0.5, 0)
local bbStroke = Instance.new("UIStroke", BoostsBtn); bbStroke.Color = T.accentPurple; bbStroke.Thickness = 2
local boostIcon = Instance.new("ImageLabel", BoostsBtn); boostIcon.Size = UDim2.new(0.6, 0, 0.6, 0); boostIcon.Position = UDim2.new(0.2, 0, 0.2, 0); boostIcon.BackgroundTransparency = 1; boostIcon.ScaleType = Enum.ScaleType.Fit; boostIcon.Image = "rbxassetid://14916846070" 
CollectionService:AddTag(BoostsBtn, "Tutorial_BoostMenuBtn")

---------------------------------------------------------------
-- ✨ SHOP PANEL & TABS (Strictly Docked & Capped)
---------------------------------------------------------------
local ShopPanel = Instance.new("Frame"); ShopPanel.Name = "BoostShopPanel"
ShopPanel.Size = UDim2.new(0.9, 0, 0.60, 0) 
ShopPanel.AnchorPoint = Vector2.new(1, 1)
ShopPanel.Position = UDim2.new(1, -15, 2, 0) 
ShopPanel.BackgroundColor3 = T.panelBG; ShopPanel.BorderSizePixel = 0; ShopPanel.Visible = false; ShopPanel.ZIndex = 40; ShopPanel.ClipsDescendants = true; ShopPanel.Parent = mainHUD
CollectionService:AddTag(ShopPanel, "Tutorial_BoostShopPanel")
Instance.new("UICorner", ShopPanel).CornerRadius = UDim.new(0, 12)

Instance.new("UISizeConstraint", ShopPanel).MaxSize = Vector2.new(360, 440) 

local shopStroke = Instance.new("UIStroke", ShopPanel); shopStroke.Color = Color3.fromRGB(255, 255, 255); shopStroke.Thickness = 1.5 

local ShopHeader = Instance.new("Frame"); ShopHeader.Name = "TitleBar"; ShopHeader.Size = UDim2.new(1, 0, 0, 40); ShopHeader.BackgroundColor3 = T.headerBG; ShopHeader.BorderSizePixel = 0; ShopHeader.ZIndex = 41; ShopHeader.Parent = ShopPanel; Instance.new("UICorner", ShopHeader).CornerRadius = UDim.new(0, 12)
local ShopTitle = Instance.new("TextLabel"); ShopTitle.Size = UDim2.new(1, -50, 1, 0); ShopTitle.Position = UDim2.new(0, 14, 0, 0); ShopTitle.BackgroundTransparency = 1; ShopTitle.Text = "BOOSTS"; ShopTitle.TextColor3 = T.headerText; ShopTitle.TextScaled = true; ShopTitle.Font = T.font; ShopTitle.TextXAlignment = Enum.TextXAlignment.Left; ShopTitle.ZIndex = 42; ShopTitle.Parent = ShopHeader
local ShopClose = Instance.new("TextButton"); ShopClose.Size = UDim2.new(0, 28, 0, 28); ShopClose.Position = UDim2.new(1, -36, 0.5, -14); ShopClose.BackgroundColor3 = T.buttonRed; ShopClose.BorderSizePixel = 0; ShopClose.Text = "X"; ShopClose.TextColor3 = Color3.fromRGB(255, 255, 255); ShopClose.TextScaled = true; ShopClose.Font = T.font; ShopClose.ZIndex = 9999; ShopClose.Parent = ShopHeader
CollectionService:AddTag(ShopClose, "Tutorial_BoostShopClose"); Instance.new("UICorner", ShopClose).CornerRadius = UDim.new(0, 5)

local TabContainer = Instance.new("Frame", ShopPanel)
TabContainer.Size = UDim2.new(1, 0, 0, 40); TabContainer.Position = UDim2.new(0, 0, 0, 40); TabContainer.BackgroundColor3 = T.headerBG; TabContainer.BorderSizePixel = 0; TabContainer.ZIndex = 41
local TabListLayout = Instance.new("UIListLayout", TabContainer); TabListLayout.FillDirection = Enum.FillDirection.Horizontal; TabListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center; TabListLayout.VerticalAlignment = Enum.VerticalAlignment.Center; TabListLayout.Padding = UDim.new(0, 10)

local shopTabBtn = Instance.new("TextButton", TabContainer); shopTabBtn.Size = UDim2.new(0.45, 0, 0.7, 0); shopTabBtn.BackgroundColor3 = T.buttonSecondary; shopTabBtn.Text = "SHOP"; shopTabBtn.TextColor3 = T.bodyText; shopTabBtn.Font = T.font; shopTabBtn.TextScaled = true; Instance.new("UICorner", shopTabBtn).CornerRadius = UDim.new(0, 6)
local invTabBtn = Instance.new("TextButton", TabContainer); invTabBtn.Size = UDim2.new(0.45, 0, 0.7, 0); invTabBtn.BackgroundColor3 = T.buttonSecondary; invTabBtn.Text = "INVENTORY"; invTabBtn.TextColor3 = T.bodyText; invTabBtn.Font = T.font; invTabBtn.TextScaled = true; Instance.new("UICorner", invTabBtn).CornerRadius = UDim.new(0, 6)

CollectionService:AddTag(shopTabBtn, "Tutorial_BoostTab_Shop")
CollectionService:AddTag(invTabBtn, "Tutorial_BoostTab_Inventory")

local ShopScroll = Instance.new("ScrollingFrame", ShopPanel); ShopScroll.Name = "ShopScroll"; ShopScroll.Size = UDim2.new(1, 0, 1, -80); ShopScroll.Position = UDim2.new(0, 0, 0, 80); ShopScroll.BackgroundTransparency = 1; ShopScroll.BorderSizePixel = 0; ShopScroll.ScrollBarThickness = 6; ShopScroll.Visible = true; Instance.new("UIListLayout", ShopScroll).Padding = UDim.new(0, 8); local spad = Instance.new("UIPadding", ShopScroll); spad.PaddingTop = UDim.new(0,8); spad.PaddingLeft = UDim.new(0,8); spad.PaddingRight = UDim.new(0,8)
local InvScroll = Instance.new("ScrollingFrame", ShopPanel); InvScroll.Name = "InvScroll"; InvScroll.Size = UDim2.new(1, 0, 1, -80); InvScroll.Position = UDim2.new(0, 0, 0, 80); InvScroll.BackgroundTransparency = 1; InvScroll.BorderSizePixel = 0; InvScroll.ScrollBarThickness = 6; InvScroll.Visible = false; Instance.new("UIListLayout", InvScroll).Padding = UDim.new(0, 8); local ipad = Instance.new("UIPadding", InvScroll); ipad.PaddingTop = UDim.new(0,8); ipad.PaddingLeft = UDim.new(0,8); ipad.PaddingRight = UDim.new(0,8)

local function AddButtonJuice(btn)
	local scale = btn:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", btn)
	btn.MouseEnter:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15), {Scale = 1.05}):Play() end)
	btn.MouseLeave:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15), {Scale = 1}):Play() end)
	btn.MouseButton1Down:Connect(function() TweenService:Create(scale, TweenInfo.new(0.1), {Scale = 0.95}):Play() end)
	btn.MouseButton1Up:Connect(function() TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), {Scale = 1.05}):Play() end)
end
AddButtonJuice(BoostsBtn); AddButtonJuice(ShopClose); AddButtonJuice(shopTabBtn); AddButtonJuice(invTabBtn)

local function SetActiveTab(tabName)
	activeTab = tabName
	if tabName == "Shop" then
		shopTabBtn.BackgroundColor3 = T.buttonPrimary; shopTabBtn.TextColor3 = T.bodyText
		invTabBtn.BackgroundColor3 = T.buttonSecondary; invTabBtn.TextColor3 = T.subText
		ShopScroll.Visible = true; InvScroll.Visible = false
	else
		shopTabBtn.BackgroundColor3 = T.buttonSecondary; shopTabBtn.TextColor3 = T.subText
		invTabBtn.BackgroundColor3 = T.buttonPrimary; invTabBtn.TextColor3 = T.bodyText
		ShopScroll.Visible = false; InvScroll.Visible = true
	end
end
SetActiveTab("Shop") 

shopTabBtn.MouseButton1Down:Connect(function()
	if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_BoostTab_Shop") then return end
	PlayUI(SoundConfig.UIClick or ""); SetActiveTab("Shop")
	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
end)
invTabBtn.MouseButton1Down:Connect(function()
	if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_BoostTab_Inventory") then return end
	PlayUI(SoundConfig.UIClick or ""); SetActiveTab("Inventory")
	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
end)

local cardRefs = {}

local function BuildCards()
	for i, boostId in ipairs(BoostConfig.ShopOrder) do
		local cfg = BoostConfig.Get(boostId); if not cfg then continue end; local color = cfg.color

		local sCard = Instance.new("Frame", ShopScroll); sCard.Size = UDim2.new(1, -8, 0, 75); sCard.BackgroundColor3 = T.cardBG; sCard.BorderSizePixel = 0; Instance.new("UICorner", sCard).CornerRadius = UDim.new(0, 8)
		local sIcon = Instance.new("ImageLabel", sCard); sIcon.Size = UDim2.new(0, 36, 0, 36); sIcon.Position = UDim2.new(0, 10, 0.5, -18); sIcon.BackgroundTransparency = 1; sIcon.Image = cfg.icon or ""; sIcon.ImageColor3 = color; sIcon.ScaleType = Enum.ScaleType.Fit

		-- ✨ Scale fixes implemented here!
		local sName = Instance.new("TextLabel", sCard); sName.Size = UDim2.new(0.55, -10, 0, 18); sName.Position = UDim2.new(0, 56, 0, 10); sName.BackgroundTransparency = 1; sName.Text = string.upper(cfg.displayName or boostId); sName.TextColor3 = T.bodyText; sName.TextScaled = true; sName.Font = T.font; sName.TextXAlignment = Enum.TextXAlignment.Left
		local sDesc = Instance.new("TextLabel", sCard); sDesc.Size = UDim2.new(0.55, -10, 0, 30); sDesc.Position = UDim2.new(0, 56, 0, 30); sDesc.BackgroundTransparency = 1; sDesc.Text = cfg.description or ""; sDesc.TextColor3 = T.subText; sDesc.TextScaled = true; sDesc.TextWrapped = true; sDesc.Font = T.fontBody; sDesc.TextXAlignment = Enum.TextXAlignment.Left; sDesc.TextYAlignment = Enum.TextYAlignment.Top

		local buyBtn = Instance.new("TextButton", sCard); buyBtn.Size = UDim2.new(0, 75, 0, 34); buyBtn.Position = UDim2.new(1, -85, 0.5, -17); buyBtn.BackgroundColor3 = T.buttonGreen; buyBtn.BorderSizePixel = 0; buyBtn.TextScaled = true; buyBtn.Font = T.font; buyBtn.TextColor3 = Color3.fromRGB(255, 255, 255); Instance.new("UICorner", buyBtn).CornerRadius = UDim.new(0, 6); CollectionService:AddTag(buyBtn, "Tutorial_BuyBoost_" .. boostId); AddButtonJuice(buyBtn)

		local iCard = Instance.new("Frame", InvScroll); iCard.Size = UDim2.new(1, -8, 0, 75); iCard.BackgroundColor3 = T.cardBG; iCard.BorderSizePixel = 0; Instance.new("UICorner", iCard).CornerRadius = UDim.new(0, 8)
		local iIcon = Instance.new("ImageLabel", iCard); iIcon.Size = UDim2.new(0, 36, 0, 36); iIcon.Position = UDim2.new(0, 10, 0.5, -18); iIcon.BackgroundTransparency = 1; iIcon.Image = cfg.icon or ""; iIcon.ImageColor3 = color; iIcon.ScaleType = Enum.ScaleType.Fit
		local iName = Instance.new("TextLabel", iCard); iName.Size = UDim2.new(0.5, 0, 0, 18); iName.Position = UDim2.new(0, 56, 0, 10); iName.BackgroundTransparency = 1; iName.Text = string.upper(cfg.displayName or boostId); iName.TextColor3 = T.bodyText; iName.TextScaled = true; iName.Font = T.font; iName.TextXAlignment = Enum.TextXAlignment.Left

		local iOwned = Instance.new("TextLabel", iCard); iOwned.Size = UDim2.new(0.5, 0, 0, 14); iOwned.Position = UDim2.new(0, 56, 0, 30); iOwned.BackgroundTransparency = 1; iOwned.Text = "Owned: 0"; iOwned.TextColor3 = T.accentGold; iOwned.TextScaled = true; iOwned.Font = T.fontBody; iOwned.TextXAlignment = Enum.TextXAlignment.Left
		local iStatus = Instance.new("TextLabel", iCard); iStatus.Size = UDim2.new(0.5, 0, 0, 14); iStatus.Position = UDim2.new(0, 56, 0, 46); iStatus.BackgroundTransparency = 1; iStatus.Text = "Inactive"; iStatus.TextColor3 = T.subText; iStatus.TextScaled = true; iStatus.Font = T.fontBody; iStatus.TextXAlignment = Enum.TextXAlignment.Left

		local iTimer = Instance.new("TextLabel", iCard); iTimer.Size = UDim2.new(0, 65, 0, 30); iTimer.Position = UDim2.new(1, -160, 0.5, -15); iTimer.BackgroundTransparency = 1; iTimer.Text = ""; iTimer.TextColor3 = color; iTimer.TextScaled = true; iTimer.Font = Enum.Font.FredokaOne; iTimer.TextXAlignment = Enum.TextXAlignment.Right

		local actBtn = Instance.new("TextButton", iCard); actBtn.Size = UDim2.new(0, 75, 0, 34); actBtn.Position = UDim2.new(1, -85, 0.5, -17); actBtn.BackgroundColor3 = color; actBtn.BorderSizePixel = 0; actBtn.TextScaled = true; actBtn.Font = T.font; actBtn.TextColor3 = Color3.fromRGB(255, 255, 255); Instance.new("UICorner", actBtn).CornerRadius = UDim.new(0, 6); CollectionService:AddTag(actBtn, "Tutorial_UseBoost_" .. boostId); AddButtonJuice(actBtn)

		cardRefs[boostId] = { sCard=sCard, iCard=iCard, buyBtn=buyBtn, actBtn=actBtn, sDesc=sDesc, iOwned=iOwned, iStatus=iStatus, iTimer=iTimer }

		buyBtn.MouseButton1Down:Connect(function() 
			if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_BuyBoost_" .. boostId) then return end
			local isUnlocked = AchievementConfig.IsBoostUnlocked(boostId, latestStats)
			local cost = cfg and cfg.cost or 0
			if not isUnlocked or liveGold < cost then PlayUI(SoundConfig.ErrorBuzz or ""); return end
			BuyBoost:FireServer(boostId) 
			if type(shared.TutorialRecordBoostBought) == "function" then shared.TutorialRecordBoostBought(boostId) end
			if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
		end)

		actBtn.MouseButton1Down:Connect(function()
			if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_UseBoost_" .. boostId) then return end
			local isUnlocked = AchievementConfig.IsBoostUnlocked(boostId, latestStats)
			local state = boostState[boostId]
			local activeCount = state and (state.activeCount or 0) or 0
			local atCap = activeCount >= (cfg and cfg.maxStack or 1)
			if not isUnlocked or not state or (state.inventoryCount or 0) <= 0 or atCap then PlayUI(SoundConfig.ErrorBuzz or ""); return end
			ActivateBoost:FireServer(boostId)
			if type(shared.TutorialRecordBoostUsed) == "function" then shared.TutorialRecordBoostUsed(boostId) end
			if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
		end)
	end
end

BuildCards()

local function RefreshCards()
	for boostId, refs in pairs(cardRefs) do
		local cfg = BoostConfig.Get(boostId); local state = boostState[boostId]
		local isUnlocked, lockReason = AchievementConfig.IsBoostUnlocked(boostId, latestStats)
		local cost = cfg and cfg.cost or 0; local canAfford = liveGold >= cost
		local invCount = state and (state.inventoryCount or 0) or 0

		if not isUnlocked then
			refs.buyBtn.Text = "LOCKED"; refs.buyBtn.BackgroundColor3 = T.buttonRed; refs.buyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
			refs.sDesc.Text = lockReason; refs.sDesc.TextColor3 = T.buttonRed
		else
			refs.sDesc.Text = cfg.description or ""; refs.sDesc.TextColor3 = T.subText
			refs.buyBtn.Text = cost .. " ⭐"; refs.buyBtn.TextColor3 = Color3.fromRGB(255, 255, 255); refs.buyBtn.BackgroundColor3 = canAfford and T.buttonGreen or T.buttonDisabled
		end

		refs.iOwned.Text = "Owned: " .. invCount
		refs.iOwned.TextColor3 = invCount > 0 and T.accentGold or T.subText
	end
end

local function OpenPanel()
	panelOpen = true; ShopPanel.Visible = true; RefreshCards()
	TweenService:Create(ShopPanel, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(1, -15, 1, -15) }):Play()
end

local function ClosePanel()
	panelOpen = false; PlayUI(SoundConfig.UIClose)
	local tween = TweenService:Create(ShopPanel, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.new(1, -15, 2, 0) })
	tween:Play(); tween.Completed:Once(function() if not panelOpen then ShopPanel.Visible = false end end)
end

BoostsBtn.MouseButton1Down:Connect(function() 
	if panelOpen then if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_CloseBoostShop") then return end; ClosePanel()
	else if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_OpenBoostShop") then return end; OpenPanel() end 
	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
end)
ShopClose.MouseButton1Down:Connect(function()
	if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_CloseBoostShop") then return end; ClosePanel()
	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
end)

BoostUpdated.OnClientEvent:Connect(function(state)
	if state._goldenAuras ~= nil then liveGold = state._goldenAuras; state._goldenAuras = nil end
	boostState = state; if panelOpen then RefreshCards() end
end)

UpdateHUDBridge:Connect(function(stats)
	for key, value in pairs(stats) do latestStats[key] = value end
	if stats.goldenAuras ~= nil then liveGold = stats.goldenAuras end
	if stats.boostInventory then for boostId, count in pairs(stats.boostInventory) do if boostState[boostId] then boostState[boostId].inventoryCount = count end end end
	if panelOpen then RefreshCards() end
end)

RunService.RenderStepped:Connect(function(dt)
	if panelOpen and type(shared.TutorialCanPerform) == "function" and shared.TutorialCanPerform("Action_OpenBoostShop") then
		if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
	end

	for _, boostId in ipairs(BoostConfig.ShopOrder) do
		local state = boostState[boostId]; local refs = cardRefs[boostId]; if not refs then continue end
		local activeCount, minTime = 0, 0

		if state and state.activeTimes and #state.activeTimes > 0 then
			local clean = {}; minTime = math.huge
			for _, t in ipairs(state.activeTimes) do
				local newT = math.max(0, t - dt)
				if newT > 0 then table.insert(clean, newT); if newT < minTime then minTime = newT end end
			end
			state.activeTimes = clean; state.activeCount = #clean; activeCount = #clean
		end

		local isUnlocked = AchievementConfig.IsBoostUnlocked(boostId, latestStats)
		if not isUnlocked then
			refs.actBtn.Text = "LOCKED"; refs.actBtn.BackgroundColor3 = T.buttonRed; refs.actBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
			refs.iStatus.Text = "Unlock in Progression Menu"; refs.iStatus.TextColor3 = T.buttonRed
			refs.iTimer.Text = ""
		else
			local invCount = state and (state.inventoryCount or 0) or 0
			local atCap = activeCount >= (BoostConfig.Get(boostId).maxStack or 1)

			if activeCount > 0 then 
				refs.iStatus.Text = "Active" .. (activeCount > 1 and (" (x"..activeCount..")") or "")
				refs.iStatus.TextColor3 = BoostConfig.Get(boostId).color
				refs.iTimer.Text = FormatTime(minTime)
			else 
				refs.iStatus.Text = "Inactive"
				refs.iStatus.TextColor3 = T.subText 
				refs.iTimer.Text = ""
			end

			if invCount <= 0 then 
				refs.actBtn.Text = "NO STOCK"; refs.actBtn.BackgroundColor3 = T.buttonDisabled; refs.actBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
			elseif atCap then 
				refs.actBtn.Text = "MAXED"; refs.actBtn.BackgroundColor3 = T.buttonDisabled; refs.actBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
			else 
				refs.actBtn.Text = "ACTIVATE"; refs.actBtn.BackgroundColor3 = BoostConfig.Get(boostId).color; refs.actBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
			end
		end
	end
end)

local shopShine    = nil
local titleFlair   = nil
local flairedExtra = false

local function RefreshLook()
	UITheme.Apply(ShopPanel, "Panel")
	UITheme.Apply(ShopHeader, "TitleBar")

	if not shopShine then
		shopShine  = UITheme.ApplyShine(ShopPanel)
		UITheme.ApplyShine(ShopHeader)
	end

	if not titleFlair then titleFlair = UITheme.ApplyFlair(ShopTitle, "Ghost") end
	if not flairedExtra then flairedExtra = true end

	for _, scrollName in ipairs({ "ShopScroll", "InvScroll" }) do
		local scroll = ShopPanel:FindFirstChild(scrollName)
		if scroll then
			local layout = scroll:FindFirstChildOfClass("UIListLayout")
			if layout then layout.SortOrder = Enum.SortOrder.LayoutOrder end
		end
	end

	local outerStroke = ShopPanel:FindFirstChildWhichIsA("UIStroke")
	if outerStroke then outerStroke.Color = Color3.fromRGB(255, 255, 255) end

	for _, card in ipairs(ShopScroll:GetChildren()) do if card:IsA("Frame") then UITheme.Apply(card, "ShopCard") end end
	for _, card in ipairs(InvScroll:GetChildren()) do if card:IsA("Frame") then UITheme.Apply(card, "ShopCard") end end
end

task.wait(2)
RefreshLook()

local forceClose = ReplicatedStorage:FindFirstChild("ForceCloseUI") or Instance.new("BindableEvent")
forceClose.Name = "ForceCloseUI"; forceClose.Parent = ReplicatedStorage
forceClose.Event:Connect(function() if panelOpen then ClosePanel() end end)

-- AchievementController
-- Location: StarterPlayer > StarterPlayerScripts > AchievementController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local UITheme = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UITheme"))
local T = UITheme.Get("Custom")
local SoundConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SoundConfig"))
local AchievementConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("AchievementConfig"))
local TierConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("TierConfig"))
local Formatter = require(ReplicatedStorage.Modules.NumberFormatter)
local BridgeNet2 = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))
local UpdateHUDBridge = BridgeNet2.ClientBridge("UpdateHUD")

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local ClaimChallenge = RemoteEvents:WaitForChild("ClaimChallenge")
local ClaimAuraIndex = RemoteEvents:WaitForChild("ClaimAuraIndex")
local ClaimBadge = RemoteEvents:WaitForChild("ClaimBadge")
local AuraDiscovered = RemoteEvents:WaitForChild("AuraDiscovered", 5)

local SettingsChanged = ReplicatedStorage:FindFirstChild("SettingsChanged") or Instance.new("BindableEvent")
SettingsChanged.Name = "SettingsChanged"; SettingsChanged.Parent = ReplicatedStorage

local player = Players.LocalPlayer
local mainHUD = player:WaitForChild("PlayerGui"):WaitForChild("MainHUD")
local Faded2 = mainHUD:WaitForChild("Faded2") 

local panelOpen, activeTab, activeTabText = false, "Challenges", "Boosts"
local latestStats = {}
local sfxEnabled, musicEnabled, jumpEnabled = true, true, true 
local liveSoulAuras, liveRunEarnings, liveRate, livePrestiges = 0, 0, 0, 0
local toggleRefs, statValueRefs = {}, {}

local function PlayUI(id) if shared.PlayUISound then shared.PlayUISound(id) end end

local AreaAuraNames = { [1] = {"Gear", "Screw", "Tin Can", "Old Tire", "Intact Radio"}, [2] = {"Rusted Nail", "Scrap Pipe", "Bent Gear", "Engine Scrap", "Corroded Core"} }
for i=3,20 do AreaAuraNames[i] = {"Common", "Uncommon", "Rare", "Epic", "Legendary"} end

local function PlayClaimVFX(rowFrame)
	PlayUI(SoundConfig.MaxOut or "rbxassetid://4612385808")
	local flash = Instance.new("Frame", rowFrame); flash.Size = UDim2.new(1,0,1,0); flash.BackgroundColor3 = Color3.fromRGB(255, 255, 255); flash.ZIndex = 50; flash.BorderSizePixel = 0
	Instance.new("UICorner", flash).CornerRadius = UDim.new(0, 8)
	TweenService:Create(flash, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 1}):Play()
	task.delay(0.4, function() flash:Destroy() end)
	for i = 1, 8 do
		local particle = Instance.new("Frame", rowFrame); particle.Size = UDim2.new(0, 10, 0, 10); particle.BackgroundColor3 = T.accentGold; particle.AnchorPoint = Vector2.new(0.5, 0.5); particle.Position = UDim2.new(0.5, 0, 0.5, 0); particle.ZIndex = 51; Instance.new("UICorner", particle).CornerRadius = UDim.new(1, 0)
		local angle = math.rad(math.random(0, 360)); local dist = math.random(30, 80); local endPos = UDim2.new(0.5, math.cos(angle)*dist, 0.5, math.sin(angle)*dist)
		TweenService:Create(particle, TweenInfo.new(0.5, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), {Position = endPos, Size = UDim2.new(0,0,0,0), BackgroundTransparency = 1}):Play()
		task.delay(0.5, function() particle:Destroy() end)
	end
end

local AchieveBtn = Instance.new("ImageButton", Faded2); AchieveBtn.Name = "AchievementButton"; AchieveBtn.Size = UDim2.new(0.85, 0, 0.85, 0); AchieveBtn.BackgroundColor3 = T.buttonSecondary; AchieveBtn.BorderSizePixel = 0; AchieveBtn.LayoutOrder = 1; Instance.new("UICorner", AchieveBtn).CornerRadius = UDim.new(0.5, 0); Instance.new("UIAspectRatioConstraint", AchieveBtn).AspectRatio = 1.0; local btnStroke = Instance.new("UIStroke", AchieveBtn); btnStroke.Color = T.accentGold; btnStroke.Thickness = 1; local btnIcon = Instance.new("ImageLabel", AchieveBtn); btnIcon.Size = UDim2.new(0.7, 0, 0.7, 0); btnIcon.Position = UDim2.new(0.15, 0, 0.15, 0); btnIcon.BackgroundTransparency = 1; btnIcon.ScaleType = Enum.ScaleType.Fit; btnIcon.Image = "rbxassetid://14923131909"
CollectionService:AddTag(AchieveBtn, "Tutorial_AchieveMenuBtn")

local Panel = Instance.new("Frame", mainHUD); Panel.Name = "AchievementPanel"; Panel.Size = UDim2.new(0.85, 0, 0.75, 0); Panel.Position = UDim2.new(0.5, 0, 0.5, 0); Panel.AnchorPoint = Vector2.new(0.5, 0.5); Panel.BackgroundColor3 = T.panelBG; Panel.BorderSizePixel = 0; Panel.Visible = false; Panel.ZIndex = 40; Panel.ClipsDescendants = true; Instance.new("UICorner", Panel).CornerRadius = UDim.new(0, 12); Instance.new("UISizeConstraint", Panel).MaxSize = Vector2.new(500, 550); local panelStroke = Instance.new("UIStroke", Panel); panelStroke.Color = T.panelStroke; panelStroke.Thickness = 2
CollectionService:AddTag(Panel, "Tutorial_AchievePanel")

local Header = Instance.new("Frame", Panel); Header.Size = UDim2.new(1, 0, 0, 44); Header.BackgroundColor3 = T.headerBG; Header.BorderSizePixel = 0; Header.ZIndex = 41
local TitleLabel = Instance.new("TextLabel", Header); TitleLabel.Size = UDim2.new(1, -50, 1, 0); TitleLabel.Position = UDim2.new(0, 14, 0, 0); TitleLabel.BackgroundTransparency = 1; TitleLabel.Text = "MENU"; TitleLabel.TextColor3 = T.headerText; TitleLabel.TextScaled = true; TitleLabel.Font = T.font; TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
local CloseBtn = Instance.new("TextButton", Header); CloseBtn.Size = UDim2.new(0, 28, 0, 28); CloseBtn.Position = UDim2.new(1, -36, 0.5, -14); CloseBtn.BackgroundColor3 = T.buttonRed; CloseBtn.Text = "X"; CloseBtn.TextColor3 = T.headerText; CloseBtn.TextScaled = true; CloseBtn.Font = T.font; Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 5); CloseBtn.ZIndex = 9999
CollectionService:AddTag(CloseBtn, "Tutorial_AchieveCloseBtn")

local TabContainer = Instance.new("Frame", Panel); TabContainer.Size = UDim2.new(1, 0, 0, 75); TabContainer.Position = UDim2.new(0, 0, 0, 44); TabContainer.BackgroundTransparency = 1; TabContainer.ZIndex = 41
local HoverLabel = Instance.new("TextLabel", TabContainer); HoverLabel.Size = UDim2.new(1, 0, 0, 20); HoverLabel.Position = UDim2.new(0, 0, 1, -15); HoverLabel.BackgroundTransparency = 1; HoverLabel.Text = "Boosts"; HoverLabel.TextColor3 = T.bodyText; HoverLabel.TextScaled = true; HoverLabel.Font = T.font
local TabButtonFrame = Instance.new("Frame", TabContainer); TabButtonFrame.Size = UDim2.new(1, 0, 1, -20); TabButtonFrame.BackgroundTransparency = 1; local TabListLayout = Instance.new("UIListLayout", TabButtonFrame); TabListLayout.FillDirection = Enum.FillDirection.Horizontal; TabListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center; TabListLayout.VerticalAlignment = Enum.VerticalAlignment.Center; TabListLayout.Padding = UDim.new(0, 12)

local tabBtns, scrolls = {}, {}
local function MakeTab(name, hoverText, iconId)
	local btn = Instance.new("ImageButton", TabButtonFrame); btn.Size = UDim2.new(0, 45, 0, 45); btn.BackgroundColor3 = T.buttonSecondary; btn.AutoButtonColor = false; Instance.new("UICorner", btn).CornerRadius = UDim.new(0.5, 0); local tStroke = Instance.new("UIStroke", btn); tStroke.Color = T.panelStroke; tStroke.Thickness = 2; local icon = Instance.new("ImageLabel", btn); icon.Size = UDim2.new(0.6, 0, 0.6, 0); icon.Position = UDim2.new(0.2, 0, 0.2, 0); icon.BackgroundTransparency = 1; icon.ScaleType = Enum.ScaleType.Fit; icon.Image = iconId; tabBtns[name] = {btn = btn, stroke = tStroke}; CollectionService:AddTag(btn, "Tutorial_AchieveTab_" .. name)

	if name ~= "Leaderboard" then
		local sf = Instance.new("ScrollingFrame", Panel); sf.Size = UDim2.new(1, -20, 1, -135); sf.Position = UDim2.new(0, 10, 0, 125); sf.BackgroundTransparency = 1; sf.BorderSizePixel = 0; sf.ScrollBarThickness = 4; sf.Visible = false; local layout = Instance.new("UIListLayout", sf); layout.Padding = UDim.new(0, 8); layout.HorizontalAlignment = Enum.HorizontalAlignment.Center; layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function() sf.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 10) end); scrolls[name] = sf
	end

	btn.MouseEnter:Connect(function() HoverLabel.Text = hoverText end); btn.MouseLeave:Connect(function() HoverLabel.Text = activeTabText end)
	btn.MouseButton1Down:Connect(function()
		if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_ClickAchieveTab_" .. name) then return end
		PlayUI(SoundConfig.UIClick or ""); activeTab = name; activeTabText = hoverText; HoverLabel.Text = activeTabText
		for k, t in pairs(tabBtns) do t.btn.BackgroundColor3 = (k == name) and T.accentGold or T.buttonSecondary; t.stroke.Color = (k == name) and T.bodyText or T.panelStroke end
		for k, s in pairs(scrolls) do s.Visible = (k == name) end
		TitleLabel.Text = (name == "Settings") and "SETTINGS" or "PROGRESSION"
		if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
	end)
end

MakeTab("Challenges", "Boosts", "rbxassetid://14916846070"); MakeTab("Index", "Auras", "rbxassetid://14916846070"); MakeTab("Badges", "Badges", "rbxassetid://14916846070"); MakeTab("Leaderboard", "Leaderboard", "rbxassetid://14916846070"); MakeTab("Settings", "Settings", "rbxassetid://14923131909") 

local lbWrapper = Instance.new("Frame", Panel)
lbWrapper.Name = "LeaderboardWrapper"
lbWrapper.Size = UDim2.new(1, -20, 1, -135)
lbWrapper.Position = UDim2.new(0, 10, 0, 125)
lbWrapper.BackgroundTransparency = 1
lbWrapper.Visible = false
scrolls["Leaderboard"] = lbWrapper 

local lbSubTabContainer = Instance.new("Frame", lbWrapper)
lbSubTabContainer.Name = "SubTabContainer"
lbSubTabContainer.Size = UDim2.new(0, 55, 1, 0)
lbSubTabContainer.BackgroundTransparency = 1

local lbSubTabLayout = Instance.new("UIListLayout", lbSubTabContainer)
lbSubTabLayout.FillDirection = Enum.FillDirection.Vertical
lbSubTabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
lbSubTabLayout.VerticalAlignment = Enum.VerticalAlignment.Top
lbSubTabLayout.Padding = UDim.new(0, 15)

local lbScroll = Instance.new("ScrollingFrame", lbWrapper)
lbScroll.Size = UDim2.new(1, -65, 1, 0)
lbScroll.Position = UDim2.new(0, 65, 0, 0)
lbScroll.BackgroundTransparency = 1
lbScroll.BorderSizePixel = 0
lbScroll.ScrollBarThickness = 4

local lbContentLayout = Instance.new("UIListLayout", lbScroll)
lbContentLayout.Padding = UDim.new(0, 8)
lbContentLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

lbContentLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	lbScroll.CanvasSize = UDim2.new(0, 0, 0, lbContentLayout.AbsoluteContentSize.Y + 10)
end)

local activeLbTab = "Auras Generated"
local lbSubBtns = {}

local function BuildLeaderboardRows(tabName)
	for _, child in ipairs(lbScroll:GetChildren()) do if child:IsA("Frame") then child:Destroy() end end

	local data = {}
	if tabName == "Top 10" then
		data = { {rank=1, name="MoldySugar2205", val="999.9M Soul Auras"}, {rank=2, name="MoldySugar2205", val="50.2M Soul Auras"}, {rank=3, name="MoldySugar2205", val="10.5M Soul Auras"}, {rank=4, name="MoldySugar2205", val="5.1M Soul Auras"}, {rank=5, name="MoldySugar2205", val="2.0M Soul Auras"} }
	elseif tabName == "Auras Generated" then
		data = { {rank=1, name="MoldySugar2205", val="5.2B Auras"}, {rank=2, name="MoldySugar2205", val="1.1B Auras"}, {rank=3, name="MoldySugar2205", val="800M Auras"}, {rank=4, name="MoldySugar2205", val="500M Auras"}, {rank=5, name="MoldySugar2205", val="150M Auras"} }
	elseif tabName == "Most Money Made" then
		data = { {rank=1, name="MoldySugar2205", val="$999.9B"}, {rank=2, name="MoldySugar2205", val="$500.5B"}, {rank=3, name="MoldySugar2205", val="$150.0B"}, {rank=4, name="MoldySugar2205", val="$50.0B"}, {rank=5, name="MoldySugar2205", val="$10.0B"} }
	end

	for i, p in ipairs(data) do
		local row = Instance.new("Frame", lbScroll)
		row.Size = UDim2.new(1, 0, 0, 45)
		row.BackgroundColor3 = T.cardBG
		Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)

		local rankLbl = Instance.new("TextLabel", row)
		rankLbl.Size = UDim2.new(0, 40, 1, 0)
		rankLbl.Position = UDim2.new(0, 10, 0, 0)
		rankLbl.BackgroundTransparency = 1
		rankLbl.Text = "#" .. p.rank
		rankLbl.TextColor3 = (p.rank==1) and Color3.fromRGB(255,215,0) or ((p.rank==2) and Color3.fromRGB(192,192,192) or ((p.rank==3) and Color3.fromRGB(205,127,50) or T.subText))
		rankLbl.Font = Enum.Font.GothamBold
		rankLbl.TextScaled = true
		rankLbl.TextWrapped = true
		Instance.new("UITextSizeConstraint", rankLbl).MaxTextSize = 22

		local nameLbl = Instance.new("TextLabel", row)
		nameLbl.Size = UDim2.new(0.45, -50, 1, 0)
		nameLbl.Position = UDim2.new(0, 60, 0, 0)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Text = p.name
		nameLbl.TextColor3 = T.bodyText
		nameLbl.Font = Enum.Font.GothamMedium
		nameLbl.TextScaled = true
		nameLbl.TextWrapped = true
		nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		Instance.new("UITextSizeConstraint", nameLbl).MaxTextSize = 18

		local valLbl = Instance.new("TextLabel", row)
		valLbl.Size = UDim2.new(0.55, -20, 1, 0)
		valLbl.Position = UDim2.new(0.45, 10, 0, 0)
		valLbl.BackgroundTransparency = 1
		valLbl.Text = p.val
		valLbl.TextColor3 = T.accentGold
		valLbl.Font = Enum.Font.GothamBold
		valLbl.TextScaled = true
		valLbl.TextWrapped = true
		valLbl.TextXAlignment = Enum.TextXAlignment.Right
		Instance.new("UITextSizeConstraint", valLbl).MaxTextSize = 18

		UITheme.Apply(row, "Card")
	end
end

local function MakeLbSubTab(tabName, iconId)
	local btn = Instance.new("ImageButton", lbSubTabContainer)
	btn.Size = UDim2.new(0, 45, 0, 45)
	btn.BackgroundColor3 = (tabName == activeLbTab) and T.accentGold or T.buttonSecondary
	btn.AutoButtonColor = false
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0.5, 0)

	local tStroke = Instance.new("UIStroke", btn)
	tStroke.Color = (tabName == activeLbTab) and T.bodyText or T.panelStroke
	tStroke.Thickness = 2

	local icon = Instance.new("ImageLabel", btn)
	icon.Size = UDim2.new(0.6, 0, 0.6, 0)
	icon.Position = UDim2.new(0.2, 0, 0.2, 0)
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = iconId

	CollectionService:AddTag(btn, "Tutorial_LbTab_" .. string.gsub(tabName, " ", ""))
	lbSubBtns[tabName] = {btn = btn, stroke = tStroke}

	btn.MouseEnter:Connect(function() HoverLabel.Text = tabName end)
	btn.MouseLeave:Connect(function() HoverLabel.Text = activeTabText end)

	btn.MouseButton1Down:Connect(function()
		if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_ClickLbTab_" .. string.gsub(tabName, " ", "")) then return end
		PlayUI(SoundConfig.UIClick or "")
		activeLbTab = tabName
		HoverLabel.Text = tabName
		for k, t in pairs(lbSubBtns) do
			t.btn.BackgroundColor3 = (k == tabName) and T.accentGold or T.buttonSecondary
			t.stroke.Color = (k == tabName) and T.bodyText or T.panelStroke
		end
		BuildLeaderboardRows(activeLbTab)
		if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
	end)

	local scale = Instance.new("UIScale", btn)
	btn.MouseEnter:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15), {Scale = 1.05}):Play() end)
	btn.MouseLeave:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15), {Scale = 1}):Play() end)
	btn.MouseButton1Down:Connect(function() TweenService:Create(scale, TweenInfo.new(0.1), {Scale = 0.95}):Play() end)
	btn.MouseButton1Up:Connect(function() TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), {Scale = 1.05}):Play() end)
end

MakeLbSubTab("Top 10", "rbxassetid://14916846070") 
MakeLbSubTab("Auras Generated", "rbxassetid://4483362458") 
MakeLbSubTab("Most Money Made", "rbxassetid://14924185885") 

BuildLeaderboardRows(activeLbTab)

local setScroll = scrolls["Settings"]; local pad = Instance.new("UIPadding", setScroll); pad.PaddingTop = UDim.new(0, 5)
local function MakeToggleRow(labelText, settingKey)
	local row = Instance.new("Frame", setScroll); row.Size = UDim2.new(1, -10, 0, 42); row.BackgroundColor3 = T.cardBG; row.BorderSizePixel = 0; row.ZIndex = 41; Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)
	local lbl = Instance.new("TextLabel", row); lbl.Size = UDim2.new(0.6, 0, 1, 0); lbl.Position = UDim2.new(0, 15, 0, 0); lbl.BackgroundTransparency = 1; lbl.Text = labelText; lbl.TextColor3 = T.subText; lbl.TextScaled = true; lbl.Font = T.fontBody; lbl.TextXAlignment = Enum.TextXAlignment.Left
	local toggle = Instance.new("TextButton", row); toggle.Size = UDim2.new(0, 60, 0, 30); toggle.Position = UDim2.new(1, -70, 0.5, -15); toggle.BorderSizePixel = 0; toggle.TextScaled = true; toggle.Font = T.font; Instance.new("UICorner", toggle).CornerRadius = UDim.new(0, 6); CollectionService:AddTag(toggle, "Tutorial_SettingToggle_" .. settingKey)
	local function Refresh(isOn) toggle.Text = isOn and "ON" or "OFF"; toggle.TextColor3 = T.bodyText; toggle.BackgroundColor3 = isOn and T.buttonGreen or T.buttonRed end
	local isOn = true; if settingKey == "sfx" then isOn = sfxEnabled elseif settingKey == "music" then isOn = musicEnabled elseif settingKey == "jump" then isOn = jumpEnabled end
	Refresh(isOn); toggleRefs[settingKey] = Refresh
	toggle.MouseButton1Down:Connect(function()
		if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_ToggleSetting_" .. settingKey) then return end
		PlayUI(SoundConfig.UIClick or ""); if settingKey == "sfx" then sfxEnabled = not sfxEnabled; isOn = sfxEnabled elseif settingKey == "music" then musicEnabled = not musicEnabled; isOn = musicEnabled elseif settingKey == "jump" then jumpEnabled = not jumpEnabled; isOn = jumpEnabled end
		Refresh(isOn); SettingsChanged:Fire(settingKey, isOn)
		if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
	end)
end
MakeToggleRow("Sound Effects", "sfx"); MakeToggleRow("Music", "music"); MakeToggleRow("Jumping", "jump") 

local div1 = Instance.new("Frame", setScroll); div1.Size = UDim2.new(1, -20, 0, 2); div1.BackgroundColor3 = T.panelStroke; div1.BorderSizePixel = 0
local statsTitle = Instance.new("TextLabel", setScroll); statsTitle.Size = UDim2.new(1, -20, 0, 20); statsTitle.BackgroundTransparency = 1; statsTitle.Text = "FARM STATS"; statsTitle.TextColor3 = T.subText; statsTitle.TextScaled = true; statsTitle.Font = T.font; statsTitle.TextXAlignment = Enum.TextXAlignment.Left
local function MakeStatRow(labelText, refKey)
	local row = Instance.new("Frame", setScroll); row.Size = UDim2.new(1, -20, 0, 26); row.BackgroundTransparency = 1; local lbl = Instance.new("TextLabel", row); lbl.Size = UDim2.new(0.55, 0, 1, 0); lbl.BackgroundTransparency = 1; lbl.Text = labelText; lbl.TextColor3 = T.subText; lbl.TextScaled = true; lbl.Font = T.fontBody; lbl.TextXAlignment = Enum.TextXAlignment.Left; local val = Instance.new("TextLabel", row); val.Size = UDim2.new(0.45, 0, 1, 0); val.Position = UDim2.new(0.55, 0, 0, 0); val.BackgroundTransparency = 1; val.Text = "0"; val.TextColor3 = T.accentBlue; val.TextScaled = true; val.Font = T.font; val.TextXAlignment = Enum.TextXAlignment.Right; statValueRefs[refKey] = val
end
MakeStatRow("Soul Auras", "soul"); MakeStatRow("This Run", "run"); MakeStatRow("Rate", "rate"); MakeStatRow("Prestiges", "prestige")
local function RefreshStats() if statValueRefs.soul then statValueRefs.soul.Text = Formatter.Format(liveSoulAuras) end; if statValueRefs.run then statValueRefs.run.Text = "$" .. Formatter.Format(liveRunEarnings) end; if statValueRefs.rate then statValueRefs.rate.Text = "$" .. Formatter.Format(liveRate) .. "/s" end; if statValueRefs.prestige then statValueRefs.prestige.Text = Formatter.Format(livePrestiges) end end

-- ✨ MOBILE RESPONSIVE SCALING ADDED TO ROWS ✨
local function CreateInteractiveRow(parent, id, claimActionId, onClaimCallback)
	local row = parent:FindFirstChild(id)
	if not row then
		row = Instance.new("TextButton", parent); row.Name = id; row.Text = ""; row.AutoButtonColor = false; row.Size = UDim2.new(1, -8, 0, 64); row.BackgroundColor3 = T.cardBG; Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8); local stroke = Instance.new("UIStroke", row); stroke.Name = "Stroke"; stroke.Thickness = 1; local icon = Instance.new("ImageLabel", row); icon.Name = "Icon"; icon.Size = UDim2.new(0, 40, 0, 40); icon.Position = UDim2.new(0, 12, 0.5, -20); icon.ScaleType = Enum.ScaleType.Fit; Instance.new("UICorner", icon).CornerRadius = UDim.new(1, 0)

		-- Use relative scales for Title, Description, and Status Labels so they shrink gracefully
		local tLbl = Instance.new("TextLabel", row); tLbl.Name = "Title"; tLbl.Size = UDim2.new(0.5, 0, 0, 20); tLbl.Position = UDim2.new(0, 64, 0, 10); tLbl.BackgroundTransparency = 1; tLbl.TextColor3 = T.bodyText; tLbl.TextScaled = true; tLbl.Font = T.font; tLbl.TextXAlignment = Enum.TextXAlignment.Left
		local dLbl = Instance.new("TextLabel", row); dLbl.Name = "Desc"; dLbl.Size = UDim2.new(0.5, 0, 0, 24); dLbl.Position = UDim2.new(0, 64, 0, 32); dLbl.BackgroundTransparency = 1; dLbl.TextColor3 = T.subText; dLbl.TextScaled = true; dLbl.TextWrapped = true; dLbl.Font = T.fontBody; dLbl.TextXAlignment = Enum.TextXAlignment.Left
		local sLbl = Instance.new("TextLabel", row); sLbl.Name = "Status"; sLbl.Size = UDim2.new(0.3, 0, 0, 24); sLbl.Position = UDim2.new(1, -10, 0.5, -12); sLbl.AnchorPoint = Vector2.new(1, 0); sLbl.BackgroundTransparency = 1; sLbl.TextScaled = true; sLbl.Font = T.font; sLbl.TextXAlignment = Enum.TextXAlignment.Right

		UITheme.Apply(row, "Card"); CollectionService:AddTag(row, "Tutorial_AchieveRow_" .. id)
		local scale = Instance.new("UIScale", row)
		row.MouseEnter:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15), {Scale = 1.02}):Play() end)
		row.MouseLeave:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15), {Scale = 1}):Play(); row.Desc.Text = row:GetAttribute("BaseDesc") or "" end)
		row.MouseButton1Down:Connect(function()
			TweenService:Create(scale, TweenInfo.new(0.1), {Scale = 0.95}):Play()
			if row:GetAttribute("RowState") == "CLAIMABLE" then
				if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform(claimActionId) then return end
				PlayClaimVFX(row); onClaimCallback(); if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
			else
				PlayUI(SoundConfig.UIClick or ""); local showingReq = not row:GetAttribute("ShowingReq"); row:SetAttribute("ShowingReq", showingReq)
				if showingReq and row:GetAttribute("ReqDesc") ~= "" then row.Desc.Text = row:GetAttribute("ReqDesc"); row.Desc.TextColor3 = T.accentGold else row.Desc.Text = row:GetAttribute("BaseDesc"); row.Desc.TextColor3 = T.subText end
			end
		end)
		row.MouseButton1Up:Connect(function() TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), {Scale = 1.02}):Play() end)
	end
	return row
end

local function RefreshData()
	local claimedChallenges, claimedAuras, claimedBadges, discoveredTiers = latestStats.claimedChallenges or {}, latestStats.claimedAuras or {}, latestStats.claimedBadges or {}, latestStats.discoveredTiers or {}

	for i, chal in ipairs(AchievementConfig.Challenges) do
		local current = latestStats[chal.statKey] or 0
		local isDone = current >= chal.goal; local isClaimed = claimedChallenges[chal.id] == true
		local rowId = "Chal_" .. chal.id
		local row = CreateInteractiveRow(scrolls["Challenges"], rowId, "Action_ClaimChallenge_" .. chal.id, function() ClaimChallenge:FireServer(chal.id) end)
		row.Title.Text = chal.title; row.Icon.Image = chal.iconId; row:SetAttribute("BaseDesc", chal.rewardText); row:SetAttribute("ReqDesc", "Requires: " .. chal.desc)
		if isClaimed then row:SetAttribute("RowState", "CLAIMED"); row.Status.Text = "UNLOCKED"; row.Status.TextColor3 = T.subText; row.BackgroundColor3 = T.cardBG; row.Stroke.Color = T.accentBlue; row.Desc.Text = chal.rewardText; row.Desc.TextColor3 = T.subText
		elseif isDone then row:SetAttribute("RowState", "CLAIMABLE"); row.Status.Text = "CLAIM!"; row.Status.TextColor3 = Color3.fromRGB(255, 255, 255); row.BackgroundColor3 = Color3.fromRGB(80, 160, 60); row.Stroke.Color = Color3.fromRGB(120, 255, 100); row.Desc.Text = "Click to Unlock!"; row.Desc.TextColor3 = Color3.fromRGB(200, 255, 200)
		else row:SetAttribute("RowState", "LOCKED"); row.Status.Text = current .. " / " .. chal.goal; row.Status.TextColor3 = T.subText; row.BackgroundColor3 = T.cardBG; row.Stroke.Color = T.subText; row.Desc.Text = (not row:GetAttribute("ShowingReq")) and chal.rewardText or ("Requires: " .. chal.desc); row.Desc.TextColor3 = T.subText end
	end

	local indexCount = 1
	for aIdx = 1, 20 do
		local areaNames = AreaAuraNames[aIdx]
		if not areaNames then continue end
		for tIdx = 1, 5 do
			local tier = TierConfig.Tiers[tIdx]
			if not tier then continue end
			local auraKey = aIdx .. "_" .. tier.name; local discovered = discoveredTiers[auraKey] == true; local isClaimed = claimedAuras[auraKey] == true
			local rewardGA = AchievementConfig.AuraTierRewards[tier.name] or 5
			local row = CreateInteractiveRow(scrolls["Index"], "Index_" .. indexCount, "Action_ClaimAura_" .. aIdx .. "_" .. tier.name, function() ClaimAuraIndex:FireServer(aIdx, tier.name) end)
			row.Icon.Image = "rbxassetid://0"
			if isClaimed then row:SetAttribute("RowState", "CLAIMED"); row.Title.Text = areaNames[tIdx] .. " Aura"; row.Title.TextColor3 = tier.color; row.Status.Text = "FOUND"; row.Status.TextColor3 = T.subText; row.BackgroundColor3 = T.cardBG; row.Stroke.Color = tier.color; row:SetAttribute("BaseDesc", "Area " .. aIdx); row:SetAttribute("ReqDesc", ""); row.Desc.Text = "Area " .. aIdx; row.Desc.TextColor3 = T.subText
			elseif discovered then row:SetAttribute("RowState", "CLAIMABLE"); row.Title.Text = areaNames[tIdx] .. " Aura"; row.Title.TextColor3 = Color3.fromRGB(255, 255, 255); row.Status.Text = "CLAIM +" .. rewardGA .. " GA!"; row.Status.TextColor3 = Color3.fromRGB(255, 215, 0); row.BackgroundColor3 = Color3.fromRGB(150, 110, 20); row.Stroke.Color = Color3.fromRGB(255, 215, 0); row:SetAttribute("BaseDesc", "Click to claim reward!"); row:SetAttribute("ReqDesc", ""); row.Desc.Text = "Click to claim reward!"; row.Desc.TextColor3 = Color3.fromRGB(255, 240, 150)
			else row:SetAttribute("RowState", "LOCKED"); row.Title.Text = "???"; row.Title.TextColor3 = Color3.fromRGB(100, 100, 100); row.Status.Text = "???"; row.Status.TextColor3 = T.buttonRed; row.BackgroundColor3 = T.cardBG; row.Stroke.Color = Color3.fromRGB(50, 50, 50); row:SetAttribute("BaseDesc", "Undiscovered"); row:SetAttribute("ReqDesc", "Area " .. aIdx); row.Desc.Text = "Undiscovered"; row.Desc.TextColor3 = T.subText end
			indexCount += 1
		end
	end

	for i, badge in ipairs(AchievementConfig.Badges) do
		local current = latestStats[badge.statKey] or 0; local isDone = current >= badge.goal; local isClaimed = claimedBadges[i] == true
		local row = CreateInteractiveRow(scrolls["Badges"], "Badge_" .. i, "Action_ClaimBadge_" .. i, function() ClaimBadge:FireServer(i) end)
		row.Title.Text = badge.title; row.Icon.Image = badge.iconId; row:SetAttribute("BaseDesc", badge.desc); row:SetAttribute("ReqDesc", "Goal: " .. badge.goal)
		if isClaimed then row:SetAttribute("RowState", "CLAIMED"); row.Status.Text = "OWNED"; row.Status.TextColor3 = T.subText; row.BackgroundColor3 = T.cardBG; row.Stroke.Color = T.accentGold; row.Desc.Text = badge.desc; row.Desc.TextColor3 = T.subText
		elseif isDone then row:SetAttribute("RowState", "CLAIMABLE"); row.Status.Text = "CLAIM BADGE!"; row.Status.TextColor3 = Color3.fromRGB(255, 255, 255); row.BackgroundColor3 = Color3.fromRGB(120, 60, 180); row.Stroke.Color = Color3.fromRGB(200, 100, 255); row.Desc.Text = "Click to receive Badge!"; row.Desc.TextColor3 = Color3.fromRGB(230, 200, 255)
		else row:SetAttribute("RowState", "LOCKED"); row.Status.Text = current .. " / " .. badge.goal; row.Status.TextColor3 = T.subText; row.BackgroundColor3 = T.cardBG; row.Stroke.Color = T.subText; row.Desc.Text = badge.desc; row.Desc.TextColor3 = T.subText end
	end
end

UpdateHUDBridge:Connect(function(stats)
	for key, value in pairs(stats) do latestStats[key] = value end
	if stats.soulAuras ~= nil then liveSoulAuras = stats.soulAuras end; if stats.totalEarned ~= nil then liveRunEarnings = stats.totalEarned end; if stats.rate ~= nil and stats.passiveInterval ~= nil and stats.passiveInterval > 0 then liveRate = stats.rate / stats.passiveInterval end; if stats.prestigeCount ~= nil then livePrestiges = stats.prestigeCount end
	if stats.settings then
		if stats.settings.sfxEnabled ~= nil then sfxEnabled = stats.settings.sfxEnabled; if toggleRefs.sfx then toggleRefs.sfx(sfxEnabled) end end
		if stats.settings.musicEnabled ~= nil then musicEnabled = stats.settings.musicEnabled; if toggleRefs.music then toggleRefs.music(musicEnabled) end end
		if stats.settings.jumpEnabled ~= nil then jumpEnabled = stats.settings.jumpEnabled; if toggleRefs.jump then toggleRefs.jump(jumpEnabled) end end
	end
	if panelOpen then RefreshData(); RefreshStats() end
end)

local function OpenToTab(tabName, hoverText)
	PlayUI(SoundConfig.UIOpen or ""); panelOpen = true; Panel.Visible = true; Panel.Size = UDim2.new(0.85, 0, 0, 0); activeTab = tabName; activeTabText = hoverText; HoverLabel.Text = activeTabText
	for k, t in pairs(tabBtns) do t.btn.BackgroundColor3 = (k == activeTab) and T.accentGold or T.buttonSecondary; t.stroke.Color = (k == activeTab) and T.bodyText or T.panelStroke end
	for k, s in pairs(scrolls) do s.Visible = (k == activeTab) end
	RefreshData(); RefreshStats(); TitleLabel.Text = (tabName == "Settings") and "SETTINGS" or "PROGRESSION"
	TweenService:Create(Panel, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = UDim2.new(0.85, 0, 0.75, 0)}):Play()
	UITheme.SetMenuVisible(true)
end

local function ClosePanel()
	if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_CloseAchievements") then return end
	PlayUI(SoundConfig.UIClose or ""); panelOpen = false; TweenService:Create(Panel, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Size = UDim2.new(0.85, 0, 0, 0)}):Play(); UITheme.SetMenuVisible(false); task.delay(0.25, function() Panel.Visible = false end)
	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
end

AchieveBtn.MouseButton1Down:Connect(function()
	if not panelOpen then
		if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_OpenAchievements") then return end
		OpenToTab("Challenges", "Boosts")
		if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
	else
		ClosePanel()
	end
end)

CloseBtn.MouseButton1Down:Connect(ClosePanel)

local function AddButtonJuice(btn)
	local scale = btn:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", btn)
	btn.MouseEnter:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15), {Scale = 1.08}):Play() end)
	btn.MouseLeave:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15), {Scale = 1}):Play() end)
	btn.MouseButton1Down:Connect(function() TweenService:Create(scale, TweenInfo.new(0.1), {Scale = 0.9}):Play() end)
	btn.MouseButton1Up:Connect(function() TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), {Scale = 1.08}):Play() end)
end
AddButtonJuice(AchieveBtn); AddButtonJuice(CloseBtn)
for _, t in pairs(tabBtns) do AddButtonJuice(t.btn) end

task.spawn(function() task.wait(1); UITheme.Apply(Panel, "Panel"); UITheme.Apply(Header, "TitleBar"); UITheme.ApplyShine(Panel) end)

---------------------------------------------------------------
-- ✨ THE FIX: JUMP ENFORCER LOGIC
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

local forceClose = ReplicatedStorage:FindFirstChild("ForceCloseUI") or Instance.new("BindableEvent")
forceClose.Name = "ForceCloseUI"; forceClose.Parent = ReplicatedStorage
forceClose.Event:Connect(function() if panelOpen then CloseBtn.MouseButton1Down:Fire() end end)
