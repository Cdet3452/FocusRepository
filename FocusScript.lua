-- =====================================================================
-- 1. MODULE: AreaRegistry
-- Location: ReplicatedStorage > Modules > AreaRegistry
-- =====================================================================
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
		FogStart = 20, FogEnd = 80, Density = 0.6, Haze = 8, AtmosphereColor = Color3.fromRGB(100, 91, 70)
	},
	["Area3_IndustrialOutskirts"] = {
		ClockTime = 16, Brightness = 3, SunRaysIntensity = 0.2,
		Ambient = Color3.fromRGB(124, 115, 105), FogColor = Color3.fromRGB(125, 117, 111),
		FogStart = 0, FogEnd = 0, Density = 0, Haze = 0, AtmosphereColor = Color3.fromRGB(120, 116, 113)
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
	[1] = { 
		name             = "Green Scrapyard",     
		threshold        = 0,   
		valueMultiplier  = 1.0, 
		yOffset          = -2.7, 
		yRotation        = 180, 
		auraPreviewColor = Color3.fromRGB(200, 200, 200), 
		grassColor       = Color3.fromRGB(92, 197, 53), 
		pathColor        = Color3.fromRGB(163, 130, 88), 
		ambientColor     = Color3.fromRGB(90, 90, 100), 
		fogColor         = Color3.fromRGB(180, 200, 220), 
		auraHolderColor  = Color3.fromRGB(255, 255, 255), 
		auraHolderGlow   = Color3.fromRGB(255, 255, 255), 
		lightingPreset   = "Area1_DeepScrapyard", 
		icon = "rbxassetid://71630626823279",
		auraModels       = { Common = "GearAura", Uncommon = "ScrewAura", Rare = "BottleAura", Epic = "TireAura", Legendary = "RadioAura" }
	},
	[2] = { 
		name             = "Industrial Rust",    
		threshold        = 5e4, 
		valueMultiplier  = 1.5, 
		yOffset          = -4.5, 
		yRotation        = 180, 
		auraPreviewColor = Color3.fromRGB(180, 100, 50), 
		grassColor       = Color3.fromRGB(104, 160, 98), 
		pathColor        = Color3.fromRGB(132, 140, 81), 
		ambientColor     = Color3.fromRGB(80, 100, 80), 
		fogColor         = Color3.fromRGB(160, 200, 160), 
		auraHolderColor  = Color3.fromRGB(187, 255, 183), 
		auraHolderGlow   = Color3.fromRGB(100, 255, 100), 
		lightingPreset   = "Area2_RustyWastes", 
		icon = "rbxassetid://71630626823279",
		auraModels       = { Common = "GearAura", Uncommon = "ScrapMetalAura", Rare = "BarrelAura", Epic = "OilAura", Legendary = "BrokenweaponAura" }
	},
	[3] = { 
		name             = "Foil Scrapyard",        
		threshold        = 5e5, 
		valueMultiplier  = 4.0, 
		yOffset          = -2.8, 
		yRotation        = 180, 
		auraPreviewColor = Color3.fromRGB(220, 230, 255), 
		grassColor       = Color3.fromRGB(180, 190, 200), 
		pathColor        = Color3.fromRGB(150, 160, 170), 
		ambientColor     = Color3.fromRGB(100, 110, 120), 
		fogColor         = Color3.fromRGB(200, 210, 220), 
		auraHolderColor  = Color3.fromRGB(220, 230, 255), 
		auraHolderGlow   = Color3.fromRGB(240, 250, 255), 
		lightingPreset   = "Area3_IndustrialOutskirts", 
		icon = "rbxassetid://71630626823279",
		auraModels       = { Common = "FoilBallAura", Uncommon = "CandyAura", Rare = "CrushedCanAura", Epic = "CapAura", Legendary = "SilverLeafAura", Mythic = "BalloonAura" }
	},
	[4] = { 
		name             = "Cheap Metal",        
		threshold        = 5e6, 
		valueMultiplier  = 8.0, 
		yOffset          = -2.8, 
		yRotation        = 180, 
		auraPreviewColor = Color3.fromRGB(150, 150, 160), 
		grassColor       = Color3.fromRGB(130, 130, 140), 
		pathColor        = Color3.fromRGB(100, 100, 110), 
		ambientColor     = Color3.fromRGB(80, 80, 90), 
		fogColor         = Color3.fromRGB(140, 140, 150), 
		auraHolderColor  = Color3.fromRGB(170, 170, 180), 
		auraHolderGlow   = Color3.fromRGB(190, 190, 200), 
		lightingPreset   = "Area4_ChemicalSpill", 
		icon = "rbxassetid://71630626823279",
		auraModels       = { Common = "GearAura", Uncommon = "ScrapMetalAura", Rare = "BarrelAura", Epic = "OilAura", Legendary = "BrokenweaponAura" }

		--auraModels       = { Common = "TinBlock", Uncommon = "ZincPlate", Rare = "LeadPipe", Epic = "NickelCoin", Legendary = "PewterIdol" }
	},
	[5] = { 
		name             = "Solid Metal",   
		threshold        = 5e7, 
		valueMultiplier  = 20.0,
		yOffset          = -3.0,   
		yRotation        = 0,   
		auraPreviewColor = Color3.fromRGB(90, 95, 100), 
		grassColor       = Color3.fromRGB(80, 85, 90), 
		pathColor        = Color3.fromRGB(60, 65, 70), 
		ambientColor     = Color3.fromRGB(50, 55, 60), 
		fogColor         = Color3.fromRGB(100, 105, 110), 
		auraHolderColor  = Color3.fromRGB(120, 125, 130), 
		auraHolderGlow   = Color3.fromRGB(140, 145, 150), 
		lightingPreset   = "Area5_BioHazard", 
		icon = "rbxassetid://71630626823279",
		auraModels       = { Common = "GearAura", Uncommon = "ScrapMetalAura", Rare = "BarrelAura", Epic = "OilAura", Legendary = "BrokenweaponAura" }
		--auraModels       = { Common = "IronOre", Uncommon = "SteelBeam", Rare = "CastIronWheel", Epic = "ChromeBumper", Legendary = "TungstenRod" }
	},
	[6] = {
		name             = "Refined Alloys",
		threshold        = 5e9,
		valueMultiplier  = 75.0,
		yOffset          = -4.5,
		yRotation        = 180,
		auraPreviewColor = Color3.fromRGB(200, 120, 50),
		grassColor       = Color3.fromRGB(160, 90, 40),
		pathColor        = Color3.fromRGB(120, 70, 30),
		ambientColor     = Color3.fromRGB(90, 50, 20),
		fogColor         = Color3.fromRGB(180, 100, 60),
		auraHolderColor  = Color3.fromRGB(220, 140, 80),
		auraHolderGlow   = Color3.fromRGB(255, 180, 100),
		lightingPreset   = "Area6_RefinedAlloys", 
		auraModels       = { Common = "CopperWire", Uncommon = "BrassGear", Rare = "BronzeStatue", Epic = "TitaniumPlate", Legendary = "CobaltShard" }
	},
	[7] = {
		name             = "Precious Metals",
		threshold        = 5e12,
		valueMultiplier  = 350.0,
		yOffset          = -4.5,
		yRotation        = 180,
		auraPreviewColor = Color3.fromRGB(255, 215, 0),
		grassColor       = Color3.fromRGB(200, 170, 0),
		pathColor        = Color3.fromRGB(150, 120, 0),
		ambientColor     = Color3.fromRGB(120, 100, 20),
		fogColor         = Color3.fromRGB(255, 230, 100),
		auraHolderColor  = Color3.fromRGB(255, 240, 150),
		auraHolderGlow   = Color3.fromRGB(255, 255, 200),
		lightingPreset   = "Area7_PreciousMetals", 
		auraModels       = { Common = "SilverBar", Uncommon = "GoldNugget", Rare = "PlatinumRing", Epic = "PalladiumCoin", Legendary = "RhodiumIngot" }
	},
	[8] = {
		name             = "Industrial Synthetics",
		threshold        = 5e15,
		valueMultiplier  = 2500.0,
		yOffset          = -4.5,
		yRotation        = 180,
		auraPreviewColor = Color3.fromRGB(230, 230, 230),
		grassColor       = Color3.fromRGB(40, 40, 40),
		pathColor        = Color3.fromRGB(20, 20, 20),
		ambientColor     = Color3.fromRGB(60, 60, 60),
		fogColor         = Color3.fromRGB(100, 100, 100),
		auraHolderColor  = Color3.fromRGB(255, 255, 255),
		auraHolderGlow   = Color3.fromRGB(200, 200, 255),
		lightingPreset   = "Area8_Synthetics", 
		auraModels       = { Common = "PVC_Pipe", Uncommon = "KevlarWeave", Rare = "TeflonBlock", Epic = "CarbonFiberRoll", Legendary = "GrapheneSheet" }
	},
	[9] = {
		name             = "Volatile Materials",
		threshold        = 5e19,
		valueMultiplier  = 50000.0,
		yOffset          = -4.5,
		yRotation        = 180,
		auraPreviewColor = Color3.fromRGB(100, 255, 100),
		grassColor       = Color3.fromRGB(30, 50, 30),
		pathColor        = Color3.fromRGB(20, 40, 20),
		ambientColor     = Color3.fromRGB(40, 70, 40),
		fogColor         = Color3.fromRGB(80, 200, 80),
		auraHolderColor  = Color3.fromRGB(150, 255, 150),
		auraHolderGlow   = Color3.fromRGB(0, 255, 0),
		lightingPreset   = "Area9_Volatile", 
		auraModels       = { Common = "GlowingSludge", Uncommon = "RadiumDial", Rare = "UraniumRod", Epic = "PlutoniumCore", Legendary = "AntimatterVial" }
	},
	[10] = {
		name             = "Rough Gemstones",
		threshold        = 5e25,
		valueMultiplier  = 1000000.0,
		yOffset          = -4.5,
		yRotation        = 180,
		auraPreviewColor = Color3.fromRGB(200, 100, 255),
		grassColor       = Color3.fromRGB(90, 50, 120),
		pathColor        = Color3.fromRGB(60, 30, 80),
		ambientColor     = Color3.fromRGB(100, 60, 130),
		fogColor         = Color3.fromRGB(180, 120, 255),
		auraHolderColor  = Color3.fromRGB(230, 150, 255),
		auraHolderGlow   = Color3.fromRGB(200, 50, 255),
		lightingPreset   = "Area10_RoughGems", 
		auraModels       = { Common = "AmethystCluster", Uncommon = "RawSapphire", Rare = "UncutRuby", Epic = "EmeraldChunk", Legendary = "OpalGeode" }
	},
	[11] = {
		name             = "Polished Gems",
		threshold        = 5e32,
		valueMultiplier  = 5e7,
		yOffset          = -4.5,
		yRotation        = 180,
		auraPreviewColor = Color3.fromRGB(150, 255, 255),
		grassColor       = Color3.fromRGB(200, 240, 255),
		pathColor        = Color3.fromRGB(180, 220, 255),
		ambientColor     = Color3.fromRGB(100, 200, 255),
		fogColor         = Color3.fromRGB(180, 255, 255),
		auraHolderColor  = Color3.fromRGB(220, 255, 255),
		auraHolderGlow   = Color3.fromRGB(255, 255, 255),
		lightingPreset   = "Area11_PolishedGems", 
		auraModels       = { Common = "PolishedTopaz", Uncommon = "FacetedSapphire", Rare = "CutRuby", Epic = "PerfectEmerald", Legendary = "FlawlessDiamond" }
	},
	[12] = {
		name             = "High-Tech Computing",
		threshold        = 5e40,
		valueMultiplier  = 2.5e9,
		yOffset          = -4.5,
		yRotation        = 180,
		auraPreviewColor = Color3.fromRGB(50, 200, 100),
		grassColor       = Color3.fromRGB(20, 40, 30),
		pathColor        = Color3.fromRGB(15, 30, 20),
		ambientColor     = Color3.fromRGB(30, 60, 40),
		fogColor         = Color3.fromRGB(40, 120, 80),
		auraHolderColor  = Color3.fromRGB(100, 255, 150),
		auraHolderGlow   = Color3.fromRGB(50, 255, 100),
		lightingPreset   = "Area12_HighTech", 
		auraModels       = { Common = "SiliconWafer", Uncommon = "Microchip", Rare = "RAM_Stick", Epic = "QuantumProcessor", Legendary = "AI_Core" }
	},
	[13] = {
		name             = "Neon & Plasma",
		threshold        = 5e50,
		valueMultiplier  = 1.5e11,
		yOffset          = -4.5,
		yRotation        = 180,
		auraPreviewColor = Color3.fromRGB(255, 50, 150),
		grassColor       = Color3.fromRGB(40, 10, 30),
		pathColor        = Color3.fromRGB(20, 5, 15),
		ambientColor     = Color3.fromRGB(60, 20, 50),
		fogColor         = Color3.fromRGB(100, 20, 80),
		auraHolderColor  = Color3.fromRGB(255, 100, 200),
		auraHolderGlow   = Color3.fromRGB(255, 0, 150),
		lightingPreset   = "Area13_Neon", 
		auraModels       = { Common = "NeonTube", Uncommon = "PlasmaArc", Rare = "LaserDiode", Epic = "HardLight", Legendary = "PhotonCell" }
	},
	[14] = {
		name             = "Quantum Mechanics",
		threshold        = 5e62,
		valueMultiplier  = 1e14,
		yOffset          = -4.5,
		yRotation        = 180,
		auraPreviewColor = Color3.fromRGB(255, 255, 255),
		grassColor       = Color3.fromRGB(200, 200, 255),
		pathColor        = Color3.fromRGB(150, 150, 200),
		ambientColor     = Color3.fromRGB(100, 100, 150),
		fogColor         = Color3.fromRGB(200, 200, 255),
		auraHolderColor  = Color3.fromRGB(255, 255, 255),
		auraHolderGlow   = Color3.fromRGB(100, 200, 255),
		lightingPreset   = "Area14_Quantum", 
		auraModels       = { Common = "Quark", Uncommon = "Tachyon", Rare = "Boson", Epic = "Tesseract", Legendary = "SchrodingerCat" }
	},
	[15] = {
		name             = "Celestial Matter",
		threshold        = 5e75,
		valueMultiplier  = 5e16,
		yOffset          = -4.5,
		yRotation        = 180,
		auraPreviewColor = Color3.fromRGB(150, 200, 255),
		grassColor       = Color3.fromRGB(30, 40, 60),
		pathColor        = Color3.fromRGB(20, 25, 40),
		ambientColor     = Color3.fromRGB(40, 50, 80),
		fogColor         = Color3.fromRGB(80, 100, 150),
		auraHolderColor  = Color3.fromRGB(200, 230, 255),
		auraHolderGlow   = Color3.fromRGB(100, 150, 255),
		lightingPreset   = "Area15_Celestial", 
		auraModels       = { Common = "MoonRock", Uncommon = "MarsDust", Rare = "CometIce", Epic = "AsteroidCore", Legendary = "SolarFlare" }
	},
	[16] = {
		name             = "Cosmic Phenomena",
		threshold        = 5e90,
		valueMultiplier  = 2e19,
		yOffset          = -4.5,
		yRotation        = 180,
		auraPreviewColor = Color3.fromRGB(200, 50, 255),
		grassColor       = Color3.fromRGB(20, 10, 40),
		pathColor        = Color3.fromRGB(10, 5, 20),
		ambientColor     = Color3.fromRGB(40, 20, 80),
		fogColor         = Color3.fromRGB(80, 30, 150),
		auraHolderColor  = Color3.fromRGB(255, 150, 255),
		auraHolderGlow   = Color3.fromRGB(150, 50, 255),
		lightingPreset   = "Area16_Cosmic", 
		auraModels       = { Common = "Stardust", Uncommon = "PulsarPulse", Rare = "QuasarLight", Epic = "SupernovaRemnant", Legendary = "GalaxySpiral" }
	},
	[17] = {
		name             = "Dark Matter",
		threshold        = 5e108,
		valueMultiplier  = 1e22,
		yOffset          = -4.5,
		yRotation        = 180,
		auraPreviewColor = Color3.fromRGB(20, 0, 40),
		grassColor       = Color3.fromRGB(10, 0, 15),
		pathColor        = Color3.fromRGB(5, 0, 10),
		ambientColor     = Color3.fromRGB(15, 5, 30),
		fogColor         = Color3.fromRGB(5, 0, 10),
		auraHolderColor  = Color3.fromRGB(50, 0, 100),
		auraHolderGlow   = Color3.fromRGB(255, 0, 50),
		lightingPreset   = "Area17_DarkMatter", 
		auraModels       = { Common = "ShadowMatter", Uncommon = "VoidResidue", Rare = "EventHorizon", Epic = "Singularity", Legendary = "HawkingRadiation" }
	},
	[18] = {
		name             = "Multiversal Elements",
		threshold        = 5e128,
		valueMultiplier  = 5e25,
		yOffset          = -4.5,
		yRotation        = 180,
		auraPreviewColor = Color3.fromRGB(0, 255, 255),
		grassColor       = Color3.fromRGB(30, 30, 30),
		pathColor        = Color3.fromRGB(15, 15, 15),
		ambientColor     = Color3.fromRGB(50, 50, 50),
		fogColor         = Color3.fromRGB(100, 200, 255),
		auraHolderColor  = Color3.fromRGB(255, 0, 255),
		auraHolderGlow   = Color3.fromRGB(0, 255, 255),
		lightingPreset   = "Area18_Multiverse", 
		auraModels       = { Common = "Paradox", Uncommon = "TimelineThread", Rare = "ParallelShard", Epic = "AlternateReality", Legendary = "MultiverseCore" }
	},
	[19] = {
		name             = "Pure Energy",
		threshold        = 5e150,
		valueMultiplier  = 2e29,
		yOffset          = -4.5,
		yRotation        = 180,
		auraPreviewColor = Color3.fromRGB(255, 255, 200),
		grassColor       = Color3.fromRGB(200, 200, 150),
		pathColor        = Color3.fromRGB(255, 255, 200),
		ambientColor     = Color3.fromRGB(255, 255, 255),
		fogColor         = Color3.fromRGB(255, 255, 200),
		auraHolderColor  = Color3.fromRGB(255, 255, 255),
		auraHolderGlow   = Color3.fromRGB(255, 255, 150),
		lightingPreset   = "Area19_PureEnergy", 
		auraModels       = { Common = "Static", Uncommon = "Kinetic", Rare = "Thermal", Epic = "Ethereal", Legendary = "InfiniteEnergy" }
	},
	[20] = {
		name             = "The Absolute",
		threshold        = 5e175,
		valueMultiplier  = 1e34,
		yOffset          = -4.5,
		yRotation        = 180,
		auraPreviewColor = Color3.fromRGB(255, 215, 0),
		grassColor       = Color3.fromRGB(255, 255, 255),
		pathColor        = Color3.fromRGB(200, 200, 200),
		ambientColor     = Color3.fromRGB(255, 240, 200),
		fogColor         = Color3.fromRGB(255, 255, 255),
		auraHolderColor  = Color3.fromRGB(255, 215, 0),
		auraHolderGlow   = Color3.fromRGB(255, 255, 255),
		lightingPreset   = "Area20_TheAbsolute", 
		auraModels       = { Common = "Concept", Uncommon = "Truth", Rare = "Existence", Epic = "Reality", Legendary = "Omnipotence" }
	},
}

function AreaRegistry.Get(idx)            return AreaRegistry.Areas[idx] end
function AreaRegistry.GetName(idx)        return (AreaRegistry.Areas[idx] and AreaRegistry.Areas[idx].name) or ("Area "..idx) end
function AreaRegistry.GetThreshold(idx)   return AreaRegistry.Areas[idx] and AreaRegistry.Areas[idx].threshold or nil end
function AreaRegistry.GetMultiplier(idx)  return (AreaRegistry.Areas[idx] and AreaRegistry.Areas[idx].valueMultiplier) or 1.0 end
function AreaRegistry.GetYOffset(idx)     return (AreaRegistry.Areas[idx] and AreaRegistry.Areas[idx].yOffset)    or 0 end
function AreaRegistry.GetYRotation(idx)   return (AreaRegistry.Areas[idx] and AreaRegistry.Areas[idx].yRotation)  or 0 end

function AreaRegistry.GetFlipbook(idx)
	local area = AreaRegistry.Areas[idx]
	if not area or not area.flipbookImage then return nil end
	return {
		image = area.flipbookImage,
		frames = area.flipbookFrames or 1,
		fps = area.flipbookFPS or 12,
		frameW = area.flipbookFrameW or 128,
		frameH = area.flipbookFrameH or 128,
		columns = area.flipbookColumns or area.flipbookFrames or 1,
	}
end

function AreaRegistry.GetLighting(idx)
	local area = AreaRegistry.Areas[idx]
	if not area or not area.lightingPreset then return AreaRegistry.LightingPresets["ClearDay"] end
	return AreaRegistry.LightingPresets[area.lightingPreset] or AreaRegistry.LightingPresets["ClearDay"]
end

function AreaRegistry.GetMaxArea()
	local max = 0
	for k in pairs(AreaRegistry.Areas) do if k > max then max = k end end
	return max
end

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

function AreaRegistry.CanAdvance(currentArea, farmEvaluation)
	local best = AreaRegistry.GetBestNextArea(currentArea, farmEvaluation)
	if best then return true, best end
	return false, nil
end

-- =====================================================================
-- [NEW] 3-STEP FALLBACK HELPER: FETCHES 3D MODEL SAFELY
-- =====================================================================
function AreaRegistry.FetchAuraModel(areaIndex, rarityName)
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local AreaAssets = ReplicatedStorage:FindFirstChild("AreaAssets")
	local GlobalAuras = ReplicatedStorage:FindFirstChild("Auras")

	local areaConfig = AreaRegistry.Areas[areaIndex]
	if not areaConfig then return nil end

	-- Step 1: Look up the mapped name (e.g., "CorrodedCore")
	local expectedModelName = areaConfig.auraModels and areaConfig.auraModels[rarityName]

	if expectedModelName and AreaAssets then
		-- Step 2: Look for it in ReplicatedStorage > AreaAssets > Area[X] > Auras
		local areaFolder = AreaAssets:FindFirstChild("Area" .. tostring(areaIndex))
		if areaFolder and areaFolder:FindFirstChild("Auras") then
			local specificModel = areaFolder.Auras:FindFirstChild(expectedModelName)
			if specificModel then
				return specificModel:Clone() -- Found specific!
			end
		end
		warn("[AreaRegistry] Missing physical model: " .. expectedModelName .. " in Area" .. tostring(areaIndex) .. ". Falling back to placeholder.")
	end

	-- Step 3: Fallback to the Global Blueprint Folder
	if GlobalAuras then
		local placeholderModel = GlobalAuras:FindFirstChild(rarityName)
		if placeholderModel then
			return placeholderModel:Clone() -- Found placeholder!
		end
	end

	warn("CRITICAL [AreaRegistry]: No custom model OR placeholder found for rarity: " .. tostring(rarityName))
	return nil
end

return AreaRegistry
