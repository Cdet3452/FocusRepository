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

-- ShopController
-- Location: StarterPlayer > StarterPlayerScripts > ShopController

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")

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
local globalHoldActive  = false  -- Global flag to prevent multiple simultaneous holds
local globalHoldGeneration = 0    -- Global generation counter

-- ✨ FORWARD DECLARATIONS (functions defined later but needed earlier)
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
	warn("⚠️ UI Sound Missing: '" .. tostring(soundName) .. "' not found in ReplicatedStorage.SFX")
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

-- ─────────────────────────────────────────────────────────────────────────────
-- MISC HELPERS
-- ─────────────────────────────────────────────────────────────────────────────
local function FormatNumber(n) return Formatter.Format(n) end
local function PlayUI(id) if shared.PlayUISound then shared.PlayUISound(id) end end

-- ─────────────────────────────────────────────────────────────────────────────
-- SHOP BUTTON
-- ─────────────────────────────────────────────────────────────────────────────
local ShopButton = Instance.new("ImageButton")
ShopButton.Name              = "ShopButton"
ShopButton.Size              = UDim2.new(0, 60, 0, 60)
ShopButton.AnchorPoint       = Vector2.new(1, 1)
ShopButton.Position          = UDim2.new(0.98, 0, 0.95, 0)
ShopButton.BackgroundColor3  = T.buttonSecondary
ShopButton.BorderSizePixel   = 0
ShopButton.AutoButtonColor   = false
ShopButton.ZIndex            = 5
ShopButton.Parent            = mainHUD
ShopButton:SetAttribute("TutorialTarget", "ShopButton")
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
-- SHOP PANEL
-- ─────────────────────────────────────────────────────────────────────────────
local PANEL_MAX_W = 420; local PANEL_MAX_H = 510; local HEADER_H = 42

local ShopPanel = Instance.new("Frame")
ShopPanel.Name              = "ShopPanel"
ShopPanel.Size              = UDim2.new(0.88, 0, 0.82, 0)
ShopPanel.AnchorPoint       = Vector2.new(0.5, 0.5)
ShopPanel.Position          = UDim2.new(0.5, 0, 0.5, 0)
ShopPanel.BackgroundColor3  = T.panelBG
ShopPanel.BorderSizePixel   = 0
ShopPanel.Visible           = false
ShopPanel.ZIndex            = 10
ShopPanel.ClipsDescendants  = true
ShopPanel.Parent            = mainHUD
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
CloseButton:SetAttribute("TutorialTarget", "ShopCloseBtn")
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
	TweenService:Create(InfoScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1
	}):Play()
end

InfoClose.MouseButton1Down:Connect(function()
	if shared.PlayUISound then shared.PlayUISound(SoundConfig.UIClick or "") end
	local tween = TweenService:Create(InfoScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
		Scale = 0.5
	})
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

	local tutorialLockLifted = false
	-- ✨ FIX: Check for the permanent persistent attribute to bypass the lock
	local function IsTutorialFinished()
		if tutorialLockLifted then return true end
		if player:GetAttribute("TutorialCompleted") then tutorialLockLifted = true; return true end
		if liveGoldenAuras > 0 then tutorialLockLifted = true; return true end
		for _, state in pairs(epicUpgradeState) do
			if state.level > 0 then tutorialLockLifted = true; return true end
		end
		local valState = upgradeState["blockValue"]
		if valState and valState.level > 0 then tutorialLockLifted = true; return true end
		return false
	end

	-- ✨ FIX: Stop any other card's hold when this one starts
	local function StopAllOtherHolds(myGen)
		if globalHoldGeneration ~= myGen then
			globalHoldGeneration = myGen
		end
	end

	local function TryBuy()
		if isLoadingData then return false end

		if isEpic then
			local state = epicUpgradeState[upgradeId]
			if not state or state.maxed then return false end
			if not IsTutorialFinished() then PlayErrorFeedback(buyButton); return false end

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
			return true
		else
			local state = upgradeState[upgradeId]
			if not state or state.maxed then return false end
			if not IsTutorialFinished() and upgradeId ~= "blockValue" then
				PlayErrorFeedback(buyButton); return false
			end

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
			UpdateLockedTierProgress() -- ✨ FIX: Update progress text immediately
			PurchaseUpgrade:FireServer(upgradeId)
			return true
		end
	end

	local pulseTween = nil

	buyButton.MouseButton1Down:Connect(function()
		-- ✨ FIX: Increment global generation to stop any other ongoing holds
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

		-- ✨ FIX: Check both local and global generation/flags
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

-- ✨ FIX: Update locked tier header progress without rebuilding the whole shop
UpdateLockedTierProgress = function()
	local totalUpgradesBought = 0
	for _, state in pairs(upgradeState) do
		totalUpgradesBought = totalUpgradesBought + (state.level or 0)
	end

	-- Find the locked tier header and update its progress text
	local lockedHeader = nil
	local required = 0
	
	for _, child in ipairs(RegularScroll:GetChildren()) do
		if child.Name == "TierHeader_Locked" then
			lockedHeader = child
			required = child:GetAttribute("Required") or 0
			local progressLabel = child:FindFirstChild("ProgressLabel")
			if progressLabel then
				progressLabel.Text = totalUpgradesBought .. " / " .. required .. " Upgrades Needed"
				
				-- Change color based on progress
				local progress = totalUpgradesBought / required
				if progress >= 1 then
					progressLabel.TextColor3 = Color3.fromRGB(100, 255, 100) -- Green when ready
				elseif progress >= 0.75 then
					progressLabel.TextColor3 = Color3.fromRGB(255, 200, 100) -- Orange when close
				else
					progressLabel.TextColor3 = Color3.fromRGB(255, 100, 100) -- Red when far
				end
			end
			break -- Only one locked header should exist
		end
	end
	
	-- ✨ FIX: If requirement met, rebuild the shop to unlock the tier!
	if lockedHeader and totalUpgradesBought >= required then
		-- ✨ Play tier unlock sound and VFX!
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

-- 5 second fail-safe in case server takes extremely long to send fullState
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
-- OPEN / CLOSE
-- ─────────────────────────────────────────────────────────────────────────────
local function OpenShop()
	shopOpen = true
	ShopPanel.Visible = true
	ShopPanel.Size    = UDim2.new(0.88, 0, 0, 0)
	SwitchToMainTab(activeMainTab)
	TweenService:Create(ShopPanel,
		TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = UDim2.new(0.88, 0, 0.82, 0) }
	):Play()
	UITheme.SetMenuVisible(true)
	ShopButton.BackgroundColor3 = T.panelStroke
end

local function CloseShop()
	shopOpen = false
	PlayUI(SoundConfig.UIClose)
	TweenService:Create(ShopPanel,
		TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Size = UDim2.new(0.88, 0, 0, 0) }
	):Play()
	UITheme.SetMenuVisible(false)
	task.delay(0.25, function() ShopPanel.Visible = false end)
	ShopButton.BackgroundColor3 = T.buttonSecondary
end

ShopButton.MouseButton1Down:Connect(function() if shopOpen then CloseShop() else OpenShop() end end)
CloseButton.MouseButton1Down:Connect(CloseShop)

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
			-- ✨ FIX: Force sync currency to server value immediately
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

			local scroll      = ShopPanel:FindFirstChild("RegularScroll")
			local savedScroll = scroll and scroll.CanvasPosition or Vector2.new(0, 0)

			RebuildRegularShop()
			UpdateCurrencyDisplay()

			if scroll then scroll.CanvasPosition = savedScroll end
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

	btn.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Sine), { Scale = 1.08 }):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Sine), { Scale = 1 }):Play()
	end)
	btn.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1, Enum.EasingStyle.Sine), { Scale = 0.9 }):Play()
	end)
	btn.MouseButton1Up:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), { Scale = 1.08 }):Play()
	end)
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

-- PrestigeController
-- Location: StarterPlayer > StarterPlayerScripts > PrestigeController
--
-- FIXES:
--   Bigger Soul Aura display text (was 22/14/14, now 28/18/18)
--   Wider display frame (200px instead of UIConfig 160px)
--   "Used" properly resets from UpdateHUD on join when wipe flags are on
--   AreaChanged always resets prestige state

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local AdminConfig       = require(ReplicatedStorage.Modules.AdminConfig)
local PrestigeModule    = require(ReplicatedStorage.Modules.PrestigeModule)
local T                 = require(ReplicatedStorage.Modules.UITheme).Get()
local C                 = require(ReplicatedStorage.Modules.UIConfig)
local Formatter         = require(ReplicatedStorage.Modules.NumberFormatter)
local UITheme = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UITheme"))
local T = UITheme.Get("Custom")
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
-- Soul Aura display � FIX: BIGGER TEXT
---------------------------------------------------------------
local SA_DISPLAY_W = 220   -- was 160
local SA_DISPLAY_H = 90    -- was 70

local SADisplay = Instance.new("Frame")
SADisplay.Name = "SoulAuraDisplay"
SADisplay.Size = UDim2.new(0, SA_DISPLAY_W, 0, SA_DISPLAY_H)
SADisplay.Position = UDim2.new(0, 10, 1, -155)
SADisplay.BackgroundTransparency = 1; SADisplay.ZIndex = 5; SADisplay.Parent = mainHUD

local SACountLabel = Instance.new("TextLabel")
SACountLabel.Size = UDim2.new(1,0,0,28)       -- FIX: was 22
SACountLabel.Position = UDim2.new(0,0,0,0)
SACountLabel.BackgroundTransparency = 1; SACountLabel.Text = "0 Soul Auras"
SACountLabel.TextColor3 = Color3.fromRGB(200,160,255); SACountLabel.TextScaled = true
SACountLabel.Font = T.font; SACountLabel.TextXAlignment = Enum.TextXAlignment.Center
SACountLabel.ZIndex = 6; SACountLabel.Parent = SADisplay

local BarBG = Instance.new("Frame")
BarBG.Size = UDim2.new(1,0,0,12)              -- FIX: was 10
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
RunSALabel.Size = UDim2.new(1,0,0,18)         -- FIX: was 14
RunSALabel.Position = UDim2.new(0,0,0,48)
RunSALabel.BackgroundTransparency = 1; RunSALabel.Text = "earning..."
RunSALabel.TextColor3 = Color3.fromRGB(160,140,180); RunSALabel.TextScaled = true
RunSALabel.Font = T.fontBody; RunSALabel.TextXAlignment = Enum.TextXAlignment.Left
RunSALabel.ZIndex = 6; RunSALabel.Parent = SADisplay

local MultDisplayLabel = Instance.new("TextLabel")
MultDisplayLabel.Size = UDim2.new(1,0,0,18)    -- FIX: was 14
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
PrestigeButton.Text = "Prestige"; PrestigeButton.TextColor3 = Color3.fromRGB(255,255,255)
PrestigeButton.TextScaled = true; PrestigeButton.Font = T.font
PrestigeButton.ZIndex = 5; PrestigeButton.Parent = mainHUD
PrestigeButton:SetAttribute("TutorialTarget", "MainPrestigeBtn")
Instance.new("UICorner", PrestigeButton).CornerRadius = UDim.new(0,6)

---------------------------------------------------------------
-- Prestige dialog (MOBILE SCROLL FIX)
---------------------------------------------------------------
local D=C.Dialog; local DW=D.W; local DH=D.H; local DHH=D.HeaderH; local GAP=D.LabelGap

local Dialog = Instance.new("Frame")
Dialog.Name="PrestigeDialog"
Dialog.Size=UDim2.new(0.88, 0, 0.72, 0)
Dialog.AnchorPoint=Vector2.new(0.5, 0.5)
Dialog.Position=UDim2.new(0.5, 0, 0.5, 0)
Dialog.BackgroundColor3=Color3.fromRGB(25,20,35); Dialog.BorderSizePixel=0
Dialog.Visible=false; Dialog.ZIndex=20; Dialog.Parent=mainHUD
Instance.new("UICorner",Dialog).CornerRadius=UDim.new(0,D.CornerRadius)
local dialogConstraint=Instance.new("UISizeConstraint"); dialogConstraint.MaxSize=Vector2.new(DW,DH); dialogConstraint.Parent=Dialog
local dialogStroke=Instance.new("UIStroke"); dialogStroke.Color=Color3.fromRGB(140,70,200); dialogStroke.Thickness=2; dialogStroke.Parent=Dialog

local DialogHeader=Instance.new("Frame"); DialogHeader.Size=UDim2.new(1,0,0,DHH)
DialogHeader.BackgroundColor3=Color3.fromRGB(60,25,90); DialogHeader.BorderSizePixel=0
DialogHeader.ZIndex=21; DialogHeader.Parent=Dialog
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
DialogCloseBtn:SetAttribute("TutorialTarget", "PrestigeCloseBtn")
Instance.new("UICorner",DialogCloseBtn).CornerRadius=UDim.new(0,5)

local CBH=D.ConfirmBtnH
local ConfirmBtn=Instance.new("TextButton"); ConfirmBtn.Size=UDim2.new(1,-30,0,CBH)
ConfirmBtn.Position=UDim2.new(0,15,1,-(CBH+8)) -- Anchored to the bottom
ConfirmBtn.BackgroundColor3=PRESTIGE_COLOR_ACTIVE; ConfirmBtn.BorderSizePixel=0
ConfirmBtn.Text="Prestige Now"; ConfirmBtn.TextColor3=Color3.fromRGB(255,255,255)
ConfirmBtn.TextScaled=true; ConfirmBtn.Font=T.font; ConfirmBtn.ZIndex=22; ConfirmBtn.Parent=Dialog
ConfirmBtn:SetAttribute("TutorialTarget", "PrestigeBtns")
Instance.new("UICorner",ConfirmBtn).CornerRadius=UDim.new(0,8)

-- THE SCROLL CONTAINER (Sits between Header and Confirm Button)
local ScrollContainer = Instance.new("ScrollingFrame")
ScrollContainer.Name = "ScrollContainer"
-- Size leaves room for Header (top) and ConfirmBtn + padding (bottom)
ScrollContainer.Size = UDim2.new(1, 0, 1, -(DHH + CBH + 20)) 
ScrollContainer.Position = UDim2.new(0, 0, 0, DHH + 5)
ScrollContainer.BackgroundTransparency = 1
ScrollContainer.BorderSizePixel = 0
ScrollContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
ScrollContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y
ScrollContainer.ScrollBarThickness = 6
ScrollContainer.Parent = Dialog

local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, GAP) -- Uses your config gap!
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
listLayout.Parent = ScrollContainer

-- Modified MakeLabel: No more manual labelY positioning, parented to ScrollContainer
local function MakeLabel(text, color, h, bold, wrapText)
	local l=Instance.new("TextLabel")
	l.Size=UDim2.new(1,-30,0,h) -- Width slightly smaller to fit scrollbar
	l.BackgroundTransparency=1; l.Text=text; l.TextColor3=color
	l.TextScaled=true; l.Font=bold and T.font or T.fontBody
	l.TextXAlignment=Enum.TextXAlignment.Left; l.ZIndex=21
	if wrapText then l.TextWrapped=true end
	l.Parent=ScrollContainer -- Auto-stacks here!
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

PrestigeButton.MouseButton1Down:Connect(function()
	if dialogOpen then CloseDialog(); return end
	if hasPrestigedThisArea then
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
	if not dialogCanPrestige then CloseDialog(); return end
	dialogCanPrestige=false; CloseDialog(); RequestPrestige:FireServer()
end)

DialogCloseBtn.MouseButton1Down:Connect(function()
	previewPending=false; CloseDialog()
	TweenService:Create(PrestigeButton,TweenInfo.new(0.2),{BackgroundColor3=GetButtonColor()}):Play()
end)

---------------------------------------------------------------
-- RenderStepped
---------------------------------------------------------------
local buttonWasEnabled = false
RunService.RenderStepped:Connect(function(dt)
	if ratePerSecond>0 then displayedTotalEarned+=ratePerSecond*dt end
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
			PrestigeButton.Text=GetButtonText()
			TweenService:Create(PrestigeButton,TweenInfo.new(0.3),{BackgroundColor3=GetButtonColor()}):Play()
		end
	end
end)

---------------------------------------------------------------
-- UpdateHUD � FIX: always reads hasPrestigedThisArea from server
---------------------------------------------------------------
local UpdateHUD=ReplicatedStorage.RemoteEvents:WaitForChild("UpdateHUD")
UpdateHUD.OnClientEvent:Connect(function(stats)
	if stats.multiplier ~= nil then
		local mult = stats.multiplier
		-- Update your prestige label here (adjust name to match your GUI)
		local bonusText = mult > 1 and ("+" .. Formatter.Format((mult - 1) * 100) .. "% earnings bonus") or "+0% earnings bonus"
		-- Example: hud.PrestigeMenu.BonusLabel.Text = bonusText
	end
	if stats.totalEarned then
		serverTotalEarned=stats.totalEarned
		if serverTotalEarned>displayedTotalEarned then displayedTotalEarned=serverTotalEarned end
	end
	if stats.soulAuras then
		serverSoulAuras=stats.soulAuras
		local mult=1+(serverSoulAuras*BONUS_PER_SA)
		-- THE FIX: Replace the string.format line with this
		local bonusPercent = (mult - 1) * 100
		MultDisplayLabel.Text = mult > 1 and ("+" .. Formatter.Format(bonusPercent) .. "% earnings bonus") or "+0% earnings bonus"
		MultDisplayLabel.TextColor3=mult>1 and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(255, 255, 255)
	end
	if stats.rate and stats.passiveInterval then
		local interval=stats.passiveInterval
		ratePerSecond=(interval>0 and stats.rate>0) and (stats.rate/interval) or 0
	end
	-- FIX: always sync prestige limit from server (fixes "Used" stuck after wipe)
	if stats.hasPrestigedThisArea~=nil then
		hasPrestigedThisArea=stats.hasPrestigedThisArea
		if not dialogOpen and not previewPending then
			PrestigeButton.Text=GetButtonText()
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
		PrestigeButton.Text="Used"; hasPrestigedThisArea=true; return
	end
	if info.hasPrestigedThisArea~=nil then hasPrestigedThisArea=info.hasPrestigedThisArea end

	for _,obj in ipairs(workspace:GetChildren()) do
		if obj:GetAttribute("AuraCube") then obj:Destroy() end
	end

	-- ✨ NEW BURST MATH LOGIC ✨
	local burstAmount = 0
	if info.newSoulAuras and info.newSoulAuras > 0 then
		-- The Custom Curve: 44->4, 440->12, 1500->20, 10000->43
		burstAmount = math.floor(math.pow(info.newSoulAuras, 0.4) * 1.1)
	elseif info.isPortalEntry then
		-- Flat amount if traveling to a new area with 0 soul auras (Early Game)
		burstAmount = 15 -- Change this flat number to whatever you want!
	end

	if burstAmount > 0 then
		burstAmount = math.clamp(burstAmount, 1, 50) -- Hard cap at 50 for safety
		local burstEvent = ReplicatedStorage.RemoteEvents:FindFirstChild("TutorialBurst")
		if burstEvent then burstEvent:FireServer(burstAmount) end
	end
	-- ✨ END BURST LOGIC ✨

	displayedTotalEarned=0; serverTotalEarned=0; displayedRunSA=0
	ratePerSecond=0; barHighWaterMark=0; previewPending=false
	serverSoulAuras=info.totalSoulAuras
	local flash=Instance.new("Frame"); flash.Size=UDim2.new(1,0,1,0)
	flash.BackgroundColor3=Color3.fromRGB(180,100,255); flash.BackgroundTransparency=0.2
	flash.ZIndex=50; flash.Parent=mainHUD
	TweenService:Create(flash,TweenInfo.new(0.8,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),{BackgroundTransparency=1}):Play()
	task.delay(0.9, function() if flash and flash.Parent then flash:Destroy() end end)
	PrestigeButton.Text=GetButtonText()
	TweenService:Create(PrestigeButton,TweenInfo.new(0.2),{BackgroundColor3=GetButtonColor()}):Play()
	if not info.isPortalEntry then task.delay(0.3, function() ShowPrestigeResultCard(info) end) end
end)

---------------------------------------------------------------
-- AreaChanged � FIX: always reset prestige state
---------------------------------------------------------------
AreaChanged.OnClientEvent:Connect(function(info)
	hasPrestigedThisArea=info.hasPrestigedThisArea or false
	displayedTotalEarned=0; serverTotalEarned=0; displayedRunSA=0
	ratePerSecond=0; barHighWaterMark=0
	PrestigeButton.Text=GetButtonText()
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

	-- 1. HEADER
	AddLabel("PRESTIGE "..info.prestigeCount.." COMPLETE",Color3.fromRGB(210,160,255),10,36)

	-- 2. SOUL AURAS (FIXED)
	AddLabel("+"..Formatter.Format(info.newSoulAuras).." Soul Auras  ->  "..Formatter.Format(info.totalSoulAuras).." total",
		Color3.fromRGB(255,210,80),52,30)

	-- 3. MULTIPLIER (FIXED)
	local prevBonus = (info.previousMultiplier - 1) * 100
	local newBonus = (info.newMultiplier - 1) * 100
	AddLabel("Earnings Bonus: +"..Formatter.Format(prevBonus).."% -> +"..Formatter.Format(newBonus).."%",
		Color3.fromRGB(160,220,255),88,24)

	-- 4. KICKSTART BONUS
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
-- UI JUICE: Button Hover & Click Animations
---------------------------------------------------------------
local function AddButtonJuice(btn)
	-- Ensure the button has a UIScale object to animate
	local scale = btn:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = btn
	end

	-- Hover in: Slight grow
	btn.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Sine), {Scale = 1.08}):Play()
	end)

	-- Hover out: Return to normal
	btn.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Sine), {Scale = 1}):Play()
	end)

	-- Click down: Shrink inwards
	btn.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1, Enum.EasingStyle.Sine), {Scale = 0.9}):Play()
	end)

	-- Release click: Bounce back to hover size
	btn.MouseButton1Up:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), {Scale = 1.08}):Play()
	end)
end

-- ✨ Apply the juice to your Area Browser buttons!
AddButtonJuice(PrestigeButton)
AddButtonJuice(ConfirmBtn)
AddButtonJuice(DialogCloseBtn)

local function RefreshLook()
	UITheme.Apply(PrestigeButton, "Panel")
	UITheme.Apply(ConfirmBtn, "Panel") -- 'Panel' usually looks best for big floating boxes
	UITheme.ApplyShine(Dialog)

	local outerStroke = Dialog:FindFirstChildWhichIsA("UIStroke")
	if outerStroke then
		outerStroke.Color = Color3.fromRGB(165, 20, 255) -- Change these RGB numbers to whatever color you want!
	end
end

task.wait(2)
RefreshLook()

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

