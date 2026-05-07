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

-- TutorialConfig
-- Location: ReplicatedStorage > Modules > TutorialConfig

local TutorialConfig = {}

TutorialConfig.TutorialEndArea = 5

TutorialConfig.DefaultDuration = 4
TutorialConfig.DefaultDelay    = 0
TutorialConfig.DefaultColor    = Color3.fromRGB(255, 255, 255)
TutorialConfig.DefaultIcon     = "rbxassetid://14914018910"

TutorialConfig.Steps = {

	-- ══════════ AREA 1: COMMON ══════════
	---- CHAIN 1: The Spawning Loop
	--{
	--	id           = "a1_hello",
	--	area         = 1,
	--	trigger      = "areaEnter",
	--	title        = "Welcome to Aura Inc!",
	--	body         = "Spam Click the Red Button to Produce Auras!",
	--	target       = "ClickButton", 
	--	isMandatory  = true, 
	--	bannerPos    = "Center",
	--	unlockUI     = {"ClickButton", "HatcheryBar", "CurrencyLabel", "RateLabel"},
	--	nextStep     = "a1_hold", -- 💥 CHANGED: Skipped the cube hint. Straight to action.
	--	icon         = "rbxassetid://14922082255",
	--},
	--{
	--	id           = "a1_hold",
	--	area         = 1,
	--	trigger      = "chain",
	--	title        = "Hold For Multipliers",
	--	body         = "Hold the Red Button! Higher multipliers = More Cash!",
	--	target       = "ClickButton", 
	--	isMandatory  = true, 
	--	holdDuration = 1.5, 
	--	bannerPos    = "Center",
	--	nextStep     = "a1_mailbox", -- 💥 CHANGED: Skipped the 10-second wait hint.
	--	icon         = "rbxassetid://14924185885",
	--},
	--{
	--	id           = "a1_mailbox",
	--	area         = 1,
	--	trigger      = "chain",
	--	title        = "Check The Mail!",
	--	body         = "Click the MailBox to claim FREE Rewards!",
	--	unlockUI     = "Mailbox",
	--	isMandatory  = true, 
	--	bannerPos    = "Center",
	--	icon         = "rbxassetid://14921813212",
	--	duration = 10
	--},

	---- CHAIN 2: The Economy Loop
	--{
	--	id           = "a1_habitat_full",
	--	area         = 1,
	--	trigger      = "habitatFull",
	--	title        = "Your Habitat is Full!",
	--	body         = "Your storage is full! Click the Blue Button to send a ship and FREE up SPACE!",
	--	target       = "SendShipBtn", 
	--	isMandatory  = true, 
	--	bannerPos    = "Center",
	--	unlockUI     = "SendShipBtn",  
	--	nextStep     = "a1_ship_toggle", 
	--	icon         = "rbxassetid://14914018910",
	--},
	--{
	--	id           = "a1_ship_toggle",
	--	area         = 1,
	--	trigger      = "chain",
	--	title        = "Automation",
	--	body         = "Click here to toggle Auto-Shipping so you don't have to do it manually!",
	--	target       = "ToggleShipBtn",
	--	isMandatory  = true,
	--	bannerPos    = "Center",
	--	unlockUI     = "ModeToggle", 
	--	nextStep     = "a1_buy_upgrade", 
	--	icon         = "rbxassetid://14914018910",
	--},
	--{
	--	id           = "a1_buy_upgrade",
	--	area         = 1,
	--	trigger      = "chain",
	--	title        = "Research Shop",
	--	body         = "Time to upgrade! Click the Shop Button.",
	--	target       = "ShopButton",
	--	unlockUI     = "ShopButton",
	--	isMandatory  = true,
	--	bannerPos    = "Center",
	--	nextStep     = "a1_buy_first_upgrade", 
	--	icon         = "rbxassetid://14917128076",
	--},
	--{
	--	id           = "a1_buy_first_upgrade",
	--	area         = 1,
	--	trigger      = "chain",
	--	title        = "Buy Your First Upgrade",
	--	body         = "Click the green $50 button to increase your Aura Value!",
	--	target       = "Buy_blockValue", 
	--	bannerPos    = "Top",
	--	isMandatory  = true, 
	--	nextStep     = "a1_close_shop",
	--	icon         = "rbxassetid://14914018910",
	--},
	--{
	--	id           = "a1_close_shop",
	--	area         = 1,
	--	trigger      = "chain",
	--	title        = "Close The Shop",
	--	body         = "Click the Red X to close the shop.",
	--	unlockUI     = "ShopCloseBtn",
	--	isMandatory  = true, 
	--	target       = "ShopCloseBtn", 
	--	bannerPos    = "Top",
	--	icon         = "rbxassetid://14915225073",
	--	-- Stops here and waits for them to hit 20,000 Eval
	--},
	
	

	---- CHAIN 3: Prestige and Progress
	--{
	--	id           = "a1_try_prestige",
	--	area         = 1,
	--	trigger      = "farmEvalReached",
	--	triggerValue = 200000,
	--	title        = "Try Prestiging!",
	--	body         = "Click the Prestige button to permanently multiply your earnings!",
	--	target       = "PrestigeButton", 
	--	isMandatory  = true, 
	--	bannerPos    = "Center",
	--	unlockUI     = {"MainPrestigeBtn", "SoulAuraDisplay"},
	--	nextStep     = "a1_prestige_button",
	--	icon         = "rbxassetid://14916846070",
	--},
	--{
	--	id           = "a1_prestige_button",
	--	area         = 1,
	--	trigger      = "chain",
	--	title        = "Prestige Now",
	--	body         = "Prestige now to get your first permanent earnings increase!",
	--	unlockUI     = {"PrestigeBtns", "PrestigeCloseBtn"},
	--	isMandatory  = true, 
	--	target       = "PrestigeBtns", 
	--	bannerPos    = "Top",
	--	icon         = "rbxassetid://14923411730",
	--	nextStep     = "a1_close_prestige",
	--},
	--{
	--	id           = "a1_progress",
	--	area         = 1,
	--	trigger      = "farmEvalReached",        
	--	triggerValue = 500000,                    
	--	title        = "Next Area Unlocked",
	--	body         = "Click the Travel button to move to the next area!",
	--	unlockUI     = {"AreaTravelButton", "PortalCloseBtn"},
	--	target       = "AreaTravelButton", 
	--	isMandatory  = true, 
	--	requirePrestige = true,                  
	--	requireStep  = "a1_prestige_button",    
	--	bannerPos    = "Center",
	--	nextStep     = "a1_arrow_button",        
	--	icon         = "rbxassetid://14914000799",
	--},
	--{
	--	id           = "a1_arrow_button",
	--	area         = 1,
	--	trigger      = "chain",
	--	title        = "Select The Area",
	--	body         = "Click the arrow to view the Uncommon Area!",
	--	target       = "ArrowBtn",
	--	isMandatory  = true, 
	--	bannerPos    = "Top",
	--	unlockUI     = "ArrowBtn",
	--	nextStep     = "a1_next_area",
	--	icon         = "rbxassetid://14914018910",
	--},
	--{
	--	id           = "a1_next_area",
	--	area         = 1,
	--	trigger      = "chain",
	--	title        = "Uncommon Area",
	--	body         = "Click Travel to progress to the Uncommon Area!",
	--	target       = "TravelBtn",
	--	unlockUI     = {"TravelBtn", "PortalCloseBtn"},
	--	isMandatory  = true, 
	--	icon         = "rbxassetid://14914018910",
	--},
	--{
	--	id           = "a1_stuck_prestige",
	--	area         = 1,
	--	trigger      = "timerElapsed",
	--	triggerValue = 600,
	--	title        = "Keep Going!",
	--	body         = "If you feel stuck make sure to prestige and Upgrade more. Also Use Boosts To Help escpecially the Value Booster!",
	--},
	


	---- ══════════ AREA 2: UNCOMMON ══════════
	--{
	--	id           = "a2_welcome",
	--	area         = 2,
	--	trigger      = "areaEnter",
	--	title        = "How To Boost",
	--	body         = "Click On The Boost Button",
	--	target       = "BoostsButton", 
	--	isMandatory  = true, 
	--	bannerPos    = "Center",
	--	unlockUI = 		"BoostsButton",
	--	nextStep     = "a2_click_boost",
	--	icon = "rbxassetid://14914018910",
	--},

	--{
	--	id           = "a2_click_boost",
	--	area         = 2,
	--	trigger      = "chain",
	--	delay        = 10,
	--	title        = "Buy A Spawn Speed Boost",
	--	body         = "Use your GOLDEN AURAS to BUY this BOOST",
	--	isMandatory  = true, 
	--	target       = "BoostsButton", 
	--	unlockUI = 		"BoostsButton",
	--	icon = "rbxassetid://14914018910",

	--},


	-- ══════════ AREA 3: RARE ══════════
	-- CHAIN 4: Golden Bank 
	--{
	--	id           = "a3_golden_auras",
	--	area         = 3,
	--	trigger      = "areaEnter",
	--	title        = "Placeholder Title 21",
	--	body         = "Placeholder text for step 21.",
	--	nextStep     = "a3_golden_aura_bank",
	--},
	--{
	--	id           = "a3_golden_aura_bank",
	--	area         = 3,
	--	trigger      = "chain",
	--	title        = "Placeholder Title 22",
	--	body         = "Placeholder text for step 22.",
	--	cameraTarget = "GoldenBankModel", -- Replace with actual model name
	--	nextStep     = "a3_golden_aura_break",
	--},
	--{
	--	id           = "a3_golden_aura_break",
	--	area         = 3,
	--	trigger      = "chain",
	--	title        = "Placeholder Title 23",
	--	body         = "Placeholder text for step 23.",
	--	cameraTarget = "GoldenBankModel",
	--	nextStep     = "a3_epic_research",
	--},


	-- ══════════ AREA 4: EPIC ══════════
	-- AREA 4 EVENTS EPIC RESEARCH HERE
	--{
	--	id           = "a4_welcome",
	--	area         = 4,
	--	trigger      = "areaEnter",
	--	title        = "Placeholder Title 25",
	--	body         = "Placeholder text for step 25.",
	--},
	--{
	--	id           = "a4_boost_hint",
	--	area         = 4,
	--	trigger      = "currencyReached",
	--	triggerValue = 5000,
	--	title        = "Placeholder Title 26",
	--	body         = "Placeholder text for step 26.",
	--},
	--{
	--	id           = "a4_combo_boost",
	--	area         = 4,
	--	trigger      = "boostActivated",
	--	title        = "Placeholder Title 27",
	--	body         = "Placeholder text for step 27.",
	--},


	-- ══════════ AREA 5: LEGENDARY ══════════
--	-- AREA 5 EVENTS
--	{
--		id           = "a5_welcome",
--		area         = 5,
--		trigger      = "areaEnter",
--		title        = "Placeholder Title 28",
--		body         = "Placeholder text for step 28.",
--	},
--	{
--		id           = "a5_graduation",
--		area         = 5,
--		trigger      = "portalReady",
--		title        = "Placeholder Title 29",
--		body         = "Placeholder text for step 29.",
--	},
}

---------------------------------------------------------------
-- HELPERS
---------------------------------------------------------------
function TutorialConfig.GetStepsForArea(area)
	local result = {}
	for _, step in ipairs(TutorialConfig.Steps) do
		if step.area == area then table.insert(result, step) end
	end
	return result
end

function TutorialConfig.GetStep(id)
	for _, step in ipairs(TutorialConfig.Steps) do
		if step.id == id then return step end
	end
	return nil
end

return TutorialConfig

