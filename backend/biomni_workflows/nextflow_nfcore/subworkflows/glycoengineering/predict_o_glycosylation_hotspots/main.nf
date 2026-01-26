#!/usr/bin/env nextflow
/*
 * glycoengineering/predict_o_glycosylation_hotspots
 * Heuristic O-glycosylation hotspot scoring.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.sequence = null
params.window = 7
params.min_st_fraction = 0.4
params.disallow_proline_next = null

process PREDICT_O_GLYCOSYLATION_HOTSPOTS {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("predict_o_glycosylation_hotspots_results.json"), emit: results
    tuple val(meta), path("predict_o_glycosylation_hotspots_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_SEQUENCE="${params.sequence?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_WINDOW="${params.window?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MIN_ST_FRACTION="${params.min_st_fraction?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_DISALLOW_PROLINE_NEXT="${params.disallow_proline_next?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def predict_o_glycosylation_hotspots(
    sequence: str,
    window: int = 7,
    min_st_fraction: float = 0.4,
    disallow_proline_next: bool = True,
) -> str:
    '''Heuristic O-glycosylation hotspot scoring.

    Background
    - O-GalNAc glycosylation frequently occurs on Ser/Thr-rich segments.
    - This lightweight heuristic flags residues in local windows enriched for S/T.
    - Not a substitute for NetOGlyc; provided as a fast, dependency-free baseline.

    Parameters
    - sequence: protein sequence (one-letter AA codes)
    - window: odd window size for local S/T density (default 7)
    - min_st_fraction: minimum S/T fraction in window to flag sites (0..1)
    - disallow_proline_next: if True, avoid flagging S/T immediately followed by Proline

    Returns
    - Research log string with candidate sites and scores
    '''
    if window < 3 or window % 2 == 0:
        window = 7
    seq = (sequence or "").upper()
    half = window // 2

    candidates: list[dict] = []
    for i, aa in enumerate(seq):
        if aa not in {"S", "T"}:
            continue
        start = max(0, i - half)
        end = min(len(seq), i + half + 1)
        segment = seq[start:end]
        st_count = sum(1 for c in segment if c in {"S", "T"})
        frac = st_count / max(1, len(segment))
        if disallow_proline_next and i + 1 < len(seq) and seq[i + 1] == "P":
            continue
        if frac >= min_st_fraction:
            candidates.append(
                {
                    "position": i + 1,
                    "residue": aa,
                    "st_fraction": round(frac, 3),
                    "window": f"{start + 1}-{end}",
                }
            )

    log = ["# Heuristic O-glycosylation hotspot prediction (S/T density based)"]
    log.append(f"Sequence length: {len(seq)} | window={window} | threshold={min_st_fraction}")
    log.append(f"Total candidate sites: {len(candidates)}")
    if candidates:
        log.append("\\nTop candidates:")
        for c in candidates[:100]:
            log.append(
                f"- pos {c['position']} ({c['residue']}): S/T fraction={c['st_fraction']} in window {c['window']}"
            )
        if len(candidates) > 100:
            log.append(f"... and {len(candidates) - 100} more")
    else:
        log.append("No candidate O-glycosylation hotspots met the heuristic threshold.")

    log.append("\\nNote: For state-of-the-art O-glycosite prediction, use NetOGlyc 4.0 (web service).")
    return "\\n".join(log)

# Execute the function
try:
    result = predict_o_glycosylation_hotspots(
        sequence=auto_convert(os.environ.get("PARAM_SEQUENCE", "")),
        window=auto_convert(os.environ.get("PARAM_WINDOW", "7")),
        min_st_fraction=auto_convert(os.environ.get("PARAM_MIN_ST_FRACTION", "0.4")),
        disallow_proline_next=auto_convert(os.environ.get("PARAM_DISALLOW_PROLINE_NEXT", "")),
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
    "function": "predict_o_glycosylation_hotspots",
    "domain": "glycoengineering",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("predict_o_glycosylation_hotspots_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("predict_o_glycosylation_hotspots_output.txt", "w") as f:
    f.write("Biomni: Predict O Glycosylation Hotspots" + NL)
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
        biomni_function: "predict_o_glycosylation_hotspots"
    END_VERSIONS
    """
}

workflow PREDICT_O_GLYCOSYLATION_HOTSPOTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    PREDICT_O_GLYCOSYLATION_HOTSPOTS(ch_input)

    emit:
    results = PREDICT_O_GLYCOSYLATION_HOTSPOTS.out.results
    output = PREDICT_O_GLYCOSYLATION_HOTSPOTS.out.output
    versions = PREDICT_O_GLYCOSYLATION_HOTSPOTS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    PREDICT_O_GLYCOSYLATION_HOTSPOTS_WORKFLOW(ch_input)

    PREDICT_O_GLYCOSYLATION_HOTSPOTS_WORKFLOW.out.output.view { "Output: $it" }
}
