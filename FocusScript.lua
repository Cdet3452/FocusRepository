-- TutorialController
-- Location: StarterPlayer > StarterPlayerScripts > TutorialController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local GuiService = game:GetService("GuiService")
local TutorialConfig = require(ReplicatedStorage.Modules.TutorialConfig)
local UITheme = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UITheme"))
local T = UITheme.Get("Custom")
local SoundConfig = require(ReplicatedStorage.Modules.SoundConfig)
local Formatter = require(ReplicatedStorage.Modules.NumberFormatter)

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local TutorialStepComplete = RemoteEvents:WaitForChild("TutorialStepComplete", 10)

local BridgeNet2 = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))
local UpdateHUDBridge = BridgeNet2.ClientBridge("UpdateHUD")

local ForceCloseUI = ReplicatedStorage:FindFirstChild("ForceCloseUI")
if not ForceCloseUI then
	ForceCloseUI = Instance.new("BindableEvent")
	ForceCloseUI.Name = "ForceCloseUI"
	ForceCloseUI.Parent = ReplicatedStorage
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = Workspace.CurrentCamera

---------------------------------------------------------------
-- STATE
---------------------------------------------------------------
local currentStepIndex = 1
local tutorialComplete = false
local tutorialActive = false

local activeFallbackStep = nil
local lastDisplayedStepId = nil 

local actionMatchedForAdvance = false 
local isAdvancing = false 

local liveStats = {
	currency = 0,
	totalEarned = 0,
	farmEvaluation = 0,
	soulAuras = 0,
	goldenAuras = 0,
	prestigeCount = 0,
	currentArea = 1,
	totalCubesProduced = 0,
	totalPlatformsShipped = 0,
	totalLegendaryCubes = 0,
	piggyBank = 0,

	pendingAuras = 0,
	habitatCapacity = 99999,
	rate = 0,
	currentMultiplier = 1,

	boostsBought = {},
	boostsUsed = {}
}

local UpdateMultiplier = ReplicatedStorage:WaitForChild("UpdateMultiplier")
UpdateMultiplier.Event:Connect(function(mult)
	liveStats.currentMultiplier = mult
end)

local baselineCubes = 0
local baselineShipped = 0
local baselineGoldenAuras = 0
local baselineBoostsBought = {}
local baselineBoostsUsed = {}

local function GetStepCubes() return math.max(0, liveStats.totalCubesProduced - baselineCubes) end
local function GetStepShipped() return math.max(0, liveStats.totalPlatformsShipped - baselineShipped) end
local function GetStepBoostsBought(id) return math.max(0, (liveStats.boostsBought[id] or 0) - (baselineBoostsBought[id] or 0)) end
local function GetStepBoostsUsed(id) return math.max(0, (liveStats.boostsUsed[id] or 0) - (baselineBoostsUsed[id] or 0)) end

local function GetStepGoldenAuras() 
	local current = player:GetAttribute("LiveGoldenAuras") or liveStats.goldenAuras
	return math.max(0, current - baselineGoldenAuras) 
end

local lockedAura = nil

local function GetActiveAura()
	if lockedAura and lockedAura.Parent and lockedAura.Parent.Name == "AuraHolder" and lockedAura:GetAttribute("AuraCube") then 
		return lockedAura 
	end
	local auraHolder = Workspace:FindFirstChild("AuraHolder")
	if auraHolder then
		local children = auraHolder:GetChildren()
		for i = #children, 1, -1 do
			local child = children[i]
			if child:GetAttribute("AuraCube") then lockedAura = child; return child end
		end
	end
	return nil
end

local currentTrackedPhysicsAura = nil

local function GetActivePhysicsAura()
	if currentTrackedPhysicsAura and currentTrackedPhysicsAura.Parent and not currentTrackedPhysicsAura:GetAttribute("Landed") then
		return currentTrackedPhysicsAura
	end

	local auras = CollectionService:GetTagged("PhysicsAura")
	for _, aura in ipairs(auras) do
		if aura and aura.Parent and not aura:GetAttribute("Landed") then
			currentTrackedPhysicsAura = aura
			return aura
		end
	end

	currentTrackedPhysicsAura = nil
	return nil
end

shared.TutorialRecordAuraSpawned = function() liveStats.totalCubesProduced += 1 end
shared.TutorialRecordShipSent = function() task.delay(4, function() liveStats.totalPlatformsShipped += 1 end) end
shared.TutorialRecordBoostBought = function(id) liveStats.boostsBought[id] = (liveStats.boostsBought[id] or 0) + 1 end
shared.TutorialRecordBoostUsed = function(id) liveStats.boostsUsed[id] = (liveStats.boostsUsed[id] or 0) + 1 end

local tutorialGui = nil
local activePointer = nil
local activeHighlight = nil
local questBanner = nil
local trackingConnection = nil

-- ✨ PANEL AWARENESS
local PANELS_TO_CHECK = {
	"Tutorial_AchievePanel",
	"Tutorial_ShopPanel",
	"Tutorial_PrestigePanel",
	"Tutorial_TravelPanel",
	"Tutorial_BoostShopPanel"
}

local HUD_DIRECTIONS = {
	Tutorial_ClickButton    = "TOP_HIGH",  
	Tutorial_ToggleShipBtn  = "TOP",
	Tutorial_SendShipBtn    = "TOP",
	Tutorial_TravelButton   = "TOP",
	Tutorial_PrestigeButton = "RIGHT", 
	Tutorial_ShopButton     = "RIGHT", 
	Tutorial_BoostMenuBtn   = "RIGHT", 
	Tutorial_AchieveMenuBtn = "RIGHT", 
	Tutorial_LbTab_Top10    = "LEFT",  
	Tutorial_LbTab_AurasGenerated = "LEFT",
	Tutorial_LbTab_MostMoneyMade = "LEFT",
}

---------------------------------------------------------------
-- VISIBILITY & GATING EVALUATION
---------------------------------------------------------------
local function IsVisibleOnScreen(guiObject)
	local current = guiObject
	while current and current ~= game do
		if current:IsA("GuiObject") and not current.Visible then return false
		elseif current:IsA("LayerCollector") and not current.Enabled then return false end
		current = current.Parent
	end
	return true
end

local function GetActivePanel()
	for _, tag in ipairs(PANELS_TO_CHECK) do
		local panel = CollectionService:GetTagged(tag)[1]
		if panel and IsVisibleOnScreen(panel) then return panel end
	end
	return nil
end

local function MeetsStrictGates(step)
	if not step then return false end

	local currentCash = player:GetAttribute("LiveCurrency") or liveStats.currency
	local currentGoldenAuras = player:GetAttribute("LiveGoldenAuras") or liveStats.goldenAuras

	if step.requireHabitatFull and liveStats.pendingAuras < liveStats.habitatCapacity then return false end
	if step.requireRateZero and liveStats.rate > 0.1 then return false end
	if step.reachMultiplier and liveStats.currentMultiplier < step.reachMultiplier then return false end
	if step.requireCubesProduced and GetStepCubes() < step.requireCubesProduced then return false end
	if step.requirePlatformsShipped and GetStepShipped() < step.requirePlatformsShipped then return false end
	if step.requireBoostBought and GetStepBoostsBought(step.requireBoostBought.id) < step.requireBoostBought.count then return false end
	if step.requireBoostUsed and GetStepBoostsUsed(step.requireBoostUsed.id) < step.requireBoostUsed.count then return false end
	if step.requireGoldenAuras and currentGoldenAuras < step.requireGoldenAuras then return false end
	if step.requireStepGoldenAuras and GetStepGoldenAuras() < step.requireStepGoldenAuras then return false end
	if step.requireCurrency and currentCash < step.requireCurrency then return false end
	if step.requireFarmEval and liveStats.farmEvaluation < step.requireFarmEval then return false end
	if step.requireSoulAuras and liveStats.soulAuras < step.requireSoulAuras then return false end
	if step.requirePrestigeCount and liveStats.prestigeCount < step.requirePrestigeCount then return false end
	if step.requireArea and liveStats.currentArea < step.requireArea then return false end
	if step.requireLegendaryCubes and liveStats.totalLegendaryCubes < step.requireLegendaryCubes then return false end
	if step.requirePiggyBankValue and liveStats.piggyBank < step.requirePiggyBankValue then return false end

	return true
end

---------------------------------------------------------------
-- LOGIC-LEVEL GATING (The Soft Lock)
---------------------------------------------------------------
shared.TutorialCanPerform = function(requestedAction)
	actionMatchedForAdvance = false 

	if tutorialComplete or not tutorialActive then return true end

	local activeStep = activeFallbackStep or TutorialConfig.GetStepByIndex(currentStepIndex)
	if not activeStep then return true end

	if activeStep.action == "Action_Wait" and not activeStep.allowClicking then
		if activeStep.duration and activeStep.duration > 0 then
			if shared.PlayUISound then shared.PlayUISound(SoundConfig.ErrorBuzz or "") end
			return false
		end
		if requestedAction == "Action_ClickRedButton" then
			if shared.PlayUISound then shared.PlayUISound(SoundConfig.ErrorBuzz or "") end
			return false
		end
	end

	if not activeStep.action then return true end
	if activeStep.action == requestedAction then actionMatchedForAdvance = true; return true end

	local isPermanentlyUnlocked = false
	for i = 1, currentStepIndex do
		local pastStep = TutorialConfig.GetStepByIndex(i)
		if pastStep then
			if i < currentStepIndex and pastStep.action == requestedAction then
				isPermanentlyUnlocked = true; break
			end
			if pastStep.unlockActions then
				for _, act in ipairs(pastStep.unlockActions) do
					if act == requestedAction then isPermanentlyUnlocked = true; break end
				end
			end
		end
	end
	if isPermanentlyUnlocked then return true end

	if requestedAction == "Action_ClickRedButton" and not MeetsStrictGates(activeStep) then return true end
	if shared.PlayUISound then shared.PlayUISound(SoundConfig.ErrorBuzz or "") end
	return false
end

---------------------------------------------------------------
-- INITIALIZATION & UI
---------------------------------------------------------------
local function InitTutorialUI()
	tutorialGui = Instance.new("ScreenGui"); tutorialGui.Name = "TutorialOverlays"; tutorialGui.DisplayOrder = 1000 
	tutorialGui.IgnoreGuiInset = false 
	tutorialGui.ResetOnSpawn = false; tutorialGui.Parent = playerGui

	-- ✨ THE FIX: We set AnchorPoint to 0.5, 0.5 so it expands evenly from the true center of the object!
	activeHighlight = Instance.new("Frame"); activeHighlight.Name = "TutorialHighlight"
	activeHighlight.AnchorPoint = Vector2.new(0.5, 0.5) 
	activeHighlight.BackgroundColor3 = Color3.new(1, 1, 1); activeHighlight.BackgroundTransparency = 1 
	activeHighlight.Interactable = false; activeHighlight.Active = false; activeHighlight.Visible = false
	activeHighlight.ZIndex = 99; activeHighlight.Parent = tutorialGui

	local highlightStroke = Instance.new("UIStroke", activeHighlight)
	highlightStroke.Color = TutorialConfig.DefaultColor; highlightStroke.Thickness = 3; highlightStroke.Transparency = 0.2
	Instance.new("UICorner", activeHighlight).CornerRadius = UDim.new(0, 8)
	TweenService:Create(highlightStroke, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {Transparency = 0.8}):Play()

	activePointer = Instance.new("ImageLabel"); activePointer.Name = "GhostHand"
	activePointer.Size = TutorialConfig.PointerSize; activePointer.BackgroundTransparency = 1
	activePointer.Image = TutorialConfig.PointerImage; activePointer.AnchorPoint = Vector2.new(0.5, 0.5)
	activePointer.Visible = false; activePointer.Active = false; activePointer.ZIndex = 100; activePointer.Parent = tutorialGui

	questBanner = Instance.new("Frame"); questBanner.Name = "QuestBanner"
	questBanner.Size = UDim2.new(0, 650, 0, 130); questBanner.AnchorPoint = Vector2.new(0.5, 0)
	questBanner.Position = UDim2.new(0.5, 0, 0, -250); questBanner.BackgroundColor3 = T.panelBG or Color3.fromRGB(20, 20, 30)
	questBanner.BorderSizePixel = 0; questBanner.Visible = false; questBanner.Active = false; questBanner.Parent = tutorialGui
	Instance.new("UICorner", questBanner).CornerRadius = UDim.new(0, 12)

	local sizeConstraint = Instance.new("UISizeConstraint", questBanner)
	sizeConstraint.MaxSize = Vector2.new(650, 130); sizeConstraint.MinSize = Vector2.new(280, 85)
	Instance.new("UIScale", questBanner)

	local bgGrad = Instance.new("UIGradient", questBanner)
	bgGrad.Rotation = 90
	bgGrad.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0.95) })

	local stroke = Instance.new("UIStroke", questBanner); stroke.Name = "BannerStroke"
	stroke.Color = TutorialConfig.DefaultColor; stroke.Thickness = 2.5; stroke.Transparency = 0.1
	local strokeGrad = Instance.new("UIGradient", stroke); strokeGrad.Name = "StrokeGradient"; strokeGrad.Rotation = 45

	local iconFrame = Instance.new("Frame", questBanner); iconFrame.Name = "IconFrame"
	iconFrame.Size = UDim2.new(0, 72, 0, 72); iconFrame.AnchorPoint = Vector2.new(0, 0.5)
	iconFrame.Position = UDim2.new(0, 14, 0.5, 0); iconFrame.BackgroundColor3 = TutorialConfig.DefaultColor
	iconFrame.BackgroundTransparency = 0.85; iconFrame.Active = false
	Instance.new("UICorner", iconFrame).CornerRadius = UDim.new(0, 12)
	Instance.new("UIStroke", iconFrame).Color = TutorialConfig.DefaultColor

	local icon = Instance.new("ImageLabel", iconFrame); icon.Name = "IconImage"
	icon.Size = UDim2.new(0.65, 0, 0.65, 0); icon.Position = UDim2.new(0.175, 0, 0.175, 0)
	icon.BackgroundTransparency = 1; icon.Image = TutorialConfig.DefaultIcon
	icon.ScaleType = Enum.ScaleType.Fit; icon.Active = false

	local title = Instance.new("TextLabel", questBanner); title.Name = "Title"
	title.Size = UDim2.new(1, -100, 0.35, 0); title.Position = UDim2.new(0, 96, 0.08, 0)
	title.BackgroundTransparency = 1; title.TextColor3 = TutorialConfig.DefaultColor
	title.TextScaled = true; title.Font = Enum.Font.FredokaOne; title.TextXAlignment = Enum.TextXAlignment.Left; title.Active = false
	local titleConstraint = Instance.new("UITextSizeConstraint", title); titleConstraint.MaxTextSize = 34; titleConstraint.MinTextSize = 10

	local titleShadow = title:Clone(); titleShadow.Name = "TitleShadow"; titleShadow.TextColor3 = Color3.new(0, 0, 0)
	titleShadow.TextTransparency = 0.6; titleShadow.Position = UDim2.new(0, 98, 0.08, 2)
	titleShadow.ZIndex = title.ZIndex - 1; titleShadow.Parent = questBanner

	local body = Instance.new("TextLabel", questBanner); body.Name = "Body"
	body.Size = UDim2.new(1, -100, 0.5, 0); body.Position = UDim2.new(0, 96, 0.45, 0)
	body.BackgroundTransparency = 1; body.TextColor3 = T.bodyText or Color3.fromRGB(230, 230, 240)
	body.TextWrapped = true; body.TextScaled = true; body.RichText = true
	body.Font = Enum.Font.GothamMedium; body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top; body.Active = false
	local bodyConstraint = Instance.new("UITextSizeConstraint", body); bodyConstraint.MaxTextSize = 22; bodyConstraint.MinTextSize = 8
end

-- ✨ NEW HELPER: Gets the 100% mathematically true bounding box on the screen, ignoring Roblox's quirks
local function GetTrueBoundingBox(guiObj)
	local absPos = guiObj.AbsolutePosition
	local absSize = guiObj.AbsoluteSize

	local scaleObj = guiObj:FindFirstChildOfClass("UIScale")
	local s = scaleObj and scaleObj.Scale or 1

	local anchor = guiObj.AnchorPoint
	local anchorPxX = absPos.X + (absSize.X * anchor.X)
	local anchorPxY = absPos.Y + (absSize.Y * anchor.Y)

	local tgtW = absSize.X * s
	local tgtH = absSize.Y * s
	local tgtX = anchorPxX - (tgtW * anchor.X)
	local tgtY = anchorPxY - (tgtH * anchor.Y)

	local parentGui = guiObj:FindFirstAncestorOfClass("ScreenGui")
	if parentGui and not parentGui.IgnoreGuiInset then
		local inset = game:GetService("GuiService"):GetGuiInset()
		tgtX = tgtX + inset.X
		tgtY = tgtY + inset.Y
	end

	return tgtX, tgtY, tgtW, tgtH
end

local function AutoScrollToTarget(target)
	local scrollFrame = target:FindFirstAncestorOfClass("ScrollingFrame")
	if scrollFrame then
		local tX, tY, tW, tH = GetTrueBoundingBox(target)
		local sX, sY, sW, sH = GetTrueBoundingBox(scrollFrame)

		local relativeY = (tY - sY) + scrollFrame.CanvasPosition.Y
		local targetCanvasY = relativeY - (scrollFrame.AbsoluteSize.Y / 2) + (tH / 2)
		local maxScroll = math.max(0, scrollFrame.AbsoluteCanvasSize.Y - scrollFrame.AbsoluteSize.Y)

		TweenService:Create(scrollFrame, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CanvasPosition = Vector2.new(scrollFrame.CanvasPosition.X, math.clamp(targetCanvasY, 0, maxScroll))
		}):Play()
	end
end

local function HideBanner()
	if not questBanner or not questBanner.Visible then return end
	TweenService:Create(questBanner, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.new(0.5, 0, 0, -250) }):Play()
	task.delay(0.4, function() if lastDisplayedStepId == nil then questBanner.Visible = false end end)
end

local function GetBannerTarget()
	local activePanel = GetActivePanel()
	local screenW = camera.ViewportSize.X
	local screenH = camera.ViewportSize.Y

	local isMobile   = screenW <= 850 or screenH <= 600
	local isPortrait = screenH > screenW * 1.1   -- ✨ NEW: portrait detection

	-- ✨ FIXED: tighter HUD estimates for portrait vs landscape
	local leftHudWidth  = isPortrait and 70  or 100
	local rightHudWidth = isPortrait and 160 or 270
	local availableCenterWidth = math.max(200, screenW - leftHudWidth - rightHudWidth)

	local baseBannerWidth = 650
	local targetScale = 1.0
	if availableCenterWidth < baseBannerWidth then
		targetScale = math.clamp(availableCenterWidth / baseBannerWidth, 0.42, 0.9)
	end

	if activePanel then
		local panelName = activePanel.Name
		local bannerW = baseBannerWidth * targetScale

		if panelName == "ShopPanel" then
			if isMobile then
				return UDim2.new(0.5, 0, 1, -120), targetScale
			else
				local panelRightEdge = activePanel.AbsolutePosition.X + activePanel.AbsoluteSize.X
				local targetPixelX = panelRightEdge + 35 + (bannerW / 2)
				targetPixelX = math.min(targetPixelX, screenW - (bannerW / 2) - 10)
				return UDim2.new(0, targetPixelX, 0, math.max(15, activePanel.AbsolutePosition.Y)), targetScale
			end

		elseif panelName == "BoostShopPanel" then
			return UDim2.new(0.5, 0, 0, isMobile and 8 or 15), targetScale

		elseif panelName == "TravelPanel" or panelName == "PrestigePanel" then
			return UDim2.new(0.5, 0, 0, isMobile and 8 or 45), targetScale

		elseif panelName == "AchievementPanel" then
			if screenH < 850 then
				return UDim2.new(0.5, 0, 1, -110), targetScale
			else
				return UDim2.new(0.5, 0, 1, -300), targetScale
			end

		else
			return UDim2.new(0.5, 0, 0, isMobile and 8 or 15), targetScale
		end
	else
		-- ✨ FIXED no-panel fallback: use small absolute offset instead of scale %
		-- so it hugs the top of the safe area on every screen size/orientation
		if isPortrait then
			return UDim2.new(0.5, 0, 0, 0), targetScale
		elseif isMobile then
			return UDim2.new(0.5, 0, 0, 0), targetScale
		else
			return UDim2.new(0.5, 0, 0, 4), targetScale
		end
	end
end

local function ShowBanner(step)
	local stepColor = step.color or TutorialConfig.DefaultColor
	questBanner.Title.Text = step.bannerTitle; questBanner.TitleShadow.Text = step.bannerTitle; questBanner.Body.Text = step.bannerBody
	questBanner.Title.TextColor3 = stepColor; questBanner.IconFrame.BackgroundColor3 = stepColor; questBanner.IconFrame.UIStroke.Color = stepColor
	questBanner.IconFrame.IconImage.Image = step.icon or TutorialConfig.DefaultIcon

	if activeHighlight then
		local stroke = activeHighlight:FindFirstChildOfClass("UIStroke")
		if stroke then stroke.Color = stepColor end
	end

	local strokeGrad = questBanner.BannerStroke:FindFirstChild("StrokeGradient")
	if strokeGrad then
		strokeGrad.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)), ColorSequenceKeypoint.new(1, stepColor) })
	end

	local targetPos, targetScale = GetBannerTarget()

	if not questBanner.Visible then
		questBanner.Position = UDim2.new(0.5, 0, 0, -250); questBanner.Visible = true
		TweenService:Create(questBanner, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = targetPos }):Play()
	else
		TweenService:Create(questBanner, TweenInfo.new(0.4, Enum.EasingStyle.Sine), { Position = targetPos }):Play()
	end

	local scaleObj = questBanner:FindFirstChildOfClass("UIScale")
	if scaleObj then
		TweenService:Create(scaleObj, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = targetScale }):Play()
	end

	if shared.PlayUISound then shared.PlayUISound(SoundConfig.TutorialHint or "6895079853") end
end

-- Corrects AbsolutePosition to TutorialOverlays screen space (IgnoreGuiInset=true)
local function GetScreenPos(guiObject)
	local pos  = guiObject.AbsolutePosition
	local sGui = guiObject:FindFirstAncestorOfClass("ScreenGui")
	if sGui and not sGui.IgnoreGuiInset then
		local inset = GuiService:GetGuiInset()  -- returns topLeft, bottomRight
		return Vector2.new(pos.X + inset.X, pos.Y + inset.Y)
	end
	return pos
end

---------------------------------------------------------------
-- CORE LOOP (RenderStepped)
---------------------------------------------------------------
local function StartTrackingLoop()
	if trackingConnection then trackingConnection:Disconnect() end

	local bounceTime = 0
	local isAutoScrolling = false

	trackingConnection = RunService.RenderStepped:Connect(function(dt)
		local allLockedTags = {}; local currentUnlockedTags = {}

		for i, stp in ipairs(TutorialConfig.Steps) do
			if stp.unlockTags then
				for _, tag in ipairs(stp.unlockTags) do
					allLockedTags[tag] = true
					if tutorialComplete or i <= currentStepIndex then currentUnlockedTags[tag] = true end
				end
			end
		end

		for tag, _ in pairs(allLockedTags) do
			local isUnlocked = currentUnlockedTags[tag] or tutorialComplete
			local elements = CollectionService:GetTagged(tag)
			for _, el in ipairs(elements) do
				local overlay = el:FindFirstChild("TutorialLockOverlay")
				if not isUnlocked then
					if not overlay then
						overlay = Instance.new("TextButton"); overlay.Name = "TutorialLockOverlay"; overlay.Size = UDim2.new(1, 0, 1, 0)
						overlay.Position = UDim2.new(0, 0, 0, 0); overlay.AnchorPoint = Vector2.new(0, 0)
						overlay.BackgroundColor3 = Color3.fromRGB(15, 15, 20); overlay.BackgroundTransparency = 0.5
						overlay.ZIndex = 99998; overlay.Text = ""; overlay.AutoButtonColor = false

						local corner = el:FindFirstChildOfClass("UICorner")
						if corner then corner:Clone().Parent = overlay end

						local icon = Instance.new("ImageLabel"); icon.Name = "PadlockIcon"; icon.Size = UDim2.new(0, 24, 0, 24)
						icon.AnchorPoint = Vector2.new(0.5, 0.5); icon.Position = UDim2.new(0.5, 0, 0.5, 0)
						icon.BackgroundTransparency = 1; icon.Image = "rbxassetid://7059346373"; icon.ImageColor3 = Color3.fromRGB(255, 255, 255)
						icon.ScaleType = Enum.ScaleType.Fit; icon.ZIndex = 99999; icon.Parent = overlay

						overlay.Parent = el
					end
				else
					if overlay then overlay:Destroy() end
				end
			end
		end

		if tutorialComplete then 
			if activePointer then activePointer.Visible = false end
			if activeHighlight then activeHighlight.Visible = false end
			HideBanner()
			if trackingConnection then trackingConnection:Disconnect() end
			return 
		end

		bounceTime += dt * 5
		local bounceOffset = math.abs(math.sin(bounceTime)) * 15

		-- ✨ VIEWPORT-RELATIVE SCALING (replaces the old fixed-pixel block)
		local screenW = camera.ViewportSize.X
		local screenH = camera.ViewportSize.Y

		-- smooth breakpoint instead of a binary 0.55 / 1.0 flip
		local refSize        = math.max(screenW, screenH)          -- longest axis
		local pointerScaleFactor = math.clamp(refSize / 1080, 0.45, 1.3)

		local basePointerSize    = TutorialConfig.PointerSize or UDim2.new(0, 80, 0, 80)
		local scaledPointerW     = basePointerSize.X.Offset * pointerScaleFactor
		local scaledPointerH     = basePointerSize.Y.Offset * pointerScaleFactor

		activePointer.Size = UDim2.new(
			basePointerSize.X.Scale, scaledPointerW,
			basePointerSize.Y.Scale, scaledPointerH
		)

		-- bounce amplitude: ~2 % of the short axis so it always feels proportional
		local bounceAmp    = screenH * 0.022
		local bounceOffset = math.abs(math.sin(bounceTime)) * bounceAmp

		local isMobileView = screenW <= 850 or screenH <= 600

		local step = activeFallbackStep or TutorialConfig.GetStepByIndex(currentStepIndex)
		if not step then return end

		if not activeFallbackStep then
			if not MeetsStrictGates(step) then
				if step.fallbackStepId then
					local foundFallback = TutorialConfig.GetStepById(step.fallbackStepId)
					if foundFallback then activeFallbackStep = foundFallback; step = activeFallbackStep end
				end
			end
		else
			local originalStep = TutorialConfig.GetStepByIndex(currentStepIndex)
			if originalStep and MeetsStrictGates(originalStep) then
				activeFallbackStep = nil; step = originalStep
			end
		end

		if not step then return end 

		if step.bannerTitle then
			if lastDisplayedStepId ~= step.id then
				lastDisplayedStepId = step.id
				ShowBanner(step)
				if step.cameraTarget or step.cameraTrackMode then ForceCloseUI:Fire() end
			end

			if questBanner and questBanner.Visible then
				local targetPos, targetScale = GetBannerTarget()
				questBanner.Position = questBanner.Position:Lerp(targetPos, 0.15)
				local scaleObj = questBanner:FindFirstChildOfClass("UIScale")
				if scaleObj then
					scaleObj.Scale = scaleObj.Scale + ((targetScale - scaleObj.Scale) * 0.15)
				end
			end

			local progressText = ""
			local checkStep = activeFallbackStep and TutorialConfig.GetStepByIndex(currentStepIndex) or step

			if checkStep.requireCubesProduced then
				local capCubes = math.min(GetStepCubes(), checkStep.requireCubesProduced)
				progressText = "\n<b><font color='rgb(100, 255, 100)'>Progress: " .. capCubes .. " / " .. checkStep.requireCubesProduced .. "</font></b>"
			elseif checkStep.requirePlatformsShipped then
				local capShipped = math.min(GetStepShipped(), checkStep.requirePlatformsShipped)
				progressText = "\n<b><font color='rgb(100, 255, 100)'>Progress: " .. capShipped .. " / " .. checkStep.requirePlatformsShipped .. "</font></b>"
			elseif checkStep.requireCurrency then
				local currentCash = player:GetAttribute("LiveCurrency") or liveStats.currency
				local capCash = math.min(math.floor(currentCash), checkStep.requireCurrency)
				progressText = "\n<b><font color='rgb(100, 255, 100)'>Progress: $" .. capCash .. " / $" .. checkStep.requireCurrency .. "</font></b>"
			elseif checkStep.reachMultiplier then
				local currentMult = liveStats.currentMultiplier or 1
				local capMult = math.min(currentMult, checkStep.reachMultiplier)
				progressText = "\n<b><font color='rgb(255, 255, 50)'>Progress: " .. string.format("%.1f", capMult) .. "x / " .. string.format("%.1f", checkStep.reachMultiplier) .. "x</font></b>"
			elseif checkStep.requireStepGoldenAuras then
				local capGA = math.min(GetStepGoldenAuras(), checkStep.requireStepGoldenAuras)
				progressText = "\n<b><font color='rgb(255, 215, 0)'>Progress: " .. capGA .. " / " .. checkStep.requireStepGoldenAuras .. " GA</font></b>"
			elseif checkStep.requireFarmEval then
				local capFE = math.min(math.floor(liveStats.farmEvaluation), checkStep.requireFarmEval)
				progressText = "\n<b><font color='rgb(100, 255, 100)'>Progress: $" .. Formatter.Format(capFE) .. " / $" .. Formatter.Format(checkStep.requireFarmEval) .. "</font></b>"
			elseif checkStep.requireBoostBought then
				local cap = math.min(GetStepBoostsBought(checkStep.requireBoostBought.id), checkStep.requireBoostBought.count)
				progressText = "\n<b><font color='rgb(100, 255, 100)'>Progress: " .. cap .. " / " .. checkStep.requireBoostBought.count .. "</font></b>"
			elseif checkStep.requireBoostUsed then
				local cap = math.min(GetStepBoostsUsed(checkStep.requireBoostUsed.id), checkStep.requireBoostUsed.count)
				progressText = "\n<b><font color='rgb(100, 255, 100)'>Progress: " .. cap .. " / " .. checkStep.requireBoostUsed.count .. "</font></b>"
			end
			questBanner.Body.Text = step.bannerBody .. progressText

		else
			if lastDisplayedStepId ~= nil then lastDisplayedStepId = nil; HideBanner() end
		end

		local targetToTrack2D = nil
		local targetToTrack3D = nil

		if step.target3D then
			if string.find(string.lower(step.target3D), "aura") then
				local aura = GetActiveAura()
				if aura then targetToTrack3D = aura:IsA("Model") and aura:GetPivot().Position or aura.Position end
			else
				local obj = CollectionService:GetTagged(step.target3D)[1]
				if obj then targetToTrack3D = obj:IsA("Model") and obj:GetPivot().Position or obj.Position end
			end
		elseif step.targetTag then
			if step.menuTag and step.menuOpenBtnTag then
				local menuInstances = CollectionService:GetTagged(step.menuTag)
				local menuIsOpen = false
				for _, menu in ipairs(menuInstances) do
					if IsVisibleOnScreen(menu) then menuIsOpen = true; break end
				end
				targetToTrack2D = menuIsOpen and CollectionService:GetTagged(step.targetTag)[1] or CollectionService:GetTagged(step.menuOpenBtnTag)[1]
			else
				targetToTrack2D = CollectionService:GetTagged(step.targetTag)[1]
			end
		end

		if targetToTrack3D then
			local screenPos, onScreen = camera:WorldToViewportPoint(targetToTrack3D)
			if onScreen and screenPos.Z > 0 then
				activePointer.Visible = true; activeHighlight.Visible = false 
				activePointer.Rotation = 0
				activePointer.Position = UDim2.new(0, screenPos.X, 0, screenPos.Y - (activePointer.Size.Y.Offset / 2) - bounceOffset)
			else
				activePointer.Visible = false; activeHighlight.Visible = false
			end

		elseif targetToTrack2D and targetToTrack2D:IsA("GuiObject") then

			-- ✨ DYNAMIC BUTTON RESOLVER
			-- Walks the tagged element (or its parent) to find the real pressable button,
			-- handles elements created after the tutorial started.
			local function ResolveButton(obj)
				if obj:IsA("GuiButton") and obj.AbsoluteSize.Magnitude > 1 then return obj end
				-- search children
				local b = obj:FindFirstChildWhichIsA("TextButton", true)
					or obj:FindFirstChildWhichIsA("ImageButton", true)
				if b and b.AbsoluteSize.Magnitude > 1 then return b end
				-- walk up one level (wrapper frames)
				if obj.Parent and obj.Parent:IsA("GuiObject") then
					b = obj.Parent:FindFirstChildWhichIsA("TextButton", true)
						or obj.Parent:FindFirstChildWhichIsA("ImageButton", true)
					if b and b.AbsoluteSize.Magnitude > 1 then return b end
				end
				return obj  -- fallback: return as-is; if size is 0 we hide below
			end

			targetToTrack2D = ResolveButton(targetToTrack2D)
			-- 🔍 TEMP DEBUG — remove after confirming
			if step.targetTag == "Tutorial_ClickButton" then
				print("[TutorialDebug] Resolved to:", targetToTrack2D.Name, 
					"| Class:", targetToTrack2D.ClassName,
					"| Size:", targetToTrack2D.AbsoluteSize,
					"| Pos:", targetToTrack2D.AbsolutePosition)
			end
			-- Guard: if the element hasn't rendered yet (size == 0) just hide & wait
			if targetToTrack2D.AbsoluteSize.Magnitude <= 1 or not IsVisibleOnScreen(targetToTrack2D) then
				activePointer.Visible = false
				activeHighlight.Visible = false
			else
				activePointer.Visible   = true
				activeHighlight.Visible = true

				local tgtW = targetToTrack2D.AbsoluteSize.X
				local tgtH = targetToTrack2D.AbsoluteSize.Y
				local corrected = GetScreenPos(targetToTrack2D)
				-- REVERT TO THIS (remove GetScreenPos):
				local tgtX = targetToTrack2D.AbsolutePosition.X
				local tgtY = targetToTrack2D.AbsolutePosition.Y

				-- ✨ UIScale correction (same logic as before, kept intact)
				local scaleObj = targetToTrack2D:FindFirstChildOfClass("UIScale")
				if scaleObj and scaleObj.Scale ~= 1 then
					local s      = scaleObj.Scale
					local anchor = targetToTrack2D.AnchorPoint
					local anchorPxX = tgtX + (tgtW * anchor.X)
					local anchorPxY = tgtY + (tgtH * anchor.Y)
					tgtW = tgtW * s;  tgtH = tgtH * s
					tgtX = anchorPxX - (tgtW * anchor.X)
					tgtY = anchorPxY - (tgtH * anchor.Y)
				end

				local centerX = tgtX + (tgtW / 2)
				local centerY = tgtY + (tgtH / 2)

				-- ✨ VIEWPORT-RELATIVE OFFSETS (replaces all hard-coded pixel gaps)
				local padding      = screenH * 0.018   -- was 15 px
				local topHighExtra = screenH * 0.065   -- was 45 px  (TOP_HIGH extra lift)

				local pointerW = scaledPointerW
				local pointerH = scaledPointerH

				-- direction logic (unchanged)
				local pX, pY, rot
				local dir = "BOTTOM"
				local tagCheck = step.targetTag or ""

				if HUD_DIRECTIONS[tagCheck] then
					dir = HUD_DIRECTIONS[tagCheck]
				elseif tagCheck:match("Tutorial_AchieveRow") or tagCheck:match("Tutorial_BuyBoost") or tagCheck:match("Tutorial_UseBoost") then
					dir = "RIGHT"
				else
					if centerX < screenW * 0.3 then        dir = "RIGHT"
					elseif centerX > screenW * 0.7 then    dir = "LEFT"
					elseif centerY > screenH * 0.5 then    dir = "TOP"
					else                                   dir = "BOTTOM" end
				end

				if dir == "RIGHT" then
					pX = centerX + (tgtW / 2) + (pointerW / 2) + padding + bounceOffset
					pY = centerY;  rot = 90
				elseif dir == "LEFT" then
					pX = centerX - (tgtW / 2) - (pointerW / 2) - padding - bounceOffset
					pY = centerY;  rot = -90
				elseif dir == "TOP_HIGH" then
					pX = centerX
					pY = centerY - (tgtH / 2) - (pointerH / 2) - topHighExtra - bounceOffset
					rot = 0
				elseif dir == "TOP" then
					pX = centerX
					pY = centerY - (tgtH / 2) - (pointerH / 2) - padding - bounceOffset
					rot = 0
				elseif dir == "BOTTOM" then
					pX = (tgtW > screenW * 0.18) and (centerX + (tgtW / 2) - tgtW * 0.08) or centerX
					pY = centerY + (tgtH / 2) + (pointerH / 2) + padding * 0.15 + bounceOffset
					rot = 180
				end

				-- ✨ Clamp so pointer never flies off-screen on tiny displays
				pX = math.clamp(pX, pointerW / 2 + 4, screenW - pointerW / 2 - 4)
				pY = math.clamp(pY, pointerH / 2 + 4, screenH - pointerH / 2 - 4)

				activePointer.Position = activePointer.Position:Lerp(UDim2.new(0, pX, 0, pY), 0.3)
				activePointer.Rotation = rot

				-- highlight (unchanged centering logic, just uses the corrected tgt* values)
				local highlightPad = math.max(6, screenH * 0.010)
				activeHighlight.Position = activeHighlight.Position:Lerp(UDim2.new(0, centerX, 0, centerY), 0.4)
				activeHighlight.Size     = activeHighlight.Size:Lerp(
					UDim2.new(0, tgtW + highlightPad * 2, 0, tgtH + highlightPad * 2), 0.4)

				local targetCorner    = targetToTrack2D:FindFirstChildOfClass("UICorner")
				local highlightCorner = activeHighlight:FindFirstChildOfClass("UICorner")
				if targetCorner and highlightCorner then
					highlightCorner.CornerRadius = targetCorner.CornerRadius
				end

				-- auto-scroll (unchanged)
				local scrollFrame = targetToTrack2D:FindFirstAncestorOfClass("ScrollingFrame")
				if scrollFrame and not isAutoScrolling then
					local targetY2   = targetToTrack2D.AbsolutePosition.Y
					local scrollY    = scrollFrame.AbsolutePosition.Y
					local scrollBot  = scrollY + scrollFrame.AbsoluteSize.Y
					if (targetY2 + tgtH < scrollY) or (targetY2 > scrollBot) then
						isAutoScrolling = true
						AutoScrollToTarget(targetToTrack2D)
						task.delay(0.5, function() isAutoScrolling = false end)
					end
				end
			end   -- end "size > 1" guard
		else
			activePointer.Visible = false; activeHighlight.Visible = false
		end

		if step.cameraTrackMode == "FollowAura" then
			local aura = GetActiveAura()
			if aura then
				if camera.CameraType ~= Enum.CameraType.Scriptable then camera.CameraType = Enum.CameraType.Scriptable end
				local targetPos = aura:IsA("Model") and aura:GetPivot().Position or aura.Position
				local offset = step.cameraOffset or Vector3.new(0, 8, 10) 
				camera.CFrame = camera.CFrame:Lerp(CFrame.new(targetPos + offset, targetPos), 0.025) 
			else
				local fallbackCam = CollectionService:GetTagged("Tutorial_AuraHolderCam")[1]
				if fallbackCam then
					if camera.CameraType ~= Enum.CameraType.Scriptable then camera.CameraType = Enum.CameraType.Scriptable end
					local desiredCFrame = fallbackCam:IsA("Model") and fallbackCam:GetPivot() or fallbackCam.CFrame
					camera.CFrame = camera.CFrame:Lerp(desiredCFrame, 0.025)
				end
			end

		elseif step.cameraTrackMode == "FollowPhysicsAura" then
			local physicsAura = GetActivePhysicsAura()

			local cameraTimeExpired = false
			if step.cameraDuration then
				if not step._cameraStartTime then step._cameraStartTime = tick() end
				if tick() - step._cameraStartTime >= step.cameraDuration then
					cameraTimeExpired = true
				end
			end

			if physicsAura and not cameraTimeExpired then
				step._returningToPlayer = nil 
				if camera.CameraType ~= Enum.CameraType.Scriptable then camera.CameraType = Enum.CameraType.Scriptable end
				local targetPos = physicsAura:IsA("Model") and physicsAura:GetPivot().Position or physicsAura.Position
				local offset = step.cameraOffset or Vector3.new(0, 15, 25) 
				camera.CFrame = camera.CFrame:Lerp(CFrame.new(targetPos + offset, targetPos), 0.05) 
			else
				if camera.CameraType == Enum.CameraType.Scriptable then
					if not step._returningToPlayer then
						step._returningToPlayer = true
						local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
						if hrp then
							local targetCF = CFrame.new(hrp.Position + Vector3.new(0, 8, 12), hrp.Position)
							local tween = TweenService:Create(camera, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {CFrame = targetCF})
							tween:Play()
							tween.Completed:Once(function()
								if step._returningToPlayer then
									camera.CameraType = Enum.CameraType.Custom
									camera.CameraSubject = player.Character:FindFirstChild("Humanoid")
								end
							end)
						else
							camera.CameraType = Enum.CameraType.Custom
						end
					end
				end
			end

		elseif step.cameraTarget then
			local camTarget = CollectionService:GetTagged(step.cameraTarget)[1]
			if not camTarget or not camTarget.Parent then
				if camera.CameraType ~= Enum.CameraType.Custom then
					camera.CameraType = Enum.CameraType.Custom
					if player.Character and player.Character:FindFirstChild("Humanoid") then
						camera.CameraSubject = player.Character:FindFirstChild("Humanoid")
					end
				end
			else
				if camera.CameraType ~= Enum.CameraType.Scriptable then camera.CameraType = Enum.CameraType.Scriptable end
				local desiredCFrame = camTarget:IsA("Model") and camTarget:GetPivot() or camTarget.CFrame
				camera.CFrame = camera.CFrame:Lerp(desiredCFrame, 0.03)
			end
		else
			if camera.CameraType ~= Enum.CameraType.Custom then
				camera.CameraType = Enum.CameraType.Custom
				if player.Character and player.Character:FindFirstChild("Humanoid") then
					camera.CameraSubject = player.Character:FindFirstChild("Humanoid")
				end
			end
		end

		if not step._startTime then step._startTime = tick() end

		if step.duration and step.duration > 0 then
			if tick() - step._startTime >= step.duration then shared.AdvanceTutorialStep(true) end
		elseif step.duration == 0 then
			if MeetsStrictGates(step) and not activeFallbackStep then shared.AdvanceTutorialStep(true) 
			elseif step.failsafeDuration and (tick() - step._startTime >= step.failsafeDuration) then shared.AdvanceTutorialStep(true) end
		end
	end)
end

---------------------------------------------------------------
-- EXTERNAL ADVANCEMENT (Server or Local UI)
---------------------------------------------------------------
shared.AdvanceTutorialStep = function(forceAdvance)
	if isAdvancing then return end 
	if tutorialComplete then return end
	if activeFallbackStep then return end

	local currentStepData = TutorialConfig.GetStepByIndex(currentStepIndex)
	if currentStepData and currentStepData.duration ~= 0 and not forceAdvance then
		if not actionMatchedForAdvance then return end
	end

	actionMatchedForAdvance = false; lockedAura = nil 

	if currentStepData and currentStepData.duration == 0 and not forceAdvance then
		if not MeetsStrictGates(currentStepData) then return end
	end

	isAdvancing = true 

	if currentStepData then TutorialStepComplete:FireServer(currentStepData.id) end
	currentStepIndex += 1

	baselineCubes = liveStats.totalCubesProduced
	baselineShipped = liveStats.totalPlatformsShipped
	baselineGoldenAuras = player:GetAttribute("LiveGoldenAuras") or liveStats.goldenAuras
	for k, v in pairs(liveStats.boostsBought) do baselineBoostsBought[k] = v end
	for k, v in pairs(liveStats.boostsUsed) do baselineBoostsUsed[k] = v end

	local nextStep = TutorialConfig.GetStepByIndex(currentStepIndex)

	if not nextStep then
		tutorialComplete = true
		if activePointer then activePointer.Visible = false end
		if activeHighlight then activeHighlight.Visible = false end
		HideBanner()
		if trackingConnection then trackingConnection:Disconnect() end

		camera.CameraType = Enum.CameraType.Custom
		if player.Character and player.Character:FindFirstChild("Humanoid") then
			camera.CameraSubject = player.Character:FindFirstChild("Humanoid")
		end

		TutorialStepComplete:FireServer("__tutorialComplete__")

		local successSound = Instance.new("Sound")
		successSound.SoundId = "rbxassetid://4612385808"; successSound.Volume = 0.6
		successSound.Parent = game:GetService("SoundService"); successSound:Play()
		game:GetService("Debris"):AddItem(successSound, 4)
	end

	task.delay(0.1, function() isAdvancing = false end)
end

---------------------------------------------------------------
-- STATE RECONCILIATION & DATA SYNC
---------------------------------------------------------------
UpdateHUDBridge:Connect(function(stats)
	if stats.currency ~= nil then liveStats.currency = stats.currency end
	if stats.totalEarned ~= nil then liveStats.totalEarned = stats.totalEarned end
	if stats.farmEvaluation ~= nil then liveStats.farmEvaluation = stats.farmEvaluation end
	if stats.soulAuras ~= nil then liveStats.soulAuras = stats.soulAuras end
	if stats.goldenAuras ~= nil then liveStats.goldenAuras = stats.goldenAuras end
	if stats.prestigeCount ~= nil then liveStats.prestigeCount = stats.prestigeCount end
	if stats.currentArea ~= nil then liveStats.currentArea = stats.currentArea end

	if stats.pendingAuras ~= nil then liveStats.pendingAuras = stats.pendingAuras end
	if stats.habitatCapacity ~= nil then liveStats.habitatCapacity = stats.habitatCapacity end
	if stats.rate ~= nil then liveStats.rate = stats.rate end

	if stats.totalCubesProduced ~= nil then liveStats.totalCubesProduced = math.max(liveStats.totalCubesProduced, stats.totalCubesProduced) end
	if stats.totalPlatformsShipped ~= nil then liveStats.totalPlatformsShipped = math.max(liveStats.totalPlatformsShipped, stats.totalPlatformsShipped) end
	if stats.totalLegendaryCubes ~= nil then liveStats.totalLegendaryCubes = math.max(liveStats.totalLegendaryCubes, stats.totalLegendaryCubes) end
	if stats.piggyBank ~= nil then liveStats.piggyBank = stats.piggyBank end

	if stats.tutorialComplete ~= nil then tutorialComplete = stats.tutorialComplete end

	if stats.tutorialProgress and not tutorialComplete then
		local highestCompletedIndex = 0

		for index, stepData in ipairs(TutorialConfig.Steps) do
			if stats.tutorialProgress[stepData.id] then highestCompletedIndex = index end
		end

		if highestCompletedIndex >= currentStepIndex then
			currentStepIndex = highestCompletedIndex + 1

			baselineCubes = liveStats.totalCubesProduced
			baselineShipped = liveStats.totalPlatformsShipped
			baselineGoldenAuras = player:GetAttribute("LiveGoldenAuras") or liveStats.goldenAuras
			for k, v in pairs(liveStats.boostsBought) do baselineBoostsBought[k] = v end
			for k, v in pairs(liveStats.boostsUsed) do baselineBoostsUsed[k] = v end

			if not TutorialConfig.GetStepByIndex(currentStepIndex) then
				tutorialComplete = true
				if trackingConnection then trackingConnection:Disconnect() end
				if questBanner then HideBanner() end
				if activePointer then activePointer.Visible = false end
				if activeHighlight then activeHighlight.Visible = false end
			end
		end
	end
end)

---------------------------------------------------------------
-- BOOT & MENU GATE
---------------------------------------------------------------
task.spawn(function()
	local menuGate = ReplicatedStorage:WaitForChild("MenuDismissed", 10)
	if menuGate and not menuGate:GetAttribute("Fired") then menuGate.Event:Wait() end

	local character = player.Character or player.CharacterAdded:Wait()
	local humanoid = character:WaitForChild("Humanoid", 5)
	camera.CameraType = Enum.CameraType.Custom
	if humanoid then camera.CameraSubject = humanoid end

	tutorialActive = true
	InitTutorialUI()
	StartTrackingLoop()
end)
