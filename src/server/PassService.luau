local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local GameMode = require(ReplicatedStorage.Shared.GameMode)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

type TeamName = Types.TeamName

local PassService = {}
PassService._matchService = nil
PassService._ballService = nil
PassService._teamService = nil
PassService._lastPassAt = {} :: { [number]: number }

local function getFlatLookVector(root: BasePart): Vector3
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if look.Magnitude < 0.01 then
		return Vector3.new(0, 0, -1)
	end

	return look.Unit
end

local function getFlatDistance(from: Vector3, to: Vector3): number
	return (Vector3.new(to.X - from.X, 0, to.Z - from.Z)).Magnitude
end

local function isInCone(fromPosition: Vector3, lookDirection: Vector3, targetPosition: Vector3): boolean
	local toTarget = Vector3.new(targetPosition.X - fromPosition.X, 0, targetPosition.Z - fromPosition.Z)
	if toTarget.Magnitude < 0.01 then
		return true
	end

	local cosThreshold = math.cos(math.rad(Config.PASS_AIM_CONE_DEGREES * 0.5))
	return lookDirection:Dot(toTarget.Unit) >= cosThreshold
end

function PassService:init(matchService, ballService, teamService)
	self._matchService = matchService
	self._ballService = ballService
	self._teamService = teamService

	self._ballService:setPassCompleteHandler(function(receiverCharacter)
		self:_onPassComplete(receiverCharacter)
	end)

	self._ballService:setPassFlightStartedHandler(function(throwerUserId)
		if throwerUserId then
			local thrower = Players:GetPlayerByUserId(throwerUserId)
			if thrower then
				self._matchService:onPassFlightStarted(thrower)
			end
		end
	end)

	self._ballService:setPassEndedHandler(function(throwerUserId, receiverCharacter, completed)
		if not completed then
			self._matchService:onPassFailed(throwerUserId)
		end

		Remotes.passEnded():FireAllClients({
			throwerUserId = throwerUserId,
			receiverCharacterName = if receiverCharacter then receiverCharacter.Name else nil,
			completed = completed,
		} :: Types.PassEndedPayload)
	end)

	Remotes.passAttempt().OnServerEvent:Connect(function(player, lookDirection)
		if typeof(lookDirection) == "Vector3" then
			self:attemptPass(player, lookDirection)
		else
			self:attemptPass(player, nil)
		end
	end)
end

function PassService:_onPassComplete(receiverCharacter: Model)
	if not GameMode.isTeamsMode() or not self._matchService:isActive() then
		return
	end

	local receiverPlayer = Players:GetPlayerFromCharacter(receiverCharacter)
	if receiverPlayer then
		self._matchService:setTeamsCarrier(receiverPlayer)
	else
		self._matchService:setTeamsNpcCarrier(receiverCharacter)
	end
end

function PassService:_findPassTarget(
	thrower: Player,
	throwerCharacter: Model,
	lookDirection: Vector3?
): (Player | Model)?
	if not self._teamService then
		return nil
	end

	local throwerTeam = self._teamService:getTeam(thrower) or self._teamService:getTeam(throwerCharacter)
	if not throwerTeam then
		return nil
	end

	local throwerRoot = throwerCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not throwerRoot then
		return nil
	end

	local aimDirection = lookDirection
	if not aimDirection or aimDirection.Magnitude < 0.01 then
		aimDirection = getFlatLookVector(throwerRoot)
	else
		aimDirection = Vector3.new(aimDirection.X, 0, aimDirection.Z)
		if aimDirection.Magnitude < 0.01 then
			aimDirection = getFlatLookVector(throwerRoot)
		else
			aimDirection = aimDirection.Unit
		end
	end

	local bestTarget: Player | Model? = nil
	local bestDistance = math.huge
	local fallbackTarget: Player | Model? = nil
	local fallbackDistance = math.huge

	for _, member in self._teamService:getTeamMembers(throwerTeam) do
		if member == thrower then
			continue
		end

		local character: Model? = nil
		if typeof(member) == "Instance" and member:IsA("Player") then
			character = member.Character
		elseif typeof(member) == "Instance" and member:IsA("Model") then
			character = member
		end

		if not character or character == throwerCharacter then
			continue
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not humanoid or humanoid.Health <= 0 or not root then
			continue
		end

		local distance = getFlatDistance(throwerRoot.Position, root.Position)
		if distance > Config.PASS_MAX_RANGE then
			continue
		end

		if distance < fallbackDistance then
			fallbackDistance = distance
			fallbackTarget = member
		end

		if not isInCone(throwerRoot.Position, aimDirection, root.Position) then
			continue
		end

		if distance < bestDistance then
			bestDistance = distance
			bestTarget = member
		end
	end

	return bestTarget or fallbackTarget
end

function PassService:_isPlayerCarrier(player: Player): boolean
	if not self._ballService:isBallHeldByPlayer(player) then
		return false
	end

	return self._matchService:getCarrier() == player or self._ballService:getCarrier() == player
end

function PassService:attemptPass(player: Player, lookDirection: Vector3?): boolean
	if not GameMode.isTeamsMode() or not self._matchService:isActive() then
		return false
	end

	if not self:_isPlayerCarrier(player) then
		return false
	end

	if self._ballService:isPassInFlight() or self._ballService:isPassPending() then
		return false
	end

	local lastPass = self._lastPassAt[player.UserId]
	if lastPass and os.clock() - lastPass < Config.PASS_COOLDOWN then
		return false
	end

	local character = player.Character
	if not character then
		return false
	end

	local receiver = self:_findPassTarget(player, character, lookDirection)
	if not receiver then
		return false
	end

	local receiverCharacter: Model? = nil
	local receiverUserId: number? = nil
	if typeof(receiver) == "Instance" and receiver:IsA("Player") then
		receiverCharacter = receiver.Character
		receiverUserId = receiver.UserId
	elseif typeof(receiver) == "Instance" and receiver:IsA("Model") then
		receiverCharacter = receiver
	end

	if not receiverCharacter then
		return false
	end

	if not self._ballService:throwPass(character, receiverCharacter, player.UserId, receiverUserId) then
		return false
	end

	self._lastPassAt[player.UserId] = os.clock()

	Remotes.passStarted():FireAllClients({
		throwerUserId = player.UserId,
		throwerCharacterName = character.Name,
		receiverUserId = receiverUserId,
		receiverCharacterName = receiverCharacter.Name,
	} :: Types.PassStartedPayload)

	return true
end

return PassService
