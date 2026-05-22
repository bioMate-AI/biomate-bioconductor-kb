#!/usr/bin/env nextflow
/*
 * genomics/find_enriched_motifs_with_homer
 * Find DNA sequence motifs enriched in genomic regions using the HOMER motif discovery software.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.peak_file = null
params.genome = null
params.background_file = null
params.motif_length = '8,10,12'
params.output_dir = null
params.num_motifs = null
params.threads = null

process FIND_ENRICHED_MOTIFS_WITH_HOMER {
    tag { meta.id }
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("find_enriched_motifs_with_homer_results.json"), emit: results
    tuple val(meta), path("find_enriched_motifs_with_homer_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
        # Export parameters as environment variables
    export PARAM_PEAK_FILE="${params.peak_file?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_GENOME="${params.genome?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_BACKGROUND_FILE="${params.background_file?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MOTIF_LENGTH="${params.motif_length?.toString()?.replace('"', '\\"') ?: '8,10,12'}"
    export PARAM_OUTPUT_DIR="${params.output_dir?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_NUM_MOTIFS="${params.num_motifs?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_THREADS="${params.threads?.toString()?.replace('"', '\\"') ?: 'null'}"


    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
import os
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



def find_enriched_motifs_with_homer(
    peak_file,
    genome="hg38",
    background_file=None,
    motif_length="8,10,12",
    output_dir="./homer_motifs",
    num_motifs=10,
    threads=4,
):
    '''Find DNA sequence motifs enriched in genomic regions using the HOMER motif discovery software.

    Parameters
    ----------
    peak_file : str
        Path to peak file in BED format containing genomic regions to analyze for motif enrichment
    genome : str, optional
        Reference genome for sequence extraction (default: "hg38")
    background_file : str, optional
        Path to BED file with background regions for comparison. If None, HOMER will generate random
        background sequences automatically (default: None)
    motif_length : str, optional
        Comma-separated list of motif lengths to discover (default: "8,10,12")
    output_dir : str, optional
        Directory to save output files (default: "./homer_motifs")
    num_motifs : int, optional
        Number of motifs to find (default: 10)
    threads : int, optional
        Number of CPU threads to use (default: 4)

    Returns
    -------
    str
        A research log summarizing the motif discovery process and results

    '''
    import datetime
    import glob
    import subprocess

    # Handle missing inputs gracefully
    if peak_file is None:
        return "No peak file provided. In production, provide a BED file with genomic regions to analyze for motif enrichment. HOMER would run findMotifsGenome.pl to discover enriched DNA sequence motifs."

    # Create output directory if it doesn't exist
    output_dir = output_dir or "./homer_motifs"
    os.makedirs(output_dir, exist_ok=True)

    # Initialize research log
    log = f"Motif Discovery with HOMER - {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\\n"
    log += "=" * 80 + "\\n\\n"

    # Log input parameters
    log += "Input Parameters:\\n"
    log += f"- Peak file: {peak_file}\\n"
    log += f"- Reference genome: {genome}\\n"
    log += f"- Background: {'User-defined' if background_file else 'HOMER-generated'}\\n"
    log += f"- Motif lengths: {motif_length}\\n"
    log += f"- Number of motifs: {num_motifs}\\n"
    log += f"- Threads: {threads}\\n\\n"

    # Construct HOMER findMotifsGenome.pl command
    homer_cmd = [
        "findMotifsGenome.pl",
        peak_file,
        genome,
        output_dir,
        "-size",
        "200",  # Default search region size (200bp centered on peak)
        "-len",
        motif_length,
        "-S",
        str(num_motifs),
        "-p",
        str(threads),
    ]

    # Add background file if provided
    if background_file:
        homer_cmd.extend(["-bg", background_file])

    log += "Executing HOMER with the following command:\\n"
    log += " ".join(homer_cmd) + "\\n\\n"

    try:
        # Run HOMER
        log += "Running HOMER motif discovery...\\n"
        process = subprocess.run(homer_cmd, capture_output=True, text=True, check=True)

        # Log stdout and stderr (truncate if too long)
        stdout_text = process.stdout
        if len(stdout_text) > 2000:
            stdout_text = stdout_text[:1000] + "\\n...[output truncated]...\\n" + stdout_text[-1000:]

        log += "HOMER Standard Output (truncated if long):\\n"
        log += stdout_text + "\\n"

        # Check and parse results
        log += "\\n## Motif Discovery Results\\n\\n"

        # Look for HTML results file
        html_results = os.path.join(output_dir, "homerResults.html")
        if os.path.exists(html_results):
            log += f"HOMER results saved to {html_results}\\n\\n"

        # Parse motif files
        motif_files = glob.glob(os.path.join(output_dir, "motif*.motif"))
        motif_files.sort()

        if motif_files:
            log += f"Found {len(motif_files)} enriched motifs:\\n\\n"

            # Parse each motif file for information
            for motif_file in motif_files[:5]:  # Show info for top 5 motifs only
                with open(motif_file) as f:
                    header = f.readline().strip()
                    # Extract motif name, p-value, etc. from header
                    # Example header: >ATGCGCTA	MA0139.1(CTCF)/Jaspar	1e-10	-1.234e+02	0	0.00%
                    parts = header.split("\\t")
                    if len(parts) >= 3:
                        motif_id = os.path.basename(motif_file)
                        motif_consensus = parts[0].replace(">", "")

                        # Try to extract transcription factor info if available
                        tf_match = ""
                        if len(parts) > 1:
                            tf_match = parts[1]

                        # Extract p-value if available
                        p_value = ""
                        if len(parts) > 2:
                            p_value = parts[2]

                        log += f"Motif: {motif_id}\\n"
                        log += f"- Consensus: {motif_consensus}\\n"
                        log += f"- Matching TF: {tf_match}\\n"
                        log += f"- P-value: {p_value}\\n\\n"

            if len(motif_files) > 5:
                log += f"... and {len(motif_files) - 5} more motifs ...\\n\\n"
        else:
            log += "No significant motifs were found.\\n\\n"

        # Check for known motif enrichment results
        known_results = os.path.join(output_dir, "knownResults.html")
        if os.path.exists(known_results):
            log += "Known motif enrichment results are available in knownResults.html\\n"

            # Try to parse known motifs results
            known_motifs_txt = os.path.join(output_dir, "knownResults.txt")
            if os.path.exists(known_motifs_txt):
                with open(known_motifs_txt) as f:
                    lines = f.readlines()
                    if len(lines) > 1:  # Header + at least one motif
                        log += "\\nTop known motifs enriched in the dataset:\\n"
                        # Show top 3 known motifs if available
                        for line in lines[1:4]:  # Skip header, show top 3
                            parts = line.strip().split("\\t")
                            if len(parts) >= 4:
                                log += f"- {parts[0]} (p-value: {parts[2]})\\n"

        # Summarize results
        log += "\\n## Summary\\n"
        log += f"- Analyzed genomic regions from {peak_file}\\n"
        log += f"- Discovered {len(motif_files)} enriched motifs\\n"
        log += f"- All results saved to {output_dir}\\n"

    except subprocess.CalledProcessError as e:
        log += "Error during HOMER execution:\\n"
        log += e.stderr + "\\n"
        log += "Motif discovery failed.\\n"
    except Exception as e:
        log += f"An unexpected error occurred: {str(e)}\\n"

    return log

# Execute the function
try:
    result = find_enriched_motifs_with_homer(
        peak_file=auto_convert(os.environ.get("PARAM_PEAK_FILE", "")),
        genome=auto_convert(os.environ.get("PARAM_GENOME", "")),
        background_file=auto_convert(os.environ.get("PARAM_BACKGROUND_FILE", "")),
        motif_length=auto_convert(os.environ.get("PARAM_MOTIF_LENGTH", "8,10,12")),
        output_dir=auto_convert(os.environ.get("PARAM_OUTPUT_DIR", "")),
        num_motifs=auto_convert(os.environ.get("PARAM_NUM_MOTIFS", "")),
        threads=auto_convert(os.environ.get("PARAM_THREADS", "")),
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
    "function": "find_enriched_motifs_with_homer",
    "domain": "genomics",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("find_enriched_motifs_with_homer_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("find_enriched_motifs_with_homer_output.txt", "w") as f:
    f.write("Biomni: Find Enriched Motifs With Homer" + NL)
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
        biomni_function: "find_enriched_motifs_with_homer"
    END_VERSIONS
    """
}

workflow FIND_ENRICHED_MOTIFS_WITH_HOMER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    FIND_ENRICHED_MOTIFS_WITH_HOMER(ch_input)

    emit:
    results = FIND_ENRICHED_MOTIFS_WITH_HOMER.out.results
    output = FIND_ENRICHED_MOTIFS_WITH_HOMER.out.output
    versions = FIND_ENRICHED_MOTIFS_WITH_HOMER.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    FIND_ENRICHED_MOTIFS_WITH_HOMER_WORKFLOW(ch_input)

    FIND_ENRICHED_MOTIFS_WITH_HOMER_WORKFLOW.out.output.view { "Output: $it" }
}
