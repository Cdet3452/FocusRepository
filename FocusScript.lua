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
		return Habitat:GetPivot().Position
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
