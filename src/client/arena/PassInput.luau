local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local GameMode = require(ReplicatedStorage.Shared.GameMode)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local TackleInput = require(script.Parent.TackleInput)

local PassInput = {}

local player = Players.LocalPlayer
local initialized = false

local function localCharacterHasBall(): boolean
	local character = player.Character
	if not character then
		return false
	end

	local gameBall = Workspace:FindFirstChild("GameBall")
	if not gameBall then
		return false
	end

	local function weldHeldByCharacter(weld: Weld): boolean
		local part0 = weld.Part0
		return part0 ~= nil and part0:IsDescendantOf(character)
	end

	if gameBall:IsA("BasePart") then
		local weld = gameBall:FindFirstChild("BallHold")
		if weld and weld:IsA("Weld") and weldHeldByCharacter(weld) then
			return true
		end
	end

	for _, descendant in gameBall:GetDescendants() do
		if descendant:IsA("Weld") and descendant.Name == "BallHold" and weldHeldByCharacter(descendant) then
			return true
		end
	end

	return false
end

local function isLocalCarrier(): boolean
	local payload = TackleInput.getLatestPayload()
	if payload and payload.carrierUserId == player.UserId then
		return true
	end

	return localCharacterHasBall()
end

local function canPass(): boolean
	local payload = TackleInput.getLatestPayload()
	if payload and payload.state ~= "Active" then
		return false
	end

	if payload and not payload.teamsMode then
		return false
	end

	if not GameMode.isTeamsMode() then
		return false
	end

	return isLocalCarrier()
end

local function getLookDirection(): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return nil
	end

	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if look.Magnitude < 0.01 then
		return Vector3.new(0, 0, -1)
	end

	return look.Unit
end

local function firePassAttempt()
	if not canPass() then
		return false
	end

	Remotes.passAttempt():FireServer(getLookDirection())
	return true
end

local function handlePassAction(_actionName: string, inputState: Enum.UserInputState, _inputObject: InputObject)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end

	if firePassAttempt() then
		return Enum.ContextActionResult.Sink
	end

	return Enum.ContextActionResult.Pass
end

local function init()
	if initialized then
		return
	end
	initialized = true

	Remotes.passAttempt()

	ContextActionService:BindActionAtPriority(
		"PassBall",
		handlePassAction,
		false,
		Enum.ContextActionPriority.High.Value,
		Config.PASS_KEY
	)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or input.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end

		if input.KeyCode ~= Config.PASS_KEY then
			return
		end

		firePassAttempt()
	end)
end

function PassInput.canPass(): boolean
	init()
	return canPass()
end

function PassInput.attemptPass()
	init()
	return firePassAttempt()
end

function PassInput.getLatestPayload()
	init()
	return TackleInput.getLatestPayload()
end

init()

return PassInput
