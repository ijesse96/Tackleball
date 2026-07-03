local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local CONFETTI_PER_BURST = 18
local CONFETTI_BURSTS = 8
local CONFETTI_BURST_INTERVAL = 0.12
local CELEBRATION_DURATION = 5
local CONFETTI_ZINDEX = 2

local CONFETTI_COLORS = {
	Color3.fromRGB(255, 80, 80),
	Color3.fromRGB(255, 200, 60),
	Color3.fromRGB(80, 220, 120),
	Color3.fromRGB(80, 160, 255),
	Color3.fromRGB(220, 100, 255),
	Color3.fromRGB(255, 140, 200),
	Color3.fromRGB(255, 255, 100),
}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ScoreCelebration"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 25
screenGui.IgnoreGuiInset = true
screenGui.Enabled = false
screenGui.Parent = playerGui

local previousState: Types.RoundState? = nil
local celebrationToken = 0

local function createConfettiPiece(fromLeft: boolean)
	local piece = Instance.new("Frame")
	piece.Name = "Confetti"
	piece.BorderSizePixel = 0
	piece.BackgroundColor3 = CONFETTI_COLORS[math.random(1, #CONFETTI_COLORS)]
	piece.AnchorPoint = Vector2.new(0.5, 0.5)
	piece.Rotation = math.random(0, 360)
	piece.ZIndex = CONFETTI_ZINDEX

	local width = math.random(6, 14)
	local height = math.random(10, 22)
	if math.random() < 0.5 then
		width, height = height, width
	end
	piece.Size = UDim2.fromOffset(width, height)

	local startX = if fromLeft then math.random(0, 8) / 100 else math.random(92, 100) / 100
	piece.Position = UDim2.fromScale(startX, 1.05)
	piece.Parent = screenGui

	local driftX = startX + (if fromLeft then 1 else -1) * (math.random(8, 28) / 100)
	local riseTime = math.random(12, 22) / 10

	local tween = TweenService:Create(
		piece,
		TweenInfo.new(riseTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Position = UDim2.fromScale(driftX, math.random(-15, -5) / 100),
			Rotation = piece.Rotation + math.random(-240, 240),
			BackgroundTransparency = 0.15,
		}
	)
	tween:Play()
	tween.Completed:Connect(function()
		piece:Destroy()
	end)
end

local function burstConfetti(fromLeft: boolean)
	for _ = 1, CONFETTI_PER_BURST do
		task.defer(function()
			createConfettiPiece(fromLeft)
		end)
	end
end

local function clearCelebration()
	for _, child in screenGui:GetChildren() do
		if child:IsA("Frame") and child.Name == "Confetti" then
			child:Destroy()
		end
	end
	screenGui.Enabled = false
end

local function playCelebration()
	celebrationToken += 1
	local token = celebrationToken
	clearCelebration()
	screenGui.Enabled = true

	for burstIndex = 1, CONFETTI_BURSTS do
		task.delay((burstIndex - 1) * CONFETTI_BURST_INTERVAL, function()
			if token ~= celebrationToken then
				return
			end
			burstConfetti(true)
			burstConfetti(false)
		end)
	end

	task.delay(CELEBRATION_DURATION, function()
		if token ~= celebrationToken then
			return
		end
		clearCelebration()
	end)
end

Remotes.roundStateChanged().OnClientEvent:Connect(function(payload: Types.RoundStatePayload)
	if payload.state == "Scored" and previousState ~= "Scored" then
		playCelebration()
	elseif payload.state == "Active" or payload.state == "Waiting" then
		clearCelebration()
	end

	previousState = payload.state
end)

