local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local LegacyRigUtil = require(script.Parent.LegacyRigUtil)

local RagdollUtil = {}

local RAGDOLL_TAG = "TackleBallRagdoll"
local RAGDOLL_FOLDER_NAME = "RagdollConstraints"

local LIMB_PART_NAMES = {
	"Head",
	"LeftUpperArm",
	"LeftLowerArm",
	"LeftHand",
	"RightUpperArm",
	"RightLowerArm",
	"RightHand",
	"LeftUpperLeg",
	"LeftLowerLeg",
	"LeftFoot",
	"RightUpperLeg",
	"RightLowerLeg",
	"RightFoot",
}

local TORSO_PART_NAMES = {
	"UpperTorso",
	"LowerTorso",
}

local CORE_PART_NAMES = {
	"HumanoidRootPart",
}

type PartPhysicsState = {
	part: BasePart,
	massless: boolean,
	canCollide: boolean,
	customPhysicalProperties: PhysicalProperties?,
}

type ConstraintState = {
	instance: Instance,
	enabled: boolean?,
	isKinematic: boolean?,
}

type RagdollSession = {
	maintainConnection: RBXScriptConnection?,
	evaluateStateMachine: boolean?,
	partStates: { PartPhysicsState },
	createdInstances: { Instance },
	constraintStates: { ConstraintState },
}

local ragdollSessions = {} :: { [Model]: RagdollSession }

local function getHumanoid(character: Model): Humanoid?
	return character:FindFirstChildOfClass("Humanoid")
end

local function isStiffJoint(jointName: string): boolean
	for _, name in Config.RAGDOLL_STIFF_JOINT_NAMES do
		if jointName == name then
			return true
		end
	end
	return false
end

local function isOurRagdollInstance(instance: Instance): boolean
	return instance:GetAttribute(RAGDOLL_TAG) == true
		or instance:FindFirstAncestor(RAGDOLL_FOLDER_NAME) ~= nil
end

local function tagInstance(instance: Instance)
	instance:SetAttribute(RAGDOLL_TAG, true)
end

local function configureConstraint(constraint: BallSocketConstraint)
	constraint.LimitsEnabled = Config.RAGDOLL_LIMITS_ENABLED
	constraint.TwistLimitsEnabled = Config.RAGDOLL_LIMITS_ENABLED
	if Config.RAGDOLL_LIMITS_ENABLED then
		constraint.UpperAngle = 90
		constraint.TwistLowerAngle = -90
		constraint.TwistUpperAngle = 90
	end
	constraint.MaxFrictionTorque = Config.RAGDOLL_MAX_FRICTION
end

local function setServerNetworkOwnership(character: Model)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			pcall(function()
				descendant:SetNetworkOwner(nil)
			end)
		end
	end
end

local function preparePartPhysics(character: Model, session: RagdollSession)
	local limbDensity = Config.RAGDOLL_LIMB_DENSITY
	local torsoDensity = Config.RAGDOLL_TORSO_DENSITY
	local hrpDensity = Config.RAGDOLL_HRP_DENSITY or torsoDensity * 0.5

	local friction = Config.RAGDOLL_PART_FRICTION
	local elasticity = Config.RAGDOLL_PART_ELASTICITY or 0.5

	local function preparePart(part: BasePart, density: number)
		table.insert(session.partStates, {
			part = part,
			massless = part.Massless,
			canCollide = part.CanCollide,
			customPhysicalProperties = part.CustomPhysicalProperties,
		})

		part.Massless = false
		part.CanCollide = true
		part.CustomPhysicalProperties = PhysicalProperties.new(density, friction, elasticity, 1, 1)
	end

	for _, partName in LIMB_PART_NAMES do
		local part = character:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			preparePart(part, limbDensity)
		end
	end

	for _, partName in TORSO_PART_NAMES do
		local part = character:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			preparePart(part, torsoDensity)
		end
	end

	for _, partName in CORE_PART_NAMES do
		local part = character:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			preparePart(part, hrpDensity)
		end
	end
end

local function restorePartPhysics(session: RagdollSession)
	for _, state in session.partStates do
		local part = state.part
		if part.Parent then
			part.Massless = state.massless
			part.CanCollide = state.canCollide
			part.CustomPhysicalProperties = state.customPhysicalProperties
		end
	end
end

local function restoreConstraintStates(session: RagdollSession)
	for _, state in session.constraintStates do
		local instance = state.instance
		if not instance.Parent then
			continue
		end

		if typeof(state.isKinematic) == "boolean" and instance:IsA("AnimationConstraint") then
			instance.IsKinematic = state.isKinematic
		elseif typeof(state.enabled) == "boolean" and instance:IsA("BallSocketConstraint") then
			instance.Enabled = state.enabled
		end
	end
end

local function buildMotor6DConstraints(character: Model, session: RagdollSession): number
	local count = 0

	for _, descendant in character:GetDescendants() do
		if descendant:IsA("Motor6D") and descendant.Part0 and descendant.Part1 and not isStiffJoint(descendant.Name) then
			descendant.Enabled = false

			local att0 = Instance.new("Attachment")
			att0.Name = "RagdollAtt0"
			att0.CFrame = descendant.C0
			tagInstance(att0)
			att0.Parent = descendant.Part0
			table.insert(session.createdInstances, att0)

			local att1 = Instance.new("Attachment")
			att1.Name = "RagdollAtt1"
			att1.CFrame = descendant.C1
			tagInstance(att1)
			att1.Parent = descendant.Part1
			table.insert(session.createdInstances, att1)

			local socket = Instance.new("BallSocketConstraint")
			socket.Name = "RagdollSocket"
			socket.Attachment0 = att0
			socket.Attachment1 = att1
			configureConstraint(socket)
			tagInstance(socket)
			socket.Parent = descendant.Part0
			table.insert(session.createdInstances, socket)
			count += 1
		end
	end

	return count
end

local function enableAvatarJointRagdoll(character: Model, session: RagdollSession): number
	local socketCount = 0

	for _, descendant in character:GetDescendants() do
		if descendant:IsA("AnimationConstraint") and not isOurRagdollInstance(descendant) then
			table.insert(session.constraintStates, {
				instance = descendant,
				isKinematic = descendant.IsKinematic,
			})

			if isStiffJoint(descendant.Name) then
				descendant.IsKinematic = true
			else
				descendant.IsKinematic = false
			end
		end
	end

	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BallSocketConstraint") and not isOurRagdollInstance(descendant) then
			if isStiffJoint(descendant.Name) then
				continue
			end

			table.insert(session.constraintStates, {
				instance = descendant,
				enabled = descendant.Enabled,
			})
			descendant.Enabled = true
			socketCount += 1
		end
	end

	return socketCount
end

local function setHumanoidStateEnabled(humanoid: Humanoid, stateType: Enum.HumanoidStateType, enabled: boolean)
	pcall(function()
		humanoid:SetStateEnabled(stateType, enabled)
	end)
end

local function disableNonPhysicsStates(humanoid: Humanoid)
	for _, stateType in Enum.HumanoidStateType:GetEnumItems() do
		if stateType ~= Enum.HumanoidStateType.Physics and stateType ~= Enum.HumanoidStateType.None then
			setHumanoidStateEnabled(humanoid, stateType, false)
		end
	end
	setHumanoidStateEnabled(humanoid, Enum.HumanoidStateType.Physics, true)
end

local function restoreHumanoidStates(humanoid: Humanoid)
	for _, stateType in Enum.HumanoidStateType:GetEnumItems() do
		setHumanoidStateEnabled(humanoid, stateType, true)
	end
end

local function disableAnimate(character: Model)
	local animate = character:FindFirstChild("Animate")
	if animate and (animate:IsA("LocalScript") or animate:IsA("Script")) then
		animate.Enabled = false
	end
end

local function startMaintainLoop(character: Model, session: RagdollSession): RBXScriptConnection
	return RunService.PostSimulation:Connect(function()
		if not character.Parent or not character:GetAttribute("TackleBallRagdollActive") then
			return
		end

		for _, descendant in character:GetDescendants() do
			if descendant:IsA("Motor6D") and not isStiffJoint(descendant.Name) and descendant.Enabled then
				descendant.Enabled = false
			elseif descendant:IsA("AnimationConstraint") and not isOurRagdollInstance(descendant) then
				if isStiffJoint(descendant.Name) then
					if not descendant.IsKinematic then
						descendant.IsKinematic = true
					end
				elseif descendant.IsKinematic then
					descendant.IsKinematic = false
				end
			elseif descendant:IsA("BallSocketConstraint") and not isOurRagdollInstance(descendant) then
				if not isStiffJoint(descendant.Name) and not descendant.Enabled then
					descendant.Enabled = true
				end
			end
		end

		for _, partName in LIMB_PART_NAMES do
			local part = character:FindFirstChild(partName)
			if part and part:IsA("BasePart") then
				if part.Massless then
					part.Massless = false
				end
				if not part.CanCollide then
					part.CanCollide = true
				end
			end
		end

		for _, partName in TORSO_PART_NAMES do
			local part = character:FindFirstChild(partName)
			if part and part:IsA("BasePart") and not part.CanCollide then
				part.CanCollide = true
			end
		end

		local humanoid = getHumanoid(character)
		if humanoid then
			humanoid.WalkSpeed = 0
			humanoid.PlatformStand = true
			humanoid.AutoRotate = false
		end

		local root = character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and not root.CanCollide then
			root.CanCollide = true
		end
	end)
end

local function clearSession(character: Model)
	local session = ragdollSessions[character]
	if not session then
		return
	end

	ragdollSessions[character] = nil

	if session.maintainConnection then
		session.maintainConnection:Disconnect()
	end

	restorePartPhysics(session)
	restoreConstraintStates(session)

	local humanoid = getHumanoid(character)
	if humanoid and session.evaluateStateMachine ~= nil then
		humanoid.EvaluateStateMachine = session.evaluateStateMachine
	end

	for _, instance in session.createdInstances do
		if instance.Parent then
			instance:Destroy()
		end
	end
end

function RagdollUtil.enable(character: Model): boolean
	local humanoid = getHumanoid(character)
	if not humanoid or humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return false
	end

	if character:GetAttribute("TackleBallRagdollActive") and ragdollSessions[character] then
		return true
	end

	if character:FindFirstChild(RAGDOLL_FOLDER_NAME) then
		local folder = character:FindFirstChild(RAGDOLL_FOLDER_NAME)
		if folder then
			folder:Destroy()
		end
	end

	LegacyRigUtil.ensureMotor6DRig(character)

	local session: RagdollSession = {
		partStates = {},
		createdInstances = {},
		constraintStates = {},
		evaluateStateMachine = humanoid.EvaluateStateMachine,
	}
	ragdollSessions[character] = session

	local constraintCount = 0
	local ok, err = pcall(function()
		humanoid.BreakJointsOnDeath = false
		humanoid.WalkSpeed = 0
		humanoid.AutoRotate = false
		humanoid.PlatformStand = true
		humanoid.EvaluateStateMachine = false

		disableNonPhysicsStates(humanoid)

		disableAnimate(character)
		setServerNetworkOwnership(character)
		preparePartPhysics(character, session)

		local motorCount = buildMotor6DConstraints(character, session)
		if motorCount == 0 then
			constraintCount = enableAvatarJointRagdoll(character, session)
		else
			constraintCount = motorCount
		end

		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		session.maintainConnection = startMaintainLoop(character, session)
	end)

	if not ok then
		warn(`TackleBall: ragdoll enable failed ({err})`)
		clearSession(character)
		return false
	end

	if constraintCount == 0 then
		warn("TackleBall: ragdoll enabled with zero BallSocketConstraints")
		clearSession(character)
		return false
	end

	return true
end

function RagdollUtil.disable(character: Model)
	local humanoid = getHumanoid(character)
	if not humanoid then
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end

	clearSession(character)

	for _, descendant in character:GetDescendants() do
		if descendant:IsA("Motor6D") then
			descendant.Enabled = true
		end
	end

	pcall(function()
		humanoid.PlatformStand = false
		restoreHumanoidStates(humanoid)
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end)
end

return RagdollUtil
