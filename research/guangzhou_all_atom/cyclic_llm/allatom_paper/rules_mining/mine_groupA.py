"""Re-mine the soft-rule weights from TRAIN source group A only (coordinator task; contracts.KNOWN_ISSUES).

Why: kb_audit/peptide_sar_rules_v1.json was mined from all 21 training sources, so it fails ihlm.symbolic.assert_priors_clean for
any experiment whose stop / held-out verifiers are fitted on sources S or B. Group definition = allatom_paper/track_e/verifiers_e.py
`source_groups` (deterministic size-balanced round-robin: A=0 train, S=1 stop, B=2 held-out), computed on that module's own
`load_labelled`. The mining code is the EXISTING kb_audit/peptide_sar_kb.py `fit` (not rewritten); this script only restricts the sources.
Outputs (next to this file unless --out is given): peptide_sar_rules_v1_groupA.json and groupA_manifest.json. Hard rules (ring, N-Me
window, MW, PAINS) are not data-mined and are unaffected.
Run on EC2 / Spark only."""
import argparse
import hashlib
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CYC = os.path.abspath(os.path.join(HERE, "..", ".."))
for p in (os.path.join(CYC, "kb_audit"), os.path.join(CYC, "stratification"), os.path.join(CYC, "allatom_paper", "track_e"),
          os.path.join(CYC, "allatom_paper"), CYC):
    sys.path.insert(0, p)


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main(out_dir=HERE, debug_recompute=False, groups_file=None):
    import pandas as pd
    import common as C                     # stratification/common.py (same loader the all-lab mining used)
    import peptide_sar_kb as P             # kb_audit/peptide_sar_kb.py: the existing mining code
    import verifiers_e as E                # group definition (Track E)

    te = os.path.join(CYC, "allatom_paper", "track_e")
    sg_path = groups_file or (os.path.join(te, "source_groups_v2.json") if os.path.exists(os.path.join(te, "source_groups_v2.json"))
                              else os.path.join(te, "source_groups.json"))
    if os.path.exists(sg_path) and not debug_recompute:
        sg = json.load(open(sg_path))        # the COMMITTED membership (owner/coordinator rule: do not recompute groups)
        mem = sg["membership"]
        A = sorted(s for s, v in mem.items() if v["group"] == "A")
        S = sorted(s for s, v in mem.items() if v["group"] == "S")
        B = sorted(s for s, v in mem.items() if v["group"] == "B")
        groups_from = dict(file="allatom_paper/track_e/" + os.path.basename(sg_path), sha256=sha256_file(sg_path),
                           annotation_sha256=sg.get("annotation_sha256"))
    elif debug_recompute:
        groups = E.source_groups(E.load_labelled())          # DEBUG ONLY: output must not be used in any comparison
        A = sorted(s for s, g in groups.items() if g == 0)
        S = sorted(s for s, g in groups.items() if g == 1)
        B = sorted(s for s, g in groups.items() if g == 2)
        groups_from = dict(file="RECOMPUTED (debug; not for use)", sha256=None)
    else:
        raise SystemExit("committed source-group file not found: refusing to recompute groups")

    d = C.load_labelled()
    pairs_path = os.path.join(CYC, "stratification", "data", "mmp_pairs_pampa.csv.gz")
    pairs = pd.read_csv(pairs_path)
    vc = d.Source.value_counts()
    elig = sorted(vc[vc >= P.MIN_SRC_N].index)
    d = d[d.Source.isin(elig)].copy()
    pairs = pairs[pairs.source.isin(elig)].copy()
    trainA = [s for s in A if s in set(elig)]
    assert trainA, "no eligible group-A source"
    assert not (set(trainA) & (set(S) | set(B))), "group overlap"
    rs = P.fit(pairs, d, trainA)           # mines ONLY from trainA (fit filters rules by train_sources)
    out_json = os.path.join(out_dir, "peptide_sar_rules_v1_groupA.json")
    rs.to_json(out_json)
    # per-rule support and drop-one-source sensitivity (coordinator requests): rules mined on few sources are narrow
    def pick(r):
        return None if r is None else {k: (float(r[k]) if isinstance(r.get(k), (int, float)) else r.get(k))
                                       for k in ("status", "weight", "ci", "effect_z", "ci_z") if k in r}
    support = {name: len(r.get("mined_from", [])) for name, r in rs.rules.items()}
    sens = {"all_A": {name: pick(r) for name, r in rs.rules.items()}}
    nt_json = None
    for src in trainA:
        rest = [x for x in trainA if x != src]
        key = "without_" + src
        if not rest:
            sens[key] = "no source left"
            continue
        try:
            rr = P.fit(pairs, d, rest)
            sens[key] = {name: pick(r) for name, r in rr.rules.items()}
            if src == "2020_Townsend":
                nt_json = os.path.join(out_dir, "peptide_sar_rules_v1_groupA_noTownsend.json")
                rr.to_json(nt_json)
        except Exception as e:                       # a single remaining source may not support any rule
            sens[key] = f"fit failed: {type(e).__name__}: {str(e)[:120]}"
    for key, val in list(sens.items()):
        if isinstance(val, dict) and key != "all_A":
            for name, r in val.items():
                wa = (sens["all_A"].get(name) or {}).get("weight")
                wb = (r or {}).get("weight")
                if isinstance(r, dict) and isinstance(wa, (int, float)) and isinstance(wb, (int, float)):
                    r["same_sign_as_all_A"] = bool(wa * wb > 0)
    with open(os.path.join(out_dir, "groupA_sensitivity.json"), "w") as fh:
        json.dump(dict(sources_all_A=trainA, rule_support_n_sources=support, sensitivity=sens), fh, indent=1, default=str)
    manifest = dict(
        description="soft-rule weights re-mined on TRAIN source group A only",
        group_rule="committed membership file allatom_paper/track_e/source_groups.json (pattern [0,1,2,2,1,0], sources by (-n, name))",
        groups_from=groups_from,
        group_A_sources_used=trainA, group_A_all=A, group_S=S, group_B=B,
        eligible_sources_all=elig, min_src_n=P.MIN_SRC_N,
        n_peptides_used=int(d.Source.isin(trainA).sum()), n_pairs_used=int(pairs.source.isin(trainA).sum()), sensitivity_file='groupA_sensitivity.json', rule_support_n_sources=support,
        output_sha256_noTownsend=(sha256_file(nt_json) if nt_json else None),
        input_sha256=dict(mmp_pairs=sha256_file(pairs_path)), output_sha256=sha256_file(out_json),
        mining_code="kb_audit/peptide_sar_kb.py fit(pairs, d, train_sources) (unmodified)")
    with open(os.path.join(out_dir, "groupA_manifest.json"), "w") as fh:
        json.dump(manifest, fh, indent=1)
    print(json.dumps({k: (v if not isinstance(v, list) else len(v)) for k, v in manifest.items()}, indent=1))
    return manifest


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=HERE)
    ap.add_argument("--debug-recompute-groups", action="store_true", help="debug only; output not for use")
    ap.add_argument("--groups-file", default=None)
    a = ap.parse_args()
    main(a.out, a.debug_recompute_groups, a.groups_file)
