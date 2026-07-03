local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local SPRINT_PHASE_ATTRIBUTE = "TackleBallSprintPhase"
local SPRINT_PROGRESS_ATTRIBUTE = "TackleBallSprintProgress"

type SprintSession = {}

local SprintService = {}
SprintService._matchService = nil
SprintService._tackleService = nil
SprintService._active = {} :: { [number]: SprintSession }
SprintService._fuel = {} :: { [number]: number }
SprintService._roundWasActive = false
SprintService._lastUpdateAt = os.clock()
SprintService._heartbeatConnection = nil :: RBXScriptConnection?

function SprintService:init(matchService, tackleService)
	self._matchService = matchService
	self._tackleService = tackleService

	self._heartbeatConnection = RunService.Heartbeat:Connect(function()
		self:_update()
	end)

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			self:_syncPlayerCharacter(player)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self._active[player.UserId] = nil
		self._fuel[player.UserId] = nil
	end)
end

function SprintService:_getHumanoid(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

function SprintService:_getFuel(player: Player): number
	local fuel = self._fuel[player.UserId]
	if fuel == nil then
		fuel = 1
		self._fuel[player.UserId] = fuel
	end
	return fuel
end

function SprintService:_setFuel(player: Player, fuel: number)
	self._fuel[player.UserId] = math.clamp(fuel, 0, 1)
end

function SprintService:_syncSprintAttributes(player: Player, phase: string, progress: number)
	local character = player.Character
	if not character then
		return
	end

	character:SetAttribute(SPRINT_PHASE_ATTRIBUTE, phase)
	character:SetAttribute(SPRINT_PROGRESS_ATTRIBUTE, math.clamp(progress, 0, 1))
end

function SprintService:_clearSprintAttributes(player: Player)
	local character = player.Character
	if not character then
		return
	end

	character:SetAttribute(SPRINT_PHASE_ATTRIBUTE, nil)
	character:SetAttribute(SPRINT_PROGRESS_ATTRIBUTE, nil)
end

function SprintService:_syncPlayerCharacter(player: Player)
	if not self._matchService:isActive() then
		self:_clearSprintAttributes(player)
		return
	end

	local fuel = self:_getFuel(player)
	local phase = if self._active[player.UserId] then "active" else "idle"
	self:_syncSprintAttributes(player, phase, fuel)

	if self._active[player.UserId] then
		local humanoid = self:_getHumanoid(player)
		if humanoid then
			humanoid.WalkSpeed = Config.SPRINT_MAX_SPEED
		end
	end
end

function SprintService:_isMovementBlocked(player: Player): boolean
	local character = player.Character
	if not character then
		return true
	end

	if character:GetAttribute("TackleBallRagdollActive") == true then
		return true
	end

	if character:GetAttribute("TackleBallPendingDeath") == true then
		return true
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return true
	end

	if not self._matchService:isActive() then
		return true
	end

	if not self._tackleService then
		return false
	end

	return self._tackleService:isDashing(player)
		or self._tackleService:isCharging(player)
		or self._tackleService:isTruckDashing(player)
		or self._tackleService:isTruckCharging(player)
		or self._matchService:isCarrierShedding(player)
end

function SprintService:_endSprint(player: Player, restoreWalkSpeed: boolean?)
	self._active[player.UserId] = nil

	local character = player.Character
	local humanoid = self:_getHumanoid(player)
	local isRagdolled = character and character:GetAttribute("TackleBallRagdollActive") == true

	if isRagdolled and humanoid then
		humanoid.WalkSpeed = 0
	elseif restoreWalkSpeed ~= false and humanoid then
		humanoid.WalkSpeed = Config.DEFAULT_WALK_SPEED
	end

	if self._matchService:isActive() then
		self:_syncSprintAttributes(player, "idle", self:_getFuel(player))
	else
		self:_clearSprintAttributes(player)
	end
end

function SprintService:activate(player: Player)
	if self._active[player.UserId] then
		self:_endSprint(player)
		return
	end

	if self:_isMovementBlocked(player) then
		return
	end

	if self:_getFuel(player) <= 0 then
		return
	end

	if not self:_getHumanoid(player) then
		return
	end

	self._active[player.UserId] = {}
	self:_syncSprintAttributes(player, "active", self:_getFuel(player))

	local humanoid = self:_getHumanoid(player)
	if humanoid then
		humanoid.WalkSpeed = Config.SPRINT_MAX_SPEED
	end
end

function SprintService:_updateActive(player: Player, dt: number)
	if self:_isMovementBlocked(player) then
		local character = player.Character
		local humanoid = self:_getHumanoid(player)
		if character and humanoid and character:GetAttribute("TackleBallRagdollActive") == true then
			humanoid.WalkSpeed = 0
		end
		self:_endSprint(player, false)
		return
	end

	local fuel = self:_getFuel(player) - dt / Config.SPRINT_DURATION
	if fuel <= 0 then
		self:_setFuel(player, 0)
		self:_endSprint(player)
		return
	end

	self:_setFuel(player, fuel)

	local humanoid = self:_getHumanoid(player)
	if humanoid then
		humanoid.WalkSpeed = Config.SPRINT_MAX_SPEED
	end

	self:_syncSprintAttributes(player, "active", fuel)
end

function SprintService:_updateIdle(player: Player, dt: number)
	local fuel = self:_getFuel(player)
	if fuel >= 1 then
		self:_syncSprintAttributes(player, "idle", 1)
		return
	end

	fuel = math.min(1, fuel + dt / Config.SPRINT_REGEN_DURATION)
	self:_setFuel(player, fuel)
	self:_syncSprintAttributes(player, "idle", fuel)
end

function SprintService:_onRoundEnd()
	for _, player in Players:GetPlayers() do
		if self._active[player.UserId] then
			self:_endSprint(player)
		else
			self:_clearSprintAttributes(player)
		end
	end
end

function SprintService:_onRoundStart()
	for _, player in Players:GetPlayers() do
		self._fuel[player.UserId] = 1
		self._active[player.UserId] = nil

		local humanoid = self:_getHumanoid(player)
		if humanoid then
			humanoid.WalkSpeed = Config.DEFAULT_WALK_SPEED
		end

		self:_syncSprintAttributes(player, "idle", 1)
	end
end

function SprintService:_update()
	local now = os.clock()
	local dt = now - self._lastUpdateAt
	self._lastUpdateAt = now
	if dt <= 0 then
		return
	end

	local roundActive = self._matchService:isActive()
	if not roundActive then
		if self._roundWasActive then
			self:_onRoundEnd()
		end
		self._roundWasActive = false
		return
	end

	if not self._roundWasActive then
		self:_onRoundStart()
	end
	self._roundWasActive = true

	local activeUserIds: { [number]: boolean } = {}
	for userId in self._active do
		activeUserIds[userId] = true
		local activePlayer = Players:GetPlayerByUserId(userId)
		if activePlayer then
			self:_updateActive(activePlayer, dt)
		else
			self._active[userId] = nil
		end
	end

	for _, player in Players:GetPlayers() do
		if not activeUserIds[player.UserId] then
			self:_updateIdle(player, dt)
		end
	end
end

return SprintService
