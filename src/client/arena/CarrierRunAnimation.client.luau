local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AnimationUtil = require(ReplicatedStorage.Shared.AnimationUtil)
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local player = Players.LocalPlayer

local carrierUserId: number? = nil
local roundActive = false
local previousRoundState: Types.RoundState? = nil
local previousCarrierUserId: number? = nil
local truckRunBlockedUntil = {} :: { [Model]: number }

local function isCarrierRunBlocked(character: Model): boolean
	if character:GetAttribute("TackleBallRagdollActive") == true then
		return true
	end

	if AnimationUtil.isJumpPlaying(character) then
		return true
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		if humanoid.Jump then
			return true
		end

		local state = humanoid:GetState()
		if state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.Freefall then
			return true
		end
	end

	if AnimationUtil.isTruckTuckActive(character) then
		return true
	end

	local blockedUntil = truckRunBlockedUntil[character]
	return blockedUntil ~= nil and os.clock() < blockedUntil
end

local function blockCarrierRun(character: Model, duration: number)
	truckRunBlockedUntil[character] = os.clock() + duration
	AnimationUtil.stopRunLoop(character)
end

local function getCharacterForUserId(userId: number?): Model?
	if not userId then
		return nil
	end

	local carrierPlayer = Players:GetPlayerByUserId(userId)
	return carrierPlayer and carrierPlayer.Character
end

local function isOnGround(humanoid: Humanoid, character: Model): boolean
	if humanoid.FloorMaterial ~= Enum.Material.Air then
		return true
	end

	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { character }

	local ray = workspace:Raycast(root.Position, Vector3.new(0, -3, 0), rayParams)
	return ray ~= nil
end

local function getHorizontalSpeed(character: Model): number
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return 0
	end

	local velocity = root.AssemblyLinearVelocity
	return Vector3.new(velocity.X, 0, velocity.Z).Magnitude
end

local function shouldPlayCarrierRun(humanoid: Humanoid, character: Model): boolean
	if humanoid.WalkSpeed <= 0 then
		return false
	end

	if not isOnGround(humanoid, character) then
		return false
	end

	return getHorizontalSpeed(character) > Config.RUN_MOVE_THRESHOLD
end

local function stopDummyRunLoops()
	for _, child in workspace:GetChildren() do
		if child:IsA("Model")
			and (child:GetAttribute("TackleBallDummyTackler") == true or child:GetAttribute("TackleBallDummyCarrier") == true)
		then
			AnimationUtil.stopRunLoop(child)
		end
	end
end

local function findDummyCarrier(): Model?
	for _, child in workspace:GetChildren() do
		if child:IsA("Model") and child:GetAttribute("TackleBallDummyCarrier") == true then
			return child
		end
	end

	return nil
end

local function updateDummyCarrierRun()
	local dummyCarrier = findDummyCarrier()
	if not dummyCarrier then
		return
	end

	local humanoid = dummyCarrier:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	if shouldPlayCarrierRun(humanoid, dummyCarrier) then
		local speed = getHorizontalSpeed(dummyCarrier)
		AnimationUtil.playRunLoop(dummyCarrier, speed)
	else
		AnimationUtil.stopRunLoop(dummyCarrier)
	end
end

local function updateCarrierRun()
	local character = getCharacterForUserId(carrierUserId)
	if not roundActive then
		for _, listedPlayer in Players:GetPlayers() do
			local listedCharacter = listedPlayer.Character
			if listedCharacter and AnimationUtil.isRunLoopPlaying(listedCharacter) then
				AnimationUtil.stopRunLoop(listedCharacter)
			end
		end
		stopDummyRunLoops()
		return
	end

	if not character then
		for _, listedPlayer in Players:GetPlayers() do
			local listedCharacter = listedPlayer.Character
			if listedCharacter and AnimationUtil.isRunLoopPlaying(listedCharacter) then
				AnimationUtil.stopRunLoop(listedCharacter)
			end
		end
		updateDummyCarrierRun()
		return
	end

	for _, listedPlayer in Players:GetPlayers() do
		local listedCharacter = listedPlayer.Character
		if listedCharacter and listedCharacter ~= character and AnimationUtil.isRunLoopPlaying(listedCharacter) then
			AnimationUtil.stopRunLoop(listedCharacter)
		end
	end

	stopDummyRunLoops()

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	if isCarrierRunBlocked(character) then
		if AnimationUtil.isJumpInProgress(character) then
			AnimationUtil.stopRunLoop(character)
		end
		return
	end

	if shouldPlayCarrierRun(humanoid, character) then
		local speed = getHorizontalSpeed(character)
		AnimationUtil.playRunLoop(character, speed)
	else
		AnimationUtil.stopRunLoop(character)
	end
end

Remotes.roundStateChanged().OnClientEvent:Connect(function(payload: Types.RoundStatePayload)
	local character = player.Character

	if character then
		if previousRoundState == "Active" and payload.state ~= "Active" then
			truckRunBlockedUntil[character] = nil
			AnimationUtil.resetLocomotion(character)
		elseif payload.state == "Active"
			and payload.carrierUserId == player.UserId
			and previousCarrierUserId ~= player.UserId
		then
			AnimationUtil.resetLocomotion(character)
		end
	end

	previousRoundState = payload.state
	previousCarrierUserId = payload.carrierUserId
	carrierUserId = payload.carrierUserId
	roundActive = payload.state == "Active"

	if not roundActive then
		updateCarrierRun()
	end
end)

RunService.PostSimulation:Connect(updateCarrierRun)

Remotes.tackleHit().OnClientEvent:Connect(function(_tackler: Player, carrier: Player?)
	if carrier and carrier.Character then
		AnimationUtil.stopJump(carrier.Character)
		AnimationUtil.stopRunLoop(carrier.Character)
	end

	stopDummyRunLoops()
end)

Remotes.dodgeStarted().OnClientEvent:Connect(function(carrier: Player)
	if carrier.Character then
		blockCarrierRun(carrier.Character, Config.SHED_ACTIVE_WINDOW + 0.1)
	end
end)

Remotes.truckDashStarted().OnClientEvent:Connect(function(carrier: Player)
	if carrier.Character then
		blockCarrierRun(carrier.Character, Config.TRUCK_DASH_WINDUP + Config.TRUCK_DASH_DURATION + 0.1)
	end
end)

Remotes.tackleShed().OnClientEvent:Connect(function(_tackler: Player, carrier: Player)
	if carrier.Character then
		blockCarrierRun(carrier.Character, Config.SHED_ANIM_DURATION + 0.1)
	end
end)

AnimationUtil.preload()
