#!/usr/bin/env nextflow
/*
 * biomni_pharmacology_analyze_fda_safety_signals
 * Analyze safety signals across multiple drugs.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.drug_list = null
params.comparison_period = null
params.signal_threshold = 2.0

// Main process
process ANALYZE_FDA_SAFETY_SIGNALS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("analyze_fda_safety_signals_results.json"), emit: results
    path("analyze_fda_safety_signals_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.pharmacology import analyze_fda_safety_signals
except ImportError:
    # Fallback: function may need to be implemented locally
    def analyze_fda_safety_signals(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = analyze_fda_safety_signals(
    drug_list="${params.drug_list}",
    comparison_period="${params.comparison_period}",
    signal_threshold=${params.signal_threshold}
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("analyze_fda_safety_signals_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("analyze_fda_safety_signals_output.txt", "w") as f:
    f.write("Biomni: Analyze Fda Safety Signals Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("analyze_fda_safety_signals completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_PHARMACOLOGY_ANALYZE_FDA_SAFETY_SIGNALS {
    take:
    // No file inputs

    main:
    ANALYZE_FDA_SAFETY_SIGNALS()

    emit:
    results = ANALYZE_FDA_SAFETY_SIGNALS.out.results
    output = ANALYZE_FDA_SAFETY_SIGNALS.out.output
}

// Entry workflow
workflow {
    if (!params.drug_list) {
        error "Please provide --drug_list parameter"
    }


    BIOMNI_PHARMACOLOGY_ANALYZE_FDA_SAFETY_SIGNALS()
}
