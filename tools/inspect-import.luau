--[[
	Inspects third-party models saved from Roblox Studio (.rbxm / .rbxmx)
	before we use them. Read-only: never modifies the files.

	    lune run tools/inspect-import imports/SomeModel.rbxm [more files...]
	    lune run tools/inspect-import imports            (every file in a folder)

	Reports, per file:
	  * size and instance counts by class
	  * every script, its length and any red-flag patterns (remote code
	    loading, obfuscation, teleports, purchases, chat/kick, HTTP)
	  * MeshParts (mesh / texture ids, size, render & collision fidelity)
	  * Decals / Textures / SurfaceAppearances (possible logos)
	  * Seats, constraints, Humanoids, sounds, particle emitters (with settings)
	  * text found in TextLabels / names that look like real brands
	  * the bounding box of the whole model (to compare with our bike geometry)
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local RED_FLAGS = {
	{ "require%s*%(%s*%d", "require(assetId) - loads code from the internet" },
	{ "loadstring", "loadstring - runs code from text" },
	{ "getfenv", "getfenv - often used to hide code" },
	{ "setfenv", "setfenv - often used to hide code" },
	{ "InsertService", "InsertService - can load other assets" },
	{ "LoadAsset", "LoadAsset - can load other assets" },
	{ "HttpService", "HttpService - talks to outside servers" },
	{ "TeleportService", "TeleportService - can send players to other games" },
	{ "MarketplaceService", "MarketplaceService - purchase prompts" },
	{ ":Kick%(", "Kick - removes players" },
	{ "\\%d%d%d\\%d%d%d", "escaped byte strings - possible obfuscation" },
	{ "string%.char%(", "string.char - possible obfuscation" },
	{ "_G%.", "_G - global tampering" },
	{ "Chat", "Chat access" },
	{ "game%.Players%.[%w_]+%.Character", "touches specific players" },
}

local BRANDS = { "surron", "sur%-ron", "light bee", "talaria", "ktm", "yamaha", "yz", "honda", "crf", "husqvarna", "kawasaki", "suzuki", "stark", "varg", "fox", "monster", "red bull", "redbull", "alpinestars", "ktc" }

local function inspectFile(path: string)
	print(string.rep("=", 78))
	print(`FILE {path}  ({fs.metadata(path).size // 1024} KB)`)
	local ok, roots = pcall(function()
		local bytes = fs.readFile(path)
		return roblox.deserializeModel(bytes)
	end)
	if not ok then
		print(`  !! could not read: {roots}`)
		return
	end

	local classes: { [string]: number } = {}
	local all = {}
	for _, root in roots do
		table.insert(all, root)
		for _, d in root:GetDescendants() do
			table.insert(all, d)
		end
	end
	for _, inst in all do
		classes[inst.ClassName] = (classes[inst.ClassName] or 0) + 1
	end
	local names = {}
	for _, root in roots do
		table.insert(names, `{root.Name} ({root.ClassName})`)
	end
	print(`  roots: {table.concat(names, ", ")}   instances: {#all}`)
	local list = {}
	for k, v in classes do
		table.insert(list, { k, v })
	end
	table.sort(list, function(a, b)
		return a[2] > b[2]
	end)
	local parts = {}
	for _, e in list do
		table.insert(parts, `{e[1]}={e[2]}`)
	end
	print(`  classes: {table.concat(parts, " ")}`)

	-- Bounding box of all BaseParts (centre +- half size; rotation ignored, so approximate)
	local lo = { math.huge, math.huge, math.huge }
	local hi = { -math.huge, -math.huge, -math.huge }
	for _, inst in all do
		if inst:IsA("BasePart") then
			local p = inst.CFrame.Position
			local s = inst.Size
			for i, v in { p.X, p.Y, p.Z } do
				local half = ({ s.X, s.Y, s.Z })[i] / 2
				lo[i] = math.min(lo[i], v - half)
				hi[i] = math.max(hi[i], v + half)
			end
		end
	end
	if lo[1] < math.huge then
		print(string.format("  bounding box (studs, approx): X %.2f  Y %.2f  Z %.2f", hi[1] - lo[1], hi[2] - lo[2], hi[3] - lo[3]))
	end

	-- Scripts
	print("  -- scripts")
	local scriptCount = 0
	for _, inst in all do
		if inst:IsA("LuaSourceContainer") then
			scriptCount += 1
			local source = inst.Source or ""
			local flags = {}
			for _, flag in RED_FLAGS do
				if string.find(source, flag[1]) then
					table.insert(flags, flag[2])
				end
			end
			local longest = 0
			for line in string.gmatch(source, "[^\n]+") do
				longest = math.max(longest, #line)
			end
			if longest > 1000 then
				table.insert(flags, `very long line ({longest} chars) - possible obfuscation`)
			end
			print(string.format("    %-14s %-60s %6d chars %s", inst.ClassName, inst:GetFullName():sub(1, 60), #source, if #flags > 0 then "\n        !! " .. table.concat(flags, "\n        !! ") else ""))
		end
	end
	if scriptCount == 0 then
		print("    (none)")
	end

	-- Meshes
	print("  -- mesh parts")
	for _, inst in all do
		if inst:IsA("MeshPart") then
			local okMesh, meshId = pcall(function()
				return inst.MeshId
			end)
			local okTex, texId = pcall(function()
				return inst.TextureID
			end)
			print(string.format(
				"    %-28s size %5.2f x %5.2f x %5.2f  mesh %s  tex %s",
				inst.Name:sub(1, 28),
				inst.Size.X,
				inst.Size.Y,
				inst.Size.Z,
				if okMesh then tostring(meshId) else "?",
				if okTex then tostring(texId) else "?"
			))
		end
	end

	-- Images that may carry logos
	print("  -- decals / textures / surface appearances")
	for _, inst in all do
		if inst:IsA("Decal") or inst:IsA("SurfaceAppearance") or inst.ClassName == "ImageLabel" then
			local okTex, tex = pcall(function()
				return if inst:IsA("SurfaceAppearance") then inst.ColorMap else inst.Texture
			end)
			print(`    {inst.ClassName} {inst:GetFullName()} {if okTex then tostring(tex) else ""}`)
		end
	end

	-- Vehicle / physics / gameplay objects
	print("  -- seats, constraints, humanoids, sounds, effects")
	for _, inst in all do
		if inst:IsA("Seat") or inst:IsA("VehicleSeat") or inst:IsA("Constraint") or inst:IsA("Humanoid") or inst:IsA("JointInstance") and inst.ClassName ~= "Weld" and inst.ClassName ~= "WeldConstraint" then
			print(`    {inst.ClassName} {inst:GetFullName()}`)
		elseif inst:IsA("Sound") then
			print(`    Sound {inst:GetFullName()} {inst.SoundId}`)
		elseif inst:IsA("ParticleEmitter") then
			local props = {}
			for _, key in { "Texture", "Rate", "Lifetime", "Speed", "SpreadAngle", "Size", "Transparency", "Color", "LightEmission", "Drag", "Acceleration", "EmissionDirection", "Rotation", "RotSpeed", "ZOffset", "Shape" } do
				local okP, value = pcall(function()
					return inst[key]
				end)
				if okP then
					table.insert(props, `{key}={tostring(value)}`)
				end
			end
			print(`    ParticleEmitter {inst:GetFullName()}\n        {table.concat(props, "\n        ")}`)
		end
	end

	-- Brand names
	local hits = {}
	for _, inst in all do
		local text = string.lower(inst.Name)
		if inst:IsA("TextLabel") or inst:IsA("TextButton") then
			text ..= " " .. string.lower(inst.Text)
		end
		for _, brand in BRANDS do
			if string.find(text, brand) then
				hits[`{brand}: {inst:GetFullName()}`] = true
			end
		end
	end
	print("  -- possible real-brand names")
	local any = false
	for hit in hits do
		any = true
		print(`    {hit}`)
	end
	if not any then
		print("    (none found in names/text; logos may still be in images)")
	end
end

local targets = {}
for _, arg in process.args do
	if fs.isDir(arg) then
		for _, entry in fs.readDir(arg) do
			if string.match(entry, "%.rbxmx?$") then
				table.insert(targets, `{arg}/{entry}`)
			end
		end
	else
		table.insert(targets, arg)
	end
end
table.sort(targets)
if #targets == 0 then
	print("usage: lune run tools/inspect-import <file.rbxm | folder> ...")
end
for _, path in targets do
	inspectFile(path)
end
