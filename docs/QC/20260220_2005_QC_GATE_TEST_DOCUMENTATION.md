# QC Gate Test Suite Documentation
**Generated**: 2026-02-20 20:05
**Total tests**: 319 / 319 PASSING
**Test files**: 4
**Production bugs found & fixed**: 8

---

## Executive Summary

This document covers the full test suite for BioMate's **Nextflow QC Gate Pipeline** — the system that monitors workflow execution, parses tool output files in real time, detects quality failures, and pushes SSE events to the frontend for researcher intervention.

The suite grew from 0 to 319 tests across four audit rounds, finding and fixing 8 production bugs along the way. All 319 tests pass as of this timestamp.

### Test File Overview

| File | Classes | Tests | Focus |
|---|---|---|---|
| `test_gap3_complete_integration.py` | 1 | 17 | End-to-end with real files; SSE contract verification |
| `test_gap3_standalone.py` | — | 7 | Smoke tests for core domains + factory + JSON serialisation |
| `test_qc_edge_cases.py` | 18 | 222 | All parser edge cases, boundary conditions, threshold logic, regression tests |
| `test_qc_e2e_domains.py` | 7 | 73 | Multi-domain researcher personas: RNA-seq, DNA-seq, scRNA, ChIP-seq, metagenomics, cryo-EM |

---

## Production Files Tested (Input Log Formats → Parsers → Metrics)

| Tool | Output File | Parser Method | Key Metrics Extracted |
|---|---|---|---|
| MotionCor2 | `*.log` (contains "Total motion:") | `_parse_motion_correction_metrics` | `total_drift_angstrom`, `drift_per_frame`, `correlation_score` |
| CTFFIND4 | `*_ctf.txt` (tab-separated, 8 columns) | `_parse_ctf_metrics` | `defocus_u`, `defocus_v`, `astigmatism`, `fit_quality` |
| CryoSPARC picking | `*.star` (RELION STAR format) | `_parse_particle_picking_metrics` | `particle_count`, `duplicate_fraction` |
| FastQC | `fastqc_data.txt`, `summary.txt` | `_parse_fastqc_metrics` | `gc_content_pct`, `avg_sequence_length`, `failed_modules` |
| FASTP | `fastp.json` | `_parse_trimming_metrics` | `reads_surviving_pct`, `q30_rate` |
| Trimmomatic | `*.log` (contains "Surviving:") | `_parse_trimming_metrics` | `reads_surviving_pct` |
| STAR | `Log.final.out` | `_parse_alignment_metrics` | `uniquely_mapped_pct`, `alignment_rate` (= uniquely_mapped + multi-loci) |
| STAR (STARsolo) | `Summary.csv` | `_parse_singlecell_metrics` | `estimated_cells`, `median_genes_per_cell` |
| HISAT2 | `*.log` (contains "overall alignment rate") | `_parse_alignment_metrics` | `alignment_rate` |
| BWA-MEM | `*.log` (contains "mapped (") | `_parse_alignment_metrics` | `alignment_rate` |
| featureCounts | `*.summary` (tab-separated) | `_parse_featurecounts_metrics` | `assigned_pct` |
| Salmon | `aux_info/meta_info.json` | `_parse_salmon_metrics` | `mapping_rate` |
| samtools flagstat | `*.flagstat` | `_parse_flagstat_metrics` | `mapped_pct`, `duplicate_pct` |
| Picard MarkDuplicates | `*.dup_metrics` | `_parse_picard_dup_metrics` | `duplicate_pct` |
| CellRanger | `metrics_summary.csv` | `_parse_singlecell_metrics` | `estimated_cells`, `median_genes_per_cell` |
| MACS2 | `*.narrowPeak`, `*.broadPeak`, `summits.bed` | `_parse_peakcalling_metrics` | `peak_count`, `tags_after_filtering` |
| Kraken2 | `*.report` (starts with "U\t") | `_parse_metagenomics_metrics` | `classified_pct`, `unclassified_pct` |
| MultiQC | `multiqc_data.json` | (inside `_parse_fastqc_metrics`) | `gc_content_pct`, `avg_read_length` |

---

## QC Thresholds Reference

| Domain | Process | Metric | Operator | Threshold |
|---|---|---|---|---|
| Cryo-EM | MOTION_CORRECTION | `total_drift_angstrom` | > | 50 Å |
| Cryo-EM | MOTION_CORRECTION | `correlation_score` | < | 0.5 |
| Cryo-EM | CTF_ESTIMATION | `astigmatism` (abs diff) | > | 500 Å |
| Cryo-EM | CTF_ESTIMATION | `fit_quality` | < | 0.1 |
| Cryo-EM | CTF_ESTIMATION | `defocus_u` | outside | [1000, 100000] Å |
| Cryo-EM | PARTICLE_PICKING | `particle_count` | < | 100 |
| RNA-seq | FASTQC/MULTIQC | `failed_modules` | > | 2 |
| RNA-seq | FASTP/TRIM | `reads_surviving_pct` | < | 70% |
| RNA-seq | FASTP/TRIM | `q30_rate` | < | 75% |
| RNA-seq | STAR_ALIGN | `alignment_rate` | < | 60% |
| RNA-seq | FEATURECOUNTS | `assigned_pct` | < | 50% |
| RNA-seq | SALMON | `mapping_rate` | < | 50% |
| DNA-seq | FLAGSTAT | `mapped_pct` | < | 90% |
| DNA-seq | FLAGSTAT | `duplicate_pct` | > | 30% |
| DNA-seq | MARKDUPLICATES | `duplicate_pct` | > | 30% |
| scRNA | CELLRANGER | `estimated_cells` | < | 500 |
| scRNA | CELLRANGER | `median_genes_per_cell` | < | 1000 |
| ChIP-seq | MACS2 | `peak_count` | < | 1000 |
| Metagenomics | KRAKEN2 | `classified_pct` | < | 50% |

---

## File 1: `test_gap3_complete_integration.py`
**17 tests** — `TestGap3CompleteIntegration`

All tests write actual files to `tmp_path`, invoke the real handler, and assert on SSE event content. No mocks of core parser or threshold logic.

| Test | Log File Used | What It Verifies |
|---|---|---|
| `test_cryo_em_domain_initialises_cryo_em_suggester` | none | `workflow_domain="cryo_em"` → `suggester` is `CryoEMParameterSuggester` |
| `test_unknown_domain_still_initialises_some_suggester` | none | `workflow_domain="totally_unknown"` → still returns a suggester (no crash) |
| `test_motion_correction_high_drift_from_real_file` | `motion.log` ("Total motion: 65.3 Å") | SSE fires; `total_drift_angstrom ≈ 65.3`; `dose_weighting` suggestion with `confidence ≈ 0.85` |
| `test_ctf_estimation_real_file_triggers_gate_with_suggestions` | `*_ctf.txt` (8-column CTFFIND4 format) | SSE fires; `astigmatism` and `fit_quality` extracted; defocus range suggestion present |
| `test_particle_picking_real_star_file` | `*.star` (RELION STAR with particle rows) | `particle_count` extracted; SSE fires when count < 100 |
| `test_sse_event_has_all_required_top_level_keys` | `motion.log` | SSE event dict has `invocation_id`, `process_name`, `timestamp`, `qc_metrics`, `failures`, `suggestions` |
| `test_sse_failure_dicts_have_required_keys` | `motion.log` | Each failure dict has `metric`, `value`, `threshold`, `operator`, `message` |
| `test_sse_suggestion_dicts_have_required_camelcase_keys` | `motion.log` | Each suggestion has `parameter`, `currentValue`, `suggestedValue`, `reason`, `confidence` (camelCase, not snake_case) |
| `test_sse_invocation_id_matches_handler` | `motion.log` | SSE `invocation_id` == the ID the handler was constructed with |
| `test_full_event_is_json_serialisable` | `motion.log` (high drift) | `json.dumps(event_data)` does not raise |
| `test_ctf_event_is_json_serialisable` | `*_ctf.txt` (bad CTF) | Full CTF event is JSON-safe (dict suggestions, float values) |
| `test_cryo_em_suggester_motion_correction` | none (direct suggester call) | `CryoEMParameterSuggester.suggest()` returns `dose_weighting=True` for drift > 50 |
| `test_cryo_em_suggester_ctf_estimation` | none (direct suggester call) | `suggest()` returns defocus range dict for astigmatism > 500 |
| `test_cryo_em_suggester_particle_picking_too_few` | none (direct suggester call) | `suggest()` returns `picking_threshold` reduction for count < 100 |
| `test_cryo_em_suggester_particle_picking_high_duplicates` | none (direct suggester call) | `suggest()` returns `min_separation_distance` increase for dup fraction > 0.3 |
| `test_good_motion_log_no_sse_event` | `motion.log` (drift = 10 Å — below threshold) | No SSE event fired |
| `test_good_ctf_no_sse_event` | `*_ctf.txt` (good defocus, low astigmatism, good fit) | No SSE event fired |

---

## File 2: `test_gap3_standalone.py`
**7 tests** — module-level functions

Smoke tests that exercise the handler end-to-end but do not inspect every detail; useful as a quick sanity check after refactors.

| Test | What It Verifies |
|---|---|
| `test_cryo_em_motion_correction` | High-drift motion log → SSE event with `total_drift_angstrom` and `dose_weighting` suggestion |
| `test_cryo_em_ctf_estimation` | Bad CTFFIND4 file → SSE event with `astigmatism` failure |
| `test_cryo_em_particle_picking` | Sparse STAR file (< 100 particles) → SSE gate triggered |
| `test_rna_seq_quality_trimming` | FASTP JSON with `reads_surviving_pct` < 70% → SSE gate triggered |
| `test_rna_seq_alignment` | STAR log with `alignment_rate` < 60% → SSE gate triggered |
| `test_domain_suggester_factory` | `get_suggester_for_domain()` returns correct subclass for 6 domains |
| `test_json_serialization` | Motion correction SSE event round-trips through `json.dumps` / `json.loads` |

---

## File 3: `test_qc_edge_cases.py`
**222 tests** across 18 classes

### `TestStatusFiltering` (5 tests)
Ensures `handle_process_completion` skips QC for non-COMPLETED tasks.

| Test | What It Verifies |
|---|---|
| `test_non_completed_status_skips_qc[FAILED]` | FAILED tasks do not trigger parser |
| `test_non_completed_status_skips_qc[RUNNING]` | RUNNING tasks do not trigger parser |
| `test_non_completed_status_skips_qc[CACHED]` | CACHED tasks do not trigger parser |
| `test_non_completed_status_skips_qc[CANCELLED]` | CANCELLED tasks do not trigger parser |
| `test_completed_status_does_call_qc` | COMPLETED status proceeds to `_calculate_qc_metrics` |

### `TestDuplicateDeduplication` (2 tests)
Ensures the `processed_tasks` set prevents re-processing the same task.

| Test | What It Verifies |
|---|---|
| `test_duplicate_task_emits_only_one_event` | Same task_id submitted twice → SSE fires exactly once |
| `test_different_task_ids_both_processed` | Two distinct task_ids → SSE fires twice |

### `TestThresholdBoundaryConditions` (8 tests)
Strict boundary tests for cryo-EM thresholds (using `>=` / `<=` semantics).

| Test | Metric | Boundary | Expected |
|---|---|---|---|
| `test_drift_exactly_at_threshold_no_trigger` | drift = 50.0 | threshold 50 | No event |
| `test_correlation_exactly_at_threshold_no_trigger` | correlation = 0.5 | threshold 0.5 | No event |
| `test_astigmatism_exactly_at_threshold_no_trigger` | astigmatism = 500.0 | threshold 500 | No event |
| `test_fit_quality_exactly_at_threshold_no_trigger` | fit_quality = 0.1 | threshold 0.1 | No event |
| `test_particles_exactly_at_threshold_no_trigger` | particles = 100 | threshold 100 | No event |
| `test_duplicate_fraction_exactly_at_threshold_no_trigger` | dup_fraction = 0.3 | threshold 0.3 | No event |
| `test_metrics_just_below_trigger_no_event` | drift = 49.9 | threshold 50 | No event |
| `test_metrics_just_above_trigger_fires_event` | drift = 50.1 | threshold 50 | SSE fires |

### `TestParserEdgeCases` (8 tests)
Verifies parsers return `None` (not crash) for corrupt or missing input.

| Test | Input Condition | Expected |
|---|---|---|
| `test_empty_log_file_returns_none` | `motion.log` is empty | `None` |
| `test_malformed_log_no_keywords_returns_none` | `motion.log` with gibberish | `None` |
| `test_malformed_ctf_file_returns_none` | `_ctf.txt` with wrong column count | `None` |
| `test_empty_star_file_returns_none` | `.star` file is empty | `None` |
| `test_star_file_only_headers_returns_none` | `.star` has headers but no data rows | `None` |
| `test_unknown_process_name_returns_none` | Process name `UNKNOWN_PROCESS` | `None` |
| `test_ctf_defocus_outside_valid_range_returns_none` | `defocus_u = 50` (< 1000 Å) | `None` |
| `test_motion_drift_zero_from_garbage_not_stored` | Log has only `"Total motion: 0.0"` | `None` (zero drift not stored) |

### `TestParserPositiveCases` (4 tests)
Happy-path parser verification.

| Test | File | Verified Metric |
|---|---|---|
| `test_motion_log_drift_parsed_correctly` | `motion.log` ("Total motion: 45.2 Å") | `total_drift_angstrom ≈ 45.2` |
| `test_ctf_file_parsed_correctly` | `_ctf.txt` (CTFFIND4 8-column) | `defocus_u`, `defocus_v`, `astigmatism`, `fit_quality` correct |
| `test_star_file_particles_counted` | `*.star` with 150 data rows | `particle_count = 150` |
| `test_drift_per_frame_derived` | `motion.log` + 40-frame count | `drift_per_frame = total_drift / frames` |

### `TestSuggesterAlreadyAtRecommended` (6 tests)
No suggestion emitted when a parameter is already at the recommended value.

| Test | Condition | Expected |
|---|---|---|
| `test_dose_weighting_already_enabled_no_suggestion` | `dose_weighting=True`, high drift | No dose_weighting suggestion |
| `test_patch_size_already_large_no_suggestion` | `patch_size=7`, high drift | No patch_size suggestion |
| `test_alignment_frames_already_sufficient_no_suggestion` | `alignment_frames=10`, low correlation | No frames suggestion |
| `test_tilt_search_already_on_no_suggestion` | `tilt_search=True`, bad CTF | No tilt_search suggestion |
| `test_defocus_range_already_wide_no_suggestion` | `defocus_min/max` at full range, bad CTF | No defocus suggestion |
| `test_picking_threshold_already_at_minimum_no_suggestion` | `picking_threshold=0.05`, few particles | No threshold suggestion |

### `TestNoneDefaults` (5 tests)
Absent optional metrics → no suggestion (not a crash, not a false suggestion).

| Test | Absent Metric | Expected |
|---|---|---|
| `test_absent_correlation_score_produces_no_frame_suggestion` | `correlation_score` absent | No alignment_frames suggestion |
| `test_ctf_no_fit_quality_no_defocus_suggestion` | `fit_quality` absent | No tilt suggestion |
| `test_picking_no_count_no_threshold_suggestion` | `particle_count` absent | No threshold suggestion |
| `test_picking_no_duplicate_frac_no_separation_suggestion` | `duplicate_fraction` absent | No separation suggestion |
| `test_2d_classify_no_convergence_no_iteration_suggestion` | `convergence_delta` absent | No max_iterations suggestion |

### `TestAbInitioAndRefinement` (5 tests)
Verifies ab initio resolution and FSC suggestions.

| Test | Metric | Condition | Expected Suggestion |
|---|---|---|---|
| `test_ab_initio_poor_resolution_suggests_more_classes` | `resolution_angstrom = 25` | > 15 Å threshold | `num_classes` increased |
| `test_ab_initio_already_multi_class_no_suggestion` | `num_classes = 4` already | — | No suggestion |
| `test_refinement_poor_fsc_suggests_per_particle_ctf` | `fsc_0143 < 4.0 Å` | — | `per_particle_ctf_refine=True` |
| `test_refinement_already_per_particle_no_suggestion` | `per_particle_ctf_refine=True` | — | No suggestion |
| `test_ab_initio_resolution_exactly_at_threshold_no_suggestion` | `resolution_angstrom = 15.0` | exactly at threshold | No event |

### `TestRNASeqSuggester` (6 tests)
Verifies `RNASeqParameterSuggester` suggestions.

| Test | Condition | Expected |
|---|---|---|
| `test_trim_low_quality_suggests_higher_cutoff` | `reads_surviving_pct = 55%` | `quality_cutoff` suggestion |
| `test_trim_good_quality_no_suggestion` | `reads_surviving_pct = 85%` | No suggestion |
| `test_trim_cutoff_already_sufficient_no_suggestion` | cutoff already at max | No suggestion |
| `test_alignment_poor_mapping_suggests_more_mismatches` | `alignment_rate = 42%` | `max_mismatches` suggestion |
| `test_alignment_already_at_max_mismatches_no_suggestion` | `max_mismatches` already maximum | No suggestion |
| `test_alignment_good_mapping_no_suggestion` | `alignment_rate = 88%` | No suggestion |

### `TestDomainFactory` (13 tests)
Verifies `get_suggester_for_domain()` dispatch table.

| Test | Domain Input | Expected Class |
|---|---|---|
| `test_correct_class_returned[cryo_em-...]` | `cryo_em` | `CryoEMParameterSuggester` |
| `test_correct_class_returned[CRYO_EM-...]` | `CRYO_EM` | `CryoEMParameterSuggester` |
| `test_correct_class_returned[cryo-em-spa-...]` | `cryo-em-spa` | `CryoEMParameterSuggester` |
| `test_correct_class_returned[rnaseq-...]` | `rnaseq` | `RNASeqParameterSuggester` |
| `test_correct_class_returned[rna_seq-...]` | `rna_seq` | `RNASeqParameterSuggester` |
| `test_correct_class_returned[RNA-seq-...]` | `RNA-seq` | `RNASeqParameterSuggester` |
| `test_correct_class_returned[genomics-...]` | `genomics` | `GenomicsParameterSuggester` |
| `test_correct_class_returned[wgs_pipeline-...]` | `wgs_pipeline` | `GenomicsParameterSuggester` |
| `test_correct_class_returned[chipseq-...]` | `chipseq` | `ChIPSeqParameterSuggester` |
| `test_correct_class_returned[metagenomics-...]` | `metagenomics` | `MetagenomicsParameterSuggester` |
| `test_correct_class_returned[single_cell_rnaseq-...]` | `single_cell_rnaseq` | `SingleCellParameterSuggester` |
| `test_correct_class_returned[completely_unknown-...]` | `completely_unknown` | `BaseParameterSuggester` |
| `test_base_suggester_raises_not_implemented` | Base class `.suggest()` | `NotImplementedError` |

### `TestSSECallbackErrors` (2 tests)
Handler is resilient to callback and suggester exceptions.

| Test | What It Verifies |
|---|---|
| `test_callback_exception_does_not_propagate` | SSE callback that raises → handler continues silently |
| `test_parameter_suggester_exception_does_not_propagate` | Suggester that raises → no SSE, no crash |

### `TestPositiveCasesNoTrigger` (4 tests)
Good-quality metrics produce no SSE events.

| Test | Domain | Condition |
|---|---|---|
| `test_good_motion_correction_no_event` | cryo-EM | drift = 10 Å, correlation = 0.9 |
| `test_good_ctf_no_event` | cryo-EM | astigmatism = 100, fit = 0.8, valid defocus |
| `test_good_picking_no_event` | cryo-EM | 500 particles, dup_fraction = 0.05 |
| `test_no_metrics_returned_no_event` | any | Parser returns `None` → no event |

### `TestMultipleFailures` (2 tests)
Multiple QC metrics failing simultaneously → multiple failure dicts in one SSE event.

| Test | Failures in One Event |
|---|---|
| `test_two_failures_in_single_event` | Motion: both high drift AND low correlation → 2 failures |
| `test_two_ctf_failures_structured` | CTF: both high astigmatism AND bad fit_quality → 2 failures |

### `TestStructuredFailureFormat` (6 tests)
Validates the typed failure dict format sent to the frontend.

| Test | What It Verifies |
|---|---|
| `test_motion_failure_has_all_required_keys` | Failure dict has `metric`, `value`, `threshold`, `operator`, `message` |
| `test_failure_operator_is_valid` | `operator` is one of `">"`, `"<"`, `">="`, `"<="`, `"!="`, `"outside"` |
| `test_failure_values_are_numeric` | `value` and `threshold` are `int` or `float`, not strings |
| `test_failure_is_json_serializable` | Failure dict round-trips through `json.dumps` |
| `test_drift_failure_operator_is_greater_than` | Drift failure uses `operator = ">"` |
| `test_correlation_failure_operator_is_less_than` | Correlation failure uses `operator = "<"` |

### `TestConfidenceRange` (5 tests — parametrized)
Suggestion confidence is always in [0.0, 1.0].

Tests all 5 process types: `MOTION_CORRECTION`, `CTF_ESTIMATION`, `PARTICLE_PICKING`, `AB_INITIO`, `HOMOGENEOUS_REFINEMENT`.

### `TestDictSuggestedValues` (2 tests)
CTF defocus suggestion uses a dict (range) rather than a scalar.

| Test | What It Verifies |
|---|---|
| `test_defocus_dict_suggestion_is_json_serializable` | `suggestedValue = {"min": ..., "max": ...}` is JSON-safe |
| `test_defocus_current_value_is_dict_too` | `currentValue` is also a dict for defocus |

### `TestProcessNameVariants` (12 tests)
Process name variants all route to the correct parser and extract real metric values from actual files.

| Test | Process Name Variants | File Written | Verified Metric |
|---|---|---|---|
| `test_motion_correction_variants_extract_real_drift[MOTION_CORRECTION]` | `MOTION_CORRECTION` | `motion.log` | `total_drift_angstrom ≈ 73.5` |
| `test_motion_correction_variants_extract_real_drift[PATCH_MOTION_CORRECTION]` | `PATCH_MOTION_CORRECTION` | `motion.log` | `total_drift_angstrom ≈ 73.5` |
| `test_motion_correction_variants_extract_real_drift[motion_correction]` | `motion_correction` (lowercase) | `motion.log` | `total_drift_angstrom ≈ 73.5` |
| `test_ctf_variants_extract_real_defocus[CTF_ESTIMATION]` | `CTF_ESTIMATION` | `_ctf.txt` | `defocus_u` in valid range |
| `test_ctf_variants_extract_real_defocus[CTF_ESTIMATE]` | `CTF_ESTIMATE` | `_ctf.txt` | `defocus_u` in valid range |
| `test_ctf_variants_extract_real_defocus[PATCH_CTF_ESTIMATION]` | `PATCH_CTF_ESTIMATION` | `_ctf.txt` | `defocus_u` in valid range |
| `test_ctf_variants_extract_real_defocus[ctf_estimation]` | `ctf_estimation` (lowercase) | `_ctf.txt` | `defocus_u` in valid range |
| `test_picking_variants_count_real_particles[PARTICLE_PICKING]` | `PARTICLE_PICKING` | `*.star` | `particle_count = 42` |
| `test_picking_variants_count_real_particles[BLOB_PARTICLE_PICKING]` | `BLOB_PARTICLE_PICKING` | `*.star` | `particle_count = 42` |
| `test_picking_variants_count_real_particles[particle_picking]` | `particle_picking` (lowercase) | `*.star` | `particle_count = 42` |
| `test_nfcore_qualified_motion_correction_parses_correctly` | `NFCORE:MOTION_CORRECTION` | `motion.log` | drift extracted correctly |
| `test_nfcore_qualified_star_align_parses_correctly` | `NFCORE:STAR_ALIGN` | `Log.final.out` | `uniquely_mapped_pct ≈ 78.5` |

### `TestSSEEventDataCompleteness` (3 tests)

| Test | What It Verifies |
|---|---|
| `test_all_required_keys_present` | Event data has `invocation_id`, `process_name`, `timestamp`, `qc_metrics`, `failures`, `suggestions` |
| `test_invocation_id_matches` | `event["data"]["invocation_id"]` equals constructor argument |
| `test_timestamp_is_iso8601_and_recent` | Timestamp parses as ISO 8601 and is within 5 seconds of `datetime.utcnow()` |

### `TestHashResolution` (2 tests)
Nextflow uses truncated hashes (`ab/cd1234`); handler globs to find the full work directory.

| Test | What It Verifies |
|---|---|
| `test_truncated_hash_resolves_to_full_dir` | Hash `ab/cd1234` resolves to `tmp/ab/cd1234ef5678/` |
| `test_nonexistent_hash_prefix_returns_none` | Hash `zz/000000` with no matching dir → parser returns `None` |

### `TestSuggestionReasonText` (3 tests)

| Test | What It Verifies |
|---|---|
| `test_drift_suggestion_includes_drift_value` | Reason string contains the actual drift value |
| `test_ctf_suggestion_includes_astigmatism_value` | Reason string contains the astigmatism value |
| `test_picking_suggestion_includes_particle_count` | Reason string contains the actual count |

### `TestBugRegressions` (21 tests)
Dedicated regression tests for all 8 production bugs found during development.

| Test | Bug | What It Catches |
|---|---|---|
| `test_bug1_ambiguous_line_does_not_corrupt_both_metrics` | Bug 1 | A log line matching both drift and correlation regex does not overwrite both metrics |
| `test_bug1_separate_lines_still_parse_both` | Bug 1 | Separate drift + correlation lines both extracted |
| `test_bug2_ab_initio_absent_resolution_no_suggestion` | Bug 2 | Missing `resolution_angstrom` → no suggestion (was KeyError) |
| `test_bug2_refinement_absent_fsc_no_suggestion` | Bug 2 | Missing `fsc_0143` → no suggestion |
| `test_bug2_ab_initio_explicit_good_resolution_no_suggestion` | Bug 2 | Good resolution → no suggestion |
| `test_bug3_qualified_motion_correction_name_gets_suggestions` | Bug 3 | `NFCORE:MOTION_CORRECTION` → still routes to cryo-EM handler |
| `test_bug3_qualified_ctf_name_gets_suggestions` | Bug 3 | `NFCORE:CTFFIND` → still routes to CTF handler |
| `test_bug3_qc_gate_and_suggester_agree_on_process_routing` | Bug 3 | QC gate and suggester both handle same qualified name |
| `test_bug4_multi_micrograph_ctf_file_invalid_last_line` | Bug 4 | Multi-line CTF file with bad last line → uses last valid line |
| `test_bug4_all_invalid_lines_still_returns_none` | Bug 4 | CTF file with all-invalid lines → returns `None` |
| `test_bug5_broad_em_match_does_not_false_route[system_biology]` | Bug 5 | `"_em"` in `"system"` — wait, `system_biology` → does NOT route to cryo-EM |
| `test_bug5_broad_em_match_does_not_false_route[problem_solving]` | Bug 5 | None of the domains false-match cryo-EM |
| `test_bug5_broad_em_match_does_not_false_route[theorem_prover]` | Bug 5 | — |
| `test_bug5_broad_em_match_does_not_false_route[genome_assembly]` | Bug 5 | `genome_assembly` contains no false `_em` |
| `test_bug5_broad_em_match_does_not_false_route[items_database]` | Bug 5 | — |
| `test_bug5_broad_em_match_does_not_false_route[stem_cell_rnaseq]` | Bug 5 | `stem_cell` contains `em` but not `_em` at word boundary |
| `test_bug5_valid_em_domains_still_route_correctly[cryo_em]` | Bug 5 | Legitimate cryo-EM domains not blocked by the fix |
| `test_bug5_valid_em_domains_still_route_correctly[cryo-em-spa]` | Bug 5 | — |
| `test_bug5_valid_em_domains_still_route_correctly[electron_microscopy]` | Bug 5 | — |
| `test_bug5_valid_em_domains_still_route_correctly[cryosparc]` | Bug 5 | — |
| `test_bug5_valid_em_domains_still_route_correctly[em]` | Bug 5 | Single `em` domain still routes correctly |

### `TestUniversalQCParsers` (56 tests)
Covers all 10 non-cryo-EM parsers with positive, negative, threshold, and dispatch tests.

#### FastQC (4 tests)
Files: `fastqc_data.txt`, `summary.txt`

| Test | File | Verified |
|---|---|---|
| `test_fastqc_summary_txt_pass_modules` | `summary.txt` (PASS/WARN/FAIL per module) | `failed_modules = 1` |
| `test_fastqc_data_txt_gc_content` | `fastqc_data.txt` | `gc_content_pct` extracted |
| `test_fastqc_no_files_returns_none` | empty dir | `None` |
| `test_fastqc_all_pass_no_failures` | all PASS | 0 `failed_modules` → no gate |

#### Trimming (4 tests)
Files: `fastp.json`, Trimmomatic `*.log`

| Test | File | Verified |
|---|---|---|
| `test_trimming_fastp_json` | `fastp.json` | `reads_surviving_pct = 75.0` |
| `test_trimming_trimmomatic_log` | `trim.log` ("Surviving: 80.50%") | `reads_surviving_pct ≈ 80.5` |
| `test_trimming_empty_dir_returns_none` | empty dir | `None` |
| `test_trimming_zero_total_reads_skipped` | `fastp.json` total_reads=0 | `None` (no division by zero) |

#### Alignment (3 tests)
Files: STAR `Log.final.out`, HISAT2 `*.log`

| Test | File | Verified |
|---|---|---|
| `test_alignment_star_log_final_out` | `Aligned.Log.final.out` | `uniquely_mapped_pct`, `alignment_rate` |
| `test_alignment_hisat2_log` | `align.log` ("85.23% overall alignment rate") | `alignment_rate ≈ 85.23` |
| `test_alignment_no_files_returns_none` | empty dir | `None` |

#### featureCounts (3 tests)
File: `*.summary` (featureCounts tab-separated summary)

| Test | Condition | Verified |
|---|---|---|
| `test_featurecounts_summary` | Normal summary | `assigned_pct = 75.0` |
| `test_featurecounts_no_file_returns_none` | empty dir | `None` |
| `test_featurecounts_zero_total_safe` | Total reads = 0 | `None` (no division by zero) |

#### Salmon (3 tests)
File: `aux_info/meta_info.json`

| Test | Condition | Verified |
|---|---|---|
| `test_salmon_meta_info_json` | Normal JSON | `mapping_rate` extracted |
| `test_salmon_mapping_rate_key` | Both key variations | `percent_mapped` OR `mapping_rate` key accepted |
| `test_salmon_no_file_returns_none` | No JSON | `None` |

#### Flagstat (3 tests)
File: `*.flagstat` (samtools flagstat text output)

| Test | Condition | Verified |
|---|---|---|
| `test_flagstat_mapped_pct_and_dup_pct` | Full flagstat | `mapped_pct`, `duplicate_pct` both extracted |
| `test_flagstat_no_duplicates_line` | No "duplicates" line | `mapped_pct` only; no crash |
| `test_flagstat_no_file_returns_none` | empty dir | `None` |

#### Picard MarkDuplicates (2 tests)
File: `*.dup_metrics` (Picard METRICS FILE format)

| Test | Condition | Verified |
|---|---|---|
| `test_picard_dup_metrics` | Full .dup_metrics file | `duplicate_pct = PERCENT_DUPLICATION × 100` |
| `test_picard_no_percent_duplication_header` | Missing header | `None` |

#### Single-cell / CellRanger (2 tests)
File: `metrics_summary.csv` (CellRanger output)

| Test | Condition | Verified |
|---|---|---|
| `test_singlecell_cellranger_csv` | Normal CSV with comma-escaped numbers ("4,521") | `estimated_cells`, `median_genes_per_cell` correct |
| `test_singlecell_no_file_returns_none` | empty dir | `None` |

#### Peak-calling / MACS2 (3 tests)
Files: `*.narrowPeak`, `*.macs2.log`

| Test | File | Verified |
|---|---|---|
| `test_peakcalling_narrowpeak_count` | `out.narrowPeak` (50 lines) | `peak_count = 50` |
| `test_peakcalling_macs2_log_tags` | `macs2.log` ("tags after filtering: 5000000") | `tags_after_filtering = 5000000` |
| `test_peakcalling_no_file_returns_none` | empty dir | `None` |

#### Kraken2 (3 tests)
File: `*.report` (Kraken2 TSV report)

| Test | Condition | Verified |
|---|---|---|
| `test_metagenomics_kraken2_report` | Full report with "U" unclassified row | `classified_pct = 72.5` |
| `test_metagenomics_no_u_line_returns_none` | No "U" row | `None` |
| `test_metagenomics_no_file_returns_none` | empty dir | `None` |

#### Threshold tests (14 tests)
Each parser tested at its threshold boundary.

| Test | Parser | Metric | Direction | Threshold |
|---|---|---|---|---|
| `test_fastp_below_threshold_fails` | trimming | reads_surviving_pct = 60% | < 70% | FAIL |
| `test_fastp_above_threshold_passes` | trimming | reads_surviving_pct = 80% | ≥ 70% | PASS |
| `test_fastp_at_threshold_exactly_passes` | trimming | reads_surviving_pct = 70% | = 70% | PASS |
| `test_star_low_alignment_rate_fails` | alignment | alignment_rate = 45% | < 60% | FAIL |
| `test_star_high_alignment_rate_passes` | alignment | alignment_rate = 80% | ≥ 60% | PASS |
| `test_featurecounts_low_assignment_fails` | featurecounts | assigned_pct = 30% | < 50% | FAIL |
| `test_salmon_low_mapping_fails` | salmon | mapping_rate = 35% | < 50% | FAIL |
| `test_flagstat_high_dup_fails` | flagstat | duplicate_pct = 45% | > 30% | FAIL |
| `test_markdup_dup_at_threshold_passes` | picard | duplicate_pct = 30% | = 30% | PASS |
| `test_cellranger_too_few_cells_fails` | singlecell | estimated_cells = 200 | < 500 | FAIL |
| `test_cellranger_low_genes_fails` | singlecell | median_genes_per_cell = 500 | < 1000 | FAIL |
| `test_macs2_few_peaks_fails` | peakcalling | peak_count = 500 | < 1000 | FAIL |
| `test_kraken2_low_classified_fails` | metagenomics | classified_pct = 30% | < 50% | FAIL |
| `test_kraken2_passes_at_threshold` | metagenomics | classified_pct = 50% | = 50% | PASS |

#### Dispatch integration tests (11 tests)
Each process name variant routes correctly and extracts real metric values from real files.

| Test | Process Name | File Written | Verified Metric |
|---|---|---|---|
| `test_dispatch_fastp_extracts_real_survival_pct` | `FASTP_TRIM` | `fastp.json` | `reads_surviving_pct = 75.0` |
| `test_dispatch_star_extracts_real_alignment_rate` | `STAR_ALIGN` | `Log.final.out` | `alignment_rate ≈ 83.5` |
| `test_dispatch_featurecounts_extracts_real_assigned_pct` | `FEATURECOUNTS` | `fc.summary` | `assigned_pct ≈ 75.0` |
| `test_dispatch_salmon_extracts_real_mapping_rate` | `SALMON_ALEVIN` | `meta_info.json` | `mapping_rate ≈ 88.5` |
| `test_dispatch_flagstat_extracts_real_mapped_pct` | `SAMTOOLS_FLAGSTAT` | `out.flagstat` | `mapped_pct ≈ 95.0` |
| `test_dispatch_markduplicates_extracts_real_dup_pct` | `MARKDUPLICATES` | `out.dup_metrics` | `duplicate_pct ≈ 15.0` |
| `test_dispatch_cellranger_extracts_real_cell_count` | `CELLRANGER_COUNT` | `metrics_summary.csv` | `estimated_cells = 5000` |
| `test_dispatch_macs2_counts_real_peaks` | `MACS2_CALLPEAK` | `out.narrowPeak` | `peak_count = 250` |
| `test_dispatch_kraken2_extracts_real_classified_pct` | `KRAKEN2_KRAKEN2` | `out.report` | `classified_pct = 72.5` |
| `test_dispatch_hisat2_extracts_real_alignment_rate` | `HISAT2_ALIGN` | `hisat2.log` | `alignment_rate ≈ 85.2` |
| `test_dispatch_bwa_mem_extracts_alignment_rate` | `BWA_MEM` | `bwa.log` | `alignment_rate ≈ 92.3` |
| `test_bug6_process_upper_defined_for_rna_seq_processes` | `FASTQC` | — | `_check_qc_thresholds` does not NameError (Bug 6 regression) |

### `TestRNASeqMultiFailure` (6 tests)
Multi-metric failure scenarios: more than one metric below threshold → multiple failure dicts in one SSE event.

| Test | Process | Failures | Verified |
|---|---|---|---|
| `test_fastp_both_low_reads_and_low_q30_emit_two_failures` | FASTP | `reads_surviving_pct` + `q30_rate` both low | 2 failures in event |
| `test_fastp_only_low_q30_emits_one_failure` | FASTP | only `q30_rate` low | exactly 1 failure |
| `test_flagstat_both_low_mapped_and_high_dup_emit_two_failures` | FLAGSTAT | `mapped_pct` low + `duplicate_pct` high | 2 failures |
| `test_cellranger_both_few_cells_and_low_genes_emit_two_failures` | CELLRANGER | `estimated_cells` + `median_genes_per_cell` both bad | 2 failures |
| `test_good_metrics_no_failures` | FASTP | all metrics pass | 0 failures; no SSE |
| `test_fastp_multi_failure_structured_keys_complete` | FASTP | both failures bad | each failure dict has all 5 required keys |

### `TestCTFDefocusBoundary` (9 tests)
Strict boundary tests for the CTF defocus validation range `(1000, 100000)` Å.

| Test | Defocus Value | Expected |
|---|---|---|
| `test_defocus_1001_accepted` | 1001 Å | Accepted (inside range) |
| `test_defocus_1000_rejected` | 1000 Å | Rejected (= lower bound, exclusive) |
| `test_defocus_999_rejected` | 999 Å | Rejected (below range) |
| `test_defocus_99999_accepted` | 99999 Å | Accepted |
| `test_defocus_100000_rejected` | 100000 Å | Rejected (= upper bound, exclusive) |
| `test_defocus_100001_rejected` | 100001 Å | Rejected (above range) |
| `test_invalid_last_line_falls_back_to_valid_earlier_line` | Multi-line; last line invalid | Falls back to last valid line |
| `test_astigmatism_is_absolute_difference` | defocus_u=5000, defocus_v=4000 | `astigmatism = abs(5000 - 4000) = 1000` |
| `test_fit_quality_clamped_to_0_1` | Raw fit > 1.0 | `fit_quality` clamped to 1.0 |
| `test_fit_quality_negative_clamped_to_zero` | Raw fit < 0 | `fit_quality` clamped to 0.0 |

### `TestPickingDuplicateFractionInvariant` (4 tests)
Documents known behaviour: `duplicate_fraction` is always 0.0 (STAR format does not include overlap data).

| Test | What It Documents |
|---|---|
| `test_duplicate_fraction_always_zero` | `_parse_particle_picking_metrics` always returns `duplicate_fraction = 0.0` |
| `test_picking_qc_gate_never_fires_on_duplicate_fraction_alone` | Gate threshold = 0.3; fraction always 0 → gate never fires for this metric |
| `test_picking_returns_none_when_no_coordinate_files` | No `.star` or `.box` file → `None` |
| `test_picking_counts_only_coordinate_lines` | Comment and header lines in `.star` not counted as particles |

### `TestEndToEndFileToSSE` (6 tests)
Full pipeline: write file on disk → call `handle_process_completion` → verify SSE event content.

| Test | Tool | File | Verified |
|---|---|---|---|
| `test_fastp_low_survival_triggers_sse_with_suggestions` | FASTP | `fastp.json` | SSE fires; suggestions include `quality_cutoff` |
| `test_fastp_good_metrics_no_sse_fired` | FASTP | `fastp.json` (85% surviving) | No SSE |
| `test_featurecounts_low_assignment_triggers_sse` | featureCounts | `fc.summary` | SSE fires; `assigned_pct` in metrics |
| `test_missing_work_dir_no_sse` | any | work_dir does not exist | No SSE, no crash |
| `test_sse_event_has_process_name_and_timestamp` | FASTP | `fastp.json` (bad) | Event has `process_name` and valid `timestamp` |
| `test_kraken2_low_classified_triggers_sse` | Kraken2 | `out.report` | SSE fires; `classified_pct` in failures |

### `TestUncoveredPaths` (17 tests)
Covers code paths that had no tests before the final audit round.

#### MultiQC JSON (5 tests)
File: `multiqc_data.json` (MultiQC aggregated output)

| Test | Verified |
|---|---|
| `test_multiqc_json_gc_content_extracted` | `multiqc_data.json` → `gc_content_pct` extracted |
| `test_multiqc_json_avg_read_length_extracted` | `multiqc_data.json` → `avg_read_length` extracted |
| `test_multiqc_json_does_not_overwrite_direct_gc` | If direct `fastqc_data.txt` also present, its GC value takes precedence |
| `test_multiqc_json_malformed_gracefully_skipped` | Corrupt JSON → skipped (no crash) |
| `test_multiqc_json_empty_stats_list_skipped` | `report_general_stats_data = []` → nothing extracted (no IndexError) |

#### STARsolo (2 tests)
File: `Summary.csv` (different from CellRanger's `metrics_summary.csv`)

| Test | Verified |
|---|---|
| `test_starsolo_summary_csv_cells_detected` | `Summary.csv` → `estimated_cells` extracted |
| `test_starsolo_summary_csv_returns_none_when_absent` | No `Summary.csv` → `None` |

#### Peak file formats (3 tests)
Files: `*.broadPeak`, `summits.bed`, `*.narrowPeak`

| Test | File | Verified |
|---|---|---|
| `test_broadpeak_line_count` | `out.broadPeak` (6 data lines) | `peak_count = 6` |
| `test_summits_bed_line_count` | `summits.bed` (4 non-comment lines) | `peak_count = 4` |
| `test_narrowpeak_takes_priority_over_summits` | both files present | narrowPeak count used (not summits) |

#### Bug 8 regression — STAR incomplete log (3 tests)

| Test | Condition | Verified |
|---|---|---|
| `test_star_no_multiloci_line_alignment_rate_equals_uniquely_mapped` | Log has only "Uniquely mapped" line | `alignment_rate = uniquely_mapped_pct` (fallback) |
| `test_star_with_multiloci_line_alignment_rate_is_sum` | Full log with both lines | `alignment_rate = uniquely + multi_loci` |
| `test_star_incomplete_log_gate_fires_correctly` | No multi-loci line, unique = 45% | Gate fires (45% < 60% threshold) |

#### Intentional defaults (4 tests)

| Test | Verified |
|---|---|
| `test_motion_suggester_absent_drift_no_drift_suggestion` | `total_drift_angstrom` absent → no suggestion (safe default=0) |
| `test_motion_suggester_absent_correlation_no_frames_suggestion` | `correlation_score` absent → no frames suggestion |
| `test_motion_suggester_zero_drift_is_safe_default` | drift=0 → below 50 threshold → no false event |

---

## File 4: `test_qc_e2e_domains.py`
**73 tests** across 7 classes — Multi-domain researcher personas

Each persona class writes realistic tool output files, submits them through `handle_process_completion`, and asserts on SSE event content including failure metrics and parameter suggestions.

### `TestAliceRNASeq` (14 tests)
Alice is an RNA-seq researcher running a bulk transcriptomics pipeline.
**Workflow**: FASTP → STAR_ALIGN → FEATURECOUNTS → SALMON

| Test | Process | File | Condition | Expected |
|---|---|---|---|---|
| `test_alice_fastp_low_survival_fires_gate` | FASTP | `fastp.json` (60% surviving) | below 70% | SSE fires |
| `test_alice_fastp_suggests_quality_cutoff_increase` | FASTP | same | low survival | `quality_cutoff` suggestion present |
| `test_alice_star_low_alignment_fires_gate` | STAR_ALIGN | `Log.final.out` (45%) | below 60% | SSE fires |
| `test_alice_star_suggests_twopass_mode` | STAR_ALIGN | same | low mapping | `twopass_mode` suggestion |
| `test_alice_featurecounts_low_assignment_fires_gate` | FEATURECOUNTS | `fc.summary` (30%) | below 50% | SSE fires |
| `test_alice_featurecounts_suggests_strandedness_change` | FEATURECOUNTS | same | low assignment | `strandedness` suggestion |
| `test_alice_salmon_low_mapping_fires_gate` | SALMON | `meta_info.json` (35%) | below 50% | SSE fires |
| `test_alice_salmon_suggests_decoy_aware` | SALMON | same | low mapping | `decoy_aware` or `gcbias` suggestion |
| `test_alice_good_fastp_no_gate` | FASTP | `fastp.json` (85%) | above 70% | No SSE |
| `test_alice_good_star_no_gate` | STAR_ALIGN | `Log.final.out` (92%) | above 60% | No SSE |
| `test_alice_good_featurecounts_no_gate` | FEATURECOUNTS | `fc.summary` (78%) | above 50% | No SSE |
| `test_alice_good_salmon_no_gate` | SALMON | `meta_info.json` (92%) | above 50% | No SSE |
| `test_alice_full_bad_run_fires_four_gates` | all 4 steps | all bad | all bad | 4 SSE events |
| `test_alice_full_good_run_fires_zero_gates` | all 4 steps | all good | all good | 0 SSE events |

### `TestBobDNASeq` (8 tests)
Bob is a DNA-seq researcher running a variant-calling pipeline.
**Workflow**: BWA_MEM → SAMTOOLS_FLAGSTAT → MARKDUPLICATES

| Test | Process | File | Condition | Expected |
|---|---|---|---|---|
| `test_bob_bwa_low_alignment_fires_gate` | BWA_MEM | `bwa.log` (75%) | below 90% | SSE fires |
| `test_bob_bwa_suggests_shorter_seed` | BWA_MEM | same | low mapping | `seed_length` suggestion |
| `test_bob_flagstat_high_dup_fires_gate` | FLAGSTAT | `out.flagstat` (45% dup) | above 30% | SSE fires |
| `test_bob_flagstat_suggests_remove_duplicates` | FLAGSTAT | same | high dup | `remove_duplicates` suggestion |
| `test_bob_picard_high_dup_fires_gate` | MARKDUPLICATES | `out.dup_metrics` (42%) | above 30% | SSE fires |
| `test_bob_picard_suggests_optical_pixel_distance` | MARKDUPLICATES | same | high optical dup | `optical_duplicate_pixel_distance` suggestion |
| `test_bob_good_run_no_gates` | all | all good | all pass | 0 SSE events |
| `test_bob_full_bad_run_fires_three_gates` | all 3 steps | all bad | all bad | 3 SSE events |

### `TestCarolSingleCell` (8 tests)
Carol is a single-cell RNA-seq researcher.
**Workflow**: CELLRANGER_COUNT

| Test | File | Condition | Expected |
|---|---|---|---|
| `test_carol_few_cells_fires_gate` | `metrics_summary.csv` (200 cells) | below 500 | SSE fires |
| `test_carol_few_cells_suggests_expected_cells_reduction` | same | few cells | `expected_cells` suggestion |
| `test_carol_few_cells_suggests_lower_umi_cutoff` | same | few cells | `umi_cutoff` suggestion |
| `test_carol_low_genes_fires_gate` | `metrics_summary.csv` (500 genes) | below 1000 | SSE fires |
| `test_carol_low_genes_suggests_min_genes_reduction` | same | few genes | `min_genes` suggestion |
| `test_carol_good_run_no_gate` | `metrics_summary.csv` (5000 cells, 2500 genes) | all pass | No SSE |
| `test_carol_comma_escaped_cell_count_parsed_correctly` | `"4,521"` in CSV | comma-escaped | `estimated_cells = 4521` (Bug 7 in parsing) |
| `test_carol_both_failures_produce_two_failures` | both bad | both fail | 2 failures in 1 event |

### `TestDaveChIPSeq` (6 tests)
Dave is a chromatin accessibility researcher running MACS2 peak-calling.
**Workflow**: MACS2_CALLPEAK

| Test | File | Condition | Expected |
|---|---|---|---|
| `test_dave_few_peaks_fires_gate` | `out.narrowPeak` (500 peaks) | below 1000 | SSE fires |
| `test_dave_suggests_relaxed_qvalue` | same | few peaks | `qvalue` suggestion (increase) |
| `test_dave_suggests_extsize_reduction` | same | few peaks | `extsize` suggestion |
| `test_dave_good_run_no_gate` | `out.narrowPeak` (5000 peaks) | above 1000 | No SSE |
| `test_dave_peaks_counted_excluding_comment_lines` | file with `#` comment lines | 5000 data + 10 comments | `peak_count = 5000` |
| `test_dave_qvalue_already_at_max_no_qvalue_suggestion` | few peaks; `qvalue=0.5` already | at max | No qvalue suggestion |

### `TestEveMetagenomics` (7 tests)
Eve is a metagenomics researcher classifying environmental samples.
**Workflow**: KRAKEN2_KRAKEN2, BRACKEN_BRACKEN

| Test | Process | File | Condition | Expected |
|---|---|---|---|---|
| `test_eve_kraken2_low_classification_fires_gate` | KRAKEN2 | `out.report` (30%) | below 50% | SSE fires |
| `test_eve_kraken2_suggests_remove_confidence_threshold` | KRAKEN2 | same | low classified | `confidence_threshold` reduction suggestion |
| `test_eve_kraken2_suggests_larger_database` | KRAKEN2 | same | low classified | `database` suggestion |
| `test_eve_bracken_low_classified_fires_gate` | BRACKEN | `out.report` (40%) | below 50% | SSE fires |
| `test_eve_good_run_no_gate` | KRAKEN2 | `out.report` (72%) | above 50% | No SSE |
| `test_eve_zero_confidence_already_no_suggestion` | KRAKEN2 | bad report | `confidence_threshold=0` | No confidence suggestion (already at minimum) |

### `TestFrankCryoEM` (11 tests)
Frank is a structural biologist running a cryo-EM SPA pipeline.
**Workflow**: MOTION_CORRECTION → CTF_ESTIMATION → PARTICLE_PICKING

| Test | Process | File | Condition | Expected |
|---|---|---|---|---|
| `test_frank_motion_high_drift_fires_gate` | MOTION_CORRECTION | `motion.log` (85 Å) | above 50 Å | SSE fires |
| `test_frank_motion_suggests_dose_weighting_or_patch_size` | MOTION_CORRECTION | same | high drift | `dose_weighting` or `patch_size` suggestion |
| `test_frank_ctf_high_astigmatism_fires_gate` | CTF_ESTIMATION | `_ctf.txt` | astigmatism > 500 | SSE fires |
| `test_frank_ctf_bad_fit_also_fires` | CTF_ESTIMATION | `_ctf.txt` | fit_quality < 0.1 | SSE fires |
| `test_frank_picking_too_few_fires_gate` | PARTICLE_PICKING | `*.star` (42 particles) | below 100 | SSE fires |
| `test_frank_picking_suggests_lower_threshold` | PARTICLE_PICKING | same | too few | `picking_threshold` reduction |
| `test_frank_good_motion_no_gate` | MOTION_CORRECTION | `motion.log` (10 Å) | below 50 Å | No SSE |
| `test_frank_good_ctf_no_gate` | CTF_ESTIMATION | `_ctf.txt` (good) | all pass | No SSE |
| `test_frank_good_picking_no_gate` | PARTICLE_PICKING | `*.star` (500 particles) | above 100 | No SSE |
| `test_frank_full_bad_run_fires_three_gates` | all 3 steps | all bad | all fail | 3 SSE events |
| `test_frank_full_good_run_zero_gates` | all 3 steps | all good | all pass | 0 SSE events |

### `TestDomainFactory` (20 tests)
Tests the `get_suggester_for_domain()` factory function with all known domain strings.

#### Correct routing (15 parametrized tests)

| Domain String | Expected Class |
|---|---|
| `rnaseq` | `RNASeqParameterSuggester` |
| `rna_seq` | `RNASeqParameterSuggester` |
| `bulk_rnaseq` | `RNASeqParameterSuggester` |
| `dna_seq` | `GenomicsParameterSuggester` |
| `wgs_variant_calling` | `GenomicsParameterSuggester` |
| `wes_gatk` | `GenomicsParameterSuggester` |
| `single_cell_rnaseq` | `SingleCellParameterSuggester` |
| `scrna_seq` | `SingleCellParameterSuggester` |
| `chip_seq` | `ChIPSeqParameterSuggester` |
| `atac_seq` | `ChIPSeqParameterSuggester` |
| `metagenomics_wgs` | `MetagenomicsParameterSuggester` |
| `kraken2_pipeline` | `MetagenomicsParameterSuggester` |
| `cryo_em` | `CryoEMParameterSuggester` |
| `cryosparc_spa` | `CryoEMParameterSuggester` |
| `em` | `CryoEMParameterSuggester` |

#### Bug 7 regression — false `_em` routes (4 parametrized tests)
These domain strings contain `em` or `_em` as a substring but must NOT route to cryo-EM.

| Domain | Why It Was a Bug | Expected |
|---|---|---|
| `genome_assembly` | `"genome"` contains `"em"` but not `"_em"` | Not cryo-EM |
| `system_biology` | `"system"` ends with `"em"` | Not cryo-EM |
| `theorem_prover` | `"theorem"` contains `"em"` | Not cryo-EM |
| `item_embedding` | `"item_em"` contains `"_em"` at non-boundary | Not cryo-EM |

#### Cross-domain uniqueness (1 test)
`test_all_six_domains_return_distinct_suggester_types` — all 6 domains return 6 distinct class types.

---

## Production Bugs Found and Fixed

| Bug | File | Description | Fix |
|---|---|---|---|
| Bug 1 | `qc_trace_monitor.py` | Ambiguous regex: a single log line matching both "Total motion" and correlation patterns could corrupt one metric | Added negative lookahead to separate regexes |
| Bug 2 | `qc_trace_monitor.py` | `KeyError` in ab initio / refinement suggester: `resolution_angstrom` or `fsc_0143` accessed without `.get()` | Replaced dict access with `.get()` + guard |
| Bug 3 | `qc_trace_monitor.py` | NF-Core qualified names (`NFCORE:MOTION_CORRECTION`) not matched by keyword checks | Used `in` substring check after `split(":")[-1]` |
| Bug 4 | `qc_trace_monitor.py` | Multi-micrograph CTF files: last line often invalid; parser used last line unconditionally | Added validation loop; falls back to last valid 8-column line |
| Bug 5 | `parameter_suggester.py` | `"_em"` substring matched `item_embedding`, `genome_assembly`, etc. → false cryo-EM routing | Replaced with `re.search(r"_em(?:[^a-z]\|$)", domain)` |
| Bug 6 | `qc_trace_monitor.py` | `process_upper` referenced in `_check_qc_thresholds` before being defined → `NameError` for all RNA-seq / DNA-seq / scRNA processes | Added `process_upper = process_name.upper()` at top of method |
| Bug 7 | `qc_trace_monitor.py` | CellRanger `metrics_summary.csv` has comma-escaped numbers (`"4,521"`) → `int("4,521")` raises `ValueError` | Added `.replace(",", "")` before `int()` conversion |
| Bug 8 | `qc_trace_monitor.py` | STAR `Log.final.out` may lack "% of reads mapped to multiple loci" line → `alignment_rate` never set → threshold check skipped | Added fallback: if `uniquely_mapped_pct` set but `alignment_rate` absent, `alignment_rate = uniquely_mapped_pct` |

---

## Test Count Progression

| Milestone | Tests | Notes |
|---|---|---|
| Initial implementation | 0 | Core `qc_trace_monitor.py` + `parameter_suggester.py` written |
| First smoke tests | 7 | `test_gap3_standalone.py` — basic cryo-EM + RNA-seq + JSON |
| Gap3 integration tests | 17 | `test_gap3_complete_integration.py` — real-file E2E, SSE contract |
| Edge case suite | 135 | `test_qc_edge_cases.py` — status filtering, boundaries, parsers, suggesters |
| Universal parsers + Bug 6 | 191 | `TestUniversalQCParsers` added (56 tests); Bug 6 NameError found and fixed |
| Audit round 1 | 217 | Multi-failure, CTF boundary, picking invariant, file→SSE E2E added |
| Domain personas (E2E) | 290 | `test_qc_e2e_domains.py` — 6 researcher personas, Bugs 5 & 7 found/fixed |
| Hollow test replacement | 303 | Gap3 integration rewritten; `TestProcessNameVariants` upgraded |
| Audit round 2 + Bug 8 | **319** | Bug 8 fixed; dispatch→real-file upgrade; `TestUncoveredPaths` added |

---

## Running the Tests

```bash
# From /home/yzhang/biomate/backend/
.venv/bin/python -m pytest tests/test_gap3_complete_integration.py \
                           tests/test_gap3_standalone.py \
                           tests/test_qc_edge_cases.py \
                           tests/test_qc_e2e_domains.py \
                           -v --tb=short

# Expected: 319 passed in ~15s
```

**Files under test** (production code):
- `backend/lib/galaxy/jobs/qc_trace_monitor.py` — `NextflowQCGateHandler` class
- `backend/lib/galaxy/jobs/parameter_suggester.py` — 6 suggester classes + factory
