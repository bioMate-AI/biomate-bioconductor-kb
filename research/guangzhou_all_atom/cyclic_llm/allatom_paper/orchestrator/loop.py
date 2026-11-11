"""Round-loop orchestrator for the all-atom hybrid-LLM paper (workstream I-A).

One round = sample from the generator (hard rules applied by the Constraint) -> verify the samples with the BUDGETED train
oracle -> form preference pairs through the PreferenceUpdater -> update the generator's LoRA delta -> add the newly scored
molecules to the Retriever -> let the StopMonitor look at train vs STOP verifier scores of the current top-k.
Design points (docs/20261031_ALLATOM_IMPLEMENTATION_PLAN.md section 2):
  * the oracle is pmo_harness.BudgetedOracle (budget, duplicates/invalid/constraint failures free, proposal cap);
  * the stop verifier is never an oracle and held-out verifiers never appear here;
  * everything is resumable: a JSON checkpoint (oracle log + monitor state + round index) and the LoRA delta bytes are written
    atomically after every round; per-round sampling seeds depend only on (seed, round), so a resumed run reproduces the
    uninterrupted one exactly for deterministic components;
  * JSONL logs (OracleCallRow / RoundRow of contracts.py) are appended locally and uploaded by an injectable uploader.
No heavy imports. Run on EC2 / Spark, never on the owner's laptop."""
from __future__ import annotations

import hashlib
import json
import os
import sys
import threading
import time
from dataclasses import dataclass, field
from typing import Any, Callable, Dict, List, Optional, Sequence

_HERE = os.path.dirname(os.path.abspath(__file__))
_PARENT = os.path.dirname(_HERE)
if _PARENT not in sys.path:
    sys.path.insert(0, _PARENT)

import numpy as np  # noqa: E402

from contracts import OracleCallRow, PromptContext, RoundRow, row_to_dict  # noqa: E402
from pmo_harness import BudgetExhausted, BudgetedOracle, Verifier, auc_topk, default_canon  # noqa: E402


# ------------------------------------------------------------------------------------------------ config
@dataclass
class LoopConfig:
    run_id: str
    method: str = "hybrid"
    objective: str = "F1"
    seed: int = 0
    budget: int = 1000            # train-verifier oracle calls (the PMO budget)
    n_per_round: int = 100        # samples drawn per feedback round
    rounds_max: int = 1000
    temperature: float = 1.0
    topk: int = 10
    margin: float = 0.0           # preference-pair margin
    lr: float = 0.5
    beta: float = 1.0
    retrieve_k: int = 5
    max_proposals_factor: int = 20
    max_seconds: Optional[float] = None  # safety cap, not optimization budget


# ------------------------------------------------------------------------------------------------ logging
class JsonlLogger:
    """Append-only JSONL log with optional background upload (default every 60 s; `uploader(local_path)` is injectable)."""

    def __init__(self, path: str, uploader: Optional[Callable[[str], Any]] = None, upload_every_s: float = 60.0):
        self.path, self.uploader, self.every = path, uploader, float(upload_every_s)
        self._lock = threading.Lock()
        self._stop = threading.Event()
        self._thread: Optional[threading.Thread] = None
        self.n_uploads = 0
        self.n_rows = 0
        os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)

    def log(self, row) -> None:
        d = row if isinstance(row, dict) else row_to_dict(row)
        line = json.dumps(d, sort_keys=True, default=float)
        with self._lock:
            with open(self.path, "a") as f:
                f.write(line + "\n")
            self.n_rows += 1

    def upload(self) -> None:
        if self.uploader is not None:
            self.uploader(self.path)
            self.n_uploads += 1

    def start(self) -> "JsonlLogger":
        if self._thread is None and self.uploader is not None:
            def run():
                while not self._stop.wait(self.every):
                    try:
                        self.upload()
                    except Exception:  # an upload failure must never kill the run
                        pass
            self._thread = threading.Thread(target=run, daemon=True)
            self._thread.start()
        return self

    def close(self) -> None:
        self._stop.set()
        if self._thread is not None:
            self._thread.join(timeout=5)
        try:
            self.upload()
        except Exception:
            pass


def s3_uploader(prefix: str) -> Callable[[str], Any]:
    """Uploader that copies a local file to <prefix>/<basename> with the aws CLI (EC2 only)."""
    import subprocess

    def up(path: str):
        return subprocess.run(["aws", "s3", "cp", path, prefix.rstrip("/") + "/" + os.path.basename(path), "--only-show-errors"], check=False)
    return up


# ------------------------------------------------------------------------------------------------ checkpoint / resume
def oracle_state(o: BudgetedOracle) -> Dict[str, Any]:
    return {"calls": o.calls, "log": [[int(i), c, float(s)] for i, c, s in o.log], "n_proposals": o.n_proposals,
            "n_invalid": o.n_invalid, "n_dup": o.n_dup, "n_constraint_fail": o.n_constraint_fail}


def restore_oracle(o: BudgetedOracle, st: Dict[str, Any]) -> None:
    o.log = [(int(i), c, float(s)) for i, c, s in st["log"]]
    o.cache = {c: s for _, c, s in o.log}
    o.calls = int(st["calls"])
    o.n_proposals, o.n_invalid, o.n_dup, o.n_constraint_fail = (int(st[k]) for k in ("n_proposals", "n_invalid", "n_dup", "n_constraint_fail"))


def _atomic_write(path: str, data: bytes) -> None:
    tmp = path + ".tmp"
    with open(tmp, "wb") as f:
        f.write(data)
    os.replace(tmp, path)


def save_checkpoint(ckpt_dir: str, next_round: int, oracle: BudgetedOracle, monitor, generator, extra: Optional[dict] = None) -> None:
    os.makedirs(ckpt_dir, exist_ok=True)
    lora = generator.lora_state()
    lora_name = f"lora_r{next_round:05d}.bin"
    _atomic_write(os.path.join(ckpt_dir, lora_name), lora)
    st = {"next_round": next_round, "oracle": oracle_state(oracle), "lora": lora_name,
          "monitor": monitor.state_dict() if monitor is not None and hasattr(monitor, "state_dict") else None, "extra": extra or {}}
    _atomic_write(os.path.join(ckpt_dir, "ckpt.json"), json.dumps(st).encode())


def load_checkpoint(ckpt_dir: str) -> Optional[Dict[str, Any]]:
    p = os.path.join(ckpt_dir, "ckpt.json")
    if not os.path.exists(p):
        return None
    return json.load(open(p))


# ------------------------------------------------------------------------------------------------ monitor adapter
class HarnessMonitorAdapter:
    """Adapts pmo_harness.StopMonitor (update(train_scores, stop_scores) -> bool) to contracts.StopMonitorLike
    (update(round_idx, train_scores, stop_scores) -> dict) and makes it checkpointable."""

    def __init__(self, patience: int = 2, min_gain: float = 0.005):
        from pmo_harness import StopMonitor  # present once the E fork's edits are committed
        self.m = StopMonitor(patience=patience, min_gain=min_gain)

    def update(self, round_idx: int, train_scores: Sequence[float], stop_scores: Sequence[float]) -> Dict[str, Any]:
        stop = self.m.update(train_scores, stop_scores)
        gap = self.m.hist[-1][2] if self.m.hist else float("nan")
        return {"gap": float(gap), "trend": int(self.m.stale), "should_stop": bool(stop)}

    def state_dict(self) -> Dict[str, Any]:
        m = self.m
        return {"hist": [list(map(float, h)) for h in m.hist], "best_stop": m.best_stop, "stale": m.stale, "stopped_at": m.stopped_at}

    def load_state_dict(self, st: Dict[str, Any]) -> None:
        m = self.m
        m.hist = [tuple(h) for h in st["hist"]]
        m.best_stop, m.stale, m.stopped_at = st["best_stop"], st["stale"], st["stopped_at"]


# ------------------------------------------------------------------------------------------------ prompt context
def default_ctx_builder(cfg: LoopConfig) -> Callable:
    def build(round_idx: int, oracle: BudgetedOracle, retriever) -> PromptContext:
        top = oracle.top_smiles(max(1, cfg.retrieve_k))
        retrieved = []
        if retriever is not None and top:
            retrieved = retriever.query(top[0], cfg.retrieve_k)
        return PromptContext(objective=cfg.objective, seed_smiles=tuple(top[:1]), retrieved=tuple(retrieved))
    return build


def _h(s: str) -> str:
    return hashlib.sha256(s.encode()).hexdigest()[:16]


# ------------------------------------------------------------------------------------------------ the loop
def run_loop(cfg: LoopConfig, generator, train_verifier: Verifier, constraint=None, stop_verifier: Optional[Verifier] = None,
             retriever=None, updater=None, monitor=None, ctx_builder: Optional[Callable] = None,
             logger: Optional[JsonlLogger] = None, canon: Callable = default_canon, ckpt_dir: Optional[str] = None,
             stop_after_rounds: Optional[int] = None) -> Dict[str, Any]:
    """Returns {run_id, calls, auc_topk, final_topk, curve, top_smiles, rounds, stopped_at, interrupted, n_stop_calls}.
    `stop_after_rounds` (tests) returns early after that many rounds (simulating an interruption) with the checkpoint written."""
    if stop_verifier is not None and stop_verifier.role != "stop":
        raise ValueError(f"stop verifier {stop_verifier.name!r} has role {stop_verifier.role!r}, expected 'stop'")
    oracle = BudgetedOracle(train_verifier, cfg.budget, canon, (constraint.check if constraint is not None else None),
                            max_proposals=cfg.max_proposals_factor * cfg.budget)
    ctx_builder = ctx_builder or default_ctx_builder(cfg)
    start_round, stopped_at, rounds_done = 0, None, 0
    stop_cache: Dict[str, float] = {}

    ck = load_checkpoint(ckpt_dir) if ckpt_dir else None
    if ck is not None:
        restore_oracle(oracle, ck["oracle"])
        if monitor is not None and ck.get("monitor") is not None and hasattr(monitor, "load_state_dict"):
            monitor.load_state_dict(ck["monitor"])
        lora_path = os.path.join(ckpt_dir, ck["lora"])
        generator.load_lora(lora_path)
        extra=ck.get("extra",{})
        stop_cache={c:float(v) for c,v in extra.get("stop_cache",{}).items()}
        if retriever is not None:
            if extra.get("retriever") is not None:
                if not hasattr(retriever,"load_state_dict"):
                    raise ValueError("retriever cannot restore provenance checkpoint")
                retriever.load_state_dict(extra["retriever"])
            else:
                for _, c, s in oracle.log:
                    retriever.add(c, {train_verifier.name: s})
        start_round = int(ck["next_round"])
        rounds_done = start_round

    interrupted = False
    started = time.monotonic()
    stop_reason = "round_limit"
    for r in range(start_round, cfg.rounds_max):
        if cfg.max_seconds is not None and time.monotonic() - started >= cfg.max_seconds:
            stop_reason = "wallclock"
            break
        if oracle.exhausted:
            stop_reason = "budget_or_proposal_cap"
            break
        ctx = ctx_builder(r, oracle, retriever)
        samples = generator.sample(cfg.n_per_round, ctx, cfg.temperature, cfg.seed * 100003 + r, constraint)
        n_inv0, n_dup0, n_cf0, calls0 = oracle.n_invalid, oracle.n_dup, oracle.n_constraint_fail, oracle.calls
        scored_raw, scored_val, budget_done = [], [], False
        seen_raw = set()
        try:
            for s in samples:
                before = oracle.calls
                sc = oracle(s)
                if sc is None:
                    continue
                if s in seen_raw:
                    continue
                seen_raw.add(s)
                scored_raw.append(s)
                scored_val.append(sc)
                if oracle.calls > before and logger is not None:
                    c, v = oracle.log[-1][1], oracle.log[-1][2]
                    logger.log(OracleCallRow(run_id=cfg.run_id, method=cfg.method, objective=cfg.objective, seed=cfg.seed, round=r,
                                             call_index=oracle.calls, verifier=train_verifier.name, smiles_hash=_h(c), score=float(v),
                                             calls_used=oracle.calls, t_unix=time.time()))
        except BudgetExhausted:
            budget_done = True

        pair_diag: Dict[str, Any] = {}
        step_metrics: Dict[str, Any] = {}
        if updater is not None:
            # Empty and small rounds must still be counted in pair diagnostics
            # and in a real updater's search-round learning-stall gate.
            pairs, pair_diag = updater.make_pairs(scored_raw, scored_val, cfg.margin)
            if pairs:
                step_metrics = updater.step(pairs, cfg.lr, cfg.beta)
            if hasattr(updater,"observe_round"):
                step_metrics = updater.observe_round(r,step_metrics or None,pair_diag)
        if retriever is not None:
            for _, c, s in oracle.log[calls0:]:
                retriever.add(c, {train_verifier.name: s})

        top = oracle.top_smiles(cfg.topk)
        train_top = [oracle.cache[c] for c in top]
        stop_mean, gap = None, None
        learning_stopped=step_metrics.get("update_gate")=="stop"
        should_stop=learning_stopped
        if stop_verifier is not None and monitor is not None and top:
            stop_vals = []
            for c in top:
                if c not in stop_cache:
                    stop_cache[c] = float(stop_verifier.fn(c))
                stop_vals.append(stop_cache[c])
            res = monitor.update(r, train_top, stop_vals)
            stop_mean, gap = float(np.mean(stop_vals)), res.get("gap")
            should_stop=should_stop or bool(res.get("should_stop"))
        if logger is not None:
            logger.log(RoundRow(run_id=cfg.run_id, method=cfg.method, objective=cfg.objective, seed=cfg.seed, round=r,
                                n_sampled=len(samples), n_invalid=oracle.n_invalid - n_inv0, n_dup=oracle.n_dup - n_dup0,
                                n_constraint_fail=oracle.n_constraint_fail - n_cf0, calls_used=oracle.calls,
                                train_topk_mean=float(np.mean(train_top)) if train_top else float("nan"),
                                stop_topk_mean=stop_mean, gap=gap, should_stop=should_stop,
                                kl=step_metrics.get("kl"), weight_delta_rel=step_metrics.get("weight_delta_rel"),
                                frac_zero_variance_groups=pair_diag.get("frac_zero_variance_groups"),
                                frac_small_groups_dropped=pair_diag.get("frac_small_groups_dropped"),
                                frac_groups_retained=pair_diag.get("frac_groups_retained"),
                                n_groups=pair_diag.get("n_groups"),n_groups_kept=pair_diag.get("n_groups_kept"),
                                preference_mean_margin=pair_diag.get("mean_margin"),
                                loss=step_metrics.get("loss"),update_gate=step_metrics.get("update_gate"),
                                update_gate_reason=step_metrics.get("update_gate_reason"),
                                learning_gate_round=step_metrics.get("learning_gate_round"),
                                optimizer_updated=step_metrics.get("optimizer_updated"),
                                n_pairs=int(pair_diag["n_pairs"]) if "n_pairs" in pair_diag else None, t_unix=time.time()))
        rounds_done = r + 1
        if ckpt_dir:
            save_checkpoint(ckpt_dir, r + 1, oracle, monitor, generator,
                            extra={"stop_cache":stop_cache,
                                   "retriever":retriever.state_dict() if retriever is not None and hasattr(retriever,"state_dict") else None})
        if should_stop:
            stopped_at = r
            stop_reason = "learning_gate" if learning_stopped else "monitor"
            break
        if budget_done or oracle.exhausted:
            stop_reason = "budget_or_proposal_cap"
            break
        if stop_after_rounds is not None and (r + 1) >= stop_after_rounds:
            interrupted = True
            stop_reason = "interrupted"
            break

    curve = oracle.topk_curve(cfg.topk)
    return {"run_id": cfg.run_id, "method": cfg.method, "objective": cfg.objective, "seed": cfg.seed, "calls": oracle.calls,
            "auc_topk": auc_topk(curve), "final_topk": float(curve[-1]), "curve": curve, "top_smiles": oracle.top_smiles(cfg.topk),
            "rounds": rounds_done, "stop_reason": stop_reason, "wall_s": time.monotonic() - started, "stopped_at": stopped_at, "interrupted": interrupted, "n_stop_calls": len(stop_cache),
            "n_proposals": oracle.n_proposals, "n_invalid": oracle.n_invalid, "n_dup": oracle.n_dup,
            "n_constraint_fail": oracle.n_constraint_fail, "oracle_log": list(oracle.log)}
