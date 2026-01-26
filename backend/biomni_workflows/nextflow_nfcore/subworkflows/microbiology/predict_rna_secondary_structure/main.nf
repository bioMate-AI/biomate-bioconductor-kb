#!/usr/bin/env nextflow
/*
 * microbiology/predict_rna_secondary_structure
 * Predict the secondary structure of an RNA molecule using ViennaRNA.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.rna_sequence = null
params.output_prefix = 'rna_structure'

process PREDICT_RNA_SECONDARY_STRUCTURE {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("predict_rna_secondary_structure_results.json"), emit: results
    tuple val(meta), path("predict_rna_secondary_structure_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_RNA_SEQUENCE="${params.rna_sequence?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_PREFIX="${params.output_prefix?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def predict_rna_secondary_structure(rna_sequence, output_prefix="rna_structure"):
    '''Predict the secondary structure of an RNA molecule using ViennaRNA.

    Parameters
    ----------
    rna_sequence : str
        The RNA sequence (consisting of A, U, G, C nucleotides)
    output_prefix : str, optional
        Prefix for output files (default: "rna_structure")

    Returns
    -------
    str
        A research log summarizing the prediction process and results

    '''
    try:
        import RNA
    except ImportError:
        return "ERROR: ViennaRNA Python package not installed. Install with 'pip install ViennaRNA'"

    # Validate input sequence
    rna_sequence = rna_sequence.upper().strip()
    valid_nucleotides = set("AUGC")
    if not all(nucleotide in valid_nucleotides for nucleotide in rna_sequence):
        return "ERROR: Invalid RNA sequence. Only A, U, G, C nucleotides are allowed."

    # Predict secondary structure
    (structure, mfe) = RNA.fold(rna_sequence)

    # Save the structure to a file
    structure_file = f"{output_prefix}_structure.txt"
    with open(structure_file, "w") as f:
        f.write(f"Sequence: {rna_sequence}\\n")
        f.write(f"Structure: {structure}\\n")
        f.write(f"Minimum Free Energy: {mfe} kcal/mol\\n")

    # Generate a simple text visualization
    viz_file = f"{output_prefix}_visualization.txt"
    with open(viz_file, "w") as f:
        f.write("Sequence:  " + rna_sequence + "\\n")
        f.write("Structure: " + structure + "\\n\\n")

        # Add a simple representation of stem-loops
        pairs = []
        stack = []
        for i, char in enumerate(structure):
            if char == "(":
                stack.append(i)
            elif char == ")" and stack:
                left = stack.pop()
                pairs.append((left, i))

        f.write("Stem-loop structures:\\n")
        for left, right in sorted(pairs):
            f.write(f"Base pair: {rna_sequence[left]}({left + 1})-{rna_sequence[right]}({right + 1})\\n")

    # Create research log
    log = f'''
RNA Secondary Structure Prediction Log:
---------------------------------------
1. Received RNA sequence of length {len(rna_sequence)}
2. Applied ViennaRNA RNAfold algorithm for structure prediction
3. Calculated minimum free energy: {mfe} kcal/mol
4. Structure saved to file: {structure_file}
5. Visualization saved to file: {viz_file}

Summary:
The RNA sequence forms a secondary structure with a minimum free energy of {mfe} kcal/mol.
The structure contains {structure.count("(")} base pairs forming stems and loops.
See {structure_file} and {viz_file} for detailed structure information.
'''

    return log

# Execute the function
try:
    result = predict_rna_secondary_structure(
        rna_sequence=auto_convert(os.environ.get("PARAM_RNA_SEQUENCE", "")),
        output_prefix=auto_convert(os.environ.get("PARAM_OUTPUT_PREFIX", "rna_structure")),
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
    "function": "predict_rna_secondary_structure",
    "domain": "microbiology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("predict_rna_secondary_structure_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("predict_rna_secondary_structure_output.txt", "w") as f:
    f.write("Biomni: Predict Rna Secondary Structure" + NL)
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
        biomni_function: "predict_rna_secondary_structure"
    END_VERSIONS
    """
}

workflow PREDICT_RNA_SECONDARY_STRUCTURE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    PREDICT_RNA_SECONDARY_STRUCTURE(ch_input)

    emit:
    results = PREDICT_RNA_SECONDARY_STRUCTURE.out.results
    output = PREDICT_RNA_SECONDARY_STRUCTURE.out.output
    versions = PREDICT_RNA_SECONDARY_STRUCTURE.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    PREDICT_RNA_SECONDARY_STRUCTURE_WORKFLOW(ch_input)

    PREDICT_RNA_SECONDARY_STRUCTURE_WORKFLOW.out.output.view { "Output: $it" }
}
