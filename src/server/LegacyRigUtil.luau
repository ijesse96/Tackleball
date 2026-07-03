local CONVERTED_ATTRIBUTE = "TackleBallMotor6DRig"

local LegacyRigUtil = {}

local function hasMotor6DJoints(character: Model): boolean
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("Motor6D") and descendant.Part0 and descendant.Part1 then
			return true
		end
	end

	return false
end

function LegacyRigUtil.ensureMotor6DRig(character: Model): boolean
	if not character or not character.Parent then
		return false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return false
	end

	if hasMotor6DJoints(character) then
		character:SetAttribute(CONVERTED_ATTRIBUTE, true)
		return true
	end

	local animationConstraints = {}
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("AnimationConstraint") then
			table.insert(animationConstraints, descendant)
		end
	end

	if #animationConstraints == 0 then
		for _ = 1, 5 do
			task.wait(0.05)
			for _, descendant in character:GetDescendants() do
				if descendant:IsA("AnimationConstraint") then
					table.insert(animationConstraints, descendant)
				end
			end
			if #animationConstraints > 0 then
				break
			end
		end
	end

	if #animationConstraints == 0 then
		return false
	end

	local converted = 0
	for _, animationConstraint in animationConstraints do
		local attachment0 = animationConstraint.Attachment0
		local attachment1 = animationConstraint.Attachment1
		local part0 = attachment0 and attachment0.Parent
		local part1 = attachment1 and attachment1.Parent

		if not attachment0 or not attachment1 or not part0 or not part1 then
			continue
		end
		if not part0:IsA("BasePart") or not part1:IsA("BasePart") then
			continue
		end

		local motor = Instance.new("Motor6D")
		motor.Name = animationConstraint.Name
		motor.Part0 = part0
		motor.Part1 = part1
		motor.C0 = attachment0.CFrame
		motor.C1 = attachment1.CFrame
		motor.Parent = part1
		converted += 1
	end

	if converted == 0 then
		return false
	end

	local toDestroy = {}
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("AnimationConstraint")
			or descendant:IsA("BallSocketConstraint")
			or descendant:IsA("NoCollisionConstraint")
		then
			table.insert(toDestroy, descendant)
		end
	end

	for _, instance in toDestroy do
		if instance.Parent then
			instance:Destroy()
		end
	end

	character:SetAttribute(CONVERTED_ATTRIBUTE, true)
	return true
end

return LegacyRigUtil
