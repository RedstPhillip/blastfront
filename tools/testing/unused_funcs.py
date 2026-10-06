"""Private functions (leading underscore, not an engine callback) that nothing calls or connects."""
import os
import re
import sys

CALLBACKS = {
    '_ready', '_process', '_physics_process', '_draw', '_input', '_unhandled_input', '_unhandled_key_input',
    '_gui_input', '_notification', '_enter_tree', '_exit_tree', '_init', '_get', '_set', '_get_property_list',
    '_to_string', '_can_drop_data', '_drop_data', '_get_drag_data', '_has_point', '_get_minimum_size',
    '_make_custom_tooltip', '_initialize', '_finalize', '_integrate_forces', '_shortcut_input',
    '_validate_property', '_property_can_revert', '_property_get_revert', '_get_configuration_warnings',
    '_run', '_static_init', '_get_tooltip', '_structured_text_parser', '_iter_init', '_iter_next', '_iter_get',
}
root = sys.argv[1]
texts = {}
for dp, dn, fn in os.walk(root):
    if '.godot' in dp or '.git' in dp or 'addons' in dp:
        continue
    for f in fn:
        if f.endswith(('.gd', '.tscn')):
            full = os.path.join(dp, f)
            texts[os.path.relpath(full, root).replace(os.sep, '/')] = open(full, encoding='utf-8', errors='ignore').read()
blob = '\n'.join(texts.values())
for rel, text in sorted(texts.items()):
    if not rel.endswith('.gd'):
        continue
    for m in re.finditer(r'^(?:static\s+)?func\s+(_\w+)\s*\(', text, re.M):
        name = m.group(1)
        if name in CALLBACKS:
            continue
        uses = len(re.findall(r'\b%s\b' % re.escape(name), blob))
        if uses <= 1:
            print('%s: %s' % (rel, name))
