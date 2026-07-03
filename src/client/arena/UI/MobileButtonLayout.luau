local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local STUDIO_TOUCH_GUI_NAME = "TackleBallStudioTouchGui"
local STUDIO_JUMP_SIZE = 70

local MobileButtonLayout = {}
local studioJumpButton: GuiObject? = nil

function MobileButtonLayout.shouldShow(): boolean
	if UserInputService.TouchEnabled then
		return true
	end

	return RunService:IsStudio() and Config.SHOW_MOBILE_UI_IN_STUDIO
end

local function getWheelAngle(index: number, totalCount: number): number
	if totalCount <= 1 then
		return math.rad(180)
	end

	local topAngle = math.rad(Config.MOBILE_WHEEL_END_ANGLE)
	local bottomAngle = math.rad(Config.MOBILE_WHEEL_START_ANGLE)
	local t = index / (totalCount - 1)
	return topAngle + (bottomAngle - topAngle) * t
end

local function getWheelRadius(jumpSize: Vector2, buttonSize: number): number
	local jumpRadius = math.max(jumpSize.X, jumpSize.Y) * 0.5
	local buttonRadius = buttonSize * 0.5
	return jumpRadius + buttonRadius + Config.MOBILE_WHEEL_GAP
end

function MobileButtonLayout.getJumpCenter(jumpButton: GuiObject): Vector2
	local pos = jumpButton.AbsolutePosition
	local size = jumpButton.AbsoluteSize
	return Vector2.new(pos.X + size.X * 0.5, pos.Y + size.Y * 0.5)
end

function MobileButtonLayout.getFallbackJumpCenter(): Vector2
	local inset = GuiService:GetGuiInset()
	local camera = Workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1920, 1080)
	local margin = 12
	local cx = viewport.X - inset.X - margin - STUDIO_JUMP_SIZE * 0.5
	local cy = viewport.Y - inset.Y - margin - STUDIO_JUMP_SIZE * 0.5
	return Vector2.new(cx, cy)
end

function MobileButtonLayout.positionOnWheel(
	button: GuiObject,
	jumpButton: GuiObject,
	index: number,
	totalCount: number,
	buttonSize: number
)
	local center = MobileButtonLayout.getJumpCenter(jumpButton)
	local jumpSize = jumpButton.AbsoluteSize
	local radius = getWheelRadius(jumpSize, buttonSize)
	local angle = getWheelAngle(index, totalCount)

	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.fromOffset(center.X + math.cos(angle) * radius, center.Y + math.sin(angle) * radius)
end

function MobileButtonLayout.applyWheelFallback(button: GuiObject, index: number, totalCount: number, buttonSize: number)
	local center = MobileButtonLayout.getFallbackJumpCenter()
	local jumpSize = Vector2.new(STUDIO_JUMP_SIZE, STUDIO_JUMP_SIZE)
	local radius = getWheelRadius(jumpSize, buttonSize)
	local angle = getWheelAngle(index, totalCount)

	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.fromOffset(center.X + math.cos(angle) * radius, center.Y + math.sin(angle) * radius)
end

function MobileButtonLayout.positionInColumn(button: GuiObject, jumpButton: GuiObject, index: number, buttonSize: number)
	local gap = Config.MOBILE_TACKLE_BUTTON_GAP
	local jumpPos = jumpButton.AbsolutePosition
	local jumpSize = jumpButton.AbsoluteSize
	local rightX = jumpPos.X + jumpSize.X
	local bottomY = jumpPos.Y - gap - index * (buttonSize + gap)

	button.AnchorPoint = Vector2.new(1, 1)
	button.Position = UDim2.fromOffset(rightX, bottomY)
end

function MobileButtonLayout.applyColumnFallback(button: GuiObject, index: number, buttonSize: number)
	local gap = Config.MOBILE_TACKLE_BUTTON_GAP
	local center = MobileButtonLayout.getFallbackJumpCenter()
	local rightX = center.X + STUDIO_JUMP_SIZE * 0.5
	local jumpTopY = center.Y - STUDIO_JUMP_SIZE * 0.5
	local bottomY = jumpTopY - gap - index * (buttonSize + gap)

	button.AnchorPoint = Vector2.new(1, 1)
	button.Position = UDim2.fromOffset(rightX, bottomY)
end

local function getStudioJumpAnchor(playerGui: PlayerGui): GuiObject?
	if not RunService:IsStudio() or not Config.SHOW_MOBILE_UI_IN_STUDIO then
		return nil
	end

	if studioJumpButton and studioJumpButton.Parent then
		return studioJumpButton
	end

	local screenGui = playerGui:FindFirstChild(STUDIO_TOUCH_GUI_NAME)
	if not screenGui then
		screenGui = Instance.new("ScreenGui")
		screenGui.Name = STUDIO_TOUCH_GUI_NAME
		screenGui.ResetOnSpawn = false
		screenGui.IgnoreGuiInset = true
		screenGui.DisplayOrder = 1
		screenGui.Parent = playerGui

		local jumpButton = Instance.new("TextButton")
		jumpButton.Name = "JumpButton"
		jumpButton.AnchorPoint = Vector2.new(1, 1)
		jumpButton.Size = UDim2.fromOffset(STUDIO_JUMP_SIZE, STUDIO_JUMP_SIZE)
		jumpButton.BackgroundColor3 = Color3.fromRGB(45, 45, 50)
		jumpButton.BackgroundTransparency = 0.35
		jumpButton.BorderSizePixel = 0
		jumpButton.Font = Enum.Font.GothamBold
		jumpButton.Text = "JUMP"
		jumpButton.TextColor3 = Color3.fromRGB(220, 220, 220)
		jumpButton.TextSize = 12
		jumpButton.AutoButtonColor = false
		jumpButton.Active = false
		jumpButton.Selectable = false

		local inset = GuiService:GetGuiInset()
		jumpButton.Position = UDim2.new(1, -(inset.X + 12), 1, -(inset.Y + 12))
		jumpButton.Parent = screenGui

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = jumpButton

		studioJumpButton = jumpButton
		return jumpButton
	end

	local jumpButton = screenGui:FindFirstChild("JumpButton")
	if jumpButton and jumpButton:IsA("GuiObject") then
		studioJumpButton = jumpButton
		return jumpButton
	end

	return nil
end

function MobileButtonLayout.findJumpButton(playerGui: PlayerGui): GuiObject?
	local touchGui = playerGui:FindFirstChild("TouchGui")
	local jumpButton = touchGui and touchGui:FindFirstChild("JumpButton", true)
	if jumpButton and jumpButton:IsA("GuiObject") then
		return jumpButton
	end

	return getStudioJumpAnchor(playerGui)
end

return MobileButtonLayout
