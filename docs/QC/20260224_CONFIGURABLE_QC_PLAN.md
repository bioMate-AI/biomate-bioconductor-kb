# Configurable QC Thresholds — Product & Engineering Plan

**Date:** 2026-02-24
**Authors:** PM Review + Domain Expert Review (dual-agent audit) + BioMate Engineering
**Status:** Approved for implementation

---

## Executive Summary

Fixed QC thresholds generate two distinct harms:

1. **High-frequency / medium-severity:** False-positive gate modals on legitimate data (cardiac scRNA-seq, FFPE WGS, soil metagenomics, non-model organism RNA-seq). Erodes user trust; causes reflexive "proceed anyway" clicks that blind users to real failures.
2. **Low-frequency / high-severity:** Thresholds that are too permissive for a specific application (e.g., 30X WGS coverage applied to clinical WES) silently pass data that should have been flagged.

The domain expert audit found **3 categories of current thresholds** requiring immediate attention due to high false-positive rates in practice:
- RNA-seq alignment rate for non-polyA libraries (FFPE, ribo-depletion, snRNA-seq)
- Duplicate rate for FFPE / cfDNA / amplicon panels
- scRNA-seq mito fraction for cardiac and neuronal tissue

---

## Architecture Decision: Three-Layer System

PM and domain expert agree on a layered approach, with strict governance at each layer.

```
Layer 0: Red Lines          — hardcoded, no override ever
Layer 1: GOLD thresholds    — no user override (ENCODE4 / GATK mandated)
Layer 2: SILVER/BRONZE      — override with justification + audit log
Layer 3: Named profiles     — curated sets of layer-2 overrides for known contexts
Layer 4: Metadata-inferred  — system suggests profile from workflow metadata (Phase 3 only)
```

---

## Layer 0: Red Lines — Non-Negotiable Hard Stops

These 6 checks detect conditions that produce **scientifically invalid results** regardless of biology. No user override ever. Hardcoded in `qc_trace_monitor.py`.

| Check | Hard Floor | Scientific Rationale |
|-------|-----------|----------------------|
| Reads surviving trimming | < 50% | > 50% loss = adapter-dominated library; downstream analysis is invalid |
| ATAC-seq NRF | < 0.5 | > 50% PCR duplicates = peak calls are amplification artifacts, not biology |
| CTF fit quality (cryo-EM SPA) | < 0.5 | CTF estimation completely failed; particle picking is nonsense |
| FLAGSTAT mapped rate (DNA-seq) | < 30% | No biological context makes < 30% mapping valid; sample swap or catastrophic failure |
| scRNA mito fraction | > 80% | Dead-cell lysates, not transcriptomes; results are biologically meaningless |
| Sample swap / sex concordance | mismatch | Integrity violation; halt unconditionally regardless of user instruction |

**Implementation:** These are enforced server-side and cannot be overridden even via API. They should be clearly labeled as "hard stops" in the QC gate modal with the scientific rationale displayed.

---

## Layer 1: GOLD Thresholds — No User Override

Strong evidence base (ENCODE4, GATK Best Practices). Can only be changed by updating the platform codebase with a new evidence citation.

| Domain | Metric | Gate | Source |
|--------|--------|------|--------|
| DNA-seq | FLAGSTAT mapped | < 70% | GATK Best Practices |
| DNA-seq | MARKDUP dup rate | > 40% (WGS) | GATK Best Practices |
| ATAC-seq | TSS enrichment | < 5 warning, < 3 critical | ENCODE4 (2022) |
| ATAC-seq | NRF | < 0.9 warning, < 0.5 critical | ENCODE4 (2022) |
| ATAC-seq | FRiP | < 0.2 | ENCODE4 (2022) |

---

## Layer 2 & 3: Override-Eligible Thresholds + Named Profiles

### Override Rules (Layer 2)
- Any SILVER or BRONZE threshold may be overridden
- Override in a **more permissive** direction requires a **justification field** (required, not optional)
- All overrides logged to `qc_threshold_overrides` table (immutable)
- Downstream result artifacts display a visible banner when thresholds were overridden

### Named Profile Catalog (Layer 3)

Domain expert has provided 20+ scientifically justified profiles. These are BioMate-curated, versioned, read-only for end users (users may fork but not edit originals).

#### RNA-seq Profiles

| Profile ID | Alignment min | Dup threshold | Trimming min | Key change from default | Source |
|------------|--------------|---------------|--------------|------------------------|--------|
| `rnaseq_polya_standard` | 70% | 40% | 70% | **Default** | nf-core/rnaseq v3.14 |
| `rnaseq_ribodepleted` | 50% | 40% | 65% | Ribo-depletion removes more reads | Zhao et al. 2020, *RNA Biol* |
| `rnaseq_ffpe` | 45% | 40% | 60% | Degraded RNA produces short reads | Sinicropi et al. 2012, *PLOS ONE* |
| `rnaseq_single_nucleus` | 50% | — skip — | 70% | snRNA-seq intronic reads misalign to spliced ref | 10x Genomics snRNA-seq Guide v2.0 |
| `rnaseq_nonmodel_organism` | 40% | 40% | 70% | Incomplete genome annotation | No formal standard; [BRONZE] |

#### DNA-seq / WGS / WES Profiles

| Profile ID | Coverage threshold | Dup threshold | Key change from default | Source |
|------------|-------------------|---------------|------------------------|--------|
| `wgs_germline_standard` | 30X | 40% | **Default WGS** | GATK Best Practices |
| `wgs_germline_lowpass` | 4X | 60% | Population genetics / imputation studies | UK Biobank; Rubinacci et al. 2021, *Nat Genet* |
| `wgs_somatic_tumor_normal` | 60X tumor / 30X normal | 50% | Somatic mutation calling | GATK Mutect2 guidelines |
| `wgs_somatic_tumor_only` | 80X | 50% | Single-sample somatic | GATK Mutect2 guidelines |
| `wgs_ffpe` | 30X | 65% | FFPE PCR bias | Robbe et al. 2018, *Nat Med* 24:1555 |
| `wes_clinical_germline` | 80X | 40% | Clinical diagnostic standard | ACMG 2016 NGS Technical Standards |
| `wes_research` | 50X | 40% | Research WES | nf-core/sarek v3 defaults |
| `cfdna_liquid_biopsy` | 500X | 70% | cfDNA is highly duplicated at depth | Wan et al. 2017, *Nat Rev Genet* 18:490 |
| `amplicon_panel` | per-amplicon | — suppress — | PCR panels: UMI-based, no dup threshold | ACMG 2016 NGS Standards |

#### scRNA-seq Profiles

| Profile ID | Mito threshold | Mito warning | Cells min | Genes/cell min | Key change | Source |
|------------|---------------|-------------|----------|----------------|------------|--------|
| `scrna_pbmc_immune` | 15% | 10% | 200 | 500 | Strict mito (PBMC typical 3–8%) | Luecken & Theis 2019, *Mol Syst Biol* |
| `scrna_cardiac` | 35% | 25% | 200 | 500 | Cardiomyocytes: high mito respiration | Litvinukova et al. 2020, *Nature* 588:466 |
| `scrna_brain_neurons` | 25% | 18% | 200 | 500 | Neurons: elevated mito, < cardiac | Luecken & Theis 2019 |
| `scrna_ipsc` | 20% | 12% | 200 | 500 | iPSC: moderate mito | Standard; [BRONZE] |
| `scrna_atlas_scale` | 20% | 10% | — suppress fixed — | — suppress fixed — | At atlas scale (100K+ cells), fixed floor is meaningless | No formal standard |

**Note on cells_detected:** The domain expert recommends replacing the fixed 200-cell floor with a relative check against `expected_cells` from loading parameters. This is a Phase 2 change requiring metadata schema updates.

#### ChIP-seq / ATAC-seq Profiles

| Profile ID | FRiP threshold | Peaks min | Key change | Source |
|------------|---------------|-----------|------------|--------|
| `chipseq_tf_encode4` | advisory (0.01) | 1,000 | **Default** (TF ChIP is sparse) | ENCODE4 ChIP-seq Standards v4.3 |
| `chipseq_histone_sharp` | 0.1 (hard gate) | 5,000 | H3K4me3, H3K27ac, H3K4me1 | ENCODE4 |
| `chipseq_histone_broad` | 0.05 (hard gate) | 500 (broad domains) | H3K27me3, H3K9me3, H3K36me3 | ENCODE4 |
| `cutrun_tf` | 0.2 (hard gate) | 2,000 | CUT&RUN signal-to-noise >> ChIP | Meers et al. 2019, *eLife* |
| `cutrun_histone` | 0.25 (hard gate) | 5,000 | CUT&RUN histone marks | Meers et al. 2019, *eLife* |
| `atacseq_encode4_human` | 0.2 | 50,000 | **Default ATAC** | ENCODE4 ATAC-seq Standards 2022 |
| `atacseq_nonmodel` | 0.15 | 10,000 | TSS enrichment suppressed | [BRONZE] |

#### Metagenomics Profiles

| Profile ID | Critical threshold | Warning threshold | Key change | Source |
|------------|-------------------|------------------|------------|--------|
| `metagenomics_human_gut` | 50% | 60% | Human-associated; HMP benchmark | HMP Consortium 2012, *Nature* |
| `metagenomics_human_skin` | 25% | 40% | More diverse than gut | HMP Phase 2 |
| `metagenomics_soil` | — suppress critical — | advisory only | Soil dark matter: 5–40% normal | Bahram et al. 2018, *Nature* 560:233 |
| `metagenomics_marine` | — suppress critical — | advisory only | Marine: 10–50% normal | Sunagawa et al. 2015, *Science* 348:1261359 |
| `metagenomics_clinical_pathogen` | 60% | 70% | Clinical samples dominated by known pathogens | [BRONZE] |

#### Cryo-EM Profiles

| Profile ID | Drift threshold | CTF fit min | Key change | Source |
|------------|----------------|------------|------------|--------|
| `cryoem_spa_purified` | 50Å | 0.7 | **Default SPA** | EMPIAR community; EMDB standards |
| `cryoem_spa_membrane` | 80Å | 0.65 | Membrane proteins more flexible | [BRONZE] |
| `cryoem_tomo_purified` | 60Å | 0.65 | Tomography subtomogram averaging | [BRONZE] |
| `cryoem_tomo_in_situ` | 150Å | 0.5 | Cellular lamellae: high drift expected | [BRONZE] |

---

## Minimum Metadata Schema (Required for Phase 2 Profile Selection)

The domain expert has identified the fields needed for correct profile auto-suggestion. These fields are required at workflow submission time and drive both profile suggestion (Phase 2) and eventual metadata-inference (Phase 3).

### Required Fields (gate profile selection)
```yaml
organism:          string   # "Homo sapiens", "Mus musculus", free text for non-model
genome_assembly:   string   # "GRCh38", "mm39", "T2T-CHM13", "custom"
assay_type:        enum     # rna_seq | dna_seq | atac_seq | chip_seq | scrna_seq | metagenomics | cryo_em
library_type:      enum     # [assay-dependent validated list — see below]
sample_source:     enum     # fresh_frozen | ffpe | cell_line | primary_culture | organoid
                            # cfdna | xenograft | environmental
```

**Library type by assay:**
- RNA-seq: `polya | ribo_depleted | total_rna | single_nucleus | ffpe`
- DNA-seq: `standard_wgs | wes | amplicon_panel | cfdna | ffpe_wgs`
- ChIP/ATAC: `tf_chip | histone_sharp | histone_broad | cut_and_run | atac_bulk | atac_multiome`
- scRNA-seq: `10x_chromium_3prime | 10x_chromium_5prime | smart_seq2 | smart_seq3 | parse_bio`
- Metagenomics: `shotgun_illumina | shotgun_nanopore | amplicon_16s | amplicon_its`
- Cryo-EM: `spa_purified | spa_membrane | tomo_purified | tomo_in_situ`

### Strongly Recommended Fields (unlock profile auto-suggestion)
```yaml
tissue:              string   # "heart", "brain cortex", "PBMC", "HEK293", "soil"
                              # controlled vocabulary preferred; free text accepted
application:         enum     # research | clinical_research | clinical_diagnostic | population_genetics
target_type:         enum     # (ChIP only) tf | histone_sharp | histone_broad | chromatin_remodeler
environment_type:    enum     # (metagenomics only) human_gut | human_skin | soil | marine | clinical_pathogen
expected_cells:      integer  # (scRNA only) cells loaded from loading calculator
sequencing_depth:    integer  # target reads per sample, millions
```

### Profile Auto-Suggestion Logic (Phase 2)
When required + recommended fields are provided, suggest the matching profile before launch with a diff table:

```
Suggested profile: "FFPE WGS"
Reason: library_type=ffpe_wgs detected

  Metric              Default     This Profile
  dup_rate_max        40%         65%          ← more permissive
  alignment_rate_min  70%         45%          ← more permissive
  coverage_min        30X         30X          (unchanged)

[Use this profile]  [Customize]  [Use default]
```

---

## Roadmap

### Phase 1 — MVP: Per-Invocation Overrides + Audit Log (Weeks 1–4)

**Scope:**
1. `qc_overrides` dict accepted at workflow launch in the API payload
2. Thread through: launch API → invocation metadata → `NextflowMonitor` → `NextflowQCGateHandler.__init__`
3. `_check_qc_thresholds` reads from `self.qc_overrides` for SILVER/BRONZE thresholds (not GOLD, not red lines)
4. Server-side validation: reject override of red lines, reject GOLD threshold overrides, enforce hard floors
5. `qc_threshold_overrides` DB table: `(id, invocation_id, step_name, metric, default_value, override_value, user_id, justification, timestamp)`
6. QC gate modal and warning events include an `overrides_active: true` flag when thresholds are non-default

**Explicitly excluded from Phase 1:**
- Profile management UI
- Justification field in UI (API-only for MVP)
- Named profile system
- Metadata schema changes

**Target outcome:** Bioinformatician power users can configure one JSON field to eliminate false-positive gate modals for known-difficult assays. Core facility managers can script this into their job submission pipelines.

---

### Phase 2 — Named Profiles + Metadata Schema (Weeks 5–14)

**Scope:**
1. `qc_profiles` DB table: `(id, name, description, assay_type, threshold_overrides JSON, curated_by, version, is_system_profile)`
2. CRUD API for user-owned profiles; read-only for system profiles (fork only)
3. Workflow launch metadata schema fields added (required + recommended above)
4. Profile selector UI at workflow launch: dropdown with diff table before launch
5. 20 BioMate-curated starter profiles from the domain expert's list (see above)
6. Justification field required in UI when profile moves a threshold in a more permissive direction
7. Audit log extended: profile selection logged in `qc_threshold_overrides`
8. "Custom QC profile active" banner shown in QC gate modal when non-default profile is in use

**Highest-priority profiles to ship on day 1 of Phase 2** (based on false-positive frequency):
1. `rnaseq_ribodepleted` — ribo-depletion is extremely common; alignment false positives daily
2. `rnaseq_ffpe` — FFPE RNA-seq is standard in translational research
3. `scrna_cardiac` — cardiac scRNA-seq is a major growth area
4. `wgs_ffpe` — FFPE WGS is standard in clinical oncology
5. `cfdna_liquid_biopsy` — high-value clinical research segment
6. `metagenomics_soil` — soil metagenomics triggers false criticals constantly
7. `chipseq_histone_sharp` / `chipseq_histone_broad` — distinct from TF ChIP but currently treated identically

---

### Phase 3 — Metadata-Inferred Thresholds (Month 6+, conditional)

**Gate criteria (do not start Phase 3 until ALL met):**
- ≥ 200 real workflow runs with Phase 2 profiles, providing ground-truth threshold ↔ biology mappings
- A transparency mechanism exists: system shows the user which inference rule was applied and allows override
- Fallback to explicit profile selection is always available
- No silent auto-adjustment: inferred thresholds are shown to user for confirmation before run starts

**Rationale for delay (PM + domain expert agree):** Auto-adjustment without transparency is the worst failure mode — incorrect science with no visible signal. The risk outweighs the convenience gain until a validation corpus exists.

---

## Open Questions (to be resolved before Phase 1 starts)

1. **`qc_overrides` schema**: Dict of `{metric_name: value}` or richer structure `{metric_name: {value, justification}}`? Richer structure enables better audit trail in the API payload itself.

2. **GOLD threshold enforcement**: When a user attempts to override a GOLD threshold via the API, do we return a 400 error or silently ignore the override? Recommendation: return 422 with the list of non-overridable metrics so the caller knows exactly what happened.

3. **Red line disclosure**: Should red lines be documented in the API reference, or kept opaque to prevent adversarial threshold-seeking? Recommendation: fully document them — transparency builds trust and the scientific rationale is the defense against misuse.

4. **Multi-step threshold scoping**: Can a `qc_overrides` dict apply different thresholds per step (e.g., relax alignment rate for STAR but not for Salmon), or is it workflow-wide? Recommendation: support per-step overrides keyed by `{process_name: {metric: value}}` — this enables fine-grained control without requiring a profile for every combination.

5. **Cells detected replacement**: The domain expert recommends replacing the fixed 200-cell floor with a relative check (`detected / expected_cells < 0.5`). This requires the `expected_cells` metadata field. Do we ship this in Phase 1 (breaking change to the gate) or Phase 2 (when metadata schema is available)? Recommendation: Phase 2 — the current floor, while imperfect, does not generate frequent false positives for standard experiments.

---

## What We Explicitly Will NOT Build

Based on domain expert and PM review:

- **Fully free-form threshold editor with no guardrails** — creates QC theater; users set everything to 0
- **Option C auto-adjustment without user confirmation** — silent misclassification risk
- **Override of GOLD thresholds** — ENCODE4 and GATK standards are the floor; if they are wrong, update the platform with a citation
- **Override of red lines** — scientifically invalid results regardless of biology
- **Tissue-specific scRNA mito thresholds without metadata** — the correct tissue is unknowable without it; using a wrong tissue profile is worse than using the conservative 20% default

---

## Success Metrics (PM-specified)

| Metric | Target | Timeframe |
|--------|--------|-----------|
| QC gate modal dismiss rate ("proceed anyway") | Drop from >40% to <20% | 60 days post-Phase 2 |
| Profile adoption at core facilities | ≥1 custom profile per active core facility account | 60 days post-Phase 2 |
| Override rate for FFPE/ribodep/cardiac workflows | ≥30% using non-default profile | 90 days post-Phase 2 |
| Audit log completeness | 100% of permissive overrides have justification | From day 1 (enforced) |
| Support tickets for "false QC failure" | Reduce by ≥50% | 90 days post-Phase 2 |

---

## References

- ENCODE4 ATAC-seq Standards (2022): https://www.encodeproject.org/atac-seq/
- ENCODE4 ChIP-seq Standards v4.3: https://www.encodeproject.org/chip-seq/transcription_factor/
- Van der Auwera GA, O'Connor BD (2020). *Genomics in the Cloud*. O'Reilly Media.
- Luecken MD & Theis FJ (2019). Current best practices in single-cell RNA-seq analysis. *Mol Syst Biol* 15:e8746.
- Litvinukova M et al. (2020). Cells of the adult human heart. *Nature* 588:466–472.
- Robbe P et al. (2018). Clinical WGS from FFPE specimens. *Nat Med* 24:1555–1563.
- Wan JCM et al. (2017). Liquid biopsies come of age. *Nat Rev Genet* 18:490–506.
- Bahram M et al. (2018). Global topsoil microbiome. *Nature* 560:233–237.
- Meers MP et al. (2019). CUT&RUN: Genomic profiling of histone modifications. *eLife* 8:e46314.
- Rubinacci S et al. (2021). Efficient phasing and imputation of low-coverage sequencing data. *Nat Genet* 53:120–127.
- HMP Consortium (2012). A framework for human microbiome research. *Nature* 486:215–221.
- Dobin A et al. (2013). STAR: ultrafast universal RNA-seq aligner. *Bioinformatics* 29(1):15–21.
- ACMG (2016). Standards and guidelines for the interpretation of sequence variants. *Genet Med* 17:405–424.
- Wood DE, Lu J & Langmead B (2019). Improved metagenomic analysis with Kraken 2. *Genome Biol* 20:257.
