local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local DodgeUtil = require(ReplicatedStorage.Shared.DodgeUtil)
local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local CarrierDodgeInput = {}

local player = Players.LocalPlayer
local latestPayload: Types.RoundStatePayload? = nil
local dodgeWindowActive = false
local activeDodgeType: Types.DodgeType? = nil
local isTruckCharging = false
local truckChargeIntent = false
local truckCooldownEndsAt = 0
local initialized = false

local function getKeyboardMoveVector(): Vector3?
	local x = 0
	local z = 0

	if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then
		x -= 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then
		x += 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then
		z -= 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down) then
		z += 1
	end

	if x == 0 and z == 0 then
		return nil
	end

	local camera = Workspace.CurrentCamera
	if not camera then
		return Vector3.new(x, 0, z)
	end

	local look = camera.CFrame.LookVector
	local right = camera.CFrame.RightVector
	local forward = Vector3.new(look.X, 0, look.Z)
	local flatRight = Vector3.new(right.X, 0, right.Z)

	if forward.Magnitude < 0.01 or flatRight.Magnitude < 0.01 then
		return Vector3.new(x, 0, z)
	end

	forward = forward.Unit
	flatRight = flatRight.Unit

	return (flatRight * x + forward * -z).Unit
end

local function resolveJukeSide(character: Model): number
	local keyboardMove = getKeyboardMoveVector()
	if keyboardMove then
		return DodgeUtil.resolveJukeSideFromCharacter(character, keyboardMove)
	end

	return DodgeUtil.resolveJukeSideFromCharacter(character, nil)
end

local function init()
	if initialized then
		return
	end
	initialized = true

	Remotes.dodgeActivate()
	Remotes.dodgeStarted()
	Remotes.truckChargeBegin()
	Remotes.truckChargeRelease()
	Remotes.truckChargeStarted()
	Remotes.truckDashStarted()
	Remotes.truckDashEnded()

	Remotes.roundStateChanged().OnClientEvent:Connect(function(payload: Types.RoundStatePayload)
		latestPayload = payload

		if payload.state ~= "Active" or payload.carrierUserId ~= player.UserId then
			dodgeWindowActive = false
			activeDodgeType = nil
			isTruckCharging = false
			truckChargeIntent = false
		end
	end)

	Remotes.dodgeStarted().OnClientEvent:Connect(function(carrier: Player, dodgeType: string)
		if carrier == player then
			dodgeWindowActive = true
			activeDodgeType = if dodgeType == "Juke" then "Juke" else "Truck"
		end
	end)

	Remotes.truckChargeStarted().OnClientEvent:Connect(function(carrier: Player)
		if carrier == player then
			truckChargeIntent = false
			isTruckCharging = true
		end
	end)

	Remotes.truckDashStarted().OnClientEvent:Connect(function(carrier: Player)
		if carrier == player then
			isTruckCharging = false
			truckChargeIntent = false
			dodgeWindowActive = true
			activeDodgeType = "Truck"
			truckCooldownEndsAt = os.clock() + Config.TRUCK_COOLDOWN
		end
	end)

	Remotes.truckDashEnded().OnClientEvent:Connect(function(carrier: Player)
		if carrier == player and activeDodgeType == "Truck" then
			dodgeWindowActive = false
			activeDodgeType = nil
		end
	end)

	Remotes.tackleShed().OnClientEvent:Connect(function(_tackler: Player, carrier: Player, _hitPosition: Vector3?, dodgeType: string?)
		if carrier == player then
			if dodgeType == "Truck" then
				truckCooldownEndsAt = 0
			end
			dodgeWindowActive = false
			activeDodgeType = nil
		end
	end)
end

function CarrierDodgeInput.canDodge(): boolean
	if not latestPayload or latestPayload.state ~= "Active" then
		return false
	end

	return latestPayload.carrierUserId == player.UserId
end

function CarrierDodgeInput.isDodgeWindowActive(): boolean
	return dodgeWindowActive
end

function CarrierDodgeInput.isTruckCharging(): boolean
	return isTruckCharging or truckChargeIntent
end

function CarrierDodgeInput.getActiveDodgeType(): Types.DodgeType?
	return activeDodgeType
end

function CarrierDodgeInput.canUseTruck(): boolean
	return CarrierDodgeInput.canDodge() and os.clock() >= truckCooldownEndsAt
end

function CarrierDodgeInput.getTruckCooldownRemaining(): number
	return math.max(0, truckCooldownEndsAt - os.clock())
end

function CarrierDodgeInput.resetTruckCooldown()
	truckCooldownEndsAt = 0
end

function CarrierDodgeInput.beginTruckCharge(): boolean
	init()

	if isTruckCharging or truckChargeIntent then
		return false
	end

	if not CarrierDodgeInput.canUseTruck() then
		return false
	end

	truckChargeIntent = true
	Remotes.truckChargeBegin():FireServer()
	return true
end

function CarrierDodgeInput.releaseTruckCharge(): boolean
	init()

	if not isTruckCharging and not truckChargeIntent then
		return false
	end

	truckChargeIntent = false
	isTruckCharging = false
	Remotes.truckChargeRelease():FireServer()
	return true
end

function CarrierDodgeInput.activateJuke(): boolean
	init()

	if not CarrierDodgeInput.canDodge() then
		return false
	end

	local character = player.Character
	if not character then
		return false
	end

	local jukeSide = resolveJukeSide(character)
	Remotes.dodgeActivate():FireServer("Juke", jukeSide)
	return true
end

init()

return CarrierDodgeInput
