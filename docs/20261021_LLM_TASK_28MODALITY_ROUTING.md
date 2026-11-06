# LLM Task — 28-Modality Orchestration / Routing (SCAFFOLD + HANDOFF)

**Status: PARKED — scaffold only, not trained.** Self-contained handoff so another session can resume cold.
**Date:** 2026-10-21 · **Scope:** the BioMate ORCHESTRATOR/ASSISTANT LLM task (identify drug modality + route a design request), **not** the cyclic-peptide design model.

---

## 1. What this task is

Given a drug-design request, the assistant must output the **drug modality** (one of 28) + **intent** + the **recommended route** (proposer/evaluator workflow set). This is the universal-assistant / composer-routing play — one model that understands all 28 modalities and routes to modality-specific workflows. It is the SFT-from-gold / routing family of task, **not** a generative design model.

**Why it's a defensible LLM task (vs just retrieval):** the LLM must add value *over* dense-cosine catalog retrieval (the lane arbiter) on **ambiguous / under-specified / multi-modal** requests where retrieval over workflow names fails (e.g. "degrade KRAS" → PROTAC vs molecular glue; "hit PD-L1 with a biologic" → mAb vs bispecific vs ADC). If it does not beat retrieval on those, it should not own the task.

---

## 2. The 28-modality taxonomy (grounded)

**Source:** `docs/20260509_modality_coverage_audit.md` (verified against `backend/database/galaxy_ai_tools.db`), expanded to 28 with the standard pharma therapeutic-modality taxonomy. The modality→route map uses **real catalog workflow names** from that audit; the `coverage` flag is the audit's own verdict.

| # | modality | coverage | routable | route (real catalog workflows, abbrev.) |
|---|---|---|---|---|
|1|small_molecule|excellent|✅|Docking Autodock Vina, Drugclip Virtual Screening, REINVENT4, ADMET, OpenFE RBFE|
|2|covalent_small_molecule|good|✅|Covalent Warhead Design, MOE Covalent Docking, ADMET|
|3|protac_degrader|good|✅|protac_design, ADMET|
|4|molecular_glue|partial|❌ GAP|(shares protac_design; no dedicated glue wf)|
|5|scaffold_hop|excellent|✅|scaffold_hopping, Physicochemical, ADMET|
|6|linear_peptide|good|✅|Boltz Structure Prediction, GROMACS MD+MM-GBSA|
|7|cyclic_peptide_macrocycle|good|✅|Boltz, **gromacs_pmx_fep**, GROMACS MD+MM-GBSA|
|8|peptide_drug_conjugate|partial|❌ GAP|(shares adc_design)|
|9|antibody_mab|excellent|✅|scfv_antibody_design, antibody_developability, proteinfold|
|10|scfv_fragment|excellent|✅|scfv_antibody_design, antibody_developability|
|11|bispecific_antibody|excellent|✅|Bispecific Antibody Design, antibody_developability|
|12|nanobody_vhh|good|✅|scfv_antibody_design, antibody_developability|
|13|fc_engineered_ab|partial|❌ GAP|(antibody_developability + Fcrn PK; no Fc-engineering wf)|
|14|adc|good|✅|adc_design, scfv_antibody_design, ADMET|
|15|large_protein_biologic|good|✅|proteinfold, AlphaFold DB Search, proteome_selectivity|
|16|fusion_protein|partial|❌ GAP|(proteinfold + developability; no dedicated wf)|
|17|sirna_rnai|good|✅|sirna_design_full, sirna_offtarget_analysis, lnp_formulation|
|18|aso_gapmer|good|✅|aso_gapmer_design|
|19|mrna_therapeutic|good|✅|mrna_therapeutic_design, codon-opt, lnp_formulation|
|20|sarna_circrna|none|❌ GAP|(no workflow)|
|21|aptamer|none|❌ GAP|(no workflow — SELEX unbuilt)|
|22|crispr_editing|good|✅|P0 Mrna Validation, codon-opt|
|23|aav_gene_therapy|good|✅|codon-opt, mrna_therapeutic_design|
|24|car_cell_therapy|good|✅|scfv_antibody_design, Bispecific Antibody Design|
|25|tcr_t|partial|❌ GAP|(epitopeprediction only; no TCR-T wf)|
|26|nk_cell_therapy|none|❌ GAP|(no workflow)|
|27|vaccine_epitope|good|✅|nf-core/epitopeprediction, mrna_therapeutic_design, codon-opt|
|28|radiopharmaceutical|partial|❌ GAP|(biodistribution + dosimetry only; no design wf)|

**Routable: 19/28** (5 excellent + 14 good). **9/28 are route-GAPs** (6 partial + 3 none): `molecular_glue, peptide_drug_conjugate, fc_engineered_ab, fusion_protein, sarna_circrna, aptamer, tcr_t, nk_cell_therapy, radiopharmaceutical`. For these the modality can be *identified* but there is **no catalog route to learn** → route label = `GAP`.

---

## 3. Task I/O spec (mirrors the existing routing gold format)

Episode record (`modality_episodes.jsonl`), consistent with `evaluation/local_trial/*routing*` conventions:
```json
{"request": "<free-text design request ± target/tissue>",
 "modality": "cyclic_peptide_macrocycle",
 "intent": "design a cyclic peptide / macrocycle binder",
 "route": ["Boltz Structure Prediction","gromacs_pmx_fep","GROMACS Protein-Ligand MD + MM-GBSA"],
 "routable": true, "coverage": "good",
 "family": "cyclic_peptide_macrocycle:stem0", "split": "train|dev",
 "source": "curated_canonical_seed"}
```
SFT formatting should reuse the `routing_prompt.build_messages` pattern (system router prompt → user request → assistant = modality + route), adapted so the assistant emits `(modality, route)` rather than a single workflow name.

---

## 4. Gold data built (SEED)

- **Builder:** `evaluation/local_trial/build_modality_routing.py`
- **Output:** `docs/20260912_onprem_llm/modality_routing_v1/{modality_episodes.jsonl, taxonomy.json}`
- **Counts:** **336 episodes**, **12 per modality × 28**, split **280 train / 56 dev** (leakage-safe: whole stem-family `stem0` held out for dev, so a request family never spans train/dev).
- **Nature (honest):** these are **curated canonical** requests — templated phrasings grounded in each modality's definition + the audit's required-inputs. They are **SEED gold, NOT real user/connector logs.**

---

## 5. Eval design + the baseline it must beat

- **Metrics:** (a) **modality-ID accuracy** (28-way), (b) **route correctness** on the 19 routable modalities (set overlap / top-route match). Report both; route accuracy only counts where `routable=true`.
- **Split:** leakage-safe, held out by **request family** (not random) — already encoded (`split`, `family`).
- **Baselines the LLM must beat (mandatory — do not claim an LLM win without them):**
  1. **Dense-retrieval** (the lane arbiter / `UnifiedWorkflowSearch` dense-cosine over the catalog) mapped request→workflow→modality. This is the real bar.
  2. **Keyword** baseline (modality keyword match in the request).
- **The honest question:** does the LLM beat dense-retrieval **specifically on ambiguous / under-specified / multi-modal** requests (where retrieval over workflow names has no signal)? Stratify the eval into "explicit-modality" vs "ambiguous" requests and report separately — the LLM's value, if any, is in the ambiguous stratum.

---

## 6. HOW TO RESUME (scaffold → trained-and-evaluated)

1. **Augment the gold (required before training):** the 336-episode seed is insufficient to train (see §7). Add real examples:
   - Mine real routing/connector logs (`frontend/server` routing, connector `workflow_id` labels) and real chat→workflow selections for request→modality pairs.
   - Expand curated requests per modality (esp. ambiguous/multi-modal ones — the stratum that justifies the LLM).
   - Target ≥ ~200–500 real/curated requests per routable modality before a training run.
2. **Format SFT:** adapt `evaluation/local_trial/format_routing_sft.py` + `routing_prompt.py` to emit `(modality, route)`; write `modality_sft_{train,dev}.jsonl`.
3. **Train:** reuse the SFT-from-gold path (`build_sft_from_gold.py` / `serve_sft_gold_standing.sh`) — add this task's jsonl to the multitask mix (`build_multitask_sft.py`). **Spot GPU only.** (NOT run here per the park decision.)
4. **Eval:** adapt `eval_routing_hf.py` (2×2 base/sft × starved/informat) for the 28-way modality-ID + route metric; compute the dense-retrieval + keyword baselines on the same held-out split; report per-stratum.
5. **Decision gate:** keep the task only if SFT beats dense-retrieval on the ambiguous stratum; otherwise retrieval owns routing and the LLM is not needed here.

---

## 7. Honest readiness

**NOT trainable as-is — blocked on gold volume, not on method.** The task is well-defined and the scaffold (taxonomy, I/O schema, leakage-safe split, eval + baselines) is complete and grounded in the real coverage audit + catalog. But the gold is a **336-episode curated SEED (12/modality)** — far below the no-tiny-dataset bar for a 28-way task. Two gaps:
1. **Volume:** needs real routing/connector-log augmentation (~200–500/modality) before any training run.
2. **Coverage:** 9/28 modalities have no catalog route (route-label `GAP`) — those are modality-ID-only until the underlying workflows exist.

**One-line state:** *scaffold + leakage-safe eval harness complete and grounded; PARKED, not trainable until the curated seed is augmented with real routing logs (and 9/28 modalities remain route-GAPs pending catalog workflows).*
