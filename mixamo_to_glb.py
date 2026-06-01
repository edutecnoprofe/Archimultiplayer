"""
Mixamo FBX → GLB para Godot (Blender 5.1)
Combina un personaje base con múltiples animaciones en un único .glb
"""
import bpy
import os

FBX_DIR  = r"C:\Users\eduna\Documents\arquitecto-multiplayer\FBX para procesar"
OUTPUT_DIR = r"C:\Users\eduna\Documents\arquitecto-multiplayer"

CHARACTERS = {
    "Male":   "MALE Y Bot.fbx",
    "Female": "Female Bot.fbx",
}

ANIMATION_FILES = [
    "Climbing Up Wall.fbx",
    "Happy Idle.fbx",
    "Jump.fbx",
    "Left Turn.fbx",
    "Right Turn.fbx",
    "Walking Backwards.fbx",
    "Walking.fbx",
]

IMPORT_OPTS = dict(
    use_anim=True,
    automatic_bone_orientation=True,
    ignore_leaf_bones=True,
    force_connect_children=False,
    use_custom_normals=True,
    use_image_search=False,
)


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=True)
    # Purge orphan data blocks
    for _ in range(3):
        bpy.ops.outliner.orphans_purge(do_recursive=True)


def import_fbx(path):
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.fbx(filepath=path, **IMPORT_OPTS)
    return set(bpy.context.scene.objects) - before


def first_armature(objects):
    for obj in objects:
        if obj.type == "ARMATURE":
            return obj
    return None


def safe_remove_objects(objects):
    """Remove a set of objects without crashing on already-removed ones."""
    for obj in list(objects):
        if obj.name in bpy.data.objects:
            bpy.data.objects.remove(obj, do_unlink=True)


def process_character(char_name, char_file):
    print(f"\n{'='*60}")
    print(f"Procesando: {char_name}")
    print(f"{'='*60}")

    clear_scene()

    # --- Importar personaje base ---
    char_path = os.path.join(FBX_DIR, char_file)
    print(f"  Importando personaje: {char_file}")
    char_objects = import_fbx(char_path)
    armature = first_armature(char_objects)
    if armature is None:
        print(f"  ERROR: No se encontró armature en {char_file}")
        return

    print(f"  Armature: {armature.name}")

    # Limpiar cualquier acción que traiga el propio FBX del personaje
    if armature.animation_data:
        if armature.animation_data.action:
            armature.animation_data.action = None
        armature.animation_data_clear()
    armature.animation_data_create()

    # --- Importar cada animación y transferir al armature del personaje ---
    for anim_file in ANIMATION_FILES:
        anim_name = os.path.splitext(anim_file)[0]
        anim_path = os.path.join(FBX_DIR, anim_file)
        print(f"  Animación: {anim_name}")

        anim_objects = import_fbx(anim_path)
        anim_arm    = first_armature(anim_objects)

        if anim_arm is None:
            print(f"    WARN: Sin armature en {anim_file}, saltando")
            safe_remove_objects(anim_objects)
            continue

        if anim_arm.animation_data is None or anim_arm.animation_data.action is None:
            print(f"    WARN: Sin acción en {anim_file}, saltando")
            safe_remove_objects(anim_objects)
            continue

        src_action = anim_arm.animation_data.action
        src_action.name = anim_name
        src_action.use_fake_user = True   # mantener viva la acción

        # Desvincular del armature temporal antes de borrarlo
        anim_arm.animation_data.action = None

        # Crear NLA track en el armature del personaje
        track = armature.animation_data.nla_tracks.new()
        track.name = anim_name

        start = int(src_action.frame_range[0])
        end   = int(src_action.frame_range[1])
        strip = track.strips.new(anim_name, start, src_action)
        strip.name            = anim_name
        strip.frame_start     = start
        strip.frame_end       = end
        strip.action_frame_start = start
        strip.action_frame_end   = end
        print(f"    OK: frames {start}–{end}")

        # Borrar objetos de animación temporal
        safe_remove_objects(anim_objects)

    # --- Exportar GLB ---
    output_path = os.path.join(OUTPUT_DIR, f"{char_name}.glb")
    print(f"\n  Exportando → {output_path}")

    bpy.ops.object.select_all(action="SELECT")

    bpy.ops.export_scene.gltf(
        filepath=output_path,
        export_format="GLB",
        # Animaciones: exportar cada NLA track como animación separada
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_bake_animation=True,
        export_force_sampling=True,
        export_optimize_animation_size=True,
        export_optimize_animation_keep_anim_armature=True,
        export_optimize_animation_keep_anim_object=False,
        export_reset_pose_bones=True,
        export_rest_position_armature=True,
        export_anim_slide_to_zero=True,
        # Mesh / rig
        export_apply=False,
        export_skins=True,
        export_texcoords=True,
        export_normals=True,
        export_yup=True,
        # Materiales
        export_materials="EXPORT",
    )
    print(f"  Exportado correctamente.")


def main():
    print("\nMixamo FBX → GLB para Godot")
    print(f"FBX dir : {FBX_DIR}")
    print(f"Out dir : {OUTPUT_DIR}\n")

    for char_name, char_file in CHARACTERS.items():
        try:
            process_character(char_name, char_file)
        except Exception as e:
            import traceback
            print(f"\nERROR procesando {char_name}: {e}")
            traceback.print_exc()

    print("\n\nFINALIZADO.")


main()
