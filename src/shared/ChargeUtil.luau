local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local ChargeUtil = {}

function ChargeUtil.lerp(min: number, max: number, charge01: number): number
	return min + (max - min) * charge01
end

function ChargeUtil.getCharge01FromElapsed(elapsed: number): number
	if elapsed <= Config.CHARGE_TAP_MAX_TIME then
		return Config.CHARGE_NORMAL_CHARGE01
	end

	local holdTime = elapsed - Config.CHARGE_TAP_MAX_TIME
	local holdWindow = Config.CHARGE_MAX_TIME - Config.CHARGE_TAP_MAX_TIME
	local hold01 = math.clamp(holdTime / holdWindow, 0, 1)

	return ChargeUtil.lerp(Config.CHARGE_NORMAL_CHARGE01, 1, hold01)
end

function ChargeUtil.getCharge01(chargeTime: number): number
	return ChargeUtil.getCharge01FromElapsed(chargeTime - Config.CHARGE_MIN_TIME)
end

function ChargeUtil.getDashSpeed(charge01: number): number
	return ChargeUtil.lerp(Config.CHARGE_MIN_DASH_SPEED, Config.CHARGE_MAX_DASH_SPEED, charge01)
end

function ChargeUtil.getKnockbackPower01(charge01: number): number
	return charge01 ^ Config.CHARGE_KNOCKBACK_POWER
end

function ChargeUtil.getKnockback(charge01: number): number
	local power01 = ChargeUtil.getKnockbackPower01(charge01)
	return ChargeUtil.lerp(Config.CHARGE_MIN_KNOCKBACK, Config.CHARGE_MAX_KNOCKBACK, power01)
end

function ChargeUtil.getKnockbackUp(charge01: number): number
	local liftPower = Config.CHARGE_KNOCKBACK_UP_POWER or Config.CHARGE_KNOCKBACK_POWER
	local lift01 = charge01 ^ liftPower
	return ChargeUtil.lerp(Config.CHARGE_MIN_KNOCKBACK_UP, Config.CHARGE_MAX_KNOCKBACK_UP, lift01)
end

function ChargeUtil.getTruckDashSpeed(charge01: number): number
	return ChargeUtil.lerp(Config.TRUCK_MIN_DASH_SPEED, Config.TRUCK_MAX_DASH_SPEED, charge01)
end

function ChargeUtil.getTruckShedBoost(charge01: number): number
	return ChargeUtil.lerp(Config.TRUCK_MIN_SHED_BOOST, Config.TRUCK_MAX_SHED_BOOST, charge01)
end

function ChargeUtil.getStunDuration(charge01: number): number
	local power01 = ChargeUtil.getKnockbackPower01(charge01)
	return ChargeUtil.lerp(Config.CHARGE_MIN_STUN, Config.CHARGE_MAX_STUN, power01)
end

function ChargeUtil.getTackleDamage(charge01: number): number
	local power01 = ChargeUtil.getKnockbackPower01(charge01)
	return ChargeUtil.lerp(Config.CHARGE_MIN_TACKLE_DAMAGE, Config.CHARGE_MAX_TACKLE_DAMAGE, power01)
end

return ChargeUtil
