--[[
	Lets Lune load the game's ModuleScripts the way Roblox would.

	Game code uses instance-style requires, e.g. require(script.Parent.Units).
	This loader builds a fake `script` tree backed by the src/ folders (using
	the same file naming rules as Rojo) so those requires work unchanged.

	Only modules that do not touch Roblox services can be loaded this way
	(configs, maths, validation). Anything that needs the real engine must be
	tested in Roblox Studio.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local ModuleLoader = {}

local ROBLOX_GLOBALS = {
	Vector2 = roblox.Vector2,
	Vector3 = roblox.Vector3,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	UDim = roblox.UDim,
	UDim2 = roblox.UDim2,
	Enum = roblox.Enum,
	Instance = roblox.Instance,
	NumberRange = roblox.NumberRange,
	PhysicalProperties = roblox.PhysicalProperties,
}

local cache: { [string]: any } = {}
local nodeMeta = {}

local function newNode(path: string, name: string, parent: any, isDir: boolean): any
	return setmetatable({ __path = path, __isDir = isDir, Name = name, Parent = parent }, nodeMeta)
end

nodeMeta.__index = function(self, key: string)
	error(`ModuleLoader: '{key}' not found in {rawget(self, "__path")}`, 2)
end

-- Builds the whole tree eagerly (Lune file APIs cannot run inside metamethods).
-- Mirrors Rojo: Foo.luau -> module "Foo", folder Foo/ -> "Foo" (module if it has init.luau).
local function scan(node: any)
	local dir = rawget(node, "__path")
	for _, entry in fs.readDir(dir) do
		local full = `{dir}/{entry}`
		if fs.isDir(full) then
			local child = newNode(full, entry, node, true)
			rawset(node, entry, child)
			scan(child)
		elseif string.sub(entry, -5) == ".luau" and entry ~= "init.luau" then
			local name = string.gsub(string.sub(entry, 1, -6), "%.server$", "")
			name = string.gsub(name, "%.client$", "")
			rawset(node, name, newNode(full, name, node, false))
		end
	end
end

local function requireNode(node: any): any
	local path = rawget(node, "__path")
	if rawget(node, "__isDir") then
		path ..= "/init.luau"
	end
	if cache[path] ~= nil then
		return cache[path]
	end

	local env = { script = node, require = requireNode }
	for name, value in ROBLOX_GLOBALS do
		env[name] = value
	end
	local chunk = luau.load(fs.readFile(path), { debugName = path, environment = env })
	local result = chunk()
	cache[path] = result
	return result
end

-- Root folder node, e.g. ModuleLoader.root("src/shared") ~ ReplicatedStorage.Shared
function ModuleLoader.root(path: string): any
	local node = newNode(path, path, nil, true)
	scan(node)
	return node
end

ModuleLoader.require = requireNode

-- Every .luau file under a directory (recursively).
function ModuleLoader.listFiles(dir: string): { string }
	local files = {}
	for _, entry in fs.readDir(dir) do
		local full = `{dir}/{entry}`
		if fs.isDir(full) then
			for _, nested in ModuleLoader.listFiles(full) do
				table.insert(files, nested)
			end
		elseif string.sub(entry, -5) == ".luau" then
			table.insert(files, full)
		end
	end
	table.sort(files)
	return files
end

return ModuleLoader
