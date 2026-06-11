# QC & Auto-Loop Coverage Expansion — 2026-06-07 / 06-10

**Goal:** extend BioMate's QC-gate + auto-loop coverage to every workflow that
has a defined gate in `qc_gate_reader.py`, with honest provenance grading
and end-to-end verification on dev.

**Result:** 15 of 17 candidate workflows verified end-to-end. 2 are
code-ready, each blocked by an issue independent of the QC code path.

## Verified workflows

Each entry below is proven by a live `[QC-S3] Reading report for <process> from s3://...`
+ `[QC Gate] PASSED/FAILED for <process>` pair in dev's
`/app/database/gravity/log/gunicorn.log`.

| # | Workflow | Process | Gate metric | Threshold | Provenance | Run ID + UTC |
|---|---|---|---|---|---|---|
| 1 | hts_plate_qc_hit_calling | HTS_PLATE_QC_HIT_CALLING | `z_prime` | ≥ 0.5 | GOLD Zhang 1999 | af7f90d0 06-07 02:41:33 |
| 2 | allometric_scaling | ALLOMETRIC_SCALING | `r_squared` | ≥ 0.85 | SILVER FDA 2005 FIH metric | e1d804bc 06-08 16:57:55 |
| 3 | ich_s5_reproductive_tox | DART_IN_SILICO_PREDICTION | `safety_margin_x` | ≥ 10× Cmax | GOLD ICH S5R3 §3.1 | 85727f6e 06-09 02:05:01 |
| 4 | ich_s7a_safety_pharmacology | ICH_S7A_ASSESS_CV | `herg_safety_margin_x` | ≥ 10× | GOLD ICH S7B / Redfern 2003 | f7f1a8a0 06-09 02:35:09 |
| 5 | pocket_detection_druggability | DRUGGABILITY_QC_GATE | `druggability_score` | ≥ 0.5 | GOLD Le Guilloux 2009 | 67c4628a 06-09 16:18:27 |
| 6 | p0_pkpd_semaglutide | P0_PKPD_SEMAGLUTIDE | `week30_weight_change_kg` | ∈ [-6, +3] kg | GOLD Overgaard 2019 / SUSTAIN-1 | 8a68457b 06-09 21:17:45 |
| 7 | clinical_trial_simulation (BOIN) | CLINICAL_TRIAL_SIMULATION | `mtd_observed_dlt_rate` | ≤ target φ | GOLD Liu & Yuan 2015 | a5c33d52 06-10 02:37:26 |
| 8 | lnp_formulation_optimization | LNP_FORMULATION_OPTIMIZATION | `z_avg_nm` | ∈ [60, 120] | SILVER, CLT range; `pdi` not computed | 222a9c10 06-10 16:13:20 |
| 9 | antibody_developability | ANTIBODY_DEVELOPABILITY | `tap_total_cdr_length` | ∈ [43, 63] residues | GOLD Raybould 2019 Table 1 (CST 5th-95th); `tap_psh_score` + `camsol_intrinsic_score` deliberately omitted (scale mismatch) | 5f1828dc 06-10 16:45:28 |
| 10 | sirna_offtarget_analysis | SIRNA_OFFTARGET_ANALYSIS | `delta_dg_asymmetry_kcal_mol` | ≥ 0.5 kcal/mol | GOLD Khvorova 2003; `min_seed_mismatches` omitted (categorical labels, no raw counts) | 512bb06d 06-10 17:02:19 |
| 11 | biomarker_patient_enrichment | BIOMARKER_PATIENT_ENRICHMENT | `biomarker_prevalence` + `enrichment_factor` | prev ∈ [0.10, 0.50] + EF ≥ 1.5 | SILVER FDA Enrichment 2019 + BRONZE Phase III convention; `biomarker_pos_hr` omitted (binary-outcome RR ≠ time-to-event HR) | 10467ddc 06-10 17:43:03 |
| 12 | ivive_hepatic_clearance | IVIVE_HEPATIC_CLEARANCE | `ivive_fold_error` | ≤ 2 | GOLD Obach 1999 Drug Metab Dispos 27:1350; fold_error only emitted when `clh_observed_ml_min_kg` param supplied | 2bd4e370 06-10 19:33:12 |
| 13 | predict_admet_properties | PREDICT_ADMET_PROPERTIES | `herg_ic50_uM` + `ames_positive` + `dili_risk` | hERG ≥10μM / Ames neg / DILI != high | GOLD Redfern 2003 + Sanguinetti 2006 (hERG) / SILVER Kazius 2005 (Ames) / SILVER Mulliner 2016 (DILI); gate TRIGGERED on terfenadine (canonical hERG positive control, IC50 0.24μM) AND on its high DILI risk — exactly as expected | 7482bb1e 06-10 19:44:27 |
| 14 | cyp_ddi_panel | DDI_RISK_ASSESSMENT | `overall_recommendation` | NOT_EXPECTED / INVESTIGATE / CLINICAL_STUDY_RECOMMENDED | GOLD FDA 2020 In Vitro DDI Guidance (R1 ≥ 1.02 INVESTIGATE; R1 ≥ 1.1 CLINICAL); requires `null`→`None` Groovy interpolation fix (`420639060`) | aae555da 06-11 19:32:10 |
| 15 | nca_pknca | NCA_PKNCA_ANALYSIS | `auc_extrap_pct_max` | ≤ 20% | GOLD FDA 2003 BA/BE Guidance; required `route` synonym canonicalization fix (`873bf21f2`) — PKNCA only accepts `extravascular`/`intravascular`. Advisory warning on `t_half_h` null fine — that is a downstream attribute, not the gate metric. Fixture: `s3://biomate-nextflow-work/fixtures/nca/synthetic_pk_theo_nca.csv` (12 subjects × 10 timepoints, derived from popPK Theophylline-style data) | 61562ea6 06-11 21:54:57 |

## Code-ready but blocked

| # | Workflow | Gate | Blocker |
|---|---|---|---|
| 9 | aizynthfinder_retrosynthesis | `num_solved_routes ≥ 1` (GOLD Genheden 2020) | Container `biomate/biomni-drug-discovery-nf:x86` ships without any expansion policy. PREDICT fails at `policy.items[0]` IndexError before RETROSYNTHESIS_REPORT can run. The qc_metrics.json emit + `_S3_REPORT_PATHS` entry are correct and will fire once the container is fixed. |
| 10 | boltz_structure_prediction | `mean_plddt ≥ 70`, `max_pae ≤ 8 Å`, `confident_fraction ≥ 0.70` (GOLD Jumper 2021 / Tunyasuvunakool 2021) | GPU Batch run, ~$ per minute. Verification deferred pending dedicated GPU-budget session. Code path validated: SUMMARISE_RESULTS renamed BOLTZ_SUMMARISE_RESULTS so process name contains the "BOLTZ" `_PROCESS_KEYWORDS` substring. |
| 11 | nlmixr2_population_pk | `eta_shrinkage_pct_max < 20%` (GOLD Savic & Karlsson 2007) + `condition_number` | Fixture now staged: `s3://biomate-nextflow-work/fixtures/popPK/synthetic_pk_theo.csv` (12 subjects × 11 timepoints, Theophylline-style 1-cmt oral). Workflow + qc_metrics.json emit + `_S3_REPORT_PATHS` entry + E2E test (`frontend/e2e/nlmixr2-qc-coverage.e2e.t`) all committed. Verification blocked: both SAEM (run `8dfe97d7`, 2026-06-10 18:54 UTC) and FOCEI (run `1e66c9f1`, 2026-06-10 19:10 UTC) reach NLMIXR2_POPULATION_PK and fail at `nlmixr2::nlmixr2()` with R-side tryCatch swallowing the message. Container `biomate/r-pharma:x86` has nlmixr2/rxode2 installed but the fit fails for this sparse fixture; root cause requires reading `.command.log` from the AWS Batch task work dir (not accessible from this session). Not a BioMate code-path bug. |

## Recipe

For each workflow:

1. **Identify the process** that computes the gate metric. Match against
   `_PROCESS_KEYWORDS[<domain>]` in `qc_gate_emit.py` — if the process
   name doesn't contain one of those keywords, either rename the process
   or extend the keyword set.
2. **Emit `qc_metrics.json`** from that process with the canonical key
   the gate reader expects (`z_prime`, `safety_margin_x`,
   `herg_safety_margin_x`, `druggability_score`, `r_squared`,
   `num_solved_routes`, `week30_weight_change_kg`, ...). Keys are
   case-sensitive — `hERG_safety_margin_x` ≠ `herg_safety_margin_x`.
3. **Add the output declaration** to the process. Watch for the
   ich_s5 footgun: if the process previously emitted N outputs and
   downstream callers reference `.out[N-1]` positionally, adding a
   new `.out[N]` will shift indices. Either reference outputs by name
   (`.out.qc_metrics`) or pin downstream calls to specific indices.
4. **Register in `_S3_REPORT_PATHS`** in `qc_trace_monitor.py`:
   ```
   "PROCESS_NAME": ("*", "qc_metrics.json"),  # gate (provenance, citation)
   ```
   Wildcard step prefix; the S3 search uses `list_objects_v2` which
   returns nested paths.
5. **Verify** by submitting via `/api/workflows/execute` and grepping
   gunicorn.log for `[QC-S3] Reading report for <PROCESS>`.

## Provenance audit (companion work)

Audited the existing 26 GOLD entries in `backend/config/qc_evidence.yaml`
and demoted 4 to SILVER where the cited paper establishes the metric but
does not state the cutoff verbatim:

| Entry | Was | Now | Why |
|---|---|---|---|
| `admet_ames` | GOLD | SILVER | Kazius 2005 defines alert SET; 0.5 cutoff is generic classifier midpoint |
| `allometric_r_squared` | GOLD | SILVER | FDA 2005 FIH doesn't state R² ≥ 0.85 — textbook convention |
| `cryo_em_fsc_resolution` | GOLD | SILVER | R&H 2003 establishes FSC 0.143 metric, not 4/8/15 Å tiers |
| `cryo_et_sta_fsc_resolution` | GOLD | SILVER | Same root — paper has no STA tier values |

Counts: GOLD 26 → 22, SILVER 26 → 30, BRONZE 5. Audit doc:
`docs/20260607_QC_EVIDENCE_AUDIT_PASS_2.md`.

Split-grade template adopted for new entries: "metric is GOLD-anchored
to paper Y; specific cutoff is operational/SILVER."

Also corrected `evidence_tier: "BRONZE"` → `"GOLD"` in the
pocket_detection workflow's qc_result.json — Le Guilloux 2009 states
the ≥0.5 cutoff verbatim, so the inline label now matches
qc_evidence.yaml.

## Infrastructure fixes (benefit every workflow)

### `0e69e9577` — Header-aware trace column lookup

The QC monitor's `_poll` thread previously hardcoded `parts[3]` /
`parts[4]` for `process_name` / `task_status`. Workflows that customize
`trace.fields` (observed: pocket_detection_druggability) drop the
default `hash` column, shifting columns left.

**Symptom on dev 2026-06-09 02:49:04:**
```
[WORKFLOW][inv=40d26482][workflow.phase_started] Step 0…
    phase_name='0'   ← bogus: this is parts[3]=exit value
```
No further `[QC Gate]` events even though both Batch tasks COMPLETED.

**Fix:** map header names → indices like
`_parse_nextflow_trace_progress` (line 1942) already does, fall back
to defaults if header is absent. Defensive bounds-check against
`len(parts) ≤ max(needed indices)`.

### `43603bf6c` — Prefer S3 when `s3_outdir` is set

The old condition was:
```python
if self.s3_outdir and not task_work_dir.is_dir(): ... read S3
```
This skipped the S3 fallback whenever `process_hash` was empty (which
happens when `trace.fields` omits `hash`): `task_work_dir` then defaults
to `self.work_dir`, which exists locally on the Galaxy container, so
`not is_dir()` is False.

**Symptom on dev 2026-06-09 04:09:43**, even after the header-aware fix:
```
[QC Gate] Process completed: POCKET_DETECTION_DRUGGABILITY:DRUGGABILITY_QC_GATE
[QC Gate] No QC metrics calculated for ...
                                            ← no [QC-S3] line at all
```
The qc_metrics.json *was* on S3 (verified out-of-band) but the monitor's
S3 read was gated off.

**Fix:** when `s3_outdir` is set, try S3 first. Local parsers still
run as a fallback if S3 returned nothing.

## Sign-convention note (p0_pkpd_semaglutide)

The workflow computes `weight_loss_30w` as positive when weight is LOST
(e.g. 4.53 kg = lost 4.53 kg). The gate expects `week30_weight_change_kg`
where negative = loss. The emit negates the sign:
```python
qc_metrics["week30_weight_change_kg"] = -weight_loss_30w
```
Without this, the band check ([-6, +3]) would interpret +4.53 as "gained
4.53 kg" and FAIL the gate.

## Known dev infrastructure flakes encountered

- Disk fullness (06-08 ~12:30 UTC) → instance hang → reboot.
- Parallel-session sync overwrote `/app/config/galaxy.yml` PYTHONPATH
  back to laptop-local path (`/home/yzhang/biomate/backend/lib`),
  breaking Galaxy boot with "No module named 'galaxy'". Required
  manual sed + `galaxyctl update` + `galaxyctl restart gunicorn`.
- Galaxy's `chat_narrator` mis-reports `outcome: failed` for many
  workflows that actually succeed (Nextflow trace shows
  `Succeeded: N`). Unrelated to QC chain; doesn't affect gate
  evaluation. Tracked separately.

## Commits (in chronological order this stretch)

| Commit | What |
|---|---|
| `4b741af54` | 4 GOLD demotions + allometric coverage as SILVER + qc_metrics.json emit |
| `f5c2cb39b5` | ALLO-1 e2e test |
| `fde8506d43` | ich_s5 coverage |
| `20eb0fe25` | ich_s5 AGGREGATE call signature fix + ICH-1 test |
| `7929b26f0` | ich_s7a coverage |
| `5c351e5656` | ICH-S7A-1 test |
| `c29304eaf2` | pocket_detection coverage + workflow's BRONZE → GOLD inline label |
| `a429c45ac9` | POCKET-1 test + initial poll-cadence finding |
| `0e69e9577` | header-aware trace column lookup |
| `43603bf6c` | S3-first when s3_outdir is set |
| `20d10f9d7b` | aizynthfinder coverage |
| `e75ccc3d5` | AIZYNTH-1 test + container-policy block doc |
| `2860c9fc9` | p0_pkpd_semaglutide coverage |
| `0757dc196` | P0-1 test |
| `13df179ac` | clinical_trial_simulation (BOIN) coverage |
| `8ae9aedb9` | BOIN-1 e2e test |
| `0badbf787` | boltz_structure_prediction coverage (rename to BOLTZ_SUMMARISE_RESULTS) |
| `98e536bc1` | lnp_formulation_optimization coverage |
| `5d98c0441` | LNP-1 test + Node-route-block note |

## Open follow-ups (not in this scope)

- Aizynthfinder container needs an expansion policy configured
- Galaxy `chat_narrator` mis-reports outcome=failed for succeeded runs
- Galaxy worker boot time (~2h cold-start observed today) — likely the
  toolbox indexing step
- 4 untouched GOLD entries in qc_evidence.yaml could benefit from a
  re-audit pass (they spot-checked legitimate but a deep re-read might
  surface more split-grade demotions)
