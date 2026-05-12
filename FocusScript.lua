-- givecurrency: CMDR command definition
-- Place in your CMDR BuiltInCommands folder (or custom commands folder)
return {
	Name = "givecurrency";
	Aliases = {"addmoney", "setmoney"};
	Description = "Gives currency to a player. Use negative values to remove.";
	Group = "DefaultAdmin";
	Args = {
		{
			Type = "players";
			Name = "targets";
			Description = "The players to give currency to.";
		},
		{
			Type = "number";
			Name = "amount";
			Description = "Amount of currency to add (negative to remove).";
		},
	};
}

-- givecurrencyServer: CMDR server handler
-- Place next to givecurrency in your CMDR commands folder
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AdminConfig = require(ReplicatedStorage.Modules.AdminConfig)
local UpgradeConfig = require(ReplicatedStorage.Modules.UpgradeConfig)

return function(_, players, amount)
	local GameManager = require(ServerScriptService.GameManager)
	local UpdateHUD = ReplicatedStorage.RemoteEvents:FindFirstChild("UpdateHUD")

	local count = 0
	for _, player in ipairs(players) do
		local data = GameManager.GetData(player.UserId)
		if data then
			data.currency = (data.currency or 0) + amount
			if amount > 0 then
				data.totalEarned = (data.totalEarned or 0) + amount
			end

			-- Send HUD update so UI refreshes instantly
			if UpdateHUD then
				local runtime = GameManager.GetRuntime(player.UserId)
				local pending = runtime and runtime.cubeCount or 0
				local habCfg = UpgradeConfig.GetUpgradeConfig("habitatCapacity")
				local habCap = (habCfg and habCfg.apply) and habCfg.apply(data) or AdminConfig.BaseHabitatCapacity
				local tickCfg = UpgradeConfig.GetUpgradeConfig("passiveTickSpeed")
				local passInt = (tickCfg and tickCfg.apply) and tickCfg.apply(data) or AdminConfig.PassiveInterval
				local pendingPayout = data.pendingPayout or 0
				local avgValue = pending > 0 and (pendingPayout / pending) or AdminConfig.BaseAuraValue

				UpdateHUD:FireClient(player, {
					currency = data.currency,
					pendingAuras = pending,
					habitatCapacity = habCap,
					rate = math.floor(pending * avgValue),
					passiveInterval = passInt,
					totalEarned = data.totalEarned or 0,
					soulAuras = data.soulAuras or 0,
				})
			end

			count += 1
		end
	end

	return ("Gave $%s to %d player(s). "):format(
		tostring(amount),
		count
	)
end

-- givegoldenauras: CMDR command definition
return {
	Name = "givegoldenauras";
	Aliases = {"addgold", "givegold"};
	Description = "Gives Golden Auras to a player. Use negative values to remove.";
	Group = "DefaultAdmin";
	Args = {
		{
			Type = "players";
			Name = "targets";
			Description = "The players to give Golden Auras to.";
		},
		{
			Type = "number";
			Name = "amount";
			Description = "Amount of Golden Auras to add (negative to remove).";
		},
	};
}

-- givegoldenaurasServer: CMDR server handler
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AdminConfig = require(ReplicatedStorage.Modules.AdminConfig)
local UpgradeConfig = require(ReplicatedStorage.Modules.UpgradeConfig)

return function(_, players, amount)
	local GameManager = require(ServerScriptService.GameManager)
	local UpdateHUD = ReplicatedStorage.RemoteEvents:FindFirstChild("UpdateHUD")

	local count = 0
	for _, player in ipairs(players) do
		local data = GameManager.GetData(player.UserId)
		if data then
			-- ✨ THE FIX: Changed GoldenAuras to goldenAuras (lowercase g)
			data.goldenAuras = (data.goldenAuras or 0) + amount

			-- Send HUD update so the Shop and UI refresh instantly
			if UpdateHUD then
				local runtime = GameManager.GetRuntime(player.UserId)
				local pending = runtime and runtime.cubeCount or 0
				local habCfg = UpgradeConfig.GetUpgradeConfig("habitatCapacity")
				local habCap = (habCfg and habCfg.apply) and habCfg.apply(data) or AdminConfig.BaseHabitatCapacity
				local tickCfg = UpgradeConfig.GetUpgradeConfig("passiveTickSpeed")
				local passInt = (tickCfg and tickCfg.apply) and tickCfg.apply(data) or AdminConfig.PassiveInterval
				local pendingPayout = data.pendingPayout or 0
				local avgValue = pending > 0 and (pendingPayout / pending) or AdminConfig.BaseAuraValue

				UpdateHUD:FireClient(player, {
					currency = data.currency or 0,
					pendingAuras = pending,
					habitatCapacity = habCap,
					rate = math.floor(pending * avgValue),
					passiveInterval = passInt,
					totalEarned = data.totalEarned or 0,
					soulAuras = data.soulAuras or 0,
					goldenAuras = data.goldenAuras -- ✨ Syncs the correct lowercase variable
				})
			end

			count += 1
		end
	end

	return ("Gave %s Golden Auras to %d player(s)."):format(
		tostring(amount),
		count
	)
end

-- givesoulauras: CMDR command definition
-- Place in your CMDR BuiltInCommands folder (or custom commands folder)
return {
	Name = "givesoulauras";
	Aliases = {"addsa", "setsa"};
	Description = "Gives Soul Auras to a player. Use negative values to remove.";
	Group = "DefaultAdmin";
	Args = {
		{
			Type = "players";
			Name = "targets";
			Description = "The players to give Soul Auras to.";
		},
		{
			Type = "number";
			Name = "amount";
			Description = "Amount of Soul Auras to add (negative to remove).";
		},
	};
}

-- givesoulaurasServer: CMDR server handler
-- Place next to givesoulauras in your CMDR commands folder
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AdminConfig = require(ReplicatedStorage.Modules.AdminConfig)
local UpgradeConfig = require(ReplicatedStorage.Modules.UpgradeConfig)

return function(_, players, amount)
	local GameManager = require(ServerScriptService.GameManager)
	local UpdateHUD = ReplicatedStorage.RemoteEvents:FindFirstChild("UpdateHUD")

	local count = 0
	for _, player in ipairs(players) do
		local data = GameManager.GetData(player.UserId)
		if data then
			data.soulAuras = math.max(0, (data.soulAuras or 0) + amount)

			-- Send HUD update so UI refreshes instantly
			if UpdateHUD then
				local runtime = GameManager.GetRuntime(player.UserId)
				local pending = runtime and runtime.cubeCount or 0
				local habCfg = UpgradeConfig.GetUpgradeConfig("habitatCapacity")
				local habCap = (habCfg and habCfg.apply) and habCfg.apply(data) or AdminConfig.BaseHabitatCapacity
				local tickCfg = UpgradeConfig.GetUpgradeConfig("passiveTickSpeed")
				local passInt = (tickCfg and tickCfg.apply) and tickCfg.apply(data) or AdminConfig.PassiveInterval
				local pendingPayout = data.pendingPayout or 0
				local avgValue = pending > 0 and (pendingPayout / pending) or AdminConfig.BaseAuraValue

				UpdateHUD:FireClient(player, {
					currency = data.currency,
					pendingAuras = pending,
					habitatCapacity = habCap,
					rate = math.floor(pending * avgValue),
					passiveInterval = passInt,
					totalEarned = data.totalEarned or 0,
					soulAuras = data.soulAuras,
				})
			end

			count += 1
		end
	end

	return ("Gave %d Soul Aura(s) to %d player(s). Total SA: %s"):format(
		amount,
		count,
		count == 1 and tostring((GameManager.GetData(players[1].UserId) or {}).soulAuras or 0) or "varies"
	)
end
