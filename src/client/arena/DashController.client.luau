local ContextActionService = game:GetService("ContextActionService")

local TackleInput = require(script.Parent.TackleInput)

local function handleTackleInput(_actionName: string, inputState: Enum.UserInputState, _inputObject: InputObject)
	if inputState == Enum.UserInputState.Begin then
		if TackleInput.isCharging() or not TackleInput.canTackle() then
			return Enum.ContextActionResult.Sink
		end

		TackleInput.beginCharge()
		return Enum.ContextActionResult.Sink
	end

	if inputState == Enum.UserInputState.End then
		if not TackleInput.isCharging() then
			return Enum.ContextActionResult.Pass
		end

		TackleInput.releaseCharge()
		return Enum.ContextActionResult.Sink
	end

	return Enum.ContextActionResult.Pass
end

ContextActionService:BindAction("TackleCharge", handleTackleInput, false, Enum.KeyCode.Q)
