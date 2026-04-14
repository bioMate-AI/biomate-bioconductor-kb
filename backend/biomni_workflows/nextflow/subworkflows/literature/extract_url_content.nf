#!/usr/bin/env nextflow
/*
 * biomni_literature_extract_url_content
 * Extract the text content of a webpage using requests and BeautifulSoup.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.url = null

// Main process
process EXTRACT_URL_CONTENT {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("extract_url_content_results.json"), emit: results
    path("extract_url_content_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.literature import extract_url_content

# Run the tool
try:
    result = extract_url_content(
    url="${params.url}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("extract_url_content_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("extract_url_content_output.txt", "w") as f:
    f.write("Biomni: Extract Url Content Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("extract_url_content completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_LITERATURE_EXTRACT_URL_CONTENT {
    take:
    // No file inputs

    main:
    EXTRACT_URL_CONTENT()

    emit:
    results = EXTRACT_URL_CONTENT.out.results
    output = EXTRACT_URL_CONTENT.out.output
}

// Entry workflow
workflow {
    if (!params.url) {
        error "Please provide --url parameter"
    }


    BIOMNI_LITERATURE_EXTRACT_URL_CONTENT()
}
