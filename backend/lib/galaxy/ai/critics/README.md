# Critic layer — generic, scalable self-correction

A decoupled **post-run judgment layer**. It replaces per-workflow, hand-coded `.nf`
statistics (Stream 3 Cox PH/confounder R, Stream 6 diffab LRT, …) with small,
independently unit-tested, evidence-grounded plugins (*critics*) that run on one
standard hook — on the **AWS Batch/cloud completion path**, not just local runs.

Full design: `../../../../../../Desktop/business/biomate_critic_framework_design.md`
(a.k.a. `business/biomate_critic_framework_design.md`).

## Interface

```python
class Critic(ABC):
    domain: str; critic_id: str; required_artifacts: list
    def applies_to(self, ctx: RunContext) -> bool    # cheap pre-check (default provided)
    def detect(self, ctx: RunContext) -> list[Issue]           # "is anything wrong?"
    def remediate(self, issue, ctx) -> Remediation             # "what's correct, and why?"
```

A critic reads **only** the run contract via `RunContext` (`design.json` +
`results_manifest.json` + lazily-loaded output artifacts) — never a workflow's `.nf`.

## Files

| File | Role |
|---|---|
| `base.py` | `Critic` ABC + `Issue` / `Remediation` / `Evidence` / `Severity` / `RemediationKind` |
| `run_context.py` | `RunContext` built from the contract; lazy S3/inline artifact loader (the local-vs-Batch seam) |
| `registry.py` | domain → critics; `get_registry()` (default, lazy-populated) |
| `hook.py` | the post-run hook; **guardrails**: cite-or-silent, advisory-by-default, audited auto-apply; publishes via existing transport |
| `evidence.py` | seed design-rule evidence (DOI + GOLD/SILVER/BRONZE); migrates into `config/qc_evidence.yaml` |
| `critics/survival.py` | **Stream 3**: `SurvivalConfoundingCritic` + `SurvivalPHCritic` |
| `critics/r_refit.py` + `r/survival_refit.R` | reusable Cox re-fit stats, decoupled from `cox.nf` |

## Wiring (not yet committed — see design §5)

```python
from galaxy.ai.critics import run_critics_from_run_meta
report = run_critics_from_run_meta(run_meta, artifact_loader=..., emit=..., store_suggestions=...)
run_meta["critic_report"] = report.to_dict()
```
Attaches in `nextflow_executor.py` right after `run_meta` carries `results_manifest` +
`design` (~L4592). Fail-open, lock-free, runs for all domains (empty report when none apply).

## Tests

```bash
cd backend && PYTHONPATH=lib python3.9 -m pytest tests/test_critics_framework.py tests/test_survival_critic.py -q
# 21 passed
```
