local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local REMOTES_FOLDER_NAME = "Remotes"

local Remotes = {}

local function getFolder(): Folder
	local folder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if not folder then
		if RunService:IsServer() then
			folder = Instance.new("Folder")
			folder.Name = REMOTES_FOLDER_NAME
			folder.Parent = ReplicatedStorage
		else
			folder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME)
		end
	end
	return folder :: Folder
end

local function getRemote(name: string, className: string): Instance
	local folder = getFolder()
	local remote = folder:FindFirstChild(name)
	if not remote then
		if RunService:IsServer() then
			remote = Instance.new(className)
			remote.Name = name
			remote.Parent = folder
		else
			remote = folder:WaitForChild(name)
		end
	end
	return remote
end

function Remotes.roundStateChanged(): RemoteEvent
	return getRemote("RoundStateChanged", "RemoteEvent") :: RemoteEvent
end

function Remotes.scoreCelebrationStarted(): RemoteEvent
	return getRemote("ScoreCelebrationStarted", "RemoteEvent") :: RemoteEvent
end

function Remotes.dashChargeBegin(): RemoteEvent
	return getRemote("DashChargeBegin", "RemoteEvent") :: RemoteEvent
end

function Remotes.dashChargeRelease(): RemoteEvent
	return getRemote("DashChargeRelease", "RemoteEvent") :: RemoteEvent
end

function Remotes.tackleChargeStarted(): RemoteEvent
	return getRemote("TackleChargeStarted", "RemoteEvent") :: RemoteEvent
end

function Remotes.tackleDashStarted(): RemoteEvent
	return getRemote("TackleDashStarted", "RemoteEvent") :: RemoteEvent
end

function Remotes.tackleDashEnded(): RemoteEvent
	return getRemote("TackleDashEnded", "RemoteEvent") :: RemoteEvent
end

function Remotes.teleportToArena(): RemoteEvent
	return getRemote("TeleportToArena", "RemoteEvent") :: RemoteEvent
end

function Remotes.teleportToArenaStatus(): RemoteEvent
	return getRemote("TeleportToArenaStatus", "RemoteEvent") :: RemoteEvent
end

function Remotes.teleportToLobbyStatus(): RemoteEvent
	return getRemote("TeleportToLobbyStatus", "RemoteEvent") :: RemoteEvent
end

function Remotes.tackleHit(): RemoteEvent
	return getRemote("TackleHit", "RemoteEvent") :: RemoteEvent
end

function Remotes.tackleVictimFlash(): RemoteEvent
	return getRemote("TackleVictimFlash", "RemoteEvent") :: RemoteEvent
end

function Remotes.devSwitchTestRole(): RemoteEvent
	return getRemote("DevSwitchTestRole", "RemoteEvent") :: RemoteEvent
end

function Remotes.truckChargeBegin(): RemoteEvent
	return getRemote("TruckChargeBegin", "RemoteEvent") :: RemoteEvent
end

function Remotes.truckChargeRelease(): RemoteEvent
	return getRemote("TruckChargeRelease", "RemoteEvent") :: RemoteEvent
end

function Remotes.truckChargeStarted(): RemoteEvent
	return getRemote("TruckChargeStarted", "RemoteEvent") :: RemoteEvent
end

function Remotes.truckDashStarted(): RemoteEvent
	return getRemote("TruckDashStarted", "RemoteEvent") :: RemoteEvent
end

function Remotes.truckDashEnded(): RemoteEvent
	return getRemote("TruckDashEnded", "RemoteEvent") :: RemoteEvent
end

function Remotes.dodgeActivate(): RemoteEvent
	return getRemote("DodgeActivate", "RemoteEvent") :: RemoteEvent
end

function Remotes.dodgeStarted(): RemoteEvent
	return getRemote("DodgeStarted", "RemoteEvent") :: RemoteEvent
end

function Remotes.truckTuckActivate(): RemoteEvent
	return Remotes.dodgeActivate()
end

function Remotes.truckTuckStarted(): RemoteEvent
	return Remotes.dodgeStarted()
end

function Remotes.tackleShed(): RemoteEvent
	return getRemote("TackleShed", "RemoteEvent") :: RemoteEvent
end

function Remotes.sprintActivate(): RemoteEvent
	return getRemote("SprintActivate", "RemoteEvent") :: RemoteEvent
end

function Remotes.passAttempt(): RemoteEvent
	return getRemote("PassAttempt", "RemoteEvent") :: RemoteEvent
end

function Remotes.passStarted(): RemoteEvent
	return getRemote("PassStarted", "RemoteEvent") :: RemoteEvent
end

function Remotes.passEnded(): RemoteEvent
	return getRemote("PassEnded", "RemoteEvent") :: RemoteEvent
end

return Remotes
