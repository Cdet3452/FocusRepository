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

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
local TutorialStepComplete = RemoteEvents:WaitForChild("TutorialStepComplete", 10)

-- ✨ BRIDGENET2 UPGRADE
local BridgeNet2 = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))
local UpdateHUDBridge = BridgeNet2.ClientBridge("UpdateHUD")

-- ✨ CINEMATIC OVERRIDE EVENT
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
	currentMultiplier = 1 
}

local UpdateMultiplier = ReplicatedStorage:WaitForChild("UpdateMultiplier")
UpdateMultiplier.Event:Connect(function(mult)
	liveStats.currentMultiplier = mult
end)

local baselineCubes = 0
local baselineShipped = 0

local function GetStepCubes()
	return math.max(0, liveStats.totalCubesProduced - baselineCubes)
end

local function GetStepShipped()
	return math.max(0, liveStats.totalPlatformsShipped - baselineShipped)
end

local lockedAura = nil

local function GetActiveAura()
	if lockedAura and lockedAura.Parent and lockedAura:GetAttribute("AuraCube") then
		return lockedAura
	end

	local auraHolder = Workspace:FindFirstChild("AuraHolder")
	if auraHolder then
		local children = auraHolder:GetChildren()
		for i = #children, 1, -1 do
			local child = children[i]
			if child:GetAttribute("AuraCube") then 
				lockedAura = child
				return child 
			end
		end
	end

	local wsChildren = Workspace:GetChildren()
	for i = #wsChildren, 1, -1 do
		local child = wsChildren[i]
		if child:GetAttribute("AuraCube") then 
			lockedAura = child
			return child 
		end
	end
	return nil
end

shared.TutorialRecordAuraSpawned = function()
	liveStats.totalCubesProduced += 1
end

shared.TutorialRecordShipSent = function()
	task.delay(4, function()
		liveStats.totalPlatformsShipped += 1
	end)
end

local tutorialGui = nil
local activePointer = nil
local activeHighlight = nil
local questBanner = nil
local trackingConnection = nil
local originalCamType = nil
local currentCamTarget = nil

---------------------------------------------------------------
-- VISIBILITY & GATING EVALUATION
---------------------------------------------------------------
local function IsVisibleOnScreen(guiObject)
	local current = guiObject
	while current and current ~= game do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		elseif current:IsA("LayerCollector") and not current.Enabled then
			return false
		end
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

	if step.requireCurrency and currentCash < step.requireCurrency then return false end
	if step.requireFarmEval and liveStats.farmEvaluation < step.requireFarmEval then return false end
	if step.requireSoulAuras and liveStats.soulAuras < step.requireSoulAuras then return false end
	if step.requireGoldenAuras and currentGoldenAuras < step.requireGoldenAuras then return false end
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

	if activeStep.action == "Action_Wait" then
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

	if activeStep.action == requestedAction then
		actionMatchedForAdvance = true
		return true
	end

	local isPermanentlyUnlocked = false
	for i = 1, currentStepIndex do
		local pastStep = TutorialConfig.GetStepByIndex(i)
		if pastStep then
			if i < currentStepIndex and pastStep.action == requestedAction then
				isPermanentlyUnlocked = true
				break
			end
			if pastStep.unlockActions then
				for _, act in ipairs(pastStep.unlockActions) do
					if act == requestedAction then
						isPermanentlyUnlocked = true
						break
					end
				end
			end
		end
	end
	if isPermanentlyUnlocked then return true end

	if requestedAction == "Action_ClickRedButton" and not MeetsStrictGates(activeStep) then
		return true
	end

	if shared.PlayUISound then shared.PlayUISound(SoundConfig.ErrorBuzz or "") end
	return false
end

---------------------------------------------------------------
-- INITIALIZATION & UI
---------------------------------------------------------------
local function InitTutorialUI()
	tutorialGui = Instance.new("ScreenGui")
	tutorialGui.Name = "TutorialOverlays"
	tutorialGui.DisplayOrder = 1000 
	tutorialGui.ResetOnSpawn = false
	tutorialGui.Parent = playerGui

	activeHighlight = Instance.new("Frame")
	activeHighlight.Name = "TutorialHighlight"
	activeHighlight.BackgroundColor3 = Color3.new(1, 1, 1) 
	activeHighlight.BackgroundTransparency = 1 
	activeHighlight.Interactable = false 
	activeHighlight.Active = false
	activeHighlight.Visible = false
	activeHighlight.ZIndex = 99
	activeHighlight.Parent = tutorialGui

	local highlightStroke = Instance.new("UIStroke", activeHighlight)
	highlightStroke.Color = TutorialConfig.DefaultColor
	highlightStroke.Thickness = 3
	highlightStroke.Transparency = 0.2
	Instance.new("UICorner", activeHighlight).CornerRadius = UDim.new(0, 8)
	TweenService:Create(highlightStroke, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {Transparency = 0.8}):Play()

	activePointer = Instance.new("ImageLabel")
	activePointer.Name = "GhostHand"
	activePointer.Size = TutorialConfig.PointerSize
	activePointer.BackgroundTransparency = 1
	activePointer.Image = TutorialConfig.PointerImage
	activePointer.AnchorPoint = Vector2.new(0.5, 0)
	activePointer.Visible = false
	activePointer.Active = false 
	activePointer.ZIndex = 100
	activePointer.Parent = tutorialGui

	questBanner = Instance.new("Frame")
	questBanner.Name = "QuestBanner"
	questBanner.Size = UDim2.new(0.85, 0, 0, 130) 
	questBanner.AnchorPoint = Vector2.new(0.5, 0)
	questBanner.Position = UDim2.new(0.5, 0, 0, -250) 
	questBanner.BackgroundColor3 = T.panelBG or Color3.fromRGB(20, 20, 30)
	questBanner.BorderSizePixel = 0
	questBanner.Visible = false
	questBanner.Active = false 
	questBanner.Parent = tutorialGui
	Instance.new("UICorner", questBanner).CornerRadius = UDim.new(0, 12)

	local sizeConstraint = Instance.new("UISizeConstraint", questBanner)
	sizeConstraint.MaxSize = Vector2.new(650, 130) 
	sizeConstraint.MinSize = Vector2.new(280, 85)

	Instance.new("UIScale", questBanner)

	local bgGrad = Instance.new("UIGradient", questBanner)
	bgGrad.Rotation = 90
	bgGrad.Transparency = NumberSequence.new({ 
		NumberSequenceKeypoint.new(0, 0.3), 
		NumberSequenceKeypoint.new(1, 0.95) 
	})

	local stroke = Instance.new("UIStroke", questBanner)
	stroke.Name = "BannerStroke"
	stroke.Color = TutorialConfig.DefaultColor
	stroke.Thickness = 2.5
	stroke.Transparency = 0.1

	local strokeGrad = Instance.new("UIGradient", stroke)
	strokeGrad.Name = "StrokeGradient"
	strokeGrad.Rotation = 45

	local iconFrame = Instance.new("Frame", questBanner)
	iconFrame.Name = "IconFrame"
	iconFrame.Size = UDim2.new(0, 72, 0, 72)
	iconFrame.AnchorPoint = Vector2.new(0, 0.5)
	iconFrame.Position = UDim2.new(0, 14, 0.5, 0)
	iconFrame.BackgroundColor3 = TutorialConfig.DefaultColor
	iconFrame.BackgroundTransparency = 0.85
	iconFrame.Active = false
	Instance.new("UICorner", iconFrame).CornerRadius = UDim.new(0, 12)
	Instance.new("UIStroke", iconFrame).Color = TutorialConfig.DefaultColor

	local icon = Instance.new("ImageLabel", iconFrame)
	icon.Name = "IconImage"
	icon.Size = UDim2.new(0.65, 0, 0.65, 0)
	icon.Position = UDim2.new(0.175, 0, 0.175, 0)
	icon.BackgroundTransparency = 1
	icon.Image = TutorialConfig.DefaultIcon
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Active = false

	local title = Instance.new("TextLabel", questBanner)
	title.Name = "Title"
	title.Size = UDim2.new(1, -100, 0.35, 0)
	title.Position = UDim2.new(0, 96, 0.08, 0)
	title.BackgroundTransparency = 1
	title.TextColor3 = TutorialConfig.DefaultColor
	title.TextScaled = true
	title.Font = Enum.Font.FredokaOne 
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Active = false

	local titleConstraint = Instance.new("UITextSizeConstraint", title)
	titleConstraint.MaxTextSize = 34 
	titleConstraint.MinTextSize = 14

	local titleShadow = title:Clone()
	titleShadow.Name = "TitleShadow"
	titleShadow.TextColor3 = Color3.new(0, 0, 0)
	titleShadow.TextTransparency = 0.6
	titleShadow.Position = UDim2.new(0, 98, 0.08, 2)
	titleShadow.ZIndex = title.ZIndex - 1
	titleShadow.Parent = questBanner

	local body = Instance.new("TextLabel", questBanner)
	body.Name = "Body"
	body.Size = UDim2.new(1, -100, 0.5, 0)
	body.Position = UDim2.new(0, 96, 0.45, 0)
	body.BackgroundTransparency = 1
	body.TextColor3 = T.bodyText or Color3.fromRGB(230, 230, 240)
	body.TextWrapped = true
	body.TextScaled = true
	body.RichText = true
	body.Font = Enum.Font.GothamMedium
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.Active = false

	local bodyConstraint = Instance.new("UITextSizeConstraint", body)
	bodyConstraint.MaxTextSize = 22 
	bodyConstraint.MinTextSize = 10
end

---------------------------------------------------------------
-- ✨ AUTO-SCROLL HELPER
---------------------------------------------------------------
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

---------------------------------------------------------------
-- ✨ ANIMATION HANDLERS
---------------------------------------------------------------
local function HideBanner()
	if not questBanner or not questBanner.Visible then return end

	TweenService:Create(questBanner, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = UDim2.new(0.5, 0, 0, -250)
	}):Play()

	task.delay(0.4, function()
		if lastDisplayedStepId == nil then 
			questBanner.Visible = false
		end
	end)
end

local function ShowBanner(step)
	local stepColor = step.color or TutorialConfig.DefaultColor

	questBanner.Title.Text = step.bannerTitle
	questBanner.TitleShadow.Text = step.bannerTitle
	questBanner.Body.Text = step.bannerBody

	questBanner.Title.TextColor3 = stepColor
	questBanner.IconFrame.BackgroundColor3 = stepColor
	questBanner.IconFrame.UIStroke.Color = stepColor
	questBanner.IconFrame.IconImage.Image = step.icon or TutorialConfig.DefaultIcon

	if activeHighlight then
		local stroke = activeHighlight:FindFirstChildOfClass("UIStroke")
		if stroke then stroke.Color = stepColor end
	end

	local strokeGrad = questBanner.BannerStroke:FindFirstChild("StrokeGradient")
	if strokeGrad then
		strokeGrad.Color = ColorSequence.new({ 
			ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)), 
			ColorSequenceKeypoint.new(1, stepColor) 
		})
	end

	if not questBanner.Visible then
		questBanner.Position = UDim2.new(0.5, 0, 0, -250)
		questBanner.Visible = true
		TweenService:Create(questBanner, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, 0, 0, 15) 
		}):Play()
	else
		local scale = questBanner:FindFirstChildOfClass("UIScale")
		if scale then
			scale.Scale = 0.85
			TweenService:Create(scale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Scale = 1
			}):Play()
		end
	end

	if shared.PlayUISound then 
		shared.PlayUISound(SoundConfig.TutorialHint or "6895079853") 
	end
end

---------------------------------------------------------------
-- CORE LOOP (RenderStepped)
---------------------------------------------------------------
local function StartTrackingLoop()
	if trackingConnection then trackingConnection:Disconnect() end

	local bounceTime = 0
	local isAutoScrolling = false

	trackingConnection = RunService.RenderStepped:Connect(function(dt)

		-- ✨ VISUAL LOCKING SYSTEM
		local allLockedTags = {}
		local currentUnlockedTags = {}

		for i, stp in ipairs(TutorialConfig.Steps) do
			if stp.unlockTags then
				for _, tag in ipairs(stp.unlockTags) do
					allLockedTags[tag] = true
					if tutorialComplete or i <= currentStepIndex then
						currentUnlockedTags[tag] = true
					end
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
						overlay = Instance.new("TextButton")
						overlay.Name = "TutorialLockOverlay"
						overlay.Size = UDim2.new(1, 0, 1, 0)
						overlay.Position = UDim2.new(0, 0, 0, 0)
						overlay.AnchorPoint = Vector2.new(0, 0)
						overlay.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
						overlay.BackgroundTransparency = 0.5

						-- ✨ THE FIX: We skyrocketed the Z-Index to guarantee it covers icons!
						overlay.ZIndex = 99998 
						overlay.Text = ""
						overlay.AutoButtonColor = false

						local corner = el:FindFirstChildOfClass("UICorner")
						if corner then corner:Clone().Parent = overlay end

						local icon = Instance.new("ImageLabel")
						icon.Name = "PadlockIcon"
						icon.Size = UDim2.new(0, 24, 0, 24)
						icon.AnchorPoint = Vector2.new(0.5, 0.5)
						icon.Position = UDim2.new(0.5, 0, 0.5, 0)
						icon.BackgroundTransparency = 1
						icon.Image = "rbxassetid://7059346373"
						icon.ImageColor3 = Color3.fromRGB(255, 255, 255)
						icon.ScaleType = Enum.ScaleType.Fit 

						-- ✨ THE FIX: Explicitly forcing the padlock above the black overlay
						icon.ZIndex = 99999 
						icon.Parent = overlay

						overlay.Parent = el
					end
				else
					if overlay then
						overlay:Destroy()
					end
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
					if foundFallback then
						activeFallbackStep = foundFallback
						step = activeFallbackStep
					end
				end
			end
		else
			local originalStep = TutorialConfig.GetStepByIndex(currentStepIndex)
			if originalStep and MeetsStrictGates(originalStep) then
				activeFallbackStep = nil
				step = originalStep
			end
		end

		if not step then return end 

		-- 2. UPDATE PERSISTENT BANNER & LIVE TEXT
		if step.bannerTitle then
			if lastDisplayedStepId ~= step.id then
				lastDisplayedStepId = step.id
				ShowBanner(step)

				if step.cameraTarget or step.cameraTrackMode then
					ForceCloseUI:Fire()
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
			end
			questBanner.Body.Text = step.bannerBody .. progressText

		else
			if lastDisplayedStepId ~= nil then
				lastDisplayedStepId = nil
				HideBanner()
			end
		end

		-- 3. POINTER LOGIC
		local targetToTrack2D = nil
		local targetToTrack3D = nil

		if step.target3D then
			if string.find(string.lower(step.target3D), "aura") then
				local aura = GetActiveAura()
				if aura then 
					targetToTrack3D = aura:IsA("Model") and aura:GetPivot().Position or aura.Position 
				end
			else
				local obj = CollectionService:GetTagged(step.target3D)[1]
				if obj then 
					targetToTrack3D = obj:IsA("Model") and obj:GetPivot().Position or obj.Position 
				end
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

		-- 4. RENDERING LOGIC
		if targetToTrack3D then
			local screenPos, onScreen = camera:WorldToViewportPoint(targetToTrack3D)
			if onScreen and screenPos.Z > 0 then
				activePointer.Visible = true
				activeHighlight.Visible = false 
				activePointer.Position = UDim2.new(0, screenPos.X, 0, screenPos.Y - (activePointer.Size.Y.Offset / 2) - bounceOffset)
			else
				activePointer.Visible = false
				activeHighlight.Visible = false
			end

		elseif targetToTrack2D and targetToTrack2D:IsA("GuiObject") then
			if targetToTrack2D.AbsoluteSize.Magnitude > 0 and IsVisibleOnScreen(targetToTrack2D) then
				activePointer.Visible = true
				activeHighlight.Visible = true

				local tgtRelX = targetToTrack2D.AbsolutePosition.X
				local tgtRelY = targetToTrack2D.AbsolutePosition.Y
				activeHighlight.Size = UDim2.new(0, targetToTrack2D.AbsoluteSize.X + 12, 0, targetToTrack2D.AbsoluteSize.Y + 12)
				activeHighlight.Position = UDim2.new(0, tgtRelX - 6, 0, tgtRelY - 6)

				local targetCorner = targetToTrack2D:FindFirstChildOfClass("UICorner")
				local highlightCorner = activeHighlight:FindFirstChildOfClass("UICorner")
				if targetCorner and highlightCorner then highlightCorner.CornerRadius = targetCorner.CornerRadius end

				local centerPos = targetToTrack2D.AbsolutePosition + (targetToTrack2D.AbsoluteSize / 2)
				activePointer.Position = UDim2.new(0, centerPos.X, 0, targetToTrack2D.AbsolutePosition.Y - activePointer.Size.Y.Offset - bounceOffset)

				local scrollFrame = targetToTrack2D:FindFirstAncestorOfClass("ScrollingFrame")
				if scrollFrame and not isAutoScrolling then
					local targetY = targetToTrack2D.AbsolutePosition.Y
					local scrollY = scrollFrame.AbsolutePosition.Y
					local scrollBottom = scrollY + scrollFrame.AbsoluteSize.Y

					if (targetY + targetToTrack2D.AbsoluteSize.Y < scrollY) or (targetY > scrollBottom) then
						isAutoScrolling = true
						AutoScrollToTarget(targetToTrack2D)
						task.delay(0.5, function() isAutoScrolling = false end)
					end
				end
			else
				activePointer.Visible = false
				activeHighlight.Visible = false
			end
		else
			activePointer.Visible = false
			activeHighlight.Visible = false
		end

		-- 5. DYNAMIC CAMERA TRACKING
		if step.cameraTrackMode == "FollowAura" then
			local aura = GetActiveAura()

			if aura then
				if camera.CameraType ~= Enum.CameraType.Scriptable then
					camera.CameraType = Enum.CameraType.Scriptable
				end

				local targetPos = aura:IsA("Model") and aura:GetPivot().Position or aura.Position
				local offset = step.cameraOffset or Vector3.new(0, 8, 10) 
				local desiredCFrame = CFrame.new(targetPos + offset, targetPos)
				camera.CFrame = camera.CFrame:Lerp(desiredCFrame, 0.025) 
			else
				local fallbackCam = CollectionService:GetTagged("Tutorial_AuraHolderCam")[1]
				if fallbackCam then
					if camera.CameraType ~= Enum.CameraType.Scriptable then
						camera.CameraType = Enum.CameraType.Scriptable
					end
					local desiredCFrame = fallbackCam:IsA("Model") and fallbackCam:GetPivot() or fallbackCam.CFrame
					camera.CFrame = camera.CFrame:Lerp(desiredCFrame, 0.025)
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
				if camera.CameraType ~= Enum.CameraType.Scriptable then
					camera.CameraType = Enum.CameraType.Scriptable
				end

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

		-- 6. ✨ AUTO-ADVANCE / FAILSAFE LOGIC
		if not step._startTime then step._startTime = tick() end

		if step.duration and step.duration > 0 then
			if tick() - step._startTime >= step.duration then
				shared.AdvanceTutorialStep(true) 
			end
		elseif step.duration == 0 then
			if MeetsStrictGates(step) and not activeFallbackStep then
				shared.AdvanceTutorialStep(true) 
			elseif step.failsafeDuration and (tick() - step._startTime >= step.failsafeDuration) then
				shared.AdvanceTutorialStep(true) 
			end
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
		if not actionMatchedForAdvance then
			return 
		end
	end

	actionMatchedForAdvance = false
	lockedAura = nil 

	if currentStepData and currentStepData.duration == 0 and not forceAdvance then
		if not MeetsStrictGates(currentStepData) then
			return 
		end
	end

	isAdvancing = true 

	if currentStepData then
		TutorialStepComplete:FireServer(currentStepData.id)
	end

	currentStepIndex += 1

	baselineCubes = liveStats.totalCubesProduced
	baselineShipped = liveStats.totalPlatformsShipped

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
		successSound.SoundId = "rbxassetid://4612385808"
		successSound.Volume = 0.6
		successSound.Parent = game:GetService("SoundService")
		successSound:Play()
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

	if stats.totalCubesProduced ~= nil then 
		liveStats.totalCubesProduced = math.max(liveStats.totalCubesProduced, stats.totalCubesProduced) 
	end
	if stats.totalPlatformsShipped ~= nil then 
		liveStats.totalPlatformsShipped = math.max(liveStats.totalPlatformsShipped, stats.totalPlatformsShipped) 
	end
	if stats.totalLegendaryCubes ~= nil then 
		liveStats.totalLegendaryCubes = math.max(liveStats.totalLegendaryCubes, stats.totalLegendaryCubes) 
	end

	if stats.piggyBank ~= nil then liveStats.piggyBank = stats.piggyBank end

	if stats.tutorialComplete ~= nil then 
		tutorialComplete = stats.tutorialComplete 
	end

	if stats.tutorialProgress and not tutorialComplete then
		local highestCompletedIndex = 0

		for index, stepData in ipairs(TutorialConfig.Steps) do
			if stats.tutorialProgress[stepData.id] then
				highestCompletedIndex = index
			end
		end

		if highestCompletedIndex >= currentStepIndex then
			currentStepIndex = highestCompletedIndex + 1

			baselineCubes = liveStats.totalCubesProduced
			baselineShipped = liveStats.totalPlatformsShipped

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
	if menuGate and not menuGate:GetAttribute("Fired") then
		menuGate.Event:Wait()
	end

	local character = player.Character or player.CharacterAdded:Wait()
	local humanoid = character:WaitForChild("Humanoid", 5)
	camera.CameraType = Enum.CameraType.Custom
	if humanoid then
		camera.CameraSubject = humanoid
	end

	tutorialActive = true
	InitTutorialUI()
	StartTrackingLoop()
end)

-- BoostController
-- Location: StarterPlayer > StarterPlayerScripts > BoostController

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local AdminConfig       = require(ReplicatedStorage.Modules.AdminConfig)
local SoundConfig       = require(ReplicatedStorage.Modules.SoundConfig)
local BoostConfig       = require(ReplicatedStorage.Modules.BoostConfig) 
local AchievementConfig = require(ReplicatedStorage.Modules.AchievementConfig)
local UITheme           = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UITheme"))
local T                 = UITheme.Get("Custom")

local BuyBoost      = ReplicatedStorage.RemoteEvents:WaitForChild("BuyBoost")
local ActivateBoost = ReplicatedStorage.RemoteEvents:WaitForChild("ActivateBoost")
local BoostUpdated  = ReplicatedStorage.RemoteEvents:WaitForChild("BoostUpdated")

-- ✨ BRIDGENET2 UPGRADE
local BridgeNet2      = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))
local UpdateHUDBridge = BridgeNet2.ClientBridge("UpdateHUD")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainHUD   = playerGui:WaitForChild("MainHUD")

local boostState = {}
local panelOpen  = false
local liveGold   = 0

local function PlayUI(id)
	if shared.PlayUISound then shared.PlayUISound(id) end
end

local function FormatTime(s)
	s = math.ceil(s or 0)
	if s <= 0 then return "0:00" end
	return string.format("%d:%02d", math.floor(s/60), s % 60)
end

---------------------------------------------------------------
-- ✨ ACTIVE BOOST STRIP (Sleek & Polished)
---------------------------------------------------------------
local BoostStrip = Instance.new("Frame")
BoostStrip.Name = "ActiveBoostStrip"
BoostStrip.Size = UDim2.new(0.14, 0, 0.5, 0) 
BoostStrip.AnchorPoint = Vector2.new(1, 0)
BoostStrip.Position = UDim2.new(0.98, 0, 0.5, 0) 
BoostStrip.BackgroundTransparency = 1
BoostStrip.ZIndex = 60; BoostStrip.Visible = false; BoostStrip.Parent = mainHUD

local StripLayout = Instance.new("UIListLayout")
StripLayout.FillDirection = Enum.FillDirection.Vertical
StripLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right 
StripLayout.VerticalAlignment = Enum.VerticalAlignment.Top
StripLayout.Padding = UDim.new(0, 6)
StripLayout.Parent = BoostStrip

local stripSlots = {}

for _, boostId in ipairs(BoostConfig.ShopOrder) do
	local cfg   = BoostConfig.Get(boostId)
	if not cfg then continue end
	local color = cfg.color

	local slot = Instance.new("Frame")
	slot.Name = "Slot_" .. boostId
	slot.Size = UDim2.new(1, 0, 0, 42)  
	slot.BackgroundColor3 = T.cardBG; slot.BorderSizePixel = 0
	slot.ZIndex = 61; slot.Visible = false; slot.Parent = BoostStrip
	Instance.new("UICorner", slot).CornerRadius = UDim.new(0, 8)
	local ss = Instance.new("UIStroke"); ss.Color = color; ss.Thickness = 1.5; ss.Parent = slot

	local iconFrame = Instance.new("Frame", slot)
	iconFrame.Size = UDim2.new(0, 32, 0, 32)
	iconFrame.Position = UDim2.new(0, 5, 0.5, -16)
	iconFrame.BackgroundColor3 = color
	iconFrame.BackgroundTransparency = 0.8
	Instance.new("UICorner", iconFrame).CornerRadius = UDim.new(0, 6)

	local iconLbl = Instance.new("ImageLabel", iconFrame)
	iconLbl.Size = UDim2.new(0.8, 0, 0.8, 0)
	iconLbl.Position = UDim2.new(0.1, 0, 0.1, 0)
	iconLbl.BackgroundTransparency = 1; iconLbl.Image = cfg.icon or ""
	iconLbl.ScaleType = Enum.ScaleType.Fit
	iconLbl.ZIndex = 62

	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size = UDim2.new(0.5, 0, 0.45, 0)
	nameLbl.Position = UDim2.new(0, 45, 0, 4)
	nameLbl.BackgroundTransparency = 1; nameLbl.Text = cfg.displayName or boostId
	nameLbl.TextColor3 = color; nameLbl.TextScaled = true
	nameLbl.Font = Enum.Font.FredokaOne; nameLbl.TextXAlignment = Enum.TextXAlignment.Left
	nameLbl.ZIndex = 62; nameLbl.Parent = slot

	local shadow = nameLbl:Clone()
	shadow.Name = "Shadow"
	shadow.ZIndex = 61
	shadow.TextColor3 = Color3.fromRGB(0,0,0)
	shadow.TextTransparency = 0.5
	shadow.Position = nameLbl.Position + UDim2.new(0,1,0,1)
	shadow.Parent = slot

	local timeLbl = Instance.new("TextLabel")
	timeLbl.Name = "TimeLabel"
	timeLbl.Size = UDim2.new(0.25, 0, 0.55, 0)
	timeLbl.Position = UDim2.new(1, -55, 0, 2)
	timeLbl.BackgroundTransparency = 1; timeLbl.Text = "0:30"
	timeLbl.TextColor3 = color; timeLbl.TextScaled = true
	timeLbl.Font = Enum.Font.FredokaOne; timeLbl.TextXAlignment = Enum.TextXAlignment.Right
	timeLbl.ZIndex = 62; timeLbl.Parent = slot

	local stackLbl = Instance.new("TextLabel")
	stackLbl.Name = "StackLabel"
	stackLbl.Size = UDim2.new(0.5, 0, 0.35, 0)
	stackLbl.Position = UDim2.new(0, 45, 0.5, 3)
	stackLbl.BackgroundTransparency = 1; stackLbl.Text = ""
	stackLbl.TextColor3 = T.subText; stackLbl.TextScaled = true
	stackLbl.Font = Enum.Font.GothamMedium; stackLbl.TextXAlignment = Enum.TextXAlignment.Left
	stackLbl.ZIndex = 62; stackLbl.Parent = slot

	stripSlots[boostId] = { slot = slot, timeLbl = timeLbl, stackLbl = stackLbl }
end

local BoostsBtn = Instance.new("ImageButton")
BoostsBtn.Name = "BoostsButton"
BoostsBtn.Size = UDim2.new(0, 60, 0, 60)
BoostsBtn.AnchorPoint = Vector2.new(1, 1) 
BoostsBtn.Position = UDim2.new(0.98, 0, 0.77, 0) 
BoostsBtn.BackgroundColor3 = T.buttonPrimary; BoostsBtn.BorderSizePixel = 0
BoostsBtn.AutoButtonColor = false
BoostsBtn.ZIndex = 10; BoostsBtn.Parent = mainHUD
BoostsBtn:SetAttribute("TutorialTarget", "BoostsButton")
Instance.new("UICorner", BoostsBtn).CornerRadius = UDim.new(0.5, 0)

local bbStroke = Instance.new("UIStroke", BoostsBtn)
bbStroke.Color = T.accentPurple; bbStroke.Thickness = 2

local boostIcon = Instance.new("ImageLabel", BoostsBtn)
boostIcon.Size = UDim2.new(0.6, 0, 0.6, 0); boostIcon.Position = UDim2.new(0.2, 0, 0.2, 0)
boostIcon.BackgroundTransparency = 1; boostIcon.ScaleType = Enum.ScaleType.Fit
boostIcon.Image = "rbxassetid://14916846070" 

-- ✨ TUTORIAL TAG: Enables automatic Padlock Overlay
CollectionService:AddTag(BoostsBtn, "Tutorial_BoostMenuBtn")

---------------------------------------------------------------
-- ✨ BOOST SHOP PANEL (Tutorial Style)
---------------------------------------------------------------
local ShopPanel = Instance.new("Frame")
ShopPanel.Name = "BoostShopPanel"
ShopPanel.Size = UDim2.new(0.85, 0, 0.8, 0) 
ShopPanel.Position = UDim2.new(0.5, 0, 0.5, 0)
ShopPanel.AnchorPoint = Vector2.new(0.5, 0.5) 
ShopPanel.BackgroundColor3 = T.panelBG; ShopPanel.BorderSizePixel = 0
ShopPanel.Visible = false; ShopPanel.ZIndex = 40
ShopPanel.ClipsDescendants = true
ShopPanel.Parent = mainHUD
Instance.new("UICorner", ShopPanel).CornerRadius = UDim.new(0, 14)

local sizeConstraint = Instance.new("UISizeConstraint")
sizeConstraint.MaxSize = Vector2.new(380, 520)
sizeConstraint.Parent = ShopPanel

local shopStroke = Instance.new("UIStroke")
shopStroke.Color = T.accentPurple; shopStroke.Thickness = 2; shopStroke.Parent = ShopPanel

local ShopHeader = Instance.new("Frame")
ShopHeader.Size = UDim2.new(1, 0, 0, 46)
ShopHeader.BackgroundColor3 = T.headerBG; ShopHeader.BorderSizePixel = 0
ShopHeader.ZIndex = 41; ShopHeader.Parent = ShopPanel
Instance.new("UICorner", ShopHeader).CornerRadius = UDim.new(0, 14)

local ShopTitle = Instance.new("TextLabel")
ShopTitle.Size = UDim2.new(1, -50, 1, 0); ShopTitle.Position = UDim2.new(0, 14, 0, 0)
ShopTitle.BackgroundTransparency = 1; ShopTitle.Text = "BOOST SHOP"
ShopTitle.TextColor3 = T.headerText; ShopTitle.TextScaled = true
ShopTitle.Font = Enum.Font.FredokaOne; ShopTitle.TextXAlignment = Enum.TextXAlignment.Left
ShopTitle.ZIndex = 42; ShopTitle.Parent = ShopHeader

local ShopClose = Instance.new("TextButton")
ShopClose.Size = UDim2.new(0, 32, 0, 32); ShopClose.Position = UDim2.new(1, -40, 0.5, -16)
ShopClose.BackgroundColor3 = T.buttonRed; ShopClose.BorderSizePixel = 0
ShopClose.Text = "X"; ShopClose.TextColor3 = T.bodyText
ShopClose.TextScaled = true; ShopClose.Font = Enum.Font.FredokaOne
ShopClose.ZIndex = 9999; ShopClose.Parent = ShopHeader
Instance.new("UICorner", ShopClose).CornerRadius = UDim.new(0, 6)

local ScrollContainer = Instance.new("ScrollingFrame")
ScrollContainer.Name = "ScrollContainer"
ScrollContainer.Size = UDim2.new(1, 0, 1, -56) 
ScrollContainer.Position = UDim2.new(0, 0, 0, 56)
ScrollContainer.BackgroundTransparency = 1
ScrollContainer.BorderSizePixel = 0
ScrollContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
ScrollContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y
ScrollContainer.ScrollBarThickness = 6
ScrollContainer.Parent = ShopPanel

local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 10)
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
listLayout.Parent = ScrollContainer

local topPadding = Instance.new("UIPadding")
topPadding.PaddingTop = UDim.new(0, 5)
topPadding.PaddingBottom = UDim.new(0, 15)
topPadding.Parent = ScrollContainer

local function AddButtonJuice(btn)
	local scale = btn:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = btn
	end

	btn.MouseEnter:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Sine), {Scale = 1.05}):Play() end)
	btn.MouseLeave:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Sine), {Scale = 1}):Play() end)
	btn.MouseButton1Down:Connect(function() TweenService:Create(scale, TweenInfo.new(0.1, Enum.EasingStyle.Sine), {Scale = 0.95}):Play() end)
	btn.MouseButton1Up:Connect(function() TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), {Scale = 1.05}):Play() end)
end

AddButtonJuice(BoostsBtn)
AddButtonJuice(ShopClose)

local cardRefs = {}

local function BuildCards()
	for i, boostId in ipairs(BoostConfig.ShopOrder) do
		local cfg = BoostConfig.Get(boostId)
		if not cfg then continue end
		local color = cfg.color

		local card = Instance.new("Frame")
		card.Size = UDim2.new(1, -20, 0, 105) 
		card.BackgroundColor3 = T.cardBG; card.BorderSizePixel = 0
		card.ZIndex = 41; card.Parent = ScrollContainer
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)

		local cs = Instance.new("UIStroke"); cs.Color = color; cs.Thickness = 1.5; cs.Parent = card

		local iconFrame = Instance.new("Frame", card)
		iconFrame.Size = UDim2.new(0, 48, 0, 48)
		iconFrame.Position = UDim2.new(0, 10, 0.5, -24)
		iconFrame.BackgroundColor3 = color
		iconFrame.BackgroundTransparency = 0.85
		Instance.new("UICorner", iconFrame).CornerRadius = UDim.new(0, 10)

		local iconLbl = Instance.new("ImageLabel", iconFrame)
		iconLbl.Size = UDim2.new(0.7, 0, 0.7, 0); iconLbl.Position = UDim2.new(0.15, 0, 0.15, 0)
		iconLbl.BackgroundTransparency = 1; iconLbl.Image = cfg.icon or ""
		iconLbl.ScaleType = Enum.ScaleType.Fit; iconLbl.ZIndex = 42

		local nameLbl = Instance.new("TextLabel")
		nameLbl.Size = UDim2.new(0.5, 0, 0, 22); nameLbl.Position = UDim2.new(0, 68, 0, 10)
		nameLbl.BackgroundTransparency = 1; nameLbl.Text = string.upper(cfg.displayName or boostId)
		nameLbl.TextColor3 = color; nameLbl.TextScaled = true
		nameLbl.Font = Enum.Font.FredokaOne; nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		nameLbl.ZIndex = 42; nameLbl.Parent = card

		local shadow = nameLbl:Clone()
		shadow.Name = "Shadow"; shadow.ZIndex = 41; shadow.TextColor3 = Color3.fromRGB(0,0,0)
		shadow.TextTransparency = 0.6; shadow.Position = nameLbl.Position + UDim2.new(0,2,0,2)
		shadow.Parent = card

		local descLbl = Instance.new("TextLabel")
		descLbl.Size = UDim2.new(0.65, 0, 0, 36); descLbl.Position = UDim2.new(0, 68, 0, 35)
		descLbl.BackgroundTransparency = 1; descLbl.Text = cfg.description or ""
		descLbl.TextColor3 = T.subText; descLbl.TextScaled = true; descLbl.TextWrapped = true
		descLbl.Font = Enum.Font.GothamMedium; descLbl.TextXAlignment = Enum.TextXAlignment.Left; descLbl.TextYAlignment = Enum.TextYAlignment.Top
		descLbl.ZIndex = 42; descLbl.Parent = card

		local durLbl = Instance.new("TextLabel")
		durLbl.Size = UDim2.new(0.65, 0, 0, 14); durLbl.Position = UDim2.new(0, 68, 0, 75)
		durLbl.BackgroundTransparency = 1; durLbl.Text = cfg.duration == 0 and "Instant Use" or (FormatTime(cfg.duration) .. " duration")
		durLbl.TextColor3 = Color3.fromRGB(130, 135, 160); durLbl.TextScaled = true
		durLbl.Font = Enum.Font.GothamMedium; durLbl.TextXAlignment = Enum.TextXAlignment.Left
		durLbl.ZIndex = 42; durLbl.Parent = card

		local buyBtn = Instance.new("TextButton")
		buyBtn.Size = UDim2.new(0, 90, 0, 40); buyBtn.Position = UDim2.new(1, -100, 0, 10)
		buyBtn.BorderSizePixel = 0; buyBtn.TextScaled = true; buyBtn.Font = Enum.Font.FredokaOne
		buyBtn.ZIndex = 42; buyBtn.Parent = card
		Instance.new("UICorner", buyBtn).CornerRadius = UDim.new(0, 8)
		AddButtonJuice(buyBtn)

		local actBtn = Instance.new("TextButton")
		actBtn.Size = UDim2.new(0, 90, 0, 40); actBtn.Position = UDim2.new(1, -100, 0, 55)
		actBtn.BorderSizePixel = 0; actBtn.TextScaled = true; actBtn.Font = Enum.Font.FredokaOne
		actBtn.ZIndex = 42; actBtn.Parent = card
		Instance.new("UICorner", actBtn).CornerRadius = UDim.new(0, 8)
		AddButtonJuice(actBtn)

		local invBadge = Instance.new("TextLabel")
		invBadge.Size = UDim2.new(0, 28, 0, 20); invBadge.Position = UDim2.new(0, 10, 1, -30)
		invBadge.BackgroundColor3 = Color3.fromRGB(20, 20, 30); invBadge.BorderSizePixel = 0
		invBadge.Text = "x0"; invBadge.TextColor3 = T.bodyText
		invBadge.TextScaled = true; invBadge.Font = Enum.Font.FredokaOne
		invBadge.ZIndex = 43; invBadge.Parent = card
		Instance.new("UICorner", invBadge).CornerRadius = UDim.new(0, 6)
		local invStroke = Instance.new("UIStroke", invBadge)
		invStroke.Color = T.panelStroke; invStroke.Thickness = 1.5

		cardRefs[boostId] = { card=card, cs=cs, buyBtn=buyBtn, actBtn=actBtn, invBadge=invBadge, descLbl=descLbl, color=color }

		buyBtn.MouseButton1Down:Connect(function() BuyBoost:FireServer(boostId) end)
		actBtn.MouseButton1Down:Connect(function()
			local state = boostState[boostId]
			if not state or (state.inventoryCount or 0) <= 0 then return end
			ActivateBoost:FireServer(boostId)
		end)
	end
end

BuildCards()
local latestStats = {}

local function RefreshCards()
	for boostId, refs in pairs(cardRefs) do
		local cfg         = BoostConfig.Get(boostId)
		local state       = boostState[boostId]
		local color       = refs.color
		local invCount    = state and (state.inventoryCount or 0) or 0
		local activeCount = state and (state.activeCount or 0) or 0
		local cost        = cfg and cfg.cost or 0
		local canAfford   = liveGold >= cost
		local atCap       = activeCount >= (cfg and cfg.maxStack or 1)

		local isUnlocked, lockReason = AchievementConfig.IsBoostUnlocked(boostId, latestStats)

		refs.invBadge.Text       = "x" .. invCount
		refs.invBadge.TextColor3 = invCount > 0 and T.accentGold or T.subText

		if not isUnlocked then
			refs.buyBtn.Text             = "LOCKED"
			refs.buyBtn.BackgroundColor3 = T.buttonRed
			refs.buyBtn.TextColor3       = T.bodyText

			refs.actBtn.Text             = "Locked"
			refs.actBtn.BackgroundColor3 = T.buttonDisabled
			refs.actBtn.TextColor3       = T.subText

			refs.descLbl.Text = "Requires: " .. lockReason
			refs.descLbl.TextColor3 = T.buttonRed
		else
			refs.descLbl.Text = cfg.description or ""
			refs.descLbl.TextColor3 = T.subText

			refs.buyBtn.Text             = cost .. " ⭐"
			refs.buyBtn.TextColor3       = T.bodyText
			refs.buyBtn.BackgroundColor3 = canAfford and T.buttonGreen or T.buttonDisabled

			if invCount <= 0 then
				refs.actBtn.Text             = "No Stock"
				refs.actBtn.BackgroundColor3 = T.buttonDisabled
				refs.actBtn.TextColor3       = T.subText
			elseif atCap then
				refs.actBtn.Text             = "MAX (" .. FormatTime(state and state.activeTimes and state.activeTimes[1] or 0) .. ")"
				refs.actBtn.BackgroundColor3 = Color3.fromRGB(40, 80, 50)
				refs.actBtn.TextColor3       = color
			else
				refs.actBtn.Text             = "Activate"
				refs.actBtn.BackgroundColor3 = color
				refs.actBtn.TextColor3       = T.bodyText
			end
		end
	end
end

local function RefreshStrip()
	local anyActive = false
	for _, boostId in ipairs(BoostConfig.ShopOrder) do
		local state = boostState[boostId]
		local refs  = stripSlots[boostId]
		if not refs then continue end
		if state and (state.activeCount or 0) > 0 then
			anyActive = true; refs.slot.Visible = true
			local minTime = math.huge
			for _, t in ipairs(state.activeTimes or {}) do if t < minTime then minTime = t end end
			refs.timeLbl.Text  = FormatTime(minTime)
			refs.stackLbl.Text = state.activeCount > 1 and ("x" .. state.activeCount) or ""
		else
			refs.slot.Visible = false
		end
	end
	BoostStrip.Visible = anyActive
end

local function OpenPanel()
	panelOpen = true; ShopPanel.Visible = true
	ShopPanel.Size = UDim2.new(0.85, 0, 0, 0)
	RefreshCards()
	TweenService:Create(ShopPanel, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0.85, 0, 0.8, 0)
	}):Play()
	UITheme.SetMenuVisible(true)
end

local function ClosePanel()
	panelOpen = false
	PlayUI(SoundConfig.UIClose)
	TweenService:Create(ShopPanel, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Size = UDim2.new(0.85, 0, 0, 0)
	}):Play()
	UITheme.SetMenuVisible(false)
	task.delay(0.3, function() ShopPanel.Visible = false end)
end

BoostsBtn.MouseButton1Down:Connect(function() 
	-- ✨ TUTORIAL GATING
	if not panelOpen then
		if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_OpenBoostShop") then return end
	end
	if panelOpen then ClosePanel() else OpenPanel() end 
end)
ShopClose.MouseButton1Down:Connect(ClosePanel)

BoostUpdated.OnClientEvent:Connect(function(state)
	if state._goldenAuras ~= nil then liveGold = state._goldenAuras; state._goldenAuras = nil end
	boostState = state; RefreshStrip()
	if panelOpen then RefreshCards() end
end)

UpdateHUDBridge:Connect(function(stats)
	for key, value in pairs(stats) do
		latestStats[key] = value
	end
	if stats.goldenAuras ~= nil then liveGold = stats.goldenAuras end
	if stats.boostInventory then
		for boostId, count in pairs(stats.boostInventory) do
			if boostState[boostId] then boostState[boostId].inventoryCount = count end
		end
	end
	if panelOpen then RefreshCards() end
end)

RunService.RenderStepped:Connect(function(dt)
	local anyActive = false
	for _, boostId in ipairs(BoostConfig.ShopOrder) do
		local state = boostState[boostId]
		if state and state.activeTimes and #state.activeTimes > 0 then
			anyActive = true
			local clean = {}
			for _, t in ipairs(state.activeTimes) do
				local newT = math.max(0, t - dt)
				if newT > 0 then table.insert(clean, newT) end
			end
			state.activeTimes = clean; state.activeCount = #clean
			local refs = stripSlots[boostId]
			if refs then
				if #clean > 0 then
					local minTime = math.huge
					for _, t in ipairs(clean) do if t < minTime then minTime = t end end
					refs.timeLbl.Text  = FormatTime(minTime)
					refs.stackLbl.Text = #clean > 1 and ("x" .. #clean) or ""
					refs.slot.Visible  = true
				else
					refs.slot.Visible = false
				end
			end
		end
	end
	BoostStrip.Visible = anyActive
end)

local shopShine = nil
local function RefreshLook()
	UITheme.Apply(ShopPanel, "Panel")
	UITheme.Apply(ShopHeader, "TitleBar")
	if not shopShine then
		shopShine = UITheme.ApplyShine(ShopPanel)
	end
	for _, card in ipairs(ScrollContainer:GetChildren()) do
		if card:IsA("Frame") then
			UITheme.Apply(card, "ShopCard")
		end
	end
end

task.wait(1) 
RefreshLook()

-- ✨ TUTORIAL OVERRIDE: Close shop when camera pans
local forceClose = ReplicatedStorage:FindFirstChild("ForceCloseUI") or Instance.new("BindableEvent")
forceClose.Name = "ForceCloseUI"
forceClose.Parent = ReplicatedStorage
forceClose.Event:Connect(function()
	if panelOpen then ClosePanel() end
end)
