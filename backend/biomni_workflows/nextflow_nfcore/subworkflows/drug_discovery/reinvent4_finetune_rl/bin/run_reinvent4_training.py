#!/usr/bin/env python3
"""
Batch entrypoint for REINVENT4 training: generator fine-tuning
(transfer_learning) and/or reinforcement learning (staged_learning).

This is the executable that makes deck slide 4 REAL — "models trained on your own
data — generator fine-tuning + reinforcement learning". It drives the unchanged
production trainer:
    backend/lib/galaxy/ai/drug_discovery/reinvent4_trainer.py
baked into the reinvent4-nf container at /opt/biomate/drug_discovery
(PYTHONPATH=/opt/biomate), with the reinvent CLI + priors present.

Stages (selectable with --stage):
  transfer   fine-tune the base prior on --train-smiles -> new checkpoint
  rl         RL-optimise vs the multi-objective reward -> new checkpoint
  both       transfer, then RL seeded from the transfer-learned checkpoint

HONESTY: any missing CLI / prior / data, or a non-zero REINVENT4 exit, makes this
exit NON-ZERO and writes a diagnosable training_summary.json — it never fabricates
a checkpoint. A real result is a genuine REINVENT4 .model on disk or nothing.

Live ECR bridge (2026-11-10 image): seeds /opt/REINVENT4 on PYTHONPATH and
Zenodo-fetches reinvent_pubchem.prior when staged priors are missing — same
contract as GENERATE_REINVENT4 / drug_discovery.reinvent4_runtime.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
import urllib.error
import urllib.request


def _bootstrap_live_ecr_layout() -> None:
    for src_root in ("/opt/REINVENT4", "/opt/reinvent4", "/opt/reinvent"):
        if os.path.isdir(os.path.join(src_root, "reinvent")):
            os.environ["PYTHONPATH"] = (
                src_root + os.pathsep + os.environ.get("PYTHONPATH", "")
            )
            if src_root not in sys.path:
                sys.path.insert(0, src_root)
            break


_bootstrap_live_ecr_layout()


def _import_trainer():
    errors = []
    for mod_root in ("drug_discovery", "backend.lib.galaxy.ai.drug_discovery"):
        try:
            return __import__(f"{mod_root}.reinvent4_trainer", fromlist=["*"])
        except Exception as exc:  # pragma: no cover - env dependent
            errors.append(f"{mod_root}: {exc}")
    sys.stderr.write(
        "FATAL: cannot import reinvent4_trainer. Tried:\n  "
        + "\n  ".join(errors)
        + "\n(Expected PYTHONPATH=/opt/biomate in the reinvent4-nf container.)\n"
    )
    sys.exit(2)


def _ensure_prior(explicit):
    """Resolve prior path; Zenodo-fetch when staged priors missing (live ECR)."""
    if explicit and os.path.isfile(explicit):
        return explicit
    try:
        from drug_discovery.reinvent4_runtime import find_or_fetch_prior
        return find_or_fetch_prior(["reinvent.prior", "reinvent_pubchem.prior"])
    except Exception:
        pass
    dirs = [
        os.environ.get("REINVENT4_PRIORS", "/opt/reinvent4/priors"),
        "/opt/reinvent4/priors",
        "/opt/REINVENT4/priors",
    ]
    names = ["reinvent.prior", "reinvent_pubchem.prior"]
    for d in dirs:
        for name in names:
            path = os.path.join(d, name)
            try:
                if os.path.isfile(path) and os.path.getsize(path) > 1_000_000:
                    return path
            except OSError:
                continue
    url = (
        "https://zenodo.org/api/records/20701824/files/reinvent_pubchem.prior/content"
    )
    cache = os.path.join(tempfile.gettempdir(), "reinvent4_priors")
    os.makedirs(cache, exist_ok=True)
    dest = os.path.join(cache, "reinvent.prior")
    if not (os.path.isfile(dest) and os.path.getsize(dest) > 1_000_000):
        print("Fetching REINVENT4 prior reinvent.prior from Zenodo…", flush=True)
        try:
            req = urllib.request.Request(
                url, headers={"User-Agent": "biomate-reinvent4/1.0"}
            )
            with urllib.request.urlopen(req, timeout=120) as resp:
                data = resp.read()
            if len(data) <= 1_000_000:
                return None
            tmp = dest + ".partial"
            with open(tmp, "wb") as fh:
                fh.write(data)
            os.replace(tmp, dest)
        except (urllib.error.URLError, OSError, TimeoutError) as exc:
            print(f"WARN: Zenodo prior fetch failed: {exc}", flush=True)
            return None
    return dest if os.path.isfile(dest) else None


_t = _import_trainer()
Reinvent4TransferLearner = _t.Reinvent4TransferLearner
Reinvent4StagedLearner = _t.Reinvent4StagedLearner
RewardComponent = _t.RewardComponent
default_multi_objective_reward = _t.default_multi_objective_reward


def _parse_reward(spec: str) -> list:
    """`affinity:1.0,sa:0.6,herg_proxy:0.6,qed:0.4` -> [RewardComponent, ...]"""
    if not spec or spec.strip().lower() == "default":
        return default_multi_objective_reward()
    comps = []
    for token in spec.split(","):
        token = token.strip()
        if not token:
            continue
        if ":" in token:
            kind, weight = token.split(":", 1)
            comps.append(RewardComponent(kind.strip(), weight=float(weight)))
        else:
            comps.append(RewardComponent(token))
    return comps


def _write_summary(payload: dict) -> None:
    with open("training_summary.json", "w") as fh:
        json.dump(payload, fh, indent=2)


def main() -> int:
    ap = argparse.ArgumentParser(description="REINVENT4 fine-tuning + RL on Batch")
    ap.add_argument("--stage", choices=["transfer", "rl", "both"], default="both")
    ap.add_argument(
        "--train-smiles",
        help="partner/in-house SMILES file (one per line); "
        "required for --stage transfer|both",
    )
    ap.add_argument("--output-prefix", default="reinvent4")
    ap.add_argument("--epochs", type=int, default=10)
    ap.add_argument("--tl-batch-size", type=int, default=128)
    ap.add_argument("--tl-learning-rate", type=float, default=1e-4)
    ap.add_argument(
        "--reward",
        default="default",
        help="comma list kind[:weight] or 'default' "
        "(affinity-proxy x SA x safety x QED)",
    )
    ap.add_argument("--rl-steps", type=int, default=300)
    ap.add_argument("--rl-batch-size", type=int, default=128)
    ap.add_argument("--sigma", type=float, default=128.0)
    ap.add_argument("--rl-learning-rate", type=float, default=1e-4)
    ap.add_argument(
        "--no-diversity-filter",
        action="store_true",
        help="disable the scaffold diversity filter (NOT recommended; "
        "the filter is the reward-hacking suppression)",
    )
    ap.add_argument(
        "--prior-path",
        default=None,
        help="explicit base prior checkpoint "
        "(default: $REINVENT4_PRIORS/reinvent.prior)",
    )
    args = ap.parse_args()

    provenance = {"stage": args.stage, "steps": {}}
    tl_checkpoint = None

    prior_path = _ensure_prior(args.prior_path)
    if prior_path is None:
        _write_summary(
            {
                **provenance,
                "status": "error",
                "reason": "prior_checkpoint_missing: staged dirs + Zenodo fetch failed",
            }
        )
        sys.stderr.write(
            "ERROR: REINVENT4 prior missing (checked staged dirs + Zenodo fetch)\n"
        )
        return 6
    args.prior_path = prior_path
    provenance["prior_path"] = prior_path

    if args.stage in ("transfer", "both"):
        if not args.train_smiles:
            _write_summary(
                {
                    **provenance,
                    "status": "error",
                    "reason": "train_smiles required for transfer stage",
                }
            )
            sys.stderr.write("ERROR: --train-smiles required for transfer stage\n")
            return 3
        tl = Reinvent4TransferLearner(prior_path=args.prior_path)
        tl_out = f"{args.output_prefix}_finetuned.model"
        res = tl.train(
            train_smiles_file=args.train_smiles,
            output_model=tl_out,
            epochs=args.epochs,
            batch_size=args.tl_batch_size,
            learning_rate=args.tl_learning_rate,
        )
        provenance["steps"]["transfer"] = res.to_dict()
        if not res.ok:
            _write_summary(
                {
                    **provenance,
                    "status": "error",
                    "reason": f"transfer_learning: {res.reason}",
                }
            )
            sys.stderr.write(
                f"ERROR: transfer_learning failed: {res.reason}\n{res.stderr_tail}\n"
            )
            return 4
        tl_checkpoint = res.checkpoint

    if args.stage in ("rl", "both"):
        reward = _parse_reward(args.reward)
        sl = Reinvent4StagedLearner(prior_path=args.prior_path)
        rl_out = f"{args.output_prefix}_rl.model"
        res = sl.train(
            output_model=rl_out,
            reward=reward,
            n_steps=args.rl_steps,
            batch_size=args.rl_batch_size,
            sigma=args.sigma,
            learning_rate=args.rl_learning_rate,
            diversity_filter=not args.no_diversity_filter,
            agent_file=tl_checkpoint,
        )
        provenance["steps"]["rl"] = res.to_dict()
        if not res.ok:
            _write_summary(
                {
                    **provenance,
                    "status": "error",
                    "reason": f"staged_learning: {res.reason}",
                }
            )
            sys.stderr.write(
                f"ERROR: staged_learning failed: {res.reason}\n{res.stderr_tail}\n"
            )
            return 5

    provenance["status"] = "ok"
    final = (provenance["steps"].get("rl") or {}).get("checkpoint") or (
        provenance["steps"].get("transfer") or {}
    ).get("checkpoint")
    provenance["final_checkpoint"] = final
    _write_summary(provenance)
    print(json.dumps(provenance, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
