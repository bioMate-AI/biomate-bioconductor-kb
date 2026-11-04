# BioMate platform generality audit — which "general" features are actually case-specific (2026-11-04)

Follows the deck-scenario audit (`20261104_DECK_SCENARIO_CAPABILITY_AUDIT_AND_FIXES.md`).
Four parallel code audits judged shipped code only. The worry — "good features that
are case-specific, not general" — is confirmed, and resolves into **four distinct
patterns**, each with a different fix.

## The four patterns
- **A — general core, single consumer.** The design is domain-neutral; it has only ever
  been wired to ONE case. Fix = add a second real consumer.
- **B — hardcoded per domain, no general mechanism.** Hand-written branches for a handful
  of domains; a new domain gets nothing. Fix = build the missing general mechanism.
- **C — general substrate, non-uniform quality.** The base (retrieval/LLM/schema) is general,
  but all the quality-boosting logic is hand-tuned for a few domains. Fix = fold special-cases
  into the general layer / data-drive them.
- **D — general engine BUILT but dormant behind a default-off flag.** Fix = activate + validate
  (the cheapest, highest-leverage wins).

## Consolidated map

| Subsystem | Verdict | Real coverage vs ~34–40 catalog domains | Pattern |
|---|---|---|---|
| Execution engine (Nextflow/Batch), literature search, methods-text | **GENERAL** | all | — |
| Accession resolve | general but **seq-only** (GEO/SRA/ENA; no PDB/ChEMBL/PRIDE) | — | C |
| **Model training** | **GENERALIZED this session** (generic tabular + k-fold CV + routing) | was 0 non-molecule; now general | D→fixed (activate `ML_TRAINING_ROUTING`) |
| **Multi-omics integration** | **general engine (arbitrary N layers, 7 methods, data-shape selection, generic normalizer) — but DORMANT** behind `MULTIOMICS_ROUTING`=off; default face is a hardcoded MOFA2 rna+protein workflow | engine: any; default-reachable: 1 | **D (quick win)** |
| Multi-channel **arbiter** | general fusion math; target-ID-named types/weights; **0 consumers outside `target_id/`** | 1 | A |
| **Grounded** evidence engine | pluggable tier model; assembly logic + both corpora regulatory-threshold-specific | 2 (both CMC/GMP) | A/B |
| **Reward / rule-gate** vocabulary | genuinely general declarative vocab (no domain terms); **only `ml_training` GRPO uses it** | 1 | A |
| **QC-evidence gates** | **CASE-SPECIFIC** — ~45 bespoke parsers + ~37 process-name threshold branches; config tunes *values* not *gate definitions*; new domain → "not_evaluated". BUT a general self-describing path exists (`qc_records.assess_qc_document` reads a workflow-emitted `_all_metrics`/`qc_metrics.json`) and a `BIOC_` catch-all | ~10 blocking (+ self-describe path under-used) | B (general path exists, not the default) |
| Auto-loop **parameter remediation** | **CASE-SPECIFIC** — 5 hardcoded pharma domains (ADMET/docking/CYP-DDI/NCA-PK/PBPK), per-gate `if gate=="herg_ic50"`. (The general `autofix/` LLM layer only fixes execution CRASHES, never gate/param breaches.) | 5 | B |
| **Routing rules** | **CASE-SPECIFIC** — hand-written blocks for 7 domains (drug_discovery = 26 of ~50 bullets), even a per-accession S3 hardcode; no-rule domains get an irrelevant full-dump + generic search | 7 | B/C |
| **Param-prefill** | general schema+description LLM base, overlaid with RNA-seq-contrast / genome / SMILES special-cases + 18 drug-workflow alias tables | base: all; boosted: ~RNA-seq + drug cluster | C |
| **Findings / results** | general grounded-LLM fallback for TEXT outputs; ~8–9 workflow families have bespoke rich parsers; data-driven descriptor system exists (5 rows); proactive next-step = **1 hardcoded demo storyline** (complement→Iptacopan); binary outputs degrade | ~8–9 rich; rest = LLM best-effort | C |

**The through-line:** BioMate's *substrate* is general (execution, retrieval, LLM bases, and
several genuinely general *cores*), but nearly every *intelligence layer that makes it good*
— routing, param boosts, QC gates, remediation, findings parsers — is hand-written for **~5–6
sequencing domains + a hand-tuned drug-discovery cluster**. The code's own
`pattern_router.py` self-rating agrees: transcriptomics/genomics/variant/epigenomics/single-cell
0.72–0.80; everything else < 0.75. Breadth is real in the *catalog*; the *smarts* are concentrated.

## Prioritized generalization plan (impact × tractability)

**Tier 1 — activate what's already general (days, low risk).**
1. **Model training** — DONE (code): generic tabular + k-fold CV + routing. Activate by setting
   `ML_TRAINING_ROUTING=1` on dev + a CPU Batch smoke.
2. **Multi-omics** — the general engine is already built and tested-looking; set `MULTIOMICS_ROUTING=1`,
   validate the planner on a 2–3 layer example, and replace the hardcoded MOFA2-rna+protein
   default face with the planner. Highest leverage per hour.

**Tier 2 — one general mechanism replaces many hardcodes (the synergy).**
3. **Make the declarative rule-gate engine the GENERAL QC-gate mechanism.** The reward/rule-gate
   interpreter (Pattern A, general vocab, already shipped) + the self-describing `qc_records`
   path are the same idea as the ~45 hardcoded QC branches. Have workflows *declare* their gates
   as data (they already can via `qc_metrics.json`), route them through the general interpreter,
   and the per-process if/elif chains stop being the only path. One engine covers training gates,
   QC gates, and inference guardrails → removes Pattern B for QC.
4. **Generalize the arbiter** — rename public types `TargetScore`→generic `EntityScore`, move the
   target-ID channel priors into config, and wire a second consumer (e.g. the multi-omics or
   literature evidence-fusion). Turns Pattern A into exercised generality.

**Tier 3 — fold case-specifics into the general layer (larger).**
5. **Routing** — convert the 7 hardcoded rule blocks into per-domain rule *data* (one schema any
   domain fills), so coverage scales without code; keep the retrieval substrate.
6. **Param-prefill** — move the RNA-seq-contrast / genome / SMILES special-cases behind the
   schema+description general extractor so any workflow's params benefit.
7. **Findings** — lean on the data-driven descriptor system + the grounded-LLM fallback; retire the
   single hardcoded "complement→Iptacopan" proactive storyline.

## This is a program, not a one-session fix
Generalizing 8 subsystems across ~30 under-served domains is multi-week. The right first moves
are Tier 1 (activate the two dormant general engines — model-training is done, multi-omics is a
flag + a day) and Tier 2 item 3 (one general gate engine). Which domains to generalize *first*
should follow the business (the ~5 sequencing domains + whatever clinical/immuno/oncology areas
matter most), not catalog breadth.
