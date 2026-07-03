local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

Remotes.teleportToLobbyStatus()

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MatchCompleteUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 50
screenGui.Enabled = false
screenGui.Parent = playerGui

local backdrop = Instance.new("Frame")
backdrop.Name = "Backdrop"
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
backdrop.BackgroundTransparency = 0.35
backdrop.BorderSizePixel = 0
backdrop.Parent = screenGui

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "Title"
titleLabel.AnchorPoint = Vector2.new(0.5, 0.5)
titleLabel.Position = UDim2.fromScale(0.5, 0.42)
titleLabel.Size = UDim2.fromOffset(520, 72)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.GothamBlack
titleLabel.TextSize = 48
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.TextStrokeColor3 = Color3.fromRGB(20, 20, 20)
titleLabel.TextStrokeTransparency = 0.35
titleLabel.Text = ""
titleLabel.Parent = screenGui

local subtitleLabel = Instance.new("TextLabel")
subtitleLabel.Name = "Subtitle"
subtitleLabel.AnchorPoint = Vector2.new(0.5, 0.5)
subtitleLabel.Position = UDim2.fromScale(0.5, 0.52)
subtitleLabel.Size = UDim2.fromOffset(420, 36)
subtitleLabel.BackgroundTransparency = 1
subtitleLabel.Font = Enum.Font.Gotham
subtitleLabel.TextSize = 22
subtitleLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
subtitleLabel.Text = "Returning to lobby..."
subtitleLabel.Parent = screenGui

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "Status"
statusLabel.AnchorPoint = Vector2.new(0.5, 0.5)
statusLabel.Position = UDim2.fromScale(0.5, 0.6)
statusLabel.Size = UDim2.fromOffset(420, 28)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextSize = 18
statusLabel.TextColor3 = Color3.fromRGB(255, 130, 130)
statusLabel.Text = ""
statusLabel.Parent = screenGui

local function getMatchTitle(payload: Types.RoundStatePayload): string?
	if payload.matchWinnerUserId == player.UserId then
		return "You Win!"
	end

	if payload.matchWinnerNpc then
		return "NPC Wins"
	end

	if payload.matchWinnerTeam then
		if payload.localTeam == payload.matchWinnerTeam then
			return "Your Team Wins!"
		end

		return `{payload.matchWinnerTeam} Team Wins!`
	end

	return nil
end

local function hideOverlay()
	screenGui.Enabled = false
	titleLabel.Text = ""
	statusLabel.Text = ""
	subtitleLabel.Text = "Returning to lobby..."
end

local function showOverlay(payload: Types.RoundStatePayload)
	local title = getMatchTitle(payload)
	if not title then
		hideOverlay()
		return
	end

	titleLabel.Text = title
	subtitleLabel.Text = "Returning to lobby..."
	statusLabel.Text = ""
	screenGui.Enabled = true
end

local function updateFromPayload(payload: Types.RoundStatePayload)
	if payload.matchComplete and (payload.state == "Scored" or payload.state == "Intermission") then
		showOverlay(payload)
		return
	end

	hideOverlay()
end

Remotes.roundStateChanged().OnClientEvent:Connect(updateFromPayload)

Remotes.teleportToLobbyStatus().OnClientEvent:Connect(function(success: boolean, message: string?)
	if success then
		return
	end

	screenGui.Enabled = true
	statusLabel.Text = message or "Return to lobby failed."
end)

TeleportService.TeleportInitFailed:Connect(function(playerToTeleport, result, errorMessage)
	if playerToTeleport ~= player then
		return
	end

	screenGui.Enabled = true
	statusLabel.Text = errorMessage or tostring(result)
end)
