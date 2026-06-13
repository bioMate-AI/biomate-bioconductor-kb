"""
Lane B3 — minimum-viable retrain worker.

Picks up `queued` jobs and transitions them through running → succeeded
(or failed). The stub here marks running, sleeps SIMULATED_TRAIN_SECONDS,
then marks succeeded with the adapter_path the resolver in
ind_assembly._resolve_adapter_path would look for. Real training (the
actual SFT loop) belongs in a separate GPU-bearing worker; this module
exercises the contract end-to-end.
"""
from __future__ import annotations
import logging, os, time
from pathlib import Path
from typing import Optional

from galaxy.ai.drug_discovery import regulatory_training_jobs as rj

log = logging.getLogger(__name__)

SIMULATED_TRAIN_SECONDS = float(os.environ.get("REG_TRAIN_SIMULATED_SECONDS", "1.0"))
POLL_SECONDS = float(os.environ.get("REG_TRAIN_POLL_SECONDS", "5.0"))

REPO = Path(__file__).resolve().parents[5]
MODELS_ROOT = REPO / "models"


def _adapter_path_for(org_id: str, version: str = "v7") -> str:
    """Match _resolve_adapter_path in ind_assembly so a succeeded job
    creates a record the live serving path will find next time."""
    return str(MODELS_ROOT / f"regulatory_llm_{version}_{org_id}" / "lora_adapter")


def _process_one(job: rj.TrainingJob) -> rj.TrainingJob:
    rj.mark_status(job.job_id, "running", message="stub worker started")
    time.sleep(SIMULATED_TRAIN_SECONDS)
    if job.edit_pair_count == 0:
        return rj.mark_status(
            job.job_id,
            "failed",
            message="no_edit_pairs_available — collect customer DPO pairs first",
        )
    adapter = _adapter_path_for(job.org_id)
    return rj.mark_status(
        job.job_id,
        "succeeded",
        message=f"stub_completed in {SIMULATED_TRAIN_SECONDS}s on {job.edit_pair_count} pairs",
        adapter_path=adapter,
    )


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
