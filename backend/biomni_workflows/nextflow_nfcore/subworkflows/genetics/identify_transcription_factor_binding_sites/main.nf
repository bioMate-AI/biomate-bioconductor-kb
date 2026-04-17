#!/usr/bin/env nextflow
/*
 * genetics/identify_transcription_factor_binding_sites
 * Identifies binding sites for a specific transcription factor in a genomic sequence.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: Searching for p53 (TP53) binding sites in a BRCA1 promoter region sequence
params.sequence = 'ATGCTAGCTAGCTAGCTAGCATGCTAGCTAGCTAGCTAGATGCTAGCTAGCTAGCTAGCATGCTAGCTAGCTAGCTAGATGCTAGCTAGCTAGCTAGCATGCTAGCTAGCTAGCTAGATGCTAGCTAGCTAGCTAGCATGCTAGCTAGCTAGCTAG'
params.tf_name = 'p53'
params.threshold = '0.7'
params.output_file = 'tf_binding_sites.txt'

process IDENTIFY_TRANSCRIPTION_FACTOR_BINDING_SITES {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("identify_transcription_factor_binding_sites_results.json"), emit: results
    tuple val(meta), path("identify_transcription_factor_binding_sites_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_SEQUENCE="${params.sequence?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_TF_NAME="${params.tf_name?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_THRESHOLD="${params.threshold?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_FILE="${params.output_file?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
from datetime import datetime
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



def identify_transcription_factor_binding_sites(sequence, tf_name, threshold=0.8, output_file=None):
    '''Identifies binding sites for a specific transcription factor in a genomic sequence.

    Parameters
    ----------
    sequence : str
        The genomic DNA sequence to analyze
    tf_name : str
        Name of the transcription factor to search for (e.g., 'Hsf1', 'GATA1')
    threshold : float, optional
        Minimum score threshold for reporting binding sites (0.0-1.0, default: 0.8)
    output_file : str, optional
        Path to save the results (default: None, results only in log)

    Returns
    -------
    str
        Research log detailing the binding site identification process and results

    '''
    import datetime
    import io

    import requests
    from Bio import motifs
    from Bio.Seq import Seq

    log = f"# Transcription Factor Binding Site Analysis: {tf_name}\\n"
    log += f"Date: {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\\n\\n"

    # Step 1: Get the PWM for the transcription factor from JASPAR database
    log += "## Step 1: Retrieving transcription factor PWM\\n"

    try:
        # Search for the TF in JASPAR database
        jaspar_url = f"https://jaspar.genereg.net/api/v1/matrix/?name={tf_name}"
        response = requests.get(jaspar_url)
        tf_data = response.json()

        if not tf_data["results"] or len(tf_data["results"]) == 0:
            log += f"No PWM found for {tf_name} in JASPAR database.\\n"
            return log

        # Get the first match's ID
        matrix_id = tf_data["results"][0]["matrix_id"]
        log += f"Found PWM with ID: {matrix_id}\\n"

        # Retrieve the PWM
        pwm_url = f"https://jaspar.genereg.net/api/v1/matrix/{matrix_id}.pfm"
        pwm_response = requests.get(pwm_url)

        # Parse the PWM
        handle = io.StringIO(pwm_response.text)
        motif = motifs.read(handle, "jaspar")
        log += f"Successfully retrieved PWM for {tf_name}\\n"

        # Calculate position-specific scoring matrix (PSSM)
        pssm = motif.pssm

        # Step 2: Scan the sequence for binding sites
        log += "\\n## Step 2: Scanning sequence for binding sites\\n"
        log += f"Sequence length: {len(sequence)} bp\\n"
        log += f"Using score threshold: {threshold}\\n\\n"

        # Find binding sites
        binding_sites = []
        max_score = pssm.max
        min_score = pssm.min

        for position, score in pssm.search(Seq(sequence), threshold=threshold):
            relative_score = (score - min_score) / (max_score - min_score)
            if position >= 0:
                strand = "+"
                site_seq = sequence[position : position + len(pssm)]
            else:
                strand = "-"
                site_seq = sequence[len(sequence) + position - len(pssm) : len(sequence) + position]

            binding_sites.append(
                {
                    "position": abs(position),
                    "strand": strand,
                    "score": score,
                    "relative_score": relative_score,
                    "sequence": site_seq,
                }
            )

        # Step 3: Summarize results
        log += f"## Step 3: Results - Found {len(binding_sites)} potential binding sites\\n\\n"

        if binding_sites:
            # Sort by position
            binding_sites.sort(key=lambda x: x["position"])

            # Create a table of results
            log += "| Position | Strand | Sequence | Score | Relative Score |\\n"
            log += "|----------|--------|----------|-------|---------------|\\n"

            for site in binding_sites:
                log += f"| {site['position']} | {site['strand']} | {site['sequence']} | {site['score']:.2f} | {site['relative_score']:.2f} |\\n"
        else:
            log += "No binding sites found meeting the threshold criteria.\\n"

        # Save results to file if specified
        if output_file:
            with open(output_file, "w") as f:
                f.write(f"# {tf_name} binding sites in sequence\\n")
                f.write("Position\\tStrand\\tSequence\\tScore\\tRelative Score\\n")

                for site in binding_sites:
                    f.write(
                        f"{site['position']}\\t{site['strand']}\\t{site['sequence']}\\t{site['score']:.2f}\\t{site['relative_score']:.2f}\\n"
                    )

            log += f"\\nResults saved to file: {output_file}\\n"

    except Exception as e:
        log += f"\\n## Error occurred during analysis: {str(e)}\\n"

    log += "\\n## Analysis complete\\n"
    return log

# Execute the function
try:
    result = identify_transcription_factor_binding_sites(
        sequence=auto_convert(os.environ.get("PARAM_SEQUENCE", "")),
        tf_name=auto_convert(os.environ.get("PARAM_TF_NAME", "")),
        threshold=auto_convert(os.environ.get("PARAM_THRESHOLD", "0.8")),
        output_file=auto_convert(os.environ.get("PARAM_OUTPUT_FILE", "")),
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
    "function": "identify_transcription_factor_binding_sites",
    "domain": "genetics",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("identify_transcription_factor_binding_sites_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("identify_transcription_factor_binding_sites_output.txt", "w") as f:
    f.write("Biomni: Identify Transcription Factor Binding Sites" + NL)
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
        biomni_function: "identify_transcription_factor_binding_sites"
    END_VERSIONS
    """
}

workflow IDENTIFY_TRANSCRIPTION_FACTOR_BINDING_SITES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    IDENTIFY_TRANSCRIPTION_FACTOR_BINDING_SITES(ch_input)

    emit:
    results = IDENTIFY_TRANSCRIPTION_FACTOR_BINDING_SITES.out.results
    output = IDENTIFY_TRANSCRIPTION_FACTOR_BINDING_SITES.out.output
    versions = IDENTIFY_TRANSCRIPTION_FACTOR_BINDING_SITES.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    IDENTIFY_TRANSCRIPTION_FACTOR_BINDING_SITES_WORKFLOW(ch_input)

    IDENTIFY_TRANSCRIPTION_FACTOR_BINDING_SITES_WORKFLOW.out.output.view { "Output: $it" }
}
