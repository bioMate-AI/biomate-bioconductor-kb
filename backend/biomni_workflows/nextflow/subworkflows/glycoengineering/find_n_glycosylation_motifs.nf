#!/usr/bin/env nextflow
/*
 * biomni_glycoengineering_find_n_glycosylation_motifs
 * Scan a protein sequence for N-linked glycosylation sequons (N-X-[S/T]).
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.sequence = null
params.allow_overlap = false

// Main process
process FIND_N_GLYCOSYLATION_MOTIFS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("find_n_glycosylation_motifs_results.json"), emit: results
    path("find_n_glycosylation_motifs_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.glycoengineering import find_n_glycosylation_motifs

# Run the tool
try:
    result = find_n_glycosylation_motifs(
    sequence="${params.sequence}",
    allow_overlap=${params.allow_overlap ? "True" : "False"}
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("find_n_glycosylation_motifs_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("find_n_glycosylation_motifs_output.txt", "w") as f:
    f.write("Biomni: Find N Glycosylation Motifs Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("find_n_glycosylation_motifs completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_GLYCOENGINEERING_FIND_N_GLYCOSYLATION_MOTIFS {
    take:
    // No file inputs

    main:
    FIND_N_GLYCOSYLATION_MOTIFS()

    emit:
    results = FIND_N_GLYCOSYLATION_MOTIFS.out.results
    output = FIND_N_GLYCOSYLATION_MOTIFS.out.output
}

// Entry workflow
workflow {
    if (!params.sequence) {
        error "Please provide --sequence parameter"
    }


    BIOMNI_GLYCOENGINEERING_FIND_N_GLYCOSYLATION_MOTIFS()
}
