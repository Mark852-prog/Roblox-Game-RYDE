"""
Render Roblox parts (exported to JSON by tools/analysis/export_parts.luau) in
Blender, so part-built models can be reviewed visually without Studio.

    <python-with-bpy> tools/analysis/render_parts.py parts.json ModelName out.png [yaw_deg] [elev_deg] [dist]

Coordinates: Roblox (x, y, z) with Y up -> Blender (x, -z, y) with Z up.
This is an approximation of Roblox's look (no Roblox materials/lighting).
"""
import bpy, json, math, sys
from mathutils import Matrix, Vector

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
path, model_name, out = args[0], args[1], args[2]
cam_override = None
for a in args[3:]:
    if a.startswith("cam="):
        cx, cy, cz, lx, ly, lz = (float(v) for v in a[4:].split(","))
        cam_override = ((cx, cy, cz), (lx, ly, lz))
radius = None
for a in args[3:]:
    if a.startswith("radius="):
        radius = float(a[7:])
args = [a for a in args if not a.startswith("cam=") and not a.startswith("radius=")]
yaw = math.radians(float(args[3]) if len(args) > 3 else 35)
elev = math.radians(float(args[4]) if len(args) > 4 else 12)
dist = float(args[5]) if len(args) > 5 else 13

bpy.ops.wm.read_factory_settings(use_empty=True)
parts = [p for p in json.load(open(path)) if (model_name == "*" or p.get("model") == model_name) and p["t"] < 1 and p["name"] != "SafetyFloor"]
R2B = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))
mats = {}

def material(rgb, name):
    key = (round(rgb[0], 3), round(rgb[1], 3), round(rgb[2], 3), name)
    if key not in mats:
        m = bpy.data.materials.new(f"{name}")
        m.use_nodes = True
        bsdf = m.node_tree.nodes["Principled BSDF"]
        bsdf.inputs["Base Color"].default_value = (*[c ** 2.2 for c in rgb], 1)
        bsdf.inputs["Roughness"].default_value = 0.35 if name in ("Metal", "DiamondPlate") else 0.6
        bsdf.inputs["Metallic"].default_value = 0.8 if name in ("Metal", "DiamondPlate") else 0.0
        if name == "Neon":
            bsdf.inputs["Emission Color"].default_value = (*rgb, 1)
            bsdf.inputs["Emission Strength"].default_value = 4
        mats[key] = m
    return mats[key]

if radius and cam_override:
    cx, cy, cz = cam_override[0]
    parts = [p for p in parts if (p["p"][0] - cx) ** 2 + (p["p"][2] - cz) ** 2 < radius * radius]
print("parts in view:", len(parts))
lo, hi = Vector((1e9,) * 3), Vector((-1e9,) * 3)
for p in parts:
    sx, sy, sz = p["s"]
    if p["shape"] == "Cylinder":
        bpy.ops.mesh.primitive_cylinder_add(vertices=32, radius=0.5, depth=1)
        o = bpy.context.object
        o.scale = (sy, sz, sx)
        local = Matrix.Rotation(math.radians(90), 4, "Y")  # Blender Z axis -> Roblox X axis
    elif p["shape"] == "Ball":
        bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, radius=0.5)
        o = bpy.context.object
        o.scale = (sx, sx, sx)
        local = Matrix.Identity(4)
    else:
        bpy.ops.mesh.primitive_cube_add(size=1)
        o = bpy.context.object
        o.scale = (sx, sy, sz)
        local = Matrix.Identity(4)
    r = p["r"]
    rot = Matrix(((r[0], r[1], r[2]), (r[3], r[4], r[5]), (r[6], r[7], r[8])))
    world = Matrix.Translation(R2B @ Vector(p["p"])) @ (R2B @ rot @ R2B.transposed()).to_4x4()
    # mesh is built in a "Roblox-local in Blender axes" frame: apply local axis fix then scale
    o.matrix_world = world @ (R2B.to_4x4()) @ local @ Matrix.Diagonal((*o.scale, 1))
    o.scale = o.scale  # keep
    o.data.materials.append(material(p["c"], p["mat"]))
    for v in o.bound_box:
        w = o.matrix_world @ Vector(v)
        lo = Vector(map(min, lo, w)); hi = Vector(map(max, hi, w))

center = (lo + hi) / 2
bpy.ops.mesh.primitive_plane_add(size=6000, location=(center.x, center.y, min(lo.z, 0.0) if model_name == "*" else lo.z))
bpy.context.object.data.materials.append(material((0.38, 0.55, 0.26) if model_name == "*" else (0.55, 0.56, 0.58), "Ground"))
cam_pos = center + Vector((math.cos(yaw) * math.cos(elev), math.sin(yaw) * math.cos(elev), math.sin(elev))) * dist
look_at = center
if cam_override:
    cam_pos = R2B @ Vector(cam_override[0])
    look_at = R2B @ Vector(cam_override[1])
bpy.ops.object.camera_add(location=cam_pos)
cam = bpy.context.object
cam.rotation_euler = (look_at - cam_pos).to_track_quat("-Z", "Y").to_euler()
cam.data.clip_end = 5000
cam.data.lens = 50
bpy.context.scene.camera = cam
bpy.ops.object.light_add(type="SUN", location=(0, 0, 10), rotation=(0.7, 0.2, 0.6))
bpy.context.object.data.energy = 3.5
world = bpy.data.worlds.new("W"); bpy.context.scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.62, 0.72, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.8
sc = bpy.context.scene
sc.render.engine = "CYCLES"; sc.cycles.device = "CPU"; sc.cycles.samples = 48
sc.render.resolution_x, sc.render.resolution_y = 960, 600
sc.render.filepath = out
bpy.ops.render.render(write_still=True)
print("rendered", len(parts), "parts ->", out)
