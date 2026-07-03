local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local GHOST_FOLDER_NAME = "TackleBallGhosts"
local RAGDOLL_FOLDER_NAME = "TackleBallRagdoll"

local GhostUtil = {}

local function getGhostFolder(): Folder
	local folder = Workspace:FindFirstChild(GHOST_FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = GHOST_FOLDER_NAME
		folder.Parent = Workspace
	end
	return folder :: Folder
end

local function setGhostTransparency(ghost: Model, transparency: number)
	for _, descendant in ghost:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Transparency = transparency
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			descendant.Transparency = transparency
		end
	end
end

local function prepareGhostClone(ghost: Model)
	local ragdollFolder = ghost:FindFirstChild(RAGDOLL_FOLDER_NAME)
	if ragdollFolder then
		ragdollFolder:Destroy()
	end

	for _, descendant in ghost:GetDescendants() do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		elseif descendant:IsA("Humanoid") then
			descendant:Destroy()
		elseif descendant:IsA("BillboardGui") or descendant:IsA("SurfaceGui") or descendant:IsA("Highlight") then
			descendant:Destroy()
		elseif descendant:IsA("Motor6D") or descendant:IsA("BallSocketConstraint") or descendant:IsA("HingeConstraint") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CastShadow = false
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
		end
	end

	ghost:SetAttribute("TackleBallGhost", true)
end

local function getOnBackPivot(character: Model): CFrame
	local pivot = character:GetPivot()
	local lift = Vector3.new(0, Config.GHOST_LIFT_OFFSET, 0)
	return pivot * CFrame.new(lift) * CFrame.Angles(math.rad(-90), 0, 0)
end

function GhostUtil.spawn(character: Model)
	if not character or not character.Parent then
		return
	end

	local ok, ghost = pcall(function()
		return character:Clone()
	end)

	if not ok or not ghost then
		return
	end

	ghost.Name = "TackleBallGhost"
	prepareGhostClone(ghost)
	setGhostTransparency(ghost, Config.GHOST_START_TRANSPARENCY)

	local startPivot = getOnBackPivot(character)
	ghost:PivotTo(startPivot)
	ghost.Parent = getGhostFolder()

	local endPosition = startPivot.Position + Vector3.new(0, Config.GHOST_FLOAT_HEIGHT, 0)
	local duration = Config.GHOST_FLOAT_DURATION
	local startedAt = os.clock()

	local connection: RBXScriptConnection?
	connection = RunService.Heartbeat:Connect(function()
		if not ghost.Parent then
			if connection then
				connection:Disconnect()
			end
			return
		end

		local alpha = math.clamp((os.clock() - startedAt) / duration, 0, 1)
		local eased = alpha * alpha
		local position = startPivot.Position:Lerp(endPosition, eased)
		ghost:PivotTo(CFrame.new(position) * (startPivot - startPivot.Position))

		local transparency = Config.GHOST_START_TRANSPARENCY
			+ (Config.GHOST_END_TRANSPARENCY - Config.GHOST_START_TRANSPARENCY) * eased
		setGhostTransparency(ghost, transparency)

		if alpha >= 1 then
			if connection then
				connection:Disconnect()
			end
			ghost:Destroy()
		end
	end)
end

return GhostUtil
