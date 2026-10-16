--!strict
--[[
	SoundConfig

	Every sound in the game, in one place. All IDs are from Roblox's licensed
	libraries on the Creator Store (ProSoundEffects, APMOfficial) or Roblox's
	own UI sounds, which any experience may use.

	NOTE: these were chosen from their Creator Store titles and lengths; they
	have not been listened to yet. To swap one, find a sound on
	create.roblox.com/store/audio, copy the number from its URL, and replace
	the id below.

	Fields:
	  id       Creator Store asset id
	  volume   base volume (0..10, Roblox default 0.5)
	  looped   loops continuously (engine, wind, ambience, music)
	  group    SoundGroup in SoundService: "Vehicles", "Ambience", "Music", "UI"
	  minDistance / maxDistance  3D roll-off in studs (sounds attached to parts)
]]

export type SoundDef = {
	id: number,
	volume: number,
	looped: boolean,
	group: "Vehicles" | "Ambience" | "Music" | "UI",
	minDistance: number?,
	maxDistance: number?,
}

local function def(id: number, volume: number, looped: boolean, group: any, minDistance: number?, maxDistance: number?): SoundDef
	return { id = id, volume = volume, looped = looped, group = group, minDistance = minDistance, maxDistance = maxDistance }
end

local SoundConfig = {}

SoundConfig.Groups = {
	Vehicles = 0.8,
	Ambience = 0.5,
	Music = 0.35,
	UI = 0.6,
}

SoundConfig.Sounds = {
	-- Vehicle loops (pitch/volume driven by speed, throttle and slip)
	MotorWhine = def(9116980973, 0.9, true, "Vehicles", 8, 160), -- Motor Whine Electric Whirring Buzzing 17
	TireRoad = def(9125955674, 0.5, true, "Vehicles", 6, 90), -- Skateboard Constant Rolling
	TireDirt = def(9126157444, 0.6, true, "Vehicles", 6, 90), -- Vehicle Gravel Tires Crunch Constant
	TireSkid = def(9119186296, 0.7, true, "Vehicles", 8, 140), -- Skids Tire Screeches On Dirt Pavement 3
	Wind = def(9125742262, 0.0, true, "Vehicles"), -- Plasma Trails Constant Airy Whooshing (2D, rider only)

	-- Vehicle one-shots
	Landing = def(9113215854, 1.0, false, "Vehicles", 8, 120), -- Auto Suspension Impacts 1
	LandingDirt = def(9114109952, 0.8, false, "Vehicles", 8, 100), -- Dirt Impacts 2
	BrakeSqueal = def(9125390563, 0.5, false, "Vehicles", 6, 80), -- Bicycle Brake Squeal
	Impact = def(9116546593, 1.0, false, "Vehicles", 10, 180), -- Metal Crash 4
	BodyFall = def(9113469691, 1.0, false, "Vehicles", 8, 100), -- Body Fall Dirt 1

	-- World
	AmbienceBirds = def(9112748214, 0.35, true, "Ambience"), -- Birds Exterior Ambience 1
	AmbienceTraffic = def(9112772284, 0.2, true, "Ambience"), -- Distant Traffic 2

	-- Music
	LobbyMusic = def(80257380636383, 0.6, true, "Music"), -- APM "Game Lobby"
	RideMusic = def(9044545570, 0.4, true, "Music"), -- APM "Night Run"

	-- UI
	UIClick = def(15675059323, 0.8, false, "UI"), -- Roblox_UI_Bright_Click
	UIHover = def(15675032796, 0.4, false, "UI"), -- Roblox_UI_Small_Click
	UIWhoosh = def(15674975792, 0.6, false, "UI"), -- Roblox_UI_Whoosh_03
}

function SoundConfig.assetUri(id: number): string
	return `rbxassetid://{id}`
end

return SoundConfig
