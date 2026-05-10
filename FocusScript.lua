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
PrestigeButton.Text = "Prestige"; PrestigeButton.TextColor3 = Color3.fromRGB(255,255,255)
PrestigeButton.TextScaled = true; PrestigeButton.Font = T.font
PrestigeButton.ZIndex = 5; PrestigeButton.Parent = mainHUD
CollectionService:AddTag(PrestigeButton, "Tutorial_PrestigeButton") -- Tutorial Tracker Tag
Instance.new("UICorner", PrestigeButton).CornerRadius = UDim.new(0,6)

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
CollectionService:AddTag(Dialog, "Tutorial_PrestigePanel") -- Tutorial Tracker Tag
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
CollectionService:AddTag(DialogCloseBtn, "Tutorial_PrestigeCloseBtn") -- Tutorial Tracker Tag
Instance.new("UICorner",DialogCloseBtn).CornerRadius=UDim.new(0,5)

local CBH=D.ConfirmBtnH
local ConfirmBtn=Instance.new("TextButton"); ConfirmBtn.Size=UDim2.new(1,-30,0,CBH)
ConfirmBtn.Position=UDim2.new(0,15,1,-(CBH+8))
ConfirmBtn.BackgroundColor3=PRESTIGE_COLOR_ACTIVE; ConfirmBtn.BorderSizePixel=0
ConfirmBtn.Text="Prestige Now"; ConfirmBtn.TextColor3=Color3.fromRGB(255,255,255)
ConfirmBtn.TextScaled=true; ConfirmBtn.Font=T.font; ConfirmBtn.ZIndex=22; ConfirmBtn.Parent=Dialog
CollectionService:AddTag(ConfirmBtn, "Tutorial_PrestigeConfirm") -- Tutorial Tracker Tag
Instance.new("UICorner",ConfirmBtn).CornerRadius=UDim.new(0,8)

local ScrollContainer = Instance.new("ScrollingFrame")
ScrollContainer.Name = "ScrollContainer"
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
listLayout.Padding = UDim.new(0, GAP)
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
listLayout.Parent = ScrollContainer

local function MakeLabel(text, color, h, bold, wrapText)
	local l=Instance.new("TextLabel")
	l.Size=UDim2.new(1,-30,0,h)
	l.BackgroundTransparency=1; l.Text=text; l.TextColor3=color
	l.TextScaled=true; l.Font=bold and T.font or T.fontBody
	l.TextXAlignment=Enum.TextXAlignment.Left; l.ZIndex=21
	if wrapText then l.TextWrapped=true end
	l.Parent=ScrollContainer
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
	if dialogOpen then
		-- LOGIC GATING
		if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_ClosePrestige") then return end
		CloseDialog()
		if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
		return
	end
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

	-- LOGIC GATING
	if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_OpenPrestige") then return end

	previewPending=true
	TweenService:Create(PrestigeButton,TweenInfo.new(0.15),{BackgroundColor3=PRESTIGE_COLOR_PENDING}):Play()
	PreviewPrestige:FireServer()

	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end

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
	-- LOGIC GATING
	if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_PrestigeConfirm") then return end

	if not dialogCanPrestige then CloseDialog(); return end
	dialogCanPrestige=false; CloseDialog(); RequestPrestige:FireServer()

	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
end)

DialogCloseBtn.MouseButton1Down:Connect(function()
	-- LOGIC GATING
	if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_ClosePrestige") then return end

	previewPending=false; CloseDialog()
	TweenService:Create(PrestigeButton,TweenInfo.new(0.2),{BackgroundColor3=GetButtonColor()}):Play()

	if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
end)

---------------------------------------------------------------
-- RenderStepped
---------------------------------------------------------------
local buttonWasEnabled = false
RunService.RenderStepped:Connect(function(dt)
	if ratePerSecond>0 then displayedTotalEarned+=ratePerSecond*dt end

	-- ✨ FIX: Make Total Earned perfectly accessible to the TutorialController instantly
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
			PrestigeButton.Text=GetButtonText()
			TweenService:Create(PrestigeButton,TweenInfo.new(0.3),{BackgroundColor3=GetButtonColor()}):Play()
		end
	end
end)

---------------------------------------------------------------
-- UpdateHUD
---------------------------------------------------------------
local UpdateHUD=ReplicatedStorage.RemoteEvents:WaitForChild("UpdateHUD")
UpdateHUD.OnClientEvent:Connect(function(stats)
	if stats.multiplier ~= nil then
		local mult = stats.multiplier
		local bonusText = mult > 1 and ("+" .. Formatter.Format((mult - 1) * 100) .. "% earnings bonus") or "+0% earnings bonus"
	end
	if stats.totalEarned then
		serverTotalEarned=stats.totalEarned
		if serverTotalEarned>displayedTotalEarned then displayedTotalEarned=serverTotalEarned end
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

	local burstAmount = 0
	if info.newSoulAuras and info.newSoulAuras > 0 then
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
	PrestigeButton.Text=GetButtonText()
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

-- ✨ TUTORIAL OVERRIDE: Close prestige when camera pans
local forceClose = ReplicatedStorage:FindFirstChild("ForceCloseUI") or Instance.new("BindableEvent")
forceClose.Name = "ForceCloseUI"
forceClose.Parent = ReplicatedStorage
forceClose.Event:Connect(function()
	if dialogOpen then CloseDialog() end
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
local globalHoldActive  = false  -- Global flag to prevent multiple simultaneous holds
local globalHoldGeneration = 0    -- Global generation counter

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
CollectionService:AddTag(ShopButton, "Tutorial_ShopButton") -- Tutorial Tracker Tag
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
CollectionService:AddTag(ShopPanel, "Tutorial_ShopPanel") -- Tutorial Tracker Tag
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
CollectionService:AddTag(CloseButton, "Tutorial_ShopCloseBtn") -- Tutorial Tracker Tag
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
	CollectionService:AddTag(buyButton, "Tutorial_Buy_" .. upgradeId) -- Tutorial Tracker Tag
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

		-- ✨ TUTORIAL ADAPTATION: Prevent accidental multi-buys if the FSM advances while holding!
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
		-- LOGIC GATING: Ask TutorialController for permission
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

ShopButton.MouseButton1Down:Connect(function()
	if shopOpen then
		-- LOGIC GATING
		if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_CloseShop") then return end
		CloseShop()
		if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
	else
		-- LOGIC GATING
		if type(shared.TutorialCanPerform) == "function" and not shared.TutorialCanPerform("Action_OpenShop") then return end
		OpenShop()
		if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
	end
end)

CloseButton.MouseButton1Down:Connect(function()
	-- LOGIC GATING
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

			-- ✨ FIX: Smoothly update the card instead of completely deleting and rebuilding the entire shop!
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

-- ✨ TUTORIAL OVERRIDE: Close shop when camera pans
local forceClose = ReplicatedStorage:FindFirstChild("ForceCloseUI") or Instance.new("BindableEvent")
forceClose.Name = "ForceCloseUI"
forceClose.Parent = ReplicatedStorage
forceClose.Event:Connect(function()
	if shopOpen then CloseShop() end
end)
