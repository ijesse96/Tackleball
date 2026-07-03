local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local RESPAWN_AT_ATTRIBUTE = "TackleBallRespawnAt"

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local timerToken = 0
local countdownConnection: RBXScriptConnection? = nil

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RespawnTimerUI"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 30
screenGui.IgnoreGuiInset = true
screenGui.Enabled = false
screenGui.Parent = playerGui

local backdrop = Instance.new("Frame")
backdrop.Name = "Backdrop"
backdrop.AnchorPoint = Vector2.new(0.5, 0.5)
backdrop.Position = UDim2.fromScale(0.5, 0.5)
backdrop.Size = UDim2.fromOffset(360, 120)
backdrop.BackgroundColor3 = Color3.fromRGB(12, 10, 18)
backdrop.BackgroundTransparency = 0.2
backdrop.BorderSizePixel = 0
backdrop.Parent = screenGui

local backdropCorner = Instance.new("UICorner")
backdropCorner.CornerRadius = UDim.new(0, 12)
backdropCorner.Parent = backdrop

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "Title"
titleLabel.BackgroundTransparency = 1
titleLabel.Size = UDim2.new(1, 0, 0.45, 0)
titleLabel.Font = Enum.Font.GothamBold
titleLabel.Text = "You died"
titleLabel.TextColor3 = Color3.fromRGB(255, 120, 120)
titleLabel.TextSize = 28
titleLabel.Parent = backdrop

local timerLabel = Instance.new("TextLabel")
timerLabel.Name = "Timer"
timerLabel.BackgroundTransparency = 1
timerLabel.Position = UDim2.fromScale(0, 0.45)
timerLabel.Size = UDim2.new(1, 0, 0.55, 0)
timerLabel.Font = Enum.Font.GothamMedium
timerLabel.Text = ""
timerLabel.TextColor3 = Color3.fromRGB(240, 240, 245)
timerLabel.TextSize = 22
timerLabel.Parent = backdrop

local function clearCountdown()
	if countdownConnection then
		countdownConnection:Disconnect()
		countdownConnection = nil
	end
end

local function hideTimer()
	timerToken += 1
	clearCountdown()
	screenGui.Enabled = false
end

local function updateTimerText(remaining: number)
	if remaining <= 0 then
		timerLabel.Text = "Respawning..."
		return
	end

	timerLabel.Text = `Back in {math.ceil(remaining)}s`
end

local function startCountdown(respawnAt: number)
	timerToken += 1
	local token = timerToken
	clearCountdown()
	screenGui.Enabled = true
	updateTimerText(respawnAt - Workspace:GetServerTimeNow())

	countdownConnection = RunService.Heartbeat:Connect(function()
		if token ~= timerToken then
			return
		end

		local remaining = respawnAt - Workspace:GetServerTimeNow()
		if remaining <= 0 then
			updateTimerText(0)
			return
		end

		updateTimerText(remaining)
	end)
end

local function syncFromAttribute()
	local respawnAt = player:GetAttribute(RESPAWN_AT_ATTRIBUTE)
	if typeof(respawnAt) == "number" and respawnAt > Workspace:GetServerTimeNow() then
		startCountdown(respawnAt)
	else
		hideTimer()
	end
end

player:GetAttributeChangedSignal(RESPAWN_AT_ATTRIBUTE):Connect(syncFromAttribute)

player.CharacterAdded:Connect(function()
	hideTimer()
end)

if typeof(player:GetAttribute(RESPAWN_AT_ATTRIBUTE)) == "number" then
	syncFromAttribute()
end

-- Fallback if the server attribute is missing (e.g. mid-death on join).
local function bindCharacter(character: Model)
	if character:GetAttribute("TackleBallDead") == true then
		startCountdown(Workspace:GetServerTimeNow() + Config.DEATH_RESPAWN_DELAY)
	end

	character:GetAttributeChangedSignal("TackleBallDead"):Connect(function()
		if character:GetAttribute("TackleBallDead") == true and not screenGui.Enabled then
			startCountdown(Workspace:GetServerTimeNow() + Config.DEATH_RESPAWN_DELAY)
		end
	end)
end

player.CharacterAdded:Connect(bindCharacter)
if player.Character then
	bindCharacter(player.Character)
end
