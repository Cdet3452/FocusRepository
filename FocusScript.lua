-- AreaTransitionController
-- Location: StarterPlayer > StarterPlayerScripts > AreaTransitionController

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local Lighting          = game:GetService("Lighting")

local AreaRegistry = require(ReplicatedStorage.Modules.AreaRegistry)
local VFX_API = require(ReplicatedStorage:WaitForChild("vfx"))

local AreaChanged = ReplicatedStorage.RemoteEvents:WaitForChild("AreaChanged")
local AreaUpdated = ReplicatedStorage.RemoteEvents:WaitForChild("AreaUpdated")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Map        = workspace:WaitForChild("Map")
local AuraHolder = workspace:WaitForChild("AuraHolder")
local HabitatHolder = workspace:WaitForChild("HabitatHolder") 
local AreaAssets = ReplicatedStorage:WaitForChild("AreaAssets")
local MapIgnore  = Map:FindFirstChild("Ignore")
local HabitatPositionPart = HabitatHolder:WaitForChild("Position") 
local PositionPart = AuraHolder:WaitForChild("Position")

local DECORATION_CONTAINER = Map:WaitForChild("Path")

local MAP_PART_COLORS = {
	Floor      = "grassColor",
	AssetFloor = "grassColor",
	Path       = "pathColor",
}

local currentAuraModel = nil
local currentHabitatModel = nil

-- ✨ THE FIX: A clean white flash transition to hide the instant model swapping!
local function PlayAreaFlash()
	local flash = Instance.new("Frame")
	flash.Size = UDim2.new(1, 0, 1, 0)
	flash.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	flash.BackgroundTransparency = 1
	flash.ZIndex = 100000

	local gui = Instance.new("ScreenGui")
	gui.Name = "AreaFlashGui"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 100000
	flash.Parent = gui
	gui.Parent = playerGui

	TweenService:Create(flash, TweenInfo.new(0.2, Enum.EasingStyle.Sine), {BackgroundTransparency = 0}):Play()

	task.delay(0.3, function()
		local tOut = TweenService:Create(flash, TweenInfo.new(0.8, Enum.EasingStyle.Sine), {BackgroundTransparency = 1})
		tOut:Play()
		tOut.Completed:Connect(function() gui:Destroy() end)
	end)
end

local function GetAuraTemplate(areaIndex)
	local folder  = AreaAssets:FindFirstChild("Area" .. areaIndex)
	local rsModel = folder and folder:FindFirstChild("AuraModel")
	if rsModel then return rsModel end

	if MapIgnore then
		local ignoreModel = MapIgnore:FindFirstChild("Area" .. areaIndex .. "Aura")
		if ignoreModel then return ignoreModel end
	end
	return nil
end

local function SwapAuraHolder(areaIndex)
	local template = GetAuraTemplate(areaIndex)
	if not template then return end

	-- Instant swap prevents all transparency bugs
	for _, child in ipairs(AuraHolder:GetChildren()) do
		if child ~= PositionPart then 
			pcall(function() VFX_API.disable(child) end)
			child:Destroy() 
		end
	end
	currentAuraModel = nil

	local newModel = template:Clone()
	newModel.Parent = AuraHolder
	currentAuraModel = newModel
	pcall(function() VFX_API.enable(newModel) end)
end

local function GetHabitatTemplate(areaIndex)
	local folder  = AreaAssets:FindFirstChild("Area" .. areaIndex)
	local rsModel = folder and folder:FindFirstChild("HabitatModel")
	if rsModel then return rsModel end

	if MapIgnore then
		local ignoreModel = MapIgnore:FindFirstChild("Area" .. areaIndex .. "Habitat")
		if ignoreModel then return ignoreModel end
	end
	return nil
end

local function SwapHabitat(areaIndex)
	local template = GetHabitatTemplate(areaIndex)
	if not template then return end

	for _, child in ipairs(HabitatHolder:GetChildren()) do
		if child ~= HabitatPositionPart then child:Destroy() end
	end
	currentHabitatModel = nil
	local newModel = template:Clone()
	newModel.Parent = HabitatHolder
	currentHabitatModel = newModel
end

local function ApplyMapColors(areaData)
	for _, part in ipairs(Map:GetChildren()) do
		if part:IsA("BasePart") then
			local key   = MAP_PART_COLORS[part.Name]
			local color = key and areaData[key]
			if color then
				pcall(function() part.Color = color end)
			end
		end
	end
end

local function ApplyLighting(areaIndex)
	local preset = AreaRegistry.GetLighting(areaIndex)

	local props = {}
	if preset.ClockTime then props.ClockTime = preset.ClockTime end
	if preset.Brightness then props.Brightness = preset.Brightness end
	if preset.FogEnd then props.FogEnd = preset.FogEnd end
	if preset.FogStart then props.FogStart = preset.FogStart end
	if preset.Ambient then props.Ambient = preset.Ambient end
	if preset.FogColor then props.FogColor = preset.FogColor end 

	for prop, val in pairs(props) do pcall(function() Lighting[prop] = val end) end

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		local atmoProps = {}
		if preset.Density then atmoProps.Density = preset.Density end
		if preset.Haze then atmoProps.Haze = preset.Haze end
		if preset.AtmosphereColor then atmoProps.Color = preset.AtmosphereColor end

		for prop, val in pairs(atmoProps) do pcall(function() atmosphere[prop] = val end) end
	end

	local sunRays = Lighting:FindFirstChildOfClass("SunRaysEffect")
	if sunRays then
		local rayProps = { Intensity = preset.SunRaysIntensity or 0.25 }
		for prop, val in pairs(rayProps) do pcall(function() sunRays[prop] = val end) end
	end
end

local function ApplySkybox(areaIndex)
	local preset = AreaRegistry.GetLighting(areaIndex)
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if not sky then return end

	if preset.skyboxBk and preset.skyboxBk ~= "" then pcall(function() sky.SkyboxBk = preset.skyboxBk end) end
	if preset.skyboxDn and preset.skyboxDn ~= "" then pcall(function() sky.SkyboxDn = preset.skyboxDn end) end
	if preset.skyboxFt and preset.skyboxFt ~= "" then pcall(function() sky.SkyboxFt = preset.skyboxFt end) end
	if preset.skyboxLf and preset.skyboxLf ~= "" then pcall(function() sky.SkyboxLf = preset.skyboxLf end) end
	if preset.skyboxRt and preset.skyboxRt ~= "" then pcall(function() sky.SkyboxRt = preset.skyboxRt end) end
	if preset.skyboxUp and preset.skyboxUp ~= "" then pcall(function() sky.SkyboxUp = preset.skyboxUp end) end
end

local function ApplyAuraHolderTint(areaData)
	if not areaData.auraHolderColor and not areaData.auraHolderGlow then return end
	for _, part in ipairs(AuraHolder:GetDescendants()) do
		if currentAuraModel and part:IsDescendantOf(currentAuraModel) then continue end
		if part == PositionPart then continue end
		if part:IsA("BasePart") and areaData.auraHolderColor then
			pcall(function() part.Color = areaData.auraHolderColor end)
		end
		if part:IsA("PointLight") and areaData.auraHolderGlow then
			pcall(function() part.Color = areaData.auraHolderGlow end)
		end
	end
end

local function SwapDecorations(areaIndex)
	local folder = AreaAssets:FindFirstChild("Area" .. areaIndex)
	local newDec = folder and folder:FindFirstChild("Decorations")

	for _, child in ipairs(DECORATION_CONTAINER:GetChildren()) do child:Destroy() end

	if newDec then
		for _, obj in ipairs(newDec:GetChildren()) do
			obj:Clone().Parent = DECORATION_CONTAINER
		end
	end
end

local function ApplyAreaConfig(areaIndex, isTeleporting)
	local areaData = AreaRegistry.Get(areaIndex)

	if isTeleporting then
		PlayAreaFlash()
		task.wait(0.2) 
	end

	SwapAuraHolder(areaIndex)
	SwapHabitat(areaIndex) 
	SwapDecorations(areaIndex)

	if areaData then
		ApplyMapColors(areaData)
		ApplyLighting(areaIndex) 
		ApplySkybox(areaIndex)   
		ApplyAuraHolderTint(areaData)
	end
end

local appliedOnJoin = false
AreaUpdated.OnClientEvent:Connect(function(info)
	if not appliedOnJoin then
		appliedOnJoin = true
		ApplyAreaConfig(info.currentArea or 1, false) 
	end
end)

AreaChanged.OnClientEvent:Connect(function(info)
	ApplyAreaConfig(info.newArea or 1, true) 
end)
