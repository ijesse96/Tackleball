local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local ChargeUtil = require(ReplicatedStorage.Shared.ChargeUtil)
local GhostUtil = require(script.Parent.GhostUtil)
local LegacyRigUtil = require(script.Parent.LegacyRigUtil)
local RagdollUtil = require(script.Parent.RagdollUtil)

local PENDING_DEATH_ATTRIBUTE = "TackleBallPendingDeath"
local SETUP_ATTRIBUTE = "TackleBallHealthSetup"
local DEAD_ATTRIBUTE = "TackleBallDead"
local CORPSE_PART_ATTRIBUTE = "TackleBallCorpsePart"

local HealthService = {}
HealthService._onCharacterDeath = nil :: ((character: Model) -> ())?
HealthService._onNpcRespawn = nil :: ((character: Model) -> ())?
HealthService._shouldDeferRespawn = nil :: (() -> boolean)?

function HealthService:setDeathHandler(handler: (character: Model) -> ())
	self._onCharacterDeath = handler
end

function HealthService:setNpcRespawnHandler(handler: (character: Model) -> ())
	self._onNpcRespawn = handler
end

function HealthService:setRespawnDefer(handler: () -> boolean)
	self._shouldDeferRespawn = handler
end

local function waitForRespawnAllowed(self: HealthService, player: Player)
	while self._shouldDeferRespawn and self._shouldDeferRespawn() do
		if not player.Parent then
			return false
		end
		task.wait(0.25)
	end

	return player.Parent ~= nil
end

function HealthService:setupCharacter(character: Model)
	if not character or not character.Parent then
		return
	end

	if character:GetAttribute(SETUP_ATTRIBUTE) then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	character:SetAttribute(SETUP_ATTRIBUTE, true)
	character:SetAttribute(PENDING_DEATH_ATTRIBUTE, nil)
	character:SetAttribute(DEAD_ATTRIBUTE, nil)

	humanoid.MaxHealth = Config.MAX_HEALTH
	humanoid.Health = Config.MAX_HEALTH
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

	LegacyRigUtil.ensureMotor6DRig(character)
end

function HealthService:resetCharacterHealth(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	character:SetAttribute(PENDING_DEATH_ATTRIBUTE, nil)
	character:SetAttribute(DEAD_ATTRIBUTE, nil)
	humanoid.MaxHealth = Config.MAX_HEALTH
	humanoid.Health = Config.MAX_HEALTH
	humanoid.BreakJointsOnDeath = false
end

function HealthService:applyTackleDamage(character: Model, charge01: number): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end

	local damage = ChargeUtil.getTackleDamage(charge01)
	local lethal = humanoid.Health - damage <= 0

	if lethal then
		character:SetAttribute(PENDING_DEATH_ATTRIBUTE, true)
		local damageToApply = math.max(humanoid.Health - 1, 0)
		if damageToApply > 0 then
			humanoid:TakeDamage(damageToApply)
		end
		return true
	end

	humanoid:TakeDamage(damage)
	return false
end

function HealthService:isPendingDeath(character: Model): boolean
	return character:GetAttribute(PENDING_DEATH_ATTRIBUTE) == true
end

function HealthService:isAliveCombatCharacter(character: Model): boolean
	if not character or not character.Parent then
		return false
	end

	if character:GetAttribute(DEAD_ATTRIBUTE) == true then
		return false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

function HealthService:corpsifyCharacter(character: Model)
	character:SetAttribute(DEAD_ATTRIBUTE, true)
	character:SetAttribute("TackleBallRagdollActive", nil)

	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant:SetAttribute(CORPSE_PART_ATTRIBUTE, true)
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
		end
	end
end

function HealthService:schedulePostDeathRespawn(character: Model, onDeathCallback: (() -> ())?)
	task.delay(Config.DEATH_RESPAWN_DELAY, function()
		if onDeathCallback then
			onDeathCallback()
		end

		local player = Players:GetPlayerFromCharacter(character)
		if player and player.Parent then
			if character.Parent then
				character:Destroy()
			end

			if not waitForRespawnAllowed(self, player) then
				return
			end

			player:SetAttribute("TackleBallRespawnAt", nil)
			player:LoadCharacter()
			return
		end

		if character:GetAttribute("TackleBallDummy") == true and self._onNpcRespawn then
			self._onNpcRespawn(character)
			return
		end

		if character.Parent and character:GetAttribute(DEAD_ATTRIBUTE) == true then
			character:Destroy()
		end
	end)
end

function HealthService:shatterDeath(character: Model, onDeathCallback: (() -> ())?)
	if not character or not character.Parent then
		if onDeathCallback then
			onDeathCallback()
		end
		return
	end

	character:SetAttribute(PENDING_DEATH_ATTRIBUTE, nil)

	GhostUtil.spawn(character)

	if character:GetAttribute("TackleBallRagdollActive") then
		RagdollUtil.disable(character)
		character:SetAttribute("TackleBallRagdollActive", nil)
	end

	self:corpsifyCharacter(character)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.BreakJointsOnDeath = true
		humanoid.Health = 0
	end

	if self._onCharacterDeath then
		self._onCharacterDeath(character)
	end

	local player = Players:GetPlayerFromCharacter(character)
	if player then
		player:SetAttribute("TackleBallRespawnAt", Workspace:GetServerTimeNow() + Config.DEATH_RESPAWN_DELAY)
	end

	self:schedulePostDeathRespawn(character, onDeathCallback)
end

function HealthService:resetAllHealth()
	for _, player in Players:GetPlayers() do
		if player.Character then
			self:resetCharacterHealth(player.Character)
		end
	end

	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("Model") and descendant:GetAttribute("TackleBallDummy") == true then
			self:resetCharacterHealth(descendant)
		end
	end
end

return HealthService
