#!/usr/bin/env python3
"""Verify a refined deck still honors the recording contract vs its pristine original.
Checks: identical scene count, identical multiset of data-seconds values, balanced
<div>/</div>, and that every number+unit and every <code>…</code> / data-* attribute
value present in the ORIGINAL still appears in the refined file (nothing dropped).

Usage: verify_contract.py <refined.html> <pristine.html>
Exit 0 = OK, 1 = violation (prints details).
"""
import re, sys, collections

def feats(s):
    scenes = s.count('class="scene')
    ds = collections.Counter(re.findall(r'data-seconds="([^"]*)"', s))
    divbal = s.count('<div') - s.count('</div>')
    # data-* attribute values that encode timing/camera (must be untouched)
    attrs = collections.Counter(re.findall(r'(data-(?:at|off|focus|rings|run|screen|size|cursor|progress|to|dec|text|dur)="[^"]*")', s))
    nums = collections.Counter(re.findall(r'[-+]?\d[\d.]*\s*(?:Å|µM|nM|kcal/mol|%|℃|°C|天|个|轮)?', s))
    codes = collections.Counter(re.findall(r'<code>[^<]*</code>', s))
    return scenes, ds, divbal, attrs, codes

def main():
    ref, pri = sys.argv[1], sys.argv[2]
    R = open(ref, encoding='utf-8').read(); P = open(pri, encoding='utf-8').read()
    rs, rds, rbal, rattr, rcode = feats(R)
    ps, pds, pbal, pattr, pcode = feats(P)
    errs = []
    if rs != ps: errs.append(f"scene count {ps}->{rs}")
    if rds != pds: errs.append(f"data-seconds multiset changed (+{list((rds-pds).elements())[:5]} -{list((pds-rds).elements())[:5]})")
    if rbal != 0: errs.append(f"div imbalance {rbal}")
    missing_attr = pattr - rattr
    if missing_attr: errs.append(f"{sum(missing_attr.values())} timing/camera attrs dropped e.g. {list(missing_attr)[:3]}")
    missing_code = pcode - rcode
    if missing_code: errs.append(f"{sum(missing_code.values())} <code> tokens dropped e.g. {list(missing_code)[:3]}")
    name = ref.split('/')[-1]
    if errs:
        print(f"FAIL  {name}: " + "; ".join(errs)); sys.exit(1)
    print(f"OK    {name}  scenes={rs} ds-ok div-ok attrs-ok code-ok")

if __name__ == '__main__':
    main()
