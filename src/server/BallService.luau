local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ChargeUtil = require(ReplicatedStorage.Shared.ChargeUtil)
local Config = require(ReplicatedStorage.Shared.Config)
local PassUtil = require(ReplicatedStorage.Shared.PassUtil)
local SoccerFieldUtil = require(ReplicatedStorage.Shared.SoccerFieldUtil)
local ArenaBoundsUtil = require(script.Parent.ArenaBoundsUtil)

local function buildHoldOffset(position: Vector3, rotationDegrees: Vector3?): CFrame
	if rotationDegrees then
		return CFrame.new(position)
			* CFrame.Angles(
				math.rad(rotationDegrees.X),
				math.rad(rotationDegrees.Y),
				math.rad(rotationDegrees.Z)
			)
	end

	return CFrame.new(position)
end

local BallService = {}
BallService._ballInstance = nil :: Instance?
BallService._ballRoot = nil :: BasePart?
BallService._hold = nil :: Weld?
BallService._carrier = nil :: Player?
BallService._carrierCharacter = nil :: Model?
BallService._holdUpdateConnection = nil :: RBXScriptConnection?
BallService._isLoose = false
BallService._pickupAvailableAt = 0
BallService._pickupConnections = {} :: { RBXScriptConnection }
BallService._pickupDebounce = {} :: { [number]: number }
BallService._pickupBlockedUntil = {} :: { [number]: number }
BallService._pickupHandler = nil :: ((Player) -> boolean)?
BallService._looseHighlight = nil :: Highlight?
BallService._looseArrow = nil :: BillboardGui?
BallService._looseLight = nil :: PointLight?
BallService._loosePulseConnection = nil :: RBXScriptConnection?
BallService._carrierArrow = nil :: BillboardGui?
BallService._carrierArrowCharacter = nil :: Model?
BallService._carrierArrowPulseConnection = nil :: RBXScriptConnection?
BallService._passInFlight = false
BallService._passTarget = nil :: Model?
BallService._passTargetUserId = nil :: number?
BallService._passConnection = nil :: RBXScriptConnection?
BallService._passCompleteHandler = nil :: ((Model) -> ())?
BallService._passEndedHandler = nil :: ((number?, Model?, boolean) -> ())?
BallService._passFlightStartedHandler = nil :: ((number?) -> ())?
BallService._passThrowerUserId = nil :: number?
BallService._passPending = nil :: {
	receiverCharacter: Model,
	receiverUserId: number?,
	throwerCharacter: Model,
	throwerUserId: number?,
	releaseAt: number,
}?
BallService._passArcStartPos = nil :: Vector3?
BallService._passStartTime = 0
BallService._passFlightDuration = 0
BallService._passReleaseToken = 0
BallService._passAimConnection = nil :: RBXScriptConnection?
BallService._boundaryConnection = nil :: RBXScriptConnection?

local function getBallTemplate(): Instance
	local template = ReplicatedStorage:FindFirstChild(Config.BALL_TEMPLATE_NAME)
	if not template then
		error(`Ball template "{Config.BALL_TEMPLATE_NAME}" not found in ReplicatedStorage`)
	end
	return template
end

local function getBallRoot(ball: Instance): BasePart?
	if ball:IsA("MeshPart") or ball:IsA("Part") then
		return ball
	end

	if ball:IsA("Model") then
		if ball.PrimaryPart and ball.PrimaryPart:IsA("BasePart") then
			return ball.PrimaryPart
		end

		local meshPart = ball:FindFirstChildWhichIsA("MeshPart", true)
		if meshPart then
			return meshPart
		end

		return ball:FindFirstChildWhichIsA("BasePart", true)
	end

	return nil
end

local function wrapBallClone(clone: Instance): (Instance, BasePart)
	if clone:IsA("MeshPart") or clone:IsA("Part") then
		local wrapper = Instance.new("Model")
		wrapper.Name = "GameBall"
		clone.Name = "BallMesh"
		clone.Parent = wrapper
		wrapper.PrimaryPart = clone
		return wrapper, clone
	end

	clone.Name = "GameBall"
	local root = getBallRoot(clone)
	if not root then
		error(`Ball "{Config.BALL_TEMPLATE_NAME}" must be a MeshPart, Part, or Model containing a mesh`)
	end

	if clone:IsA("Model") then
		clone.PrimaryPart = root
	end

	return clone, root
end

local function getRootToVisualCenter(ballInstance: Instance, ballRoot: BasePart): CFrame
	if ballInstance:IsA("Model") then
		local bboxCFrame = select(1, ballInstance:GetBoundingBox())
		return ballRoot.CFrame:ToObjectSpace(bboxCFrame)
	end

	return CFrame.new()
end

local function getAttachPart(character: Model): BasePart?
	return character:FindFirstChild("RightLowerArm") :: BasePart?
		or character:FindFirstChild("RightHand") :: BasePart?
		or character:FindFirstChild("Right Arm") :: BasePart?
		or character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function getHoldOffset(attachPart: BasePart, mode: string): CFrame
	if attachPart.Name == "RightLowerArm" then
		if mode == "run" then
			return buildHoldOffset(Config.BALL_HOLD_OFFSET_LOWER_ARM_RUN, Config.BALL_HOLD_LOWER_ARM_ROTATION_RUN)
		end
		if mode == "truck" then
			return buildHoldOffset(Config.BALL_HOLD_OFFSET_LOWER_ARM_TRUCK, Config.BALL_HOLD_LOWER_ARM_ROTATION_TRUCK)
		end
		return buildHoldOffset(Config.BALL_HOLD_OFFSET_LOWER_ARM, Config.BALL_HOLD_LOWER_ARM_ROTATION)
	end

	if attachPart.Name == "HumanoidRootPart" then
		return buildHoldOffset(Config.BALL_HOLD_OFFSET_HRP)
	end

	return buildHoldOffset(Config.BALL_HOLD_OFFSET_HAND)
end

local function getCarrierMoveBlend(character: Model): number
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return 0
	end

	local speed = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude
	return if speed > Config.RUN_MOVE_THRESHOLD then 1 else 0
end

local function setBallPhysics(ball: Instance, carried: boolean)
	local parts = {}
	if ball:IsA("BasePart") then
		table.insert(parts, ball)
	else
		for _, descendant in ball:GetDescendants() do
			if descendant:IsA("BasePart") then
				table.insert(parts, descendant)
			end
		end
	end

	for _, part in parts do
		part.Anchored = false
		part.CanTouch = true
		part.CanCollide = not carried
		part.Massless = carried
		if not carried then
			part.CustomPhysicalProperties = PhysicalProperties.new(0.7, Config.BALL_PHYSICS_FRICTION, Config.BALL_PHYSICS_ELASTICITY, 1, 1)
		end
	end
end

local function setPassFlightPhysics(ball: Instance)
	local parts = {}
	if ball:IsA("BasePart") then
		table.insert(parts, ball)
	else
		for _, descendant in ball:GetDescendants() do
			if descendant:IsA("BasePart") then
				table.insert(parts, descendant)
			end
		end
	end

	for _, part in parts do
		part.Anchored = true
		part.CanCollide = false
		part.Massless = false
		part.AssemblyLinearVelocity = Vector3.zero
		part.AssemblyAngularVelocity = Vector3.zero
	end
end

local function clearPassFlightAttributes(ballRoot: BasePart)
	ballRoot:SetAttribute("PassInFlight", nil)
	ballRoot:SetAttribute("PassStartPos", nil)
	ballRoot:SetAttribute("PassFlightStartTime", nil)
	ballRoot:SetAttribute("PassFlightDuration", nil)
	ballRoot:SetAttribute("PassReceiverName", nil)
	ballRoot:SetAttribute("PassReceiverUserId", nil)
end

local function setPassFlightAttributes(
	ballRoot: BasePart,
	startPos: Vector3,
	receiverCharacter: Model,
	receiverUserId: number?,
	flightDuration: number,
	startTime: number
)
	ballRoot:SetAttribute("PassInFlight", true)
	ballRoot:SetAttribute("PassStartPos", startPos)
	ballRoot:SetAttribute("PassFlightStartTime", startTime)
	ballRoot:SetAttribute("PassFlightDuration", flightDuration)
	ballRoot:SetAttribute("PassReceiverName", receiverCharacter.Name)
	ballRoot:SetAttribute("PassReceiverUserId", receiverUserId)
end

function BallService:init()
	self:_ensureBall()
	self._boundaryConnection = RunService.Heartbeat:Connect(function()
		self:_updatePassPendingRelease()
		self:_enforceArenaBounds()
		self:_tryProximityPickup()
	end)
end

function BallService:_updatePassPendingRelease()
	local pending = self._passPending
	if not pending or os.clock() < pending.releaseAt then
		return
	end

	self:_beginPassFlight()
end

function BallService:_snapBallToArenaFloor()
	if not self._ballRoot or not self._ballInstance then
		return
	end

	local position = self._ballRoot.Position
	local ballHalfHeight = self._ballRoot.Size.Y * 0.5
	local exclude: { Instance } = { self._ballInstance }
	local ray = SoccerFieldUtil.raycastArenaFloor(position + Vector3.new(0, 20, 0), 80, exclude)
	local newPos = if ray
		then Vector3.new(position.X, ray.Position.Y + ballHalfHeight, position.Z)
		else Vector3.new(position.X, (SoccerFieldUtil.getArenaFloorTopY() or position.Y) + ballHalfHeight, position.Z)

	self._ballInstance:PivotTo(CFrame.new(newPos))

	local velocity = self._ballRoot.AssemblyLinearVelocity
	self._ballRoot.AssemblyLinearVelocity = Vector3.new(velocity.X, math.max(velocity.Y, 0), velocity.Z)
end

function BallService:enforceBallFloor()
	if not self._ballRoot or not self._ballInstance then
		return
	end

	if self._passInFlight or self._hold or self._carrier or self._carrierCharacter then
		return
	end

	local floorTopY = SoccerFieldUtil.getArenaFloorTopY()
	if not floorTopY then
		return
	end

	local position = self._ballRoot.Position
	local ballHalfHeight = self._ballRoot.Size.Y * 0.5
	local fallThroughY = floorTopY - Config.FLOOR_SAFETY_BALL_FALL_THROUGH

	local ray = SoccerFieldUtil.raycastArenaFloor(position + Vector3.new(0, 4, 0), 30, { self._ballInstance })
	if ray then
		local restingY = ray.Position.Y + ballHalfHeight
		if position.Y >= restingY - 2 and position.Y >= fallThroughY then
			return
		end
	end

	if position.Y >= fallThroughY then
		return
	end

	self:_snapBallToArenaFloor()
end

function BallService:_recoverBallInsideBounds(position: Vector3, velocity: Vector3?): Vector3
	local clamped = ArenaBoundsUtil.clampPosition(position)
	if not self._ballInstance or not self._ballRoot then
		return clamped
	end

	self._ballInstance:PivotTo(CFrame.new(clamped))

	if velocity then
		local bounds = ArenaBoundsUtil.getPlayBounds()
		local newVelocity = velocity
		if position.X < bounds.min.X or position.X > bounds.max.X then
			newVelocity = Vector3.new(-newVelocity.X * 0.35, newVelocity.Y, newVelocity.Z)
		end
		if position.Z < bounds.min.Z or position.Z > bounds.max.Z then
			newVelocity = Vector3.new(newVelocity.X, newVelocity.Y, -newVelocity.Z * 0.35)
		end
		if position.Y < bounds.min.Y or position.Y > bounds.max.Y then
			newVelocity = Vector3.new(newVelocity.X, -newVelocity.Y * 0.35, newVelocity.Z)
		end
		self._ballRoot.AssemblyLinearVelocity = newVelocity
		self._ballRoot.AssemblyAngularVelocity = self._ballRoot.AssemblyAngularVelocity * 0.5
	end

	return clamped
end

function BallService:_enforceArenaBounds()
	if not self._ballRoot or not self._ballInstance then
		return
	end

	if self._carrier or self._carrierCharacter then
		return
	end

	if not self._isLoose and not self._passInFlight then
		return
	end

	local position = self._ballRoot.Position
	if ArenaBoundsUtil.isInside(position) then
		return
	end

	if self._passInFlight then
		self:_endPassFlight(false, nil)
		self:_recoverBallInsideBounds(position, nil)
		self:releaseLoose()
		return
	end

	self:_recoverBallInsideBounds(position, self._ballRoot.AssemblyLinearVelocity)
end

function BallService:_ensureBall()
	if self._ballInstance and self._ballInstance.Parent then
		return
	end

	local existingBall = Workspace:FindFirstChild("GameBall")
	if existingBall then
		existingBall:Destroy()
	end

	local template = getBallTemplate()
	self._ballInstance, self._ballRoot = wrapBallClone(template:Clone())
	setBallPhysics(self._ballInstance, false)
	self._ballInstance.Parent = Workspace
end

function BallService:getBall(): BasePart?
	return self._ballRoot
end

function BallService:isBallPart(part: BasePart): boolean
	if not self._ballInstance or not self._ballRoot then
		return false
	end

	if part == self._ballRoot then
		return true
	end

	return part:IsDescendantOf(self._ballInstance)
end

function BallService:getCarrier(): Player?
	return self._carrier
end

function BallService:getCarrierCharacter(): Model?
	return self._carrierCharacter
end

function BallService:isLoose(): boolean
	return self._isLoose
end

function BallService:canPickupLooseBall(): boolean
	return self._isLoose and os.clock() >= self._pickupAvailableAt
end

function BallService:_stopLoosePulse()
	if self._loosePulseConnection then
		self._loosePulseConnection:Disconnect()
		self._loosePulseConnection = nil
	end
end

function BallService:_clearLooseVisuals()
	self:_stopLoosePulse()

	if self._looseHighlight then
		self._looseHighlight:Destroy()
		self._looseHighlight = nil
	end

	if self._looseArrow then
		self._looseArrow:Destroy()
		self._looseArrow = nil
	end

	if self._looseLight then
		self._looseLight:Destroy()
		self._looseLight = nil
	end
end

function BallService:_startLoosePulse()
	self:_stopLoosePulse()

	local pulseStart = os.clock()
	self._loosePulseConnection = RunService.Heartbeat:Connect(function()
		if not self._isLoose then
			return
		end

		local elapsed = os.clock() - pulseStart
		local pulse = (math.sin(elapsed * 3) + 1) * 0.5

		if self._looseHighlight then
			self._looseHighlight.FillTransparency = 0.6 + pulse * 0.2
			self._looseHighlight.OutlineTransparency = 0.45 + pulse * 0.25
		end

		if self._looseArrow then
			local bob = math.sin(elapsed * 4) * 0.4
			self._looseArrow.StudsOffset = Config.BALL_LOOSE_ARROW_OFFSET + Vector3.new(0, bob, 0)
		end

		if self._looseLight then
			self._looseLight.Brightness = 0.45 + pulse * 0.35
			self._looseLight.Range = 6 + pulse * 2
		end
	end)
end

function BallService:_syncLooseVisuals()
	self:_clearLooseVisuals()

	if not self._isLoose or not self._ballInstance or not self._ballRoot then
		return
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "LooseBallGlow"
	highlight.Adornee = self._ballRoot
	highlight.FillColor = Config.BALL_LOOSE_GLOW_COLOR
	highlight.OutlineColor = Config.BALL_LOOSE_GLOW_COLOR
	highlight.FillTransparency = 0.65
	highlight.OutlineTransparency = 0.5
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Parent = self._ballInstance
	self._looseHighlight = highlight

	local arrowBillboard = Instance.new("BillboardGui")
	arrowBillboard.Name = "LooseBallArrow"
	arrowBillboard.Adornee = self._ballRoot
	arrowBillboard.AlwaysOnTop = true
	arrowBillboard.Size = UDim2.fromOffset(72, 72)
	arrowBillboard.StudsOffset = Config.BALL_LOOSE_ARROW_OFFSET
	arrowBillboard.LightInfluence = 0
	arrowBillboard.Parent = self._ballInstance
	self._looseArrow = arrowBillboard

	local arrow = Instance.new("TextLabel")
	arrow.Name = "Arrow"
	arrow.BackgroundTransparency = 1
	arrow.Size = UDim2.fromScale(1, 1)
	arrow.Font = Enum.Font.GothamBlack
	arrow.Text = "▼"
	arrow.TextColor3 = Config.BALL_LOOSE_GLOW_COLOR
	arrow.TextScaled = true
	arrow.TextStrokeColor3 = Color3.fromRGB(20, 20, 20)
	arrow.TextStrokeTransparency = 0.2
	arrow.ZIndex = 2
	arrow.Parent = arrowBillboard

	local light = Instance.new("PointLight")
	light.Name = "LooseBallLight"
	light.Color = Config.BALL_LOOSE_GLOW_COLOR
	light.Brightness = 0.6
	light.Range = 7
	light.Parent = self._ballRoot
	self._looseLight = light

	self:_startLoosePulse()
end

function BallService:_clearCarrierArrow()
	if self._carrierArrowPulseConnection then
		self._carrierArrowPulseConnection:Disconnect()
		self._carrierArrowPulseConnection = nil
	end

	if self._carrierArrow then
		self._carrierArrow:Destroy()
		self._carrierArrow = nil
	end

	self._carrierArrowCharacter = nil
end

function BallService:_syncCarrierArrow(character: Model)
	self:_clearCarrierArrow()

	local adornee = character:FindFirstChild("Head") :: BasePart?
		or character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not adornee then
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "CarrierArrow"
	billboard.Adornee = adornee
	billboard.AlwaysOnTop = true
	billboard.Size = UDim2.fromOffset(64, 64)
	billboard.StudsOffset = Config.CARRIER_ARROW_OFFSET
	billboard.LightInfluence = 0
	billboard.Parent = character
	self._carrierArrow = billboard
	self._carrierArrowCharacter = character

	local arrow = Instance.new("TextLabel")
	arrow.Name = "Arrow"
	arrow.BackgroundTransparency = 1
	arrow.Size = UDim2.fromScale(1, 1)
	arrow.Font = Enum.Font.GothamBlack
	arrow.Text = "▼"
	arrow.TextColor3 = Config.CARRIER_ARROW_COLOR
	arrow.TextScaled = true
	arrow.TextStrokeColor3 = Color3.fromRGB(20, 20, 20)
	arrow.TextStrokeTransparency = 0.2
	arrow.ZIndex = 2
	arrow.Parent = billboard

	local pulseStart = os.clock()
	self._carrierArrowPulseConnection = RunService.Heartbeat:Connect(function()
		if not self._carrierArrow or self._carrierArrowCharacter ~= character then
			return
		end

		local bob = math.sin((os.clock() - pulseStart) * 4) * 0.35
		billboard.StudsOffset = Config.CARRIER_ARROW_OFFSET + Vector3.new(0, bob, 0)
	end)
end

function BallService:_setLooseAttribute(isLoose: boolean)
	if self._ballRoot then
		self._ballRoot:SetAttribute("IsLoose", if isLoose then true else nil)
	end

	if self._ballInstance and self._ballInstance ~= self._ballRoot then
		self._ballInstance:SetAttribute("IsLoose", if isLoose then true else nil)
	end

	self:_syncLooseVisuals()
end

function BallService:setPickupHandler(handler: (Player) -> boolean)
	self._pickupHandler = handler
end

local function getPlayerFromPart(part: BasePart): Player?
	local model = part:FindFirstAncestorOfClass("Model")
	if not model then
		return nil
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end

	return Players:GetPlayerFromCharacter(model)
end

local function isCharacterRagdolled(character: Model): boolean
	return character:GetAttribute("TackleBallRagdollActive") == true
end

function BallService:_canPlayerAttemptPickup(player: Player): boolean
	local character = player.Character
	if not character or isCharacterRagdolled(character) then
		return false
	end

	local blockedUntil = self._pickupBlockedUntil[player.UserId]
	return not blockedUntil or os.clock() >= blockedUntil
end

function BallService:_unbindPickupTouches()
	for _, connection in self._pickupConnections do
		connection:Disconnect()
	end
	table.clear(self._pickupConnections)
end

function BallService:_tryPickupPlayer(player: Player)
	if self._passInFlight then
		return
	end

	if not self._isLoose or not self._pickupHandler then
		return
	end

	if os.clock() < self._pickupAvailableAt then
		return
	end

	if not self:_canPlayerAttemptPickup(player) then
		return
	end

	local lastAttempt = self._pickupDebounce[player.UserId]
	if lastAttempt and os.clock() - lastAttempt < Config.BALL_PICKUP_DEBOUNCE then
		return
	end

	self._pickupDebounce[player.UserId] = os.clock()

	if self._pickupHandler(player) then
		self._isLoose = false
		self:_setLooseAttribute(false)
		self:_unbindPickupTouches()
	end
end

function BallService:_tryProximityPickup()
	if not self._isLoose or not self._ballRoot then
		return
	end

	local ballPosition = self._ballRoot.Position
	local baseRadius = Config.BALL_PICKUP_RADIUS
	local leadTime = Config.BALL_PICKUP_LEAD_TIME
	local verticalTolerance = Config.BALL_PICKUP_VERTICAL_TOLERANCE
	local pickupParts = { "HumanoidRootPart", "LowerTorso", "UpperTorso", "Head" }

	local function canPickupFromPosition(playerPosition: Vector3, horizontalSpeed: number): boolean
		local pickupRadius = baseRadius + horizontalSpeed * Config.BALL_PICKUP_SPEED_SCALE
		local delta = playerPosition - ballPosition
		if math.abs(delta.Y) > verticalTolerance then
			return false
		end

		local flatDelta = Vector3.new(delta.X, 0, delta.Z)
		return flatDelta.Magnitude <= pickupRadius
	end

	for _, player in Players:GetPlayers() do
		local character = player.Character
		if not character then
			continue
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			continue
		end

		if not self:_canPlayerAttemptPickup(player) then
			continue
		end

		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			continue
		end

		local velocity = root.AssemblyLinearVelocity
		local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
		local leadOffset = Vector3.new(velocity.X, 0, velocity.Z) * leadTime

		local inRange = false
		for _, partName in pickupParts do
			local part = character:FindFirstChild(partName) :: BasePart?
			if not part then
				continue
			end

			if canPickupFromPosition(part.Position, horizontalSpeed)
				or canPickupFromPosition(part.Position + leadOffset, horizontalSpeed)
			then
				inRange = true
				break
			end
		end

		if inRange then
			self:_tryPickupPlayer(player)
			if not self._isLoose then
				return
			end
		end
	end
end

function BallService:_tryPickupFromTouch(hit: BasePart)
	local player = getPlayerFromPart(hit)
	if not player then
		return
	end

	self:_tryPickupPlayer(player)
end

function BallService:_bindPickupTouches()
	self:_unbindPickupTouches()

	if not self._ballInstance then
		return
	end

	local function bindPart(part: BasePart)
		part.CanTouch = true
		local connection = part.Touched:Connect(function(hit)
			if hit:IsA("BasePart") then
				self:_tryPickupFromTouch(hit)
			end
		end)
		table.insert(self._pickupConnections, connection)
	end

	if self._ballInstance:IsA("BasePart") then
		bindPart(self._ballInstance)
	else
		for _, descendant in self._ballInstance:GetDescendants() do
			if descendant:IsA("BasePart") then
				bindPart(descendant)
			end
		end
	end
end

function BallService:_stopHoldUpdate()
	if self._holdUpdateConnection then
		self._holdUpdateConnection:Disconnect()
		self._holdUpdateConnection = nil
	end
end

function BallService:_updateHoldOffset()
	if not self._hold or not self._carrierCharacter then
		return
	end

	local attachPart = self._hold.Part0
	if not attachPart or attachPart.Name ~= "RightLowerArm" then
		return
	end

	local blend = getCarrierMoveBlend(self._carrierCharacter)
	local isTruck = self._carrierCharacter:GetAttribute("TruckTuckActive") == true
	local idleOffset = getHoldOffset(attachPart, "idle")
	local runOffset = getHoldOffset(attachPart, "run")
	local truckOffset = getHoldOffset(attachPart, "truck")

	if isTruck then
		self._hold.C0 = truckOffset
	elseif blend > 0 then
		self._hold.C0 = idleOffset:Lerp(runOffset, blend)
	else
		self._hold.C0 = idleOffset
	end
end

function BallService:_startHoldUpdate()
	self:_stopHoldUpdate()
	self._holdUpdateConnection = RunService.Heartbeat:Connect(function()
		self:_updateHoldOffset()
	end)
end

function BallService:_clearHold()
	self:_stopHoldUpdate()
	self:_clearCarrierArrow()
	if self._hold then
		self._hold:Destroy()
		self._hold = nil
	end
end

function BallService:_setBallOwnershipForHold(networkOwner: Player?)
	if not self._ballRoot then
		return
	end

	pcall(function()
		if networkOwner then
			self._ballRoot:SetNetworkOwner(networkOwner)
		else
			self._ballRoot:SetNetworkOwner(nil)
		end
	end)
end

function BallService:_detachBallFromCharacter(character: Model?)
	self:_clearHold()

	if not self._ballRoot then
		return
	end

	local ballRoot = self._ballRoot

	local function destroyBallHoldWeld(weld: Instance)
		if not weld:IsA("Weld") or weld.Name ~= "BallHold" then
			return
		end

		if weld.Part0 == ballRoot or weld.Part1 == ballRoot then
			weld:Destroy()
		end
	end

	for _, child in ballRoot:GetChildren() do
		destroyBallHoldWeld(child)
	end

	if character then
		for _, descendant in character:GetDescendants() do
			destroyBallHoldWeld(descendant)
		end
	end
end

function BallService:_attachToCharacter(character: Model, networkOwner: Player?)
	local attachPart = getAttachPart(character)
	if not attachPart or not self._ballInstance or not self._ballRoot then
		warn("BallService: could not attach ball, missing attach part or ball")
		return
	end

	self:_ensureBall()
	self:_clearHold()
	setBallPhysics(self._ballInstance, true)

	local holdOffset = getHoldOffset(attachPart, "idle")
	local rootToVisualCenter = getRootToVisualCenter(self._ballInstance, self._ballRoot)
	local targetRootCFrame = attachPart.CFrame * holdOffset * rootToVisualCenter:Inverse()

	self._ballInstance:PivotTo(targetRootCFrame)

	local weld = Instance.new("Weld")
	weld.Name = "BallHold"
	weld.Part0 = attachPart
	weld.Part1 = self._ballRoot
	weld.C0 = holdOffset
	weld.C1 = rootToVisualCenter
	weld.Parent = self._ballRoot

	self._hold = weld
	self._carrierCharacter = character
	self:_startHoldUpdate()
	self:_syncCarrierArrow(character)
	self:_setBallOwnershipForHold(networkOwner)
end

function BallService:resetPassState()
	self:_cancelPassPending()
	if self._passInFlight then
		self:_endPassFlight(false, nil)
	end
end

function BallService:_isBallHeldByCharacter(character: Model): boolean
	if not self._hold or not self._ballRoot then
		return false
	end

	local attachPart = self._hold.Part0
	if not attachPart or not attachPart:IsDescendantOf(character) then
		return false
	end

	return self._hold.Part1 == self._ballRoot or self._hold.Part0 == self._ballRoot
end

function BallService:setCarrierCharacter(character: Model?, networkOwner: Player?)
	if self._passInFlight then
		if character then
			return
		end
		self:_endPassFlight(false, nil)
	end

	if self._passPending and character then
		local throwerUserId = self._passPending.throwerUserId
		if self._passPending.throwerCharacter == character then
			self._carrierCharacter = character
			return
		end
		if throwerUserId then
			local thrower = Players:GetPlayerByUserId(throwerUserId)
			if thrower and thrower.Character == character then
				self._carrierCharacter = character
				return
			end
		end
		self:_cancelPassPending()
	end

	if self._passPending and not character then
		self:_cancelPassPending()
	end

	self:_stopPassFlight()
	self:_clearHold()
	self._isLoose = false
	self:_setLooseAttribute(false)
	self:_unbindPickupTouches()
	self._carrier = nil
	self._carrierCharacter = character

	if not character then
		if self._ballInstance then
			setBallPhysics(self._ballInstance, false)
		end
		return
	end

	local expectedCharacter = character
	if expectedCharacter:FindFirstChild("HumanoidRootPart") then
		self:_attachToCharacter(expectedCharacter, networkOwner)
		return
	end

	task.spawn(function()
		expectedCharacter:WaitForChild("HumanoidRootPart", 10)

		if self._carrierCharacter ~= expectedCharacter then
			return
		end

		self:_attachToCharacter(expectedCharacter, networkOwner)
	end)
end

function BallService:setCarrier(player: Player?)
	if self._passInFlight then
		if player then
			return
		end
		self:_endPassFlight(false, nil)
	end

	if self._passPending and player and self._passPending.throwerUserId == player.UserId then
		self._carrier = player
		return
	end

	if self._passPending then
		self:_cancelPassPending()
	end

	self:_stopPassFlight()
	self:_clearHold()
	self._isLoose = false
	self:_setLooseAttribute(false)
	self:_unbindPickupTouches()
	self._carrier = player
	self._carrierCharacter = nil

	if not player then
		if self._ballInstance then
			setBallPhysics(self._ballInstance, false)
		end
		return
	end

	local function attachIfStillCarrier(character: Model)
		if self._carrier ~= player then
			return
		end

		if character:FindFirstChild("HumanoidRootPart") then
			self:_attachToCharacter(character, player)
			return
		end

		task.spawn(function()
			character:WaitForChild("HumanoidRootPart", 10)
			if self._carrier ~= player then
				return
			end
			self:_attachToCharacter(character, player)
		end)
	end

	local character = player.Character
	if character then
		attachIfStillCarrier(character)
	else
		task.spawn(function()
			attachIfStillCarrier(player.Character or player.CharacterAdded:Wait())
		end)
	end
end

function BallService:dropBall()
	self:_cancelPassPending()
	if self._passInFlight then
		self:_endPassFlight(false, nil)
	else
		self:_stopPassFlight()
	end
	self:_clearHold()
	self._isLoose = false
	self:_setLooseAttribute(false)
	self:_unbindPickupTouches()

	if self._ballInstance and self._ballRoot then
		setBallPhysics(self._ballInstance, false)
		pcall(function()
			self._ballRoot:SetNetworkOwnershipAuto()
		end)
	end

	self._carrier = nil
	self._carrierCharacter = nil
end

function BallService:releaseLoose()
	self:dropBall()
	self._isLoose = true
	self:_setLooseAttribute(true)
	self._pickupAvailableAt = 0
	if self._ballInstance then
		setBallPhysics(self._ballInstance, false)
	end
	self:_bindPickupTouches()
end

function BallService:knockoutBall(direction: Vector3, charge01: number)
	if self._passInFlight or self._passPending then
		self:_endPassFlight(false, nil)
	else
		self:_stopPassFlight()
	end
	local tackledCarrier = self._carrier
	self:_clearHold()

	if self._ballInstance and self._ballRoot then
		setBallPhysics(self._ballInstance, false)
		pcall(function()
			self._ballRoot:SetNetworkOwnershipAuto()
		end)

		local flatDirection = Vector3.new(direction.X, 0, direction.Z)
		if flatDirection.Magnitude < 0.01 then
			flatDirection = Vector3.new(0, 0, -1)
		else
			flatDirection = flatDirection.Unit
		end

		local knockback = ChargeUtil.getKnockback(charge01) * Config.BALL_KNOCKOUT_FORCE_SCALE
		local knockbackUp = ChargeUtil.getKnockbackUp(charge01) * Config.BALL_KNOCKOUT_UP_SCALE
		local velocity = flatDirection * knockback + Vector3.new(0, knockbackUp, 0)
		if velocity.Magnitude > Config.BALL_KNOCKOUT_MAX_SPEED then
			velocity = velocity.Unit * Config.BALL_KNOCKOUT_MAX_SPEED
		end
		self._ballRoot.AssemblyLinearVelocity = velocity
		self._ballRoot.AssemblyAngularVelocity = Vector3.new(
			(math.random() - 0.5) * 2 * Config.BALL_KNOCKOUT_SPIN,
			(math.random() - 0.5) * 2 * Config.BALL_KNOCKOUT_SPIN,
			(math.random() - 0.5) * 2 * Config.BALL_KNOCKOUT_SPIN
		)
	end

	self._carrier = nil
	self._carrierCharacter = nil
	self._isLoose = true
	self:_setLooseAttribute(true)
	self._pickupAvailableAt = os.clock() + Config.BALL_KNOCKOUT_PICKUP_DELAY
	if tackledCarrier then
		self._pickupBlockedUntil[tackledCarrier.UserId] = os.clock() + Config.BALL_KNOCKOUT_CARRIER_PICKUP_BLOCK
	end
	self:_bindPickupTouches()

	return tackledCarrier
end

function BallService:isPassInFlight(): boolean
	return self._passInFlight
end

function BallService:isPassPending(): boolean
	return self._passPending ~= nil
end

function BallService:isBallHeldByPlayer(player: Player): boolean
	local character = player.Character
	if not character then
		return false
	end

	return self:_isBallHeldByCharacter(character)
end

function BallService:getPassTarget(): Model?
	return self._passTarget
end

function BallService:setPassCompleteHandler(handler: ((Model) -> ())?)
	self._passCompleteHandler = handler
end

function BallService:setPassEndedHandler(handler: ((number?, Model?, boolean) -> ())?)
	self._passEndedHandler = handler
end

function BallService:setPassFlightStartedHandler(handler: ((number?) -> ())?)
	self._passFlightStartedHandler = handler
end

function BallService:_stopPassAimLock()
	if self._passAimConnection then
		self._passAimConnection:Disconnect()
		self._passAimConnection = nil
	end
end

function BallService:_faceThrowerTowardReceiver(throwerCharacter: Model?, receiverCharacter: Model?)
	if not throwerCharacter or not receiverCharacter then
		return
	end

	if throwerCharacter:GetAttribute("TackleBallRagdollActive") == true then
		return
	end

	PassUtil.faceCharacterTowardCharacter(throwerCharacter, receiverCharacter)
end

function BallService:_startPassAimLock()
	self:_stopPassAimLock()

	local token = self._passReleaseToken
	self._passAimConnection = RunService.Heartbeat:Connect(function()
		if token ~= self._passReleaseToken then
			self:_stopPassAimLock()
			return
		end

		local pending = self._passPending
		if not pending then
			self:_stopPassAimLock()
			return
		end

		local throwerCharacter = pending.throwerCharacter
		if pending.throwerUserId then
			local thrower = Players:GetPlayerByUserId(pending.throwerUserId)
			if thrower and thrower.Character then
				throwerCharacter = thrower.Character
			end
		end

		local receiverCharacter = self:_resolvePassReceiver(pending.receiverCharacter, pending.receiverUserId)
		self:_faceThrowerTowardReceiver(throwerCharacter, receiverCharacter)
	end)
end

function BallService:_cancelPassPending()
	self:_stopPassAimLock()
	self._passPending = nil
	self._passReleaseToken += 1
end

function BallService:_stopPassFlight(skipPhysicsRestore: boolean?)
	if self._passConnection then
		self._passConnection:Disconnect()
		self._passConnection = nil
	end

	self._passInFlight = false
	self._passTarget = nil
	self._passTargetUserId = nil
	self._passArcStartPos = nil
	self._passStartTime = 0
	self._passFlightDuration = 0

	if self._ballRoot then
		clearPassFlightAttributes(self._ballRoot)
	end

	if not skipPhysicsRestore and self._ballInstance and not self._hold then
		setBallPhysics(self._ballInstance, false)
	end
end

function BallService:_endPassFlight(completed: boolean, receiverCharacter: Model?)
	local throwerUserId = self._passThrowerUserId
	self:_cancelPassPending()
	self._passThrowerUserId = nil
	self:_stopPassFlight(completed)

	if not completed and not self._carrier and not self._carrierCharacter and not self._hold then
		self:releaseLoose()
	end

	if self._passEndedHandler then
		self._passEndedHandler(throwerUserId, receiverCharacter, completed)
	end
end

function BallService:_resolvePassReceiver(receiverCharacter: Model?, receiverUserId: number?): Model?
	if receiverUserId then
		local receiver = Players:GetPlayerByUserId(receiverUserId)
		if receiver and receiver.Character then
			return receiver.Character
		end
	end

	if receiverCharacter and receiverCharacter.Parent then
		return receiverCharacter
	end

	return nil
end

function BallService:_setPassBallCFrame(arcPos: Vector3, spin: number)
	if not self._ballRoot or not self._ballInstance then
		return
	end

	local targetCFrame = CFrame.new(arcPos) * CFrame.Angles(spin, spin * 0.7, spin * 0.35)
	self._ballInstance:PivotTo(targetCFrame)
end

function BallService:_updatePassArc()
	if not self._passInFlight or not self._ballRoot or not self._ballInstance then
		self:_endPassFlight(false, nil)
		return
	end

	if not self._passArcStartPos then
		self:_endPassFlight(false, nil)
		return
	end

	local receiverCharacter = self:_resolvePassReceiver(self._passTarget, self._passTargetUserId)
	if not receiverCharacter then
		self:_endPassFlight(false, nil)
		return
	end

	self._passTarget = receiverCharacter

	local elapsed = Workspace:GetServerTimeNow() - self._passStartTime
	if elapsed > Config.PASS_TIMEOUT then
		self:_endPassFlight(false, nil)
		return
	end

	local targetHumanoid = receiverCharacter:FindFirstChildOfClass("Humanoid")
	if not targetHumanoid or targetHumanoid.Health <= 0 then
		self:_endPassFlight(false, nil)
		return
	end

	local targetPos = PassUtil.getPassTargetPosition(receiverCharacter)
	if not targetPos then
		self:_endPassFlight(false, nil)
		return
	end

	local alpha = if self._passFlightDuration > 0 then elapsed / self._passFlightDuration else 1
	local arcPos = PassUtil.getArcPosition(self._passArcStartPos, targetPos, alpha, Config.PASS_ARC_HEIGHT)
	arcPos = ArenaBoundsUtil.clampPosition(arcPos)
	local spin = elapsed * Config.PASS_SPIN
	self:_setPassBallCFrame(arcPos, spin)

	if alpha >= 1 then
		self:_completePass(receiverCharacter)
	end
end

function BallService:_beginPassFlight()
	local pending = self._passPending
	self._passPending = nil
	if not pending or not self._ballInstance or not self._ballRoot then
		return
	end

	local throwerCharacter = pending.throwerCharacter
	if pending.throwerUserId then
		local thrower = Players:GetPlayerByUserId(pending.throwerUserId)
		if thrower and thrower.Character then
			throwerCharacter = thrower.Character
		end
	end

	local receiverCharacter = self:_resolvePassReceiver(pending.receiverCharacter, pending.receiverUserId)
	if not receiverCharacter then
		warn("BallService: pass receiver missing at release")
		self:_releasePassFromThrower(throwerCharacter, pending.throwerUserId)
		return
	end

	self:_stopPassAimLock()
	self:_faceThrowerTowardReceiver(throwerCharacter, receiverCharacter)

	local targetPos = PassUtil.getPassTargetPosition(receiverCharacter)
	if not targetPos then
		warn("BallService: pass receiver has no target position at release")
		self:_releasePassFromThrower(throwerCharacter, pending.throwerUserId)
		return
	end

	self:_setBallOwnershipForHold(nil)
	local startPos = self._ballRoot.Position
	self:_detachBallFromCharacter(throwerCharacter)
	self._carrier = nil
	self._carrierCharacter = nil
	self._isLoose = false
	self:_setLooseAttribute(false)
	self:_unbindPickupTouches()

	if self._ballInstance.Parent ~= Workspace then
		self._ballInstance.Parent = Workspace
	end

	setPassFlightPhysics(self._ballInstance)
	self:_setPassBallCFrame(startPos, 0)

	self._passInFlight = true
	self._passTarget = receiverCharacter
	self._passTargetUserId = pending.receiverUserId
	self._passThrowerUserId = pending.throwerUserId
	self._passArcStartPos = startPos
	self._passFlightDuration = PassUtil.getPassFlightDuration(startPos, targetPos)
	self._passStartTime = Workspace:GetServerTimeNow()

	if self._ballRoot then
		setPassFlightAttributes(
			self._ballRoot,
			startPos,
			receiverCharacter,
			pending.receiverUserId,
			self._passFlightDuration,
			self._passStartTime
		)
	end

	self._passConnection = RunService.Heartbeat:Connect(function()
		self:_updatePassArc()
	end)

	self:_updatePassArc()

	if self._passFlightStartedHandler then
		local ok, err = pcall(function()
			self._passFlightStartedHandler(pending.throwerUserId)
		end)
		if not ok then
			warn(`BallService: pass flight started handler failed: {err}`)
		end
	end
end

function BallService:_releasePassFromThrower(throwerCharacter: Model?, _throwerUserId: number?)
	self:_setBallOwnershipForHold(nil)
	self:_detachBallFromCharacter(throwerCharacter)
	self._carrier = nil
	self._carrierCharacter = nil
	self:_endPassFlight(false, nil)
end

function BallService:_completePass(receiverCharacter: Model)
	self:_endPassFlight(true, receiverCharacter)
	self._isLoose = false
	self:_setLooseAttribute(false)
	self:_unbindPickupTouches()

	local receiverPlayer = Players:GetPlayerFromCharacter(receiverCharacter)
	if receiverPlayer then
		self._carrier = receiverPlayer
		self._carrierCharacter = nil
	else
		self._carrier = nil
		self._carrierCharacter = receiverCharacter
	end

	self:_attachToCharacter(receiverCharacter, receiverPlayer)

	if self._passCompleteHandler then
		self._passCompleteHandler(receiverCharacter)
	end
end

function BallService:throwPass(
	throwerCharacter: Model,
	receiverCharacter: Model,
	throwerUserId: number?,
	receiverUserId: number?
)
	if not self._ballInstance or not self._ballRoot then
		return false
	end

	if self._passInFlight or self._passPending then
		return false
	end

	if not self:_isBallHeldByCharacter(throwerCharacter) then
		return false
	end

	local receiverRoot = receiverCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
	local receiverHumanoid = receiverCharacter:FindFirstChildOfClass("Humanoid")
	if not receiverRoot or not receiverHumanoid or receiverHumanoid.Health <= 0 then
		return false
	end

	self:_cancelPassPending()
	self._passPending = {
		receiverCharacter = receiverCharacter,
		receiverUserId = receiverUserId,
		throwerCharacter = throwerCharacter,
		throwerUserId = throwerUserId,
		releaseAt = os.clock() + Config.PASS_RELEASE_DELAY,
	}

	self:_faceThrowerTowardReceiver(throwerCharacter, receiverCharacter)
	self:_startPassAimLock()

	local releaseToken = self._passReleaseToken
	task.delay(Config.PASS_RELEASE_DELAY, function()
		if releaseToken ~= self._passReleaseToken then
			return
		end

		local pending = self._passPending
		if not pending or pending.throwerUserId ~= throwerUserId then
			return
		end

		self:_beginPassFlight()
	end)

	return true
end

function BallService:onTackle(direction: Vector3, charge01: number)
	return self:knockoutBall(direction, charge01)
end

return BallService
