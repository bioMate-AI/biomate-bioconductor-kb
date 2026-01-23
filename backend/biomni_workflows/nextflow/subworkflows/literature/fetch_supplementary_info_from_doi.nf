#!/usr/bin/env nextflow
/*
 * biomni_literature_fetch_supplementary_info_from_doi
 * Fetches supplementary information for a paper given its DOI and returns a research log.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.doi = null
params.output_dir = 'supplementary_info'

// Main process
process FETCH_SUPPLEMENTARY_INFO_FROM_DOI {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("fetch_supplementary_info_from_doi_results.json"), emit: results
    path("fetch_supplementary_info_from_doi_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.literature import fetch_supplementary_info_from_doi

# Run the tool
try:
    result = fetch_supplementary_info_from_doi(
    doi="${params.doi}",
    output_dir="${params.output_dir}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("fetch_supplementary_info_from_doi_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("fetch_supplementary_info_from_doi_output.txt", "w") as f:
    f.write("Biomni: Fetch Supplementary Info From Doi Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("fetch_supplementary_info_from_doi completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_LITERATURE_FETCH_SUPPLEMENTARY_INFO_FROM_DOI {
    take:
    // No file inputs

    main:
    FETCH_SUPPLEMENTARY_INFO_FROM_DOI()

    emit:
    results = FETCH_SUPPLEMENTARY_INFO_FROM_DOI.out.results
    output = FETCH_SUPPLEMENTARY_INFO_FROM_DOI.out.output
}

// Entry workflow
workflow {
    if (!params.doi) {
        error "Please provide --doi parameter"
    }


    BIOMNI_LITERATURE_FETCH_SUPPLEMENTARY_INFO_FROM_DOI()
}
