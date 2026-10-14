"""Keep a resource whose pointer was already fixed up from ending the game.

datResourceMap lookup (f2092) turns a file-relative pointer (0x5... virtual, 0x6... physical)
into the delta to the chunk it was placed in. A pointer that is not in the map is fatal ("Invalid
fixup, address 0x2fff8000 is neither virtual nor physical"). Players hit it on two fences in the
Vinewood Hills (ch2_07_fence_03, ch2_07d_fencing_02), always with the same address: the start of
a chunk the resource itself had just been placed in, so the pointer was being fixed up a second
time. pg_fixup_already_placed answers delta 0 for an address inside one of the resource's placed
chunks (it is already right) and logs it; any other address still stops the game as before.
"""
from pathlib import Path
import re
root = Path(__file__).resolve().parents[1]
FUNCTION = '2092'
MARK = 'pg_fixup_already_placed('
OLD = '  var_B3:;\n  var_j0 = var_p0;\n'
NEW = ('  var_B3:;\n  if (pg_fixup_already_placed(instance, var_p0, var_p1)) { var_j0 = 0ull; goto var_B2; }\n'
       '  var_j0 = var_p0;\n')
done = False
for path in sorted((root / 'Generated').glob('game_*.c')):
    s = path.read_text()
    found = re.search(r'^u64 w2c_game_f' + FUNCTION + r'\(w2c_game\* instance, u64 var_p0, u64 var_p1\) \{$', s, re.M)
    if not found: continue
    start, end = found.start(), s.index('\n}\n', found.start())
    body = s[start:end]
    if MARK not in body:
        if body.count(OLD) != 1 or '1322386ull' not in body or '4120u' not in body:
            raise RuntimeError(f'Pinned f{FUNCTION} (datResourceMap fixup lookup) changed')
        s = s[:start] + body.replace(OLD, NEW, 1) + s[end:]
        include = '#include "game-fixup-guard-impl.h"'
        if include not in s: s = s.replace('#include "game-impl.h"', include, 1)
        path.write_text(s)
    done = True
    break
if not done: raise RuntimeError(f'Pinned function f{FUNCTION} not found')
(root / 'Generated/game-fixup-guard-impl.h').write_text(
    '#include "game-impl.h"\n'
    'extern u32 pg_fixup_already_placed(w2c_game *instance, u64 map, u64 address);\n')
