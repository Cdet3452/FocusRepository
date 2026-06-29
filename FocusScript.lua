-- Location: ServerScriptService > GameManager

local DataStoreService  = game:GetService("DataStoreService")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PlayerDB       = DataStoreService:GetDataStore("PlayerData_v1")
local AdminConfig    = require(ReplicatedStorage.Modules.AdminConfig)	
local UpgradeConfig  = require(ReplicatedStorage.Modules.UpgradeConfig)
local MutationConfig = require(ReplicatedStorage.Modules.MutationConfig)
local EpicUpgradeConfig = require(ReplicatedStorage.Modules:WaitForChild("EpicUpgradeConfig"))

local BridgeNet2      = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))
local UpdateHUDBridge = BridgeNet2.ServerBridge("UpdateHUD")
local BankActionBridge = BridgeNet2.ServerBridge("BankAction")

local AreaChanged = ReplicatedStorage.RemoteEvents:WaitForChild("AreaChanged")

local SAVE_COOLDOWN = 7

local function DefaultData()
	return {
		currency      = 0,
		totalEarned   = 0,
		soulAuras     = 0,
		prestigeCount = 0,
		pendingAuras        = 0,
		upgrades = { dropRate=0, blockValue=0, habitatCapacity=0, autoShipper=0, mutationSpeed=0, mutationTierChance=0, passiveTickSpeed=0, hatcheryCapacity=0 },
		totalCubesProduced    = 0,
		totalPlatformsShipped = 0,
		totalLegendaryCubes   = 0,
		totalMythicCubes      = 0,
		totalDivineCubes      = 0,
		totalCelestialCubes   = 0,
		totalCosmicCubes      = 0,
		totalOmniCubes        = 0,
		settings = { sfxEnabled=true, musicEnabled=true },
		farmEvaluation = 0,
		currentArea    = 1,
		unlockedAreas  = { 1 },
		goldenAuras = AdminConfig.GoldenAuraStart or 10,
		piggyBank = 0,
		highestPiggyBank = 0, 
		piggyBankBroken = 0, 
		aurmers = 0,
		inSpecialArea = false,
		boostInventory = { AuraRush=0, SpawnBoost=0, SoulBoost=0 },
		hasPrestigedThisArea = false,
		epicUpgrades         = {},
		tutorialProgress     = {},
		tutorialComplete     = false,
		claimedMail          = {},
		unlockedMail         = {},
		claimedBadges        = {},
		claimedChallenges    = {},
		claimedAuras         = {},
		discoveredTiers      = {}
	}
end

local function DefaultRuntime()
	return {
		cubes              = {},
		cubeOrder          = {},
		cubeCount          = 0,
		storedCubeCount    = 0,

		activeMutatedValue = 0,

		nextCubeId         = 1,
		totalMutatedValue  = 0,
		lastActiveTime     = tick(),
		sessionStart       = tick(),
	}
end

local PlayerData    = {}
local PlayerRuntime = {}
local lastSaveTick  = {}
local pendingSave   = {}

local function DeepMerge(saved, defaults)
	for key, defaultValue in pairs(defaults) do
		if saved[key] == nil then
			saved[key] = defaultValue
		elseif type(defaultValue) == "table" and type(saved[key]) == "table" and not getmetatable(saved[key]) then
			if defaultValue[1] == nil then DeepMerge(saved[key], defaultValue) end
		end
	end
end

local function EnsureUnlockedAreas(data)
	if type(data.unlockedAreas) ~= "table" then data.unlockedAreas = { 1 } end
	local has1, hasCurrent = false, false
	for _, v in ipairs(data.unlockedAreas) do
		if v == 1 then has1 = true end
		if v == data.currentArea then hasCurrent = true end
	end
	if not has1 then table.insert(data.unlockedAreas, 1) end
	if not hasCurrent and data.currentArea ~= 1 then table.insert(data.unlockedAreas, data.currentArea) end
end

local function SaveData(player)
	local uid  = player.UserId
	local data = PlayerData[uid]
	if not data then return end
	local now, last = tick(), lastSaveTick[uid] or 0
	if now - last >= SAVE_COOLDOWN then
		lastSaveTick[uid] = now
		pcall(function() PlayerDB:SetAsync("Player_" .. uid, data) end)
	else
		if not pendingSave[uid] then
			pendingSave[uid] = true
			task.delay(SAVE_COOLDOWN - (now - last) + 0.5, function()
				pendingSave[uid] = nil
				if player and player.Parent and PlayerData[uid] then
					pcall(function() PlayerDB:SetAsync("Player_" .. uid, PlayerData[uid]) end)
					lastSaveTick[uid] = tick()
				end
			end)
		end
	end
end

local function LoadData(player)
	local key      = "Player_" .. player.UserId
	local ok, data = pcall(function() return PlayerDB:GetAsync(key) end)

	if ok and data then
		DeepMerge(data, DefaultData())
		PlayerData[player.UserId] = data
	else
		PlayerData[player.UserId] = DefaultData()
	end

	local d = PlayerData[player.UserId]
	EnsureUnlockedAreas(d)
	PlayerRuntime[player.UserId] = DefaultRuntime()

	if AdminConfig.WipeMoneyOnLoad then
		d.currency=0; d.totalEarned=0; d.pendingAuras=0; d.pendingPayout=0; d.pendingBonusPayout=0; d.lastPayout=0
		for k in pairs(d.upgrades) do d.upgrades[k] = 0 end
		d.totalCubesProduced=0; d.totalPlatformsShipped=0; d.totalLegendaryCubes=0
		d.totalMythicCubes=0; d.totalDivineCubes=0; d.totalCelestialCubes=0; d.totalCosmicCubes=0; d.totalOmniCubes=0
		d.piggyBank=0; d.highestPiggyBank=0; d.piggyBankBroken=0; d.farmEvaluation=0; d.goldenAuras=AdminConfig.GoldenAuraStart or 10
		d.aurmers=0; d.inSpecialArea=false
		d.boostInventory={ AuraRush=0, SpawnBoost=0, SoulBoost=0 }
		d.hasPrestigedThisArea=false; d.claimedMail={}; d.tutorialProgress={}; d.tutorialComplete=false
	end

	if AdminConfig.WipePrestigeOnLoad then d.soulAuras=0; d.prestigeCount=0; d.hasPrestigedThisArea=false end
	if AdminConfig.WipeAreaOnLoad then d.currentArea=1; d.farmEvaluation=0; d.unlockedAreas={ 1 }; d.hasPrestigedThisArea=false end
	if AdminConfig.WipeEpicOnLoad then d.goldenAuras = AdminConfig.GoldenAuraStart or 0; d.epicUpgrades = {} end

	if AdminConfig.WipeAchievementsOnLoad then 
		d.totalCubesProduced=0; d.totalPlatformsShipped=0; d.totalLegendaryCubes=0
		d.totalMythicCubes=0; d.totalDivineCubes=0; d.totalCelestialCubes=0; d.totalCosmicCubes=0; d.totalOmniCubes=0
		d.claimedBadges={}; d.claimedChallenges={}; d.claimedAuras={}; d.discoveredTiers={}
	end

	if not d.epicUpgrades     then d.epicUpgrades     = {} end
	if not d.tutorialProgress then d.tutorialProgress = {} end
	if d.tutorialComplete == nil then d.tutorialComplete = false end
	if not d.claimedMail      then d.claimedMail      = {} end
	if not d.unlockedMail     then d.unlockedMail     = {} end
	if d.hasPrestigedThisArea == nil then d.hasPrestigedThisArea = false end

	d.inSpecialArea = false

	task.wait(1)
	if not player or not player.Parent then return end

	local upgradesState = {}
	for upgradeId, level in pairs(d.upgrades or {}) do upgradesState[upgradeId] = { level = level } end

	local epicUpgradesState = {}
	for upgradeId, level in pairs(d.epicUpgrades or {}) do epicUpgradesState[upgradeId] = { level = level } end

	UpdateHUDBridge:Fire(player, {
		currency=d.currency, pendingAuras=0, 
		habitatCapacity = UpgradeConfig.GetHabitatCapacity(d), 
		rate=0, 
		passiveInterval = UpgradeConfig.GetPassiveInterval(d),
		totalEarned=d.totalEarned or 0, soulAuras=d.soulAuras or 0, farmEvaluation=d.farmEvaluation or 0,
		goldenAuras=d.goldenAuras or 0, 
		piggyBank=d.piggyBank or 0, piggyBankBroken=d.piggyBankBroken or 0, highestPiggyBank=d.highestPiggyBank or 0,
		aurmers=d.aurmers or 0, inSpecialArea=d.inSpecialArea or false,
		boostInventory=d.boostInventory or {}, settings=d.settings or {},
		prestigeCount=d.prestigeCount or 0, hasPrestigedThisArea=d.hasPrestigedThisArea or false,
		tutorialProgress=d.tutorialProgress or {}, tutorialComplete=d.tutorialComplete or false,
		epicUpgrades=epicUpgradesState, totalCubesProduced=d.totalCubesProduced or 0,
		currentArea=d.currentArea or 1, upgrades=upgradesState,
	})

	player:SetAttribute("LivePiggyBank", d.piggyBank or 0)
	player:SetAttribute("HighestPiggyBank", d.highestPiggyBank or 0)
	player:SetAttribute("PiggyBankBroken", d.piggyBankBroken or 0)

	task.delay(0.5, function()
		if not player or not player.Parent then return end

		local resetState = {}
		for tierNum, tierData in ipairs(UpgradeConfig.Tiers) do
			for upgradeId, cfg in pairs(tierData.upgrades) do
				local lv = d.upgrades[upgradeId] or 0
				local maxed = lv >= cfg.maxLevel
				resetState[upgradeId] = { level=lv, maxLevel=cfg.maxLevel, cost=maxed and 0 or UpgradeConfig.CalculateCost(upgradeId, lv, d), maxed=maxed }
			end
		end
		local UpgradeUpdated = ReplicatedStorage.RemoteEvents:FindFirstChild("UpgradeUpdated")
		if UpgradeUpdated then UpgradeUpdated:FireClient(player, { type="fullState", upgrades=resetState, currency=d.currency }) end

		local epicResetState = {}
		for tierNum, tierData in ipairs(EpicUpgradeConfig.Tiers) do
			for upgradeId, cfg in pairs(tierData.upgrades) do
				local lv = d.epicUpgrades[upgradeId] or 0
				local maxed = lv >= cfg.maxLevel
				epicResetState[upgradeId] = { level=lv, maxLevel=cfg.maxLevel, cost=maxed and 0 or EpicUpgradeConfig.CalculateCost(upgradeId, lv), maxed=maxed }
			end
		end
		local EpicUpgradeUpdated = ReplicatedStorage.RemoteEvents:FindFirstChild("EpicUpgradeUpdated")
		if EpicUpgradeUpdated then EpicUpgradeUpdated:FireClient(player, { type="fullState", upgrades=epicResetState, goldenAuras=d.goldenAuras or 0 }) end
	end)
end

Players.PlayerAdded:Connect(LoadData)

Players.PlayerRemoving:Connect(function(player)
	SaveData(player)
	PlayerData[player.UserId] = nil
	PlayerRuntime[player.UserId] = nil
end)

local lastPeriodicSave = tick()
game:GetService("RunService").Heartbeat:Connect(function()
	if tick() - lastPeriodicSave >= 60 then
		lastPeriodicSave = tick()
		for _, p in ipairs(Players:GetPlayers()) do SaveData(p) end
	end
end)

task.spawn(function()
	local TutorialStepComplete = ReplicatedStorage.RemoteEvents:WaitForChild("TutorialStepComplete", 10)
	if not TutorialStepComplete then return end
	TutorialStepComplete.OnServerEvent:Connect(function(player, stepId)
		local uid  = player.UserId
		local data = PlayerData[uid]
		if not data then return end
		if not data.tutorialProgress then data.tutorialProgress = {} end
		if stepId == "tutorialComplete" then data.tutorialComplete = true
		elseif type(stepId) == "string" and #stepId < 100 then data.tutorialProgress[stepId] = true end
	end)
end)

local GameManager = {}

function GameManager.GetData(uid)    return PlayerData[uid]    end
function GameManager.GetRuntime(uid) return PlayerRuntime[uid] end
function GameManager.SavePlayer(p)   SaveData(p)               end

function GameManager.PerformPrestigeReset(player)
	local uid = player.UserId
	local runtime = PlayerRuntime[uid]
	if runtime then
		runtime.cubes = {}
		runtime.cubeOrder = {}
		runtime.cubeCount = 0
		runtime.activeMutatedValue = 0
		runtime.storedCubeCount = 0
		runtime.totalMutatedValue = 0
		runtime.lastActiveTime = tick()
		runtime.sessionStart = tick()
	end
	SaveData(player)
end

function GameManager.AddGoldenAuras(uid, amount)
	local data = PlayerData[uid]
	if not data then return 0 end

	local epicBonus = 0
	pcall(function()
		local EpicUpgradeManager = require(ReplicatedStorage.Modules:WaitForChild("EpicUpgradeManager"))
		epicBonus = EpicUpgradeManager.GetBonus(uid, "goldenAuraValue") or 0
	end)

	local finalAmount = math.floor(amount * (1 + epicBonus))
	data.goldenAuras = (data.goldenAuras or 0) + finalAmount

	local player = Players:GetPlayerByUserId(uid)
	if player then
		UpdateHUDBridge:Fire(player, { goldenAuras = data.goldenAuras })
	end

	return finalAmount
end

function GameManager.AddPiggyBank(uid, rawAmount)
	local BankFillEvent = game:GetService("ServerScriptService"):FindFirstChild("BankFillEvent")
	if BankFillEvent then
		BankFillEvent:Fire(uid, rawAmount)
	else
		warn("[GameManager] BankFillEvent not found! PiggyBank visual routing failed.")
	end
end

function GameManager.AddCube(uid, cubeRecord)
	local runtime = PlayerRuntime[uid]
	if not runtime then return nil end

	local id = runtime.nextCubeId
	runtime.nextCubeId += 1	
	runtime.cubes[id] = cubeRecord

	local val = MutationConfig.GetMutatedValue(cubeRecord)
	runtime.totalMutatedValue += val

	if not cubeRecord.isStored then
		runtime.activeMutatedValue += val
	else
		runtime.storedCubeCount += 1
	end

	table.insert(runtime.cubeOrder, id)
	runtime.cubeCount += 1
	return id
end

function GameManager.MarkCubeStored(uid, cubeId)
	local runtime = PlayerRuntime[uid]
	if not runtime then return end
	local cube = runtime.cubes[cubeId]
	if cube and not cube.isStored then
		cube.isStored = true
		runtime.storedCubeCount += 1
		runtime.activeMutatedValue -= MutationConfig.GetMutatedValue(cube)
	end
end

function GameManager.RemoveCube(uid, cubeId)
	local runtime = PlayerRuntime[uid]
	if not runtime or not runtime.cubes[cubeId] then return end
	local cube = runtime.cubes[cubeId]

	local val = MutationConfig.GetMutatedValue(cube)
	runtime.totalMutatedValue -= val

	if cube.isStored then
		runtime.storedCubeCount -= 1
	else
		runtime.activeMutatedValue -= val
	end

	runtime.cubes[cubeId] = nil
	runtime.cubeCount -= 1
end

function GameManager.CollectOldestCubes(uid, count)
	local runtime = PlayerRuntime[uid]
	if not runtime then return {}, {} end
	local collected, collectedCubes, newOrder = {}, {}, {}
	local needed = count
	for _, cubeId in ipairs(runtime.cubeOrder) do
		if runtime.cubes[cubeId] then
			if needed > 0 then
				table.insert(collected, cubeId)
				table.insert(collectedCubes, runtime.cubes[cubeId])
				GameManager.RemoveCube(uid, cubeId)
				needed -= 1
			else
				table.insert(newOrder, cubeId)
			end
		end
	end
	runtime.cubeOrder = newOrder
	return collected, collectedCubes
end

game:BindToClose(function()
	print("[GameManager] Server shutting down. Forcing final save for all players...")
	for _, player in ipairs(Players:GetPlayers()) do SaveData(player) end
	task.wait(2)
end)

return GameManager

-- PlatformController.lua
-- Location: StarterPlayer > StarterPlayerScripts > PlatformController

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local AdminConfig = require(ReplicatedStorage.Modules.AdminConfig)
local Formatter = require(ReplicatedStorage.Modules.NumberFormatter) 
local PoolManager = require(ReplicatedStorage.Modules:WaitForChild("PoolManager"))
local UpdateMultiplier = ReplicatedStorage:WaitForChild("UpdateMultiplier")
local HabitatFullEvent = ReplicatedStorage:WaitForChild("HabitatFullEvent")

local AreaChanged = ReplicatedStorage.RemoteEvents:WaitForChild("AreaChanged")
local AreaUpdated = ReplicatedStorage.RemoteEvents:WaitForChild("AreaUpdated")

local BridgeNet2      = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))
local ShipAurasBridge = BridgeNet2.ClientBridge("ShipAuras")

local HabitatHolder = workspace:WaitForChild("HabitatHolder") 

local Camera = workspace.CurrentCamera
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainHUD = playerGui:WaitForChild("MainHUD")
local currLabel = mainHUD:WaitForChild("CurrencyLabel")
local gaurasLabel = mainHUD:WaitForChild("GoldenAurasLabel")

local function GetHabitatPos()
	return HabitatHolder:WaitForChild("Position").Position
end

local currentMultiplier = 1.0
local currentAreaIndex = 1
local platformQueue = {}
local processingPlatform = false

local MultiplierColors = {
	[1.0] = Color3.fromRGB(255, 255, 255),
	[1.5] = Color3.fromRGB(100, 200, 255),
	[2.0] = Color3.fromRGB(80, 255, 120),
	[3.0] = Color3.fromRGB(180, 60, 255),
	[5.0] = Color3.fromRGB(255, 200, 0),
}

local MultiplierNames = {
	[1.0] = "No Bonus",
	[1.5] = "1.5x Bonus",
	[2.0] = "2x Bonus",
	[3.0] = "3x Bonus",
	[5.0] = "5x Bonus",
}

UpdateMultiplier.Event:Connect(function(mult)
	currentMultiplier = mult
end)

AreaUpdated.OnClientEvent:Connect(function(info)
	if info.currentArea then currentAreaIndex = info.currentArea end
end)

AreaChanged.OnClientEvent:Connect(function(info)
	if info.newArea then currentAreaIndex = info.newArea end
end)

local function FormatCurrency(n)
	local num = tonumber(n) or 0
	if num < 1000 then
		return string.format("%.2f", num)
	else
		return Formatter.Format(num)
	end
end

local function FormatNumber(n)
	return Formatter.Format(math.floor(tonumber(n) or 0))
end

---------------------------------------------------------------
-- ✨ UNIVERSAL JUICY VISUALS (CASH & AURAS) ✨
---------------------------------------------------------------
local function PlayJuiceEffect(exactAmount, currencyType)
	local isAura = (currencyType == "Auras")
	local targetLabel = isAura and gaurasLabel or currLabel

	local pendingKey = isAura and "LocalPendingAuras" or "LocalPendingPayout"
	local addKey = isAura and "VisualAurasToAdd" or "VisualCashToAdd"

	local currentPending = player:GetAttribute(pendingKey) or 0
	player:SetAttribute(pendingKey, currentPending + exactAmount)

	local targetPos = targetLabel.AbsolutePosition
	local targetSize = targetLabel.AbsoluteSize

	local popupWidth = 250
	local popupHeight = 70
	local startX = targetPos.X - popupWidth - 40 
	local startY = targetPos.Y + (targetSize.Y / 2) - (popupHeight / 2) 

	local endPos2D = targetPos + (targetSize / 2)

	local effectGui = Instance.new("ScreenGui")
	effectGui.Name = "JuiceGui_" .. currencyType
	effectGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	effectGui.Parent = playerGui

	local popupText = Instance.new("TextLabel")
	popupText.Text = (isAura and "+" or "+$") .. FormatCurrency(exactAmount)
	popupText.Font = Enum.Font.FredokaOne
	popupText.TextScaled = true
	popupText.TextColor3 = isAura and Color3.fromRGB(255, 215, 0) or Color3.fromRGB(85, 255, 127)
	popupText.BackgroundTransparency = 1
	popupText.TextXAlignment = Enum.TextXAlignment.Right 
	popupText.Size = UDim2.new(0, popupWidth, 0, popupHeight)
	popupText.Position = UDim2.new(0, startX, 0, startY)
	popupText.ZIndex = 100
	popupText.Parent = effectGui

	local textStroke = Instance.new("UIStroke", popupText)
	textStroke.Color = isAura and Color3.fromRGB(80, 50, 0) or Color3.fromRGB(0, 50, 0)
	textStroke.Thickness = 3

	local textScale = Instance.new("UIScale", popupText)
	textScale.Scale = 0

	TweenService:Create(textScale, TweenInfo.new(0.4, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), {Scale = 1.2}):Play()

	task.delay(0.6, function()
		TweenService:Create(popupText, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			Position = UDim2.new(0, startX - 120, 0, startY),
			TextTransparency = 1
		}):Play()
		TweenService:Create(textStroke, TweenInfo.new(0.8), {Transparency = 1}):Play()
	end)

	local sfxFolder = ReplicatedStorage:FindFirstChild("SFX") or ReplicatedStorage:FindFirstChild("Sounds")
	if sfxFolder and sfxFolder:FindFirstChild("CashRegister") then
		local sfx = sfxFolder.CashRegister:Clone()
		if isAura then sfx.Pitch = 1.3 end 
		sfx.Parent = game:GetService("SoundService")
		sfx:Play()
		Debris:AddItem(sfx, 2)
	end

	local iconCount = 10
	local iconSize = 40
	local iconId = "rbxassetid://14916846070" 

	if isAura then
		iconId = "rbxassetid://4483362458" 
		if exactAmount < 100 then
			iconCount = math.min(exactAmount, 30)
			iconSize = 35 
		elseif exactAmount < 1000 then
			iconCount = math.min(math.ceil(exactAmount / 10), 30)
			iconSize = 55 
		else
			iconCount = math.min(math.ceil(exactAmount / 100), 30)
			iconSize = 80 
		end
	end

	local chunkAmount = exactAmount / iconCount
	local coinsHit = 0

	for i = 1, iconCount do
		local coin = Instance.new("ImageLabel")
		coin.Image = iconId
		if isAura then coin.ImageColor3 = Color3.fromRGB(255, 215, 0) end 
		coin.BackgroundTransparency = 1
		coin.Size = UDim2.new(0, iconSize, 0, iconSize)

		local coinStartX = startX + popupWidth - (iconSize * 1.5)
		local coinStartY = startY + (popupHeight / 2) - (iconSize / 2)

		coin.Position = UDim2.new(0, coinStartX, 0, coinStartY)
		coin.ZIndex = 90
		coin.Parent = effectGui

		local randomOffsetX = math.random(-80, 80)
		local randomOffsetY = math.random(-80, 80)
		local burstPos = UDim2.new(0, coinStartX + randomOffsetX, 0, coinStartY + randomOffsetY)

		local burstTween = TweenService:Create(coin, TweenInfo.new(0.3, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), {
			Position = burstPos,
			Rotation = math.random(-180, 180)
		})
		burstTween:Play()

		burstTween.Completed:Connect(function()
			local flyTween = TweenService:Create(coin, TweenInfo.new(0.4 + (i * 0.02), Enum.EasingStyle.Back, Enum.EasingDirection.In), {
				Position = UDim2.new(0, endPos2D.X - (iconSize/2), 0, endPos2D.Y - (iconSize/2)),
				Size = UDim2.new(0, iconSize/2, 0, iconSize/2),
				ImageTransparency = 0.3
			})
			flyTween:Play()

			flyTween.Completed:Connect(function()
				if coin.Parent then coin:Destroy() end
				coinsHit += 1

				player:SetAttribute(addKey, chunkAmount)

				local pending = player:GetAttribute(pendingKey) or 0
				player:SetAttribute(pendingKey, math.max(0, pending - chunkAmount))

				if sfxFolder and sfxFolder:FindFirstChild("CoinTick") then
					local sfx = sfxFolder.CoinTick:Clone()
					sfx.Pitch = (isAura and 1.8 or 1.5) + (math.random()*0.2)
					sfx.Parent = game:GetService("SoundService")
					sfx:Play()
					Debris:AddItem(sfx, 1)
				end

				local ts = targetLabel:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", targetLabel)
				ts.Scale = 1.1
				TweenService:Create(ts, TweenInfo.new(0.1, Enum.EasingStyle.Sine), {Scale = 1}):Play()
			end)
		end)
	end

	task.delay(3, function()
		if effectGui.Parent then effectGui:Destroy() end
		if coinsHit < iconCount then
			local remaining = (iconCount - coinsHit) * chunkAmount
			player:SetAttribute(addKey, remaining)
			player:SetAttribute(pendingKey, 0)
		end
	end)
end

---------------------------------------------------------------
-- ✨ DYNAMIC 3D PLATFORM SPAWNER ✨
---------------------------------------------------------------
local function CreatePlatform(spawnCFrame, multiplierColor)
	local areaFolder = ReplicatedStorage:FindFirstChild("AreaAssets") and ReplicatedStorage.AreaAssets:FindFirstChild("Area" .. currentAreaIndex)
	local template = areaFolder and areaFolder:FindFirstChild("PlatformModel")

	if not template then
		template = ReplicatedStorage:FindFirstChild("PlatformModel")
	end

	local platform

	if template and template:IsA("Model") then
		platform = template:Clone()
		platform:PivotTo(spawnCFrame)

		for _, part in ipairs(platform:GetDescendants()) do
			if part:IsA("BasePart") and (part.Name == "Glow" or part.Material == Enum.Material.Neon) then
				part.Color = multiplierColor
			end
		end
	else
		platform = Instance.new("Part")
		platform.Name = "HoverPlatform"
		platform.Size = Vector3.new(8, 0.5, 8)
		platform.Anchored = true
		platform.CastShadow = false
		platform.Material = Enum.Material.Neon
		platform.Color = multiplierColor
		platform.CFrame = spawnCFrame

		local light = Instance.new("PointLight")
		light.Brightness = 2
		light.Range = 12
		light.Color = multiplierColor
		light.Parent = platform
	end

	platform.Parent = workspace
	return platform
end

local function AttachLabels(platformRoot, payout, multiplier)
	if not platformRoot then return end

	local payoutBB = Instance.new("BillboardGui")
	payoutBB.Size = UDim2.new(8, 0, 2.5, 0) 
	payoutBB.StudsOffset = Vector3.new(0, 5, 0)
	payoutBB.AlwaysOnTop = false
	payoutBB.Adornee = platformRoot
	payoutBB.Parent = platformRoot

	local payoutLabel = Instance.new("TextLabel")
	payoutLabel.Size = UDim2.new(1, 0, 1, 0)
	payoutLabel.BackgroundTransparency = 1
	payoutLabel.Text = "$" .. FormatCurrency(payout)
	payoutLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
	payoutLabel.TextScaled = true
	payoutLabel.Font = Enum.Font.GothamBold
	payoutLabel.TextStrokeTransparency = 1
	payoutLabel.TextTransparency = 1
	payoutLabel.Parent = payoutBB

	local payoutStroke = Instance.new("UIStroke", payoutLabel)
	payoutStroke.Thickness = 3
	payoutStroke.Color = Color3.fromRGB(0, 40, 0)

	local multBB = Instance.new("BillboardGui")
	multBB.Size = UDim2.new(6, 0, 1.5, 0) 
	multBB.StudsOffset = Vector3.new(0, 2.5, 0)
	multBB.AlwaysOnTop = false
	multBB.Adornee = platformRoot
	multBB.Parent = platformRoot

	local multLabel = Instance.new("TextLabel")
	multLabel.Size = UDim2.new(1, 0, 1, 0)
	multLabel.BackgroundTransparency = 1
	multLabel.Text = MultiplierNames[multiplier] or "No Bonus"
	multLabel.TextColor3 = MultiplierColors[multiplier] or Color3.fromRGB(255, 255, 255)
	multLabel.TextScaled = true
	multLabel.Font = Enum.Font.Gotham
	multLabel.TextStrokeTransparency = 1
	multLabel.TextTransparency = 1
	multLabel.Parent = multBB

	local multStroke = Instance.new("UIStroke", multLabel)
	multStroke.Thickness = 2.5
	multStroke.Color = Color3.fromRGB(0, 0, 0)

	TweenService:Create(payoutLabel, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
	TweenService:Create(multLabel, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
end

local function PayoutPopup(position, payout, multiplier)
	local anchor = Instance.new("Part")
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Anchored = true
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.Position = position
	anchor.Parent = workspace

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(10, 0, 2.5, 0) 
	bb.StudsOffset = Vector3.new(0, 7, 0)
	bb.AlwaysOnTop = false
	bb.Adornee = anchor
	bb.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = "+ $" .. FormatCurrency(payout)
	label.TextColor3 = MultiplierColors[multiplier] or Color3.fromRGB(100, 255, 100)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextStrokeTransparency = 1
	label.TextTransparency = 0
	label.Parent = bb

	local lStroke = Instance.new("UIStroke", label)
	lStroke.Thickness = 3
	lStroke.Color = Color3.fromRGB(0, 0, 0)

	TweenService:Create(bb, TweenInfo.new(1.8, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { StudsOffset = Vector3.new(0, 18, 0) }):Play()
	task.delay(0.6, function()
		TweenService:Create(label, TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1 }):Play()
		TweenService:Create(lStroke, TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
	end)
	Debris:AddItem(anchor, 2.5)
end

local function GetAuraBlocksNearHabitat()
	local blocks = {}
	local habitatPos = GetHabitatPos()  

	for _, obj in ipairs(workspace:GetChildren()) do
		if obj.Name == "HoverPlatform" or obj == HabitatHolder then
			continue
		end

		local rootPart = nil
		local isCube = false

		if obj:GetAttribute("AuraCube") then
			isCube = true
			if obj:IsA("Model") then
				rootPart = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
			elseif obj:IsA("BasePart") then
				rootPart = obj
			end
		elseif obj:IsA("Part") and obj.Material == Enum.Material.Neon then
			isCube = true
			rootPart = obj
		end

		if isCube and rootPart then
			local dist = (rootPart.Position - habitatPos).Magnitude  
			if dist < 20 then
				table.insert(blocks, { instance = obj, rootPart = rootPart })
			end
		end
	end
	return blocks
end

local function MagnetBlocks(platformRoot, blocks, count)
	if not platformRoot then return end
	local collected = math.min(#blocks, count)
	if collected == 0 then return end

	local tweensDone = 0
	local tweensStarted = 0

	for i = 1, collected do
		local block = blocks[i]
		if not block or not block.rootPart or not block.rootPart.Parent then continue end

		local rootPart = block.rootPart
		local instance = block.instance

		rootPart.Anchored = true

		local tweenProps = { Position = platformRoot.Position }
		if instance:IsA("BasePart") then
			tweenProps.Size = Vector3.new(0.1, 0.1, 0.1)
		end

		local tween = TweenService:Create(rootPart,
			TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			tweenProps
		)

		tweensStarted += 1
		tween.Completed:Connect(function()
			PoolManager.ReturnAura(instance)
			tweensDone += 1

			local currentOffset = player:GetAttribute("HabitatVisualOffset") or 0
			player:SetAttribute("HabitatVisualOffset", math.max(0, currentOffset - 1))
		end)
		tween:Play()
		task.wait(0.05)
	end

	local timeout = tick() + 3
	while tweensDone < tweensStarted and tick() < timeout do
		task.wait(0.05)
	end
end

local function ProcessPlatform(info)
	if info.collected == 0 then return end

	local myPayout     = info.payout
	local myMultiplier = currentMultiplier
	local myDispatchId = info.dispatchId
	local multColor    = MultiplierColors[myMultiplier] or Color3.fromRGB(255, 255, 255)

	local activeSpawn = workspace:FindFirstChild("TruckSpawn", true)
	local activeDest  = workspace:FindFirstChild("TruckDestination", true)

	if not activeSpawn or not activeDest then
		warn("TruckSpawn or TruckDestination not found! Ensure they exist in the current Area model.")
		return
	end

	local spawnCF = activeSpawn:IsA("Model") and activeSpawn:GetPivot() or activeSpawn.CFrame
	local destCF  = activeDest:IsA("Model") and activeDest:GetPivot() or activeDest.CFrame

	spawnCF = spawnCF + Vector3.new(0, AdminConfig.PlatformHoverHeight, 0)
	destCF  = destCF + Vector3.new(0, AdminConfig.PlatformHoverHeight, 0)

	local platform = CreatePlatform(spawnCF, multColor)
	local platformRoot = platform:IsA("Model") and (platform.PrimaryPart or platform:FindFirstChildWhichIsA("BasePart")) or platform

	-- Inject Thruster Visuals
	local thrusterAtt = Instance.new("Attachment")
	thrusterAtt.Position = Vector3.new(0, -1, 0)
	thrusterAtt.Parent = platformRoot

	local thrusterVFX = Instance.new("ParticleEmitter")
	thrusterVFX.Color = ColorSequence.new(multColor)
	thrusterVFX.Size = NumberSequence.new({NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1)})
	thrusterVFX.Lifetime = NumberRange.new(0.3, 0.6)
	thrusterVFX.Rate = 50
	thrusterVFX.Speed = NumberRange.new(5, 10)
	thrusterVFX.EmissionDirection = Enum.NormalId.Bottom
	thrusterVFX.Parent = thrusterAtt

	local habitatPos = GetHabitatPos()
	local midCF = CFrame.new(habitatPos + Vector3.new(0, AdminConfig.PlatformHoverHeight, 0))

	-- Strict alignment to spawn CF rotation
	midCF = CFrame.new(midCF.Position) * spawnCF.Rotation 
	destCF = CFrame.new(destCF.Position) * spawnCF.Rotation

	local cframeProxy = Instance.new("CFrameValue")
	cframeProxy.Value = spawnCF
	cframeProxy.Changed:Connect(function(val)
		if platform:IsA("Model") then
			platform:PivotTo(val)
		else
			platform.CFrame = val
		end
	end)

	local distIn = (spawnCF.Position - midCF.Position).Magnitude
	local tweenIn = TweenService:Create(cframeProxy,
		TweenInfo.new(math.max(0.1, distIn / AdminConfig.PlatformSpeed), Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Value = midCF }
	)
	tweenIn:Play()
	tweenIn.Completed:Wait()

	AttachLabels(platformRoot, myPayout, myMultiplier)
	PayoutPopup(platformRoot.Position, myPayout, myMultiplier)

	local blocks = GetAuraBlocksNearHabitat()
	MagnetBlocks(platformRoot, blocks, info.collected)

	task.wait(0.5)
	HabitatFullEvent:Fire(false)

	local distOut = (midCF.Position - destCF.Position).Magnitude
	local tweenOut = TweenService:Create(cframeProxy,
		TweenInfo.new(math.max(0.1, distOut / AdminConfig.PlatformSpeed), Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Value = destCF }
	)
	tweenOut:Play()
	tweenOut.Completed:Wait()

	cframeProxy:Destroy()
	platform:Destroy()
	ShipAurasBridge:Fire({ action = "payout", value = myDispatchId })
end

local function ProcessQueue()
	if processingPlatform then return end
	processingPlatform = true

	while #platformQueue > 0 do
		local nextInfo = table.remove(platformQueue, 1)
		ProcessPlatform(nextInfo)
	end

	processingPlatform = false
end

ShipAurasBridge:Connect(function(info)
	if type(info) ~= "table" then return end
	if info.action == "payoutConfirmed" then
		PlayJuiceEffect(info.amount, "Currency")
	elseif info.action == "playJuice" then
		PlayJuiceEffect(info.amount, info.currencyType)
	else
		local currentOffset = player:GetAttribute("HabitatVisualOffset") or 0
		player:SetAttribute("HabitatVisualOffset", currentOffset + (info.collected or 0))

		table.insert(platformQueue, info)
		task.spawn(ProcessQueue)
	end
end)

local LocalJuiceEvent = ReplicatedStorage:FindFirstChild("LocalJuiceEvent")
if not LocalJuiceEvent then
	LocalJuiceEvent = Instance.new("BindableEvent")
	LocalJuiceEvent.Name = "LocalJuiceEvent"
	LocalJuiceEvent.Parent = ReplicatedStorage
end
LocalJuiceEvent.Event:Connect(function(exactAmount, currencyType)
	PlayJuiceEffect(exactAmount, currencyType)
end)

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local HttpService         = game:GetService("HttpService")

local AdminConfig       = require(ReplicatedStorage.Modules.AdminConfig)
local UpgradeConfig     = require(ReplicatedStorage.Modules.UpgradeConfig)
local MutationConfig    = require(ReplicatedStorage.Modules.MutationConfig)
local GameManager       = require(ServerScriptService.GameManager)
local EpicUpgradeConfig = require(ReplicatedStorage.Modules.EpicUpgradeConfig)
local BoostManager      = require(ServerScriptService.BoostManager)
local BankConfig        = require(ReplicatedStorage.Modules.BankConfig)

local BridgeNet2      = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))
local UpdateHUDBridge = BridgeNet2.ServerBridge("UpdateHUD")
local ShipAurasBridge = BridgeNet2.ServerBridge("ShipAuras")

local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")
if not RemoteEvents:FindFirstChild("AuraDiscovered") then
	local ev = Instance.new("RemoteEvent")
	ev.Name = "AuraDiscovered"
	ev.Parent = RemoteEvents
end
local AuraDiscovered = RemoteEvents:WaitForChild("AuraDiscovered")

local playerTimers   = {}
local activeTrucks   = {}
local playerAutoMode = {}
local pendingPayouts = {}

Players.PlayerAdded:Connect(function(player)
	playerTimers[player.UserId]   = AdminConfig.ShipInterval
	activeTrucks[player.UserId]   = 0
	playerAutoMode[player.UserId] = AdminConfig.AutoDispatch
	pendingPayouts[player.UserId] = {}
end)

Players.PlayerRemoving:Connect(function(player)
	playerTimers[player.UserId]   = nil
	activeTrucks[player.UserId]   = nil
	playerAutoMode[player.UserId] = nil
	pendingPayouts[player.UserId] = nil
end)

local function SendHUDUpdate(player)
	local uid     = player.UserId
	local data    = GameManager.GetData(uid)
	local runtime = GameManager.GetRuntime(uid)
	if not data or not runtime then return end

	local storedCount = runtime.storedCubeCount or 0
	local activeMV    = runtime.activeMutatedValue or 0

	local boostMult = BoostManager.GetValueMultiplier(uid) * BoostManager.GetSpawnRateMultiplier(uid)
	local rate = math.floor(activeMV * boostMult)

	local habCfg      = UpgradeConfig.GetUpgradeConfig("habitatCapacity")
	local habitatCap  = (habCfg and habCfg.apply) and habCfg.apply(data) or AdminConfig.BaseHabitatCapacity

	local tickCfg    = UpgradeConfig.GetUpgradeConfig("passiveTickSpeed")
	local passiveInt = (tickCfg and tickCfg.apply) and tickCfg.apply(data) or AdminConfig.PassiveInterval

	local shipReduction = 0
	local shipCfg = EpicUpgradeConfig.GetUpgradeConfig("epicShipCooldown")
	if shipCfg and shipCfg.apply then
		shipReduction = shipCfg.apply(data)
	end

	-- CLAMPED TO 0.5
	local finalCooldown = math.max(0.5, AdminConfig.ShipInterval - shipReduction)

	UpdateHUDBridge:Fire(player, {
		currency        = data.currency,
		pendingAuras    = storedCount,
		habitatCapacity = habitatCap,
		rate            = rate,
		passiveInterval = passiveInt,
		totalEarned     = data.totalEarned    or 0,
		soulAuras       = data.soulAuras      or 0,
		farmEvaluation  = data.farmEvaluation or 0,
		shipCooldown    = finalCooldown,
		discoveredTiers = data.discoveredTiers or {},

		-- ✨ THE FIX: Sync achievement stats so the client instantly recognizes the shipping/production milestones!
		totalPlatformsShipped = data.totalPlatformsShipped or 0,
		totalCubesProduced    = data.totalCubesProduced or 0
	})
end

local function TryDispatch(player)
	if AdminConfig.DisableShipping then return end
	local uid     = player.UserId
	local data    = GameManager.GetData(uid)
	local runtime = GameManager.GetRuntime(uid)
	if not data or not runtime then return end
	if data.inSpecialArea then return end
	if (activeTrucks[uid] or 0) >= 50 then return end

	local totalCubes = runtime.cubeCount
	if totalCubes <= 0 then return end

	-- Check for epic shipping storage boost
	local epicStorageBoost = 0
	local epicStorageCfg = EpicUpgradeConfig.GetUpgradeConfig("epicShipStorage")
	if epicStorageCfg and epicStorageCfg.apply then 
		epicStorageBoost = epicStorageCfg.apply(data)
	end

	local toCollect  = math.min(totalCubes, AdminConfig.PlatformCapacity + epicStorageBoost)
	local cubeIds, cubes = GameManager.CollectOldestCubes(uid, toCollect)
	local collected  = #cubeIds
	if collected == 0 then return end

	local totalPayout = 0

	data.discoveredTiers = data.discoveredTiers or {}
	local newlyDiscovered = {}

	local doubleEarningsOwned = player:GetAttribute("Pass_DoubleEarnings")
	local passMultiplier = doubleEarningsOwned and BankConfig.Gamepasses.DoubleEarnings.bonus or 1.0

	-- Epic Golden Yield Config 
	local epicGoldenYield = 0
	local goldenYieldCfg = EpicUpgradeConfig.GetUpgradeConfig("epicGoldenAuraYield")
	if goldenYieldCfg and goldenYieldCfg.apply then epicGoldenYield = goldenYieldCfg.apply(data) end

	for _, cube in ipairs(cubes) do
		totalPayout = totalPayout + (MutationConfig.GetMutatedValue(cube) * passMultiplier)

		-- Handling Golden Yield additions (Assumes tracking logic for golden auras happens upon collect)
		if epicGoldenYield > 0 and (cube.isGolden or cube.tierName == "Legendary") then
			data.goldenAuras = (data.goldenAuras or 0) + epicGoldenYield
		end

		local cArea = cube.currentArea or data.currentArea or 1
		local discoverKey = cArea .. "_" .. cube.tierName

		if not data.discoveredTiers[discoverKey] then
			data.discoveredTiers[discoverKey] = true
			table.insert(newlyDiscovered, {name = cube.tierName, color = cube.color, area = cArea})
		end
	end

	activeTrucks[uid] = (activeTrucks[uid] or 0) + 1
	data.totalPlatformsShipped = (data.totalPlatformsShipped or 0) + 1

	-- ✨ THE FIX: Force hard-save the exact millisecond the platform ships!
	GameManager.SavePlayer(player)

	local dispatchId = HttpService:GenerateGUID(false)
	pendingPayouts[uid][dispatchId] = totalPayout

	SendHUDUpdate(player)

	ShipAurasBridge:Fire(player, {
		collected  = collected,
		payout     = totalPayout,
		dispatchId = dispatchId,
	})

	if #newlyDiscovered > 0 then
		AuraDiscovered:FireClient(player, newlyDiscovered)
	end
end

ShipAurasBridge:Connect(function(player, payload)
	if type(payload) ~= "table" then return end
	local uid = player.UserId
	local action = payload.action
	local value = payload.value

	if action == "manual" then
		TryDispatch(player)

		local data          = GameManager.GetData(uid)
		local shipReduction = 0
		if data then
			local shipCfg = EpicUpgradeConfig.GetUpgradeConfig("epicShipCooldown")
			if shipCfg and shipCfg.apply then shipReduction = shipCfg.apply(data) end
		end

		-- CLAMPED TO 0.5
		playerTimers[uid] = math.max(0.5, AdminConfig.ShipInterval - shipReduction)
		return
	end

	if action == "setMode" then
		playerAutoMode[uid] = (value == "auto")
		return
	end

	if action == "payout" then
		if player:GetAttribute("TutorialFrozen") then return end

		local data = GameManager.GetData(uid)
		if not data then return end

		local dispatchId   = value
		local actualPayout = pendingPayouts[uid] and pendingPayouts[uid][dispatchId]

		if not actualPayout then
			warn("[Security] " .. player.Name .. " attempted invalid platform payout.")
			return
		end

		pendingPayouts[uid][dispatchId] = nil
		activeTrucks[uid] = math.max(0, (activeTrucks[uid] or 1) - 1)

		data.currency       = (data.currency        or 0) + actualPayout
		data.totalEarned    = (data.totalEarned     or 0) + actualPayout
		data.farmEvaluation = (data.farmEvaluation  or 0) + actualPayout

		-- ✨ THE FIX: Force hard-save the exact millisecond the platform cashes out!
		GameManager.SavePlayer(player)

		SendHUDUpdate(player)

		ShipAurasBridge:Fire(player, {
			action = "payoutConfirmed",
			amount = actualPayout
		})
	end
end)

-- UpgradeManager
-- Location: ServerScriptService > UpgradeManager

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AdminConfig       = require(ReplicatedStorage.Modules.AdminConfig)
local UpgradeConfig     = require(ReplicatedStorage.Modules.UpgradeConfig)
local EpicUpgradeConfig = require(ReplicatedStorage.Modules:WaitForChild("EpicUpgradeConfig"))
local MutationConfig    = require(ReplicatedStorage.Modules.MutationConfig)
local GameManager       = require(ServerScriptService.GameManager)
local BoostManager      = require(ServerScriptService.BoostManager)

local PurchaseUpgrade     = ReplicatedStorage.RemoteEvents:WaitForChild("PurchaseUpgrade")
local UpgradeUpdated      = ReplicatedStorage.RemoteEvents:WaitForChild("UpgradeUpdated")
local PurchaseEpicUpgrade = ReplicatedStorage.RemoteEvents:WaitForChild("PurchaseEpicUpgrade")
local EpicUpgradeUpdated  = ReplicatedStorage.RemoteEvents:WaitForChild("EpicUpgradeUpdated")

-- ✨ BRIDGENET2 UPGRADE
local BridgeNet2      = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))
local UpdateHUDBridge = BridgeNet2.ServerBridge("UpdateHUD")

-- ✨ THE FIX: Replaced strict time cooldowns with a generous per-frame batch limit!
-- This allows ultra-fast holding without the server dropping your network requests.
local purchasesThisFrame = {}
game:GetService("RunService").Heartbeat:Connect(function()
	table.clear(purchasesThisFrame)
end)

-- Mapping the Index Rewards to the Upgrade Tiers to scale Bank filling
local TierFillAmounts = {
	[1] = 5,   
	[2] = 10,  
	[3] = 15,  
	[4] = 25,  
	[5] = 50,  
	[6] = 75,  
	[7] = 125, 
	[8] = 175, 
	[9] = 250, 
	[10] = 500 
}

local function GetUpgradeTierIndex(upgradeId, isEpic)
	local config = isEpic and EpicUpgradeConfig or UpgradeConfig
	for idx, tierData in ipairs(config.Tiers) do
		if tierData.upgrades[upgradeId] then
			return idx
		end
	end
	return 1
end

local function SendFullUpgradeState(player)
	local data = GameManager.GetData(player.UserId)
	if not data then return end

	local state = {}
	for tierNum, tierData in ipairs(UpgradeConfig.Tiers) do
		for upgradeId, cfg in pairs(tierData.upgrades) do
			local currentLevel = data.upgrades[upgradeId] or 0
			state[upgradeId] = {
				level    = currentLevel,
				maxLevel = cfg.maxLevel,
				-- Passed "data" in here to respect the dynamic `habitatDiscount`
				cost     = currentLevel < cfg.maxLevel and UpgradeConfig.CalculateCost(upgradeId, currentLevel, data) or 0,
				maxed    = currentLevel >= cfg.maxLevel,
			}
		end
	end

	UpgradeUpdated:FireClient(player, {
		type     = "fullState",
		upgrades = state,
		currency = data.currency,
	})

	local epicState = {}
	if data.epicUpgrades then
		for tierNum, tierData in ipairs(EpicUpgradeConfig.Tiers) do
			for upgradeId, cfg in pairs(tierData.upgrades) do
				local currentLevel = data.epicUpgrades[upgradeId] or 0
				epicState[upgradeId] = {
					level    = currentLevel,
					maxLevel = cfg.maxLevel,
					cost     = currentLevel < cfg.maxLevel and EpicUpgradeConfig.CalculateCost(upgradeId, currentLevel) or 0,
					maxed    = currentLevel >= cfg.maxLevel,
				}
			end
		end

		EpicUpgradeUpdated:FireClient(player, {
			type        = "fullState",
			upgrades    = epicState,
			goldenAuras = data.goldenAuras
		})
	end
end

Players.PlayerAdded:Connect(function(player)
	task.wait(2)
	SendFullUpgradeState(player)
end)

local function SendHUDAfterPurchase(player, data)
	local uid     = player.UserId
	local runtime = GameManager.GetRuntime(uid)
	if not runtime then return end

	local storedCount = runtime.storedCubeCount or 0
	local activeMV    = runtime.activeMutatedValue or 0

	local boostMult = BoostManager.GetValueMultiplier(uid) * BoostManager.GetSpawnRateMultiplier(uid)
	local rate = math.floor(activeMV * boostMult)

	local upgradesState = {}
	for upgradeId, level in pairs(data.upgrades or {}) do
		upgradesState[upgradeId] = { level = level }
	end

	local epicUpgradesState = {}
	for upgradeId, level in pairs(data.epicUpgrades or {}) do
		epicUpgradesState[upgradeId] = { level = level }
	end

	UpdateHUDBridge:Fire(player, {
		currency        = data.currency,
		goldenAuras     = data.goldenAuras,
		pendingAuras    = storedCount,
		habitatCapacity = UpgradeConfig.GetHabitatCapacity(data),
		rate            = rate,
		passiveInterval = UpgradeConfig.GetPassiveInterval(data),
		totalEarned     = data.totalEarned    or 0,
		soulAuras       = data.soulAuras      or 0,
		farmEvaluation  = data.farmEvaluation or 0,
		upgrades        = upgradesState, 
		epicUpgrades    = epicUpgradesState
	})
end

-- 1. Regular Upgrades
PurchaseUpgrade.OnServerEvent:Connect(function(player, upgradeId)
	local uid = player.UserId

	if type(upgradeId) ~= "string" then return end

	-- Allow up to 20 purchases per physics frame (perfect for high-speed holding)
	purchasesThisFrame[uid] = (purchasesThisFrame[uid] or 0) + 1
	if purchasesThisFrame[uid] > 20 then return end

	local cfg = UpgradeConfig.GetUpgradeConfig(upgradeId)
	if not cfg then return end

	local data = GameManager.GetData(uid)
	if not data then return end
	if not data.upgrades then data.upgrades = {} end

	local currentLevel = data.upgrades[upgradeId] or 0
	if currentLevel >= cfg.maxLevel then return end

	-- Passed "data" in here to respect the dynamic `habitatDiscount`
	local cost = UpgradeConfig.CalculateCost(upgradeId, currentLevel, data)
	if data.currency < cost then return end

	data.currency            = data.currency - cost
	data.upgrades[upgradeId] = currentLevel + 1
	local newLevel           = currentLevel + 1

	local nextCost = 0
	if newLevel < cfg.maxLevel then
		nextCost = UpgradeConfig.CalculateCost(upgradeId, newLevel, data)
	end

	GameManager.SavePlayer(player)

	UpgradeUpdated:FireClient(player, {
		type      = "purchased",
		upgradeId = upgradeId,
		level     = newLevel,
		maxLevel  = cfg.maxLevel,
		cost      = nextCost,
		maxed     = newLevel >= cfg.maxLevel,
		currency  = data.currency,
	})

	local tierIndex = GetUpgradeTierIndex(upgradeId, false)
	local fillAmount = TierFillAmounts[tierIndex] or 5
	local BankFillEvent = ServerScriptService:FindFirstChild("BankFillEvent")
	if BankFillEvent then
		BankFillEvent:Fire(uid, fillAmount)
	end

	SendHUDAfterPurchase(player, data)
end)

-- 2. Epic Upgrades (Research)
PurchaseEpicUpgrade.OnServerEvent:Connect(function(player, upgradeId)
	local uid = player.UserId

	if type(upgradeId) ~= "string" then return end

	-- Allow up to 20 purchases per physics frame (perfect for high-speed holding)
	purchasesThisFrame[uid] = (purchasesThisFrame[uid] or 0) + 1
	if purchasesThisFrame[uid] > 20 then return end

	local cfg = EpicUpgradeConfig.GetUpgradeConfig(upgradeId)
	if not cfg then return end

	local data = GameManager.GetData(uid)
	if not data then return end
	if not data.epicUpgrades then data.epicUpgrades = {} end

	local currentLevel = data.epicUpgrades[upgradeId] or 0
	if currentLevel >= cfg.maxLevel then return end

	local cost = EpicUpgradeConfig.CalculateCost(upgradeId, currentLevel)
	if (data.goldenAuras or 0) < cost then return end

	data.goldenAuras = data.goldenAuras - cost
	data.epicUpgrades[upgradeId] = currentLevel + 1
	local newLevel = currentLevel + 1

	local nextCost = 0
	if newLevel < cfg.maxLevel then
		nextCost = EpicUpgradeConfig.CalculateCost(upgradeId, newLevel)
	end

	GameManager.SavePlayer(player)

	EpicUpgradeUpdated:FireClient(player, {
		type        = "purchased",
		upgradeId   = upgradeId,
		level       = newLevel,
		maxLevel    = cfg.maxLevel,
		cost        = nextCost,
		maxed       = newLevel >= cfg.maxLevel,
		goldenAuras = data.goldenAuras,
	})

	local tierIndex = GetUpgradeTierIndex(upgradeId, true)
	local fillAmount = TierFillAmounts[tierIndex] or 25
	local BankFillEvent = ServerScriptService:FindFirstChild("BankFillEvent")
	if BankFillEvent then
		BankFillEvent:Fire(uid, fillAmount)
	end

	SendHUDAfterPurchase(player, data)
end)

Players.PlayerRemoving:Connect(function(player)
	purchasesThisFrame[player.UserId] = nil
end)

return {}

-- EpicUpgradeManager
-- Location: ServerScriptService > EpicUpgradeManager

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local EpicUpgradeConfig = require(ReplicatedStorage.Modules.EpicUpgradeConfig)
local GameManager       = require(ServerScriptService.GameManager)

local PurchaseEpicUpgrade = ReplicatedStorage.RemoteEvents:WaitForChild("PurchaseEpicUpgrade")
local EpicUpgradeUpdated  = ReplicatedStorage.RemoteEvents:WaitForChild("EpicUpgradeUpdated")

-- ✨ BRIDGENET2 UPGRADE
local BridgeNet2      = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))
local UpdateHUDBridge = BridgeNet2.ServerBridge("UpdateHUD")

PurchaseEpicUpgrade.OnServerEvent:Connect(function(player, upgradeId)
	local uid, data = player.UserId, GameManager.GetData(player.UserId)
	if not data then return end
	local cfg = EpicUpgradeConfig.GetUpgradeConfig(upgradeId)
	if not cfg then return end
	if not data.epicUpgrades then data.epicUpgrades = {} end

	local lv = data.epicUpgrades[upgradeId] or 0
	if lv >= cfg.maxLevel then return end

	local cost = EpicUpgradeConfig.CalculateCost(upgradeId, lv)
	if (data.goldenAuras or 0) < cost then return end

	data.goldenAuras = data.goldenAuras - cost
	data.epicUpgrades[upgradeId] = lv + 1

	local newLv = lv + 1
	local maxed = newLv >= cfg.maxLevel

	EpicUpgradeUpdated:FireClient(player, {
		type = "purchased", 
		upgradeId = upgradeId, 
		level = newLv,
		maxLevel = cfg.maxLevel, 
		-- ✨ FIX: Used `newLv` instead of `lv` to accurately show the NEXT cost!
		cost = maxed and 0 or EpicUpgradeConfig.CalculateCost(upgradeId, newLv), 
		maxed = maxed,
	})

	UpdateHUDBridge:Fire(player, { goldenAuras = data.goldenAuras })
	GameManager.SavePlayer(player)
end)

local function SendFullState(player)
	local data = GameManager.GetData(player.UserId)
	if not data then return end
	local ep = data.epicUpgrades or {}; local payload = {}

	for _, tierData in ipairs(EpicUpgradeConfig.Tiers) do
		for id, cfg in pairs(tierData.upgrades) do
			local lv = ep[id] or 0
			local maxed = lv >= cfg.maxLevel
			local cost = maxed and 0 or EpicUpgradeConfig.CalculateCost(id, lv)

			payload[id] = {
				level = lv, 
				maxLevel = cfg.maxLevel, 
				cost = cost,
				maxed = maxed
			}
		end
	end

	EpicUpgradeUpdated:FireClient(player, { type="fullState", upgrades=payload, goldenAuras=data.goldenAuras or 0 })
end

Players.PlayerAdded:Connect(function(player) task.wait(2); SendFullState(player) end)

local EpicUpgradeManager = {}

function EpicUpgradeManager.GetBonus(uid, upgradeId)
	local cfg = EpicUpgradeConfig.GetUpgradeConfig(upgradeId)
	if not cfg then return 0 end
	local data = GameManager.GetData(uid)
	return cfg.apply(data or { epicUpgrades = {} })
end

function EpicUpgradeManager.GetAllBonuses(uid)
	local data = GameManager.GetData(uid) or { epicUpgrades = {} }
	local b = {}
	for _, tierData in ipairs(EpicUpgradeConfig.Tiers) do
		for id, cfg in pairs(tierData.upgrades) do
			b[id] = cfg.apply(data)
		end
	end
	return b
end

function EpicUpgradeManager.ResendState(player) SendFullState(player) end

return EpicUpgradeManager

-- UIController
-- Location: StarterPlayer > StarterPlayerScripts > UIController

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local Debris            = game:GetService("Debris")
local UserInputService  = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")

local AdminConfig       = require(ReplicatedStorage.Modules:WaitForChild("AdminConfig"))
local Formatter         = require(ReplicatedStorage.Modules:WaitForChild("NumberFormatter"))
local UITheme           = require(ReplicatedStorage.Modules:WaitForChild("UITheme"))

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

local GoldenAurasLabel    = mainHUD:FindFirstChild("GoldenAurasLabel", true)
local AurmerLabel         = mainHUD:FindFirstChild("AurmerLabel", true)

-- Adjust these to nudge the chaining effect left/right/up/down
local BANK_POPUP_OFFSET_X = 15 
local BANK_POPUP_OFFSET_Y = 45

local function AddPaddingToLabel(label)
	if label and not label:FindFirstChildOfClass("UIPadding") then
		local pad = Instance.new("UIPadding", label)
		pad.PaddingLeft = UDim.new(0, 35)
	end
end

AddPaddingToLabel(GoldenAurasLabel)
AddPaddingToLabel(AurmerLabel)

if GoldenAurasLabel then
	local scale = GoldenAurasLabel:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", GoldenAurasLabel)
	scale.Scale = 1.15
end

local displayedCurrency   = 0
local liveGoldenAuras     = 0
local liveAurmers         = 0
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

local localLastPiggyBank  = 0
local isFirstBankLoad     = true

-- Variables for PiggyBank chaining effect
local accumulatedBankDiff = 0
local activeBankPopup = nil
local activeBankTweens = {}

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

local manualTimerLabel = Instance.new("TextLabel")
manualTimerLabel.Name = "ManualTimerLabel"
manualTimerLabel.Size = UDim2.new(0, 50, 1, 0)
manualTimerLabel.AnchorPoint = Vector2.new(1, 0)
manualTimerLabel.Position = UDim2.new(0, -10, 0, 0)
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

local function UpdateWalletVisual()
	local pendingCash = player:GetAttribute("LocalPendingPayout") or 0
	curr.Text = "Currency: $" .. FormatCurrency(math.max(0, displayedCurrency - pendingCash))
end

local function UpdateAuraVisual()
	if not GoldenAurasLabel then return end
	local pendingAurasVis = player:GetAttribute("LocalPendingAuras") or 0
	GoldenAurasLabel.Text = FormatNumber(math.max(0, liveGoldenAuras - pendingAurasVis))
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

-- ✨ THE FIX: We bind the Bank Popup perfectly to the Attribute instead of UpdateHUD
-- This guarantees it never drops an update regardless of which server script modified it!
player:GetAttributeChangedSignal("LivePiggyBank"):Connect(function()
	local currentBank = player:GetAttribute("LivePiggyBank") or 0
	local diff = currentBank - localLastPiggyBank

	if isFirstBankLoad then
		diff = 0
		isFirstBankLoad = false
	end

	localLastPiggyBank = currentBank

	if diff > 0 and GoldenAurasLabel then
		accumulatedBankDiff = accumulatedBankDiff + diff

		local targetPos = GoldenAurasLabel.AbsolutePosition
		local targetSize = GoldenAurasLabel.AbsoluteSize

		local startX = targetPos.X + (targetSize.X / 2) + BANK_POPUP_OFFSET_X
		local startY = targetPos.Y + targetSize.Y + BANK_POPUP_OFFSET_Y 

		if not activeBankPopup or not activeBankPopup.Parent then
			activeBankPopup = Instance.new("TextLabel")
			activeBankPopup.Font = Enum.Font.FredokaOne
			activeBankPopup.TextScaled = true
			activeBankPopup.TextColor3 = Color3.fromRGB(255, 210, 20)
			activeBankPopup.BackgroundTransparency = 1
			activeBankPopup.Size = UDim2.new(0, 120, 0, 20)
			activeBankPopup.AnchorPoint = Vector2.new(0.5, 0)

			local stroke = Instance.new("UIStroke", activeBankPopup)
			stroke.Color = Color3.fromRGB(80, 40, 0)
			stroke.Thickness = 3

			local effectGui = playerGui:FindFirstChild("JuiceGui_PiggyBank")
			if not effectGui then
				effectGui = Instance.new("ScreenGui")
				effectGui.Name = "JuiceGui_PiggyBank"
				effectGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
				effectGui.DisplayOrder = 100 
				effectGui.IgnoreGuiInset = true -- Prevents the Roblox topbar from messing up positioning
				effectGui.Parent = playerGui
			end
			activeBankPopup.Parent = effectGui

			local scale = Instance.new("UIScale", activeBankPopup)
			scale.Scale = 1
		end

		for _, tw in ipairs(activeBankTweens) do
			tw:Cancel()
		end
		activeBankTweens = {}

		activeBankPopup.Text = "+" .. Formatter.Format(accumulatedBankDiff) .. " Banked!"
		activeBankPopup.Position = UDim2.new(0, startX, 0, startY)
		activeBankPopup.TextTransparency = 0

		local stroke = activeBankPopup:FindFirstChildOfClass("UIStroke")
		if stroke then stroke.Transparency = 0 end

		local scale = activeBankPopup:FindFirstChildOfClass("UIScale")
		if scale then
			scale.Scale = 1.25
			local popTween = TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {Scale = 1})
			popTween:Play()
		end

		local currentUpdateId = tick()
		activeBankPopup:SetAttribute("UpdateId", currentUpdateId)

		task.delay(0.8, function()
			if activeBankPopup and activeBankPopup:GetAttribute("UpdateId") == currentUpdateId then

				local driftTween = TweenService:Create(activeBankPopup, TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
					Position = UDim2.new(0, startX, 0, startY + 25),
					TextTransparency = 1
				})

				table.insert(activeBankTweens, driftTween)

				if stroke then
					local strokeTween = TweenService:Create(stroke, TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
						Transparency = 1
					})
					table.insert(activeBankTweens, strokeTween)
					strokeTween:Play()
				end

				driftTween:Play()

				driftTween.Completed:Connect(function(playbackState)
					if playbackState == Enum.PlaybackState.Completed then
						if activeBankPopup and activeBankPopup:GetAttribute("UpdateId") == currentUpdateId then
							accumulatedBankDiff = 0
							activeBankPopup:Destroy()
							activeBankPopup = nil
						end
					end
				end)
			end
		end)
	end
end)

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
	if isAutoMode then
		manualTimerLabel.Visible = false
		return
	end

	local progressContainer = sendButton:FindFirstChild("CooldownProgress")
	local fillPart          = progressContainer and progressContainer:FindFirstChild("Fill")
	local textTarget        = sendButton:FindFirstChildOfClass("TextLabel") or sendButton

	local uiStroke = sendButton:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke", sendButton)
	uiStroke.Thickness = 1.5

	if not fillPart then return end

	sendButton.ClipsDescendants = false
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

	if timeLeft > 0 then
		sendButton.BackgroundColor3    = Color3.fromRGB(0, 160, 255)
		uiStroke.Color                 = Color3.fromRGB(0, 220, 255)
		fillPart.BackgroundColor3      = Color3.fromRGB(0, 0, 0)
		fillPart.BackgroundTransparency = 0.55

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

				if pendingAuras <= 0 then
					sendButton.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
					uiStroke.Color = Color3.fromRGB(50, 50, 50)
				else
					sendButton.BackgroundColor3 = Color3.fromRGB(0, 160, 255)
					uiStroke.Color = Color3.fromRGB(0, 220, 255)
				end
			end
		end)
	else
		isShipOnCooldown = false
		textTarget.Text  = ""
		fillPart.Size    = UDim2.new(1, 0, 0, 0)
		manualTimerLabel.Visible = false

		if pendingAuras <= 0 then
			sendButton.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
			uiStroke.Color = Color3.fromRGB(50, 50, 50)
		else
			sendButton.BackgroundColor3 = Color3.fromRGB(0, 160, 255)
			uiStroke.Color = Color3.fromRGB(0, 220, 255)
		end
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
		sendButton.Visible = true 
		SyncManualCooldownVisuals()
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

if AdminConfig.DisableShipping then
	isAutoMode         = false
	sendButton.Visible = false
	modeToggle.Visible = false
end

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

	if stats.aurmers ~= nil then
		liveAurmers = stats.aurmers
		player:SetAttribute("LiveAurmers", liveAurmers)
		if AurmerLabel then
			AurmerLabel.Text = FormatNumber(liveAurmers)
		end
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
	if GoldenAurasLabel then UITheme.ApplyFlair(GoldenAurasLabel, "GoldStroke") end
	if AurmerLabel then UITheme.ApplyFlair(AurmerLabel, "AurmerStroke") end
end

task.wait(2)
RefreshLook()

-- ✨ FORCE TELEPORT TO SPAWN ON JOIN
local function ForceSpawnTeleport()
	local char = player.Character or player.CharacterAdded:Wait()
	local spawnLoc = workspace:WaitForChild("SpawnLocation", 10)

	if char and spawnLoc then
		-- Wait a fraction of a second to ensure physics and character parts have fully loaded
		task.wait(0.1) 
		char:PivotTo(spawnLoc.CFrame * CFrame.new(0, (spawnLoc.Size.Y / 2) + 3, 0))
	end
end

-- Fire the spawn teleport function immediately
task.spawn(ForceSpawnTeleport)

-- ClickHandler.lua
-- Location: StarterPlayer > StarterPlayerScripts > ClickHandler

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")

local AdminConfig = require(ReplicatedStorage.Modules.AdminConfig)
local UITheme = require(ReplicatedStorage.Modules.UITheme)
local AreaRegistry = require(ReplicatedStorage.Modules.AreaRegistry)
local NumberFormatter = require(ReplicatedStorage.Modules.NumberFormatter)

local PoolManager = require(ReplicatedStorage.Modules:WaitForChild("PoolManager"))

local BridgeNet2             = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))
local UpdateHUDBridge        = BridgeNet2.ClientBridge("UpdateHUD")
local ProduceAuraBridge      = BridgeNet2.ClientBridge("ProduceAura")
local AuraSpawnedBridge      = BridgeNet2.ClientBridge("AuraSpawned")
local UpdateHatcheryBridge   = BridgeNet2.ClientBridge("UpdateHatchery")
local CubeMutatedBatchBridge = BridgeNet2.ClientBridge("CubeMutatedBatch")
local CubeSmushedBridge      = BridgeNet2.ClientBridge("CubeSmushed")
local CubeStoredBridge       = BridgeNet2.ClientBridge("CubeStored")

local ForceStopHold = ReplicatedStorage.RemoteEvents:WaitForChild("ForceStopHold")
local HabitatFull = ReplicatedStorage.RemoteEvents:WaitForChild("HabitatFull")
local UpdateMultiplier = ReplicatedStorage:WaitForChild("UpdateMultiplier")
local HabitatFullEvent = ReplicatedStorage:WaitForChild("HabitatFullEvent")
local AreaChanged = ReplicatedStorage.RemoteEvents:WaitForChild("AreaChanged")
local PrestigeComplete = ReplicatedStorage.RemoteEvents:WaitForChild("PrestigeComplete")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local holding = false
local isAreaLoading = false 

local currentFireRate = AdminConfig.FireRate
local globalBoostMultiplier = 1
local currentPassiveInterval = AdminConfig.PassiveInterval

local holdStart = nil
local hatcheryEmpty = false
local habitatFull = false

local ClickButton = playerGui:WaitForChild("MainHUD"):WaitForChild("ClickButton")
local HatcheryBar = playerGui:WaitForChild("MainHUD"):WaitForChild("HatcheryBar")
local HatcheryFill = HatcheryBar:WaitForChild("Fill")
local HatcheryLabel = HatcheryBar:WaitForChild("Label")

local ModeToggle = playerGui:WaitForChild("MainHUD"):WaitForChild("ModeToggle")
local SendButton = playerGui:WaitForChild("MainHUD"):WaitForChild("SendButton")

CollectionService:AddTag(ClickButton, "Tutorial_ClickButton")
CollectionService:AddTag(ModeToggle, "Tutorial_ToggleShipBtn")
CollectionService:AddTag(SendButton, "Tutorial_SendShipBtn")

local clickScale = ClickButton:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", ClickButton)

local ringFrame = ClickButton:FindFirstChild("ActionRing")
if not ringFrame then
	ringFrame = Instance.new("Frame")
	ringFrame.Name = "ActionRing"
	ringFrame.Size = UDim2.new(1, 0, 1, 0)
	ringFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	ringFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	ringFrame.BackgroundTransparency = 1
	ringFrame.ZIndex = ClickButton.ZIndex - 1

	local btnCorner = ClickButton:FindFirstChildOfClass("UICorner")
	if btnCorner then btnCorner:Clone().Parent = ringFrame end
	ringFrame.Parent = ClickButton
end

local clickStroke = ringFrame:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke", ringFrame)
clickStroke.Color = Color3.fromRGB(255, 215, 0)
clickStroke.Thickness = 0
clickStroke.Transparency = 1

local basePos = ClickButton.Position
local tiltSide = 1

local Camera = workspace.CurrentCamera
local defaultFOV = 70
local lastMilestone = 1

local MilestoneData = AdminConfig.MilestoneData

local playerMultSpeed = 1.0
local playerMaxTier = 5

local lastTierIndex = 1

local latestPendingAuras = 0
local latestHabitatCapacity = 50

local function FormatNumber(n)
	return NumberFormatter.Format(n)
end

local VFXFolder = ReplicatedStorage:FindFirstChild("VFX")
local cubeDataMap = {}

local TierScale = {
	Common    = 1.0,
	Uncommon  = 1.15,
	Rare      = 1.3,
	Epic      = 1.5,
	Legendary = 1.75,
}

local function GetRootPart(instance)
	if instance:IsA("Model") then return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart") end
	return instance
end

local function ApplyHeavyPhysics(instance)
	local heavyProps = PhysicalProperties.new(100, 2.0, 0, 100, 100)
	if instance:IsA("BasePart") then instance.CustomPhysicalProperties = heavyProps
	elseif instance:IsA("Model") then
		for _, part in ipairs(instance:GetDescendants()) do
			if part:IsA("BasePart") then part.CustomPhysicalProperties = heavyProps end
		end
	end
end

local function SpawnAuraInstance(tierName, color, glow, position, currentArea)
	currentArea = currentArea or 1

	local auraModel = nil
	local isCustom = false
	local success = false
	local attempts = 0

	while not success and attempts < 3 do
		attempts += 1
		auraModel = PoolManager.GetAura(currentArea, tierName)

		if not auraModel then
			warn("PoolManager returned nil for Area: " .. tostring(currentArea) .. ", Tier: " .. tostring(tierName))
			return nil, false
		end

		success = pcall(function()
			auraModel.Parent = workspace
		end)

		if not success then
			warn("[ClickHandler] Pool returned a destroyed instance. Retrying...")
		end
	end

	if not success or not auraModel then 
		return nil, false 
	end

	if auraModel:IsA("Model") then
		auraModel:PivotTo(CFrame.new(position))
		local primary = auraModel.PrimaryPart or auraModel:FindFirstChildWhichIsA("BasePart")

		if primary then
			primary.Anchored = false
			primary.CanCollide = true
			primary.CollisionGroup = "Auras"
			primary.CastShadow = false
		end

		for _, desc in ipairs(auraModel:GetDescendants()) do
			if desc:IsA("BasePart") and desc ~= primary then
				desc.CanCollide = false
				desc.CanTouch = false
				desc.CanQuery = false
				desc.CastShadow = false
			end
		end

	elseif auraModel:IsA("BasePart") then
		auraModel.Position = position
		auraModel.Anchored = false
		auraModel.CanCollide = true
		auraModel.CollisionGroup = "Auras"
		auraModel.CastShadow = false
		auraModel.Color = color
		if glow then
			local light = auraModel:FindFirstChildOfClass("PointLight")
			if not light then light = Instance.new("PointLight"); light.Parent = auraModel end
			light.Brightness = 3; light.Range = 8; light.Color = color
		end
	end

	for _, desc in ipairs(auraModel:GetDescendants()) do
		if desc:IsA("ParticleEmitter") or desc:IsA("Trail") then
			desc.Enabled = true
		end
	end

	ApplyHeavyPhysics(auraModel)
	return auraModel, true
end

local function ScaleAura(instance, tierName, animated, fromTierName)
	local targetScale = TierScale[tierName] or 1.0
	local fromScale = fromTierName and (TierScale[fromTierName] or 1.0) or nil

	if instance:IsA("Model") then
		if animated then
			local scaleProxy = Instance.new("NumberValue")
			scaleProxy.Value = fromScale or 1.0
			local scaleTween = TweenService:Create(scaleProxy, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Value = targetScale })
			local conn
			conn = scaleProxy.Changed:Connect(function(val)
				if instance and instance.Parent then pcall(function() instance:ScaleTo(val) end) else conn:Disconnect() end
			end)
			scaleTween:Play()
			scaleTween.Completed:Connect(function() scaleProxy:Destroy(); if conn then conn:Disconnect() end end)
		else
			pcall(function() instance:ScaleTo(targetScale) end)
		end
	elseif instance:IsA("BasePart") then
		local baseSize = 1.5
		local targetSize = Vector3.new(1, 1, 1) * (baseSize * targetScale)
		if animated then
			if fromScale then instance.Size = Vector3.new(1, 1, 1) * (baseSize * fromScale) end
			TweenService:Create(instance, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = targetSize }):Play()
		else
			instance.Size = targetSize
		end
	end
end

local function PlayVFX(effectName, position, duration)
	if not VFXFolder then return end
	local template = VFXFolder:FindFirstChild(effectName)
	if not template then return end
	local vfx = template:Clone()

	if vfx:IsA("Model") then vfx:PivotTo(CFrame.new(position))
	elseif vfx:IsA("BasePart") then vfx.Position = position end

	for _, obj in ipairs(vfx:GetDescendants()) do
		if obj:IsA("BasePart") then
			obj.Anchored = true; obj.Transparency = 1; obj.CanCollide = false; obj.CastShadow = false
		end
	end
	if vfx:IsA("BasePart") then
		vfx.Anchored = true; vfx.Transparency = 1; vfx.CanCollide = false; vfx.CastShadow = false
	end
	vfx.Parent = workspace

	for _, emitter in ipairs(vfx:GetDescendants()) do
		if emitter:IsA("ParticleEmitter") then
			emitter.Enabled = true; emitter:Emit(emitter:GetAttribute("BurstCount") or 15)
		end
	end
	task.delay((duration or 1.0) * 0.5, function()
		if vfx and vfx.Parent then
			for _, emitter in ipairs(vfx:GetDescendants()) do
				if emitter:IsA("ParticleEmitter") then emitter.Enabled = false end
			end
		end
	end)
	Debris:AddItem(vfx, duration or 1.5)
end

local function GetCurrentMultiplier()
	if not holding or not holdStart then return 1.0, 1 end
	local holdTime = tick() - holdStart
	local effectiveTime = holdTime * playerMultSpeed

	local currentTier = 1; local nextTier = 1
	for i = 1, playerMaxTier do
		if effectiveTime >= MilestoneData[i].time then
			currentTier = i; nextTier = math.min(i + 1, playerMaxTier)
		end
	end

	if currentTier == playerMaxTier then return MilestoneData[currentTier].mult, currentTier end

	local timePassedInTier = effectiveTime - MilestoneData[currentTier].time
	local timeNeededForNext = MilestoneData[nextTier].time - MilestoneData[currentTier].time
	local progressRatio = timePassedInTier / timeNeededForNext

	local currentMult = MilestoneData[currentTier].mult
	local nextMult = MilestoneData[nextTier].mult
	local smoothMult = currentMult + ((nextMult - currentMult) * progressRatio)

	return smoothMult, currentTier
end

local function PlayMilestoneSound(soundValue)
	if not soundValue or soundValue == "" then return end
	local sfxToPlay = nil
	if string.find(soundValue, "rbxassetid://") then
		sfxToPlay = Instance.new("Sound"); sfxToPlay.SoundId = soundValue; sfxToPlay.Volume = 0.6
	else
		local sfxFolder = ReplicatedStorage:FindFirstChild("SFX") or ReplicatedStorage:FindFirstChild("Sounds")
		if sfxFolder then
			local foundSound = sfxFolder:FindFirstChild(soundValue)
			if foundSound then sfxToPlay = foundSound:Clone(); sfxToPlay.Volume = 0.6 end
		end
	end
	if sfxToPlay then
		sfxToPlay.Parent = game:GetService("SoundService"); sfxToPlay:Play()
		Debris:AddItem(sfxToPlay, sfxToPlay.TimeLength > 0 and sfxToPlay.TimeLength or 3)
	end
end

local function SpawnMilestonePopup(multFloor)
	local data = MilestoneData[multFloor]
	if not data then return end

	PlayMilestoneSound(data.sound)

	local pop = Instance.new("TextLabel")
	pop.Text = data.name .. " (" .. string.format("%.1f", data.mult) .. "x)"
	pop.Font = Enum.Font.FredokaOne; pop.TextScaled = true; pop.TextColor3 = data.color
	pop.BackgroundTransparency = 1; pop.AnchorPoint = Vector2.new(0.5, 0.5)

	pop.Position = UDim2.new(
		ClickButton.Position.X.Scale, ClickButton.Position.X.Offset, 
		ClickButton.Position.Y.Scale - 0.15, ClickButton.Position.Y.Offset
	)
	pop.Parent = ClickButton.Parent

	local stroke = Instance.new("UIStroke", pop); stroke.Thickness = 3; stroke.Color = Color3.fromRGB(0, 0, 0)
	pop.Size = UDim2.new(0.1, 0, 0.02, 0) 

	TweenService:Create(pop, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0.35, 0, 0.08, 0),
		Position = UDim2.new(pop.Position.X.Scale, pop.Position.X.Offset, ClickButton.Position.Y.Scale - 0.25, ClickButton.Position.Y.Offset)
	}):Play()

	task.delay(0.6, function()
		TweenService:Create(pop, TweenInfo.new(0.3), {TextTransparency = 1}):Play()
		TweenService:Create(stroke, TweenInfo.new(0.3), {Transparency = 1}):Play()
		task.delay(0.3, function() pop:Destroy() end)
	end)
end

local function UpdateButtonVisual()
	local col; local mult = 1; local currentTierIndex = 1
	if habitatFull then col = Color3.fromRGB(180, 60, 60)
	elseif not holding then col = Color3.fromRGB(255, 0, 0)
	else
		mult, currentTierIndex = GetCurrentMultiplier()
		col = MilestoneData[currentTierIndex].color
		UpdateMultiplier:Fire(mult)
	end

	local targetFOV = defaultFOV + (mult * 1.2)
	if not holding then targetFOV = defaultFOV end
	TweenService:Create(Camera, TweenInfo.new(0.3, Enum.EasingStyle.Sine), {FieldOfView = targetFOV}):Play()

	if holding then
		if currentTierIndex > lastTierIndex then
			if currentTierIndex > 1 then SpawnMilestonePopup(currentTierIndex) end
			lastTierIndex = currentTierIndex
		end
	else lastTierIndex = 1 end

	TweenService:Create(ClickButton, TweenInfo.new(0.2), { BackgroundColor3 = col }):Play()

	if holding and not habitatFull then
		tiltSide = tiltSide * -1 
		if mult >= 5.0 then 
			TweenService:Create(ClickButton, TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true), { Rotation = 8 * tiltSide }):Play()
			clickStroke.Thickness = 12; clickStroke.Transparency = 0
			TweenService:Create(clickStroke, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Thickness = 0, Transparency = 1}):Play()
		else
			TweenService:Create(ClickButton, TweenInfo.new(0.08, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, true), { Rotation = 3 * tiltSide }):Play()
		end
	elseif not holding then
		TweenService:Create(ClickButton, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Rotation = 0}):Play()
		TweenService:Create(clickScale, TweenInfo.new(0.15), {Scale = 1}):Play()
	end
end

local function UpdateHatcheryBar(current, max)
	local ratio = math.clamp(current / max, 0, 1)
	TweenService:Create(HatcheryFill, TweenInfo.new(0.1), { Size = UDim2.new(ratio, 0, 1, 0) }):Play()

	local color = Color3.fromRGB(255, 60, 60)
	if ratio > 0.5 then color = Color3.fromRGB(80, 220, 80)
	elseif ratio > 0.25 then color = Color3.fromRGB(255, 200, 0) end

	TweenService:Create(HatcheryFill, TweenInfo.new(0.1), { BackgroundColor3 = color }):Play()
	HatcheryLabel.Text = "Hatchery: " .. math.floor(current) .. " / " .. max
	hatcheryEmpty = (current <= 0)
end

local function FlashEmpty()
	TweenService:Create(HatcheryFill, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(255, 255, 255) }):Play()
	task.delay(0.1, function() TweenService:Create(HatcheryFill, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(255, 60, 60) }):Play() end)
end

local function ShowTierPopup(position, tierName, tierColor)
	local anchor = Instance.new("Part"); anchor.Size = Vector3.new(0.1, 0.1, 0.1); anchor.Anchored = true; anchor.Transparency = 1; anchor.CanCollide = false
	anchor.Position = position + Vector3.new(0, 3, 0); anchor.Parent = workspace

	local bb = Instance.new("BillboardGui"); bb.Size = UDim2.new(0, 120, 0, 40); bb.StudsOffset = Vector3.new(0, 2, 0)
	bb.AlwaysOnTop = false; bb.Adornee = anchor; bb.Parent = anchor

	local label = Instance.new("TextLabel"); label.Size = UDim2.new(1, 0, 1, 0); label.BackgroundTransparency = 1
	label.Text = tierName:upper(); label.TextColor3 = tierColor; label.TextScaled = true
	label.Font = Enum.Font.GothamBold; label.TextStrokeTransparency = 0.3; label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0); label.Parent = bb

	TweenService:Create(bb, TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffset = Vector3.new(0, 6, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(anchor, 2)
end

local function ShowCubeValue(position, value, color)
	local anchor = Instance.new("Part"); anchor.Size = Vector3.new(0.1, 0.1, 0.1); anchor.Anchored = true; anchor.Transparency = 1; anchor.CanCollide = false
	anchor.Position = position + Vector3.new(math.random(-1, 1), 2, math.random(-1, 1)); anchor.Parent = workspace

	local bb = Instance.new("BillboardGui"); bb.Size = UDim2.new(0, 80, 0, 25); bb.StudsOffset = Vector3.new(0, 0, 0)
	bb.AlwaysOnTop = false; bb.Adornee = anchor; bb.Parent = anchor

	local label = Instance.new("TextLabel"); label.Size = UDim2.new(1, 0, 1, 0); label.BackgroundTransparency = 1
	label.Text = "Value: $" .. FormatNumber(value); label.TextColor3 = Color3.fromRGB(255, 255, 255); label.TextScaled = true
	label.Font = Enum.Font.Gotham; label.TextStrokeTransparency = 0.4; label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0); label.Parent = bb

	TweenService:Create(bb, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffset = Vector3.new(0, 4, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(anchor, 1.5)
end

local function AttachPermanentRateLabel(auraInstance, baseValue, auraColor)
	local rootPart = GetRootPart(auraInstance)
	if not rootPart then return end

	local bb = Instance.new("BillboardGui")
	bb.Name = "PermanentRateLabel"
	bb.Size = UDim2.new(0, 90, 0, 25)
	bb.StudsOffset = Vector3.new(0, 0.5, 0)
	bb.AlwaysOnTop = false
	bb.MaxDistance = 35 
	bb.Adornee = rootPart

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1

	local ratePerSec = baseValue / currentPassiveInterval
	label.Text = "+$" .. FormatNumber(ratePerSec) .. "/sec"

	label.TextColor3 = auraColor or Color3.fromRGB(100, 255, 100)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextTransparency = 0.2
	label.TextStrokeTransparency = 0.6
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.Parent = bb

	bb.Parent = rootPart
	return label
end

local function RefreshAllRateLabels()
	for id, data in pairs(cubeDataMap) do
		if data.rateLabel and data.baseValue and not data.isStored then
			local ratePerSec = (data.baseValue * globalBoostMultiplier) / currentPassiveInterval
			data.rateLabel.Text = "+$" .. FormatNumber(ratePerSec) .. "/sec"
		end
	end
end

local AuraHolder = workspace:WaitForChild("AuraHolder")
local HabitatHolder = workspace:WaitForChild("HabitatHolder")

local function UpdateHabitatBar(actualPending, max)
	local offset = player:GetAttribute("HabitatVisualOffset") or 0
	local current = actualPending + offset

	local habitatModel = HabitatHolder:FindFirstChildWhichIsA("Model")
	if not habitatModel then return end

	local habitatGui = habitatModel:FindFirstChild("HabitatGui", true)
	if not habitatGui then return end

	local bg = habitatGui:FindFirstChild("BarBackground")
	if not bg then return end

	local fill = bg:FindFirstChild("BarFill")
	local textLabel = bg:FindFirstChild("CountLabel") or bg:FindFirstChild("AmountLabel")

	if fill and max > 0 then
		local ratio = math.clamp(current / max, 0, 1)

		TweenService:Create(fill, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(ratio, 0, 1, 0)
		}):Play()

		local targetColor = Color3.fromRGB(80, 220, 80)
		if ratio >= 1 then targetColor = Color3.fromRGB(255, 60, 60)
		elseif ratio >= 0.8 then targetColor = Color3.fromRGB(255, 200, 0) end

		TweenService:Create(fill, TweenInfo.new(0.2), {BackgroundColor3 = targetColor}):Play()

		if textLabel then
			if current >= max then
				textLabel.Text = "FULL!"
				textLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
			else
				textLabel.Text = math.floor(current) .. " / " .. max
				textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
			end
		end
	end
end

player:GetAttributeChangedSignal("HabitatVisualOffset"):Connect(function()
	UpdateHabitatBar(latestPendingAuras, latestHabitatCapacity)
end)

local function GetAuraCubeFromHit(hit)
	if hit.Name == "ExplodedGoldenAura" or hit.Name == "DynamicPiggyBankAura" then return nil end
	if hit:GetAttribute("AuraCube") then return hit end

	local p = hit.Parent; if p and p:GetAttribute("AuraCube") then return p end
	local m = hit:FindFirstAncestorWhichIsA("Model"); if m and m:GetAttribute("AuraCube") then return m end
	return nil
end

local function HookAuraModel(model)
	task.delay(0.1, function()
		local smush = model:FindFirstChild("SmushTrigger", true)
		if smush then
			smush.Touched:Connect(function(hit)
				local auraObj = GetAuraCubeFromHit(hit)
				if auraObj then
					for id, data in pairs(cubeDataMap) do
						if data.instance == auraObj then
							if data.isStored then return end
							CubeSmushedBridge:Fire(id)
							local root = GetRootPart(auraObj)
							local pos = (root and root.Position) or hit.Position
							PlayVFX("Spawn", pos, 0.5)

							pcall(function() PoolManager.ReturnAura(data.instance) end)
							cubeDataMap[id] = nil
							break
						end
					end
				end
			end)
		end

		for _, conveyer in ipairs(model:GetDescendants()) do
			if (conveyer.Name == "ConveyerPath" or conveyer.Name == "ConveyerPathCorner") and conveyer:IsA("BasePart") then
				local forwardBeam = conveyer:FindFirstChild("Foward") or conveyer:FindFirstChild("Forward")
				local backwardBeam = conveyer:FindFirstChild("Backward")

				if forwardBeam then forwardBeam.Enabled = not habitatFull end
				if backwardBeam then backwardBeam.Enabled = habitatFull end

				if not conveyer:GetAttribute("OriginalVelocity") then
					conveyer:SetAttribute("OriginalVelocity", conveyer.AssemblyLinearVelocity)
				end

				local origVel = conveyer:GetAttribute("OriginalVelocity")

				if habitatFull then 
					conveyer.AssemblyLinearVelocity = origVel * -2
				else 
					conveyer.AssemblyLinearVelocity = origVel 
				end
			end
		end
	end)
end

local function HookHabitatModel(model)
	task.delay(0.1, function()
		local storage = model:FindFirstChild("StorageTrigger", true)
		if storage then
			storage.Touched:Connect(function(hit)
				-- Handle custom Golden/Elite physical auras pushed into storage
				if hit:HasTag("PhysicsAura") or (hit.Parent and hit.Parent:HasTag("PhysicsAura")) then
					local physicsPart = hit:HasTag("PhysicsAura") and hit or hit.Parent
					local claimEvent = ReplicatedStorage:FindFirstChild("RemoteEvents") and ReplicatedStorage.RemoteEvents:FindFirstChild("ClaimPhysicsAura")
					if claimEvent then
						claimEvent:FireServer(physicsPart)
					end
					return
				end

				local auraObj = GetAuraCubeFromHit(hit)
				if auraObj then
					for id, data in pairs(cubeDataMap) do
						if data.instance == auraObj and not data.isStored then
							data.isStored = true

							if data.rateLabel and data.rateLabel.Parent and data.rateLabel.Parent:IsA("BillboardGui") then 
								data.rateLabel.Parent.Enabled = false 
							end

							local root = GetRootPart(auraObj)
							if root then
								local dropOffset = Vector3.new(-10, 4, math.random(-4, 4))
								auraObj:PivotTo(CFrame.new(storage.Position + dropOffset))
								root.AssemblyLinearVelocity = Vector3.new(0, -10, 0)
								root.AssemblyAngularVelocity = Vector3.new(math.random(-5, 5), math.random(-5, 5), math.random(-5, 5))
							end

							CubeStoredBridge:Fire(id)
							break
						end
					end
				end
			end)
		end
	end)
end

AuraHolder.ChildAdded:Connect(function(child) if child:IsA("Model") then HookAuraModel(child) end end)
HabitatHolder.ChildAdded:Connect(function(child) if child:IsA("Model") then HookHabitatModel(child) end end)

for _, child in ipairs(AuraHolder:GetChildren()) do if child:IsA("Model") then HookAuraModel(child) end end
for _, child in ipairs(HabitatHolder:GetChildren()) do if child:IsA("Model") then HookHabitatModel(child) end end

local trackedInputs = {}

local function EvaluateHolding()
	if isAreaLoading then return end 

	local hasInput = false
	for _, _ in pairs(trackedInputs) do hasInput = true; break end

	if hasInput and not holding then
		if type(shared.TutorialCanPerform) == "function" then
			if not shared.TutorialCanPerform("Action_ClickRedButton") then table.clear(trackedInputs); return end
		end

		if hatcheryEmpty then FlashEmpty() return end
		if habitatFull then return end

		holding = true; holdStart = tick()
		TweenService:Create(clickScale, TweenInfo.new(0.1, Enum.EasingStyle.Sine), {Scale = 0.9}):Play()
		ProduceAuraBridge:Fire("start")

		if type(shared.AdvanceTutorialStep) == "function" then shared.AdvanceTutorialStep() end
	elseif not hasInput and holding then
		holding = false; holdStart = nil
		ProduceAuraBridge:Fire("stop")
		UpdateButtonVisual(); UpdateMultiplier:Fire(1.0)
	end
end

ClickButton.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		trackedInputs[input] = true; EvaluateHolding()
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if input.KeyCode == Enum.KeyCode.Space and not UserInputService:GetFocusedTextBox() then
		local player = game:GetService("Players").LocalPlayer
		if player:GetAttribute("InSpecialArea") then return end

		trackedInputs[input] = true; EvaluateHolding()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if trackedInputs[input] then trackedInputs[input] = nil; EvaluateHolding() end
end)

UserInputService.WindowFocusReleased:Connect(function()
	table.clear(trackedInputs); EvaluateHolding()
end)

ForceStopHold.OnClientEvent:Connect(function()
	table.clear(trackedInputs); EvaluateHolding()
end)

HabitatFull.OnClientEvent:Connect(function()
	habitatFull = true; HabitatFullEvent:Fire(true); table.clear(trackedInputs); EvaluateHolding()
end)

HabitatFullEvent.Event:Connect(function(isFull)
	habitatFull = isFull
	if not isFull then 
		UpdateButtonVisual() 
	end

	local targetedConveyors = {}

	for _, auraModel in ipairs(AuraHolder:GetChildren()) do
		if auraModel:IsA("Model") then
			for _, conveyer in ipairs(auraModel:GetDescendants()) do
				if string.find(conveyer.Name, "Storage") or string.find(conveyer:GetFullName(), "HabitatStorageModel") then
					continue
				end

				if (conveyer.Name == "ConveyerPath" or conveyer.Name == "ConveyerPathCorner") and conveyer:IsA("BasePart") then
					table.insert(targetedConveyors, conveyer:GetFullName())

					local forwardBeam = conveyer:FindFirstChild("Foward") or conveyer:FindFirstChild("Forward")
					local backwardBeam = conveyer:FindFirstChild("Backward")

					if forwardBeam then forwardBeam.Enabled = not isFull end
					if backwardBeam then backwardBeam.Enabled = isFull end

					if not conveyer:GetAttribute("OriginalVelocity") then
						conveyer:SetAttribute("OriginalVelocity", conveyer.AssemblyLinearVelocity)
					end

					local origVel = conveyer:GetAttribute("OriginalVelocity")

					if isFull then 
						conveyer.AssemblyLinearVelocity = origVel * -2
					else 
						conveyer.AssemblyLinearVelocity = origVel 
					end
				end
			end
		end
	end
end)

UpdateHatcheryBridge:Connect(function(info)
	local finalMax = info.max
	local localHatchLvl = player:GetAttribute("LocalHatcheryLevel")

	if localHatchLvl then
		local UpgradeConfig = require(ReplicatedStorage.Modules.UpgradeConfig)
		local cfg = UpgradeConfig.GetUpgradeConfig("hatcheryCapacity")
		if cfg and cfg.apply then
			local predictedMax = cfg.apply({ upgrades = { hatcheryCapacity = localHatchLvl } })
			finalMax = math.max(info.max, predictedMax)
		end
	end
	UpdateHatcheryBar(info.current, finalMax)
end)

local localUpgradesState = {}

local function RecalculateMaxTier()
	local speedData = localUpgradesState["multiplierSpeed"]
	local speedLevel = (typeof(speedData) == "table" and speedData.level) or (typeof(speedData) == "number" and speedData) or 0
	playerMultSpeed = 1.0 + (speedLevel * 0.05)

	local tierUnlocks = {
		{ upgradeId = "unlockOmniMult",      tier = 10 },
		{ upgradeId = "unlockUniversalMult", tier = 9 },
		{ upgradeId = "unlockGodlyMult",     tier = 8 },
		{ upgradeId = "unlockCosmicMult",    tier = 7 },
		{ upgradeId = "unlockMythicMult",    tier = 6 },
	}

	local calculatedMaxTier = 5 
	for _, data in ipairs(tierUnlocks) do
		local upgData = localUpgradesState[data.upgradeId]
		local level = (typeof(upgData) == "table" and upgData.level) or (typeof(upgData) == "number" and upgData) or 0
		if level > 0 then calculatedMaxTier = data.tier; break end
	end
	playerMaxTier = calculatedMaxTier
end

ReplicatedStorage.RemoteEvents.UpgradeUpdated.OnClientEvent:Connect(function(info)
	if not info then return end
	if info.type == "fullState" and info.upgrades then
		localUpgradesState = info.upgrades; RecalculateMaxTier()
	elseif info.type == "purchased" then
		if not localUpgradesState[info.upgradeId] then localUpgradesState[info.upgradeId] = {} end
		if type(localUpgradesState[info.upgradeId]) == "number" then localUpgradesState[info.upgradeId] = { level = info.level }
		else localUpgradesState[info.upgradeId].level = info.level end
		RecalculateMaxTier()
	end
end)

local EpicUpgradeUpdated = ReplicatedStorage.RemoteEvents:FindFirstChild("EpicUpgradeUpdated")
if EpicUpgradeUpdated then
	EpicUpgradeUpdated.OnClientEvent:Connect(function(info)
		if not info then return end
		if info.type == "fullState" and info.upgrades then
			for k,v in pairs(info.upgrades) do localUpgradesState[k] = v end; RecalculateMaxTier()
		elseif info.type == "purchased" then
			if not localUpgradesState[info.upgradeId] then localUpgradesState[info.upgradeId] = {} end
			if type(localUpgradesState[info.upgradeId]) == "number" then localUpgradesState[info.upgradeId] = { level = info.level }
			else localUpgradesState[info.upgradeId].level = info.level end
			RecalculateMaxTier()
		end
	end)
end

UpdateHUDBridge:Connect(function(stats)
	local needsRefresh = false

	if stats.passiveInterval ~= nil and stats.passiveInterval ~= currentPassiveInterval then 
		currentPassiveInterval = stats.passiveInterval
		needsRefresh = true
	end

	if stats.boostMultiplier ~= nil and stats.boostMultiplier ~= globalBoostMultiplier then
		globalBoostMultiplier = stats.boostMultiplier
		needsRefresh = true
	end

	if stats.currentFireRate ~= nil then
		currentFireRate = stats.currentFireRate
	end

	if stats.upgrades then
		for k, v in pairs(stats.upgrades) do localUpgradesState[k] = v end
		RecalculateMaxTier()
	end

	if stats.pendingAuras ~= nil and stats.habitatCapacity ~= nil then
		latestPendingAuras = stats.pendingAuras
		latestHabitatCapacity = stats.habitatCapacity

		if stats.pendingAuras < stats.habitatCapacity and habitatFull then
			habitatFull = false; HabitatFullEvent:Fire(false); UpdateButtonVisual()
		end
		UpdateHabitatBar(stats.pendingAuras, stats.habitatCapacity)
	end

	if needsRefresh then RefreshAllRateLabels() end
end)

task.spawn(function()
	while true do
		if holding then
			if hatcheryEmpty or habitatFull then
				table.clear(trackedInputs); EvaluateHolding()
			else
				ProduceAuraBridge:Fire(); UpdateButtonVisual()
			end
		end
		task.wait(currentFireRate)
	end
end)

AuraSpawnedBridge:Connect(function(info)
	if isAreaLoading then return end 

	local activeAuraModel = workspace:FindFirstChild("AuraHolder") and workspace.AuraHolder:FindFirstChildWhichIsA("Model")
	local safeSpawnPos = info.spawnPos
	if activeAuraModel then
		local spawnPoint = activeAuraModel:FindFirstChild("AuraSpawnPoint", true)
		if spawnPoint and spawnPoint:IsA("BasePart") then
			local size = spawnPoint.Size
			local randX = (math.random() - 0.5) * size.X
			local randZ = (math.random() - 0.5) * size.Z
			safeSpawnPos = (spawnPoint.CFrame * CFrame.new(randX, 0, randZ)).Position
		end
	end

	local instance, isCustom = SpawnAuraInstance(info.tier, info.color, info.glow, safeSpawnPos, info.currentArea)

	if not instance then return end

	instance:SetAttribute("AuraCube", true)
	ScaleAura(instance, info.tier, false)
	ShowCubeValue(safeSpawnPos, info.value, info.color)
	PlayVFX("Spawn", safeSpawnPos, 1.0)

	local permLabel = AttachPermanentRateLabel(instance, info.value, info.color)

	if info.tier == "Legendary" then
		ShowTierPopup(safeSpawnPos, "Legendary", Color3.fromRGB(255, 200, 0))
		PlayVFX("Legendary", safeSpawnPos, 2.0)
	end

	if info.cubeId then
		cubeDataMap[info.cubeId] = { 
			instance = instance, 
			tierName = info.tier, 
			isCustom = isCustom,
			rateLabel = permLabel,
			baseValue = info.value 
		}
		instance.AncestryChanged:Connect(function(_, parent)
			if not parent then cubeDataMap[info.cubeId] = nil end
		end)
	end

	local thrustLevel = 0
	if localUpgradesState["epicConveyorThrust"] then
		thrustLevel = (typeof(localUpgradesState["epicConveyorThrust"]) == "table" and localUpgradesState["epicConveyorThrust"].level) or (typeof(localUpgradesState["epicConveyorThrust"]) == "number" and localUpgradesState["epicConveyorThrust"]) or 0
	end

	if thrustLevel > 0 then
		local root = GetRootPart(instance)
		if root then
			root.AssemblyLinearVelocity = root.AssemblyLinearVelocity + Vector3.new(0, 5, 25)
		end
	end
end)

CubeMutatedBatchBridge:Connect(function(batchData)
	if isAreaLoading then return end

	for _, info in ipairs(batchData) do
		local cubeData = cubeDataMap[info.cubeId]
		if not cubeData then continue end

		if info.newValue then
			cubeData.baseValue = info.newValue
		end

		local instance = cubeData.instance
		if not instance or not instance.Parent then continue end 

		local rootPart = GetRootPart(instance)
		if not rootPart then continue end 
		local position = rootPart.Position

		if info.mutationType == "tierUpgrade" then
			PlayVFX("TierUpgrade", position, 1.5)
			if info.tierName == "Legendary" then PlayVFX("Legendary", position, 2.0) end

			local oldTierName = cubeData.tierName

			local newAura = nil
			local success = false
			local attempts = 0

			while not success and attempts < 3 do
				attempts += 1
				newAura = PoolManager.GetAura(info.currentArea, info.tierName)
				if newAura then
					success = pcall(function() newAura.Parent = workspace end)
				end
			end

			if not success or not newAura then continue end

			if newAura:IsA("Model") then
				newAura:PivotTo(CFrame.new(position))
				local primary = newAura.PrimaryPart or newAura:FindFirstChildWhichIsA("BasePart")

				if primary then
					primary.Anchored = false
					primary.CanCollide = true
					primary.CollisionGroup = "Auras"
					primary.CastShadow = false
				end

				for _, desc in ipairs(newAura:GetDescendants()) do
					if desc:IsA("BasePart") and desc ~= primary then
						desc.CanCollide = false
						desc.CanTouch = false
						desc.CanQuery = false
						desc.CastShadow = false
					end
				end

			elseif newAura:IsA("BasePart") then
				newAura.Position = position
				newAura.Anchored = false
				newAura.CanCollide = true
				newAura.CollisionGroup = "Auras"
				newAura.CastShadow = false
				newAura.Color = info.newColor
			end

			for _, desc in ipairs(newAura:GetDescendants()) do
				if desc:IsA("ParticleEmitter") or desc:IsA("Trail") then desc.Enabled = true end
			end

			newAura:SetAttribute("AuraCube", true)
			ScaleAura(newAura, info.tierName, true, oldTierName)
			ApplyHeavyPhysics(newAura)

			if cubeData.rateLabel and cubeData.rateLabel.Parent and cubeData.rateLabel.Parent:IsA("BillboardGui") then
				local bb = cubeData.rateLabel.Parent
				bb.Adornee = GetRootPart(newAura)
				bb.Parent = GetRootPart(newAura)
				cubeData.rateLabel.TextColor3 = info.newColor or Color3.fromRGB(100, 255, 100)
				if cubeData.isStored then bb.Enabled = false end
			end

			pcall(function() PoolManager.ReturnAura(instance) end)
			cubeData.instance = newAura; cubeData.tierName = info.tierName; cubeData.isCustom = true
			newAura.AncestryChanged:Connect(function(_, parent) if not parent then cubeDataMap[info.cubeId] = nil end end)

			ShowTierPopup(position, info.tierName, info.newColor)
		end

		if cubeData.rateLabel and cubeData.rateLabel.Parent and not cubeData.isStored then
			local ratePerSec = ((cubeData.baseValue or 0) * globalBoostMultiplier) / currentPassiveInterval
			cubeData.rateLabel.Text = "+$" .. FormatNumber(ratePerSec) .. "/sec"
		end
	end
end)

task.spawn(function()
	while true do
		task.wait(1.5)
		local now = tick()

		for id, data in pairs(cubeDataMap) do
			if not data.isStored and data.instance and data.instance.Parent then
				local root = GetRootPart(data.instance)
				if root then
					local currentPos = root.Position
					if not data.spawnY then
						data.spawnY = currentPos.Y; data.lastPos = currentPos; data.lastMovedTime = now
					end
					if currentPos.Y < data.spawnY - 12 then
						CubeSmushedBridge:Fire(id)
						PlayVFX("Spawn", currentPos, 0.5)
						pcall(function() PoolManager.ReturnAura(data.instance) end)
						cubeDataMap[id] = nil
						continue
					end

					local dist = (currentPos - data.lastPos).Magnitude
					if dist < 0.25 then
						if now - data.lastMovedTime > 8 then
							CubeSmushedBridge:Fire(id)
							PlayVFX("Spawn", currentPos, 0.5)
							pcall(function() PoolManager.ReturnAura(data.instance) end)
							cubeDataMap[id] = nil
						end
					else
						data.lastPos = currentPos; data.lastMovedTime = now
					end
				end
			end
		end
	end
end)

AreaChanged.OnClientEvent:Connect(function()
	isAreaLoading = true 

	for id, data in pairs(cubeDataMap) do
		if data.instance then
			pcall(function() data.instance:Destroy() end)
		end
	end
	table.clear(cubeDataMap)
	lastTierIndex = 1

	PoolManager.ClearPools()

	if holding then
		holding = false
		holdStart = nil
		ProduceAuraBridge:Fire("stop")
		UpdateButtonVisual()
		UpdateMultiplier:Fire(1.0)
		table.clear(trackedInputs)
	end

	task.delay(3, function()
		isAreaLoading = false
	end)
end)

PrestigeComplete.OnClientEvent:Connect(function(info)
	table.clear(trackedInputs)
	holding = false
	holdStart = nil
	ProduceAuraBridge:Fire("stop")
	UpdateButtonVisual()
	UpdateMultiplier:Fire(1.0)
end)
