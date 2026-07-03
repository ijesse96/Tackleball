local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")

local Places = require(ReplicatedStorage.Shared.Places)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

if not Places.isMainMenuPlace() then
	return
end

Remotes.teleportToArena()
Remotes.teleportToArenaStatus()

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MainMenuUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder = 10
screenGui.Parent = playerGui

local title = Instance.new("TextLabel")
title.Name = "Title"
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.Position = UDim2.fromScale(0.5, 0.28)
title.Size = UDim2.fromScale(0.8, 0.12)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBlack
title.Text = "TACKLEBALL"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextScaled = true
title.Parent = screenGui

local buttonRow = Instance.new("Frame")
buttonRow.Name = "ButtonRow"
buttonRow.AnchorPoint = Vector2.new(0.5, 0.5)
buttonRow.Position = UDim2.fromScale(0.5, 0.52)
buttonRow.Size = UDim2.fromScale(0.8, 0.1)
buttonRow.BackgroundTransparency = 1
buttonRow.Parent = screenGui

local rowLayout = Instance.new("UIListLayout")
rowLayout.FillDirection = Enum.FillDirection.Horizontal
rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
rowLayout.Padding = UDim.new(0, 16)
rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
rowLayout.Parent = buttonRow

local function createModeButton(name: string, text: string, color: Color3): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = UDim2.fromScale(0.42, 1)
	button.BackgroundColor3 = color
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.Text = text
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.TextScaled = true
	button.AutoButtonColor = true
	button.Active = true
	button.Selectable = true
	button.ZIndex = 2
	button.Parent = buttonRow

	local textConstraint = Instance.new("UITextSizeConstraint")
	textConstraint.MaxTextSize = 36
	textConstraint.MinTextSize = 22
	textConstraint.Parent = button

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = button

	return button
end

local soloButton = createModeButton("SoloButton", "SOLO", Color3.fromRGB(55, 120, 220))
local teamsButton = createModeButton("TeamsButton", "TEAMS", Color3.fromRGB(40, 170, 70))

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "Status"
statusLabel.AnchorPoint = Vector2.new(0.5, 0)
statusLabel.Position = UDim2.fromScale(0.5, 0.62)
statusLabel.Size = UDim2.fromScale(0.85, 0.1)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.Gotham
statusLabel.Text = ""
statusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
statusLabel.TextScaled = true
statusLabel.TextWrapped = true
statusLabel.Parent = screenGui

local teleporting = false
local modeButtons = { soloButton, teamsButton }

local function setButtonsEnabled(enabled: boolean)
	for _, button in modeButtons do
		button.Active = enabled
		button.Selectable = enabled
	end
end

local function setStatus(message: string, isError: boolean?)
	statusLabel.Text = message
	statusLabel.TextColor3 = if isError
		then Color3.fromRGB(255, 120, 120)
		else Color3.fromRGB(200, 200, 200)
end

local function playArena(mode: string)
	if teleporting then
		return
	end

	teleporting = true
	setButtonsEnabled(false)
	setStatus(if mode == "solo" then "Loading solo arena..." else "Loading teams arena...")

	Remotes.teleportToArena():FireServer(mode)
end

local function onTeleportStatus(success: boolean, message: string?)
	if success then
		return
	end

	teleporting = false
	setButtonsEnabled(true)
	setStatus(message or "Teleport failed.", true)
end

TeleportService.TeleportInitFailed:Connect(function(teleportPlayer, result, errorMessage)
	if teleportPlayer ~= player then
		return
	end

	onTeleportStatus(false, `Teleport failed: {errorMessage} ({result.Name})`)
end)

Remotes.teleportToArenaStatus().OnClientEvent:Connect(onTeleportStatus)

soloButton.Activated:Connect(function()
	playArena("solo")
end)
soloButton.MouseButton1Click:Connect(function()
	playArena("solo")
end)

teamsButton.Activated:Connect(function()
	playArena("teams")
end)
teamsButton.MouseButton1Click:Connect(function()
	playArena("teams")
end)

print("TackleBall main menu client started")
