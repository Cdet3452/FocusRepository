-- AchievementController
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

-- ✨ BRIDGENET2 UPGRADE
local BridgeNet2      = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))
local UpdateHUDBridge = BridgeNet2.ClientBridge("UpdateHUD")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainHUD   = playerGui:WaitForChild("MainHUD")
local Faded2    = mainHUD:WaitForChild("Faded2") 
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

-- ✨ TUTORIAL TAG: Enables automatic Padlock Overlay
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

UpdateHUDBridge:Connect(function(stats)
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
	banner.Position = UDim2.new(0, -300, 0.4, 0)
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
	nameLbl.Text = string.upper(info.actualName or info.name) .. " AURA"
	nameLbl.TextColor3 = info.color
	nameLbl.Font = T.font
	nameLbl.TextScaled = true
	nameLbl.TextXAlignment = Enum.TextXAlignment.Left

	banner.Parent = mainHUD

	TweenService:Create(banner, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Position = UDim2.new(0, 20, 0.4, 0)}):Play()

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
	-- ✨ TUTORIAL GATING
	if not panelOpen then
		if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_OpenAchievements") then return end
	end

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

-- ✨ TUTORIAL OVERRIDE: Close menu when camera pans
local forceClose = ReplicatedStorage:FindFirstChild("ForceCloseUI") or Instance.new("BindableEvent")
forceClose.Name = "ForceCloseUI"
forceClose.Parent = ReplicatedStorage
forceClose.Event:Connect(function()
	if panelOpen then 
		panelOpen = false
		TweenService:Create(Panel, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Size = UDim2.new(0.85, 0, 0, 0)}):Play()
		UITheme.SetMenuVisible(false)
		task.delay(0.25, function() Panel.Visible = false end)
	end
end)

-- SettingsController
-- Location: StarterPlayer > StarterPlayerScripts > SettingsController
-- FIX: ClipsDescendants = true so close animation clips content.
-- MOBILE FIX: UIListLayout + AutomaticCanvasSize + NumberFormatter linked!

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local T                 = require(ReplicatedStorage.Modules.UITheme).Get()
local Formatter         = require(ReplicatedStorage.Modules.NumberFormatter)
local UITheme = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("UITheme"))
local T = UITheme.Get("Custom")
local UpdateHUD = ReplicatedStorage.RemoteEvents:WaitForChild("UpdateHUD")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainHUD   = playerGui:WaitForChild("MainHUD")
local Faded2 = mainHUD:WaitForChild("Faded2") -- ✨ Get the container!

local SettingsChanged = Instance.new("BindableEvent")
SettingsChanged.Name   = "SettingsChanged"
SettingsChanged.Parent = ReplicatedStorage

local sfxEnabled   = true
local musicEnabled = true
local jumpEnabled  = true 
local panelOpen    = false

local liveSoulAuras   = 0
local liveRunEarnings = 0
local liveRate        = 0
local livePrestiges   = 0
local toggleRefs      = {}

---------------------------------------------------------------
-- 2. SETTINGS BUTTON (Left Side of Faded2)
---------------------------------------------------------------
local SettingsBtn = Instance.new("ImageButton", Faded2) -- ✨ PARENTED TO FADED2
SettingsBtn.Name = "SettingsButton"
SettingsBtn.Size = UDim2.new(0.85, 0, 0.85, 0) -- ✨ Takes up 85% of Faded2's height
SettingsBtn.Position = UDim2.new(0.05, 0, 0.5, 0) -- ✨ Placed on the far left
SettingsBtn.AnchorPoint = Vector2.new(0, 0.5) -- ✨ Anchored perfectly center-left
SettingsBtn.BackgroundColor3 = T.buttonSecondary 
SettingsBtn.BorderSizePixel = 0
SettingsBtn.AutoButtonColor = false
SettingsBtn.ZIndex = 15
Instance.new("UICorner", SettingsBtn).CornerRadius = UDim.new(0.5, 0)

-- ✨ MOBILE FIX: Forces it to stay a perfect circle no matter the screen size!
local settingsAspect = Instance.new("UIAspectRatioConstraint", SettingsBtn)
settingsAspect.AspectRatio = 1.0 

local gearStroke = Instance.new("UIStroke", SettingsBtn)
gearStroke.Color = T.accentGold; gearStroke.Thickness = 1
---------------------------------------------------------------
-- PANEL (MOBILE RESPONSIVE)
---------------------------------------------------------------
local Panel = Instance.new("Frame")
Panel.Name = "SettingsPanel"
Panel.Size = UDim2.new(0.85, 0, 0.65, 0) -- Responsive Scale
Panel.Position = UDim2.new(0.5, 0, 0.5, 0)
Panel.AnchorPoint = Vector2.new(0.5, 0.5)
Panel.BackgroundColor3 = T.panelBG; Panel.BorderSizePixel = 0
Panel.Visible = false; Panel.ZIndex = 40
Panel.ClipsDescendants = true
Panel.Parent = mainHUD
Instance.new("UICorner", Panel).CornerRadius = UDim.new(0, 12)
local btnIcon = Instance.new("ImageLabel", SettingsBtn)
btnIcon.Size = UDim2.new(0.7, 0, 0.7, 0)
btnIcon.Position = UDim2.new(0.15, 0, 0.15, 0)
btnIcon.BackgroundTransparency = 1
btnIcon.ScaleType = Enum.ScaleType.Fit
btnIcon.Image = "rbxassetid://14923131909"
local scale = Instance.new("UIScale", SettingsBtn)
SettingsBtn.MouseEnter:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15), {Scale = 1.08}):Play() end)
SettingsBtn.MouseLeave:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15), {Scale = 1}):Play() end)
SettingsBtn.MouseButton1Down:Connect(function() TweenService:Create(scale, TweenInfo.new(0.1), {Scale = 0.9}):Play() end)
SettingsBtn.MouseButton1Up:Connect(function() TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), {Scale = 1.08}):Play() end)
-- Prevents Settings from being massive on PC
local sizeConstraint = Instance.new("UISizeConstraint")
sizeConstraint.MaxSize = Vector2.new(280, 380) 
sizeConstraint.Parent = Panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = T.panelStroke; panelStroke.Thickness = 2; panelStroke.Parent = Panel

local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 38)
Header.BackgroundColor3 = T.headerBG; Header.BorderSizePixel = 0
Header.ZIndex = 41; Header.Parent = Panel
Instance.new("UICorner", Header).CornerRadius = UDim.new(0, 12)

local HeaderLabel = Instance.new("TextLabel")
HeaderLabel.Size = UDim2.new(1, -44, 1, 0); HeaderLabel.Position = UDim2.new(0, 12, 0, 0)
HeaderLabel.BackgroundTransparency = 1; HeaderLabel.Text = "SETTINGS"
HeaderLabel.TextColor3 = T.headerText; HeaderLabel.TextScaled = true
HeaderLabel.Font = T.font; HeaderLabel.TextXAlignment = Enum.TextXAlignment.Left
HeaderLabel.ZIndex = 42; HeaderLabel.Parent = Header

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 26, 0, 26); CloseBtn.Position = UDim2.new(1, -32, 0.5, -13)
CloseBtn.BackgroundColor3 = T.buttonRed; CloseBtn.BorderSizePixel = 0
CloseBtn.Text = "X"; CloseBtn.TextColor3 = T.bodyText
CloseBtn.TextScaled = true; CloseBtn.Font = T.font
CloseBtn.ZIndex = 42; CloseBtn.Parent = Header
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 5)

---------------------------------------------------------------
-- SCROLL CONTAINER
---------------------------------------------------------------
local ScrollContainer = Instance.new("ScrollingFrame")
ScrollContainer.Name = "ScrollContainer"
ScrollContainer.Size = UDim2.new(1, 0, 1, -38) -- Fits under header
ScrollContainer.Position = UDim2.new(0, 0, 0, 38)
ScrollContainer.BackgroundTransparency = 1
ScrollContainer.BorderSizePixel = 0
ScrollContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
ScrollContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y
ScrollContainer.ScrollBarThickness = 4
ScrollContainer.Parent = Panel

local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 8)
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
listLayout.Parent = ScrollContainer

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 8)
padding.PaddingBottom = UDim.new(0, 10)
padding.Parent = ScrollContainer

---------------------------------------------------------------
-- BUILD UI ELEMENTS
---------------------------------------------------------------
local function MakeToggleRow(labelText, settingKey)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -20, 0, 36) -- No Position needed!
	row.BackgroundColor3 = T.cardBG; row.BorderSizePixel = 0
	row.ZIndex = 41; row.Parent = ScrollContainer
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 7)

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(0.58, 0, 1, 0); lbl.Position = UDim2.new(0, 10, 0, 0)
	lbl.BackgroundTransparency = 1; lbl.Text = labelText
	lbl.TextColor3 = T.subText; lbl.TextScaled = true
	lbl.Font = T.fontBody; lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.ZIndex = 42; lbl.Parent = row

	local toggle = Instance.new("TextButton")
	toggle.Size = UDim2.new(0, 50, 0, 24); toggle.Position = UDim2.new(1, -58, 0.5, -12)
	toggle.BorderSizePixel = 0; toggle.TextScaled = true; toggle.Font = T.font
	toggle.ZIndex = 42; toggle.Parent = row
	Instance.new("UICorner", toggle).CornerRadius = UDim.new(0, 5)

	local function Refresh(isOn)
		toggle.Text             = isOn and "ON" or "OFF"
		toggle.TextColor3       = T.bodyText
		toggle.BackgroundColor3 = isOn and T.buttonGreen or T.buttonRed
	end

	-- FIX: Upgraded to handle all 3 settings
	local isOn = true
	if settingKey == "sfx" then isOn = sfxEnabled
	elseif settingKey == "music" then isOn = musicEnabled
	elseif settingKey == "jump" then isOn = jumpEnabled end

	Refresh(isOn)
	toggleRefs[settingKey] = Refresh

	toggle.MouseButton1Down:Connect(function()
		if settingKey == "sfx" then sfxEnabled = not sfxEnabled; isOn = sfxEnabled
		elseif settingKey == "music" then musicEnabled = not musicEnabled; isOn = musicEnabled
		elseif settingKey == "jump" then jumpEnabled = not jumpEnabled; isOn = jumpEnabled end

		Refresh(isOn)
		SettingsChanged:Fire(settingKey, isOn)
	end)
end

MakeToggleRow("Sound Effects", "sfx")
MakeToggleRow("Music",      "music")
MakeToggleRow("Jumping",       "jump") 

local div1 = Instance.new("Frame")
div1.Size = UDim2.new(1, -20, 0, 1)
div1.BackgroundColor3 = T.panelStroke; div1.BorderSizePixel = 0
div1.ZIndex = 41; div1.Parent = ScrollContainer

local statsTitle = Instance.new("TextLabel")
statsTitle.Size = UDim2.new(1, -20, 0, 16)
statsTitle.BackgroundTransparency = 1; statsTitle.Text = "FARM STATS"
statsTitle.TextColor3 = T.subText; statsTitle.TextScaled = true
statsTitle.Font = T.font; statsTitle.TextXAlignment = Enum.TextXAlignment.Left
statsTitle.ZIndex = 41; statsTitle.Parent = ScrollContainer

local statValueRefs = {}

local function MakeStatRow(labelText, refKey)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -20, 0, 22)
	row.BackgroundTransparency = 1; row.ZIndex = 41; row.Parent = ScrollContainer

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(0.55, 0, 1, 0); lbl.BackgroundTransparency = 1
	lbl.Text = labelText; lbl.TextColor3 = T.subText
	lbl.TextScaled = true; lbl.Font = T.fontBody
	lbl.TextXAlignment = Enum.TextXAlignment.Left; lbl.ZIndex = 42; lbl.Parent = row

	local val = Instance.new("TextLabel")
	val.Size = UDim2.new(0.45, 0, 1, 0); val.Position = UDim2.new(0.55, 0, 0, 0)
	val.BackgroundTransparency = 1; val.Text = "0"
	val.TextColor3 = T.accentBlue; val.TextScaled = true
	val.Font = T.font; val.TextXAlignment = Enum.TextXAlignment.Right
	val.ZIndex = 42; val.Parent = row
	statValueRefs[refKey] = val
end

MakeStatRow("Soul Auras",  "soul")
MakeStatRow("This Run",    "run")
MakeStatRow("Rate",        "rate")
MakeStatRow("Prestiges",   "prestige")

local function RefreshStats()
	if statValueRefs.soul     then statValueRefs.soul.Text     = Formatter.Format(liveSoulAuras) end
	if statValueRefs.run      then statValueRefs.run.Text      = "$" .. Formatter.Format(liveRunEarnings) end
	if statValueRefs.rate     then statValueRefs.rate.Text     = "$" .. Formatter.Format(liveRate) .. "/s" end
	if statValueRefs.prestige then statValueRefs.prestige.Text = Formatter.Format(livePrestiges) end
end

local div2 = Instance.new("Frame")
div2.Size = UDim2.new(1, -20, 0, 1)
div2.BackgroundColor3 = T.panelStroke; div2.BorderSizePixel = 0
div2.ZIndex = 41; div2.Parent = ScrollContainer

local function Credit(text, color)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, -20, 0, 14)
	l.BackgroundTransparency = 1; l.Text = text; l.TextColor3 = color
	l.TextScaled = true; l.Font = T.fontBody
	l.TextXAlignment = Enum.TextXAlignment.Left; l.ZIndex = 41; l.Parent = ScrollContainer
end

Credit("Aura Inc",               Color3.fromRGB(85, 100, 135))
Credit("Made by MoldySugar2205", Color3.fromRGB(65, 80,  110))
Credit("Phase 4",                Color3.fromRGB(50, 65,  90))

---------------------------------------------------------------
-- PANEL TWEENS
---------------------------------------------------------------
local function OpenPanel()
	panelOpen = true; Panel.Visible = true; Panel.Size = UDim2.new(0.85, 0, 0, 0)
	RefreshStats()
	TweenService:Create(Panel, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0.85, 0, 0.65, 0) -- Responsive Target Size
	}):Play()
	UITheme.SetMenuVisible(true)
end

local function ClosePanel()
	panelOpen = false
	TweenService:Create(Panel, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Size = UDim2.new(0.85, 0, 0, 0)
	}):Play()
	UITheme.SetMenuVisible(false)
	task.delay(0.2, function() Panel.Visible = false end)
end

SettingsBtn.MouseButton1Down:Connect(function() if panelOpen then ClosePanel() else OpenPanel() end end)
CloseBtn.MouseButton1Down:Connect(ClosePanel)

UpdateHUD.OnClientEvent:Connect(function(stats)
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
		-- THIS is the only part that goes inside the HUD update:
		if stats.settings.jumpEnabled ~= nil then
			jumpEnabled = stats.settings.jumpEnabled
			if toggleRefs.jump then toggleRefs.jump(jumpEnabled) end
			SettingsChanged:Fire("jump", jumpEnabled)
		end
	end

	if panelOpen then RefreshStats() end
end)

---------------------------------------------------------------
-- JUMP ENFORCER LOGIC (FOOLPROOF FIX)
-- Must be OUTSIDE the UpdateHUD event at the bottom of the script!
---------------------------------------------------------------
local defaultJumpHeight = 7.2
local defaultJumpPower = 50

local function UpdateJumpState(character, canJump)
	if not character then return end
	local humanoid = character:WaitForChild("Humanoid", 3)
	if humanoid then
		-- Save their normal jump stats just in case you add jump upgrades later
		if humanoid.JumpHeight > 0 then defaultJumpHeight = humanoid.JumpHeight end
		if humanoid.JumpPower > 0 then defaultJumpPower = humanoid.JumpPower end

		if canJump then
			humanoid.UseJumpPower = not humanoid.UseJumpPower -- Forces an update
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

-- 1. Apply when the player flips the setting switch
SettingsChanged.Event:Connect(function(key, value)
	if key == "jump" then
		UpdateJumpState(player.Character, value)
	end
end)

-- 2. Re-apply automatically if the player resets/respawns
player.CharacterAdded:Connect(function(char)
	-- Slight delay to ensure the character is fully loaded before changing stats
	task.wait(0.1) 
	UpdateJumpState(char, jumpEnabled)
end)

-- 3. Catch the player when they first load in
if player.Character then
	UpdateJumpState(player.Character, jumpEnabled)
end

-- SoundManager
-- Location: StarterPlayer > StarterPlayerScripts > SoundManager
--
-- MENU GATE: Only the initial area music waits for MenuDismissed.
-- shared.PlayUISound and all event connections work immediately.
-- This ensures other scripts can play sounds during loading.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local SoundService      = game:GetService("SoundService")

local SoundConfig = require(ReplicatedStorage.Modules.SoundConfig)

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local SoundGroup = Instance.new("SoundGroup")
SoundGroup.Name   = "AuraIncSounds"
SoundGroup.Volume = 1
SoundGroup.Parent = SoundService

local soundCache = {}

local function GetOrCreateSound(id, volume, looped)
	if not id or id == "" then return nil end
	local fullId = "rbxassetid://" .. id
	if not soundCache[id] then
		local s = Instance.new("Sound")
		s.SoundId = fullId; s.Volume = volume or 1
		s.Looped  = looped or false; s.RollOffMaxDistance = 0
		s.Parent  = SoundGroup
		soundCache[id] = s
	end
	return soundCache[id]
end

local sfxEnabled   = true
local musicEnabled = true
local MUSIC_VOL    = SoundConfig.Volume and SoundConfig.Volume.music or 0.4

local function Vol(category)
	return SoundConfig.Volume and SoundConfig.Volume[category] or 0.5
end

local function Play(id, volume)
	if not sfxEnabled then return end
	if not id or id == "" then return end
	local s = GetOrCreateSound(id, volume, false)
	if s then s:Play() end
end

-- Expose for other LocalScripts (PrestigeController, PortalController, etc.)
shared.PlayUISound = function(id, volume)
	Play(id, volume or Vol("ui"))
end

---------------------------------------------------------------
-- Hold loop
---------------------------------------------------------------
local loopingSound = nil

local function PlayLoop(id, volume)
	if not sfxEnabled then return end
	if not id or id == "" then return end
	local s = GetOrCreateSound(id, volume, true)
	if s and not s.IsPlaying then s:Play(); loopingSound = s end
end

local function StopLoop()
	if loopingSound and loopingSound.IsPlaying then loopingSound:Stop() end
	loopingSound = nil
end

---------------------------------------------------------------
-- Area music
---------------------------------------------------------------
local currentMusicSound = nil

local function PlayAreaMusic(areaIndex)
	local id = SoundConfig.AreaMusic and SoundConfig.AreaMusic[areaIndex]

	if not id or id == "" then
		if currentMusicSound and currentMusicSound.IsPlaying then
			local old = currentMusicSound; currentMusicSound = nil
			TweenService:Create(old, TweenInfo.new(1.5), { Volume = 0 }):Play()
			task.delay(1.6, function() old:Stop() end)
		end
		return
	end

	local fullId = "rbxassetid://" .. id
	if currentMusicSound and currentMusicSound.SoundId == fullId
		and currentMusicSound.IsPlaying then return end

	if currentMusicSound and currentMusicSound.IsPlaying then
		local old = currentMusicSound; currentMusicSound = nil
		TweenService:Create(old, TweenInfo.new(1.5), { Volume = 0 }):Play()
		task.delay(1.6, function() old:Stop() end)
	end

	task.delay(0.5, function()
		local s = GetOrCreateSound(id, 0, true)
		if not s then return end
		s:Play(); currentMusicSound = s
		local targetVol = musicEnabled and MUSIC_VOL or 0
		TweenService:Create(s, TweenInfo.new(1.5), { Volume = targetVol }):Play()
	end)
end

---------------------------------------------------------------
-- Settings
---------------------------------------------------------------
task.spawn(function()
	local SettingsChanged = ReplicatedStorage:WaitForChild("SettingsChanged", 20)
	if not SettingsChanged then
		warn("[SoundManager] SettingsChanged not found — sound toggles won't work")
		return
	end

	SettingsChanged.Event:Connect(function(settingKey, isOn)
		if settingKey == "sfx" then
			sfxEnabled = isOn
			SoundGroup.Volume = isOn and 1 or 0
			if not isOn then StopLoop() end
		elseif settingKey == "music" then
			musicEnabled = isOn
			if currentMusicSound then
				if currentMusicSound.IsPlaying then
					TweenService:Create(currentMusicSound,
						TweenInfo.new(0.4), { Volume = isOn and MUSIC_VOL or 0 }):Play()
				elseif isOn then
					currentMusicSound:Play()
					TweenService:Create(currentMusicSound,
						TweenInfo.new(1.0), { Volume = MUSIC_VOL }):Play()
				end
			end
		end
	end)
end)

---------------------------------------------------------------
-- UI button hooks (main HUD buttons)
---------------------------------------------------------------
task.spawn(function()
	local mainHUD = playerGui:WaitForChild("MainHUD")

	local function HookOpen(name)
		local btn = mainHUD:WaitForChild(name, 10)
		if btn then
			btn.MouseButton1Down:Connect(function()
				Play(SoundConfig.UIOpen, Vol("ui"))
			end)
		end
	end

	HookOpen("ShopButton")
	HookOpen("StatsButton")
	HookOpen("PrestigeButton")
	HookOpen("SettingsButton")
	HookOpen("BoostsButton")
end)

---------------------------------------------------------------
-- PrestigeReady BindableEvent
---------------------------------------------------------------
task.spawn(function()
	local pr = ReplicatedStorage:WaitForChild("PrestigeReady", 30)
	if not pr then return end
	pr.Event:Connect(function()
		Play(SoundConfig.PrestigeReady, Vol("ui"))
	end)
end)

---------------------------------------------------------------
-- Game event sounds
---------------------------------------------------------------
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")

local AuraSpawned = RemoteEvents:WaitForChild("AuraSpawned")
AuraSpawned.OnClientEvent:Connect(function(info)
	if info.tier == "Legendary" then
		Play(SoundConfig.LegendarySpawn, Vol("mutation"))
	else
		Play(SoundConfig.Click, Vol("interaction"))
	end
end)

local CubeMutated = RemoteEvents:WaitForChild("CubeMutated")
CubeMutated.OnClientEvent:Connect(function(info)
	if info.mutationType == "tierUpgrade" then
		Play(info.tierName == "Legendary"
			and SoundConfig.LegendarySpawn or SoundConfig.TierUpgrade, Vol("mutation"))
	elseif info.mutationType == "valueBonus" then
		Play(SoundConfig.MutationBonus, Vol("mutation"))
	end
end)

local UpdateMultiplier = ReplicatedStorage:WaitForChild("UpdateMultiplier")
UpdateMultiplier.Event:Connect(function(mult)
	if mult > 1 then PlayLoop(SoundConfig.HoldLoop, Vol("interaction"))
	else StopLoop() end
end)

local ForceStopHold = RemoteEvents:WaitForChild("ForceStopHold")
ForceStopHold.OnClientEvent:Connect(function()
	StopLoop()
	Play(SoundConfig.HatcheryEmpty, Vol("interaction"))
end)

local HabitatFull = RemoteEvents:WaitForChild("HabitatFull")
HabitatFull.OnClientEvent:Connect(function()
	StopLoop()
	Play(SoundConfig.HabitatFull, Vol("interaction"))
end)

local ShipAuras = RemoteEvents:WaitForChild("ShipAuras")
ShipAuras.OnClientEvent:Connect(function(info)
	if info and info.collected then Play(SoundConfig.PlatformArrive, Vol("shipping")) end
end)

local UpgradeUpdated = RemoteEvents:WaitForChild("UpgradeUpdated")
UpgradeUpdated.OnClientEvent:Connect(function(info)
	if info.type == "purchased" then Play(SoundConfig.Purchase, Vol("mutation")) end
end)

local PrestigeComplete = RemoteEvents:WaitForChild("PrestigeComplete")
PrestigeComplete.OnClientEvent:Connect(function(info)
	StopLoop()
	if info.isPortalEntry then
		Play(SoundConfig.PortalEnter, Vol("portal"))
	else
		Play(SoundConfig.PrestigeComplete, Vol("prestige"))
	end
end)

local AreaUnlocked = RemoteEvents:WaitForChild("AreaUnlocked")
AreaUnlocked.OnClientEvent:Connect(function()
	Play(SoundConfig.PortalOpen, Vol("portal"))
end)

local AreaChanged = RemoteEvents:WaitForChild("AreaChanged")
AreaChanged.OnClientEvent:Connect(function(info)
	Play(SoundConfig.PortalEnter, Vol("portal"))
	PlayAreaMusic(info.newArea or 1)
end)

---------------------------------------------------------------
-- MENU GATE: Only the initial area music waits for the menu.
-- Everything else (SFX, event sounds, shared.PlayUISound) is live.
---------------------------------------------------------------
local AreaUpdated = RemoteEvents:WaitForChild("AreaUpdated")
local joinMusicStarted = false
AreaUpdated.OnClientEvent:Connect(function(info)
	if not joinMusicStarted then
		joinMusicStarted = true
		task.spawn(function()
			local _menuGate = ReplicatedStorage:WaitForChild("MenuDismissed")
			if not _menuGate:GetAttribute("Fired") then _menuGate.Event:Wait() end
			PlayAreaMusic(info.currentArea or 1)
		end)
	end
end)
