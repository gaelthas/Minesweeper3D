"""生成扫雷用的立体水雷，导出 GLB。

Blender 无界面运行：
    /Applications/Blender.app/Contents/MacOS/Blender -b -P build_mine.py

产物：同目录下 mine.glb。整体外径约 0.80，正好装进边长 0.84 的方块格。
"""

import math
import os

import bpy
from mathutils import Vector

OUT_DIR = os.path.dirname(os.path.abspath(__file__))
OUT_FILE = os.path.join(OUT_DIR, "mine.glb")

BODY_RADIUS = 0.245
SPIKE_RADIUS = 0.058
SPIKE_DEPTH = 0.17
SPIKE_BASE = 0.225


def reset_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in (bpy.data.meshes, bpy.data.materials):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


def make_material(name, color, metallic, roughness):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (color[0], color[1], color[2], 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


def assign(obj, mat):
    obj.data.materials.clear()
    obj.data.materials.append(mat)


def build_body(mat):
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=48, ring_count=24, radius=BODY_RADIUS, location=(0, 0, 0)
    )
    obj = bpy.context.active_object
    obj.name = "mine_body"
    bpy.ops.object.shade_smooth()
    assign(obj, mat)
    return obj


def build_band(mat):
    bpy.ops.mesh.primitive_torus_add(
        major_radius=BODY_RADIUS + 0.018,
        minor_radius=0.024,
        major_segments=48,
        minor_segments=12,
        location=(0, 0, 0),
    )
    obj = bpy.context.active_object
    obj.name = "mine_band"
    bpy.ops.object.shade_smooth()
    assign(obj, mat)
    return obj


def spike_directions():
    """六个轴向 + 八个对角，共 14 根刺。"""
    dirs = [
        (1, 0, 0), (-1, 0, 0),
        (0, 1, 0), (0, -1, 0),
        (0, 0, 1), (0, 0, -1),
    ]
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                dirs.append((sx, sy, sz))
    return [Vector(d).normalized() for d in dirs]


def build_spikes(mat):
    objs = []
    for d in spike_directions():
        center = d * (SPIKE_BASE + SPIKE_DEPTH * 0.5)
        bpy.ops.mesh.primitive_cone_add(
            vertices=12,
            radius1=SPIKE_RADIUS,
            radius2=0.005,
            depth=SPIKE_DEPTH,
            location=center,
        )
        obj = bpy.context.active_object
        obj.name = "mine_spike"
        obj.rotation_euler = Vector((0, 0, 1)).rotation_difference(d).to_euler()
        assign(obj, mat)
        objs.append(obj)
    return objs


def main():
    reset_scene()

    body_mat = make_material("MineBody", (0.160, 0.172, 0.202), 0.45, 0.40)
    spike_mat = make_material("MineSpike", (0.262, 0.274, 0.310), 0.55, 0.28)
    band_mat = make_material("MineBand", (0.450, 0.470, 0.520), 0.60, 0.35)

    parts = [build_body(body_mat), build_band(band_mat)]
    parts += build_spikes(spike_mat)

    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()

    mine = bpy.context.active_object
    mine.name = "mine"
    mine.data.name = "mine_mesh"
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    bpy.ops.export_scene.gltf(
        filepath=OUT_FILE,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
    )
    print("exported:", OUT_FILE)


if __name__ == "__main__":
    main()
