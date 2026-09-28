--!strict
--[[
	WeaponStats
	Turns a weapon ItemInstance into the numbers combat uses: fire rate,
	magazine, damage, falloff, reload and swap time, spread and recoil.

	Shared so the client predicts exactly what the server enforces.

	Final 0-100 stats = rolled stats + barrel/magazine perk modifiers +
	masterwork bonus, clamped. Then (CombatConfig.WeaponStats):
	  damage     = archetype BaseDamage * lerp(ImpactDamageMin, ImpactDamageMax, Impact/100)
	  falloff    = archetype Falloff distances * lerp(RangeScaleMin, RangeScaleMax, Range/100)
	  reload     = archetype ReloadTime * lerp(ReloadScaleSlow, ReloadScaleFast, Reload/100)
	  swap       = archetype SwapTime * lerp(HandlingScaleSlow, HandlingScaleFast, Handling/100)
	  recoil     = archetype Recoil * lerp(StabilityRecoilMax, StabilityRecoilMin, Stability/100)
]]

local Config = script.Parent.Parent.Config
local CombatConfig = require(Config.CombatConfig)
local PerkConfig = require(Config.PerkConfig)
local RarityConfig = require(Config.RarityConfig)
local Types = require(script.Parent.Parent.Types)
local WeaponConfig = require(Config.WeaponConfig)
local WeaponTypeConfig = require(Config.WeaponTypeConfig)

export type WeaponStats = {
	DefId: string,
	Name: string,
	Type: Types.WeaponTypeId,
	Slot: Types.WeaponSlot,
	Element: Types.Element,
	Rarity: Types.Rarity,
	AmmoType: Types.AmmoType,
	FireMode: Types.FireMode,
	-- Final 0-100 stats after perks and masterwork.
	Stats: { [string]: number },
	Rpm: number,
	FireInterval: number,
	Magazine: number,
	-- nil = infinite reserves (primary ammo).
	Reserves: number?,
	Damage: number,
	PrecisionMultiplier: number,
	FalloffStart: number,
	FalloffEnd: number,
	FalloffMin: number,
	MaxRange: number,
	ReloadTime: number,
	SwapTime: number,
	AdsFov: number,
	AdsMoveScale: number,
	SpreadHip: number,
	SpreadAds: number,
	SpreadPerShot: number,
	SpreadMax: number,
	RecoilVertical: number,
	RecoilHorizontal: number,
	RecoilRecovery: number,
	Projectile: { Speed: number, BlastRadius: number, Gravity: number? }?,
	-- Pellets per shot (shotguns); bolts per charged shot (fusion rifles).
	Pellets: number,
	-- Rounds per trigger pull (pulse rifles) and the gap between them.
	BurstCount: number,
	BurstDelay: number,
	-- Seconds a charge weapon must charge before it fires.
	ChargeTime: number,
	-- The exotic perk's effect, if this is an exotic with one.
	Exotic: ExoticEffect?,
}

export type ExoticEffect = {
	PerkId: string,
	Kind: string,
	Value: number,
	Every: number,
	Radius: number,
	Duration: number,
}

local WeaponStats = {}

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- Final 0-100 stats for a weapon item (rolled + perks + masterwork).
function WeaponStats.FinalStats(item: Types.ItemInstance): { [string]: number }
	local stats: { [string]: number } = {}
	for _, stat in WeaponTypeConfig.RolledStats do
		stats[stat] = item.Stats[stat] or 50
	end
	for _, perkId in item.Perks do
		local perk = PerkConfig.ById[perkId]
		if perk and perk.StatModifiers then
			for stat, delta in perk.StatModifiers do
				if stats[stat] ~= nil then
					stats[stat] += delta
				end
			end
		end
	end
	if item.Masterwork and stats[item.Masterwork] ~= nil then
		stats[item.Masterwork] += RarityConfig.MasterworkBonus
	end
	for stat, value in stats do
		stats[stat] = math.clamp(value, WeaponTypeConfig.StatMin, WeaponTypeConfig.StatMax)
	end
	return stats
end

-- Everything combat needs for a weapon item, or nil if it isn't a known weapon.
function WeaponStats.Compute(item: Types.ItemInstance): WeaponStats?
	local def = WeaponConfig.ById[item.DefId]
	if def == nil then
		return nil
	end
	local archetype = WeaponTypeConfig.Types[def.Type]
	local tuning = CombatConfig.WeaponStats
	local stats = WeaponStats.FinalStats(item)

	local magazineScale = 1
	for _, perkId in item.Perks do
		local perk = PerkConfig.ById[perkId]
		if perk and perk.MagazineScale then
			magazineScale *= perk.MagazineScale
		end
	end

	local exotic: ExoticEffect? = nil
	for _, perkId in item.Perks do
		local perk = PerkConfig.ById[perkId]
		if perk and perk.Column == "Exotic" and perk.Effect then
			local effect = perk.Effect
			exotic = {
				PerkId = perk.Id,
				Kind = effect.Kind,
				Value = effect.Value or 1,
				Every = effect.Every or 1,
				Radius = effect.Radius or 8,
				Duration = effect.Duration or 3,
			}
		end
	end

	local rpm = def.Rpm or archetype.Rpm
	local rangeScale = lerp(tuning.RangeScaleMin, tuning.RangeScaleMax, stats.Range / 100)
	local recoilScale = lerp(tuning.StabilityRecoilMax, tuning.StabilityRecoilMin, stats.Stability / 100)

	return {
		DefId = def.Id,
		Name = def.Name,
		Type = def.Type,
		Slot = def.Slot,
		Element = def.Element,
		Rarity = item.Rarity,
		AmmoType = archetype.AmmoType,
		FireMode = archetype.FireMode,
		Stats = stats,
		Rpm = rpm,
		FireInterval = 60 / rpm,
		Magazine = math.max(1, math.floor((def.Magazine or archetype.Magazine) * magazineScale)),
		Reserves = if archetype.AmmoType == "Primary" then nil else archetype.Reserves,
		Damage = archetype.BaseDamage * lerp(tuning.ImpactDamageMin, tuning.ImpactDamageMax, stats.Impact / 100),
		PrecisionMultiplier = archetype.PrecisionMultiplier,
		FalloffStart = archetype.Falloff.Start * rangeScale,
		FalloffEnd = archetype.Falloff.End * rangeScale,
		FalloffMin = archetype.Falloff.MinMultiplier,
		MaxRange = archetype.MaxRange,
		ReloadTime = archetype.ReloadTime * lerp(tuning.ReloadScaleSlow, tuning.ReloadScaleFast, stats.Reload / 100),
		SwapTime = archetype.SwapTime * lerp(tuning.HandlingScaleSlow, tuning.HandlingScaleFast, stats.Handling / 100),
		AdsFov = archetype.Ads.Fov,
		AdsMoveScale = archetype.Ads.MoveSpeedScale,
		SpreadHip = archetype.Spread.Hip,
		SpreadAds = archetype.Spread.Ads,
		SpreadPerShot = archetype.Spread.PerShot,
		SpreadMax = archetype.Spread.Max,
		RecoilVertical = archetype.Recoil.Vertical * recoilScale,
		RecoilHorizontal = archetype.Recoil.Horizontal * recoilScale,
		RecoilRecovery = archetype.Recoil.Recovery,
		Projectile = archetype.Projectile,
		Pellets = if archetype.FireMode == "Charge" then archetype.BurstCount or 1 else archetype.Pellets or 1,
		BurstCount = if archetype.FireMode == "Burst" then archetype.BurstCount or 3 else 1,
		BurstDelay = 0.07,
		ChargeTime = archetype.ChargeTime or 0,
		Exotic = exotic,
	}
end

return WeaponStats
