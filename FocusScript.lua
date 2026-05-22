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
local UIConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UIConfig"))
local UpdateHUDBridge = BridgeNet2.ClientBridge("UpdateHUD")

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local ClaimChallenge = RemoteEvents:WaitForChild("ClaimChallenge")
local ClaimAuraIndex = RemoteEvents:WaitForChild("ClaimAuraIndex")
local ClaimBadge = RemoteEvents:WaitForChild("ClaimBadge")
local AuraDiscovered = RemoteEvents:WaitForChild("AuraDiscovered", 5)

-- ✨ UI MUTUAL EXCLUSION
local ForceCloseUI = ReplicatedStorage:FindFirstChild("ForceCloseUI") or Instance.new("BindableEvent")
ForceCloseUI.Name = "ForceCloseUI"
if not ForceCloseUI.Parent then ForceCloseUI.Parent = ReplicatedStorage end

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

local AchieveBtn = Instance.new("ImageButton", Faded2); AchieveBtn.Name = "AchievementButton"; AchieveBtn.Size = UDim2.new(0.85, 0, 0.85, 0); AchieveBtn.BackgroundColor3 = T.buttonSecondary; AchieveBtn.BorderSizePixel = 0; AchieveBtn.LayoutOrder = 1; Instance.new("UICorner", AchieveBtn).CornerRadius = UDim.new(0.5, 0); Instance.new("UIAspectRatioConstraint", AchieveBtn).AspectRatio = 1.0; local btnStroke = Instance.new("UIStroke", AchieveBtn); btnStroke.Color = Color3.fromRGB(255, 243, 111); btnStroke.Thickness = 2; local btnIcon = Instance.new("ImageLabel", AchieveBtn); btnIcon.Size = UDim2.new(0.7, 0, 0.7, 0); btnIcon.Position = UDim2.new(0.15, 0, 0.15, 0); btnIcon.BackgroundTransparency = 1; btnIcon.ScaleType = Enum.ScaleType.Fit; btnIcon.Image = UIConfig.Icons.AchieveButton or "rbxassetid://14923131909"
CollectionService:AddTag(AchieveBtn, "Tutorial_AchieveMenuBtn")

local Panel = Instance.new("Frame", mainHUD)
Panel.Name = "AchievementPanel"
Panel.Size = UDim2.new(1, -110, 0.85, 0) 
Panel.Position = UDim2.new(0, -500, 0.5, 0) 
Panel.AnchorPoint = Vector2.new(0, 0.5) 
Panel.BackgroundColor3 = T.panelBG
Panel.BorderSizePixel = 0
Panel.Visible = false
Panel.ZIndex = 40
Panel.ClipsDescendants = true
Instance.new("UICorner", Panel).CornerRadius = UDim.new(0, 12)
Instance.new("UISizeConstraint", Panel).MaxSize = Vector2.new(500, 650)
local panelStroke = Instance.new("UIStroke", Panel); panelStroke.Color = T.panelStroke; panelStroke.Thickness = 2
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

MakeTab("Challenges", "Boosts", UIConfig.Icons.AchieveTabChallenges or "rbxassetid://14916846070"); MakeTab("Index", "Auras", UIConfig.Icons.AchieveTabIndex or "rbxassetid://14916846070"); MakeTab("Badges", "Badges", UIConfig.Icons.AchieveTabBadges or "rbxassetid://14916846070"); MakeTab("Leaderboard", "Leaderboard", UIConfig.Icons.AchieveTabLeaderboard or "rbxassetid://14916846070"); MakeTab("Settings", "Settings", UIConfig.Icons.AchieveTabSettings or "rbxassetid://14923131909") 

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

local function CreateInteractiveRow(parent, id, claimActionId, onClaimCallback)
	local row = parent:FindFirstChild(id)
	if not row then
		row = Instance.new("TextButton", parent); row.Name = id; row.Text = ""; row.AutoButtonColor = false; row.Size = UDim2.new(1, -8, 0, 64); row.BackgroundColor3 = T.cardBG; Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8); local stroke = Instance.new("UIStroke", row); stroke.Name = "Stroke"; stroke.Thickness = 1; local icon = Instance.new("ImageLabel", row); icon.Name = "Icon"; icon.Size = UDim2.new(0, 40, 0, 40); icon.Position = UDim2.new(0, 12, 0.5, -20); icon.ScaleType = Enum.ScaleType.Fit; Instance.new("UICorner", icon).CornerRadius = UDim.new(1, 0)

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
	-- ✨ FIRE MUTUAL EXCLUSION SIGNAL
	ForceCloseUI:Fire("AchievementPanel")

	PlayUI(SoundConfig.UIOpen or "")
	panelOpen = true
	Panel.Visible = true
	Panel.Size = UDim2.new(1, -110, 0.85, 0)
	activeTab = tabName
	activeTabText = hoverText
	HoverLabel.Text = activeTabText
	for k, t in pairs(tabBtns) do t.btn.BackgroundColor3 = (k == activeTab) and T.accentGold or T.buttonSecondary; t.stroke.Color = (k == activeTab) and T.bodyText or T.panelStroke end
	for k, s in pairs(scrolls) do s.Visible = (k == activeTab) end
	RefreshData(); RefreshStats(); TitleLabel.Text = (tabName == "Settings") and "SETTINGS" or "PROGRESSION"

	TweenService:Create(Panel, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0, 95, 0.5, 0) }):Play()
	UITheme.SetMenuVisible(true)
end

local function ClosePanel()
	if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_CloseAchievements") then return end
	PlayUI(SoundConfig.UIClose or "")
	panelOpen = false
	TweenService:Create(Panel, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.new(0, -500, 0.5, 0) }):Play()
	UITheme.SetMenuVisible(false)
	task.delay(0.25, function() if not panelOpen then Panel.Visible = false end end)
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

ForceCloseUI.Event:Connect(function(exceptionPanel)
	if exceptionPanel ~= "AchievementPanel" and panelOpen then 
		ClosePanel() 
	end 
end)

--serverscriptservice
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local BadgeService = game:GetService("BadgeService")

local GameManager = require(ServerScriptService.GameManager)
local AchievementConfig = require(ReplicatedStorage.Modules.AchievementConfig)
local BridgeNet2 = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))
local UpdateHUDBridge = BridgeNet2.ServerBridge("UpdateHUD")

local Events = {"ClaimChallenge", "ClaimAuraIndex", "ClaimBadge"}
for _, name in ipairs(Events) do
	if not ReplicatedStorage.RemoteEvents:FindFirstChild(name) then
		local re = Instance.new("RemoteEvent")
		re.Name = name
		re.Parent = ReplicatedStorage.RemoteEvents
	end
end

-- 1. CLAIM CHALLENGE (Unlocks Boosts)
ReplicatedStorage.RemoteEvents.ClaimChallenge.OnServerEvent:Connect(function(player, challengeId)
	local data = GameManager.GetData(player.UserId)
	if not data then return end

	local challenge = nil
	for _, chal in ipairs(AchievementConfig.Challenges) do
		if chal.id == challengeId then challenge = chal; break end
	end
	if not challenge then return end

	data.claimedChallenges = data.claimedChallenges or {}
	if data.claimedChallenges[challengeId] then return end

	local currentAmount = data[challenge.statKey] or 0
	if currentAmount >= challenge.goal then
		data.claimedChallenges[challengeId] = true
		UpdateHUDBridge:Fire(player, { claimedChallenges = data.claimedChallenges })
	end
end)

-- 2. CLAIM AURA INDEX (Awards Golden Auras)
ReplicatedStorage.RemoteEvents.ClaimAuraIndex.OnServerEvent:Connect(function(player, areaIdx, tierName)
	local data = GameManager.GetData(player.UserId)
	if not data then return end

	data.discoveredTiers = data.discoveredTiers or {}
	data.claimedAuras = data.claimedAuras or {}
	local auraKey = areaIdx .. "_" .. tierName

	if data.discoveredTiers[auraKey] and not data.claimedAuras[auraKey] then
		data.claimedAuras[auraKey] = true
		local reward = AchievementConfig.AuraTierRewards[tierName] or 5
		data.goldenAuras = (data.goldenAuras or 0) + reward
		UpdateHUDBridge:Fire(player, { claimedAuras = data.claimedAuras, goldenAuras = data.goldenAuras })
	end
end)

-- 3. CLAIM BADGE (Fires BadgeService safely)
ReplicatedStorage.RemoteEvents.ClaimBadge.OnServerEvent:Connect(function(player, badgeIndex)
	local data = GameManager.GetData(player.UserId)
	if not data then return end

	local badge = AchievementConfig.Badges[badgeIndex]
	if not badge then return end

	data.claimedBadges = data.claimedBadges or {}
	if data.claimedBadges[badgeIndex] then return end

	local currentAmount = data[badge.statKey] or 0
	if currentAmount >= badge.goal then
		data.claimedBadges[badgeIndex] = true

		local badgeId = tonumber(badge.id)
		if badgeId and badgeId > 0 then
			task.spawn(function()
				local fetchSuccess, badgeInfo = pcall(function() return BadgeService:GetBadgeInfoAsync(badgeId) end)
				if fetchSuccess and badgeInfo.IsEnabled then
					local awardSuccess, result = pcall(function() return BadgeService:AwardBadge(player.UserId, badgeId) end)
					if not awardSuccess then warn("Error awarding badge:", result) end
				end
			end)
		end
		UpdateHUDBridge:Fire(player, { claimedBadges = data.claimedBadges })
	end
end)

--ReplicatedStorage
-- AchievementConfig
-- Location: ReplicatedStorage > Modules > AchievementConfig

local AchievementConfig = {}

AchievementConfig.AuraTierRewards = {
	["Common"]    = 5,
	["Uncommon"]  = 10,
	["Rare"]      = 15,
	["Epic"]      = 25,
	["Legendary"] = 50
}

AchievementConfig.Challenges = {
	-- ✨ THE FIX: Matched boostId to "HatcheryRefill"
	{ id = "unlock_fastrefill", boostId = "HatcheryRefill", title = "Aura Tycoon", desc = "Spawn 1,000 Auras", iconId = "rbxassetid://14916846070", statKey = "totalCubesProduced", goal = 1000, rewardText = "Unlocks: Fast Refill Boost" },

	-- ✨ THE FIX: Matched boostId to "SpawnBoost"
	{ id = "unlock_spawnboost", boostId = "SpawnBoost", title = "Explorer", desc = "Reach Area 2", iconId = "rbxassetid://14916846070", statKey = "currentArea", goal = 2, rewardText = "Unlocks: Value Boost" },

	{ id = "unlock_soulboost", boostId = "SoulBoost", title = "Soul Searcher", desc = "Prestige 5 Times", iconId = "rbxassetid://14916846070", statKey = "prestigeCount", goal = 5, rewardText = "Unlocks: Soul Boost" }
}

AchievementConfig.Badges = {
	{ id = 0, title = "First Prestige", desc = "Prestige for the first time.", iconId = "rbxassetid://14916846070", statKey = "prestigeCount", goal = 1 }, 
	{ id = 0, title = "Millionaire", desc = "Hold $1,000,000 at once.", iconId = "rbxassetid://14916846070", statKey = "currency", goal = 1000000 }, 
}

function AchievementConfig.IsBoostUnlocked(boostId, latestStats)
	for _, challenge in ipairs(AchievementConfig.Challenges) do
		if challenge.boostId == boostId then
			local claimed = latestStats.claimedChallenges or {}
			if not claimed[challenge.id] then return false, "Claim in Progress Menu!" end
		end
	end
	return true, ""
end

return AchievementConfig
