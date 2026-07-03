local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Places = require(ReplicatedStorage.Shared.Places)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local GameMode = require(ReplicatedStorage.Shared.GameMode)

local PlayerDataService = require(script.PlayerDataService)
PlayerDataService:init()

if Places.isMainMenuPlace() then
	local MainMenuService = require(script.MainMenuService)
	local LobbyBoundaryService = require(script.LobbyBoundaryService)
	Remotes.teleportToArena()
	Remotes.teleportToArenaStatus()
	MainMenuService:init()
	LobbyBoundaryService:init()
	print("TackleBall main menu server started")
	return
end

if not Places.isArenaPlace() then
	warn(`TackleBall: unknown place id {game.PlaceId}`)
	return
end

-- Create remotes before any service broadcasts or listens.
Remotes.roundStateChanged()
Remotes.scoreCelebrationStarted()
Remotes.dashChargeBegin()
Remotes.dashChargeRelease()
Remotes.tackleChargeStarted()
Remotes.tackleDashStarted()
Remotes.tackleDashEnded()
Remotes.tackleHit()
Remotes.tackleVictimFlash()
Remotes.devSwitchTestRole()
Remotes.truckChargeBegin()
Remotes.truckChargeRelease()
Remotes.truckChargeStarted()
Remotes.truckDashStarted()
Remotes.truckDashEnded()
Remotes.dodgeActivate()
Remotes.dodgeStarted()
Remotes.tackleShed()
Remotes.sprintActivate()
Remotes.passAttempt()
Remotes.passStarted()
Remotes.passEnded()
Remotes.teleportToLobbyStatus()

local LobbyReturnService = require(script.LobbyReturnService)
local TeamService = require(script.TeamService)
local PassService = require(script.PassService)
local BallService = require(script.BallService)
local AvatarService = require(script.AvatarService)
local DummyCarrierService = require(script.DummyCarrierService)
local DummyTacklerService = require(script.DummyTacklerService)
local EndzoneService = require(script.EndzoneService)
local HealthService = require(script.HealthService)
local MatchService = require(script.MatchService)
local MoneyService = require(script.MoneyService)
local SprintService = require(script.SprintService)
local TackleService = require(script.TackleService)
local BoostOrbService = require(script.BoostOrbService)
local ArenaLayoutService = require(script.ArenaLayoutService)
local FloorSafetyService = require(script.FloorSafetyService)

local ballService = BallService
ballService:init()

MoneyService:init(ballService)
AvatarService:init()
MatchService:init(ballService, DummyCarrierService, DummyTacklerService, MoneyService, HealthService)
MatchService:setTeamService(TeamService)
LobbyReturnService:init()
MatchService:setLobbyReturnService(LobbyReturnService)
DummyCarrierService:init(MatchService)
TackleService:init(MatchService, DummyTacklerService)
SprintService:init(MatchService, TackleService)
BoostOrbService:init(MatchService, TackleService)
DummyTacklerService:init(TackleService, MatchService, ballService)
MatchService:setTackleService(TackleService)
PassService:init(MatchService, ballService, TeamService)
EndzoneService:init(MatchService, ballService)

if GameMode.usesStadiumLayout() then
	ArenaLayoutService:init()
end

FloorSafetyService:init(ballService)

Remotes.sprintActivate().OnServerEvent:Connect(function(player)
	SprintService:activate(player)
end)

Remotes.devSwitchTestRole().OnServerEvent:Connect(function(player, role)
	if typeof(role) ~= "string" then
		return
	end
	MatchService:switchTestRole(player, role)
end)

print("TackleBall arena server started")
