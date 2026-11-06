#!/usr/bin/env nextflow
/*
 * pharmacology/biomarker_patient_enrichment
 *
 * Biomarker-driven patient enrichment analysis for the Phase II -> III transition.
 * Identifies predictive biomarkers (those that predict whether a patient will respond
 * to treatment) from Phase II clinical trial data and computes the patient-count
 * savings achievable by enrolling only biomarker-positive patients in the pivotal trial.
 *
 * Computations:
 *   1. Biomarker screening -- logistic (binary) or linear (continuous) regression per
 *      biomarker; reports OR/HR with 95 % CI, p-value, and FDR-adjusted q-value
 *      (Benjamini-Hochberg).
 *   2. Optimal cut-point analysis -- Youden's J statistic over continuous biomarkers
 *      to find the threshold that maximises sensitivity + specificity - 1.
 *   3. Enrichment metrics per biomarker:
 *        ER  -- enrichment ratio (response rate BM+ / response rate BM-)
 *        NNT -- number needed to treat (1 / ARR)
 *        PEF -- predictive enrichment factor (% of all responders captured in BM+)
 *        NNS -- number needed to screen per responder enrolled
 *   4. Phase III power analysis -- two-proportion z-test sample size with vs without
 *      biomarker enrichment, showing absolute patient-count savings.
 *   5. Structured output -- JSON results + plain-English regulatory narrative + CSV
 *      sample-size comparison table.
 *
 * References:
 *   - Sargent DJ et al. A Generic Predictive Biomarker Analysis Framework. J Natl
 *     Cancer Inst. 2005.
 *   - Simon R. Biomarker-based clinical trial designs. Cancer Biomarkers. 2010.
 *   - FDA Enrichment Strategies for Clinical Trials guidance (2019).
 *   - Youden WJ. Index for rating diagnostic tests. Cancer. 1950.
 *   - Benjamini Y, Hochberg Y. Controlling the false discovery rate. JRSS-B. 1995.
 *
 * Inputs:
 *   --patient_data_json   JSON array of {patient_id, response, biomarker_1, ...}
 *   --response_type       "binary" (0/1) or "continuous" (default: "binary")
 *   --alpha               Significance level (default: 0.05)
 *   --phase3_power        Target power for Phase III (default: 0.80)
 *   --phase3_alpha        Phase III significance level, one-sided (default: 0.025)
 *
 * Outputs:
 *   biomarker_enrichment_results.json    -- per-biomarker enrichment metrics + statistics
 *   enrichment_summary.txt              -- plain-English narrative for regulatory submission
 *   phase3_sample_size_comparison.csv   -- unenriched vs enriched Phase III sample sizes
 */

nextflow.enable.dsl = 2

params.outdir             = './results'
params.patient_data_json  = 'null'
params.response_type      = 'binary'
params.alpha              = '0.05'
params.phase3_power       = '0.80'
params.phase3_alpha       = '0.025'

process BIOMARKER_PATIENT_ENRICHMENT {
    tag "$meta.id"
    label 'process_low'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("biomarker_enrichment_results.json"),  emit: results
    tuple val(meta), path("enrichment_summary.txt"),             emit: summary
    tuple val(meta), path("phase3_sample_size_comparison.csv"),  emit: sample_size
    tuple val(meta), path("qc_metrics.json"),                    emit: qc_metrics
    path "versions.yml",                                         emit: versions

    // integrity: was an RNG stub fabricating results; honest-fail (no real implementation).
    script:
    """
    export PARAM_PATIENT_DATA='${params.patient_data_json}'
    export PARAM_RESPONSE_TYPE='${params.response_type}'
    export PARAM_ALPHA='${params.alpha}'
    export PARAM_P3_POWER='${params.phase3_power}'
    export PARAM_P3_ALPHA='${params.phase3_alpha}'

    python3 << 'PYEOF'
import sys
sys.stderr.write("ERROR: biomarker_patient_enrichment is not implemented against a real cohort — it requires a real Phase II clinical trial dataset (per-patient measured response outcomes and measured biomarker values). No such data is supplied here; the previous implementation fabricated patient responses and biomarker values via RNG. Refusing to emit fabricated OR/enrichment Phase II findings.\\n")
sys.exit(1)
PYEOF

    cat << 'EOF' > versions.yml
biomarker_patient_enrichment:
  python: "3.10"
  scipy: ">=1.10"
  numpy: ">=1.24"
  statsmodels: ">=0.14"
  references: >
    Sargent 2005 JNCI; Simon 2010 Cancer Biomarkers;
    FDA Enrichment Strategies Guidance 2019;
    Youden 1950; Benjamini & Hochberg 1995
EOF
    """
}

workflow BIOMARKER_PATIENT_ENRICHMENT_WORKFLOW {
    take: meta_ch
    main: BIOMARKER_PATIENT_ENRICHMENT(meta_ch)
    emit:
        results     = BIOMARKER_PATIENT_ENRICHMENT.out.results
        summary     = BIOMARKER_PATIENT_ENRICHMENT.out.summary
        sample_size = BIOMARKER_PATIENT_ENRICHMENT.out.sample_size
}

workflow {
    meta = [id: 'biomarker_enrichment_run', single_end: false]
    Channel.value(meta) | BIOMARKER_PATIENT_ENRICHMENT_WORKFLOW
}
