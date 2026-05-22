#!/usr/bin/env nextflow
/*
 * glycoengineering/find_n_glycosylation_motifs
 * Scan a protein sequence for N-linked glycosylation sequons (N-X-[S/T]).
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.sequence = null
params.allow_overlap = null

process FIND_N_GLYCOSYLATION_MOTIFS {
    tag "$meta.id"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("find_n_glycosylation_motifs_results.json"), emit: results
    tuple val(meta), path("find_n_glycosylation_motifs_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_SEQUENCE="${params.sequence?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_ALLOW_OVERLAP="${params.allow_overlap?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def find_n_glycosylation_motifs(sequence: str, allow_overlap: bool = False) -> str:
    '''Scan a protein sequence for N-linked glycosylation sequons (N-X-[S/T]).

    Rules
    - Motif: Asn (N) followed by any residue except Proline (P), followed by Serine (S) or Threonine (T)
    - By default, overlapping matches are not reported twice

    Parameters
    - sequence: protein sequence (one-letter amino-acid codes)
    - allow_overlap: if True, allow overlapping motif detection

    Returns
    - Research log string summarizing motif locations and counts
    '''
    seq = (sequence or "").upper()
    results: list[dict] = []

    i = 0
    while i <= len(seq) - 3:
        tri = seq[i : i + 3]
        if tri[0] == "N" and tri[1] != "P" and tri[2] in {"S", "T"}:
            results.append({"position": i + 1, "motif": tri})  # 1-based
            i = i + (1 if allow_overlap else 3)
        else:
            i += 1

    log = ["# N-linked glycosylation sequon scan (N-X-[S/T], X≠P)"]
    log.append(f"Sequence length: {len(seq)}")
    log.append(f"Total sequons found: {len(results)}")
    if results:
        log.append("\\nPositions (1-based):")
        for r in results[:100]:  # print at most 100 entries to keep output manageable
            log.append(f"- {r['position']}: {r['motif']}")
        if len(results) > 100:
            log.append(f"... and {len(results) - 100} more")
    else:
        log.append("No canonical N-linked sequons detected.")
    return "\\n".join(log)

# Execute the function
try:
    result = find_n_glycosylation_motifs(
        sequence=auto_convert(os.environ.get("PARAM_SEQUENCE", "")),
        allow_overlap=auto_convert(os.environ.get("PARAM_ALLOW_OVERLAP", "")),
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
    "function": "find_n_glycosylation_motifs",
    "domain": "glycoengineering",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("find_n_glycosylation_motifs_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("find_n_glycosylation_motifs_output.txt", "w") as f:
    f.write("Biomni: Find N Glycosylation Motifs" + NL)
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
        biomni_function: "find_n_glycosylation_motifs"
    END_VERSIONS
    """
}

workflow FIND_N_GLYCOSYLATION_MOTIFS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    FIND_N_GLYCOSYLATION_MOTIFS(ch_input)

    emit:
    results = FIND_N_GLYCOSYLATION_MOTIFS.out.results
    output = FIND_N_GLYCOSYLATION_MOTIFS.out.output
    versions = FIND_N_GLYCOSYLATION_MOTIFS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    FIND_N_GLYCOSYLATION_MOTIFS_WORKFLOW(ch_input)

    FIND_N_GLYCOSYLATION_MOTIFS_WORKFLOW.out.output.view { "Output: $it" }
}
