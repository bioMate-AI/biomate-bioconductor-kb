# Cyclic-Peptide Innovation Program — Consolidated Status (our own LLM)

**Date:** 2026-10-06 · One-page status of the "our own model, inverted data dependency" program that
came out of the two deep critical surveys (`20261005_INNOVATION_THESIS_CYCLIC_LLM.md`). All results
below are **in-silico** unless stated; honest caveats included.

## Validated pillars (3) — all in-silico, trained on our GPU
| Pillar | What | Result | Caveat |
|---|---|---|---|
| **MVP cyclic LLM** (`cyclic_llm/train_cyclic_llm.py`) | 10.8M GPT over SMILES, joint **binding + permeability** conditioning, trained on 21,921 real cyclic peptides | macrocycle 0.98, novelty 0.90, **perm Δ+0.45, binding Δ+0.81**; validity 0.53 | validity modest (char-SMILES); conditioning scored by RF proxy, not wet-lab |
| **Display-NGS harvest** (`harvest_display_ngs_rapid.py`) | real enrichment-labeled cyclic display data (PADI4 RaPID, ncAA) | **370k peptides × 5 rounds** on S3; enrichment signal textbook-valid | ~10⁶–10⁷ free (prototype scale, not 10¹²); **zero public data on our targets** → proprietary campaign = moat |
| **v2 display-conditioned LLM** (`cyclic_llm/train_cyclic_llm_v2.py`) | enrichment-conditioned sequence LLM — can display be the PRIMARY binding signal? | **YES: Δ+0.317** (binder-threshold), validity 0.988, novelty 0.995, 0 top-binder copies | in-silico (RF proxy); **single target (PADI4)**; learns "enriched-like," not identity |

**Net:** our own small LLM does two things the SOTA tools (per both surveys) defer — **joint
multi-objective conditional cyclic generation on real data**, and **learning binding from abundant
display data** instead of scarce co-structures + a circular oracle. The inverted-data-dependency thesis
has an in-silico proof.

**Key methodological finding (v2):** with display/selection data, **bucket by the enriched tail
(log2FC>threshold), not quantiles** — selection kills most peptides so quantile-"high" dilutes the rare
strong-binder tail (+0.066 vs +0.317, ~4.8× difference).

## Structure-prior component (the reuse path, demoted from headline)
- **BoltzGen cyclic fine-tune:** pipeline validated at scale (converted 229/236; trained ~27 epochs);
  first full run crashed on a dataloader `selector.select` IndexError on one bad complex → fixed with a
  robust skip-bad-sample patch; **re-run in progress** for a real checkpoint. Its LOTO eval remains the
  honest novel-target datapoint for the structure path (expected to plateau per the surveys).

## The honest frontier (NOT yet proven)
1. **Wet-lab validation** — everything is in-silico/RF-proxy; real proof = SPR/display against reality + the closed loop.
2. **Multi-target generalization** — the LLMs are single-target (v2) or property- (not target-) conditioned (MVP). The hard problem is target-conditioned generation that generalizes to a new target.
3. **Richer chemistry** — AA-sequence / SMILES MVPs; HELM/monomer gives arbitrary ncAA + cyclization.

## v3 plan (the real differentiation)
- **Representation:** HELM/monomer (arbitrary ncAA/cyclization as first-class).
- **Data:** assemble a **multi-target** display pool (harvest more public display accessions) → target-conditioned training → test cross-target generalization with a leakage-controlled held-out-target split (honest per-synthesized metric, not per-shortlist).
- **Loop:** close it with real assay readouts so conditioning is validated against reality, not an RF proxy.
- Small-LLM fit (per `project_llm_harness_task_split`): this stays a small, cheap, on-prem-deployable domain model; the moat is the data + loop, not parameters.

## Artifacts
Docs: `20261005_INNOVATION_THESIS_CYCLIC_LLM.md`, `20261005_CYCLIC_LLM_MVP_RESULTS.md`,
`20261005_DISPLAY_NGS_HARVEST.md`, `20261006_CYCLIC_LLM_V2_DISPLAY_RESULTS.md`,
`20261005_CHALLENGE_INVENTORY_RECOVERED.md`. Code: `research/guangzhou_all_atom/cyclic_llm/*`,
`harvest_display_ngs_rapid.py`. Checkpoints on S3 under `cyclic_peptide/runs/cyclic-llm-*`.
