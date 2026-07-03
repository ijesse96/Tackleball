local Config = require(script.Parent.Config)

local PassUtil = {}

function PassUtil.getPassTargetPosition(receiverCharacter: Model): Vector3?
	local root = receiverCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		return root.Position + Vector3.new(0, 2, 0)
	end

	local attachPart = receiverCharacter:FindFirstChild("RightLowerArm") :: BasePart?
		or receiverCharacter:FindFirstChild("RightHand") :: BasePart?
	if attachPart then
		return attachPart.Position + Vector3.new(0, 1, 0)
	end

	return nil
end

function PassUtil.getArcPosition(startPos: Vector3, endPos: Vector3, alpha: number, arcHeight: number): Vector3
	local t = math.clamp(alpha, 0, 1)
	local control = startPos:Lerp(endPos, 0.5) + Vector3.new(0, arcHeight, 0)
	local oneMinusT = 1 - t
	return oneMinusT * oneMinusT * startPos + 2 * oneMinusT * t * control + t * t * endPos
end

function PassUtil.getPassFlightDuration(startPos: Vector3, endPos: Vector3): number
	local flatDistance = (Vector3.new(endPos.X - startPos.X, 0, endPos.Z - startPos.Z)).Magnitude
	return math.max(flatDistance / Config.PASS_SPEED, Config.PASS_MIN_FLIGHT_TIME)
end

function PassUtil.faceCharacterToward(character: Model, targetPosition: Vector3): boolean
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end

	local flat = Vector3.new(targetPosition.X - root.Position.X, 0, targetPosition.Z - root.Position.Z)
	if flat.Magnitude < 0.01 then
		return false
	end

	root.CFrame = CFrame.lookAt(root.Position, root.Position + flat.Unit)
	return true
end

function PassUtil.faceCharacterTowardCharacter(character: Model, targetCharacter: Model): boolean
	local targetRoot = targetCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not targetRoot then
		return false
	end

	return PassUtil.faceCharacterToward(character, targetRoot.Position)
end

return PassUtil
