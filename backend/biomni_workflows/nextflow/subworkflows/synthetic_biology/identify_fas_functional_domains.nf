#!/usr/bin/env nextflow
/*
 * biomni_synthetic_biology_identify_fas_functional_domains
 * Identifies functional domains within a Fatty Acid Synthase (FAS) sequence and predicts their roles.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.sequence = null
params.sequence_type = 'protein'
params.output_file = 'fas_domains_report.txt'

// Main process
process IDENTIFY_FAS_FUNCTIONAL_DOMAINS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("identify_fas_functional_domains_results.json"), emit: results
    path("identify_fas_functional_domains_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.synthetic_biology import identify_fas_functional_domains

# Run the tool
try:
    result = identify_fas_functional_domains(
    sequence="${params.sequence}",
    sequence_type="${params.sequence_type}",
    output_file="${params.output_file}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("identify_fas_functional_domains_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("identify_fas_functional_domains_output.txt", "w") as f:
    f.write("Biomni: Identify Fas Functional Domains Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("identify_fas_functional_domains completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_SYNTHETIC_BIOLOGY_IDENTIFY_FAS_FUNCTIONAL_DOMAINS {
    take:
    // No file inputs

    main:
    IDENTIFY_FAS_FUNCTIONAL_DOMAINS()

    emit:
    results = IDENTIFY_FAS_FUNCTIONAL_DOMAINS.out.results
    output = IDENTIFY_FAS_FUNCTIONAL_DOMAINS.out.output
}

// Entry workflow
workflow {
    if (!params.sequence) {
        error "Please provide --sequence parameter"
    }


    BIOMNI_SYNTHETIC_BIOLOGY_IDENTIFY_FAS_FUNCTIONAL_DOMAINS()
}
