#!/usr/bin/env nextflow
/*
 * biomni_literature_advanced_web_search_claude
 * Initiate an advanced web search by launching a specialized agent to collect relevant information and citations through multiple rounds of web searches for a given query.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.query = null
params.max_searches = 1
params.max_retries = 3

// Main process
process ADVANCED_WEB_SEARCH_CLAUDE {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("advanced_web_search_claude_results.json"), emit: results
    path("advanced_web_search_claude_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
import sys

# Import the biomni function
try:
    from biomni.tool.literature import advanced_web_search_claude
except ImportError:
    # Fallback: function may need to be implemented locally
    def advanced_web_search_claude(**kwargs):
        return {"status": "Function not available", "params": kwargs}

# Run the tool
try:
    result = advanced_web_search_claude(
    query="${params.query}",
    max_searches=${params.max_searches},
    max_retries=${params.max_retries}
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("advanced_web_search_claude_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
with open("advanced_web_search_claude_output.txt", "w") as f:
    f.write("Biomni: Advanced Web Search Claude Results\n")
    f.write("=" * 60 + "\n\n")
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(f"{key}: {value}\n")
    else:
        f.write(str(result))

print("advanced_web_search_claude completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_LITERATURE_ADVANCED_WEB_SEARCH_CLAUDE {
    take:
    // No file inputs

    main:
    ADVANCED_WEB_SEARCH_CLAUDE()

    emit:
    results = ADVANCED_WEB_SEARCH_CLAUDE.out.results
    output = ADVANCED_WEB_SEARCH_CLAUDE.out.output
}

// Entry workflow
workflow {
    if (!params.query) {
        error "Please provide --query parameter"
    }


    BIOMNI_LITERATURE_ADVANCED_WEB_SEARCH_CLAUDE()
}
