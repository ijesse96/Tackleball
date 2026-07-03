local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local GameMode = require(ReplicatedStorage.Shared.GameMode)
local HealthService = require(script.Parent.HealthService)
local LegacyRigUtil = require(script.Parent.LegacyRigUtil)

type DummyEntry = {
	model: Model,
	profileIndex: number,
	lastTackleAt: number,
	lastMoveAt: number,
}

local DummyTacklerService = {}
DummyTacklerService._templates = {} :: { [number]: Model }
DummyTacklerService._dummies = {} :: { DummyEntry }
DummyTacklerService._attackLoopRunning = false
DummyTacklerService._tackleService = nil
DummyTacklerService._matchService = nil
DummyTacklerService._ballService = nil
DummyTacklerService._carrierDummy = nil :: Model?
DummyTacklerService._carrierEndzoneTarget = nil :: Vector3?

local function getEndzoneCenter(endzoneName: string): Vector3?
	if not GameMode.usesStadiumLayout() then
		local field = Workspace:FindFirstChild(Config.FIELD_FOLDER_NAME)
		if field then
			local endzone = field:FindFirstChild(endzoneName)
			if endzone and endzone:IsA("BasePart") then
				return endzone.Position
			end
		end
	end

	for _, descendant in Workspace:GetDescendants() do
		if descendant.Name == endzoneName then
			if descendant:IsA("BasePart") then
				return descendant.Position
			end
			if descendant:IsA("Model") then
				return select(1, descendant:GetBoundingBox()).Position
			end
		end
	end

	return nil
end

local function pickEndzoneTarget(fromPosition: Vector3): Vector3
	local endzoneNames = GameMode.getEndzoneNames()
	local endzoneA = getEndzoneCenter(endzoneNames[1])
	local endzoneB = getEndzoneCenter(endzoneNames[2])
	if endzoneA and endzoneB then
		local distA = (Vector3.new(fromPosition.X, 0, fromPosition.Z) - Vector3.new(endzoneA.X, 0, endzoneA.Z)).Magnitude
		local distB = (Vector3.new(fromPosition.X, 0, fromPosition.Z) - Vector3.new(endzoneB.X, 0, endzoneB.Z)).Magnitude
		return if distA <= distB then endzoneA else endzoneB
	end

	return endzoneA or endzoneB or fromPosition + Vector3.new(0, 0, 40)
end

local function getProfile(index: number)
	local squad = Config.DUMMY_TACKLER_SQUAD
	if #squad == 0 then
		return {
			name = Config.DUMMY_TACKLER_NAME,
			charge01 = Config.DUMMY_TACKLER_CHARGE01,
			headColor = Color3.fromRGB(200, 80, 80),
			torsoColor = Color3.fromRGB(180, 60, 60),
		}
	end

	return squad[((index - 1) % #squad) + 1]
end

local function getTemplate(profileIndex: number): Model
	if DummyTacklerService._templates[profileIndex] then
		LegacyRigUtil.ensureMotor6DRig(DummyTacklerService._templates[profileIndex])
		return DummyTacklerService._templates[profileIndex]
	end

	local profile = getProfile(profileIndex)
	local description = Instance.new("HumanoidDescription")
	description.HeadColor = profile.headColor
	description.TorsoColor = profile.torsoColor
	description.LeftArmColor = profile.torsoColor
	description.RightArmColor = profile.torsoColor
	description.LeftLegColor = profile.torsoColor:Lerp(Color3.new(0, 0, 0), 0.15)
	description.RightLegColor = profile.torsoColor:Lerp(Color3.new(0, 0, 0), 0.15)

	local template = Players:CreateHumanoidModelFromDescriptionAsync(
		description,
		Enum.HumanoidRigType.R15,
		Enum.AssetTypeVerification.ClientOnly
	)
	template.Name = `DummyTacklerTemplate_{profileIndex}`
	template.Parent = ServerStorage
	LegacyRigUtil.ensureMotor6DRig(template)
	DummyTacklerService._templates[profileIndex] = template
	return template
end

function DummyTacklerService:getDummyCharge01(dummy: Model): number
	local charge01 = dummy:GetAttribute("DummyTackleCharge01")
	if typeof(charge01) == "number" then
		return charge01
	end

	return Config.DUMMY_TACKLER_CHARGE01
end

function DummyTacklerService:getDummies(): { Model }
	local models = {}
	for _, entry in self._dummies do
		if entry.model.Parent and HealthService:isAliveCombatCharacter(entry.model) then
			table.insert(models, entry.model)
		end
	end

	return models
end

function DummyTacklerService:getCarrierDummy(): Model?
	return self._carrierDummy
end

function DummyTacklerService:setCarrierDummy(dummy: Model?)
	if self._carrierDummy and self._carrierDummy ~= dummy then
		self._carrierDummy:SetAttribute("TackleBallDummyCarrier", nil)
	end

	self._carrierDummy = dummy
	if dummy then
		dummy:SetAttribute("TackleBallDummyCarrier", true)
		local root = dummy:FindFirstChild("HumanoidRootPart") :: BasePart?
		if GameMode.isTeamsMode() and self._matchService and self._matchService.getTeamService then
			local teamService = self._matchService:getTeamService()
			local team = teamService and teamService:getTeam(dummy)
			if team and root then
				local goalEndzone = teamService:getGoalEndzone(team)
				local goalCenter = getEndzoneCenter(goalEndzone)
				self._carrierEndzoneTarget = goalCenter or pickEndzoneTarget(root.Position)
			elseif root then
				self._carrierEndzoneTarget = pickEndzoneTarget(root.Position)
			end
		elseif root then
			self._carrierEndzoneTarget = pickEndzoneTarget(root.Position)
		end
	else
		self._carrierEndzoneTarget = nil
	end
end

function DummyTacklerService:clearCarrierDummy()
	self:setCarrierDummy(nil)
end

function DummyTacklerService:isNpcMatchMode(): boolean
	return GameMode.isSoloMode()
end

function DummyTacklerService:getDummy(): Model?
	local dummies = self:getDummies()
	return dummies[1]
end

function DummyTacklerService:_findEntry(model: Model): DummyEntry?
	for _, entry in self._dummies do
		if entry.model == model then
			return entry
		end
	end

	return nil
end

function DummyTacklerService:_setChaseEnabled(model: Model, enabled: boolean)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	if enabled then
		humanoid.WalkSpeed = Config.DUMMY_TACKLER_CHASE_SPEED
		humanoid.AutoRotate = true
	else
		humanoid.WalkSpeed = 0
		humanoid:MoveTo(model:GetPivot().Position)
		humanoid.AutoRotate = false
	end
end

function DummyTacklerService:_getSpawnCFrame(carrierRoot: BasePart, profileIndex: number, squadSize: number): CFrame
	local flatLook = Vector3.new(carrierRoot.CFrame.LookVector.X, 0, carrierRoot.CFrame.LookVector.Z)
	if flatLook.Magnitude < 0.01 then
		flatLook = Vector3.new(0, 0, -1)
	else
		flatLook = flatLook.Unit
	end

	local flatRight = Vector3.new(carrierRoot.CFrame.RightVector.X, 0, carrierRoot.CFrame.RightVector.Z)
	if flatRight.Magnitude < 0.01 then
		flatRight = Vector3.new(1, 0, 0)
	else
		flatRight = flatRight.Unit
	end

	local arcRad = math.rad(Config.DUMMY_TACKLER_SPAWN_ARC_DEGREES)
	local slotT = if squadSize <= 1 then 0.5 else (profileIndex - 1) / (squadSize - 1)
	local angle = -arcRad * 0.5 + arcRad * slotT
	local direction = (flatLook * math.cos(angle) + flatRight * math.sin(angle)).Unit
	local distance = Config.DUMMY_TACKLER_SPAWN_DISTANCE + ((profileIndex - 1) % 3) * 4
	local spawnPos = carrierRoot.Position + direction * distance + Vector3.new(0, 3, 0)

	return CFrame.lookAt(spawnPos, Vector3.new(carrierRoot.Position.X, spawnPos.Y, carrierRoot.Position.Z))
end

function DummyTacklerService:_getFlatDistance(from: Vector3, to: Vector3): number
	local delta = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	return delta.Magnitude
end

function DummyTacklerService:_spawnOne(profileIndex: number, carrierRoot: BasePart, squadSize: number): Model?
	local profile = getProfile(profileIndex)

	local ok, dummy = pcall(function()
		local model = getTemplate(profileIndex):Clone()
		model.Name = profile.name
		model:SetAttribute("TackleBallDummy", true)
		model:SetAttribute("TackleBallDummyTackler", true)
		model:SetAttribute("DummyTackleCharge01", profile.charge01)
		model:SetAttribute("DummyTackleProfileIndex", profileIndex)

		local humanoid = model:FindFirstChildOfClass("Humanoid")
		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not humanoid or not root then
			error("Dummy tackler template is missing Humanoid or HumanoidRootPart")
		end

		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.DisplayName = profile.name

		HealthService:setupCharacter(model)

		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				pcall(function()
					descendant:SetNetworkOwner(nil)
				end)
			end
		end

		model:PivotTo(self:_getSpawnCFrame(carrierRoot, profileIndex, squadSize))
		model.Parent = workspace

		return model
	end)

	if not ok or not dummy then
		warn(`TackleBall: failed to spawn dummy tackler ({dummy})`)
		return nil
	end

	table.insert(self._dummies, {
		model = dummy,
		profileIndex = profileIndex,
		lastTackleAt = 0,
		lastMoveAt = 0,
	})

	self:_setChaseEnabled(dummy, true)
	return dummy
end

function DummyTacklerService:_spawnOneForEntry(
	entry: DummyEntry,
	profileIndex: number,
	carrierRoot: BasePart,
	squadSize: number
): Model?
	local profile = getProfile(profileIndex)

	local ok, dummy = pcall(function()
		local model = getTemplate(profileIndex):Clone()
		model.Name = profile.name
		model:SetAttribute("TackleBallDummy", true)
		model:SetAttribute("TackleBallDummyTackler", true)
		model:SetAttribute("DummyTackleCharge01", profile.charge01)
		model:SetAttribute("DummyTackleProfileIndex", profileIndex)

		local humanoid = model:FindFirstChildOfClass("Humanoid")
		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not humanoid or not root then
			error("Dummy tackler template is missing Humanoid or HumanoidRootPart")
		end

		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.DisplayName = profile.name

		HealthService:setupCharacter(model)

		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				pcall(function()
					descendant:SetNetworkOwner(nil)
				end)
			end
		end

		model:PivotTo(self:_getSpawnCFrame(carrierRoot, profileIndex, squadSize))
		model.Parent = workspace

		return model
	end)

	if not ok or not dummy then
		warn(`TackleBall: failed to respawn dummy tackler ({dummy})`)
		return nil
	end

	entry.model = dummy
	entry.profileIndex = profileIndex
	self:_setChaseEnabled(dummy, true)
	return dummy
end

function DummyTacklerService:_spawnOneAtCFrame(profileIndex: number, spawnCFrame: CFrame): Model?
	local profile = getProfile(profileIndex)

	local ok, dummy = pcall(function()
		local model = getTemplate(profileIndex):Clone()
		model.Name = profile.name
		model:SetAttribute("TackleBallDummy", true)
		model:SetAttribute("TackleBallDummyTackler", true)
		model:SetAttribute("DummyTackleCharge01", profile.charge01)
		model:SetAttribute("DummyTackleProfileIndex", profileIndex)

		local humanoid = model:FindFirstChildOfClass("Humanoid")
		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not humanoid or not root then
			error("Dummy tackler template is missing Humanoid or HumanoidRootPart")
		end

		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.DisplayName = profile.name

		HealthService:setupCharacter(model)

		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				pcall(function()
					descendant:SetNetworkOwner(nil)
				end)
			end
		end

		model:PivotTo(spawnCFrame)
		model.Parent = workspace

		return model
	end)

	if not ok or not dummy then
		warn(`TackleBall: failed to spawn dummy tackler ({dummy})`)
		return nil
	end

	table.insert(self._dummies, {
		model = dummy,
		profileIndex = profileIndex,
		lastTackleAt = 0,
		lastMoveAt = 0,
	})

	self:_setChaseEnabled(dummy, true)
	return dummy
end

function DummyTacklerService:_getTeamsSpawnCFrame(team: string, slotIndex: number, teamSize: number): CFrame
	local floorY = self._matchService:_getArenaFloorTopY()
	local center = Config.ARENA_SPAWN_CENTER
	local xOffset = if team == Config.TEAM_A_NAME then -35 else 35
	local zSpread = 24
	local zStep = if teamSize <= 1 then 0 else zSpread / (teamSize - 1)
	local z = -zSpread * 0.5 + zStep * (slotIndex - 1)
	local spawnPos = Vector3.new(center.X + xOffset, floorY + Config.ARENA_SPAWN_HEIGHT_OFFSET, center.Z + z)
	local lookAt = Vector3.new(center.X, spawnPos.Y, center.Z)
	return CFrame.lookAt(spawnPos, lookAt)
end

function DummyTacklerService:_getPassTestTeammateSpawnCFrame(slotIndex: number, total: number): CFrame
	local floorY = self._matchService:_getArenaFloorTopY()
	local center = Config.ARENA_SPAWN_CENTER
	local forwardDistance = 28
	local lateralSpread = 22
	local lateralStep = if total <= 1 then 0 else lateralSpread / (total - 1)
	local lateral = -lateralSpread * 0.5 + lateralStep * (slotIndex - 1)
	local spawnPos = Vector3.new(
		center.X + lateral,
		floorY + Config.ARENA_SPAWN_HEIGHT_OFFSET,
		center.Z + forwardDistance
	)
	local lookAt = Vector3.new(center.X, spawnPos.Y, center.Z)
	return CFrame.lookAt(spawnPos, lookAt)
end

function DummyTacklerService:spawnTeamsRoster(blueCount: number, redCount: number): ({ Model }, { Model })
	self:despawn()

	local blueDummies = {}
	local redDummies = {}
	local passTestLayout = Config.TEAMS_PASS_TEST_MODE and redCount == 0

	for slotIndex = 1, blueCount do
		local spawnCFrame = if passTestLayout
			then self:_getPassTestTeammateSpawnCFrame(slotIndex, math.max(blueCount, 1))
			else self:_getTeamsSpawnCFrame(Config.TEAM_A_NAME, slotIndex, math.max(blueCount, 1))
		local dummy = self:_spawnOneAtCFrame(slotIndex, spawnCFrame)
		if dummy then
			if passTestLayout then
				self:_setChaseEnabled(dummy, false)
			end
			table.insert(blueDummies, dummy)
		end
	end

	for slotIndex = 1, redCount do
		local spawnCFrame = self:_getTeamsSpawnCFrame(Config.TEAM_B_NAME, slotIndex, math.max(redCount, 1))
		local dummy = self:_spawnOneAtCFrame(blueCount + slotIndex, spawnCFrame)
		if dummy then
			table.insert(redDummies, dummy)
		end
	end

	return blueDummies, redDummies
end

function DummyTacklerService:spawnArenaRoster(totalFieldPlayers: number, humanSlotCount: number): { Model }
	self:despawn()

	local spawned = {}
	local botIndex = 0

	for slotIndex = humanSlotCount + 1, totalFieldPlayers do
		botIndex += 1
		local spawnCFrame = self._matchService:_getArenaSpawnCFrame(slotIndex, totalFieldPlayers)
		local dummy = self:_spawnOneAtCFrame(botIndex, spawnCFrame)
		if dummy then
			table.insert(spawned, dummy)
		end
	end

	return spawned
end

function DummyTacklerService:spawnFacingCarrier(carrierRoot: BasePart): { Model }
	self:despawn()

	local squad = Config.DUMMY_TACKLER_SQUAD
	local squadSize = if #squad > 0 then #squad else 1
	local spawned = {}

	for profileIndex = 1, squadSize do
		local dummy = self:_spawnOne(profileIndex, carrierRoot, squadSize)
		if dummy then
			table.insert(spawned, dummy)
		end
	end

	return spawned
end

function DummyTacklerService:respawnDummy(dummy: Model, carrierRoot: BasePart)
	local entry = self:_findEntry(dummy)
	local profileIndex = if entry then entry.profileIndex else dummy:GetAttribute("DummyTackleProfileIndex") or 1
	if typeof(profileIndex) ~= "number" then
		profileIndex = 1
	end

	local squadSize = math.max(#self._dummies, #Config.DUMMY_TACKLER_SQUAD, 1)
	if entry then
		entry.lastTackleAt = 0
		entry.lastMoveAt = 0
		if dummy.Parent and HealthService:isAliveCombatCharacter(dummy) then
			dummy:PivotTo(self:_getSpawnCFrame(carrierRoot, profileIndex, squadSize))
			self:_setChaseEnabled(dummy, true)
			return
		end

		if dummy.Parent then
			dummy:Destroy()
		end

		local replacement = self:_spawnOneForEntry(entry, profileIndex, carrierRoot, squadSize)
		if replacement then
			return
		end
	end

	self:_spawnOne(profileIndex, carrierRoot, squadSize)
end

function DummyTacklerService:removeDummy(dummy: Model)
	if dummy == self._carrierDummy then
		self:clearCarrierDummy()
	end

	for index, entry in self._dummies do
		if entry.model == dummy then
			table.remove(self._dummies, index)
			break
		end
	end

	if dummy.Parent then
		dummy:Destroy()
	end
end

function DummyTacklerService:respawnFacingCarrier(carrierRoot: BasePart)
	self:spawnFacingCarrier(carrierRoot)
end

function DummyTacklerService:despawn()
	self:despawnExcept(nil)
end

function DummyTacklerService:despawnExcept(keepModel: Model?)
	self:stopAttackLoop()

	local kept = {} :: { DummyEntry }
	for _, entry in self._dummies do
		if keepModel and entry.model == keepModel then
			table.insert(kept, entry)
			continue
		end

		if entry.model.Parent then
			entry.model:Destroy()
		end
	end

	self._dummies = kept

	if not keepModel or self._carrierDummy ~= keepModel then
		self:clearCarrierDummy()
	end
end

function DummyTacklerService:stopAttackLoop()
	self._attackLoopRunning = false
end

function DummyTacklerService:startAttackLoop()
	if self._attackLoopRunning or not self._tackleService or not self._matchService then
		return
	end

	self._attackLoopRunning = true

	task.spawn(function()
		while self._attackLoopRunning do
			task.wait(0.1)

			if not self._attackLoopRunning then
				break
			end

			if not self._matchService:isActive() then
				for _, entry in self._dummies do
					self:_setChaseEnabled(entry.model, false)
				end
				continue
			end

			local humanCarrier = self._matchService:getCarrier()
			local carrierCharacter = self._matchService:getCarrierCharacter()
			local carrierRoot = carrierCharacter and carrierCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
			local ballLoose = self._ballService and self._ballService:isLoose()
			local looseBall = if ballLoose and self._ballService then self._ballService:getBall() else nil
			local ballPosition = if looseBall then looseBall.Position else nil
			local canPickupBall = ballLoose and self._ballService and self._ballService:canPickupLooseBall()

			for _, entry in self._dummies do
				local dummy = entry.model
				if not dummy.Parent then
					continue
				end

				if not HealthService:isAliveCombatCharacter(dummy) then
					self:_setChaseEnabled(dummy, false)
					continue
				end

				if dummy:GetAttribute("TackleBallRagdollActive") == true then
					self:_setChaseEnabled(dummy, false)
					continue
				end

				local dummyRoot = dummy:FindFirstChild("HumanoidRootPart") :: BasePart?
				local humanoid = dummy:FindFirstChildOfClass("Humanoid")
				if not dummyRoot or not humanoid then
					continue
				end

				if self._tackleService:isDummyTackling(dummy) then
					self:_setChaseEnabled(dummy, false)
					continue
				end

				if dummy == self._carrierDummy and self._carrierEndzoneTarget then
					self:_setChaseEnabled(dummy, true)
					if os.clock() - entry.lastMoveAt >= Config.DUMMY_TACKLER_CHASE_UPDATE_INTERVAL then
						humanoid:MoveTo(self._carrierEndzoneTarget)
						entry.lastMoveAt = os.clock()
					end
					continue
				end

				if canPickupBall and ballPosition then
					local distance = self:_getFlatDistance(dummyRoot.Position, ballPosition)
					if distance <= Config.NPC_MATCH_BALL_PICKUP_RANGE then
						if self._matchService:tryAssignNpcCarrier(dummy) then
							continue
						end
					end

					self:_setChaseEnabled(dummy, true)
					if os.clock() - entry.lastMoveAt >= Config.DUMMY_TACKLER_CHASE_UPDATE_INTERVAL then
						humanoid:MoveTo(ballPosition)
						entry.lastMoveAt = os.clock()
					end
					continue
				end

				if not carrierRoot or dummy == carrierCharacter then
					self:_setChaseEnabled(dummy, false)
					continue
				end

				if GameMode.isTeamsMode() and self._matchService and self._matchService.getTeamService then
					local teamService = self._matchService:getTeamService()
					if teamService and teamService:areTeammates(dummy, carrierCharacter) then
						self:_setChaseEnabled(dummy, true)
						if os.clock() - entry.lastMoveAt >= Config.DUMMY_TACKLER_CHASE_UPDATE_INTERVAL then
							local offset = dummyRoot.Position - carrierRoot.Position
							local flat = Vector3.new(offset.X, 0, offset.Z)
							local supportPos = if flat.Magnitude > 1
								then carrierRoot.Position + flat.Unit * 8
								else carrierRoot.Position + Vector3.new(8, 0, 0)
							humanoid:MoveTo(supportPos)
							entry.lastMoveAt = os.clock()
						end
						continue
					end
				end

				local distance = self:_getFlatDistance(dummyRoot.Position, carrierRoot.Position)
				local attackCooldown = Config.DUMMY_TACKLER_ATTACK_COOLDOWN + (entry.profileIndex - 1) * 0.25
				local onCooldown = os.clock() - entry.lastTackleAt < attackCooldown

				if distance <= Config.DUMMY_TACKLER_TACKLE_RANGE and not onCooldown then
					self:_setChaseEnabled(dummy, false)
					entry.lastTackleAt = os.clock()
					if humanCarrier then
						self._tackleService:startDummyTackleDash(dummy, humanCarrier, self:getDummyCharge01(dummy))
					else
						self._tackleService:startDummyTackleDashAtCharacter(
							dummy,
							carrierCharacter,
							self:getDummyCharge01(dummy)
						)
					end
					continue
				end

				self:_setChaseEnabled(dummy, true)

				if os.clock() - entry.lastMoveAt >= Config.DUMMY_TACKLER_CHASE_UPDATE_INTERVAL then
					humanoid:MoveTo(carrierRoot.Position)
					entry.lastMoveAt = os.clock()
				end
			end
		end

		self._attackLoopRunning = false
	end)
end

function DummyTacklerService:init(tackleService, matchService, ballService)
	self._tackleService = tackleService
	self._matchService = matchService
	self._ballService = ballService

	task.spawn(function()
		local squadSize = math.max(#Config.DUMMY_TACKLER_SQUAD, 1)
		for profileIndex = 1, squadSize do
			pcall(getTemplate, profileIndex)
		end
	end)
end

return DummyTacklerService
