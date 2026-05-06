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

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainHUD   = playerGui:WaitForChild("MainHUD")
local Faded2 = mainHUD:WaitForChild("Faded2") 
local panelOpen = false
local activeTab = "Challenges"
local activeTabText = "Boosts" -- For the hover label
local latestStats = {}

local function PlayUI(id) if shared.PlayUISound then shared.PlayUISound(id) end end

---------------------------------------------------------------
-- 1. THE CIRCULAR BUTTON (Right Side of Faded2)
---------------------------------------------------------------
local AchieveBtn = Instance.new("ImageButton", Faded2) -- ✨ PARENTED TO FADED2
AchieveBtn.Name = "AchievementButton"
AchieveBtn.Size = UDim2.new(0.85, 0, 0.85, 0) -- ✨ Takes up 85% of Faded2's height
AchieveBtn.Position = UDim2.new(0.95, 0, 0.5, 0) -- ✨ Placed on the far right
AchieveBtn.AnchorPoint = Vector2.new(1, 0.5) -- ✨ Anchored perfectly center-right
AchieveBtn.BackgroundColor3 = T.buttonSecondary
AchieveBtn.BorderSizePixel = 0
AchieveBtn.AutoButtonColor = false
AchieveBtn.ZIndex = 15
Instance.new("UICorner", AchieveBtn).CornerRadius = UDim.new(0.5, 0)

-- ✨ MOBILE FIX: Forces it to stay a perfect circle no matter the screen size!
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

	-- ✨ TUTORIAL TAG! Now your tutorial config can target "ChallengesTab", "IndexTab", etc.
	btn:SetAttribute("TutorialTarget", name .. "Tab")

	local tStroke = Instance.new("UIStroke", btn)
	tStroke.Color = T.panelStroke; tStroke.Thickness = 2

	local icon = Instance.new("ImageLabel", btn)
	icon.Size = UDim2.new(0.6, 0, 0.6, 0); icon.Position = UDim2.new(0.2, 0, 0.2, 0); icon.BackgroundTransparency = 1; icon.ScaleType = Enum.ScaleType.Fit; icon.Image = iconId
	tabBtns[name] = {btn = btn, stroke = tStroke}

	-- Mobile-responsive Scrolling Frame
	local sf = Instance.new("ScrollingFrame", Panel)
	sf.Size = UDim2.new(1, -20, 1, -135); sf.Position = UDim2.new(0, 10, 0, 125); sf.BackgroundTransparency = 1; sf.BorderSizePixel = 0; sf.ScrollBarThickness = 4; sf.Visible = false
	local layout = Instance.new("UIListLayout", sf); layout.Padding = UDim.new(0, 8); layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function() sf.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 10) end)
	scrolls[name] = sf

	-- Dynamic Hover Text Logic
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

-- 🖼️ PLACEHOLDERS: Replace "rbxassetid://14916846070" with your actual icon IDs!
MakeTab("Challenges", "Boosts", "rbxassetid://14916846070")
MakeTab("Index", "Auras", "rbxassetid://14916846070")
MakeTab("Badges", "Badges", "rbxassetid://14916846070")
MakeTab("Leaderboard", "Top 10", "rbxassetid://14916846070")

---------------------------------------------------------------
-- 4. DYNAMIC CONTENT BUILDER (SMART UPDATES)
---------------------------------------------------------------
local function UpdateOrCreateRow(parent, id, title, desc, hoverDesc, iconImage, iconColor, statusText, statusColor)
	-- Look for an existing row so we don't delete it while the player is hovering!
	local row = parent:FindFirstChild(id)

	if not row then
		-- Create it for the first time
		row = Instance.new("TextButton", parent) -- TextButtons track hovering much better than Frames!
		row.Name = id; row.Text = ""; row.AutoButtonColor = false
		row.Size = UDim2.new(1, -8, 0, 64); row.BackgroundColor3 = T.cardBG
		Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)

		local stroke = Instance.new("UIStroke", row); stroke.Name = "Stroke"; stroke.Thickness = 1

		local icon = Instance.new("ImageLabel", row); icon.Name = "Icon"; icon.Size = UDim2.new(0, 40, 0, 40); icon.Position = UDim2.new(0, 12, 0.5, -20); icon.ScaleType = Enum.ScaleType.Fit; Instance.new("UICorner", icon).CornerRadius = UDim.new(1, 0)

		local tLbl = Instance.new("TextLabel", row); tLbl.Name = "Title"; tLbl.Size = UDim2.new(0.6, 0, 0, 20); tLbl.Position = UDim2.new(0, 64, 0, 10); tLbl.BackgroundTransparency = 1; tLbl.TextColor3 = T.bodyText; tLbl.TextScaled = true; tLbl.Font = T.font; tLbl.TextXAlignment = Enum.TextXAlignment.Left
		local dLbl = Instance.new("TextLabel", row); dLbl.Name = "Desc"; dLbl.Size = UDim2.new(0.6, 0, 0, 16); dLbl.Position = UDim2.new(0, 64, 0, 32); dLbl.BackgroundTransparency = 1; tLbl.TextColor3 = T.subText; dLbl.TextScaled = true; dLbl.Font = T.fontBody; dLbl.TextXAlignment = Enum.TextXAlignment.Left
		local sLbl = Instance.new("TextLabel", row); sLbl.Name = "Status"; sLbl.Size = UDim2.new(0, 80, 0, 24); sLbl.Position = UDim2.new(1, -90, 0.5, -12); sLbl.BackgroundTransparency = 1; sLbl.TextScaled = true; sLbl.Font = T.font; sLbl.TextXAlignment = Enum.TextXAlignment.Right

		UITheme.Apply(row, "Card")

		-- ✨ SMART HOVER LOGIC
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

	-- ✨ UPDATE THE ROW LIVE (Without deleting it)
	row:SetAttribute("NormalDesc", desc)
	row:SetAttribute("HoverDesc", hoverDesc)

	row.Title.Text = title
	row.Status.Text = statusText
	row.Status.TextColor3 = statusColor
	row.Icon.Image = iconImage
	row.Icon.BackgroundColor3 = iconColor
	row.Stroke.Color = iconColor

	-- Keep the correct text showing based on if their mouse is currently on it
	if row:GetAttribute("IsHovering") and hoverDesc and hoverDesc ~= "" then
		row.Desc.Text = hoverDesc; row.Desc.TextColor3 = T.accentGold
	else
		row.Desc.Text = desc; row.Desc.TextColor3 = T.subText
	end
end

local function RefreshData()
	-- 1. Build Challenges
	for i, chal in ipairs(AchievementConfig.Challenges) do
		local current = latestStats[chal.statKey] or 0
		local isDone = current >= chal.goal
		local statusText = isDone and "UNLOCKED" or (current .. " / " .. chal.goal)
		local statusColor = isDone and T.buttonGreen or T.subText

		local hoverReq = not isDone and ("Requires: " .. chal.desc) or "Boost Unlocked!"

		UpdateOrCreateRow(scrolls["Challenges"], "Chal_"..i, chal.title, chal.rewardText, hoverReq, chal.iconId, T.accentBlue, statusText, statusColor)
	end

	-- 2. Build Aura Index
	for i, tier in ipairs(TierConfig.Tiers) do
		local discovered = (latestStats.totalCubesProduced or 0) > 0
		if tier.name == "Legendary" then discovered = (latestStats.totalLegendaryCubes or 0) > 0 end
		local statusText = discovered and "Found" or "???"
		local statusColor = discovered and T.buttonGreen or T.buttonRed
		UpdateOrCreateRow(scrolls["Index"], "Index_"..i, tier.name .. " Aura", "Multiplier: " .. tier.multiplier .. "x", nil, "rbxassetid://0", tier.color, statusText, statusColor)
	end

	-- 3. Build Badges
	for i, badge in ipairs(AchievementConfig.Badges) do
		UpdateOrCreateRow(scrolls["Badges"], "Badge_"..i, badge.title, badge.desc, nil, badge.iconId, T.accentGold, "BADGE", T.subText)
	end

	-- 4. Leaderboard Placeholder
	UpdateOrCreateRow(scrolls["Leaderboard"], "Leader_1", "1. MoldySugar2205", "Total Earnings", nil, "rbxassetid://0", T.accentGold, "Top Player", T.accentGreen)
end

UpdateHUD.OnClientEvent:Connect(function(stats)
	for key, value in pairs(stats) do latestStats[key] = value end
	if panelOpen then RefreshData() end
end)

---------------------------------------------------------------
-- 5. BUTTON JUICE & OPEN/CLOSE
---------------------------------------------------------------
local function AddButtonJuice(btn)
	local scale = btn:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", btn)
	btn.MouseEnter:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15), {Scale = 1.08}):Play() end)
	btn.MouseLeave:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15), {Scale = 1}):Play() end)
	btn.MouseButton1Down:Connect(function() TweenService:Create(scale, TweenInfo.new(0.1), {Scale = 0.9}):Play() end)
	btn.MouseButton1Up:Connect(function() TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), {Scale = 1.08}):Play() end)
end

AddButtonJuice(AchieveBtn); AddButtonJuice(CloseBtn)

-- Attach juice to the new circular tabs
for _, t in pairs(tabBtns) do AddButtonJuice(t.btn) end

AchieveBtn.MouseButton1Down:Connect(function()
	if panelOpen then
		-- Close Logic
		PlayUI(SoundConfig.UIClose or "")
		panelOpen = false
		TweenService:Create(Panel, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Size = UDim2.new(0.85, 0, 0, 0)}):Play()
		UITheme.SetMenuVisible(false)
		task.delay(0.25, function() Panel.Visible = false end)
	else
		-- Open Logic
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

-- ClickHandler
-- Location: StarterPlayer > StarterPlayerScripts > ClickHandler

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")

local AdminConfig = require(ReplicatedStorage.Modules.AdminConfig)
local UITheme = require(ReplicatedStorage.Modules.UITheme)
local AreaRegistry = require(ReplicatedStorage.Modules.AreaRegistry) 
local NumberFormatter = require(ReplicatedStorage.Modules.NumberFormatter)

local ProduceAura = ReplicatedStorage.RemoteEvents:WaitForChild("ProduceAura")
local AuraSpawned = ReplicatedStorage.RemoteEvents:WaitForChild("AuraSpawned")
local UpdateHatchery = ReplicatedStorage.RemoteEvents:WaitForChild("UpdateHatchery")
local ForceStopHold = ReplicatedStorage.RemoteEvents:WaitForChild("ForceStopHold")
local HabitatFull = ReplicatedStorage.RemoteEvents:WaitForChild("HabitatFull")
local UpdateMultiplier = ReplicatedStorage:WaitForChild("UpdateMultiplier")
local HabitatFullEvent = ReplicatedStorage:WaitForChild("HabitatFullEvent")
local CubeMutatedBatch = ReplicatedStorage.RemoteEvents:WaitForChild("CubeMutatedBatch")
local CubeSmushed = ReplicatedStorage.RemoteEvents:WaitForChild("CubeSmushed")
local CubeStored = ReplicatedStorage.RemoteEvents:WaitForChild("CubeStored") 

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local holding = false
local fireRate = AdminConfig.FireRate
local holdStart = nil
local hatcheryEmpty = false
local habitatFull = false

local currentPassiveInterval = AdminConfig.PassiveInterval

local ClickButton = playerGui:WaitForChild("MainHUD"):WaitForChild("ClickButton")
local HatcheryBar = playerGui:WaitForChild("MainHUD"):WaitForChild("HatcheryBar")
local HatcheryFill = HatcheryBar:WaitForChild("Fill")
local HatcheryLabel = HatcheryBar:WaitForChild("Label")

local clickScale = ClickButton:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", ClickButton)
local clickStroke = ClickButton:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke", ClickButton)
clickStroke.Color = Color3.fromRGB(255, 215, 0)
clickStroke.Thickness = 0
local basePos = ClickButton.Position
local tiltSide = 1

local Camera = workspace.CurrentCamera
local defaultFOV = 70 
local lastMilestone = 1

local MilestoneData = AdminConfig.MilestoneData

local playerMultSpeed = 1.0 
local playerMaxTier = 5     
local lastTierIndex = 1

local function FormatNumber(n)
	return NumberFormatter.Format(n)
end	

---------------------------------------------------------------
-- AURA MODEL FOLDERS & INSTANTIATION
---------------------------------------------------------------
local VFXFolder = ReplicatedStorage:FindFirstChild("VFX")
local cubeDataMap = {}

local TierScale = {
	Common    = 1.0,
	Uncommon  = 1.15,
	Rare      = 1.3,
	Epic      = 1.5,
	Legendary = 1.75,
}

local function CloneAuraModel(tierName, currentArea)
	currentArea = currentArea or 1
	local clone = AreaRegistry.FetchAuraModel(currentArea, tierName)
	if clone and not clone.PrimaryPart then
		warn("[Aura] Model '" .. tierName .. "' has no PrimaryPart set! Set PrimaryPart to the main BasePart for reliable positioning.")
	end
	return clone
end

local function CreatePlaceholderPart(color, glow)
	local part = Instance.new("Part")
	part.Size = Vector3.new(1.5, 1.5, 1.5)
	part.Color = color
	part.Anchored = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	if glow then
		local light = Instance.new("PointLight")
		light.Brightness = 3
		light.Range = 8
		light.Color = color
		light.Parent = part
	end
	return part
end

local function GetRootPart(instance)
	if instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart")
	end
	return instance
end

-- ✨ APPLIES HEAVY, NON-BOUNCY PHYSICS ✨
local function ApplyHeavyPhysics(instance)
	-- Density (100 = max heavy), Friction (0.3 = slides down funnels), Elasticity (0 = no bounce)
	local heavyProps = PhysicalProperties.new(100, 0.3, 0, 1, 100) 

	if instance:IsA("BasePart") then
		instance.CustomPhysicalProperties = heavyProps
	elseif instance:IsA("Model") then
		for _, part in ipairs(instance:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CustomPhysicalProperties = heavyProps
			end
		end
	end
end

local function SpawnAuraInstance(tierName, color, glow, position, currentArea)
	local auraModel = CloneAuraModel(tierName, currentArea)
	if auraModel then
		auraModel:PivotTo(CFrame.new(position))
		auraModel.Parent = workspace
		if auraModel.PrimaryPart then
			auraModel.PrimaryPart.Anchored = false
			auraModel.PrimaryPart.CanCollide = true
			auraModel.PrimaryPart.CollisionGroup = "Auras"
		end
		ApplyHeavyPhysics(auraModel)
		return auraModel, true
	else
		local part = CreatePlaceholderPart(color, glow)
		part.Position = position
		part.CollisionGroup = "Auras"
		part.Parent = workspace
		ApplyHeavyPhysics(part)
		return part, false
	end
end

local function ScaleAura(instance, tierName, animated, fromTierName)
	local targetScale = TierScale[tierName] or 1.0
	local fromScale = fromTierName and (TierScale[fromTierName] or 1.0) or nil

	if instance:IsA("Model") then
		if animated then
			local scaleProxy = Instance.new("NumberValue")
			scaleProxy.Value = fromScale or 1.0

			local scaleTween = TweenService:Create(scaleProxy, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Value = targetScale
			})

			local conn
			conn = scaleProxy.Changed:Connect(function(val)
				if instance and instance.Parent then
					pcall(function() instance:ScaleTo(val) end)
				else
					conn:Disconnect()
				end
			end)

			scaleTween:Play()
			scaleTween.Completed:Connect(function()
				scaleProxy:Destroy()
				if conn then conn:Disconnect() end
			end)
		else
			pcall(function() instance:ScaleTo(targetScale) end)
		end
	elseif instance:IsA("BasePart") then
		local baseSize = 1.5
		local targetSize = Vector3.new(1, 1, 1) * (baseSize * targetScale)
		if animated then
			if fromScale then instance.Size = Vector3.new(1, 1, 1) * (baseSize * fromScale) end
			TweenService:Create(instance, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = targetSize
			}):Play()
		else
			instance.Size = targetSize
		end
	end
end

---------------------------------------------------------------
-- VFX SYSTEM
---------------------------------------------------------------
local function PlayVFX(effectName, position, duration)
	if not VFXFolder then return end
	local template = VFXFolder:FindFirstChild(effectName)
	if not template then return end

	local vfx = template:Clone()

	if vfx:IsA("Model") then vfx:PivotTo(CFrame.new(position))
	elseif vfx:IsA("BasePart") then vfx.Position = position end

	for _, obj in ipairs(vfx:GetDescendants()) do
		if obj:IsA("BasePart") then
			obj.Anchored = true; obj.Transparency = 1; obj.CanCollide = false; obj.CastShadow = false
		end
	end

	if vfx:IsA("BasePart") then
		vfx.Anchored = true; vfx.Transparency = 1; vfx.CanCollide = false; vfx.CastShadow = false
	end

	vfx.Parent = workspace

	for _, emitter in ipairs(vfx:GetDescendants()) do
		if emitter:IsA("ParticleEmitter") then
			emitter.Enabled = true
			emitter:Emit(emitter:GetAttribute("BurstCount") or 15)
		end
	end

	task.delay((duration or 1.0) * 0.5, function()
		if vfx and vfx.Parent then
			for _, emitter in ipairs(vfx:GetDescendants()) do
				if emitter:IsA("ParticleEmitter") then emitter.Enabled = false end
			end
		end
	end)

	Debris:AddItem(vfx, duration or 1.5)
end

---------------------------------------------------------------
-- GAMEPLAY VISUAL LOGIC
---------------------------------------------------------------
local function GetCurrentMultiplier()
	if not holding or not holdStart then return 1.0, 1 end

	local holdTime = tick() - holdStart
	local effectiveTime = holdTime * playerMultSpeed 

	local currentTier = 1
	local nextTier = 1

	for i = 1, playerMaxTier do
		if effectiveTime >= MilestoneData[i].time then
			currentTier = i
			nextTier = math.min(i + 1, playerMaxTier)
		end
	end

	if currentTier == playerMaxTier then
		return MilestoneData[currentTier].mult, currentTier
	end

	local timePassedInTier = effectiveTime - MilestoneData[currentTier].time
	local timeNeededForNext = MilestoneData[nextTier].time - MilestoneData[currentTier].time
	local progressRatio = timePassedInTier / timeNeededForNext

	local currentMult = MilestoneData[currentTier].mult
	local nextMult = MilestoneData[nextTier].mult
	local smoothMult = currentMult + ((nextMult - currentMult) * progressRatio)

	return smoothMult, currentTier
end

local function PlayMilestoneSound(soundValue)
	if not soundValue or soundValue == "" then return end
	local sfxToPlay = nil

	if string.find(soundValue, "rbxassetid://") then
		sfxToPlay = Instance.new("Sound")
		sfxToPlay.SoundId = soundValue
		sfxToPlay.Volume = 0.6
	else
		local sfxFolder = ReplicatedStorage:FindFirstChild("SFX") or ReplicatedStorage:FindFirstChild("Sounds")
		if sfxFolder then
			local foundSound = sfxFolder:FindFirstChild(soundValue)
			if foundSound then
				sfxToPlay = foundSound:Clone()
				sfxToPlay.Volume = 0.6
			end
		end
	end

	if sfxToPlay then
		sfxToPlay.Parent = game:GetService("SoundService")
		sfxToPlay:Play()
		Debris:AddItem(sfxToPlay, sfxToPlay.TimeLength > 0 and sfxToPlay.TimeLength or 3)
	end
end

local function SpawnMilestonePopup(multFloor)
	local data = MilestoneData[multFloor]
	if not data then return end 

	PlayMilestoneSound(data.sound)

	local pop = Instance.new("TextLabel")
	pop.Text = data.name .. " (" .. string.format("%.1f", data.mult) .. "x)"
	pop.Font = Enum.Font.FredokaOne 
	pop.TextScaled = true
	pop.TextColor3 = data.color
	pop.BackgroundTransparency = 1
	pop.AnchorPoint = Vector2.new(0.5, 0.5)

	pop.Position = UDim2.new(
		ClickButton.Position.X.Scale, ClickButton.Position.X.Offset, 
		ClickButton.Position.Y.Scale - 0.15, ClickButton.Position.Y.Offset
	)
	pop.Parent = ClickButton.Parent

	local stroke = Instance.new("UIStroke", pop)
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(0, 0, 0)
	pop.Size = UDim2.new(0.1, 0, 0.02, 0) 

	TweenService:Create(pop, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0.35, 0, 0.08, 0),
		Position = UDim2.new(
			pop.Position.X.Scale, pop.Position.X.Offset, 
			ClickButton.Position.Y.Scale - 0.25, ClickButton.Position.Y.Offset
		)
	}):Play()

	task.delay(0.6, function()
		TweenService:Create(pop, TweenInfo.new(0.3), {TextTransparency = 1}):Play()
		TweenService:Create(stroke, TweenInfo.new(0.3), {Transparency = 1}):Play()
		task.delay(0.3, function() pop:Destroy() end)
	end)
end

local function UpdateButtonVisual()
	local col
	local mult = 1
	local currentTierIndex = 1

	if habitatFull then
		col = Color3.fromRGB(180, 60, 60)
	elseif not holding then
		col = Color3.fromRGB(255, 0, 0)
	else
		mult, currentTierIndex = GetCurrentMultiplier()
		col = MilestoneData[currentTierIndex].color
		UpdateMultiplier:Fire(mult)
	end

	local targetFOV = defaultFOV + (mult * 1.2)
	if not holding then targetFOV = defaultFOV end
	TweenService:Create(Camera, TweenInfo.new(0.3, Enum.EasingStyle.Sine), {FieldOfView = targetFOV}):Play()

	if holding then
		if currentTierIndex > lastTierIndex then
			if currentTierIndex > 1 then SpawnMilestonePopup(currentTierIndex) end
			lastTierIndex = currentTierIndex
		end
	else
		lastTierIndex = 1
	end

	TweenService:Create(ClickButton, TweenInfo.new(0.2), { BackgroundColor3 = col }):Play()

	if holding and not habitatFull then
		tiltSide = tiltSide * -1 
		if mult >= 5.0 then 
			TweenService:Create(ClickButton, TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true), {
				Rotation = 8 * tiltSide
			}):Play()
			clickStroke.Thickness = 12
			clickStroke.Transparency = 0
			TweenService:Create(clickStroke, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Thickness = 0, Transparency = 1}):Play()
		else
			TweenService:Create(ClickButton, TweenInfo.new(0.08, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, true), {
				Rotation = 3 * tiltSide
			}):Play()
		end
	elseif not holding then
		TweenService:Create(ClickButton, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Rotation = 0}):Play()
		TweenService:Create(clickScale, TweenInfo.new(0.15), {Scale = 1}):Play()
	end
end

local function UpdateHatcheryBar(current, max)
	local ratio = math.clamp(current / max, 0, 1)
	TweenService:Create(HatcheryFill, TweenInfo.new(0.1), { Size = UDim2.new(ratio, 0, 1, 0) }):Play()

	local color = Color3.fromRGB(255, 60, 60)
	if ratio > 0.5 then color = Color3.fromRGB(80, 220, 80)
	elseif ratio > 0.25 then color = Color3.fromRGB(255, 200, 0) end

	TweenService:Create(HatcheryFill, TweenInfo.new(0.1), { BackgroundColor3 = color }):Play()
	HatcheryLabel.Text = "Hatchery: " .. math.floor(current) .. " / " .. max
	hatcheryEmpty = (current <= 0)
end

local function FlashEmpty()
	TweenService:Create(HatcheryFill, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(255, 255, 255) }):Play()
	task.delay(0.1, function() TweenService:Create(HatcheryFill, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(255, 60, 60) }):Play() end)
end

local function ShowTierPopup(position, tierName, tierColor)
	local anchor = Instance.new("Part")
	anchor.Size = Vector3.new(0.1, 0.1, 0.1); anchor.Anchored = true; anchor.Transparency = 1; anchor.CanCollide = false
	anchor.Position = position + Vector3.new(0, 3, 0); anchor.Parent = workspace

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 120, 0, 40); bb.StudsOffset = Vector3.new(0, 2, 0)
	bb.AlwaysOnTop = false; bb.Adornee = anchor; bb.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0); label.BackgroundTransparency = 1
	label.Text = tierName:upper(); label.TextColor3 = tierColor; label.TextScaled = true
	label.Font = Enum.Font.GothamBold; label.TextStrokeTransparency = 0.3; label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.Parent = bb

	TweenService:Create(bb, TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffset = Vector3.new(0, 6, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(anchor, 2)
end

local function ShowCubeValue(position, value, color)
	local anchor = Instance.new("Part")
	anchor.Size = Vector3.new(0.1, 0.1, 0.1); anchor.Anchored = true; anchor.Transparency = 1; anchor.CanCollide = false
	anchor.Position = position + Vector3.new(math.random(-1, 1), 2, math.random(-1, 1)); anchor.Parent = workspace

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 80, 0, 25); bb.StudsOffset = Vector3.new(0, 0, 0)
	bb.AlwaysOnTop = false; bb.Adornee = anchor; bb.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0); label.BackgroundTransparency = 1
	label.Text = "Value: $" .. FormatNumber(value); label.TextColor3 = Color3.fromRGB(255, 255, 255); label.TextScaled = true
	label.Font = Enum.Font.Gotham; label.TextStrokeTransparency = 0.4; label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.Parent = bb

	TweenService:Create(bb, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffset = Vector3.new(0, 4, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(anchor, 1.5)
end

local function AttachPermanentRateLabel(auraInstance, baseValue, auraColor)
	local rootPart = GetRootPart(auraInstance)
	if not rootPart then return end

	local bb = Instance.new("BillboardGui")
	bb.Name = "PermanentRateLabel"
	bb.Size = UDim2.new(0, 90, 0, 25)
	bb.StudsOffset = Vector3.new(0, 0.5, 0) 
	bb.AlwaysOnTop = false
	bb.Adornee = rootPart

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1

	local ratePerSec = baseValue / currentPassiveInterval
	label.Text = "+$" .. FormatNumber(ratePerSec) .. "/sec"

	label.TextColor3 = auraColor or Color3.fromRGB(100, 255, 100) 
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextTransparency = 0.2 
	label.TextStrokeTransparency = 0.6 
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.Parent = bb

	bb.Parent = rootPart
	return label
end

---------------------------------------------------------------
-- ✨ DYNAMIC TRIGGER HOOKS (RECURSIVE) ✨
---------------------------------------------------------------
local AuraHolder = workspace:WaitForChild("AuraHolder")
local HabitatHolder = workspace:WaitForChild("HabitatHolder")

-- Fixes the hierarchy issue by searching up from the hit part
local function GetAuraCubeFromHit(hit)
	if hit:GetAttribute("AuraCube") then return hit end
	local p = hit.Parent
	if p and p:GetAttribute("AuraCube") then return p end
	local m = hit:FindFirstAncestorWhichIsA("Model")
	if m and m:GetAttribute("AuraCube") then return m end
	return nil
end

local function HookAuraModel(model)
	task.delay(0.1, function()
		local smush = model:FindFirstChild("SmushTrigger", true)
		if smush then
			smush.Touched:Connect(function(hit)
				local auraObj = GetAuraCubeFromHit(hit)
				if auraObj then
					for id, data in pairs(cubeDataMap) do
						if data.instance == auraObj then
							CubeSmushed:FireServer(id)

							local root = GetRootPart(auraObj)
							local pos = (root and root.Position) or hit.Position
							PlayVFX("Spawn", pos, 0.5) 

							if data.instance.Parent then data.instance:Destroy() end
							cubeDataMap[id] = nil
							break
						end
					end
				end
			end)
		end

		-- ✨ NEW: Force default Conveyor state on load (Forward ON, Backward OFF)
		local conveyer = model:FindFirstChild("ConveyerPath", true)
		if conveyer then
			local forwardBeam = conveyer:FindFirstChild("Foward") or conveyer:FindFirstChild("Forward")
			local backwardBeam = conveyer:FindFirstChild("Backward")

			if forwardBeam then forwardBeam.Enabled = not habitatFull end
			if backwardBeam then backwardBeam.Enabled = habitatFull end

			if habitatFull then
				conveyer.AssemblyLinearVelocity = Vector3.new(10, 0, 0)
			else
				conveyer.AssemblyLinearVelocity = Vector3.new(-5, 0, 0)
			end
		end

		-- Ensure StorageBelt is always securely locked moving forward
		local storageBelt = model:FindFirstChild("StorageBelt", true)
		if not storageBelt then
			local habModel = HabitatHolder:FindFirstChildWhichIsA("Model")
			if habModel then storageBelt = habModel:FindFirstChild("StorageBelt", true) end
		end

		if storageBelt then
			storageBelt.AssemblyLinearVelocity = Vector3.new(-5, 0, 0)
		end
	end)
end

local function HookHabitatModel(model)
	task.delay(0.1, function()
		local storage = model:FindFirstChild("StorageTrigger", true)
		if storage then
			storage.Touched:Connect(function(hit)
				local auraObj = GetAuraCubeFromHit(hit)
				if auraObj then
					for id, data in pairs(cubeDataMap) do
						if data.instance == auraObj and not data.isStored then
							data.isStored = true
							local label = auraObj:FindFirstChild("PermanentRateLabel", true)
							if label then label.Enabled = false end

							CubeStored:FireServer(id)
							break
						end
					end
				end
			end)
		end
	end)
end

AuraHolder.ChildAdded:Connect(function(child) if child:IsA("Model") then HookAuraModel(child) end end)
HabitatHolder.ChildAdded:Connect(function(child) if child:IsA("Model") then HookHabitatModel(child) end end)

for _, child in ipairs(AuraHolder:GetChildren()) do if child:IsA("Model") then HookAuraModel(child) end end
for _, child in ipairs(HabitatHolder:GetChildren()) do if child:IsA("Model") then HookHabitatModel(child) end end

---------------------------------------------------------------
-- INPUT CONTROLS
---------------------------------------------------------------
local trackedInputs = {}

local function EvaluateHolding()
	local hasInput = false
	for _, _ in pairs(trackedInputs) do hasInput = true; break end

	if hasInput and not holding then
		if hatcheryEmpty then FlashEmpty() return end
		if habitatFull then return end
		holding = true
		holdStart = tick()
		TweenService:Create(clickScale, TweenInfo.new(0.1, Enum.EasingStyle.Sine), {Scale = 0.9}):Play()
		ProduceAura:FireServer("start")
	elseif not hasInput and holding then
		holding = false
		holdStart = nil
		ProduceAura:FireServer("stop")
		UpdateButtonVisual()
		UpdateMultiplier:Fire(1.0)
	end
end

ClickButton.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		trackedInputs[input] = true; EvaluateHolding()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if trackedInputs[input] then trackedInputs[input] = nil; EvaluateHolding() end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if input.KeyCode == Enum.KeyCode.Space and not UserInputService:GetFocusedTextBox() then
		trackedInputs[input] = true; EvaluateHolding()
	end
end)

UserInputService.WindowFocusReleased:Connect(function()
	table.clear(trackedInputs); EvaluateHolding()
end)

ForceStopHold.OnClientEvent:Connect(function()
	table.clear(trackedInputs); EvaluateHolding()
end)

HabitatFull.OnClientEvent:Connect(function()
	habitatFull = true; 
	HabitatFullEvent:Fire(true); 
	table.clear(trackedInputs); 
	EvaluateHolding()
end)

HabitatFullEvent.Event:Connect(function(isFull)
	local auraModel = AuraHolder:FindFirstChildWhichIsA("Model")
	local conveyer = auraModel and auraModel:FindFirstChild("ConveyerPath", true)

	if isFull then 
		if conveyer then 
			conveyer.AssemblyLinearVelocity = Vector3.new(10, 0, 0) 

			-- ✨ TOGGLE BEAMS (Enable Backward, Disable Forward)
			local forwardBeam = conveyer:FindFirstChild("Foward") or conveyer:FindFirstChild("Forward")
			local backwardBeam = conveyer:FindFirstChild("Backward")

			if forwardBeam then forwardBeam.Enabled = false end
			if backwardBeam then backwardBeam.Enabled = true end
		end
	else 
		habitatFull = false; 
		UpdateButtonVisual() 
		if conveyer then 
			conveyer.AssemblyLinearVelocity = Vector3.new(-5, 0, 0) 

			-- ✨ TOGGLE BEAMS (Enable Forward, Disable Backward)
			local forwardBeam = conveyer:FindFirstChild("Foward") or conveyer:FindFirstChild("Forward")
			local backwardBeam = conveyer:FindFirstChild("Backward")

			if forwardBeam then forwardBeam.Enabled = true end
			if backwardBeam then backwardBeam.Enabled = false end
		end
	end
end)

UpdateHatchery.OnClientEvent:Connect(function(info)
	local finalMax = info.max
	local localHatchLvl = player:GetAttribute("LocalHatcheryLevel")

	if localHatchLvl then
		local UpgradeConfig = require(ReplicatedStorage.Modules.UpgradeConfig)
		local cfg = UpgradeConfig.GetUpgradeConfig("hatcheryCapacity")
		if cfg and cfg.apply then
			local predictedMax = cfg.apply({ upgrades = { hatcheryCapacity = localHatchLvl } })
			finalMax = math.max(info.max, predictedMax)
		end
	end
	UpdateHatcheryBar(info.current, finalMax)
end)

ReplicatedStorage.RemoteEvents:WaitForChild("UpdateHUD").OnClientEvent:Connect(function(stats)
	if stats.passiveInterval ~= nil then
		currentPassiveInterval = stats.passiveInterval
	end

	if stats.pendingAuras and stats.habitatCapacity then
		if stats.pendingAuras < stats.habitatCapacity and habitatFull then
			habitatFull = false; HabitatFullEvent:Fire(false); UpdateButtonVisual()
		end
	end

	if stats.upgrades then
		local tierUnlocks = {
			{ upgradeId = "unlockOmniMult",      tier = 10 },
			{ upgradeId = "unlockUniversalMult", tier = 9 },
			{ upgradeId = "unlockGodlyMult",     tier = 8 },
			{ upgradeId = "unlockCosmicMult",    tier = 7 },
			{ upgradeId = "unlockMythicMult",    tier = 6 },
		}

		local calculatedMaxTier = 5 
		for _, data in ipairs(tierUnlocks) do
			local upgData = stats.upgrades[data.upgradeId]
			local level = (typeof(upgData) == "table" and upgData.level) or (typeof(upgData) == "number" and upgData) or 0
			if level > 0 then calculatedMaxTier = data.tier; break end
		end

		playerMaxTier = calculatedMaxTier

		local speedData = stats.upgrades["multiplierSpeed"]
		local speedLevel = (typeof(speedData) == "table" and speedData.level) or (typeof(speedData) == "number" and speedData) or 0
		playerMultSpeed = 1.0 + (speedLevel * 0.05) 
	end
end)

task.spawn(function()
	while true do
		if holding then
			if hatcheryEmpty or habitatFull then
				table.clear(trackedInputs); EvaluateHolding()
			else
				ProduceAura:FireServer(); UpdateButtonVisual()
			end
		end
		task.wait(fireRate)
	end
end)

---------------------------------------------------------------
-- AURA MUTATION RESPONSES (CLIENT BOUND)
---------------------------------------------------------------
AuraSpawned.OnClientEvent:Connect(function(info)
	local instance, isCustom = SpawnAuraInstance(info.tier, info.color, info.glow, info.spawnPos, info.currentArea)

	instance:SetAttribute("AuraCube", true)
	ScaleAura(instance, info.tier, false)
	ShowCubeValue(info.spawnPos, info.value, info.color)
	PlayVFX("Spawn", info.spawnPos, 1.0)

	local permLabel = AttachPermanentRateLabel(instance, info.value, info.color)

	if info.tier == "Legendary" then
		ShowTierPopup(info.spawnPos, "Legendary", Color3.fromRGB(255, 200, 0))
		PlayVFX("Legendary", info.spawnPos, 2.0)
	end

	if info.cubeId then
		cubeDataMap[info.cubeId] = { 
			instance = instance, 
			tierName = info.tier, 
			isCustom = isCustom,
			rateLabel = permLabel 
		}
		instance.AncestryChanged:Connect(function(_, parent)
			if not parent then cubeDataMap[info.cubeId] = nil end
		end)
	end
end)

CubeMutatedBatch.OnClientEvent:Connect(function(batchData)
	for _, info in ipairs(batchData) do
		local cubeData = cubeDataMap[info.cubeId]
		if not cubeData then continue end 

		local instance = cubeData.instance
		if not instance or not instance.Parent then continue end 

		local rootPart = GetRootPart(instance)
		if not rootPart then continue end 
		local position = rootPart.Position

		if info.mutationType == "tierUpgrade" then
			PlayVFX("TierUpgrade", position, 1.5)
			if info.tierName == "Legendary" then PlayVFX("Legendary", position, 2.0) end

			local oldTierName = cubeData.tierName
			local newAura = CloneAuraModel(info.tierName, info.currentArea)

			if newAura then
				newAura:PivotTo(CFrame.new(position))
				newAura.Parent = workspace
				newAura:SetAttribute("AuraCube", true)

				if newAura.PrimaryPart then
					newAura.PrimaryPart.Anchored = false
					newAura.PrimaryPart.CanCollide = true
					newAura.PrimaryPart.CollisionGroup = "Auras"
				end

				ScaleAura(newAura, info.tierName, true, oldTierName)
				ApplyHeavyPhysics(newAura)

				if cubeData.rateLabel and cubeData.rateLabel.Parent then
					cubeData.rateLabel.Adornee = GetRootPart(newAura)
					cubeData.rateLabel.Parent = GetRootPart(newAura)

					cubeData.rateLabel.TextColor3 = info.newColor or Color3.fromRGB(100, 255, 100)

					if cubeData.isStored then
						cubeData.rateLabel.Enabled = false
					end
				end

				instance:Destroy()

				cubeData.instance = newAura
				cubeData.tierName = info.tierName
				cubeData.isCustom = true

				newAura.AncestryChanged:Connect(function(_, parent)
					if not parent then cubeDataMap[info.cubeId] = nil end
				end)
			else
				if rootPart:IsA("BasePart") then
					TweenService:Create(rootPart, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { Color = info.newColor }):Play()
					if info.newGlow then
						local light = rootPart:FindFirstChildOfClass("PointLight")
						if not light then light = Instance.new("PointLight"); light.Parent = rootPart end
						TweenService:Create(light, TweenInfo.new(0.5), { Brightness = 3, Range = 8, Color = info.newColor }):Play()
					end
					ScaleAura(instance, info.tierName, true, oldTierName)
				end
				cubeData.tierName = info.tierName
			end
			ShowTierPopup(position, info.tierName, info.newColor)
		end
	end
end)

---------------------------------------------------------------
-- HUD BUTTON POLISH
---------------------------------------------------------------
local function AddBasicJuice(btn)
	if not btn then return end
	local scale = btn:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", btn)
	btn.MouseEnter:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15), {Scale = 1.08}):Play() end)
	btn.MouseLeave:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15), {Scale = 1}):Play() end)
	btn.MouseButton1Down:Connect(function() TweenService:Create(scale, TweenInfo.new(0.1), {Scale = 0.9}):Play() end)
	btn.MouseButton1Up:Connect(function() TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), {Scale = 1.08}):Play() end)
end

AddBasicJuice(playerGui:WaitForChild("MainHUD"):FindFirstChild("ModeToggle"))
AddBasicJuice(playerGui:WaitForChild("MainHUD"):FindFirstChild("SendButton"))

ReplicatedStorage.RemoteEvents.UpgradeUpdated.OnClientEvent:Connect(function(info)
	if not info or not info.upgrades then return end
	local speedData = info.upgrades["multiplierSpeed"]
	local speedLevel = (typeof(speedData) == "table" and speedData.level) or (typeof(speedData) == "number" and speedData) or 0
	playerMultSpeed = 1.0 + (speedLevel * 0.05) 

	local tierUnlocks = {
		{ upgradeId = "unlockOmniMult",      tier = 10 },
		{ upgradeId = "unlockUniversalMult", tier = 9 },
		{ upgradeId = "unlockGodlyMult",     tier = 8 },
		{ upgradeId = "unlockCosmicMult",    tier = 7 },
		{ upgradeId = "unlockMythicMult",    tier = 6 },
	}

	local calculatedMaxTier = 5 
	for _, data in ipairs(tierUnlocks) do
		local upgData = info.upgrades[data.upgradeId]
		local level = (typeof(upgData) == "table" and upgData.level) or (typeof(upgData) == "number" and upgData) or 0
		if level > 0 then calculatedMaxTier = data.tier; break end
	end

	playerMaxTier = calculatedMaxTier
end)

-- AuraSpawner
-- Location: ServerScriptService > AuraSpawner

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local TierConfig     = require(ReplicatedStorage.Modules.TierConfig)
local UpgradeConfig  = require(ReplicatedStorage.Modules.UpgradeConfig)
local PrestigeModule = require(ReplicatedStorage.Modules.PrestigeModule)
local AdminConfig    = require(ReplicatedStorage.Modules.AdminConfig)
local MutationConfig = require(ReplicatedStorage.Modules.MutationConfig)
local AreaRegistry   = require(ReplicatedStorage.Modules.AreaRegistry)
local GameManager    = require(ServerScriptService.GameManager)
local BoostManager   = require(ServerScriptService.BoostManager)
local WeatherManager = require(ServerScriptService.WeatherManager) 

local AuraSpawned    = ReplicatedStorage.RemoteEvents:WaitForChild("AuraSpawned")
local ProduceAura    = ReplicatedStorage.RemoteEvents:WaitForChild("ProduceAura")
local UpdateHatchery = ReplicatedStorage.RemoteEvents:WaitForChild("UpdateHatchery")
local UpdateHUD      = ReplicatedStorage.RemoteEvents:WaitForChild("UpdateHUD")
local HabitatFull    = ReplicatedStorage.RemoteEvents:WaitForChild("HabitatFull")
local CubeMutated    = ReplicatedStorage.RemoteEvents:WaitForChild("CubeMutated")
local CubeSmushed    = ReplicatedStorage.RemoteEvents:WaitForChild("CubeSmushed")

-- ✨ Ensure CubeStored RemoteEvent exists safely
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
if not RemoteEvents:FindFirstChild("CubeStored") then
	local ev = Instance.new("RemoteEvent")
	ev.Name = "CubeStored"
	ev.Parent = RemoteEvents
end
local CubeStored = RemoteEvents:WaitForChild("CubeStored")

local HABITAT_HOLDER = workspace:WaitForChild("HabitatHolder")
local HABITAT_PART   = HABITAT_HOLDER:WaitForChild("Position")
local AURA_HOLDER    = workspace:WaitForChild("AuraHolder") 

local lastFire          = {}
local holdStart         = {}
local hatchery          = {}
local clickSessionStart = {}

-- Helper to safely retrieve the current area's defined aura models
local function GetAreaAuraModels(areaId)
	local config = nil
	if type(AreaRegistry.GetArea) == "function" then
		config = AreaRegistry.GetArea(areaId)
	elseif type(AreaRegistry.GetAreaConfig) == "function" then
		config = AreaRegistry.GetAreaConfig(areaId)
	elseif AreaRegistry.Areas then
		config = AreaRegistry.Areas[areaId]
	end
	return config and config.auraModels or nil
end

local function GetHatcheryMax(data)
	local cfg = UpgradeConfig.GetUpgradeConfig("hatcheryCapacity")
	return (cfg and cfg.apply) and cfg.apply(data) or AdminConfig.HatcheryMax
end

local function GetHabitatCapacity(data)
	local cfg = UpgradeConfig.GetUpgradeConfig("habitatCapacity")
	return (cfg and cfg.apply) and cfg.apply(data) or AdminConfig.BaseHabitatCapacity
end

local function GetMutationSpeedMult(data)
	local cfg = UpgradeConfig.GetUpgradeConfig("mutationSpeed")
	return (cfg and cfg.apply) and cfg.apply(data) or 1
end

Players.PlayerAdded:Connect(function(p)
	hatchery[p.UserId] = AdminConfig.HatcheryMax
	clickSessionStart[p.UserId] = nil
end)

Players.PlayerRemoving:Connect(function(p)
	hatchery[p.UserId]=nil; holdStart[p.UserId]=nil
	lastFire[p.UserId]=nil; clickSessionStart[p.UserId]=nil
end)

task.spawn(function()
	local PR = ServerScriptService:WaitForChild("PrestigeReset", 30)
	if PR then
		PR.Event:Connect(function(player)
			local uid = player.UserId
			local data = GameManager.GetData(uid)
			hatchery[uid] = data and GetHatcheryMax(data) or AdminConfig.HatcheryMax
			holdStart[uid]=nil; lastFire[uid]=nil; clickSessionStart[uid]=nil
		end)
	end
end)

-- Continuous Hatchery Tick Thread
task.spawn(function()
	while true do
		task.wait(0.1)
		for _, player in ipairs(Players:GetPlayers()) do
			local uid = player.UserId
			local data = GameManager.GetData(uid)
			local hatchMax = data and GetHatcheryMax(data) or AdminConfig.HatcheryMax
			local prev = hatchery[uid] or hatchMax

			if holdStart[uid] then
				hatchery[uid] = math.max(0, prev - AdminConfig.HatcheryDrainRate * 0.1)
			else
				hatchery[uid] = math.min(hatchMax, prev + AdminConfig.HatcheryRefillRate * 0.1)
			end

			if hatchery[uid] ~= prev then
				UpdateHatchery:FireClient(player, { current=hatchery[uid], max=hatchMax })
			end

			if hatchery[uid] <= 0 and holdStart[uid] then
				holdStart[uid] = nil
				ReplicatedStorage.RemoteEvents.ForceStopHold:FireClient(player)
			end
		end
	end
end)

local function GetAFKSpeed(runtime)
	local idleTime = tick() - runtime.lastActiveTime
	local speed = MutationConfig.AFKDecay[1].speed
	for _, e in ipairs(MutationConfig.AFKDecay) do
		if idleTime >= e.time then speed = e.speed end
	end
	return speed
end

local function SendHUDUpdate(player)
	local uid = player.UserId
	local data = GameManager.GetData(uid)
	local runtime = GameManager.GetRuntime(uid)
	if not data or not runtime then return end

	-- ✨ NEW: Separates Stored vs Active auras!
	local storedCount = 0
	local activeMV = 0
	local totalCubes = 0

	for _, cube in pairs(runtime.cubes) do
		totalCubes += 1
		if cube.isStored then
			storedCount += 1
		else
			activeMV += MutationConfig.GetMutatedValue(cube)
		end
	end

	runtime.cubeCount = totalCubes
	runtime.storedCubeCount = storedCount

	local rate = math.floor(activeMV)
	local passTickCfg = UpgradeConfig.GetUpgradeConfig("passiveTickSpeed")

	local passInt = (passTickCfg and passTickCfg.apply) and passTickCfg.apply(data) or AdminConfig.PassiveInterval
	local displayRate = math.floor(rate * BoostManager.GetValueMultiplier(uid) * BoostManager.GetSpawnRateMultiplier(uid))

	UpdateHUD:FireClient(player, {
		currency=data.currency, 
		pendingAuras=storedCount, -- ✨ ONLY affects the Habitat Bar
		habitatCapacity=GetHabitatCapacity(data), 
		rate=displayRate,
		passiveInterval=passInt, 
		totalEarned=data.totalEarned or 0,
		soulAuras=data.soulAuras or 0, 
		farmEvaluation=data.farmEvaluation or 0,
		goldenAuras=data.goldenAuras or 0, 
		boostInventory=data.boostInventory or {},
		prestigeCount=data.prestigeCount or 0,
		upgrades=data.upgrades or {},
		totalCubesProduced = data.totalCubesProduced or 0,
		currentArea        = data.currentArea or 1,
	})
end

-- Continuous Mutation Tick Thread
task.spawn(function()
	while true do
		local tickInterval = AdminConfig.MutationTickInterval or MutationConfig.CheckInterval
		task.wait(tickInterval)

		for _, player in ipairs(Players:GetPlayers()) do
			local uid = player.UserId
			local data = GameManager.GetData(uid)
			local runtime = GameManager.GetRuntime(uid)
			if not data or not runtime then continue end

			local dt = tickInterval * GetAFKSpeed(runtime) * GetMutationSpeedMult(data) * (AdminConfig.MutationSpeedMultiplier or 1)
			local mutationBatch = {}

			local currentArea = data.currentArea or 1
			local areaModels = GetAreaAuraModels(currentArea)

			for cubeId, cube in pairs(runtime.cubes) do
				local oldMutatedValue = MutationConfig.GetMutatedValue(cube)
				local mutated = false

				local prev = cube.effectiveElapsed
				cube.effectiveElapsed += dt
				local pl = MutationConfig.GetValueBonusLevel(prev)
				local nl = MutationConfig.GetValueBonusLevel(cube.effectiveElapsed)

				if nl > pl then
					mutated = true
					local be = MutationConfig.ValueBonuses[nl]
					table.insert(mutationBatch, { 
						cubeId = cubeId, 
						mutationType = "valueBonus",
						bonusLevel = nl, 
						bonusPercent = be and math.floor(be.bonus * 100) or 0 
					})
				end

				local maxTier = AdminConfig.MutationMaxTierIndex or 3
				local upgrades = 0

				while cube.tierIndex < maxTier and cube.tierIndex < #TierConfig.Tiers and upgrades < 5 do

					if areaModels then
						local nextTierName = TierConfig.Tiers[cube.tierIndex + 1].name
						if not areaModels[nextTierName] then
							break 
						end
					end

					local timeSince = cube.effectiveElapsed - (cube.lastUpgradeElapsed or 0)
					local bestChance, bestTime = 0, 0

					for _, threshold in ipairs(MutationConfig.TierUpgrades) do
						if timeSince >= threshold.time then 
							bestChance = threshold.chance
							bestTime = threshold.time 
						end
					end

					if bestChance <= 0 then break end

					if math.random() <= bestChance then
						local oldTier = TierConfig.Tiers[cube.tierIndex]
						cube.tierIndex += 1
						local newTier = TierConfig.Tiers[cube.tierIndex]

						cube.baseValue = math.floor(cube.baseValue * (newTier.multiplier/oldTier.multiplier))
						cube.color = newTier.color
						cube.glow = newTier.glow
						cube.tierName = newTier.name
						cube.lastUpgradeElapsed = (cube.lastUpgradeElapsed or 0) + bestTime
						upgrades += 1
						mutated = true

						table.insert(mutationBatch, { 
							cubeId = cubeId, 
							mutationType = "tierUpgrade",
							newColor = newTier.color, 
							newGlow = newTier.glow, 
							tierName = newTier.name,
							currentArea = currentArea
						})

						if newTier.name == "Legendary" then
							data.totalLegendaryCubes = (data.totalLegendaryCubes or 0) + 1
						end
					else 
						break 
					end
				end

				if mutated then
					local newMutatedValue = MutationConfig.GetMutatedValue(cube)
					runtime.totalMutatedValue = (runtime.totalMutatedValue or 0) + (newMutatedValue - oldMutatedValue)
				end
			end

			if #mutationBatch > 0 then
				ReplicatedStorage.RemoteEvents.CubeMutatedBatch:FireClient(player, mutationBatch)
			end
			SendHUDUpdate(player)
		end
	end
end)

local function GetHoldMultiplier(holdTime, data)
	local upgrades = data and data.upgrades or {}
	local speedData = upgrades["multiplierSpeed"]
	local speedLevel = (typeof(speedData) == "table" and speedData.level) or (typeof(speedData) == "number" and speedData) or 0
	local playerMultSpeed = 1.0 + (speedLevel * 0.05)

	local playerMaxTier = 5
	local mythicData = upgrades["unlockMythicMult"]
	local mythicLevel = (typeof(mythicData) == "table" and mythicData.level) or (typeof(mythicData) == "number" and mythicData) or 0
	if mythicLevel > 0 then playerMaxTier = 6 end

	local effectiveTime = holdTime * playerMultSpeed
	local currentTier = 1

	for i = 1, playerMaxTier do
		if AdminConfig.MilestoneData[i] and effectiveTime >= AdminConfig.MilestoneData[i].time then
			currentTier = i
		end
	end

	local nextTier = math.min(currentTier + 1, playerMaxTier)
	if currentTier == playerMaxTier then
		return AdminConfig.MilestoneData[currentTier].mult, AdminConfig.MilestoneData[currentTier].luck
	end

	local timePassed = effectiveTime - AdminConfig.MilestoneData[currentTier].time
	local timeNeeded = AdminConfig.MilestoneData[nextTier].time - AdminConfig.MilestoneData[currentTier].time
	local ratio = timePassed / timeNeeded

	local cMult = AdminConfig.MilestoneData[currentTier].mult
	local nMult = AdminConfig.MilestoneData[nextTier].mult
	local smoothMult = cMult + ((nMult - cMult) * ratio)

	return smoothMult, AdminConfig.MilestoneData[currentTier].luck
end

local function RollWithLuck(luckBonus)
	local tiers = TierConfig.Tiers
	local adjusted, total = {}, 0
	for _, tier in ipairs(tiers) do
		local chance = tier.chance
		if tier.name ~= "Common" then chance += luckBonus/(#tiers-1) end
		table.insert(adjusted, { tier=tier, chance=chance })
		total += chance
	end

	local r, cum = math.random() * total, 0
	for _, e in ipairs(adjusted) do
		cum += e.chance
		if r <= cum then return e.tier end
	end
	return tiers[1]
end

local function SpawnAura(player, data, runtime, holdMult, luckBonus)
	local uid  = player.UserId
	local tier = RollWithLuck(luckBonus)
	local tierIndex = 1
	for i, t in ipairs(TierConfig.Tiers) do if t.name == tier.name then tierIndex=i; break end end

	local currentArea = data.currentArea or 1
	local areaModels = GetAreaAuraModels(currentArea)

	if areaModels then
		while tierIndex > 1 do
			local checkName = TierConfig.Tiers[tierIndex].name
			if areaModels[checkName] then
				break
			end
			tierIndex -= 1
		end
		tier = TierConfig.Tiers[tierIndex] 
	end

	local totalValueMultiplier = 1.0 
	local valueUpgrades = {
		"blockValue", "blockValueT2", "auraValueT3", 
		"auraValueT4", "auraValueT6", "auraValueT8", "auraValueT10"
	}

	for _, upgradeId in ipairs(valueUpgrades) do
		local cfg = UpgradeConfig.GetUpgradeConfig(upgradeId)
		if cfg and cfg.apply then totalValueMultiplier += cfg.apply(data) end
	end

	local prestigeMult    = PrestigeModule.GetMultiplier(data.soulAuras)
	local areaMult        = AreaRegistry.GetMultiplier(data.currentArea or 1)
	local boostValueMult  = BoostManager.GetValueMultiplier(uid)
	local _, weatherValueMult = WeatherManager.GetMultipliers(uid)

	local calcMultFloat = totalValueMultiplier * prestigeMult * areaMult * boostValueMult * weatherValueMult
	local baseValue = math.floor(AdminConfig.BaseAuraValue * tier.multiplier * calcMultFloat)
	local totalValue = baseValue + math.floor(baseValue * (holdMult - 1))

	local spawnPos = HABITAT_PART.Position + Vector3.new(math.random(-3,3), 10, math.random(-3,3))	

	local areaFolder = ReplicatedStorage:FindFirstChild("AreaAssets") and ReplicatedStorage.AreaAssets:FindFirstChild("Area" .. currentArea)
	if areaFolder then
		local auraModel = areaFolder:FindFirstChild("AuraModel")
		if auraModel then
			local spawnPoint = auraModel:FindFirstChild("AuraSpawnPoint", true)
			if spawnPoint and spawnPoint:IsA("BasePart") then
				local size = spawnPoint.Size
				local randX = (math.random() - 0.5) * size.X
				local randZ = (math.random() - 0.5) * size.Z
				spawnPos = (spawnPoint.CFrame * CFrame.new(randX, 0, randZ)).Position
			end
		end
	end

	local cubeRecord = {
		spawnTime=tick(), effectiveElapsed=0, lastUpgradeElapsed=0,
		baseValue=totalValue, tierIndex=tierIndex,
		tierName=tier.name, color=tier.color, glow=tier.glow,
		isStored=false -- ✨ NEW
	}

	if AdminConfig.MutationInstantMax then
		local mb = MutationConfig.ValueBonuses[#MutationConfig.ValueBonuses]
		if mb then cubeRecord.effectiveElapsed = mb.time + 1 end
	end

	local cubeId = GameManager.AddCube(uid, cubeRecord)
	if not cubeId then return end

	data.totalCubesProduced = (data.totalCubesProduced or 0) + 1
	if tier.name == "Legendary" then data.totalLegendaryCubes = (data.totalLegendaryCubes or 0) + 1 end
	runtime.lastActiveTime = tick()

	AuraSpawned:FireClient(player, {
		cubeId=cubeId, tier=tier.name, color=tier.color,
		glow=tier.glow, value=totalValue, spawnPos=spawnPos,
		currentArea = currentArea 
	})
end

ProduceAura.OnServerEvent:Connect(function(player, action)
	local uid = player.UserId
	local now = tick()
	local data    = GameManager.GetData(uid)
	local runtime = GameManager.GetRuntime(uid)

	if action == "start" then 
		if data and runtime then
			local storedCount = runtime.storedCubeCount or 0
			if storedCount >= GetHabitatCapacity(data) then
				HabitatFull:FireClient(player)
				return
			end
		end

		if (hatchery[uid] or 0) > 0.5 then 
			holdStart[uid] = now 
		else
			UpdateHatchery:FireClient(player, { current = 0, max = data and GetHatcheryMax(data) or AdminConfig.HatcheryMax })
		end
		return 
	end

	if action == "stop" then 
		holdStart[uid] = nil; return 
	end

	if not data or not runtime then return end

	local capacity = GetHabitatCapacity(data)
	local storedCount = runtime.storedCubeCount or 0

	if storedCount >= capacity then HabitatFull:FireClient(player); return end
	if runtime.cubeCount >= capacity + 150 then return end -- Failsafe anti-lag cap

	if (hatchery[uid] or 0) <= 0.5 then 
		UpdateHatchery:FireClient(player, { current = 0, max = data and GetHatcheryMax(data) or AdminConfig.HatcheryMax })
		return 
	end
	if not holdStart[uid] then return end

	local rushMult = BoostManager.GetSpawnRateMultiplier(uid)
	local weatherSpawnMult, _ = WeatherManager.GetMultipliers(uid)
	local effectiveFireRate = AdminConfig.FireRate / (rushMult * weatherSpawnMult)

	if lastFire[uid] then
		local timeSinceLast = now - lastFire[uid]
		if timeSinceLast > 3 then clickSessionStart[uid] = now end
		if not clickSessionStart[uid] then clickSessionStart[uid] = now end

		local sessionLength = now - clickSessionStart[uid]
		if sessionLength > 300 then effectiveFireRate *= 2 end
		if sessionLength > 600 then effectiveFireRate *= 4 end
		if timeSinceLast < effectiveFireRate then return end
	else
		clickSessionStart[uid] = now
	end

	lastFire[uid] = now

	local holdTime = now - holdStart[uid]
	local holdMult, luckBonus = GetHoldMultiplier(holdTime, data)
	SpawnAura(player, data, runtime, holdMult, luckBonus)
	SendHUDUpdate(player)
	UpdateHatchery:FireClient(player, { current=hatchery[uid], max=GetHatcheryMax(data) })
end)

-- ✨ OFFICIAL STORAGE TRIGGER RESPONSE
CubeStored.OnServerEvent:Connect(function(player, cubeId)
	local uid = player.UserId
	local runtime = GameManager.GetRuntime(uid)

	if runtime and runtime.cubes[cubeId] then
		runtime.cubes[cubeId].isStored = true
		SendHUDUpdate(player)

		local data = GameManager.GetData(uid)
		local storedCount = runtime.storedCubeCount or 0
		if storedCount >= GetHabitatCapacity(data) then
			HabitatFull:FireClient(player)
		end
	end
end)

CubeSmushed.OnServerEvent:Connect(function(player, cubeId)
	local uid = player.UserId
	local runtime = GameManager.GetRuntime(uid)

	if runtime and runtime.cubes[cubeId] then
		runtime.cubes[cubeId] = nil

		SendHUDUpdate(player)

		local data = GameManager.GetData(uid)
		UpdateHatchery:FireClient(player, { current = hatchery[uid], max = GetHatcheryMax(data) })
	end
end)

-- TutorialController
-- Location: StarterPlayer > StarterPlayerScripts > TutorialController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local TutorialConfig = require(ReplicatedStorage.Modules.TutorialConfig)
local UITheme = require(ReplicatedStorage.Modules.UITheme)
local T = UITheme.Get("Custom")
local C = require(ReplicatedStorage.Modules.UIConfig)
local SoundConfig = require(ReplicatedStorage.Modules.SoundConfig)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainHUD = playerGui:WaitForChild("MainHUD")

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local AreaChanged = RemoteEvents:WaitForChild("AreaChanged")
local AreaUnlocked = RemoteEvents:WaitForChild("AreaUnlocked")
local AuraSpawned = RemoteEvents:WaitForChild("AuraSpawned")
local ShipAuras = RemoteEvents:WaitForChild("ShipAuras")
local UpgradeUpdated = RemoteEvents:WaitForChild("UpgradeUpdated")
local PrestigeComplete = RemoteEvents:WaitForChild("PrestigeComplete")
local HabitatFull = RemoteEvents:WaitForChild("HabitatFull")
local UpdateHUD = RemoteEvents:WaitForChild("UpdateHUD")
local BoostUpdated = RemoteEvents:WaitForChild("BoostUpdated")
local TutorialStepComplete = RemoteEvents:WaitForChild("TutorialStepComplete", 10)

local activePointer = nil
local activeSpotlight = nil
local activeHighlight = nil
local pointerUpdate = nil

-- FORWARD DECLARATIONS
local ShowBanner = nil
local DismissBanner = nil

---------------------------------------------------------------
-- STATE
---------------------------------------------------------------
local completedSteps = {}
local tutorialComplete = false
local currentArea = 1

local liveCurrency = 0
local liveFarmEval = 0
local liveSoulAuras = 0
local liveGoldenAuras = 0
local livePrestigeCount = 0

local hasSpawnedCube = false
local hasShipped = false
local hasUpgraded = false
local hasPrestieged = false
local hasHabitatFulled = false
local hasHatcheryEmpty = false
local hasActivatedBoost = false
local hasCollectedGift = false
local hasOpenedMail = false

local areaEnterTime = tick()

---------------------------------------------------------------
-- PROGRESSIVE UI LOCKING SYSTEM
---------------------------------------------------------------
local progressiveLocks = {}
local hidden3DObjects = {}
local aggressivelyLockedUI = {}
local function ForceHideProgressiveUI(targetName)
	-- 1. 2D UI AGGRESSIVE LOCK
	local searchGui = mainHUD:FindFirstAncestorOfClass("PlayerGui") or mainHUD.Parent
	for _, desc in ipairs(searchGui:GetDescendants()) do
		if (desc.Name == targetName or desc:GetAttribute("TutorialTarget") == targetName) and desc:IsA("GuiObject") then

			if not desc:GetAttribute("OriginalSize") then
				desc:SetAttribute("OriginalSize", desc.Size)
			end

			-- Add to hit-list and hide
			aggressivelyLockedUI[desc] = true
			desc.Visible = false

			-- The Guard: Slap it back to false if the Mailbox script tries to un-hide it
			if not desc:GetAttribute("LockEnforcer") then
				desc:SetAttribute("LockEnforcer", true)
				desc:GetPropertyChangedSignal("Visible"):Connect(function()
					if aggressivelyLockedUI[desc] and desc.Visible == true then
						desc.Visible = false 
					end
				end)
			end
		end
	end

	-- 2. 3D WORKSPACE HIDE (Transparency Method)
	local wsTarget = workspace:FindFirstChild(targetName, true)
	if wsTarget then
		hidden3DObjects[targetName] = wsTarget

		local parts = wsTarget:IsA("Model") and wsTarget:GetDescendants() or {wsTarget}
		for _, desc in ipairs(parts) do
			if desc:IsA("BasePart") or desc:IsA("Decal") or desc:IsA("Texture") then
				if not desc:GetAttribute("OriginalTrans") then
					desc:SetAttribute("OriginalTrans", desc.Transparency)
				end
				desc.Transparency = 1 

				if desc:IsA("BasePart") then
					if desc:GetAttribute("OrigCollide") == nil then
						desc:SetAttribute("OrigCollide", desc.CanCollide)
					end
					desc.CanCollide = false
				end
			end
		end
	end
end

local function UnlockProgressiveUI(targetName, showEffect)
	-- 1. 2D UI UNLOCK
	local searchGui = mainHUD:FindFirstAncestorOfClass("PlayerGui") or mainHUD.Parent
	for _, desc in ipairs(searchGui:GetDescendants()) do
		if (desc.Name == targetName or desc:GetAttribute("TutorialTarget") == targetName) and desc:IsA("GuiObject") then

			-- Release the lock
			aggressivelyLockedUI[desc] = nil
			desc.Visible = true

			local targetSize = desc:GetAttribute("OriginalSize") or desc.Size 
			if showEffect then
				desc.Size = UDim2.new(0,0,0,0)

				-- ✨ THE SPEED & CLICK SHIELD FIX ✨
				-- 1. Find the actual button to temporarily disable
				local buttonToLock = desc:IsA("GuiButton") and desc or desc:FindFirstChildWhichIsA("GuiButton", true)
				if buttonToLock then 
					buttonToLock.Interactable = false 
				end

				-- 2. Lightning-fast 0.15s snappy tween instead of the slow 0.5s bounce
				local popupTween = TweenService:Create(desc, TweenInfo.new(0.02, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = targetSize})
				popupTween:Play()

				-- 3. Re-enable the button the exact millisecond the animation finishes
				popupTween.Completed:Connect(function()
					if buttonToLock then 
						buttonToLock.Interactable = true 
					end
				end)
			end
		end
	end

	-- 2. 3D WORKSPACE UNLOCK (Transparency Method)
	if hidden3DObjects[targetName] then
		local wsTarget = hidden3DObjects[targetName]

		local parts = wsTarget:IsA("Model") and wsTarget:GetDescendants() or {wsTarget}
		for _, desc in ipairs(parts) do
			if desc:IsA("BasePart") or desc:IsA("Decal") or desc:IsA("Texture") then
				local origTrans = desc:GetAttribute("OriginalTrans")
				desc.Transparency = origTrans ~= nil and origTrans or 0

				if desc:IsA("BasePart") then
					local origCollide = desc:GetAttribute("OrigCollide")
					desc.CanCollide = origCollide ~= nil and origCollide or true
				end
			end
		end

		hidden3DObjects[targetName] = nil 
	end
end

local function SyncProgressiveUI()
	for _, step in ipairs(TutorialConfig.Steps) do
		if step.unlockUI then
			local targets = type(step.unlockUI) == "table" and step.unlockUI or {step.unlockUI}
			if completedSteps[step.id] then
				for _, t in ipairs(targets) do UnlockProgressiveUI(t, false) end
			else
				for _, t in ipairs(targets) do ForceHideProgressiveUI(t) end
			end
		end
	end
end

---------------------------------------------------------------
-- THE GLASS WALL
---------------------------------------------------------------
local globalGlassWall = nil
local function ToggleGlassWall(enable)
	if enable then
		if not globalGlassWall then
			local pGui = mainHUD:FindFirstAncestorOfClass("PlayerGui") or mainHUD.Parent
			globalGlassWall = Instance.new("TextButton")
			globalGlassWall.Name = "TutorialGlassWall"
			globalGlassWall.Size = UDim2.new(4, 0, 4, 0)
			globalGlassWall.Position = UDim2.new(-1, 0, -1, 0)
			globalGlassWall.BackgroundTransparency = 1
			globalGlassWall.Text = ""
			globalGlassWall.ZIndex = 100000 
			globalGlassWall.Parent = pGui
		end
	else
		if globalGlassWall then
			globalGlassWall:Destroy()
			globalGlassWall = nil
		end
	end
end

---------------------------------------------------------------
-- BANNER LAYOUT & JUMBO MATH
---------------------------------------------------------------
local activeBanners = {}
local triggeredSteps = {}


local BANNER_W = (C.Banners and C.Banners.AreaBannerW or 280) + 40 
local ICON_SIZE = 48 
local BANNER_GAP = 8
local BASE_Y = mainHUD.AbsoluteSize.Y * 0.35
local SLIDE_IN = 0.4
local SLIDE_OUT = 0.3
local OFFSCREEN_X = -BANNER_W - 50
local ONSCREEN_X = 15

local TITLE_H = 28 
local TITLE_PAD_T = 12
local BODY_PAD_T = 8
local BODY_PAD_B = 26
local ICON_PAD = 10

local function CalcBannerHeight(step, isMandatory)
	local hasBody = step.body and step.body ~= ""
	local hasIcon = (step.icon or "") ~= ""

	local screenW = mainHUD.AbsoluteSize.X
	local isMobile = screenW < 800

	local actualW = isMandatory and (isMobile and 380 or 600) or BANNER_W
	local iconS = isMandatory and (isMobile and 68 or 96) or ICON_SIZE
	local titleH = isMandatory and (isMobile and 32 or 46) or TITLE_H

	if not hasBody then
		return hasIcon and (iconS + ICON_PAD * 2) or (titleH + TITLE_PAD_T * 2 + 4)
	end

	local charsPerLine = math.floor((actualW - (hasIcon and (iconS + 20) or 12) - 16) / 9)
	local bodyLen = #(step.body or "")
	local lines = math.max(1, math.ceil(bodyLen / math.max(charsPerLine, 1)))

	local bodyH = math.max(26, lines * 26)

	local total = TITLE_PAD_T + titleH + BODY_PAD_T + bodyH + BODY_PAD_B
	if hasIcon then total = math.max(total, iconS + ICON_PAD * 2) end
	return total
end

---------------------------------------------------------------
-- HELPERS
---------------------------------------------------------------
local function PlaySound(id)
	if not id or id == "" then return end
	if shared.PlayUISound then shared.PlayUISound(id) end
end

local function IsStepComplete(id) return completedSteps[id] == true end

local function MarkComplete(id)
	if completedSteps[id] then return end
	completedSteps[id] = true
	if TutorialStepComplete then TutorialStepComplete:FireServer(id) end
end

---------------------------------------------------------------
-- CAMERA CONTROL & VISUAL POINTER
---------------------------------------------------------------
local activeBlur = nil
local currentCamera = workspace.CurrentCamera
local originalCamType = nil
local currentPanID = 0
local temporarilyHiddenMenus = {}

local function PanCameraTo(anchorName)
	currentPanID += 1
	local anchor = workspace:FindFirstChild(anchorName, true)
	if not anchor then return end

	ToggleGlassWall(true)

	temporarilyHiddenMenus = {}
	local pGui = mainHUD:FindFirstAncestorOfClass("PlayerGui") or mainHUD.Parent
	for _, desc in ipairs(pGui:GetDescendants()) do
		if desc:IsA("Frame") or desc:IsA("ScrollingFrame") then
			if desc.Visible and desc ~= mainHUD then
				local nameLower = string.lower(desc.Name)
				local isMenu = string.find(nameLower, "menu") or string.find(nameLower, "dialog") or string.find(nameLower, "panel")
				local isGiantWindow = (desc.AbsoluteSize.X > 300 and desc.AbsoluteSize.Y > 300)

				if (isMenu or isGiantWindow) and not string.find(desc.Name, "Tutorial") then
					desc.Visible = false
					table.insert(temporarilyHiddenMenus, desc)
				end
			end
		end
	end

	if currentCamera.CameraType ~= Enum.CameraType.Scriptable then
		originalCamType = currentCamera.CameraType
		currentCamera.CameraType = Enum.CameraType.Scriptable
	end
	TweenService:Create(currentCamera, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {CFrame = anchor.CFrame}):Play()
end

local function ResetCamera()
	for _, menu in ipairs(temporarilyHiddenMenus) do
		if menu and menu.Parent then menu.Visible = true end
	end
	temporarilyHiddenMenus = {}

	if originalCamType then
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local humanoid = char and char:FindFirstChild("Humanoid")

		if hrp and humanoid then
			local targetPos = hrp.Position + (hrp.CFrame.LookVector * -12) + Vector3.new(0, 5, 0)
			local targetCFrame = CFrame.new(targetPos, hrp.Position)
			local tweenTime = 0.8

			TweenService:Create(currentCamera, TweenInfo.new(tweenTime, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
				CFrame = targetCFrame
			}):Play()

			task.delay(tweenTime, function()
				currentCamera.CameraType = originalCamType
				currentCamera.CameraSubject = humanoid
				originalCamType = nil
			end)
		else
			currentCamera.CameraType = originalCamType
			if humanoid then currentCamera.CameraSubject = humanoid end
			originalCamType = nil
		end
	end
end

local function ClearVisuals()
	if activePointer then activePointer:Destroy(); activePointer = nil end
	if activeSpotlight then activeSpotlight:Destroy(); activeSpotlight = nil end
	if activeHighlight then activeHighlight:Destroy(); activeHighlight = nil end
	if pointerUpdate then pointerUpdate:Disconnect(); pointerUpdate = nil end

	if activeBlur then
		local blurToKill = activeBlur
		activeBlur = nil
		TweenService:Create(blurToKill, TweenInfo.new(0.3), {Size = 0}):Play()
		task.delay(0.3, function()
			if blurToKill and blurToKill.Parent then blurToKill:Destroy() end
		end)
	end
end

---------------------------------------------------------------
-- ✨ UPGRADED AUTO SCROLL (Math Fix + No Yielding)
---------------------------------------------------------------
local function AutoScrollToTarget(target)
	local scrollFrame = target:FindFirstAncestorOfClass("ScrollingFrame")
	if scrollFrame then
		local relativeY = (target.AbsolutePosition.Y - scrollFrame.AbsolutePosition.Y) + scrollFrame.CanvasPosition.Y
		local targetCanvasY = relativeY - (scrollFrame.AbsoluteSize.Y / 2) + (target.AbsoluteSize.Y / 2)

		-- ✨ MATH FIX: Must use AbsoluteCanvasSize for modern UI!
		local maxScroll = math.max(0, scrollFrame.AbsoluteCanvasSize.Y - scrollFrame.AbsoluteSize.Y)

		TweenService:Create(scrollFrame, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CanvasPosition = Vector2.new(scrollFrame.CanvasPosition.X, math.clamp(targetCanvasY, 0, maxScroll))
		}):Play()
	end
end

local function ShowVisualPointer(targetName, dismissCallback, holdDuration)
	ClearVisuals()

	local target = nil
	local clickTarget = nil
	local attempts = 0
	local searchGui = mainHUD:FindFirstAncestorOfClass("PlayerGui") or mainHUD.Parent

	while not target and attempts < 60 do 
		for _, desc in ipairs(searchGui:GetDescendants()) do
			local isMatch = (desc.Name == targetName) or (desc:GetAttribute("TutorialTarget") == targetName)

			if isMatch and desc:IsA("GuiObject") then
				local isVisible = true
				local curr = desc
				while curr and curr ~= game do
					if curr:IsA("GuiObject") and not curr.Visible then 
						isVisible = false; break 
					elseif curr:IsA("LayerCollector") and not curr.Enabled then
						isVisible = false; break
					elseif curr:IsA("Folder") then 
						isVisible = false; break
					end
					curr = curr.Parent
				end

				if isVisible and desc.AbsoluteSize.Y > 0 then
					-- ✨ THE FIX: Prioritize a button named "BuyButton" so we don't accidentally target the info icon!
					clickTarget = desc:IsA("GuiButton") and desc or (desc:FindFirstChild("BuyButton", true) or desc:FindFirstChildWhichIsA("GuiButton", true))
					if clickTarget then target = desc; break end
				end
			end
		end
		if not target then task.wait(0.5); attempts += 1 end
	end

	if target and clickTarget and target:IsA("GuiObject") then

		AutoScrollToTarget(target)

		local freezeEvent = RemoteEvents:FindFirstChild("TutorialFreeze")
		if freezeEvent then freezeEvent:FireServer(true) end

		activeBlur = Instance.new("BlurEffect")
		activeBlur.Name = "TutorialBlur"
		activeBlur.Size = 0 
		activeBlur.Parent = game:GetService("Lighting")
		TweenService:Create(activeBlur, TweenInfo.new(0.5), {Size = 15}):Play()

		activeSpotlight = Instance.new("Frame")
		activeSpotlight.Name = "TutorialShield"
		activeSpotlight.Size = UDim2.new(4, 0, 4, 0)
		activeSpotlight.Position = UDim2.new(-1, 0, -1, 0)
		activeSpotlight.BackgroundColor3 = Color3.new(0, 0, 0)
		activeSpotlight.BackgroundTransparency = 1
		activeSpotlight.Active = true 
		activeSpotlight.ZIndex = 80
		activeSpotlight.Parent = mainHUD
		TweenService:Create(activeSpotlight, TweenInfo.new(0.5), {BackgroundTransparency = 0.65}):Play()

		local originalZIndex = target.ZIndex
		target.ZIndex = 90

		-- ✨ 1. Find the Main Window (StatsPanel, ShopPanel, etc.) and pull it forward!
		local rootPanel = target
		while rootPanel and rootPanel.Parent ~= mainHUD and rootPanel.Parent ~= game do
			rootPanel = rootPanel.Parent
		end

		local originalRootZ = nil
		if rootPanel and rootPanel:IsA("GuiObject") then
			originalRootZ = rootPanel.ZIndex
			rootPanel.ZIndex = 81 -- The dark shield is 80, so this puts the whole menu on top!
		end

		-- ✨ 2. Elevate the Scrolling Frame (Just to be mathematically safe)
		local scrollFrame = target:FindFirstAncestorOfClass("ScrollingFrame")
		local originalScrollZ = nil
		if scrollFrame then
			originalScrollZ = scrollFrame.ZIndex
			scrollFrame.ZIndex = 82 
		end

		-- ✨ 3. The Master Restore Function
		local function RestoreZ()
			if target then target.ZIndex = originalZIndex end
			if scrollFrame and originalScrollZ then scrollFrame.ZIndex = originalScrollZ end
			if rootPanel and originalRootZ then rootPanel.ZIndex = originalRootZ end
		end

		activeHighlight = Instance.new("Frame")
		activeHighlight.Name = "TutorialHighlight"
		activeHighlight.BackgroundColor3 = Color3.new(1, 1, 1) 
		activeHighlight.BackgroundTransparency = 0.85 
		activeHighlight.Interactable = false 
		activeHighlight.Active = false
		activeHighlight.ZIndex = 85
		activeHighlight.Parent = mainHUD

		local highlightStroke = Instance.new("UIStroke", activeHighlight)
		highlightStroke.Color = Color3.fromRGB(255, 255, 255)
		highlightStroke.Thickness = 3

		local targetCorner = target:FindFirstChildOfClass("UICorner")
		local highlightCorner = Instance.new("UICorner", activeHighlight)
		highlightCorner.CornerRadius = targetCorner and targetCorner.CornerRadius or UDim.new(0, 8)

		TweenService:Create(activeHighlight, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {BackgroundTransparency = 0.65}):Play()

		activePointer = Instance.new("ImageLabel")
		activePointer.Name = "TutorialPointer"
		activePointer.Size = UDim2.new(0, 55, 0, 55)
		activePointer.BackgroundTransparency = 1
		activePointer.Image = "rbxassetid://14922084401"
		activePointer.ZIndex = 100
		activePointer.AnchorPoint = Vector2.new(0.5, 1)
		activePointer.Parent = mainHUD

		-- ✨ THE RE-SCROLL WATCHDOG SETUP
		local scrollFrame = target:FindFirstAncestorOfClass("ScrollingFrame")
		local isAutoScrolling = false

		pointerUpdate = RunService.RenderStepped:Connect(function()
			if not activePointer or not activeHighlight or not target or not target.Parent then
				ClearVisuals()
				RestoreZ() -- ✨ FIX: Restores both the target and the scroll frame!
				return
			end

			-- ✨ WATCHDOG LOGIC: Check if the button was pushed out of view!
			if scrollFrame and not isAutoScrolling then
				local targetY = target.AbsolutePosition.Y
				local scrollY = scrollFrame.AbsolutePosition.Y
				local scrollBottom = scrollY + scrollFrame.AbsoluteSize.Y

				-- Is the target entirely outside the visible scroll window?
				if (targetY + target.AbsoluteSize.Y < scrollY) or (targetY > scrollBottom) then

					-- Verify the menu is actually open before forcing a scroll
					local isMenuOpen = true
					local curr = target
					while curr and curr ~= game do
						if curr:IsA("GuiObject") and not curr.Visible then isMenuOpen = false; break end
						curr = curr.Parent
					end

					if isMenuOpen then
						isAutoScrolling = true
						AutoScrollToTarget(target)
						task.delay(0.5, function() isAutoScrolling = false end)
					end
				end
			end

			-- Update Highlight & Pointer Positions
			local tgtRelX = target.AbsolutePosition.X - mainHUD.AbsolutePosition.X
			local tgtRelY = target.AbsolutePosition.Y - mainHUD.AbsolutePosition.Y
			activeHighlight.Size = UDim2.new(0, target.AbsoluteSize.X + 8, 0, target.AbsoluteSize.Y + 8)
			activeHighlight.Position = UDim2.new(0, tgtRelX - 4, 0, tgtRelY - 4)

			local btnRelX = clickTarget.AbsolutePosition.X - mainHUD.AbsolutePosition.X
			local btnRelY = clickTarget.AbsolutePosition.Y - mainHUD.AbsolutePosition.Y
			local btnCenterX = btnRelX + (clickTarget.AbsoluteSize.X / 2)
			local bounceOffset = math.abs(math.sin(tick() * 5)) * 15

			activePointer.Position = UDim2.new(0, btnCenterX, 0, btnRelY - 5 - bounceOffset)
		end)

		if dismissCallback then
			if holdDuration and holdDuration > 0 then
				local holdAttempt = 0
				local uisConns = {}

				local function startHold()
					holdAttempt += 1
					local currentAttempt = holdAttempt
					task.delay(holdDuration, function()
						if holdAttempt == currentAttempt then
							holdAttempt = 0 
							for _, c in ipairs(uisConns) do c:Disconnect() end
							ToggleGlassWall(true)
							ClearVisuals() 
							RestoreZ() -- ✨ FIX

							if freezeEvent then freezeEvent:FireServer(false) end

							dismissCallback() 
						end
					end)
				end

				local function cancelHold() holdAttempt += 1 end

				clickTarget.MouseButton1Down:Connect(startHold)
				clickTarget.MouseButton1Up:Connect(cancelHold)
				clickTarget.MouseLeave:Connect(cancelHold)

				table.insert(uisConns, UserInputService.InputBegan:Connect(function(input, gpe)
					if input.KeyCode == Enum.KeyCode.Space and not gpe then startHold() end
				end))
				table.insert(uisConns, UserInputService.InputEnded:Connect(function(input)
					if input.KeyCode == Enum.KeyCode.Space then cancelHold() end
				end))

				if UserInputService:IsKeyDown(Enum.KeyCode.Space) or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
					startHold()
				end
			else
				local clickConn, uisConn
				local function completeClick()
					if clickConn then clickConn:Disconnect() end
					if uisConn then uisConn:Disconnect() end
					ToggleGlassWall(true) 
					ClearVisuals() 
					RestoreZ() -- ✨ FIX

					if freezeEvent then freezeEvent:FireServer(false) end

					dismissCallback() 
				end

				clickConn = clickTarget.MouseButton1Down:Connect(completeClick)
				uisConn = UserInputService.InputBegan:Connect(function(input, gpe)
					if input.KeyCode == Enum.KeyCode.Space and not gpe then completeClick() end
				end)
			end
		end
	else
		warn("Tutorial Error: Target '"..targetName.."' not found after waiting!")
	end
end

---------------------------------------------------------------
-- REFLOW & DISMISS
---------------------------------------------------------------
local function ReflowBanners()
	local yOffset = 0
	for _, entry in ipairs(activeBanners) do
		if not entry.dismissed and not entry.isMandatory and entry.frame and entry.frame.Parent then
			local targetY = BASE_Y + yOffset
			TweenService:Create(entry.frame,
				TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Position = UDim2.new(0, ONSCREEN_X, 0, targetY) }):Play()
			entry.currentY = targetY
			yOffset += entry.height + BANNER_GAP
		end
	end
end

DismissBanner = function(entry)
	if entry.dismissed then return end
	entry.dismissed = true
	local offscreenPos
	if entry.isMandatory and entry.frame then
		offscreenPos = UDim2.new(0.5, -(entry.frame.Size.X.Offset / 2), 0, -entry.height - 50)
	else
		offscreenPos = UDim2.new(0, OFFSCREEN_X, 0, entry.currentY or BASE_Y)
	end
	TweenService:Create(entry.frame, TweenInfo.new(SLIDE_OUT, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = offscreenPos }):Play()

	if entry.panID then
		local resetDelay = entry.step.cameraResetDelay or 0
		task.delay(resetDelay, function()
			if currentPanID == entry.panID then
				ResetCamera()
			end
		end)
	end

	task.delay(SLIDE_OUT + 0.1, function()
		if entry.frame and entry.frame.Parent then entry.frame:Destroy() end
		for i, e in ipairs(activeBanners) do
			if e == entry then table.remove(activeBanners, i); break end
		end
		ReflowBanners()
		if entry.step.nextStep and entry.step.nextStep ~= "" then
			local nextData = TutorialConfig.GetStep(entry.step.nextStep)
			if nextData and not triggeredSteps[entry.step.nextStep] then
				task.delay(entry.step.chainDelay or 0.5, function() ShowBanner(nextData) end)
			else
				ToggleGlassWall(false)
			end
		else
			ToggleGlassWall(false)
		end
	end)
end

---------------------------------------------------------------
-- SHOW BANNER
---------------------------------------------------------------
ShowBanner = function(step)
	if triggeredSteps[step.id] then return end
	triggeredSteps[step.id] = true

	if step.unlockUI then
		local targets = type(step.unlockUI) == "table" and step.unlockUI or {step.unlockUI}
		for _, t in ipairs(targets) do UnlockProgressiveUI(t, true) end
	end

	local isMandatory = step.isMandatory == true

	-- THE FIX: If it is mandatory, wait forever (0). Otherwise, use the step duration or default!
	local duration = 0
	if step.duration ~= nil then
		duration = step.duration
	elseif not isMandatory then
		duration = TutorialConfig.DefaultDuration or 8
	end

	local color = step.color or TutorialConfig.DefaultColor or T.accentTeal
	local iconId = step.icon or TutorialConfig.DefaultIcon or ""
	local hasBody = step.body and step.body ~= ""
	local hasIcon = iconId ~= ""

	if step.cameraPan and step.cameraPan ~= "" then
		PanCameraTo(step.cameraPan)
	end

	local screenW = mainHUD.AbsoluteSize.X
	local isMobile = screenW < 800
	local targetX = isMobile and (ONSCREEN_X + 45) or ONSCREEN_X
	local actualW = isMandatory and (isMobile and 380 or 600) or BANNER_W
	local iconS = isMandatory and (isMobile and 68 or 96) or ICON_SIZE
	local titleH = isMandatory and (isMobile and 32 or 46) or TITLE_H
	local bannerH = CalcBannerHeight(step, isMandatory)

	local currentBaseY = mainHUD.AbsoluteSize.Y * 0.35
	local yOffset = 0
	for _, e in ipairs(activeBanners) do
		if not e.dismissed and not e.isMandatory then yOffset += e.height + BANNER_GAP end
	end
	local targetY = currentBaseY + yOffset

	local entry = { step = step, height = bannerH, currentY = targetY, dismissed = false, isMandatory = isMandatory }

	if step.freezeGame then
		local freezeEvent = RemoteEvents:FindFirstChild("TutorialFreeze")
		if freezeEvent then freezeEvent:FireServer(true) end
	end

	local function triggerDismiss()
		if step.freezeGame then
			local freezeEvent = RemoteEvents:FindFirstChild("TutorialFreeze")
			if freezeEvent then freezeEvent:FireServer(false) end
		end
		MarkComplete(step.id)
		DismissBanner(entry) 
	end

	if step.target and step.target ~= "" then
		ShowVisualPointer(step.target, triggerDismiss, step.holdDuration)
	end

	if step.cameraTarget and step.cameraTarget ~= "" then
		local posPart = workspace:FindFirstChild(step.cameraTarget, true)
		if posPart and posPart:IsA("BasePart") then
			local currentPanID = os.clock()
			entry.panID = currentPanID
			local camera = workspace.CurrentCamera
			camera.CameraType = Enum.CameraType.Scriptable
			TweenService:Create(camera, TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {CFrame = posPart.CFrame}):Play()

			-- ✨ THE AUTO-RESET FIX
			if step.cameraResetDelay and step.cameraResetDelay > 0 then
				task.delay(step.cameraResetDelay, function()
					-- Ensure we are still looking at THIS specific target
					if entry.panID == currentPanID then
						workspace.CurrentCamera.CameraType = Enum.CameraType.Custom -- Reset Camera

						-- If it's mandatory but has no button to click, auto-dismiss to unstick the player
						if step.isMandatory and (not step.target or step.target == "") then
							MarkComplete(step.id)
							DismissBanner(entry)
						end
					end
				end)
			end
		end
		if step.burstAuras and type(step.burstAuras) == "number" then
			local burstEvent = RemoteEvents:FindFirstChild("TutorialBurst")
			if burstEvent then
				burstEvent:FireServer(step.burstAuras)
			else
				warn("Tutorial: Please create a RemoteEvent named 'TutorialBurst' in ReplicatedStorage.RemoteEvents!")
			end
		end
	end

	-- ✨ THE FIX: Changed from TextButton to Frame with Active = false!
	local banner = Instance.new("Frame")
	banner.Name = "TutorialBanner_" .. step.id
	banner.Size = UDim2.new(0, actualW, 0, bannerH)
	banner.Active = false -- ✨ CRITICAL: Lets clicks pass through the banner to the UI underneath!
	banner.ZIndex = 95; banner.ClipsDescendants = false; banner.Parent = mainHUD
	UITheme.Apply(banner, "Panel")

	local bgGrad = Instance.new("UIGradient", banner)
	bgGrad.Rotation = 90
	bgGrad.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 1) })

	local stroke = banner:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color; stroke.Thickness = 1.5; stroke.Transparency = 0.2
		local strokeGrad = Instance.new("UIGradient", stroke)
		strokeGrad.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)), ColorSequenceKeypoint.new(1, color) })
		strokeGrad.Rotation = 45
	end

	local textX = hasIcon and (iconS + 20) or 14
	local textW = actualW - textX - 14

	if hasIcon then
		local iconFrame = Instance.new("Frame")
		iconFrame.Size = UDim2.new(0, iconS + 8, 0, iconS + 8)
		iconFrame.Position = UDim2.new(0, 6, 0.5, -(iconS + 8)/2)
		iconFrame.BackgroundColor3 = color; iconFrame.BackgroundTransparency = 0.8
		iconFrame.BorderSizePixel = 0; iconFrame.ZIndex = 96; iconFrame.Parent = banner
		Instance.new("UICorner", iconFrame).CornerRadius = UDim.new(0, 8)

		local iconStroke = Instance.new("UIStroke", iconFrame)
		iconStroke.Color = color; iconStroke.Transparency = 0.4; iconStroke.Thickness = 1.2

		local iconImg = Instance.new("ImageLabel")
		iconImg.Size = UDim2.new(0, iconS, 0, iconS)
		iconImg.Position = UDim2.new(0.5, -iconS/2, 0.5, -iconS/2)
		iconImg.BackgroundTransparency = 1; iconImg.Image = iconId
		iconImg.ScaleType = Enum.ScaleType.Fit; iconImg.ZIndex = 97; iconImg.Parent = iconFrame
	end

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(0, textW, 0, titleH)
	titleLabel.Position = UDim2.new(0, textX, 0, hasBody and TITLE_PAD_T or (bannerH/2 - titleH/2))
	titleLabel.BackgroundTransparency = 1; titleLabel.Text = step.title or ""
	titleLabel.TextColor3 = color; titleLabel.TextScaled = true; titleLabel.Font = T.font; titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.ZIndex = 96; titleLabel.Parent = banner

	local titleShadow = titleLabel:Clone()
	titleShadow.TextColor3 = Color3.new(0,0,0); titleShadow.TextTransparency = 0.5
	titleShadow.Position = UDim2.new(0, textX + 1, 0, (hasBody and TITLE_PAD_T or (bannerH/2 - titleH/2)) + 1)
	titleShadow.ZIndex = 95; titleShadow.Parent = banner

	if hasBody then
		local bodyTop = TITLE_PAD_T + titleH + BODY_PAD_T
		local bodyH = bannerH - bodyTop - BODY_PAD_B
		local bodyLabel = Instance.new("TextLabel")
		bodyLabel.Size = UDim2.new(0, textW, 0, bodyH)
		bodyLabel.Position = UDim2.new(0, textX, 0, bodyTop)
		bodyLabel.BackgroundTransparency = 1; bodyLabel.Text = step.body
		bodyLabel.TextColor3 = T.bodyText; bodyLabel.TextScaled = true; bodyLabel.Font = T.fontBody; bodyLabel.TextXAlignment = Enum.TextXAlignment.Left
		bodyLabel.TextWrapped = true; bodyLabel.ZIndex = 96; bodyLabel.Parent = banner
	end

	if not isMandatory or (isMandatory and (not step.target or step.target == "")) then
		-- ✨ ADDED: An invisible click-catcher only when the banner is meant to be dismissable!
		local clickCatcher = Instance.new("TextButton")
		clickCatcher.Size = UDim2.new(1, 0, 1, 0)
		clickCatcher.BackgroundTransparency = 1
		clickCatcher.Text = ""
		clickCatcher.ZIndex = 99
		clickCatcher.Parent = banner

		clickCatcher.MouseButton1Down:Connect(function()
			ToggleGlassWall(true)
			triggerDismiss()
		end)

		if not isMandatory then
			local hintLabel = Instance.new("TextLabel")
			hintLabel.Size = UDim2.new(0, 80, 0, 12)
			hintLabel.Position = UDim2.new(1, -86, 1, -14)
			hintLabel.BackgroundTransparency = 1; hintLabel.Text = "tap to dismiss"
			hintLabel.TextColor3 = T.subText; hintLabel.TextScaled = true; hintLabel.Font = T.fontBody; hintLabel.TextXAlignment = Enum.TextXAlignment.Right
			hintLabel.ZIndex = 96; hintLabel.Parent = banner
			TweenService:Create(hintLabel, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {TextTransparency = 0.7}):Play()
		end
	end

	if duration > 0 then
		task.delay(duration, function()
			ToggleGlassWall(true)
			triggerDismiss()
		end)
	end

	entry.frame = banner
	table.insert(activeBanners, entry)

	local snd = step.sound or SoundConfig.TutorialHint or ""
	PlaySound(snd)

	if isMandatory then
		local targetPos
		if step.bannerPos == "Top" then
			targetPos = UDim2.new(0.5, -actualW/2, 0, 40)
		elseif step.bannerPos == "Center" then
			targetPos = UDim2.new(0.5, -actualW/2, 0.5, -bannerH/2)
		else
			if step.target and step.target ~= "" then
				targetPos = UDim2.new(0.5, -actualW/2, 0, 40)
			else
				targetPos = UDim2.new(0.5, -actualW/2, 0.5, -bannerH/2)
			end
		end
		banner.Position = UDim2.new(0.5, -actualW/2, 0, -bannerH - 50)
		TweenService:Create(banner, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = targetPos }):Play()
	else
		banner.Position = UDim2.new(0, OFFSCREEN_X, 0, targetY)
		TweenService:Create(banner, TweenInfo.new(SLIDE_IN, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = UDim2.new(0, targetX, 0, targetY)
		}):Play()
	end
	ToggleGlassWall(false)
end

---------------------------------------------------------------
-- TRIGGER SYSTEM
---------------------------------------------------------------
local function FireTrigger(triggerName, value)
	if tutorialComplete then return end
	if not mainHUD.Enabled then return end 

	-- THE ULTIMATE OVERLAP FIX: One banner at a time!
	if triggerName ~= "chain" then
		for _, entry in ipairs(activeBanners) do
			if not entry.dismissed then return end
		end
	end

	for _, step in ipairs(TutorialConfig.Steps) do
		if step.trigger == triggerName and not IsStepComplete(step.id) then

			-- Area Lock
			if step.area and step.area ~= currentArea then
				continue
			end

			-- Prestige Lock (FIXED: Now checks actual stats instead of a hardcoded step name)
			if step.requirePrestige and livePrestigeCount <= 0 and not hasPrestieged then
				continue
			end

			-- Sequence Lock
			if step.requireStep and not IsStepComplete(step.requireStep) then
				continue
			end

			-- Normal trigger value checking
			if step.triggerValue ~= nil then
				if type(value) == "number" and value >= step.triggerValue then
					ShowBanner(step)
				end
			else
				ShowBanner(step)
			end

		end
	end
end

local ManualTrigger = Instance.new("BindableEvent")
ManualTrigger.Name = "TutorialTrigger"; ManualTrigger.Parent = ReplicatedStorage
ManualTrigger.Event:Connect(function(stepId)
	if tutorialComplete then return end
	local step = TutorialConfig.GetStep(stepId)
	if step then
		MarkComplete(step.id)
		task.delay(step.delay or TutorialConfig.DefaultDelay, function() ShowBanner(step) end)
	end
end)
shared.FireTutorial = function(stepId) ManualTrigger:Fire(stepId) end

task.spawn(function()
	while true do
		task.wait(1)

		if tutorialComplete then continue end
		if not mainHUD.Enabled then continue end

		FireTrigger("areaEnter", currentArea)
		FireTrigger("farmEvalReached", liveFarmEval)
		FireTrigger("currencyReached", liveCurrency)
		FireTrigger("soulAurasReached", liveSoulAuras)

		-- THE FIX: Continually re-fire one-time events if they were blocked!
		if hasSpawnedCube then FireTrigger("firstCube") end
		if hasShipped then FireTrigger("firstShip") end
		if hasUpgraded then FireTrigger("firstUpgrade") end
		if hasPrestieged then FireTrigger("firstPrestige") end
		if hasHabitatFulled then FireTrigger("habitatFull") end
		if hasActivatedBoost then FireTrigger("boostActivated") end
		if hasCollectedGift then FireTrigger("giftCollected") end
		if hasOpenedMail then FireTrigger("mailOpened") end

		FireTrigger("timerElapsed", tick() - areaEnterTime)
	end
end)
---------------------------------------------------------------
-- EVENT LISTENERS
---------------------------------------------------------------
AreaChanged.OnClientEvent:Connect(function(info)
	currentArea = info.newArea or currentArea
	areaEnterTime = tick()
	hasSpawnedCube = false; hasShipped = false; hasUpgraded = false
	hasHabitatFulled = false; hasHatcheryEmpty = false
	hasActivatedBoost = false; hasCollectedGift = false; hasOpenedMail = false

	if info.isPortalEntry and currentArea > TutorialConfig.TutorialEndArea and not tutorialComplete then
		tutorialComplete = true
		if TutorialStepComplete then TutorialStepComplete:FireServer("__tutorialComplete__") end
	end
	task.delay(0.5, function()
		if SyncProgressiveUI then SyncProgressiveUI() end
		FireTrigger("areaEnter", currentArea)
	end)
end)

AuraSpawned.OnClientEvent:Connect(function()
	if not hasSpawnedCube then hasSpawnedCube = true; FireTrigger("firstCube") end
end)

ShipAuras.OnClientEvent:Connect(function()
	if not hasShipped then hasShipped = true; FireTrigger("firstShip") end
end)

UpgradeUpdated.OnClientEvent:Connect(function(info)
	if info.type == "purchased" then
		if not hasUpgraded then hasUpgraded = true; FireTrigger("firstUpgrade") end
		if info.level then FireTrigger("upgradeLevel", info.level) end
	end
end)

PrestigeComplete.OnClientEvent:Connect(function(info)
	if not info.isPortalEntry then
		if not hasPrestieged then hasPrestieged = true; FireTrigger("firstPrestige") end
		if info.prestigeCount then
			livePrestigeCount = info.prestigeCount
			FireTrigger("prestigeCount", livePrestigeCount)
		end
	end
end)

HabitatFull.OnClientEvent:Connect(function()
	if not hasHabitatFulled then hasHabitatFulled = true; FireTrigger("habitatFull") end
end)

AreaUnlocked.OnClientEvent:Connect(function() FireTrigger("portalReady") end)

BoostUpdated.OnClientEvent:Connect(function(info)
	if info and info.activated then
		if not hasActivatedBoost then hasActivatedBoost = true; FireTrigger("boostActivated") end
	end
end)

shared.OnPhysicsAuraCollected = function()
	if not hasCollectedGift then hasCollectedGift = true; FireTrigger("giftCollected") end
end

shared.OnMailOpened = function()
	if not hasOpenedMail then hasOpenedMail = true; FireTrigger("mailOpened") end
end

UpdateHUD.OnClientEvent:Connect(function(stats)
	if stats.tutorialProgress then
		for id, v in pairs(stats.tutorialProgress) do if v then completedSteps[id] = true end end
		SyncProgressiveUI()
	end
	if stats.tutorialComplete ~= nil then tutorialComplete = stats.tutorialComplete end
	if stats.currentArea then currentArea = stats.currentArea end

	-- ✨ FIX THESE TWO LINES: Map to the correct local variables!
	if stats.hasPrestigedThisArea ~= nil then hasPrestieged = stats.hasPrestigedThisArea end
	if stats.prestigeCount ~= nil then livePrestigeCount = stats.prestigeCount end

	if stats.currency ~= nil then
		local old = liveCurrency; liveCurrency = stats.currency
		if liveCurrency > old then FireTrigger("currencyReached", liveCurrency) end
	end
	if stats.farmEvaluation ~= nil then
		local old = liveFarmEval; liveFarmEval = stats.farmEvaluation
		if liveFarmEval > old then FireTrigger("farmEvalReached", liveFarmEval) end
	end
	if stats.soulAuras ~= nil then
		local old = liveSoulAuras; liveSoulAuras = stats.soulAuras
		if liveSoulAuras > old then FireTrigger("soulAurasReached", liveSoulAuras) end
	end
	if stats.goldenAuras ~= nil then
		local old = liveGoldenAuras; liveGoldenAuras = stats.goldenAuras
		if liveGoldenAuras > old then FireTrigger("goldenAurasReached", liveGoldenAuras) end
	end
end)

local joinFired = false
RemoteEvents:WaitForChild("AreaUpdated").OnClientEvent:Connect(function(info)
	if not joinFired then
		joinFired = true; currentArea = info.currentArea or 1; areaEnterTime = tick()
		task.delay(2, function() FireTrigger("areaEnter", currentArea) end)
	end
end)

---------------------------------------------------------------
-- STARTUP INITIALIZATION
---------------------------------------------------------------
task.spawn(function()
	task.wait(1)
	if SyncProgressiveUI then SyncProgressiveUI() end
end)

-- PlatformController
-- Location: StarterPlayer > StarterPlayerScripts > PlatformController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local AdminConfig = require(ReplicatedStorage.Modules.AdminConfig)
local Formatter = require(ReplicatedStorage.Modules.NumberFormatter) 

local ShipAuras       = ReplicatedStorage.RemoteEvents:WaitForChild("ShipAuras")
local UpdateMultiplier = ReplicatedStorage:WaitForChild("UpdateMultiplier")
local HabitatFullEvent = ReplicatedStorage:WaitForChild("HabitatFullEvent")

local TRUCK_SPAWN = workspace:WaitForChild("TruckSpawn")
local TRUCK_DEST  = workspace:WaitForChild("TruckDestination")
local HabitatHolder = workspace:WaitForChild("HabitatHolder") 

local Camera = workspace.CurrentCamera
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainHUD = playerGui:WaitForChild("MainHUD")
local currLabel = mainHUD:WaitForChild("CurrencyLabel")
local gaurasLabel = mainHUD:WaitForChild("GoldenAurasLabel")

local function GetHabitatPos()
	return HabitatHolder:WaitForChild("Position").Position
end

local currentMultiplier = 1.0
local platformQueue = {}
local processingPlatform = false

local MultiplierColors = {
	[1.0] = Color3.fromRGB(255, 255, 255),
	[1.5] = Color3.fromRGB(100, 200, 255),
	[2.0] = Color3.fromRGB(80, 255, 120),
	[3.0] = Color3.fromRGB(180, 60, 255),
	[5.0] = Color3.fromRGB(255, 200, 0),
}

local MultiplierNames = {
	[1.0] = "No Bonus",
	[1.5] = "1.5x Bonus",
	[2.0] = "2x Bonus",
	[3.0] = "3x Bonus",
	[5.0] = "5x Bonus",
}

UpdateMultiplier.Event:Connect(function(mult)
	currentMultiplier = mult
end)

local function FormatNumber(n)
	return Formatter.Format(math.floor(tonumber(n) or 0))
end

---------------------------------------------------------------
-- ✨ UNIVERSAL JUICY VISUALS (CASH & AURAS) ✨
---------------------------------------------------------------
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
	popupText.Text = (isAura and "+" or "+$") .. FormatNumber(exactAmount)
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

local function CreatePlatform()
	local platform = Instance.new("Part")
	platform.Name = "HoverPlatform"
	platform.Size = Vector3.new(8, 0.5, 8)
	platform.Anchored = true
	platform.CastShadow = false
	platform.Material = Enum.Material.Neon
	platform.Color = MultiplierColors[currentMultiplier] or Color3.fromRGB(255, 255, 255)
	platform.Position = TRUCK_SPAWN.Position + Vector3.new(0, AdminConfig.PlatformHoverHeight, 0)
	platform.Parent = workspace

	local light = Instance.new("PointLight")
	light.Brightness = 2
	light.Range = 12
	light.Color = platform.Color
	light.Parent = platform

	return platform
end

local function AttachLabels(platform, payout, multiplier)
	local payoutBB = Instance.new("BillboardGui")
	payoutBB.Size = UDim2.new(8, 0, 2.5, 0) 
	payoutBB.StudsOffset = Vector3.new(0, 5, 0)
	payoutBB.AlwaysOnTop = false
	payoutBB.Adornee = platform
	payoutBB.Parent = platform

	local payoutLabel = Instance.new("TextLabel")
	payoutLabel.Size = UDim2.new(1, 0, 1, 0)
	payoutLabel.BackgroundTransparency = 1
	payoutLabel.Text = "$" .. FormatNumber(payout)
	payoutLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
	payoutLabel.TextScaled = true
	payoutLabel.Font = Enum.Font.GothamBold
	payoutLabel.TextStrokeTransparency = 1
	payoutLabel.TextTransparency = 1
	payoutLabel.Parent = payoutBB

	local payoutStroke = Instance.new("UIStroke", payoutLabel)
	payoutStroke.Thickness = 3
	payoutStroke.Color = Color3.fromRGB(0, 40, 0)

	local multBB = Instance.new("BillboardGui")
	multBB.Size = UDim2.new(6, 0, 1.5, 0) 
	multBB.StudsOffset = Vector3.new(0, 2.5, 0)
	multBB.AlwaysOnTop = false
	multBB.Adornee = platform
	multBB.Parent = platform

	local multLabel = Instance.new("TextLabel")
	multLabel.Size = UDim2.new(1, 0, 1, 0)
	multLabel.BackgroundTransparency = 1
	multLabel.Text = MultiplierNames[multiplier] or "No Bonus"
	multLabel.TextColor3 = MultiplierColors[multiplier] or Color3.fromRGB(255, 255, 255)
	multLabel.TextScaled = true
	multLabel.Font = Enum.Font.Gotham
	multLabel.TextStrokeTransparency = 1
	multLabel.TextTransparency = 1
	multLabel.Parent = multBB

	local multStroke = Instance.new("UIStroke", multLabel)
	multStroke.Thickness = 2.5
	multStroke.Color = Color3.fromRGB(0, 0, 0)

	TweenService:Create(payoutLabel, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
	TweenService:Create(multLabel, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
end

local function PayoutPopup(position, payout, multiplier)
	local anchor = Instance.new("Part")
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Anchored = true
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.Position = position
	anchor.Parent = workspace

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(10, 0, 2.5, 0) 
	bb.StudsOffset = Vector3.new(0, 7, 0)
	bb.AlwaysOnTop = false
	bb.Adornee = anchor
	bb.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = "+ $" .. FormatNumber(payout)
	label.TextColor3 = MultiplierColors[multiplier] or Color3.fromRGB(100, 255, 100)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextStrokeTransparency = 1
	label.TextTransparency = 0
	label.Parent = bb

	local lStroke = Instance.new("UIStroke", label)
	lStroke.Thickness = 3
	lStroke.Color = Color3.fromRGB(0, 0, 0)

	TweenService:Create(bb, TweenInfo.new(1.8, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { StudsOffset = Vector3.new(0, 18, 0) }):Play()
	task.delay(0.6, function()
		TweenService:Create(label, TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1 }):Play()
		TweenService:Create(lStroke, TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
	end)
	Debris:AddItem(anchor, 2.5)
end

local function GetAuraBlocksNearHabitat()
	local blocks = {}
	local habitatPos = GetHabitatPos()  

	for _, obj in ipairs(workspace:GetChildren()) do
		if obj.Name == "HoverPlatform" or obj == HabitatHolder
			or obj == TRUCK_SPAWN or obj == TRUCK_DEST then
			continue
		end

		local rootPart = nil
		local isCube = false

		if obj:GetAttribute("AuraCube") then
			isCube = true
			if obj:IsA("Model") then
				rootPart = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
			elseif obj:IsA("BasePart") then
				rootPart = obj
			end
		elseif obj:IsA("Part") and obj.Material == Enum.Material.Neon then
			isCube = true
			rootPart = obj
		end

		if isCube and rootPart then
			local dist = (rootPart.Position - habitatPos).Magnitude  
			if dist < 20 then
				table.insert(blocks, { instance = obj, rootPart = rootPart })
			end
		end
	end
	return blocks
end

local function MagnetBlocks(platform, blocks, count)
	local collected = math.min(#blocks, count)
	if collected == 0 then return end

	local tweensDone = 0
	local tweensStarted = 0

	for i = 1, collected do
		local block = blocks[i]
		if not block or not block.rootPart or not block.rootPart.Parent then continue end

		local rootPart = block.rootPart
		local instance = block.instance

		rootPart.Anchored = true

		local tweenProps = { Position = platform.Position }
		if instance:IsA("BasePart") then
			tweenProps.Size = Vector3.new(0.1, 0.1, 0.1)
		end

		local tween = TweenService:Create(rootPart,
			TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			tweenProps
		)

		tweensStarted += 1
		tween.Completed:Connect(function()
			instance:Destroy()
			tweensDone += 1
		end)
		tween:Play()
		task.wait(0.05)
	end

	local timeout = tick() + 3
	while tweensDone < tweensStarted and tick() < timeout do
		task.wait(0.05)
	end
end

local function ProcessPlatform(info)
	if info.collected == 0 then return end

	local myPayout     = info.payout
	local myMultiplier = currentMultiplier
	local myDispatchId = info.dispatchId
	local platform     = CreatePlatform()

	local habitatPos = GetHabitatPos()

	local distIn = (TRUCK_SPAWN.Position - habitatPos).Magnitude
	local tweenIn = TweenService:Create(platform,
		TweenInfo.new(distIn / AdminConfig.PlatformSpeed, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = habitatPos + Vector3.new(0, AdminConfig.PlatformHoverHeight, 0) }
	)
	tweenIn:Play()
	tweenIn.Completed:Wait()

	AttachLabels(platform, myPayout, myMultiplier)
	PayoutPopup(platform.Position, myPayout, myMultiplier)

	local blocks = GetAuraBlocksNearHabitat()
	MagnetBlocks(platform, blocks, info.collected)

	task.wait(0.5)

	HabitatFullEvent:Fire(false)

	local distOut = (habitatPos - TRUCK_DEST.Position).Magnitude
	local tweenOut = TweenService:Create(platform,
		TweenInfo.new(distOut / AdminConfig.PlatformSpeed, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = TRUCK_DEST.Position + Vector3.new(0, AdminConfig.PlatformHoverHeight, 0) }
	)
	tweenOut:Play()
	tweenOut.Completed:Wait()

	platform:Destroy()
	ShipAuras:FireServer("payout", myDispatchId)
end

local function ProcessQueue()
	if processingPlatform then return end
	processingPlatform = true

	while #platformQueue > 0 do
		local nextInfo = table.remove(platformQueue, 1)
		ProcessPlatform(nextInfo)
	end

	processingPlatform = false
end

ShipAuras.OnClientEvent:Connect(function(info)
	if info.action == "payoutConfirmed" then
		PlayJuiceEffect(info.amount, "Currency")
	elseif info.action == "playJuice" then
		PlayJuiceEffect(info.amount, info.currencyType)
	else
		table.insert(platformQueue, info)
		task.spawn(ProcessQueue)
	end
end)

local LocalJuiceEvent = ReplicatedStorage:FindFirstChild("LocalJuiceEvent")
if not LocalJuiceEvent then
	LocalJuiceEvent = Instance.new("BindableEvent")
	LocalJuiceEvent.Name = "LocalJuiceEvent"
	LocalJuiceEvent.Parent = ReplicatedStorage
end
LocalJuiceEvent.Event:Connect(function(exactAmount, currencyType)
	PlayJuiceEffect(exactAmount, currencyType)
end)


-- ShippingManager
-- Location: ServerScriptService > ShippingManager

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local HttpService         = game:GetService("HttpService")

local AdminConfig      = require(ReplicatedStorage.Modules.AdminConfig)
local UpgradeConfig    = require(ReplicatedStorage.Modules.UpgradeConfig)
local MutationConfig   = require(ReplicatedStorage.Modules.MutationConfig)
local GameManager      = require(ServerScriptService.GameManager)
local EpicUpgradeConfig = require(ReplicatedStorage.Modules.EpicUpgradeConfig)

local ShipAuras = ReplicatedStorage.RemoteEvents:WaitForChild("ShipAuras")
local UpdateHUD = ReplicatedStorage.RemoteEvents:WaitForChild("UpdateHUD")

local playerTimers   = {}
local activeTrucks   = {}
local playerAutoMode = {}
local pendingPayouts = {}

-- ─────────────────────────────────────────────────────────────────────────────
-- PLAYER LIFECYCLE
-- ─────────────────────────────────────────────────────────────────────────────
Players.PlayerAdded:Connect(function(player)
	playerTimers[player.UserId]   = AdminConfig.ShipInterval
	activeTrucks[player.UserId]   = 0
	playerAutoMode[player.UserId] = AdminConfig.AutoDispatch
	pendingPayouts[player.UserId] = {}
end)

Players.PlayerRemoving:Connect(function(player)
	playerTimers[player.UserId]   = nil
	activeTrucks[player.UserId]   = nil
	playerAutoMode[player.UserId] = nil
	pendingPayouts[player.UserId] = nil
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- HUD UPDATE HELPER
-- ─────────────────────────────────────────────────────────────────────────────
local function SendHUDUpdate(player)
	local uid     = player.UserId
	local data    = GameManager.GetData(uid)
	local runtime = GameManager.GetRuntime(uid)
	if not data or not runtime then return end

	local totalMutatedValue = runtime.totalMutatedValue
	local pending           = runtime.cubeCount
	local avgValue          = pending > 0 and (totalMutatedValue / pending) or AdminConfig.BaseAuraValue
	local rate              = math.floor(pending * avgValue)

	local habCfg      = UpgradeConfig.GetUpgradeConfig("habitatCapacity")
	local habitatCap  = (habCfg and habCfg.apply) and habCfg.apply(data) or AdminConfig.BaseHabitatCapacity

	local tickCfg    = UpgradeConfig.GetUpgradeConfig("passiveTickSpeed")
	local passiveInt = (tickCfg and tickCfg.apply) and tickCfg.apply(data) or AdminConfig.PassiveInterval

	local shipReduction = 0
	local shipCfg = EpicUpgradeConfig.GetUpgradeConfig("epicShipCooldown")
	if shipCfg and shipCfg.apply then
		shipReduction = shipCfg.apply(data)
	end
	local finalCooldown = math.max(1, AdminConfig.ShipInterval - shipReduction)

	UpdateHUD:FireClient(player, {
		currency        = data.currency,
		pendingAuras    = pending,
		habitatCapacity = habitatCap,
		rate            = rate,
		passiveInterval = passiveInt,
		totalEarned     = data.totalEarned    or 0,
		soulAuras       = data.soulAuras      or 0,
		farmEvaluation  = data.farmEvaluation or 0,
		shipCooldown    = finalCooldown,
	})
end

-- ─────────────────────────────────────────────────────────────────────────────
-- DISPATCH
-- ─────────────────────────────────────────────────────────────────────────────
local function TryDispatch(player)
	if AdminConfig.DisableShipping then return end
	local uid     = player.UserId
	local data    = GameManager.GetData(uid)
	local runtime = GameManager.GetRuntime(uid)
	if not data or not runtime then return end
	if (activeTrucks[uid] or 0) >= 50 then return end

	local totalCubes = runtime.cubeCount
	if totalCubes <= 0 then return end

	local toCollect  = math.min(totalCubes, AdminConfig.PlatformCapacity)
	local cubeIds, cubes = GameManager.CollectOldestCubes(uid, toCollect)
	local collected  = #cubeIds
	if collected == 0 then return end

	local totalPayout = 0
	for _, cube in ipairs(cubes) do
		totalPayout = totalPayout + MutationConfig.GetMutatedValue(cube)
	end

	activeTrucks[uid] = (activeTrucks[uid] or 0) + 1
	data.totalPlatformsShipped = (data.totalPlatformsShipped or 0) + 1

	local dispatchId = HttpService:GenerateGUID(false)
	pendingPayouts[uid][dispatchId] = totalPayout

	SendHUDUpdate(player)

	ShipAuras:FireClient(player, {
		collected  = collected,
		payout     = totalPayout,
		dispatchId = dispatchId,
	})
end

-- ─────────────────────────────────────────────────────────────────────────────
-- SERVER EVENT
-- ─────────────────────────────────────────────────────────────────────────────
ShipAuras.OnServerEvent:Connect(function(player, action, value)
	local uid = player.UserId

	if action == "manual" then
		TryDispatch(player)

		local data          = GameManager.GetData(uid)
		local shipReduction = 0
		if data then
			local shipCfg = EpicUpgradeConfig.GetUpgradeConfig("epicShipCooldown")
			if shipCfg and shipCfg.apply then shipReduction = shipCfg.apply(data) end
		end
		playerTimers[uid] = math.max(1, AdminConfig.ShipInterval - shipReduction)
		return
	end

	if action == "setMode" then
		playerAutoMode[uid] = (value == "auto")
		return
	end

	if action == "payout" then
		if player:GetAttribute("TutorialFrozen") then return end

		local data = GameManager.GetData(uid)
		if not data then return end

		local dispatchId   = value
		local actualPayout = pendingPayouts[uid] and pendingPayouts[uid][dispatchId]

		if not actualPayout then
			warn("[Security] " .. player.Name .. " attempted invalid platform payout.")
			return
		end

		pendingPayouts[uid][dispatchId] = nil
		activeTrucks[uid] = math.max(0, (activeTrucks[uid] or 1) - 1)

		data.currency       = (data.currency       or 0) + actualPayout
		data.totalEarned    = (data.totalEarned     or 0) + actualPayout
		data.farmEvaluation = (data.farmEvaluation  or 0) + actualPayout

		SendHUDUpdate(player)

		ShipAuras:FireClient(player, {
			action = "payoutConfirmed",
			amount = actualPayout
		})
	end
end)
