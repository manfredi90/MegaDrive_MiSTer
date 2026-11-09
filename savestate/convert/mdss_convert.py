#!/usr/bin/env python3
"""Carry MegaDrive (Nuked-MD) savestates over to a new build of the core.

Every build writes its layout map (savestate/layouts/<hash>.map.gz): the scan-chain bits
in save order with their register names and power-on values, the memories and the
cartridge fields. A state records the hash of the build that saved it. This script reads
the old map and the current one and rebuilds each state by name:

  - registers found in both builds keep their value,
  - registers that are new get their power-on value,
  - registers that no longer exist are dropped,
  - memories and cartridge fields are copied by name (overlapping part).

The original file is kept next to the new one as <name>.ss.<oldhash>.bak.

Runs on the MiSTer (Scripts menu, through megadrive_savestates.sh) or on a PC with the
SD card mounted. Python 3.5+, no extra modules.

usage: mdss_convert.py [--maps DIR] [--to HASH] [--dry-run] [PATH ...]
  PATH      .ss files or folders (default: /media/fat/savestates/MegaDrive)
  --maps    folder with the <hash>.map.gz files (default: maps/ next to this script)
  --to      target layout (default: the hash in <maps>/current)
"""
import argparse
import gzip
import os
import struct
import sys

MAGIC = 0x4D445353  # "MDSS"
VERSION = 2


class Layout:
    def __init__(self, path):
        with gzip.open(path, 'rt') as f:
            lines = f.read().splitlines()
        if not lines or lines[0] != 'mdss-layout 1':
            raise ValueError('%s: not a layout map' % path)
        self.bits = []          # (init, [names]) in save order
        self.mems = []          # (name, entries, per_word, bits)
        self.cart = []          # (word, name, lsb, bits)
        for l in lines[1:]:
            t = l.split()
            if t[0] == 'chain':
                pass
            elif t[0] == 'b':
                self.bits.append((int(t[1]), t[2].split('|')))
            elif t[0] == 'mem':
                self.mems.append((t[1], int(t[2]), int(t[3]), int(t[4])))
            elif t[0] == 'cart':
                self.cart.append((int(t[1]), t[2], int(t[3]), int(t[4])))
        self.chain_words = (len(self.bits) + 63) // 64
        self.cart_words = 1 + max(c[0] for c in self.cart) if self.cart else 0
        self.mem_words = sum((m[1] + m[2] - 1) // m[2] for m in self.mems)
        self.data_words = 2 + self.chain_words + self.mem_words + self.cart_words
        self.index = {}
        for i, (_, names) in enumerate(self.bits):
            for n in names:
                self.index.setdefault(n, i)


def read_state(path):
    raw = open(path, 'rb').read()
    n = len(raw) // 8
    words = list(struct.unpack('<%dQ' % n, raw[:n * 8]))
    if n < 3 or words[1] >> 32 != MAGIC:
        return None, None
    return words, (words[1] >> 16) & 0xFFFF


def unpack_state(words, lay):
    p = 3
    chain = []
    for i in range(len(lay.bits)):
        chain.append((words[p + i // 64] >> (i % 64)) & 1)
    p += lay.chain_words
    mems = {}
    for name, entries, per_word, bits in lay.mems:
        slot = 64 // per_word
        mask = (1 << bits) - 1
        mems[name] = [(words[p + k // per_word] >> ((k % per_word) * slot)) & mask for k in range(entries)]
        p += (entries + per_word - 1) // per_word
    cart = {}
    for w, name, lsb, bits in lay.cart:
        cart[name] = ((words[p + w] >> lsb) & ((1 << bits) - 1), bits)
    return chain, mems, cart


def pack_state(counter, layout_hash, lay, chain, mems, cart):
    words = [((lay.data_words * 2) << 32) | counter,
             (MAGIC << 32) | (VERSION << 16) | lay.cart_words,
             (layout_hash << 32) | len(lay.bits)]
    cw = [0] * lay.chain_words
    for i, b in enumerate(chain):
        cw[i // 64] |= b << (i % 64)
    words += cw
    for name, entries, per_word, bits in lay.mems:
        slot = 64 // per_word
        mw = [0] * ((entries + per_word - 1) // per_word)
        for k, v in enumerate(mems[name]):
            mw[k // per_word] |= (v & ((1 << bits) - 1)) << ((k % per_word) * slot)
        words += mw
    kw = [0] * lay.cart_words
    for w, name, lsb, bits in lay.cart:
        kw[w] |= (cart.get(name, 0) & ((1 << bits) - 1)) << lsb
    words += kw
    return struct.pack('<%dQ' % len(words), *words)


def convert(old, new, chain_old, mems_old, cart_old):
    chain, copied, missing = [], 0, []
    for init, names in new.bits:
        i = next((old.index[n] for n in names if n in old.index), None)
        if i is None:
            chain.append(init)
            missing.append(names[0])
        else:
            chain.append(chain_old[i])
            copied += 1
    used = set()
    for init, names in new.bits:
        for n in names:
            if n in old.index:
                used.add(old.index[n])
                break
    dropped = [old.bits[i][1][0] for i in range(len(old.bits)) if i not in used]

    mems = {}
    for name, entries, per_word, bits in new.mems:
        src = mems_old.get(name, [])
        mems[name] = [src[k] if k < len(src) else 0 for k in range(entries)]
    cart = {name: cart_old[name][0] if name in cart_old else 0 for _, name, _, _ in new.cart}
    return chain, mems, cart, copied, missing, dropped


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description='Convert MegaDrive savestates to the current core build.')
    ap.add_argument('paths', nargs='*', default=['/media/fat/savestates/MegaDrive'])
    ap.add_argument('--maps', default=os.path.join(here, 'maps'))
    ap.add_argument('--to')
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args()

    target = a.to
    if not target:
        try:
            target = open(os.path.join(a.maps, 'current')).read().strip()
        except OSError:
            sys.exit('no %s/current: copy the maps of the core build you use' % a.maps)
    layouts = {}

    def layout(h):
        if h not in layouts:
            p = os.path.join(a.maps, '%08x.map.gz' % h)
            layouts[h] = Layout(p) if os.path.exists(p) else None
        return layouts[h]

    target_hash = int(target, 16)
    new = layout(target_hash)
    if new is None:
        sys.exit('missing map for the current build: %s/%s.map.gz' % (a.maps, target))

    files = []
    for p in a.paths:
        if os.path.isdir(p):
            files += sorted(os.path.join(p, f) for f in os.listdir(p) if f.lower().endswith('.ss'))
        elif os.path.exists(p):
            files.append(p)
    if not files:
        print('no savestates found in', ' '.join(a.paths))
        return

    print('current core layout %s, %d savestate file(s)' % (target, len(files)))
    done = 0
    for path in files:
        words, version = read_state(path)
        name = os.path.basename(path)
        if words is None:
            print('  %s: empty or not a Nuked-MD state, skipped' % name)
            continue
        if version != VERSION:
            print('  %s: format version %d not supported, skipped' % (name, version))
            continue
        h = words[2] >> 32
        if h == target_hash:
            print('  %s: already current' % name)
            continue
        old = layout(h)
        if old is None:
            print('  %s: saved by build %08x, its map is missing: skipped' % (name, h))
            continue
        if len(words) < 1 + old.data_words:
            print('  %s: truncated file, skipped' % name)
            continue
        chain_old, mems_old, cart_old = unpack_state(words, old)
        chain, mems, cart, copied, missing, dropped = convert(old, new, chain_old, mems_old, cart_old)
        print('  %s: %08x -> %s, %d registers kept, %d new (power-on value), %d gone'
              % (name, h, target, copied, len(missing), len(dropped)))
        for label, lst in (('new', missing), ('gone', dropped)):
            if lst:
                print('      %s: %s%s' % (label, ', '.join(lst[:5]), ' ...' if len(lst) > 5 else ''))
        if a.dry_run:
            continue
        data = pack_state(words[0] & 0xFFFFFFFF, target_hash, new, chain, mems, cart)
        bak = '%s.%08x.bak' % (path, h)
        os.replace(path, bak)
        with open(path, 'wb') as f:
            f.write(data)
        done += 1
    print('%d file(s) converted' % done)


if __name__ == '__main__':
    main()
