"""perfcompare.py <base_glob> <new_glob>: median of each metric over the runs, and the change in percent.
Lower is better for every metric (times, draw calls, memory, node counts)."""
import glob
import os
import re
import statistics
import sys


def native(pattern):
    # Git Bash hands over /c/Users/...; Python on Windows needs C:/Users/...
    match = re.match(r'^/([a-zA-Z])/(.*)$', pattern)
    if match and os.name == 'nt':
        return '%s:/%s' % (match.group(1).upper(), match.group(2))
    return pattern


def load(pattern):
    files = [path for path in sorted(glob.glob(native(pattern))) if not path.endswith('.log')]
    runs = {}
    for path in files:
        for line in open(path, encoding='utf-8', errors='ignore'):
            parts = line.split()
            if len(parts) == 3 and parts[0] == 'R':
                runs.setdefault(parts[1], []).append(float(parts[2]))
    return {k: statistics.median(v) for k, v in runs.items()}, len(files)


base, nb = load(sys.argv[1])
new, nn = load(sys.argv[2])
print('%-28s %12s %12s %9s   (median of %d vs %d runs)' % ('metric', 'before', 'after', 'change', nb, nn))
for key in base:
    if key not in new:
        continue
    b, n = base[key], new[key]
    change = (n - b) / b * 100.0 if b else 0.0
    print('%-28s %12.3f %12.3f %+8.1f%%' % (key, b, n, change))
