#!/usr/bin/env python3
"""Slice-0 cross-target proof: feed the closed loop the FIKK13 cross-target question via cofold.

FIKK13 has NO prepped target_spec (dispatch_cofold cold-starts), so this builds the cofold input
MANUALLY from the FIKK13 target sequence (data/display/target_proteins.json) + held-out candidate
peptides, reusing json_to_boltz_yaml.py + physics_batch._boltz_command on the SAME spot GPU
Batch job-def. Cofold-geometry (iptm/pTM/interface) is the loop's TRAINING reward; the INDEPENDENT
evaluation endpoint is the FIKK13 display `is_binder` label — kept separate (circularity control).

Usage:
  python slice0_fikk13_cofold.py --manifest        # build + store candidate manifest (binders+nonbinders+labels)
  python slice0_fikk13_cofold.py --smoke           # submit 3 cofolds (2 binder + 1 nonbinder) to prove the path
  python slice0_fikk13_cofold.py --full            # submit the full bounded sample
  (default = dry run: build + validate YAML, estimate cost, SPEND NOTHING)
"""
import json, gzip, csv, os, time, tempfile, subprocess, collections, sys, random
import physics_batch as PB  # reuse BUCKET/PREFIX/QUEUE/JOBDEF/_boltz_command/_boto

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
RESULTS = os.path.join(ROOT, "results")
TP = os.path.join(ROOT, "data/display/target_proteins.json")
CSV = os.path.join(ROOT, "data/display/display_ngs_multitarget.csv.gz")
CONV = os.path.join(HERE, "json_to_boltz_yaml.py")
N_NONBINDER = 62          # 38 distinct binders + 62 nonbinders = 100 cofolds (bounded for the ~$30-60 Slice-0)
RUN = "fikk13-xtarget-slice0"


def _auc(scores, labels):
    """AUC of scores vs binary labels (prob a random positive outranks a random negative)."""
    pos = [s for s, y in zip(scores, labels) if y == 1]
    neg = [s for s, y in zip(scores, labels) if y == 0]
    if not pos or not neg: return None
    c = sum((p > n) + 0.5 * (p == n) for p in pos for n in neg)
    return round(c / (len(pos) * len(neg)), 4)


def load_candidates():
    """CIRCULARITY-SAFE set. is_binder is a clean enrichment threshold AND read count trivially
    separates binders (median 89) from non-binders (median 3) -> an abundance null hits AUC~1.0.
    So we ABUNDANCE-MATCH: keep only binders/non-binders in the overlapping count window and match
    their count distributions, forcing the abundance (read-count) null to ~chance on the eval set.
    cofold-geometry never sees read counts, so cofold separating this set is NON-circular."""
    tseq = json.load(open(TP))["FIKK13"]["seq"]
    agg = {}
    with gzip.open(CSV, "rt") as f:
        for r in csv.DictReader(f):
            if not r["target"].startswith("FIKK13"): continue
            s = r["sequence"]; c = float(r.get("count") or 0); b = int(r.get("is_binder") or 0)
            if s not in agg: agg[s] = [0.0, 0]
            agg[s][0] = max(agg[s][0], c); agg[s][1] = max(agg[s][1], b)
    binders = [(s, c) for s, (c, b) in agg.items() if b == 1]
    nonb = [(s, c) for s, (c, b) in agg.items() if b == 0]
    # overlap window = [min binder count, max non-binder count] so both classes are representable
    lo = min(c for _, c in binders); hi = max(c for _, c in nonb)
    eb = [(s, c) for s, c in binders if lo <= c <= hi]
    en = [(s, c) for s, c in nonb if lo <= c <= hi]
    # BIN-EQUALIZE: split the window into log-spaced count bins; in each bin keep equal
    # numbers of binders and non-binders (min of the two) -> read count cannot separate the
    # retained set (null AUC -> ~0.5). Trades n for a clean, non-circular abundance control.
    import math
    K = 6
    edges = [lo * (hi / lo) ** (k / K) for k in range(K + 1)]
    def binof(c):
        for k in range(K):
            if edges[k] <= c <= edges[k + 1]: return k
        return K - 1
    rnd = random.Random(0)
    bb = collections.defaultdict(list); nn = collections.defaultdict(list)
    for s, c in eb: bb[binof(c)].append((s, c))
    for s, c in en: nn[binof(c)].append((s, c))
    keep_b, keep_n = [], []
    for k in range(K):
        m = min(len(bb[k]), len(nn[k]))
        if m == 0: continue
        rnd.shuffle(bb[k]); rnd.shuffle(nn[k])
        keep_b += bb[k][:m]; keep_n += nn[k][:m]
    cands = [{"id": f"B{i:03d}", "pep": s, "is_binder": 1, "count": c} for i, (s, c) in enumerate(keep_b)] + \
            [{"id": f"N{i:03d}", "pep": s, "is_binder": 0, "count": c} for i, (s, c) in enumerate(keep_n)]
    eb, matched_nb = keep_b, keep_n
    # the abundance NULL on this matched set (must be ~0.5, else still circular)
    null_auc = _auc([c["count"] for c in cands], [c["is_binder"] for c in cands])
    return tseq, cands, {"count_window": [lo, hi], "n_eval_binders": len(eb),
                         "n_matched_nonbinders": len(matched_nb), "abundance_null_auc": null_auc}


def validate_yaml(tseq, pep):
    ci = {"target": "FIKK13", "receptor_chains": {"A": tseq}, "ligands": [], "peptides": [{"id": "P", "pep": pep}]}
    td = tempfile.mkdtemp(); ij = os.path.join(td, "ci.json"); oy = os.path.join(td, "in.yaml")
    json.dump(ci, open(ij, "w"))
    rc = subprocess.run(["python3", CONV, ij, oy], capture_output=True, text=True)
    return rc.returncode == 0 and os.path.exists(oy), ci


def submit_one(cand, tseq):
    """Manual replica of dispatch_cofold for FIKK13 (no target_spec): upload input+converter, submit 1 spot job."""
    ok, ci = validate_yaml(tseq, cand["pep"])
    if not ok:
        return {"id": cand["id"], "error": "yaml build failed"}
    rid = f"{RUN}-{cand['id']}"
    base = f"s3://{PB.BUCKET}/{PB.PREFIX}/{rid}"
    in_s3, conv_s3, out_s3 = f"{base}/cofold_input.json", f"{base}/json_to_boltz_yaml.py", f"{base}/complexes/"
    s3 = PB._boto("s3")
    s3.put_object(Bucket=PB.BUCKET, Key=f"{PB.PREFIX}/{rid}/cofold_input.json", Body=json.dumps(ci).encode())
    s3.put_object(Bucket=PB.BUCKET, Key=f"{PB.PREFIX}/{rid}/json_to_boltz_yaml.py", Body=open(CONV, "rb").read())
    payload = dict(jobName=f"cofold-{rid}".replace("_", "-")[:120], jobQueue=PB.QUEUE, jobDefinition=PB.JOBDEF,
                   containerOverrides=dict(command=PB._boltz_command(in_s3, conv_s3, out_s3)),
                   tags={"pipeline": "cyclic-peptide", "stage": "cofold-xtarget", "target": "FIKK13", "cand": cand["id"]})
    jid = PB._boto("batch").submit_job(**payload)["jobId"]
    return {"id": cand["id"], "is_binder": cand["is_binder"], "jobId": jid, "out_s3": out_s3}


def main():
    mode = "dry"
    if "--smoke" in sys.argv: mode = "smoke"
    elif "--full" in sys.argv: mode = "full"
    elif "--manifest" in sys.argv: mode = "manifest"
    tseq, cands, match = load_candidates()
    nb = sum(c["is_binder"] for c in cands)
    os.makedirs(RESULTS, exist_ok=True)
    manifest = {"target": "FIKK13", "target_uniprot": "A0A143ZWL4", "n_candidates": len(cands),
                "n_binders": nb, "n_nonbinders": len(cands) - nb, "endpoint": "display is_binder (independent)",
                "reward": "cofold geometry (iptm/pTM) — NOT the eval endpoint (circularity control)",
                "circularity": {"note": "is_binder is an enrichment threshold AND read count trivially separates "
                                        "(binder median count 89 vs nonbinder 3); set is ABUNDANCE-MATCHED so the "
                                        "read-count null ~= chance -> cofold (never sees reads) is the non-circular test",
                                **match},
                "candidates": cands}
    json.dump(manifest, open(os.path.join(RESULTS, "slice0_fikk13_manifest.json"), "w"), indent=1)
    ok0, _ = validate_yaml(tseq, cands[0]["pep"])
    est_min = len(cands) * 15  # ~15 GPU-min per 561-aa-receptor cofold; spot ~$1-2/GPU-hr
    print(f"[manifest] {len(cands)} candidates ({nb} binders + {len(cands)-nb} nonbinders); YAML build ok={ok0}")
    print(f"[circularity] count window={match['count_window']}  ABUNDANCE-NULL AUC on matched set = {match['abundance_null_auc']}  "
          f"(must be ~0.5 to be non-circular; was ~1.0 before matching)")
    print(f"[cost] full sample: {len(cands)} cofolds x ~15 GPU-min = ~{est_min/60:.1f} GPU-hr ~= ${est_min/60*1.5:.0f}-${est_min/60*2:.0f} spot")
    if mode in ("dry", "manifest"):
        print(f"[{mode}] manifest written to results/slice0_fikk13_manifest.json; NO jobs submitted (spend nothing).")
        return
    sample = ([c for c in cands if c["is_binder"]][:2] + [c for c in cands if not c["is_binder"]][:1]) if mode == "smoke" else cands
    print(f"[{mode}] submitting {len(sample)} cofold job(s) to {PB.QUEUE} ...")
    subs = [submit_one(c, tseq) for c in sample]
    json.dump({"mode": mode, "submitted": subs}, open(os.path.join(RESULTS, f"slice0_fikk13_cofold_{mode}_jobs.json"), "w"), indent=1)
    for s in subs: print("  ", s.get("id"), "binder" if s.get("is_binder") else "nonbinder", "->", s.get("jobId", s.get("error")))


if __name__ == "__main__":
    main()
