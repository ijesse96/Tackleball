local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MobileButtonLayout = require(script.Parent.UI.MobileButtonLayout)

if not MobileButtonLayout.shouldShow() then
	return
end

local player = Players.LocalPlayer
local visibilityConnection: RBXScriptConnection? = nil
local humanoidConnections: { RBXScriptConnection } = {}

local function disconnectHumanoidConnections()
	for _, connection in humanoidConnections do
		connection:Disconnect()
	end
	table.clear(humanoidConnections)
end

local function disconnectVisibilityConnection()
	if visibilityConnection then
		visibilityConnection:Disconnect()
		visibilityConnection = nil
	end
end

local function shouldKeepJumpButtonVisible(humanoid: Humanoid, character: Model): boolean
	if character:GetAttribute("TackleBallCelebrationLocked") == true then
		return false
	end

	if humanoid.JumpHeight <= 0 then
		return false
	end

	return humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping)
end

local function findJumpButton(): GuiObject?
	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then
		return nil
	end

	local touchGui = playerGui:FindFirstChild("TouchGui")
	if not touchGui then
		return nil
	end

	local jumpButton = touchGui:FindFirstChild("JumpButton", true)
	if jumpButton and jumpButton:IsA("GuiObject") then
		return jumpButton
	end

	return nil
end

local function syncJumpButton(jumpButton: GuiObject, humanoid: Humanoid, character: Model)
	if shouldKeepJumpButtonVisible(humanoid, character) then
		jumpButton.Visible = true
	end
end

local function bindJumpButton(jumpButton: GuiObject, humanoid: Humanoid, character: Model)
	disconnectVisibilityConnection()
	disconnectHumanoidConnections()

	local function refresh()
		syncJumpButton(jumpButton, humanoid, character)
	end

	refresh()

	visibilityConnection = jumpButton:GetPropertyChangedSignal("Visible"):Connect(function()
		if shouldKeepJumpButtonVisible(humanoid, character) and not jumpButton.Visible then
			jumpButton.Visible = true
		end
	end)

	table.insert(humanoidConnections, humanoid:GetPropertyChangedSignal("JumpHeight"):Connect(refresh))
	table.insert(
		humanoidConnections,
		humanoid:GetPropertyChangedSignal("Jump"):Connect(function()
			task.defer(refresh)
		end)
	)
	table.insert(
		humanoidConnections,
		character:GetAttributeChangedSignal("TackleBallCelebrationLocked"):Connect(refresh)
	)
end

local function bindCharacter(character: Model)
	disconnectVisibilityConnection()
	disconnectHumanoidConnections()

	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end

	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)

	task.spawn(function()
		for _ = 1, 60 do
			if not character.Parent then
				return
			end

			local jumpButton = findJumpButton()
			if jumpButton then
				bindJumpButton(jumpButton, humanoid, character)
				return
			end

			task.wait(0.1)
		end
	end)
end

player.CharacterAdded:Connect(bindCharacter)
if player.Character then
	bindCharacter(player.Character)
end
