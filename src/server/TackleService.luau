local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ChargeUtil = require(ReplicatedStorage.Shared.ChargeUtil)
local Config = require(ReplicatedStorage.Shared.Config)
local GameMode = require(ReplicatedStorage.Shared.GameMode)
local HealthService = require(script.Parent.HealthService)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local AnimationUtil = require(ReplicatedStorage.Shared.AnimationUtil)
local DodgeUtil = require(ReplicatedStorage.Shared.DodgeUtil)

type ActiveDash = {
	connection: RBXScriptConnection?,
	direction: Vector3,
	initialDirection: Vector3,
	endsAt: number,
	inWindup: boolean,
	dashSpeed: number,
	charge01: number,
	targetCharacter: Model?,
	targetRoot: BasePart?,
}

type ActiveCharge = {
	startedAt: number,
	direction: Vector3,
	releaseToken: {},
	monitorConnection: RBXScriptConnection?,
}

type ActiveTruckCharge = {
	startedAt: number,
	direction: Vector3,
	releaseToken: {},
	monitorConnection: RBXScriptConnection?,
	peakCharge01: number,
}

type TruckContestMemory = {
	charge01: number,
	expiresAt: number,
}

type ActiveTruckDash = {
	connection: RBXScriptConnection?,
	direction: Vector3,
	initialDirection: Vector3,
	speed: number,
	charge01: number,
	endsAt: number,
	inWindup: boolean,
}

type ActiveDummyTackleDash = {
	connection: RBXScriptConnection?,
	direction: Vector3,
	dashSpeed: number,
	charge01: number,
	endsAt: number,
	inWindup: boolean,
	carrier: Player?,
	carrierCharacter: Model?,
}

type ActiveJukeDash = {
	connection: RBXScriptConnection?,
	direction: Vector3,
	speed: number,
	endsAt: number,
}

type ActiveShedWindow = {
	expiresAt: number,
	dodgeType: string,
	jukeSide: number,
}

local TackleService = {}
TackleService._matchService = nil
TackleService._dummyTacklerService = nil
TackleService._cooldowns = {} :: { [number]: number }
TackleService._shedCooldowns = {} :: { [number]: number }
TackleService._truckCooldowns = {} :: { [number]: number }
TackleService._shedWindows = {} :: { [number]: ActiveShedWindow }
TackleService._activeDashes = {} :: { [number]: ActiveDash }
TackleService._activeJukeDashes = {} :: { [number]: ActiveJukeDash }
TackleService._activeTruckCharges = {} :: { [number]: ActiveTruckCharge }
TackleService._activeTruckDashes = {} :: { [number]: ActiveTruckDash }
TackleService._activeDummyDashes = {} :: { [Model]: ActiveDummyTackleDash }
TackleService._activeCharges = {} :: { [number]: ActiveCharge }
TackleService._savedWalkSpeeds = {} :: { [number]: number }
TackleService._pendingRelease = {} :: { [number]: boolean }
TackleService._pendingTruckRelease = {} :: { [number]: boolean }
TackleService._resolvedExchanges = {} :: { [number]: boolean }
TackleService._truckContestMemory = {} :: { [number]: TruckContestMemory }

function TackleService:init(matchService, dummyTacklerService)
	self._matchService = matchService
	self._dummyTacklerService = dummyTacklerService

	AnimationUtil.preload()

	Remotes.dashChargeBegin().OnServerEvent:Connect(function(player)
		self:beginCharge(player)
	end)

	Remotes.dashChargeRelease().OnServerEvent:Connect(function(player)
		if self._activeCharges[player.UserId] then
			self:releaseCharge(player)
		else
			self._pendingRelease[player.UserId] = true
			task.delay(0.2, function()
				self._pendingRelease[player.UserId] = nil
			end)
		end
	end)

	Remotes.truckChargeBegin().OnServerEvent:Connect(function(player)
		self:beginTruckCharge(player)
	end)

	Remotes.truckChargeRelease().OnServerEvent:Connect(function(player)
		if self._activeTruckCharges[player.UserId] then
			self:releaseTruckCharge(player)
		else
			self._pendingTruckRelease[player.UserId] = true
			task.delay(0.2, function()
				self._pendingTruckRelease[player.UserId] = nil
			end)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:cancelCharge(player)
		self:cancelTruckCharge(player)
		self:_stopTruckDash(player)
		self:_stopJukeDash(player)
		self._shedWindows[player.UserId] = nil
		self._shedCooldowns[player.UserId] = nil
		self._truckCooldowns[player.UserId] = nil
		self._truckContestMemory[player.UserId] = nil
	end)

	Remotes.dodgeActivate().OnServerEvent:Connect(function(player, clientDodgeType, clientJukeSide)
		self:activateDodge(player, clientDodgeType, clientJukeSide)
	end)
end

function TackleService:_getRoot(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

function TackleService:_getHumanoid(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

function TackleService:_isOnCooldown(player: Player): boolean
	local expiresAt = self._cooldowns[player.UserId]
	return expiresAt ~= nil and os.clock() < expiresAt
end

function TackleService:_setCooldown(player: Player)
	self._cooldowns[player.UserId] = os.clock() + Config.TACKLE_COOLDOWN
end

function TackleService:_getFlatLookVector(root: BasePart): Vector3
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then
		return Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

function TackleService:_zeroVelocity(root: BasePart)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
end

function TackleService:_getCarrierRoot(): BasePart?
	local character = self._matchService:getCarrierCharacter()
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

function TackleService:_isValidTackleVictim(tacklerPlayer: Player, victimCharacter: Model): boolean
	if not victimCharacter.Parent then
		return false
	end

	local tacklerCharacter = tacklerPlayer.Character
	if tacklerCharacter and victimCharacter == tacklerCharacter then
		return false
	end

	local victimPlayer = Players:GetPlayerFromCharacter(victimCharacter)
	if victimPlayer and victimPlayer == tacklerPlayer then
		return false
	end

	if GameMode.isTeamsMode() then
		local teamService = self._matchService:getTeamService()
		local tacklerCharacter = tacklerPlayer.Character
		if teamService and tacklerCharacter and teamService:areTeammates(tacklerCharacter, victimCharacter) then
			return false
		end
	end

	return HealthService:isAliveCombatCharacter(victimCharacter)
end

function TackleService:_getCharacterRoot(character: Model): BasePart?
	return character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

function TackleService:_getNearestTackleTargetRoot(tacklerRoot: BasePart, tacklerPlayer: Player): BasePart?
	local lookDirection = self:_getFlatLookVector(tacklerRoot)
	local nearestRoot: BasePart? = nil
	local nearestDistance = math.huge

	local function consider(character: Model)
		if not self:_isValidTackleVictim(tacklerPlayer, character) then
			return
		end

		local root = self:_getCharacterRoot(character)
		if not root then
			return
		end

		local offset = root.Position - tacklerRoot.Position
		local flat = Vector3.new(offset.X, 0, offset.Z)
		local distance = flat.Magnitude
		if distance > Config.TACKLE_AIM_ASSIST_RANGE then
			return
		end

		if distance > 0.01 and not self:_isCarrierInFront(lookDirection, flat.Unit) then
			return
		end

		if distance < nearestDistance then
			nearestDistance = distance
			nearestRoot = root
		end
	end

	for _, otherPlayer in Players:GetPlayers() do
		if otherPlayer.Character then
			consider(otherPlayer.Character)
		end
	end

	local dummyTacklers = self._dummyTacklerService and self._dummyTacklerService:getDummies() or {}
	for _, dummy in dummyTacklers do
		consider(dummy)
	end

	return nearestRoot
end

function TackleService:_getForwardConeMinDot(): number
	return math.cos(math.rad(Config.TACKLE_FORWARD_ASSIST_ANGLE * 0.5))
end

function TackleService:_isCarrierInFront(forwardDir: Vector3, toTargetDir: Vector3): boolean
	return forwardDir:Dot(toTargetDir) >= self:_getForwardConeMinDot()
end

function TackleService:_getAimAssistedDirectionToward(
	lookDirection: Vector3,
	fromRoot: BasePart,
	targetRoot: BasePart
): Vector3
	local offset = targetRoot.Position - fromRoot.Position
	local flat = Vector3.new(offset.X, 0, offset.Z)
	if flat.Magnitude < 0.01 then
		return lookDirection
	end

	local toTarget = flat.Unit

	if not self:_isCarrierInFront(lookDirection, toTarget) then
		return lookDirection
	end

	if flat.Magnitude <= Config.TACKLE_AIM_ASSIST_CLOSE_RANGE then
		return toTarget
	end

	local distanceFactor = 1
		- math.clamp(
			(flat.Magnitude - Config.TACKLE_AIM_ASSIST_CLOSE_RANGE)
				/ (Config.TACKLE_AIM_ASSIST_RANGE - Config.TACKLE_AIM_ASSIST_CLOSE_RANGE),
			0,
			1
		)
	local assist = Config.TACKLE_AIM_ASSIST_STRENGTH * (0.65 + 0.35 * distanceFactor)
	return lookDirection:Lerp(toTarget, assist).Unit
end

function TackleService:_getNearestTruckTargetRoot(carrierRoot: BasePart): BasePart?
	local carrier = self._matchService:getCarrier()
	local nearestRoot: BasePart? = nil
	local nearestDistance = math.huge

	for _, player in Players:GetPlayers() do
		if carrier and player == carrier then
			continue
		end

		local root = self:_getRoot(player)
		if not root then
			continue
		end

		local distance = (root.Position - carrierRoot.Position).Magnitude
		if distance <= Config.TACKLE_AIM_ASSIST_RANGE and distance < nearestDistance then
			nearestDistance = distance
			nearestRoot = root
		end
	end

	local dummyTacklers = self._dummyTacklerService and self._dummyTacklerService:getDummies() or {}
	for _, dummyTackler in dummyTacklers do
		if not HealthService:isAliveCombatCharacter(dummyTackler) then
			continue
		end

		local dummyRoot = dummyTackler:FindFirstChild("HumanoidRootPart") :: BasePart?
		if dummyRoot then
			local distance = (dummyRoot.Position - carrierRoot.Position).Magnitude
			if distance <= Config.TACKLE_AIM_ASSIST_RANGE and distance < nearestDistance then
				nearestDistance = distance
				nearestRoot = dummyRoot
			end
		end
	end

	return nearestRoot
end

function TackleService:_getTruckAimAssistedDirection(lookDirection: Vector3, carrierRoot: BasePart): Vector3
	local targetRoot = self:_getNearestTruckTargetRoot(carrierRoot)
	if not targetRoot then
		return lookDirection
	end

	return self:_getAimAssistedDirectionToward(lookDirection, carrierRoot, targetRoot)
end

function TackleService:_getAimAssistedDirection(lookDirection: Vector3, tacklerRoot: BasePart, tacklerPlayer: Player): Vector3
	local targetRoot = self:_getNearestTackleTargetRoot(tacklerRoot, tacklerPlayer)
	if not targetRoot then
		return lookDirection
	end

	return self:_getAimAssistedDirectionToward(lookDirection, tacklerRoot, targetRoot)
end

function TackleService:_resolveDashHitTarget(
	tacklerCharacter: Model,
	tacklerPlayer: Player,
	dash: ActiveDash
): Model?
	local candidates: { Model } = {}

	local function tryAdd(character: Model)
		if not self:_isValidTackleVictim(tacklerPlayer, character) then
			return
		end

		local victimRoot = self:_getCharacterRoot(character)
		local tacklerRoot = self:_getCharacterRoot(tacklerCharacter)
		if not victimRoot or not tacklerRoot then
			return
		end

		local hasContact = self:_hasTackleContact(tacklerCharacter, character)
		local withinFallback = (tacklerRoot.Position - victimRoot.Position).Magnitude
			<= Config.TACKLE_CONTACT_FALLBACK_RANGE
		if not hasContact and not withinFallback then
			return
		end

		if self:_isCarrierJumpingOverTackler(tacklerCharacter, character) then
			return
		end

		table.insert(candidates, character)
	end

	for _, otherPlayer in Players:GetPlayers() do
		if otherPlayer ~= tacklerPlayer and otherPlayer.Character then
			tryAdd(otherPlayer.Character)
		end
	end

	local dummyTacklers = self._dummyTacklerService and self._dummyTacklerService:getDummies() or {}
	for _, dummy in dummyTacklers do
		tryAdd(dummy)
	end

	if #candidates == 0 then
		return nil
	end

	if dash.targetCharacter then
		for _, candidate in candidates do
			if candidate == dash.targetCharacter then
				return candidate
			end
		end
	end

	return candidates[1]
end

function TackleService:_clampDirectionToMaxAngle(fromDir: Vector3, toDir: Vector3, maxAngleRad: number): Vector3
	local dot = math.clamp(fromDir:Dot(toDir), -1, 1)
	local angle = math.acos(dot)
	if angle <= maxAngleRad then
		return toDir
	end

	local sign = if fromDir:Cross(toDir).Y >= 0 then 1 else -1
	local cos = math.cos(maxAngleRad * sign)
	local sin = math.sin(maxAngleRad * sign)
	local x, z = fromDir.X, fromDir.Z
	return Vector3.new(x * cos - z * sin, 0, x * sin + z * cos).Unit
end

function TackleService:_getHomingDirection(
	initialDirection: Vector3,
	currentDirection: Vector3,
	tacklerRoot: BasePart,
	carrierRoot: BasePart
): Vector3
	local offset = carrierRoot.Position - tacklerRoot.Position
	local flatOffset = Vector3.new(offset.X, 0, offset.Z)
	if flatOffset.Magnitude > Config.TACKLE_HOMING_RANGE then
		return currentDirection
	end

	local targetDirection = if flatOffset.Magnitude < 0.01 then currentDirection else flatOffset.Unit

	if not self:_isCarrierInFront(initialDirection, targetDirection) then
		return currentDirection
	end

	if flatOffset.Magnitude <= Config.TACKLE_HOMING_STICKY_RANGE then
		return targetDirection
	end

	if flatOffset.Magnitude <= Config.TACKLE_HOMING_LOCK_RANGE then
		return self:_clampDirectionToMaxAngle(initialDirection, targetDirection, math.rad(Config.TACKLE_HOMING_MAX_ANGLE))
	end

	local distanceFactor = 1 - math.clamp(flatOffset.Magnitude / Config.TACKLE_HOMING_RANGE, 0, 1)
	local strength = math.clamp(
		Config.TACKLE_HOMING_STRENGTH * (1 + (Config.TACKLE_HOMING_CLOSE_MULTIPLIER - 1) * distanceFactor),
		0,
		1
	)
	local blended = currentDirection:Lerp(targetDirection, strength).Unit
	return self:_clampDirectionToMaxAngle(initialDirection, blended, math.rad(Config.TACKLE_HOMING_MAX_ANGLE))
end

function TackleService:_snapTacklerToCarrier(tacklerRoot: BasePart, carrierRoot: BasePart)
	local toCarrier = carrierRoot.Position - tacklerRoot.Position
	local flat = Vector3.new(toCarrier.X, 0, toCarrier.Z)
	local approachDir = if flat.Magnitude < 0.01
		then self:_getFlatLookVector(tacklerRoot)
		else flat.Unit

	local snapPos = carrierRoot.Position - approachDir * Config.TACKLE_SNAP_OFFSET
	snapPos = Vector3.new(snapPos.X, tacklerRoot.Position.Y, snapPos.Z)
	tacklerRoot.CFrame = CFrame.lookAt(snapPos, carrierRoot.Position)
	self:_zeroVelocity(tacklerRoot)
end

function TackleService:_snapCarrierToTackler(carrierRoot: BasePart, tacklerRoot: BasePart)
	local toTackler = tacklerRoot.Position - carrierRoot.Position
	local flat = Vector3.new(toTackler.X, 0, toTackler.Z)
	local approachDir = if flat.Magnitude < 0.01
		then self:_getFlatLookVector(carrierRoot)
		else flat.Unit

	local snapPos = tacklerRoot.Position - approachDir * Config.TACKLE_SNAP_OFFSET
	snapPos = Vector3.new(snapPos.X, carrierRoot.Position.Y, snapPos.Z)
	carrierRoot.CFrame = CFrame.lookAt(snapPos, tacklerRoot.Position)
	self:_zeroVelocity(carrierRoot)
end

function TackleService:_isCharacterBodyPart(part: BasePart, character: Model): boolean
	return part.Parent == character
end

function TackleService:_isCarrierJumpingOverTackler(tacklerCharacter: Model, carrierCharacter: Model): boolean
	local carrierRoot = carrierCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
	local tacklerRoot = tacklerCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
	local carrierHumanoid = carrierCharacter:FindFirstChildOfClass("Humanoid")
	if not carrierRoot or not tacklerRoot or not carrierHumanoid then
		return false
	end

	local flatOffset = Vector3.new(
		carrierRoot.Position.X - tacklerRoot.Position.X,
		0,
		carrierRoot.Position.Z - tacklerRoot.Position.Z
	)
	if flatOffset.Magnitude > Config.TACKLE_JUMP_CLEARANCE_HORIZONTAL then
		return false
	end

	local heightAbove = carrierRoot.Position.Y - tacklerRoot.Position.Y
	if heightAbove < Config.TACKLE_JUMP_CLEARANCE_HEIGHT then
		return false
	end

	local state = carrierHumanoid:GetState()
	if state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.Freefall then
		return true
	end

	return carrierRoot.AssemblyLinearVelocity.Y > Config.TACKLE_JUMP_CLEARANCE_MIN_ASCENT
end

function TackleService:_hasTackleContact(tacklerCharacter: Model, carrierCharacter: Model): boolean
	if self:_isCarrierJumpingOverTackler(tacklerCharacter, carrierCharacter) then
		return false
	end
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Include
	overlapParams.FilterDescendantsInstances = { carrierCharacter }

	for _, descendant in tacklerCharacter:GetDescendants() do
		if descendant:IsA("BasePart") and self:_isCharacterBodyPart(descendant, tacklerCharacter) then
			local overlaps = Workspace:GetPartBoundsInBox(descendant.CFrame, descendant.Size, overlapParams)
			for _, overlap in overlaps do
				if overlap:GetAttribute("TackleBallCorpsePart") ~= true then
					return true
				end
			end
		end
	end

	return false
end

function TackleService:_isShedOnCooldown(player: Player): boolean
	local expiresAt = self._shedCooldowns[player.UserId]
	return expiresAt ~= nil and os.clock() < expiresAt
end

function TackleService:_setShedCooldown(player: Player)
	self._shedCooldowns[player.UserId] = os.clock() + Config.SHED_COOLDOWN
end

function TackleService:_isTruckOnCooldown(player: Player): boolean
	local expiresAt = self._truckCooldowns[player.UserId]
	return expiresAt ~= nil and os.clock() < expiresAt
end

function TackleService:_setTruckCooldown(player: Player)
	self._truckCooldowns[player.UserId] = os.clock() + Config.TRUCK_COOLDOWN
end

function TackleService:_clearTruckCooldown(player: Player)
	self._truckCooldowns[player.UserId] = nil
end

function TackleService:isShedActive(player: Player): boolean
	local window = self._shedWindows[player.UserId]
	return window ~= nil and os.clock() < window.expiresAt
end

function TackleService:_canActivateDodge(player: Player): boolean
	if not self._matchService:isActive() then
		return false
	end

	if self._matchService:getCarrier() ~= player then
		return false
	end

	if self:_isShedOnCooldown(player) then
		return false
	end

	if self._matchService:isCarrierShedding(player) then
		return false
	end

	if self:isTruckDashing(player) or self:isTruckCharging(player) then
		return false
	end

	return self:_getRoot(player) ~= nil
end

function TackleService:_canBeginTruckCharge(player: Player): boolean
	if not self._matchService:isActive() then
		return false
	end

	if self._matchService:getCarrier() ~= player then
		return false
	end

	if self:_isTruckOnCooldown(player) then
		return false
	end

	if self._matchService:isCarrierShedding(player) then
		return false
	end

	if self:isTruckDashing(player) or self:isTruckCharging(player) then
		return false
	end

	return self:_getRoot(player) ~= nil
end

function TackleService:isTruckCharging(player: Player): boolean
	return self._activeTruckCharges[player.UserId] ~= nil
end

function TackleService:isTruckDashing(player: Player): boolean
	return self._activeTruckDashes[player.UserId] ~= nil
end

function TackleService:cancelTruckCharge(player: Player)
	local charge = self._activeTruckCharges[player.UserId]
	if not charge then
		return
	end

	if charge.monitorConnection then
		charge.monitorConnection:Disconnect()
	end

	self._activeTruckCharges[player.UserId] = nil
end

function TackleService:cancelAllTruckCharges()
	for _, player in Players:GetPlayers() do
		self:cancelTruckCharge(player)
	end
	self:_stopAllDummyTackleDashes()
end

function TackleService:_stopTruckDash(player: Player, restoreWalkSpeed: boolean?)
	local dash = self._activeTruckDashes[player.UserId]
	if not dash then
		return
	end

	if dash.connection then
		dash.connection:Disconnect()
	end

	self:_recordTruckContest(player, dash.charge01)
	self._activeTruckDashes[player.UserId] = nil

	local character = player.Character
	if character then
		character:SetAttribute("TruckTuckWindowActive", nil)
		character:SetAttribute("TruckTuckActive", nil)
		character:SetAttribute("DodgeType", nil)
		AnimationUtil.stopDodge(character)

		if restoreWalkSpeed ~= false then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid
				and character:GetAttribute("TackleBallRagdollActive") ~= true
				and self._matchService:getCarrier() == player
				and not self._matchService:isCarrierShedding(player)
			then
				humanoid.WalkSpeed = Config.DEFAULT_WALK_SPEED
			end
		end
	end

	Remotes.truckDashEnded():FireAllClients(player)
end

function TackleService:_getContactingTackler(carrierCharacter: Model): Player?
	local carrier = self._matchService:getCarrier()
	for _, player in Players:GetPlayers() do
		if carrier and player == carrier then
			continue
		end

		local character = player.Character
		if character and self:_hasTackleContact(character, carrierCharacter) then
			return player
		end
	end

	return nil
end

function TackleService:_recordTruckContest(player: Player, charge01: number)
	self._truckContestMemory[player.UserId] = {
		charge01 = charge01,
		expiresAt = os.clock() + Config.TRUCK_CONTEST_WINDOW,
	}
end

function TackleService:_getStoredTruckContestCharge01(player: Player): number?
	local memory = self._truckContestMemory[player.UserId]
	if memory and os.clock() < memory.expiresAt then
		return memory.charge01
	end

	return nil
end

function TackleService:_getTruckCharge01(player: Player): number?
	local dash = self._activeTruckDashes[player.UserId]
	if dash then
		return dash.charge01
	end

	local charge = self._activeTruckCharges[player.UserId]
	if charge then
		local liveCharge01 = ChargeUtil.getCharge01(os.clock() - charge.startedAt)
		return math.max(charge.peakCharge01, liveCharge01)
	end

	return self:_getStoredTruckContestCharge01(player)
end

function TackleService:_getTruckContestSpeed(player: Player): number
	local charge01 = self:_getTruckCharge01(player)
	if charge01 then
		return ChargeUtil.getTruckDashSpeed(charge01)
	end

	return 0
end

function TackleService:isTruckContesting(player: Player): boolean
	return self:isTruckDashing(player)
		or self:isTruckCharging(player)
		or self:_getStoredTruckContestCharge01(player) ~= nil
end

function TackleService:_getTruckDashSpeed(player: Player): number
	return self:_getTruckContestSpeed(player)
end

function TackleService:_getTackleDashSpeed(player: Player): number
	local dash = self._activeDashes[player.UserId]
	if not dash then
		return 0
	end

	return dash.dashSpeed
end

function TackleService:_resolveDashContest(
	carrier: Player,
	tackler: Player,
	tacklerCharge01: number,
	direction: Vector3,
	hitPosition: Vector3
)
	if self._resolvedExchanges[carrier.UserId] then
		return
	end

	self._resolvedExchanges[carrier.UserId] = true
	task.delay(0.5, function()
		self._resolvedExchanges[carrier.UserId] = nil
	end)

	local truckDash = self._activeTruckDashes[carrier.UserId]
	local truckCharge01 = self:_getTruckCharge01(carrier) or Config.CHARGE_NORMAL_CHARGE01
	local carrierSpeed = self:_getTruckContestSpeed(carrier)
	local tacklerSpeed = self:_getTackleDashSpeed(tackler)

	if self:isTruckCharging(carrier) then
		self:cancelTruckCharge(carrier)
	end

	self:_stopTruckDash(carrier)
	self:_clearDashState(tackler)

	local tacklerCharacter = tackler.Character
	if tacklerCharacter then
		AnimationUtil.stopTackleDive(tacklerCharacter)
	end

	self:_setCooldown(tackler)
	Remotes.tackleDashEnded():FireAllClients(tackler)

	if carrierSpeed >= tacklerSpeed then
		self:_clearTruckCooldown(carrier)
		self:_setShedCooldown(carrier)
		if tacklerCharacter then
			self._matchService:onTruckBeatTackle(carrier, direction, truckCharge01, tacklerCharacter, tackler)
		else
			self._matchService:onTackleShed(
				carrier,
				tackler,
				direction,
				"Truck",
				0,
				truckCharge01
			)
		end
		Remotes.tackleHit():FireAllClients(carrier, tackler, hitPosition, truckCharge01)
		Remotes.tackleShed():FireAllClients(tackler, carrier, hitPosition, "Truck")
	else
		self:_lockMovement(tackler, Config.DASH_STOP_ON_HIT)
		local carrierCharacter = carrier.Character
		if carrierCharacter then
			self._matchService:onTackleHit(tackler, carrierCharacter, direction, tacklerCharge01)
		end
		Remotes.tackleHit():FireAllClients(tackler, carrier, hitPosition, tacklerCharge01)
	end
end

function TackleService:beginTruckCharge(player: Player)
	if not self:_canBeginTruckCharge(player) then
		return
	end

	local root = self:_getRoot(player)
	if not root then
		return
	end

	local direction = self:_getFlatLookVector(root)
	local releaseToken = {}
	local initialCharge01 = ChargeUtil.getCharge01(0)

	self._activeTruckCharges[player.UserId] = {
		startedAt = os.clock(),
		direction = direction,
		releaseToken = releaseToken,
		monitorConnection = nil,
		peakCharge01 = initialCharge01,
	}

	Remotes.truckChargeStarted():FireAllClients(player)

	local monitorConnection = RunService.Heartbeat:Connect(function()
		local activeCharge = self._activeTruckCharges[player.UserId]
		if not activeCharge then
			return
		end

		if not self._matchService:isActive() then
			self:cancelTruckCharge(player)
			return
		end

		if self._matchService:getCarrier() ~= player then
			self:cancelTruckCharge(player)
			return
		end

		if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
			self:cancelTruckCharge(player)
			return
		end

		local liveCharge01 = ChargeUtil.getCharge01(os.clock() - activeCharge.startedAt)
		activeCharge.peakCharge01 = math.max(activeCharge.peakCharge01, liveCharge01)
	end)

	self._activeTruckCharges[player.UserId].monitorConnection = monitorConnection

	task.delay(Config.CHARGE_MAX_TIME, function()
		local activeCharge = self._activeTruckCharges[player.UserId]
		if activeCharge and activeCharge.releaseToken == releaseToken then
			self:releaseTruckCharge(player)
		end
	end)

	if self._pendingTruckRelease[player.UserId] then
		self._pendingTruckRelease[player.UserId] = nil
		self:releaseTruckCharge(player)
	end
end

function TackleService:releaseTruckCharge(player: Player)
	local charge = self._activeTruckCharges[player.UserId]
	if not charge then
		return
	end

	local chargeTime = os.clock() - charge.startedAt
	local charge01 = math.max(charge.peakCharge01, ChargeUtil.getCharge01(chargeTime))

	local root = self:_getRoot(player)
	local direction = if root then self:_getFlatLookVector(root) else charge.direction
	if root then
		direction = self:_getTruckAimAssistedDirection(direction, root)
	end

	if charge.monitorConnection then
		charge.monitorConnection:Disconnect()
	end

	self._activeTruckCharges[player.UserId] = nil
	self:_recordTruckContest(player, charge01)

	self:startTruckDash(player, direction, charge01)
end

function TackleService:_beginTruckBurst(player: Player)
	local root = self:_getRoot(player)
	local dash = self._activeTruckDashes[player.UserId]
	if not root or not dash then
		return
	end

	dash.inWindup = false
	dash.endsAt = os.clock() + Config.TRUCK_DASH_DURATION

	local humanoid = self:_getHumanoid(player)
	if humanoid then
		humanoid.WalkSpeed = dash.speed
	end

	root.AssemblyLinearVelocity = dash.direction * dash.speed

	dash.connection = RunService.Heartbeat:Connect(function()
		if not self._activeTruckDashes[player.UserId] then
			return
		end

		local currentDash = self._activeTruckDashes[player.UserId]
		local currentRoot = self:_getRoot(player)
		if not currentRoot then
			self:_stopTruckDash(player)
			return
		end

		if os.clock() >= currentDash.endsAt then
			self:_stopTruckDash(player)
			return
		end

		local targetRoot = self:_getNearestTruckTargetRoot(currentRoot)
		if targetRoot then
			currentDash.direction = self:_getHomingDirection(
				currentDash.initialDirection,
				currentDash.direction,
				currentRoot,
				targetRoot
			)
		end

		currentRoot.AssemblyLinearVelocity = currentDash.direction * currentDash.speed

		local carrierCharacter = player.Character
		if not carrierCharacter then
			return
		end

		local tackler = self:_getContactingTackler(carrierCharacter)
		if not tackler and targetRoot then
			for _, otherPlayer in Players:GetPlayers() do
				if otherPlayer ~= player and self:_getRoot(otherPlayer) == targetRoot then
					tackler = otherPlayer
					break
				end
			end
		end

		if tackler then
			local tacklerRoot = self:_getRoot(tackler)
			if tacklerRoot then
				local tacklerCharacter = tackler.Character
				local hasContact = tacklerCharacter and self:_hasTackleContact(tacklerCharacter, carrierCharacter)
				local withinFallback = (currentRoot.Position - tacklerRoot.Position).Magnitude
					<= Config.TACKLE_CONTACT_FALLBACK_RANGE
				local jumpingOver = tacklerCharacter
					and self:_isCarrierJumpingOverTackler(tacklerCharacter, carrierCharacter)
				if (hasContact or withinFallback) and not jumpingOver then
					self:_snapCarrierToTackler(currentRoot, tacklerRoot)
					local hitPosition = (currentRoot.Position + tacklerRoot.Position) / 2

					if self:isDashing(tackler) then
						local tacklerDash = self._activeDashes[tackler.UserId]
						local tacklerCharge01 = if tacklerDash then tacklerDash.charge01 else 0
						self:_resolveDashContest(player, tackler, tacklerCharge01, currentDash.direction, hitPosition)
					else
						self:_stopTruckDash(player)
						self._matchService:onTackleHit(tackler, carrierCharacter, currentDash.direction, 0)
						Remotes.tackleHit():FireAllClients(tackler, player, hitPosition, 0)
					end
					return
				end
			end
		end

		local dummyTacklers = self._dummyTacklerService and self._dummyTacklerService:getDummies() or {}
		for _, dummyTackler in dummyTacklers do
			if not HealthService:isAliveCombatCharacter(dummyTackler) then
				continue
			end

			local dummyRoot = dummyTackler:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not dummyRoot then
				continue
			end

			local hasContact = self:_hasTackleContact(dummyTackler, carrierCharacter)
			local withinFallback = (currentRoot.Position - dummyRoot.Position).Magnitude
				<= Config.TACKLE_CONTACT_FALLBACK_RANGE
			local jumpingOver = self:_isCarrierJumpingOverTackler(dummyTackler, carrierCharacter)
			if (hasContact or withinFallback) and not jumpingOver then
				self:_snapCarrierToTackler(currentRoot, dummyRoot)
				local hitPosition = (currentRoot.Position + dummyRoot.Position) / 2
				local dummyDash = self._activeDummyDashes[dummyTackler]
				local dummyCharge01 = if dummyDash then dummyDash.charge01
					elseif self._dummyTacklerService then self._dummyTacklerService:getDummyCharge01(dummyTackler)
					else Config.DUMMY_TACKLER_CHARGE01
				self:_resolveDummyDashContest(player, dummyTackler, dummyCharge01, currentDash.direction, hitPosition)
				return
			end
		end
	end)
end

function TackleService:startTruckDash(player: Player, direction: Vector3, charge01: number)
	if not self._matchService:isActive() or self._matchService:getCarrier() ~= player then
		return
	end

	if self:isTruckDashing(player) then
		return
	end

	if self:_isTruckOnCooldown(player) then
		return
	end

	local root = self:_getRoot(player)
	if not root then
		return
	end

	local dashSpeed = ChargeUtil.getTruckDashSpeed(charge01)

	self:_setTruckCooldown(player)
	self:_recordTruckContest(player, charge01)

	self._activeTruckDashes[player.UserId] = {
		connection = nil,
		direction = direction,
		initialDirection = direction,
		speed = dashSpeed,
		charge01 = charge01,
		endsAt = 0,
		inWindup = true,
	}

	local character = player.Character
	if character then
		character:SetAttribute("TruckTuckWindowActive", true)
		character:SetAttribute("TruckTuckActive", true)
		character:SetAttribute("DodgeType", "Truck")
		AnimationUtil.playDodge(character, "Truck")
	end

	Remotes.truckDashStarted():FireAllClients(player, charge01)
	self:_zeroVelocity(root)

	task.delay(Config.TRUCK_DASH_WINDUP, function()
		if self._activeTruckDashes[player.UserId] then
			self:_beginTruckBurst(player)
		end
	end)
end

function TackleService:stopTruckDash(player: Player, restoreWalkSpeed: boolean?)
	self:_stopTruckDash(player, restoreWalkSpeed)
end

function TackleService:stopJukeDash(player: Player, restoreWalkSpeed: boolean?)
	self:_stopJukeDash(player, restoreWalkSpeed)
end

function TackleService:_stopJukeDash(player: Player, restoreWalkSpeed: boolean?)
	local dash = self._activeJukeDashes[player.UserId]
	if not dash then
		return
	end

	if dash.connection then
		dash.connection:Disconnect()
	end

	self._activeJukeDashes[player.UserId] = nil

	if restoreWalkSpeed == false then
		return
	end

	local humanoid = self:_getHumanoid(player)
	if humanoid
		and character:GetAttribute("TackleBallRagdollActive") ~= true
		and self._matchService:getCarrier() == player
		and not self._matchService:isCarrierShedding(player)
	then
		humanoid.WalkSpeed = Config.DEFAULT_WALK_SPEED
	end
end

function TackleService:_applyJukeDash(player: Player, jukeSide: number)
	local root = self:_getRoot(player)
	local humanoid = self:_getHumanoid(player)
	if not root or not humanoid then
		return
	end

	self:_stopJukeDash(player, false)

	local right = root.CFrame.RightVector
	local flatRight = Vector3.new(right.X, 0, right.Z)
	if flatRight.Magnitude < 0.01 then
		flatRight = Vector3.new(1, 0, 0)
	else
		flatRight = flatRight.Unit
	end

	local direction = flatRight * jukeSide
	local dash: ActiveJukeDash = {
		direction = direction,
		speed = Config.JUKE_DASH_SPEED,
		endsAt = os.clock() + Config.JUKE_DASH_DURATION,
		connection = nil,
	}

	self._activeJukeDashes[player.UserId] = dash
	humanoid.WalkSpeed = Config.JUKE_DASH_SPEED

	dash.connection = RunService.Heartbeat:Connect(function()
		local activeDash = self._activeJukeDashes[player.UserId]
		local currentRoot = self:_getRoot(player)
		if not activeDash or not currentRoot then
			self:_stopJukeDash(player)
			return
		end

		if os.clock() >= activeDash.endsAt then
			self:_stopJukeDash(player)
			return
		end

		local currentY = currentRoot.AssemblyLinearVelocity.Y
		currentRoot.AssemblyLinearVelocity = activeDash.direction * activeDash.speed + Vector3.new(0, currentY, 0)
	end)
end

function TackleService:activateDodge(player: Player, clientDodgeType: string?, clientJukeSide: number?)
	local dodgeType, jukeSide = DodgeUtil.sanitizeClientDodge(clientDodgeType, clientJukeSide)
	if dodgeType ~= "Juke" then
		return
	end

	if not self:_canActivateDodge(player) then
		return
	end

	self._shedWindows[player.UserId] = {
		expiresAt = os.clock() + Config.SHED_ACTIVE_WINDOW,
		dodgeType = dodgeType,
		jukeSide = jukeSide,
	}

	local character = player.Character
	if character then
		character:SetAttribute("TruckTuckWindowActive", true)
		character:SetAttribute("DodgeType", dodgeType)

		local userId = player.UserId
		local dashed = false

		local function triggerJukeDash()
			if dashed then
				return
			end

			local window = self._shedWindows[userId]
			if not window or window.dodgeType ~= "Juke" then
				return
			end

			dashed = true
			self:_applyJukeDash(player, jukeSide)
		end

		AnimationUtil.playDodge(character, dodgeType, nil, triggerJukeDash, jukeSide)

		task.delay(0.45, function()
			triggerJukeDash()
		end)
	end

	Remotes.dodgeStarted():FireAllClients(player, dodgeType)

	task.delay(Config.SHED_ACTIVE_WINDOW, function()
		local window = self._shedWindows[player.UserId]
		if window and os.clock() >= window.expiresAt then
			self._shedWindows[player.UserId] = nil
			if character.Parent and not self._matchService:isCarrierShedding(player) then
				self:_stopJukeDash(player)
				character:SetAttribute("TruckTuckWindowActive", nil)
				character:SetAttribute("DodgeType", nil)
				AnimationUtil.stopDodge(character)

				local humanoid = character:FindFirstChildOfClass("Humanoid")
				if humanoid and window.dodgeType == "Juke" then
					humanoid.WalkSpeed = Config.DEFAULT_WALK_SPEED
				end
			end
		end
	end)
end

function TackleService:isDummyTackling(dummy: Model): boolean
	return self._activeDummyDashes[dummy] ~= nil
end

function TackleService:_stopDummyTackleDash(dummy: Model)
	local dash = self._activeDummyDashes[dummy]
	if not dash then
		return
	end

	if dash.connection then
		dash.connection:Disconnect()
	end

	self._activeDummyDashes[dummy] = nil
	AnimationUtil.stopTackleDive(dummy)
end

function TackleService:_stopAllDummyTackleDashes()
	for dummy in self._activeDummyDashes do
		self:_stopDummyTackleDash(dummy)
	end
end

function TackleService:_getFxPlayer(): Player?
	return Players:GetPlayers()[1]
end

function TackleService:_resolveDummyDashContestWithSpeeds(
	carrier: Player,
	dummy: Model,
	dummyCharge01: number,
	direction: Vector3,
	hitPosition: Vector3,
	carrierSpeed: number,
	dummySpeed: number,
	truckCharge01: number
)
	if self._resolvedExchanges[carrier.UserId] then
		return
	end

	self._resolvedExchanges[carrier.UserId] = true
	task.delay(0.5, function()
		self._resolvedExchanges[carrier.UserId] = nil
	end)

	if self:isTruckCharging(carrier) then
		self:cancelTruckCharge(carrier)
	end

	self:_stopTruckDash(carrier)
	self:_stopDummyTackleDash(dummy)

	local fxPlayer = self:_getFxPlayer()

	if carrierSpeed >= dummySpeed then
		self:_clearTruckCooldown(carrier)
		self:_setShedCooldown(carrier)
		self._matchService:onTruckBeatTackle(carrier, direction, truckCharge01, dummy, fxPlayer)
		if fxPlayer then
			Remotes.tackleHit():FireAllClients(carrier, fxPlayer, hitPosition, truckCharge01)
			Remotes.tackleShed():FireAllClients(fxPlayer, carrier, hitPosition, "Truck")
		end
	else
		self._matchService:onDummyTackleHit(carrier, direction, dummyCharge01, dummy)
		if fxPlayer then
			Remotes.tackleHit():FireAllClients(fxPlayer, carrier, hitPosition, dummyCharge01)
		end
	end
end

function TackleService:_resolveDummyDashContest(
	carrier: Player,
	dummy: Model,
	dummyCharge01: number,
	direction: Vector3,
	hitPosition: Vector3
)
	local truckCharge01 = self:_getTruckCharge01(carrier) or Config.CHARGE_NORMAL_CHARGE01
	local carrierSpeed = self:_getTruckContestSpeed(carrier)
	local dummyDash = self._activeDummyDashes[dummy]
	local dummySpeed = if dummyDash then dummyDash.dashSpeed else 0

	self:_resolveDummyDashContestWithSpeeds(
		carrier,
		dummy,
		dummyCharge01,
		direction,
		hitPosition,
		carrierSpeed,
		dummySpeed,
		truckCharge01
	)
end

function TackleService:_stopDummyDashOnHit(dummy: Model, direction: Vector3)
	local dash = self._activeDummyDashes[dummy]
	local charge01 = dash and dash.charge01 or Config.DUMMY_TACKLER_CHARGE01
	local dummySpeed = dash and dash.dashSpeed or 0
	local carrier = dash and dash.carrier
	local carrierCharacter = dash and dash.carrierCharacter
	if not carrierCharacter and carrier then
		carrierCharacter = carrier.Character
	end
	local carrierRoot = carrierCharacter and carrierCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
	local dummyRoot = dummy:FindFirstChild("HumanoidRootPart") :: BasePart?

	if not carrierCharacter or not carrierRoot or not dummyRoot then
		self:_stopDummyTackleDash(dummy)
		return
	end

	local hitPosition = (dummyRoot.Position + carrierRoot.Position) / 2

	self:_stopDummyTackleDash(dummy)

	if not carrier then
		self._matchService:onNpcCarrierTackleHit(dummy, carrierCharacter, direction, charge01)
		return
	end

	local truckCharge01 = self:_getTruckCharge01(carrier) or Config.CHARGE_NORMAL_CHARGE01
	local carrierSpeed = self:_getTruckContestSpeed(carrier)

	if self:isTruckContesting(carrier) then
		self:_resolveDummyDashContestWithSpeeds(
			carrier,
			dummy,
			charge01,
			direction,
			hitPosition,
			carrierSpeed,
			dummySpeed,
			truckCharge01
		)
	elseif self:isShedActive(carrier) then
		local window = self._shedWindows[carrier.UserId]
		local dodgeType = if window then window.dodgeType else "Juke"
		local jukeSide = if window then window.jukeSide else 0
		self._shedWindows[carrier.UserId] = nil
		self:_setShedCooldown(carrier)
		self._matchService:onTackleShed(carrier, self:_getFxPlayer(), direction, dodgeType, jukeSide, nil)
		local fxPlayer = self:_getFxPlayer()
		if fxPlayer then
			Remotes.tackleShed():FireAllClients(fxPlayer, carrier, hitPosition, dodgeType)
		end
	else
		self._matchService:onDummyTackleHit(carrier, direction, charge01, dummy)
		local fxPlayer = self:_getFxPlayer()
		if fxPlayer then
			Remotes.tackleHit():FireAllClients(fxPlayer, carrier, hitPosition, charge01)
		end
	end
end

function TackleService:_beginDummyBurst(dummy: Model)
	local root = dummy:FindFirstChild("HumanoidRootPart") :: BasePart?
	local dash = self._activeDummyDashes[dummy]
	if not root or not dash then
		return
	end

	dash.inWindup = false
	dash.endsAt = os.clock() + Config.DASH_DURATION

	root.AssemblyLinearVelocity = dash.direction * dash.dashSpeed

	dash.connection = RunService.Heartbeat:Connect(function()
		if not self._activeDummyDashes[dummy] then
			return
		end

		local currentDash = self._activeDummyDashes[dummy]
		local currentRoot = dummy:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not currentRoot then
			self:_stopDummyTackleDash(dummy)
			return
		end

		if os.clock() >= currentDash.endsAt then
			self:_stopDummyTackleDash(dummy)
			return
		end

		currentRoot.AssemblyLinearVelocity = currentDash.direction * currentDash.dashSpeed

		local carrierCharacter = currentDash.carrierCharacter
		if not carrierCharacter and currentDash.carrier then
			carrierCharacter = currentDash.carrier.Character
		end
		if not carrierCharacter then
			return
		end

		local hasContact = self:_hasTackleContact(dummy, carrierCharacter)
		local carrierRoot = carrierCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
		local withinFallback = carrierRoot
			and (currentRoot.Position - carrierRoot.Position).Magnitude <= Config.TACKLE_CONTACT_FALLBACK_RANGE
		local jumpingOver = self:_isCarrierJumpingOverTackler(dummy, carrierCharacter)

		if (hasContact or withinFallback) and not jumpingOver then
			self:_stopDummyDashOnHit(dummy, currentDash.direction)
		end
	end)
end

function TackleService:startDummyTackleDashAtCharacter(dummy: Model, carrierCharacter: Model, charge01: number)
	if self:isDummyTackling(dummy) then
		return
	end

	local carrierRoot = carrierCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
	local dummyRoot = dummy:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not carrierRoot or not dummyRoot then
		return
	end

	local offset = carrierRoot.Position - dummyRoot.Position
	local flat = Vector3.new(offset.X, 0, offset.Z)
	local direction = if flat.Magnitude < 0.01 then Vector3.new(0, 0, 1) else flat.Unit
	local dashSpeed = ChargeUtil.getDashSpeed(charge01)

	self._activeDummyDashes[dummy] = {
		connection = nil,
		direction = direction,
		dashSpeed = dashSpeed,
		charge01 = charge01,
		endsAt = 0,
		inWindup = true,
		carrier = nil,
		carrierCharacter = carrierCharacter,
	}

	AnimationUtil.playTackleDive(dummy)
	self:_zeroVelocity(dummyRoot)

	task.delay(Config.DASH_WINDUP, function()
		if self._activeDummyDashes[dummy] then
			self:_beginDummyBurst(dummy)
		end
	end)
end

function TackleService:startDummyTackleDash(dummy: Model, carrier: Player, charge01: number)
	if self:isDummyTackling(dummy) then
		return
	end

	local carrierRoot = self:_getRoot(carrier)
	if not carrierRoot then
		return
	end

	local dummyRoot = dummy:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not dummyRoot then
		return
	end

	local offset = carrierRoot.Position - dummyRoot.Position
	local flat = Vector3.new(offset.X, 0, offset.Z)
	local direction = if flat.Magnitude < 0.01 then Vector3.new(0, 0, 1) else flat.Unit
	local dashSpeed = ChargeUtil.getDashSpeed(charge01)

	self._activeDummyDashes[dummy] = {
		connection = nil,
		direction = direction,
		dashSpeed = dashSpeed,
		charge01 = charge01,
		endsAt = 0,
		inWindup = true,
		carrier = carrier,
		carrierCharacter = carrier.Character,
	}

	AnimationUtil.playTackleDive(dummy)
	self:_zeroVelocity(dummyRoot)

	task.delay(Config.DASH_WINDUP, function()
		if self._activeDummyDashes[dummy] then
			self:_beginDummyBurst(dummy)
		end
	end)
end

function TackleService:activateShed(player: Player)
	local root = self:_getRoot(player)
	if not root then
		return
	end

	self:startTruckDash(player, self:_getFlatLookVector(root), Config.CHARGE_NORMAL_CHARGE01)
end

function TackleService:_canTackle(player: Player): boolean
	if not self._matchService:isActive() then
		return false
	end

	local humanCarrier = self._matchService:getCarrier()
	if humanCarrier and player == humanCarrier then
		return false
	end

	if self:_isOnCooldown(player) or self:isDashing(player) or self:isCharging(player) then
		return false
	end

	return self:_getRoot(player) ~= nil
end

function TackleService:_lockMovement(player: Player, duration: number)
	local humanoid = self:_getHumanoid(player)
	if not humanoid then
		return
	end

	if not self._savedWalkSpeeds[player.UserId] then
		self._savedWalkSpeeds[player.UserId] = humanoid.WalkSpeed
	end

	humanoid.WalkSpeed = 0

	task.delay(duration, function()
		if humanoid.Parent then
			humanoid.WalkSpeed = self._savedWalkSpeeds[player.UserId] or Config.DEFAULT_WALK_SPEED
		end
		self._savedWalkSpeeds[player.UserId] = nil
	end)
end

function TackleService:_clearDashState(player: Player)
	local dash = self._activeDashes[player.UserId]
	if not dash then
		return
	end

	if dash.connection then
		dash.connection:Disconnect()
	end

	self._activeDashes[player.UserId] = nil
end

function TackleService:_stopDash(player: Player, applyCooldown: boolean)
	self:_clearDashState(player)

	local root = self:_getRoot(player)
	if root then
		self:_zeroVelocity(root)
	end

	local character = player.Character
	if character then
		AnimationUtil.stopTackleDive(character)
	end

	if applyCooldown then
		self:_setCooldown(player)
	end

	Remotes.tackleDashEnded():FireAllClients(player)
end

function TackleService:_stopDashOnHit(player: Player, direction: Vector3, victimCharacter: Model)
	local dash = self._activeDashes[player.UserId]
	local charge01 = dash and dash.charge01 or 0
	local humanCarrier = self._matchService:getCarrier()
	local carrierCharacter = self._matchService:getCarrierCharacter()
	local tacklerRoot = self:_getRoot(player)
	local victimRoot = self:_getCharacterRoot(victimCharacter)

	self:_clearDashState(player)

	local tacklerCharacter = player.Character
	if tacklerCharacter then
		AnimationUtil.stopTackleDive(tacklerCharacter)
	end

	self:_lockMovement(player, Config.DASH_STOP_ON_HIT)
	self:_setCooldown(player)

	if victimRoot and tacklerRoot then
		self:_snapTacklerToCarrier(tacklerRoot, victimRoot)
		local hitPosition = (tacklerRoot.Position + victimRoot.Position) / 2
		local isCarrierHit = victimCharacter == carrierCharacter

		if isCarrierHit and humanCarrier and self:isTruckContesting(humanCarrier) then
			self:_resolveDashContest(humanCarrier, player, charge01, direction, hitPosition)
		elseif isCarrierHit and humanCarrier and self:isShedActive(humanCarrier) then
			local window = self._shedWindows[humanCarrier.UserId]
			local dodgeType = if window then window.dodgeType else "Juke"
			local jukeSide = if window then window.jukeSide else 0
			self._shedWindows[humanCarrier.UserId] = nil
			self:_setShedCooldown(humanCarrier)
			self._matchService:onTackleShed(humanCarrier, player, direction, dodgeType, jukeSide, nil)
			Remotes.tackleShed():FireAllClients(player, humanCarrier, hitPosition, dodgeType)
		elseif isCarrierHit then
			self._matchService:onTackleHit(player, victimCharacter, direction, charge01)
			Remotes.tackleHit():FireAllClients(player, humanCarrier, hitPosition, charge01)
			Remotes.tackleVictimFlash():FireClient(player, victimCharacter)
		else
			self._matchService:onPushHit(player, victimCharacter, direction, charge01)
			local victimPlayer = Players:GetPlayerFromCharacter(victimCharacter)
			Remotes.tackleHit():FireAllClients(player, victimPlayer, hitPosition, charge01)
			Remotes.tackleVictimFlash():FireClient(player, victimCharacter)
		end
	end

	Remotes.tackleDashEnded():FireAllClients(player)
end

function TackleService:isDashing(player: Player): boolean
	return self._activeDashes[player.UserId] ~= nil
end

function TackleService:isCharging(player: Player): boolean
	return self._activeCharges[player.UserId] ~= nil
end

function TackleService:cancelCharge(player: Player)
	local charge = self._activeCharges[player.UserId]
	if not charge then
		return
	end

	if charge.monitorConnection then
		charge.monitorConnection:Disconnect()
	end

	self._activeCharges[player.UserId] = nil
end

function TackleService:cancelAllCharges()
	for _, player in Players:GetPlayers() do
		self:cancelCharge(player)
	end
end

function TackleService:beginCharge(player: Player)
	if not self:_canTackle(player) then
		return
	end

	local root = self:_getRoot(player)
	if not root then
		return
	end

	local direction = self:_getFlatLookVector(root)
	local releaseToken = {}

	self._activeCharges[player.UserId] = {
		startedAt = os.clock(),
		direction = direction,
		releaseToken = releaseToken,
		monitorConnection = nil,
	}

	Remotes.tackleChargeStarted():FireAllClients(player)

	local monitorConnection = RunService.Heartbeat:Connect(function()
		local activeCharge = self._activeCharges[player.UserId]
		if not activeCharge then
			return
		end

		if not self._matchService:isActive() then
			self:cancelCharge(player)
			return
		end

		if self._matchService:getCarrier() == player then
			self:cancelCharge(player)
			return
		end

		if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
			self:cancelCharge(player)
		end
	end)

	self._activeCharges[player.UserId].monitorConnection = monitorConnection

	task.delay(Config.CHARGE_MAX_TIME, function()
		local activeCharge = self._activeCharges[player.UserId]
		if activeCharge and activeCharge.releaseToken == releaseToken then
			self:releaseCharge(player)
		end
	end)

	if self._pendingRelease[player.UserId] then
		self._pendingRelease[player.UserId] = nil
		self:releaseCharge(player)
	end
end

function TackleService:releaseCharge(player: Player)
	local charge = self._activeCharges[player.UserId]
	if not charge then
		return
	end

	local chargeTime = os.clock() - charge.startedAt
	local charge01 = ChargeUtil.getCharge01(chargeTime)

	local root = self:_getRoot(player)
	local direction = if root then self:_getFlatLookVector(root) else charge.direction
	if root then
		direction = self:_getAimAssistedDirection(direction, root, player)
	end

	if charge.monitorConnection then
		charge.monitorConnection:Disconnect()
	end

	self._activeCharges[player.UserId] = nil

	self:startDash(player, direction, charge01)
end

function TackleService:_beginBurst(player: Player)
	local root = self:_getRoot(player)
	local dash = self._activeDashes[player.UserId]
	if not root or not dash then
		return
	end

	dash.inWindup = false
	dash.endsAt = os.clock() + Config.DASH_DURATION

	root.AssemblyLinearVelocity = dash.direction * dash.dashSpeed

	dash.connection = RunService.Heartbeat:Connect(function()
		if not self._activeDashes[player.UserId] then
			return
		end

		local currentDash = self._activeDashes[player.UserId]
		local currentRoot = self:_getRoot(player)
		if not currentRoot then
			self:_stopDash(player, true)
			return
		end

		if os.clock() >= currentDash.endsAt then
			self:_stopDash(player, true)
			return
		end

		local targetRoot = currentDash.targetRoot
		if not targetRoot then
			targetRoot = self:_getNearestTackleTargetRoot(currentRoot, player)
		end
		if targetRoot then
			currentDash.direction = self:_getHomingDirection(
				currentDash.initialDirection,
				currentDash.direction,
				currentRoot,
				targetRoot
			)
		end

		currentRoot.AssemblyLinearVelocity = currentDash.direction * currentDash.dashSpeed

		local tacklerCharacter = player.Character
		local victimCharacter = if tacklerCharacter
			then self:_resolveDashHitTarget(tacklerCharacter, player, currentDash)
			else nil

		if victimCharacter then
			self:_stopDashOnHit(player, currentDash.direction, victimCharacter)
		end
	end)
end

function TackleService:startDash(player: Player, direction: Vector3, charge01: number)
	if not self._matchService:isActive() then
		return
	end

	if not self:_canTackle(player) then
		return
	end

	local humanCarrier = self._matchService:getCarrier()
	if humanCarrier and player == humanCarrier then
		return
	end

	if self:_isOnCooldown(player) or self:isDashing(player) then
		return
	end

	local root = self:_getRoot(player)
	if not root then
		return
	end

	local targetRoot = self:_getNearestTackleTargetRoot(root, player)
	local targetCharacter = targetRoot and targetRoot:FindFirstAncestorOfClass("Model")
	local dashSpeed = ChargeUtil.getDashSpeed(charge01)

	self._activeDashes[player.UserId] = {
		connection = nil,
		direction = direction,
		initialDirection = direction,
		endsAt = 0,
		inWindup = true,
		dashSpeed = dashSpeed,
		charge01 = charge01,
		targetCharacter = targetCharacter,
		targetRoot = targetRoot,
	}

	local character = player.Character
	if character then
		AnimationUtil.playTackleDive(character)
	end

	Remotes.tackleDashStarted():FireAllClients(player, charge01)
	self:_lockMovement(player, Config.DASH_WINDUP + Config.DASH_DURATION + Config.DASH_STOP_ON_HIT)
	self:_zeroVelocity(root)

	task.delay(Config.DASH_WINDUP, function()
		if self._activeDashes[player.UserId] then
			self:_beginBurst(player)
		end
	end)
end

return TackleService
