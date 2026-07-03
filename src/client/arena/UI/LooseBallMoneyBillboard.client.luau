local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)

local CARRY_MONEY_ATTRIBUTE = "CarryMoney"
local IS_LOOSE_ATTRIBUTE = "IsLoose"
local BALL_NAME = "GameBall"

local activeBillboard: BillboardGui? = nil
local billboardConnections: { RBXScriptConnection } = {}
local looseWatchConnection: RBXScriptConnection? = nil
local trackedBallRoot: BasePart? = nil

local function formatMoney(amount: number): string
	return `$` .. tostring(amount)
end

local function disconnectBillboardConnections()
	for _, connection in billboardConnections do
		connection:Disconnect()
	end
	table.clear(billboardConnections)
end

local function hideBillboard()
	disconnectBillboardConnections()

	if activeBillboard then
		activeBillboard:Destroy()
		activeBillboard = nil
	end
end

local function getBallRoot(ball: Instance): BasePart?
	if ball:IsA("BasePart") then
		return ball
	end

	if ball:IsA("Model") then
		if ball.PrimaryPart and ball.PrimaryPart:IsA("BasePart") then
			return ball.PrimaryPart
		end

		local meshPart = ball:FindFirstChildWhichIsA("MeshPart", true)
		if meshPart then
			return meshPart
		end

		return ball:FindFirstChildWhichIsA("BasePart", true)
	end

	return nil
end

local function createBillboardGui(adornee: BasePart): BillboardGui
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "LooseBallMoneyBillboard"
	billboard.Adornee = adornee
	billboard.AlwaysOnTop = true
	billboard.Size = UDim2.fromOffset(120, 36)
	billboard.StudsOffset = Config.BALL_LOOSE_MONEY_STUDS_OFFSET
	billboard.LightInfluence = 0

	local label = Instance.new("TextLabel")
	label.Name = "Amount"
	label.BackgroundTransparency = 0.35
	label.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.fromRGB(255, 220, 60)
	label.TextSize = 22
	label.Text = "$0"
	label.Size = UDim2.fromScale(1, 1)
	label.Parent = billboard

	return billboard
end

local function updateLabelAmount(amount: number)
	if not activeBillboard then
		return
	end

	local label = activeBillboard:FindFirstChild("Amount")
	if label and label:IsA("TextLabel") then
		label.Text = formatMoney(amount)
	end
end

local function syncAmount(ballRoot: BasePart)
	local amount = ballRoot:GetAttribute(CARRY_MONEY_ATTRIBUTE)
	updateLabelAmount(if typeof(amount) == "number" then amount else 0)
end

local function showBillboard(ballRoot: BasePart)
	if trackedBallRoot == ballRoot and activeBillboard then
		syncAmount(ballRoot)
		return
	end

	hideBillboard()
	trackedBallRoot = ballRoot

	local billboard = createBillboardGui(ballRoot)
	billboard.Parent = if ballRoot.Parent then ballRoot.Parent else ballRoot
	activeBillboard = billboard

	syncAmount(ballRoot)

	table.insert(
		billboardConnections,
		ballRoot:GetAttributeChangedSignal(CARRY_MONEY_ATTRIBUTE):Connect(function()
			syncAmount(ballRoot)
		end)
	)
end

local function watchBallRoot(ballRoot: BasePart)
	if looseWatchConnection then
		looseWatchConnection:Disconnect()
		looseWatchConnection = nil
	end

	local function refreshLooseState()
		if ballRoot:GetAttribute(IS_LOOSE_ATTRIBUTE) == true then
			showBillboard(ballRoot)
		else
			hideBillboard()
		end
	end

	refreshLooseState()

	looseWatchConnection = ballRoot:GetAttributeChangedSignal(IS_LOOSE_ATTRIBUTE):Connect(refreshLooseState)
end

local function trackBall(ball: Instance)
	local ballRoot = getBallRoot(ball)
	if not ballRoot then
		return
	end

	watchBallRoot(ballRoot)
end

local function tryTrackBallInstance(ball: Instance)
	if ball.Name ~= BALL_NAME then
		return
	end

	trackBall(ball)
end

for _, child in Workspace:GetChildren() do
	tryTrackBallInstance(child)
end

Workspace.ChildAdded:Connect(function(child)
	tryTrackBallInstance(child)
end)
