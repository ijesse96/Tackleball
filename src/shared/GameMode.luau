local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Places = require(ReplicatedStorage.Shared.Places)

export type ArenaGameMode = Places.ArenaGameMode

local GameMode = {}

local function resolveMode(): ArenaGameMode?
	local placeMode = Places.getArenaGameMode()
	if placeMode then
		return placeMode
	end

	if RunService:IsStudio() and Places.isArenaPlace() then
		local attributeMode = ReplicatedStorage:GetAttribute("GameMode")
		if attributeMode == "solo" or attributeMode == "teams" then
			return attributeMode
		end

		local studioMode = Config.STUDIO_ARENA_MODE
		if studioMode == "solo" or studioMode == "teams" then
			return studioMode
		end
	end

	return nil
end

function GameMode.getMode(): ArenaGameMode?
	return resolveMode()
end

function GameMode.isTeamsMode(): boolean
	return resolveMode() == "teams"
end

function GameMode.isSoloMode(): boolean
	return resolveMode() == "solo"
end

function GameMode.isSoloTestMode(): boolean
	return Config.SOLO_TEST_MODE and not GameMode.isTeamsMode() and not GameMode.isSoloMode()
end

function GameMode.shouldSkipLobbyWait(): boolean
	local mode = resolveMode()
	return mode == "teams" or mode == "solo" or Config.SOLO_TEST_MODE
end

function GameMode.getMinPlayers(): number
	if GameMode.shouldSkipLobbyWait() then
		return 1
	end

	if RunService:IsStudio() then
		return 1
	end

	return Config.MIN_PLAYERS_TO_START
end

function GameMode.getEndzoneNames(): { string }
	if GameMode.usesStadiumLayout() then
		return Config.STADIUM_GOAL_NAMES
	end

	return Config.ENDZONE_NAMES
end

function GameMode.usesStadiumLayout(): boolean
	return GameMode.isSoloMode() or GameMode.isTeamsMode()
end

function GameMode.getSoccerFieldPath(): string
	if GameMode.usesStadiumLayout() then
		return Config.STADIUM_SOCCER_FIELD_PATH
	end

	return Config.LOBBY_SOCCER_FIELD_PATH
end

return GameMode
