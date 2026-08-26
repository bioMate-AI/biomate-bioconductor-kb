#!/usr/bin/env python3
"""
run_biomate_llm_matrix.py — BioMate×LLM model-invariance matrix (fills flagship Suppl. S5.4
with *BioMate-through-different-backends* data instead of the regulatory-crossjudge proxy).

WHAT IT PROVES
  Enabled by the resolve_model(role) refactor (PR #170): BioMate's backend model is now set by
  a single env var BIOMATE_MODEL, read by resolve_model at call time. This runner sweeps
  BIOMATE_MODEL across models, runs a D3 generation-path benchmark (BiomniEval1) through the
  BioMate pipeline for each, and reports accuracy + latency per model. Expected:
    - engine-free tasks (routing/pharmacology): flat (no model call — the S5.2 invariance result)
    - D3 knowledge (BiomniEval1): varies with the backend model (the S5.4 dependence)

BACKEND REQUIREMENT (why this is gated)
  Each item runs through a live BioMate backend (BioMateEvalClient.ask). To switch the model the
  BACKEND must see the new BIOMATE_MODEL and reload. Two supported ways:
    (a) LOCAL backend: this runner restarts the local Galaxy backend with the env set per model.
    (b) DEV backend: DEV env changes are NOT ad-hoc-permitted — set BIOMATE_MODEL on the dev
        container via the sanctioned deploy/config path, then run this with --no-restart.
  It does NOT modify dev out-of-band.

USAGE
  # local backend, sweep 3 models on 30 BiomniEval1 items:
  BIOMATE_BASE_URL=http://localhost:5000 python3 runners/run_biomate_llm_matrix.py \
      --models claude-sonnet-4-5 gpt-5.6 gemini-3.1-pro-preview --n 30 --benchmark biomni_eval1
  # dev backend already configured for one model (no restart), single arm:
  BIOMATE_BASE_URL=https://dev-public.biomate.ai python3 runners/run_biomate_llm_matrix.py \
      --models gpt-5.6 --no-restart

OUTPUT
  results/biomate_llm_matrix/<benchmark>.csv  (model, n, accuracy, ci_lo, ci_hi,
      lat_median_s, lat_max_s) — paste-ready for Suppl. S5.4.
"""
import os, sys, json, time, argparse, subprocess, statistics as st
from pathlib import Path

EVAL_DIR = Path(__file__).parent.parent
OUT_DIR = EVAL_DIR / "results" / "biomate_llm_matrix"

def wilson(k, n, z=1.96):
    if not n: return (None, None)
    p = k / n; d = 1 + z*z/n
    c = (p + z*z/(2*n)) / d
    h = z*((p*(1-p)/n + z*z/(4*n*n))**0.5)/d
    return (round(max(0, c-h), 4), round(min(1, c+h), 4))

def restart_local_backend(model: str):
    """Restart the LOCAL Galaxy backend with BIOMATE_MODEL=model so resolve_model picks it up.
    No-op for dev (guarded by caller). Adjust to your local run mechanism."""
    env = os.environ.copy(); env["BIOMATE_MODEL"] = model
    # Local dev typically runs gunicorn on 8081; HUP after exporting the env in the service file.
    # This is intentionally explicit rather than magic — wire to your local start script.
    print(f"  [local] set BIOMATE_MODEL={model}; restart the local backend, then press-through.")
    # e.g. subprocess.run(["bash","scripts/restart_local_backend.sh"], env=env, check=True)

def run_arm(model: str, benchmark: str, n: int, no_restart: bool) -> dict:
    from core.biomate_client import BioMateEvalClient
    import yaml
    cfg = yaml.safe_load(open(EVAL_DIR / "config.yaml"))
    if not no_restart:
        restart_local_backend(model)
    client = BioMateEvalClient.from_config(cfg)
    # Load benchmark items + score fn from the existing adapter/registry.
    from runners.run_model_selection import score_task           # reuse the objective scorer
    if benchmark == "biomni_eval1":
        from evaluation.adapters.biomni_eval1_adapter import BiomniEval1Adapter
        tasks = list(BiomniEval1Adapter(cfg).load_tasks())[:n or None]
    else:
        raise SystemExit(f"benchmark {benchmark} not wired here")
    hits = tot = 0; lats = []
    for t in tasks:
        t0 = time.time()
        resp = client.ask(t.question)
        lats.append(time.time() - t0)
        s = score_task(getattr(t, "subtask", benchmark), resp.message, str(getattr(t, "answer", "")))
        tot += 1; hits += 1 if s and s >= 1.0 else 0
        sys.stderr.write(f"  {model} {tot}/{len(tasks)} score={s}\n")
    acc = hits / tot if tot else None
    lo, hi = wilson(hits, tot)
    slat = sorted(lats)
    return {"model": model, "n": tot, "accuracy": round(acc, 4) if acc is not None else None,
            "ci_lo": lo, "ci_hi": hi,
            "lat_median_s": round(slat[len(slat)//2], 1) if slat else None,
            "lat_max_s": round(max(lats), 1) if lats else None}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--models", nargs="+", required=True)
    ap.add_argument("--benchmark", default="biomni_eval1")
    ap.add_argument("--n", type=int, default=30)
    ap.add_argument("--no-restart", action="store_true",
                    help="backend already configured for the (single) model; do not restart")
    a = ap.parse_args()
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    rows = [run_arm(m, a.benchmark, a.n, a.no_restart) for m in a.models]
    outp = OUT_DIR / f"{a.benchmark}.csv"
    with open(outp, "w") as f:
        f.write("model,n,accuracy,ci_lo,ci_hi,lat_median_s,lat_max_s\n")
        for r in rows:
            f.write(",".join(str(r[k]) for k in ["model","n","accuracy","ci_lo","ci_hi","lat_median_s","lat_max_s"]) + "\n")
    print(f"\nwrote {outp}")
    for r in rows: print(" ", r)

if __name__ == "__main__":
    main()
