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


def load_candidates():
    tseq = json.load(open(TP))["FIKK13"]["seq"]
    seen = collections.OrderedDict()
    with gzip.open(CSV, "rt") as f:
        for r in csv.DictReader(f):
            if r["target"].startswith("FIKK13"):
                s = r["sequence"]
                if s not in seen:
                    seen[s] = int(r.get("is_binder") or 0)
    binders = [s for s, b in seen.items() if b == 1]
    nonb = [s for s, b in seen.items() if b == 0]
    random.Random(0).shuffle(nonb)
    # length-match nonbinders to the binder length distribution (avoid a trivial length confound)
    blen = collections.Counter(len(s) for s in binders)
    picked, need = [], dict(blen)
    for s in nonb:
        if need.get(len(s), 0) > 0:
            picked.append(s); need[len(s)] -= 1
        if len(picked) >= N_NONBINDER:
            break
    for s in nonb:  # top up if length-match ran short
        if len(picked) >= N_NONBINDER: break
        if s not in picked: picked.append(s)
    cands = [{"id": f"B{i:03d}", "pep": s, "is_binder": 1} for i, s in enumerate(binders)] + \
            [{"id": f"N{i:03d}", "pep": s, "is_binder": 0} for i, s in enumerate(picked)]
    return tseq, cands


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
    tseq, cands = load_candidates()
    nb = sum(c["is_binder"] for c in cands)
    os.makedirs(RESULTS, exist_ok=True)
    manifest = {"target": "FIKK13", "target_uniprot": "A0A143ZWL4", "n_candidates": len(cands),
                "n_binders": nb, "n_nonbinders": len(cands) - nb, "endpoint": "display is_binder (independent)",
                "reward": "cofold geometry (iptm/pTM) — NOT the eval endpoint (circularity control)",
                "candidates": cands}
    json.dump(manifest, open(os.path.join(RESULTS, "slice0_fikk13_manifest.json"), "w"), indent=1)
    ok0, _ = validate_yaml(tseq, cands[0]["pep"])
    # ~15 GPU-min per 561-aa-receptor cofold; spot ~$1-2/GPU-hr
    est_min = len(cands) * 15
    print(f"[manifest] {len(cands)} candidates ({nb} binders + {len(cands)-nb} nonbinders); YAML build ok={ok0}")
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
