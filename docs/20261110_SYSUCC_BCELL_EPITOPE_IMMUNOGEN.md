# SYSUCC modality coverage — status + new B-cell epitope / immunogen workflow

**Date:** 2026-11-10
**Context:** continuation of the SYSUCC (Sun Yat-sen University Cancer Center / 中山肿瘤医院) modality-capability work. SYSUCC's own drug-research directions: PD-1/PD-L1 IO, ADCs, bispecifics, cell therapy (TCR-T / CAR-T / TIL), and **EBV vaccines / antibodies / mRNA** (Guangzhou is the world center for EBV+ nasopharyngeal carcinoma). This records current status and the next increment built: a license-free **B-cell epitope + immunogen design** workflow, which fills the gap flagged as "the thinnest vs a stated SYSUCC strength."

See also `docs/20261109_SYSUCC_MODALITY_CAPABILITY_AND_ANTIBODY_COMPLEX.md` (capability audit) and `docs/20261109_MHC_BINDING_LICENSE_FREE.md`.

---

## 1. Current status of SYSUCC-tailored workflows

| SOTA gap (ranked in the 11-09 audit) | Status |
|---|---|
| #1 Antibody structure — AF3/Boltz-2 complex | **DONE** — `drug_discovery/antibody_antigen_complex` (Boltz-2), catalog id 14665, validated on dev (interface_iptm 0.964 on an FMC63 Fv vs demo CD19). |
| #4 License-free MHC (class I) | **DONE (class I)** — `immunology/mhc_binding_prediction` (MHCflurry 2), id 14666. Class II still needs the gated NetMHCIIpan (no mature redistributable class-II predictor). |
| #5 EBV immunogen / B-cell epitope / mRNA | **DONE (first increment, this doc)** — `immunology/bcell_epitope_immunogen`, id 14667. |
| #2 ESMFold / AntiBERTa developability | open |
| #3 Macrocycle folding (HighFold/AfCycDesign, ncAA) | open (serves our own peptide lead more than SYSUCC) |

Verified against the catalog (`galaxy_ai_tools.db`): 14665 / 14666 / 14667 all present; FTS routes `bcell epitope`, `EBV vaccine`, `antigenicity epitope` → 14667.

---

## 2. Built: `immunology/bcell_epitope_immunogen` (license-free)

**File:** `backend/biomni_workflows/nextflow_nfcore/subworkflows/immunology/bcell_epitope_immunogen/main.nf`
**Catalog:** id 14667, domain `immunology`, category "Vaccine / Immunogen Design".
**Container:** the shared `biomate/workflow-tools` image (python3 stdlib only — **no new image, no GPU**).

### What it does
Per antigen (fans out one AWS-Batch task each, e.g. EBV gp350 / gH / gL / gB / EBNA1 / LMP2):

1. Scores every residue with the **standard published B-cell propensity scales** used by the classic IEDB tools — all deterministic, open, no license, no model weights:
   - Parker hydrophilicity (1986), Emini surface accessibility (1985), Kolaskar-Tongaonkar antigenicity (1990), Karplus-Schulz flexibility (1985), Chou-Fasman β-turn (1978).
2. Combines them (per-track z-score → antigenicity-weighted composite) and calls contiguous **linear B-cell epitopes** above a data-driven cutoff (mean + k·σ), ranked by composite propensity.
3. `BUILD_IMMUNOGEN` (optional) assembles the top distinct epitopes across antigens into a **draft multi-epitope vaccine protein** (GPGPG B-cell linkers, M-start) and a **codon-optimized mRNA** (human high-frequency codons + Kozak + stop).

### Outputs
- `<id>_residue_scores.csv` (per-residue: all five scales + composite + is_epitope)
- `<id>_epitopes.csv` (ranked epitope regions: start/end/sequence/composite/antigenicity/hydrophilicity/surface)
- `<id>_summary.json`
- `bcell_epitopes_ranked.csv` (cross-antigen ranking)
- `immunogen_construct.json` (draft protein + mRNA + epitope provenance)
- `immunogen_summary.json`

### Honesty guards (critical)
- **Sequence propensity, NOT a trained SOTA (BepiPred-3.0/ESM) and NOT conformational (DiscoTope).** It maps *linear* epitope propensity only — a ranked shortlist to confirm by **ELISA / neutralization**, never a measured binding result. Stated in the header, every summary, and the catalog description.
- Scores are **computed, never fabricated**: a non-amino-acid sequence fails the task (exit 1) rather than inventing a track.
- The vaccine construct is a **computational DRAFT** (no signal peptide / adjuvant / UTRs / folding / immunogenicity validation).
- A structure-aware refinement (ESMFold + SASA for surface accessibility) is a stated future increment, not silently implied.

### Validation done
- Both embedded Python blocks `py_compile` clean and **run** on a demo antigen: 2 sensible linear epitopes called (`GPSSQT`, `GDRSNPEV` — hydrophilic/turn-rich exposed stretches), construct `MGPSSQTGPGPGGDRSNPEV` + 69-nt mRNA built correctly.
- `nextflow lint`: identical error profile to the live, dev-validated `mhc_binding_prediction` (the `import groovy.json.JsonSlurper` / `new JsonSlurper()` classic-parser pattern) — i.e. runtime-valid.
- FTS routing confirmed.

### Pending
- Run on dev against a real EBV antigen FASTA (gp350 neutralization domain) and confirm the epitope table + construct populate; the demo default is a clearly-labelled SYNTHETIC sequence, not a validated EBV antigen.

---

## 3. Next (by priority)
1. **This workflow on dev** against real EBV antigens; sanity-check epitopes vs known gp350 neutralizing regions.
2. **ESMFold + SASA** surface-accessibility refinement → conformational-aware epitope filtering (upgrades #2 developability path too).
3. **ESMFold / AntiBERTa antibody developability** (#2) — strengthens SYSUCC's current antibody/ADC/bispecific wave.
4. Class-II neoantigen remains gated (NetMHCIIpan); revisit if a redistributable class-II model matures.

External SYSUCC framing stays confident-but-true and firewalls the ACT / MD-Anderson status ([[project_sysucc_multisite_act]], [[feedback_bd_material_no_internal_hedging]]). Judge runs by real output, not a "completed" flag ([[project_nfcore_run_status_not_trustworthy]]).

Related: [[project_sysucc_modality_capability]] · [[project_drugdev_capability]] · [[reference_workflow_db_canonical]]
