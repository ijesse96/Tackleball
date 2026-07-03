local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameMode = require(ReplicatedStorage.Shared.GameMode)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

if not GameMode.isSoloTestMode() then
	return
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local ACTIVE_COLOR = Color3.fromRGB(55, 140, 220)
local INACTIVE_COLOR = Color3.fromRGB(45, 45, 50)
local TEXT_COLOR = Color3.fromRGB(255, 255, 255)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DevRoleToggleUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 10
screenGui.Parent = playerGui

local container = Instance.new("Frame")
container.Name = "Container"
container.AnchorPoint = Vector2.new(0, 0)
container.Position = UDim2.fromOffset(12, 12)
container.Size = UDim2.fromOffset(220, 36)
container.BackgroundColor3 = Color3.fromRGB(25, 25, 28)
container.BackgroundTransparency = 0.15
container.BorderSizePixel = 0
container.Parent = screenGui

local containerCorner = Instance.new("UICorner")
containerCorner.CornerRadius = UDim.new(0, 8)
containerCorner.Parent = container

local containerPadding = Instance.new("UIPadding")
containerPadding.PaddingLeft = UDim.new(0, 4)
containerPadding.PaddingRight = UDim.new(0, 4)
containerPadding.PaddingTop = UDim.new(0, 4)
containerPadding.PaddingBottom = UDim.new(0, 4)
containerPadding.Parent = container

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.VerticalAlignment = Enum.VerticalAlignment.Center
layout.Padding = UDim.new(0, 4)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = container

local label = Instance.new("TextLabel")
label.Name = "Label"
label.LayoutOrder = 0
label.Size = UDim2.fromOffset(52, 28)
label.BackgroundTransparency = 1
label.Font = Enum.Font.GothamBold
label.Text = "TEST"
label.TextColor3 = Color3.fromRGB(180, 180, 185)
label.TextSize = 11
label.Parent = container

local carrierButton = Instance.new("TextButton")
carrierButton.Name = "CarrierButton"
carrierButton.LayoutOrder = 1
carrierButton.Size = UDim2.new(1, -60, 1, 0)
carrierButton.BackgroundColor3 = ACTIVE_COLOR
carrierButton.BorderSizePixel = 0
carrierButton.Font = Enum.Font.GothamBold
carrierButton.Text = "Carrier"
carrierButton.TextColor3 = TEXT_COLOR
carrierButton.TextSize = 13
carrierButton.Parent = container

local carrierCorner = Instance.new("UICorner")
carrierCorner.CornerRadius = UDim.new(0, 6)
carrierCorner.Parent = carrierButton

local tacklerButton = Instance.new("TextButton")
tacklerButton.Name = "TacklerButton"
tacklerButton.LayoutOrder = 2
tacklerButton.Size = UDim2.new(1, -60, 1, 0)
tacklerButton.BackgroundColor3 = INACTIVE_COLOR
tacklerButton.BorderSizePixel = 0
tacklerButton.Font = Enum.Font.GothamBold
tacklerButton.Text = "Tackler"
tacklerButton.TextColor3 = TEXT_COLOR
tacklerButton.TextSize = 13
tacklerButton.Parent = container

local tacklerCorner = Instance.new("UICorner")
tacklerCorner.CornerRadius = UDim.new(0, 6)
tacklerCorner.Parent = tacklerButton

local function setActiveRole(role: string)
	local isCarrier = role == "carrier"
	carrierButton.BackgroundColor3 = if isCarrier then ACTIVE_COLOR else INACTIVE_COLOR
	tacklerButton.BackgroundColor3 = if isCarrier then INACTIVE_COLOR else ACTIVE_COLOR
end

local function switchRole(role: string)
	Remotes.devSwitchTestRole():FireServer(role)
	setActiveRole(role)
end

carrierButton.MouseButton1Click:Connect(function()
	switchRole("carrier")
end)

tacklerButton.MouseButton1Click:Connect(function()
	switchRole("tackler")
end)

Remotes.roundStateChanged().OnClientEvent:Connect(function(payload: Types.RoundStatePayload)
	if payload.soloTestRole then
		setActiveRole(payload.soloTestRole)
	end
end)

setActiveRole("carrier")
