local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local PlayerDataService = require(script.Parent.PlayerDataService)
local Types = require(ReplicatedStorage.Shared.Types)

local CARRY_MONEY_ATTRIBUTE = "CarryMoney"

type HolderType = "none" | "human" | "npc" | "loose"

local MoneyService = {}
MoneyService._banks = {} :: Types.BankMap
MoneyService._carryUserId = nil :: number?
MoneyService._valueBase = 0
MoneyService._valueStartedAt = nil :: number?
MoneyService._holderType = "none" :: HolderType
MoneyService._heartbeatConnection = nil :: RBXScriptConnection?
MoneyService._ballService = nil
MoneyService._carrierCharacter = nil :: Model?

local function getPlayerByUserId(userId: number): Player?
	return Players:GetPlayerByUserId(userId)
end

local function clearCharacterCarryAttribute(character: Model?)
	if character and character.Parent then
		character:SetAttribute(CARRY_MONEY_ATTRIBUTE, nil)
	end
end

function MoneyService:getCarryAmount(): number
	return self:getBallWorth()
end

function MoneyService:getBallWorth(): number
	if self._holderType == "loose" then
		return self._valueBase
	end

	if self._valueStartedAt then
		local elapsed = os.clock() - self._valueStartedAt
		return self._valueBase + math.floor(elapsed * Config.MONEY_PER_SECOND)
	end

	return self._valueBase
end

function MoneyService:getBanks(): Types.BankMap
	return self._banks
end

function MoneyService:_clearCarryAttribute(userId: number?)
	if not userId then
		return
	end

	local player = getPlayerByUserId(userId)
	clearCharacterCarryAttribute(player and player.Character)
end

function MoneyService:_syncCarrierCharacterAttribute()
	local character: Model? = nil

	if self._holderType == "human" and self._carryUserId then
		local player = getPlayerByUserId(self._carryUserId)
		character = player and player.Character
	elseif self._holderType == "npc" and self._ballService then
		character = self._ballService:getCarrierCharacter()
	end

	if self._carrierCharacter and self._carrierCharacter ~= character then
		clearCharacterCarryAttribute(self._carrierCharacter)
	end

	self._carrierCharacter = character

	if character then
		character:SetAttribute(CARRY_MONEY_ATTRIBUTE, self:getBallWorth())
	end
end

function MoneyService:_syncCarryAttribute()
	self:_syncCarrierCharacterAttribute()
end

function MoneyService:_syncBallWorthAttribute()
	local ball = self._ballService and self._ballService:getBall()
	if not ball then
		return
	end

	if self._holderType == "loose" then
		ball:SetAttribute(CARRY_MONEY_ATTRIBUTE, self:getBallWorth())
	else
		ball:SetAttribute(CARRY_MONEY_ATTRIBUTE, nil)
	end
end

function MoneyService:onCarrierSet(player: Player, resetValue: boolean?)
	self:_clearCarryAttribute(self._carryUserId)
	clearCharacterCarryAttribute(self._carrierCharacter)
	self._carrierCharacter = nil

	if resetValue then
		self._valueBase = 0
	end

	self._carryUserId = player.UserId
	self._holderType = "human"
	self._valueStartedAt = os.clock()
	self._banks[player.UserId] = PlayerDataService:getNetWorth(player.UserId)

	self:_syncCarrierCharacterAttribute()
	self:_syncBallWorthAttribute()
end

function MoneyService:onNpcCarrierHeld(resetValue: boolean?)
	if resetValue then
		self._valueBase = 0
	end

	self:_clearCarryAttribute(self._carryUserId)
	clearCharacterCarryAttribute(self._carrierCharacter)
	self._carryUserId = nil
	self._holderType = "npc"
	self._valueStartedAt = os.clock()

	self:_syncCarrierCharacterAttribute()
	self:_syncBallWorthAttribute()
end

function MoneyService:onBallKnockedLoose()
	if self._holderType == "human" then
		self:_clearCarryAttribute(self._carryUserId)
		self._carryUserId = nil
	elseif self._holderType == "npc" then
		clearCharacterCarryAttribute(self._carrierCharacter)
		self._carrierCharacter = nil
	end

	self._valueBase = self:getBallWorth()
	self._valueStartedAt = nil
	self._holderType = "loose"

	self:_syncBallWorthAttribute()
end

function MoneyService:onCarrierLost()
	self:_clearCarryAttribute(self._carryUserId)
	clearCharacterCarryAttribute(self._carrierCharacter)
	self._carrierCharacter = nil
	self._carryUserId = nil
	self._valueBase = 0
	self._valueStartedAt = nil
	self._holderType = "none"
	self:_syncBallWorthAttribute()
end

function MoneyService:onScore(carrier: Player): number
	local deposited = self:getBallWorth()
	if deposited > 0 then
		self._banks[carrier.UserId] = PlayerDataService:addNetWorth(carrier.UserId, deposited)
	end

	self:_clearCarryAttribute(carrier.UserId)
	clearCharacterCarryAttribute(self._carrierCharacter)
	self._carrierCharacter = nil
	self._carryUserId = nil
	self._valueBase = 0
	self._valueStartedAt = nil
	self._holderType = "none"
	self:_syncBallWorthAttribute()

	return deposited
end

function MoneyService:init(ballService)
	self._ballService = ballService

	local function syncPlayerBank(player: Player)
		PlayerDataService:waitForLoaded(player)
		self._banks[player.UserId] = PlayerDataService:getNetWorth(player.UserId)
	end

	for _, player in Players:GetPlayers() do
		task.spawn(syncPlayerBank, player)
	end

	Players.PlayerAdded:Connect(function(player)
		task.spawn(syncPlayerBank, player)
	end)

	self._heartbeatConnection = RunService.Heartbeat:Connect(function()
		if self._holderType == "human" or self._holderType == "npc" then
			self:_syncCarrierCharacterAttribute()
		elseif self._holderType == "loose" then
			self:_syncBallWorthAttribute()
		end
	end)
end

return MoneyService
