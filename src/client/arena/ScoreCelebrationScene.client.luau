local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local CelebrationScorerResolve = require(script.Parent.CelebrationScorerResolve)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local defaultFov = if camera then camera.FieldOfView else 70

local CELEBRATION_RENDER_STEP = "TackleBallCelebrationCamera"

local sceneToken = 0
local celebrationRenderBound = false
local activeCelebrationPayload: Types.CelebrationScenePayload? = nil
local hiddenPartModifiers = {} :: { [BasePart]: number }

local function smoothstep(t: number): number
	return t * t * (3 - 2 * t)
end

local function resolveScorerModel(payload: Types.CelebrationScenePayload): Model?
	return CelebrationScorerResolve.resolveFromPayload(payload)
end

local function setModelHidden(model: Model, hidden: boolean)
	for _, descendant in model:GetDescendants() do
		if not descendant:IsA("BasePart") then
			continue
		end

		if hidden then
			if hiddenPartModifiers[descendant] == nil then
				hiddenPartModifiers[descendant] = descendant.LocalTransparencyModifier
			end
			descendant.LocalTransparencyModifier = 1
		elseif hiddenPartModifiers[descendant] ~= nil then
			descendant.LocalTransparencyModifier = hiddenPartModifiers[descendant]
			hiddenPartModifiers[descendant] = nil
		end
	end
end

local function hideNonScorerCharacters(scorerModel: Model?)
	for _, otherPlayer in Players:GetPlayers() do
		local character = otherPlayer.Character
		if character and character ~= scorerModel then
			setModelHidden(character, true)
		end
	end

	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("Model") and descendant ~= scorerModel and descendant:GetAttribute("TackleBallDummy") == true then
			setModelHidden(descendant, true)
		end
	end
end

local function restoreHiddenCharacters()
	for part, modifier in hiddenPartModifiers do
		if part.Parent then
			part.LocalTransparencyModifier = modifier
		end
	end

	table.clear(hiddenPartModifiers)
end

local function getCharacterFlatLook(scorerModel: Model?): Vector3
	if scorerModel then
		local root = scorerModel:FindFirstChild("HumanoidRootPart")
		if root then
			local flatLook = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
			if flatLook.Magnitude > 0.01 then
				return flatLook.Unit
			end
		end
	end

	return Vector3.new(0, 0, 1)
end

local function computeZoomCFrame(focusPos: Vector3, flatLook: Vector3, distance: number): CFrame
	local camPos = focusPos + flatLook * distance + Vector3.new(0, Config.SCORE_CELEBRATION_CAMERA_HEIGHT, 0)
	return CFrame.lookAt(camPos, focusPos + Vector3.new(0, 2, 0))
end

local function unbindCelebrationRender()
	if celebrationRenderBound then
		RunService:UnbindFromRenderStep(CELEBRATION_RENDER_STEP)
		celebrationRenderBound = false
	end
end

local function releaseCelebrationCamera()
	unbindCelebrationRender()
	activeCelebrationPayload = nil
	restoreHiddenCharacters()

	if not camera then
		return
	end

	camera.CameraType = Enum.CameraType.Custom

	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
	end

	camera.FieldOfView = defaultFov
end

local function playScene(payload: Types.CelebrationScenePayload)
	sceneToken += 1
	local token = sceneToken
	unbindCelebrationRender()
	restoreHiddenCharacters()

	activeCelebrationPayload = payload

	if not camera then
		return
	end

	local scorerModel = resolveScorerModel(payload)
	local lockedFocus = payload.focusPosition
	local lockedFlatLook = getCharacterFlatLook(scorerModel)
	local startDistance = Config.SCORE_CELEBRATION_CAMERA_DISTANCE
	local closeDistance = Config.SCORE_CELEBRATION_CAMERA_CLOSE_DISTANCE
	local cinematicFov = Config.SCORE_CELEBRATION_FOV
	local zoomEnd = Config.SCORE_CELEBRATION_ZOOM_DURATION

	local startCFrame = computeZoomCFrame(lockedFocus, lockedFlatLook, startDistance)
	local endCFrame = computeZoomCFrame(lockedFocus, lockedFlatLook, closeDistance)
	local startTime = os.clock()

	hideNonScorerCharacters(scorerModel)

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CameraSubject = nil
	camera.CFrame = startCFrame
	camera.FieldOfView = cinematicFov

	RunService:BindToRenderStep(CELEBRATION_RENDER_STEP, Enum.RenderPriority.Camera.Value + 50, function()
		if token ~= sceneToken or not activeCelebrationPayload or not camera then
			return
		end

		camera.CameraType = Enum.CameraType.Scriptable
		camera.CameraSubject = nil
		camera.FieldOfView = cinematicFov

		local elapsed = os.clock() - startTime
		local zoomT = smoothstep(math.clamp(elapsed / zoomEnd, 0, 1))
		camera.CFrame = startCFrame:Lerp(endCFrame, zoomT)
	end)
	celebrationRenderBound = true
end

Remotes.scoreCelebrationStarted().OnClientEvent:Connect(function(payload: Types.CelebrationScenePayload)
	playScene(payload)
end)

Remotes.roundStateChanged().OnClientEvent:Connect(function(payload: Types.RoundStatePayload)
	if payload.state == "Active" or payload.state == "Waiting" then
		sceneToken += 1
		releaseCelebrationCamera()
	end
end)
