# Capability Gaps — MCP Multi-Workflow Param Prefill & ADMET Endpoint Coverage (2026-10-19)

Surfaced while testing the QC after-run document (see
`20261019_QC_PERSISTENCE_ROOTCAUSE_AND_FIX.md`). A BioMate MCP `biomate_session`
ADMET run launched two workflows in parallel; the hERG QSAR run failed with empty
params, and the ADMET-AI run emitted only AMES despite a request for hERG/CYP3A4/
oral bioavailability.

---

## Gap 1 — MCP multi-workflow param prefill (FIXED + shipping)

**Root cause (NOT in the connector).** The connector's `biomate_session`
(`/Users/kky/biomate-connector/mcp/biomate_mcp_server.py`, `open_claw_stream`
L626-665, `SessionRunner` L1012-1067) is a pure SSE pass-through — it does no
workflow selection or param extraction. All of that happens in the backend
open-claw agentic loop at `frontend/server/routes.ts:16179-16300`. The inner
Claude emits one `run_workflow` tool_use per workflow; it fills `params` (SMILES)
on the first and **omits them on the 2nd+ parallel call**. `executeOpenClaudeTool`
(`:792`) resolved each workflow with `defer_param_prefill: true` (`:841`) and
filled params **only** from `input.params` — with no goal context and no
deterministic backstop — so workflow #2 reached `/api/workflows/execute` with
empty `required_params[].value` → `missing_required_params`.

**Fix (applied, `routes.ts`).**
1. Derive the goal text (first user message) in the open-claw loop and pass it to
   `executeOpenClaudeTool(..., goalText)`.
2. In the `run_workflow` case, after applying the model's `input.params`, if any
   REQUIRED param is still unfilled, re-prefill from the goal via
   `/api/workflows/search` with `defer_param_prefill: false` (query = workflow_id
   + goal), resolved against THAT workflow's own schema, and merge (model params
   win on conflict).

This matches CLAUDE.md's "rule-first + LLM prefill + schema guardrail" principle:
every workflow a session launches now gets its params prefilled from the goal,
not just the first. Verifiable via a parallel-workflow `biomate_session` run.

---

## Gap 2 — ADMET-AI endpoint coverage (DIAGNOSED; fix documented, NOT shipped)

**The workflow supports hERG/CYP/bioavailability** (Phase 2 ADMET-AI/Chemprop in
`backend/biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/predict_admet_properties/main.nf`,
`_COL` map L369-389; container `backend/docker/biomni-admet/Dockerfile` installs
admet-ai 1.3.1 + chemprop). Three distinct issues:

- **Gap 2A — emission (code, provable).** CYP panel + oral bioavailability are
  written only to `tox_report["per_compound_admet_ai"]` (L488); never promoted to
  the `toxicity` block (L428-527 promote only hERG/ClinTox/DILI/PPBR) nor to
  `qc_metrics.json` (L779-818). Both QC parsers read only `toxicity.*`, so those
  endpoints are invisible to QC and the summary even on a successful run.
- **Gap 2B — hERG key mismatch (code, provable).** Phase 2 writes
  `toxicity["hERG_probability"]` (L437) but every consumer reads
  `herg_inhibition_prob` (gate L5417; parsers L1964/L3726) — a dead key. (hERG is
  still gated via `herg_ic50_uM`, which Phase 2 does write at L470.)
- **Gap 2C — runtime/env (the actual cause of the observed only-AMES run).** The
  observed `toxicity_report.json` had `estimation_method:"rdkit_descriptors"` →
  Phase 2 produced ZERO rows (empty ADMET-AI shard output), and the Phase-1 RDKit
  hERG/DILI were also absent while AMES survived — consistent with either all
  SMILES failing `Chem.MolFromSmiles`, or `from rdkit.Chem import Descriptors`
  failing in the container while `from rdkit import Chem` succeeds. Needs a LIVE
  biomni-admet container check (shard stderr "ADMET-AI shard error:" at L80;
  `python3 -c "from rdkit.Chem import Descriptors; import admet_ai"`).

**Honest capability note.** ADMET-AI/TDC has **no CYP3A4 *inhibitor* endpoint** —
only CYP3A4 *substrate* (CarbonMangels) + inhibitor models for 2C9/2C19/2D6/1A2.
A "CYP3A4 inhibition" request must be answered with the substrate prob + the other
inhibitor panel, explicitly labelled — not a fabricated CYP3A4-inhibitor number.

**Correction to an earlier assumption.** The PREDICT_ADMET gate branch
(`qc_trace_monitor.py` L5375-5509) does NOT gate CYP or bioavailability — only
hERG (IC50 + prob), DILI, Ames, ClinTox. Surfacing CYP/bioavailability to QC
needs BOTH emission (2A) AND new gate branches.

**Why not shipped this session.** 2A/2B are provably-correct additive edits, but
(i) they won't manifest until 2C (Phase-2-empty) is fixed — so they can't be
E2E-verified now, and (ii) they edit executed Nextflow process code, where an
unverified embedded-Python error would regress ADMET for all users. Per CLAUDE.md
("document clearly and do nothing rather than ship an unverifiable change"), the
exact diffs are recorded for a focused cycle that also resolves 2C. Proposed
diffs: promote oral-bioavailability + CYP panel and `herg_inhibition_prob` into
`toxicity` + `qc_metrics.json`; add honest `admet_ai_status:"not_run"` markers
when Phase 2 is empty; add an advisory oral-bioavailability gate.

### Next steps (ordered)
1. Resolve 2C (live container: ADMET-AI shard + RDKit Descriptors import) — the
   blocker; without it hERG/CYP/bioavailability never appear.
2. Apply 2A/2B emission fixes + qc_metrics mirror; verify with one ADMET Batch run.
3. Add CYP-substrate + oral-bioavailability advisory gates (labelled honestly).
