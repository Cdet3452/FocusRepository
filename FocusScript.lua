-- PortalController
-- Location: StarterPlayer > StarterPlayerScripts > PortalController

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")

local AreaRegistry = require(ReplicatedStorage.Modules.AreaRegistry)
local SoundConfig  = require(ReplicatedStorage.Modules.SoundConfig)
local C            = require(ReplicatedStorage.Modules.UIConfig)
local Formatter    = require(ReplicatedStorage.Modules.NumberFormatter) 
local UITheme      = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UITheme"))
local T            = UITheme.Get("Custom")

local AreaUpdated      = ReplicatedStorage.RemoteEvents:WaitForChild("AreaUpdated")
local AreaUnlocked     = ReplicatedStorage.RemoteEvents:WaitForChild("AreaUnlocked")
local EnterPortal      = ReplicatedStorage.RemoteEvents:WaitForChild("EnterPortal")
local TravelToArea     = ReplicatedStorage.RemoteEvents:WaitForChild("TravelToArea")
local AreaChanged      = ReplicatedStorage.RemoteEvents:WaitForChild("AreaChanged")
local PrestigeComplete = ReplicatedStorage.RemoteEvents:WaitForChild("PrestigeComplete")
local UpdateHUD        = ReplicatedStorage.RemoteEvents:WaitForChild("UpdateHUD")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainHUD   = playerGui:WaitForChild("MainHUD")

local PositionPart = workspace:WaitForChild("AuraHolder"):WaitForChild("Position")

local promptAdded   = false
local currentArea   = 1
local portalReady   = false
local panelOpen     = false
local browseIndex   = 1
local liveFarmEval  = 0
local unlockedAreas = { 1 }
local MAX_AREA      = AreaRegistry.GetMaxArea()

local PW = C.Panels.AreaTravelW
local PH = C.Panels.AreaTravelH
local PR = C.Panels.CornerRadius
local BW = C.Banners.AreaBannerW
local BY = C.Banners.AreaBannerY
local BR = C.Banners.CornerRadius

local function PlayUI(id)
	if shared.PlayUISound then shared.PlayUISound(id) end
end

local function IsUnlocked(idx)
	for _, v in ipairs(unlockedAreas) do if v == idx then return true end end
	return false
end

local AreaAssets = ReplicatedStorage:WaitForChild("AreaAssets")

-- ✨ FLIPBOOK ANIMATION SYSTEM
local flipbookConnection = nil
local currentFlipbook = nil
local flipbookFrame = 1
local flipbookTime = 0

local function StopFlipbook()
	if flipbookConnection then
		flipbookConnection:Disconnect()
		flipbookConnection = nil
	end
	currentFlipbook = nil
end

local function StartFlipbook(areaIdx, AreaIcon)
	StopFlipbook()

	local flipbookData = AreaRegistry.GetFlipbook(areaIdx)
	if not flipbookData then return end

	currentFlipbook = flipbookData
	flipbookFrame = 1
	flipbookTime = 0

	if not AreaIcon then return end

	AreaIcon.Image = flipbookData.image
	AreaIcon.ImageRectSize = Vector2.new(flipbookData.frameW, flipbookData.frameH)
	AreaIcon.ImageRectOffset = Vector2.new(0, 0)

	flipbookConnection = RunService.RenderStepped:Connect(function(dt)
		flipbookTime += dt
		local frameTime = 1 / flipbookData.fps

		if flipbookTime >= frameTime then
			flipbookTime = flipbookTime % frameTime
			flipbookFrame = flipbookFrame + 1

			if flipbookFrame > flipbookData.frames then
				flipbookFrame = 1
			end

			local col = (flipbookFrame - 1) % flipbookData.columns
			local row = math.floor((flipbookFrame - 1) / flipbookData.columns)
			local offsetX = col * flipbookData.frameW
			local offsetY = row * flipbookData.frameH

			AreaIcon.ImageRectOffset = Vector2.new(offsetX, offsetY)
		end
	end)
end

-- UI Setup (StatsPanel)
local StatsPanel = Instance.new("Frame")
StatsPanel.Name="StatsPanel"; StatsPanel.Size = UDim2.new(0.88, 0, 0.82, 0)
StatsPanel.Position = UDim2.new(0.5, 0, 0.5, 0)
StatsPanel.AnchorPoint = Vector2.new(0.5, 0.5)
StatsPanel.BackgroundColor3=T.panelBG; StatsPanel.BorderSizePixel=0
StatsPanel.Visible=false; StatsPanel.ZIndex=30; StatsPanel.ClipsDescendants=true
StatsPanel.Parent=mainHUD
Instance.new("UICorner",StatsPanel).CornerRadius=UDim.new(0,PR)

local sizeConstraint = Instance.new("UISizeConstraint")
sizeConstraint.MaxSize = Vector2.new(PW, PH) 
sizeConstraint.Parent = StatsPanel

local panelStroke=Instance.new("UIStroke"); panelStroke.Color=T.panelStroke; panelStroke.Thickness=2; panelStroke.Parent=StatsPanel

local HeaderBar=Instance.new("Frame"); HeaderBar.Size=UDim2.new(1,0,0,46); HeaderBar.BackgroundColor3=T.headerBG
HeaderBar.BorderSizePixel=0; HeaderBar.ZIndex=31; HeaderBar.Parent=StatsPanel
Instance.new("UICorner",HeaderBar).CornerRadius=UDim.new(0,PR)
local HeaderLabel=Instance.new("TextLabel"); HeaderLabel.Size=UDim2.new(1,-50,1,0); HeaderLabel.Position=UDim2.new(0,16,0,0)
HeaderLabel.BackgroundTransparency=1; HeaderLabel.Text="AREA TRAVEL"; HeaderLabel.TextColor3=T.headerText
HeaderLabel.TextScaled=true; HeaderLabel.Font=T.font; HeaderLabel.TextXAlignment=Enum.TextXAlignment.Left
HeaderLabel.ZIndex=32; HeaderLabel.Parent=HeaderBar
local CloseBtn=Instance.new("TextButton"); CloseBtn.Size=UDim2.new(0,32,0,32); CloseBtn.Position=UDim2.new(1,-40,0.5,-16)
CloseBtn.BackgroundColor3=T.buttonRed; CloseBtn.BorderSizePixel=0; CloseBtn.Text="X"; CloseBtn.TextColor3=T.bodyText
CloseBtn.TextScaled=true; CloseBtn.Font=T.font; CloseBtn.ZIndex=33; CloseBtn.Parent=HeaderBar
CloseBtn:SetAttribute("TutorialTarget", "PortalCloseBtn")
Instance.new("UICorner",CloseBtn).CornerRadius=UDim.new(0,6)

local ScrollContainer = Instance.new("ScrollingFrame")
ScrollContainer.Name = "ScrollContainer"
ScrollContainer.Size = UDim2.new(1, 0, 1, -46) 
ScrollContainer.Position = UDim2.new(0, 0, 0, 46) 
ScrollContainer.BackgroundTransparency = 1
ScrollContainer.BorderSizePixel = 0
ScrollContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
ScrollContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y 
ScrollContainer.ScrollBarThickness = 6
ScrollContainer.Parent = StatsPanel

local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 10) 
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center 
listLayout.Parent = ScrollContainer

local topPadding = Instance.new("UIPadding")
topPadding.PaddingTop = UDim.new(0, 10)
topPadding.PaddingBottom = UDim.new(0, 10)
topPadding.Parent = ScrollContainer

local GoalSection=Instance.new("Frame"); GoalSection.Size=UDim2.new(1,-24,0,90)
GoalSection.BackgroundColor3=T.cardBG; GoalSection.BorderSizePixel=0; GoalSection.ZIndex=31; GoalSection.Parent=ScrollContainer
Instance.new("UICorner",GoalSection).CornerRadius=UDim.new(0,8)
local FarmEvalTitle=Instance.new("TextLabel"); FarmEvalTitle.Size=UDim2.new(1,-12,0,16); FarmEvalTitle.Position=UDim2.new(0,12,0,6)
FarmEvalTitle.BackgroundTransparency=1; FarmEvalTitle.Text="FARM EVALUATION"; FarmEvalTitle.TextColor3=T.subText
FarmEvalTitle.TextScaled=true; FarmEvalTitle.Font=T.font; FarmEvalTitle.TextXAlignment=Enum.TextXAlignment.Left
FarmEvalTitle.ZIndex=32; FarmEvalTitle.Parent=GoalSection
local FarmEvalNumber=Instance.new("TextLabel"); FarmEvalNumber.Name="FarmEvalNumber"
FarmEvalNumber.Size=UDim2.new(1,-12,0,28); FarmEvalNumber.Position=UDim2.new(0,12,0,22)
FarmEvalNumber.BackgroundTransparency=1; FarmEvalNumber.Text="$0"; FarmEvalNumber.TextColor3=T.accentGreen
FarmEvalNumber.TextScaled=true; FarmEvalNumber.Font=T.font; FarmEvalNumber.TextXAlignment=Enum.TextXAlignment.Left
FarmEvalNumber.ZIndex=32; FarmEvalNumber.Parent=GoalSection
local ProgressBG=Instance.new("Frame"); ProgressBG.Size=UDim2.new(1,-24,0,8); ProgressBG.Position=UDim2.new(0,12,0,54)
ProgressBG.BackgroundColor3=Color3.fromRGB(40,50,70); ProgressBG.BorderSizePixel=0; ProgressBG.ZIndex=32; ProgressBG.Parent=GoalSection
Instance.new("UICorner",ProgressBG).CornerRadius=UDim.new(0,4)
local ProgressFill=Instance.new("Frame"); ProgressFill.Name="ProgressFill"; ProgressFill.Size=UDim2.new(0,0,1,0)
ProgressFill.BackgroundColor3=T.accentGreen; ProgressFill.BorderSizePixel=0; ProgressFill.ZIndex=33; ProgressFill.Parent=ProgressBG
Instance.new("UICorner",ProgressFill).CornerRadius=UDim.new(0,4)
local ProgressLabel=Instance.new("TextLabel"); ProgressLabel.Name="ProgressLabel"
ProgressLabel.Size=UDim2.new(1,-12,0,14); ProgressLabel.Position=UDim2.new(0,12,0,66)
ProgressLabel.BackgroundTransparency=1; ProgressLabel.Text=""; ProgressLabel.TextColor3=T.subText
ProgressLabel.TextScaled=true; ProgressLabel.Font=T.fontBody; ProgressLabel.TextXAlignment=Enum.TextXAlignment.Left
ProgressLabel.ZIndex=32; ProgressLabel.Parent=GoalSection

local AreaBrowser=Instance.new("Frame"); AreaBrowser.Size=UDim2.new(1,-24,0,260)
AreaBrowser.BackgroundColor3=T.cardBG; AreaBrowser.BorderSizePixel=0; AreaBrowser.ZIndex=31; AreaBrowser.Parent=ScrollContainer
Instance.new("UICorner",AreaBrowser).CornerRadius=UDim.new(0,8)
local BrowseAreaName=Instance.new("TextLabel"); BrowseAreaName.Size=UDim2.new(0.6, 0, 0, 24)
BrowseAreaName.AnchorPoint=Vector2.new(0.5, 0)
BrowseAreaName.Position=UDim2.new(0.5, 0, 0, 8)
BrowseAreaName.BackgroundTransparency=1; BrowseAreaName.Text="Starter Area"; BrowseAreaName.TextColor3=T.accentBlue
BrowseAreaName.TextScaled=true; BrowseAreaName.Font=T.font; BrowseAreaName.TextXAlignment=Enum.TextXAlignment.Center
BrowseAreaName.ZIndex=32; BrowseAreaName.Parent=AreaBrowser
local AreaIndexLabel=Instance.new("TextLabel"); AreaIndexLabel.Size=UDim2.new(0,60,0,20); AreaIndexLabel.Position=UDim2.new(1,-66,0,10)
AreaIndexLabel.BackgroundTransparency=1; AreaIndexLabel.Text="1/5"; AreaIndexLabel.TextColor3=T.subText
AreaIndexLabel.TextScaled=true; AreaIndexLabel.Font=T.fontBody; AreaIndexLabel.TextXAlignment=Enum.TextXAlignment.Right
AreaIndexLabel.ZIndex=32; AreaIndexLabel.Parent=AreaBrowser
local BrowseAreaMult=Instance.new("TextLabel"); BrowseAreaMult.Size=UDim2.new(1,-20,0,18); BrowseAreaMult.Position=UDim2.new(0,10,0,34)
BrowseAreaMult.BackgroundTransparency=1; BrowseAreaMult.Text="Cube Value: 1.0x base"; BrowseAreaMult.TextColor3=T.accentGold
BrowseAreaMult.TextScaled=true; BrowseAreaMult.Font=T.fontBody; BrowseAreaMult.TextXAlignment=Enum.TextXAlignment.Center
BrowseAreaMult.ZIndex=32; BrowseAreaMult.Parent=AreaBrowser
local LeftArrow=Instance.new("TextButton"); LeftArrow.Size=UDim2.new(0,36,0,36); LeftArrow.Position=UDim2.new(0,8,0,62)
LeftArrow.BackgroundColor3=T.headerBG; LeftArrow.BorderSizePixel=0; LeftArrow.Text="<"; LeftArrow.TextColor3=T.bodyText
LeftArrow.TextScaled=true; LeftArrow.Font=T.font; LeftArrow.ZIndex=33; LeftArrow.Parent=AreaBrowser
Instance.new("UICorner",LeftArrow).CornerRadius=UDim.new(0,18)
local RightArrow=Instance.new("TextButton"); RightArrow.Size=UDim2.new(0,36,0,36); RightArrow.Position=UDim2.new(1,-44,0,62)
RightArrow.BackgroundColor3=T.headerBG; RightArrow.BorderSizePixel=0; RightArrow.Text=">"; RightArrow.TextColor3=T.bodyText
RightArrow.TextScaled=true; RightArrow.Font=T.font; RightArrow.ZIndex=33; RightArrow.Parent=AreaBrowser
RightArrow:SetAttribute("TutorialTarget", "ArrowBtn")
Instance.new("UICorner",RightArrow).CornerRadius=UDim.new(0,18)
local AreaIcon = Instance.new("ImageLabel")
AreaIcon.Name = "AreaIcon" 
AreaIcon.AnchorPoint = Vector2.new(0.5, 0)
AreaIcon.Size = UDim2.new(0, 110, 0, 110)
AreaIcon.Position = UDim2.new(0.5, 0, 0, 54)
AreaIcon.BackgroundTransparency = 1
AreaIcon.BorderSizePixel = 0
AreaIcon.ZIndex = 33
AreaIcon.Image = "" 
AreaIcon.Parent = AreaBrowser
local BrowseStatus=Instance.new("TextLabel"); BrowseStatus.Size=UDim2.new(1,-24,0,20); BrowseStatus.Position=UDim2.new(0,12,0,172)
BrowseStatus.BackgroundTransparency=1; BrowseStatus.Text="CURRENT AREA"; BrowseStatus.TextColor3=T.subText
BrowseStatus.TextScaled=true; BrowseStatus.Font=T.font; BrowseStatus.TextXAlignment=Enum.TextXAlignment.Center
BrowseStatus.ZIndex=32; BrowseStatus.Parent=AreaBrowser
local BrowseProgress=Instance.new("TextLabel"); BrowseProgress.Size=UDim2.new(1,-24,0,28); BrowseProgress.Position=UDim2.new(0,12,0,194)
BrowseProgress.BackgroundTransparency=1; BrowseProgress.Text=""; BrowseProgress.TextColor3=T.subText
BrowseProgress.TextScaled=true; BrowseProgress.Font=T.fontBody; BrowseProgress.TextWrapped=true
BrowseProgress.TextXAlignment=Enum.TextXAlignment.Center; BrowseProgress.ZIndex=32; BrowseProgress.Parent=AreaBrowser
local TravelBtn=Instance.new("TextButton"); TravelBtn.Size=UDim2.new(1,-24,0,38); TravelBtn.Position=UDim2.new(0,12,0,220)
TravelBtn.BackgroundColor3=T.buttonGreen; TravelBtn.BorderSizePixel=0; TravelBtn.Text="TRAVEL"; TravelBtn.TextColor3=T.bodyText
TravelBtn.TextScaled=true; TravelBtn.Font=T.font; TravelBtn.Visible=false; TravelBtn.ZIndex=33; TravelBtn.Parent=AreaBrowser
TravelBtn:SetAttribute("TutorialTarget", "TravelBtn")
Instance.new("UICorner",TravelBtn).CornerRadius=UDim.new(0,8)

local function AddButtonJuice(btn)
	local scale = btn:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", btn)
	btn.MouseEnter:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Sine), {Scale = 1.08}):Play() end)
	btn.MouseLeave:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Sine), {Scale = 1}):Play() end)
	btn.MouseButton1Down:Connect(function() TweenService:Create(scale, TweenInfo.new(0.1, Enum.EasingStyle.Sine), {Scale = 0.9}):Play() end)
	btn.MouseButton1Up:Connect(function() TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), {Scale = 1.08}):Play() end)
end

AddButtonJuice(LeftArrow)
AddButtonJuice(RightArrow)
AddButtonJuice(TravelBtn)
AddButtonJuice(CloseBtn)

TravelBtn.MouseButton1Down:Connect(function()
	if browseIndex == currentArea then return end
	TravelToArea:FireServer(browseIndex)
end)

local function UpdateGoalSection()
	FarmEvalNumber.Text = "$" .. Formatter.Format(liveFarmEval)
	local nextGoalArea, nextGoalThreshold = nil, nil
	for i = currentArea + 1, MAX_AREA do
		local area = AreaRegistry.Get(i)
		if area and liveFarmEval < (area.threshold or 0) then
			nextGoalArea = i; nextGoalThreshold = area.threshold; break
		end
	end
	if nextGoalThreshold and nextGoalThreshold > 0 then
		local pct = math.clamp(liveFarmEval / nextGoalThreshold, 0, 1)
		TweenService:Create(ProgressFill, TweenInfo.new(0.3), { Size = UDim2.new(pct,0,1,0) }):Play()
		ProgressFill.BackgroundColor3 = pct >= 1 and Color3.fromRGB(80,255,160) or T.accentGreen
		local needed = math.max(0, nextGoalThreshold - liveFarmEval)
		ProgressLabel.Text = needed <= 0
			and "New areas available! Browse below."
			or "$" .. Formatter.Format(needed) .. " to unlock " .. AreaRegistry.GetName(nextGoalArea)
		ProgressLabel.TextColor3 = needed <= 0 and T.accentTeal or T.subText
	elseif portalReady then
		ProgressFill.Size = UDim2.new(1,0,1,0); ProgressFill.BackgroundColor3 = T.accentTeal
		ProgressLabel.Text = "Areas available! Pick a destination."; ProgressLabel.TextColor3 = T.accentTeal
	elseif currentArea >= MAX_AREA then
		ProgressFill.Size = UDim2.new(1,0,1,0); ProgressFill.BackgroundColor3 = T.accentGold
		ProgressLabel.Text = "Maximum area reached."; ProgressLabel.TextColor3 = T.accentGold
	end
end

local function RefreshBrowser()
	local idx = browseIndex
	local areaData = AreaRegistry.Get(idx)	
	if not areaData then return end
	AreaIndexLabel.Text = idx .. " / " .. MAX_AREA
	LeftArrow.Visible  = idx > 1
	RightArrow.Visible = AreaRegistry.Get(idx+1) ~= nil

	local highestUnlocked = 1
	for _, v in ipairs(unlockedAreas) do
		if v > highestUnlocked then highestUnlocked = v end
	end

	local unlockReq = areaData.threshold or 0
	local discReq = areaData.discoveryThreshold or (unlockReq * 0.25) 

	if idx <= highestUnlocked then
		local flipbookData = AreaRegistry.GetFlipbook(idx)
		if flipbookData then
			StartFlipbook(idx, AreaIcon)
			AreaIcon.ImageColor3 = Color3.fromRGB(255, 255, 255)
		else
			StopFlipbook()
			AreaIcon.Image = areaData.auraPreviewImage or ""
			AreaIcon.ImageRectSize = Vector2.new(0, 0)
			AreaIcon.ImageRectOffset = Vector2.new(0, 0)
			AreaIcon.ImageColor3 = Color3.fromRGB(255, 255, 255)
		end
		BrowseAreaName.Text = AreaRegistry.GetName(idx)
		BrowseAreaMult.Text = "Cube Value: " .. string.format("%.1f", AreaRegistry.GetMultiplier(idx)) .. "x base"

		if idx == currentArea then
			BrowseStatus.Text = "CURRENT AREA"; BrowseStatus.TextColor3 = T.accentGreen
			BrowseProgress.Text = "This is your active farm."
			BrowseProgress.TextColor3 = T.accentTeal
			TravelBtn.Visible = false
		else
			BrowseStatus.Text = "PREVIOUS AREA"; BrowseStatus.TextColor3 = T.accentGreen
			BrowseProgress.Text = "Travel back for free (no reset)."
			BrowseProgress.TextColor3 = T.accentGreen
			TravelBtn.Visible = true; TravelBtn.Text = "Travel"
			TravelBtn.BackgroundColor3 = Color3.fromRGB(60,100,60)
		end

	elseif idx == highestUnlocked + 1 then
		if liveFarmEval >= unlockReq then
			local flipbookData = AreaRegistry.GetFlipbook(idx)
			if flipbookData then
				StartFlipbook(idx, AreaIcon)
				AreaIcon.ImageColor3 = Color3.fromRGB(255, 255, 255)
			else
				StopFlipbook()
				AreaIcon.Image = areaData.auraPreviewImage or ""
				AreaIcon.ImageRectSize = Vector2.new(0, 0)
				AreaIcon.ImageRectOffset = Vector2.new(0, 0)
				AreaIcon.ImageColor3 = Color3.fromRGB(255, 255, 255)
			end
			BrowseAreaName.Text = AreaRegistry.GetName(idx)
			BrowseAreaMult.Text = "Cube Value: " .. string.format("%.1f", AreaRegistry.GetMultiplier(idx)) .. "x base"
			BrowseStatus.Text = "UNLOCKED"; BrowseStatus.TextColor3 = T.accentTeal
			BrowseProgress.Text = "Travel here (resets current run)."
			BrowseProgress.TextColor3 = T.accentTeal
			TravelBtn.Visible = true; TravelBtn.Text = "TRAVEL"
			TravelBtn.BackgroundColor3 = T.buttonGreen

		elseif liveFarmEval >= discReq then
			local flipbookData = AreaRegistry.GetFlipbook(idx)
			if flipbookData then
				StartFlipbook(idx, AreaIcon)
				AreaIcon.ImageColor3 = Color3.fromRGB(180, 180, 180)
			else
				StopFlipbook()
				AreaIcon.Image = areaData.auraPreviewImage or ""
				AreaIcon.ImageRectSize = Vector2.new(0, 0)
				AreaIcon.ImageRectOffset = Vector2.new(0, 0)
				AreaIcon.ImageColor3 = Color3.fromRGB(255, 255, 255)
			end
			BrowseAreaName.Text = AreaRegistry.GetName(idx)
			BrowseAreaMult.Text = "Cube Value: " .. string.format("%.1f", AreaRegistry.GetMultiplier(idx)) .. "x base"
			BrowseStatus.Text = "DISCOVERED"; BrowseStatus.TextColor3 = T.accentPurple

			local needed = math.max(0, unlockReq - liveFarmEval)
			BrowseProgress.Text = "Requires $"..Formatter.Format(unlockReq).." Farm Eval\n$"..Formatter.Format(needed).." remaining"
			BrowseProgress.TextColor3 = T.subText
			TravelBtn.Visible = false

		else
			StopFlipbook()
			AreaIcon.Image = areaData.auraPreviewImage or ""
			AreaIcon.ImageRectSize = Vector2.new(0, 0)
			AreaIcon.ImageRectOffset = Vector2.new(0, 0)
			AreaIcon.ImageColor3 = Color3.fromRGB(0, 0, 0) 
			BrowseAreaName.Text = "???"
			BrowseAreaMult.Text = "???x base"
			BrowseStatus.Text = "UNDISCOVERED"; BrowseStatus.TextColor3 = T.subText

			local needed = math.max(0, discReq - liveFarmEval)
			BrowseProgress.Text = "Keep growing to discover what's next.\n$"..Formatter.Format(needed).." to Discover"
			BrowseProgress.TextColor3 = T.subText
			TravelBtn.Visible = false
		end

	else
		StopFlipbook()
		AreaIcon.Image = areaData.auraPreviewImage or ""
		AreaIcon.ImageRectSize = Vector2.new(0, 0)
		AreaIcon.ImageRectOffset = Vector2.new(0, 0)
		AreaIcon.ImageColor3 = Color3.fromRGB(0, 0, 0)
		BrowseAreaName.Text = "???"
		BrowseAreaMult.Text = "???x base"
		BrowseStatus.Text = "LOCKED"; BrowseStatus.TextColor3 = T.subText
		BrowseProgress.Text = "Unlock previous areas first."
		BrowseProgress.TextColor3 = T.subText
		TravelBtn.Visible = false
	end
end

LeftArrow.MouseButton1Down:Connect(function()
	if browseIndex > 1 then browseIndex -= 1; PlayUI(SoundConfig.UIArrow); RefreshBrowser() end
end)
RightArrow.MouseButton1Down:Connect(function()
	if AreaRegistry.Get(browseIndex+1) then browseIndex += 1; PlayUI(SoundConfig.UIArrow); RefreshBrowser() end
end)

local StatsBtn=Instance.new("TextButton"); StatsBtn.Name="NextAreaButton"
StatsBtn.Size=UDim2.new(0,C.HUD.NextAreaButtonW,0,C.HUD.NextAreaButtonH)
StatsBtn.Position=UDim2.new(0,156,1,C.HUD.BottomButtonY)
StatsBtn.BackgroundColor3=T.headerBG; StatsBtn.BorderSizePixel=0
StatsBtn.Text="Next Area"; StatsBtn.TextColor3=T.bodyText; StatsBtn.TextScaled=true; StatsBtn.Font=T.font
StatsBtn.Visible = false
StatsBtn.ZIndex=10; StatsBtn.Parent=mainHUD
StatsBtn:SetAttribute("TutorialTarget", "AreaTravelButton")
Instance.new("UICorner",StatsBtn).CornerRadius=UDim.new(0,8)
AddButtonJuice(StatsBtn)

local function OpenPanel()
	panelOpen=true; browseIndex=currentArea; UpdateGoalSection(); RefreshBrowser()
	StatsPanel.Visible=true
	StatsPanel.Size=UDim2.new(0.88, 0, 0, 0)
	TweenService:Create(StatsPanel, TweenInfo.new(0.35,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
		{ Size=UDim2.new(0.88, 0, 0.82, 0) }):Play()
	UITheme.SetMenuVisible(true)
end

local function ClosePanel()
	panelOpen=false; StopFlipbook(); PlayUI(SoundConfig.UIClose)
	TweenService:Create(StatsPanel, TweenInfo.new(0.25,Enum.EasingStyle.Quad,Enum.EasingDirection.In),
		{ Size=UDim2.new(0.88, 0, 0, 0) }):Play()
	UITheme.SetMenuVisible(false)
	task.delay(0.3, function() StatsPanel.Visible=false end)
end
StatsBtn.MouseButton1Down:Connect(function() if panelOpen then ClosePanel() else OpenPanel() end end)
CloseBtn.MouseButton1Down:Connect(ClosePanel)

local function ShowAreaBanner(info)
	if info.travelType == "backward" then return end
	local areaIndex = info.newArea or 2
	local areaData = AreaRegistry.Get(areaIndex)
	local areaName = info.areaName or AreaRegistry.GetName(areaIndex)
	local multText = "Cube Value: "..string.format("%.1f", info.areaMultiplier or 1.0).."x"
	local saText = (info.newSoulAuras and info.newSoulAuras > 0)
		and ("+"..Formatter.Format(info.newSoulAuras).." Soul Auras") or nil
	local accentColor = (areaData and areaData.auraHolderGlow) or T.accentTeal
	local bannerH = saText and 82 or 64
	local banner=Instance.new("Frame"); banner.Size=UDim2.new(0,BW,0,bannerH)
	banner.Position=UDim2.new(0,-(BW+10),0,BY); banner.BackgroundColor3=T.panelBG; banner.BorderSizePixel=0
	banner.ZIndex=55; banner.ClipsDescendants=true; banner.Parent=mainHUD
	Instance.new("UICorner",banner).CornerRadius=UDim.new(0,BR)
	local bs=Instance.new("UIStroke"); bs.Color=accentColor; bs.Thickness=1.5; bs.Parent=banner
	local nameLabel=Instance.new("TextLabel"); nameLabel.Size=UDim2.new(1,-12,0,22); nameLabel.Position=UDim2.new(0,10,0,6)
	nameLabel.BackgroundTransparency=1; nameLabel.Text=areaName; nameLabel.TextColor3=accentColor
	nameLabel.TextScaled=true; nameLabel.Font=T.font; nameLabel.TextXAlignment=Enum.TextXAlignment.Left
	nameLabel.ZIndex=56; nameLabel.Parent=banner
	local multLabel=Instance.new("TextLabel"); multLabel.Size=UDim2.new(1,-12,0,18); multLabel.Position=UDim2.new(0,10,0,30)
	multLabel.BackgroundTransparency=1; multLabel.Text=multText; multLabel.TextColor3=T.accentGold
	multLabel.TextScaled=true; multLabel.Font=T.fontBody; multLabel.TextXAlignment=Enum.TextXAlignment.Left
	multLabel.ZIndex=56; multLabel.Parent=banner
	if saText then
		local saLabel=Instance.new("TextLabel"); saLabel.Size=UDim2.new(1,-12,0,16); saLabel.Position=UDim2.new(0,10,0,52)
		saLabel.BackgroundTransparency=1; saLabel.Text=saText; saLabel.TextColor3=T.accentPurple
		saLabel.TextScaled=true; saLabel.Font=T.fontBody; saLabel.TextXAlignment=Enum.TextXAlignment.Left
		saLabel.ZIndex=56; saLabel.Parent=banner
	end
	TweenService:Create(banner, TweenInfo.new(0.4,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
		{ Position=UDim2.new(0,10,0,BY) }):Play()
	task.delay(4, function()
		TweenService:Create(banner, TweenInfo.new(0.35,Enum.EasingStyle.Quad,Enum.EasingDirection.In),
			{ Position=UDim2.new(0,-(BW+10),0,BY) }):Play()
		task.delay(0.4, function() if banner and banner.Parent then banner:Destroy() end end)
	end)
end

UpdateHUD.OnClientEvent:Connect(function(stats)
	if stats.farmEvaluation ~= nil then liveFarmEval = stats.farmEvaluation end
	if panelOpen then UpdateGoalSection(); RefreshBrowser() end
end)

AreaUpdated.OnClientEvent:Connect(function(info)
	currentArea = info.currentArea or 1
	if currentArea > 1 then player:SetAttribute("TutorialCompleted", true) end
	portalReady = info.portalReady == true
	if info.unlockedAreas then unlockedAreas = info.unlockedAreas end
	MAX_AREA = info.maxArea or AreaRegistry.GetMaxArea()
	if info.portalReady then AddPortalPrompt() else RemovePortalPrompt() end
	if panelOpen then UpdateGoalSection(); RefreshBrowser() end
end)

AreaUnlocked.OnClientEvent:Connect(function(info)
	portalReady = true; AddPortalPrompt()
	if info.unlockedAreas then unlockedAreas = info.unlockedAreas end
	local count = info.newAreasCount or 1
	local highestName = info.highestNewName or "New Area"
	local PBW = C.Banners.PortalBannerW; local PBH = C.Banners.PortalBannerH
	local banner=Instance.new("Frame"); banner.Size=UDim2.new(0,PBW,0,PBH)
	banner.Position=UDim2.new(0.5,-PBW/2,0,-PBH-10); banner.BackgroundColor3=T.panelBG; banner.BorderSizePixel=0
	banner.ZIndex=60; banner.Parent=mainHUD
	Instance.new("UICorner",banner).CornerRadius=UDim.new(0,BR)
	local bStroke=Instance.new("UIStroke"); bStroke.Color=T.accentTeal; bStroke.Thickness=2; bStroke.Parent=banner
	local bLabel=Instance.new("TextLabel"); bLabel.Size=UDim2.new(1,-20,1,0); bLabel.Position=UDim2.new(0,10,0,0)
	bLabel.BackgroundTransparency=1
	bLabel.Text = count == 1
		and (highestName.." unlocked! Open Area Travel.")
		or (count.." new areas unlocked! Open Area Travel to choose.")
	bLabel.TextColor3=T.accentTeal; bLabel.TextScaled=true; bLabel.Font=T.font; bLabel.ZIndex=61; bLabel.Parent=banner
	TweenService:Create(banner, TweenInfo.new(0.4,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
		{ Position=UDim2.new(0.5,-PBW/2,0,14) }):Play()
	task.delay(5, function()
		TweenService:Create(banner, TweenInfo.new(0.35,Enum.EasingStyle.Quad,Enum.EasingDirection.In),
			{ Position=UDim2.new(0.5,-PBW/2,0,-PBH-10) }):Play()
		task.delay(0.4, function() if banner and banner.Parent then banner:Destroy() end end)
	end)
end)

PrestigeComplete.OnClientEvent:Connect(function(info)
	if info.isPortalEntry then
		portalReady=false; liveFarmEval=0; RemovePortalPrompt()
		if panelOpen then ClosePanel() end
	end
end)

AreaChanged.OnClientEvent:Connect(function(info)
	currentArea = info.newArea or currentArea; browseIndex = currentArea; portalReady = false
	if info.unlockedAreas then unlockedAreas = info.unlockedAreas end
	if panelOpen then ClosePanel() end
	ShowAreaBanner(info)
end)

function AddPortalPrompt()
	if promptAdded then return end; promptAdded = true
	local prompt=Instance.new("ProximityPrompt"); prompt.Name="PortalPrompt"; prompt.ObjectText="Portal"
	prompt.ActionText="Open Area Travel"; prompt.HoldDuration=0.5; prompt.MaxActivationDistance=12
	prompt.Parent=PositionPart
	prompt.Triggered:Connect(function(p) if p == player and not panelOpen then OpenPanel() end end)
end

function RemovePortalPrompt()
	promptAdded=false; local e=PositionPart:FindFirstChild("PortalPrompt"); if e then e:Destroy() end
end

local function RefreshLook()
	UITheme.Apply(StatsPanel, "Panel")
	UITheme.Apply(HeaderBar, "TitleBar")
	UITheme.Apply(GoalSection, "ShopCard")
	UITheme.Apply(AreaBrowser, "ShopCard")
	UITheme.Apply(HeaderBar, "Panel")
	UITheme.Apply(RightArrow, "Panel")
	UITheme.Apply(LeftArrow, "Panel")
	UITheme.Apply(StatsBtn, "Panel")
	UITheme.ApplyShine(AreaBrowser)
	UITheme.ApplyShine(GoalSection)
	UITheme.ApplyShine(StatsPanel)
	GoalSection.BackgroundColor3 = T.cardBG 
	AreaBrowser.BackgroundColor3 = T.cardBG
	local outerStroke = StatsPanel:FindFirstChildWhichIsA("UIStroke")
	if outerStroke then outerStroke.Color = Color3.fromRGB(255, 255, 255) end
end

task.wait(2)
RefreshLook()



-- AreaTransitionController
-- Location: StarterPlayer > StarterPlayerScripts > AreaTransitionController
--
-- PER-AREA AURA PLACEMENT:
--   yOffset   = studs up/down from Position Part  (e.g. 5 = 5 studs above)
--   yRotation = degrees of Y-axis rotation        (e.g. 90 = quarter turn)
--   Both set in AreaRegistry per area.
--
-- AURA MODEL LOOKUP ORDER:
--   1. ReplicatedStorage/AreaAssets/Area{N}/AuraModel
--   2. workspace/Map/Ignore/Area{N}Aura
--
-- ALL TweenService:Create calls wrapped in pcall.
-- activeSwap has 10s timeout — no permanent deadlock.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local Lighting          = game:GetService("Lighting")

local AreaRegistry = require(ReplicatedStorage.Modules.AreaRegistry)

local AreaChanged = ReplicatedStorage.RemoteEvents:WaitForChild("AreaChanged")
local AreaUpdated = ReplicatedStorage.RemoteEvents:WaitForChild("AreaUpdated")

local Map        = workspace:WaitForChild("Map")
local AuraHolder = workspace:WaitForChild("AuraHolder")
local HabitatHolder = workspace:WaitForChild("HabitatHolder") 
local AreaAssets = ReplicatedStorage:WaitForChild("AreaAssets")
local MapIgnore  = Map:FindFirstChild("Ignore")
local HabitatPositionPart = HabitatHolder:WaitForChild("Position") 
local PositionPart = AuraHolder:WaitForChild("Position")

local DECORATION_CONTAINER = Map:WaitForChild("Path")

local TWEEN_DURATION = 2.5
local FADE_DURATION  = 0.5
local SWAP_TIMEOUT   = 10

local MAP_PART_COLORS = {
	Floor      = "grassColor",
	AssetFloor = "grassColor",
	Path       = "pathColor",
}

local currentAuraModel = nil
local activeSwap       = false
local swapStartedAt    = 0

---------------------------------------------------------------
-- SAFE TWEEN
---------------------------------------------------------------
local function SafeTween(instance, tweenInfo, properties)
	pcall(function()
		TweenService:Create(instance, tweenInfo, properties):Play()
	end)
end

---------------------------------------------------------------
-- TRANSPARENCY HELPERS
---------------------------------------------------------------
local function SetTransparency(obj, alpha)
	if obj:IsA("BasePart") then
		pcall(function() obj.Transparency = alpha end)
	elseif obj:IsA("Model") then
		for _, p in ipairs(obj:GetDescendants()) do
			if p:IsA("BasePart") then
				pcall(function() p.Transparency = alpha end)
			end
		end
	end
end

local function TweenTransparency(obj, alpha, duration)
	local info   = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	local tweens = {}
	local parts  = {}
	if obj:IsA("BasePart") then
		table.insert(parts, obj)
	elseif obj:IsA("Model") then
		for _, p in ipairs(obj:GetDescendants()) do
			if p:IsA("BasePart") then table.insert(parts, p) end
		end
	end
	for _, part in ipairs(parts) do
		local ok, t = pcall(function()
			return TweenService:Create(part, info, { Transparency = alpha })
		end)
		if ok and t then t:Play(); table.insert(tweens, t) end
	end
	return tweens
end

---------------------------------------------------------------
-- PLACE AT POSITION WITH OFFSET + ROTATION
-- Builds a CFrame from Position Part + yOffset + yRotation.
--   yOffset   = studs along world Y axis
--   yRotation = degrees around world Y axis
---------------------------------------------------------------
local function PlaceAtPosition(obj, yOffset, yRotation)
	local pos      = PositionPart.Position + Vector3.new(0, yOffset or 0, 0)
	local rotation = CFrame.Angles(0, math.rad(yRotation or 0), 0)
	local targetCF = CFrame.new(pos) * rotation

	pcall(function()
		if obj:IsA("Model") then
			obj:PivotTo(targetCF)
		elseif obj:IsA("BasePart") then
			obj.CFrame = targetCF
		end
	end)
end

---------------------------------------------------------------
-- AURA MODEL LOOKUP
---------------------------------------------------------------
local function GetAuraTemplate(areaIndex)
	local folder  = AreaAssets:FindFirstChild("Area" .. areaIndex)
	local rsModel = folder and folder:FindFirstChild("AuraModel")
	if rsModel then return rsModel end

	if MapIgnore then
		local ignoreModel = MapIgnore:FindFirstChild("Area" .. areaIndex .. "Aura")
		if ignoreModel then return ignoreModel end
	end

	warn("[AreaTransition] No AuraModel for area " .. areaIndex
		.. " — checked AreaAssets/Area" .. areaIndex .. "/AuraModel"
		.. " and Map/Ignore/Area" .. areaIndex .. "Aura")
	return nil
end

---------------------------------------------------------------
-- AURA HOLDER SWAP
---------------------------------------------------------------
local function SwapAuraHolder(areaIndex, instant)
	local template = GetAuraTemplate(areaIndex)
	if not template then
		warn("[AreaTransition] Skipping swap — no template for area " .. areaIndex)
		return
	end

	local yOffset   = AreaRegistry.GetYOffset(areaIndex)
	local yRotation = AreaRegistry.GetYRotation(areaIndex)

	--print("[AreaTransition] Swapping aura → Area" .. areaIndex
	--	.. " (yOffset=" .. yOffset .. ", yRotation=" .. yRotation .. "°)"
	--	.. (instant and " [instant]" or " [tween]"))

	if instant then
		for _, child in ipairs(AuraHolder:GetChildren()) do
			if child ~= PositionPart then child:Destroy() end
		end
		currentAuraModel = nil

		local newModel = template:Clone()
		newModel.Parent = AuraHolder
		PlaceAtPosition(newModel, yOffset, yRotation)
		currentAuraModel = newModel

	else
		if activeSwap and (tick() - swapStartedAt) < SWAP_TIMEOUT then return end
		activeSwap    = true
		swapStartedAt = tick()

		task.spawn(function()
			if currentAuraModel and currentAuraModel.Parent then
				local outTweens = TweenTransparency(currentAuraModel, 1, FADE_DURATION)
				if #outTweens > 0 then
					outTweens[1].Completed:Wait()
				else
					task.wait(FADE_DURATION)
				end
				if currentAuraModel and currentAuraModel.Parent then
					currentAuraModel:Destroy()
				end
				currentAuraModel = nil
			else
				task.wait(FADE_DURATION)
			end

			local newModel = template:Clone()
			newModel.Parent = AuraHolder
			PlaceAtPosition(newModel, yOffset, yRotation)
			SetTransparency(newModel, 1)
			currentAuraModel = newModel
			TweenTransparency(newModel, 0, FADE_DURATION)

			task.wait(FADE_DURATION)
			activeSwap = false
		end)
	end
end

---------------------------------------------------------------
-- HABITAT MODEL LOOKUP
---------------------------------------------------------------
local function GetHabitatTemplate(areaIndex)
	local folder  = AreaAssets:FindFirstChild("Area" .. areaIndex)
	local rsModel = folder and folder:FindFirstChild("HabitatModel")
	if rsModel then return rsModel end

	if MapIgnore then
		local ignoreModel = MapIgnore:FindFirstChild("Area" .. areaIndex .. "Habitat")
		if ignoreModel then return ignoreModel end
	end

	warn("[AreaTransition] No HabitatModel for area " .. areaIndex
		.. " — checked AreaAssets/Area" .. areaIndex .. "/HabitatModel")
	return nil
end

---------------------------------------------------------------
-- HABITAT SWAP
---------------------------------------------------------------
local currentHabitatModel = nil

local function SwapHabitat(areaIndex, instant)
	local template = GetHabitatTemplate(areaIndex)
	if not template then
		warn("[AreaTransition] Skipping habitat swap — no template for area " .. areaIndex)
		return
	end

	-- Optional: If you want to add yOffset/yRotation to AreaRegistry for habitats later!
	local yOffset = 0 
	local yRotation = 0

	if instant then
		for _, child in ipairs(HabitatHolder:GetChildren()) do
			if child ~= HabitatPositionPart then child:Destroy() end
		end
		currentHabitatModel = nil

		local newModel = template:Clone()
		newModel.Parent = HabitatHolder

		-- Positions it at the HabitatPositionPart
		local targetCF = CFrame.new(HabitatPositionPart.Position + Vector3.new(0, yOffset, 0)) * CFrame.Angles(0, math.rad(yRotation), 0)
		newModel:PivotTo(targetCF)

		currentHabitatModel = newModel
	else
		-- Async Tweening Swap
		task.spawn(function()
			if currentHabitatModel and currentHabitatModel.Parent then
				local outTweens = TweenTransparency(currentHabitatModel, 1, FADE_DURATION)
				if #outTweens > 0 then
					outTweens[1].Completed:Wait()
				else
					task.wait(FADE_DURATION)
				end
				if currentHabitatModel and currentHabitatModel.Parent then
					currentHabitatModel:Destroy()
				end
				currentHabitatModel = nil
			else
				task.wait(FADE_DURATION)
			end

			local newModel = template:Clone()
			newModel.Parent = HabitatHolder

			local targetCF = CFrame.new(HabitatPositionPart.Position + Vector3.new(0, yOffset, 0)) * CFrame.Angles(0, math.rad(yRotation), 0)
			newModel:PivotTo(targetCF)

			SetTransparency(newModel, 1)
			currentHabitatModel = newModel
			TweenTransparency(newModel, 0, FADE_DURATION)
		end)
	end
end
---------------------------------------------------------------
-- MAP COLORS
---------------------------------------------------------------
local function ApplyMapColors(areaData, instant)
	local info = TweenInfo.new(TWEEN_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	for _, part in ipairs(Map:GetChildren()) do
		if part:IsA("BasePart") then
			local key   = MAP_PART_COLORS[part.Name]
			local color = key and areaData[key]
			if color then
				if instant then pcall(function() part.Color = color end)
				else SafeTween(part, info, { Color = color }) end
			end
		end
	end
end

local function ApplyLighting(areaIndex, instant)
	local preset = AreaRegistry.GetLighting(areaIndex)

	-- 1. Tween standard Lighting properties
	local props = {}
	if preset.ClockTime then props.ClockTime = preset.ClockTime end
	if preset.Brightness then props.Brightness = preset.Brightness end
	if preset.FogEnd then props.FogEnd = preset.FogEnd end
	if preset.FogStart then props.FogStart = preset.FogStart end
	if preset.Ambient then props.Ambient = preset.Ambient end
	if preset.FogColor then props.FogColor = preset.FogColor end 

	if instant then
		for prop, val in pairs(props) do pcall(function() Lighting[prop] = val end) end
	elseif next(props) then
		SafeTween(Lighting, TweenInfo.new(TWEEN_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), props)
	end

	-- ✨ 2. Tween Atmosphere properties (The Smog Maker!)
	-- ✨ 2. Tween Atmosphere properties
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		local atmoProps = {}
		if preset.Density then atmoProps.Density = preset.Density end
		if preset.Haze then atmoProps.Haze = preset.Haze end
		if preset.AtmosphereColor then atmoProps.Color = preset.AtmosphereColor end

		if instant then
			for prop, val in pairs(atmoProps) do pcall(function() atmosphere[prop] = val end) end
		elseif next(atmoProps) then
			SafeTween(atmosphere, TweenInfo.new(TWEEN_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), atmoProps)
		end
	end

	-- ✨ 3. Tween SunRays properties (NEW!)
	local sunRays = Lighting:FindFirstChildOfClass("SunRaysEffect")
	if sunRays then
		local rayProps = {}

		-- Use the preset intensity, or default back to 0.25 if the preset forgot to mention it
		if preset.SunRaysIntensity ~= nil then 
			rayProps.Intensity = preset.SunRaysIntensity 
		else
			rayProps.Intensity = 0.25
		end

		if instant then
			for prop, val in pairs(rayProps) do pcall(function() sunRays[prop] = val end) end
		elseif next(rayProps) then
			SafeTween(sunRays, TweenInfo.new(TWEEN_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), rayProps)
		end
	end
end

---------------------------------------------------------------
-- SKYBOX (Updated to use Presets)
---------------------------------------------------------------
local function ApplySkybox(areaIndex, instant)
	local preset = AreaRegistry.GetLighting(areaIndex)
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if not sky then return end

	local function DoSwap()
		if preset.skyboxBk and preset.skyboxBk ~= "" then pcall(function() sky.SkyboxBk = preset.skyboxBk end) end
		if preset.skyboxDn and preset.skyboxDn ~= "" then pcall(function() sky.SkyboxDn = preset.skyboxDn end) end
		if preset.skyboxFt and preset.skyboxFt ~= "" then pcall(function() sky.SkyboxFt = preset.skyboxFt end) end
		if preset.skyboxLf and preset.skyboxLf ~= "" then pcall(function() sky.SkyboxLf = preset.skyboxLf end) end
		if preset.skyboxRt and preset.skyboxRt ~= "" then pcall(function() sky.SkyboxRt = preset.skyboxRt end) end
		if preset.skyboxUp and preset.skyboxUp ~= "" then pcall(function() sky.SkyboxUp = preset.skyboxUp end) end
	end

	if instant then DoSwap()
	else task.delay(TWEEN_DURATION * 0.5, DoSwap) end
end

---------------------------------------------------------------
-- AURAHOLDER RING TINT
---------------------------------------------------------------
local function ApplyAuraHolderTint(areaData, instant)
	if not areaData.auraHolderColor and not areaData.auraHolderGlow then return end
	local info = TweenInfo.new(TWEEN_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	for _, part in ipairs(AuraHolder:GetDescendants()) do
		if currentAuraModel and part:IsDescendantOf(currentAuraModel) then continue end
		if part == PositionPart then continue end
		if part:IsA("BasePart") and areaData.auraHolderColor then
			if instant then pcall(function() part.Color = areaData.auraHolderColor end)
			else SafeTween(part, info, { Color = areaData.auraHolderColor }) end
		end
		if part:IsA("PointLight") and areaData.auraHolderGlow then
			if instant then pcall(function() part.Color = areaData.auraHolderGlow end)
			else SafeTween(part, info, { Color = areaData.auraHolderGlow }) end
		end
	end
end

---------------------------------------------------------------
-- DECORATIONS
---------------------------------------------------------------
local function FadeDecorations(alpha, duration)
	local info   = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	local tweens = {}
	for _, obj in ipairs(DECORATION_CONTAINER:GetDescendants()) do
		if obj:IsA("BasePart") then
			local ok, t = pcall(function()
				return TweenService:Create(obj, info, { Transparency = alpha })
			end)
			if ok and t then t:Play(); table.insert(tweens, t) end
		end
	end
	if #tweens > 0 then tweens[1].Completed:Wait() end
end

---------------------------------------------------------------
-- DECORATIONS (With Memory Transparency Fix)
---------------------------------------------------------------
local function SwapDecorations(areaIndex)
	local folder = AreaAssets:FindFirstChild("Area" .. areaIndex)
	local newDec = folder and folder:FindFirstChild("Decorations")

	-- 1. Fade OUT old decorations
	for _, child in ipairs(DECORATION_CONTAINER:GetChildren()) do
		for _, desc in ipairs(child:GetDescendants()) do
			if desc:IsA("BasePart") or desc:IsA("Decal") or desc:IsA("Texture") then
				SafeTween(desc, TweenInfo.new(TWEEN_DURATION * 0.5), {Transparency = 1})
			end
		end
	end

	task.wait(TWEEN_DURATION * 0.5)

	-- Destroy the old ones once they are invisible
	for _, child in ipairs(DECORATION_CONTAINER:GetChildren()) do 
		child:Destroy() 
	end

	-- 2. Fade IN new decorations
	if newDec then
		for _, obj in ipairs(newDec:GetChildren()) do
			local clone = obj:Clone()

			-- ✨ THE FIX: Save the original transparency before making it invisible!
			for _, desc in ipairs(clone:GetDescendants()) do
				if desc:IsA("BasePart") or desc:IsA("Decal") or desc:IsA("Texture") then
					-- Memorize its true transparency as an Attribute
					desc:SetAttribute("OrigTrans", desc.Transparency)
					-- Now hide it for the fade-in
					desc.Transparency = 1
				end
			end

			clone.Parent = DECORATION_CONTAINER

			-- ✨ THE FIX: Tween back to the saved value instead of 0!
			for _, desc in ipairs(clone:GetDescendants()) do
				if desc:IsA("BasePart") or desc:IsA("Decal") or desc:IsA("Texture") then
					local targetTrans = desc:GetAttribute("OrigTrans") or 0
					SafeTween(desc, TweenInfo.new(TWEEN_DURATION * 0.5), {Transparency = targetTrans})
				end
			end
		end
	end
end

---------------------------------------------------------------
-- MASTER
---------------------------------------------------------------
local function ApplyAreaConfig(areaIndex, instant)
	local areaData = AreaRegistry.Get(areaIndex)
	SwapAuraHolder(areaIndex, instant)
	SwapHabitat(areaIndex, instant) 
	if areaData then
		ApplyMapColors(areaData, instant)
		ApplyLighting(areaIndex, instant) -- ✨ FIX: Passing areaIndex
		ApplySkybox(areaIndex, instant)   -- ✨ FIX: Passing areaIndex
		ApplyAuraHolderTint(areaData, instant)
	end

	if instant then
		local folder = AreaAssets:FindFirstChild("Area" .. areaIndex)
		local newDec = folder and folder:FindFirstChild("Decorations")
		for _, child in ipairs(DECORATION_CONTAINER:GetChildren()) do child:Destroy() end
		if newDec then
			for _, obj in ipairs(newDec:GetChildren()) do obj:Clone().Parent = DECORATION_CONTAINER end
		end
	else
		task.spawn(function() SwapDecorations(areaIndex) end)
	end
end

---------------------------------------------------------------
-- STARTUP
---------------------------------------------------------------
task.defer(function()
	--print("[AreaTransition] Position Part at:", PositionPart.Position)
	--print("[AreaTransition] Ready — yOffset + yRotation read from AreaRegistry per area")
end)

---------------------------------------------------------------
-- CONNECTIONS
---------------------------------------------------------------
local appliedOnJoin = false

AreaUpdated.OnClientEvent:Connect(function(info)
	if not appliedOnJoin then
		appliedOnJoin = true
		print("[AreaTransition] Join → area", info.currentArea or 1)
		ApplyAreaConfig(info.currentArea or 1, true)
	end
end)

AreaChanged.OnClientEvent:Connect(function(info)
	print("[AreaTransition] AreaChanged →", info.newArea, "(" .. (info.travelType or "?") .. ")")
	ApplyAreaConfig(info.newArea or 1, false)
end)
