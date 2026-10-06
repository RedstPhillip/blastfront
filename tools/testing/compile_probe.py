"""inject <mirror>: add a static-init marker to every script (prints when the script finished compiling).
report <log>: turn the markers into per-script deltas (time since the previous marker)."""
import os
import sys

if sys.argv[1] == 'inject':
    root = sys.argv[2]
    count = 0
    for dp, dn, fn in os.walk(root):
        if '.godot' in dp or 'addons' in dp or os.sep + 'tools' in dp:
            continue
        for f in fn:
            if not f.endswith('.gd'):
                continue
            p = os.path.join(dp, f)
            raw = open(p, 'rb').read()
            bom = raw.startswith(b'\xef\xbb\xbf')
            s = raw.decode('utf-8-sig')
            if '@tool' in s:
                continue
            lines = s.split('\n')
            idx = next((i for i, l in enumerate(lines) if l.startswith('extends')), None)
            if idx is None:
                continue
            j = idx + 1
            while j < len(lines) and (lines[j].startswith('class_name') or lines[j].startswith('extends')):
                j += 1
            rel = os.path.relpath(p, root).replace(os.sep, '/')
            lines[j:j] = ['', 'static var __bt_load: int = __bt_mark("%s")' % rel, 'static func __bt_mark(label: String) -> int:',
                          '\tprint("CMP %d %s" % [Time.get_ticks_usec(), label])', '\treturn 0']
            open(p, 'w', encoding='utf-8-sig' if bom else 'utf-8', newline='\n').write('\n'.join(lines))
            count += 1
    print('probed', count)
else:
    rows = [l.split() for l in open(sys.argv[2], encoding='utf-8', errors='ignore') if l.startswith('CMP ')]
    prev = None
    deltas = []
    for r in rows:
        t = int(r[1])
        deltas.append(((t - (prev if prev is not None else 0)) / 1000.0, r[2]))
        prev = t
    print('first %.0f ms, last %.0f ms, scripts %d' % (int(rows[0][1]) / 1000, int(rows[-1][1]) / 1000, len(rows)))
    for d, n in sorted(deltas, reverse=True)[:int(sys.argv[3]) if len(sys.argv) > 3 else 30]:
        print('%8.1f ms  %s' % (d, n))
