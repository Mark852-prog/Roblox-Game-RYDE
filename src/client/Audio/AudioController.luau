--!strict
--[[
	AudioController (client)

	Sets up the mix (create.roblox.com/docs/sound/groups): every sound plays
	through one SoundGroup - Vehicles, Ambience, Music or UI - whose volume
	comes from the Settings menu. Also plays:
	  * lobby music while the main menu is open (fades out on PLAY),
	  * outdoor ambience (birds, distant traffic) while in the world.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SoundConfig = require(Shared.Config.SoundConfig)

local Settings = require(script.Parent.Parent.Settings)

local AudioController = {}

local groups: { [string]: SoundGroup } = {}
local loops: { [string]: Sound } = {}

local SETTING_FOR_GROUP = {
	Vehicles = "volumeVehicles",
	Ambience = "volumeAmbience",
	Music = "volumeMusic",
	UI = "volumeUI",
}

local function applyVolumes()
	local master = Settings.get("volumeMaster")
	for name, group in groups do
		group.Volume = master * Settings.get(SETTING_FOR_GROUP[name])
	end
end

local function loopSound(key: string): Sound
	local def = SoundConfig.Sounds[key]
	local sound = Instance.new("Sound")
	sound.Name = "RYDE_" .. key
	sound.SoundId = SoundConfig.assetUri(def.id)
	sound.Looped = true
	sound.Volume = 0
	sound.SoundGroup = groups[def.group]
	sound.Parent = SoundService
	loops[key] = sound
	return sound
end

local function fadeTo(key: string, volume: number, seconds: number)
	local sound = loops[key]
	if not sound then
		return
	end
	if volume > 0 and not sound.Playing then
		sound:Play()
	end
	local tween = TweenService:Create(sound, TweenInfo.new(seconds), { Volume = volume })
	tween:Play()
	if volume <= 0 then
		tween.Completed:Once(function()
			if sound.Volume <= 0.001 then
				sound:Pause()
			end
		end)
	end
end

-- Switch between the menu mix (music) and the world mix (ambience).
function AudioController.setMenuMode(inMenu: boolean)
	local s = SoundConfig.Sounds
	if inMenu then
		fadeTo("LobbyMusic", s.LobbyMusic.volume, 1.5)
		fadeTo("AmbienceBirds", s.AmbienceBirds.volume * 0.3, 1.5)
		fadeTo("AmbienceTraffic", 0, 1.5)
	else
		fadeTo("LobbyMusic", 0, 2.5)
		fadeTo("AmbienceBirds", s.AmbienceBirds.volume, 2)
		fadeTo("AmbienceTraffic", s.AmbienceTraffic.volume, 2)
	end
end

function AudioController.start()
	for name in SETTING_FOR_GROUP do
		local group = SoundService:FindFirstChild(name)
		if not group then
			group = Instance.new("SoundGroup")
			group.Name = name
			group.Parent = SoundService
		end
		groups[name] = group :: SoundGroup
	end
	applyVolumes()
	Settings.onChanged(function(key)
		if string.sub(key, 1, 6) == "volume" then
			applyVolumes()
		end
	end)
	for _, key in { "LobbyMusic", "AmbienceBirds", "AmbienceTraffic" } do
		loopSound(key)
	end
end

return AudioController
