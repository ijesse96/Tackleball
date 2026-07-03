local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local GameMode = require(ReplicatedStorage.Shared.GameMode)
local SoccerFieldUtil = require(ReplicatedStorage.Shared.SoccerFieldUtil)

local ArenaLayoutService = {}

function ArenaLayoutService:init()
	if not GameMode.usesStadiumLayout() then
		return
	end

	task.spawn(function()
		local fieldPath = GameMode.getSoccerFieldPath()
		local field = SoccerFieldUtil.waitForField(fieldPath, 30)
		if not field then
			warn(`ArenaLayoutService: could not find {fieldPath}`)
			return
		end

		SoccerFieldUtil.buildInvisibleWalls(field, {
			folderName = Config.STADIUM_BOUNDARY_FOLDER_NAME,
			wallHeight = Config.STADIUM_BOUNDARY_WALL_HEIGHT,
			wallThickness = Config.STADIUM_BOUNDARY_WALL_THICKNESS,
			wallInset = Config.STADIUM_BOUNDARY_WALL_INSET,
			includeCeiling = Config.STADIUM_BOUNDARY_INCLUDE_CEILING,
			ceilingHeightOffset = Config.STADIUM_BOUNDARY_CEILING_HEIGHT_OFFSET,
			includeFloor = true,
		})
		SoccerFieldUtil.ensurePlaySurfaceCollision(field, Config.STADIUM_BOUNDARY_FOLDER_NAME)
	end)
end

return ArenaLayoutService
