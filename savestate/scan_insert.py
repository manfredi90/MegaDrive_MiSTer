#!/usr/bin/env python3
"""Insert the savestate scan chain into the flattened md_core netlist (Yosys JSON).

Every flip-flop gets   D' = ss_sel ? <previous chain bit> : D
                       EN' = ss_shift | (~ss_hold & EN)      (EN = 1 for a plain $dff)
so while ss_hold is high the whole board is frozen and with ss_shift it becomes one long
shift register from ss_in to ss_out. Both cost no logic in front of the flip-flop: the
freeze goes through the register's hardware clock enable, and the shift mux is the
register's synchronous load (a dffeas primitive with sload = ss_sel, asdata = previous
bit), which Cyclone V has in every register with a LAB-wide sload. ss_sel only changes while the
board is frozen and not shifting (ss_ctrl keeps it steady for two clocks around every
shift and release), so it gets two-clock timing; the single-clock ss_shift only feeds the
enables. The netlist must keep its clock enables ($dffe, dffunmap -srst-only).
Bits whose net name starts with "ssx_" belong to the savestate logic itself (memory
access) and are left untouched; MegaDrive.sdc gives their paths two clocks. "ssy_" bits are
left untouched too but keep single-clock timing: copies of state registers that also serve
the memory access and are rebuilt from the original while the board is held.

Almost half of the flip-flops take D straight from another flip-flop (the shift registers
and delay lines of the gate-level chips). The chain follows those links wherever it can,
so that shifting runs through the existing D path and needs no mux. The rest of the order
comes from the register names (e.g. md_board.m68k.w529[3]), not from Yosys' internal
names, so it is deterministic and only moves where the design changes.

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
        if leaf.startswith(('ssx_', 'ssy_')):
            excluded.update(b for b in net['bits'] if isinstance(b, int))

    def port_bit(name):
        bits = ports[name]['bits']
        assert len(bits) == 1
        return bits[0]

    ss_hold, ss_shift, ss_sel, ss_in = (port_bit(p) for p in ('ss_hold', 'ss_shift', 'ss_sel', 'ss_in'))

    FF = ('$dff', '$dffe')
    bad = sorted({c['type'] for c in cells.values()
                  if ('dff' in c['type'] or 'latch' in c['type'] or c['type'] in ('$sr', '$aldff'))
                  and c['type'] not in FF})
    if bad:
        sys.exit(f'unexpected storage cells (run dffunmap -srst-only first?): {bad}')

    clocks = {tuple(c['connections']['CLK']) for c in cells.values() if c['type'] in FF}
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

    # register attributes from the RTL that Quartus must still see (upstream timing fixes):
    # dont_retime keeps the register where it is, dont_merge keeps a register copy apart
    # (Verilog attributes on a reg; these registers stay plain regs with a LUT shift mux)
    QATTR = ('dont_retime', 'dont_merge')
    qattr = set()
    for net in nets.values():
        if any(k in net.get('attributes', {}) for k in QATTR):
            qattr.update(b for b in net['bits'] if isinstance(b, int))

    named = {}
    dsrc = {}
    for cname, cell in cells.items():
        if cell['type'] not in FF:
            continue
        assert int(cell['parameters']['CLK_POLARITY'], 2) == 1
        for i, (b, d) in enumerate(zip(cell['connections']['Q'], cell['connections']['D'])):
            if isinstance(b, int) and b not in excluded:
                names = sorted(set(aliases.get(b, [])), key=lambda n: (-n.count('.'), natural(n)))
                if not names:
                    names = [f'?{cname}[{i}]']   # no name in the design: cannot be matched across builds
                named[b] = names
                dsrc[b] = d
    key = {b: natural(n[0]) for b, n in named.items()}
    unnamed = sum(1 for n in named.values() if n[0].startswith('?'))

    # natural links a -> b where D(b) = Q(a); each a can lead to one b only
    succ, pred = {}, {}
    for b in sorted(named, key=key.get):
        a = dsrc[b]
        if isinstance(a, int) and a in named and a != b and a not in succ:
            succ[a], pred[b] = b, a
    flow, seen = [], set()

    def follow(x):
        while x is not None and x not in seen:
            seen.add(x)
            flow.append(x)
            x = succ.get(x)

    segments = sorted((b for b in named if b not in pred), key=key.get)
    for h in segments:
        follow(h)
    cycles = 0
    for x in sorted(named, key=key.get):   # what is left are rings: break each at its first name
        if x not in seen:
            cycles += 1
            del succ[pred.pop(x)]
            follow(x)
    assert len(flow) == len(named)

    # flow runs from ss_in to ss_out; the stream (as read from ss_out) is the other way
    prev = {}
    chain = ss_in
    for b in flow:
        prev[b] = chain
        chain = b
    ffs = [(None, named[b], b) for b in reversed(flow)]
    length = len(ffs)

    def gate(kind, conn, ports_out='Y'):
        y = new_bits(1)
        w1 = format(1, '032b')
        params = {'A_SIGNED': format(0, '032b'), 'A_WIDTH': w1, 'Y_WIDTH': w1}
        dirs = {'A': 'input', 'Y': 'output'}
        if 'B' in conn:
            params.update({'B_SIGNED': format(0, '032b'), 'B_WIDTH': w1})
            dirs['B'] = 'input'
        conn = {k: [v] for k, v in conn.items()}
        conn['Y'] = y
        new_cells[f'$ss_{kind}{len(new_cells)}'] = {
            'hide_name': 1, 'type': kind, 'parameters': params, 'attributes': {},
            'port_directions': dirs, 'connections': conn,
        }
        return y[0]

    new_cells = {}
    not_hold = gate('$not', {'A': ss_hold})
    # A few clock enables feed thousands of flip-flops (2048 for one VRAM slice): with
    # ss_shift in front, one LUT driving all of them misses timing by several ns depending
    # on placement. Every enable gets its own LUT per group of at most EN_GROUP bits, named
    # ss_en_* and kept apart in Quartus (synthesis keep, see gen_netlist.sh).
    EN_GROUP = 32
    actives = {}
    groups = {}
    n_en = 0

    def enable(cell, width):
        nonlocal n_en
        if cell['type'] == '$dff':
            key = None
        else:
            key = (cell['connections']['EN'][0], int(cell['parameters']['EN_POLARITY'], 2))
        g = groups.get(key)
        if g is None or g[1] + width > EN_GROUP:
            if key is None:
                y = gate('$or', {'A': ss_shift, 'B': not_hold})
            else:
                if key not in actives:
                    en, pol = key
                    actives[key] = en if pol else gate('$not', {'A': en})
                y = gate('$or', {'A': ss_shift, 'B': gate('$and', {'A': not_hold, 'B': actives[key]})})
            nets[f'ss_en_{n_en}'] = {'hide_name': 0, 'bits': [y], 'attributes': {}}
            n_en += 1
            g = groups[key] = [y, 0]
        g[1] += width
        return g[0]

    # Quartus primitive: a Cyclone V register with its clock enable and synchronous load
    def sync_load(clk, en, d, q, sdata):
        # named after the register bit, so that the timing reports stay readable
        new_cells['ssff_' + named[q][0].lstrip('\\')] = {
            'hide_name': 0, 'type': 'dffeas',
            'parameters': {'power_up': 'high' if init.get(q) == '1' else 'low'},
            'attributes': {},
            'port_directions': {p: 'input' for p in
                                ('d', 'clk', 'ena', 'asdata', 'sload', 'clrn', 'prn', 'aload', 'sclr')} | {'q': 'output'},
            'connections': {'d': [d], 'clk': [clk], 'ena': [en], 'asdata': [sdata], 'sload': [ss_sel],
                            'clrn': ['1'], 'prn': ['1'], 'aload': ['0'], 'sclr': ['0'], 'q': [q]},
        }
        sload_bits.add(q)

    dead, sload_bits = set(), set()
    split = muxes = 0
    for name in sorted(n for n, c in cells.items() if c['type'] in FF):
        cell = cells[name]
        q = cell['connections']['Q']
        idx = [i for i, b in enumerate(q) if b in prev]
        if not idx:
            continue
        if len(idx) < len(q):
            # a few bits of this register are savestate logic (ssx_): keep them in a cell of
            # their own with the original clock enable
            split += 1
            rest = [i for i in range(len(q)) if i not in idx]
            keep = json.loads(json.dumps(cell))
            for p in ('D', 'Q'):
                keep['connections'][p] = [cell['connections'][p][i] for i in rest]
                cell['connections'][p] = [cell['connections'][p][i] for i in idx]
            keep['parameters']['WIDTH'] = format(len(rest), '032b')
            cell['parameters']['WIDTH'] = format(len(idx), '032b')
            new_cells[f'{name}_ssx'] = keep
        d = cell['connections']['D']
        q = cell['connections']['Q']
        w = len(q)
        clk = cell['connections']['CLK'][0]
        muxes += sum(1 for i in range(w) if prev[q[i]] != d[i])
        orig_type = cell['type']
        cell['type'] = '$dffe'
        cell['port_directions']['EN'] = 'input'
        # wide registers are cut into pieces of at most EN_GROUP bits, each on its own enable
        pieces = [cell]
        if w > EN_GROUP:
            pieces = []
            for k in range(0, w, EN_GROUP):
                piece = json.loads(json.dumps(cell))
                for p in ('D', 'Q'):
                    piece['connections'][p] = cell['connections'][p][k:k + EN_GROUP]
                piece['parameters']['WIDTH'] = format(len(piece['connections']['Q']), '032b')
                pieces.append(piece)
                if k:
                    new_cells[f'{name}_ss{k // EN_GROUP}'] = piece
            cells[name] = pieces[0]
        for k, piece in enumerate(pieces):
            piece['type'] = orig_type
            en = enable(piece, len(piece['connections']['Q']))
            piece['connections']['EN'] = [en]
            piece['type'] = '$dffe'
            piece['parameters']['EN_POLARITY'] = format(1, '032b')
            # the bits that need a shift mux become single registers that take the previous
            # chain bit through their synchronous load (sload = ss_sel, asdata), so the mux
            # costs no LUT and no logic level in front of the flip-flop
            pd, pq = list(piece['connections']['D']), piece['connections']['Q']
            keep = [i for i in range(len(pq)) if prev[pq[i]] == pd[i] or pq[i] in qattr]
            for i in range(len(pq)):
                if prev[pq[i]] == pd[i]:
                    continue
                if pq[i] in qattr:
                    y = new_bits(1)
                    new_cells[f'$ss_shift{name}_{k}_{i}'] = {
                        'hide_name': 1, 'type': '$mux',
                        'parameters': {'WIDTH': format(1, '032b')},
                        'attributes': {},
                        'port_directions': {'A': 'input', 'B': 'input', 'S': 'input', 'Y': 'output'},
                        'connections': {'A': [pd[i]], 'B': [prev[pq[i]]], 'S': [ss_sel], 'Y': y},
                    }
                    pd[i] = y[0]
                else:
                    sync_load(clk, en, pd[i], pq[i], prev[pq[i]])
            piece['connections']['D'] = pd
            if len(keep) < len(pq):
                piece['connections']['D'] = [pd[i] for i in keep]
                piece['connections']['Q'] = [pq[i] for i in keep]
                piece['parameters']['WIDTH'] = format(len(keep), '032b')
            if not keep:
                dead.add(id(piece))
    cells.update(new_cells)
    for name in [n for n, c in cells.items() if id(c) in dead]:
        del cells[name]
    # their power-up value is now the power_up parameter
    for net in nets.values():
        iv = net.get('attributes', {}).get('init')
        if iv is not None and len(iv) == len(net['bits']):
            w = len(iv)
            iv = ''.join('x' if net['bits'][w - 1 - j] in sload_bits else iv[j] for j in range(w))
            if set(iv) == {'x'}:
                del net['attributes']['init']
            else:
                net['attributes']['init'] = iv
    print(f'clock enables: {len(actives)} distinct + 1 in {n_en} groups, {split} registers split, '
          f'{muxes} shift muxes (sync load), {len(segments)} chain segments + {cycles} rings')

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

    # Quartus 17 crashes (SGN "dimension == 0") on escaped names such as
    # \md_board.ym.fm.ch.l1[0].sr.MCLK: keep only identifier characters. The layout map
    # above keeps the original names.
    def clean(n):
        return re.sub(r'[^A-Za-z0-9_]', '_', n)

    taken = set(ports)
    renamed = {}
    for name in list(nets):
        if name.startswith('$') or name in ports:
            renamed[name] = name
            continue
        new = clean(name)
        while new in taken:
            new += '_'
        taken.add(new)
        renamed[name] = new
    mod['netnames'] = {renamed[n]: v for n, v in nets.items()}
    mod['cells'] = {(n if n.startswith('$') else clean(n)): c for n, c in cells.items()}
    for c in mod['cells'].values():
        memid = c.get('parameters', {}).get('MEMID')
        if isinstance(memid, str) and memid.startswith('\\'):
            c['parameters']['MEMID'] = '\\' + clean(memid[1:])

    # the netlist is written with attributes: keep only the power-up values and the
    # register attributes above
    for net in mod['netnames'].values():
        net['attributes'] = {k: v for k, v in net.get('attributes', {}).items() if k == 'init' or k in QATTR}
    for c in mod['cells'].values():
        c['attributes'] = {}
    for m in design['modules'].values():
        m['attributes'] = {k: v for k, v in m.get('attributes', {}).items() if k in ('blackbox', 'top')}
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
