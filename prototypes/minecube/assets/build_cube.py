"""削角立方体，导出 GLB。

    /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup -noaudio -P build_cube.py

直接削角：八个顶点各被切掉一大块（球形切削），十二条棱保持原始的直边、
不做倒角。于是六个面仍是平面（四角被圆弧吃掉）、棱是一条清晰的直线、
角是一块大圆弧面。

着色上必须把六个平面设为平直：切削面和平面并不相切，交界本来就是一道折边。
整颗平滑的话，平面上的大多边形会被拉出斜纹。

产物 cube_rounded.glb：边长 1.0，原点在中心，Godot 里按尺寸缩放。
"""

import os

import bpy

OUT_DIR = os.path.dirname(os.path.abspath(__file__))
OUT_FILE = os.path.join(OUT_DIR, "cube_rounded.glb")

S = 1.0
CORNER_CUT = 0.30          # 沿棱从顶点往里切掉的距离
CORNER_SEGMENTS = 12


def main():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)

    bpy.ops.mesh.primitive_cube_add(size=S, location=(0, 0, 0))
    obj = bpy.context.active_object
    obj.name = "cube"

    bev = obj.modifiers.new("CornerCut", "BEVEL")
    bev.affect = "VERTICES"
    bev.width = CORNER_CUT
    bev.segments = CORNER_SEGMENTS
    bev.profile = 0.5
    bpy.ops.object.modifier_apply(modifier=bev.name)

    mesh = obj.data
    flat_faces = 0
    for poly in mesh.polygons:
        n = poly.normal
        axis = max(abs(n.x), abs(n.y), abs(n.z))
        poly.use_smooth = axis < 0.999
        if axis >= 0.999:
            flat_faces += 1

    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    dims = obj.dimensions
    print("faces %d  flat %d  dims %.3f %.3f %.3f" % (
        len(mesh.polygons), flat_faces, dims.x, dims.y, dims.z))

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
