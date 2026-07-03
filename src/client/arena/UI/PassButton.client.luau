local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local MobileButtonLayout = require(script.Parent.MobileButtonLayout)
local PassInput = require(script.Parent.Parent.PassInput)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

if not MobileButtonLayout.shouldShow() then
	return
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local buttonSize = Config.MOBILE_TACKLE_BUTTON_SIZE

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "PassButtonUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 5
screenGui.Parent = playerGui

local passButton = Instance.new("TextButton")
passButton.Name = "PassButton"
passButton.AnchorPoint = Vector2.new(1, 1)
passButton.Size = UDim2.fromOffset(buttonSize, buttonSize)
passButton.BackgroundColor3 = Color3.fromRGB(70, 150, 90)
passButton.BorderSizePixel = 0
passButton.Font = Enum.Font.GothamBold
passButton.Text = "PASS"
passButton.TextColor3 = Color3.fromRGB(255, 255, 255)
passButton.TextScaled = true
passButton.Visible = false
passButton.ZIndex = 2
passButton.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(1, 0)
corner.Parent = passButton

local textConstraint = Instance.new("UITextSizeConstraint")
textConstraint.MaxTextSize = 14
textConstraint.MinTextSize = 10
textConstraint.Parent = passButton

local function updateVisibility()
	passButton.Visible = PassInput.canPass()
end

passButton.Activated:Connect(function()
	PassInput.attemptPass()
end)

Remotes.roundStateChanged().OnClientEvent:Connect(updateVisibility)

RunService.RenderStepped:Connect(updateVisibility)

updateVisibility()
