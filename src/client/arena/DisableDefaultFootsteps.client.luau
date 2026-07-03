local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local MUTED_SOUND_NAMES = {
	Running = true,
}

local function muteDefaultFootstepSound(sound: Instance)
	if not sound:IsA("Sound") then
		return
	end

	if not MUTED_SOUND_NAMES[sound.Name] then
		return
	end

	sound.Volume = 0
	sound:Stop()
end

local function bindCharacter(character: Model)
	if character:GetAttribute("TackleBallFootstepsMuted") then
		return
	end

	if not character:FindFirstChildOfClass("Humanoid") then
		return
	end

	character:SetAttribute("TackleBallFootstepsMuted", true)

	for _, descendant in character:GetDescendants() do
		muteDefaultFootstepSound(descendant)
	end

	character.DescendantAdded:Connect(muteDefaultFootstepSound)
end

local function tryBindCharacter(model: Instance)
	if model:IsA("Model") then
		bindCharacter(model)
	end
end

for _, child in Workspace:GetChildren() do
	tryBindCharacter(child)
end

Workspace.ChildAdded:Connect(tryBindCharacter)

for _, listedPlayer in Players:GetPlayers() do
	if listedPlayer.Character then
		bindCharacter(listedPlayer.Character)
	end

	listedPlayer.CharacterAdded:Connect(bindCharacter)
end

Players.PlayerAdded:Connect(function(listedPlayer)
	listedPlayer.CharacterAdded:Connect(bindCharacter)
end)
