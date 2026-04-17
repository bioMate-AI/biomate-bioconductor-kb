#!/usr/bin/env nextflow
/*
 * molecular_biology/merge_overlapping_regions
 * Merge overlapping regions in the list.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: Merge overlapping genomic regions
params.regions = '[[0, 50], [40, 100], [200, 250], [240, 300]]'

process MERGE_OVERLAPPING_REGIONS {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("merge_overlapping_regions_results.json"), emit: results
    tuple val(meta), path("merge_overlapping_regions_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
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



def merge_overlapping_regions(regions):
    '''Merge overlapping regions.
    Args: regions: list of (start, end) tuples or JSON string
    '''
    if isinstance(regions, str):
        regions = json.loads(regions)
    if not regions:
        return {"merged": [], "count": 0}
    
    sorted_regions = sorted(regions, key=lambda x: x[0])
    merged = [sorted_regions[0]]
    
    for start, end in sorted_regions[1:]:
        if start <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(merged[-1][1], end))
        else:
            merged.append((start, end))
    
    return {"merged": merged, "count": len(merged), "original_count": len(regions)}

# Execute the function
try:
    result = merge_overlapping_regions(
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
    "function": "merge_overlapping_regions",
    "domain": "molecular_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("merge_overlapping_regions_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("merge_overlapping_regions_output.txt", "w") as f:
    f.write("Biomni: Merge Overlapping Regions" + NL)
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
        biomni_function: "merge_overlapping_regions"
    END_VERSIONS
    """
}

workflow MERGE_OVERLAPPING_REGIONS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    MERGE_OVERLAPPING_REGIONS(ch_input)

    emit:
    results = MERGE_OVERLAPPING_REGIONS.out.results
    output = MERGE_OVERLAPPING_REGIONS.out.output
    versions = MERGE_OVERLAPPING_REGIONS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    MERGE_OVERLAPPING_REGIONS_WORKFLOW(ch_input)

    MERGE_OVERLAPPING_REGIONS_WORKFLOW.out.output.view { "Output: $it" }
}
