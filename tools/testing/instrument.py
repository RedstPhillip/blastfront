"""Wraps engine callbacks (and selected functions) in every .gd file of the mirror with per-frame timers.

Timings accumulate in Engine meta "prof" (Dictionary name -> usec); capture.gd reads and clears it each frame.
Only ever run on a throwaway copy (profile.sh makes one), never on the real project or the test mirror.
"""
import os
import re
import sys

MIRROR = sys.argv[1]
CALLBACKS = {"_process", "_physics_process", "_draw", "_input", "_unhandled_input", "_gui_input", "_ready", "_notification"}
EXTRA = {
    "game_juice.gd": None,  # all public funcs
    "impact_decals.gd": None,
    "audio_director.gd": {"play", "play_at", "play_ui", "play_music", "play_ambience"},
    "fx_lib.gd": None,
    "burst_effect.gd": None,
    "bot_brain.gd": None,
    "level_navigation.gd": None,
    "player.gd": None,
    "gun.gd": None,
    "projectile.gd": None,
    "game.gd": None,
    "airdrop_manager.gd": None,
    "hud_player_card.gd": None,
    "extension_inventory.gd": None,
    "weapon_extension_visuals.gd": None,
    "weapon_art.gd": None,
    "hud_toasts.gd": None,
    "research_quest_manager.gd": None,
    "loadout_page.gd": None,
    "loadout_item_tile.gd": None,
    "loadout_weapon_bay.gd": None,
    "loadout_operator_stage.gd": None,
    "loadout_operator_puppet.gd": None,
    "loadout_inspector.gd": None,
    "loadout_style.gd": None,
    "armor_art.gd": None,
    "loadout_socket_chip.gd": None,
    "loadout_stat_strip.gd": None,
    "main_menu.gd": None,
    "mars_weather.gd": None,
    "hud_quest_tracker.gd": None,
    "ui_style.gd": None,
}

FUNC_RE = re.compile(r'^(static\s+)?func\s+(\w+)\s*\((.*)\)\s*(->\s*([\w\[\], ]+))?\s*:\s*$')


def split_params(params):
    out, depth, cur = [], 0, ''
    for ch in params:
        if ch in '([{':
            depth += 1
        elif ch in ')]}':
            depth -= 1
        if ch == ',' and depth == 0:
            out.append(cur)
            cur = ''
        else:
            cur += ch
    if cur.strip():
        out.append(cur)
    names = []
    for p in out:
        p = p.strip()
        name = re.split(r'[:=]', p)[0].strip()
        names.append(name)
    return names


def body_has_await(lines, start):
    i = start + 1
    while i < len(lines):
        l = lines[i]
        if l.strip() and not l.startswith(('\t', ' ', '#')):
            break
        if re.search(r'\bawait\b', l):
            return True
        i += 1
    return False


def transform(path, only):
    src = open(path, encoding='utf-8').read()
    lines = src.split('\n')
    base = os.path.basename(path)
    out = []
    changed = False
    for i, line in enumerate(lines):
        m = FUNC_RE.match(line)
        if not m:
            out.append(line)
            continue
        static, name, params, _, ret = m.group(1), m.group(2), m.group(3), m.group(4), m.group(5)
        wanted = name in CALLBACKS or (only is None and base in EXTRA) or (only is not None and name in only)
        if not wanted or name.startswith('__p_') or body_has_await(lines, i):
            out.append(line)
            continue
        if name in ('_init', '_enter_tree', '_exit_tree', '_get', '_set', '_get_property_list', '_to_string', '_validate_property', '_can_drop_data', '_get_drag_data', '_drop_data', '_has_point', '_get_minimum_size', '_make_custom_tooltip', '_structured_text_parser', '_property_can_revert', '_property_get_revert'):
            out.append(line)
            continue
        names = split_params(params)
        key = '%s:%s' % (base, name)
        orig = '__p_' + name
        ret_t = (ret or '').strip()
        is_void = ret_t in ('', 'void')
        prefix = 'static ' if static else ''
        call = '%s(%s)' % (orig, ', '.join(names))
        wrapper = [
            '%sfunc %s(%s)%s:' % (prefix, name, params, (' -> ' + ret_t) if ret_t else ''),
            '\tvar __t: int = Time.get_ticks_usec()',
        ]
        if is_void:
            wrapper.append('\t' + call)
            wrapper.append('\tvar __d: Dictionary = Engine.get_meta(&"prof", {})')
            wrapper.append('\t__d["%s"] = int(__d.get("%s", 0)) + Time.get_ticks_usec() - __t' % (key, key))
            wrapper.append('\t__d["%s#"] = int(__d.get("%s#", 0)) + 1' % (key, key))
        else:
            wrapper.append('\tvar __r = ' + call)
            wrapper.append('\tvar __d: Dictionary = Engine.get_meta(&"prof", {})')
            wrapper.append('\t__d["%s"] = int(__d.get("%s", 0)) + Time.get_ticks_usec() - __t' % (key, key))
            wrapper.append('\t__d["%s#"] = int(__d.get("%s#", 0)) + 1' % (key, key))
            wrapper.append('\treturn __r')
        out.extend(wrapper)
        out.append('')
        out.append('')
        out.append(line.replace('func ' + name + '(', 'func ' + orig + '(', 1))
        changed = True
    if changed:
        open(path, 'w', encoding='utf-8', newline='\n').write('\n'.join(out))
    return changed


count = 0
for dp, dn, fn in os.walk(MIRROR):
    if '.godot' in dp or 'addons' in dp:
        continue
    for f in fn:
        if f.endswith('.gd') and not f.startswith('build_') and 'tools' not in dp:
            only = EXTRA.get(f, set()) if f in EXTRA else set()
            if transform(os.path.join(dp, f), only):
                count += 1
print('instrumented files:', count)
