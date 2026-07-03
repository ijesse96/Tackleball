local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local MobileButtonLayout = require(script.Parent.MobileButtonLayout)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local SprintInput = require(script.Parent.Parent.SprintInput)
local Types = require(ReplicatedStorage.Shared.Types)

if not MobileButtonLayout.shouldShow() then
	return
end

local SPRINT_PHASE_ATTRIBUTE = "TackleBallSprintPhase"
local SPRINT_PROGRESS_ATTRIBUTE = "TackleBallSprintProgress"

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local buttonSize = Config.MOBILE_TACKLE_BUTTON_SIZE

local roundActive = false
local attributeConnections: { RBXScriptConnection } = {}

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SprintButtonUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 5
screenGui.Parent = playerGui

local sprintButton = Instance.new("TextButton")
sprintButton.Name = "SprintButton"
sprintButton.AnchorPoint = Vector2.new(1, 1)
sprintButton.Size = UDim2.fromOffset(buttonSize, buttonSize)
sprintButton.BackgroundColor3 = Color3.fromRGB(40, 170, 90)
sprintButton.BorderSizePixel = 0
sprintButton.Font = Enum.Font.GothamBold
sprintButton.Text = "SPRINT"
sprintButton.TextColor3 = Color3.fromRGB(255, 255, 255)
sprintButton.TextScaled = true
sprintButton.Visible = false
sprintButton.ZIndex = 2
sprintButton.Parent = screenGui

local buttonCorner = Instance.new("UICorner")
buttonCorner.CornerRadius = UDim.new(1, 0)
buttonCorner.Parent = sprintButton

local textConstraint = Instance.new("UITextSizeConstraint")
textConstraint.MaxTextSize = 14
textConstraint.MinTextSize = 10
textConstraint.Parent = sprintButton

local meterRing = Instance.new("Frame")
meterRing.Name = "MeterRing"
meterRing.AnchorPoint = Vector2.new(0.5, 0.5)
meterRing.Position = UDim2.fromScale(0.5, 0.5)
meterRing.Size = UDim2.new(1, 8, 1, 8)
meterRing.BackgroundTransparency = 1
meterRing.Visible = false
meterRing.ZIndex = 1
meterRing.Parent = sprintButton

local ringStroke = Instance.new("UIStroke")
ringStroke.Color = Color3.fromRGB(255, 220, 80)
ringStroke.Thickness = 3
ringStroke.Transparency = 0.15
ringStroke.Parent = meterRing

local ringCorner = Instance.new("UICorner")
ringCorner.CornerRadius = UDim.new(1, 0)
ringCorner.Parent = meterRing

local ringFill = Instance.new("Frame")
ringFill.Name = "Fill"
ringFill.AnchorPoint = Vector2.new(0.5, 1)
ringFill.Position = UDim2.fromScale(0.5, 0.5)
ringFill.Size = UDim2.fromScale(1, 0)
ringFill.BackgroundColor3 = Color3.fromRGB(255, 220, 80)
ringFill.BackgroundTransparency = 0.35
ringFill.BorderSizePixel = 0
ringFill.ZIndex = 0
ringFill.Parent = meterRing

local ringFillCorner = Instance.new("UICorner")
ringFillCorner.CornerRadius = UDim.new(1, 0)
ringFillCorner.Parent = ringFill

local readyColor = Color3.fromRGB(40, 170, 90)
local activeColor = Color3.fromRGB(255, 170, 40)
local emptyColor = Color3.fromRGB(70, 70, 80)

local function disconnectAttributes()
	for _, connection in attributeConnections do
		connection:Disconnect()
	end
	table.clear(attributeConnections)
end

local function syncFromCharacter(character: Model?)
	if not character then
		SprintInput.setPhase("idle")
		SprintInput.setFuel(1)
		return
	end

	local phase = character:GetAttribute(SPRINT_PHASE_ATTRIBUTE)
	SprintInput.setPhase(if typeof(phase) == "string" then phase else "idle")

	local progress = character:GetAttribute(SPRINT_PROGRESS_ATTRIBUTE)
	SprintInput.setFuel(if typeof(progress) == "number" then progress else 1)
end

local function bindCharacter(character: Model)
	disconnectAttributes()
	syncFromCharacter(character)

	table.insert(
		attributeConnections,
		character:GetAttributeChangedSignal(SPRINT_PHASE_ATTRIBUTE):Connect(function()
			syncFromCharacter(character)
		end)
	)
	table.insert(
		attributeConnections,
		character:GetAttributeChangedSignal(SPRINT_PROGRESS_ATTRIBUTE):Connect(function()
			syncFromCharacter(character)
		end)
	)
end

local function updateButtonVisuals()
	sprintButton.Visible = false
	meterRing.Visible = false
end

local function onPress()
	if not SprintInput.canToggle() or not roundActive then
		return
	end

	SprintInput.activate()
end

sprintButton.Activated:Connect(onPress)

player.CharacterAdded:Connect(function(character)
	character:WaitForChild("HumanoidRootPart", 10)
	bindCharacter(character)
	updateButtonVisuals()
end)

if player.Character then
	bindCharacter(player.Character)
end

RunService.RenderStepped:Connect(updateButtonVisuals)

Remotes.roundStateChanged().OnClientEvent:Connect(function(payload: Types.RoundStatePayload)
	roundActive = payload.state == "Active"
	if not roundActive then
		SprintInput.setPhase("idle")
		SprintInput.setFuel(1)
	end
	updateButtonVisuals()
end)

updateButtonVisuals()
