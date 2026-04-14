#!/bin/bash -ue
python3 - <<'PYEOF'
import csv, math

potency_col = 'IC50_BCR_ABL1_value'
safety_col  = 'hERG_IC50_value'
pw = float('0.6')
sw = float('0.4')
herg_threshold = float('1.0')

with open('wide_assay.csv') as f:
    rows = list(csv.DictReader(f))

def safe_float(v, default=None):
    try:
        return float(v)
    except (TypeError, ValueError):
        return default

def potency_score(ic50_nm):
    # Log-scaled score: max at 0.01 nM, 0.5 at 1 nM, decays for weaker compounds
    if ic50_nm is None or ic50_nm <= 0:
        return 0.0
    # pIC50-based normalisation, clamp 0-1
    pic50 = -math.log10(ic50_nm * 1e-9)  # convert nM to M
    # Normalise: 12 = perfect (0.01 nM), 6 = weak (1 uM)
    score = max(0.0, min(1.0, (pic50 - 6.0) / 6.0))
    return score

def safety_score(herg_um):
    # Higher hERG IC50 = safer; threshold at 1 uM
    if herg_um is None:
        return 0.5  # unknown -- neutral
    if herg_um <= 0:
        return 0.0
    # Log-scaled: 30 uM = 1.0, 1 uM = 0.5, 0.05 uM = 0 (withdrawn)
    score = max(0.0, min(1.0, math.log10(herg_um + 0.001) / math.log10(30)))
    return score

scored = []
for r in rows:
    cid = r.get('compound_id', '')
    pot_nm = safe_float(r.get(potency_col, ''))
    herg_um_raw = safe_float(r.get(safety_col, ''))

    # Safety assay may be in uM or nM -- detect by magnitude
    # hERG IC50 for most drugs is in uM range (0.05-30 uM)
    # If value > 100, assume nM and convert
    if herg_um_raw is not None and herg_um_raw > 100:
        herg_um = herg_um_raw / 1000.0
    else:
        herg_um = herg_um_raw

    ps = potency_score(pot_nm)
    ss = safety_score(herg_um)
    composite = pw * ps + sw * ss

    safety_flag = 'SAFE' if (herg_um is not None and herg_um >= herg_threshold) else 'UNSAFE'

    scored.append({
        'compound_id': cid,
        'potency_ic50_nm': pot_nm if pot_nm is not None else 'N/A',
        'herg_ic50_um': herg_um if herg_um is not None else 'N/A',
        'potency_score': round(ps, 4),
        'safety_score': round(ss, 4),
        'composite_score': round(composite, 4),
        'safety_flag': safety_flag,
    })

scored.sort(key=lambda x: -x['composite_score'])

with open('scored_compounds.csv', 'w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=['compound_id', 'potency_ic50_nm', 'herg_ic50_um',
                                           'potency_score', 'safety_score', 'composite_score', 'safety_flag'])
    writer.writeheader()
    writer.writerows(scored)

print(f'Scored {len(scored)} compounds')
for s in scored[:5]:
    print(f"  {s['compound_id']}: composite={s['composite_score']:.4f} ({s['safety_flag']})")
PYEOF
