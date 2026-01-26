#!/usr/bin/env nextflow
/*
 * systems_biology/query_chatnt
 * Call ChatNT to answer a question about a DNA sequence.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.question = null
params.sequence = null
params.device = null

process QUERY_CHATNT {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("query_chatnt_results.json"), emit: results
    tuple val(meta), path("query_chatnt_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_QUESTION="${params.question?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_SEQUENCE="${params.sequence?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_DEVICE="${params.device?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def query_chatnt(question, sequence, device=-1):
    '''
    Call ChatNT to answer a question about a DNA sequence.

    Parameters:
    -----------
    question : str
        Question to ask about the DNA sequence
    sequence : str
        DNA sequence to analyze
    device : int, optional
        Device to use for the ChatNT model. Default is -1 (CPU).

    Returns:
    --------
    str
        Answer to the question
    '''
    from transformers import pipeline

    pipe = pipeline(model="InstaDeepAI/ChatNT", trust_remote_code=True, device=device)

    # Define custom inputs (note that the number of <DNA> token in the english sequence must be equal to len(dna_sequences))
    english_sequence = f"{question} <DNA> ?"
    dna_sequences = [sequence]

    # Generate sequence
    generated_english_sequence = pipe(inputs={"english_sequence": english_sequence, "dna_sequences": dna_sequences})

    return generated_english_sequence

# Execute the function
try:
    result = query_chatnt(
        question=auto_convert(os.environ.get("PARAM_QUESTION", "")),
        sequence=auto_convert(os.environ.get("PARAM_SEQUENCE", "")),
        device=auto_convert(os.environ.get("PARAM_DEVICE", "")),
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
    "function": "query_chatnt",
    "domain": "systems_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("query_chatnt_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("query_chatnt_output.txt", "w") as f:
    f.write("Biomni: Query Chatnt" + NL)
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
        biomni_function: "query_chatnt"
    END_VERSIONS
    """
}

workflow QUERY_CHATNT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    QUERY_CHATNT(ch_input)

    emit:
    results = QUERY_CHATNT.out.results
    output = QUERY_CHATNT.out.output
    versions = QUERY_CHATNT.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    QUERY_CHATNT_WORKFLOW(ch_input)

    QUERY_CHATNT_WORKFLOW.out.output.view { "Output: $it" }
}
