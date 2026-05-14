-- TutorialConfig
-- Location: ReplicatedStorage > Modules > TutorialConfig

local TutorialConfig = {}

TutorialConfig.TutorialEndArea = 5

-- The Ghost Hand / Pointer asset
TutorialConfig.PointerImage = "rbxassetid://14914009728"
TutorialConfig.PointerSize = UDim2.new(0, 75, 0, 75)

-- Default Styling
TutorialConfig.DefaultColor = Color3.fromRGB(100, 200, 255)
TutorialConfig.DefaultIcon  = "rbxassetid://14914018910"

-- THE FSM SEQUENCE
TutorialConfig.Steps = {

	-- ✨ STEP 1: Welcome & First Click
	[1] = {
		id           = "a1_welcome_click",
		action       = "Action_ClickRedButton",
		targetTag    = "Tutorial_ClickButton",

		bannerTitle  = "Welcome to Aura Inc!",
		bannerBody   = "Spam Click the Red Button below to produce your first Auras.",

		icon         = "rbxassetid://14922082255", 
		color        = Color3.fromRGB(143, 255, 131), -- Green
	},

	-- ✨ STEP 2: Cinematic Camera Follow! Watch the Aura move.
	[2] = {
		id               = "a1_watch_aura",
		action           = "Action_Wait",

		cameraTrackMode  = "FollowAura", 
		target3D         = "Aura",       
		duration         = 10,          

		bannerTitle  = "Generating Profit",
		bannerBody   = "Each Aura generates cash every second based on its rarity.",
		
		icon         = "rbxassetid://14914018910",
		color        = Color3.fromRGB(255, 255, 255), 
	},

	-- ✨ STEP 3: Produce Bulk
	[3] = {
		id           = "a1_produce_25",
		action       = "Action_ClickRedButton",
		targetTag    = "Tutorial_ClickButton",

		-- Look back at the general factory area
		cameraTarget = "Tutorial_AuraHolderCam",

		requireCubesProduced = 25,
		failsafeDuration = 35, -- ✨ NEW: Autocompletes after 35 seconds if they get stuck!
		bannerTitle  = "Producing Auras",
		bannerBody   = "Keep clicking to produce 25 Auras! The more you make, the more money you earn.",
		duration     = 0, 

		icon         = "rbxassetid://14914018910",
		color        = Color3.fromRGB(130, 226, 255), -- Cyan
	},

	-- ✨ STEP 4: Farm up Cash
	[4] = {
		id           = "a1_farm_150",
		action       = "Action_ClickRedButton",

		requireCurrency = 150,

		bannerTitle  = "Stacking Cash",
		bannerBody   = "Your Auras are passively generating income while on the Conveyer. Keep producing until you save up $150!",
		duration     = 0,
		failsafeDuration = 25, -- ✨ NEW: Autocompletes after 35 seconds if they get stuck!
		icon         = "rbxassetid://14924185885",
		color        = Color3.fromRGB(150, 255, 150), -- Light Green
	},

	-- ✨ STEP 5: Unlock Shop
	[5] = {
		id           = "a1_open_shop",
		action       = "Action_OpenShop",
		targetTag    = "Tutorial_ShopButton",

		unlockTags    = {"Tutorial_ShopButton"},
		unlockActions = {"Action_OpenShop", "Action_CloseShop"},

		bannerTitle  = "Open The Shop",
		bannerBody   = "You have enough Money! Click the Shop icon to view your upgrades.",
		
		icon         = "rbxassetid://14915225073",
		color        = Color3.fromRGB(123, 216, 250), -- Grey
	},

	-- ✨ STEP 6: First Upgrade
	[6] = {
		id             = "a1_buy_blockValue",
		action         = "Action_BuyUpgrade",
		targetTag      = "Tutorial_Buy_blockValue",

		unlockTags     = {"Tutorial_Buy_blockValue"},
		-- ✨ FIX: Removed duration = 0 so it doesn't auto-skip!

		menuTag        = "Tutorial_ShopPanel",
		menuOpenBtnTag = "Tutorial_ShopButton",

		bannerTitle  = "Increase Value",
		bannerBody   = "Buy the Value upgrade to increase the Value of your Auras by +10%",

		icon         = "rbxassetid://14917128076",
		color        = Color3.fromRGB(142, 206, 255), 
	},

	-- ✨ STEP 7: The "Trap". Waiting for the physical bin to fill up.
	[7] = {
		id           = "a1_fill_habitat",
		action       = "Action_ClickRedButton",
		targetTag    = "Tutorial_ClickButton",

		requireHabitatFull = true,
		duration           = 0, 

		bannerTitle  = "Keep Producing",
		bannerBody   = "Close the shop and keep Producing Auras. Spam Click or HOLD the red button To keep producing Auras.",

		icon         = "rbxassetid://14914018910",
		color        = Color3.fromRGB(130, 226, 255), -- Cyan
	},

	-- ✨ STEP 8: Watch the Aura Die (Zoomed Out). 
	[8] = {
		id               = "a1_watch_aura_die",
		action           = "Action_Wait",

		cameraTrackMode  = "FollowAura",
		cameraOffset     = Vector3.new(0, 22, 28), 

		requireRateZero  = true, 
		duration         = 0, 

		bannerTitle  = "Incinerated!",
		bannerBody   = "Since your habitat Got full, Auras get incinerated. Wait for your Rate to hit $0.",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(255, 0, 4), -- Red
	},

	-- ✨ STEP 9: Pan to Habitat to show the full bin
	[9] = {
		id           = "a1_look_at_habitat",
		action       = "Action_Wait",
		cameraTarget = "Tutorial_HabitatCam",

		duration     = 7, 

		bannerTitle  = "Habitat is Full!",
		bannerBody   = "Your storage is completely Full. You need to clear some Space.",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(255, 155, 155), -- Red
	},

	-- ✨ STEP 10: The Solution (Send Button)
	[10] = {
		id           = "a1_send_ship",
		action       = "Action_SendShip",
		targetTag    = "Tutorial_SendShipBtn",

		unlockTags    = {"Tutorial_SendShipBtn"},
		unlockActions = {"Action_SendShip"},

		bannerTitle  = "Clear Space",
		bannerBody   = "Click the newly unlocked SEND button to clear out your habitat of the Auras.",

		icon         = "rbxassetid://14915225073",
		color        = Color3.fromRGB(100, 255, 255), -- Cyan
	},

	-- ✨ STEP 11: Watch the Ship!
	[11] = {
		id           = "a1_wait_for_ship",
		action       = "Action_Wait",
		cameraTarget = "Tutorial_ShippingCam",

		requirePlatformsShipped = 2,

		bannerTitle  = "Ship Delivery",
		bannerBody   = "Ships collect all your Auras and pay out the cash directly to your wallet. Send 2 Ships Out.",
		duration     = 0,

		icon         = "rbxassetid://14914018910",
		color        = Color3.fromRGB(150, 200, 255), -- Light Blue
	},

	-- ✨ STEP 12: Automate it
	[12] = {
		id           = "a1_toggle_auto",
		action       = "Action_ToggleAutoShip",
		targetTag    = "Tutorial_ToggleShipBtn",

		unlockTags    = {"Tutorial_ToggleShipBtn"},
		unlockActions = {"Action_ToggleAutoShip"},

		bannerTitle  = "Automate Ships",
		bannerBody   = "Click the new unlocked Toggle Button to automate your shipments!",

		icon         = "rbxassetid://14915225073",
		color        = Color3.fromRGB(50, 150, 50), -- Dark Green
	},

	-- ✨ STEP 13: Business as usual
	[13] = {
		id           = "a1_farm_500",
		action       = "Action_ClickRedButton",

		requireCurrency = 500,

		bannerTitle  = "More Upgrades!",
		bannerBody   = "Make $500 to afford your next upgrade.",
		duration     = 0,

		icon         = "rbxassetid://14924185885",
		color        = Color3.fromRGB(150, 255, 150), -- Light Green
	},

	[14] = {
		id             = "a1_buy_auraExpansion",
		action         = "Action_BuyUpgrade",
		targetTag      = "Tutorial_Buy_hatcheryCapacity",

		unlockTags     = {"Tutorial_Buy_hatcheryCapacity"},

		menuTag        = "Tutorial_ShopPanel",
		menuOpenBtnTag = "Tutorial_ShopButton",

		bannerTitle  = "More Hatchery",
		bannerBody   = "Buy the Aura Expansion upgrade to increase your Hatchery space!",

		icon         = "rbxassetid://14917128076",
		color        = Color3.fromRGB(105, 255, 250), 
	},

	[15] = {
		id           = "a1_farm_1500",
		action       = "Action_ClickRedButton",

		requireCurrency = 1500,

		bannerTitle  = "Growing the Factory",
		bannerBody   = "Make $1500 to afford the Habitat upgrade, allowing you to store more auras! Buy the aura value upgrade if you feel stuck.",
		duration     = 0,

		icon         = "rbxassetid://14924185885",
		color        = Color3.fromRGB(87, 255, 98),
	},

	[16] = {
		id             = "a1_buy_habitatCapacity",
		action         = "Action_BuyUpgrade",
		targetTag      = "Tutorial_Buy_habitatCapacity",

		unlockTags     = {"Tutorial_Buy_habitatCapacity"},

		menuTag        = "Tutorial_ShopPanel",
		menuOpenBtnTag = "Tutorial_ShopButton",

		bannerTitle  = "More Habitat Space",
		bannerBody   = "Buy the Habitat Reservoir Upgrade to store more Auras before they get Incinirated!",

		icon         = "rbxassetid://14917128076",
		color        = Color3.fromRGB(120, 248, 255),
	},

	[17] = {
		id           = "a1_multiply",
		action       = "Action_ClickRedButton",

		reachMultiplier = 5,

		bannerTitle  = "Hatchery Multipliers",
		bannerBody   = "Hold the Red button to reach the legendary multiplier! Make sure you have enough Hatchery and Space",
		duration     = 0,

		icon         = "rbxassetid://14924185885",
		color        = Color3.fromRGB(255, 255, 0), 
	},
	
	[18] = {
		id           = "a1_farm_25000",
		action       = "Action_ClickRedButton",

		requireCurrency = 5000,

		bannerTitle  = "Mythic Multiplier",
		bannerBody   = "Multipliers Increase Ship and Aura Value. Save up $5,000 to afford the Mythic Multiplier! Upgrade Aura Value If Stuck.",
		duration     = 0,

		icon         = "rbxassetid://14924185885",
		color        = Color3.fromRGB(137, 255, 110), -- White
	},

	[19] = {
		id             = "a1_buy_mythicMult",
		action         = "Action_BuyUpgrade",
		targetTag      = "Tutorial_Buy_unlockMythicMult", 

		unlockTags     = {"Tutorial_Buy_unlockMythicMult"},

		menuTag        = "Tutorial_ShopPanel",
		menuOpenBtnTag = "Tutorial_ShopButton",

		bannerTitle  = "Mythic Multiplier",
		bannerBody   = "Buy the Mythic Multiplier to hold past the legendary multiplier limit!",

		icon         = "rbxassetid://14917128076",
		color        = Color3.fromRGB(80, 246, 255),
	},
	
	[20] = {
		id           = "a1_multiply",
		action       = "Action_ClickRedButton",

		reachMultiplier = 10,

		bannerTitle  = "Hatchery Multipliers",
		bannerBody   = "Hold the Red button to reach the Mythic multiplier! Make sure to have plenty of Hatchery and Space",
		duration     = 0,

		icon         = "rbxassetid://14924185885",
		color        = Color3.fromRGB(134, 24, 161), 
	},

	[21] = {
		id           = "a1_open_prestige",
		action       = "Action_OpenPrestige",
		targetTag    = "Tutorial_PrestigeButton",

		-- We intentionally don't unlock the Confirm button yet!
		unlockTags    = {"Tutorial_PrestigeButton", "Tutorial_PrestigeCloseBtn"},
		unlockActions = {"Action_OpenPrestige", "Action_ClosePrestige"},

		bannerTitle  = "How to Prestige",
		bannerBody   = "Click the Prestige button to restart with a massive permanent earnings multiplier.",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(180, 100, 255),
	},

	[22] = {
		id             = "a1_confirm_prestige",
		action         = "Action_PrestigeConfirm",
		targetTag      = "Tutorial_PrestigeConfirm",

		-- Now we unlock the actual Confirm Button
		unlockTags     = {"Tutorial_PrestigeConfirm"},
		unlockActions  = {"Action_PrestigeConfirm"},

		-- If they close the menu by mistake, the pointer will snap back to the HUD Prestige button!
		menuTag        = "Tutorial_PrestigePanel",
		menuOpenBtnTag = "Tutorial_PrestigeButton",
		
		bannerTitle  = "Confirm Prestige",
		bannerBody   = "Click 'Prestige Now' to get your Soul Auras and increase your earnings permentantly.",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(215, 121, 255),
	},
	[23] = {
		id           = "a1_post_prestige_pan",
		action       = "Action_Wait", -- ✨ THE FIX: Wait for collection instead of clicking!
		duration     = 0,             -- ✨ Auto-advances instantly when the condition is met
		allowClicking = true, -- ✨ THE FIX
		cameraTrackMode = "FollowPhysicsAura", 
		cameraOffset    = Vector3.new(0, 15, 25), 

		requireStepGoldenAuras = 10, -- ✨ THE FIX: Only counts GA collected DURING this step!
	
		bannerTitle  = "Golden Auras",
		bannerBody   = "Collect Auras that spawn from the Producer OR claim your mailbox rewards!",

		icon         = "rbxassetid://4483362458",
		color        = Color3.fromRGB(255, 215, 0),
	},

	-- ✨ STEP 24: Farm for the next area
	[24] = {
		id           = "a1_farm_area2",
		action       = "Action_Wait", -- ✨ THE FIX: Monitor passively instead of requiring a click!
		duration     = 0,             -- ✨ Auto-advances instantly when the condition is met
		allowClicking = true, -- ✨ THE FIX
		requireFarmEval = 50000, 
		unlockTags    = {"Tutorial_TravelButton", "Tutorial_TravelCloseBtn"},
		unlockActions = {"Action_OpenTravel", "Action_CloseTravel"},
		bannerTitle  = "Reaching More Areas",
		bannerBody   = "Open the travel menu to unlock the next Area. Your farm evaluation is based on the total amount of money made in that area.",

		icon         = "rbxassetid://14924185885",
		color        = Color3.fromRGB(126, 255, 212),
	},

	-- ✨ STEP 25: Open Area Travel
	[25] = {
		id           = "a1_open_travel",
		action       = "Action_OpenTravel",
		targetTag    = "Tutorial_TravelButton",

		bannerTitle  = "New Area Unlocked!",
		bannerBody   = "Click the Area Travel button to open the travel menu.",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(100, 200, 255),
	},

	-- ✨ STEP 26: Browse to Area 2 (Click Right Arrow)
	[26] = {
		id             = "a1_travel_arrow",
		action         = "Action_ClickRightArrow",
		targetTag      = "Tutorial_RightArrow",

		unlockTags     = {"Tutorial_RightArrow"},
		unlockActions  = {"Action_ClickRightArrow", "Action_ClickLeftArrow"},

		menuTag        = "Tutorial_TravelPanel",
		menuOpenBtnTag = "Tutorial_TravelButton",
		fallbackStepId = "a1_open_travel", -- Sends them back if they closed the UI

		bannerTitle  = "Browse Areas",
		bannerBody   = "Click the Arrows to view the newly unlocked area and other areas.",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(150, 200, 255),
	},

	-- ✨ STEP 27: Confirm Travel
	[27] = {
		id             = "a1_confirm_travel",
		action         = "Action_TravelConfirm",
		targetTag      = "Tutorial_TravelConfirm",

		unlockTags     = {"Tutorial_TravelConfirm"},
		unlockActions  = {"Action_TravelConfirm"},

		menuTag        = "Tutorial_TravelPanel",
		menuOpenBtnTag = "Tutorial_TravelButton",
		fallbackStepId = "a1_open_travel",

		bannerTitle  = "Travel Now",
		bannerBody   = "Click TRAVEL to jump to the new Area!",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(107, 255, 161),
	},

	[28] = {
		id           = "a1_open_boosts",
		action       = "Action_OpenBoostShop",
		targetTag    = "Tutorial_BoostMenuBtn",

		-- Unlock the tabs so the FSM can use them!
		unlockTags    = {"Tutorial_BoostMenuBtn", "Tutorial_BoostShopClose", "Tutorial_BoostTab_Shop", "Tutorial_BoostTab_Inventory"},
		unlockActions = {"Action_OpenBoostShop", "Action_CloseBoostShop", "Action_BoostTab_Shop", "Action_BoostTab_Inventory"},

		bannerTitle  = "Area Boosts and Multipliers",
		bannerBody   = "Auras in this area have much higher base values! Open the new Boosts menu.",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(75, 255, 174),
	},

	-- ✨ STEP 29: Buy Aura Spawner Boost
	[29] = {
		id           = "a1_buy_boost1",
		action       = "Action_BuyBoost_AuraRush",
		targetTag    = "Tutorial_BuyBoost_AuraRush",

		unlockTags    = {"Tutorial_BuyBoost_AuraRush"},
		unlockActions = {"Action_BuyBoost_AuraRush"},

		menuTag        = "Tutorial_BoostShopPanel",
		menuOpenBtnTag = "Tutorial_BoostMenuBtn",

		requireBoostBought = { id = "AuraRush", count = 1 },

		bannerTitle  = "Buy a Boost",
		bannerBody   = "Buy the Aura Rush Boost using your Golden Auras.",

		icon         = "rbxassetid://4483362458",
		color        = Color3.fromRGB(114, 213, 255),
	},

	-- ✨ STEP 30 (NEW): Switch to Inventory Tab
	[30] = {
		id           = "a1_click_inv_tab",
		action       = "Action_BoostTab_Inventory",
		targetTag    = "Tutorial_BoostTab_Inventory",

		menuTag        = "Tutorial_BoostShopPanel",
		menuOpenBtnTag = "Tutorial_BoostMenuBtn",

		bannerTitle  = "Check Inventory",
		bannerBody   = "Click the INVENTORY tab at the top of the menu to view the boosts you own.",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(103, 111, 255),
	},

	-- ✨ STEP 31: Use Aura Spawner Boost
	[31] = {
		id           = "a1_use_boost1",
		action       = "Action_UseBoost_AuraRush",
		targetTag    = "Tutorial_UseBoost_AuraRush",

		unlockTags    = {"Tutorial_UseBoost_AuraRush"},
		unlockActions = {"Action_UseBoost_AuraRush"},

		menuTag        = "Tutorial_BoostShopPanel",
		menuOpenBtnTag = "Tutorial_BoostMenuBtn",

		requireBoostUsed = { id = "AuraRush", count = 1 },

		bannerTitle  = "Activate the Boost",
		bannerBody   = "Click ACTIVATE to use your new Aura Rush boost!",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(103, 111, 255),
	},

	-- ✨ STEP 32: Spawn 30 Auras 
	[32] = {
		id           = "a1_spawn_30",
		action       = "Action_Wait", 
		targetTag    = "Tutorial_ClickButton",
		allowClicking = true, 

		requireCubesProduced = 30,

		bannerTitle  = "Double Spawn Speed",
		bannerBody   = "Your boost is now active. Produce 30 Auras with the increased spawn speed.",

		icon         = "rbxassetid://14914018910",
		color        = Color3.fromRGB(105, 255, 200),
	},

	-- ✨ STEP 33: Open Boost Shop Again
	[33] = {
		id           = "a1_open_boosts2",
		action       = "Action_OpenBoostShop",
		targetTag    = "Tutorial_BoostMenuBtn",

		bannerTitle  = "Buy More Boosts",
		bannerBody   = "Open up the boosts menu again to buy more boosts.",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(106, 255, 188),
	},

	-- ✨ STEP 34 (NEW): Switch back to Shop Tab
	[34] = {
		id           = "a1_click_shop_tab",
		action       = "Action_BoostTab_Shop",
		targetTag    = "Tutorial_BoostTab_Shop",

		menuTag        = "Tutorial_BoostShopPanel",
		menuOpenBtnTag = "Tutorial_BoostMenuBtn",

		bannerTitle  = "Return to Shop",
		bannerBody   = "Click the SHOP tab to view the boosts available for purchase.",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(114, 213, 255),
	},

	-- ✨ STEP 35: Buy 5 Aura Spawners
	[35] = {
		id           = "a1_buy_boost3",
		action       = "Action_BuyBoost_AuraRush",
		targetTag    = "Tutorial_BuyBoost_AuraRush",

		menuTag        = "Tutorial_BoostShopPanel",
		menuOpenBtnTag = "Tutorial_BoostMenuBtn",

		requireBoostBought = { id = "AuraRush", count = 5 },

		bannerTitle  = "Buy More Aura Rush Boosts",
		bannerBody   = "Buy 5 more Aura Rush Boosts. Note Boosts can stack for even faster production and MONEY.",

		icon         = "rbxassetid://4483362458",
		color        = Color3.fromRGB(101, 255, 199),
	},

	-- ✨ STEP 36: Mass Produce 150 Auras
	[36] = {
		id           = "a1_spawn_150",
		action       = "Action_Wait",
		targetTag    = "Tutorial_ClickButton",
		allowClicking = true, 

		requireCubesProduced = 150,

		bannerTitle  = "Mass Production",
		bannerBody   = "Produce 150 Auras. Don't forget you can use those boosts you just bought!",

		icon         = "rbxassetid://14914018910",
		color        = Color3.fromRGB(130, 226, 255),
	},
	[36] = {
		id           = "a1_claim_boost_chal",
		action       = "Action_ClaimChallenge_unlock_spawnboost",
		targetTag    = "Tutorial_AchieveRow_Chal_unlock_spawnboost",

		unlockTags    = {"Tutorial_AchieveRow_Chal_unlock_spawnboost"},
		unlockActions = {"Action_ClaimChallenge_unlock_spawnboost"},

		menuTag        = "Tutorial_AchievePanel",
		menuOpenBtnTag = "Tutorial_AchieveMenuBtn",

		bannerTitle  = "Claim Your Rewards",
		bannerBody   = "You reached Area 2! Click the green 'CLAIM' button on the Explorer challenge to unlock the Value Boost.",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(80, 255, 100),
	},

	-- ✨ STEP 37: View Aura Index
	[37] = {
		id           = "a1_click_index_tab",
		action       = "Action_ClickAchieveTab_Index",
		targetTag    = "Tutorial_AchieveTab_Index",

		unlockTags    = {"Tutorial_AchieveTab_Index"},
		unlockActions = {"Action_ClickAchieveTab_Index"},

		menuTag        = "Tutorial_AchievePanel",
		menuOpenBtnTag = "Tutorial_AchieveMenuBtn",

		bannerTitle  = "The Aura Index",
		bannerBody   = "Click the Auras tab. Here you can track every single Aura you have discovered across all Areas!",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(100, 200, 255),
	},

	-- ✨ STEP 38: Claim Golden Auras from Index
	[38] = {
		id           = "a1_claim_index_reward",
		action       = "Action_ClaimAura_1_Common",
		targetTag    = "Tutorial_AchieveRow_Index_1",

		unlockTags    = {"Tutorial_AchieveRow_Index_1"},
		unlockActions = {"Action_ClaimAura_1_Common"},

		menuTag        = "Tutorial_AchievePanel",
		menuOpenBtnTag = "Tutorial_AchieveMenuBtn",

		bannerTitle  = "Discovery Bonus",
		bannerBody   = "Click on the Area 1 Common Aura to claim a Golden Aura bonus for discovering it!",

		icon         = "rbxassetid://4483362458",
		color        = Color3.fromRGB(255, 215, 0),
	},

	-- ✨ STEP 39: View Badges Tab
	[39] = {
		id           = "a1_click_badges_tab",
		action       = "Action_ClickAchieveTab_Badges",
		targetTag    = "Tutorial_AchieveTab_Badges",

		unlockTags    = {"Tutorial_AchieveTab_Badges"},
		unlockActions = {"Action_ClickAchieveTab_Badges"},

		menuTag        = "Tutorial_AchievePanel",
		menuOpenBtnTag = "Tutorial_AchieveMenuBtn",

		bannerTitle  = "Roblox Badges",
		bannerBody   = "Click the Badges tab. You can officially earn Roblox Badges for reaching massive milestones.",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(255, 100, 255),
	},

	-- ✨ STEP 40: Claim First Prestige Badge
	[40] = {
		id           = "a1_claim_badge_1",
		action       = "Action_ClaimBadge_1", 
		targetTag    = "Tutorial_AchieveRow_Badge_1",

		unlockTags    = {"Tutorial_AchieveRow_Badge_1"},
		unlockActions = {"Action_ClaimBadge_1"},

		menuTag        = "Tutorial_AchievePanel",
		menuOpenBtnTag = "Tutorial_AchieveMenuBtn",

		bannerTitle  = "Claim Badge",
		bannerBody   = "Click the First Prestige badge to officially unlock it on your Roblox profile!",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(200, 150, 255),
	},

	-- ✨ STEP 41: View Leaderboard
	[41] = {
		id           = "a1_click_leaderboard",
		action       = "Action_ClickAchieveTab_Leaderboard",
		targetTag    = "Tutorial_AchieveTab_Leaderboard",

		unlockTags    = {"Tutorial_AchieveTab_Leaderboard"},
		unlockActions = {"Action_ClickAchieveTab_Leaderboard"},

		menuTag        = "Tutorial_AchievePanel",
		menuOpenBtnTag = "Tutorial_AchieveMenuBtn",

		bannerTitle  = "Global Rankings",
		bannerBody   = "Click the Top 10 tab to view the Global Leaderboard. Can you become the richest player in the world?",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(255, 150, 50),
	},

	-- ✨ STEP 42: View Settings
	[42] = {
		id           = "a1_click_settings",
		action       = "Action_ClickAchieveTab_Settings",
		targetTag    = "Tutorial_AchieveTab_Settings",

		unlockTags    = {"Tutorial_AchieveTab_Settings"},
		unlockActions = {"Action_ClickAchieveTab_Settings"},

		menuTag        = "Tutorial_AchievePanel",
		menuOpenBtnTag = "Tutorial_AchieveMenuBtn",

		bannerTitle  = "Customize Your Farm",
		bannerBody   = "Finally, click the Settings tab. You can customize the game audio and mechanics here.",

		icon         = "rbxassetid://14923131909",
		color        = Color3.fromRGB(150, 255, 255),
	},

	-- ✨ STEP 43: Toggle Jumping
	[43] = {
		id           = "a1_toggle_jump",
		action       = "Action_ToggleSetting_jump",
		targetTag    = "Tutorial_SettingToggle_jump",

		unlockTags    = {"Tutorial_SettingToggle_jump"},
		unlockActions = {"Action_ToggleSetting_jump"},

		menuTag        = "Tutorial_AchievePanel",
		menuOpenBtnTag = "Tutorial_AchieveMenuBtn",

		bannerTitle  = "Disable Jumping",
		bannerBody   = "Click to disable Jumping. (You can also quick-toggle jumping at any time by pressing 'T' on your keyboard!)",

		icon         = "rbxassetid://14923131909",
		color        = Color3.fromRGB(255, 100, 100),
	},

	-- ✨ STEP 44: End of Tutorial
	[44] = {
		id           = "a1_final_travel",
		action       = "Action_OpenTravel",
		targetTag    = "Tutorial_TravelButton",

		bannerTitle  = "goober",
		bannerBody   = "yay piggy bank",

		icon         = "rbxassetid://14916846070",
		color        = Color3.fromRGB(100, 255, 150),
	},
}

function TutorialConfig.GetStepByIndex(index)
	return TutorialConfig.Steps[index]
end

function TutorialConfig.GetStepById(id)
	for _, step in ipairs(TutorialConfig.Steps) do
		if step.id == id then return step end
	end
	return nil
end

return TutorialConfig
