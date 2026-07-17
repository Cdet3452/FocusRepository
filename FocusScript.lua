--!strict
export type M1Def = {
    name: string,
    damage: number,
    knockback: number?,
    hitRange: number,
    hitRadius: number,
    hitArc: number, -- degrees
}

export type AbilityDef = {
    name: string,
    displayName: string,
    description: string,
    damage: number,
    cooldown: number,
    range: number,
    hitboxRadius: number,
    hitboxType: string,
    projectileSpeed: number?,
    duration: number?,
    knockback: number?,
    launchPower: number?,
    chargeTime: number?,
    element: string,
}

export type PassiveDef = {
    name: string,
    description: string,
    element: string,
}

export type ElementAbilityConfig = {
    m1Combo: { M1Def },
    abilities: { AbilityDef },
    passive: PassiveDef,
}

local ElementConfig = {}

ElementConfig.Fire = {
	m1Combo = {
		{
			name = "M1-1",
			damage = 4,
			hitRange = 10,
			hitRadius = 4,
			hitArc = 60,
		},
		{
			name = "M1-2",
			damage = 4,
			hitRange = 10,
			hitRadius = 4,
			hitArc = 60,
		},
		{
			name = "M1-3",
			damage = 5,
			hitRange = 12,
			hitRadius = 5,
			hitArc = 70,
		},
		{
			name = "M1-4",
			damage = 7,
			knockback = 18,
			hitRange = 14,
			hitRadius = 8,
			hitArc = 100,
		},
	},
	abilities = {
		{
			name = "FireShot",
			displayName = "FireShot",
			description = "Create a compressed fire sphere and launch it.",
			damage = 15,
			cooldown = 5,
			range = 320,
			hitboxRadius = 6,
			hitboxType = "Projectile",
			projectileSpeed = 120,
			duration = 5.5,
			knockback = 10,
			element = "Fire",
		},
		{
			name = "FirePillar",
			displayName = "Fire Pillar",
			description = "Mark a target and summon a blazing pillar of fire erupting from the ground.",
			damage = 20,
			cooldown = 8,
			range = 120,
			hitboxRadius = 7,
			hitboxType = "Aoe",
			duration = 4.0,
			knockback = 18,
			element = "Fire",
		},
		{
			name = "FlameTracker",
			displayName = "Flame Tracker",
			description = "Launch a volley of homing fire discs that track toward the cursor.",
			damage = 5,
			cooldown = 9,
			range = 200,
			hitboxRadius = 5,
			hitboxType = "Projectile",
			projectileSpeed = 130,
			duration = 4.0,
			knockback = 12,
			element = "Fire",
		},
		{
			name = "MeteorShower",
			displayName = "Meteor Shower",
			description = "Summon a blazing sun that rises into the air, raining down a cascade of fiery meteors.",
			damage = 0,
			cooldown = 25,
			range = 40,
			hitboxRadius = 30,
			hitboxType = "Aoe",
			duration = 13.0,
			knockback = 0,
			element = "Fire",
		},
	},
	passive = {
		name = "BurningEmbers",
		description = "Leaves burning embers while moving.",
		element = "Fire",
	},
} :: ElementAbilityConfig

ElementConfig.Air = {
	m1Combo = {
		{
			name = "M1-1",
			damage = 3,
			hitRange = 11,
			hitRadius = 4,
			hitArc = 65,
		},
		{
			name = "M1-2",
			damage = 3,
			hitRange = 11,
			hitRadius = 4,
			hitArc = 65,
		},
		{
			name = "M1-3",
			damage = 5,
			hitRange = 13,
			hitRadius = 5,
			hitArc = 80,
		},
		{
			name = "M1-4",
			damage = 8,
			knockback = 22,
			hitRange = 15,
			hitRadius = 9,
			hitArc = 120,
		},
	},
	abilities = {
		{
			name = "GustBlade",
			displayName = "Gust Blade",
			description = "Slash a crescent of compressed air forward.",
			damage = 14,
			cooldown = 4,
			range = 200,
			hitboxRadius = 5,
			hitboxType = "Projectile",
			projectileSpeed = 140,
			duration = 4,
			knockback = 12,
			element = "Air",
		},
		{
			name = "Cyclone",
			displayName = "Cyclone",
			description = "Spin rapidly, creating a whirlwind that pulls enemies in and launches them upward.",
			damage = 20,
			cooldown = 10,
			range = 18,
			hitboxRadius = 14,
			hitboxType = "Aoe",
			duration = 0.8,
			launchPower = 40,
			element = "Air",
		},
		{
			name = "AirDash",
			displayName = "Air Dash",
			description = "Dash forward in a burst of wind, slashing through enemies in your path.",
			damage = 18,
			cooldown = 8,
			range = 55,
			hitboxRadius = 8,
			hitboxType = "Melee",
			duration = 0.5,
			knockback = 20,
			element = "Air",
		},
		{
			name = "Tornado",
			displayName = "Tornado",
			description = "Summon a massive tornado that devastates everything in its path.",
			damage = 38,
			cooldown = 22,
			range = 30,
			hitboxRadius = 26,
			hitboxType = "Aoe",
			duration = 2.0,
			chargeTime = 1.0,
			knockback = 30,
			element = "Air",
		},
	},
	passive = {
		name = "DoubleJump",
		description = "Double jump capability.",
		element = "Air",
	},
} :: ElementAbilityConfig

ElementConfig.Water = {
	m1Combo = {
		{
			name = "M1-1",
			damage = 4,
			hitRange = 10,
			hitRadius = 4,
			hitArc = 60,
		},
		{
			name = "M1-2",
			damage = 4,
			hitRange = 10,
			hitRadius = 4,
			hitArc = 60,
		},
		{
			name = "M1-3",
			damage = 5,
			hitRange = 12,
			hitRadius = 5,
			hitArc = 70,
		},
		{
			name = "M1-4",
			damage = 7,
			knockback = 18,
			hitRange = 14,
			hitRadius = 8,
			hitArc = 100,
		},
	},
	abilities = {
		{
			name = "WaterSpark",
			displayName = "Water Spark",
			description = "Fire a high-pressure jet of water.",
			damage = 14,
			cooldown = 5,
			range = 200,
			hitboxRadius = 5,
			hitboxType = "Projectile",
			projectileSpeed = 120,
			duration = 4,
			knockback = 10,
			element = "Water",
		},
		{
			name = "Bubbles",
			displayName = "Bubbles",
			description = "Spawn floating bubbles that chase and damage nearby enemies.",
			damage = 10,
			cooldown = 8,
			range = 25,
			hitboxRadius = 3,
			hitboxType = "Projectile",
			duration = 15,
			element = "Water",
		},
		{
			name = "AquaShield",
			displayName = "Aqua Shield",
			description = "Summon a protective shield of water.",
			damage = 0,
			cooldown = 12,
			range = 0,
			hitboxRadius = 8,
			hitboxType = "Aoe",
			duration = 5,
			element = "Water",
		},
		{
			name = "WaterBurst",
			displayName = "Water Burst",
			description = "Release a burst of water in all directions.",
			damage = 18,
			cooldown = 10,
			range = 20,
			hitboxRadius = 12,
			hitboxType = "Aoe",
			duration = 3,
			knockback = 15,
			element = "Water",
		},
	},
	passive = {
		name = "IncreasedMovementSpeed",
		description = "Increased movement speed while using abilities.",
		element = "Water",
	},
} :: ElementAbilityConfig

ElementConfig.Celestial = {
	m1Combo = {
		{
			name = "M1-1",
			damage = 4,
			hitRange = 10,
			hitRadius = 4,
			hitArc = 60,
		},
		{
			name = "M1-2",
			damage = 4,
			hitRange = 10,
			hitRadius = 4,
			hitArc = 60,
		},
		{
			name = "M1-3",
			damage = 5,
			hitRange = 12,
			hitRadius = 5,
			hitArc = 70,
		},
		{
			name = "M1-4",
			damage = 7,
			knockback = 18,
			hitRange = 14,
			hitRadius = 8,
			hitArc = 100,
		},
	},
	abilities = {
		{
			name = "GalaxyStrike",
			displayName = "Galaxy Strike",
			description = "Summon a cosmic cloud that rains down galaxies on your target.",
			damage = 0,
			cooldown = 10,
			range = 200,
			hitboxRadius = 6,
			hitboxType = "Aoe",
			duration = 8.0,
			knockback = 0,
			element = "Celestial",
		},
		{
			name = "StarFall",
			displayName = "Star Fall",
			description = "Call down a cascade of stars from the heavens.",
			damage = 18,
			cooldown = 8,
			range = 150,
			hitboxRadius = 7,
			hitboxType = "Aoe",
			duration = 4.0,
			knockback = 12,
			element = "Celestial",
		},
		{
			name = "CosmicRay",
			displayName = "Cosmic Ray",
			description = "Fire a concentrated beam of cosmic energy.",
			damage = 22,
			cooldown = 9,
			range = 250,
			hitboxRadius = 4,
			hitboxType = "Projectile",
			projectileSpeed = 180,
			duration = 3.0,
			knockback = 10,
			element = "Celestial",
		},
		{
			name = "NebulaShield",
			displayName = "Nebula Shield",
			description = "Wrap yourself in a protective nebula that damages nearby foes.",
			damage = 8,
			cooldown = 14,
			range = 0,
			hitboxRadius = 12,
			hitboxType = "Aoe",
			duration = 5.0,
			knockback = 0,
			element = "Celestial",
		},
	},
	passive = {
		name = "RegenerateEnergy",
		description = "Regenerate energy faster during combat.",
		element = "Celestial",
	},
} :: ElementAbilityConfig

function ElementConfig.getElementConfig(elementName: string): ElementAbilityConfig?
    -- Check for explicit config first
    for key, config in ElementConfig do
        if key == elementName then
            return config :: ElementAbilityConfig
        end
    end

    -- Auto-generate from GachaConfig if the element exists but has no explicit config
    local GachaConfig = require(script.Parent.GachaConfig)
    local elementDef = GachaConfig.getElementByName(elementName)
    if not elementDef then
        return nil
    end

    -- Generate ability configs from the element's skill display names
    -- Determine hitbox types based on common naming patterns
    local function guessHitboxType(skillDisplayName: string): string
        local lower = string.lower(skillDisplayName)
        if string.find(lower, "shot") or string.find(lower, "bolt")
            or string.find(lower, "blast") or string.find(lower, "jet")
            or string.find(lower, "splash") or string.find(lower, "sling")
            or string.find(lower, "spike") or string.find(lower, "lance")
            or string.find(lower, "beam") or string.find(lower, "ray")
            or string.find(lower, "shard") or string.find(lower, "fang")
            or string.find(lower, "burst") and not string.find(lower, "storm")
        then
            return "Projectile"
        end
        if string.find(lower, "storm") or string.find(lower, "nova")
            or string.find(lower, "wave") or string.find(lower, "eruption")
            or string.find(lower, "explosion") or string.find(lower, "quake")
            or string.find(lower, "stomp") or string.find(lower, "rain")
            or string.find(lower, "surge") or string.find(lower, "call")
            or string.find(lower, "age") or string.find(lower, "zero")
            or string.find(lower, "deluge") or string.find(lower, "maelstrom")
            or string.find(lower, "ragnarok") or string.find(lower, "collapse")
            or string.find(lower, "avalanche")
        then
            return "Aoe"
        end
        return "Melee"
    end

    -- Map rarity to base damage scaling
    local rarityDamageMultipliers: { [string]: number } = {
        Common = 1.0,
        Uncommon = 1.15,
        Rare = 1.3,
        Legendary = 1.5,
        Mythic = 1.75,
        Transcendent = 2.0,
    }
    local damageMultiplier = rarityDamageMultipliers[elementDef.rarity] or 1.0

    local abilities: { AbilityDef } = {}
    local baseDamages = { 12, 16, 22, 35, 28, 32, 38, 45 }
    local baseCooldowns = { 5, 8, 12, 20, 10, 14, 16, 24 }
    local baseRanges = { 80, 14, 40, 25, 60, 35, 45, 30 }
    local baseHitboxRadii = { 5, 6, 12, 20, 10, 14, 16, 22 }

    local elementSkills = GachaConfig.getElementSkills(elementDef)
    for i, skillDisplayName in elementSkills do
        local skillName = string.gsub(skillDisplayName, "%s+", "")
        local hitboxType = guessHitboxType(skillDisplayName)
        local isUltimate = (i == #elementDef.skills and #elementDef.skills >= 3)
        local ability: AbilityDef = {
            name = skillName,
            displayName = skillDisplayName,
            description = elementDef.description,
            damage = math.floor(baseDamages[i] * damageMultiplier + 0.5),
            cooldown = if isUltimate then 20 else baseCooldowns[i],
            range = if hitboxType == "Projectile" then baseRanges[i] * 4 else baseRanges[i],
            hitboxRadius = baseHitboxRadii[i],
            hitboxType = hitboxType,
            projectileSpeed = if hitboxType == "Projectile" then 100 else nil,
            duration = 3,
            knockback = if hitboxType == "Melee" then 12 else 8,
            launchPower = if hitboxType == "Melee" then 35 else nil,
            element = elementDef.name,
        }
        if isUltimate then
            ability.chargeTime = 1.0
        end
        table.insert(abilities, ability)
    end

    local generated: ElementAbilityConfig = {
        m1Combo = {
            { name = "M1-1", damage = math.floor(4 * damageMultiplier + 0.5), hitRange = 10, hitRadius = 4, hitArc = 60 },
            { name = "M1-2", damage = math.floor(4 * damageMultiplier + 0.5), hitRange = 10, hitRadius = 4, hitArc = 60 },
            { name = "M1-3", damage = math.floor(5 * damageMultiplier + 0.5), hitRange = 12, hitRadius = 5, hitArc = 70 },
            { name = "M1-4", damage = math.floor(7 * damageMultiplier + 0.5), knockback = 18, hitRange = 14, hitRadius = 8, hitArc = 100 },
        },
        abilities = abilities,
        passive = {
            name = string.gsub(elementDef.passive, "%s+", ""),
            description = elementDef.passive,
            element = elementDef.name,
        },
    }

    return generated
end

return ElementConfig

					--!strict
-- Celestial Combat Animations (R6) -- single hand-raised summoning cast for GalaxyStrike
-- Mirrors the FireAnimations/AirAnimations pattern: procedural KeyframeSequence
-- registered through AnimationClipProvider, cached so subsequent getAnimationId
-- calls reuse the same Content id.

local AnimationClipProvider = game:GetService("AnimationClipProvider")

local registeredAnims: { [string]: Content } = {}

local SMOOTH = Enum.PoseEasingStyle.Cubic
local LINEAR = Enum.PoseEasingStyle.Linear
local ELASTIC = Enum.PoseEasingStyle.Elastic
local BOUNCE = Enum.PoseEasingStyle.Bounce
local OUT = Enum.PoseEasingDirection.Out
local IN = Enum.PoseEasingDirection.In
local INOUT = Enum.PoseEasingDirection.InOut

local function pose(name: string, cf: CFrame, easeStyle: PoseEasingStyle?, easeDir: PoseEasingDirection?): Pose
	local p = Instance.new("Pose")
	p.Name = name
	p.CFrame = cf
	p.EasingStyle = easeStyle or SMOOTH
	p.EasingDirection = easeDir or OUT
	return p
end

local function kf(time: number, data: { [string]: CFrame }, eases: { [string]: any }?): Keyframe
	local frame = Instance.new("Keyframe")
	frame.Time = time
	local torsoPose = pose("Torso", data.Torso or CFrame.new())
	local headPose = pose("Head", data.Head or CFrame.new()); headPose.Parent = torsoPose
	local rArmPose = pose("Right Arm", data["Right Arm"] or CFrame.new()); rArmPose.Parent = torsoPose
	local lArmPose = pose("Left Arm", data["Left Arm"] or CFrame.new()); lArmPose.Parent = torsoPose
	local rLegPose = pose("Right Leg", data["Right Leg"] or CFrame.new()); rLegPose.Parent = torsoPose
	local lLegPose = pose("Left Leg", data["Left Leg"] or CFrame.new()); lLegPose.Parent = torsoPose
	frame:AddPose(torsoPose)
	return frame
end

local IDLE = {
	Torso = CFrame.new(),
	Head = CFrame.new(),
	["Right Arm"] = CFrame.new(),
	["Left Arm"] = CFrame.new(),
	["Right Leg"] = CFrame.new(),
	["Left Leg"] = CFrame.new(),
}

-- ===== SKILL 1: GALAXY STRIKE (1.30s, hands raised, summoning the cosmic cloud) =====
-- The cloud casts up around 0.15s and lingers for 8s in VFX while the player
-- returns to idle. The animation is intentionally short (1.30s) so the
-- client can immediately return control while the galaxies keep falling.
local function createGalaxyStrike(): KeyframeSequence
	local seq = Instance.new("KeyframeSequence")
	seq.Priority = Enum.AnimationPriority.Action
	seq.Loop = false
	seq:AddKeyframe(kf(0.0, {
		Torso = CFrame.new(0, -0.02, 0) * CFrame.Angles(math.rad(2), 0, 0),
		Head = CFrame.Angles(math.rad(2), 0, 0),
		["Right Arm"] = CFrame.Angles(math.rad(-6), 0, math.rad(-3)),
		["Left Arm"] = CFrame.Angles(math.rad(-6), 0, math.rad(3)),
		["Right Leg"] = CFrame.Angles(math.rad(2), 0, 0),
		["Left Leg"] = CFrame.Angles(math.rad(-2), 0, 0),
	}, {}))
	seq:AddKeyframe(kf(0.18, {
		Torso = CFrame.new(0, -0.05, 0) * CFrame.Angles(math.rad(-3), 0, 0),
		Head = CFrame.Angles(math.rad(-6), 0, 0),
		["Right Arm"] = CFrame.Angles(math.rad(-120), 0, math.rad(-10)),
		["Left Arm"] = CFrame.Angles(math.rad(-120), 0, math.rad(10)),
		["Right Leg"] = CFrame.Angles(math.rad(3), 0, math.rad(-1)),
		["Left Leg"] = CFrame.Angles(math.rad(-3), 0, math.rad(1)),
	}, { ["Right Arm"] = { SMOOTH, OUT }, ["Left Arm"] = { SMOOTH, OUT } }))
	seq:AddKeyframe(kf(0.45, {
		Torso = CFrame.new(0, -0.06, 0) * CFrame.Angles(math.rad(-4), 0, 0),
		Head = CFrame.Angles(math.rad(-8), 0, 0),
		["Right Arm"] = CFrame.Angles(math.rad(-130), 0, math.rad(-12)),
		["Left Arm"] = CFrame.Angles(math.rad(-130), 0, math.rad(12)),
		["Right Leg"] = CFrame.Angles(math.rad(3), 0, math.rad(-1)),
		["Left Leg"] = CFrame.Angles(math.rad(-3), 0, math.rad(1)),
	}, {}))
	seq:AddKeyframe(kf(0.75, {
		Torso = CFrame.new(0, -0.04, 0) * CFrame.Angles(math.rad(-2), 0, 0),
		Head = CFrame.Angles(math.rad(-4), 0, 0),
		["Right Arm"] = CFrame.Angles(math.rad(-100), 0, math.rad(-8)),
		["Left Arm"] = CFrame.Angles(math.rad(-100), 0, math.rad(8)),
		["Right Leg"] = CFrame.Angles(math.rad(2), 0, 0),
		["Left Leg"] = CFrame.Angles(math.rad(-2), 0, 0),
	}, { ["Right Arm"] = { SMOOTH, INOUT }, ["Left Arm"] = { SMOOTH, INOUT } }))
	seq:AddKeyframe(kf(1.10, {
		Torso = CFrame.new(0, -0.02, 0) * CFrame.Angles(math.rad(1), 0, 0),
		Head = CFrame.Angles(math.rad(1), 0, 0),
		["Right Arm"] = CFrame.Angles(math.rad(-12), 0, math.rad(-4)),
		["Left Arm"] = CFrame.Angles(math.rad(-12), 0, math.rad(4)),
		["Right Leg"] = CFrame.Angles(math.rad(1), 0, 0),
		["Left Leg"] = CFrame.Angles(math.rad(-1), 0, 0),
	}, { ["Right Arm"] = { SMOOTH, IN }, ["Left Arm"] = { SMOOTH, IN } }))
	seq:AddKeyframe(kf(1.30, IDLE, {}))
	return seq
end

local CelestialAnimations = {}

function CelestialAnimations.getAnimationId(abilityName: string): Content?
	if registeredAnims[abilityName] then return registeredAnims[abilityName] end

	local seq: KeyframeSequence?
	if abilityName == "GalaxyStrike" then
		seq = createGalaxyStrike()
	end

	if not seq then return nil end

	local contentId
	local ok1, id1 = pcall(function()
		return AnimationClipProvider:RegisterActiveAnimationClip(seq)
	end)
	if ok1 and id1 then contentId = id1 end
	if not contentId then
		local ok2, id2 = pcall(function()
			return AnimationClipProvider:RegisterAnimationClip(seq)
		end)
		if ok2 and id2 then contentId = id2 end
	end

	if not contentId then
		warn(string.format("[celestial-anim] Failed to register animation for %s", abilityName))
		return nil
	end
	registeredAnims[abilityName] = contentId
	print(string.format("[celestial-anim] R6 %s registered", abilityName))
	return contentId
end

return CelestialAnimations


					--!strict
-- Celestial Element — Tool 1 (Galaxy Strike) server handler
-- Minimal handler: validates the activation request from the client and
-- logs it. The ability itself is a client-side VFX rain (6 galaxies over
-- 8s with collision-driven impact effects), so the server has no damage
-- or hitbox to apply. This script is here to match the pattern of the
-- other element handlers and to be a place to add server-authoritative
-- logic later (e.g. damage per Galaxy on hit) without changing the client.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CelestialRemotes = ReplicatedStorage:WaitForChild("ElementAbilities"):WaitForChild("Celestial")
local SkillActivated = CelestialRemotes:WaitForChild("SkillActivated") :: RemoteEvent
local CombatVFX = CelestialRemotes:WaitForChild("CombatVFX") :: RemoteEvent

local playerCooldowns: { [Player]: { [string]: number } } = {}

local function getCooldowns(player: Player): { [string]: number }
	if not playerCooldowns[player] then
		playerCooldowns[player] = {}
	end
	return playerCooldowns[player]
end

local COOLDOWN_SECONDS = 10

SkillActivated.OnServerEvent:Connect(function(player: Player, skillName: string, _direction: Vector3, targetPos: Vector3?)
	if typeof(skillName) ~= "string" then return end
	if skillName ~= "GalaxyStrike" then return end

	-- Basic rate-limit: reject activations faster than the ability's cooldown.
	-- This is a client-trust sanity check; the tool's LastUsed attribute is
	-- the primary cooldown gate, this just stops a malicious client from
	-- spamming the remote.
	local lastUsed = getCooldowns(player)[skillName]
	if lastUsed and tick() - lastUsed < COOLDOWN_SECONDS then
		warn(string.format("[celestial-server] %s tried to spam %s", player.Name, skillName))
		return
	end
	getCooldowns(player)[skillName] = tick()

	-- Element ownership sanity: if the player has switched elements, drop
	-- the activation. We don't need to take any action; the client already
	-- ran its VFX. Logging is enough for now.
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local elementStat = leaderstats:FindFirstChild("Element")
		if elementStat and elementStat:IsA("StringValue") and elementStat.Value ~= "Celestial" then
			warn(string.format("[celestial-server] %s activated %s but equipped %s — ignoring",
				player.Name, skillName, elementStat.Value))
			return
		end
	end

	-- Replicate the Galaxy Strike VFX to every OTHER client. The caster
	-- already renders it locally; other players generate the same visual on
	-- their own machine using the caster's target point + character.
	if typeof(targetPos) == "Vector3" and player.Character then
		for _, other in Players:GetPlayers() do
			if other ~= player then
				CombatVFX:FireClient(other, "GalaxyStrike", player, targetPos)
			end
		end
	end

	print(string.format("[celestial-server] %s activated %s", player.Name, skillName))
end)

-- Relay authoritative impact points from the caster to every other client.
-- Observers render the impact VFX at the caster's moment instead of
-- re-simulating the galaxy fall (which previously made their VFX vanish early).
CombatVFX.OnServerEvent:Connect(function(player: Player, eventType: string, a: any)
	if typeof(eventType) ~= "string" then return end
	if eventType == "GalaxyImpact" then
		if typeof(a) ~= "Vector3" then return end
		for _, other in Players:GetPlayers() do
			if other ~= player then
				CombatVFX:FireClient(other, "GalaxyImpact", a)
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player: Player)
	playerCooldowns[player] = nil
end)

print("[celestial-server] CelestialCombatHandler initialized (Galaxy Strike)")

					--!strict
-- Celestial Element — Tool 1 (Galaxy Strike) client
-- Listens for the toolbar's RequestSkillActivation BindableEvent and for
-- Tool.Activated. On GalaxyStrike it spawns a cosmic cloud (SpawnGalaxy)
-- 110 studs above the target, then rains 6 Galaxy parts from inside it
-- toward the mouse cursor over 8 seconds. Each Galaxy falls with a slight
-- tilt and medium continuous spin, and on impact ALL 5 meshes (Galaxy +
-- 3 Shock + Wave) appear together at the impact point, each expands and
-- rotates around its own center, all fade transparency 0 -> 1, and a
-- substantial one-shot particle burst fires from GalaxyExplosion. The
-- impact root is destroyed after the fade completes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local ElementConfig = require(ReplicatedStorage.GachaSystem.ElementConfig)
local CelestialAnimations = require(ReplicatedStorage.GachaSystem.CelestialAnimations)

local CelestialRemotes = ReplicatedStorage.ElementAbilities.Celestial
local SkillActivated = CelestialRemotes.SkillActivated :: RemoteEvent
local CombatVFX = CelestialRemotes.CombatVFX :: RemoteEvent

-- Templates authored in workspace. Use WaitForChild so the LocalScript
-- doesn't grab them before the workspace has finished replicating to the
-- client (FindFirstChild ran too early on first boot and warned about
-- templates that were actually present).
local GALAXY_TEMPLATE = Workspace:WaitForChild("Galaxy", 15) :: MeshPart?
local CLOUD_TEMPLATE = Workspace:WaitForChild("SpawnGalaxy", 15) :: Part?
local EXPLOSION_TEMPLATE = Workspace:WaitForChild("GalaxyExplosion", 15) :: Part?

if not GALAXY_TEMPLATE then warn("[celestial-client] Workspace.Galaxy template missing") end
if not CLOUD_TEMPLATE then warn("[celestial-client] Workspace.SpawnGalaxy template missing") end
if not EXPLOSION_TEMPLATE then warn("[celestial-client] Workspace.GalaxyExplosion template missing") end

-- ===== TUNING =====
local TOTAL_GALAXIES = 6
local RAIN_DURATION = 8.0
local CLOUD_HOVER_HEIGHT = 166.0 -- studs above target (110 + 56 = 166 for sky-high spawn)
local CLOUD_HOVER_JITTER = 4.0 -- random Y jitter per cloud
local GALAXY_FALL_SPEED = 90.0 -- studs/sec
local GALAXY_FALL_TILT_DEG = 10.0 -- max tilt of the fall vector away from a straight-to-target line
local GALAXY_TILT_DEG = 25.0 -- visible tilt of the galaxy's own orientation (off-vertical)
local GALAXY_ROT_SPEED = 180.0 -- deg/sec, medium continuous spin
local EXPAND_DURATION = 0.85 -- mesh expand + fade duration on impact
local EXPAND_SIZE_MULT = 1.8 -- how much each mesh grows
local IMPACT_SPIN_SPEED = 90.0 -- deg/sec, smooth elegant spin on each mesh during impact
local EXPLOSION_EMIT_COUNT = 35 -- particles per emitter for the one-shot impact burst
local FALL_MAX_LIFETIME = 6.0 -- safety cap per Galaxy in case nothing is below
local CLOUD_CLEANUP_DELAY = 9.5 -- how long after cast the cloud self-destructs
local CLEANUP_PARTICLE_WAIT = 1.2 -- seconds after the particle fade starts before destroying all impact VFX (0.6s fade + 0.6s buffer)

-- ===== STATE =====
local currentCharacter: Model? = nil
local humanoid: Humanoid? = nil
local humanoidRootPart: BasePart? = nil
local isAttacking: boolean = false
local toolConnections: { RBXScriptConnection } = {}
local activeClouds: { Part } = {}

-- ===== SFX =====
local SFX = {
	GalaxyStrikeCast = "rbxassetid://1839256025",
	GalaxyStrikeImpact = "rbxassetid://1839255657",
}

-- ===== HELPERS =====
local function getElement(): string
	local ls = player:FindFirstChild("leaderstats")
	if not ls then return "" end
	local es = ls:FindFirstChild("Element")
	if not es or not es:IsA("StringValue") then return "" end
	return es.Value
end

-- Resolve where the cursor is pointing in 3D (raycast from camera).
-- Falls back to a point ahead of the player if nothing is under the cursor.
local function getClickTarget(): (Vector3, Vector3)
	if not humanoidRootPart then
		return Vector3.new(), Vector3.new(0, 0, -1)
	end
	local camera = Workspace.CurrentCamera
	if not camera then
		local fwd = humanoidRootPart.CFrame.LookVector
		return humanoidRootPart.Position + fwd * 30, fwd
	end

	local mousePos = UserInputService:GetMouseLocation()
	local unitRay = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	if currentCharacter then
		rayParams.FilterDescendantsInstances = { currentCharacter }
	end
	-- Ignore our own active clouds so the raycast never hits the cloud itself
	for _, c in activeClouds do
		table.insert(rayParams.FilterDescendantsInstances, c)
	end

	local rayResult = Workspace:Raycast(unitRay.Origin, unitRay.Direction * 1000, rayParams)
	local targetPos = if rayResult then rayResult.Position
		else unitRay.Origin + unitRay.Direction * 250
	return targetPos, unitRay.Direction
end

-- ===== ANIMATION =====
local function playAnimation(animName: string, speed: number?): AnimationTrack?
	if not humanoid then return nil end
	local animId = CelestialAnimations.getAnimationId(animName)
	if not animId then return nil end
	local anim = Instance.new("Animation")
	anim.AnimationId = animId
	local track: AnimationTrack = humanoid.Animator:LoadAnimation(anim)
	if not track then return nil end
	track:Play(0.08, 1, speed or 1)
	track.Ended:Connect(function()
		track:Destroy()
	end)
	task.delay((track.Length or 1) / (speed or 1) + 0.1, function()
		if track and track.IsPlaying then
			track:Stop(0.1)
		end
	end)
	return track
end

-- ===== PLAY SOUND =====
local function playSoundAt(position: Vector3, soundId: string, volume: number, speed: number?)
	local anchor = Instance.new("Part")
	anchor.Name = "CelestialSoundAnchor"
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Position = position
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.Transparency = 1
	anchor.Parent = Workspace
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume
	sound.PlaybackSpeed = speed or 1
	sound.RollOffMinDistance = 12
	sound.RollOffMaxDistance = 200
	sound.Parent = anchor
	sound:Play()
	Debris:AddItem(anchor, 6)
end

-- ===== EXTRA IMPACT VFX =====
-- In addition to the expanding GalaxyImpact meshes and the GalaxyExplosion
-- particle burst, spawn four more visible impact elements:
--   1. A flat neon ground ring that expands outward from the impact point
--      (the classic shockwave-on-the-ground look).
--   2. A tall vertical light pillar (neon cylinder) that briefly flashes up.
--   3. A PointLight that flashes bright purple then fades.
--   4. An outer "Shock" mesh — a larger expanding sphere that goes wider
--      than the inner Shock meshes for a layered shockwave effect.
-- All elements fade to Transparency = 1 over their duration and self-destruct.
local IMPACT_COLOR = Color3.fromRGB(180, 110, 255)

local function spawnImpactExtras(impactPos: Vector3)
	-- 1. Ground shockwave ring (flat cylinder that expands outward).
	local ring = Instance.new("Part")
	ring.Name = "ImpactRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.2, 1, 1)
	ring.CFrame = CFrame.new(impactPos + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Color = IMPACT_COLOR
	ring.Material = Enum.Material.Neon
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Transparency = 0
	ring.Parent = Workspace
	task.spawn(function()
		local start = tick()
		local DURATION = 0.9
		while true do
			local elapsed = tick() - start
			if elapsed >= DURATION then break end
			local alpha = math.min(elapsed / DURATION, 1)
			local radius = 1 + alpha * 22
			ring.Size = Vector3.new(0.2, radius, radius)
			ring.Transparency = alpha
			task.wait(0)
		end
		if ring.Parent then ring:Destroy() end
	end)

	-- 2. Vertical light pillar (brief neon beam shooting up).
	local pillar = Instance.new("Part")
	pillar.Name = "ImpactPillar"
	pillar.Shape = Enum.PartType.Cylinder
	pillar.Size = Vector3.new(3, 1, 3)
	pillar.CFrame = CFrame.new(impactPos)
	pillar.Color = IMPACT_COLOR
	pillar.Material = Enum.Material.Neon
	pillar.Anchored = true
	pillar.CanCollide = false
	pillar.CanQuery = false
	pillar.CanTouch = false
	pillar.CastShadow = false
	pillar.Transparency = 0
	pillar.Parent = Workspace
	task.spawn(function()
		local start = tick()
		local DURATION = 0.45
		while true do
			local elapsed = tick() - start
			if elapsed >= DURATION then break end
			local alpha = math.min(elapsed / DURATION, 1)
			pillar.Size = Vector3.new(
				3 - alpha * 2.5,
				1 + alpha * 55,
				3 - alpha * 2.5
			)
			pillar.Transparency = alpha
			task.wait(0)
		end
		if pillar.Parent then pillar:Destroy() end
	end)

	-- 3. PointLight flash (illuminates the surrounding area briefly).
	local lightHolder = Instance.new("Part")
	lightHolder.Name = "ImpactLightHolder"
	lightHolder.Size = Vector3.new(1, 1, 1)
	lightHolder.CFrame = CFrame.new(impactPos)
	lightHolder.Anchored = true
	lightHolder.CanCollide = false
	lightHolder.CanQuery = false
	lightHolder.CanTouch = false
	lightHolder.CastShadow = false
	lightHolder.Transparency = 1
	lightHolder.Parent = Workspace
	local flash = Instance.new("PointLight")
	flash.Color = IMPACT_COLOR
	flash.Brightness = 6
	flash.Range = 35
	flash.Parent = lightHolder
	task.spawn(function()
		local start = tick()
		local DURATION = 0.8
		while true do
			local elapsed = tick() - start
			if elapsed >= DURATION then break end
			local alpha = math.min(elapsed / DURATION, 1)
			flash.Brightness = 6 * (1 - alpha)
			task.wait(0)
		end
		if lightHolder.Parent then lightHolder:Destroy() end
	end)

	-- 4. Outer shock mesh — a larger expanding sphere for a layered wave.
	local outerShock = Instance.new("Part")
	outerShock.Name = "OuterShock"
	outerShock.Shape = Enum.PartType.Ball
	outerShock.Size = Vector3.new(2, 2, 2)
	outerShock.CFrame = CFrame.new(impactPos)
	outerShock.Color = IMPACT_COLOR
	outerShock.Material = Enum.Material.Neon
	outerShock.Anchored = true
	outerShock.CanCollide = false
	outerShock.CanQuery = false
	outerShock.CanTouch = false
	outerShock.CastShadow = false
	outerShock.Transparency = 0
	outerShock.Parent = Workspace
	task.spawn(function()
		local start = tick()
		local DURATION = 0.7
		local startSize = outerShock.Size
		local endSize = startSize * 3.5
		while true do
			local elapsed = tick() - start
			if elapsed >= DURATION then break end
			local alpha = math.min(elapsed / DURATION, 1)
			outerShock.Size = startSize:Lerp(endSize, alpha)
			outerShock.Transparency = alpha
			task.wait(0)
		end
		if outerShock.Parent then outerShock:Destroy() end
	end)
end

-- ===== IMPACT: ALL 5 MESHES EXPAND + SPIN + FADE TOGETHER =====
-- The cloned Galaxy is a MeshPart named "Galaxy" with child MeshParts
-- named "Shock" (x3) and "Wave" — 5 visual meshes total. Each one must
-- appear at the impact point, expand and rotate around its own center,
-- and fade 0 -> 1 over EXPAND_DURATION. The GalaxyExplosion fires a
-- substantial particle burst (Emit(EXPLOSION_EMIT_COUNT)) at the impact
-- and stops emitting after the fade finishes. The whole impact root is
-- then destroyed.
local function onGalaxyImpact(galaxyRoot: MeshPart?, impactPos: Vector3, isLocal: boolean?)
	-- On collision:
	--   1. The falling Galaxy's 5 MeshParts disappear IMMEDIATELY
	--      (Transparency = 1) so the player never sees the falling mesh
	--      sitting on the ground.
	--   2. A fresh clone of the Galaxy template is spawned at the
	--      impact point as the impact VFX. It expands, spins on X,
	--      and fades its 5 MeshParts over exactly 1 second, then is
	--      destroyed.
	--   3. Every ParticleEmitter (inside Galaxy, inside Hitbox, and
	--      inside GalaxyExplosion) is disabled, gets a lifetime-based
	--      Transparency gradient + Size shrink, and is destroyed
	--      after particles have finished.
	--   4. The original falling Galaxy (already invisible) is destroyed
	--      once its particles have finished.

	local FADE_DURATION = 1.0
	local PARTICLE_LIFETIME = 2.3

	-- 1. Immediately hide every MeshPart in the falling Galaxy so it
	-- vanishes the instant it touches a surface. Stop all continuous
	-- emission. Set particles to fade over their remaining lifetime.
	if galaxyRoot then
		local allFallingEmitters: { ParticleEmitter } = {}
		for _, desc in galaxyRoot:GetDescendants() do
			if desc:IsA("MeshPart") then
				desc.Transparency = 1
			end
			if desc:IsA("ParticleEmitter") or desc:IsA("Trail") or desc:IsA("Beam") then
				desc.Enabled = false
			end
			if desc:IsA("ParticleEmitter") then
				table.insert(allFallingEmitters, desc)
				desc.Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0),
					NumberSequenceKeypoint.new(1, 1),
				})
			end
		end
		-- Hide the root too.
		galaxyRoot.Transparency = 1
	end

	-- 2. Spawn a fresh Galaxy at the impact point as the impact VFX.
	-- Its 5 MeshParts (root + Shock1..3 + Wave) expand, spin, and
	-- fade over 1 second, then the whole impact VFX is destroyed.
	if GALAXY_TEMPLATE then
		local impactGalaxy = GALAXY_TEMPLATE:Clone()
		impactGalaxy.Name = "GalaxyImpact"
		impactGalaxy.Anchored = true
		impactGalaxy.CanCollide = false
		impactGalaxy.CanQuery = false
		impactGalaxy.CanTouch = false
		impactGalaxy.CastShadow = false
		impactGalaxy.CFrame = CFrame.new(impactPos)
		impactGalaxy.Transparency = 0
		impactGalaxy.Parent = Workspace

		-- Snap every child MeshPart / Part to the impact point and anchor.
		-- Only MeshParts are made visible (Transparency = 0). The hitbox Part
		-- stays at its template Transparency = 1 so it doesn't show as a
		-- white block — visuals come from the expanding Shock/Wave meshes.
		local meshes: { MeshPart } = { impactGalaxy }
		for _, child in ipairs(impactGalaxy:GetChildren()) do
			if child:IsA("MeshPart") or child:IsA("BasePart") then
				child.Anchored = true
				child.CanCollide = false
				child.CanQuery = false
				child.CanTouch = false
				child.CastShadow = false
				child.CFrame = CFrame.new(impactPos)
				if child:IsA("MeshPart") then
					child.Transparency = 0
				end
			end
			if child:IsA("MeshPart") then
				table.insert(meshes, child)
			end
		end

		-- Disable and fade every ParticleEmitter in the impact VFX.
		local impactEmitters: { ParticleEmitter } = {}
		for _, desc in impactGalaxy:GetDescendants() do
			if desc:IsA("ParticleEmitter") then
				desc.Enabled = false
				table.insert(impactEmitters, desc)
				desc.Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0),
					NumberSequenceKeypoint.new(1, 1),
				})
			end
		end

		-- Store original Size sequences for the shrink-to-0 fallback.
		local originalSizes: { [ParticleEmitter]: NumberSequence } = {}
		for _, emitter in ipairs(impactEmitters) do
			originalSizes[emitter] = emitter.Size
		end

		-- Per-mesh spin data.
		local SPIN_AXIS = Vector3.new(1, 0, 0)
		local spinRad = math.rad(IMPACT_SPIN_SPEED)
		local startAngle = math.random() * math.pi * 2
		type SpinData = {
			mesh: MeshPart,
			startSize: Vector3,
			endSize: Vector3,
			angle: number,
		}
		local spins: { SpinData } = {}
		for _, mesh in ipairs(meshes) do
			table.insert(spins, {
				mesh = mesh,
				startSize = mesh.Size,
				endSize = mesh.Size * EXPAND_SIZE_MULT,
				angle = startAngle + math.random() * math.pi * 2,
			})
		end

		-- Drive the 1-second fade in a task.spawn loop (more reliable
		-- than Heartbeat in some cases). Every frame: spin, expand,
		-- and set Transparency = alpha.
		task.spawn(function()
			local startTime = tick()
			while true do
				local now = tick()
				local elapsed = now - startTime
				if elapsed >= FADE_DURATION then
					break
				end
				local alpha = math.min(elapsed / FADE_DURATION, 1)

				-- Fade + expand + spin every impact mesh.
				for _, s in ipairs(spins) do
					if s.mesh and s.mesh.Parent then
						s.mesh.Transparency = alpha
					end
				end

				-- Shrink particle Size to 0 over the same 1s.
				for _, emitter in ipairs(impactEmitters) do
					if emitter and emitter.Parent then
						local orig = originalSizes[emitter]
						if orig then
							local keypoints = {}
							for _, kp in ipairs(orig.Keypoints) do
								table.insert(keypoints, NumberSequenceKeypoint.new(kp.Time, kp.Value * (1 - alpha), kp.Envelope * (1 - alpha)))
							end
							emitter.Size = NumberSequence.new(keypoints)
						end
					end
				end

				task.wait(0)
			end

			-- Force final state: fully transparent.
			for _, s in ipairs(spins) do
				if s.mesh and s.mesh.Parent then
					s.mesh.Transparency = 1
				end
			end
			for _, emitter in ipairs(impactEmitters) do
				if emitter and emitter.Parent then
					local orig = originalSizes[emitter]
					if orig then
						emitter.Size = NumberSequence.new(0)
					end
				end
			end
		end)

		-- A separate loop drives the spin + expand (different from fade).
		-- The spin should continue smoothly while meshes expand; the
		-- transparency is handled above.
		task.spawn(function()
			local startTime = tick()
			local lastTick = startTime
			while true do
				local now = tick()
				local elapsed = now - startTime
				if elapsed >= FADE_DURATION then break end
				local dt2 = math.min(now - lastTick, 1/30)
				lastTick = now
				local alpha = math.min(elapsed / FADE_DURATION, 1)
				for _, s in ipairs(spins) do
					if s.mesh and s.mesh.Parent then
						s.angle = s.angle + spinRad * dt2
						s.mesh.CFrame = CFrame.new(s.mesh.Position)
							* CFrame.fromAxisAngle(SPIN_AXIS, s.angle)
						s.mesh.Size = s.startSize:Lerp(s.endSize, alpha)
					end
				end
				task.wait(0)
			end
		end)

		-- Destroy the impact VFX after the fade + particle lifetime.
		task.delay(FADE_DURATION + PARTICLE_LIFETIME + 0.2, function()
			if impactGalaxy and impactGalaxy.Parent then
				impactGalaxy:Destroy()
			end
		end)
		Debris:AddItem(impactGalaxy, FADE_DURATION + PARTICLE_LIFETIME + 0.5)
	end

	-- 3. GalaxyExplosion: one-shot burst, lifetime-based fade, destroy.
	-- The base Part itself is kept invisible (Transparency = 1) so it
	-- doesn't show as a white block — all visuals come from its child
	-- ParticleEmitters (the purple burst).
	local explosion: Part? = nil
	if EXPLOSION_TEMPLATE then
		explosion = EXPLOSION_TEMPLATE:Clone() :: Part
		explosion.Name = "GalaxyExplosion"
		explosion.Anchored = true
		explosion.CanCollide = false
		explosion.CanQuery = false
		explosion.CanTouch = false
		explosion.CastShadow = false
		explosion.CFrame = CFrame.new(impactPos)
		explosion.Transparency = 1
		explosion.Parent = Workspace

		for _, desc in explosion:GetDescendants() do
			if desc:IsA("ParticleEmitter") then
				desc:Emit(EXPLOSION_EMIT_COUNT)
				desc.Enabled = false
				desc.Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0),
					NumberSequenceKeypoint.new(1, 1),
				})
			end
		end

		task.delay(PARTICLE_LIFETIME + 0.2, function()
			if explosion and explosion.Parent then
				explosion:Destroy()
			end
		end)
		Debris:AddItem(explosion, PARTICLE_LIFETIME + 0.5)
	end

	-- Hit sound at impact.
	playSoundAt(impactPos, SFX.GalaxyStrikeImpact, 0.9, 0.95 + math.random() * 0.1)

	-- 4. Extra impact VFX: ground shockwave ring, light pillar, PointLight
	-- flash, and an outer expanding shock sphere.
	spawnImpactExtras(impactPos)

	-- The local caster relays the exact impact point to the server so every
	-- other client renders the impact at the same moment — a single
	-- authoritative impact event. Observers do not re-simulate the galaxy
	-- fall (that divergence made their VFX vanish early).
	if isLocal then
		CombatVFX:FireServer("GalaxyImpact", impactPos)
	end

	if galaxyRoot then
		-- 5. Destroy the (already hidden) falling Galaxy after its particles
		-- have finished their lifetime.
		task.delay(PARTICLE_LIFETIME + 0.5, function()
			if galaxyRoot and galaxyRoot.Parent then
				galaxyRoot:Destroy()
			end
		end)
		Debris:AddItem(galaxyRoot, PARTICLE_LIFETIME + 0.8)
	end
end

-- ===== FALL LOOP FOR ONE GALAXY =====
-- Spawns one cloned Galaxy from the cloud's center and drops it toward the
-- exact mouse hit position. The fall vector is built from spawn -> target
-- with a small extra horizontal tilt so it isn't a perfectly straight line.
-- The galaxy itself is given a visible tilt and a continuous single-axis
-- spin at a medium speed. Raycasts ahead of the galaxy detect ground impact.
local function spawnOneGalaxy(cloud: Part, targetPos: Vector3, characterFilter: Model?)
	if not GALAXY_TEMPLATE then return end

	local galaxy = GALAXY_TEMPLATE:Clone() :: MeshPart
	galaxy.Name = "Galaxy"
	galaxy.Anchored = true
	galaxy.CanCollide = false
	galaxy.CanQuery = false
	galaxy.CanTouch = false
	galaxy.CastShadow = false
	galaxy.Transparency = 0 -- visible while falling, expanded/faded on impact

	-- Spawn from the cloud's center (with a tiny jitter so consecutive
	-- galaxies don't all start at the exact same point).
	local spawnPos = cloud.Position + Vector3.new(
		(math.random() - 0.5) * 4.0,
		(math.random() - 0.5) * 4.0,
		(math.random() - 0.5) * 4.0
	)
	galaxy.Position = spawnPos

	-- Base fall direction: from spawn toward the target. The spawn is high
	-- above the target, so this is mostly -Y with a horizontal component.
	local toTarget = (targetPos - spawnPos)
	local distance = toTarget.Magnitude
	local fallDir = if distance > 0.01 then toTarget.Unit else Vector3.new(0, -1, 0)

	-- Slight extra tilt: nudge the fall direction sideways by a few degrees
	-- (around a random axis) so the trajectory is not perfectly straight.
	local tiltRad = math.rad(GALAXY_FALL_TILT_DEG)
	local tiltYaw = math.random() * math.pi * 2
	local tiltNudge = (CFrame.Angles(0, tiltYaw, 0) * CFrame.Angles(tiltRad, 0, 0)).LookVector
	fallDir = (fallDir + Vector3.new(tiltNudge.X, 0, tiltNudge.Z) * 0.3).Unit

	-- Visible tilt of the galaxy itself (its orientation, not the fall line).
	local tiltAxis = Vector3.new(
		math.random() - 0.5,
		math.random() - 0.5,
		math.random() - 0.5
	)
	if tiltAxis.Magnitude < 0.1 then tiltAxis = Vector3.new(1, 0, 0) end
	tiltAxis = tiltAxis.Unit
	local tiltCFrame = CFrame.fromAxisAngle(tiltAxis, math.rad(GALAXY_TILT_DEG))

	-- Continuous spin around the X axis only, like a slowly spinning
	-- galaxy. The spin speed is randomized per-galaxy for variety.
	local spinAxis = Vector3.new(1, 0, 0)
	local spinSpeed = GALAXY_ROT_SPEED * (0.8 + math.random() * 0.4)
	local spinRad = math.rad(spinSpeed)
	local spinAngle = math.random() * math.pi * 2

	-- Initial CFrame: position + visible tilt + starting spin
	galaxy.CFrame = CFrame.new(spawnPos) * tiltCFrame * CFrame.fromAxisAngle(spinAxis, spinAngle)
	galaxy.Parent = Workspace

	-- The hitbox child of the Galaxy template holds 16 ParticleEmitters
	-- (Hit 3, Ring_2, circlee, Flashstep, Impact_Line_01, EnergyVFX23,
	-- Energytrilowquality, 14200879082_2, Flipbook Beam 7, Fog, Fire1,
	-- 0043, Untitled_Artwork, 22 (2), and 16 more) that make up the
	-- "full Galaxy VFX" — the swirly purple/blue/pink ring, the black
	-- curves, the burst particles. These need to be active AND travel
	-- with the galaxy during the fall.
	--
	-- The hitbox is Anchored=false in the template. Anchored children
	-- do NOT follow the parent when the parent teleports via CFrame
	-- assignment. We anchor the hitbox and explicitly re-set its CFrame
	-- every frame in the fall loop + on impact so the particles always
	-- emit at the galaxy's current position, not at the template's
	-- static spawn location. We also disable its collision (we raycast
	-- manually) and explicitly enable every ParticleEmitter in the
	-- hierarchy.
	local hitbox: BasePart? = galaxy:FindFirstChild("hitbox") :: BasePart?
	if hitbox and hitbox:IsA("BasePart") then
		hitbox.Anchored = true
		hitbox.CanCollide = false
		hitbox.CanQuery = false
		hitbox.CanTouch = false
		-- Snap the hitbox to the galaxy's CFrame right now so the
		-- particles emit at the spawn point (not the template's).
		hitbox.CFrame = galaxy.CFrame
	end
	-- Enable every visual effect inside the Galaxy (ParticleEmitters,
	-- plus any Trails/Beams/Lights if present) so the full VFX plays
	-- during the fall.
	for _, desc in galaxy:GetDescendants() do
		if desc:IsA("ParticleEmitter")
			or desc:IsA("Trail")
			or desc:IsA("Beam")
			or desc:IsA("PointLight")
			or desc:IsA("SpotLight")
			or desc:IsA("SurfaceLight") then
			desc.Enabled = true
			if desc:IsA("ParticleEmitter") then
				desc.Transparency = NumberSequence.new(0) -- start fully visible
			end
		end
	end

	-- Raycast filter: ignore self, character, and active clouds
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local filterList: { Instance } = { galaxy }
	if characterFilter then table.insert(filterList, characterFilter) end
	for _, c in activeClouds do table.insert(filterList, c) end
	rayParams.FilterDescendantsInstances = filterList

	local startTime = tick()
	task.spawn(function()
		-- The falling Galaxy is NOT hidden instantly on collision.
		-- It becomes the impact effect and fades smoothly over 1 second
		-- inside onGalaxyImpact, per user requirement that nothing
		-- disappear instantly.

		while galaxy and galaxy.Parent do
			if tick() - startTime > FALL_MAX_LIFETIME then
				onGalaxyImpact(galaxy, galaxy.Position, true)
				return
			end

			local dt = task.wait(0.03)
			if not galaxy or not galaxy.Parent then return end

			-- Move along fall direction (toward the target)
			local step = GALAXY_FALL_SPEED * dt
			galaxy.Position = galaxy.Position + fallDir * step

			-- Accumulate continuous spin and rebuild CFrame: tilt + spin
			spinAngle = spinAngle + spinRad * dt
			galaxy.CFrame = CFrame.new(galaxy.Position)
				* tiltCFrame
				* CFrame.fromAxisAngle(spinAxis, spinAngle)
			-- Keep the hitbox rigidly locked to the galaxy so its
			-- ParticleEmitters emit at the galaxy's current position,
			-- not at the template's static spawn location.
			if hitbox and hitbox.Parent then
				hitbox.CFrame = galaxy.CFrame
			end

			-- Collision check: raycast a short distance ahead in the fall direction
			local rayOrigin = galaxy.Position - fallDir * 1.0
			local rayResult = Workspace:Raycast(rayOrigin, fallDir * 3.5, rayParams)
			if rayResult then
				onGalaxyImpact(galaxy, rayResult.Position, true)
				return
			end
		end
	end)
end

-- ===== SPAWN CLOUD (shared by local cast + remote observers) =====
-- Spawns the hovering cosmic cloud above targetPos, plays the cast sound, and
-- self-cleans up after CLOUD_CLEANUP_DELAY. Returns the cloud Part (or nil if
-- the template is missing). Both the local caster and other clients call this
-- so a remote observer sees the same charging cloud.
local function spawnCloud(targetPos: Vector3): Part?
	local cloudPos = Vector3.new(
		targetPos.X,
		targetPos.Y + CLOUD_HOVER_HEIGHT + (math.random() - 0.5) * CLOUD_HOVER_JITTER,
		targetPos.Z
	)

	local cloud: Part? = nil
	if CLOUD_TEMPLATE then
		cloud = CLOUD_TEMPLATE:Clone() :: Part
		cloud.Name = "SpawnGalaxy"
		cloud.Anchored = true
		cloud.CanCollide = false
		cloud.CanQuery = false
		cloud.CanTouch = false
		cloud.CastShadow = false
		cloud.Size = CLOUD_TEMPLATE.Size
		cloud.CFrame = CFrame.new(cloudPos)
		cloud.Transparency = 1
		cloud.Parent = Workspace
		table.insert(activeClouds, cloud)
	end

	playSoundAt(cloudPos, SFX.GalaxyStrikeCast, 0.7, 1.0)

	-- Self-cleanup the cloud after the rain finishes + a small tail.
	task.delay(CLOUD_CLEANUP_DELAY, function()
		if cloud and cloud.Parent then
			for idx, c in ipairs(activeClouds) do
				if c == cloud then
					table.remove(activeClouds, idx)
					break
				end
			end
			for _, desc in cloud:GetDescendants() do
				if desc:IsA("ParticleEmitter") then
					desc.Enabled = false
				end
			end
			local tween = TweenService:Create(
				cloud,
				TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Transparency = 1 }
			)
			tween:Play()
			tween.Completed:Once(function()
				if cloud and cloud.Parent then cloud:Destroy() end
			end)
		end
	end)

	return cloud
end

-- ===== MAIN CAST: vfxGalaxyStrike =====
-- Spawns the cloud, rains 6 galaxies over RAIN_DURATION seconds toward the
-- target the cursor was on at cast time (locked in, so the player can move
-- their mouse while it's raining without dragging the aim).
-- origin is only used by the local caster; for a remote cast we use
-- targetPosOverride (the caster's locked cursor point) and casterCharacter
-- (the caster's character, used as the collision filter so the galaxies
-- don't collide with the wrong player). When omitted, falls back to this
-- client's own cursor + character (local cast).
local function vfxGalaxyStrike(origin: Vector3, targetPosOverride: Vector3?, casterCharacter: Model?)
	local targetPos = if targetPosOverride then targetPosOverride else (getClickTarget())

	-- Cloud position: above the target, with vertical jitter so consecutive
	-- casts don't sit at the exact same height
	local cloudPos = Vector3.new(
		targetPos.X,
		targetPos.Y + CLOUD_HOVER_HEIGHT + (math.random() - 0.5) * CLOUD_HOVER_JITTER,
		targetPos.Z
	)

	-- Spawn the cloud (handles its own hover position + self-cleanup).
	local cloud = spawnCloud(targetPos)

	-- Schedule 6 galaxies, one every (RAIN_DURATION / TOTAL_GALAXIES) seconds
	local interval = RAIN_DURATION / TOTAL_GALAXIES
		for i = 1, TOTAL_GALAXIES do
			task.delay((i - 1) * interval, function()
				if not cloud or not cloud.Parent then return end
				if not casterCharacter then return end
				spawnOneGalaxy(cloud, targetPos, casterCharacter)
			end)
		end

	-- (cloud self-cleanup now lives in spawnCloud, shared with remote observers)
end

-- ===== ABILITY CONFIG LOOKUP =====
local function getAbilityConfig(skillName: string): any?
	local currentElement = getElement()
	local config = ElementConfig.getElementConfig(currentElement)
	if config then
		for _, ability in config.abilities do
			if ability.name == skillName then
				return ability
			end
		end
	end
	-- Fallback: search explicit element configs by skill name
	for key, val in ElementConfig do
		if typeof(val) == "table" and val.abilities then
			for _, ability in val.abilities do
				if ability.name == skillName then
					return ability
				end
			end
		end
	end
	return nil
end

-- ===== SKILL ACTIVATION =====
local function activateSkill(tool: Tool, skillName: string, currentElement: string, ability: any)
	local origin = if humanoidRootPart then humanoidRootPart.Position else Vector3.new()

	-- Lock the cursor target now so the local cast and the replicated event
	-- use the exact same impact point.
	local targetPos, _ = getClickTarget()

	-- Play the cast animation (the visual cast; the cloud holds in place while
	-- the galaxies keep falling for 8s after the 1.3s cast).
	playAnimation("GalaxyStrike", 1.0)

	-- Fire the remote so the server has a record of the activation and can
	-- replicate the VFX to every other client.
	SkillActivated:FireServer(skillName, Vector3.new(0, 0, -1), targetPos)

	-- Kick off the VFX in a coroutine so the client stays responsive during
	-- the 8s rain (the 6 spawns each run their own fall loops).
	task.spawn(function()
		local ok, err = pcall(vfxGalaxyStrike, origin, targetPos, currentCharacter)
		if not ok then
			warn("[celestial-client] vfxGalaxyStrike error:", err)
		end
	end)
end

-- ===== TOOL ACTIVATION (legacy path) =====
local function onToolActivated(tool: Tool)
	if isAttacking then return end
	if not humanoidRootPart then return end

	local skillName = tool:GetAttribute("SkillName") :: string?
	if not skillName or skillName ~= "GalaxyStrike" then return end

	local currentElement = getElement()
	if currentElement == "" then
		currentElement = tool:GetAttribute("Element") :: string or ""
	end
	if currentElement == "" then
		local ability = getAbilityConfig(skillName)
		if ability then currentElement = ability.element end
	end
	if currentElement == "" then return end

	local ability = getAbilityConfig(skillName)
	if not ability then return end

	local lastUsed = tool:GetAttribute("LastUsed") :: number?
	if lastUsed and tick() - lastUsed < ability.cooldown then
		print("[celestial-client] " .. skillName .. " on cooldown")
		return
	end

	tool:SetAttribute("LastUsed", tick())
	isAttacking = true
	local ok, err = pcall(activateSkill, tool, skillName, currentElement, ability)
	if not ok then warn("[celestial-client] Ability error:", err) end
	task.delay(0.4, function() isAttacking = false end)
end

-- ===== REQUEST SKILL ACTIVATION (toolbar) =====
local requestEvent = ReplicatedStorage:FindFirstChild("RequestSkillActivation")
if requestEvent and requestEvent:IsA("BindableEvent") then
	requestEvent.Event:Connect(function(tool: Tool, skillName: string, currentElement: string)
		if skillName ~= "GalaxyStrike" then return end
		if isAttacking then return end
		if not humanoidRootPart then return end

		local ability = getAbilityConfig(skillName)
		if not ability then return end

		if currentElement == "" then currentElement = tool:GetAttribute("Element") :: string or "" end
		if currentElement == "" then currentElement = ability.element end
		if currentElement == "" then return end

		local lastUsed = tool:GetAttribute("LastUsed") :: number?
		if lastUsed and tick() - lastUsed < ability.cooldown then
			print("[celestial-client] " .. skillName .. " on cooldown")
			return
		end
		tool:SetAttribute("LastUsed", tick())
		isAttacking = true
		local ok, err = pcall(activateSkill, tool, skillName, currentElement, ability)
		if not ok then warn("[celestial-client] Ability error:", err) end
		task.delay(0.4, function() isAttacking = false end)
	end)
	print("[celestial-client] RequestSkillActivation listener wired")
end

-- ===== CONNECT TOOLS =====
local function disconnectTools()
	for _, con in toolConnections do
		con:Disconnect()
	end
	toolConnections = {}
end

local function connectAllTools(character: Model)
	disconnectTools()
	local function hook(tool: Tool)
		local con = tool.Activated:Connect(function()
			onToolActivated(tool)
		end)
		table.insert(toolConnections, con)
	end
	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		for _, child in ipairs(backpack:GetChildren()) do
			if child:IsA("Tool") and child:GetAttribute("IsAbilityTool") then
				hook(child)
			end
		end
	end
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") and child:GetAttribute("IsAbilityTool") then
			hook(child)
		end
	end
	local workspaceChar = character.Parent
	if workspaceChar and workspaceChar:IsA("Model") then
		for _, child in ipairs(workspaceChar:GetChildren()) do
			if child:IsA("Tool") and child:GetAttribute("IsAbilityTool") then
				hook(child)
			end
		end
	end
end

-- ===== CHARACTER SETUP =====
local function onCharacterAdded(character: Model)
	currentCharacter = character
	humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
	humanoidRootPart = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?

	if humanoid then
		humanoid.RigType = Enum.HumanoidRigType.R6
		local animator = humanoid:FindFirstChild("Animator") :: Animator?
		if not animator then
			local newAnim = Instance.new("Animator")
			newAnim.Parent = humanoid
		end
	end

	local function tryConnect()
		connectAllTools(character)
	end
	-- Tools replicate from the server over a few frames; retry a few times.
	for _, delay in ipairs({0.1, 0.3, 0.6, 1.0, 2.0}) do
		task.delay(delay, tryConnect)
	end

	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		backpack.ChildAdded:Connect(function(child: Instance)
			if child:IsA("Tool") and child:GetAttribute("IsAbilityTool") then
				connectAllTools(character)
			end
		end)
		backpack.ChildRemoved:Connect(function(_child: Instance)
			connectAllTools(character)
		end)
	end
	character.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Tool") and child:GetAttribute("IsAbilityTool") then
			connectAllTools(character)
		end
	end)
	character.ChildRemoved:Connect(function(_child: Instance)
		connectAllTools(character)
	end)
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	onCharacterAdded(player.Character)
end

-- ===== NETWORKED VFX (from other players) =====
-- When another player casts Galaxy Strike, the server relays the caster's
-- locked target point: we show the charging cloud, and the caster separately
-- relays each impact ("GalaxyImpact") at its real moment. This keeps every
-- observer's impact VFX synced (no per-client re-simulation of the galaxy
-- fall, which previously made the VFX vanish early).
CombatVFX.OnClientEvent:Connect(function(eventType: string, a: any, b: any)
	if eventType == "GalaxyStrike" then
		-- Remote observer: show the charging cloud only. The galaxy rain is
		-- NOT re-simulated here (that was the source of the early-vanish
		-- desync); the caster relays each impact via "GalaxyImpact" events.
		local targetPos = b :: Vector3
		spawnCloud(targetPos)
	elseif eventType == "GalaxyImpact" then
		-- Authoritative impact point from the caster; render the impact VFX
		-- at the caster's moment with no falling galaxy.
		local impactPos = a :: Vector3
		onGalaxyImpact(nil, impactPos, false)
	end
end)

print("[celestial-client] Galaxy Strike client loaded")
