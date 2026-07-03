local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local AnimationUtil = require(ReplicatedStorage.Shared.AnimationUtil)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local player = Players.LocalPlayer

-- Dive animation plays on the server; this client script silences default walk/run
-- from the Animate script while the local player is tackling.
AnimationUtil.preload()

local function syncRagdollAnimationState(character: Model, wasRagdolled: { was: boolean })
	local isRagdolled = character:GetAttribute("TackleBallRagdollActive") == true
	if isRagdolled then
		wasRagdolled.was = true
		AnimationUtil.stopAllForRagdoll(character)
	elseif wasRagdolled.was then
		wasRagdolled.was = false
		AnimationUtil.restoreAfterRagdoll(character)
	end
end

local function bindRagdollRecovery(character: Model)
	if character:GetAttribute("TackleBallRagdollRecoveryBound") then
		return
	end

	character:SetAttribute("TackleBallRagdollRecoveryBound", true)
	local wasRagdolled = { was = character:GetAttribute("TackleBallRagdollActive") == true }
	character:GetAttributeChangedSignal("TackleBallRagdollActive"):Connect(function()
		syncRagdollAnimationState(character, wasRagdolled)
	end)

	if wasRagdolled.was then
		AnimationUtil.stopAllForRagdoll(character)
	end
end

local function bindPlayer(plr: Player)
	plr.CharacterAdded:Connect(bindRagdollRecovery)
	if plr.Character then
		bindRagdollRecovery(plr.Character)
	end
end

for _, plr in Players:GetPlayers() do
	bindPlayer(plr)
end

Players.PlayerAdded:Connect(bindPlayer)

Workspace.ChildAdded:Connect(function(child)
	if child:IsA("Model")
		and (child:GetAttribute("TackleBallDummyCarrier") == true or child:GetAttribute("TackleBallDummyTackler") == true)
	then
		bindRagdollRecovery(child)
	end
end)

for _, child in Workspace:GetChildren() do
	if child:IsA("Model")
		and (child:GetAttribute("TackleBallDummyCarrier") == true or child:GetAttribute("TackleBallDummyTackler") == true)
	then
		bindRagdollRecovery(child)
	end
end

Remotes.tackleDashStarted().OnClientEvent:Connect(function(tackler: Player)
	if tackler ~= player then
		return
	end

	local character = tackler.Character
	if not character then
		return
	end

	AnimationUtil.lockLocomotionForTackleDive(character)
end)

Remotes.tackleDashEnded().OnClientEvent:Connect(function(tackler: Player)
	if tackler ~= player then
		return
	end

	local character = tackler.Character
	if not character then
		return
	end

	AnimationUtil.unlockLocomotionForTackleDive(character)
end)
