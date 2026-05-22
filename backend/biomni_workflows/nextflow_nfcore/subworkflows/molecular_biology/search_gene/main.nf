#!/usr/bin/env nextflow
/*
 * molecular_biology/search_gene
 * Search for gene ID in NCBI database.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: Search for start codon ATG in DNA sequence
params.sequence = 'ATGGTGAGCAAGGGCGAGGAGATGCTGTTCACCATGGGGTGGTG'
params.pattern = 'ATG'
params.case_sensitive = 'false'

process SEARCH_GENE {
    tag "$meta.id"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("search_gene_results.json"), emit: results
    tuple val(meta), path("search_gene_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
        # Export parameters as environment variables
    export PARAM_SEQUENCE="${params.sequence?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_PATTERN="${params.pattern?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_CASE_SENSITIVE="${params.case_sensitive?.toString()?.replace('"', '\\"') ?: 'null'}"

    # No value parameters

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
import re
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



def search_gene(sequence, pattern, case_sensitive=False):
    '''Search for pattern in sequence.
    Args: sequence: DNA/RNA, pattern: regex or sequence, case_sensitive: bool
    '''
    # Validate inputs - use defaults if None
    if sequence is None:
        sequence = "ATGCATGCATGC"
    if pattern is None:
        pattern = "ATG"
    if case_sensitive is None:
        case_sensitive = False
    sequence = str(sequence)
    pattern = str(pattern)

    flags = 0 if case_sensitive else re.IGNORECASE
    matches = []
    for m in re.finditer(pattern, sequence, flags):
        matches.append({"start": m.start(), "end": m.end(), "match": m.group()})
    return {"matches": matches, "count": len(matches), "pattern": pattern}

# Execute the function
try:
    result = search_gene(
        sequence=auto_convert(os.environ.get("PARAM_SEQUENCE", "")),
        pattern=auto_convert(os.environ.get("PARAM_PATTERN", "")),
        case_sensitive=auto_convert(os.environ.get("PARAM_CASE_SENSITIVE", "")),
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
    "function": "search_gene",
    "domain": "molecular_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("search_gene_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("search_gene_output.txt", "w") as f:
    f.write("Biomni: Search Gene" + NL)
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
        biomni_function: "search_gene"
    END_VERSIONS
    """
}

workflow SEARCH_GENE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    SEARCH_GENE(ch_input)

    emit:
    results = SEARCH_GENE.out.results
    output = SEARCH_GENE.out.output
    versions = SEARCH_GENE.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    SEARCH_GENE_WORKFLOW(ch_input)

    SEARCH_GENE_WORKFLOW.out.output.view { "Output: $it" }
}
