local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Places = require(ReplicatedStorage.Shared.Places)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local LobbyReturnService = {}
LobbyReturnService._returning = false

function LobbyReturnService:init()
	Remotes.teleportToLobbyStatus()
end

function LobbyReturnService:returnAllToLobby()
	if self._returning then
		return
	end

	if not Places.isArenaPlace() then
		return
	end

	local players = Players:GetPlayers()
	if #players == 0 then
		return
	end

	if RunService:IsStudio() and game.PlaceId == 0 then
		warn("TackleBall: skipping lobby return teleport in Studio (publish to test cross-place teleport)")
		return
	end

	self._returning = true

	local options = Instance.new("TeleportOptions")
	options.ShouldReserveServer = false

	local ok, err = pcall(function()
		TeleportService:TeleportAsync(Places.MAIN_MENU_PLACE_ID, players, options)
	end)

	if not ok then
		self._returning = false
		warn(`TackleBall: return to lobby failed: {err}`)
		for _, player in players do
			Remotes.teleportToLobbyStatus():FireClient(
				player,
				false,
				`Return to lobby failed. ({err})`
			)
		end
	end
end

return LobbyReturnService
