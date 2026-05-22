#!/usr/bin/env nextflow
/*
 * pharmacology/apply_vcog_grade
 * Apply VCOG-CTCAE grading criteria to an adverse event.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: Anemia grading in veterinary patient (VCOG-CTCAE criteria)
params.event_type = 'anemia'
params.symptom = null  // alias for event_type
params.severity_value = '8.5'
params.species = 'canine'

process APPLY_VCOG_GRADE {
    tag "$meta.id"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("apply_vcog_grade_results.json"), emit: results
    tuple val(meta), path("apply_vcog_grade_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
        # Export parameters as environment variables
    export PARAM_EVENT_TYPE="${(params.symptom != null ? params.symptom : params.event_type)?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_SEVERITY_VALUE="${params.severity_value?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_SPECIES="${params.species?.toString()?.replace('"', '\\"') ?: 'null'}"


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



def apply_vcog_grade(event_type, severity_value, species="canine"):
    '''Apply VCOG grading criteria.
    Args: event_type: type of adverse event, severity_value: numeric severity, species
    '''
    # Simplified grading
    if severity_value < 1:
        grade = 1
    elif severity_value < 2:
        grade = 2
    elif severity_value < 3:
        grade = 3
    elif severity_value < 4:
        grade = 4
    else:
        grade = 5
    return {"event_type": event_type, "severity": severity_value, "vcog_grade": grade, "species": species}

# Execute the function
try:
    result = apply_vcog_grade(
        event_type=auto_convert(os.environ.get("PARAM_EVENT_TYPE", "")),
        severity_value=auto_convert(os.environ.get("PARAM_SEVERITY_VALUE", "")),
        species=auto_convert(os.environ.get("PARAM_SPECIES", "")),
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
    "function": "apply_vcog_grade",
    "domain": "pharmacology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("apply_vcog_grade_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("apply_vcog_grade_output.txt", "w") as f:
    f.write("Biomni: Apply Vcog Grade" + NL)
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
        biomni_function: "apply_vcog_grade"
    END_VERSIONS
    """
}

workflow APPLY_VCOG_GRADE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    APPLY_VCOG_GRADE(ch_input)

    emit:
    results = APPLY_VCOG_GRADE.out.results
    output = APPLY_VCOG_GRADE.out.output
    versions = APPLY_VCOG_GRADE.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    APPLY_VCOG_GRADE_WORKFLOW(ch_input)

    APPLY_VCOG_GRADE_WORKFLOW.out.output.view { "Output: $it" }
}
