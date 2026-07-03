local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

export type PlayerData = {
	netWorth: number,
}

type LoadState = "loading" | "loaded" | "failed"

local DEFAULT_DATA: PlayerData = {
	netWorth = 0,
}

local MAX_RETRIES = 3
local RETRY_DELAY = 1

local PlayerDataService = {}
PlayerDataService._dataStore = nil :: GlobalDataStore?
PlayerDataService._useDataStore = false
PlayerDataService._sessionData = {} :: { [number]: PlayerData }
PlayerDataService._loadStates = {} :: { [number]: LoadState }
PlayerDataService._dirtyUserIds = {} :: { [number]: boolean }
PlayerDataService._lastSaveAt = {} :: { [number]: number }
PlayerDataService._saveScheduled = false

local function cloneDefaultData(): PlayerData
	return {
		netWorth = DEFAULT_DATA.netWorth,
	}
end

local function normalizeData(raw: any): PlayerData
	if typeof(raw) ~= "table" then
		return cloneDefaultData()
	end

	local netWorth = raw.netWorth
	return {
		netWorth = if type(netWorth) == "number" and netWorth >= 0 then math.floor(netWorth) else 0,
	}
end

local function getKey(userId: number): string
	return tostring(userId)
end

function PlayerDataService:_tryInitDataStore()
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(Config.PLAYER_DATA_STORE_NAME)
	end)

	if ok and store then
		self._dataStore = store
		self._useDataStore = true
	else
		self._dataStore = nil
		self._useDataStore = false
		warn("TackleBall: DataStore unavailable, using in-memory player data only")
	end
end

function PlayerDataService:_loadFromStore(userId: number): PlayerData
	if not self._useDataStore or not self._dataStore then
		return cloneDefaultData()
	end

	for attempt = 1, MAX_RETRIES do
		local ok, result = pcall(function()
			return self._dataStore:GetAsync(getKey(userId))
		end)

		if ok then
			return normalizeData(result)
		end

		warn(`TackleBall: failed to load player data for {userId} (attempt {attempt}): {result}`)
		if attempt < MAX_RETRIES then
			task.wait(RETRY_DELAY * attempt)
		end
	end

	return cloneDefaultData()
end

function PlayerDataService:_saveToStore(userId: number): boolean
	local data = self._sessionData[userId]
	if not data then
		return true
	end

	if not self._useDataStore or not self._dataStore then
		return true
	end

	for attempt = 1, MAX_RETRIES do
		local ok, err = pcall(function()
			self._dataStore:SetAsync(getKey(userId), data)
		end)

		if ok then
			self._dirtyUserIds[userId] = nil
			self._lastSaveAt[userId] = os.clock()
			return true
		end

		warn(`TackleBall: failed to save player data for {userId} (attempt {attempt}): {err}`)
		if attempt < MAX_RETRIES then
			task.wait(RETRY_DELAY * attempt)
		end
	end

	return false
end

function PlayerDataService:_markDirty(userId: number)
	self._dirtyUserIds[userId] = true
	self:_scheduleDebouncedSave(userId)
end

function PlayerDataService:_scheduleDebouncedSave(userId: number)
	if self._saveScheduled then
		return
	end

	self._saveScheduled = true
	task.delay(Config.PLAYER_DATA_SAVE_DEBOUNCE, function()
		self._saveScheduled = false

		for dirtyUserId in self._dirtyUserIds do
			local lastSave = self._lastSaveAt[dirtyUserId] or 0
			if os.clock() - lastSave >= Config.PLAYER_DATA_SAVE_DEBOUNCE then
				self:_saveToStore(dirtyUserId)
			end
		end
	end)
end

function PlayerDataService:_loadPlayer(player: Player)
	local userId = player.UserId
	self._loadStates[userId] = "loading"

	local data = self:_loadFromStore(userId)
	self._sessionData[userId] = data
	self._loadStates[userId] = "loaded"
end

function PlayerDataService:init()
	self:_tryInitDataStore()

	for _, player in Players:GetPlayers() do
		task.spawn(function()
			self:_loadPlayer(player)
		end)
	end

	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			self:_loadPlayer(player)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		local userId = player.UserId
		if self._dirtyUserIds[userId] then
			self:_saveToStore(userId)
		end
		self._sessionData[userId] = nil
		self._loadStates[userId] = nil
		self._dirtyUserIds[userId] = nil
		self._lastSaveAt[userId] = nil
	end)
end

function PlayerDataService:waitForLoaded(player: Player)
	local userId = player.UserId
	while self._loadStates[userId] == "loading" do
		task.wait()
	end

	if not self._sessionData[userId] then
		self._sessionData[userId] = cloneDefaultData()
		self._loadStates[userId] = "loaded"
	end
end

function PlayerDataService:getNetWorth(userId: number): number
	local data = self._sessionData[userId]
	if not data then
		return 0
	end

	return data.netWorth
end

function PlayerDataService:flushDirtySaves()
	for dirtyUserId in self._dirtyUserIds do
		self:_saveToStore(dirtyUserId)
	end
end

function PlayerDataService:addNetWorth(userId: number, amount: number): number
	if amount <= 0 then
		return self:getNetWorth(userId)
	end

	local data = self._sessionData[userId]
	if not data then
		data = cloneDefaultData()
		self._sessionData[userId] = data
		self._loadStates[userId] = "loaded"
	end

	data.netWorth += math.floor(amount)
	self:_markDirty(userId)
	return data.netWorth
end

return PlayerDataService
