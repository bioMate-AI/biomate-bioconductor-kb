#!/usr/bin/env nextflow
/*
 * biophysics/predict_protein_disorder_regions
 * Predicts intrinsically disordered regions (IDRs) in a protein sequence using IUPred2A.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Default test data: Sample protein sequence (partial p53 protein, known to have IDRs)
params.protein_sequence = 'MEEPQSDPSVEPPLSQETFSDLWKLLPENNVLSPLPSQAMDDLMLSPDDIEQWFTEDPGPDEAPRMPEAAPPVAPAPAAPTPAAPAPAPSWPLSSSVPSQKTYQGSYGFRLGFLHSGTAKSVTCTYSPALNKMFCQLAKTCPVQLWVDSTPPPGTRVRAMAIYKQSQHMTEVVRRCPHHERCSDSDGLAPPQHLIRVEGNLRVEYLDDRNTFRHSVVVPYEPPEVGSDCTTIHYNYMCNSSCMGGMNRRPILTIITLEDSSGNLLGRNSFEVRVCACPGRDRRTEEENLRKKGEPHHELPPGSTKRALPNNTSSSPQPKKKPLDGEYFTLQIRGRERFEMFRELNEALELKDAQAGKEPGGSRAHSSHLKSKKGQSTSRHKKLMFKTEGPDSD'
params.threshold = '0.5'
params.output_file = 'disorder_prediction_results.csv'

process PREDICT_PROTEIN_DISORDER_REGIONS {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("predict_protein_disorder_regions_results.json"), emit: results
    tuple val(meta), path("predict_protein_disorder_regions_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_PROTEIN_SEQUENCE="${params.protein_sequence?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_THRESHOLD="${params.threshold?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_FILE="${params.output_file?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def predict_protein_disorder_regions(protein_sequence, threshold=0.5, output_file="disorder_prediction_results.csv"):
    '''Predicts intrinsically disordered regions (IDRs) in a protein sequence using IUPred2A.

    Parameters
    ----------
    protein_sequence : str
        The amino acid sequence of the protein to analyze
    threshold : float, optional
        The disorder score threshold above which a residue is considered disordered (default: 0.5)
    output_file : str, optional
        Filename to save the per-residue disorder scores (default: "disorder_prediction_results.csv")

    Returns
    -------
    str
        A research log summarizing the prediction process and results

    '''
    import csv
    import re

    import requests

    # Clean the input sequence
    protein_sequence = "".join(re.findall(r"[A-Za-z]", protein_sequence))

    # Step 1: Submit the sequence to IUPred2A web server
    url = "https://iupred2a.elte.hu/iupred2a"
    payload = {
        "seq": protein_sequence,
        "iupred2": "long",  # Use IUPred2 long disorder prediction
        "anchor2": "no",  # Don't use ANCHOR2 prediction
    }

    try:
        response = requests.post(url, data=payload)
        response.raise_for_status()
    except requests.exceptions.RequestException as e:
        return f"Error accessing IUPred2A server: {str(e)}"

    # Step 2: Parse the results to extract disorder scores
    result_lines = response.text.split("\\n")
    scores = []

    for line in result_lines:
        if line.startswith("#") or not line.strip():
            continue
        parts = line.split()
        if len(parts) >= 3:
            try:
                position = int(parts[0])
                residue = parts[1]
                score = float(parts[2])
                scores.append((position, residue, score))
            except (ValueError, IndexError):
                continue

    if not scores:
        return "No valid prediction data was returned from the server."

    # Step 3: Identify disordered regions
    disordered_regions = []
    current_region = []

    for pos, _, score in scores:
        if score >= threshold:
            if not current_region:
                current_region = [pos]
            elif pos == current_region[-1] + 1:
                current_region.append(pos)
            else:
                if len(current_region) > 1:
                    disordered_regions.append((current_region[0], current_region[-1]))
                current_region = [pos]
        elif current_region and len(current_region) > 1:
            disordered_regions.append((current_region[0], current_region[-1]))
            current_region = []
        elif current_region:
            current_region = []

    # Add the last region if it exists
    if current_region and len(current_region) > 1:
        disordered_regions.append((current_region[0], current_region[-1]))

    # Step 4: Save results to CSV
    with open(output_file, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["Position", "Amino_Acid", "Disorder_Score", "Is_Disordered"])
        for pos, aa, score in scores:
            is_disordered = "Yes" if score >= threshold else "No"
            writer.writerow([pos, aa, score, is_disordered])

    # Step 5: Generate the research log
    total_residues = len(scores)
    disordered_count = sum(1 for _, _, score in scores if score >= threshold)
    disordered_percentage = (disordered_count / total_residues) * 100 if total_residues > 0 else 0

    log = f'''
Intrinsically Disordered Region (IDR) Prediction Research Log:
=============================================================
Analysis performed using IUPred2A algorithm (long disorder mode)
Protein sequence length: {total_residues} amino acids
Disorder threshold: {threshold}

Results Summary:
- {disordered_count} residues ({disordered_percentage:.2f}%) predicted as disordered
- {len(disordered_regions)} distinct disordered regions identified

Disordered Regions:
'''

    if disordered_regions:
        for start, end in disordered_regions:
            length = end - start + 1
            log += f"- Region {start}-{end} (length: {length} residues)\\n"
    else:
        log += "- No significant disordered regions found\\n"

    log += f"\\nDetailed per-residue scores saved to: {output_file}"

    return log

# Execute the function
try:
    result = predict_protein_disorder_regions(
        protein_sequence=auto_convert(os.environ.get("PARAM_PROTEIN_SEQUENCE", "")),
        threshold=auto_convert(os.environ.get("PARAM_THRESHOLD", "0.5")),
        output_file=auto_convert(os.environ.get("PARAM_OUTPUT_FILE", "disorder_prediction_results.csv")),
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
    "function": "predict_protein_disorder_regions",
    "domain": "biophysics",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("predict_protein_disorder_regions_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("predict_protein_disorder_regions_output.txt", "w") as f:
    f.write("Biomni: Predict Protein Disorder Regions" + NL)
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
        biomni_function: "predict_protein_disorder_regions"
    END_VERSIONS
    """
}

workflow PREDICT_PROTEIN_DISORDER_REGIONS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    PREDICT_PROTEIN_DISORDER_REGIONS(ch_input)

    emit:
    results = PREDICT_PROTEIN_DISORDER_REGIONS.out.results
    output = PREDICT_PROTEIN_DISORDER_REGIONS.out.output
    versions = PREDICT_PROTEIN_DISORDER_REGIONS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    PREDICT_PROTEIN_DISORDER_REGIONS_WORKFLOW(ch_input)

    PREDICT_PROTEIN_DISORDER_REGIONS_WORKFLOW.out.output.view { "Output: $it" }
}
