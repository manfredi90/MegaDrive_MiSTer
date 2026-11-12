# EXPERIMENT: only the name cleanup of scan_insert.py, no scan chain
import json, re, sys
design = json.load(open(sys.argv[1]))
mod = design['modules']['md_core']
ports, nets, cells = mod['ports'], mod['netnames'], mod['cells']
clean = lambda n: re.sub(r'[^A-Za-z0-9_]', '_', n)
taken, renamed = set(ports), {}
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
QATTR = {'dont_retime': '-name DONT_RETIME ON', 'dont_merge': '-name DONT_MERGE_REGISTER ON'}
for net in mod['netnames'].values():
    at = net.get('attributes', {})
    q = '; '.join(QATTR[k] for k in QATTR if k in at)
    net['attributes'] = {k: v for k, v in at.items() if k == 'init'} | ({'altera_attribute': q} if q else {})
for c in mod['cells'].values():
    c['attributes'] = {}
for m in design['modules'].values():
    m['attributes'] = {k: v for k, v in m.get('attributes', {}).items() if k in ('blackbox', 'top')}
json.dump(design, open(sys.argv[2], 'w'))
