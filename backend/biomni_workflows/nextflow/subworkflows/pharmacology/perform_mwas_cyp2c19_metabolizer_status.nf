#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_perform_mwas_cyp2c19_metabolizer_status
 * Perform a Methylome-wide Association Study (MWAS) to identify CpG sites significantly associated with CYP2C19 metabolizer status.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.methylation_data_path = null
params.metabolizer_status_path = null
params.covariates_path = null
params.pvalue_threshold = '0.05'
params.output_file = 'significant_cpg_sites.csv'

// Main process
process PERFORM_MWAS_CYP2C19_METABOLIZER_STATUS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("perform_mwas_cyp2c19_metabolizer_status_results.json"), emit: results
    path("perform_mwas_cyp2c19_metabolizer_status_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.pharmacology import perform_mwas_cyp2c19_metabolizer_status

# Run the tool
try:
    result = perform_mwas_cyp2c19_metabolizer_status(
    methylation_data_path="${params.methylation_data_path}",
    metabolizer_status_path="${params.metabolizer_status_path}",
    covariates_path="${params.covariates_path}",
    pvalue_threshold="${params.pvalue_threshold}",
    output_file="${params.output_file}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("perform_mwas_cyp2c19_metabolizer_status_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("perform_mwas_cyp2c19_metabolizer_status_output.txt", "w") as f:
    f.write("Biomni: Perform Mwas Cyp2C19 Metabolizer Status Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("perform_mwas_cyp2c19_metabolizer_status completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_PHARMACOLOGY_PERFORM_MWAS_CYP2C19_METABOLIZER_STATUS {
    take:
    // No file inputs

    main:
    PERFORM_MWAS_CYP2C19_METABOLIZER_STATUS()

    emit:
    results = PERFORM_MWAS_CYP2C19_METABOLIZER_STATUS.out.results
    output = PERFORM_MWAS_CYP2C19_METABOLIZER_STATUS.out.output
}

// Entry workflow
workflow {
    if (!params.methylation_data_path) {
        error "Please provide --methylation_data_path parameter"
    }
    if (!params.metabolizer_status_path) {
        error "Please provide --metabolizer_status_path parameter"
    }


    BIOMNI_PHARMACOLOGY_PERFORM_MWAS_CYP2C19_METABOLIZER_STATUS()
}
