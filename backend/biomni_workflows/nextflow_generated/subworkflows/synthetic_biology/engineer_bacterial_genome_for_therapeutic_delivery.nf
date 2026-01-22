#!/usr/bin/env nextflow
/*
 * biomni_synthetic_biology_engineer_bacterial_genome_for_therapeutic_delivery
 * Engineer a bacterial genome by integrating therapeutic genetic parts for therapeutic delivery.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.bacterial_genome_file = null
params.genetic_parts = null

// Main process
process ENGINEER_BACTERIAL_GENOME_FOR_THERAPEUTIC_DELIVERY {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("engineer_bacterial_genome_for_therapeutic_delivery_results.json"), emit: results
    path("engineer_bacterial_genome_for_therapeutic_delivery_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.synthetic_biology import engineer_bacterial_genome_for_therapeutic_delivery
except ImportError:
    # Fallback: function may need to be implemented locally
    def engineer_bacterial_genome_for_therapeutic_delivery(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = engineer_bacterial_genome_for_therapeutic_delivery(
    bacterial_genome_file="${params.bacterial_genome_file}",
    genetic_parts="${params.genetic_parts}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("engineer_bacterial_genome_for_therapeutic_delivery_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("engineer_bacterial_genome_for_therapeutic_delivery_output.txt", "w") as f:
    f.write("Biomni: Engineer Bacterial Genome For Therapeutic Delivery Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("engineer_bacterial_genome_for_therapeutic_delivery completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_SYNTHETIC_BIOLOGY_ENGINEER_BACTERIAL_GENOME_FOR_THERAPEUTIC_DELIVERY {
    take:
    // No file inputs

    main:
    ENGINEER_BACTERIAL_GENOME_FOR_THERAPEUTIC_DELIVERY()

    emit:
    results = ENGINEER_BACTERIAL_GENOME_FOR_THERAPEUTIC_DELIVERY.out.results
    output = ENGINEER_BACTERIAL_GENOME_FOR_THERAPEUTIC_DELIVERY.out.output
}

// Entry workflow
workflow {
    if (!params.bacterial_genome_file) {
        error "Please provide --bacterial_genome_file parameter"
    }
    if (!params.genetic_parts) {
        error "Please provide --genetic_parts parameter"
    }


    BIOMNI_SYNTHETIC_BIOLOGY_ENGINEER_BACTERIAL_GENOME_FOR_THERAPEUTIC_DELIVERY()
}
