# CRO Statement of Work — Multi-HLA Machinery-KO Immunopeptidome Atlas (H4 cross-allele generalization)

Date 2026-09-14. Derived from the leave-HLA-out gate analysis (`H4_GATE_CORRECTED_VERDICT.md`,
`LEAVE_HLA_OUT_RESULT_CORRECTED.json`, `HARD_ESSENTIAL_KO_RESCAN.json`, `RENORMALIZATION_SPEC.md`).

> **Provider caveat:** capabilities below were checked via public web search on 2026-09-14 but
> NOT confirmed with the vendors. Treat Part B as a shortlist to qualify by direct contact, not
> a verified vendor list. Pricing/scale figures are order-of-magnitude — obtain quotes.

---

## 1. Why this experiment (the gap it closes)
The H4 thesis — antigen-presentation is controlled by antigen-processing **machinery state**, not
source-protein abundance — is **corroborated but only within HLA-A\*02:01**. Every public
hard-essential-KO immunopeptidome (HAP1, A375, THP-1, HeLa, C1R-A2, K562-A2) is A\*02:01; the
corrected gate transfers across A\*02 *cell lines* (ρ=+0.68, p=0.0003) but **cross-allele
generalization is 100% untested and cannot be sourced from public data.** This CRO supplies the
one missing axis: hard-essential machinery KO on **allele-disjoint, non-A\*02** backgrounds.

## 2. Experimental design (factorial; the 4-layer version also closes H2/H3)
| Axis | Requirement |
|---|---|
| **HLA backgrounds** | **≥3 allele-disjoint, non-A\*02:01** cell lines, each with an **expression-validated** HLA-I genotype. Span distinct supertypes/anchors (e.g. representatives among A\*01:01, A\*03:01, A\*11:01, A\*24:02, B\*07:02, B\*08:01). **Mono-allelic** lines (single defined HLA-I allele on an HLA-null parent, e.g. 721.221- or K562-based transfectants) are STRONGLY preferred — clean per-allele deconvolution and disjointness by construction. |
| **Machinery perturbations** | Per background: **WT + hard-essential KO panel {B2M, TAP1, TAP2, TAPBP}** (≥3 KOs/background — the gate needs ≥3 KO conditions per background for an informative fold). Optional contrast arms: ERAP1 (trimmer), IFN-γ induction (inflammation axis → feeds tolerance score). |
| **Modalities (same flask)** | **HLA-I immunopeptidome (W6/32 antibody-IP)** + **matched proteome** (mandatory — the abundance baseline B1). ADD **Ribo-seq + RNA-seq** on the same cultures to simultaneously close H2 (translation efficiency) and H3 (protein abundance) at marginal extra cost. |
| **Replicates** | ≥2 biological replicates/condition (≥3 for the WT anchor). |
| **Scale** | HLA-I IP typically needs ~1–5 ×10⁸ cells/sample; plan cell expansion accordingly. |

Minimal footprint: 3 backgrounds × (WT + 4 KO) × 2 reps ≈ **30 immunopeptidome units** + matched
proteome (+ optional RNA/Ribo). Design is factorial so the model can do **leave-allele-out** and
**leave-KO-out**.

## 3. Non-negotiable methodological requirements (lessons already paid for)
1. **Antibody-IP (W6/32 pan-HLA-I), NOT mild-acid-elution.** MAE co-elutes a large
   B2M-independent intracellular background that produced a false "88% retained" for A375 B2M-KO
   (corrected to a real collapse only after ligand-stratification). Acid-elution data is not
   comparable and must be avoided.
2. **Verified-complete KOs.** Confirm target-protein absence (Western blot AND in the matched
   proteome). A leaky/partial KO invalidates the collapse readout. Reject clones with residual
   target protein.
3. **Matched proteome on the SAME samples** — required for the source-abundance baseline; without
   it the "beyond-abundance" H4 metric cannot be computed.
4. **Expression-validated HLA genotype** per line (do not trust vendor/catalog genotypes — a wrong
   HAP1 genotype depressed its measured ligand-fraction ~20× in our own analysis).
5. **Absolute quantification** (copies/cell or spike-in) where feasible, for the H4 abundance head.

## 4. QC / acceptance criteria (bake into the SOW)
- **KO completeness:** target protein ≤5% of WT (WB + proteome). Fail → reject clone.
- **Immunopeptidome depth:** ≥1,500 unique 8–12mer HLA-I ligands per WT sample (class-I).
- **Ligand purity:** length distribution with a clear 9mer peak; ≥60% of peptides NetMHCpan/MHCpan
  %rank ≤2 against the line's own alleles. (Low purity = prep problem.)
- **Reproducibility:** replicate ligand-overlap ≥ agreed threshold; quantitative CV reported.
- **B2M-KO positive control:** each background's B2M-KO must collapse HLA-I ligands to <~20% of
  WT (the expected biology) — this is the built-in sanity check that the assay works.

## 5. Deliverables (data schema)
- Raw MS (`.raw`/`.d`) + processed **per-condition peptide tables** (peptide, intensity, charge,
  RT, run) for immunopeptidome and proteome; **RNA/Ribo count tables** if 4-layer.
- Per-line: validated HLA-I genotype, KO validation (WB + proteomic evidence), cell counts.
- Machine-readable metadata: background, allele set, KO gene, condition, replicate, enrichment
  method, absolute-quant method. (Match our `RENORMALIZED_H4_CORPUS.json` schema.)
- License: data usable for model training/eval without downstream restriction.

## 6. How it feeds the model (acceptance = the gate)
On delivery, re-run `leave_hla_out_gate.py` with the new **disjoint-allele** backgrounds:
PASS = pooled leave-allele-out transfer ρ≥0.3, permutation p≤0.05, **≥3 allele-disjoint
backgrounds** each carrying the machinery-severity→presentation-loss ordering. PASS establishes
H4 cross-allele generalization — the differentiator claim. All scoring **ligand-stratified**
(per-line alleles), never raw totals.

## 7. Order-of-magnitude scope (obtain quotes; do not treat as a budget)
- CRISPR-KO line generation (validated): ~$3–10k/line commercial; academic-core rates lower.
- HLA-I immunopeptidomics MS: ~$1–3k+/sample at scale (IP + LC-MS/MS + analysis); ~30–45 samples.
- Matched proteome: incremental; RNA-seq/Ribo-seq: relatively cheap add-ons.
- Realistic minimal program: low-to-mid six figures. Phase it: 3 backgrounds first; expand if PASS.

---

## Part B — Houston-area providers (qualify by direct contact)

**Reality check:** immunopeptidomics (HLA-IP + LC-MS/MS) is specialized; there is **no turnkey
single-vendor immunopeptidomics CRO in Houston** in the public results. The Houston path is to
**assemble** the workflow across academic cores; a specialist national CRO is the turnkey fallback
for the HLA-ligandome leg.

### Houston academic cores (assemble the workflow)
- **Baylor College of Medicine — Mass Spectrometry Proteomics Core** (Dan L. Duncan Cancer Center /
  CPRIT-supported). Full fee-for-service MS proteomics, **serves external users**, offers a free
  design consult (msproteomicscore@bcm.edu). *Best Houston candidate for the proteome + MS leg;
  confirm whether they run HLA-I immunopeptidomics (W6/32 IP) or only standard proteomics.*
  ([services](https://www.bcm.edu/research/atc-core-labs/mass-spectrometry-proteomics-core/services) ·
  [fees](https://www.bcm.edu/research/atc-core-labs/mass-spectrometry-proteomics-core/fees))
- **BCM — CPRIT Cancer Proteomics & Metabolomics** (cancer-focused MS)
  ([link](https://www.bcm.edu/academic-centers/dan-l-duncan-comprehensive-cancer-center/research/cancer-center-shared-resources/cprit-cancer-proteomics-and-metabolomics)).
- **MD Anderson Cancer Center** — has active **immunopeptidomics/HLA-ligandome research groups**
  plus genome-editing and clinical **HLA typing** labs. No public turnkey service listing, but the
  in-house expertise is world-class; approach via a core/collaboration. (Confirm service access.)
- **HLA genotyping:** MD Anderson HLA lab or a clinical HLA lab for the expression-validation step.

### CRISPR-KO cell line engineering (KO can be done anywhere, ship cells to the Houston MS core)
No Houston-specific commercial vendor surfaced; national providers ship validated KO lines:
[GenScript](https://www.genscript.com/CRISPR-genome-edited-mammalian-cell-lines.html) ·
[VectorBuilder](https://en.vectorbuilder.com/products-services/service/stable-cell-line/knockout.html) ·
[abm](https://www.abmgood.com/CRISPR-Stable-Knockout-Cell-Line.html) ·
[BPS Bioscience](https://bpsbioscience.com/crispr-services) ·
[Cellecta](https://cellecta.com/products/custom-engineered-cell-lines). Or use an MD Anderson/BCM
genome-editing core to keep it local.

### Turnkey specialist alternative (if you don't want to assemble)
- **CellCarta** — global CRO with **US facilities**, integrated immunopeptidomics/HLA-peptidomics
  offering ([site](https://cellcarta.com/)).
- **Biognosys** — CRO with a dedicated
  [immunopeptidomics service](https://biognosysgroup.com/cro-services/proteomics/immunopeptidomics/).
- **Creative Proteomics** — immunopeptidome profiling
  ([link](https://www.creative-proteomics.com/peptidomics/integrated-analysis-of-immunopeptidomics.html)).
These do the HLA-ligandome MS end-to-end; you'd still supply/commission the validated KO lines.

## Recommended path
1. **Qualify BCM MS Proteomics Core** for HLA-I immunopeptidomics (W6/32 IP + LC-MS/MS) + matched
   proteome — the free consult is the cheap first call. If they can do the IP step, the whole wet
   pipeline stays in Houston.
2. **KO lines:** MD Anderson/BCM genome-editing core (local) or a commercial vendor; insist on the
   §4 KO-completeness QC.
3. **If BCM can't run the HLA-IP leg:** keep proteome/RNA/Ribo local, send the immunopeptidome leg
   to CellCarta/Biognosys.
4. Start with **3 disjoint-allele backgrounds** (ideally mono-allelic); expand only if the gate PASSes.
