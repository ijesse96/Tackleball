local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local Places = require(ReplicatedStorage.Shared.Places)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local MainMenuService = {}
MainMenuService._teleporting = {} :: { [number]: boolean }

function MainMenuService:init()
	Remotes.teleportToArena()
	Remotes.teleportToArenaStatus()

	Remotes.teleportToArena().OnServerEvent:Connect(function(player, mode)
		self:teleportToArena(player, mode)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self._teleporting[player.UserId] = nil
	end)
end

function MainMenuService:teleportToArena(player: Player, mode: any)
	if self._teleporting[player.UserId] then
		return
	end

	if not Places.isMainMenuPlace() then
		Remotes.teleportToArenaStatus():FireClient(player, false, "Teleport only works from the main menu.")
		return
	end

	if typeof(mode) ~= "string" then
		Remotes.teleportToArenaStatus():FireClient(player, false, "Choose Solo or Teams.")
		return
	end

	local placeId = Places.getArenaPlaceIdForMode(mode)
	if not placeId then
		Remotes.teleportToArenaStatus():FireClient(player, false, "Invalid game mode.")
		return
	end

	self._teleporting[player.UserId] = true

	local options = Instance.new("TeleportOptions")
	options.ShouldReserveServer = false

	local ok, err = pcall(function()
		TeleportService:TeleportAsync(placeId, { player }, options)
	end)

	if not ok then
		self._teleporting[player.UserId] = nil
		warn(`TackleBall: teleport to arena failed for {player.Name}: {err}`)
		Remotes.teleportToArenaStatus():FireClient(
			player,
			false,
			`Teleport failed. Make sure the arena place is published in this same experience. ({err})`
		)
	end
end

return MainMenuService
