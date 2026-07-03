local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local MobileButtonLayout = require(script.Parent.MobileButtonLayout)

if not MobileButtonLayout.shouldShow() then
	return
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local buttonSize = Config.MOBILE_TACKLE_BUTTON_SIZE

local COLUMN_BUTTONS = {
	{ screenGuiName = "TackleButtonUI", buttonName = "TackleButton" },
	{ screenGuiName = "PassButtonUI", buttonName = "PassButton" },
}

local function findColumnButton(entry: { screenGuiName: string, buttonName: string }): GuiObject?
	local screenGui = playerGui:FindFirstChild(entry.screenGuiName)
	if not screenGui then
		return nil
	end

	local button = screenGui:FindFirstChild(entry.buttonName)
	if button and button:IsA("GuiObject") then
		return button
	end

	return nil
end

local function collectVisibleButtons(): { GuiObject }
	local visible: { GuiObject } = {}

	for _, entry in COLUMN_BUTTONS do
		local button = findColumnButton(entry)
		if button and button.Visible then
			table.insert(visible, button)
		end
	end

	return visible
end

local function updateColumnLayout()
	local jumpButton = MobileButtonLayout.findJumpButton(playerGui)
	local visibleButtons = collectVisibleButtons()

	for index, button in visibleButtons do
		local columnIndex = index - 1
		if jumpButton then
			MobileButtonLayout.positionInColumn(button, jumpButton, columnIndex, buttonSize)
		else
			MobileButtonLayout.applyColumnFallback(button, columnIndex, buttonSize)
		end
	end
end

RunService.RenderStepped:Connect(updateColumnLayout)
updateColumnLayout()
