#!/usr/bin/env nextflow
/*
 * biomni_genetics_analyze_cas9_mutation_outcomes
 * Analyzes and categorizes mutations induced by Cas9 at target sites.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.reference_sequences = null
params.edited_sequences = null
params.cell_line_info = null
params.output_prefix = 'cas9_mutation_analysis'

// Main process
process ANALYZE_CAS9_MUTATION_OUTCOMES {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("analyze_cas9_mutation_outcomes_results.json"), emit: results
    path("analyze_cas9_mutation_outcomes_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.genetics import analyze_cas9_mutation_outcomes

# Run the tool
try:
    result = analyze_cas9_mutation_outcomes(
    reference_sequences="${params.reference_sequences}",
    edited_sequences="${params.edited_sequences}",
    cell_line_info="${params.cell_line_info}",
    output_prefix="${params.output_prefix}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_cas9_mutation_outcomes_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("analyze_cas9_mutation_outcomes_output.txt", "w") as f:
    f.write("Biomni: Analyze Cas9 Mutation Outcomes Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("analyze_cas9_mutation_outcomes completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_GENETICS_ANALYZE_CAS9_MUTATION_OUTCOMES {
    take:
    // No file inputs

    main:
    ANALYZE_CAS9_MUTATION_OUTCOMES()

    emit:
    results = ANALYZE_CAS9_MUTATION_OUTCOMES.out.results
    output = ANALYZE_CAS9_MUTATION_OUTCOMES.out.output
}

// Entry workflow
workflow {
    if (!params.reference_sequences) {
        error "Please provide --reference_sequences parameter"
    }
    if (!params.edited_sequences) {
        error "Please provide --edited_sequences parameter"
    }


    BIOMNI_GENETICS_ANALYZE_CAS9_MUTATION_OUTCOMES()
}
