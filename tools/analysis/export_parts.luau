-- Exports every BasePart of a model file to JSON for tools/analysis/render_parts.py.
--   lune run tools/analysis/export_parts out.json assets/Vehicles.rbxm
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local outPath, modelPath = process.args[1], process.args[2]
local root = roblox.deserializeModel(fs.readFile(modelPath))[1]
local out = {}
for _, d in root:GetDescendants() do
	if d:IsA("BasePart") then
		local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = d.CFrame:GetComponents()
		table.insert(out, {
			name = d.Name,
			cls = d.ClassName,
			shape = if d:IsA("Part") then d.Shape.Name else "Block",
			mat = d.Material.Name,
			c = { d.Color.R, d.Color.G, d.Color.B },
			s = { d.Size.X, d.Size.Y, d.Size.Z },
			p = { x, y, z },
			r = { r00, r01, r02, r10, r11, r12, r20, r21, r22 },
			collide = d.CanCollide,
			t = d.Transparency,
			model = (d:FindFirstAncestorOfClass("Model") or d).Name,
		})
	end
end
fs.writeFile(outPath, serde.encode("json", out))
print(`Exported {#out} parts to {outPath}`)
