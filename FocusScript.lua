-- PortalController
-- Location: StarterPlayer > StarterPlayerScripts > PortalController

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

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

-- ✨ BRIDGENET2 UPGRADE
local BridgeNet2      = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))
local UpdateHUDBridge = BridgeNet2.ClientBridge("UpdateHUD")

local ForceCloseUI = ReplicatedStorage:FindFirstChild("ForceCloseUI") or Instance.new("BindableEvent")
ForceCloseUI.Name = "ForceCloseUI"
ForceCloseUI.Parent = ReplicatedStorage

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

-- ✨ UI Setup (AreaPanel)
local AreaPanel = Instance.new("Frame")
AreaPanel.Name="AreaTravelPanel"; AreaPanel.Size = UDim2.new(0.88, 0, 0.82, 0)
AreaPanel.Position = UDim2.new(0.5, 0, 0.5, 0)
AreaPanel.AnchorPoint = Vector2.new(0.5, 0.5)
AreaPanel.BackgroundColor3=T.panelBG; AreaPanel.BorderSizePixel=0
AreaPanel.Visible=false; AreaPanel.ZIndex=30; AreaPanel.ClipsDescendants=true
AreaPanel.Parent=mainHUD
CollectionService:AddTag(AreaPanel, "Tutorial_TravelPanel") 
Instance.new("UICorner",AreaPanel).CornerRadius=UDim.new(0,PR)

local sizeConstraint = Instance.new("UISizeConstraint")
sizeConstraint.MaxSize = Vector2.new(PW, PH) 
sizeConstraint.Parent = AreaPanel

local panelStroke=Instance.new("UIStroke"); panelStroke.Color=T.panelStroke; panelStroke.Thickness=2; panelStroke.Parent=AreaPanel

local PortalContentScaler = Instance.new("Frame")
PortalContentScaler.Name = "ContentScaler"
PortalContentScaler.AnchorPoint = Vector2.new(0.5, 0)
PortalContentScaler.Position = UDim2.new(0.5, 0, 0, 0)
PortalContentScaler.BackgroundTransparency = 1
PortalContentScaler.Parent = AreaPanel

local portalContentScale = Instance.new("UIScale")
portalContentScale.Parent = PortalContentScaler

local PORTAL_DESIGN_WIDTH = 480

local function UpdatePortalScale()
	local realWidth = AreaPanel.AbsoluteSize.X
	if realWidth <= 0 then return end
	local scale = realWidth / PORTAL_DESIGN_WIDTH
	if scale > 1.05 then scale = 1.05 end
	portalContentScale.Scale = scale
	PortalContentScaler.Size = UDim2.new(0, PORTAL_DESIGN_WIDTH, 1 / scale, 0)
end

AreaPanel:GetPropertyChangedSignal("AbsoluteSize"):Connect(UpdatePortalScale)
UpdatePortalScale()

local HeaderBar=Instance.new("Frame"); HeaderBar.Size=UDim2.new(1,0,0,46); HeaderBar.BackgroundColor3=T.headerBG
HeaderBar.BorderSizePixel=0; HeaderBar.ZIndex=31; HeaderBar.Parent=PortalContentScaler
Instance.new("UICorner",HeaderBar).CornerRadius=UDim.new(0,PR)
local HeaderLabel=Instance.new("TextLabel"); HeaderLabel.Size=UDim2.new(1,-50,1,0); HeaderLabel.Position=UDim2.new(0,16,0,0)
HeaderLabel.BackgroundTransparency=1; HeaderLabel.Text="AREA TRAVEL"; HeaderLabel.TextColor3=T.headerText
HeaderLabel.TextScaled=true; HeaderLabel.Font=T.font; HeaderLabel.TextXAlignment=Enum.TextXAlignment.Left
HeaderLabel.ZIndex=32; HeaderLabel.Parent=HeaderBar
local CloseBtn=Instance.new("TextButton"); CloseBtn.Size=UDim2.new(0,32,0,32); CloseBtn.Position=UDim2.new(1,-40,0.5,-16)
CloseBtn.BackgroundColor3=T.buttonRed; CloseBtn.BorderSizePixel=0; CloseBtn.Text="X"; CloseBtn.TextColor3=T.bodyText
CloseBtn.TextScaled=true; CloseBtn.Font=T.font; CloseBtn.ZIndex=33; CloseBtn.Parent=HeaderBar
CollectionService:AddTag(CloseBtn, "Tutorial_TravelCloseBtn") 
Instance.new("UICorner",CloseBtn).CornerRadius=UDim.new(0,6)

local ScrollContainer = Instance.new("ScrollingFrame")
ScrollContainer.Name = "ScrollContainer"
ScrollContainer.Parent = AreaPanel -- kept OUTSIDE PortalContentScaler for correct mobile touch scrolling
ScrollContainer.BackgroundTransparency = 1
ScrollContainer.BorderSizePixel = 0
ScrollContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
ScrollContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y 
ScrollContainer.ScrollBarThickness = 6

local function UpdatePortalScrollBounds()
	local scale = portalContentScale.Scale
	local scaledTop = 46 * scale
	ScrollContainer.Position = UDim2.new(0, 0, 0, scaledTop)
	ScrollContainer.Size     = UDim2.new(1, 0, 1, -scaledTop)
end

portalContentScale:GetPropertyChangedSignal("Scale"):Connect(UpdatePortalScrollBounds)
UpdatePortalScrollBounds()

local PortalCardsScaler = Instance.new("Frame")
PortalCardsScaler.Name = "CardsScaler"
PortalCardsScaler.BackgroundTransparency = 1
PortalCardsScaler.Parent = ScrollContainer

local portalCardsScale = Instance.new("UIScale")
portalCardsScale.Parent = PortalCardsScaler

local PORTAL_CARDS_DESIGN_WIDTH = 460

local function UpdatePortalCardsScale()
	local realWidth = ScrollContainer.AbsoluteSize.X
	if realWidth <= 0 then return end
	local scale = realWidth / PORTAL_CARDS_DESIGN_WIDTH
	if scale > 1.05 then scale = 1.05 end
	portalCardsScale.Scale = scale
	PortalCardsScaler.Size = UDim2.new(0, PORTAL_CARDS_DESIGN_WIDTH, 1 / scale, 0)
end

ScrollContainer:GetPropertyChangedSignal("AbsoluteSize"):Connect(UpdatePortalCardsScale)
UpdatePortalCardsScale()

local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 10) 
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center 
listLayout.Parent = PortalCardsScaler

local topPadding = Instance.new("UIPadding")
topPadding.PaddingTop = UDim.new(0, 10)
topPadding.PaddingBottom = UDim.new(0, 10)
topPadding.Parent = PortalCardsScaler

local GoalSection=Instance.new("Frame"); GoalSection.Size=UDim2.new(1,-24,0,90)
GoalSection.BackgroundColor3=T.cardBG; GoalSection.BorderSizePixel=0; GoalSection.ZIndex=31; GoalSection.Parent=PortalCardsScaler
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
AreaBrowser.BackgroundColor3=T.cardBG; AreaBrowser.BorderSizePixel=0; AreaBrowser.ZIndex=31; AreaBrowser.Parent=PortalCardsScaler
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
CollectionService:AddTag(LeftArrow, "Tutorial_LeftArrow") 
Instance.new("UICorner",LeftArrow).CornerRadius=UDim.new(0,18)
local RightArrow=Instance.new("TextButton"); RightArrow.Size=UDim2.new(0,36,0,36); RightArrow.Position=UDim2.new(1,-44,0,62)
RightArrow.BackgroundColor3=T.headerBG; RightArrow.BorderSizePixel=0; RightArrow.Text=">"; RightArrow.TextColor3=T.bodyText
RightArrow.TextScaled=true; RightArrow.Font=T.font; RightArrow.ZIndex=33; RightArrow.Parent=AreaBrowser
CollectionService:AddTag(RightArrow, "Tutorial_RightArrow") 
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
CollectionService:AddTag(TravelBtn, "Tutorial_TravelConfirm") 
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

local travelDebounce = false
TravelBtn.MouseButton1Down:Connect(function()
	if travelDebounce then return end

	if type(shared.TutorialCanPerform) == "function" then
		local canConfirm = shared.TutorialCanPerform("Action_TravelConfirm")
		if not canConfirm then canConfirm = shared.TutorialCanPerform("Action_TravelArea") end
		if not canConfirm then return end
	end

	if browseIndex == currentArea then return end

	travelDebounce = true
	task.delay(0.25, function() travelDebounce = false end)

	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end

	local targetIndex = tonumber(browseIndex)
	if targetIndex then
		TravelToArea:FireServer(targetIndex)
	end
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
	RightArrow.Visible = (idx < MAX_AREA) and (AreaRegistry.Get(idx+1) ~= nil)

	local highestUnlocked = 1
	for _, v in ipairs(unlockedAreas) do
		if v > highestUnlocked then highestUnlocked = v end
	end
	if highestUnlocked > MAX_AREA then highestUnlocked = MAX_AREA end

	local unlockReq = areaData.threshold or 0
	local discReq = areaData.discoveryThreshold or (unlockReq * 0.25) 

	if idx <= highestUnlocked then
		local flipbookData = AreaRegistry.GetFlipbook(idx)
		if flipbookData then
			StartFlipbook(idx, AreaIcon)
			AreaIcon.ImageColor3 = Color3.fromRGB(255, 255, 255)
		else
			StopFlipbook()
			AreaIcon.Image = areaData.icon or areaData.auraPreviewImage or ""
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
				AreaIcon.Image = areaData.icon or areaData.auraPreviewImage or ""
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
				AreaIcon.Image = areaData.icon or areaData.auraPreviewImage or ""
				AreaIcon.ImageRectSize = Vector2.new(0, 0)
				AreaIcon.ImageRectOffset = Vector2.new(0, 0)
				AreaIcon.ImageColor3 = Color3.fromRGB(180, 180, 180)
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
			AreaIcon.Image = areaData.icon or areaData.auraPreviewImage or ""
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
		AreaIcon.Image = areaData.icon or areaData.auraPreviewImage or ""
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

local arrowDebounce = false

LeftArrow.MouseButton1Down:Connect(function()
	if arrowDebounce then return end
	if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_BrowseArea") then return end

	if browseIndex > 1 then 
		arrowDebounce = true
		task.delay(0.15, function() arrowDebounce = false end)

		if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
		browseIndex -= 1; PlayUI(SoundConfig.UIArrow); RefreshBrowser() 
	end
end)

RightArrow.MouseButton1Down:Connect(function()
	if arrowDebounce then return end
	if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_BrowseArea") then return end

	if browseIndex < MAX_AREA and AreaRegistry.Get(browseIndex+1) then 
		arrowDebounce = true
		task.delay(0.15, function() arrowDebounce = false end)

		if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
		browseIndex += 1; PlayUI(SoundConfig.UIArrow); RefreshBrowser() 
	end
end)

local AreaTravelBtn = Instance.new("TextButton")
AreaTravelBtn.Name = "AreaTravelButton"
AreaTravelBtn.Size = UDim2.new(0, C.HUD.NextAreaButtonW, 0, C.HUD.NextAreaButtonH)
AreaTravelBtn.Position = UDim2.new(0, 156, 1, C.HUD.BottomButtonY)
AreaTravelBtn.BackgroundColor3 = T.headerBG; AreaTravelBtn.BorderSizePixel = 0
AreaTravelBtn.Text = "" 
AreaTravelBtn.Visible = true 
AreaTravelBtn.ZIndex = 10; AreaTravelBtn.Parent = mainHUD
CollectionService:AddTag(AreaTravelBtn, "Tutorial_TravelButton")

Instance.new("UICorner", AreaTravelBtn).CornerRadius = UDim.new(0, 10)

local travelBtnGradient = Instance.new("UIGradient", AreaTravelBtn)
travelBtnGradient.Rotation = 90
travelBtnGradient.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.15),
	NumberSequenceKeypoint.new(1, 0),
})

local travelBtnGlow = Instance.new("UIStroke", AreaTravelBtn)
travelBtnGlow.Color = Color3.fromRGB(100, 180, 255)
travelBtnGlow.Thickness = 1.5
travelBtnGlow.Transparency = 0.3

local AreaTravelBtnIcon = Instance.new("ImageLabel")
AreaTravelBtnIcon.Name = "Icon"
AreaTravelBtnIcon.Size = UDim2.new(0, 22, 0, 22)
AreaTravelBtnIcon.Position = UDim2.new(0, 10, 0.5, -11)
AreaTravelBtnIcon.BackgroundTransparency = 1
AreaTravelBtnIcon.ScaleType = Enum.ScaleType.Fit
AreaTravelBtnIcon.Image = "rbxassetid://14916846070" -- swap for your portal/map icon
AreaTravelBtnIcon.ZIndex = 11
AreaTravelBtnIcon.Parent = AreaTravelBtn

local AreaTravelBtnLabel = Instance.new("TextLabel")
AreaTravelBtnLabel.Name = "Label"
AreaTravelBtnLabel.Size = UDim2.new(1, -40, 1, 0)
AreaTravelBtnLabel.Position = UDim2.new(0, 36, 0, 0)
AreaTravelBtnLabel.BackgroundTransparency = 1
AreaTravelBtnLabel.Text = "Area Travel"
AreaTravelBtnLabel.TextColor3 = T.bodyText
AreaTravelBtnLabel.TextScaled = false
AreaTravelBtnLabel.TextSize = 22
AreaTravelBtnLabel.Font = T.font
AreaTravelBtnLabel.TextXAlignment = Enum.TextXAlignment.Left
AreaTravelBtnLabel.ZIndex = 11
AreaTravelBtnLabel.Parent = AreaTravelBtn

AddButtonJuice(AreaTravelBtn)

local function UpdateTravelButtonVisual()
	local canTravel = (#unlockedAreas > 1) or portalReady
	if canTravel then
		TweenService:Create(AreaTravelBtn, TweenInfo.new(0.3), { BackgroundColor3 = Color3.fromRGB(40, 130, 210) }):Play()
		TweenService:Create(AreaTravelBtnLabel, TweenInfo.new(0.3), { TextColor3 = Color3.fromRGB(255, 255, 255) }):Play()
	else
		TweenService:Create(AreaTravelBtn, TweenInfo.new(0.3), { BackgroundColor3 = Color3.fromRGB(50, 55, 70) }):Play()
		TweenService:Create(AreaTravelBtnLabel, TweenInfo.new(0.3), { TextColor3 = Color3.fromRGB(180, 180, 180) }):Play()
	end
end

local function OpenPanel()
	ForceCloseUI:Fire("AreaTravelPanel")
	panelOpen=true; browseIndex=currentArea; UpdateGoalSection(); RefreshBrowser()
	AreaPanel.Visible=true
	AreaPanel.Size=UDim2.new(0.88, 0, 0, 0)
	TweenService:Create(AreaPanel, TweenInfo.new(0.35,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
		{ Size=UDim2.new(0.88, 0, 0.82, 0) }):Play()
	UITheme.SetMenuVisible(true)
end

local function ClosePanel()
	panelOpen=false; StopFlipbook(); PlayUI(SoundConfig.UIClose)
	TweenService:Create(AreaPanel, TweenInfo.new(0.25,Enum.EasingStyle.Quad,Enum.EasingDirection.In),
		{ Size=UDim2.new(0.88, 0, 0, 0) }):Play()
	UITheme.SetMenuVisible(false)
	task.delay(0.3, function() AreaPanel.Visible=false end)
end

local panelDebounce = false

AreaTravelBtn.MouseButton1Down:Connect(function()
	if panelDebounce then return end
	panelDebounce = true
	task.delay(0.25, function() panelDebounce = false end)

	if panelOpen then
		if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_CloseTravel") then return end
		if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
		ClosePanel()
	else
		if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_OpenTravel") then return end
		if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
		OpenPanel()
	end
end)

CloseBtn.MouseButton1Down:Connect(function()
	if panelDebounce then return end
	panelDebounce = true
	task.delay(0.25, function() panelDebounce = false end)

	if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_CloseTravel") then return end

	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
	ClosePanel()
end)

local function ShowAreaBanner(info)
	if type(info.newArea) ~= "number" then return end

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

UpdateHUDBridge:Connect(function(stats)
	if stats.farmEvaluation ~= nil then liveFarmEval = stats.farmEvaluation end
	if panelOpen then UpdateGoalSection(); RefreshBrowser() end
end)

AreaUpdated.OnClientEvent:Connect(function(info)
	if type(info.currentArea) == "number" then
		currentArea = info.currentArea
	end

	if currentArea > 1 then player:SetAttribute("TutorialCompleted", true) end
	portalReady = info.portalReady == true
	if info.unlockedAreas then unlockedAreas = info.unlockedAreas end

	MAX_AREA = info.maxArea or AreaRegistry.GetMaxArea()
	if type(browseIndex) == "number" and type(MAX_AREA) == "number" then
		if browseIndex > MAX_AREA then browseIndex = MAX_AREA end
	end

	if info.portalReady then AddPortalPrompt() else RemovePortalPrompt() end

	UpdateTravelButtonVisual()

	if panelOpen then UpdateGoalSection(); RefreshBrowser() end
end)

AreaUnlocked.OnClientEvent:Connect(function(info)
	portalReady = true; AddPortalPrompt()
	if info.unlockedAreas then unlockedAreas = info.unlockedAreas end

	UpdateTravelButtonVisual()

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
		UpdateTravelButtonVisual() 
		if panelOpen then ClosePanel() end
	end
end)

AreaChanged.OnClientEvent:Connect(function(info)
	if type(info.newArea) == "number" then
		currentArea = info.newArea 
		browseIndex = currentArea
	end

	portalReady = false
	if info.unlockedAreas then unlockedAreas = info.unlockedAreas end
	UpdateTravelButtonVisual()
	if panelOpen then ClosePanel() end
	ShowAreaBanner(info)
end)

function AddPortalPrompt()
	if promptAdded then return end; promptAdded = true
	local prompt=Instance.new("ProximityPrompt"); prompt.Name="PortalPrompt"; prompt.ObjectText="Portal"
	prompt.ActionText="Open Area Travel"; prompt.HoldDuration=0.5; prompt.MaxActivationDistance=12
	prompt.Parent=PositionPart
	prompt.Triggered:Connect(function(p) 
		if p == player and not panelOpen then 
			if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_OpenTravel") then return end

			if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
			OpenPanel() 
		end 
	end)
end

function RemovePortalPrompt()
	promptAdded=false; local e=PositionPart:FindFirstChild("PortalPrompt"); if e then e:Destroy() end
end

local function RefreshLook()
	UITheme.Apply(AreaPanel, "Panel")
	UITheme.Apply(HeaderBar, "TitleBar")
	UITheme.Apply(GoalSection, "ShopCard")
	UITheme.Apply(AreaBrowser, "ShopCard")
	UITheme.Apply(HeaderBar, "Panel")
	UITheme.Apply(RightArrow, "Panel")
	UITheme.Apply(LeftArrow, "Panel")
	UITheme.Apply(AreaTravelBtn, "Panel")
	UITheme.ApplyShine(AreaBrowser)
	UITheme.ApplyShine(GoalSection)
	UITheme.ApplyShine(AreaPanel)
	GoalSection.BackgroundColor3 = T.cardBG 
	AreaBrowser.BackgroundColor3 = T.cardBG
	local outerStroke = AreaPanel:FindFirstChildWhichIsA("UIStroke")
	if outerStroke then outerStroke.Color = Color3.fromRGB(255, 255, 255) end
end

task.wait(2)
RefreshLook()

ForceCloseUI.Event:Connect(function(exceptionPanel)
	if exceptionPanel ~= "AreaTravelPanel" and panelOpen then ClosePanel() end
end)

-- STREAMING_CHUNK:Initializing UI dependencies...
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local MarketplaceService = game:GetService("MarketplaceService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local UITheme = require(ReplicatedStorage.Modules:WaitForChild("UITheme"))
local T = UITheme.Get("Custom")
local SoundConfig = require(ReplicatedStorage.Modules:WaitForChild("SoundConfig"))
local NumberFormatter = require(ReplicatedStorage.Modules:WaitForChild("NumberFormatter"))
local BridgeNet2 = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))
local BankConfig = require(ReplicatedStorage.Modules:WaitForChild("BankConfig"))

-- STREAMING_CHUNK:Mapping Client Bridges...
local UpdateHUDBridge = BridgeNet2.ClientBridge("UpdateHUD")
local BankActionBridge = BridgeNet2.ClientBridge("BankAction")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainHUD = playerGui:WaitForChild("MainHUD")

local ForceCloseUI = ReplicatedStorage:FindFirstChild("ForceCloseUI") or Instance.new("BindableEvent")
ForceCloseUI.Name = "ForceCloseUI"
if not ForceCloseUI.Parent then ForceCloseUI.Parent = ReplicatedStorage end

local panelOpen = false
local currentAurmers = 0
local currentBank = 0
local currentArea = 1

-- STREAMING_CHUNK:Setting up Tooltip system...
local TooltipGui = Instance.new("ScreenGui", playerGui)
TooltipGui.Name = "GamepassTooltipGui"
TooltipGui.DisplayOrder = 2000

local TooltipLabel = Instance.new("TextLabel", TooltipGui)
TooltipLabel.Size = UDim2.new(0, 240, 0, 32)
TooltipLabel.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
TooltipLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
TooltipLabel.Font = Enum.Font.GothamMedium
TooltipLabel.TextSize = 14
TooltipLabel.Text = "Thank you for supporting the game!"
TooltipLabel.Visible = false
TooltipLabel.ZIndex = 50
Instance.new("UICorner", TooltipLabel).CornerRadius = UDim.new(0, 6)
local tipStroke = Instance.new("UIStroke", TooltipLabel)
tipStroke.Color = Color3.fromRGB(255, 215, 0)
tipStroke.Thickness = 1.5

RunService.RenderStepped:Connect(function()
	if TooltipLabel.Visible then
		local mousePos = UserInputService:GetMouseLocation()
		TooltipLabel.Position = UDim2.new(0, mousePos.X + 15, 0, mousePos.Y + 15)
	end
end)

local function BindTooltip(uiElement)
	uiElement.MouseEnter:Connect(function() TooltipLabel.Visible = true end)
	uiElement.MouseLeave:Connect(function() TooltipLabel.Visible = false end)
	uiElement.SelectionLost:Connect(function() TooltipLabel.Visible = false end)
end

-- STREAMING_CHUNK:Configuring Button Juice...
local function AddButtonJuice(btn)
	local scale = btn:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", btn)
	btn.MouseEnter:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Sine), {Scale = 1.05}):Play() end)
	btn.MouseLeave:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Sine), {Scale = 1}):Play() end)
	btn.MouseButton1Down:Connect(function() TweenService:Create(scale, TweenInfo.new(0.1, Enum.EasingStyle.Sine), {Scale = 0.95}):Play() end)
	btn.MouseButton1Up:Connect(function() TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), {Scale = 1.05}):Play() end)
end

-- STREAMING_CHUNK:Building Store Panel Frame...
local StoreBtn = Instance.new("ImageButton")
StoreBtn.Name = "StoreButton"
StoreBtn.Size = UDim2.new(0.85, 0, 0.85, 0)
StoreBtn.BackgroundColor3 = T.buttonSecondary
StoreBtn.BorderSizePixel = 0
StoreBtn.LayoutOrder = 3
Instance.new("UICorner", StoreBtn).CornerRadius = UDim.new(0.5, 0)
Instance.new("UIAspectRatioConstraint", StoreBtn).AspectRatio = 1.0
local btnStroke = Instance.new("UIStroke", StoreBtn)
btnStroke.Color = Color3.fromRGB(125, 255, 162)
btnStroke.Thickness = 2
local btnIcon = Instance.new("ImageLabel", StoreBtn)
btnIcon.Size = UDim2.new(0.6, 0, 0.6, 0)
btnIcon.Position = UDim2.new(0.2, 0, 0.2, 0)
btnIcon.BackgroundTransparency = 1
btnIcon.ScaleType = Enum.ScaleType.Fit
btnIcon.Image = "rbxassetid://14923161672"
AddButtonJuice(StoreBtn)

local Faded2 = mainHUD:FindFirstChild("Faded2")
if Faded2 then StoreBtn.Parent = Faded2 end
CollectionService:AddTag(StoreBtn, "Tutorial_StoreButton")

local Panel = Instance.new("Frame", mainHUD)
Panel.Name = "StorePanel"
Panel.Size = UDim2.new(0.85, 0, 0.75, 0)
Panel.Position = UDim2.new(0.5, 0, 0.5, 0)
Panel.AnchorPoint = Vector2.new(0.5, 0.5)
Panel.BackgroundColor3 = T.panelBG
Panel.BorderSizePixel = 0
Panel.Visible = false
Panel.ZIndex = 40
Panel.ClipsDescendants = true
Instance.new("UICorner", Panel).CornerRadius = UDim.new(0, 12)
Instance.new("UISizeConstraint", Panel).MaxSize = Vector2.new(500, 650)
local panelStroke = Instance.new("UIStroke", Panel)
panelStroke.Color = T.panelStroke
panelStroke.Thickness = 2
CollectionService:AddTag(Panel, "Tutorial_StorePanel")

local ContentScaler = Instance.new("Frame")
ContentScaler.Name = "ContentScaler"
ContentScaler.AnchorPoint = Vector2.new(0.5, 0)
ContentScaler.Position = UDim2.new(0.5, 0, 0, 0)
ContentScaler.BackgroundTransparency = 1
ContentScaler.Parent = Panel

local storeContentScale = Instance.new("UIScale")
storeContentScale.Parent = ContentScaler

local STORE_DESIGN_WIDTH = 480

local function UpdateStoreScale()
	local realWidth = Panel.AbsoluteSize.X
	if realWidth <= 0 then return end
	local scale = realWidth / STORE_DESIGN_WIDTH
	if scale > 1.05 then scale = 1.05 end
	storeContentScale.Scale = scale
	ContentScaler.Size = UDim2.new(0, STORE_DESIGN_WIDTH, 1 / scale, 0)
end

Panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(UpdateStoreScale)
UpdateStoreScale()

-- STREAMING_CHUNK:Adding Header and Close Button...
local Header = Instance.new("Frame", ContentScaler)
Header.Size = UDim2.new(1, 0, 0, 46)
Header.BackgroundColor3 = T.headerBG
Header.BorderSizePixel = 0
Header.ZIndex = 41
Instance.new("UICorner", Header).CornerRadius = UDim.new(0, 12)

local TitleLabel = Instance.new("TextLabel", Header)
TitleLabel.Size = UDim2.new(1, -50, 1, 0)
TitleLabel.Position = UDim2.new(0, 16, 0, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Text = "STORE & BANK"
TitleLabel.TextColor3 = T.headerText
TitleLabel.TextScaled = true
TitleLabel.Font = T.font
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.ZIndex = 42

local CloseBtn = Instance.new("TextButton", Header)
CloseBtn.Size = UDim2.new(0, 32, 0, 32)
CloseBtn.Position = UDim2.new(1, -40, 0.5, -16)
CloseBtn.BackgroundColor3 = T.buttonRed
CloseBtn.BorderSizePixel = 0
CloseBtn.Text = "X"
CloseBtn.TextColor3 = T.bodyText
CloseBtn.TextScaled = true
CloseBtn.Font = T.font
CloseBtn.ZIndex = 43
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 6)
AddButtonJuice(CloseBtn)

-- STREAMING_CHUNK:Creating Scrolling Frames...
local ScrollFrame = Instance.new("ScrollingFrame")
ScrollFrame.Parent = Panel -- kept OUTSIDE ContentScaler for correct mobile touch scrolling
ScrollFrame.BackgroundTransparency = 1
ScrollFrame.BorderSizePixel = 0
ScrollFrame.ScrollBarThickness = 6
ScrollFrame.ScrollBarImageColor3 = T.accentGold
ScrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
ScrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
ScrollFrame.ZIndex = 41

local function UpdateStoreScrollBounds()
	local scale = storeContentScale.Scale
	local scaledTop = 46 * scale
	ScrollFrame.Position = UDim2.new(0, 0, 0, scaledTop)
	ScrollFrame.Size     = UDim2.new(1, 0, 1, -scaledTop)
end

storeContentScale:GetPropertyChangedSignal("Scale"):Connect(UpdateStoreScrollBounds)
UpdateStoreScrollBounds()

local StoreCardsScaler = Instance.new("Frame")
StoreCardsScaler.Name = "CardsScaler"
StoreCardsScaler.BackgroundTransparency = 1
StoreCardsScaler.Parent = ScrollFrame

local storeCardsScale = Instance.new("UIScale")
storeCardsScale.Parent = StoreCardsScaler

local STORE_CARDS_DESIGN_WIDTH = 460

local function UpdateStoreCardsScale()
	local realWidth = ScrollFrame.AbsoluteSize.X
	if realWidth <= 0 then return end
	local scale = realWidth / STORE_CARDS_DESIGN_WIDTH
	if scale > 1.05 then scale = 1.05 end
	storeCardsScale.Scale = scale
	StoreCardsScaler.Size = UDim2.new(0, STORE_CARDS_DESIGN_WIDTH, 1 / scale, 0)
end

ScrollFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(UpdateStoreCardsScale)
UpdateStoreCardsScale()

local Layout = Instance.new("UIListLayout", StoreCardsScaler)
Layout.SortOrder = Enum.SortOrder.LayoutOrder
Layout.Padding = UDim.new(0, 15)
Layout.HorizontalAlignment = Enum.HorizontalAlignment.Center

local TopPadding = Instance.new("UIPadding", StoreCardsScaler)
TopPadding.PaddingTop = UDim.new(0, 15)
TopPadding.PaddingBottom = UDim.new(0, 15)

local VisualElements = {}
local GamepassBuyButtons = {}

local function CreateSectionLabel(text, order)
	local lbl = Instance.new("TextLabel", StoreCardsScaler)
	lbl.Size = UDim2.new(1, -30, 0, 24)
	lbl.BackgroundTransparency = 1
	lbl.Text = text
	lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
	lbl.TextScaled = true
	lbl.Font = Enum.Font.FredokaOne
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.LayoutOrder = order
	return lbl
end

-- STREAMING_CHUNK:Initializing Piggybank Card...
local function CreateCard(parent, sizeY, order)
	local card = Instance.new("Frame", parent)
	card.Size = UDim2.new(1, -30, 0, sizeY)
	card.BackgroundColor3 = T.cardBG
	card.BorderSizePixel = 0
	card.LayoutOrder = order
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 8)
	table.insert(VisualElements, card)
	return card
end

local BankCard = CreateCard(StoreCardsScaler, 130, 1)

local BankTitle = Instance.new("TextLabel", BankCard)
BankTitle.Size = UDim2.new(1, -24, 0, 24)
BankTitle.Position = UDim2.new(0, 12, 0, 12)
BankTitle.BackgroundTransparency = 1
BankTitle.Text = "GOLDEN AURA PIGGYBANK"
BankTitle.TextColor3 = T.accentGold
BankTitle.TextScaled = true
BankTitle.Font = Enum.Font.FredokaOne

local BankAmountLabel = Instance.new("TextLabel", BankCard)
BankAmountLabel.Size = UDim2.new(1, -24, 0, 32)
BankAmountLabel.Position = UDim2.new(0, 12, 0, 40)
BankAmountLabel.BackgroundTransparency = 1
BankAmountLabel.Text = "Stored: 0 GA"
BankAmountLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
BankAmountLabel.TextScaled = true
BankAmountLabel.Font = Enum.Font.GothamBold
BankAmountLabel.TextXAlignment = Enum.TextXAlignment.Left

-- STREAMING_CHUNK:Setting up Bank Badges...
local BankBadges = Instance.new("Frame", BankCard)
BankBadges.Size = UDim2.new(0.5, -12, 0, 32)
BankBadges.Position = UDim2.new(1, -12, 0, 40)
BankBadges.AnchorPoint = Vector2.new(1, 0)
BankBadges.BackgroundTransparency = 1
local bbLayout = Instance.new("UIListLayout", BankBadges)
bbLayout.FillDirection = Enum.FillDirection.Horizontal
bbLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
bbLayout.VerticalAlignment = Enum.VerticalAlignment.Center
bbLayout.Padding = UDim.new(0, 6)

local function CreateBankBadge(text, color, strokeColor)
	local badge = Instance.new("TextLabel", BankBadges)
	badge.Size = UDim2.new(0, 0, 0, 22)
	badge.AutomaticSize = Enum.AutomaticSize.X
	badge.BackgroundColor3 = color
	badge.TextColor3 = Color3.fromRGB(255, 255, 255)
	badge.Font = Enum.Font.FredokaOne
	badge.TextSize = 14
	badge.Text = " " .. text .. " "
	badge.Visible = false
	Instance.new("UICorner", badge).CornerRadius = UDim.new(0, 5)
	local strk = Instance.new("UIStroke", badge)
	strk.Color = strokeColor
	strk.Thickness = 1.5
	BindTooltip(badge)
	return badge
end

local Badge_FasterFill = CreateBankBadge("2x Fill", Color3.fromRGB(0, 120, 200), Color3.fromRGB(0, 50, 100))
local Badge_BonusBreak = CreateBankBadge("+40% Auras", Color3.fromRGB(150, 50, 200), Color3.fromRGB(80, 0, 100))
local Badge_DoubleCash = CreateBankBadge("2x Cash", Color3.fromRGB(0, 150, 60), Color3.fromRGB(0, 80, 0))

-- STREAMING_CHUNK:Teleport Button Details...
local TeleportBtn = Instance.new("TextButton", BankCard)
TeleportBtn.Size = UDim2.new(0.6, 0, 0, 36)
TeleportBtn.Position = UDim2.new(0.2, 0, 0, 82)
TeleportBtn.BackgroundColor3 = T.buttonPrimary
TeleportBtn.BorderSizePixel = 0
TeleportBtn.Text = "Teleport (Cost: 1 Aurmer)"
TeleportBtn.TextColor3 = T.bodyText
TeleportBtn.TextScaled = true
TeleportBtn.Font = Enum.Font.FredokaOne
Instance.new("UICorner", TeleportBtn).CornerRadius = UDim.new(0, 8)
CollectionService:AddTag(TeleportBtn, "Tutorial_TeleportPiggyBankBtn")
AddButtonJuice(TeleportBtn)
table.insert(VisualElements, TeleportBtn)

local AurmerCard = CreateCard(StoreCardsScaler, 80, 2)

-- STREAMING_CHUNK:Aurmer Card Construction...
local aIcon = Instance.new("ImageLabel", AurmerCard)
aIcon.Size = UDim2.new(0, 50, 0, 50)
aIcon.Position = UDim2.new(0, 12, 0.5, -25)
aIcon.BackgroundTransparency = 1
aIcon.ScaleType = Enum.ScaleType.Fit
aIcon.Image = "rbxassetid://14949477468"

local aName = Instance.new("TextLabel", AurmerCard)
aName.Size = UDim2.new(0.6, -60, 0.35, 0)
aName.Position = UDim2.new(0, 72, 0, 10)
aName.BackgroundTransparency = 1
aName.Text = "AURMER KEY"
aName.TextColor3 = Color3.fromRGB(255, 180, 50)
aName.TextScaled = true
aName.Font = Enum.Font.FredokaOne
aName.TextXAlignment = Enum.TextXAlignment.Left

local aDesc = Instance.new("TextLabel", AurmerCard)
aDesc.Size = UDim2.new(0.6, -60, 0.35, 0)
aDesc.Position = UDim2.new(0, 72, 0.5, 5)
aDesc.BackgroundTransparency = 1
aDesc.Text = "Required to enter the Golden Vault."
aDesc.TextColor3 = Color3.fromRGB(200, 200, 200)
aDesc.TextScaled = true
aDesc.Font = Enum.Font.Gotham
aDesc.TextXAlignment = Enum.TextXAlignment.Left

local aBuy = Instance.new("TextButton", AurmerCard)
aBuy.Size = UDim2.new(0.3, 0, 0.6, 0)
aBuy.Position = UDim2.new(0.65, 0, 0.2, 0)
aBuy.BackgroundColor3 = Color3.fromRGB(255, 150, 50)
aBuy.Text = "99 R$"
aBuy.TextColor3 = Color3.fromRGB(255, 255, 255)
aBuy.TextScaled = true
aBuy.Font = Enum.Font.FredokaOne
Instance.new("UICorner", aBuy).CornerRadius = UDim.new(0, 6)
AddButtonJuice(aBuy)
table.insert(VisualElements, aBuy)

aBuy.MouseButton1Down:Connect(function()
	local productId = (BankConfig.DeveloperProducts and BankConfig.DeveloperProducts.Aurmer and BankConfig.DeveloperProducts.Aurmer.id) or 0
	if productId > 0 then
		MarketplaceService:PromptProductPurchase(player, productId)
	else
		warn("Aurmer Product ID not set in BankConfig!")
	end
end)

CreateSectionLabel("GOLDEN AURAS", 3)

local currentProductOrder = 4
local productLabels = {}

-- STREAMING_CHUNK:Looping through Dev Products...
for key, product in pairs(BankConfig.DeveloperProducts) do
	if key == "Aurmer" then continue end

	local pCard = CreateCard(StoreCardsScaler, 70, currentProductOrder)
	currentProductOrder += 1

	local pIcon = Instance.new("ImageLabel", pCard)
	pIcon.Size = UDim2.new(0, 46, 0, 46)
	pIcon.Position = UDim2.new(0, 12, 0.5, -23)
	pIcon.BackgroundTransparency = 1
	pIcon.ScaleType = Enum.ScaleType.Fit
	pIcon.Image = product.icon or "rbxassetid://14923131909" 

	local pName = Instance.new("TextLabel", pCard)
	pName.Size = UDim2.new(0.6, -55, 0.4, 0)
	pName.Position = UDim2.new(0, 68, 0, 10)
	pName.BackgroundTransparency = 1
	pName.Text = product.name
	pName.TextColor3 = Color3.fromRGB(255, 215, 0)
	pName.TextScaled = true
	pName.Font = Enum.Font.FredokaOne
	pName.TextXAlignment = Enum.TextXAlignment.Left

	local pYield = Instance.new("TextLabel", pCard)
	pYield.Size = UDim2.new(0.6, -55, 0.35, 0)
	pYield.Position = UDim2.new(0, 68, 0.5, 5)
	pYield.BackgroundTransparency = 1
	pYield.Text = "Yields: " .. product.baseAmount .. " GA"
	pYield.TextColor3 = Color3.fromRGB(200, 200, 200)
	pYield.TextScaled = true
	pYield.Font = Enum.Font.Gotham
	pYield.TextXAlignment = Enum.TextXAlignment.Left

	table.insert(productLabels, {label = pYield, base = product.baseAmount})

	local pBuy = Instance.new("TextButton", pCard)
	pBuy.Size = UDim2.new(0.3, 0, 0.7, 0)
	pBuy.Position = UDim2.new(0.65, 0, 0.15, 0)
	pBuy.BackgroundColor3 = Color3.fromRGB(0, 180, 80)
	pBuy.Text = product.priceStr
	pBuy.TextColor3 = Color3.fromRGB(255, 255, 255)
	pBuy.TextScaled = true
	pBuy.Font = Enum.Font.FredokaOne
	Instance.new("UICorner", pBuy).CornerRadius = UDim.new(0, 6)
	AddButtonJuice(pBuy)
	table.insert(VisualElements, pBuy)

	pBuy.MouseButton1Down:Connect(function()
		MarketplaceService:PromptProductPurchase(player, product.id)
	end)


end

CreateSectionLabel("GAMEPASSES", currentProductOrder)
currentProductOrder += 1

-- STREAMING_CHUNK:Looping through Gamepasses...
for key, pass in pairs(BankConfig.Gamepasses) do
	local gCard = CreateCard(StoreCardsScaler, 80, currentProductOrder)
	currentProductOrder += 1

	local gIcon = Instance.new("ImageLabel", gCard)
	gIcon.Size = UDim2.new(0, 50, 0, 50)
	gIcon.Position = UDim2.new(0, 12, 0.5, -25)
	gIcon.BackgroundTransparency = 1
	gIcon.ScaleType = Enum.ScaleType.Fit
	gIcon.Image = pass.icon or "rbxassetid://14923131909" 

	local gName = Instance.new("TextLabel", gCard)
	gName.Size = UDim2.new(0.6, -60, 0.35, 0)
	gName.Position = UDim2.new(0, 72, 0, 10)
	gName.BackgroundTransparency = 1
	gName.Text = pass.name
	gName.TextColor3 = Color3.fromRGB(150, 200, 255)
	gName.TextScaled = true
	gName.Font = Enum.Font.FredokaOne
	gName.TextXAlignment = Enum.TextXAlignment.Left

	local gDesc = Instance.new("TextLabel", gCard)
	gDesc.Size = UDim2.new(0.6, -60, 0.35, 0)
	gDesc.Position = UDim2.new(0, 72, 0.5, 5)
	gDesc.BackgroundTransparency = 1
	gDesc.Text = pass.desc
	gDesc.TextColor3 = Color3.fromRGB(200, 200, 200)
	gDesc.TextScaled = true
	gDesc.Font = Enum.Font.Gotham
	gDesc.TextXAlignment = Enum.TextXAlignment.Left

	local gBuy = Instance.new("TextButton", gCard)
	gBuy.Size = UDim2.new(0.3, 0, 0.6, 0)
	gBuy.Position = UDim2.new(0.65, 0, 0.2, 0)
	gBuy.BackgroundColor3 = Color3.fromRGB(180, 50, 150)
	gBuy.Text = "VIEW"
	gBuy.TextColor3 = Color3.fromRGB(255, 255, 255)
	gBuy.TextScaled = true
	gBuy.Font = Enum.Font.FredokaOne
	Instance.new("UICorner", gBuy).CornerRadius = UDim.new(0, 6)
	AddButtonJuice(gBuy)

	GamepassBuyButtons[key] = gBuy
	table.insert(VisualElements, gBuy)

	gBuy.MouseButton1Down:Connect(function()
		if player:GetAttribute("Pass_" .. key) then return end
		MarketplaceService:PromptGamePassPurchase(player, pass.id)
	end)


end

-- STREAMING_CHUNK:Theme Refresh Method...
local function RefreshLook()
	UITheme.Apply(Panel, "Panel")
	UITheme.Apply(Header, "TitleBar")

	for _, element in ipairs(VisualElements) do
		if element:IsA("Frame") then
			UITheme.Apply(element, "ShopCard")
			UITheme.ApplyShine(element)
		elseif element:IsA("TextButton") then
			UITheme.Apply(element, "Panel")
		end
	end

	UITheme.ApplyShine(Panel)

	local outerStroke = Panel:FindFirstChildWhichIsA("UIStroke")
	if outerStroke then outerStroke.Color = Color3.fromRGB(255, 255, 255) end


end

-- STREAMING_CHUNK:Gamepass Syncing Functionality...
local function SyncGamepasses()
	local hasFasterFill = player:GetAttribute("Pass_FasterFill")
	local hasBonusBreak = player:GetAttribute("Pass_BonusBreak")
	local hasDoubleCash = player:GetAttribute("Pass_DoubleEarnings")

	Badge_FasterFill.Visible = hasFasterFill == true
	Badge_BonusBreak.Visible = hasBonusBreak == true
	Badge_DoubleCash.Visible = hasDoubleCash == true

	local hasAnyPass = hasFasterFill or hasBonusBreak or hasDoubleCash
	if hasAnyPass then
		BankAmountLabel.Size = UDim2.new(0.5, -12, 0, 32)
	else
		BankAmountLabel.Size = UDim2.new(1, -24, 0, 32)
	end

	local function SetOwned(btn)
		if not btn then return end
		btn.Text = "OWNED"
		btn.BackgroundColor3 = Color3.fromRGB(90, 90, 100)
		btn.TextColor3 = Color3.fromRGB(200, 200, 200)
		btn.Interactable = false
	end

	if hasFasterFill then SetOwned(GamepassBuyButtons["FasterFill"]) end
	if hasBonusBreak then SetOwned(GamepassBuyButtons["BonusBreak"]) end
	if hasDoubleCash then SetOwned(GamepassBuyButtons["DoubleEarnings"]) end

	RefreshLook()


end

player:GetAttributeChangedSignal("Pass_FasterFill"):Connect(SyncGamepasses)
player:GetAttributeChangedSignal("Pass_BonusBreak"):Connect(SyncGamepasses)
player:GetAttributeChangedSignal("Pass_DoubleEarnings"):Connect(SyncGamepasses)
SyncGamepasses()

-- STREAMING_CHUNK:Store Open and Close Logic...
local function OpenPanel()
	ForceCloseUI:Fire("StorePanel")

	if shared.PlayUISound then shared.PlayUISound(SoundConfig.UIOpen or "") end
	panelOpen = true
	Panel.Visible = true
	Panel.Size = UDim2.new(0.85, 0, 0, 0)
	TweenService:Create(Panel, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = UDim2.new(0.85, 0, 0.75, 0)}):Play()
	UITheme.SetMenuVisible(true)
end

local function ClosePanel()
	if not panelOpen then return end

	if shared.PlayUISound then shared.PlayUISound(SoundConfig.UIClose or "") end
	panelOpen = false
	TooltipLabel.Visible = false
	TweenService:Create(Panel, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Size = UDim2.new(0.85, 0, 0, 0)}):Play()
	UITheme.SetMenuVisible(false)
	task.delay(0.25, function() Panel.Visible = false end)
end

-- ✨ FIX: Standardized debounces and Advance timing applied
local panelDebounce = false

StoreBtn.MouseButton1Down:Connect(function()
	if panelDebounce then return end
	panelDebounce = true
	task.delay(0.25, function() panelDebounce = false end)

	if panelOpen then 
		if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_CloseStore") then return end
		-- ✨ FIX: Advance BEFORE triggering state changes
		if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
		ClosePanel() 
	else 
		if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_OpenStore") then return end
		-- ✨ FIX: Advance BEFORE triggering state changes
		if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
		OpenPanel() 
	end
end)

CloseBtn.MouseButton1Down:Connect(function()
	if panelDebounce then return end
	panelDebounce = true
	task.delay(0.25, function() panelDebounce = false end)

	if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_CloseStore") then return end

	-- ✨ FIX: Advance BEFORE triggering state changes
	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
	ClosePanel()
end)

ForceCloseUI.Event:Connect(function(exceptionPanel)
	if exceptionPanel ~= "StorePanel" and panelOpen then
		ClosePanel()
	end
end)

-- STREAMING_CHUNK:Teleport Execution and HUD Sync...
local teleportDebounce = false

TeleportBtn.MouseButton1Down:Connect(function()
	if teleportDebounce then return end
	teleportDebounce = true
	task.delay(0.25, function() teleportDebounce = false end)

	if player:GetAttribute("InSpecialArea") then
		if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_TeleportHome") then return end

		-- ✨ FIX: Advance BEFORE triggering network calls and state changes
		if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
		BankActionBridge:Fire({ action = "returnToFarm" })
	else
		if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_TeleportPiggyBank") then return end
		if currentAurmers >= 1 then
			-- ✨ FIX: Advance BEFORE triggering network calls and state changes
			if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
			BankActionBridge:Fire({ action = "teleportToBank" })
		else
			if shared.PlayUISound then shared.PlayUISound(SoundConfig.ErrorBuzz or "") end
		end
	end
end)

UpdateHUDBridge:Connect(function(stats)
	if stats.aurmers ~= nil then currentAurmers = stats.aurmers end
	if stats.piggyBank ~= nil then
		currentBank = stats.piggyBank
		BankAmountLabel.Text = "Stored: " .. NumberFormatter.Format(currentBank) .. " GA"
	end
	if stats.currentArea ~= nil then
		currentArea = stats.currentArea
		for _, data in ipairs(productLabels) do
			local scaledYield = BankConfig.CalculateProductYield(data.base, currentArea)
			data.label.Text = "Yields: " .. NumberFormatter.Format(scaledYield) .. " GA"
		end
	end
end)

BankActionBridge:Connect(function(payload)
	if payload.action == "teleportApproved" then
		player:SetAttribute("InSpecialArea", true)
		TeleportBtn.Text = "Return to Farm"
		TeleportBtn.BackgroundColor3 = T.buttonGreen

		CollectionService:RemoveTag(TeleportBtn, "Tutorial_TeleportPiggyBankBtn")
		CollectionService:AddTag(TeleportBtn, "Tutorial_TeleportHomeBtn")

		ClosePanel()

	elseif payload.action == "returnApproved" then
		player:SetAttribute("InSpecialArea", false)
		TeleportBtn.Text = "Teleport (Cost: 1 Aurmer)"
		TeleportBtn.BackgroundColor3 = T.buttonPrimary

		CollectionService:RemoveTag(TeleportBtn, "Tutorial_TeleportHomeBtn")
		CollectionService:AddTag(TeleportBtn, "Tutorial_TeleportPiggyBankBtn")

		ClosePanel()
	end


end)

task.spawn(function()
	task.wait(2)
	RefreshLook()
end)

-- PrestigeController
-- Location: StarterPlayer > StarterPlayerScripts > PrestigeController

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local AdminConfig       = require(ReplicatedStorage.Modules.AdminConfig)
local PrestigeModule    = require(ReplicatedStorage.Modules.PrestigeModule)
local UITheme           = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UITheme"))
local T                 = UITheme.Get("Custom")
local C                 = require(ReplicatedStorage.Modules.UIConfig)
local Formatter         = require(ReplicatedStorage.Modules.NumberFormatter)
local PoolManager = require(ReplicatedStorage.Modules:WaitForChild("PoolManager"))

-- ✨ BRIDGENET2 UPGRADE
local BridgeNet2        = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))
local UpdateHUDBridge   = BridgeNet2.ClientBridge("UpdateHUD")

local ForceCloseUI = ReplicatedStorage:FindFirstChild("ForceCloseUI") or Instance.new("BindableEvent")
ForceCloseUI.Name = "ForceCloseUI"
ForceCloseUI.Parent = ReplicatedStorage

local EXPONENT     = PrestigeModule.EXPONENT
local COEFFICIENT  = PrestigeModule.COEFFICIENT
local BONUS_PER_SA = PrestigeModule.BONUS_PER_SA

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainHUD   = playerGui:WaitForChild("MainHUD")

local RequestPrestige  = ReplicatedStorage.RemoteEvents:WaitForChild("RequestPrestige")
local PrestigeComplete = ReplicatedStorage.RemoteEvents:WaitForChild("PrestigeComplete")
local PreviewPrestige  = ReplicatedStorage.RemoteEvents:WaitForChild("PreviewPrestige")
local AreaChanged      = ReplicatedStorage.RemoteEvents:WaitForChild("AreaChanged")

local PrestigeReady = Instance.new("BindableEvent")
PrestigeReady.Name   = "PrestigeReady"
PrestigeReady.Parent = ReplicatedStorage

local dialogOpen        = false
local dialogCanPrestige = false
local previewPending    = false

local serverTotalEarned    = 0
local displayedTotalEarned = 0
local ratePerSecond        = 0
local serverSoulAuras      = 0
local displayedRunSA       = 0
local barHighWaterMark     = 0
local hasPrestigedThisArea = false

local PRESTIGE_COLOR_ACTIVE   = Color3.fromRGB(120, 50,  160)
local PRESTIGE_COLOR_DISABLED = Color3.fromRGB(60,  55,  70)
local PRESTIGE_COLOR_PENDING  = Color3.fromRGB(80,  40,  110)
local PRESTIGE_COLOR_USED     = Color3.fromRGB(80,  60,  50)

local function CalcSoulAurasLocal(totalEarned)
	if totalEarned <= 0 then return 0 end
	return math.floor((totalEarned ^ EXPONENT) * COEFFICIENT)
end	
local function GetThreshold(n)
	if n <= 0 then return 0 end
	return (n / COEFFICIENT) ^ (1 / EXPONENT)
end
local function PlayUI(id) if shared.PlayUISound then shared.PlayUISound(id) end end

local function GetButtonColor()
	if hasPrestigedThisArea then return PRESTIGE_COLOR_USED end
	if CalcSoulAurasLocal(serverTotalEarned) > 0 then return PRESTIGE_COLOR_ACTIVE end
	return PRESTIGE_COLOR_DISABLED
end
local function GetButtonText()
	if hasPrestigedThisArea then return "Used" end
	return "Prestige"
end

---------------------------------------------------------------
-- Soul Aura display
---------------------------------------------------------------
local SA_DISPLAY_W = 220
local SA_DISPLAY_H = 90

local SADisplay = Instance.new("Frame")
SADisplay.Name = "SoulAuraDisplay"
SADisplay.Size = UDim2.new(0, SA_DISPLAY_W, 0, SA_DISPLAY_H)
SADisplay.Position = UDim2.new(0, 10, 1, -155)
SADisplay.BackgroundTransparency = 1; SADisplay.ZIndex = 5; SADisplay.Parent = mainHUD

local saScale = Instance.new("UIScale")
saScale.Parent = SADisplay

local SACountLabel = Instance.new("TextLabel")
SACountLabel.Size = UDim2.new(1,0,0,28)
SACountLabel.Position = UDim2.new(0,0,0,0)
SACountLabel.BackgroundTransparency = 1; SACountLabel.Text = "0 Soul Auras"
SACountLabel.TextColor3 = Color3.fromRGB(200,160,255); SACountLabel.TextScaled = true
SACountLabel.Font = T.font; SACountLabel.TextXAlignment = Enum.TextXAlignment.Center
SACountLabel.ZIndex = 6; SACountLabel.Parent = SADisplay

local BarBG = Instance.new("Frame")
BarBG.Size = UDim2.new(1,0,0,12)
BarBG.Position = UDim2.new(0,0,0,32)
BarBG.BackgroundColor3 = Color3.fromRGB(60,30,80); BarBG.BorderSizePixel = 0
BarBG.ZIndex = 6; BarBG.Parent = SADisplay
Instance.new("UICorner", BarBG).CornerRadius = UDim.new(0,5)

local BarFill = Instance.new("Frame")
BarFill.Size = UDim2.new(0,0,1,0)
BarFill.BackgroundColor3 = Color3.fromRGB(255,255,255); BarFill.BorderSizePixel = 0
BarFill.ZIndex = 7; BarFill.Parent = BarBG
Instance.new("UICorner", BarFill).CornerRadius = UDim.new(0,5)

local RunSALabel = Instance.new("TextLabel")
RunSALabel.Size = UDim2.new(1,0,0,18)
RunSALabel.Position = UDim2.new(0,0,0,48)
RunSALabel.BackgroundTransparency = 1; RunSALabel.Text = "earning..."
RunSALabel.TextColor3 = Color3.fromRGB(160,140,180); RunSALabel.TextScaled = true
RunSALabel.Font = T.fontBody; RunSALabel.TextXAlignment = Enum.TextXAlignment.Left
RunSALabel.ZIndex = 6; RunSALabel.Parent = SADisplay

local MultDisplayLabel = Instance.new("TextLabel")
MultDisplayLabel.Size = UDim2.new(1,0,0,18)
MultDisplayLabel.Position = UDim2.new(0,0,0,68)
MultDisplayLabel.BackgroundTransparency = 1; MultDisplayLabel.Text = "+0% earnings bonus"
MultDisplayLabel.TextColor3 = Color3.fromRGB(140,120,170); MultDisplayLabel.TextScaled = true
MultDisplayLabel.Font = T.fontBody; MultDisplayLabel.TextXAlignment = Enum.TextXAlignment.Left
MultDisplayLabel.ZIndex = 6; MultDisplayLabel.Parent = SADisplay

---------------------------------------------------------------
-- Prestige button
---------------------------------------------------------------
local PrestigeButton = Instance.new("TextButton")
PrestigeButton.Name = "PrestigeButton"
PrestigeButton.Size = UDim2.new(0, C.HUD.PrestigeButtonW, 0, C.HUD.PrestigeButtonH)
PrestigeButton.Position = UDim2.new(0, 10, 1, C.HUD.BottomButtonY)
PrestigeButton.BackgroundColor3 = PRESTIGE_COLOR_DISABLED; PrestigeButton.BorderSizePixel = 0
PrestigeButton.Text = "" 
PrestigeButton.ZIndex = 5; PrestigeButton.Parent = mainHUD
CollectionService:AddTag(PrestigeButton, "Tutorial_PrestigeButton")

local prestigeBtnScale = Instance.new("UIScale")
prestigeBtnScale.Parent = PrestigeButton

local SA_DESIGN_SCREEN_HEIGHT = 700

local function UpdateSAScale()
	local screenSize = mainHUD.AbsoluteSize
	if screenSize.Y <= 0 then return end
	local scale = math.clamp(screenSize.Y / SA_DESIGN_SCREEN_HEIGHT, 0.6, 1.1)
	saScale.Scale = scale
	prestigeBtnScale.Scale = scale
end

mainHUD:GetPropertyChangedSignal("AbsoluteSize"):Connect(UpdateSAScale)
UpdateSAScale()

Instance.new("UICorner", PrestigeButton).CornerRadius = UDim.new(0,10)

local prestigeBtnGradient = Instance.new("UIGradient", PrestigeButton)
prestigeBtnGradient.Rotation = 90
prestigeBtnGradient.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.15),
	NumberSequenceKeypoint.new(1, 0),
})

local prestigeBtnGlow = Instance.new("UIStroke", PrestigeButton)
prestigeBtnGlow.Color = Color3.fromRGB(200, 140, 255)
prestigeBtnGlow.Thickness = 1.5
prestigeBtnGlow.Transparency = 0.3

local PrestigeButtonIcon = Instance.new("ImageLabel")
PrestigeButtonIcon.Name = "Icon"
PrestigeButtonIcon.Size = UDim2.new(0, 22, 0, 22)
PrestigeButtonIcon.Position = UDim2.new(0, 10, 0.5, -11)
PrestigeButtonIcon.BackgroundTransparency = 1
PrestigeButtonIcon.ScaleType = Enum.ScaleType.Fit
PrestigeButtonIcon.Image = "rbxassetid://14916846070" -- swap for your prestige/star icon
PrestigeButtonIcon.ZIndex = 6
PrestigeButtonIcon.Parent = PrestigeButton

local PrestigeButtonLabel = Instance.new("TextLabel")
PrestigeButtonLabel.Name = "Label"
PrestigeButtonLabel.Size = UDim2.new(1, -40, 1, 0)
PrestigeButtonLabel.Position = UDim2.new(0, 36, 0, 0)
PrestigeButtonLabel.BackgroundTransparency = 1
PrestigeButtonLabel.Text = "Prestige"
PrestigeButtonLabel.TextColor3 = Color3.fromRGB(255,255,255)
PrestigeButtonLabel.TextScaled = true
PrestigeButtonLabel.Font = T.font
PrestigeButtonLabel.TextXAlignment = Enum.TextXAlignment.Left
PrestigeButtonLabel.ZIndex = 6
PrestigeButtonLabel.Parent = PrestigeButton

---------------------------------------------------------------
-- Prestige dialog
---------------------------------------------------------------
local D=C.Dialog; local DW=D.W; local DH=D.H; local DHH=D.HeaderH; local GAP=D.LabelGap

local Dialog = Instance.new("Frame")
Dialog.Name="PrestigeDialog"
Dialog.Size=UDim2.new(0.88, 0, 0.72, 0)
Dialog.AnchorPoint=Vector2.new(0.5, 0.5)
Dialog.Position=UDim2.new(0.5, 0, 0.5, 0)
Dialog.BackgroundColor3=Color3.fromRGB(25,20,35); Dialog.BorderSizePixel=0
Dialog.Visible=false; Dialog.ZIndex=20; Dialog.Parent=mainHUD
CollectionService:AddTag(Dialog, "Tutorial_PrestigePanel") 
Instance.new("UICorner",Dialog).CornerRadius=UDim.new(0,D.CornerRadius)
local dialogConstraint=Instance.new("UISizeConstraint"); dialogConstraint.MaxSize=Vector2.new(DW,DH); dialogConstraint.Parent=Dialog

local dialogStroke=Instance.new("UIStroke"); dialogStroke.Color=Color3.fromRGB(140,70,200); dialogStroke.Thickness=2; dialogStroke.Parent=Dialog

local DialogContentScaler = Instance.new("Frame")
DialogContentScaler.Name = "ContentScaler"
DialogContentScaler.AnchorPoint = Vector2.new(0.5, 0)
DialogContentScaler.Position = UDim2.new(0.5, 0, 0, 0)
DialogContentScaler.BackgroundTransparency = 1
DialogContentScaler.Parent = Dialog

local dialogContentScale = Instance.new("UIScale")
dialogContentScale.Parent = DialogContentScaler

local DIALOG_DESIGN_WIDTH = 420

local function UpdateDialogScale()
	local realWidth = Dialog.AbsoluteSize.X
	if realWidth <= 0 then return end
	local scale = realWidth / DIALOG_DESIGN_WIDTH
	if scale > 1.05 then scale = 1.05 end
	dialogContentScale.Scale = scale
	DialogContentScaler.Size = UDim2.new(0, DIALOG_DESIGN_WIDTH, 1 / scale, 0)
end

Dialog:GetPropertyChangedSignal("AbsoluteSize"):Connect(UpdateDialogScale)
UpdateDialogScale()

local DialogHeader=Instance.new("Frame"); DialogHeader.Size=UDim2.new(1,0,0,DHH)
DialogHeader.BackgroundColor3=Color3.fromRGB(60,25,90); DialogHeader.BorderSizePixel=0
DialogHeader.ZIndex=21; DialogHeader.Parent=DialogContentScaler
Instance.new("UICorner",DialogHeader).CornerRadius=UDim.new(0,D.CornerRadius)
local DialogTitle=Instance.new("TextLabel"); DialogTitle.Size=UDim2.new(1,-48,1,0); DialogTitle.Position=UDim2.new(0,14,0,0)
DialogTitle.BackgroundTransparency=1; DialogTitle.Text="Prestige?"
DialogTitle.TextColor3=Color3.fromRGB(200,140,255); DialogTitle.TextScaled=true
DialogTitle.Font=T.font; DialogTitle.TextXAlignment=Enum.TextXAlignment.Left; DialogTitle.ZIndex=22; DialogTitle.Parent=DialogHeader

local CBS=D.CloseBtnSize
local DialogCloseBtn=Instance.new("TextButton"); DialogCloseBtn.Size=UDim2.new(0,CBS,0,CBS)
DialogCloseBtn.Position=UDim2.new(1,-(CBS+8),0.5,-CBS/2)
DialogCloseBtn.BackgroundColor3=Color3.fromRGB(180,50,50); DialogCloseBtn.BorderSizePixel=0
DialogCloseBtn.Text="X"; DialogCloseBtn.TextColor3=Color3.fromRGB(255,255,255)
DialogCloseBtn.TextScaled=true; DialogCloseBtn.Font=T.font; DialogCloseBtn.ZIndex=22; DialogCloseBtn.Parent=DialogHeader
CollectionService:AddTag(DialogCloseBtn, "Tutorial_PrestigeCloseBtn") 
Instance.new("UICorner",DialogCloseBtn).CornerRadius=UDim.new(0,5)

local CBH=D.ConfirmBtnH
local ConfirmBtn=Instance.new("TextButton"); ConfirmBtn.Size=UDim2.new(1,-30,0,CBH)
ConfirmBtn.Position=UDim2.new(0,15,1,-(CBH+8))
ConfirmBtn.BackgroundColor3=PRESTIGE_COLOR_ACTIVE; ConfirmBtn.BorderSizePixel=0
ConfirmBtn.Text="Prestige Now"; ConfirmBtn.TextColor3=Color3.fromRGB(255,255,255)
ConfirmBtn.TextScaled=true; ConfirmBtn.Font=T.font; ConfirmBtn.ZIndex=22; ConfirmBtn.Parent=DialogContentScaler
CollectionService:AddTag(ConfirmBtn, "Tutorial_PrestigeConfirm") 
Instance.new("UICorner",ConfirmBtn).CornerRadius=UDim.new(0,8)

local ScrollContainer = Instance.new("ScrollingFrame")
ScrollContainer.Name = "ScrollContainer"
ScrollContainer.Parent = Dialog -- kept OUTSIDE DialogContentScaler for correct mobile touch scrolling
ScrollContainer.BackgroundTransparency = 1
ScrollContainer.BorderSizePixel = 0
ScrollContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
ScrollContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y
ScrollContainer.ScrollBarThickness = 6

local function UpdateDialogScrollBounds()
	local scale = dialogContentScale.Scale
	local scaledTop = (DHH + 5) * scale
	-- simplified equivalent of original (1, 0, 1, -(DHH+CBH+20)) scaled by current content scale:
	ScrollContainer.Position = UDim2.new(0, 0, 0, scaledTop)
	ScrollContainer.Size = UDim2.new(1, 0, 1, -((DHH + CBH + 20) * scale))
end

dialogContentScale:GetPropertyChangedSignal("Scale"):Connect(UpdateDialogScrollBounds)
UpdateDialogScrollBounds()

local DialogCardsScaler = Instance.new("Frame")
DialogCardsScaler.Name = "CardsScaler"
DialogCardsScaler.BackgroundTransparency = 1
DialogCardsScaler.Parent = ScrollContainer

local dialogCardsScale = Instance.new("UIScale")
dialogCardsScale.Parent = DialogCardsScaler

local DIALOG_CARDS_DESIGN_WIDTH = 400

local function UpdateDialogCardsScale()
	local realWidth = ScrollContainer.AbsoluteSize.X
	if realWidth <= 0 then return end
	local scale = realWidth / DIALOG_CARDS_DESIGN_WIDTH
	if scale > 1.05 then scale = 1.05 end
	dialogCardsScale.Scale = scale
	DialogCardsScaler.Size = UDim2.new(0, DIALOG_CARDS_DESIGN_WIDTH, 1 / scale, 0)
end

ScrollContainer:GetPropertyChangedSignal("AbsoluteSize"):Connect(UpdateDialogCardsScale)
UpdateDialogCardsScale()

local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, GAP)
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
listLayout.Parent = DialogCardsScaler

local function MakeLabel(text, color, h, bold, wrapText)
	local l=Instance.new("TextLabel")
	l.Size=UDim2.new(1,-30,0,h)
	l.BackgroundTransparency=1; l.Text=text; l.TextColor3=color
	l.TextScaled=true; l.Font=bold and T.font or T.fontBody
	l.TextXAlignment=Enum.TextXAlignment.Left; l.ZIndex=21
	if wrapText then l.TextWrapped=true end
	l.Parent=DialogCardsScaler
	return l
end

local EarnedLabel  = MakeLabel("You will earn: +0 Soul Auras",  Color3.fromRGB(255,200,100), D.EarnedH, true)
local BoostLabel   = MakeLabel("",                              Color3.fromRGB(80,220,160),  D.BoostH,  true)
local MultLabel    = MakeLabel("Earnings Bonus: +0% -> +0%",    Color3.fromRGB(180,180,200), D.MultH,   false)
local TotalLabel   = MakeLabel("Total Soul Auras: 0",           Color3.fromRGB(140,140,160), D.TotalH,  false)
local HintLabel    = MakeLabel("Each Soul Aura gives +"..string.format("%.0f",BONUS_PER_SA*100).."% earnings!", Color3.fromRGB(200,160,255), D.HintH, true)
local BonusLabel   = MakeLabel("Kickstart Bonus: $50",          Color3.fromRGB(100,220,100), D.BonusH,  true)
local WarningLabel = MakeLabel("This will RESET your currency, upgrades, and all cubes. Soul Auras are permanent.", Color3.fromRGB(255,100,100), D.WarningH, false, true)

---------------------------------------------------------------
-- Dialog logic
---------------------------------------------------------------
local function CloseDialog()
	dialogOpen=false; dialogCanPrestige=false; Dialog.Visible=false; PlayUI("6895079853")
	UITheme.SetMenuVisible(false)
end

local function OpenDialogWithPreview(info)
	if dialogOpen then return end
	ForceCloseUI:Fire("PrestigeDialog")
	UITheme.SetMenuVisible(true)
	if info.hasPrestigedThisArea then
		dialogOpen=true; dialogCanPrestige=false
		EarnedLabel.Text="Already prestiged in this area!"; EarnedLabel.TextColor3=Color3.fromRGB(255,100,100)
		BoostLabel.Text=""
		MultLabel.Text="Travel to a new area to prestige again."; MultLabel.TextColor3=Color3.fromRGB(180,180,200)
		TotalLabel.Text="Total Soul Auras: "..Formatter.Format(info.currentSoulAuras or serverSoulAuras)
		BonusLabel.Text=""
		WarningLabel.Text="One prestige per area keeps progression fair. Keep farming or travel!"
		WarningLabel.TextColor3=Color3.fromRGB(200,180,140)
		ConfirmBtn.Text="USED"; ConfirmBtn.BackgroundColor3=PRESTIGE_COLOR_USED
		Dialog.Visible=true; return
	end
	if (info.newSoulAuras or 0) <= 0 then
		TweenService:Create(PrestigeButton,TweenInfo.new(0.1),{BackgroundColor3=Color3.fromRGB(90,40,120)}):Play()
		task.delay(0.15, function()
			TweenService:Create(PrestigeButton,TweenInfo.new(0.15),{BackgroundColor3=GetButtonColor()}):Play()
		end); return
	end
	dialogCanPrestige=true; dialogOpen=true
	EarnedLabel.Text="You will earn: +"..Formatter.Format(info.newSoulAuras).." Soul Auras"
	EarnedLabel.TextColor3=Color3.fromRGB(255,200,100)
	BoostLabel.Text=info.soulBoostActive and "Soul Boost active - 2x Soul Auras!" or ""
	local currentBonus = (info.currentMultiplier - 1) * 100
	local newBonus = (info.newMultiplier - 1) * 100
	MultLabel.Text = "Earnings Bonus: +"..Formatter.Format(currentBonus).."% -> +"..Formatter.Format(newBonus).."%"
	TotalLabel.Text="Total Soul Auras: "..Formatter.Format(info.currentSoulAuras+info.newSoulAuras)
		.." (was "..Formatter.Format(info.currentSoulAuras)..")"
	BonusLabel.Text="Kickstart Bonus: $"..Formatter.Format(info.prestigeBonus).." to start your next run!"
	WarningLabel.Text="This will RESET your currency, upgrades, and all cubes. Soul Auras are permanent."
	WarningLabel.TextColor3=Color3.fromRGB(255,100,100)
	ConfirmBtn.BackgroundColor3=PRESTIGE_COLOR_ACTIVE; ConfirmBtn.Text="PRESTIGE"
	Dialog.Visible=true
end

local prestigeDebounce = false

PrestigeButton.MouseButton1Down:Connect(function()
	if prestigeDebounce then return end
	prestigeDebounce = true
	task.delay(0.25, function() prestigeDebounce = false end)

	if dialogOpen then
		if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_ClosePrestige") then return end
		-- ✨ FIX: Advance BEFORE triggering state changes
		if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
		CloseDialog()
		return
	end
	if hasPrestigedThisArea then
		ForceCloseUI:Fire("PrestigeDialog")
		dialogOpen=true; dialogCanPrestige=false
		UITheme.SetMenuVisible(true)
		EarnedLabel.Text="Already prestiged in this area!"; EarnedLabel.TextColor3=Color3.fromRGB(255,100,100)
		BoostLabel.Text=""; MultLabel.Text="Travel to a new area to prestige again."
		MultLabel.TextColor3=Color3.fromRGB(180,180,200)
		TotalLabel.Text="Total Soul Auras: "..Formatter.Format(serverSoulAuras)
		BonusLabel.Text=""
		WarningLabel.Text="One prestige per area. Keep farming or travel!"
		WarningLabel.TextColor3=Color3.fromRGB(200,180,140)
		ConfirmBtn.Text="USED"; ConfirmBtn.BackgroundColor3=PRESTIGE_COLOR_USED
		Dialog.Visible=true; return
	end
	if previewPending then return end
	if serverTotalEarned<=0 then
		TweenService:Create(PrestigeButton,TweenInfo.new(0.1),{BackgroundColor3=Color3.fromRGB(90,40,120)}):Play()
		task.delay(0.15, function()
			TweenService:Create(PrestigeButton,TweenInfo.new(0.15),{BackgroundColor3=GetButtonColor()}):Play()
		end); return
	end

	if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_OpenPrestige") then return end

	-- ✨ FIX: Advance BEFORE triggering state changes
	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end

	previewPending=true
	TweenService:Create(PrestigeButton,TweenInfo.new(0.15),{BackgroundColor3=PRESTIGE_COLOR_PENDING}):Play()
	PreviewPrestige:FireServer()

	task.delay(5, function()
		if previewPending then previewPending=false
			TweenService:Create(PrestigeButton,TweenInfo.new(0.2),{BackgroundColor3=GetButtonColor()}):Play()
		end
	end)
end)

PreviewPrestige.OnClientEvent:Connect(function(info)
	previewPending=false
	if info.hasPrestigedThisArea~=nil then hasPrestigedThisArea=info.hasPrestigedThisArea end
	OpenDialogWithPreview(info)
end)

ConfirmBtn.MouseButton1Down:Connect(function()
	if prestigeDebounce then return end
	prestigeDebounce = true
	task.delay(0.25, function() prestigeDebounce = false end)

	if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_PrestigeConfirm") then return end

	if not dialogCanPrestige then CloseDialog(); return end

	-- ✨ FIX: Advance BEFORE triggering state changes
	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
	PoolManager.ClearPools()
	dialogCanPrestige=false; CloseDialog(); RequestPrestige:FireServer()
end)

DialogCloseBtn.MouseButton1Down:Connect(function()
	if prestigeDebounce then return end
	prestigeDebounce = true
	task.delay(0.25, function() prestigeDebounce = false end)

	if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_ClosePrestige") then return end

	-- ✨ FIX: Advance BEFORE triggering state changes
	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end

	previewPending=false; CloseDialog()
	TweenService:Create(PrestigeButton,TweenInfo.new(0.2),{BackgroundColor3=GetButtonColor()}):Play()
end)

---------------------------------------------------------------
-- RenderStepped
---------------------------------------------------------------
local buttonWasEnabled = false
RunService.RenderStepped:Connect(function(dt)
	if ratePerSecond>0 then displayedTotalEarned+=ratePerSecond*dt end

	player:SetAttribute("LiveTotalEarned", displayedTotalEarned)

	local runSA=CalcSoulAurasLocal(displayedTotalEarned)
	SACountLabel.Text=Formatter.Format(serverSoulAuras).." Soul Auras"
	if runSA>0 then
		RunSALabel.Text="+"..Formatter.Format(runSA).." on prestige"
		RunSALabel.TextColor3=hasPrestigedThisArea and Color3.fromRGB(140,120,100) or Color3.fromRGB(255,200,100)
	else
		RunSALabel.Text="earning..."
		RunSALabel.TextColor3=Color3.fromRGB(160,140,180)
	end
	local tc=GetThreshold(runSA); local tn=GetThreshold(runSA+1)
	local range=tn-tc; local progress=range>0 and math.clamp((displayedTotalEarned-tc)/range,0,1) or 0
	if runSA~=displayedRunSA then barHighWaterMark=0; displayedRunSA=runSA end
	if progress>barHighWaterMark then barHighWaterMark=progress end
	BarFill.Size=UDim2.new(barHighWaterMark,0,1,0)
	local canPrestige=CalcSoulAurasLocal(serverTotalEarned)>0 and not hasPrestigedThisArea
	if canPrestige~=buttonWasEnabled then
		buttonWasEnabled=canPrestige
		if canPrestige then PrestigeReady:Fire() end
		if not dialogOpen and not previewPending then
			PrestigeButtonLabel.Text=GetButtonText()
			TweenService:Create(PrestigeButton,TweenInfo.new(0.3),{BackgroundColor3=GetButtonColor()}):Play()
		end
	end
end)

---------------------------------------------------------------
-- ✨ BRIDGENET2 UPDATEHUD EVENT
---------------------------------------------------------------
UpdateHUDBridge:Connect(function(stats)
	if stats.totalEarned ~= nil then
		serverTotalEarned = stats.totalEarned
		-- ✨ THE FIX: Force the bar to reset if the server says 0!
		if serverTotalEarned == 0 then
			displayedTotalEarned = 0
			barHighWaterMark = 0
		elseif serverTotalEarned > displayedTotalEarned then 
			displayedTotalEarned = serverTotalEarned 
		end
	end

	if stats.soulAuras then
		serverSoulAuras=stats.soulAuras
		local mult=1+(serverSoulAuras*BONUS_PER_SA)
		local bonusPercent = (mult - 1) * 100
		MultDisplayLabel.Text = mult > 1 and ("+" .. Formatter.Format(bonusPercent) .. "% earnings bonus") or "+0% earnings bonus"
		MultDisplayLabel.TextColor3=mult>1 and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(255, 255, 255)
	end
	if stats.rate and stats.passiveInterval then
		local interval=stats.passiveInterval
		ratePerSecond=(interval>0 and stats.rate>0) and (stats.rate/interval) or 0
	end
	if stats.hasPrestigedThisArea~=nil then
		hasPrestigedThisArea=stats.hasPrestigedThisArea
		if not dialogOpen and not previewPending then
			PrestigeButtonLabel.Text=GetButtonText()
			TweenService:Create(PrestigeButton,TweenInfo.new(0.2),{BackgroundColor3=GetButtonColor()}):Play()
		end
	end
end)

---------------------------------------------------------------
-- PrestigeComplete
---------------------------------------------------------------
PrestigeComplete.OnClientEvent:Connect(function(info)
	if info.blocked then
		TweenService:Create(PrestigeButton,TweenInfo.new(0.1),{BackgroundColor3=Color3.fromRGB(180,60,60)}):Play()
		task.delay(0.2, function() TweenService:Create(PrestigeButton,TweenInfo.new(0.2),{BackgroundColor3=PRESTIGE_COLOR_USED}):Play() end)
		PrestigeButtonLabel.Text="Used"; hasPrestigedThisArea=true; return
	end
	if info.hasPrestigedThisArea~=nil then hasPrestigedThisArea=info.hasPrestigedThisArea end

	player:SetAttribute("HabitatVisualOffset", 0)

	for _,obj in ipairs(workspace:GetDescendants()) do
		if obj:GetAttribute("AuraCube") then obj:Destroy() end
	end

	-- ✨ THE FIX: Guarantee a massive burst on the very first prestige!
	local burstAmount = 0
	if info.prestigeCount == 1 then
		burstAmount = 15 
	elseif info.newSoulAuras and info.newSoulAuras > 0 then
		burstAmount = math.floor(math.pow(info.newSoulAuras, 0.4) * 1.1)
	elseif info.isPortalEntry then
		burstAmount = 15 
	end

	if burstAmount > 0 then
		burstAmount = math.clamp(burstAmount, 1, 50)
		local burstEvent = ReplicatedStorage.RemoteEvents:FindFirstChild("TutorialBurst")
		if burstEvent then burstEvent:FireServer(burstAmount) end
	end

	displayedTotalEarned=0; serverTotalEarned=0; displayedRunSA=0
	ratePerSecond=0; barHighWaterMark=0; previewPending=false
	serverSoulAuras=info.totalSoulAuras
	local flash=Instance.new("Frame"); flash.Size=UDim2.new(1,0,1,0)
	flash.BackgroundColor3=Color3.fromRGB(180,100,255); flash.BackgroundTransparency=0.2
	flash.ZIndex=50; flash.Parent=mainHUD
	TweenService:Create(flash,TweenInfo.new(0.8,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{BackgroundTransparency=1}):Play()
	task.delay(0.9, function() if flash and flash.Parent then flash:Destroy() end end)
	PrestigeButtonLabel.Text=GetButtonText()
	TweenService:Create(PrestigeButton,TweenInfo.new(0.2),{BackgroundColor3=GetButtonColor()}):Play()
	if not info.isPortalEntry then task.delay(0.3, function() ShowPrestigeResultCard(info) end) end
end)

---------------------------------------------------------------
-- AreaChanged
---------------------------------------------------------------
AreaChanged.OnClientEvent:Connect(function(info)
	hasPrestigedThisArea=info.hasPrestigedThisArea or false
	displayedTotalEarned=0; serverTotalEarned=0; displayedRunSA=0
	ratePerSecond=0; barHighWaterMark=0
	PrestigeButtonLabel.Text=GetButtonText()
	TweenService:Create(PrestigeButton,TweenInfo.new(0.2),{BackgroundColor3=GetButtonColor()}):Play()
end)

---------------------------------------------------------------
-- Result card
---------------------------------------------------------------
function ShowPrestigeResultCard(info)
	local CW=C.Cards.PrestigeCardW; local CH=C.Cards.PrestigeCardH
	local card=Instance.new("Frame"); card.Name="PrestigeResultCard"
	card.Size=UDim2.new(0,CW,0,CH); card.Position=UDim2.new(0.5,-CW/2,0,-CH-10)
	card.BackgroundColor3=Color3.fromRGB(22,16,32); card.BorderSizePixel=0
	card.ZIndex=55; card.Parent=mainHUD
	Instance.new("UICorner",card).CornerRadius=UDim.new(0,C.Cards.CornerRadius)
	local cs=Instance.new("UIStroke"); cs.Color=Color3.fromRGB(180,100,255); cs.Thickness=2; cs.Parent=card

	local function AddLabel(text,color,y,h)
		local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,-20,0,h or 28); l.Position=UDim2.new(0,10,0,y)
		l.BackgroundTransparency=1; l.Text=text; l.TextColor3=color
		l.TextScaled=true; l.Font=T.font; l.ZIndex=56; l.Parent=card
	end

	AddLabel("PRESTIGE "..info.prestigeCount.." COMPLETE",Color3.fromRGB(210,160,255),10,36)
	AddLabel("+"..Formatter.Format(info.newSoulAuras).." Soul Auras  ->  "..Formatter.Format(info.totalSoulAuras).." total",
		Color3.fromRGB(255,210,80),52,30)
	local prevBonus = (info.previousMultiplier - 1) * 100
	local newBonus = (info.newMultiplier - 1) * 100
	AddLabel("Earnings Bonus: +"..Formatter.Format(prevBonus).."% -> +"..Formatter.Format(newBonus).."%",
		Color3.fromRGB(160,220,255),88,24)
	AddLabel("Prestige Bonus: $"..Formatter.Format(info.prestigeBonus).." added to your wallet!",
		Color3.fromRGB(100,230,120),118,24)

	local cont=Instance.new("TextButton"); cont.Size=UDim2.new(0,130,0,36)
	cont.Position=UDim2.new(0.5,-65,1,-50)
	cont.BackgroundColor3=Color3.fromRGB(120,50,160); cont.BorderSizePixel=0
	cont.Text="Continue"; cont.TextColor3=Color3.fromRGB(255,255,255)
	cont.TextScaled=true; cont.Font=T.font; cont.ZIndex=57; cont.Parent=card
	Instance.new("UICorner",cont).CornerRadius=UDim.new(0,8)

	TweenService:Create(card,TweenInfo.new(0.45,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
		{Position=UDim2.new(0.5,-CW/2,0.22,0)}):Play()

	local dismissed=false
	local function Dismiss()
		if dismissed then return end; dismissed=true
		TweenService:Create(card,TweenInfo.new(0.4,Enum.EasingStyle.Quad,Enum.EasingDirection.In),
			{Position=UDim2.new(0.5,-CW/2,0,-CH-10)}):Play()
		task.delay(0.5, function() if card and card.Parent then card:Destroy() end end)
	end
	cont.MouseButton1Down:Connect(Dismiss); task.delay(10,Dismiss)
end

---------------------------------------------------------------
-- UI JUICE
---------------------------------------------------------------
local function AddButtonJuice(btn)
	local scale = btn:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = btn
	end
	btn.MouseEnter:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Sine), {Scale = 1.08}):Play() end)
	btn.MouseLeave:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Sine), {Scale = 1}):Play() end)
	btn.MouseButton1Down:Connect(function() TweenService:Create(scale, TweenInfo.new(0.1, Enum.EasingStyle.Sine), {Scale = 0.9}):Play() end)
	btn.MouseButton1Up:Connect(function() TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), {Scale = 1.08}):Play() end)
end

AddButtonJuice(PrestigeButton)
AddButtonJuice(ConfirmBtn)
AddButtonJuice(DialogCloseBtn)

local function RefreshLook()
	UITheme.Apply(PrestigeButton, "Panel")
	UITheme.Apply(ConfirmBtn, "Panel")
	UITheme.ApplyShine(Dialog)

	local outerStroke = Dialog:FindFirstChildWhichIsA("UIStroke")
	if outerStroke then
		outerStroke.Color = Color3.fromRGB(165, 20, 255)
	end
end

task.wait(2)
RefreshLook()

ForceCloseUI.Event:Connect(function(exceptionPanel)
	if exceptionPanel ~= "PrestigeDialog" and dialogOpen then CloseDialog() end
end)



local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local UpgradeConfig     = require(ReplicatedStorage.Modules:WaitForChild("UpgradeConfig"))
local Formatter         = require(ReplicatedStorage.Modules:WaitForChild("NumberFormatter"))
local EpicUpgradeConfig = require(ReplicatedStorage.Modules:WaitForChild("EpicUpgradeConfig"))
local UIConfig          = require(ReplicatedStorage.Modules:WaitForChild("UIConfig"))
local UITheme           = require(ReplicatedStorage.Modules:WaitForChild("UITheme"))
local T                 = UITheme.Get("Custom")
local SoundConfig       = require(ReplicatedStorage.Modules:WaitForChild("SoundConfig"))

local RemoteEvents        = ReplicatedStorage:WaitForChild("RemoteEvents")
local PurchaseUpgrade     = RemoteEvents:WaitForChild("PurchaseUpgrade", 15)
local UpgradeUpdated      = RemoteEvents:WaitForChild("UpgradeUpdated", 15)
local PurchaseEpicUpgrade = RemoteEvents:WaitForChild("PurchaseEpicUpgrade", 15)
local EpicUpgradeUpdated  = RemoteEvents:WaitForChild("EpicUpgradeUpdated", 15)
local RequestUpgradeState = RemoteEvents:WaitForChild("RequestUpgradeState", 15)

local ForceCloseUI = ReplicatedStorage:FindFirstChild("ForceCloseUI") or Instance.new("BindableEvent")
ForceCloseUI.Name = "ForceCloseUI"
if not ForceCloseUI.Parent then ForceCloseUI.Parent = ReplicatedStorage end

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
shopStroke.Color     = Color3.fromRGB(255, 255, 255)
shopStroke.Thickness = 2

local shopIcon = Instance.new("ImageLabel", ShopButton)
shopIcon.Size               = UDim2.new(0.6, 0, 0.6, 0)
shopIcon.Position           = UDim2.new(0.2, 0, 0.2, 0)
shopIcon.BackgroundTransparency = 1
shopIcon.ScaleType          = Enum.ScaleType.Fit
shopIcon.Image              = UIConfig.Icons.ShopButton or "rbxassetid://14916846070"

local HEADER_H = 44

local ShopPanel = Instance.new("Frame")
ShopPanel.Name              = "ShopPanel"
ShopPanel.Size              = UDim2.new(0.42, 0, 0.85, 0) -- Force 42% width for better tiny screen fit
ShopPanel.AnchorPoint       = Vector2.new(0, 0.5) 
ShopPanel.Position          = UDim2.new(0, -500, 0.5, 0) 
ShopPanel.BackgroundColor3  = T.panelBG
ShopPanel.BorderSizePixel   = 0
ShopPanel.Visible           = false
ShopPanel.ZIndex            = 10
ShopPanel.ClipsDescendants  = true
ShopPanel.Parent            = mainHUD
CollectionService:AddTag(ShopPanel, "Tutorial_ShopPanel") 
Instance.new("UICorner", ShopPanel).CornerRadius = UDim.new(0, 12)

local sizeConstraint = Instance.new("UISizeConstraint")
sizeConstraint.MaxSize = Vector2.new(500, 650) -- Prevents stretching on desktop
sizeConstraint.Parent  = ShopPanel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color     = T.panelStroke
panelStroke.Thickness = 2
panelStroke.Parent    = ShopPanel

local ContentScaler = Instance.new("Frame")
ContentScaler.Name = "ContentScaler"
ContentScaler.AnchorPoint = Vector2.new(0.5, 0)
ContentScaler.Position = UDim2.new(0.5, 0, 0, 0)
ContentScaler.BackgroundTransparency = 1
ContentScaler.Parent = ShopPanel

local shopContentScale = Instance.new("UIScale")
shopContentScale.Parent = ContentScaler

local SHOP_DESIGN_WIDTH = 480

local function UpdateShopScale()
	local realWidth = ShopPanel.AbsoluteSize.X
	if realWidth <= 0 then return end

	local scale = realWidth / SHOP_DESIGN_WIDTH
	if scale > 1.05 then scale = 1.05 end

	shopContentScale.Scale = scale

	-- By locking the width to the design width, and using Scale for the height,
	-- the engine synchronously recalculates the exact dimensions without offset lag.
	ContentScaler.Size = UDim2.new(0, SHOP_DESIGN_WIDTH, 1 / scale, 0)

	-- Dynamically pull the panel tight to the Faded2 menu whenever screen size changes
	if shopOpen then
		local targetX = 65
		if Faded2 then
			-- Calculate position relative to mainHUD to completely bypass safe area/notch absolute offsets
			local relativeX = Faded2.AbsolutePosition.X - mainHUD.AbsolutePosition.X
			targetX = relativeX + Faded2.AbsoluteSize.X + 15
		end
		ShopPanel.Position = UDim2.new(0, targetX, 0.5, 0)
	end
end

ShopPanel:GetPropertyChangedSignal("AbsoluteSize"):Connect(UpdateShopScale)
UpdateShopScale()

local TitleBar = Instance.new("Frame")
TitleBar.Name                 = "TitleBar"
TitleBar.Size                 = UDim2.new(1, 0, 0, HEADER_H)
TitleBar.BackgroundColor3     = T.headerBG
TitleBar.BorderSizePixel      = 0
TitleBar.ZIndex               = 11
TitleBar.ClipsDescendants     = true
TitleBar.BackgroundTransparency = 1
TitleBar.Parent               = ContentScaler
Instance.new("UICorner", TitleBar).CornerRadius = UDim.new(0, 12)

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
CloseButton.Size             = UDim2.new(0, 28, 0, 28)
CloseButton.Position         = UDim2.new(1, -36, 0.5, -14)
CloseButton.BackgroundColor3 = T.buttonRed
CloseButton.BorderSizePixel  = 0
CloseButton.Text             = "X"
CloseButton.TextColor3       = T.headerText
CloseButton.TextScaled       = true
CloseButton.Font             = T.font
CloseButton.ZIndex           = 9999
CloseButton.Parent           = TitleBar
CollectionService:AddTag(CloseButton, "Tutorial_ShopCloseBtn") 
Instance.new("UICorner", CloseButton).CornerRadius = UDim.new(0, 5)

local InfoPopup = Instance.new("Frame")
InfoPopup.Name                 = "InfoPopup"
InfoPopup.Size                 = UDim2.new(0.85, 0, 0.6, 0)
InfoPopup.Position             = UDim2.new(0.5, 0, 0.5, 0)
InfoPopup.AnchorPoint          = Vector2.new(0.5, 0.5)
InfoPopup.BackgroundColor3     = T.cardBG
InfoPopup.BackgroundTransparency = 0
InfoPopup.ZIndex               = 50
InfoPopup.Visible              = false
InfoPopup.Parent               = ContentScaler
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

local activeShopTabText = "Regular Upgrades"

local MainTabBar = Instance.new("Frame")
MainTabBar.Size                 = UDim2.new(1, -20, 0, 85)
MainTabBar.Position             = UDim2.new(0, 10, 0, HEADER_H + 4)
MainTabBar.BackgroundTransparency = 1
MainTabBar.ZIndex               = 11
MainTabBar.Parent               = ContentScaler

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
local TAB_COLOR_ACTIVE = Color3.fromRGB(143, 78, 217)

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

local tabEpic     = MakeMainTab("Epic",     "Epic Research",     UIConfig.Icons.ShopTabEpic or "rbxassetid://14916846070")
local tabUpgrades = MakeMainTab("Upgrades", "Regular Upgrades",  UIConfig.Icons.ShopTabRegular or "rbxassetid://14916846070")
CollectionService:AddTag(tabEpic, "Tutorial_EpicResearchTab")

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
CurrencyLabel.Parent            = ContentScaler

local function MakeScroll(name, yTop)
	local sf = Instance.new("ScrollingFrame")
	sf.Name                 = name
	sf.BackgroundTransparency = 1
	sf.BorderSizePixel      = 0
	sf.ScrollBarThickness   = 4
	sf.ScrollBarImageColor3 = T.subText
	sf.CanvasSize           = UDim2.new(0, 0, 0, 0)
	sf.ZIndex               = 11
	sf.Visible              = false
	sf.ClipsDescendants     = true
	sf.Parent               = ShopPanel

	local function UpdateScrollBounds()
		local scale = shopContentScale.Scale
		local scaledTop = yTop * scale
		sf.Position = UDim2.new(0, 10, 0, scaledTop)
		sf.Size     = UDim2.new(1, -20, 1, -(scaledTop + 10))
	end

	shopContentScale:GetPropertyChangedSignal("Scale"):Connect(UpdateScrollBounds)
	UpdateScrollBounds()

	local pad = Instance.new("UIPadding", sf)
	pad.PaddingTop = UDim.new(0, 5)
	pad.PaddingBottom = UDim.new(0, 15)

	local CardsScaler = Instance.new("Frame")
	CardsScaler.Name = "CardsScaler"
	CardsScaler.BackgroundTransparency = 1
	CardsScaler.Position = UDim2.new(0, 0, 0, 0)
	CardsScaler.Parent = sf

	local cardsScale = Instance.new("UIScale")
	cardsScale.Parent = CardsScaler

	local CARDS_DESIGN_WIDTH = 460

	local function UpdateCardsScale()
		local realWidth = sf.AbsoluteSize.X
		if realWidth <= 0 then return end
		local scale = realWidth / CARDS_DESIGN_WIDTH
		if scale > 1.05 then scale = 1.05 end
		cardsScale.Scale = scale
		CardsScaler.Size = UDim2.new(0, CARDS_DESIGN_WIDTH, 1 / scale, 0)
	end

	sf:GetPropertyChangedSignal("AbsoluteSize"):Connect(UpdateCardsScale)
	UpdateCardsScale()

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.Parent  = CardsScaler

	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		sf.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 25)
	end)
	return sf, CardsScaler
end

local REGULAR_SCROLL_TOP = HEADER_H + 95
local RegularScroll, RegularCardsScaler = MakeScroll("RegularScroll", REGULAR_SCROLL_TOP)
local EPIC_SCROLL_TOP    = HEADER_H + 95
local EpicScroll, EpicCardsScaler       = MakeScroll("EpicScroll", EPIC_SCROLL_TOP)

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

	local nameLabel = Instance.new("TextLabel", card)
	nameLabel.Size              = UDim2.new(1, -119, 0, 20)
	nameLabel.Position          = UDim2.new(0, 58, 0, 11)
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
	buyButton.Size             = UDim2.new(0, 72, 0, 40)
	buyButton.AnchorPoint      = Vector2.new(1, 0.5)
	buyButton.Position         = UDim2.new(1, -8, 0.5, 0)
	buyButton.BackgroundColor3 = isEpic and T.accentPurple or T.buttonGreen
	buyButton.BorderSizePixel  = 0
	buyButton.TextColor3       = T.bodyText
	buyButton.TextScaled       = true
	buyButton.Font             = Enum.Font.FredokaOne
	CollectionService:AddTag(buyButton, "Tutorial_Buy_" .. upgradeId) 

	if isEpic and upgradeId == "epicAuraValue" then
		CollectionService:AddTag(buyButton, "Tutorial_BuyEpic_epicAuraValue")
	end

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

	local function TryBuy()
		if isLoadingData then return false end

		-- FIX: We define a specific action for advancing, and a generic one to fallback to for unlocked purchases
		local specificAction = isEpic and ("Action_BuyEpic_" .. upgradeId) or ("Action_BuyUpgrade_" .. upgradeId)
		local genericAction  = isEpic and "Action_BuyEpic" or "Action_BuyUpgrade"

		local canPerform = true
		if type(shared.TutorialCanPerform) == "function" then
			-- If the specific action matches the step, it flags the advance system
			if shared.TutorialCanPerform(specificAction) then
				canPerform = true
				-- If the step is NOT looking for this specific upgrade, check if generic buying is unlocked
			elseif shared.TutorialCanPerform(genericAction) then
				canPerform = true
			else
				canPerform = false
			end
		end

		if not canPerform then 
			PlayErrorFeedback(buyButton)
			return false 
		end

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
		local specificAction = isEpic and ("Action_BuyEpic_" .. upgradeId) or ("Action_BuyUpgrade_" .. upgradeId)
		local genericAction  = isEpic and "Action_BuyEpic" or "Action_BuyUpgrade"

		local canPerform = true
		if type(shared.TutorialCanPerform) == "function" then
			if shared.TutorialCanPerform(specificAction) then
				canPerform = true
			elseif shared.TutorialCanPerform(genericAction) then
				canPerform = true
			else
				canPerform = false
			end
		end

		if not canPerform then return end

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

-- === DYNAMIC EPIC SORTING ===
local epicUpgradesList = {}
for _, tierData in ipairs(EpicUpgradeConfig.Tiers) do
	for upgradeId, cfg in pairs(tierData.upgrades) do
		table.insert(epicUpgradesList, { id = upgradeId, cfg = cfg })
	end
end

table.sort(epicUpgradesList, function(a, b)
	return (a.cfg.baseCost or 0) < (b.cfg.baseCost or 0)
end)

local epicOrderIndex = 1
for _, item in ipairs(epicUpgradesList) do
	BuildCard(EpicCardsScaler, item.id, item.cfg, true, epicCardRefs)
	local ref = epicCardRefs[item.id]
	if ref and ref.frame then
		ref.baseOrder      = epicOrderIndex
		ref.frame.LayoutOrder = epicOrderIndex
		epicOrderIndex     += 1
		ref.frame.Visible  = false
		ref.frame.Parent   = EpicCardsScaler
		if UITheme and UITheme.Apply then UITheme.Apply(ref.frame, "ShopCard") end
	end
end
-- ==========================

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

		local epicIcon = ref.buyButton:FindFirstChild("EpicImage")
		if epicIcon then epicIcon:Destroy() end
	else
		ref.frame.LayoutOrder      = ref.baseOrder or 0
		ref.buyButton.Text         = "🌟" .. FormatNumber(state.cost)
		ref.buyButton.TextColor3   = (actualAuras < state.cost) and Color3.fromRGB(255, 100, 100) or Color3.fromRGB(255, 255, 255)
		ref.buyButton.BackgroundColor3 = Color3.fromRGB(150, 80, 255)

		local epicIcon = ref.buyButton:FindFirstChild("EpicImage")
		if not epicIcon then
			epicIcon = Instance.new("ImageLabel")
			epicIcon.Name = "EpicImage"
			epicIcon.Size = UDim2.new(0, 20, 0, 20)
			epicIcon.Position = UDim2.new(0, 10, 0.5, -10)
			epicIcon.BackgroundTransparency = 1
			epicIcon.Image = "rbxassetid://0"
			epicIcon.Parent = ref.buyButton
		end
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

	for _, child in ipairs(RegularCardsScaler:GetChildren()) do
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

RebuildRegularShop = function()
	for _, child in ipairs(RegularCardsScaler:GetChildren()) do
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
			header.Parent = RegularCardsScaler

			local sortedUpgrades = {}
			for upgradeId, cfg in pairs(tierData.upgrades) do
				table.insert(sortedUpgrades, { id = upgradeId, cfg = cfg })
			end
			table.sort(sortedUpgrades, function(a, b)
				return (a.cfg.baseCost or 0) < (b.cfg.baseCost or 0)
			end)

			for _, entry in ipairs(sortedUpgrades) do
				local upgradeId, cfg = entry.id, entry.cfg
				BuildCard(RegularCardsScaler, upgradeId, cfg, false, regularCardRefs)
				local ref = regularCardRefs[upgradeId]

				if ref and ref.frame then
					if ref.buyButton then
						ref.buyButton.Name = "Buy_" .. upgradeId
					end
					ref.baseOrder          = listOrder
					ref.frame.LayoutOrder  = listOrder
					listOrder             += 1
					ref.frame.Visible      = true
					ref.frame.Parent       = RegularCardsScaler
					if UITheme and UITheme.Apply then UITheme.Apply(ref.frame, "ShopCard") end
					local myColor = Color3.fromRGB(45, 30, 55)
					ref.frame:SetAttribute("TierColor", myColor)
					ref.frame.BackgroundColor3 = myColor
				end
			end
		else
			local lockedHeader = CreateLockedTierHeader(tierData.tierName or "Tier " .. tierNum, totalUpgradesBought, tierData.unlockRequirement)
			lockedHeader.LayoutOrder = listOrder
			lockedHeader.Parent      = RegularCardsScaler
			break
		end
	end
	UpdateAllRegularCards()
end

RebuildRegularShop()

task.delay(5, function() isLoadingData = false end)

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

local function OpenShop()
	if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_OpenShop") then return end

	ForceCloseUI:Fire("ShopPanel")

	shopOpen = true
	ShopPanel.Visible = true
	SwitchToMainTab(activeMainTab)

	local targetX = 65
	if Faded2 then
		-- Calculate position relative to mainHUD to completely bypass safe area/notch absolute offsets
		local relativeX = Faded2.AbsolutePosition.X - mainHUD.AbsolutePosition.X
		targetX = relativeX + Faded2.AbsoluteSize.X + 15
	end

	ShopPanel.Size = UDim2.new(0.42, 0, 0, 0)
	TweenService:Create(ShopPanel, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.new(0.42, 0, 0.85, 0), Position = UDim2.new(0, targetX, 0.5, 0) }):Play()
	ShopButton.BackgroundColor3 = T.buttonSecondary

	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
end

local function CloseShop()
	if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_CloseShop") then return end

	shopOpen = false
	PlayUI(SoundConfig.UIClose)

	local tween = TweenService:Create(ShopPanel, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.new(0, -500, 0.5, 0) })
	tween:Play()
	tween.Completed:Once(function() if not shopOpen then ShopPanel.Visible = false end end)
	ShopButton.BackgroundColor3 = T.buttonSecondary

	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
end

ShopButton.MouseButton1Down:Connect(function()
	if shopOpen then CloseShop() else OpenShop() end
end)

CloseButton.MouseButton1Down:Connect(CloseShop)

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

if RequestUpgradeState then
	RequestUpgradeState:FireServer()
end

local MenuDismissedEvent = ReplicatedStorage:FindFirstChild("MenuDismissed") or ReplicatedStorage:WaitForChild("MenuDismissed", 15)
if MenuDismissedEvent and RequestUpgradeState then
	MenuDismissedEvent.Event:Connect(function()
		RequestUpgradeState:FireServer()
	end)
end

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
			local cardsScaler = scroll:FindFirstChild("CardsScaler")
			local layout = cardsScaler and cardsScaler:FindFirstChildOfClass("UIListLayout")
			if layout then layout.SortOrder = Enum.SortOrder.LayoutOrder end
		end
	end

	local outerStroke = ShopPanel:FindFirstChildWhichIsA("UIStroke")
	if outerStroke then outerStroke.Color = Color3.fromRGB(255, 255, 255) end
end

task.wait(2)
RefreshLook()

ForceCloseUI.Event:Connect(function(exceptionPanel)
	if exceptionPanel ~= "ShopPanel" and shopOpen then
		CloseShop()
	end
end)
