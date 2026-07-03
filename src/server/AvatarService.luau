local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local LegacyRigUtil = require(script.Parent.LegacyRigUtil)

local AvatarService = {}
AvatarService._converting = {} :: { [number]: boolean }
AvatarService._skipConversion = {} :: { [number]: boolean }
AvatarService._r15Template = nil :: Model?

local function getR15Template(): Model
	if AvatarService._r15Template then
		return AvatarService._r15Template
	end

	local description = Instance.new("HumanoidDescription")
	local template = Players:CreateHumanoidModelFromDescriptionAsync(
		description,
		Enum.HumanoidRigType.R15,
		Enum.AssetTypeVerification.ClientOnly
	)
	template.Name = "R15Template"
	template.Parent = ServerStorage
	LegacyRigUtil.ensureMotor6DRig(template)
	AvatarService._r15Template = template
	return template
end

local function getHumanoidDescription(player: Player): HumanoidDescription?
	local ok, description = pcall(function()
		return Players:GetHumanoidDescriptionFromUserIdAsync(player.UserId)
	end)

	if ok and description then
		return description
	end

	return nil
end

local function applyPlayerAppearance(r15Model: Model, player: Player)
	local description = getHumanoidDescription(player)
	if not description then
		return
	end

	local humanoid = r15Model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	pcall(function()
		humanoid:ApplyDescriptionAsync(description, Enum.AssetTypeVerification.ClientOnly)
	end)
end

local function replaceWithR15(player: Player, character: Model)
	if AvatarService._skipConversion[player.UserId] then
		return
	end

	if AvatarService._converting[player.UserId] then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.RigType == Enum.HumanoidRigType.R15 then
		return
	end

	if character:GetAttribute("TackleBallR15") then
		return
	end

	AvatarService._converting[player.UserId] = true

	local spawnCFrame = character:GetPivot()
	local ok, err = pcall(function()
		character:WaitForChild("HumanoidRootPart", 5)

		local r15Model = getR15Template():Clone()
		r15Model.Name = player.Name
		r15Model:SetAttribute("TackleBallR15", true)

		local newHumanoid = r15Model:FindFirstChildOfClass("Humanoid")
		local hrp = r15Model:FindFirstChild("HumanoidRootPart")
		if not newHumanoid or not hrp then
			error("R15 template is missing Humanoid or HumanoidRootPart")
		end

		r15Model:PivotTo(spawnCFrame)
		r15Model.Parent = workspace

		applyPlayerAppearance(r15Model, player)
		LegacyRigUtil.ensureMotor6DRig(r15Model)

		local HealthService = require(script.Parent.HealthService)
		HealthService:setupCharacter(r15Model)

		player.Character = r15Model
	end)

	AvatarService._converting[player.UserId] = false

	if not ok then
		warn(`TackleBall: failed to convert {player.Name} to R15 ({err})`)
		AvatarService._skipConversion[player.UserId] = true
		player:LoadCharacter()
		return
	end

	task.delay(0.5, function()
		if not player.Character or not player.Character.Parent then
			warn(`TackleBall: {player.Name} lost character after R15 conversion, reloading`)
			AvatarService._skipConversion[player.UserId] = true
			player:LoadCharacter()
		end
	end)
end

local function preparePlayerCharacter(player: Player, character: Model)
	replaceWithR15(player, character)

	local activeCharacter = player.Character or character
	if not activeCharacter or not activeCharacter.Parent then
		return
	end

	activeCharacter:WaitForChild("HumanoidRootPart", 5)
	LegacyRigUtil.ensureMotor6DRig(activeCharacter)
end

local function bindPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		task.spawn(function()
			preparePlayerCharacter(player, character)
		end)
	end)

	if player.Character then
		task.spawn(function()
			preparePlayerCharacter(player, player.Character :: Model)
		end)
	end
end

function AvatarService:init()
	task.spawn(function()
		pcall(getR15Template)
	end)

	Players.PlayerAdded:Connect(bindPlayer)

	for _, player in Players:GetPlayers() do
		bindPlayer(player)
	end
end

return AvatarService
