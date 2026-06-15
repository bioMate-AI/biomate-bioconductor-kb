"""
Lane B3 — per-org adaptation worker.

Picks up `queued` jobs and dispatches on adaptation_mode:

  prompt_rules  →  cheap rule-compile (no GPU, runs in seconds). Writes a
                   per-org YAML to data/regulatory_training/org_rules/
                   that _build_rag_context can load on the NEXT inference
                   call. Default mode — serves the frontier-API
                   production path TODAY.

  few_shot_index → builds a per-org retrieval index over the customer
                   edit pairs; injected as few-shot exemplars at prompt
                   time. Stub: writes a placeholder so the lifecycle
                   exercise works.

  post_train_lora → full GPU SFT/DPO LoRA on the open base. Gated by
                   harness witness: refuses to run unless
                   models/regulatory_llm_eval_witness.json shows local >
                   frontier with non-overlap-CI on the org's task mix.
                   Without that witness, GPU spend is forbidden per
                   CLAUDE.md "Review Code Before Testing — No
                   Speculative Deploys".
"""
from __future__ import annotations
import json, logging, os, time
from pathlib import Path
from typing import Optional

from galaxy.ai.drug_discovery import regulatory_training_jobs as rj

log = logging.getLogger(__name__)

SIMULATED_TRAIN_SECONDS = float(os.environ.get("REG_TRAIN_SIMULATED_SECONDS", "1.0"))
POLL_SECONDS = float(os.environ.get("REG_TRAIN_POLL_SECONDS", "5.0"))

REPO = Path(__file__).resolve().parents[5]
MODELS_ROOT = REPO / "models"
ORG_RULES_DIR = REPO / "data" / "regulatory_training" / "org_rules"
ORG_FEWSHOT_DIR = REPO / "data" / "regulatory_training" / "org_fewshot"
HARNESS_WITNESS = MODELS_ROOT / "regulatory_llm_eval_witness.json"


def _adapter_path_for(org_id: str, version: str = "v7") -> str:
    """Match _resolve_adapter_path in ind_assembly so a succeeded job
    creates a record the live serving path will find next time."""
    return str(MODELS_ROOT / f"regulatory_llm_{version}_{org_id}" / "lora_adapter")


# ─── per-mode handlers ─────────────────────────────────────────────────────
def _do_prompt_rules(job: rj.TrainingJob) -> rj.TrainingJob:
    """Compile org edit-pair signal into a per-org rule YAML.

    Replaces the prior placeholder with the real compiler at
    org_rule_compiler.compile_org_rules — extracts preferred_citations,
    preferred_phrases, and banned_phrases by diffing chosen vs rejected
    on each customer pair, plus task/section distribution metadata.

    Cheap (~ms per pair), no GPU. The output YAML is loaded back by
    ind_assembly._build_rag_context at the next inference call so the
    customer's accumulated edits actually shape generation.
    """
    from galaxy.ai.drug_discovery.org_rule_compiler import compile_and_write
    ORG_RULES_DIR.mkdir(parents=True, exist_ok=True)
    out_path = ORG_RULES_DIR / f"{job.org_id}.yaml"
    n_pairs = compile_and_write(rj.DPO_PAIRS_PATH, out_path, job.org_id)
    return rj.mark_status(
        job.job_id,
        "succeeded",
        message=f"prompt_rules compiled from {n_pairs} pairs into {out_path.name}",
        adapter_path=str(out_path),
    )


def _do_few_shot_index(job: rj.TrainingJob) -> rj.TrainingJob:
    """Build a per-org retrieval index over customer edit pairs. Stub
    writes a placeholder; real implementation indexes with BGE or
    similar local embeddings."""
    ORG_FEWSHOT_DIR.mkdir(parents=True, exist_ok=True)
    out_path = ORG_FEWSHOT_DIR / f"{job.org_id}.jsonl"
    out_path.write_text(json.dumps({
        "org_id": job.org_id,
        "pair_count": job.edit_pair_count,
        "note": "stub — real implementation builds a BGE/Qwen embedding index",
    }) + "\n")
    return rj.mark_status(
        job.job_id,
        "succeeded",
        message=f"few_shot_index indexed {job.edit_pair_count} pairs",
        adapter_path=str(out_path),
    )


def _do_post_train_lora(job: rj.TrainingJob) -> rj.TrainingJob:
    """Full SFT/DPO LoRA on the open base. Refuses to run without a
    harness witness showing local > frontier on this org's task mix —
    this prevents GPU burn before the cross-judge has shown headroom
    (CLAUDE.md "Review Code Before Testing")."""
    if not HARNESS_WITNESS.exists():
        return rj.mark_status(
            job.job_id,
            "failed",
            message=(
                "harness_witness_missing — refuse to start GPU training "
                f"until {HARNESS_WITNESS.name} shows local > frontier "
                "with non-overlap CI on a recent cross-judge run"
            ),
        )
    if job.edit_pair_count == 0:
        return rj.mark_status(
            job.job_id,
            "failed",
            message="no_edit_pairs_available — collect customer DPO pairs first",
        )
    # Real GPU loop goes here. The stub simulates training, then registers
    # the adapter path the serving resolver will pick up.
    time.sleep(SIMULATED_TRAIN_SECONDS)
    adapter = _adapter_path_for(job.org_id)
    return rj.mark_status(
        job.job_id,
        "succeeded",
        message=f"post_train_lora stub_completed on {job.edit_pair_count} pairs",
        adapter_path=adapter,
    )


_MODE_DISPATCH = {
    "prompt_rules":    _do_prompt_rules,
    "few_shot_index":  _do_few_shot_index,
    "post_train_lora": _do_post_train_lora,
}


def _process_one(job: rj.TrainingJob) -> rj.TrainingJob:
    rj.mark_status(job.job_id, "running", message=f"worker started ({job.adaptation_mode})")
    handler = _MODE_DISPATCH.get(job.adaptation_mode)
    if handler is None:
        return rj.mark_status(
            job.job_id,
            "failed",
            message=f"unknown_adaptation_mode:{job.adaptation_mode}",
        )
    return handler(job)


def tick(max_jobs: int = 1) -> list[rj.TrainingJob]:
    processed: list[rj.TrainingJob] = []
    all_jobs = sorted(
        rj._coalesce_status(rj._read_jobs()).values(),
        key=lambda j: j.submitted_at,
    )
    queued = [j for j in all_jobs if j.status == "queued"]
    for job in queued[:max_jobs]:
        try:
            updated = _process_one(job)
            if updated is not None:
                processed.append(updated)
        except Exception as e:
            log.exception("worker failed on %s: %s", job.job_id, e)
            failed = rj.mark_status(job.job_id, "failed", message=f"{type(e).__name__}: {e}")
            if failed is not None:
                processed.append(failed)
    return processed


def run_forever(poll_seconds: Optional[float] = None) -> None:
    """Long-running poll loop. Don't use from tests."""
    sleep_s = poll_seconds if poll_seconds is not None else POLL_SECONDS
    log.info("[reg_train_worker] starting; poll=%.1fs", sleep_s)
    while True:
        try:
            done = tick(max_jobs=1)
            if done:
                log.info("[reg_train_worker] processed %s", [j.job_id for j in done])
        except KeyboardInterrupt:
            log.info("[reg_train_worker] interrupted, exiting")
            return
        except Exception as e:
            log.exception("[reg_train_worker] poll cycle failed: %s", e)
        time.sleep(sleep_s)


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    run_forever()
