#!/usr/bin/env nextflow
/*
 * biomni_genomics_find_enriched_motifs_with_homer
 * Find DNA sequence motifs enriched in genomic regions using the HOMER motif discovery software.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.peak_file = null
params.genome = 'hg38'
params.background_file = null
params.motif_length = '8,10,12'
params.output_dir = './homer_motifs'
params.num_motifs = '10'
params.threads = '4'

// Main process
process FIND_ENRICHED_MOTIFS_WITH_HOMER {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("find_enriched_motifs_with_homer_results.json"), emit: results
    path("find_enriched_motifs_with_homer_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.genomics import find_enriched_motifs_with_homer

# Run the tool
try:
    result = find_enriched_motifs_with_homer(
    peak_file="${params.peak_file}",
    genome="${params.genome}",
    background_file="${params.background_file}",
    motif_length="${params.motif_length}",
    output_dir="${params.output_dir}",
    num_motifs="${params.num_motifs}",
    threads="${params.threads}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("find_enriched_motifs_with_homer_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("find_enriched_motifs_with_homer_output.txt", "w") as f:
    f.write("Biomni: Find Enriched Motifs With Homer Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("find_enriched_motifs_with_homer completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_GENOMICS_FIND_ENRICHED_MOTIFS_WITH_HOMER {
    take:
    // No file inputs

    main:
    FIND_ENRICHED_MOTIFS_WITH_HOMER()

    emit:
    results = FIND_ENRICHED_MOTIFS_WITH_HOMER.out.results
    output = FIND_ENRICHED_MOTIFS_WITH_HOMER.out.output
}

// Entry workflow
workflow {
    if (!params.peak_file) {
        error "Please provide --peak_file parameter"
    }


    BIOMNI_GENOMICS_FIND_ENRICHED_MOTIFS_WITH_HOMER()
}
