local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimationUtil = require(ReplicatedStorage.Shared.AnimationUtil)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

AnimationUtil.preload()

local function shouldLockDodgeLocomotion(character: Model): boolean
	return character:GetAttribute("TruckTuckWindowActive") == true
		or character:GetAttribute("TruckTuckActive") == true
end

local function syncDodgeLocomotionLock(character: Model)
	if shouldLockDodgeLocomotion(character) then
		AnimationUtil.lockLocomotionForTruckTuck(character)
	else
		AnimationUtil.unlockLocomotionForTruckTuck(character)
	end
end

local function bindCharacter(character: Model)
	character:GetAttributeChangedSignal("TruckTuckWindowActive"):Connect(function()
		syncDodgeLocomotionLock(character)
	end)

	character:GetAttributeChangedSignal("TruckTuckActive"):Connect(function()
		syncDodgeLocomotionLock(character)
	end)
end

local function bindPlayer(player: Player)
	player.CharacterAdded:Connect(bindCharacter)
	if player.Character then
		bindCharacter(player.Character)
	end
end

for _, player in Players:GetPlayers() do
	bindPlayer(player)
end

Players.PlayerAdded:Connect(bindPlayer)

Remotes.dodgeStarted().OnClientEvent:Connect(function(carrier: Player)
	local character = carrier.Character
	if not character then
		return
	end

	AnimationUtil.stopRunLoop(character)
	AnimationUtil.lockLocomotionForTruckTuck(character)
end)

Remotes.tackleShed().OnClientEvent:Connect(function(_tackler: Player, carrier: Player)
	if carrier.Character then
		AnimationUtil.stopRunLoop(carrier.Character)
		syncDodgeLocomotionLock(carrier.Character)
	end
end)

Remotes.tackleHit().OnClientEvent:Connect(function(_tackler: Player, carrier: Player?)
	if carrier and carrier.Character then
		AnimationUtil.unlockLocomotionForTruckTuck(carrier.Character)
	end
end)
