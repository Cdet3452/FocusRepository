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
		shipCapacity = UpgradeConfig.GetShippingCapacity(d) or (AdminConfig.PlatformCapacity or 5), rate=0, 
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
		local cube = runtime.cubes[cubeId]
		if cube then
			if cube.isStored and needed > 0 then
				table.insert(collected, cubeId)
				table.insert(collectedCubes, cube)
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
	player:SetAttribute("HabitatVisualOffset", 0)
end)

local PrestigeComplete = ReplicatedStorage.RemoteEvents:FindFirstChild("PrestigeComplete")
if PrestigeComplete then
	PrestigeComplete.OnClientEvent:Connect(function()
		player:SetAttribute("HabitatVisualOffset", 0)
	end)
end

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
-- UNIVERSAL JUICY VISUALS
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
-- DYNAMIC 3D PLATFORM SPAWNER
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

	local thrusterAtt = Instance.new("Attachment")
	thrusterAtt.Position = Vector3.new(0, -1, 0)
	thrusterAtt.Parent = platformRoot

	local thrusterVFX = Instance.new("ParticleEmitter")
	thrusterVFX.Color = ColorSequence.new(multColor)

	thrusterVFX.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(1, 1)
	})

	thrusterVFX.Lifetime = NumberRange.new(0.3, 0.6)
	thrusterVFX.Rate = 50
	thrusterVFX.Speed = NumberRange.new(5, 10)
	thrusterVFX.EmissionDirection = Enum.NormalId.Bottom
	thrusterVFX.Parent = thrusterAtt

	local habitatPos = GetHabitatPos()
	local midCF = CFrame.new(habitatPos + Vector3.new(0, AdminConfig.PlatformHoverHeight, 0))

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

	local habitatCap = UpgradeConfig.GetHabitatCapacity(data)
	local passiveInt = UpgradeConfig.GetPassiveInterval(data)

	local shipReduction = 0
	local shipCfg = EpicUpgradeConfig.GetUpgradeConfig("epicShipCooldown")
	if shipCfg and shipCfg.apply then
		shipReduction = shipCfg.apply(data)
	end

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
		totalPlatformsShipped = data.totalPlatformsShipped or 0,
		totalCubesProduced    = data.totalCubesProduced or 0,
		shipCapacity          = UpgradeConfig.GetShippingCapacity(data) or AdminConfig.PlatformCapacity,
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

	local epicStorageBoost = 0
	local epicStorageCfg = EpicUpgradeConfig.GetUpgradeConfig("epicShipStorage")
	if epicStorageCfg and epicStorageCfg.apply then 
		epicStorageBoost = epicStorageCfg.apply(data)
	end

	local baseShipCap = UpgradeConfig.GetShippingCapacity and UpgradeConfig.GetShippingCapacity(data) or AdminConfig.PlatformCapacity
	local toCollect = math.min(totalCubes, baseShipCap + epicStorageBoost)		
	local cubeIds, cubes = GameManager.CollectOldestCubes(uid, toCollect)
	local collected  = #cubeIds
	if collected == 0 then return end

	local totalPayout = 0

	data.discoveredTiers = data.discoveredTiers or {}
	local newlyDiscovered = {}

	local doubleEarningsOwned = player:GetAttribute("Pass_DoubleEarnings")
	local passMultiplier = doubleEarningsOwned and BankConfig.Gamepasses.DoubleEarnings.bonus or 1.0

	local epicGoldenYield = 0
	local goldenYieldCfg = EpicUpgradeConfig.GetUpgradeConfig("epicGoldenAuraYield")
	if goldenYieldCfg and goldenYieldCfg.apply then epicGoldenYield = goldenYieldCfg.apply(data) end

	for _, cube in ipairs(cubes) do
		totalPayout = totalPayout + (MutationConfig.GetMutatedValue(cube) * passMultiplier)

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

	task.delay(AdminConfig.PlatformSpeed * 4 + 10, function()
		if Players:GetPlayerByUserId(uid) and pendingPayouts[uid] and pendingPayouts[uid][dispatchId] then
			pendingPayouts[uid][dispatchId] = nil
			activeTrucks[uid] = math.max(0, (activeTrucks[uid] or 1) - 1)
		end
	end)


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

		GameManager.SavePlayer(player)

		SendHUDUpdate(player)

		ShipAurasBridge:Fire(player, {
			action = "payoutConfirmed",
			amount = actualPayout
		})
	end


end)

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
		shipCapacity    = UpgradeConfig.GetShippingCapacity(data) or AdminConfig.PlatformCapacity,
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

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local TweenService       = game:GetService("TweenService")
local Debris             = game:GetService("Debris")
local UserInputService   = game:GetService("UserInputService")
local CollectionService  = game:GetService("CollectionService")

local AdminConfig        = require(ReplicatedStorage.Modules:WaitForChild("AdminConfig"))
local Formatter          = require(ReplicatedStorage.Modules:WaitForChild("NumberFormatter"))
local UITheme            = require(ReplicatedStorage.Modules:WaitForChild("UITheme"))

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
local habitatCapacity     = AdminConfig.BaseHabitatCapacity or 50
local shipCapacity        = AdminConfig.BaseShipCapacity or 5
local passiveInterval     = AdminConfig.PassiveInterval
local currentCooldownTime = 15
local isShipOnCooldown    = false
local sharedCooldownEnd   = 0
local manualCooldownLoopID = 0
local autoLoopID          = 0
local currentHatcheryLevel = AdminConfig.HatcheryMax or 150

local localLastPiggyBank  = 0
local isFirstBankLoad     = true

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
				effectGui.IgnoreGuiInset = true 
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
	local visualPending = math.max(0, actualPending + offset)

	local capacityToUse = capacity > 0 and capacity or habitatCapacity
	local ratio    = math.clamp(visualPending / capacityToUse, 0, 1)
	local color    = GetRateColor(visualPending, capacityToUse)
	local model    = HabitatHolder:FindFirstChild("HabitatModel")

	if model then
		local gui    = model:FindFirstChild("HabitatGui")
		local barBg  = gui and gui:FindFirstChild("BarBackground")
		local barFill = barBg and barBg:FindFirstChild("BarFill")

		if barBg then
			local oldLabel1 = barBg:FindFirstChild("CountLabel")
			local oldLabel2 = barBg:FindFirstChild("AmountLabel")
			if oldLabel1 then oldLabel1.Visible = false end
			if oldLabel2 then oldLabel2.Visible = false end
		end

		if barFill then
			TweenService:Create(barFill, TweenInfo.new(0.3), {
				Size = UDim2.new(ratio, 0, 1, 0),
				BackgroundColor3 = color,
			}):Play()
		end

		if gui then
			local textCap = gui:FindFirstChild("3DCapacityLabel")
			if not textCap then
				textCap = Instance.new("TextLabel")
				textCap.Name = "3DCapacityLabel"
				textCap.Size = UDim2.new(1, 0, 1, 0)
				textCap.Position = UDim2.new(0, 0, 0, 0)
				textCap.BackgroundTransparency = 1
				textCap.Font = Enum.Font.GothamBlack 
				textCap.TextScaled = true
				textCap.TextColor3 = Color3.fromRGB(255, 255, 255)
				textCap.Parent = gui

				local stroke = Instance.new("UIStroke", textCap)
				stroke.Thickness = 3
				stroke.Color = Color3.fromRGB(0, 0, 0)
			end

			textCap.Text = FormatNumber(visualPending) .. " / " .. FormatNumber(capacityToUse)

			local prevPending = textCap:GetAttribute("LastPending") or 0

			if visualPending < prevPending then
				textCap.TextColor3 = Color3.fromRGB(100, 255, 128) 
				TweenService:Create(textCap, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					TextColor3 = Color3.fromRGB(255, 255, 255)
				}):Play()
			elseif visualPending >= capacityToUse and capacityToUse > 0 then
				textCap.TextColor3 = Color3.fromRGB(255, 80, 80) 
			elseif visualPending > prevPending then
				if textCap.TextColor3 == Color3.fromRGB(255, 80, 80) then
					textCap.TextColor3 = Color3.fromRGB(255, 255, 255)
				end
			end

			textCap:SetAttribute("LastPending", visualPending)

			local shipTextCap = gui:FindFirstChild("3DShipCapacityLabel")
			if not shipTextCap then
				shipTextCap = Instance.new("TextLabel")
				shipTextCap.Name = "3DShipCapacityLabel"
				shipTextCap.Size = UDim2.new(1, 0, 0.45, 0)
				shipTextCap.Position = UDim2.new(0, 1, 1, 0)
				shipTextCap.BackgroundTransparency = 1
				shipTextCap.Font = Enum.Font.GothamBold 
				shipTextCap.TextScaled = true
				shipTextCap.TextColor3 = Color3.fromRGB(180, 220, 255)
				shipTextCap.Parent = gui

				local stroke = Instance.new("UIStroke", shipTextCap)
				stroke.Thickness = 2
				stroke.Color = Color3.fromRGB(0, 0, 0)
			end

			shipTextCap.Text = "Ship Capacity: " .. FormatNumber(shipCapacity)
		end
	end


end

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

		local offset = player:GetAttribute("HabitatVisualOffset") or 0
		local visualPending = math.max(0, pendingAuras + offset)

		autoHabitatLabel.Text = "Waiting: " .. FormatNumber(visualPending) .. " / " .. FormatNumber(habitatCapacity)

		if visualPending >= habitatCapacity then
			autoHabitatLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
		elseif visualPending > 0 then
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

player:GetAttributeChangedSignal("HabitatVisualOffset"):Connect(function()
	UpdateHabitatBar(pendingAuras, habitatCapacity)
	UpdateSendButton()
end)

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

	if stats.prestigeCount ~= nil then
		local currentPrestige = player:GetAttribute("PrestigeCount") or 0
		if stats.prestigeCount > currentPrestige then
			player:SetAttribute("PrestigeCount", stats.prestigeCount)
			player:SetAttribute("HabitatVisualOffset", 0)
			pendingAuras = 0
		end
	end

	if stats.currentArea ~= nil then
		local currentArea = player:GetAttribute("CurrentArea") or 1
		if stats.currentArea ~= currentArea then
			player:SetAttribute("CurrentArea", stats.currentArea)
			player:SetAttribute("HabitatVisualOffset", 0)
			pendingAuras = 0
		end
	end

	if stats.shipCapacity ~= nil then
		shipCapacity = stats.shipCapacity
		UpdateHabitatBar(pendingAuras, habitatCapacity)
	end

	-- FIX: ONLY update capacity if it explicitly exists and is valid. Never fall back to nil/0.
	if stats.habitatCapacity ~= nil and stats.habitatCapacity > 0 then
		habitatCapacity = stats.habitatCapacity
	end

	if stats.pendingAuras ~= nil then
		if stats.pendingAuras < pendingAuras then
			local diff = pendingAuras - stats.pendingAuras
			local currentOffset = player:GetAttribute("HabitatVisualOffset") or 0
			player:SetAttribute("HabitatVisualOffset", currentOffset + diff)
		end

		pendingAuras = stats.pendingAuras

		UpdateHabitatBar(pendingAuras, habitatCapacity)
		UpdateSendButton() 
	end

	if stats.rate ~= nil then
		passiveInterval = stats.passiveInterval or passiveInterval
		local serverRate = stats.rate
		ratePerSecond = (passiveInterval > 0 and serverRate > 0) and serverRate / passiveInterval or 0

		rate.Text = FormatRate(ratePerSecond)
		local offset = player:GetAttribute("HabitatVisualOffset") or 0
		TweenService:Create(rate, TweenInfo.new(0.3), { TextColor3 = GetRateColor(pendingAuras + offset, habitatCapacity) }):Play()	
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

local function ForceSpawnTeleport()
	local char = player.Character or player.CharacterAdded:Wait()
	local spawnLoc = workspace:WaitForChild("SpawnLocation", 10)

	if char and spawnLoc then
		task.wait(0.1) 
		char:PivotTo(spawnLoc.CFrame * CFrame.new(0, (spawnLoc.Size.Y / 2) + 3, 0))
	end


end

task.spawn(ForceSpawnTeleport)

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

	if stats.pendingAuras ~= nil then
		latestPendingAuras = stats.pendingAuras
	end

	-- FIX: Securely fetch from valid data payloads
	if stats.habitatCapacity ~= nil and stats.habitatCapacity > 0 then
		latestHabitatCapacity = stats.habitatCapacity
	end

	if stats.pendingAuras ~= nil then
		if stats.pendingAuras < latestHabitatCapacity and habitatFull then
			habitatFull = false
			HabitatFullEvent:Fire(false)
			UpdateButtonVisual()
		end
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
		cubeDataMap[info.cubeId].ancestryConn = instance.AncestryChanged:Connect(function(_, parent)
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
			if cubeData.ancestryConn then cubeData.ancestryConn:Disconnect() end
			local conn = newAura.AncestryChanged:Connect(function(_, parent)
				if not parent then cubeDataMap[info.cubeId] = nil end
			end)
			cubeData.ancestryConn = conn
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


-- UpgradeConfig
-- Location: ReplicatedStorage > Modules > UpgradeConfig
local AdminConfig = require(script.Parent.AdminConfig)
local UpgradeConfig = {}

UpgradeConfig.Tiers = {
	[1] = {
		tierName = "Tier 1",
		unlockRequirement = 0,
		upgrades = {
			blockValue = {
				baseCost = 45, costScale = 1.03, maxLevel = 100,
				apply = function(data) return ((data.upgrades and data.upgrades.blockValue) or 0) * 0.1 end,
				displayName = "Glow Enhancement", description = "Increases base aura value by +10%", iconId = "rbxassetid://98075952013490",
			},
			hatcheryCapacity = {
				baseCost = 475, costScale = 1.02, maxLevel = 50,
				apply = function(data) return ((data.upgrades and data.upgrades.hatcheryCapacity) or 0) * 1 end,
				displayName = "Aura Expansion", description = "Increases the max capacity of your Hatchery by 1", iconId = "rbxassetid://140457223774888",
			},
			habitatCapacity = {
				baseCost = 850, costScale = 1.05, maxLevel = 25,
				apply = function(data) return ((data.upgrades and data.upgrades.habitatCapacity) or 0) * 2 end,
				displayName = "Habitat Reservoir", description = "Increase habitat capacity by 2", iconId = "rbxassetid://78419118472133",
			},
			unlockMythicMult = { 
				baseCost = 3000, costScale = 1, maxLevel = 1, 
				apply = function(data) return ((data.upgrades and data.upgrades.unlockMythicMult) or 0) == 1 end,
				displayName = "Mythic Multiplier",
				description = "Allows you to hold past the legendary multiplier! Unlocks the " .. (AdminConfig.MilestoneData[6] and AdminConfig.MilestoneData[6].name or "MYTHIC") .. " tier!",
				iconId = "rbxassetid://113828358885527",
			},
		}
	},
	[2] = {
		tierName = "Tier 2",
		unlockRequirement = 150,
		upgrades = {
			blockValueT2 = {
				baseCost = 1000, costScale = 1.05, maxLevel = 125,
				apply = function(data) return ((data.upgrades and data.upgrades.blockValueT2) or 0) * 0.25 end,
				displayName = "Faster Aura Pulse", description = "Increased aura value by +25%", iconId = "rbxassetid://114779329450267",
			},
			passiveTickSpeedT2 = {
				baseCost = 20000, costScale = 1.45, maxLevel = 5,
				apply = function(data) return ((data.upgrades and data.upgrades.passiveTickSpeedT2) or 0) * 0.05 end,
				displayName = "Advanced Aura Generation", description = "Speeds up passive aura Money by 0.05s", iconId = "rbxassetid://101759432122769",
			},	
			shipCapacityT1 = {
				baseCost = 8000, costScale = 1.25, maxLevel = 25,
				apply = function(data) return ((data.upgrades and data.upgrades.shipCapacityT1) or 0) * 1 end,	iconId = "rbxassetid://121937028282282",
				displayName = "Shipping Expansion", description = "Increases the max auras a ship can carry by 1.",
			},
		}
	},
	[3] = {
		tierName = "Tier 3",
		unlockRequirement = 150, 
		upgrades = {
			auraValueT3 = {
				baseCost = 250000, costScale = 1.15, maxLevel = 4,
				apply = function(data) return ((data.upgrades and data.upgrades.auraValueT3) or 0) * 0.5 end,
				displayName = "Aura Purifier", description = "Purifies Your Auras, Increases Value by 50%",
			},
			hatcheryT3 = {
				baseCost = 750000, costScale = 1.3, maxLevel = 25,
				apply = function(data) return ((data.upgrades and data.upgrades.hatcheryT3) or 0) * 2 end,
				displayName = "Increased Hatchery", description = "Provides even more hatchery space for more auras by 2",
			},
			habitatT3 = {
				baseCost = 2000000, costScale = 1.4, maxLevel = 15,
				apply = function(data) return ((data.upgrades and data.upgrades.habitatT3) or 0) * 10 end,
				displayName = "Industrial Packaging", description = "Increases Habitat Capacity by 10",
			},
			droneFrequency = {
				baseCost = 500000, costScale = 1.4, maxLevel = 25,
				apply = function(data) return ((data.upgrades and data.upgrades.droneFrequency) or 0) * 1 end,
				displayName = "Unstable Area", description = "Random Aura Shots appear more frequently. 1% higher chance for more.",
			},
		}
	},
	[4] = {
		tierName = "Tier 4",
		unlockRequirement = 225, 
		upgrades = {
			auraValueT4 = {
				baseCost = 15000000, costScale = 1.25, maxLevel = 250,
				apply = function(data) return ((data.upgrades and data.upgrades.auraValueT4) or 0) * 1.0 end,
				displayName = "Shinier Auras", description = "Auras Shine Brighter and increase value by 100%",
			},
			hatcheryT4 = {
				baseCost = 40000000, costScale = 1.35, maxLevel = 20,
				apply = function(data) return ((data.upgrades and data.upgrades.hatcheryT4) or 0) * 5 end,
				displayName = "Advanced Hatchery", description = "Increases Hatchery by 5",
			},
			eliteSpawnChance = {
				baseCost = 25000000, costScale = 1.4, maxLevel = 25,
				apply = function(data) return ((data.upgrades and data.upgrades.eliteSpawnChance) or 0) * 1.0 end,
				displayName = "Luckier Shots", description = "Increases the chance of an Elite Aura spawning by 1%.",
			},
		}
	},
	[5] = {
		tierName = "Tier 5",
		unlockRequirement = 200,
		upgrades = {
			habitatT5 = {
				baseCost = 5e8, costScale = 1.4, maxLevel = 50,
				apply = function(data) return ((data.upgrades and data.upgrades.habitatT5) or 0) * 50 end,
				displayName = "Stellar Habitats", description = "House your auras inside miniature stars (+50 capacity).",
			},
			habitatDiscount = {
				baseCost = 1e8, costScale = 1.5, maxLevel = 10,
				apply = function(data) return ((data.upgrades and data.upgrades.habitatDiscount) or 0) * 0.02 end,
				displayName = "Material Synthesis", description = "Reduces the cost of upgrading habitats by 2%.",
			},
			autoDispatchSpeed = {
				baseCost = 7.5e8, costScale = 1.3, maxLevel = 25,
				apply = function(data) return ((data.upgrades and data.upgrades.autoDispatchSpeed) or 0) * 0.1 end,
				displayName = "Logistics AI", description = "Auto-shipping speed increased by 10%.",
			},
			unlockCosmicMult = { 
				baseCost = 2.5e9, costScale = 1, maxLevel = 1, 
				apply = function(data) return ((data.upgrades and data.upgrades.unlockCosmicMult) or 0) == 1 end,
				displayName = "Cosmic Multiplier", 
				description = "Shatters the Mythic limit, unlocking the " .. (AdminConfig.MilestoneData[7] and AdminConfig.MilestoneData[7].name or "COSMIC") .. " tier!",
			},
		}
	},
	[6] = {
		tierName = "Tier 6",
		unlockRequirement = 300,
		upgrades = {
			passiveSpeedT6 = {
				baseCost = 5e10, costScale = 1.5, maxLevel = 25,
				apply = function(data) return ((data.upgrades and data.upgrades.passiveSpeedT6) or 0) * 0.1 end,
				displayName = "Faster Than Light", description = "Auras spawn before you even need them (-0.1s delay).",
			},
			auraValueT6 = {
				baseCost = 1.5e11, costScale = 1.3, maxLevel = 200,
				apply = function(data) return ((data.upgrades and data.upgrades.auraValueT6) or 0) * 5.0 end,
				displayName = "Tachyon Infusion", description = "Infuse auras with speed particles for +500% value per level.",
			},
			doubleSpawnChance = {
				baseCost = 2e10, costScale = 1.35, maxLevel = 25,
				apply = function(data) return ((data.upgrades and data.upgrades.doubleSpawnChance) or 0) * 1 end,
				displayName = "Mitosis Splitting", description = "1% chance for a spawner to generate two auras at once.",
			},
			offlineTimeCap = {
				baseCost = 3.5e10, costScale = 1.4, maxLevel = 25,
				apply = function(data) return ((data.upgrades and data.upgrades.offlineTimeCap) or 0) * 1 end,
				displayName = "Stasis Batteries", description = "Increases max offline earnings time by 1 hour.",
			},
			goldenAuraValue = {
				baseCost = 8e10, costScale = 1.5, maxLevel = 25,
				apply = function(data) return ((data.upgrades and data.upgrades.goldenAuraValue) or 0) * 0.1 end,
				displayName = "Refined Gold", description = "Golden Auras collected grant +10% more premium currency.",
			},
			shippingCapacityT6 = {
				baseCost = 1e11, costScale = 1.45, maxLevel = 25,
				apply = function(data) return ((data.upgrades and data.upgrades.shippingCapacityT6) or 0) * 500 end,
				displayName = "Wormhole Freight", description = "Ships carry +500 more auras through hyperspace.",
			},
		}
	},
	[7] = {
		tierName = "Tier 7",
		unlockRequirement = 500,
		upgrades = {
			hatcheryT7 = {
				baseCost = 1e13, costScale = 1.4, maxLevel = 100,
				apply = function(data) return ((data.upgrades and data.upgrades.hatcheryT7) or 0) * 50 end,
				displayName = "Void Reservoirs", description = "Store energy in the endless void (+50 capacity).",
			},
			habitatT7 = {
				baseCost = 5e13, costScale = 1.45, maxLevel = 100,
				apply = function(data) return ((data.upgrades and data.upgrades.habitatT7) or 0) * 250 end,
				displayName = "Antimatter Containment", description = "Safely store massive amounts of auras (+250 capacity).",
			},
			prestigeMultiplierBonus = {
				baseCost = 2e13, costScale = 1.6, maxLevel = 10,
				apply = function(data) return ((data.upgrades and data.upgrades.prestigeMultiplierBonus) or 0) * 0.05 end,
				displayName = "Soul Memory", description = "Increases the multiplier gained from Prestiging by 5%.",
			},
			droneRewardMulti = {
				baseCost = 8e13, costScale = 1.5, maxLevel = 25,
				apply = function(data) return ((data.upgrades and data.upgrades.droneRewardMulti) or 0) * 0.2 end,
				displayName = "Heavier Payloads", description = "Random drops contain 20% more resources.",
			},
		}
	},
	[8] = {
		tierName = "Tier 8",
		unlockRequirement = 1000,
		upgrades = {
			auraValueT8 = {
				baseCost = 5e15, costScale = 1.35, maxLevel = 250,
				apply = function(data) return ((data.upgrades and data.upgrades.auraValueT8) or 0) * 25.0 end,
				displayName = "Reality Bending", description = "Auras pull value from alternate dimensions (+2,500% value).",
			},
			godlyCritChance = {
				baseCost = 1e16, costScale = 1.4, maxLevel = 25,
				apply = function(data) return ((data.upgrades and data.upgrades.godlyCritChance) or 0) * 0.2 end,
				displayName = "Divine Intervention", description = "0.2% chance for an aura to instantly massively spike its value.",
			},
			habitatT8 = {
				baseCost = 8e16, costScale = 1.5, maxLevel = 100,
				apply = function(data) return ((data.upgrades and data.upgrades.habitatT8) or 0) * 1000 end,
				displayName = "Pocket Universes", description = "Creates entire universes to hold your auras (+1,000 capacity).",
			},
			unlockGodlyMult = { 
				baseCost = 1e17, costScale = 1, maxLevel = 1,
				apply = function(data) return ((data.upgrades and data.upgrades.unlockGodlyMult) or 0) == 1 end,
				displayName = "Godly Multiplier", 
				description = "Reach ascension. Unlocks the " .. (AdminConfig.MilestoneData[8] and AdminConfig.MilestoneData[8].name or "GODLY") .. " tier!",
			},
		}
	},
	[9] = {
		tierName = "Tier 9",
		unlockRequirement = 1500,
		upgrades = {
			habitatT9 = {
				baseCost = 1e19, costScale = 1.5, maxLevel = 150,
				apply = function(data) return ((data.upgrades and data.upgrades.habitatT9) or 0) * 5000 end,
				displayName = "Galaxy Clusters", description = "Your habitats are now comprised of entire galaxies (+5,000 capacity).",
			},
			hatcheryT9 = {
				baseCost = 5e19, costScale = 1.5, maxLevel = 1500,
				apply = function(data) return ((data.upgrades and data.upgrades.hatcheryT9) or 0) * 200 end,
				displayName = "Big Bang Forges", description = "Hatch energy from the birth of new universes (+200 capacity).",
			},
			universalShipping = {
				baseCost = 8e19, costScale = 1.45, maxLevel = 50,
				apply = function(data) return ((data.upgrades and data.upgrades.universalShipping) or 0) * 50000 end,
				displayName = "Teleportation Networks", description = "Instantly beam auras to buyers (+50,000 shipping capacity).",
			},
			unlockUniversalMult = { 
				baseCost = 1e20, costScale = 1, maxLevel = 1, 
				apply = function(data) return ((data.upgrades and data.upgrades.unlockUniversalMult) or 0) == 1 end,
				displayName = "Universal Multiplier", 
				description = "Shatter reality. Unlocks the " .. (AdminConfig.MilestoneData[9] and AdminConfig.MilestoneData[9].name or "UNIVERSAL") .. " tier!",
			},
		}
	},
	[10] = {
		tierName = "Tier 10",
		unlockRequirement = 2500,
		upgrades = {
			auraValueT10 = {
				baseCost = 1e22, costScale = 1.4, maxLevel = 500,
				apply = function(data) return ((data.upgrades and data.upgrades.auraValueT10) or 0) * 150.0 end,
				displayName = "Limitless Potential", description = "The ultimate value upgrade. +15,000% value per level.",
			},
			omniCapacity = {
				baseCost = 5e22, costScale = 1.5, maxLevel = 500,
				apply = function(data) return ((data.upgrades and data.upgrades.omniCapacity) or 0) * 25000 end,
				displayName = "The Final Frontier", description = "Unfathomable space (+25,000 habitat capacity).",
			},
			omniSpeed = {
				baseCost = 8e22, costScale = 1.6, maxLevel = 100,
				apply = function(data) return ((data.upgrades and data.upgrades.omniSpeed) or 0) * 0.2 end,
				displayName = "Time Collapse", description = "Auras generate infinitely fast (-0.2s delay).",
			},
			unlockOmniMult = { 
				baseCost = 5e23, costScale = 1, maxLevel = 1,
				apply = function(data) return ((data.upgrades and data.upgrades.unlockOmniMult) or 0) == 1 end,
				displayName = "Omni Multiplier", 
				description = "The absolute limit. Unlocks the " .. (AdminConfig.MilestoneData[10] and AdminConfig.MilestoneData[10].name or "OMNI") .. " tier!",
			},
		}
	},
}

-- === GLOBAL HELPER FUNCTIONS ===

function UpgradeConfig.GetUpgradeConfig(upgradeId)
	for _, tierData in ipairs(UpgradeConfig.Tiers) do
		if tierData.upgrades[upgradeId] then return tierData.upgrades[upgradeId] end
	end
	return nil
end

function UpgradeConfig.CalculateCost(upgradeId, currentLevel, data)
	local cfg = UpgradeConfig.GetUpgradeConfig(upgradeId)
	if not cfg then return math.huge end
	if currentLevel >= cfg.maxLevel then return math.huge end

	local cost = math.floor(cfg.baseCost * (cfg.costScale ^ currentLevel))

	-- Apply habitat material synthesis discount if applicable
	if data and string.find(string.lower(upgradeId), "habitat") then
		local discountCfg = UpgradeConfig.GetUpgradeConfig("habitatDiscount")
		if discountCfg and discountCfg.apply then
			local discount = discountCfg.apply(data)
			cost = math.floor(cost * (1 - discount))
		end
	end

	return cost
end

function UpgradeConfig.GetHabitatCapacity(data)
	local cap = AdminConfig.BaseHabitatCapacity or 50
	local keys = {"habitatCapacity", "habitatT3", "habitatT5", "habitatT7", "habitatT8", "habitatT9", "omniCapacity"}
	for _, k in ipairs(keys) do
		local cfg = UpgradeConfig.GetUpgradeConfig(k)
		if cfg and cfg.apply then cap = cap + cfg.apply(data) end
	end
	return cap
end

function UpgradeConfig.GetHatcheryMax(data)
	local cap = AdminConfig.HatcheryMax or 100
	local keys = {"hatcheryCapacity", "hatcheryT3", "hatcheryT4", "hatcheryT7", "hatcheryT9"}
	for _, k in ipairs(keys) do
		local cfg = UpgradeConfig.GetUpgradeConfig(k)
		if cfg and cfg.apply then cap = cap + cfg.apply(data) end
	end
	return cap
end

function UpgradeConfig.GetPassiveInterval(data)
	local interval = AdminConfig.PassiveInterval or 10
	local keys = {"passiveTickSpeedT2", "passiveSpeedT6", "omniSpeed"}
	local totalReduction = 0
	for _, k in ipairs(keys) do
		local cfg = UpgradeConfig.GetUpgradeConfig(k)
		if cfg and cfg.apply then totalReduction = totalReduction + cfg.apply(data) end
	end
	return math.max(0.1, interval - totalReduction) -- Cap minimum tick speed to 0.1s
end

function UpgradeConfig.GetTotalValueMultiplier(data)
	local mult = 1.0
	local keys = {"blockValue", "blockValueT2", "auraValueT3", "auraValueT4", "auraValueT6", "auraValueT8", "auraValueT10"}
	for _, k in ipairs(keys) do
		local cfg = UpgradeConfig.GetUpgradeConfig(k)
		if cfg and cfg.apply then mult = mult + cfg.apply(data) end
	end
	return mult
end

function UpgradeConfig.GetShippingCapacity(data)
	local cap = AdminConfig.PlatformCapacity or 10
	local keys = {"shipCapacityT1", "shippingCapacityT6", "universalShipping"}
	for _, k in ipairs(keys) do
		local cfg = UpgradeConfig.GetUpgradeConfig(k)
		if cfg and cfg.apply then cap = cap + cfg.apply(data) end
	end
	return cap
end

return UpgradeConfig

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
local EpicUpgradeConfig = require(ReplicatedStorage.Modules:WaitForChild("EpicUpgradeConfig"))

local HabitatFull    = ReplicatedStorage.RemoteEvents:WaitForChild("HabitatFull")

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
	if type(UpgradeConfig.GetHatcheryMax) == "function" then
		return UpgradeConfig.GetHatcheryMax(data)
	end
	return AdminConfig.HatcheryMax or 150
end

local function GetHabitatCapacity(data)
	if type(UpgradeConfig.GetHabitatCapacity) == "function" then
		return UpgradeConfig.GetHabitatCapacity(data)
	end
	return AdminConfig.BaseHabitatCapacity or 50
end

local function GetMutationSpeedMult(data)
	local cfg = UpgradeConfig.GetUpgradeConfig("mutationSpeed")
	return (cfg and cfg.apply) and cfg.apply(data) or 1
end

local function TrackTierSpawn(data, tierName)
	if tierName == "Legendary" then data.totalLegendaryCubes = (data.totalLegendaryCubes or 0) + 1
	elseif tierName == "Mythic" then data.totalMythicCubes = (data.totalMythicCubes or 0) + 1
	elseif tierName == "Divine" then data.totalDivineCubes = (data.totalDivineCubes or 0) + 1
	elseif tierName == "Celestial" then data.totalCelestialCubes = (data.totalCelestialCubes or 0) + 1
	elseif tierName == "Cosmic" then data.totalCosmicCubes = (data.totalCosmicCubes or 0) + 1
	elseif tierName == "Omni" then data.totalOmniCubes = (data.totalOmniCubes or 0) + 1
	end
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

			local hasInstaHatchery = data and data.boostInventory and data.boostInventory["InstaHatchery"]

			if hasInstaHatchery then
				hatchery[uid] = hatchMax
			else
				if holdStart[uid] then
					hatchery[uid] = math.max(0, prev - AdminConfig.HatcheryDrainRate * 0.1)
				else
					hatchery[uid] = math.min(hatchMax, prev + AdminConfig.HatcheryRefillRate * 0.1)
				end
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

local function GetEffectiveFireRate(uid)
	local rushMult = BoostManager.GetSpawnRateMultiplier(uid)
	local weatherSpawnMult, _ = WeatherManager.GetMultipliers(uid)
	local effectiveFireRate = AdminConfig.FireRate / (rushMult * weatherSpawnMult)
	if effectiveFireRate < 0.05 then effectiveFireRate = 0.05 end
	return effectiveFireRate
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

	UpdateHUDBridge:Fire(player, {
		currency        = data.currency, 
		pendingAuras    = storedCount, 
		habitatCapacity = GetHabitatCapacity(data), 
		rate            = displayRate,
		passiveInterval = UpgradeConfig.GetPassiveInterval(data), 
		totalEarned     = data.totalEarned or 0,
		soulAuras       = data.soulAuras or 0, 
		farmEvaluation  = data.farmEvaluation or 0,
		goldenAuras     = data.goldenAuras or 0, 
		boostInventory  = data.boostInventory or {},
		prestigeCount   = data.prestigeCount or 0,
		upgrades        = data.upgrades or {},
		totalCubesProduced = data.totalCubesProduced or 0,
		currentArea     = data.currentArea or 1,
		discoveredTiers = data.discoveredTiers or {},
		currentFireRate = GetEffectiveFireRate(uid),
		boostMultiplier = boostMult ,
		shipCapacity    = UpgradeConfig.GetShippingCapacity(data) or AdminConfig.PlatformCapacity,
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

						local auraKey = currentArea .. "_" .. newTier.name
						if not data.discoveredTiers then data.discoveredTiers = {} end
						if not data.discoveredTiers[auraKey] then
							data.discoveredTiers[auraKey] = true
							GameManager.SavePlayer(player)
							UpdateHUDBridge:Fire(player, { discoveredTiers = data.discoveredTiers })
						end

						table.insert(mutationBatch, { 
							cubeId = cubeId, mutationType = "tierUpgrade",
							newColor = newTier.color, newGlow = newTier.glow, 
							tierName = newTier.name, currentArea = currentArea
						})

						TrackTierSpawn(data, newTier.name)
					else break end
				end

				if mutated then
					local newMutatedValue = MutationConfig.GetMutatedValue(cube)
					runtime.totalMutatedValue = (runtime.totalMutatedValue or 0) + (newMutatedValue - oldMutatedValue)
					if not cube.isStored then runtime.activeMutatedValue = (runtime.activeMutatedValue or 0) + (newMutatedValue - oldMutatedValue) end

					if #mutationBatch > 0 then
						for i = #mutationBatch, 1, -1 do
							if mutationBatch[i].cubeId == cubeId then
								mutationBatch[i].newValue = newMutatedValue
								break
							end
						end
					end
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

	local milestoneReduction = 0
	local clickMilestoneCfg = EpicUpgradeConfig.GetUpgradeConfig("epicClickMilestone")
	if clickMilestoneCfg and clickMilestoneCfg.apply then
		milestoneReduction = clickMilestoneCfg.apply(data)
	end

	local function GetMilestoneTime(index)
		if not AdminConfig.MilestoneData[index] then return 999999 end
		return math.max(0, AdminConfig.MilestoneData[index].time - milestoneReduction)
	end

	local effectiveTime = holdTime * playerMultSpeed
	local currentTier = 1

	for i = 1, playerMaxTier do
		if AdminConfig.MilestoneData[i] and effectiveTime >= GetMilestoneTime(i) then currentTier = i end
	end

	local nextTier = math.min(currentTier + 1, playerMaxTier)
	if currentTier == playerMaxTier then return AdminConfig.MilestoneData[currentTier].mult, AdminConfig.MilestoneData[currentTier].luck end

	local timePassed = effectiveTime - GetMilestoneTime(currentTier)
	local timeNeeded = GetMilestoneTime(nextTier) - GetMilestoneTime(currentTier)
	local ratio = timeNeeded > 0 and (timePassed / timeNeeded) or 1 

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
		if tier.name ~= "Common" then 
			chance = chance * (1 + (luckBonus or 0)) 
		end
		table.insert(adjusted, { tier=tier, chance=chance })
		total += chance
	end

	local r = math.random() * total
	local cum = 0
	local rolledTier = nil

	for _, e in ipairs(adjusted) do 
		cum += e.chance
		if not rolledTier and r <= cum then 
			rolledTier = e.tier 
		end 
	end

	rolledTier = rolledTier or tiers[1]
	return rolledTier
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

	local totalValueMultiplier = UpgradeConfig.GetTotalValueMultiplier(data)

	local prestigeMult    = PrestigeModule.GetMultiplier(data.soulAuras, data)
	local areaMult        = AreaRegistry.GetMultiplier(data.currentArea or 1)
	local boostValueMult  = BoostManager.GetValueMultiplier(uid)
	local _, weatherValueMult = WeatherManager.GetMultipliers(uid)

	local epicLuckCfg = EpicUpgradeConfig.GetUpgradeConfig("epicLuck")
	if epicLuckCfg and epicLuckCfg.apply then luckBonus = (luckBonus or 0) + epicLuckCfg.apply(data) end

	local calcMultFloat = totalValueMultiplier * prestigeMult * areaMult * boostValueMult * weatherValueMult
	local baseValue = math.floor(AdminConfig.BaseAuraValue * tier.multiplier * calcMultFloat)

	local godlyCritCfg = UpgradeConfig.GetUpgradeConfig("godlyCritChance")
	local critChance = (godlyCritCfg and godlyCritCfg.apply) and godlyCritCfg.apply(data) or 0
	local isGodlyCrit = false

	if critChance > 0 and (math.random() * 100) <= critChance then
		isGodlyCrit = true
		baseValue = baseValue * 500 
	end

	local totalValue = baseValue + math.floor(baseValue * (holdMult - 1))

	local spawnPos = HABITAT_PART.Position + Vector3.new(math.random(-3,3), 10, math.random(-3,3))	
	local activeAuraModel = workspace:FindFirstChild("AuraHolder") and workspace.AuraHolder:FindFirstChildWhichIsA("Model")
	if activeAuraModel then
		local spawnPoint = activeAuraModel:FindFirstChild("AuraSpawnPoint", true)
		if spawnPoint and spawnPoint:IsA("BasePart") then
			local size = spawnPoint.Size
			local randX = (math.random() - 0.5) * size.X
			local randZ = (math.random() - 0.5) * size.Z
			spawnPos = (spawnPoint.CFrame * CFrame.new(randX, 0, randZ)).Position
		end
	end

	local cubeRecord = { spawnTime=tick(), effectiveElapsed=0, lastUpgradeElapsed=0, baseValue=totalValue, tierIndex=tierIndex, tierName=tier.name, color=tier.color, glow=tier.glow, isStored=false, currentArea=currentArea }

	if AdminConfig.MutationInstantMax then
		local mb = MutationConfig.ValueBonuses[#MutationConfig.ValueBonuses]
		if mb then cubeRecord.effectiveElapsed = mb.time + 1 end
	end

	local cubeId = GameManager.AddCube(uid, cubeRecord)
	if not cubeId then return end

	local epicDoubleSpawn = EpicUpgradeConfig.GetUpgradeConfig("epicDoubleSpawn")
	if epicDoubleSpawn and epicDoubleSpawn.apply and epicDoubleSpawn.apply(data) > 0 then
		local doubleCubeId = GameManager.AddCube(uid, cubeRecord)
		if doubleCubeId then
			AuraSpawnedBridge:Fire(player, { cubeId=doubleCubeId, tier=tier.name, color=tier.color, glow=tier.glow, value=totalValue, spawnPos=spawnPos, currentArea = currentArea, isGodlyCrit = isGodlyCrit })
			data.totalCubesProduced = (data.totalCubesProduced or 0) + 1
			TrackTierSpawn(data, tier.name)
		end
	end

	local auraKey = currentArea .. "_" .. tier.name
	if not data.discoveredTiers then data.discoveredTiers = {} end
	if not data.discoveredTiers[auraKey] then
		data.discoveredTiers[auraKey] = true
		GameManager.SavePlayer(player)
		UpdateHUDBridge:Fire(player, { discoveredTiers = data.discoveredTiers })
	end

	data.totalCubesProduced = (data.totalCubesProduced or 0) + 1
	TrackTierSpawn(data, tier.name)

	runtime.lastActiveTime = tick()

	AuraSpawnedBridge:Fire(player, { cubeId=cubeId, tier=tier.name, color=tier.color, glow=tier.glow, value=totalValue, spawnPos=spawnPos, currentArea = currentArea, isGodlyCrit = isGodlyCrit })
end

ProduceAuraBridge:Connect(function(player, action)
	if player:GetAttribute("IsTransitioning") or player:GetAttribute("InSpecialArea") then
		if action == "start" then holdStart[player.UserId] = nil end
		return
	end

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

	if runtime.cubeCount >= capacity + 600 then return end 

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

	if lastFire[uid] then
		local timeSinceLast = now - lastFire[uid]
		if timeSinceLast < (effectiveFireRate - 0.015) then return end 
	end
	lastFire[uid] = now

	local holdTime = now - holdStart[uid]
	local holdMult, luckBonus = GetHoldMultiplier(holdTime, data)

	local doubleSpawnCfg = UpgradeConfig.GetUpgradeConfig("doubleSpawnChance")
	local doubleChance = (doubleSpawnCfg and doubleSpawnCfg.apply) and doubleSpawnCfg.apply(data) or 0

	for i = 1, spawnCount do 
		SpawnAura(player, data, runtime, holdMult, luckBonus) 

		if doubleChance > 0 and math.random(1, 100) <= doubleChance then
			SpawnAura(player, data, runtime, holdMult, luckBonus) 
		end
	end

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

-- PassiveIncome
-- Location: ServerScriptService > PassiveIncome

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AdminConfig    = require(ReplicatedStorage.Modules.AdminConfig)
local UpgradeConfig  = require(ReplicatedStorage.Modules.UpgradeConfig)
local GameManager    = require(ServerScriptService.GameManager)
local BoostManager   = require(ServerScriptService.BoostManager)

local BridgeNet2      = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))
local UpdateHUDBridge = BridgeNet2.ServerBridge("UpdateHUD")

if script:GetAttribute("Running") then script:Destroy(); return end
script:SetAttribute("Running", true)

local lastSentCurrency   = {}  
local lastSentStored     = {}

Players.PlayerAdded:Connect(function(p)
	lastSentCurrency[p.UserId] = 0
	lastSentStored[p.UserId]   = 0
end)

Players.PlayerRemoving:Connect(function(p)
	lastSentCurrency[p.UserId] = nil
	lastSentStored[p.UserId]   = nil
end)

while true do
	-- ✨ BLAZING FAST 20Hz LOOP (Matches your FocusScript!)
	local dt = task.wait(0.05)

	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("TutorialFrozen") then continue end

		local uid     = player.UserId
		local data    = GameManager.GetData(uid)
		local runtime = GameManager.GetRuntime(uid)
		if not data or not runtime then continue end

		local activeValue = runtime.activeMutatedValue or 0
		local storedCount = runtime.storedCubeCount or 0

		local interval = AdminConfig.PassiveInterval or 1
		local tickCfg = UpgradeConfig.GetUpgradeConfig("passiveTickSpeed")
		if tickCfg and tickCfg.apply then interval = tickCfg.apply(data) end
		if interval <= 0 then interval = 1 end

		local boostMult = BoostManager.GetValueMultiplier(uid) * BoostManager.GetSpawnRateMultiplier(uid)

		-- Calculate the exact microscopic fraction earned in this 0.05s window
		local fullTickEarned   = activeValue * boostMult
		local fractionalEarned = fullTickEarned * (dt / interval)

		if fractionalEarned > 0 then
			data.currency       = (data.currency       or 0) + fractionalEarned
			data.totalEarned    = (data.totalEarned     or 0) + fractionalEarned
			data.farmEvaluation = (data.farmEvaluation  or 0) + fractionalEarned
		end

		-- Only fire the BridgeNet update if they are actively making money or the habitat changed
		local shouldFire = false
		if not lastSentCurrency[uid] or math.abs(data.currency - lastSentCurrency[uid]) > 0.001 then
			shouldFire = true
		end
		if storedCount ~= lastSentStored[uid] then
			shouldFire = true
		end

		if shouldFire then
			lastSentCurrency[uid] = data.currency
			lastSentStored[uid]   = storedCount

			local habCfg = UpgradeConfig.GetUpgradeConfig("habitatCapacity")
			local habCap = (habCfg and habCfg.apply) and habCfg.apply(data) or AdminConfig.BaseHabitatCapacity

			UpdateHUDBridge:Fire(player, {
				currency        = data.currency, 
				pendingAuras    = storedCount, 
				habitatCapacity = habCap,
				rate            = math.floor(fullTickEarned),
				passiveInterval = interval,
				totalEarned     = math.floor(data.totalEarned or 0),
				soulAuras       = data.soulAuras      or 0,
				farmEvaluation  = math.floor(data.farmEvaluation or 0),
				boostMultiplier = boostMult -- ✨ THE FIX: Sync to HUD so labels scale!
			})
		end
	end
end

-- BoostManager
-- Location: ServerScriptService > BoostManager (ModuleScript)

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AdminConfig = require(ReplicatedStorage.Modules.AdminConfig)
local GameManager = require(ServerScriptService.GameManager)
local BoostConfig = require(ReplicatedStorage.Modules.BoostConfig)
local AchievementConfig = require(ReplicatedStorage.Modules.AchievementConfig)

local BridgeNet2      = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))
local UpdateHUDBridge = BridgeNet2.ServerBridge("UpdateHUD")

local function GetOrCreate(name)
	local existing = ReplicatedStorage.RemoteEvents:FindFirstChild(name)
	if existing then return existing end
	local re = Instance.new("RemoteEvent")
	re.Name   = name
	re.Parent = ReplicatedStorage.RemoteEvents
	return re
end

local BuyBoost      = GetOrCreate("BuyBoost")
local ActivateBoost = GetOrCreate("ActivateBoost")
local BoostUpdated  = GetOrCreate("BoostUpdated")

local activeStacks = {}

local function GetActiveStacks(uid, boostId)
	local stacks = activeStacks[uid] or {}
	local count, now = 0, tick()
	for _, entry in ipairs(stacks) do
		if entry.boostId == boostId and entry.endsAt > now then
			count += 1
		end
	end
	return count
end

local function PruneExpired(uid)
	local stacks = activeStacks[uid]
	if not stacks then return end
	local now, pruned = tick(), {}
	for _, entry in ipairs(stacks) do
		if entry.endsAt > now then table.insert(pruned, entry) end
	end
	activeStacks[uid] = pruned
end

-- ✨ THE FIX: Calculates the total Premium "Boost Beacon" Multiplier
local function GetPremiumMultiplier(uid)
	local stacks = activeStacks[uid] or {}
	local now = tick()
	local premMult = 1
	for _, entry in ipairs(stacks) do
		if entry.endsAt > now then
			local cfg = BoostConfig.Get(entry.boostId)
			if cfg and cfg.effectType == "boostMultiplier" then
				premMult = premMult * cfg.multiplier
			end
		end
	end
	return premMult
end

-- ✨ THE FIX: Dynamically grabs ANY boost matching the effect type and stacks them properly
local function GetTotalMultiplier(uid, effectType, isExponential)
	PruneExpired(uid)
	local totalMultiplier = 1
	local stacks = activeStacks[uid] or {}
	local now = tick()

	local premMult = GetPremiumMultiplier(uid)

	local counts = {}
	for _, entry in ipairs(stacks) do
		if entry.endsAt > now then
			local cfg = BoostConfig.Get(entry.boostId)
			if cfg and cfg.effectType == effectType then
				counts[entry.boostId] = (counts[entry.boostId] or 0) + 1
			end
		end
	end

	if isExponential then
		for boostId, count in pairs(counts) do
			local cfg = BoostConfig.Get(boostId)
			-- Applies the premium multiplier to the boost's bonus factor
			local effectiveBase = 1 + ((cfg.multiplier - 1) * premMult)
			totalMultiplier = totalMultiplier * (effectiveBase ^ count)
		end
	else
		local totalBonus = 0
		for boostId, count in pairs(counts) do
			local cfg = BoostConfig.Get(boostId)
			totalBonus = totalBonus + ((cfg.multiplier - 1) * count)
		end
		totalMultiplier = 1 + (totalBonus * premMult)
	end

	return totalMultiplier
end

local BoostManager = {}

-- Dynamically maps to the effectTypes in your config
function BoostManager.GetSpawnRateMultiplier(uid) return GetTotalMultiplier(uid, "spawnSpeed", true) end
function BoostManager.GetValueMultiplier(uid) return GetTotalMultiplier(uid, "cubeValue", false) end
function BoostManager.GetHatcheryMultiplier(uid) return GetTotalMultiplier(uid, "hatcheryRefill", false) end
function BoostManager.GetShippingMultiplier(uid) return GetTotalMultiplier(uid, "shipSpeed", false) end
function BoostManager.GetSoulMultiplier(uid) return GetTotalMultiplier(uid, "soulMult", false) end
function BoostManager.GetLuckMultiplier(uid) return GetTotalMultiplier(uid, "luckMult", false) end
function BoostManager.GetGoldenMultiplier(uid) return GetTotalMultiplier(uid, "goldenMult", false) end

function BoostManager.IsActive(uid, boostId)
	return GetActiveStacks(uid, boostId) > 0
end

local function BuildState(uid)
	PruneExpired(uid)
	local stacks = activeStacks[uid] or {}
	local data   = GameManager.GetData(uid)
	local now    = tick()

	local state = {}

	for boostId, cfg in pairs(BoostConfig.Boosts or {}) do
		local activeList = {}
		for _, entry in ipairs(stacks) do
			if entry.boostId == boostId and entry.endsAt > now then
				table.insert(activeList, math.max(0, entry.endsAt - now))
			end
		end
		state[boostId] = {
			inventoryCount = data and (data.boostInventory and data.boostInventory[boostId] or 0) or 0,
			activeCount    = #activeList,
			activeTimes    = activeList,
			duration       = cfg.duration,
			cost           = cfg.cost,
			multiplier     = cfg.multiplier,
			displayName    = cfg.displayName,
			description    = cfg.description,
			icon           = cfg.icon,
			maxStack       = cfg.maxStack,
			stackable      = cfg.stackable,
		}
	end

	state._goldenAuras = data and (data.goldenAuras or 0) or 0
	return state
end

local function SendState(player)
	BoostUpdated:FireClient(player, BuildState(player.UserId))
end

BuyBoost.OnServerEvent:Connect(function(player, boostId)
	local uid  = player.UserId
	local data = GameManager.GetData(uid)
	if not data then return end

	local cfg = BoostConfig.Get(boostId)
	if not cfg then warn("[BoostManager] Unknown boost:", boostId); return end

	local cost = cfg.cost or 0
	if (data.goldenAuras or 0) < cost then return end
	local isUnlocked = AchievementConfig.IsBoostUnlocked(boostId, data)
	if not isUnlocked then return end 

	data.goldenAuras = (data.goldenAuras or 0) - cost
	data.boostInventory = data.boostInventory or {}
	data.boostInventory[boostId] = (data.boostInventory[boostId] or 0) + 1

	SendState(player)
	UpdateHUDBridge:Fire(player, {
		goldenAuras    = data.goldenAuras,
		boostInventory = data.boostInventory,
	})
end)

ActivateBoost.OnServerEvent:Connect(function(player, boostId)
	local uid  = player.UserId
	local data = GameManager.GetData(uid)
	if not data then return end

	local cfg = BoostConfig.Get(boostId)
	if not cfg then return end

	data.boostInventory = data.boostInventory or {}
	if (data.boostInventory[boostId] or 0) <= 0 then return end

	PruneExpired(uid)
	local currentStacks = GetActiveStacks(uid, boostId)
	if currentStacks >= (cfg.maxStack or 1) then return end

	data.boostInventory[boostId] = data.boostInventory[boostId] - 1

	if cfg.duration == 0 then
		if cfg.effectType == "cashCheck" then
			local premMult = GetPremiumMultiplier(uid)
			local payout = math.floor((data.farmEvaluation or 0) * (cfg.multiplier or 5) * premMult)
			if payout > 0 then
				data.currency    = (data.currency or 0) + payout
				data.totalEarned = (data.totalEarned or 0) + payout

				UpdateHUDBridge:Fire(player, {
					currency      = data.currency,
					totalEarned   = data.totalEarned,
					instantPayout = payout 
				})
			end
		end

		SendState(player)
		return
	end

	activeStacks[uid] = activeStacks[uid] or {}
	table.insert(activeStacks[uid], {
		boostId = boostId,
		endsAt  = tick() + cfg.duration,
	})

	SendState(player)

	task.delay(cfg.duration, function()
		PruneExpired(uid)
		if player and player.Parent then SendState(player) end
	end)
end)

Players.PlayerAdded:Connect(function(player)
	activeStacks[player.UserId] = {}
	task.wait(2)
	SendState(player)
end)

Players.PlayerRemoving:Connect(function(player)
	activeStacks[player.UserId] = nil
end)

task.spawn(function()
	while true do
		task.wait(5)
		for _, player in ipairs(Players:GetPlayers()) do
			if activeStacks[player.UserId] and #activeStacks[player.UserId] > 0 then
				SendState(player)
			end
		end
	end
end)

return BoostManager

-- PrestigeHandler
-- Location: ServerScriptService > PrestigeHandler

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AdminConfig    = require(ReplicatedStorage.Modules.AdminConfig)
local UpgradeConfig  = require(ReplicatedStorage.Modules.UpgradeConfig)
local PrestigeModule = require(ReplicatedStorage.Modules.PrestigeModule)
local GameManager    = require(ServerScriptService.GameManager)
local BoostManager   = require(ServerScriptService.BoostManager)

local RequestPrestige  = ReplicatedStorage.RemoteEvents:WaitForChild("RequestPrestige")
local PrestigeComplete = ReplicatedStorage.RemoteEvents:WaitForChild("PrestigeComplete")
local UpgradeUpdated   = ReplicatedStorage.RemoteEvents:WaitForChild("UpgradeUpdated")

local BridgeNet2             = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))
local UpdateHUDBridge        = BridgeNet2.ServerBridge("UpdateHUD")
local UpdateHatcheryBridge   = BridgeNet2.ServerBridge("UpdateHatchery")

local PrestigeReset = Instance.new("BindableEvent")
PrestigeReset.Name   = "PrestigeReset"
PrestigeReset.Parent = ServerScriptService

local prestigeDebounce  = {}
local PRESTIGE_COOLDOWN = 5

RequestPrestige.OnServerEvent:Connect(function(player)
	local uid = player.UserId
	local now = tick()

	if prestigeDebounce[uid] and now - prestigeDebounce[uid] < PRESTIGE_COOLDOWN then return end
	prestigeDebounce[uid] = now

	local data    = GameManager.GetData(uid)
	local runtime = GameManager.GetRuntime(uid)
	if not data then warn("[PrestigeHandler] No data for player:", uid); return end

	if data.hasPrestigedThisArea then
		PrestigeComplete:FireClient(player, {
			blocked              = true,
			reason               = "Already prestiged in this area. Travel to a new area to prestige again!",
			hasPrestigedThisArea = true,
		})
		return
	end

	local earned       = data.totalEarned or 0
	local rawSoulAuras = PrestigeModule.CalcSoulAuras(earned)
	if rawSoulAuras <= 0 then return end

	local soulMult     = BoostManager.GetSoulMultiplier(uid)
	local newSoulAuras = math.floor(rawSoulAuras * soulMult)

	local previousSoulAuras  = data.soulAuras or 0
	local previousMultiplier = PrestigeModule.GetMultiplier(previousSoulAuras)

	local bonusPercent  = AdminConfig.PrestigeStartBonusPercent or 0.05
	local prestigeBonus = math.max(math.floor(earned * bonusPercent), 50)

	data.soulAuras              = previousSoulAuras + newSoulAuras
	data.prestigeCount          = (data.prestigeCount or 0) + 1
	data.hasPrestigedThisArea   = true
	local newMultiplier = PrestigeModule.GetMultiplier(data.soulAuras)

	data.currency           = prestigeBonus
	data.totalEarned        = 0
	data.pendingAuras       = 0
	data.pendingPayout      = 0
	data.pendingBonusPayout = 0
	data.lastPayout         = 0

	for key, _ in pairs(data.upgrades) do data.upgrades[key] = 0 end

	GameManager.PerformPrestigeReset(player)

	PrestigeReset:Fire(player)

	PrestigeComplete:FireClient(player, {
		newSoulAuras         = newSoulAuras,
		totalSoulAuras       = data.soulAuras,
		previousMultiplier   = previousMultiplier,
		newMultiplier        = newMultiplier,
		prestigeCount        = data.prestigeCount,
		prestigeBonus        = prestigeBonus,
		soulBoostActive      = soulMult > 1,
		hasPrestigedThisArea = true,
	})

	local resetState = {}
	for _, tierData in ipairs(UpgradeConfig.Tiers) do
		for upgradeId, cfg in pairs(tierData.upgrades) do
			resetState[upgradeId] = {
				level    = 0,
				maxLevel = cfg.maxLevel,
				cost     = UpgradeConfig.CalculateCost(upgradeId, 0),
				maxed    = false,
			}
		end
	end
	UpgradeUpdated:FireClient(player, {
		type     = "fullState",
		upgrades = resetState,
		currency = prestigeBonus,
	})

	UpdateHatcheryBridge:Fire(player, {
		current = AdminConfig.HatcheryMax,
		max     = AdminConfig.HatcheryMax,
	})

	task.wait(0.3)
	UpdateHUDBridge:Fire(player, {
		currency             = data.currency,
		pendingAuras         = 0,
		habitatCapacity      = AdminConfig.BaseHabitatCapacity,
		rate                 = 0,
		passiveInterval      = AdminConfig.PassiveInterval,
		totalEarned          = 0,
		soulAuras            = data.soulAuras      or 0,
		farmEvaluation       = data.farmEvaluation or 0,
		goldenAuras          = data.goldenAuras    or 0,
		boostInventory       = data.boostInventory or {},
		prestigeCount        = data.prestigeCount  or 0,
		hasPrestigedThisArea = true,
	})
end)

local PreviewPrestige = ReplicatedStorage.RemoteEvents:WaitForChild("PreviewPrestige")

PreviewPrestige.OnServerEvent:Connect(function(player)
	local data = GameManager.GetData(player.UserId)
	if not data then return end

	local earned       = data.totalEarned or 0
	local rawSoulAuras = PrestigeModule.CalcSoulAuras(earned)
	local currentSA    = data.soulAuras or 0
	local currentMult  = PrestigeModule.GetMultiplier(currentSA)
	local soulMult     = BoostManager.GetSoulMultiplier(player.UserId)
	local newSoulAuras = math.floor(rawSoulAuras * soulMult)
	local newMult      = PrestigeModule.GetMultiplier(currentSA + newSoulAuras)
	local bonusPercent  = AdminConfig.PrestigeStartBonusPercent or 0.05
	local prestigeBonus = math.max(math.floor(earned * bonusPercent), 50)

	PreviewPrestige:FireClient(player, {
		totalEarned          = earned,
		newSoulAuras         = newSoulAuras,
		currentSoulAuras     = currentSA,
		currentMultiplier    = currentMult,
		newMultiplier        = newMult,
		prestigeCount        = data.prestigeCount or 0,
		prestigeBonus        = prestigeBonus,
		soulBoostActive      = soulMult > 1,
		hasPrestigedThisArea = data.hasPrestigedThisArea == true,
	})
end)

local BoostConfig = {}

BoostConfig.Boosts = {

	-- ══════════ PRODUCTION (Spawn Speed, Hatchery, Shipping) ══════════
	AuraRush = {
		id          = "AuraRush",
		displayName = "Aura Rush",
		description = "1.5x spawn speed",
		icon        = "rbxassetid://14915278241", 
		duration    = 30,
		cost        = 5,
		multiplier  = 1.5,
		effectType  = "spawnSpeed",
		stackable   = true,
		maxStack    = 3,
		category    = "Production",
		color       = Color3.fromRGB(60, 160, 255),
	},
	MegaAuraRush = {
		id          = "MegaAuraRush",
		displayName = "Super Aura Rush",
		description = "3x spawn speed",
		icon        = "rbxassetid://14915278241", 
		duration    = 45,
		cost        = 15,
		multiplier  = 3.0,
		effectType  = "spawnSpeed",
		stackable   = true,
		maxStack    = 3,
		category    = "Production",
		color       = Color3.fromRGB(40, 140, 255),
	},
	HatcheryRefill = {
		id          = "HatcheryRefill",
		displayName = "Fast Refill",
		description = "2x hatchery refill speed",
		icon        = "rbxassetid://14917001489",
		duration    = 60,
		cost        = 8,
		multiplier  = 2.0,
		effectType  = "hatcheryRefill",
		stackable   = true,
		maxStack    = 3,
		category    = "Production",
		color       = Color3.fromRGB(80, 220, 120),
	},
	InstaHatchery = {
		id          = "InstaHatchery",
		displayName = "Insta Refill",
		description = "Instantly refill hatchery to max",
		icon        = "rbxassetid://14922827627",
		duration    = 5,   
		cost        = 12,
		multiplier  = 9999,
		effectType  = "instaRefill",
		stackable   = false,
		maxStack    = 1,
		category    = "Production",
		color       = Color3.fromRGB(0, 255, 180),
	},
	AutoShipperBoost = {
		id          = "AutoShipperBoost",
		displayName = "Cargo Boost",
		description = "2x auto-shipping speed",
		icon        = "rbxassetid://14958914404", 
		duration    = 120,
		cost        = 10,
		multiplier  = 2.0,
		effectType  = "shipSpeed",
		stackable   = true,
		maxStack    = 3,
		category    = "Production",
		color       = Color3.fromRGB(200, 200, 200),
	},
	FleetBoost = {
		id          = "FleetBoost",
		displayName = "Fleet Boost",
		description = "5x auto-shipping speed",
		icon        = "rbxassetid://14958914404", 
		duration    = 180,
		cost        = 30,
		multiplier  = 5.0,
		effectType  = "shipSpeed",
		stackable   = true,
		maxStack    = 3,
		category    = "Production",
		color       = Color3.fromRGB(150, 150, 150),
	},

	-- ══════════ VALUE (Cash, Souls, Luck, Golden) ══════════
	ValueBoost = {
		id          = "ValueBoost",
		displayName = "Value Boost",
		description = "2x Aura Value",
		icon        = "rbxassetid://14916016959",
		duration    = 45,
		cost        = 4,
		multiplier  = 2.0,
		effectType  = "cubeValue",
		stackable   = true,
		maxStack    = 3,
		category    = "Value",
		color       = Color3.fromRGB(255, 160, 40),
	},
	SoulBoost = {
		id          = "SoulBoost",
		displayName = "Soul Boost",
		description = "2x Soul Auras on prestige",
		icon        = "rbxassetid://14923413548",
		duration    = 120,
		cost        = 15,
		multiplier  = 2.0,
		effectType  = "soulMult",
		stackable   = false,
		maxStack    = 1,
		category    = "Value",
		color       = Color3.fromRGB(180, 60, 255),
	},
	CashCheck = {
		id          = "CashCheck",
		displayName = "Cash Check",
		description = "Get 5x your farm evaluation as cash!",
		icon        = "rbxassetid://14914085898",
		duration    = 0,   
		cost        = 20,
		multiplier  = 5,   
		effectType  = "cashCheck",
		stackable   = false,
		maxStack    = 1,
		category    = "Value",
		color       = Color3.fromRGB(80, 255, 80),
	},

	-- ══════════ PREMIUM — BOOST MULTIPLIERS ══════════
	BoostBeacon2x = {
		id          = "BoostBeacon2x",
		displayName = "Boost Beacon x2",
		description = "Double all active boost effects!",
		icon        = "rbxassetid://14915837331",
		duration    = 30,
		cost        = 25,
		multiplier  = 2,
		effectType  = "boostMultiplier",
		stackable   = false,
		maxStack    = 1,
		category    = "Premium",
		color       = Color3.fromRGB(255, 100, 100),
	},
	BoostBeacon10x = {
		id          = "BoostBeacon10x",
		displayName = "Boost Beacon x10",
		description = "10x all active boost effects!",
		icon        = "rbxassetid://14916585009",
		duration    = 15,
		cost        = 100,
		multiplier  = 10,
		effectType  = "boostMultiplier",
		stackable   = false,
		maxStack    = 1,
		category    = "Premium",
		color       = Color3.fromRGB(255, 60, 60),
	},

}

-- Perfected IDs so AuraRush and ValueBoost are untangled
BoostConfig.ShopOrder = {
	"AuraRush", "MegaAuraRush",
	"HatcheryRefill", "InstaHatchery",
	"AutoShipperBoost", "FleetBoost",
	"ValueBoost", "SoulBoost",
	"CashCheck",
	"BoostBeacon2x", "BoostBeacon10x",
}

BoostConfig.Categories = { "Production", "Value", "Premium" }

BoostConfig.CategoryColors = {
	Production = Color3.fromRGB(60, 180, 255),
	Value      = Color3.fromRGB(255, 200, 60),
	Premium    = Color3.fromRGB(255, 60, 80),
}

function BoostConfig.Get(id) return BoostConfig.Boosts[id] end

function BoostConfig.GetByCategory(category)
	local result = {}
	for _, id in ipairs(BoostConfig.ShopOrder) do
		local b = BoostConfig.Boosts[id]
		if b and b.category == category then table.insert(result, b) end
	end
	return result
end

return BoostConfig
