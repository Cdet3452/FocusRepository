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
		color        = Color3.fromRGB(255, 255, 255), -- Gold
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
		bannerTitle  = "Producing Stock",
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
		failsafeDuration = 35, -- ✨ NEW: Autocompletes after 35 seconds if they get stuck!
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
		-- ✨ FIX: Removed duration = 0 so it doesn't auto-skip!

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
		bannerBody   = "Click the new Toggle Button to automate your shipments!",

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
	}
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
