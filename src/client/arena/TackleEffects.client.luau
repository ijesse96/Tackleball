local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local defaultFov = camera and camera.FieldOfView or 70

local activeShake = 0
local chargeShakeConnection: RBXScriptConnection? = nil
local activeFovTween: Tween? = nil
local celebrationActive = false
local lastDashCharge01 = 0

local function isCelebrationState(state: Types.RoundState): boolean
	return state == "Scored" or state == "Intermission"
end

local function stopChargeShake()
	if chargeShakeConnection then
		chargeShakeConnection:Disconnect()
		chargeShakeConnection = nil
	end
end

local function stopCameraEffects()
	stopChargeShake()
	activeShake = 0

	if activeFovTween then
		activeFovTween:Cancel()
		activeFovTween = nil
	end
end

local function setCelebrationActive(active: boolean)
	if celebrationActive == active then
		return
	end

	celebrationActive = active
	if active then
		stopCameraEffects()
	end
end

local function playSoundAt(soundId: string, position: Vector3, volume: number)
	if soundId == "" then
		return
	end

	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Position = position
	anchor.Parent = Workspace

	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume
	sound.RollOffMaxDistance = 120
	sound.Parent = anchor
	sound:Play()
	sound.Ended:Connect(function()
		anchor:Destroy()
	end)
end

local function tweenFov(targetFov: number, duration: number)
	if celebrationActive or not camera then
		return
	end

	if activeFovTween then
		activeFovTween:Cancel()
		activeFovTween = nil
	end

	activeFovTween = TweenService:Create(
		camera,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ FieldOfView = targetFov }
	)
	activeFovTween:Play()
end

local function shakeCamera(intensity: number, duration: number)
	if celebrationActive then
		return
	end

	activeShake = math.max(activeShake, os.clock() + duration)

	task.spawn(function()
		local endsAt = os.clock() + duration
		while os.clock() < endsAt and activeShake >= os.clock() - 0.05 do
			if celebrationActive or not camera then
				return
			end

			local offset = Vector3.new(
				(math.random() - 0.5) * intensity,
				(math.random() - 0.5) * intensity,
				0
			)
			camera.CFrame = camera.CFrame * CFrame.new(offset)
			RunService.RenderStepped:Wait()
		end
	end)
end

local function startChargeShake()
	if celebrationActive then
		return
	end

	stopChargeShake()

	local chargeStartedAt = os.clock()
	chargeShakeConnection = RunService.RenderStepped:Connect(function()
		if celebrationActive or not camera then
			return
		end

		local elapsed = os.clock() - chargeStartedAt
		local charge01 = math.clamp(elapsed / Config.CHARGE_MAX_TIME, 0, 1)

		tweenFov(defaultFov + 2 + charge01 * 6, 0.05)

		if math.random() < 0.15 + charge01 * 0.25 then
			shakeCamera(0.1 + charge01 * 0.25, 0.04)
		end
	end)
end

Remotes.tackleChargeStarted().OnClientEvent:Connect(function(tackler: Player)
	if tackler ~= player then
		return
	end

	startChargeShake()
end)

Remotes.tackleDashStarted().OnClientEvent:Connect(function(tackler: Player, charge01: number?)
	if tackler ~= player then
		return
	end

	stopChargeShake()
	lastDashCharge01 = charge01 or 0

	local fovBoost = 4 + lastDashCharge01 * 8
	local shakeIntensity = 0.2 + lastDashCharge01 * 0.35

	tweenFov(defaultFov + fovBoost, 0.08)
	shakeCamera(shakeIntensity, 0.1)
	playSoundAt(
		Config.SOUND_DASH_WHOOSH,
		player.Character and player.Character:GetPivot().Position or Vector3.zero,
		0.4 + lastDashCharge01 * 0.4
	)
end)

local function flashVictimCharacter(victimCharacter: Model)
	if not victimCharacter.Parent then
		return
	end

	local existing = victimCharacter:FindFirstChild("TackleVictimFlash")
	if existing then
		existing:Destroy()
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "TackleVictimFlash"
	highlight.Adornee = victimCharacter
	highlight.FillColor = Color3.fromRGB(255, 40, 40)
	highlight.OutlineColor = Color3.fromRGB(255, 80, 80)
	highlight.FillTransparency = 0.15
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = victimCharacter

	TweenService:Create(
		highlight,
		TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ FillTransparency = 1, OutlineTransparency = 1 }
	):Play()

	task.delay(0.4, function()
		if highlight.Parent then
			highlight:Destroy()
		end
	end)
end

Remotes.tackleVictimFlash().OnClientEvent:Connect(function(victimCharacter: Model)
	if typeof(victimCharacter) ~= "Instance" or not victimCharacter:IsA("Model") then
		return
	end

	flashVictimCharacter(victimCharacter)
end)

Remotes.tackleHit().OnClientEvent:Connect(function(_tackler: Player, _victim: Player?, hitPosition: Vector3, charge01: number?)
	local hitCharge = charge01 or 0

	tweenFov(defaultFov - (6 + hitCharge * 14), 0.06)
	task.delay(0.08, function()
		tweenFov(defaultFov, 0.14)
	end)

	shakeCamera(0.8 + hitCharge * 2.0, 0.14 + hitCharge * 0.1)
	playSoundAt(Config.SOUND_TACKLE_HIT, hitPosition, 0.7 + hitCharge * 0.8)
end)

Remotes.tackleShed().OnClientEvent:Connect(function(_tackler: Player, carrier: Player, hitPosition: Vector3)
	if carrier == player then
		tweenFov(defaultFov + 6, 0.08)
		task.delay(0.1, function()
			tweenFov(defaultFov, 0.12)
		end)
		shakeCamera(0.35, 0.08)
	end

	playSoundAt(Config.SOUND_TACKLE_SHED, hitPosition, 0.85)
end)

Remotes.scoreCelebrationStarted().OnClientEvent:Connect(function()
	setCelebrationActive(true)
end)

Remotes.roundStateChanged().OnClientEvent:Connect(function(payload: Types.RoundStatePayload)
	if payload.state == "Active" or payload.state == "Waiting" then
		setCelebrationActive(false)
	elseif isCelebrationState(payload.state) then
		setCelebrationActive(true)
	end

	if payload.state ~= "Active" or payload.carrierUserId == player.UserId then
		stopChargeShake()
		if not celebrationActive then
			tweenFov(defaultFov, 0.12)
		end
	end
end)
