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


def main(out_dir=HERE):
    import pandas as pd
    import common as C                     # stratification/common.py (same loader the all-lab mining used)
    import peptide_sar_kb as P             # kb_audit/peptide_sar_kb.py: the existing mining code
    import verifiers_e as E                # group definition (Track E)

    groups = E.source_groups(E.load_labelled())
    A = sorted(s for s, g in groups.items() if g == 0)
    S = sorted(s for s, g in groups.items() if g == 1)
    B = sorted(s for s, g in groups.items() if g == 2)

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
    manifest = dict(
        description="soft-rule weights re-mined on TRAIN source group A only",
        group_rule="allatom_paper/track_e/verifiers_e.py source_groups (order [0,1,2,2,1,0], sources by descending size)",
        group_A_sources_used=trainA, group_A_all=A, group_S=S, group_B=B,
        eligible_sources_all=elig, min_src_n=P.MIN_SRC_N,
        n_peptides_used=int(d.Source.isin(trainA).sum()), n_pairs_used=int(pairs.source.isin(trainA).sum()),
        input_sha256=dict(mmp_pairs=sha256_file(pairs_path)), output_sha256=sha256_file(out_json),
        mining_code="kb_audit/peptide_sar_kb.py fit(pairs, d, train_sources) (unmodified)")
    with open(os.path.join(out_dir, "groupA_manifest.json"), "w") as fh:
        json.dump(manifest, fh, indent=1)
    print(json.dumps({k: (v if not isinstance(v, list) else len(v)) for k, v in manifest.items()}, indent=1))
    return manifest


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=HERE)
    main(ap.parse_args().out)
