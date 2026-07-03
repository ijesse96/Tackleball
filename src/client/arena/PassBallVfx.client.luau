local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

type PassVfxState = {
	ballRoot: BasePart,
	attach0: Attachment,
	attach1: Attachment,
	trail: Trail,
	emitter: ParticleEmitter,
	lastPosition: Vector3,
	updateConnection: RBXScriptConnection,
	attributeConnection: RBXScriptConnection?,
}

local activeVfx: PassVfxState? = nil
local pendingFlightWatcher: RBXScriptConnection? = nil

local function stopPendingFlightWatcher()
	if pendingFlightWatcher then
		pendingFlightWatcher:Disconnect()
		pendingFlightWatcher = nil
	end
end

local function getBallRoot(): BasePart?
	local gameBall = Workspace:FindFirstChild("GameBall")
	if not gameBall then
		return nil
	end

	if gameBall:IsA("BasePart") then
		return gameBall
	end

	if gameBall:IsA("Model") then
		if gameBall.PrimaryPart and gameBall.PrimaryPart:IsA("BasePart") then
			return gameBall.PrimaryPart
		end

		return gameBall:FindFirstChildWhichIsA("MeshPart", true)
			or gameBall:FindFirstChildWhichIsA("BasePart", true)
	end

	return nil
end

local function updateTrailDirection(state: PassVfxState, deltaTime: number)
	local ballRoot = state.ballRoot
	if not ballRoot.Parent then
		return
	end

	local position = ballRoot.Position
	local delta = position - state.lastPosition
	state.lastPosition = position

	if delta.Magnitude < 0.02 then
		state.attach0.WorldPosition = position
		state.attach1.WorldPosition = position - ballRoot.CFrame.LookVector * Config.PASS_TRAIL_SPAN
		return
	end

	local back = delta.Unit * Config.PASS_TRAIL_SPAN
	state.attach0.WorldPosition = position
	state.attach1.WorldPosition = position - back

	local speed = delta.Magnitude / math.max(deltaTime, 0.001)
	state.emitter.Speed = NumberRange.new(speed * 0.35, speed * 0.55)
end

local function destroyPassVfx()
	local state = activeVfx
	if not state then
		return
	end

	activeVfx = nil

	state.updateConnection:Disconnect()
	if state.attributeConnection then
		state.attributeConnection:Disconnect()
	end

	state.trail.Enabled = false
	state.emitter.Enabled = false
	state.trail:Destroy()
	state.emitter:Destroy()
	state.attach0:Destroy()
	state.attach1:Destroy()
end

local function createPassVfx(ballRoot: BasePart): PassVfxState?
	if activeVfx and activeVfx.ballRoot == ballRoot then
		return activeVfx
	end

	destroyPassVfx()

	local attach0 = Instance.new("Attachment")
	attach0.Name = "PassTrail0"
	attach0.Parent = ballRoot

	local attach1 = Instance.new("Attachment")
	attach1.Name = "PassTrail1"
	attach1.Parent = ballRoot

	local trail = Instance.new("Trail")
	trail.Name = "PassSpeedTrail"
	trail.Attachment0 = attach0
	trail.Attachment1 = attach1
	trail.Lifetime = Config.PASS_TRAIL_LIFETIME
	trail.MinLength = Config.PASS_TRAIL_MIN_LENGTH
	trail.FaceCamera = true
	trail.LightEmission = 1
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(220, 240, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(140, 200, 255)),
	})
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, Config.PASS_TRAIL_WIDTH),
		NumberSequenceKeypoint.new(1, 0.05),
	})
	trail.Enabled = true
	trail.Parent = ballRoot

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "PassWind"
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.Rate = Config.PASS_WIND_PARTICLE_RATE
	emitter.Lifetime = NumberRange.new(0.12, 0.28)
	emitter.Speed = NumberRange.new(10, 18)
	emitter.SpreadAngle = Vector2.new(10, 10)
	emitter.Drag = 2
	emitter.VelocityInheritance = 0.8
	emitter.LightEmission = 0.9
	emitter.Rotation = NumberRange.new(-20, 20)
	emitter.RotSpeed = NumberRange.new(-40, 40)
	emitter.Orientation = Enum.ParticleOrientation.VelocityParallel
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(235, 245, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(170, 210, 255)),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(0.5, 0.65),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9),
		NumberSequenceKeypoint.new(1, 0.05),
	})
	emitter.Enabled = true
	emitter.Parent = attach1

	local state: PassVfxState = {
		ballRoot = ballRoot,
		attach0 = attach0,
		attach1 = attach1,
		trail = trail,
		emitter = emitter,
		lastPosition = ballRoot.Position,
		updateConnection = nil :: any,
		attributeConnection = nil,
	}

	state.updateConnection = RunService.RenderStepped:Connect(function(deltaTime)
		if ballRoot:GetAttribute("PassInFlight") ~= true then
			destroyPassVfx()
			return
		end

		updateTrailDirection(state, deltaTime)
	end)

	state.attributeConnection = ballRoot:GetAttributeChangedSignal("PassInFlight"):Connect(function()
		if ballRoot:GetAttribute("PassInFlight") ~= true then
			destroyPassVfx()
		end
	end)

	activeVfx = state
	updateTrailDirection(state, 1 / 60)
	return state
end

local function tryStartPassVfx()
	local ballRoot = getBallRoot()
	if not ballRoot then
		return
	end

	if ballRoot:GetAttribute("PassInFlight") == true then
		stopPendingFlightWatcher()
		createPassVfx(ballRoot)
	end
end

local function watchForPassFlight()
	stopPendingFlightWatcher()

	local ballRoot = getBallRoot()
	if not ballRoot then
		return
	end

	if ballRoot:GetAttribute("PassInFlight") == true then
		createPassVfx(ballRoot)
		return
	end

	pendingFlightWatcher = ballRoot:GetAttributeChangedSignal("PassInFlight"):Connect(function()
		if ballRoot:GetAttribute("PassInFlight") == true then
			stopPendingFlightWatcher()
			createPassVfx(ballRoot)
		end
	end)

	task.delay(Config.PASS_RELEASE_DELAY + Config.PASS_TIMEOUT, stopPendingFlightWatcher)
end

Remotes.passStarted().OnClientEvent:Connect(function()
	task.defer(watchForPassFlight)
end)

Remotes.passEnded().OnClientEvent:Connect(function()
	stopPendingFlightWatcher()
	destroyPassVfx()
end)

Workspace.ChildAdded:Connect(function(child)
	if child.Name ~= "GameBall" then
		return
	end

	task.defer(tryStartPassVfx)
end)

tryStartPassVfx()
