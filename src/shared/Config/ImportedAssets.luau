--!strict
--[[
	ImportedAssets

	Creator Store assets the game loads at runtime with
	AssetService:LoadAssetAsync (the place file has "Allow Loading Third
	Party Assets" switched on). Loaded models are stripped of scripts,
	seats, physics objects and sounds, then fitted onto our physics bike
	(see src/server/Services/AssetImportService.luau).

	Bike "styles" are purely visual: handling always comes from the
	vehicle config. If an asset fails to load, the game falls back to the
	built-in bike model.
]]

export type Style = {
	key: string,
	name: string, -- shown in the garage
	assetId: number,
	triangles: number, -- from the Creator Store listing (performance hint)
}

local ImportedAssets = {}

-- Visual styles that can be put on any electric dirt bike.
ImportedAssets.BikeStyles = {
	{ key = "LightBeeGear", name = "Sur-Ron Light Bee (Gear)", assetId = 89251937064157, triangles = 54422 },
	{ key = "LightBeeX", name = "Sur-Ron Light Bee X", assetId = 83883251155029, triangles = 15123 },
	{ key = "SurronTruly", name = "Sur-Ron (Truly)", assetId = 78650331752762, triangles = 388976 },
	{ key = "SurronModel", name = "Sur-Ron (Detailed)", assetId = 18991052849, triangles = 334883 },
	{ key = "KtcRacing", name = "KTC Racing", assetId = 74259543978107, triangles = 352408 },
	{ key = "YZ450F", name = "Yamaha YZ450F", assetId = 122428726722900, triangles = 319147 },
} :: { Style }

-- Default style per vehicle id (first entry that loads is used if this one fails).
ImportedAssets.DefaultStyle = {
	VoltraStorm = "LightBeeGear",
	KestrelSting = "SurronTruly",
}

-- Particle effects: the first ParticleEmitter found in each asset is used.
ImportedAssets.Effects = {
	Sparks = { 9373307685, 120499146774984 },
	Dust = { 15961846766, 3489188704 },
	Pebbles = { 11459655073 },
}

function ImportedAssets.getStyle(key: string): Style?
	for _, style in ImportedAssets.BikeStyles do
		if style.key == key then
			return style
		end
	end
	return nil
end

return ImportedAssets
