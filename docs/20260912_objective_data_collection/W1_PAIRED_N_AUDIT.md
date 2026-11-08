# W1 — Paired-N Audit (true trainable/validatable N per objective)

**Date:** 2026-09-13 · **Role:** FEASIBILITY · **training_eligible = false** (all rows) · ImmPort quarantined.

**The decisive metric is paired-N** = number of matched *(model-input-feature, objective-label)* pairs, **not** the label count. For each objective below the label side often looks large; the paired side (feature ∧ label on the same unit) is what decides "can we train/validate this." Where a modality is held only as RAW (no processed features) or only as a manifest, the **currently-computable** paired-N is lower than the **exists-publicly** paired-N; both are reported.

## Summary table

| Objective | Feature → Label | paired-N (HELD) | paired-N (exists publicly) | Status |
|---|---|---|---|---|
| **H1** transcriptional perturbation | baseline/control cell → post-perturbation expr | **>100M cells / ~70k (pert×context) conditions** | (held is the corpus) | ✅ ABUNDANT — only objective with a same-experiment paired training corpus already on S3 |
| **H2** translation efficiency | transcriptome → ribo-seq (same sample) | **0** | ~1,000–2,300 generic human matched pairs; **~1** immune-perturbation-matched (PXD013649) | ❌ NEAR-ZERO — biggest cross-modal gap |
| **H3** protein abundance | transcriptome → proteome (same sample/line) | **~0 same-flask** (proteome held RAW-only, unprocessed) | ~950–1,000 cell-line (RNA,protein) pairs + >1,000 CPTAC tumor same-sample pairs | ⚠️ EXISTS but not held/processed; cell-line pairs are cross-study |
| **H4** presentation | machinery-state proteome/pert + HLA → immunopeptidome | **1–2 causal-KO sets** (PXD056426 HAP1 APM, PXD054491 ERAP1) + benign ref (HLA Ligand Atlas) | ~3 same-flask T+P+L triads + ~29 causal-KO sets; hundreds cross-study baseline | ⚠️ THIN (bootstrap-only) → Tier-2 CRO generation required |
| **Vaccine response** (VALIDATE) | baseline transcriptome → seroconversion | **2,125** | — | ✅ Real validation N (label count 6,819 → only 31% paired) |
| **Safety** (VALIDATE) | transcriptome → adverse-event outcome | **~1,047–1,240 subjects** (label-only = 16,516 / 297 arms) | — | ⚠️ MODEST but real — 13–16× label overstatement |
| **Therapy duration** (VALIDATE) | molecular feature → time-to-event | **0 molecular pairs** (88-patient iWITH clinical cohort, covariates only) | — | ❌ ZERO molecular pairs |

## Per-objective detail

### H1 — transcriptional perturbation (FM-TRAIN) — the pairing is intrinsic
Perturb-seq datasets pair *within* the experiment: NTC/vehicle control cells = baseline feature, perturbed cells = label; the *(perturbation-id, cell-context)* is the join key — **no cross-dataset join needed**. Held on S3: **Tahoe-100M** (95.6M cells, 50 lines × ~1,100 compounds, 429 GB), **Replogle-Nadig** DE (4 lines × ~2,000 KDs), **CZI genome-scale primary human CD4⁺ T-cell Perturb-seq** (GWCD4i: 18,129 genes, ~22M cells, pseudobulk + DE_stats, ~107 GB). This is the one objective where a large paired training corpus is already in hand. Caveat: cell-context coverage skews to cancer lines + CD4 T; broader immune cell types thinner.

### H2 — translation efficiency (FM-TRAIN) — 0 held, near-absent for immune contexts
Pair = (RNA-seq, Ribo-seq) from the **same sample** → TE. **Zero Ribo-seq held on S3** (confirmed). Publicly ~1,054 human TE-ready matched pairs (RiboBase) / 2,343 matched RNA (RPFdb), but on **immune/HLA-typed** contexts under matched perturbation it is essentially absent — IFN-γ Ribo-seq exists only on primary macrophages with no matched immunopeptidome. As the perturbation-matched 4-layer (T+R+P+L) cross-modal layer aligned with H1/H3/H4: **1 identified set (PXD013649), 0 held**. This is the biggest H2–H4 modality gap.

### H3 — protein abundance (FM-TRAIN) — proteome held RAW-only
Pair = (transcriptome, proteome) same sample/line. Held: transcriptome side (CCLE/DepMap TPM) yes; proteome side **only PXD023038 (MDA-MB-231 ±IFN-γ DIA) as RAW .raw files, no processed protein matrix** → currently-computable same-flask paired-N ≈ 0 until searched. Publicly: ProCan (949 lines) ∪ CCLE-Nusinow (375) joined to CCLE RNA by DepMap ID → **~950–1,000 cell-line (RNA,protein) pairs** (cross-study), plus **>1,000 CPTAC tumors** with same-sample RNA+protein. Fetch + process required.

### H4 — presentation (FM-TRAIN) — thinnest held layer
Pair = *(cell-context × perturbation × HLA-genotype)* triple with **both** a machinery-state feature (from held T/P) and an eluted-ligand MS readout; HLA genotype supplied by TCLP (1,082 lines). **Held:** PXD056426 (HAP1 11-gene APM-KO, 12 conditions, matched proteome, H4 kill-test PASS: B2M-KO→2% surface) + PXD054491 (ERAP1-KO) + HLA Ligand Atlas (223k peptides, benign reference). The `tracks/immunopeptidome/` entry is a **2–4 KB manifest with dead URLs — no bulk landed L data.** Publicly: ~3 same-flask T+P+L triads (GRANTA-519/PXD020750 is the clean prize) + **~29 verified perturbation-paired immunopeptidome sets** (ERAP1/2, B2M, TAPBP/TAPBPR, CIITA KO; DNMTi/HDACi/MEKi/AZA; ONX-0914 MSV000091285) + hundreds of cross-study baseline pairs via CCLE. **Verdict:** enough to build the pipeline and run the IFN-γ kill-test, **not** enough to be a generalizing training corpus → **Tier-2 CRO generation required.**

### Vaccine response (VALIDATE) — 2,125 paired (of 6,819 labels)
subject → biosample → expsample → public-repo baseline transcriptome **∧** measured pre/post titer. **paired-N = 2,125** baseline-transcriptome subjects across 40 studies (GEO 2,178 / SRA 69, any-timepoint 2,188; baseline 2,125). Only 31% of the 6,819 response-labeled subjects are paired — the label count is not the metric. dbGaP links excluded (controlled genotype, not transcriptome).

### Safety (VALIDATE) — ~1,047–1,240 paired (of 16,516 labels)
**Label-only:** 297 arms / 107 studies / **16,516 subjects** with AE rates + denominators (92,733 AE rows). **This is not the paired-N.** Intersecting AE-labeled subjects with those carrying a public-repo (GEO/SRA) expsample link: **1,240 subjects have both**; **1,047** after excluding 193 subjects whose linked biosample material is `DNA` (genotype/exome, not expression). Concentrated in **9–10 studies** (SDY1880/1903 270 each, SDY1402 250, SDY1490 133). Accession prefixes GSM 2,501 + SRX 207 (sample-level). Component counts: 16,516 label subjects; 7,258 have a GEO/SRA/ENA link; intersection 1,240. **The label count overstates the paired-N by 13–16×.** Caveat: per-GSM assay type (RNA-seq vs methylation/miRNA/scRNA) not individually verified → 1,047 is an upper bound on true RNA-expression pairs.

### Therapy duration (VALIDATE) — 0 molecular pairs
iWITH / SDY1490 gives a real patient-level time-to-event cohort — **88 enrolled, 40 biopsy-proven rejection events (45.5%), median 230 d** — but with **only age/sex/rejection-history covariates, no transcriptome landed**. Aggregate RA/asthma/lupus withdrawal arms (194/104/43 trials) are arm-level label aggregates, no per-patient molecular feature. **molecular-feature → duration paired-N = 0.**

## The 2–3 biggest gaps

1. **H2 translation efficiency ≈ 0 paired (held), ~1 immune-matched (public).** No Ribo-seq held at all; matched RNA+Ribo on immune/HLA-typed contexts under perturbation is near-absent (1 identified 4-layer set, PXD013649). The T→R→P chain must be trained on *unpaired* Ribo-seq with modality-dropout, or generated.
2. **H4 presentation held paired-N = 1–2 sets** (PXD056426, PXD054491) vs. a thin public perturbation-matched layer (~3 triads + ~29 causal-KO). Immunopeptidome is the least-held modality (manifest-only). Bootstrap-feasible for the kill-test, not corpus-sufficient → **Tier-2 generation is the moat, not scraping.**
3. **Validation objectives are label-rich but pairing-poor.** Vaccine: 6,819 labels → **2,125** paired (31%). Safety: 16,516 AE-labeled subjects → only **~1,047–1,240** paired (transcriptome ∧ AE), a 13–16× overstatement, concentrated in ~9 studies. Duration: 88-patient clinical cohort but **0** molecular pairs. For every validation objective, the label count massively overstates the validatable N — the paired-N is the number to plan against.

**Note (H3):** proteome exists publicly at ~950–1,000 cell-line pairs + >1,000 CPTAC tumors but is held only as one set's unprocessed RAW; it is a fetch+process task, not a fundamental data absence.
