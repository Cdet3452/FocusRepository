--!strict
-- Fire Element — FlameTracker (3rd tool) client
-- Reverted from previous multi-tool system. Handles only the tracking fire attack.
-- Uses the user's VFX parts in Workspace: "trackfire" (projectile) and
-- "trackfireexplotion" (single explosion on first collision). The cloned
-- trackfire carries the user's particles; the trackfireexplotion VFX is
-- emitted ONCE and impact blocks are spawned slightly larger than standard.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local PhysicsService = game:GetService("PhysicsService")

-- Manual third-person camera follow. The menu's CameraController leaves
-- the camera in a scriptable cinematic position; Roblox's default
-- PlayerModule camera doesn't always hand off cleanly from Scriptable
-- to Custom, so the player gets stranded looking at the sky. This loop
-- forces the camera behind the character every frame during gameplay.
-- Cached reference to the MenuState.GameStarted BoolValue. The camera follow
-- loop runs every frame, so we resolve this once and read .Value each frame
-- instead of re-walking the hierarchy 60x/second.
-- NOTE: uses Players.LocalPlayer directly because the `player` local is
-- declared further down and isn't in scope here yet.
local gameStartedValue: BoolValue? = nil
local function resolveGameStartedValue()
	if gameStartedValue then return gameStartedValue end
	local localPlayer = Players.LocalPlayer
	if not localPlayer then return nil end
	local playerGui = localPlayer:FindFirstChild("PlayerGui")
	if not playerGui then return nil end
	local mainMenu = playerGui:FindFirstChild("MainMenuUI")
	if not mainMenu then return nil end
	local menuState = mainMenu:FindFirstChild("MenuState")
	if not menuState then return nil end
	local v = menuState:FindFirstChild("GameStarted")
	if v and v:IsA("BoolValue") then
		gameStartedValue = v
	end
	return gameStartedValue
end

local function isGameplayActive(): boolean
	local v = resolveGameStartedValue()
	if not v then return false end
	return v.Value
end

local function forcePlayerCamera()
	-- Use Roblox's built-in third-person camera. The custom Scriptable camera
	-- was causing jitter, stuck rotation, and wrong angles. Just set the
	-- subject to the humanoid and let Roblox's default camera handle the rest.
	task.defer(function()
		local character = Players.LocalPlayer and Players.LocalPlayer.Character
		if not character then return end
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then return end
		local camera = Workspace.CurrentCamera
		if not camera then return end
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = humanoid
	end)
end

local player = Players.LocalPlayer
local FireRemotes = ReplicatedStorage.ElementAbilities.Fire
local SkillActivated = FireRemotes.SkillActivated :: RemoteEvent
local CombatVFX = FireRemotes.CombatVFX :: RemoteEvent

-- ===== STATE =====
local currentCharacter: Model? = nil
local humanoidRootPart: BasePart? = nil
local toolConnections: { RBXScriptConnection } = {}

-- ===== HELPERS =====
local function getMouseDirection(): Vector3
	if not humanoidRootPart then return Vector3.new(0, 0, -1) end
	local camera = Workspace.CurrentCamera
	if not camera then return humanoidRootPart.CFrame.LookVector end
	local mousePos = UserInputService:GetMouseLocation()
	local unitRay = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	if currentCharacter then
		rayParams.FilterDescendantsInstances = { currentCharacter }
	end
	local rayResult = Workspace:Raycast(unitRay.Origin, unitRay.Direction * 1000, rayParams)
	local targetPos = if rayResult then rayResult.Position else unitRay.Origin + unitRay.Direction * 500
	local dir = targetPos - humanoidRootPart.Position
	if dir.Magnitude < 0.1 then return humanoidRootPart.CFrame.LookVector end
	return dir.Unit
end

-- Slightly larger than standard impact blocks (per pasted text spec)
local function spawnImpactBlocks(origin: Vector3, count: number)
	local blockShapes = { "Block", "Cylinder", "Wedge" }
	for i = 1, count do
		-- Slightly larger than the old fire-shot blocks
		local width = math.random(16, 36) / 10
		local depth = math.random(14, 30) / 10
		local height = math.random(8, 20) / 10
		local shape = blockShapes[math.random(1, 3)]
		local block: BasePart
		if shape == "Wedge" then
			block = Instance.new("WedgePart")
		else
			block = Instance.new("Part")
			if shape == "Cylinder" then block.Shape = Enum.PartType.Cylinder end
		end
		block.Size = Vector3.new(width, height, depth)
		block.Color = Color3.fromRGB(120, 100, 90)
		block.Material = Enum.Material.SmoothPlastic
		block.Anchored = false
		block.CanCollide = false
		block.CastShadow = false
		local angle = (i / count) * math.pi * 2 + math.random(-0.4, 0.4)
		local radius = math.random(4, 10)
		local yOff = math.random(-2, 6)
		block.Position = origin + Vector3.new(math.cos(angle) * radius, yOff, math.sin(angle) * radius)
		block.CFrame = block.CFrame * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		block.Parent = Workspace
		local bv = Instance.new("BodyVelocity")
		local outDir = (block.Position - origin).Unit
		bv.Velocity = outDir * math.random(25, 50) + Vector3.new(0, math.random(8, 20), 0)
		bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
		bv.Parent = block
		Debris:AddItem(bv, 0.4)
		local bav = Instance.new("BodyAngularVelocity")
		bav.AngularVelocity = Vector3.new(math.random(-25, 25), math.random(-25, 25), math.random(-25, 25))
		bav.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
		bav.Parent = block
		Debris:AddItem(bav, 0.5)
		task.delay(2.5 + math.random() * 1.5, function()
			if block and block.Parent then
				TweenService:Create(block, TweenInfo.new(0.8), { Transparency = 1 }):Play()
				task.delay(0.8, function()
					if block and block.Parent then block:Destroy() end
				end)
			end
		end)
	end
end



local ElementConfig = require(ReplicatedStorage.GachaSystem.ElementConfig)
local GachaConfig = require(ReplicatedStorage.GachaSystem.GachaConfig)
local FireAnimations = require(ReplicatedStorage.GachaSystem.FireAnimations)

-- ===== COLOR CONSTANTS =====
local C_WHITE = Color3.fromRGB(255, 255, 255)
local C_YELLOW = Color3.fromRGB(255, 240, 100)
local C_ORANGE = Color3.fromRGB(255, 160, 30)
local C_RED = Color3.fromRGB(255, 60, 10)
local C_DARK_RED = Color3.fromRGB(180, 30, 0)
local C_FLAME_CORE = Color3.fromRGB(255, 200, 50)
local C_FLAME_MID = Color3.fromRGB(255, 120, 20)
local C_FLAME_OUTER = Color3.fromRGB(200, 40, 5)
local C_BLACK_SMOKE = Color3.fromRGB(40, 20, 10)
local C_GOLD = Color3.fromRGB(255, 215, 0)

-- ===== STATE =====
local humanoid: Humanoid? = nil
local isAttacking: boolean = false

-- ===== SOUND ASSETS =====
local SFX = {
	FireShotCast = "rbxassetid://421058925",
	FireShotExplode = "rbxassetid://421058925",
	UppercutCast = "rbxassetid://311506727",
	UppercutHit = "rbxassetid://262562082",
	FlameTrackerCast = "rbxassetid://421058925",
	FlameTrackerHit = "rbxassetid://421058925",
	FlameSurgeCast = "rbxassetid://421058925",
	FlameSurgeHit = "rbxassetid://421058925",
	PhoenixBurstCharge = "rbxassetid://130775481",
	PhoenixBurstExplode = "rbxassetid://184776510",
	FirePillarCast = "rbxassetid://311506727",
	FirePillarImpact = "rbxassetid://421058925",
}

-- ===== HELPERS =====
local function getElement(): string
	local ls = player:FindFirstChild("leaderstats")
	if not ls then return "" end
	local es = ls:FindFirstChild("Element")
	if not es or not es:IsA("StringValue") then return "" end
	return es.Value
end

local function getClickDirection(): Vector3
	if not humanoidRootPart then return Vector3.new(0, 0, -1) end
	local camera = Workspace.CurrentCamera
	if not camera then return humanoidRootPart.CFrame.LookVector end

	local mousePos = UserInputService:GetMouseLocation()
	local unitRay = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	if currentCharacter then rayParams.FilterDescendantsInstances = { currentCharacter } end
	local rayResult = Workspace:Raycast(unitRay.Origin, unitRay.Direction * 1000, rayParams)
	local targetPos = if rayResult then rayResult.Position else unitRay.Origin + unitRay.Direction * 500
	local dir = targetPos - humanoidRootPart.Position
	if dir.Magnitude < 0.1 then return humanoidRootPart.CFrame.LookVector end
	return dir.Unit
end

-- Returns the world position the cursor is pointing at, plus the direction
-- from the player root to that point. Used for ground-targeted abilities
-- like Fire Pillar where the server needs the actual hit position.
local function getClickTarget(): (Vector3, Vector3)
	if not humanoidRootPart then
		return Vector3.new(), Vector3.new(0, 0, -1)
	end
	local camera = Workspace.CurrentCamera
	if not camera then
		local fwd = humanoidRootPart.CFrame.LookVector
		return humanoidRootPart.Position + fwd * 10, fwd
	end

	local mousePos = UserInputService:GetMouseLocation()
	local unitRay = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	if currentCharacter then rayParams.FilterDescendantsInstances = { currentCharacter } end
	local rayResult = Workspace:Raycast(unitRay.Origin, unitRay.Direction * 1000, rayParams)
	local targetPos = if rayResult then rayResult.Position else unitRay.Origin + unitRay.Direction * 500

	local offset = targetPos - humanoidRootPart.Position
	local dir = if offset.Magnitude < 0.1 then humanoidRootPart.CFrame.LookVector else offset.Unit
	return targetPos, dir
end

local function isSkillOnCooldown(skillName: string): boolean
	local currentElement = getElement()
	local config = ElementConfig.getElementConfig(currentElement)
	if not config then return false end
	for _, ability in config.abilities do
		if ability.name == skillName then
			local tool = player.Character:FindFirstChildOfClass("Tool")
			if not tool then return false end
			local lastUsed = tool:GetAttribute("LastUsed")
			if not lastUsed then return false end
			return tick() - lastUsed < ability.cooldown
		end
	end
	return false
end

-- ===== ANIMATION SYSTEM =====
local function playAnimation(animName: string, speed: number?): AnimationTrack?
	if not humanoid then return nil end
	local animId = FireAnimations.getAnimationId(animName)
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

-- ===== CAMERA SHAKE =====
-- Shake goes through the shared CameraShake bus owned by
-- PremiumCameraController, which is the single writer of camera.CFrame.
-- This script must NOT write camera.CFrame directly — doing so would
-- race with the controller's Last-priority write and either cancel the
-- shake or cause the visual jitter the user reported.
local CameraShakeEvent = ReplicatedStorage:WaitForChild("CameraShake") :: BindableEvent
local function cameraShake(intensity: number, duration: number)
	if intensity <= 0 or duration <= 0 then return end
	CameraShakeEvent:Fire(intensity, duration)
end

-- ===== PLAY SOUND =====
local function playSoundAt(position: Vector3, soundId: string, volume: number)
	local anchor = Instance.new("Part")
	anchor.Name = "SoundAnchor"
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Position = position
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.Transparency = 1
	anchor.Parent = Workspace
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume
	sound.PlaybackSpeed = 1
	sound.RollOffMinDistance = 10
	sound.RollOffMaxDistance = 150
	sound.Parent = anchor
	sound:Play()
	Debris:AddItem(anchor, 6)
end

-- ===== PARTICLE HELPER =====
local FIRE_TEXTURE = "rbxassetid://243098098"

local function addLight(parent: Instance, color: Color3, brightness: number, range: number): PointLight
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = brightness
	light.Range = range
	light.Shadows = false
	light.Parent = parent
	return light
end

local function oneShotEmitter(parent: Instance, pos: Vector3, color: ColorSequence, size: NumberSequence, lifetime: NumberRange, count: number, speed: NumberRange, spread: Vector2, lightEmission: number, brightness: number)
	local att = Instance.new("Attachment")
	att.Position = pos
	att.Parent = parent

	local pe = Instance.new("ParticleEmitter")
	pe.Color = color
	pe.Size = size
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	pe.Lifetime = lifetime
	pe.Rate = 0
	pe.Speed = speed
	pe.SpreadAngle = spread
	pe.Acceleration = Vector3.new(0, 2, 0)
	pe.RotSpeed = NumberRange.new(-180, 180)
	pe.LightEmission = lightEmission
	pe.LightInfluence = 0
	pe.Brightness = brightness
	pe.Texture = FIRE_TEXTURE
	pe.Parent = att

	pe:Emit(count)
	task.delay(0.1, function()
		att:Destroy()
	end)
end

-- ===== SCREEN FLASH EFFECT =====
local function screenFlash(color: Color3, transparency: number, duration: number)
	local gui = Instance.new("Frame")
	gui.Name = "ScreenFlash"
	gui.Size = UDim2.new(1, 0, 1, 0)
	gui.BackgroundColor3 = color
	gui.BackgroundTransparency = transparency
	gui.BorderSizePixel = 0
	gui.ZIndex = 10
	gui.Parent = player:WaitForChild("PlayerGui")

	TweenService:Create(gui, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 1}):Play()
	Debris:AddItem(gui, duration + 0.1)
end

-- ===== SHOCKWAVE RING HELPER =====
local function spawnShockwaveRing(center: Vector3, color: Color3, maxRadius: number, duration: number)
	local ring = Instance.new("Part")
	ring.Name = "ShockwaveRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.3, 0.5, 0.5)
	ring.Anchored = true
	ring.CanCollide = false
	ring.CastShadow = false
	ring.Color = color
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.3
	ring.CFrame = CFrame.new(center)
	ring.Parent = Workspace

	local startSize = 0.5
	local twInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tw = TweenService:Create(ring, twInfo, {
		Size = Vector3.new(0.05, maxRadius * 2, maxRadius * 2),
		Transparency = 1,
	})
	tw:Play()
	tw.Completed:Connect(function()
		ring:Destroy()
	end)
	Debris:AddItem(ring, duration + 0.1)
end

-- ===== HEAT DISTORTION HELPER =====
local function spawnHeatDistortion(position: Vector3, size: number, duration: number)
	local heat = Instance.new("Part")
	heat.Name = "HeatDistortion"
	heat.Shape = Enum.PartType.Ball
	heat.Size = Vector3.new(size, size * 0.3, size)
	heat.Anchored = true
	heat.CanCollide = false
	heat.CastShadow = false
	heat.Transparency = 0.95
	heat.Color = Color3.fromRGB(255, 200, 100)
	heat.Material = Enum.Material.Glass
	heat.Position = position + Vector3.new(0, 0.5, 0)
	heat.Parent = Workspace

	task.spawn(function()
		local elapsed = 0
		while heat and heat.Parent and elapsed < duration do
			elapsed += 0.03
			local wobble = math.sin(elapsed * 30) * 0.5
			local wobble2 = math.cos(elapsed * 25) * 0.3
			heat.CFrame = CFrame.new(position + Vector3.new(0, 0.5 + wobble2 * 0.2, 0)) * CFrame.Angles(wobble * 0.02, wobble2 * 0.02, wobble * 0.01)
			heat.Size = Vector3.new(size + math.sin(elapsed * 15) * 0.3, 0.3 + math.sin(elapsed * 20) * 0.1, size + math.cos(elapsed * 12) * 0.3)
			task.wait(0.03)
		end
		if heat and heat.Parent then heat:Destroy() end
	end)
	Debris:AddItem(heat, duration + 0.5)
end

-- ===== VFX: GENERIC ELEMENT CAST =====
local function vfxGenericElementCast(origin: Vector3, direction: Vector3, elementColor: Color3)
	-- Simple colored burst effect for elements without custom VFX
	local burst = Instance.new("Part")
	burst.Size = Vector3.new(4, 4, 4)
	burst.Shape = Enum.PartType.Ball
	burst.Anchored = true
	burst.CanCollide = false
	burst.Transparency = 0.4
	burst.Color = elementColor
	burst.Material = Enum.Material.Neon
	burst.CFrame = CFrame.new(origin + direction * 3)
	burst.Parent = Workspace
	Debris:AddItem(burst, 0.6)

	TweenService:Create(burst, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(8, 8, 8),
		Transparency = 1,
	}):Play()

	local light = Instance.new("PointLight")
	light.Color = elementColor
	light.Brightness = 3
	light.Range = 16
	light.Parent = burst
end

-- ===== VFX: FLAME SHOT =====
-- ===== FIREBALL PROJECTILE TEMPLATE =====
local FireballTemplate = ReplicatedStorage:FindFirstChild("FireAssets") and ReplicatedStorage.FireAssets:FindFirstChild("fireball") :: Part?
if not FireballTemplate then
	warn("[fire-client] fireball template not found in ReplicatedStorage.FireAssets; FireShot projectile VFX will be skipped")
end

-- ===== MESH VFX HELPERS (reusable building blocks for mesh-based VFX) =====
-- Each helper creates a Part with a simple shape, parents it to Workspace,
-- runs a short tween loop to animate its size/transparency/position, and
-- destroys itself. Used to add extra mesh VFX to all fire abilities without
-- inlining 60+ lines of boilerplate per function.

-- Flat horizontal ring (cylinder rotated 90°) that expands from startRadius
-- to startRadius + maxRadius over `duration` seconds, fading out.
local function meshExpandingRing(position: Vector3, color: Color3, startRadius: number, maxRadius: number, duration: number, thickness: number?, yOffset: number?, parent: Instance?)
	local ring = Instance.new("Part")
	ring.Name = "MeshExpandingRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Color = color
	ring.Material = Enum.Material.Neon
	ring.Anchored = true; ring.CanCollide = false; ring.CanQuery = false; ring.CanTouch = false; ring.CastShadow = false
	ring.Transparency = 0.3
	local t0 = thickness or 0.5
	ring.Size = Vector3.new(t0, startRadius, startRadius)
	ring.CFrame = CFrame.new(position + Vector3.new(0, yOffset or 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = parent or Workspace
	task.spawn(function()
		local s = tick()
		while ring and ring.Parent do
			local t = tick() - s; if t > duration then break end
			local sz = startRadius + t * maxRadius
			ring.Size = Vector3.new(t0 + t * 0.8, sz, sz)
			ring.Transparency = 0.3 + t * 1.3
			ring.CFrame = CFrame.new(position + Vector3.new(0, yOffset or 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90))
			task.wait(0.03)
		end
		if ring and ring.Parent then ring:Destroy() end
	end)
	return ring
end

-- Expanding sphere (ball) that grows from 1 to maxSize over `duration`, fading.
local function meshExpandingSphere(position: Vector3, color: Color3, maxSize: number, duration: number, startTransparency: number?, material: Enum.Material?, parent: Instance?)
	local sphere = Instance.new("Part")
	sphere.Name = "MeshExpandingSphere"
	sphere.Shape = Enum.PartType.Ball
	sphere.Color = color
	sphere.Material = material or Enum.Material.Neon
	sphere.Anchored = true; sphere.CanCollide = false; sphere.CanQuery = false; sphere.CanTouch = false; sphere.CastShadow = false
	sphere.Transparency = startTransparency or 0.3
	sphere.Size = Vector3.new(1, 1, 1)
	sphere.CFrame = CFrame.new(position)
	sphere.Parent = parent or Workspace
	task.spawn(function()
		local s = tick()
		while sphere and sphere.Parent do
			local t = tick() - s; if t > duration then break end
			local sz = 1 + t * (maxSize - 1)
			sphere.Size = Vector3.new(sz, sz, sz)
			sphere.Transparency = (startTransparency or 0.3) + t * 1.2
			sphere.CFrame = CFrame.new(position)
			task.wait(0.03)
		end
		if sphere and sphere.Parent then sphere:Destroy() end
	end)
	return sphere
end

-- Vertical pillar (cylinder) that rises from `position` and widens as it climbs.
-- `maxRise` = total Y travel; `maxWidth` = final X/Y radius; `duration` = total time.
local function meshVerticalPillar(position: Vector3, color: Color3, maxRise: number, maxWidth: number, duration: number, material: Enum.Material?, startYOffset: number?, parent: Instance?)
	local pillar = Instance.new("Part")
	pillar.Name = "MeshVerticalPillar"
	pillar.Shape = Enum.PartType.Cylinder
	pillar.Color = color
	pillar.Material = material or Enum.Material.SmoothPlastic
	pillar.Anchored = true; pillar.CanCollide = false; pillar.CanQuery = false; pillar.CanTouch = false; pillar.CastShadow = false
	pillar.Transparency = 0.5
	pillar.Size = Vector3.new(1, 1, 1)
	pillar.CFrame = CFrame.new(position + Vector3.new(0, startYOffset or 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	pillar.Parent = parent or Workspace
	task.spawn(function()
		local s = tick()
		while pillar and pillar.Parent do
			local t = tick() - s; if t > duration then break end
			local rise = t * maxRise
			local w = 1 + t * (maxWidth - 1)
			pillar.Size = Vector3.new(w, 1 + t * maxWidth * 0.3, 1 + t * maxWidth * 0.3)
			pillar.CFrame = CFrame.new(position + Vector3.new(0, (startYOffset or 2) + rise, 0)) * CFrame.Angles(0, 0, math.rad(90))
			pillar.Transparency = 0.5 + t * 0.5
			task.wait(0.03)
		end
		if pillar and pillar.Parent then pillar:Destroy() end
	end)
	return pillar
end

-- Flat dark scorch disk on the ground that expands and lingers, then fades.
local function meshScorchDisk(position: Vector3, maxRadius: number, duration: number, parent: Instance?)
	local disk = Instance.new("Part")
	disk.Name = "MeshScorchDisk"
	disk.Shape = Enum.PartType.Cylinder
	disk.Color = Color3.fromRGB(20, 10, 5)
	disk.Material = Enum.Material.SmoothPlastic
	disk.Anchored = true; disk.CanCollide = false; disk.CanQuery = false; disk.CanTouch = false; disk.CastShadow = false
	disk.Transparency = 0.2
	disk.Size = Vector3.new(0.3, 2, 2)
	disk.CFrame = CFrame.new(position + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	disk.Parent = parent or Workspace
	task.spawn(function()
		local s = tick()
		while disk and disk.Parent do
			local t = tick() - s; if t > duration then break end
			local r = 2 + t * maxRadius
			disk.Size = Vector3.new(0.3, r, r)
			disk.Transparency = 0.2 + t * 0.4
			disk.CFrame = CFrame.new(position + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
			task.wait(0.03)
		end
		if disk and disk.Parent then
			local fade = TweenService:Create(disk, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 })
			fade:Play()
			fade.Completed:Once(function()
				if disk and disk.Parent then disk:Destroy() end
			end)
		end
	end)
	return disk
end

-- ===== FIRE SHOT: hold the fireball (with its VFX) in the right hand, then throw it =====

-- Builds the fireball part (from the ReplicatedStorage template if available,
-- otherwise a procedural glowing ball) with its fire + smoke trail and point
-- light. Parented to the given folder and returned.
local function createFireballPart(folder: Folder): Part
	local fireball: Part
	if FireballTemplate then
		fireball = FireballTemplate:Clone() :: Part
	else
		fireball = Instance.new("Part")
		fireball.Size = Vector3.new(2, 2, 2)
		fireball.Shape = Enum.PartType.Ball
		fireball.Material = Enum.Material.Neon
		fireball.Color = C_ORANGE
		local ballAtt = Instance.new("Attachment")
		ballAtt.Name = "FireballAttachment"
		ballAtt.Parent = fireball
		local ballLight = Instance.new("PointLight")
		ballLight.Name = "FireballLight"
		ballLight.Color = C_ORANGE
		ballLight.Brightness = 5
		ballLight.Range = 18
		ballLight.Shadows = false
		ballLight.Parent = fireball
	end
	fireball.Name = "Fireball"
	fireball.CastShadow = false
	fireball.Anchored = false
	fireball.CanCollide = false
	fireball.CanQuery = false
	fireball.CanTouch = false
	fireball.Size = Vector3.new(3, 3, 3)
	fireball.Parent = folder

	-- Fire trail + smoke on the fireball
	local trailAtt = fireball:FindFirstChild("FireballAttachment")
	if trailAtt then
		local trailPE = Instance.new("ParticleEmitter")
		trailPE.Name = "FireTrail"
		trailPE.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, C_YELLOW),
			ColorSequenceKeypoint.new(0.5, C_ORANGE),
			ColorSequenceKeypoint.new(1, C_RED),
		})
		trailPE.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(0.5, 1.5), NumberSequenceKeypoint.new(1, 0) })
		trailPE.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.3), NumberSequenceKeypoint.new(1, 1) })
		trailPE.Lifetime = NumberRange.new(0.3, 0.7)
		trailPE.Rate = 80
		trailPE.Speed = NumberRange.new(1, 4)
		trailPE.SpreadAngle = Vector2.new(80, 80)
		trailPE.Acceleration = Vector3.new(0, 5, 0)
		trailPE.RotSpeed = NumberRange.new(-180, 180)
		trailPE.LightEmission = 1
		trailPE.LightInfluence = 0
		trailPE.Brightness = 3
		trailPE.Texture = FIRE_TEXTURE
		trailPE.Parent = trailAtt

		local smokePE = Instance.new("ParticleEmitter")
		smokePE.Name = "SmokeTrail"
		smokePE.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(80, 40, 20)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(50, 25, 10)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 10, 5)),
		})
		smokePE.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(0.5, 2), NumberSequenceKeypoint.new(1, 0) })
		smokePE.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(0.5, 0.8), NumberSequenceKeypoint.new(1, 1) })
		smokePE.Lifetime = NumberRange.new(0.5, 1.0)
		smokePE.Rate = 40
		smokePE.Speed = NumberRange.new(0.5, 2)
		smokePE.SpreadAngle = Vector2.new(40, 40)
		smokePE.Acceleration = Vector3.new(0, 3, 0)
		smokePE.RotSpeed = NumberRange.new(-60, 60)
		smokePE.LightEmission = 0.3
		smokePE.LightInfluence = 0
		smokePE.Brightness = 0.5
		smokePE.Texture = FIRE_TEXTURE
		smokePE.Parent = trailAtt
	end
	return fireball
end

-- Holds the fireball (with its VFX) in the player's right hand during the
-- wind-up. Welds it to the Right Arm so it follows the cast animation. Returns
-- the fireball, its folder, and the weld so the launcher can detach and throw.
local function vfxFlameShotHold(character: Model): (Part, Folder, WeldConstraint?)
	local folder = Instance.new("Folder")
	folder.Name = "FlameShotProjectile"
	folder.Parent = Workspace
	local fireball = createFireballPart(folder)

	local rightArm = character:FindFirstChild("Right Arm") :: BasePart?
	local weld: WeldConstraint? = nil
	if rightArm then
		fireball.CFrame = rightArm.CFrame * CFrame.new(0, -2.0, -1.4)
		weld = Instance.new("WeldConstraint")
		weld.Part0 = rightArm
		weld.Part1 = fireball
		weld.Parent = fireball
	else
		-- No Right Arm (unexpected): hold it anchored in front of the chest.
		local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		fireball.Anchored = true
		if hrp then
			fireball.CFrame = hrp.CFrame * CFrame.new(0, 1.5, -2)
		end
	end
	return fireball, folder, weld
end

-- Detaches the held fireball and throws it from startPos along direction.
local function vfxFlameShotLaunch(fireball: Part, folder: Folder, weld: WeldConstraint?, startPos: Vector3, direction: Vector3)
	if weld then weld:Destroy() end
	fireball.Anchored = true
	fireball.Position = startPos

	local ability = ElementConfig.Fire.abilities[1]
	local speed = ability.projectileSpeed or 120
	local maxRange = ability.range or 160
	local maxDuration = ability.duration or 3.5
	local traveled = 0
	local startTime = tick()

	task.spawn(function()
		while folder and folder.Parent and traveled < maxRange and tick() - startTime < maxDuration do
			local dt = task.wait(0.03)
			local step = speed * dt
			traveled += step
			local newPos = startPos + direction * traveled
			fireball.Position = newPos
			local pulse = 1 + math.sin(tick() * 12) * 0.12
			fireball.Size = Vector3.new(4 * pulse, 4 * pulse, 4 * pulse)
		end

		-- Fade out if reached max range
		if folder and folder.Parent then
			local fade = TweenService:Create(fireball, TweenInfo.new(0.3), { Transparency = 1 })
			fade:Play()
			fade.Completed:Connect(function()
				if folder and folder.Parent then folder:Destroy() end
			end)
		end
	end)
end

-- ===== FIREBALL EXPLOSION TEMPLATE (used by FireShot) =====
local FireballExplosionTemplate = ReplicatedStorage:FindFirstChild("FireAssets") and ReplicatedStorage.FireAssets:FindFirstChild("fireballexplotion") :: Part?
if not FireballExplosionTemplate then
	warn("[fire-client] fireballexplotion template not found in ReplicatedStorage.FireAssets; FireShot explosion VFX will be skipped")
end

-- ===== CRATER (IMPACT BLOCKS) =====
-- Map surface materials to their base colors (for matching crater blocks)
local MATERIAL_COLORS: { [Enum.Material]: Color3 } = {
	[Enum.Material.Grass] = Color3.fromRGB(86, 130, 50),
	[Enum.Material.LeafyGrass] = Color3.fromRGB(76, 122, 40),
	[Enum.Material.Ground] = Color3.fromRGB(106, 84, 56),
	[Enum.Material.Mud] = Color3.fromRGB(70, 56, 40),
	[Enum.Material.Sand] = Color3.fromRGB(196, 176, 118),
	[Enum.Material.Sandstone] = Color3.fromRGB(170, 144, 96),
	[Enum.Material.Rock] = Color3.fromRGB(112, 106, 100),
	[Enum.Material.Slate] = Color3.fromRGB(68, 68, 72),
	[Enum.Material.Basalt] = Color3.fromRGB(60, 60, 64),
	[Enum.Material.CrackedLava] = Color3.fromRGB(52, 28, 16),
	[Enum.Material.Brick] = Color3.fromRGB(148, 76, 52),
	[Enum.Material.Cobblestone] = Color3.fromRGB(116, 110, 102),
	[Enum.Material.Concrete] = Color3.fromRGB(156, 156, 156),
	[Enum.Material.Pavement] = Color3.fromRGB(108, 108, 108),
	[Enum.Material.Asphalt] = Color3.fromRGB(58, 58, 62),
	[Enum.Material.Limestone] = Color3.fromRGB(200, 190, 170),
	[Enum.Material.Wood] = Color3.fromRGB(124, 84, 44),
	[Enum.Material.WoodPlanks] = Color3.fromRGB(140, 100, 56),
	[Enum.Material.Metal] = Color3.fromRGB(128, 132, 136),
	[Enum.Material.Snow] = Color3.fromRGB(232, 236, 240),
	[Enum.Material.Ice] = Color3.fromRGB(208, 232, 244),
	[Enum.Material.Glacier] = Color3.fromRGB(184, 212, 232),
	[Enum.Material.Salt] = Color3.fromRGB(232, 232, 220),
	[Enum.Material.DiamondPlate] = Color3.fromRGB(148, 148, 152),
}

local function vfxFlameShotCrater(position: Vector3, surfaceMat: Enum.Material?)
	-- Resolve the base color from the detected surface material
	local baseColor = MATERIAL_COLORS[surfaceMat] or Color3.fromRGB(60, 60, 60)
	-- Scorched/darkened version: 35% brightness for a charred impact look
	local scorchColor = Color3.new(
		baseColor.R * 0.35,
		baseColor.G * 0.35,
		baseColor.B * 0.35
	)

	local blockCount = 16
	local craterRadius = 3.5

	for i = 1, blockCount do
		-- Evenly spaced around the circle, with small jitter for a natural look
		local angle = (i / blockCount) * math.pi * 2 + (math.random() - 0.5) * 0.15
		local dist = craterRadius + (math.random() - 0.5) * 0.6
		local bx = position.X + math.cos(angle) * dist
		local bz = position.Z + math.sin(angle) * dist
		local by = position.Y + 0.05  -- sit just above the ground

		-- Flat, elongated blocks: wide, thin, variable length
		local sizeX = 1.0 + math.random() * 0.8
		local sizeY = 0.3 + math.random() * 0.2
		local sizeZ = 0.7 + math.random() * 0.7

		local block = Instance.new("Part")
		block.Name = "CraterBlock"
		block.Size = Vector3.new(sizeX, sizeY, sizeZ)
		-- Only rotate on Y so blocks stay flat on the ground
		block.CFrame = CFrame.new(bx, by, bz) * CFrame.Angles(0, math.rad(math.random(0, 360)), 0)
		block.Anchored = true
		block.CanCollide = false
		-- Use the surface material (or CorrodedMetal as a safe fallback)
		block.Material = surfaceMat or Enum.Material.CorrodedMetal
		block.Color = scorchColor
		block.Parent = Workspace

		Debris:AddItem(block, 8.0 + math.random() * 4.0)
	end
end

-- MeteorShower crater: ground-anchored dark scorch blocks with a 1s fade-out
-- and extra VFX (expanding ring + ember particles). Uses the actual ground
-- Y from a downward raycast so the blocks sit on the surface instead of
-- floating at the meteor's mid-air impact position.
local function vfxMeteorCrater(position: Vector3)
	-- Raycast straight down from the impact to find the actual ground level
	local surfaceRay = workspace:Raycast(position + Vector3.new(0, 4, 0), Vector3.new(0, -20, 0))
	if not surfaceRay then return end
	local groundPos = surfaceRay.Position
	local surfaceMat = surfaceRay.Material

	local baseColor = MATERIAL_COLORS[surfaceMat] or Color3.fromRGB(60, 60, 60)
	local scorchColor = Color3.new(baseColor.R * 0.35, baseColor.G * 0.35, baseColor.B * 0.35)

	-- ===== CRATER BLOCKS =====
	-- 14 small dark blocks ringed around the impact, anchored to groundPos.Y
	-- so they sit flush on the surface. Fade from opacity 0 to 1 over the
	-- final 1s of their 2s lifetime so they appear instantly, hold, then
	-- dissolve smoothly.
	local blockCount = 14
	local craterRadius = 2.8
	local blocks: { Part } = {}

	for i = 1, blockCount do
		local angle = (i / blockCount) * math.pi * 2 + (math.random() - 0.5) * 0.15
		local dist = craterRadius + (math.random() - 0.5) * 0.4
		local bx = groundPos.X + math.cos(angle) * dist
		local bz = groundPos.Z + math.sin(angle) * dist
		local by = groundPos.Y + 0.05

		local sizeX = 0.7 + math.random() * 0.5
		local sizeY = 0.2 + math.random() * 0.15
		local sizeZ = 0.5 + math.random() * 0.5

		local block = Instance.new("Part")
		block.Name = "MeteorCraterBlock"
		block.Size = Vector3.new(sizeX, sizeY, sizeZ)
		block.CFrame = CFrame.new(bx, by, bz) * CFrame.Angles(0, math.rad(math.random(0, 360)), 0)
		block.Anchored = true
		block.CanCollide = false
		block.Material = surfaceMat or Enum.Material.CorrodedMetal
		block.Color = scorchColor
		block.Transparency = 0
		block.Parent = Workspace
		table.insert(blocks, block)
	end

	-- Fade the blocks from transparency 0 to 1 over the last 1s of their
	-- 2s lifetime. The first 1s they stay solid, then they dissolve.
	task.delay(1.0, function()
		local fadeStart = tick()
		local fadeDuration = 1.0
		while tick() - fadeStart < fadeDuration do
			local t = (tick() - fadeStart) / fadeDuration
			for _, block in blocks do
				if block and block.Parent then
					block.Transparency = t
				end
			end
			task.wait(0.03)
		end
		for _, block in blocks do
			if block and block.Parent then block:Destroy() end
		end
	end)

	-- ===== EXTRA VFX: EXPANDING DARK RING =====
	-- A flat dark disc on the ground that expands and fades, reinforcing the
	-- "scorched earth" look on top of the blocks.
	local ring = Instance.new("Part")
	ring.Name = "MeteorCraterRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Color = Color3.new(0, 0, 0)
	ring.Material = Enum.Material.SmoothPlastic
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Transparency = 0.2
	ring.Size = Vector3.new(0.3, 2, 2)
	ring.CFrame = CFrame.new(groundPos + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = Workspace
	task.spawn(function()
		local s = tick()
		while ring and ring.Parent do
			local t = tick() - s
			if t > 1.2 then break end
			local size = 2 + t * 12
			ring.Size = Vector3.new(0.3 + t * 0.5, size, size)
			ring.Transparency = 0.2 + t * 0.8
			task.wait(0.03)
		end
		if ring and ring.Parent then ring:Destroy() end
	end)

	-- ===== EXTRA VFX: EMBER PARTICLE BURST =====
	-- A short burst of glowing embers shooting up and outward from the
	-- crater, adding a hot "freshly hit" feel that the static blocks don't.
	local emberAtt = Instance.new("Attachment")
	emberAtt.Name = "MeteorCraterEmberAtt"
	emberAtt.WorldPosition = groundPos + Vector3.new(0, 0.3, 0)
	emberAtt.Parent = Workspace
	local emberPE = Instance.new("ParticleEmitter")
	emberPE.Name = "MeteorCraterEmbers"
	emberPE.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 200, 80)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 100, 30)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(80, 20, 5)),
	})
	emberPE.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(0.5, 0.6),
		NumberSequenceKeypoint.new(1, 0),
	})
	emberPE.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	emberPE.Lifetime = NumberRange.new(0.4, 0.9)
	emberPE.Rate = 0
	emberPE.Speed = NumberRange.new(4, 10)
	emberPE.SpreadAngle = Vector2.new(160, 160)
	emberPE.Acceleration = Vector3.new(0, -10, 0)
	emberPE.LightEmission = 1
	emberPE.LightInfluence = 0
	emberPE.Brightness = 3
	emberPE.Texture = FIRE_TEXTURE
	emberPE.Parent = emberAtt
	emberPE:Emit(20)
	Debris:AddItem(emberAtt, 1.5)

	-- ===== EXTRA VFX: CENTER DARK SPOT =====
	-- A small dark decal-like disc at the exact impact point.
	local spot = Instance.new("Part")
	spot.Name = "MeteorCraterSpot"
	spot.Shape = Enum.PartType.Cylinder
	spot.Color = Color3.new(0.05, 0.05, 0.05)
	spot.Material = Enum.Material.SmoothPlastic
	spot.Anchored = true
	spot.CanCollide = false
	spot.CanQuery = false
	spot.CanTouch = false
	spot.CastShadow = false
	spot.Transparency = 0
	spot.Size = Vector3.new(0.1, 1.5, 1.5)
	spot.CFrame = CFrame.new(groundPos + Vector3.new(0, 0.02, 0)) * CFrame.Angles(0, 0, math.rad(90))
	spot.Parent = Workspace
	Debris:AddItem(spot, 2.0)
end

-- Forward declaration: spawnFireDebris is defined further down but referenced by
-- vfxFlameShotExplode below, so declare the local up front and assign it later.
local spawnFireDebris: (Vector3, Color3, number, number, number, number, number, string?) -> ()

local function vfxFlameShotExplode(position: Vector3, surfaceMat: Enum.Material?)
	playSoundAt(position, SFX.FireShotExplode, 1.0)

	-- Spawn crater impact blocks at the impact point
	vfxFlameShotCrater(position, surfaceMat)

	-- Clone the fireball explosion part and place it at the impact point (once).
	-- Use a procedural fallback (cylinder with one-shot fire burst) if the
	-- ReplicatedStorage template is missing from the playtest.
	local explosion: Part
	if FireballExplosionTemplate then
		explosion = FireballExplosionTemplate:Clone() :: Part
	else
		explosion = Instance.new("Part")
		explosion.Size = Vector3.new(4, 1, 2)
		explosion.Shape = Enum.PartType.Cylinder
		local light = Instance.new("PointLight")
		light.Color = C_ORANGE
		light.Brightness = 12
		light.Range = 28
		light.Shadows = false
		light.Parent = explosion
	end
	explosion.Name = "fireball explosion"
	explosion.Anchored = true
	explosion.CanCollide = false
	explosion.CastShadow = false
	explosion.Position = position
	-- Hide the host part so only the explosion particles are visible.
	-- Particles emit from inside the part and are unaffected by Part.Transparency.
	explosion.Transparency = 1
	explosion.LocalTransparencyModifier = 1
	explosion.Material = Enum.Material.ForceField
	explosion.Color = Color3.fromRGB(0, 0, 0)
	for _, child in explosion:GetChildren() do
		if child:IsA("SpecialMesh") or child:IsA("MeshPart") or child:IsA("BlockMesh") then
			child:Destroy()
		end
	end
	explosion.Parent = Workspace

	-- Emit all particle emitters on the cloned part exactly once
	for _, desc in explosion:GetDescendants() do
		if desc:IsA("ParticleEmitter") then
			desc:Emit(desc:GetAttribute("EmitCount") or 25)
		end
	end

	local miniExplodeTemplate = getVFXTemplate("miniexplode")
	if miniExplodeTemplate then
		local miniClone = miniExplodeTemplate:Clone()
		if miniClone:IsA("BasePart") then
			miniClone.CFrame = CFrame.new(position)
		elseif miniClone:IsA("Attachment") then
			miniClone.WorldPosition = position
		end
		miniClone.Parent = Workspace

		for _, desc in miniClone:GetDescendants() do
			if desc:IsA("ParticleEmitter") then
				desc:Emit(desc:GetAttribute("EmitCount") or 25)
			end
		end
		Debris:AddItem(miniClone, 3.0)
	else
		warn("miniexplode template missing")
	end

	-- Flash light burst
	local flashLight = Instance.new("PointLight")
	flashLight.Color = C_ORANGE
	flashLight.Brightness = 20
	flashLight.Range = 40
	flashLight.Shadows = false
	flashLight.Parent = explosion
	task.spawn(function()
		local start = tick()
		while flashLight and flashLight.Parent and tick() - start < 0.5 do
			flashLight.Brightness = 20 * (1 - (tick() - start) / 0.5)
			task.wait()
		end
		if flashLight then flashLight:Destroy() end
	end)

	-- Shockwave accent rings
	spawnShockwaveRing(position, C_ORANGE, 14, 0.5)
	task.delay(0.12, function()
		spawnShockwaveRing(position, C_YELLOW, 18, 0.4)
	end)

	-- Folder to hold all extra MeshPart VFX for cleanup
	local explosionFX = Instance.new("Folder")
	explosionFX.Name = "FireballExplosionFX"
	explosionFX.Parent = Workspace

	-- ===== INNER WHITE-HOT CORE SPHERE =====
	-- A bright white sphere that pops in and shrinks fast
	-- (Part with Ball shape — SPHERE_MESH_ID asset is not accessible in this game)
	local coreSphere = Instance.new("Part")
	coreSphere.Name = "ExplosionCore"
	coreSphere.Shape = Enum.PartType.Ball
	coreSphere.Color = C_WHITE
	coreSphere.Material = Enum.Material.Neon
	coreSphere.Anchored = true
	coreSphere.CanCollide = false
	coreSphere.CanQuery = false
	coreSphere.CanTouch = false
	coreSphere.CastShadow = false
	coreSphere.Transparency = 0.1
	coreSphere.Size = Vector3.new(1, 1, 1)
	coreSphere.CFrame = CFrame.new(position)
	coreSphere.Parent = explosionFX

	task.spawn(function()
		local startTick = tick()
		while coreSphere and coreSphere.Parent do
			local t = tick() - startTick
			if t > 0.5 then break end
			local growT = math.min(1, t / 0.15)
			local size = 16 * growT
			coreSphere.Size = Vector3.new(size, size, size)
			coreSphere.Transparency = 0.1 + t * 1.6
			task.wait(0.03)
		end
		if coreSphere and coreSphere.Parent then coreSphere:Destroy() end
	end)
	Debris:AddItem(coreSphere, 1.0)

	-- ===== MID ORANGE EXPANDING SPHERE =====
	local midSphere = Instance.new("Part")
	midSphere.Name = "ExplosionMid"
	midSphere.Shape = Enum.PartType.Ball
	midSphere.Color = C_ORANGE
	midSphere.Material = Enum.Material.Neon
	midSphere.Anchored = true
	midSphere.CanCollide = false
	midSphere.CanQuery = false
	midSphere.CanTouch = false
	midSphere.CastShadow = false
	midSphere.Transparency = 0.3
	midSphere.Size = Vector3.new(4, 4, 4)
	midSphere.CFrame = CFrame.new(position)
	midSphere.Parent = explosionFX

	task.spawn(function()
		local startTick = tick()
		while midSphere and midSphere.Parent do
			local t = tick() - startTick
			if t > 0.8 then break end
			local size = 4 + t * 38
			midSphere.Size = Vector3.new(size, size, size)
			midSphere.Transparency = 0.3 + t * 0.85
			task.wait(0.03)
		end
		if midSphere and midSphere.Parent then midSphere:Destroy() end
	end)
	Debris:AddItem(midSphere, 1.2)

	-- ===== OUTER RED EXPANDING SPHERE =====
	task.delay(0.08, function()
		local outerSphere = Instance.new("Part")
		outerSphere.Name = "ExplosionOuter"
		outerSphere.Shape = Enum.PartType.Ball
		outerSphere.Color = C_RED
		outerSphere.Material = Enum.Material.Neon
		outerSphere.Anchored = true
		outerSphere.CanCollide = false
		outerSphere.CanQuery = false
		outerSphere.CanTouch = false
		outerSphere.CastShadow = false
		outerSphere.Transparency = 0.4
		outerSphere.Size = Vector3.new(2, 2, 2)
		outerSphere.CFrame = CFrame.new(position)
		outerSphere.Parent = explosionFX

		local startTick = tick()
		while outerSphere and outerSphere.Parent do
			local t = tick() - startTick
			if t > 1.2 then break end
			local size = 2 + t * 55
			outerSphere.Size = Vector3.new(size, size, size)
			outerSphere.Transparency = 0.4 + t * 0.55
			task.wait(0.03)
		end
		if outerSphere and outerSphere.Parent then outerSphere:Destroy() end
	end)
	Debris:AddItem(outerSphere, 1.5)

	-- ===== GROUND SCORCH DISK =====
	-- A flat dark charred cylinder on the ground that lingers
	local scorchDisk = Instance.new("Part")
	scorchDisk.Name = "ExplosionScorchDisk"
	scorchDisk.Shape = Enum.PartType.Cylinder
	scorchDisk.Color = Color3.fromRGB(20, 10, 5)
	scorchDisk.Material = Enum.Material.SmoothPlastic
	scorchDisk.Anchored = true
	scorchDisk.CanCollide = false
	scorchDisk.CanQuery = false
	scorchDisk.CanTouch = false
	scorchDisk.CastShadow = false
	scorchDisk.Transparency = 0.2
	scorchDisk.Size = Vector3.new(0.3, 4, 4)
	scorchDisk.CFrame = CFrame.new(position + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	scorchDisk.Parent = explosionFX

	task.spawn(function()
		local startTick = tick()
		while scorchDisk and scorchDisk.Parent do
			local t = tick() - startTick
			if t > 1.0 then break end
			local radius = 4 + t * 28
			scorchDisk.Size = Vector3.new(0.3, radius, radius)
			scorchDisk.Transparency = 0.2 + t * 0.3
			task.wait(0.03)
		end
		-- Hold for a short time then fade out and destroy
		if scorchDisk and scorchDisk.Parent then
			task.wait(1.5)
			if scorchDisk and scorchDisk.Parent then
				local fade = TweenService:Create(scorchDisk, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					Transparency = 1,
				})
				fade:Play()
				fade.Completed:Once(function()
					if scorchDisk and scorchDisk.Parent then scorchDisk:Destroy() end
				end)
			end
		end
	end)
	Debris:AddItem(scorchDisk, 3.5)

	-- ===== SMOKE COLUMN (DARK VERTICAL CYLINDER) =====
	task.delay(0.15, function()
		local smokeCol = Instance.new("Part")
		smokeCol.Name = "ExplosionSmokeColumn"
		smokeCol.Shape = Enum.PartType.Cylinder
		smokeCol.Color = Color3.fromRGB(50, 25, 12)
		smokeCol.Material = Enum.Material.SmoothPlastic
		smokeCol.Anchored = true
		smokeCol.CanCollide = false
		smokeCol.CanQuery = false
		smokeCol.CanTouch = false
		smokeCol.CastShadow = false
		smokeCol.Transparency = 0.5
		smokeCol.Size = Vector3.new(8, 6, 6)
		smokeCol.CFrame = CFrame.new(position + Vector3.new(0, 4, 0)) * CFrame.Angles(0, 0, math.rad(90))
		smokeCol.Parent = explosionFX

		local startTick = tick()
		while smokeCol and smokeCol.Parent do
			local t = tick() - startTick
			if t > 2.0 then break end
			local rise = t * 6
			local width = 6 + t * 5
			smokeCol.Size = Vector3.new(width, 6 + t * 14, 6 + t * 14)
			smokeCol.CFrame = CFrame.new(position + Vector3.new(0, 4 + rise, 0)) * CFrame.Angles(0, 0, math.rad(90))
			smokeCol.Transparency = 0.5 + t * 0.4
			task.wait(0.03)
		end
		if smokeCol and smokeCol.Parent then smokeCol:Destroy() end
	end)
	Debris:AddItem(smokeCol, 2.5)

	-- ===== MESHPART: ROCK DEBRIS CHUNKS (HEAVY) =====
	-- 14 dark charred cylinder rocks flying outward
	spawnFireDebris(position + Vector3.new(0, 0.5, 0), C_DARK_RED, 1.4, 14, 22, 16, 1.4, CYLINDER_MESH_ID)
	-- 10 glowing embered sphere chunks
	spawnFireDebris(position + Vector3.new(0, 0.3, 0), C_ORANGE, 0.7, 10, 18, 22, 1.1, SPHERE_MESH_ID)

	-- ===== HEAT DISTORTION =====
	spawnHeatDistortion(position, 20, 1.5)

	cameraShake(1.0, 0.3)
	screenFlash(C_ORANGE, 0.1, 0.2)

	-- Belt-and-suspenders: Debris destroys the explosion and FX folder if anything fails
	Debris:AddItem(explosion, 2.0)
	Debris:AddItem(explosionFX, 4.0)
end


-- ===== VFX: FIRE PILLAR =====
-- Local "telegraph" visual that the caster sees at their cursor before
-- the pillar erupts. Cloned from the workspace `adverticepillar` template.
-- CRITICAL: Use FindFirstChild (not WaitForChild) so the script doesn't hang
-- if the template is missing from the playtest DataModel. The telegraph is
-- non-critical — the rest of the fire combat system must keep working.
-- (Previously used WaitForChild which blocked the entire script and broke
-- ALL 4 fire tools, not just Fire Pillar.)
local function getVFXTemplate(name: string): Part?
	-- Prefer the workspace template; fall back to ReplicatedStorage.VFXTemplates
	-- (saved by the editor so the templates are guaranteed to be in playtest
	-- DataModels even when they vanish from the workspace).
	return Workspace:FindFirstChild(name) :: Part?
		or (ReplicatedStorage:FindFirstChild("VFXTemplates")
			and ReplicatedStorage.VFXTemplates:FindFirstChild(name) :: Part?)
end

local AdverticePillarTemplate = getVFXTemplate("adverticepillar")
assert(AdverticePillarTemplate, "[fire-client] adverticepillar template not found in workspace or ReplicatedStorage.VFXTemplates")

local function vfxFirePillarTelegraph(targetPos: Vector3)
	playSoundAt(targetPos, SFX.FirePillarCast, 0.8, 1.1)

	-- Clone the user's adverticepillar part from workspace AS-IS.
	-- Keep its original material, color, transparency, and meshes so the
	-- user's particle design is fully visible.
	local indicator: Part = AdverticePillarTemplate:Clone()
	indicator.Name = "FirePillarIndicator"
	indicator.Anchored = true
	indicator.CanCollide = false
	indicator.CanQuery = false
	indicator.CanTouch = false
	indicator.CastShadow = false
	-- Position the indicator flat on the ground at the target location
	indicator.CFrame = CFrame.new(targetPos.X, targetPos.Y + indicator.Size.Y / 2, targetPos.Z)
	indicator.Parent = Workspace

	-- Show the indicator for 1 second, then destroy so the pillar can replace it
	task.delay(1.0, function()
		if indicator and indicator.Parent then
			indicator:Destroy()
		end
	end)
end

-- Erupting pillar of fire. Plays for every client when the server broadcasts
-- "FirePillar". Cloned from the workspace `pillarflame` template.
local PillarFlameTemplate = getVFXTemplate("pillarflame")
assert(PillarFlameTemplate, "[fire-client] pillarflame template not found in workspace or ReplicatedStorage.VFXTemplates")

-- Cylinder / sphere mesh IDs (Roblox built-in primitive meshes).
-- NOTE: these asset IDs are blocked by the game's asset permissions
-- (lacking capability NotAccessible), so spawnFireDebris falls back to
-- a Part with the matching built-in Shape (Cylinder / Ball) instead.
local CYLINDER_MESH_ID = "rbxassetid://1033714"
local SPHERE_MESH_ID = "rbxassetid://36869986"

-- Helper: spawn a tumbling debris chunk that flies outward.
-- Uses a Part with Shape=Cylinder/Ball for the built-in primitive meshes
-- (the asset IDs above are not accessible to LocalScripts in this game).
-- For any other meshId it still tries MeshPart.MeshId, but guards with pcall.
function spawnFireDebris(origin: Vector3, baseColor: Color3, baseSize: number, count: number, outwardSpeed: number, upwardSpeed: number, lifetime: number, meshId: string?)
	for i = 1, count do
		local debris
		if meshId == CYLINDER_MESH_ID then
			debris = Instance.new("Part")
			debris.Name = "FireDebris"
			debris.Shape = Enum.PartType.Cylinder
		elseif meshId == SPHERE_MESH_ID then
			debris = Instance.new("Part")
			debris.Name = "FireDebris"
			debris.Shape = Enum.PartType.Ball
		else
			debris = Instance.new("MeshPart")
			debris.Name = "FireDebris"
			if meshId and meshId ~= "" then
				pcall(function() debris.MeshId = meshId end)
			end
		end
		local sx = baseSize * (0.5 + math.random() * 0.7)
		local sy = baseSize * (0.4 + math.random() * 0.5)
		local sz = baseSize * (0.5 + math.random() * 0.7)
		debris.Size = Vector3.new(sx, sy, sz)
		debris.Color = baseColor
		debris.Material = Enum.Material.SmoothPlastic
		debris.Anchored = true
		debris.CanCollide = false
		debris.CanQuery = false
		debris.CanTouch = false
		debris.CastShadow = false
		debris.Transparency = 0
		debris.Position = origin

		local angle = (i / count) * math.pi * 2 + math.random() * 0.6
		local speedMult = 0.7 + math.random() * 0.6
		local vx = math.cos(angle) * outwardSpeed * speedMult
		local vz = math.sin(angle) * outwardSpeed * speedMult
		local vy = upwardSpeed * (0.6 + math.random() * 0.8)

		local startPos = origin
		local endPos = origin + Vector3.new(vx, vy, vz)
		local rotation = CFrame.Angles(
			math.rad(math.random(-180, 180)),
			math.rad(math.random(-180, 180)),
			math.rad(math.random(-180, 180))
		)

		debris.CFrame = CFrame.new(startPos) * rotation
		debris.Parent = Workspace

		-- Animate translation + rotation + fade
		task.spawn(function()
			local startTick = tick()
			while debris and debris.Parent and tick() - startTick < lifetime do
				local t = (tick() - startTick) / lifetime
				local gravity = -25 * t * t
				local pos = startPos:Lerp(endPos, t) + Vector3.new(0, gravity, 0)
				local rot = rotation * CFrame.Angles(t * 8, t * 6, t * 4)
				debris.CFrame = CFrame.new(pos) * rot
				debris.Transparency = t * t
				debris.Size = Vector3.new(sx * (1 - t * 0.4), sy * (1 - t * 0.4), sz * (1 - t * 0.4))
				task.wait(0.03)
			end
			if debris and debris.Parent then debris:Destroy() end
		end)
	end
end

local function vfxFirePillar(targetPos: Vector3)
	playSoundAt(targetPos, SFX.FirePillarImpact, 1.2, 0.9)
	cameraShake(1.2, 0.4)
	screenFlash(C_ORANGE, 0.12, 0.25)

	-- Clone the user's pillarflame part from workspace AS-IS.
	-- Keep its original size, material, color, transparency, meshes, and
	-- particle emitters so the user's fire pillar design is fully visible.
	local pillar: Part = PillarFlameTemplate:Clone()

	pillar.Name = "FirePillar"
	pillar.Anchored = true
	pillar.CanCollide = false
	pillar.CanQuery = false
	pillar.CanTouch = false
	pillar.CastShadow = false

	-- Orient the pillar vertically (its longest dimension becomes the height)
	-- and lift it so its base sits on the ground at the target location.
	local baseSize = pillar.Size
	local pillarHeight = math.max(baseSize.X, baseSize.Y, baseSize.Z)
	pillar.CFrame = CFrame.new(targetPos.X, targetPos.Y + pillarHeight / 2, targetPos.Z)
	pillar.Parent = Workspace

	-- Add a point light on the pillar for dramatic lighting (keeps the user's
	-- template particles and any PointLight the user already placed on it).
	local hasLight = false
	for _, desc in pillar:GetDescendants() do
		if desc:IsA("PointLight") then hasLight = true break end
	end
	if not hasLight then
		local light = Instance.new("PointLight")
		light.Color = C_ORANGE
		light.Brightness = 18
		light.Range = 35
		light.Shadows = false
		light.Parent = pillar
	end

	-- Heat distortion at the base
	spawnHeatDistortion(targetPos + Vector3.new(0, 4, 0), 16, 1.5)

	-- Rock debris flying outward from the base
	spawnFireDebris(targetPos + Vector3.new(0, 0.5, 0), C_DARK_RED, 1.2, 12, 18, 14, 1.2, CYLINDER_MESH_ID)
	spawnFireDebris(targetPos + Vector3.new(0, 0.3, 0), C_ORANGE, 0.8, 8, 14, 18, 1.0, SPHERE_MESH_ID)
	-- ============================================================
	-- VFX PARTS: extra MeshPart effects layered on the pillar
	-- ============================================================
	local pillarFX = Instance.new("Folder")
	pillarFX.Name = "FirePillarFX"
	pillarFX.Parent = Workspace
	-- White-hot core sphere expanding from the pillar
	local coreSphere = Instance.new("Part")
	coreSphere.Name = "PillarCore"
	coreSphere.Shape = Enum.PartType.Ball
	coreSphere.Color = C_WHITE
	coreSphere.Material = Enum.Material.Neon
	coreSphere.Anchored = true
	coreSphere.CanCollide = false
	coreSphere.CanQuery = false
	coreSphere.CanTouch = false
	coreSphere.CastShadow = false
	coreSphere.Transparency = 0.1
	coreSphere.Size = Vector3.new(1, 1, 1)
	coreSphere.CFrame = CFrame.new(targetPos + Vector3.new(0, pillarHeight * 0.4, 0))
	coreSphere.Parent = pillarFX
	task.spawn(function()
		local startTick = tick()
		while coreSphere and coreSphere.Parent do
			local t = tick() - startTick
			if t > 0.7 then break end
			local growT = math.min(1, t / 0.18)
			local size = 14 * growT
			coreSphere.Size = Vector3.new(size, size, size)
			coreSphere.Transparency = 0.1 + t * 1.3
			task.wait(0.03)
		end
		if coreSphere and coreSphere.Parent then coreSphere:Destroy() end
	end)
	Debris:AddItem(coreSphere, 1.0)
	-- Mid orange expanding sphere (slightly delayed)
	task.delay(0.05, function()
		local midSphere = Instance.new("Part")
		midSphere.Name = "PillarMid"
		midSphere.Shape = Enum.PartType.Ball
		midSphere.Color = C_ORANGE
		midSphere.Material = Enum.Material.Neon
		midSphere.Anchored = true
		midSphere.CanCollide = false
		midSphere.CanQuery = false
		midSphere.CanTouch = false
		midSphere.CastShadow = false
		midSphere.Transparency = 0.3
		midSphere.Size = Vector3.new(4, 4, 4)
		midSphere.CFrame = CFrame.new(targetPos + Vector3.new(0, pillarHeight * 0.35, 0))
		midSphere.Parent = pillarFX
		local startTick = tick()
		while midSphere and midSphere.Parent do
			local t = tick() - startTick
			if t > 1.0 then break end
			local size = 4 + t * 32
			midSphere.Size = Vector3.new(size, size, size)
			midSphere.Transparency = 0.3 + t * 0.7
			task.wait(0.03)
		end
		if midSphere and midSphere.Parent then midSphere:Destroy() end
	end)
	-- Horizontal glowing rings (3 of them at different heights, rotating)
	for ringIdx, ringY in ipairs({ 0.25, 0.55, 0.85 }) do
		task.delay((ringIdx - 1) * 0.08, function()
			local ring = Instance.new("Part")
			ring.Name = "PillarRing" .. ringIdx
			ring.Shape = Enum.PartType.Cylinder
			ring.Color = ringIdx == 2 and C_YELLOW or C_ORANGE
			ring.Material = Enum.Material.Neon
			ring.Anchored = true
			ring.CanCollide = false
			ring.CanQuery = false
			ring.CanTouch = false
			ring.CastShadow = false
			ring.Transparency = 0.4
			local ringRadius = 4 + ringIdx * 1.5
			ring.Size = Vector3.new(0.6, ringRadius, ringRadius)
			ring.CFrame = CFrame.new(targetPos + Vector3.new(0, pillarHeight * ringY, 0)) * CFrame.Angles(0, 0, math.rad(90))
			ring.Parent = pillarFX
			local startTick = tick()
			local baseRot = (ringIdx - 1) * math.pi / 3
			while ring and ring.Parent do
				local t = tick() - startTick
				if t > 2.5 then break end
				local size = ringRadius + t * 8
				ring.Size = Vector3.new(0.6, size, size)
				ring.Transparency = 0.4 + t * 0.25
				ring.CFrame = CFrame.new(targetPos + Vector3.new(0, pillarHeight * ringY, 0))
					* CFrame.Angles(0, math.rad(baseRot + t * 60), math.rad(90))
				task.wait(0.03)
			end
			if ring and ring.Parent then ring:Destroy() end
		end)
	end
	-- Rising fire sphere that travels from the base to the top of the pillar
	task.spawn(function()
		local startTick = tick()
		local riseDuration = 0.6
		local riseSphere = Instance.new("Part")
		riseSphere.Name = "PillarRiseSphere"
		riseSphere.Shape = Enum.PartType.Ball
		riseSphere.Color = C_WHITE
		riseSphere.Material = Enum.Material.Neon
		riseSphere.Anchored = true
		riseSphere.CanCollide = false
		riseSphere.CanQuery = false
		riseSphere.CanTouch = false
		riseSphere.CastShadow = false
		riseSphere.Transparency = 0.2
		riseSphere.Size = Vector3.new(2, 2, 2)
		riseSphere.CFrame = CFrame.new(targetPos + Vector3.new(0, 0.5, 0))
		riseSphere.Parent = pillarFX
		while riseSphere and riseSphere.Parent do
			local t = tick() - startTick
			if t > riseDuration then break end
			local frac = t / riseDuration
			local y = 0.5 + (pillarHeight + 2) * frac
			local size = 2 + frac * 3
			riseSphere.Size = Vector3.new(size, size, size)
			riseSphere.Transparency = 0.2 + frac * 0.6
			riseSphere.CFrame = CFrame.new(targetPos + Vector3.new(0, y, 0))
			task.wait(0.03)
		end
		if riseSphere and riseSphere.Parent then riseSphere:Destroy() end
	end)
	-- Ground scorch disk (dark, flat, lingers briefly)
	local scorchDisk = Instance.new("Part")
	scorchDisk.Name = "PillarScorchDisk"
	scorchDisk.Shape = Enum.PartType.Cylinder
	scorchDisk.Color = Color3.fromRGB(20, 10, 5)
	scorchDisk.Material = Enum.Material.SmoothPlastic
	scorchDisk.Anchored = true
	scorchDisk.CanCollide = false
	scorchDisk.CanQuery = false
	scorchDisk.CanTouch = false
	scorchDisk.CastShadow = false
	scorchDisk.Transparency = 0.2
	scorchDisk.Size = Vector3.new(0.3, 4, 4)
	scorchDisk.CFrame = CFrame.new(targetPos + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	scorchDisk.Parent = pillarFX
	task.spawn(function()
		local startTick = tick()
		while scorchDisk and scorchDisk.Parent do
			local t = tick() - startTick
			if t > 1.2 then break end
			local radius = 4 + t * 18
			scorchDisk.Size = Vector3.new(0.3, radius, radius)
			scorchDisk.Transparency = 0.2 + t * 0.4
			task.wait(0.03)
		end
		if scorchDisk and scorchDisk.Parent then
			local fade = TweenService:Create(scorchDisk, TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Transparency = 1,
			})
			fade:Play()
			fade.Completed:Once(function()
				if scorchDisk and scorchDisk.Parent then scorchDisk:Destroy() end
			end)
		end
	end)
	Debris:AddItem(scorchDisk, 3.0)
	-- Dark smoke column rising above the pillar
	task.delay(0.15, function()
		local smokeCol = Instance.new("Part")
		smokeCol.Name = "PillarSmokeColumn"
		smokeCol.Shape = Enum.PartType.Cylinder
		smokeCol.Color = Color3.fromRGB(50, 25, 12)
		smokeCol.Material = Enum.Material.SmoothPlastic
		smokeCol.Anchored = true
		smokeCol.CanCollide = false
		smokeCol.CanQuery = false
		smokeCol.CanTouch = false
		smokeCol.CastShadow = false
		smokeCol.Transparency = 0.5
		smokeCol.Size = Vector3.new(8, 6, 6)
		smokeCol.CFrame = CFrame.new(targetPos + Vector3.new(0, pillarHeight + 4, 0)) * CFrame.Angles(0, 0, math.rad(90))
		smokeCol.Parent = pillarFX
		local startTick = tick()
		while smokeCol and smokeCol.Parent do
			local t = tick() - startTick
			if t > 2.5 then break end
			local rise = t * 6
			local width = 6 + t * 4
			smokeCol.Size = Vector3.new(width, 6 + t * 12, 6 + t * 12)
			smokeCol.CFrame = CFrame.new(targetPos + Vector3.new(0, pillarHeight + 4 + rise, 0)) * CFrame.Angles(0, 0, math.rad(90))
			smokeCol.Transparency = 0.5 + t * 0.3
			task.wait(0.03)
		end
		if smokeCol and smokeCol.Parent then smokeCol:Destroy() end
	end)
	Debris:AddItem(pillarFX, 4.5)

	-- Hold the pillar visible for 3 seconds (its particles play out),
	-- then disable the emitters and destroy.
	task.delay(3.0, function()
		if not pillar or not pillar.Parent then return end
		for _, desc in pillar:GetDescendants() do
			if desc:IsA("ParticleEmitter") then
				desc.Enabled = false
			end
		end
	end)

	task.delay(3.5, function()
		if pillar and pillar.Parent then pillar:Destroy() end
	end)

	-- Hard safeguard: destroy at t=5.0s no matter what
	task.delay(5.0, function()
		if pillar and pillar.Parent then pillar:Destroy() end
	end)

	-- ===== EXTRA MESH VFX: MID RING + TOP SPHERE + DARK TOP COLUMN =====
	meshExpandingRing(targetPos + Vector3.new(0, pillarHeight * 0.5, 0), C_YELLOW, 4, 14, 0.6, 0.5, 0.15)
	meshExpandingSphere(targetPos + Vector3.new(0, pillarHeight * 0.7, 0), C_RED, 18, 0.8, 0.4)
	meshVerticalPillar(targetPos + Vector3.new(0, pillarHeight, 0), Color3.fromRGB(80, 35, 12), 6, 4, 1.0)
end





-- ===== VFX: FLAME SURGE =====
local function vfxFlameSurge(origin: Vector3, direction: Vector3)
	local anchor = Instance.new("Part")
	anchor.Name = "FlameSurgeVFX"
	anchor.Size = Vector3.new(0.5, 0.5, 0.5)
	anchor.Position = origin
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.Transparency = 1
	anchor.Parent = Workspace

	-- Ground burst ignition
	oneShotEmitter(anchor, Vector3.new(0, -1.5, 0), ColorSequence.new({
		ColorSequenceKeypoint.new(0, C_WHITE),
		ColorSequenceKeypoint.new(0.2, C_YELLOW),
		ColorSequenceKeypoint.new(0.5, C_ORANGE),
		ColorSequenceKeypoint.new(1, C_RED),
	}), NumberSequence.new({
		NumberSequenceKeypoint.new(0, 3),
		NumberSequenceKeypoint.new(0.5, 8),
		NumberSequenceKeypoint.new(1, 0),
	}), NumberRange.new(0.2, 0.5), 70, NumberRange.new(14, 30), Vector2.new(80, 80), 1, 7)

	-- Forward fire blast
	oneShotEmitter(anchor, Vector3.new(), ColorSequence.new({
		ColorSequenceKeypoint.new(0, C_WHITE),
		ColorSequenceKeypoint.new(0.3, C_YELLOW),
		ColorSequenceKeypoint.new(0.7, C_ORANGE),
		ColorSequenceKeypoint.new(1, C_DARK_RED),
	}), NumberSequence.new({
		NumberSequenceKeypoint.new(0, 4),
		NumberSequenceKeypoint.new(0.5, 10),
		NumberSequenceKeypoint.new(1, 0),
	}), NumberRange.new(0.15, 0.4), 80, NumberRange.new(18, 35), Vector2.new(30, 30), 1, 8)

	-- Sparks
	oneShotEmitter(anchor, Vector3.new(), ColorSequence.new({
		ColorSequenceKeypoint.new(0, C_GOLD),
		ColorSequenceKeypoint.new(0.5, C_WHITE),
		ColorSequenceKeypoint.new(1, C_YELLOW),
	}), NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(0.3, 2.5),
		NumberSequenceKeypoint.new(1, 0),
	}), NumberRange.new(0.1, 0.4), 50, NumberRange.new(12, 30), Vector2.new(100, 100), 1, 7)

	addLight(anchor, C_YELLOW, 16, 35)
	cameraShake(0.8, 0.25)
	playSoundAt(origin, SFX.FlameSurgeCast, 1.2)
	screenFlash(C_YELLOW, 0.2, 0.15)

	-- ===== MESH VFX: EXPANDING FIRE HALO RINGS (surge burst) =====
	local haloFX = Instance.new("Folder")
	haloFX.Name = "FlameSurgeHaloFX"
	haloFX.Parent = Workspace
	for ringIdx, ringInfo in ipairs({ { delay = 0.00, color = C_YELLOW, maxR = 22, dur = 0.55 }, { delay = 0.10, color = C_ORANGE, maxR = 30, dur = 0.70 }, { delay = 0.20, color = C_RED,    maxR = 38, dur = 0.85 } }) do
		task.delay(ringInfo.delay, function()
			local ring = Instance.new("Part")
			ring.Name = "SurgeHalo" .. ringIdx
			ring.Shape = Enum.PartType.Cylinder
			ring.Color = ringInfo.color
			ring.Material = Enum.Material.Neon
			ring.Anchored = true
			ring.CanCollide = false
			ring.CanQuery = false
			ring.CanTouch = false
			ring.CastShadow = false
			ring.Transparency = 0.2
			ring.Size = Vector3.new(0.6, 2, 2)
			ring.CFrame = CFrame.new(origin + Vector3.new(0, -1, 0)) * CFrame.Angles(0, 0, math.rad(90))
			ring.Parent = haloFX
			local startTick = tick()
			while ring and ring.Parent do
				local t = tick() - startTick
				if t > ringInfo.dur then break end
				local frac = t / ringInfo.dur
				local size = 2 + frac * ringInfo.maxR
				ring.Size = Vector3.new(0.6 + frac * 0.8, size, size)
				ring.Transparency = 0.2 + frac * 0.7
				ring.CFrame = CFrame.new(origin + Vector3.new(0, -1 + frac * 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
				task.wait(0.03)
			end
			if ring and ring.Parent then ring:Destroy() end
		end)
	end
	-- Vertical pillar orb that rises during the surge
	task.spawn(function()
		local pillarOrb = Instance.new("Part")
		pillarOrb.Name = "SurgePillarOrb"
		pillarOrb.Shape = Enum.PartType.Ball
		pillarOrb.Color = C_ORANGE
		pillarOrb.Material = Enum.Material.Neon
		pillarOrb.Anchored = true
		pillarOrb.CanCollide = false
		pillarOrb.CanQuery = false
		pillarOrb.CanTouch = false
		pillarOrb.CastShadow = false
		pillarOrb.Transparency = 0.3
		pillarOrb.Size = Vector3.new(2, 2, 2)
		pillarOrb.CFrame = CFrame.new(origin)
		pillarOrb.Parent = haloFX
		local startTick = tick()
		while pillarOrb and pillarOrb.Parent do
			local t = tick() - startTick
			if t > 0.5 then break end
			local rise = t * 14
			local size = 2 + t * 6
			pillarOrb.Size = Vector3.new(size, size, size)
			pillarOrb.Transparency = 0.3 + t * 1.2
			pillarOrb.CFrame = CFrame.new(origin + Vector3.new(0, rise, 0))
			task.wait(0.03)
		end
		if pillarOrb and pillarOrb.Parent then pillarOrb:Destroy() end
	end)
	Debris:AddItem(haloFX, 1.3)

	-- ===== EXTRA MESH VFX: DELAYED RED RING + ORANGE SPHERE + DARK COLUMN =====
	meshExpandingRing(origin + Vector3.new(0, -1, 0), C_RED, 2, 20, 0.6, 0.5, -1)
	meshExpandingSphere(origin, C_ORANGE, 10, 0.5, 0.3)
	meshVerticalPillar(origin, Color3.fromRGB(80, 35, 12), 5, 4, 0.7)

	-- Create fire trail that follows the dash path
	local trailFolder = Instance.new("Folder")
	trailFolder.Name = "FlameSurgeTrail"
	trailFolder.Parent = Workspace

	task.spawn(function()
		-- Fire trail along the dash path - drops fire patches along the way
		local trailLength = 40
		local segmentCount = 10
		for i = 1, segmentCount do
			if not trailFolder.Parent then break end
			local frac = i / segmentCount
			local trailPos = origin + direction * trailLength * frac
			local trailAnchor = Instance.new("Part")
			trailAnchor.Name = "TrailSegment"
			trailAnchor.Size = Vector3.new(0.5, 0.5, 0.5)
			trailAnchor.Position = trailPos + Vector3.new(0, -1, 0)
			trailAnchor.Anchored = true
			trailAnchor.CanCollide = false
			trailAnchor.Transparency = 1
			trailAnchor.Parent = trailFolder

			oneShotEmitter(trailAnchor, Vector3.new(), ColorSequence.new({
				ColorSequenceKeypoint.new(0, C_YELLOW),
				ColorSequenceKeypoint.new(0.5, C_ORANGE),
				ColorSequenceKeypoint.new(1, C_RED),
			}), NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1.5),
				NumberSequenceKeypoint.new(0.5, 4),
				NumberSequenceKeypoint.new(1, 0),
			}), NumberRange.new(0.3, 0.7), 20, NumberRange.new(2, 6), Vector2.new(60, 60), 1, 4)

			task.wait(0.05)
		end
		task.delay(0.8, function()
			if trailFolder and trailFolder.Parent then trailFolder:Destroy() end
		end)
	end)

	task.delay(0.4, anchor.Destroy, anchor)
end

local function vfxFlameSurgeHit(position: Vector3, direction: Vector3)
	local anchor = Instance.new("Part")
	anchor.Name = "FlameSurgeHitVFX"
	anchor.Size = Vector3.new(0.5, 0.5, 0.5)
	anchor.Position = position
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.Transparency = 1
	anchor.Parent = Workspace

	-- Dynamic flash light
	local flashLight = Instance.new("PointLight")
	flashLight.Color = C_WHITE
	flashLight.Brightness = 40
	flashLight.Range = 70
	flashLight.Shadows = false
	flashLight.Parent = anchor
	task.spawn(function()
		local start = tick()
		while flashLight and flashLight.Parent and tick() - start < 0.6 do
			flashLight.Brightness = 40 * (1 - (tick() - start) / 0.6)
			task.wait()
		end
		if flashLight then flashLight:Destroy() end
	end)

	-- Massive slam burst
	oneShotEmitter(anchor, Vector3.new(), ColorSequence.new({
		ColorSequenceKeypoint.new(0, C_WHITE),
		ColorSequenceKeypoint.new(0.15, C_YELLOW),
		ColorSequenceKeypoint.new(0.4, C_ORANGE),
		ColorSequenceKeypoint.new(0.7, C_RED),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 5, 0)),
	}), NumberSequence.new({
		NumberSequenceKeypoint.new(0, 10),
		NumberSequenceKeypoint.new(0.2, 22),
		NumberSequenceKeypoint.new(0.5, 28),
		NumberSequenceKeypoint.new(0.8, 12),
		NumberSequenceKeypoint.new(1, 0),
	}), NumberRange.new(0.3, 0.8), 100, NumberRange.new(18, 50), Vector2.new(120, 120), 1, 14)

	-- Ring burst outward
	oneShotEmitter(anchor, Vector3.new(), ColorSequence.new({
		ColorSequenceKeypoint.new(0, C_WHITE),
		ColorSequenceKeypoint.new(0.3, C_YELLOW),
		ColorSequenceKeypoint.new(1, C_RED),
	}), NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.5),
		NumberSequenceKeypoint.new(0.5, 8),
		NumberSequenceKeypoint.new(1, 0),
	}), NumberRange.new(0.2, 0.6), 80, NumberRange.new(25, 60), Vector2.new(10, 10), 1, 12)

	-- Ember shower
	oneShotEmitter(anchor, Vector3.new(), ColorSequence.new({
		ColorSequenceKeypoint.new(0, C_GOLD),
		ColorSequenceKeypoint.new(0.5, C_ORANGE),
		ColorSequenceKeypoint.new(1, C_RED),
	}), NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.8),
		NumberSequenceKeypoint.new(0.5, 3),
		NumberSequenceKeypoint.new(1, 0),
	}), NumberRange.new(0.5, 1.5), 70, NumberRange.new(4, 12), Vector2.new(180, 180), 1, 5)

	-- Shockwave rings
	spawnShockwaveRing(position, C_YELLOW, 25, 0.7)
	task.delay(0.12, function()
		spawnShockwaveRing(position, C_ORANGE, 30, 0.6)
	end)

	-- Heat distortion
	spawnHeatDistortion(position, 18, 1.2)

	-- ===== EXTRA MESH VFX: WHITE-HOT CORE + GROUND RING + DARK COLUMN =====
	meshExpandingSphere(position, C_WHITE, 20, 0.5, 0.1)
	meshExpandingRing(position + Vector3.new(0, 0.3, 0), C_ORANGE, 3, 22, 0.6, 0.5, 0.3)
	meshVerticalPillar(position, Color3.fromRGB(80, 35, 12), 7, 5, 1.0)

	addLight(anchor, C_YELLOW, 35, 60)
	addLight(anchor, C_ORANGE, 25, 80)
	cameraShake(2.0, 0.6)
	playSoundAt(position, SFX.FlameSurgeHit, 1.5)
	screenFlash(C_ORANGE, 0.06, 0.4)

	task.delay(1.2, anchor.Destroy, anchor)
end

-- ===== VFX: FLAME TRACKER =====
-- 5 fire discs spawn behind the player, slightly above, randomized within 0.9 studs.
-- They launch one by one with a 0.40s delay, each traveling in the mouse direction
-- at the moment of its own launch. On collision, the trackfireexplotion VFX fires once
-- and all remaining projectiles are cancelled. Impact blocks are spawned slightly larger
-- than the standard flame-shot crater for a stronger visual hit.
-- The workspace parts (trackfire / trackfireexplotion) are used only as size/position
-- hosts. All particle effects are attached procedurally by the helpers below.
local TrackFireTemplate = getVFXTemplate("trackfire")
assert(TrackFireTemplate, "[fire-client] trackfire template not found in workspace or ReplicatedStorage.VFXTemplates")
local TrackFireExplosionTemplate = getVFXTemplate("trackfireexplotion")
assert(TrackFireExplosionTemplate, "[fire-client] trackfireexplotion template not found in workspace or ReplicatedStorage.VFXTemplates")

-- Procedural VFX for a moving trackfire disc. Adds fire trail, dark smoke, ember
-- sparks, and a glow light to the cloned projectile's Attachment.
local function decorateTrackFireProj(host: BasePart)
	local att = host:FindFirstChild("Attachment") :: Attachment?
	if not att then
		att = Instance.new("Attachment")
		att.Name = "Attachment"
		att.Parent = host
	end

	-- Main fire trail
	local trail = Instance.new("ParticleEmitter")
	trail.Name = "TrackFireTrail"
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, C_WHITE),
		ColorSequenceKeypoint.new(0.2, C_YELLOW),
		ColorSequenceKeypoint.new(0.5, C_ORANGE),
		ColorSequenceKeypoint.new(0.85, C_RED),
		ColorSequenceKeypoint.new(1, C_DARK_RED),
	})
	trail.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.6),
		NumberSequenceKeypoint.new(0.5, 2.4),
		NumberSequenceKeypoint.new(1, 0),
	})
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Lifetime = NumberRange.new(0.25, 0.55)
	trail.Rate = 90
	trail.Speed = NumberRange.new(2, 6)
	trail.SpreadAngle = Vector2.new(50, 50)
	trail.Acceleration = Vector3.new(0, 1.5, 0)
	trail.RotSpeed = NumberRange.new(-180, 180)
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.Brightness = 4
	trail.Texture = FIRE_TEXTURE
	trail.Parent = att

	-- Dark smoke trailing behind
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "TrackFireSmoke"
	smoke.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(60, 30, 15)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(30, 15, 8)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 5, 2)),
	})
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.8),
		NumberSequenceKeypoint.new(0.5, 2.0),
		NumberSequenceKeypoint.new(1, 0),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(0.5, 0.7),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Lifetime = NumberRange.new(0.4, 0.8)
	smoke.Rate = 50
	smoke.Speed = NumberRange.new(1, 3)
	smoke.SpreadAngle = Vector2.new(40, 40)
	smoke.Acceleration = Vector3.new(0, 2, 0)
	smoke.RotSpeed = NumberRange.new(-30, 30)
	smoke.LightEmission = 0.2
	smoke.LightInfluence = 0
	smoke.Brightness = 0.5
	smoke.Texture = FIRE_TEXTURE
	smoke.Parent = att

	-- Glowing ember sparks
	local embers = Instance.new("ParticleEmitter")
	embers.Name = "TrackFireEmbers"
	embers.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 220, 80)),
		ColorSequenceKeypoint.new(0.5, C_ORANGE),
		ColorSequenceKeypoint.new(1, C_RED),
	})
	embers.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(0.4, 0.8),
		NumberSequenceKeypoint.new(1, 0),
	})
	embers.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	embers.Lifetime = NumberRange.new(0.4, 0.9)
	embers.Rate = 60
	embers.Speed = NumberRange.new(3, 8)
	embers.SpreadAngle = Vector2.new(70, 70)
	embers.Acceleration = Vector3.new(0, 4, 0)
	embers.RotSpeed = NumberRange.new(-180, 180)
	embers.LightEmission = 1
	embers.LightInfluence = 0
	embers.Brightness = 5
	embers.Texture = FIRE_TEXTURE
	embers.Parent = att

	-- Glow light to make the disc read as a fire source
	local light = Instance.new("PointLight")
	light.Name = "TrackFireLight"
	light.Color = C_ORANGE
	light.Brightness = 4
	light.Range = 14
	light.Shadows = false
	light.Parent = att
end

-- Procedural VFX for the trackfire explosion. Returns the list of particle emitters
-- with their target one-shot emit counts so the caller can fire them in a single burst.
local function decorateTrackFireExplosion(host: BasePart): { [ParticleEmitter]: number }
	local att = host:FindFirstChild("Attachment") :: Attachment?
	if not att then
		att = Instance.new("Attachment")
		att.Name = "Attachment"
		att.Parent = host
	end

	local emitMap: { [ParticleEmitter]: number } = {}

	-- Main fire burst (largest, brightest, one-shot)
	local fireBurst = Instance.new("ParticleEmitter")
	fireBurst.Name = "ExplosionFireBurst"
	fireBurst.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, C_WHITE),
		ColorSequenceKeypoint.new(0.15, C_YELLOW),
		ColorSequenceKeypoint.new(0.4, C_ORANGE),
		ColorSequenceKeypoint.new(0.7, C_RED),
		ColorSequenceKeypoint.new(1, C_DARK_RED),
	})
	fireBurst.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 6),
		NumberSequenceKeypoint.new(0.2, 14),
		NumberSequenceKeypoint.new(0.5, 18),
		NumberSequenceKeypoint.new(0.85, 8),
		NumberSequenceKeypoint.new(1, 0),
	})
	fireBurst.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	fireBurst.Lifetime = NumberRange.new(0.4, 1.0)
	fireBurst.Rate = 0
	fireBurst.Speed = NumberRange.new(20, 55)
	fireBurst.SpreadAngle = Vector2.new(140, 140)
	fireBurst.Acceleration = Vector3.new(0, 1, 0)
	fireBurst.RotSpeed = NumberRange.new(-180, 180)
	fireBurst.LightEmission = 1
	fireBurst.LightInfluence = 0
	fireBurst.Brightness = 8
	fireBurst.Texture = FIRE_TEXTURE
	fireBurst.Parent = att
	emitMap[fireBurst] = 150

	-- Secondary flame wave (low spread, one-shot)
	local flameWave = Instance.new("ParticleEmitter")
	flameWave.Name = "ExplosionFlameWave"
	flameWave.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, C_WHITE),
		ColorSequenceKeypoint.new(0.3, C_YELLOW),
		ColorSequenceKeypoint.new(0.7, C_ORANGE),
		ColorSequenceKeypoint.new(1, C_RED),
	})
	flameWave.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 3),
		NumberSequenceKeypoint.new(0.4, 10),
		NumberSequenceKeypoint.new(0.8, 5),
		NumberSequenceKeypoint.new(1, 0),
	})
	flameWave.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	flameWave.Lifetime = NumberRange.new(0.5, 1.2)
	flameWave.Rate = 0
	flameWave.Speed = NumberRange.new(15, 40)
	flameWave.SpreadAngle = Vector2.new(30, 30)
	flameWave.Acceleration = Vector3.new(0, 2, 0)
	flameWave.RotSpeed = NumberRange.new(-180, 180)
	flameWave.LightEmission = 1
	flameWave.LightInfluence = 0
	flameWave.Brightness = 7
	flameWave.Texture = FIRE_TEXTURE
	flameWave.Parent = att
	emitMap[flameWave] = 120

	-- Ember shower (one-shot)
	local emberShower = Instance.new("ParticleEmitter")
	emberShower.Name = "ExplosionEmbers"
	emberShower.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 220, 80)),
		ColorSequenceKeypoint.new(0.4, C_ORANGE),
		ColorSequenceKeypoint.new(1, C_RED),
	})
	emberShower.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(0.3, 1.4),
		NumberSequenceKeypoint.new(1, 0),
	})
	emberShower.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	emberShower.Lifetime = NumberRange.new(0.7, 1.5)
	emberShower.Rate = 0
	emberShower.Speed = NumberRange.new(15, 45)
	emberShower.SpreadAngle = Vector2.new(160, 160)
	emberShower.Acceleration = Vector3.new(0, -8, 0)
	emberShower.RotSpeed = NumberRange.new(-360, 360)
	emberShower.LightEmission = 1
	emberShower.LightInfluence = 0
	emberShower.Brightness = 6
	emberShower.Texture = FIRE_TEXTURE
	emberShower.Parent = att
	emitMap[emberShower] = 100

	-- Dark smoke column (one-shot)
	local smokeCol = Instance.new("ParticleEmitter")
	smokeCol.Name = "ExplosionSmoke"
	smokeCol.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(60, 30, 15)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(30, 15, 8)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 5, 2)),
	})
	smokeCol.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 4),
		NumberSequenceKeypoint.new(0.4, 10),
		NumberSequenceKeypoint.new(0.7, 14),
		NumberSequenceKeypoint.new(1, 0),
	})
	smokeCol.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(0.6, 0.7),
		NumberSequenceKeypoint.new(1, 1),
	})
	smokeCol.Lifetime = NumberRange.new(1.0, 2.2)
	smokeCol.Rate = 0
	smokeCol.Speed = NumberRange.new(3, 10)
	smokeCol.SpreadAngle = Vector2.new(80, 80)
	smokeCol.Acceleration = Vector3.new(0, 4, 0)
	smokeCol.RotSpeed = NumberRange.new(-20, 20)
	smokeCol.LightEmission = 0.15
	smokeCol.LightInfluence = 0
	smokeCol.Brightness = 0.8
	smokeCol.Texture = FIRE_TEXTURE
	smokeCol.Parent = att
	emitMap[smokeCol] = 60

	return emitMap
end

-- Larger variant of vfxFlameShotCrater: 20 blocks (vs 16), 4.5 stud radius (vs 3.5),
-- and ~50-60% larger per-block dimensions for a stronger impact read.
local function vfxFlameTrackerCrater(position: Vector3, surfaceMat: Enum.Material?)
	local baseColor = MATERIAL_COLORS[surfaceMat] or Color3.fromRGB(60, 60, 60)
	local scorchColor = Color3.new(
		baseColor.R * 0.35,
		baseColor.G * 0.35,
		baseColor.B * 0.35
	)

	local blockCount = 20
	local craterRadius = 4.5

	for i = 1, blockCount do
		local angle = (i / blockCount) * math.pi * 2 + (math.random() - 0.5) * 0.15
		local dist = craterRadius + (math.random() - 0.5) * 0.6
		local bx = position.X + math.cos(angle) * dist
		local bz = position.Z + math.sin(angle) * dist
		local by = position.Y + 0.05

		-- Slightly larger than the standard crater blocks
		local sizeX = 1.6 + math.random() * 1.0
		local sizeY = 0.4 + math.random() * 0.3
		local sizeZ = 1.1 + math.random() * 0.9

		local block = Instance.new("Part")
		block.Name = "FlameTrackerCraterBlock"
		block.Size = Vector3.new(sizeX, sizeY, sizeZ)
		block.CFrame = CFrame.new(bx, by, bz) * CFrame.Angles(0, math.rad(math.random(0, 360)), 0)
		block.Anchored = true
		block.CanCollide = false
		block.Material = surfaceMat or Enum.Material.CorrodedMetal
		block.Color = scorchColor
		block.Parent = Workspace

		Debris:AddItem(block, 8.0 + math.random() * 4.0)
	end
end

-- ===== FLAME TRACKER EXPLOSION POOL =====
-- Pre-warm a pool of explosion clones so the Flipbook texture atlas is
-- loaded BEFORE the explosion fires. Cloning at the moment of impact
-- leaves the texture uninitialized and the Grid4x4 flipbook silently
-- stops animating. Pre-warming (parent to Workspace, wait a frame) lets
-- the engine load the atlas, so the flipbook plays correctly when the
-- clone is finally moved into position and Emit() is called.
local EXPLOSION_POOL_SIZE = 8
local explosionPool: { Part } = {}

local function warmExplosionClone(clone: Part)
	clone.Name = "FlameTrackerExplosion"
	clone.Anchored = true
	clone.CanCollide = false
	clone.CanQuery = false
	clone.CanTouch = false
	clone.CastShadow = false
	clone.Transparency = 1
	-- Park far below the map so it's never visible while idle
	clone.CFrame = CFrame.new(0, -1000, 0)
	clone.Parent = Workspace
	-- Force the engine to load the Flipbook atlas by emitting a single
	-- particle and immediately clearing it.
	for _, desc in clone:GetDescendants() do
		if desc:IsA("ParticleEmitter") then
			desc:Emit(1)
		end
	end
	task.defer(function()
		if not clone or not clone.Parent then return end
		for _, desc in clone:GetDescendants() do
			if desc:IsA("ParticleEmitter") then
				desc:Clear()
			end
		end
	end)
end

local function initExplosionPool()
	if not TrackFireExplosionTemplate then return end
	for _ = 1, EXPLOSION_POOL_SIZE do
		local clone = TrackFireExplosionTemplate:Clone() :: Part
		warmExplosionClone(clone)
		table.insert(explosionPool, clone)
	end
end

local function vfxFlameTrackerExplode(position: Vector3, surfaceMat: Enum.Material?)
	playSoundAt(position, SFX.FlameTrackerHit, 0.7)
	-- Spawn smaller impact blocks (we have up to 5 of these at once, so keep them light)
	vfxFlameTrackerCrater(position, surfaceMat)
	-- Take a pre-warmed clone from the pool. Each clone is a real copy
	-- of the user's trackfireexplotion template, with the Flipbook atlas
	-- already loaded. Multiple simultaneous explosions are supported.
	local explosion = table.remove(explosionPool, 1)
	if not explosion then return end
	-- Lie flat on the ground (template is 4x1x2, thin in Y, so rotate 90° around Z)
	explosion.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	-- Emit every particle emitter on the clone once
	for _, desc in explosion:GetDescendants() do
		if desc:IsA("ParticleEmitter") then
			desc:Emit(desc:GetAttribute("EmitCount") or 25)
		end
	end
	-- Snappy shockwave ring + screen flash
	spawnShockwaveRing(position, C_ORANGE, 12, 0.3)
	screenFlash(C_ORANGE, 0.05, 0.1)

	-- ===== MESH VFX: IMPACT CORE SPHERE + GROUND RING =====
	local impactFX = Instance.new("Folder")
	impactFX.Name = "FlameTrackerImpactFX"
	impactFX.Parent = Workspace
	-- White-hot core sphere
	local coreSphere = Instance.new("Part")
	coreSphere.Name = "TrackerCore"
	coreSphere.Shape = Enum.PartType.Ball
	coreSphere.Color = C_WHITE
	coreSphere.Material = Enum.Material.Neon
	coreSphere.Anchored = true
	coreSphere.CanCollide = false
	coreSphere.CanQuery = false
	coreSphere.CanTouch = false
	coreSphere.CastShadow = false
	coreSphere.Transparency = 0.1
	coreSphere.Size = Vector3.new(1, 1, 1)
	coreSphere.CFrame = CFrame.new(position)
	coreSphere.Parent = impactFX
	task.spawn(function()
		local startTick = tick()
		while coreSphere and coreSphere.Parent do
			local t = tick() - startTick
			if t > 0.45 then break end
			local growT = math.min(1, t / 0.12)
			local size = 10 * growT
			coreSphere.Size = Vector3.new(size, size, size)
			coreSphere.Transparency = 0.1 + t * 1.6
			coreSphere.CFrame = CFrame.new(position)
			task.wait(0.03)
		end
		if coreSphere and coreSphere.Parent then coreSphere:Destroy() end
	end)
	-- Mid orange expanding sphere (delayed)
	task.delay(0.06, function()
		local midSphere = Instance.new("Part")
		midSphere.Name = "TrackerMid"
		midSphere.Shape = Enum.PartType.Ball
		midSphere.Color = C_ORANGE
		midSphere.Material = Enum.Material.Neon
		midSphere.Anchored = true
		midSphere.CanCollide = false
		midSphere.CanQuery = false
		midSphere.CanTouch = false
		midSphere.CastShadow = false
		midSphere.Transparency = 0.3
		midSphere.Size = Vector3.new(2, 2, 2)
		midSphere.CFrame = CFrame.new(position)
		midSphere.Parent = impactFX
		local startTick = tick()
		while midSphere and midSphere.Parent do
			local t = tick() - startTick
			if t > 0.6 then break end
			local size = 2 + t * 24
			midSphere.Size = Vector3.new(size, size, size)
			midSphere.Transparency = 0.3 + t * 1.0
			midSphere.CFrame = CFrame.new(position)
			task.wait(0.03)
		end
		if midSphere and midSphere.Parent then midSphere:Destroy() end
	end)
	-- Horizontal ground ring (flat disc that expands)
	task.delay(0.04, function()
		local groundRing = Instance.new("Part")
		groundRing.Name = "TrackerGroundRing"
		groundRing.Shape = Enum.PartType.Cylinder
		groundRing.Color = C_YELLOW
		groundRing.Material = Enum.Material.Neon
		groundRing.Anchored = true
		groundRing.CanCollide = false
		groundRing.CanQuery = false
		groundRing.CanTouch = false
		groundRing.CastShadow = false
		groundRing.Transparency = 0.3
		groundRing.Size = Vector3.new(0.5, 2, 2)
		groundRing.CFrame = CFrame.new(position + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90))
		groundRing.Parent = impactFX
		local startTick = tick()
		while groundRing and groundRing.Parent do
			local t = tick() - startTick
			if t > 0.5 then break end
			local size = 2 + t * 26
			groundRing.Size = Vector3.new(0.5 + t * 0.6, size, size)
			groundRing.Transparency = 0.3 + t * 1.3
			groundRing.CFrame = CFrame.new(position + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90))
			task.wait(0.03)
		end
		if groundRing and groundRing.Parent then groundRing:Destroy() end
	end)
	-- Vertical ember pillar that rises briefly
	task.spawn(function()
		local emberCol = Instance.new("Part")
		emberCol.Name = "TrackerEmberPillar"
		emberCol.Shape = Enum.PartType.Cylinder
		emberCol.Color = Color3.fromRGB(80, 35, 12)
		emberCol.Material = Enum.Material.SmoothPlastic
		emberCol.Anchored = true
		emberCol.CanCollide = false
		emberCol.CanQuery = false
		emberCol.CanTouch = false
		emberCol.CastShadow = false
		emberCol.Transparency = 0.5
		emberCol.Size = Vector3.new(4, 3, 3)
		emberCol.CFrame = CFrame.new(position + Vector3.new(0, 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
		emberCol.Parent = impactFX
		local startTick = tick()
		while emberCol and emberCol.Parent do
			local t = tick() - startTick
			if t > 1.4 then break end
			local rise = t * 4
			local width = 3 + t * 4
			emberCol.Size = Vector3.new(width, 3 + t * 10, 3 + t * 10)
			emberCol.CFrame = CFrame.new(position + Vector3.new(0, 2 + rise, 0)) * CFrame.Angles(0, 0, math.rad(90))
			emberCol.Transparency = 0.5 + t * 0.4
			task.wait(0.03)
		end
		if emberCol and emberCol.Parent then emberCol:Destroy() end
	end)

	-- ===== MESH VFX: FIRE TORNADO =====
	-- A bright orange cylinder that rises from the impact, stretching
	-- taller and wider as it climbs while rotating around its vertical
	-- axis, then fades. Adds a dramatic vertical flourish to the blast.
	task.spawn(function()
		local tornado = Instance.new("Part")
		tornado.Name = "TrackerTornado"
		tornado.Shape = Enum.PartType.Cylinder
		tornado.Color = Color3.fromRGB(255, 100, 20)
		tornado.Material = Enum.Material.Neon
		tornado.Anchored = true
		tornado.CanCollide = false
		tornado.CanQuery = false
		tornado.CanTouch = false
		tornado.CastShadow = false
		tornado.Transparency = 0.3
		tornado.Size = Vector3.new(2, 4, 4)
		tornado.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
		tornado.Parent = impactFX
		local startTick = tick()
		while tornado and tornado.Parent do
			local t = tick() - startTick
			if t > 1.2 then break end
			local height = 4 + t * 12
			local width = 4 + t * 2
			tornado.Size = Vector3.new(math.max(0.5, 2 - t * 0.8), height, width)
			tornado.CFrame = CFrame.new(position + Vector3.new(0, height / 2, 0))
				* CFrame.Angles(0, t * math.rad(180), math.rad(90))
			tornado.Transparency = 0.3 + t * 0.6
			task.wait(0.03)
		end
		if tornado and tornado.Parent then tornado:Destroy() end
	end)

	-- ===== MESH VFX: SECONDARY FIRE RING =====
	-- A delayed inner fire ring that snaps outward from the impact,
	-- complementing the first ground ring for a layered shockwave feel.
	task.delay(0.06, function()
		local ring2 = Instance.new("Part")
		ring2.Name = "TrackerGroundRing2"
		ring2.Shape = Enum.PartType.Cylinder
		ring2.Color = Color3.fromRGB(255, 140, 40)
		ring2.Material = Enum.Material.Neon
		ring2.Anchored = true
		ring2.CanCollide = false
		ring2.CanQuery = false
		ring2.CanTouch = false
		ring2.CastShadow = false
		ring2.Transparency = 0.3
		ring2.Size = Vector3.new(0.5, 3, 3)
		ring2.CFrame = CFrame.new(position + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
		ring2.Parent = impactFX
		local startTick = tick()
		while ring2 and ring2.Parent do
			local t = tick() - startTick
			if t > 0.5 then break end
			local size = 3 + t * 28
			ring2.Size = Vector3.new(0.5 + t * 0.7, size, size)
			ring2.Transparency = 0.3 + t * 1.4
			task.wait(0.03)
		end
		if ring2 and ring2.Parent then ring2:Destroy() end
	end)

	Debris:AddItem(impactFX, 2.0)

	-- ===== EXTRA MESH VFX: DARK EMBER COLUMN + SCORCH DISK + RED SPHERE =====
	meshVerticalPillar(position, Color3.fromRGB(80, 35, 12), 6, 5, 1.2)
	meshScorchDisk(position, 14, 0.8)
	meshExpandingSphere(position, C_RED, 16, 0.8, 0.4)

	-- Cleanup: clear in-flight particles, return the clone to the pool,
	-- and re-warm it so the next explosion is ready immediately.
	task.delay(1, function()
		if not explosion or not explosion.Parent then return end
		for _, desc in explosion:GetDescendants() do
			if desc:IsA("ParticleEmitter") then
				desc:Clear()
			elseif desc:IsA("PointLight") then
				desc.Enabled = false
			end
		end
		-- Park the clone back in the hidden spot and re-warm it
		explosion.CFrame = CFrame.new(0, -1000, 0)
		warmExplosionClone(explosion)
		table.insert(explosionPool, explosion)
	end)
end

initExplosionPool()

local function vfxFlameTrackerCast(origin: Vector3, initialDir: Vector3)
	-- Back position: 2.5 studs behind the player, 1.5 studs above the root
	local backPos = origin - initialDir * 2.5 + Vector3.new(0, 1.5, 0)
	playSoundAt(origin, SFX.FlameTrackerCast, 1.0)
	-- Hand gathering effect: a brief bright flash at the back position
	local gatherAnchor = Instance.new("Part")
	gatherAnchor.Name = "FlameTrackerGather"
	gatherAnchor.Size = Vector3.new(0.5, 0.5, 0.5)
	gatherAnchor.Position = backPos
	gatherAnchor.Anchored = true
	gatherAnchor.CanCollide = false
	gatherAnchor.Transparency = 1
	gatherAnchor.Parent = Workspace
	local gatherAtt = gatherAnchor:FindFirstChildOfClass("Attachment")
	if not gatherAtt then
		gatherAtt = Instance.new("Attachment")
		gatherAtt.Parent = gatherAnchor
	end
	local gatherPE = Instance.new("ParticleEmitter")
	gatherPE.Name = "GatherEmber"
	gatherPE.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, C_YELLOW),
		ColorSequenceKeypoint.new(0.5, C_ORANGE),
		ColorSequenceKeypoint.new(1, C_RED),
	})
	gatherPE.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(0.5, 0.9),
		NumberSequenceKeypoint.new(1, 0),
	})
	gatherPE.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.5, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	gatherPE.Lifetime = NumberRange.new(0.3, 0.6)
	gatherPE.Rate = 60
	gatherPE.Speed = NumberRange.new(1, 3)
	gatherPE.SpreadAngle = Vector2.new(180, 180)
	gatherPE.LightEmission = 1
	gatherPE.LightInfluence = 0
	gatherPE.Brightness = 3
	gatherPE.Texture = FIRE_TEXTURE
	gatherPE.Parent = gatherAtt
	local gatherLight = Instance.new("PointLight")
	gatherLight.Color = C_ORANGE
	gatherLight.Brightness = 2
	gatherLight.Range = 8
	gatherLight.Shadows = false
	gatherLight.Parent = gatherAnchor
	task.delay(0.4, function() if gatherAnchor and gatherAnchor.Parent then gatherAnchor:Destroy() end end)

	-- ===== EXTRA MESH VFX: GATHER RING + ORANGE SPHERE + EMBER COLUMN =====
	meshExpandingRing(backPos + Vector3.new(0, -1, 0), C_YELLOW, 2, 12, 0.5, 0.5, -1)
	meshExpandingSphere(backPos, C_ORANGE, 8, 0.5, 0.3)
	meshVerticalPillar(backPos, Color3.fromRGB(80, 35, 12), 4, 3, 0.6)

	-- Pre-compute spawn positions for 5 projectiles (random within 0.9 studs of the back)
	local spawnPositions: { Vector3 } = {}
	for _ = 1, 5 do
		local angle = math.random() * math.pi * 2
		local radius = math.random() * 0.9
		local yJitter = (math.random() * 2 - 1) * 0.4
		table.insert(spawnPositions, backPos + Vector3.new(
			math.cos(angle) * radius,
			yJitter,
			math.sin(angle) * radius
		))
	end
	-- Spawn 5 INDEPENDENT fireball projectiles. Each runs its own collision
	-- loop and calls vfxFlameTrackerExplode when it hits — they do not share
	-- state and do not cancel each other.
	local ability = ElementConfig.Fire.abilities[3]
	local speed = ability.projectileSpeed or 130
	local maxRange = ability.range or 200
	local maxDuration = ability.duration or 4.0
	for i, startPos in spawnPositions do
		task.delay((i - 1) * 0.30, function()
			if not humanoidRootPart or not currentCharacter then return end
			-- Re-aim at the moment of THIS launch so the player can move the mouse
			local launchDir = getClickDirection()
			-- Clone the user's trackfire template AS-IS — keep the disc, particles, and PointLight
			local fireball: Part
			if TrackFireTemplate then
				fireball = TrackFireTemplate:Clone() :: Part
			else
				-- Fallback if template is missing
				fireball = Instance.new("Part")
				fireball.Size = Vector3.new(2, 1, 2)
				fireball.Material = Enum.Material.Neon
				fireball.Color = C_ORANGE
				local att = Instance.new("Attachment")
				att.Parent = fireball
			end
			fireball.Name = "FlameTrackerProjectile"
			fireball.Anchored = true
			fireball.CanCollide = false
			fireball.CanQuery = false
			fireball.CanTouch = false
			fireball.CastShadow = false
			-- Orient disc so its flat face points along travel direction
			fireball.CFrame = CFrame.lookAt(startPos, startPos + launchDir)
			fireball.Parent = Workspace
			-- Collision params: ignore self + character
			local rayParams = RaycastParams.new()
			rayParams.FilterType = Enum.RaycastFilterType.Exclude
			if currentCharacter then
				rayParams.FilterDescendantsInstances = { currentCharacter, fireball }
			else
				rayParams.FilterDescendantsInstances = { fireball }
			end
			local traveled = 0
			local startTime = tick()
			-- INDEPENDENT collision loop — no shared hasExploded
			task.spawn(function()
				while fireball and fireball.Parent do
					if tick() - startTime > maxDuration then break end
					local dt = task.wait(0.03)
					local moveStep = speed * dt
					traveled += moveStep
					if traveled > maxRange then break end
					local newPos = fireball.Position + launchDir * moveStep
					fireball.CFrame = CFrame.new(newPos)
					-- Environment collision: skip first 3 studs to avoid self-hit
					if traveled > 3 then
						local rayRes = Workspace:Raycast(fireball.Position - launchDir * 1.5, launchDir * 5, rayParams)
						if rayRes then
							vfxFlameTrackerExplode(rayRes.Position, rayRes.Material)
							if fireball and fireball.Parent then fireball:Destroy() end
							return
						end
					end
					-- Player-on-player collision check
					for _, other in Players:GetPlayers() do
						if other == player then continue end
						local oChar = other.Character
						if not oChar then continue end
						local oHrp = oChar:FindFirstChild("HumanoidRootPart") :: BasePart?
						if not oHrp then continue end
						if (oHrp.Position - fireball.Position).Magnitude <= 4 then
							vfxFlameTrackerExplode(fireball.Position, nil)
							if fireball and fireball.Parent then fireball:Destroy() end
							return
						end
					end
				end
				-- Max range or timeout: just destroy (no explosion)
				if fireball and fireball.Parent then fireball:Destroy() end
			end)
		end)
	end
end

-- ===== VFX: PHOENIX BURST =====
local function vfxPhoenixBurstCharge(origin: Vector3, direction: Vector3)
	local anchor = Instance.new("Part")
	anchor.Name = "PhoenixBurstVFX"
	anchor.Size = Vector3.new(0.5, 0.5, 0.5)
	anchor.Position = origin
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.Transparency = 1
	anchor.Parent = Workspace

	-- Ground glow that intensifies
	local groundGlow = Instance.new("Part")
	groundGlow.Name = "PhoenixGroundGlow"
	groundGlow.Shape = Enum.PartType.Cylinder
	groundGlow.Size = Vector3.new(0.5, 8, 8)
	groundGlow.Anchored = true
	groundGlow.CanCollide = false
	groundGlow.CastShadow = false
	groundGlow.Color = C_YELLOW
	groundGlow.Material = Enum.Material.Neon
	groundGlow.Transparency = 0.5
	groundGlow.Position = origin + Vector3.new(0, -1.5, 0)
	groundGlow.CFrame = CFrame.new(origin + Vector3.new(0, -1.5, 0)) * CFrame.Angles(math.rad(90), 0, 0)
	groundGlow.Parent = Workspace

	-- Fire swirl around player (fire vortex)
	local vortexAtt = Instance.new("Attachment")
	vortexAtt.Position = Vector3.new()
	vortexAtt.Parent = anchor

	local vortexEmitter = Instance.new("ParticleEmitter")
	vortexEmitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, C_WHITE),
		ColorSequenceKeypoint.new(0.2, C_YELLOW),
		ColorSequenceKeypoint.new(0.5, C_ORANGE),
		ColorSequenceKeypoint.new(0.8, C_RED),
		ColorSequenceKeypoint.new(1, C_DARK_RED),
	})
	vortexEmitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(0.4, 10), NumberSequenceKeypoint.new(1, 0) })
	vortexEmitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.5, 0.3), NumberSequenceKeypoint.new(1, 1) })
	vortexEmitter.Lifetime = NumberRange.new(0.4, 1.0)
	vortexEmitter.Rate = 150
	vortexEmitter.Speed = NumberRange.new(8, 30)
	vortexEmitter.SpreadAngle = Vector2.new(180, 180)
	vortexEmitter.Acceleration = Vector3.new(0, 0, 0)
	vortexEmitter.RotSpeed = NumberRange.new(-360, 360)
	vortexEmitter.LightEmission = 1
	vortexEmitter.LightInfluence = 0
	vortexEmitter.Brightness = 12
	vortexEmitter.Texture = FIRE_TEXTURE
	vortexEmitter.Parent = vortexAtt

	-- Orbiting embers (outer ring)
	local orbitAtt = Instance.new("Attachment")
	orbitAtt.Position = Vector3.new()
	orbitAtt.Parent = anchor
	local orbitEmitter = Instance.new("ParticleEmitter")
	orbitEmitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, C_GOLD),
		ColorSequenceKeypoint.new(0.5, C_ORANGE),
		ColorSequenceKeypoint.new(1, C_RED),
	})
	orbitEmitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(0.5, 6), NumberSequenceKeypoint.new(1, 0) })
	orbitEmitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.3), NumberSequenceKeypoint.new(1, 1) })
	orbitEmitter.Lifetime = NumberRange.new(0.6, 1.5)
	orbitEmitter.Rate = 100
	orbitEmitter.Speed = NumberRange.new(4, 18)
	orbitEmitter.SpreadAngle = Vector2.new(180, 180)
	orbitEmitter.Acceleration = Vector3.new(0, 3, 0)
	orbitEmitter.RotSpeed = NumberRange.new(-360, 360)
	orbitEmitter.LightEmission = 0.8
	orbitEmitter.LightInfluence = 0
	orbitEmitter.Brightness = 6
	orbitEmitter.Texture = FIRE_TEXTURE
	orbitEmitter.Parent = orbitAtt

	-- Shockwave ring pulses
	local shockAtt = Instance.new("Attachment")
	shockAtt.Position = Vector3.new()
	shockAtt.Parent = anchor
	local shockEmitter = Instance.new("ParticleEmitter")
	shockEmitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, C_WHITE),
		ColorSequenceKeypoint.new(0.5, C_YELLOW),
		ColorSequenceKeypoint.new(1, C_GOLD),
	})
	shockEmitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 12), NumberSequenceKeypoint.new(0.3, 30), NumberSequenceKeypoint.new(1, 0) })
	shockEmitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(0.3, 0.4), NumberSequenceKeypoint.new(1, 1) })
	shockEmitter.Lifetime = NumberRange.new(0.2, 0.5)
	shockEmitter.Rate = 40
	shockEmitter.Speed = NumberRange.new(3, 10)
	shockEmitter.SpreadAngle = Vector2.new(180, 180)
	shockEmitter.LightEmission = 1
	shockEmitter.LightInfluence = 0
	shockEmitter.Brightness = 10
	shockEmitter.Texture = FIRE_TEXTURE
	shockEmitter.Parent = shockAtt

	local light1 = addLight(anchor, C_YELLOW, 15, 30)
	local light2 = addLight(anchor, C_ORANGE, 10, 55)
	cameraShake(0.8, 1.5)
	playSoundAt(origin, SFX.PhoenixBurstCharge, 1.2)
	screenFlash(C_WHITE, 0.25, 0.15)

	-- Intensify over time
	task.spawn(function()
		local start = tick()
		while anchor and anchor.Parent and tick() - start < 1.5 do
			local elapsed = tick() - start
			local intensity = 1 + elapsed * 0.5
			local pulse = 1 + math.sin(elapsed * 8) * 0.5
			if light1 and light1.Parent then light1.Brightness = 15 * intensity * pulse end
			if light2 and light2.Parent then light2.Brightness = 10 * intensity * pulse end
			vortexEmitter.Rate = math.floor(150 * intensity)
			orbitEmitter.Rate = math.floor(100 * intensity)
			if groundGlow and groundGlow.Parent then
				groundGlow.Size = Vector3.new(0.5, 8 + elapsed * 4, 8 + elapsed * 4)
				groundGlow.Transparency = 0.5 - elapsed * 0.2
			end
			task.wait(0.05)
		end
	end)

	task.delay(1.5, function()
		vortexEmitter.Rate = 0
		orbitEmitter.Rate = 0
		shockEmitter.Rate = 0
		if groundGlow and groundGlow.Parent then
			local fade = TweenService:Create(groundGlow, TweenInfo.new(0.3), { Transparency = 1 })
			fade:Play()
			task.delay(0.3, function()
				if groundGlow and groundGlow.Parent then groundGlow:Destroy() end
			end)
		end
		anchor:Destroy()
	end)
end

local function vfxPhoenixBurstExplode(position: Vector3, direction: Vector3)
	playSoundAt(position, SFX.PhoenixBurstExplode, 2.0)

	local anchor = Instance.new("Part")
	anchor.Name = "PhoenixBurstExplodeVFX"
	anchor.Size = Vector3.new(0.5, 0.5, 0.5)
	anchor.Position = position
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.Transparency = 1
	anchor.Parent = Workspace

	-- Dynamic flash light
	local flashLight = Instance.new("PointLight")
	flashLight.Color = C_WHITE
	flashLight.Brightness = 30
	flashLight.Range = 60
	flashLight.Shadows = false
	flashLight.Parent = anchor
	task.spawn(function()
		local start = tick()
		while flashLight and flashLight.Parent and tick() - start < 1.0 do
			local t = (tick() - start) / 1.0
			flashLight.Brightness = 30 * (1 - t)
			task.wait()
		end
		if flashLight then flashLight:Destroy() end
	end)

	-- Nuclear core explosion
	oneShotEmitter(anchor, Vector3.new(), ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.1, Color3.fromRGB(255, 255, 200)),
		ColorSequenceKeypoint.new(0.3, Color3.fromRGB(255, 200, 50)),
		ColorSequenceKeypoint.new(0.6, Color3.fromRGB(255, 100, 20)),
		ColorSequenceKeypoint.new(0.8, Color3.fromRGB(200, 50, 5)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(50, 10, 0)),
	}), NumberSequence.new({
		NumberSequenceKeypoint.new(0, 18),
		NumberSequenceKeypoint.new(0.15, 40),
		NumberSequenceKeypoint.new(0.35, 55),
		NumberSequenceKeypoint.new(0.6, 30),
		NumberSequenceKeypoint.new(0.85, 12),
		NumberSequenceKeypoint.new(1, 0),
	}), NumberRange.new(0.3, 1.2), 150, NumberRange.new(25, 75), Vector2.new(180, 180), 1, 18)

	-- Fire tornado fragments (vertical pillars)
	oneShotEmitter(anchor, Vector3.new(), ColorSequence.new({
		ColorSequenceKeypoint.new(0, C_WHITE),
		ColorSequenceKeypoint.new(0.3, C_YELLOW),
		ColorSequenceKeypoint.new(1, C_RED),
	}), NumberSequence.new({
		NumberSequenceKeypoint.new(0, 6),
		NumberSequenceKeypoint.new(0.5, 20),
		NumberSequenceKeypoint.new(1, 0),
	}), NumberRange.new(0.2, 0.6), 120, NumberRange.new(35, 100), Vector2.new(10, 10), 1, 14)

	-- Ring waves (multiple expanding rings)
	oneShotEmitter(anchor, Vector3.new(), ColorSequence.new({
		ColorSequenceKeypoint.new(0, C_GOLD),
		ColorSequenceKeypoint.new(0.3, C_ORANGE),
		ColorSequenceKeypoint.new(0.7, C_YELLOW),
		ColorSequenceKeypoint.new(1, C_DARK_RED),
	}), NumberSequence.new({
		NumberSequenceKeypoint.new(0, 5),
		NumberSequenceKeypoint.new(0.4, 16),
		NumberSequenceKeypoint.new(0.7, 8),
		NumberSequenceKeypoint.new(1, 0),
	}), NumberRange.new(0.5, 1.8), 120, NumberRange.new(25, 65), Vector2.new(10, 10), 1, 12)

	-- Ember storm (huge spread)
	oneShotEmitter(anchor, Vector3.new(), ColorSequence.new({
		ColorSequenceKeypoint.new(0, C_YELLOW),
		ColorSequenceKeypoint.new(0.4, C_ORANGE),
		ColorSequenceKeypoint.new(0.7, C_RED),
		ColorSequenceKeypoint.new(1, C_DARK_RED),
	}), NumberSequence.new({
		NumberSequenceKeypoint.new(0, 3),
		NumberSequenceKeypoint.new(0.4, 10),
		NumberSequenceKeypoint.new(0.7, 5),
		NumberSequenceKeypoint.new(1, 0),
	}), NumberRange.new(1.0, 2.5), 100, NumberRange.new(6, 25), Vector2.new(180, 180), 1, 9)

	-- Smoke dome (big)
	oneShotEmitter(anchor, Vector3.new(0, 2, 0), ColorSequence.new({
		ColorSequenceKeypoint.new(0, C_BLACK_SMOKE),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(40, 20, 10)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 5, 2)),
	}), NumberSequence.new({
		NumberSequenceKeypoint.new(0, 15),
		NumberSequenceKeypoint.new(0.3, 35),
		NumberSequenceKeypoint.new(0.7, 40),
		NumberSequenceKeypoint.new(1, 0),
	}), NumberRange.new(1.5, 3.5), 60, NumberRange.new(4, 14), Vector2.new(180, 180), 0.15, 1)

	-- Multiple shockwave rings
	spawnShockwaveRing(position, C_WHITE, 40, 0.9)
	task.delay(0.15, function()
		spawnShockwaveRing(position, C_YELLOW, 50, 0.8)
	end)
	task.delay(0.3, function()
		spawnShockwaveRing(position, C_ORANGE, 55, 0.6)
	end)

	-- Heat distortion (large)
	spawnHeatDistortion(position, 30, 2.0)

	-- Sparks flying everywhere
	oneShotEmitter(anchor, Vector3.new(), ColorSequence.new({
		ColorSequenceKeypoint.new(0, C_WHITE),
		ColorSequenceKeypoint.new(0.3, C_GOLD),
		ColorSequenceKeypoint.new(0.7, C_YELLOW),
		ColorSequenceKeypoint.new(1, C_RED),
	}), NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 3),
		NumberSequenceKeypoint.new(1, 0),
	}), NumberRange.new(0.3, 0.8), 80, NumberRange.new(30, 80), Vector2.new(180, 180), 1, 10)

	-- Multiple lights
	addLight(anchor, C_WHITE, 25, 60)
	addLight(anchor, C_YELLOW, 15, 80)
	addLight(anchor, C_ORANGE, 10, 100)
	cameraShake(3.5, 1.2)
	screenFlash(C_WHITE, 0.35, 0.5)

	task.delay(2.5, anchor.Destroy, anchor)
end

-- ===== METEOR SHOWER TEMPLATES =====
-- Templates live in ReplicatedStorage (workspace contents aren't reliably available
-- in all contexts). Look in ReplicatedStorage first, then fall back to workspace,
-- then create simple fallback parts if nothing is found.
local function findTemplate(candidates: { string }, timeout: number): Part?
	local deadline = tick() + timeout
	while tick() < deadline do
		for _, location in ipairs({ ReplicatedStorage, workspace }) do
			for _, name in candidates do
				local t = location:FindFirstChild(name)
				if t and t:IsA("BasePart") then return t end
			end
		end
		task.wait(0.5)
	end
	return nil
end

local function createFallbackPart(name: string, color: Color3, size: Vector3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.Neon
	p.Anchored = true
	p.CanCollide = false
	p.Parent = ReplicatedStorage
	return p
end

-- fireballexplotion = mini-explode, fireball = fireprojectile
local FiresunTemplate = findTemplate({"firesun"}, 3) :: Part?
if not FiresunTemplate then
	FiresunTemplate = createFallbackPart("firesun_fallback", Color3.fromRGB(255, 200, 50), Vector3.new(6, 6, 6))
end
local FireprojectileTemplate = findTemplate({"fireprojectile", "fireball"}, 3) :: Part?
if not FireprojectileTemplate then
	FireprojectileTemplate = createFallbackPart("fireprojectile_fallback", Color3.fromRGB(255, 120, 30), Vector3.new(2, 2, 2))
end
local MiniExplodeTemplate = findTemplate({"miniexplode", "fireballexplotion"}, 3) :: Part?
if not MiniExplodeTemplate then
	MiniExplodeTemplate = createFallbackPart("miniexplode_fallback", Color3.fromRGB(255, 180, 60), Vector3.new(3, 3, 3))
end

-- Register a collision group for Meteor Shower projectiles so they don't collide
-- with each other and self-destruct before reaching the ground. Wrapped in pcall
-- because CollisionGroups may already exist if the script is reloaded.
local METEOR_GROUP = "MeteorProjectile"
do
	local ok = pcall(function()
		PhysicsService:RegisterCollisionGroup(METEOR_GROUP)
	end)
	if ok then
		PhysicsService:CollisionGroupSetCollidable(METEOR_GROUP, METEOR_GROUP, false)
		PhysicsService:CollisionGroupSetCollidable(METEOR_GROUP, "Default", true)
	end
end

-- ===== GENERIC VFX UTILITY: FADE OUT AND REMOVE =====
-- Smoothly tweens the Transparency of every BasePart under the given root
-- (and its descendants) from its current value to 1 over the given
-- duration, then destroys the root. Also disables all ParticleEmitters
-- immediately and tweens their Transparency NumberSequence to all 1s so
-- any particles still in the air become invisible. Used to gracefully
-- clean up VFX instances (firesun, fireprojectile, miniexplode) once
-- their effect has played out.
local function fadeOutAndRemove(root: Instance, duration: number)
	if not root or not root.Parent then return end
	duration = duration or 1

	-- Stop all particle emission so no new particles are emitted
	for _, desc in ipairs(root:GetDescendants()) do
		if desc:IsA("ParticleEmitter") then
			desc.Enabled = false
		end
	end

	-- Tween BasePart.Transparency and ParticleEmitter.Transparency to 1
	-- over the given duration. For ParticleEmitter.Transparency (a
	-- NumberSequence), build a target sequence with the same keypoint
	-- count but all values = 1, so emitted particles become invisible.
	local tweens: { Tween } = {}
	for _, desc in ipairs(root:GetDescendants()) do
		if desc:IsA("BasePart") then
			local ti = TweenInfo.new(duration, Enum.EasingStyle.Linear)
			local t = TweenService:Create(desc, ti, { Transparency = 1 })
			table.insert(tweens, t)
			t:Play()
		elseif desc:IsA("ParticleEmitter") then
			local current = desc.Transparency
			local n = #current.Keypoints
			if n > 0 then
				local keypoints: { NumberSequenceKeypoint } = {}
				for _, kp in ipairs(current.Keypoints) do
					table.insert(keypoints, NumberSequenceKeypoint.new(kp.Time, 1))
				end
				local target = NumberSequence.new(keypoints)
				local ti = TweenInfo.new(duration, Enum.EasingStyle.Linear)
				local t = TweenService:Create(desc, ti, { Transparency = target })
				table.insert(tweens, t)
				t:Play()
			end
		end
	end

	-- Wait for the tweens to complete
	if #tweens > 0 then
		tweens[1].Completed:Wait()
	end

	root:Destroy()
end

-- ===== VFX: METEOR SHOWER =====
-- Uses only the user-provided VFX templates from workspace:
--   * firesun        — cloned, travels in a smooth curved (Bezier) path from the
--                       hand to ~3 studs in front of the player at 70 studs up,
--                       over 1.5s. Then floats in place while meteors fall,
--                       and finally fades out (1s) before being destroyed.
--   * fireprojectile — cloned 70 times from the EXACT CENTER of the firesun,
--                       spawned one by one at random intervals over 10s. Each
--                       gets a random horizontal velocity (full 360°) for a
--                       wide landing spread, with a slight upward Y kick for a
--                       curved fall under gravity. Fade-out (1s) on impact.
--   * miniexplode    — cloned at each impact point, emitters disabled after
--                       a short burst so the effect plays exactly once. Then
--                       fades out (1s) and is destroyed.
local function vfxMeteorShower(caster: Player, origin: Vector3, direction: Vector3)
	if not FiresunTemplate or not FireprojectileTemplate or not MiniExplodeTemplate then return end
	if not direction or direction.Magnitude < 0.1 then direction = Vector3.new(0, 0, -1) end
	direction = direction.Unit

	-- Determine start position (player's right hand); fall back to a point in front
	local character = caster.Character
	local startPos: Vector3
	if character then
		local rightArm = character:FindFirstChild("Right Arm") :: BasePart?
		if rightArm and rightArm:IsA("BasePart") then
			startPos = rightArm.Position
		else
			local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			startPos = (hrp and hrp.Position or origin) + direction * 2 + Vector3.new(0, 1.2, 0)
		end
	else
		startPos = origin + direction * 2 + Vector3.new(0, 1.2, 0)
	end

	-- End position: 70 studs above and 3 studs in front of the player
	local endPos = origin + direction * 3 + Vector3.new(0, 70, 0)

	-- Clone the firesun at the hand
	local sun = FiresunTemplate:Clone()
	sun.Name = "MeteorShowerSun"
	sun.CFrame = CFrame.new(startPos)
	sun.Anchored = true
	sun.CanCollide = false
	sun.CanQuery = false
	sun.CanTouch = false
	sun.Parent = Workspace

	-- Smooth curved ascent (1.5s) using a quadratic Bezier path. The control
	-- point is offset perpendicular to the player's facing direction by 30
	-- studs, so the sun arcs outward smoothly and ends ~3 studs in front of
	-- the player at 70 studs up.
	local ascendDuration = 1.5
	local mid = (startPos + endPos) / 2
	local perp = Vector3.new(-direction.Z, 0, direction.X)
	local control = mid + perp * 30
	local t0 = tick()
	local ascendConn
	ascendConn = RunService.Heartbeat:Connect(function()
		local elapsed = tick() - t0
		local t = math.clamp(elapsed / ascendDuration, 0, 1)
		-- Quadratic Bezier: B(t) = (1-t)² P0 + 2(1-t)t P1 + t² P2
		local u = 1 - t
		local p = u * u * startPos + 2 * u * t * control + t * t * endPos
		sun.CFrame = CFrame.new(p)
		if t >= 1 then ascendConn:Disconnect() end
	end)

	-- Spawn a single meteor from the EXACT CENTER of the firesun. The spread
	-- on landing comes from a random horizontal velocity (full 360°) so the
	-- shower still covers a wide footprint around the player. The meteor
	-- gets a small upward Y kick so the trajectory arcs up briefly before
	-- gravity pulls it down — giving a visible curved fall.
	local function spawnMeteor()
		local meteor = FireprojectileTemplate:Clone()
		meteor.Name = "MeteorShowerProjectile"
		meteor.CFrame = CFrame.new(sun.Position)
		meteor.Anchored = false
		meteor.CanCollide = true
		meteor.CanQuery = false
		meteor.CanTouch = true
		meteor.CollisionGroup = METEOR_GROUP
		meteor.Parent = Workspace

		local angle = math.random() * math.pi * 2
		local horizontalSpeed = math.random(10, 30)
		local yKick = math.random(0, 8)
		meteor.AssemblyLinearVelocity = Vector3.new(
			math.cos(angle) * horizontalSpeed,
			yKick,
			math.sin(angle) * horizontalSpeed
		)

		local fired = false
		local touchConn -- forward declaration so onTouched can disconnect it
		local function onTouched(otherPart: BasePart)
			if fired then return end
			if not otherPart or not otherPart.Parent then return end
			if otherPart:IsDescendantOf(sun) then return end
			if otherPart == meteor then return end
			-- Skip the caster's character so the meteor doesn't blow up on the player
			if caster.Character and otherPart:IsDescendantOf(caster.Character) then return end
			-- Skip other meteors in the same shower (collision group is the primary guard)
			if otherPart.CollisionGroup == METEOR_GROUP then return end

			fired = true
			-- Stop the meteor in place at the impact point
			meteor.Anchored = true
			meteor.AssemblyLinearVelocity = Vector3.zero
			-- Disconnect the Touched event so it can never fire again on this meteor
			if touchConn then touchConn:Disconnect() end

			local impactPos = meteor.Position + Vector3.new(0, 1, 0)

			-- ===== MESH VFX: IMPACT CORE SPHERE =====
			-- White-hot core sphere that expands and fades quickly. Lightweight
			-- enough to run for all 70 meteors without performance issues.
			local coreSphere = Instance.new("Part")
			coreSphere.Name = "MeteorCore"
			coreSphere.Shape = Enum.PartType.Ball
			coreSphere.Color = Color3.new(1, 1, 1)
			coreSphere.Material = Enum.Material.Neon
			coreSphere.Anchored = true
			coreSphere.CanCollide = false
			coreSphere.CanQuery = false
			coreSphere.CanTouch = false
			coreSphere.CastShadow = false
			coreSphere.Transparency = 0.1
			coreSphere.Size = Vector3.new(1, 1, 1)
			coreSphere.CFrame = CFrame.new(impactPos)
			coreSphere.Parent = Workspace
			task.spawn(function()
				local startTick = tick()
				while coreSphere and coreSphere.Parent do
					local t = tick() - startTick
					if t > 0.4 then break end
					local size = 1 + t * 22
					coreSphere.Size = Vector3.new(size, size, size)
					coreSphere.Transparency = 0.1 + t * 2.0
					task.wait(0.03)
				end
				if coreSphere and coreSphere.Parent then coreSphere:Destroy() end
			end)

			-- ===== MESH VFX: GROUND RING =====
			-- Flat yellow-orange disc that expands outward on the ground.
			local groundRing = Instance.new("Part")
			groundRing.Name = "MeteorGroundRing"
			groundRing.Shape = Enum.PartType.Cylinder
			groundRing.Color = Color3.fromRGB(255, 200, 50)
			groundRing.Material = Enum.Material.Neon
			groundRing.Anchored = true
			groundRing.CanCollide = false
			groundRing.CanQuery = false
			groundRing.CanTouch = false
			groundRing.CastShadow = false
			groundRing.Transparency = 0.3
			groundRing.Size = Vector3.new(0.5, 2, 2)
			groundRing.CFrame = CFrame.new(impactPos + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90))
			groundRing.Parent = Workspace
			task.spawn(function()
				local startTick = tick()
				while groundRing and groundRing.Parent do
					local t = tick() - startTick
					if t > 0.5 then break end
					local size = 2 + t * 30
					groundRing.Size = Vector3.new(0.5 + t * 0.8, size, size)
					groundRing.Transparency = 0.3 + t * 1.4
					task.wait(0.03)
				end
				if groundRing and groundRing.Parent then groundRing:Destroy() end
			end)

			-- ===== MESH VFX: VERTICAL EMBER PILLAR =====
			-- A dark-red column of embers that rises from the impact and
			-- expands as it climbs, then fades. Mirrors the 3rd tool's
			-- TrackerEmberPillar but tuned for the per-meteor impact scale.
			task.spawn(function()
				local emberCol = Instance.new("Part")
				emberCol.Name = "MeteorEmberPillar"
				emberCol.Shape = Enum.PartType.Cylinder
				emberCol.Color = Color3.fromRGB(80, 35, 12)
				emberCol.Material = Enum.Material.SmoothPlastic
				emberCol.Anchored = true
				emberCol.CanCollide = false
				emberCol.CanQuery = false
				emberCol.CanTouch = false
				emberCol.CastShadow = false
				emberCol.Transparency = 0.5
				emberCol.Size = Vector3.new(4, 3, 3)
				emberCol.CFrame = CFrame.new(impactPos + Vector3.new(0, 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
				emberCol.Parent = Workspace
				local startTick = tick()
				while emberCol and emberCol.Parent do
					local t = tick() - startTick
					if t > 1.0 then break end
					local rise = t * 5
					local width = 3 + t * 5
					emberCol.Size = Vector3.new(width, 3 + t * 8, 3 + t * 8)
					emberCol.CFrame = CFrame.new(impactPos + Vector3.new(0, 2 + rise, 0)) * CFrame.Angles(0, 0, math.rad(90))
					emberCol.Transparency = 0.5 + t * 0.5
					task.wait(0.03)
				end
				if emberCol and emberCol.Parent then emberCol:Destroy() end
			end)

			-- ===== MESH VFX: DELAYED SECONDARY GROUND RING =====
			-- A second, orange-tinted ring that expands outward a moment
			-- after the first yellow ring, giving the impact a layered feel.
			task.delay(0.08, function()
				local ring2 = Instance.new("Part")
				ring2.Name = "MeteorGroundRing2"
				ring2.Shape = Enum.PartType.Cylinder
				ring2.Color = Color3.fromRGB(255, 120, 30)
				ring2.Material = Enum.Material.Neon
				ring2.Anchored = true
				ring2.CanCollide = false
				ring2.CanQuery = false
				ring2.CanTouch = false
				ring2.CastShadow = false
				ring2.Transparency = 0.3
				ring2.Size = Vector3.new(0.5, 3, 3)
				ring2.CFrame = CFrame.new(impactPos + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
				ring2.Parent = Workspace
				local startTick = tick()
				while ring2 and ring2.Parent do
					local t = tick() - startTick
					if t > 0.6 then break end
					local size = 3 + t * 35
					ring2.Size = Vector3.new(0.5 + t * 1.0, size, size)
					ring2.Transparency = 0.3 + t * 1.2
					task.wait(0.03)
				end
				if ring2 and ring2.Parent then ring2:Destroy() end
			end)

			-- ===== EXTRA MESH VFX: SCORCH DISK + DARK EMBER COLUMN =====
			meshScorchDisk(impactPos, 8, 0.6)
			meshVerticalPillar(impactPos, Color3.fromRGB(80, 35, 12), 4, 3, 0.8)

			-- ===== CRATER BLOCKS =====
			-- Short-lived dark blocks around the impact so the ground shows a
			-- visible crater mark (matches FireShot's behavior, tuned shorter
			-- because 70 meteors share the world).
			vfxMeteorCrater(impactPos)

			-- Clone the miniexplode template at the impact position. The
			-- template's emitter values (Rate 0.1-2, Speed 0.001-0.007) make
			-- the effect nearly invisible on their own, so we boost the
			-- cloned emitters (NOT the template) so the explosion reads
			-- clearly on impact.
			local explode = MiniExplodeTemplate:Clone()
			explode.CFrame = CFrame.new(impactPos)
			explode.Anchored = true
			explode.CanCollide = false
			explode.CanQuery = false
			explode.CanTouch = false
			explode.Parent = Workspace

			for _, desc in ipairs(explode:GetDescendants()) do
				if desc:IsA("ParticleEmitter") then
					desc.Rate = 25
					desc.Speed = NumberRange.new(4, 10)
				end
			end

			-- Emit the miniexplode particles for a short burst, then disable
			-- the emitters so the effect plays exactly once and never loops.
			task.delay(0.5, function()
				if not explode or not explode.Parent then return end
				for _, desc in ipairs(explode:GetDescendants()) do
					if desc:IsA("ParticleEmitter") then
						desc.Enabled = false
					end
				end
			end)

			-- Fade out and remove the meteor (1s transparency tween from
			-- current to 1, then destroy)
			task.delay(0.1, function()
				fadeOutAndRemove(meteor, 1)
			end)

			-- Wait for the explosion to play out, then fade out and remove
			-- the miniexplode (1s transparency tween from current to 1,
			-- then destroy)
			task.delay(2, function()
				fadeOutAndRemove(explode, 1)
			end)
		end

		touchConn = meteor.Touched:Connect(onTouched)

		-- FALLBACK: Use Heartbeat + Raycast to GUARANTEE the impact is
		-- detected even if the Touched event fails to fire (e.g., due to
		-- collision-group quirks, the meteor passing through thin geometry,
		-- or the meteor being destroyed before it can touch anything).
		-- Every frame, raycast straight down 1000 studs; if the hit is
		-- within 3 studs of the meteor, treat that as an impact.
		local rayConn
		rayConn = RunService.Heartbeat:Connect(function()
			if fired or not meteor or not meteor.Parent then
				rayConn:Disconnect()
				return
			end
			local origin = meteor.Position
			local ray = workspace:Raycast(origin, Vector3.new(0, -1000, 0))
			if ray then
				local distance = (origin - ray.Position).Magnitude
				if distance < 3 then
					rayConn:Disconnect()
					onTouched(ray.Instance)
				end
			end
		end)

		-- Safety net: clean up if the meteor never touches anything (e.g. fell off the world)
		Debris:AddItem(meteor, 12)
	end

	-- Wait for the sun to reach its peak position (Bezier ascent takes 1.5s)
	task.wait(1.5)

	-- Spawn 70 meteors one by one at random intervals over 10 seconds,
	-- creating a constant meteor shower effect while the sun is floating.
	local showerStart = tick()
	for i = 1, 70 do
		spawnMeteor()
		if i < 70 then
			local elapsed = tick() - showerStart
			local remaining = math.max(0, 10 - elapsed)
			local avgDelay = remaining / (70 - i)
			-- Random interval: 50%-150% of the average for organic timing
			task.wait(avgDelay * (0.5 + math.random()))
		end
	end

	-- Wait for the last batch of meteors to fall and explode, then fade out
	-- the sun smoothly over 1 second before removing it.
	task.wait(2)
	fadeOutAndRemove(sun, 1)

	-- Safety-net Debris in case the fade coroutine above never runs
	Debris:AddItem(sun, 30)
end

-- ===== GROUND CRACK =====
local function vfxGroundCrack(position: Vector3)
	local part = Instance.new("Part")
	part.Name = "GroundCrack"
	part.Size = Vector3.new(8, 0.5, 8)
	part.Position = position + Vector3.new(0, 0.25, 0)
	part.Anchored = true
	part.CanCollide = false
	part.CastShadow = false
	part.Transparency = 0.7
	part.Color = Color3.fromRGB(30, 20, 10)
	part.Material = Enum.Material.SmoothPlastic
	part.Parent = Workspace

	local tween = TweenService:Create(part, TweenInfo.new(2.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 1 })
	tween:Play()
	tween.Completed:Connect(function()
		part:Destroy()
	end)
end

-- ===== DEBRIS =====
local function spawnDebris(origin: Vector3, color: Color3, debrisType: string, count: number, isHeavy: boolean)
	for i = 1, count do
		local size = math.random(3, 8) / 10
		local chunk = Instance.new("Part")
		chunk.Size = Vector3.new(size, size * math.random(1, 3) * 0.5, size * math.random(1, 3) * 0.5)
		chunk.Color = color
		chunk.Material = Enum.Material.SmoothPlastic
		chunk.Shape = Enum.PartType.Block
		chunk.Anchored = false
		chunk.CanCollide = false
		chunk.CastShadow = false

		local offset = Vector3.new(math.random(-100, 100) / 100 * 2.5, math.random(0, 50) / 100 * 3, math.random(-100, 100) / 100 * 2.5)
		chunk.Position = origin + offset
		chunk.CFrame = chunk.CFrame * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		chunk.Parent = Workspace

		local speed = if isHeavy then 25 else 15
		local bv = Instance.new("BodyVelocity")
		bv.Velocity = Vector3.new(math.random(-100, 100)/100*speed, math.random(30, 80)/100*(if isHeavy then 20 else 12), math.random(-100, 100)/100*speed)
		bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
		bv.Parent = chunk
		Debris:AddItem(bv, 0.3)

		task.delay(1.5 + math.random() * 1.0, function()
			if chunk and chunk.Parent then
				local tween = TweenService:Create(chunk, TweenInfo.new(0.5), { Transparency = 1 })
				tween:Play()
				task.delay(0.5, function()
					if chunk and chunk.Parent then chunk:Destroy() end
				end)
			end
		end)
	end
end

-- ===== IMPACT BLOCKS =====
local function spawnImpactBlocks(origin: Vector3, color: Color3, debrisType: string, blockCount: number)
	local blockShapes = { "Block", "Cylinder", "Wedge" }
	for i = 1, blockCount do
		local width = math.random(10, 24) / 10
		local depth = math.random(8, 20) / 10
		local height = math.random(5, 14) / 10
		local shape = blockShapes[math.random(1, 3)]

		local block: BasePart
		if shape == "Wedge" then
			block = Instance.new("WedgePart")
		else
			block = Instance.new("Part")
			if shape == "Cylinder" then
				block.Shape = Enum.PartType.Cylinder
			end
		end

		block.Size = Vector3.new(width, height, depth)
		block.Color = color
		block.Material = Enum.Material.SmoothPlastic
		block.Anchored = false
		block.CanCollide = false
		block.CastShadow = false

		local angle = (i / blockCount) * math.pi * 2 + math.random(-0.4, 0.4)
		local radius = math.random(4, 10)
		local yOff = math.random(-2, 6)
		block.Position = origin + Vector3.new(math.cos(angle) * radius, yOff, math.sin(angle) * radius)
		block.CFrame = block.CFrame * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		block.Parent = Workspace

		local bv = Instance.new("BodyVelocity")
		local outDir = (block.Position - origin).Unit
		bv.Velocity = outDir * math.random(25, 50) + Vector3.new(0, math.random(8, 20), 0)
		bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
		bv.Parent = block
		Debris:AddItem(bv, 0.4)

		local bav = Instance.new("BodyAngularVelocity")
		bav.AngularVelocity = Vector3.new(math.random(-25, 25), math.random(-25, 25), math.random(-25, 25))
		bav.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
		bav.Parent = block
		Debris:AddItem(bav, 0.5)

		task.delay(2.0 + math.random() * 1.5, function()
			if block and block.Parent then
				local tween = TweenService:Create(block, TweenInfo.new(0.8), { Transparency = 1 })
				tween:Play()
				task.delay(0.8, function()
					if block and block.Parent then block:Destroy() end
				end)
			end
		end)
	end
end

-- ===== PASSIVE FIRE EFFECTS =====
local passiveEmitters: { [string]: Instance } = {}

local function vfxApplyPassive(character: Model)
	for _, inst in passiveEmitters do
		if inst and inst.Parent then inst:Destroy() end
	end
	table.clear(passiveEmitters)

	if getElement() ~= "Fire" then return end
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then return end

	local feetAtt = Instance.new("Attachment")
	feetAtt.Name = "FirePassiveFeet"
	feetAtt.Position = Vector3.new(0, -2.5, 0)
	feetAtt.Parent = hrp
	passiveEmitters["feetAtt"] = feetAtt

	local feetPE = Instance.new("ParticleEmitter")
	feetPE.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, C_YELLOW), ColorSequenceKeypoint.new(0.5, C_ORANGE), ColorSequenceKeypoint.new(1, C_DARK_RED) })
	feetPE.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(0.5, 2.5), NumberSequenceKeypoint.new(1, 0) })
	feetPE.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.6, 0.3), NumberSequenceKeypoint.new(1, 1) })
	feetPE.Lifetime = NumberRange.new(0.5, 1.0)
	feetPE.Rate = 25
	feetPE.Speed = NumberRange.new(0.5, 2)
	feetPE.SpreadAngle = Vector2.new(50, 50)
	feetPE.Acceleration = Vector3.new(0, 6, 0)
	feetPE.RotSpeed = NumberRange.new(-180, 180)
	feetPE.LightEmission = 0.8
	feetPE.LightInfluence = 0
	feetPE.Brightness = 2
	feetPE.Texture = FIRE_TEXTURE
	feetPE.Parent = feetAtt
	passiveEmitters["feetPE"] = feetPE

	local bodyAtt = Instance.new("Attachment")
	bodyAtt.Name = "FirePassiveBody"
	bodyAtt.Position = Vector3.new(0, 0, 0)
	bodyAtt.Parent = hrp
	passiveEmitters["bodyAtt"] = bodyAtt

	local bodyPE = Instance.new("ParticleEmitter")
	bodyPE.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, C_ORANGE), ColorSequenceKeypoint.new(0.5, C_RED), ColorSequenceKeypoint.new(1, Color3.fromRGB(80, 15, 0)) })
	bodyPE.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(0.5, 3.5), NumberSequenceKeypoint.new(1, 0) })
	bodyPE.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(0.5, 0.6), NumberSequenceKeypoint.new(1, 1) })
	bodyPE.Lifetime = NumberRange.new(0.3, 0.7)
	bodyPE.Rate = 10
	bodyPE.Speed = NumberRange.new(1, 3)
	bodyPE.SpreadAngle = Vector2.new(180, 180)
	bodyPE.Acceleration = Vector3.new(0, 10, 0)
	bodyPE.RotSpeed = NumberRange.new(-120, 120)
	bodyPE.LightEmission = 0.7
	bodyPE.LightInfluence = 0
	bodyPE.Brightness = 2
	bodyPE.Texture = FIRE_TEXTURE
	bodyPE.Parent = bodyAtt
	passiveEmitters["bodyPE"] = bodyPE

	local light = addLight(hrp, C_ORANGE, 1.5, 14)
	passiveEmitters["light"] = light
	task.spawn(function()
		while light and light.Parent do
			light.Brightness = 1.2 + math.sin(tick() * 3) * 0.6
			task.wait(0.05)
		end
	end)
end

-- ===== BUBBLES ABILITY VFX =====
-- Spawns 6 floating bubbles from the player's center that spread ~30 studs,
-- follow the player for 15 seconds, chase nearby targets on detection, and
-- burst on collision. Uses the user's existing VFX parts in Workspace
-- (bubblesspawn, bubbleswater, bubbleshock) cloned as-is without modifying
-- their particle settings.

local BUBBLE_COUNT = 6
local BUBBLE_LIFETIME = 6.0
local BUBBLE_SPREAD = 12.0
local BUBBLE_DETECT_RANGE = 35.0
local BUBBLE_HIT_RADIUS = 3.0
local BUBBLE_CHASE_SPEED = 25.0
local BUBBLE_FADE_DURATION = 0.8

local function emitOneShotEffect(templateName: string, position: Vector3, emitCount: number)
	local template = Workspace:FindFirstChild(templateName)
	if not template or not template:IsA("BasePart") then return end
	local effect = template:Clone()
	effect.Anchored = true
	effect.CanCollide = false
	effect.CanQuery = false
	effect.CanTouch = false
	effect.CastShadow = false
	effect.CFrame = CFrame.new(position)
	effect.Parent = Workspace
	for _, desc in effect:GetDescendants() do
		if desc:IsA("ParticleEmitter") then
			desc:Emit(emitCount)
		end
	end
	task.delay(0.1, function()
		if not effect or not effect.Parent then return end
		for _, desc in effect:GetDescendants() do
			if desc:IsA("ParticleEmitter") then
				desc.Enabled = false
			end
		end
	end)
	Debris:AddItem(effect, 5)
end

local function findNearestBubbleTarget(origin: Vector3, range: number): Model?
	local nearest: Model? = nil
	local nearestDist = range

	for _, plr in Players:GetPlayers() do
		if plr == player then continue end
		local char = plr.Character
		if not char then continue end
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then continue end
		local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hrp then continue end
		local dist = (hrp.Position - origin).Magnitude
		if dist < nearestDist then
			nearest = char
			nearestDist = dist
		end
	end

	for _, model in Workspace:GetDescendants() do
		if not model:IsA("Model") then continue end
		if model == currentCharacter then continue end
		local parent = model.Parent
		if parent ~= Workspace and not (parent and parent:IsA("Folder") and parent.Parent == Workspace) then
			continue
		end
		local hum = model:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then continue end
		local hrp = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hrp then continue end
		local dist = (hrp.Position - origin).Magnitude
		if dist < nearestDist then
			nearest = model
			nearestDist = dist
		end
	end

	return nearest
end

local function fadeOutBubble(bubble: Part)
	local emitters: { ParticleEmitter } = {}
	for _, desc in bubble:GetDescendants() do
		if desc:IsA("ParticleEmitter") then
			table.insert(emitters, desc)
		end
	end
	local fadeStart = tick()
	task.spawn(function()
		while bubble and bubble.Parent do
			local t = (tick() - fadeStart) / BUBBLE_FADE_DURATION
			if t >= 1 then
				bubble:Destroy()
				return
			end
			bubble.Transparency = t
			for _, pe in emitters do
				pe.Transparency = NumberSequence.new(t)
			end
			task.wait(0.03)
		end
	end)
end

local function runBubble(bubble: Part, spreadOffset: Vector3)
	local startTime = tick()
	local phase = math.random() * math.pi * 2
	local floatSpeedY = 3.0 + math.random() * 2.0
	local driftSpeed = 2.0 + math.random() * 2.0
	local floatRadius = 1.0 + math.random() * 1.0
	local oscFreq = 4.0 + math.random() * 4.0
	local target: Model? = nil
	local lastSearch = 0

	while bubble and bubble.Parent do
		local elapsed = tick() - startTime
		if elapsed >= BUBBLE_LIFETIME then
			fadeOutBubble(bubble)
			return
		end

		local dt = task.wait(0.03)
		if not bubble or not bubble.Parent then return end

		if not target and tick() - lastSearch > 0.25 then
			lastSearch = tick()
			target = findNearestBubbleTarget(bubble.Position, BUBBLE_DETECT_RANGE)
		end

		if target then
			local hum = target:FindFirstChildOfClass("Humanoid")
			local hrp = target:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not hum or hum.Health <= 0 or not hrp then
				target = nil
			else
				local toTarget = hrp.Position - bubble.Position
				local dist = toTarget.Magnitude
				if dist <= BUBBLE_HIT_RADIUS then
					emitOneShotEffect("bubbleshock", bubble.Position, 20)
					bubble:Destroy()
					return
				end
				if dist > 0.1 then
					bubble.CFrame = CFrame.new(bubble.Position + toTarget.Unit * BUBBLE_CHASE_SPEED * dt)
				end
			end
		else
			if not humanoidRootPart then return end
			local followPos = humanoidRootPart.Position + spreadOffset
			local t = elapsed
			local yOffset = math.sin(t * floatSpeedY + phase) * floatRadius
			local xOffset = math.cos(t * driftSpeed + phase) * floatRadius
			local zOffset = math.sin(t * driftSpeed * 1.3 + phase) * floatRadius
			local oscX = math.sin(t * oscFreq) * 0.4
			local oscZ = math.cos(t * oscFreq * 1.1) * 0.4
			bubble.CFrame = CFrame.new(followPos + Vector3.new(xOffset + oscX, yOffset, zOffset + oscZ))
		end
	end
end

local function vfxBubbles(origin: Vector3)
	emitOneShotEffect("bubblesspawn", origin, 50)

	task.delay(0.4, function()
		local template = Workspace:FindFirstChild("bubbleswater")
		if not template or not template:IsA("BasePart") then
			warn("[bubbles] bubbleswater template not found in Workspace")
			return
		end

		for i = 1, BUBBLE_COUNT do
			local bubble = template:Clone()
			bubble.Anchored = true
			bubble.CanCollide = false
			bubble.CanQuery = false
			bubble.CanTouch = false
			bubble.CastShadow = false
			bubble.Transparency = 0
			bubble.CFrame = CFrame.new(origin)
			bubble.Parent = Workspace

			for _, desc in bubble:GetDescendants() do
				if desc:IsA("ParticleEmitter") then
					desc:Emit(10)
				end
			end

			local angle = math.random() * math.pi * 2
			local radius = BUBBLE_SPREAD * (0.7 + math.random() * 0.5)
			local spreadY = 4 + (math.random() - 0.5) * 2
			local spreadOffset = Vector3.new(
				math.cos(angle) * radius,
				spreadY,
				math.sin(angle) * radius
			)
			local spreadPos = origin + spreadOffset

			TweenService:Create(bubble, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				CFrame = CFrame.new(spreadPos),
			}):Play()

			task.spawn(function()
				task.wait(0.3)
				if bubble and bubble.Parent then
					runBubble(bubble, spreadOffset)
				end
			end)
		end
	end)
end

-- ===== TOOL ACTIVATION =====
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

-- Runs the full client-side skill activation: animation, VFX (telegraph /
-- fireball cast), and fires the SkillActivated remote with targetPos.
-- Shared by the Tool.Activated handler AND the RequestSkillActivation
-- BindableEvent (fired by the toolbar, which bypasses Tool.Activated).
local function activateSkill(tool: Tool, skillName: string, currentElement: string, ability: any)
	local dir = getClickDirection()
	local origin = humanoidRootPart.Position

	local targetPos: Vector3? = nil
	if skillName == "FirePillar" then
		targetPos, dir = getClickTarget()
	end

	if currentElement == "Fire" then
		if skillName == "FireShot" then
			-- Slow wind-up: the fireball is held in the right hand (with its
			-- VFX) during the cast, then thrown 1.2s after activation.
			playAnimation("FireShot", 1.0 / 1.2)
			local character = player.Character
			local heldFireball: Part? = nil
			local heldFolder: Folder? = nil
			local heldWeld: WeldConstraint? = nil
			if character then
				heldFireball, heldFolder, heldWeld = vfxFlameShotHold(character)
			end
			local castStart = tick()
			task.delay(1.2, function()
				if not heldFireball or not heldFolder then return end
				if not humanoidRootPart then heldFolder:Destroy(); return end
				-- Throw from where the hand currently is
				local launchOrigin = heldFireball.Position
				local launchDir = getClickDirection()
				print(string.format("[fireshot] fireball launched after %.2fs", tick() - castStart))
				vfxFlameShotLaunch(heldFireball, heldFolder, heldWeld, launchOrigin, launchDir)
				SkillActivated:FireServer(skillName, launchDir, targetPos)
			end)
			return
		elseif skillName == "FirePillar" then
			playAnimation("FirePillar", 1.0)
			if targetPos then
				vfxFirePillarTelegraph(targetPos)
			end
		elseif skillName == "FlameTracker" then
			playAnimation("FlameTracker", 1.0)
			vfxFlameTrackerCast(origin, dir)
		elseif skillName == "FlameSurge" then
			playAnimation("FlameSurge", 1.0)
			vfxFlameSurge(origin, dir)
		elseif skillName == "MeteorShower" then
			playAnimation("MeteorShower", 1.0)
			task.spawn(function()
				local ok, err = pcall(vfxMeteorShower, player, origin, dir)
				if not ok then
					warn("[fire-client] vfxMeteorShower error:", err)
				end
			end)
		end
	elseif currentElement == "Water" and skillName == "Bubbles" then
		vfxBubbles(origin)
	else
		local elementDef = GachaConfig.getElementByName(currentElement)
		if elementDef then
			vfxGenericElementCast(origin, dir, elementDef.color)
		end
	end

	SkillActivated:FireServer(skillName, dir, targetPos)
end

-- Listens for the toolbar's RequestSkillActivation BindableEvent so the
-- toolbar can route through the same full skill activation code (animation,
-- telegraph, fireball visual, targetPos) instead of bypassing it.
local requestEvent = ReplicatedStorage:FindFirstChild("RequestSkillActivation")
if requestEvent and requestEvent:IsA("BindableEvent") then
	requestEvent.Event:Connect(function(tool: Tool, skillName: string, currentElement: string)
		if skillName == "WaterSpark" then return end -- handled by WaterCombatClient
		if skillName == "GalaxyStrike" then return end -- handled by CelestialCombatClient
		if isAttacking then return end
		if not humanoidRootPart then return end

		local ability = getAbilityConfig(skillName)
		if not ability then warn(string.format("[fire-client] No ability config for %s", skillName)); return end

		if currentElement == "" then currentElement = tool:GetAttribute("Element") :: string end
		if currentElement == "" then currentElement = ability.element end
		if currentElement == "" then return end

		local lastUsed = tool:GetAttribute("LastUsed") :: number?
		if lastUsed and tick() - lastUsed < ability.cooldown then
			print("[combat] " .. skillName .. " on cooldown")
			return
		end

		tool:SetAttribute("LastUsed", tick())
		isAttacking = true

		local success, err = pcall(activateSkill, tool, skillName, currentElement, ability)
		if not success then warn("[fire-client] Ability error:", err) end

		task.delay(0.4, function()
			isAttacking = false
		end)
	end)
	print("[fire-client] RequestSkillActivation listener wired")
end

local function onToolActivated(tool: Tool)
	if isAttacking then return end
	if not humanoidRootPart then return end

	local skillName = tool:GetAttribute("SkillName") :: string?
	if not skillName then return end
	if skillName == "WaterSpark" then return end -- handled by WaterCombatClient
	if skillName == "GalaxyStrike" then return end -- handled by CelestialCombatClient

	local currentElement = getElement()
	if currentElement == "" then
		currentElement = tool:GetAttribute("Element") :: string
	end
	if currentElement == "" then
		local ability = getAbilityConfig(skillName)
		if ability then
			currentElement = ability.element
		end
	end

	if currentElement == "" then
		return
	end

	local ability = getAbilityConfig(skillName)
	if not ability then
		warn(string.format("[fire-client] No ability config for %s", skillName))
		return
	end

	local lastUsed = tool:GetAttribute("LastUsed") :: number?
	if lastUsed and ability then
		if tick() - lastUsed < ability.cooldown then
			print("[combat] " .. skillName .. " on cooldown")
			return
		end
	end

	tool:SetAttribute("LastUsed", tick())
	isAttacking = true

	local success, err = pcall(activateSkill, tool, skillName, currentElement, ability)
	if not success then
		warn("[fire-client] Ability error:", err)
	end

	task.delay(0.4, function()
		isAttacking = false
	end)
end

-- ===== CONNECT TOOLS =====
local function disconnectTools()
	for _, con in toolConnections do
		con:Disconnect()
	end
	toolConnections = {}
end

local function connectTool(tool: Tool)
	disconnectTools()
	local con = tool.Activated:Connect(function()
		onToolActivated(tool)
	end)
	table.insert(toolConnections, con)
end

-- Track all ability tools and connect them without disconnecting others.
local function connectAllTools(character: Model)
	disconnectTools()
	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		for _, child in ipairs(backpack:GetChildren()) do
			if child:IsA("Tool") and child:GetAttribute("IsAbilityTool") then
				local con = child.Activated:Connect(function()
					onToolActivated(child)
				end)
				table.insert(toolConnections, con)
			end
		end
	end
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") and child:GetAttribute("IsAbilityTool") then
			local con = child.Activated:Connect(function()
				onToolActivated(child)
			end)
			table.insert(toolConnections, con)
		end
	end
	-- Tools equipped by Humanoid:EquipTool are parented to the character model in workspace.
	local workspaceChar = character.Parent
	if workspaceChar and workspaceChar:IsA("Model") then
		for _, child in ipairs(workspaceChar:GetChildren()) do
			if child:IsA("Tool") and child:GetAttribute("IsAbilityTool") then
				local con = child.Activated:Connect(function()
					onToolActivated(child)
				end)
				table.insert(toolConnections, con)
			end
		end
	end
	-- Also search the whole workspace for any ability tool belonging to this player
	for _, child in ipairs(Workspace:GetDescendants()) do
		if child:IsA("Tool") and child:GetAttribute("IsAbilityTool") then
			local con = child.Activated:Connect(function()
				onToolActivated(child)
			end)
			table.insert(toolConnections, con)
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

	-- Ensure the camera follows this character so the screen isn't stuck on
	-- the menu's cinematic camera when GameStarted flips to true.
	local camera = Workspace.CurrentCamera
	if camera and humanoid then
		camera.CameraSubject = humanoid
		-- Custom camera ignores CFrame; force the position while Scriptable.
		camera.CameraType = Enum.CameraType.Scriptable
		if humanoidRootPart then
			local camPos = humanoidRootPart.Position + humanoidRootPart.CFrame.LookVector * -12 + Vector3.new(0, 4, 0)
			camera.CFrame = CFrame.lookAt(camPos, humanoidRootPart.Position)
		end
		task.wait()
		camera.CameraType = Enum.CameraType.Custom
	end

	vfxApplyPassive(character)

	local function tryConnectTools()
		connectAllTools(character)
	end

	-- Delay initial connect so tools replicated from the server are present
	for _, delay in ipairs({0.1, 0.3, 0.6, 1.0, 2.0}) do
		task.delay(delay, tryConnectTools)
	end

	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		backpack.ChildAdded:Connect(function(child: Instance)
			if child:IsA("Tool") and child:GetAttribute("IsAbilityTool") then
				connectAllTools(character)
			end
		end)
		backpack.ChildRemoved:Connect(function(child: Instance)
			if child:IsA("Tool") and child:GetAttribute("IsAbilityTool") then
				connectAllTools(character)
			end
		end)
	end

	character.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Tool") and child:GetAttribute("IsAbilityTool") then
			connectAllTools(character)
		end
	end)

	character.ChildRemoved:Connect(function(child: Instance)
		if child:IsA("Tool") and child:GetAttribute("IsAbilityTool") then
			connectAllTools(character)
		end
	end)

	-- When Humanoid:EquipTool is called, the tool may be parented to the
	-- workspace character model rather than the Players.Character model.
	local workspaceChar = character.Parent
	if workspaceChar and workspaceChar:IsA("Model") then
		workspaceChar.ChildAdded:Connect(function(child: Instance)
			if child:IsA("Tool") and child:GetAttribute("IsAbilityTool") then
				connectAllTools(character)
			end
		end)
		workspaceChar.ChildRemoved:Connect(function(child: Instance)
			if child:IsA("Tool") and child:GetAttribute("IsAbilityTool") then
				connectAllTools(character)
			end
		end)
	end

	-- Also watch the Player object itself for tool parent transitions
	player.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Tool") and child:GetAttribute("IsAbilityTool") then
			connectAllTools(character)
		end
	end)
	player.ChildRemoved:Connect(function(child: Instance)
		if child:IsA("Tool") and child:GetAttribute("IsAbilityTool") then
			connectAllTools(character)
		end
	end)
end

player.CharacterAdded:Connect(onCharacterAdded)
if player.Character then
	onCharacterAdded(player.Character)
end

-- Hand off the camera to Roblox's default third-person controller so mouse
-- rotation, zoom, and follow all work natively after the menu's cinematic.
forcePlayerCamera()

-- ===== NETWORKED VFX HANDLER =====
CombatVFX.OnClientEvent:Connect(function(...)
	local args = { ... }
	local eventType = args[1] :: string

	if eventType == "SpawnDebris" then
		local origin = args[2] :: Vector3
		local color = args[3] :: Color3
		local debrisType = args[4] :: string
		local count = args[5] :: number
		local isHeavy = args[6] :: boolean
		spawnDebris(origin, color, debrisType, count, isHeavy)

	elseif eventType == "SpawnBlocks" then
		local origin = args[2] :: Vector3
		local color = args[3] :: Color3
		local debrisType = args[4] :: string
		local count = args[5] :: number
		spawnImpactBlocks(origin, color, debrisType, count)

	elseif eventType == "GroundCrack" then
		local position = args[2] :: Vector3
		vfxGroundCrack(position)

	elseif eventType == "FireShotExplode" then
		-- Clean up client-side projectile visual only for this player's own shot
		local firer = args[2] :: Player
		if firer == player then
			local projFolder = Workspace:FindFirstChild("FlameShotProjectile")
			if projFolder and projFolder:IsA("Folder") then
				projFolder:Destroy()
			end
		end
		vfxFlameShotExplode(args[3] :: Vector3, args[4] :: Enum.Material?)

	elseif eventType == "FirePillar" then
		vfxFirePillar(args[2] :: Vector3)

	elseif eventType == "FlameSurgeCast" then
		vfxFlameSurge(args[3] :: Vector3, args[4] :: Vector3)

	elseif eventType == "FlameSurgeHit" then
		vfxFlameSurgeHit(args[3] :: Vector3, args[4] :: Vector3)

	elseif eventType == "FlameTrackerExplode" then
		vfxFlameTrackerExplode(args[2] :: Vector3, args[3] :: Enum.Material?)

	elseif eventType == "MeteorShower" then
		-- Run in a coroutine so the ~14s VFX doesn't block the main thread
		-- and freeze all tool activations on this client.
		task.spawn(function()
			vfxMeteorShower(args[2] :: Player, args[3] :: Vector3, args[4] :: Vector3)
		end)

	elseif eventType == "BubbleHit" then
		emitOneShotEffect("bubbleshock", args[2] :: Vector3, 20)

	elseif eventType == "Bubbles" then
		vfxBubbles(args[2] :: Vector3)
	end
end)

print("[fire-client] Enhanced Fire Combat Client loaded")
