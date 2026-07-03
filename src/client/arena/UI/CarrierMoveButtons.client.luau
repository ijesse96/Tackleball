local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ChargeUtil = require(ReplicatedStorage.Shared.ChargeUtil)
local Config = require(ReplicatedStorage.Shared.Config)
local MobileButtonLayout = require(script.Parent.MobileButtonLayout)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local CarrierDodgeInput = require(script.Parent.Parent.CarrierDodgeInput)

if not MobileButtonLayout.shouldShow() then
	return
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local buttonSize = Config.MOBILE_TACKLE_BUTTON_SIZE

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CarrierMoveButtonUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 5
screenGui.Parent = playerGui

local function createMoveButton(name: string, label: string, color: Color3): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.AnchorPoint = Vector2.new(1, 1)
	button.Size = UDim2.fromOffset(buttonSize, buttonSize)
	button.BackgroundColor3 = color
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.Text = label
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.TextScaled = true
	button.Visible = false
	button.ZIndex = 2
	button.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = button

	local textConstraint = Instance.new("UITextSizeConstraint")
	textConstraint.MaxTextSize = 14
	textConstraint.MinTextSize = 10
	textConstraint.Parent = button

	local readyStroke = Instance.new("UIStroke")
	readyStroke.Color = Color3.fromRGB(255, 220, 80)
	readyStroke.Thickness = 3
	readyStroke.Transparency = 1
	readyStroke.Parent = button

	return button
end

local truckButton = createMoveButton("TruckButton", "TRUCK", Color3.fromRGB(55, 120, 200))

local truckReadyStroke = truckButton:FindFirstChildOfClass("UIStroke")

local truckBaseColor = Color3.fromRGB(55, 120, 200)
local truckActiveColor = Color3.fromRGB(80, 150, 230)
local truckCooldownColor = Color3.fromRGB(70, 70, 80)

local truckChargeRing = Instance.new("Frame")
truckChargeRing.Name = "ChargeRing"
truckChargeRing.AnchorPoint = Vector2.new(0.5, 0.5)
truckChargeRing.Position = UDim2.fromScale(0.5, 0.5)
truckChargeRing.Size = UDim2.new(1, 8, 1, 8)
truckChargeRing.BackgroundTransparency = 1
truckChargeRing.Visible = false
truckChargeRing.ZIndex = 1
truckChargeRing.Parent = truckButton

local truckRingStroke = Instance.new("UIStroke")
truckRingStroke.Color = Color3.fromRGB(255, 220, 80)
truckRingStroke.Thickness = 3
truckRingStroke.Transparency = 0.15
truckRingStroke.Parent = truckChargeRing

local truckRingCorner = Instance.new("UICorner")
truckRingCorner.CornerRadius = UDim.new(1, 0)
truckRingCorner.Parent = truckChargeRing

local truckRingFill = Instance.new("Frame")
truckRingFill.Name = "Fill"
truckRingFill.AnchorPoint = Vector2.new(0.5, 1)
truckRingFill.Position = UDim2.fromScale(0.5, 0.5)
truckRingFill.Size = UDim2.fromScale(1, 0)
truckRingFill.BackgroundColor3 = Color3.fromRGB(255, 220, 80)
truckRingFill.BackgroundTransparency = 0.35
truckRingFill.BorderSizePixel = 0
truckRingFill.ZIndex = 0
truckRingFill.Parent = truckChargeRing

local truckRingFillCorner = Instance.new("UICorner")
truckRingFillCorner.CornerRadius = UDim.new(1, 0)
truckRingFillCorner.Parent = truckRingFill

local truckCooldownRing = Instance.new("Frame")
truckCooldownRing.Name = "CooldownRing"
truckCooldownRing.AnchorPoint = Vector2.new(0.5, 0.5)
truckCooldownRing.Position = UDim2.fromScale(0.5, 0.5)
truckCooldownRing.Size = UDim2.new(1, 8, 1, 8)
truckCooldownRing.BackgroundTransparency = 1
truckCooldownRing.Visible = false
truckCooldownRing.ZIndex = 1
truckCooldownRing.Parent = truckButton

local truckCooldownRingStroke = Instance.new("UIStroke")
truckCooldownRingStroke.Color = Color3.fromRGB(180, 180, 190)
truckCooldownRingStroke.Thickness = 3
truckCooldownRingStroke.Transparency = 0.1
truckCooldownRingStroke.Parent = truckCooldownRing

local truckCooldownRingCorner = Instance.new("UICorner")
truckCooldownRingCorner.CornerRadius = UDim.new(1, 0)
truckCooldownRingCorner.Parent = truckCooldownRing

local truckCooldownRingFill = Instance.new("Frame")
truckCooldownRingFill.Name = "Fill"
truckCooldownRingFill.AnchorPoint = Vector2.new(0.5, 1)
truckCooldownRingFill.Position = UDim2.fromScale(0.5, 0.5)
truckCooldownRingFill.Size = UDim2.fromScale(1, 0)
truckCooldownRingFill.BackgroundColor3 = Color3.fromRGB(120, 120, 130)
truckCooldownRingFill.BackgroundTransparency = 0.2
truckCooldownRingFill.BorderSizePixel = 0
truckCooldownRingFill.ZIndex = 0
truckCooldownRingFill.Parent = truckCooldownRing

local truckCooldownRingFillCorner = Instance.new("UICorner")
truckCooldownRingFillCorner.CornerRadius = UDim.new(1, 0)
truckCooldownRingFillCorner.Parent = truckCooldownRingFill

local holdingTruckButton = false
local truckChargeStartedAt = 0
local truckChargeRenderConnection: RBXScriptConnection? = nil

local function updateVisibility()
	truckButton.Visible = false
end

local function updateReadyState()
	local dodgeActive = CarrierDodgeInput.isDodgeWindowActive()
	local activeType = CarrierDodgeInput.getActiveDodgeType()
	local cooldownRemaining = CarrierDodgeInput.getTruckCooldownRemaining()
	local onCooldown = cooldownRemaining > 0

	if truckReadyStroke then
		truckReadyStroke.Transparency = if dodgeActive and activeType == "Truck" then 0.15 else 1
	end

	if onCooldown then
		local cooldown01 = math.clamp(cooldownRemaining / Config.TRUCK_COOLDOWN, 0, 1)
		truckCooldownRing.Visible = true
		truckCooldownRingFill.Size = UDim2.fromScale(1, cooldown01)
		truckButton.BackgroundColor3 = truckCooldownColor
		truckButton.Text = string.format("%.1f", cooldownRemaining)
		truckButton.Active = false
	elseif dodgeActive and activeType == "Truck" then
		truckCooldownRing.Visible = false
		truckButton.BackgroundColor3 = truckActiveColor
		truckButton.Text = "TRUCK"
		truckButton.Active = true
	else
		truckCooldownRing.Visible = false
		truckButton.BackgroundColor3 = truckBaseColor
		truckButton.Text = "TRUCK"
		truckButton.Active = true
	end
end

local function stopTruckChargeRing()
	truckChargeRing.Visible = false
	truckRingFill.Size = UDim2.fromScale(1, 0)

	if truckChargeRenderConnection then
		truckChargeRenderConnection:Disconnect()
		truckChargeRenderConnection = nil
	end
end

local function startTruckChargeRing()
	stopTruckChargeRing()
	truckChargeStartedAt = os.clock()
	truckChargeRing.Visible = true

	truckChargeRenderConnection = RunService.RenderStepped:Connect(function()
		if not holdingTruckButton and not CarrierDodgeInput.isTruckCharging() then
			stopTruckChargeRing()
			return
		end

		local charge01 = ChargeUtil.getCharge01FromElapsed(os.clock() - truckChargeStartedAt)
		truckRingFill.Size = UDim2.fromScale(1, charge01)
	end)
end

local function onTruckPressBegan()
	if not CarrierDodgeInput.canUseTruck() or holdingTruckButton then
		return
	end

	holdingTruckButton = true
	truckButton.Active = false
	startTruckChargeRing()
	CarrierDodgeInput.beginTruckCharge()
end

local function onTruckPressEnded()
	if not holdingTruckButton and not CarrierDodgeInput.isTruckCharging() then
		return
	end

	holdingTruckButton = false
	truckButton.Active = true
	stopTruckChargeRing()
	CarrierDodgeInput.releaseTruckCharge()
end

truckButton.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
		onTruckPressBegan()
	end
end)

truckButton.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
		onTruckPressEnded()
	end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end

	if holdingTruckButton or CarrierDodgeInput.isTruckCharging() then
		onTruckPressEnded()
	end
end)

Remotes.roundStateChanged().OnClientEvent:Connect(function()
	updateVisibility()
	updateReadyState()
end)

Remotes.dodgeStarted().OnClientEvent:Connect(function(carrier: Player)
	if carrier == player then
		updateReadyState()
	end
end)

Remotes.truckDashStarted().OnClientEvent:Connect(function(carrier: Player)
	if carrier == player then
		holdingTruckButton = false
		truckButton.Active = true
		stopTruckChargeRing()
		updateReadyState()
	end
end)

Remotes.truckChargeStarted().OnClientEvent:Connect(function(carrier: Player)
	if carrier == player and not truckChargeRenderConnection then
		startTruckChargeRing()
	end
end)

Remotes.tackleShed().OnClientEvent:Connect(function(_tackler: Player, carrier: Player, _hitPosition: Vector3?, dodgeType: string?)
	if carrier == player then
		if dodgeType == "Truck" then
			CarrierDodgeInput.resetTruckCooldown()
		end
		updateReadyState()
	end
end)

RunService.RenderStepped:Connect(updateReadyState)
