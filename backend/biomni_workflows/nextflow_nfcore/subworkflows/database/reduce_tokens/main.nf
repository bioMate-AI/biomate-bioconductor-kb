#!/usr/bin/env nextflow
/*
 * database/reduce_tokens
 * 
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.res_json = null

process REDUCE_TOKENS {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("reduce_tokens_results.json"), emit: results
    tuple val(meta), path("reduce_tokens_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_RES_JSON="${params.res_json?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def reduce_tokens(text, max_tokens=4000, method="truncate"):
    '''Reduce text to fit token limit.
    Args: text: input text, max_tokens: limit, method: truncate/summarize
    '''
    # Rough estimate: 4 chars per token
    max_chars = max_tokens * 4
    if len(text) <= max_chars:
        return {"text": text, "reduced": False, "original_length": len(text)}
    
    if method == "truncate":
        reduced = text[:max_chars] + "..."
    else:
        reduced = text[:max_chars] + "..."
    
    return {"text": reduced, "reduced": True, "original_length": len(text), "new_length": len(reduced)}

# Execute the function
try:
    result = reduce_tokens(
        res_json=auto_convert(os.environ.get("PARAM_RES_JSON", "")),
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
    "function": "reduce_tokens",
    "domain": "database",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("reduce_tokens_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("reduce_tokens_output.txt", "w") as f:
    f.write("Biomni: Reduce Tokens" + NL)
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
        biomni_function: "reduce_tokens"
    END_VERSIONS
    """
}

workflow REDUCE_TOKENS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    REDUCE_TOKENS(ch_input)

    emit:
    results = REDUCE_TOKENS.out.results
    output = REDUCE_TOKENS.out.output
    versions = REDUCE_TOKENS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    REDUCE_TOKENS_WORKFLOW(ch_input)

    REDUCE_TOKENS_WORKFLOW.out.output.view { "Output: $it" }
}
