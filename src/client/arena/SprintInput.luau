local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

local SPRINT_PHASE_ATTRIBUTE = "TackleBallSprintPhase"
local SPRINT_PROGRESS_ATTRIBUTE = "TackleBallSprintProgress"

local player = Players.LocalPlayer

local SprintInput = {}
SprintInput._phase = "idle" :: string
SprintInput._fuel = 1 :: number

local function readFromCharacter()
	local character = player.Character
	if not character then
		SprintInput._phase = "idle"
		SprintInput._fuel = 1
		return
	end

	local phase = character:GetAttribute(SPRINT_PHASE_ATTRIBUTE)
	SprintInput._phase = if typeof(phase) == "string" then phase else "idle"

	local progress = character:GetAttribute(SPRINT_PROGRESS_ATTRIBUTE)
	SprintInput._fuel = if typeof(progress) == "number" then progress else 1
end

function SprintInput.getPhase(): string
	return SprintInput._phase
end

function SprintInput.getFuel(): number
	return SprintInput._fuel
end

function SprintInput.isSprinting(): boolean
	return SprintInput._phase == "active"
end

function SprintInput.isIdle(): boolean
	return SprintInput._phase == "idle"
end

function SprintInput.canToggle(): boolean
	if SprintInput._phase == "active" then
		return true
	end

	return SprintInput._phase == "idle" and SprintInput._fuel > 0
end

function SprintInput.setPhase(phase: string?)
	SprintInput._phase = if typeof(phase) == "string" then phase else "idle"
end

function SprintInput.setFuel(fuel: number?)
	SprintInput._fuel = if typeof(fuel) == "number" then fuel else 1
end

function SprintInput.syncFromCharacter()
	readFromCharacter()
end

function SprintInput.activate()
	if not SprintInput.canToggle() then
		return
	end

	Remotes.sprintActivate():FireServer()
end

player.CharacterAdded:Connect(function(character)
	character:WaitForChild("HumanoidRootPart", 10)
	readFromCharacter()
end)

if player.Character then
	readFromCharacter()
end

return SprintInput
