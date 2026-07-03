local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local TackleInput = {}

local player = Players.LocalPlayer
local latestPayload: Types.RoundStatePayload? = nil
local isCharging = false
local chargeIntent = false
local initialized = false

local function isLocalCarrier(): boolean
	return latestPayload ~= nil and latestPayload.carrierUserId == player.UserId
end

local function init()
	if initialized then
		return
	end
	initialized = true

	Remotes.dashChargeBegin()
	Remotes.dashChargeRelease()

	Remotes.roundStateChanged().OnClientEvent:Connect(function(payload: Types.RoundStatePayload)
		latestPayload = payload

		if (isCharging or chargeIntent) and isLocalCarrier() then
			isCharging = false
			chargeIntent = false
		end
	end)

	Remotes.tackleChargeStarted().OnClientEvent:Connect(function(tackler: Player)
		if tackler == player then
			chargeIntent = false
			isCharging = true
		end
	end)

	Remotes.tackleDashStarted().OnClientEvent:Connect(function(tackler: Player)
		if tackler == player then
			isCharging = false
			chargeIntent = false
		end
	end)
end

function TackleInput.canTackle(): boolean
	if not latestPayload or latestPayload.state ~= "Active" then
		return false
	end

	if latestPayload.carrierUserId == player.UserId then
		return false
	end

	return true
end

function TackleInput.isCharging(): boolean
	return isCharging or chargeIntent
end

function TackleInput.getLatestPayload(): Types.RoundStatePayload?
	return latestPayload
end

function TackleInput.beginCharge(): boolean
	init()

	if isCharging or chargeIntent then
		return false
	end

	if isLocalCarrier() then
		return false
	end

	chargeIntent = true
	Remotes.dashChargeBegin():FireServer()
	return true
end

function TackleInput.releaseCharge(): boolean
	init()

	if not isCharging and not chargeIntent then
		return false
	end

	chargeIntent = false
	isCharging = false
	Remotes.dashChargeRelease():FireServer()
	return true
end

init()

return TackleInput
