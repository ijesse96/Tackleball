local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimationUtil = require(ReplicatedStorage.Shared.AnimationUtil)
local Config = require(ReplicatedStorage.Shared.Config)
local PassUtil = require(ReplicatedStorage.Shared.PassUtil)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local player = Players.LocalPlayer

local function getReceiverCharacter(payload: Types.PassStartedPayload): Model?
	if payload.receiverCharacterName then
		return workspace:FindFirstChild(payload.receiverCharacterName) :: Model?
	end

	return nil
end

local function startLocalAimLock(throwerCharacter: Model, receiverCharacter: Model)
	if throwerCharacter ~= player.Character then
		return
	end

	local connection: RBXScriptConnection? = nil
	connection = game:GetService("RunService").Heartbeat:Connect(function()
		if not throwerCharacter.Parent or not receiverCharacter.Parent then
			if connection then
				connection:Disconnect()
			end
			return
		end

		PassUtil.faceCharacterTowardCharacter(throwerCharacter, receiverCharacter)
	end)

	task.delay(Config.PASS_RELEASE_DELAY + 0.05, function()
		if connection then
			connection:Disconnect()
		end
	end)
end

Remotes.passStarted().OnClientEvent:Connect(function(payload: Types.PassStartedPayload)
	local throwerCharacter: Model? = nil

	if payload.throwerUserId == player.UserId then
		throwerCharacter = player.Character
	elseif payload.throwerCharacterName then
		throwerCharacter = workspace:FindFirstChild(payload.throwerCharacterName) :: Model?
	end

	local receiverCharacter = getReceiverCharacter(payload)
	if throwerCharacter and receiverCharacter then
		PassUtil.faceCharacterTowardCharacter(throwerCharacter, receiverCharacter)
		startLocalAimLock(throwerCharacter, receiverCharacter)
	end

	if throwerCharacter then
		AnimationUtil.playPassThrow(throwerCharacter)
	end
end)
