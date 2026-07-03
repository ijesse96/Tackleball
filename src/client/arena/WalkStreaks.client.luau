local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local player = Players.LocalPlayer

local STREAK_LINES = {
	{ offset = Vector3.new(-0.5, 0.1, 0.75), span = 0.35 },
	{ offset = Vector3.new(0, 0.2, 0.85), span = 0.4 },
	{ offset = Vector3.new(0.5, 0, 0.75), span = 0.35 },
}

local WATCHED_ATTRIBUTES = {
	"TackleBallRagdollActive",
	"TackleBallCelebrationLocked",
	"TackleBallDead",
}

type StreakEntry = {
	trails: { Trail },
	visible: boolean,
	connections: { RBXScriptConnection },
}

local tracked = {} :: { [Model]: StreakEntry }
local tacklingUserIds = {} :: { [number]: boolean }
local pendingChargeClear = {} :: { [number]: {} }
local lastLocalTestRole: string? = nil

local function isBlocked(character: Model): boolean
	if character:GetAttribute("TackleBallCelebrationLocked") == true then
		return true
	end

	if character:GetAttribute("TackleBallDead") == true then
		return true
	end

	return false
end

local function isPlayerTackling(character: Model): boolean
	local listedPlayer = Players:GetPlayerFromCharacter(character)
	return listedPlayer ~= nil and tacklingUserIds[listedPlayer.UserId] == true
end

local function shouldShowStreaks(character: Model): boolean
	if isBlocked(character) then
		return false
	end

	if character:GetAttribute("TackleBallRagdollActive") == true then
		return true
	end

	return isPlayerTackling(character)
end

local function getStreakAdornee(character: Model): BasePart?
	return character:FindFirstChild("LowerTorso") :: BasePart?
		or character:FindFirstChild("UpperTorso") :: BasePart?
		or character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function createDashedTrail(root: BasePart, offset: Vector3, span: number): Trail
	local attachment0 = Instance.new("Attachment")
	attachment0.Name = "WalkStreak0"
	attachment0.Position = offset
	attachment0.Parent = root

	local attachment1 = Instance.new("Attachment")
	attachment1.Name = "WalkStreak1"
	attachment1.Position = offset + Vector3.new(0, 0, span)
	attachment1.Parent = root

	local trail = Instance.new("Trail")
	trail.Name = "WalkStreak"
	trail.Attachment0 = attachment0
	trail.Attachment1 = attachment1
	trail.Lifetime = Config.WALK_STREAK_TRAIL_LIFETIME
	trail.MinLength = Config.WALK_STREAK_TRAIL_MIN_LENGTH
	trail.FaceCamera = true
	trail.LightEmission = 1
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(235, 245, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 215, 255)),
	})
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, Config.WALK_STREAK_TRAIL_WIDTH),
		NumberSequenceKeypoint.new(1, 0.05),
	})
	trail.Enabled = false
	trail.Parent = root

	return trail
end

local function setEntryVisible(entry: StreakEntry, visible: boolean)
	if entry.visible == visible then
		return
	end

	entry.visible = visible
	for _, trail in entry.trails do
		trail.Enabled = visible
	end
end

local function refreshStreakState(character: Model)
	local entry = tracked[character]
	if not entry then
		return
	end

	setEntryVisible(entry, shouldShowStreaks(character))
end

local function refreshPlayerStreaks(listedPlayer: Player)
	local character = listedPlayer.Character
	if character then
		refreshStreakState(character)
	end
end

local function clearTacklingState(userId: number)
	tacklingUserIds[userId] = nil
	pendingChargeClear[userId] = nil
end

local function setPlayerTackling(listedPlayer: Player)
	tacklingUserIds[listedPlayer.UserId] = true
	refreshPlayerStreaks(listedPlayer)
end

local function setPlayerNotTackling(listedPlayer: Player)
	clearTacklingState(listedPlayer.UserId)
	refreshPlayerStreaks(listedPlayer)
end

local function scheduleChargeFallbackClear(listedPlayer: Player)
	local userId = listedPlayer.UserId
	local token = {}
	pendingChargeClear[userId] = token

	task.delay(Config.CHARGE_MAX_TIME + 0.25, function()
		if pendingChargeClear[userId] ~= token then
			return
		end

		pendingChargeClear[userId] = nil
		if tacklingUserIds[userId] then
			tacklingUserIds[userId] = nil
			refreshPlayerStreaks(listedPlayer)
		end
	end)
end

local function createStreakTrails(root: BasePart): { Trail }
	local trails = {}

	for index, line in STREAK_LINES do
		local trail = createDashedTrail(root, line.offset, line.span)
		trail.Name = `WalkStreak{index}`
		table.insert(trails, trail)
	end

	return trails
end

local function disconnectEntry(entry: StreakEntry)
	for _, connection in entry.connections do
		connection:Disconnect()
	end

	table.clear(entry.connections)
end

local function untrackCharacter(character: Model)
	local entry = tracked[character]
	if not entry then
		return
	end

	disconnectEntry(entry)

	for _, trail in entry.trails do
		local attachment0 = trail.Attachment0
		local attachment1 = trail.Attachment1
		trail:Destroy()
		if attachment0 then
			attachment0:Destroy()
		end
		if attachment1 then
			attachment1:Destroy()
		end
	end

	tracked[character] = nil
end

local function trackCharacter(character: Model)
	if tracked[character] or not character.Parent then
		return
	end

	if not character:FindFirstChildOfClass("Humanoid") then
		return
	end

	local adornee = getStreakAdornee(character)
	if not adornee then
		return
	end

	local entry: StreakEntry = {
		trails = createStreakTrails(adornee),
		visible = false,
		connections = {},
	}
	tracked[character] = entry

	for _, attributeName in WATCHED_ATTRIBUTES do
		table.insert(
			entry.connections,
			character:GetAttributeChangedSignal(attributeName):Connect(function()
				refreshStreakState(character)
			end)
		)
	end

	table.insert(
		entry.connections,
		character.AncestryChanged:Connect(function(_, parent)
			if not parent then
				untrackCharacter(character)
			end
		end)
	)

	refreshStreakState(character)
end

local function resetCharacterStreaks(character: Model?)
	if not character then
		return
	end

	untrackCharacter(character)
	trackCharacter(character)
end

local function tryTrackModel(model: Instance)
	if not model:IsA("Model") then
		return
	end

	if model:FindFirstChildOfClass("Humanoid") then
		trackCharacter(model)
		return
	end

	local connection: RBXScriptConnection?
	connection = model.ChildAdded:Connect(function(child)
		if child:IsA("Humanoid") then
			if connection then
				connection:Disconnect()
			end
			trackCharacter(model)
		end
	end)
end

for _, child in Workspace:GetChildren() do
	tryTrackModel(child)
end

Workspace.ChildAdded:Connect(tryTrackModel)

for _, listedPlayer in Players:GetPlayers() do
	if listedPlayer.Character then
		trackCharacter(listedPlayer.Character)
	end
	listedPlayer.CharacterAdded:Connect(function(character)
		trackCharacter(character)
		refreshStreakState(character)
	end)
end

Players.PlayerAdded:Connect(function(listedPlayer)
	listedPlayer.CharacterAdded:Connect(function(character)
		trackCharacter(character)
		refreshStreakState(character)
	end)
end)

Players.PlayerRemoving:Connect(function(listedPlayer)
	clearTacklingState(listedPlayer.UserId)
end)

player.CharacterAdded:Connect(function(character)
	resetCharacterStreaks(character)
end)

Remotes.tackleChargeStarted().OnClientEvent:Connect(function(tackler: Player)
	setPlayerTackling(tackler)
	scheduleChargeFallbackClear(tackler)
end)

Remotes.tackleDashStarted().OnClientEvent:Connect(function(tackler: Player)
	pendingChargeClear[tackler.UserId] = nil
	setPlayerTackling(tackler)
end)

Remotes.tackleDashEnded().OnClientEvent:Connect(function(tackler: Player)
	setPlayerNotTackling(tackler)
end)

Remotes.roundStateChanged().OnClientEvent:Connect(function(payload: Types.RoundStatePayload)
	if payload.soloTestRole and payload.soloTestRole ~= lastLocalTestRole then
		lastLocalTestRole = payload.soloTestRole
		task.defer(function()
			resetCharacterStreaks(player.Character)
		end)
	end
end)
