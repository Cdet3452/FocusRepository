-- TutorialController
-- Location: StarterPlayer > StarterPlayerScripts > TutorialController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

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
	tutorialGui.IgnoreGuiInset = true 
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

local function AutoScrollToTarget(target)
	local scrollFrame = target:FindFirstAncestorOfClass("ScrollingFrame")
	if scrollFrame then
		local relativeY = (target.AbsolutePosition.Y - scrollFrame.AbsolutePosition.Y) + scrollFrame.CanvasPosition.Y
		local targetCanvasY = relativeY - (scrollFrame.AbsoluteSize.Y / 2) + (target.AbsoluteSize.Y / 2)
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

	local isMobile = screenW <= 850 or screenH <= 600
	local leftHudWidth = 100
	local rightHudWidth = 270
	local availableCenterWidth = screenW - leftHudWidth - rightHudWidth

	if availableCenterWidth < 250 then availableCenterWidth = 250 end 

	local baseBannerWidth = 650
	local targetScale = 1.0

	if availableCenterWidth < baseBannerWidth then
		targetScale = math.clamp(availableCenterWidth / baseBannerWidth, 0.45, 0.9)
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
		-- 🛠️ NO PANELS OPEN: Central fallback
		if isMobile then
			return UDim2.new(0.5, 0, 0.02, 0), targetScale
		else
			return UDim2.new(0.5, 0, 0, 15), targetScale
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

		local screenW = camera.ViewportSize.X
		local screenH = camera.ViewportSize.Y

		local isMobileView = screenW <= 850 or screenH <= 600
		local pointerScaleFactor = isMobileView and 0.55 or 1.0
		local basePointerSize = TutorialConfig.PointerSize or UDim2.new(0, 80, 0, 80)

		activePointer.Size = UDim2.new(
			basePointerSize.X.Scale, basePointerSize.X.Offset * pointerScaleFactor,
			basePointerSize.Y.Scale, basePointerSize.Y.Offset * pointerScaleFactor
		)

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

			-- Ensure we always grab the physical button if tagged on a wrapper
			if not targetToTrack2D:IsA("GuiButton") then
				local foundBtn = targetToTrack2D:FindFirstChildWhichIsA("TextButton", true) or targetToTrack2D:FindFirstChildWhichIsA("ImageButton", true)
				if not foundBtn and targetToTrack2D.Parent then
					foundBtn = targetToTrack2D.Parent:FindFirstChildWhichIsA("TextButton", true) or targetToTrack2D.Parent:FindFirstChildWhichIsA("ImageButton", true)
				end
				if foundBtn and foundBtn.Visible then
					targetToTrack2D = foundBtn
				end
			end

			if targetToTrack2D.AbsoluteSize.Magnitude > 0 and IsVisibleOnScreen(targetToTrack2D) then
				activePointer.Visible = true; activeHighlight.Visible = true

				local tgtW = targetToTrack2D.AbsoluteSize.X
				local tgtH = targetToTrack2D.AbsoluteSize.Y
				local tgtX = targetToTrack2D.AbsolutePosition.X
				local tgtY = targetToTrack2D.AbsolutePosition.Y

				-- ✨ THE FIX: Calculates the true VISUAL bounding box.
				-- Because your AnchorPoint is 0.95, UIScale pulls the button downwards. 
				-- This finds exactly where the visual borders actually are.
				local scaleObj = targetToTrack2D:FindFirstChildOfClass("UIScale")
				if scaleObj and scaleObj.Scale ~= 1 then
					local s = scaleObj.Scale
					local anchor = targetToTrack2D.AnchorPoint
					local anchorPxX = tgtX + (tgtW * anchor.X)
					local anchorPxY = tgtY + (tgtH * anchor.Y)

					tgtW = tgtW * s
					tgtH = tgtH * s
					tgtX = anchorPxX - (tgtW * anchor.X)
					tgtY = anchorPxY - (tgtH * anchor.Y)
				end

				local centerX = tgtX + (tgtW / 2)
				local centerY = tgtY + (tgtH / 2)

				local padding = 15
				local pointerW = activePointer.Size.X.Offset
				local pointerH = activePointer.Size.Y.Offset

				local pX, pY, rot
				local dir = "BOTTOM" 

				local tagCheck = step.targetTag or ""

				if HUD_DIRECTIONS[tagCheck] then
					dir = HUD_DIRECTIONS[tagCheck]
				elseif tagCheck:match("Tutorial_AchieveRow") or tagCheck:match("Tutorial_BuyBoost") or tagCheck:match("Tutorial_UseBoost") then
					dir = "RIGHT"
				else
					if centerX < screenW * 0.3 then dir = "RIGHT"
					elseif centerX > screenW * 0.7 then dir = "LEFT"
					elseif centerY > screenH * 0.5 then dir = "TOP"
					else dir = "BOTTOM" end
				end

				if dir == "RIGHT" then
					pX = centerX + (tgtW / 2) + (pointerW / 2) + padding + bounceOffset
					pY = centerY
					rot = 90
				elseif dir == "LEFT" then
					pX = centerX - (tgtW / 2) - (pointerW / 2) - padding - bounceOffset
					pY = centerY
					rot = -90
				elseif dir == "TOP_HIGH" then
					pX = centerX
					pY = centerY - (tgtH / 2) - (pointerH / 2) - 45 - bounceOffset
					rot = 0
				elseif dir == "TOP" then
					pX = centerX
					pY = centerY - (tgtH / 2) - (pointerH / 2) - padding - bounceOffset
					rot = 0
				elseif dir == "BOTTOM" then
					if tgtW > 200 then
						pX = centerX + (tgtW / 2) - 55 
					else
						pX = centerX
					end
					pY = centerY + (tgtH / 2) + (pointerH / 2) + 2 + bounceOffset 
					rot = 180
				end

				local targetPointerPos = UDim2.new(0, pX, 0, pY)
				activePointer.Position = activePointer.Position:Lerp(targetPointerPos, 0.3)
				activePointer.Rotation = rot

				-- The highlight is now centered precisely on the true visual center
				local targetHighPos = UDim2.new(0, centerX, 0, centerY)
				local targetHighSize = UDim2.new(0, tgtW + 12, 0, tgtH + 12)

				activeHighlight.Position = activeHighlight.Position:Lerp(targetHighPos, 0.4)
				activeHighlight.Size = activeHighlight.Size:Lerp(targetHighSize, 0.4)

				local targetCorner = targetToTrack2D:FindFirstChildOfClass("UICorner")
				local highlightCorner = activeHighlight:FindFirstChildOfClass("UICorner")
				if targetCorner and highlightCorner then highlightCorner.CornerRadius = targetCorner.CornerRadius end

				local scrollFrame = targetToTrack2D:FindFirstAncestorOfClass("ScrollingFrame")
				if scrollFrame and not isAutoScrolling then
					local targetY2 = targetToTrack2D.AbsolutePosition.Y
					local scrollY = scrollFrame.AbsolutePosition.Y
					local scrollBottom = scrollY + scrollFrame.AbsoluteSize.Y

					if (targetY2 + tgtH < scrollY) or (targetY2 > scrollBottom) then
						isAutoScrolling = true; AutoScrollToTarget(targetToTrack2D)
						task.delay(0.5, function() isAutoScrolling = false end)
					end
				end
			else
				activePointer.Visible = false; activeHighlight.Visible = false
			end
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
