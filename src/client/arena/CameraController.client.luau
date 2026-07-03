local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local player = Players.LocalPlayer
local celebrationActive = false

local function isCelebrationState(state: Types.RoundState): boolean
	return state == "Scored" or state == "Intermission"
end

local function bindCameraToCharacter(character: Model)
	if celebrationActive then
		return
	end

	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end

	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	camera.CameraSubject = humanoid
	camera.CameraType = Enum.CameraType.Custom
end

player.CharacterAdded:Connect(bindCameraToCharacter)

if player.Character then
	bindCameraToCharacter(player.Character)
end

Remotes.scoreCelebrationStarted().OnClientEvent:Connect(function()
	celebrationActive = true
end)

Remotes.roundStateChanged().OnClientEvent:Connect(function(payload: Types.RoundStatePayload)
	if payload.state == "Active" or payload.state == "Waiting" then
		celebrationActive = false
	elseif isCelebrationState(payload.state) then
		celebrationActive = true
	end
end)
