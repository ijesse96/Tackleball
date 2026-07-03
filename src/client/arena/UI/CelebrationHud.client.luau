local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local CelebrationScorerResolve = require(script.Parent.Parent.CelebrationScorerResolve)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local celebrationActive = false
local celebrationScorerUserId: number? = nil
local celebrationScorerCharacterName: string? = nil
local heartbeatConnection: RBXScriptConnection? = nil

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CelebrationHud"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 30
screenGui.Enabled = false
screenGui.Parent = playerGui

local nameLabel = Instance.new("TextLabel")
nameLabel.Name = "ScorerName"
nameLabel.AnchorPoint = Vector2.new(0.5, 0.5)
nameLabel.Position = UDim2.fromScale(0.5, 0.72)
nameLabel.Size = UDim2.fromOffset(360, 44)
nameLabel.BackgroundTransparency = 1
nameLabel.Font = Enum.Font.GothamBlack
nameLabel.TextSize = 36
nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
nameLabel.TextStrokeColor3 = Color3.fromRGB(15, 15, 15)
nameLabel.TextStrokeTransparency = 0.4
nameLabel.Text = ""
nameLabel.Parent = screenGui

local function getNameColor(character: Model?): Color3
	if not character then
		return Color3.fromRGB(255, 255, 255)
	end

	local team = character:GetAttribute("TackleBallTeam")
	if team == Config.TEAM_A_NAME then
		return Config.TEAM_A_COLOR
	end
	if team == Config.TEAM_B_NAME then
		return Config.TEAM_B_COLOR
	end

	return Color3.fromRGB(255, 255, 255)
end

local function getScorerDisplayName(character: Model?): string
	if character then
		local scorerPlayer = Players:GetPlayerFromCharacter(character)
		if scorerPlayer then
			return scorerPlayer.DisplayName
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.DisplayName ~= "" then
			return humanoid.DisplayName
		end

		return character.Name
	end

	if celebrationScorerUserId then
		local scorerPlayer = Players:GetPlayerByUserId(celebrationScorerUserId)
		if scorerPlayer then
			return scorerPlayer.DisplayName
		end
	end

	if celebrationScorerCharacterName then
		return celebrationScorerCharacterName
	end

	return "Player"
end

local function stopHeartbeat()
	if heartbeatConnection then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end
end

local function refreshHud()
	if not celebrationActive then
		return
	end

	local character = CelebrationScorerResolve.resolveFromPayload({
		scorerUserId = celebrationScorerUserId,
		scorerCharacterName = celebrationScorerCharacterName,
	})

	nameLabel.Text = getScorerDisplayName(character)
	nameLabel.TextColor3 = getNameColor(character)
end

local function clearCelebration()
	celebrationActive = false
	celebrationScorerUserId = nil
	celebrationScorerCharacterName = nil
	stopHeartbeat()
	screenGui.Enabled = false
	nameLabel.Text = ""
end

local function startCelebration(
	scoredAmount: number,
	_scorerUserId: number?,
	scorerCharacterName: string?
)
	if scoredAmount <= 0 then
		return
	end

	celebrationActive = true
	celebrationScorerUserId = _scorerUserId
	celebrationScorerCharacterName = scorerCharacterName

	screenGui.Enabled = true
	refreshHud()

	stopHeartbeat()
	heartbeatConnection = RunService.Heartbeat:Connect(refreshHud)
end

local function tryStartCelebrationFromPayload(payload: Types.RoundStatePayload)
	if payload.state ~= "Scored" and payload.state ~= "Intermission" then
		return
	end

	local scoredAmount = payload.scoredAmount
	if not scoredAmount or scoredAmount <= 0 then
		return
	end

	startCelebration(scoredAmount, payload.scorerUserId, payload.scorerCharacterName)
end

Remotes.scoreCelebrationStarted().OnClientEvent:Connect(function(payload: Types.CelebrationScenePayload)
	local scoredAmount = payload.scoredAmount
	if not scoredAmount or scoredAmount <= 0 then
		return
	end

	startCelebration(scoredAmount, payload.scorerUserId, payload.scorerCharacterName)
end)

Remotes.roundStateChanged().OnClientEvent:Connect(function(payload: Types.RoundStatePayload)
	if payload.state == "Active" or payload.state == "Waiting" then
		clearCelebration()
	elseif payload.state == "Scored" or payload.state == "Intermission" then
		tryStartCelebrationFromPayload(payload)
	end
end)
