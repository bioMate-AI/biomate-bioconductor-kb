#!/usr/bin/env nextflow
/*
 * database/get_hpo_names
 * Retrieve the names of given HPO terms.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.hpo_terms = null
params.data_lake_path = null

process GET_HPO_NAMES {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("get_hpo_names_results.json"), emit: results
    tuple val(meta), path("get_hpo_names_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_HPO_TERMS="${params.hpo_terms?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_DATA_LAKE_PATH="${params.data_lake_path?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation

import json
import os

def parse_hpo_obo(obo_file):
    """Parse HPO OBO file."""
    return {}  # Placeholder - needs full implementation

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



def get_hpo_names(hpo_terms: list[str], data_lake_path: str) -> list[str]:
    '''Retrieve the names of given HPO terms.

    Args:
        hpo_terms (List[str]): A list of HPO terms (e.g., ['HP:0001250']).
        data_lake_path (str): Path to the data lake containing hp.obo file.

    Returns:
        List[str]: A list of corresponding HPO term names.

    '''
    hp_dict = parse_hpo_obo(data_lake_path + "/hp.obo")

    hpo_names = []
    for term in hpo_terms:
        name = hp_dict.get(term, f"Unknown term: {term}")
        hpo_names.append(name)
    return hpo_names

# Execute the function
try:
    result = get_hpo_names(
        hpo_terms=auto_convert(os.environ.get("PARAM_HPO_TERMS", "")),
        data_lake_path=auto_convert(os.environ.get("PARAM_DATA_LAKE_PATH", "")),
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
    "function": "get_hpo_names",
    "domain": "database",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("get_hpo_names_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("get_hpo_names_output.txt", "w") as f:
    f.write("Biomni: Get Hpo Names" + NL)
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
        biomni_function: "get_hpo_names"
    END_VERSIONS
    """
}

workflow GET_HPO_NAMES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    GET_HPO_NAMES(ch_input)

    emit:
    results = GET_HPO_NAMES.out.results
    output = GET_HPO_NAMES.out.output
    versions = GET_HPO_NAMES.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    GET_HPO_NAMES_WORKFLOW(ch_input)

    GET_HPO_NAMES_WORKFLOW.out.output.view { "Output: $it" }
}
