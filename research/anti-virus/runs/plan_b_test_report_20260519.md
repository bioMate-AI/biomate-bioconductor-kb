# Plan B (mRNA-LNP) — BioMate test report

**Date:** 2026-05-19  
**Scope:** Codon optimization (10813) routing + execute smoke; full Plan B UI E2E not yet implemented.

---

## Summary

| Area | Result |
|------|--------|
| Docs + smoke script | **Pass** — `run_plan_b_codon_lnp_smoke.sh` prints five workflow examples; does not execute |
| Backend `127.0.0.1:8081` | **Up** — gunicorn; OpenAPI lists `/api/nextflow/*`, `/api/ai_assistant/generate_workflow` |
| Frontend `127.0.0.1:5000` | **Up** |
| Workflow `main.nf` on disk (10813, 10721, 12819, 12869, 12867) | **Pass** |
| `generate_workflow` + Plan B codon query (`request_text`) | **Pass** — routes to `optimize_codons_for_heterologous_expression` |
| `POST /api/nextflow/execute` (10813, local/docker) | **Partial** — accepts job; terminal COMPLETED not confirmed in session |
| Playwright Plan B E2E | **Added** — `frontend/e2e/plan-b-codon-stepwise.e2e.ts` (PB-1 … PB-5); run and refresh audit JSON |

---

## API notes

- `generate_workflow` body field must be **`request_text`**, not `query`.
- Registry id **10813** may not appear in JSON; verify via `nextflow_path` / workflow name.
- For production Batch tests use `profile: docker` + `executor: awsbatch` and S3 `outdir` (see Plan A lessons in `docs/ANDV_CAMPAIGN_LESSONS_LEARNED.md`).

---

## Recommended next steps

1. Add `frontend/e2e/plan-b-codon-stepwise.e2e.ts` (PB-1 … PB-5) reusing `andv-stepwise-shared.ts`.
2. Optional `run_plan_b_codon_batch.py` for CLI parity with Plan A epitope script.
3. Chain test (10813 → 10721 → 12819 → 12869 → 12867) after single-step UI is green.
4. Keep Phase 1 epitope on Plan A checklist (**12700**); do not duplicate in Plan B smoke.

---

## Related

- UI scenario: `research/anti-virus/docs/BIOMATE_UI_SCENARIO_PLAN_B_mRNA_LNP.md`
- Implementation: `research/anti-virus/ANDV_VACCINE_PLAN_B_mRNA_LNP_IMPLEMENTATION.md`
- Smoke output archive: `research/anti-virus/runs/plan_b_smoke_20260519T154106Z.txt` (if present)
