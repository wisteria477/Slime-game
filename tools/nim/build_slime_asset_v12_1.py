"""
NIM SLIME V12.1 - Blender asset builder
------------------------------------
Purpose: generate the approved cute blue slime as a reusable Blender/Unreal prototype.
Targeted for Blender 5.2 LTS, but should also run on Blender 4.2+.

Outputs to: C:\\Users\\<you>\\NimSlimeOutputV12_1
Files:
- nim_slime_v12.blend
- nim_slime_v12.fbx
- nim_slime_v12.glb

This script is intentionally self-contained and rerun-safe.
"""
from pathlib import Path
import math
import bpy
from mathutils import Vector

# --------------------------- config ---------------------------
MIN_VERSION = (4, 2, 0)
VERSION_LABEL = '12.1'
ASSET_NAME = 'Nim_Slime_V12_1'
OUT_DIR = Path.home() / 'NimSlimeOutputV12_1'
EXPECTED_ACTIONS = ('Idle','Happy','Sad','Angry','Scared','Tired','Flirty')
EXPECTED_SHAPES = (
    'Basis','Squash','Stretch','Puddle','Happy','SadDroop',
    'AngryTense','ScaredTall','EmbarrassedShrink','TiredMelt','FlirtySway'
)
EXPECTED_BONES = ('root','body','head','arm.L','arm.R','antenna','eye.L','eye.R','mouth')

# --------------------------- helpers ---------------------------
def log(msg=''):
    print(msg)


def ensure_output_dir():
    if OUT_DIR.exists() and not OUT_DIR.is_dir():
        raise RuntimeError(f'Output path exists but is not a folder: {OUT_DIR}')
    OUT_DIR.mkdir(parents=True, exist_ok=True)


def preflight():
    if bpy.app.version < MIN_VERSION:
        raise RuntimeError(
            f'Nim Slime V12.1 requires Blender {MIN_VERSION[0]}.{MIN_VERSION[1]}+; '
            f'found {bpy.app.version_string}'
        )

    # Validate the exact Blender operators this build relies on BEFORE touching
    # the current scene. This catches API/add-on mismatches early and safely.
    required_ops = (
        ('object.voxel_remesh', bpy.ops.object, 'voxel_remesh'),
        ('export_scene.fbx', bpy.ops.export_scene, 'fbx'),
        ('export_scene.gltf', bpy.ops.export_scene, 'gltf'),
        ('import_scene.gltf', bpy.ops.import_scene, 'gltf'),
        ('wm.fbx_import', bpy.ops.wm, 'fbx_import'),
    )
    missing = [label for label, owner, attr in required_ops if not hasattr(owner, attr)]
    if missing:
        raise RuntimeError(f'Missing required Blender operators: {missing}')

    ensure_output_dir()
    log(f'Nim Slime V12.1 preflight: Blender {bpy.app.version_string}')
    log('API PREFLIGHT PASSED')
    log(f'Output folder: {OUT_DIR}')


def safe_remove(collection, predicate=None):
    for block in list(collection):
        if predicate is not None and not predicate(block):
            continue
        try:
            collection.remove(block)
        except Exception:
            pass


def wipe_scene():
    # Remove scene objects first.
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)

    # Remove only our prototype-ish data and orphaned leftovers.
    prefixes = ('Nim_', 'SK_Nim_', 'M_Slime_', 'M_Eye', 'M_Mouth', 'M_Cheek', 'M_Core', 'M_BodyHighlight')
    safe_remove(bpy.data.actions)
    safe_remove(bpy.data.meshes)
    safe_remove(bpy.data.curves)
    safe_remove(bpy.data.metaballs)
    safe_remove(bpy.data.armatures)
    safe_remove(bpy.data.materials, lambda m: m.name.startswith(prefixes))
    safe_remove(bpy.data.cameras, lambda c: c.name.startswith(prefixes))
    safe_remove(bpy.data.lights, lambda l: l.name.startswith(prefixes))


def set_socket(node, names, value):
    for n in names:
        sock = node.inputs.get(n)
        if sock is not None:
            sock.default_value = value
            return True
    return False


def make_principled(name, base, rough=0.25, metallic=0.0, transmission=0.0, alpha=1.0, ior=1.333, emission=None):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.diffuse_color = (*base[:3], alpha)
    nodes = mat.node_tree.nodes
    bsdf = nodes.get('Principled BSDF')
    set_socket(bsdf, ['Base Color'], (*base[:3], 1.0))
    set_socket(bsdf, ['Roughness'], rough)
    set_socket(bsdf, ['Metallic'], metallic)
    set_socket(bsdf, ['IOR'], ior)
    set_socket(bsdf, ['Transmission Weight', 'Transmission'], transmission)
    set_socket(bsdf, ['Alpha'], alpha)
    if emission:
        set_socket(bsdf, ['Emission Color', 'Emission'], (*emission[:3], 1.0))
        set_socket(bsdf, ['Emission Strength'], emission[3] if len(emission) > 3 else 0.15)
    if alpha < 1.0:
        try:
            mat.surface_render_method = 'DITHERED'
        except Exception:
            try:
                mat.blend_method = 'BLEND'
            except Exception:
                pass
        try:
            mat.use_transparency_overlap = False
        except Exception:
            pass
    return mat


def add_uv(name, loc, scale, material, segments=48, rings=32):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings, location=loc)
    ob = bpy.context.object
    ob.name = name
    ob.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    bpy.ops.object.shade_smooth()
    if material:
        ob.data.materials.append(material)
    return ob


def add_flat_mouth(name, loc, material):
    """Create the wide friendly open smile from the approved turnaround."""
    ob = add_uv(name, loc, (0.185, 0.016, 0.105), material, 40, 28)
    # Slight horizontal flattening gives the soft open-smile silhouette.
    return ob


def add_antenna(arm, material):
    """Create a short thick C-shaped jelly antenna without Bezier overshoot."""
    mb = bpy.data.metaballs.new('Nim_AntennaMeta')
    mb.resolution = 0.035
    mb.render_resolution = 0.025
    mb.threshold = 0.62
    ob = bpy.data.objects.new('Nim_AntennaMeta', mb)
    bpy.context.collection.objects.link(ob)

    points = [
        ((0.02, 0.00, 2.18), 0.145),
        ((0.06, 0.00, 2.30), 0.145),
        ((0.13, 0.00, 2.40), 0.140),
        ((0.23, 0.00, 2.48), 0.135),
        ((0.34, 0.00, 2.51), 0.130),
        ((0.41, 0.00, 2.47), 0.125),
        ((0.43, 0.00, 2.40), 0.120),
        ((0.39, 0.00, 2.34), 0.115),
    ]
    for co, radius in points:
        e = mb.elements.new()
        e.co = co
        e.radius = radius
        e.stiffness = 2.0

    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.convert(target='MESH')
    antenna = bpy.context.object
    antenna.name = 'Nim_Antenna'
    bpy.ops.object.shade_smooth()
    if material:
        antenna.data.materials.append(material)
    bone_parent(antenna, arm, 'antenna')
    return antenna


def bone_parent(ob, arm, bone_name):
    world = ob.matrix_world.copy()
    ob.parent = arm
    ob.parent_type = 'BONE'
    ob.parent_bone = bone_name
    bpy.context.view_layer.update()
    ob.matrix_world = world


def front_surface_y(body, x, z, radius_x=0.16, radius_z=0.20):
    candidates = [
        v.co.y for v in body.data.vertices
        if abs(v.co.x - x) <= radius_x and abs(v.co.z - z) <= radius_z
    ]
    if len(candidates) < 6:
        candidates = [
            v.co.y for v in body.data.vertices
            if abs(v.co.x - x) <= radius_x * 1.8 and abs(v.co.z - z) <= radius_z * 1.8
        ]
    if not candidates:
        candidates = [v.co.y for v in body.data.vertices]
    return min(candidates)

# --------------------------- body ---------------------------
def build_body(slime_mat):
    """Build a softer, reference-matched body: huge head, tiny pear torso, puddle feet."""
    pieces=[]

    def sphere(name, loc, scale, seg=48, rings=32):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=rings, location=loc)
        ob=bpy.context.object
        ob.name=name
        ob.scale=scale
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        pieces.append(ob)
        return ob

    # Head: dominant, wide and softly squashed rather than a perfect ball.
    sphere('Body_Head', (0.0, 0.00, 1.67), (0.95, 0.75, 0.70), 64, 40)
    sphere('Body_LowerFace', (0.0, -0.01, 1.31), (0.67, 0.54, 0.34), 56, 36)

    # Pear torso: narrower shoulders, rounder lower belly.
    sphere('Body_UpperTorso', (0.0, 0.02, 0.93), (0.46, 0.38, 0.38), 52, 34)
    sphere('Body_Belly', (0.0, 0.02, 0.62), (0.51, 0.42, 0.45), 56, 36)
    sphere('Body_NeckBridge', (0.0, 0.01, 1.16), (0.49, 0.40, 0.27), 48, 32)
    sphere('Body_LowerBridge', (0.0, 0.02, 0.34), (0.43, 0.36, 0.27), 44, 30)

    # Tiny droplet arms, low enough to read beside the torso.
    sphere('Arm_L_Upper', (-0.50, -0.01, 0.87), (0.145, 0.145, 0.205), 36, 24)
    sphere('Arm_L_Lower', (-0.515, -0.02, 0.72), (0.125, 0.125, 0.155), 32, 22)
    sphere('Arm_R_Upper', ( 0.50, -0.01, 0.87), (0.145, 0.145, 0.205), 36, 24)
    sphere('Arm_R_Lower', ( 0.515, -0.02, 0.72), (0.125, 0.125, 0.155), 32, 22)

    # Wide integrated puddle feet with a central notch.
    sphere('Foot_L', (-0.255, -0.07, 0.145), (0.315, 0.285, 0.125), 44, 28)
    sphere('Foot_R', ( 0.255, -0.07, 0.145), (0.315, 0.285, 0.125), 44, 28)
    sphere('Foot_Bridge', (0.0, -0.015, 0.245), (0.27, 0.25, 0.16), 40, 26)

    bpy.ops.object.select_all(action='DESELECT')
    for o in pieces:
        o.select_set(True)
    bpy.context.view_layer.objects.active=pieces[0]
    bpy.ops.object.join()
    body=bpy.context.object
    body.name='SK_Nim_Body'

    body.data.remesh_mode='VOXEL'
    body.data.remesh_voxel_size=0.024
    body.data.remesh_voxel_adaptivity=0.0
    bpy.context.view_layer.objects.active=body
    result=bpy.ops.object.voxel_remesh()
    if 'FINISHED' not in result:
        raise RuntimeError(f'Voxel remesh failed: {result}')

    sm=body.modifiers.new('ReferenceSurfaceSmooth','SMOOTH')
    sm.factor=0.13
    sm.iterations=2
    bpy.ops.object.modifier_apply(modifier=sm.name)
    bpy.ops.object.shade_smooth()

    target_verts=13500
    current=len(body.data.vertices)
    if current > target_verts*1.25:
        dec=body.modifiers.new('MobileSourceDecimate','DECIMATE')
        dec.decimate_type='COLLAPSE'
        dec.ratio=max(0.12,min(1.0,target_verts/current))
        dec.use_collapse_triangulate=False
        bpy.ops.object.modifier_apply(modifier=dec.name)

    if slime_mat:
        body.data.materials.append(slime_mat)
    return body

# --------------------------- rig ---------------------------
def build_rig():
    arm_data = bpy.data.armatures.new('Nim_Rig')
    arm = bpy.data.objects.new('Nim_Rig', arm_data)
    bpy.context.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')

    def ebone(name, head, tail, parent=None, connected=False):
        b = arm_data.edit_bones.new(name)
        b.head, b.tail = head, tail
        if parent:
            b.parent = arm_data.edit_bones[parent]
            b.use_connect = connected
        return b

    ebone('root', (0,0,0.03), (0,0,0.23))
    ebone('body', (0,0,0.22), (0,0,1.10), 'root')
    ebone('head', (0,0,1.02), (0,0,2.30), 'body')
    ebone('arm.L', (-0.30,0,1.06), (-0.56,-0.02,0.78), 'body')
    ebone('arm.R', ( 0.30,0,1.06), ( 0.56,-0.02,0.78), 'body')
    ebone('antenna', (0.02,0,2.12), (0.38,0,2.52), 'head')
    # Face-control bones. Separate controls let each emotion change the eyes/mouth
    # without requiring separate facial objects/actions.
    ebone('eye.L', (-0.30,-0.68,1.61), (-0.30,-0.68,1.83), 'head')
    ebone('eye.R', ( 0.30,-0.68,1.61), ( 0.30,-0.68,1.83), 'head')
    ebone('mouth', (0.0,-0.70,1.36), (0.0,-0.70,1.52), 'head')
    bpy.ops.object.mode_set(mode='POSE')
    for p in arm.pose.bones:
        p.rotation_mode = 'XYZ'
    bpy.ops.object.mode_set(mode='OBJECT')
    arm.show_in_front = False
    try:
        arm.data.display_type = 'STICK'
    except Exception:
        pass
    return arm


def assign_weights(body, arm):
    for n in ('root','body','head','arm.L','arm.R','antenna'):
        if n not in body.vertex_groups:
            body.vertex_groups.new(name=n)

    deform_bones = ('root','body','head','arm.L','arm.R','antenna')
    vg = {n: body.vertex_groups[n] for n in deform_bones}
    for v in body.data.vertices:
        x, y, z = v.co
        weights = {n:0.0 for n in deform_bones}
        weights['body'] = 1.0

        if z < 0.42:
            t = max(0.0, min(1.0, (0.42-z)/0.32))
            weights['root'] = 0.55*t
            weights['body'] = 1.0 - weights['root']

        if z > 1.04:
            t = max(0.0, min(1.0, (z-1.04)/0.46))
            weights['head'] = max(weights['head'], t)
            weights['body'] *= (1.0-t)

        if x < -0.35 and 0.58 < z < 1.48:
            t = max(0.0, min(1.0, (-x-0.35)/0.25))
            weights['arm.L'] = 0.85*t
            weights['body'] *= (1.0-0.85*t)
            weights['head'] *= (1.0-0.85*t)
        if x > 0.35 and 0.58 < z < 1.48:
            t = max(0.0, min(1.0, (x-0.35)/0.25))
            weights['arm.R'] = 0.85*t
            weights['body'] *= (1.0-0.85*t)
            weights['head'] *= (1.0-0.85*t)

        total = sum(weights.values()) or 1.0
        for n, w in weights.items():
            if w > 0.0001:
                vg[n].add([v.index], w/total, 'REPLACE')

    mod = body.modifiers.new('Armature', 'ARMATURE')
    mod.object = arm
    body.parent = arm

# --------------------------- shape keys ---------------------------
def add_shape_keys(body):
    basis = body.shape_key_add(name='Basis')
    basis.interpolation = 'KEY_LINEAR'
    source = [v.co.copy() for v in body.data.vertices]

    def make_key(name, fn):
        key = body.shape_key_add(name=name)
        for i, co in enumerate(source):
            key.data[i].co = fn(co.copy())
        key.value = 0.0
        return key

    pivot = 0.82
    make_key('Squash', lambda c: Vector((c.x*1.16, c.y*1.12, pivot+(c.z-pivot)*0.72)))
    make_key('Stretch', lambda c: Vector((c.x*0.86, c.y*0.90, pivot+(c.z-pivot)*1.24)))

    def puddle(c):
        z = 0.20 + (c.z-0.20)*0.48
        spread = 1.0 + 0.30*max(0.0, 1.0-min(c.z/2.6,1.0))
        return Vector((c.x*spread*1.18, c.y*spread*1.12, z))
    make_key('Puddle', puddle)

    make_key('Happy', lambda c: Vector((c.x*(1.02 if c.z < 1.2 else 0.97), c.y, c.z + 0.06*max(0, c.z-0.5)/2.5)))

    def sad(c):
        top = max(0.0, min(1.0, (c.z-0.8)/1.8))
        return Vector((c.x*(1.0+0.05*(1-top)), c.y, c.z-0.11*top))
    make_key('SadDroop', sad)

    make_key('AngryTense', lambda c: Vector((c.x*0.96, c.y*0.96, pivot+(c.z-pivot)*0.93)))
    make_key('ScaredTall', lambda c: Vector((c.x*0.88, c.y*0.90, pivot+(c.z-pivot)*1.16)))
    make_key('EmbarrassedShrink', lambda c: Vector((c.x*0.94, c.y*0.95, pivot+(c.z-pivot)*0.90)))

    def tired(c):
        top = max(0.0, min(1.0, (c.z-0.45)/2.4))
        return Vector((c.x*(1.0+0.16*(1-top)), c.y*(1.0+0.10*(1-top)), c.z*(0.72+0.12*top)))
    make_key('TiredMelt', tired)

    def flirty(c):
        top = max(0.0, min(1.0, (c.z-0.7)/2.0))
        return Vector((c.x+0.11*top, c.y, c.z))
    make_key('FlirtySway', flirty)

# --------------------------- details ---------------------------
def create_details(body, arm, mats):
    # Reference face sits low on the head with large glossy eyes and a wide smile.
    eye_l_s = front_surface_y(body, -0.30, 1.61)
    eye_r_s = front_surface_y(body,  0.30, 1.61)
    mouth_s = front_surface_y(body, 0.0, 1.34, 0.25, 0.18)
    cheek_l_s = front_surface_y(body, -0.43, 1.36, 0.15, 0.13)
    cheek_r_s = front_surface_y(body,  0.43, 1.36, 0.15, 0.13)

    eye_l_y = eye_l_s - 0.018
    eye_r_y = eye_r_s - 0.018
    mouth_y = mouth_s - 0.020
    cheek_l_y = cheek_l_s - 0.018
    cheek_r_y = cheek_r_s - 0.018

    eye_l = add_uv('Nim_Eye_L', (-0.30, eye_l_y, 1.60), (0.135, 0.020, 0.220), mats['eye'])
    eye_r = add_uv('Nim_Eye_R', ( 0.30, eye_r_y, 1.60), (0.135, 0.020, 0.220), mats['eye'])

    mouth = add_flat_mouth('Nim_Mouth', (0.0, mouth_y, 1.335), mats['mouth'])
    # Pink tongue/lower mouth inset.
    mouth_inner = add_uv('Nim_MouthInner', (0.0, mouth_y - 0.014, 1.292), (0.095, 0.009, 0.044), mats['mouth_inner'], 34, 22)

    cheek_l = add_uv('Nim_Cheek_L', (-0.43, cheek_l_y, 1.35), (0.075, 0.010, 0.040), mats['cheek'], 30, 18)
    cheek_r = add_uv('Nim_Cheek_R', ( 0.43, cheek_r_y, 1.35), (0.075, 0.010, 0.040), mats['cheek'], 30, 18)

    # Eye highlights.
    hl_l = add_uv('Nim_EyeHighlight_L', (-0.335, eye_l_y - 0.024, 1.695), (0.031, 0.006, 0.040), mats['highlight'], 22, 14)
    hl_r = add_uv('Nim_EyeHighlight_R', ( 0.265, eye_r_y - 0.024, 1.695), (0.031, 0.006, 0.040), mats['highlight'], 22, 14)
    hl_l2 = add_uv('Nim_EyeHighlight2_L', (-0.278, eye_l_y - 0.025, 1.655), (0.014, 0.005, 0.018), mats['highlight'], 18, 12)
    hl_r2 = add_uv('Nim_EyeHighlight2_R', ( 0.322, eye_r_y - 0.025, 1.655), (0.014, 0.005, 0.018), mats['highlight'], 18, 12)

    # Stylized body shine patches to match the glossy turnaround even in material preview.
    shine_l = add_uv('Nim_HeadShine_L', (-0.41, front_surface_y(body,-0.41,1.93)-0.025, 1.93), (0.18,0.006,0.055), mats['body_highlight'], 24, 16)
    shine_dot = add_uv('Nim_HeadShine_Dot', (0.43, front_surface_y(body,0.43,1.82)-0.026, 1.82), (0.040,0.005,0.027), mats['body_highlight'], 20, 12)

    # Warm glowing internal cloud.
    core_parts=[]
    for i,(loc,scale) in enumerate([
        ((0.00,0.11,0.68),(0.15,0.13,0.17)),
        ((-0.10,0.12,0.66),(0.11,0.10,0.13)),
        (( 0.10,0.12,0.65),(0.11,0.10,0.13)),
        (( 0.00,0.11,0.78),(0.12,0.11,0.13)),
    ]):
        c=add_uv(f'Nim_InnerCore_{i}',loc,scale,mats['core'],30,18)
        core_parts.append(c)

    antenna = add_antenna(arm, mats['slime'])
    bubble = add_uv('Nim_FloatingBubble', (0.55, -0.02, 2.46), (0.070, 0.070, 0.070), mats['slime'], 26, 16)

    bone_parent(eye_l, arm, 'eye.L')
    bone_parent(eye_r, arm, 'eye.R')
    for o in (hl_l,hl_r,hl_l2,hl_r2):
        bone_parent(o, arm, 'eye.L' if '_L' in o.name else 'eye.R')
    bone_parent(mouth, arm, 'mouth')
    bone_parent(mouth_inner, arm, 'mouth')
    for o in (cheek_l, cheek_r, shine_l, shine_dot, bubble):
        bone_parent(o, arm, 'head')
    for c in core_parts:
        bone_parent(c, arm, 'body')

    return {
        'eye_l': eye_l, 'eye_r': eye_r, 'mouth': mouth,
        'mouth_inner': mouth_inner, 'cheek_l': cheek_l, 'cheek_r': cheek_r,
        'hl_l': hl_l, 'hl_r': hl_r, 'hl_l2': hl_l2, 'hl_r2': hl_r2,
        'shine_l': shine_l, 'shine_dot': shine_dot,
        'core': core_parts[0], 'core_parts': core_parts,
        'antenna': antenna, 'bubble': bubble,
    }

# --------------------------- animation ---------------------------
def clear_pose(arm):
    for p in arm.pose.bones:
        p.location = (0,0,0)
        p.rotation_euler = (0,0,0)
        p.scale = (1,1,1)


def safe_action_flags(action, name, frame_range):
    if hasattr(action, 'use_frame_range'):
        action.use_frame_range = True
    if hasattr(action, 'frame_start'):
        action.frame_start = float(frame_range[0])
    if hasattr(action, 'frame_end'):
        action.frame_end = float(frame_range[1])
    # Only set if available on this Blender version.
    if hasattr(action, 'use_cyclic'):
        action.use_cyclic = name in {'Idle','Happy','Angry','Scared','Flirty'}


def create_action(arm, name, frames, keys):
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    arm.animation_data_create()
    arm.animation_data.action = action
    clear_pose(arm)

    # Start every action from an explicit neutral pose, then carry authored values
    # forward inside that action. This prevents stale values from a previous clip
    # while preserving an emotion (e.g. sad eyes) across later body-motion beats.
    current = {
        bone: {'loc': (0,0,0), 'rot': (0,0,0), 'scale': (1,1,1)}
        for bone in EXPECTED_BONES
    }
    for frame, transforms in keys:
        for bone_name, props in transforms.items():
            current[bone_name].update(props)
        for bone_name, props in current.items():
            p = arm.pose.bones[bone_name]
            p.location = props['loc']
            p.rotation_euler = props['rot']
            p.scale = props['scale']
            p.keyframe_insert('location', frame=frame, group=bone_name)
            p.keyframe_insert('rotation_euler', frame=frame, group=bone_name)
            p.keyframe_insert('scale', frame=frame, group=bone_name)

    safe_action_flags(action, name, frames)
    return action


def add_actions(arm):
    actions = []
    actions.append(create_action(arm, 'Idle', (1,48), [
        (1,  {'root':{'loc':(0,0,0)},'body':{'rot':(0,0,math.radians(-1.5)),'scale':(1.0,1.0,1.0)},'head':{'rot':(0,0,math.radians(1.0))},'antenna':{'rot':(0,math.radians(-3),0)},'eye.L':{'scale':(1,1,1)},'eye.R':{'scale':(1,1,1)},'mouth':{'scale':(1,1,1)}}),
        (13, {'root':{'loc':(0,0,0.035)},'body':{'rot':(0,0,math.radians(1.5)),'scale':(1.015,1.015,0.992)},'head':{'rot':(0,0,math.radians(-1.2))},'antenna':{'rot':(0,math.radians(4),0)}}),
        (25, {'root':{'loc':(0,0,0)},'body':{'rot':(0,0,math.radians(-1.0)),'scale':(1.0,1.0,1.0)},'head':{'rot':(0,0,math.radians(1.0))},'antenna':{'rot':(0,math.radians(-2),0)}}),
        (37, {'root':{'loc':(0,0,0.028)},'body':{'rot':(0,0,math.radians(1.0)),'scale':(1.012,1.012,0.994)},'head':{'rot':(0,0,math.radians(-0.8))},'antenna':{'rot':(0,math.radians(3),0)}}),
        (48, {'root':{'loc':(0,0,0)},'body':{'rot':(0,0,math.radians(-1.5)),'scale':(1.0,1.0,1.0)},'head':{'rot':(0,0,math.radians(1.0))},'antenna':{'rot':(0,math.radians(-3),0)},'eye.L':{'scale':(1,1,1)},'eye.R':{'scale':(1,1,1)},'mouth':{'scale':(1,1,1)}}),
    ]))
    actions.append(create_action(arm, 'Happy', (1,32), [
        (1, {'root':{'loc':(0,0,0)},'body':{'rot':(0,0,0),'scale':(1,1,1)},'arm.L':{'rot':(0,0,math.radians(-8))},'arm.R':{'rot':(0,0,math.radians(8))}}),
        (8, {'root':{'loc':(0,0,0.16)},'body':{'rot':(0,0,math.radians(4)),'scale':(0.96,0.96,1.08)},'arm.L':{'rot':(0,0,math.radians(-28))},'arm.R':{'rot':(0,0,math.radians(28))},'eye.L':{'scale':(1,1,0.50)},'eye.R':{'scale':(1,1,0.50)},'mouth':{'scale':(1.28,1,1.35)}}),
        (16,{'root':{'loc':(0,0,0)},'body':{'rot':(0,0,math.radians(-4)),'scale':(1.04,1.04,0.95)}}),
        (24,{'root':{'loc':(0,0,0.13)},'body':{'rot':(0,0,math.radians(3)),'scale':(0.97,0.97,1.06)}}),
        (32,{'root':{'loc':(0,0,0)},'body':{'rot':(0,0,0),'scale':(1,1,1)},'arm.L':{'rot':(0,0,math.radians(-8))},'arm.R':{'rot':(0,0,math.radians(8))}}),
    ]))
    actions.append(create_action(arm, 'Sad', (1,48), [
        (1, {'body':{'scale':(1,1,1)},'head':{'rot':(math.radians(5),0,0)},'arm.L':{'rot':(0,0,math.radians(8))},'arm.R':{'rot':(0,0,math.radians(-8))},'eye.L':{'scale':(1,1,0.78),'rot':(0,math.radians(-4),0)},'eye.R':{'scale':(1,1,0.78),'rot':(0,math.radians(4),0)},'mouth':{'scale':(0.90,1,0.48),'loc':(0,0,-0.015)}}),
        (24,{'root':{'loc':(0,0,-0.07)},'head':{'rot':(math.radians(13),0,math.radians(3))},'body':{'rot':(0,0,math.radians(-2)),'scale':(1.06,1.04,0.90)}}),
        (48,{'root':{'loc':(0,0,-0.05)},'body':{'scale':(1.07,1.05,0.88)},'head':{'rot':(math.radians(9),0,math.radians(-2))}}),
    ]))
    actions.append(create_action(arm, 'Angry', (1,36), [
        (1, {'root':{'loc':(0,0,0)},'body':{'rot':(0,0,math.radians(-2)),'scale':(1.03,1.03,0.96)},'arm.L':{'rot':(0,0,math.radians(16))},'arm.R':{'rot':(0,0,math.radians(-16))},'eye.L':{'scale':(1,1,0.65),'rot':(0,math.radians(-12),0)},'eye.R':{'scale':(1,1,0.65),'rot':(0,math.radians(12),0)},'mouth':{'scale':(1.15,1,0.35)}}),
        (6, {'root':{'loc':(-0.025,0,0)},'body':{'rot':(0,0,math.radians(3)),'scale':(1.05,1.05,0.94)}}),
        (12,{'root':{'loc':(0.025,0,0)},'body':{'rot':(0,0,math.radians(-3)),'scale':(1.05,1.05,0.94)}}),
        (18,{'root':{'loc':(-0.02,0,0)},'body':{'rot':(0,0,math.radians(2)),'scale':(1.04,1.04,0.95)}}),
        (24,{'root':{'loc':(0.02,0,0)},'body':{'rot':(0,0,math.radians(-2)),'scale':(1.04,1.04,0.95)}}),
        (36,{'root':{'loc':(0,0,0)},'body':{'rot':(0,0,math.radians(-2)),'scale':(1.03,1.03,0.96)},'arm.L':{'rot':(0,0,math.radians(16))},'arm.R':{'rot':(0,0,math.radians(-16))},'eye.L':{'scale':(1,1,0.65),'rot':(0,math.radians(-12),0)},'eye.R':{'scale':(1,1,0.65),'rot':(0,math.radians(12),0)},'mouth':{'scale':(1.15,1,0.35)}}),
    ]))
    actions.append(create_action(arm, 'Scared', (1,30), [
        (1, {'root':{'loc':(0,0,0)},'body':{'scale':(1,1,1)},'head':{'rot':(0,0,0)},'arm.L':{'rot':(0,0,math.radians(22))},'arm.R':{'rot':(0,0,math.radians(-22))},'eye.L':{'scale':(1.12,1,1.25)},'eye.R':{'scale':(1.12,1,1.25)},'mouth':{'scale':(0.82,1,1.55)}}),
        (5, {'root':{'loc':(-0.035,0,0.04)},'body':{'scale':(0.92,0.92,1.10)},'head':{'rot':(0,0,math.radians(-4))}}),
        (10,{'root':{'loc':(0.035,0,0.02)},'body':{'scale':(0.94,0.94,1.07)},'head':{'rot':(0,0,math.radians(4))}}),
        (15,{'root':{'loc':(-0.03,0,0.04)},'body':{'scale':(0.92,0.92,1.10)},'head':{'rot':(0,0,math.radians(-3))}}),
        (20,{'root':{'loc':(0.03,0,0.02)},'body':{'scale':(0.94,0.94,1.07)},'head':{'rot':(0,0,math.radians(3))}}),
        (30,{'root':{'loc':(0,0,0)},'body':{'scale':(1,1,1)},'head':{'rot':(0,0,0)},'arm.L':{'rot':(0,0,math.radians(22))},'arm.R':{'rot':(0,0,math.radians(-22))},'eye.L':{'scale':(1.12,1,1.25)},'eye.R':{'scale':(1.12,1,1.25)},'mouth':{'scale':(0.82,1,1.55)}}),
    ]))
    actions.append(create_action(arm, 'Tired', (1,60), [
        (1, {'root':{'loc':(0,0,0)},'body':{'scale':(1,1,1)},'head':{'rot':(math.radians(4),0,0)},'eye.L':{'scale':(1,1,0.45)},'eye.R':{'scale':(1,1,0.45)},'mouth':{'scale':(0.9,1,0.45)}}),
        (30,{'root':{'loc':(0,0,-0.14)},'body':{'scale':(1.10,1.08,0.86)},'head':{'rot':(math.radians(15),0,math.radians(4))},'arm.L':{'rot':(0,0,math.radians(10))},'arm.R':{'rot':(0,0,math.radians(-10))}}),
        (60,{'root':{'loc':(0,0,-0.18)},'body':{'scale':(1.13,1.10,0.82)},'head':{'rot':(math.radians(18),0,math.radians(-2))}}),
    ]))
    actions.append(create_action(arm, 'Flirty', (1,48), [
        (1, {'body':{'rot':(0,0,math.radians(-4)),'scale':(1,1,1)},'head':{'rot':(0,0,math.radians(7))},'arm.R':{'rot':(0,0,0)},'eye.L':{'scale':(1,1,0.35)},'eye.R':{'scale':(1,1,0.90)},'mouth':{'scale':(1.08,1,0.70),'rot':(0,math.radians(-5),0)}}),
        (12,{'body':{'rot':(0,0,math.radians(4)),'scale':(0.985,0.985,1.03)},'head':{'rot':(0,0,math.radians(-8))},'arm.R':{'rot':(0,0,math.radians(-12))}}),
        (24,{'body':{'rot':(0,0,math.radians(-4)),'scale':(1,1,1)},'head':{'rot':(0,0,math.radians(7))}}),
        (36,{'body':{'rot':(0,0,math.radians(4)),'scale':(0.985,0.985,1.03)},'head':{'rot':(0,0,math.radians(-8))}}),
        (48,{'body':{'rot':(0,0,math.radians(-4)),'scale':(1,1,1)},'head':{'rot':(0,0,math.radians(7))},'arm.R':{'rot':(0,0,0)},'eye.L':{'scale':(1,1,0.35)},'eye.R':{'scale':(1,1,0.90)},'mouth':{'scale':(1.08,1,0.70),'rot':(0,math.radians(-5),0)}}),
    ]))
    arm.animation_data.action = actions[0]
    return actions

# --------------------------- mesh integrity ---------------------------
def connected_component_sizes(mesh):
    """Return vertex counts for every connected mesh island, largest first."""
    adjacency = [[] for _ in mesh.vertices]
    for e in mesh.edges:
        a, b = e.vertices
        adjacency[a].append(b)
        adjacency[b].append(a)
    seen = set()
    sizes = []
    for i in range(len(mesh.vertices)):
        if i in seen:
            continue
        stack = [i]
        seen.add(i)
        count = 0
        while stack:
            cur = stack.pop()
            count += 1
            for nb in adjacency[cur]:
                if nb not in seen:
                    seen.add(nb)
                    stack.append(nb)
        sizes.append(count)
    sizes.sort(reverse=True)
    return sizes


def connected_component_count(mesh):
    return len(connected_component_sizes(mesh))

# --------------------------- validation ---------------------------
def smoke_test_actions(arm):
    scene = bpy.context.scene
    saved_frame = scene.frame_current
    saved_action = arm.animation_data.action if arm.animation_data else None
    for name in EXPECTED_ACTIONS:
        action = bpy.data.actions.get(name)
        if action is None:
            raise RuntimeError(f'Animation smoke test missing action: {name}')
        arm.animation_data.action = action
        start = int(round(action.frame_range[0]))
        end = int(round(action.frame_range[1]))
        mid = (start + end) // 2
        for frame in sorted({start, mid, end}):
            scene.frame_set(frame)
            bpy.context.view_layer.update()
            for pb in arm.pose.bones:
                vals = list(pb.location) + list(pb.rotation_euler) + list(pb.scale)
                if not all(math.isfinite(float(v)) for v in vals):
                    raise RuntimeError(f'Non-finite pose value in {name}, bone {pb.name}, frame {frame}')
                if min(float(v) for v in pb.scale) <= 0.0:
                    raise RuntimeError(f'Invalid non-positive bone scale in {name}, bone {pb.name}, frame {frame}')
    arm.animation_data.action = saved_action
    scene.frame_set(saved_frame)
    bpy.context.view_layer.update()
    log('ANIMATION SMOKE TEST PASSED')


def validate_asset(body, arm, details):
    actual_bones = set(arm.data.bones.keys())
    missing_bones = set(EXPECTED_BONES) - actual_bones
    if missing_bones:
        raise RuntimeError(f'Missing rig bones: {sorted(missing_bones)}')

    actual_shapes = set(body.data.shape_keys.key_blocks.keys()) if body.data.shape_keys else set()
    missing_shapes = set(EXPECTED_SHAPES) - actual_shapes
    if missing_shapes:
        raise RuntimeError(f'Missing shape keys: {sorted(missing_shapes)}')

    # Validate face placement in a true neutral/rest pose, not in whatever
    # emotion/action happened to be authored last.
    saved_action = arm.animation_data.action if arm.animation_data else None
    arm.animation_data.action = None
    clear_pose(arm)
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()

    probes = {
        'eye_l': (-0.30, 1.62, 0.18, 0.24),
        'eye_r': ( 0.30, 1.62, 0.18, 0.24),
        'mouth': (0.0, 1.34, 0.24, 0.18),
        'cheek_l': (-0.43, 1.35, 0.15, 0.13),
        'cheek_r': ( 0.43, 1.35, 0.15, 0.13),
    }
    for key, (x, z, rx, rz) in probes.items():
        surf = front_surface_y(body, x, z, rx, rz)
        center_y = details[key].matrix_world.translation.y
        if abs(center_y - surf) > 0.05:
            raise RuntimeError(
                f'{key} is too far from body surface: center_y={center_y:.3f}, surface_y={surf:.3f}'
            )

    arm.animation_data.action = saved_action
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()

    # Validate all basis/key coordinates are finite before we save or export.
    for v in body.data.vertices:
        if not all(math.isfinite(float(q)) for q in v.co):
            raise RuntimeError(f'Non-finite body vertex at index {v.index}')
    for kb in body.data.shape_keys.key_blocks:
        for i, pt in enumerate(kb.data):
            if not all(math.isfinite(float(q)) for q in pt.co):
                raise RuntimeError(f'Non-finite shape key coordinate in {kb.name} at index {i}')

    missing_actions = set(EXPECTED_ACTIONS) - set(bpy.data.actions.keys())
    if missing_actions:
        raise RuntimeError(f'Missing animation actions: {sorted(missing_actions)}')

    component_sizes = connected_component_sizes(body.data)
    components = len(component_sizes)
    if components != 1:
        raise RuntimeError(
            f'Body mesh is not continuous: found {components} disconnected components '
            f'with vertex counts {component_sizes}. V12 refuses to save a broken slime.'
        )
    log(f'BODY CONNECTIVITY PASSED: 1 component, {component_sizes[0]} vertices')

    if len(body.data.vertices) < 500:
        raise RuntimeError('Body mesh unexpectedly low resolution.')

    for key in ('eye_l','eye_r','mouth','mouth_inner','cheek_l','cheek_r','hl_l','hl_r'):
        if details[key].parent != arm:
            raise RuntimeError(f'{key} is not parented to the rig.')

    smoke_test_actions(arm)
    log('PRE-SAVE VALIDATION PASSED')

# --------------------------- export ---------------------------
def export_selected(arm, body):
    bpy.ops.object.select_all(action='DESELECT')
    arm.select_set(True)
    body.select_set(True)
    for o in bpy.context.scene.objects:
        if o.parent == arm:
            o.select_set(True)
    bpy.context.view_layer.objects.active = arm


def _snapshot_import_state():
    return {
        'objects': set(bpy.data.objects.keys()),
        'actions': set(bpy.data.actions.keys()),
        'collections': set(bpy.data.collections.keys()),
        'meshes': set(bpy.data.meshes.keys()),
        'armatures': set(bpy.data.armatures.keys()),
        'materials': set(bpy.data.materials.keys()),
        'images': set(bpy.data.images.keys()),
    }


def _cleanup_imported(before):
    # Delete imported objects first, then the orphaned data blocks/collections
    # created by round-trip testing. This prevents glTF helper collections such
    # as `glTF_not_exported` from leaking into the final .blend.
    for o in list(bpy.data.objects):
        if o.name not in before['objects']:
            try:
                bpy.data.objects.remove(o, do_unlink=True)
            except Exception:
                pass
    for a in list(bpy.data.actions):
        if a.name not in before['actions']:
            try:
                bpy.data.actions.remove(a)
            except Exception:
                pass
    for c in list(bpy.data.collections):
        if c.name not in before['collections']:
            try:
                bpy.data.collections.remove(c)
            except Exception:
                pass
    for datablocks, key in (
        (bpy.data.meshes, 'meshes'),
        (bpy.data.armatures, 'armatures'),
        (bpy.data.materials, 'materials'),
        (bpy.data.images, 'images'),
    ):
        for d in list(datablocks):
            if d.name not in before[key] and getattr(d, 'users', 0) == 0:
                try:
                    datablocks.remove(d)
                except Exception:
                    pass


def roundtrip_validate_export(path, kind):
    before = _snapshot_import_state()
    try:
        if kind == 'GLB':
            result = bpy.ops.import_scene.gltf(filepath=str(path), import_select_created_objects=True)
        elif kind == 'FBX':
            result = bpy.ops.wm.fbx_import(filepath=str(path), use_anim=True)
        else:
            raise ValueError(kind)
        if 'FINISHED' not in result:
            raise RuntimeError(f'{kind} round-trip importer returned {result}')

        imported = [o for o in bpy.data.objects if o.name not in before['objects']]
        if not imported:
            raise RuntimeError(f'{kind} round-trip imported no objects')
        if not any(o.type == 'ARMATURE' for o in imported):
            raise RuntimeError(f'{kind} round-trip imported no armature')
        imported_meshes = [o for o in imported if o.type == 'MESH']
        if not imported_meshes:
            raise RuntimeError(f'{kind} round-trip imported no mesh')
        # glTF is our morph-preserving interchange file. Blender 5.2's legacy
        # FBX exporter does not write vertex shape keys, so do not falsely fail
        # the FBX round-trip on a documented exporter limitation.
        if kind == 'GLB':
            found_shapes = False
            for mesh_ob in imported_meshes:
                sk = getattr(mesh_ob.data, 'shape_keys', None)
                if sk and set(EXPECTED_SHAPES).issubset(set(sk.key_blocks.keys())):
                    found_shapes = True
                    break
            if not found_shapes:
                raise RuntimeError('GLB round-trip did not preserve the expected morph targets')

        new_actions = [a for a in bpy.data.actions if a.name not in before['actions']]
        minimum_actions = len(EXPECTED_ACTIONS) if kind == 'GLB' else 1
        if len(new_actions) < minimum_actions:
            raise RuntimeError(
                f'{kind} round-trip imported only {len(new_actions)} actions; expected at least {minimum_actions}'
            )
        log(f'{kind} ROUND-TRIP VALIDATION PASSED')
    finally:
        _cleanup_imported(before)


def main():
    preflight()
    wipe_scene()

    mats = {
        'slime': make_principled('M_Slime_Blue', (0.28,0.70,1.00), rough=0.045, transmission=0.16, alpha=1.0, ior=1.333),
        'eye': make_principled('M_Eye', (0.012,0.025,0.055), rough=0.16),
        'mouth': make_principled('M_Mouth', (0.02,0.03,0.06), rough=0.22),
        'mouth_inner': make_principled('M_MouthInner', (0.96,0.35,0.55), rough=0.28),
        'highlight': make_principled('M_EyeHighlight', (0.95,0.98,1.0), rough=0.08),
        'cheek': make_principled('M_Cheek', (1.0,0.38,0.52), rough=0.35, transmission=0.08, alpha=0.50),
        'core': make_principled('M_Core', (1.0,0.90,0.48), rough=0.10, transmission=0.12, alpha=0.90, emission=(1.0,0.78,0.26,1.60)),
        'body_highlight': make_principled('M_BodyHighlight', (0.98,1.0,1.0), rough=0.02, transmission=0.05, alpha=0.68),
    }

    slime_bsdf = mats['slime'].node_tree.nodes.get('Principled BSDF')
    set_socket(slime_bsdf, ['Coat Weight','Clearcoat'], 0.88)
    set_socket(slime_bsdf, ['Coat Roughness','Clearcoat Roughness'], 0.025)
    set_socket(slime_bsdf, ['Subsurface Weight','Subsurface'], 0.12)

    body = build_body(mats['slime'])
    arm = build_rig()
    assign_weights(body, arm)
    add_shape_keys(body)
    details = create_details(body, arm, mats)
    add_actions(arm)
    validate_asset(body, arm, details)

    arm['slime_asset_version'] = VERSION_LABEL
    arm['approved_visual_target'] = 'glossy_blue_slime_turnaround_2026-09-27'
    arm['emotion_morphs'] = 'Happy,SadDroop,AngryTense,ScaredTall,EmbarrassedShrink,TiredMelt,FlirtySway'
    body['runtime_note'] = 'Drive shape keys + material parameters on top of skeletal animation for slime feel.'

    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = 60
    bpy.context.scene.render.fps = 30

    blend_path = OUT_DIR / 'nim_slime_v12_1.blend'
    fbx_path = OUT_DIR / 'nim_slime_v12_1.fbx'
    glb_path = OUT_DIR / 'nim_slime_v12_1.glb'

    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))
    export_selected(arm, body)

    # Remove stale exports so a previous successful run can never mask a new failure.
    for stale in (fbx_path, glb_path):
        try:
            if stale.exists():
                stale.unlink()
        except Exception as e:
            raise RuntimeError(f'Could not clear old export {stale}: {e}')

    try:
        result = bpy.ops.export_scene.fbx(
            filepath=str(fbx_path),
            check_existing=False,
            use_selection=True,
            object_types={'ARMATURE','MESH'},
            add_leaf_bones=False,
            bake_anim=True,
            bake_anim_use_nla_strips=False,
            bake_anim_use_all_actions=True,
            bake_anim_force_startend_keying=True,
            bake_anim_simplify_factor=0.0,
            use_custom_props=True,
            apply_scale_options='FBX_SCALE_UNITS',
            axis_forward='-Z', axis_up='Y'
        )
        if 'FINISHED' not in result:
            raise RuntimeError(f'FBX exporter returned {result}')
    except Exception as e:
        raise RuntimeError(f'FBX EXPORT FAILED: {e}') from e

    try:
        result = bpy.ops.export_scene.gltf(
            filepath=str(glb_path),
            check_existing=False,
            export_format='GLB',
            use_selection=True,
            export_animations=True,
            export_animation_mode='BROADCAST',
            export_force_sampling=True,
            export_reset_pose_bones=True,
            export_morph=True,
            export_morph_animation=True,
            export_skins=True
        )
        if 'FINISHED' not in result:
            raise RuntimeError(f'GLB exporter returned {result}')
    except Exception as e:
        raise RuntimeError(f'GLB EXPORT FAILED: {e}') from e

    # Do not print COMPLETE unless all three deliverables really exist.
    for output in (blend_path, fbx_path, glb_path):
        if not output.exists() or output.stat().st_size < 1024:
            raise RuntimeError(f'POST-EXPORT VALIDATION FAILED: missing/empty {output}')

    # Re-import both exchange formats in the same Blender version. This catches
    # corrupt exports, missing rigs, missing morphs, and missing animation stacks.
    roundtrip_validate_export(glb_path, 'GLB')
    roundtrip_validate_export(fbx_path, 'FBX')
    log('POST-EXPORT VALIDATION PASSED')

    # Present the character cleanly when the generated .blend is opened.
    try:
        arm.hide_set(True)
    except Exception:
        pass
    bpy.context.view_layer.objects.active = body
    body.select_set(True)

    # Save in Layout + Material Preview when running interactively, so opening
    # the generated .blend presents the slime instead of a wall of script text.
    try:
        if bpy.context.window and bpy.data.workspaces.get('Layout'):
            bpy.context.window.workspace = bpy.data.workspaces.get('Layout')
            for area in bpy.context.window.screen.areas:
                if area.type == 'VIEW_3D':
                    area.spaces.active.shading.type = 'MATERIAL'
    except Exception:
        pass
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path))

    log('\nNIM SLIME V12.1 COMPLETE')
    log(f'Blend: {blend_path}')
    log(f'FBX  : {fbx_path}')
    log(f'GLB  : {glb_path}')


if __name__ == '__main__':
    main()
