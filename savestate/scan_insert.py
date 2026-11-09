#!/usr/bin/env python3
"""Insert the savestate scan chain into the flattened md_core netlist (Yosys JSON).

Every flip-flop gets   D' = ss_shift ? <previous chain bit> : (ss_hold ? Q : D)
so while ss_hold is high the whole board is frozen and with ss_shift it becomes one long
shift register from ss_in to ss_out. Bits whose net name starts with "ssx_" belong to the
savestate logic itself (memory access) and are left untouched.

The bits come out of ss_out sorted by register name (e.g. md_board.m68k.w529[3]), so the
order does not depend on Yosys' internal names and only moves where the design changes.
The layout map lists, in that order, every bit with its power-on value and all the names
it has in the design, followed by layout_fixed.txt (memories, cartridge fields). Its hash
goes into the savestate header; the converter uses the maps to carry states across builds.

usage: scan_insert.py in.json out.json chain.vh maps_dir layout_fixed.txt
"""
import gzip
import hashlib
import json
import os
import re
import sys


def natural(s):
    return [int(t) if t.isdigit() else t for t in re.split(r'(\d+)', s)]


def main():
    src, dst, vh, maps_dir, fixed = sys.argv[1:6]
    design = json.load(open(src))
    mod = design['modules']['md_core']
    cells = mod['cells']
    nets = mod['netnames']
    ports = mod['ports']

    next_id = 1 + max(b for n in nets.values() for b in n['bits'] if isinstance(b, int))

    def new_bits(width):
        nonlocal next_id
        bits = list(range(next_id, next_id + width))
        next_id += width
        return bits

    excluded = set()
    for name, net in nets.items():
        leaf = name.split('.')[-1].lstrip('\\')
        if leaf.startswith('ssx_'):
            excluded.update(b for b in net['bits'] if isinstance(b, int))

    def port_bit(name):
        bits = ports[name]['bits']
        assert len(bits) == 1
        return bits[0]

    ss_hold, ss_shift, ss_in = port_bit('ss_hold'), port_bit('ss_shift'), port_bit('ss_in')

    bad = sorted({c['type'] for c in cells.values()
                  if ('dff' in c['type'] or 'latch' in c['type'] or c['type'] in ('$sr', '$aldff'))
                  and c['type'] != '$dff'})
    if bad:
        sys.exit(f'unexpected storage cells (run dffunmap first?): {bad}')

    clocks = {tuple(c['connections']['CLK']) for c in cells.values() if c['type'] == '$dff'}
    if len(clocks) != 1:
        sys.exit(f'expected a single clock, found {len(clocks)}')

    # every name each bit is known by, and its power-on value
    aliases, init = {}, {}
    for name, net in nets.items():
        bits = net['bits']
        w = len(bits)
        off = int(net.get('offset', 0))
        upto = int(net.get('upto', 0))
        iv = net.get('attributes', {}).get('init')
        for i, b in enumerate(bits):
            if not isinstance(b, int):
                continue
            idx = off + (w - 1 - i if upto else i)
            if not net['hide_name']:
                aliases.setdefault(b, []).append(f'{name}[{idx}]' if w > 1 or off else name)
            if iv is not None and b not in init and len(iv) == w:
                init[b] = iv[w - 1 - i]

    ffs = []
    for cname, cell in cells.items():
        if cell['type'] != '$dff':
            continue
        assert int(cell['parameters']['CLK_POLARITY'], 2) == 1
        for i, b in enumerate(cell['connections']['Q']):
            if isinstance(b, int) and b not in excluded:
                names = sorted(set(aliases.get(b, [])), key=lambda n: (-n.count('.'), natural(n)))
                if not names:
                    names = [f'?{cname}[{i}]']   # no name in the design: cannot be matched across builds
                ffs.append((natural(names[0]), names, b))
    ffs.sort(key=lambda f: f[0])
    unnamed = sum(1 for f in ffs if f[1][0].startswith('?'))

    # stream order (as read from ss_out) = sorted; the chain runs the other way
    prev = {}
    chain = ss_in
    for _, _, b in reversed(ffs):
        prev[b] = chain
        chain = b
    length = len(ffs)

    new_cells = {}
    for name in sorted(n for n, c in cells.items() if c['type'] == '$dff'):
        cell = cells[name]
        d = cell['connections']['D']
        q = cell['connections']['Q']
        w = len(q)
        held = [q[i] if q[i] in prev else d[i] for i in range(w)]
        shifted = [prev[q[i]] if q[i] in prev else d[i] for i in range(w)]
        if held == d:
            continue
        m1, m2 = new_bits(w), new_bits(w)
        for tag, a, b, s, y in (('hold', d, held, ss_hold, m1), ('shift', m1, shifted, ss_shift, m2)):
            new_cells[f'$ss_{tag}{name}'] = {
                'hide_name': 1, 'type': '$mux',
                'parameters': {'WIDTH': format(w, '032b')},
                'attributes': {},
                'port_directions': {'A': 'input', 'B': 'input', 'S': 'input', 'Y': 'output'},
                'connections': {'A': a, 'B': b, 'S': [s], 'Y': y},
            }
        cell['connections']['D'] = m2
    cells.update(new_cells)

    # ss_out: drive from the end of the chain (the RTL ties it to ss_in)
    out = new_bits(1)
    cells['$ss_out_buf'] = {
        'hide_name': 1, 'type': '$pos',
        'parameters': {'A_SIGNED': format(0, '032b'), 'A_WIDTH': format(1, '032b'), 'Y_WIDTH': format(1, '032b')},
        'attributes': {},
        'port_directions': {'A': 'input', 'Y': 'output'},
        'connections': {'A': [chain], 'Y': out},
    }
    ports['ss_out']['bits'] = out
    for name, net in nets.items():
        if name == 'ss_out':
            net['bits'] = out

    json.dump(design, open(dst, 'w'))

    lines = ['mdss-layout 1', f'chain {length}']
    for _, names, b in ffs:
        v = init.get(b, '0')
        lines.append(f"b {v if v in '01' else '0'} {'|'.join(names)}")
    lines += [l.strip() for l in open(fixed) if l.strip() and not l.startswith('#')]
    text = '\n'.join(lines) + '\n'
    digest = hashlib.sha1(text.encode()).hexdigest()[:8]
    os.makedirs(maps_dir, exist_ok=True)
    with open(os.path.join(maps_dir, f'{digest}.map.gz'), 'wb') as f:
        with gzip.GzipFile(fileobj=f, mode='wb', mtime=0, filename='') as g:
            g.write(text.encode())
    with open(vh, 'w') as f:
        f.write('// generated by savestate/scan_insert.py\n')
        f.write(f'localparam SS_CHAIN_LEN = {length};\n')
        f.write(f"localparam [31:0] SS_LAYOUT_HASH = 32'h{digest};\n")
    print(f'scan chain: {length} bits ({unnamed} without a name), layout {digest}')


if __name__ == '__main__':
    main()
