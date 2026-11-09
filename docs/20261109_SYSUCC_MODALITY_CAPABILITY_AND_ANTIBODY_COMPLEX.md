# SYSUCC modality coverage audit + Boltz-2 antibody–antigen complex workflow

**Date:** 2026-11-09
**Context:** SYSUCC (Sun Yat-sen University Cancer Center) is a platform prospect. Its own modalities are PD-1/PD-L1 IO, antibody–drug conjugates (ADCs), bispecific antibodies, cell therapy (TCR-T / CAR-T / TIL), and EBV vaccines/antibodies/mRNA. This audits what BioMate actually has for those modalities, corrects an earlier over-harsh read of three modules, identifies SOTA gaps, and records the first SOTA addition built in response: a Boltz-2 antibody–antigen complex-prediction workflow.

This is an **internal** honest capability audit, not BD-facing copy. Several items are analytics-only or knowledge-base tools; those limits are stated plainly here and must not be dressed up externally (see [[feedback_bd_material_no_internal_hedging]] for how the external framing differs).

---

## 1. Coverage by SYSUCC modality (read from catalog + workflow sources)

| Modality | What BioMate has (real) | Nature |
|---|---|---|
| **Antibody** | `scfv_antibody_design` (scFv-pMPNN + AlphaFold2); `antibody_developability`, `fcrn_antibody_pk` (descriptor/PK analytics); `analyze_radiolabeled_antibody_biodistribution` | design (AF2-era) + analytics |
| **Bispecific** | `bispecific_antibody_design` | **honest stub** — refuses, prints the real tools it would need (CDR grafting, interface energetics, NetMHCII); emits nothing fabricated |
| **ADC** | `adc_design` | **real recommender** — curated payload/linker/DAR/bystander knowledge base with clinical precedent (MMAE→Adcetris, DM1→Kadcyla, DXd→Enhertu, SN-38→Trodelvy, PBD→Zynlonta, calicheamicin→Mylotarg); emits `design_recommendation` + `adc_summary.txt` |
| **CAR-T** | `cart_construct_design`, `in_vivo_cart_codesign` | **real assembler for catalog targets** — full CAR (GM-CSFR signal + scFv + CD8α hinge/TM + costim + CD3ζ) from real published domain sequences; honest placeholder + pointer to scFv design for novel antigens |
| **HLA / epitope / TCR** | `nf-core/hlatyping`, `nf-core/epitopeprediction` + `antigen_resolution` (NetMHCpan/NetMHCIIpan), `midashla`, `powertcr`, `immuneapp_hla_screen` | strongest area; NetMHC paths are **license-gated** (DTU tarball; executor already blocks unlicensed runs) |
| **EBV / vaccine / mRNA** | `analyze_ebv_antibody_titers` (titers), `p0_mrna_validation` + RNA-seq | **thinnest vs. a stated SYSUCC strength** — no real immunogen / mRNA-construct / B-cell-epitope design |
| **Peptide (our own αvβ6/PD-L1 lead)** | `cyclic_peptide_cofold` (Boltz-2), `amber_peptide_mmgbsa`, `peptide_mmgbsa`, cyclic-LLM research program | Boltz uses an **L-backbone approximation** — cannot express ncAA / D-residues / N-methylation, the chemistry that makes macrocycles drug-like |

### Correction to an earlier read
`adc_design`, `cart_construct_design` and `in_vivo_cart_codesign` were first flagged "suspect (placeholder?)". On reading them in full they are **real knowledge-base tools**, not fabrication stubs: real linker/payload/DAR precedent (ADC) and real published scFv + CAR domain sequences for CD19 (FMC63, Kymriah/Yescarta), CD22, BCMA, CD33, GD2, HER2, EGFR, MSLN, CD7, PSMA, FOLR1 with 4-1BB/CD28 costim. For targets outside the library they insert a labelled placeholder and route to scFv design — honest, not fabricated. The defensible line: **for known CAR/ADC targets we produce a real, literature-grounded construct/recommendation**; de-novo design against a novel antigen is the honest gap.

---

## 2. SOTA gaps, ranked by SYSUCC fit

1. **Antibody structure + design** — AF3 / Boltz-2 complex prediction, and RFantibody / IgDesign for CDR design. Makes `bispecific_antibody_design` real and upgrades scFv beyond AF2. Highest leverage: antibodies/ADCs/bispecifics are SYSUCC's entire current wave. **→ first increment built, see §3.**
2. **ESMFold / ESM-2 + AntiBERTa/BALM** — fast antibody folding and liganded developability/immunogenicity, replacing the descriptor-only developability path.
3. **Peptide macrocycle folding** — HighFold / AfCycDesign for head-to-tail cyclization + ncAA, closing the Boltz L-backbone gap for our own lead.
4. **License-free MHC-II / neoantigen** — MHCflurry 2 / BigMHC / TransPHLA alongside the gated NetMHC, so the cell-therapy/epitope path runs without the DTU license.
5. **EBV / immunogen** — the real build (B-cell epitope + mRNA construct design), not a model swap.

---

## 3. Built: `drug_discovery/antibody_antigen_complex` (Boltz-2)

**File:** `backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/antibody_antigen_complex/main.nf`
**Registered:** workflows DB id 14665, name "Antibody Antigen Complex", FTS rebuilt.
**Container:** the existing Boltz-2 GPU image shared with `cyclic_peptide_cofold` / `boltz_structure_prediction` (`biomate/ai-tools/boltz:latest`; ECR on AWS) — no new image needed.

### What it does
Predicts the antibody Fv–antigen 3D complex for each antibody and reports Boltz-2's own **interface confidence** as the binding-interface readout. It is the structure-prediction primitive the antibody / bispecific / CAR-ADC-binder paths were missing.

- **Inputs:** `params.antibodies` = JSON list `[{id, vh, vl?}]`; `params.antigen_chains` = JSON map `{label: sequence}` (1+ antigens); `params.target` (label); `params.outdir`.
- **Fan-out:** one `FOLD_COMPLEX` GPU task per antibody (`Channel.fromList` → parallel on AWS Batch), the same parallelism pattern as `cyclic_peptide_cofold`. Labelled `process_gpu`.
- **Covers:** monospecific antibody / scFv (VH+VL), nanobody / VHH / single-domain (VH only), and bispecific arms (two antigens, each interface scored separately).
- **Outputs:** predicted complex CIF(s); Boltz `confidence_*.json`; per-antibody `<id>_complex.json` with `complex_iptm`, `complex_plddt`, and `interface_iptm` = antibody↔antigen `pair_chains_iptm` for each antigen (plus `best_interface_iptm`).

### Method notes / honesty guards
- `pair_chains_iptm` is indexed by **0-based chain position** (string), not chain id — confirmed against `research/guangzhou_all_atom/multitarget/cyclic_complex_benchmark/scripts/scoring.py`. The summary maps antibody vs antigen chains by the YAML order it writes (`chain_order.json`) and takes `interface_iptm` = max over antibody positions of `max(pc[i][ag], pc[ag][i])`.
- Confidence is **Boltz's own**, never fabricated — null when Boltz does not emit it; `status="no_structure"` when no CIF is produced.
- `interface_iptm` is a **binding-interface confidence, not an affinity**. The model is the Fv variable domains only (no constant region, glycans, or ncAA).
- Boltz run flags carried over from the cyclic workflow's hard-won corrections: `--no_kernels` (cuequivariance kernel ImportError without it) and `--use_msa_server` (single-seq folds error without an MSA).

### Why this first
It upgrades three SYSUCC-relevant paths at once with an image we already ship: scFv (beyond AF2), a real bispecific (two-arm interface scoring), and the CAR/ADC binder-validation step. It does not touch the honest ADC/CAR knowledge-base tools, which stay as they are.

### Validation done / pending
- **Done (static):** `nextflow lint` shows only the file's pre-existing strict-syntax classes (the `import groovy.json.JsonSlurper` warning is identical to the known-good `cyclic_peptide_cofold`); both embedded Python blocks parse after Groovy-escape rendering.
- **Pending (runtime):** not yet executed on dev. First real run should fold a known antibody–antigen pair (e.g. an anti-HER2 Fv vs the HER2 ECD fragment) and confirm `interface_iptm` is populated and the CIF is emitted. Deploy carries the `.nf` (workflows layer) and the DB row (db layer — the DB is gitignored, synced by md5, so this sync uploads the ~300 MB DB once).

---

## 4. Open / next

- Run `antibody_antigen_complex` on dev against a known pair; confirm interface readout.
- Then, by priority: a license-free MHC-II predictor (#4) for the cell-therapy/epitope path, and macrocycle folding (#3) for our own peptide lead.
- EBV/immunogen (#5) is a genuine build, scoped separately.
- External SYSUCC framing: lead with HLA/epitope/TCR + antibody developability/PK analytics + structure prediction as live; design is roadmap. Do **not** present the stubs/placeholders as live, and keep the ACT / MD-Anderson-status firewall ([[project_sysucc_multisite_act]]).

Related: [[project_sysucc_multisite_act]] · [[project_drugdev_capability]] · [[reference_workflow_db_canonical]] · [[project_md_workflows_status]]
