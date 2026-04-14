#!/bin/bash -ue
python3 - <<'PYEOF'
import csv, io, json, sys

raw = '''Compound_ID,IC50_BCR_ABL1,hERG_IC50\nIMA,0.01,10.0\nNIL,0.001,5.0'''

# Strip any leading/trailing whitespace lines
lines = [l for l in raw.strip().splitlines() if l.strip()]

# Find header row
header_idx = 0
for i, l in enumerate(lines):
    if 'compound_id' in l.lower() or 'cpd' in l.lower() and 'assay' in l.lower():
        header_idx = i
        break

reader = csv.DictReader(lines[header_idx:])
rows = list(reader)

if not rows:
    sys.exit('ERROR: No data rows found in assay CSV')

# Normalize column names
def norm_col(c):
    return c.strip().lower().replace(' ', '_')

rows_norm = [{norm_col(k): v.strip() for k, v in r.items()} for r in rows]

# Pivot: one row per compound, columns per assay_type
from collections import defaultdict
data = defaultdict(dict)
for r in rows_norm:
    cid = r.get('compound_id', r.get('cpd_id', ''))
    atype = r.get('assay_type', '')
    val = r.get('value', r.get('ic50', ''))
    unit = r.get('unit', '')
    data[cid][atype] = (val, unit)

assay_types = sorted({atype for cid_data in data.values() for atype in cid_data})

with open('wide_assay.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    header = ['compound_id'] + [f'{a}_value' for a in assay_types] + [f'{a}_unit' for a in assay_types]
    writer.writerow(header)
    for cid, amap in sorted(data.items()):
        row = [cid]
        for a in assay_types:
            v, u = amap.get(a, ('', ''))
            row.append(v)
        for a in assay_types:
            v, u = amap.get(a, ('', ''))
            row.append(u)
        writer.writerow(row)

with open('parse_report.txt', 'w') as f:
    f.write(f'Compounds parsed: {len(data)}\n')
    f.write(f'Assay types: {assay_types}\n')
    f.write(f'Total rows: {len(rows)}\n')

print(f'Parsed {len(data)} compounds, assays: {assay_types}')
PYEOF
