-- PortalController
-- Location: StarterPlayer > StarterPlayerScripts > PortalController

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")

local AreaRegistry = require(ReplicatedStorage.Modules.AreaRegistry)
local SoundConfig  = require(ReplicatedStorage.Modules.SoundConfig)
local T            = require(ReplicatedStorage.Modules.UITheme).Get()
local C            = require(ReplicatedStorage.Modules.UIConfig)
local Formatter    = require(ReplicatedStorage.Modules.NumberFormatter) 
local UITheme = require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("UITheme"))
local T = UITheme.Get("Custom")
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
local previewRotationConn, previewModelInViewport = nil, nil

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

local function StartFlipbook(areaIdx)
	StopFlipbook()
	
	local flipbookData = AreaRegistry.GetFlipbook(areaIdx)
	if not flipbookData then return end
	
	currentFlipbook = flipbookData
	flipbookFrame = 1
	flipbookTime = 0
	
	local AreaIcon = AreaBrowser:FindFirstChild("AreaIcon")
	if not AreaIcon then return end
	
	-- Set up the image for flipbook
	AreaIcon.Image = flipbookData.image
	AreaIcon.ImageRectSize = Vector2.new(flipbookData.frameW, flipbookData.frameH)
	AreaIcon.ImageRectOffset = Vector2.new(0, 0)
	
	-- Animation loop
	flipbookConnection = RunService.RenderStepped:Connect(function(dt)
		flipbookTime += dt
		local frameTime = 1 / flipbookData.fps
		
		if flipbookTime >= frameTime then
			flipbookTime = flipbookTime % frameTime
			flipbookFrame = flipbookFrame + 1
			
			if flipbookFrame > flipbookData.frames then
				flipbookFrame = 1
			end
			
			-- Calculate frame position in sprite sheet
			local col = (flipbookFrame - 1) % flipbookData.columns
			local row = math.floor((flipbookFrame - 1) / flipbookData.columns)
			local offsetX = col * flipbookData.frameW
			local offsetY = row * flipbookData.frameH
			
			AreaIcon.ImageRectOffset = Vector2.new(offsetX, offsetY)
		end
	end)
end

local function LoadAreaPreview(viewport, worldModel, areaIndex)
	if previewRotationConn then previewRotationConn:Disconnect(); previewRotationConn = nil end
	previewModelInViewport = nil; worldModel:ClearAllChildren()
	local auraFolder = AreaAssets:FindFirstChild("Area" .. areaIndex)
	auraFolder = auraFolder and auraFolder:FindFirstChild("Auras")
	local auraModel = auraFolder and auraFolder:FindFirstChildWhichIsA("Model")
	local displayModel
	if auraModel then
		displayModel = auraModel:Clone(); displayModel.Parent = worldModel
	else
		local areaData = AreaRegistry.Get(areaIndex)
		local color = (areaData and areaData.auraPreviewColor) or Color3.fromRGB(200,200,200)
		local sphere = Instance.new("Part")
		sphere.Shape = Enum.PartType.Ball; sphere.Size = Vector3.new(3,3,3)
		sphere.Color = color; sphere.Material = Enum.Material.Neon
		sphere.Anchored = true; sphere.CastShadow = false; sphere.Position = Vector3.new(0,0,0)
		local glow = Instance.new("PointLight"); glow.Brightness=3; glow.Range=10; glow.Color=color; glow.Parent=sphere
		local model = Instance.new("Model"); model.Name="PreviewModel"; model.PrimaryPart=sphere
		sphere.Parent = model; model.Parent = worldModel; displayModel = model
	end
	local cf, size = displayModel:GetBoundingBox()
	local center, radius = cf.Position, math.max(size.X, size.Y, size.Z)
	local camera = Instance.new("Camera"); camera.FieldOfView = 45
	camera.CFrame = CFrame.new(center + Vector3.new(0, radius*0.2, radius*2.2), center)
	camera.Parent = worldModel; viewport.CurrentCamera = camera
	previewModelInViewport = displayModel
	local angle = 0
	previewRotationConn = RunService.RenderStepped:Connect(function(dt)
		if not previewModelInViewport or not previewModelInViewport.Parent then
			previewRotationConn:Disconnect(); previewRotationConn = nil; return
		end
		angle += dt * 40
		local p = previewModelInViewport:GetBoundingBox()
		previewModelInViewport:PivotTo(CFrame.new(p.Position) * CFrame.Angles(0, math.rad(angle), 0))
	end)
end

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
	local AreaIcon = AreaBrowser:FindFirstChild("AreaIcon")
	if not AreaIcon then return end
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
		-- ✨ Check for flipbook animation first
		local flipbookData = AreaRegistry.GetFlipbook(idx)
		if flipbookData then
			StartFlipbook(idx)
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
			-- ✨ Check for flipbook animation
			local flipbookData = AreaRegistry.GetFlipbook(idx)
			if flipbookData then
				StartFlipbook(idx)
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
			-- ✨ Check for flipbook animation (dimmed for discovered)
			local flipbookData = AreaRegistry.GetFlipbook(idx)
			if flipbookData then
				StartFlipbook(idx)
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
	if outerStroke then
		outerStroke.Color = Color3.fromRGB(255, 255, 255) 
	end
end

task.wait(2)
RefreshLook()
-- ══════════ DEVELOPER ECONOMY CHEAT SHEET ══════════

-- [ Hundreds ]
-- 5e1  = 50
-- 5e2  = 500

-- [ Thousands (k) ]
-- 5e3  = 5k
-- 5e4  = 50k
-- 5e5  = 500k

-- [ Millions (M) ]
-- 5e6  = 5M
-- 5e7  = 50M
-- 5e8  = 500M

-- [ Billions (B) ]
-- 5e9  = 5B
-- 5e10 = 50B
-- 5e11 = 500B

-- [ Trillions (T) ]
-- 5e12 = 5T
-- 5e13 = 50T
-- 5e14 = 500T

-- [ Quadrillions (Qa) ]
-- 5e15 = 5Qa
-- 5e16 = 50Qa
-- 5e17 = 500Qa

-- [ Quintillions (Qi) ]
-- 5e18 = 5Qi
-- 5e19 = 50Qi
-- 5e20 = 500Qi

-- [ Sextillions (Sx) ]
-- 5e21 = 5Sx
-- 5e22 = 50Sx
-- 5e23 = 500Sx

-- [ Septillions (Sp) ]
-- 5e24 = 5Sp
-- 5e25 = 50Sp
-- 5e26 = 500Sp

-- [ Octillions (Oc) ]
-- 5e27 = 5Oc
-- 5e28 = 50Oc
-- 5e29 = 500Oc

-- [ Nonillions (No) ]
-- 5e30 = 5No
-- 5e31 = 50No
-- 5e32 = 500No

-- [ Decillions (Dc) ]
-- 5e33 = 5Dc
-- 5e34 = 50Dc
-- 5e35 = 500Dc

-- ══════════ ROMAN NUMERAL RANKS ══════════

-- [ Rank I ]
-- 5e36 = 5 I
-- 5e37 = 50 I
-- 5e38 = 500 I

-- [ Rank II ]
-- 5e39 = 5 II
-- 5e40 = 50 II
-- 5e41 = 500 II

-- [ Rank III ]
-- 5e42 = 5 III
-- 5e43 = 50 III
-- 5e44 = 500 III

-- [ Rank IV ]
-- 5e45 = 5 IV
-- 5e46 = 50 IV
-- 5e47 = 500 IV

-- [ Rank V ]
-- 5e48 = 5 V
-- 5e49 = 50 V
-- 5e50 = 500 V

-- [ Rank VI ]
-- 5e51 = 5 VI
-- 5e52 = 50 VI
-- 5e53 = 500 VI

-- [ Rank VII ]
-- 5e54 = 5 VII
-- 5e55 = 50 VII
-- 5e56 = 500 VII

-- [ Rank VIII ]
-- 5e57 = 5 VIII
-- 5e58 = 50 VIII
-- 5e59 = 500 VIII

-- [ Rank IX ]
-- 5e60 = 5 IX
-- 5e61 = 50 IX
-- 5e62 = 500 IX

-- [ Rank X ]
-- 5e63 = 5 X
-- 5e64 = 50 X
-- 5e65 = 500 X

-- [ Rank XI ]
-- 5e66 = 5 XI
-- 5e67 = 50 XI
-- 5e68 = 500 XI

-- [ Rank XII ]
-- 5e69 = 5 XII
-- 5e70 = 50 XII
-- 5e71 = 500 XII

-- ═══════════════════════════════════════════════════
local AreaRegistry = {}

AreaRegistry.LightingPresets = {

	-- 🏭 PHASE 1: THE GRIME (Areas 1-3)
	["Area1_DeepScrapyard"] = {
		ClockTime = 12, Brightness = 0.3, SunRaysIntensity = 0,
		Ambient = Color3.fromRGB(70, 60, 50), FogColor = Color3.fromRGB(90, 80, 65),
		FogStart = 20, FogEnd = 60, Density = 0.7, Haze = 10, AtmosphereColor = Color3.fromRGB(90, 80, 65)
	},
	["Area2_RustyWastes"] = {
		ClockTime = 14, Brightness = 0.4, SunRaysIntensity = 0,
		Ambient = Color3.fromRGB(80, 65, 50), FogColor = Color3.fromRGB(100, 85, 60),
		FogStart = 20, FogEnd = 80, Density = 0.6, Haze = 8, AtmosphereColor = Color3.fromRGB(100, 85, 60)
	},
	["Area3_IndustrialOutskirts"] = {
		ClockTime = 16, Brightness = 0.5, SunRaysIntensity = 0,
		Ambient = Color3.fromRGB(85, 75, 65), FogColor = Color3.fromRGB(110, 100, 90),
		FogStart = 30, FogEnd = 100, Density = 0.55, Haze = 6, AtmosphereColor = Color3.fromRGB(110, 100, 90)
	},

	-- ☣️ PHASE 2: TOXIC ZONES (Areas 4-5)
	["Area4_ChemicalSpill"] = {
		ClockTime = 17, Brightness = 0.4, SunRaysIntensity = 0,
		Ambient = Color3.fromRGB(60, 75, 50), FogColor = Color3.fromRGB(75, 90, 55),
		FogStart = 50, FogEnd = 110, Density = 0.5, Haze = 7, AtmosphereColor = Color3.fromRGB(75, 90, 55)
	},
	["Area5_BioHazard"] = {
		ClockTime = 17.5, Brightness = 0.3, SunRaysIntensity = 0,
		Ambient = Color3.fromRGB(40, 60, 40), FogColor = Color3.fromRGB(45, 80, 45),
		FogStart = 60, FogEnd = 120, Density = 0.4, Haze = 5, AtmosphereColor = Color3.fromRGB(45, 80, 45)
	},

	-- 🌆 PHASE 3: TWILIGHT SLUMS (Areas 6-8)
	["Area6_SunsetStrip"] = {
		ClockTime = 17.8, Brightness = 0.6, SunRaysIntensity = 0.1, -- Sun peeks through!
		Ambient = Color3.fromRGB(70, 40, 40), FogColor = Color3.fromRGB(90, 40, 30),
		FogStart = 20, FogEnd = 150, Density = 0.5, Haze = 4, AtmosphereColor = Color3.fromRGB(120, 50, 40)
	},
	["Area7_TwilightSector"] = {
		ClockTime = 18.2, Brightness = 0.4, SunRaysIntensity = 0,
		Ambient = Color3.fromRGB(40, 30, 60), FogColor = Color3.fromRGB(35, 25, 55),
		FogStart = 20, FogEnd = 180, Density = 0.55, Haze = 4, AtmosphereColor = Color3.fromRGB(35, 25, 55)
	},
	["Area8_NeonSlums"] = {
		ClockTime = 0, Brightness = 0.5, SunRaysIntensity = 0,
		Ambient = Color3.fromRGB(30, 20, 50), FogColor = Color3.fromRGB(20, 10, 40),
		FogStart = 25, FogEnd = 200, Density = 0.5, Haze = 3, AtmosphereColor = Color3.fromRGB(40, 20, 80)
	},

	-- 🌃 PHASE 4: CYBER CITY (Areas 9-10)
	["Area9_LowerCyber"] = {
		ClockTime = 0, Brightness = 0.7, SunRaysIntensity = 0,
		Ambient = Color3.fromRGB(25, 25, 55), FogColor = Color3.fromRGB(15, 15, 45),
		FogStart = 30, FogEnd = 250, Density = 0.4, Haze = 2, AtmosphereColor = Color3.fromRGB(20, 20, 60)
	},
	["Area10_CyberCore"] = {
		ClockTime = 0, Brightness = 1, SunRaysIntensity = 0,
		Ambient = Color3.fromRGB(20, 30, 60), FogColor = Color3.fromRGB(10, 20, 50),
		FogStart = 50, FogEnd = 400, Density = 0.25, Haze = 1, AtmosphereColor = Color3.fromRGB(15, 25, 65)
	},

	-- 🌐 PHASE 5: CORPORATE STERILITY (Areas 11-13)
	["Area11_GlassFacility"] = {
		ClockTime = 12, Brightness = 2.0, SunRaysIntensity = 0.4, -- Blinding sudden daylight
		Ambient = Color3.fromRGB(130, 130, 140), FogColor = Color3.fromRGB(200, 220, 240),
		FogStart = 100, FogEnd = 1500, Density = 0.15, Haze = 0, AtmosphereColor = Color3.fromRGB(200, 220, 240)
	},
	["Area12_CrystalLab"] = {
		ClockTime = 14, Brightness = 2.5, SunRaysIntensity = 0.5,
		Ambient = Color3.fromRGB(150, 150, 150), FogColor = Color3.fromRGB(220, 240, 255),
		FogStart = 150, FogEnd = 2500, Density = 0.1, Haze = 0, AtmosphereColor = Color3.fromRGB(220, 240, 255)
	},
	["Area13_QuantumGrid"] = {
		ClockTime = 14, Brightness = 2.2, SunRaysIntensity = 0.3,
		Ambient = Color3.fromRGB(100, 180, 200), FogColor = Color3.fromRGB(150, 255, 255),
		FogStart = 200, FogEnd = 3000, Density = 0.05, Haze = 0, AtmosphereColor = Color3.fromRGB(150, 255, 255)
	},

	-- 🌌 PHASE 6: REALITY BREAKING (Areas 14-16)
	["Area14_PlasmaCore"] = {
		ClockTime = 17.5, Brightness = 1.8, SunRaysIntensity = 0.3,
		Ambient = Color3.fromRGB(150, 80, 150), FogColor = Color3.fromRGB(200, 100, 200),
		FogStart = 100, FogEnd = 2000, Density = 0.2, Haze = 2, AtmosphereColor = Color3.fromRGB(200, 100, 200)
	},
	["Area15_CosmicRift"] = {
		ClockTime = 6, Brightness = 1.5, SunRaysIntensity = 0.2,
		Ambient = Color3.fromRGB(100, 30, 150), FogColor = Color3.fromRGB(70, 0, 100),
		FogStart = 50, FogEnd = 1000, Density = 0.3, Haze = 4, AtmosphereColor = Color3.fromRGB(150, 0, 255)
	},
	["Area16_DarkMatter"] = {
		ClockTime = 0, Brightness = 0.8, SunRaysIntensity = 0,
		Ambient = Color3.fromRGB(80, 10, 20), FogColor = Color3.fromRGB(40, 0, 5),
		FogStart = 30, FogEnd = 600, Density = 0.5, Haze = 6, AtmosphereColor = Color3.fromRGB(120, 0, 10)
	},

	-- ⬛ PHASE 7: THE VOID (Areas 17-20)
	["Area17_EventHorizon"] = {
		ClockTime = 0, Brightness = 0.4, SunRaysIntensity = 0,
		Ambient = Color3.fromRGB(30, 10, 40), FogColor = Color3.fromRGB(15, 5, 20),
		FogStart = 50, FogEnd = 800, Density = 0.3, Haze = 3, AtmosphereColor = Color3.fromRGB(20, 5, 30)
	},
	["Area18_DeepSpace"] = {
		ClockTime = 0, Brightness = 0.2, SunRaysIntensity = 0,
		Ambient = Color3.fromRGB(15, 15, 25), FogColor = Color3.fromRGB(5, 5, 15),
		FogStart = 100, FogEnd = 1500, Density = 0.15, Haze = 1, AtmosphereColor = Color3.fromRGB(5, 5, 15)
	},
	["Area19_TheAbyss"] = {
		ClockTime = 0, Brightness = 0.05, SunRaysIntensity = 0,
		Ambient = Color3.fromRGB(5, 5, 5), FogColor = Color3.fromRGB(2, 2, 2),
		FogStart = 200, FogEnd = 3000, Density = 0.05, Haze = 0, AtmosphereColor = Color3.fromRGB(2, 2, 2)
	},
	["Area20_UniversalVoid"] = {
		ClockTime = 0, Brightness = 0, SunRaysIntensity = 0,
		Ambient = Color3.fromRGB(0, 0, 0), FogColor = Color3.fromRGB(0, 0, 0),
		FogStart = 500, FogEnd = 5000, Density = 0, Haze = 0, AtmosphereColor = Color3.fromRGB(0, 0, 0)
	}
}

-- ══════════ FLIPBOOK ANIMATION CONFIG ══════════
-- To add an animated icon, include these fields in your area data:
--   flipbookImage   = "rbxassetid://12345678"  -- The sprite sheet image
--   flipbookFrames  = 8                        -- Number of frames in the sprite sheet
--   flipbookFPS     = 12                       -- Frames per second (animation speed)
--   flipbookFrameW  = 128                      -- Width of each frame in pixels
--   flipbookFrameH  = 128                      -- Height of each frame in pixels
--   flipbookColumns = 4                        -- Number of columns in the sprite sheet (optional, defaults to frames)
--
-- Example sprite sheet layout (4 columns x 2 rows = 8 frames):
--   [1][2][3][4]
--   [5][6][7][8]
--
-- The frames play left-to-right, top-to-bottom.

AreaRegistry.Areas = {
	[1] = { 
		name             = "Starter Area",     
		threshold        = 0,   
		valueMultiplier  = 1.0, 
		yOffset          = -2.7, 
		yRotation        = 180, 
		auraPreviewColor = Color3.fromRGB(200, 200, 200), 
		grassColor       = Color3.fromRGB(92, 197, 53), 
		pathColor        = Color3.fromRGB(163, 130, 88), 
		ambientColor     = Color3.fromRGB(90, 90, 100), 
		fogColor         = Color3.fromRGB(180, 200, 220), 
		auraHolderColor  = Color3.fromRGB(255, 255, 255), 
		auraHolderGlow   = Color3.fromRGB(255, 255, 255), 
		lightingPreset   = "Area1_DeepScrapyard", 
		flipbookImage    = "rbxassetid://1234567890", 
		flipbookFrames   = 6, 
		flipbookFPS      = 10, 
		flipbookFrameW   = 128, 
		flipbookFrameH   = 128, 
		flipbookColumns  = 3,
	},
	[2] = { 
		name             = "Uncommon Area",    
		threshold        = 5e4, 
		valueMultiplier  = 1.5, 
		yOffset          = -4.5, 
		yRotation        = 180, 
		auraPreviewColor = Color3.fromRGB(100, 200, 100), 
		grassColor       = Color3.fromRGB(104, 160, 98), 
		pathColor        = Color3.fromRGB(132, 140, 81), 
		ambientColor     = Color3.fromRGB(80, 100, 80), 
		fogColor         = Color3.fromRGB(160, 200, 160), 
		auraHolderColor  = Color3.fromRGB(187, 255, 183), 
		auraHolderGlow   = Color3.fromRGB(100, 255, 100), 
		lightingPreset   = "Area2_RustyWastes", 
		flipbookImage    = "rbxassetid://1234567891", 
		flipbookFrames   = 8, 
		flipbookFPS      = 12, 
		flipbookFrameW   = 128, 
		flipbookFrameH   = 128, 
		flipbookColumns  = 4,
	},
	[3] = { 
		name             = "Rare Area",        
		threshold        = 5e5, 
		valueMultiplier  = 4.0, 
		yOffset          = -2.8, 
		yRotation        = 180, 
		auraPreviewColor = Color3.fromRGB(80, 120, 220), 
		grassColor       = Color3.fromRGB(2, 226, 170), 
		pathColor        = Color3.fromRGB(22, 81, 168), 
		ambientColor     = Color3.fromRGB(70, 80, 130), 
		fogColor         = Color3.fromRGB(92, 169, 220), 
		auraHolderColor  = Color3.fromRGB(75, 87, 255), 
		auraHolderGlow   = Color3.fromRGB(56, 86, 255), 
		lightingPreset   = "Area3_IndustrialOutskirts", 
		flipbookImage    = "rbxassetid://1234567892", 
		flipbookFrames   = 12, 
		flipbookFPS      = 15, 
		flipbookFrameW   = 128, 
		flipbookFrameH   = 128, 
		flipbookColumns  = 4,
	},
	[4] = { 
		name             = "Epic Area",        
		threshold        = 5e6, 
		valueMultiplier  = 8.0, 
		yOffset          = -2.8, 
		yRotation        = 180, 
		auraPreviewColor = Color3.fromRGB(180, 80, 220), 
		grassColor       = Color3.fromRGB(154, 102, 175), 
		pathColor        = Color3.fromRGB(71, 34, 90), 
		ambientColor     = Color3.fromRGB(90, 50, 120), 
		fogColor         = Color3.fromRGB(160, 120, 200), 
		auraHolderColor  = Color3.fromRGB(220, 160, 255), 
		auraHolderGlow   = Color3.fromRGB(180, 60, 255), 
		lightingPreset   = "Area4_ChemicalSpill", 
		flipbookImage    = "rbxassetid://1234567893", 
		flipbookFrames   = 16, 
		flipbookFPS      = 20, 
		flipbookFrameW   = 128, 
		flipbookFrameH   = 128, 
		flipbookColumns  = 4,
	},
	[5] = { 
		name             = "Legendary Area",   
		threshold        = 5e7, 
		valueMultiplier  = 20.0,
		yOffset          = -3.0,   
		yRotation        = 0,   
		auraPreviewColor = Color3.fromRGB(255, 200, 50), 
		grassColor       = Color3.fromRGB(160, 120, 20), 
		pathColor        = Color3.fromRGB(180, 150, 60), 
		ambientColor     = Color3.fromRGB(140, 120, 60), 
		fogColor         = Color3.fromRGB(220, 200, 150), 
		auraHolderColor  = Color3.fromRGB(255, 230, 120), 
		auraHolderGlow   = Color3.fromRGB(255, 180, 0), 
		lightingPreset   = "Area5_BioHazard", 
		flipbookImage    = "rbxassetid://1234567894", 
		flipbookFrames   = 20, 
		flipbookFPS      = 24, 
		flipbookFrameW   = 128, 
		flipbookFrameH   = 128, 
		flipbookColumns  = 5,
	},
	-- ✨ THE COSMIC PROGRESSION BEGINS (Egg Inc Style leaps)
	[6] = {
		name            = "Quantum Area",
		threshold       = 5e9, -- 5 Billion
		valueMultiplier = 75.0,
		yOffset         = -4.5,
		yRotation       = 180,
		auraPreviewColor = Color3.fromRGB(0, 255, 255),
		grassColor        = Color3.fromRGB(0, 150, 150),
		pathColor         = Color3.fromRGB(0, 100, 100),
		ambientColor      = Color3.fromRGB(50, 200, 200),
		fogColor          = Color3.fromRGB(150, 255, 255),
		auraHolderColor   = Color3.fromRGB(0, 255, 255),
		auraHolderGlow    = Color3.fromRGB(255, 255, 255),
	},
	[7] = {
		name            = "Cosmic Area",
		threshold       = 5e12, -- 5 Trillion
		valueMultiplier = 350.0,
		yOffset         = -4.5,
		yRotation       = 180,
		auraPreviewColor = Color3.fromRGB(138, 43, 226),
		grassColor        = Color3.fromRGB(75, 0, 130),
		pathColor         = Color3.fromRGB(48, 25, 52),
		ambientColor      = Color3.fromRGB(147, 112, 219),
		fogColor          = Color3.fromRGB(216, 191, 216),
		auraHolderColor   = Color3.fromRGB(138, 43, 226),
		auraHolderGlow    = Color3.fromRGB(255, 0, 255),
	},
	[8] = {
		name            = "Tachyon Area",
		threshold       = 5e15, -- 5 Quadrillion
		valueMultiplier = 2500.0,
		yOffset         = -4.5,
		yRotation       = 180,
		auraPreviewColor = Color3.fromRGB(255, 255, 0),
		grassColor        = Color3.fromRGB(200, 200, 0),
		pathColor         = Color3.fromRGB(255, 140, 0),
		ambientColor      = Color3.fromRGB(255, 215, 0),
		fogColor          = Color3.fromRGB(255, 250, 205),
		auraHolderColor   = Color3.fromRGB(255, 255, 0),
		auraHolderGlow    = Color3.fromRGB(255, 165, 0),
	},
	[9] = {
		name            = "Dark Matter Area",
		threshold       = 5e19, -- 50 Quintillion
		valueMultiplier = 50000.0,
		yOffset         = -4.5,
		yRotation       = 180,
		auraPreviewColor = Color3.fromRGB(20, 0, 0),
		grassColor        = Color3.fromRGB(15, 15, 15),
		pathColor         = Color3.fromRGB(30, 0, 0),
		ambientColor      = Color3.fromRGB(50, 0, 0),
		fogColor          = Color3.fromRGB(10, 0, 0),
		auraHolderColor   = Color3.fromRGB(0, 0, 0),
		auraHolderGlow    = Color3.fromRGB(255, 0, 0),
	},
	[10] = {
		name            = "Universal Area",
		threshold       = 5e25, -- 50 Septillion
		valueMultiplier = 1000000.0,
		yOffset         = -4.5,
		yRotation       = 180,
		auraPreviewColor = Color3.fromRGB(255, 255, 255),
		grassColor        = Color3.fromRGB(240, 248, 255),
		pathColor         = Color3.fromRGB(211, 211, 211),
		ambientColor      = Color3.fromRGB(255, 250, 250),
		fogColor          = Color3.fromRGB(255, 255, 255),
		auraHolderColor   = Color3.fromRGB(255, 255, 255),
		auraHolderGlow    = Color3.fromRGB(255, 215, 0),
	},
}

---------------------------------------------------------------
-- BASIC GETTERS
---------------------------------------------------------------
function AreaRegistry.Get(idx)            return AreaRegistry.Areas[idx] end
function AreaRegistry.GetName(idx)        return (AreaRegistry.Areas[idx] and AreaRegistry.Areas[idx].name) or ("Area "..idx) end
function AreaRegistry.GetThreshold(idx)   return AreaRegistry.Areas[idx] and AreaRegistry.Areas[idx].threshold or nil end
function AreaRegistry.GetMultiplier(idx)  return (AreaRegistry.Areas[idx] and AreaRegistry.Areas[idx].valueMultiplier) or 1.0 end
function AreaRegistry.GetYOffset(idx)     return (AreaRegistry.Areas[idx] and AreaRegistry.Areas[idx].yOffset)    or 0 end
function AreaRegistry.GetYRotation(idx)   return (AreaRegistry.Areas[idx] and AreaRegistry.Areas[idx].yRotation)  or 0 end

---------------------------------------------------------------
-- FLIPBOOK GETTER
-- Returns flipbook config if the area has one, nil otherwise
---------------------------------------------------------------
function AreaRegistry.GetFlipbook(idx)
	local area = AreaRegistry.Areas[idx]
	if not area or not area.flipbookImage then return nil end
	
	return {
		image = area.flipbookImage,
		frames = area.flipbookFrames or 1,
		fps = area.flipbookFPS or 12,
		frameW = area.flipbookFrameW or 128,
		frameH = area.flipbookFrameH or 128,
		columns = area.flipbookColumns or area.flipbookFrames or 1,
	}
end

---------------------------------------------------------------
-- LIGHTING GETTER
---------------------------------------------------------------
function AreaRegistry.GetLighting(idx)
	local area = AreaRegistry.Areas[idx]
	if not area or not area.lightingPreset then 
		return AreaRegistry.LightingPresets["ClearDay"] 
	end

	-- Return the preset data
	return AreaRegistry.LightingPresets[area.lightingPreset] or AreaRegistry.LightingPresets["ClearDay"]
end

function AreaRegistry.GetMaxArea()
	local max = 0
	for k in pairs(AreaRegistry.Areas) do if k > max then max = k end end
	return max
end

---------------------------------------------------------------
-- AREA SKIPPING — find the highest area the player qualifies for
---------------------------------------------------------------
-- Returns the best (highest) area index the player can advance to,
-- or nil if they can't advance at all.
-- Scans every area above currentArea; if farmEvaluation meets
-- the threshold, that area is a candidate.  Returns the highest one.
--
-- Example: player is in Area 1 with 6e6 farmEval.
--   Area 2 threshold = 5e5  → qualifies
--   Area 3 threshold = 5e6  → qualifies
--   Area 4 threshold = 5e7  → does NOT qualify
--   Returns 3 (skips Area 2, goes straight to Area 3).
---------------------------------------------------------------
function AreaRegistry.GetBestNextArea(currentArea, farmEvaluation)
	local maxArea  = AreaRegistry.GetMaxArea()
	local bestArea = nil

	for i = currentArea + 1, maxArea do
		local area = AreaRegistry.Areas[i]
		if area and farmEvaluation >= (area.threshold or 0) then
			bestArea = i
		end
	end

	return bestArea
end

---------------------------------------------------------------
-- LEGACY — kept for any old code that still calls CanAdvance.
-- Now uses GetBestNextArea internally.
---------------------------------------------------------------
function AreaRegistry.CanAdvance(currentArea, farmEvaluation)
	local best = AreaRegistry.GetBestNextArea(currentArea, farmEvaluation)
	if best then
		return true, best
	end
	return false, nil
end

return AreaRegistry


local AdminConfig = require(game:GetService("ReplicatedStorage").Modules.AdminConfig)

local TierConfig = {}

TierConfig.Tiers = {
	{ name = "Common",    chance = 0.75,   multiplier = 1,   color = Color3.fromRGB(220, 220, 220), glow = false },
	{ name = "Uncommon",  chance = 0.17,   multiplier = 1.5, color = Color3.fromRGB(80, 200, 80),   glow = true  },
	{ name = "Rare",      chance = 0.06,   multiplier = 3,   color = Color3.fromRGB(60, 120, 255),  glow = true  },
	{ name = "Epic",      chance = 0.018,  multiplier = 8,   color = Color3.fromRGB(180, 60, 255),  glow = true  },
	{ name = "Legendary", chance = 0.002,  multiplier = 25,  color = Color3.fromRGB(255, 200, 0),   glow = true  },
}

if AdminConfig.TierOverride then
	TierConfig.Tiers = AdminConfig.TierOverride
end

function TierConfig.Roll()
	local r = math.random()
	local cumulative = 0
	for _, tier in ipairs(TierConfig.Tiers) do
		cumulative += tier.chance
		if r <= cumulative then return tier end
	end
	return TierConfig.Tiers[1]
end

return TierConfig

-- ClickHandler
-- Location: StarterPlayer > StarterPlayerScripts > ClickHandler
-- CHANGES: Added local FormatNumber (K/M/B/T/Q)
--          ShowCubeValue: label.Text now uses FormatNumber instead of tostring
--          Everything else identical to your uploaded script.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")
local AdminConfig = require(ReplicatedStorage.Modules.AdminConfig)
local UITheme = require(game:GetService("ReplicatedStorage").Modules.UITheme)

local ProduceAura = ReplicatedStorage.RemoteEvents:WaitForChild("ProduceAura")
local AuraSpawned = ReplicatedStorage.RemoteEvents:WaitForChild("AuraSpawned")
local UpdateHatchery = ReplicatedStorage.RemoteEvents:WaitForChild("UpdateHatchery")
local ForceStopHold = ReplicatedStorage.RemoteEvents:WaitForChild("ForceStopHold")
local HabitatFull = ReplicatedStorage.RemoteEvents:WaitForChild("HabitatFull")
local CubeMutated = ReplicatedStorage.RemoteEvents:WaitForChild("CubeMutated")
local UpdateMultiplier = ReplicatedStorage:WaitForChild("UpdateMultiplier")
local HabitatFullEvent = ReplicatedStorage:WaitForChild("HabitatFullEvent")
local CubeMutatedBatch = ReplicatedStorage.RemoteEvents:WaitForChild("CubeMutatedBatch")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local holding = false
local fireRate = AdminConfig.FireRate
local holdStart = nil
local hatcheryEmpty = false
local habitatFull = false

local ClickButton = playerGui:WaitForChild("MainHUD"):WaitForChild("ClickButton")
local HatcheryBar = playerGui:WaitForChild("MainHUD"):WaitForChild("HatcheryBar")
local HatcheryFill = HatcheryBar:WaitForChild("Fill")
local HatcheryLabel = HatcheryBar:WaitForChild("Label")
local clickScale = ClickButton:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", ClickButton)
local clickStroke = ClickButton:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke", ClickButton)
clickStroke.Color = Color3.fromRGB(255, 215, 0) -- Pure Gold
clickStroke.Thickness = 0
local basePos = ClickButton.Position
local tiltSide = 1

-- ✨ MILESTONE SYSTEM SETUP
local Camera = workspace.CurrentCamera
local defaultFOV = 70 -- Standard Roblox camera FOV
local lastMilestone = 1

local MilestoneData = AdminConfig.MilestoneData

local playerMultSpeed = 1.0 -- Increased by "Synaptic Overdrive" upgrade
local playerMaxTier = 5     -- Increased by "Epic Core Resonance" tier unlock upgrade
local lastTierIndex = 1
-- ADDED: FormatNumber so cube value popups show K/M instead of raw numbers
local function FormatNumber(n)
	n = math.floor(n or 0)
	if n >= 1e15 then return string.format("%.3f Q", n / 1e15)
	elseif n >= 1e12 then return string.format("%.3f T", n / 1e12)
	elseif n >= 1e9  then return string.format("%.3f B", n / 1e9)
	elseif n >= 1e6  then return string.format("%.3f M", n / 1e6)
	elseif n >= 1e3  then return string.format("%.1fK", n / 1e3)
	end
	local s = tostring(n)
	local result = ""
	local count = 0
	for i = #s, 1, -1 do
		if count > 0 and count % 3 == 0 then result = "," .. result end
		result = s:sub(i, i) .. result
		count += 1
	end
	return result
end	

---------------------------------------------------------------
-- AURA MODEL FOLDERS
---------------------------------------------------------------
local AurasFolder = ReplicatedStorage:FindFirstChild("Auras")
local VFXFolder = ReplicatedStorage:FindFirstChild("VFX")

local cubeDataMap = {}

local TierScale = {
	Common    = 1.0,
	Uncommon  = 1.15,
	Rare      = 1.3,
	Epic      = 1.5,
	Legendary = 1.75,
}

local function CloneAuraModel(tierName)
	if not AurasFolder then return nil end
	local template = AurasFolder:FindFirstChild(tierName)
	if not template then return nil end
	local clone = template:Clone()
	if not clone.PrimaryPart then
		warn("[Aura] Model '" .. tierName .. "' has no PrimaryPart set! Set PrimaryPart to the main BasePart (e.g. " .. tierName .. "VFX) for reliable positioning.")
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

local function SpawnAuraInstance(tierName, color, glow, position)
	local auraModel = CloneAuraModel(tierName)
	if auraModel then
		auraModel:PivotTo(CFrame.new(position))
		auraModel.Parent = workspace
		if auraModel.PrimaryPart then
			auraModel.PrimaryPart.Anchored = false
			auraModel.PrimaryPart.CanCollide = true
		end
		return auraModel, true
	else
		local part = CreatePlaceholderPart(color, glow)
		part.Position = position
		part.Parent = workspace
		return part, false
	end
end

local function GetRootPart(instance)
	if instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart")
	end
	return instance
end

local function ScaleAura(instance, tierName, animated, fromTierName)
	local targetScale = TierScale[tierName] or 1.0
	local fromScale = fromTierName and (TierScale[fromTierName] or 1.0) or nil

	if instance:IsA("Model") then
		if fromScale and animated then
			pcall(function() instance:ScaleTo(fromScale) end)
		end
		if animated then
			local root = instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart")
			if root and root:IsA("BasePart") then
				local currentSize = root.Size
				local ratio = targetScale / (fromScale or targetScale)
				local targetSize = currentSize * ratio
				TweenService:Create(root, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
					Size = targetSize
				}):Play()
			end
		else
			pcall(function() instance:ScaleTo(targetScale) end)
		end
	elseif instance:IsA("BasePart") then
		local baseSize = 1.5
		local targetSize = Vector3.new(1, 1, 1) * (baseSize * targetScale)
		if animated then
			if fromScale then
				instance.Size = Vector3.new(1, 1, 1) * (baseSize * fromScale)
			end
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

	if vfx:IsA("Model") then
		vfx:PivotTo(CFrame.new(position))
	elseif vfx:IsA("BasePart") then
		vfx.Position = position
	end

	for _, obj in ipairs(vfx:GetDescendants()) do
		if obj:IsA("BasePart") then
			obj.Anchored = true
			obj.Transparency = 1
			obj.CanCollide = false
			obj.CastShadow = false
		end
	end
	if vfx:IsA("BasePart") then
		vfx.Anchored = true
		vfx.Transparency = 1
		vfx.CanCollide = false
		vfx.CastShadow = false
	end

	vfx.Parent = workspace

	for _, emitter in ipairs(vfx:GetDescendants()) do
		if emitter:IsA("ParticleEmitter") then
			emitter.Enabled = true
		end
	end
	for _, emitter in ipairs(vfx:GetDescendants()) do
		if emitter:IsA("ParticleEmitter") then
			emitter:Emit(emitter:GetAttribute("BurstCount") or 15)
		end
	end

	task.delay((duration or 1.0) * 0.5, function()
		if vfx and vfx.Parent then
			for _, emitter in ipairs(vfx:GetDescendants()) do
				if emitter:IsA("ParticleEmitter") then
					emitter.Enabled = false
				end
			end
		end
	end)

	Debris:AddItem(vfx, duration or 1.5)
end

-- ✨ PROGRESSION STATS (These can be updated later by shop upgrades!)
local playerMultSpeed = 1.0  -- 1.0 is base speed
local playerMaxMult = 5.0    -- The highest tier they can reach
local baseGrowthPerSecond = 0.8 -- At 0.8, it takes exactly 5 seconds to hit 5.0x

local function GetCurrentMultiplier()
	if not holding or not holdStart then return 1.0, 1 end

	local holdTime = tick() - holdStart
	local effectiveTime = holdTime * playerMultSpeed 

	local currentTier = 1
	local nextTier = 1

	-- 1. Find which tier we are currently in
	for i = 1, playerMaxTier do
		if effectiveTime >= MilestoneData[i].time then
			currentTier = i
			nextTier = math.min(i + 1, playerMaxTier)
		end
	end

	-- 2. If we hit the max tier, lock it at that multiplier
	if currentTier == playerMaxTier then
		return MilestoneData[currentTier].mult, currentTier
	end

	-- 3. SMOOTH MATH: Calculate the exact decimal between the current and next tier
	local timePassedInTier = effectiveTime - MilestoneData[currentTier].time
	local timeNeededForNext = MilestoneData[nextTier].time - MilestoneData[currentTier].time
	local progressRatio = timePassedInTier / timeNeededForNext

	local currentMult = MilestoneData[currentTier].mult
	local nextMult = MilestoneData[nextTier].mult
	local smoothMult = currentMult + ((nextMult - currentMult) * progressRatio)

	return smoothMult, currentTier
end

-- ✨ PASTE THIS NEW FUNCTION RIGHT HERE
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
			else
				warn("⚠️ Could not find sound named '" .. soundValue .. "' in ReplicatedStorage.SFX!")
			end
		end
	end

	if sfxToPlay then
		sfxToPlay.Parent = game:GetService("SoundService")
		sfxToPlay:Play()
		local duration = sfxToPlay.TimeLength > 0 and sfxToPlay.TimeLength or 3
		Debris:AddItem(sfxToPlay, duration)
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

	-- ✨ MOBILE FIX 1: Starts floating 15% above the button instead of 120 pixels
	pop.Position = UDim2.new(
		ClickButton.Position.X.Scale, ClickButton.Position.X.Offset, 
		ClickButton.Position.Y.Scale - 0.15, ClickButton.Position.Y.Offset
	)
	pop.Parent = ClickButton.Parent

	local stroke = Instance.new("UIStroke", pop)
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(0, 0, 0)

	-- ✨ MOBILE FIX 2: Tiny starting size using Scale instead of flat pixels
	pop.Size = UDim2.new(0.1, 0, 0.02, 0) 

	-- ✨ MOBILE FIX 3: Grows to 35% of the screen width, and floats up an extra 10%
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

local function GetColorForMultiplier(multValue)
	local floorMult = math.floor(multValue)
	local highestTier = 1
	local chosenColor = Color3.fromRGB(255, 0, 0) -- Default Red for Tier 1

	for tier, data in pairs(MilestoneData) do
		if floorMult >= tier and tier >= highestTier then
			highestTier = tier
			chosenColor = data.color
		end
	end
	return chosenColor
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
		-- Get both the exact multiplier and the Tier Index (1-5)
		mult, currentTierIndex = GetCurrentMultiplier()
		col = MilestoneData[currentTierIndex].color
		UpdateMultiplier:Fire(mult)
	end

	-- ✨ SCREEN EFFECT: Warp speed camera FOV!
	local targetFOV = defaultFOV + (mult * 1.2)
	if not holding then targetFOV = defaultFOV end
	TweenService:Create(Camera, TweenInfo.new(0.3, Enum.EasingStyle.Sine), {FieldOfView = targetFOV}):Play()

	-- ✨ BULLETPROOF MILESTONE POPUPS
	if holding then
		if currentTierIndex > lastTierIndex then
			-- If they upgraded tiers, spawn the popup for the new tier!
			-- We skip tier 1 ("NORMAL") so it doesn't pop up immediately on click.
			if currentTierIndex > 1 then
				SpawnMilestonePopup(currentTierIndex)
			end
			lastTierIndex = currentTierIndex
		end
	else
		lastTierIndex = 1
	end

	TweenService:Create(ClickButton, TweenInfo.new(0.2), { BackgroundColor3 = col }):Play()

	-- ... (Keep your alternating tilt/shake code below here exactly as it is!)

	if holding and not habitatFull then
		-- Flip the tilt direction every single time it fires
		tiltSide = tiltSide * -1 

		if mult >= 5.0 then 
			-- ✨ LEGENDARY: Violent alternating rotation (8 degrees)
			TweenService:Create(ClickButton, TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true), {
				Rotation = 8 * tiltSide
			}):Play()

			-- Fast, aggressive golden energy bleed
			clickStroke.Thickness = 12
			clickStroke.Transparency = 0
			TweenService:Create(clickStroke, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Thickness = 0, Transparency = 1}):Play()
		else
			-- ✨ NORMAL: Gentle alternating tilt (3 degrees)
			TweenService:Create(ClickButton, TweenInfo.new(0.08, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, true), {
				Rotation = 3 * tiltSide
			}):Play()
		end
	elseif not holding then
		-- Reset rotation and scale safely when let go
		TweenService:Create(ClickButton, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Rotation = 0}):Play()
		TweenService:Create(clickScale, TweenInfo.new(0.15), {Scale = 1}):Play()
	end
end

-- 3. UpdateHatcheryBar
local function UpdateHatcheryBar(current, max)
	local ratio = math.clamp(current / max, 0, 1)
	TweenService:Create(HatcheryFill, TweenInfo.new(0.1), {
		Size = UDim2.new(ratio, 0, 1, 0)
	}):Play()
	local color
	if ratio > 0.5 then color = Color3.fromRGB(80, 220, 80)
	elseif ratio > 0.25 then color = Color3.fromRGB(255, 200, 0)
	else color = Color3.fromRGB(255, 60, 60) end
	TweenService:Create(HatcheryFill, TweenInfo.new(0.1), { BackgroundColor3 = color }):Play()
	HatcheryLabel.Text = "Hatchery: " .. math.floor(current) .. " / " .. max
	hatcheryEmpty = (current <= 0)
end

-- 4. FlashEmpty
local function FlashEmpty()
	TweenService:Create(HatcheryFill, TweenInfo.new(0.1), {
		BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	}):Play()
	task.delay(0.1, function()
		TweenService:Create(HatcheryFill, TweenInfo.new(0.1), {
			BackgroundColor3 = Color3.fromRGB(255, 60, 60)
		}):Play()
	end)
end

-- 5. ShowTierPopup
local function ShowTierPopup(position, tierName, tierColor)
	local anchor = Instance.new("Part")
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Anchored = true
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.Position = position + Vector3.new(0, 3, 0)
	anchor.Parent = workspace

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 120, 0, 40)
	bb.StudsOffset = Vector3.new(0, 2, 0)
	bb.AlwaysOnTop = false
	bb.Adornee = anchor
	bb.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = tierName:upper()
	label.TextColor3 = tierColor
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextStrokeTransparency = 0.3
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.Parent = bb

	TweenService:Create(bb,
		TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ StudsOffset = Vector3.new(0, 6, 0) }
	):Play()
	TweenService:Create(label,
		TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }
	):Play()

	Debris:AddItem(anchor, 2)
end

-- 6. ShowCubeValue
local function ShowCubeValue(position, value, color)
	local anchor = Instance.new("Part")
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Anchored = true
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.Position = position + Vector3.new(math.random(-1, 1), 2, math.random(-1, 1))
	anchor.Parent = workspace

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 80, 0, 25)
	bb.StudsOffset = Vector3.new(0, 0, 0)
	bb.AlwaysOnTop = false
	bb.Adornee = anchor
	bb.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = "$" .. FormatNumber(value)  -- CHANGED: was tostring(value)
	label.TextColor3 = color
	label.TextScaled = true
	label.Font = Enum.Font.Gotham
	label.TextStrokeTransparency = 0.4
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.Parent = bb

	TweenService:Create(bb,
		TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ StudsOffset = Vector3.new(0, 4, 0) }
	):Play()
	TweenService:Create(label,
		TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }
	):Play()

	Debris:AddItem(anchor, 1.5)
end

---------------------------------------------------------------
-- 8 & 9. HOLD STATE EVALUATION (MOBILE FIX & SPACEBAR)
---------------------------------------------------------------
local trackedInputs = {}

local function EvaluateHolding()
	local hasInput = false
	for _, _ in pairs(trackedInputs) do
		hasInput = true
		break
	end

	if hasInput and not holding then
		-- Start Holding
		if hatcheryEmpty then FlashEmpty() return end
		if habitatFull then return end
		holding = true
		holdStart = tick()

		-- ✨ TACTILE PRESS: Heavy center squish before the rotations start
		TweenService:Create(clickScale, TweenInfo.new(0.1, Enum.EasingStyle.Sine), {Scale = 0.9}):Play()

		ProduceAura:FireServer("start")
	elseif not hasInput and holding then
		-- Stop Holding
		holding = false
		holdStart = nil
		ProduceAura:FireServer("stop")
		UpdateButtonVisual()
		UpdateMultiplier:Fire(1.0)
	end
end

---------------------------------------------------------------
-- 10. INPUT CONNECTIONS
---------------------------------------------------------------
ClickButton.InputBegan:Connect(function(input)
	-- Track the exact touch or click
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		trackedInputs[input] = true
		EvaluateHolding()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	-- Only stop holding if the EXACT touch/click/key that started it has been released
	if trackedInputs[input] then
		trackedInputs[input] = nil
		EvaluateHolding()
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	-- Spacebar support (Allows jumping because it doesn't block the input!)
	if input.KeyCode == Enum.KeyCode.Space then
		if not UserInputService:GetFocusedTextBox() then -- Ignores Spacebar if typing in chat
			trackedInputs[input] = true
			EvaluateHolding()
		end
	end
end)

-- Prevents the button getting "stuck" if the player alt-tabs out of Roblox
UserInputService.WindowFocusReleased:Connect(function()
	table.clear(trackedInputs)
	EvaluateHolding()
end)

ForceStopHold.OnClientEvent:Connect(function()
	table.clear(trackedInputs)
	EvaluateHolding()
end)

HabitatFull.OnClientEvent:Connect(function()
	habitatFull = true
	HabitatFullEvent:Fire(true)
	table.clear(trackedInputs)
	EvaluateHolding()
end)

HabitatFullEvent.Event:Connect(function(isFull)
	if not isFull then
		habitatFull = false
		UpdateButtonVisual()
	end
end)

UpdateHatchery.OnClientEvent:Connect(function(info)
	-- ✨ FIX: Check our local prediction to bypass server lag on spam purchases
	local finalMax = info.max
	local localHatchLvl = player:GetAttribute("LocalHatcheryLevel")

	if localHatchLvl then
		local UpgradeConfig = require(ReplicatedStorage.Modules.UpgradeConfig)
		local cfg = UpgradeConfig.GetUpgradeConfig("hatcheryCapacity")
		if cfg and cfg.apply then
			-- ✨ FIX: Pass the level directly, not wrapped in a table
			local predictedMax = cfg.apply({ upgrades = { hatcheryCapacity = localHatchLvl } })
			finalMax = math.max(info.max, predictedMax)
		end
	end

	UpdateHatcheryBar(info.current, finalMax)
end)

local UpdateHUDEvent = ReplicatedStorage.RemoteEvents:WaitForChild("UpdateHUD")
UpdateHUDEvent.OnClientEvent:Connect(function(stats)
	-- 1. Check Habitat
	if stats.pendingAuras and stats.habitatCapacity then
		if stats.pendingAuras < stats.habitatCapacity and habitatFull then
			habitatFull = false
			HabitatFullEvent:Fire(false)
			UpdateButtonVisual()
		end
	end

	-- ✨ THE FIX: Constantly check upgrades so the client never forgets!
	if stats.upgrades then
		-- ✨ THE SCALABLE TIER UNLOCK SYSTEM (Now syncing correctly on HUD update!)
		local tierUnlocks = {
			{ upgradeId = "unlockOmniMult",      tier = 10 },
			{ upgradeId = "unlockUniversalMult", tier = 9 },
			{ upgradeId = "unlockGodlyMult",     tier = 8 },
			{ upgradeId = "unlockCosmicMult",    tier = 7 },
			{ upgradeId = "unlockMythicMult",    tier = 6 },
		}

		local calculatedMaxTier = 5 -- Default max tier (Legendary) if they bought nothing

		-- Check upgrades from top to bottom
		for _, data in ipairs(tierUnlocks) do
			local upgData = stats.upgrades[data.upgradeId]
			local level = (typeof(upgData) == "table" and upgData.level) or (typeof(upgData) == "number" and upgData) or 0

			if level > 0 then
				calculatedMaxTier = data.tier
				break -- We found their highest unlock, so stop checking!
			end
		end

		-- Apply the properly calculated cap
		playerMaxTier = calculatedMaxTier

		-- Sync the Speed Multiplier
		local speedData = stats.upgrades["multiplierSpeed"]
		local speedLevel = (typeof(speedData) == "table" and speedData.level) or (typeof(speedData) == "number" and speedData) or 0
		playerMultSpeed = 1.0 + (speedLevel * 0.05) 
	end
end)

-- 11. Fire loop
task.spawn(function()
	while true do
		if holding then
			if hatcheryEmpty or habitatFull then
				-- ✨ THE FIX: Properly tell the new input system to stop holding
				table.clear(trackedInputs)
				EvaluateHolding()
			else
				ProduceAura:FireServer()
				UpdateButtonVisual()
			end
		end
		task.wait(fireRate)
	end
end)

---------------------------------------------------------------
-- 12. AuraSpawned
---------------------------------------------------------------
AuraSpawned.OnClientEvent:Connect(function(info)
	local instance, isCustom = SpawnAuraInstance(info.tier, info.color, info.glow, info.spawnPos)

	instance:SetAttribute("AuraCube", true)
	ScaleAura(instance, info.tier, false)
	ShowCubeValue(info.spawnPos, info.value, info.color)
	PlayVFX("Spawn", info.spawnPos, 1.0)

	if info.tier == "Legendary" then
		ShowTierPopup(info.spawnPos, "Legendary", Color3.fromRGB(255, 200, 0))
		PlayVFX("Legendary", info.spawnPos, 2.0)
	end

	if info.cubeId then
		cubeDataMap[info.cubeId] = {
			instance = instance,
			tierName = info.tier,
			isCustom = isCustom,
		}

		if instance:IsA("Model") then
			instance.AncestryChanged:Connect(function(_, parent)
				if not parent then cubeDataMap[info.cubeId] = nil end
			end)
		else
			instance.AncestryChanged:Connect(function(_, parent)
				if not parent then cubeDataMap[info.cubeId] = nil end
			end)
		end
	end
end)

CubeMutatedBatch.OnClientEvent:Connect(function(batchData)
	-- Loop through every mutation the server sent in this batch
	for _, info in ipairs(batchData) do

		local cubeData = cubeDataMap[info.cubeId]
		if not cubeData then continue end -- CHANGED: Use continue instead of return

		local instance = cubeData.instance
		if not instance or not instance.Parent then continue end -- CHANGED

		local rootPart = GetRootPart(instance)
		if not rootPart then continue end -- CHANGED
		local position = rootPart.Position

		if info.mutationType == "tierUpgrade" then
			PlayVFX("TierUpgrade", position, 1.5)
			if info.tierName == "Legendary" then
				PlayVFX("Legendary", position, 2.0)
			end

			local oldTierName = cubeData.tierName
			local newAura = CloneAuraModel(info.tierName)
			if newAura then
				newAura:PivotTo(CFrame.new(position))
				newAura.Parent = workspace
				newAura:SetAttribute("AuraCube", true)
				ScaleAura(newAura, info.tierName, true, oldTierName)

				if newAura.PrimaryPart then
					newAura.PrimaryPart.Anchored = false
					newAura.PrimaryPart.CanCollide = true
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
					TweenService:Create(rootPart, TweenInfo.new(0.5, Enum.EasingStyle.Quad), {
						Color = info.newColor
					}):Play()

					if info.newGlow then
						local light = rootPart:FindFirstChildOfClass("PointLight")
						if not light then
							light = Instance.new("PointLight")
							light.Parent = rootPart
						end
						TweenService:Create(light, TweenInfo.new(0.5), {
							Brightness = 3,
							Range = 8,
							Color = info.newColor,
						}):Play()
					end

					ScaleAura(instance, info.tierName, true, oldTierName)
				end

				cubeData.tierName = info.tierName
			end

			ShowTierPopup(position, info.tierName, info.newColor)

		elseif info.mutationType == "valueBonus" then
			-- Silent
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

	-- 1. Setup Speed
	local speedData = info.upgrades["multiplierSpeed"]
	local speedLevel = (typeof(speedData) == "table" and speedData.level) or (typeof(speedData) == "number" and speedData) or 0
	playerMultSpeed = 1.0 + (speedLevel * 0.05) 

	-- ✨ 2. THE NEW SCALABLE TIER UNLOCK SYSTEM
	-- List your highest upgrades at the top, down to the lowest.
	local tierUnlocks = {
		{ upgradeId = "unlockOmniMult",      tier = 10 },
		{ upgradeId = "unlockUniversalMult", tier = 9 },
		{ upgradeId = "unlockGodlyMult",     tier = 8 },
		{ upgradeId = "unlockCosmicMult",    tier = 7 },
		{ upgradeId = "unlockMythicMult",    tier = 6 },
	}

	local calculatedMaxTier = 5 -- Default max tier (Legendary) if they bought nothing

	-- Check upgrades from top to bottom. The first one they own becomes their max tier!
	for _, data in ipairs(tierUnlocks) do
		local upgData = info.upgrades[data.upgradeId]
		local level = (typeof(upgData) == "table" and upgData.level) or (typeof(upgData) == "number" and upgData) or 0

		if level > 0 then
			calculatedMaxTier = data.tier
			break -- We found their highest unlock, so stop checking!
		end
	end

	-- Apply the newly calculated cap
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

local HABITAT_HOLDER = workspace:WaitForChild("HabitatHolder")
local HABITAT_PART = HABITAT_HOLDER:WaitForChild("Position")
local lastFire          = {}
local holdStart         = {}
local hatchery          = {}
local clickSessionStart = {}

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
	local totalMV = runtime.totalMutatedValue or 0
	local pending = runtime.cubeCount
	local avgVal  = pending > 0 and (totalMV/pending) or AdminConfig.BaseAuraValue
	local rate    = math.floor(pending * avgVal)
	local passTickCfg = UpgradeConfig.GetUpgradeConfig("passiveTickSpeed")

	local passInt = (passTickCfg and passTickCfg.apply) and passTickCfg.apply(data) or AdminConfig.PassiveInterval
	local displayRate = math.floor(rate * BoostManager.GetValueMultiplier(uid) * BoostManager.GetSpawnRateMultiplier(uid))
	UpdateHUD:FireClient(player, {
		currency=data.currency, pendingAuras=pending,
		habitatCapacity=GetHabitatCapacity(data), rate=displayRate,
		passiveInterval=passInt, totalEarned=data.totalEarned or 0,
		soulAuras=data.soulAuras or 0, farmEvaluation=data.farmEvaluation or 0,
		goldenAuras=data.goldenAuras or 0, boostInventory=data.boostInventory or {},
		prestigeCount=data.prestigeCount or 0,
		upgrades=data.upgrades or {},
		totalCubesProduced = data.totalCubesProduced or 0,
		currentArea        = data.currentArea or 1,
	})
end

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
							tierName = newTier.name 
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
		table.insert(adjusted, { tier=tier, chance=chance }); total += chance
	end
	local r, cum = math.random()*total, 0
	for _, e in ipairs(adjusted) do
		cum += e.chance; if r <= cum then return e.tier end
	end
	return tiers[1]
end

local function SpawnAura(player, data, runtime, holdMult, luckBonus)
	local uid  = player.UserId
	local tier = RollWithLuck(luckBonus)
	local tierIndex = 1
	for i, t in ipairs(TierConfig.Tiers) do if t.name == tier.name then tierIndex=i; break end end

	local totalValueMultiplier = 1.0 
	local valueUpgrades = {
		"blockValue", "blockValueT2", "auraValueT3", 
		"auraValueT4", "auraValueT6", "auraValueT8", "auraValueT10"
	}

	for _, upgradeId in ipairs(valueUpgrades) do
		local cfg = UpgradeConfig.GetUpgradeConfig(upgradeId)
		if cfg and cfg.apply then
			totalValueMultiplier += cfg.apply(data) 
		end
	end

	local prestigeMult    = PrestigeModule.GetMultiplier(data.soulAuras)
	local areaMult        = AreaRegistry.GetMultiplier(data.currentArea or 1)
	local boostValueMult  = BoostManager.GetValueMultiplier(uid)
	local _, weatherValueMult = WeatherManager.GetMultipliers(uid)

	local baseValue  = math.floor(AdminConfig.BaseAuraValue * tier.multiplier * totalValueMultiplier * prestigeMult * areaMult * boostValueMult * weatherValueMult)
	local totalValue = baseValue + math.floor(baseValue * (holdMult - 1))

	local spawnPos = HABITAT_PART.Position + Vector3.new(math.random(-3,3), 10, math.random(-3,3))	
	local cubeRecord = {
		spawnTime=tick(), effectiveElapsed=0, lastUpgradeElapsed=0,
		baseValue=totalValue, tierIndex=tierIndex,
		tierName=tier.name, color=tier.color, glow=tier.glow,
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
	})
end

ProduceAura.OnServerEvent:Connect(function(player, action)
	local uid = player.UserId
	local now = tick()
	local data    = GameManager.GetData(uid)
	local runtime = GameManager.GetRuntime(uid)

	if action == "start" then 
		if data and runtime and runtime.cubeCount >= GetHabitatCapacity(data) then
			HabitatFull:FireClient(player)
			return
		end

		-- ✨ Require at least 0.5 juice to start holding so it doesn't instantly die
		if (hatchery[uid] or 0) > 0.5 then 
			holdStart[uid] = now 
		else
			UpdateHatchery:FireClient(player, { current = 0, max = data and GetHatcheryMax(data) or AdminConfig.HatcheryMax })
		end
		return 
	end

	if action == "stop" then 
		holdStart[uid] = nil
		return 
	end

	if not data or not runtime then return end

	if runtime.cubeCount >= GetHabitatCapacity(data) then 
		HabitatFull:FireClient(player)
		return 
	end

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

