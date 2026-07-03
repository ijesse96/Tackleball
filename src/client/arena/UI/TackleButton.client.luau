local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ChargeUtil = require(ReplicatedStorage.Shared.ChargeUtil)
local Config = require(ReplicatedStorage.Shared.Config)
local MobileButtonLayout = require(script.Parent.MobileButtonLayout)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local TackleInput = require(script.Parent.Parent.TackleInput)

if not MobileButtonLayout.shouldShow() then
	return
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local buttonSize = Config.MOBILE_TACKLE_BUTTON_SIZE

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TackleButtonUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 5
screenGui.Parent = playerGui

local tackleButton = Instance.new("TextButton")
tackleButton.Name = "TackleButton"
tackleButton.AnchorPoint = Vector2.new(1, 1)
tackleButton.Size = UDim2.fromOffset(buttonSize, buttonSize)
tackleButton.BackgroundColor3 = Color3.fromRGB(200, 55, 55)
tackleButton.BorderSizePixel = 0
tackleButton.Font = Enum.Font.GothamBold
tackleButton.Text = "TACKLE"
tackleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
tackleButton.TextScaled = true
tackleButton.Visible = false
tackleButton.ZIndex = 2
tackleButton.Parent = screenGui

local buttonCorner = Instance.new("UICorner")
buttonCorner.CornerRadius = UDim.new(1, 0)
buttonCorner.Parent = tackleButton

local textConstraint = Instance.new("UITextSizeConstraint")
textConstraint.MaxTextSize = 14
textConstraint.MinTextSize = 10
textConstraint.Parent = tackleButton

local chargeRing = Instance.new("Frame")
chargeRing.Name = "ChargeRing"
chargeRing.AnchorPoint = Vector2.new(0.5, 0.5)
chargeRing.Position = UDim2.fromScale(0.5, 0.5)
chargeRing.Size = UDim2.new(1, 8, 1, 8)
chargeRing.BackgroundTransparency = 1
chargeRing.Visible = false
chargeRing.ZIndex = 1
chargeRing.Parent = tackleButton

local ringStroke = Instance.new("UIStroke")
ringStroke.Color = Color3.fromRGB(255, 220, 80)
ringStroke.Thickness = 3
ringStroke.Transparency = 0.15
ringStroke.Parent = chargeRing

local ringCorner = Instance.new("UICorner")
ringCorner.CornerRadius = UDim.new(1, 0)
ringCorner.Parent = chargeRing

local ringFill = Instance.new("Frame")
ringFill.Name = "Fill"
ringFill.AnchorPoint = Vector2.new(0.5, 1)
ringFill.Position = UDim2.fromScale(0.5, 0.5)
ringFill.Size = UDim2.fromScale(1, 0)
ringFill.BackgroundColor3 = Color3.fromRGB(255, 220, 80)
ringFill.BackgroundTransparency = 0.35
ringFill.BorderSizePixel = 0
ringFill.ZIndex = 0
ringFill.Parent = chargeRing

local ringFillCorner = Instance.new("UICorner")
ringFillCorner.CornerRadius = UDim.new(1, 0)
ringFillCorner.Parent = ringFill

local holdingButton = false
local chargeStartedAt = 0
local chargeRenderConnection: RBXScriptConnection? = nil

local function updateVisibility()
	local canTackle = TackleInput.canTackle()
	tackleButton.Visible = canTackle

	if not canTackle then
		holdingButton = false
		chargeRing.Visible = false
		tackleButton.Active = true
		tackleButton.BackgroundTransparency = 0
	end
end

local function stopChargeRing()
	chargeRing.Visible = false
	ringFill.Size = UDim2.fromScale(1, 0)

	if chargeRenderConnection then
		chargeRenderConnection:Disconnect()
		chargeRenderConnection = nil
	end
end

local function startChargeRing()
	stopChargeRing()
	chargeStartedAt = os.clock()
	chargeRing.Visible = true

	chargeRenderConnection = RunService.RenderStepped:Connect(function()
		if not holdingButton and not TackleInput.isCharging() then
			stopChargeRing()
			return
		end

		local charge01 = ChargeUtil.getCharge01FromElapsed(os.clock() - chargeStartedAt)
		ringFill.Size = UDim2.fromScale(1, charge01)
	end)
end

local function onPressBegan()
	if not TackleInput.canTackle() or holdingButton then
		return
	end

	holdingButton = true
	tackleButton.Active = false
	startChargeRing()
	TackleInput.beginCharge()
end

local function onPressEnded()
	if not holdingButton and not TackleInput.isCharging() then
		return
	end

	holdingButton = false
	tackleButton.Active = true
	stopChargeRing()
	TackleInput.releaseCharge()
end

tackleButton.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
		onPressBegan()
	end
end)

tackleButton.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
		onPressEnded()
	end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end

	if holdingButton or TackleInput.isCharging() then
		onPressEnded()
	end
end)

Remotes.roundStateChanged().OnClientEvent:Connect(function()
	updateVisibility()
end)

Remotes.tackleDashStarted().OnClientEvent:Connect(function(tackler: Player)
	if tackler == player then
		holdingButton = false
		tackleButton.Active = true
		stopChargeRing()
	end
end)

Remotes.tackleChargeStarted().OnClientEvent:Connect(function(tackler: Player)
	if tackler == player and not chargeRenderConnection then
		startChargeRing()
	end
end)

updateVisibility()
