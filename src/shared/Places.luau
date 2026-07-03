local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Places = {
	MAIN_MENU_PLACE_ID = 73490771045679,
	SOLO_ARENA_PLACE_ID = 95975589855069,
	TEAMS_ARENA_PLACE_ID = 79166542960911,
	-- Backward-compatible alias
	ARENA_PLACE_ID = 95975589855069,
}

export type ArenaGameMode = "solo" | "teams"

local function hasArenaWorkspace(): boolean
	return Workspace:FindFirstChild("Field") ~= nil
		or Workspace:FindFirstChild("ArenaFloor") ~= nil
		or Workspace:FindFirstChild("Stadium") ~= nil
end

function Places.isArenaPlace(): boolean
	if game.PlaceId == Places.SOLO_ARENA_PLACE_ID or game.PlaceId == Places.TEAMS_ARENA_PLACE_ID then
		return true
	end

	if RunService:IsStudio() then
		return hasArenaWorkspace()
	end

	return false
end

function Places.isMainMenuPlace(): boolean
	if game.PlaceId == Places.MAIN_MENU_PLACE_ID then
		return true
	end

	if RunService:IsStudio() and game.PlaceId == 0 then
		return not Places.isArenaPlace()
	end

	return false
end

function Places.getArenaGameMode(): ArenaGameMode?
	if game.PlaceId == Places.SOLO_ARENA_PLACE_ID then
		return "solo"
	end

	if game.PlaceId == Places.TEAMS_ARENA_PLACE_ID then
		return "teams"
	end

	return nil
end

function Places.getArenaPlaceIdForMode(mode: string): number?
	if mode == "solo" then
		return Places.SOLO_ARENA_PLACE_ID
	end

	if mode == "teams" then
		return Places.TEAMS_ARENA_PLACE_ID
	end

	return nil
end

return Places
