local Workspace = game:GetService("Workspace")

local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
local GameMode = require(game:GetService("ReplicatedStorage").Shared.GameMode)
local SoccerFieldUtil = require(game:GetService("ReplicatedStorage").Shared.SoccerFieldUtil)

export type PlayBounds = {
	min: Vector3,
	max: Vector3,
}

local ArenaBoundsUtil = {}

local function normalizePlayBounds(bounds: PlayBounds): PlayBounds
	return {
		min = Vector3.new(
			math.min(bounds.min.X, bounds.max.X),
			math.min(bounds.min.Y, bounds.max.Y),
			math.min(bounds.min.Z, bounds.max.Z)
		),
		max = Vector3.new(
			math.max(bounds.min.X, bounds.max.X),
			math.max(bounds.min.Y, bounds.max.Y),
			math.max(bounds.min.Z, bounds.max.Z)
		),
	}
end

local function getStadiumFloorTopY(): number?
	if not GameMode.usesStadiumLayout() then
		return nil
	end

	local field = SoccerFieldUtil.findByPath(Workspace, Config.STADIUM_SOCCER_FIELD_PATH)
	if not field then
		return nil
	end

	return SoccerFieldUtil.getFloorTopY(field)
end

local function getDefaultMaxY(floorTopY: number?): number
	if floorTopY then
		return floorTopY + Config.ARENA_PLAY_MAX_Y
	end

	return Config.ARENA_PLAY_MAX_Y
end

local function tryBoundsFromSoccerField(): PlayBounds?
	if not GameMode.usesStadiumLayout() then
		return nil
	end

	local field = SoccerFieldUtil.findByPath(Workspace, Config.STADIUM_SOCCER_FIELD_PATH)
	if not field then
		return nil
	end

	return normalizePlayBounds(
		SoccerFieldUtil.getPlayBoundsFromField(field, Config.ARENA_BOUND_INSET, Config.ARENA_PLAY_MAX_Y)
	)
end

local function tryBoundsFromWalls(): PlayBounds?
	local folder = Workspace:FindFirstChild("ArenaBoundaries")
	if not folder then
		local stadiumField = SoccerFieldUtil.findByPath(Workspace, Config.STADIUM_SOCCER_FIELD_PATH)
		if stadiumField then
			folder = stadiumField:FindFirstChild(Config.STADIUM_BOUNDARY_FOLDER_NAME)
		end
	end

	if not folder then
		return nil
	end

	local minX = -math.huge
	local maxX = math.huge
	local minZ = -math.huge
	local maxZ = math.huge
	local floorTopY = getStadiumFloorTopY()
	local maxY = getDefaultMaxY(floorTopY)
	local foundWall = false
	local inset = Config.ARENA_BOUND_INSET

	for _, child in folder:GetChildren() do
		if child:IsA("BasePart") then
			if child.Name == "Ceiling" then
				maxY = child.Position.Y - child.Size.Y * 0.5 - inset
			elseif child.Name == "WallNorth" then
				foundWall = true
				maxZ = child.Position.Z - child.Size.Z * 0.5 - inset
			elseif child.Name == "WallSouth" then
				foundWall = true
				minZ = child.Position.Z + child.Size.Z * 0.5 + inset
			elseif child.Name == "WallEast" then
				foundWall = true
				maxX = child.Position.X - child.Size.X * 0.5 - inset
			elseif child.Name == "WallWest" then
				foundWall = true
				minX = child.Position.X + child.Size.X * 0.5 + inset
			end
		end
	end

	if not foundWall then
		return nil
	end

	local minY = Config.ARENA_PLAY_MIN_Y
	if floorTopY then
		minY = floorTopY - Config.FLOOR_SAFETY_MARGIN
	elseif GameMode.usesStadiumLayout() then
		local field = SoccerFieldUtil.findByPath(Workspace, Config.STADIUM_SOCCER_FIELD_PATH)
		if field then
			minY = SoccerFieldUtil.getFloorTopY(field) - Config.FLOOR_SAFETY_MARGIN
		end
	else
		local floor = Workspace:FindFirstChild(Config.ARENA_FLOOR_NAME)
		if floor and floor:IsA("BasePart") then
			minY = floor.Position.Y + floor.Size.Y * 0.5 - 1
		end
	end

	return normalizePlayBounds({
		min = Vector3.new(minX, minY, minZ),
		max = Vector3.new(maxX, maxY, maxZ),
	})
end

function ArenaBoundsUtil.getPlayBounds(): PlayBounds
	if GameMode.usesStadiumLayout() then
		local fromWalls = tryBoundsFromWalls()
		if fromWalls then
			return fromWalls
		end

		local fromSoccerField = tryBoundsFromSoccerField()
		if fromSoccerField then
			return fromSoccerField
		end
	end

	local fromWalls = tryBoundsFromWalls()
	if fromWalls then
		return fromWalls
	end

	local halfX = Config.ARENA_PLAY_HALF_X
	local halfZ = Config.ARENA_PLAY_HALF_Z
	local minY = Config.ARENA_PLAY_MIN_Y
	local maxY = Config.ARENA_PLAY_MAX_Y
	local inset = Config.ARENA_BOUND_INSET

	local floor = Workspace:FindFirstChild(Config.ARENA_FLOOR_NAME)
	if floor and floor:IsA("BasePart") then
		local floorHalf = floor.Size * 0.5
		halfX = floorHalf.X - inset
		halfZ = floorHalf.Z - inset
		local floorTopY = floor.Position.Y + floorHalf.Y
		minY = floorTopY - Config.FLOOR_SAFETY_MARGIN
		maxY = floorTopY + Config.ARENA_PLAY_MAX_Y
	end

	return normalizePlayBounds({
		min = Vector3.new(-halfX, minY, -halfZ),
		max = Vector3.new(halfX, maxY, halfZ),
	})
end

function ArenaBoundsUtil.isInside(position: Vector3): boolean
	local bounds = ArenaBoundsUtil.getPlayBounds()
	return position.X >= bounds.min.X
		and position.X <= bounds.max.X
		and position.Y >= bounds.min.Y
		and position.Y <= bounds.max.Y
		and position.Z >= bounds.min.Z
		and position.Z <= bounds.max.Z
end

function ArenaBoundsUtil.clampPosition(position: Vector3): Vector3
	local bounds = ArenaBoundsUtil.getPlayBounds()
	return Vector3.new(
		math.clamp(position.X, bounds.min.X, bounds.max.X),
		math.clamp(position.Y, bounds.min.Y, bounds.max.Y),
		math.clamp(position.Z, bounds.min.Z, bounds.max.Z)
	)
end

return ArenaBoundsUtil
