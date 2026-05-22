#!/usr/bin/env nextflow
/*
 * cancer_biology/norm_chr
 * 
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: chromosome name to normalize (can be chr1, 1, Chr1, chrX, 23, etc.)
params.chrom = 'chr17'
params.x = null  // alias for chrom

process NORM_CHR {
    tag "$meta.id"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomni-lite:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("norm_chr_results.json"), emit: results
    tuple val(meta), path("norm_chr_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
        # Export parameters as environment variables
    export PARAM_CHROM="${(params.x != null ? params.x : params.chrom)?.toString()?.replace('"', '\\"') ?: 'null'}"


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



def norm_chr(chrom):
    '''Normalize chromosome name to standard format.
    Args: chrom: chromosome name (chr1, 1, Chr1, etc.)
    '''
    chrom = str(chrom).strip()
    if chrom.lower().startswith('chr'):
        chrom = chrom[3:]
    # Handle special cases
    chrom = chrom.upper()
    if chrom in ['23', 'X']:
        normalized = 'chrX'
    elif chrom in ['24', 'Y']:
        normalized = 'chrY'
    elif chrom in ['25', 'M', 'MT']:
        normalized = 'chrM'
    else:
        normalized = f'chr{chrom}'
    return {"original": str(chrom), "normalized": normalized}

# Execute the function
try:
    result = norm_chr(
        chrom=auto_convert(os.environ.get("PARAM_CHROM", "")),
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
    "function": "norm_chr",
    "domain": "cancer_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("norm_chr_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("norm_chr_output.txt", "w") as f:
    f.write("Biomni: Norm Chr" + NL)
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
        biomni_function: "norm_chr"
    END_VERSIONS
    """
}

workflow NORM_CHR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    NORM_CHR(ch_input)

    emit:
    results = NORM_CHR.out.results
    output = NORM_CHR.out.output
    versions = NORM_CHR.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    NORM_CHR_WORKFLOW(ch_input)

    NORM_CHR_WORKFLOW.out.output.view { "Output: $it" }
}
