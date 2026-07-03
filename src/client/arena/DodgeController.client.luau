local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local CarrierDodgeInput = require(script.Parent.CarrierDodgeInput)

local function handleTruckInput(_actionName: string, inputState: Enum.UserInputState, _inputObject: InputObject)
	if inputState == Enum.UserInputState.Begin then
		if CarrierDodgeInput.isTruckCharging() or not CarrierDodgeInput.canUseTruck() then
			return Enum.ContextActionResult.Sink
		end

		CarrierDodgeInput.beginTruckCharge()
		return Enum.ContextActionResult.Sink
	end

	if inputState == Enum.UserInputState.End then
		if not CarrierDodgeInput.isTruckCharging() then
			return Enum.ContextActionResult.Pass
		end

		CarrierDodgeInput.releaseTruckCharge()
		return Enum.ContextActionResult.Sink
	end

	return Enum.ContextActionResult.Pass
end

local function handleJukeInput(_actionName: string, inputState: Enum.UserInputState, _inputObject: InputObject)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end

	if not CarrierDodgeInput.canDodge() then
		return Enum.ContextActionResult.Pass
	end

	CarrierDodgeInput.activateJuke()
	return Enum.ContextActionResult.Sink
end

ContextActionService:BindAction("TruckActivate", handleTruckInput, false, Config.TRUCK_KEY)
ContextActionService:BindAction("JukeActivate", handleJukeInput, false, Config.JUKE_KEY)
