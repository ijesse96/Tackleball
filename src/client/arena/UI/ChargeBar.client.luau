local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ChargeUtil = require(ReplicatedStorage.Shared.ChargeUtil)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ChargeBarUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local barBackground = Instance.new("Frame")
barBackground.Name = "Background"
barBackground.AnchorPoint = Vector2.new(0.5, 1)
barBackground.Position = if UserInputService.TouchEnabled
	then UDim2.fromScale(0.5, 0.82)
	else UDim2.fromScale(0.5, 0.92)
barBackground.Size = UDim2.fromOffset(220, 18)
barBackground.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
barBackground.BackgroundTransparency = 0.25
barBackground.BorderSizePixel = 0
barBackground.Visible = false
barBackground.Parent = screenGui

local barCorner = Instance.new("UICorner")
barCorner.CornerRadius = UDim.new(0, 6)
barCorner.Parent = barBackground

local barFill = Instance.new("Frame")
barFill.Name = "Fill"
barFill.Size = UDim2.fromScale(0, 1)
barFill.BackgroundColor3 = Color3.fromRGB(80, 220, 100)
barFill.BorderSizePixel = 0
barFill.Parent = barBackground

local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(0, 6)
fillCorner.Parent = barFill

local chargeLabel = Instance.new("TextLabel")
chargeLabel.Name = "Label"
chargeLabel.BackgroundTransparency = 1
chargeLabel.Size = UDim2.fromScale(1, 1)
chargeLabel.Font = Enum.Font.GothamBold
chargeLabel.Text = "CHARGE"
chargeLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
chargeLabel.TextSize = 12
chargeLabel.Parent = barBackground

local charging = false
local chargeStartedAt = 0
local renderConnection: RBXScriptConnection? = nil

local function getChargeColor(charge01: number): Color3
	if charge01 < 0.5 then
		return Color3.fromRGB(80, 220, 100):Lerp(Color3.fromRGB(240, 220, 60), charge01 * 2)
	end
	return Color3.fromRGB(240, 220, 60):Lerp(Color3.fromRGB(240, 70, 60), (charge01 - 0.5) * 2)
end

local function stopChargeBar()
	charging = false
	barBackground.Visible = false
	barFill.Size = UDim2.fromScale(0, 1)

	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
end

local function startChargeBar()
	stopChargeBar()

	charging = true
	chargeStartedAt = os.clock()
	barBackground.Visible = true

	renderConnection = RunService.RenderStepped:Connect(function()
		if not charging then
			return
		end

		local elapsed = os.clock() - chargeStartedAt
		local charge01 = ChargeUtil.getCharge01FromElapsed(elapsed)

		barFill.Size = UDim2.fromScale(charge01, 1)
		barFill.BackgroundColor3 = getChargeColor(charge01)

		if charge01 >= 1 then
			chargeLabel.Text = "MAX!"
		else
			chargeLabel.Text = "CHARGE"
		end
	end)
end

Remotes.tackleChargeStarted().OnClientEvent:Connect(function(tackler: Player)
	if tackler == player then
		startChargeBar()
	end
end)

Remotes.truckChargeStarted().OnClientEvent:Connect(function(carrier: Player)
	if carrier == player then
		startChargeBar()
	end
end)

Remotes.tackleDashStarted().OnClientEvent:Connect(function(tackler: Player)
	if tackler == player then
		stopChargeBar()
	end
end)

Remotes.truckDashStarted().OnClientEvent:Connect(function(carrier: Player)
	if carrier == player then
		stopChargeBar()
	end
end)

Remotes.roundStateChanged().OnClientEvent:Connect(function(payload)
	if payload.state ~= "Active" then
		stopChargeBar()
	end
end)
