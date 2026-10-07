"""Lists files under assets/ that no script, scene, resource or config mentions (by path or, for files
loaded by key such as sounds, colours and icons, by bare file stem)."""
import os
import re
import sys

# Default: the repository this file lives in (tools/testing/../..).
root = sys.argv[1] if len(sys.argv) > 1 else os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
texts = []
for dp, dn, fn in os.walk(root):
    if '.godot' in dp or '.git' in dp:
        continue
    for f in fn:
        if f.endswith(('.gd', '.tscn', '.tres', '.cfg', '.godot', '.gdshader')):
            texts.append(open(os.path.join(dp, f), encoding='utf-8', errors='ignore').read())
blob = '\n'.join(texts)
unused = []
for dp, dn, fn in os.walk(os.path.join(root, 'assets')):
    for f in fn:
        if f.endswith(('.import', '.uid')):
            continue
        full = os.path.join(dp, f)
        path = os.path.relpath(full, root).replace(os.sep, '/')
        stem = os.path.splitext(f)[0]
        if path in blob:
            continue
        if re.search(r'["/:&]' + re.escape(stem) + r'["\.]', blob):
            continue
        unused.append((os.path.getsize(full), path))
unused.sort(reverse=True)
print('possibly unused: %d files, %.1f MB' % (len(unused), sum(u[0] for u in unused) / 1048576))
for size, path in unused:
    print('%9d %s' % (size, path))
