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
