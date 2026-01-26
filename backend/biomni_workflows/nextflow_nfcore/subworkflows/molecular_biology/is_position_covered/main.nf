#!/usr/bin/env nextflow
/*
 * molecular_biology/is_position_covered
 * Check if a position is covered by any region.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.pos = null
params.covered_regions = null

process IS_POSITION_COVERED {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("is_position_covered_results.json"), emit: results
    tuple val(meta), path("is_position_covered_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_POS="${params.pos?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_COVERED_REGIONS="${params.covered_regions?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
import json
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



def is_position_covered(position, regions):
    '''Check if position falls within any region.
    Args: position: int, regions: list of (start, end) or JSON
    '''
    if isinstance(regions, str):
        regions = json.loads(regions)
    for start, end in regions:
        if start <= position <= end:
            return {"covered": True, "position": position, "covering_region": [start, end]}
    return {"covered": False, "position": position}

# Execute the function
try:
    result = is_position_covered(
        pos=auto_convert(os.environ.get("PARAM_POS", "")),
        covered_regions=auto_convert(os.environ.get("PARAM_COVERED_REGIONS", "")),
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
    "function": "is_position_covered",
    "domain": "molecular_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("is_position_covered_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("is_position_covered_output.txt", "w") as f:
    f.write("Biomni: Is Position Covered" + NL)
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
        biomni_function: "is_position_covered"
    END_VERSIONS
    """
}

workflow IS_POSITION_COVERED_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    IS_POSITION_COVERED(ch_input)

    emit:
    results = IS_POSITION_COVERED.out.results
    output = IS_POSITION_COVERED.out.output
    versions = IS_POSITION_COVERED.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    IS_POSITION_COVERED_WORKFLOW(ch_input)

    IS_POSITION_COVERED_WORKFLOW.out.output.view { "Output: $it" }
}
