local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)

local AnimationUtil = {}

local cachedDiveAnimation: Animation? = nil
local cachedKnockbackAnimation: Animation? = nil
local cachedGetUpAnimation: Animation? = nil
local cachedRunAnimation: Animation? = nil
local cachedJumpAnimation: Animation? = nil
local cachedPassThrowAnimation: Animation? = nil
local cachedDodgeAnimations = {} :: { [string]: Animation }
local activeDodgeTypes = {} :: { [Model]: string }
local activeDiveTracks = {} :: { [Model]: AnimationTrack }
local activeKnockbackTracks = {} :: { [Model]: AnimationTrack }
local activeGetUpTracks = {} :: { [Model]: AnimationTrack }
local activeRunTracks = {} :: { [Model]: AnimationTrack }
local activeJumpTracks = {} :: { [Model]: AnimationTrack }
local activePassThrowTracks = {} :: { [Model]: AnimationTrack }
local activeTruckTuckTracks = {} :: { [Model]: AnimationTrack }
local animateSuppressed = {} :: { [Model]: boolean }
local diveLocomotionLocked = {} :: { [Model]: { suppressionConnection: RBXScriptConnection? } }
local truckTuckLocomotionLocked = {} :: { [Model]: { suppressionConnection: RBXScriptConnection? } }
local truckTuckSuppressionConnections = {} :: { [Model]: RBXScriptConnection }
local jumpSuppressionConnections = {} :: { [Model]: RBXScriptConnection }
local jumpAnimationPlayedConnections = {} :: { [Model]: RBXScriptConnection }
local jumpDefaultBlockConnections = {} :: { [Model]: RBXScriptConnection }
local jumpAirborneCharacters = {} :: { [Model]: boolean }
local jumpStoredAnimate = {} :: { [Model]: LocalScript }
local jumpRequestedCharacters = {} :: { [Model]: boolean }
local carrierNativeJumpCharacters = {} :: { [Model]: boolean }
local carrierJumpBoostConnections = {} :: { [Model]: RBXScriptConnection }
local dodgeFreezeConnections = {} :: { [Model]: RBXScriptConnection }
local jukeFreezeCallbacks = {} :: { [Model]: () -> () }

local blockedDefaultAirAnimLookup: { [string]: boolean }? = nil

local function getBlockedDefaultAirAnimLookup(): { [string]: boolean }
	if blockedDefaultAirAnimLookup then
		return blockedDefaultAirAnimLookup
	end

	local lookup = {}
	for _, animationId in Config.BLOCKED_DEFAULT_AIR_ANIM_IDS do
		lookup[animationId] = true
	end
	blockedDefaultAirAnimLookup = lookup
	return lookup
end

local function isBlockedDefaultAirAnimation(animationId: string): boolean
	return getBlockedDefaultAirAnimLookup()[animationId] == true
end

function AnimationUtil.canAcceptJump(humanoid: Humanoid): boolean
	local state = humanoid:GetState()
	if state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.Freefall then
		return false
	end

	local character = humanoid.Parent
	if not character or not character:IsA("Model") then
		return false
	end

	return AnimationUtil.isCharacterGrounded(humanoid, character)
end

function AnimationUtil.getJumpRaycastParams(character: Model): RaycastParams
	local filter = { character }
	local gameBall = workspace:FindFirstChild("GameBall")
	if gameBall then
		table.insert(filter, gameBall)
	end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = filter
	return rayParams
end

function AnimationUtil.isCharacterGrounded(humanoid: Humanoid, character: Model): boolean
	if humanoid.FloorMaterial ~= Enum.Material.Air then
		return true
	end

	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end

	local origin = root.Position + Vector3.new(0, 0.5, 0)
	local ray = workspace:Raycast(origin, Vector3.new(0, -6, 0), AnimationUtil.getJumpRaycastParams(character))
	return ray ~= nil
end

local function isHumanoidAirborne(humanoid: Humanoid, character: Model): boolean
	local state = humanoid:GetState()
	if state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.Freefall then
		return true
	end

	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return root ~= nil and root.AssemblyLinearVelocity.Y > 2
end

function AnimationUtil.isJumpInProgress(character: Model): boolean
	if carrierNativeJumpCharacters[character] then
		return true
	end

	if jumpRequestedCharacters[character] or activeJumpTracks[character] or jumpAirborneCharacters[character] then
		return true
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false
	end

	return isHumanoidAirborne(humanoid, character)
end

function AnimationUtil.beginJumpRequest(character: Model)
	AnimationUtil.stopRunLoop(character, true)
	jumpRequestedCharacters[character] = true
	AnimationUtil.setCarrierAnimateEnabled(character, true)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		humanoid.EvaluateStateMachine = true
	end
end

function AnimationUtil.beginCarrierNativeJump(character: Model)
	carrierNativeJumpCharacters[character] = true
end

function AnimationUtil.isCarrierNativeJump(character: Model): boolean
	return carrierNativeJumpCharacters[character] == true
end

local function stopCarrierJumpBoost(character: Model)
	local connection = carrierJumpBoostConnections[character]
	if connection then
		connection:Disconnect()
		carrierJumpBoostConnections[character] = nil
	end
end

local function getCarrierLaunchVelocity(): number
	return math.sqrt(2 * workspace.Gravity * Config.CARRIER_JUMP_HEIGHT)
end

function AnimationUtil.applyCarrierJumpImpulse(character: Model, humanoid: Humanoid)
	if isHumanoidAirborne(humanoid, character) then
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	local launchVelocity = getCarrierLaunchVelocity()

	local function boost()
		local velocity = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(velocity.X, math.max(velocity.Y, launchVelocity), velocity.Z)
		pcall(function()
			humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		end)
	end

	boost()
	stopCarrierJumpBoost(character)

	local boostedAt = os.clock()
	carrierJumpBoostConnections[character] = RunService.PreSimulation:Connect(function()
		if not character.Parent or not carrierNativeJumpCharacters[character] then
			stopCarrierJumpBoost(character)
			return
		end

		local currentHumanoid = character:FindFirstChildOfClass("Humanoid")
		local currentRoot = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not currentHumanoid or not currentRoot then
			stopCarrierJumpBoost(character)
			return
		end

		if os.clock() - boostedAt > 0.3 then
			stopCarrierJumpBoost(character)
			return
		end

		if currentRoot.AssemblyLinearVelocity.Y < launchVelocity * 0.65 then
			boost()
		end
	end)
end

function AnimationUtil.ensureJumpImpulse(character: Model, humanoid: Humanoid)
	if isHumanoidAirborne(humanoid, character) then
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end

	if root.AssemblyLinearVelocity.Y > 3 then
		return
	end

	local jumpHeight = if carrierNativeJumpCharacters[character]
		then Config.CARRIER_JUMP_HEIGHT
		else math.max(humanoid.JumpHeight, 1)
	local launchVelocity = math.sqrt(2 * workspace.Gravity * jumpHeight)
	local velocity = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(velocity.X, launchVelocity, velocity.Z)

	pcall(function()
		root:ApplyImpulse(Vector3.new(0, root.AssemblyMass * launchVelocity * 0.5, 0))
	end)

	pcall(function()
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	end)
end

local function denyJump(humanoid: Humanoid)
	if humanoid.Jump then
		humanoid.Jump = false
	end
end

local function restoreMobileJumpButton()
	if not RunService:IsClient() or not UserInputService.TouchEnabled then
		return
	end

	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		return
	end

	local playerGui = localPlayer:FindFirstChild("PlayerGui")
	if not playerGui then
		return
	end

	local touchGui = playerGui:FindFirstChild("TouchGui")
	if not touchGui then
		return
	end

	local jumpButton = touchGui:FindFirstChild("JumpButton", true)
	if jumpButton and jumpButton:IsA("GuiObject") then
		jumpButton.Visible = true
		task.defer(function()
			if jumpButton.Parent then
				jumpButton.Visible = true
			end
		end)
	end
end

local function isDefaultAirTrack(track: AnimationTrack, keepTrack: AnimationTrack?): boolean
	if track == keepTrack then
		return false
	end

	local anim = track.Animation
	if anim then
		if anim.AnimationId == Config.JUMP_ANIMATION then
			return false
		end
		if isBlockedDefaultAirAnimation(anim.AnimationId) then
			return true
		end
	end

	local lowered = string.lower(track.Name)
	return lowered == "jump" or lowered == "fall"
end

local function muteCompetingTracks(animator: Animator, keepTrack: AnimationTrack)
	for _, playingTrack in animator:GetPlayingAnimationTracks() do
		if playingTrack == keepTrack then
			pcall(function()
				playingTrack:AdjustWeight(1, 0)
			end)
			continue
		end

		pcall(function()
			playingTrack:AdjustWeight(0, 0)
		end)
		playingTrack:Stop(0)
	end
end

local function syncAnimationId(animation: Animation, configuredId: string): Animation
	if animation.AnimationId ~= configuredId then
		animation.AnimationId = configuredId
	end

	return animation
end

local function getConfiguredAnimation(name: string, configuredId: string, cache: Animation?): Animation
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing and existing:IsA("Animation") then
		return syncAnimationId(existing, configuredId)
	end

	if cache then
		return syncAnimationId(cache, configuredId)
	end

	local animation = Instance.new("Animation")
	animation.Name = name
	animation.AnimationId = configuredId
	return animation
end

local function getDiveAnimationInstance(): Animation
	local existing = ReplicatedStorage:FindFirstChild("TackleDiveAnimation")
	if existing and existing:IsA("Animation") then
		return existing
	end

	if cachedDiveAnimation then
		return cachedDiveAnimation
	end

	local animation = Instance.new("Animation")
	animation.Name = "TackleDiveAnimation"
	animation.AnimationId = Config.TACKLE_DIVE_ANIMATION
	cachedDiveAnimation = animation
	return animation
end

local function getKnockbackAnimationInstance(): Animation
	local existing = ReplicatedStorage:FindFirstChild("TackleKnockbackAnimation")
	if existing and existing:IsA("Animation") then
		return existing
	end

	if cachedKnockbackAnimation then
		return cachedKnockbackAnimation
	end

	local animation = Instance.new("Animation")
	animation.Name = "TackleKnockbackAnimation"
	animation.AnimationId = Config.TACKLE_KNOCKBACK_ANIMATION
	cachedKnockbackAnimation = animation
	return animation
end

local function getGetUpAnimationInstance(): Animation
	local existing = ReplicatedStorage:FindFirstChild("TackleGetUpAnimation")
	if existing and existing:IsA("Animation") then
		return existing
	end

	if cachedGetUpAnimation then
		return cachedGetUpAnimation
	end

	local animation = Instance.new("Animation")
	animation.Name = "TackleGetUpAnimation"
	animation.AnimationId = Config.TACKLE_GETUP_ANIMATION
	cachedGetUpAnimation = animation
	return animation
end

local function getRunAnimationInstance(): Animation
	cachedRunAnimation = getConfiguredAnimation("RunAnimation", Config.RUN_ANIMATION, cachedRunAnimation)
	return cachedRunAnimation
end

local function getJumpAnimationInstance(): Animation
	cachedJumpAnimation = getConfiguredAnimation("JumpAnimation", Config.JUMP_ANIMATION, cachedJumpAnimation)
	return cachedJumpAnimation
end

local function getPassThrowAnimationInstance(): Animation
	cachedPassThrowAnimation = getConfiguredAnimation("PassThrowAnimation", Config.PASS_THROW_ANIMATION, cachedPassThrowAnimation)
	return cachedPassThrowAnimation
end

local function getDodgeAnimationInstance(dodgeType: string): Animation?
	local configuredId = Config.DODGE_ANIMATIONS[dodgeType]
	if not configuredId or configuredId == "" or configuredId == "rbxassetid://0" then
		return nil
	end

	local instanceName = Config.DODGE_ANIM_INSTANCE_NAMES[dodgeType]
	if not instanceName then
		return nil
	end

	local existing = ReplicatedStorage:FindFirstChild(instanceName)
	if existing and existing:IsA("Animation") then
		return syncAnimationId(existing, configuredId)
	end

	local cached = cachedDodgeAnimations[dodgeType]
	if cached then
		return syncAnimationId(cached, configuredId)
	end

	local animation = Instance.new("Animation")
	animation.Name = instanceName
	animation.AnimationId = configuredId
	cachedDodgeAnimations[dodgeType] = animation
	return animation
end

local function getTruckTuckAnimationInstance(): Animation?
	return getDodgeAnimationInstance("Truck")
end

local function isJukeAnimKey(animKey: string?): boolean
	return animKey == "JukeLeft" or animKey == "JukeRight"
end

local function resolveDodgeAnimKey(dodgeType: string, jukeSide: number?): string
	if dodgeType == "Juke" then
		return if jukeSide == -1 then "JukeLeft" else "JukeRight"
	end

	return "Truck"
end

local function isDodgeAnimationId(animationId: string): boolean
	for _, configuredId in Config.DODGE_ANIMATIONS do
		if animationId == configuredId then
			return true
		end
	end
	return false
end

function AnimationUtil.preload()
	if preloadStarted then
		return
	end
	preloadStarted = true

	local diveAnimation = getDiveAnimationInstance()
	local knockbackAnimation = getKnockbackAnimationInstance()
	local getUpAnimation = getGetUpAnimationInstance()
	local runAnimation = getRunAnimationInstance()
	local jumpAnimation = getJumpAnimationInstance()
	local passThrowAnimation = getPassThrowAnimationInstance()
	local truckTuckAnimation = getDodgeAnimationInstance("Truck")
	local jukeAnimation = getDodgeAnimationInstance("JukeRight")
	local jukeLeftAnimation = getDodgeAnimationInstance("JukeLeft")
	task.spawn(function()
		local assets = { diveAnimation, knockbackAnimation, getUpAnimation, runAnimation, jumpAnimation, passThrowAnimation }
		if truckTuckAnimation then
			table.insert(assets, truckTuckAnimation)
		end
		if jukeAnimation then
			table.insert(assets, jukeAnimation)
		end
		if jukeLeftAnimation then
			table.insert(assets, jukeLeftAnimation)
		end
		pcall(function()
			ContentProvider:PreloadAsync(assets)
		end)
	end)
end

local function getAnimator(humanoid: Humanoid): Animator
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		return animator
	end

	animator = Instance.new("Animator")
	animator.Parent = humanoid
	return animator
end

local function isR15Humanoid(humanoid: Humanoid): boolean
	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		warn("TackleBall: tackle animations require an R15 character")
		return false
	end

	return true
end

local function suppressDefaultLocomotion(animator: Animator, keepTrack: AnimationTrack?)
	for _, track in animator:GetPlayingAnimationTracks() do
		if track == keepTrack then
			continue
		end

		local priority = track.Priority
		if priority == Enum.AnimationPriority.Movement or priority == Enum.AnimationPriority.Core then
			track:Stop(0.05)
		end
	end
end

local function suppressAllExcept(animator: Animator, keepTrack: AnimationTrack?)
	for _, track in animator:GetPlayingAnimationTracks() do
		if track ~= keepTrack then
			track:Stop(0)
		end
	end
end

local function disableAnimateScript(character: Model)
	local animate = character:FindFirstChild("Animate")
	if animate and (animate:IsA("LocalScript") or animate:IsA("Script")) then
		animate.Enabled = false
		animateSuppressed[character] = true
	end
end

function AnimationUtil.stopAllForRagdoll(character: Model)
	AnimationUtil.stopRunLoop(character)
	AnimationUtil.stopJump(character)
	AnimationUtil.stopTruckTuck(character)
	AnimationUtil.stopKnockback(character)
	AnimationUtil.stopGetUp(character)
	AnimationUtil.stopTackleDive(character)
	AnimationUtil.setCarrierAnimateEnabled(character, false)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end

	for _, track in animator:GetPlayingAnimationTracks() do
		track:Stop(0)
	end
end

local function stopCustomAnimationTracks(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		return
	end

	local customAnimationIds = {
		[Config.TACKLE_KNOCKBACK_ANIMATION] = true,
		[Config.TACKLE_GETUP_ANIMATION] = true,
		[Config.TACKLE_DIVE_ANIMATION] = true,
		[Config.JUMP_ANIMATION] = true,
		[Config.RUN_ANIMATION] = true,
	}

	for _, configuredId in Config.DODGE_ANIMATIONS do
		customAnimationIds[configuredId] = true
	end

	for _, track in animator:GetPlayingAnimationTracks() do
		local anim = track.Animation
		if anim and customAnimationIds[anim.AnimationId] then
			pcall(function()
				track:AdjustSpeed(1)
			end)
			track:Stop(0.1)
		end
	end
end

function AnimationUtil.resetLocomotion(character: Model)
	AnimationUtil.stopJump(character)
	AnimationUtil.stopKnockback(character)
	AnimationUtil.stopGetUp(character)
	AnimationUtil.stopTackleDive(character)

	if not RunService:IsServer() then
		AnimationUtil.unlockLocomotionForTackleDive(character)
		AnimationUtil.unlockLocomotionForTruckTuck(character)
	end

	stopCustomAnimationTracks(character)

	if not activeRunTracks[character]
		and not AnimationUtil.isTruckTuckActive(character)
		and not AnimationUtil.isJumpPlaying(character)
	then
		AnimationUtil.setCarrierAnimateEnabled(character, true)
	end
end

function AnimationUtil.restoreAfterRagdoll(character: Model)
	AnimationUtil.stopJump(character)
	AnimationUtil.stopKnockback(character)
	AnimationUtil.stopGetUp(character)
	AnimationUtil.stopTackleDive(character)
	AnimationUtil.stopDodge(character)

	if not RunService:IsServer() then
		AnimationUtil.unlockLocomotionForTackleDive(character)
		AnimationUtil.unlockLocomotionForTruckTuck(character)
	end

	stopCustomAnimationTracks(character)
	AnimationUtil.setCarrierAnimateEnabled(character, true)
end

function AnimationUtil.setCarrierAnimateEnabled(character: Model, enabled: boolean)
	if enabled and not character:FindFirstChild("Animate") then
		local backup = jumpStoredAnimate[character]
		if backup then
			local restored = backup:Clone()
			restored.Parent = character
			jumpStoredAnimate[character] = nil
		end
	end

	local animate = character:FindFirstChild("Animate")
	if not animate or not (animate:IsA("LocalScript") or animate:IsA("Script")) then
		return
	end

	if enabled then
		if animateSuppressed[character] then
			animate.Enabled = true
			animateSuppressed[character] = nil
		end
	else
		if animate.Enabled then
			animate.Enabled = false
			animateSuppressed[character] = true
		end
	end
end

function AnimationUtil.lockLocomotionForTackleDive(character: Model)
	if RunService:IsServer() or diveLocomotionLocked[character] then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local animate = character:FindFirstChild("Animate")
	if animate and (animate:IsA("LocalScript") or animate:IsA("Script")) then
		animate.Enabled = false
	end

	local animator = getAnimator(humanoid)
	suppressDefaultLocomotion(animator, nil)

	local suppressionConnection = RunService.PostSimulation:Connect(function()
		if not diveLocomotionLocked[character] or not character.Parent then
			return
		end

		local currentHumanoid = character:FindFirstChildOfClass("Humanoid")
		if currentHumanoid then
			suppressDefaultLocomotion(getAnimator(currentHumanoid), nil)
		end
	end)

	diveLocomotionLocked[character] = {
		suppressionConnection = suppressionConnection,
	}
end

function AnimationUtil.unlockLocomotionForTackleDive(character: Model)
	local state = diveLocomotionLocked[character]
	if not state then
		return
	end

	diveLocomotionLocked[character] = nil

	if state.suppressionConnection then
		state.suppressionConnection:Disconnect()
	end

	if not activeRunTracks[character] then
		local animate = character:FindFirstChild("Animate")
		if animate and (animate:IsA("LocalScript") or animate:IsA("Script")) then
			animate.Enabled = true
		end
	end
end

local function findDodgeTrack(animator: Animator, character: Model): AnimationTrack?
	local tracked = activeTruckTuckTracks[character]
	if tracked then
		return tracked
	end

	for _, track in animator:GetPlayingAnimationTracks() do
		local anim = track.Animation
		if anim and isDodgeAnimationId(anim.AnimationId) then
			return track
		end
	end

	return nil
end

local function findTruckTrack(animator: Animator, character: Model): AnimationTrack?
	return findDodgeTrack(animator, character)
end

function AnimationUtil.isTruckTuckActive(character: Model): boolean
	if character:GetAttribute("TruckTuckWindowActive") == true then
		return true
	end

	if character:GetAttribute("TruckTuckActive") == true then
		return true
	end

	if activeTruckTuckTracks[character] then
		return true
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			for _, track in animator:GetPlayingAnimationTracks() do
				local anim = track.Animation
				if anim and isDodgeAnimationId(anim.AnimationId) and track.IsPlaying then
					return true
				end
			end
		end
	end

	return false
end

local function stopRunAnimationTracks(character: Model, reEnableAnimate: boolean?, immediate: boolean?)
	local fadeTime = if immediate then 0 else 0.15
	local track = activeRunTracks[character]
	if track then
		track:Stop(fadeTime)
		activeRunTracks[character] = nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local animator = getAnimator(humanoid)
		for _, playingTrack in animator:GetPlayingAnimationTracks() do
			local anim = playingTrack.Animation
			if anim and anim.AnimationId == Config.RUN_ANIMATION then
				playingTrack:Stop(if immediate then 0 else 0.1)
			end
		end
	end

	if reEnableAnimate ~= false
		and not AnimationUtil.isTruckTuckActive(character)
		and not AnimationUtil.isJumpPlaying(character)
	then
		AnimationUtil.setCarrierAnimateEnabled(character, true)
	end
end

local function shouldReEnableAnimateAfterJump(character: Model): boolean
	if activeRunTracks[character] then
		return false
	end

	if activeTruckTuckTracks[character] or AnimationUtil.isTruckTuckActive(character) then
		return false
	end

	if diveLocomotionLocked[character] or truckTuckLocomotionLocked[character] then
		return false
	end

	return true
end

local function releaseAnimateAfterJump(character: Model)
	if not character:FindFirstChild("Animate") then
		local backup = jumpStoredAnimate[character]
		if backup then
			local restored = backup:Clone()
			restored.Parent = character
		end
	end

	jumpStoredAnimate[character] = nil

	local animate = character:FindFirstChild("Animate")
	if not animate or not (animate:IsA("LocalScript") or animate:IsA("Script")) then
		return
	end

	if shouldReEnableAnimateAfterJump(character) then
		animate.Enabled = true
		animateSuppressed[character] = nil
	else
		animate.Enabled = false
		animateSuppressed[character] = true
	end
end

local function stashAndRemoveAnimate(character: Model)
	local animate = character:FindFirstChild("Animate")
	if not animate or not (animate:IsA("LocalScript") or animate:IsA("Script")) then
		return
	end

	if not jumpStoredAnimate[character] then
		jumpStoredAnimate[character] = animate:Clone()
	end
	animate:Destroy()
end

local function stopJumpSuppression(character: Model)
	local connection = jumpSuppressionConnections[character]
	if connection then
		connection:Disconnect()
		jumpSuppressionConnections[character] = nil
	end

	local playedConnection = jumpAnimationPlayedConnections[character]
	if playedConnection then
		playedConnection:Disconnect()
		jumpAnimationPlayedConnections[character] = nil
	end
end

local function holdJumpTrackAtEnd(track: AnimationTrack)
	if track.Length <= 0 then
		if not track.IsPlaying then
			track:Play(0, 1, 0)
		end
		return
	end

	local holdTime = math.max(0, track.Length - 0.03)
	track.TimePosition = holdTime
	track:AdjustSpeed(0)
	if not track.IsPlaying then
		track:Play(0, 1, 0)
	end
end

local function maintainJumpTrack(track: AnimationTrack)
	if track.IsPlaying then
		if track.Length > 0 and track.TimePosition >= track.Length - 0.05 then
			holdJumpTrackAtEnd(track)
		end
		return
	end

	if track.Length > 0 then
		holdJumpTrackAtEnd(track)
	else
		track:Play(0, 1, 1)
	end
end

local function tryFinishJumpIfGrounded(character: Model): boolean
	if not jumpAirborneCharacters[character] then
		return false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or not AnimationUtil.isCharacterGrounded(humanoid, character) then
		return false
	end

	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root and math.abs(root.AssemblyLinearVelocity.Y) > 6 then
		return false
	end

	restoreMobileJumpButton()
	AnimationUtil.stopJump(character)
	return true
end

local function startJumpSuppression(character: Model, track: AnimationTrack)
	stopJumpSuppression(character)
	stashAndRemoveAnimate(character)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local animator = getAnimator(humanoid)
		jumpAnimationPlayedConnections[character] = animator.AnimationPlayed:Connect(function(playedTrack)
			if not jumpAirborneCharacters[character] then
				return
			end

			if playedTrack ~= track then
				playedTrack:Stop(0)
			end
		end)
	end

	local jumpStartedAt = os.clock()

	local function suppressAirborneAnimations()
		if activeJumpTracks[character] ~= track or not character.Parent then
			return
		end

		local currentHumanoid = character:FindFirstChildOfClass("Humanoid")
		if not currentHumanoid then
			AnimationUtil.stopJump(character)
			return
		end

		if isHumanoidAirborne(currentHumanoid, character) then
			jumpAirborneCharacters[character] = true
		end

		if jumpAirborneCharacters[character] then
			if tryFinishJumpIfGrounded(character) then
				return
			end

			stashAndRemoveAnimate(character)

			local animator = getAnimator(currentHumanoid)
			muteCompetingTracks(animator, track)
			maintainJumpTrack(track)
			return
		end

		if not track.IsPlaying then
			track:Play(0, 1, 1)
		end

		if AnimationUtil.isCharacterGrounded(currentHumanoid, character) and os.clock() - jumpStartedAt < 0.2 then
			AnimationUtil.ensureJumpImpulse(character, currentHumanoid)
		end
	end

	jumpSuppressionConnections[character] = RunService.PreAnimation:Connect(suppressAirborneAnimations)
	suppressAirborneAnimations()
end

local function stopDodgeFreeze(character: Model)
	local connection = dodgeFreezeConnections[character]
	if connection then
		connection:Disconnect()
		dodgeFreezeConnections[character] = nil
	end
end

local function holdJukePose(character: Model, track: AnimationTrack)
	if track.Length > 0 then
		track.TimePosition = math.max(track.Length - 0.04, 0)
	end

	pcall(function()
		track:AdjustSpeed(0)
	end)

	local callback = jukeFreezeCallbacks[character]
	if callback then
		jukeFreezeCallbacks[character] = nil
		callback()
	end
end

local function startJukeFreezeMonitor(character: Model, track: AnimationTrack)
	stopDodgeFreeze(character)

	dodgeFreezeConnections[character] = RunService.Heartbeat:Connect(function()
		if activeTruckTuckTracks[character] ~= track or not character.Parent then
			stopDodgeFreeze(character)
			return
		end

		if not track.IsPlaying then
			return
		end

		if track.Length > 0 and track.TimePosition >= track.Length - 0.05 then
			holdJukePose(character, track)
			stopDodgeFreeze(character)
		end
	end)
end

local function stopTruckTuckSuppression(character: Model)
	local connection = truckTuckSuppressionConnections[character]
	if connection then
		connection:Disconnect()
		truckTuckSuppressionConnections[character] = nil
	end
end

local function startTruckTuckSuppression(character: Model, track: AnimationTrack)
	stopTruckTuckSuppression(character)

	truckTuckSuppressionConnections[character] = RunService.PostSimulation:Connect(function()
		if activeTruckTuckTracks[character] ~= track or not character.Parent then
			return
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end

		local animator = getAnimator(humanoid)
		stopRunAnimationTracks(character, false)
		suppressDefaultLocomotion(animator, track)

		local animKey = activeDodgeTypes[character]
		if isJukeAnimKey(animKey) then
			if not track.IsPlaying then
				holdJukePose(character, track)
			end
			return
		end

		if not track.IsPlaying then
			track.Looped = true
			track:Play(0.05, 1, track.Speed)
		end

		local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and Config.RUN_ANIM_REFERENCE_SPEED > 0 then
			local horizontalSpeed = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude
			local playbackSpeed = math.clamp(horizontalSpeed / Config.RUN_ANIM_REFERENCE_SPEED, 0.75, 2)
				* (Config.RUN_ANIM_SPEED_SCALE or 1)
			if horizontalSpeed <= Config.RUN_MOVE_THRESHOLD then
				playbackSpeed = 1
			end
			track:AdjustSpeed(playbackSpeed)
		end
	end)
end

function AnimationUtil.lockLocomotionForTruckTuck(character: Model)
	if RunService:IsServer() then
		return
	end

	if truckTuckLocomotionLocked[character] then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local animate = character:FindFirstChild("Animate")
	if animate and (animate:IsA("LocalScript") or animate:IsA("Script")) then
		animate.Enabled = false
	end

	local function suppressForTruck()
		local currentHumanoid = character:FindFirstChildOfClass("Humanoid")
		if not currentHumanoid then
			return
		end

		local animator = getAnimator(currentHumanoid)
		stopRunAnimationTracks(character, false)
		local keepTrack = findTruckTrack(animator, character)
		suppressDefaultLocomotion(animator, keepTrack)
		if keepTrack and not keepTrack.IsPlaying then
			keepTrack.Looped = true
			keepTrack:Play(0.05, 1, keepTrack.Speed)
		end
	end

	suppressForTruck()

	local suppressionConnection = RunService.PostSimulation:Connect(function()
		if not truckTuckLocomotionLocked[character] or not character.Parent then
			return
		end

		local currentHumanoid = character:FindFirstChildOfClass("Humanoid")
		if currentHumanoid then
			suppressForTruck()
		end
	end)

	truckTuckLocomotionLocked[character] = {
		suppressionConnection = suppressionConnection,
	}
end

function AnimationUtil.unlockLocomotionForTruckTuck(character: Model)
	if RunService:IsServer() then
		return
	end

	local state = truckTuckLocomotionLocked[character]
	if not state then
		return
	end

	truckTuckLocomotionLocked[character] = nil

	if state.suppressionConnection then
		state.suppressionConnection:Disconnect()
	end

	if not activeRunTracks[character] and not activeTruckTuckTracks[character] then
		local animate = character:FindFirstChild("Animate")
		if animate and (animate:IsA("LocalScript") or animate:IsA("Script")) then
			animate.Enabled = true
		end
	end
end

function AnimationUtil.isTackleDivePlaying(character: Model): boolean
	return activeDiveTracks[character] ~= nil
end

function AnimationUtil.stopTackleDive(character: Model)
	local track = activeDiveTracks[character]
	if track then
		track:Stop(0.1)
		activeDiveTracks[character] = nil
	end
end

function AnimationUtil.playTackleDive(character: Model): AnimationTrack?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		warn("TackleBall: no humanoid found for tackle dive animation")
		return nil
	end

	if not isR15Humanoid(humanoid) then
		return nil
	end

	AnimationUtil.stopTackleDive(character)

	local animation = getDiveAnimationInstance()
	local animator = getAnimator(humanoid)

	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	if not ok or not track then
		warn(`TackleBall: failed to load tackle dive animation ({Config.TACKLE_DIVE_ANIMATION})`)
		return nil
	end

	track.Priority = Config.TACKLE_DIVE_ANIM_PRIORITY
	track:Play(0.05, 1, 1)

	activeDiveTracks[character] = track
	suppressDefaultLocomotion(animator, track)

	task.delay(Config.DASH_WINDUP + Config.DASH_DURATION + Config.DASH_STOP_ON_HIT, function()
		if activeDiveTracks[character] == track then
			AnimationUtil.stopTackleDive(character)
		end
	end)

	return track
end

function AnimationUtil.stopKnockback(character: Model)
	local track = activeKnockbackTracks[character]
	if track then
		pcall(function()
			track:AdjustSpeed(1)
		end)
		track:Stop(0.1)
		activeKnockbackTracks[character] = nil
	end
end

function AnimationUtil.playKnockback(character: Model, onFrozen: (() -> ())?): AnimationTrack?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end

	if not isR15Humanoid(humanoid) then
		return nil
	end

	AnimationUtil.stopKnockback(character)

	local animation = getKnockbackAnimationInstance()
	local animator = getAnimator(humanoid)

	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	if not ok or not track then
		warn(`TackleBall: failed to load knockback animation ({Config.TACKLE_KNOCKBACK_ANIMATION})`)
		return nil
	end

	track.Priority = Config.TACKLE_KNOCKBACK_ANIM_PRIORITY
	track:Play(0.05, 1, 1)

	activeKnockbackTracks[character] = track

	local freezeAt = Config.TACKLE_KNOCKBACK_FREEZE_AT
	if track.Length and track.Length > 0 then
		freezeAt = math.max(0, track.Length - 0.02)
	end

	task.delay(freezeAt, function()
		if activeKnockbackTracks[character] ~= track then
			return
		end

		pcall(function()
			track.TimePosition = freezeAt
			track:AdjustSpeed(0)
		end)

		if onFrozen then
			onFrozen()
		end
	end)

	return track
end

function AnimationUtil.stopGetUp(character: Model)
	local track = activeGetUpTracks[character]
	if track then
		track:Stop(0.1)
		activeGetUpTracks[character] = nil
	end
end

function AnimationUtil.playGetUp(character: Model): (AnimationTrack?, number)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil, 1
	end

	if not isR15Humanoid(humanoid) then
		return nil, 1
	end

	AnimationUtil.stopGetUp(character)

	local animation = getGetUpAnimationInstance()
	local animator = getAnimator(humanoid)

	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	if not ok or not track then
		warn(`TackleBall: failed to load get-up animation ({Config.TACKLE_GETUP_ANIMATION})`)
		return nil, 1
	end

	track.Priority = Config.TACKLE_GETUP_ANIM_PRIORITY
	local speed = Config.TACKLE_GETUP_SPEED or 1
	track:Play(0.05, 1, speed)

	activeGetUpTracks[character] = track

	return track, speed
end

function AnimationUtil.stopRunLoop(character: Model, immediate: boolean?)
	stopRunAnimationTracks(character, true, immediate == true)
end

function AnimationUtil.isRunLoopPlaying(character: Model): boolean
	return activeRunTracks[character] ~= nil
end

function AnimationUtil.playRunLoop(character: Model, movementSpeed: number?): AnimationTrack?
	if AnimationUtil.isJumpInProgress(character) then
		return nil
	end

	if AnimationUtil.isTruckTuckActive(character) then
		stopRunAnimationTracks(character, false)
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end

	if humanoid.Jump or isHumanoidAirborne(humanoid, character) then
		return nil
	end

	if not isR15Humanoid(humanoid) then
		return nil
	end

	if not humanoid.EvaluateStateMachine then
		humanoid.EvaluateStateMachine = true
	end

	local playbackSpeed = 1
	if movementSpeed and Config.RUN_ANIM_REFERENCE_SPEED > 0 then
		playbackSpeed = math.clamp(movementSpeed / Config.RUN_ANIM_REFERENCE_SPEED, 0.75, 2)
			* (Config.RUN_ANIM_SPEED_SCALE or 1)
	end

	local animation = getRunAnimationInstance()
	local animator = getAnimator(humanoid)
	local existing = activeRunTracks[character]
	if existing then
		local trackAnimation = existing.Animation
		if trackAnimation ~= animation or trackAnimation.AnimationId ~= Config.RUN_ANIMATION then
			existing:Stop(0.15)
			activeRunTracks[character] = nil
			AnimationUtil.setCarrierAnimateEnabled(character, true)
			existing = nil
		end
	end

	if existing then
		AnimationUtil.setCarrierAnimateEnabled(character, false)
		if not existing.IsPlaying then
			existing.Looped = true
			existing:Play(0.05, 1, playbackSpeed)
		else
			pcall(function()
				existing:AdjustSpeed(playbackSpeed)
			end)
		end
		suppressDefaultLocomotion(animator, existing)
		return existing
	end

	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	if not ok or not track then
		warn(`TackleBall: failed to load run animation ({Config.RUN_ANIMATION})`)
		return nil
	end

	AnimationUtil.setCarrierAnimateEnabled(character, false)
	suppressDefaultLocomotion(animator, track)

	track.Priority = Config.RUN_ANIM_PRIORITY
	track.Looped = true
	track:Play(0.05, 1, playbackSpeed)

	activeRunTracks[character] = track
	return track
end

function AnimationUtil.stopJump(character: Model)
	jumpRequestedCharacters[character] = nil
	jumpAirborneCharacters[character] = nil
	carrierNativeJumpCharacters[character] = nil
	stopCarrierJumpBoost(character)
	stopJumpSuppression(character)

	local track = activeJumpTracks[character]
	if track then
		pcall(function()
			track:AdjustSpeed(1)
		end)
		track:Stop(0.1)
		activeJumpTracks[character] = nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local animator = getAnimator(humanoid)
		for _, playingTrack in animator:GetPlayingAnimationTracks() do
			local anim = playingTrack.Animation
			if anim and anim.AnimationId == Config.JUMP_ANIMATION then
				playingTrack:Stop(0.1)
			end
		end
	end

	local runTrack = activeRunTracks[character]
	if runTrack and not runTrack.IsPlaying then
		activeRunTracks[character] = nil
	end

	if shouldReEnableAnimateAfterJump(character) then
		releaseAnimateAfterJump(character)
	end
end

function AnimationUtil.isJumpPlaying(character: Model): boolean
	return AnimationUtil.isJumpInProgress(character)
end

function AnimationUtil.playJump(character: Model): AnimationTrack?
	if carrierNativeJumpCharacters[character] then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end

	if jumpAirborneCharacters[character] then
		local state = humanoid:GetState()
		if AnimationUtil.isCharacterGrounded(humanoid, character)
			and state ~= Enum.HumanoidStateType.Jumping
			and state ~= Enum.HumanoidStateType.Freefall
		then
			AnimationUtil.stopJump(character)
		else
			return activeJumpTracks[character]
		end
	end

	if AnimationUtil.isTruckTuckActive(character) or AnimationUtil.isTackleDivePlaying(character) then
		return nil
	end

	if activeKnockbackTracks[character] or activeGetUpTracks[character] then
		return nil
	end

	if not isR15Humanoid(humanoid) then
		return nil
	end

	stopRunAnimationTracks(character, false)

	stashAndRemoveAnimate(character)

	local existing = activeJumpTracks[character]
	if existing and existing.IsPlaying then
		return existing
	end

	local animation = getJumpAnimationInstance()
	local animator = getAnimator(humanoid)

	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	if not ok or not track then
		warn(`TackleBall: failed to load jump animation ({Config.JUMP_ANIMATION})`)
		return nil
	end

	track.Priority = Config.JUMP_ANIM_PRIORITY
	track.Looped = false
	track:Play(0, 1, 1)

	activeJumpTracks[character] = track
	stashAndRemoveAnimate(character)
	muteCompetingTracks(animator, track)
	startJumpSuppression(character, track)

	if isHumanoidAirborne(humanoid, character) then
		jumpAirborneCharacters[character] = true
	end

	jumpRequestedCharacters[character] = nil

	return track
end

function AnimationUtil.bindCustomJump(character: Model)
	if RunService:IsServer() then
		return
	end

	if character:GetAttribute("TackleBallJumpBound") then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid
	end
	if not humanoid then
		return
	end

	character:WaitForChild("Animate", 10)
	character:SetAttribute("TackleBallJumpBound", true)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	restoreMobileJumpButton()

	local animator = getAnimator(humanoid)
	if jumpDefaultBlockConnections[character] then
		jumpDefaultBlockConnections[character]:Disconnect()
	end

	jumpDefaultBlockConnections[character] = animator.AnimationPlayed:Connect(function(playedTrack)
		if carrierNativeJumpCharacters[character] then
			return
		end

		if isDefaultAirTrack(playedTrack, activeJumpTracks[character]) then
			playedTrack:Stop(0)
		end

		if jumpAirborneCharacters[character] then
			return
		end

		if AnimationUtil.isTruckTuckActive(character) or AnimationUtil.isTackleDivePlaying(character) then
			return
		end

		local anim = playedTrack.Animation
		if anim and isBlockedDefaultAirAnimation(anim.AnimationId) then
			AnimationUtil.playJump(character)
		end
	end)

	local function finishJumpFromLanding()
		if not activeJumpTracks[character]
			and not jumpAirborneCharacters[character]
			and not jumpRequestedCharacters[character]
			and not carrierNativeJumpCharacters[character]
		then
			return
		end

		if not AnimationUtil.isCharacterGrounded(humanoid, character) then
			return
		end

		restoreMobileJumpButton()
		AnimationUtil.stopJump(character)
	end

	humanoid.StateChanged:Connect(function(_oldState, newState)
		if newState == Enum.HumanoidStateType.Jumping and not carrierNativeJumpCharacters[character] then
			AnimationUtil.playJump(character)
		elseif
			newState == Enum.HumanoidStateType.Landed
			or newState == Enum.HumanoidStateType.Running
			or newState == Enum.HumanoidStateType.None
		then
			task.defer(finishJumpFromLanding)
		end
	end)

	humanoid:GetPropertyChangedSignal("FloorMaterial"):Connect(function()
		if humanoid.FloorMaterial ~= Enum.Material.Air then
			task.defer(finishJumpFromLanding)
		end
	end)

	humanoid:GetPropertyChangedSignal("Jump"):Connect(function()
		if not humanoid.Jump then
			return
		end

		if jumpRequestedCharacters[character]
			or jumpAirborneCharacters[character]
			or carrierNativeJumpCharacters[character]
		then
			return
		end

		if not AnimationUtil.canAcceptJump(humanoid) then
			denyJump(humanoid)
		end
	end)
end

function AnimationUtil.stopDodge(character: Model)
	local track = activeTruckTuckTracks[character]
	if track then
		track:Stop(0.1)
		activeTruckTuckTracks[character] = nil
	end

	stopDodgeFreeze(character)
	jukeFreezeCallbacks[character] = nil
	activeDodgeTypes[character] = nil
	stopTruckTuckSuppression(character)
	if not RunService:IsServer() then
		AnimationUtil.unlockLocomotionForTruckTuck(character)
	end
	AnimationUtil.setCarrierAnimateEnabled(character, true)
end

function AnimationUtil.stopTruckTuck(character: Model)
	AnimationUtil.stopDodge(character)
end

function AnimationUtil.isDodgePlaying(character: Model): boolean
	return activeTruckTuckTracks[character] ~= nil
end

function AnimationUtil.isTruckTuckPlaying(character: Model): boolean
	return AnimationUtil.isDodgePlaying(character)
end

function AnimationUtil.playDodge(
	character: Model,
	dodgeType: string,
	onEnded: (() -> ())?,
	onJukeFreeze: (() -> ())?,
	jukeSide: number?
): AnimationTrack?
	local animKey = resolveDodgeAnimKey(if dodgeType == "Juke" then "Juke" else "Truck", jukeSide)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end

	if not isR15Humanoid(humanoid) then
		return nil
	end

	local existing = activeTruckTuckTracks[character]
	if existing and existing.IsPlaying and activeDodgeTypes[character] == animKey then
		stopRunAnimationTracks(character, false)
		AnimationUtil.setCarrierAnimateEnabled(character, false)
		if isJukeAnimKey(animKey) then
			existing.Looped = false
			startJukeFreezeMonitor(character, existing)
		else
			existing.Looped = true
		end
		startTruckTuckSuppression(character, existing)
		return existing
	end

	AnimationUtil.stopDodge(character)
	stopRunAnimationTracks(character, false)

	local animation = getDodgeAnimationInstance(animKey)
	if not animation then
		if onEnded then
			task.delay(Config.SHED_ANIM_DURATION, onEnded)
		end
		return nil
	end

	local animator = getAnimator(humanoid)

	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	if not ok or not track then
		warn(`TackleBall: failed to load dodge animation ({animKey}: {Config.DODGE_ANIMATIONS[animKey]})`)
		if onEnded then
			task.delay(Config.SHED_ANIM_DURATION, onEnded)
		end
		return nil
	end

	AnimationUtil.setCarrierAnimateEnabled(character, false)
	suppressDefaultLocomotion(animator, track)

	track.Priority = Config.TRUCK_TUCK_ANIM_PRIORITY
	track.Looped = not isJukeAnimKey(animKey)
	track:Play(0.05, 1, 1)

	activeTruckTuckTracks[character] = track
	activeDodgeTypes[character] = animKey
	startTruckTuckSuppression(character, track)

	if isJukeAnimKey(animKey) then
		if onJukeFreeze then
			jukeFreezeCallbacks[character] = onJukeFreeze
		end
		startJukeFreezeMonitor(character, track)
	end

	local duration = Config.SHED_ANIM_DURATION
	if isJukeAnimKey(animKey) and track.Length and track.Length > 0 then
		duration = track.Length
	elseif track.Length and track.Length > 0 then
		duration = track.Length
	end

	if onEnded then
		task.delay(duration, function()
			if activeTruckTuckTracks[character] == track then
				onEnded()
			end
		end)
	end

	track.Stopped:Once(function()
		if activeTruckTuckTracks[character] ~= track then
			return
		end

		if isJukeAnimKey(animKey)
			and (
				character:GetAttribute("TruckTuckWindowActive") == true
				or character:GetAttribute("TruckTuckActive") == true
			)
		then
			track:Play(0.05, 1, 1)
			holdJukePose(character, track)
			return
		end

		activeTruckTuckTracks[character] = nil
		activeDodgeTypes[character] = nil
		stopDodgeFreeze(character)
		jukeFreezeCallbacks[character] = nil
		if not AnimationUtil.isTruckTuckActive(character) then
			AnimationUtil.setCarrierAnimateEnabled(character, true)
		end
	end)

	return track
end

function AnimationUtil.stopPassThrow(character: Model)
	local track = activePassThrowTracks[character]
	if track then
		track:Stop(0.1)
		activePassThrowTracks[character] = nil
	end
end

function AnimationUtil.playPassThrow(character: Model): AnimationTrack?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end

	if not isR15Humanoid(humanoid) then
		return nil
	end

	AnimationUtil.stopPassThrow(character)

	local animation = getPassThrowAnimationInstance()
	local animator = getAnimator(humanoid)

	local ok, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	if not ok or not track then
		warn(`TackleBall: failed to load pass throw animation ({Config.PASS_THROW_ANIMATION})`)
		return nil
	end

	track.Priority = Config.PASS_THROW_ANIM_PRIORITY
	track:Play(0.05, 1, 1)
	activePassThrowTracks[character] = track

	track.Stopped:Once(function()
		if activePassThrowTracks[character] == track then
			activePassThrowTracks[character] = nil
		end
	end)

	return track
end

function AnimationUtil.playTruckTuck(character: Model, onEnded: (() -> ())?): AnimationTrack?
	return AnimationUtil.playDodge(character, "Truck", onEnded)
end

return AnimationUtil
