#!/usr/bin/env nextflow
/*
 * genomics/check_ensembl_patterns
 * 
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.gene_index = null

process CHECK_ENSEMBL_PATTERNS {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("check_ensembl_patterns_results.json"), emit: results
    tuple val(meta), path("check_ensembl_patterns_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_GENE_INDEX="${params.gene_index?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation

import json
import os

def auto_convert(val):
    # Auto-convert string to appropriate type
    if val is None or val == '' or val == 'null':
        return None
    # Try bool
    if isinstance(val, str) and val.lower() in ('true', 'false'):
        return val.lower() == 'true'
    # Try JSON for lists and dicts
    if isinstance(val, str) and val.strip().startswith(('[', '{')):
        try:
            return json.loads(val)
        except json.JSONDecodeError:
            pass
    # Try int
    try:
        if isinstance(val, str) and '.' not in val:
            return int(val)
    except ValueError:
        pass
    # Try float
    try:
        return float(val)
    except ValueError:
        pass
    # Return as string
    return val



def check_ensembl_patterns(**kwargs):
    '''Placeholder for check_ensembl_patterns. Actual implementation requires specific dependencies.
    '''
    return {"function": "check_ensembl_patterns", "status": "placeholder", "args": kwargs,
            "note": "This function requires specific dependencies not available in this context"}

# Execute the function
try:
    result = check_ensembl_patterns(
        gene_index=auto_convert(os.environ.get("PARAM_GENE_INDEX", "")),
    )
    success = True
    error_msg = None
except Exception as e:
    result = None
    success = False
    error_msg = str(e)

# Save results
output_data = {
    "success": success,
    "function": "check_ensembl_patterns",
    "domain": "genomics",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("check_ensembl_patterns_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("check_ensembl_patterns_output.txt", "w") as f:
    f.write("Biomni: Check Ensembl Patterns" + NL)
    f.write("=" * 60 + NL + NL)
    if success:
        if isinstance(result, str):
            f.write(result)
        elif isinstance(result, dict):
            for key, value in result.items():
                f.write(f"{key}: {value}" + NL)
        else:
            f.write(str(result))
    else:
        f.write(f"ERROR: {error_msg}" + NL)

if not success:
    exit(1)
PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version | cut -d' ' -f2)
        biomni_function: "check_ensembl_patterns"
    END_VERSIONS
    """
}

workflow CHECK_ENSEMBL_PATTERNS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    CHECK_ENSEMBL_PATTERNS(ch_input)

    emit:
    results = CHECK_ENSEMBL_PATTERNS.out.results
    output = CHECK_ENSEMBL_PATTERNS.out.output
    versions = CHECK_ENSEMBL_PATTERNS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    CHECK_ENSEMBL_PATTERNS_WORKFLOW(ch_input)

    CHECK_ENSEMBL_PATTERNS_WORKFLOW.out.output.view { "Output: $it" }
}
