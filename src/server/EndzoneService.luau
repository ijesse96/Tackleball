local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local GameMode = require(ReplicatedStorage.Shared.GameMode)

type EndzoneZone = BasePart | Model

local EndzoneService = {}
EndzoneService._matchService = nil
EndzoneService._ballService = nil
EndzoneService._connections = {} :: { RBXScriptConnection }
EndzoneService._endzones = {} :: { [string]: EndzoneZone }
EndzoneService._boundTouchEndzones = {} :: { [string]: boolean }

local SCORING_BOUNDS_PADDING = 3
local CHARACTER_SCORE_PARTS = { "HumanoidRootPart", "LowerTorso", "UpperTorso", "Head" }

local TEAM_GOAL_COLORS = {
	BlueGoal = Config.TEAM_A_COLOR,
	GreenGoal = Config.TEAM_B_COLOR,
}

local ENDZONE_BANK_FACES = {
	EndzoneA = Enum.NormalId.Right,
	EndzoneB = Enum.NormalId.Left,
	GreenGoal = Enum.NormalId.Front,
	BlueGoal = Enum.NormalId.Front,
}

local function isCharacterPart(part: BasePart): Model?
	local model = part:FindFirstAncestorOfClass("Model")
	if not model then
		return nil
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end

	return model
end

local function getZoneBounds(zone: EndzoneZone): (CFrame, Vector3)
	if zone:IsA("BasePart") then
		return zone.CFrame, zone.Size
	end

	return zone:GetBoundingBox()
end

local function isPointInEndzone(point: Vector3, endzone: EndzoneZone, padding: number?): boolean
	local zoneCFrame, zoneSize = getZoneBounds(endzone)
	local localPoint = zoneCFrame:PointToObjectSpace(point)
	local pad = padding or 0
	local half = zoneSize * 0.5 + Vector3.new(pad, pad, pad)
	return math.abs(localPoint.X) <= half.X
		and math.abs(localPoint.Y) <= half.Y
		and math.abs(localPoint.Z) <= half.Z
end

local function isCharacterInEndzone(character: Model, endzone: EndzoneZone, padding: number?): boolean
	for _, partName in CHARACTER_SCORE_PARTS do
		local part = character:FindFirstChild(partName) :: BasePart?
		if part and isPointInEndzone(part.Position, endzone, padding) then
			return true
		end
	end

	return false
end

local function getLabelPart(endzone: EndzoneZone): BasePart?
	if endzone:IsA("BasePart") then
		return endzone
	end

	if endzone.PrimaryPart then
		return endzone.PrimaryPart
	end

	local largestPart: BasePart? = nil
	local largestVolume = 0
	for _, descendant in endzone:GetDescendants() do
		if descendant:IsA("BasePart") then
			local volume = descendant.Size.X * descendant.Size.Y * descendant.Size.Z
			if volume > largestVolume then
				largestVolume = volume
				largestPart = descendant
			end
		end
	end

	return largestPart
end

local function createBankLabel(labelPart: BasePart, endzoneName: string)
	local existing = labelPart:FindFirstChild("BankLabel")
	if existing then
		return
	end

	local face = ENDZONE_BANK_FACES[endzoneName] or Enum.NormalId.Front

	local gui = Instance.new("SurfaceGui")
	gui.Name = "BankLabel"
	gui.Face = face
	gui.LightInfluence = 0
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.AlwaysOnTop = false
	gui.Parent = labelPart

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(0.9, 0.85)
	label.BackgroundTransparency = 1
	label.Text = "BANK"
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.Parent = gui

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(0, 0, 0)
	stroke.Thickness = 2
	stroke.Parent = label
end

local function findScoringPart(endzone: Model, endzoneName: string): BasePart?
	local configuredName = Config.GOAL_SCORING_PART_NAMES[endzoneName]
	if configuredName then
		local part = endzone:FindFirstChild(configuredName, true)
		if part and part:IsA("BasePart") then
			return part
		end
	end

	local genericGoalPart = endzone:FindFirstChild("GoalPart", true)
	if genericGoalPart and genericGoalPart:IsA("BasePart") then
		return genericGoalPart
	end

	for _, descendant in endzone:GetDescendants() do
		if descendant:IsA("BasePart") and string.find(descendant.Name, "GoalPart", 1, true) then
			return descendant
		end
	end

	return nil
end

local function prepareGoalPart(goalPart: BasePart)
	goalPart.CanTouch = true
	goalPart.CanCollide = false
	goalPart.CanQuery = true
end

local function applyTeamGoalColor(endzone: EndzoneZone, endzoneName: string)
	if not GameMode.isTeamsMode() then
		return
	end

	local color = TEAM_GOAL_COLORS[endzoneName]
	if not color then
		return
	end

	if endzone:IsA("BasePart") then
		endzone.Color = color
		return
	end

	for _, descendant in endzone:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Color = color
		end
	end
end

local function prepareEndzone(endzone: EndzoneZone, endzoneName: string)
	if endzone:IsA("BasePart") then
		endzone.Anchored = true
		endzone.CanCollide = false
		endzone.CanTouch = true
		endzone.CanQuery = true
		applyTeamGoalColor(endzone, endzoneName)
		createBankLabel(endzone, endzoneName)
		return
	end

	for _, descendant in endzone:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanTouch = true
			descendant.CanQuery = true
		end
	end

	applyTeamGoalColor(endzone, endzoneName)

	local labelPart = getLabelPart(endzone)
	if labelPart then
		createBankLabel(labelPart, endzoneName)
	end
end

function EndzoneService:init(matchService, ballService)
	self._matchService = matchService
	self._ballService = ballService

	if GameMode.usesStadiumLayout() then
		task.spawn(function()
			self:_waitForGoalsAndBind()
		end)
	else
		self:_bindEndzones()
	end

	table.insert(
		self._connections,
		RunService.Heartbeat:Connect(function()
			self:_checkScoringOverlaps()
		end)
	)
end

function EndzoneService:_waitForGoalsAndBind()
	local deadline = os.clock() + 30

	while os.clock() < deadline do
		local allFound = true
		for _, endzoneName in GameMode.getEndzoneNames() do
			if not self:_findEndzone(endzoneName) then
				allFound = false
				break
			end
		end

		if allFound then
			break
		end

		task.wait(0.25)
	end

	self:_bindEndzones()

	if next(self._endzones) == nil then
		self:_watchForLateGoals()
	end
end

function EndzoneService:_watchForLateGoals()
	local goalNames = GameMode.getEndzoneNames()
	local goalNameSet = {}
	for _, name in goalNames do
		goalNameSet[name] = true
	end

	local connection = Workspace.DescendantAdded:Connect(function(descendant)
		if not goalNameSet[descendant.Name] then
			return
		end
		if not (descendant:IsA("BasePart") or descendant:IsA("Model")) then
			return
		end

		local missing = false
		for _, endzoneName in goalNames do
			if not self._endzones[endzoneName] then
				missing = true
				break
			end
		end

		if missing then
			self:_bindEndzones()
		end
	end)

	table.insert(self._connections, connection)
end

function EndzoneService:_findEndzone(endzoneName: string): EndzoneZone?
	if not GameMode.usesStadiumLayout() then
		local field = Workspace:FindFirstChild(Config.FIELD_FOLDER_NAME)
		if field then
			local endzone = field:FindFirstChild(endzoneName)
			if endzone and endzone:IsA("BasePart") then
				return endzone
			end
		end
	end

	for _, descendant in Workspace:GetDescendants() do
		if descendant.Name == endzoneName and (descendant:IsA("BasePart") or descendant:IsA("Model")) then
			return descendant
		end
	end

	return nil
end

function EndzoneService:_bindEndzoneTouches(endzone: EndzoneZone, endzoneName: string)
	if self._boundTouchEndzones[endzoneName] then
		return
	end

	self._boundTouchEndzones[endzoneName] = true

	local function bindPart(part: BasePart)
		local connection = part.Touched:Connect(function(hit)
			self:_onEndzoneTouched(hit, endzoneName)
		end)
		table.insert(self._connections, connection)
	end

	if endzone:IsA("BasePart") then
		bindPart(endzone)
		return
	end

	for _, descendant in endzone:GetDescendants() do
		if descendant:IsA("BasePart") then
			bindPart(descendant)
		end
	end
end

function EndzoneService:_bindEndzones()
	if not GameMode.usesStadiumLayout() then
		local field = Workspace:WaitForChild(Config.FIELD_FOLDER_NAME, 10)
		if not field then
			warn(`EndzoneService: "{Config.FIELD_FOLDER_NAME}" folder not found; searching workspace`)
		end
	end

	for _, endzoneName in GameMode.getEndzoneNames() do
		if self._endzones[endzoneName] then
			continue
		end

		local endzone = self:_findEndzone(endzoneName)
		if not endzone then
			warn(`EndzoneService: endzone "{endzoneName}" not found`)
			continue
		end

		prepareEndzone(endzone, endzoneName)
		self._endzones[endzoneName] = endzone

		if endzone:IsA("Model") then
			local goalPart = findScoringPart(endzone, endzoneName)
			if goalPart then
				prepareGoalPart(goalPart)
			elseif Config.GOAL_SCORING_PART_NAMES[endzoneName] then
				warn(`EndzoneService: scoring part for "{endzoneName}" not found; using full goal volume`)
			end
		end

		self:_bindEndzoneTouches(endzone, endzoneName)
	end
end

function EndzoneService:_tryScore(carrierCharacter: Model, endzoneName: string)
	if not self._matchService:isActive() then
		return
	end

	local activeCarrier = self._matchService:getCarrierCharacter()
	if not activeCarrier or activeCarrier ~= carrierCharacter then
		return
	end

	if GameMode.isTeamsMode() then
		local teamService = self._matchService:getTeamService()
		if not teamService then
			return
		end

		local carrierTeam = teamService:getTeam(carrierCharacter)
		if not carrierTeam then
			return
		end

		local goalEndzone = teamService:getGoalEndzone(carrierTeam)
		if endzoneName ~= goalEndzone then
			return
		end

		local scoringPlayer = Players:GetPlayerFromCharacter(carrierCharacter)
		self._matchService:scoreTeamCarrier(carrierCharacter, carrierTeam, scoringPlayer)
		return
	end

	local scoringPlayer = Players:GetPlayerFromCharacter(carrierCharacter)
	if scoringPlayer then
		self._matchService:score(scoringPlayer)
	else
		self._matchService:scoreNpcCarrier(carrierCharacter)
	end
end

function EndzoneService:_isInScoringZone(endzone: EndzoneZone, carrierCharacter: Model): boolean
	local ball = self._ballService:getBall()
	if ball and isPointInEndzone(ball.Position, endzone, SCORING_BOUNDS_PADDING) then
		return true
	end

	return isCharacterInEndzone(carrierCharacter, endzone, SCORING_BOUNDS_PADDING)
end

function EndzoneService:_checkScoringOverlaps()
	local carrierCharacter = self._matchService:getCarrierCharacter()
	if not carrierCharacter then
		return
	end

	for endzoneName, endzone in self._endzones do
		if self:_isInScoringZone(endzone, carrierCharacter) then
			self:_tryScore(carrierCharacter, endzoneName)
			return
		end
	end
end

function EndzoneService:_onEndzoneTouched(hit: BasePart, endzoneName: string)
	local carrierCharacter = self._matchService:getCarrierCharacter()
	if not carrierCharacter then
		return
	end

	if self._ballService:isBallPart(hit) then
		self:_tryScore(carrierCharacter, endzoneName)
		return
	end

	local character = isCharacterPart(hit)
	if character and character == carrierCharacter then
		self:_tryScore(carrierCharacter, endzoneName)
	end
end

return EndzoneService
