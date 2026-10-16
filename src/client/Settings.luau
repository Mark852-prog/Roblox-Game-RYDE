--!strict
--[[
	Settings (client)

	Player preferences, changed from the Settings menu. Saved per player in
	Milestone 8 (data saving); until then they reset when you rejoin.
]]

local Settings = {}

Settings.values = {
	units = "kmh", -- "kmh" | "mph"
	chaseCamera = true,
	showControls = true,
	debugHud = false,
	volumeMaster = 1,
	volumeVehicles = 0.8,
	volumeMusic = 0.35,
	volumeAmbience = 0.5,
	volumeUI = 0.6,
}

local listeners: { (key: string, value: any) -> () } = {}

function Settings.get(key: string): any
	return (Settings.values :: any)[key]
end

function Settings.set(key: string, value: any)
	(Settings.values :: any)[key] = value
	for _, listener in listeners do
		task.spawn(listener, key, value)
	end
end

function Settings.onChanged(listener: (key: string, value: any) -> ())
	table.insert(listeners, listener)
end

-- Whether a full-screen menu is open (riding input is ignored while it is).
Settings.menuOpen = false

return Settings
