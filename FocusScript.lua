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
	if currentTrackedPhysicsAura and currentTrackedPhysicsAura.Parent and currentTrackedPhysicsAura.Parent.Name == "AuraHolder" and not currentTrackedPhysicsAura:GetAttribute("Landed") then
		return currentTrackedPhysicsAura
	end

	local auras = CollectionService:GetTagged("PhysicsAura")
	for _, aura in ipairs(auras) do
		if aura and aura.Parent and aura.Parent.Name == "AuraHolder" and not aura:GetAttribute("Landed") then
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
		-- ✨ THE FIX: Restored this back to 15 (Very top) instead of 180!
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
		duration         = 5,          
		allowClicking = true, 

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

	-- ✨ STEP 32: Spawn 30 Auras
	[32] = {
		id           = "a1_spawn_30",
		action       = "Action_Wait", 
		targetTag    = "Tutorial_ClickButton",
		allowClicking = true, 

		requireCubesProduced = 30,
		duration     = 0,

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
		duration = 0,
		requireBoostBought = { id = "AuraRush", count = 5 },

		bannerTitle  = "Buy More Aura Rush Boosts",
		bannerBody   = "Buy 5 more Aura Rush Boosts. Note Boosts can stack for even faster production and MONEY.",

		icon         = "rbxassetid://4483362458",
		color        = Color3.fromRGB(101, 255, 199),
	},

	-- ✨ STEP 36: Mass Produce 150 Auras
	[36] = {
		id           = "a1_spawn_150",
		action       = "Action_Wait",
		targetTag    = "Tutorial_ClickButton",
		allowClicking = true, 

		requireCubesProduced = 150,
		duration     = 0,

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

-- UIController
-- Location: StarterPlayer > StarterPlayerScripts > UIController

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local Debris            = game:GetService("Debris")
local UserInputService  = game:GetService("UserInputService") 
local CollectionService = game:GetService("CollectionService")

local AdminConfig       = require(ReplicatedStorage.Modules.AdminConfig)
local Formatter         = require(ReplicatedStorage.Modules.NumberFormatter)
local UITheme           = require(ReplicatedStorage.Modules.UITheme)

local BridgeNet2             = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))
local UpdateHUDBridge        = BridgeNet2.ClientBridge("UpdateHUD")
local ShipAurasBridge        = BridgeNet2.ClientBridge("ShipAuras")
local UpdateHatcheryBridge   = BridgeNet2.ClientBridge("UpdateHatchery")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local HabitatFull = ReplicatedStorage.RemoteEvents:WaitForChild("HabitatFull")
local mainHUD   = playerGui:WaitForChild("MainHUD")

local isAutoMode          = AdminConfig.AutoDispatch
local HabitatHolder       = workspace:WaitForChild("HabitatHolder")
local GoldenAurasLabel    = mainHUD:WaitForChild("GoldenAurasLabel")

local displayedCurrency   = 0
local liveGoldenAuras     = 0
local ratePerSecond       = 0
local pendingAuras        = 0
local habitatCapacity     = AdminConfig.BaseHabitatCapacity
local passiveInterval     = AdminConfig.PassiveInterval
local currentCooldownTime = 15
local isShipOnCooldown    = false
local sharedCooldownEnd   = 0
local manualCooldownLoopID = 0
local autoLoopID          = 0
local currentHatcheryLevel = AdminConfig.HatcheryMax or 150 

local function FormatCurrency(n)
	local num = tonumber(n) or 0
	if num < 1000 then return string.format("%.2f", num)
	else return Formatter.Format(num) end
end

local function FormatNumber(n) return Formatter.Format(math.floor(tonumber(n) or 0)) end

local hud        = playerGui:WaitForChild("MainHUD")
local curr       = hud:WaitForChild("CurrencyLabel")
local rate       = hud:WaitForChild("RateLabel")
local sendButton = hud:WaitForChild("SendButton")
local modeToggle = hud:WaitForChild("ModeToggle")

CollectionService:AddTag(sendButton, "Tutorial_SendShipBtn")
CollectionService:AddTag(modeToggle, "Tutorial_ToggleShipBtn")

-- ─────────────────────────────────────────────────────────────────────────────
-- ✨ AUTO-MODE UI ENHANCEMENTS (Timer & Habitat Status)
-- ─────────────────────────────────────────────────────────────────────────────
local autoTimerLabel = Instance.new("TextLabel")
autoTimerLabel.Name = "AutoTimerLabel"
autoTimerLabel.Size = UDim2.new(0, 45, 1, 0)
autoTimerLabel.Position = UDim2.new(1, 26, 0, 0) 
autoTimerLabel.BackgroundTransparency = 1
autoTimerLabel.Text = ""
autoTimerLabel.TextColor3 = Color3.fromRGB(0, 255, 128)
autoTimerLabel.TextScaled = true
autoTimerLabel.Font = Enum.Font.GothamBold
autoTimerLabel.TextXAlignment = Enum.TextXAlignment.Left
autoTimerLabel.Visible = false
autoTimerLabel.Parent = modeToggle

-- Bigger & Styled Auto Habitat Label
local autoHabitatLabel = Instance.new("TextLabel")
autoHabitatLabel.Name = "AutoHabitatLabel"
autoHabitatLabel.Size = sendButton.Size
autoHabitatLabel.Position = sendButton.Position
autoHabitatLabel.AnchorPoint = sendButton.AnchorPoint
autoHabitatLabel.BackgroundTransparency = 1
autoHabitatLabel.Font = Enum.Font.FredokaOne 
autoHabitatLabel.TextColor3 = Color3.fromRGB(160, 200, 255)
autoHabitatLabel.TextScaled = true
autoHabitatLabel.TextXAlignment = Enum.TextXAlignment.Center 
autoHabitatLabel.Visible = false
autoHabitatLabel.Parent = sendButton.Parent

local autoHabStroke = Instance.new("UIStroke", autoHabitatLabel)
autoHabStroke.Thickness = 3
autoHabStroke.Transparency = 0.1
autoHabStroke.Color = Color3.new(0, 0, 0)

local autoHabConstraint = Instance.new("UITextSizeConstraint", autoHabitatLabel)
autoHabConstraint.MaxTextSize = 26 

-- ✨ MANUAL MODE BLUE TIMER (Left of the Send Button)
local manualTimerLabel = Instance.new("TextLabel")
manualTimerLabel.Name = "ManualTimerLabel"
manualTimerLabel.Size = UDim2.new(0, 60, 0.7, 0)
manualTimerLabel.AnchorPoint = Vector2.new(1, 0.5)
manualTimerLabel.Position = UDim2.new(0, -10, 0.5, 0) 
manualTimerLabel.BackgroundTransparency = 1
manualTimerLabel.Text = ""
manualTimerLabel.TextColor3 = Color3.fromRGB(0, 180, 255)
manualTimerLabel.TextScaled = true
manualTimerLabel.Font = Enum.Font.GothamBold
manualTimerLabel.TextXAlignment = Enum.TextXAlignment.Right
manualTimerLabel.Visible = false
manualTimerLabel.ZIndex = 50
manualTimerLabel.Parent = sendButton

local manualTimerStroke = Instance.new("UIStroke", manualTimerLabel)
manualTimerStroke.Color = Color3.new(0, 0, 0)
manualTimerStroke.Thickness = 2

-- ─────────────────────────────────────────────────────────────────────────────
-- ✨ INSTANT UI RESPONSIVENESS (Purchases & Juice Masks) ✨
-- ─────────────────────────────────────────────────────────────────────────────
local function UpdateWalletVisual()
	local pendingCash = player:GetAttribute("LocalPendingPayout") or 0
	curr.Text = "Currency: $" .. FormatCurrency(math.max(0, displayedCurrency - pendingCash))
end

local function UpdateAuraVisual()
	local pendingAurasVis = player:GetAttribute("LocalPendingAuras") or 0
	GoldenAurasLabel.Text = "GAURAS: " .. FormatNumber(math.max(0, liveGoldenAuras - pendingAurasVis))
end

player:GetAttributeChangedSignal("LocalSpend"):Connect(function()
	local spend = player:GetAttribute("LocalSpend") or 0
	if spend > 0 then
		displayedCurrency = math.max(0, displayedCurrency - spend)
		UpdateWalletVisual()
		player:SetAttribute("LocalSpend", 0)
	end
end)

player:GetAttributeChangedSignal("LocalAuraSpend"):Connect(function()
	local spend = player:GetAttribute("LocalAuraSpend") or 0
	if spend > 0 then
		liveGoldenAuras = math.max(0, liveGoldenAuras - spend)
		UpdateAuraVisual()
		player:SetAttribute("LocalAuraSpend", 0)
	end
end)

player:GetAttributeChangedSignal("LocalPendingPayout"):Connect(UpdateWalletVisual)
player:GetAttributeChangedSignal("LocalPendingAuras"):Connect(UpdateAuraVisual)

local function FormatRate(perSecond)
	if perSecond <= 0 then return "$0.00/sec" end
	return "$" .. FormatCurrency(perSecond) .. "/sec"
end

local function GetRateColor(pending, capacity)
	local ratio = math.clamp((pending or 0) / (capacity or 50), 0, 1)
	if ratio >= 1        then return Color3.fromRGB(255, 60,  60)
	elseif ratio >= 0.75 then return Color3.fromRGB(255, 200,  0)
	elseif ratio >= 0.5  then return Color3.fromRGB(80,  255, 80)
	else                      return Color3.fromRGB(80,  180, 80)
	end
end

local function UpdateHabitatBar(actualPending, capacity)
	local offset = player:GetAttribute("HabitatVisualOffset") or 0
	local visualPending = actualPending + offset

	local ratio    = math.clamp(visualPending / (capacity or 50), 0, 1)
	local color    = GetRateColor(visualPending, capacity)
	local model    = HabitatHolder:FindFirstChild("HabitatModel")
	if model then
		local gui    = model:FindFirstChild("HabitatGui")
		local barBg  = gui and gui:FindFirstChild("BarBackground")
		local barFill = barBg and barBg:FindFirstChild("BarFill")
		if barFill then
			TweenService:Create(barFill, TweenInfo.new(0.3), {
				Size = UDim2.new(ratio, 0, 1, 0),
				BackgroundColor3 = color,
			}):Play()
		end
	end
end

player:GetAttributeChangedSignal("HabitatVisualOffset"):Connect(function()
	UpdateHabitatBar(pendingAuras, habitatCapacity)
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- ✨ WARNING POPUP SYSTEM
-- ─────────────────────────────────────────────────────────────────────────────
local activeAlerts = {}

local function ShowAlertPopup(alertType, text, iconColor)
	if tick() - (activeAlerts[alertType] or 0) < 2.5 then return end
	activeAlerts[alertType] = tick()

	local ratePos = rate.AbsolutePosition
	local rateSize = rate.AbsoluteSize

	local alertW = 200
	local alertH = 40
	local padding = 15

	local endX = ratePos.X - padding
	local startX = endX + 40
	local startY = ratePos.Y + (rateSize.Y / 2)

	local effectGui = Instance.new("ScreenGui")
	effectGui.Name = "AlertGui_" .. alertType
	effectGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	effectGui.Parent = playerGui

	local alertFrame = Instance.new("Frame")
	alertFrame.Size = UDim2.new(0, alertW, 0, alertH)
	alertFrame.AnchorPoint = Vector2.new(1, 0.5)
	alertFrame.Position = UDim2.new(0, startX, 0, startY)
	alertFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
	alertFrame.BorderSizePixel = 0
	alertFrame.BackgroundTransparency = 1 
	alertFrame.Parent = effectGui

	local corner = Instance.new("UICorner", alertFrame)
	corner.CornerRadius = UDim.new(0.5, 0)

	local stroke = Instance.new("UIStroke", alertFrame)
	stroke.Color = iconColor
	stroke.Thickness = 2
	stroke.Transparency = 1

	local icon = Instance.new("ImageLabel", alertFrame)
	icon.Size = UDim2.new(0, 20, 0, 20)
	icon.Position = UDim2.new(0, 10, 0.5, -10)
	icon.BackgroundTransparency = 1
	icon.Image = "rbxassetid://7733658504" 
	icon.ImageColor3 = iconColor
	icon.ImageTransparency = 1

	local msg = Instance.new("TextLabel", alertFrame)
	msg.Size = UDim2.new(1, -40, 1, 0)
	msg.Position = UDim2.new(0, 35, 0, 0)
	msg.BackgroundTransparency = 1
	msg.Text = text
	msg.TextColor3 = iconColor
	msg.Font = Enum.Font.GothamBold
	msg.TextScaled = true
	msg.TextTransparency = 1
	msg.TextXAlignment = Enum.TextXAlignment.Left

	local sfxFolder = ReplicatedStorage:FindFirstChild("SFX") or ReplicatedStorage:FindFirstChild("Sounds")
	if sfxFolder and sfxFolder:FindFirstChild("ErrorBuzz") then
		local sfx = sfxFolder.ErrorBuzz:Clone()
		sfx.Parent = game:GetService("SoundService")
		sfx.Volume = 0.5
		sfx:Play()
		Debris:AddItem(sfx, 2)
	end

	TweenService:Create(alertFrame, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0, endX, 0, startY),
		BackgroundTransparency = 0.1
	}):Play()
	TweenService:Create(stroke, TweenInfo.new(0.4), {Transparency = 0}):Play()
	TweenService:Create(icon, TweenInfo.new(0.4), {ImageTransparency = 0}):Play()
	TweenService:Create(msg, TweenInfo.new(0.4), {TextTransparency = 0}):Play()

	task.delay(2, function()
		if not alertFrame.Parent then return end
		TweenService:Create(alertFrame, TweenInfo.new(0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
			Position = UDim2.new(0, startX, 0, startY),
			BackgroundTransparency = 1
		}):Play()
		TweenService:Create(stroke, TweenInfo.new(0.3), {Transparency = 1}):Play()
		TweenService:Create(icon, TweenInfo.new(0.3), {ImageTransparency = 1}):Play()
		TweenService:Create(msg, TweenInfo.new(0.3), {TextTransparency = 1}):Play()
		Debris:AddItem(effectGui, 0.4)
	end)
end

HabitatFull.OnClientEvent:Connect(function()
	ShowAlertPopup("HabitatFull", "HABITAT FULL!", Color3.fromRGB(255, 80, 80))
end)

UpdateHatcheryBridge:Connect(function(info)
	currentHatcheryLevel = info.current
	if info.current <= 0 then
		ShowAlertPopup("HatcheryEmpty", "HATCHERY EMPTY!", Color3.fromRGB(255, 180, 50))
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then

		local clickedMainButton = false
		if gameProcessed then
			local guis = playerGui:GetGuiObjectsAtPosition(input.Position.X, input.Position.Y)
			for _, gui in ipairs(guis) do
				if gui.Name == "ClickButton" then
					clickedMainButton = true
					break
				end
			end
		end

		if not clickedMainButton then return end

		if currentHatcheryLevel <= 0.5 then
			ShowAlertPopup("HatcheryEmpty", "HATCHERY EMPTY!", Color3.fromRGB(255, 180, 50))
		elseif pendingAuras >= habitatCapacity then
			ShowAlertPopup("HabitatFull", "HABITAT FULL!", Color3.fromRGB(255, 80, 80))
		end
	end
end)

local function SyncManualCooldownVisuals()
	if isAutoMode or not sendButton.Visible then 
		manualTimerLabel.Visible = false
		return 
	end

	local progressContainer = sendButton:FindFirstChild("CooldownProgress")
	local fillPart          = progressContainer and progressContainer:FindFirstChild("Fill")
	local textTarget        = sendButton:FindFirstChildOfClass("TextLabel") or sendButton

	local uiStroke = sendButton:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke", sendButton)
	uiStroke.Thickness = 1.5

	if not fillPart then return end

	-- ✨ THE FIX: We turn ClipsDescendants OFF on the button so the timer label outside the button isn't erased
	sendButton.ClipsDescendants = false

	-- And instead we put the clipping on the container so the black bar stays nicely inside!
	progressContainer.ClipsDescendants = true
	local progCorner = progressContainer:FindFirstChildOfClass("UICorner") or Instance.new("UICorner", progressContainer)
	local btnCorner = sendButton:FindFirstChildOfClass("UICorner")
	if btnCorner then progCorner.CornerRadius = btnCorner.CornerRadius end

	progressContainer.Size     = UDim2.new(1, 0, 1, 0)
	progressContainer.Position = UDim2.new(0, 0, 0, 0)
	progressContainer.AnchorPoint = Vector2.new(0, 0)

	fillPart.BorderSizePixel = 0
	fillPart.AnchorPoint     = Vector2.new(0, 1)
	fillPart.Position        = UDim2.new(0, 0, 1, 0)

	manualCooldownLoopID += 1
	local currentLoop = manualCooldownLoopID
	local timeLeft    = sharedCooldownEnd - tick()

	sendButton.BackgroundColor3    = Color3.fromRGB(0, 160, 255)
	uiStroke.Color                 = Color3.fromRGB(0, 220, 255)
	fillPart.BackgroundColor3      = Color3.fromRGB(0, 0, 0)
	fillPart.BackgroundTransparency = 0.55

	if timeLeft > 0 then
		isShipOnCooldown = true
		if textTarget ~= sendButton then sendButton.Text = "" end

		manualTimerLabel.Visible = true

		local pct = timeLeft / currentCooldownTime
		fillPart.Size = UDim2.new(1, 0, pct, 0)

		TweenService:Create(fillPart, TweenInfo.new(timeLeft, Enum.EasingStyle.Linear), {
			Size = UDim2.new(1, 0, 0, 0)
		}):Play()

		task.spawn(function()
			while manualCooldownLoopID == currentLoop do
				local currentLeft = sharedCooldownEnd - tick()

				if currentLeft <= 0 then break end

				manualTimerLabel.Text = string.format("%.1fs", currentLeft)
				task.wait(0.05) 
			end

			if manualCooldownLoopID == currentLoop then
				isShipOnCooldown  = false
				textTarget.Text   = ""
				fillPart.Size     = UDim2.new(1, 0, 0, 0)
				manualTimerLabel.Visible = false
			end
		end)
	else
		isShipOnCooldown = false
		textTarget.Text  = ""
		fillPart.Size    = UDim2.new(1, 0, 0, 0)
		manualTimerLabel.Visible = false
	end
end

local function UpdateSendButton()
	if AdminConfig.DisableShipping then 
		sendButton.Visible = false
		autoHabitatLabel.Visible = false
		return 
	end

	if isAutoMode then
		sendButton.Visible = false
		autoHabitatLabel.Visible = true
		autoHabitatLabel.Text = "Waiting: " .. FormatNumber(pendingAuras) .. " / " .. FormatNumber(habitatCapacity)

		if pendingAuras >= habitatCapacity then
			autoHabitatLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
		elseif pendingAuras > 0 then
			autoHabitatLabel.TextColor3 = Color3.fromRGB(100, 255, 128)
		else
			autoHabitatLabel.TextColor3 = Color3.fromRGB(160, 160, 180)
		end
	else
		autoHabitatLabel.Visible = false
		sendButton.Visible = pendingAuras > 0
		if sendButton.Visible then
			SyncManualCooldownVisuals()
		end
	end
end

local autoProgressContainer = Instance.new("Frame")
autoProgressContainer.Name             = "AutoProgressContainer"
autoProgressContainer.Size             = UDim2.new(0, 12, 1, 0)
autoProgressContainer.Position         = UDim2.new(1, 8, 0, 0)
autoProgressContainer.BackgroundColor3 = Color3.fromRGB(24, 60, 24)
autoProgressContainer.BorderSizePixel  = 0
autoProgressContainer.Visible          = false
autoProgressContainer.Parent           = modeToggle
Instance.new("UICorner", autoProgressContainer).CornerRadius = UDim.new(0.5, 0)

local autoFillClip = Instance.new("Frame")
autoFillClip.Size                 = UDim2.new(1, 0, 1, 0)
autoFillClip.BackgroundTransparency = 1
autoFillClip.ClipsDescendants     = true
autoFillClip.Parent               = autoProgressContainer
Instance.new("UICorner", autoFillClip).CornerRadius = UDim.new(0.5, 0)

local autoFill = Instance.new("Frame")
autoFill.Name             = "Fill"
autoFill.Size             = UDim2.new(1, 0, 1, 0)
autoFill.Position         = UDim2.new(0, 0, 1, 0)
autoFill.AnchorPoint      = Vector2.new(0, 1)
autoFill.BackgroundColor3 = Color3.fromRGB(0, 255, 128)
autoFill.BorderSizePixel  = 0
autoFill.Parent           = autoFillClip

local function UpdateModeToggleVisuals()
	local textLabel = modeToggle:FindFirstChildOfClass("TextLabel") or modeToggle
	local uiStroke  = modeToggle:FindFirstChildOfClass("UIStroke")

	autoLoopID += 1
	local currentLoop = autoLoopID

	if isAutoMode then
		modeToggle.BackgroundColor3 = Color3.fromRGB(24, 60, 24)
		textLabel.Text              = "[AUTO ACTIVE]"
		textLabel.TextColor3        = Color3.fromRGB(0, 255, 128)
		if uiStroke then uiStroke.Color = Color3.fromRGB(0, 255, 128) end

		autoProgressContainer.Visible = true
		autoTimerLabel.Visible = true

		task.spawn(function()
			local activeTween = nil

			while isAutoMode and autoLoopID == currentLoop do
				local currentLeft = sharedCooldownEnd - tick()

				if currentLeft <= 0 then
					if pendingAuras > 0 then
						ShipAurasBridge:Fire({ action = "manual" })
						if type(shared.TutorialRecordShipSent) == "function" then shared.TutorialRecordShipSent() end
					end

					sharedCooldownEnd = tick() + currentCooldownTime
					currentLeft = currentCooldownTime

					if activeTween then activeTween:Cancel() end
					autoFill.Size = UDim2.new(1, 0, 1, 0)
					activeTween = TweenService:Create(autoFill, TweenInfo.new(currentLeft, Enum.EasingStyle.Linear), {
						Size = UDim2.new(1, 0, 0, 0)
					})
					activeTween:Play()
				end

				autoTimerLabel.Text = string.format("%.1fs", math.max(0, currentLeft))
				task.wait(0.05) 
			end

			if activeTween then activeTween:Cancel() end
		end)
	else
		modeToggle.BackgroundColor3 = Color3.fromRGB(38, 38, 45)
		textLabel.Text              = "Mode: Manual"
		textLabel.TextColor3        = Color3.fromRGB(220, 230, 240)
		if uiStroke then uiStroke.Color = Color3.fromRGB(100, 180, 220) end

		autoProgressContainer.Visible = false
		autoTimerLabel.Visible = false
	end
end

---------------------------------------------------------------
-- ✨ SEND BUTTON CLICK
---------------------------------------------------------------
sendButton.MouseButton1Down:Connect(function()
	if AdminConfig.DisableShipping then return end
	if isAutoMode or isShipOnCooldown or pendingAuras <= 0 then return end

	if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_SendShip") then return end

	ShipAurasBridge:Fire({ action = "manual" })
	sharedCooldownEnd = tick() + currentCooldownTime
	SyncManualCooldownVisuals()

	if type(shared.TutorialRecordShipSent) == "function" then shared.TutorialRecordShipSent() end
	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
end)

modeToggle.MouseButton1Down:Connect(function()
	if AdminConfig.DisableShipping then return end

	if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_ToggleAutoShip") then return end

	isAutoMode = not isAutoMode
	ShipAurasBridge:Fire({ action = "setMode", value = isAutoMode and "auto" or "manual" })

	UpdateModeToggleVisuals()
	UpdateSendButton()

	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
end)

UpdateModeToggleVisuals()
sendButton.Visible = false

if AdminConfig.DisableShipping then
	isAutoMode         = false
	sendButton.Visible = false
	modeToggle.Visible = false
end

-- ─────────────────────────────────────────────────────────────────────────────
-- ✨ STRICT SERVER AUTHORITY LISTENER ✨
-- ─────────────────────────────────────────────────────────────────────────────
UpdateHUDBridge:Connect(function(stats)

	if stats.currency ~= nil then
		displayedCurrency = stats.currency
		player:SetAttribute("LiveCurrency", displayedCurrency)
		UpdateWalletVisual()
	end

	if stats.goldenAuras ~= nil then
		liveGoldenAuras = stats.goldenAuras
		player:SetAttribute("LiveGoldenAuras", liveGoldenAuras)
		UpdateAuraVisual()
	end

	if stats.pendingAuras ~= nil then
		pendingAuras    = stats.pendingAuras
		habitatCapacity = stats.habitatCapacity or habitatCapacity
		UpdateHabitatBar(pendingAuras, habitatCapacity)

		UpdateSendButton() 
	end

	if stats.rate ~= nil then
		passiveInterval = stats.passiveInterval or passiveInterval
		local serverRate = stats.rate
		ratePerSecond = (passiveInterval > 0 and serverRate > 0) and serverRate / passiveInterval or 0

		rate.Text = FormatRate(ratePerSecond)
		TweenService:Create(rate, TweenInfo.new(0.3), { TextColor3 = GetRateColor(pendingAuras, habitatCapacity) }):Play()
	end

	if stats.shipCooldown ~= nil then
		currentCooldownTime = stats.shipCooldown
	end
end)

-- ✨ FLASH GREEN WHEN SHIP PAYS OUT
ShipAurasBridge:Connect(function(info)
	if type(info) == "table" and info.action == "payoutConfirmed" then
		local amt = info.amount or 0
		if amt > 0 then
			if type(shared.TutorialRecordEarned) == "function" then shared.TutorialRecordEarned(amt) end
			curr.TextColor3 = Color3.fromRGB(80, 255, 80)
			TweenService:Create(curr, TweenInfo.new(0.5), { TextColor3 = Color3.fromRGB(255, 255, 255) }):Play()
		end
	end
end)

local function RefreshLook()
	UITheme.ApplyFlair(GoldenAurasLabel, "GoldStroke")
end
task.wait(2)
RefreshLook()
