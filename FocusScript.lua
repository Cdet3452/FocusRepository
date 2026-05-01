-- ══════════ DEVELOPER ECONOMY CHEAT SHEET ══════════

-- [ Hundreds ]
-- 5e1  = 50
-- 5e2  = 500

-- [ Thousands (k) ]
-- 5e3  = 5k
-- 5e4  = 50k
-- 5e5  = 500k

-- [ Millions (M) ]
-- 5e6  = 5M
-- 5e7  = 50M
-- 5e8  = 500M

-- [ Billions (B) ]
-- 5e9  = 5B
-- 5e10 = 50B
-- 5e11 = 500B

-- [ Trillions (T) ]
-- 5e12 = 5T
-- 5e13 = 50T
-- 5e14 = 500T

-- [ Quadrillions (Qa) ]
-- 5e15 = 5Qa
-- 5e16 = 50Qa
-- 5e17 = 500Qa

-- [ Quintillions (Qi) ]
-- 5e18 = 5Qi
-- 5e19 = 50Qi
-- 5e20 = 500Qi

-- [ Sextillions (Sx) ]
-- 5e21 = 5Sx
-- 5e22 = 50Sx
-- 5e23 = 500Sx

-- [ Septillions (Sp) ]
-- 5e24 = 5Sp
-- 5e25 = 50Sp
-- 5e26 = 500Sp

-- [ Octillions (Oc) ]
-- 5e27 = 5Oc
-- 5e28 = 50Oc
-- 5e29 = 500Oc

-- [ Nonillions (No) ]
-- 5e30 = 5No
-- 5e31 = 50No
-- 5e32 = 500No

-- [ Decillions (Dc) ]
-- 5e33 = 5Dc
-- 5e34 = 50Dc
-- 5e35 = 500Dc

-- ══════════ ROMAN NUMERAL RANKS ══════════

-- [ Rank I ]
-- 5e36 = 5 I
-- 5e37 = 50 I
-- 5e38 = 500 I

-- [ Rank II ]
-- 5e39 = 5 II
-- 5e40 = 50 II
-- 5e41 = 500 II

-- [ Rank III ]
-- 5e42 = 5 III
-- 5e43 = 50 III
-- 5e44 = 500 III

-- [ Rank IV ]
-- 5e45 = 5 IV
-- 5e46 = 50 IV
-- 5e47 = 500 IV

-- [ Rank V ]
-- 5e48 = 5 V
-- 5e49 = 50 V
-- 5e50 = 500 V

-- [ Rank VI ]
-- 5e51 = 5 VI
-- 5e52 = 50 VI
-- 5e53 = 500 VI

-- [ Rank VII ]
-- 5e54 = 5 VII
-- 5e55 = 50 VII
-- 5e56 = 500 VII

-- [ Rank VIII ]
-- 5e57 = 5 VIII
-- 5e58 = 50 VIII
-- 5e59 = 500 VIII

-- [ Rank IX ]
-- 5e60 = 5 IX
-- 5e61 = 50 IX
-- 5e62 = 500 IX

-- [ Rank X ]
-- 5e63 = 5 X
-- 5e64 = 50 X
-- 5e65 = 500 X

-- [ Rank XI ]
-- 5e66 = 5 XI
-- 5e67 = 50 XI
-- 5e68 = 500 XI

-- [ Rank XII ]
-- 5e69 = 5 XII
-- 5e70 = 50 XII
-- 5e71 = 500 XII

-- ═══════════════════════════════════════════════════
local AreaRegistry = {}

AreaRegistry.LightingPresets = {

	-- 🏭 PHASE 1: THE GRIME (Areas 1-3)
	["Area1_DeepScrapyard"] = {
		ClockTime = 12, Brightness = 0.3, SunRaysIntensity = 0,
		Ambient = Color3.fromRGB(70, 60, 50), FogColor = Color3.fromRGB(90, 80, 65),
		FogStart = 20, FogEnd = 60, Density = 0.7, Haze = 10, AtmosphereColor = Color3.fromRGB(90, 80, 65)
	},
	["Area2_RustyWastes"] = {
		ClockTime = 14, Brightness = 0.4, SunRaysIntensity = 0,
		Ambient = Color3.fromRGB(80, 65, 50), FogColor = Color3.fromRGB(100, 85, 60),
		FogStart = 20, FogEnd = 80, Density = 0.6, Haze = 8, AtmosphereColor = Color3.fromRGB(100, 85, 60)
	},
	["Area3_IndustrialOutskirts"] = {
		ClockTime = 16, Brightness = 0.5, SunRaysIntensity = 0,
		Ambient = Color3.fromRGB(85, 75, 65), FogColor = Color3.fromRGB(110, 100, 90),
		FogStart = 30, FogEnd = 100, Density = 0.55, Haze = 6, AtmosphereColor = Color3.fromRGB(110, 100, 90)
	},

	-- ☣️ PHASE 2: TOXIC ZONES (Areas 4-5)
	["Area4_ChemicalSpill"] = {
		ClockTime = 17, Brightness = 0.4, SunRaysIntensity = 0,
		Ambient = Color3.fromRGB(60, 75, 50), FogColor = Color3.fromRGB(75, 90, 55),
		FogStart = 50, FogEnd = 110, Density = 0.5, Haze = 7, AtmosphereColor = Color3.fromRGB(75, 90, 55)
	},
	["Area5_BioHazard"] = {
		ClockTime = 17.5, Brightness = 0.3, SunRaysIntensity = 0,
		Ambient = Color3.fromRGB(40, 60, 40), FogColor = Color3.fromRGB(45, 80, 45),
		FogStart = 60, FogEnd = 120, Density = 0.4, Haze = 5, AtmosphereColor = Color3.fromRGB(45, 80, 45)
	},

	-- 🌆 PHASE 3: TWILIGHT SLUMS (Areas 6-8)
	["Area6_SunsetStrip"] = {
		ClockTime = 17.8, Brightness = 0.6, SunRaysIntensity = 0.1, -- Sun peeks through!
		Ambient = Color3.fromRGB(70, 40, 40), FogColor = Color3.fromRGB(90, 40, 30),
		FogStart = 20, FogEnd = 150, Density = 0.5, Haze = 4, AtmosphereColor = Color3.fromRGB(120, 50, 40)
	},
	["Area7_TwilightSector"] = {
		ClockTime = 18.2, Brightness = 0.4, SunRaysIntensity = 0,
		Ambient = Color3.fromRGB(40, 30, 60), FogColor = Color3.fromRGB(35, 25, 55),
		FogStart = 20, FogEnd = 180, Density = 0.55, Haze = 4, AtmosphereColor = Color3.fromRGB(35, 25, 55)
	},
	["Area8_NeonSlums"] = {
		ClockTime = 0, Brightness = 0.5, SunRaysIntensity = 0,
		Ambient = Color3.fromRGB(30, 20, 50), FogColor = Color3.fromRGB(20, 10, 40),
		FogStart = 25, FogEnd = 200, Density = 0.5, Haze = 3, AtmosphereColor = Color3.fromRGB(40, 20, 80)
	},

	-- 🌃 PHASE 4: CYBER CITY (Areas 9-10)
	["Area9_LowerCyber"] = {
		ClockTime = 0, Brightness = 0.7, SunRaysIntensity = 0,
		Ambient = Color3.fromRGB(25, 25, 55), FogColor = Color3.fromRGB(15, 15, 45),
		FogStart = 30, FogEnd = 250, Density = 0.4, Haze = 2, AtmosphereColor = Color3.fromRGB(20, 20, 60)
	},
	["Area10_CyberCore"] = {
		ClockTime = 0, Brightness = 1, SunRaysIntensity = 0,
		Ambient = Color3.fromRGB(20, 30, 60), FogColor = Color3.fromRGB(10, 20, 50),
		FogStart = 50, FogEnd = 400, Density = 0.25, Haze = 1, AtmosphereColor = Color3.fromRGB(15, 25, 65)
	},

	-- 🌐 PHASE 5: CORPORATE STERILITY (Areas 11-13)
	["Area11_GlassFacility"] = {
		ClockTime = 12, Brightness = 2.0, SunRaysIntensity = 0.4, -- Blinding sudden daylight
		Ambient = Color3.fromRGB(130, 130, 140), FogColor = Color3.fromRGB(200, 220, 240),
		FogStart = 100, FogEnd = 1500, Density = 0.15, Haze = 0, AtmosphereColor = Color3.fromRGB(200, 220, 240)
	},
	["Area12_CrystalLab"] = {
		ClockTime = 14, Brightness = 2.5, SunRaysIntensity = 0.5,
		Ambient = Color3.fromRGB(150, 150, 150), FogColor = Color3.fromRGB(220, 240, 255),
		FogStart = 150, FogEnd = 2500, Density = 0.1, Haze = 0, AtmosphereColor = Color3.fromRGB(220, 240, 255)
	},
	["Area13_QuantumGrid"] = {
		ClockTime = 14, Brightness = 2.2, SunRaysIntensity = 0.3,
		Ambient = Color3.fromRGB(100, 180, 200), FogColor = Color3.fromRGB(150, 255, 255),
		FogStart = 200, FogEnd = 3000, Density = 0.05, Haze = 0, AtmosphereColor = Color3.fromRGB(150, 255, 255)
	},

	-- 🌌 PHASE 6: REALITY BREAKING (Areas 14-16)
	["Area14_PlasmaCore"] = {
		ClockTime = 17.5, Brightness = 1.8, SunRaysIntensity = 0.3,
		Ambient = Color3.fromRGB(150, 80, 150), FogColor = Color3.fromRGB(200, 100, 200),
		FogStart = 100, FogEnd = 2000, Density = 0.2, Haze = 2, AtmosphereColor = Color3.fromRGB(200, 100, 200)
	},
	["Area15_CosmicRift"] = {
		ClockTime = 6, Brightness = 1.5, SunRaysIntensity = 0.2,
		Ambient = Color3.fromRGB(100, 30, 150), FogColor = Color3.fromRGB(70, 0, 100),
		FogStart = 50, FogEnd = 1000, Density = 0.3, Haze = 4, AtmosphereColor = Color3.fromRGB(150, 0, 255)
	},
	["Area16_DarkMatter"] = {
		ClockTime = 0, Brightness = 0.8, SunRaysIntensity = 0,
		Ambient = Color3.fromRGB(80, 10, 20), FogColor = Color3.fromRGB(40, 0, 5),
		FogStart = 30, FogEnd = 600, Density = 0.5, Haze = 6, AtmosphereColor = Color3.fromRGB(120, 0, 10)
	},

	-- ⬛ PHASE 7: THE VOID (Areas 17-20)
	["Area17_EventHorizon"] = {
		ClockTime = 0, Brightness = 0.4, SunRaysIntensity = 0,
		Ambient = Color3.fromRGB(30, 10, 40), FogColor = Color3.fromRGB(15, 5, 20),
		FogStart = 50, FogEnd = 800, Density = 0.3, Haze = 3, AtmosphereColor = Color3.fromRGB(20, 5, 30)
	},
	["Area18_DeepSpace"] = {
		ClockTime = 0, Brightness = 0.2, SunRaysIntensity = 0,
		Ambient = Color3.fromRGB(15, 15, 25), FogColor = Color3.fromRGB(5, 5, 15),
		FogStart = 100, FogEnd = 1500, Density = 0.15, Haze = 1, AtmosphereColor = Color3.fromRGB(5, 5, 15)
	},
	["Area19_TheAbyss"] = {
		ClockTime = 0, Brightness = 0.05, SunRaysIntensity = 0,
		Ambient = Color3.fromRGB(5, 5, 5), FogColor = Color3.fromRGB(2, 2, 2),
		FogStart = 200, FogEnd = 3000, Density = 0.05, Haze = 0, AtmosphereColor = Color3.fromRGB(2, 2, 2)
	},
	["Area20_UniversalVoid"] = {
		ClockTime = 0, Brightness = 0, SunRaysIntensity = 0,
		Ambient = Color3.fromRGB(0, 0, 0), FogColor = Color3.fromRGB(0, 0, 0),
		FogStart = 500, FogEnd = 5000, Density = 0, Haze = 0, AtmosphereColor = Color3.fromRGB(0, 0, 0)
	}
}

AreaRegistry.Areas = {
	-- [ TUTORIAL AREAS 1-5 KEPT THE SAME ]
	[1] = { name = "Starter Area",     threshold = 0,   valueMultiplier = 1.0, yOffset = -2.7, yRotation = 180, auraPreviewColor = Color3.fromRGB(200, 200, 200), grassColor = Color3.fromRGB(92, 197, 53), pathColor = Color3.fromRGB(163, 130, 88), ambientColor = Color3.fromRGB(90, 90, 100), fogColor = Color3.fromRGB(180, 200, 220), auraHolderColor = Color3.fromRGB(255, 255, 255), auraHolderGlow = Color3.fromRGB(255, 255, 255), lightingPreset = "Area1_DeepScrapyard" },
	[2] = { name = "Uncommon Area",    threshold = 5e4, valueMultiplier = 1.5, yOffset = -4.5, yRotation = 180, auraPreviewColor = Color3.fromRGB(100, 200, 100), grassColor = Color3.fromRGB(104, 160, 98), pathColor = Color3.fromRGB(132, 140, 81), ambientColor = Color3.fromRGB(80, 100, 80), fogColor = Color3.fromRGB(160, 200, 160), auraHolderColor = Color3.fromRGB(187, 255, 183), auraHolderGlow = Color3.fromRGB(100, 255, 100), lightingPreset = "Area2_RustyWastes" },
	[3] = { name = "Rare Area",        threshold = 5e5, valueMultiplier = 4.0, yOffset = -2.8, yRotation = 180, auraPreviewColor = Color3.fromRGB(80, 120, 220), grassColor = Color3.fromRGB(2, 226, 170), pathColor = Color3.fromRGB(22, 81, 168), ambientColor = Color3.fromRGB(70, 80, 130), fogColor = Color3.fromRGB(92, 169, 220), auraHolderColor = Color3.fromRGB(75, 87, 255), auraHolderGlow = Color3.fromRGB(56, 86, 255), lightingPreset = "Area3_IndustrialOutskirts" },
	[4] = { name = "Epic Area",        threshold = 5e6, valueMultiplier = 8.0, yOffset = -2.8, yRotation = 180, auraPreviewColor = Color3.fromRGB(180, 80, 220), grassColor = Color3.fromRGB(154, 102, 175), pathColor = Color3.fromRGB(71, 34, 90), ambientColor = Color3.fromRGB(90, 50, 120), fogColor = Color3.fromRGB(160, 120, 200), auraHolderColor = Color3.fromRGB(220, 160, 255), auraHolderGlow = Color3.fromRGB(180, 60, 255), lightingPreset = "Area4_ChemicalSpill" },
	[5] = { name = "Legendary Area",   threshold = 5e7, valueMultiplier = 20.0,yOffset = -3,   yRotation = 0,   auraPreviewColor = Color3.fromRGB(255, 200, 50), grassColor = Color3.fromRGB(160, 120, 20), pathColor = Color3.fromRGB(180, 150, 60), ambientColor = Color3.fromRGB(140, 120, 60), fogColor = Color3.fromRGB(220, 200, 150), auraHolderColor = Color3.fromRGB(255, 230, 120), auraHolderGlow = Color3.fromRGB(255, 180, 0), lightingPreset = "Area5_BioHazard" },

	-- ✨ THE COSMIC PROGRESSION BEGINS (Egg Inc Style leaps)
	[6] = {
		name            = "Quantum Area",
		threshold       = 5e9, -- 5 Billion
		valueMultiplier = 75.0,
		yOffset         = -4.5,
		yRotation       = 180,
		auraPreviewColor = Color3.fromRGB(0, 255, 255),
		grassColor        = Color3.fromRGB(0, 150, 150),
		pathColor         = Color3.fromRGB(0, 100, 100),
		ambientColor      = Color3.fromRGB(50, 200, 200),
		fogColor          = Color3.fromRGB(150, 255, 255),
		auraHolderColor   = Color3.fromRGB(0, 255, 255),
		auraHolderGlow    = Color3.fromRGB(255, 255, 255),
	},
	[7] = {
		name            = "Cosmic Area",
		threshold       = 5e12, -- 5 Trillion
		valueMultiplier = 350.0,
		yOffset         = -4.5,
		yRotation       = 180,
		auraPreviewColor = Color3.fromRGB(138, 43, 226),
		grassColor        = Color3.fromRGB(75, 0, 130),
		pathColor         = Color3.fromRGB(48, 25, 52),
		ambientColor      = Color3.fromRGB(147, 112, 219),
		fogColor          = Color3.fromRGB(216, 191, 216),
		auraHolderColor   = Color3.fromRGB(138, 43, 226),
		auraHolderGlow    = Color3.fromRGB(255, 0, 255),
	},
	[8] = {
		name            = "Tachyon Area",
		threshold       = 5e15, -- 5 Quadrillion
		valueMultiplier = 2500.0,
		yOffset         = -4.5,
		yRotation       = 180,
		auraPreviewColor = Color3.fromRGB(255, 255, 0),
		grassColor        = Color3.fromRGB(200, 200, 0),
		pathColor         = Color3.fromRGB(255, 140, 0),
		ambientColor      = Color3.fromRGB(255, 215, 0),
		fogColor          = Color3.fromRGB(255, 250, 205),
		auraHolderColor   = Color3.fromRGB(255, 255, 0),
		auraHolderGlow    = Color3.fromRGB(255, 165, 0),
	},
	[9] = {
		name            = "Dark Matter Area",
		threshold       = 5e19, -- 50 Quintillion
		valueMultiplier = 50000.0,
		yOffset         = -4.5,
		yRotation       = 180,
		auraPreviewColor = Color3.fromRGB(20, 0, 0),
		grassColor        = Color3.fromRGB(15, 15, 15),
		pathColor         = Color3.fromRGB(30, 0, 0),
		ambientColor      = Color3.fromRGB(50, 0, 0),
		fogColor          = Color3.fromRGB(10, 0, 0),
		auraHolderColor   = Color3.fromRGB(0, 0, 0),
		auraHolderGlow    = Color3.fromRGB(255, 0, 0),
	},
	[10] = {
		name            = "Universal Area",
		threshold       = 5e25, -- 50 Septillion
		valueMultiplier = 1000000.0,
		yOffset         = -4.5,
		yRotation       = 180,
		auraPreviewColor = Color3.fromRGB(255, 255, 255),
		grassColor        = Color3.fromRGB(240, 248, 255),
		pathColor         = Color3.fromRGB(211, 211, 211),
		ambientColor      = Color3.fromRGB(255, 250, 250),
		fogColor          = Color3.fromRGB(255, 255, 255),
		auraHolderColor   = Color3.fromRGB(255, 255, 255),
		auraHolderGlow    = Color3.fromRGB(255, 215, 0),
	},
}

---------------------------------------------------------------
-- BASIC GETTERS
---------------------------------------------------------------
function AreaRegistry.Get(idx)            return AreaRegistry.Areas[idx] end
function AreaRegistry.GetName(idx)        return (AreaRegistry.Areas[idx] and AreaRegistry.Areas[idx].name) or ("Area "..idx) end
function AreaRegistry.GetThreshold(idx)   return AreaRegistry.Areas[idx] and AreaRegistry.Areas[idx].threshold or nil end
function AreaRegistry.GetMultiplier(idx)  return (AreaRegistry.Areas[idx] and AreaRegistry.Areas[idx].valueMultiplier) or 1.0 end
function AreaRegistry.GetYOffset(idx)     return (AreaRegistry.Areas[idx] and AreaRegistry.Areas[idx].yOffset)    or 0 end
function AreaRegistry.GetYRotation(idx)   return (AreaRegistry.Areas[idx] and AreaRegistry.Areas[idx].yRotation)  or 0 end
---------------------------------------------------------------
-- LIGHTING GETTER
---------------------------------------------------------------
function AreaRegistry.GetLighting(idx)
	local area = AreaRegistry.Areas[idx]
	if not area or not area.lightingPreset then 
		return AreaRegistry.LightingPresets["ClearDay"] 
	end

	-- Return the preset data
	return AreaRegistry.LightingPresets[area.lightingPreset] or AreaRegistry.LightingPresets["ClearDay"]
end

function AreaRegistry.GetMaxArea()
	local max = 0
	for k in pairs(AreaRegistry.Areas) do if k > max then max = k end end
	return max
end

---------------------------------------------------------------
-- AREA SKIPPING — find the highest area the player qualifies for
---------------------------------------------------------------
-- Returns the best (highest) area index the player can advance to,
-- or nil if they can't advance at all.
-- Scans every area above currentArea; if farmEvaluation meets
-- the threshold, that area is a candidate.  Returns the highest one.
--
-- Example: player is in Area 1 with 6e6 farmEval.
--   Area 2 threshold = 5e5  → qualifies
--   Area 3 threshold = 5e6  → qualifies
--   Area 4 threshold = 5e7  → does NOT qualify
--   Returns 3 (skips Area 2, goes straight to Area 3).
---------------------------------------------------------------
function AreaRegistry.GetBestNextArea(currentArea, farmEvaluation)
	local maxArea  = AreaRegistry.GetMaxArea()
	local bestArea = nil

	for i = currentArea + 1, maxArea do
		local area = AreaRegistry.Areas[i]
		if area and farmEvaluation >= (area.threshold or 0) then
			bestArea = i
		end
	end

	return bestArea
end

---------------------------------------------------------------
-- LEGACY — kept for any old code that still calls CanAdvance.
-- Now uses GetBestNextArea internally.
---------------------------------------------------------------
function AreaRegistry.CanAdvance(currentArea, farmEvaluation)
	local best = AreaRegistry.GetBestNextArea(currentArea, farmEvaluation)
	if best then
		return true, best
	end
	return false, nil
end

return AreaRegistry

-- AuraSpawner
-- Location: ServerScriptService > AuraSpawner

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

local AuraSpawned    = ReplicatedStorage.RemoteEvents:WaitForChild("AuraSpawned")
local ProduceAura    = ReplicatedStorage.RemoteEvents:WaitForChild("ProduceAura")
local UpdateHatchery = ReplicatedStorage.RemoteEvents:WaitForChild("UpdateHatchery")
local UpdateHUD      = ReplicatedStorage.RemoteEvents:WaitForChild("UpdateHUD")
local HabitatFull    = ReplicatedStorage.RemoteEvents:WaitForChild("HabitatFull")
local CubeMutated    = ReplicatedStorage.RemoteEvents:WaitForChild("CubeMutated")

local HABITAT_HOLDER = workspace:WaitForChild("HabitatHolder")
local HABITAT_PART = HABITAT_HOLDER:WaitForChild("Position")
local lastFire          = {}
local holdStart         = {}
local hatchery          = {}
local clickSessionStart = {}

local function GetHatcheryMax(data)
	local cfg = UpgradeConfig.GetUpgradeConfig("hatcheryCapacity")
	return (cfg and cfg.apply) and cfg.apply(data) or AdminConfig.HatcheryMax
end

local function GetHabitatCapacity(data)
	local cfg = UpgradeConfig.GetUpgradeConfig("habitatCapacity")
	return (cfg and cfg.apply) and cfg.apply(data) or AdminConfig.BaseHabitatCapacity
end

local function GetMutationSpeedMult(data)
	local cfg = UpgradeConfig.GetUpgradeConfig("mutationSpeed")
	return (cfg and cfg.apply) and cfg.apply(data) or 1
end

Players.PlayerAdded:Connect(function(p)
	hatchery[p.UserId] = AdminConfig.HatcheryMax
	clickSessionStart[p.UserId] = nil
end)
Players.PlayerRemoving:Connect(function(p)
	hatchery[p.UserId]=nil; holdStart[p.UserId]=nil
	lastFire[p.UserId]=nil; clickSessionStart[p.UserId]=nil
end)

task.spawn(function()
	local PR = ServerScriptService:WaitForChild("PrestigeReset", 30)
	if PR then
		PR.Event:Connect(function(player)
			local uid = player.UserId
			local data = GameManager.GetData(uid)
			hatchery[uid] = data and GetHatcheryMax(data) or AdminConfig.HatcheryMax
			holdStart[uid]=nil; lastFire[uid]=nil; clickSessionStart[uid]=nil
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
			if holdStart[uid] then
				hatchery[uid] = math.max(0, prev - AdminConfig.HatcheryDrainRate * 0.1)
			else
				hatchery[uid] = math.min(hatchMax, prev + AdminConfig.HatcheryRefillRate * 0.1)
			end
			if hatchery[uid] ~= prev then
				UpdateHatchery:FireClient(player, { current=hatchery[uid], max=hatchMax })
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

local function SendHUDUpdate(player)
	local uid = player.UserId
	local data = GameManager.GetData(uid)
	local runtime = GameManager.GetRuntime(uid)
	if not data or not runtime then return end
	local totalMV = runtime.totalMutatedValue or 0
	local pending = runtime.cubeCount
	local avgVal  = pending > 0 and (totalMV/pending) or AdminConfig.BaseAuraValue
	local rate    = math.floor(pending * avgVal)
	local passTickCfg = UpgradeConfig.GetUpgradeConfig("passiveTickSpeed")

	local passInt = (passTickCfg and passTickCfg.apply) and passTickCfg.apply(data) or AdminConfig.PassiveInterval
	local displayRate = math.floor(rate * BoostManager.GetValueMultiplier(uid) * BoostManager.GetSpawnRateMultiplier(uid))
	UpdateHUD:FireClient(player, {
		currency=data.currency, pendingAuras=pending,
		habitatCapacity=GetHabitatCapacity(data), rate=displayRate,
		passiveInterval=passInt, totalEarned=data.totalEarned or 0,
		soulAuras=data.soulAuras or 0, farmEvaluation=data.farmEvaluation or 0,
		goldenAuras=data.goldenAuras or 0, boostInventory=data.boostInventory or {},
		prestigeCount=data.prestigeCount or 0,
		upgrades=data.upgrades or {},
		totalCubesProduced = data.totalCubesProduced or 0,
		currentArea        = data.currentArea or 1,
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
						cubeId = cubeId, 
						mutationType = "valueBonus",
						bonusLevel = nl, 
						bonusPercent = be and math.floor(be.bonus * 100) or 0 
					})
				end

				local maxTier = AdminConfig.MutationMaxTierIndex or 3
				local upgrades = 0

				while cube.tierIndex < maxTier and cube.tierIndex < #TierConfig.Tiers and upgrades < 5 do
					local timeSince = cube.effectiveElapsed - (cube.lastUpgradeElapsed or 0)
					local bestChance, bestTime = 0, 0

					for _, threshold in ipairs(MutationConfig.TierUpgrades) do
						if timeSince >= threshold.time then 
							bestChance = threshold.chance
							bestTime = threshold.time 
						end
					end

					if bestChance <= 0 then break end

					if math.random() <= bestChance then
						local oldTier = TierConfig.Tiers[cube.tierIndex]
						cube.tierIndex += 1
						local newTier = TierConfig.Tiers[cube.tierIndex]

						cube.baseValue = math.floor(cube.baseValue * (newTier.multiplier/oldTier.multiplier))
						cube.color = newTier.color
						cube.glow = newTier.glow
						cube.tierName = newTier.name
						cube.lastUpgradeElapsed = (cube.lastUpgradeElapsed or 0) + bestTime
						upgrades += 1
						mutated = true

						table.insert(mutationBatch, { 
							cubeId = cubeId, 
							mutationType = "tierUpgrade",
							newColor = newTier.color, 
							newGlow = newTier.glow, 
							tierName = newTier.name 
						})

						if newTier.name == "Legendary" then
							data.totalLegendaryCubes = (data.totalLegendaryCubes or 0) + 1
						end
					else 
						break 
					end
				end

				if mutated then
					local newMutatedValue = MutationConfig.GetMutatedValue(cube)
					runtime.totalMutatedValue = (runtime.totalMutatedValue or 0) + (newMutatedValue - oldMutatedValue)
				end
			end

			if #mutationBatch > 0 then
				ReplicatedStorage.RemoteEvents.CubeMutatedBatch:FireClient(player, mutationBatch)
			end

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
	local mythicData = upgrades["unlockMythicMult"]
	local mythicLevel = (typeof(mythicData) == "table" and mythicData.level) or (typeof(mythicData) == "number" and mythicData) or 0
	if mythicLevel > 0 then playerMaxTier = 6 end

	local effectiveTime = holdTime * playerMultSpeed
	local currentTier = 1

	for i = 1, playerMaxTier do
		if AdminConfig.MilestoneData[i] and effectiveTime >= AdminConfig.MilestoneData[i].time then
			currentTier = i
		end
	end

	local nextTier = math.min(currentTier + 1, playerMaxTier)
	if currentTier == playerMaxTier then
		return AdminConfig.MilestoneData[currentTier].mult, AdminConfig.MilestoneData[currentTier].luck
	end

	local timePassed = effectiveTime - AdminConfig.MilestoneData[currentTier].time
	local timeNeeded = AdminConfig.MilestoneData[nextTier].time - AdminConfig.MilestoneData[currentTier].time
	local ratio = timePassed / timeNeeded

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
		if tier.name ~= "Common" then chance += luckBonus/(#tiers-1) end
		table.insert(adjusted, { tier=tier, chance=chance }); total += chance
	end
	local r, cum = math.random()*total, 0
	for _, e in ipairs(adjusted) do
		cum += e.chance; if r <= cum then return e.tier end
	end
	return tiers[1]
end

local function SpawnAura(player, data, runtime, holdMult, luckBonus)
	local uid  = player.UserId
	local tier = RollWithLuck(luckBonus)
	local tierIndex = 1
	for i, t in ipairs(TierConfig.Tiers) do if t.name == tier.name then tierIndex=i; break end end

	local totalValueMultiplier = 1.0 
	local valueUpgrades = {
		"blockValue", "blockValueT2", "auraValueT3", 
		"auraValueT4", "auraValueT6", "auraValueT8", "auraValueT10"
	}

	for _, upgradeId in ipairs(valueUpgrades) do
		local cfg = UpgradeConfig.GetUpgradeConfig(upgradeId)
		if cfg and cfg.apply then
			totalValueMultiplier += cfg.apply(data) 
		end
	end

	local prestigeMult    = PrestigeModule.GetMultiplier(data.soulAuras)
	local areaMult        = AreaRegistry.GetMultiplier(data.currentArea or 1)
	local boostValueMult  = BoostManager.GetValueMultiplier(uid)
	local _, weatherValueMult = WeatherManager.GetMultipliers(uid)

	local baseValue  = math.floor(AdminConfig.BaseAuraValue * tier.multiplier * totalValueMultiplier * prestigeMult * areaMult * boostValueMult * weatherValueMult)
	local totalValue = baseValue + math.floor(baseValue * (holdMult - 1))

	local spawnPos = HABITAT_PART.Position + Vector3.new(math.random(-3,3), 10, math.random(-3,3))	
	local cubeRecord = {
		spawnTime=tick(), effectiveElapsed=0, lastUpgradeElapsed=0,
		baseValue=totalValue, tierIndex=tierIndex,
		tierName=tier.name, color=tier.color, glow=tier.glow,
	}
	if AdminConfig.MutationInstantMax then
		local mb = MutationConfig.ValueBonuses[#MutationConfig.ValueBonuses]
		if mb then cubeRecord.effectiveElapsed = mb.time + 1 end
	end

	local cubeId = GameManager.AddCube(uid, cubeRecord)
	if not cubeId then return end
	data.totalCubesProduced = (data.totalCubesProduced or 0) + 1
	if tier.name == "Legendary" then data.totalLegendaryCubes = (data.totalLegendaryCubes or 0) + 1 end
	runtime.lastActiveTime = tick()

	AuraSpawned:FireClient(player, {
		cubeId=cubeId, tier=tier.name, color=tier.color,
		glow=tier.glow, value=totalValue, spawnPos=spawnPos,
	})
end

ProduceAura.OnServerEvent:Connect(function(player, action)
	local uid = player.UserId
	local now = tick()
	local data    = GameManager.GetData(uid)
	local runtime = GameManager.GetRuntime(uid)

	if action == "start" then 
		if data and runtime and runtime.cubeCount >= GetHabitatCapacity(data) then
			HabitatFull:FireClient(player)
			return
		end

		-- ✨ Require at least 0.5 juice to start holding so it doesn't instantly die
		if (hatchery[uid] or 0) > 0.5 then 
			holdStart[uid] = now 
		else
			UpdateHatchery:FireClient(player, { current = 0, max = data and GetHatcheryMax(data) or AdminConfig.HatcheryMax })
		end
		return 
	end

	if action == "stop" then 
		holdStart[uid] = nil
		return 
	end

	if not data or not runtime then return end

	if runtime.cubeCount >= GetHabitatCapacity(data) then 
		HabitatFull:FireClient(player)
		return 
	end

	if (hatchery[uid] or 0) <= 0.5 then 
		UpdateHatchery:FireClient(player, { current = 0, max = data and GetHatcheryMax(data) or AdminConfig.HatcheryMax })
		return 
	end

	if not holdStart[uid] then return end

	local rushMult = BoostManager.GetSpawnRateMultiplier(uid)
	local weatherSpawnMult, _ = WeatherManager.GetMultipliers(uid)
	local effectiveFireRate = AdminConfig.FireRate / (rushMult * weatherSpawnMult)
	if lastFire[uid] then
		local timeSinceLast = now - lastFire[uid]
		if timeSinceLast > 3 then clickSessionStart[uid] = now end
		if not clickSessionStart[uid] then clickSessionStart[uid] = now end
		local sessionLength = now - clickSessionStart[uid]
		if sessionLength > 300 then effectiveFireRate *= 2 end
		if sessionLength > 600 then effectiveFireRate *= 4 end
		if timeSinceLast < effectiveFireRate then return end
	else
		clickSessionStart[uid] = now
	end
	lastFire[uid] = now

	local holdTime = now - holdStart[uid]
	local holdMult, luckBonus = GetHoldMultiplier(holdTime, data)
	SpawnAura(player, data, runtime, holdMult, luckBonus)
	SendHUDUpdate(player)
	UpdateHatchery:FireClient(player, { current=hatchery[uid], max=GetHatcheryMax(data) })
end)

local AdminConfig = require(game:GetService("ReplicatedStorage").Modules.AdminConfig)

local TierConfig = {}

TierConfig.Tiers = {
	{ name = "Common",    chance = 0.75,   multiplier = 1,   color = Color3.fromRGB(220, 220, 220), glow = false },
	{ name = "Uncommon",  chance = 0.17,   multiplier = 1.5, color = Color3.fromRGB(80, 200, 80),   glow = true  },
	{ name = "Rare",      chance = 0.06,   multiplier = 3,   color = Color3.fromRGB(60, 120, 255),  glow = true  },
	{ name = "Epic",      chance = 0.018,  multiplier = 8,   color = Color3.fromRGB(180, 60, 255),  glow = true  },
	{ name = "Legendary", chance = 0.002,  multiplier = 25,  color = Color3.fromRGB(255, 200, 0),   glow = true  },
}

if AdminConfig.TierOverride then
	TierConfig.Tiers = AdminConfig.TierOverride
end

function TierConfig.Roll()
	local r = math.random()
	local cumulative = 0
	for _, tier in ipairs(TierConfig.Tiers) do
		cumulative += tier.chance
		if r <= cumulative then return tier end
	end
	return TierConfig.Tiers[1]
end

return TierConfig


-- GameManager
-- Location: ServerScriptService > GameManager (ModuleScript)
--
-- FIXES:
--   hasPrestigedThisArea now resets in WipePrestigeOnLoad AND WipeAreaOnLoad
--   AND WipeMoneyOnLoad. Any wipe = fresh prestige state.
--   All Phase 4 fields in DefaultData + safety net after wipes.
--   TutorialStepComplete handler at bottom.

local DataStoreService  = game:GetService("DataStoreService")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDB      = DataStoreService:GetDataStore("PlayerData_v1")
local AdminConfig   = require(ReplicatedStorage.Modules.AdminConfig)
local UpgradeConfig = require(ReplicatedStorage.Modules.UpgradeConfig)
local MutationConfig = require(ReplicatedStorage.Modules.MutationConfig)

local SAVE_COOLDOWN = 7

local function DefaultData()
	return {
		currency      = 0,
		totalEarned   = 0,
		soulAuras     = 0,
		prestigeCount = 0,

		pendingAuras        = 0,
		pendingPayout       = 0,
		pendingBonusPayout  = 0,
		lastPayout          = 0,

		upgrades = {
			dropRate           = 0,
			blockValue         = 0,
			habitatCapacity    = 0,
			autoShipper        = 0,
			mutationSpeed      = 0,
			mutationTierChance = 0,
			passiveTickSpeed   = 0,
			hatcheryCapacity   = 0,
		},

		piggyBank       = 0,
		piggyBankBroken = 0,

		totalCubesProduced    = 0,
		totalPlatformsShipped = 0,
		totalLegendaryCubes   = 0,

		missions = {},

		settings = {
			sfxEnabled   = true,
			musicEnabled = true,
		},

		farmEvaluation = 0,
		currentArea    = 1,
		unlockedAreas  = { 1 },

		goldenAuras = AdminConfig.GoldenAuraStart or 10,

		boostInventory = {
			AuraRush   = 0,
			SpawnBoost = 0,
			SoulBoost  = 0,
		},

		hasPrestigedThisArea = false,
		epicUpgrades         = {},
		tutorialProgress     = {},
		tutorialComplete     = false,
		claimedMail          = {},
		unlockedMail         = {},
	}
end

local function DefaultRuntime()
	return {
		cubes          = {},
		cubeOrder      = {},
		cubeCount      = 0,
		nextCubeId     = 1,
		totalMutatedValue = 0, -- NEW: Track the total value instantly
		lastActiveTime = tick(),
		sessionStart   = tick(),
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
		elseif type(defaultValue) == "table" and type(saved[key]) == "table"
			and not getmetatable(saved[key]) then
			if defaultValue[1] == nil then
				DeepMerge(saved[key], defaultValue)
			end
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
	if not hasCurrent and data.currentArea ~= 1 then
		table.insert(data.unlockedAreas, data.currentArea)
	end
end

local function SaveData(player)
	local uid  = player.UserId
	local data = PlayerData[uid]
	if not data then return end
	local now, last = tick(), lastSaveTick[uid] or 0
	if now - last >= SAVE_COOLDOWN then
		lastSaveTick[uid] = now
		local ok, err = pcall(function() PlayerDB:SetAsync("Player_" .. uid, data) end)
		if not ok then warn("[GameManager] SaveData failed for", player.Name, ":", err) end
	else
		if not pendingSave[uid] then
			pendingSave[uid] = true
			task.delay(SAVE_COOLDOWN - (now - last) + 0.5, function()
				pendingSave[uid] = nil
				if player and player.Parent and PlayerData[uid] then
					local ok, err = pcall(function() PlayerDB:SetAsync("Player_" .. uid, PlayerData[uid]) end)
					lastSaveTick[uid] = tick()
					if not ok then warn("[GameManager] Deferred save failed for", player.Name, ":", err) end
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

	EnsureUnlockedAreas(PlayerData[player.UserId])
	PlayerRuntime[player.UserId] = DefaultRuntime()

	local d = PlayerData[player.UserId]

	if AdminConfig.WipeMoneyOnLoad then
		d.currency           = 0
		d.totalEarned        = 0
		d.pendingAuras       = 0
		d.pendingPayout      = 0
		d.pendingBonusPayout = 0
		d.lastPayout         = 0
		for k in pairs(d.upgrades) do d.upgrades[k] = 0 end
		d.totalCubesProduced    = 0
		d.totalPlatformsShipped = 0
		d.totalLegendaryCubes   = 0
		d.piggyBank             = 0
		d.piggyBankBroken       = 0
		d.farmEvaluation        = 0
		d.goldenAuras           = AdminConfig.GoldenAuraStart or 10
		d.boostInventory        = { AuraRush = 0, SpawnBoost = 0, SoulBoost = 0 }
		d.hasPrestigedThisArea  = false   -- FIX: reset on money wipe
		d.claimedMail = {}           -- ADD THIS: reset claimed mail
		d.tutorialProgress = {}      -- ADD THIS: reset tutorial popups
		d.tutorialComplete = false   -- ADD THIS: reset tutorial lockout
	end

	if AdminConfig.WipePrestigeOnLoad then
		d.soulAuras            = 0
		d.prestigeCount        = 0
		d.hasPrestigedThisArea = false   -- FIX: reset on prestige wipe
	end

	if AdminConfig.WipeAreaOnLoad then
		d.currentArea          = 1
		d.farmEvaluation       = 0
		d.unlockedAreas        = { 1 }
		d.hasPrestigedThisArea = false   -- FIX: reset on area wipe
	end
	
	if AdminConfig.WipeEpicOnLoad then
		d.GoldenAuras = 0
		d.epicUpgrades = {}
	end
	
	if AdminConfig.WipeAchievementsOnLoad then
		d.totalCubesProduced = 0
		d.totalLegendaryCubes = 0
		d.totalPlatformsShipped = 0
	end

	-- Safety: Phase 4 fields always exist, never wiped
	if not d.epicUpgrades     then d.epicUpgrades     = {} end
	if not d.tutorialProgress then d.tutorialProgress = {} end
	if d.tutorialComplete == nil then d.tutorialComplete = false end
	if not d.claimedMail      then d.claimedMail      = {} end
	if not d.unlockedMail     then d.unlockedMail     = {} end
	if d.hasPrestigedThisArea == nil then d.hasPrestigedThisArea = false end

	task.wait(1)

	local habCfg = UpgradeConfig.GetUpgradeConfig("habitatCapacity")
	local habCap  = (habCfg and habCfg.apply) and habCfg.apply(d) or AdminConfig.BaseHabitatCapacity
	local tickCfg = UpgradeConfig.GetUpgradeConfig("passiveTickSpeed")
	local passInt = (tickCfg and tickCfg.apply) and tickCfg.apply(d) or AdminConfig.PassiveInterval

	ReplicatedStorage.RemoteEvents.UpdateHUD:FireClient(player, {
		currency             = d.currency,
		pendingAuras         = 0,
		habitatCapacity      = habCap,
		rate                 = 0,
		passiveInterval      = passInt,
		totalEarned          = d.totalEarned        or 0,
		soulAuras            = d.soulAuras          or 0,
		farmEvaluation       = d.farmEvaluation     or 0,
		goldenAuras          = d.goldenAuras        or 0,
		boostInventory       = d.boostInventory     or {},
		settings             = d.settings           or {},
		prestigeCount        = d.prestigeCount      or 0,
		hasPrestigedThisArea = d.hasPrestigedThisArea or false,
		tutorialProgress     = d.tutorialProgress   or {},
		tutorialComplete     = d.tutorialComplete   or false,
		epicUpgrades         = d.epicUpgrades       or {},
		totalCubesProduced   = d.totalCubesProduced or 0,
		currentArea          = d.currentArea or 1,
	})

	-- FIX: Send UpgradeUpdated fullState so ShopController has data on join
	-- This fires AFTER UpdateHUD so the shop has both currency AND upgrade state
	-- FIX: Send UpgradeUpdated fullState so ShopController has data on join
	task.delay(0.5, function()
		if not player or not player.Parent then return end
		local resetState = {}

		-- SURGICAL FIX: Use Tiered Loop and New CalculateCost function
		for tierNum, tierData in ipairs(UpgradeConfig.Tiers) do
			for upgradeId, cfg in pairs(tierData.upgrades) do
				local lv = d.upgrades[upgradeId] or 0
				local maxed = lv >= cfg.maxLevel

				resetState[upgradeId] = {
					level    = lv,
					maxLevel = cfg.maxLevel,
					cost     = maxed and 0 or UpgradeConfig.CalculateCost(upgradeId, lv),
					maxed    = maxed,
				}
			end
		end

		local UpgradeUpdated = ReplicatedStorage.RemoteEvents:FindFirstChild("UpgradeUpdated")
		if UpgradeUpdated then
			UpgradeUpdated:FireClient(player, {
				type     = "fullState",
				upgrades = resetState,
				currency = d.currency,
			})
		end
	end)
end

Players.PlayerAdded:Connect(LoadData)
Players.PlayerRemoving:Connect(function(player)
	local uid  = player.UserId
	local data = PlayerData[uid]
	if data then pcall(function() PlayerDB:SetAsync("Player_" .. uid, data) end) end
	pendingSave[uid]   = nil
	lastSaveTick[uid]  = nil
	PlayerData[uid]    = nil
	PlayerRuntime[uid] = nil
end)

local lastPeriodicSave = tick()
game:GetService("RunService").Heartbeat:Connect(function()
	if tick() - lastPeriodicSave >= 60 then
		lastPeriodicSave = tick()
		for _, p in ipairs(Players:GetPlayers()) do SaveData(p) end
	end
end)

---------------------------------------------------------------
-- TutorialStepComplete handler
---------------------------------------------------------------
task.spawn(function()
	local TutorialStepComplete = ReplicatedStorage.RemoteEvents:WaitForChild("TutorialStepComplete", 10)
	if not TutorialStepComplete then return end
	TutorialStepComplete.OnServerEvent:Connect(function(player, stepId)
		local uid  = player.UserId
		local data = PlayerData[uid]
		if not data then return end
		if not data.tutorialProgress then data.tutorialProgress = {} end
		if stepId == "__tutorialComplete__" then
			data.tutorialComplete = true
		elseif type(stepId) == "string" and #stepId < 100 then
			data.tutorialProgress[stepId] = true
		end
	end)
end)

---------------------------------------------------------------
-- Public API
---------------------------------------------------------------
local GameManager = {}

function GameManager.GetData(uid)    return PlayerData[uid]    end
function GameManager.GetRuntime(uid) return PlayerRuntime[uid] end
function GameManager.SavePlayer(p)   SaveData(p)               end

function GameManager.AddCube(uid, cubeRecord)
	local runtime = PlayerRuntime[uid]
	if not runtime then return nil end
	local id = runtime.nextCubeId
	runtime.nextCubeId += 1	
	runtime.cubes[id] = cubeRecord
	runtime.totalMutatedValue += MutationConfig.GetMutatedValue(cubeRecord)
	table.insert(runtime.cubeOrder, id)
	runtime.cubeCount += 1
	return id
end

function GameManager.RemoveCube(uid, cubeId)
	local runtime = PlayerRuntime[uid]
	if not runtime or not runtime.cubes[cubeId] then return end
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

				-- 1. Grab the value BEFORE deleting it!
				local valToRemove = MutationConfig.GetMutatedValue(runtime.cubes[cubeId])
				runtime.totalMutatedValue -= valToRemove

				-- 2. NOW delete it
				runtime.cubes[cubeId] = nil
				runtime.cubeCount -= 1
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
	for _, player in ipairs(Players:GetPlayers()) do
		SaveData(player)
	end
	task.wait(2) -- Give DataStoreService a moment to flush the queues
end)

return GameManager

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
	pop.Font = Enum.Font.FredokaOne 
	pop.TextScaled = true
	pop.TextColor3 = data.color
	pop.BackgroundTransparency = 1
	pop.AnchorPoint = Vector2.new(0.5, 0.5)

	-- ✨ MOBILE FIX 1: Starts floating 15% above the button instead of 120 pixels
	pop.Position = UDim2.new(
		ClickButton.Position.X.Scale, ClickButton.Position.X.Offset, 
		ClickButton.Position.Y.Scale - 0.15, ClickButton.Position.Y.Offset
	)
	pop.Parent = ClickButton.Parent

	local stroke = Instance.new("UIStroke", pop)
	stroke.Thickness = 3
	stroke.Color = Color3.fromRGB(0, 0, 0)

	-- ✨ MOBILE FIX 2: Tiny starting size using Scale instead of flat pixels
	pop.Size = UDim2.new(0.1, 0, 0.02, 0) 

	-- ✨ MOBILE FIX 3: Grows to 35% of the screen width, and floats up an extra 10%
	TweenService:Create(pop, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0.35, 0, 0.08, 0),
		Position = UDim2.new(
			pop.Position.X.Scale, pop.Position.X.Offset, 
			ClickButton.Position.Y.Scale - 0.25, ClickButton.Position.Y.Offset
		)
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
	-- ✨ FIX: Check our local prediction to bypass server lag on spam purchases
	local finalMax = info.max
	local localHatchLvl = player:GetAttribute("LocalHatcheryLevel")

	if localHatchLvl then
		local UpgradeConfig = require(ReplicatedStorage.Modules.UpgradeConfig)
		local cfg = UpgradeConfig.GetUpgradeConfig("hatcheryCapacity")
		if cfg and cfg.apply then
			local predictedMax = cfg.apply({ upgrades = { hatcheryCapacity = { level = localHatchLvl } } })
			finalMax = math.max(info.max, predictedMax)
		end
	end

	UpdateHatcheryBar(info.current, finalMax)
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

-- AchievementController
-- Location: StarterPlayer > StarterPlayerScripts > AchievementController

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local UITheme           = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("UITheme"))
local T                 = UITheme.Get("Custom")
local SoundConfig       = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SoundConfig"))
local AchievementConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("AchievementConfig"))
local TierConfig        = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("TierConfig"))
local UpdateHUD         = ReplicatedStorage.RemoteEvents:WaitForChild("UpdateHUD")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainHUD   = playerGui:WaitForChild("MainHUD")
local Faded2 = mainHUD:WaitForChild("Faded2") 
local panelOpen = false
local activeTab = "Challenges"
local activeTabText = "Boosts" -- For the hover label
local latestStats = {}

local function PlayUI(id) if shared.PlayUISound then shared.PlayUISound(id) end end

---------------------------------------------------------------
-- 1. THE CIRCULAR BUTTON (Right Side of Faded2)
---------------------------------------------------------------
local AchieveBtn = Instance.new("ImageButton", Faded2) -- ✨ PARENTED TO FADED2
AchieveBtn.Name = "AchievementButton"
AchieveBtn.Size = UDim2.new(0.85, 0, 0.85, 0) -- ✨ Takes up 85% of Faded2's height
AchieveBtn.Position = UDim2.new(0.95, 0, 0.5, 0) -- ✨ Placed on the far right
AchieveBtn.AnchorPoint = Vector2.new(1, 0.5) -- ✨ Anchored perfectly center-right
AchieveBtn.BackgroundColor3 = T.buttonSecondary
AchieveBtn.BorderSizePixel = 0
AchieveBtn.AutoButtonColor = false
AchieveBtn.ZIndex = 15
Instance.new("UICorner", AchieveBtn).CornerRadius = UDim.new(0.5, 0)

-- ✨ MOBILE FIX: Forces it to stay a perfect circle no matter the screen size!
local achieveAspect = Instance.new("UIAspectRatioConstraint", AchieveBtn)
achieveAspect.AspectRatio = 1.0 

local btnStroke = Instance.new("UIStroke", AchieveBtn)
btnStroke.Color = T.accentGold; btnStroke.Thickness = 1

local btnIcon = Instance.new("ImageLabel", AchieveBtn)
btnIcon.Size = UDim2.new(0.7, 0, 0.7, 0)
btnIcon.Position = UDim2.new(0.15, 0, 0.15, 0)
btnIcon.BackgroundTransparency = 1; btnIcon.ScaleType = Enum.ScaleType.Fit
btnIcon.Image = "rbxassetid://14916846070"

---------------------------------------------------------------
-- 2. THE MAIN PANEL & HEADER
---------------------------------------------------------------
local Panel = Instance.new("Frame", mainHUD)
Panel.Name = "AchievementPanel"; Panel.Size = UDim2.new(0.85, 0, 0.75, 0); Panel.Position = UDim2.new(0.5, 0, 0.5, 0); Panel.AnchorPoint = Vector2.new(0.5, 0.5)
Panel.BackgroundColor3 = T.panelBG; Panel.BorderSizePixel = 0; Panel.Visible = false; Panel.ZIndex = 40; Panel.ClipsDescendants = true
Instance.new("UICorner", Panel).CornerRadius = UDim.new(0, 12)
local sizeConstraint = Instance.new("UISizeConstraint", Panel); sizeConstraint.MaxSize = Vector2.new(500, 550) 
local panelStroke = Instance.new("UIStroke", Panel); panelStroke.Color = T.panelStroke; panelStroke.Thickness = 2

local Header = Instance.new("Frame", Panel)
Header.Size = UDim2.new(1, 0, 0, 44); Header.BackgroundColor3 = T.headerBG; Header.BorderSizePixel = 0; Header.ZIndex = 41
local TitleLabel = Instance.new("TextLabel", Header); TitleLabel.Size = UDim2.new(1, -50, 1, 0); TitleLabel.Position = UDim2.new(0, 14, 0, 0); TitleLabel.BackgroundTransparency = 1; TitleLabel.Text = "PROGRESSION"; TitleLabel.TextColor3 = T.headerText; TitleLabel.TextScaled = true; TitleLabel.Font = T.font; TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
local CloseBtn = Instance.new("TextButton", Header); CloseBtn.Size = UDim2.new(0, 28, 0, 28); CloseBtn.Position = UDim2.new(1, -36, 0.5, -14); CloseBtn.BackgroundColor3 = T.buttonRed; CloseBtn.Text = "X"; CloseBtn.TextColor3 = T.headerText; CloseBtn.TextScaled = true; CloseBtn.Font = T.font; Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 5); CloseBtn.ZIndex = 9999


---------------------------------------------------------------
-- 3. CIRCULAR TABS & HOVER LABEL
---------------------------------------------------------------
local TabContainer = Instance.new("Frame", Panel)
TabContainer.Size = UDim2.new(1, 0, 0, 75); TabContainer.Position = UDim2.new(0, 0, 0, 44); TabContainer.BackgroundTransparency = 1; TabContainer.ZIndex = 41

local HoverLabel = Instance.new("TextLabel", TabContainer)
HoverLabel.Size = UDim2.new(1, 0, 0, 20); HoverLabel.Position = UDim2.new(0, 0, 1, -15); HoverLabel.BackgroundTransparency = 1
HoverLabel.Text = "Boosts"; HoverLabel.TextColor3 = T.bodyText; HoverLabel.TextScaled = true; HoverLabel.Font = T.font

local TabButtonFrame = Instance.new("Frame", TabContainer)
TabButtonFrame.Size = UDim2.new(1, 0, 1, -20); TabButtonFrame.Position = UDim2.new(0, 0, 0, 0); TabButtonFrame.BackgroundTransparency = 1
local TabListLayout = Instance.new("UIListLayout", TabButtonFrame)
TabListLayout.FillDirection = Enum.FillDirection.Horizontal; TabListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center; TabListLayout.VerticalAlignment = Enum.VerticalAlignment.Center; TabListLayout.Padding = UDim.new(0, 20)

local tabBtns = {}; local scrolls = {}

local function MakeTab(name, hoverText, iconId)
	local btn = Instance.new("ImageButton", TabButtonFrame)
	btn.Size = UDim2.new(0, 45, 0, 45); btn.BackgroundColor3 = T.buttonSecondary; btn.AutoButtonColor = false
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0.5, 0)

	-- ✨ TUTORIAL TAG! Now your tutorial config can target "ChallengesTab", "IndexTab", etc.
	btn:SetAttribute("TutorialTarget", name .. "Tab")

	local tStroke = Instance.new("UIStroke", btn)
	tStroke.Color = T.panelStroke; tStroke.Thickness = 2

	local icon = Instance.new("ImageLabel", btn)
	icon.Size = UDim2.new(0.6, 0, 0.6, 0); icon.Position = UDim2.new(0.2, 0, 0.2, 0); icon.BackgroundTransparency = 1; icon.ScaleType = Enum.ScaleType.Fit; icon.Image = iconId
	tabBtns[name] = {btn = btn, stroke = tStroke}

	-- Mobile-responsive Scrolling Frame
	local sf = Instance.new("ScrollingFrame", Panel)
	sf.Size = UDim2.new(1, -20, 1, -135); sf.Position = UDim2.new(0, 10, 0, 125); sf.BackgroundTransparency = 1; sf.BorderSizePixel = 0; sf.ScrollBarThickness = 4; sf.Visible = false
	local layout = Instance.new("UIListLayout", sf); layout.Padding = UDim.new(0, 8); layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function() sf.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 10) end)
	scrolls[name] = sf

	-- Dynamic Hover Text Logic
	btn.MouseEnter:Connect(function() HoverLabel.Text = hoverText end)
	btn.MouseLeave:Connect(function() HoverLabel.Text = activeTabText end)

	btn.MouseButton1Down:Connect(function()
		PlayUI(SoundConfig.UIClick or "")
		activeTab = name; activeTabText = hoverText; HoverLabel.Text = activeTabText
		for k, t in pairs(tabBtns) do 
			t.btn.BackgroundColor3 = (k == name) and T.accentGold or T.buttonSecondary 
			t.stroke.Color = (k == name) and T.bodyText or T.panelStroke
		end
		for k, s in pairs(scrolls) do s.Visible = (k == name) end
	end)
end

-- 🖼️ PLACEHOLDERS: Replace "rbxassetid://14916846070" with your actual icon IDs!
MakeTab("Challenges", "Boosts", "rbxassetid://14916846070")
MakeTab("Index", "Auras", "rbxassetid://14916846070")
MakeTab("Badges", "Badges", "rbxassetid://14916846070")
MakeTab("Leaderboard", "Top 10", "rbxassetid://14916846070")

---------------------------------------------------------------
-- 4. DYNAMIC CONTENT BUILDER (SMART UPDATES)
---------------------------------------------------------------
local function UpdateOrCreateRow(parent, id, title, desc, hoverDesc, iconImage, iconColor, statusText, statusColor)
	-- Look for an existing row so we don't delete it while the player is hovering!
	local row = parent:FindFirstChild(id)

	if not row then
		-- Create it for the first time
		row = Instance.new("TextButton", parent) -- TextButtons track hovering much better than Frames!
		row.Name = id; row.Text = ""; row.AutoButtonColor = false
		row.Size = UDim2.new(1, -8, 0, 64); row.BackgroundColor3 = T.cardBG
		Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)

		local stroke = Instance.new("UIStroke", row); stroke.Name = "Stroke"; stroke.Thickness = 1

		local icon = Instance.new("ImageLabel", row); icon.Name = "Icon"; icon.Size = UDim2.new(0, 40, 0, 40); icon.Position = UDim2.new(0, 12, 0.5, -20); icon.ScaleType = Enum.ScaleType.Fit; Instance.new("UICorner", icon).CornerRadius = UDim.new(1, 0)

		local tLbl = Instance.new("TextLabel", row); tLbl.Name = "Title"; tLbl.Size = UDim2.new(0.6, 0, 0, 20); tLbl.Position = UDim2.new(0, 64, 0, 10); tLbl.BackgroundTransparency = 1; tLbl.TextColor3 = T.bodyText; tLbl.TextScaled = true; tLbl.Font = T.font; tLbl.TextXAlignment = Enum.TextXAlignment.Left
		local dLbl = Instance.new("TextLabel", row); dLbl.Name = "Desc"; dLbl.Size = UDim2.new(0.6, 0, 0, 16); dLbl.Position = UDim2.new(0, 64, 0, 32); dLbl.BackgroundTransparency = 1; tLbl.TextColor3 = T.subText; dLbl.TextScaled = true; dLbl.Font = T.fontBody; dLbl.TextXAlignment = Enum.TextXAlignment.Left
		local sLbl = Instance.new("TextLabel", row); sLbl.Name = "Status"; sLbl.Size = UDim2.new(0, 80, 0, 24); sLbl.Position = UDim2.new(1, -90, 0.5, -12); sLbl.BackgroundTransparency = 1; sLbl.TextScaled = true; sLbl.Font = T.font; sLbl.TextXAlignment = Enum.TextXAlignment.Right

		UITheme.Apply(row, "Card")

		-- ✨ SMART HOVER LOGIC
		row:SetAttribute("IsHovering", false)
		row.MouseEnter:Connect(function() 
			row:SetAttribute("IsHovering", true)
			local hd = row:GetAttribute("HoverDesc")
			if hd and hd ~= "" then
				row.Desc.Text = hd; row.Desc.TextColor3 = T.accentGold
			end
		end)
		row.MouseLeave:Connect(function() 
			row:SetAttribute("IsHovering", false)
			row.Desc.Text = row:GetAttribute("NormalDesc") or ""; row.Desc.TextColor3 = T.subText 
		end)
	end

	-- ✨ UPDATE THE ROW LIVE (Without deleting it)
	row:SetAttribute("NormalDesc", desc)
	row:SetAttribute("HoverDesc", hoverDesc)

	row.Title.Text = title
	row.Status.Text = statusText
	row.Status.TextColor3 = statusColor
	row.Icon.Image = iconImage
	row.Icon.BackgroundColor3 = iconColor
	row.Stroke.Color = iconColor

	-- Keep the correct text showing based on if their mouse is currently on it
	if row:GetAttribute("IsHovering") and hoverDesc and hoverDesc ~= "" then
		row.Desc.Text = hoverDesc; row.Desc.TextColor3 = T.accentGold
	else
		row.Desc.Text = desc; row.Desc.TextColor3 = T.subText
	end
end

local function RefreshData()
	-- 1. Build Challenges
	for i, chal in ipairs(AchievementConfig.Challenges) do
		local current = latestStats[chal.statKey] or 0
		local isDone = current >= chal.goal
		local statusText = isDone and "UNLOCKED" or (current .. " / " .. chal.goal)
		local statusColor = isDone and T.buttonGreen or T.subText

		local hoverReq = not isDone and ("Requires: " .. chal.desc) or "Boost Unlocked!"

		UpdateOrCreateRow(scrolls["Challenges"], "Chal_"..i, chal.title, chal.rewardText, hoverReq, chal.iconId, T.accentBlue, statusText, statusColor)
	end

	-- 2. Build Aura Index
	for i, tier in ipairs(TierConfig.Tiers) do
		local discovered = (latestStats.totalCubesProduced or 0) > 0
		if tier.name == "Legendary" then discovered = (latestStats.totalLegendaryCubes or 0) > 0 end
		local statusText = discovered and "Found" or "???"
		local statusColor = discovered and T.buttonGreen or T.buttonRed
		UpdateOrCreateRow(scrolls["Index"], "Index_"..i, tier.name .. " Aura", "Multiplier: " .. tier.multiplier .. "x", nil, "rbxassetid://0", tier.color, statusText, statusColor)
	end

	-- 3. Build Badges
	for i, badge in ipairs(AchievementConfig.Badges) do
		UpdateOrCreateRow(scrolls["Badges"], "Badge_"..i, badge.title, badge.desc, nil, badge.iconId, T.accentGold, "BADGE", T.subText)
	end

	-- 4. Leaderboard Placeholder
	UpdateOrCreateRow(scrolls["Leaderboard"], "Leader_1", "1. MoldySugar2205", "Total Earnings", nil, "rbxassetid://0", T.accentGold, "Top Player", T.accentGreen)
end

UpdateHUD.OnClientEvent:Connect(function(stats)
	for key, value in pairs(stats) do latestStats[key] = value end
	if panelOpen then RefreshData() end
end)

---------------------------------------------------------------
-- 5. BUTTON JUICE & OPEN/CLOSE
---------------------------------------------------------------
local function AddButtonJuice(btn)
	local scale = btn:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", btn)
	btn.MouseEnter:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15), {Scale = 1.08}):Play() end)
	btn.MouseLeave:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15), {Scale = 1}):Play() end)
	btn.MouseButton1Down:Connect(function() TweenService:Create(scale, TweenInfo.new(0.1), {Scale = 0.9}):Play() end)
	btn.MouseButton1Up:Connect(function() TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Bounce), {Scale = 1.08}):Play() end)
end

AddButtonJuice(AchieveBtn); AddButtonJuice(CloseBtn)

-- Attach juice to the new circular tabs
for _, t in pairs(tabBtns) do AddButtonJuice(t.btn) end

AchieveBtn.MouseButton1Down:Connect(function()
	if panelOpen then
		-- Close Logic
		PlayUI(SoundConfig.UIClose or "")
		panelOpen = false
		TweenService:Create(Panel, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Size = UDim2.new(0.85, 0, 0, 0)}):Play()
		UITheme.SetMenuVisible(false)
		task.delay(0.25, function() Panel.Visible = false end)
	else
		-- Open Logic
		PlayUI(SoundConfig.UIOpen or "")
		panelOpen = true; Panel.Visible = true; Panel.Size = UDim2.new(0.85, 0, 0, 0)

		for k, t in pairs(tabBtns) do 
			t.btn.BackgroundColor3 = (k == activeTab) and T.accentGold or T.buttonSecondary 
			t.stroke.Color = (k == activeTab) and T.bodyText or T.panelStroke
		end
		scrolls[activeTab].Visible = true
		HoverLabel.Text = activeTabText
		RefreshData()

		TweenService:Create(Panel, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = UDim2.new(0.85, 0, 0.75, 0)}):Play()
		UITheme.SetMenuVisible(true)
	end
end)

CloseBtn.MouseButton1Down:Connect(function()
	PlayUI(SoundConfig.UIClose or ""); panelOpen = false
	TweenService:Create(Panel, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Size = UDim2.new(0.85, 0, 0, 0)}):Play()
	UITheme.SetMenuVisible(false); task.delay(0.25, function() Panel.Visible = false end)
end)

task.spawn(function()
	task.wait(1)
	UITheme.Apply(Panel, "Panel")
	UITheme.Apply(Header, "TitleBar")
	UITheme.ApplyShine(Panel)

end)

-- SoundManager
-- Location: StarterPlayer > StarterPlayerScripts > SoundManager
--
-- MENU GATE: Only the initial area music waits for MenuDismissed.
-- shared.PlayUISound and all event connections work immediately.
-- This ensures other scripts can play sounds during loading.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local SoundService      = game:GetService("SoundService")

local SoundConfig = require(ReplicatedStorage.Modules.SoundConfig)

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local SoundGroup = Instance.new("SoundGroup")
SoundGroup.Name   = "AuraIncSounds"
SoundGroup.Volume = 1
SoundGroup.Parent = SoundService

local soundCache = {}

local function GetOrCreateSound(id, volume, looped)
	if not id or id == "" then return nil end
	local fullId = "rbxassetid://" .. id
	if not soundCache[id] then
		local s = Instance.new("Sound")
		s.SoundId = fullId; s.Volume = volume or 1
		s.Looped  = looped or false; s.RollOffMaxDistance = 0
		s.Parent  = SoundGroup
		soundCache[id] = s
	end
	return soundCache[id]
end

local sfxEnabled   = true
local musicEnabled = true
local MUSIC_VOL    = SoundConfig.Volume and SoundConfig.Volume.music or 0.4

local function Vol(category)
	return SoundConfig.Volume and SoundConfig.Volume[category] or 0.5
end

local function Play(id, volume)
	if not sfxEnabled then return end
	if not id or id == "" then return end
	local s = GetOrCreateSound(id, volume, false)
	if s then s:Play() end
end

-- Expose for other LocalScripts (PrestigeController, PortalController, etc.)
shared.PlayUISound = function(id, volume)
	Play(id, volume or Vol("ui"))
end

---------------------------------------------------------------
-- Hold loop
---------------------------------------------------------------
local loopingSound = nil

local function PlayLoop(id, volume)
	if not sfxEnabled then return end
	if not id or id == "" then return end
	local s = GetOrCreateSound(id, volume, true)
	if s and not s.IsPlaying then s:Play(); loopingSound = s end
end

local function StopLoop()
	if loopingSound and loopingSound.IsPlaying then loopingSound:Stop() end
	loopingSound = nil
end

---------------------------------------------------------------
-- Area music
---------------------------------------------------------------
local currentMusicSound = nil

local function PlayAreaMusic(areaIndex)
	local id = SoundConfig.AreaMusic and SoundConfig.AreaMusic[areaIndex]

	if not id or id == "" then
		if currentMusicSound and currentMusicSound.IsPlaying then
			local old = currentMusicSound; currentMusicSound = nil
			TweenService:Create(old, TweenInfo.new(1.5), { Volume = 0 }):Play()
			task.delay(1.6, function() old:Stop() end)
		end
		return
	end

	local fullId = "rbxassetid://" .. id
	if currentMusicSound and currentMusicSound.SoundId == fullId
		and currentMusicSound.IsPlaying then return end

	if currentMusicSound and currentMusicSound.IsPlaying then
		local old = currentMusicSound; currentMusicSound = nil
		TweenService:Create(old, TweenInfo.new(1.5), { Volume = 0 }):Play()
		task.delay(1.6, function() old:Stop() end)
	end

	task.delay(0.5, function()
		local s = GetOrCreateSound(id, 0, true)
		if not s then return end
		s:Play(); currentMusicSound = s
		local targetVol = musicEnabled and MUSIC_VOL or 0
		TweenService:Create(s, TweenInfo.new(1.5), { Volume = targetVol }):Play()
	end)
end

---------------------------------------------------------------
-- Settings
---------------------------------------------------------------
task.spawn(function()
	local SettingsChanged = ReplicatedStorage:WaitForChild("SettingsChanged", 20)
	if not SettingsChanged then
		warn("[SoundManager] SettingsChanged not found — sound toggles won't work")
		return
	end

	SettingsChanged.Event:Connect(function(settingKey, isOn)
		if settingKey == "sfx" then
			sfxEnabled = isOn
			SoundGroup.Volume = isOn and 1 or 0
			if not isOn then StopLoop() end
		elseif settingKey == "music" then
			musicEnabled = isOn
			if currentMusicSound then
				if currentMusicSound.IsPlaying then
					TweenService:Create(currentMusicSound,
						TweenInfo.new(0.4), { Volume = isOn and MUSIC_VOL or 0 }):Play()
				elseif isOn then
					currentMusicSound:Play()
					TweenService:Create(currentMusicSound,
						TweenInfo.new(1.0), { Volume = MUSIC_VOL }):Play()
				end
			end
		end
	end)
end)

---------------------------------------------------------------
-- UI button hooks (main HUD buttons)
---------------------------------------------------------------
task.spawn(function()
	local mainHUD = playerGui:WaitForChild("MainHUD")

	local function HookOpen(name)
		local btn = mainHUD:WaitForChild(name, 10)
		if btn then
			btn.MouseButton1Down:Connect(function()
				Play(SoundConfig.UIOpen, Vol("ui"))
			end)
		end
	end

	HookOpen("ShopButton")
	HookOpen("StatsButton")
	HookOpen("PrestigeButton")
	HookOpen("SettingsButton")
	HookOpen("BoostsButton")
end)

---------------------------------------------------------------
-- PrestigeReady BindableEvent
---------------------------------------------------------------
task.spawn(function()
	local pr = ReplicatedStorage:WaitForChild("PrestigeReady", 30)
	if not pr then return end
	pr.Event:Connect(function()
		Play(SoundConfig.PrestigeReady, Vol("ui"))
	end)
end)

---------------------------------------------------------------
-- Game event sounds
---------------------------------------------------------------
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")

local AuraSpawned = RemoteEvents:WaitForChild("AuraSpawned")
AuraSpawned.OnClientEvent:Connect(function(info)
	if info.tier == "Legendary" then
		Play(SoundConfig.LegendarySpawn, Vol("mutation"))
	else
		Play(SoundConfig.Click, Vol("interaction"))
	end
end)

local CubeMutated = RemoteEvents:WaitForChild("CubeMutated")
CubeMutated.OnClientEvent:Connect(function(info)
	if info.mutationType == "tierUpgrade" then
		Play(info.tierName == "Legendary"
			and SoundConfig.LegendarySpawn or SoundConfig.TierUpgrade, Vol("mutation"))
	elseif info.mutationType == "valueBonus" then
		Play(SoundConfig.MutationBonus, Vol("mutation"))
	end
end)

local UpdateMultiplier = ReplicatedStorage:WaitForChild("UpdateMultiplier")
UpdateMultiplier.Event:Connect(function(mult)
	if mult > 1 then PlayLoop(SoundConfig.HoldLoop, Vol("interaction"))
	else StopLoop() end
end)

local ForceStopHold = RemoteEvents:WaitForChild("ForceStopHold")
ForceStopHold.OnClientEvent:Connect(function()
	StopLoop()
	Play(SoundConfig.HatcheryEmpty, Vol("interaction"))
end)

local HabitatFull = RemoteEvents:WaitForChild("HabitatFull")
HabitatFull.OnClientEvent:Connect(function()
	StopLoop()
	Play(SoundConfig.HabitatFull, Vol("interaction"))
end)

local ShipAuras = RemoteEvents:WaitForChild("ShipAuras")
ShipAuras.OnClientEvent:Connect(function(info)
	if info and info.collected then Play(SoundConfig.PlatformArrive, Vol("shipping")) end
end)

local UpgradeUpdated = RemoteEvents:WaitForChild("UpgradeUpdated")
UpgradeUpdated.OnClientEvent:Connect(function(info)
	if info.type == "purchased" then Play(SoundConfig.Purchase, Vol("mutation")) end
end)

local PrestigeComplete = RemoteEvents:WaitForChild("PrestigeComplete")
PrestigeComplete.OnClientEvent:Connect(function(info)
	StopLoop()
	if info.isPortalEntry then
		Play(SoundConfig.PortalEnter, Vol("portal"))
	else
		Play(SoundConfig.PrestigeComplete, Vol("prestige"))
	end
end)

local AreaUnlocked = RemoteEvents:WaitForChild("AreaUnlocked")
AreaUnlocked.OnClientEvent:Connect(function()
	Play(SoundConfig.PortalOpen, Vol("portal"))
end)

local AreaChanged = RemoteEvents:WaitForChild("AreaChanged")
AreaChanged.OnClientEvent:Connect(function(info)
	Play(SoundConfig.PortalEnter, Vol("portal"))
	PlayAreaMusic(info.newArea or 1)
end)

---------------------------------------------------------------
-- MENU GATE: Only the initial area music waits for the menu.
-- Everything else (SFX, event sounds, shared.PlayUISound) is live.
---------------------------------------------------------------
local AreaUpdated = RemoteEvents:WaitForChild("AreaUpdated")
local joinMusicStarted = false
AreaUpdated.OnClientEvent:Connect(function(info)
	if not joinMusicStarted then
		joinMusicStarted = true
		task.spawn(function()
			local _menuGate = ReplicatedStorage:WaitForChild("MenuDismissed")
			if not _menuGate:GetAttribute("Fired") then _menuGate.Event:Wait() end
			PlayAreaMusic(info.currentArea or 1)
		end)
	end
end)

-- VFXController
-- Location: StarterPlayer > StarterPlayerScripts > VFXController
--
-- CHANGES:
--   VFX_CONFIG entries now support a `scale` field.
--   EmitVFX passes scale to shared.vfx.emit(scale, clone).
--   scale = 1 is default, 2 = double size, 0.5 = half size.
--
-- SETUP:
--   VFX templates in ReplicatedStorage/VFX/ OR directly in workspace.
--   InvertedDistortion is in workspace — the script finds it there automatically.
--
-- ADDING NEW VFX:
--   1. Add the VFX Model to workspace or ReplicatedStorage/VFX/
--   2. Add an entry to VFX_CONFIG with vfxName, positions, and scale
--   3. That's it — no other changes needed

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris            = game:GetService("Debris")

local player = Players.LocalPlayer

local VFX_FOLDER = ReplicatedStorage:FindFirstChild("VFX")
local AuraHolder = workspace:WaitForChild("AuraHolder")
local HabitatHolder = workspace:WaitForChild("HabitatHolder")
---------------------------------------------------------------
-- VFX CONFIG
-- vfxName  = name of Model in ReplicatedStorage/VFX/ or workspace
-- positions = where to emit: "AuraHolder", "Habitat", "Character", or Vector3
-- scale    = size multiplier passed to shared.vfx.emit(scale, ...)
--            1.0 = default, 2.0 = twice as big, 0.5 = half size
---------------------------------------------------------------
local VFX_CONFIG = {
	Prestige = {
		vfxName   = "InvertedDistortion",
		positions = { "Habitat" },
		scale     = 1.5,
	},
	PortalEnter = {
		vfxName   = "InvertedDistortion",
		positions = { "Habitat" },
		scale     = 2.0,
	},
	AreaUnlocked = {
		vfxName   = "InvertedDistortion",
		positions = { "Habitat" },
		scale     = 1.0,
	},
	ShopPurchase = {
		vfxName   = "",   -- fill in when you have a purchase VFX
		positions = { "Character" },
		scale     = 1.0,
	},
	BoostActivated = {
		vfxName   = "",
		positions = { "AuraHolder" },
		scale     = 7.0,
	},
	TierUpgrade = {
		vfxName   = "",
		positions = { "AuraHolder" },
		scale     = 1.0,
	},
	LegendarySpawn = {
		vfxName   = "",
		positions = { "AuraHolder" },
		scale     = 1.5,
	},
}

local EMIT_CLEANUP_DELAY = 6

---------------------------------------------------------------
-- GetWorldPosition
---------------------------------------------------------------
local function GetWorldPosition(target)
	if typeof(target) == "Vector3" then return target end

	if target == "AuraHolder" then
		return AuraHolder:GetPivot().Position
	end
	

	if target == "Habitat" then
		return HabitatHolder:WaitForChild("Position").Position
	end

	if target == "Character" then
		local char = player.Character
		if char then
			local hrp = char:FindFirstChild("HumanoidRootPart")
			if hrp then return hrp.Position end
		end
		return AuraHolder:GetPivot().Position
	end

	return Vector3.new(0, 0, 0)
end

---------------------------------------------------------------
-- EmitVFX
-- Finds the VFX template, clones it, moves it to worldPos,
-- calls shared.vfx.emit(scale, clone), then Debris cleans it up.
---------------------------------------------------------------
local function EmitVFX(vfxName, worldPos, scale)
	if not vfxName or vfxName == "" then return end

	-- Wait for Forge to initialize (shared.vfx set by ForgeInit)
	if not shared.vfx then
		local waited = 0
		repeat task.wait(0.1); waited += 0.1
		until shared.vfx or waited >= 10
		if not shared.vfx then
			warn("[VFXController] shared.vfx not available — Forge not initialized")
			return
		end
	end

	scale = scale or 1

	-- Check ReplicatedStorage/VFX/ first, then workspace directly
	local template = VFX_FOLDER and VFX_FOLDER:FindFirstChild(vfxName)

	if template then
		-- Clone from template so the original is reusable
		local clone = template:Clone()
		clone.Parent = workspace

		if clone:IsA("Model") then
			clone:PivotTo(CFrame.new(worldPos))
		elseif clone:IsA("BasePart") then
			clone.CFrame = CFrame.new(worldPos)
		end

		local ok, err = pcall(function()
			if scale ~= 1 then
				shared.vfx.emit(scale, clone)
			else
				shared.vfx.emit(clone)
			end
		end)
		if not ok then warn("[VFXController] Emit error: " .. tostring(err)) end

		Debris:AddItem(clone, EMIT_CLEANUP_DELAY)

	else
		-- No template — look for it directly in workspace (e.g. InvertedDistortion)
		local wsObj = workspace:FindFirstChild(vfxName)
		if wsObj then
			-- Move it to the target position and emit in-place
			if wsObj:IsA("Model") then
				wsObj:PivotTo(CFrame.new(worldPos))
			elseif wsObj:IsA("BasePart") then
				wsObj.CFrame = CFrame.new(worldPos)
			end

			local ok, err = pcall(function()
				if scale ~= 1 then
					shared.vfx.emit(scale, wsObj)
				else
					shared.vfx.emit(wsObj)
				end
			end)
			if not ok then warn("[VFXController] Emit error: " .. tostring(err)) end
		else
			warn("[VFXController] VFX not found in VFX folder or workspace: '" .. vfxName .. "'")
		end
	end
end

---------------------------------------------------------------
-- FireEvent — looks up config and emits at all positions
---------------------------------------------------------------
local function FireEvent(eventName)
	local cfg = VFX_CONFIG[eventName]
	if not cfg or not cfg.vfxName or cfg.vfxName == "" then return end

	for _, target in ipairs(cfg.positions or {}) do
		EmitVFX(cfg.vfxName, GetWorldPosition(target), cfg.scale)
	end
end

---------------------------------------------------------------
-- Public API
-- shared.VFXController is set so other LocalScripts can use it:
--   shared.VFXController.Fire("Prestige")
--   shared.VFXController.FireAt("InvertedDistortion", Vector3.new(0,10,0), 2.0)
--   shared.VFXController.FireAtTarget("InvertedDistortion", "AuraHolder", 1.5)
---------------------------------------------------------------
local VFXController = {}

function VFXController.Fire(eventName)
	FireEvent(eventName)
end

function VFXController.FireAt(vfxName, worldPos, scale)
	EmitVFX(vfxName, worldPos, scale)
end

function VFXController.FireAtTarget(vfxName, target, scale)
	EmitVFX(vfxName, GetWorldPosition(target), scale)
end

shared.VFXController = VFXController

---------------------------------------------------------------
-- Event hooks — auto-fire VFX on game events
---------------------------------------------------------------
local RemoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents")

-- Prestige or portal entry
local PrestigeComplete = RemoteEvents:WaitForChild("PrestigeComplete")
PrestigeComplete.OnClientEvent:Connect(function(info)
	if info.isPortalEntry then
		FireEvent("PortalEnter")
	else
		FireEvent("Prestige")
	end
end)

-- Portal threshold hit
local AreaUnlocked = RemoteEvents:WaitForChild("AreaUnlocked")
AreaUnlocked.OnClientEvent:Connect(function()
	FireEvent("AreaUnlocked")
end)

-- Shop upgrade purchased
local UpgradeUpdated = RemoteEvents:WaitForChild("UpgradeUpdated")
UpgradeUpdated.OnClientEvent:Connect(function(info)
	if info.type == "purchased" then
		FireEvent("ShopPurchase")
	end
end)

-- Boost activated
local BoostUpdated = RemoteEvents:WaitForChild("BoostUpdated")
local prevActiveCounts = {}
BoostUpdated.OnClientEvent:Connect(function(state)
	for boostId, data in pairs(state) do
		if type(data) == "table" and data.activeCount then
			local prev = prevActiveCounts[boostId] or 0
			if data.activeCount > prev then
				FireEvent("BoostActivated")
			end
			prevActiveCounts[boostId] = data.activeCount
		end
	end
end)

-- Tier upgrade / legendary
local CubeMutated = RemoteEvents:WaitForChild("CubeMutated")
CubeMutated.OnClientEvent:Connect(function(info)
	if info.mutationType == "tierUpgrade" then
		if info.tierName == "Legendary" then
			FireEvent("LegendarySpawn")
		else
			FireEvent("TierUpgrade")
		end
	end
end)
