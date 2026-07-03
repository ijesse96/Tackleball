local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local player = Players.LocalPlayer
local MOVE_ACTION = "TackleBallCelebrationMoveLock"

local locked = false
local latestRoundState: Types.RoundState? = nil
local attributeConnection: RBXScriptConnection? = nil

local MOVEMENT_ACTIONS = {
	Enum.PlayerActions.CharacterForward,
	Enum.PlayerActions.CharacterBackward,
	Enum.PlayerActions.CharacterLeft,
	Enum.PlayerActions.CharacterRight,
	Enum.PlayerActions.CharacterJump,
}

local function sinkMovement()
	return Enum.ContextActionResult.Sink
end

local function isCelebrationRoundState(state: Types.RoundState?): boolean
	return state == "Scored" or state == "Intermission"
end

local function shouldLockMovement(character: Model?): boolean
	if not isCelebrationRoundState(latestRoundState) then
		return character ~= nil and character:GetAttribute("TackleBallCelebrationLocked") == true
	end

	return true
end

local function setLocked(nextLocked: boolean)
	if locked == nextLocked then
		return
	end

	locked = nextLocked

	if locked then
		ContextActionService:BindActionAtPriority(
			MOVE_ACTION,
			sinkMovement,
			false,
			Enum.ContextActionPriority.High.Value,
			table.unpack(MOVEMENT_ACTIONS)
		)
	else
		ContextActionService:UnbindAction(MOVE_ACTION)
	end
end

local function refreshLock(character: Model?)
	setLocked(shouldLockMovement(character))
end

local function bindCharacter(character: Model)
	if attributeConnection then
		attributeConnection:Disconnect()
		attributeConnection = nil
	end

	refreshLock(character)
	attributeConnection = character:GetAttributeChangedSignal("TackleBallCelebrationLocked"):Connect(function()
		refreshLock(character)
	end)
end

local function updateFromRoundState(payload: Types.RoundStatePayload)
	latestRoundState = payload.state
	refreshLock(player.Character)
end

UserInputService.JumpRequest:Connect(function()
	if not locked then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Jump = false
	end
end)

player.CharacterAdded:Connect(bindCharacter)
if player.Character then
	bindCharacter(player.Character)
end

Remotes.roundStateChanged().OnClientEvent:Connect(updateFromRoundState)
