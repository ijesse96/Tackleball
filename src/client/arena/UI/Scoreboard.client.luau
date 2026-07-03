local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerMapUtil = require(ReplicatedStorage.Shared.PlayerMapUtil)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TackleBallUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

local TOP_MARGIN = 6
local SCORE_GAP = 4

local timerLabel = Instance.new("TextLabel")
timerLabel.Name = "Timer"
timerLabel.AnchorPoint = Vector2.new(0.5, 0)
timerLabel.BackgroundTransparency = 0.35
timerLabel.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
timerLabel.BorderSizePixel = 0
timerLabel.Font = Enum.Font.GothamBold
timerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
timerLabel.TextSize = 20
timerLabel.Text = ""
timerLabel.Position = UDim2.new(0.5, 0, 0, TOP_MARGIN)
timerLabel.Size = UDim2.fromOffset(120, 32)
timerLabel.Parent = screenGui

local teamScoreLabel = Instance.new("TextLabel")
teamScoreLabel.Name = "TeamScore"
teamScoreLabel.AnchorPoint = Vector2.new(0.5, 0)
teamScoreLabel.BackgroundTransparency = 0.35
teamScoreLabel.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
teamScoreLabel.BorderSizePixel = 0
teamScoreLabel.Font = Enum.Font.GothamBold
teamScoreLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
teamScoreLabel.TextSize = 16
teamScoreLabel.Text = ""
teamScoreLabel.Visible = false
teamScoreLabel.Position = UDim2.new(0.5, 0, 0, TOP_MARGIN + 32 + SCORE_GAP)
teamScoreLabel.Size = UDim2.fromOffset(220, 26)
teamScoreLabel.Parent = screenGui

local function updateUI(payload: Types.RoundStatePayload)
	timerLabel.Text = `{math.max(0, payload.timeRemaining)}s`

	if payload.teamsMode and payload.teamScores then
		teamScoreLabel.Visible = true
		teamScoreLabel.Text = `Blue {payload.teamScores.Blue} - {payload.teamScores.Red} Red`
	elseif payload.gameMode == "solo" and payload.npcScore ~= nil then
		teamScoreLabel.Visible = true
		local humanScore = PlayerMapUtil.get(payload.scores, player.UserId)
		teamScoreLabel.Text = `You {humanScore} - {payload.npcScore} NPC`
	else
		teamScoreLabel.Visible = false
		teamScoreLabel.Text = ""
	end
end

Remotes.roundStateChanged().OnClientEvent:Connect(updateUI)
