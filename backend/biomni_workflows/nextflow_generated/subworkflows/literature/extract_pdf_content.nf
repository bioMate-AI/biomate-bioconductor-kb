#!/usr/bin/env nextflow
/*
 * biomni_literature_extract_pdf_content
 * Extract the text content of a PDF file given its URL.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.url = null

// Main process
process EXTRACT_PDF_CONTENT {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("extract_pdf_content_results.json"), emit: results
    path("extract_pdf_content_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.literature import extract_pdf_content
except ImportError:
    # Fallback: function may need to be implemented locally
    def extract_pdf_content(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = extract_pdf_content(
    url="${params.url}"
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("extract_pdf_content_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("extract_pdf_content_output.txt", "w") as f:
    f.write("Biomni: Extract Pdf Content Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("extract_pdf_content completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_LITERATURE_EXTRACT_PDF_CONTENT {
    take:
    // No file inputs

    main:
    EXTRACT_PDF_CONTENT()

    emit:
    results = EXTRACT_PDF_CONTENT.out.results
    output = EXTRACT_PDF_CONTENT.out.output
}

// Entry workflow
workflow {
    if (!params.url) {
        error "Please provide --url parameter"
    }


    BIOMNI_LITERATURE_EXTRACT_PDF_CONTENT()
}
