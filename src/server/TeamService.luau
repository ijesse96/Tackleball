local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)

type TeamName = Types.TeamName

local TEAM_ATTRIBUTE = "TackleBallTeam"

local TeamService = {}
TeamService._teamScores = { Blue = 0, Red = 0 } :: Types.TeamScores
TeamService._teamsGameWinner = nil :: TeamName?
TeamService._bluePlayers = {} :: { Player }
TeamService._redPlayers = {} :: { Player }
TeamService._blueDummies = {} :: { Model }
TeamService._redDummies = {} :: { Model }

local function isTeamName(value: any): boolean
	return value == Config.TEAM_A_NAME or value == Config.TEAM_B_NAME
end

local function getOppositeTeam(team: TeamName): TeamName
	return if team == Config.TEAM_A_NAME then Config.TEAM_B_NAME else Config.TEAM_A_NAME
end

function TeamService:getTeamColors(team: TeamName): (Color3, Color3)
	if team == Config.TEAM_A_NAME then
		return Config.TEAM_A_HEAD_COLOR, Config.TEAM_A_TORSO_COLOR
	end

	return Config.TEAM_B_HEAD_COLOR, Config.TEAM_B_TORSO_COLOR
end

function TeamService:applyTeamVisuals(character: Model, team: TeamName)
	local headColor, torsoColor = self:getTeamColors(team)

	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			local lowered = string.lower(part.Name)
			if lowered == "head" then
				part.Color = headColor
			elseif string.find(lowered, "arm") or string.find(lowered, "leg") or string.find(lowered, "torso") or string.find(lowered, "hand") or string.find(lowered, "foot") then
				part.Color = torsoColor
			end
		end
	end
end

function TeamService:setEntityTeam(entity: Player | Model, team: TeamName)
	entity:SetAttribute(TEAM_ATTRIBUTE, team)

	if entity:IsA("Player") then
		local character = entity.Character
		if character then
			character:SetAttribute(TEAM_ATTRIBUTE, team)
			self:applyTeamVisuals(character, team)
		end
	elseif entity:IsA("Model") then
		self:applyTeamVisuals(entity, team)
	end
end

function TeamService:getTeam(entity: Player | Model?): TeamName?
	if not entity then
		return nil
	end

	local team = entity:GetAttribute(TEAM_ATTRIBUTE)
	if isTeamName(team) then
		return team
	end

	if entity:IsA("Model") then
		local player = Players:GetPlayerFromCharacter(entity)
		if player then
			local playerTeam = player:GetAttribute(TEAM_ATTRIBUTE)
			if isTeamName(playerTeam) then
				return playerTeam
			end
		end
	end

	return nil
end

function TeamService:areTeammates(a: Player | Model, b: Player | Model): boolean
	local teamA = self:getTeam(a)
	local teamB = self:getTeam(b)
	return teamA ~= nil and teamA == teamB
end

function TeamService:areOpponents(a: Player | Model, b: Player | Model): boolean
	local teamA = self:getTeam(a)
	local teamB = self:getTeam(b)
	return teamA ~= nil and teamB ~= nil and teamA ~= teamB
end

function TeamService:getGoalEndzone(team: TeamName): string
	if team == Config.TEAM_A_NAME then
		return Config.TEAM_A_GOAL_ENDZONE
	end

	return Config.TEAM_B_GOAL_ENDZONE
end

function TeamService:getTeamScore(team: TeamName): number
	return self._teamScores[team]
end

function TeamService:getTeamScores(): Types.TeamScores
	return {
		Blue = self._teamScores.Blue,
		Red = self._teamScores.Red,
	}
end

function TeamService:addTeamScore(team: TeamName): number
	self._teamScores[team] += 1
	return self._teamScores[team]
end

function TeamService:getTeamsGameWinner(): TeamName?
	return self._teamsGameWinner
end

function TeamService:setTeamsGameWinner(team: TeamName)
	self._teamsGameWinner = team
end

function TeamService:clearTeamsGameWinner()
	self._teamsGameWinner = nil
end

function TeamService:getBluePlayers(): { Player }
	return self._bluePlayers
end

function TeamService:getRedPlayers(): { Player }
	return self._redPlayers
end

function TeamService:getBlueDummies(): { Model }
	return self._blueDummies
end

function TeamService:getRedDummies(): { Model }
	return self._redDummies
end

function TeamService:getTeamMembers(team: TeamName): { Player | Model }
	local members: { Player | Model } = {}
	local players = if team == Config.TEAM_A_NAME then self._bluePlayers else self._redPlayers
	local dummies = if team == Config.TEAM_A_NAME then self._blueDummies else self._redDummies

	for _, player in players do
		table.insert(members, player)
	end

	for _, dummy in dummies do
		if dummy.Parent then
			table.insert(members, dummy)
		end
	end

	return members
end

function TeamService:getAllRosterMembers(): { Player | Model }
	local members: { Player | Model } = {}
	for _, member in self:getTeamMembers(Config.TEAM_A_NAME) do
		table.insert(members, member)
	end
	for _, member in self:getTeamMembers(Config.TEAM_B_NAME) do
		table.insert(members, member)
	end
	return members
end

function TeamService:getPlayerTeam(player: Player): TeamName?
	return self:getTeam(player)
end

function TeamService:assignRoster(players: { Player }, blueDummies: { Model }, redDummies: { Model })
	table.clear(self._bluePlayers)
	table.clear(self._redPlayers)
	table.clear(self._blueDummies)
	table.clear(self._redDummies)

	for index, player in players do
		local team: TeamName = if index % 2 == 1 then Config.TEAM_A_NAME else Config.TEAM_B_NAME
		self:setEntityTeam(player, team)
		if team == Config.TEAM_A_NAME then
			table.insert(self._bluePlayers, player)
		else
			table.insert(self._redPlayers, player)
		end

		if player.Character then
			self:applyTeamVisuals(player.Character, team)
		end
	end

	for _, dummy in blueDummies do
		self:setEntityTeam(dummy, Config.TEAM_A_NAME)
		table.insert(self._blueDummies, dummy)
	end

	for _, dummy in redDummies do
		self:setEntityTeam(dummy, Config.TEAM_B_NAME)
		table.insert(self._redDummies, dummy)
	end
end

function TeamService:clearRoster()
	table.clear(self._bluePlayers)
	table.clear(self._redPlayers)
	table.clear(self._blueDummies)
	table.clear(self._redDummies)

	for _, player in Players:GetPlayers() do
		player:SetAttribute(TEAM_ATTRIBUTE, nil)
	end
end

function TeamService:reset()
	self._teamScores = { Blue = 0, Red = 0 }
	self._teamsGameWinner = nil
	self:clearRoster()
end

function TeamService:getNpcCountNeeded(playerCount: number): (number, number)
	local bluePlayers = 0
	local redPlayers = 0

	for index = 1, playerCount do
		if index % 2 == 1 then
			bluePlayers += 1
		else
			redPlayers += 1
		end
	end

	local blueNeeded = math.max(Config.TEAMS_SIZE - bluePlayers, 0)
	local redNeeded = math.max(Config.TEAMS_SIZE - redPlayers, 0)
	return blueNeeded, redNeeded
end

function TeamService:getOppositeTeamName(team: TeamName): TeamName
	return getOppositeTeam(team)
end

return TeamService
