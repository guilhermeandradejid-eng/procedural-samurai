#!/usr/bin/env python3
"""Generates project.godot (settings, input map, shader globals, layers).

Run from the repository root:  python3 tools/project/make_project.py
The Godot editor may later rewrite the file; this script is only the
reproducible starting point for the project configuration.
"""
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

KEY = {
    "SPACE": 32, "SHIFT": 4194325, "CTRL": 4194326, "ALT": 4194328, "TAB": 4194306,
    "ESC": 4194305, "ENTER": 4194309, "UP": 4194320, "DOWN": 4194322, "LEFT": 4194319,
    "RIGHT": 4194321, "F1": 4194332, "F2": 4194333, "F3": 4194334, "F4": 4194335,
    "F5": 4194336, "F9": 4194340, "F11": 4194342, "F12": 4194343,
}
for c in "ABCDEFGHIJKLMNOPQRSTUVWXYZ":
    KEY[c] = ord(c)

MOUSE = {"LMB": 1, "RMB": 2, "MMB": 3, "XB1": 8, "XB2": 9}
JOYB = {"A": 0, "B": 1, "X": 2, "Y": 3, "BACK": 4, "START": 6, "L3": 7, "R3": 8,
        "LB": 9, "RB": 10, "DUP": 11, "DDOWN": 12, "DLEFT": 13, "DRIGHT": 14}
JOYA = {"LX": 0, "LY": 1, "RX": 2, "RY": 3, "LT": 4, "RT": 5}

# action: (deadzone, [events])  events: ("key", name) ("mouse", name) ("joyb", name) ("joya", axis, value)
ACTIONS = {
    "move_forward": (0.2, [("key", "W"), ("key", "UP"), ("joya", "LY", -1.0)]),
    "move_back": (0.2, [("key", "S"), ("key", "DOWN"), ("joya", "LY", 1.0)]),
    "move_left": (0.2, [("key", "A"), ("key", "LEFT"), ("joya", "LX", -1.0)]),
    "move_right": (0.2, [("key", "D"), ("key", "RIGHT"), ("joya", "LX", 1.0)]),
    "look_left": (0.15, [("joya", "RX", -1.0)]),
    "look_right": (0.15, [("joya", "RX", 1.0)]),
    "look_up": (0.15, [("joya", "RY", -1.0)]),
    "look_down": (0.15, [("joya", "RY", 1.0)]),
    "attack_light": (0.5, [("mouse", "LMB"), ("joyb", "X")]),
    "attack_heavy": (0.5, [("key", "E"), ("mouse", "XB1"), ("joyb", "Y")]),
    "block": (0.5, [("mouse", "RMB"), ("joyb", "LB")]),
    "dodge": (0.5, [("key", "SPACE"), ("joyb", "B")]),
    "sprint": (0.5, [("key", "SHIFT"), ("joyb", "L3")]),
    "jump": (0.5, [("key", "V"), ("joyb", "A")]),
    "crouch": (0.5, [("key", "C"), ("key", "CTRL"), ("joya", "LT", 1.0)]),
    "interact": (0.5, [("key", "F"), ("joyb", "RB")]),
    "heal": (0.5, [("key", "R"), ("joyb", "DUP")]),
    "guiding_wind": (0.5, [("key", "T"), ("joyb", "DDOWN")]),
    "standoff": (0.5, [("key", "G"), ("joyb", "DLEFT")]),
    "lock_on": (0.5, [("key", "TAB"), ("mouse", "MMB"), ("joyb", "R3")]),
    "pause": (0.5, [("key", "ESC"), ("joyb", "START")]),
    "map": (0.5, [("key", "M"), ("joyb", "BACK")]),
    "toggle_help": (0.5, [("key", "F1")]),
    "photo_mode": (0.5, [("key", "F2")]),
    "kurosawa": (0.5, [("key", "F3")]),
    "debug_stats": (0.5, [("key", "F4")]),
    "fullscreen": (0.5, [("key", "F11")]),
    "screenshot": (0.5, [("key", "F12")]),
}


def ev_key(name):
    return ('Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,'
            '"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,'
            '"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":%d,"key_label":0,'
            '"unicode":0,"location":0,"echo":false,"script":null)' % KEY[name])


def ev_mouse(name):
    return ('Object(InputEventMouseButton,"resource_local_to_scene":false,"resource_name":"",'
            '"device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,'
            '"meta_pressed":false,"button_mask":0,"position":Vector2(0, 0),"global_position":Vector2(0, 0),'
            '"factor":1.0,"button_index":%d,"canceled":false,"pressed":false,"double_click":false,'
            '"script":null)' % MOUSE[name])


def ev_joyb(name):
    return ('Object(InputEventJoypadButton,"resource_local_to_scene":false,"resource_name":"",'
            '"device":-1,"button_index":%d,"pressure":0.0,"pressed":false,"script":null)' % JOYB[name])


def ev_joya(axis, value):
    return ('Object(InputEventJoypadMotion,"resource_local_to_scene":false,"resource_name":"",'
            '"device":-1,"axis":%d,"axis_value":%.1f,"script":null)' % (JOYA[axis], value))


def input_section():
    out = ["[input]", ""]
    for action, (dz, events) in ACTIONS.items():
        evs = []
        for e in events:
            if e[0] == "key":
                evs.append(ev_key(e[1]))
            elif e[0] == "mouse":
                evs.append(ev_mouse(e[1]))
            elif e[0] == "joyb":
                evs.append(ev_joyb(e[1]))
            else:
                evs.append(ev_joya(e[1], e[2]))
        out.append("%s={" % action)
        out.append('"deadzone": %s,' % dz)
        out.append('"events": [' + "\n, ".join(evs) + "\n]")
        out.append("}")
    return "\n".join(out) + "\n"


GLOBALS = [
    ("wind_dir", "vec2", "Vector2(0.93, 0.37)"),
    ("wind_strength", "float", "1.0"),
    ("wind_time", "float", "0.0"),
    ("guide_wind", "float", "0.0"),
    ("player_pos", "vec3", "Vector3(0, 0, 0)"),
    ("lod_center", "vec3", "Vector3(0, 0, 0)"),
    ("trample_0", "vec4", "Vector4(0, -1000, 0, 0)"),
    ("trample_1", "vec4", "Vector4(0, -1000, 0, 0)"),
    ("trample_2", "vec4", "Vector4(0, -1000, 0, 0)"),
    ("trample_3", "vec4", "Vector4(0, -1000, 0, 0)"),
    ("sun_dir", "vec3", "Vector3(0.3, 0.5, 0.8)"),
    ("sun_color", "color", "Color(1, 0.85, 0.6, 1)"),
    ("ambient_color", "color", "Color(0.4, 0.45, 0.55, 1)"),
    ("fog_color", "color", "Color(0.75, 0.7, 0.65, 1)"),
    ("wetness", "float", "0.0"),
    ("rain_amount", "float", "0.0"),
    ("snow_amount", "float", "0.0"),
    ("terrain_info", "vec4", "Vector4(1024, 2, 1023, 0)"),
    ("terrain_height", "sampler2D", '""'),
    ("terrain_normal", "sampler2D", '""'),
    ("terrain_splat", "sampler2D", '""'),
    ("terrain_veg", "sampler2D", '""'),
]


def globals_section():
    out = ["[shader_globals]", ""]
    for name, typ, val in GLOBALS:
        out.append("%s={" % name)
        out.append('"type": "%s",' % typ)
        out.append('"value": %s' % val)
        out.append("}")
    return "\n".join(out) + "\n"


HEADER = """; Engine configuration file.
; Generated by tools/project/make_project.py - Procedural Samurai

config_version=5

[application]

config/name="Procedural Samurai"
config/description="Mundo aberto samurai procedural com ragdolls ativos, desmembramento e ambientação inspirada no Japão feudal."
config/version="0.1.0"
run/main_scene="res://scenes/main.tscn"
config/features=PackedStringArray("4.7", "Forward Plus")
boot_splash/bg_color=Color(0.043, 0.035, 0.031, 1)
boot_splash/show_image=false
config/icon="res://icon.svg"

[audio]

buses/default_bus_layout="res://assets/audio/bus_layout.tres"

[autoload]

Settings="*res://scripts/autoload/settings.gd"
Game="*res://scripts/autoload/game.gd"
Audio="*res://scripts/autoload/audio.gd"
SaveGame="*res://scripts/autoload/save_game.gd"
FX="*res://scripts/autoload/fx.gd"

[debug]

gdscript/warnings/unused_parameter=0
gdscript/warnings/shadowed_variable=0
gdscript/warnings/integer_division=0
gdscript/warnings/narrowing_conversion=0
gdscript/warnings/untyped_declaration=0
gdscript/warnings/inferred_declaration=0

[display]

window/size/viewport_width=1920
window/size/viewport_height=1080
window/size/window_width_override=1600
window/size/window_height_override=900
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"
window/vsync/vsync_mode=1
mouse_cursor/custom_image_hotspot=Vector2(0, 0)

[gui]

theme/custom="res://assets/ui/theme.tres"

[layer_names]

3d_physics/layer_1="world"
3d_physics/layer_2="characters"
3d_physics/layer_3="ragdoll_alive"
3d_physics/layer_4="ragdoll_dead"
3d_physics/layer_5="props_dynamic"
3d_physics/layer_6="water"
3d_physics/layer_7="interact"
3d_physics/layer_8="weapons"

[physics]

3d/physics_engine="Jolt Physics"
3d/default_gravity=12.0
common/physics_ticks_per_second=60
common/max_physics_steps_per_frame=6
common/physics_interpolation=true
jolt_physics_3d/limits/max_bodies=16384

[rendering]

renderer/rendering_method="forward_plus"
textures/default_filters/anisotropic_filtering_level=3
textures/canvas_textures/default_texture_filter=1
anti_aliasing/quality/screen_space_aa=2
anti_aliasing/quality/use_debanding=true
lights_and_shadows/directional_shadow/size=4096
lights_and_shadows/directional_shadow/soft_shadow_filter_quality=3
lights_and_shadows/positional_shadow/soft_shadow_filter_quality=2
environment/volumetric_fog/volume_size=96
environment/volumetric_fog/volume_depth=96
environment/defaults/default_clear_color=Color(0.55, 0.62, 0.72, 1)
anti_aliasing/screen_space_roughness_limiter/enabled=true

"""


def main():
    text = HEADER + input_section() + "\n" + globals_section()
    with open(os.path.join(ROOT, "project.godot"), "w", encoding="utf-8") as f:
        f.write(text)
    print("project.godot written (%d actions, %d globals)" % (len(ACTIONS), len(GLOBALS)))


if __name__ == "__main__":
    main()
