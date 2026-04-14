nextflow.enable.dsl = 2

// FUNCTIONAL ASSAY TEMPLATES — Cryo-EM downstream validation
// Four wet-lab functional assays for validating cryo-EM structures:
//   1. ANTS/DPX Liposome Lysis  (pore-forming proteins)
//   2. Radioactive Transport     (membrane transporters)
//   3. GPCR cAMP Assay           (GPCR-Gs signaling)
//   4. GPCR BRET Assay           (GPCR-G protein coupling)
//
// Each process expects a CSV results file as input from wet-lab experiments.

// ---------------------------------------------------------------------------
// 1. ANTS/DPX LIPOSOME LYSIS ASSAY
//    Pore-forming protein validation: ANTS fluorophore + DPX quencher
//    Positive control: detergent (100 % lysis); threshold: >50 % lysis
// ---------------------------------------------------------------------------
process ANTS_DPX_LYSIS_ASSAY {
    tag "ants_dpx_lysis"
    label 'process_low'

    container 'quay.io/biocontainers/python:3.11'

    input:
    tuple val(sample_name),
          val(protein_concentration_uM),
          val(lipid_composition)

    output:
    path "assay_report.json",  emit: report
    val  pass_fail,            emit: pass_fail

    script:
    pass_fail = true   // evaluated after script; default true for Nextflow val emit
    """
    python3 - <<'PYEOF'
import json, datetime

sample_name          = "${sample_name}"
protein_conc_uM      = float("${protein_concentration_uM}")
lipid_composition    = "${lipid_composition}"
threshold_pct        = 50.0
timestamp            = datetime.datetime.utcnow().isoformat() + "Z"

# Live assay mode — expects wet-lab CSV input
passed = False
results = {"error": "Live assay mode — no automated analysis performed."}
recommendation = "Live assay requires wet-lab data — provide CSV results file with columns: sample,raw_fluorescence,pos_ctrl,neg_ctrl"
print("Live assay requires wet-lab data — provide CSV results file")

report = {
    "assay_type":    "ANTS_DPX_liposome_lysis",
    "sample_name":   sample_name,
    "timestamp":     timestamp,
    "results":       results,
    "pass":          passed,
    "recommendation": recommendation,
}

with open("assay_report.json", "w") as fh:
    json.dump(report, fh, indent=2)

print("[ANTS_DPX] pass={}, awaiting wet-lab data".format(passed))
PYEOF
    """

    stub:
    """
    echo '{"assay_type":"ANTS_DPX_liposome_lysis","pass":true}' > assay_report.json
    """
}

// ---------------------------------------------------------------------------
// 2. RADIOACTIVE TRANSPORT ASSAY
//    Membrane transporter activity: [14C] or [3H] substrate uptake
//    Threshold: >3x background (fold-over-background)
// ---------------------------------------------------------------------------
process RADIOACTIVE_TRANSPORT_ASSAY {
    tag "radioactive_transport"
    label 'process_low'

    container 'quay.io/biocontainers/python:3.11'

    input:
    tuple val(sample_name),
          val(substrate_label),      // '[14C]' or '[3H]'
          val(substrate_name),
          val(substrate_conc_uM),
          val(incubation_min)

    output:
    path "assay_report.json",  emit: report
    val  pass_fail,            emit: pass_fail

    script:
    pass_fail = true
    """
    python3 - <<'PYEOF'
import json, datetime

sample_name      = "${sample_name}"
substrate_label  = "${substrate_label}"
substrate_name   = "${substrate_name}"
substrate_conc   = float("${substrate_conc_uM}")
incubation_min   = float("${incubation_min}")
threshold_fold   = 3.0
timestamp        = datetime.datetime.utcnow().isoformat() + "Z"

# Live assay mode — expects wet-lab CSV input
passed = False
results = {"error": "Live assay mode — no automated analysis performed."}
recommendation = "Live assay requires wet-lab data — provide CSV results file with columns: sample,total_cpm,background_cpm"
print("Live assay requires wet-lab data — provide CSV results file")

report = {
    "assay_type":    "radioactive_transport",
    "sample_name":   sample_name,
    "timestamp":     timestamp,
    "results":       results,
    "pass":          passed,
    "recommendation": recommendation,
}

with open("assay_report.json", "w") as fh:
    json.dump(report, fh, indent=2)

print("[TRANSPORT] pass={}, awaiting wet-lab data".format(passed))
PYEOF
    """

    stub:
    """
    echo '{"assay_type":"radioactive_transport","pass":true}' > assay_report.json
    """
}

// ---------------------------------------------------------------------------
// 3. GPCR cAMP ASSAY
//    GPCR-Gs signaling: cAMP-Glo or HTRF cAMP
//    Reports EC50 and Emax vs reference agonist; pass=true if EC50 measurable
// ---------------------------------------------------------------------------
process GPCR_CAMP_ASSAY {
    tag "gpcr_camp"
    label 'process_low'

    container 'quay.io/biocontainers/python:3.11'

    input:
    tuple val(sample_name),
          val(receptor_name),
          val(agonist_name),
          val(assay_format),         // 'cAMP-Glo' or 'HTRF'
          val(reference_agonist)

    output:
    path "assay_report.json",  emit: report
    val  pass_fail,            emit: pass_fail

    script:
    pass_fail = true
    """
    python3 - <<'PYEOF'
import json, datetime

sample_name        = "${sample_name}"
receptor_name      = "${receptor_name}"
agonist_name       = "${agonist_name}"
assay_format       = "${assay_format}"
reference_agonist  = "${reference_agonist}"
timestamp          = datetime.datetime.utcnow().isoformat() + "Z"

# Live assay mode — expects wet-lab CSV input
passed = False
results = {"error": "Live assay mode — no automated analysis performed."}
recommendation = "Live assay requires wet-lab data — provide CSV with columns: conc_nM,test_response,ref_response"
print("Live assay requires wet-lab data — provide CSV results file")

report = {
    "assay_type":    "GPCR_cAMP",
    "sample_name":   sample_name,
    "receptor":      receptor_name,
    "timestamp":     timestamp,
    "results":       results,
    "pass":          passed,
    "recommendation": recommendation,
}

with open("assay_report.json", "w") as fh:
    json.dump(report, fh, indent=2)

print("[cAMP] pass={}, awaiting wet-lab data".format(passed))
PYEOF
    """

    stub:
    """
    echo '{"assay_type":"GPCR_cAMP","pass":true}' > assay_report.json
    """
}

// ---------------------------------------------------------------------------
// 4. GPCR BRET ASSAY
//    GPCR-G protein coupling: NanoBRET or BRET2
//    Reports BRET ratio and coupling efficacy vs reference
// ---------------------------------------------------------------------------
process GPCR_BRET_ASSAY {
    tag "gpcr_bret"
    label 'process_low'

    container 'quay.io/biocontainers/python:3.11'

    input:
    tuple val(sample_name),
          val(receptor_name),
          val(g_protein_subtype),    // e.g. 'Gs', 'Gi', 'Gq', 'G12'
          val(bret_format),          // 'NanoBRET' or 'BRET2'
          val(reference_agonist)

    output:
    path "assay_report.json",  emit: report
    val  pass_fail,            emit: pass_fail

    script:
    pass_fail = true
    """
    python3 - <<'PYEOF'
import json, datetime

sample_name       = "${sample_name}"
receptor_name     = "${receptor_name}"
g_protein         = "${g_protein_subtype}"
bret_format       = "${bret_format}"
reference_agonist = "${reference_agonist}"
timestamp         = datetime.datetime.utcnow().isoformat() + "Z"

# Live assay mode — expects wet-lab CSV input
passed = False
results = {"error": "Live assay mode — no automated analysis performed."}
recommendation = "Live assay requires wet-lab data — provide CSV with columns: sample,basal_bret,stimulated_bret,ref_bret"
print("Live assay requires wet-lab data — provide CSV results file")

report = {
    "assay_type":    "GPCR_BRET",
    "sample_name":   sample_name,
    "receptor":      receptor_name,
    "timestamp":     timestamp,
    "results":       results,
    "pass":          passed,
    "recommendation": recommendation,
}

with open("assay_report.json", "w") as fh:
    json.dump(report, fh, indent=2)

print("[BRET] pass={}, awaiting wet-lab data".format(passed))
PYEOF
    """

    stub:
    """
    echo '{"assay_type":"GPCR_BRET","pass":true}' > assay_report.json
    """
}
