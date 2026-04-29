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

local function AutoScrollToTarget(target)
	local scrollFrame = target:FindFirstAncestorOfClass("ScrollingFrame")
	if scrollFrame then
		local relativeY = (target.AbsolutePosition.Y - scrollFrame.AbsolutePosition.Y) + scrollFrame.CanvasPosition.Y
		local targetCanvasY = relativeY - (scrollFrame.AbsoluteSize.Y / 2) + (target.AbsoluteSize.Y / 2)
		local maxScroll = math.max(0, scrollFrame.CanvasSize.Y.Offset - scrollFrame.AbsoluteSize.Y)

		TweenService:Create(scrollFrame, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CanvasPosition = Vector2.new(scrollFrame.CanvasPosition.X, math.clamp(targetCanvasY, 0, maxScroll))
		}):Play()

		task.wait(0.35) 
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

		pointerUpdate = RunService.RenderStepped:Connect(function()
			if not activePointer or not activeHighlight or not target or not target.Parent then
				ClearVisuals()
				if target then target.ZIndex = originalZIndex end
				return
			end

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
							target.ZIndex = originalZIndex

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
					target.ZIndex = originalZIndex

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




-- ShopController
-- Location: StarterPlayer > StarterPlayerScripts > ShopController

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")

local UpgradeConfig     = require(ReplicatedStorage.Modules.UpgradeConfig)
local Formatter         = require(ReplicatedStorage.Modules.NumberFormatter)
local EpicUpgradeConfig = require(ReplicatedStorage.Modules.EpicUpgradeConfig)
local T                 = require(ReplicatedStorage.Modules.UITheme).Get()
local SoundConfig       = require(ReplicatedStorage.Modules.SoundConfig)
local UITheme = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UITheme"))
local T = UITheme.Get("Custom") 
local RemoteEvents      = ReplicatedStorage:WaitForChild("RemoteEvents")
local PurchaseUpgrade     = RemoteEvents:WaitForChild("PurchaseUpgrade", 15)
local UpgradeUpdated      = RemoteEvents:WaitForChild("UpgradeUpdated", 15)
local PurchaseEpicUpgrade = RemoteEvents:WaitForChild("PurchaseEpicUpgrade", 15)
local EpicUpgradeUpdated  = RemoteEvents:WaitForChild("EpicUpgradeUpdated", 15)

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainHUD   = playerGui:WaitForChild("MainHUD")

local upgradeState     = {}
local epicUpgradeState  = {}
local currentCurrency   = 0
local liveGoldenAuras   = 0
local shopOpen          = false
local activeMainTab     = "Upgrades"
local activeEpicSubTab  = "Active"
local regularCardRefs   = {}
local epicCardRefs      = {}
local isLoadingData     = true

---------------------------------------------------------------
-- INITIALIZATION (TIERED)
---------------------------------------------------------------
for _, tierData in ipairs(UpgradeConfig.Tiers) do
	for upgradeId, cfg in pairs(tierData.upgrades) do
		upgradeState[upgradeId] = {
			level = 0, maxLevel = cfg.maxLevel,
			cost = UpgradeConfig.CalculateCost(upgradeId, 0), maxed = false,
		}
	end
end

for _, tierData in ipairs(EpicUpgradeConfig.Tiers) do
	for upgradeId, cfg in pairs(tierData.upgrades) do
		epicUpgradeState[upgradeId] = {
			level = 0, maxLevel = cfg.maxLevel,
			cost = EpicUpgradeConfig.CalculateCost(upgradeId, 0), maxed = false,
		}
	end
end

local function PlayUIBurst(targetElement, amount, colorTheme)
	if not shopOpen then return end
	local burstGui = Instance.new("ScreenGui")
	burstGui.Name = "JuiceBurst"
	burstGui.Parent = playerGui

	local absPos = targetElement.AbsolutePosition
	local absSize = targetElement.AbsoluteSize
	local center = absPos + (absSize / 2)

	for i = 1, amount do
		local particle = Instance.new("Frame")
		particle.BackgroundColor3 = colorTheme or Color3.fromRGB(255, 215, 0) -- Default Gold
		particle.BorderSizePixel = 0
		particle.Size = UDim2.new(0, math.random(6, 12), 0, math.random(6, 12))
		particle.Position = UDim2.new(0, center.X, 0, center.Y)
		particle.Rotation = math.random(0, 360)

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = particle
		particle.Parent = burstGui

		local angle = math.rad(math.random(0, 360))
		local distance = math.random(50, 150)
		local endPos = UDim2.new(0, center.X + math.cos(angle) * distance, 0, center.Y + math.sin(angle) * distance + 50) 

		local tInfo = TweenInfo.new(math.random(4, 7)/10, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out)
		local tween = TweenService:Create(particle, tInfo, {
			Position = endPos,
			Size = UDim2.new(0, 0, 0, 0),
			Rotation = particle.Rotation + math.random(-180, 180),
			BackgroundTransparency = 1
		})
		tween:Play()
	end

	task.delay(1, function() burstGui:Destroy() end)
end

local comboPitch = 1.0
local lastBuyTime = tick()

local function PlayPurchaseSound()
	if tick() - lastBuyTime < 0.3 then
		comboPitch = math.min(comboPitch + 0.05, 2.5) 
	else
		comboPitch = 1.0 
	end
	lastBuyTime = tick()

	local soundsFolder = ReplicatedStorage:FindFirstChild("SFX") or ReplicatedStorage:FindFirstChild("Sounds")
	if soundsFolder and soundsFolder:FindFirstChild("BuyPing") then
		local sfx = soundsFolder.BuyPing:Clone() 
		sfx.PlaybackSpeed = comboPitch
		sfx.Parent = game:GetService("SoundService")
		sfx:Play()
		game.Debris:AddItem(sfx, 2)
	end
end

local function PlayFeedbackSound(soundName, volume)
	local soundsFolder = ReplicatedStorage:FindFirstChild("SFX") or ReplicatedStorage:FindFirstChild("Sounds")
	local soundToPlay = nil

	if soundsFolder then
		soundToPlay = soundsFolder:FindFirstChild(soundName)
	end

	if soundToPlay then
		local sfx = soundToPlay:Clone()
		sfx.Volume = volume or 0.5
		sfx.Parent = game:GetService("SoundService") 
		sfx:Play()
		game.Debris:AddItem(sfx, 3)
	else
		warn("⚠️ UI Sound Missing: You need to add a sound named '" .. tostring(soundName) .. "' inside ReplicatedStorage.SFX!")
	end
end

local lastErrorTime = tick()

local function PlayErrorFeedback(targetButton)
	if tick() - lastErrorTime < 0.25 then return end
	lastErrorTime = tick()

	local soundsFolder = ReplicatedStorage:FindFirstChild("Sounds") or ReplicatedStorage:FindFirstChild("SFX")
	if soundsFolder and soundsFolder:FindFirstChild("ErrorBuzz") then
		local sfx = soundsFolder.ErrorBuzz:Clone()
		sfx.Volume = 0.5 
		sfx.Parent = workspace
		sfx:Play()
		game.Debris:AddItem(sfx, 2)
	end

	if targetButton and targetButton.Parent then
		local origPos = targetButton.Position
		local wobbleInfo = TweenInfo.new(0.04, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 3, true)
		TweenService:Create(targetButton, wobbleInfo, {Position = origPos + UDim2.new(0, 4, 0, 0)}):Play()
	end
end

-----------------------------------------------------------
-- HELPERS
---------------------------------------------------------------
local function FormatNumber(n) return Formatter.Format(n) end
local function PlayUI(id) if shared.PlayUISound then shared.PlayUISound(id) end end

local ShopButton = Instance.new("ImageButton")
ShopButton.Name="ShopButton"; ShopButton.Size=UDim2.new(0,60,0,60)
ShopButton.AnchorPoint = Vector2.new(1, 1) -- ✨ Anchors perfectly to bottom right
ShopButton.Position = UDim2.new(0.98, 0, 0.95, 0) -- ✨ Scaled position
ShopButton.BackgroundColor3=T.buttonSecondary; ShopButton.BorderSizePixel=0
ShopButton.AutoButtonColor = false
ShopButton.ZIndex=5; ShopButton.Parent=mainHUD
ShopButton:SetAttribute("TutorialTarget", "ShopButton")
Instance.new("UICorner",ShopButton).CornerRadius=UDim.new(0.5, 0)

local shopStroke = Instance.new("UIStroke", ShopButton)
shopStroke.Color = T.accentGold; shopStroke.Thickness = 2

local shopIcon = Instance.new("ImageLabel", ShopButton)
shopIcon.Size = UDim2.new(0.6, 0, 0.6, 0); shopIcon.Position = UDim2.new(0.2, 0, 0.2, 0)
shopIcon.BackgroundTransparency = 1; shopIcon.ScaleType = Enum.ScaleType.Fit
shopIcon.Image = "rbxassetid://14916846070" -- 🖼️ PLACEHOLDER: Cart Icon ID


---------------------------------------------------------------
-- SHOP PANEL
---------------------------------------------------------------
local PANEL_MAX_W=420; local PANEL_MAX_H=510; local HEADER_H=42
local MAINTAB_H=34; local SUBTAB_H=30; local CURRENCY_H=0

local ShopPanel=Instance.new("Frame"); ShopPanel.Name="ShopPanel"
ShopPanel.Size=UDim2.new(0.88, 0, 0.82, 0)
ShopPanel.AnchorPoint=Vector2.new(0.5, 0.5)
ShopPanel.Position=UDim2.new(0.5, 0, 0.5, 0)
ShopPanel.BackgroundColor3=T.panelBG; ShopPanel.BorderSizePixel=0
ShopPanel.Visible=false; ShopPanel.ZIndex=10; ShopPanel.ClipsDescendants=true
ShopPanel.Parent=mainHUD
Instance.new("UICorner",ShopPanel).CornerRadius=UDim.new(0,10)
local sizeConstraint=Instance.new("UISizeConstraint"); sizeConstraint.MaxSize=Vector2.new(PANEL_MAX_W, PANEL_MAX_H); sizeConstraint.Parent=ShopPanel
local panelStroke=Instance.new("UIStroke"); panelStroke.Color=T.panelStroke; panelStroke.Thickness=2; panelStroke.Parent=ShopPanel

local TitleBar=Instance.new("Frame"); TitleBar.Name="TitleBar"
TitleBar.Size=UDim2.new(1,0,0,HEADER_H)
TitleBar.BackgroundColor3=T.headerBG; TitleBar.BorderSizePixel=0; TitleBar.ZIndex=11; TitleBar.Parent=ShopPanel
TitleBar.ClipsDescendants=true 
TitleBar.BackgroundTransparency = 1
Instance.new("UICorner",TitleBar).CornerRadius=UDim.new(0,10)
local TitleLabel=Instance.new("TextLabel"); TitleLabel.Size=UDim2.new(1,-50,1,0); TitleLabel.Position=UDim2.new(0,15,0,0)
TitleLabel.BackgroundTransparency=1; TitleLabel.Text="RESEARCH"; TitleLabel.TextColor3=T.headerText
TitleLabel.TextScaled=true; TitleLabel.Font=T.font; TitleLabel.TextXAlignment=Enum.TextXAlignment.Left
TitleLabel.ZIndex=12; TitleLabel.Parent=TitleBar
local CloseButton=Instance.new("TextButton"); CloseButton.Size=UDim2.new(0,30,0,30); CloseButton.Position=UDim2.new(1,-35,0,6)
CloseButton.BackgroundColor3=T.buttonRed; CloseButton.BorderSizePixel=0; CloseButton.Text="X"; CloseButton.TextColor3=T.bodyText
CloseButton.TextScaled=true; CloseButton.Font=T.font; CloseButton.ZIndex=9999; CloseButton.Parent=TitleBar
CloseButton:SetAttribute("TutorialTarget", "ShopCloseBtn")
Instance.new("UICorner",CloseButton).CornerRadius=UDim.new(0,6)

---------------------------------------------------------------
-- INFO POPUP (SCALED & CONSTRAINED SQUARE)
---------------------------------------------------------------
local InfoPopup = Instance.new("Frame")
InfoPopup.Name = "InfoPopup"
InfoPopup.Size = UDim2.new(0.85, 0, 0.6, 0) -- ✨ Now sizes relative to the Shop Panel!
InfoPopup.Position = UDim2.new(0.5, 0, 0.5, 0)
InfoPopup.AnchorPoint = Vector2.new(0.5, 0.5)
InfoPopup.BackgroundColor3 = T.cardBG 
InfoPopup.BackgroundTransparency = 0 
InfoPopup.ZIndex = 50
InfoPopup.Visible = false
InfoPopup.Parent = ShopPanel -- ✨ PARENT CHANGED FROM mainHUD TO ShopPanel
Instance.new("UICorner", InfoPopup).CornerRadius = UDim.new(0, 12)

-- ✨ FORCES IT TO BE A SQUARE REGARDLESS OF SCREEN SIZE
local AspectConstraint = Instance.new("UIAspectRatioConstraint", InfoPopup)
AspectConstraint.AspectRatio = 1.0 -- 1.0 means a perfect 1:1 square!

local InfoScale = Instance.new("UIScale", InfoPopup)
InfoScale.Scale = 1

local InfoTitle = Instance.new("TextLabel", InfoPopup)
InfoTitle.Size = UDim2.new(1, -20, 0, 35)
InfoTitle.Position = UDim2.new(0, 10, 0, 10)
InfoTitle.BackgroundTransparency = 1
InfoTitle.Text = ""
InfoTitle.TextColor3 = T.headerText
InfoTitle.TextScaled = true
InfoTitle.Font = Enum.Font.GothamBold
InfoTitle.ZIndex = 51

local InfoDesc = Instance.new("TextLabel", InfoPopup)
InfoDesc.Size = UDim2.new(1, -20, 1, -110)
InfoDesc.Position = UDim2.new(0, 10, 0, 55)
InfoDesc.BackgroundTransparency = 1
InfoDesc.Text = ""
InfoDesc.TextColor3 = T.bodyText
InfoDesc.TextWrapped = true
InfoDesc.TextScaled = true
InfoDesc.Font = T.font
InfoDesc.TextYAlignment = Enum.TextYAlignment.Top
InfoDesc.ZIndex = 51

local InfoClose = Instance.new("TextButton", InfoPopup)
InfoClose.Size = UDim2.new(0.6, 0, 0, 40) -- Made slightly narrower to fit the square look
InfoClose.Position = UDim2.new(0.2, 0, 1, -50)
InfoClose.BackgroundColor3 = T.buttonPrimary
InfoClose.BorderSizePixel = 0
InfoClose.Text = "Close"
InfoClose.TextColor3 = T.headerText
InfoClose.TextScaled = true
InfoClose.Font = T.font
InfoClose.ZIndex = 51
Instance.new("UICorner", InfoClose).CornerRadius = UDim.new(0, 8)

local function ShowInfo(title, desc)
	if shared.PlayUISound then shared.PlayUISound(SoundConfig.UIClick or "") end
	InfoTitle.Text = title
	InfoDesc.Text = desc
	InfoPopup.BackgroundTransparency = 0 

	InfoScale.Scale = 0.5
	InfoPopup.Visible = true
	game:GetService("TweenService"):Create(InfoScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
end

InfoClose.MouseButton1Down:Connect(function()
	if shared.PlayUISound then shared.PlayUISound(SoundConfig.UIClick or "") end
	local tween = game:GetService("TweenService"):Create(InfoScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In), {Scale = 0.5})
	tween:Play()
	tween.Completed:Once(function()
		InfoPopup.Visible = false
	end)
end)

---------------------------------------------------------------
-- CIRCULAR SHOP TABS
---------------------------------------------------------------
local activeShopTabText = "Regular Upgrades"

local MainTabBar = Instance.new("Frame")
MainTabBar.Size = UDim2.new(1, -20, 0, 85) -- ✨ Made taller (was 75)
MainTabBar.Position = UDim2.new(0, 10, 0, HEADER_H + 4)
MainTabBar.BackgroundTransparency = 1; MainTabBar.ZIndex = 11; MainTabBar.Parent = ShopPanel

-- ✨ MOVED TEXT TO THE TOP OF THE BAR
local ShopHoverLabel = Instance.new("TextLabel", MainTabBar)
ShopHoverLabel.Size = UDim2.new(1, 0, 0, 20)
ShopHoverLabel.Position = UDim2.new(0, 0, 0, 0) -- Locks perfectly to the top
ShopHoverLabel.BackgroundTransparency = 1; ShopHoverLabel.TextColor3 = T.bodyText
ShopHoverLabel.TextScaled = true; ShopHoverLabel.Font = T.font
ShopHoverLabel.Text = activeShopTabText

-- ✨ PUSHED THE BUTTONS DOWN SO THEY DON'T OVERLAP
local TabBtnFrame = Instance.new("Frame", MainTabBar)
TabBtnFrame.Size = UDim2.new(1, 0, 1, -25)
TabBtnFrame.Position = UDim2.new(0, 0, 0, 25) -- Pushed down 25 pixels
TabBtnFrame.BackgroundTransparency = 1

local TabListLayout = Instance.new("UIListLayout", TabBtnFrame)
TabListLayout.FillDirection = Enum.FillDirection.Horizontal
TabListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
TabListLayout.VerticalAlignment = Enum.VerticalAlignment.Center
TabListLayout.Padding = UDim.new(0, 25)

-- (Keep your local mainTabButtons = {} and MakeMainTab function exactly as it is below this!)

local TAB_COLOR_BASE   = T.buttonSecondary
local TAB_COLOR_HOVER  = T.buttonPrimary    -- Color when mouse is over it
local TAB_COLOR_ACTIVE = T.accentGold       -- Color when tab is selected

local mainTabButtons = {}
local function MakeMainTab(name, hoverText, iconId)
	local btn = Instance.new("ImageButton", TabBtnFrame)
	btn.Name = "MainTab_" .. name
	btn.Size = UDim2.new(0, 48, 0, 48)
	btn.BackgroundColor3 = TAB_COLOR_BASE; btn.AutoButtonColor = false
	btn.ZIndex = 12
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0.5, 0)

	local stroke = Instance.new("UIStroke", btn)
	stroke.Color = T.panelStroke; stroke.Thickness = 2

	local icon = Instance.new("ImageLabel", btn)
	icon.Size = UDim2.new(0.6, 0, 0.6, 0); icon.Position = UDim2.new(0.2, 0, 0.2, 0)
	icon.BackgroundTransparency = 1; icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = iconId

	-- ✨ SMART HOVER LOGIC
	btn.MouseEnter:Connect(function() 
		ShopHoverLabel.Text = hoverText 
		if activeMainTab ~= name then btn.BackgroundColor3 = TAB_COLOR_HOVER end
	end)

	btn.MouseLeave:Connect(function() 
		ShopHoverLabel.Text = activeShopTabText 
		if activeMainTab ~= name then btn.BackgroundColor3 = TAB_COLOR_BASE end
	end)

	mainTabButtons[name] = {btn = btn, stroke = stroke}
	return btn
end
local tabEpic     = MakeMainTab("Epic", "Epic Research", "rbxassetid://14916846070")

local tabUpgrades = MakeMainTab("Upgrades", "Regular Upgrades", "rbxassetid://14916846070")

-----------------------------
-- CURRENCY LABEL
---------------------------------------------------------------
local CurrencyLabel=Instance.new("TextLabel"); CurrencyLabel.Name="ShopCurrencyLabel"
CurrencyLabel.Size=UDim2.new(1,-24,0,CURRENCY_H); CurrencyLabel.BackgroundTransparency=1
CurrencyLabel.Text="$0"; CurrencyLabel.TextColor3=T.currencyColor; CurrencyLabel.TextScaled=true
CurrencyLabel.Font=T.font; CurrencyLabel.TextXAlignment=Enum.TextXAlignment.Right
CurrencyLabel.ZIndex=11; CurrencyLabel.Parent=ShopPanel

local function MakeScroll(name,yTop)
	local sf=Instance.new("ScrollingFrame"); sf.Name=name
	sf.Size=UDim2.new(1,-20,1,-(yTop+10)); sf.Position=UDim2.new(0,10,0,yTop)
	sf.BackgroundTransparency=1; sf.BorderSizePixel=0; sf.ScrollBarThickness=4; sf.ScrollBarImageColor3=T.subText
	sf.CanvasSize=UDim2.new(0,0,0,0); sf.ZIndex=11; sf.Visible=false; sf.Parent=ShopPanel

	-- ✨ THIS IS THE MAGIC LINE THAT STOPS SCROLL OVERLAP:
	sf.ClipsDescendants = true 

	local layout=Instance.new("UIListLayout"); layout.Padding=UDim.new(0,8); layout.Parent=sf
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		sf.CanvasSize=UDim2.new(0,0,0,layout.AbsoluteContentSize.Y+10)
	end); return sf
end

-- ✨ Math fixed: Pushed down to clear the 85px tall MainTabBar
local REGULAR_SCROLL_TOP = HEADER_H + 95 
local RegularScroll = MakeScroll("RegularScroll", REGULAR_SCROLL_TOP)
local EPIC_SCROLL_TOP = HEADER_H + 95
local EpicScroll = MakeScroll("EpicScroll", EPIC_SCROLL_TOP)

local activeEpicSubTab = "Epic"
---------------------------------------------------------------
-- CARD BUILDER
---------------------------------------------------------------
local function BuildCard(parent, upgradeId, cfg, isEpic, cardRefsTable)
	local card = Instance.new("Frame")
	card.Name = "Card_"..upgradeId
	card.Size = UDim2.new(1, 0, 0, 100)
	card.BackgroundColor3 = T.cardBG 
	card.BorderSizePixel = 0; card.Parent = parent
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)

	local icon = Instance.new("ImageLabel", card)
	icon.Size = UDim2.new(0, 50, 0, 50); icon.Position = UDim2.new(0, 15, 0.5, -25)
	icon.BackgroundTransparency = 1
	icon.Image = cfg.iconId or "rbxassetid://0" 

	local infoBtn = Instance.new("TextButton", card)
	infoBtn.Size = UDim2.new(0, 22, 0, 22); infoBtn.Position = UDim2.new(0, 75, 0, 12)
	infoBtn.BackgroundColor3 = T.buttonSecondary 
	infoBtn.Text = "i"; infoBtn.TextColor3 = T.bodyText
	infoBtn.Font = Enum.Font.GothamBlack; infoBtn.TextSize = 14
	Instance.new("UICorner", infoBtn).CornerRadius = UDim.new(1, 0)
	infoBtn.MouseButton1Click:Connect(function() ShowInfo(cfg.displayName, cfg.description) end)

	local nameLabel = Instance.new("TextLabel", card)
	nameLabel.Size = UDim2.new(0.74, -120, 0, 24); nameLabel.Position = UDim2.new(0, 102, 0, 11)
	nameLabel.BackgroundTransparency = 1; nameLabel.Text = string.upper(cfg.displayName)
	nameLabel.TextColor3 = T.bodyText 
	nameLabel.TextScaled = true; nameLabel.Font = Enum.Font.FredokaOne
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left

	local descLabel = Instance.new("TextLabel", card)
	descLabel.Size = UDim2.new(0.74, -95, 0, 36); descLabel.Position = UDim2.new(0, 75, 0, 38)
	descLabel.BackgroundTransparency = 1; descLabel.Text = cfg.description
	descLabel.TextColor3 = T.subText 
	descLabel.TextWrapped = true; descLabel.TextSize = 16; descLabel.Font = Enum.Font.GothamMedium
	descLabel.TextXAlignment = Enum.TextXAlignment.Left; descLabel.TextYAlignment = Enum.TextYAlignment.Top

	local levelLabel = Instance.new("TextLabel", card)
	levelLabel.Size = UDim2.new(0.74, -95, 0, 18); levelLabel.Position = UDim2.new(0, 75, 0, 76)
	levelLabel.BackgroundTransparency = 1; levelLabel.Text = "Lv. 0 / "..cfg.maxLevel
	levelLabel.TextColor3 = T.accentGreen
	levelLabel.TextSize = 16; levelLabel.Font = Enum.Font.FredokaOne; levelLabel.TextXAlignment = Enum.TextXAlignment.Left

	local buyButton = Instance.new("TextButton", card)
	buyButton.Name = "PurchaseButton" -- ✨ ADDED NAME so particle script can find it
	buyButton.Size = UDim2.new(0.24, 0, 0, 46); buyButton.AnchorPoint = Vector2.new(1, 0.5)
	buyButton.Position = UDim2.new(1, -12, 0.5, 0)
	buyButton.BackgroundColor3 = isEpic and T.accentPurple or T.buttonGreen
	buyButton.BorderSizePixel = 0; buyButton.TextColor3 = T.bodyText
	buyButton.TextScaled = true; buyButton.Font = Enum.Font.FredokaOne
	Instance.new("UICorner", buyButton).CornerRadius = UDim.new(0, 8)

	cardRefsTable[upgradeId] = {
		frame = card, levelLabel = levelLabel, buyButton = buyButton, isEpic = isEpic, tab = cfg.category
	}

	local holdingBuy = false; local buyGeneration = 0

	-- ✨ THE MEMORY FIX: Checks if you have ever passed the tutorial
	local tutorialLockLifted = false
	local function IsTutorialFinished()
		if tutorialLockLifted then return true end -- If we already lifted it, keep it lifted forever!
		if liveGoldenAuras > 0 then tutorialLockLifted = true; return true end -- You prestiged!
		for _, state in pairs(epicUpgradeState) do
			if state.level > 0 then tutorialLockLifted = true; return true end -- You have epic upgrades!
		end
		local valState = upgradeState["blockValue"]
		if valState and valState.level > 0 then tutorialLockLifted = true; return true end -- You bought the tutorial upgrade!
		return false
	end

	local function TryBuy()
		if isEpic then
			local state = epicUpgradeState[upgradeId]
			if not state or state.maxed then return end 

			-- ✨ THE EPIC TUTORIAL LOCK (Uses Memory):
			if not IsTutorialFinished() then
				PlayErrorFeedback(buyButton) -- Buzz error
				return -- Cancel the purchase!
			end
			-- ✨ ==========================================

			if liveGoldenAuras < state.cost then PlayErrorFeedback(buyButton); return end

			local wasMaxedLocally = state.maxed; liveGoldenAuras -= state.cost; state.level += 1
			state.maxed = (state.level >= state.maxLevel)
			state.cost = state.maxed and 0 or EpicUpgradeConfig.CalculateCost(upgradeId, state.level)

			if state.maxed and not wasMaxedLocally then PlayFeedbackSound("MaxOut", 0.6); PlayUIBurst(buyButton, 20) else PlayPurchaseSound() end
			UpdateEpicCard(upgradeId); UpdateCurrencyDisplay(); PurchaseEpicUpgrade:FireServer(upgradeId)
		else
			local state = upgradeState[upgradeId]
			if not state or state.maxed then return end 

			-- ✨ THE REGULAR TUTORIAL LOCK (Uses Memory):
			if not IsTutorialFinished() and upgradeId ~= "blockValue" then
				PlayErrorFeedback(buyButton) -- Shake the wrong button and play error sound
				return -- Cancel the purchase entirely!
			end
			-- ✨ ==========================================

			if currentCurrency < state.cost then PlayErrorFeedback(buyButton); return end

			local wasMaxedLocally = state.maxed; currentCurrency -= state.cost; state.level += 1
			state.maxed = (state.level >= state.maxLevel)
			state.cost = state.maxed and 0 or UpgradeConfig.CalculateCost(upgradeId, state.level)

			if state.maxed and not wasMaxedLocally then PlayFeedbackSound("MaxOut", 0.6); PlayUIBurst(buyButton, 20) else PlayPurchaseSound() end
			UpdateRegularCard(upgradeId); UpdateCurrencyDisplay(); PurchaseUpgrade:FireServer(upgradeId)
		end
	end

	local pulseTween = nil

	buyButton.MouseButton1Down:Connect(function()
		buyGeneration += 1
		local myGen = buyGeneration
		holdingBuy = true

		local scale = buyButton:FindFirstChildOfClass("UIScale")
		if not scale then 
			scale = Instance.new("UIScale")
			scale.Parent = buyButton 
		end

		pulseTween = TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {Scale = 0.88})
		pulseTween:Play()

		TryBuy() 
		task.wait(0.3) 
		local holdStart = tick()

		local UserInputService = game:GetService("UserInputService")
		
		
		local epicHoldSpeedLevel = (epicUpgradeState["epicHoldSpeed"] and epicUpgradeState["epicHoldSpeed"].level) or 0
		local holdSpeedMultiplier = 1 + (epicHoldSpeedLevel * 0.3) -- +30% speed per level

		while holdingBuy and buyGeneration == myGen do
			if not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
				holdingBuy = false
				break
			end
			TryBuy()
			-- Base speed gets divided by your epic speed multiplier!
			task.wait(math.max(0.01, (0.15 - ((tick() - holdStart) * 0.05)) / holdSpeedMultiplier))
		end

		if pulseTween then pulseTween:Cancel() end
		if scale then TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), {Scale = 1}):Play() end
	end)

	buyButton.MouseButton1Up:Connect(function() 
		holdingBuy = false 
		if pulseTween then pulseTween:Cancel() end
		local scale = buyButton:FindFirstChildOfClass("UIScale")
		if scale then TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), {Scale = 1}):Play() end
	end)

	buyButton.MouseLeave:Connect(function() 
		holdingBuy = false 
		if pulseTween then pulseTween:Cancel() end
		local scale = buyButton:FindFirstChildOfClass("UIScale")
		if scale then TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), {Scale = 1}):Play() end
	end)
end

---------------------------------------------------------------
-- BUILD CARDS & DYNAMIC REBUILDER
---------------------------------------------------------------
local epicOrderIndex = 1
for _, tab in ipairs(EpicUpgradeConfig.Tabs) do
	for _, tierData in ipairs(EpicUpgradeConfig.Tiers) do
		for upgradeId, cfg in pairs(tierData.upgrades) do
			BuildCard(EpicScroll, upgradeId, cfg, true, epicCardRefs) 

			local ref = epicCardRefs[upgradeId]
			if ref and ref.frame then
				ref.baseOrder = epicOrderIndex
				ref.frame.LayoutOrder = epicOrderIndex
				epicOrderIndex += 1

				ref.frame.Visible = false 
				ref.frame.Parent = EpicScroll

				if UITheme and UITheme.Apply then UITheme.Apply(ref.frame, "ShopCard") end
			end
		end
	end
end

function UpdateRegularCard(upgradeId)
	local ref=regularCardRefs[upgradeId]; local state=upgradeState[upgradeId]
	if not ref or not state then return end

	if UITheme and UITheme.Apply then
		UITheme.Apply(ref.frame, "ShopCard")
	end

	ref.levelLabel.Text="Lv. "..state.level.." / "..state.maxLevel

	if state.level >= state.maxLevel then
		ref.frame.LayoutOrder = (ref.baseOrder or 0) + 100000 
		ref.levelLabel.TextColor3=Color3.fromRGB(255, 215, 0) 
		ref.buyButton.Text="MAX"
		ref.buyButton.TextColor3=Color3.fromRGB(255, 255, 255) 
		ref.buyButton.BackgroundColor3=Color3.fromRGB(100, 100, 100)
	else
		ref.frame.LayoutOrder = ref.baseOrder or 0 

		if currentCurrency<state.cost then
			ref.buyButton.Text="$"..FormatNumber(state.cost)
			ref.buyButton.TextColor3=Color3.fromRGB(255, 100, 100) 
			ref.buyButton.BackgroundColor3=Color3.fromRGB(60, 170, 80) 
		else
			ref.buyButton.Text="$"..FormatNumber(state.cost)
			ref.buyButton.TextColor3=Color3.fromRGB(255, 255, 255) 
			ref.buyButton.BackgroundColor3=Color3.fromRGB(60, 170, 80) 
		end
	end
end

function UpdateEpicCard(upgradeId)
	local ref=epicCardRefs[upgradeId]; local state=epicUpgradeState[upgradeId]
	if not ref or not state then return end

	if UITheme and UITheme.Apply then
		UITheme.Apply(ref.frame, "ShopCard")
	end

	ref.levelLabel.Text="Lv. "..state.level.." / "..state.maxLevel

	if state.level >= state.maxLevel then
		ref.frame.LayoutOrder = (ref.baseOrder or 0) + 100000 
		ref.levelLabel.TextColor3=Color3.fromRGB(255, 215, 0)
		ref.buyButton.Text="MAX"
		ref.buyButton.TextColor3=Color3.fromRGB(255, 255, 255)
		ref.buyButton.BackgroundColor3=Color3.fromRGB(100, 100, 100)
	else
		ref.frame.LayoutOrder = ref.baseOrder or 0 

		if liveGoldenAuras<state.cost then
			ref.buyButton.Text="✦ "..FormatNumber(state.cost)
			ref.buyButton.TextColor3=Color3.fromRGB(255, 100, 100) 
			ref.buyButton.BackgroundColor3=Color3.fromRGB(150, 80, 255) 
		else
			ref.buyButton.Text="✦ "..FormatNumber(state.cost)
			ref.buyButton.TextColor3=Color3.fromRGB(255, 255, 255) 
			ref.buyButton.BackgroundColor3=Color3.fromRGB(150, 80, 255) 
		end
	end
end
local function UpdateAllRegularCards() for id in pairs(regularCardRefs) do UpdateRegularCard(id) end end
local function UpdateAllEpicCards() for id in pairs(epicCardRefs) do UpdateEpicCard(id) end end

local function CreateTierHeader(tierName)
	local header = Instance.new("Frame")
	header.Name = "TierHeader"; header.Size = UDim2.new(1, 0, 0, 30); header.BackgroundTransparency = 1

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, -5); label.Position = UDim2.new(0, 0, 0, 0); label.BackgroundTransparency = 1
	label.Text = string.upper(tierName); label.TextColor3 = Color3.fromRGB(220, 220, 220)
	label.TextSize = 16; label.Font = Enum.Font.GothamBlack; 
	label.TextXAlignment = Enum.TextXAlignment.Left 
	label.Parent = header

	local line = Instance.new("Frame")
	line.Size = UDim2.new(1, 0, 0, 2); line.Position = UDim2.new(0, 0, 1, -2) 
	line.BackgroundColor3 = Color3.fromRGB(100, 100, 100); line.BorderSizePixel = 0; line.Parent = header
	return header
end

local function CreateLockedTierHeader(tierName, current, required)
	local header = Instance.new("Frame")
	header.Name = "TierHeader_Locked"; header.Size = UDim2.new(1, 0, 0, 45); header.BackgroundTransparency = 1
	header:SetAttribute("Required", required) 

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0.5, 0); label.Position = UDim2.new(0, 0, 0, 0); label.BackgroundTransparency = 1
	label.Text = string.upper(tierName) .. " (LOCKED)"; label.TextColor3 = Color3.fromRGB(150, 150, 150)
	label.TextSize = 16; label.Font = Enum.Font.GothamBlack; 
	label.TextXAlignment = Enum.TextXAlignment.Left; label.Parent = header

	local progress = Instance.new("TextLabel")
	progress.Name = "ProgressLabel" 
	progress.Size = UDim2.new(1, 0, 0.4, 0); progress.Position = UDim2.new(0, 0, 0.6, 0); progress.BackgroundTransparency = 1
	progress.Text = current .. " / " .. required .. " Upgrades Needed"
	progress.TextColor3 = Color3.fromRGB(255, 100, 100) 
	progress.TextSize = 12; progress.Font = Enum.Font.GothamBold; 
	progress.TextXAlignment = Enum.TextXAlignment.Left; progress.Parent = header

	local line = Instance.new("Frame")
	line.Size = UDim2.new(1, 0, 0, 2); line.Position = UDim2.new(0, 0, 1, -2)
	line.BackgroundColor3 = Color3.fromRGB(80, 80, 80); line.BorderSizePixel = 0; line.Parent = header
	return header
end

local function RebuildRegularShop()
	for _, child in ipairs(RegularScroll:GetChildren()) do
		if child:IsA("Frame") and child.Name ~= "CardTemplate" then
			if not string.find(child.Name, "TierHeader") then UITheme.Apply(child, "ShopCard") end
			child:Destroy() 
		end
	end
	regularCardRefs = {}

	local totalUpgradesBought = 0
	for _, state in pairs(upgradeState) do totalUpgradesBought = totalUpgradesBought + (state.level or 0) end

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
					-- ✨ THE FIX: Just these 3 lines! (Deleted the old local buyBtn line)
					if ref.buyButton then
						ref.buyButton.Name = "Buy_" .. upgradeId
					end
					-- ✨ ==========================================

					ref.baseOrder = listOrder
					ref.frame.LayoutOrder = listOrder
					listOrder += 1

					ref.frame.Visible = true
					ref.frame.Parent = RegularScroll

					if UITheme and UITheme.Apply then UITheme.Apply(ref.frame, "ShopCard") end
					local myColor = Color3.fromRGB(45, 30, 55)
					ref.frame:SetAttribute("TierColor", myColor)
					ref.frame.BackgroundColor3 = myColor
				end
			end
		else
			local lockedHeader = CreateLockedTierHeader(tierData.tierName or "Tier " .. tierNum, totalUpgradesBought, tierData.unlockRequirement)
			lockedHeader.LayoutOrder = listOrder
			lockedHeader.Parent = RegularScroll
			break 
		end
	end
	UpdateAllRegularCards()
end 
RebuildRegularShop() 

task.delay(1, function()
	isLoadingData = false
end)

function UpdateCurrencyDisplay()
	if activeMainTab=="Upgrades" then
		CurrencyLabel.Text="$"..FormatNumber(currentCurrency); CurrencyLabel.TextColor3=T.currencyColor
		CurrencyLabel.Position=UDim2.new(0,12,0,HEADER_H+MAINTAB_H+8)
	end
end

---------------------------------------------------------------
-- TAB SWITCHING
---------------------------------------------------------------
local function HighlightMainTab(tabName)
	for name,btn in pairs(mainTabButtons) do btn.BackgroundColor3=(name==tabName) and T.panelStroke or T.buttonSecondary end
end
local function SwitchToMainTab(tabName)
	if shared.PlayUISound then shared.PlayUISound(SoundConfig.UIClick or "") end
	activeMainTab = tabName
	
	activeShopTabText = (tabName == "Epic") and "Epic Research" or "Regular Upgrades"
	ShopHoverLabel.Text = activeShopTabText

	for name, data in pairs(mainTabButtons) do
		data.btn.BackgroundColor3 = (name == tabName) and TAB_COLOR_ACTIVE or TAB_COLOR_BASE
		data.stroke.Color = (name == tabName) and T.bodyText or T.panelStroke
	end

	RegularScroll.Visible = (tabName == "Upgrades")
	EpicScroll.Visible    = (tabName == "Epic")

	-- ✨ Instantly show ALL epic cards when switching to the Epic tab
	if tabName == "Epic" then
		for id, ref in pairs(epicCardRefs) do
			if ref and ref.frame then
				ref.frame.Visible = true 
			end
		end
		if EpicScroll then EpicScroll.CanvasPosition = Vector2.new(0,0) end
	end
end

tabUpgrades.MouseButton1Down:Connect(function() PlayUI(SoundConfig.UIClick); SwitchToMainTab("Upgrades") end)
tabEpic.MouseButton1Down:Connect(function() PlayUI(SoundConfig.UIClick); SwitchToMainTab("Epic") end)

---------------------------------------------------------------
-- OPEN / CLOSE
---------------------------------------------------------------
local function OpenShop()
	shopOpen=true; ShopPanel.Visible=true; ShopPanel.Size=UDim2.new(0.88, 0, 0, 0)
	SwitchToMainTab(activeMainTab)
	TweenService:Create(ShopPanel,TweenInfo.new(0.3,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
		{Size=UDim2.new(0.88, 0, 0.82, 0)}):Play()
	UITheme.SetMenuVisible(true)
	ShopButton.BackgroundColor3=T.panelStroke
end
local function CloseShop()
	shopOpen=false; PlayUI(SoundConfig.UIClose)
	TweenService:Create(ShopPanel,TweenInfo.new(0.22,Enum.EasingStyle.Quad,Enum.EasingDirection.In),
		{Size=UDim2.new(0.88, 0, 0, 0)}):Play()
	UITheme.SetMenuVisible(false)
	task.delay(0.25, function() ShopPanel.Visible=false end)
	ShopButton.BackgroundColor3=T.buttonSecondary
end
ShopButton.MouseButton1Down:Connect(function() if shopOpen then CloseShop() else OpenShop() end end)
CloseButton.MouseButton1Down:Connect(CloseShop)

---------------------------------------------------------------
-- CURRENCY SYNC
---------------------------------------------------------------
local ratePerSecond=0
local UpdateHUD=ReplicatedStorage.RemoteEvents:WaitForChild("UpdateHUD")
UpdateHUD.OnClientEvent:Connect(function(stats)
	if stats.currency~=nil then
		if stats.currency>currentCurrency then currentCurrency=stats.currency end
	end
	if stats.goldenAuras~=nil then liveGoldenAuras=stats.goldenAuras end
	if stats.rate and stats.passiveInterval then
		local interval=stats.passiveInterval
		ratePerSecond=(interval>0 and stats.rate>0) and (stats.rate/interval) or 0
	end
end)

---------------------------------------------------------------
-- LIVE UPDATE LOOP
---------------------------------------------------------------
local lastCardUpdate=0
RunService.Heartbeat:Connect(function(dt)
	if not shopOpen then return end
	if ratePerSecond>0 then currentCurrency+=ratePerSecond*dt end
	local now=tick()
	if now-lastCardUpdate>0.3 then
		lastCardUpdate=now
		if activeMainTab=="Upgrades" then UpdateAllRegularCards() else UpdateAllEpicCards() end
		UpdateCurrencyDisplay()
	end
end)

---------------------------------------------------------------
-- SERVER EVENTS (Cleaned of Sound/UI logic)
---------------------------------------------------------------
if UpgradeUpdated then
	UpgradeUpdated.OnClientEvent:Connect(function(info)
		if info.type=="fullState" then
			upgradeState=info.upgrades; currentCurrency=info.currency; 
			RebuildRegularShop()
			UpdateCurrencyDisplay()

		elseif info.type=="purchased" then
			local current = upgradeState[info.upgradeId]

			if not current or info.level >= current.level then
				upgradeState[info.upgradeId]={level=info.level,maxLevel=info.maxLevel,cost=info.cost,maxed=info.maxed}
			end
			currentCurrency = info.currency

			local scroll = ShopPanel:FindFirstChild("RegularScroll")
			local savedScroll = scroll and scroll.CanvasPosition or Vector2.new(0, 0)

			-- ✨ Safely updates the shop tiers WITHOUT triggering ghost sounds!
			RebuildRegularShop()
			UpdateCurrencyDisplay()

			if scroll then
				scroll.CanvasPosition = savedScroll
			end
		end
	end)
end

if EpicUpgradeUpdated then
	EpicUpgradeUpdated.OnClientEvent:Connect(function(info)
		if info.type=="fullState" then
			epicUpgradeState=info.upgrades; liveGoldenAuras=info.goldenAuras or liveGoldenAuras
			UpdateAllEpicCards(); UpdateCurrencyDisplay()

		elseif info.type=="purchased" then
			local current = epicUpgradeState[info.upgradeId]

			if not current or info.level >= current.level then
				epicUpgradeState[info.upgradeId]={level=info.level,maxLevel=info.maxLevel,cost=info.cost,maxed=info.maxed}
			end
			UpdateEpicCard(info.upgradeId); UpdateCurrencyDisplay()
		end
	end)
end

---------------------------------------------------------------
-- UI JUICE: Button Hover & Click Animations
---------------------------------------------------------------
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

AddButtonJuice(ShopButton)
AddButtonJuice(CloseButton)
AddButtonJuice(ShopButton)
AddButtonJuice(tabUpgrades)
AddButtonJuice(tabEpic)
AddButtonJuice(CloseButton)
---------------------------------------------------------------
-- REFRESH LOOK + APPLY SHINE TO TITLE BAR
---------------------------------------------------------------
local shopShine = nil
local titleFlair = nil
local TitleShine = nil
local flairedExtraUI = false

local function RefreshLook()
	UITheme.Apply(ShopPanel, "Panel")
	UITheme.Apply(ShopPanel, "TitleBar")

	if not shopShine then
		shopShine = UITheme.ApplyShine(ShopPanel)
		TitleShine = UITheme.ApplyShine(TitleBar)
	end

	if not titleFlair then
		titleFlair = UITheme.ApplyFlair(TitleLabel, "Ghost")
	end

	-- ✨ THE FLAIR INJECTOR FOR ALL CIRCLES AND LINES
	if not flairedExtraUI then
		flairedExtraUI = true
		-- Flair all the new circular tabs!
	end

	for _, scrollName in ipairs({"RegularScroll", "EpicScroll"}) do
		local scroll = ShopPanel:FindFirstChild(scrollName) 
		if scroll then
			local layout = scroll:FindFirstChildOfClass("UIListLayout")
			if layout then layout.SortOrder = Enum.SortOrder.LayoutOrder end
		end
	end

	local outerStroke = ShopPanel:FindFirstChildWhichIsA("UIStroke")
	if outerStroke then
		outerStroke.Color = Color3.fromRGB(255, 255, 255) 
	end
end

task.wait(2)
RefreshLook()

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

	-- ✨ THE FONT FIX: Switched to FredokaOne
	pop.Font = Enum.Font.FredokaOne 

	pop.TextScaled = true
	pop.TextColor3 = data.color
	pop.BackgroundTransparency = 1
	pop.Size = UDim2.new(0, 200, 0, 40)

	pop.AnchorPoint = Vector2.new(0.5, 0.5)

	-- ✨ THE HEIGHT FIX: Changed starting offset from -60 to -120 to sit higher
	pop.Position = UDim2.new(ClickButton.Position.X.Scale, ClickButton.Position.X.Offset, ClickButton.Position.Y.Scale, ClickButton.Position.Y.Offset - 120)
	pop.Parent = ClickButton.Parent

	local stroke = Instance.new("UIStroke", pop)
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(0, 0, 0)

	pop.Size = UDim2.new(0, 50, 0, 10) 

	-- ✨ THE ANIMATION FIX: Increased the upward float distance (-80 higher than start)
	TweenService:Create(pop, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 250, 0, 50),
		Position = UDim2.new(pop.Position.X.Scale, pop.Position.X.Offset, pop.Position.Y.Scale, pop.Position.Y.Offset - 80)
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
	UpdateHatcheryBar(info.current, info.max)
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
