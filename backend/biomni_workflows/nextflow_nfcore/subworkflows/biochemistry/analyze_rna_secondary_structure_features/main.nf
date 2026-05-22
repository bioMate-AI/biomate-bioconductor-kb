#!/usr/bin/env nextflow
/*
 * biochemistry/analyze_rna_secondary_structure_features
 * Calculate numeric values for various structural features of an RNA secondary structure.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.dot_bracket_structure = null
params.sequence = null

process ANALYZE_RNA_SECONDARY_STRUCTURE_FEATURES {
    tag "$meta.id"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("analyze_rna_secondary_structure_features_results.json"), emit: results
    tuple val(meta), path("analyze_rna_secondary_structure_features_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_DOT_BRACKET_STRUCTURE="${params.dot_bracket_structure?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_SEQUENCE="${params.sequence?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def analyze_rna_secondary_structure_features(dot_bracket_structure, sequence=None):
    '''Calculate numeric values for various structural features of an RNA secondary structure.

    Parameters
    ----------
    dot_bracket_structure : str
        RNA secondary structure in dot-bracket notation (e.g., "(((...)))").
        Parentheses represent base pairs, dots represent unpaired bases.
    sequence : str, optional
        The RNA sequence corresponding to the structure. If provided,
        sequence-dependent energy calculations will be performed.

    Returns
    -------
    str
        A research log summarizing the calculated structural features and analysis steps.

    '''
    # Validate inputs - use defaults if None
    if dot_bracket_structure is None:
        dot_bracket_structure = "((((....))))"
    dot_bracket_structure = str(dot_bracket_structure)

    # Initialize research log
    log = "# RNA Secondary Structure Feature Analysis\\n\\n"

    # Validate input
    if not all(c in "().[]{}" for c in dot_bracket_structure):
        return "Error: Invalid dot-bracket notation. Use only '()', '[]', '{}', and '.'"

    log += f"Input structure (length: {len(dot_bracket_structure)}): {dot_bracket_structure}\\n"
    if sequence:
        log += f"Input sequence (length: {len(sequence)}): {sequence}\\n"
        if len(sequence) != len(dot_bracket_structure):
            return "Error: Sequence and structure lengths do not match."

    # Extract base pairs
    pairs = []
    stack = []

    for i, char in enumerate(dot_bracket_structure):
        if char in "([{":
            stack.append((i, char))
        elif char in ")]}":
            if not stack:
                return "Error: Unbalanced structure. More closing than opening brackets."

            j, opening_char = stack.pop()
            # Check for matching bracket types
            if (
                (opening_char == "(" and char != ")")
                or (opening_char == "[" and char != "]")
                or (opening_char == "{" and char != "}")
            ):
                return "Error: Mismatched bracket types. Opening and closing brackets must match."

            pairs.append((j, i))

    if stack:
        return "Error: Unbalanced structure. More opening than closing brackets."

    # Sort pairs by position
    pairs.sort()

    # Identify stems (consecutive base pairs)
    stems = []
    current_stem = []

    for i, (start, end) in enumerate(pairs):
        if (i == 0 or start != pairs[i - 1][0] + 1 or end != pairs[i - 1][1] - 1) and current_stem:
            stems.append(current_stem)
            current_stem = []
        current_stem.append((start, end))

    if current_stem:
        stems.append(current_stem)

    # Calculate stem lengths
    stem_lengths = [len(stem) for stem in stems]

    # Calculate loop sizes
    loops = []
    for i in range(len(stems)):
        stem = stems[i]
        last_pair = stem[-1]
        next_stem_start = stems[i + 1][0][0] if i < len(stems) - 1 else len(dot_bracket_structure)
        loop_size = next_stem_start - last_pair[1] - 1
        if loop_size > 0:
            loops.append(loop_size)

    # Calculate base pair statistics
    total_paired_bases = len(pairs) * 2
    total_unpaired_bases = len(dot_bracket_structure) - total_paired_bases

    # Calculate simplified free energy if sequence is provided
    stem_energies = []
    if sequence and len(stems) > 0:
        # Simplified energy parameters for nearest-neighbor model
        # Values are approximate and simplified for illustration
        energy_params = {
            "AU": -0.9,
            "UA": -0.9,
            "GC": -2.1,
            "CG": -2.1,
            "GU": -0.5,
            "UG": -0.5,
        }

        for stem in stems:
            stem_energy = 0
            for start, end in stem:
                if start < len(sequence) and end < len(sequence):
                    pair = sequence[start] + sequence[end]
                    stem_energy += energy_params.get(pair, 0)
            stem_energies.append(stem_energy)

    # Prepare results
    log += "\\n## Structural Features\\n\\n"
    log += f"Total base pairs: {len(pairs)}\\n"
    log += f"Number of stems: {len(stems)}\\n"
    log += f"Longest stem length: {max(stem_lengths) if stem_lengths else 0}\\n"
    log += f"Average stem length: {sum(stem_lengths) / len(stem_lengths) if stem_lengths else 0:.2f}\\n"
    log += f"Paired bases: {total_paired_bases} ({total_paired_bases / len(dot_bracket_structure) * 100:.1f}%)\\n"
    log += f"Unpaired bases: {total_unpaired_bases} ({total_unpaired_bases / len(dot_bracket_structure) * 100:.1f}%)\\n"

    if loops:
        log += f"Number of loops: {len(loops)}\\n"
        log += f"Average loop size: {sum(loops) / len(loops):.2f}\\n"
        log += f"Largest loop size: {max(loops)}\\n"

    if sequence and stem_energies:
        log += "\\n## Energy Calculations\\n\\n"
        log += f"Total estimated free energy: {sum(stem_energies):.2f} kcal/mol\\n"

        if len(stems) >= 2:
            log += f"Upstream stem free energy: {stem_energies[0]:.2f} kcal/mol\\n"
            log += f"Downstream stem free energy: {stem_energies[-1]:.2f} kcal/mol\\n"

        # If the first stem is the "zipper" stem
        if stem_lengths and stem_lengths[0] >= 3:
            log += f"Zipper stem free energy: {stem_energies[0]:.2f} kcal/mol\\n"

    log += "\\n## Stem Details\\n\\n"
    for i, stem in enumerate(stems):
        log += f"Stem {i + 1}: {len(stem)} base pairs\\n"
        log += f"  Positions: {stem[0][0]}-{stem[0][1]} to {stem[-1][0]}-{stem[-1][1]}\\n"
        if sequence and i < len(stem_energies):
            log += f"  Estimated stability: {stem_energies[i]:.2f} kcal/mol\\n"

    return log

# Execute the function
try:
    result = analyze_rna_secondary_structure_features(
        dot_bracket_structure=auto_convert(os.environ.get("PARAM_DOT_BRACKET_STRUCTURE", "")),
        sequence=auto_convert(os.environ.get("PARAM_SEQUENCE", "")),
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
    "function": "analyze_rna_secondary_structure_features",
    "domain": "biochemistry",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("analyze_rna_secondary_structure_features_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("analyze_rna_secondary_structure_features_output.txt", "w") as f:
    f.write("Biomni: Analyze Rna Secondary Structure Features" + NL)
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
        biomni_function: "analyze_rna_secondary_structure_features"
    END_VERSIONS
    """
}

workflow ANALYZE_RNA_SECONDARY_STRUCTURE_FEATURES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANALYZE_RNA_SECONDARY_STRUCTURE_FEATURES(ch_input)

    emit:
    results = ANALYZE_RNA_SECONDARY_STRUCTURE_FEATURES.out.results
    output = ANALYZE_RNA_SECONDARY_STRUCTURE_FEATURES.out.output
    versions = ANALYZE_RNA_SECONDARY_STRUCTURE_FEATURES.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANALYZE_RNA_SECONDARY_STRUCTURE_FEATURES_WORKFLOW(ch_input)

    ANALYZE_RNA_SECONDARY_STRUCTURE_FEATURES_WORKFLOW.out.output.view { "Output: $it" }
}
