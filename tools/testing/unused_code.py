"""Lists scripts and scenes nobody references: no other file mentions their res:// path (or uid) and,
for scripts, nobody uses their class_name."""
import os
import re
import sys

# Default: the repository this file lives in (tools/testing/../..).
root = sys.argv[1] if len(sys.argv) > 1 else os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
files = {}
for dp, dn, fn in os.walk(root):
    if '.godot' in dp or '.git' in dp or 'addons' in dp:
        continue
    for f in fn:
        if f.endswith(('.gd', '.tscn', '.tres', '.godot', '.cfg', '.gdshader')):
            full = os.path.join(dp, f)
            files[os.path.relpath(full, root).replace(os.sep, '/')] = open(full, encoding='utf-8', errors='ignore').read()

for rel, text in sorted(files.items()):
    if not rel.endswith(('.gd', '.tscn')) or rel.startswith('tools/'):
        continue
    others = '\n'.join(t for r, t in files.items() if r != rel and r != rel + '.uid')
    if ('res://' + rel) in others:
        continue
    uid_file = os.path.join(root, rel + '.uid')
    if os.path.exists(uid_file):
        uid = open(uid_file).read().strip()
        if uid and uid in others:
            continue
    if rel.endswith('.tscn'):
        m = re.search(r'uid="(uid://[a-z0-9]+)"', text)
        if m and m.group(1) in others:
            continue
    m = re.search(r'^class_name\s+(\w+)', text, re.M)
    if m and re.search(r'\b%s\b' % m.group(1), others):
        continue
    print(rel)
