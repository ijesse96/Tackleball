local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage.Shared.Config)
local CelebrationScorerResolve = require(script.Parent.Parent.CelebrationScorerResolve)
local PlayerMapUtil = require(ReplicatedStorage.Shared.PlayerMapUtil)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local CARRY_MONEY_ATTRIBUTE = "CarryMoney"

local activeBillboard: BillboardGui? = nil
local attributeConnection: RBXScriptConnection? = nil
local trackedCharacter: Model? = nil
local latestPayload: Types.RoundStatePayload? = nil

local celebrationActive = false
local celebrationScoredAmount = 0
local celebrationNetWorth: number? = nil
local celebrationStartTime = 0
local celebrationScorerUserId: number? = nil
local celebrationScorerCharacterName: string? = nil

local function formatMoney(amount: number): string
	return `$` .. tostring(amount)
end

local function clearBillboard()
	if attributeConnection then
		attributeConnection:Disconnect()
		attributeConnection = nil
	end

	if activeBillboard then
		activeBillboard:Destroy()
		activeBillboard = nil
	end

	trackedCharacter = nil
end

local function clearCelebration()
	celebrationActive = false
	celebrationScoredAmount = 0
	celebrationNetWorth = nil
	celebrationScorerUserId = nil
	celebrationScorerCharacterName = nil
	clearBillboard()
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

local function resolveScorerNetWorth(
	bankTotal: number?,
	banks: Types.BankMap?,
	scorerUserId: number?
): number?
	if typeof(bankTotal) == "number" then
		return bankTotal
	end

	if scorerUserId and banks then
		return PlayerMapUtil.get(banks, scorerUserId)
	end

	return nil
end

local function createBillboardGui(adornee: BasePart, includeNetWorth: boolean): BillboardGui
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "CarryMoneyBillboard"
	billboard.Adornee = adornee
	billboard.AlwaysOnTop = true
	billboard.Size = if includeNetWorth then UDim2.fromOffset(150, 58) else UDim2.fromOffset(120, 36)
	billboard.StudsOffset = Config.MONEY_BILLBOARD_STUDS_OFFSET
	billboard.LightInfluence = 0

	local amount = Instance.new("TextLabel")
	amount.Name = "Amount"
	amount.BackgroundTransparency = 0.35
	amount.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	amount.BorderSizePixel = 0
	amount.Font = Enum.Font.GothamBold
	amount.TextColor3 = Color3.fromRGB(120, 255, 120)
	amount.TextSize = 22
	amount.Text = "$0"
	amount.Size = if includeNetWorth then UDim2.new(1, 0, 0, 32) else UDim2.fromScale(1, 1)
	amount.Parent = billboard

	if includeNetWorth then
		local netWorth = Instance.new("TextLabel")
		netWorth.Name = "NetWorth"
		netWorth.BackgroundTransparency = 1
		netWorth.BorderSizePixel = 0
		netWorth.Font = Enum.Font.GothamBold
		netWorth.TextColor3 = Color3.fromRGB(200, 230, 200)
		netWorth.TextSize = 16
		netWorth.Text = "Net Worth: $0"
		netWorth.Position = UDim2.fromOffset(0, 32)
		netWorth.Size = UDim2.new(1, 0, 0, 22)
		netWorth.Parent = billboard
	end

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

local function updateNetWorthLabel(amount: number)
	if not activeBillboard then
		return
	end

	local label = activeBillboard:FindFirstChild("NetWorth")
	if label and label:IsA("TextLabel") then
		label.Text = `Net Worth: {formatMoney(amount)}`
	end
end

local function resolveCelebrationCharacter(): Model?
	return CelebrationScorerResolve.resolveFromPayload({
		scorerUserId = celebrationScorerUserId,
		scorerCharacterName = celebrationScorerCharacterName,
	})
end

local function getCelebrationDisplayAmounts(): (number, number?)
	local countDuration = math.max(Config.SCORE_CELEBRATION_MONEY_COUNT_DURATION, 0.1)
	local elapsed = os.clock() - celebrationStartTime
	local countRate = celebrationScoredAmount / countDuration
	local displayedScore = math.min(celebrationScoredAmount, math.floor(elapsed * countRate))

	if celebrationNetWorth and celebrationScoredAmount > 0 then
		local netWorthBefore = celebrationNetWorth - celebrationScoredAmount
		local displayedNetWorth = math.min(celebrationNetWorth, netWorthBefore + displayedScore)
		return displayedScore, displayedNetWorth
	end

	if celebrationNetWorth then
		return displayedScore, celebrationNetWorth
	end

	return displayedScore, nil
end

local function bindCelebrationCharacter(character: Model)
	if trackedCharacter == character and activeBillboard then
		local displayedScore, displayedNetWorth = getCelebrationDisplayAmounts()
		updateLabelAmount(displayedScore)
		if displayedNetWorth then
			updateNetWorthLabel(displayedNetWorth)
		end
		return
	end

	local adornee = getAdornee(character)
	if not adornee then
		return
	end

	clearBillboard()
	trackedCharacter = character

	local billboard = createBillboardGui(adornee, celebrationNetWorth ~= nil)
	billboard.Parent = character
	activeBillboard = billboard

	local displayedScore, displayedNetWorth = getCelebrationDisplayAmounts()
	updateLabelAmount(displayedScore)
	if displayedNetWorth then
		updateNetWorthLabel(displayedNetWorth)
	end
end

local function startCelebration(
	scoredAmount: number,
	bankTotal: number?,
	banks: Types.BankMap?,
	scorerUserId: number?,
	scorerCharacterName: string?
)
	if scoredAmount <= 0 then
		return
	end

	celebrationActive = true
	celebrationScoredAmount = scoredAmount
	celebrationNetWorth = resolveScorerNetWorth(bankTotal, banks, scorerUserId)
	celebrationStartTime = os.clock()
	celebrationScorerUserId = scorerUserId
	celebrationScorerCharacterName = scorerCharacterName
	clearBillboard()
end

local function refreshCelebrationBillboard()
	if not celebrationActive then
		return
	end

	local character = resolveCelebrationCharacter()
	if not character then
		return
	end

	bindCelebrationCharacter(character)

	local displayedScore, displayedNetWorth = getCelebrationDisplayAmounts()
	updateLabelAmount(displayedScore)
	if displayedNetWorth then
		updateNetWorthLabel(displayedNetWorth)
	end
end

local function bindCharacter(character: Model)
	if trackedCharacter == character and activeBillboard then
		local amount = character:GetAttribute(CARRY_MONEY_ATTRIBUTE)
		if typeof(amount) == "number" then
			updateLabelAmount(amount)
		end
		return
	end

	local adornee = getAdornee(character)
	if not adornee then
		return
	end

	clearBillboard()
	trackedCharacter = character

	local billboard = createBillboardGui(adornee, false)
	billboard.Parent = character
	activeBillboard = billboard

	local initialAmount = character:GetAttribute(CARRY_MONEY_ATTRIBUTE)
	updateLabelAmount(if typeof(initialAmount) == "number" then initialAmount else 0)

	attributeConnection = character:GetAttributeChangedSignal(CARRY_MONEY_ATTRIBUTE):Connect(function()
		local amount = character:GetAttribute(CARRY_MONEY_ATTRIBUTE)
		if typeof(amount) == "number" then
			updateLabelAmount(amount)
		else
			updateLabelAmount(0)
		end
	end)
end

local function findCarrierCharacter(payload: Types.RoundStatePayload): Model?
	if payload.carrierUserId then
		local carrierPlayer = Players:GetPlayerByUserId(payload.carrierUserId)
		if carrierPlayer and carrierPlayer.Character then
			return carrierPlayer.Character
		end
	end

	for _, listedPlayer in Players:GetPlayers() do
		local character = listedPlayer.Character
		if character and typeof(character:GetAttribute(CARRY_MONEY_ATTRIBUTE)) == "number" then
			return character
		end
	end

	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("Model") and typeof(descendant:GetAttribute(CARRY_MONEY_ATTRIBUTE)) == "number" then
			return descendant
		end
	end

	return nil
end

local function refreshBillboard()
	if celebrationActive then
		refreshCelebrationBillboard()
		return
	end

	if not latestPayload or latestPayload.state ~= "Active" then
		clearBillboard()
		return
	end

	if not latestPayload.carrierUserId and not latestPayload.carrierName then
		clearBillboard()
		return
	end

	local character = findCarrierCharacter(latestPayload)
	if not character then
		clearBillboard()
		return
	end

	bindCharacter(character)
end

local function tryStartCelebrationFromPayload(payload: Types.RoundStatePayload)
	if payload.state ~= "Scored" and payload.state ~= "Intermission" then
		return
	end

	local scoredAmount = payload.scoredAmount
	if not scoredAmount or scoredAmount <= 0 then
		return
	end

	if celebrationActive and celebrationScoredAmount == scoredAmount then
		return
	end

	startCelebration(scoredAmount, payload.bankTotal, payload.banks, payload.scorerUserId, payload.scorerCharacterName)
end

Remotes.scoreCelebrationStarted().OnClientEvent:Connect(function(payload: Types.CelebrationScenePayload)
	local scoredAmount = payload.scoredAmount
	if not scoredAmount or scoredAmount <= 0 then
		return
	end

	startCelebration(
		scoredAmount,
		payload.bankTotal,
		payload.banks,
		payload.scorerUserId,
		payload.scorerCharacterName
	)
	refreshCelebrationBillboard()
end)

Remotes.roundStateChanged().OnClientEvent:Connect(function(payload: Types.RoundStatePayload)
	latestPayload = payload

	if payload.state == "Active" or payload.state == "Waiting" then
		clearCelebration()
	elseif payload.state == "Scored" or payload.state == "Intermission" then
		tryStartCelebrationFromPayload(payload)
	end

	refreshBillboard()
end)

RunService.Heartbeat:Connect(refreshBillboard)
