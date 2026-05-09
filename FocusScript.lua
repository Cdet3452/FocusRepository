-- BoostController
-- Location: StarterPlayer > StarterPlayerScripts > BoostController
-- FIX: Active boost strip now stacks vertically (was horizontal).
--      Active Boosts use Scale + AspectRatio to fit mobile and PC.
--      Shop Cards fixed and restored to original sizes.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local AdminConfig       = require(ReplicatedStorage.Modules.AdminConfig)
local T                 = require(ReplicatedStorage.Modules.UITheme).Get()
local SoundConfig       = require(ReplicatedStorage.Modules.SoundConfig)
local BoostConfig       = require(ReplicatedStorage.Modules.BoostConfig) 
local AchievementConfig = require(ReplicatedStorage.Modules.AchievementConfig)
local UITheme = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("UITheme"))
local T = UITheme.Get("Custom")
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

local BOOST_ORDER = {
	"AuraRush", "SpawnBoost", "SoulBoost", "CashCheck",
	"HatcheryRefill", "InstaHatchery",
	"BoostBeacon2x", "BoostBeacon10x", "BoostBeacon50x"
}
local BOOST_COLORS = {
	AuraRush       = Color3.fromRGB(60,  160, 255),
	SpawnBoost     = Color3.fromRGB(255, 160, 40),
	SoulBoost      = Color3.fromRGB(180, 60,  255),
	BoostBeacon50x = Color3.fromRGB(255, 50,  50),  -- Example red
	CashCheck      = Color3.fromRGB(50,  255, 100), -- Example green
	HatcheryRefill      = Color3.fromRGB(50,  255, 100), -- Example green
	InstaHatchery      = Color3.fromRGB(50,  255, 100), -- Example green
	BoostBeacon2x      = Color3.fromRGB(50,  255, 100), -- Example green
	BoostBeacon10x      = Color3.fromRGB(50,  255, 100), -- Example green
}

local function PlayUI(id)
	if shared.PlayUISound then shared.PlayUISound(id) end
end

local function FormatTime(s)
	s = math.ceil(s or 0)
	if s <= 0 then return "0:00" end
	return string.format("%d:%02d", math.floor(s/60), s % 60)
end

---------------------------------------------------------------
-- ACTIVE BOOST STRIP (MOBILE & PC SCALING FIX)
---------------------------------------------------------------
local BoostStrip = Instance.new("Frame")
BoostStrip.Name = "ActiveBoostStrip"
BoostStrip.Size = UDim2.new(0.14, 0, 0.5, 0) 
BoostStrip.AnchorPoint = Vector2.new(1, 0)
BoostStrip.Position = UDim2.new(0.98, 0, 0.5, 0) 
BoostStrip.BackgroundTransparency = 1

-- FIX 1: Pushed ZIndex to 60 so it appears on top of the Shop Menu!
BoostStrip.ZIndex = 60; BoostStrip.Visible = false; BoostStrip.Parent = mainHUD

local StripLayout = Instance.new("UIListLayout")
StripLayout.FillDirection = Enum.FillDirection.Vertical
StripLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right 
StripLayout.VerticalAlignment = Enum.VerticalAlignment.Top
StripLayout.Padding = UDim.new(0, 6)
StripLayout.Parent = BoostStrip

local stripSlots = {}

for _, boostId in ipairs(BOOST_ORDER) do
	local cfg   = BoostConfig.Get(boostId)
	if not cfg then continue end
	local color = BOOST_COLORS[boostId]

	local slot = Instance.new("Frame")
	slot.Name = "Slot_" .. boostId
	-- FIX 2: 100% responsive width, but guaranteed 40px readable height! (No more invisible squish)
	slot.Size = UDim2.new(1, 0, 0, 40)  
	slot.BackgroundColor3 = T.cardBG; slot.BorderSizePixel = 0
	slot.ZIndex = 61; slot.Visible = false; slot.Parent = BoostStrip
	Instance.new("UICorner", slot).CornerRadius = UDim.new(0, 7)
	local ss = Instance.new("UIStroke"); ss.Color = color; ss.Thickness = 1.5; ss.Parent = slot

	-- Icon on the left
	local iconLbl = Instance.new("TextLabel")
	iconLbl.Size = UDim2.new(0.2, 0, 1, 0)
	iconLbl.Position = UDim2.new(0, 4, 0, 0)
	iconLbl.BackgroundTransparency = 1; iconLbl.Text = cfg.icon or "?"
	iconLbl.TextScaled = true; iconLbl.Font = T.font
	iconLbl.ZIndex = 62; iconLbl.Parent = slot

	-- Boost name
	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size = UDim2.new(0.5, 0, 0.55, 0)
	nameLbl.Position = UDim2.new(0.25, 0, 0, 2)
	nameLbl.BackgroundTransparency = 1; nameLbl.Text = cfg.displayName or boostId
	nameLbl.TextColor3 = color; nameLbl.TextScaled = true
	nameLbl.Font = T.font; nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.ZIndex = 62; nameLbl.Parent = slot

	-- Timer on the right
	local timeLbl = Instance.new("TextLabel")
	timeLbl.Name = "TimeLabel"
	timeLbl.Size = UDim2.new(0.25, 0, 0.55, 0)
	timeLbl.Position = UDim2.new(0.7, -4, 0, 2)
	timeLbl.BackgroundTransparency = 1; timeLbl.Text = "0:30"
	timeLbl.TextColor3 = color; timeLbl.TextScaled = true
	timeLbl.Font = T.font; timeLbl.TextXAlignment = Enum.TextXAlignment.Right
	timeLbl.ZIndex = 62; timeLbl.Parent = slot

	-- Stack count below name
	local stackLbl = Instance.new("TextLabel")
	stackLbl.Name = "StackLabel"
	stackLbl.Size = UDim2.new(0.5, 0, 0.4, 0)
	stackLbl.Position = UDim2.new(0.25, 0, 0.5, 0)
	stackLbl.BackgroundTransparency = 1; stackLbl.Text = ""
	stackLbl.TextColor3 = T.subText; stackLbl.TextScaled = true
	stackLbl.Font = T.fontBody; stackLbl.TextXAlignment = Enum.TextXAlignment.Left
	stackLbl.ZIndex = 62; stackLbl.Parent = slot

	stripSlots[boostId] = { slot = slot, timeLbl = timeLbl, stackLbl = stackLbl }
end

local BoostsBtn = Instance.new("ImageButton")
BoostsBtn.Name = "BoostsButton"
BoostsBtn.Size = UDim2.new(0, 60, 0, 60)
BoostsBtn.AnchorPoint = Vector2.new(1, 1) -- ✨ Anchors perfectly to bottom right
BoostsBtn.Position = UDim2.new(0.98, 0, 0.77, 0) -- ✨ Stacked neatly above Shop
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
boostIcon.Image = "rbxassetid://14916846070" -- 🖼️ PLACEHOLDER: Lightning Icon ID
---------------------------------------------------------------
-- BOOST SHOP PANEL
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
sizeConstraint.MaxSize = Vector2.new(340, 480)
sizeConstraint.Parent = ShopPanel

local shopStroke = Instance.new("UIStroke")
shopStroke.Color = T.panelStroke; shopStroke.Thickness = 2; shopStroke.Parent = ShopPanel

local ShopHeader = Instance.new("Frame")
ShopHeader.Size = UDim2.new(1, 0, 0, 44)
ShopHeader.BackgroundColor3 = T.headerBG; ShopHeader.BorderSizePixel = 0
ShopHeader.ZIndex = 41; ShopHeader.Parent = ShopPanel
Instance.new("UICorner", ShopHeader).CornerRadius = UDim.new(0, 14)

local ShopTitle = Instance.new("TextLabel")
ShopTitle.Size = UDim2.new(1, -50, 1, 0); ShopTitle.Position = UDim2.new(0, 14, 0, 0)
ShopTitle.BackgroundTransparency = 1; ShopTitle.Text = "BOOST SHOP"
ShopTitle.TextColor3 = T.headerText; ShopTitle.TextScaled = true
ShopTitle.Font = T.font; ShopTitle.TextXAlignment = Enum.TextXAlignment.Left
ShopTitle.ZIndex = 42; ShopTitle.Parent = ShopHeader

local ShopClose = Instance.new("TextButton")
ShopClose.Size = UDim2.new(0, 28, 0, 28); ShopClose.Position = UDim2.new(1, -36, 0.5, -14)
ShopClose.BackgroundColor3 = T.buttonRed; ShopClose.BorderSizePixel = 0
ShopClose.Text = "X"; ShopClose.TextColor3 = T.headerText
ShopClose.TextScaled = true; ShopClose.Font = T.font
ShopClose.ZIndex = 9999; ShopClose.Parent = ShopHeader
Instance.new("UICorner", ShopClose).CornerRadius = UDim.new(0, 5)

local ScrollContainer = Instance.new("ScrollingFrame")
ScrollContainer.Name = "ScrollContainer"
ScrollContainer.Size = UDim2.new(1, 0, 1, -80) 
ScrollContainer.Position = UDim2.new(0, 0, 0, 80)
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

local cardRefs = {}

local function BuildCards()
	for i, boostId in ipairs(BOOST_ORDER) do
		local cfg = BoostConfig.Get(boostId)
		if not cfg then continue end
		local color = BOOST_COLORS[boostId]

		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, -16, 0, 98) -- ORIGINAL SHOP CARD SIZE IS BACK!
		card.BackgroundColor3 = T.cardBG; card.BorderSizePixel = 0
		card.ZIndex = 41; card.Parent = ScrollContainer
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 10)

		local cs = Instance.new("UIStroke"); cs.Color = color; cs.Thickness = 1.5; cs.Parent = card

		local iconLbl = Instance.new("TextLabel")
		iconLbl.Size = UDim2.new(0, 36, 0, 36); iconLbl.Position = UDim2.new(0, 8, 0, 8)
		iconLbl.BackgroundTransparency = 1; iconLbl.Text = cfg.icon or "?"
		iconLbl.TextScaled = true; iconLbl.Font = T.font; iconLbl.ZIndex = 42; iconLbl.Parent = card

		local nameLbl = Instance.new("TextLabel")
		nameLbl.Size = UDim2.new(0.5, 0, 0, 22); nameLbl.Position = UDim2.new(0, 50, 0, 6)
		nameLbl.BackgroundTransparency = 1; nameLbl.Text = cfg.displayName or boostId
		nameLbl.TextColor3 = color; nameLbl.TextScaled = true
		nameLbl.Font = T.font; nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		nameLbl.ZIndex = 42; nameLbl.Parent = card

		local descLbl = Instance.new("TextLabel")
		descLbl.Size = UDim2.new(0.7, 0, 0, 16); descLbl.Position = UDim2.new(0, 50, 0, 30)
		descLbl.BackgroundTransparency = 1; descLbl.Text = cfg.description or ""
		descLbl.TextColor3 = T.subText; descLbl.TextScaled = true
		descLbl.Font = T.fontBody; descLbl.TextXAlignment = Enum.TextXAlignment.Left
		descLbl.ZIndex = 42; descLbl.Parent = card

		local durLbl = Instance.new("TextLabel")
		durLbl.Size = UDim2.new(0.7, 0, 0, 14); durLbl.Position = UDim2.new(0, 50, 0, 48)
		durLbl.BackgroundTransparency = 1; durLbl.Text = FormatTime(cfg.duration) .. " duration"
		durLbl.TextColor3 = Color3.fromRGB(110, 115, 140); durLbl.TextScaled = true
		durLbl.Font = T.fontBody; durLbl.TextXAlignment = Enum.TextXAlignment.Left
		durLbl.ZIndex = 42; durLbl.Parent = card

		local buyBtn = Instance.new("TextButton")
		buyBtn.Size = UDim2.new(0, 82, 0, 38); buyBtn.Position = UDim2.new(1, -94, 0, 6)
		buyBtn.BorderSizePixel = 0; buyBtn.TextScaled = true; buyBtn.Font = T.font
		buyBtn.ZIndex = 42; buyBtn.Parent = card
		Instance.new("UICorner", buyBtn).CornerRadius = UDim.new(0, 7)

		local actBtn = Instance.new("TextButton")
		actBtn.Size = UDim2.new(0, 82, 0, 38); actBtn.Position = UDim2.new(1, -94, 0, 54)
		actBtn.BorderSizePixel = 0; actBtn.TextScaled = true; actBtn.Font = T.font
		actBtn.ZIndex = 42; actBtn.Parent = card
		Instance.new("UICorner", actBtn).CornerRadius = UDim.new(0, 7)

		local invBadge = Instance.new("TextLabel")
		invBadge.Size = UDim2.new(0, 28, 0, 18); invBadge.Position = UDim2.new(0, 6, 1, -22)
		invBadge.BackgroundColor3 = Color3.fromRGB(40, 40, 60); invBadge.BorderSizePixel = 0
		invBadge.Text = "x0"; invBadge.TextColor3 = T.subText
		invBadge.TextScaled = true; invBadge.Font = T.font
		invBadge.ZIndex = 43; invBadge.Parent = card
		Instance.new("UICorner", invBadge).CornerRadius = UDim.new(0, 4)

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
		refs.invBadge.TextColor3 = invCount > 0 and T.bodyText or Color3.fromRGB(100,100,120)

		if not isUnlocked then
			-- ✨ VISUALLY LOCKED STATE
			refs.buyBtn.Text             = "LOCKED"
			refs.buyBtn.BackgroundColor3 = T.buttonRed
			refs.buyBtn.TextColor3       = T.bodyText

			refs.actBtn.Text             = "Locked"
			refs.actBtn.BackgroundColor3 = T.buttonDisabled
			refs.actBtn.TextColor3       = T.subText

			-- ✨ SHOW REQUIREMENT IN RED
			refs.descLbl.Text = "Requires: " .. lockReason
			refs.descLbl.TextColor3 = T.buttonRed
		else
			-- ✨ VISUALLY UNLOCKED STATE
			refs.descLbl.Text = cfg.description or ""
			refs.descLbl.TextColor3 = T.subText

			refs.buyBtn.Text             = cost .. " ⭐"
			refs.buyBtn.TextColor3       = T.bodyText
			refs.buyBtn.BackgroundColor3 = canAfford and T.buttonGreen or T.buttonDisabled

			if invCount <= 0 then
				refs.actBtn.Text             = "No stock"
				refs.actBtn.BackgroundColor3 = T.buttonDisabled
				refs.actBtn.TextColor3       = T.subText
			elseif atCap then
				refs.actBtn.Text             = "MAX " .. FormatTime(state and state.activeTimes and state.activeTimes[1] or 0)
				refs.actBtn.BackgroundColor3 = Color3.fromRGB(30, 70, 40)
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
	for _, boostId in ipairs(BOOST_ORDER) do
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
	TweenService:Create(ShopPanel, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0.85, 0, 0.8, 0)
	}):Play()
	UITheme.SetMenuVisible(true)
end

local function ClosePanel()
	panelOpen = false
	PlayUI(SoundConfig.UIClose)
	TweenService:Create(ShopPanel, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Size = UDim2.new(0.85, 0, 0, 0)
	}):Play()
	UITheme.SetMenuVisible(false)
	task.delay(0.22, function() ShopPanel.Visible = false end)
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
	for _, boostId in ipairs(BOOST_ORDER) do
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

AddButtonJuice(BoostsBtn)

local shopShine = nil

-- Add this at the end of the script to 'Glass-ify' the existing UI
local function RefreshLook()
	-- Apply to the main panel
	UITheme.Apply(ShopPanel, "Panel") -- or whatever your frame is named

	if not shopShine then
		shopShine = UITheme.ApplyShine(ShopPanel)
	end
	-- Apply to each existing upgrade card
	for _, card in ipairs(ScrollContainer:GetChildren()) do
		if card:IsA("Frame") then
			UITheme.Apply(card, "Card")
		end
	end
end

-- Run it once on start
task.wait(1) 
RefreshLook()

-- BoostManager
-- Location: ServerScriptService > BoostManager (ModuleScript)
--
-- STACKING CHANGE: Additive like Egg Inc Bird Feed.
--   OLD (multiplicative): 3x AuraRush stacks = 2 × 2 × 2 = 8x
--   NEW (additive):       3x AuraRush stacks = 1 + (1+1+1) = 4x
--
--   Formula: total = 1 + (multiplier - 1) * activeStackCount
--   So 1 stack of 2x = 2x, 2 stacks = 3x, 3 stacks = 4x
--   Much more balanced — same as Egg Inc's Bird Feed behaviour.

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AdminConfig = require(ReplicatedStorage.Modules.AdminConfig)
local GameManager = require(ServerScriptService.GameManager)
local BoostConfig = require(ReplicatedStorage.Modules.BoostConfig)
local AchievementConfig = require(ReplicatedStorage.Modules.AchievementConfig)
local function GetOrCreate(name)
	local existing = ReplicatedStorage.RemoteEvents:FindFirstChild(name)
	if existing then return existing end
	local re = Instance.new("RemoteEvent")
	re.Name   = name
	re.Parent = ReplicatedStorage.RemoteEvents
	return re
end

local BuyBoost      = GetOrCreate("BuyBoost")
local ActivateBoost = GetOrCreate("ActivateBoost")
local BoostUpdated  = GetOrCreate("BoostUpdated")

local activeStacks = {}  -- [uid] = { {boostId, endsAt}, ... }

---------------------------------------------------------------
-- Helpers
---------------------------------------------------------------
local function GetActiveStacks(uid, boostId)
	local stacks = activeStacks[uid] or {}
	local count, now = 0, tick()
	for _, entry in ipairs(stacks) do
		if entry.boostId == boostId and entry.endsAt > now then
			count += 1
		end
	end
	return count
end

local function PruneExpired(uid)
	local stacks = activeStacks[uid]
	if not stacks then return end
	local now, pruned = tick(), {}
	for _, entry in ipairs(stacks) do
		if entry.endsAt > now then table.insert(pruned, entry) end
	end
	activeStacks[uid] = pruned
end

---------------------------------------------------------------
-- ADDITIVE multiplier helper
-- Returns: 1 + (bonus_per_stack) * activeCount
-- Example: 2x boost, 3 stacks → 1 + 1×3 = 4x  (not 8x)
---------------------------------------------------------------
local function AdditiveMultiplier(uid, boostId)
	PruneExpired(uid)
	local cfg = BoostConfig.Get(boostId)
	if not cfg then return 1 end
	local bonus  = (cfg.multiplier or 2) - 1  -- bonus per stack (e.g. 2x → bonus = 1)
	local count  = GetActiveStacks(uid, boostId)	
	return 1 + bonus * count
end

---------------------------------------------------------------
-- Public API
---------------------------------------------------------------
local BoostManager = {}

-- Additive spawn rate multiplier for AuraRush
-- AuraSpawner divides its fire interval by this value
function BoostManager.GetSpawnRateMultiplier(uid)
	return AdditiveMultiplier(uid, "AuraRush")
end

-- Additive value multiplier for SpawnBoost
function BoostManager.GetValueMultiplier(uid)
	return AdditiveMultiplier(uid, "SpawnBoost")
end



function BoostManager.IsActive(uid, boostId)
	return GetActiveStacks(uid, boostId) > 0
end

-- Soul aura multiplier (SoulBoost, max 1 active — no stacking needed)
function BoostManager.GetSoulMultiplier(uid)
	PruneExpired(uid)
	local stacks = activeStacks[uid] or {}
	local now    = tick()
	local cfg = BoostConfig.Get("SoulBoost") -- Changed boostId to the string "SoulBoost"
	for _, entry in ipairs(stacks) do
		if entry.boostId == "SoulBoost" and entry.endsAt > now then
			return cfg and cfg.multiplier or 2
		end
	end
	return 1
end

local function BuildState(uid)
	PruneExpired(uid)
	local stacks = activeStacks[uid] or {}
	local data   = GameManager.GetData(uid)
	local now    = tick()

	local state = {}

	-- THE FIX: Iterate through BoostConfig instead of AdminConfig!
	for boostId, cfg in pairs(BoostConfig.Boosts or {}) do

		local activeList = {}
		for _, entry in ipairs(stacks) do
			if entry.boostId == boostId and entry.endsAt > now then
				table.insert(activeList, math.max(0, entry.endsAt - now))
			end
		end
		state[boostId] = {
			inventoryCount = data and (data.boostInventory and data.boostInventory[boostId] or 0) or 0,
			activeCount    = #activeList,
			activeTimes    = activeList,
			duration       = cfg.duration,
			cost           = cfg.cost,
			multiplier     = cfg.multiplier,
			displayName    = cfg.displayName,
			description    = cfg.description,
			icon           = cfg.icon,
			maxStack       = cfg.maxStack,
			stackable      = cfg.stackable,
		}
	end

	state._goldenAuras = data and (data.goldenAuras or 0) or 0
	return state
end

local function SendState(player)
	BoostUpdated:FireClient(player, BuildState(player.UserId))
end

---------------------------------------------------------------
-- BUY
---------------------------------------------------------------
BuyBoost.OnServerEvent:Connect(function(player, boostId)
	local uid  = player.UserId
	local data = GameManager.GetData(uid)
	if not data then return end

	local cfg = BoostConfig.Get(boostId) -- NEW
	if not cfg then warn("[BoostManager] Unknown boost:", boostId); return end

	local cost = cfg.cost or 0
	if (data.goldenAuras or 0) < cost then return end
	local isUnlocked = AchievementConfig.IsBoostUnlocked(boostId, data)
	if not isUnlocked then return end 
	data.goldenAuras = (data.goldenAuras or 0) - cost
	data.boostInventory = data.boostInventory or {}
	data.boostInventory[boostId] = (data.boostInventory[boostId] or 0) + 1

	SendState(player)
	ReplicatedStorage.RemoteEvents.UpdateHUD:FireClient(player, {
		goldenAuras    = data.goldenAuras,
		boostInventory = data.boostInventory,
	})
end)

---------------------------------------------------------------
-- ACTIVATE
---------------------------------------------------------------
ActivateBoost.OnServerEvent:Connect(function(player, boostId)
	local uid  = player.UserId
	local data = GameManager.GetData(uid)
	if not data then return end

	local cfg = BoostConfig.Get(boostId)
	if not cfg then return end

	data.boostInventory = data.boostInventory or {}
	if (data.boostInventory[boostId] or 0) <= 0 then return end

	PruneExpired(uid)
	local currentStacks = GetActiveStacks(uid, boostId)
	if currentStacks >= (cfg.maxStack or 1) then return end

	data.boostInventory[boostId] = data.boostInventory[boostId] - 1

	activeStacks[uid] = activeStacks[uid] or {}
	table.insert(activeStacks[uid], {
		boostId = boostId,
		endsAt  = tick() + cfg.duration,
	})

	SendState(player)

	task.delay(cfg.duration, function()
		PruneExpired(uid)
		if player and player.Parent then SendState(player) end
	end)
end)

---------------------------------------------------------------
-- Player lifecycle
---------------------------------------------------------------
Players.PlayerAdded:Connect(function(player)
	activeStacks[player.UserId] = {}
	task.wait(2)
	SendState(player)
end)

Players.PlayerRemoving:Connect(function(player)
	activeStacks[player.UserId] = nil
end)

-- Periodic sync for countdown accuracy
task.spawn(function()
	while true do
		task.wait(5)
		for _, player in ipairs(Players:GetPlayers()) do
			if activeStacks[player.UserId] and #activeStacks[player.UserId] > 0 then
				SendState(player)
			end
		end
	end
end)

return BoostManager

-- BoostConfig
-- Location: ReplicatedStorage > Modules > BoostConfig
--
-- ONE place for all boost definitions. Replaces AdminConfig.Boosts.
-- BoostManager and BoostController read from this.
--
-- Each boost:
--   id            = key name (e.g. "AuraRush")
--   displayName   = shown in UI
--   description   = shown in shop card
--   icon          = "rbxassetid://12345" (must include full prefix!)
--   duration      = seconds (0 = instant/one-shot)
--   cost          = golden auras to buy
--   multiplier    = effect value (meaning depends on effectType)
--   effectType    = how the boost works:
--       "spawnSpeed"     — multiplies spawn rate
--       "cubeValue"      — multiplies cube value
--       "soulMult"       — multiplies soul aura gain on prestige
--       "hatcheryRefill" — multiplies hatchery refill rate
--       "instaRefill"    — instantly refills hatchery to max (one-shot)
--       "boostMultiplier"— multiplies ALL active boost effects
--       "cashCheck"      — gives currency = farmEval * multiplier (one-shot)
--   stackable     = can buy and activate multiple at once
--   maxStack      = max active stacks
--   category      = "Production" / "Value" / "Premium" / "Utility"
--   color         = accent Color3 for UI cards

local BoostConfig = {}

BoostConfig.Boosts = {

	-- ══════════ PRODUCTION ══════════

	AuraRush = {
		id          = "AuraRush",
		displayName = "Aura Rush",
		description = "Double spawn speed",
		icon        = "",   -- rbxassetid://YOUR_ID
		duration    = 30,
		cost        = 5,
		multiplier  = 2.0,
		effectType  = "spawnSpeed",
		stackable   = true,
		maxStack    = 3,
		category    = "Production",
		color       = Color3.fromRGB(60, 160, 255),
	},

	HatcheryRefill = {
		id          = "HatcheryRefill",
		displayName = "Fast Refill",
		description = "2x hatchery refill speed",
		icon        = "",
		duration    = 60,
		cost        = 8,
		multiplier  = 2.0,
		effectType  = "hatcheryRefill",
		stackable   = true,
		maxStack    = 3,
		category    = "Production",
		color       = Color3.fromRGB(80, 220, 120),
	},

	InstaHatchery = {
		id          = "InstaHatchery",
		displayName = "Insta Refill",
		description = "Instantly refill hatchery to max",
		icon        = "",
		duration    = 0,   -- one-shot
		cost        = 12,
		multiplier  = 1,
		effectType  = "instaRefill",
		stackable   = false,
		maxStack    = 1,
		category    = "Production",
		color       = Color3.fromRGB(0, 255, 180),
	},

	-- ══════════ VALUE ══════════

	SpawnBoost = {
		id          = "SpawnBoost",
		displayName = "Value Boost",
		description = "Double cube value",
		icon        = "",
		duration    = 45,
		cost        = 8,
		multiplier  = 2.0,
		effectType  = "cubeValue",
		stackable   = true,
		maxStack    = 3,
		category    = "Value",
		color       = Color3.fromRGB(255, 160, 40),
	},

	SoulBoost = {
		id          = "SoulBoost",
		displayName = "Soul Boost",
		description = "2x Soul Auras on prestige",
		icon        = "",
		duration    = 120,
		cost        = 15,
		multiplier  = 2.0,
		effectType  = "soulMult",
		stackable   = false,
		maxStack    = 1,
		category    = "Value",
		color       = Color3.fromRGB(180, 60, 255),
	},

	CashCheck = {
		id          = "CashCheck",
		displayName = "Cash Check",
		description = "Get 5x your farm evaluation as cash!",
		icon        = "",
		duration    = 0,   -- one-shot
		cost        = 20,
		multiplier  = 5,   -- currency = farmEval * 5
		effectType  = "cashCheck",
		stackable   = false,
		maxStack    = 1,
		category    = "Value",
		color       = Color3.fromRGB(80, 255, 80),
	},

	-- ══════════ PREMIUM — BOOST MULTIPLIERS ══════════
	-- Like Egg Inc's Boost Beacon — multiplies ALL active boosts

	BoostBeacon2x = {
		id          = "BoostBeacon2x",
		displayName = "Boost Beacon x2",
		description = "Double all active boost effects!",
		icon        = "",
		duration    = 30,
		cost        = 25,
		multiplier  = 2,
		effectType  = "boostMultiplier",
		stackable   = false,
		maxStack    = 1,
		category    = "Premium",
		color       = Color3.fromRGB(255, 100, 100),
	},

	BoostBeacon10x = {
		id          = "BoostBeacon10x",
		displayName = "Boost Beacon x10",
		description = "10x all active boost effects!",
		icon        = "",
		duration    = 15,
		cost        = 100,
		multiplier  = 10,
		effectType  = "boostMultiplier",
		stackable   = false,
		maxStack    = 1,
		category    = "Premium",
		color       = Color3.fromRGB(255, 60, 60),
	},

	BoostBeacon50x = {
		id          = "BoostBeacon50x",
		displayName = "Boost Beacon x50",
		description = "50x all active boost effects!! Insane!",
		icon        = "",
		duration    = 10,
		cost        = 500,
		multiplier  = 50,
		effectType  = "boostMultiplier",
		stackable   = false,
		maxStack    = 1,
		category    = "Premium",
		color       = Color3.fromRGB(255, 30, 30),
	},
}

---------------------------------------------------------------
-- DISPLAY ORDER — controls which boosts show in the shop
---------------------------------------------------------------
BoostConfig.ShopOrder = {
	"AuraRush", "HatcheryRefill", "InstaHatchery",
	"SpawnBoost", "SoulBoost", "CashCheck",
	"BoostBeacon2x", "BoostBeacon10x", "BoostBeacon50x",
}

---------------------------------------------------------------
-- CATEGORY ORDER — for grouping in shop
---------------------------------------------------------------
BoostConfig.Categories = { "Production", "Value", "Premium" }

BoostConfig.CategoryColors = {
	Production = Color3.fromRGB(60, 180, 255),
	Value      = Color3.fromRGB(255, 200, 60),
	Premium    = Color3.fromRGB(255, 60, 80),
}

---------------------------------------------------------------
-- HELPERS
---------------------------------------------------------------
function BoostConfig.Get(id)
	return BoostConfig.Boosts[id]
end

function BoostConfig.GetByCategory(category)
	local result = {}
	for _, id in ipairs(BoostConfig.ShopOrder) do
		local b = BoostConfig.Boosts[id]
		if b and b.category == category then
			table.insert(result, b)
		end
	end
	return result
end

return BoostConfig

