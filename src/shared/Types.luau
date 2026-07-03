export type DodgeType = "Truck" | "Juke"

export type TeamName = "Blue" | "Red"

export type TeamScores = {
	Blue: number,
	Red: number,
}

export type RoundState = "Waiting" | "Active" | "Scored" | "Intermission"

export type ScoreMap = { [number]: number } | { [string]: number }

export type BankMap = { [number]: number } | { [string]: number }

export type CelebrationScenePayload = {
	scorerUserId: number?,
	scorerCharacterName: string?,
	focusPosition: Vector3,
	scoredAmount: number?,
	bankTotal: number?,
}

export type RoundStatePayload = {
	state: RoundState,
	carrierName: string?,
	carrierUserId: number?,
	scores: ScoreMap,
	banks: BankMap,
	timeRemaining: number,
	roundNumber: number,
	winnerName: string?,
	scorerUserId: number?,
	scorerPosition: Vector3?,
	scorerCharacterName: string?,
	scoredAmount: number?,
	bankTotal: number?,
	soloTestRole: string?,
	npcMatchMode: boolean?,
	npcScore: number?,
	gameMode: string?,
	teamsMode: boolean?,
	teamScores: TeamScores?,
	localTeam: TeamName?,
	carrierTeam: TeamName?,
	matchComplete: boolean?,
	matchWinnerUserId: number?,
	matchWinnerNpc: boolean?,
	matchWinnerTeam: TeamName?,
}

export type PassStartedPayload = {
	throwerUserId: number?,
	throwerCharacterName: string?,
	receiverUserId: number?,
	receiverCharacterName: string?,
}

export type PassEndedPayload = {
	throwerUserId: number?,
	receiverCharacterName: string?,
	completed: boolean?,
}

return {}
