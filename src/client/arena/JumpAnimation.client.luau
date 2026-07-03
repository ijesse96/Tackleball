local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local AnimationUtil = require(ReplicatedStorage.Shared.AnimationUtil)
local Config = require(ReplicatedStorage.Shared.Config)
local TackleInput = require(script.Parent.TackleInput)

local player = Players.LocalPlayer

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

local function bindLocalCharacter(character: Model)
	task.defer(function()
		if character.Parent then
			AnimationUtil.bindCustomJump(character)
		end
	end)
end

player.CharacterAdded:Connect(bindLocalCharacter)
if player.Character then
	bindLocalCharacter(player.Character)
end

UserInputService.JumpRequest:Connect(function()
	local character = player.Character
	if not character then
		return
	end

	if character:GetAttribute("TackleBallCelebrationLocked") == true then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Jump = false
		end
		return
	end

	AnimationUtil.beginJumpRequest(character)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or not AnimationUtil.canAcceptJump(humanoid) then
		if humanoid then
			humanoid.Jump = false
		end
		AnimationUtil.stopJump(character)
		return
	end

	if isLocalCarrier() then
		AnimationUtil.beginCarrierNativeJump(character)
		humanoid.JumpHeight = Config.CARRIER_JUMP_HEIGHT
		humanoid.Jump = true
		AnimationUtil.applyCarrierJumpImpulse(character, humanoid)
		return
	end

	AnimationUtil.ensureJumpImpulse(character, humanoid)
	humanoid.Jump = true
	AnimationUtil.playJump(character)
end)

AnimationUtil.preload()
