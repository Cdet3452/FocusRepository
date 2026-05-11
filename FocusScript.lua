-- AreaTransitionController
-- Location: StarterPlayer > StarterPlayerScripts > AreaTransitionController
--
-- PER-AREA AURA PLACEMENT:
--   yOffset   = studs up/down from Position Part  (e.g. 5 = 5 studs above)
--   yRotation = degrees of Y-axis rotation        (e.g. 90 = quarter turn)
--   Both set in AreaRegistry per area.
--
-- AURA MODEL LOOKUP ORDER:
--   1. ReplicatedStorage/AreaAssets/Area{N}/AuraModel
--   2. workspace/Map/Ignore/Area{N}Aura
--
-- ALL TweenService:Create calls wrapped in pcall.
-- activeSwap has 10s timeout — no permanent deadlock.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local Lighting          = game:GetService("Lighting")

local AreaRegistry = require(ReplicatedStorage.Modules.AreaRegistry)

-- ✨ NEW: Import the custom VFX API
local VFX_API = require(ReplicatedStorage:WaitForChild("vfx"))

local AreaChanged = ReplicatedStorage.RemoteEvents:WaitForChild("AreaChanged")
local AreaUpdated = ReplicatedStorage.RemoteEvents:WaitForChild("AreaUpdated")

local Map        = workspace:WaitForChild("Map")
local AuraHolder = workspace:WaitForChild("AuraHolder")
local HabitatHolder = workspace:WaitForChild("HabitatHolder") 
local AreaAssets = ReplicatedStorage:WaitForChild("AreaAssets")
local MapIgnore  = Map:FindFirstChild("Ignore")
local HabitatPositionPart = HabitatHolder:WaitForChild("Position") 
local PositionPart = AuraHolder:WaitForChild("Position")

local DECORATION_CONTAINER = Map:WaitForChild("Path")

local TWEEN_DURATION = 2.5
local FADE_DURATION  = 0.5
local SWAP_TIMEOUT   = 10

local MAP_PART_COLORS = {
	Floor      = "grassColor",
	AssetFloor = "grassColor",
	Path       = "pathColor",
}

local currentAuraModel = nil
local activeSwap       = false
local swapStartedAt    = 0

---------------------------------------------------------------
-- SAFE TWEEN
---------------------------------------------------------------
local function SafeTween(instance, tweenInfo, properties)
	pcall(function()
		TweenService:Create(instance, tweenInfo, properties):Play()
	end)
end

---------------------------------------------------------------
-- TRANSPARENCY HELPERS
---------------------------------------------------------------
local function SetTransparency(obj, alpha)
	if obj:IsA("BasePart") then
		pcall(function() obj.Transparency = alpha end)
	elseif obj:IsA("Model") then
		for _, p in ipairs(obj:GetDescendants()) do
			if p:IsA("BasePart") then
				pcall(function() p.Transparency = alpha end)
			end
		end
	end
end

local function TweenTransparency(obj, alpha, duration)
	local info   = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	local tweens = {}
	local parts  = {}
	if obj:IsA("BasePart") then
		table.insert(parts, obj)
	elseif obj:IsA("Model") then
		for _, p in ipairs(obj:GetDescendants()) do
			if p:IsA("BasePart") then table.insert(parts, p) end
		end
	end
	for _, part in ipairs(parts) do
		local ok, t = pcall(function()
			return TweenService:Create(part, info, { Transparency = alpha })
		end)
		if ok and t then t:Play(); table.insert(tweens, t) end
	end
	return tweens
end

---------------------------------------------------------------
-- PLACE AT POSITION WITH OFFSET + ROTATION
-- Builds a CFrame from Position Part + yOffset + yRotation.
--   yOffset   = studs along world Y axis
--   yRotation = degrees around world Y axis
---------------------------------------------------------------
local function PlaceAtPosition(obj, yOffset, yRotation)
	local pos      = PositionPart.Position + Vector3.new(0, yOffset or 0, 0)
	local rotation = CFrame.Angles(0, math.rad(yRotation or 0), 0)
	local targetCF = CFrame.new(pos) * rotation

	pcall(function()
		if obj:IsA("Model") then
			-- ✨ BULLETPROOF ALIGNMENT FIX ✨
			-- Force the script to use the 'Position' part as the center of gravity,
			-- completely ignoring the bounding box of the conveyor belt!
			local centerPart = obj:FindFirstChild("Position", true)
			if centerPart and centerPart:IsA("BasePart") then
				obj.PrimaryPart = centerPart
			end

			obj:PivotTo(targetCF)
		elseif obj:IsA("BasePart") then
			obj.CFrame = targetCF
		end
	end)
end

---------------------------------------------------------------
-- AURA MODEL LOOKUP
---------------------------------------------------------------
local function GetAuraTemplate(areaIndex)
	local folder  = AreaAssets:FindFirstChild("Area" .. areaIndex)
	local rsModel = folder and folder:FindFirstChild("AuraModel")
	if rsModel then return rsModel end

	if MapIgnore then
		local ignoreModel = MapIgnore:FindFirstChild("Area" .. areaIndex .. "Aura")
		if ignoreModel then return ignoreModel end
	end

	warn("[AreaTransition] No AuraModel for area " .. areaIndex
		.. " — checked AreaAssets/Area" .. areaIndex .. "/AuraModel"
		.. " and Map/Ignore/Area" .. areaIndex .. "Aura")
	return nil
end

---------------------------------------------------------------
-- AURA HOLDER SWAP
---------------------------------------------------------------
local function SwapAuraHolder(areaIndex, instant)
	local template = GetAuraTemplate(areaIndex)
	if not template then
		warn("[AreaTransition] Skipping swap — no template for area " .. areaIndex)
		return
	end

	if instant then
		for _, child in ipairs(AuraHolder:GetChildren()) do
			if child ~= PositionPart then 
				-- ✨ NEW: Disable old custom VFX before destroying the part
				pcall(function() VFX_API.disable(child) end)
				child:Destroy() 
			end
		end
		currentAuraModel = nil

		local newModel = template:Clone()
		newModel.Parent = AuraHolder

		-- ✨ FIX: Removed PivotTo! It now spawns EXACTLY where you built it in Studio.
		currentAuraModel = newModel

		-- ✨ NEW: Instantly enable the custom VFX once placed in Workspace
		pcall(function() VFX_API.enable(newModel) end)

	else
		if activeSwap and (tick() - swapStartedAt) < SWAP_TIMEOUT then return end
		activeSwap    = true
		swapStartedAt = tick()

		task.spawn(function()
			if currentAuraModel and currentAuraModel.Parent then
				-- ✨ NEW: Disable old custom VFX smoothly as the model fades out
				pcall(function() VFX_API.disable(currentAuraModel) end)

				local outTweens = TweenTransparency(currentAuraModel, 1, FADE_DURATION)
				if #outTweens > 0 then
					outTweens[1].Completed:Wait()
				else
					task.wait(FADE_DURATION)
				end
				if currentAuraModel and currentAuraModel.Parent then
					currentAuraModel:Destroy()
				end
				currentAuraModel = nil
			else
				task.wait(FADE_DURATION)
			end

			local newModel = template:Clone()
			newModel.Parent = AuraHolder

			-- ✨ FIX: Removed PivotTo! 
			SetTransparency(newModel, 1)
			currentAuraModel = newModel

			-- ✨ NEW: Turn on the new custom VFX so it begins while fading in
			pcall(function() VFX_API.enable(newModel) end)

			TweenTransparency(newModel, 0, FADE_DURATION)

			task.wait(FADE_DURATION)
			activeSwap = false
		end)
	end
end

---------------------------------------------------------------
-- HABITAT MODEL LOOKUP
---------------------------------------------------------------
local function GetHabitatTemplate(areaIndex)
	local folder  = AreaAssets:FindFirstChild("Area" .. areaIndex)
	local rsModel = folder and folder:FindFirstChild("HabitatModel")
	if rsModel then return rsModel end

	if MapIgnore then
		local ignoreModel = MapIgnore:FindFirstChild("Area" .. areaIndex .. "Habitat")
		if ignoreModel then return ignoreModel end
	end

	warn("[AreaTransition] No HabitatModel for area " .. areaIndex
		.. " — checked AreaAssets/Area" .. areaIndex .. "/HabitatModel")
	return nil
end

---------------------------------------------------------------
-- HABITAT SWAP
---------------------------------------------------------------
local currentHabitatModel = nil

local function SwapHabitat(areaIndex, instant)
	local template = GetHabitatTemplate(areaIndex)
	if not template then
		warn("[AreaTransition] Skipping habitat swap — no template for area " .. areaIndex)
		return
	end

	if instant then
		for _, child in ipairs(HabitatHolder:GetChildren()) do
			if child ~= HabitatPositionPart then child:Destroy() end
		end
		currentHabitatModel = nil

		local newModel = template:Clone()
		newModel.Parent = HabitatHolder

		-- ✨ FIX: Removed PivotTo! It now spawns EXACTLY where you built it in Studio.
		currentHabitatModel = newModel
	else
		-- Async Tweening Swap
		task.spawn(function()
			if currentHabitatModel and currentHabitatModel.Parent then
				local outTweens = TweenTransparency(currentHabitatModel, 1, FADE_DURATION)
				if #outTweens > 0 then
					outTweens[1].Completed:Wait()
				else
					task.wait(FADE_DURATION)
				end
				if currentHabitatModel and currentHabitatModel.Parent then
					currentHabitatModel:Destroy()
				end
				currentHabitatModel = nil
			else
				task.wait(FADE_DURATION)
			end

			local newModel = template:Clone()
			newModel.Parent = HabitatHolder

			-- ✨ FIX: Removed PivotTo! 
			SetTransparency(newModel, 1)
			currentHabitatModel = newModel
			TweenTransparency(newModel, 0, FADE_DURATION)
		end)
	end
end
---------------------------------------------------------------
-- MAP COLORS
---------------------------------------------------------------
local function ApplyMapColors(areaData, instant)
	local info = TweenInfo.new(TWEEN_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	for _, part in ipairs(Map:GetChildren()) do
		if part:IsA("BasePart") then
			local key   = MAP_PART_COLORS[part.Name]
			local color = key and areaData[key]
			if color then
				if instant then pcall(function() part.Color = color end)
				else SafeTween(part, info, { Color = color }) end
			end
		end
	end
end

local function ApplyLighting(areaIndex, instant)
	local preset = AreaRegistry.GetLighting(areaIndex)

	-- 1. Tween standard Lighting properties
	local props = {}
	if preset.ClockTime then props.ClockTime = preset.ClockTime end
	if preset.Brightness then props.Brightness = preset.Brightness end
	if preset.FogEnd then props.FogEnd = preset.FogEnd end
	if preset.FogStart then props.FogStart = preset.FogStart end
	if preset.Ambient then props.Ambient = preset.Ambient end
	if preset.FogColor then props.FogColor = preset.FogColor end 

	if instant then
		for prop, val in pairs(props) do pcall(function() Lighting[prop] = val end) end
	elseif next(props) then
		SafeTween(Lighting, TweenInfo.new(TWEEN_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), props)
	end

	-- ✨ 2. Tween Atmosphere properties
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		local atmoProps = {}
		if preset.Density then atmoProps.Density = preset.Density end
		if preset.Haze then atmoProps.Haze = preset.Haze end
		if preset.AtmosphereColor then atmoProps.Color = preset.AtmosphereColor end

		if instant then
			for prop, val in pairs(atmoProps) do pcall(function() atmosphere[prop] = val end) end
		elseif next(atmoProps) then
			SafeTween(atmosphere, TweenInfo.new(TWEEN_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), atmoProps)
		end
	end

	-- ✨ 3. Tween SunRays properties (NEW!)
	local sunRays = Lighting:FindFirstChildOfClass("SunRaysEffect")
	if sunRays then
		local rayProps = {}

		-- Use the preset intensity, or default back to 0.25 if the preset forgot to mention it
		if preset.SunRaysIntensity ~= nil then 
			rayProps.Intensity = preset.SunRaysIntensity 
		else
			rayProps.Intensity = 0.25
		end

		if instant then
			for prop, val in pairs(rayProps) do pcall(function() sunRays[prop] = val end) end
		elseif next(rayProps) then
			SafeTween(sunRays, TweenInfo.new(TWEEN_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), rayProps)
		end
	end
end

---------------------------------------------------------------
-- SKYBOX (Updated to use Presets)
---------------------------------------------------------------
local function ApplySkybox(areaIndex, instant)
	local preset = AreaRegistry.GetLighting(areaIndex)
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if not sky then return end

	local function DoSwap()
		if preset.skyboxBk and preset.skyboxBk ~= "" then pcall(function() sky.SkyboxBk = preset.skyboxBk end) end
		if preset.skyboxDn and preset.skyboxDn ~= "" then pcall(function() sky.SkyboxDn = preset.skyboxDn end) end
		if preset.skyboxFt and preset.skyboxFt ~= "" then pcall(function() sky.SkyboxFt = preset.skyboxFt end) end
		if preset.skyboxLf and preset.skyboxLf ~= "" then pcall(function() sky.SkyboxLf = preset.skyboxLf end) end
		if preset.skyboxRt and preset.skyboxRt ~= "" then pcall(function() sky.SkyboxRt = preset.skyboxRt end) end
		if preset.skyboxUp and preset.skyboxUp ~= "" then pcall(function() sky.SkyboxUp = preset.skyboxUp end) end
	end

	if instant then DoSwap()
	else task.delay(TWEEN_DURATION * 0.5, DoSwap) end
end

---------------------------------------------------------------
-- AURAHOLDER RING TINT
---------------------------------------------------------------
local function ApplyAuraHolderTint(areaData, instant)
	if not areaData.auraHolderColor and not areaData.auraHolderGlow then return end
	local info = TweenInfo.new(TWEEN_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	for _, part in ipairs(AuraHolder:GetDescendants()) do
		if currentAuraModel and part:IsDescendantOf(currentAuraModel) then continue end
		if part == PositionPart then continue end
		if part:IsA("BasePart") and areaData.auraHolderColor then
			if instant then pcall(function() part.Color = areaData.auraHolderColor end)
			else SafeTween(part, info, { Color = areaData.auraHolderColor }) end
		end
		if part:IsA("PointLight") and areaData.auraHolderGlow then
			if instant then pcall(function() part.Color = areaData.auraHolderGlow end)
			else SafeTween(part, info, { Color = areaData.auraHolderGlow }) end
		end
	end
end

---------------------------------------------------------------
-- DECORATIONS
---------------------------------------------------------------
local function FadeDecorations(alpha, duration)
	local info   = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	local tweens = {}
	for _, obj in ipairs(DECORATION_CONTAINER:GetDescendants()) do
		if obj:IsA("BasePart") then
			local ok, t = pcall(function()
				return TweenService:Create(obj, info, { Transparency = alpha })
			end)
			if ok and t then t:Play(); table.insert(tweens, t) end
		end
	end
	if #tweens > 0 then tweens[1].Completed:Wait() end
end

---------------------------------------------------------------
-- DECORATIONS (With Memory Transparency Fix)
---------------------------------------------------------------
local function SwapDecorations(areaIndex)
	local folder = AreaAssets:FindFirstChild("Area" .. areaIndex)
	local newDec = folder and folder:FindFirstChild("Decorations")

	-- 1. Fade OUT old decorations
	for _, child in ipairs(DECORATION_CONTAINER:GetChildren()) do
		for _, desc in ipairs(child:GetDescendants()) do
			if desc:IsA("BasePart") or desc:IsA("Decal") or desc:IsA("Texture") then
				SafeTween(desc, TweenInfo.new(TWEEN_DURATION * 0.5), {Transparency = 1})
			end
		end
	end

	task.wait(TWEEN_DURATION * 0.5)

	-- Destroy the old ones once they are invisible
	for _, child in ipairs(DECORATION_CONTAINER:GetChildren()) do 
		child:Destroy() 
	end

	-- 2. Fade IN new decorations
	if newDec then
		for _, obj in ipairs(newDec:GetChildren()) do
			local clone = obj:Clone()

			-- ✨ THE FIX: Save the original transparency before making it invisible!
			for _, desc in ipairs(clone:GetDescendants()) do
				if desc:IsA("BasePart") or desc:IsA("Decal") or desc:IsA("Texture") then
					-- Memorize its true transparency as an Attribute
					desc:SetAttribute("OrigTrans", desc.Transparency)
					-- Now hide it for the fade-in
					desc.Transparency = 1
				end
			end

			clone.Parent = DECORATION_CONTAINER

			-- ✨ THE FIX: Tween back to the saved value instead of 0!
			for _, desc in ipairs(clone:GetDescendants()) do
				if desc:IsA("BasePart") or desc:IsA("Decal") or desc:IsA("Texture") then
					local targetTrans = desc:GetAttribute("OrigTrans") or 0
					SafeTween(desc, TweenInfo.new(TWEEN_DURATION * 0.5), {Transparency = targetTrans})
				end
			end
		end
	end
end

---------------------------------------------------------------
-- MASTER
---------------------------------------------------------------
local function ApplyAreaConfig(areaIndex, instant)
	local areaData = AreaRegistry.Get(areaIndex)
	SwapAuraHolder(areaIndex, instant)
	SwapHabitat(areaIndex, instant) 
	if areaData then
		ApplyMapColors(areaData, instant)
		ApplyLighting(areaIndex, instant) -- ✨ FIX: Passing areaIndex
		ApplySkybox(areaIndex, instant)   -- ✨ FIX: Passing areaIndex
		ApplyAuraHolderTint(areaData, instant)
	end

	if instant then
		local folder = AreaAssets:FindFirstChild("Area" .. areaIndex)
		local newDec = folder and folder:FindFirstChild("Decorations")
		for _, child in ipairs(DECORATION_CONTAINER:GetChildren()) do child:Destroy() end
		if newDec then
			for _, obj in ipairs(newDec:GetChildren()) do obj:Clone().Parent = DECORATION_CONTAINER end
		end
	else
		task.spawn(function() SwapDecorations(areaIndex) end)
	end
end

---------------------------------------------------------------
-- STARTUP
---------------------------------------------------------------
task.defer(function()
	--print("[AreaTransition] Position Part at:", PositionPart.Position)
	--print("[AreaTransition] Ready — yOffset + yRotation read from AreaRegistry per area")
end)

---------------------------------------------------------------
-- CONNECTIONS
---------------------------------------------------------------
local appliedOnJoin = false

AreaUpdated.OnClientEvent:Connect(function(info)
	if not appliedOnJoin then
		appliedOnJoin = true
		print("[AreaTransition] Join → area", info.currentArea or 1)
		ApplyAreaConfig(info.currentArea or 1, true)
	end
end)

AreaChanged.OnClientEvent:Connect(function(info)
	print("[AreaTransition] AreaChanged →", info.newArea, "(" .. (info.travelType or "?") .. ")")
	ApplyAreaConfig(info.newArea or 1, false)
end)
