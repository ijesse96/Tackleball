local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local GameMode = require(ReplicatedStorage.Shared.GameMode)

export type BoundaryOptions = {
	folderName: string,
	wallHeight: number,
	wallThickness: number,
	wallInset: number,
	includeCeiling: boolean?,
	ceilingHeightOffset: number?,
	includeFloor: boolean?,
	floorThickness: number?,
}

local SoccerFieldUtil = {}

function SoccerFieldUtil.findByPath(root: Instance, path: string): Instance?
	local current: Instance? = root
	for segment in string.gmatch(path, "[^/]+") do
		if not current then
			return nil
		end
		current = current:FindFirstChild(segment)
	end

	return current
end

function SoccerFieldUtil.waitForField(path: string, timeout: number?): Instance?
	local field = SoccerFieldUtil.findByPath(Workspace, path)
	if field then
		return field
	end

	local stadium = Workspace:WaitForChild("Stadium", timeout or 30)
	if not stadium then
		return nil
	end

	return SoccerFieldUtil.findByPath(Workspace, path)
end

function SoccerFieldUtil.getBounds(field: Instance): (CFrame, Vector3)
	if field:IsA("BasePart") then
		return field.CFrame, field.Size
	end

	if field:IsA("Model") then
		return field:GetBoundingBox()
	end

	error(`SoccerFieldUtil: unsupported field type {field.ClassName}`)
end

function SoccerFieldUtil.getFloorTopY(field: Instance): number
	local fieldCFrame, fieldSize = SoccerFieldUtil.getBounds(field)
	return fieldCFrame.Position.Y + fieldSize.Y * 0.5
end

function SoccerFieldUtil.getCenterPosition(field: Instance): Vector3
	local fieldCFrame, _fieldSize = SoccerFieldUtil.getBounds(field)
	return fieldCFrame.Position
end

function SoccerFieldUtil.getArenaFloorTopY(): number?
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

	return nil
end

function SoccerFieldUtil.raycastArenaFloor(origin: Vector3, maxDistance: number, exclude: { Instance }?): RaycastResult?
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = exclude or {}

	return Workspace:Raycast(origin, Vector3.new(0, -maxDistance, 0), rayParams)
end

function SoccerFieldUtil.getPlayBoundsFromField(field: Instance, inset: number, maxY: number?): { min: Vector3, max: Vector3 }
	local fieldCFrame, fieldSize = SoccerFieldUtil.getBounds(field)
	local half = fieldSize * 0.5
	local center = fieldCFrame.Position
	local floorTopY = center.Y + half.Y
	local minY = floorTopY - Config.FLOOR_SAFETY_MARGIN
	local playHeight = maxY or Config.ARENA_PLAY_MAX_Y
	local topY = floorTopY + playHeight

	return {
		min = Vector3.new(center.X - half.X + inset, minY, center.Z - half.Z + inset),
		max = Vector3.new(center.X + half.X - inset, topY, center.Z + half.Z - inset),
	}
end

local function createInvisibleWall(
	name: string,
	fieldCFrame: CFrame,
	localOffset: Vector3,
	size: Vector3,
	parent: Instance
): Part
	local wall = Instance.new("Part")
	wall.Name = name
	wall.Anchored = true
	wall.CanCollide = true
	wall.CanQuery = false
	wall.CanTouch = true
	wall.Locked = true
	wall.Material = Enum.Material.SmoothPlastic
	wall.Transparency = 1
	wall.Size = size
	wall.CFrame = fieldCFrame * CFrame.new(localOffset)
	wall.Parent = parent

	return wall
end

function SoccerFieldUtil.ensurePlaySurfaceCollision(field: Instance, boundaryFolderName: string)
	for _, descendant in field:GetDescendants() do
		if not descendant:IsA("BasePart") then
			continue
		end

		local parent = descendant.Parent
		if parent and parent.Name == boundaryFolderName then
			continue
		end

		descendant.CanCollide = true
	end

	if field:IsA("BasePart") then
		field.CanCollide = true
	end
end

function SoccerFieldUtil.buildInvisibleWalls(field: Instance, options: BoundaryOptions): Folder
	local existing = field:FindFirstChild(options.folderName)
	if existing then
		existing:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = options.folderName
	folder.Parent = field

	local fieldCFrame, fieldSize = SoccerFieldUtil.getBounds(field)
	local halfX = fieldSize.X * 0.5
	local halfZ = fieldSize.Z * 0.5
	local halfY = fieldSize.Y * 0.5
	local inset = options.wallInset
	local thickness = options.wallThickness
	local wallHeight = options.wallHeight
	local wallCenterY = halfY + wallHeight * 0.5 - inset

	local spanX = fieldSize.X + thickness * 2
	local spanZ = fieldSize.Z + thickness * 2

	createInvisibleWall(
		"WallNorth",
		fieldCFrame,
		Vector3.new(0, wallCenterY, -halfZ - thickness * 0.5 - inset),
		Vector3.new(spanX, wallHeight, thickness),
		folder
	)
	createInvisibleWall(
		"WallSouth",
		fieldCFrame,
		Vector3.new(0, wallCenterY, halfZ + thickness * 0.5 + inset),
		Vector3.new(spanX, wallHeight, thickness),
		folder
	)
	createInvisibleWall(
		"WallEast",
		fieldCFrame,
		Vector3.new(halfX + thickness * 0.5 + inset, wallCenterY, 0),
		Vector3.new(thickness, wallHeight, spanZ),
		folder
	)
	createInvisibleWall(
		"WallWest",
		fieldCFrame,
		Vector3.new(-halfX - thickness * 0.5 - inset, wallCenterY, 0),
		Vector3.new(thickness, wallHeight, spanZ),
		folder
	)

	if options.includeCeiling then
		local ceilingOffset = options.ceilingHeightOffset or wallHeight
		createInvisibleWall(
			"Ceiling",
			fieldCFrame,
			Vector3.new(0, halfY + ceilingOffset, 0),
			Vector3.new(spanX, 2, spanZ),
			folder
		)
	end

	if options.includeFloor ~= false then
		local floorThickness = options.floorThickness or Config.STADIUM_FLOOR_COLLIDER_THICKNESS
		createInvisibleWall(
			"FloorCollider",
			fieldCFrame,
			Vector3.new(0, halfY - floorThickness * 0.5, 0),
			Vector3.new(spanX, floorThickness, spanZ),
			folder
		)
	end

	return folder
end

return SoccerFieldUtil
