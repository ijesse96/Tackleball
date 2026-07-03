local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local SoccerFieldUtil = require(ReplicatedStorage.Shared.SoccerFieldUtil)

local FloorSafetyService = {}
FloorSafetyService._ballService = nil
FloorSafetyService._connection = nil :: RBXScriptConnection?

local RAYCAST_DISTANCE = 80

local function getFloorTopY(): number?
	return SoccerFieldUtil.getArenaFloorTopY()
end

local function needsFloorRecovery(positionY: number, floorTopY: number): boolean
	return positionY < floorTopY - Config.FLOOR_SAFETY_MARGIN
end

local function recoverCharacterRoot(root: BasePart, character: Model)
	local floorTopY = getFloorTopY()
	if not floorTopY or not needsFloorRecovery(root.Position.Y, floorTopY) then
		return
	end

	local rayOrigin = Vector3.new(root.Position.X, math.max(root.Position.Y, floorTopY + 8), root.Position.Z)
	local ray = SoccerFieldUtil.raycastArenaFloor(rayOrigin, RAYCAST_DISTANCE, { character })
	local offset = Config.FLOOR_SAFETY_CHARACTER_OFFSET
	local snappedPos = if ray
		then ray.Position + ray.Normal * offset
		else Vector3.new(root.Position.X, floorTopY + offset, root.Position.Z)

	local look = root.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatLook.Magnitude < 0.01 then
		flatLook = Vector3.new(0, 0, -1)
	else
		flatLook = flatLook.Unit
	end

	root.CFrame = CFrame.lookAt(snappedPos, snappedPos + flatLook)
	local velocity = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(velocity.X, math.max(0, velocity.Y), velocity.Z)
	root.AssemblyAngularVelocity = Vector3.zero
end

local function recoverCharacters()
	for _, child in Workspace:GetChildren() do
		if not child:IsA("Model") then
			continue
		end

		local humanoid = child:FindFirstChildOfClass("Humanoid")
		local root = child:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not humanoid or not root or humanoid.Health <= 0 then
			continue
		end

		if child:GetAttribute("TackleBallRagdollActive") == true then
			continue
		end

		recoverCharacterRoot(root, child)
	end
end

function FloorSafetyService:init(ballService)
	self._ballService = ballService

	if self._connection then
		self._connection:Disconnect()
	end

	self._connection = RunService.Heartbeat:Connect(function()
		recoverCharacters()
		if self._ballService then
			self._ballService:enforceBallFloor()
		end
	end)
end

return FloorSafetyService
