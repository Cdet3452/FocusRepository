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

-- TutorialConfig
-- Location: ReplicatedStorage > Modules > TutorialConfig

local TutorialConfig = {}

TutorialConfig.TutorialEndArea = 5

-- The Ghost Hand / Pointer asset
TutorialConfig.PointerImage = "rbxassetid://14914009728"
TutorialConfig.PointerSize = UDim2.new(0, 75, 0, 75)

-- Default Styling
TutorialConfig.DefaultColor = Color3.fromRGB(100, 200, 255)
TutorialConfig.DefaultIcon  = "rbxassetid://14914018910"

-- THE FSM SEQUENCE
TutorialConfig.Steps = {

	-- ✨ STEP 1: Welcome & First Click
	[1] = {
		id           = "a1_welcome_click",
		action       = "Action_ClickRedButton",
		targetTag    = "Tutorial_ClickButton",

		bannerTitle  = "Welcome to Aura Inc!",
		bannerBody   = "Spam Click the Red Button below to produce your first Auras.",

		icon         = "rbxassetid://14922082255", 
		color        = Color3.fromRGB(143, 255, 131), -- Green
	},

	-- ✨ STEP 2: Cinematic Camera Follow! Watch the Aura move.
	[2] = {
		id               = "a1_watch_aura",
		action           = "Action_Wait",

		cameraTrackMode  = "FollowAura", 
		target3D         = "Aura",       
		duration         = 10,          

		bannerTitle  = "Generating Profit",
		bannerBody   = "Each Aura generates cash every second based on its rarity.",
		
		icon         = "rbxassetid://14914018910",
		color        = Color3.fromRGB(255, 255, 255), 
	},

	-- ✨ STEP 3: Produce Bulk
	[3] = {
		id           = "a1_produce_25",
		action       = "Action_ClickRedButton",
		targetTag    = "Tutorial_ClickButton",

		-- Look back at the general factory area
		cameraTarget = "Tutorial_AuraHolderCam",

		requireCubesProduced = 25,
		failsafeDuration = 35, -- ✨ NEW: Autocompletes after 35 seconds if they get stuck!
		bannerTitle  = "Producing Auras",
		bannerBody   = "Keep clicking to produce 25 Auras! The more you make, the more money you earn.",
		duration     = 0, 

		icon         = "rbxassetid://14914018910",
		color        = Color3.fromRGB(130, 226, 255), -- Cyan
	},

	-- ✨ STEP 4: Farm up Cash
	[4] = {
		id           = "a1_farm_150",
		action       = "Action_ClickRedButton",

		requireCurrency = 150,

		bannerTitle  = "Stacking Cash",
		bannerBody   = "Your Auras are passively generating income while on the Conveyer. Keep producing until you save up $150!",
		duration     = 0,
		failsafeDuration = 25, -- ✨ NEW: Autocompletes after 35 seconds if they get stuck!
		icon         = "rbxassetid://14924185885",
		color        = Color3.fromRGB(150, 255, 150), -- Light Green
	},

	-- ✨ STEP 5: Unlock Shop
	[5] = {
		id           = "a1_open_shop",
		action       = "Action_OpenShop",
		targetTag    = "Tutorial_ShopButton",

		unlockTags    = {"Tutorial_ShopButton"},
		unlockActions = {"Action_OpenShop", "Action_CloseShop"},

		bannerTitle  = "Open The Shop",
		bannerBody   = "You have enough Money! Click the Shop icon to view your upgrades.",
		
		icon         = "rbxassetid://14915225073",
		color        = Color3.fromRGB(123, 216, 250), -- Grey
	},

	-- ✨ STEP 6: First Upgrade
	[6] = {
		id             = "a1_buy_blockValue",
		action         = "Action_BuyUpgrade",
		targetTag      = "Tutorial_Buy_blockValue",

		unlockTags     = {"Tutorial_Buy_blockValue"},
		-- ✨ FIX: Removed duration = 0 so it doesn't auto-skip!

		menuTag        = "Tutorial_ShopPanel",
		menuOpenBtnTag = "Tutorial_ShopButton",

		bannerTitle  = "Increase Value",
		bannerBody   = "Buy the Value upgrade to increase the Value of your Auras by +10%",

		icon         = "rbxassetid://14917128076",
		color        = Color3.fromRGB(142, 206, 255), 
	},

	-- ✨ STEP 7: The "Trap". Waiting for the physical bin to fill up.
	[7] = {
		id           = "a1_fill_habitat",
		action       = "Action_ClickRedButton",
		targetTag    = "Tutorial_ClickButton",

		requireHabitatFull = true,
		duration           = 0, 

		bannerTitle  = "Keep Producing",
		bannerBody   = "Close the shop and keep Producing Auras. Spam Click or HOLD the red button To keep producing Auras.",

		icon         = "rbxassetid://14914018910",
		color        = Color3.fromRGB(130, 226, 255), -- Cyan
	},

	-- ✨ STEP 8: Watch the Aura Die (Zoomed Out). 
	[8] = {
		id               = "a1_watch_aura_die",
		action           = "Action_Wait",

		cameraTrackMode  = "FollowAura",
		cameraOffset     = Vector3.new(0, 22, 28), 

		requireRateZero  = true, 
		duration         = 0, 

		bannerTitle  = "Incinerated!",
		bannerBody   = "Since your habitat Got full, Auras get incinerated. Wait for your Rate to hit $0.",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(255, 0, 4), -- Red
	},

	-- ✨ STEP 9: Pan to Habitat to show the full bin
	[9] = {
		id           = "a1_look_at_habitat",
		action       = "Action_Wait",
		cameraTarget = "Tutorial_HabitatCam",

		duration     = 7, 

		bannerTitle  = "Habitat is Full!",
		bannerBody   = "Your storage is completely Full. You need to clear some Space.",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(255, 155, 155), -- Red
	},

	-- ✨ STEP 10: The Solution (Send Button)
	[10] = {
		id           = "a1_send_ship",
		action       = "Action_SendShip",
		targetTag    = "Tutorial_SendShipBtn",

		unlockTags    = {"Tutorial_SendShipBtn"},
		unlockActions = {"Action_SendShip"},

		bannerTitle  = "Clear Space",
		bannerBody   = "Click the newly unlocked SEND button to clear out your habitat of the Auras.",

		icon         = "rbxassetid://14915225073",
		color        = Color3.fromRGB(100, 255, 255), -- Cyan
	},

	-- ✨ STEP 11: Watch the Ship!
	[11] = {
		id           = "a1_wait_for_ship",
		action       = "Action_Wait",
		cameraTarget = "Tutorial_ShippingCam",

		requirePlatformsShipped = 2,

		bannerTitle  = "Ship Delivery",
		bannerBody   = "Ships collect all your Auras and pay out the cash directly to your wallet. Send 2 Ships Out.",
		duration     = 0,

		icon         = "rbxassetid://14914018910",
		color        = Color3.fromRGB(150, 200, 255), -- Light Blue
	},

	-- ✨ STEP 12: Automate it
	[12] = {
		id           = "a1_toggle_auto",
		action       = "Action_ToggleAutoShip",
		targetTag    = "Tutorial_ToggleShipBtn",

		unlockTags    = {"Tutorial_ToggleShipBtn"},
		unlockActions = {"Action_ToggleAutoShip"},

		bannerTitle  = "Automate Ships",
		bannerBody   = "Click the new unlocked Toggle Button to automate your shipments!",

		icon         = "rbxassetid://14915225073",
		color        = Color3.fromRGB(50, 150, 50), -- Dark Green
	},

	-- ✨ STEP 13: Business as usual
	[13] = {
		id           = "a1_farm_500",
		action       = "Action_ClickRedButton",

		requireCurrency = 500,

		bannerTitle  = "More Upgrades!",
		bannerBody   = "Make $500 to afford your next upgrade.",
		duration     = 0,

		icon         = "rbxassetid://14924185885",
		color        = Color3.fromRGB(150, 255, 150), -- Light Green
	},

	[14] = {
		id             = "a1_buy_auraExpansion",
		action         = "Action_BuyUpgrade",
		targetTag      = "Tutorial_Buy_hatcheryCapacity",

		unlockTags     = {"Tutorial_Buy_hatcheryCapacity"},

		menuTag        = "Tutorial_ShopPanel",
		menuOpenBtnTag = "Tutorial_ShopButton",

		bannerTitle  = "More Hatchery",
		bannerBody   = "Buy the Aura Expansion upgrade to increase your Hatchery space!",

		icon         = "rbxassetid://14917128076",
		color        = Color3.fromRGB(105, 255, 250), 
	},

	[15] = {
		id           = "a1_farm_1500",
		action       = "Action_ClickRedButton",

		requireCurrency = 1500,

		bannerTitle  = "Growing the Factory",
		bannerBody   = "Make $1500 to afford the Habitat upgrade, allowing you to store more auras! Buy the aura value upgrade if you feel stuck.",
		duration     = 0,

		icon         = "rbxassetid://14924185885",
		color        = Color3.fromRGB(87, 255, 98),
	},

	[16] = {
		id             = "a1_buy_habitatCapacity",
		action         = "Action_BuyUpgrade",
		targetTag      = "Tutorial_Buy_habitatCapacity",

		unlockTags     = {"Tutorial_Buy_habitatCapacity"},

		menuTag        = "Tutorial_ShopPanel",
		menuOpenBtnTag = "Tutorial_ShopButton",

		bannerTitle  = "More Habitat Space",
		bannerBody   = "Buy the Habitat Reservoir Upgrade to store more Auras before they get Incinirated!",

		icon         = "rbxassetid://14917128076",
		color        = Color3.fromRGB(120, 248, 255),
	},

	[17] = {
		id           = "a1_multiply",
		action       = "Action_ClickRedButton",

		reachMultiplier = 5,

		bannerTitle  = "Hatchery Multipliers",
		bannerBody   = "Hold the Red button to reach the legendary multiplier! Make sure you have enough Hatchery and Space",
		duration     = 0,

		icon         = "rbxassetid://14924185885",
		color        = Color3.fromRGB(255, 255, 0), 
	},
	
	[18] = {
		id           = "a1_farm_25000",
		action       = "Action_ClickRedButton",

		requireCurrency = 5000,

		bannerTitle  = "Mythic Multiplier",
		bannerBody   = "Multipliers Increase Ship and Aura Value. Save up $5,000 to afford the Mythic Multiplier! Upgrade Aura Value If Stuck.",
		duration     = 0,

		icon         = "rbxassetid://14924185885",
		color        = Color3.fromRGB(137, 255, 110), -- White
	},

	[19] = {
		id             = "a1_buy_mythicMult",
		action         = "Action_BuyUpgrade",
		targetTag      = "Tutorial_Buy_unlockMythicMult", 

		unlockTags     = {"Tutorial_Buy_unlockMythicMult"},

		menuTag        = "Tutorial_ShopPanel",
		menuOpenBtnTag = "Tutorial_ShopButton",

		bannerTitle  = "Mythic Multiplier",
		bannerBody   = "Buy the Mythic Multiplier to hold past the legendary multiplier limit!",

		icon         = "rbxassetid://14917128076",
		color        = Color3.fromRGB(80, 246, 255),
	},
	
	[20] = {
		id           = "a1_multiply",
		action       = "Action_ClickRedButton",

		reachMultiplier = 10,

		bannerTitle  = "Hatchery Multipliers",
		bannerBody   = "Hold the Red button to reach the Mythic multiplier! Make sure to have plenty of Hatchery and Space",
		duration     = 0,

		icon         = "rbxassetid://14924185885",
		color        = Color3.fromRGB(134, 24, 161), 
	},

	[21] = {
		id           = "a1_open_prestige",
		action       = "Action_OpenPrestige",
		targetTag    = "Tutorial_PrestigeButton",

		-- We intentionally don't unlock the Confirm button yet!
		unlockTags    = {"Tutorial_PrestigeButton", "Tutorial_PrestigeCloseBtn"},
		unlockActions = {"Action_OpenPrestige", "Action_ClosePrestige"},

		bannerTitle  = "How to Prestige",
		bannerBody   = "Click the Prestige button to restart with a massive permanent earnings multiplier.",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(180, 100, 255),
	},

	[22] = {
		id             = "a1_confirm_prestige",
		action         = "Action_PrestigeConfirm",
		targetTag      = "Tutorial_PrestigeConfirm",

		-- Now we unlock the actual Confirm Button
		unlockTags     = {"Tutorial_PrestigeConfirm"},
		unlockActions  = {"Action_PrestigeConfirm"},

		-- If they close the menu by mistake, the pointer will snap back to the HUD Prestige button!
		menuTag        = "Tutorial_PrestigePanel",
		menuOpenBtnTag = "Tutorial_PrestigeButton",
		
		bannerTitle  = "Confirm Prestige",
		bannerBody   = "Click 'Prestige Now' to get your Soul Auras and increase your earnings permentantly.",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(215, 121, 255),
	},
	[23] = {
		id           = "a1_post_prestige_pan",
		action       = "Action_Wait", -- ✨ THE FIX: Wait for collection instead of clicking!
		duration     = 0,             -- ✨ Auto-advances instantly when the condition is met
		allowClicking = true, -- ✨ THE FIX
		cameraTrackMode = "FollowPhysicsAura", 
		cameraOffset    = Vector3.new(0, 15, 25), 

		requireStepGoldenAuras = 10, -- ✨ THE FIX: Only counts GA collected DURING this step!
	
		bannerTitle  = "Golden Auras",
		bannerBody   = "Collect Auras that spawn from the Producer OR claim your mailbox rewards!",

		icon         = "rbxassetid://4483362458",
		color        = Color3.fromRGB(255, 215, 0),
	},

	-- ✨ STEP 24: Farm for the next area
	[24] = {
		id           = "a1_farm_area2",
		action       = "Action_Wait", -- ✨ THE FIX: Monitor passively instead of requiring a click!
		duration     = 0,             -- ✨ Auto-advances instantly when the condition is met
		allowClicking = true, -- ✨ THE FIX
		requireFarmEval = 50000, 
		unlockTags    = {"Tutorial_TravelButton", "Tutorial_TravelCloseBtn"},
		unlockActions = {"Action_OpenTravel", "Action_CloseTravel"},
		bannerTitle  = "Reaching More Areas",
		bannerBody   = "Open the travel menu to unlock the next Area. Your farm evaluation is based on the total amount of money made in that area.",

		icon         = "rbxassetid://14924185885",
		color        = Color3.fromRGB(126, 255, 212),
	},

	-- ✨ STEP 25: Open Area Travel
	[25] = {
		id           = "a1_open_travel",
		action       = "Action_OpenTravel",
		targetTag    = "Tutorial_TravelButton",

		bannerTitle  = "New Area Unlocked!",
		bannerBody   = "Click the Area Travel button to open the travel menu.",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(100, 200, 255),
	},

	-- ✨ STEP 26: Browse to Area 2 (Click Right Arrow)
	[26] = {
		id             = "a1_travel_arrow",
		action         = "Action_ClickRightArrow",
		targetTag      = "Tutorial_RightArrow",

		unlockTags     = {"Tutorial_RightArrow"},
		unlockActions  = {"Action_ClickRightArrow", "Action_ClickLeftArrow"},

		menuTag        = "Tutorial_TravelPanel",
		menuOpenBtnTag = "Tutorial_TravelButton",
		fallbackStepId = "a1_open_travel", -- Sends them back if they closed the UI

		bannerTitle  = "Browse Areas",
		bannerBody   = "Click the Arrows to view the newly unlocked area and other areas.",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(150, 200, 255),
	},

	-- ✨ STEP 27: Confirm Travel
	[27] = {
		id             = "a1_confirm_travel",
		action         = "Action_TravelConfirm",
		targetTag      = "Tutorial_TravelConfirm",

		unlockTags     = {"Tutorial_TravelConfirm"},
		unlockActions  = {"Action_TravelConfirm"},

		menuTag        = "Tutorial_TravelPanel",
		menuOpenBtnTag = "Tutorial_TravelButton",
		fallbackStepId = "a1_open_travel",

		bannerTitle  = "Travel Now",
		bannerBody   = "Click TRAVEL to jump to the new Area!",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(107, 255, 161),
	},

	[28] = {
		id           = "a1_open_boosts",
		action       = "Action_OpenBoostShop",
		targetTag    = "Tutorial_BoostMenuBtn",

		unlockTags    = {"Tutorial_BoostMenuBtn", "Tutorial_BoostShopClose"},
		unlockActions = {"Action_OpenBoostShop", "Action_CloseBoostShop"},

		bannerTitle  = "Area Boosts and Multipliers",
		bannerBody   = "Auras in this area have much higher base values! Open the new Boosts menu.",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(75, 255, 174),
	},

	-- ✨ STEP 29: Buy Aura Spawner Boost
	[29] = {
		id           = "a1_buy_boost1",
		action       = "Action_BuyBoost_AuraRush",
		targetTag    = "Tutorial_BuyBoost_AuraRush",

		unlockTags    = {"Tutorial_BuyBoost_AuraRush"},
		unlockActions = {"Action_BuyBoost_AuraRush"},

		menuTag        = "Tutorial_BoostShopPanel",
		menuOpenBtnTag = "Tutorial_BoostMenuBtn",

		requireBoostBought = { id = "AuraRush", count = 1 },
		duration     = 0,

		bannerTitle  = "Buy a Boost",
		bannerBody   = "Buy the Aura Rush Boost using your Golden Auras",

		icon         = "rbxassetid://4483362458",
		color        = Color3.fromRGB(114, 213, 255),
	},

	-- ✨ STEP 30: Use Aura Spawner Boost
	[30] = {
		id           = "a1_use_boost1",
		action       = "Action_UseBoost_AuraRush",
		targetTag    = "Tutorial_UseBoost_AuraRush",

		unlockTags    = {"Tutorial_UseBoost_AuraRush"},
		unlockActions = {"Action_UseBoost_AuraRush"},

		menuTag        = "Tutorial_BoostShopPanel",
		menuOpenBtnTag = "Tutorial_BoostMenuBtn",

		requireBoostUsed = { id = "AuraRush", count = 1 },
		duration     = 0,

		bannerTitle  = "Activate the Boost",
		bannerBody   = "Click Activate to use your new Aura Rush boost!",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(103, 111, 255),
	},

	-- ✨ STEP 31: Spawn 30 Auras (Under the effect)
	[31] = {
		id           = "a1_spawn_30",
		action       = "Action_Wait", 
		targetTag    = "Tutorial_ClickButton",
		allowClicking = true, -- ✨ THE FIX
		requireCubesProduced = 30,
		duration     = 0, 

		bannerTitle  = "Double Spawn Speed",
		bannerBody   = "Your boost is now active. Produce 30 Auras with the increased spawn speed.",

		icon         = "rbxassetid://14914018910",
		color        = Color3.fromRGB(105, 255, 200),
	},

	-- ✨ STEP 32: Open Boost Shop Again
	[32] = {
		id           = "a1_open_boosts2",
		action       = "Action_OpenBoostShop",
		targetTag    = "Tutorial_BoostMenuBtn",

		bannerTitle  = "Buy More Boosts",
		bannerBody   = "Open up the boosts menu again to buy more boosts.",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(106, 255, 188),
	},

	-- ✨ STEP 33: Buy 3 Aura Spawners
	[33] = {
		id           = "a1_buy_boost3",
		action       = "Action_BuyBoost_AuraRush",
		targetTag    = "Tutorial_BuyBoost_AuraRush",

		menuTag        = "Tutorial_BoostShopPanel",
		menuOpenBtnTag = "Tutorial_BoostMenuBtn",

		requireBoostBought = { id = "AuraRush", count = 5 },
		duration     = 0,

		bannerTitle  = "Buy More Aura Rush Boosts",
		bannerBody   = "Buy 5 more Aura Rush Boosts. Note Boosts can stack for even faster productiona and MONEY.",

		icon         = "rbxassetid://4483362458",
		color        = Color3.fromRGB(101, 255, 199),
	},

	-- ✨ STEP 34: Produce 150 Auras
	[34] = {
		id           = "a1_spawn_150",
		action       = "Action_Wait",
		targetTag    = "Tutorial_ClickButton",
		allowClicking = true, 
		requireCubesProduced = 150,
		duration     = 0, 

		bannerTitle  = "Quick Production",
		bannerBody   = "Produce 150 Auras. Remember to use boosts to help you. Boosts Stack Multiplicative so they are extremely powerful!",

		icon         = "rbxassetid://14914018910",
		color        = Color3.fromRGB(97, 255, 229),
	},

	-- ✨ STEP 35: Unlock Achievements
	[35] = {
		id           = "a1_open_achievements",
		action       = "Action_OpenAchievements",
		targetTag    = "Tutorial_AchieveMenuBtn",

		unlockTags    = {"Tutorial_AchieveMenuBtn"},
		unlockActions = {"Action_OpenAchievements"},

		bannerTitle  = "Achievements Unlocked!",
		bannerBody   = "Open the Achievements menu.",

		icon         = "rbxassetid://14923131909",
		color        = Color3.fromRGB(255, 158, 60),
	}
}

function TutorialConfig.GetStepByIndex(index)
	return TutorialConfig.Steps[index]
end

function TutorialConfig.GetStepById(id)
	for _, step in ipairs(TutorialConfig.Steps) do
		if step.id == id then return step end
	end
	return nil
end

return TutorialConfig
