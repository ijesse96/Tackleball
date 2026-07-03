local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ArenaBoundsUtil = require(script.Parent.ArenaBoundsUtil)
local Config = require(ReplicatedStorage.Shared.Config)
local GameMode = require(ReplicatedStorage.Shared.GameMode)
local SoccerFieldUtil = require(ReplicatedStorage.Shared.SoccerFieldUtil)

local ORBS_FOLDER_NAME = "BoostOrbs"
local BOOST_ATTRIBUTE = "TackleBallSpeedBoostActive"

type BoostSession = {
	expiresAt: number,
	baseSpeed: number,
	stackCount: number,
	boostSpeed: number,
}

local BoostOrbService = {}
BoostOrbService._matchService = nil
BoostOrbService._tackleService = nil
BoostOrbService._orbsFolder = nil :: Folder?
BoostOrbService._activeOrbs = {} :: { BasePart }
BoostOrbService._boostSessions = {} :: { [Model]: BoostSession }
BoostOrbService._roundWasActive = false
BoostOrbService._lastUpdateAt = os.clock()
BoostOrbService._lastRefillAt = 0
BoostOrbService._spinConnection = nil :: RBXScriptConnection?
BoostOrbService._heartbeatConnection = nil :: RBXScriptConnection?

local function getFloorTopY(): number
	if GameMode.usesStadiumLayout() then
		local field = SoccerFieldUtil.findByPath(Workspace, Config.STADIUM_SOCCER_FIELD_PATH)
		if field then
			return SoccerFieldUtil.getFloorTopY(field)
		end
	end

	local floor = Workspace:FindFirstChild(Config.ARENA_FLOOR_NAME)
	if floor and floor:IsA("BasePart") then
		return floor.Position.Y + floor.Size.Y * 0.5
	end

	return Config.ARENA_SPAWN_CENTER.Y
end

local function findEndzoneByName(endzoneName: string): Instance?
	if not GameMode.usesStadiumLayout() then
		local field = Workspace:FindFirstChild("Field")
		if field then
			local endzone = field:FindFirstChild(endzoneName)
			if endzone then
				return endzone
			end
		end
	end

	for _, descendant in Workspace:GetDescendants() do
		if descendant.Name == endzoneName and (descendant:IsA("BasePart") or descendant:IsA("Model")) then
			return descendant
		end
	end

	return nil
end

local function getEndzoneZones(): { Instance }
	local endzones = {}
	for _, endzoneName in GameMode.getEndzoneNames() do
		local endzone = findEndzoneByName(endzoneName)
		if endzone then
			table.insert(endzones, endzone)
		end
	end

	return endzones
end

local function getZoneBounds(zone: Instance): (CFrame, Vector3)
	if zone:IsA("BasePart") then
		return zone.CFrame, zone.Size
	end

	if zone:IsA("Model") then
		return zone:GetBoundingBox()
	end

	return CFrame.new(), Vector3.zero
end

local function isPointInAnyEndzone(point: Vector3, endzones: { Instance }): boolean
	for _, endzone in endzones do
		local zoneCFrame, zoneSize = getZoneBounds(endzone)
		local localPoint = zoneCFrame:PointToObjectSpace(point)
		local half = zoneSize * 0.5 + Vector3.new(Config.BOOST_ORB_ENDZONE_MARGIN, 0, Config.BOOST_ORB_ENDZONE_MARGIN)
		if math.abs(localPoint.X) <= half.X
			and math.abs(localPoint.Y) <= half.Y + 4
			and math.abs(localPoint.Z) <= half.Z
		then
			return true
		end
	end

	return false
end

local function isFarEnoughFromOrbs(position: Vector3, orbs: { BasePart }): boolean
	local minSeparation = Config.BOOST_ORB_MIN_SEPARATION
	for _, orb in orbs do
		local flatDelta = Vector3.new(orb.Position.X - position.X, 0, orb.Position.Z - position.Z)
		if flatDelta.Magnitude < minSeparation then
			return false
		end
	end

	return true
end

function BoostOrbService:_ensureFolder(): Folder
	if self._orbsFolder and self._orbsFolder.Parent then
		return self._orbsFolder
	end

	local folder = Workspace:FindFirstChild(ORBS_FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = ORBS_FOLDER_NAME
		folder.Parent = Workspace
	end

	self._orbsFolder = folder
	return folder
end

function BoostOrbService:_pickSpawnPosition(): Vector3?
	local bounds = ArenaBoundsUtil.getPlayBounds()
	local endzones = getEndzoneZones()
	local floorY = getFloorTopY()
	local orbHalfHeight = Config.BOOST_ORB_SIZE.Y * 0.5
	local spawnY = floorY + Config.BOOST_ORB_FLOOR_OFFSET + orbHalfHeight

	for _ = 1, Config.BOOST_ORB_SPAWN_ATTEMPTS do
		local x = bounds.min.X + math.random() * (bounds.max.X - bounds.min.X)
		local z = bounds.min.Z + math.random() * (bounds.max.Z - bounds.min.Z)
		local position = Vector3.new(x, spawnY, z)

		if not isPointInAnyEndzone(position, endzones) and isFarEnoughFromOrbs(position, self._activeOrbs) then
			return position
		end
	end

	return nil
end

function BoostOrbService:_createOrbPart(position: Vector3): BasePart
	local orb = Instance.new("Part")
	orb.Name = "BoostOrb"
	orb.Shape = Enum.PartType.Ball
	orb.Size = Config.BOOST_ORB_SIZE
	orb.Anchored = true
	orb.CanCollide = false
	orb.CanTouch = true
	orb.CanQuery = false
	orb.Material = Enum.Material.Neon
	orb.Color = Color3.fromRGB(80, 220, 255)
	orb.CFrame = CFrame.new(position)
	orb:SetAttribute("TackleBallBoostOrb", true)

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(120, 230, 255)
	light.Brightness = 1.2
	light.Range = 10
	light.Parent = orb

	return orb
end

function BoostOrbService:_canCollectOrb(character: Model): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end

	if character:GetAttribute("TackleBallRagdollActive") == true then
		return false
	end

	if character:GetAttribute("TackleBallDead") == true then
		return false
	end

	if character:GetAttribute("TackleBallCelebrationLocked") == true then
		return false
	end

	return true
end

function BoostOrbService:_tryCollectOrb(orb: BasePart, character: Model): boolean
	if not orb.Parent or not self._matchService:isActive() then
		return false
	end

	if not self:_canCollectOrb(character) then
		return false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false
	end

	self:_applyBoost(character, humanoid)
	self:_destroyOrb(orb)
	self:_scheduleRespawn()
	return true
end

function BoostOrbService:_onOrbTouched(orb: BasePart, otherPart: BasePart)
	local character = otherPart:FindFirstAncestorOfClass("Model")
	if not character then
		return
	end

	self:_tryCollectOrb(orb, character)
end

function BoostOrbService:_tryProximityPickup()
	if not self._matchService:isActive() then
		return
	end

	local pickupRadius = Config.BOOST_ORB_PICKUP_RADIUS

	for _, player in Players:GetPlayers() do
		local character = player.Character
		if not character or not self:_canCollectOrb(character) then
			continue
		end

		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			continue
		end

		for _, orb in self._activeOrbs do
			if not orb.Parent then
				continue
			end

			local flatDelta = Vector3.new(root.Position.X - orb.Position.X, 0, root.Position.Z - orb.Position.Z)
			if flatDelta.Magnitude <= pickupRadius then
				if self:_tryCollectOrb(orb, character) then
					break
				end
			end
		end
	end
end

function BoostOrbService:_destroyOrb(orb: BasePart)
	local index = table.find(self._activeOrbs, orb)
	if index then
		table.remove(self._activeOrbs, index)
	end

	orb:Destroy()
end

function BoostOrbService:_spawnOrb()
	if not self._matchService:isActive() then
		return
	end

	if #self._activeOrbs >= Config.BOOST_ORB_MAX_ACTIVE then
		return
	end

	local position = self:_pickSpawnPosition()
	if not position then
		return
	end

	local orb = self:_createOrbPart(position)
	orb.Parent = self:_ensureFolder()

	local touchedConnection: RBXScriptConnection
	touchedConnection = orb.Touched:Connect(function(otherPart)
		if otherPart:IsA("BasePart") then
			self:_onOrbTouched(orb, otherPart)
		end
	end)

	orb.Destroying:Connect(function()
		touchedConnection:Disconnect()
	end)

	table.insert(self._activeOrbs, orb)
end

function BoostOrbService:_fillOrbs()
	while #self._activeOrbs < Config.BOOST_ORB_MAX_ACTIVE do
		local before = #self._activeOrbs
		self:_spawnOrb()
		if #self._activeOrbs == before then
			break
		end
	end
end

function BoostOrbService:_scheduleRespawn()
	task.delay(Config.BOOST_ORB_RESPAWN_DELAY, function()
		if self._matchService:isActive() then
			self:_fillOrbs()
		end
	end)
end

function BoostOrbService:_clearAllOrbs()
	for _, orb in self._activeOrbs do
		if orb.Parent then
			orb:Destroy()
		end
	end

	table.clear(self._activeOrbs)
end

function BoostOrbService:_isMovementBlocked(character: Model): boolean
	if character:GetAttribute("TackleBallRagdollActive") == true then
		return true
	end

	if character:GetAttribute("TackleBallDead") == true then
		return true
	end

	if character:GetAttribute("TackleBallCelebrationLocked") == true then
		return true
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return true
	end

	local player = Players:GetPlayerFromCharacter(character)
	if not player or not self._tackleService then
		return false
	end

	return self._tackleService:isDashing(player)
		or self._tackleService:isCharging(player)
		or self._tackleService:isTruckDashing(player)
		or self._tackleService:isTruckCharging(player)
		or self._matchService:isCarrierShedding(player)
end

function BoostOrbService:_getStackedBoostSpeed(baseSpeed: number, stackCount: number): number
	local clampedStacks = math.min(stackCount, Config.BOOST_ORB_MAX_STACKS)
	return baseSpeed + clampedStacks * Config.BOOST_ORB_SPEED_PER_STACK
end

function BoostOrbService:_applyBoost(character: Model, humanoid: Humanoid)
	local now = os.clock()
	local session = self._boostSessions[character]

	if session then
		if session.stackCount < Config.BOOST_ORB_MAX_STACKS then
			session.stackCount += 1
			session.boostSpeed = self:_getStackedBoostSpeed(session.baseSpeed, session.stackCount)
		end
		session.expiresAt = now + Config.BOOST_ORB_DURATION
	else
		session = {
			expiresAt = now + Config.BOOST_ORB_DURATION,
			baseSpeed = humanoid.WalkSpeed,
			stackCount = 1,
			boostSpeed = self:_getStackedBoostSpeed(humanoid.WalkSpeed, 1),
		}
		self._boostSessions[character] = session
		character:SetAttribute(BOOST_ATTRIBUTE, true)
	end

	character:SetAttribute("TackleBallSpeedBoostStacks", session.stackCount)

	if not self:_isMovementBlocked(character) then
		humanoid.WalkSpeed = session.boostSpeed
	end
end

function BoostOrbService:_clearBoost(character: Model)
	local session = self._boostSessions[character]
	if not session then
		return
	end

	self._boostSessions[character] = nil
	character:SetAttribute(BOOST_ATTRIBUTE, nil)
	character:SetAttribute("TackleBallSpeedBoostStacks", nil)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Parent and not self:_isMovementBlocked(character) then
		humanoid.WalkSpeed = session.baseSpeed
	end
end

function BoostOrbService:_clearAllBoosts()
	for character in self._boostSessions do
		self:_clearBoost(character)
	end

	table.clear(self._boostSessions)
end

function BoostOrbService:_onRoundStart()
	self._lastRefillAt = os.clock()
	self:_fillOrbs()
end

function BoostOrbService:_onRoundEnd()
	self:_clearAllOrbs()
	self:_clearAllBoosts()
end

function BoostOrbService:_updateBoostSessions(dt: number)
	local now = os.clock()
	local expired: { Model } = {}

	for character, session in self._boostSessions do
		if not character.Parent then
			table.insert(expired, character)
			continue
		end

		if now >= session.expiresAt then
			table.insert(expired, character)
			continue
		end

		if self:_isMovementBlocked(character) then
			session.expiresAt += dt
			continue
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = session.boostSpeed
		end
	end

	for _, character in expired do
		self:_clearBoost(character)
	end
end

function BoostOrbService:_updateSpin()
	local now = os.clock()
	for _, orb in self._activeOrbs do
		if orb.Parent then
			local position = orb.Position
			orb.CFrame = CFrame.new(position) * CFrame.Angles(0, now * 1.5, 0)
		end
	end
end

function BoostOrbService:_update()
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

	if now - self._lastRefillAt >= Config.BOOST_ORB_REFILL_INTERVAL then
		self._lastRefillAt = now
		if #self._activeOrbs < Config.BOOST_ORB_MAX_ACTIVE then
			self:_fillOrbs()
		end
	end

	self:_updateBoostSessions(dt)
	self:_tryProximityPickup()
end

function BoostOrbService:init(matchService, tackleService)
	if not Config.BOOST_ORBS_ENABLED then
		return
	end

	self._matchService = matchService
	self._tackleService = tackleService

	self._heartbeatConnection = RunService.Heartbeat:Connect(function()
		self:_update()
	end)

	self._spinConnection = RunService.Heartbeat:Connect(function()
		if self._roundWasActive then
			self:_updateSpin()
		end
	end)
end

return BoostOrbService
