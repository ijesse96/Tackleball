-- Roblox remotes stringify numeric dictionary keys, so player-keyed maps must use
-- string userIds when sent to clients.
local PlayerMapUtil = {}

export type SerializedPlayerMap = { [string]: number }

function PlayerMapUtil.serialize(map: { [number]: number }): SerializedPlayerMap
	local serialized: SerializedPlayerMap = {}
	for userId, value in map do
		serialized[tostring(userId)] = value
	end
	return serialized
end

function PlayerMapUtil.get(map: { [number | string]: number }?, userId: number): number
	if not map then
		return 0
	end

	local value = map[userId]
	if value == nil then
		value = map[tostring(userId)]
	end

	return if type(value) == "number" then value else 0
end

return PlayerMapUtil
