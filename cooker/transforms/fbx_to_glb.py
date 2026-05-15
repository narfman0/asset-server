"""
Batch convert FBX files to glTF using Blender.
Usage: blender --background --python convert_fbx_to_gltf.py -- <input_dir> <output_dir> [--rename PRESET]

The optional --rename flag applies a bone-name remap during import. Use it for
animation packs whose bone naming doesn't match our cached Synty character GLBs.

Supported presets:
  mixamo  — Mixamo's `mixamorig:*` naming → Synty bone names
            (collapses Mixamo's 4-bone spine onto Synty's 3-bone spine)
"""
import bpy
import sys
import os
from pathlib import Path


# Bone-name remap presets. Apply during import: every imported bone whose
# original name is a key gets renamed to the value before glTF export.
# Bones not in the dict keep their original name.
#
# Mixamo → Synty: maps Adobe's mocap rig to the Synty POLYGON Humanoid rig.
# - Mixamo has 4 spine bones (Spine, Spine1, Spine2, Spine3); Synty has 3
#   (Spine_01..03). We map Spine→Spine_01, Spine1→Spine_02, Spine2→Spine_03.
#   The deepest spine (Spine3) maps to a "drop" name that won't match any
#   target bone — Bevy will silently skip those tracks. Body silhouette still
#   animates correctly via the three real spine bones.
# - Mixamo's LeftUpLeg/RightUpLeg → Synty's UpperLeg_L/_R (same for arms, etc.)
# - Mixamo's finger naming differs more substantially. We map the primary thumb
#   and index/middle bones; the rest fall through unmapped (right-hand fingers
#   are sub-pixel at our isometric zoom — invisible).
RENAME_PRESETS = {
    "mixamo": {
        "mixamorig:Hips":            "Hips",
        "mixamorig:Spine":           "Spine_01",
        "mixamorig:Spine1":          "Spine_02",
        "mixamorig:Spine2":          "Spine_03",
        "mixamorig:Spine3":          "_MIXAMO_DROP_Spine3",
        "mixamorig:Neck":            "Neck",
        "mixamorig:Head":            "Head",
        "mixamorig:HeadTop_End":     "_MIXAMO_DROP_HeadTop",

        "mixamorig:LeftShoulder":    "Clavicle_L",
        "mixamorig:LeftArm":         "Shoulder_L",
        "mixamorig:LeftForeArm":     "Elbow_L",
        "mixamorig:LeftHand":        "Hand_L",
        "mixamorig:LeftHandThumb1":  "Thumb_01",
        "mixamorig:LeftHandThumb2":  "Thumb_02",
        "mixamorig:LeftHandThumb3":  "Thumb_03",
        "mixamorig:LeftHandIndex1":  "IndexFinger_01",
        "mixamorig:LeftHandIndex2":  "IndexFinger_02",
        "mixamorig:LeftHandIndex3":  "IndexFinger_03",
        "mixamorig:LeftHandMiddle1": "Finger_01",
        "mixamorig:LeftHandMiddle2": "Finger_02",
        "mixamorig:LeftHandMiddle3": "Finger_03",

        "mixamorig:RightShoulder":   "Clavicle_R",
        "mixamorig:RightArm":        "Shoulder_R",
        "mixamorig:RightForeArm":    "Elbow_R",
        "mixamorig:RightHand":       "Hand_R",
        # Right-hand fingers stay unmapped; Synty character GLBs have them
        # under `.001` suffix due to a Blender import quirk. At our isometric
        # zoom these tracks no-op invisibly.

        "mixamorig:LeftUpLeg":       "UpperLeg_L",
        "mixamorig:LeftLeg":         "LowerLeg_L",
        "mixamorig:LeftFoot":        "Ankle_L",
        "mixamorig:LeftToeBase":     "Ball_L",
        "mixamorig:LeftToe_End":     "Toes_L",

        "mixamorig:RightUpLeg":      "UpperLeg_R",
        "mixamorig:RightLeg":        "LowerLeg_R",
        "mixamorig:RightFoot":       "Ankle_R",
        "mixamorig:RightToeBase":    "Ball_R",
        "mixamorig:RightToe_End":    "Toes_R",
    },
}


def apply_rename(rename_dict):
    """Rename every bone in every Armature in the currently-loaded scene."""
    if not rename_dict:
        return 0
    renamed = 0
    for obj in bpy.data.objects:
        if obj.type != 'ARMATURE':
            continue
        for bone in obj.data.bones:
            if bone.name in rename_dict:
                bone.name = rename_dict[bone.name]
                renamed += 1
    # Animation curves reference bone names via their data path
    # (`pose.bones["mixamorig:Hips"].rotation_quaternion`). Renaming bones in
    # the Armature automatically updates these because Blender uses live
    # references, not strings — provided we use bone.name = "..." rather than
    # editing through animation data directly.
    return renamed


def convert_fbx_to_gltf(fbx_path: Path, output_dir: Path, rename_dict: dict):
    output_dir.mkdir(parents=True, exist_ok=True)
    out_file = output_dir / (fbx_path.stem + ".glb")
    if out_file.exists():
        print(f"SKIP (exists): {out_file}")
        return

    bpy.ops.wm.read_factory_settings(use_empty=True)

    try:
        bpy.ops.import_scene.fbx(filepath=str(fbx_path))
    except Exception as e:
        print(f"ERROR importing {fbx_path}: {e}")
        return

    if rename_dict:
        n = apply_rename(rename_dict)
        if n:
            print(f"  RENAMED: {n} bones")

    try:
        bpy.ops.export_scene.gltf(
            filepath=str(out_file),
            export_format='GLB',
            export_materials='EXPORT',
            export_apply=True,
        )
        print(f"OK: {fbx_path.name} -> {out_file}")
    except Exception as e:
        print(f"ERROR exporting {fbx_path.name}: {e}")


def main():
    argv = sys.argv
    if "--" in argv:
        argv = argv[argv.index("--") + 1:]
    else:
        print("Usage: blender --background --python convert_fbx_to_gltf.py -- <input_dir> <output_dir> [--rename PRESET]")
        sys.exit(1)

    if len(argv) < 2:
        print("Need at least <input_dir> <output_dir>")
        sys.exit(1)

    input_dir = Path(argv[0])
    output_dir = Path(argv[1])

    rename_dict = {}
    if "--rename" in argv:
        idx = argv.index("--rename")
        if idx + 1 >= len(argv):
            print("--rename requires a preset name")
            sys.exit(1)
        preset = argv[idx + 1]
        if preset not in RENAME_PRESETS:
            print(f"Unknown rename preset: {preset}. Available: {list(RENAME_PRESETS.keys())}")
            sys.exit(1)
        rename_dict = RENAME_PRESETS[preset]
        print(f"Bone rename preset: {preset} ({len(rename_dict)} entries)")

    fbx_files = list(input_dir.rglob("*.fbx")) + list(input_dir.rglob("*.FBX"))
    print(f"Found {len(fbx_files)} FBX files in {input_dir}")

    for i, fbx in enumerate(fbx_files, 1):
        rel = fbx.relative_to(input_dir)
        out_subdir = output_dir / rel.parent
        print(f"[{i}/{len(fbx_files)}] {rel}")
        convert_fbx_to_gltf(fbx, out_subdir, rename_dict)


if __name__ == "__main__":
    main()
