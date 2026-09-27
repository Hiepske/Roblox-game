--!strict
--[[
	AssetIds
	Every external asset the game references, in one place.

	All ids are PLACEHOLDERS (0). Replace them with assets you own or that are
	free to use from the Creator Store. Never use ripped assets from other
	games. Code should read ids through AssetIds.Get(...), which returns ""
	for placeholders so nothing tries to load asset 0.

	Models are not asset ids: the game looks for Models by name under
	ReplicatedStorage.Assets (Weapons / Armor / Enemies / Props). Until you add
	real models there, code spawns clearly named grey placeholder parts.
]]

local TableUtil = require(script.Parent.Parent.Util.TableUtil)

local AssetIds = {
	Sounds = {
		Weapons = {
			AutoRifle = { Fire = 0, Reload = 0 },
			PulseRifle = { Fire = 0, Reload = 0 },
			ScoutRifle = { Fire = 0, Reload = 0 },
			HandCannon = { Fire = 0, Reload = 0 },
			SMG = { Fire = 0, Reload = 0 },
			Sidearm = { Fire = 0, Reload = 0 },
			Shotgun = { Fire = 0, Reload = 0 },
			SniperRifle = { Fire = 0, Reload = 0 },
			FusionRifle = { Fire = 0, Charge = 0, Reload = 0 },
			GrenadeLauncher = { Fire = 0, Explode = 0, Reload = 0 },
			RocketLauncher = { Fire = 0, Explode = 0, Reload = 0 },
			Sword = { Swing = 0, Hit = 0 },
			MachineGun = { Fire = 0, Reload = 0 },
		},
		Combat = {
			HitMarker = 0,
			CritMarker = 0,
			KillConfirm = 0,
			ShieldBreak = 0,
			PlayerHurt = 0,
		},
		UI = {
			Click = 0,
			Hover = 0,
			LootRare = 0,
			LootEpic = 0,
			LootLegendary = 0,
			LootExotic = 0,
			PowerUp = 0,
		},
		Music = {
			Hub = 0,
			Combat = 0,
			Boss = 0,
		},
	},
	Images = {
		Currencies = { Quanta = 0, Alloy = 0, Fluxite = 0, Starglass = 0 },
		Elements = { Kinetic = 0, Flare = 0, Storm = 0, Null = 0 },
		Classes = { Bulwark = 0, Ranger = 0, Mystic = 0 },
		Ammo = { Primary = 0, Special = 0, Heavy = 0 },
		Rarity = { Rare = 0, Epic = 0, Legendary = 0, Exotic = 0 },
		PowerIcon = 0,
		Crosshair = 0,
	},
	-- Place ids for TeleportService (reserved servers). 0 = not published yet;
	-- ActivityService (Phase 5) runs activities in the current place instead.
	Places = {
		Hub = 0,
		Mission = 0,
		PatrolVeyra = 0,
		PatrolHollowmere = 0,
		PatrolKessler = 0,
		PatrolSolace = 0,
		Strike = 0,
		Dungeon = 0,
		Raid = 0,
		PvP = 0,
	} :: { [string]: number },
}

local Frozen = TableUtil.DeepFreeze(AssetIds)

-- "rbxassetid://123" for a real id, "" for a placeholder.
local function Get(id: number): string
	if id == 0 then
		return ""
	end
	return `rbxassetid://{id}`
end

local function IsPlaceholder(id: number): boolean
	return id == 0
end

return table.freeze({
	Sounds = Frozen.Sounds,
	Images = Frozen.Images,
	Places = Frozen.Places,
	Get = Get,
	IsPlaceholder = IsPlaceholder,
})
