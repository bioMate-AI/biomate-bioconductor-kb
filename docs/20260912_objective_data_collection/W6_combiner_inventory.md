# W6 — Target-selection combiner: data inventory + build spec

**Date:** 2026-09-13 · **Role:** COMBINER · **Bucket:** `s3://knowledge-datasets-1759951976/`
**Companions:** `20260908_TARGET_SELECTION_CHANNELS_DESIGN.md`, `20260909_COMBINER_REDESIGN_evidence_gated_selector.md`, `KG_REGISTRY.md`, `NETWORK_REGISTRY.md`, `CAUSAL_PERTURBATION_IMMUNE_MANIFEST.md`.

## The canonical claim this workstream defends
"The correct target" is **not** an FM head. It is produced by a **null-calibrated, evidence-gated combiner** that (a) scores each evidence channel against its **own matched null**, (b) **OR-gates** channels for nomination/recall, (c) **AND-corroborates** for a confidence tier/precision, weights each channel by its **measured reliability on this substrate**, and always emits a **per-target evidence breakdown**. Druggability is a downstream **GATE** (W5), not a channel.

## Honest current state (measured, not asserted)
Grounded in the S3 result artifacts, not the design prose:

| Channel | Status | Measured evidence (S3) |
|---|---|---|
| **perturbation** (virtual-KO) | **demonstrated** | `P1b/p1b_target_id_ranking.json`: known-regulator AUROC **0.8492** (validated-gold **0.8572**) vs degree/magnitude null **0.6841**. CZI CD4+T Perturb-seq, 7864 KOs. |
| **human genetics** | **demonstrated** | `gold/target_id_baseline.json`: genetics-baseline mean AUROC **0.585** over 8 autoimmune diseases (CD 0.639…SLE 0.543). Design: genetics-anchored **0.7647** vs null on SLE gold; MR from published work. |
| **pathway / gene-set** | **under-test** | `P1c`: 0.706 on TF universe; `P1d` pathway **0.52** union / **0.7058** own-universe = modest/underpowered on surface gold. |
| **regulatory network** (CollecTRI/DoRothEA) | **under-test** | Same P1c/P1d run (regulon proxy). Real CollecTRI staged (42,990 signed edges) but combiner still routes it through the pathway proxy. |
| **PPI network** (STRING/MAP-KG) | **available-not-fused** | `P1d` network AUROC **≈ degree null** (0.46–0.61). Data present; not yet value-adding. |
| **differential expression** | **available-not-fused** | `P1d` effect_mag **0.6485 ≈ null**. Populates (734 DE genes Perez-2022), no independent lift. |
| **cell-type/state specificity** | **to-build (channel)** | Data deep (DICE 15 types + sc atlas) but **no channel code** and no measured run. |
| **proteomic / autoantibody** | **to-build (channel)** | ImmPort (8.09 GB, quarantined) + PXD023038 present; **no channel wired**. The Mohan-pilot channel. |
| **knowledge priors** (OpenTargets/DisGeNET) | **available-not-fused** | DisGeNET *is* the gold → keep as **soft prior only** (circularity risk); de-circularize as in the 0.7647 run. |

**The v1 averaged combiner is a clean NEGATIVE** (`P1d/target_selection_fixed.json`): `AUROC_combined=0.8542` **<** `AUROC_best_single_real=0.8572` (perturbation). Genetics was **UNPOPULATED** for the CZI substrate (honestly, not faked). This is *exactly* why the redesign moved from "average for lift" to "OR-gate + AND-corroborate."

**Bottom line: data availability is NOT the blocker.** 8 of 9 channels have data present or a staged artifact on S3; the 2 to-build channels (cell-state, proteomic) also have their data present — only the channel code is missing. **The missing piece is the combiner LOGIC itself.**

## Channel data locations (S3, verified 2026-09-13)
- Genetics: `…/genetics/genetics_priors_long.parquet`; `…/tracks/structured_knowledge/dice/` (15 immune eQTL/TPM); `gold/target_id_baseline.json`.
- Perturbation: CZI T-cell Perturb-seq atlas (18,129 genes, ~22M cells); `…/perturbation/` (54.68 GB); `…/replogle_nadig` (36.27 GB).
- Pathway: `…/tracks/structured_knowledge/pathways/{reactome,go_bp,kegg}.gmt` (swap KEGG→WikiPathways for commercial); `…/msigdb_c7/…gmt`.
- Regulatory: `…/tracks/structured_knowledge/tf/collectri_human.tsv` (42,990 signed). Replace the GTRD-mislabel in `bakeoff_fm.py`.
- PPI: `…/tracks/structured_knowledge/ppi/string_ppi_hc.parquet`; MAP-KG `…/immune_llm_models/rebakeoff_stage/A_mapkg_full_edges.parquet` (233,773/vocab).
- DE / cell-state: `…/full_v1/imid/curated/imid.h5ad`; harmonized/immune_expanded arms; DICE.
- Proteomic: `…/immport` (quarantined); `…/proteome_raw/PXD023038`; Mohan LN cohort (external, not landed).
- Knowledge priors: `biomni_data_lake/{DisGeNET.parquet.gz,kg.csv.gz,txgnn_prediction.pkl.gz}`; OpenTargets (not staged).

---

## BUILD SPEC — null-calibrated, evidence-gated combiner

### Contract
Input: a disease/endotype signature `s` + a candidate gene universe `G`.
Output: a ranked target list, each row carrying **per-channel null-calibrated scores**, an **OR-gate nomination flag**, an **AND-corroboration confidence tier**, and a **human-readable evidence breakdown**.

### 1. Per-channel score + matched null (each channel is independent + swappable)
Every channel `k` emits, for each gene `g`: a raw score `x_k(g)` and a **null distribution** from a channel-specific matched control, converted to a calibrated signal `z_k(g)` (empirical p or z vs null). Matched nulls (from the design):

| Channel | Score | Matched null |
|---|---|---|
| genetics | strength/consistency of genetic support (GWAS/eQTL/pQTL/coloc/MR) | AF / LD / gene-length matched genes |
| perturbation | signed projection of KO effect onto `s` | degree/abundance null (global effect magnitude + expression level) — **already implemented (P1b)** |
| pathway | pathway/gene-set enrichment of `g`'s sets in `s` | gene-set-size-matched random sets |
| regulatory | regulon-activity enrichment (CollecTRI signed / decoupler) | regulon-size null |
| PPI | connectivity/centrality to the disease module | degree-preserving rewired network |
| DE | disease-vs-control effect size | label permutation |
| cell-state | signal concentrated in disease-driving state (not bulk avg) | cell-type-shuffled null |
| proteomic | differential protein / autoantigen | abundance-matched permutation |
| knowledge prior | OpenTargets/DisGeNET association | **not hit-tested** — soft prior/shrinkage only (annotation-depth-matched if scored); avoid circularity vs gold |

**A channel at ≈ null contributes ~0 automatically** (network/effect_mag today) — no hand-tuned down-weighting needed.

### 2. Nomination — OR / max across channels (RECALL)
A target is **nominated** if `z_k(g) > τ_k` for **any** null-beating channel `k`. Genetics-only and perturbation-only are each valid high-confidence hits — this is a first-class rule, not a fallback. `τ_k` set from the channel's own null (e.g. empirical FDR).

### 3. Confidence tier — AND / corroboration (PRECISION)
Tier = the count/weight of **independent** channels that fire above `τ_k`. More independent agreement → higher tier. This is where "combined" earns its place (lowers FP / de-risks); it need not raise top-1 rank. Report **precision/calibration per tier**, not one averaged AUROC.

### 4. Substrate-adaptive channel trust (rank-aggregation)
Rank-aggregate the calibrated per-channel signals with weights `w_k` = the channel's **measured reliability on THIS substrate** (its null-gap, e.g. AUROC_channel − AUROC_null), **not fixed weights**. Genetics up on observational cohorts; perturbation up when a KO screen exists. Genetics is the de-risking **anchor** (capital + clinical success follow genetics-validated targets). Use a transparent weighted rank-aggregation (Borda / RRA over `z_k`) OR a learned combiner whose weights are **inspected + reported** — never an opaque single score.

### 5. Druggability gate (W5 handoff)
Filter/down-rank the ranked list by W5's druggability+modality-fit gate (cyclic-peptide/PPI-interface). Applied last; never a selection score.

### 6. Per-target evidence breakdown (the REQUIRED output — the product)
For each nominated target emit: `{gene, rank, tier, per_channel: {genetics: z·p·null_gap, perturbation: …, pathway: …, cell_state: …}, which_channels_fired, druggability_gate_status, rationale_string}`. Auditable by a domain expert, not a black box. This is the deliverable Dr. Mohan's question asked for.

### 7. Metrics (from the redesign — replace the single averaged AUROC)
- **recall@k** of the OR-gate against `gold_targets_immune.json`.
- **precision / calibration per confidence tier** (AND-corroboration).
- **Held-out validation:** a **second independent public SLE/LN cohort disjoint from Perez-2022** to break the small-N (n_gold 4/14 surface bias) — before any external (Mohan) pilot.

### 8. Pair nomination (v-next)
Anchor on a validated target + nominate a complementary partner by network separation `sAB = dAB − (dAA+dBB)/2` on STRING/MAP-KG. **Test, not assume** (oncology/hypertension-validated, not autoimmune). Do NOT use topology-beats-potency / parallel>serial / BAFF+IL-17 (refuted).

---

## THE single most important thing to build
**Implement the evidence-gated combiner logic (steps 2–4 + 6) and score it with recall@k + per-tier calibration (step 7).** All nine channels' data is present or staged on S3; two channels (perturbation, genetics) already produce validated null-calibrated signal. The gap is not data and not more channels — it is the **OR-gate-nominate / AND-corroborate / substrate-adaptive-weight aggregation that turns per-channel signals into a ranked, auditable target list**, replacing the v1 averaged combiner that is a proven clean negative (0.854 < 0.857 best-single). Build that against the two demonstrated channels first (genetics on observational cohorts, perturbation on CZI), wire the staged-but-unfused channels (STRING/MAP-KG PPI, DE, CollecTRI regulon) as null-gated add-ons, then add the two to-build channels (cell-state, proteomic) for the Mohan pilot.
