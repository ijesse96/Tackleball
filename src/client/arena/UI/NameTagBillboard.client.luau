local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

type TrackedEntry = {
	billboard: BillboardGui,
	label: TextLabel,
	ancestryConnection: RBXScriptConnection?,
	displayNameConnection: RBXScriptConnection?,
}

local tracked: { [Model]: TrackedEntry } = {}
local celebrationActive = false

local function refreshCelebrationNameTags()
	if celebrationActive then
		for _, entry in tracked do
			entry.billboard.Enabled = false
		end
		return
	end

	for _, entry in tracked do
		entry.billboard.Enabled = true
	end
end

local function getAdornee(character: Model): BasePart?
	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end

	return nil
end

local function getDisplayName(character: Model, humanoid: Humanoid): string
	local player = Players:GetPlayerFromCharacter(character)
	if player then
		return player.DisplayName
	end

	if humanoid.DisplayName ~= "" then
		return humanoid.DisplayName
	end

	return character.Name
end

local function getNameColor(character: Model): Color3
	local team = character:GetAttribute("TackleBallTeam")
	if team == Config.TEAM_A_NAME then
		return Config.TEAM_A_COLOR
	end
	if team == Config.TEAM_B_NAME then
		return Config.TEAM_B_COLOR
	end

	return Color3.fromRGB(255, 255, 255)
end

local function updateLabel(entry: TrackedEntry, character: Model, humanoid: Humanoid)
	entry.label.Text = getDisplayName(character, humanoid)
	entry.label.TextColor3 = getNameColor(character)
end

local function createBillboardGui(adornee: BasePart, displayName: string, textColor: Color3): (BillboardGui, TextLabel)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "NameTagBillboard"
	billboard.Adornee = adornee
	billboard.AlwaysOnTop = true
	billboard.Size = UDim2.fromOffset(140, Config.NAME_TAG_HEIGHT_PX)
	billboard.StudsOffset = Config.NAME_TAG_STUDS_OFFSET
	billboard.LightInfluence = 0

	local label = Instance.new("TextLabel")
	label.Name = "Name"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.Text = displayName
	label.TextColor3 = textColor
	label.TextScaled = true
	label.TextStrokeColor3 = Color3.fromRGB(15, 15, 15)
	label.TextStrokeTransparency = 0.35
	label.Parent = billboard

	local textConstraint = Instance.new("UITextSizeConstraint")
	textConstraint.MaxTextSize = 18
	textConstraint.MinTextSize = 10
	textConstraint.Parent = label

	return billboard, label
end

local function untrackCharacter(character: Model)
	local entry = tracked[character]
	if not entry then
		return
	end

	if entry.ancestryConnection then
		entry.ancestryConnection:Disconnect()
	end
	if entry.displayNameConnection then
		entry.displayNameConnection:Disconnect()
	end
	if entry.billboard then
		entry.billboard:Destroy()
	end

	tracked[character] = nil
end

local function trackCharacter(character: Model)
	if tracked[character] or not character.Parent then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	local adornee = getAdornee(character)
	if not adornee then
		return
	end

	local displayName = getDisplayName(character, humanoid)
	local billboard, label = createBillboardGui(adornee, displayName, getNameColor(character))
	billboard.Parent = character

	local entry: TrackedEntry = {
		billboard = billboard,
		label = label,
	}

	tracked[character] = entry

	if celebrationActive then
		billboard.Enabled = false
	end

	entry.displayNameConnection = humanoid:GetPropertyChangedSignal("DisplayName"):Connect(function()
		if tracked[character] then
			updateLabel(entry, character, humanoid)
		end
	end)

	character:GetAttributeChangedSignal("TackleBallTeam"):Connect(function()
		if tracked[character] then
			updateLabel(entry, character, humanoid)
		end
	end)

	entry.ancestryConnection = character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			untrackCharacter(character)
		end
	end)
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

Workspace.ChildAdded:Connect(function(child)
	tryTrackModel(child)
end)

for _, player in Players:GetPlayers() do
	if player.Character then
		trackCharacter(player.Character)
	end
	player.CharacterAdded:Connect(trackCharacter)
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(trackCharacter)
end)

Remotes.scoreCelebrationStarted().OnClientEvent:Connect(function()
	celebrationActive = true
	refreshCelebrationNameTags()
end)

Remotes.roundStateChanged().OnClientEvent:Connect(function(payload)
	if payload.state == "Active" or payload.state == "Waiting" then
		celebrationActive = false
		refreshCelebrationNameTags()
	end
end)
