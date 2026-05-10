local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")

local Assets = ReplicatedStorage.Assets.Abilities.Law
local fx = require(ReplicatedStorage.Modules.Ability.VFXHelp)
local Packets = require(ReplicatedStorage.Modules.Packets)
local MouseData = require(ReplicatedStorage.Modules.Ability.MouseData)
local Misc = require(ReplicatedStorage.Modules.Misc)
local Movement = require(ReplicatedStorage.Modules.Ability.MovementLock)

return function(Player: Player, Character: Model, Stats)
	local HRP = Character:FindFirstChild("HumanoidRootPart")
	local Humanoid = Character:FindFirstChildWhichIsA("Humanoid")
	if not HRP then return end

	local Folder = workspace.Debris:FindFirstChild("Room_" .. Player.Name)
	if not Folder then
		warn(Player.Name .. " tried to use Shambles_ but no Room is Open")
		return
	end
	local loaded = Humanoid:LoadAnimation(Assets.LawShamblesAnim)
	loaded.Priority = Enum.AnimationPriority.Action4
	loaded:Play()	
	
	Movement.ApplySlow(Character, 0.1, 1)
	
	loaded:GetMarkerReachedSignal("Cast"):Connect(function()

		local RoomMesh = Folder:FindFirstChild("MockRoom")

		local roomCenter = RoomMesh.Position
		local roomRadius = RoomMesh.Size.X / 2
		local targetPos = MouseData.Positions[Player.UserId]
		if not targetPos then return end

		-- Inside room check
		if (HRP.Position - roomCenter).Magnitude > roomRadius then
			warn(Player.Name .. " is outside the room, can't use Shambles_")
			return
		end
		if (targetPos - roomCenter).Magnitude > roomRadius then
			warn("Mouse target is outside the room")
			return
		end

		-- Find closest humanoid to mouse position
		local closestTarget = nil
		local closestDist = 10 -- stud range around mouse

		for _, model in pairs(workspace:GetDescendants()) do
			local hum = model:FindFirstChildOfClass("Humanoid")
			local hrp = model:FindFirstChild("HumanoidRootPart")
			if hum and hrp and model ~= Character then
				local distToMouse = (hrp.Position - targetPos).Magnitude
				local distToRoom = (hrp.Position - roomCenter).Magnitude
				if distToMouse <= closestDist and distToRoom <= roomRadius then
					closestDist = distToMouse
					closestTarget = hrp
				end
			end
		end

		if not closestTarget then
			warn("No valid target near mouse for Shambles_")
			return
		end

		-- Swap setup
		local casterPos, targetPos = HRP.Position, closestTarget.Position
		local casterRot, targetRot = HRP.Orientation, closestTarget.Orientation

		local ShamblesFolder = Instance.new("Folder")
		ShamblesFolder.Name = "Shambles_" .. Player.Name
		ShamblesFolder.Parent = Folder

		local ShamblesVFXStart = fx.CloneParticle(Assets.ShamblesVFXStart.fx:Clone(), ShamblesFolder, HRP.Position)
		local ShamblesVFXEnd = fx.CloneParticle(Assets.ShamblesVFXEnd.fx:Clone(), ShamblesFolder, closestTarget.Position)

		Packets.AbilityCore:Fire({'Emit', ShamblesVFXStart})
		Packets.AbilityCore:Fire({'Emit', ShamblesVFXEnd})

		--Da swap
		HRP.CFrame = CFrame.new(targetPos) * CFrame.Angles(
			math.rad(casterRot.X),
			math.rad(casterRot.Y),
			math.rad(casterRot.Z)
		)
		closestTarget.CFrame = CFrame.new(casterPos) * CFrame.Angles(
			math.rad(targetRot.X),
			math.rad(targetRot.Y),
			math.rad(targetRot.Z)
		)

		HRP.Velocity = Vector3.zero
		closestTarget.Velocity = Vector3.zero

		local eHumanoid = closestTarget.Parent:FindFirstChildOfClass("Humanoid")
		if eHumanoid then
			local anim = eHumanoid:LoadAnimation(Assets.Stun)
			anim:Play()
			Misc.InsertDisabled(closestTarget.Parent, 1)
			game.Debris:AddItem(anim, 3)
		end

		fx.Cleanup(ShamblesFolder, 2)
	end)

end

-- MouseData.lua
local MouseData = {}
MouseData.Positions = {} -- keyed by player.UserId -> Vector3
return MouseData

--local bridge
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local camera = workspace.CurrentCamera

local MouseData = require(ReplicatedStorage.Modules.Ability.MouseData)
local BridgeNet2 = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))
local MouseBridge = BridgeNet2.ClientBridge("MousePosition") -- make a bridge

-- Send mouse position every 0.2 seconds
task.spawn(function()
	while task.wait(0.05) do
		local mousePos = UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
		local result = workspace:Raycast(ray.Origin, ray.Direction * 1000)

		if result then
			MouseBridge:Fire(result.Position)
		end
	end
end)

--server bridge
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BridgeNet2 = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))

local MouseData = require(ReplicatedStorage.Modules.Ability.MouseData)
local MouseBridge = BridgeNet2.ServerBridge("MousePosition") -- listen to same bridge

MouseBridge:Connect(function(player, mousePos)
	MouseData.Positions[player.UserId] = mousePos
end)

--Bridgentv2 thing:
--BridgeNet2:
return require(script.src)

--src:
--!strict
local RunService = game:GetService("RunService")

local Client = require(script.Client)
local PublicTypes = require(script.PublicTypes)
local Server = require(script.Server)
local MockBridge = require(script.Studio.MockBridge)
local NetworkUtils = require(script.Utilities.NetworkUtils)
local Output = require(script.Utilities.Output)
local isEditMode = require(script.Utilities.isEditMode)
local version = require(script.version)

local isServer = RunService:IsServer()

task.spawn(function()
	if not isEditMode then
		if isServer then
			Server.start()
		else
			Client.start()
		end
	end
end)

--[=[
	The parent of all classes.

	@class BridgeNet2
]=]

--[=[
	Generates a new UUID, removing all dashes (-).

	@prop CreateUUID () -> (string)
	@within BridgeNet2
]=]

--[=[
	References an identifier.

	@prop ReferenceIdentifer (name: string) -> (Types.Identifier?)
	@within BridgeNet2
]=]

--[=[
	Allows you to send a bridge event to all players.

	@prop AllPlayers any
	@within BridgeNet2
]=]

--[=[
	Allows you to send a bridge event to all players except for the listed players.

	@prop PlayersExcept any
	@within BridgeNet2
]=]

--[=[
	Allows you to send a bridge event to specific players only.

	@prop Players any
	@within BridgeNet2
]=]

--[=[
	References a bridge.

	@prop ReferenceBridge (name: string) -> (any)
	@within BridgeNet2
]=]

--[=[
	References a server bridge directly.

	@prop ServerBridge (name: string) -> (any)
	@within BridgeNet2
]=]

--[=[
	References a server bridge directly.

	@prop ClientBridge (name: string) -> (any)
	@within BridgeNet2
]=]

--[=[
	The function to handle invalid packets with.

	@prop HandleInvalidPlayer (handler: (player: Player) -> ()) -> ()
	@within BridgeNet2
]=]

local BridgeNet2 = {
	ToHex = NetworkUtils.ToHex,
	ToReadableHex = NetworkUtils.ToReadableHex,
	FromHex = NetworkUtils.FromHex,

	CreateUUID = NetworkUtils.CreateUUID,

	ReferenceIdentifier = if isServer then Server.makeIdentifier else Client.makeIdentifier,
	Deserialize = if isServer then Server.deser else Client.deser,
	Serialize = if isServer then Server.ser else Client.ser,

	AllPlayers = Server.playerContainers().All,

	PlayersExcept = Server.playerContainers().Except,

	Players = Server.playerContainers().Players,

	ReferenceBridge = if isServer then Server.makeBridge else Client.makeBridge,
	ServerBridge = if isServer then Server.makeBridge else nil,
	ClientBridge = if not isServer then Client.makeBridge else nil,

	Types = script.ExportedTypes,

	HandleInvalidPlayer = function(handler: (player: Player) -> ())
		Output.fatalAssert(isServer, "Cannot call from client")

		Server.invalidPlayerhandler(handler)
	end,

	version = version,
}

if isEditMode then
	Output.log("running BridgeNet2 in mock mode")

	BridgeNet2.ClientBridge = MockBridge
	BridgeNet2.ServerBridge = nil
	BridgeNet2.ReferenceBridge = MockBridge

	function BridgeNet2.ReferenceIdentifier(identifier)
		return identifier
	end

	function BridgeNet2.Serialize(identifier)
		return identifier
	end

	function BridgeNet2.Deserialize(identifier)
		return identifier
	end
end

table.freeze(BridgeNet2)

return (BridgeNet2 :: {}) :: PublicTypes.BridgeNet2


--MockBridge:
							--!strict
local MockConnection = require(script.Parent.MockConnection)
local Constants = require(script.Parent.Parent.Constants)
local Output = require(script.Parent.Parent.Utilities.Output)
local TableKit = require(script.Parent.Parent.Parent.TableKit)
local RemotePacketSizeCounter = require(script.Parent.Parent.Parent.RemotePacketSizeCounter)
local Types = require(script.Parent.Parent.Types)
local tostringData = require(script.Parent.Parent.Utilities.tostringData)

local mockBridgePrototype = {}

local CLASS_METATABLE = { __index = mockBridgePrototype }

function CLASS_METATABLE:__tostring()
	return "ClientBridge"
end

function mockBridgePrototype:RateLimit()
	Output.warn("cannot call :RateLimit() from client")
end

function mockBridgePrototype:DisableRateLimit()
	Output.warn("cannot call :DisableRateLimit() from client")
end

function mockBridgePrototype:InboundMiddleware(middlewareTable: { (object: any) -> any })
	Output.fatalAssert(tostring(self) == "ClientBridge", "InboundMiddleware called with . instead of :")
	Output.fatalAssert(
		typeof(middlewareTable) == "table",
		string.format("InboundMiddleware takes table, got %*", typeof(middlewareTable))
	)
	Output.warnAssert(TableKit.IsArray(middlewareTable), "InboundMiddleware takes array, got dictionary.")

	self._inboundMiddleware = middlewareTable
end

function mockBridgePrototype:OutboundMiddleware(middlewareTable: { (object: any) -> any })
	Output.fatalAssert(tostring(self) == "ClientBridge", "OutboundMiddleware called with . instead of :")
	Output.fatalAssert(
		typeof(middlewareTable) == "table",
		string.format("OutboundMiddleware takes table, got %*", typeof(middlewareTable))
	)
	Output.warnAssert(TableKit.IsArray(middlewareTable), "InboundMiddleware takes array, got dictionary.")

	self._outboundMiddleware = middlewareTable
end

function mockBridgePrototype:Fire(content: any)
	Output.fatalAssert(tostring(self) == "ClientBridge", "Fire called with . instead of :")

	if self.Logging then
		local logOutput = string.format(
			Constants.CLIENT_FIRE_LOG,
			self._name,
			tostringData(content),
			RemotePacketSizeCounter.GetDataByteSize(content)
		)
		Output.log(logOutput)
	end
end

function mockBridgePrototype:Connect(callback: (content: Types.Content) -> ())
	Output.fatalAssert(tostring(self) == "ClientBridge", "connect called with . instead of :")
	Output.typecheck("function", "Connect", "callback", callback)

	return MockConnection()
end

function mockBridgePrototype:Wait()
	Output.fatalAssert(tostring(self) == "ClientBridge", "Wait called with . instead of :")
	-- Again, very basic QoL implementation of :Wait()
	local thread = coroutine.running()
	self:Once(function(content)
		task.spawn(thread, content)
	end)
	return coroutine.yield()
end

function mockBridgePrototype:InvokeServerAsync(_: any)
	Output.fatalAssert(tostring(self) == "ClientBridge", "InvokeServerAsync called with . instead of :")

	return coroutine.yield()
end

function mockBridgePrototype:Once(_: (content: Types.Content) -> ())
	Output.fatalAssert(tostring(self) == "ClientBridge", "Once called with . instead of :")

	return MockConnection()
end

function mockBridgePrototype:Destroy()
	Output.fatalAssert(tostring(self) == "ClientBridge", "Destroy called with . instead of :")
	-- Don't actually do any logic here- remember that ClientBridges are really just listening objects that let the end user communicate.
	table.clear(self)
	setmetatable(self, nil)
end

return function(name: string)
	local self = setmetatable({
		Logging = false,

		_identifier = name,
		_name = name,

		_inboundMiddleware = {},
		_outboundMiddleware = {},
	}, CLASS_METATABLE)

	return self
end


							--Client:
							--!strict
local ClientBridge = require(script.ClientBridge)
local ClientIdentifiers = require(script.ClientIdentifiers)
local ClientProcess = require(script.ClientProcess)
local Types = require(script.Parent.Types)
local isEditMode = require(script.Parent.Utilities.isEditMode)

local activeBridges = {}

local Client = {}

function Client.start()
	if isEditMode then
		return
	end

	ClientProcess.start()
	ClientIdentifiers.start()
end

function Client.ser(identifierName: Types.Identifier): Types.Identifier?
	if isEditMode then
		return identifierName
	end

	return ClientIdentifiers.ser(identifierName)
end

function Client.deser(compressedIdentifier: Types.Identifier): Types.Identifier?
	if isEditMode then
		return compressedIdentifier
	end

	return ClientIdentifiers.deser(compressedIdentifier)
end

function Client.makeIdentifier(name: string, timeout: number?)
	if isEditMode then
		return name
	end

	return ClientIdentifiers.ref(name, timeout, false)
end

function Client.makeBridge(name: string)
	if activeBridges[name] then
		return activeBridges[name]
	else
		local bridge = ClientBridge(name)

		activeBridges[name] = bridge

		return bridge
	end
end

return Client


							--ClientBridge:
							--!strict
local ClientConnection = require(script.Parent.ClientConnection)
local ClientIdentifiers = require(script.Parent.ClientIdentifiers)
local ClientProcess = require(script.Parent.ClientProcess)
local Constants = require(script.Parent.Parent.Constants)
local Output = require(script.Parent.Parent.Utilities.Output)
local TableKit = require(script.Parent.Parent.Parent.TableKit)
local RemotePacketSizeCounter = require(script.Parent.Parent.Parent.RemotePacketSizeCounter)
local Types = require(script.Parent.Parent.Types)
local NetworkUtils = require(script.Parent.Parent.Utilities.NetworkUtils)
local tostringData = require(script.Parent.Parent.Utilities.tostringData)

--[=[
	This class handles the client-sided interface of BridgeNet2.

	@class ClientBridge
]=]
local clientBridgePrototype = {}

local CLASS_METATABLE = { __index = clientBridgePrototype }

function CLASS_METATABLE:__tostring()
	return "ClientBridge"
end

--[=[
	Sets the rate limit, cannot be used client-sided.
	
	@within ClientBridge
	@ignore
	@return string
]=]
function clientBridgePrototype:RateLimit()
	Output.warn("cannot call :RateLimit() from client")
end

--[=[
	Disables the rate limit, cannot be used client-sided.

	@within ClientBridge
	@ignore
	@return string
]=]
function clientBridgePrototype:DisableRateLimit()
	Output.warn("cannot call :DisableRateLimit() from client")
end

--[=[
	Sets some middleware to run when a bridge is fired from the server. 

	@within ClientBridge
	@param middlewareTable {(object: any) -> any}
]=]
function clientBridgePrototype:InboundMiddleware(middlewareTable: { (object: any) -> any })
	Output.fatalAssert(tostring(self) == "ClientBridge", "InboundMiddleware called with . instead of :")
	Output.fatalAssert(
		typeof(middlewareTable) == "table",
		string.format("InboundMiddleware takes table, got %*", typeof(middlewareTable))
	)
	Output.warnAssert(TableKit.IsArray(middlewareTable), "InboundMiddleware takes array, got dictionary.")

	self._inboundMiddleware = middlewareTable
end

--[=[
	Sets some middleware to run when a bridge is fired from the local client. 

	@within ClientBridge
	@param middlewareTable {(object: any) -> any}
]=]
function clientBridgePrototype:OutboundMiddleware(middlewareTable: { (object: any) -> any })
	Output.fatalAssert(tostring(self) == "ClientBridge", "OutboundMiddleware called with . instead of :")
	Output.fatalAssert(
		typeof(middlewareTable) == "table",
		string.format("OutboundMiddleware takes table, got %*", typeof(middlewareTable))
	)
	Output.warnAssert(TableKit.IsArray(middlewareTable), "InboundMiddleware takes array, got dictionary.")

	self._outboundMiddleware = middlewareTable
end

--[=[
	Fires the bridge locally, which can then be recieved from the server along with packet data sent along.

	@within ClientBridge
	@param content any
]=]
function clientBridgePrototype:Fire(content: any)
	Output.fatalAssert(tostring(self) == "ClientBridge", "Fire called with . instead of :")

	if self._outboundMiddleware ~= nil then
		local result = content

		-- Loop through the middleware functions- raise a silent log if any of them return nil for debugging.
		for _, middlewareFunction: (object: Types.Content) -> any in self._outboundMiddleware do
			local returned = middlewareFunction(result)
			if typeof(returned) ~= "table" then
				Output.silent(
					string.format(
						"Inbound middleware on bridge %* did not return a table; ignoring the return.",
						self._name
					)
				)
			else
				result = returned
			end
		end

		if self.Logging then
			Output.log(`{debug.info(2, "s")}:{debug.info(2, "l")}`)
			local logOutput = string.format(
				Constants.CLIENT_FIRE_LOG,
				self._name,
				tostringData(result),
				RemotePacketSizeCounter.GetDataByteSize(result)
			)
			Output.log(logOutput)
		end

		ClientProcess.addToQueue(self._identifier, result)
	else
		if self.Logging then
			Output.log(`{debug.info(2, "s")}:{debug.info(2, "l")}`)
			local logOutput = string.format(
				Constants.CLIENT_FIRE_LOG,
				self._name,
				tostringData(content),
				RemotePacketSizeCounter.GetDataByteSize(content)
			)
			Output.log(logOutput)
		end

		ClientProcess.addToQueue(self._identifier, content)
	end
end

--[=[
	Connects the bridge to any events recieved from the server, this is when inbound middleware is ran. This shares identical behavior with [RemoteEvent.OnServerEvent:Connect].
	
	@within ClientBridge
	@param callback (content: Types.Content) -> ()
	@return RBXScriptConnection
]=]
function clientBridgePrototype:Connect(callback: (content: Types.Content) -> (), name: string?)
	Output.fatalAssert(tostring(self) == "ClientBridge", "connect called with . instead of :")
	Output.typecheck("function", "Connect", "callback", callback)

	local line = debug.info(2, "l")
	local scriptName = debug.info(2, "s")

	return ClientConnection(self._identifier, function(content)
		if typeof(content) == "table" then
			if (content :: {})[1] == ClientIdentifiers.ref("REQUEST", 3, false) then
				return
			end
		end

		if self._inboundMiddleware ~= nil then
			local result = content

			-- Loop through the middleware functions- raise a silent log if any of them return nil for debugging.
			for _, middlewareFunction: (object: any) -> any in self._inboundMiddleware do
				local returned = middlewareFunction(result)
				if typeof(returned) ~= "table" then
					Output.silent(
						string.format(
							"Inbound middleware on bridge %* did not return a table; ignoring the return.",
							self._name
						)
					)
				else
					result = returned
				end
			end

			if self.Logging then
				local logOutput = string.format(
					Constants.CLIENT_CONNECT_LOG,
					name or self._name,
					tostringData(result),
					RemotePacketSizeCounter.GetDataByteSize(result),
					scriptName,
					line
				)
				Output.log(logOutput)
			end

			if name then
				debug.profilebegin(name)
			end

			callback(result)

			if name then
				debug.profileend()
			end
		else
			if self.Logging then
				local logOutput = string.format(
					Constants.CLIENT_CONNECT_LOG,
					name or self._name,
					tostringData(content),
					RemotePacketSizeCounter.GetDataByteSize(content),
					scriptName,
					line
				)
				Output.log(logOutput)
			end

			if name then
				debug.profilebegin(name)
			end

			callback(content)

			if name then
				debug.profileend()
			end
		end
	end)
end

--[=[
	Connects the bridge to any events recieved from the server, this is when inbound middleware is ran. This shares identical behavior with [RemoteEvent.OnServerEvent:Wait].
	
	@within ClientBridge
	@yields
	@return any
]=]
function clientBridgePrototype:Wait()
	Output.fatalAssert(tostring(self) == "ClientBridge", "Wait called with . instead of :")
	-- Again, very basic QoL implementation of :Wait()
	local thread = coroutine.running()
	self:Once(function(content)
		task.spawn(thread, content)
	end)
	return coroutine.yield()
end

--[=[
	Invokes the server, then returns a value afterwards. This function yields the thread until content is recieved.
	
	@yields
	@within ClientBridge
	@param content any
	@return any
]=]
function clientBridgePrototype:InvokeServerAsync(content: any)
	Output.fatalAssert(tostring(self) == "ClientBridge", "InvokeServerAsync called with . instead of :")

	local id = NetworkUtils.FromHex(NetworkUtils.CreateUUID())

	self:Fire({ ClientIdentifiers.ref("REQUEST", 3, false), id, content })

	local thread = coroutine.running()
	local connection
	connection = ClientProcess.connect(self._identifier, function(reply)
		if typeof(reply) ~= "table" then
			return
		end
		if (reply :: {})[1] == ClientIdentifiers.ref("REQUEST", 3, false) and (reply :: {})[2] == id then
			connection()
			task.spawn(thread, (reply :: {})[3])
		end
	end)
	return coroutine.yield()
end

--[=[
	Connects the bridge to any events recieved from the server, this is when inbound middleware is ran. This shares identical behavior with [clientBridgePrototype:Connect] with the difference being that the event instantly disconnects on recieved.
	
	@within ClientBridge
	@param func (content: Types.Content) -> ()
	@return RBXScriptConnection
]=]
function clientBridgePrototype:Once(func: (content: Types.Content) -> ())
	Output.fatalAssert(tostring(self) == "ClientBridge", "Once called with . instead of :")
	-- Instantly disconnects. Very basic QoL implementation
	local connection
	connection = self:Connect(function(content)
		connection:Disconnect()
		func(content)
	end)

	return connection
end

--[=[
	Destroys the bridge it was called on.
	@within ClientBridge
]=]
function clientBridgePrototype:Destroy()
	Output.fatalAssert(tostring(self) == "ClientBridge", "Destroy called with . instead of :")
	-- Don't actually do any logic here- remember that ClientBridges are really just listening objects that let the end user communicate.
	table.clear(self)
	setmetatable(self, nil)
end

return function(name: string)
	local self = setmetatable({
		Logging = false,

		_identifier = ClientIdentifiers.ref(name, 3, true),
		_name = name,

		_inboundMiddleware = {},
		_outboundMiddleware = {},
	}, CLASS_METATABLE)

	-- Identifiers can be created by the end user too, so we have to tell BridgeNet2 that it's a bridge, not an identifier.
	ClientProcess.registerBridge(self._identifier)

	return self
end


							--Server:
							--!strict
local Types = require(script.Parent.Types)
local isEditMode = require(script.Parent.Utilities.isEditMode)
local PlayerContainers = require(script.PlayerContainers)
local ServerBridge = require(script.ServerBridge)
local ServerIdentifiers = require(script.ServerIdentifiers)
local ServerProcess = require(script.ServerProcess)

local activeBridges = {}

local Server = {}

function Server.start()
	if isEditMode then
		return
	end

	ServerIdentifiers.start()
	ServerProcess.start()
end

function Server.makeBridge(name: string)
	if activeBridges[name] then
		return activeBridges[name]
	else
		local bridge = ServerBridge(name)

		activeBridges[name] = bridge

		return bridge
	end
end

function Server.ser(identifierName: string): Types.Identifier?
	return ServerIdentifiers.ser(identifierName)
end

function Server.deser(compressedIdentifier: string): Types.Identifier?
	return ServerIdentifiers.deser(compressedIdentifier)
end

function Server.makeIdentifier(name: string)
	return ServerIdentifiers.ref(name)
end

function Server.playerContainers()
	return PlayerContainers
end

function Server.invalidPlayerhandler(func)
	ServerProcess.setInvalidPlayerFunction(func)
end

return Server


							--ServerBridge:
							--!strict
local Constants = require(script.Parent.Parent.Constants)
local RemotePacketSizeCounter = require(script.Parent.Parent.Parent.RemotePacketSizeCounter)
local ServerProcess = require(script.Parent.ServerProcess)
local TableKit = require(script.Parent.Parent.Parent.TableKit)
local Types = require(script.Parent.Parent.Types)
local Output = require(script.Parent.Parent.Utilities.Output)
local tostringData = require(script.Parent.Parent.Utilities.tostringData)
local PlayerContainers = require(script.Parent.PlayerContainers)
local ServerConnection = require(script.Parent.ServerConnection)
local ServerIdentifiers = require(script.Parent.ServerIdentifiers)

type TOptionalCallback<T> = (() -> T) | (() -> nil) | (() -> ())

--[=[
	This class handles the server-sided interface of BridgeNet2.

	@class ServerBridge
]=]
local serverBridgePrototype = {}

--[=[
	Sets a function that runs when the server is invoked by the client, should return some values.

	@within ServerBridge
	@prop OnServerInvoke (player: Player, content: Types.Content?) -> ...any
]=]

local CLASS_METATABLE = { __index = serverBridgePrototype }

function CLASS_METATABLE:__tostring()
	return "ServerBridge"
end

--[=[
	Sets some middleware to run when a bridge is fired from the client. 

	@within ServerBridge
	@param middlewareTable {(player: Player, content: Types.Content) -> any}
]=]
function serverBridgePrototype:InboundMiddleware(middlewareTable: { (player: Player, content: Types.Content) -> any })
	Output.fatalAssert(tostring(self) == "ServerBridge", "InboundMiddleware called with . instead of :")
	self._inboundMiddleware = middlewareTable
end

--[=[
	Sets some middleware to run when a bridge is fired from the backend server.

	@within ServerBridge
	@param middlewareTable {(target: Types.PlayerContainer, content: Types.Content) -> any}
]=]
function serverBridgePrototype:OutboundMiddleware(
	middlewareTable: { (target: Types.PlayerContainer, content: Types.Content) -> any }
)
	Output.fatalAssert(tostring(self) == "ServerBridge", "OutboundMiddleware called with . instead of :")
	self._outboundMiddleware = middlewareTable
end

--[=[
	Connects the bridge to any events recieved from the client, this is when inbound middleware is ran. This shares identical behavior with [RemoteEvent.OnClientEvent].

	@within ServerBridge
	@param callback (player: Player, content: Types.Content) -> nil
	@return RBXScriptConnection
]=]
function serverBridgePrototype:Connect(callback: (player: Player, content: Types.Content) -> nil, name: string?)
	Output.fatalAssert(tostring(self) == "ServerBridge", "Connect called with . instead of :")
	Output.typecheck("function", "Connect", "callback", callback)

	local line = debug.info(2, "l")
	local scriptName = debug.info(2, "s")

	return ServerConnection(self._identifier, function(player, content)
		if typeof(content) == "table" then
			if (content :: {})[1] == ServerIdentifiers.ref("REQUEST") then
				return
			end
		end

		if self.RateLimitActive then
			-- get the current second
			local thisSecond = math.round(os.clock() - os.clock() % 1)

			if self._rateMap[player] ~= nil then
				local lastSecond = self._rateMap[player][1] or 0

				if lastSecond ~= thisSecond then
					self._rateMap[player][2] = 0

					self._rateMap[player][1] = thisSecond
				else
					self._rateMap[player][2] += 1
				end
			else
				self._rateMap[player] = { thisSecond, 1 }
			end

			if self._rateMap[player][2] >= self._maxRate then
				if not self._overflowFunction(player) then
					return
				end
			end
		end

		if self._inboundMiddleware ~= nil then
			local result = content

			-- Loop through the middleware functions- raise a silent log if any of them don't return a table for debugging.
			for _, middlewareFunction: (player: Player, content: Types.Content) -> any in self._inboundMiddleware do
				local returned = middlewareFunction(player, result)
				if typeof(returned) ~= "table" then
					Output.silent(
						string.format(
							"Inbound middleware on bridge %* did not return a table; ignoring the return.",
							self._name
						)
					)
				else
					result = returned
				end
			end

			if self.Logging then
				local logOutput = string.format(
					Constants.SERVER_CONNECT_LOG,
					name or self._name,
					player.Name,
					tostringData(content),
					RemotePacketSizeCounter.GetDataByteSize(content),
					scriptName,
					line
				)
				Output.log(logOutput)
			end

			if name then
				debug.profilebegin(name)
			end
			callback(player, result)
			if name then
				debug.profileend()
			end
		else
			if self.Logging then
				local logOutput = string.format(
					Constants.SERVER_CONNECT_LOG,
					name or self._name,
					player.Name,
					tostringData(content),
					RemotePacketSizeCounter.GetDataByteSize(content),
					scriptName,
					line
				)
				Output.log(logOutput)
			end

			if name then
				debug.profilebegin(name)
			end
			callback(player, content)
			if name then
				debug.profileend()
			end
		end
	end)
end

--[=[
	Sets the rate limit, which makes a bridge only allow `invokesPerSecond` invoke per second.

	@within ServerBridge
	@param invokesPerSecond number -- The maximum invokes per second allowed from the client
	@param overflowFunction (player: Player) -> nil -- The function to run if the client runs over the maximum amount of request
]=]
function serverBridgePrototype:RateLimit(invokesPerSecond: number, overflowFunction: (player: Player) -> nil)
	Output.fatalAssert(tostring(self) == "ServerBridge", "RateLimit called with . instead of :")
	self.RateLimitActive = true
	self._overflowFunction = overflowFunction
	self._maxRate = invokesPerSecond
end

--[=[
	Disables the set rate limit for the bridge.
	@within ServerBridge
]=]
function serverBridgePrototype:DisableRateLimit()
	Output.fatalAssert(tostring(self) == "ServerBridge", "DisableRateLimit called with . instead of :")
	self.RateLimitActive = false
end

--[=[
	Connects the bridge to any events recieved from the client, this is when inbound middleware is ran. This shares identical behavior with [RemoteEvent.OnClientEvent].

	@within ServerBridge
	@yields
	@return Player, any
]=]
function serverBridgePrototype:Wait()
	Output.fatalAssert(tostring(self) == "ServerBridge", "Wait called with . instead of :")
	local thread = coroutine.running()
	self:Connect(function(player, content)
		task.spawn(thread, player, content)
	end)
	return coroutine.yield()
end

--[=[
	Connects the bridge to any events recieved from the client, this is when inbound middleware is ran. This shares identical behavior with [ClientBridge:Connect] with the difference being that the event instantly disconnects on recieved.

	@within ServerBridge
	@param callback (player: Player, content: Types.Content) -> ()
	@return RBXScriptConnection
]=]
function serverBridgePrototype:Once(callback: (player: Player, content: Types.Content) -> ())
	Output.fatalAssert(tostring(self) == "ServerBridge", "Once called with . instead of :")
	Output.typecheck("function", "Once", "callback", callback)

	local connection
	connection = self:Connect(function(player, content)
		connection:Disconnect()
		callback(player, content)
	end)
	return connection
end

--[=[
	Fires the bridge from the backend server, which can then be recieved from the client along with packet data sent along.

	@within ServerBridge
	@param target Player | Types.PlayerContainer -- The player which the event should be fired to
	@param content any -- The packet data which should be sent along
]=]
function serverBridgePrototype:Fire(target: Player | Types.PlayerContainer, content: any)
	Output.fatalAssert(tostring(self) == "ServerBridge", "Fire called with . instead of :")
	local playerContainer: Types.PlayerContainer

	-- if it's a single player, then create a player container w/ type "single"
	if typeof(target) == "Instance" then
		if target:IsA("Player") then
			playerContainer = PlayerContainers.Single(target)
		else
			Output.fatal("non-player instance passed into :Fire()")
		end
	else
		if typeof(target) == "nil" then
			Output.fatal("target parameter passed into ServerBridge:Fire() is nil")
		end
		Output.typecheck("table", "Fire", "target", target)
		playerContainer = target
	end

	if self._outboundMiddleware ~= nil then
		local result = content

		-- Loop through the middleware functions- raise a silent log if any of them return nil for debugging.
		for _, middlewareFunction: (object: any) -> any in self._outboundMiddleware do
			local returned = middlewareFunction(result)
			if typeof(returned) ~= "table" then
				Output.silent(
					string.format(
						"Outbound middleware on bridge %* did not return a table; ignoring the return.",
						self._name
					)
				)
			else
				result = returned
			end
		end

		if self.Logging then
			Output.log(`{debug.info(2, "s")}:{debug.info(2, "l")}`)
			local logOutput = string.format(
				Constants.SERVER_FIRE_LOG,
				self._name,
				if playerContainer.kind == "all"
					then "{all}"
					elseif playerContainer.kind == "single" then playerContainer.value.Name
					else TableKit.ToArrayString(playerContainer.value),
				tostringData(result),
				RemotePacketSizeCounter.GetDataByteSize(result)
			)
			Output.log(logOutput)
		end

		ServerProcess.addToQueue(playerContainer, self._identifier, result)
	else
		if self.Logging then
			Output.log(`{debug.info(2, "s")}:{debug.info(2, "l")}`)
			local logOutput = string.format(
				Constants.SERVER_FIRE_LOG,
				self._name,
				if playerContainer.kind == "all"
					then "{all}"
					elseif playerContainer.kind == "single" then playerContainer.value.Name
					else TableKit.ToArrayString(playerContainer.value),
				tostringData(content),
				RemotePacketSizeCounter.GetDataByteSize(content)
			)
			Output.log(logOutput)
		end

		ServerProcess.addToQueue(playerContainer, self._identifier, content)
	end
end

return function(name: string)
	local self = setmetatable({
		-- Since this is the server, ReferenceIdentifier will not yield
		_identifier = ServerIdentifiers.ref(name),

		-- Middleware
		_outboundMiddleware = nil,
		_inboundMiddleware = nil,

		_name = name,

		Logging = false,
		OnServerInvoke = function() end :: (player: Player, content: Types.Content?) -> ...any,

		-- Rate limiting
		RateLimitActive = false,
		_maxRate = 500,
		_rateMap = {} :: { [Player]: { number } },
		_overflowFunction = function()
			return false
		end,
	}, CLASS_METATABLE)

	ServerProcess.registerBridge(self._identifier)

	ServerProcess.connect(self._identifier, function(player, content)
		if typeof(content) ~= "table" then
			return
		end

		if self.OnServerInvoke ~= nil then
			if (content :: {})[1] == ServerIdentifiers.ref("REQUEST") then
				local reply = self.OnServerInvoke(player, (content :: {})[3])

				self:Fire(player, { ServerIdentifiers.ref("REQUEST"), (content :: {})[2], reply })
			end
		end
	end)

	return self
end

										--MouseBridge Server:
										local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BridgeNet2 = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))

local MouseData = require(ReplicatedStorage.Modules.Ability.MouseData)
local MouseBridge = BridgeNet2.ServerBridge("MousePosition") -- listen to same bridge

MouseBridge:Connect(function(player, mousePos)
	MouseData.Positions[player.UserId] = mousePos
end)

										--MouseBridge Client:
										local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local camera = workspace.CurrentCamera

local MouseData = require(ReplicatedStorage.Modules.Ability.MouseData)
local BridgeNet2 = require(ReplicatedStorage.Modules:WaitForChild("BridgeNet2"))
local MouseBridge = BridgeNet2.ClientBridge("MousePosition") -- make a bridge

-- Send mouse position every 0.2 seconds
task.spawn(function()
	while task.wait(0.05) do
		local mousePos = UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
		local result = workspace:Raycast(ray.Origin, ray.Direction * 1000)

		if result then
			MouseBridge:Fire(result.Position)
		end
	end
end)


										
							
							
