local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local HealthService = require(script.Parent.HealthService)
local LegacyRigUtil = require(script.Parent.LegacyRigUtil)

local DummyCarrierService = {}
DummyCarrierService._template = nil :: Model?
DummyCarrierService._dummy = nil :: Model?
DummyCarrierService._behaviorLoopRunning = false
DummyCarrierService._chaseLoopRunning = false
DummyCarrierService._fleeTarget = nil :: Player?
DummyCarrierService._getBallPosition = nil :: (() -> Vector3?)?
DummyCarrierService._lastMoveAt = 0
DummyCarrierService._matchService = nil

local function getTemplate(): Model
	if DummyCarrierService._template then
		LegacyRigUtil.ensureMotor6DRig(DummyCarrierService._template)
		return DummyCarrierService._template
	end

	local description = Instance.new("HumanoidDescription")
	description.HeadColor = Color3.fromRGB(90, 170, 255)
	description.TorsoColor = Color3.fromRGB(60, 130, 220)
	description.LeftArmColor = Color3.fromRGB(60, 130, 220)
	description.RightArmColor = Color3.fromRGB(60, 130, 220)
	description.LeftLegColor = Color3.fromRGB(45, 100, 190)
	description.RightLegColor = Color3.fromRGB(45, 100, 190)

	local template = Players:CreateHumanoidModelFromDescriptionAsync(
		description,
		Enum.HumanoidRigType.R15,
		Enum.AssetTypeVerification.ClientOnly
	)
	template.Name = "DummyCarrierTemplate"
	template.Parent = ServerStorage
	LegacyRigUtil.ensureMotor6DRig(template)
	DummyCarrierService._template = template
	return template
end

function DummyCarrierService:getDummy(): Model?
	return self._dummy
end

function DummyCarrierService:_getHumanoid(): Humanoid?
	return self._dummy and self._dummy:FindFirstChildOfClass("Humanoid")
end

function DummyCarrierService:_setJogEnabled(enabled: boolean)
	local humanoid = self:_getHumanoid()
	if not humanoid then
		return
	end

	if enabled then
		humanoid.WalkSpeed = Config.DUMMY_CARRIER_JOG_SPEED
		humanoid.AutoRotate = true
	else
		humanoid.WalkSpeed = 0
		if self._dummy then
			humanoid:MoveTo(self._dummy:GetPivot().Position)
		end
		humanoid.AutoRotate = false
	end
end

function DummyCarrierService:spawn(nearPosition: Vector3): Model?
	self:despawn()

	local ok, dummy = pcall(function()
		local model = getTemplate():Clone()
		model.Name = Config.DUMMY_CARRIER_NAME
		model:SetAttribute("TackleBallDummy", true)
		model:SetAttribute("TackleBallDummyCarrier", true)

		local humanoid = model:FindFirstChildOfClass("Humanoid")
		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not humanoid or not root then
			error("Dummy carrier template is missing Humanoid or HumanoidRootPart")
		end

		humanoid.AutoRotate = false
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.DisplayName = "Carrier NPC"

		HealthService:setupCharacter(model)

		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				pcall(function()
					descendant:SetNetworkOwner(nil)
				end)
			end
		end

		local spawnCFrame = CFrame.new(nearPosition + Config.DUMMY_CARRIER_SPAWN_OFFSET + Vector3.new(0, 3, 0))
		model:PivotTo(spawnCFrame)
		model.Parent = workspace

		return model
	end)

	if not ok or not dummy then
		warn(`TackleBall: failed to spawn dummy carrier ({dummy})`)
		return nil
	end

	self._dummy = dummy
	self._lastMoveAt = 0
	return dummy
end

function DummyCarrierService:stopBallChaseLoop()
	self._chaseLoopRunning = false
	self._getBallPosition = nil
	self:_setJogEnabled(false)
end

function DummyCarrierService:isChasingBall(): boolean
	return self._chaseLoopRunning
end

function DummyCarrierService:stopBehaviorLoop()
	self._behaviorLoopRunning = false
	self._fleeTarget = nil
	self:stopBallChaseLoop()
end

function DummyCarrierService:startBallChaseLoop(getBallPosition: () -> Vector3?)
	self._behaviorLoopRunning = false
	self._fleeTarget = nil

	if self._chaseLoopRunning then
		self._getBallPosition = getBallPosition
		return
	end

	self._getBallPosition = getBallPosition
	self._chaseLoopRunning = true
	self._lastMoveAt = 0

	task.spawn(function()
		while self._chaseLoopRunning and self._dummy and self._dummy.Parent do
			task.wait(0.1)

			if not self._chaseLoopRunning or not self._dummy or not self._dummy.Parent then
				break
			end

			if not self._matchService or not self._matchService:isActive() then
				self:_setJogEnabled(false)
				continue
			end

			local getPosition = self._getBallPosition
			local ballPosition = if getPosition then getPosition() else nil
			if not ballPosition then
				self:_setJogEnabled(false)
				continue
			end

			local dummyRoot = self._dummy:FindFirstChild("HumanoidRootPart") :: BasePart?
			local humanoid = self:_getHumanoid()
			if not dummyRoot or not humanoid then
				self:_setJogEnabled(false)
				continue
			end

			if os.clock() - self._lastMoveAt < Config.DUMMY_CARRIER_FLEE_UPDATE_INTERVAL then
				continue
			end

			self:_setJogEnabled(true)
			humanoid:MoveTo(ballPosition)
			self._lastMoveAt = os.clock()
		end

		self._chaseLoopRunning = false
	end)
end

function DummyCarrierService:startBehaviorLoop(fleeFromPlayer: Player)
	self:stopBallChaseLoop()

	if self._behaviorLoopRunning then
		self._fleeTarget = fleeFromPlayer
		return
	end

	self._fleeTarget = fleeFromPlayer
	self._behaviorLoopRunning = true

	task.spawn(function()
		while self._behaviorLoopRunning and self._dummy and self._dummy.Parent do
			task.wait(0.1)

			if not self._behaviorLoopRunning or not self._dummy or not self._dummy.Parent then
				break
			end

			if not self._matchService or not self._matchService:isActive() then
				self:_setJogEnabled(false)
				continue
			end

			local dummyRoot = self._dummy:FindFirstChild("HumanoidRootPart") :: BasePart?
			local humanoid = self:_getHumanoid()
			local fleeTarget = self._fleeTarget
			local fleeRoot = fleeTarget and fleeTarget.Character and fleeTarget.Character:FindFirstChild("HumanoidRootPart") :: BasePart?

			if not dummyRoot or not humanoid or not fleeRoot then
				self:_setJogEnabled(false)
				continue
			end

			if os.clock() - self._lastMoveAt < Config.DUMMY_CARRIER_FLEE_UPDATE_INTERVAL then
				continue
			end

			self:_setJogEnabled(true)

			local away = dummyRoot.Position - fleeRoot.Position
			local flatAway = Vector3.new(away.X, 0, away.Z)
			if flatAway.Magnitude < 0.01 then
				flatAway = Vector3.new(1, 0, 0)
			else
				flatAway = flatAway.Unit
			end

			local fleeDistance = 26
			local destination = dummyRoot.Position + flatAway * fleeDistance
			humanoid:MoveTo(destination)
			self._lastMoveAt = os.clock()
		end

		self._behaviorLoopRunning = false
	end)
end

function DummyCarrierService:despawn()
	self:stopBehaviorLoop()
	if self._dummy then
		self._dummy:Destroy()
		self._dummy = nil
	end
end

function DummyCarrierService:init(matchService)
	self._matchService = matchService

	task.spawn(function()
		pcall(getTemplate)
	end)
end

return DummyCarrierService
