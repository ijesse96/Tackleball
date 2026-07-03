local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local GameMode = require(ReplicatedStorage.Shared.GameMode)
local ChargeUtil = require(ReplicatedStorage.Shared.ChargeUtil)
local AnimationUtil = require(ReplicatedStorage.Shared.AnimationUtil)
local PlayerMapUtil = require(ReplicatedStorage.Shared.PlayerMapUtil)
local SoccerFieldUtil = require(ReplicatedStorage.Shared.SoccerFieldUtil)
local RagdollUtil = require(script.Parent.RagdollUtil)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

type RoundState = Types.RoundState

local MatchService = {}
MatchService._state = "Waiting" :: RoundState
MatchService._carrier = nil :: Player?
MatchService._scores = {} :: Types.ScoreMap
MatchService._roundNumber = 0
MatchService._timeRemaining = 0
MatchService._winnerName = nil :: string?
MatchService._scorerUserId = nil :: number?
MatchService._scorerPosition = nil :: Vector3?
MatchService._scorerCharacter = nil :: Model?
MatchService._lastScoredAmount = 0
MatchService._lastBankTotal = nil :: number?
MatchService._ballService = nil
MatchService._dummyCarrierService = nil
MatchService._dummyTacklerService = nil
MatchService._tackleService = nil
MatchService._moneyService = nil
MatchService._healthService = nil
MatchService._gameWinner = nil :: Player?
MatchService._scoreLocked = false
MatchService._soloTestRole = "carrier" :: "carrier" | "tackler"
MatchService._looseBallContestToken = 0
MatchService._npcScore = 0
MatchService._npcGameWon = false
MatchService._sheddingCarriers = {} :: { [number]: boolean }
MatchService._celebrationLocked = false
MatchService._celebrationLockConnection = nil :: RBXScriptConnection?
MatchService._savedCelebrationWalkSpeeds = {} :: { [number]: number }
MatchService._teamService = nil
MatchService._lobbyReturnService = nil
MatchService._matchEnded = false

function MatchService:setTeamService(teamService)
	self._teamService = teamService
end

function MatchService:getTeamService()
	return self._teamService
end

function MatchService:setLobbyReturnService(lobbyReturnService)
	self._lobbyReturnService = lobbyReturnService
end

function MatchService:_isMatchComplete(): boolean
	if self._gameWinner then
		return true
	end

	if self._npcGameWon then
		return true
	end

	if self._teamService and self._teamService:getTeamsGameWinner() then
		return true
	end

	return false
end

function MatchService:_clearMatchWinnerState()
	self._gameWinner = nil
	self._npcGameWon = false
	self._npcScore = 0
	if self._teamService then
		self._teamService:reset()
	end
	for userId, _ in pairs(self._scores) do
		self._scores[userId] = 0
	end
end

function MatchService:_finishMatchAndReturnToLobby()
	self:_broadcastState()
	task.wait(Config.MATCH_COMPLETE_LOBBY_DELAY)

	local PlayerDataService = require(script.Parent.PlayerDataService)
	PlayerDataService:flushDirtySaves()

	if self._lobbyReturnService then
		self._lobbyReturnService:returnAllToLobby()
	end

	self:_clearMatchWinnerState()
	self._matchEnded = true
	self._carrier = nil
	self._ballService:setCarrier(nil)
	if self._moneyService then
		self._moneyService:onCarrierLost()
	end
	if self._dummyCarrierService then
		self._dummyCarrierService:despawn()
	end
	if self._dummyTacklerService then
		self._dummyTacklerService:despawn()
	end
	self:_setState("Waiting")
end

function MatchService:init(ballService, dummyCarrierService, dummyTacklerService, moneyService, healthService)
	self._ballService = ballService
	self._dummyCarrierService = dummyCarrierService
	self._dummyTacklerService = dummyTacklerService
	self._moneyService = moneyService
	self._healthService = healthService

	if healthService then
		healthService:setDeathHandler(function(character)
			self:handleCharacterDeath(character)
		end)
		healthService:setNpcRespawnHandler(function(character)
			self:respawnNpcCharacter(character)
		end)
		healthService:setRespawnDefer(function()
			return self._celebrationLocked
		end)
	end

	self._ballService:setPickupHandler(function(player)
		return self:tryAssignCarrier(player)
	end)

	Players.CharacterAutoLoads = false

	local function applyDefaultMovement(character: Model, player: Player?)
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = Config.DEFAULT_WALK_SPEED
			humanoid.UseJumpPower = false
			if player and self._carrier == player then
				humanoid.JumpHeight = Config.CARRIER_JUMP_HEIGHT
			else
				humanoid.JumpHeight = Config.JUMP_HEIGHT
			end
		end
	end

	local function finalizeSpawnedCharacter(player: Player, character: Model)
		local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
		if humanoid and humanoid:IsA("Humanoid") then
			applyDefaultMovement(character, player)
		end

		local players = Players:GetPlayers()
		local slotIndex = table.find(players, player) or #players

		self._savedCelebrationWalkSpeeds[player.UserId] = nil

		if self._celebrationLocked then
			local isCelebrationScorer = self._scorerUserId ~= nil and player.UserId == self._scorerUserId
			if not isCelebrationScorer then
				self:_teleportPlayerToArenaSpawn(player, slotIndex, #players)
			end
			self:_applyCelebrationLock(player)
		else
			self:_clearCelebrationLockFromCharacter(character)
			self:_restorePlayerMovement(player)
			self:_teleportPlayerToArenaSpawn(player, slotIndex, #players)
		end

		if GameMode.isTeamsMode() and self._teamService then
			local team = self._teamService:getPlayerTeam(player)
			if team then
				self._teamService:applyTeamVisuals(character, team)
				character:SetAttribute("TackleBallTeam", team)
			end
		end
	end

	local function bindPlayerSpawn(player: Player)
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("HumanoidRootPart", 10)
			if self._healthService then
				self._healthService:setupCharacter(character)
			end
			finalizeSpawnedCharacter(player, character)
		end)

		if player.Character then
			task.spawn(function()
				finalizeSpawnedCharacter(player, player.Character :: Model)
			end)
		else
			player:LoadCharacter()
		end
	end

	for _, player in Players:GetPlayers() do
		self._scores[player.UserId] = 0
		bindPlayerSpawn(player)
	end

	Players.PlayerAdded:Connect(function(player)
		self._scores[player.UserId] = self._scores[player.UserId] or 0
		bindPlayerSpawn(player)
		self:_broadcastState()
	end)

	Players.PlayerRemoving:Connect(function(player)
		if self._carrier == player and self._state == "Active" then
			if self._moneyService then
				self._moneyService:onBallKnockedLoose()
			end
			self._carrier = nil
			self._ballService:releaseLoose()
			self:_broadcastState()
		end
		self._sheddingCarriers[player.UserId] = nil
	end)

	task.spawn(function()
		self:_runGameLoop()
	end)
end

function MatchService:getState(): RoundState
	return self._state
end

function MatchService:getCarrier(): Player?
	return self._carrier
end

function MatchService:getCarrierCharacter(): Model?
	if self._carrier and self._carrier.Character then
		return self._carrier.Character
	end

	return self._ballService:getCarrierCharacter()
end

function MatchService:getSoloTestRole(): string
	return self._soloTestRole
end

function MatchService:isActive(): boolean
	return self._state == "Active"
end

function MatchService:_getAlivePlayers(): { Player }
	local alive = {}
	for _, player in Players:GetPlayers() do
		if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
			table.insert(alive, player)
		end
	end
	return alive
end

function MatchService:_getSoccerField(): Instance?
	if not GameMode.usesStadiumLayout() then
		return nil
	end

	return SoccerFieldUtil.findByPath(Workspace, Config.STADIUM_SOCCER_FIELD_PATH)
end

function MatchService:_getArenaFloorTopY(): number
	local soccerField = self:_getSoccerField()
	if soccerField then
		return SoccerFieldUtil.getFloorTopY(soccerField)
	end

	local floor = Workspace:FindFirstChild(Config.ARENA_FLOOR_NAME)
	if floor and floor:IsA("BasePart") then
		return floor.Position.Y + floor.Size.Y / 2
	end
	return Config.ARENA_SPAWN_CENTER.Y
end

function MatchService:_getArenaSpawnCenter(): Vector3
	local soccerField = self:_getSoccerField()
	if soccerField then
		return SoccerFieldUtil.getCenterPosition(soccerField)
	end

	return Config.ARENA_SPAWN_CENTER
end

function MatchService:_getArenaSpawnCFrame(slotIndex: number, totalPlayers: number): CFrame
	totalPlayers = math.max(totalPlayers, 1)
	local floorY = self:_getArenaFloorTopY()
	local center = self:_getArenaSpawnCenter()
	local angle = (slotIndex - 1) / totalPlayers * math.pi * 2
	local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * Config.ARENA_SPAWN_RING_RADIUS
	local spawnPos = Vector3.new(center.X, floorY, center.Z) + offset + Vector3.new(0, Config.ARENA_SPAWN_HEIGHT_OFFSET, 0)
	return CFrame.new(spawnPos)
end

function MatchService:_teleportPlayerToArenaSpawn(player: Player, slotIndex: number, totalPlayers: number)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	root.CFrame = self:_getArenaSpawnCFrame(slotIndex, totalPlayers)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and not self._sheddingCarriers[player.UserId] then
		humanoid.WalkSpeed = Config.DEFAULT_WALK_SPEED
		humanoid.UseJumpPower = false
		humanoid.JumpHeight = Config.JUMP_HEIGHT
	end
end

function MatchService:_teleportAllPlayersToArenaSpawn()
	local players = Players:GetPlayers()
	local totalPlayers = #players
	for slotIndex, player in ipairs(players) do
		self:_teleportPlayerToArenaSpawn(player, slotIndex, totalPlayers)
	end
end

function MatchService:_getCelebrationFocusCFrame(): CFrame
	local spawnPart = Workspace:FindFirstChild(Config.CELEBRATION_SPAWN_NAME)
	if not spawnPart or not spawnPart:IsA("BasePart") then
		warn(`MatchService: celebration spawn "{Config.CELEBRATION_SPAWN_NAME}" not found`)
		return CFrame.new(0, 10, 0)
	end

	local spawnPos = spawnPart.Position + Vector3.new(0, Config.ARENA_SPAWN_HEIGHT_OFFSET, 0)
	return CFrame.new(spawnPos) * (spawnPart.CFrame - spawnPart.Position)
end

function MatchService:_teleportCharacterToCelebrationFocus(character: Model)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	root.CFrame = self:_getCelebrationFocusCFrame()
end

function MatchService:_applyCelebrationLockToCharacter(character: Model)
	if character:GetAttribute("TackleBallDead") == true then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	character:SetAttribute("TackleBallCelebrationLocked", true)
	humanoid.WalkSpeed = 0
	humanoid.JumpHeight = 0
	humanoid.Jump = false
	humanoid.AutoRotate = true
end

function MatchService:_applyCelebrationLock(player: Player)
	local character = player.Character
	if not character then
		return
	end

	if character:GetAttribute("TackleBallDead") == true then
		return
	end

	local humanoid = self:_getHumanoid(player)
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	if self._savedCelebrationWalkSpeeds[player.UserId] == nil then
		local savedSpeed = humanoid.WalkSpeed
		if savedSpeed <= 0 then
			savedSpeed = Config.DEFAULT_WALK_SPEED
		end
		self._savedCelebrationWalkSpeeds[player.UserId] = savedSpeed
	end

	self:_applyCelebrationLockToCharacter(character)
end

function MatchService:_restorePlayerMovement(player: Player)
	local humanoid = self:_getHumanoid(player)
	if not humanoid then
		return
	end

	local restoredSpeed = self._savedCelebrationWalkSpeeds[player.UserId]
	if not restoredSpeed or restoredSpeed <= 0 then
		restoredSpeed = Config.DEFAULT_WALK_SPEED
	end

	if not self._sheddingCarriers[player.UserId] then
		humanoid.WalkSpeed = restoredSpeed
		humanoid.JumpHeight = Config.JUMP_HEIGHT
	end
end

function MatchService:_clearCelebrationLockFromCharacter(character: Model)
	character:SetAttribute("TackleBallCelebrationLocked", nil)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	humanoid.JumpHeight = Config.JUMP_HEIGHT
end

function MatchService:_resolveScorerCharacter(): Model?
	if self._scorerCharacter and self._scorerCharacter.Parent then
		return self._scorerCharacter
	end

	if self._scorerUserId then
		local scorer = Players:GetPlayerByUserId(self._scorerUserId)
		return scorer and scorer.Character
	end

	return nil
end

function MatchService:_beginCelebration()
	if self._celebrationLocked then
		return
	end

	self._celebrationLocked = true

	if self._dummyTacklerService then
		local keepScorer = self:_resolveScorerCharacter()
		if keepScorer and keepScorer:GetAttribute("TackleBallDummy") ~= true then
			keepScorer = nil
		end
		self._dummyTacklerService:despawnExcept(keepScorer)
	end

	if self._dummyCarrierService then
		self._dummyCarrierService:despawn()
	end

	for _, player in Players:GetPlayers() do
		self:_applyCelebrationLock(player)
	end

	local scorerCharacter = self:_resolveScorerCharacter()
	if scorerCharacter then
		scorerCharacter:SetAttribute("TackleBallCelebrationScorer", true)
		self:_teleportCharacterToCelebrationFocus(scorerCharacter)
		self:_applyCelebrationLockToCharacter(scorerCharacter)

		local root = scorerCharacter:FindFirstChild("HumanoidRootPart")
		if root then
			self._scorerPosition = root.Position
		end

		Remotes.scoreCelebrationStarted():FireAllClients({
			scorerUserId = self._scorerUserId,
			scorerCharacterName = scorerCharacter.Name,
			focusPosition = self._scorerPosition or Vector3.zero,
			scoredAmount = if self._lastScoredAmount > 0 then self._lastScoredAmount else nil,
			bankTotal = self._lastBankTotal,
		} :: Types.CelebrationScenePayload)
	end

	if not self._celebrationLockConnection then
		self._celebrationLockConnection = RunService.Heartbeat:Connect(function()
			if not self._celebrationLocked then
				return
			end

			for _, player in Players:GetPlayers() do
				self:_applyCelebrationLock(player)
			end

			local celebrationScorer = self:_resolveScorerCharacter()
			if celebrationScorer then
				self:_applyCelebrationLockToCharacter(celebrationScorer)
			end
		end)
	end
end

function MatchService:_endCelebration()
	if not self._celebrationLocked then
		return
	end

	self._celebrationLocked = false

	if self._celebrationLockConnection then
		self._celebrationLockConnection:Disconnect()
		self._celebrationLockConnection = nil
	end

	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character then
			self:_clearCelebrationLockFromCharacter(character)
		end

		self:_restorePlayerMovement(player)
		self._savedCelebrationWalkSpeeds[player.UserId] = nil
	end

	local scorerCharacter = self._scorerCharacter
	if scorerCharacter and scorerCharacter.Parent then
		scorerCharacter:SetAttribute("TackleBallCelebrationScorer", nil)
		scorerCharacter:SetAttribute("TackleBallCelebrationLocked", nil)
	end
	self._scorerCharacter = nil

	if self._dummyTacklerService then
		self._dummyTacklerService:despawn()
	end

	if self._dummyCarrierService then
		self._dummyCarrierService:despawn()
	end
end

function MatchService:_waitForReadyPlayers(timeout: number)
	local deadline = os.clock() + timeout
	while os.clock() < deadline and #self:_getAlivePlayers() < GameMode.getMinPlayers() do
		task.wait(0.1)
	end
end

function MatchService:_getNpcContestSpawnPosition(referencePosition: Vector3): Vector3
	local center = Config.ARENA_SPAWN_CENTER
	local offset = referencePosition - center
	local flat = Vector3.new(offset.X, 0, offset.Z)
	if flat.Magnitude < 0.01 then
		flat = Vector3.new(1, 0, 0)
	else
		flat = flat.Unit
	end
	local floorY = self:_getArenaFloorTopY()
	return Vector3.new(center.X, floorY, center.Z) + flat * Config.ARENA_SPAWN_RING_RADIUS
end

function MatchService:_stopLooseBallContest()
	self._looseBallContestToken += 1
	if self._dummyCarrierService then
		self._dummyCarrierService:stopBallChaseLoop()
	end
end

function MatchService:_setHumanCarrier(player: Player, resetValue: boolean?)
	self:_stopLooseBallContest()

	if GameMode.isTeamsMode() then
		if self._dummyTacklerService then
			self._dummyTacklerService:clearCarrierDummy()
		end
	elseif GameMode.isSoloMode() then
		if self._dummyTacklerService then
			self._dummyTacklerService:clearCarrierDummy()
		end
	else
		if self._dummyCarrierService then
			self._dummyCarrierService:despawn()
		end
	end

	self._carrier = player
	self._ballService:setCarrier(player)
	if self._moneyService then
		self._moneyService:onCarrierSet(player, resetValue)
	end

	if self._dummyTacklerService then
		if Config.TEAMS_PASS_TEST_MODE then
			self._dummyTacklerService:stopAttackLoop()
		elseif GameMode.isTeamsMode() or GameMode.isSoloMode() then
			self._dummyTacklerService:startAttackLoop()
		else
			local root = self:_getRoot(player)
			if root then
				self._dummyTacklerService:spawnFacingCarrier(root)
				self._dummyTacklerService:startAttackLoop()
			end
		end
	end

	self:_broadcastState()
end

function MatchService:_setNpcCarrierFromRoster(dummy: Model, networkOwner: Player?, resetValue: boolean?)
	self:_stopLooseBallContest()

	if self._moneyService then
		self._moneyService:onNpcCarrierHeld(resetValue)
	end
	self._carrier = nil

	local owner = networkOwner or Players:GetPlayers()[1]
	if self._dummyTacklerService then
		self._dummyTacklerService:setCarrierDummy(dummy)
		self._ballService:setCarrierCharacter(dummy, owner)
		self._dummyTacklerService:startAttackLoop()
	end

	self:_broadcastState()
end

function MatchService:tryAssignNpcCarrier(dummy: Model): boolean
	if not (GameMode.isSoloMode() or GameMode.isTeamsMode()) or self._state ~= "Active" then
		return false
	end

	if self._ballService:isPassInFlight() then
		return false
	end

	if not self._ballService:isLoose() or not self._ballService:canPickupLooseBall() then
		return false
	end

	if not dummy.Parent or dummy:GetAttribute("TackleBallDummy") ~= true then
		return false
	end

	if dummy:GetAttribute("TackleBallRagdollActive") == true then
		return false
	end

	self:_setNpcCarrierFromRoster(dummy, nil, false)
	return true
end

function MatchService:_setNpcCarrier(fleeFromPlayer: Player, existingDummy: Model?)
	if GameMode.isSoloMode() then
		if existingDummy then
			self:_setNpcCarrierFromRoster(existingDummy, fleeFromPlayer, false)
		end
		return
	end

	self:_stopLooseBallContest()

	if self._dummyTacklerService then
		self._dummyTacklerService:despawn()
	end
	if self._moneyService then
		self._moneyService:onCarrierLost()
	end
	self._carrier = nil

	local dummy = existingDummy
	if not dummy then
		if self._dummyCarrierService then
			self._dummyCarrierService:despawn()
			local root = self:_getRoot(fleeFromPlayer)
			local position = root and root.Position or Config.ARENA_SPAWN_CENTER
			dummy = self._dummyCarrierService:spawn(position)
		end
	elseif self._dummyCarrierService then
		self._dummyCarrierService:stopBallChaseLoop()
	end

	if dummy and self._dummyCarrierService then
		self._ballService:setCarrierCharacter(dummy, fleeFromPlayer)
		self._dummyCarrierService:startBehaviorLoop(fleeFromPlayer)
	end

	self:_broadcastState()
end

function MatchService:_startTeamsRound()
	local players = Players:GetPlayers()
	if #players == 0 then
		return
	end

	if self._teamService then
		self._teamService:clearRoster()
	end

	local blueNpcCount = 0
	local redNpcCount = 0
	if Config.TEAMS_PASS_TEST_MODE then
		blueNpcCount = Config.TEAMS_PASS_TEST_TEAMMATE_NPCS
		redNpcCount = 0
	elseif self._teamService then
		blueNpcCount, redNpcCount = self._teamService:getNpcCountNeeded(#players)
	end

	local blueDummies = {}
	local redDummies = {}
	if self._dummyTacklerService then
		blueDummies, redDummies = self._dummyTacklerService:spawnTeamsRoster(blueNpcCount, redNpcCount)
	end

	if self._teamService then
		self._teamService:assignRoster(players, blueDummies, redDummies)
	end

	local humanPlayer = players[1]
	if Config.TEAMS_PASS_TEST_MODE and humanPlayer then
		self:_setHumanCarrier(humanPlayer, true)
		return
	end

	local roster = if self._teamService then self._teamService:getAllRosterMembers() else players
	if #roster == 0 then
		return
	end

	local carrierEntity = roster[math.random(1, #roster)]
	if typeof(carrierEntity) == "Instance" and carrierEntity:IsA("Player") then
		self:_setHumanCarrier(carrierEntity, true)
	elseif typeof(carrierEntity) == "Instance" and carrierEntity:IsA("Model") then
		self:_setNpcCarrierFromRoster(carrierEntity, players[1], true)
	end
end

function MatchService:setTeamsCarrier(player: Player)
	if not GameMode.isTeamsMode() or self._state ~= "Active" then
		return
	end

	self:_stopLooseBallContest()
	if self._dummyTacklerService then
		self._dummyTacklerService:clearCarrierDummy()
	end

	self._carrier = player
	self._ballService:setCarrier(player)
	if self._moneyService then
		self._moneyService:onCarrierSet(player, false)
	end

	if self._dummyTacklerService then
		self._dummyTacklerService:startAttackLoop()
	end

	self:_broadcastState()
end

function MatchService:setTeamsNpcCarrier(dummy: Model)
	if not GameMode.isTeamsMode() or self._state ~= "Active" then
		return
	end

	self:_setNpcCarrierFromRoster(dummy, Players:GetPlayers()[1], false)
end

function MatchService:onPassFlightStarted(thrower: Player)
	if self._state ~= "Active" then
		return
	end

	if self._carrier == thrower then
		self._carrier = nil
	end

	if self._moneyService then
		self._moneyService:onCarrierLost()
	end

	self:_broadcastState()
end

function MatchService:onPassFailed(_throwerUserId: number?)
	if self._state ~= "Active" then
		return
	end

	if GameMode.isTeamsMode() then
		self:_startLooseBallContest()
	end

	self:_broadcastState()
end

function MatchService:_startSoloRound()
	local players = Players:GetPlayers()
	if #players == 0 then
		return
	end

	local fieldSize = Config.NPC_MATCH_FIELD_PLAYERS
	local humanCount = math.min(#players, fieldSize)

	for index, player in players do
		if index > humanCount then
			break
		end
		self:_teleportPlayerToArenaSpawn(player, index, fieldSize)
	end

	local dummies = {}
	if self._dummyTacklerService then
		dummies = self._dummyTacklerService:spawnArenaRoster(fieldSize, humanCount)
	end

	local roster: { Player | Model } = {}
	for index = 1, humanCount do
		roster[index] = players[index]
	end
	for index, dummy in dummies do
		roster[humanCount + index] = dummy
	end

	local filledCount = humanCount + #dummies
	if filledCount == 0 then
		return
	end

	local roll = math.random(1, filledCount)
	local carrierEntity = roster[roll]
	if typeof(carrierEntity) == "Instance" and carrierEntity:IsA("Player") then
		self:_setHumanCarrier(carrierEntity, true)
	elseif typeof(carrierEntity) == "Instance" and carrierEntity:IsA("Model") then
		self:_setNpcCarrierFromRoster(carrierEntity, players[1], true)
	end
end

function MatchService:_startLooseBallContest(_fleeFromPlayer: Player)
	self:_stopLooseBallContest()
	if self._dummyTacklerService then
		self._dummyTacklerService:startAttackLoop()
	end
end

function MatchService:_applyRoundRoles()
	if GameMode.isTeamsMode() then
		self:_startTeamsRound()
	elseif GameMode.isSoloMode() then
		self:_startSoloRound()
	elseif GameMode.isSoloTestMode() then
		local player = Players:GetPlayers()[1]
		if player then
			self:switchTestRole(player, self._soloTestRole)
		end
	else
		self:_pickNewCarrier()
	end
end

function MatchService:_applySoloTestRole()
	self:_applyRoundRoles()
end

function MatchService:switchTestRole(player: Player, role: string)
	if not GameMode.isSoloTestMode() then
		return
	end
	if role ~= "carrier" and role ~= "tackler" then
		return
	end

	self._soloTestRole = role :: "carrier" | "tackler"

	if role == "carrier" then
		if self._dummyCarrierService then
			self._dummyCarrierService:despawn()
		end
		self._carrier = player
		self._ballService:setCarrier(player)
		if self._moneyService then
			self._moneyService:onCarrierSet(player, true)
		end

		if self._dummyTacklerService then
			local root = self:_getRoot(player)
			if root then
				self._dummyTacklerService:spawnFacingCarrier(root)
				self._dummyTacklerService:startAttackLoop()
			end
		end
	else
		if self._dummyTacklerService then
			self._dummyTacklerService:despawn()
		end
		if self._moneyService then
			self._moneyService:onCarrierLost()
		end
		self._carrier = nil
		self._ballService:setCarrier(nil)

		if self._dummyCarrierService then
			local root = self:_getRoot(player)
			local position = root and root.Position or Vector3.zero
			local dummy = self._dummyCarrierService:spawn(position)
			if dummy then
				self._ballService:setCarrierCharacter(dummy, player)
				self._dummyCarrierService:startBehaviorLoop(player)
			end
		end
	end

	self:_broadcastState()
end

function MatchService:_getRespawnAnchorRoot(): BasePart?
	local carrier = self:getCarrier()
	if carrier then
		local root = self:_getRoot(carrier)
		if root then
			return root
		end
	end

	local ballCharacter = self._ballService:getCarrierCharacter()
	if ballCharacter then
		local root = ballCharacter:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			return root
		end
	end

	for _, player in Players:GetPlayers() do
		local root = self:_getRoot(player)
		if root then
			return root
		end
	end

	return nil
end

function MatchService:respawnNpcCharacter(character: Model)
	if self._state ~= "Active" then
		if character.Parent then
			character:Destroy()
		end
		return
	end

	local anchorRoot = self:_getRespawnAnchorRoot()
	if not anchorRoot then
		if character.Parent then
			character:Destroy()
		end
		return
	end

	if character:GetAttribute("TackleBallDummyTackler") == true and self._dummyTacklerService then
		self._dummyTacklerService:removeDummy(character)
		return
	end

	if character:GetAttribute("TackleBallDummyCarrier") == true and self._dummyCarrierService then
		local nearPlayer = self:getCarrier() or Players:GetPlayers()[1]
		if nearPlayer then
			self:_respawnDummyAfterTackle(nearPlayer)
		elseif character.Parent then
			character:Destroy()
		end
		return
	end

	if character.Parent and character:GetAttribute("TackleBallDead") == true then
		character:Destroy()
	end
end

function MatchService:_respawnDummyTacklerAfterHit(carrier: Player, victimDummy: Model?)
	if GameMode.isSoloMode() then
		return
	end

	if not GameMode.isSoloTestMode() or self._soloTestRole ~= "carrier" or not self._dummyTacklerService then
		return
	end
	if self._state ~= "Active" then
		return
	end

	local root = self:_getRoot(carrier)
	if not root then
		return
	end

	if victimDummy then
		self._dummyTacklerService:respawnDummy(victimDummy, root)
	else
		self._dummyTacklerService:respawnFacingCarrier(root)
	end

	self._dummyTacklerService:startAttackLoop()
end

function MatchService:_respawnDummyAfterTackle(nearPlayer: Player)
	if not GameMode.isSoloTestMode() or self._soloTestRole ~= "tackler" or not self._dummyCarrierService then
		return
	end
	if self._state ~= "Active" then
		return
	end

	local root = self:_getRoot(nearPlayer)
	local position = root and root.Position or Vector3.zero
	self._dummyCarrierService:despawn()
	local dummy = self._dummyCarrierService:spawn(position)
	if dummy then
		self._ballService:setCarrierCharacter(dummy, nearPlayer)
		self._dummyCarrierService:startBehaviorLoop(nearPlayer)
	end
	self:_broadcastState()
end

function MatchService:tryAssignCarrier(player: Player): boolean
	if self._state ~= "Active" or self._carrier then
		return false
	end

	if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
		return false
	end

	local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end

	if player.Character:GetAttribute("TackleBallRagdollActive") == true then
		return false
	end

	if GameMode.isTeamsMode() or GameMode.isSoloMode() then
		self:_setHumanCarrier(player)
		return true
	end

	if GameMode.isSoloTestMode() and self._dummyCarrierService then
		self._dummyCarrierService:despawn()
	end

	self._carrier = player
	self._ballService:setCarrier(player)
	if self._moneyService then
		self._moneyService:onCarrierSet(player, false)
	end
	self:_broadcastState()
	return true
end

function MatchService:_pickNewCarrier(excludePlayer: Player?)
	if GameMode.isTeamsMode() then
		self:_startTeamsRound()
		return
	end

	if GameMode.isSoloMode() then
		self:_startNpcMatchRound()
		return
	end

	if GameMode.isSoloTestMode() then
		local player = Players:GetPlayers()[1]
		if player then
			if player == excludePlayer then
				self:switchTestRole(player, "tackler")
			else
				self:switchTestRole(player, self._soloTestRole)
			end
		end
		return
	end

	local candidates = self:_getAlivePlayers()
	local filtered = {}

	for _, player in candidates do
		if player ~= excludePlayer then
			table.insert(filtered, player)
		end
	end

	if #filtered == 0 then
		filtered = candidates
	end

	if #filtered == 0 then
		if self._moneyService then
			self._moneyService:onCarrierLost()
		end
		self._carrier = nil
		self._ballService:setCarrier(nil)
		return
	end

	local carrier = filtered[math.random(1, #filtered)]
	self._carrier = carrier
	self._ballService:setCarrier(carrier)
	if self._moneyService then
		self._moneyService:onCarrierSet(carrier, false)
	end
	self:_broadcastState()
end

function MatchService:_buildPayload(): Types.RoundStatePayload
	local carrierName = self._carrier and self._carrier.DisplayName or nil
	local carrierUserId = self._carrier and self._carrier.UserId or nil

	local ballCharacter = self._ballService:getCarrierCharacter()
	if not self._carrier and ballCharacter then
		if GameMode.isTeamsMode() or GameMode.isSoloMode() then
			local humanoid = ballCharacter:FindFirstChildOfClass("Humanoid")
			carrierName = humanoid and humanoid.DisplayName or ballCharacter.Name
			carrierUserId = nil
		elseif self._dummyCarrierService and ballCharacter == self._dummyCarrierService:getDummy() then
			carrierName = "Test Dummy"
			carrierUserId = nil
		end
	end

	local matchComplete: boolean? = nil
	local matchWinnerUserId: number? = nil
	local matchWinnerNpc: boolean? = nil
	local matchWinnerTeam: Types.TeamName? = nil

	if self:_isMatchComplete() and (self._state == "Scored" or self._state == "Intermission") then
		matchComplete = true
		if self._gameWinner then
			matchWinnerUserId = self._gameWinner.UserId
		elseif self._npcGameWon then
			matchWinnerNpc = true
		elseif self._teamService then
			matchWinnerTeam = self._teamService:getTeamsGameWinner()
		end
	end

	return {
		state = self._state,
		carrierName = carrierName,
		carrierUserId = carrierUserId,
		scores = PlayerMapUtil.serialize(self._scores),
		banks = PlayerMapUtil.serialize(if self._moneyService then self._moneyService:getBanks() else {}),
		timeRemaining = self._timeRemaining,
		roundNumber = self._roundNumber,
		winnerName = self._winnerName,
		scorerUserId = self._scorerUserId,
		scorerPosition = self._scorerPosition,
		scorerCharacterName = if self._scorerCharacter then self._scorerCharacter.Name else nil,
		scoredAmount = if self._state == "Scored" or self._state == "Intermission"
			then if self._lastScoredAmount > 0 then self._lastScoredAmount else nil
			else nil,
		bankTotal = if self._state == "Scored" or self._state == "Intermission" then self._lastBankTotal else nil,
		soloTestRole = if GameMode.isSoloTestMode() then self._soloTestRole else nil,
		npcMatchMode = if GameMode.isSoloMode() then true else nil,
		npcScore = if GameMode.isSoloMode() then self._npcScore else nil,
		teamsMode = if GameMode.isTeamsMode() then true else nil,
		gameMode = GameMode.getMode(),
		teamScores = if GameMode.isTeamsMode() and self._teamService then self._teamService:getTeamScores() else nil,
		carrierTeam = if GameMode.isTeamsMode() and self._teamService and ballCharacter
			then self._teamService:getTeam(ballCharacter)
			else nil,
		matchComplete = matchComplete,
		matchWinnerUserId = matchWinnerUserId,
		matchWinnerNpc = matchWinnerNpc,
		matchWinnerTeam = matchWinnerTeam,
	}
end

function MatchService:_buildPayloadForPlayer(player: Player): Types.RoundStatePayload
	local payload = self:_buildPayload()
	if GameMode.isTeamsMode() and self._teamService then
		payload.localTeam = self._teamService:getPlayerTeam(player)
	end
	return payload
end

function MatchService:_syncCarrierJumpHeights()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if not character then
			continue
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or self._sheddingCarriers[player.UserId] then
			continue
		end

		if self._carrier == player then
			humanoid.JumpHeight = Config.CARRIER_JUMP_HEIGHT
		else
			humanoid.JumpHeight = Config.JUMP_HEIGHT
		end
	end
end

function MatchService:_broadcastState()
	local payload = self:_buildPayload()
	self:_syncCarrierJumpHeights()
	for _, player in Players:GetPlayers() do
		local playerPayload = table.clone(payload)
		if GameMode.isTeamsMode() and self._teamService then
			playerPayload.localTeam = self._teamService:getPlayerTeam(player)
		end
		Remotes.roundStateChanged():FireClient(player, playerPayload)
	end
end

function MatchService:setTackleService(tackleService)
	self._tackleService = tackleService
end

function MatchService:_setState(state: RoundState)
	local previousState = self._state

	if (previousState == "Scored" or previousState == "Intermission") and (state == "Active" or state == "Waiting") then
		self:_endCelebration()
	end

	self._state = state

	if previousState == "Active" and state ~= "Active" then
		self:_stopLooseBallContest()
		if self._tackleService then
			self._tackleService:cancelAllCharges()
			self._tackleService:cancelAllTruckCharges()
		end
	end

	if previousState == "Active" and state ~= "Active" and state ~= "Scored" and self._dummyTacklerService then
		self._dummyTacklerService:despawn()
	end

	if previousState == "Active" and state ~= "Active" and state ~= "Scored" and self._dummyCarrierService then
		self._dummyCarrierService:despawn()
	end

	if state == "Scored" and previousState == "Active" then
		self:_beginCelebration()
	end

	self:_broadcastState()
end

function MatchService:startRound()
	local players = Players:GetPlayers()
	if #players < GameMode.getMinPlayers() then
		return
	end

	self._matchEnded = false
	self._roundNumber += 1
	self._timeRemaining = Config.ROUND_DURATION
	self._winnerName = nil
	self._scorerUserId = nil
	self._scorerPosition = nil
	self._scorerCharacter = nil
	self._lastScoredAmount = 0
	self._lastBankTotal = nil
	if self._healthService then
		self._healthService:resetAllHealth()
	end
	self:_teleportAllPlayersToArenaSpawn()
	task.wait(0.2)
	self:_waitForReadyPlayers(5)
	self:_setState("Active")
	self:_applyRoundRoles()
end

function MatchService:_getHumanoid(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

function MatchService:_getRoot(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

function MatchService:_getFloorRaycast(character: Model, root: BasePart): RaycastResult?
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { character }

	return Workspace:Raycast(
		root.Position,
		Vector3.new(0, -Config.TACKLE_FLOOR_RAY_DISTANCE, 0),
		rayParams
	)
end

function MatchService:_isCarrierOnFloor(humanoid: Humanoid, root: BasePart, character: Model): boolean
	local ray = self:_getFloorRaycast(character, root)
	if not ray then
		return false
	end

	local heightAboveFloor = root.Position.Y - ray.Position.Y
	if heightAboveFloor > Config.TACKLE_FLOOR_CONTACT_MAX then
		return false
	end

	if root.AssemblyLinearVelocity.Y > Config.TACKLE_FLOOR_MAX_ASCENT then
		return false
	end

	return true
end

function MatchService:_snapCarrierToFloor(root: BasePart, character: Model): boolean
	local ray = self:_getFloorRaycast(character, root)
	if not ray then
		return false
	end

	local offset = Config.TACKLE_GETUP_GROUND_OFFSET
	local snappedPos = ray.Position + ray.Normal * offset
	local look = root.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatLook.Magnitude < 0.01 then
		flatLook = Vector3.new(0, 0, -1)
	else
		flatLook = flatLook.Unit
	end

	root.CFrame = CFrame.lookAt(snappedPos, snappedPos + flatLook)
	return true
end

function MatchService:_getFlatLookVector(root: BasePart): Vector3
	local look = root.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatLook.Magnitude < 0.01 then
		return Vector3.new(0, 0, -1)
	end

	return flatLook.Unit
end

function MatchService:_snapCharacterInFrontOfCarrier(
	victimRoot: BasePart,
	victimCharacter: Model,
	carrierRoot: BasePart,
	distance: number
): boolean
	local forward = self:_getFlatLookVector(carrierRoot)
	local targetPos = carrierRoot.Position + forward * distance

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local filter: { Instance } = { victimCharacter }
	local carrierCharacter = carrierRoot.Parent
	if carrierCharacter and carrierCharacter:IsA("Model") then
		table.insert(filter, carrierCharacter)
	end
	rayParams.FilterDescendantsInstances = filter

	local ray = Workspace:Raycast(targetPos + Vector3.new(0, 8, 0), Vector3.new(0, -24, 0), rayParams)
	if not ray then
		return self:_snapCarrierToFloor(victimRoot, victimCharacter)
	end

	local snappedPos = ray.Position + ray.Normal * Config.TACKLE_GETUP_GROUND_OFFSET
	local toCarrier = carrierRoot.Position - snappedPos
	local flatToCarrier = Vector3.new(toCarrier.X, 0, toCarrier.Z)
	if flatToCarrier.Magnitude < 0.01 then
		flatToCarrier = -forward
	else
		flatToCarrier = flatToCarrier.Unit
	end

	victimRoot.CFrame = CFrame.lookAt(snappedPos, snappedPos + flatToCarrier)
	return true
end

function MatchService:_launchRagdollCharacter(
	character: Model,
	direction: Vector3,
	charge01: number,
	faceFromPosition: Vector3?,
	networkOwner: Player?,
	onRecovered: (() -> ())?,
	recoverInFrontOfRoot: BasePart?,
	recoverForwardDistance: number?
)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		return
	end

	local isLethal = false
	if self._healthService then
		isLethal = self._healthService:applyTackleDamage(character, charge01)
	end

	local oldWalkSpeed = humanoid.WalkSpeed
	local oldAutoRotate = humanoid.AutoRotate
	humanoid.WalkSpeed = 0
	humanoid.AutoRotate = false

	local flatDirection = Vector3.new(direction.X, 0, direction.Z)
	if flatDirection.Magnitude < 0.01 then
		flatDirection = Vector3.new(0, 0, -1)
	else
		flatDirection = flatDirection.Unit
	end

	local knockbackForce = ChargeUtil.getKnockback(charge01)
	local knockbackUp = ChargeUtil.getKnockbackUp(charge01)
	local stunDuration = ChargeUtil.getStunDuration(charge01)

	character:SetAttribute("TackleBallRagdollActive", true)
	AnimationUtil.stopAllForRagdoll(character)
	AnimationUtil.stopTackleDive(character)

	local ragdollActive = RagdollUtil.enable(character)
	if not ragdollActive then
		warn("TackleBall: ragdoll enable failed, using impulse-only knockback")
	end
	local recoveryStarted = false
	local recovered = false
	local floorConnection: RBXScriptConnection? = nil
	local movementLockConnection: RBXScriptConnection? = nil
	local ragdollStartedAt = os.clock()
	local minFloorTime = math.max(stunDuration, Config.TACKLE_RAGDOLL_MIN_FLOOR_TIME)

	local function recoverMovement()
		if recovered then
			return
		end
		recovered = true

		if floorConnection then
			floorConnection:Disconnect()
			floorConnection = nil
		end

		if movementLockConnection then
			movementLockConnection:Disconnect()
			movementLockConnection = nil
		end

		if root.Parent then
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
		end

		if character.Parent then
			RagdollUtil.disable(character)
		end

		if humanoid.Parent then
			humanoid.WalkSpeed = oldWalkSpeed
			humanoid.AutoRotate = oldAutoRotate
		end

		if character.Parent then
			character:SetAttribute("TackleBallRagdollActive", nil)
			AnimationUtil.restoreAfterRagdoll(character)
		end

		if networkOwner then
			pcall(function()
				root:SetNetworkOwner(networkOwner)
			end)
		end

		if onRecovered then
			onRecovered()
		end
	end

	local function tryRecoverFromRagdoll()
		if isLethal or recoveryStarted or recovered then
			return
		end
		if not self:_isCarrierOnFloor(humanoid, root, character) then
			return
		end
		if root.AssemblyLinearVelocity.Magnitude > Config.TACKLE_RAGDOLL_SETTLE_SPEED then
			return
		end

		if os.clock() - ragdollStartedAt < minFloorTime then
			return
		end

		recoveryStarted = true
		if floorConnection then
			floorConnection:Disconnect()
			floorConnection = nil
		end

		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero

		RagdollUtil.disable(character)
		if recoverInFrontOfRoot and recoverForwardDistance then
			self:_snapCharacterInFrontOfCarrier(root, character, recoverInFrontOfRoot, recoverForwardDistance)
		else
			self:_snapCarrierToFloor(root, character)
		end
		recoverMovement()
	end

	pcall(function()
		root:SetNetworkOwner(nil)
	end)

	if faceFromPosition then
		local toSource = faceFromPosition - root.Position
		local flat = Vector3.new(toSource.X, 0, toSource.Z)
		if flat.Magnitude > 0.01 then
			root.CFrame = CFrame.lookAt(root.Position, root.Position + flat.Unit)
		end
	end

	local function applyKnockback()
		root.AssemblyLinearVelocity = flatDirection * knockbackForce + Vector3.new(0, knockbackUp, 0)

		local spin = ChargeUtil.lerp(Config.TACKLE_KNOCKBACK_SPIN_MIN, Config.TACKLE_KNOCKBACK_SPIN_MAX, ChargeUtil.getKnockbackPower01(charge01))
		root.AssemblyAngularVelocity = Vector3.new(
			(math.random() - 0.5) * 2 * spin,
			(math.random() - 0.5) * 2 * spin,
			(math.random() - 0.5) * 2 * spin
		)

		local limbImpulseScale = Config.RAGDOLL_LIMB_IMPULSE_SCALE
		local limbAngularScale = Config.RAGDOLL_LIMB_ANGULAR_IMPULSE_SCALE
		if limbImpulseScale > 0 or limbAngularScale > 0 then
			local limbImpulse = flatDirection * knockbackForce * limbImpulseScale
			local limbNames = {
				"LeftUpperArm",
				"RightUpperArm",
				"LeftLowerArm",
				"RightLowerArm",
				"LeftUpperLeg",
				"RightUpperLeg",
				"LeftLowerLeg",
				"RightLowerLeg",
				"Head",
			}
			for _, limbName in limbNames do
				local part = character:FindFirstChild(limbName)
				if part and part:IsA("BasePart") then
					if limbImpulseScale > 0 then
						part:ApplyImpulse(limbImpulse * (0.5 + math.random() * 0.5))
					end
					if limbAngularScale > 0 then
						part:ApplyAngularImpulse(
							Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
								* knockbackForce
								* limbAngularScale
						)
					end
				end
			end
		end
	end

	task.defer(applyKnockback)

	movementLockConnection = RunService.Heartbeat:Connect(function()
		if recovered or not humanoid.Parent then
			return
		end

		if character:GetAttribute("TackleBallRagdollActive") == true then
			humanoid.WalkSpeed = 0
			humanoid.AutoRotate = false
		end
	end)

	local function finishLethalDeath()
		if recovered then
			return
		end
		recovered = true

		if floorConnection then
			floorConnection:Disconnect()
			floorConnection = nil
		end

		if movementLockConnection then
			movementLockConnection:Disconnect()
			movementLockConnection = nil
		end

		if self._healthService then
			self._healthService:shatterDeath(character, nil)
		end
	end

	if isLethal then
		task.delay(Config.HEALTH_BAR_DEATH_SHATTER_DELAY, finishLethalDeath)
		task.delay(stunDuration + Config.TACKLE_GETUP_MAX_WAIT, finishLethalDeath)
	else
		floorConnection = RunService.Heartbeat:Connect(function()
			tryRecoverFromRagdoll()
		end)

		task.delay(stunDuration + Config.TACKLE_GETUP_MAX_WAIT, function()
			if not recovered then
				if not recoveryStarted then
					RagdollUtil.disable(character)
					if recoverInFrontOfRoot and recoverForwardDistance then
						self:_snapCharacterInFrontOfCarrier(root, character, recoverInFrontOfRoot, recoverForwardDistance)
					else
						self:_snapCarrierToFloor(root, character)
					end
				end
				recoverMovement()
			end
		end)
	end
end

function MatchService:_launchCarrierCharacter(
	character: Model,
	tackler: Player,
	direction: Vector3,
	charge01: number,
	networkOwner: Player?,
	onRecovered: (() -> ())?
)
	local tacklerRoot = self:_getRoot(tackler)
	local faceFrom = tacklerRoot and tacklerRoot.Position
	self:_launchRagdollCharacter(character, direction, charge01, faceFrom, networkOwner, onRecovered)
end

function MatchService:_launchCarrier(carrier: Player, tackler: Player, direction: Vector3, charge01: number)
	local character = carrier.Character
	if not character then
		return
	end

	self:_launchCarrierCharacter(character, tackler, direction, charge01, carrier, nil)
end

function MatchService:isCarrierShedding(player: Player): boolean
	return self._sheddingCarriers[player.UserId] == true
end

function MatchService:onTackleShed(
	carrier: Player,
	tackler: Player,
	direction: Vector3,
	dodgeType: string?,
	jukeSide: number?,
	truckCharge01: number?
)
	if self._state ~= "Active" or self._carrier ~= carrier then
		return
	end

	dodgeType = if dodgeType == "Juke" then "Juke" else "Truck"
	jukeSide = jukeSide or 0

	local character = carrier.Character
	if not character then
		return
	end

	if self._tackleService then
		self._tackleService:stopJukeDash(carrier, false)
		self._tackleService:stopTruckDash(carrier, false)
	end

	self._sheddingCarriers[carrier.UserId] = true
	character:SetAttribute("TruckTuckWindowActive", nil)
	character:SetAttribute("TruckTuckActive", true)
	character:SetAttribute("DodgeType", dodgeType)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		self._sheddingCarriers[carrier.UserId] = nil
		character:SetAttribute("TruckTuckActive", nil)
		character:SetAttribute("DodgeType", nil)
		return
	end

	local boostVector: Vector3
	if dodgeType == "Juke" and jukeSide ~= 0 then
		local right = root.CFrame.RightVector
		local flatRight = Vector3.new(right.X, 0, right.Z)
		if flatRight.Magnitude < 0.01 then
			flatRight = Vector3.new(1, 0, 0)
		else
			flatRight = flatRight.Unit
		end
		boostVector = flatRight * (jukeSide * Config.SHED_LATERAL_BOOST)
	else
		local flatDirection = Vector3.new(direction.X, 0, direction.Z)
		if flatDirection.Magnitude < 0.01 then
			flatDirection = Vector3.new(0, 0, -1)
		else
			flatDirection = flatDirection.Unit
		end
		boostVector = flatDirection * ChargeUtil.getTruckShedBoost(truckCharge01 or Config.CHARGE_NORMAL_CHARGE01)
	end

	root.AssemblyLinearVelocity = boostVector + Vector3.new(0, Config.SHED_SPEED_BOOST_UP, 0)
	humanoid.WalkSpeed = Config.SHED_SPEED_BOOST

	local function finishShed()
		if not self._sheddingCarriers[carrier.UserId] then
			return
		end

		self._sheddingCarriers[carrier.UserId] = nil

		if character.Parent then
			character:SetAttribute("TruckTuckWindowActive", nil)
			character:SetAttribute("TruckTuckActive", nil)
			character:SetAttribute("DodgeType", nil)
			AnimationUtil.stopDodge(character)
		end

		if humanoid.Parent and self._carrier == carrier then
			humanoid.WalkSpeed = Config.DEFAULT_WALK_SPEED
		end
	end

	if not AnimationUtil.isDodgePlaying(character) then
		AnimationUtil.playDodge(character, dodgeType, nil, nil, jukeSide)
	end

	task.delay(Config.SHED_ANIM_DURATION + 0.1, function()
		if self._sheddingCarriers[carrier.UserId] then
			finishShed()
		end
	end)
end

function MatchService:onTruckBeatTackle(
	carrier: Player,
	direction: Vector3,
	truckCharge01: number,
	victimCharacter: Model,
	victimPlayer: Player?
)
	if self._state ~= "Active" or self._carrier ~= carrier then
		return
	end

	self:onTackleShed(carrier, victimPlayer, direction, "Truck", 0, truckCharge01)

	local carrierRoot = self:_getRoot(carrier)
	local knockDirection = if carrierRoot then self:_getFlatLookVector(carrierRoot) else direction
	local faceFrom = carrierRoot and carrierRoot.Position
	local isDummyTackler = victimCharacter:GetAttribute("TackleBallDummyTackler") == true

	local function onVictimRecovered()
		if isDummyTackler then
			self:_respawnDummyTacklerAfterHit(carrier, victimCharacter)
		end
	end

	self:_launchRagdollCharacter(
		victimCharacter,
		knockDirection,
		truckCharge01,
		faceFrom,
		victimPlayer,
		onVictimRecovered,
		carrierRoot,
		Config.TRUCK_VICTIM_LANDING_DISTANCE
	)
end

function MatchService:onDummyTackleHit(carrier: Player, direction: Vector3, charge01: number, tacklerDummy: Model?)
	if self._state ~= "Active" or self._carrier ~= carrier then
		return
	end

	local carrierCharacter = carrier.Character
	if not carrierCharacter then
		return
	end

	if self._tackleService then
		self._tackleService:stopJukeDash(carrier, false)
		self._tackleService:stopTruckDash(carrier, false)
	end

	AnimationUtil.stopDodge(carrierCharacter)
	AnimationUtil.stopAllForRagdoll(carrierCharacter)
	carrierCharacter:SetAttribute("TruckTuckWindowActive", nil)
	carrierCharacter:SetAttribute("TruckTuckActive", nil)
	carrierCharacter:SetAttribute("DodgeType", nil)

	local dummy = tacklerDummy
	if not dummy and self._dummyTacklerService then
		dummy = self._dummyTacklerService:getDummy()
	end
	local dummyRoot = dummy and dummy:FindFirstChild("HumanoidRootPart") :: BasePart?
	local carrierRoot = self:_getRoot(carrier)
	if dummyRoot and carrierRoot then
		local toDummy = dummyRoot.Position - carrierRoot.Position
		local flat = Vector3.new(toDummy.X, 0, toDummy.Z)
		if flat.Magnitude > 0.01 then
			carrierRoot.CFrame = CFrame.lookAt(carrierRoot.Position, carrierRoot.Position + flat.Unit)
		end
	end

	self._carrier = nil
	if self._moneyService then
		self._moneyService:onBallKnockedLoose()
	end
	self._ballService:knockoutBall(direction, charge01)
	self:_broadcastState()

	local facePlayer = carrier
	if GameMode.isSoloMode() then
		self:_startLooseBallContest(carrier)
	end
	self:_launchCarrierCharacter(carrierCharacter, facePlayer, direction, charge01, carrier, function()
		if not GameMode.isSoloMode() then
			self:_respawnDummyTacklerAfterHit(carrier, dummy)
		end
	end)
end

function MatchService:onNpcCarrierTackleHit(_tacklerDummy: Model, carrierDummy: Model, direction: Vector3, charge01: number)
	if self._state ~= "Active" then
		return
	end

	if self._dummyTacklerService then
		self._dummyTacklerService:clearCarrierDummy()
	end

	AnimationUtil.stopDodge(carrierDummy)
	AnimationUtil.stopAllForRagdoll(carrierDummy)
	carrierDummy:SetAttribute("TruckTuckWindowActive", nil)
	carrierDummy:SetAttribute("TruckTuckActive", nil)
	carrierDummy:SetAttribute("DodgeType", nil)

	if self._moneyService then
		self._moneyService:onBallKnockedLoose()
	end
	self._ballService:knockoutBall(direction, charge01)
	self:_broadcastState()

	local player = Players:GetPlayers()[1]
	if player then
		self:_startLooseBallContest(player)
	end

	self:_launchRagdollCharacter(carrierDummy, direction, charge01, nil, nil, nil)
end

function MatchService:handleCharacterDeath(character: Model)
	if self._state ~= "Active" then
		return
	end

	local carrierCharacter = self:getCarrierCharacter()
	if not carrierCharacter or carrierCharacter ~= character then
		return
	end

	local humanCarrier = self._carrier
	if humanCarrier and self._tackleService then
		self._tackleService:stopJukeDash(humanCarrier, false)
		self._tackleService:stopTruckDash(humanCarrier, false)
	end

	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local direction = Vector3.new(0, 0, 1)
	if root then
		local flatLook = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
		if flatLook.Magnitude > 0.01 then
			direction = -flatLook.Unit
		end
	end

	if self._moneyService then
		self._moneyService:onBallKnockedLoose()
	end
	self._carrier = nil
	if GameMode.isSoloMode() and self._dummyTacklerService then
		self._dummyTacklerService:clearCarrierDummy()
	end
	self._ballService:knockoutBall(direction, Config.CHARGE_NORMAL_CHARGE01)
	self:_broadcastState()

	if GameMode.isSoloMode() then
		local contestPlayer = humanCarrier
		if not contestPlayer then
			local players = Players:GetPlayers()
			contestPlayer = players[1]
		end
		if contestPlayer then
			self:_startLooseBallContest(contestPlayer)
		end
	elseif humanCarrier and self._soloTestRole == "tackler" then
		self:_respawnDummyAfterTackle(humanCarrier)
	end
end

function MatchService:onPushHit(tackler: Player, victimCharacter: Model, direction: Vector3, charge01: number)
	if self._state ~= "Active" then
		return
	end

	AnimationUtil.stopDodge(victimCharacter)
	AnimationUtil.stopAllForRagdoll(victimCharacter)
	victimCharacter:SetAttribute("TruckTuckWindowActive", nil)
	victimCharacter:SetAttribute("TruckTuckActive", nil)
	victimCharacter:SetAttribute("DodgeType", nil)

	local victimPlayer = Players:GetPlayerFromCharacter(victimCharacter)
	local tacklerRoot = self:_getRoot(tackler)
	local faceFrom = tacklerRoot and tacklerRoot.Position

	self:_launchRagdollCharacter(
		victimCharacter,
		direction,
		charge01,
		faceFrom,
		victimPlayer or tackler,
		nil
	)
end

function MatchService:onTackleHit(tackler: Player, victimCharacter: Model, direction: Vector3, charge01: number)
	if self._state ~= "Active" then
		return
	end

	if GameMode.isTeamsMode() and self._teamService then
		local tacklerCharacter = tackler.Character
		if tacklerCharacter and self._teamService:areTeammates(tacklerCharacter, victimCharacter) then
			return
		end
	end

	local carrierCharacter = self:getCarrierCharacter()
	if not carrierCharacter or victimCharacter ~= carrierCharacter then
		self:onPushHit(tackler, victimCharacter, direction, charge01)
		return
	end

	local humanCarrier = self._carrier
	if humanCarrier and self._tackleService then
		self._tackleService:stopJukeDash(humanCarrier, false)
		self._tackleService:stopTruckDash(humanCarrier, false)
	end

	AnimationUtil.stopDodge(carrierCharacter)
	AnimationUtil.stopAllForRagdoll(carrierCharacter)
	carrierCharacter:SetAttribute("TruckTuckWindowActive", nil)
	carrierCharacter:SetAttribute("TruckTuckActive", nil)
	carrierCharacter:SetAttribute("DodgeType", nil)

	if humanCarrier and tackler == humanCarrier then
		return
	end

	local isNpcCarrier = not humanCarrier
		and carrierCharacter
		and carrierCharacter:GetAttribute("TackleBallDummy") == true

	if isNpcCarrier then
		if self._moneyService then
			self._moneyService:onBallKnockedLoose()
		end
		self._carrier = nil
		if GameMode.isSoloMode() and self._dummyTacklerService then
			self._dummyTacklerService:clearCarrierDummy()
		end
		self._ballService:knockoutBall(direction, charge01)
		self:_broadcastState()
		if GameMode.isSoloMode() or GameMode.isTeamsMode() then
			self:_startLooseBallContest(tackler)
		end
		self:_launchCarrierCharacter(carrierCharacter, tackler, direction, charge01, nil, nil)
		return
	end

	if not humanCarrier then
		return
	end

	if self._moneyService then
		self._moneyService:onBallKnockedLoose()
	end
	self._carrier = nil
	self._ballService:knockoutBall(direction, charge01)
	self:_launchCarrier(humanCarrier, tackler, direction, charge01)
	self:_broadcastState()
	if GameMode.isSoloMode() or GameMode.isTeamsMode() then
		self:_startLooseBallContest(tackler)
	end
end

function MatchService:score(carrier: Player)
	if GameMode.isTeamsMode() then
		return
	end

	if self._state ~= "Active" or self._carrier ~= carrier or self._scoreLocked then
		return
	end

	self._scoreLocked = true
	local deposited = 0
	if self._moneyService then
		deposited = self._moneyService:onScore(carrier)
	end
	self._lastScoredAmount = deposited
	self._lastBankTotal = if self._moneyService then self._moneyService:getBanks()[carrier.UserId] or 0 else nil
	self._scores[carrier.UserId] = (self._scores[carrier.UserId] or 0) + 1
	self._winnerName = carrier.DisplayName
	self._scorerUserId = carrier.UserId
	local carrierCharacter = carrier.Character
	self._scorerCharacter = carrierCharacter
	local root = carrierCharacter and carrierCharacter:FindFirstChild("HumanoidRootPart")
	self._scorerPosition = if root then root.Position else nil
	self._carrier = nil
	if GameMode.isSoloMode() and self._dummyTacklerService then
		self._dummyTacklerService:clearCarrierDummy()
	end

	if self._scores[carrier.UserId] >= Config.WIN_SCORE then
		self._gameWinner = carrier
		self:_setState("Scored")
		self._ballService:setCarrier(nil)
		task.delay(1, function()
			self._scoreLocked = false
		end)
		return
	end

	self:_setState("Scored")
	self._ballService:setCarrier(nil)
	task.delay(1, function()
		self._scoreLocked = false
	end)
end

function MatchService:scoreNpcCarrier(carrierCharacter: Model)
	if GameMode.isTeamsMode() then
		return
	end

	if self._state ~= "Active" or self._scoreLocked then
		return
	end

	if GameMode.isSoloMode() and self._dummyTacklerService then
		if carrierCharacter ~= self._dummyTacklerService:getCarrierDummy() then
			return
		end
	end

	self._scoreLocked = true
	local scoredAmount = 0
	if self._moneyService then
		scoredAmount = self._moneyService:getBallWorth()
		self._moneyService:onCarrierLost()
	end
	self._lastScoredAmount = scoredAmount
	self._lastBankTotal = nil
	self._npcScore += 1
	local humanoid = carrierCharacter:FindFirstChildOfClass("Humanoid")
	self._winnerName = humanoid and humanoid.DisplayName or "NPC"
	self._scorerUserId = nil
	self._scorerCharacter = carrierCharacter
	local root = carrierCharacter:FindFirstChild("HumanoidRootPart")
	self._scorerPosition = if root then root.Position else nil
	self._carrier = nil
	if self._dummyTacklerService then
		self._dummyTacklerService:clearCarrierDummy()
	end
	self._ballService:setCarrier(nil)

	if self._npcScore >= Config.WIN_SCORE then
		self._npcGameWon = true
		self:_setState("Scored")
		task.delay(1, function()
			self._scoreLocked = false
		end)
		return
	end

	self:_setState("Scored")
	task.delay(1, function()
		self._scoreLocked = false
	end)
end

function MatchService:scoreTeamCarrier(carrierCharacter: Model, team: Types.TeamName, scoringPlayer: Player?)
	if not GameMode.isTeamsMode() or self._state ~= "Active" or self._scoreLocked then
		return
	end

	if self._carrier and scoringPlayer and self._carrier ~= scoringPlayer then
		return
	end

	if not self._carrier and carrierCharacter then
		local ballCharacter = self._ballService:getCarrierCharacter()
		if ballCharacter ~= carrierCharacter then
			return
		end
	end

	self._scoreLocked = true
	local deposited = 0
	if scoringPlayer and self._moneyService then
		deposited = self._moneyService:onScore(scoringPlayer)
	elseif self._moneyService then
		deposited = self._moneyService:getBallWorth()
		self._moneyService:onCarrierLost()
	end

	self._lastScoredAmount = deposited
	self._lastBankTotal = if scoringPlayer and self._moneyService
		then self._moneyService:getBanks()[scoringPlayer.UserId] or 0
		else nil

	local teamScore = 0
	if self._teamService then
		teamScore = self._teamService:addTeamScore(team)
	end

	self._winnerName = `{team} Team`
	self._scorerUserId = if scoringPlayer then scoringPlayer.UserId else nil
	self._scorerCharacter = carrierCharacter
	local root = carrierCharacter and carrierCharacter:FindFirstChild("HumanoidRootPart")
	self._scorerPosition = if root then root.Position else nil
	self._carrier = nil

	if self._dummyTacklerService then
		self._dummyTacklerService:clearCarrierDummy()
	end

	self._ballService:setCarrier(nil)

	if teamScore >= Config.WIN_SCORE and self._teamService then
		self._teamService:setTeamsGameWinner(team)
		self:_setState("Scored")
		task.delay(1, function()
			self._scoreLocked = false
		end)
		return
	end

	self:_setState("Scored")
	task.delay(1, function()
		self._scoreLocked = false
	end)
end

function MatchService:_runIntermission()
	self._timeRemaining = Config.INTERMISSION_DURATION
	self:_setState("Intermission")

	while self._timeRemaining > 0 do
		task.wait(1)
		self._timeRemaining -= 1
		self:_broadcastState()
	end
end

function MatchService:_runActiveRound()
	while self._state == "Active" and self._timeRemaining > 0 do
		task.wait(1)
		self._timeRemaining -= 1
		self:_broadcastState()
	end

	if self._state == "Scored" then
		self._timeRemaining = Config.INTERMISSION_DURATION
		self:_setState("Intermission")
		return
	end

	if self._state == "Active" then
		if self._moneyService then
			self._moneyService:onCarrierLost()
		end
		self._ballService:setCarrier(nil)
		self._carrier = nil
		if self._dummyCarrierService then
			self._dummyCarrierService:despawn()
		end
		if self._dummyTacklerService then
			self._dummyTacklerService:despawn()
		end
		self:_setState("Intermission")
	end
end

function MatchService:_runGameLoop()
	self:_setState("Waiting")

	if not GameMode.shouldSkipLobbyWait() then
		self._timeRemaining = Config.AUTO_START_DELAY

		while self._timeRemaining > 0 do
			if #Players:GetPlayers() >= GameMode.getMinPlayers() then
				break
			end
			task.wait(1)
			self._timeRemaining -= 1
			self:_broadcastState()
		end
	end

	while true do
		if #Players:GetPlayers() < GameMode.getMinPlayers() then
			self._state = "Waiting"
			if not GameMode.shouldSkipLobbyWait() then
				self._timeRemaining = Config.AUTO_START_DELAY
			end
			self._carrier = nil
			self._ballService:setCarrier(nil)
			if self._moneyService then
				self._moneyService:onCarrierLost()
			end
			if self._dummyCarrierService then
				self._dummyCarrierService:despawn()
			end
			if self._dummyTacklerService then
				self._dummyTacklerService:despawn()
			end
			self:_broadcastState()

			while #Players:GetPlayers() < GameMode.getMinPlayers() do
				task.wait(1)
			end

			if not GameMode.shouldSkipLobbyWait() then
				self._timeRemaining = Config.AUTO_START_DELAY
				while self._timeRemaining > 0 do
					task.wait(1)
					self._timeRemaining -= 1
					self:_broadcastState()
				end
			end
		end

		self:startRound()
		self:_runActiveRound()

		if self._state == "Intermission" then
			self:_runIntermission()
		end

		if self:_isMatchComplete() then
			self:_finishMatchAndReturnToLobby()

			while #Players:GetPlayers() > 0 do
				task.wait(1)
			end
		end
	end
end

return MatchService
