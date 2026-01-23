#!/usr/bin/env nextflow
/*
 * biomni_genomics_interspecies_gene_conversion
 * Convert ENSEMBL gene IDs between different species using BioMart homology mapping.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.gene_list = null
params.source_species = null
params.target_species = null

// Main process
process INTERSPECIES_GENE_CONVERSION {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("interspecies_gene_conversion_results.json"), emit: results
    path("interspecies_gene_conversion_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.genomics import interspecies_gene_conversion

# Run the tool
try:
    result = interspecies_gene_conversion(
    gene_list="${params.gene_list}",
    source_species="${params.source_species}",
    target_species="${params.target_species}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("interspecies_gene_conversion_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("interspecies_gene_conversion_output.txt", "w") as f:
    f.write("Biomni: Interspecies Gene Conversion Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("interspecies_gene_conversion completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_GENOMICS_INTERSPECIES_GENE_CONVERSION {
    take:
    // No file inputs

    main:
    INTERSPECIES_GENE_CONVERSION()

    emit:
    results = INTERSPECIES_GENE_CONVERSION.out.results
    output = INTERSPECIES_GENE_CONVERSION.out.output
}

// Entry workflow
workflow {
    if (!params.gene_list) {
        error "Please provide --gene_list parameter"
    }
    if (!params.source_species) {
        error "Please provide --source_species parameter"
    }
    if (!params.target_species) {
        error "Please provide --target_species parameter"
    }


    BIOMNI_GENOMICS_INTERSPECIES_GENE_CONVERSION()
}
