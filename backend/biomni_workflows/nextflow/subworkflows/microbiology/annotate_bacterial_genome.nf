#!/usr/bin/env nextflow
/*
 * biomni_microbiology_annotate_bacterial_genome
 * Annotate a bacterial genome using Prokka to identify genes, proteins, and functional features.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.genome_file_path = null
params.output_dir = 'annotation_results'
params.genus = null
params.species = null
params.strain = null
params.prefix = null

// Main process
process ANNOTATE_BACTERIAL_GENOME {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("annotate_bacterial_genome_results.json"), emit: results
    path("annotate_bacterial_genome_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.microbiology import annotate_bacterial_genome

# Run the tool
try:
    result = annotate_bacterial_genome(
    genome_file_path="${params.genome_file_path}",
    output_dir="${params.output_dir}",
    genus="${params.genus}",
    species="${params.species}",
    strain="${params.strain}",
    prefix="${params.prefix}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("annotate_bacterial_genome_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("annotate_bacterial_genome_output.txt", "w") as f:
    f.write("Biomni: Annotate Bacterial Genome Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("annotate_bacterial_genome completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_MICROBIOLOGY_ANNOTATE_BACTERIAL_GENOME {
    take:
    // No file inputs

    main:
    ANNOTATE_BACTERIAL_GENOME()

    emit:
    results = ANNOTATE_BACTERIAL_GENOME.out.results
    output = ANNOTATE_BACTERIAL_GENOME.out.output
}

// Entry workflow
workflow {
    if (!params.genome_file_path) {
        error "Please provide --genome_file_path parameter"
    }


    BIOMNI_MICROBIOLOGY_ANNOTATE_BACTERIAL_GENOME()
}
