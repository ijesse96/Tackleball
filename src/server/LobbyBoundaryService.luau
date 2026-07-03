local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local SoccerFieldUtil = require(ReplicatedStorage.Shared.SoccerFieldUtil)

local LobbyBoundaryService = {}

function LobbyBoundaryService:init()
	task.spawn(function()
		local field = SoccerFieldUtil.waitForField(Config.LOBBY_SOCCER_FIELD_PATH, 30)
		if not field then
			warn(`LobbyBoundaryService: could not find {Config.LOBBY_SOCCER_FIELD_PATH}`)
			return
		end

		SoccerFieldUtil.buildInvisibleWalls(field, {
			folderName = Config.LOBBY_BOUNDARY_FOLDER_NAME,
			wallHeight = Config.LOBBY_BOUNDARY_WALL_HEIGHT,
			wallThickness = Config.LOBBY_BOUNDARY_WALL_THICKNESS,
			wallInset = Config.LOBBY_BOUNDARY_WALL_INSET,
			includeCeiling = false,
			includeFloor = true,
		})
		SoccerFieldUtil.ensurePlaySurfaceCollision(field, Config.LOBBY_BOUNDARY_FOLDER_NAME)
	end)
end

return LobbyBoundaryService
