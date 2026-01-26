#!/usr/bin/env nextflow
/*
 * molecular_biology/is_region_fully_covered
 * Check if the target region is fully covered.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.query_start = null
params.query_end = null
params.regions = null

process IS_REGION_FULLY_COVERED {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("is_region_fully_covered_results.json"), emit: results
    tuple val(meta), path("is_region_fully_covered_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
        # Export parameters as environment variables
    export PARAM_QUERY_START="${params.query_start?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_QUERY_END="${params.query_end?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_REGIONS="${params.regions?.toString()?.replace('"', '\\"') ?: 'null'}"


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



def is_region_fully_covered(query_start, query_end, regions):
    '''Check if query region is fully covered by other regions.
    Args: query_start, query_end, regions: list of (start, end)
    '''
    if isinstance(regions, str):
        regions = json.loads(regions)
    # Merge regions first
    sorted_regions = sorted(regions, key=lambda x: x[0])
    merged = [list(sorted_regions[0])]
    for start, end in sorted_regions[1:]:
        if start <= merged[-1][1]:
            merged[-1][1] = max(merged[-1][1], end)
        else:
            merged.append([start, end])
    
    for start, end in merged:
        if start <= query_start and end >= query_end:
            return {"fully_covered": True, "query": [query_start, query_end]}
    return {"fully_covered": False, "query": [query_start, query_end]}

# Execute the function
try:
    result = is_region_fully_covered(
        query_start=auto_convert(os.environ.get("PARAM_QUERY_START", "")),
        query_end=auto_convert(os.environ.get("PARAM_QUERY_END", "")),
        regions=auto_convert(os.environ.get("PARAM_REGIONS", "")),
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
    "function": "is_region_fully_covered",
    "domain": "molecular_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("is_region_fully_covered_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("is_region_fully_covered_output.txt", "w") as f:
    f.write("Biomni: Is Region Fully Covered" + NL)
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
        biomni_function: "is_region_fully_covered"
    END_VERSIONS
    """
}

workflow IS_REGION_FULLY_COVERED_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    IS_REGION_FULLY_COVERED(ch_input)

    emit:
    results = IS_REGION_FULLY_COVERED.out.results
    output = IS_REGION_FULLY_COVERED.out.output
    versions = IS_REGION_FULLY_COVERED.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    IS_REGION_FULLY_COVERED_WORKFLOW(ch_input)

    IS_REGION_FULLY_COVERED_WORKFLOW.out.output.view { "Output: $it" }
}
