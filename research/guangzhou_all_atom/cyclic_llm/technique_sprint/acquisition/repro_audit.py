#!/usr/bin/env python3
"""Pre-registration 1.9 C4: our `greedy` and `random` must reproduce the stored L5 `fp` and `random` per-round hits EXACTLY (regimes A, B; seeds 0-2). usage: repro_audit.py CSV OUT.json [--cache P]"""
import os, sys, json, subprocess, tempfile
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import acq as A
S3 = "s3://biomate-nextflow-work/cyclic_peptide/loop_retro/res5"
if __name__ == "__main__":
    csv, out = sys.argv[1], sys.argv[2]; cache = sys.argv[sys.argv.index("--cache") + 1] if "--cache" in sys.argv else None
    D = A.prepare(csv, cache); cfg = dict(lam=0.0, cap_src=50, cap_flat=A.BIG); rows = []; ok = True; tmp = tempfile.mkdtemp()
    for regime in ("A", "B"):
        for seed in (0, 1, 2):
            for mine, theirs in (("greedy", "fp"), ("random", "random")):
                f = f"{tmp}/{theirs}_{regime}_{seed}.json"; subprocess.run(["aws", "s3", "cp", f"{S3}/{theirs}_{regime}_{seed}.json", f, "--only-show-errors"], check=True)
                L5 = json.load(open(f)); init, pool, _ = A.setup(regime, seed, D); r = A.run_arm(mine, D, init, pool, seed, cfg)
                same = (r["rounds"] == L5["rounds"]) and (len(pool) == L5["n_pool"]); ok &= same
                rows.append(dict(arm=mine, vs=theirs, regime=regime, seed=seed, mine=r["rounds"], l5=L5["rounds"], n_pool=(len(pool), L5["n_pool"]), identical=same)); print(rows[-1], flush=True)
    json.dump(dict(all_identical=ok, rows=rows), open(out, "w"), indent=1); print("REPRO", "PASS" if ok else "FAIL"); sys.exit(0 if ok else 1)
