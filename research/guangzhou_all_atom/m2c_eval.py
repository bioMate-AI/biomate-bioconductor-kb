#!/usr/bin/env python3
"""m2c_eval.py — TARGET-CONDITIONED acceptance eval for the 2c bound-cyclic generator, driving the OFFICIAL
PepGLAD pipeline (setup_latent_guidance.py -> generate.py -> cal_metrics.py) on the HELD-OUT D2 test split,
then emitting the full metric panel vs the SOTA-per-metric targets with the honest small-data caveat.

============================================================================================================
WHY THE OFFICIAL PIPELINE (not a hand-rolled eval like m2_eval.py's 2b path)
============================================================================================================
For 2c the receptor + a reference BOUND pose exist for every test target, so the FULL cal_metrics.py panel is
meaningful (unlike unconditional 2b). We therefore drive the STOCK generate.py + cal_metrics.py verbatim
(CLAUDE.md: leverage the official harness, don't reinvent). This file only ORCHESTRATES them + parses the
report; it does not re-implement any metric.

VERIFIED PIPELINE FACTS (fork-verified against the runtime — do NOT assume):
  * generate.py loads test_set = create_dataset(config['dataset'])[2] ('test' slot), samples n_samples per
    target, writes references/<id>_ref.pdb + candidates/<id>/<id>_gen_<n>.pdb + results.jsonl. get_summary
    reads mmap_dir/../pdbs/<id>.pdb -> the D2 pdbs/ dir MUST sit next to the mmap (m2c_process stages it there).
  * sample_opt.energy_func == 'default' -> ldm.latent_geometry_guidance ASSERTS consec_dist_mean is set
    (ldm.py:138-140). So setup_latent_guidance.py MUST run first (it computes consec-dist over TRAIN + re-saves
    the ckpt). We run it iff energy_func == default; with energy_func null we skip it.
  * cal_metrics.py CO-DESIGN mode (neither seq_only nor struct_only) computes: Slide AAR, RMSD(CA), DockQ,
    Sequence/Struct/Codesign Diversity, Consistency. The DockQ>=/RMSD<=/RMSD(full-atom) BUCKETS are gated
    behind struct_only (cal_metrics.py:71-98) — to also get those we run a SECOND struct_only generate+eval
    pass (optional, --struct-pass). It writes eval_report.json (per-id) + prints point-wise aggregates.
  * DockQ needs a git-clone+make of bjornwallner/DockQ v1.0 at import of evaluation.dockq (globals.py:19-23):
    needs git + a C/Fortran toolchain. The launcher installs these. If DockQ import/build fails, this driver
    catches it and reports DockQ as "unavailable" (never a silent 0). dG needs pyrosetta+ray+openmm (NOT in the
    env) -> ALWAYS reported N/A here (honest; matches the work-plan "dG if feasible").

SOTA-PER-METRIC TARGETS (from the work-plan): PepGLAD DockQ 0.592; D-Flow AAR 59% / RMSD 1.63 A.

USAGE (driven by run_m2c_ldm_finetune.sh on the instance):
  python3 m2c_eval.py \
      --m2c-ckpt ./ckpts/m2c_ldm_finetune/version_0/checkpoint/epochXX_stepYY.ckpt \
      --data-dir ./data/bound_cyclic_pepglad \
      --test-config m2c_test_codesign.yaml \
      --guidance-config m2c_setup_latent_guidance.yaml \
      --n-samples 16 --gpu 0 --out ./m2c_eval_result.json
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
RUNTIME = ROOT / "runtime" / "PepGLAD"

# SOTA-per-metric bars (work-plan): match-or-beat is the strength gate.
SOTA = {
    "DockQ": {"value": 0.592, "source": "PepGLAD", "better": "higher"},
    "Slide AAR": {"value": 0.59, "source": "D-Flow (59%)", "better": "higher"},
    "RMSD(CA)": {"value": 1.63, "source": "D-Flow (1.63 A)", "better": "lower"},
}


def _run(cmd, env, cwd, log_prefix):
    """Run a subprocess, streaming to stdout with a prefix, returning (rc, tail_of_output)."""
    print(f"\n[m2c_eval] $ {' '.join(str(c) for c in cmd)}", flush=True)
    proc = subprocess.Popen(cmd, cwd=cwd, env=env, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True, bufsize=1)
    lines = []
    for line in proc.stdout:
        sys.stdout.write(f"[{log_prefix}] {line}")
        lines.append(line)
    proc.wait()
    return proc.returncode, "".join(lines[-80:])


def _check_dockq_available(env, cwd):
    """Import evaluation.dockq in a subprocess (it git-clones + makes DockQ on first import). Returns
    (available: bool, detail: str). We isolate it so a build failure NEVER aborts the whole eval — DockQ is
    then reported unavailable, not silently 0."""
    probe = (
        "import sys; sys.path.insert(0, '.');\n"
        "try:\n"
        "    from evaluation.dockq import dockq\n"
        "    print('DOCKQ_OK')\n"
        "except Exception as e:\n"
        "    print('DOCKQ_FAIL:' + type(e).__name__ + ':' + str(e)[:200])\n"
    )
    rc, out = _run([sys.executable, "-c", probe], env, cwd, "dockq-probe")
    return ("DOCKQ_OK" in out), out.strip().splitlines()[-1] if out.strip() else ""


def _parse_cal_metrics_stdout(text: str):
    """Parse cal_metrics.py's point-wise stdout block into {metric: value}. Lines look like:
       'DockQ(mean): 0.31', 'RMSD(CA)(median): 2.4', 'Slide AAR(mean): 0.41',
       'Sequence Diversity (mean): 0.6', 'Consistency (mean): 0.5', 'DockQ>=0.23: 0.2'
    We capture both '<name>(mean|median): v' and '<name> (mean): v' and '<name>: v' forms."""
    import re
    out = {}
    for line in text.splitlines():
        m = re.match(r"^\s*([A-Za-z0-9_()>=<.\- ]+?)\s*(?:\((mean|median)\))?\s*:\s*([-+0-9.eE]+)\s*$", line)
        if not m:
            continue
        name = m.group(1).strip()
        try:
            val = float(m.group(3))
        except ValueError:
            continue
        # keep the cleanest key (strip trailing '(mean)'/'(median)' already handled by regex group)
        if name and name not in ("lowest", "highest", "id"):
            out[name] = val
    return out


def _sota_line(metric, value):
    s = SOTA.get(metric)
    if s is None or value is None:
        return None
    if s["better"] == "higher":
        passed = value >= s["value"]
    else:
        passed = value <= s["value"]
    return {"metric": metric, "measured": value, "sota": s["value"], "sota_source": s["source"],
            "better": s["better"], "match_or_beat": bool(passed)}


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--m2c-ckpt", type=Path, required=True)
    ap.add_argument("--data-dir", type=Path, required=True,
                    help="the D2 base dir (m2c_process_complexes --out-dir): contains pdbs/ and processed/")
    ap.add_argument("--test-config", type=Path, default=ROOT / "m2c_test_codesign.yaml")
    ap.add_argument("--guidance-config", type=Path, default=ROOT / "m2c_setup_latent_guidance.yaml")
    ap.add_argument("--n-samples", type=int, default=16)
    ap.add_argument("--gpu", type=int, default=0)
    ap.add_argument("--num-workers", type=int, default=4, help="cal_metrics workers")
    ap.add_argument("--struct-pass", action="store_true",
                    help="also run a struct_only pass to get DockQ>=/RMSD<= buckets + RMSD(full-atom)")
    ap.add_argument("--out", type=Path, default=ROOT / "m2c_eval_result.json")
    args = ap.parse_args(argv)

    cwd = str(RUNTIME)   # run the stock scripts from the PepGLAD root (their imports assume cwd == repo root)
    env = dict(os.environ)
    env["PYTHONPATH"] = f"{RUNTIME}:{ROOT}:" + env.get("PYTHONPATH", "")
    env.setdefault("PYTORCH_CUDA_ALLOC_CONF", "expandable_segments:True")
    # the stock scripts must unpickle the v1 AE class -> ensure m1_closure_ae is importable & imported. We do
    # this by pre-pending a sitecustomize-style import via PYTHONSTARTUP is unreliable in subprocess; instead we
    # pass -c wrappers that import the registration module first, then exec the stock script.

    if not args.m2c_ckpt.is_file():
        print(f"FATAL: --m2c-ckpt not found: {args.m2c_ckpt}", file=sys.stderr)
        return 2
    ckpt = str(args.m2c_ckpt.resolve())
    test_cfg = str(args.test_config.resolve())
    guid_cfg = str(args.guidance_config.resolve())
    # the mmap lives in <base>/processed; pdbs at <base>/pdbs (get_summary resolves processed/../pdbs).
    processed_dir = str((args.data_dir / "processed").resolve())
    test_index = os.path.join(processed_dir, "test_index.txt")

    report = {
        "experiment": "M2 stage-2c target-conditioned eval on HELD-OUT bound cyclic complexes (official panel)",
        "utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "m2c_ckpt": ckpt,
        "n_samples": args.n_samples,
        "sota_targets": SOTA,
        "panel_NA": {"dG": "needs pyrosetta+ray+openmm (not in env) — reported N/A (work-plan: dG if feasible)"},
        "steps": {},
    }

    # a tiny launcher that imports the AE/model registration then execs a stock script with argv
    def stock(script, script_args):
        wrapper = (
            "import sys; sys.path.insert(0,'.'); sys.path.insert(0, r'%s');\n"
            "import m1_closure_ae  # register v1 AE class for unpickle\n"
            "import models  # register LDMPepDesign/AutoEncoder/CoDesignDataset\n"
            "sys.argv = %r\n"
            "exec(open(%r).read())\n"
        ) % (str(ROOT), [script] + [str(a) for a in script_args], str(RUNTIME / script))
        return _run([sys.executable, "-c", wrapper], env, cwd, script.replace(".py", ""))

    # read the test config to know if energy guidance is on (=> setup_latent_guidance needed)
    import yaml
    tcfg = yaml.safe_load(open(test_cfg))
    energy_func = (tcfg.get("sample_opt") or {}).get("energy_func")

    try:
        # ---- 0. DockQ availability (git-clone+make on first import) ----
        dockq_ok, dockq_detail = _check_dockq_available(env, cwd)
        report["steps"]["dockq_available"] = {"ok": dockq_ok, "detail": dockq_detail}

        # ---- 1. setup_latent_guidance (only if energy guidance is requested) ----
        if energy_func == "default":
            rc, _ = stock("setup_latent_guidance.py",
                          ["--config", guid_cfg, "--ckpt", ckpt, "--gpu", args.gpu])
            report["steps"]["setup_latent_guidance"] = {"rc": rc}
            if rc != 0:
                raise RuntimeError("setup_latent_guidance.py failed (needed for energy_func:default)")
        else:
            report["steps"]["setup_latent_guidance"] = {"skipped": "energy_func is not 'default'"}

        # ---- 2. generate on the held-out test split (co-design mode) ----
        gen_dir = str((args.out.parent / "m2c_gen_codesign").resolve())
        rc, _ = stock("generate.py",
                      ["--config", test_cfg, "--ckpt", ckpt, "--gpu", args.gpu,
                       "--save_dir", gen_dir,
                       "--dataset.test.mmap_dir=" + processed_dir,
                       "--dataset.test.specify_index=" + test_index,
                       "--n_samples=%d" % args.n_samples])
        report["steps"]["generate_codesign"] = {"rc": rc, "save_dir": gen_dir}
        if rc != 0:
            raise RuntimeError("generate.py (co-design) failed")

        # ---- 3. cal_metrics (co-design panel) ----
        results_jsonl = os.path.join(gen_dir, "results.jsonl")
        rc, cm_out = stock("cal_metrics.py",
                           ["--results", results_jsonl, "--num_workers", args.num_workers])
        report["steps"]["cal_metrics_codesign"] = {"rc": rc}
        panel = _parse_cal_metrics_stdout(cm_out) if rc == 0 else {}
        report["panel_codesign"] = panel

        # ---- 4. optional struct_only pass for bucket metrics ----
        if args.struct_pass:
            gen_dir_s = str((args.out.parent / "m2c_gen_struct").resolve())
            rc, _ = stock("generate.py",
                          ["--config", test_cfg, "--ckpt", ckpt, "--gpu", args.gpu,
                           "--save_dir", gen_dir_s,
                           "--struct_only=True",
                           "--dataset.test.mmap_dir=" + processed_dir,
                           "--dataset.test.specify_index=" + test_index,
                           "--n_samples=%d" % args.n_samples])
            if rc == 0:
                rc2, cm_out2 = stock("cal_metrics.py",
                                     ["--results", os.path.join(gen_dir_s, "results.jsonl"),
                                      "--num_workers", args.num_workers])
                report["panel_struct_only"] = _parse_cal_metrics_stdout(cm_out2) if rc2 == 0 else {}
            report["steps"]["struct_pass"] = {"rc": rc}

        # ---- 5. SOTA comparison ----
        sota_cmp = []
        for metric in ("DockQ", "Slide AAR", "RMSD(CA)"):
            val = panel.get(metric)
            if metric == "DockQ" and not dockq_ok:
                sota_cmp.append({"metric": "DockQ", "measured": None,
                                 "status": "unavailable (DockQ build failed)"})
                continue
            line = _sota_line(metric, val)
            if line:
                sota_cmp.append(line)
        report["sota_comparison"] = sota_cmp

        report["caveat"] = (
            "SMALL DATA: n~235 experimental bound cyclic complexes, held-out test ~24-30 targets, "
            "leakage-controlled by whole-cluster split. Expect a WEAK-BUT-REAL target-conditioned signal, "
            "NOT SOTA. A DockQ/AAR below the SOTA bar is EXPECTED at this data scale and is honest; the "
            "signal is: does target-conditioned fine-tuning on real complexes move the panel above the "
            "warm-start prior (run the same eval on the epoch-221 warm-start as the baseline to attribute "
            "any lift). dG is N/A (needs pyrosetta). DockQ requires the git-clone+make build to have succeeded."
        )
        report["status"] = "ok"
    except Exception as e:  # noqa: BLE001
        import traceback
        report["status"] = "error"
        report["error"] = f"{type(e).__name__}: {e}"
        report["traceback"] = traceback.format_exc()
        print(report["traceback"], file=sys.stderr)

    Path(args.out).write_text(json.dumps(report, indent=2, default=float))
    print("\n" + json.dumps({"status": report["status"],
                             "panel_codesign": report.get("panel_codesign", {}),
                             "sota_comparison": report.get("sota_comparison", [])},
                            indent=2, default=float))
    return 0 if report.get("status") == "ok" else 1


if __name__ == "__main__":
    raise SystemExit(main())
