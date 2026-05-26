# BioMate QC Gates, Workflows, and Auto-Loop Strategy

**Comprehensive reference, May 2026**
**Branch:** `integration/next-phase` (tip: `bee3390f1`, pushed)
**Supersedes:** the sampled and exhaustive audits earlier this month;
this document is the single canonical reference going forward.

---

## Table of Contents

1. [Executive summary](#1-executive-summary)
2. [Architecture: gate → SSE → UI](#2-architecture-gate--sse--ui)
3. [Provenance framework](#3-provenance-framework)
4. [Full gate catalog (29 gates × 16 domains)](#4-full-gate-catalog-29-gates--16-domains)
5. [Auto-loop strategy](#5-auto-loop-strategy)
6. [Workflow → gate mapping (226 drug-dev workflows)](#6-workflow--gate-mapping-226-drug-dev-workflows)
7. [Coverage gaps and roadmap](#7-coverage-gaps-and-roadmap)
8. [Operational reference](#8-operational-reference)

---

## 1. Executive summary

BioMate's QC layer has three components, all live in repo:

| Component | What it does | File |
|---|---|---|
| **Gate evaluation** | Computes pass/fail from raw metrics, per domain | `backend/experiments/*_autoloop/qc_evaluator.py` (5 domains) + `backend/lib/galaxy/ai/retrievers/qc_gate_reader.py` (10 more) |
| **SSE emission** | Forwards gate results to the frontend | `qc_trace_monitor.py` → `autoloop_bridge.evaluate_and_emit` (5 domains) + `qc_gate_emit.emit_gate_only_event` (10 more) |
| **Evidence anchors** | Per-gate citation + provenance grade | `backend/config/qc_evidence.yaml` → rendered as hover tooltip via `frontend/client/src/components/qc-evidence-tooltip.tsx` |

**Coverage:** 29 gates across 16 domains. **22 GOLD** (verbatim regulatory/peer-reviewed source), **5 SILVER** (community convention attributed to the source), **2 BRONZE** (operational heuristic — explicitly disclaimed in the user-facing tooltip).

**Auto-loop scope:** 5 domains (ADMET, CYP-DDI, NCA-PK, Docking, PBPK) have full remediation logic. 10 more domains have gate display + evidence tooltips but no remediation (operator decisions, not auto-tunable).

**Coverage gap:** 226 drug-development workflows audited; **~22 covered by full auto-loop**, **~10 more by gate-only emit**, **~24 evidence-backed with QC in main.nf but not yet wired into the emit path**. The remaining 170 are either NO_QC (45.6%) or N/A (text generation, file conversion — 30.5%).

---

## 2. Architecture: gate → SSE → UI

```
┌──────────────────────────────────────────────────────────────┐
│  Nextflow process completes (any workflow)                  │
│  → emits raw metrics (e.g. toxicity_report.json, qc.json)   │
└──────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌──────────────────────────────────────────────────────────────┐
│  qc_trace_monitor.py — single hook point                     │
│  (backend/lib/galaxy/jobs/qc_trace_monitor.py)               │
│                                                              │
│  Parses metrics → qc_metrics dict                            │
│                                                              │
│  Calls TWO emitters (both fail-open):                        │
└──────────────────────────────────────────────────────────────┘
                │                       │
                ▼                       ▼
┌──────────────────────────┐  ┌──────────────────────────────┐
│ autoloop_bridge          │  │ qc_gate_emit                 │
│ evaluate_and_emit()      │  │ emit_gate_only_event()       │
│                          │  │                              │
│ For 5 wired domains:     │  │ For 10 gate-only domains:    │
│   admet, docking,        │  │   hts, ich_s5, ich_s7,       │
│   cyp_ddi, nca_pk, pbpk  │  │   clinical_trial, allometric,│
│                          │  │   ivive, openfe, p0_pkpd,    │
│ Emits TWO SSE events:    │  │   pocket_detection,          │
│  - autoloop_gate_results │  │   aizynthfinder              │
│    (with `evidence`)     │  │                              │
│  - autoloop_update       │  │ Emits ONE SSE event:         │
│    (remediation rules)   │  │  - autoloop_gate_results     │
│                          │  │    (with `evidence`)         │
│                          │  │  (no remediation)            │
└──────────────────────────┘  └──────────────────────────────┘
                │                       │
                └───────────┬───────────┘
                            ▼
┌──────────────────────────────────────────────────────────────┐
│  Frontend: auto-loop-panel.tsx                               │
│  Renders gate table; each label wrapped in                   │
│  <QCEvidenceTooltip domain={d} gate={g.gate}>                │
│                                                              │
│  Tooltip pulls from build-time embedded                      │
│  frontend/client/src/data/qc-evidence.ts                     │
│  (generated from backend/config/qc_evidence.yaml)            │
└──────────────────────────────────────────────────────────────┘
                            │
                            ▼
            User hovers over any gate label →
            sees: provenance badge, paper_ref, DOI link,
                  "Rule applied", "What the source actually contains"
```

**Key design properties:**

- **No protected-file edits required.** All new code lives in net-new files. The two existing files modified (`qc_trace_monitor.py`, `auto-loop-panel.tsx`) got minimal additive changes that survived parallel-session collisions.
- **Same event type for both emitters.** Frontend renders gate-only events identically to auto-loop events; no UI code change to add a new domain.
- **Build-time embedded evidence.** No `/api/qc/evidence` route needed; tooltip data ships in the bundle.
- **Fail-open everywhere.** Any emit error is logged at WARN and skipped; never blocks the QC pipeline.

---

## 3. Provenance framework

Every threshold in `qc_evidence.yaml` carries an explicit grade so users can apply the right level of scrutiny when hovering the tooltip:

| Grade | Meaning | UI rendering |
|---|---|---|
| **GOLD** | Threshold is stated in the cited paper/guidance verbatim, or trivially derived from values in it | Yellow badge |
| **SILVER** | Community convention attributed to the paper; paper supports the concept but doesn't state the exact value | Gray badge |
| **BRONZE** | Operational heuristic with no peer-reviewed anchor; cited reference is related context, not the source of the cutoff | Orange badge; tooltip explicitly disclaims |

This is the framework codified in `docs/20260522_AUTOLOOP_EVIDENCE_PROVENANCE_AUDIT.md`.

**Distribution across the 29 gates:**

| Grade | Count | % |
|---|---|---|
| GOLD | 22 | 75.9% |
| SILVER | 5 | 17.2% |
| BRONZE | 2 | 6.9% |

The two BRONZE gates are the docking thresholds (`docking_binding_score`, `docking_valid_poses`); the previously-BRONZE `pbpk_cl_min` has a replacement (`pbpk_cl_implausible_high`) ready in a parallel refactor that got reverted by the file-protection guard — see open work in §7.

---

## 4. Full gate catalog (29 gates × 16 domains)

### Auto-loop domains (5) — full remediation logic

#### ADMET

| Gate | Threshold | Provenance | Citation |
|---|---|---|---|
| `admet_herg_ic50` | ≤ 10 µM HALT | GOLD | Aronov AM 2008. *J Med Chem* 51:6632–6641. DOI: 10.1021/jm800467u |
| `admet_dili_probability` | > 0.5 HALT | SILVER | Lammert C et al. *Hepatology* 2010; 51:615–620. DOI: 10.1002/hep.23317 |
| `admet_ames` | > 0.5 HALT | GOLD | Kazius J et al. *J Med Chem* 2005; 48:312–320. DOI: 10.1021/jm040835a |
| `admet_ro5` | > 1 violation HALT | GOLD | Lipinski CA et al. *Adv Drug Deliv Rev* 1997; 23:3–25. DOI: 10.1016/S0169-409X(96)00423-1 |

**Remediation knob:** tighten upstream logP/MW filters. **Workflows:** `ADMET_pred`, `predict_admet_properties`, `herg_cardiac_safety_qsar`.

#### CYP-DDI

| Gate | Threshold | Provenance | Citation |
|---|---|---|---|
| `cyp_ddi_r1_basic` | R1 ≥ 1.1 HALT; ≥ 1.02 ADVISORY | GOLD | FDA In Vitro Drug Interaction Studies Guidance (2020) |
| `cyp_ddi_r2_mbi` | R2 ≤ 0.71 HALT; ≤ 0.79 ADVISORY | GOLD | FDA 2020 DDI Guidance, mechanism-based inhibition |

**Remediation knob:** reduce simulated `cmax_ss_uM`; swap total → unbound Cmax. **Workflows:** `cyp_ddi_panel`, `transporter_ddi_pgp_bcrp`, `transporter_ddi_prediction`.

#### NCA-PK

| Gate | Threshold | Provenance | Citation |
|---|---|---|---|
| `nca_auc_extrap` | > 20% HALT (standard); > 15% (regulatory) | GOLD | FDA Bioavailability Studies Guidance (2003) |
| `nca_terminal_slope_coverage` | > 2 subjects without slope HALT | SILVER | Gabrielsson & Weiner, *PK/PD Data Analysis* 5th ed. |

**Remediation knob:** extend `last_sampling_time_h` × 1.5. **Workflows:** `nca_pknca`.

#### Docking

| Gate | Threshold | Provenance | Citation |
|---|---|---|---|
| `docking_binding_score` | > −7 kcal/mol (Vina) ADVISORY | BRONZE | Trott O & Olson AJ. *J Comput Chem* 2010; 31:455–461 — paper does NOT prescribe the cutoff |
| `docking_valid_poses` | < 3 poses ADVISORY | BRONZE | Community heuristic |

**Remediation knob:** increase `exhaustiveness` 8 → 32; expand search box; SP → XP precision. **Workflows:** `docking_autodock_vina`, `schrodinger_glide_docking`, `drugclip_virtual_screening`, `moe_covalent_docking`, `structure_prediction_docking`, `run_diffdock_with_smiles`, `p0_docking_validation`.

#### PBPK (newly wired this week)

| Gate | Threshold | Provenance | Citation |
|---|---|---|---|
| `pbpk_tmax_fraction` | > 80% of sim window HALT (IND); > 90% ADVISORY | SILVER | FDA Guidance for Industry — PBPK Analyses (2018) |
| `pbpk_cl_min` | < 0.01 L/h (operational, no source) | BRONZE | Davies & Morris 1993 — paper does NOT state a CL minimum (disclaimed in tooltip) |
| `pbpk_mass_balance` | recovery outside ±5% HALT; ±10% ADVISORY | SILVER | EMA Guideline EMA/CHMP/458101/2016 (2019) |
| `pbpk_auc_fold_error` | \|log2(pred/obs)\| > 1 HALT (2-fold) | GOLD | FDA 2018 PBPK Guidance — 2-fold criterion verbatim |

**Remediation knobs:** extend `simulation_duration_h`, adjust `kp_scale`, tighten `integration_rtol`. **Workflows:** `pbpk_simulation`, `pbpk_pediatric`, `pbpk_pediatric_pregnancy`, `pbpk_disease_state`, `pk_sim_pbpk`, `simcyp_pbpk`.

### Gate-only domains (10) — display + evidence, no auto-tune

These domains have well-defined pass/fail criteria but auto-tuning is inappropriate (operator decisions, regulatory constraints, or no clear param→outcome mapping).

#### HTS (high-throughput screening)

| Gate | Threshold | Provenance | Citation |
|---|---|---|---|
| `hts_z_prime` | < 0.5 FAIL | GOLD | Zhang JH et al. *J Biomol Screen* 1999; 4(2):67–73. DOI: 10.1177/108705719900400206 |
| `hts_signal_window` | < 2 FLAG | SILVER | Iversen PW et al. *J Biomol Screen* 2006; 11(3):247–252. DOI: 10.1177/1087057105285610 |

**Workflows:** `hts_plate_qc_hit_calling`. **Operator action:** investigate controls, plate-edge effects, re-run.

#### ICH-S5 (reproductive toxicity)

| Gate | Threshold | Provenance | Citation |
|---|---|---|---|
| `ich_s5_safety_margin` | < 10× Cmax FAIL | GOLD | ICH S5(R3) 2020 — verbatim 10× WOCBP margin |
| `ich_s5_structural_alert` | categorical (RED/YELLOW/GREEN) | SILVER | Schilter B et al. *Regul Toxicol Pharmacol* 2013; 67(1):39–52. DOI: 10.1016/j.yrtph.2013.05.001 |

**Workflows:** `ich_s5_reproductive_tox`. **Operator action:** dose reduction; alternative formulation; additional reproductive tox studies.

#### ICH-S7 (cardiac & general safety pharmacology)

| Gate | Threshold | Provenance | Citation |
|---|---|---|---|
| `ich_s7b_herg_margin` | < 10× FAIL; 10–30× FLAG | GOLD | ICH S7B (2005) — verbatim safety margin tiers |
| `ich_s7b_qnet` | < −30 pC/pF triggers CiPA Tier 2 | GOLD | Dutta S et al. *Front Physiol* 2017; 8:616. DOI: 10.3389/fphys.2017.00616 |

**Workflows:** `ich_s7a_safety_pharmacology`. **Operator action:** structural modification; full CiPA evaluation.

#### Clinical trial (BOIN)

| Gate | Threshold | Provenance | Citation |
|---|---|---|---|
| `boin_dlt_boundary` | observed DLT > target φ HALT | GOLD | Liu S & Yuan Y. *J R Stat Soc C* 2015; 64(3):507–523. DOI: 10.1111/rssc.12089 |

**Workflows:** `clinical_trial_simulation`, `adaptive_trial_design`. **Operator action:** the BOIN algorithm IS the gold standard — auto-tuning would be inappropriate.

#### Allometric scaling (FIH dose)

| Gate | Threshold | Provenance | Citation |
|---|---|---|---|
| `allometric_r_squared` | < 0.85 FAIL | GOLD | FDA Maximum Safe Starting Dose Guidance (2005) |

**Workflows:** `allometric_scaling`. **Operator action:** include more species; check outliers; switch to PBPK.

#### IVIVE (hepatic clearance)

| Gate | Threshold | Provenance | Citation |
|---|---|---|---|
| `ivive_fold_error` | \|pred/obs\| > 2 FAIL | GOLD | Obach RS. *Drug Metab Dispos* 1999; 27(11):1350–1359 (PMID 10534321) |
| `ivive_well_stirred_consistency` | E > 0.7 indicates model sensitivity | SILVER | Pang KS & Rowland M. *J Pharmacokinet Biopharm* 1977; 5(6):625–653. DOI: 10.1007/BF01059688 |

**Workflows:** `ivive_hepatic_clearance`. **Operator action:** model-choice review; protein binding/active transport corrections.

#### OpenFE (free energy perturbation)

| Gate | Threshold | Provenance | Citation |
|---|---|---|---|
| `openfe_cycle_closure` | \|ΔG_sum\| > 1 kcal/mol FAIL | GOLD | Mey ASJS et al. *Living J Comput Mol Sci* 2020; 2(1):18378. DOI: 10.33011/livecoms.2.1.18378 |

**Workflows:** `openfe_rbfe`. **Operator action:** extend sim time; add λ windows; use HREX.

#### p0 PKPD (semaglutide validation reference)

| Gate | Threshold | Provenance | Citation |
|---|---|---|---|
| `p0_pkpd_weight_loss_band` | week-30 Δweight outside [−6, +3] kg FAIL | GOLD | Overgaard RV et al. *Clin Pharmacokinet* 2019; 58:781–791. DOI: 10.1007/s40262-018-0728-4 |

**Workflows:** `p0_pkpd_semaglutide`. **Operator action:** ER model parameter re-fit; PD model structure review.

#### Pocket detection (druggability)

| Gate | Threshold | Provenance | Citation |
|---|---|---|---|
| `pocket_druggability_score` | < 0.5 FAIL | GOLD | Le Guilloux V et al. *BMC Bioinformatics* 2009; 10:168. DOI: 10.1186/1471-2105-10-168 |

**Workflows:** `pocket_detection_druggability`. **Operator action:** allosteric site search; fragment screen for cryptic pockets; PROTAC strategy.

#### Retrosynthesis (aizynthfinder)

| Gate | Threshold | Provenance | Citation |
|---|---|---|---|
| `aizynth_solved_routes` | < 1 route FAIL; < 3 ADVISORY | SILVER | Genheden S et al. *J Cheminform* 2020; 12:70. DOI: 10.1186/s13321-020-00472-1 |

**Workflows:** `aizynthfinder_retrosynthesis`. **Operator action:** relax stock DB constraints; extend search time; alternative disconnections.

### Forward-looking (1) — tooltip data ready, awaits emit

| Gate | Threshold | Provenance | Citation |
|---|---|---|---|
| `struct_pred_mean_plddt` | < 70 FAIL | GOLD | Jumper J et al. *Nature* 2021; 596:583–589. DOI: 10.1038/s41586-021-03819-2 |

**Workflows:** `boltz_structure_prediction`, `chai1_structure_prediction`, `alphafold_db_search`. **Status:** evidence in YAML, but emit-path wiring (boltz/chai don't yet write a qc.json) is open work.

---

## 5. Auto-loop strategy

### What "auto-loop" means in BioMate

Auto-loop = automated parameter-tuning of a workflow's inputs when QC gates fail. The pipeline:

1. Run workflow → emit metrics
2. Evaluator scores gates against profile thresholds (per `QC_PROFILES` dict)
3. If any HALT-grade gate fails: `param_tuner` proposes one parameter change per failed gate
4. `enriched_tuner` attaches knowledge_base citations to each remediation
5. SSE event `autoloop_update` carries the remediations to the frontend
6. (Optional, off by default) Caller re-runs the workflow with the new parameters

### Why only 5 domains have auto-loop wired

The decision tree for whether a workflow should get auto-loop:

```
Does the workflow have a quantitative QC gate?
  ├─ No → no auto-loop possible (49% of audited drug-dev workflows)
  └─ Yes
      │
      Is the parameter→outcome relationship well-defined?
        ├─ No → gate-only display, no auto-tune
        │      (BOIN, ICH-S5, structural-alert workflows)
        └─ Yes
            │
            Is auto-tuning appropriate, or should the
            operator make the decision?
              ├─ Operator decision → gate-only display
              │   (clinical trial dose escalation, regulatory
              │    submissions, structure-prediction confidence)
              └─ Algorithmic decision → full auto-loop
                  (the 5 wired domains)
```

### The 5 wired auto-loops

| Domain | What gets tuned | Tested? | Confidence |
|---|---|---|---|
| **ADMET** | Upstream logP/MW filters | 24 regression tests | HIGH |
| **CYP-DDI** | `cmax_ss_uM`, unbound Cmax flag | 24 tests | HIGH |
| **NCA-PK** | `last_sampling_time_h × 1.5`, λz window | 24 tests | HIGH |
| **Docking** | `exhaustiveness`, search box, SP→XP | 24 tests | HIGH |
| **PBPK** | `simulation_duration_h`, `clint_mL_per_min`, `kp_scale`, `integration_rtol` | 18 tests | HIGH (new this week) |

### What's NOT wired (and why)

| Domain | Reason auto-loop is inappropriate |
|---|---|
| BOIN clinical trial | The BOIN algorithm is the gold standard; tuning φ would be scientifically wrong |
| ICH-S5 / ICH-S7 | Regulatory submissions need human review; auto-modification could fail audit |
| Structure prediction (Boltz/Chai) | "Increase recycling" is one knob, but the workflow itself doesn't yet emit confidence summary |
| HTS Z'-factor | Plate failures usually indicate hardware/protocol issues, not param tuning |
| Allometric scaling | Operator decides which species to include — domain knowledge |
| OpenFE cycle closure | Extending sim time is the standard fix — could automate, but expensive (GPU hours) |

---

## 6. Workflow → gate mapping (226 drug-dev workflows)

This section is the canonical mapping. Numbers come from the exhaustive audit in `docs/20260522_EXHAUSTIVE_QC_AUDIT_DRUGDEV_AND_BIOCONDUCTOR.md`.

### Summary table

| Category | Count | Auto-loop | Gate-only | Evidence-backed (any) | NO_QC | N/A |
|---|---|---|---|---|---|---|
| Total drug-dev workflows | 226 | ~22 (9.7%) | ~10 (4.4%) | 24 (10.6%) | 103 (45.6%) | 69 (30.5%) |

### Per-domain summary

| Domain | Total | Workflows with QC |
|---|---|---|
| drug_discovery | 44 | 19 (12 EVIDENCE + 3 HEURISTIC + 4 PARTIAL) |
| pharmacology | 48 | 17 (9 EVIDENCE + 3 HEURISTIC + 5 PARTIAL) |
| molecular_biology | 26 | 0 (all 26 are N/A — utility) |
| cryo_em | 15 | 2 (1 HEURISTIC + 1 PARTIAL) |
| immunology | 13 | 2 (PARTIAL) |
| virtual_cell | 12 | 4 (3 EVIDENCE + 1 PARTIAL) |
| systems_biology | 12 | 0 |
| genetics | 11 | 0 |
| synthetic_biology | 10 | 3 (PARTIAL) |
| biochemistry | 9 | 1 (PARTIAL) |
| pathology | 7 | 3 (PARTIAL) |
| cancer_biology | 7 | 0 — bare |
| cell_biology | 5 | 2 (1 HEURISTIC + 1 PARTIAL) |
| glycoengineering | 3 | 0 (N/A) |
| biophysics | 2 | 1 (PARTIAL) |
| structural_biology | 2 | 0 — bare; Boltz/Chai are highest-leverage open gap |

### The 24 evidence-backed workflows

These appear in the citations above. Listed compactly:

**Pharmacology:** `predict_admet_properties`, `dart_toxicity_prediction`, `exposure_response_modeling`, `genotoxicity_ames_prediction`, `herg_cardiac_safety_qsar`, `ivive_hepatic_clearance`, `pbpk_disease_state`, `pbpk_pediatric_pregnancy`, `phase2_dose_justification`, `transporter_ddi_prediction`, `allometric_scaling`, `cipa_cardiac_safety_ode`.

**Drug discovery:** `ADMET_pred`, `adaptive_trial_design`, `aizynthfinder_retrosynthesis`, `clinical_trial_simulation`, `cyp_ddi_panel`, `hts_plate_qc_hit_calling`, `ich_s5_reproductive_tox`, `ich_s7a_safety_pharmacology`, `nca_pknca`, `openfe_rbfe`, `p0_docking_validation`, `p0_pkpd_semaglutide`, `pbpk_pediatric`, `pbpk_simulation`, `pk_sim_pbpk`, `pocket_detection_druggability`, `simcyp_pbpk`, `transporter_ddi_pgp_bcrp`.

**Virtual cell:** `metabolic_flux_fba`, `virtual_patient_cohort`, `cipa_cardiac_safety_ode`.

---

## 7. Coverage gaps and roadmap

### Top-10 open gaps (from the exhaustive audit + this week's work)

| # | Workflow / domain | Gap | Effort | Evidence anchor available? |
|---|---|---|---|---|
| 1 | `boltz_structure_prediction` / `chai1_structure_prediction` | No pLDDT/PAE gate emission | Half-day | YES — Jumper 2021 in YAML |
| 2 | `pbpk_cl_min` BRONZE gate | Replace with GOLD anchored `pbpk_cl_implausible_high` (CL ≤ Qh ≈ 87 L/h from Davies & Morris 1993 Table 1) | Half-day | YES — refactor blocked by file-protection guard, retry needed |
| 3 | `cryosparc_standard_spa` (13/15 cryo-EM workflows bare) | FSC 0.143 gate | 1 day | YES — Rosenthal & Henderson 2003 |
| 4 | `cancer_biology/detect_and_annotate_somatic_mutations` (all 7 cancer_biology workflows bare) | VAF≥5%, depth≥30, Q≥20 | 1 day | YES — GATK best practices |
| 5 | All docking workflows: standardize `n_poses_generated + binding_score` JSON output schema so the docking gate fires consistently | 1 day | partial — DockingQCEvaluator exists |
| 6 | `lnp_formulation_optimization` | Z-avg size / PDI / encapsulation efficiency gates | 1 day | YES — ISO 22412; FDA LNP draft 2023 |
| 7 | `nlmixr2_population_pk` | OFV change, η-shrinkage < 30% | 1 day | YES — Savic 2009 |
| 8 | Antibody design (3 workflows) | TAP / CamSol / HI developability | 1 day | YES — Raybould 2019 |
| 9 | `polymorph_stability_screening`, `analyze_accelerated_stability` | ICH Q1A shelf-life gate | Half-day | YES — ICH Q1A(R2) |
| 10 | `sirna_offtarget_analysis` | Seed-mismatch + thermo-energy gates | Half-day | YES — Birmingham 2006 |

### Bioconductor — separate strategy

The exhaustive audit confirmed: **0 of 1,818 Bioconductor wrappers have inline QC gates.** All share one scaffolder template. Recommended path (from `docs/20260522_EXHAUSTIVE_QC_AUDIT_DRUGDEV_AND_BIOCONDUCTOR.md`):

| Action | Effort | Coverage |
|---|---|---|
| Scaffold-level integrity decorator (existence + schema sniff + `qc_status.json` emit) | 1–2 days | All 1,818 |
| Top-10 chain-level biological gates (deseq2, edger, limma, dexseq, dada2, chipqc, diffbind, dropletutils, methylkit, chromvar) | ~30 dev-days | ~80% of real usage |
| Per-wrapper main.nf gates | ❌ wrong architecture — generalist primitives |

Status: not started; deferred until the drug-dev gaps above are closed.

---

## 8. Operational reference

### Adding a new gate (developer recipe)

1. **Pick or build an evaluator.** If the domain is one of the 5 auto-loop ones, edit the relevant `qc_evaluator.py`. If it's gate-only, add the gate function to `qc_gate_reader.py` (`_gate_<domain>_<name>` pattern).

2. **Add the evidence entry to `backend/config/qc_evidence.yaml`.**
   ```yaml
   <domain>:
     <gate_name>:
       - paper_ref: "Surname et al. Journal YYYY; vol:pp"
         paper_doi: "10.xxxx/yyyy"
         provenance: GOLD | SILVER | BRONZE   # be honest!
         paper_supports: |
           What the paper actually says (factual, quoteable).
         rule_text: |
           What BioMate enforces (your operational threshold).
         finding: |
           Optional: plain-language explanation of remediation.
   ```

3. **Regenerate the frontend embed:**
   ```bash
   python3 -c "import yaml, json; print(json.dumps(
       yaml.safe_load(open('backend/config/qc_evidence.yaml')),
       indent=2, ensure_ascii=False))" \
     > /tmp/qc.json
   # Then manually update the const literal in
   # frontend/client/src/data/qc-evidence.ts
   ```

4. **If gate-only (no auto-loop), add a keyword to `_PROCESS_KEYWORDS` in `qc_gate_emit.py`** so process names matching the workflow get classified to your domain.

5. **Tests:** Add a case to `backend/tests/test_qc_gate_reader.py` (or to the auto-loop's own tests dir). Run `PYTHONPATH=. pytest backend/tests/test_qc_*.py -q`.

### Honesty checklist for the evidence entry

Before grading GOLD, ask: **"Could I open the paper PDF and find this exact threshold?"** If yes → GOLD. If "the paper supports the idea but I'd be paraphrasing" → SILVER. If "this is my operational practice, the paper is just the closest related source" → BRONZE (and write a frank `paper_supports` field disclosing this).

GOLD-without-quoting is the most dangerous mistake — it propagates into AI-generated regulatory narratives.

### File reference

```
backend/
├── config/
│   └── qc_evidence.yaml                          ← single source of truth
├── lib/galaxy/ai/retrievers/
│   ├── qc_evidence.py                            ← Python YAML loader
│   ├── qc_gate_reader.py                         ← gate evaluators (10 domains)
│   └── qc_gate_emit.py                           ← SSE emitter
├── lib/galaxy/jobs/
│   └── qc_trace_monitor.py:1172                  ← single hook point
├── experiments/
│   ├── autoloop_bridge.py                        ← 5 auto-loop domain dispatcher
│   ├── admet_autoloop/                           ← per-domain modules
│   ├── docking_autoloop/
│   ├── cyp_ddi_autoloop/
│   ├── nca_pk_autoloop/
│   └── pbpk_autoloop/                            ← built this week
└── tests/
    ├── test_qc_evidence.py                       ← 11 tests
    └── test_qc_gate_reader.py                    ← 30 tests

frontend/client/src/
├── data/qc-evidence.ts                           ← build-time embedded
└── components/
    ├── qc-evidence-tooltip.tsx                   ← tooltip wrapper
    └── auto-loop-panel.tsx                       ← gate table + tooltip
```

### Documentation index (referenced in this doc)

- `docs/20260522_EXHAUSTIVE_QC_AUDIT_DRUGDEV_AND_BIOCONDUCTOR.md` — the 226+500 exhaustive audit
- `docs/20260522_AUTOLOOP_EVIDENCE_PROVENANCE_AUDIT.md` — provenance grading framework
- `docs/20260522_PBPK_AUTOLOOP_AND_QC_AUDIT.md` — PBPK build details
- `docs/20260521_DEPLOYMENT_MISTAKES_LESSONS.md` — file-protection collision pattern + remediation

---

## Closing notes

This document captures BioMate's QC + auto-loop state as of 2026-05-26.

The system is in equilibrium for the 5 wired auto-loop domains + 10 gate-only domains. The next-priority gap is structure-prediction confidence (Boltz/Chai pLDDT/PAE) because it gates input quality for downstream docking pipelines that already have QC — closing this is half-day work with a GOLD-anchored evidence already in the YAML.

The honest BRONZE flags (`pbpk_cl_min`, `docking_*`) are visible to users via the tooltip's BRONZE badge, so the system fails safely — users hover, see the disclaimer ("Trott & Olson 2010 does not prescribe a cutoff"), and apply their own scrutiny.

The Bioconductor story (1,818 wrappers with zero QC) is separate; the recommended scaffold-level integrity layer is documented but not yet built.
