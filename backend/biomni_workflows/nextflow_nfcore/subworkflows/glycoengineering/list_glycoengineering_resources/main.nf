#!/usr/bin/env nextflow
/*
 * glycoengineering/list_glycoengineering_resources
 * Curate and summarize external glycoengineering tools and resources.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// No value parameters

process LIST_GLYCOENGINEERING_RESOURCES {
    tag { meta.id }
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("list_glycoengineering_resources_results.json"), emit: results
    tuple val(meta), path("list_glycoengineering_resources_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    # No value parameters

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



def list_glycoengineering_resources() -> str:
    '''Curate and summarize external glycoengineering tools and resources.

    Includes links referenced in issue #198 and brief usage notes.
    Returns a research-log style summary with URLs for further use.
    '''
    lines = ["# Glycoengineering tools and resources (curated)"]
    lines.append("")
    lines.append("1) Glycoshield-md")
    lines.append("   - MD workflows for glycan shielding analysis around proteins.")
    lines.append("   - URL: https://gitlab.mpcdf.mpg.de/dioscuri-biophysics/glycoshield-md/")
    lines.append("")
    lines.append("2) SweetTalk")
    lines.append("   - Language-model based framework applied to glycomics/glycoproteomics tasks.")
    lines.append("   - Search on GitHub for installation and examples (various forks exist).")
    lines.append("")
    lines.append("3) N-Glycosylation Markov Models")
    lines.append("   - Probabilistic modeling of N-glycan biosynthesis/patterns.")
    lines.append("   - Search GitHub for ‘N-Glycosylation-Markov-Models’ implementations.")
    lines.append("")
    lines.append("4) Copenhagen Center for Glycomics (CCG)")
    lines.append("   - Consortium hosting many glyco-related datasets, tools, and protocols.")
    lines.append("   - URL: https://github.com/CopenhagenCenterForGlycomics")
    lines.append("")
    lines.append("5) NetOGlyc 4.0 (O-glycosite predictor)")
    lines.append("   - Web service for O-GalNAc site prediction; check license/usage terms.")
    lines.append("   - URL: https://services.healthtech.dtu.dk/services/NetOGlyc-4.0/")
    lines.append("")
    lines.append("Notes:")
    lines.append("- Many tools are heavy and best run via their own environments or containers.")
    lines.append("- For tight Biomni integration, consider adding MCP wrappers or CLI installers.")
    return "\\n".join(lines)

# Execute the function
try:
    result = list_glycoengineering_resources(

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
    "function": "list_glycoengineering_resources",
    "domain": "glycoengineering",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("list_glycoengineering_resources_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("list_glycoengineering_resources_output.txt", "w") as f:
    f.write("Biomni: List Glycoengineering Resources" + NL)
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
        biomni_function: "list_glycoengineering_resources"
    END_VERSIONS
    """
}

workflow LIST_GLYCOENGINEERING_RESOURCES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    LIST_GLYCOENGINEERING_RESOURCES(ch_input)

    emit:
    results = LIST_GLYCOENGINEERING_RESOURCES.out.results
    output = LIST_GLYCOENGINEERING_RESOURCES.out.output
    versions = LIST_GLYCOENGINEERING_RESOURCES.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    LIST_GLYCOENGINEERING_RESOURCES_WORKFLOW(ch_input)

    LIST_GLYCOENGINEERING_RESOURCES_WORKFLOW.out.output.view { "Output: $it" }
}
