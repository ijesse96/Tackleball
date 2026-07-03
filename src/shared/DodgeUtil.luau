local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local DodgeUtil = {}

function DodgeUtil.getJukeAnimKey(jukeSide: number): string
	return if jukeSide == -1 then "JukeLeft" else "JukeRight"
end

function DodgeUtil.sanitizeClientDodge(dodgeType: any, jukeSide: any): (string, number)
	if dodgeType == "Juke" and (jukeSide == 1 or jukeSide == -1) then
		return "Juke", jukeSide
	end

	return "Truck", 0
end

function DodgeUtil.resolveJukeSide(root: BasePart, worldMove: Vector3): number
	if worldMove.Magnitude < 0.01 then
		return 1
	end

	local localMove = root.CFrame:VectorToObjectSpace(worldMove.Unit)
	if math.abs(localMove.X) < 0.01 then
		return 1
	end

	return if localMove.X > 0 then 1 else -1
end

function DodgeUtil.resolveJukeSideFromCharacter(character: Model, worldMove: Vector3?): number
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		return 1
	end

	local moveDir = worldMove
	if not moveDir or moveDir.Magnitude < 0.01 then
		moveDir = humanoid.MoveDirection
	end

	return DodgeUtil.resolveJukeSide(root, moveDir)
end

function DodgeUtil.resolveFromMoveVector(root: BasePart, worldMove: Vector3): (string, number)
	if worldMove.Magnitude < 0.01 then
		return "Truck", 0
	end

	local localMove = root.CFrame:VectorToObjectSpace(worldMove.Unit)
	local localX = localMove.X
	local localZ = localMove.Z

	if math.abs(localX) > Config.DODGE_SIDEWAYS_THRESHOLD and math.abs(localX) >= math.abs(localZ) then
		return "Juke", if localX > 0 then 1 else -1
	end

	return "Truck", 0
end

function DodgeUtil.resolveFromCharacter(character: Model, worldMove: Vector3?): (string, number)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		return "Truck", 0
	end

	local moveDir = worldMove
	if not moveDir or moveDir.Magnitude < 0.01 then
		moveDir = humanoid.MoveDirection
	end

	return DodgeUtil.resolveFromMoveVector(root, moveDir)
end

return DodgeUtil
