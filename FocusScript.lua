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
	if lockedAura and lockedAura.Parent and lockedAura:GetAttribute("AuraCube") then return lockedAura end
	local auraHolder = Workspace:FindFirstChild("AuraHolder")
	if auraHolder then
		local children = auraHolder:GetChildren()
		for i = #children, 1, -1 do
			local child = children[i]
			if child:GetAttribute("AuraCube") then lockedAura = child; return child end
		end
	end
	local wsChildren = Workspace:GetChildren()
	for i = #wsChildren, 1, -1 do
		local child = wsChildren[i]
		if child:GetAttribute("AuraCube") then lockedAura = child; return child end
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
	tutorialGui.ResetOnSpawn = false; tutorialGui.Parent = playerGui

	activeHighlight = Instance.new("Frame"); activeHighlight.Name = "TutorialHighlight"
	activeHighlight.BackgroundColor3 = Color3.new(1, 1, 1); activeHighlight.BackgroundTransparency = 1 
	activeHighlight.Interactable = false; activeHighlight.Active = false; activeHighlight.Visible = false
	activeHighlight.ZIndex = 99; activeHighlight.Parent = tutorialGui

	local highlightStroke = Instance.new("UIStroke", activeHighlight)
	highlightStroke.Color = TutorialConfig.DefaultColor; highlightStroke.Thickness = 3; highlightStroke.Transparency = 0.2
	Instance.new("UICorner", activeHighlight).CornerRadius = UDim.new(0, 8)
	TweenService:Create(highlightStroke, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {Transparency = 0.8}):Play()

	activePointer = Instance.new("ImageLabel"); activePointer.Name = "GhostHand"
	activePointer.Size = TutorialConfig.PointerSize; activePointer.BackgroundTransparency = 1
	activePointer.Image = TutorialConfig.PointerImage; activePointer.AnchorPoint = Vector2.new(0.5, 0)
	activePointer.Visible = false; activePointer.Active = false; activePointer.ZIndex = 100; activePointer.Parent = tutorialGui

	questBanner = Instance.new("Frame"); questBanner.Name = "QuestBanner"
	questBanner.Size = UDim2.new(0.85, 0, 0, 130); questBanner.AnchorPoint = Vector2.new(0.5, 0)
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
	local titleConstraint = Instance.new("UITextSizeConstraint", title); titleConstraint.MaxTextSize = 34; titleConstraint.MinTextSize = 14

	local titleShadow = title:Clone(); titleShadow.Name = "TitleShadow"; titleShadow.TextColor3 = Color3.new(0, 0, 0)
	titleShadow.TextTransparency = 0.6; titleShadow.Position = UDim2.new(0, 98, 0.08, 2)
	titleShadow.ZIndex = title.ZIndex - 1; titleShadow.Parent = questBanner

	local body = Instance.new("TextLabel", questBanner); body.Name = "Body"
	body.Size = UDim2.new(1, -100, 0.5, 0); body.Position = UDim2.new(0, 96, 0.45, 0)
	body.BackgroundTransparency = 1; body.TextColor3 = T.bodyText or Color3.fromRGB(230, 230, 240)
	body.TextWrapped = true; body.TextScaled = true; body.RichText = true
	body.Font = Enum.Font.GothamMedium; body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top; body.Active = false
	local bodyConstraint = Instance.new("UITextSizeConstraint", body); bodyConstraint.MaxTextSize = 22; bodyConstraint.MinTextSize = 10
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

	if not questBanner.Visible then
		questBanner.Position = UDim2.new(0.5, 0, 0, -250); questBanner.Visible = true
		TweenService:Create(questBanner, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 0, 15) }):Play()
	else
		local scale = questBanner:FindFirstChildOfClass("UIScale")
		if scale then
			scale.Scale = 0.85
			TweenService:Create(scale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
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
				activePointer.Position = UDim2.new(0, screenPos.X, 0, screenPos.Y - (activePointer.Size.Y.Offset / 2) - bounceOffset)
			else
				activePointer.Visible = false; activeHighlight.Visible = false
			end

		elseif targetToTrack2D and targetToTrack2D:IsA("GuiObject") then
			if targetToTrack2D.AbsoluteSize.Magnitude > 0 and IsVisibleOnScreen(targetToTrack2D) then
				activePointer.Visible = true; activeHighlight.Visible = true

				local tgtRelX = targetToTrack2D.AbsolutePosition.X; local tgtRelY = targetToTrack2D.AbsolutePosition.Y
				activeHighlight.Size = UDim2.new(0, targetToTrack2D.AbsoluteSize.X + 12, 0, targetToTrack2D.AbsoluteSize.Y + 12)
				activeHighlight.Position = UDim2.new(0, tgtRelX - 6, 0, tgtRelY - 6)

				local targetCorner = targetToTrack2D:FindFirstChildOfClass("UICorner")
				local highlightCorner = activeHighlight:FindFirstChildOfClass("UICorner")
				if targetCorner and highlightCorner then highlightCorner.CornerRadius = targetCorner.CornerRadius end

				local centerPos = targetToTrack2D.AbsolutePosition + (targetToTrack2D.AbsoluteSize / 2)
				activePointer.Position = UDim2.new(0, centerPos.X, 0, targetToTrack2D.AbsolutePosition.Y - activePointer.Size.Y.Offset - bounceOffset)

				local scrollFrame = targetToTrack2D:FindFirstAncestorOfClass("ScrollingFrame")
				if scrollFrame and not isAutoScrolling then
					local targetY = targetToTrack2D.AbsolutePosition.Y; local scrollY = scrollFrame.AbsolutePosition.Y
					local scrollBottom = scrollY + scrollFrame.AbsoluteSize.Y

					if (targetY + targetToTrack2D.AbsoluteSize.Y < scrollY) or (targetY > scrollBottom) then
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
				-- ✨ THE FIX: Smoothly TWEEN back to the player to avoid "droning" and grant instant control!
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

-- ShopController
-- Location: StarterPlayer > StarterPlayerScripts > ShopController

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local UpgradeConfig     = require(ReplicatedStorage.Modules.UpgradeConfig)
local Formatter         = require(ReplicatedStorage.Modules.NumberFormatter)
local EpicUpgradeConfig = require(ReplicatedStorage.Modules.EpicUpgradeConfig)
local UITheme           = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UITheme"))
local T                 = UITheme.Get("Custom")
local SoundConfig       = require(ReplicatedStorage.Modules.SoundConfig)

local RemoteEvents        = ReplicatedStorage:WaitForChild("RemoteEvents")
local PurchaseUpgrade     = RemoteEvents:WaitForChild("PurchaseUpgrade", 15)
local UpgradeUpdated      = RemoteEvents:WaitForChild("UpgradeUpdated", 15)
local PurchaseEpicUpgrade = RemoteEvents:WaitForChild("PurchaseEpicUpgrade", 15)
local EpicUpgradeUpdated  = RemoteEvents:WaitForChild("EpicUpgradeUpdated", 15)

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

-- FORWARD DECLARATIONS
local UpdateLockedTierProgress = nil
local RebuildRegularShop = nil 

-- ─────────────────────────────────────────────────────────────────────────────
-- INITIALIZATION
-- ─────────────────────────────────────────────────────────────────────────────
for _, tierData in ipairs(UpgradeConfig.Tiers) do
	for upgradeId, cfg in pairs(tierData.upgrades) do
		upgradeState[upgradeId] = {
			level    = 0,
			maxLevel = cfg.maxLevel,
			cost     = UpgradeConfig.CalculateCost(upgradeId, 0),
			maxed    = false,
		}
	end
end

for _, tierData in ipairs(EpicUpgradeConfig.Tiers) do
	for upgradeId, cfg in pairs(tierData.upgrades) do
		epicUpgradeState[upgradeId] = {
			level    = 0,
			maxLevel = cfg.maxLevel,
			cost     = EpicUpgradeConfig.CalculateCost(upgradeId, 0),
			maxed    = false,
		}
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- VFX / SOUND HELPERS
-- ─────────────────────────────────────────────────────────────────────────────
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
		TweenService:Create(particle, tInfo, {
			Position             = endPos,
			Size                 = UDim2.new(0, 0, 0, 0),
			Rotation             = particle.Rotation + math.random(-180, 180),
			BackgroundTransparency = 1,
		}):Play()
	end

	task.delay(1, function() burstGui:Destroy() end)
end

local comboPitch  = 1.0
local lastBuyTime = tick()

local function PlayPurchaseSound()
	if tick() - lastBuyTime < 0.3 then
		comboPitch = math.min(comboPitch + 0.05, 2.5)
	else
		comboPitch = 1.0
	end
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
			return
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
		TweenService:Create(targetButton, wobbleInfo, {
			Position = origPos + UDim2.new(0, 4, 0, 0)
		}):Play()
	end
end

local function FormatNumber(n) return Formatter.Format(n) end
local function PlayUI(id) if shared.PlayUISound then shared.PlayUISound(id) end end

-- ─────────────────────────────────────────────────────────────────────────────
-- ✨ SHOP BUTTON (Moved to Left Sidebar)
-- ─────────────────────────────────────────────────────────────────────────────
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

	-- Ensure Faded2 cleanly stacks the Shop button beneath the Achievement button
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
	-- Fallback if Faded2 is missing
	ShopButton.Size = UDim2.new(0, 60, 0, 60)
	ShopButton.AnchorPoint = Vector2.new(0, 0.5)
	ShopButton.Position = UDim2.new(0, 15, 0.5, 0)
	ShopButton.Parent = mainHUD
end

CollectionService:AddTag(ShopButton, "Tutorial_ShopButton")
Instance.new("UICorner", ShopButton).CornerRadius = UDim.new(0.5, 0)

local shopStroke = Instance.new("UIStroke", ShopButton)
shopStroke.Color     = T.accentGold
shopStroke.Thickness = 2

local shopIcon = Instance.new("ImageLabel", ShopButton)
shopIcon.Size               = UDim2.new(0.6, 0, 0.6, 0)
shopIcon.Position           = UDim2.new(0.2, 0, 0.2, 0)
shopIcon.BackgroundTransparency = 1
shopIcon.ScaleType          = Enum.ScaleType.Fit
shopIcon.Image              = "rbxassetid://14916846070"

-- ─────────────────────────────────────────────────────────────────────────────
-- ✨ SHOP PANEL (Left Slide-out format)
-- ─────────────────────────────────────────────────────────────────────────────
local PANEL_MAX_W = 420; local PANEL_MAX_H = 800; local HEADER_H = 42

local ShopPanel = Instance.new("Frame")
ShopPanel.Name              = "ShopPanel"
ShopPanel.Size              = UDim2.new(0.85, 0, 0.88, 0) 
ShopPanel.AnchorPoint       = Vector2.new(0, 0.5) 
ShopPanel.Position          = UDim2.new(0, -500, 0.5, 0) -- Hidden to the left initially
ShopPanel.BackgroundColor3  = T.panelBG
ShopPanel.BorderSizePixel   = 0
ShopPanel.Visible           = false
ShopPanel.ZIndex            = 10
ShopPanel.ClipsDescendants  = true
ShopPanel.Parent            = mainHUD
CollectionService:AddTag(ShopPanel, "Tutorial_ShopPanel") 
Instance.new("UICorner", ShopPanel).CornerRadius = UDim.new(0, 10)

local sizeConstraint = Instance.new("UISizeConstraint")
sizeConstraint.MaxSize = Vector2.new(PANEL_MAX_W, PANEL_MAX_H)
sizeConstraint.Parent  = ShopPanel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color     = T.panelStroke
panelStroke.Thickness = 2
panelStroke.Parent    = ShopPanel

local TitleBar = Instance.new("Frame")
TitleBar.Name                 = "TitleBar"
TitleBar.Size                 = UDim2.new(1, 0, 0, HEADER_H)
TitleBar.BackgroundColor3     = T.headerBG
TitleBar.BorderSizePixel      = 0
TitleBar.ZIndex               = 11
TitleBar.ClipsDescendants     = true
TitleBar.BackgroundTransparency = 1
TitleBar.Parent               = ShopPanel
Instance.new("UICorner", TitleBar).CornerRadius = UDim.new(0, 10)

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
CloseButton.Size             = UDim2.new(0, 30, 0, 30)
CloseButton.Position         = UDim2.new(1, -35, 0, 6)
CloseButton.BackgroundColor3 = T.buttonRed
CloseButton.BorderSizePixel  = 0
CloseButton.Text             = "X"
CloseButton.TextColor3       = T.bodyText
CloseButton.TextScaled       = true
CloseButton.Font             = T.font
CloseButton.ZIndex           = 9999
CloseButton.Parent           = TitleBar
CollectionService:AddTag(CloseButton, "Tutorial_ShopCloseBtn") 
Instance.new("UICorner", CloseButton).CornerRadius = UDim.new(0, 6)

-- ─────────────────────────────────────────────────────────────────────────────
-- INFO POPUP
-- ─────────────────────────────────────────────────────────────────────────────
local InfoPopup = Instance.new("Frame")
InfoPopup.Name                 = "InfoPopup"
InfoPopup.Size                 = UDim2.new(0.85, 0, 0.6, 0)
InfoPopup.Position             = UDim2.new(0.5, 0, 0.5, 0)
InfoPopup.AnchorPoint          = Vector2.new(0.5, 0.5)
InfoPopup.BackgroundColor3     = T.cardBG
InfoPopup.BackgroundTransparency = 0
InfoPopup.ZIndex               = 50
InfoPopup.Visible              = false
InfoPopup.Parent               = ShopPanel
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
	tween:Play()
	tween.Completed:Once(function() InfoPopup.Visible = false end)
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- MAIN TAB BAR
-- ─────────────────────────────────────────────────────────────────────────────
local activeShopTabText = "Regular Upgrades"

local MainTabBar = Instance.new("Frame")
MainTabBar.Size                 = UDim2.new(1, -20, 0, 85)
MainTabBar.Position             = UDim2.new(0, 10, 0, HEADER_H + 4)
MainTabBar.BackgroundTransparency = 1
MainTabBar.ZIndex               = 11
MainTabBar.Parent               = ShopPanel

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
local TAB_COLOR_ACTIVE = T.accentGold

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

local tabEpic     = MakeMainTab("Epic",     "Epic Research",     "rbxassetid://14916846070")
local tabUpgrades = MakeMainTab("Upgrades", "Regular Upgrades",  "rbxassetid://14916846070")

-- ─────────────────────────────────────────────────────────────────────────────
-- CURRENCY LABEL
-- ─────────────────────────────────────────────────────────────────────────────
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
CurrencyLabel.Parent            = ShopPanel

-- ─────────────────────────────────────────────────────────────────────────────
-- SCROLL FRAMES
-- ─────────────────────────────────────────────────────────────────────────────
local function MakeScroll(name, yTop)
	local sf = Instance.new("ScrollingFrame")
	sf.Name                 = name
	sf.Size                 = UDim2.new(1, -20, 1, -(yTop + 10))
	sf.Position             = UDim2.new(0, 10, 0, yTop)
	sf.BackgroundTransparency = 1
	sf.BorderSizePixel      = 0
	sf.ScrollBarThickness   = 4
	sf.ScrollBarImageColor3 = T.subText
	sf.CanvasSize           = UDim2.new(0, 0, 0, 0)
	sf.ZIndex               = 11
	sf.Visible              = false
	sf.ClipsDescendants     = true
	sf.Parent               = ShopPanel

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.Parent  = sf
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		sf.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 10)
	end)
	return sf
end

local REGULAR_SCROLL_TOP = HEADER_H + 95
local RegularScroll      = MakeScroll("RegularScroll", REGULAR_SCROLL_TOP)
local EPIC_SCROLL_TOP    = HEADER_H + 95
local EpicScroll         = MakeScroll("EpicScroll", EPIC_SCROLL_TOP)

-- ─────────────────────────────────────────────────────────────────────────────
-- CARD BUILDER
-- ─────────────────────────────────────────────────────────────────────────────
local function BuildCard(parent, upgradeId, cfg, isEpic, cardRefsTable)
	local card = Instance.new("Frame")
	card.Name             = "Card_" .. upgradeId
	card.Size             = UDim2.new(1, 0, 0, 100)
	card.BackgroundColor3 = T.cardBG
	card.BorderSizePixel  = 0
	card.Parent           = parent
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)

	local icon = Instance.new("ImageLabel", card)
	icon.Size               = UDim2.new(0, 50, 0, 50)
	icon.Position           = UDim2.new(0, 15, 0.5, -25)
	icon.BackgroundTransparency = 1
	icon.Image              = cfg.iconId or "rbxassetid://0"

	local infoBtn = Instance.new("TextButton", card)
	infoBtn.Size             = UDim2.new(0, 22, 0, 22)
	infoBtn.Position         = UDim2.new(0, 75, 0, 12)
	infoBtn.BackgroundColor3 = T.buttonSecondary
	infoBtn.Text             = "i"
	infoBtn.TextColor3       = T.bodyText
	infoBtn.Font             = Enum.Font.GothamBlack
	infoBtn.TextSize         = 14
	Instance.new("UICorner", infoBtn).CornerRadius = UDim.new(1, 0)
	infoBtn.MouseButton1Click:Connect(function() ShowInfo(cfg.displayName, cfg.description) end)

	local nameLabel = Instance.new("TextLabel", card)
	nameLabel.Size              = UDim2.new(0.74, -120, 0, 24)
	nameLabel.Position          = UDim2.new(0, 102, 0, 11)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text              = string.upper(cfg.displayName)
	nameLabel.TextColor3        = T.bodyText
	nameLabel.TextScaled        = true
	nameLabel.Font              = Enum.Font.FredokaOne
	nameLabel.TextXAlignment    = Enum.TextXAlignment.Left

	local descLabel = Instance.new("TextLabel", card)
	descLabel.Size              = UDim2.new(0.74, -95, 0, 36)
	descLabel.Position          = UDim2.new(0, 75, 0, 38)
	descLabel.BackgroundTransparency = 1
	descLabel.Text              = cfg.description
	descLabel.TextColor3        = T.subText
	descLabel.TextWrapped       = true
	descLabel.TextSize          = 16
	descLabel.Font              = Enum.Font.GothamMedium
	descLabel.TextXAlignment    = Enum.TextXAlignment.Left
	descLabel.TextYAlignment    = Enum.TextYAlignment.Top

	local levelLabel = Instance.new("TextLabel", card)
	levelLabel.Size             = UDim2.new(0.74, -95, 0, 18)
	levelLabel.Position         = UDim2.new(0, 75, 0, 76)
	levelLabel.BackgroundTransparency = 1
	levelLabel.Text             = "Lv. 0 / " .. cfg.maxLevel
	levelLabel.TextColor3       = T.accentGreen
	levelLabel.TextSize         = 16
	levelLabel.Font             = Enum.Font.FredokaOne
	levelLabel.TextXAlignment   = Enum.TextXAlignment.Left

	local buyButton = Instance.new("TextButton", card)
	buyButton.Name             = "PurchaseButton"
	buyButton.Size             = UDim2.new(0.24, 0, 0, 46)
	buyButton.AnchorPoint      = Vector2.new(1, 0.5)
	buyButton.Position         = UDim2.new(1, -12, 0.5, 0)
	buyButton.BackgroundColor3 = isEpic and T.accentPurple or T.buttonGreen
	buyButton.BorderSizePixel  = 0
	buyButton.TextColor3       = T.bodyText
	buyButton.TextScaled       = true
	buyButton.Font             = Enum.Font.FredokaOne
	CollectionService:AddTag(buyButton, "Tutorial_Buy_" .. upgradeId) 
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

	local function StopAllOtherHolds(myGen)
		if globalHoldGeneration ~= myGen then
			globalHoldGeneration = myGen
		end
	end

	local function TryBuy()
		if isLoadingData then return false end

		if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_BuyUpgrade") then return false end

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
		if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_BuyUpgrade") then return end

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

		pulseTween = TweenService:Create(scale,
			TweenInfo.new(0.12, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Scale = 0.88 })
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
		if scale then
			TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), { Scale = 1 }):Play()
		end
	end)

	local function StopHold()
		holdingBuy = false
		globalHoldActive = false
		if pulseTween then pulseTween:Cancel() end
		local scale = buyButton:FindFirstChildOfClass("UIScale")
		if scale then
			TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), { Scale = 1 }):Play()
		end
	end

	buyButton.MouseButton1Up:Connect(StopHold)
	buyButton.MouseLeave:Connect(StopHold)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- BUILD EPIC CARDS
-- ─────────────────────────────────────────────────────────────────────────────
local epicOrderIndex = 1
for _, tierData in ipairs(EpicUpgradeConfig.Tiers) do
	for upgradeId, cfg in pairs(tierData.upgrades) do
		BuildCard(EpicScroll, upgradeId, cfg, true, epicCardRefs)

		local ref = epicCardRefs[upgradeId]
		if ref and ref.frame then
			ref.baseOrder      = epicOrderIndex
			ref.frame.LayoutOrder = epicOrderIndex
			epicOrderIndex    += 1
			ref.frame.Visible  = false
			ref.frame.Parent   = EpicScroll
			if UITheme and UITheme.Apply then UITheme.Apply(ref.frame, "ShopCard") end
		end
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- CARD UPDATE FUNCTIONS
-- ─────────────────────────────────────────────────────────────────────────────
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
		ref.buyButton.TextColor3   = (actualCash < state.cost)
			and Color3.fromRGB(255, 100, 100) or Color3.fromRGB(255, 255, 255)
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
	else
		ref.frame.LayoutOrder      = ref.baseOrder or 0
		ref.buyButton.Text         = "✦ " .. FormatNumber(state.cost)
		ref.buyButton.TextColor3   = (actualAuras < state.cost)
			and Color3.fromRGB(255, 100, 100) or Color3.fromRGB(255, 255, 255)
		ref.buyButton.BackgroundColor3 = Color3.fromRGB(150, 80, 255)
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

	for _, child in ipairs(RegularScroll:GetChildren()) do
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

-- ─────────────────────────────────────────────────────────────────────────────
-- TIER HEADERS
-- ─────────────────────────────────────────────────────────────────────────────
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

-- ─────────────────────────────────────────────────────────────────────────────
-- REBUILD REGULAR SHOP
-- ─────────────────────────────────────────────────────────────────────────────
RebuildRegularShop = function()
	for _, child in ipairs(RegularScroll:GetChildren()) do
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
			header.Parent = RegularScroll

			for upgradeId, cfg in pairs(tierData.upgrades) do
				BuildCard(RegularScroll, upgradeId, cfg, false, regularCardRefs)
				local ref = regularCardRefs[upgradeId]

				if ref and ref.frame then
					if ref.buyButton then
						ref.buyButton.Name = "Buy_" .. upgradeId
					end
					ref.baseOrder          = listOrder
					ref.frame.LayoutOrder  = listOrder
					listOrder             += 1
					ref.frame.Visible      = true
					ref.frame.Parent       = RegularScroll
					if UITheme and UITheme.Apply then UITheme.Apply(ref.frame, "ShopCard") end
					local myColor = Color3.fromRGB(45, 30, 55)
					ref.frame:SetAttribute("TierColor", myColor)
					ref.frame.BackgroundColor3 = myColor
				end
			end
		else
			local lockedHeader = CreateLockedTierHeader(
				tierData.tierName or "Tier " .. tierNum,
				totalUpgradesBought,
				tierData.unlockRequirement
			)
			lockedHeader.LayoutOrder = listOrder
			lockedHeader.Parent      = RegularScroll
			break
		end
	end
	UpdateAllRegularCards()
end

RebuildRegularShop()

task.delay(5, function() isLoadingData = false end)

-- ─────────────────────────────────────────────────────────────────────────────
-- TAB SWITCHING
-- ─────────────────────────────────────────────────────────────────────────────
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

-- ─────────────────────────────────────────────────────────────────────────────
-- ✨ OPEN / CLOSE (Modified for Slide-out & No Blur)
-- ─────────────────────────────────────────────────────────────────────────────
local function OpenShop()
	shopOpen = true
	ShopPanel.Visible = true
	SwitchToMainTab(activeMainTab)

	-- Slide in from the left, docking next to the left sidebar margin
	TweenService:Create(ShopPanel,
		TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0, 90, 0.5, 0) }
	):Play()

	ShopButton.BackgroundColor3 = T.panelStroke
end

local function CloseShop()
	shopOpen = false
	PlayUI(SoundConfig.UIClose)

	-- Slide back out off the left side of the screen
	local tween = TweenService:Create(ShopPanel,
		TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Position = UDim2.new(0, -500, 0.5, 0) }
	)
	tween:Play()
	tween.Completed:Once(function()
		if not shopOpen then ShopPanel.Visible = false end
	end)

	ShopButton.BackgroundColor3 = T.buttonSecondary
end

ShopButton.MouseButton1Down:Connect(function()
	if shopOpen then
		if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_CloseShop") then return end
		CloseShop()
		if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
	else
		if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_OpenShop") then return end
		OpenShop()
		if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
	end
end)

CloseButton.MouseButton1Down:Connect(function()
	if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_CloseShop") then return end
	CloseShop()
	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- LIVE UPDATE LOOP
-- ─────────────────────────────────────────────────────────────────────────────
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

-- ─────────────────────────────────────────────────────────────────────────────
-- SERVER EVENTS
-- ─────────────────────────────────────────────────────────────────────────────
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

-- ─────────────────────────────────────────────────────────────────────────────
-- BUTTON JUICE
-- ─────────────────────────────────────────────────────────────────────────────
local function AddButtonJuice(btn)
	if not btn then return end
	local scale = btn:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = btn
	end

	btn.MouseEnter:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Sine), { Scale = 1.08 }):Play() end)
	btn.MouseLeave:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Sine), { Scale = 1 }):Play() end)
	btn.MouseButton1Down:Connect(function() TweenService:Create(scale, TweenInfo.new(0.1, Enum.EasingStyle.Sine), { Scale = 0.9 }):Play() end)
	btn.MouseButton1Up:Connect(function() TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), { Scale = 1.08 }):Play() end)
end

AddButtonJuice(ShopButton)
AddButtonJuice(CloseButton)
AddButtonJuice(tabUpgrades)
AddButtonJuice(tabEpic)

-- ─────────────────────────────────────────────────────────────────────────────
-- REFRESH LOOK
-- ─────────────────────────────────────────────────────────────────────────────
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

	if not titleFlair then
		titleFlair = UITheme.ApplyFlair(TitleLabel, "Ghost")
	end

	if not flairedExtra then flairedExtra = true end

	for _, scrollName in ipairs({ "RegularScroll", "EpicScroll" }) do
		local scroll = ShopPanel:FindFirstChild(scrollName)
		if scroll then
			local layout = scroll:FindFirstChildOfClass("UIListLayout")
			if layout then layout.SortOrder = Enum.SortOrder.LayoutOrder end
		end
	end

	local outerStroke = ShopPanel:FindFirstChildWhichIsA("UIStroke")
	if outerStroke then outerStroke.Color = Color3.fromRGB(255, 255, 255) end
end

task.wait(2)
RefreshLook()

-- ✨ TUTORIAL OVERRIDE: Close shop when camera pans
local forceClose = ReplicatedStorage:FindFirstChild("ForceCloseUI") or Instance.new("BindableEvent")
forceClose.Name = "ForceCloseUI"
forceClose.Parent = ReplicatedStorage
forceClose.Event:Connect(function()
	if shopOpen then CloseShop() end
end)

-- BoostController
-- Location: StarterPlayer > StarterPlayerScripts > BoostController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local AdminConfig = require(ReplicatedStorage.Modules.AdminConfig)
local SoundConfig = require(ReplicatedStorage.Modules.SoundConfig)
local BoostConfig = require(ReplicatedStorage.Modules.BoostConfig) 
local AchievementConfig = require(ReplicatedStorage.Modules.AchievementConfig)
local UITheme = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UITheme"))
local T = UITheme.Get("Custom")

local BuyBoost = ReplicatedStorage.RemoteEvents:WaitForChild("BuyBoost")
local ActivateBoost = ReplicatedStorage.RemoteEvents:WaitForChild("ActivateBoost")
local BoostUpdated = ReplicatedStorage.RemoteEvents:WaitForChild("BoostUpdated")
local BridgeNet2 = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))
local UpdateHUDBridge = BridgeNet2.ClientBridge("UpdateHUD")

local player = Players.LocalPlayer
local mainHUD = player:WaitForChild("PlayerGui"):WaitForChild("MainHUD")

local boostState = {}; local panelOpen = false; local liveGold = 0; local latestStats = {}
local activeTab = "Shop"

local function PlayUI(id) if shared.PlayUISound then shared.PlayUISound(id) end end
local function FormatTime(s) s = math.ceil(s or 0); if s <= 0 then return "0:00" end; return string.format("%d:%02d", math.floor(s/60), s % 60) end

---------------------------------------------------------------
-- ✨ MENU BUTTON
---------------------------------------------------------------
local BoostsBtn = Instance.new("ImageButton"); BoostsBtn.Name = "BoostsButton"; BoostsBtn.BackgroundColor3 = T.buttonPrimary; BoostsBtn.BorderSizePixel = 0; BoostsBtn.AutoButtonColor = false; BoostsBtn.ZIndex = 10
local Faded2 = mainHUD:FindFirstChild("Faded2")
if Faded2 then BoostsBtn.Parent = Faded2; BoostsBtn.Size = UDim2.new(0.85, 0, 0.85, 0); Instance.new("UIAspectRatioConstraint", BoostsBtn).AspectRatio = 1.0; local layout = Faded2:FindFirstChildOfClass("UIListLayout"); if not layout then layout = Instance.new("UIListLayout", Faded2); layout.HorizontalAlignment = Enum.HorizontalAlignment.Center; layout.VerticalAlignment = Enum.VerticalAlignment.Center; layout.Padding = UDim.new(0, 15); layout.SortOrder = Enum.SortOrder.LayoutOrder end; BoostsBtn.LayoutOrder = 3 
else BoostsBtn.Size = UDim2.new(0, 60, 0, 60); BoostsBtn.AnchorPoint = Vector2.new(1, 1); BoostsBtn.Position = UDim2.new(0.98, 0, 0.77, 0); BoostsBtn.Parent = mainHUD end
BoostsBtn:SetAttribute("TutorialTarget", "BoostsButton"); Instance.new("UICorner", BoostsBtn).CornerRadius = UDim.new(0.5, 0)
local bbStroke = Instance.new("UIStroke", BoostsBtn); bbStroke.Color = T.accentPurple; bbStroke.Thickness = 2
local boostIcon = Instance.new("ImageLabel", BoostsBtn); boostIcon.Size = UDim2.new(0.6, 0, 0.6, 0); boostIcon.Position = UDim2.new(0.2, 0, 0.2, 0); boostIcon.BackgroundTransparency = 1; boostIcon.ScaleType = Enum.ScaleType.Fit; boostIcon.Image = "rbxassetid://14916846070" 
CollectionService:AddTag(BoostsBtn, "Tutorial_BoostMenuBtn")

---------------------------------------------------------------
-- ✨ SHOP PANEL & TABS (Strictly Docked & Capped)
---------------------------------------------------------------
local ShopPanel = Instance.new("Frame"); ShopPanel.Name = "BoostShopPanel"
ShopPanel.Size = UDim2.new(0.9, 0, 0.60, 0) 
ShopPanel.AnchorPoint = Vector2.new(1, 1)
ShopPanel.Position = UDim2.new(1, -15, 2, 0) 
ShopPanel.BackgroundColor3 = T.panelBG; ShopPanel.BorderSizePixel = 0; ShopPanel.Visible = false; ShopPanel.ZIndex = 40; ShopPanel.ClipsDescendants = true; ShopPanel.Parent = mainHUD
CollectionService:AddTag(ShopPanel, "Tutorial_BoostShopPanel")
Instance.new("UICorner", ShopPanel).CornerRadius = UDim.new(0, 12)

-- ✨ THE FIX: Expanded MaxSize slightly to fill the gap
Instance.new("UISizeConstraint", ShopPanel).MaxSize = Vector2.new(360, 440) 

local shopStroke = Instance.new("UIStroke", ShopPanel); shopStroke.Color = Color3.fromRGB(255, 255, 255); shopStroke.Thickness = 1.5 

local ShopHeader = Instance.new("Frame"); ShopHeader.Name = "TitleBar"; ShopHeader.Size = UDim2.new(1, 0, 0, 40); ShopHeader.BackgroundColor3 = T.headerBG; ShopHeader.BorderSizePixel = 0; ShopHeader.ZIndex = 41; ShopHeader.Parent = ShopPanel; Instance.new("UICorner", ShopHeader).CornerRadius = UDim.new(0, 12)
local ShopTitle = Instance.new("TextLabel"); ShopTitle.Size = UDim2.new(1, -50, 1, 0); ShopTitle.Position = UDim2.new(0, 14, 0, 0); ShopTitle.BackgroundTransparency = 1; ShopTitle.Text = "BOOSTS"; ShopTitle.TextColor3 = T.headerText; ShopTitle.TextScaled = true; ShopTitle.Font = T.font; ShopTitle.TextXAlignment = Enum.TextXAlignment.Left; ShopTitle.ZIndex = 42; ShopTitle.Parent = ShopHeader
local ShopClose = Instance.new("TextButton"); ShopClose.Size = UDim2.new(0, 28, 0, 28); ShopClose.Position = UDim2.new(1, -36, 0.5, -14); ShopClose.BackgroundColor3 = T.buttonRed; ShopClose.BorderSizePixel = 0; ShopClose.Text = "X"; ShopClose.TextColor3 = Color3.fromRGB(255, 255, 255); ShopClose.TextScaled = true; ShopClose.Font = T.font; ShopClose.ZIndex = 9999; ShopClose.Parent = ShopHeader
CollectionService:AddTag(ShopClose, "Tutorial_BoostShopClose"); Instance.new("UICorner", ShopClose).CornerRadius = UDim.new(0, 5)

local TabContainer = Instance.new("Frame", ShopPanel)
TabContainer.Size = UDim2.new(1, 0, 0, 40); TabContainer.Position = UDim2.new(0, 0, 0, 40); TabContainer.BackgroundColor3 = T.headerBG; TabContainer.BorderSizePixel = 0; TabContainer.ZIndex = 41
local TabListLayout = Instance.new("UIListLayout", TabContainer); TabListLayout.FillDirection = Enum.FillDirection.Horizontal; TabListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center; TabListLayout.VerticalAlignment = Enum.VerticalAlignment.Center; TabListLayout.Padding = UDim.new(0, 10)

local shopTabBtn = Instance.new("TextButton", TabContainer); shopTabBtn.Size = UDim2.new(0.45, 0, 0.7, 0); shopTabBtn.BackgroundColor3 = T.buttonSecondary; shopTabBtn.Text = "SHOP"; shopTabBtn.TextColor3 = T.bodyText; shopTabBtn.Font = T.font; shopTabBtn.TextScaled = true; Instance.new("UICorner", shopTabBtn).CornerRadius = UDim.new(0, 6)
local invTabBtn = Instance.new("TextButton", TabContainer); invTabBtn.Size = UDim2.new(0.45, 0, 0.7, 0); invTabBtn.BackgroundColor3 = T.buttonSecondary; invTabBtn.Text = "INVENTORY"; invTabBtn.TextColor3 = T.bodyText; invTabBtn.Font = T.font; invTabBtn.TextScaled = true; Instance.new("UICorner", invTabBtn).CornerRadius = UDim.new(0, 6)

CollectionService:AddTag(shopTabBtn, "Tutorial_BoostTab_Shop")
CollectionService:AddTag(invTabBtn, "Tutorial_BoostTab_Inventory")

local ShopScroll = Instance.new("ScrollingFrame", ShopPanel); ShopScroll.Name = "ShopScroll"; ShopScroll.Size = UDim2.new(1, 0, 1, -80); ShopScroll.Position = UDim2.new(0, 0, 0, 80); ShopScroll.BackgroundTransparency = 1; ShopScroll.BorderSizePixel = 0; ShopScroll.ScrollBarThickness = 6; ShopScroll.Visible = true; Instance.new("UIListLayout", ShopScroll).Padding = UDim.new(0, 8); local spad = Instance.new("UIPadding", ShopScroll); spad.PaddingTop = UDim.new(0,8); spad.PaddingLeft = UDim.new(0,8); spad.PaddingRight = UDim.new(0,8)
local InvScroll = Instance.new("ScrollingFrame", ShopPanel); InvScroll.Name = "InvScroll"; InvScroll.Size = UDim2.new(1, 0, 1, -80); InvScroll.Position = UDim2.new(0, 0, 0, 80); InvScroll.BackgroundTransparency = 1; InvScroll.BorderSizePixel = 0; InvScroll.ScrollBarThickness = 6; InvScroll.Visible = false; Instance.new("UIListLayout", InvScroll).Padding = UDim.new(0, 8); local ipad = Instance.new("UIPadding", InvScroll); ipad.PaddingTop = UDim.new(0,8); ipad.PaddingLeft = UDim.new(0,8); ipad.PaddingRight = UDim.new(0,8)

local function AddButtonJuice(btn)
	local scale = btn:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", btn)
	btn.MouseEnter:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15), {Scale = 1.05}):Play() end)
	btn.MouseLeave:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15), {Scale = 1}):Play() end)
	btn.MouseButton1Down:Connect(function() TweenService:Create(scale, TweenInfo.new(0.1), {Scale = 0.95}):Play() end)
	btn.MouseButton1Up:Connect(function() TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), {Scale = 1.05}):Play() end)
end
AddButtonJuice(BoostsBtn); AddButtonJuice(ShopClose); AddButtonJuice(shopTabBtn); AddButtonJuice(invTabBtn)

local function SetActiveTab(tabName)
	activeTab = tabName
	if tabName == "Shop" then
		shopTabBtn.BackgroundColor3 = T.buttonPrimary; shopTabBtn.TextColor3 = T.bodyText
		invTabBtn.BackgroundColor3 = T.buttonSecondary; invTabBtn.TextColor3 = T.subText
		ShopScroll.Visible = true; InvScroll.Visible = false
	else
		shopTabBtn.BackgroundColor3 = T.buttonSecondary; shopTabBtn.TextColor3 = T.subText
		invTabBtn.BackgroundColor3 = T.buttonPrimary; invTabBtn.TextColor3 = T.bodyText
		ShopScroll.Visible = false; InvScroll.Visible = true
	end
end
SetActiveTab("Shop") 

shopTabBtn.MouseButton1Down:Connect(function()
	if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_BoostTab_Shop") then return end
	PlayUI(SoundConfig.UIClick or ""); SetActiveTab("Shop")
	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
end)
invTabBtn.MouseButton1Down:Connect(function()
	if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_BoostTab_Inventory") then return end
	PlayUI(SoundConfig.UIClick or ""); SetActiveTab("Inventory")
	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
end)

local cardRefs = {}

local function BuildCards()
	for i, boostId in ipairs(BoostConfig.ShopOrder) do
		local cfg = BoostConfig.Get(boostId); if not cfg then continue end; local color = cfg.color

		local sCard = Instance.new("Frame", ShopScroll); sCard.Size = UDim2.new(1, -8, 0, 75); sCard.BackgroundColor3 = T.cardBG; sCard.BorderSizePixel = 0; Instance.new("UICorner", sCard).CornerRadius = UDim.new(0, 8)
		local sIcon = Instance.new("ImageLabel", sCard); sIcon.Size = UDim2.new(0, 36, 0, 36); sIcon.Position = UDim2.new(0, 10, 0.5, -18); sIcon.BackgroundTransparency = 1; sIcon.Image = cfg.icon or ""; sIcon.ImageColor3 = color; sIcon.ScaleType = Enum.ScaleType.Fit
		local sName = Instance.new("TextLabel", sCard); sName.Size = UDim2.new(0.5, 0, 0, 18); sName.Position = UDim2.new(0, 56, 0, 10); sName.BackgroundTransparency = 1; sName.Text = string.upper(cfg.displayName or boostId); sName.TextColor3 = T.bodyText; sName.TextScaled = true; sName.Font = T.font; sName.TextXAlignment = Enum.TextXAlignment.Left
		local sDesc = Instance.new("TextLabel", sCard); sDesc.Size = UDim2.new(0.5, 0, 0, 30); sDesc.Position = UDim2.new(0, 56, 0, 30); sDesc.BackgroundTransparency = 1; sDesc.Text = cfg.description or ""; sDesc.TextColor3 = T.subText; sDesc.TextScaled = true; sDesc.TextWrapped = true; sDesc.Font = T.fontBody; sDesc.TextXAlignment = Enum.TextXAlignment.Left; sDesc.TextYAlignment = Enum.TextYAlignment.Top

		local buyBtn = Instance.new("TextButton", sCard); buyBtn.Size = UDim2.new(0, 75, 0, 34); buyBtn.Position = UDim2.new(1, -85, 0.5, -17); buyBtn.BackgroundColor3 = T.buttonGreen; buyBtn.BorderSizePixel = 0; buyBtn.TextScaled = true; buyBtn.Font = T.font; buyBtn.TextColor3 = Color3.fromRGB(255, 255, 255); Instance.new("UICorner", buyBtn).CornerRadius = UDim.new(0, 6); CollectionService:AddTag(buyBtn, "Tutorial_BuyBoost_" .. boostId); AddButtonJuice(buyBtn)

		local iCard = Instance.new("Frame", InvScroll); iCard.Size = UDim2.new(1, -8, 0, 75); iCard.BackgroundColor3 = T.cardBG; iCard.BorderSizePixel = 0; Instance.new("UICorner", iCard).CornerRadius = UDim.new(0, 8)
		local iIcon = Instance.new("ImageLabel", iCard); iIcon.Size = UDim2.new(0, 36, 0, 36); iIcon.Position = UDim2.new(0, 10, 0.5, -18); iIcon.BackgroundTransparency = 1; iIcon.Image = cfg.icon or ""; iIcon.ImageColor3 = color; iIcon.ScaleType = Enum.ScaleType.Fit
		local iName = Instance.new("TextLabel", iCard); iName.Size = UDim2.new(0.5, 0, 0, 18); iName.Position = UDim2.new(0, 56, 0, 10); iName.BackgroundTransparency = 1; iName.Text = string.upper(cfg.displayName or boostId); iName.TextColor3 = T.bodyText; iName.TextScaled = true; iName.Font = T.font; iName.TextXAlignment = Enum.TextXAlignment.Left

		-- ✨ THE FIX: Status (ACTIVE) sits neatly under Owned
		local iOwned = Instance.new("TextLabel", iCard); iOwned.Size = UDim2.new(0.5, 0, 0, 14); iOwned.Position = UDim2.new(0, 56, 0, 30); iOwned.BackgroundTransparency = 1; iOwned.Text = "Owned: 0"; iOwned.TextColor3 = T.accentGold; iOwned.TextScaled = true; iOwned.Font = T.fontBody; iOwned.TextXAlignment = Enum.TextXAlignment.Left
		local iStatus = Instance.new("TextLabel", iCard); iStatus.Size = UDim2.new(0.5, 0, 0, 14); iStatus.Position = UDim2.new(0, 56, 0, 46); iStatus.BackgroundTransparency = 1; iStatus.Text = "Inactive"; iStatus.TextColor3 = T.subText; iStatus.TextScaled = true; iStatus.Font = T.fontBody; iStatus.TextXAlignment = Enum.TextXAlignment.Left

		-- ✨ THE FIX: Massive, bold timer directly to the left of the button!
		local iTimer = Instance.new("TextLabel", iCard); iTimer.Size = UDim2.new(0, 65, 0, 30); iTimer.Position = UDim2.new(1, -160, 0.5, -15); iTimer.BackgroundTransparency = 1; iTimer.Text = ""; iTimer.TextColor3 = color; iTimer.TextScaled = true; iTimer.Font = Enum.Font.FredokaOne; iTimer.TextXAlignment = Enum.TextXAlignment.Right

		local actBtn = Instance.new("TextButton", iCard); actBtn.Size = UDim2.new(0, 75, 0, 34); actBtn.Position = UDim2.new(1, -85, 0.5, -17); actBtn.BackgroundColor3 = color; actBtn.BorderSizePixel = 0; actBtn.TextScaled = true; actBtn.Font = T.font; actBtn.TextColor3 = Color3.fromRGB(255, 255, 255); Instance.new("UICorner", actBtn).CornerRadius = UDim.new(0, 6); CollectionService:AddTag(actBtn, "Tutorial_UseBoost_" .. boostId); AddButtonJuice(actBtn)

		cardRefs[boostId] = { sCard=sCard, iCard=iCard, buyBtn=buyBtn, actBtn=actBtn, sDesc=sDesc, iOwned=iOwned, iStatus=iStatus, iTimer=iTimer }

		buyBtn.MouseButton1Down:Connect(function() 
			if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_BuyBoost_" .. boostId) then return end
			local isUnlocked = AchievementConfig.IsBoostUnlocked(boostId, latestStats)
			local cost = cfg and cfg.cost or 0
			if not isUnlocked or liveGold < cost then PlayUI(SoundConfig.ErrorBuzz or ""); return end
			BuyBoost:FireServer(boostId) 
			if type(shared.TutorialRecordBoostBought) == "function" then shared.TutorialRecordBoostBought(boostId) end
			if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
		end)

		actBtn.MouseButton1Down:Connect(function()
			if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_UseBoost_" .. boostId) then return end
			local isUnlocked = AchievementConfig.IsBoostUnlocked(boostId, latestStats)
			local state = boostState[boostId]
			local activeCount = state and (state.activeCount or 0) or 0
			local atCap = activeCount >= (cfg and cfg.maxStack or 1)
			if not isUnlocked or not state or (state.inventoryCount or 0) <= 0 or atCap then PlayUI(SoundConfig.ErrorBuzz or ""); return end
			ActivateBoost:FireServer(boostId)
			if type(shared.TutorialRecordBoostUsed) == "function" then shared.TutorialRecordBoostUsed(boostId) end
			if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
		end)
	end
end

BuildCards()

local function RefreshCards()
	for boostId, refs in pairs(cardRefs) do
		local cfg = BoostConfig.Get(boostId); local state = boostState[boostId]
		local isUnlocked, lockReason = AchievementConfig.IsBoostUnlocked(boostId, latestStats)
		local cost = cfg and cfg.cost or 0; local canAfford = liveGold >= cost
		local invCount = state and (state.inventoryCount or 0) or 0

		if not isUnlocked then
			refs.buyBtn.Text = "LOCKED"; refs.buyBtn.BackgroundColor3 = T.buttonRed; refs.buyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
			refs.sDesc.Text = lockReason; refs.sDesc.TextColor3 = T.buttonRed
		else
			refs.sDesc.Text = cfg.description or ""; refs.sDesc.TextColor3 = T.subText
			refs.buyBtn.Text = cost .. " ⭐"; refs.buyBtn.TextColor3 = Color3.fromRGB(255, 255, 255); refs.buyBtn.BackgroundColor3 = canAfford and T.buttonGreen or T.buttonDisabled
		end

		refs.iOwned.Text = "Owned: " .. invCount
		refs.iOwned.TextColor3 = invCount > 0 and T.accentGold or T.subText
	end
end

local function OpenPanel()
	panelOpen = true; ShopPanel.Visible = true; RefreshCards()
	-- ✨ THE FIX: Docked at -15 on the Y-axis so the bottom edge perfectly rests at the bottom margin of the screen!
	TweenService:Create(ShopPanel, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(1, -15, 1, -15) }):Play()
end

local function ClosePanel()
	panelOpen = false; PlayUI(SoundConfig.UIClose)
	local tween = TweenService:Create(ShopPanel, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.new(1, -15, 2, 0) })
	tween:Play(); tween.Completed:Once(function() if not panelOpen then ShopPanel.Visible = false end end)
end

BoostsBtn.MouseButton1Down:Connect(function() 
	if panelOpen then if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_CloseBoostShop") then return end; ClosePanel()
	else if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_OpenBoostShop") then return end; OpenPanel() end 
	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
end)
ShopClose.MouseButton1Down:Connect(function()
	if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_CloseBoostShop") then return end; ClosePanel()
	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
end)

BoostUpdated.OnClientEvent:Connect(function(state)
	if state._goldenAuras ~= nil then liveGold = state._goldenAuras; state._goldenAuras = nil end
	boostState = state; if panelOpen then RefreshCards() end
end)

UpdateHUDBridge:Connect(function(stats)
	for key, value in pairs(stats) do latestStats[key] = value end
	if stats.goldenAuras ~= nil then liveGold = stats.goldenAuras end
	if stats.boostInventory then for boostId, count in pairs(stats.boostInventory) do if boostState[boostId] then boostState[boostId].inventoryCount = count end end end
	if panelOpen then RefreshCards() end
end)

RunService.RenderStepped:Connect(function(dt)
	-- ✨ Auto-skim past Step 33 if the Shop is already Open!
	if panelOpen and type(shared.TutorialCanPerform) == "function" and shared.TutorialCanPerform("Action_OpenBoostShop") then
		if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
	end

	for _, boostId in ipairs(BoostConfig.ShopOrder) do
		local state = boostState[boostId]; local refs = cardRefs[boostId]; if not refs then continue end
		local activeCount, minTime = 0, 0

		if state and state.activeTimes and #state.activeTimes > 0 then
			local clean = {}; minTime = math.huge
			for _, t in ipairs(state.activeTimes) do
				local newT = math.max(0, t - dt)
				if newT > 0 then table.insert(clean, newT); if newT < minTime then minTime = newT end end
			end
			state.activeTimes = clean; state.activeCount = #clean; activeCount = #clean
		end

		local isUnlocked = AchievementConfig.IsBoostUnlocked(boostId, latestStats)
		if not isUnlocked then
			refs.actBtn.Text = "LOCKED"; refs.actBtn.BackgroundColor3 = T.buttonRed; refs.actBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
			refs.iStatus.Text = "Unlock in Progression Menu"; refs.iStatus.TextColor3 = T.buttonRed
			refs.iTimer.Text = ""
		else
			local invCount = state and (state.inventoryCount or 0) or 0
			local atCap = activeCount >= (BoostConfig.Get(boostId).maxStack or 1)

			if activeCount > 0 then 
				refs.iStatus.Text = "ACTIVE" .. (activeCount > 1 and (" (x"..activeCount..")") or "")
				refs.iStatus.TextColor3 = BoostConfig.Get(boostId).color
				refs.iTimer.Text = FormatTime(minTime)
			else 
				refs.iStatus.Text = "Inactive"
				refs.iStatus.TextColor3 = T.subText 
				refs.iTimer.Text = ""
			end

			if invCount <= 0 then 
				refs.actBtn.Text = "NO STOCK"; refs.actBtn.BackgroundColor3 = T.buttonDisabled; refs.actBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
			elseif atCap then 
				refs.actBtn.Text = "MAXED"; refs.actBtn.BackgroundColor3 = T.buttonDisabled; refs.actBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
			else 
				refs.actBtn.Text = "ACTIVATE"; refs.actBtn.BackgroundColor3 = BoostConfig.Get(boostId).color; refs.actBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
			end
		end
	end
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- ✨ REFRESH LOOK (Matches your ShopController flair and stroke)
-- ─────────────────────────────────────────────────────────────────────────────
local shopShine    = nil
local titleFlair   = nil
local flairedExtra = false

local function RefreshLook()
	UITheme.Apply(ShopPanel, "Panel")
	UITheme.Apply(ShopHeader, "TitleBar")

	if not shopShine then
		shopShine  = UITheme.ApplyShine(ShopPanel)
		UITheme.ApplyShine(ShopHeader)
	end

	if not titleFlair then
		titleFlair = UITheme.ApplyFlair(ShopTitle, "Ghost")
	end

	if not flairedExtra then flairedExtra = true end

	for _, scrollName in ipairs({ "ShopScroll", "InvScroll" }) do
		local scroll = ShopPanel:FindFirstChild(scrollName)
		if scroll then
			local layout = scroll:FindFirstChildOfClass("UIListLayout")
			if layout then layout.SortOrder = Enum.SortOrder.LayoutOrder end
		end
	end

	local outerStroke = ShopPanel:FindFirstChildWhichIsA("UIStroke")
	if outerStroke then outerStroke.Color = Color3.fromRGB(255, 255, 255) end

	for _, card in ipairs(ShopScroll:GetChildren()) do if card:IsA("Frame") then UITheme.Apply(card, "ShopCard") end end
	for _, card in ipairs(InvScroll:GetChildren()) do if card:IsA("Frame") then UITheme.Apply(card, "ShopCard") end end
end

task.wait(2)
RefreshLook()

local forceClose = ReplicatedStorage:FindFirstChild("ForceCloseUI") or Instance.new("BindableEvent")
forceClose.Name = "ForceCloseUI"; forceClose.Parent = ReplicatedStorage
forceClose.Event:Connect(function() if panelOpen then ClosePanel() end end)


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

local HabitatFull    = ReplicatedStorage.RemoteEvents:WaitForChild("HabitatFull")

-- ✨ BRIDGENET2 UPGRADES
local BridgeNet2             = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))
local UpdateHUDBridge        = BridgeNet2.ServerBridge("UpdateHUD")
local ProduceAuraBridge      = BridgeNet2.ServerBridge("ProduceAura")
local AuraSpawnedBridge      = BridgeNet2.ServerBridge("AuraSpawned")
local UpdateHatcheryBridge   = BridgeNet2.ServerBridge("UpdateHatchery")
local CubeMutatedBatchBridge = BridgeNet2.ServerBridge("CubeMutatedBatch")
local CubeSmushedBridge      = BridgeNet2.ServerBridge("CubeSmushed")
local CubeStoredBridge       = BridgeNet2.ServerBridge("CubeStored")

local HABITAT_HOLDER = workspace:WaitForChild("HabitatHolder")
local HABITAT_PART   = HABITAT_HOLDER:WaitForChild("Position")
local AURA_HOLDER    = workspace:WaitForChild("AuraHolder") 

local lastFire          = {}
local holdStart         = {}
local hatchery          = {}

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
end)

Players.PlayerRemoving:Connect(function(p)
	hatchery[p.UserId]=nil; holdStart[p.UserId]=nil; lastFire[p.UserId]=nil
end)

task.spawn(function()
	local PR = ServerScriptService:WaitForChild("PrestigeReset", 30)
	if PR then
		PR.Event:Connect(function(player)
			local uid = player.UserId
			local data = GameManager.GetData(uid)
			hatchery[uid] = data and GetHatcheryMax(data) or AdminConfig.HatcheryMax
			holdStart[uid]=nil; lastFire[uid]=nil
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
				UpdateHatcheryBridge:Fire(player, { current=hatchery[uid], max=hatchMax })
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

	local storedCount = runtime.storedCubeCount or 0
	local activeMV = runtime.activeMutatedValue or 0

	local boostMult = BoostManager.GetValueMultiplier(uid) * BoostManager.GetSpawnRateMultiplier(uid)
	local displayRate = math.floor(activeMV * boostMult)

	local passTickCfg = UpgradeConfig.GetUpgradeConfig("passiveTickSpeed")
	local passInt = (passTickCfg and passTickCfg.apply) and passTickCfg.apply(data) or AdminConfig.PassiveInterval

	UpdateHUDBridge:Fire(player, {
		currency        = data.currency, 
		pendingAuras    = storedCount, 
		habitatCapacity = GetHabitatCapacity(data), 
		rate            = displayRate,
		passiveInterval = passInt, 
		totalEarned     = data.totalEarned or 0,
		soulAuras       = data.soulAuras or 0, 
		farmEvaluation  = data.farmEvaluation or 0,
		goldenAuras     = data.goldenAuras or 0, 
		boostInventory  = data.boostInventory or {},
		prestigeCount   = data.prestigeCount or 0,
		upgrades        = data.upgrades or {},
		totalCubesProduced = data.totalCubesProduced or 0,
		currentArea     = data.currentArea or 1,
		discoveredTiers = data.discoveredTiers or {}
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
						cubeId = cubeId, mutationType = "valueBonus", bonusLevel = nl, 
						bonusPercent = be and math.floor(be.bonus * 100) or 0 
					})
				end

				local maxTier = AdminConfig.MutationMaxTierIndex or 3
				local upgrades = 0

				while cube.tierIndex < maxTier and cube.tierIndex < #TierConfig.Tiers and upgrades < 5 do
					if areaModels then
						local nextTierName = TierConfig.Tiers[cube.tierIndex + 1].name
						if not areaModels[nextTierName] then break end
					end

					local timeSince = cube.effectiveElapsed - (cube.lastUpgradeElapsed or 0)
					local bestChance, bestTime = 0, 0
					for _, threshold in ipairs(MutationConfig.TierUpgrades) do
						if timeSince >= threshold.time then bestChance = threshold.chance; bestTime = threshold.time end
					end

					if bestChance <= 0 then break end

					if math.random() <= bestChance then
						local oldTier = TierConfig.Tiers[cube.tierIndex]
						cube.tierIndex += 1
						local newTier = TierConfig.Tiers[cube.tierIndex]
						cube.baseValue = math.floor(cube.baseValue * (newTier.multiplier/oldTier.multiplier))
						cube.color = newTier.color; cube.glow = newTier.glow; cube.tierName = newTier.name
						cube.lastUpgradeElapsed = (cube.lastUpgradeElapsed or 0) + bestTime
						upgrades += 1; mutated = true

						table.insert(mutationBatch, { 
							cubeId = cubeId, mutationType = "tierUpgrade",
							newColor = newTier.color, newGlow = newTier.glow, 
							tierName = newTier.name, currentArea = currentArea
						})

						if newTier.name == "Legendary" then data.totalLegendaryCubes = (data.totalLegendaryCubes or 0) + 1 end
					else break end
				end

				if mutated then
					local newMutatedValue = MutationConfig.GetMutatedValue(cube)
					runtime.totalMutatedValue = (runtime.totalMutatedValue or 0) + (newMutatedValue - oldMutatedValue)
					if not cube.isStored then runtime.activeMutatedValue = (runtime.activeMutatedValue or 0) + (newMutatedValue - oldMutatedValue) end
				end
			end

			if #mutationBatch > 0 then CubeMutatedBatchBridge:Fire(player, mutationBatch) end
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
	local tierUnlocks = {
		{ upgradeId = "unlockOmniMult", tier = 10 }, { upgradeId = "unlockUniversalMult", tier = 9 },
		{ upgradeId = "unlockGodlyMult", tier = 8 }, { upgradeId = "unlockCosmicMult", tier = 7 },
		{ upgradeId = "unlockMythicMult", tier = 6 },
	}

	for _, tData in ipairs(tierUnlocks) do
		local lvl = upgrades[tData.upgradeId]
		local finalLvl = (typeof(lvl) == "table" and lvl.level) or (typeof(lvl) == "number" and lvl) or 0
		if finalLvl > 0 then playerMaxTier = tData.tier; break end
	end

	local effectiveTime = holdTime * playerMultSpeed
	local currentTier = 1

	for i = 1, playerMaxTier do
		if AdminConfig.MilestoneData[i] and effectiveTime >= AdminConfig.MilestoneData[i].time then currentTier = i end
	end

	local nextTier = math.min(currentTier + 1, playerMaxTier)
	if currentTier == playerMaxTier then return AdminConfig.MilestoneData[currentTier].mult, AdminConfig.MilestoneData[currentTier].luck end

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
	for _, e in ipairs(adjusted) do cum += e.chance; if r <= cum then return e.tier end end
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
			if areaModels[checkName] then break end
			tierIndex -= 1
		end
		tier = TierConfig.Tiers[tierIndex] 
	end

	local totalValueMultiplier = 1.0 
	local valueUpgrades = {"blockValue", "blockValueT2", "auraValueT3", "auraValueT4", "auraValueT6", "auraValueT8", "auraValueT10"}

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

	local cubeRecord = { spawnTime=tick(), effectiveElapsed=0, lastUpgradeElapsed=0, baseValue=totalValue, tierIndex=tierIndex, tierName=tier.name, color=tier.color, glow=tier.glow, isStored=false, currentArea=currentArea }

	if AdminConfig.MutationInstantMax then
		local mb = MutationConfig.ValueBonuses[#MutationConfig.ValueBonuses]
		if mb then cubeRecord.effectiveElapsed = mb.time + 1 end
	end

	local cubeId = GameManager.AddCube(uid, cubeRecord)
	if not cubeId then return end

	data.totalCubesProduced = (data.totalCubesProduced or 0) + 1
	if tier.name == "Legendary" then data.totalLegendaryCubes = (data.totalLegendaryCubes or 0) + 1 end
	runtime.lastActiveTime = tick()

	AuraSpawnedBridge:Fire(player, { cubeId=cubeId, tier=tier.name, color=tier.color, glow=tier.glow, value=totalValue, spawnPos=spawnPos, currentArea = currentArea })
end

ProduceAuraBridge:Connect(function(player, action)
	local uid = player.UserId
	local now = tick()
	local data = GameManager.GetData(uid)
	local runtime = GameManager.GetRuntime(uid)

	if action == "start" then 
		if data and runtime then
			local storedCount = runtime.storedCubeCount or 0
			if storedCount >= GetHabitatCapacity(data) then HabitatFull:FireClient(player); return end
		end
		if (hatchery[uid] or 0) > 0.5 then holdStart[uid] = now 
		else UpdateHatcheryBridge:Fire(player, { current = 0, max = data and GetHatcheryMax(data) or AdminConfig.HatcheryMax }) end
		return 
	end

	if action == "stop" then holdStart[uid] = nil; return end
	if not data or not runtime then return end

	local capacity = GetHabitatCapacity(data)
	local storedCount = runtime.storedCubeCount or 0

	if storedCount >= capacity then HabitatFull:FireClient(player); return end
	if runtime.cubeCount >= capacity + 150 then return end 

	if (hatchery[uid] or 0) <= 0.5 then 
		UpdateHatcheryBridge:Fire(player, { current = 0, max = data and GetHatcheryMax(data) or AdminConfig.HatcheryMax })
		return 
	end
	if not holdStart[uid] then return end

	local rushMult = BoostManager.GetSpawnRateMultiplier(uid)
	local weatherSpawnMult, _ = WeatherManager.GetMultipliers(uid)
	local effectiveFireRate = AdminConfig.FireRate / (rushMult * weatherSpawnMult)
	local spawnCount = 1

	if effectiveFireRate < 0.05 then
		spawnCount = math.floor(0.05 / effectiveFireRate)
		effectiveFireRate = 0.05
	end

	-- ✨ THE FIX: We now let the Client smoothly manage the dynamic spawn rate delay.
	-- This block acts as a basic anti-exploit sanity check (max 25 requests/sec) to ensure 
	-- the server and client never desync or lock up when a boost multiplier expires!
	if lastFire[uid] then
		local timeSinceLast = now - lastFire[uid]
		if timeSinceLast < 0.04 then return end 
	end
	lastFire[uid] = now

	local holdTime = now - holdStart[uid]
	local holdMult, luckBonus = GetHoldMultiplier(holdTime, data)

	for i = 1, spawnCount do SpawnAura(player, data, runtime, holdMult, luckBonus) end
	SendHUDUpdate(player)
	UpdateHatcheryBridge:Fire(player, { current=hatchery[uid], max=GetHatcheryMax(data) })
end)

CubeStoredBridge:Connect(function(player, cubeId)
	local uid = player.UserId
	local runtime = GameManager.GetRuntime(uid)
	local data = GameManager.GetData(uid)
	if runtime and runtime.cubes[cubeId] then
		GameManager.MarkCubeStored(uid, cubeId)
		SendHUDUpdate(player)
		local storedCount = runtime.storedCubeCount or 0
		if storedCount >= GetHabitatCapacity(data) then HabitatFull:FireClient(player) end
	end
end)

CubeSmushedBridge:Connect(function(player, cubeId)
	local uid = player.UserId
	GameManager.RemoveCube(uid, cubeId)
	SendHUDUpdate(player)
	local data = GameManager.GetData(uid)
	UpdateHatcheryBridge:Fire(player, { current = hatchery[uid], max = GetHatcheryMax(data) })
end)


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
		color        = Color3.fromRGB(143, 255, 131), 
	},

	-- ✨ STEP 2: Cinematic Camera Follow
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

		cameraTarget = "Tutorial_AuraHolderCam",

		requireCubesProduced = 25,
		failsafeDuration = 35, 
		bannerTitle  = "Producing Auras",
		bannerBody   = "Keep clicking to produce 25 Auras! The more you make, the more money you earn.",
		duration     = 0, 

		icon         = "rbxassetid://14914018910",
		color        = Color3.fromRGB(130, 226, 255), 
	},

	-- ✨ STEP 4: Farm up Cash
	[4] = {
		id           = "a1_farm_150",
		action       = "Action_ClickRedButton",

		requireCurrency = 150,

		bannerTitle  = "Stacking Cash",
		bannerBody   = "Your Auras are passively generating income while on the Conveyer. Keep producing until you save up $150!",
		duration     = 0,
		failsafeDuration = 25, 
		icon         = "rbxassetid://14924185885",
		color        = Color3.fromRGB(150, 255, 150), 
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
		color        = Color3.fromRGB(123, 216, 250),
	},

	-- ✨ STEP 6: First Upgrade
	[6] = {
		id             = "a1_buy_blockValue",
		action         = "Action_BuyUpgrade",
		targetTag      = "Tutorial_Buy_blockValue",

		unlockTags     = {"Tutorial_Buy_blockValue"},

		menuTag        = "Tutorial_ShopPanel",
		menuOpenBtnTag = "Tutorial_ShopButton",

		bannerTitle  = "Increase Value",
		bannerBody   = "Buy the Value upgrade to increase the Value of your Auras by +10%",

		icon         = "rbxassetid://14917128076",
		color        = Color3.fromRGB(142, 206, 255), 
	},

	-- ✨ STEP 7: Habitat Fill
	[7] = {
		id           = "a1_fill_habitat",
		action       = "Action_ClickRedButton",
		targetTag    = "Tutorial_ClickButton",

		requireHabitatFull = true,
		duration           = 0, 

		bannerTitle  = "Keep Producing",
		bannerBody   = "Close the shop and keep Producing Auras. Spam Click or HOLD the red button To keep producing Auras.",

		icon         = "rbxassetid://14914018910",
		color        = Color3.fromRGB(130, 226, 255),
	},

	-- ✨ STEP 8: Watch Aura Die
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
		color        = Color3.fromRGB(255, 0, 4), 
	},

	-- ✨ STEP 9: Pan to Habitat
	[9] = {
		id           = "a1_look_at_habitat",
		action       = "Action_Wait",
		cameraTarget = "Tutorial_HabitatCam",

		duration     = 7, 

		bannerTitle  = "Habitat is Full!",
		bannerBody   = "Your storage is completely Full. You need to clear some Space.",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(255, 155, 155), 
	},

	-- ✨ STEP 10: Send Ship
	[10] = {
		id           = "a1_send_ship",
		action       = "Action_SendShip",
		targetTag    = "Tutorial_SendShipBtn",

		unlockTags    = {"Tutorial_SendShipBtn"},
		unlockActions = {"Action_SendShip"},

		bannerTitle  = "Clear Space",
		bannerBody   = "Click the newly unlocked SEND button to clear out your habitat of the Auras.",

		icon         = "rbxassetid://14915225073",
		color        = Color3.fromRGB(100, 255, 255), 
	},

	-- ✨ STEP 11: Watch Ship
	[11] = {
		id           = "a1_wait_for_ship",
		action       = "Action_Wait",
		cameraTarget = "Tutorial_ShippingCam",

		requirePlatformsShipped = 2,

		bannerTitle  = "Ship Delivery",
		bannerBody   = "Ships collect all your Auras and pay out the cash directly to your wallet. Send 2 Ships Out.",
		duration     = 0,

		icon         = "rbxassetid://14914018910",
		color        = Color3.fromRGB(150, 200, 255), 
	},

	-- ✨ STEP 12: Auto Ship
	[12] = {
		id           = "a1_toggle_auto",
		action       = "Action_ToggleAutoShip",
		targetTag    = "Tutorial_ToggleShipBtn",

		unlockTags    = {"Tutorial_ToggleShipBtn"},
		unlockActions = {"Action_ToggleAutoShip"},

		bannerTitle  = "Automate Ships",
		bannerBody   = "Click the new unlocked Toggle Button to automate your shipments!",

		icon         = "rbxassetid://14915225073",
		color        = Color3.fromRGB(50, 150, 50), 
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
		color        = Color3.fromRGB(150, 255, 150),
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
		color        = Color3.fromRGB(137, 255, 110), 
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

		unlockTags     = {"Tutorial_PrestigeConfirm"},
		unlockActions  = {"Action_PrestigeConfirm"},

		menuTag        = "Tutorial_PrestigePanel",
		menuOpenBtnTag = "Tutorial_PrestigeButton",

		bannerTitle  = "Confirm Prestige",
		bannerBody   = "Click 'Prestige Now' to get your Soul Auras and increase your earnings permentantly.",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(215, 121, 255),
	},
	[23] = {
		id           = "a1_post_prestige_pan",
		action       = "Action_Wait", 
		duration     = 0,             
		allowClicking = true, 
		cameraTrackMode = "FollowPhysicsAura", 
		cameraOffset    = Vector3.new(0, 15, 25), 

		requireStepGoldenAuras = 10, 

		bannerTitle  = "Golden Auras",
		bannerBody   = "Collect Auras that spawn from the Producer OR claim your mailbox rewards!",

		icon         = "rbxassetid://4483362458",
		color        = Color3.fromRGB(255, 215, 0),
	},

	-- ✨ STEP 24: Farm for the next area
	[24] = {
		id           = "a1_farm_area2",
		action       = "Action_Wait", 
		duration     = 0,             
		allowClicking = true, 
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

	-- ✨ STEP 26: Browse to Area 2
	[26] = {
		id             = "a1_travel_arrow",
		action         = "Action_ClickRightArrow",
		targetTag      = "Tutorial_RightArrow",

		unlockTags     = {"Tutorial_RightArrow"},
		unlockActions  = {"Action_ClickRightArrow", "Action_ClickLeftArrow"},

		menuTag        = "Tutorial_TravelPanel",
		menuOpenBtnTag = "Tutorial_TravelButton",
		fallbackStepId = "a1_open_travel", 

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

	-- ✨ STEP 28: Open Boost Shop
	[28] = {
		id           = "a1_open_boosts",
		action       = "Action_OpenBoostShop",
		targetTag    = "Tutorial_BoostMenuBtn",

		unlockTags    = {"Tutorial_BoostMenuBtn", "Tutorial_BoostShopClose", "Tutorial_BoostTab_Shop", "Tutorial_BoostTab_Inventory"},
		unlockActions = {"Action_OpenBoostShop", "Action_CloseBoostShop", "Action_BoostTab_Shop", "Action_BoostTab_Inventory"},

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

		bannerTitle  = "Buy a Boost",
		bannerBody   = "Buy the Aura Rush Boost using your Golden Auras.",

		icon         = "rbxassetid://4483362458",
		color        = Color3.fromRGB(114, 213, 255),
	},

	-- ✨ STEP 30: Switch to Inventory Tab
	[30] = {
		id           = "a1_click_inv_tab",
		action       = "Action_BoostTab_Inventory",
		targetTag    = "Tutorial_BoostTab_Inventory",

		menuTag        = "Tutorial_BoostShopPanel",
		menuOpenBtnTag = "Tutorial_BoostMenuBtn",

		bannerTitle  = "Check Inventory",
		bannerBody   = "Click the INVENTORY tab at the top of the menu to view the boosts you own.",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(103, 111, 255),
	},

	-- ✨ STEP 31: Use Aura Spawner Boost
	[31] = {
		id           = "a1_use_boost1",
		action       = "Action_UseBoost_AuraRush",
		targetTag    = "Tutorial_UseBoost_AuraRush",

		unlockTags    = {"Tutorial_UseBoost_AuraRush"},
		unlockActions = {"Action_UseBoost_AuraRush"},

		menuTag        = "Tutorial_BoostShopPanel",
		menuOpenBtnTag = "Tutorial_BoostMenuBtn",

		requireBoostUsed = { id = "AuraRush", count = 1 },

		bannerTitle  = "Activate the Boost",
		bannerBody   = "Click ACTIVATE to use your new Aura Rush boost!",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(103, 111, 255),
	},

	-- ✨ STEP 32: Spawn 30 Auras (FIXED BUG: targetTag Removed)
	[32] = {
		id           = "a1_spawn_30",
		action       = "Action_Wait", 
		-- ✨ THE FIX: Removed targetTag so the FSM doesn't infinitely wait for a click!
		allowClicking = true, 

		requireCubesProduced = 30,
		duration = 0,
		bannerTitle  = "Double Spawn Speed",
		bannerBody   = "Your boost is now active. Produce 30 Auras with the increased spawn speed.",

		icon         = "rbxassetid://14914018910",
		color        = Color3.fromRGB(105, 255, 200),
	},

	-- ✨ STEP 33: Open Boost Shop Again
	[33] = {
		id           = "a1_open_boosts2",
		action       = "Action_OpenBoostShop",
		targetTag    = "Tutorial_BoostMenuBtn",
			
		bannerTitle  = "Buy More Boosts",
		bannerBody   = "Open up the boosts menu again to buy more boosts.",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(106, 255, 188),
	},

	-- ✨ STEP 34: Switch back to Shop Tab
	[34] = {
		id           = "a1_click_shop_tab",
		action       = "Action_BoostTab_Shop",
		targetTag    = "Tutorial_BoostTab_Shop",

		menuTag        = "Tutorial_BoostShopPanel",
		menuOpenBtnTag = "Tutorial_BoostMenuBtn",

		bannerTitle  = "Return to Shop",
		bannerBody   = "Click the SHOP tab to view the boosts available for purchase.",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(114, 213, 255),
	},

	-- ✨ STEP 35: Buy 5 Aura Spawners
	[35] = {
		id           = "a1_buy_boost3",
		action       = "Action_BuyBoost_AuraRush",
		targetTag    = "Tutorial_BuyBoost_AuraRush",

		menuTag        = "Tutorial_BoostShopPanel",
		menuOpenBtnTag = "Tutorial_BoostMenuBtn",

		requireBoostBought = { id = "AuraRush", count = 5 },

		bannerTitle  = "Buy More Aura Rush Boosts",
		bannerBody   = "Buy 5 more Aura Rush Boosts. Note Boosts can stack for even faster production and MONEY.",

		icon         = "rbxassetid://4483362458",
		color        = Color3.fromRGB(101, 255, 199),
	},

	-- ✨ STEP 36: Mass Produce 150 Auras (FIXED BUG: targetTag Removed)
	[36] = {
		id           = "a1_spawn_150",
		action       = "Action_Wait",
		-- ✨ THE FIX: Removed targetTag so FSM doesn't get stuck!
		allowClicking = true, 
		duration = 0,
		requireCubesProduced = 150,

		bannerTitle  = "Mass Production",
		bannerBody   = "Produce 150 Auras. Don't forget you can use those boosts you just bought!",

		icon         = "rbxassetid://14914018910",
		color        = Color3.fromRGB(130, 226, 255),
	},

	-- ✨ STEP 37: Open Achievements
	[37] = {
		id           = "a1_open_achievements",
		action       = "Action_OpenAchievements",
		targetTag    = "Tutorial_AchieveMenuBtn",

		unlockTags    = {"Tutorial_AchieveMenuBtn", "Tutorial_AchieveCloseBtn", "Tutorial_AchieveTab_Challenges"},
		unlockActions = {"Action_OpenAchievements", "Action_CloseAchievements", "Action_ClickAchieveTab_Challenges"},

		bannerTitle  = "Achievements Unlocked!",
		bannerBody   = "You've hit a major milestone! Click the new Achievements button to view your Progression.",

		icon         = "rbxassetid://14923131909",
		color        = Color3.fromRGB(255, 200, 50),
	},

	-- ✨ STEP 38: Claim Boost Challenge
	[38] = {
		id           = "a1_claim_boost_chal",
		action       = "Action_ClaimChallenge_unlock_spawnboost",
		targetTag    = "Tutorial_AchieveRow_Chal_unlock_spawnboost",

		unlockTags    = {"Tutorial_AchieveRow_Chal_unlock_spawnboost"},
		unlockActions = {"Action_ClaimChallenge_unlock_spawnboost"},

		menuTag        = "Tutorial_AchievePanel",
		menuOpenBtnTag = "Tutorial_AchieveMenuBtn",

		bannerTitle  = "Claim Your Rewards",
		bannerBody   = "You reached Area 2! Click the green 'CLAIM' button on the Explorer challenge to unlock the Value Boost.",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(80, 255, 100),
	},

	-- ✨ STEP 39: Click Index Tab
	[39] = {
		id           = "a1_click_index_tab",
		action       = "Action_ClickAchieveTab_Index",
		targetTag    = "Tutorial_AchieveTab_Index",

		unlockTags    = {"Tutorial_AchieveTab_Index"},
		unlockActions = {"Action_ClickAchieveTab_Index"},

		menuTag        = "Tutorial_AchievePanel",
		menuOpenBtnTag = "Tutorial_AchieveMenuBtn",

		bannerTitle  = "The Aura Index",
		bannerBody   = "Click the Auras tab. Here you can track every single Aura you have discovered across all Areas!",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(100, 200, 255),
	},

	-- ✨ STEP 40: Claim Aura Index Reward
	[40] = {
		id           = "a1_claim_index_reward",
		action       = "Action_ClaimAura_1_Common",
		targetTag    = "Tutorial_AchieveRow_Index_1",

		unlockTags    = {"Tutorial_AchieveRow_Index_1"},
		unlockActions = {"Action_ClaimAura_1_Common"},

		menuTag        = "Tutorial_AchievePanel",
		menuOpenBtnTag = "Tutorial_AchieveMenuBtn",

		bannerTitle  = "Discovery Bonus",
		bannerBody   = "Click on the Area 1 Common Aura to claim a Golden Aura bonus for discovering it!",

		icon         = "rbxassetid://4483362458",
		color        = Color3.fromRGB(255, 215, 0),
	},

	-- ✨ STEP 41: Click Badges Tab
	[41] = {
		id           = "a1_click_badges_tab",
		action       = "Action_ClickAchieveTab_Badges",
		targetTag    = "Tutorial_AchieveTab_Badges",

		unlockTags    = {"Tutorial_AchieveTab_Badges"},
		unlockActions = {"Action_ClickAchieveTab_Badges"},

		menuTag        = "Tutorial_AchievePanel",
		menuOpenBtnTag = "Tutorial_AchieveMenuBtn",

		bannerTitle  = "Roblox Badges",
		bannerBody   = "Click the Badges tab. You can officially earn Roblox Badges for reaching massive milestones.",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(255, 100, 255),
	},

	-- ✨ STEP 42: Claim Badge
	[42] = {
		id           = "a1_claim_badge_1",
		action       = "Action_ClaimBadge_1", 
		targetTag    = "Tutorial_AchieveRow_Badge_1",

		unlockTags    = {"Tutorial_AchieveRow_Badge_1"},
		unlockActions = {"Action_ClaimBadge_1"},

		menuTag        = "Tutorial_AchievePanel",
		menuOpenBtnTag = "Tutorial_AchieveMenuBtn",

		bannerTitle  = "Claim Badge",
		bannerBody   = "Click the First Prestige badge to officially unlock it on your Roblox profile!",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(200, 150, 255),
	},

	-- ✨ STEP 43: Click Leaderboard Tab
	[43] = {
		id           = "a1_click_leaderboard",
		action       = "Action_ClickAchieveTab_Leaderboard",
		targetTag    = "Tutorial_AchieveTab_Leaderboard",

		unlockTags    = {"Tutorial_AchieveTab_Leaderboard"},
		unlockActions = {"Action_ClickAchieveTab_Leaderboard"},

		menuTag        = "Tutorial_AchievePanel",
		menuOpenBtnTag = "Tutorial_AchieveMenuBtn",

		bannerTitle  = "Global Rankings",
		bannerBody   = "Click the Top 10 tab to view the Global Leaderboard. Can you become the richest player in the world?",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(255, 150, 50),
	},

	-- ✨ STEP 44: Click Settings Tab
	[44] = {
		id           = "a1_click_settings",
		action       = "Action_ClickAchieveTab_Settings",
		targetTag    = "Tutorial_AchieveTab_Settings",

		unlockTags    = {"Tutorial_AchieveTab_Settings"},
		unlockActions = {"Action_ClickAchieveTab_Settings"},

		menuTag        = "Tutorial_AchievePanel",
		menuOpenBtnTag = "Tutorial_AchieveMenuBtn",

		bannerTitle  = "Customize Your Farm",
		bannerBody   = "Finally, click the Settings tab. You can customize the game audio and mechanics here.",

		icon         = "rbxassetid://14923131909",
		color        = Color3.fromRGB(150, 255, 255),
	},

	-- ✨ STEP 45: Toggle Jumping
	[45] = {
		id           = "a1_toggle_jump",
		action       = "Action_ToggleSetting_jump",
		targetTag    = "Tutorial_SettingToggle_jump",

		unlockTags    = {"Tutorial_SettingToggle_jump"},
		unlockActions = {"Action_ToggleSetting_jump"},

		menuTag        = "Tutorial_AchievePanel",
		menuOpenBtnTag = "Tutorial_AchieveMenuBtn",

		bannerTitle  = "Disable Jumping",
		bannerBody   = "Click to disable Jumping. (You can also quick-toggle jumping at any time by pressing 'T' on your keyboard!)",

		icon         = "rbxassetid://14923131909",
		color        = Color3.fromRGB(255, 100, 100),
	},

	-- ✨ STEP 46: Open Area Travel
	[46] = {
		id           = "a1_final_travel",
		action       = "Action_OpenTravel",
		targetTag    = "Tutorial_TravelButton",

		bannerTitle  = "The Universe Awaits!",
		bannerBody   = "You have mastered the mechanics! Close the menu and open Area Travel to explore Area 3.",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(100, 255, 150),
	},

	-- ✨ STEP 47: Browse to Area 3
	[47] = {
		id             = "a1_travel_arrow_3",
		action         = "Action_ClickRightArrow",
		targetTag      = "Tutorial_RightArrow",

		menuTag        = "Tutorial_TravelPanel",
		menuOpenBtnTag = "Tutorial_TravelButton",
		fallbackStepId = "a1_final_travel", 

		bannerTitle  = "Browse Areas",
		bannerBody   = "Click the Right Arrow to view Area 3.",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(150, 200, 255),
	},

	-- ✨ STEP 48: Confirm Travel to Area 3 (End of Area 2)
	[48] = {
		id             = "a1_confirm_travel_3",
		action         = "Action_TravelConfirm",
		targetTag      = "Tutorial_TravelConfirm",

		menuTag        = "Tutorial_TravelPanel",
		menuOpenBtnTag = "Tutorial_TravelButton",
		fallbackStepId = "a1_final_travel",

		bannerTitle  = "Travel to Area 3",
		bannerBody   = "Click TRAVEL to jump to the new Area and continue your journey!",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(107, 255, 161),
	},
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
