local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local CELEBRATION_SCORER_ATTRIBUTE = "TackleBallCelebrationScorer"

local function findCelebrationScorerModel(): Model?
	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("Model") and descendant:GetAttribute(CELEBRATION_SCORER_ATTRIBUTE) == true then
			return descendant
		end
	end

	return nil
end

local function findModelByName(name: string): Model?
	local instance = Workspace:FindFirstChild(name, true)
	if instance and instance:IsA("Model") then
		return instance
	end

	return nil
end

local function resolveFromPayload(payload: { scorerUserId: number?, scorerCharacterName: string? }): Model?
	if payload.scorerCharacterName then
		local namedModel = findModelByName(payload.scorerCharacterName)
		if namedModel then
			return namedModel
		end
	end

	local fromAttribute = findCelebrationScorerModel()
	if fromAttribute then
		return fromAttribute
	end

	if payload.scorerUserId then
		local scorerPlayer = Players:GetPlayerByUserId(payload.scorerUserId)
		if scorerPlayer and scorerPlayer.Character then
			return scorerPlayer.Character
		end
	end

	return nil
end

return {
	CELEBRATION_SCORER_ATTRIBUTE = CELEBRATION_SCORER_ATTRIBUTE,
	findCelebrationScorerModel = findCelebrationScorerModel,
	resolveFromPayload = resolveFromPayload,
}
